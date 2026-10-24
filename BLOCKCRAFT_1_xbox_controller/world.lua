-- ============================================================
-- world.lua - the open world, stored as 16x16x16 CHUNKS.
--
-- Only chunks near the player exist (see chunks.lua, which loads and unloads them).
-- The world is endless sideways (x and y, up to +-LIMIT blocks) and H blocks tall.
--
--   chunk = {cx, cy, cz, key, x0, y0, z0, blocks, fill}
--     blocks : table of 4096 block ids, or nil when the whole chunk is one block
--     fill   : that single block id (0 = all air, 3 = all stone)   [used when blocks == nil]
--   index of a block inside a chunk:  lx + ly*16 + lz*256 + 1   (lx,ly,lz are 0..15)
--
--   W.edits  = every block a player/mod changed:  chunk key -> {index -> id}
--              They are remembered even after a chunk is unloaded and are re-applied when
--              the chunk is generated again. The server stores the same thing.
--   W.dirty  = chunks whose mesh must be rebuilt (mesher.lua works through them)
--
-- Unloaded chunks: get() says air, solid() says solid (so the player cannot fall
-- through ground that has not been generated yet).
-- ============================================================
local W = {CS = 16, CZ = 4}
W.H = W.CS * W.CZ        -- build height in blocks (64)
W.LIMIT = 1000000        -- the world ends this far from the middle (must match protocol.lua)
W.chunks = {}            -- key -> chunk
W.dirty = {}             -- key -> chunk
W.edits = {}             -- key -> {index -> id}
W.count = 0              -- number of loaded chunks
W.version = 0            -- goes up with every recorded block change (save.lua uses it to skip saving when nothing changed)
W.generating = nil       -- the chunk record being generated (mods may decorate it)

local CS, CZ, H = W.CS, W.CZ, W.H
local CS2 = CS * CS
local SPAN, OFF = 2097152, 1048576   -- keys stay below 2^53, so they are exact
local floor, abs = math.floor, math.abs

function W.key(cx, cy, cz) return (cz * SPAN + (cy + OFF)) * SPAN + (cx + OFF) end

-- the opposite of key(): chunk key -> cx, cy, cz
function W.unkey(key)
  local cxo = key % SPAN
  local rest = (key - cxo) / SPAN
  local cyo = rest % SPAN
  return cxo - OFF, cyo - OFF, (rest - cyo) / SPAN
end

function W.getChunk(cx, cy, cz) return W.chunks[W.key(cx, cy, cz)] end

function W.inBounds(x, y, z)
  return z >= 0 and z < H and abs(x) <= W.LIMIT and abs(y) <= W.LIMIT
end

function W.get(x, y, z)
  if z < 0 or z >= H then return 0 end
  local cx, cy, cz = floor(x / CS), floor(y / CS), floor(z / CS)
  local c = W.chunks[(cz * SPAN + (cy + OFF)) * SPAN + (cx + OFF)]
  if not c then return 0 end
  local b = c.blocks
  if not b then return c.fill end
  return b[(x - cx * CS) + (y - cy * CS) * CS + (z - cz * CS) * CS2 + 1] or 0
end

-- solid for physics: the floor is solid, the sky is not, unloaded chunks are solid
function W.solid(x, y, z)
  if z < 0 then return true end
  if z >= H then return false end
  local cx, cy, cz = floor(x / CS), floor(y / CS), floor(z / CS)
  local c = W.chunks[(cz * SPAN + (cy + OFF)) * SPAN + (cx + OFF)]
  if not c then return true end
  local b = c.blocks
  if not b then return c.fill ~= 0 end
  return (b[(x - cx * CS) + (y - cy * CS) * CS + (z - cz * CS) * CS2 + 1] or 0) ~= 0
end

local function markDirty(c) if c then W.dirty[c.key] = c end end

local function markNeighbor(cx, cy, cz)
  if cz >= 0 and cz < CZ then markDirty(W.chunks[W.key(cx, cy, cz)]) end
end

local function markAround(cx, cy, cz)
  markNeighbor(cx - 1, cy, cz); markNeighbor(cx + 1, cy, cz)
  markNeighbor(cx, cy - 1, cz); markNeighbor(cx, cy + 1, cz)
  markNeighbor(cx, cy, cz - 1); markNeighbor(cx, cy, cz + 1)
end

-- write one block into a chunk record; returns true if it changed
local function writeBlock(c, idx, id)
  local b = c.blocks
  if not b then
    if c.fill == id then return false end
    b = {}
    local f = c.fill
    for i = 1, CS2 * CS do b[i] = f end   -- a uniform chunk becomes a real one
    c.blocks = b
  end
  if b[idx] == id then return false end
  b[idx] = id
  return true
end

-- W.onSet (set by net/session.lua while playing online) is told about every change;
-- W.silent = true hides a change from it (used when applying other players' changes)
function W.set(x, y, z, id)
  if z < 0 or z >= H or abs(x) > W.LIMIT or abs(y) > W.LIMIT then return end
  local cx, cy, cz = floor(x / CS), floor(y / CS), floor(z / CS)
  local lx, ly, lz = x - cx * CS, y - cy * CS, z - cz * CS
  local idx = lx + ly * CS + lz * CS2 + 1
  local key = W.key(cx, cy, cz)

  -- a mod decorating the chunk that is being generated right now: write straight into
  -- it (not an "edit", not sent over the network); other chunks are not available yet
  local gen = W.generating
  if gen then
    if gen.key == key then writeBlock(gen, idx, id) end
    return
  end

  local e = W.edits[key]
  if not e then e = {}; W.edits[key] = e end
  e[idx] = id
  W.version = W.version + 1

  local c = W.chunks[key]
  if c and writeBlock(c, idx, id) then
    markDirty(c)
    if lx == 0 then markNeighbor(cx - 1, cy, cz) elseif lx == CS - 1 then markNeighbor(cx + 1, cy, cz) end
    if ly == 0 then markNeighbor(cx, cy - 1, cz) elseif ly == CS - 1 then markNeighbor(cx, cy + 1, cz) end
    if lz == 0 then markNeighbor(cx, cy, cz - 1) elseif lz == CS - 1 then markNeighbor(cx, cy, cz + 1) end
  end
  if W.onSet and not W.silent then W.onSet(x, y, z, id) end
end

-- install a generated chunk. rec = {cx, cy, cz, blocks (or nil), fill}
-- Earlier edits are applied on top of the generated terrain.
function W.addChunk(rec)
  local cx, cy, cz = rec.cx, rec.cy, rec.cz
  rec.key = rec.key or W.key(cx, cy, cz)
  rec.x0, rec.y0, rec.z0 = cx * CS, cy * CS, cz * CS
  rec.fill = rec.fill or 0
  if not W.chunks[rec.key] then W.count = W.count + 1 end
  W.chunks[rec.key] = rec
  local e = W.edits[rec.key]
  if e then for idx, id in pairs(e) do writeBlock(rec, idx, id) end end
  markDirty(rec)
  markAround(cx, cy, cz)   -- neighbours waiting for this chunk can be meshed now
  return rec
end

function W.removeChunk(key)
  local c = W.chunks[key]
  if not c then return end
  W.chunks[key] = nil
  W.dirty[key] = nil
  W.count = W.count - 1
  return c
end

-- wipe everything (used when starting a new game)
function W.clear()
  W.chunks, W.dirty, W.edits, W.count, W.generating = {}, {}, {}, 0, nil
end

-- re-mesh every chunk (used after the texture atlas is rebuilt)
function W.markAllDirty()
  for _, c in pairs(W.chunks) do W.dirty[c.key] = c end
end

-- highest non-air block in a column. If the column is not loaded, W.surface(x, y)
-- (set by chunks.lua: the terrain height) is used instead.
function W.top(x, y)
  local cx, cy = floor(x / CS), floor(y / CS)
  local lx, ly = x - cx * CS, y - cy * CS
  for cz = CZ - 1, 0, -1 do
    local c = W.chunks[W.key(cx, cy, cz)]
    if not c then
      return W.surface and W.surface(x, y) or 0
    end
    local b = c.blocks
    if not b then
      if c.fill ~= 0 then return cz * CS + CS - 1 end
    else
      for lz = CS - 1, 0, -1 do
        if (b[lx + ly * CS + lz * CS2 + 1] or 0) ~= 0 then return cz * CS + lz end
      end
    end
  end
  return 0
end

return W

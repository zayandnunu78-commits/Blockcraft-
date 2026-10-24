-- ============================================================
-- chunks.lua - the chunk manager: decides which chunks exist around the player.
--
--   every frame:  chunks.update(px, py, pz)
--     1. when the player enters a new chunk column, make a list of the chunks that are
--        missing within the view distance (nearest first) and unload the ones that are far
--     2. generate from that list until the time budget for this frame is used up
--     3. mesh dirty chunks (see mesher.lua) with its own time budget
--
--   Chunks are generated from the seed (terrain.lua) and then the saved edits are applied
--   on top (world.edits). Chunks within viewDistance are drawn; one more ring is kept
--   loaded so the drawn ones always have their neighbours.
-- ============================================================
local world = require "world"
local terrain = require "terrain"
local mesher = require "mesher"
local events = require "modsys.events"

local CS, CZ = world.CS, world.CZ
local floor = math.floor

local M = {
  viewDistance = 5,       -- chunks drawn around the player (horizontal radius)
  seed = 1,
  genBudget = 0.004,      -- seconds per frame spent generating chunks
  meshBudget = 0.004,     -- seconds per frame spent building meshes
  queue = {}, qi = 1,
  lastCx = nil, lastCy = nil, lastCz = nil,
}
M.clock = function() return love.timer.getTime() end

function M.reset(seed)
  world.clear()
  mesher.clear()
  terrain.clearCache()
  M.seed = seed
  M.queue, M.qi, M.lastCx, M.lastCy = {}, 1, nil, nil
  world.surface = function(x, y) return terrain.height(M.seed, x, y) end
end

-- make one chunk: terrain, then mods get a chance to decorate it, then it goes live
local function make(cx, cy, cz)
  local blocks, fill = terrain.generateChunk(M.seed, cx, cy, cz)
  local rec = {cx = cx, cy = cy, cz = cz, key = world.key(cx, cy, cz), blocks = blocks, fill = fill}
  local hooks = events.handlers.chunk_generate
  if hooks and #hooks > 0 then
    rec.x0, rec.y0, rec.z0 = cx * CS, cy * CS, cz * CS
    world.generating = rec
    events.fire("chunk_generate", {cx = cx, cy = cy, cz = cz, x0 = rec.x0, y0 = rec.y0, z0 = rec.z0})
    world.generating = nil
  end
  world.addChunk(rec)
end

-- build every chunk in the column radius right now (used when a world starts)
function M.generateAround(px, py, radius)
  local pcx, pcy = floor(px / CS), floor(py / CS)
  for dx = -radius, radius do
    for dy = -radius, radius do
      for cz = 0, CZ - 1 do
        local cx, cy = pcx + dx, pcy + dy
        if not world.chunks[world.key(cx, cy, cz)] then make(cx, cy, cz) end
      end
    end
  end
end

-- mesh everything that can be meshed right now (world start, texture atlas rebuilt)
function M.flush(px, py, pz)
  return mesher.update(px or 0, py or 0, pz or 0, math.huge)
end

-- the list of missing chunks, nearest first, and unloading of far ones
local function replan(pcx, pcy, pcz)
  local R = M.viewDistance + 1          -- loaded radius (one ring more than is drawn)
  local list = {}
  for dx = -R, R do
    for dy = -R, R do
      local d2 = dx * dx + dy * dy
      if d2 <= R * R + R then
        for cz = 0, CZ - 1 do
          local cx, cy = pcx + dx, pcy + dy
          if not world.chunks[world.key(cx, cy, cz)] then
            local dz = cz - pcz
            list[#list + 1] = {cx, cy, cz, d2 + dz * dz * 0.5}
          end
        end
      end
    end
  end
  table.sort(list, function(a, b) return a[4] < b[4] end)
  M.queue, M.qi = list, 1

  -- unload chunks that are well outside the loaded radius
  local far = (R + 2) * (R + 2)
  local drop = {}
  for key, c in pairs(world.chunks) do
    local dx, dy = c.cx - pcx, c.cy - pcy
    if dx * dx + dy * dy > far then drop[#drop + 1] = key end
  end
  for _, key in ipairs(drop) do
    world.removeChunk(key)
    mesher.release(key)
  end
end

function M.setViewDistance(n)
  M.viewDistance = math.max(2, math.min(12, floor(n)))
  M.lastCx = nil -- plan again on the next update
end

function M.update(px, py, pz)
  local pcx, pcy, pcz = floor(px / CS), floor(py / CS), floor(pz / CS)
  if pcz < 0 then pcz = 0 elseif pcz > CZ - 1 then pcz = CZ - 1 end
  if pcx ~= M.lastCx or pcy ~= M.lastCy then
    M.lastCx, M.lastCy = pcx, pcy
    replan(pcx, pcy, pcz)
  end

  local t0 = M.clock()
  local q = M.queue
  while M.qi <= #q do
    local e = q[M.qi]
    M.qi = M.qi + 1
    if not world.chunks[world.key(e[1], e[2], e[3])] then make(e[1], e[2], e[3]) end
    if M.clock() - t0 >= M.genBudget then break end
  end

  mesher.update(px, py, pz, M.meshBudget)
end

function M.info()
  local meshes, verts = 0, 0
  for _, e in pairs(mesher.models) do meshes = meshes + 1; verts = verts + e.verts end
  return {loaded = world.count, meshes = meshes, vertices = verts,
          queued = #M.queue - M.qi + 1, drawn = mesher.drawn, culled = mesher.culled}
end

return M

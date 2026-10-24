-- ============================================================
-- terrain.lua - the shape of the land, as PURE FUNCTIONS of (seed, position).
--
-- Nothing in here uses random numbers, the clock, or math.sin / math.pow (those can differ
-- by a tiny amount between devices). It only uses + - * / floor and whole-number maths
-- that is exact in a double, so a phone, a PC and the server all build THE SAME land
-- from the same seed. That is why the server never has to send terrain: it only sends
-- the seed and the blocks players have changed.
--
--   T.height(seed, x, y)                      -> z of the top block in that column
--   T.generateChunk(seed, cx, cy, cz)         -> blocks (table of 4096 or nil), fill
-- ============================================================
local T = {CS = 16, CZ = 4}
T.MAX_HEIGHT = 37       -- no column is ever taller than this
T.TREE_MAX_Z = 35       -- no tree block is ever higher than this
T.SAND_MAX = 9          -- columns up to this height are sand (beaches / lowlands)
T.ROCK_MIN = 31         -- columns from this height up are bare stone (mountain tops)

local CS, CZ = T.CS, T.CZ
local CS2 = CS * CS
local floor, abs = math.floor, math.abs
local MOD = 2147483647

-- block ids (the order in blocks.lua)
local GRASS, DIRT, STONE, WOOD, LEAVES, SAND = 1, 2, 3, 4, 5, 6

-- integer hash -> [0, 1). Every product stays below 2^53, so it is exact everywhere.
local function hash(ix, iy, seed)
  local h = (ix * 1619 + iy * 31337 + seed * 6971 + 1013904223) % MOD
  h = (h * 48271 + 12345) % MOD
  h = (h * 48271 + ix * 7 + 12345) % MOD
  h = (h * 48271 + iy * 13 + 12345) % MOD
  return h / MOD
end
T.hash = hash

local function vnoise(x, y, seed)
  local x0, y0 = floor(x), floor(y)
  local fx, fy = x - x0, y - y0
  fx = fx * fx * (3 - 2 * fx)
  fy = fy * fy * (3 - 2 * fy)
  local a, b = hash(x0, y0, seed), hash(x0 + 1, y0, seed)
  local c, d = hash(x0, y0 + 1, seed), hash(x0 + 1, y0 + 1, seed)
  local top = a + (b - a) * fx
  local bot = c + (d - c) * fx
  return top + (bot - top) * fy
end

local function fbm(x, y, seed, octaves)
  local sum, amp, norm, f = 0, 1, 0, 1
  for o = 0, octaves - 1 do
    sum = sum + vnoise(x * f, y * f, seed + o * 1013) * amp
    norm = norm + amp
    amp = amp * 0.5
    f = f * 2
  end
  return sum / norm
end

function T.height(seed, x, y)
  -- 0.015625 = 1/64 and 0.0625 = 1/16 are powers of two: the multiplication is exact
  local base = fbm(x * 0.015625, y * 0.015625, seed, 4)          -- big hills (64 blocks wide)
  local detail = fbm(x * 0.0625, y * 0.0625, seed + 7919, 2)     -- bumps (16 blocks wide)
  local b = (base - 0.5) * 1.8 + 0.5                              -- more contrast
  if b < 0 then b = 0 elseif b > 1 then b = 1 end
  local ridge = b * b * (3 - 2 * b)
  return 5 + floor(ridge * 30 + detail * 2.5)
end

-- ---------------- trees ----------------
-- The land is cut into 6x6 cells; each cell may hold one tree. Whether and where is a
-- pure function of the cell, so every chunk can work out the trees that reach into it
-- without looking at its neighbours.
local CELL = 6

-- returns ox, oy, groundHeight of the tree in cell (qx, qy), or nil
function T.treeOrigin(seed, qx, qy)
  if hash(qx, qy, seed + 555) >= 0.5 then return nil end
  local ox = qx * CELL + 1 + floor(hash(qx, qy, seed + 556) * 4)
  local oy = qy * CELL + 1 + floor(hash(qx, qy, seed + 557) * 4)
  if abs(ox) <= 4 and abs(oy) <= 4 then return nil end   -- keep the spawn area clear
  local h = T.height(seed, ox, oy)
  if h <= T.SAND_MAX or h >= T.ROCK_MIN then return nil end
  return ox, oy, h
end

-- the blocks of one tree: calls put(x, y, z, id) for every leaf, then every trunk block
function T.treeBlocks(ox, oy, h, put)
  for lz = h + 3, h + 5 do
    local r = (lz == h + 5) and 1 or 2
    for dx = -r, r do
      for dy = -r, r do
        if not (abs(dx) == r and abs(dy) == r) then put(ox + dx, oy + dy, lz, LEAVES, true) end
      end
    end
  end
  for k = 1, 4 do put(ox, oy, h + k, WOOD, false) end
end

-- ---------------- columns ----------------
-- heights of the 16x16 columns of one chunk column, remembered for the 4 chunks above
-- each other (and for a few neighbours)
local cache, cacheCount, cacheSeed = {}, 0, nil

function T.clearCache() cache, cacheCount, cacheSeed = {}, 0, nil end

local function column(seed, cx, cy)
  if cacheSeed ~= seed then cache, cacheCount, cacheSeed = {}, 0, seed end
  local ck = cx * 4194304 + cy
  local col = cache[ck]
  if col then return col end
  if cacheCount >= 96 then cache, cacheCount = {}, 0 end
  col = {h = {}, top = {}, sub = {}}
  local mn, mx = 1e9, -1e9
  for ly = 0, CS - 1 do
    for lx = 0, CS - 1 do
      local h = T.height(seed, cx * CS + lx, cy * CS + ly)
      local i = lx + ly * CS + 1
      col.h[i] = h
      if h <= T.SAND_MAX then col.top[i], col.sub[i] = SAND, SAND
      elseif h >= T.ROCK_MIN then col.top[i], col.sub[i] = STONE, STONE
      else col.top[i], col.sub[i] = GRASS, DIRT end
      if h < mn then mn = h end
      if h > mx then mx = h end
    end
  end
  col.min, col.max = mn, mx
  cache[ck] = col
  cacheCount = cacheCount + 1
  return col
end

-- Returns blocks, fill:  blocks = table of 4096 ids, or nil with fill = the one id the
-- whole chunk is made of. `slow = true` skips the shortcuts (used by the tests to prove
-- the shortcuts give the same result).
function T.generateChunk(seed, cx, cy, cz, slow)
  local col = column(seed, cx, cy)
  local x0, y0, z0 = cx * CS, cy * CS, cz * CS
  local z1 = z0 + CS - 1

  if not slow then
    if z0 > col.max and z0 > T.TREE_MAX_Z then return nil, 0 end    -- open sky
    if z1 <= col.min - 4 then return nil, STONE end                 -- solid rock
  end

  local blocks = {}
  local first = nil
  local uniform = true
  local h, top, sub = col.h, col.top, col.sub
  for ly = 0, CS - 1 do
    for lx = 0, CS - 1 do
      local ci = lx + ly * CS + 1
      local hh, tb, sb = h[ci], top[ci], sub[ci]
      local base = ci
      for lz = 0, CS - 1 do
        local z = z0 + lz
        local id
        if z > hh then id = 0
        elseif z == hh then id = tb
        elseif z >= hh - 3 then id = sb
        else id = STONE end
        blocks[base + lz * CS2] = id
        if first == nil then first = id elseif id ~= first then uniform = false end
      end
    end
  end

  -- trees from every cell that can reach into this chunk (a tree is 5 wide at most)
  if z0 <= T.TREE_MAX_Z then
    local qx0, qx1 = floor((x0 - 2) / CELL), floor((x0 + CS + 1) / CELL)
    local qy0, qy1 = floor((y0 - 2) / CELL), floor((y0 + CS + 1) / CELL)
    local function put(x, y, z, id, onlyAir)
      local lx, ly, lz = x - x0, y - y0, z - z0
      if lx < 0 or lx >= CS or ly < 0 or ly >= CS or lz < 0 or lz >= CS then return end
      local i = lx + ly * CS + lz * CS2 + 1
      if onlyAir and blocks[i] ~= 0 then return end
      blocks[i] = id
      uniform = false
    end
    for qx = qx0, qx1 do
      for qy = qy0, qy1 do
        local ox, oy, oh = T.treeOrigin(seed, qx, qy)
        if ox then T.treeBlocks(ox, oy, oh, put) end
      end
    end
  end

  if uniform and not slow then return nil, first end
  return blocks, 0
end

return T

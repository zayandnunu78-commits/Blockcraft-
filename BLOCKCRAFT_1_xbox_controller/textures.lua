-- Block textures drawn in code (no image files needed)
-- The atlas is one row of 16x16 tiles. Mods can append tiles with T.addTile()
-- and then call T.rebuild() once. Built-in tiles: 1 grass top, 2 grass side, 3 dirt, 4 stone,
-- 5 bark, 6 log rings, 7 leaves, 8 sand, 9 planks, 10 cobble, 11 brick
local T = {N = 0, S = 16, quads = {}, tiles = {}, MAX_TILES = 512}

local function rnd(x, y, t)
  local v = math.sin(x * 12.9898 + y * 78.233 + t * 37.719) * 43758.5453
  return v - math.floor(v)
end

local function grassTop(x, y)
  local n = (rnd(x, y, 1) - .5) * .2
  if rnd(x, y, 11) > .88 then n = n - .1 end
  return .32 + n, .66 + n, .2 + n * .6
end

local function dirt(x, y)
  local n = (rnd(x, y, 3) - .5) * .2
  if rnd(x, y, 13) > .9 then n = n - .12 end
  return .52 + n, .36 + n, .22 + n
end

local function grassSide(x, y)
  local edge = 3 + math.floor(rnd(x, 0, 2) * 3)
  if y < edge then return grassTop(x, y) end
  return dirt(x, y)
end

local function stone(x, y)
  local n = (rnd(x, y, 4) - .5) * .16
  if rnd(x, y, 14) > .93 then n = n - .14 end
  if rnd(x + 5, y + 3, 24) > .95 then n = n + .08 end
  return .5 + n, .5 + n, .52 + n
end

local function bark(x, y)
  local n = (rnd(x, y, 5) - .5) * .1
  if x % 4 == 0 then n = n - .08 end
  return .42 + n, .28 + n * .8, .14 + n * .5
end

local function rings(x, y)
  local d = math.sqrt((x - 7.5) ^ 2 + (y - 7.5) ^ 2)
  if d > 7 then return bark(x, y) end
  local n = (rnd(x, y, 6) - .5) * .06
  if math.floor(d) % 2 == 1 then n = n - .08 end
  return .68 + n, .52 + n, .3 + n
end

local function leaves(x, y)
  local n = (rnd(x, y, 7) - .5) * .2
  if rnd(x, y, 17) > .8 then n = n - .15 end
  return .16 + n * .6, .5 + n, .14 + n * .6
end

local function sand(x, y)
  local n = (rnd(x, y, 8) - .5) * .1
  if rnd(x, y, 18) > .92 then n = n - .06 end
  return .86 + n, .8 + n, .56 + n
end

local function planks(x, y)
  local n = (rnd(x, y, 9) - .5) * .08
  if y % 4 == 0 then n = n - .1 end
  if rnd(math.floor(y / 4), 0, 19) > .5 and x % 8 == 0 then n = n - .08 end
  return .72 + n, .55 + n, .32 + n
end

local function cobble(x, y)
  local cell = rnd(math.floor(x / 5), math.floor(y / 5), 10) - .5
  local n = cell * .22 + (rnd(x, y, 20) - .5) * .06
  if x % 5 == 0 or y % 5 == 0 then n = n - .16 end
  return .5 + n, .5 + n, .52 + n
end

local function brick(x, y)
  local row = math.floor(y / 4)
  local off = (row % 2) * 4
  if y % 4 == 0 or (x + off) % 8 == 0 then return .75, .73, .7 end
  local n = (rnd(x, y, 11) - .5) * .1
  return .6 + n, .25 + n * .5, .2 + n * .5
end

local fns = {grassTop, grassSide, dirt, stone, bark, rings, leaves, sand, planks, cobble, brick}

-- ---------------------------------------------------------------
-- tiles are kept as separate 16x16 ImageData; T.rebuild() packs them
-- ---------------------------------------------------------------
for t, fn in ipairs(fns) do
  local img = love.image.newImageData(T.S, T.S)
  for y = 0, T.S - 1 do
    for x = 0, T.S - 1 do
      local r, g, b = fn(x, y)
      img:setPixel(x, y, math.max(0, math.min(1, r)), math.max(0, math.min(1, g)),
                   math.max(0, math.min(1, b)), 1)
    end
  end
  T.tiles[t] = img
end
T.N = #fns

-- Convert any image to a 16x16 opaque tile.
-- Taller-than-wide images (Minecraft animated textures) use their first frame.
function T.normalize(src)
  local w, h = src:getDimensions()
  local size = math.min(w, h)
  local out = love.image.newImageData(T.S, T.S)
  for y = 0, T.S - 1 do
    for x = 0, T.S - 1 do
      local sx = math.min(w - 1, math.floor((x + 0.5) * size / T.S))
      local sy = math.min(h - 1, math.floor((y + 0.5) * size / T.S))
      local r, g, b = src:getPixel(sx, sy)
      out:setPixel(x, y, r, g, b, 1)
    end
  end
  return out
end

-- Add a tile (ImageData of any size). Returns the new tile number,
-- or nil if the atlas is full. Call T.rebuild() after adding.
function T.addTile(imageData)
  if T.N >= T.MAX_TILES then return nil end
  T.N = T.N + 1
  T.tiles[T.N] = T.normalize(imageData)
  return T.N
end

function T.rebuild()
  local atlas = love.image.newImageData(T.N * T.S, T.S)
  for i = 1, T.N do
    atlas:paste(T.tiles[i], (i - 1) * T.S, 0, 0, 0, T.S, T.S)
  end
  T.image = love.graphics.newImage(atlas)
  T.image:setFilter("nearest", "nearest")
  T.quads = {} -- quads depend on N, so they must be recreated
  T.version = (T.version or 0) + 1
end

T.rebuild()

-- uv for a corner (cu, cv are 0 or 1) of a tile, inset a hair to avoid bleeding
function T.uv(tile, cu, cv)
  local e = 0.002
  return (tile - 1 + e + cu * (1 - 2 * e)) / T.N, e + cv * (1 - 2 * e)
end

function T.quad(tile)
  if not T.quads[tile] then
    T.quads[tile] = love.graphics.newQuad((tile - 1) * T.S, 0, T.S, T.S,
                                          T.N * T.S, T.S)
  end
  return T.quads[tile]
end

return T

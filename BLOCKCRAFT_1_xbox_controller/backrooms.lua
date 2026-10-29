-- Backrooms Level 0: deterministic rooms, corridors, and a light fluorescent hum.
-- This module owns only the optional level mode; the normal terrain, saves, and
-- multiplayer protocol remain unchanged until the player explicitly teleports.
local blocks = require "blocks"
local textures = require "textures"

local B = {active = false, seed = 41027, CELL = 8, FLOOR_Z = 0, CEILING_Z = 4}
local wallpaper, carpet, fluorescent
local logo, hum
local floor = math.floor

local function hash(x, y, seed)
  local n = (x * 374761393 + y * 668265263 + seed * 69069) % 2147483647
  n = (n * 48271 + 12345) % 2147483647
  return n / 2147483647
end

local function tile(fn)
  local d = love.image.newImageData(16, 16)
  for y = 0, 15 do
    for x = 0, 15 do
      local r, g, b = fn(x, y)
      d:setPixel(x, y, r, g, b, 1)
    end
  end
  return textures.addTile(d)
end

local function setupMaterials()
  if wallpaper then return end
  carpet = tile(function(x, y)
    local n = (hash(x, y, 7) - 0.5) * 0.07
    return 0.29 + n, 0.22 + n, 0.11 + n * 0.5
  end)
  wallpaper = tile(function(x, y)
    local seam = (x == 0 or x == 15) and -0.06 or 0
    local n = (hash(x, y, 11) - 0.5) * 0.035
    return 0.78 + n + seam, 0.68 + n + seam, 0.31 + n * 0.6 + seam
  end)
  fluorescent = tile(function(x, y)
    local edge = (x < 2 or x > 13 or y < 2 or y > 13) and 0.72 or 1
    return 0.96 * edge, 0.95 * edge, 0.78 * edge
  end)
  textures.rebuild()
  local function reg(key, name, tileId)
    return blocks.register(key, name, tileId, tileId, tileId)
  end
  carpet = reg("backrooms:carpet", "Backrooms Carpet", carpet)
  wallpaper = reg("backrooms:yellow_wallpaper", "Yellow Wallpaper", wallpaper)
  fluorescent = reg("backrooms:fluorescent_light", "Fluorescent Light", fluorescent)
end

function B.init()
  setupMaterials()
  if love.filesystem.getInfo("assets/backrooms_logo.png") then
    logo = love.graphics.newImage("assets/backrooms_logo.png")
    logo:setFilter("linear", "linear")
  end
  if not hum and love.audio and love.sound then
    local rate, seconds = 22050, 3
    local data = love.sound.newSoundData(rate * seconds, rate, 16, 1)
    for i = 0, data:getSampleCount() - 1 do
      local t = i / rate
      local buzz = math.sin(t * math.pi * 2 * 96) * 0.035
      local whine = math.sin(t * math.pi * 2 * 192) * 0.012
      data:setSample(i, buzz + whine)
    end
    hum = love.audio.newSource(data, "static")
    hum:setLooping(true)
    hum:setVolume(0.18)
    hum:play()
  end
end

function B.height(_, _) return B.FLOOR_Z end
function B.isActive() return B.active end
function B.enter(seed)
  setupMaterials()
  B.active = true
  B.seed = seed or B.seed
end

-- Grid walls make rooms approximately 7x7 blocks wide. Deterministic openings
-- remove enough wall segments to form a connected-looking maze without storing
-- a large map or allocating more than one 16^3 chunk at a time.
local function openingX(cx, cy)
  return hash(cx, cy, B.seed + 101) > 0.28
end
local function openingY(cx, cy)
  return hash(cx, cy, B.seed + 211) > 0.28
end
local function isWall(x, y)
  local lx, ly = x % B.CELL, y % B.CELL
  if lx == 0 then
    return not (ly >= 2 and ly <= 5 and openingX(floor(x / B.CELL), floor(y / B.CELL)))
  end
  if ly == 0 then
    return not (lx >= 2 and lx <= 5 and openingY(floor(x / B.CELL), floor(y / B.CELL)))
  end
  return false
end

function B.blockAt(x, y, z)
  if z < B.FLOOR_Z or z > B.CEILING_Z then return 0 end
  if z == B.FLOOR_Z then return carpet end
  if z < B.CEILING_Z and isWall(x, y) then return wallpaper end
  if z == B.CEILING_Z then
    local lx, ly = x % B.CELL, y % B.CELL
    if (lx == 3 or lx == 4) and (ly == 3 or ly == 4) then return fluorescent end
    return wallpaper
  end
  return 0
end

function B.generateChunk(_, cx, cy, cz)
  local x0, y0, z0 = cx * 16, cy * 16, cz * 16
  local blocksOut, first, uniform = {}, nil, true
  for ly = 0, 15 do
    for lx = 0, 15 do
      for lz = 0, 15 do
        local id = B.blockAt(x0 + lx, y0 + ly, z0 + lz)
        local i = lx + ly * 16 + lz * 256 + 1
        blocksOut[i] = id
        if first == nil then first = id elseif id ~= first then uniform = false end
      end
    end
  end
  if uniform then return nil, first end
  return blocksOut, 0
end

function B.buttonLayout(w, h)
  return {x = w - 74, y = h - 238, r = 30}
end
function B.buttonHit(x, y, w, h)
  if B.active then return false end
  local p = B.buttonLayout(w, h)
  return (x - p.x)^2 + (y - p.y)^2 <= (p.r + 10)^2
end
function B.drawButton(w, h)
  if B.active then return end
  local p = B.buttonLayout(w, h)
  love.graphics.setColor(0.15, 0.08, 0.02, 0.75)
  love.graphics.circle("fill", p.x, p.y, p.r + 5)
  if logo then
    local iw, ih = logo:getDimensions()
    local s = (p.r * 1.55) / math.max(iw, ih)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.draw(logo, p.x - iw * s / 2, p.y - ih * s / 2, 0, s, s)
  else
    love.graphics.setColor(1, 0.86, 0.4, 1)
    love.graphics.circle("fill", p.x, p.y, p.r)
    love.graphics.setColor(0.25, 0.15, 0.04, 1)
    love.graphics.printf("L0", p.x - p.r, p.y - 9, p.r * 2, "center")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return B

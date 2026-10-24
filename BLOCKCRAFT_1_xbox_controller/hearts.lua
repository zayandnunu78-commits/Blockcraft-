-- ============================================================
-- hearts.lua - draws the hearts above the hotbar and the red flash when you are hurt.
-- The heart pictures are made in code (no image files): a 7x6 pixel heart with an outline,
-- made once as a tiny image and then drawn scaled up, so drawing 10 hearts is 10 draw calls.
-- ============================================================
local health = require "health"
local hotbar = require "hotbar"

local M = {}

local PATTERN = {
  ".XX.XX.",
  "XXXXXXX",
  "XXXXXXX",
  ".XXXXX.",
  "..XXX..",
  "...X...",
}
local PW, PH = 7, 6
M.IMG_W, M.IMG_H = PW + 2, PH + 2     -- 1 pixel of outline all around

local images -- {full, half, empty}

local function make(kind)
  local img = love.image.newImageData(M.IMG_W, M.IMG_H)
  local function on(px, py) -- is the pattern lit at (px, py)? (1-based, inside the 7x6 grid)
    return px >= 1 and px <= PW and py >= 1 and py <= PH and PATTERN[py]:sub(px, px) == "X"
  end
  for py = 0, PH + 1 do
    for px = 0, PW + 1 do
      local ix, iy = px, py
      if on(px, py) then
        local r, g, b
        local filled = (kind == "full") or (kind == "half" and px <= 4)
        if filled then
          r, g, b = 0.90, 0.14, 0.20
          if px == 2 and py == 2 then r, g, b = 1.0, 0.62, 0.66 end       -- shine
          if py >= 5 or (py == 4 and (px == 2 or px == 6)) then r, g, b = 0.68, 0.08, 0.15 end -- shade
        else
          r, g, b = 0.24, 0.24, 0.28
        end
        img:setPixel(ix, iy, r, g, b, 1)
      elseif on(px - 1, py) or on(px + 1, py) or on(px, py - 1) or on(px, py + 1) then
        img:setPixel(ix, iy, 0.08, 0.04, 0.06, 1)    -- outline
      else
        img:setPixel(ix, iy, 0, 0, 0, 0)
      end
    end
  end
  local image = love.graphics.newImage(img)
  image:setFilter("nearest", "nearest")
  return image
end

local function getImages()
  if not images then images = {full = make("full"), half = make("half"), empty = make("empty")} end
  return images
end

-- where the hearts go: left edge of the hotbar, above the block name
function M.layout()
  local x0, y, s, gap = hotbar.layout()
  local hotbarW = 9 * s + 8 * gap
  local per = health.max / 2                                   -- 10 hearts
  local sc = math.max(2, math.min(3, math.floor(hotbarW / (per * (M.IMG_W + 2)))))
  local cell = M.IMG_W * sc
  local step = cell + sc
  local hy = y - 26 - 4 - M.IMG_H * sc
  return x0, hy, sc, step
end

-- the red flash when hurt (draw first, under the other HUD parts)
function M.drawFlash()
  if health.flash > 0 then
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(1, 0.1, 0.1, 0.35 * health.flash / health.FLASH)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function M.draw()
  local img = getImages()
  local x, y, sc, step = M.layout()
  local per = math.floor(health.max / 2)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, per do
    local pointsHere = health.hp - (i - 1) * 2
    local which = pointsHere >= 2 and img.full or (pointsHere == 1 and img.half or img.empty)
    love.graphics.draw(which, x + (i - 1) * step, y, 0, sc, sc)
  end
end

M._pattern = PATTERN
return M

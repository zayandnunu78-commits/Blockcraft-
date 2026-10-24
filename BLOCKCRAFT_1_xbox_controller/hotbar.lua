-- Hotbar: 9 slots, number keys / mouse wheel / tap to select
local blocks = require "blocks"
local textures = require "textures"

local Hb = {slots = {}, selected = 1, count = 9}

-- slots hold block ids (see blocks.lua)
function Hb.load()
  Hb.slots = {2, 1, 3, 4, 5, 6, 7, 8, 9} -- Dirt, Grass, Stone, Wood, Leaves, Sand, Planks, Cobble, Brick
  Hb.selected = 1
end

function Hb.select(i)
  Hb.selected = (i - 1) % Hb.count + 1
end

function Hb.scroll(dir)
  Hb.select(Hb.selected + dir)
end

-- returns the block id of the active slot, and its definition
function Hb.getSelectedBlock()
  local id = Hb.slots[Hb.selected]
  return id, blocks[id]
end

-- [ and ] swap the selected slot's block for the previous / next registered
-- block, so every block added by mods can be reached
function Hb.cycleBlock(dir)
  local id = Hb.slots[Hb.selected]
  Hb.slots[Hb.selected] = (id - 1 + dir) % #blocks + 1
end

function Hb.keypressed(key)
  if key == "[" then Hb.cycleBlock(-1) return end
  if key == "]" then Hb.cycleBlock(1) return end
  local n = tonumber(key)
  if n and n >= 1 and n <= Hb.count then Hb.select(n) end
end

function Hb.wheelmoved(x, y)
  if y > 0 or x < 0 then Hb.scroll(-1)
  elseif y < 0 or x > 0 then Hb.scroll(1) end
end

-- bottom center of the screen
function Hb.layout()
  local w, h = love.graphics.getDimensions()
  local gap = 4
  local s = math.min(48, math.floor((w - 16 - gap * (Hb.count - 1)) / Hb.count))
  local x0 = (w - (Hb.count * s + (Hb.count - 1) * gap)) / 2
  return x0, h - s - 12, s, gap
end

-- tap on a slot; returns true if a slot was hit
function Hb.pressed(px, py)
  local x0, y, s, gap = Hb.layout()
  for i = 1, Hb.count do
    local x = x0 + (i - 1) * (s + gap)
    if px >= x and px <= x + s and py >= y and py <= y + s then
      if i == Hb.selected then Hb.cycleBlock(1) -- tap the selected slot again: next block (phones)
      else Hb.select(i) end
      return true
    end
  end
  return false
end

function Hb.draw()
  Hb.small = Hb.small or love.graphics.newFont(12)
  Hb.big = Hb.big or love.graphics.newFont(16)
  local prev = love.graphics.getFont()
  local x0, y, s, gap = Hb.layout()
  local w = love.graphics.getWidth()

  for i = 1, Hb.count do
    local x = x0 + (i - 1) * (s + gap)
    local def = blocks[Hb.slots[i]]
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", x, y, s, s)

    local pad = 5
    local sc = (s - pad * 2) / textures.S
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(textures.image, textures.quad(def.icon), x + pad, y + pad, 0, sc, sc)

    love.graphics.setFont(Hb.small)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.print(i, x + 3, y + 1)

    if i == Hb.selected then
      love.graphics.setColor(1, 0.9, 0.2, 1)
      love.graphics.setLineWidth(4)
    else
      love.graphics.setColor(1, 1, 1, 0.35)
      love.graphics.setLineWidth(2)
    end
    love.graphics.rectangle("line", x, y, s, s)
  end

  love.graphics.setFont(Hb.big)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(blocks[Hb.slots[Hb.selected]].name, 0, y - 26, w, "center")
  love.graphics.setFont(prev)
end

return Hb

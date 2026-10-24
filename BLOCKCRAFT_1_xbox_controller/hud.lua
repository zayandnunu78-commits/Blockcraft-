-- Draws the crosshair, hotbar, buttons and move stick
local hotbar = require "hotbar"
local hearts = require "hearts"
local events = require "modsys.events"
local modapi = require "modsys.api"
local H = {}

function H.draw(I)
  H.font = H.font or love.graphics.newFont(16)
  love.graphics.setFont(H.font)
  local L = I.layout()
  local cx, cy = L.w / 2, L.h / 2

  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.line(cx - 10, cy, cx + 10, cy)
  love.graphics.line(cx, cy - 10, cx, cy + 10)

  hearts.drawFlash()  -- red flash when hurt (under everything else)
  hotbar.draw()
  hearts.draw()

  local p = L.pause
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 8, 8)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", p.x + 15, p.y + 13, 6, 22)
  love.graphics.rectangle("fill", p.x + 27, p.y + 13, 6, 22)

  local m = L.mode
  if I.mode == "break" then love.graphics.setColor(.8, .25, .2, .75)
  else love.graphics.setColor(.2, .7, .3, .75) end
  love.graphics.rectangle("fill", m.x, m.y, m.w, m.h, 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(I.mode:upper(), m.x, m.y + 13, m.w, "center")

  local j = L.jump
  love.graphics.setColor(1, 1, 1, 0.25)
  love.graphics.circle("fill", j.x, j.y, j.r)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf("JUMP", j.x - j.r, j.y - 9, j.r * 2, "center")

  for _, t in pairs(I.touches) do
    if t.kind == "move" then
      local dx, dy = t.x - t.sx, t.y - t.sy
      local d = math.sqrt(dx * dx + dy * dy)
      if d > 50 then dx, dy = dx / d * 50, dy / d * 50 end
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.circle("line", t.sx, t.sy, 50)
      love.graphics.circle("fill", t.sx + dx, t.sy + dy, 22)
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)

  events.fire("draw_hud", modapi.gfx) -- mods can draw on top
  love.graphics.setColor(1, 1, 1, 1)
end

return H

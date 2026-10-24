-- Touch, mouse, keyboard, and Xbox controller controls.
-- Xbox bindings are kept exact in xbox_controller.lua.
local world = require "world"
local player = require "player"
local raycast = require "raycast"
local hotbar = require "hotbar"
local gameState = require "gamestate"
local settings = require "settings"
local events = require "modsys.events"
local blocks = require "blocks"
local XboxController = require "xbox_controller"

local I = {yaw = 0, pitch = -0.2, mode = "break", touches = {},
           controller = XboxController.new(), jumpPressed = false,
           cameraView = 1, flightEnabled = false}
local desktop = false

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

function I.init()
  local os_ = love.system.getOS()
  desktop = (os_ ~= "iOS" and os_ ~= "Android")
end

function I.layout()
  local w, h = love.graphics.getDimensions()
  local L = {w = w, h = h}
  L.pause = {x = w - 62, y = 14, w = 48, h = 48}
  L.jump = {x = w - 80, y = h - 140, r = 48}
  L.mode = {x = w - 138, y = h - 260, w = 116, h = 46}
  return L
end

local function act(mode)
  local eye = player.z + player.eye
  local hit, prev = raycast.cast(player.x, player.y, eye, I.yaw, I.pitch, 6)
  if not hit then return end
  if mode == "break" then
    if hit[3] > 0 then
      -- Blocks with destroy_time are still mined by holding the desktop mouse.
      local bd = blocks[world.get(hit[1], hit[2], hit[3])]
      if desktop and bd and (bd.destroyTime or 0) > 0 then return end
      local e = {x = hit[1], y = hit[2], z = hit[3], block = world.get(hit[1], hit[2], hit[3])}
      if events.fire("block_break", e) then world.set(hit[1], hit[2], hit[3], 0) end
    end
  elseif prev and world.inBounds(prev[1], prev[2], prev[3])
      and not player.overlaps(prev[1], prev[2], prev[3]) then
    local e = {x = prev[1], y = prev[2], z = prev[3], block = (hotbar.getSelectedBlock())}
    if events.fire("block_place", e) then
      local id = blocks.find(e.block)
      if id then world.set(prev[1], prev[2], prev[3], id) end
    end
  end
end

-- LÖVE joystick callbacks are translated into this platform-neutral layer by
-- main.lua. Actions without an existing game system are emitted as hooks so
-- future inventory/chat/player systems can use the same exact bindings.
function I.controllerPressed(button)
  local handled = I.controller:hotbar(button)
  if not handled then handled = I.controller:press(button) end
  for _, e in ipairs(I.controller:drainEvents()) do
    if e.action == "hotbar" then
      hotbar.scroll(e.value)
    elseif e.action == "interact" then
      act(I.mode)                                      -- A: place/break
    elseif e.action == "jump" then
      I.jumpPressed = true                             -- B: jump
    elseif e.action == "camera_view" then
      I.cameraView = I.cameraView % 2 + 1              -- Y: view hook
      events.fire("xbox_action", {action = e.action, view = I.cameraView})
    elseif e.action == "flight_toggle" then
      I.flightEnabled = e.value and true or false     -- LT: exact press counts
      events.fire("xbox_action", {action = e.action, enabled = I.flightEnabled})
    else
      events.fire("xbox_action", {action = e.action, value = e.value})
    end
  end
  return handled
end

function I.controllerReleased(button)
  return I.controller:release(button)
end

function I.controllerAxis(axis, value)
  I.controller:axis(axis, value)
  for _, e in ipairs(I.controller:drainEvents()) do
    if e.action == "flight_toggle" then
      I.flightEnabled = e.value and true or false
      events.fire("xbox_action", {action = e.action, enabled = I.flightEnabled})
    elseif e.action == "chat" then
      events.fire("xbox_action", {action = "chat"})
    end
  end
end

function I.pressed(id, x, y)
  local L = I.layout()
  local p = L.pause
  if x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h then
    I.touches = {}
    gameState.set("paused")
    return
  end
  if require("net.session").pressed(x, y) then return end
  if hotbar.pressed(x, y) then return end
  local m = L.mode
  if x >= m.x and x <= m.x + m.w and y >= m.y and y <= m.y + m.h then
    I.mode = (I.mode == "break") and "place" or "break"
    return
  end
  local j = L.jump
  if (x - j.x) ^ 2 + (y - j.y) ^ 2 <= j.r ^ 2 * 1.5 then
    I.touches[id] = {kind = "jump"}
    return
  end
  local kind = (x < L.w / 2) and "move" or "look"
  I.touches[id] = {kind = kind, sx = x, sy = y, x = x, y = y,
                   moved = 0, t0 = love.timer.getTime()}
end

function I.moved(id, x, y, dx, dy)
  local t = I.touches[id]
  if not t then return end
  t.x, t.y = x, y
  if t.kind == "look" then
    I.yaw = I.yaw - dx * 0.005 * settings.sensitivity
    I.pitch = clamp(I.pitch - dy * 0.005 * settings.sensitivity, -1.5, 1.5)
    t.moved = t.moved + math.abs(dx) + math.abs(dy)
  end
end

function I.released(id)
  local t = I.touches[id]
  I.touches[id] = nil
  if t and t.kind == "look" and t.moved < 14
      and love.timer.getTime() - t.t0 < 0.35 then
    act(I.mode)
  end
end

function I.mousepressed(x, y, button, istouch)
  if istouch or not desktop then return end
  if button == 1 then act("break") elseif button == 2 then act("place") end
end

function I.mousemoved(x, y, dx, dy, istouch)
  if istouch or not desktop then return end
  I.yaw = I.yaw - dx * 0.003 * settings.sensitivity
  I.pitch = clamp(I.pitch - dy * 0.003 * settings.sensitivity, -1.5, 1.5)
end

function I.keypressed(key)
  hotbar.keypressed(key)
  events.fire("key", key)
end

function I.wheelmoved(x, y)
  hotbar.wheelmoved(x, y)
end

function I.update(dt)
  I.controller:update(dt)
  local k = love.keyboard.isDown
  local lookX, lookY = I.controller:look()
  I.yaw = I.yaw - lookX * 2.8 * dt
  I.pitch = clamp(I.pitch - lookY * 2.2 * dt, -1.5, 1.5)
  if k("left") then I.yaw = I.yaw + 2 * dt end
  if k("right") then I.yaw = I.yaw - 2 * dt end
  if k("up") then I.pitch = clamp(I.pitch + 1.5 * dt, -1.5, 1.5) end
  if k("down") then I.pitch = clamp(I.pitch - 1.5 * dt, -1.5, 1.5) end
end

-- returns forward, strafe, jump
function I.move()
  local fwd, str, jump = 0, 0, false
  local k = love.keyboard.isDown
  local controllerStr, controllerFwd = I.controller:move()
  str, fwd = str + controllerStr, fwd + controllerFwd
  if k("w") then fwd = fwd + 1 end
  if k("s") then fwd = fwd - 1 end
  if k("d") then str = str + 1 end
  if k("a") then str = str - 1 end
  for _, t in pairs(I.touches) do
    if t.kind == "move" then
      local dx, dy = (t.x - t.sx) / 50, (t.y - t.sy) / 50
      if math.abs(dx) < 0.15 then dx = 0 end
      if math.abs(dy) < 0.15 then dy = 0 end
      str = str + clamp(dx, -1, 1)
      fwd = fwd - clamp(dy, -1, 1)
    elseif t.kind == "jump" then
      jump = true
    end
  end
  jump = jump or I.jumpPressed
  I.jumpPressed = false
  return clamp(fwd, -1, 1), clamp(str, -1, 1), jump or k("space")
end

return I

-- Xbox controller abstraction for Blockcraft 1.
-- This module is platform-neutral: LÖVE events are translated into button/axis
-- calls by input.lua, while gameplay/menu code consumes named actions.
local C = {}
C.__index = C

C.DEFAULTS = {
  deadzone = 0.18,
  triggerThreshold = 0.55,
  flightWindow = 0.45,
}

-- Exact requested layout. Do not silently replace these with Minecraft defaults.
C.BINDINGS = {
  a = "interact",       -- place/break using the current Blockcraft mode
  b = "jump",
  x = "inventory",
  y = "camera_view",
  leftstick = "move",
  rightstick = "look",
  leftshoulder = "attack",
  rightshoulder = "feed",
  lefttrigger = "flight_press",
  righttrigger = "chat",
  back = "world_menu",
  start = "main_menu",
  dpad = "hotbar",
}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

function C.new(options)
  options = options or {}
  local self = setmetatable({}, C)
  self.deadzone = options.deadzone or C.DEFAULTS.deadzone
  self.triggerThreshold = options.triggerThreshold or C.DEFAULTS.triggerThreshold
  self.flightWindow = options.flightWindow or C.DEFAULTS.flightWindow
  self.flightEnabled = false
  self.flightPresses = 0
  self.flightTimer = 0
  self.ltDown = false
  self.rtDown = false
  self.buttons = {}
  self.axes = {leftx = 0, lefty = 0, rightx = 0, righty = 0}
  self.pressedActions = {}
  self.events = {}
  return self
end

function C:emit(action, value)
  self.pressedActions[action] = value == nil and true or value
  self.events[#self.events + 1] = {action = action, value = value}
end

function C:consume(action)
  local value = self.pressedActions[action]
  self.pressedActions[action] = nil
  return value
end

function C:drainEvents()
  local out = self.events
  self.events = {}
  return out
end

function C:press(button)
  if type(button) ~= "string" then return false end
  button = button:lower()
  -- LÖVE sends one pressed event; the held state is kept only to prevent
  -- duplicate synthetic trigger presses from repeated axis samples.
  if self.buttons[button] then return false end
  self.buttons[button] = true
  if button == "lt" or button == "lefttrigger" then
    self:triggerPress("lefttrigger")
    return true
  elseif button == "rt" or button == "righttrigger" then
    self:emit("chat")
    return true
  end
  local action = C.BINDINGS[button]
  if action and action ~= "move" and action ~= "look" and action ~= "dpad" then
    self:emit(action)
    return true
  end
  return action ~= nil
end

function C:release(button)
  if type(button) ~= "string" then return false end
  button = button:lower()
  self.buttons[button] = nil
  if button == "lt" or button == "lefttrigger" then self.ltDown = false end
  if button == "rt" or button == "righttrigger" then self.rtDown = false end
  return true
end

function C:triggerPress(which)
  if which == "lefttrigger" then
    if self.ltDown then return false end
    self.ltDown = true
    self.flightPresses = self.flightPresses + 1
    self.flightTimer = self.flightWindow
    local needed = self.flightEnabled and 3 or 2
    if self.flightPresses >= needed then
      self.flightEnabled = not self.flightEnabled
      self.flightPresses = 0
      self.flightTimer = 0
      self:emit("flight_toggle", self.flightEnabled)
    end
    return true
  end
  return false
end

function C:axis(name, value)
  if type(name) ~= "string" or type(value) ~= "number" then return end
  name = name:lower()
  value = clamp(value, -1, 1)
  if name == "triggerleft" or name == "lefttrigger" then
    local active = value >= self.triggerThreshold
    if active and not self.ltDown then self:triggerPress("lefttrigger") end
    if not active then self.ltDown = false end
    return
  elseif name == "triggerright" or name == "righttrigger" then
    local active = value >= self.triggerThreshold
    if active and not self.rtDown then self:emit("chat") end
    self.rtDown = active
    return
  end
  if self.axes[name] ~= nil then self.axes[name] = self:stick(value) end
end

function C:stick(value)
  if math.abs(value) < self.deadzone then return 0 end
  local sign = value < 0 and -1 or 1
  return sign * (math.abs(value) - self.deadzone) / (1 - self.deadzone)
end

function C:update(dt)
  if self.flightPresses > 0 then
    self.flightTimer = self.flightTimer - math.max(0, dt or 0)
    if self.flightTimer <= 0 then
      self.flightPresses = 0
      self.flightTimer = 0
    end
  end
end

function C:move()
  return self.axes.leftx, -self.axes.lefty
end

function C:look()
  return self.axes.rightx, self.axes.righty
end

function C:hotbar(button)
  local index = ({
    dpleft = -1, dpright = 1, dpup = -1, dpdown = 1,
  })[button]
  if index then self:emit("hotbar", index); return true end
  return false
end

return C

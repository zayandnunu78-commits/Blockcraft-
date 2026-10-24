-- account/account_screen.lua
-- Reusable LÖVE UI for Blockcraft account login and registration.
-- Authentication is deliberately injected through opts.auth.

local Screen = {}
Screen.__index = Screen

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
local function trim(s) return (s or ""):gsub("^%s+", ""):gsub("%s+$", "") end

function Screen.new(opts)
  opts = opts or {}
  local self = setmetatable({
    auth = opts.auth,
    mode = "login",
    visible = false,
    focus = nil,
    busy = false,
    status = nil,
    statusKind = nil,
    values = {username = "", email = "", password = "", confirm = ""},
    cursor = 0,
    blink = 0,
    onAuthenticated = opts.onAuthenticated,
    onOffline = opts.onOffline,
    onClose = opts.onClose,
    fonts = {},
  }, Screen)
  return self
end

function Screen:setAuth(auth) self.auth = auth end
function Screen:openLogin() self.mode, self.visible = "login", true; self.status = nil; self.focus = "username" end
function Screen:openRegister() self.mode, self.visible = "register", true; self.status = nil; self.focus = "username" end
function Screen:close() self.visible, self.busy, self.focus = false, false, nil; if self.onClose then self.onClose() end end
function Screen:isOpen() return self.visible end

function Screen:font(size)
  size = math.floor(size)
  self.fonts[size] = self.fonts[size] or love.graphics.newFont(size)
  return self.fonts[size]
end

function Screen:layout()
  local w, h = love.graphics.getDimensions()
  local narrow = w < 560
  local panelW = math.min(520, w - (narrow and 24 or 48))
  local fieldH = narrow and 46 or 52
  local gap = narrow and 8 or 11
  local panelH = self.mode == "register" and (narrow and 548 or 586) or (narrow and 460 or 500)
  panelH = math.min(panelH, h - 18)
  local x, y = (w - panelW) / 2, math.max(9, (h - panelH) / 2)
  local fields = {}
  local function add(name, label, secret)
    fields[#fields + 1] = {name = name, label = label, secret = secret, x = x + 26,
      y = y + 112 + (#fields) * (fieldH + gap), w = panelW - 52, h = fieldH}
  end
  add("username", "USERNAME", false)
  if self.mode == "register" then add("email", "EMAIL", false) end
  add("password", "PASSWORD", true)
  if self.mode == "register" then add("confirm", "CONFIRM PASSWORD", true) end
  local last = fields[#fields]
  local buttonY = last.y + fieldH + (narrow and 17 or 22)
  return {w = w, h = h, panelX = x, panelY = y, panelW = panelW, panelH = panelH,
    fieldH = fieldH, fields = fields, buttonY = buttonY, narrow = narrow}
end

function Screen:fieldAt(x, y, layout)
  for _, f in ipairs(layout.fields) do
    if x >= f.x - 8 and x <= f.x + f.w + 8 and y >= f.y - 8 and y <= f.y + f.h + 8 then return f end
  end
end

function Screen:setFocus(name)
  self.focus = name
  self.cursor = #(self.values[name] or "")
  if love.keyboard and love.keyboard.setTextInput then love.keyboard.setTextInput(true) end
end

function Screen:message(text, kind)
  self.status, self.statusKind = text, kind or "error"
end

function Screen:complete(ok, result)
  self.busy = false
  if ok then
    self:message(self.mode == "login" and "Logged in successfully." or "Account created successfully.", "success")
    if self.onAuthenticated then self.onAuthenticated(result) end
  else
    self:message(tostring(result or "The request failed. Try again."), "error")
  end
end

function Screen:submitLogin()
  if self.busy then return end
  self.busy = true; self:message("Signing in…", "loading")
  if not self.auth then self:complete(false, "Authentication service is not connected yet."); return end
  self.auth:login(self.values.username, self.values.password, function(ok, result) self:complete(ok, result) end)
end

function Screen:submitRegister()
  if self.busy then return end
  self.busy = true; self:message("Creating account…", "loading")
  if not self.auth then self:complete(false, "Authentication service is not connected yet."); return end
  self.auth:register(self.values.username, self.values.email, self.values.password,
    self.values.confirm, function(ok, result) self:complete(ok, result) end)
end

function Screen:forgot()
  if self.busy then return end
  if self.mode ~= "login" then self:openLogin(); self:setFocus("email"); return end
  self.busy = true; self:message("Sending recovery request…", "loading")
  if not self.auth then self:complete(false, "Authentication service is not connected yet."); return end
  self.auth:resetPassword(self.values.email, function(ok, result) self:complete(ok, result) end)
end

function Screen:pressed(px, py)
  if not self.visible then return false end
  local l = self:layout()
  local f = self:fieldAt(px, py, l)
  if f then self:setFocus(f.name); return true end
  local buttonX, buttonW = l.panelX + 26, l.panelW - 52
  local buttonH = l.narrow and 44 or 48
  local function hit(y) return px >= buttonX and px <= buttonX + buttonW and py >= y and py <= y + buttonH end
  if hit(l.buttonY) then
    if self.mode == "login" then self:submitLogin() else self:submitRegister() end
    return true
  end
  local secondaryY = l.buttonY + buttonH + 9
  if self.mode == "login" and hit(secondaryY) then self:openRegister(); return true end
  if self.mode == "register" and hit(secondaryY) then self:openLogin(); return true end
  local thirdY = secondaryY + buttonH + 8
  if self.mode == "login" and hit(thirdY) then self:forgot(); return true end
  local offlineY = self.mode == "login" and thirdY + buttonH + 8 or secondaryY + buttonH + 8
  if hit(offlineY) then
    self:message("Playing offline. Online account features are disabled.", "success")
    if self.onOffline then self.onOffline() end
    return true
  end
  if py >= l.panelY + l.panelH - 42 and px >= l.panelX + 20 and px <= l.panelX + 145 then
    self:close(); return true
  end
  return true
end

function Screen:textinput(text)
  if not self.visible or not self.focus or self.busy then return end
  local old = self.values[self.focus] or ""
  if #old < 96 then
    self.values[self.focus] = old:sub(1, self.cursor) .. text .. old:sub(self.cursor + 1)
    self.cursor = self.cursor + #text
  end
end

function Screen:keypressed(key)
  if not self.visible then return false end
  if key == "tab" then
    local order = self.mode == "login" and {"username", "password"} or {"username", "email", "password", "confirm"}
    local i = 1; for n, name in ipairs(order) do if name == self.focus then i = n end end
    self:setFocus(order[(i % #order) + 1]); return true
  end
  if key == "backspace" and self.focus and not self.busy then
    local s, c = self.values[self.focus] or "", self.cursor
    if c > 0 then self.values[self.focus] = s:sub(1, c - 1) .. s:sub(c + 1); self.cursor = c - 1 end
    return true
  end
  if key == "return" or key == "kpenter" then
    if self.mode == "login" then self:submitLogin() else self:submitRegister() end
    return true
  end
  if key == "escape" then self:close(); return true end
  return true
end

function Screen:update(dt)
  self.blink = self.blink + (dt or 0)
end

function Screen:drawButton(label, x, y, w, h, primary, disabled)
  local r, g, b = primary and 0.38 or 0.12, primary and 0.08 or 0.16, primary and 0.05 or 0.20
  if disabled then r, g, b = 0.10, 0.10, 0.12 end
  love.graphics.setColor(r, g, b, 0.98); love.graphics.rectangle("fill", x, y, w, h, 7, 7)
  love.graphics.setColor(primary and 1 or 0.75, primary and 0.82 or 0.78, primary and 0.55 or 0.82, 1)
  love.graphics.setLineWidth(2); love.graphics.rectangle("line", x, y, w, h, 7, 7)
  love.graphics.setFont(self:font(18)); love.graphics.printf(label, x, y + (h - self:font(18):getHeight()) / 2, w, "center")
end

function Screen:draw()
  if not self.visible then return end
  local l = self:layout()
  love.graphics.setColor(0.015, 0.02, 0.025, 0.82); love.graphics.rectangle("fill", 0, 0, l.w, l.h)
  love.graphics.setColor(0.035, 0.045, 0.055, 0.99); love.graphics.rectangle("fill", l.panelX, l.panelY, l.panelW, l.panelH, 10, 10)
  love.graphics.setColor(0.70, 0.48, 0.18, 1); love.graphics.setLineWidth(3); love.graphics.rectangle("line", l.panelX, l.panelY, l.panelW, l.panelH, 10, 10)
  love.graphics.setColor(1, 0.88, 0.55, 1); love.graphics.setFont(self:font(l.narrow and 25 or 31))
  love.graphics.printf(self.mode == "login" and "BLOCKCRAFT ACCOUNT" or "CREATE ACCOUNT", l.panelX + 18, l.panelY + 24, l.panelW - 36, "center")
  love.graphics.setColor(0.78, 0.82, 0.86, 1); love.graphics.setFont(self:font(14))
  local subtitle = self.mode == "login" and "Sign in to use your Blockcraft account" or "One account for Blockcraft 1 and Blockcraft 2"
  love.graphics.printf(subtitle, l.panelX + 18, l.panelY + 70, l.panelW - 36, "center")

  for _, f in ipairs(l.fields) do
    love.graphics.setFont(self:font(12)); love.graphics.setColor(0.72, 0.76, 0.80, 1); love.graphics.print(f.label, f.x, f.y - 17)
    local active = self.focus == f.name
    love.graphics.setColor(active and 0.12 or 0.07, active and 0.15 or 0.09, active and 0.19 or 0.11, 1)
    love.graphics.rectangle("fill", f.x, f.y, f.w, f.h, 5, 5)
    love.graphics.setColor(active and 1 or 0.45, active and 0.78 or 0.50, active and 0.35 or 0.55, 1)
    love.graphics.setLineWidth(active and 2 or 1); love.graphics.rectangle("line", f.x, f.y, f.w, f.h, 5, 5)
    local value = self.values[f.name] or ""
    if f.secret then value = string.rep("•", #value) end
    if value == "" then value = f.label == "EMAIL" and "you@example.com" or "Tap to enter" end
    local placeholder = self.values[f.name] == ""
    love.graphics.setFont(self:font(17)); love.graphics.setColor(placeholder and 0.45 or 0.92, placeholder and 0.50 or 0.94, placeholder and 0.55 or 0.96, 1)
    love.graphics.print(value, f.x + 14, f.y + (f.h - self:font(17):getHeight()) / 2)
  end

  local buttonH = l.narrow and 44 or 48
  local buttonX, buttonW = l.panelX + 26, l.panelW - 52
  self:drawButton(self.busy and "PLEASE WAIT..." or (self.mode == "login" and "LOG IN" or "CREATE ACCOUNT"), buttonX, l.buttonY, buttonW, buttonH, true, self.busy)
  local secondaryY = l.buttonY + buttonH + 9
  self:drawButton(self.mode == "login" and "CREATE ACCOUNT" or "BACK TO LOG IN", buttonX, secondaryY, buttonW, buttonH, false, false)
  if self.mode == "login" then
    local thirdY = secondaryY + buttonH + 8
    love.graphics.setFont(self:font(15)); love.graphics.setColor(0.95, 0.75, 0.38, 1)
    love.graphics.printf("Forgot Password?", buttonX, thirdY + 12, buttonW, "center")
    self:drawButton("PLAY OFFLINE", buttonX, thirdY + buttonH + 8, buttonW, buttonH, false, false)
  else
    self:drawButton("PLAY OFFLINE", buttonX, secondaryY + buttonH + 8, buttonW, buttonH, false, false)
  end

  if self.status then
    local ok = self.statusKind == "success"
    local loading = self.statusKind == "loading"
    love.graphics.setFont(self:font(13)); love.graphics.setColor(loading and 0.95 or (ok and 0.48 or 1), loading and 0.83 or (ok and 1 or 0.38), loading and 0.35 or (ok and 0.48 or 0.38), 1)
    love.graphics.printf((loading and "[ ... ]  " or "") .. self.status, l.panelX + 22, l.panelY + l.panelH - 68, l.panelW - 44, "center")
  end
  love.graphics.setFont(self:font(12)); love.graphics.setColor(0.60, 0.65, 0.70, 1)
  love.graphics.print("ESC: close", l.panelX + 22, l.panelY + l.panelH - 25)
end

return Screen

-- ============================================================
-- mpmenu.lua - the MULTIPLAYER screen (state "multiplayer").
-- Reached from the main menu. Layout is computed from the screen size so it fits
-- a phone held sideways (the on-screen keyboard covers the bottom, the text boxes
-- are at the top).
--
--   main mode : player name and server settings
--   worlds mode: separate saved-world screen, creation, and invite-code joining
--   pin mode  : asks for the parent code before safe mode can be turned OFF
--   help mode : the "Multiplayer is not connecting?" tips screen
-- ============================================================
local gs = require "gamestate"
local P = require "net.protocol"
local safety = require "net.safety"
local session = require "net.session"
local config = require "net.config"
local catalog = require "net.world_catalog"

local M = {}
local fonts = {}
local mode = "main"        -- "main" | "pin" | "help" | "worlds" | "create" | "join"
local focus = nil          -- name of the text box being typed in
local code, pin, pinMessage = "", "", nil
local worldName, worlds, worldPage = "My World", {}, 1

-- ---------- "Multiplayer is not connecting?" help ----------
-- The owner's address comes from net/config.lua (reportEmail). The game never sends
-- email itself and never collects anyone's address: the button only opens the player's
-- OWN email app with a ready-made message, and the player decides whether to send it.
local helpNote = nil -- shown under the tips (e.g. when no email app could be opened)

local function ownerEmail()
  local e = config.reportEmail
  if type(e) == "string" and e:match("^[%w%.%%%+%-_]+@[%w%.%-]+%.%a+$") then return e end
end

local function helpText()
  local last = ownerEmail()
    and "5. Still stuck? Tap Email the server owner and send the message. Under 9? Ask a grown-up to send it."
    or "5. Still stuck? Ask whoever runs the server to check that it is turned on."
  return table.concat({
    "Try these, in order:",
    "",
    "1. Check the server address. Use numbers and dots only, with no spaces.",
    "2. Check your internet. Try switching between Wi-Fi and mobile data. School and public Wi-Fi often block games.",
    "3. Joining a friend? They create a cloud world, then share its 12-character invite code. Type it exactly.",
    "4. Everyone needs the same game version and the same mods.",
    last,
  }, "\n") .. (helpNote and ("\n\n" .. helpNote) or "")
end

local function urlEncode(str)
  return (str:gsub("[^%w%-_%.~]", function(c) return ("%%%02X"):format(c:byte()) end))
end

local function font(size)
  size = math.floor(size)
  fonts[size] = fonts[size] or love.graphics.newFont(size)
  return fonts[size]
end

local function inside(r, px, py)
  return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function setFocus(name)
  focus = name
  pcall(love.keyboard.setTextInput, name ~= nil)
end

function M.enter()
  mode, pin, pinMessage = "main", "", nil
  worldName = "My World"
  setFocus(nil)
  session.clearRetry()
  session.status = nil
  if safety.server == "" then safety.server = config.server or "" end
end

function M.enterWorlds()
  mode, pin, pinMessage = "worlds", "", nil
  worldName = "My World"
  worldPage = 1
  setFocus(nil)
  session.clearRetry()
  session.status = nil
  if safety.server == "" then safety.server = config.server or "" end
  gs.set("worlds")
end

-- ---------- what is on screen ----------
local function layout()
  local w, h = love.graphics.getDimensions()
  local bw, rh, gap = math.min(440, w - 30), math.max(38, math.min(46, h * 0.09)), 8
  local x = (w - bw) / 2
  local y = h * 0.2
  local half = (bw - gap) / 2
  local L = {w = w, h = h, boxes = {}, buttons = {}}

  local function box(name, label, value, bx, by, bwid, secret)
    L.boxes[#L.boxes + 1] = {name = name, label = label, value = value, secret = secret,
                             x = bx, y = by, w = bwid, h = rh}
  end
  local function button(label, fn, bx, by, bwid, enabled)
    L.buttons[#L.buttons + 1] = {label = label, fn = fn, x = bx, y = by, w = bwid, h = rh,
                                 enabled = enabled ~= false}
  end

  if mode == "pin" then
    L.prompt = safety.hasPin() and "Enter the parent code to turn safe mode off."
               or "Players under 9 need someone 9 or older to do this step. Choose a 4-number parent code. It is needed to turn safe mode off."
    L.promptY = y
    box("pin", "Parent code", pin, x, y + 84, bw, true)
    button("OK", M.confirmPin, x, y + 84 + rh + gap, half)
    button("Cancel", function() mode, pin, pinMessage = "main", "", nil; setFocus(nil) end,
           x + half + gap, y + 84 + rh + gap, half)
    L.statusY = y + 84 + 2 * (rh + gap)
    return L
  end

  if mode == "help" then
    local hbw = math.min(640, w - 30)
    local hx = (w - hbw) / 2
    -- start higher than the other screens: the tips need room on a short phone screen
    L.helpText, L.helpX, L.helpY, L.helpW = helpText(), hx, math.max(52, h * 0.16), hbw
    local by = h - rh - 14
    if ownerEmail() then -- Back (30%) + Email (70%) on one row, so the tips keep their room
      button("Back", M.closeHelp, hx, by, hbw * 0.3 - gap / 2)
      button("Email the server owner", M.emailOwner, hx + hbw * 0.3 + gap / 2, by, hbw * 0.7 - gap / 2)
    else
      button("Back", M.closeHelp, hx, by, hbw)
    end
    return L
  end

  local busy = session.active()
  if mode == "worlds" then
    worlds = catalog.list()
    L.title = "WORLDS"
    L.prompt, L.promptY = "Create a cloud world, join with an invite code, or pick one you have saved.", y
    y = y + 38
    L.listTitle, L.listTitleY = "SAVED WORLDS", y
    y = y + 26
    local rows = math.max(1, math.min(4, math.floor((h - 305) / (rh + gap))))
    local pages = math.max(1, math.ceil(#worlds / rows))
    worldPage = math.max(1, math.min(worldPage, pages))
    local first = (worldPage - 1) * rows + 1
    if #worlds == 0 then
      L.empty, L.emptyY = "No saved cloud worlds on this device yet.", y
      y = y + rh + gap
    else
      for i = first, math.min(#worlds, first + rows - 1) do
        local item = worlds[i]
        button(item.name .. "  [" .. item.code .. "]", function() M.joinSaved(item) end,
               x, y, bw, not busy)
        y = y + rh + gap
      end
    end
    if pages > 1 then
      button("Previous", function() worldPage = math.max(1, worldPage - 1) end, x, y, half)
      button("Next", function() worldPage = math.min(pages, worldPage + 1) end,
             x + half + gap, y, half)
      y = y + rh + gap
    end
    button("Create New World", M.showCreate, x, y, half, not busy)
    button("Join by Code", M.showJoin, x + half + gap, y, half, not busy)
    y = y + rh + gap
    if session.canRetry() then
      button("Retry", session.retry, x, y, half)
      button("Back to Menu", M.closeWorlds, x + half + gap, y, half)
    elseif busy then
      button("Cancel Connection", M.closeWorlds, x, y, bw)
    else
      button("Back to Menu", M.closeWorlds, x, y, bw)
    end
    L.statusY = y + rh + gap
    return L
  end

  if mode == "create" then
    L.title = "CREATE WORLD"
    L.prompt, L.promptY = "Create a persistent shared world. Anyone with its invite code can join and edit.", y
    box("worldName", "World name (1-24 characters)", worldName, x, y + 48, bw)
    y = y + 48 + rh + gap
    button("Create Cloud World", M.host, x, y, half, not busy)
    button("Back to Worlds", M.closeSubmenu, x + half + gap, y, half)
    L.statusY = y + rh + gap
    return L
  end

  if mode == "join" then
    L.title = "JOIN GAME"
    L.prompt, L.promptY = "Enter the 12-character invite code shared by the world creator.", y
    box("code", "World invite code", code, x, y + 48, bw)
    y = y + 48 + rh + gap
    button("Join Game", M.join, x, y, half, not busy)
    button("Back to Worlds", M.closeSubmenu, x + half + gap, y, half)
    L.statusY = y + rh + gap
    return L
  end

  -- main mode: player display name and server
  if safety.safe then
    L.nameText = "You are: " .. safety.presetName()
    L.nameRect = {x = x, y = y, w = bw * 0.58, h = rh}
  else
    box("custom", "Custom name (optional)", safety.custom, x, y, bw * 0.58 - gap / 2)
  end
  button("New Name", function() safety.newName() end, x + bw * 0.58 + gap / 2, y, bw * 0.42 - gap / 2, not busy)
  y = y + rh + gap
  box("server", "Server address", safety.server, x, y, bw)
  y = y + rh + gap
  button(safety.safe and "Safe Mode: ON" or "Safe Mode: OFF", M.toggleSafe,
         x, y, bw, not busy)
  y = y + rh + gap
  -- A failed attempt stays on this screen; retry or leave explicitly, never go offline.
  if session.canRetry() then
    button("Retry", session.retry, x, y, half)
    button("Back to Menu", M.back, x + half + gap, y, half)
  else
    button(busy and "Cancel" or "Back", M.back, x, y, bw * 0.3 - gap / 2)
    button("Multiplayer is not connecting?", M.showHelp, x + bw * 0.3 + gap / 2, y, bw * 0.7 - gap / 2)
  end
  L.statusY = y + rh + gap - 2
  return L
end

-- ---------- actions ----------
function M.showWorlds()
  return M.enterWorlds()
end

function M.showCreate()
  mode = "create"
  worldName = "My World"
  setFocus("worldName")
end

function M.showJoin()
  mode = "join"
  code = ""
  setFocus("code")
end

function M.closeSubmenu()
  mode = "worlds"
  setFocus(nil)
end

function M.closeWorlds()
  if session.active() then session.leave() end
  mode = "worlds"
  setFocus(nil)
  session.status = nil
  gs.set("menu")
end

function M.host()
  if not P.validWorldName(worldName) then
    session.status, session.statusOk = "World names may use 1-24 letters, numbers, spaces, _ or -.", false
    return
  end
  setFocus(nil)
  session.start("host", safety.server, nil, worldName)
  mode = "worlds"
end

function M.joinSaved(item)
  if not item or not P.validCode(item.code or "") then return end
  mode, code = "worlds", item.code
  setFocus(nil)
  session.start("join", safety.server, code)
end

function M.showHelp()
  mode, helpNote = "help", nil
  setFocus(nil)
end

-- opens the player's own email app with a ready-made message to the server owner
function M.emailOwner()
  local to = ownerEmail()
  if not to then return end
  local who = safety.safe and safety.presetName() or safety.custom
  local body = table.concat({
    "Hi! Blockcraft 1 multiplayer is not connecting for me.",
    "",
    "Game name: " .. ((who and who ~= "") and who or "(not set)"),
    "Server: " .. (safety.server ~= "" and safety.server or "(not set)"),
    "Message in the game: " .. ((session.status and session.status ~= "") and session.status or "(none)"),
    "",
    "Please email me when the server is back up. Thank you!",
  }, "\n")
  local url = "mailto:" .. to .. "?subject=" .. urlEncode("Blockcraft 1 is not connecting")
              .. "&body=" .. urlEncode(body)
  local ok, opened = pcall(love.system.openURL, url)
  if ok and opened then
    helpNote = "Your email app should open. Check the message, then send it."
  else
    helpNote = "Could not open an email app. Please send an email to " .. to .. " and say that Blockcraft 1 is not connecting."
  end
end

function M.closeHelp() mode = "main" end

function M.join()
  session.clearRetry()
  if #code ~= P.CODE_LENGTH or not P.validCode(code) then
    session.status, session.statusOk = "Type the " .. P.CODE_LENGTH .. "-character invite code from your friend.", false
    return
  end
  setFocus(nil)
  session.start("join", safety.server, code)
  mode = "worlds"
end

function M.toggleSafe()
  if safety.safe then
    mode, pin, pinMessage = "pin", "", nil
    setFocus("pin")
  else
    safety.turnOn()
    session.status, session.statusOk = "Safe mode is ON.", true
  end
end

function M.confirmPin()
  local ok, msg = safety.turnOff(pin)
  if ok then
    mode, pin, pinMessage = "main", "", nil
    setFocus(nil)
    session.status, session.statusOk = "Safe mode is OFF. Custom names are allowed.", true
  else
    pin, pinMessage = "", msg
  end
end

function M.back()
  if mode == "worlds" then
    M.closeWorlds()
    return
  elseif mode == "create" or mode == "join" then
    M.closeSubmenu()
    return
  end
  if session.active() then session.leave() end
  setFocus(nil)
  session.status = nil
  gs.set("menu")
end

-- ---------- input ----------
function M.pressed(px, py)
  local L = layout()
  for _, b in ipairs(L.buttons) do
    if b.enabled and inside(b, px, py) then b.fn() return end
  end
  for _, b in ipairs(L.boxes) do
    if inside(b, px, py) then setFocus(b.name) return end
  end
  setFocus(nil)
end

local filters = {
  server = {pattern = "[%w%.%-:]", max = 80},
  code = {pattern = "[%w]", max = P.CODE_LENGTH, upper = true},
  custom = {pattern = "[%w]", max = 12},
  worldName = {pattern = "[%w _%-]", max = 24},
  pin = {pattern = "%d", max = 4},
}

local function get(name)
  if name == "server" then return safety.server elseif name == "code" then return code
  elseif name == "custom" then return safety.custom
  elseif name == "worldName" then return worldName else return pin end
end
local function put(name, v)
  if name == "server" then safety.server = v elseif name == "code" then code = v
  elseif name == "custom" then safety.custom = v
  elseif name == "worldName" then worldName = v else pin = v end
end

function M.textinput(t)
  local f = focus and filters[focus]
  if not f then return end
  local v = get(focus)
  for ch in t:gmatch(".") do
    if f.upper then ch = ch:upper() end
    local allowed = ch:match(f.pattern)
    -- invite codes only use the letters/numbers in P.CODE_LETTERS (typos cannot be entered)
    if allowed and focus == "code" then allowed = P.CODE_LETTERS:find(ch, 1, true) end
    if allowed and #v < f.max then v = v .. ch end
  end
  put(focus, v)
end

-- returns true if the key was used here
function M.keypressed(key)
  if key == "escape" then
    if mode == "pin" then mode, pin, pinMessage = "main", "", nil; setFocus(nil)
    elseif mode == "help" then mode = "main"
    elseif mode == "worlds" then M.closeWorlds()
    elseif mode == "create" or mode == "join" then M.closeSubmenu()
    else M.back() end
    return true
  end
  if focus then
    if key == "backspace" then put(focus, get(focus):sub(1, -2)) return true end
    if key == "return" or key == "kpenter" then
      if mode == "pin" then M.confirmPin()
      elseif mode == "create" and focus == "worldName" then M.host()
      elseif mode == "join" and focus == "code" then M.join()
      else if focus == "custom" then safety.save() end setFocus(nil) end
      return true
    end
  end
  return false
end

-- ---------- drawing ----------
function M.draw()
  local L = layout()
  local w, h = L.w, L.h
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, w, h)

  love.graphics.setFont(font(math.max(24, math.min(46, h * 0.09))))
  love.graphics.setColor(0, 0, 0, 0.6)
  local title = L.title or "MULTIPLAYER"
  love.graphics.printf(title, 3, h * 0.04 + 3, w, "center")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(title, 0, h * 0.04, w, "center")
  love.graphics.setFont(font(14))
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.printf("Online only - an internet connection is required.", 0, h * 0.125, w, "center")
  love.graphics.setColor(1, 1, 1, 1)

  local bw = math.min(440, w - 30)
  local x = (w - bw) / 2

  if L.helpText then
    love.graphics.setFont(font(15))
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.printf(L.helpText, L.helpX, L.helpY, L.helpW, "left")
  end

  if L.prompt then
    love.graphics.setFont(font(17))
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(L.prompt, x, L.promptY, bw, "left")
  end

  if L.empty then
    love.graphics.setFont(font(16))
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf(L.empty, x, L.emptyY, bw, "center")
  end
  if L.listTitle then
    love.graphics.setFont(font(15))
    love.graphics.setColor(1, 1, 1, 0.65)
    love.graphics.printf(L.listTitle, x, L.listTitleY, bw, "left")
  end

  if L.nameText then
    local r = L.nameRect
    love.graphics.setFont(font(18))
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.printf(L.nameText, r.x, r.y + (r.h - font(18):getHeight()) / 2, r.w, "left")
  end

  for _, b in ipairs(L.boxes) do
    local active = (focus == b.name)
    love.graphics.setColor(0.08, 0.08, 0.1, 0.95)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8, 8)
    love.graphics.setColor(1, active and 0.9 or 1, active and 0.2 or 1, active and 1 or 0.5)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 8, 8)
    love.graphics.setFont(font(18))
    local text = b.value
    if b.secret then text = ("*"):rep(#text) end
    if text == "" and not active then
      love.graphics.setColor(1, 1, 1, 0.4)
      love.graphics.printf(b.label, b.x + 10, b.y + (b.h - font(18):getHeight()) / 2, b.w - 20, "left")
    else
      love.graphics.setColor(1, 1, 1, 1)
      local shown = text .. ((active and love.timer.getTime() % 1 < 0.5) and "|" or "")
      love.graphics.printf(shown, b.x + 10, b.y + (b.h - font(18):getHeight()) / 2, b.w - 20, "left")
    end
  end

  local mx, my = love.mouse.getPosition()
  for _, b in ipairs(L.buttons) do
    local hot = gs.desktop and b.enabled and inside(b, mx, my)
    love.graphics.setColor(hot and 0.3 or 0.15, hot and 0.3 or 0.15, hot and 0.38 or 0.18, 0.92)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 10, 10)
    love.graphics.setColor(1, 1, 1, b.enabled and (hot and 1 or 0.6) or 0.2)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 10, 10)
    -- shrink long labels so they fit inside the button
    local size = 19
    while size > 12 and font(size):getWidth(b.label) > b.w - 14 do size = size - 1 end
    love.graphics.setFont(font(size))
    love.graphics.setColor(1, 1, 1, b.enabled and 1 or 0.35)
    love.graphics.printf(b.label, b.x, b.y + (b.h - font(size):getHeight()) / 2, b.w, "center")
  end

  -- status line
  love.graphics.setFont(font(15))
  local text, ok
  if mode == "pin" then
    local locked = safety.lockedFor()
    text, ok = pinMessage, false
    if locked > 0 then text = ("Too many tries. Wait %d seconds."):format(locked) end
  elseif session.status and session.status ~= "" then
    text, ok = session.status, session.statusOk
  elseif mode == "worlds" then
    text, ok = "Invite codes are stored on this device. Share a code only with people you trust.", true
  else
    text, ok = safety.safe and "Safe mode is ON: no chat, preset names, shared worlds use invite codes."
                           or "Safe mode is OFF: custom names are allowed. Cloud worlds are shared by invite code.", true
  end
  if mode == "help" then text = nil end
  if text then
    if ok then love.graphics.setColor(0.7, 1, 0.7, 1) else love.graphics.setColor(1, 0.55, 0.55, 1) end
    love.graphics.printf(text, x, L.statusY, bw, "left")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return M

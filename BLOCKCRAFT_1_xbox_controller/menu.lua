-- Menu screens: main menu, pause menu and settings.
-- Everything is laid out from the screen size, so it works on phones and desktop.
local settings = require "settings"
local gs = require "gamestate"
local install = require "modsys.install"
local mpmenu = require "net.mpmenu"
local music = require "music"
local session = require "net.session"
local save = require "save"
local worldgen = require "worldgen"
local player = require "player"
local chunks = require "chunks"
local hotbar = require "hotbar"
local health = require "health"

local M = {}
local TITLE = "BLOCKCRAFT 1" -- <-- put your game's name here
local fonts = {}
local active -- the slider being dragged

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function font(size)
  size = math.floor(size)
  fonts[size] = fonts[size] or love.graphics.newFont(size)
  return fonts[size]
end

local function inside(it, px, py)
  return px >= it.x and px <= it.x + it.w and py >= it.y and py <= it.y + it.h
end

function M.back()
  settings.save()
  gs.set(gs.settingsFrom)
end

-- text on the Add Mods screen (changes with the platform)
local function modsText()
  if gs.desktop then
    return "Drag a .mcpack, .mcaddon, .zip or .jar file onto the game window. "
        .. "It loads right away. Or press Open Folder to copy files in yourself, then Load New."
  end
  return "Share or \"Open in\" a .mcpack, .mcaddon, .zip or .jar file with this game "
      .. "(for example from the Files app). It loads right away."
end

-- Settings > Add Mods. On an iPhone this opens the Files app straight away;
-- everywhere else it opens the Add Mods screen.
local function addModsPressed()
  if install.canOpenFiles() and install.openFiles() then return end
  gs.set("mods")
end

local function modsTextWidth(w) return math.min(520, w - 40) end

-- how tall the text block on the Add Mods screen is (buttons are placed under it)
local function modsBodyHeight(w)
  local f = font(16)
  local _, lines = f:getWrap(modsText(), modsTextWidth(w))
  local statusLines = 0
  if install.status then
    local _, sl = f:getWrap(install.status, modsTextWidth(w))
    statusLines = #sl + 1
  end
  return (#lines + statusLines) * f:getHeight() + 24
end

local function toggleMusic()
  settings.music = not settings.music
  music.setEnabled(settings.music)
  settings.save()
end

-- builds the list of buttons / sliders for a screen
local function items(screen)
  local w, h = love.graphics.getDimensions()
  local bw, bh, gap = math.min(340, w - 40), 54, 16
  local x = (w - bw) / 2
  local y = (screen == "settings") and h * 0.22 or h * 0.4
  if screen == "mods" then y = h * 0.25 + modsBodyHeight(w) end
  local list = {}

  -- two half-width buttons side by side (saves height on a phone held sideways)
  local function buttonRow(l1, f1, l2, f2)
    local half = (bw - gap) / 2
    list[#list + 1] = {kind = "button", label = l1, fn = f1, x = x, y = y, w = half, h = bh}
    list[#list + 1] = {kind = "button", label = l2, fn = f2, x = x + half + gap, y = y,
                       w = half, h = bh}
    y = y + bh + gap
  end

  local function button(label, fn)
    list[#list + 1] = {kind = "button", label = label, fn = fn,
                       x = x, y = y, w = bw, h = bh}
    y = y + bh + gap
  end
  local function slider(label, key, min, max, step, fmt)
    list[#list + 1] = {kind = "slider", label = label, key = key, min = min,
                       max = max, step = step, fmt = fmt,
                       x = x, y = y + 26, w = bw, h = 26}
    y = y + 82
  end

  if screen == "menu" then
    buttonRow("Normal Worlds", function() gs.set("localworlds") end,
              "Multiplayer", function() mpmenu.enter(); gs.set("multiplayer") end)
    buttonRow("Settings", function() gs.set("settings") end,
              "Account", function()
                if M.onAccount then M.onAccount() else gs.set("account") end
              end)
    button("Quit", function() love.event.quit() end)
  elseif screen == "paused" then
    y = h * 0.3 -- higher than the title screen, so three rows also fit a short phone screen
    button("Resume", function() gs.set("playing") end)
    buttonRow("Save to Cloud", session.saveNow, "Settings", function() gs.set("settings") end)
    button("Main Menu", function()
      if M.onLeave then M.onLeave() end -- leaves an online game, if there is one
      gs.set("menu")
    end)
  elseif screen == "settings" then
    slider("Field of View", "fov", 60, 110, 1, "%d°")
    slider("Mouse Sensitivity", "sensitivity", 0.2, 3.0, 0.05, "x%.2f")
    buttonRow("Add Mods", addModsPressed, "Load New", install.rescan)
    button("Back", M.back)
  elseif screen == "mods" then
    local openLabel, openFn
    if gs.desktop then openLabel, openFn = "Open Folder", install.openFolder
    elseif install.canOpenFiles() then openLabel, openFn = "Open Files", install.openFiles end
    if openFn then buttonRow(openLabel, openFn, "Load New", install.rescan)
    else button("Load New", install.rescan) end
    button("Back", function() gs.set("settings") end)
  end
  -- music on/off: a small button in the top right corner of every menu
  list[#list + 1] = {kind = "button", label = settings.music and "Music: On" or "Music: Off",
                     fn = toggleMusic, x = w - 122, y = 10, w = 112, h = 34}
  return list
end

local function setSlider(it, px)
  local t = clamp((px - it.x) / it.w, 0, 1)
  local v = it.min + t * (it.max - it.min)
  v = clamp(math.floor(v / it.step + 0.5) * it.step, it.min, it.max)
  settings[it.key] = v
  if it.key == "fov" then settings.apply() end
end

-- click / tap
function M.pressed(px, py)
  if gs.current == "multiplayer" or gs.current == "worlds" then
    return mpmenu.pressed(px, py)
  elseif gs.current == "localworlds" then
    local w, h = love.graphics.getDimensions()
    local bw, bh, gap = math.min(420, w - 40), 56, 14
    local x, y = (w - bw) / 2, h * 0.30
    for slot = 1, 3 do
      if px >= x and px <= x + bw and py >= y and py <= y + bh then
        local info = save.info(slot)
        if info.state == "saved" then
          local ok, err = save.loadSlot(slot)
          if ok then gs.set("playing") else save.message(err, false) end
        else
          worldgen.generate()
          player.spawn(); hotbar.load(); health.reset()
          save.attach(slot)
          -- Persist the new world immediately; waiting for the 30-second
          -- autosave made a quick leave appear to lose the world.
          save.saveNow(false)
          gs.set("playing")
        end
        return
      end
      y = y + bh + gap
    end
    if px >= 20 and px <= 160 and py >= h - 70 then gs.set("menu") end
    return
  end
  for _, it in ipairs(items(gs.current)) do
    if it.kind == "button" then
      if inside(it, px, py) then
        it.fn()
        return
      end
    elseif px >= it.x - 14 and px <= it.x + it.w + 14
        and py >= it.y - 14 and py <= it.y + it.h + 14 then
      active = it
      setSlider(it, px)
      return
    end
  end
end

-- drag
function M.moved(px, py)
  if active then setSlider(active, px) end
end

-- let go
function M.released()
  if active then
    active = nil
    settings.save()
  end
end

function M.draw(screen)
  if screen == "multiplayer" or screen == "worlds" then return mpmenu.draw() end
  if screen == "localworlds" then
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, 0.62); love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setColor(1,1,1,1); love.graphics.setFont(font(clamp(h * 0.085, 26, 48)))
    love.graphics.printf("NORMAL WORLDS", 0, h * 0.09, w, "center")
    local bw, bh, gap = math.min(420, w - 40), 56, 14
    local x, y = (w - bw) / 2, h * 0.30
    for slot = 1, 3 do
      local info = save.info(slot)
      local label = info.state == "saved" and ("World " .. slot .. " - Continue") or ("World " .. slot .. " - Create")
      if info.state == "damaged" then label = "World " .. slot .. " - Damaged (overwrite)" end
      love.graphics.setColor(0.12, 0.18, 0.22, 0.95); love.graphics.rectangle("fill", x, y, bw, bh, 9, 9)
      love.graphics.setColor(1,1,1,1); love.graphics.rectangle("line", x, y, bw, bh, 9, 9)
      love.graphics.setFont(font(20)); love.graphics.printf(label, x, y + 16, bw, "center")
      y = y + bh + gap
    end
    love.graphics.setFont(font(16)); love.graphics.setColor(1,1,1,0.85)
    love.graphics.printf("Saved locally on this device — no internet required", 10, h - 88, w - 20, "center")
    love.graphics.setColor(0.15,0.18,0.22,0.95); love.graphics.rectangle("fill", 20, h - 54, 120, 40, 7, 7)
    love.graphics.setColor(1,1,1,1); love.graphics.printf("Back", 20, h - 44, 120, "center")
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, screen == "menu" and 0.35 or 0.55)
  love.graphics.rectangle("fill", 0, 0, w, h)

  local titles = {menu = TITLE, paused = "PAUSED", settings = "SETTINGS", mods = "ADD MODS"}
  love.graphics.setFont(font(clamp(h * 0.12, 28, 64)))
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(titles[screen], 3, h * 0.08 + 3, w, "center")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.printf(titles[screen], 0, h * 0.08, w, "center")

  if screen == "mods" then
    local f = font(16)
    love.graphics.setFont(f)
    local tw = modsTextWidth(w)
    local tx, ty = (w - tw) / 2, h * 0.25
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.printf(modsText(), tx, ty, tw, "left")
    if install.status then
      local _, lines = f:getWrap(modsText(), tw)
      local sy = ty + (#lines + 1) * f:getHeight()
      if install.statusOk then love.graphics.setColor(0.5, 1, 0.5, 1)
      else love.graphics.setColor(1, 0.5, 0.5, 1) end
      love.graphics.printf(install.status, tx, sy, tw, "left")
    end
  end

  local mx, my = love.mouse.getPosition()
  for _, it in ipairs(items(screen)) do
    if it.kind == "button" then
      local hot = gs.desktop and inside(it, mx, my)
      love.graphics.setColor(hot and 0.3 or 0.15, hot and 0.3 or 0.15,
                             hot and 0.38 or 0.18, 0.92)
      love.graphics.rectangle("fill", it.x, it.y, it.w, it.h, 10, 10)
      love.graphics.setColor(1, 1, 1, hot and 1 or 0.6)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", it.x, it.y, it.w, it.h, 10, 10)
      -- shrink long labels (a world's date, for example) until they fit in the button
      local size = 22
      while size > 12 and font(size):getWidth(it.label) > it.w - 12 do size = size - 1 end
      local f = font(size)
      love.graphics.setFont(f)
      if it.danger then love.graphics.setColor(1, 0.45, 0.45, 1) else love.graphics.setColor(1, 1, 1, 1) end
      love.graphics.printf(it.label, it.x, it.y + (it.h - f:getHeight()) / 2, it.w, "center")
    else
      local v = settings[it.key]
      local t = (v - it.min) / (it.max - it.min)
      love.graphics.setFont(font(18))
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.printf(it.label .. ": " .. string.format(it.fmt, v),
                           it.x, it.y - 26, it.w, "left")
      local cy = it.y + it.h / 2
      love.graphics.setColor(1, 1, 1, 0.25)
      love.graphics.rectangle("fill", it.x, cy - 3, it.w, 6, 3, 3)
      love.graphics.setColor(1, 0.9, 0.2, 1)
      love.graphics.rectangle("fill", it.x, cy - 3, it.w * t, 6, 3, 3)
      love.graphics.circle("fill", it.x + it.w * t, cy, 13)
    end
  end


  if screen == "menu" then
    love.graphics.setFont(font(14))
    love.graphics.setColor(1, 1, 1, 0.7)
    local hint = gs.desktop
      and "WASD move  |  Mouse look  |  Click break/place  |  1-9 hotbar  |  Esc pause"
      or "Left side: move  |  Right side: look  |  Tap: break/place"
    love.graphics.printf(hint, 0, h - 28, w, "center")
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return M

-- Server mode:  love . --server   (no graphics; see SERVER_SETUP.md)
for _, a in pairs(arg or {}) do
  if a == "--server" then
    require "net.server_main"
    return
  end
end

-- ============================================================
-- main.lua  (state machine: menu / worlds / multiplayer / playing / paused / settings)
--
-- How it fits together:
--   gamestate.lua  the state variable + gameState.set() (also handles mouse lock)
--   menu.lua       draws and handles the menu / pause / settings screens
--   settings.lua   FOV + mouse sensitivity (saved to a file)
--   everything else is your game and only runs while state == "playing"
-- ============================================================
local g3d = require "g3d"
local world = require "world"
local worldgen = require "worldgen"
local mesher = require "mesher"
local chunks = require "chunks"
local save = require "save"
local health = require "health"
local music = require "music"
local player = require "player"
local input = require "input"
local raycast = require "raycast"
local hud = require "hud"
local hotbar = require "hotbar"
local gameState = require "gamestate"
local menu = require "menu"
local session = require "net.session"
local safety = require "net.safety"
local mpmenu = require "net.mpmenu"
local settings = require "settings"
local modloader = require "modsys.loader"
local bedrock = require "modsys.bedrock"
local install = require "modsys.install"
local events = require "modsys.events"
local json = require "json"
local blocks = require "blocks"
local textures = require "textures"
local registeredBlocks = require "registeredblocks" -- central table of custom blocks
local AuthInterface = require "account.auth_interface"
local AccountScreen = require "account.account_screen"
local FirebaseRest = require "account.firebase_rest"

local target
local orbit = 0
local toastFont -- created on first use
local account
local firebaseAuth

-- ============================================================
-- BEDROCK BLOCKS (loose .json files, .mcpack / .mcaddon, unzipped packs)
-- The loader lives in modsys/bedrock.lua - read the diagram at the top of that file.
-- ============================================================
local function scanBedrockBlocks()
  bedrock.init()
  bedrock.scan()
end

-- Says what is in mods/ and why nothing new loaded (so "nothing happened" is never a mystery).
local function describeModsFolder()
  if not love.filesystem.getInfo("mods") then
    return "No 'mods' folder found. Create a folder named mods next to main.lua, or in: "
        .. love.filesystem.getSaveDirectory()
  end
  local items = love.filesystem.getDirectoryItems("mods")
  table.sort(items)
  if #items == 0 then return "The mods folder is empty. Add a mod file to it first." end
  local okExt = {mcpack = true, mcaddon = true, zip = true, jar = true, json = true, png = true}
  local done, ignored = {}, {}
  for _, f in ipairs(items) do
    local first = f:sub(1, 1)
    local info = love.filesystem.getInfo("mods/" .. f)
    local ext = (f:match("%.([^%.]+)$") or ""):lower()
    if first == "." or first == "_" then
      ignored[#ignored + 1] = f .. " (name starts with . or _ = disabled)"
    elseif info and info.type == "file" and not okExt[ext] then
      ignored[#ignored + 1] = f .. " (type not supported)"
    else
      local inf = bedrock.info[f]
      local detail
      if inf and inf.failed then detail = "could not be opened (damaged file?)"
      elseif inf and (ext == "mcpack" or ext == "mcaddon" or (info and info.type == "directory")) then
        if inf.packs == 0 then detail = "no pack found inside"
        elseif inf.files == 0 then detail = "no block files (items/mobs aren't supported)"
        elseif inf.blocks == 0 then detail = ("0 blocks, skipped: %s"):format((inf.err or "?"):sub(1, 60))
        else detail = ("%d block%s"):format(inf.blocks, inf.blocks == 1 and "" or "s") end
      end
      done[#done + 1] = detail and (f .. " (" .. detail .. ")") or f
    end
  end
  local text = ("Nothing new to load. mods has %d item(s)"):format(#items)
  if #done > 0 then text = text .. ", already loaded: " .. table.concat(done, ", ", 1, math.min(#done, 4)) end
  if #ignored > 0 then text = text .. ". Ignored: " .. table.concat(ignored, "; ", 1, math.min(#ignored, 2)) end
  return text
end

-- Load whatever is NEW in mods/ while the game is running (used by Add Mods).
-- Returns a message for the player and true/false for success.
local function reloadMods()
  local before = #blocks
  local okL, newMods, newFailed = pcall(modloader.loadAll)
  local okB, bErr = pcall(scanBedrockBlocks)
  local added = #blocks - before

  local text, ok
  if added > 0 then
    -- put the first new block in the selected hotbar slot so it can be used right away
    hotbar.slots[hotbar.selected] = before + 1
    text = ("Loaded %d new block%s. Tap the selected hotbar slot to switch blocks."):format(
      added, added == 1 and "" or "s")
    ok = true
  elseif okL and (newMods or 0) > 0 then
    text = ("Loaded %d new mod%s (no new blocks)."):format(newMods, newMods == 1 and "" or "s")
    ok = true
  else
    text = describeModsFolder()
    ok = true
  end
  -- problems: show the newest one (the console has the rest)
  if not okL then
    text, ok = "Mod loader error: " .. tostring(newMods), false
  elseif not okB then
    text, ok = "Bedrock loader error: " .. tostring(bErr), false
  elseif (newFailed or 0) > 0 then
    local f = modloader.failed[#modloader.failed]
    text = text .. (" %d failed: %s"):format(newFailed, tostring(f.error):sub(1, 90))
    ok = false
  end
  return text, ok
end
install.reload = reloadMods

-- ---------------- hold-to-break (uses destroyTime) ----------------
-- Blocks with destroy_time > 0 must be held with the left mouse button.
-- (On phones, taps still break instantly: there is no "hold" on a tap.)
local breaking -- {x, y, z, t} progress on the block being mined

local function updateBreaking(dt)
  if not (gameState.desktop and love.mouse.isDown(1) and target) then
    breaking = nil
    return
  end
  local x, y, z = target[1], target[2], target[3]
  local def = registeredBlocks.byId[world.get(x, y, z)]   -- raycast result -> registered block
  if not def or def.destroyTime <= 0 or z <= 0 then breaking = nil; return end
  if not breaking or breaking.x ~= x or breaking.y ~= y or breaking.z ~= z then
    breaking = {x = x, y = y, z = z, t = 0}               -- aiming at a new block: start over
  end
  breaking.t = breaking.t + dt
  if breaking.t >= def.destroyTime then
    local e = {x = x, y = y, z = z, block = def.id}
    if events.fire("block_break", e) then world.set(x, y, z, 0) end
    breaking = nil
  end
end

local function drawBreaking()
  if not breaking then return end
  local def = registeredBlocks.byId[world.get(breaking.x, breaking.y, breaking.z)]
  if not def then return end
  local w, h = love.graphics.getDimensions()
  local frac = math.min(1, breaking.t / def.destroyTime)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", w / 2 - 42, h / 2 + 22, 84, 10)
  love.graphics.setColor(1, 0.9, 0.2, 1)
  love.graphics.rectangle("fill", w / 2 - 40, h / 2 + 24, 80 * frac, 6)
  love.graphics.setColor(1, 1, 1, 1)
end

-- the menu shows the world behind it with a slowly circling camera
local function menuBackground()
  return gameState.current == "menu"
      or gameState.current == "account"
      or gameState.current == "worlds"
      or gameState.current == "localworlds"
      or gameState.current == "multiplayer"
      or ((gameState.current == "settings" or gameState.current == "mods")
          and gameState.settingsFrom == "menu")
end

-- ---------------- love.load ----------------
function love.load()
  love.graphics.setBackgroundColor(.5, .75, 1)
  settings.load()          -- read saved FOV / sensitivity / music
  music.init(settings.music) -- background music (music/ folder)
  safety.load()            -- multiplayer safe mode (starts ON), preset name, last server
  -- load mods BEFORE the world exists so their blocks/textures are ready.
  -- (pcall: a broken mod system must never stop the game from starting)
  local ok, err = pcall(function() modloader.init(); modloader.loadAll() end)
  if not ok then print("[modloader] crashed: " .. tostring(err)) end
  -- Bedrock-style mods/*.json blocks (also before the world exists)
  ok, err = pcall(scanBedrockBlocks)
  if not ok then print("[bedrock] crashed: " .. tostring(err)) end
  settings.apply()         -- push FOV into the camera
  -- phones get a shorter view distance than computers
  chunks.setViewDistance(gameState.desktop and 6 or 4)
  worldgen.generate()      -- world for the menu background
  player.spawn()
  hotbar.load()
  input.init()
  chunks.flush(player.x, player.y, player.z)
  events.fire("ready")     -- game is fully set up (hotbar, player, world exist)
  -- a short message on screen (the same one the mod installer uses)
  local function toast(text, ok) install.toast, install.toastTime, install.statusOk = text, 4, ok end
  session.message = toast
  firebaseAuth = FirebaseRest.new()
  local auth = AuthInterface.new(firebaseAuth)
  account = AccountScreen.new{
    auth = auth,
    onAuthenticated = function(sessionInfo)
      account:close()
      toast("Account session ready. Online account features are connected.", true)
      print("[account] authenticated", sessionInfo and sessionInfo.uid or "unknown")
    end,
    onOffline = function()
      account:close()
      gameState.set("localworlds")
      toast("Playing offline. No account login is required.", true)
    end,
    onClose = function()
      if gameState.current == "account" then gameState.set("menu") end
    end,
  }
  menu.onAccount = function()
    account:openLogin()
    gameState.set("account")
  end
  -- hearts: a fall of more than 3 blocks hurts; at 0 you wake up at the spawn point
  player.onFall = function(dist)
    health.damage(math.floor(dist - player.SAFE_FALL), "fall")
  end
  health.onDeath = function(source)
    player.spawn()
    health.reset()
    toast(source == "fall" and "You fell too far! Back at the spawn point."
                            or "Back at the spawn point.", false)
  end
  -- saving: the hooks save.lua needs from the rest of the game
  save.getView = function() return input.yaw, input.pitch end
  save.setView = function(yaw, pitch) input.yaw, input.pitch, input.touches = yaw, pitch, {} end
  save.message = toast
  menu.onLeave = function()                     -- pause menu "Main Menu"
    save.leave()                                -- save the world first
    session.leave()                             -- then leave the online game, if there is one
  end
  gameState.set("menu")    -- start on the title screen
end

-- ---------------- love.update ----------------
function love.update(dt)
  if firebaseAuth then firebaseAuth:update() end
  if gameState.current == "account" and account then account:update(dt) end
  if gameState.current == "playing" then
    input.update(dt)
    local fwd, str, jump = input.move()
    player.update(dt, fwd, str, jump, input.yaw, input.pitch)
    target = raycast.cast(player.x, player.y, player.z + player.eye,
                          input.yaw, input.pitch, 6)
    events.fire("update", dt)
    updateBreaking(dt)
    chunks.update(player.x, player.y, player.z) -- stream chunks in and out around the player
    save.update(dt)                             -- automatic save every 30 s if something changed
    health.update(dt)                           -- hearts heal by themselves
  elseif menuBackground() then
    orbit = orbit + dt * 0.15
    -- circle the spawn point (the world is endless; 0.5, 0.5 is the middle of the first block)
    local top = world.top(0, 0)
    g3d.camera.lookAt(0.5 + 26 * math.cos(orbit), 0.5 + 26 * math.sin(orbit), top + 12,
                      0.5, 0.5, top)
    chunks.update(0.5, 0.5, top)
  else
    -- "paused": the game is frozen, but changes from other players still need meshing
    mesher.update(player.x, player.y, player.z, chunks.meshBudget)
  end
  music.update()           -- the next song, when one ends
  session.update(dt)       -- online games (does nothing when offline)
  install.update(dt)
end

-- ---------------- love.draw ----------------
function love.draw()
  -- Reset both color and depth every frame. A stale depth buffer can make moving
  -- cameras leave disappearing geometry or flicker on some graphics drivers.
  local r, g, b, a = love.graphics.getBackgroundColor()
  love.graphics.clear(r, g, b, a, true, true)
  -- the world is drawn in every state (menus dim it on top)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setDepthMode("lequal", true)
  mesher.draw()
  session.draw3d()         -- other players (online only)
  if gameState.current == "playing" and target then
    mesher.highlight(target[1], target[2], target[3])
  end
  love.graphics.setDepthMode()

  if gameState.current == "playing" then
    hud.draw(input)
    session.drawHud()
    drawBreaking()
    -- Dispatch the documented mod HUD hook after the native HUD so mods can draw overlays.
    events.fire("draw_hud", require("modsys.api").gfx)
  elseif gameState.current == "account" then
    account:draw()
  else
    menu.draw(gameState.current)
    if gameState.current == "menu" then
      love.graphics.setColor(1, 1, 1, 0.8)
      love.graphics.print(modloader.summary(), 10, love.graphics.getHeight() - 24)
    end
  end

  -- message after a mod file was added (shown on any screen for a few seconds)
  if install.toast and install.toastTime > 0 then
    local w, h = love.graphics.getDimensions()
    toastFont = toastFont or love.graphics.newFont(16)
    local f = toastFont
    local tw = math.min(520, w - 40)
    local _, lines = f:getWrap(install.toast, tw)
    local th = #lines * f:getHeight() + 16
    love.graphics.setFont(f)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", (w - tw) / 2 - 8, 12, tw + 16, th, 8, 8)
    if install.statusOk then love.graphics.setColor(0.5, 1, 0.5, 1)
    else love.graphics.setColor(1, 0.5, 0.5, 1) end
    love.graphics.printf(install.toast, (w - tw) / 2, 20, tw, "left")
    love.graphics.setColor(1, 1, 1, 1)
  end
end

-- ---------------- love.keypressed ----------------
function love.keypressed(key)
  local state = gameState.current
  if state == "account" then
    account:keypressed(key)
  elseif state == "multiplayer" or state == "worlds" then
    mpmenu.keypressed(key)
  elseif state == "playing" then
    -- Let mods handle their own keyboard controls first (FNAF mode uses F/M/G/H/R).
    -- A mod can return false to consume the key and prevent normal gameplay input.
    if not events.fire("key", key) then return end
    if key == "escape" then gameState.set("paused")
    elseif session.keypressed(key) then -- emote keys Z X C V B (online)
    else input.keypressed(key) end
  elseif key == "escape" then
    if state == "paused" then gameState.set("playing")
    elseif state == "settings" then menu.back()
    elseif state == "mods" then gameState.set("settings") end
  end
end

-- ---------------- mouse (desktop) ----------------
-- Touch screens also send mouse events (istouch = true); those are ignored
-- here so a tap is never handled twice. Taps come in through love.touch*.
function love.mousepressed(x, y, button, istouch)
  if gameState.current == "playing" then
    if not events.fire("pointer_pressed", x, y, button) then return end
    input.mousepressed(x, y, button, istouch)
  elseif gameState.current == "account" and not istouch and button == 1 then
    account:pressed(x, y)
  elseif not istouch and button == 1 then
    menu.pressed(x, y)
  end
end

function love.mousemoved(x, y, dx, dy, istouch)
  if gameState.current == "playing" then
    input.mousemoved(x, y, dx, dy, istouch)
  elseif not istouch then
    menu.moved(x, y)
  end
end

function love.mousereleased(x, y, button, istouch)
  if gameState.current ~= "playing" and not istouch then menu.released() end
end

function love.wheelmoved(x, y)
  if gameState.current == "playing" then input.wheelmoved(x, y) end
end

-- ---------------- Xbox-style controller ----------------
-- The exact bindings live in xbox_controller.lua. Prefer LÖVE's standardized
-- gamepad callbacks; joystick callbacks remain as a compatibility fallback for
-- runtimes which expose gamepad controls through the older callback family.
local function controllerMenuKey(button)
  local keys = {
    dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "return", b = "escape", back = "escape", start = "return",
  }
  local key = keys[button]
  if key then love.keypressed(key); return true end
  return false
end

local function controllerButtonPressed(button)
  button = tostring(button):lower()
  if gameState.current == "playing" then
    -- View is the World Menu/pause screen; Menu is the Main Menu.
    if button == "back" then
      gameState.set("paused")
      return
    elseif button == "start" then
      save.saveNow(false)
      gameState.set("menu")
      return
    end
    input.controllerPressed(button)
  elseif gameState.current == "account" then
    controllerMenuKey(button)
  elseif gameState.current == "multiplayer" or gameState.current == "worlds"
      or gameState.current == "localworlds" or gameState.current == "menu"
      or gameState.current == "paused" or gameState.current == "settings"
      or gameState.current == "mods" then
    controllerMenuKey(button)
  end
end

local function controllerButtonReleased(button)
  if gameState.current == "playing" then
    input.controllerReleased(tostring(button):lower())
  end
end

local function controllerAxisMoved(axis, value)
  if gameState.current == "playing" then
    input.controllerAxis(tostring(axis):lower(), value)
  end
end

-- Standard gamepad callbacks use Xbox-style names (a, leftx, triggerleft).
function love.gamepadpressed(joystick, button)
  controllerButtonPressed(button)
end

function love.gamepadreleased(joystick, button)
  controllerButtonReleased(button)
end

function love.gamepadaxis(joystick, axis, value)
  controllerAxisMoved(axis, value)
end

-- Legacy/raw joystick callbacks are retained for older LÖVE ports. Raw
-- numeric joystick mappings are intentionally not guessed.
function love.joystickpressed(joystick, button)
  if type(button) == "string" then controllerButtonPressed(button) end
end

function love.joystickreleased(joystick, button)
  if type(button) == "string" then controllerButtonReleased(button) end
end

function love.joystickaxis(joystick, axis, value)
  if type(axis) == "string" then controllerAxisMoved(axis, value) end
end

-- text boxes on the Multiplayer and Worlds screens (opens the keyboard on a phone)
function love.textinput(t)
  if gameState.current == "account" then
    account:textinput(t)
  elseif gameState.current == "multiplayer" or gameState.current == "worlds"
      or gameState.current == "localworlds" then
    mpmenu.textinput(t)
  end
end

-- save when the game goes to the background (a phone may close it without asking)
function love.focus(focused)
  music.focus(focused)
  if not focused and (gameState.current == "playing" or gameState.current == "paused") then
    save.saveNow(false)
  end
end

-- leave an online game politely when the window is closed
function love.quit()
  save.leave()
  session.leave()
  if firebaseAuth then firebaseAuth:stop() end
  return false
end

-- ---------------- files dropped on the window / shared with the app ----------------
function love.filedropped(file)
  install.dropped(file)
end

-- ---------------- touch (phone) ----------------
function love.touchpressed(id, x, y, ...)
  if gameState.current == "playing" then
    if not events.fire("pointer_pressed", x, y, 1) then return end
    input.pressed(id, x, y, ...)
  elseif gameState.current == "account" then
    account:pressed(x, y)
  else menu.pressed(x, y) end
end

function love.touchmoved(id, x, y, ...)
  if gameState.current == "playing" then input.moved(id, x, y, ...)
  else menu.moved(x, y) end
end

function love.touchreleased(id, ...)
  if gameState.current == "playing" then input.released(id, ...)
  else menu.released() end
end

function love.resize(w, h)
  g3d.camera.resize(w, h)
end

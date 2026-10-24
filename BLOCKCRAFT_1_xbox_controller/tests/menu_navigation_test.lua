-- Navigation and keyboard-input smoke tests for the separate Worlds and Multiplayer screens.
-- Run from the project root with: lua tests/menu_navigation_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local P = require "net.protocol"
local config = require "net.config"
local started

love = {
  system = {getOS = function() return "Linux" end},
  mouse = {setRelativeMode = function() end},
  keyboard = {setTextInput = function() end},
  graphics = {getDimensions = function() return 800, 600 end},
}

local fakeSession = {
  status = nil,
  active = function() return false end,
  canRetry = function() return false end,
  clearRetry = function() end,
  leave = function() end,
  retry = function() end,
  start = function(mode, address, code, name)
    started = {mode = mode, address = address, code = code, name = name}
    return true
  end,
}
package.preload["net.session"] = function() return fakeSession end
package.preload["net.safety"] = function()
  return {safe = true, server = "", custom = "", nameId = 0,
          presetName = function() return "Happy Fox" end}
end
package.preload["net.world_catalog"] = function()
  return {list = function() return {} end}
end
package.preload["settings"] = function()
  return {music = true, save = function() end, apply = function() end}
end
package.preload["modsys.install"] = function()
  return {rescan = function() end, toastTime = 0}
end
package.preload["music"] = function() return {setEnabled = function() end} end

local gs = require "gamestate"
local mpmenu = require "net.mpmenu"
local menu = require "menu"

-- The title screen exposes separate destinations rather than nesting Worlds in Multiplayer.
menu.pressed(300, 260)
assert(gs.current == "worlds", "title-screen Worlds button did not open the Worlds state")

-- Invite-code typing and submit remain available while Worlds is a separate state.
mpmenu.showJoin()
mpmenu.textinput("ACDEFGHJKMNP")
assert(mpmenu.keypressed("return"), "Return was not handled in the invite-code form")
assert(started and started.mode == "join" and started.code == "ACDEFGHJKMNP"
       and started.address == config.server,
       "world join did not reach the online session with the entered code")

-- World creation remains reachable from the Worlds state and passes the chosen label onward.
mpmenu.showCreate()
assert(mpmenu.keypressed("escape"), "Escape was not handled from the creation form")
assert(gs.current == "worlds", "leaving a world subform exited the Worlds screen")
mpmenu.showCreate()
for _ = 1, #"My World" do mpmenu.keypressed("backspace") end
mpmenu.textinput("Oak Base")
assert(mpmenu.keypressed("return"), "Return was not handled in the world-name form")
assert(started and started.mode == "host" and started.name == "Oak Base",
       "world creation did not pass the entered name to the online session")

-- Escape from the Worlds library returns to the title screen.
mpmenu.keypressed("escape")
assert(gs.current == "menu", "Escape from Worlds did not return to the title screen")

-- Multiplayer has its own title-screen destination and Back route.
menu.pressed(450, 260)
assert(gs.current == "multiplayer", "title-screen Multiplayer button did not open its own state")
mpmenu.keypressed("escape")
assert(gs.current == "menu", "Escape from Multiplayer did not return to the title screen")

-- A menu or world-list transition can never start offline gameplay.
assert(not gs.set("playing"), "offline gameplay was unexpectedly allowed")

print("PASS menu navigation: separate title destinations, Worlds invite-code input, Back routes, online-only gate")

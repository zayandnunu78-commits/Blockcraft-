-- Navigation and keyboard-input smoke tests for the separate Worlds and Multiplayer screens.
-- Run from the project root with: lua tests/menu_navigation_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local P = require "net.protocol"
local config = require "net.config"
local started
local worldGenerations, attachedSlot = 0, nil

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
          presetName = function() return "Happy Fox" end,
          newName = function() end, hasPin = function() return false end,
          turnOff = function() return true end, turnOn = function() end,
          save = function() end}
end
package.preload["net.world_catalog"] = function()
  return {list = function() return {} end}
end
package.preload["settings"] = function()
  return {music = true, save = function() end, apply = function() end}
end
package.preload["modsys.install"] = function()
  return {rescan = function() end, toastTime = 0, canOpenFiles = function() return false end}
end
package.preload["music"] = function() return {setEnabled = function() end} end
package.preload["worldgen"] = function()
  return {generate = function() worldGenerations = worldGenerations + 1 end}
end
package.preload["player"] = function() return {spawn = function() end} end
package.preload["chunks"] = function() return {flush = function() end} end
package.preload["hotbar"] = function() return {load = function() end} end
package.preload["health"] = function() return {reset = function() end} end
package.preload["save"] = function()
  return {info = function() return {state = "empty"} end,
          attach = function(slot) attachedSlot = slot end, saveNow = function() end,
          loadSlot = function() return true end, message = function() end}
end

local gs = require "gamestate"
local mpmenu = require "net.mpmenu"
local menu = require "menu"

-- A on the title screen opens offline worlds; B returns without a mouse.
assert(menu.keypressed("return"), "A was not handled on the title screen")
assert(gs.current == "localworlds", "title-screen A did not open Normal Worlds")
assert(menu.keypressed("down"), "D-pad down was not handled in the offline-world chooser")
assert(menu.keypressed("return"), "A did not create the focused offline world")
assert(gs.current == "playing" and attachedSlot == 2 and worldGenerations == 1,
       "controller selection did not start the selected offline world")
gs.set("menu")
assert(menu.keypressed("return"), "A did not reopen Normal Worlds")
assert(gs.current == "localworlds", "A did not reopen the offline-world chooser")
assert(menu.keypressed("escape"), "B was not handled in the offline-world chooser")
assert(gs.current == "menu", "B did not return from Normal Worlds")

-- D-pad right focuses Multiplayer and A opens its menu.
assert(menu.keypressed("right"), "D-pad right was not handled on the title screen")
assert(menu.keypressed("return"), "A was not handled on the title screen")
assert(gs.current == "multiplayer", "focused Multiplayer button did not open its screen")
assert(mpmenu.keypressed("down"), "D-pad down was not handled in Multiplayer")
assert(mpmenu.keypressed("down"), "D-pad down did not advance to Cloud Worlds")
assert(mpmenu.keypressed("return"), "A did not activate the focused Cloud Worlds button")
assert(gs.current == "worlds", "Cloud Worlds button did not open the Worlds screen")

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

print("PASS menu navigation: title/offline D-pad/A/B, Cloud Worlds focus, join/create flows, Back routes")

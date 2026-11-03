-- The state machine. gameState.current is one of:
--   "menu"      title screen
--   "playing"   the actual game
--   "paused"    game frozen, pause menu showing
--   "settings"  FOV / sensitivity screen (remembers where you came from)
--   "mods"      Add Mods screen (opened from settings, Back returns to settings)
--   "account"   Login / registration screen
--   "worlds"      saved online-world library (see net/mpmenu.lua)
--   "multiplayer" server and player settings (see net/mpmenu.lua)
local S = {current = "menu", settingsFrom = "menu", onlineSession = false}

local os_ = love.system.getOS()
S.xbox = (os_ == "UWP")
S.desktop = (os_ ~= "iOS" and os_ ~= "Android" and not S.xbox)

-- Always change state through this function so the mouse stays in sync.
function S.set(new)
  -- Local single-player worlds are allowed without an online session.
  -- remember where settings was opened from (not when coming back from the mods screen)
  if new == "settings" and (S.current == "menu" or S.current == "paused") then
    S.settingsFrom = S.current -- so "Back" knows where to return
  end
  S.current = new
  -- Mouse look is locked only while playing; every menu gets a free cursor.
  -- UWP/Xbox uses gamepad look and must not enter the desktop mouse-lock path.
  if S.desktop then love.mouse.setRelativeMode(new == "playing") end
  return true
end

function S.is(name) return S.current == name end

return S

-- Platform classification test for the LÖVE UWP/Xbox runtime.
-- Run from the project root with: lua tests/xbox_platform_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local relativeModeCalls = {}
love = {
  system = {getOS = function() return "UWP" end},
  mouse = {setRelativeMode = function(enabled) relativeModeCalls[#relativeModeCalls + 1] = enabled end},
}
local gs = require "gamestate"
assert(gs.xbox == true, "UWP was not identified as Xbox/UWP")
assert(gs.desktop == false, "UWP was incorrectly classified as desktop")
gs.set("playing")
assert(#relativeModeCalls == 0, "UWP gameplay attempted desktop mouse locking")

package.loaded.gamestate = nil
love.system.getOS = function() return "Windows" end
local desktop = require "gamestate"
assert(desktop.xbox == false and desktop.desktop == true,
       "ordinary Windows was not kept in desktop mode")
desktop.set("playing")
assert(#relativeModeCalls == 1 and relativeModeCalls[1] == true,
       "desktop Windows no longer enables mouse look")

print("PASS Xbox platform: UWP avoids desktop mouse mode; Windows retains desktop behavior")

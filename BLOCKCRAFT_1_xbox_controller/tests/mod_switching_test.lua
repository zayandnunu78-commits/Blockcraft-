-- Regression test for the host mod lifecycle event gate.
-- Run from the project root with: lua tests/mod_switching_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local events = require "modsys.events"
local a, b = 0, 0
events.on("update", function() a = a + 1 end, "fnaf_horror")
events.on("update", function() b = b + 1 end, "backrooms")

events.fire("update", 0.1)
assert(a == 1 and b == 1, "both modes should work before a mode is selected")
events.setOwnerEnabled("fnaf_horror", false)
events.setOwnerEnabled("backrooms", true)
events.fire("update", 0.1)
assert(a == 1 and b == 2, "FNAF handler leaked into Backrooms")
events.setOwnerEnabled("fnaf_horror", true)
events.setOwnerEnabled("backrooms", false)
events.fire("update", 0.1)
assert(a == 2 and b == 2, "Backrooms handler leaked into FNAF")

events.setOwnerEnabled("fnaf_horror", false)
events.setOwnerEnabled("backrooms", true)
events.fire("update", 0.1)
assert(a == 2 and b == 3, "repeated switch reactivated stale FNAF state")
print("PASS mod switching: inactive owner handlers stay disabled across repeated switches")

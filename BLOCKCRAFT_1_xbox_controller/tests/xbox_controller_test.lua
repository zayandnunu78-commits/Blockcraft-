package.path = "./?.lua;./?/init.lua;" .. package.path
local C = require "xbox_controller"

local function check(ok, msg)
  if not ok then error(msg, 2) end
end

local c = C.new({flightWindow = 0.45, deadzone = 0.2})
check(C.BINDINGS.a == "interact" and C.BINDINGS.b == "jump", "A/B bindings changed")
check(C.BINDINGS.x == "inventory" and C.BINDINGS.y == "camera_view", "X/Y bindings changed")
check(C.BINDINGS.leftshoulder == "attack" and C.BINDINGS.rightshoulder == "feed", "LB/RB bindings changed")
check(C.BINDINGS.righttrigger == "chat", "RT binding changed")
check(C.BINDINGS.back == "world_menu" and C.BINDINGS.start == "main_menu", "menu bindings changed")

c:press("a")
check(c:consume("interact") == true, "A did not emit interact")
check(c:press("a") == false, "held A emitted a duplicate press")
c:release("a")
check(c:press("a") == true, "A did not emit after release")

c:press("lefttrigger")
c:release("lefttrigger")
c:press("lefttrigger")
check(c.flightEnabled == true, "two LT presses did not enable flight")
check(c:consume("flight_toggle") == true, "flight-on event missing")
c:release("lefttrigger")
for _ = 1, 3 do c:press("lefttrigger"); c:release("lefttrigger") end
check(c.flightEnabled == false, "three LT presses did not disable flight")
check(c:consume("flight_toggle") == false, "flight-off event missing")

-- An incomplete sequence expires and cannot toggle flight.
c = C.new({flightWindow = 0.1})
c:press("lefttrigger"); c:release("lefttrigger")
c:update(0.11)
c:press("lefttrigger"); c:release("lefttrigger")
check(c.flightEnabled == false and c:consume("flight_toggle") == nil,
      "expired LT sequence toggled flight")

c:axis("leftx", 0.1)
check(c.axes.leftx == 0, "stick dead zone was not applied")
c:axis("leftx", 1)
check(c.axes.leftx > 0.99, "stick range was not normalized")
c = C.new()
c:axis("triggerleft", 1)
check(c.flightPresses == 1, "trigger axis created a press")
c:axis("triggerleft", 0)

print("PASS Xbox controller: exact bindings, edge-triggered buttons, LT flight counts, timeout, and dead zones")

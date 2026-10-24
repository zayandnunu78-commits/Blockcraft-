-- Run from the project root with Lua 5.1/LuaJIT: lua tests/camera_stability_test.lua
-- The real camera/matrix modules are loaded against a minimal graphics-size stub.
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["g3d"] = {path = "g3d"}

local width, height = 800, 600
love = {graphics = {
  getWidth = function() return width end,
  getHeight = function() return height end,
}}

local camera = require "g3d.camera"
local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

assert(camera.resize(1280, 720) == true, "valid resize should succeed")
assert(math.abs(camera.aspectRatio - 1280 / 720) < 1e-12, "aspect ratio should update")
assert(finite(camera.projectionMatrix[1]) and finite(camera.projectionMatrix[6]),
       "projection matrix should contain finite values")

local goodAspect = camera.aspectRatio
for _, dims in ipairs({
  {800, 0}, {0, 600}, {-1, 600}, {800, -1}, {"800", 600}, {800, math.huge},
}) do
  assert(camera.resize(dims[1], dims[2]) == false, "invalid dimensions should be rejected")
  assert(camera.aspectRatio == goodAspect, "invalid resize must preserve the last valid projection")
  assert(finite(camera.projectionMatrix[1]) and finite(camera.projectionMatrix[6]),
         "invalid resize must not poison the projection matrix")
end

width, height = 1920, 1080
assert(camera.resize() == true, "resize without explicit dimensions should use current viewport")
assert(math.abs(camera.aspectRatio - 1920 / 1080) < 1e-12,
       "current viewport dimensions should be used when arguments are omitted")
print("PASS camera stability: valid resize, invalid viewport guards, and finite projection")

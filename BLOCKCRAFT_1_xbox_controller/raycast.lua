-- Finds the block the player is looking at
local world = require "world"
local R = {}

function R.cast(ox, oy, oz, yaw, pitch, reach)
  local dx = math.cos(pitch) * math.cos(yaw)
  local dy = math.cos(pitch) * math.sin(yaw)
  local dz = math.sin(pitch)
  local px, py, pz
  local t = 0
  while t < reach do
    local x = math.floor(ox + dx * t)
    local y = math.floor(oy + dy * t)
    local z = math.floor(oz + dz * t)
    if world.get(x, y, z) ~= 0 then
      return {x, y, z}, px and {px, py, pz}
    end
    px, py, pz = x, y, z
    t = t + 0.03
  end
  return nil
end

return R

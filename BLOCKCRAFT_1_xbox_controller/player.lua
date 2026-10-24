-- The player: walking, jumping, gravity and block collisions
local g3d = require "g3d"
local world = require "world"

local P = {x = 0.5, y = 0.5, z = 40, vz = 0, ground = false}
local R, H = 0.3, 1.8
P.eye = 1.62
P.SAFE_FALL = 3     -- blocks you can fall without being hurt
P.fallFrom = nil    -- the highest point since you last stood on something
P.onFall = nil      -- set by main.lua: called with the height fallen when it was more than SAFE_FALL

local function hits(px, py, pz)
  for x = math.floor(px - R), math.floor(px + R) do
    for y = math.floor(py - R), math.floor(py + R) do
      for z = math.floor(pz), math.floor(pz + H - 0.001) do
        if world.solid(x, y, z) then return true end
      end
    end
  end
  return false
end

function P.spawn()
  P.x, P.y = 0.5, 0.5
  P.z = world.top(0, 0) + 1
  P.vz = 0
  P.fallFrom = nil
end

function P.overlaps(x, y, z)
  return P.x + R > x and P.x - R < x + 1 and P.y + R > y and P.y - R < y + 1
     and P.z + H > z and P.z < z + 1
end

function P.update(dt, fwd, str, jump, yaw, pitch)
  dt = math.min(dt, 1 / 30)
  local len = math.sqrt(fwd * fwd + str * str)
  if len > 1 then fwd, str = fwd / len, str / len end
  local sp = 4.5 * dt
  local dx = (math.cos(yaw) * fwd + math.sin(yaw) * str) * sp
  local dy = (math.sin(yaw) * fwd - math.cos(yaw) * str) * sp
  if not hits(P.x + dx, P.y, P.z) then P.x = P.x + dx end
  if not hits(P.x, P.y + dy, P.z) then P.y = P.y + dy end

  local z0 = P.z -- where this frame started (a fall is measured from here if we have no better start)
  if jump and P.ground then P.vz = 8.5 end
  P.vz = math.max(P.vz - 26 * dt, -30)
  local nz = P.z + P.vz * dt
  P.ground = false
  if hits(P.x, P.y, nz) then
    if P.vz < 0 then
      P.z = math.floor(nz) + 1
      P.ground = true
      -- landed: how far did we fall since the highest point?
      local dist = (P.fallFrom or P.z) - P.z
      P.fallFrom = P.z
      if dist > P.SAFE_FALL and P.onFall then P.onFall(dist) end
    else
      P.z = math.floor(nz + H) - H - 0.001
    end
    P.vz = 0
  else
    P.z = nz
    P.fallFrom = math.max(P.fallFrom or z0, z0, P.z)
  end

  if P.z < -20 then P.spawn() end
  g3d.camera.lookInDirection(P.x, P.y, P.z + P.eye, yaw, pitch)
end

return P

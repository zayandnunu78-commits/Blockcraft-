-- Player settings (saved to a small file so they stick between runs)
local S = {fov = 90, sensitivity = 1.0, music = true}
local FILE = "settings.txt"

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

-- push the FOV into the g3d camera
function S.apply()
  local g3d = require "g3d"
  g3d.camera.fov = math.rad(S.fov)
  g3d.camera.updateProjectionMatrix()
end

function S.save()
  love.filesystem.write(FILE, string.format("fov=%d\nsens=%.2f\nmusic=%d\n",
    math.floor(S.fov + 0.5), S.sensitivity, S.music and 1 or 0))
end

function S.load()
  local data = love.filesystem.read(FILE)
  if not data then return end
  local fov = tonumber(data:match("fov=([%d%.]+)"))
  local sens = tonumber(data:match("sens=([%d%.]+)"))
  if fov then S.fov = clamp(fov, 60, 110) end
  if sens then S.sensitivity = clamp(sens, 0.2, 3.0) end
  local music = data:match("music=(%d)")
  if music then S.music = (music ~= "0") end
end

return S

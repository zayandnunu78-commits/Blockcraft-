-- ============================================================
-- safety.lua - SAFE MODE for multiplayer.  It starts ON.
--
--   ON  : preset names only ("Happy Fox"), you never see anybody's custom name,
--         join with a code only. (There is no chat in this game at all.)
--   OFF : you may type a custom name (3-12 letters/numbers) and you see the
--         custom names of other players who have safe mode off.
--
-- Turning safe mode OFF needs the PARENT CODE (4 digits). Turning it back ON
-- needs nothing. The very first time, whoever turns safe mode off creates the
-- code, so a grown-up should do that step.
-- This is a speed bump kept on this device, not a lock that cannot be broken.
-- ============================================================
local P = require "net.protocol"

local S = {safe = true, nameId = nil, custom = "", server = ""}
local FILE = "multiplayer.txt"
local failures, lockedUntil = 0, 0

-- simple scrambling so the code is not stored as plain digits
local function scramble(pin)
  local h = 7919
  for i = 1, #pin do h = (h * 31 + pin:byte(i) * 17 + i) % 1000003 end
  return tostring(h)
end

function S.save()
  love.filesystem.write(FILE, ("safe=%d\npin=%s\nname=%d\ncustom=%s\nserver=%s\n"):format(
    S.safe and 1 or 0, S.pinHash or "", S.nameId or 0, S.custom or "", S.server or ""))
end

function S.load()
  local data = love.filesystem.read(FILE)
  if data then
    -- safe mode only turns OFF if the file says so AND a parent code exists
    S.pinHash = data:match("pin=(%d+)")
    S.safe = not (data:match("safe=(%d)") == "0" and S.pinHash)
    S.nameId = tonumber(data:match("name=(%d+)"))
    S.custom = data:match("custom=([%w]*)") or ""
    S.server = data:match("server=([%w%.%-:]*)") or ""
  end
  if not S.nameId or S.nameId >= P.NAME_COUNT then
    S.nameId = love.math.random(0, P.NAME_COUNT - 1)
  end
end

function S.presetName() return P.presetName(S.nameId) end

function S.newName()
  S.nameId = (S.nameId + love.math.random(1, P.NAME_COUNT - 1)) % P.NAME_COUNT
  S.save()
end

function S.hasPin() return S.pinHash ~= nil end

-- seconds left before another try is allowed (after 3 wrong codes)
function S.lockedFor()
  return math.max(0, math.ceil(lockedUntil - love.timer.getTime()))
end

-- returns true, or false + message
function S.turnOff(pin)
  if not pin:match("^%d%d%d%d$") then return false, "The parent code is 4 numbers." end
  if S.lockedFor() > 0 then return false, ("Too many tries. Wait %d seconds."):format(S.lockedFor()) end
  if not S.hasPin() then
    S.pinHash = scramble(pin) -- first time: this becomes the parent code
  elseif scramble(pin) ~= S.pinHash then
    failures = failures + 1
    if failures >= 3 then failures = 0; lockedUntil = love.timer.getTime() + 30 end
    return false, "That is not the parent code."
  end
  failures = 0
  S.safe = false
  S.save()
  return true
end

function S.turnOn()
  S.safe = true
  S.save()
end

return S

-- Device-local index of cloud worlds the player has created or joined.
-- This contains display labels and invitation codes only; world data lives on the server.
-- Invite codes are capabilities, so this file should remain inside LÖVE's private save dir.
local P = require "net.protocol"

local M = {MAX_WORLDS = 100}
local MAGIC = "BLOCKCRAFT_CLOUD_CATALOG 1"
local FILE = "cloud_worlds"
local cache
local generation = 0
local floor = math.floor

local function checksum(text)
  local a, b = 1, 0
  for i = 1, #text do
    a = (a + text:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return ("%08x"):format(b * 65536 + a)
end

local function decode(text)
  if type(text) ~= "string" then return nil end
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  if lines[1] ~= MAGIC then return nil end
  local gen = tonumber((lines[2] or ""):match("^generation (%d+)$"))
  local count = tonumber((lines[3] or ""):match("^count (%d+)$"))
  if not gen or gen < 1 or not count or count < 0 or count > M.MAX_WORLDS
      or #lines ~= count + 5 then return nil end
  local bodyEnd = 3 + count
  local sum = (lines[bodyEnd + 1] or ""):match("^checksum (%x%x%x%x%x%x%x%x)$")
  if lines[bodyEnd + 2] ~= "end" then return nil end
  local body = table.concat(lines, "\n", 1, bodyEnd) .. "\n"
  if not sum or checksum(body) ~= sum:lower() then return nil end

  local worlds, seen = {}, {}
  for i = 4, 3 + count do
    local code, name = (lines[i] or ""):match("^([A-Z0-9]+)|(.+)$")
    if not (P.validCode(code or "") and P.validWorldName(name or "") and not seen[code]) then
      return nil
    end
    seen[code] = true
    worlds[#worlds + 1] = {code = code, name = name}
  end
  return worlds, gen
end

local function encode(worlds, gen)
  local lines = {MAGIC, "generation " .. gen, "count " .. #worlds}
  for _, w in ipairs(worlds) do lines[#lines + 1] = w.code .. "|" .. w.name end
  local body = table.concat(lines, "\n") .. "\n"
  return body .. "checksum " .. checksum(body) .. "\nend\n"
end

local function fs()
  return love.filesystem
end

local function readBest()
  local best, bestGen
  for _, suffix in ipairs({"a", "b"}) do
    local text = fs().read(FILE .. "." .. suffix)
    local worlds, gen = decode(text)
    if worlds and (not bestGen or gen > bestGen) then best, bestGen = worlds, gen end
  end
  return best or {}, bestGen or 0
end

local function write(worlds)
  local nextGen = generation + 1
  local suffix = nextGen % 2 == 1 and "a" or "b"
  local path = FILE .. "." .. suffix
  local text = encode(worlds, nextGen)
  local ok = fs().write(path, text)
  if not ok then return false end
  local verified, verifiedGen = decode(fs().read(path))
  if not verified or verifiedGen ~= nextGen then return false end
  cache, generation = verified, nextGen
  return true
end

function M.list()
  if not cache then cache, generation = readBest() end
  local out = {}
  for i, w in ipairs(cache) do out[i] = {code = w.code, name = w.name} end
  return out
end

function M.add(code, name)
  if not P.validCode(code or "") then return false end
  name = P.validWorldName(name or "") and name or "Cloud World"
  if not cache then cache, generation = readBest() end
  local nextWorlds = {}
  local updated = false
  for i, w in ipairs(cache) do
    nextWorlds[i] = {code = w.code, name = w.code == code and name or w.name}
    if w.code == code then updated = true end
  end
  if not updated then table.insert(nextWorlds, 1, {code = code, name = name}) end
  while #nextWorlds > M.MAX_WORLDS do table.remove(nextWorlds) end
  return write(nextWorlds)
end

return M

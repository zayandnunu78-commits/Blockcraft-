-- Persistent storage for BLOCKCRAFT 1 shared worlds.
--
-- A cloud world is the existing multiplayer format: deterministic terrain seed plus
-- the server's sparse block-edit map. Two alternating complete files are kept per
-- invite code. A save is accepted only after read-back and full checksum/decode
-- validation, so a short write never replaces the last known-good generation.
local P = require "net.protocol"

local Store = {}
Store.__index = Store

local MAGIC = "BLOCKCRAFT_CLOUD_WORLD 1"
local DIR = "worlds"
local MAX_BYTES = 40 * 1024 * 1024
local MAX_EDITS = P.MAX_EDITS
local floor = math.floor

local function integer(s, lo, hi)
  if type(s) ~= "string" or #s > 12 or not s:match("^%-?%d+$") then return nil end
  local n = tonumber(s)
  if not n or n < lo or n > hi then return nil end
  return n
end

local function chunkKey(cx, cy, cz)
  return cx .. "," .. cy .. "," .. cz
end

-- Adler-32 detects accidental corruption; it is not an authentication mechanism.
local function checksum(text)
  local a, b = 1, 0
  for i = 1, #text do
    a = (a + text:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return ("%08x"):format(b * 65536 + a)
end

local function validName(s)
  return P.validWorldName(s)
end

-- Returns a complete file, or nil + a validation error.
function Store.encode(room, generation)
  if type(room) ~= "table" or not P.validCode(room.code or "")
      or not P.validRequestId(room.createId or "")
      or not integer(tostring(room.seed), 1, 2147483647)
      or not P.validSig(room.sig or "") or not validName(room.name or "") then
    return nil, "invalid world metadata"
  end
  generation = generation or ((room.generation or 0) + 1)
  if not integer(tostring(generation), 1, 2147483647) then return nil, "invalid generation" end

  local records = {}
  for _, ch in pairs(room.chunks or {}) do
    for pos, id in pairs(ch.edits or {}) do
      local sx, sy, sz = pos:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
      local x = integer(sx, -P.WORLD_LIMIT, P.WORLD_LIMIT)
      local y = integer(sy, -P.WORLD_LIMIT, P.WORLD_LIMIT)
      local z = integer(sz, 0, P.WORLD_H - 1)
      if not (x and y and z and integer(tostring(id), 0, P.sigCount(room.sig))) then
        return nil, "world contains an invalid block edit"
      end
      records[#records + 1] = ("%d %d %d %d"):format(x, y, z, id)
      if #records > MAX_EDITS then return nil, "world has too many block edits" end
    end
  end
  table.sort(records)

  local lines = {
    MAGIC,
    "world " .. room.code,
    "request " .. room.createId,
    "generation " .. generation,
    "seed " .. room.seed,
    "sig " .. room.sig,
    "name " .. room.name,
    "edits " .. #records,
  }
  for _, record in ipairs(records) do lines[#lines + 1] = record end
  local body = table.concat(lines, "\n") .. "\n"
  local text = body .. "checksum " .. checksum(body) .. "\nend\n"
  if #text > MAX_BYTES then return nil, "world file is too big" end
  return text
end

-- Returns a server room record, or nil + an error. No partial world is returned.
function Store.decode(text, expectedCode)
  if type(text) ~= "string" or #text == 0 then return nil, "empty save" end
  if #text > MAX_BYTES then return nil, "save is too big" end
  local lines = {}
  for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
  if lines[1] ~= MAGIC then return nil, "wrong save format" end

  local code = (lines[2] or ""):match("^world ([A-Z0-9]+)$")
  if not P.validCode(code or "") or (expectedCode and code ~= expectedCode) then
    return nil, "bad world code"
  end
  local createId = (lines[3] or ""):match("^request ([A-Z0-9]+)$")
  local generation = integer((lines[4] or ""):match("^generation (%d+)$"), 1, 2147483647)
  local seed = integer((lines[5] or ""):match("^seed (%d+)$"), 1, 2147483647)
  local sig = (lines[6] or ""):match("^sig ([^%s]+)$")
  local name = (lines[7] or ""):match("^name (.+)$")
  local count = integer((lines[8] or ""):match("^edits (%d+)$"), 0, MAX_EDITS)
  if not (P.validRequestId(createId or "") and generation and seed and P.validSig(sig or "")
      and validName(name or "") and count) then
    return nil, "bad world header"
  end
  if #lines ~= count + 10 then return nil, "incomplete or trailing save data" end

  local bodyEnd = 8 + count
  local expectedChecksum = (lines[bodyEnd + 1] or ""):match("^checksum (%x%x%x%x%x%x%x%x)$")
  if lines[bodyEnd + 2] ~= "end" or not expectedChecksum then
    return nil, "save has no complete footer"
  end
  local body = table.concat(lines, "\n", 1, bodyEnd) .. "\n"
  if checksum(body) ~= expectedChecksum:lower() then return nil, "save checksum does not match" end

  local room = {
    code = code, createId = createId, name = name, generation = generation, seed = seed, sig = sig,
    chunks = {}, editCount = 0, players = {}, dirty = false,
  }
  local lim = P.WORLD_LIMIT
  for i = 9, 8 + count do
    local sx, sy, sz, sid = (lines[i] or ""):match("^(%-?%d+) (%-?%d+) (%d+) (%d+)$")
    local x = integer(sx, -lim, lim)
    local y = integer(sy, -lim, lim)
    local z = integer(sz, 0, P.WORLD_H - 1)
    local id = integer(sid, 0, P.sigCount(sig))
    if not (x and y and z and id) then return nil, "invalid block edit in save" end
    local cx, cy, cz = floor(x / P.CHUNK), floor(y / P.CHUNK), floor(z / P.CHUNK)
    local ck = chunkKey(cx, cy, cz)
    local ch = room.chunks[ck]
    if not ch then
      ch = {cx = cx, cy = cy, cz = cz, edits = {}}
      room.chunks[ck] = ch
    end
    local pos = x .. "," .. y .. "," .. z
    if ch.edits[pos] ~= nil then return nil, "duplicate block edit in save" end
    ch.edits[pos] = id
    room.editCount = room.editCount + 1
  end
  return room
end

function Store.new(fs)
  assert(type(fs) == "table", "world store requires a filesystem adapter")
  assert(fs.read and fs.write and fs.exists and fs.list and fs.mkdir,
         "world store filesystem adapter is incomplete")
  fs.mkdir(DIR)
  return setmetatable({fs = fs, dir = DIR}, Store)
end

function Store.loveFilesystem()
  local fs = love.filesystem
  return {
    read = function(path)
      local data = fs.read(path)
      return data
    end,
    write = function(path, data)
      local ok, size, err = fs.write(path, data)
      if not ok then return false, err or size end
      return true
    end,
    exists = function(path) return fs.getInfo(path) ~= nil end,
    list = function(path) return fs.getDirectoryItems(path) or {} end,
    mkdir = function(path) return fs.createDirectory(path) end,
  }
end

local function path(code, slot)
  return DIR .. "/" .. code .. "." .. slot
end

function Store:codes()
  local found = {}
  for _, file in ipairs(self.fs.list(DIR) or {}) do
    local code, slot = file:match("^([A-Z0-9]+)%.([ab])$")
    if code and P.validCode(code) and (slot == "a" or slot == "b") then found[code] = true end
  end
  local out = {}
  for code in pairs(found) do out[#out + 1] = code end
  table.sort(out)
  return out
end

-- Corrupt files still reserve their code so a newly created world cannot overwrite them.
function Store:exists(code)
  if not P.validCode(code or "") then return false end
  return self.fs.exists(path(code, "a")) or self.fs.exists(path(code, "b"))
end

function Store:load(code)
  if not P.validCode(code or "") then return nil, "bad world code" end
  local best, lastError
  for _, slot in ipairs({"a", "b"}) do
    local filename = path(code, slot)
    if self.fs.exists(filename) then
      local data, err = Store.decode(self.fs.read(filename), code)
      if data and (not best or data.generation > best.generation) then
        best = data
      elseif not data then
        lastError = err
      end
    end
  end
  if best then return best end
  if self:exists(code) then return nil, "both save generations are damaged: " .. tostring(lastError) end
  return nil, "world does not exist"
end

function Store:loadAll()
  local rooms, errors = {}, {}
  for _, code in ipairs(self:codes()) do
    local room, err = self:load(code)
    if room then rooms[#rooms + 1] = room
    else errors[#errors + 1] = {code = code, error = err} end
  end
  return rooms, errors
end

function Store:save(room)
  local generation = (room.generation or 0) + 1
  local text, err = Store.encode(room, generation)
  if not text then return false, err end
  local slot = generation % 2 == 1 and "a" or "b"
  local filename = path(room.code, slot)
  local ok, writeErr = self.fs.write(filename, text)
  if not ok then return false, writeErr or "could not write save file" end
  local check, readErr = self.fs.read(filename)
  local decoded, decodeErr = Store.decode(check, room.code)
  if not decoded or decoded.generation ~= generation then
    return false, readErr or decodeErr or "save verification failed"
  end
  return true, generation
end

return Store

-- ============================================================
-- save.lua - legacy single-player world format, disabled in this online-only build.
--
-- A world is only TWO things, so a save file is tiny:
--   1. the seed        (the land is rebuilt from it, see terrain.lua)
--   2. world.edits     (every block a player or mod changed, see world.lua)
-- plus where you stand and what is in your hotbar.
--
-- Files live in LÖVE's save folder:   worlds/slot1.world .. slot3.world
--
-- Block types are saved by NAME ("stone", "ruby:ruby_block"), never by number. So a save
-- still opens if you add, remove or re-order mods. Blocks of a mod that is gone are left out
-- (the game says how many).
--
-- Safe writing: the new file is written as slotN.new, read back and checked, and only then
-- copied over slotN.world. If the game dies half way, the other file is still whole and is
-- used when loading (the newer valid one wins).
--
-- Offline world save/load/delete APIs are guarded off in this build; existing files are retained.
-- Online games are never saved (the world belongs to the server's room).
--
-- main.lua connects the hooks below (getView / setView / message).
-- ============================================================
local world = require "world"
local blocks = require "blocks"
local worldgen = require "worldgen"
local player = require "player"
local hotbar = require "hotbar"
local health = require "health"

local S = {
  SLOTS = 3, DIR = "worlds",
  slot = nil,            -- the slot of the world being played (nil = nothing is saved)
  lastVersion = 0,       -- world.version at the last save
  interval = 30,         -- seconds between automatic saves
  timer = 0,
  MAX_BYTES = 40 * 1024 * 1024, MAX_EDITS = 2000000,
  infoCache = {},
  -- set by main.lua:
  getView = function() return 0, 0 end,           -- -> yaw, pitch
  setView = function(yaw, pitch) end,
  message = function(text, ok) end,               -- short message on screen
}
local MAGIC = "BLOCKCRAFT_WORLD 1"
local CS, CZ = world.CS, world.CZ
local floor = math.floor

-- ---------------- files ----------------
local fs
local function loveFs()
  local f = love.filesystem
  return {
    read = function(p) local s = f.read(p); return s end,
    write = function(p, d) local ok = f.write(p, d); return ok and true or false end,
    exists = function(p) return f.getInfo(p) ~= nil end,
    remove = function(p) if f.getInfo(p) then f.remove(p) end end,
    mkdir = function(p) f.createDirectory(p) end,
  }
end
local function F()
  if not fs then fs = loveFs(); fs.mkdir(S.DIR) end
  return fs
end
function S.useFs(adapter) fs = adapter; if fs.mkdir then fs.mkdir(S.DIR) end end -- (tests)

local function path(slot, ext) return ("%s/slot%d.%s"):format(S.DIR, slot, ext) end

-- ---------------- encoding ----------------
-- snap = {seed, time, x, y, z, yaw, pitch, selected, hotbar = {key x9 or false},
--         edits = {chunkKey -> {index -> id}}, keyOf = function(id) -> key}
function S.encode(snap)
  local palette, plist = {}, {}
  local function pal(key)
    if not key then return 0 end
    local p = palette[key]
    if not p then plist[#plist + 1] = key; p = #plist; palette[key] = p end
    return p
  end

  -- chunks, in a fixed order (so the same world always gives the same file)
  local keys = {}
  for ckey, e in pairs(snap.edits) do if next(e) then keys[#keys + 1] = ckey end end
  table.sort(keys)
  local body, nChunks = {}, 0
  for _, ckey in ipairs(keys) do
    local e = snap.edits[ckey]
    local idxs = {}
    for idx in pairs(e) do idxs[#idxs + 1] = idx end
    table.sort(idxs)
    local pairsList = {}
    for _, idx in ipairs(idxs) do
      local id = e[idx]
      local p = 0
      if id ~= 0 then
        local k = snap.keyOf(id)
        if k then p = pal(k) else p = nil end
      end
      if p then pairsList[#pairsList + 1] = idx .. ":" .. p end
    end
    if #pairsList > 0 then
      local cx, cy, cz = world.unkey(ckey)
      nChunks = nChunks + 1
      body[#body + 1] = ("c %d %d %d %d"):format(cx, cy, cz, #pairsList)
      for i = 1, #pairsList, 64 do
        body[#body + 1] = table.concat(pairsList, " ", i, math.min(i + 63, #pairsList))
      end
    end
  end

  local hb = {}
  for i = 1, 9 do hb[i] = pal(snap.hotbar[i] or nil) end

  local out = {
    MAGIC,
    ("seed %d"):format(snap.seed),
    ("saved %d"):format(snap.time),
    ("player %.3f %.3f %.3f %.4f %.4f"):format(snap.x, snap.y, snap.z, snap.yaw, snap.pitch),
    ("select %d"):format(snap.selected),
    ("health %d"):format(snap.health or health.max),
    "hotbar " .. table.concat(hb, " "),
    ("palette %d"):format(#plist),
  }
  for i, k in ipairs(plist) do out[#out + 1] = ("p %d %s"):format(i, k) end
  out[#out + 1] = ("chunks %d"):format(nChunks)
  for _, l in ipairs(body) do out[#out + 1] = l end
  out[#out + 1] = "end"
  return table.concat(out, "\n") .. "\n"
end

-- ---------------- decoding (never trusts the file) ----------------
local function int(s, lo, hi)
  if type(s) ~= "string" or not s:match("^%-?%d+$") or #s > 12 then return nil end
  local n = tonumber(s)
  if n < lo or n > hi then return nil end
  return n
end
local function num(s, lo, hi)
  if type(s) ~= "string" or #s > 20 or not s:match("^%-?%d+%.?%d*$") then return nil end
  local n = tonumber(s)
  if not n or n < lo or n > hi then return nil end
  return n
end

-- returns data, or nil + a reason
function S.decode(text)
  if type(text) ~= "string" then return nil, "empty file" end
  if #text > S.MAX_BYTES then return nil, "file is too big" end
  local lines = {}
  for l in text:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
  if lines[1] ~= MAGIC then return nil, "not a Blockcraft world" end

  local L = world.LIMIT
  local data = {palette = {}, edits = {}, hotbar = {}, editCount = 0}
  local i = 2
  local function bad(msg) return nil, ("line %d: %s"):format(i, msg) end

  local seed = int((lines[i] or ""):match("^seed (%S+)$"), 1, 2147483647)
  if not seed then return bad("bad seed") end
  data.seed = seed; i = i + 1

  local saved = int((lines[i] or ""):match("^saved (%S+)$"), 0, 99999999999)
  if not saved then return bad("bad time") end
  data.saved = saved; i = i + 1

  local a, b, c, d, e = (lines[i] or ""):match("^player (%S+) (%S+) (%S+) (%S+) (%S+)$")
  data.x, data.y, data.z = num(a, -L, L), num(b, -L, L), num(c, -100, 200)
  data.yaw, data.pitch = num(d, -1000, 1000), num(e, -4, 4)
  if not (data.x and data.y and data.z and data.yaw and data.pitch) then return bad("bad player position") end
  i = i + 1

  data.selected = int((lines[i] or ""):match("^select (%S+)$"), 1, 9)
  if not data.selected then return bad("bad hotbar selection") end
  i = i + 1

  -- hearts (older saves have no such line)
  local hp = (lines[i] or ""):match("^health (%S+)$")
  if hp then
    data.health = int(hp, 0, 1000)
    if not data.health then return bad("bad health") end
    i = i + 1
  end

  local hb = (lines[i] or ""):match("^hotbar (.+)$")
  if not hb then return bad("bad hotbar") end
  local hbIdx = {}
  for tok in hb:gmatch("%S+") do hbIdx[#hbIdx + 1] = tok end
  if #hbIdx ~= 9 then return bad("hotbar needs 9 entries") end
  i = i + 1

  local np = int((lines[i] or ""):match("^palette (%S+)$"), 0, 100000)
  if not np then return bad("bad palette") end
  i = i + 1
  for p = 1, np do
    local n, key = (lines[i] or ""):match("^p (%d+) (.+)$")
    if tonumber(n) ~= p or #key > 80 or key:find("%c") then return bad("bad palette entry") end
    data.palette[p] = key
    i = i + 1
  end
  for k = 1, 9 do
    local p = int(hbIdx[k], 0, np)
    if not p then return bad("bad hotbar entry") end
    data.hotbar[k] = p > 0 and data.palette[p] or false
  end

  local nChunks = int((lines[i] or ""):match("^chunks (%S+)$"), 0, 10000000)
  if not nChunks then return bad("bad chunk count") end
  i = i + 1
  local lim = floor(L / world.CS) + 1
  for _ = 1, nChunks do
    local sx, sy, sz, sn = (lines[i] or ""):match("^c (%S+) (%S+) (%S+) (%S+)$")
    local cx, cy, cz, n = int(sx, -lim, lim), int(sy, -lim, lim), int(sz, 0, CZ - 1), int(sn, 1, CS * CS * CS)
    if not (cx and cy and cz and n) then return bad("bad chunk header") end
    local ckey = world.key(cx, cy, cz)
    if data.edits[ckey] then return bad("chunk listed twice") end
    local e = {}
    data.edits[ckey] = e
    i = i + 1
    local got = 0
    while got < n do
      local line = lines[i]
      if not line or line == "end" or line:sub(1, 2) == "c " then return bad("chunk is shorter than it says") end
      for idx, pv in line:gmatch("(%d+):(%d+)") do
        idx, pv = tonumber(idx), tonumber(pv)
        if idx < 1 or idx > CS * CS * CS or pv > np then return bad("bad block entry") end
        if e[idx] == nil then got = got + 1 end
        e[idx] = pv
      end
      i = i + 1
    end
    if got ~= n then return bad("chunk has the wrong number of blocks") end
    data.editCount = data.editCount + got
    if data.editCount > S.MAX_EDITS then return bad("too many block changes") end
  end

  if lines[i] ~= "end" then return nil, "the file ends too early (it was probably cut off)" end
  return data
end

-- ---------------- reading / writing slots ----------------
function S.writeSlot(slot, text)
  if S.OFFLINE_DISABLED then return false, "Offline world saving is disabled." end
  local f = F()
  local new, final = path(slot, "new"), path(slot, "world")
  if not f.write(new, text) then return false, "could not write the file (is the disk full?)" end
  if f.read(new) ~= text then return false, "the file could not be checked" end
  if not f.write(final, text) then return false, "could not write the file" end
  f.remove(new)
  return true
end

-- the newest valid save of a slot: data, or nil + reason
function S.readSlot(slot)
  local f = F()
  local best, anyFile, lastErr = nil, false, nil
  for _, ext in ipairs({"world", "new"}) do   -- ties go to the .world file
    local p = path(slot, ext)
    if f.exists(p) then
      anyFile = true
      local data, err = S.decode(f.read(p))
      if data then
        if not best or data.saved > best.saved then best = data end
      else lastErr = err end
    end
  end
  if best then return best end
  if not anyFile then return nil, "there is no saved world here" end
  return nil, "the save is damaged (" .. tostring(lastErr) .. ")"
end

-- {state = "empty" | "saved" | "damaged", saved = time, seed = n}; remembered until refresh()
function S.info(slot)
  local c = S.infoCache[slot]
  if c then return c end
  local f = F()
  local info
  local data, err = S.readSlot(slot)
  if data then info = {state = "saved", saved = data.saved, seed = data.seed}
  elseif f.exists(path(slot, "world")) or f.exists(path(slot, "new")) then info = {state = "damaged", err = err}
  else info = {state = "empty"} end
  S.infoCache[slot] = info
  return info
end

function S.refresh() S.infoCache = {} end
function S.exists(slot) return S.info(slot).state ~= "empty" end

function S.label(slot)
  local info = S.info(slot)
  if info.state == "empty" then return ("World %d  -  New"):format(slot) end
  if info.state == "damaged" then return ("World %d  -  damaged"):format(slot) end
  return ("World %d  -  %s"):format(slot, os.date("%b %d  %H:%M", info.saved))
end

function S.delete(slot)
  if S.OFFLINE_DISABLED then return false end
  local f = F()
  f.remove(path(slot, "world")); f.remove(path(slot, "new"))
  S.infoCache[slot] = nil
  if S.slot == slot then S.slot = nil end
end

-- ---------------- the world being played ----------------
local function keyOf(id) local b = blocks[id]; return b and b.key end

function S.snapshot()
  local yaw, pitch = S.getView()
  local hb = {}
  for i = 1, hotbar.count do hb[i] = keyOf(hotbar.slots[i]) or false end
  return {
    seed = require("chunks").seed, time = os.time(),
    x = player.x, y = player.y, z = player.z, yaw = yaw, pitch = pitch,
    selected = hotbar.selected, hotbar = hb, edits = world.edits, keyOf = keyOf,
    health = health.hp,
  }
end

-- the world that is open now belongs to this slot (autosave starts)
function S.attach(slot)
  if S.OFFLINE_DISABLED then return false end
  S.slot = slot
  S.lastVersion = world.version
  S.timer = 0
  S.failed = false
  S.infoCache[slot] = nil
end

function S.detach() S.slot = nil end

-- announce = true shows "World saved." (the Save World button)
function S.saveNow(announce)
  if S.OFFLINE_DISABLED then return false end
  if not S.slot then return false end
  local ok, err = S.writeSlot(S.slot, S.encode(S.snapshot()))
  if ok then
    S.lastVersion = world.version
    S.infoCache[S.slot] = nil
    S.failed = false
    if announce then S.message("World saved.", true) end
  elseif announce or not S.failed then
    S.failed = true  -- automatic saves only complain once
    S.message("Could not save the world: " .. tostring(err), false)
  end
  return ok
end

-- every frame while playing: saves by itself every `interval` seconds if something changed
function S.update(dt)
  if S.OFFLINE_DISABLED then return end
  if not S.slot then return end
  S.timer = S.timer + dt
  if S.timer >= S.interval then
    S.timer = 0
    if world.version ~= S.lastVersion then S.saveNow(false) end
  end
end

-- leaving the world (Main Menu, closing the game): save, then stop saving
function S.leave()
  if S.OFFLINE_DISABLED then S.slot = nil; return end
  if S.slot then S.saveNow(false) end
  S.slot = nil
end

-- turn saved block numbers into this game's block ids; returns edits, number of blocks left out
function S.remap(data)
  local map = {}
  for p, key in ipairs(data.palette) do map[p] = blocks.find(key) or false end
  local edits, skipped = {}, 0
  for ckey, e in pairs(data.edits) do
    local ne = {}
    for idx, p in pairs(e) do
      if p == 0 then ne[idx] = 0
      elseif map[p] then ne[idx] = map[p]
      else skipped = skipped + 1 end
    end
    if next(ne) then edits[ckey] = ne end
  end
  return edits, skipped
end

function S.loadSlot(slot)
  if S.OFFLINE_DISABLED then
    return false, "Offline worlds are disabled. Connect to the BLOCKCRAFT 1 server to play."
  end
  local data, err = S.readSlot(slot)
  if not data then return false, "Could not open this world: " .. tostring(err) end
  local edits, skipped = S.remap(data)
  worldgen.load(data.seed, edits, data.x, data.y)

  player.x, player.y, player.z, player.vz = data.x, data.y, data.z, 0
  player.ground = false
  -- never start inside a block (a mod that was removed could have changed the ground)
  if world.solid(floor(player.x), floor(player.y), floor(player.z + 0.5)) then
    player.z = world.top(floor(player.x), floor(player.y)) + 1
  end

  -- Older FNAF builds wrote the pizzeria over the normal spawn area. If this
  -- save still has that recognizable layout and the saved player is inside
  -- its office, move the player to untouched natural terrain instead of
  -- making Continue look like it opened the FNAF world.
  local brick, wood = blocks.find("Brick"), blocks.find("Wood")
  local legacyPizzeria = brick and wood
      and world.get(-10, -8, 1) == brick
      and world.get(10, -8, 1) == brick
      and world.get(0, -7, 1) == wood
      and math.abs(data.x) < 6 and math.abs(data.y + 4) < 4
  local migrated = false
  if legacyPizzeria then
    local chunks = require("chunks")
    chunks.generateAround(32.5, 32.5, 2)
    player.x, player.y = 32.5, 32.5
    player.z = world.top(32, 32) + 1
    player.vz = 0
    migrated = true
  end

  -- Build the loaded meshes immediately around the restored player. Without
  -- this flush, a continue could briefly draw the old menu area and make it
  -- look as if the saved world had not loaded.
  require("chunks").flush(player.x, player.y, player.z)

  hotbar.load()
  for i = 1, 9 do
    local id = data.hotbar[i] and blocks.find(data.hotbar[i])
    if id and id ~= 0 then hotbar.slots[i] = id end
  end
  hotbar.select(data.selected)
  S.setView(data.yaw, data.pitch)
  player.fallFrom = nil
  health.reset()
  if data.health then health.set(data.health) end -- hearts as you left them (never 0)

  -- Update the 3D camera immediately. Otherwise the first frame after
  -- Continue can still show the menu camera even though the player is already
  -- at the saved coordinates.
  player.update(0, 0, 0, false, data.yaw, data.pitch)

  S.attach(slot)
  if migrated then
    S.message(("Continued World %d in a clean normal-world area; old FNAF edits were preserved at their old location."):format(slot), true)
  else
    S.message(("Continued World %d at your saved location."):format(slot), true)
  end
  if skipped > 0 then
    S.message(("Opened. %d changed block(s) from missing mods were left out."):format(skipped), false)
  end
  return true
end

-- BLOCKCRAFT 1 online-only build: saved files remain on disk but cannot be loaded or attached.
S.OFFLINE_DISABLED = false

return S

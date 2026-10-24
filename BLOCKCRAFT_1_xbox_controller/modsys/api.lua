-- ============================================================
-- api.lua - the Mod API (version 1)
--
-- Every mod gets its OWN `api` table (see A.new) and runs inside a sandbox
-- (see A.newEnv): no io, os.execute, love.*, require of real files, load, debug.
-- A mod can only touch the game through the functions below.
--
--   api.mod                       {id, name, version, description, path}
--   api.log(...)                  print to the console, tagged with the mod id
--
--   api.block.register{...}       add a block (see below)      -> numeric id
--   api.block.find(x)             numeric id / "mod:key" / "Stone"  -> id or nil
--   api.block.name(id)            display name
--   api.block.count()
--
--   api.world.get(x, y, z)        numeric block id (0 = air)
--   api.world.set(x, y, z, b)     b = numeric id, "mod:key", "Stone" or 0/"air"
--   api.world.top(x, y)           highest solid z at x, y
--   api.world.size()              horizontal limit (the world is endless up to this) and height
--   api.world.fill(x1,y1,z1,x2,y2,z2,b)
--
--   api.player.getPosition()      x, y, z (feet)
--   api.player.teleport(x, y, z)
--   api.player.getHealth()        0..20 (20 points = 10 hearts, a half heart is 1 point)
--   api.player.setHealth(n)       1..20 (use damage() to hurt or kill)
--   api.player.damage(n)          hurt the player (goes through the "player_hurt" event)
--   api.player.heal(n)
--
--   api.hotbar.set(slot, block)   slot 1..9
--   api.hotbar.get(slot)          numeric id
--   api.hotbar.select(slot)
--
--   api.events.on(name, fn)       subscribe (return false to cancel cancellable events)
--   api.gfx                       print / rect / setColor / size  (use in "draw_hud")
--   require("lib/util")           loads <modfolder>/lib/util.lua inside the sandbox
--
-- Events:
--   "load"                 every mod finished loading (blocks are all registered)
--   "ready"                the game finished starting (hotbar, player, world exist)
--   "world_generate"       a new world was just generated (the area around the spawn point exists)
--   "chunk_generate" (c)   a 16x16x16 chunk was just generated: c = {cx, cy, cz, x0, y0, z0}.
--                          Inside this handler api.world.set only changes THIS chunk (other
--                          chunks do not exist yet) and the change is not sent over the network.
--   "update"   (dt)        every frame while playing
--   "key"      (key)       key pressed while playing
--   "player_hurt" (e)      e = {amount, source}  source is "fall" ...  cancellable; change e.amount
--   "block_break" (e)      e = {x, y, z, block}              cancellable
--   "block_place" (e)      e = {x, y, z, block}              cancellable; set e.block to change it
--   "draw_hud" (gfx)       draw 2D overlay on the HUD
--
-- api.block.register{
--   id = "ruby_block",                 -- required, [a-z0-9_]
--   name = "Ruby Block",               -- optional display name
--   texture = "textures/ruby.png",     -- one texture on all faces, OR
--   textures = {top=..., side=..., bottom=...},
-- }
-- Texture values are a path inside the mod folder/zip, or a Minecraft style
-- reference like "mymod:block/ruby_block".
-- ============================================================
local events = require "modsys.events"
local blocks = require "blocks"
local textures = require "textures"
local world = require "world"
local hotbar = require "hotbar"
local player = require "player"
local mcformat = require "modsys.mcformat"
local health = require "health"

local A = {API_VERSION = 1, fs = nil, MAX_FILL = 4096}

-- tiny drawing helpers handed to "draw_hud" handlers (also api.gfx)
A.gfx = {
  setColor = function(r, g, b, a) love.graphics.setColor(r, g, b, a or 1) end,
  rect = function(x, y, w, h) love.graphics.rectangle("fill", x, y, w, h) end,
  print = function(text, x, y) love.graphics.print(tostring(text), x, y) end,
  size = function() return love.graphics.getDimensions() end,
}

-- ---------------- textures ----------------

-- ref -> tile number (or nil, reason). Cached per mod so one png is one tile.
function A.tileFor(mod, ref)
  if type(ref) ~= "string" or ref == "" then return nil, "texture must be a string" end
  local path
  if ref:find(":", 1, true) then
    path = mcformat.texturePath(mod.root, ref, mod.id)
  else
    local candidates = {ref, ref .. ".png", "textures/" .. ref, "textures/" .. ref .. ".png"}
    for _, c in ipairs(candidates) do
      if A.fs.exists(mod.root .. "/" .. c) and not A.fs.isDir(mod.root .. "/" .. c) then
        path = mod.root .. "/" .. c
        break
      end
    end
  end
  if not path or not A.fs.exists(path) then
    return nil, "texture not found: " .. ref
  end
  mod.tileCache = mod.tileCache or {}
  if mod.tileCache[path] then return mod.tileCache[path] end
  local ok, img = pcall(love.image.newImageData, path)
  if not ok then return nil, "could not read image " .. ref .. ": " .. tostring(img) end
  local tile = textures.addTile(img)
  if not tile then return nil, "texture atlas is full (" .. textures.MAX_TILES .. " tiles)" end
  mod.tileCache[path] = tile
  return tile
end

-- ---------------- helpers ----------------

local function blockId(b)
  if b == 0 or b == "air" or b == nil then return 0 end
  local id = blocks.find(b)
  if not id then error("unknown block: " .. tostring(b), 3) end
  return id
end

local function num(v, what)
  if type(v) ~= "number" or v ~= v then error(what .. " must be a number", 3) end
  return math.floor(v)
end

-- ---------------- per-mod api ----------------

function A.new(mod)
  local api = {mod = {id = mod.id, name = mod.name, version = mod.version,
                      description = mod.description, path = mod.root},
               API_VERSION = A.API_VERSION}

  function api.log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = ("[%s] %s"):format(mod.id, table.concat(parts, " "))
    print(line)
    mod.logs = mod.logs or {}
    mod.logs[#mod.logs + 1] = line
  end

  -- ---- small persistent per-mod storage (device-local; not cloud sync) ----
  -- Keys are restricted to safe characters and are namespaced by mod ID.
  api.storage = {}
  local function storagePath(key)
    if type(key) ~= "string" or #key < 1 or #key > 48 or not key:match("^[%w_%-]+$") then
      error("storage key must use letters, numbers, _ or -", 3)
    end
    return "moddata/" .. mod.id .. "/" .. key .. ".txt"
  end
  function api.storage.read(key)
    local path = storagePath(key)
    if not love.filesystem.getInfo(path) then return nil end
    local data = love.filesystem.read(path)
    return data
  end
  function api.storage.write(key, value)
    local path = storagePath(key)
    if type(value) ~= "string" or #value > 4096 then return false, "invalid or oversized value" end
    love.filesystem.createDirectory("moddata/" .. mod.id)
    local ok, err = love.filesystem.write(path, value)
    return ok and true or false, err
  end

  -- ---- blocks ----
  api.block = {}
  function api.block.register(def)
    if type(def) ~= "table" then error("block.register expects a table", 2) end
    local id = def.id
    if type(id) ~= "string" or not id:match("^[a-z0-9_]+$") then
      error("block id must be lowercase letters, digits or _", 2)
    end
    local top, side, bottom = def.top, def.side, def.bottom
    local t = def.textures or {}
    local single = def.texture
    local refTop = t.top or t.all or single or t.side
    local refSide = t.side or t.all or single or t.top
    local refBottom = t.bottom or t.all or single or t.side or t.top
    if not (refTop and refSide and refBottom) then
      error("block '" .. id .. "' needs 'texture' or 'textures'", 2)
    end
    local tiles = {}
    for i, ref in ipairs({refTop, refSide, refBottom}) do
      local tile, why = A.tileFor(mod, ref)
      if not tile then error(why, 2) end
      tiles[i] = tile
    end
    local key = mod.id .. ":" .. id
    local nid, err = blocks.register(key, def.name or id, tiles[1], tiles[2], tiles[3], tiles[2])
    if not nid then error(err, 2) end
    mod.blockCount = (mod.blockCount or 0) + 1
    return nid
  end
  function api.block.find(x) return blocks.find(x) end
  function api.block.name(id) local b = blocks[id]; return b and b.name end
  function api.block.count() return #blocks end

  -- ---- world ----
  api.world = {}
  function api.world.get(x, y, z) return world.get(num(x, "x"), num(y, "y"), num(z, "z")) end
  function api.world.set(x, y, z, b) world.set(num(x, "x"), num(y, "y"), num(z, "z"), blockId(b)) end
  function api.world.top(x, y) return world.top(num(x, "x"), num(y, "y")) end
  function api.world.size() return world.LIMIT * 2, world.H end
  function api.world.fill(x1, y1, z1, x2, y2, z2, b)
    x1, y1, z1, x2, y2, z2 = num(x1, "x1"), num(y1, "y1"), num(z1, "z1"),
                             num(x2, "x2"), num(y2, "y2"), num(z2, "z2")
    local id = blockId(b)
    local count = (math.abs(x2 - x1) + 1) * (math.abs(y2 - y1) + 1) * (math.abs(z2 - z1) + 1)
    if count > A.MAX_FILL then error("fill is limited to " .. A.MAX_FILL .. " blocks", 2) end
    for x = math.min(x1, x2), math.max(x1, x2) do
      for y = math.min(y1, y2), math.max(y1, y2) do
        for z = math.min(z1, z2), math.max(z1, z2) do world.set(x, y, z, id) end
      end
    end
  end

  -- ---- player ----
  api.player = {}
  function api.player.getPosition() return player.x, player.y, player.z end
  function api.player.teleport(x, y, z)
    player.x, player.y, player.z = num(x, "x") + 0.5, num(y, "y") + 0.5, num(z, "z")
    player.vz = 0
    player.fallFrom = nil -- the distance fallen before the teleport does not count
  end
  function api.player.getHealth() return health.hp end
  function api.player.getMaxHealth() return health.max end
  function api.player.setHealth(n) health.set(num(n, "health")) end
  function api.player.damage(n) return health.damage(num(n, "amount"), "mod:" .. mod.id) end
  function api.player.heal(n) health.heal(num(n, "amount")) end

  -- ---- hotbar ----
  api.hotbar = {}
  function api.hotbar.set(slot, b)
    slot = num(slot, "slot")
    if slot < 1 or slot > hotbar.count then error("slot must be 1.." .. hotbar.count, 2) end
    local id = blockId(b)
    if id == 0 then error("a hotbar slot cannot be air", 2) end
    hotbar.slots[slot] = id
  end
  function api.hotbar.get(slot) return hotbar.slots[num(slot, "slot")] end
  function api.hotbar.select(slot) hotbar.select(num(slot, "slot")) end

  -- ---- audio (restricted to files inside this mod) ----
  api.audio = {}
  mod.audioSources = mod.audioSources or {}
  local function safeAudioRef(ref)
    return type(ref) == "string" and ref ~= "" and not ref:find("..", 1, true)
       and not ref:find("^/") and not ref:find("\\", 1, true)
  end
  function api.audio.exists(ref)
    return safeAudioRef(ref) and A.fs and A.fs.exists(mod.root .. "/" .. ref) or false
  end
  function api.audio.play(ref, loop, volume, streaming)
    if not safeAudioRef(ref) then return false, "invalid audio path" end
    if not api.audio.exists(ref) then return false, "audio file not found: " .. tostring(ref) end
    if not love or not love.audio then return false, "audio is unavailable" end
    local path = mod.root .. "/" .. ref
    local ok, src = pcall(love.audio.newSource, path, streaming and "stream" or "static")
    if not ok then return false, tostring(src) end
    pcall(src.setLooping, src, loop == true)
    local v = type(volume) == "number" and math.max(0, math.min(1, volume)) or 1
    pcall(src.setVolume, src, v)
    mod.audioSources[#mod.audioSources + 1] = src
    local played, err = pcall(src.play, src)
    if not played then return false, tostring(err) end
    return true
  end
  function api.audio.stopAll()
    for _, src in ipairs(mod.audioSources or {}) do pcall(src.stop, src) end
    mod.audioSources = {}
  end

  -- ---- events ----
  api.events = {}
  function api.events.on(name, fn) events.on(name, fn, mod.id) end

  -- ---- tiny drawing helpers for "draw_hud" ----
  api.gfx = A.gfx

  return api
end

-- ---------------- sandbox ----------------

local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end

local function compile(src, chunkname, env)
  if src:sub(1, 1) == "\27" then return nil, "precompiled bytecode is not allowed" end
  if setfenv then -- LuaJIT / Lua 5.1 (what LOVE uses)
    local fn, err = loadstring(src, chunkname)
    if fn then setfenv(fn, env) end
    return fn, err
  end
  return load(src, chunkname, "t", env)
end

function A.newEnv(mod, api)
  local env = {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, select = select, tonumber = tonumber, tostring = tostring,
    type = type, unpack = unpack or table.unpack, rawget = rawget, rawset = rawset,
    rawequal = rawequal, setmetatable = setmetatable,
    -- getmetatable("") would hand out the real string table, so tables only
    getmetatable = function(t) if type(t) == "table" then return getmetatable(t) end end,
    math = copy(math), string = copy(string), table = copy(table),
    os = {time = os.time, clock = os.clock, date = os.date},
    api = api, print = api.log,
  }
  env.string.dump = nil
  env._G = env

  local loaded = {}
  function env.require(name)
    if type(name) ~= "string" or name:find("..", 1, true) or name:find("[^%w_%./%-]") then
      error("bad module name", 2)
    end
    if loaded[name] ~= nil then return loaded[name] end
    local rel = name:gsub("%.", "/") .. ".lua"
    local path = mod.root .. "/" .. rel
    if not A.fs.exists(path) then error("module '" .. name .. "' not found in mod", 2) end
    local fn, err = compile(A.fs.read(path), "@" .. mod.id .. "/" .. rel, env)
    if not fn then error(err, 2) end
    loaded[name] = true -- guards against require loops
    local result = fn()
    if result == nil then result = true end
    loaded[name] = result
    return result
  end
  return env
end

-- Run a mod's entry script. The script may use the global `api`, and/or return
-- a function that receives api.
function A.run(mod, api, file)
  local path = mod.root .. "/" .. file
  local env = A.newEnv(mod, api)
  local fn, err = compile(A.fs.read(path), "@" .. mod.id .. "/" .. file, env)
  if not fn then return false, err end
  local ok, res = pcall(fn, api)
  if not ok then return false, res end
  if type(res) == "function" then
    ok, res = pcall(res, api)
    if not ok then return false, res end
  end
  return true
end

return A

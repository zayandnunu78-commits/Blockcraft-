-- ============================================================
-- loader.lua - finds mods, reads them, runs them.
--
-- Looks in the  mods/  folder (next to the game, or in LOVE's save folder).
-- A mod can be:
--   * a folder                      mods/my_mod/
--   * a .zip                        mods/my_mod.zip
--   * a Minecraft .jar              mods/cool_blocks-1.0.jar   (assets are imported)
-- Folders/files starting with "." or "_" are ignored (handy to disable a mod).
--
-- A mod is recognised by one of:
--   mod.json            native Lua mod        {"id","name","version","description","main","depends"}
--   fabric.mod.json     Minecraft Fabric mod
--   META-INF/mods.toml  Minecraft Forge/NeoForge mod
--   mcmod.info          old Minecraft Forge mod
--   assets/             plain resource pack (blocks only)
-- ============================================================
local api = require "modsys.api"
local events = require "modsys.events"
local mcformat = require "modsys.mcformat"
local json = require "modsys.json"
local blocks = require "blocks"
local textures = require "textures"
local world = require "world"

local L = {
  MOD_DIR = "mods",
  MOUNT_DIR = "modmount",
  MAX_BLOCKS_PER_MOD = 64,
  mods = {},       -- successfully loaded mods, in load order
  failed = {},     -- {source=, error=}
  byId = {},
  keepAlive = {},  -- FileData objects of mounted archives must not be garbage collected
  attempted = {},  -- file / folder names in mods/ that were already tried (so a reload skips them)
  mountN = 0,      -- counter for unique mount points
  started = false, -- false until the first loadAll() (game start)
}

local fs -- adapter, set by L.init

local function loveFs()
  local lfs = love.filesystem
  return {
    read = function(p) local s = lfs.read(p); return s end,
    exists = function(p) return lfs.getInfo(p) ~= nil end,
    isDir = function(p) local i = lfs.getInfo(p); return i ~= nil and i.type == "directory" end,
    list = function(p) local t = lfs.getDirectoryItems(p); table.sort(t); return t end,
    mount = function(path, mountpoint)
      -- preferred: mount from memory, so it works for files in the game folder,
      -- the save folder, and for .jar files (contents decide the format, not the name)
      local okData, data = pcall(lfs.newFileData, path)
      if okData and data then
        L.keepAlive[#L.keepAlive + 1] = data
        local okMount, res = pcall(lfs.mount, data, mountpoint, false)
        if okMount and res then return true end
      end
      -- fallback: mount by path (archives in the save folder)
      local okPath, res = pcall(lfs.mount, path, mountpoint, false)
      return okPath and res or false
    end,
  }
end

-- `adapter` is optional (tests pass a fake file system)
function L.init(adapter)
  fs = adapter or loveFs()
  api.fs = fs
end

local function sanitize(s)
  s = s:lower():gsub("%.[^%.]+$", ""):gsub("[^a-z0-9_]", "_"):gsub("^_+", "")
  if s == "" or s:match("^%d") then s = "mod_" .. s end
  return s
end

-- Zips are sometimes packed with one wrapper folder (MyMod-1.0/...). Step into it.
local markers = {"mod.json", "fabric.mod.json", "mcmod.info", "pack.mcmeta", "assets", "META-INF"}
local function findRoot(root)
  for _ = 1, 2 do
    for _, m in ipairs(markers) do
      if fs.exists(root .. "/" .. m) then return root end
    end
    local items = fs.list(root)
    if #items == 1 and fs.isDir(root .. "/" .. items[1]) then
      root = root .. "/" .. items[1]
    else
      break
    end
  end
  return root
end

-- ---------------- discovery ----------------

local function isNativeFolder(path)
  return fs.exists(path .. "/mod.json") or fs.exists(path .. "/fabric.mod.json")
      or fs.exists(path .. "/mcmod.info") or fs.exists(path .. "/META-INF/mods.toml")
end

-- a Bedrock pack has manifest.json (possibly one or two folders down, e.g. an unzipped .mcaddon)
local function hasBedrockManifest(path, depth)
  if fs.exists(path .. "/manifest.json") then return true end
  if depth >= 2 then return false end
  for _, item in ipairs(fs.list(path)) do
    if fs.isDir(path .. "/" .. item) and hasBedrockManifest(path .. "/" .. item, depth + 1) then
      return true
    end
  end
  return false
end

local function discover()
  local entries = {}
  if not fs.exists(L.MOD_DIR) then return entries end
  for _, item in ipairs(fs.list(L.MOD_DIR)) do
    local path = L.MOD_DIR .. "/" .. item
    local first = item:sub(1, 1)
    if first ~= "." and first ~= "_" and not L.attempted[item] then
      local lower = item:lower()
      if fs.isDir(path) then
        -- Bedrock pack folders are read by modsys/bedrock.lua, not here
        if not isNativeFolder(path) and hasBedrockManifest(path, 0) then
          -- skip
        else
          L.attempted[item] = true
          entries[#entries + 1] = {source = item, root = findRoot(path), kind = "folder"}
        end
      elseif lower:match("%.zip$") or lower:match("%.jar$") then
        L.attempted[item] = true
        L.mountN = L.mountN + 1
        local mp = L.MOUNT_DIR .. "/" .. sanitize(item) .. "_" .. L.mountN
        if fs.mount(path, mp) then
          entries[#entries + 1] = {source = item, root = findRoot(mp),
                                   kind = lower:match("%.jar$") and "jar" or "zip"}
        else
          L.failed[#L.failed + 1] = {source = item,
            error = "could not open as a zip/jar archive (corrupt file?)"}
        end
      end
    end
  end
  return entries
end

-- ---------------- reading one mod ----------------

local function readManifest(entry)
  local root = entry.root
  if fs.exists(root .. "/mod.json") then
    local j, err = json.try(fs.read(root .. "/mod.json"))
    if type(j) ~= "table" then return nil, "mod.json: " .. tostring(err or "must be an object") end
    if type(j.id) ~= "string" or not j.id:match("^[a-z][a-z0-9_]*$") then
      return nil, "mod.json: 'id' is required (lowercase letters, digits, _; starting with a letter)"
    end
    return {id = j.id, name = j.name or j.id, version = tostring(j.version or "1.0"),
            description = j.description, main = j.main or "main.lua",
            depends = j.depends or {}, loader = "lua", importAssets = j.import_assets ~= false}
  end

  local meta, err = mcformat.readMetadata(fs, root)
  if err then return nil, err end
  if meta then
    meta.id = sanitize(meta.id or entry.source)
    meta.main = "main.lua"
    meta.depends = {}
    meta.importAssets = true
    return meta
  end

  if fs.isDir(root .. "/assets") then
    local id = sanitize(entry.source)
    return {id = id, name = entry.source, version = "?", loader = "resourcepack",
            main = "main.lua", depends = {}, importAssets = true}
  end
  return nil, "no mod.json, fabric.mod.json, mods.toml or assets/ folder found"
end

-- turn assets/<ns>/... into blocks
local function importAssets(mod)
  local found, notes = mcformat.scanBlocks(fs, mod.root, L.MAX_BLOCKS_PER_MOD)
  local imported = 0
  for _, b in ipairs(found) do
    local tiles, why = {}, nil
    for i, ref in ipairs({b.top, b.side, b.bottom}) do
      local tile, e = api.tileFor(mod, ref)
      if not tile then why = e; break end
      tiles[i] = tile
    end
    if why then
      notes[#notes + 1] = ("skipped %s:%s - %s"):format(b.ns, b.name, why)
    else
      local _, err = blocks.register(b.ns .. ":" .. b.name, b.display,
                                     tiles[1], tiles[2], tiles[3], tiles[2])
      if err then notes[#notes + 1] = "skipped " .. b.ns .. ":" .. b.name .. " - " .. err
      else imported = imported + 1 end
    end
  end
  mod.blockCount = (mod.blockCount or 0) + imported
  return notes
end

-- Order so every mod loads after the mods it depends on.
-- A dependency that is NOT installed (e.g. "fabric-api") never blocks a mod:
-- it is loaded anyway and a note is printed (see loadAll).
local function sortByDependencies(list)
  local present = {}
  for _, m in ipairs(list) do present[m.meta.id] = true end
  local ordered, placed, pending = {}, {}, list
  while #pending > 0 do
    local nextPending, progress = {}, false
    for _, m in ipairs(pending) do
      local ready = true
      for _, dep in ipairs(m.meta.depends) do
        if present[dep] and not placed[dep] then ready = false end
      end
      if ready then ordered[#ordered + 1] = m; placed[m.meta.id] = true; progress = true
      else nextPending[#nextPending + 1] = m end
    end
    if not progress then
      for _, m in ipairs(nextPending) do -- circular: load them anyway
        m.circular = true
        ordered[#ordered + 1] = m
      end
      break
    end
    pending = nextPending
  end
  return ordered
end

-- ---------------- main entry ----------------

-- Loads every mod in mods/ that has not been tried yet.
-- At game start that is all of them; later calls (a mod was added while playing)
-- only load the new ones. Returns: newLoaded, newFailed, list of new mods.
function L.loadAll()
  if not fs then L.init() end
  local firstRun = not L.started
  L.started = true
  local failedBefore = #L.failed
  local newMods = {}

  local candidates = {}
  for _, entry in ipairs(discover()) do
    local meta, err = readManifest(entry)
    if not meta then
      L.failed[#L.failed + 1] = {source = entry.source, error = err}
    elseif L.byId[meta.id] then
      L.failed[#L.failed + 1] = {source = entry.source,
                                 error = "duplicate mod id '" .. meta.id .. "'"}
    else
      L.byId[meta.id] = true
      candidates[#candidates + 1] = {entry = entry, meta = meta}
    end
  end

  for _, c in ipairs(sortByDependencies(candidates)) do
    local meta, entry = c.meta, c.entry
    local mod = {id = meta.id, name = meta.name, version = meta.version,
                 description = meta.description, root = entry.root, kind = entry.kind,
                 loader = meta.loader, source = entry.source, notes = {}}
    local ok, err = true, nil

    -- needed APIs / mods that are not installed: say so, but load the mod anyway
    for _, dep in ipairs(meta.requires or meta.depends or {}) do
      if not L.byId[dep] then
        mod.notes[#mod.notes + 1] = ("needs '%s', which is not installed - loaded without it"):format(dep)
      end
    end
    if c.circular then mod.notes[#mod.notes + 1] = "circular dependency - loaded anyway" end

    if meta.importAssets then
      local okA, notes = pcall(importAssets, mod)
      if okA then
        for _, n in ipairs(notes) do mod.notes[#mod.notes + 1] = n end
      else
        ok, err = false, "asset import failed: " .. tostring(notes)
      end
    end

    if ok and fs.exists(mod.root .. "/" .. meta.main) then
      local modApi = api.new(mod)
      ok, err = api.run(mod, modApi, meta.main)
    elseif ok and meta.hasJava then
      mod.notes[#mod.notes + 1] = "Java code in this mod was not run (only its blocks/textures are used)"
    end

    if ok then
      L.mods[#L.mods + 1] = mod
      newMods[#newMods + 1] = mod
      print(("[modloader] loaded %s v%s (%s) - %d block(s)"):format(
        mod.id, mod.version, mod.loader, mod.blockCount or 0))
      for _, n in ipairs(mod.notes) do print("[modloader]   note: " .. n) end
    else
      events.removeOwner(mod.id)
      L.failed[#L.failed + 1] = {source = entry.source, error = tostring(err)}
    end
  end

  for i = failedBefore + 1, #L.failed do
    local f = L.failed[i]
    print(("[modloader] FAILED %s: %s"):format(f.source, f.error))
  end

  -- all textures are known now: build the atlas once and re-mesh the world
  if firstRun or #newMods > 0 then
    textures.rebuild()
    world.markAllDirty()
  end
  if firstRun then
    events.fire("load")
  else
    -- game already running: only the NEW mods get their load / ready events
    for _, m in ipairs(newMods) do
      events.fireFor(m.id, "load")
      events.fireFor(m.id, "ready")
    end
  end
  return #newMods, #L.failed - failedBefore, newMods
end

-- short text for the title screen
function L.summary()
  local line = ("%d mod(s) loaded"):format(#L.mods)
  if #L.failed > 0 then line = line .. (", %d failed (see console)"):format(#L.failed) end
  return line
end

return L

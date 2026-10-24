-- ============================================================
-- bedrock.lua - loads Bedrock / Minecraft Education blocks.
--
-- Where blocks can come from (all inside  mods/ ):
--   * loose files          mods/ruby_block.json + mods/ruby_block.png
--   * .mcpack / .mcaddon   drop the file in mods/, no unzipping needed
--                          (an .mcaddon can hold .mcpack files or folders inside)
--   * unzipped pack folder mods/my_pack/   (has manifest.json, blocks/, textures/ ...)
--
-- What it reads inside a pack:
--   blocks/**/*.json                 block definitions ("minecraft:block")
--   textures/terrain_texture.json    short texture name -> file path
--   blocks.json                      older style: block id -> textures (resource pack)
--   texts/en_US.lang                 display names  (tile.<id>.name=Name)
--
-- How a block gets its textures (first match wins):
--   1. components["minecraft:material_instances"]   (new style)
--   2. blocks.json entry for the identifier         (older style)
--   3. "texture" shortcut in components / description
--
-- How a texture NAME turns into a picture:
--   1. terrain_texture.json  ("ruby_block" -> "textures/blocks/ruby_block")
--   2. <root>/<name>.png   <root>/textures/<name>.png   <root>/textures/blocks/<name>.png
--   3. nothing found -> magenta/black checkerboard (the block still loads)
-- (a "root" is mods/ itself or the top folder of one pack)
--
-- Packs are searched together, so a behavior pack (blocks) and a resource pack
-- (textures) from the same .mcaddon find each other.
-- Console lines start with [bedrock].
-- ============================================================
local json = require "json"
local blocks = require "blocks"
local textures = require "textures"
local world = require "world"
local registeredBlocks = require "registeredblocks"

local B = {
  MOD_DIR = "mods",
  MOUNT_DIR = "bedrockmount",
  MAX_DEPTH = 3,         -- how deep to look inside nested folders / archives
  keepAlive = {},        -- FileData of mounted archives must not be garbage collected
}
-- B.scan() can be called again while the game runs (a mod was added). Everything it
-- already handled is remembered, so a rescan only picks up new files; texture names and
-- packs found earlier stay known, so a block file added later can still use them.

local fs -- file system adapter (B.init)

local function loveFs()
  local lfs = love.filesystem
  return {
    read = function(p) local s = lfs.read(p); return s end,
    exists = function(p) return lfs.getInfo(p) ~= nil end,
    isFile = function(p) local i = lfs.getInfo(p); return i ~= nil and i.type == "file" end,
    isDir = function(p) local i = lfs.getInfo(p); return i ~= nil and i.type == "directory" end,
    list = function(p) local t = lfs.getDirectoryItems(p); table.sort(t); return t end,
    mount = function(path, mountpoint)
      local okData, data = pcall(lfs.newFileData, path)
      if okData and data then
        B.keepAlive[#B.keepAlive + 1] = data
        local okMount, res = pcall(lfs.mount, data, mountpoint, false)
        if okMount and res then return true end
      end
      local okPath, res = pcall(lfs.mount, path, mountpoint, false)
      return okPath and res or false
    end,
    image = function(path)
      local ok, data = pcall(love.image.newImageData, path)
      if ok then return data end
    end,
    missing = function()
      local img = love.image.newImageData(16, 16)
      for y = 0, 15 do
        for x = 0, 15 do
          if (math.floor(x / 8) + math.floor(y / 8)) % 2 == 0 then
            img:setPixel(x, y, 1, 0, 1, 1)
          else
            img:setPixel(x, y, 0, 0, 0, 1)
          end
        end
      end
      return img
    end,
  }
end

-- `adapter` is optional (tests pass a fake file system)
function B.init(adapter)
  fs = adapter or loveFs()
end

-- ---------------- small helpers ----------------

-- Bedrock files are allowed to contain // and /* */ comments. Remove them
-- (but never touch text inside "strings") before handing the text to json.decode.
local function stripComments(s)
  if not s:find("/", 1, true) then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c == '"' then
      local j = i + 1
      while j <= n do
        local d = s:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == '"' then break
        else j = j + 1 end
      end
      out[#out + 1] = s:sub(i, j)
      i = j + 1
    elseif c == "/" and s:sub(i + 1, i + 1) == "/" then
      i = (s:find("\n", i, true) or n + 1)
    elseif c == "/" and s:sub(i + 1, i + 1) == "*" then
      local e = s:find("*/", i + 2, true)
      i = e and e + 2 or n + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

local function readJson(path)
  local text = fs.read(path)
  if not text then return nil, "could not read file" end
  local ok, data = pcall(json.decode, stripComments(text))
  if not ok then return nil, "invalid JSON: " .. tostring(data) end
  return data
end

-- names that come from a file must never point outside the pack
local function safeName(name)
  return type(name) == "string" and name ~= ""
     and not name:find("..", 1, true)
     and name:sub(1, 1) ~= "/" and not name:find("\\", 1, true)
end

local function prettyName(identifier)
  local short = identifier:match(":(.+)$") or identifier
  return (short:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

local function endsWith(s, ext) return s:lower():sub(-#ext) == ext end

-- ---------------- state, filled while scanning ----------------

local roots          -- list of root folders to look for textures in
local terrain        -- texture name -> {root=, path=}  (terrain_texture.json)
local legacyFaces    -- identifier -> {top=, side=, bottom=}  (blocks.json)
local lang           -- "tile.ns:name.name" -> display name
local blockFiles     -- list of {path=, label=}
local tileCache      -- cache key -> atlas tile
local mountCount
local counts         -- {packs=, archivesFailed=}
local seen           -- file / folder names in mods/ that were already handled
local modsRootAdded
B.info = {}          -- per file in mods/: {packs=, files=, blocks=, skipped=, failed=, err=}  (for messages)

local function infoFor(top)
  B.info[top] = B.info[top] or {packs = 0, files = 0, blocks = 0, skipped = 0}
  return B.info[top]
end

local function reset()
  roots, terrain, legacyFaces, lang, blockFiles, tileCache = {}, {}, {}, {}, {}, {}
  mountCount = 0
  seen = {}
  modsRootAdded = false
end

-- ---------------- reading one root ----------------

local function textureValue(entry)
  -- terrain_texture.json: "textures" is a string, a list, or {path=...}
  local v = type(entry) == "table" and entry.textures or entry
  if type(v) == "table" and v[1] ~= nil then v = v[1] end
  if type(v) == "table" then v = v.path end
  if type(v) == "string" then return v end
end

local function readTerrain(root, file)
  local data = readJson(file)
  if type(data) ~= "table" or type(data.texture_data) ~= "table" then return 0 end
  local n = 0
  for name, entry in pairs(data.texture_data) do
    local path = textureValue(entry)
    if safeName(path) and not terrain[name] then
      terrain[name] = {root = root, path = (path:gsub("%.%a+$", ""))}
      n = n + 1
    end
  end
  return n
end

-- older style: blocks.json maps  "ns:name" -> { "textures": "x" or {up=,down=,side=} }
local function faceEntryTexture(v)
  if type(v) == "string" then return v end
  if type(v) == "table" and type(v.texture) == "string" then return v.texture end
end

local function facesFrom(t)
  if type(t) == "string" then return t, t, t end
  if type(t) ~= "table" then return end
  local all = faceEntryTexture(t["*"])
  local top = faceEntryTexture(t.up) or all
  local bottom = faceEntryTexture(t.down) or all
  local side = faceEntryTexture(t.side) or faceEntryTexture(t.north) or faceEntryTexture(t.south)
            or faceEntryTexture(t.east) or faceEntryTexture(t.west) or all
  side = side or top or bottom
  if not side then return end
  return top or side, side, bottom or side
end

local function readLegacyBlocks(file)
  local data = readJson(file)
  if type(data) ~= "table" then return 0 end
  local n = 0
  for id, entry in pairs(data) do
    if type(id) == "string" and id:find(":", 1, true) and type(entry) == "table"
       and not legacyFaces[id] then
      local top, side, bottom = facesFrom(entry.textures)
      if side then
        legacyFaces[id] = {top = top, side = side, bottom = bottom}
        n = n + 1
      end
    end
  end
  return n
end

local function readLang(file)
  local text = fs.read(file)
  if not text then return end
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    local k, v = line:match("^(tile%.[^=]+)=(.-)%s*$")
    if k then
      v = v:gsub("%s*#.*$", "")
      if v ~= "" and not lang[k] then lang[k] = v end
    end
  end
end

-- collect every .json under <dir>
local function collectJson(dir, out, depth)
  if depth > 6 then return end
  for _, item in ipairs(fs.list(dir)) do
    local path = dir .. "/" .. item
    local first = item:sub(1, 1)
    if first ~= "." and first ~= "_" then
      if fs.isDir(path) then collectJson(path, out, depth + 1)
      elseif endsWith(item, ".json") then out[#out + 1] = path end
    end
  end
end

-- add a root (mods/ itself or one pack) and read everything useful from it
local function addRoot(root, label, isPack)
  roots[#roots + 1] = root
  local notes = {}

  for _, f in ipairs({"textures/terrain_texture.json", "terrain_texture.json"}) do
    if fs.exists(root .. "/" .. f) then
      local n = readTerrain(root, root .. "/" .. f)
      if n > 0 then notes[#notes + 1] = n .. " texture name(s)" end
    end
  end
  if fs.exists(root .. "/blocks.json") then
    local n = readLegacyBlocks(root .. "/blocks.json")
    if n > 0 then notes[#notes + 1] = n .. " blocks.json entr" .. (n == 1 and "y" or "ies") end
  end
  for _, f in ipairs({"texts/en_US.lang", "texts/en_us.lang"}) do
    if fs.exists(root .. "/" .. f) then readLang(root .. "/" .. f); break end
  end
  if fs.isDir(root .. "/blocks") then
    local found = {}
    collectJson(root .. "/blocks", found, 0)
    for _, path in ipairs(found) do
      local top = label:match("^[^/]+") or label
      blockFiles[#blockFiles + 1] = {path = path, top = top,
                                     label = label .. ": " .. path:sub(#root + 2)}
    end
    if #found > 0 then infoFor(label:match("^[^/]+") or label).files = infoFor(label:match("^[^/]+") or label).files + #found end
    if #found > 0 then notes[#notes + 1] = #found .. " block file(s)" end
  end

  if isPack then
    counts.packs = counts.packs + 1
    infoFor(label:match("^[^/]+") or label).packs = infoFor(label:match("^[^/]+") or label).packs + 1
    print(("[bedrock] pack %s%s"):format(label, #notes > 0 and (" (" .. table.concat(notes, ", ") .. ")") or ""))
  end
end

-- does this folder look like a Bedrock pack?
local function looksLikePack(dir)
  if fs.exists(dir .. "/manifest.json") or fs.exists(dir .. "/blocks.json")
     or fs.exists(dir .. "/textures/terrain_texture.json") then
    return true
  end
  if fs.isDir(dir .. "/blocks") then -- a folder of block .json files (not just textures/blocks/)
    local found = {}
    collectJson(dir .. "/blocks", found, 0)
    return #found > 0
  end
  return false
end

local function isNativeMod(dir)
  return fs.exists(dir .. "/mod.json") or fs.exists(dir .. "/fabric.mod.json")
      or fs.exists(dir .. "/META-INF/mods.toml") or fs.exists(dir .. "/mcmod.info")
end

local function isArchive(name)
  local l = name:lower()
  return l:match("%.mcpack$") or l:match("%.mcaddon$")
end

-- look inside a folder / mounted archive: it is either a pack, or it holds packs
local function scanContainer(dir, label, depth)
  if depth > B.MAX_DEPTH then return end
  if looksLikePack(dir) then
    addRoot(dir, label, true)
    return
  end
  for _, item in ipairs(fs.list(dir)) do
    local path = dir .. "/" .. item
    local first = item:sub(1, 1)
    if first ~= "." and first ~= "_" then
      if fs.isDir(path) then
        scanContainer(path, label .. "/" .. item, depth + 1)
      elseif isArchive(item) or (depth > 0 and endsWith(item, ".zip")) then
        -- nested archive (an .mcaddon holding .mcpack files)
        mountCount = mountCount + 1
        local mp = B.MOUNT_DIR .. "/p" .. mountCount
        if fs.mount(path, mp) then
          scanContainer(mp, label .. "/" .. item, depth + 1)
        else
          counts.archivesFailed = counts.archivesFailed + 1
          print(("[bedrock] could not open %s/%s (corrupt file?)"):format(label, item))
        end
      end
    end
  end
end

-- ---------------- textures ----------------

local function fileExists(path) return fs.isFile and fs.isFile(path) or fs.exists(path) end

local function loadImage(path)
  for _, ext in ipairs({".png", ".tga"}) do
    local p = path .. ext
    if fileExists(p) then
      local img = fs.image(p)
      if img then return img end
    end
  end
end

local function findImage(name)
  name = name:gsub("%.png$", ""):gsub("%.tga$", "")
  if not safeName(name) then return nil end

  -- 1. terrain_texture.json
  local t = terrain[name]
  if t then
    local img = loadImage(t.root .. "/" .. t.path)
    if img then return img end
  end
  -- 2. plain file names
  for _, root in ipairs(roots) do
    for _, pattern in ipairs({"%s/%s", "%s/textures/%s", "%s/textures/blocks/%s"}) do
      local img = loadImage(pattern:format(root, name))
      if img then return img end
    end
  end
end

-- texture name -> tile number in the atlas (textures.lua shrinks/crops any size to 16x16)
local function textureTile(name)
  if tileCache[name] then return tileCache[name] end
  local img = findImage(name)
  if not img then
    print(("[bedrock] texture '%s' not found - using the missing-texture checkerboard"):format(name))
    img = fs.missing()
  end
  local tile = textures.addTile(img) -- nil only if the atlas is full
  tileCache[name] = tile
  return tile
end

-- ---------------- one block file ----------------

local function pickFaces(identifier, components, description)
  local function texOf(entry)
    if type(entry) == "string" then return entry end
    if type(entry) == "table" and type(entry.texture) == "string" then return entry.texture end
  end
  local mi = components["minecraft:material_instances"]
  if type(mi) == "table" then
    local all = texOf(mi["*"])
    local top = texOf(mi.up) or all
    local bottom = texOf(mi.down) or all
    local side = texOf(mi.side) or texOf(mi.north) or texOf(mi.south)
              or texOf(mi.east) or texOf(mi.west) or all
    side = side or top or bottom
    top = top or side
    bottom = bottom or side
    if side then return top, side, bottom end
  end
  -- older style: textures come from the resource pack's blocks.json
  local legacy = legacyFaces[identifier]
  if legacy then return legacy.top, legacy.side, legacy.bottom end
  -- shortcut: a plain "texture": "name"
  local simple = components.texture or description.texture
  if type(simple) == "string" then return simple, simple, simple end
end

-- seconds to mine: "minecraft:destroy_time" (number or {value=}) or the newer
-- "minecraft:destructible_by_mining": {"seconds_to_destroy": n}
local function destroyTimeOf(components)
  local dt = components["minecraft:destroy_time"]
  if type(dt) == "table" then dt = dt.value end
  if dt == nil then
    local d = components["minecraft:destructible_by_mining"]
    if type(d) == "table" then dt = d.seconds_to_destroy end
  end
  if dt ~= nil and (type(dt) ~= "number" or dt < 0) then
    return nil, "minecraft:destroy_time must be a number >= 0"
  end
  return dt or 0 -- 0 = breaks instantly, like the built-in blocks
end

local function loadBlockFile(path)
  local data, err = readJson(path)
  if not data then return nil, err end
  if type(data) ~= "table" or type(data["minecraft:block"]) ~= "table" then
    return nil, 'no "minecraft:block" object (not a block definition)'
  end

  local block = data["minecraft:block"]
  local description = type(block.description) == "table" and block.description or {}
  local components = type(block.components) == "table" and block.components or {}

  local identifier = description.identifier
  local ns = type(identifier) == "string" and identifier:match("^([a-z0-9_]+):[a-z0-9_]+$")
  if not ns then
    return nil, 'description.identifier must look like "namespace:name" (a-z, 0-9, _)'
  end
  if ns == "minecraft" then return nil, 'namespace "minecraft" is reserved' end
  if registeredBlocks[identifier] then return nil, "identifier already registered" end

  local destroyTime, derr = destroyTimeOf(components)
  if not destroyTime then return nil, derr end

  local top, side, bottom = pickFaces(identifier, components, description)
  if not side then
    return nil, 'no texture found (use components["minecraft:material_instances"]["*"].texture)'
  end
  local tTop, tSide, tBottom = textureTile(top), textureTile(side), textureTile(bottom)
  if not (tTop and tSide and tBottom) then return nil, "texture atlas is full" end

  local display = lang["tile." .. identifier .. ".name"] or prettyName(identifier)
  local numericId, rerr = blocks.register(identifier, display, tTop, tSide, tBottom, tSide)
  if not numericId then return nil, rerr end
  blocks[numericId].destroyTime = destroyTime

  local def = {
    identifier = identifier, name = display, id = numericId,
    destroyTime = destroyTime, source = path,
    textures = {top = top, side = side, bottom = bottom},
    tiles = {top = tTop, side = tSide, bottom = tBottom},
  }
  registeredBlocks.add(def)
  return def
end

-- ---------------- main entry ----------------

-- Finds everything NEW in mods/ and registers the blocks.
-- Returns: total registered, skipped this scan, newly registered this scan.
function B.scan()
  if not fs then B.init() end
  if not roots then reset() end
  counts = {packs = 0, archivesFailed = 0}
  blockFiles = {}
  local countBefore = registeredBlocks.count
  if not fs.exists(B.MOD_DIR) then return registeredBlocks.count, 0, 0 end

  -- loose files: mods/*.json and mods/*.png (mods/ itself is a root)
  if not modsRootAdded then
    modsRootAdded = true
    addRoot(B.MOD_DIR, "mods", false)
  end
  local items = fs.list(B.MOD_DIR)
  local skipNames = {["manifest.json"] = true, ["blocks.json"] = true,
                     ["terrain_texture.json"] = true}
  for _, f in ipairs(items) do
    local path = B.MOD_DIR .. "/" .. f
    local first = f:sub(1, 1)
    if first ~= "." and first ~= "_" and endsWith(f, ".json") and not skipNames[f:lower()]
       and not seen[f] and (not fs.isFile or fs.isFile(path)) then
      seen[f] = true
      blockFiles[#blockFiles + 1] = {path = path, label = f, top = f}
      infoFor(f).files = 1
    end
  end

  -- packs: .mcpack / .mcaddon files and unzipped pack folders
  for _, f in ipairs(items) do
    local path = B.MOD_DIR .. "/" .. f
    local first = f:sub(1, 1)
    if first ~= "." and first ~= "_" and not seen[f] then
      if isArchive(f) and (not fs.isFile or fs.isFile(path)) then
        seen[f] = true
        mountCount = mountCount + 1
        local mp = B.MOUNT_DIR .. "/p" .. mountCount
        if fs.mount(path, mp) then
          scanContainer(mp, f, 0)
        else
          counts.archivesFailed = counts.archivesFailed + 1
          infoFor(f).failed = true
          print(("[bedrock] could not open %s (corrupt file?)"):format(f))
        end
      elseif fs.isDir(path) and not isNativeMod(path) then
        local before = counts.packs
        scanContainer(path, f, 0)
        if counts.packs > before then seen[f] = true end
      end
    end
  end

  -- register the blocks (all textures / names are known now)
  local skipped = 0
  for _, bf in ipairs(blockFiles) do
    local def, err = loadBlockFile(bf.path)
    local inf = infoFor(bf.top or bf.label)
    if def then
      inf.blocks = inf.blocks + 1
      print(("[bedrock] %s -> %s (id %d, destroy_time %s)"):format(
        bf.label, def.identifier, def.id, tostring(def.destroyTime)))
    else
      inf.skipped = inf.skipped + 1
      inf.err = inf.err or tostring(err)
      skipped = skipped + 1
      print(("[bedrock] skipped %s: %s"):format(bf.label, err))
    end
  end
  local new = registeredBlocks.count - countBefore
  print(("[bedrock] %d block(s) registered (%d new), %d file(s) skipped, %d new pack(s)"):format(
    registeredBlocks.count, new, skipped, counts.packs))

  if new > 0 then
    textures.rebuild()      -- all textures are in: build the atlas once
    world.markAllDirty()    -- and re-mesh so the new atlas is used
  end
  return registeredBlocks.count, skipped, new
end

-- true if mods/<name> was already handled by a scan
function B.handled(name) return seen ~= nil and seen[name] == true end

B._stripComments = stripComments -- exposed for tests
return B

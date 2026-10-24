-- ============================================================
-- mcformat.lua - reads REAL Minecraft mod / resource-pack files.
--
-- What it can read (data only):
--   fabric.mod.json, META-INF/mods.toml (Forge/NeoForge), mcmod.info (old Forge)
--   assets/<ns>/lang/en_us.json            display names
--   assets/<ns>/blockstates/*.json         which blocks exist
--   assets/<ns>/models/block/*.json        which texture goes on which face
--   assets/<ns>/textures/block/*.png       the textures
--
-- What it can NOT do: run Java code (.class files). A jar's blocks can be
-- imported as plain cubes, but custom behaviour has to be written as a Lua mod.
-- ============================================================
local json = require "modsys.json"

local M = {}

-- `fs` is a tiny adapter: fs.read(path) fs.exists(path) fs.list(path) fs.isDir(path)

-- ---------------- metadata ----------------

-- very small TOML reader: only what mods.toml needs ([[mods]] tables, key = "string")
local function parseModsToml(text)
  local mods, cur = {}, nil
  local multi -- key of a ''' ... ''' multi-line string being read
  for line in (text .. "\n"):gmatch("(.-)\r?\n") do
    if multi then
      local close = line:find("'''", 1, true)
      if close then
        cur[multi] = (cur[multi] or "") .. line:sub(1, close - 1)
        multi = nil
      else
        cur[multi] = (cur[multi] or "") .. line .. "\n"
      end
    else
      line = line:gsub("^%s+", "")
      if line:match("^%[%[mods%]%]") then
        cur = {}
        mods[#mods + 1] = cur
      elseif line:match("^%[") then
        cur = nil -- some other table (dependencies etc.)
      elseif cur then
        local k, v = line:match("^([%w_%.]+)%s*=%s*(.-)%s*$")
        if k then
          local q = v:match('^"(.-)"') or v:match("^'([^']-)'$")
          if q then cur[k] = q
          elseif v:sub(1, 3) == "'''" then
            local rest = v:sub(4)
            local close = rest:find("'''", 1, true)
            if close then cur[k] = rest:sub(1, close - 1)
            else cur[k] = rest .. "\n"; multi = k end
          end
        end
      end
    end
  end
  return mods[1]
end

-- returns {id=, name=, version=, description=, loader=, hasJava=} or nil
function M.readMetadata(fs, root)
  local function p(rel) return root .. "/" .. rel end

  if fs.exists(p("fabric.mod.json")) then
    local j, err = json.try(fs.read(p("fabric.mod.json")))
    if not j then return nil, "fabric.mod.json: " .. tostring(err) end
    -- what the mod says it needs (only used for a console note: Java code is never run)
    local requires = {}
    if type(j.depends) == "table" then
      for k in pairs(j.depends) do
        if k ~= "minecraft" and k ~= "java" and k ~= "fabricloader" then requires[#requires + 1] = k end
      end
      table.sort(requires)
    end
    return {id = j.id, name = j.name or j.id, version = tostring(j.version or "?"),
            description = j.description, loader = "fabric",
            hasJava = j.entrypoints ~= nil, requires = requires}
  end

  if fs.exists(p("META-INF/mods.toml")) or fs.exists(p("META-INF/neoforge.mods.toml")) then
    local f = fs.exists(p("META-INF/mods.toml")) and "META-INF/mods.toml"
              or "META-INF/neoforge.mods.toml"
    local m = parseModsToml(fs.read(p(f)))
    if not m or not m.modId then return nil, f .. ": no [[mods]] entry with modId" end
    -- ${file.jarVersion} placeholders are filled in by the Forge build, not us
    local ver = m.version
    if not ver or ver:find("${", 1, true) then ver = "?" end
    return {id = m.modId, name = m.displayName or m.modId, version = ver,
            description = m.description, loader = "forge", hasJava = true}
  end

  if fs.exists(p("mcmod.info")) then
    local j = json.try(fs.read(p("mcmod.info")))
    local m = j and (j.modList and j.modList[1] or j[1] or j)
    if m and m.modid then
      return {id = m.modid, name = m.name or m.modid, version = tostring(m.version or "?"),
              description = m.description, loader = "forge-legacy", hasJava = true}
    end
  end
  return nil
end

-- ---------------- asset helpers ----------------

local function splitRef(ref, defaultNs)
  local ns, path = ref:match("^([%w_%.%-]+):(.+)$")
  if ns then return ns, path end
  return defaultNs or "minecraft", ref
end

-- Read a model file and follow "parent" links inside the mod.
-- Returns {textures=merged table, elements=or nil, parents=names of ancestors that
-- are not in the mod}. Vanilla parents such as minecraft:block/cube_all can't be
-- read, but their NAME tells us what shape the block is.
local function resolveModel(fs, root, ref, defaultNs, depth)
  depth = depth or 0
  local out = {textures = {}, parents = {}}
  if depth > 8 then return out end
  local ns, path = splitRef(ref, defaultNs)
  local file = ("%s/assets/%s/models/%s.json"):format(root, ns, path)
  if not fs.exists(file) then
    out.parents[1] = path -- vanilla / unreadable model: its NAME tells us the shape
    return out
  end
  local j = json.try(fs.read(file))
  if not j then return out end
  if j.parent then
    local parent = resolveModel(fs, root, j.parent, ns, depth + 1)
    out.textures = parent.textures
    out.elements = parent.elements
    out.parents = parent.parents
  end
  for k, v in pairs(j.textures or {}) do out.textures[k] = v end -- child overrides parent
  if j.elements then out.elements = j.elements end
  return out
end

local function deref(textures, v)
  local guard = 0
  while type(v) == "string" and v:sub(1, 1) == "#" and guard < 10 do
    v = textures[v:sub(2)]
    guard = guard + 1
  end
  if type(v) == "string" and v:sub(1, 1) == "#" then return nil end
  return v
end

local cubeParents = {
  cube_all = true, cube = true, cube_column = true, cube_column_horizontal = true,
  cube_bottom_top = true, cube_top = true, orientable = true,
  orientable_with_bottom = true, cube_mirrored_all = true, cube_directional = true,
}

local function isFullCube(elements)
  if not elements or #elements ~= 1 then return false end
  local e = elements[1]
  local f, t = e.from, e.to
  return f and t and f[1] == 0 and f[2] == 0 and f[3] == 0
     and t[1] == 16 and t[2] == 16 and t[3] == 16
end

-- Figure out the top / side / bottom texture refs for a block model.
-- Returns {top=, side=, bottom=} (texture refs) or nil, "reason it was skipped".
function M.blockTextures(fs, root, ns, modelRef)
  local m = resolveModel(fs, root, modelRef, ns)
  local cube = false
  for _, parent in ipairs(m.parents) do
    local leaf = parent:match("([%w_]+)$")
    if cubeParents[leaf] then cube = true end
  end
  if not cube and isFullCube(m.elements) then cube = true end
  if not cube then
    return nil, "not a full cube (" .. (m.parents[#m.parents] or "custom model") .. ")"
  end

  local t = m.textures
  local function g(...)
    for _, k in ipairs({...}) do
      local v = deref(t, t[k])
      if v then return v end
    end
  end

  local top, side, bottom
  if m.elements and isFullCube(m.elements) then
    local faces = m.elements[1].faces or {}
    local function face(n) return faces[n] and deref(t, faces[n].texture) end
    top, bottom = face("up"), face("down")
    side = face("north") or face("south") or face("east") or face("west")
  end
  top = top or g("top", "up", "end", "all", "particle")
  side = side or g("side", "north", "front", "all", "particle")
  bottom = bottom or g("bottom", "down", "end", "top", "all", "particle")
  side = side or top or bottom
  top = top or side
  bottom = bottom or side
  if not side then return nil, "model has no textures" end
  return {top = top, side = side, bottom = bottom}
end

-- Where a texture ref lives inside the mod: "ns:block/foo" -> assets/ns/textures/block/foo.png
function M.texturePath(root, ref, defaultNs)
  local ns, path = splitRef(ref, defaultNs)
  return ("%s/assets/%s/textures/%s.png"):format(root, ns, path), ns
end

-- Scan a mod's assets/ folder. Returns a list of
--   {ns=, name=, display=, top=ref, side=ref, bottom=ref}   (refs are texture refs)
-- plus a list of human-readable notes about anything skipped.
function M.scanBlocks(fs, root, maxBlocks)
  local found, notes = {}, {}
  local assets = root .. "/assets"
  if not fs.isDir(assets) then return found, notes end

  for _, ns in ipairs(fs.list(assets)) do
    if ns ~= "minecraft" and fs.isDir(assets .. "/" .. ns) then
      -- language file for display names
      local lang = {}
      local langFile = ("%s/%s/lang/en_us.json"):format(assets, ns)
      if fs.exists(langFile) then lang = json.try(fs.read(langFile)) or {} end

      local function displayName(name)
        local n = lang["block." .. ns .. "." .. name]
        if n then return n end
        return (name:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
      end

      local names = {}
      local bsDir = ("%s/%s/blockstates"):format(assets, ns)
      if fs.isDir(bsDir) then
        for _, f in ipairs(fs.list(bsDir)) do
          local n = f:match("^(.+)%.json$")
          if n then names[#names + 1] = {name = n, state = bsDir .. "/" .. f} end
        end
      else
        -- no blockstates: treat every block texture as a plain cube
        local texDir = ("%s/%s/textures/block"):format(assets, ns)
        if fs.isDir(texDir) then
          for _, f in ipairs(fs.list(texDir)) do
            local n = f:match("^(.+)%.png$")
            if n then names[#names + 1] = {name = n} end
          end
        end
      end
      table.sort(names, function(a, b) return a.name < b.name end)

      for _, entry in ipairs(names) do
        if #found >= maxBlocks then
          notes[#notes + 1] = ("block limit (%d) reached, rest skipped"):format(maxBlocks)
          return found, notes
        end
        local name = entry.name
        local tex, why
        if entry.state then
          local st = json.try(fs.read(entry.state))
          local modelRef
          if st and st.variants then
            -- first variant; "variants" values are a model table or a list of them
            local _, v = next(st.variants)
            -- prefer the plain "" variant when present
            if st.variants[""] then v = st.variants[""] end
            if type(v) == "table" and v[1] then v = v[1] end
            modelRef = v and v.model
          elseif st and st.multipart then
            local part = st.multipart[1]
            local a = part and part.apply
            if type(a) == "table" and a[1] then a = a[1] end
            modelRef = a and a.model
          end
          if modelRef then
            tex, why = M.blockTextures(fs, root, ns, modelRef)
          else
            why = "blockstate has no model"
          end
        else
          local ref = ns .. ":block/" .. name
          tex = {top = ref, side = ref, bottom = ref}
        end
        if tex then
          found[#found + 1] = {ns = ns, name = name, display = displayName(name),
                               top = tex.top, side = tex.side, bottom = tex.bottom}
        else
          notes[#notes + 1] = ("skipped %s:%s - %s"):format(ns, name, why or "?")
        end
      end
    end
  end
  return found, notes
end

M._parseModsToml = parseModsToml -- exposed for tests
return M

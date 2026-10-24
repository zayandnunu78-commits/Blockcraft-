-- Block types. Numbers are tiles in textures.lua.
-- id = position in this list. icon = tile shown in the hotbar.
-- Mods add blocks through blocks.register() (see modsys/api.lua).
local list = {}
local names = {} -- "Grass" / "modid:ruby_block" -> id

local function add(name, icon, top, side, bottom, key)
  list[#list + 1] = {name = name, key = key or name:lower(), icon = icon,
                     top = top, side = side, bottom = bottom}
  names[list[#list].key] = #list
  if not key then names[name] = #list end -- plain names ("Stone") are for built-in blocks only
  return #list
end

add("Grass",  2, 1, 2, 3)
add("Dirt",   3, 3, 3, 3)
add("Stone",  4, 4, 4, 4)
add("Wood",   5, 6, 5, 6)
add("Leaves", 7, 7, 7, 7)
add("Sand",   8, 8, 8, 8)
add("Planks", 9, 9, 9, 9)
add("Cobble", 10, 10, 10, 10)
add("Brick",  11, 11, 11, 11)

-- Register a new block. key is the unique string id, e.g. "ruby:ruby_block".
-- Returns the numeric id, or nil + error message.
function list.register(key, name, top, side, bottom, icon)
  if names[key] then return nil, "block '" .. key .. "' already registered" end
  local id = add(name, icon or side, top, side, bottom, key)
  return id
end

-- look up by numeric id, key ("ruby:ruby_block") or built-in name ("Stone")
function list.find(x)
  if type(x) == "number" then return list[x] and x or nil end
  return names[x] or names[tostring(x):lower()]
end

return list

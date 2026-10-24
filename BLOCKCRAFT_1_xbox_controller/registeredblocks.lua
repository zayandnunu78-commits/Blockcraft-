-- ============================================================
-- registeredblocks.lua - the ONE central table of custom (Bedrock-style) blocks.
--
--   main.lua   fills it while scanning mods/*.json
--   mesher / hotbar / raycast / input / hud  can `require "registeredblocks"` and read it
--
-- Every entry (the "def") looks like:
--   {
--     identifier  = "ruby:ruby_block",   -- unique string id from the JSON
--     name        = "Ruby Block",        -- display name (made from the identifier)
--     id          = 12,                  -- numeric id used inside the world grid
--     destroyTime = 3.0,                 -- from "minecraft:destroy_time" (seconds to mine)
--     textures    = {top=, side=, bottom=},   -- texture names from the JSON
--     tiles       = {top=, side=, bottom=},   -- tile numbers in the texture atlas
--     source      = "mods/ruby_block.json",
--   }
--
-- Lookups:
--   registeredBlocks["ruby:ruby_block"]   by identifier (identifiers always contain
--                                         ":" so they can never clash with the helpers below)
--   registeredBlocks.byId[12]             by numeric id  <- what raycasting/mining uses
--   registeredBlocks.list                 array, in load order, for iterating
-- ============================================================
local R = {byId = {}, list = {}, count = 0}

function R.add(def)
  R[def.identifier] = def
  R.byId[def.id] = def
  R.list[#R.list + 1] = def
  R.count = R.count + 1
end

-- accepts an identifier string or a numeric id; returns the def or nil
function R.get(x)
  if type(x) == "number" then return R.byId[x] end
  return R[x]
end

return R

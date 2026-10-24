-- ============================================================
-- worldgen.lua - starts a world. The land itself comes from terrain.lua; chunks.lua
-- streams it in around the player. This file only sets the seed, builds the chunks
-- around the spawn point right away, and tells mods the world exists.
-- ============================================================
local world = require "world"
local chunks = require "chunks"
local events = require "modsys.events"
local G = {SPAWN_RADIUS = 2}  -- chunks around the spawn point built before the first frame

-- seed: online games pass the host's seed so everybody builds the same world
function G.generate(seed)
  seed = seed or love.math.random(1, 2000000000)
  chunks.reset(seed)
  chunks.generateAround(0.5, 0.5, G.SPAWN_RADIUS)
  -- mods can decorate the fresh world. These changes are never sent over the network:
  -- every player runs the same mods, so everybody makes them for themselves.
  local was = world.silent
  world.silent = true
  events.fire("world_generate")
  world.silent = was
end

-- open a SAVED world: same seed, the saved block changes put back, spawn area built around
-- the player. world_generate is not fired: whatever mods built then is already in the edits.
function G.load(seed, edits, px, py)
  chunks.reset(seed)
  for key, e in pairs(edits) do world.edits[key] = e end
  chunks.generateAround(px or 0.5, py or 0.5, G.SPAWN_RADIUS)
end

return G

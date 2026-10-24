-- Example native mod. Everything it can do goes through the `api` table.
local ruby = api.block.register{
  id = "ruby_block", name = "Ruby Block", texture = "textures/ruby_block.png",
}
local lamp = api.block.register{
  id = "lamp", name = "Lamp",
  textures = {top = "textures/lamp_top.png", side = "textures/lamp_side.png",
              bottom = "textures/lamp_top.png"},
}

-- build a 4 high ruby tower with a lamp on top whenever a world is generated
api.events.on("world_generate", function()
  local x, y = 21, 16
  local top = api.world.top(x, y)
  api.world.fill(x, y, top + 1, x, y, top + 4, "ruby_mod:ruby_block")
  api.world.set(x, y, top + 5, "ruby_mod:lamp")
end)

-- put the new blocks in the last hotbar slots
api.events.on("ready", function()
  api.hotbar.set(8, "ruby_mod:lamp")
  api.hotbar.set(9, "ruby_mod:ruby_block")
end)

-- events are cancelled by returning false: the bottom ruby of a tower can't be broken
api.events.on("block_break", function(e)
  if e.block == ruby and api.world.get(e.x, e.y, e.z - 1) ~= ruby
     and api.world.get(e.x, e.y, e.z + 1) == ruby then
    api.log("the base of a ruby tower is unbreakable")
    return false
  end
end)

-- placing Sand turns it into a ruby block (handlers may replace e.block)
api.events.on("block_place", function(e)
  if e.block == api.block.find("Sand") then e.block = ruby end
end)

-- T teleports you back to the spawn point
api.events.on("key", function(key)
  if key == "t" then
    api.player.teleport(0, 0, api.world.top(0, 0) + 1)
  end
end)

api.events.on("draw_hud", function(g)
  g.setColor(1, 0.85, 0.3, 1)
  g.print("Ruby Mod active - [ ] cycles blocks, T = spawn", 10, 34)
end)

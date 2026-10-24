-- ============================================================
-- Runs the multiplayer SERVER:   love . --server        (see SERVER_SETUP.md)
-- Needs no window or graphics. The rules are in net/server_core.lua.
-- Fixed UDP port: 22122 (BLOCKCRAFT 2 uses 22123 and is separate).
-- ============================================================
local enet = require "enet"
local Core = require "net.server_core"
local P = require "net.protocol"
local Store = require "net.world_store"

local host, core, entropy
local wrappers = {} -- enet peer index -> {raw = enet peer}

local function randomInt(lo, hi)
  if entropy then
    local bytes = entropy:read(4)
    if bytes and #bytes == 4 then
      local n = bytes:byte(1) * 16777216 + bytes:byte(2) * 65536
          + bytes:byte(3) * 256 + bytes:byte(4)
      return lo + (n % (hi - lo + 1))
    end
  end
  return love.math.random(lo, hi)
end

function love.load()
  local port = P.PORT -- BLOCKCRAFT 1 is fixed to UDP 22122.
  host = enet.host_create("*:" .. port, 64, 2)
  assert(host, "could not open port " .. port .. " (is something else using it?)")
  love.math.setRandomSeed(os.time())
  entropy = io.open("/dev/urandom", "rb")
  if not entropy then print("WARNING: /dev/urandom unavailable; invite codes use the LÖVE PRNG.") end
  core = Core.new{
    store = Store.new(Store.loveFilesystem()),
    send = function(peer, text, reliable)
      if reliable then peer.raw:send(text, 0, "reliable")
      else peer.raw:send(text, 1, "unreliable") end
    end,
    disconnect = function(peer) peer.raw:disconnect_later() end,
    random = randomInt,
    log = function(text) print(os.date("%H:%M:%S ") .. text) end,
  }
  print(("Server running on UDP port %d. Press Ctrl+C to stop."):format(port))
end

function love.quit()
  if core then core:shutdown() end
  if entropy then entropy:close(); entropy = nil end
end

function love.update(dt)
  core:tick(dt)
  local ev = host:service(0)
  while ev do
    local index = ev.peer:index()
    if ev.type == "connect" then
      wrappers[index] = {raw = ev.peer}
      core:connected(wrappers[index])
    elseif ev.type == "receive" then
      if wrappers[index] then core:received(wrappers[index], ev.data) end
    elseif ev.type == "disconnect" then
      if wrappers[index] then core:disconnected(wrappers[index]) end
      wrappers[index] = nil
    end
    ev = host:service(0)
  end
  host:flush()
  love.timer.sleep(0.005)
end

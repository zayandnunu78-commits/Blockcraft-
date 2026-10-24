-- Pure-Lua integration tests for server-side cloud-world persistence.
-- Run from the project root with: lua tests/cloud_save_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local P = require "net.protocol"
local Store = require "net.world_store"
local Core = require "net.server_core"

local function check(ok, message)
  if not ok then error(message or "assertion failed", 2) end
end

local fs = {files = {}, failNextWrite = false}
function fs.mkdir() return true end
function fs.list(dir)
  local out = {}
  for path in pairs(fs.files) do
    local name = path:match("^" .. dir .. "/(.+)$")
    if name then out[#out + 1] = name end
  end
  return out
end
function fs.exists(path) return fs.files[path] ~= nil end
function fs.read(path) return fs.files[path] end
function fs.write(path, data)
  if fs.failNextWrite then
    fs.failNextWrite = false
    fs.files[path] = data:sub(1, math.max(1, math.floor(#data / 2)))
    return false, "simulated short write"
  end
  fs.files[path] = data
  return true
end

local store = Store.new(fs)
local signature = P.makeSig({"stone"})
local sample = {
  code = "ACDEFGHJKMNP", createId = "AAAAAAAAAAAAAAAAAAAAAAAA",
  name = "Test World", seed = 12345, sig = signature,
  generation = 1, chunks = {
    ["0,0,0"] = {cx = 0, cy = 0, cz = 0, edits = {["1,2,3"] = 1, ["4,5,6"] = 0}},
  },
}
local encoded = assert(Store.encode(sample, 1))
local decoded = assert(Store.decode(encoded, sample.code))
check(decoded.seed == sample.seed and decoded.name == sample.name, "metadata round-trip")
check(decoded.editCount == 2 and decoded.chunks["0,0,0"].edits["1,2,3"] == 1,
      "block edits round-trip")
check(not Store.decode(encoded:sub(1, -8), sample.code), "truncated save was accepted")

local nextRandom = 19
local nextRequest = 0
local function random(lo, hi)
  nextRandom = nextRandom + 1
  return lo + (nextRandom * 37) % (hi - lo + 1)
end
local function server()
  return Core.new({
    store = store,
    random = random,
    send = function(peer, text) peer.out[#peer.out + 1] = text end,
    disconnect = function() end,
  })
end
local function peer(core)
  local p = {out = {}}
  core:connected(p)
  return p
end
local function sent(peer, prefix)
  for _, message in ipairs(peer.out) do
    if message:sub(1, #prefix) == prefix then return message end
  end
end
local function host(core, name)
  local p = peer(core)
  nextRequest = nextRequest + 1
  local requestId = ("REQUEST%017d"):format(nextRequest)
  core:received(p, ("HOST|%d|1|0|-|%s|%s|%s"):format(P.VERSION, signature, name, requestId))
  local welcome = sent(p, "WELCOME|")
  check(welcome, "host did not receive WELCOME")
  local code = welcome:match("^WELCOME|%d+|([A-Z0-9]+)|")
  check(P.validCode(code or ""), "server returned invalid invite code")
  return p, code, requestId
end
local function edit(core, p, x, y, z, id)
  core:received(p, ("VIEW|%d|%d"):format(math.floor(x / P.CHUNK), math.floor(y / P.CHUNK)))
  core:received(p, ("SET|%d|%d|%d|%d"):format(x, y, z, id))
end

-- Create/save one world, then create a second: IDs and file sets must stay separate.
local firstServer = server()
local owner1, code1, firstRequest = host(firstServer, "Forest Home")
local retryPeer = peer(firstServer)
firstServer:received(retryPeer,
  ("HOST|%d|1|0|-|%s|%s|%s"):format(P.VERSION, signature, "Forest Home", firstRequest))
local retryWelcome = sent(retryPeer, "WELCOME|")
check(retryWelcome and retryWelcome:find("|" .. code1 .. "|", 1, true),
      "repeated create request made a second cloud world")
firstServer:disconnected(retryPeer)
edit(firstServer, owner1, 1, 2, 3, 1)
firstServer:tick(5)
local afterAutosave = assert(store:load(code1))
check(afterAutosave.generation >= 2 and afterAutosave.editCount == 1, "autosave did not persist edit")

edit(firstServer, owner1, 4, 5, 6, 0)
firstServer:received(owner1, "SAVE")
check(sent(owner1, "SAVED|"), "explicit save was not acknowledged")
firstServer:disconnected(owner1)
local persisted1 = assert(store:load(code1))
check(persisted1.editCount == 2 and persisted1.name == "Forest Home", "leave save lost edits")

local owner2, code2 = host(firstServer, "Ocean Base")
check(code1 ~= code2, "two worlds were assigned the same code")
edit(firstServer, owner2, 8, 8, 8, 1)
firstServer:disconnected(owner2)
local persisted2 = assert(store:load(code2))
check(persisted2.editCount == 1 and persisted2.code == code2, "second world's data was not isolated")

-- Simulate a process restart: a fresh Core must load both disk-backed worlds.
local restarted = server()
check(restarted.rooms[code1] and restarted.rooms[code2], "restart did not reload both worlds")
check(restarted.rooms[code1].chunks["0,0,0"].edits["1,2,3"] == 1,
      "restart did not restore first world block")
check(restarted.rooms[code2].chunks["0,0,0"].edits["8,8,8"] == 1,
      "restart mixed or lost second world block")
local retryAfterRestart = peer(restarted)
restarted:received(retryAfterRestart,
  ("HOST|%d|1|0|-|%s|%s|%s"):format(P.VERSION, signature, "Forest Home", firstRequest))
local restartWelcome = sent(retryAfterRestart, "WELCOME|")
check(restartWelcome and restartWelcome:find("|" .. code1 .. "|", 1, true),
      "retry after restart created a duplicate world")
restarted:disconnected(retryAfterRestart)

-- Reconnect by invite code and verify the normal VIEW chunk stream contains the saved state.
local joiner = peer(restarted)
restarted:received(joiner, ("JOIN|%d|1|0|-|%s|%s"):format(P.VERSION, signature, code1))
check(sent(joiner, "WELCOME|"), "reconnect failed")
restarted:received(joiner, "VIEW|0|0")
restarted:tick(0.1)
local editsMessage = sent(joiner, "EDITS|")
check(editsMessage and editsMessage:find("1,2,3,1", 1, true)
      and editsMessage:find("4,5,6,0", 1, true), "reconnect stream omitted saved block edits")

-- A failed write may damage only the inactive slot; the previous generation must still load.
local beforeFailure = assert(store:load(code1))
local mutable = restarted.rooms[code1]
mutable.chunks["0,0,0"].edits["7,7,7"] = 1
mutable.editCount = mutable.editCount + 1
fs.failNextWrite = true
local saveOk = store:save(mutable)
check(not saveOk, "simulated short write unexpectedly succeeded")
local recovered = assert(store:load(code1))
check(recovered.generation == beforeFailure.generation and recovered.editCount == beforeFailure.editCount,
      "failed save replaced the last complete generation")

-- A malformed newest slot falls back to the older verified generation.
local savedOk, newGen = store:save(mutable)
check(savedOk and newGen, "valid retry save failed")
local newestSlot = newGen % 2 == 1 and "a" or "b"
fs.files["worlds/" .. code1 .. "." .. newestSlot] = "partial"
local fallback = assert(store:load(code1))
check(fallback.generation == beforeFailure.generation, "corrupt newest generation did not fall back")

-- The Multiplayer menu's device-local index contains only invite codes and names.
local catalogFiles = {}
love = {filesystem = {
  read = function(path) return catalogFiles[path] end,
  write = function(path, data) catalogFiles[path] = data; return true, #data end,
}}
package.loaded["net.world_catalog"] = nil
local Catalog = require "net.world_catalog"
check(Catalog.add(code1, "Forest Home") and Catalog.add(code2, "Ocean Base"),
      "device world catalog could not save entries")
check(#Catalog.list() == 2, "device world catalog did not list saved entries")
catalogFiles["cloud_worlds.b"] = "torn catalog"
package.loaded["net.world_catalog"] = nil
Catalog = require "net.world_catalog"
check(#Catalog.list() == 1 and Catalog.list()[1].code == code1,
      "catalog did not fall back to its previous valid generation")

-- Verify the client sends the v3 host request and recognizes the server's save acknowledgment.
local Client = require "net.client"
local packets, events = {}, {{type = "connect"}}
local transport = {
  connect = function() end,
  send = function(_, text) packets[#packets + 1] = text end,
  poll = function() local batch = events; events = {}; return batch end,
  disconnect = function() end,
}
local client = Client.new(transport, {
  mode = "host", safe = true, nameId = 0, custom = "-", sig = signature,
  worldName = "Client Test", createId = "BBBBBBBBBBBBBBBBBBBBBBBB",
})
client:connect("localhost:22122")
client:update(0.1)
check(packets[1] == ("HOST|%d|1|0|-|%s|Client Test|%s"):format(
      P.VERSION, signature, "BBBBBBBBBBBBBBBBBBBBBBBB"), "client host protocol fields mismatch")
client:handle(("WELCOME|1|%s|2000000000|%s|Client Test"):format(code1, signature))
client:handle("READY")
check(client.status == "ready" and client.seed == 2000000000, "client rejected a valid high seed")
check(client:saveNow() and packets[#packets] == "SAVE", "client did not request a cloud save")
client:handle("SAVED|1234567890")
check(client.saveResult and client.saveResult.ok
      and client.saveResult.generation == 1234567890, "client rejected a valid save acknowledgment")

-- A server that never completes the connection produces a visible client-side timeout.
local offlineTransport = {
  connect = function() end,
  send = function() end,
  poll = function() return {} end,
  disconnect = function() end,
}
local offlineClient = Client.new(offlineTransport, {
  mode = "join", safe = true, nameId = 0, custom = "-", sig = signature, code = code1,
})
offlineClient:connect("unreachable.example:22122")
offlineClient:update(11)
check(offlineClient.status == "error"
      and offlineClient.error:find("Could not reach the server", 1, true),
      "unavailable server did not produce a useful timeout")

print("PASS cloud save tests: format/corruption, create/retry, autosave, explicit save, leave, isolation, restart/reconnect, recovery, catalog, protocol, connection timeout")

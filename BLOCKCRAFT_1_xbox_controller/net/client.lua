-- ============================================================
-- client.lua - the game's side of the conversation (see protocol.lua).
-- No LÖVE code in here: it talks through a "transport" object, so the tests can
-- plug in a fake one. The real one is net/enet_transport.lua.
--
-- A transport has:  connect(address)  send(text, reliable)  poll() -> list of events
--                   disconnect()      events: {type="connect"} {type="receive", data=}
--                                             {type="disconnect"}
--
-- status: "idle" -> "connecting" -> "joining" -> "loading" -> "ready"
--         or "error" (see .error) / "closed"
--
-- Everything the server says is checked again here: a bad server cannot crash
-- the game or put weird text on the screen.
-- ============================================================
local P = require "net.protocol"

local Client = {}
Client.__index = Client

local CONNECT_TIMEOUT = 10 -- seconds

-- printable plain text only, short (names / errors that came over the network)
local function clean(s, max)
  s = tostring(s or ""):gsub("[^%w %.,:!%?%-']", "")
  return s:sub(1, max or 40)
end

function Client.new(transport, opts)
  return setmetatable({
    t = transport, opts = opts, status = "idle", error = nil,
    players = {},        -- pid -> {name=, x=,y=,z=, tx=,ty=,tz=, yaw=, pitch=}
    initialEdits = {},   -- (not used any more: changes arrive as EDITS after we send VIEW)
    remoteSets = {},     -- {x,y,z,id} changes from the server / others, waiting to be applied
    pid = nil, code = nil, seed = nil, worldName = nil,
    saveResult = nil,
    age = 0, posTimer = 0,
  }, Client)
end

function Client:connect(address)
  self.status = "connecting"
  self.age = 0
  self.t:connect(address)
end

local function fail(self, reason)
  if self.status == "error" or self.status == "closed" then return end
  self.status = "error"
  self.error = reason
  pcall(self.t.disconnect, self.t)
end

function Client:handle(msg)
  local f = P.split(msg)
  local kind = f[1]

  if kind == "WELCOME" then
    -- WELCOME|pid|CODE|seed|sig|worldName
    local pid, seed = P.int(f[2], 0, 1e9), P.int(f[4], 0, 2147483647)
    if not (pid and seed and P.validCode(f[3] or "") and P.validSig(f[5] or "")
        and P.validWorldName(f[6] or "")) then return fail(self, "bad answer from server") end
    self.pid, self.code, self.seed, self.worldName = pid, f[3], seed, f[6]
    self.status = "loading"

  elseif kind == "PLAYER" or kind == "JOINED" then
    local pid = P.int(f[2], 0, 1e9)
    if pid then self.players[pid] = {name = clean(f[3], 24)} end

  elseif kind == "LEFT" then
    local pid = P.int(f[2], 0, 1e9)
    if pid then self.players[pid] = nil end

  elseif kind == "EDITS" then
    -- block changes in a chunk near us (streamed by the server after our VIEW message)
    for item in (f[2] or ""):gmatch("[^;]+") do
      local sx, sy, sz, sid = item:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%d+)$")
      local x, y = P.int(sx, -P.WORLD_LIMIT, P.WORLD_LIMIT), P.int(sy, -P.WORLD_LIMIT, P.WORLD_LIMIT)
      local z, id = P.int(sz, 0, P.WORLD_H - 1), P.int(sid, 0, 100000)
      if x and y and z and id and #self.remoteSets < P.MAX_EDITS then
        self.remoteSets[#self.remoteSets + 1] = {x, y, z, id}
      end
    end

  elseif kind == "READY" then
    if self.status == "loading" then self.status = "ready" end

  elseif kind == "SAVED" then
    local generation = P.int(f[2], 1, 2147483647)
    if generation then self.saveResult = {ok = true, generation = generation} end

  elseif kind == "SAVEERR" then
    self.saveResult = {ok = false, message = clean(f[2], 80)}

  elseif kind == "P" then
    local pid = P.int(f[2], 0, 1e9)
    local p = pid and self.players[pid]
    local L = P.WORLD_LIMIT + 5
    local x, y, z = P.num(f[3], -L, L), P.num(f[4], -L, L), P.num(f[5], -40, P.WORLD_H + 40)
    local yaw, pitch = P.num(f[6], -100, 100), P.num(f[7], -3, 3)
    if p and x and y and z and yaw and pitch then
      if not p.tx then p.x, p.y, p.z = x, y, z end
      p.tx, p.ty, p.tz, p.yaw, p.pitch = x, y, z, yaw, pitch
    end

  elseif kind == "S" then
    local L = P.WORLD_LIMIT
    local x, y, z = P.int(f[3], -L, L), P.int(f[4], -L, L), P.int(f[5], 0, P.WORLD_H - 1)
    local id = P.int(f[6], 0, 100000)
    if x and y and z and id and #self.remoteSets < P.MAX_EDITS then
      self.remoteSets[#self.remoteSets + 1] = {x, y, z, id}
    end

  elseif kind == "ERR" then
    fail(self, clean(f[2], 80))
  end
end

function Client:update(dt)
  if self.status == "idle" or self.status == "error" or self.status == "closed" then return end
  self.age = self.age + dt
  if self.status == "connecting" and self.age > CONNECT_TIMEOUT then
    return fail(self, "Could not reach the server. Check the address.")
  end

  for _, ev in ipairs(self.t:poll()) do
    if ev.type == "connect" then
      local o = self.opts
      local line
      if o.mode == "host" then
        line = ("HOST|%d|%d|%d|%s|%s|%s|%s"):format(
          P.VERSION, o.safe and 1 or 0, o.nameId, o.custom or "-", o.sig, o.worldName, o.createId)
      else
        line = ("JOIN|%d|%d|%d|%s|%s|%s"):format(P.VERSION, o.safe and 1 or 0, o.nameId,
                                                   o.custom or "-", o.sig, o.code)
      end
      self.t:send(line, true)
      self.status = "joining"
    elseif ev.type == "receive" then
      self:handle(ev.data)
    elseif ev.type == "disconnect" then
      if self.status == "ready" then fail(self, "Lost connection to the server.")
      elseif self.status ~= "closed" then fail(self, "The server closed the connection.") end
    end
  end
end

-- call every frame while playing; sends about 15 times per second
function Client:sendPos(dt, x, y, z, yaw, pitch)
  if self.status ~= "ready" then return end
  self.posTimer = self.posTimer + dt
  if self.posTimer < 1 / 15 then return end
  self.posTimer = 0
  self.t:send(("POS|%.2f|%.2f|%.2f|%.2f|%.2f"):format(x, y, z, yaw % (2 * math.pi), pitch), false)
end

function Client:sendSet(x, y, z, id)
  if self.status ~= "ready" then return end
  self.t:send(("SET|%d|%d|%d|%d"):format(x, y, z, id), true)
end

-- "I am in chunk column cx,cy": the server answers with the block changes around it
function Client:sendView(cx, cy)
  if self.status ~= "ready" then return end
  self.t:send(("VIEW|%d|%d"):format(cx, cy), true)
end

function Client:sendEmote(id)
  if self.status ~= "ready" then return end
  self.t:send(("EMOTE|%d"):format(id), true)
end

function Client:saveNow()
  if self.status ~= "ready" then return false end
  self.saveResult = nil
  self.t:send("SAVE", true)
  return true
end

function Client:leave()
  if self.status == "closed" then return end
  if self.status == "ready" or self.status == "loading" or self.status == "joining" then
    pcall(self.t.send, self.t, "BYE", true)
  end
  self.status = "closed"
  pcall(self.t.disconnect, self.t)
end

return Client

-- ============================================================
-- server_core.lua - the rules of the multiplayer server (no network code in here).
-- net/server_main.lua gives it real connections; the tests give it fake ones.
--
-- What the server does:
--   * keeps saved ROOMS. A room has an invite code, a world seed, the block changes
--     made so far (stored per 16x16x16 chunk) and up to 8 players.
--   * the terrain is NEVER sent: every game builds it from the seed. The server only
--     streams block changes, chunk by chunk, to players who are near them (VIEW message).
--   * passes each player's position and block changes on to the others.
--   * enforces SAFE MODE: a safe player never receives a custom name, and
--     a player can only ever send the few message types in protocol.lua.
--   * protects itself: checks every number, limits how fast a player may send,
--     and removes players who keep breaking the rules.
--
-- Use:  local core = Core.new{send = function(peer, text, reliable) end,
--                              disconnect = function(peer) end,
--                              random = love.math.random}
--       core:connected(peer)  core:received(peer, text)  core:disconnected(peer)
--       core:tick(dt)          -- call often; refills the speed limits
-- ============================================================
local P = require "net.protocol"

local Core = {}
Core.__index = Core

-- messages allowed per second, per player
local LIMITS = {POS = 30, SET = 25, other = 5}
local MAX_STRIKES = 200 -- ignored messages before a player is removed
local STREAM_PER_TICK = 6  -- chunks of block changes sent to each player per server tick
local EDITS_PER_MESSAGE = 120
local SAVE_INTERVAL = 5    -- seconds between durable writes while a world is changing

local floor, abs = math.floor, math.abs

local function chunkKey(cx, cy, cz) return cx .. "," .. cy .. "," .. cz end

-- how many chunk columns apart (the larger of the x / y difference) the player is from a chunk
local function columnsAway(player, cx, cy)
  local v = player.view
  if not v then return math.huge end
  return math.max(abs(cx - v[1]), abs(cy - v[2]))
end

function Core.new(opts)
  local self = setmetatable({}, Core)
  self.send = opts.send
  self.disconnect = opts.disconnect or function() end
  self.random = opts.random or math.random
  self.rooms = {}      -- code -> room
  self.createRequests = {} -- retry id -> saved room, prevents duplicate worlds on lost WELCOME
  self.totalEditCount = 0
  self.peers = {}      -- peer -> player
  self.nextPid = 1
  self.clock = 0       -- seconds since the server started (for emote cooldowns)
  self.log = opts.log or function() end
  self.store = opts.store
  if self.store then
    local rooms, errors = self.store:loadAll()
    for _, room in ipairs(rooms) do
      room.lastSaved = self.clock
      self.rooms[room.code] = room
      self.totalEditCount = self.totalEditCount + room.editCount
      if room.createId and not self.createRequests[room.createId] then
        self.createRequests[room.createId] = room
      end
      self.log(("loaded cloud world %s (%d block edits, generation %d)"):format(
        room.code, room.editCount, room.generation))
    end
    for _, entry in ipairs(errors) do
      self.log(("cloud world %s was not loaded: %s"):format(entry.code, entry.error))
    end
  end
  return self
end

-- ---------- helpers ----------
local function tell(self, player, text, reliable)
  self.send(player.peer, text, reliable ~= false)
end

-- what `viewer` is allowed to see as `who`'s name
local function nameFor(viewer, who)
  if who.custom and not viewer.safe then return who.custom end
  return who.preset
end

local function makeCode(self)
  for _ = 1, 100 do
    local c = {}
    for i = 1, P.CODE_LENGTH do
      local k = self.random(1, #P.CODE_LETTERS)
      c[i] = P.CODE_LETTERS:sub(k, k)
    end
    local code = table.concat(c)
    if not self.rooms[code] and not (self.store and self.store:exists(code)) then return code end
  end
end

local function roomCount(room)
  local n = 0
  for _ in pairs(room.players) do n = n + 1 end
  return n
end

local function worldCount(self)
  local n = 0
  for _ in pairs(self.rooms) do n = n + 1 end
  return n
end

local function broadcast(self, room, except, textFn, reliable)
  for _, p in pairs(room.players) do
    if p ~= except then tell(self, p, textFn(p), reliable) end
  end
end

local function fail(self, player, reason)
  tell(self, player, "ERR|" .. reason)
  self.log(("player %d: %s"):format(player.pid, reason))
end

-- ---------- connection events ----------
function Core:connected(peer)
  self.peers[peer] = {peer = peer, pid = self.nextPid, tokens = {POS = LIMITS.POS,
                      SET = LIMITS.SET, other = LIMITS.other}, strikes = 0,
                      view = nil,      -- {cx, cy}: the chunk column the player is in
                      sent = {},       -- chunk key -> true: this player already has that chunk's changes
                      queue = {}, qi = 1}  -- chunks of changes still to send
  self.nextPid = self.nextPid + 1
end

local function leave(self, player)
  local room = player.room
  if not room then return end
  if room.dirty and self.store then
    local ok, result = self.store:save(room)
    if ok then
      room.generation, room.dirty, room.lastSaved = result, false, self.clock
      self.log(("saved cloud world %s at generation %d on player leave"):format(room.code, result))
    else
      self.log(("could not save cloud world %s on player leave: %s"):format(room.code, tostring(result)))
    end
  end
  room.players[player.pid] = nil
  player.room = nil
  broadcast(self, room, player, function() return "LEFT|" .. player.pid end)
  if next(room.players) == nil then self.log("cloud world " .. room.code .. " is idle and saved") end
end

function Core:disconnected(peer)
  local player = self.peers[peer]
  if player then leave(self, player) end
  self.peers[peer] = nil
end

-- send one chunk's block changes to a player
local function sendChunkEdits(self, player, ck, ch)
  player.sent[ck] = true
  local items = {}
  local function flush()
    if #items > 0 then tell(self, player, "EDITS|" .. table.concat(items, ";")); items = {} end
  end
  for pos, id in pairs(ch.edits) do
    items[#items + 1] = pos .. "," .. id
    if #items >= EDITS_PER_MESSAGE then flush() end
  end
  flush()
end

function Core:tick(dt)
  self.clock = self.clock + dt
  for _, p in pairs(self.peers) do
    for k, limit in pairs(LIMITS) do
      p.tokens[k] = math.min(limit, p.tokens[k] + limit * dt)
    end
    -- streaming: a few chunks of block changes per tick, nearest first
    if p.room then
      local sent = 0
      while p.qi <= #p.queue and sent < STREAM_PER_TICK do
        local item = p.queue[p.qi]
        p.qi = p.qi + 1
        if not p.sent[item.ck] then
          sendChunkEdits(self, p, item.ck, item.ch)
          sent = sent + 1
        end
      end
    end
  end
  if self.store then
    for _, room in pairs(self.rooms) do
      if room.dirty and self.clock - (room.lastSaved or 0) >= SAVE_INTERVAL then
        local ok, result = self.store:save(room)
        if ok then
          room.generation, room.dirty, room.lastSaved = result, false, self.clock
          self.log(("autosaved cloud world %s at generation %d"):format(room.code, result))
        else
          -- Leave the last verified generation untouched; retry on the next interval.
          room.lastSaved = self.clock
          self.log(("could not autosave cloud world %s: %s"):format(room.code, tostring(result)))
        end
      end
    end
  end
end

-- ---------- joining ----------
local function enter(self, player, room)
  room.players[player.pid] = player
  player.room = room

  tell(self, player, ("WELCOME|%d|%s|%d|%s|%s"):format(
    player.pid, room.code, room.seed, room.sig, room.name))
  for _, other in pairs(room.players) do
    if other ~= player then
      tell(self, player, ("PLAYER|%d|%s"):format(other.pid, nameFor(player, other)))
    end
  end
  -- (block changes are not sent here: the player sends VIEW and gets the ones nearby)
  tell(self, player, "READY")
  broadcast(self, room, player, function(p)
    return ("JOINED|%d|%s"):format(player.pid, nameFor(p, player))
  end)
  self.log(("player %d joined room %s (%d players)"):format(player.pid, room.code, roomCount(room)))
end

local function handleJoin(self, player, f, hosting)
  if player.room then return fail(self, player, "already in a room") end
  local need = hosting and 8 or 7
  if #f ~= need then return fail(self, player, "bad message") end

  if P.int(f[2], 0, 1000) ~= P.VERSION then
    return fail(self, player, "update the game: versions do not match")
  end
  local safe = P.int(f[3], 0, 1)
  local nameId = P.int(f[4], 0, P.NAME_COUNT - 1)
  local custom = f[5]
  local sig = f[6]
  if safe == nil or nameId == nil or not P.validSig(sig) then
    return fail(self, player, "bad message")
  end

  player.safe = (safe == 1)
  player.preset = P.presetName(nameId)
  player.custom = nil
  -- a custom name is only accepted from a player whose safe mode is OFF
  if custom ~= "-" and custom ~= "" then
    if player.safe then
      -- safe players cannot have one: ignore it (they still get a preset name)
    elseif P.validCustomName(custom) then
      player.custom = custom
    else
      return fail(self, player, "custom name: 3-12 letters or numbers only")
    end
  end

  local room
  if hosting then
    local worldName = f[7]
    if not P.validWorldName(worldName) then return fail(self, player, "world name: use 1-24 letters, numbers, spaces, _ or -") end
    local createId = f[8]
    if not P.validRequestId(createId) then return fail(self, player, "bad create request") end
    room = self.createRequests[createId]
    if room then
      if room.sig ~= sig or room.name ~= worldName then
        return fail(self, player, "create request does not match the saved world")
      end
      if roomCount(room) >= P.MAX_PLAYERS then return fail(self, player, "room is full") end
    else
      if worldCount(self) >= P.MAX_WORLDS then
        return fail(self, player, "server world limit reached")
      end
      local code = makeCode(self)
      if not code then return fail(self, player, "server is busy, try again") end
      room = {code = code, createId = createId, name = worldName,
              seed = self.random(1, 2000000000), sig = sig,
              chunks = {}, editCount = 0, players = {}, generation = 0,
              dirty = false, lastSaved = self.clock}
      -- Reserve the code durably before telling the client that creation succeeded.
      if self.store then
        local ok, result = self.store:save(room)
        if not ok then return fail(self, player, "could not create cloud world: " .. tostring(result)) end
        room.generation, room.dirty, room.lastSaved = result, false, self.clock
      end
      self.rooms[code] = room
      self.createRequests[createId] = room
      self.log("cloud world " .. code .. " created")
    end
  else
    local code = f[7]:upper()
    room = P.validCode(code) and self.rooms[code]
    if not room then return fail(self, player, "no room with that code") end
    if roomCount(room) >= P.MAX_PLAYERS then return fail(self, player, "room is full") end
    if room.sig ~= sig then
      return fail(self, player, "your blocks/mods are different from the host's")
    end
  end
  enter(self, player, room)
end

-- ---------- messages while playing ----------
local function handlePos(self, player, f)
  local room = player.room
  if not room or #f ~= 6 then return end
  local L = P.WORLD_LIMIT + 5
  local x, y, z = P.num(f[2], -L, L), P.num(f[3], -L, L), P.num(f[4], -30, P.WORLD_H + 40)
  local yaw, pitch = P.num(f[5], -100, 100), P.num(f[6], -3, 3)
  if not (x and y and z and yaw and pitch) then return end
  local text = ("P|%d|%s|%s|%s|%s|%s"):format(player.pid, f[2], f[3], f[4], f[5], f[6])
  broadcast(self, room, player, function() return text end, false)
end

-- VIEW|cx|cy : "I am in this chunk column". Queue the block changes around it.
local function handleView(self, player, f)
  local room = player.room
  if not room or #f ~= 3 then return end
  local lim = floor(P.WORLD_LIMIT / P.CHUNK) + 1
  local cx, cy = P.int(f[2], -lim, lim), P.int(f[3], -lim, lim)
  if not (cx and cy) then return end
  player.view = {cx, cy}

  local list = {}
  for ck, ch in pairs(room.chunks) do
    if not player.sent[ck] then
      local d = columnsAway(player, ch.cx, ch.cy)
      if d <= P.VIEW_RADIUS then list[#list + 1] = {ck = ck, ch = ch, d = d} end
    end
  end
  table.sort(list, function(a, b) if a.d ~= b.d then return a.d < b.d end return a.ck < b.ck end)
  player.queue, player.qi = list, 1
end

local function handleSet(self, player, f)
  local room = player.room
  if not room or #f ~= 5 then return end
  local L = P.WORLD_LIMIT
  local x, y, z = P.int(f[2], -L, L), P.int(f[3], -L, L), P.int(f[4], 0, P.WORLD_H - 1)
  local id = P.int(f[5], 0, P.sigCount(room.sig))
  if not (x and y and z and id) then return end

  local cx, cy, cz = floor(x / P.CHUNK), floor(y / P.CHUNK), floor(z / P.CHUNK)
  -- you can only change blocks near where you said you are (no griefing from across the map)
  if columnsAway(player, cx, cy) > P.VIEW_RADIUS then return end

  local ck = chunkKey(cx, cy, cz)
  local ch = room.chunks[ck]
  local pos = x .. "," .. y .. "," .. z
  local previous = ch and ch.edits[pos]
  if previous == id then return end
  if previous == nil then
    if room.editCount >= P.MAX_EDITS or self.totalEditCount >= P.MAX_SERVER_EDITS then return end
    if not ch then
      ch = {cx = cx, cy = cy, cz = cz, edits = {}}
      room.chunks[ck] = ch
    end
    room.editCount = room.editCount + 1
    self.totalEditCount = self.totalEditCount + 1
  end
  ch.edits[pos] = id
  room.dirty = true

  local text = ("S|%d|%d|%d|%d|%d"):format(player.pid, x, y, z, id)
  for _, p in pairs(room.players) do
    if p ~= player then
      if p.sent[ck] then
        tell(self, p, text)                       -- they have this chunk's changes: keep them current
      elseif columnsAway(p, cx, cy) <= P.VIEW_RADIUS then
        sendChunkEdits(self, p, ck, ch)           -- first change here, and they are near: send the chunk
      end
      -- otherwise they are far away: they get it when they come near (VIEW)
    end
  end
end

local function handleSave(self, player)
  local room = player.room
  if not room then return end
  if not self.store then
    tell(self, player, "SAVEERR|server storage is not configured")
    return
  end
  local ok, result = self.store:save(room)
  if ok then
    room.generation, room.dirty, room.lastSaved = result, false, self.clock
    tell(self, player, "SAVED|" .. result)
    self.log(("saved cloud world %s at generation %d on request"):format(room.code, result))
  else
    tell(self, player, "SAVEERR|could not save the cloud world")
    self.log(("could not save cloud world %s on request: %s"):format(room.code, tostring(result)))
  end
end

-- emotes are just a number 1-5; one every 1.5 seconds per player
local EMOTE_COOLDOWN = 1.5

local function handleEmote(self, player, f)
  local room = player.room
  if not room or #f ~= 2 then return end
  local id = P.int(f[2], 1, P.EMOTE_COUNT)
  if not id then return end
  if self.clock - (player.lastEmote or -100) < EMOTE_COOLDOWN then return end
  player.lastEmote = self.clock
  local text = ("E|%d|%d"):format(player.pid, id)
  broadcast(self, room, player, function() return text end)
end

function Core:received(peer, text)
  local player = self.peers[peer]
  if not player or type(text) ~= "string" or #text > 4000 then return end

  local f = P.split(text)
  local kind = f[1]
  local bucket = (kind == "POS" or kind == "SET") and kind or "other"
  if player.tokens[bucket] < 1 then
    player.strikes = player.strikes + 1
    if player.strikes > MAX_STRIKES then
      self.log(("player %d removed: sending too fast"):format(player.pid))
      self.disconnect(peer)
    end
    return
  end
  player.tokens[bucket] = player.tokens[bucket] - 1

  if kind == "POS" then handlePos(self, player, f)
  elseif kind == "SET" then handleSet(self, player, f)
  elseif kind == "VIEW" then handleView(self, player, f)
  elseif kind == "EMOTE" then handleEmote(self, player, f)
  elseif kind == "HOST" then handleJoin(self, player, f, true)
  elseif kind == "JOIN" then handleJoin(self, player, f, false)
  elseif kind == "SAVE" and #f == 1 then handleSave(self, player)
  elseif kind == "BYE" and #f == 1 then
    leave(self, player)
    self.disconnect(peer)
  end
  -- anything else (chat, commands, ...) is simply ignored
end

function Core:shutdown()
  if not self.store then return end
  for _, room in pairs(self.rooms) do
    if room.dirty then
      local ok, result = self.store:save(room)
      if ok then
        room.generation, room.dirty, room.lastSaved = result, false, self.clock
        self.log(("saved cloud world %s at shutdown (generation %d)"):format(room.code, result))
      else
        self.log(("could not save cloud world %s at shutdown: %s"):format(room.code, tostring(result)))
      end
    end
  end
end

return Core

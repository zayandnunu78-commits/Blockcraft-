-- ============================================================
-- session.lua - connects the multiplayer client (net/client.lua) to the game:
--   * starts / leaves a game      S.start("host" | "join", address, code)  S.leave()
--   * builds the shared world from the host's seed and applies block changes
--   * sends your position and block changes, applies other players' changes
--   * draws the other players (simple coloured figures) and the world invite code
-- ============================================================
local g3d = require "g3d"
local world = require "world"
local worldgen = require "worldgen"
local mesher = require "mesher"
local chunks = require "chunks"
local save = require "save"
local health = require "health"
local player = require "player"
local input = require "input"
local blocks = require "blocks"
local faces = require "faces"
local gs = require "gamestate"
local P = require "net.protocol"
local Client = require "net.client"
local safety = require "net.safety"
local emotes = require "net.emotes"
local catalog = require "net.world_catalog"

local S = {client = nil, inGame = false, status = nil, statusOk = true,
           emoteOpen = false, emoteOpenT = 0, myEmote = nil, lastEmote = -10,
           lastAttempt = nil, retryAvailable = false, message = function() end}

local order = {1, 2, 3, 1, 3, 4}
local models = {} -- colour index -> model
local palette = {{0.9, 0.3, 0.3}, {0.3, 0.6, 0.95}, {0.95, 0.8, 0.2}, {0.4, 0.8, 0.4},
                 {0.8, 0.45, 0.9}, {0.95, 0.55, 0.2}, {0.3, 0.85, 0.85}, {0.9, 0.5, 0.7}}
local white

function S.colorOf(pid) return palette[(pid or 0) % #palette + 1] end

local function say(ok, text) S.statusOk, S.status = ok, text end

local function newCreateId()
  local out = {}
  for i = 1, 24 do
    local index = love.math.random(1, #P.CODE_LETTERS)
    out[i] = P.CODE_LETTERS:sub(index, index)
  end
  return table.concat(out)
end

-- a box made of the cube faces from faces.lua, coloured with vertex colours
local function addBox(verts, x0, y0, z0, x1, y1, z1, c, shadeBoost)
  for _, f in ipairs(faces) do
    local shade = math.min(1, f.s * (shadeBoost or 1))
    for i = 1, 6 do
      local p = f.v[order[i]]
      verts[#verts + 1] = {x0 + p[1] * (x1 - x0), y0 + p[2] * (y1 - y0), z0 + p[3] * (z1 - z0),
                           0, 0, f.n[1], f.n[2], f.n[3], c[1] * shade, c[2] * shade, c[3] * shade, 1}
    end
  end
end

local function modelFor(pid)
  local key = pid % #palette + 1
  if not models[key] then
    if not white then
      local d = love.image.newImageData(1, 1)
      d:setPixel(0, 0, 1, 1, 1, 1)
      white = love.graphics.newImage(d)
    end
    local c = palette[key]
    local verts = {}
    addBox(verts, -0.3, -0.2, 0.0, 0.3, 0.2, 1.1, c)                       -- body
    addBox(verts, -0.25, -0.25, 1.1, 0.25, 0.25, 1.65, {1, 0.85, 0.7})      -- head
    addBox(verts, 0.25, -0.1, 1.3, 0.4, 0.1, 1.45, {0.2, 0.2, 0.25})        -- "nose": shows where they look
    models[key] = g3d.newModel(verts, white)
  end
  return models[key]
end

-- ---------- start / stop ----------
function S.active() return S.client ~= nil end

local function validAddress(a)
  return type(a) == "string" and #a >= 3 and #a <= 80 and a:match("^[%w%.%-]+:?%d*$") ~= nil
end

function S.start(mode, address, code, worldName, createId)
  if S.client then return false end
  S.retryAvailable = false
  if not validAddress(address) then
    say(false, "Type the server address first, for example myserver.com or 203.0.113.5:22122")
    return false
  end
  if address:sub(-1) == ":" then
    address = address .. P.PORT
  elseif not address:find(":", 1, true) then
    address = address .. ":" .. P.PORT
  end
  local requestedPort = address:match(":(%d+)$")
  if requestedPort and tonumber(requestedPort) ~= P.PORT then
    say(false, "BLOCKCRAFT 1 uses UDP port 22122. Remove the other port from the server address.")
    return false
  end
  worldName = (mode == "host" and P.validWorldName(worldName or ""))
      and worldName or "My World"
  if mode == "host" and not P.validRequestId(createId or "") then createId = newCreateId() end
  S.lastAttempt = {mode = mode, address = address, code = code, worldName = worldName, createId = createId}

  local names = {}
  for i = 1, #blocks do names[i] = blocks[i].key end

  local ok, transport = pcall(function() return require("net.enet_transport").new() end)
  if not ok or not transport then
    S.retryAvailable = true
    say(false, "Multiplayer is not available in this version of LÖVE.")
    return false
  end

  safety.server = address
  safety.save()
  S.client = Client.new(transport, {
    mode = mode, safe = safety.safe, nameId = safety.nameId,
    custom = (not safety.safe and safety.custom ~= "") and safety.custom or "-",
    sig = P.makeSig(names), code = code, worldName = worldName, createId = createId,
  })
  S.seenSaveResult = nil
  S.cataloguedCode = nil
  local okC, err = pcall(S.client.connect, S.client, address)
  if not okC then
    S.client = nil
    S.retryAvailable = true
    say(false, "Could not connect: " .. tostring(err))
    return false
  end
  say(true, "Connecting...")
  return true
end

-- Restore only the existing non-interactive menu backdrop after online play ends.
local function restoreLocalWorld()
  world.onSet, world.silent = nil, false
  world.clear()
  worldgen.generate()
  player.spawn()
  chunks.flush(player.x, player.y, player.z)
end

local function teardown()
  local wasInGame = S.inGame
  if S.client then S.client:leave() end
  S.client, S.inGame = nil, false
  S.emoteOpen, S.myEmote = false, nil
  if wasInGame then restoreLocalWorld() end
  gs.onlineSession = false
end

-- the pause menu's "Main Menu" button and quitting the game
function S.leave()
  if S.client then teardown() end
  if gs.current == "playing" or gs.current == "paused" then gs.set("menu") end
  S.status = nil
  S.retryAvailable = false
end

function S.canRetry() return S.retryAvailable and S.lastAttempt ~= nil end
function S.clearRetry() S.retryAvailable = false end

function S.retry()
  if not S.canRetry() then return false end
  local a = S.lastAttempt
  S.retryAvailable = false
  return S.start(a.mode, a.address, a.code, a.worldName, a.createId)
end

function S.saveNow()
  local c = S.client
  if not (c and S.inGame and c:saveNow()) then
    S.message("You must be connected to a cloud world to save it.", false)
    return false
  end
  S.seenSaveResult = nil
  S.message("Saving cloud world...", true)
  return true
end

-- the world is built from the host's seed, then earlier block changes are applied
local function begin()
  local c = S.client
  save.detach()            -- an online world is never written to a single-player save slot
  world.clear()
  world.silent = true
  worldgen.generate(c.seed)
  for _, e in ipairs(c.initialEdits) do world.set(e[1], e[2], e[3], e[4]) end
  world.silent = false
  world.onSet = function(x, y, z, id) c:sendSet(x, y, z, id) end
  player.spawn()
  health.reset()
  input.yaw, input.pitch, input.touches = 0, -0.2, {}
  chunks.flush(player.x, player.y, player.z)
  -- tell the server where we are: it streams the block changes near us (net/server_core.lua)
  S.viewCx, S.viewCy = math.floor(player.x / world.CS), math.floor(player.y / world.CS)
  c:sendView(S.viewCx, S.viewCy)
  S.inGame = true
  gs.onlineSession = true
  say(true, "")
  gs.set("playing")
end

function S.update(dt)
  local c = S.client
  if not c then return end
  c:update(dt)

  if c.code and S.cataloguedCode ~= c.code then
    local okCatalog, indexed = pcall(catalog.add, c.code, c.worldName)
    S.cataloguedCode = c.code
    if not okCatalog or not indexed then
      S.message("World is saved on the server, but this device could not update its saved-world list.", false)
    end
  end

  if c.saveResult and c.saveResult ~= S.seenSaveResult then
    S.seenSaveResult = c.saveResult
    if c.saveResult.ok then
      S.message("Cloud world saved on the server.", true)
    else
      S.message("Cloud save failed: " .. tostring(c.saveResult.message), false)
    end
  end

  if c.status == "error" or c.status == "closed" then
    local msg = c.error or "Disconnected."
    local wasInGame = S.inGame
    teardown()
    S.retryAvailable = S.lastAttempt ~= nil
    say(false, wasInGame and (msg .. " Offline play is disabled. Retry or go back to the menu.") or msg)
    if wasInGame then gs.set("worlds") end
    return
  end

  if c.status == "ready" and not S.inGame then
    begin()
  elseif not S.inGame then
    say(true, c.status == "connecting" and "Connecting..." or "Joining...")
    return
  end

  -- block changes from other players
  -- (at most 500 per frame, so a big burst of changes never freezes the game)
  local sets = c.remoteSets
  local n = math.min(#sets, 500)
  if n > 0 then
    world.silent = true
    for i = 1, n do local e = sets[i]; world.set(e[1], e[2], e[3], e[4]) end
    world.silent = false
    local rest = {}
    for i = n + 1, #sets do rest[#rest + 1] = sets[i] end
    c.remoteSets = rest
  end

  -- smooth movement of the other players
  local k = math.min(1, dt * 12)
  for _, p in pairs(c.players) do
    if p.tx then
      p.x, p.y, p.z = p.x + (p.tx - p.x) * k, p.y + (p.ty - p.y) * k, p.z + (p.tz - p.z) * k
    end
    if p.emoteT then -- emotes disappear after a few seconds
      p.emoteT = p.emoteT - dt
      if p.emoteT <= 0 then p.emote, p.emoteT = nil, nil end
    end
  end
  if S.myEmote then
    S.myEmote.t = S.myEmote.t - dt
    if S.myEmote.t <= 0 then S.myEmote = nil end
  end
  if S.emoteOpen then
    S.emoteOpenT = S.emoteOpenT - dt
    if S.emoteOpenT <= 0 then S.emoteOpen = false end
  end

  if gs.current == "playing" then
    c:sendPos(dt, player.x, player.y, player.z, input.yaw, input.pitch)
    -- entered a new chunk column: the server sends the changes made around it
    local vx, vy = math.floor(player.x / world.CS), math.floor(player.y / world.CS)
    if vx ~= S.viewCx or vy ~= S.viewCy then
      S.viewCx, S.viewCy = vx, vy
      c:sendView(vx, vy)
    end
  end
end

-- ---------- emotes (buttons, keys, sending) ----------
local EMOTE_KEYS = {z = 1, x = 2, c = 3, v = 4, b = 5}

local function emoteButton()
  local w = love.graphics.getWidth()
  return {x = w - 62, y = 70, w = 48, h = 48}
end

-- the 5 picture buttons, in a row to the left of the emote button (1 = leftmost)
local function emoteSlot(id)
  local b = emoteButton()
  return {x = b.x - (emotes.count + 1 - id) * 52, y = b.y + 1, w = 46, h = 46}
end

local function inside(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function S.sendEmote(id)
  local c = S.client
  if not (c and S.inGame) then return end
  if love.timer.getTime() - S.lastEmote < 1.5 then return end -- the server also enforces this
  S.lastEmote = love.timer.getTime()
  c:sendEmote(id)
  S.myEmote = {id = id, t = 2}
  S.emoteOpen = false
end

-- a tap on the emote button or one of the pictures; true if it was used
function S.pressed(x, y)
  if not (S.client and S.inGame) then return false end
  if inside(emoteButton(), x, y) then
    S.emoteOpen = not S.emoteOpen
    S.emoteOpenT = 8
    return true
  end
  if S.emoteOpen then
    for id = 1, emotes.count do
      if inside(emoteSlot(id), x, y) then
        S.sendEmote(id)
        return true
      end
    end
  end
  return false
end

-- desktop keys Z X C V B
function S.keypressed(key)
  local id = EMOTE_KEYS[key]
  if id and S.client and S.inGame then
    S.sendEmote(id)
    return true
  end
  return false
end

-- ---------- drawing ----------
function S.draw3d()
  local c = S.client
  if not (c and S.inGame) then return end
  for pid, p in pairs(c.players) do
    if p.x then
      local m = modelFor(pid)
      m:setTransform({p.x, p.y, p.z}, {0, 0, p.yaw or 0}, {1, 1, 1})
      m:draw()
      if p.emote and p.emoteT and p.emoteT > 0 then
        -- the emote sign floats over the head and turns to face you
        local face = (math.atan2 or math.atan)(player.y - p.y, player.x - p.x)
        local bob = math.sin(love.timer.getTime() * 4) * 0.06
        local em = emotes.model(p.emote)
        em:setTransform({p.x, p.y, p.z + 1.9 + bob}, {0, 0, face}, {1, 1, 1})
        em:draw()
      end
    end
  end
end

local hudFont
function S.drawHud()
  local c = S.client
  if not (c and S.inGame) then return end
  hudFont = hudFont or love.graphics.newFont(16)
  love.graphics.setFont(hudFont)
  local y = 34
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 6, y - 4, 190, 24 + 20 * (1 + (function() local n = 0 for _ in pairs(c.players) do n = n + 1 end return n end)()), 6, 6)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print("Invite code: " .. tostring(c.code), 12, y)
  y = y + 26
  local mine = S.colorOf(c.pid)
  love.graphics.setColor(mine[1], mine[2], mine[3], 1)
  love.graphics.rectangle("fill", 12, y + 3, 12, 12)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.print((safety.safe or safety.custom == "") and safety.presetName() or safety.custom, 30, y)
  y = y + 20
  for pid, p in pairs(c.players) do
    local col = S.colorOf(pid)
    love.graphics.setColor(col[1], col[2], col[3], 1)
    love.graphics.rectangle("fill", 12, y + 3, 12, 12)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(p.name or "?", 30, y)
    y = y + 20
  end
  -- emote button, the row of pictures, and your own emote
  local w = love.graphics.getWidth()
  local cooling = love.timer.getTime() - S.lastEmote < 1.5
  local eb = emoteButton()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", eb.x, eb.y, eb.w, eb.h, 8, 8)
  emotes.draw2d(3, eb.x + 8, eb.y + 8, 32, cooling and 0.4 or 1)
  if S.emoteOpen then
    for id = 1, emotes.count do
      local r = emoteSlot(id)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 8, 8)
      emotes.draw2d(id, r.x + 7, r.y + 7, 32, cooling and 0.4 or 1)
    end
  end
  if S.myEmote then
    emotes.draw2d(S.myEmote.id, w / 2 - 20, 72, 40, math.min(1, S.myEmote.t))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return S

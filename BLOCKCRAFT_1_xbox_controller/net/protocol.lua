-- ============================================================
-- protocol.lua - what the game and the server say to each other.
-- Shared by the client (net/client.lua) and the server (net/server_core.lua).
--
-- Messages are short lines of text with | between the fields.
--
--  client -> server
--    HOST|ver|safe|nameId|custom|sig|worldName|rid create/retry a saved room idempotently
--    JOIN|ver|safe|nameId|custom|sig|CODE          join a room
--    POS|x|y|z|yaw|pitch                           where I am (sent often, may be lost)
--    VIEW|cx|cy                                    I am in chunk column cx,cy (sent when I enter a new
--                                                  one). The server then streams me the block changes
--                                                  made in the chunks around it.
--    SET|x|y|z|id                                  I changed a block (id 0 = removed). Only accepted
--                                                  near where I said I am (see VIEW).
--    EMOTE|n                                       show emote number n (1-5): a picture, never words
--    BYE                                           I am leaving
--    SAVE                                          save this shared world now
--
--  server -> client
--    WELCOME|pid|CODE|seed|sig|worldName           you are in. Then PLAYER... EDITS... READY
--    PLAYER|pid|name                               someone who was already there
--    EDITS|x,y,z,id;x,y,z,id;...                   block changes in one chunk near you, streamed after
--                                                  VIEW (a few chunks per server tick, nearest first)
--    READY                                         you may start playing (the terrain itself is never
--                                                  sent: both sides build it from the seed)
--    SAVED|generation                              the server confirmed a durable world save
--    SAVEERR|reason                                the server could not save the world
--    JOINED|pid|name      LEFT|pid                 someone came / went
--    P|pid|x|y|z|yaw|pitch                         where somebody is
--    S|pid|x|y|z|id                                somebody changed a block (only sent if you have that
--                                                  chunk's changes)
--    E|pid|n                                       somebody showed emote n
--    ERR|reason                                    something went wrong
--
-- SAFE BY DESIGN: there is no chat message at all. The only text a player can send
-- is an optional custom name, and only when safe mode is OFF. Safe clients are never
-- sent a custom name: the server swaps it for the preset name (see server_core.lua).
-- ============================================================
local P = {
  VERSION = 3,          -- 3 = persistent cloud worlds; server and clients must update together
  PORT = 22122,
  MAX_PLAYERS = 8,
  WORLD_LIMIT = 1000000, -- blocks from the middle; must match world.lua (LIMIT)
  WORLD_H = 64,          -- must match world.lua (H = 4 chunks of 16)
  CHUNK = 16,
  VIEW_RADIUS = 10,      -- chunks around a player whose block changes the server cares about
  MAX_EDITS = 200000,    -- changed blocks one room may hold (stops a player filling up the server)
  MAX_WORLDS = 100,      -- bounds persistent world count on an unauthenticated invite-code server
  MAX_SERVER_EDITS = 500000,
  CODE_LENGTH = 12,     -- invitation code; worlds are separate and never keyed by player name
  EMOTE_COUNT = 5,       -- must match net/emotes.lua
  CODE_LETTERS = "ACDEFGHJKLMNPQRTUVWXY34679", -- no 0/O, 1/I/L, 5/S, 2/Z, 8/B mix-ups
}

-- ---------- preset names: 20 x 20 = 400 friendly names ----------
local adjectives = {"Happy", "Brave", "Sunny", "Swift", "Clever", "Cozy", "Lucky", "Jolly",
                    "Calm", "Bold", "Bright", "Gentle", "Silly", "Mighty", "Merry", "Witty",
                    "Zippy", "Kind", "Sparky", "Snowy"}
local animals = {"Fox", "Panda", "Otter", "Owl", "Koala", "Bunny", "Tiger", "Penguin",
             "Turtle", "Dolphin", "Hedgehog", "Llama", "Frog", "Duck", "Bear", "Seal",
             "Gecko", "Puffin", "Moose", "Badger"}

P.NAME_COUNT = #adjectives * #animals

-- nameId 0..399 -> "Happy Fox"
function P.presetName(id)
  id = math.floor(tonumber(id) or 0) % P.NAME_COUNT
  return adjectives[math.floor(id / #animals) + 1] .. " " .. animals[id % #animals + 1]
end

-- ---------- checking text from the other side (never trust it) ----------
function P.split(msg)
  local out = {}
  for field in (msg .. "|"):gmatch("([^|]*)|") do out[#out + 1] = field end
  return out
end

-- a whole number in range, or nil
function P.int(s, lo, hi)
  if type(s) ~= "string" or not s:match("^%-?%d+$") or #s > 12 then return nil end
  local n = tonumber(s)
  if n < lo or n > hi then return nil end
  return n
end

-- a normal number in range, or nil (no nan / inf / weird text)
function P.num(s, lo, hi)
  if type(s) ~= "string" or #s > 16 or not s:match("^%-?%d+%.?%d*$") then return nil end
  local n = tonumber(s)
  if not n or n < lo or n > hi then return nil end
  return n
end

-- custom names: 3 to 12 letters / digits, nothing else
function P.validCustomName(s)
  return type(s) == "string" and s:match("^[A-Za-z0-9]+$") ~= nil and #s >= 3 and #s <= 12
end

-- World names are display labels only; never use them to identify or authorize a player.
function P.validWorldName(s)
  return type(s) == "string" and #s >= 1 and #s <= 24
      and s:match("%w") ~= nil and s:match("^[A-Za-z0-9 _%-]+$") ~= nil
end

function P.validRequestId(s)
  return type(s) == "string" and #s == 24 and s:match("^[A-Z0-9]+$") ~= nil
end

function P.validCode(s)
  if type(s) ~= "string" or #s ~= P.CODE_LENGTH then return false end
  for ch in s:gmatch(".") do
    if not P.CODE_LETTERS:find(ch, 1, true) then return false end
  end
  return true
end

-- "mods signature": a short fingerprint of the block list, so only players with
-- the same blocks can share a world.  format  count:hash
function P.validSig(s)
  return type(s) == "string" and #s <= 24 and s:match("^%d+:%x+$") ~= nil
end

function P.sigCount(sig) return tonumber(sig:match("^(%d+):")) or 0 end

function P.makeSig(names)
  local h = 5381
  for _, name in ipairs(names) do
    for i = 1, #name do h = (h * 33 + name:byte(i)) % 4294967296 end
    h = (h * 33 + 124) % 4294967296
  end
  return ("%d:%x"):format(#names, h)
end

return P

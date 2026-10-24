-- ============================================================
-- music.lua - background music.
--
-- Every .mp3 / .ogg / .wav file in the music/ folder is played in turn (a single song loops).
-- It is streamed from the file, so a long song does not use much memory.
-- The Music button (top right of the menus, see menu.lua) turns it on and off; the choice is
-- saved in settings.txt (settings.lua).
--
-- Nothing here can crash the game: no music folder, a broken file, or a device without sound
-- just means silence.
-- ============================================================
local M = {
  enabled = true,
  volume = 0.5,        -- 0..1
  dir = "music",
  tracks = {},         -- file names found in the folder
  index = 1,           -- which track is playing
  source = nil,        -- the LÖVE audio source of that track
  paused = false,      -- true while the game is in the background
}

local EXT = {mp3 = true, ogg = true, wav = true}

local function scan()
  local list = {}
  if love.filesystem and love.filesystem.getInfo(M.dir) then
    for _, f in ipairs(love.filesystem.getDirectoryItems(M.dir)) do
      local ext = f:lower():match("%.(%w+)$")
      if ext and EXT[ext] and f:sub(1, 1) ~= "." and f:sub(1, 1) ~= "_" then
        list[#list + 1] = M.dir .. "/" .. f
      end
    end
  end
  table.sort(list)
  return list
end

local function open(path)
  if not love.audio then return nil end
  local ok, src = pcall(love.audio.newSource, path, "stream")
  if ok then return src end
  print("[music] could not open " .. path .. ": " .. tostring(src))
end

-- start playing track number i (or the next one that opens)
local function startTrack(i)
  for k = 0, #M.tracks - 1 do
    local idx = (i - 1 + k) % #M.tracks + 1
    local src = open(M.tracks[idx])
    if src then
      M.index, M.source = idx, src
      src:setVolume(M.volume)
      src:setLooping(#M.tracks == 1)   -- one song loops; with more, update() moves to the next
      pcall(src.play, src)
      return true
    end
  end
  M.source = nil
  return false
end

-- call once at start-up. enabled = the saved setting (nil counts as on)
function M.init(enabled)
  M.enabled = enabled ~= false
  M.tracks = scan()
  M.source = nil
  if M.enabled and #M.tracks > 0 then startTrack(1) end
end

function M.setEnabled(on)
  M.enabled = on and true or false
  if M.enabled then
    if M.source then pcall(M.source.play, M.source)
    elseif #M.tracks > 0 then startTrack(M.index) end
  elseif M.source then
    pcall(M.source.pause, M.source)
  end
end

function M.setVolume(v)
  M.volume = math.max(0, math.min(1, v))
  if M.source then M.source:setVolume(M.volume) end
end

-- every frame: with several songs, start the next one when a song ends
function M.update()
  if M.enabled and not M.paused and M.source and #M.tracks > 1 and not M.source:isPlaying() then
    startTrack(M.index % #M.tracks + 1)
  end
end

-- the game went to the background / came back (phones)
function M.focus(focused)
  M.paused = not focused
  if not M.source then return end
  if not focused then pcall(M.source.pause, M.source)
  elseif M.enabled then pcall(M.source.play, M.source) end
end

return M

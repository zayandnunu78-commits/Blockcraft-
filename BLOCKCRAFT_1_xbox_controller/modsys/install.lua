-- ============================================================
-- install.lua - the "Add Mods" helper.
--
-- love.filedropped (main.lua) hands every dropped / shared file to I.dropped().
-- It is copied into  mods/  inside LÖVE's save folder, and a message is kept in
-- I.status so the Add Mods screen (menu.lua) can show it.
--
--   desktop : drag a file onto the game window
--   iPhone  : share / "Open in" the file with the game (LÖVE for iOS)
--
-- After the copy the mod is loaded right away (main.lua sets I.reload), no restart needed.
-- (Replacing a file of a mod that is already loaded still needs a restart.)
-- ============================================================
local I = {
  MOD_DIR = "mods",
  status = nil,       -- text for the Add Mods screen
  statusOk = true,
  toast = nil,        -- short message drawn on any screen for a few seconds
  toastTime = 0,
  added = 0,          -- files added since the game started
  reload = nil,       -- set by main.lua: function() -> text, ok   (loads whatever is new in mods/)
}

-- file types that make sense in mods/
local allowed = {mcpack = true, mcaddon = true, zip = true, jar = true, json = true, png = true}

local function say(ok, text)
  I.statusOk = ok
  I.status = text
  I.toast = text
  I.toastTime = 6
end

-- the folder on the real disk (for the "where is it" hint)
function I.folder()
  return love.filesystem.getSaveDirectory() .. "/" .. I.MOD_DIR
end

-- make a safe file name: letters, digits, . _ - and spaces; never starts with . or _
-- (those prefixes mean "disabled" to the mod loaders)
local function cleanName(name)
  name = name:match("[^/\\]+$") or name
  name = name:gsub("[^%w%._%- ]", "_"):gsub("^[%._]+", "")
  return name
end

-- called with the File object from love.filedropped
function I.dropped(file)
  local path = file:getFilename() or ""
  local name = cleanName(path)
  local ext = (name:match("%.([^%.]+)$") or ""):lower()
  if name == "" or not allowed[ext] then
    say(false, ("Can't add '%s'. Use .mcpack, .mcaddon, .zip, .jar, .json or .png"):format(
      path:match("[^/\\]+$") or path))
    return false
  end

  local ok, data = pcall(function()
    assert(file:open("r"))
    local s = file:read()
    file:close()
    return s
  end)
  if not ok or not data or #data == 0 then
    pcall(file.close, file)
    say(false, ("Could not read '%s'"):format(name))
    return false
  end

  love.filesystem.createDirectory(I.MOD_DIR)
  local target = I.MOD_DIR .. "/" .. name
  local existed = love.filesystem.getInfo(target) ~= nil
  local wrote, err = love.filesystem.write(target, data)
  if not wrote then
    say(false, ("Could not save '%s': %s"):format(name, tostring(err)))
    return false
  end

  I.added = I.added + 1
  print("[install] copied " .. target)

  if existed then
    say(true, ("Replaced '%s'. Restart the game to use the new version."):format(name))
  elseif ext == "png" then
    say(true, ("Added '%s'. A texture is used by a block file added AFTER it, so add the .json next."):format(name))
  elseif I.reload then
    local okR, text, okLoad = pcall(I.reload)
    if okR then
      say(okLoad ~= false, ("Added '%s'. %s"):format(name, text))
    else
      say(false, ("Added '%s' but loading failed: %s"):format(name, tostring(text)))
    end
  else
    say(true, ("Added '%s'. Close and reopen the game to load it."):format(name))
  end
  return true
end

-- load whatever is new in mods/ right now (the "Load New" button)
function I.rescan()
  if not I.reload then say(false, "Mod loading is not available"); return end
  local okR, text, okLoad = pcall(I.reload)
  if okR then say(okLoad ~= false, text) else say(false, "Loading failed: " .. tostring(text)) end
end

-- phones: open the Files app so you can pick a mod and share it to this game
-- (iOS only: LOVE has no built-in file picker)
function I.canOpenFiles()
  return love.system.getOS() == "iOS"
end

function I.openFiles()
  local ok, res = pcall(love.system.openURL, "shareddocuments://")
  if ok and res ~= false then
    say(true, "Files opened. Pick the mod, tap Share, then choose this game.")
    return true
  end
  say(false, "Could not open the Files app.")
  return false
end

-- desktop only: open the mods folder in the file manager
function I.openFolder()
  love.filesystem.createDirectory(I.MOD_DIR)
  local ok = pcall(love.system.openURL, "file://" .. I.folder())
  if not ok then say(false, "Could not open the folder. It is at: " .. I.folder()) end
  return ok
end

function I.update(dt)
  if I.toastTime > 0 then I.toastTime = I.toastTime - dt end
end

return I

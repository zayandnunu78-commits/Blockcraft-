-- FNAF Horror Night for Blockcraft 1 (LÖVE2D)
-- Controls: F starts/exits the mode, M cameras, G/H doors, R restarts after game over.
-- Touch/mouse controls are also provided through pointer_pressed events.
-- All audio is loaded through the host game's mod API; no copyrighted FNAF audio is included.

local S = {
  open = false, active = false, ended = false, won = false, jumpscare = false,
  screen = "title", selectedSlot = nil, slots = {},
  elapsed = 0, hourTick = 0, hour = 12, power = 100,
  camera = false, camIndex = 1, leftDoor = false, rightDoor = false,
  leftLight = false, rightLight = false,
  moveTick = 0, powerZeroTick = 0, flash = 0, static = 0,
  enemies = {
    {name = "RUSTY", side = "left", stage = 1, route = "WEST HALL"},
    {name = "PATCH", side = "right", stage = 1, route = "EAST HALL"},
    {name = "VEX", side = "right", stage = 1, route = "BACKSTAGE"},
    {name = "MIMIC", side = "left", stage = 1, route = "PIRATE COVE"},
  },
  cams = {"SHOW STAGE", "DINING ROOM", "WEST HALL", "EAST HALL", "BACKSTAGE", "PIRATE COVE"},
}
local gfx
local startedSong = false
local SAVE_KEY = "horror_slots_v1"
local PIZ_X, PIZ_Y = 100, 100
local returnPosition

local function loadSlots()
  S.slots = {{nights=0, best=0}, {nights=0, best=0}, {nights=0, best=0}}
  local raw = api.storage and api.storage.read(SAVE_KEY)
  if type(raw) ~= "string" then return end
  local i = 0
  for line in raw:gmatch("[^\r\n]+") do
    local slot, nights, best = line:match("^(%d),(%d+),(%d+)$")
    slot, nights, best = tonumber(slot), tonumber(nights), tonumber(best)
    if slot and slot >= 1 and slot <= 3 and nights and best then
      S.slots[slot] = {nights=math.min(nights, 999999), best=math.min(best, 6)}
      i = i + 1
    end
  end
end

local function saveSlots()
  if not (api.storage and api.storage.write) then return end
  local rows = {}
  for i = 1, 3 do
    local slot = S.slots[i] or {nights=0, best=0}
    rows[#rows + 1] = string.format("%d,%d,%d", i, slot.nights or 0, slot.best or 0)
  end
  local ok = api.storage.write(SAVE_KEY, table.concat(rows, "\n") .. "\n")
  if not ok then api.log("Could not save horror slots locally.") end
end

local function say(text, x, y)
  gfx.setColor(1, 1, 1, 1)
  gfx.print(text, x, y)
end

local function panel(x, y, w, h, r, g, b, a)
  gfx.setColor(r or 0.03, g or 0.04, b or 0.05, a or 0.92)
  gfx.rect(x, y, w, h)
end

local function playSound(path, loop, volume, stream)
  if api.audio and api.audio.exists(path) then
    api.audio.play(path, loop or false, volume or 1, stream or false)
  end
end

local function stopAudio()
  if api.audio then api.audio.stopAll() end
  startedSong = false
end

local function closeMode()
  S.open, S.active, S.ended = false, false, false
  S.screen = "title"
  stopAudio()
  if returnPosition then
    api.player.teleport(returnPosition.x, returnPosition.y, returnPosition.z)
    returnPosition = nil
  end
end

local function enemyOnCamera(enemy, cam)
  if enemy.name == "RUSTY" then
    return (enemy.stage == 1 and cam == 1) or (enemy.stage >= 2 and cam == 3)
  elseif enemy.name == "PATCH" then
    return (enemy.stage == 1 and cam == 1) or (enemy.stage >= 2 and cam == 4)
  elseif enemy.name == "VEX" then
    return (enemy.stage == 1 and cam == 5) or (enemy.stage == 2 and cam == 2) or (enemy.stage >= 3 and cam == 4)
  end
  return (enemy.stage == 1 and cam == 6) or (enemy.stage == 2 and cam == 2) or (enemy.stage >= 3 and cam == 3)
end

local function enemyAtDoor(enemy)
  return enemy.stage >= 3
    and ((enemy.side == "left" and S.leftDoor) or (enemy.side == "right" and S.rightDoor))
end

local function enemyLit(enemy)
  return enemy.stage >= 3
    and ((enemy.side == "left" and S.leftLight) or (enemy.side == "right" and S.rightLight))
end

-- Build a compact pizzeria map in the active Blockcraft world and place the player inside it.
-- Coordinates use Z as vertical, matching the host game's world API.
local pizzeriaBuilt = false
local function pizzeriaFill(x1, y1, z1, x2, y2, z2, block)
  api.world.fill(x1 + PIZ_X, y1 + PIZ_Y, z1, x2 + PIZ_X, y2 + PIZ_Y, z2, block)
end

local function pizzeriaSet(x, y, z, block)
  api.world.set(x + PIZ_X, y + PIZ_Y, z, block)
end

local function buildPizzeria()
  if pizzeriaBuilt then
    -- Always put the player back at the office when a new night starts.
    api.player.teleport(PIZ_X, PIZ_Y - 4, 1)
    return
  end
  -- Compact, recognizable pizzeria footprint: tiled floor, red-brick perimeter,
  -- dining tables, stage, kitchen counters, and a separate security office.
  pizzeriaFill(-10, -8, 0, 10, 8, 0, "Cobble")
  -- Outer walls with an entrance gap at the south and a service gap at the north.
  pizzeriaFill(-10, -8, 1, 10, -8, 5, "Brick")
  pizzeriaFill(-10, 8, 1, 10, 8, 5, "Brick")
  pizzeriaFill(-10, -7, 1, -10, 7, 5, "Brick")
  pizzeriaFill(10, -7, 1, 10, 7, 5, "Brick")
  pizzeriaFill(-2, -8, 1, 2, -8, 3, 0)
  pizzeriaFill(-2, 8, 1, 2, 8, 3, 0)
  -- Dining room / stage divider with a broad opening.
  pizzeriaFill(-7, 2, 1, -3, 2, 3, "Brick")
  pizzeriaFill(3, 2, 1, 7, 2, 3, "Brick")
  -- Security office divider and door opening.
  pizzeriaFill(-4, -5, 1, -1, -5, 3, "Brick")
  pizzeriaFill(1, -5, 1, 4, -5, 3, "Brick")
  -- Kitchen/service area at the east side.
  pizzeriaFill(6, -3, 1, 6, 1, 3, "Brick")
  pizzeriaFill(6, -1, 1, 6, 1, 2, 0)
  -- Stage at the back: raised platform and three colored-looking block figures.
  pizzeriaFill(-4, 5, 1, 4, 7, 1, "Planks")
  pizzeriaFill(-3, 6, 2, -2, 6, 3, "Wood")
  pizzeriaFill(-1, 6, 2, 0, 6, 3, "Stone")
  pizzeriaFill(1, 6, 2, 2, 6, 3, "Wood")
  -- Pirate Cove alcove for the fast runner: curtains, sign, and a dark stage.
  pizzeriaFill(7, 5, 1, 9, 7, 1, "Planks")
  pizzeriaFill(7, 5, 2, 7, 7, 4, "Brick")
  pizzeriaFill(9, 5, 2, 9, 7, 4, "Brick")
  pizzeriaFill(8, 5, 2, 8, 7, 3, "Wood")
  -- Dining tables and seats (arranged in rows so the room reads as a pizzeria).
  for _, x in ipairs({-6, -2, 2}) do
    for _, y in ipairs({-2, 0}) do
      pizzeriaFill(x, y, 1, x + 1, y, 1, "Planks")
      pizzeriaSet(x, y - 1, 1, "Wood")
      pizzeriaSet(x + 1, y - 1, 1, "Wood")
    end
  end
  -- Kitchen counter / back room props.
  pizzeriaFill(7, -3, 1, 9, -2, 1, "Stone")
  pizzeriaFill(8, 0, 1, 9, 0, 2, "Wood")
  -- Office desk, side walls, and two door alcoves.
  pizzeriaFill(-2, -7, 1, 2, -7, 2, "Wood")
  pizzeriaFill(-4, -7, 1, -4, -4, 3, "Brick")
  pizzeriaFill(4, -7, 1, 4, -4, 3, "Brick")
  -- Keep the spawn pad clear, then place the player safely inside the security office.
  pizzeriaFill(-1, -4, 1, 1, -2, 3, 0)
  api.player.teleport(PIZ_X, PIZ_Y - 4, 1)
  pizzeriaBuilt = true
  api.log("Pizzeria layout built (stage, dining tables, kitchen, office); teleported to security office.")
end

local function startNight(slot)
  if slot then S.selectedSlot = slot end
  if not returnPosition then
    local x, y, z = api.player.getPosition()
    returnPosition = {x = x, y = y, z = z}
  end
  buildPizzeria()
  S.screen = "game"
  S.active, S.ended, S.won, S.jumpscare = true, false, false, false
  S.elapsed, S.hourTick, S.hour, S.power = 0, 0, 12, 100
  S.camera, S.camIndex = false, 1
  S.leftDoor, S.rightDoor = false, false
  S.leftLight, S.rightLight = false, false
  S.moveTick, S.powerZeroTick, S.flash, S.static = 0, 0, 0, 0
  S.enemies = {
    {name = "RUSTY", side = "left", stage = 1, route = "WEST HALL"},
    {name = "PATCH", side = "right", stage = 1, route = "EAST HALL"},
    {name = "VEX", side = "right", stage = 1, route = "BACKSTAGE"},
    {name = "MIMIC", side = "left", stage = 1, route = "PIRATE COVE"},
  }
  stopAudio()
  if api.audio and api.audio.exists("theme.mp3") then
    playSound("theme.mp3", true, 0.55, true)
    startedSong = true
  end
  api.log("FNAF Horror Night started.")
end

local function endNight(win, scare)
  S.active, S.ended, S.won, S.jumpscare = false, true, win, scare or false
  S.screen = "result"
  if win and S.selectedSlot then
    local slot = S.slots[S.selectedSlot] or {nights=0, best=0}
    slot.nights = math.min(999999, (slot.nights or 0) + 1)
    slot.best = 6
    S.slots[S.selectedSlot] = slot
    saveSlots()
  end
  stopAudio()
  if scare then playSound("sounds/jumpscare.wav", false, 1, false) end
end

local function toggleCamera()
  if not S.active or S.ended or S.power <= 0 then return end
  S.camera = not S.camera
end

local function clickAt(x, y)
  local w, h = gfx.size()
  if type(x) ~= "number" or type(y) ~= "number" then return true end
  -- Touch/mouse coordinates are normally pixels; scale normalized coordinates too,
  -- which helps some mobile wrappers that forward 0..1 touch positions.
  if x >= 0 and x <= 1 and w > 1 then x = x * w end
  if y >= 0 and y <= 1 and h > 1 then y = y * h end
  -- Large, always-available touch target for phones and tablets.
  if x >= w * 0.84 and y <= h * 0.12 then
    closeMode()
    return false
  end
  if S.screen == "title" then
    if x > w * 0.30 and x < w * 0.70 and y > h * 0.48 and y < h * 0.64 then
      S.screen = "slots"
      return false
    end
    return true
  elseif S.screen == "slots" then
    local top = h * 0.28
    for i = 1, 3 do
      local by = top + (i - 1) * h * 0.16
      if x > w * 0.18 and x < w * 0.82 and y > by and y < by + h * 0.12 then
        startNight(i)
        return false
      end
    end
    if y > h * 0.80 and x > w * 0.28 and x < w * 0.72 then S.screen = "title"; return false end
    return true
  elseif S.screen == "result" then
    if x > w * 0.20 and x < w * 0.80 and y > h * 0.58 and y < h * 0.73 then
      S.screen = "slots"
      S.active, S.ended = false, false
      return false
    end
    return true
  end
  if not S.active then return true end
  if y > h * 0.78 then
    if x < w * 0.20 then S.leftDoor = not S.leftDoor
    elseif x < w * 0.36 then S.leftLight = not S.leftLight
    elseif x < w * 0.64 then toggleCamera()
    elseif x < w * 0.80 then S.rightLight = not S.rightLight
    else S.rightDoor = not S.rightDoor end
    return false
  end
  if S.camera then
    if x < w / 2 then S.camIndex = math.max(1, S.camIndex - 1)
    else S.camIndex = math.min(#S.cams, S.camIndex + 1) end
    return false
  end
  return true
end

-- A generated world is a new map, so the pizzeria must be rebuilt there even
-- if this mod instance has already hosted a night in an older world.
api.events.on("world_generate", function()
  pizzeriaBuilt = false
end)

api.events.on("key", function(key)
  if key == "f" then
    if not S.open then
      S.open, S.screen = true, "title"
    else
      closeMode()
    end
    return false
  end
  if not S.open then return true end
  if key == "escape" and (S.screen == "slots" or S.screen == "result") then
    closeMode()
    return
  end
  if S.screen == "title" and (key == "return" or key == "kpenter") then
    S.screen = "slots"
    return false
  elseif S.screen == "slots" then
    if key == "1" then startNight(1); return false
    elseif key == "2" then startNight(2); return false
    elseif key == "3" then startNight(3); return false
    elseif key == "backspace" then S.screen = "title"; return false end
  elseif S.screen == "result" and (key == "return" or key == "kpenter") then
    S.screen, S.active, S.ended = "slots", false, false
    return false
  elseif key == "r" and S.ended then
    startNight(S.selectedSlot)
    return false
  elseif S.active then
    if key == "c" or key == "m" then toggleCamera(); return false
    elseif key == "a" or key == "g" then S.leftDoor = not S.leftDoor; return false
    elseif key == "z" then S.leftLight = not S.leftLight; return false
    elseif key == "d" or key == "h" then S.rightDoor = not S.rightDoor; return false
    elseif key == "x" then S.rightLight = not S.rightLight; return false
    elseif key == "left" or key == "q" then S.camIndex = math.max(1, S.camIndex - 1); return false
    elseif key == "right" or key == "e" then S.camIndex = math.min(#S.cams, S.camIndex + 1); return false
    end
  end
end)

api.events.on("pointer_pressed", function(x, y, button)
  -- Only a primary click/tap should activate the overlay controls. This keeps
  -- secondary-click block interactions from toggling a door or camera.
  if button ~= nil and button ~= 1 then return true end
  if not S.open then
    local w, h = gfx.size()
    if x >= 0 and x <= 1 then x = x * w end
    if y >= 0 and y <= 1 then y = y * h end
    if x >= 12 and x <= 132 and y >= 14 and y <= 62 then
      S.open, S.screen = true, "title"
      return false
    end
    return true
  end
  local consumed = clickAt(x, y)
  if consumed == false then return false end
  if S.screen ~= "game" then return false end
end)

api.events.on("update", function(dt)
  if not S.active then return end
  dt = math.min(dt or 0, 0.1)
  S.elapsed = S.elapsed + dt
  S.hourTick = S.hourTick + dt
  S.moveTick = S.moveTick + dt
  S.flash = math.max(0, S.flash - dt * 2)

  -- Six in-game hours; each hour lasts 30 seconds (a 3-minute night).
  if S.hourTick >= 30 then
    S.hourTick = S.hourTick - 30
    if S.hour == 12 then S.hour = 1 else S.hour = S.hour + 1 end
    if S.hour == 6 then
      endNight(true, false)
      return
    end
  end

  local drain = 0.08
  if S.camera then drain = drain + 0.30 end
  if S.leftDoor then drain = drain + 0.55 end
  if S.rightDoor then drain = drain + 0.55 end
  if S.leftLight then drain = drain + 0.20 end
  if S.rightLight then drain = drain + 0.20 end
  S.power = math.max(0, S.power - drain * dt)
  S.static = math.max(0, S.static - dt * 2)
  if S.power <= 0 then
    S.camera, S.leftDoor, S.rightDoor = false, false, false
    S.leftLight, S.rightLight = false, false
    S.powerZeroTick = S.powerZeroTick + dt
  else
    S.powerZeroTick = 0
  end

  if S.moveTick >= 6.5 then
    S.moveTick = 0
    for _, enemy in ipairs(S.enemies) do
      local watched = S.camera and enemyOnCamera(enemy, S.camIndex)
      local aggression = math.min(0.92, 0.48 + S.elapsed / 420)
      -- MIMIC is the fast runner; camera discipline is the counterplay.
      if enemy.name == "MIMIC" then aggression = math.min(0.96, aggression + 0.18) end
      if not watched and math.random() < aggression then
        if enemy.stage < 3 then
          enemy.stage = enemy.stage + 1
          S.static = 0.35
        elseif enemyAtDoor(enemy) then
          enemy.stage = 2
          S.flash = 0.45
        elseif enemyLit(enemy) then
          -- A lit hall catches an animatronic before it enters the office.
          enemy.stage = 2
          S.flash = 0.65
        else
          S.flash = 1
          endNight(false, true)
          return
        end
      end
    end
  end
  if S.powerZeroTick > 2.2 then
    for _, enemy in ipairs(S.enemies) do
      if enemy.stage >= 2 then
        S.flash = 1
        endNight(false, true)
        return
      end
    end
  end
end)

api.events.on("draw_hud", function(g)
  gfx = g
  local w, h = gfx.size()
  if not S.open then
    -- This button is the mobile replacement for the keyboard F shortcut.
    panel(12, 14, 120, 48, 0.28, 0.03, 0.03, 0.94)
    say("FNAF", 42, 28)
    say("TAP TO PLAY", 24, 46)
    return
  end
  -- Keep the exit target large enough for a phone thumb on every FNAF screen.
  panel(w * 0.84, 8, w * 0.14, 42, 0.20, 0.04, 0.04, 0.96)
  say("EXIT", w * 0.885, 22)
  if S.screen == "title" then
    panel(w * 0.18, h * 0.10, w * 0.64, h * 0.26, 0.02, 0.02, 0.03, 0.96)
    say("FNAF HORROR NIGHT", w * 0.28, h * 0.15)
    say("BLOCKCRAFT 1", w * 0.40, h * 0.23)
    panel(w * 0.30, h * 0.48, w * 0.40, h * 0.16, 0.32, 0.03, 0.03, 0.97)
    say("PLAY", w * 0.46, h * 0.53)
    say("Tap PLAY or press ENTER", w * 0.35, h * 0.68)
    say("Press F again to return to your normal Blockcraft world", w * 0.24, h * 0.73)
    say("3 save slots | Choose a slot to start a night", w * 0.22, h * 0.78)
    say("Save slots are stored on this device; cloud sync needs a configured server.", w * 0.10, h * 0.88)
    return
  elseif S.screen == "slots" then
    panel(w * 0.14, h * 0.08, w * 0.72, h * 0.16, 0.02, 0.02, 0.03, 0.96)
    say("SELECT SAVE SLOT", w * 0.32, h * 0.12)
    say("Choose a slot to play. Press 1, 2, or 3 on keyboard.", w * 0.19, h * 0.19)
    for i = 1, 3 do
      local slot = S.slots[i] or {nights=0, best=0}
      local by = h * 0.28 + (i - 1) * h * 0.16
      panel(w * 0.18, by, w * 0.64, h * 0.12, 0.08, 0.09, 0.12, 0.98)
      say("SLOT " .. i, w * 0.23, by + h * 0.025)
      say("Nights survived: " .. tostring(slot.nights or 0), w * 0.43, by + h * 0.025)
      say("Best: " .. tostring(slot.best or 0) .. " AM", w * 0.43, by + h * 0.065)
    end
    panel(w * 0.32, h * 0.80, w * 0.36, h * 0.10, 0.20, 0.04, 0.04, 0.96)
    say("BACK", w * 0.46, h * 0.825)
    say("Local saves are active. Cloud saves are not connected yet.", w * 0.15, h * 0.93)
    return
  end

  if S.ended or S.screen == "result" then
    panel(0, 0, w, h, S.won and 0.02 or 0.22, 0.02, 0.03, 0.94)
    if S.won then
      say("6 AM - YOU SURVIVED!", w * 0.28, h * 0.34)
      say("The pizzeria is quiet... for now.", w * 0.28, h * 0.42)
    else
      panel(0, 0, w, h, 0.45, 0.01, 0.02, 0.85)
      say("JUMPSCARE!", w * 0.37, h * 0.27)
      say("YOU DIDN'T SURVIVE THE NIGHT", w * 0.22, h * 0.40)
    end
    panel(w * 0.30, h * 0.58, w * 0.40, h * 0.17, 0.10, 0.10, 0.12, 0.98)
    say("BACK TO SLOTS", w * 0.36, h * 0.62)
    say("Press ENTER or tap to continue", w * 0.30, h * 0.68)
    return
  end

  panel(8, 8, w - 16, 42, 0.02, 0.02, 0.025, 0.92)
  say("FNAF HORROR NIGHT - SLOT " .. tostring(S.selectedSlot or "?"), 18, 14)
  say(string.format("%d AM", S.hour), w - 116, 14)
  say(string.format("POWER %d%%", math.floor(S.power)), w - 116, 29)

  if S.camera then
    panel(w * 0.13, h * 0.12, w * 0.74, h * 0.48, 0.01, 0.02, 0.025, 0.97)
    say("SECURITY CAMERAS  [SIGNAL STABLE]", w * 0.18, h * 0.15)
    say("CAM " .. tostring(S.camIndex) .. " - " .. S.cams[S.camIndex], w * 0.18, h * 0.20)
    say("CAM MAP: 1 STAGE  2 DINING  3 WEST  4 EAST  5 BACK  6 COVE", w * 0.18, h * 0.25)
    say("<< Q / LEFT", w * 0.18, h * 0.53)
    say("RIGHT / E >>", w * 0.65, h * 0.53)
    local found = {}
    for _, enemy in ipairs(S.enemies) do
      if enemyOnCamera(enemy, S.camIndex) then found[#found + 1] = enemy.name .. " DETECTED" end
    end
    if #found > 0 then
      panel(w * 0.28, h * 0.32, w * 0.44, h * 0.10, 0.22, 0.02, 0.02, 0.98)
      say(table.concat(found, " / "), w * 0.33, h * 0.35)
    else
      say("NO MOVEMENT DETECTED", w * 0.32, h * 0.34)
    end
    if S.static > 0 then
      panel(w * 0.29, h * 0.43, w * 0.42, h * 0.07, 0.22, 0.22, 0.22, 0.55)
      say("VIDEO NOISE", w * 0.43, h * 0.45)
    end
  else
    panel(w * 0.18, h * 0.16, w * 0.64, h * 0.30, 0.015, 0.015, 0.02, 0.94)
    say("SECURITY OFFICE // NIGHT WATCH", w * 0.29, h * 0.20)
    say("Listen for movement. Flash lights before opening doors.", w * 0.20, h * 0.27)
    say("CAMERAS COST POWER. SURVIVE UNTIL 6 AM.", w * 0.25, h * 0.33)
    say("WEST LIGHT: " .. (S.leftLight and "ON" or "OFF"), w * 0.08, h * 0.46)
    say("EAST LIGHT: " .. (S.rightLight and "ON" or "OFF"), w * 0.70, h * 0.46)
    if S.leftDoor then say("WEST DOOR: CLOSED", w * 0.08, h * 0.47)
    else say("WEST DOOR: OPEN", w * 0.08, h * 0.47) end
    if S.rightDoor then say("EAST DOOR: CLOSED", w * 0.66, h * 0.47)
    else say("EAST DOOR: OPEN", w * 0.66, h * 0.47) end
    for i, enemy in ipairs(S.enemies) do
      if enemy.stage >= 2 and not (enemyLit(enemy) and enemy.stage == 3) then
        say(enemy.name .. " MOVEMENT - " .. enemy.route, w * 0.24, h * (0.51 + (i - 1) * 0.045))
      end
    end
  end

  local by = h * 0.80
  local bw, gap = w * 0.18, w * 0.012
  local bx = {gap, w * 0.20, w * 0.40, w * 0.60, w * 0.80}
  panel(bx[1], by, bw, h * 0.14, S.leftDoor and 0.42 or 0.10, 0.03, 0.03, 0.95)
  panel(bx[2], by, bw, h * 0.14, S.leftLight and 0.36 or 0.10, 0.22, 0.03, 0.95)
  panel(bx[3], by, bw, h * 0.14, S.camera and 0.03 or 0.10, 0.10, S.camera and 0.34 or 0.12, 0.95)
  panel(bx[4], by, bw, h * 0.14, S.rightLight and 0.36 or 0.10, 0.22, 0.03, 0.95)
  panel(bx[5], by, bw, h * 0.14, S.rightDoor and 0.42 or 0.10, 0.03, 0.03, 0.95)
  say("G DOOR", bx[1] + 12, by + 12)
  say("Z LIGHT", bx[2] + 10, by + 12)
  say("M CAM", bx[3] + 16, by + 12)
  say("X LIGHT", bx[4] + 10, by + 12)
  say("H DOOR", bx[5] + 12, by + 12)
  say("F exits | Q/E cameras", w * 0.37, h - 22)
  if S.power < 20 then
    panel(w * 0.36, h * 0.64, w * 0.28, h * 0.08, 0.35, 0.02, 0.02, 0.96)
    say("LOW POWER!", w * 0.43, h * 0.66)
  end
  if S.flash > 0 and not S.ended then
    panel(0, 0, w, h, 1, 1, 1, math.min(0.45, S.flash * 0.45))
  end
end)

api.events.on("load", function()
  loadSlots()
  api.log("FNAF Horror Night loaded. Open the mod overlay and choose PLAY, then a save slot.")
  if not (api.audio and api.audio.exists("theme.mp3")) then
    api.log("Optional: add your horror theme song as mods/fnaf_horror/theme.mp3.")
  end
end)

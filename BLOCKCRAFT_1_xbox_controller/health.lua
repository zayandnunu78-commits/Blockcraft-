-- ============================================================
-- health.lua - the player's hearts.
--
-- 20 health points = 10 hearts (a half heart is 1 point).
--   * hurt by a fall of more than 3 blocks: 1 point for every extra block (see player.lua)
--   * heals by itself: after 5 seconds without being hurt, +1 point every 4 seconds
--     (so the first point is back 9 seconds after the hurt)
--   * at 0 you "fall too far" and wake up at the spawn point with full hearts (main.lua)
--
-- Mods: the "player_hurt" event (e = {amount, source}) can lower, raise or cancel (return false)
-- any damage. api.player.getHealth / setHealth / damage / heal (modsys/api.lua).
-- ============================================================
local events = require "modsys.events"

local H = {max = 20, hp = 20, sinceHurt = 99, regenTimer = 0, flash = 0, onDeath = nil}
H.REGEN_DELAY = 5     -- seconds after a hurt before healing starts
H.REGEN_EVERY = 4     -- seconds per healed point
H.FLASH = 0.35        -- seconds the screen flashes red

local floor = math.floor

function H.reset()
  H.hp, H.sinceHurt, H.regenTimer, H.flash = H.max, 99, 0, 0
end

-- set the health directly (loading a saved world); no events, no flash, never dead
function H.set(n)
  n = tonumber(n) or H.max
  H.hp = math.max(1, math.min(H.max, floor(n)))
end

-- returns the damage that was really taken (0 if a mod cancelled it)
function H.damage(amount, source)
  amount = floor(tonumber(amount) or 0)
  if amount <= 0 or H.hp <= 0 then return 0 end
  local e = {amount = amount, source = source or "unknown"}
  if not events.fire("player_hurt", e) then return 0 end
  amount = floor(tonumber(e.amount) or 0)
  if amount <= 0 then return 0 end
  amount = math.min(amount, H.hp)
  H.hp = H.hp - amount
  H.sinceHurt, H.regenTimer, H.flash = 0, 0, H.FLASH
  if H.hp <= 0 and H.onDeath then H.onDeath(e.source) end
  return amount
end

function H.heal(amount)
  amount = floor(tonumber(amount) or 0)
  if amount <= 0 or H.hp <= 0 then return end
  H.hp = math.min(H.max, H.hp + amount)
end

-- every frame while playing
function H.update(dt)
  if H.flash > 0 then H.flash = math.max(0, H.flash - dt) end
  H.sinceHurt = H.sinceHurt + dt
  if H.hp < H.max and H.sinceHurt >= H.REGEN_DELAY then
    H.regenTimer = H.regenTimer + dt
    while H.regenTimer >= H.REGEN_EVERY and H.hp < H.max do
      H.regenTimer = H.regenTimer - H.REGEN_EVERY
      H.hp = H.hp + 1
    end
  else
    H.regenTimer = 0
  end
end

return H

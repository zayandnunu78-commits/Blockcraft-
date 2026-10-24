# Hearts (health)

You have **10 hearts = 20 health points** (a half heart is 1 point). They show above the hotbar.

* **Falling:** a fall of more than 3 blocks hurts, 1 point for every extra block
  (4 blocks = half a heart, 13 blocks = 5 hearts). Jumping and small ledges never hurt.
* **Healing:** after 5 seconds without being hurt you heal 1 point every 4 seconds.
* **At 0 hearts** you "fall too far": you wake up at the spawn point with full hearts, and the game says so.
* The screen flashes red for a moment when you are hurt.
* Hearts are saved with the world (SAVING.md). Online games start with full hearts; health is not
  shared between players (nobody can hurt anybody else yet).

## Files
| File | Job |
|---|---|
| `health.lua` | the numbers: damage, healing over time, death, the `player_hurt` event |
| `hearts.lua` | draws the hearts (pictures made in code, no image files) and the red flash |
| `player.lua` | measures falls (`P.SAFE_FALL = 3`) and calls `player.onFall(distance)` |
| `main.lua` | connects them: `player.onFall` -> `health.damage`, `health.onDeath` -> respawn |

## For mods
```lua
api.player.getHealth()  api.player.getMaxHealth()   -- 0..20
api.player.setHealth(n) api.player.heal(n) api.player.damage(n)
api.events.on("player_hurt", function(e)   -- e = {amount = 6, source = "fall"}
  e.amount = math.floor(e.amount / 2)       -- change the damage ...
  -- return false                          -- ... or cancel it
end)
```
`damage(n)` from a mod has the source `"mod:<modid>"`. `setHealth` never kills (minimum 1).
A teleport (`api.player.teleport`) forgets the fall in progress; falling after it counts from the new height.

## Changing the numbers
`health.lua`: `max`, `REGEN_DELAY`, `REGEN_EVERY`, `FLASH`. `player.lua`: `P.SAFE_FALL`.
The terrain can be up to 37 blocks high, so with the defaults a fall of 23 blocks or more is deadly.

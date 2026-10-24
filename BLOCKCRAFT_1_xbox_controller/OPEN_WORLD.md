# Open world (chunk streaming)

The world is now endless sideways (x, y up to ±1,000,000 blocks) and 64 blocks tall (4 chunk layers).
The middle of the world / spawn point is x = 0, y = 0.

## How it works
| File | Job |
|---|---|
| `terrain.lua` | The land as **pure functions of (seed, x, y)**: heights, sand/grass/stone, trees. Uses only `+ - * /` and floor, no `sin`/`pow`/random, so every device and the server build *identical* land. |
| `world.lua` | Sparse storage: only loaded 16x16x16 chunks exist. A chunk that is all one block (air / stone) is stored as a single number. `world.edits` remembers every changed block even after its chunk is unloaded. |
| `chunks.lua` | Chunk manager. Each frame: when you enter a new chunk column it plans the missing chunks (nearest first) and unloads far ones, then generates for at most `genBudget` seconds. |
| `mesher.lua` | One mesh per chunk. Hidden faces are skipped (also across chunk borders), a chunk is meshed once its 6 neighbours exist, nearest first within `meshBudget`, vertex tables are recycled, meshes use chunk-local coordinates (no jitter far from the middle), and chunks outside the camera's view cone are not drawn. |
| `worldgen.lua` | Starts a world: sets the seed, builds the 5x5 chunk columns around spawn at once, fires the `world_generate` mod event. |

## Multiplayer
Terrain is **never sent**: the server sends the seed, and each game builds the land itself.
The server only streams *changed blocks*:
1. the game sends `VIEW|cx|cy` whenever you enter a new chunk column,
2. the server stores changes per chunk and sends the chunks within 10 columns of you, nearest first, 6 chunks per server tick (`EDITS|...`),
3. a change made near you arrives as `S|...`; you can only change blocks within 10 columns of where you said you are.
Protocol version is now **3**: the server and every player must update together. Each room is a
persistent cloud world keyed by a unique 12-character invite code; up to 200,000 changed blocks
are stored on the server and survive a process restart when its save directory/volume is kept.

## Settings you can change
* `chunks.viewDistance` (set in `main.lua`: 6 on computers, 4 on phones; `chunks.setViewDistance(n)` allows 2-12)
* `chunks.genBudget`, `chunks.meshBudget` (seconds per frame, default 4 ms each)
* terrain shape: the numbers at the top of `terrain.lua` (`SAND_MAX`, `ROCK_MIN`) and `T.height`.
  If you change `T.height`, also check `T.MAX_HEIGHT` and `T.TREE_MAX_Z`: the shortcuts rely on them.
  Changing terrain breaks compatibility with existing servers' worlds (same seed gives different land).

## Mods
* `api.world.set` / `get` / `top` / `fill` work anywhere; a chunk that is not loaded reads as air.
* New event `chunk_generate(c)`, `c = {cx, cy, cz, x0, y0, z0}`: decorate a fresh chunk. Inside it `api.world.set` only changes *that* chunk (others do not exist yet).
* `world_generate` runs once after the spawn area exists; its changes are never sent over the network (every player runs the same mods).
* `api.world.size()` now returns the horizontal limit (2,000,000) and the height (64).

## Known limits
* This online-only build cannot create or load single-player worlds. Legacy local saves remain on disk but are inaccessible (see SAVING.md). Multiplayer world data is stored by the server, not on each player's device.
* No water, caves or lighting; no fog, so the edge of the view distance pops in.
* Beyond roughly ±100,000 blocks from the middle, graphics precision gets coarse (float32).
* Draw calls = visible chunk meshes (roughly 100-300). Merging them further needs a shader for tiled textures.
* Cloud persistence unit/integration tests run against a simulated filesystem and server peers; real LÖVE/ENet, live VPS and phone networking still require deployment testing (see SERVER_SETUP.md).

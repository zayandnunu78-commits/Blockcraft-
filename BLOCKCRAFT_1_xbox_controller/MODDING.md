# Modding guide (Mod API v1)

Put mods in the `mods/` folder (next to `main.lua`, or in LÖVE's save folder).
Folders or files starting with `.` or `_` are ignored (rename a mod to `_mymod` to disable it).
The console prints `[modloader] ...` lines saying what loaded, what failed, and why.
The title screen shows "N mod(s) loaded".

## What a mod can be

| Format | Recognised by | What is used |
|---|---|---|
| Lua mod (folder / .zip) | `mod.json` | `main.lua` runs in a sandbox with the `api` table. Optionally its `assets/` too. |
| Minecraft Fabric `.jar` | `fabric.mod.json` | metadata, blockstates, models, lang, textures |
| Minecraft Forge/NeoForge `.jar` | `META-INF/mods.toml` (or old `mcmod.info`) | same |
| Resource pack / textures only | an `assets/` folder | every `textures/block/*.png` becomes a cube block |

**Important limit:** Java code inside a real Minecraft `.jar` can't run here (this game is Lua).
Its *data* is imported: full-cube blocks, their per-face textures and display names.
Stairs, slabs, fences, entities, items, recipes etc. are skipped (listed in the console).
Textures of any size are shrunk to 16x16; animated textures use their first frame;
blocks that reuse vanilla `minecraft:` textures are skipped (vanilla assets aren't bundled).

## mod.json
```json
{ "id": "my_mod", "name": "My Mod", "version": "1.0.0",
  "description": "...", "main": "main.lua",
  "depends": ["other_mod"], "import_assets": true }
```
`id`: lowercase letters/digits/`_`, starts with a letter. `main` and `depends` are optional.

## API (see the top of `modsys/api.lua` for the full list)
```lua
api.block.register{ id="ruby_block", name="Ruby Block", texture="textures/ruby.png" }
api.block.register{ id="lamp", textures={top="a.png", side="b.png", bottom="a.png"} }
api.world.get/set/top/fill/size      api.player.getPosition/teleport
api.hotbar.set(slot, "my_mod:ruby_block")
api.events.on("block_break", function(e) ... return false end)   -- false = cancel
api.log("hello")
```
Events: `load`, `ready`, `world_generate`, `update(dt)`, `key(k)`,
`block_break(e)`, `block_place(e)` (set `e.block` to swap the block), `draw_hud(gfx)`.

In game: `[` and `]` cycle the selected hotbar slot through every registered block.

## Sandbox
Mod scripts have no `io`, `os.execute`, `love`, `load`, `debug` or real `require`.
`require("lib/util")` loads `lib/util.lua` from inside the same mod only.
Known gap: a mod with an endless loop will freeze the game (no time limit yet).

## Samples in `mods/`
* `ruby_mod/` - Lua mod: 2 blocks, world-gen tower, cancelled break, block swap, HUD text, hotkey
* `crystal_blocks-1.2.0.jar` - Fabric-format jar: blockstates, models with parent chains, lang, animated texture
* `mossy_bricks-3.0.zip` - Forge-format zip in a wrapper folder, textures only


## Adding mods from the game (no restart needed)
Settings -> **Add Mods**.
* **iPhone / iPad:** the button opens the Files app. Pick the mod, tap Share, choose this game.
  (LOVE has no built-in file picker, so the game gets the file through the share sheet.)
* **Desktop:** drag the file onto the game window, or use *Open Folder* and then *Load New*.
Allowed: `.mcpack`, `.mcaddon`, `.zip`, `.jar`, `.json`, `.png`. The file is copied into `mods/` in LOVE's
save folder and loaded right away (`modsys/install.lua`, `loadAll()` in `modsys/loader.lua`).
New blocks go in the selected hotbar slot; tap the selected slot again to switch blocks.

A mod that needs another mod or API that is not installed (for example `fabric-api`) still loads;
the console prints a note. Java code is never run, only blocks, textures and names are imported.
Replacing a file of a mod that is already loaded needs a restart. Add a `.png` before the `.json` that uses it
(or add them together in a `.mcpack`).

## Bedrock / Minecraft Education blocks
Put any of these in `mods/` (names starting with `.` or `_` are ignored). Console lines start with `[bedrock]`.

| What you drop in `mods/` | Notes |
|---|---|
| `my_pack.mcpack` or `my_addon.mcaddon` | No unzipping needed. An `.mcaddon` can hold folders or `.mcpack` files. |
| an unzipped pack folder (has `manifest.json`) | A folder that holds several pack folders also works. |
| `ruby_block.json` + `ruby_block.png` | Loose files, side by side. |

Behavior packs (blocks) and resource packs (textures) are searched together, so a
`.mcaddon` with both works. What is read inside a pack:

* `blocks/**/*.json` - block definitions (`minecraft:block`). `//` and `/* */` comments are fine.
* `textures/terrain_texture.json` - maps a short texture name to a file path.
* `blocks.json` - older style: block id -> textures (`"textures": "name"` or `{up, down, side}`).
* `texts/en_US.lang` - display names (`tile.ns:name.name=Name`).

```json
{ "format_version": "1.20.60",
  "minecraft:block": {
    "description": { "identifier": "ruby:ruby_block" },
    "components": {
      "minecraft:destroy_time": 3.0,
      "minecraft:material_instances": { "*": { "texture": "ruby_block" } } } } }
```
Read from a block: `identifier` (required, `namespace:name`), mining time from `minecraft:destroy_time`
(or `minecraft:destructible_by_mining.seconds_to_destroy`), textures from `material_instances`
(`*`, `up`, `down`, `side`) or from `blocks.json`. Everything else is ignored.

A texture name is found in this order: `terrain_texture.json`, then `<name>.png`,
`textures/<name>.png`, `textures/blocks/<name>.png` in each pack (and in `mods/`).
If nothing is found you get a magenta/black checkerboard and the block still loads.
Not supported: custom geometry, items, entities, scripts, and `.zip` files holding Bedrock packs
(rename them to `.mcpack`).

Code can use `require "registeredblocks"`: `[identifier]`, `.byId[numericId]`, `.list`.
Blocks with destroy time > 0 are mined by holding the left mouse button (desktop); phone taps break instantly.
The loader is `modsys/bedrock.lua` (the diagram is at the top of that file).

## The open world (see OPEN_WORLD.md)
The world is endless sideways and 64 blocks tall; spawn is x = 0, y = 0. A chunk that is not loaded
reads as air, so `api.world.get` far from the player returns 0.
* `world_generate` : once, after the spawn area exists
* `chunk_generate(c)` : every new 16x16x16 chunk, `c = {cx, cy, cz, x0, y0, z0}`.
  Inside it `api.world.set` only changes that chunk.

## Saving and mods (see SAVING.md)
Saves store blocks by name, so adding/removing mods does not break old worlds. If a block's mod is
removed, those blocks simply disappear from the saved world (the game tells the player how many).

## Hearts (see HEARTS.md)
`api.player.getHealth/getMaxHealth/setHealth/damage/heal` and the cancellable `player_hurt` event.

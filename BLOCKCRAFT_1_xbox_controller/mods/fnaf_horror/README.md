# Blockcraft 1 — FNAF Horror Mod

## Play flow and save slots
- From the Blockcraft title menu, use **Normal Worlds** for the regular survival/building game. The FNAF mode is optional and does not replace normal worlds.
- While playing a normal world, press **F** to open the FNAF overlay; press **F** again to close it and return to ordinary Blockcraft gameplay.
- On mobile, tap the red **FNAF — TAP TO PLAY** button in the upper-left corner. Use the large bottom buttons for doors, hallway lights, and cameras; tap **EXIT** in the upper-right corner to return to the normal world.
- Press **F** while in Blockcraft 1 gameplay to open the mod.
- Choose **PLAY**, then choose **Slot 1**, **Slot 2**, or **Slot 3** (or press keyboard `1`, `2`, or `3`).
- Each slot records the number of nights survived and best result.
- Slot metadata persists locally in LÖVE's private save directory through the host's per-mod storage API.
- **Cloud synchronization is not configured in this build.** The existing Blockcraft cloud-world server stores world edits, but it does not currently provide a user/account-backed generic storage endpoint for this mod's save-slot records. To make slots sync between devices, a server endpoint and player identity/authentication must be configured; this ZIP does not pretend local saves are cloud saves.

## Night controls
- `M` / `C`: cameras
- `G` / `A`: left door
- `Z`: west hallway light
- `H` / `D`: right door
- `X`: east hallway light
- `Q` / left arrow and `E` / right arrow: change cameras
- `R`: retry after game over
- `Escape`: return from menus

Touch controls use large hit areas and also accept normalized touch coordinates from mobile wrappers.

The night lasts about three minutes. It now includes four original fictional animatronics with different routes, six camera feeds, camera static, office hallway lights, doors, escalating AI, a power meter, a 6 AM win state, and an original synthesized jumpscare effect. Watch the cameras, flash the hallway lights, and close the correct door only when necessary: every system drains power. It is a Blockcraft-native FNAF-inspired survival mode, not a full 3D recreation. No official FNAF assets or sounds are included.

## Add your theme song
Copy your licensed theme song into `mods/fnaf_horror/` as `theme.mp3`. It loops during a night if present.


## Pizzeria map
Starting a night builds a small brick pizzeria in a separate area of the current world and teleports the player into its security office. Closing the mode returns the player to their previous position, so the normal world and its builds are not overwritten. The map uses built-in Blockcraft blocks and is generated locally.

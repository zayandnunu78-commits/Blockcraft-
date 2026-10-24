# Blockcraft 1 — FNAF Horror Mod

## Play flow and save slots
- Press **F** while in Blockcraft 1 gameplay to open the mod.
- Choose **PLAY**, then choose **Slot 1**, **Slot 2**, or **Slot 3** (or press keyboard `1`, `2`, or `3`).
- Each slot records the number of nights survived and best result.
- Slot metadata persists locally in LÖVE's private save directory through the host's per-mod storage API.
- **Cloud synchronization is not configured in this build.** The existing Blockcraft cloud-world server stores world edits, but it does not currently provide a user/account-backed generic storage endpoint for this mod's save-slot records. To make slots sync between devices, a server endpoint and player identity/authentication must be configured; this ZIP does not pretend local saves are cloud saves.

## Night controls
- `M` / `C`: cameras
- `G` / `A`: left door
- `H` / `D`: right door
- `Q` / left arrow and `E` / right arrow: change cameras
- `R`: retry after game over
- `Escape`: return from menus

The night lasts about three minutes. It includes two original fictional animatronics, a power meter, camera views, doors, a 6 AM win state, and an original synthesized jumpscare effect. It is a prototype mini-mode overlay, not a full 3D FNAF recreation. No official FNAF assets or sounds are included.

## Add your theme song
Copy your licensed theme song into `mods/fnaf_horror/` as `theme.mp3`. It loops during a night if present.

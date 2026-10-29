# Backrooms Level 0

Blockcraft 1 now includes an optional procedural Backrooms Level 0 for offline play.

## Play

On a mobile device, start an offline world and tap the circular logo button above the jump control. The supplied Backrooms logo is used byte-for-byte as the button image. The game switches to a deterministic maze of small rooms and connecting corridors with yellow wallpaper, dark yellow carpet, ceiling fluorescent panels, and a quiet procedural fluorescent hum.

The teleport is deliberately disabled during an online session so the existing multiplayer world, seed, position streaming, and block-change protocol cannot be desynchronized. Existing saves are saved before the offline level switch and are not overwritten by Backrooms generation.

## Implementation

- `backrooms.lua` provides the deterministic chunk generator, materials, logo button, and ambient hum.
- `chunks.lua` selects the Backrooms generator only after the explicit teleport.
- `main.lua` performs the safe offline transition and reloads nearby chunks.
- `input.lua` adds the mobile hit target without changing the joystick/look/mining controls.
- `hud.lua` draws the circular logo button.
- `player.lua` adds a position setter used only for teleporting.
- `assets/backrooms_logo.png` is the user-provided image copied without modification.

## Verification

Lua syntax checks passed for the changed scripts. The supplied logo and the packaged copy have identical SHA-256 hashes. A physical iPhone/mobile runtime test was not possible in this sandbox, so the ZIP should be tested in the target LÖVE mobile runtime before release.

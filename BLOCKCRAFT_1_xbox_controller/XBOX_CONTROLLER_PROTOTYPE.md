# Blockcraft 1 Xbox controller prototype

This isolated copy adds an Xbox-style controller abstraction without changing the original project at `/home/ubuntu/work/blockcraft/BLOCKCRAFT_1_render_fix`.

## Exact bindings

| Controller input | Action in this prototype |
|---|---|
| A | Place or break using the current Blockcraft interaction mode |
| B | Jump |
| X | Emits the `inventory` action hook; inventory UI is not present in the current game |
| Y | Toggles the camera-view index and emits the `camera_view` action hook; only one camera view currently exists |
| Left stick | Movement with a configurable dead zone |
| Right stick | Camera look with a configurable dead zone |
| LB | Emits the `attack` action hook; combat is not present in the current game |
| RB | Emits the `feed` action hook; feeding is not present in the current game |
| LT | Two distinct presses enable flight; three additional distinct presses disable it |
| RT | Emits the `chat` action hook; text chat is not present in the current multiplayer protocol |
| View/back | Opens the existing paused World Menu |
| Menu/start | Saves and opens the existing Main Menu |
| D-pad | Selects/cycles hotbar items through controller menu-style input |

Unsupported actions are explicit hooks rather than fake features. A future inventory, combat, feeding, flight movement, camera system, or chat implementation can subscribe to `xbox_action` without changing the requested bindings.

## Flight press behavior

LT counts button edges, not held frames. The default counting window is 0.45 seconds. An incomplete sequence expires when the window ends. Trigger axes are thresholded at 0.55 and also produce one press edge, so holding a trigger does not repeatedly toggle flight.

The isolated prototype includes `tests/xbox_controller_test.lua`, which validates the binding table, held-button suppression, flight enable/disable counts, timeout behavior, and analog dead zones.

## Runtime status

This is a desktop/LÖVE controller prototype, not an Xbox build. The sandbox has no LÖVE graphics runtime or Xbox GDK, so hardware testing and graphics runtime testing remain blocked. The original game source and published server were not modified.

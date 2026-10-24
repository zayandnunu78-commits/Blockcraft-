# Music

The song in `music/childhood.mp3` ("Childhood" by Daniel, 2:09) plays in the menus and while you play, and loops.

* **Music: On / Off** button in the top right corner of the title, pause, settings, and Add Mods screens.
  The choice is saved in `settings.txt`.
* The music pauses when the game goes to the background (phones) and comes back with it.
* **Add more songs:** copy `.mp3`, `.ogg` or `.wav` files into the `music/` folder. They play one after
  the other (by file name). With only one song it loops. Names starting with `.` or `_` are ignored,
  so rename a song to `_name.mp3` to switch it off.
* A missing or broken file, or a device without sound, just means silence (never a crash).
* The song is streamed from the file, so it does not use much memory. The file is 3.7 MB; a 128 kbps
  copy would be about 2 MB if you want a smaller download.

## Files
| File | Job |
|---|---|
| `music.lua` | finds the songs, plays them, on/off, volume (`music.setVolume`, default 0.5), pause on focus loss |
| `menu.lua` | the Music button |
| `settings.lua` | saves `music=1/0` |

## Rights
Only keep music in the game that you made, or that you have permission or a licence to use.
If you share or publish the game, say who made each song (in `music/README.txt` and in the game's
description).

# Multiplayer server setup (for a grown-up)

The game's online play needs one small program running on a computer that is always
on and reachable from the internet. Phones cannot do this job. Players create saved
cloud worlds and share each world's 12-character invite code with friends.

## What you need
* A small Linux cloud computer (a "VPS"). Some providers have free plans; check the price before you sign up.
* UDP port **22122** open to the internet (in the provider's firewall AND on the machine, e.g. `sudo ufw allow 22122/udp`).

## Option A: Docker (easiest)
```
docker build -t blockcraft-server .
docker run -d --restart unless-stopped -p 22122:22122/udp \
  -v blockcraft1-worlds:/data blockcraft-server
```

The named Docker volume is required: it keeps server saves when the container is replaced.
Do not remove the volume when upgrading the image.

## Option B: LÖVE directly
```
sudo apt install love
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy love /path/to/this/folder --server
```
The server is fixed to UDP port **22122**. It prints a line when worlds load, save, and
players join. Stop it with Ctrl+C; changed worlds are flushed on a clean shutdown.

## Connecting
In the game: **Multiplayer**, enter the server address (for example `myserver.example.com`
or `203.0.113.5`; UDP port 22122 is added for you), then open **Worlds** to create a cloud
world, select a saved one, or join by invite code. Everyone in a world needs the **same game
version and the same mods** (the server refuses players whose blocks differ).
To pre-fill the address, edit `net/config.lua`.

## Cloud world storage and access

- The server stores a world's terrain seed and every changed block in `worlds/<code>.a`
  and `worlds/<code>.b`. Terrain is regenerated from the seed, then stored edits are streamed
  when a player enters nearby chunks.
- The game autosaves changed worlds about every 5 seconds, saves on player disconnect and
  clean server shutdown, and offers **Save to Cloud** in the pause menu. Saves alternate
  between two complete generations and are read back and checksum-validated before they
  count as successful. If one generation is incomplete or corrupt, the last valid one remains.
- The device keeps a small index of worlds it has created or joined (name + invite code);
  the world contents themselves are on the server. Losing the device's index does not delete
  server data, but the invite code must be recovered from whoever shared it.
- This build deliberately has **no player accounts or private owner role**. A world is shared:
  anyone with its invite code can join and edit it. Player names are display-only, never identity.
  The current ENet protocol is unencrypted, so invite codes are not safe from a network observer.
  Use only a trusted server/network; private owner-only worlds would require authenticated,
  encrypted transport plus a real identity/recovery system.
- Abrupt power loss can lose edits made since the last successful 5-second autosave. The two
  generations prevent a partial save from replacing the previous complete one; they cannot
  preserve data that had not yet reached disk.
- To bound storage use on a shared invite-code server, the game allows at most 100 saved worlds,
  200,000 edits per world, and 500,000 edits across the server.

## Safe mode (starts ON)
* There is **no chat** anywhere in the game or server.
* **Emotes** are 5 fixed pictures (heart, star, smile, thumbs up, diamond). A player can only send the number 1-5, so they can never carry words. The server allows one every 1.5 seconds per player. Keys Z X C V B on desktop, or the smiley button on a phone.
* Safe mode: players get a preset name like "Happy Fox" and never see anyone's typed name.
* Players under 9 need someone 9 or older to create the parent code (the first person to turn safe mode off creates it).
* Safe mode OFF (needs the 4-number parent code) allows a typed name of
  3-12 letters/numbers. Players with safe mode ON still only ever see preset names.
* Worlds can only be entered with their random 12-character invite code. Share it only with
  people you trust; anyone with the code can edit the shared world.
* The server never sends a player's address to other players. It stores world files, but no
  account identity or player name is used to select or authorize a world.
* Safe mode and the parent code are settings on each device. They protect against accidents,
  but they cannot stop someone who deliberately edits their own copy of the game.

## Verification performed on this source copy

- `lua tests/cloud_save_test.lua` passed: save format and corruption checks, persistent world
  creation, retry-safe create requests, timed save, explicit save, disconnect save, two-world
  isolation, loading into a fresh server-core instance (restart simulation), reconnect and restored
  chunk streaming, plus recovery after a simulated short write and corrupt newest generation,
  device catalog recovery, and client protocol/save acknowledgments.
- A separate real-disk smoke test passed: it wrote a world to local files, created a fresh server
  core over the same files, rejoined by invite code, and verified the restored edit stream.
- `luac -p` passed for every Lua source file in the archive.
- The automated suite uses a fake filesystem; the additional disk smoke test uses real local
  files. Both use simulated peers. They do **not** test the actual LÖVE filesystem adapter, ENet
  sockets, a real UDP connection, the target VPS, Docker-volume mounting, or an actual process
  restart. No live server was changed or restarted. Do a smoke test on the intended BLOCKCRAFT 1
  host before deployment.

## Updating to persistent cloud worlds (protocol version 3)
The server and ALL players must update together: an old game that tries to join gets
"update the game: versions do not match". This ZIP is a staging copy, not a live deployment.
Before copying files or restarting anything, verify the exact BLOCKCRAFT 1 directory and service
name, take a fresh backup on that host, and confirm its UDP port is 22122. Preserve the Docker
volume or LÖVE save directory containing `worlds/`. Do not guess a service name or restart the
BLOCKCRAFT 2 process on UDP 22123.

# BLOCKCRAFT 1 — persistent cloud worlds

This archive contains **BLOCKCRAFT 1 only**. The update keeps its dedicated server on UDP
port **22122**; it does not include or modify BLOCKCRAFT 2.

## What changed

- Multiplayer now creates persistent worlds instead of volatile rooms. Each world has a unique
  12-character invite code and independent server files.
- Players can create a named cloud world, list worlds known on their device, join by a saved
  entry or invite code, and request **Save to Cloud** from the pause menu.
- World management now lives in its own **Worlds** section, separate from the Multiplayer
  server-address and player settings screen.
- The existing seed + sparse block-edit model is reused. The server restores the seed and edits
  after a restart, and streams edits to clients as they enter nearby chunks.
- Server saves happen every 5 seconds while dirty, on disconnect, on explicit save, and on clean
  shutdown. Alternating generations, read-back validation, bounded parsing, and checksums protect
  the last complete save from a truncated write.
- World files are keyed by generated invite codes, not usernames. There is no account or private
  owner role: anyone with the code can edit the shared world. ENet is unencrypted, so the code is
  not private from a network observer.
- Existing offline access remains disabled. Legacy local world slots are untouched and not
  migrated. Settings remain local as before.

## Operation and limits

Run the Docker server with a persistent `/data` volume and publish only UDP 22122:

```
docker run -d --restart unless-stopped -p 22122:22122/udp \
  -v blockcraft1-worlds:/data blockcraft-server
```

Without a persistent volume, replacing the container loses the server's world files. An abrupt
power failure can lose edits since the most recent successful autosave (normally at most about
5 seconds). The protocol and save format are version 3; update the BLOCKCRAFT 1 server and all
clients together. Do not change or restart the separate BLOCKCRAFT 2 service on UDP 22123.

## Verification

See `SERVER_SETUP.md` for test results from this workspace. A local simulated restart test does
not prove the live VPS, Docker volume, actual LÖVE/ENet runtime, or public UDP path is deployed
correctly; those require a test on the target server.

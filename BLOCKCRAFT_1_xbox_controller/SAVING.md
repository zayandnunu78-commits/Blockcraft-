# BLOCKCRAFT 1 world persistence

BLOCKCRAFT 1 now supports server-saved multiplayer worlds. Offline play remains disabled in this
build; the three legacy local single-player slots are retained and are not modified by cloud saves.

## Cloud world format

The multiplayer protocol already sends the host's terrain seed and streams changed blocks by chunk.
The server now persists that same representation: **seed + mod/block signature + changed block
coordinates and IDs**. Clients regenerate the terrain and apply the server's edits. Player names,
positions, and inventory are not used as world identity or ownership.

Each world has a unique 12-character invite code and separate pair of files:
`worlds/<CODE>.a` and `worlds/<CODE>.b` in the server's LÖVE save directory. Files include a
generation number, strict bounds checks, a record count, and an Adler-32 corruption checksum.
Autosaves alternate between the two files; the candidate is read back and fully decoded before
being accepted. Startup chooses the newest valid generation and keeps the older one as recovery.

The server writes approximately every 5 seconds while edits are arriving, immediately on a
player's disconnect, on explicit **Save to Cloud**, and on clean server shutdown. A sudden power
loss may lose edits since the last completed write. Existing worlds remain in memory when empty;
they are not deleted when the last player leaves.
To bound resource use, a server permits at most 100 worlds, 200,000 edits in one world, and
500,000 edits total across all worlds.

The client stores only a device-local list of world names and invite codes. The world data is
server-side. World codes are shared write-access invitations, not account credentials: there are
no private owners or username-based authorization. The current ENet protocol is unencrypted, so
do not use invite codes over untrusted networks or treat this as private storage.

## Compatibility

The cloud format retains the current multiplayer model: terrain is regenerated from a seed and
block IDs are valid only for the matching block/mod signature. All clients and servers must use
protocol version 3. Local legacy save files are not migrated or read by this feature.

# Map library

Each subfolder here is one selectable map: a Minecraft save read straight
out of its Anvil region files. **There are none checked in.** With this
directory empty the game runs procedurally generated worlds only, and the
map picker does not appear at all — add a folder and it comes back.

The importer is in `game/src/mca.gd`. It parses Anvil directly (NBT, 1.16+
packed palettes, 1.18+ section layout, zlib/gzip) and maps ~200 block types
onto the game's own palette. Nothing is ever written back: Godot-side edits
are an overlay and the save is read-only.

## Adding one

Make a subfolder and drop the region files in it — either directly or in a
`region/` subdirectory — plus an optional `map.cfg`:

    maps/skyblock/r.0.0.mca
    maps/skyblock/map.cfg

```ini
[map]
name="Sky Block"
center_x=256          ; the Minecraft x,z that becomes our origin
center_z=256
y0=40                 ; the Minecraft y that becomes world floor + 1
```

Every folder shows up by itself as a button in the game's WORLD section —
the server rescans on each connect. `WORLD_MCA_DIR` points at any save
outside this directory without committing it.

## Before you commit one

A map here is redistributed to everyone who clones this repository, so it
has to be yours or licensed to allow that. Record which in `map.cfg`'s
name, and add a row to `NOTICE`.

Worth knowing: a map built for survival usually plays badly here. What
works is open ground with cover on it and a few ways up — a dense city or
a cave network reads as a maze at this camera distance.

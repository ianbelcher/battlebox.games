# Kits

Buildings the picker can stamp into the world. Two kinds live here:

- **Hand-written kits** — code, in `game/src/structures.gd` (house,
  watchtower, bridge, and so on).
- **Imported kits** — real Minecraft builds, which is what this
  directory is for.

## Adding a build — just drop the file in

Most of these sites want a login (minecraft-schematics.com is also behind
a CDN), so downloading by hand is the NORMAL way to do this, not a
fallback:

1. Download the `.schem` / `.schematic` / `.nbt`.
2. Drop it **anywhere under `kits/`** — subfolder or not, doesn't matter.
3. Run `./tools/import_kits.sh`, then commit.

That's it. If you also paste the build's link into `sources.txt` and the
file keeps the site's id as its name (`30747.schem`), the importer matches
the two up and uses the name and builder you wrote there — otherwise it
falls back to something readable.

Anything skipped is reported with the reason (usually "bigger than the
limit"), so a build never disappears silently.

## Adding a build by link

1. Put its link in `sources.txt`, one per line, with the name and builder.
2. Run the fetcher, then the importer:

   ```sh
   cd deployments/world
   python3 tools/fetch_kits.py          # downloads into kits/downloads/
   ./tools/import_kits.sh               # turns them into game kits
   ```

3. Commit. The build now appears on the picker's **Kits** tab, and its
   builder appears in the game's **Credits** tab automatically.

If a site refuses the download (minecraft-schematics.com asks for a free
login), just download the file by hand and drop it into
`kits/downloads/` — the importer does not care how it got there.

## What lands where

| Path | What |
| --- | --- |
| `kits/sources.txt` | the links you paste — **this is the file you edit** |
| `kits/downloads/` | the builds themselves — **committed**, because they're the source everything is generated from |
| `kits/manifest.json` | what was imported, and who built it |
| `game/src/structures_imported.gd` | **generated** — the kits the game ships |

Re-running the importer regenerates every kit from `kits/downloads/`, so
that folder is the single source of truth. Deleting a file from it and
re-running removes that kit from the game.

## Formats

All three are read automatically, so whatever a site gives you should work:

- `.schem` — Sponge v1/v2/v3. What most sites serve today.
- `.schematic` — MCEdit/WorldEdit legacy, flat 1.12 numeric block ids.
- `.nbt` — Minecraft structure blocks, from datapacks.

Block states survive all of them, so stairs keep their facing rather than
importing flat.

## Size limits

A kit has to be something a child can stamp down and walk around, so
anything wider than 26 blocks, taller than 30, or over 9000 blocks is
skipped. The importer says which ones it skipped and why.

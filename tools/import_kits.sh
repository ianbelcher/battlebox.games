#!/usr/bin/env bash
# Turn everything in kits/downloads/ into kits the game can stamp.
#
#   ./tools/import_kits.sh
#
# Fetches anything listed in kits/sources.txt first, then imports every
# build sitting in kits/downloads/ (however it got there — a hand
# download works exactly the same) and regenerates
# game/src/structures_imported.gd.
set -euo pipefail
cd "$(dirname "$0")/.."
WORLD="$PWD"

echo "==> fetching anything new from kits/sources.txt"
python3 tools/fetch_kits.py || true

# Anywhere under kits/ counts. Insisting on kits/downloads/ meant a file
# dropped one folder up was silently ignored, which is a rotten way to
# treat someone who just did what you asked.
count=$(find kits -type f \( -name '*.schem' -o -name '*.schematic' \
  -o -name '*.nbt' \) 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" = "0" ]; then
  echo
  echo "No builds under kits/ yet — drop a .schem, .schematic or .nbt"
  echo "anywhere in that folder and run this again."
  exit 0
fi

echo "==> importing $count build(s)"
# WORLD_NBT_ALL=1: take everything in the folder rather than the curated
# WANTED list, which only applies to the big datapack import.
WORLD_NBT_ALL=1 \
WORLD_NBT_DIR="$WORLD/kits" \
WORLD_NBT_OUT="$WORLD/game/src/structures_imported.gd" \
WORLD_NBT_MANIFEST="$WORLD/kits/manifest.json" \
WORLD_NBT_BY="unknown" \
WORLD_NBT_LICENSE="see kits/manifest.json" \
WORLD_NBT_SOURCE="kits/sources.txt" \
godot --headless --path "$WORLD/game" --script res://tests/import_structures.gd

echo "==> registering the generated class"
godot --headless --path "$WORLD/game" --import >/dev/null 2>&1 || true
echo
echo "Done. The new kits are on the picker's Kits tab, and their builders"
echo "are in the game's Credits tab. Commit game/src/structures_imported.gd."

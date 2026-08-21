extends SceneTree
## Offline importer: real Minecraft structure blocks (.nbt) -> a generated
## src/structures_imported.gd that the Kits picker stamps into the world.
##
## We use .nbt (and, later, Sponge .schem) rather than MagicaVoxel .vox
## because they carry real Minecraft BLOCK TYPES — oak planks, cobble,
## stairs, glass — which map onto our palette through McaWorld.map_entry()
## and stay diggable. A .vox would import as anonymous coloured cubes.
##
##   WORLD_NBT_DIR=<dir of .nbt>  WORLD_NBT_BY="Author"
##   WORLD_NBT_LICENSE=MIT        WORLD_NBT_SOURCE=<url>
##   WORLD_NBT_OUT=<abs path to structures_imported.gd>
##   godot --headless --path <game> --script res://tests/import_structures.gd
##
## Anything taller or wider than the caps below is skipped: a kit has to be
## something a child can stamp down and walk around, not a whole village.

## A kit has to be something a child can stamp down and walk around, not
## a whole village — but the first limits were far too mean: the Verdant
## Treehouse missed by ONE block of height. Tall builds are exactly what
## you want from a treehouse.
const MAX_W := 34
const MAX_H := 52
const MAX_CELLS := 20000
## Picker thumbnail resolution. Every kit gets a front-on elevation of
## ITSELF rather than a generic house glyph, so a child can tell the
## library from the stable at a glance.
const THUMB := 16

## Hand-picked from the pack: a spread of ideas a child would want to
## stamp down — houses, a stable, a library, wells, ponds, shrines and
## temples — each small enough to place and walk into.
const WANTED := [
	"temple/shrine",
	"temple/temple_cherry",
	"temple/temple_plains",
	"temple/temple_snow",
	"temple/temple_snowyplains",
	"village/ganlan/buildings/ganlan_house_1",
	"village/ganlan/buildings/ganlan_house_2",
	"village/ganlan/buildings/ganlan_house_6",
	"village/ganlan/buildings/ganlan_shrine",
	"village/ganlan/decor/ganlan_pond",
	"village/grotto/buildings/yaodong_1",
	"village/grotto/buildings/yaodong_2",
	"village/grotto/center/grotto_well",
	"village/hui/hui_pond_1",
	"village/hui/plains_blacksmith_1",
	"village/hui/plains_butcher_1",
	"village/hui/plains_fisher_cottage_1",
	"village/hui/plains_hotel_1",
	"village/hui/plains_library_1",
	"village/hui/plains_mid_house_1",
	"village/hui/plains_small_house_1",
	"village/hui/plains_stable_1",
	"village/hui/plains_temple_1",
	"village/hui/plains_town_center_1",
	"village/hui/plains_well_1",
	"village/yurt/buildings/yurt_03",
	"village/yurt/buildings/yurt_05",
	"village/yurt/buildings/yurt_stable_01",
]

## Friendlier names than the datapack's filenames.
const RENAME := {
	"shrine": "Stone Shrine",
	"temple cherry": "Cherry Temple",
	"temple plains": "Meadow Temple",
	"temple snow": "Snow Temple",
	"temple snowyplains": "Little Snow Shrine",
	"ganlan house 1": "Stilt House",
	"ganlan house 2": "Big Stilt House",
	"ganlan house 6": "Stilt Hut",
	"ganlan shrine": "Wooden Shrine",
	"ganlan pond": "Lily Pond",
	"yaodong 1": "Cave House",
	"yaodong 2": "Cave Dwelling",
	"grotto well": "Deep Well",
	"hui pond 1": "Koi Pond",
	"plains blacksmith 1": "Blacksmith",
	"plains butcher 1": "Butcher",
	"plains fisher cottage 1": "Fisher Cottage",
	"plains hotel 1": "Inn",
	"plains library 1": "Library",
	"plains mid house 1": "Town House",
	"plains small house 1": "Little Cottage",
	"plains stable 1": "Stable",
	"plains temple 1": "Village Temple",
	"plains town center 1": "Town Square",
	"plains well 1": "Village Well",
	"yurt 03": "Yurt",
	"yurt 05": "Small Yurt",
	"yurt stable 01": "Yurt Stable",
}

var _nbt := McaWorld.new("")

func _initialize() -> void:
	var dir := OS.get_environment("WORLD_NBT_DIR")
	var out := OS.get_environment("WORLD_NBT_OUT")
	var by := OS.get_environment("WORLD_NBT_BY")
	var license := OS.get_environment("WORLD_NBT_LICENSE")
	var source := OS.get_environment("WORLD_NBT_SOURCE")
	if dir.is_empty() or out.is_empty():
		push_error("WORLD_NBT_DIR and WORLD_NBT_OUT are required")
		quit(1)
		return
	# kits/manifest.json: per-build name and builder, written by
	# tools/fetch_kits.py from the links in kits/sources.txt. These sites
	# rarely state a licence, so naming the builder is the least we can do
	# — and Credits reads it straight off the generated file.
	var manifest: Dictionary = {}
	var manifest_path := OS.get_environment("WORLD_NBT_MANIFEST")
	if not manifest_path.is_empty() and FileAccess.file_exists(manifest_path):
		var text := FileAccess.get_file_as_string(manifest_path)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			manifest = parsed
	var files := _find_nbt(dir)
	print("found %d schematics under %s" % [files.size(), dir])
	var entries: Array = []
	var skipped: Array = []
	for path: String in files:
		var rel := path.trim_prefix(dir).trim_prefix("/")
		for ext in [".schematic", ".schem", ".nbt"]:
			rel = rel.trim_suffix(ext)
		if OS.get_environment("WORLD_NBT_ALL") != "1" \
				and not WANTED.is_empty() and not WANTED.has(rel):
			continue
		var built := _import_one(path, rel)
		if built.is_empty():
			skipped.append("%s (%s)" % [rel, _skip_reason])
			print("  SKIPPED %-32s %s" % [rel, _skip_reason])
			continue
		# A manifest entry overrides the run-wide defaults, so a folder of
		# builds from different people credits each of them properly.
		var entry: Dictionary = manifest.get(path.get_file(), {})
		if not str(entry.get("name", "")).is_empty():
			built["name"] = str(entry["name"])
		built["by"] = str(entry.get("by", "")) if not str(entry.get("by", "")).is_empty() else by
		built["license"] = license
		built["source"] = str(entry.get("url", "")) if not str(entry.get("url", "")).is_empty() else source
		entries.append(built)
		print("  %-40s %s  %d cells" % [rel, built.size_v, built.count])
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id))
	_write(out, entries, by, license, source)
	print("wrote %s: %d kits, %d skipped" % [out, entries.size(), skipped.size()])
	quit()

func _find_nbt(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		var path := dir.path_join(name)
		if da.current_is_dir():
			out.append_array(_find_nbt(path))
		elif name.ends_with(".nbt") or name.ends_with(".schem") \
				or name.ends_with(".schematic"):
			out.append(path)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

## Reads whichever of the three formats this file actually is and returns
## a flat list of [x, y, z, block] rows, plus the structure's size:
##
##   .nbt      Minecraft structure block. A list of {state, pos} against a
##             palette of block states — nothing packed.
##   .schem    Sponge (v1/v2/v3). Same idea, but the blocks are a VARINT
##             stream in YZX order against a name->index palette.
##   .schematic  MCEdit/WorldEdit legacy. Flat 1.12 NUMERIC block ids, so
##             it needs an id->name table (LEGACY_IDS) to reach our blocks.
##
## Sponge and MCEdit are what minecraft-schematics.com and friends hand
## out; .nbt only comes from datapacks.
func _read_any(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_buffer(file.get_length())
	# Nearly all of these are gzipped; a few .schem are stored plain.
	var plain := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if plain.is_empty():
		plain = raw
	var stream := StreamPeerBuffer.new()
	stream.data_array = plain
	stream.big_endian = true
	if stream.get_u8() != McaWorld.TAG_COMPOUND:
		return {}
	var _root_name := _read_string(stream)
	var root: Dictionary = _nbt._read_compound(stream)
	# Sponge wraps everything in a named "Schematic" compound.
	if root.has("Schematic") and root["Schematic"] is Dictionary:
		root = root["Schematic"]
	if root.has("size") and root.has("palette") and root.has("blocks"):
		return _read_structure_nbt(root)
	# Sponge has a Palette (v1/v2) or a Blocks compound (v3). MCEdit's
	# older .schematic has a flat Blocks BYTE ARRAY and no palette at all.
	if root.has("Palette") or root.has("BlockData") \
			or (root.has("Blocks") and root["Blocks"] is Dictionary):
		return _read_sponge(root)
	if root.has("Blocks"):
		return _read_mcedit(root)
	return {}

## 1.12 numeric block id -> modern name. MCEdit/WorldEdit .schematic files
## predate the flattening, so they store ids like 5 rather than
## "oak_planks". Only the ids worth building with are listed; anything
## else falls through to stone, which is what an unknown solid already
## becomes everywhere else in the importer.
const LEGACY_IDS := {
	1: "stone", 2: "grass_block", 3: "dirt", 4: "cobblestone", 5: "oak_planks",
	7: "bedrock", 12: "sand", 13: "gravel", 17: "oak_log", 18: "oak_leaves",
	20: "glass", 22: "lapis_block", 24: "sandstone", 35: "white_wool",
	41: "gold_block", 42: "iron_block", 43: "smooth_stone", 44: "stone_slab",
	45: "bricks", 47: "bookshelf", 48: "mossy_cobblestone", 49: "obsidian",
	50: "torch", 53: "oak_stairs", 54: "chest", 57: "diamond_block",
	58: "crafting_table", 61: "furnace", 64: "oak_door", 65: "ladder",
	67: "cobblestone_stairs", 79: "ice", 80: "snow_block", 82: "clay",
	85: "oak_fence", 87: "netherrack", 89: "glowstone", 98: "stone_bricks",
	102: "glass_pane", 103: "melon", 108: "brick_stairs",
	109: "stone_brick_stairs", 112: "nether_bricks", 121: "end_stone",
	126: "oak_slab", 128: "sandstone_stairs", 133: "emerald_block",
	134: "spruce_stairs", 135: "birch_stairs", 139: "cobblestone_wall",
	155: "quartz_block", 156: "quartz_stairs", 159: "white_terracotta",
	162: "acacia_log", 163: "acacia_stairs", 164: "dark_oak_stairs",
	179: "red_sandstone", 180: "red_sandstone_stairs", 251: "white_concrete",
}
## Stair facing is packed into the low two bits of the metadata nibble,
## in MCEdit's own order.
const LEGACY_STAIR_FACING := ["east", "west", "south", "north"]

## MCEdit / classic WorldEdit .schematic: flat numeric ids plus a nibble
## of metadata each, indexed YZX like Sponge.
func _read_mcedit(root: Dictionary) -> Dictionary:
	var w := int(root.get("Width", 0))
	var h := int(root.get("Height", 0))
	var l := int(root.get("Length", 0))
	var ids: PackedByteArray = root.get("Blocks", PackedByteArray())
	var meta: PackedByteArray = root.get("Data", PackedByteArray())
	if w <= 0 or h <= 0 or l <= 0 or ids.is_empty():
		return {}
	var cache: Dictionary = {}
	var rows: Array = []
	for n in mini(ids.size(), w * h * l):
		var id := ids[n]
		if id == 0:
			continue
		var nibble: int = meta[n] if n < meta.size() else 0
		var key := id * 16 + nibble
		if not cache.has(key):
			var name: String = LEGACY_IDS.get(id, "stone")
			var props: Dictionary = {}
			if name.ends_with("_stairs"):
				props["facing"] = LEGACY_STAIR_FACING[nibble & 3]
				props["half"] = "top" if (nibble & 4) != 0 else "bottom"
			elif name.ends_with("_slab"):
				props["type"] = "top" if (nibble & 8) != 0 else "bottom"
			cache[key] = McaWorld.map_entry({"Name": name, "Properties": props})
		var block: int = cache[key]
		if block == Blocks.AIR:
			continue
		rows.append([n % w, n / (w * l), (n / w) % l, block])
	return {"w": w, "h": h, "l": l, "rows": rows}

## Minecraft structure block: {state, pos} against a state palette.
func _read_structure_nbt(root: Dictionary) -> Dictionary:
	var size: Array = root.get("size", [])
	var palette: Array = root.get("palette", [])
	var blocks: Array = root.get("blocks", [])
	if size.size() != 3 or palette.is_empty() or blocks.is_empty():
		return {}
	var mapped: Array = []
	for entry in palette:
		mapped.append(McaWorld.map_entry(entry as Dictionary))
	var rows: Array = []
	for b in blocks:
		var pos: Array = (b as Dictionary).get("pos", [])
		if pos.size() != 3:
			continue
		var block: int = mapped[int((b as Dictionary).get("state", 0))]
		if block == Blocks.AIR:
			continue
		rows.append([int(pos[0]), int(pos[1]), int(pos[2]), block])
	return {"w": int(size[0]), "h": int(size[1]), "l": int(size[2]), "rows": rows}

## Sponge .schem, all three versions. v3 moved the palette and data into a
## "Blocks" compound; v1/v2 keep them at the top level. Either way the
## block array is VARINT-encoded and indexed YZX.
func _read_sponge(root: Dictionary) -> Dictionary:
	var w := int(root.get("Width", 0))
	var h := int(root.get("Height", 0))
	var l := int(root.get("Length", 0))
	var palette_src: Dictionary = root.get("Palette", {})
	var data = root.get("BlockData", null)
	var container = root.get("Blocks", null)
	if container is Dictionary:
		palette_src = (container as Dictionary).get("Palette", palette_src)
		data = (container as Dictionary).get("Data", data)
	if w <= 0 or h <= 0 or l <= 0 or palette_src.is_empty() or data == null:
		return {}
	# Palette is name -> index; invert it, then map each name once.
	var by_index: Dictionary = {}
	for name: String in palette_src.keys():
		by_index[int(palette_src[name])] = _map_state_string(str(name))
	var bytes: PackedByteArray = data
	var rows: Array = []
	var i := 0
	var n := 0
	var total := w * h * l
	while i < bytes.size() and n < total:
		# LEB128: seven bits a byte, top bit means "another byte follows".
		var value := 0
		var shift := 0
		while i < bytes.size():
			var byte := bytes[i]
			i += 1
			value |= (byte & 0x7F) << shift
			if byte & 0x80 == 0:
				break
			shift += 7
		var block: int = by_index.get(value, Blocks.AIR)
		if block != Blocks.AIR:
			# YZX: index = (y * Length + z) * Width + x
			var x := n % w
			var z := (n / w) % l
			var y := n / (w * l)
			rows.append([x, y, z, block])
		n += 1
	return {"w": w, "h": h, "l": l, "rows": rows}

## "minecraft:oak_stairs[facing=north,half=bottom]" -> our block id. The
## properties matter: without them every stair imports flat.
func _map_state_string(name: String) -> int:
	var props: Dictionary = {}
	var bracket := name.find("[")
	if bracket >= 0:
		var inner := name.substr(bracket + 1).trim_suffix("]")
		for pair in inner.split(","):
			var kv := pair.split("=")
			if kv.size() == 2:
				props[kv[0].strip_edges()] = kv[1].strip_edges()
		name = name.substr(0, bracket)
	return McaWorld.map_entry({"Name": name, "Properties": props})

var _skip_reason := ""

func _import_one(path: String, rel: String) -> Dictionary:
	_skip_reason = "couldn't read it as a .schem/.schematic/.nbt"
	var parsed := _read_any(path)
	if parsed.is_empty():
		return {}
	_skip_reason = ""
	var sx := int(parsed.w)
	var sy := int(parsed.h)
	var sz := int(parsed.l)
	if sx > MAX_W or sz > MAX_W or sy > MAX_H or sx < 2 or sz < 2:
		_skip_reason = "%dx%dx%d — over the %dx%d limit" % [sx, sy, sz, MAX_W, MAX_H]
		return {}
	var raw_cells: Array = []
	var min_y := 1 << 30
	for r: Array in parsed.rows:
		# Centre on x/z so a kit stamps around the player's target.
		raw_cells.append([int(r[0]) - sx / 2, int(r[1]),
			int(r[2]) - sz / 2, int(r[3])])
		min_y = mini(min_y, int(r[1]))
		if raw_cells.size() > MAX_CELLS:
			_skip_reason = "over %d blocks — too big to stamp" % MAX_CELLS
			return {}
	if raw_cells.size() < 30:
		_skip_reason = "only %d blocks — too small to be a build" % raw_cells.size()
		return {}
	# Sit the kit ON the ground. Some builds (the cave dwellings, the deep
	# well) have their lowest block well above the structure block's own
	# origin, and stamped as-is they hovered in mid-air.
	# The block the build is mostly made of, so the picker tile can wear
	# the build's own colour instead of 28 identical tan squares.
	var max_y := 0
	for c: Array in raw_cells:
		max_y = maxi(max_y, int(c[1]))
	var tally := {}
	var roof_tally := {}
	for c: Array in raw_cells:
		var b := int(c[3])
		if b == Blocks.GRASS or b == Blocks.DIRT or Blocks.is_liquid(b):
			continue
		tally[b] = int(tally.get(b, 0)) + 1
		if int(c[1]) >= max_y - maxi(1, (max_y - min_y) / 5):
			roof_tally[b] = int(roof_tally.get(b, 0)) + 1
	var top := _most_common(tally, Blocks.PLANKS)
	# Roofs on these builds are usually a different material from the
	# walls, which is what makes one picker tile tell from another.
	var roof := _most_common(roof_tally, top)
	var cells := PackedByteArray()
	for c: Array in raw_cells:
		cells.append(int(c[0]) + 128)
		cells.append(int(c[1]) - min_y)
		cells.append(int(c[2]) + 128)
		cells.append(int(c[3]))
	var count := raw_cells.size()
	return {
		"id": "mc_" + rel.replace("/", "_"),
		"name": _pretty(rel),
		"size_v": Vector3i(sx, sy, sz),
		"count": count,
		"top": top,
		"roof": roof,
		"thumb": Marshalls.raw_to_base64(_thumbnail(raw_cells, min_y, max_y)),
		"data": Marshalls.raw_to_base64(cells),
	}

## Front elevation: look down +z and keep the NEAREST block in each
## column, exactly like standing in front of the build. Returns THUMB*THUMB
## block ids, row 0 at the top; 0 (air) means transparent.
static func _thumbnail(cells: Array, min_y: int, max_y: int) -> PackedByteArray:
	var lo_x := 1 << 30
	var hi_x := -(1 << 30)
	for c: Array in cells:
		lo_x = mini(lo_x, int(c[0]))
		hi_x = maxi(hi_x, int(c[0]))
	var w := maxi(hi_x - lo_x + 1, 1)
	var h := maxi(max_y - min_y + 1, 1)
	# One scale for both axes so nothing is stretched, and NEVER below 1:
	# upscaling with a forward nearest-neighbour mapping skips whole
	# output rows and columns, which drew blank lines through every small
	# build. Anything smaller than THUMB just renders 1:1 and is centred.
	var scale := maxf(maxf(float(w) / float(THUMB), float(h) / float(THUMB)), 1.0)
	var pad_x := int((THUMB - float(w) / scale) * 0.5)
	var pad_y := int((THUMB - float(h) / scale) * 0.5)
	var best_z := {}
	var out := PackedByteArray()
	out.resize(THUMB * THUMB)
	out.fill(0)
	for c: Array in cells:
		var tx := int(float(int(c[0]) - lo_x) / scale) + pad_x
		# Rows run top-down, so the roof lands at row 0.
		var ty := THUMB - 1 - (int(float(int(c[1]) - min_y) / scale) + pad_y)
		if tx < 0 or tx >= THUMB or ty < 0 or ty >= THUMB:
			continue
		var key := ty * THUMB + tx
		var z := int(c[2])
		if best_z.has(key) and int(best_z[key]) <= z:
			continue
		best_z[key] = z
		out[key] = int(c[3])
	return out

static func _most_common(tally: Dictionary, fallback: int) -> int:
	var best := 0
	var winner := fallback
	for b: int in tally:
		if int(tally[b]) > best:
			best = int(tally[b])
			winner = b
	return winner

func _read_string(stream: StreamPeerBuffer) -> String:
	var length := stream.get_u16()
	return "" if length == 0 else stream.get_utf8_string(length)

func _pretty(rel: String) -> String:
	var leaf := rel.get_file().replace("_", " ")
	if RENAME.has(leaf):
		return str(RENAME[leaf])
	# Downloads from the schematic sites are named after their id ("30747"),
	# which tells a child nothing. Give it something readable; the real
	# name comes from kits/sources.txt via the manifest when it's known.
	if leaf.strip_edges().is_valid_int():
		return "Build #%s" % leaf.strip_edges()
	var words := leaf.split(" ")
	var out: Array = []
	for w: String in words:
		out.append(w.capitalize() if w.length() > 1 else w.to_upper())
	return " ".join(out)

func _write(out: String, entries: Array, by: String, license: String,
		source: String) -> void:
	var text := """class_name StructuresImported
## GENERATED by tests/import_structures.gd — do not edit by hand.
##
## Real Minecraft builds (structure-block .nbt) mapped onto our palette,
## so they arrive as oak planks, cobble, stairs and glass rather than
## anonymous coloured cubes — and stay diggable like anything else.
##
## Source: %s
## Author: %s   License: %s
##
## Each kit's cells are packed 4 bytes per block: x+128, y, z+128, block.

const KITS := [
""" % [source, by, license]
	for entry: Dictionary in entries:
		text += '\t{"id": "%s", "name": "%s", "by": "%s", "license": "%s",\n' % [
			entry.id, entry.name, entry.get("by", by), license]
		text += '\t\t"size": Vector3i%s, "cells": %d, "top": %d, "roof": %d,\n' % [
			str(entry.size_v), entry.count, entry.top, entry.roof]
		text += '\t\t"thumb": "%s",\n' % entry.thumb
		text += '\t\t"data": "%s"},\n' % entry.data
	text += "]\n"
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(text)
	file.close()

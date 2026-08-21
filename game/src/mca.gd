class_name McaWorld
extends RefCounted
## Read-only Minecraft world importer: parses Anvil region files (r.X.Z.mca)
## and converts modern paletted chunk sections (1.16+ packing, 1.18+ layout,
## with the pre-1.18 "Level" wrapper also handled) into our block palette.
## The Minecraft save is NEVER written to — Godot-side edits live in the
## ChunkStore overlay files.
##
## Env knobs:
##   WORLD_MCA_DIR     directory containing the region/*.mca files (or the
##                     world dir itself; "region" is appended if present)
##   WORLD_MCA_Y0      Minecraft y that becomes our y=1 (default 40)
##   WORLD_MCA_CENTER  "x,z" Minecraft block coords that become our origin
##                     (snapped to chunk alignment; default 0,0)

const TAG_END := 0
const TAG_BYTE := 1
const TAG_SHORT := 2
const TAG_INT := 3
const TAG_LONG := 4
const TAG_FLOAT := 5
const TAG_DOUBLE := 6
const TAG_BYTE_ARRAY := 7
const TAG_STRING := 8
const TAG_LIST := 9
const TAG_COMPOUND := 10
const TAG_INT_ARRAY := 11
const TAG_LONG_ARRAY := 12

var region_dir := ""
var y0 := 40           # Minecraft y mapped to our y=1
var center := Vector2i.ZERO  # Minecraft block coords of our origin, chunk-aligned

var _regions: Dictionary = {}   # Vector2i -> PackedByteArray (whole file) or false

func _init(world_dir: String) -> void:
	if world_dir.is_empty():
		return
	region_dir = world_dir
	if DirAccess.dir_exists_absolute(world_dir.path_join("region")):
		region_dir = world_dir.path_join("region")
	var y_env := EnvConfig.text("WORLD_MCA_Y0")
	if y_env.is_valid_int():
		y0 = y_env.to_int()
	var center_env := OS.get_environment("WORLD_MCA_CENTER")
	var parts := center_env.split(",")
	if parts.size() == 2 and parts[0].strip_edges().is_valid_int() and parts[1].strip_edges().is_valid_int():
		# Snap to chunk alignment so chunk borders line up 1:1.
		center = Vector2i(
			(parts[0].strip_edges().to_int() >> 4) << 4,
			(parts[1].strip_edges().to_int() >> 4) << 4)
	print("MCA world: %s (y0=%d, center=%s)" % [region_dir, y0, center])

func is_valid() -> bool:
	if region_dir.is_empty():
		return false
	var dir := DirAccess.open(region_dir)
	if dir == null:
		return false
	for file in dir.get_files():
		if file.ends_with(".mca"):
			return true
	return false

## Our chunk (cx, cz) -> block data, or empty if the save has no such chunk.
func read_chunk(cx: int, cz: int) -> PackedByteArray:
	var mc_cx := cx + (center.x >> 4)
	var mc_cz := cz + (center.y >> 4)
	var nbt := _read_chunk_nbt(mc_cx, mc_cz)
	if nbt.is_empty():
		return PackedByteArray()
	# Pre-1.18 wraps everything in "Level".
	var root: Dictionary = nbt.get("Level", nbt)
	var sections: Array = root.get("sections", root.get("Sections", []))
	if sections.is_empty():
		return PackedByteArray()
	var data := PackedByteArray()
	data.resize(WorldGen.CHUNK_SIZE * WorldGen.CHUNK_SIZE * WorldGen.CHUNK_H)
	for section: Dictionary in sections:
		_apply_section(data, section)
	# A safety floor so nobody falls out of the world.
	for lz in 16:
		for lx in 16:
			data[WorldGen.idx(lx, 0, lz)] = Blocks.BEDROCK
	return data

func _apply_section(data: PackedByteArray, section: Dictionary) -> void:
	var sy := int(section.get("Y", 127))
	if sy == 127:
		return
	var states: Dictionary = section.get("block_states", {})
	var palette: Array = states.get("palette", section.get("Palette", []))
	if palette.is_empty():
		return
	var longs: PackedInt64Array = states.get("data", section.get("BlockStates", PackedInt64Array()))
	# Map the palette once per section.
	var mapped := PackedByteArray()
	mapped.resize(palette.size())
	for i in palette.size():
		var entry: Dictionary = palette[i]
		mapped[i] = map_entry(entry)
	var base_y := sy * 16 - y0 + 1   # our y for the section's mc y floor
	if base_y >= WorldGen.CHUNK_H or base_y + 16 <= 1:
		return
	if longs.is_empty() or palette.size() == 1:
		var block := mapped[0]
		if block == Blocks.AIR:
			return
		for y in range(maxi(base_y, 1), mini(base_y + 16, WorldGen.CHUNK_H)):
			for lz in 16:
				for lx in 16:
					data[WorldGen.idx(lx, y, lz)] = block
		return
	var bits := maxi(4, _bit_length(palette.size() - 1))
	var per_long := 64 / bits
	var mask := (1 << bits) - 1
	for my in 16:
		var y := base_y + my
		if y < 1 or y >= WorldGen.CHUNK_H:
			continue
		for lz in 16:
			for lx in 16:
				var index := (my * 16 + lz) * 16 + lx
				var value := (longs[index / per_long] >> ((index % per_long) * bits)) & mask
				if value < mapped.size():
					var block := mapped[value]
					if block != Blocks.AIR:
						data[WorldGen.idx(lx, y, lz)] = block

static func _bit_length(value: int) -> int:
	var bits := 0
	while value > 0:
		bits += 1
		value >>= 1
	return maxi(bits, 1)

## Find somewhere sensible to spawn: the first grassy-ish column near origin.
func find_spawn() -> Vector3i:
	for radius in range(0, 10):
		for attempt in 16:
			var wx := int(cos(attempt * TAU / 16.0) * radius * 10.0)
			var wz := int(sin(attempt * TAU / 16.0) * radius * 10.0)
			var chunk := read_chunk(floori(wx / 16.0), floori(wz / 16.0))
			if chunk.is_empty():
				continue
			var lx := posmod(wx, 16)
			var lz := posmod(wz, 16)
			for y in range(WorldGen.CHUNK_H - 8, 1, -1):
				var b := chunk[WorldGen.idx(lx, y, lz)]
				if b == Blocks.WATER:
					break
				if Blocks.is_solid(b):
					return Vector3i(wx, y, wz)
	return Vector3i(0, WorldGen.CHUNK_H - 12, 0)

# ------------------------------------------------------------------
# Region file + NBT plumbing
# ------------------------------------------------------------------

func _read_chunk_nbt(mc_cx: int, mc_cz: int) -> Dictionary:
	var rpos := Vector2i(mc_cx >> 5, mc_cz >> 5)
	var blob := _region_blob(rpos)
	if blob.is_empty():
		return {}
	var lx := mc_cx & 31
	var lz := mc_cz & 31
	var head := 4 * (lx + lz * 32)
	if blob.size() < head + 4:
		return {}
	var offset_sectors := (blob[head] << 16) | (blob[head + 1] << 8) | blob[head + 2]
	if offset_sectors == 0:
		return {}
	var at := offset_sectors * 4096
	if blob.size() < at + 5:
		return {}
	var length := (blob[at] << 24) | (blob[at + 1] << 16) | (blob[at + 2] << 8) | blob[at + 3]
	var compression := blob[at + 4]
	if length <= 1 or blob.size() < at + 4 + length:
		return {}
	var payload := blob.slice(at + 5, at + 4 + length)
	var raw: PackedByteArray
	match compression:
		1:
			raw = payload.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		2:
			raw = payload.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		3:
			raw = payload
		_:
			push_error("Region %s chunk %d,%d: unsupported compression %d" % [rpos, mc_cx, mc_cz, compression])
			return {}
	if raw.is_empty():
		return {}
	var stream := StreamPeerBuffer.new()
	stream.data_array = raw
	stream.big_endian = true
	var tag_type := stream.get_u8()
	if tag_type != TAG_COMPOUND:
		return {}
	_read_string(stream)  # root name, usually ""
	return _read_compound(stream)

func _region_blob(rpos: Vector2i) -> PackedByteArray:
	if _regions.has(rpos):
		var cached = _regions[rpos]
		return cached if cached is PackedByteArray else PackedByteArray()
	var path := region_dir.path_join("r.%d.%d.mca" % [rpos.x, rpos.y])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_regions[rpos] = false
		return PackedByteArray()
	var blob := file.get_buffer(file.get_length())
	file.close()
	# Cap the region cache; whole files are ~5-30 MiB each.
	if _regions.size() > 9:
		_regions.clear()
	_regions[rpos] = blob
	return blob

func _read_string(stream: StreamPeerBuffer) -> String:
	var length := stream.get_u16()
	if length == 0:
		return ""
	return stream.get_utf8_string(length)

func _read_compound(stream: StreamPeerBuffer) -> Dictionary:
	var result := {}
	while stream.get_available_bytes() > 0:
		var tag_type := stream.get_u8()
		if tag_type == TAG_END:
			break
		var tag_name := _read_string(stream)
		result[tag_name] = _read_payload(stream, tag_type)
	return result

func _read_payload(stream: StreamPeerBuffer, tag_type: int):
	match tag_type:
		TAG_BYTE:
			return stream.get_8()
		TAG_SHORT:
			return stream.get_16()
		TAG_INT:
			return stream.get_32()
		TAG_LONG:
			return stream.get_64()
		TAG_FLOAT:
			return stream.get_float()
		TAG_DOUBLE:
			return stream.get_double()
		TAG_BYTE_ARRAY:
			var count := stream.get_32()
			return stream.get_data(count)[1]
		TAG_STRING:
			return _read_string(stream)
		TAG_LIST:
			var child_type := stream.get_u8()
			var count := stream.get_32()
			var list := []
			for i in count:
				list.append(_read_payload(stream, child_type))
			return list
		TAG_COMPOUND:
			return _read_compound(stream)
		TAG_INT_ARRAY:
			var count := stream.get_32()
			var ints := PackedInt32Array()
			ints.resize(count)
			for i in count:
				ints[i] = stream.get_32()
			return ints
		TAG_LONG_ARRAY:
			var count := stream.get_32()
			var longs := PackedInt64Array()
			longs.resize(count)
			for i in count:
				longs[i] = stream.get_64()
			return longs
	return null

# ------------------------------------------------------------------
# Block mapping
# ------------------------------------------------------------------

const NAME_MAP := {
	"air": Blocks.AIR, "cave_air": Blocks.AIR, "void_air": Blocks.AIR,
	"grass_block": Blocks.GRASS, "mycelium": Blocks.MYCELIUM, "podzol": 123,
	"dirt": Blocks.DIRT, "coarse_dirt": Blocks.DIRT, "rooted_dirt": Blocks.DIRT,
	"farmland": Blocks.DIRT, "clay": 122,
	"dirt_path": Blocks.PATH, "grass_path": Blocks.PATH,
	"sand": Blocks.SAND,
	"sandstone": Blocks.SANDSTONE, "smooth_sandstone": Blocks.SANDSTONE,
	"water": Blocks.WATER, "seagrass": Blocks.WATER, "tall_seagrass": Blocks.WATER,
	"kelp": Blocks.WATER, "kelp_plant": Blocks.WATER, "bubble_column": Blocks.WATER,
	"lava": Blocks.LAVA,
	"stone": Blocks.STONE,
	"cobblestone": Blocks.COBBLE, "mossy_cobblestone": Blocks.MOSSY_COBBLE,
	"snow": Blocks.SNOW_LAYER, "snow_block": Blocks.SNOW, "powder_snow": Blocks.SNOW,
	"ice": Blocks.ICE, "frosted_ice": Blocks.ICE,
	"glass": Blocks.GLASS, "tinted_glass": Blocks.GLASS,
	"bricks": Blocks.BRICK,
	"pumpkin": Blocks.PUMPKIN, "carved_pumpkin": Blocks.PUMPKIN, "jack_o_lantern": Blocks.LANTERN,
	"lantern": Blocks.LANTERN, "soul_lantern": Blocks.LANTERN, "glowstone": Blocks.GLOWSTONE,
	"verdant_froglight": Blocks.LANTERN,
	"end_rod": Blocks.LANTERN, "redstone_lamp": Blocks.LANTERN, "copper_bulb": Blocks.LANTERN,
	"campfire": Blocks.CAMPFIRE, "soul_campfire": Blocks.CAMPFIRE,
	"fire": Blocks.FIRE, "soul_fire": Blocks.FIRE, "magma_block": 207,
	"poppy": Blocks.FLOWER_RED, "red_tulip": Blocks.FLOWER_RED, "rose_bush": Blocks.FLOWER_RED,
	"dandelion": Blocks.FLOWER_YELLOW, "sunflower": Blocks.FLOWER_YELLOW,
	"orange_tulip": Blocks.FLOWER_YELLOW, "torchflower": Blocks.FLOWER_YELLOW,
	"pink_tulip": Blocks.FLOWER_PINK, "peony": Blocks.FLOWER_PINK, "allium": Blocks.FLOWER_PINK,
	"lilac": Blocks.FLOWER_PINK, "pink_petals": Blocks.FLOWER_PINK,
	"blue_orchid": Blocks.BLUEBELL, "cornflower": Blocks.BLUEBELL,
	"azure_bluet": Blocks.DAISY, "oxeye_daisy": Blocks.DAISY,
	"lily_of_the_valley": Blocks.DAISY, "white_tulip": Blocks.DAISY,
	"wither_rose": Blocks.DEAD_BUSH, "pitcher_plant": Blocks.BLUEBELL,
	"pitcher_crop": Blocks.SAPLING, "torchflower_crop": Blocks.SAPLING,
	"attached_pumpkin_stem": Blocks.SAPLING, "attached_melon_stem": Blocks.SAPLING,
	"cocoa": Blocks.BERRY_BUSH, "nether_sprouts": Blocks.FERN,
	"weeping_vines": Blocks.VINE, "weeping_vines_plant": Blocks.VINE,
	"twisting_vines": Blocks.VINE, "twisting_vines_plant": Blocks.VINE,
	"cave_vines": Blocks.VINE, "cave_vines_plant": Blocks.VINE, "vine": Blocks.VINE,
	"big_dripleaf": Blocks.LILY_PAD, "big_dripleaf_stem": Blocks.BAMBOO,
	"small_dripleaf": Blocks.SAPLING,
	"cherry_leaves": Blocks.LEAVES_PINK, "spruce_leaves": Blocks.LEAVES_DARK,
	"dark_oak_leaves": Blocks.LEAVES_DARK, "pale_oak_leaves": Blocks.LEAVES_DARK,
	"birch_leaves": Blocks.LEAVES_LIGHT,
	"mangrove_planks": 205, "crimson_planks": 204, "warped_planks": 203,
	"bamboo_planks": Blocks.BIRCH_PLANKS, "bamboo_mosaic": Blocks.BIRCH_PLANKS,
	"bamboo_block": 206, "stripped_bamboo_block": Blocks.BIRCH_PLANKS,
	"mangrove_roots": Blocks.LOG, "muddy_mangrove_roots": Blocks.LOG,
	"netherrack": 139, "nether_wart_block": 139, "crimson_nylium": 139,
	"warped_nylium": Blocks.WOOL_TEAL, "warped_wart_block": Blocks.WOOL_TEAL,
	"nether_wart": Blocks.MUSHROOM, "soul_sand": 118, "soul_soil": 118,
	"end_stone": Blocks.SANDSTONE, "end_stone_bricks": Blocks.SANDSTONE,
	"purpur_block": Blocks.PURPUR, "purpur_pillar": Blocks.PURPUR,
	"chorus_plant": Blocks.WOOL_PURPLE, "chorus_flower": Blocks.WOOL_PURPLE,
	"nether_portal": Blocks.GLASS_RED + 5, "end_portal": Blocks.WOOL_BLACK,
	"end_gateway": Blocks.WOOL_BLACK, "respawn_anchor": 113,
	"shulker_box": Blocks.WOOL_PURPLE, "decorated_pot": 117,
	"lodestone": Blocks.COBBLE, "ancient_debris": Blocks.CHARRED,
	"netherite_block": Blocks.CHARRED, "raw_iron_block": 141, "bone_block": 111,
	"pale_moss_block": 133,
	"dripstone_block": 117, "smithing_table": Blocks.PLANKS,
	"fletching_table": Blocks.PLANKS, "cartography_table": Blocks.PLANKS,
	"lectern": Blocks.PLANKS, "loom": Blocks.PLANKS, "composter": Blocks.PLANKS,
	"beehive": Blocks.PLANKS, "bee_nest": Blocks.PLANKS,
	"smoker": Blocks.FURNACE, "blast_furnace": Blocks.FURNACE,
	"dispenser": Blocks.COBBLE, "dropper": Blocks.COBBLE,
	"observer": Blocks.COBBLE, "piston": Blocks.COBBLE,
	"sticky_piston": Blocks.COBBLE, "piston_head": Blocks.COBBLE,
	"hopper": Blocks.STEEL, "cauldron": Blocks.STEEL, "bell": Blocks.GOLD,
	"enchanting_table": 113, "ender_chest": 113,
	"grass": Blocks.TALL_GRASS, "short_grass": Blocks.TALL_GRASS, "tall_grass": Blocks.TALL_GRASS,
	"fern": Blocks.FERN, "large_fern": Blocks.FERN, "dead_bush": Blocks.DEAD_BUSH,
	"sweet_berry_bush": Blocks.BERRY_BUSH,
	"brown_mushroom": Blocks.MUSHROOM, "red_mushroom": Blocks.MUSHROOM,
	"bedrock": Blocks.BEDROCK,
	"tnt": Blocks.BOOM, "slime_block": Blocks.BOUNCY, "honey_block": Blocks.BOUNCY,
	"sponge": Blocks.SPONGE, "wet_sponge": Blocks.SPONGE, "note_block": Blocks.NOTE,
	"jukebox": Blocks.NOTE, "gold_block": Blocks.GOLD, "raw_gold_block": Blocks.GOLD,
	"diamond_block": Blocks.DIAMOND,
	"amethyst_block": Blocks.CRYSTAL_PINK, "budding_amethyst": Blocks.CRYSTAL_PINK,
	"beacon": Blocks.TELEPORT, "end_portal_frame": Blocks.TELEPORT,
	"birch_planks": Blocks.BIRCH_PLANKS, "dark_oak_planks": Blocks.DARK_PLANKS,
	"cherry_planks": Blocks.CHERRY_PLANKS,
	"quartz_block": Blocks.MARBLE, "smooth_quartz": Blocks.MARBLE,
	"anvil": Blocks.STEEL, "cake": Blocks.CONFETTI,
	"crafting_table": Blocks.CRAFTING_TABLE,
	"chest": Blocks.CHEST, "trapped_chest": Blocks.CHEST,
	"barrel": Blocks.CHEST, "furnace": Blocks.FURNACE,
	"pumpkin_stem": Blocks.SAPLING, "melon_stem": Blocks.SAPLING,
	"lily_pad": Blocks.LILY_PAD, "moss_carpet": Blocks.CARPET_RED + 3,
	"honeycomb_block": Blocks.WOOL_ORANGE,
}

## Stained glass keeps its color (16 vanilla tints onto our 8).
const STAINED_GLASS_MAP := {
	"red": Blocks.GLASS_RED, "orange": Blocks.GLASS_RED + 1,
	"yellow": Blocks.GLASS_RED + 2, "lime": Blocks.GLASS_RED + 3,
	"green": Blocks.GLASS_RED + 3, "cyan": Blocks.GLASS_RED + 4,
	"light_blue": Blocks.GLASS_RED + 4, "blue": Blocks.GLASS_RED + 4,
	"purple": Blocks.GLASS_RED + 5, "magenta": Blocks.GLASS_RED + 5,
	"pink": Blocks.GLASS_RED + 6, "white": Blocks.GLASS_RED + 7,
	"light_gray": Blocks.GLASS_RED + 7, "gray": Blocks.GLASS_RED + 7,
	"black": Blocks.GLASS_RED + 7, "brown": Blocks.GLASS_RED + 1,
}

const CARPET_COLOR_MAP := {
	"red": Blocks.CARPET_RED, "orange": Blocks.CARPET_RED + 1,
	"brown": Blocks.CARPET_RED + 1, "yellow": Blocks.CARPET_RED + 2,
	"lime": Blocks.CARPET_RED + 3, "green": Blocks.CARPET_RED + 3,
	"cyan": Blocks.CARPET_RED + 4, "light_blue": Blocks.CARPET_RED + 4,
	"blue": Blocks.CARPET_RED + 4, "purple": Blocks.CARPET_RED + 5,
	"magenta": Blocks.CARPET_RED + 5, "pink": Blocks.CARPET_RED + 6,
	"white": Blocks.CARPET_RED + 7, "light_gray": Blocks.CARPET_RED + 7,
	"gray": Blocks.CARPET_RED + 7, "black": Blocks.CARPET_RED + 7,
}

const WOOL_COLOR_MAP := {
	"red": Blocks.WOOL_RED, "orange": Blocks.WOOL_ORANGE, "yellow": Blocks.WOOL_YELLOW,
	"lime": Blocks.WOOL_GREEN, "green": Blocks.WOOL_GREEN, "cyan": Blocks.WOOL_TEAL,
	"light_blue": Blocks.WOOL_BLUE, "blue": Blocks.WOOL_BLUE, "purple": Blocks.WOOL_PURPLE,
	"magenta": Blocks.WOOL_PURPLE, "pink": Blocks.WOOL_PINK, "white": Blocks.WOOL_WHITE,
	"light_gray": Blocks.WOOL_WHITE, "gray": Blocks.WOOL_BLACK, "black": Blocks.WOOL_BLACK,
	"brown": Blocks.WOOL_BROWN,
}

## Parts of a block name that mean "thin decoration we can't represent" —
## these become air rather than a misleading full cube.
const SKIP_PARTS := [
	"rail", "button", "lever", "sign", "banner", "pressure_plate", "carpet",
	"brewing_stand", "pointed_dripstone",
	"tripwire", "redstone_wire", "repeater", "comparator", "candle", "pot",
	"flower_pot", "scaffolding", "cobweb", "chain",
	"sculk_vein", "frogspawn", "sniffer_egg", "turtle_egg",
	"structure_void", "light", "barrier", "player_head", "skull", "spore_blossom",
	"hanging_roots", "glow_lichen", "sea_pickle", "amethyst_cluster", "coral_fan",
	"coral_wall_fan", "head", "amethyst_bud", "lightning_rod",
]

static var _map_cache: Dictionary = {}

const _STAIR_FACING := {"north": 0, "east": 1, "south": 2, "west": 3}

## Full-entry mapping: uses blockstate Properties so stairs keep their
## facing, double slabs become full blocks, and so on.
static func map_entry(entry: Dictionary) -> int:
	var name := str(entry.get("Name", "")).trim_prefix("minecraft:")
	var props: Dictionary = entry.get("Properties", {})
	if name.ends_with("_stairs"):
		# Stone-family checks must beat the generic "brick" check, or every
		# stone_brick/deepslate/blackstone stair turns red clay.
		var base := _wood_stairs_base(name)
		if name.contains("quartz") or name.contains("diorite") or name.contains("sandstone"):
			base = Blocks.STAIRS_QUARTZ
		elif name.contains("stone") or name.contains("andesite") or name.contains("deepslate") \
				or name.contains("cobbled") or name.contains("tuff") \
				or name.contains("purpur") or name.contains("prismarine"):
			base = Blocks.STAIRS_STONE
		elif name.contains("brick") or name.contains("granite"):
			base = Blocks.STAIRS_BRICK
		return base + int(_STAIR_FACING.get(str(props.get("facing", "north")), 0))
	if name.ends_with("_slab"):
		var double: bool = str(props.get("type", "bottom")) == "double"
		if name.contains("quartz") or name.contains("diorite") or name.contains("sandstone"):
			return 114 if double else Blocks.SLAB_QUARTZ
		if name.contains("stone") or name.contains("andesite") or name.contains("deepslate") \
				or name.contains("cobbled") or name.contains("tuff") \
				or name.contains("purpur") or name.contains("prismarine"):
			return 104 if double else Blocks.SLAB_STONE
		if name.contains("brick") or name.contains("granite"):
			return Blocks.BRICK if double else Blocks.SLAB_BRICK
		return _wood_slab(name, double)
	if name.ends_with("_fence") or name.ends_with("_fence_gate"):
		if name.begins_with("spruce"):
			return Blocks.FENCE_SPRUCE
		if name.begins_with("birch") or name.begins_with("bamboo"):
			return Blocks.FENCE_BIRCH
		if name.begins_with("dark_oak") or name.begins_with("pale_oak"):
			return Blocks.FENCE_DARK
		if name.begins_with("crimson") or name.begins_with("cherry"):
			return Blocks.FENCE_CRIMSON
		if name.begins_with("mangrove"):
			return Blocks.FENCE_MANGROVE
		if name.begins_with("warped"):
			return Blocks.FENCE_WARPED
		return Blocks.FENCE
	if name.ends_with("_wall"):
		return Blocks.WALL
	if name.contains("glass_pane") or name == "iron_bars":
		return Blocks.GLASS_PANE
	if name.contains("torch") and not name.contains("torchflower"):
		return Blocks.TORCH
	if name == "ladder":
		return Blocks.LADDER
	if name == "vine" or name.ends_with("_vines") or name.ends_with("_vines_plant") \
			or name == "glow_lichen":
		return Blocks.VINE
	if name == "bamboo" or name == "bamboo_sapling":
		return Blocks.BAMBOO
	if name.ends_with("_trapdoor"):
		return Blocks.SLAB_STONE if name.begins_with("iron") else Blocks.SLAB_WOOD
	if name.ends_with("_door"):
		return Blocks.DOOR_IRON if name.begins_with("iron") else Blocks.DOOR_WOOD
	match name:
		"wheat": return Blocks.WHEAT_PLANT
		"carrots", "potatoes", "beetroots", "sweet_berry_bush": return Blocks.BERRY_BUSH
		"sugar_cane": return Blocks.CATTAIL
		"fern", "large_fern": return Blocks.FERN
		"dead_bush": return Blocks.DEAD_BUSH
	return map_block("minecraft:" + name)

## Species-colored wooden stairs/slabs so imported builds keep their wood.
static func _wood_stairs_base(name: String) -> int:
	if name.begins_with("spruce"):
		return Blocks.STAIRS_SPRUCE
	if name.begins_with("birch") or name.begins_with("bamboo"):
		return Blocks.STAIRS_BIRCH
	if name.begins_with("dark_oak") or name.begins_with("pale_oak"):
		return Blocks.STAIRS_DARK
	if name.begins_with("crimson") or name.begins_with("cherry"):
		return Blocks.STAIRS_CRIMSON
	if name.begins_with("mangrove"):
		return Blocks.STAIRS_MANGROVE
	if name.begins_with("warped"):
		return Blocks.STAIRS_WARPED
	return Blocks.STAIRS_WOOD

static func _wood_slab(name: String, double: bool) -> int:
	if name.begins_with("spruce"):
		return Blocks.PLANKS if double else Blocks.SLAB_SPRUCE
	if name.begins_with("birch") or name.begins_with("bamboo"):
		return Blocks.BIRCH_PLANKS if double else Blocks.SLAB_BIRCH
	if name.begins_with("dark_oak") or name.begins_with("pale_oak"):
		return Blocks.DARK_PLANKS if double else Blocks.SLAB_DARK
	if name.begins_with("crimson") or name.begins_with("cherry"):
		return 204 if double else Blocks.SLAB_CRIMSON
	if name.begins_with("mangrove"):
		return 205 if double else Blocks.SLAB_MANGROVE
	if name.begins_with("warped"):
		return 203 if double else Blocks.SLAB_WARPED
	return Blocks.PLANKS if double else Blocks.SLAB_WOOD

static func map_block(mc_name: String) -> int:
	if _map_cache.has(mc_name):
		return _map_cache[mc_name]
	var mapped := _map_block_uncached(mc_name.trim_prefix("minecraft:"))
	_map_cache[mc_name] = mapped
	return mapped

static func _map_block_uncached(short_name: String) -> int:
	if NAME_MAP.has(short_name):
		return NAME_MAP[short_name]
	# Direct matches onto the Minecraft-style building set (ids 101+).
	match short_name:
		"dirt_path", "grass_path", "coarse_dirt":
			return Blocks.PATH
		"gravel": return 121
		"mud": return 118
		"packed_mud": return 120
		"mud_bricks": return 119
		"rooted_dirt": return Blocks.DIRT
		"podzol", "mycelium": return 123
		"red_sand": return 124
		"smooth_stone": return 104
		"obsidian", "crying_obsidian": return 113
		"terracotta": return 117
		"bookshelf", "chiseled_bookshelf": return 132
		"moss_block", "moss_carpet": return 133
		"packed_ice": return 134
		"blue_ice": return 135
		"cactus": return 136
		"melon": return 137
		"hay_block": return 138
		"red_mushroom_block": return 139
		"brown_mushroom_block", "mushroom_stem": return 140
		"iron_block": return 141
		"copper_block", "cut_copper", "exposed_copper", "weathered_copper": return 142
		"oxidized_copper", "oxidized_cut_copper": return 143
		"emerald_block": return 144
		"lapis_block": return 145
		"redstone_block": return 146
		"coal_block": return 108
		"sea_lantern": return 147
		"shroomlight", "ochre_froglight", "pearlescent_froglight": return 148
		"birch_log", "birch_wood", "stripped_birch_log", "stripped_birch_wood": return 125
		"spruce_log", "spruce_wood", "stripped_spruce_log", "stripped_spruce_wood": return 126
		"cherry_log", "cherry_wood", "stripped_cherry_log", "stripped_cherry_wood": return 127
		"acacia_log", "acacia_wood", "stripped_acacia_log", "stripped_acacia_wood": return 128
		"acacia_planks": return 129
		"jungle_log", "jungle_wood", "stripped_jungle_log", "stripped_jungle_wood": return 130
		"jungle_planks": return 131
		"mangrove_log", "mangrove_wood", "stripped_mangrove_log", "stripped_mangrove_wood": return 205
		"warped_stem", "warped_hyphae", "stripped_warped_stem", "stripped_warped_hyphae": return 208
		"crimson_stem", "crimson_hyphae", "stripped_crimson_stem", "stripped_crimson_hyphae": return 127
	# Potted plants and thin decor bail out before anything can turn them
	# into full cubes.
	if short_name.begins_with("potted_"):
		return Blocks.AIR
	if short_name.contains("candle_cake"):
		return Blocks.CONFETTI
	# Wool / concrete / terracotta / stained glass by their color token.
	for color: String in WOOL_COLOR_MAP.keys():
		if short_name.begins_with(color + "_"):
			var rest := short_name.trim_prefix(color + "_")
			if rest.contains("glass"):
				return STAINED_GLASS_MAP.get(color, Blocks.GLASS)
			if rest == "carpet":
				return CARPET_COLOR_MAP.get(color, Blocks.CARPET_RED + 7)
			if rest == "bed":
				return Blocks.BED
			if rest == "wool" or rest.contains("concrete") or rest.contains("terracotta") \
					or rest.contains("shulker"):
				return WOOL_COLOR_MAP[color]
	for part: String in SKIP_PARTS:
		if short_name == part or short_name.ends_with("_" + part) or short_name.begins_with(part + "_"):
			return Blocks.AIR
	# Ores read as their host rock (checked before quartz/copper so
	# nether_quartz_ore doesn't turn bright white).
	if short_name.ends_with("_ore"):
		if short_name.begins_with("nether_"):
			return 139
		if short_name.contains("deepslate"):
			return 108
		return Blocks.STONE
	if short_name.contains("copper"):
		return 143 if short_name.contains("oxidized") else 142
	if short_name.contains("mossy_stone_brick"):
		return 102
	if short_name.contains("cracked_stone_brick"):
		return 103
	if short_name.contains("deepslate_brick") or short_name.contains("deepslate_tile"):
		return 109
	if short_name.contains("deepslate"):
		return 108
	if short_name.contains("blackstone") or short_name.contains("basalt"):
		return 112
	if short_name.contains("stone_brick"):
		return 101
	if short_name.contains("cobblestone"):
		return Blocks.COBBLE
	if short_name.contains("andesite"):
		return 105
	if short_name.contains("tuff"):
		return 110
	if short_name.contains("diorite"):
		return 106
	if short_name.contains("calcite"):
		return 111
	if short_name.contains("granite"):
		return 107
	if short_name.contains("red_sandstone"):
		return 116
	if short_name.contains("sandstone"):
		return Blocks.SANDSTONE
	if short_name.contains("prismarine"):
		return Blocks.WOOL_TEAL
	if short_name.contains("sculk"):
		return Blocks.WOOL_BLACK
	if short_name.contains("quartz_brick"):
		return 115
	if short_name.contains("quartz"):
		return 114
	if short_name.ends_with("_log") or short_name.ends_with("_wood") \
			or short_name.ends_with("_stem") or short_name.ends_with("_hyphae"):
		return Blocks.LOG
	if short_name.ends_with("_leaves"):
		return Blocks.LEAVES
	if short_name.ends_with("_planks"):
		return Blocks.PLANKS
	if short_name.ends_with("_sapling") or short_name.ends_with("_propagule") \
			or short_name.ends_with("_fungus") or short_name.ends_with("_roots"):
		return Blocks.SAPLING
	if short_name.contains("brick"):
		return Blocks.BRICK
	if short_name.contains("glass"):
		return Blocks.GLASS
	if short_name.contains("coral"):
		# Five coral colors, live and dead, blocks and plants.
		if short_name.begins_with("dead_"):
			return Blocks.WOOL_WHITE if short_name.contains("block") else Blocks.DEAD_BUSH
		var coral_block := short_name.contains("block")
		if short_name.begins_with("tube_"):
			return Blocks.WOOL_BLUE if coral_block else Blocks.BLUEBELL
		if short_name.begins_with("fire_"):
			return Blocks.WOOL_RED if coral_block else Blocks.FLOWER_RED
		if short_name.begins_with("horn_"):
			return Blocks.WOOL_YELLOW if coral_block else Blocks.FLOWER_YELLOW
		return Blocks.WOOL_PINK if coral_block else Blocks.FLOWER_PINK
	# Partial wooden shapes read best as their material.
	for wood in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak",
			"mangrove", "cherry", "bamboo", "crimson", "warped", "pale_oak"]:
		if short_name.begins_with(wood + "_"):
			return Blocks.PLANKS
	if short_name.ends_with("_slab") or short_name.ends_with("_stairs") \
			or short_name.ends_with("_wall") or short_name.ends_with("_fence") \
			or short_name.ends_with("_fence_gate") or short_name.ends_with("_door") \
			or short_name.ends_with("_trapdoor"):
		return Blocks.COBBLE
	if short_name.contains("wheat") or short_name.contains("carrot") \
			or short_name.contains("potato") or short_name.contains("beetroot") \
			or short_name.contains("flower") or short_name.contains("bush") \
			or short_name.contains("azalea"):
		return Blocks.TALL_GRASS
	# Unknown: assume a full solid block reads best as stone.
	return Blocks.STONE

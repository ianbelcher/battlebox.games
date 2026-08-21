class_name Blocks
## The block palette. Every block is a flat-colored voxel (vertex colors, no
## textures) — the look comes from per-face shading, baked ambient occlusion,
## a per-position color jitter and the Forward+ lighting on top.

enum {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	WATER = 5,
	LOG = 6,
	LEAVES = 7,
	PLANKS = 8,
	COBBLE = 9,
	SNOW = 10,
	FLOWER_RED = 11,
	FLOWER_YELLOW = 12,
	FLOWER_PINK = 13,
	TALL_GRASS = 14,
	PUMPKIN = 15,
	MUSHROOM = 16,
	LANTERN = 17,
	CAMPFIRE = 18,
	SAPLING = 19,
	BRICK = 20,
	GLASS = 21,
	WOOL_RED = 22,
	WOOL_ORANGE = 23,
	WOOL_YELLOW = 24,
	WOOL_GREEN = 25,
	WOOL_BLUE = 26,
	WOOL_PURPLE = 27,
	WOOL_WHITE = 28,
	WOOL_BLACK = 29,
	ICE = 30,
	SHELL = 31,
	BERRY_BUSH = 32,
	PATH = 33,
	BEDROCK = 34,
	MARBLE = 35,
	SLATE = 36,
	SANDSTONE = 37,
	BIRCH_PLANKS = 38,
	DARK_PLANKS = 39,
	CHERRY_PLANKS = 40,
	MOSSY_COBBLE = 41,
	GOLD = 42,
	DIAMOND = 43,
	GLOWSTONE = 44,
	CRYSTAL_PINK = 45,
	CRYSTAL_BLUE = 46,
	CRYSTAL_GREEN = 47,
	LAVA = 48,
	WOOL_PINK = 49,
	WOOL_TEAL = 50,
	WOOL_BROWN = 51,
	BOOM = 52,
	FIREWORK = 53,
	BOUNCY = 54,
	LAUNCHER = 55,
	NOTE = 56,
	SPONGE = 57,
	TELEPORT = 58,
	CONFETTI = 59,
	STEEL = 60,
	FIRE = 61,
	CHARRED = 62,
	# 63..102: the battle-block families — 4 materials x 10 colors, generated
	# in _static_init (M_* are the row starts).
	M_STEEL = 63,
	M_STONE = 71,
	M_SOIL = 79,
	M_SNOW = 87,
	MAX_BLOCK = 95,
}

## Eight columns, rainbow-aligned across the four material rows. Each block
## gets a REAL name; the finish still tells the materials apart.
const FAMILY_COLORS := [
	Color("c94a3d"), Color("d98a3d"), Color("d9c44a"), Color("58a850"),
	Color("4a7dc9"), Color("8f5fc2"), Color("e8e8ea"), Color("35363c"),
]
const STEEL_NAMES := ["Bronze", "Copper", "Gold Alloy", "Emerald Steel",
	"Cobalt", "Amethyst Steel", "Silver", "Iron"]
const STONE_NAMES := ["Ruby Rock", "Topaz Rock", "Amber Rock", "Jade",
	"Lapis", "Amethyst", "Gypsum", "Coal"]
const ORGANIC_NAMES := ["Redwood", "Timber", "Sand Pile", "Turf",
	"Clay", "Lavender", "Birch Bark", "Peat"]
const SNOW_NAMES := ["Rose Snow", "Peach Snow", "Golden Snow", "Mint Snow",
	"Blue Ice", "Violet Snow", "Snow Drift", "Ash"]
static var EXTRA: Dictionary = {}
## Extra cross-plants past the family rows.
const FERN := 95
const DEAD_BUSH := 96
const CATTAIL := 97
const DAISY := 98
const BLUEBELL := 99
const WHEAT_PLANT := 100
## Shaped blocks (ids 149+): stairs come in four materials x four facings
## (N/E/S/W = +0..3); slabs, fences, walls and panes are one id each.
## Torch/vine/ladder/bamboo render as crosses.
const STAIRS_WOOD := 149
const STAIRS_STONE := 153
const STAIRS_BRICK := 157
const STAIRS_QUARTZ := 161
const SLAB_WOOD := 165
const SLAB_STONE := 166
const SLAB_BRICK := 167
const SLAB_QUARTZ := 168
const FENCE := 169
const WALL := 170
const GLASS_PANE := 171
const TORCH := 172
const VINE := 173
const LADDER := 174
const BAMBOO := 175
## Import-fidelity extras: thin snow, stained glass in 8 tints, and
## species-tinted leaves so vanilla Minecraft maps read like themselves.
const SNOW_LAYER := 176
const GLASS_RED := 177  # ..184: red orange yellow green blue purple pink white
const LEAVES_DARK := 185
const LEAVES_LIGHT := 186
const LEAVES_PINK := 187
const CARPET_RED := 188  # ..195: 8 wool-colored floor carpets
const CRAFTING_TABLE := 196
const CHEST := 197
const FURNACE := 198
const DOOR_WOOD := 199
const DOOR_IRON := 200
const BED := 201
const LILY_PAD := 202
const WARPED_PLANKS := 203
const CRIMSON_PLANKS := 204
const MANGROVE_PLANKS := 205
const BAMBOO_BLOCK := 206
const MAGMA := 207
const WARPED_STEM := 208
## Per-species wooden stairs (4 facings each) and slabs, so imported
## builds keep their wood colors: spruce, birch, dark oak,
## crimson/cherry, mangrove, warped.
const STAIRS_SPRUCE := 209
const STAIRS_BIRCH := 213
const STAIRS_DARK := 217
const STAIRS_CRIMSON := 221
const STAIRS_MANGROVE := 225
const STAIRS_WARPED := 229
const SLAB_SPRUCE := 233
const SLAB_BIRCH := 234
const SLAB_DARK := 235
const SLAB_CRIMSON := 236
const SLAB_MANGROVE := 237
const SLAB_WARPED := 238
## Per-species fences + the last two audit leftovers.
const FENCE_SPRUCE := 239
const FENCE_BIRCH := 240
const FENCE_DARK := 241
const FENCE_CRIMSON := 242
const FENCE_MANGROVE := 243
const FENCE_WARPED := 244
const PURPUR := 245
const MYCELIUM := 246
## THE CAPTURE-THE-FLAG BEACON: the glowing pole standing on each team's
## mound. One id per team colour, in the SAME ORDER as WorldNode.TEAM_WOOL,
## so `BEACON_TEAM + (team % 8)` is that team's.
##
## Unbreakable, because a flag you can dig away is not a flag, and bright,
## because it is the thing everybody navigates by — you should be able to
## pick your own base out of the landscape from across the map.
##
## NOTE FOR WHOEVER ADDS BLOCKS NEXT: a block id is ONE BYTE. Chunks are
## `PackedByteArray`, so 255 is the ceiling and 255 is now the only id
## left. The next family needs the chunk format widened first; do not
## quietly renumber these, they are the wire format.
const BEACON_TEAM := 247  # ..254: red blue green yellow purple orange teal pink
## THE TRAP BLOCK. Looks like whatever is beside it and is not there.
##
## It takes the LAST free id: chunks are a PackedByteArray, so 255 is the
## ceiling and this is the end of the road. Anything after this needs the
## chunk format widened first.
const TRAP := 255

static func shape_of(id: int) -> String:
	return str(info(id).get("shape", ""))

static func stairs_facing_of(id: int) -> int:
	return posmod(id - STAIRS_WOOD, 4)

## Rotate a placeable stairs id so it ascends the way the player faces.
static func orient_stairs(id: int, dir: Vector3) -> int:
	if shape_of(id) != "stairs":
		return id
	var base := id - stairs_facing_of(id)
	var facing := 0  # north (-z)
	if absf(dir.x) > absf(dir.z):
		facing = 1 if dir.x > 0.0 else 3
	elif dir.z > 0.0:
		facing = 2
	return base + facing

## The Minecraft-style building set (ids 101+). Grouped in rows of 8 so
## the Blocks tab lines up: stone, deep/dark, earthy, wood, nature, shiny.
const MC_BLOCKS := {
	101: {"name": "Stone Bricks", "color": Color("8c8f96"), "hard": 2, "rough": 1.2},
	102: {"name": "Mossy Stone Bricks", "color": Color("7c8a72"), "hard": 2, "rough": 1.4},
	103: {"name": "Cracked Stone Bricks", "color": Color("7e8188"), "hard": 2, "rough": 1.6},
	104: {"name": "Smooth Stone", "color": Color("a3a6ad"), "hard": 2, "rough": 0.4},
	105: {"name": "Andesite", "color": Color("888a86"), "hard": 2, "rough": 1.3},
	106: {"name": "Diorite", "color": Color("c8c5c0"), "hard": 2, "rough": 1.3},
	107: {"name": "Granite", "color": Color("9a6a55"), "hard": 2, "rough": 1.3},
	108: {"name": "Deepslate", "color": Color("4b4d52"), "hard": 2, "rough": 1.5},
	109: {"name": "Deepslate Bricks", "color": Color("55575c"), "hard": 2, "rough": 1.2},
	110: {"name": "Tuff", "color": Color("6d6f66"), "hard": 2, "rough": 1.6},
	111: {"name": "Calcite", "color": Color("dedbd4"), "hard": 2, "rough": 0.8},
	112: {"name": "Basalt", "color": Color("47454b"), "hard": 2, "rough": 1.4},
	113: {"name": "Obsidian", "color": Color("1c1226"), "hard": 3, "rough": 0.2, "emit": 0.05},
	114: {"name": "Quartz", "color": Color("efe9e2"), "hard": 2, "rough": 0.3},
	115: {"name": "Quartz Bricks", "color": Color("e6e0d8"), "hard": 2, "rough": 0.4},
	116: {"name": "Red Sandstone", "color": Color("b56b3a"), "hard": 2, "rough": 1.2},
	117: {"name": "Terracotta", "color": Color("9a5f43"), "hard": 2, "rough": 1.4},
	118: {"name": "Mud", "color": Color("5c4a3d"), "rough": 2.6},
	119: {"name": "Mud Bricks", "color": Color("8a6f52"), "hard": 1, "rough": 1.8},
	120: {"name": "Packed Mud", "color": Color("6e5a48"), "hard": 1, "rough": 2.0},
	121: {"name": "Gravel", "color": Color("7f7c78"), "rough": 2.4},
	122: {"name": "Clay Block", "color": Color("9aa3b0"), "rough": 1.6},
	123: {"name": "Podzol", "color": Color("5a4630"), "top": Color("7a5c38"), "rough": 2.4},
	124: {"name": "Red Sand", "color": Color("c07a45"), "rough": 2.2},
	125: {"name": "Birch Log", "color": Color("d9d4c2"), "top": Color("c2b48a"), "hard": 1, "rough": 1.2},
	126: {"name": "Spruce Log", "color": Color("4a3524"), "top": Color("6e5238"), "hard": 1, "rough": 1.4},
	127: {"name": "Cherry Log", "color": Color("6e4148"), "top": Color("d9a8b8"), "hard": 1, "rough": 1.2},
	128: {"name": "Acacia Log", "color": Color("6e5a4a"), "top": Color("b0603a"), "hard": 1, "rough": 1.4},
	129: {"name": "Acacia Planks", "color": Color("b0603a"), "hard": 1, "rough": 1.0},
	130: {"name": "Jungle Log", "color": Color("5a4a30"), "top": Color("8a6f47"), "hard": 1, "rough": 1.4},
	131: {"name": "Jungle Planks", "color": Color("a5794f"), "hard": 1, "rough": 1.0},
	132: {"name": "Bookshelf", "color": Color("8a6a42"), "top": Color("b08d5e"), "hard": 1, "rough": 1.0},
	133: {"name": "Moss Block", "color": Color("5d7e3c"), "rough": 2.0},
	134: {"name": "Packed Ice", "color": Color("9cc2e8"), "hard": 1, "rough": 0.2},
	135: {"name": "Blue Ice", "color": Color("6fa8e8"), "hard": 1, "rough": 0.1},
	136: {"name": "Cactus", "color": Color("4a7a35"), "top": Color("6b9a4d"), "rough": 1.6},
	137: {"name": "Melon", "color": Color("5d8a3a"), "top": Color("6f9c47"), "rough": 1.2},
	138: {"name": "Hay Bale", "color": Color("c9a83a"), "top": Color("d9bc50"), "rough": 1.8},
	139: {"name": "Red Mushroom Block", "color": Color("b03a30"), "top": Color("c24a40"), "rough": 1.2},
	140: {"name": "Brown Mushroom Block", "color": Color("8a674a"), "rough": 1.2},
	141: {"name": "Iron Block", "color": Color("d8d8d8"), "hard": 3, "rough": 0.2, "emit": 0.1},
	142: {"name": "Copper Block", "color": Color("c06843"), "hard": 3, "rough": 0.3, "emit": 0.08},
	143: {"name": "Oxidized Copper", "color": Color("4fab90"), "hard": 3, "rough": 0.6},
	144: {"name": "Emerald Block", "color": Color("2fbf6b"), "hard": 3, "rough": 0.2, "emit": 0.15},
	145: {"name": "Lapis Block", "color": Color("2a4fc0"), "hard": 2, "rough": 0.5, "emit": 0.08},
	146: {"name": "Redstone Block", "color": Color("c02a1c"), "hard": 2, "rough": 0.4, "emit": 0.5},
	147: {"name": "Sea Lantern", "color": Color("c9e8dc"), "hard": 1, "emit": 2.0, "light": 3.0},
	148: {"name": "Shroomlight", "color": Color("f0a05a"), "hard": 1, "emit": 2.2, "light": 3.2},
}

static func _static_init() -> void:
	for i in FAMILY_COLORS.size():
		var base: Color = FAMILY_COLORS[i]
		# Same COLOR across materials — the finish tells them apart:
		# steel smooth + sheen, stone rough + faint sheen, organic rough
		# matte (and it BURNS), snow smooth, translucent and soft.
		EXTRA[M_STEEL + i] = {"name": STEEL_NAMES[i], "color": base,
			"top": base.lightened(0.18), "solid": true, "opaque": true, "emit": 0.25}
		EXTRA[M_STONE + i] = {"name": STONE_NAMES[i], "color": base,
			"solid": true, "opaque": true, "emit": 0.06, "rough": 2.2}
		EXTRA[M_SOIL + i] = {"name": ORGANIC_NAMES[i], "color": base.darkened(0.06),
			"solid": true, "opaque": true, "rough": 3.0}
		EXTRA[M_SNOW + i] = {"name": SNOW_NAMES[i],
			"color": Color(base.lightened(0.35), 0.8),
			"solid": false, "opaque": false, "translucent": true}
	EXTRA[FERN] = {"name": "Fern", "color": Color("3f7a33"), "cross": true, "sway": 0.5}
	EXTRA[DEAD_BUSH] = {"name": "Dead Bush", "color": Color("9a7648"), "cross": true, "sway": 0.2}
	EXTRA[CATTAIL] = {"name": "Cattail", "color": Color("6b8a3d"), "cross": true, "sway": 0.6}
	EXTRA[DAISY] = {"name": "Daisy", "color": Color("f2f2e0"), "cross": true, "sway": 0.4}
	EXTRA[BLUEBELL] = {"name": "Bluebell", "color": Color("6a7df0"), "cross": true, "sway": 0.4}
	EXTRA[WHEAT_PLANT] = {"name": "Wild Wheat", "color": Color("d9b84a"), "cross": true, "sway": 0.7}
	# The team beacons. Brighter and more saturated than the matching wool,
	# because these are meant to be READ at distance and after dark rather
	# than to look like a building material.
	var beacon_names := ["Red", "Blue", "Green", "Yellow", "Purple",
		"Orange", "Teal", "Pink"]
	var beacon_colors := [Color("ff5555"), Color("5a8cff"), Color("5ad35c"),
		Color("ffd83d"), Color("bf6bff"), Color("ff9a3d"), Color("48dcd2"),
		Color("ff79c0")]
	# THE TRAP BLOCK. Drawn as a full cube so it reads as part of a wall or
	# a floor, and `solid` FALSE so you drop straight through it.
	#
	# Its colour is a placeholder: the mesher replaces it per face with
	# whatever is beside that face, so a trap set among grass is grass and
	# one set in a brick wall is brick. See `Mesher` and `disguise_of`.
	# OPAQUE but NOT SOLID, and the pair is the whole trick. Opaque is what
	# the MESHER reads: neighbours cull their faces toward it exactly as
	# they would toward any block, so there is no seam to give it away.
	# Solid is what PHYSICS reads, and it is false, so you go straight
	# through. Getting either the wrong way round loses the joke — a
	# non-opaque trap is outlined in seams, and a solid one is a block.
	EXTRA[TRAP] = {"name": "Trap Block", "color": Color("7fb84e"),
		"solid": false, "opaque": true, "hard": 1}
	for i in beacon_colors.size():
		# `emit` is what makes the block itself look lit, and it is free —
		# it is only a material property. `light` spawns a REAL OmniLight3D
		# per block, and ChunkView caps those at 8 per chunk: a four-block
		# pole therefore spends half a chunk's light budget on one column.
		# That is worth it for the thing everyone navigates by, but keep
		# the energy modest — four of these are stacked on top of each
		# other, so they add up, and anything brighter washes the mound out
		# at night instead of lighting it.
		EXTRA[BEACON_TEAM + i] = {"name": str(beacon_names[i]) + " Beacon",
			"color": beacon_colors[i], "top": beacon_colors[i].lightened(0.25),
			"solid": true, "opaque": true, "emit": 3.2, "light": 1.6,
			"unbreakable": true}
	for mc_id: int in MC_BLOCKS.keys():
		var spec: Dictionary = MC_BLOCKS[mc_id].duplicate()
		spec["solid"] = true
		spec["opaque"] = true
		EXTRA[mc_id] = spec
	var stair_mats := [["Wood", Color("b08d5e")], ["Stone", Color("8c8f96")],
		["Brick", Color("b0524a")], ["Quartz", Color("efe9e2")]]
	for mat_i in 4:
		for f in 4:
			EXTRA[STAIRS_WOOD + mat_i * 4 + f] = {
				"name": str(stair_mats[mat_i][0]) + " Stairs",
				"color": stair_mats[mat_i][1], "solid": true, "opaque": false,
				"shape": "stairs", "hard": 1 if mat_i == 0 else 2}
		EXTRA[SLAB_WOOD + mat_i] = {"name": str(stair_mats[mat_i][0]) + " Slab",
			"color": stair_mats[mat_i][1], "solid": true, "opaque": false,
			"shape": "slab", "hard": 1 if mat_i == 0 else 2}
	EXTRA[FENCE] = {"name": "Fence", "color": Color("9a7a4f"), "solid": true,
		"opaque": false, "shape": "fence", "hard": 1}
	EXTRA[WALL] = {"name": "Stone Wall", "color": Color("7e8188"), "solid": true,
		"opaque": false, "shape": "wall", "hard": 2}
	EXTRA[GLASS_PANE] = {"name": "Glass Pane", "color": Color(0.75, 0.87, 0.95, 0.5),
		"solid": true, "opaque": false, "shape": "pane", "hard": 0}
	EXTRA[TORCH] = {"name": "Torch", "color": Color("ffd98a"), "cross": true,
		"emit": 2.2, "light": 2.6}
	EXTRA[VINE] = {"name": "Vine", "color": Color("4a7a35"), "cross": true, "sway": 0.5}
	EXTRA[LADDER] = {"name": "Ladder", "color": Color("9a7a4f"), "cross": true}
	EXTRA[BAMBOO] = {"name": "Bamboo", "color": Color("6b9a3d"), "cross": true, "sway": 0.3}
	EXTRA[SNOW_LAYER] = {"name": "Snow Layer", "color": Color("eef3f6"),
		"solid": false, "opaque": false, "shape": "carpet", "hard": 0}
	var glass_tints := [["Red", Color(0.85, 0.2, 0.2, 0.5)],
		["Orange", Color(0.9, 0.55, 0.15, 0.5)], ["Yellow", Color(0.92, 0.85, 0.25, 0.5)],
		["Green", Color(0.3, 0.75, 0.3, 0.5)], ["Blue", Color(0.25, 0.45, 0.9, 0.5)],
		["Purple", Color(0.6, 0.3, 0.85, 0.5)], ["Pink", Color(0.9, 0.55, 0.75, 0.5)],
		["White", Color(0.92, 0.94, 0.97, 0.42)]]
	for gi in glass_tints.size():
		EXTRA[GLASS_RED + gi] = {"name": str(glass_tints[gi][0]) + " Glass",
			"color": glass_tints[gi][1], "solid": true, "opaque": false,
			"translucent": true, "hard": 0}
	EXTRA[LEAVES_DARK] = {"name": "Dark Leaves", "color": Color("2f5a30"),
		"solid": true, "opaque": true, "sway": 0.35, "hard": 0}
	EXTRA[LEAVES_LIGHT] = {"name": "Bright Leaves", "color": Color("7fbb4f"),
		"solid": true, "opaque": true, "sway": 0.35, "hard": 0}
	EXTRA[LEAVES_PINK] = {"name": "Blossom Leaves", "color": Color("e8a7c8"),
		"solid": true, "opaque": true, "sway": 0.35, "hard": 0}
	var carpet_tints := [["Red", Color("c94040")], ["Orange", Color("d97d33")],
		["Yellow", Color("d9c23d")], ["Green", Color("57a04a")],
		["Blue", Color("4a68c9")], ["Purple", Color("8850c9")],
		["Pink", Color("d98cb8")], ["White", Color("e8e8ea")]]
	for ci in carpet_tints.size():
		EXTRA[CARPET_RED + ci] = {"name": str(carpet_tints[ci][0]) + " Carpet",
			"color": carpet_tints[ci][1], "solid": false, "opaque": false,
			"shape": "carpet", "hard": 0}
	EXTRA[CRAFTING_TABLE] = {"name": "Crafting Table", "color": Color("9a6b3f"),
		"top": Color("7a5230"), "solid": true, "opaque": true, "hard": 1}
	EXTRA[CHEST] = {"name": "Chest", "color": Color("a5762f"),
		"top": Color("8a6228"), "solid": true, "opaque": true, "hard": 1}
	EXTRA[FURNACE] = {"name": "Furnace", "color": Color("7e8188"),
		"solid": true, "opaque": true, "hard": 2}
	EXTRA[DOOR_WOOD] = {"name": "Door", "color": Color("a5793f"),
		"solid": true, "opaque": false, "shape": "door", "hard": 1}
	EXTRA[DOOR_IRON] = {"name": "Iron Door", "color": Color("c2c8d2"),
		"solid": true, "opaque": false, "shape": "door", "hard": 2}
	EXTRA[BED] = {"name": "Bed", "color": Color("c94040"),
		"top": Color("e8e8ea"), "solid": true, "opaque": false,
		"shape": "bed", "hard": 1}
	EXTRA[LILY_PAD] = {"name": "Lily Pad", "color": Color("3f7a33"),
		"solid": false, "opaque": false, "shape": "carpet", "hard": 0}
	EXTRA[WARPED_PLANKS] = {"name": "Warped Planks", "color": Color("3a8078"),
		"solid": true, "opaque": true, "hard": 1}
	EXTRA[CRIMSON_PLANKS] = {"name": "Crimson Planks", "color": Color("7e3a56"),
		"solid": true, "opaque": true, "hard": 1}
	EXTRA[MANGROVE_PLANKS] = {"name": "Mangrove Planks", "color": Color("7a3b33"),
		"solid": true, "opaque": true, "hard": 1}
	EXTRA[BAMBOO_BLOCK] = {"name": "Bamboo Block", "color": Color("83973f"),
		"top": Color("b3a94e"), "solid": true, "opaque": true, "hard": 1}
	EXTRA[MAGMA] = {"name": "Magma", "color": Color("5b2c1e"),
		"top": Color("d95f2a"), "solid": true, "opaque": true, "emit": 0.7, "hard": 2}
	EXTRA[WARPED_STEM] = {"name": "Warped Stem", "color": Color("3f6b62"),
		"top": Color("2f4f48"), "solid": true, "opaque": true, "hard": 1}
	var species_mats := [["Spruce", Color("6b4f2e")], ["Birch", Color("c7b77c")],
		["Dark Oak", Color("4a3524")], ["Crimson", Color("7e3a56")],
		["Mangrove", Color("7a3b33")], ["Warped", Color("3a8078")]]
	for sp_i in species_mats.size():
		for f in 4:
			EXTRA[STAIRS_SPRUCE + sp_i * 4 + f] = {
				"name": str(species_mats[sp_i][0]) + " Stairs",
				"color": species_mats[sp_i][1], "solid": true, "opaque": false,
				"shape": "stairs", "hard": 1}
		EXTRA[SLAB_SPRUCE + sp_i] = {"name": str(species_mats[sp_i][0]) + " Slab",
			"color": species_mats[sp_i][1], "solid": true, "opaque": false,
			"shape": "slab", "hard": 1}
		EXTRA[FENCE_SPRUCE + sp_i] = {"name": str(species_mats[sp_i][0]) + " Fence",
			"color": species_mats[sp_i][1], "solid": true, "opaque": false,
			"shape": "fence", "hard": 1}
	EXTRA[PURPUR] = {"name": "Purpur", "color": Color("a678a6"),
		"solid": true, "opaque": true, "hard": 2}
	EXTRA[MYCELIUM] = {"name": "Mycelium", "color": Color("8a6242"),
		"top": Color("7a6d80"), "solid": true, "opaque": true, "hard": 0}
	_build_lookups()

## Flat per-id lookup tables for the mesher's hot loop — dictionary
## lookups per voxel were the whole cost of chunk meshing (measured
## ~245 ms/chunk before, dominated by info() dict traffic).
const SHAPE_IDS := {"": 0, "slab": 1, "carpet": 2, "stairs": 3, "fence": 4,
	"wall": 5, "pane": 6, "door": 7, "bed": 8}
static var LK_OPAQUE := PackedByteArray()
static var LK_CROSS := PackedByteArray()
static var LK_TRANS := PackedByteArray()
static var LK_LIQUID := PackedByteArray()
static var LK_SHAPE := PackedByteArray()
static var LK_COLOR := PackedColorArray()
static var LK_TOP := PackedColorArray()
static var LK_SWAY := PackedFloat32Array()
static var LK_EMIT := PackedFloat32Array()
static var LK_LIGHT := PackedFloat32Array()
static var LK_ROUGH := PackedFloat32Array()
## In-world face patterns the terrain shader draws procedurally
## (0 none · 1 books · 2 crafting grid · 3 chest · 4 furnace · 5 tnt ·
## 6 melon stripes · 7 pumpkin ribs · 8 hay bands · 9 plank grain ·
## 10 brick bond · 11 stone-brick bond · 12 bark · 13 log rings).
static var LK_PATTERN_SIDE := PackedByteArray()
static var LK_PATTERN_TOP := PackedByteArray()

static func _build_lookups() -> void:
	LK_OPAQUE.resize(256)
	LK_CROSS.resize(256)
	LK_TRANS.resize(256)
	LK_LIQUID.resize(256)
	LK_SHAPE.resize(256)
	LK_COLOR.resize(256)
	LK_TOP.resize(256)
	LK_SWAY.resize(256)
	LK_EMIT.resize(256)
	LK_LIGHT.resize(256)
	LK_ROUGH.resize(256)
	LK_PATTERN_SIDE.resize(256)
	LK_PATTERN_TOP.resize(256)
	var side_patterns := {132: 1, CRAFTING_TABLE: 2, CHEST: 3, FURNACE: 4,
		BOOM: 5, 137: 6, PUMPKIN: 7, 138: 8,
		PLANKS: 9, BIRCH_PLANKS: 9, DARK_PLANKS: 9, CHERRY_PLANKS: 9,
		129: 9, 131: 9, 203: 9, 204: 9, 205: 9,
		BRICK: 10, 119: 10, 101: 11, 102: 11, 103: 11, 109: 11, 115: 11,
		LOG: 12, 125: 12, 126: 12, 127: 12, 128: 12, 130: 12, 208: 12, 206: 12}
	var top_patterns := {CRAFTING_TABLE: 2, CHEST: 3, BOOM: 5, 137: 6,
		PUMPKIN: 7, 138: 8, PLANKS: 9, BIRCH_PLANKS: 9, DARK_PLANKS: 9,
		CHERRY_PLANKS: 9, 129: 9, 131: 9, 203: 9, 204: 9, 205: 9,
		BRICK: 10, 119: 10, 101: 11, 102: 11, 103: 11, 109: 11, 115: 11,
		LOG: 13, 125: 13, 126: 13, 127: 13, 128: 13, 130: 13, 208: 13}
	for pid: int in side_patterns.keys():
		LK_PATTERN_SIDE[pid] = side_patterns[pid]
	for pid: int in top_patterns.keys():
		LK_PATTERN_TOP[pid] = top_patterns[pid]
	for id in 256:
		var spec := info(id)
		LK_OPAQUE[id] = 1 if bool(spec.get("opaque", false)) else 0
		LK_CROSS[id] = 1 if bool(spec.get("cross", false)) else 0
		LK_TRANS[id] = 1 if bool(spec.get("translucent", false)) else 0
		LK_LIQUID[id] = 1 if is_liquid(id) else 0
		LK_SHAPE[id] = int(SHAPE_IDS.get(str(spec.get("shape", "")), 0))
		var c: Color = spec.get("color", Color(0, 0, 0, 0))
		LK_COLOR[id] = c
		LK_TOP[id] = spec.get("top", c)
		LK_SWAY[id] = float(spec.get("sway", 0.0))
		LK_EMIT[id] = float(spec.get("emit", 0.0))
		LK_LIGHT[id] = float(spec.get("light", 0.0))
		LK_ROUGH[id] = float(spec.get("rough", 0.0))

## Per-block info, indexed by block id:
##   color: base albedo
##   top: optional distinct top-face color (grass, path, pumpkin lid...)
##   solid: players collide with it
##   opaque: hides neighboring faces (false = translucent or plant)
##   cross: rendered as two crossed quads instead of a cube
##   translucent: rendered in the see-through surface (water/glass/ice)
##   sway: vertex wind animation strength (plants, leaves)
##   emit: emissive energy (lantern glow, campfire, berries pop slightly)
##   light: spawns a real OmniLight3D (energy) — the Forward+ showcase
##   collect: digging it counts as a treasure
##   unbreakable: bedrock
const INFO := {
	AIR: {"name": "Air", "color": Color(0, 0, 0, 0), "solid": false, "opaque": false},
	GRASS: {"name": "Grass", "color": Color("6c9a3f"), "top": Color("7fb84e"), "solid": true, "opaque": true},
	DIRT: {"name": "Dirt", "color": Color("8a6242"), "solid": true, "opaque": true},
	STONE: {"name": "Stone", "color": Color("8d9296"), "solid": true, "opaque": true},
	SAND: {"name": "Sand", "color": Color("e6d29a"), "solid": true, "opaque": true},
	WATER: {"name": "Water", "color": Color(0.18, 0.45, 0.75, 0.62), "solid": false, "opaque": false, "translucent": true},
	LOG: {"name": "Log", "color": Color("6e523a"), "top": Color("a8845f"), "solid": true, "opaque": true},
	LEAVES: {"name": "Leaves", "color": Color("4f8a3d"), "solid": true, "opaque": true, "sway": 0.35},
	PLANKS: {"name": "Planks", "color": Color("b08d5e"), "solid": true, "opaque": true},
	COBBLE: {"name": "Cobble", "color": Color("7a7d80"), "solid": true, "opaque": true},
	SNOW: {"name": "Snow", "color": Color("eef3f6"), "solid": true, "opaque": true},
	FLOWER_RED: {"name": "Poppy", "color": Color("e2574c"), "solid": false,
		"opaque": false, "cross": true, "sway": 1.0, "collect": true},
	FLOWER_YELLOW: {"name": "Buttercup", "color": Color("f5c542"), "solid": false,
		"opaque": false, "cross": true, "sway": 1.0, "collect": true},
	FLOWER_PINK: {"name": "Blossom", "color": Color("ef8fc0"), "solid": false,
		"opaque": false, "cross": true, "sway": 1.0, "collect": true},
	TALL_GRASS: {"name": "Wild Grass", "color": Color("5d8f43"), "solid": false,
		"opaque": false, "cross": true, "sway": 1.0},
	PUMPKIN: {"name": "Pumpkin", "color": Color("dd7d2a"), "top": Color("b8641f"), "solid": true, "opaque": true},
	MUSHROOM: {"name": "Mushroom", "color": Color("d95f4b"), "solid": false,
		"opaque": false, "cross": true, "sway": 0.4, "collect": true},
	LANTERN: {"name": "Lantern", "color": Color("ffd98a"), "solid": true, "opaque": false, "emit": 2.2, "light": 3.2},
	CAMPFIRE: {"name": "Campfire", "color": Color("ff9d45"), "solid": false, "opaque": false, "emit": 2.6, "light": 4.2},
	SAPLING: {"name": "Sapling", "color": Color("70a94e"), "solid": false, "opaque": false, "cross": true, "sway": 0.8},
	BRICK: {"name": "Brick", "color": Color("aa5d49"), "solid": true, "opaque": true},
	GLASS: {"name": "Glass", "color": Color(0.75, 0.87, 0.94, 0.3), "solid": true, "opaque": false, "translucent": true},
	WOOL_RED: {"name": "Red Wool", "color": Color("cc4b4b"), "solid": true, "opaque": true},
	WOOL_ORANGE: {"name": "Orange Wool", "color": Color("e08c3a"), "solid": true, "opaque": true},
	WOOL_YELLOW: {"name": "Yellow Wool", "color": Color("e8c94a"), "solid": true, "opaque": true},
	WOOL_GREEN: {"name": "Green Wool", "color": Color("62a851"), "solid": true, "opaque": true},
	WOOL_BLUE: {"name": "Blue Wool", "color": Color("4a76c9"), "solid": true, "opaque": true},
	WOOL_PURPLE: {"name": "Purple Wool", "color": Color("9a5fc2"), "solid": true, "opaque": true},
	WOOL_WHITE: {"name": "White Wool", "color": Color("e9e6df"), "solid": true, "opaque": true},
	WOOL_BLACK: {"name": "Black Wool", "color": Color("3a3d45"), "solid": true, "opaque": true},
	ICE: {"name": "Ice", "color": Color(0.68, 0.82, 0.94, 0.75), "solid": true, "opaque": false, "translucent": true},
	SHELL: {"name": "Seashell", "color": Color("f2e0d0"), "solid": false, "opaque": false, "cross": true, "collect": true},
	BERRY_BUSH: {"name": "Berry Bush", "color": Color("3f7a38"), "solid": false,
		"opaque": false, "cross": true, "sway": 0.5, "emit": 0.35, "collect": true},
	PATH: {"name": "Path", "color": Color("9c7f52"), "top": Color("b5975f"), "solid": true, "opaque": true},
	BEDROCK: {"name": "Bedrock", "color": Color("4c4c52"), "solid": true, "opaque": true, "unbreakable": true},
	# --- Building families ---
	MARBLE: {"name": "Marble", "color": Color("e8e6e0"), "solid": true, "opaque": true},
	SLATE: {"name": "Slate", "color": Color("4a5568"), "solid": true, "opaque": true},
	SANDSTONE: {"name": "Sandstone", "color": Color("d9c78f"), "top": Color("e3d4a3"), "solid": true, "opaque": true},
	BIRCH_PLANKS: {"name": "Birch Planks", "color": Color("d6c396"), "solid": true, "opaque": true},
	DARK_PLANKS: {"name": "Dark Planks", "color": Color("5d4430"), "solid": true, "opaque": true},
	CHERRY_PLANKS: {"name": "Cherry Planks", "color": Color("d4a0a8"), "solid": true, "opaque": true},
	MOSSY_COBBLE: {"name": "Mossy Cobble", "color": Color("6d7d68"), "solid": true, "opaque": true},
	GOLD: {"name": "Gold", "color": Color("f2c744"), "solid": true, "opaque": true, "emit": 0.25},
	DIAMOND: {"name": "Diamond", "color": Color("7de8e0"), "solid": true, "opaque": true, "emit": 0.25},
	WOOL_PINK: {"name": "Pink Wool", "color": Color("ef9fc8"), "solid": true, "opaque": true},
	WOOL_TEAL: {"name": "Teal Wool", "color": Color("3aa8a0"), "solid": true, "opaque": true},
	WOOL_BROWN: {"name": "Brown Wool", "color": Color("7a5b40"), "solid": true, "opaque": true},
	# --- Glow set ---
	GLOWSTONE: {"name": "Glowstone", "color": Color("ffe08a"), "solid": true, "opaque": false, "emit": 2.4, "light": 3.6},
	CRYSTAL_PINK: {"name": "Pink Crystal", "color": Color(0.95, 0.55,
		0.8, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	CRYSTAL_BLUE: {"name": "Blue Crystal", "color": Color(0.45, 0.7,
		0.98, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	CRYSTAL_GREEN: {"name": "Green Crystal", "color": Color(0.5, 0.95,
		0.6, 0.65), "solid": true, "opaque": false, "translucent": true, "emit": 1.5, "light": 2.0},
	LAVA: {"name": "Glow Goo", "color": Color(1.0, 0.48,
		0.14, 0.85), "solid": false, "opaque": false, "translucent": true, "emit": 1.7, "light": 3.0},
	# --- Fun machines ---
	BOOM: {"name": "Boom Block", "color": Color("d63d2e"), "top": Color("8f2318"),
		"solid": true, "opaque": true, "emit": 0.35},
	FIREWORK: {"name": "Firework", "color": Color("c94fd4"), "top": Color("f2e04a"),
		"solid": true, "opaque": true, "emit": 0.3},
	BOUNCY: {"name": "Bouncy Block", "color": Color(0.5, 0.88,
		0.45, 0.7), "solid": true, "opaque": false, "translucent": true, "emit": 0.2},
	LAUNCHER: {"name": "Launch Pad", "color": Color("8a5fe8"), "top": Color("c9b3ff"),
		"solid": true, "opaque": true, "emit": 0.4},
	NOTE: {"name": "Music Block", "color": Color("e0a63d"), "top": Color("6d4a26"), "solid": true, "opaque": true},
	SPONGE: {"name": "Sponge", "color": Color("d8c94a"), "solid": true, "opaque": true},
	TELEPORT: {"name": "Warp Stone", "color": Color("4de0d4"), "top": Color("aef7f0"),
		"solid": true, "opaque": true, "emit": 0.9, "light": 1.6},
	CONFETTI: {"name": "Party Popper", "color": Color("f2e8f7"), "top": Color("ef9fc8"),
		"solid": true, "opaque": true, "emit": 0.3},
	STEEL: {"name": "Steel", "color": Color("aab4c2"), "top": Color("c4cdd8"), "solid": true, "opaque": true},
	FIRE: {"name": "Fire", "color": Color(1.0, 0.55,
		0.15), "solid": false, "opaque": false, "cross": true, "sway": 1.4, "emit": 2.6, "light": 3.2},
	CHARRED: {"name": "Charred", "color": Color("2e2a26"), "solid": true, "opaque": true},
}

## Weapon interaction tiers:
##   0 fragile (grass, dirt, sand, wool, glass...): pellets break, blasts vaporize
##   1 wood: pellets break, blasts destroy
##   2 stone family: pellet-proof, blasts only bite at close range
##   3 steel: only a DIRECT bazooka hit removes one block
##   4 diamond: weapons can't touch it at all (hands still can)
const WOOD := [LOG, PLANKS, BIRCH_PLANKS, DARK_PLANKS, CHERRY_PLANKS]
const STONY := [STONE, COBBLE, MOSSY_COBBLE, BRICK, MARBLE, SLATE, SANDSTONE, GOLD, PATH, CHARRED]
static func hardness(id: int) -> int:
	if id >= M_STEEL and id < M_STONE:
		return 3
	if id >= M_STONE and id < M_SOIL:
		return 2
	if id >= M_SOIL and id < MAX_BLOCK:
		return 0
	if id > WHEAT_PLANT:
		return int(info(id).get("hard", 0))
	if id == DIAMOND:
		return 4
	if id == STEEL:
		return 3
	if id in STONY:
		return 2
	if id in WOOD:
		return 1
	return 0

## What fire eats. Everything else just lets it gutter out.
static func is_flammable(id: int) -> bool:
	return id in [LOG, LEAVES, PLANKS, BIRCH_PLANKS, DARK_PLANKS, CHERRY_PLANKS,
		TALL_GRASS, FLOWER_RED, FLOWER_YELLOW, FLOWER_PINK, SAPLING, BERRY_BUSH,
		MUSHROOM, SHELL, WOOL_RED, WOOL_ORANGE, WOOL_YELLOW, WOOL_GREEN,
		WOOL_TEAL, WOOL_BLUE, WOOL_PURPLE, WOOL_PINK, WOOL_BROWN, WOOL_WHITE,
		WOOL_BLACK, PUMPKIN] \
		or (id >= M_SOIL and id < M_SNOW) \
		or (id >= FERN and id <= WHEAT_PLANT)  # organic blocks + plants burn

## What the place-hotbar offers, in order: build stuff first, glow stuff,
## then the fun machines. Everything is infinite (creative style) — the cozy
## loop is building, not resource grinding.
const HOTBAR: Array[int] = [
	PLANKS, BIRCH_PLANKS, DARK_PLANKS, CHERRY_PLANKS, LOG,
	COBBLE, MOSSY_COBBLE, STONE, MARBLE, SLATE, BRICK, SANDSTONE, SAND,
	GLASS, ICE, SNOW, GOLD, DIAMOND,
	WOOL_RED, WOOL_ORANGE, WOOL_YELLOW, WOOL_GREEN, WOOL_TEAL, WOOL_BLUE,
	WOOL_PURPLE, WOOL_PINK, WOOL_BROWN, WOOL_WHITE, WOOL_BLACK,
	LANTERN, CAMPFIRE, GLOWSTONE, CRYSTAL_PINK, CRYSTAL_BLUE, CRYSTAL_GREEN, LAVA,
	STEEL, CHARRED, BOOM, FIREWORK, BOUNCY, LAUNCHER, NOTE, SPONGE, TELEPORT, CONFETTI,
	FLOWER_RED, FLOWER_YELLOW, SAPLING,
	M_STEEL, M_STEEL + 1, M_STEEL + 2, M_STEEL + 3, M_STEEL + 4, M_STEEL + 5, M_STEEL + 6, M_STEEL + 7,
	M_STONE, M_STONE + 1, M_STONE + 2, M_STONE + 3, M_STONE + 4, M_STONE + 5, M_STONE + 6, M_STONE + 7,
	M_SOIL, M_SOIL + 1, M_SOIL + 2, M_SOIL + 3, M_SOIL + 4, M_SOIL + 5, M_SOIL + 6, M_SOIL + 7,
	M_SNOW, M_SNOW + 1, M_SNOW + 2, M_SNOW + 3, M_SNOW + 4, M_SNOW + 5, M_SNOW + 6, M_SNOW + 7,
	101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116,
	117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132,
	133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148,
	149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164,
	165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178,
	179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191, 192,
	193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206,
	207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220,
	221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234,
	235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246,
]

## Picker categories (what each tab shows).
static func family_blocks() -> Array:
	var out: Array = []
	for row in [M_STEEL, M_STONE, M_SOIL, M_SNOW]:
		for i in 8:
			out.append(row + i)
	var mc_ids := MC_BLOCKS.keys()
	mc_ids.sort()
	out.append_array(mc_ids)
	out.append_array([STAIRS_WOOD, STAIRS_STONE, STAIRS_BRICK, STAIRS_QUARTZ,
		SLAB_WOOD, SLAB_STONE, SLAB_BRICK, SLAB_QUARTZ,
		FENCE, WALL, GLASS_PANE, TORCH, VINE, LADDER, BAMBOO,
		SNOW_LAYER, GLASS_RED, GLASS_RED + 1, GLASS_RED + 2, GLASS_RED + 3,
		GLASS_RED + 4, GLASS_RED + 5, GLASS_RED + 6, GLASS_RED + 7,
		LEAVES_DARK, LEAVES_LIGHT, LEAVES_PINK])
	return out

## Special = OUR inventions only; everything vanilla lives in the
## Minecraft-style categories below.
## THE SPECIAL BLOCKS, and there are four because the rest were noise.
##
## Gone from the picker: the Launch Pad (a Bouncy Block that went higher —
## now just what a Bouncy Block does), the Music Block, the Sponge (nobody
## ever worked out what it was for), the Firework, the Party Popper, and
## Lava. Their ids stay burned and their behaviour stays in the code: they
## are still what imported Minecraft maps map onto, and an id is wire
## format forever. They simply cannot be chosen any more.
const SPECIAL_BLOCKS := [BOOM, BOUNCY, TELEPORT, TRAP]

## Minecraft-style Build tabs: what each picker page shows.
static func picker_category(cat: String) -> Array:
	var out: Array = []
	match cat:
		"building":
			out = [PLANKS, BIRCH_PLANKS, DARK_PLANKS, CHERRY_PLANKS, 129, 131,
				WARPED_PLANKS, CRIMSON_PLANKS, MANGROVE_PLANKS, BAMBOO_BLOCK,
				LOG, 125, 126, 127, 128, 130, WARPED_STEM,
				COBBLE, MOSSY_COBBLE, STONE, MARBLE, SLATE, BRICK, SANDSTONE,
				101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112,
				113, 114, 115, 116, 117, 119, 121, 132, BEDROCK,
				STEEL, CHARRED, GOLD, DIAMOND, 141, 142, 143, 144, 145, 146]
			for row in [M_STEEL, M_STONE]:
				for i in 8:
					out.append(row + i)
			out.append_array([STAIRS_WOOD, STAIRS_SPRUCE, STAIRS_BIRCH,
				STAIRS_DARK, STAIRS_CRIMSON, STAIRS_MANGROVE, STAIRS_WARPED,
				STAIRS_STONE, STAIRS_BRICK, STAIRS_QUARTZ,
				SLAB_WOOD, SLAB_SPRUCE, SLAB_BIRCH, SLAB_DARK, SLAB_CRIMSON,
				SLAB_MANGROVE, SLAB_WARPED, SLAB_STONE, SLAB_BRICK, SLAB_QUARTZ,
				FENCE, FENCE_SPRUCE, FENCE_BIRCH, FENCE_DARK, FENCE_CRIMSON,
				FENCE_MANGROVE, FENCE_WARPED, WALL, LADDER, PURPUR])
			# ...and everything Nature, Colors and Lights used to be.
			#
			# Three separate tabs for "things you build with" meant four
			# pages to hunt through for one block, and the split never
			# held up: snow and mushrooms were filed under Nature when
			# they are colours to build with, and Lights contained a
			# ladder, a bookshelf, a chest and a bed, which do not glow.
			out.append_array([GRASS, DIRT, PATH, SAND, 124, 118, 120, 122,
				123, SHELL, LILY_PAD, MAGMA, MYCELIUM,
				LEAVES, LEAVES_DARK, LEAVES_LIGHT, LEAVES_PINK, 133,
				SNOW, SNOW_LAYER, ICE, 134, 135,
				PUMPKIN, 136, 137, 138, 139, 140,
				FLOWER_RED, FLOWER_YELLOW, FLOWER_PINK, MUSHROOM, TALL_GRASS,
				SAPLING, BERRY_BUSH, FERN, DEAD_BUSH, CATTAIL, DAISY,
				BLUEBELL, WHEAT_PLANT, VINE, BAMBOO])
			for row in [M_SOIL, M_SNOW]:
				for i in 8:
					out.append(row + i)
			out.append_array([WOOL_WHITE, WOOL_BLACK, WOOL_BROWN, WOOL_RED,
				WOOL_ORANGE, WOOL_YELLOW, WOOL_GREEN, WOOL_TEAL, WOOL_BLUE,
				WOOL_PURPLE, WOOL_PINK, GLASS, GLASS_PANE])
			for i in 8:
				out.append(GLASS_RED + i)
			for i in 8:
				out.append(CARPET_RED + i)
			out.append_array([TORCH, LANTERN, GLOWSTONE, CAMPFIRE, 147, 148,
				CRYSTAL_PINK, CRYSTAL_BLUE, CRYSTAL_GREEN, 132,
				CRAFTING_TABLE, CHEST, FURNACE, DOOR_WOOD, DOOR_IRON, BED])
	return out

## WHAT A TRAP BLOCK SHOULD LOOK LIKE, given what is beside it.
##
## The four LATERAL neighbours only — never what is above or below — so a
## trap laid in a grass floor takes the grass beside it rather than the
## dirt underneath, which is what a floor looks like from where you are
## standing. First solid, opaque neighbour wins; with nothing beside it at
## all it keeps its own placeholder green, which is the honest answer:
## a trap in mid-air was never going to fool anybody.
static func disguise_of(neighbours: Array) -> int:
	for id: int in neighbours:
		if id == TRAP or id == AIR:
			continue
		if is_solid(id) and is_opaque(id) and shape_of(id).is_empty():
			return id
	return TRAP

static func info(id: int) -> Dictionary:
	if id >= M_STEEL:
		return EXTRA.get(id, INFO[AIR])
	return INFO.get(id, INFO[AIR])

static func color_of(id: int) -> Color:
	var i: Dictionary = info(id)
	var c: Color = i.color
	return c

static func top_color_of(id: int) -> Color:
	var i: Dictionary = info(id)
	return i.get("top", i.color)

static func is_solid(id: int) -> bool:
	return bool(info(id).get("solid", false))

static func is_opaque(id: int) -> bool:
	return bool(info(id).get("opaque", false))

static func is_cross(id: int) -> bool:
	return bool(info(id).get("cross", false))

static func is_translucent(id: int) -> bool:
	return bool(info(id).get("translucent", false))

## Swimmable stuff (water and glow goo).
static func is_liquid(id: int) -> bool:
	return id == WATER or id == LAVA

static func is_collectible(id: int) -> bool:
	return bool(info(id).get("collect", false))

static func is_breakable(id: int) -> bool:
	if id == AIR:
		return false
	return not bool(info(id).get("unbreakable", false))

static func sway_of(id: int) -> float:
	return float(info(id).get("sway", 0.0))

static func emit_of(id: int) -> float:
	return float(info(id).get("emit", 0.0))

static func light_of(id: int) -> float:
	return float(info(id).get("light", 0.0))

static func display_name(id: int) -> String:
	return str(info(id).get("name", "?"))

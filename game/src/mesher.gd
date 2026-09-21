class_name Mesher
extends RefCounted
## Turns raw chunk bytes into render surfaces. No textures anywhere: the look
## is vertex colors + per-face shading + baked ambient occlusion + a subtle
## per-position jitter, with the Forward+ pipeline (sun shadows, SSAO, glow,
## fog) doing the rest.
##
## Outputs three surfaces per chunk:
##   opaque  - solid cubes
##   plants  - crossed quads (flowers, grass tufts...), double-sided, swaying
##   trans   - water / glass / ice, translucent
## plus light spec dicts for blocks that cast real light (lantern, campfire).

const SIZE := WorldGen.CHUNK_SIZE
const H := WorldGen.CHUNK_H

## THE GROUND IS A SURFACE, NOT A PILE OF LIDS.
##
## Every place four columns of ground meet is a POINT, and the ground is
## drawn through those points: one piece of skin per column, stretched
## over the four corners it shares with the columns around it. The blocks
## say where the points are and how high; what happens between them is
## the skin's business, and it does not care whether there is a block
## under any particular part of it.
##
## That is the whole idea, and everything below follows from it:
##
##   - A step of ONE level has no vertical face. Both columns read the
##     same height for the corners between them, so the two pieces meet
##     edge to edge and the step is a slope.
##   - A diagonal hillside is ONE PLANE. It used to be a field of little
##     pyramids with holes between them, because a cell with no block in
##     it had no face to draw.
##   - A wall is drawn only where the ground falls TWO levels or more —
##     a cliff, which is the one place a vertical face belongs. There the
##     points stay on the lattice and the blocks are drawn as the blocks
##     they are, so a cliff is square and a cave in its face is open.
##   - Anything standing on the ground — a trunk, a wall, a crate — holds
##     its column's points where the blocks are, and is drawn as a whole
##     box sitting on the skin rather than welded into it.
##
## THE SHAPE IS ONLY A PICTURE. A block is still a whole block to walk on
## and to dig; nothing here moves a block, and collision never hears
## about any of it.
##
## ROUGH is how far a point may fall below where the blocks put it: a
## little per-point noise, so ground the map says is flat is not a plane.
## It is the only knob, and 0.0 leaves the lattice alone.
const ROUGH := 0.3
const SWELL_SALT := 7919

## What counts as GROWN rather than built, and so bends with the ground.
##
## TREE TRUNKS ARE IN IT, and they have to be. A log that kept its corners
## square held the points under it up while the ground a step away fell
## the full roughness, so every tree stood on a little pedestal with the
## earth pulled away around it — read as trees floating over the ground.
##
## LEAVES ARE NOT. A canopy is a loose shell of blocks, and dropping the
## corners of blocks that only touch each other at an edge tears it into
## scraps hanging off the top of a trunk.
## The square twins of these (Blocks.BUILT_TWIN — "Stone Block", "Sand
## Block") are deliberately NOT here: same material, cut square, and what
## a pavement, a kerb, a castle wall or a bridge deck is made of.
const SMOOTH_BLOCKS := [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND,
	Blocks.SANDSTONE, Blocks.SNOW, Blocks.MYCELIUM, Blocks.COBBLE,
	Blocks.CHARRED, Blocks.SLATE, Blocks.MOSSY_COBBLE, Blocks.MAGMA]

## Baked face shading kept subtle - the sun and SSAO do the heavy lifting.
## Per-face shading, BAKED into the vertex colour as a stand-in for the
## sun. Gentler than it was (bottom faces were 0.62): the bake multiplies
## every light, so a ceiling directly over a lamp was drawn at two thirds
## of the brightness of the floor under it, which read as lamps that only
## shone upward. The sun still tells the faces apart; the lamps no longer
## lose on the underside.
const SHADE_TOP := 1.0
const SHADE_BOTTOM := 0.82
const SHADE_X := 0.9
const SHADE_Z := 0.86
static var ao_step := 0.16

## Cross-quad footprint (width, height) per plant so flowers read as flowers
## rather than block-sized billboards.
## Ground cover drawn as Kenney Nature Kit models (chunk_view foliage
## layer) instead of crossed silhouette quads.
const MODEL_PLANTS := {Blocks.TALL_GRASS: 1, Blocks.FERN: 1,
	Blocks.FLOWER_RED: 1, Blocks.FLOWER_YELLOW: 1, Blocks.MUSHROOM: 1,
	Blocks.FLOWER_PINK: 1, Blocks.DAISY: 1, Blocks.BLUEBELL: 1,
	Blocks.CATTAIL: 1, Blocks.WHEAT_PLANT: 1, Blocks.DEAD_BUSH: 1,
	Blocks.BERRY_BUSH: 1, Blocks.BAMBOO: 1}

const CROSS_SIZES := {
	Blocks.FLOWER_RED: Vector2(0.5, 0.7),
	Blocks.FLOWER_YELLOW: Vector2(0.5, 0.65),
	Blocks.FLOWER_PINK: Vector2(0.5, 0.75),
	Blocks.TALL_GRASS: Vector2(0.9, 0.65),
	Blocks.MUSHROOM: Vector2(0.45, 0.5),
	Blocks.SAPLING: Vector2(0.6, 0.9),
	Blocks.SHELL: Vector2(0.4, 0.35),
	Blocks.BERRY_BUSH: Vector2(0.95, 0.9),
	Blocks.FIRE: Vector2(1.0, 1.3),
	Blocks.FERN: Vector2(0.85, 0.5),
	Blocks.DEAD_BUSH: Vector2(0.6, 0.5),
	# A pot plant fills its tub and stands about waist high; the palm is
	# the one in the corner everybody walks round.
	Blocks.OFFICE_PLANT: Vector2(0.85, 0.85),
	Blocks.OFFICE_PALM: Vector2(0.95, 1.35),
	Blocks.CATTAIL: Vector2(0.35, 1.1),
	Blocks.DAISY: Vector2(0.45, 0.5),
	Blocks.BLUEBELL: Vector2(0.4, 0.55),
	Blocks.WHEAT_PLANT: Vector2(0.9, 0.8),
}

## Face table: [normal, u_axis, v_axis, shade]. Vertices are laid out
## (-u,-v) (+u,-v) (+u,+v) (-u,+v) around the face center.
const FACES := [
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), SHADE_TOP],
	[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), SHADE_BOTTOM],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), SHADE_X],
	[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), SHADE_X],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), SHADE_Z],
	[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), SHADE_Z],
]

## Per-corner constants of a cube face, hoisted out of the per-face loop.
const CORNER_SIGNS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1),
	Vector2i(1, 1), Vector2i(-1, 1)]
const CORNER_U: PackedFloat32Array = [0.0, 0.999, 0.999, 0.0]
const CORNER_V: PackedFloat32Array = [1.0, 1.0, 0.0, 0.0]
const QUAD_ORDER: PackedInt32Array = [0, 2, 1, 0, 3, 2]
const QUAD_ORDER_FLIPPED: PackedInt32Array = [1, 3, 2, 1, 0, 3]

var _data: PackedByteArray
var _neighbors: Dictionary  # Vector2i (unit offsets) -> PackedByteArray

## Per-surface accumulation.
## The surfaces a chunk is split into. "roof" is only ever filled on a
## map that has one — see roof_y.
const SURFACES := ["opaque", "plants", "trans", "roof"]
var _verts := {}
var _normals := {}
var _colors := {}
var _uv2s := {}
var _uvs := {}
var _indices := {}
var lights: Array = []
var teleporters: Array = []   # local-space Vector3i of warp stones

func _init() -> void:
	for key in SURFACES:
		_verts[key] = PackedVector3Array()
		_normals[key] = PackedVector3Array()
		_colors[key] = PackedColorArray()
		_uv2s[key] = PackedVector2Array()
		_uvs[key] = PackedVector2Array()
		_indices[key] = PackedInt32Array()

## Block lookup that sees one block into neighboring chunks.
func _block_at(x: int, y: int, z: int) -> int:
	if y < 0 or y >= H:
		return Blocks.AIR
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		return _data.decode_u16(((y * SIZE + z) * SIZE + x) << 1)
	var off := Vector2i(0, 0)
	if x < 0:
		off.x = -1
		x += SIZE
	elif x >= SIZE:
		off.x = 1
		x -= SIZE
	if z < 0:
		off.y = -1
		z += SIZE
	elif z >= SIZE:
		off.y = 1
		z -= SIZE
	var neighbor: PackedByteArray = _neighbors.get(off, PackedByteArray())
	if neighbor.is_empty():
		return Blocks.AIR
	return neighbor.decode_u16(((y * SIZE + z) * SIZE + x) << 1)

## Whether all six neighbours of the block at byte offset `at` in _data are
## opaque. Interior blocks only: every neighbour is in this chunk.
func _buried(at: int) -> bool:
	return _lk_opaque[_data.decode_u16(at - 2)] == 1 \
		and _lk_opaque[_data.decode_u16(at + 2)] == 1 \
		and _lk_opaque[_data.decode_u16(at - SIZE * 2)] == 1 \
		and _lk_opaque[_data.decode_u16(at + SIZE * 2)] == 1 \
		and _lk_opaque[_data.decode_u16(at - SIZE * SIZE * 2)] == 1 \
		and _lk_opaque[_data.decode_u16(at + SIZE * SIZE * 2)] == 1

func _occludes(x: int, y: int, z: int) -> bool:
	return _lk_opaque[_block_at(x, y, z)] == 1

## Build all surfaces for a chunk. cx/cz are only used to seed color jitter
## so the pattern doesn't repeat chunk to chunk.
var _lk_opaque := PackedByteArray()
var _lk_solid := PackedByteArray()
var _lk_smooth := PackedByteArray()
var _lk_cross := PackedByteArray()
## This chunk's origin in world blocks, so the roughness lines up across
## chunk borders. And how far a point may fall: ROUGH, unless a test
## wants the bare lattice on its own.
var _wx0 := 0
var _wz0 := 0
var rough := ROUGH

## THE CUTAWAY LINE. Solid cubes at or above this y go into the "roof"
## surface instead of "opaque", so a camera can decline to draw them —
## see RenderLayers.ROOF. Below zero (every outdoor map) nothing is split
## and the roof surface is never made at all.
var roof_y := -1

func build(data: PackedByteArray, neighbors: Dictionary, cx: int, cz: int,
		p_roof_y := -1) -> Dictionary:
	roof_y = p_roof_y
	_lk_opaque = Blocks.LK_OPAQUE
	_lk_solid = Blocks.LK_SOLID
	_lk_smooth = _smooth_lk
	_lk_cross = Blocks.LK_CROSS
	_data = data
	_neighbors = neighbors
	_wx0 = cx * SIZE
	_wz0 = cz * SIZE
	_point_cache.clear()
	_normal_cache.clear()
	_full_cache.clear()
	# The minimap's block per column, two bytes each like everything else
	# that holds a block id.
	var topmap := PackedByteArray()
	topmap.resize(SIZE * SIZE * 2)
	# How far the ground has dropped under each column's own plants, for
	# the models ChunkView plants (see _ground_drop). Written as the
	# columns are walked, so it costs nothing to carry.
	var roots := PackedFloat32Array()
	roots.resize(SIZE * SIZE)
	for y in H:
		# Whole-slab air check runs in C++ — skips most of the sky instantly.
		var slab_off := y * SIZE * SIZE * 2
		var slab_bytes := SIZE * SIZE * 2
		if _data.slice(slab_off, slab_off + slab_bytes).count(0) == slab_bytes:
			continue
		for z in SIZE:
			for x in SIZE:
				var block := _data.decode_u16(((y * SIZE + z) * SIZE + x) << 1)
				if block == Blocks.AIR:
					continue
				topmap.encode_u16((z * SIZE + x) << 1, block)
				if Blocks.LK_CROSS[block] == 1:
					if not MODEL_PLANTS.has(block):
						_add_cross(block, x, y, z, cx, cz)
					else:
						roots[z * SIZE + x] = _ground_drop(x, y, z)
					continue
				var solid_key := "roof" if roof_y >= 0 and y >= roof_y else "opaque"
				var shape := int(Blocks.LK_SHAPE[block])
				if shape != 0:
					_add_shape(block, shape, x, y, z, cx, cz, solid_key)
					continue
				if Blocks.LK_TRANS[block] == 1:
					_add_cube(block, x, y, z, cx, cz, "trans")
					# The crystals are translucent AND lit, and only the
					# opaque pass used to make lights: a cave full of them
					# glowed on their own faces and lit nothing.
					var glow := Blocks.LK_LIGHT[block]
					if glow > 0.0:
						lights.append({
							"pos": Vector3(x + 0.5, y + 0.6, z + 0.5),
							"energy": glow,
							"color": Blocks.LK_COLOR[block],
							"flicker": false,
						})
					continue
				# THE TRAP BLOCK WEARS ITS NEIGHBOURS. Drawn with a
				# borrowed id so every face is coloured, jittered and
				# shaded as whatever is beside it — a trap in a grass
				# floor IS grass to look at. Only the drawing id changes;
				# `block` stays TRAP below, or a trap disguised as a warp
				# stone would start teleporting people.
				# BURIED: all six neighbours opaque means _add_cube would
				# cull every face, and the block above being solid means it
				# is not shaped ground either. Most of a chunk is buried
				# ground, so skipping the call (its jitter hash, six face
				# lookups, the smoothing test) is most of the build. Its
				# lamp and warp stone still count.
				if x > 0 and x < SIZE - 1 and z > 0 and z < SIZE - 1 \
						and y > 0 and y < H - 1 \
						and _buried(((y * SIZE + z) * SIZE + x) << 1):
					if block == Blocks.TELEPORT:
						teleporters.append(Vector3i(x, y, z))
					var buried_light := Blocks.LK_LIGHT[block]
					if buried_light > 0.0:
						lights.append({
							"pos": Vector3(x + 0.5, y + 0.6, z + 0.5),
							"energy": buried_light,
							"color": Blocks.LK_COLOR[block],
							"flicker": block == Blocks.CAMPFIRE or block == Blocks.FIRE,
						})
					continue
				var draw := block
				if block == Blocks.TRAP:
					draw = Blocks.disguise_of([
						_block_at(x - 1, y, z), _block_at(x + 1, y, z),
						_block_at(x, y, z - 1), _block_at(x, y, z + 1)])
				# GROUND IS DRAWN AS SURFACE, everything else as the box
				# it is. The same six faces either way, culled the same
				# way; the only difference is whether the corners of
				# those faces are the lattice or the points.
				if _lk_smooth[draw] == 1:
					_add_ground(draw, x, y, z, cx, cz, solid_key)
				else:
					_add_cube(draw, x, y, z, cx, cz, solid_key)
				if block == Blocks.TELEPORT:
					teleporters.append(Vector3i(x, y, z))
				var light := Blocks.LK_LIGHT[block]
				if light > 0.0:
					lights.append({
						"pos": Vector3(x + 0.5, y + 0.6, z + 0.5),
						"energy": light,
						"color": Blocks.LK_COLOR[block],
						"flicker": block == Blocks.CAMPFIRE or block == Blocks.FIRE,
					})
	var result := {}
	for key in SURFACES:
		if _indices[key].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts[key]
		if _uvs[key].size() == _verts[key].size():
			arrays[Mesh.ARRAY_TEX_UV] = _uvs[key]
		arrays[Mesh.ARRAY_NORMAL] = _normals[key]
		arrays[Mesh.ARRAY_COLOR] = _colors[key]
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2s[key]
		arrays[Mesh.ARRAY_INDEX] = _indices[key]
		result[key] = arrays
	result["lights"] = _merged(lights)
	result["teleporters"] = teleporters
	result["topmap"] = topmap
	result["roots"] = roots
	return result

func _jitter(x: int, y: int, z: int, cx: int, cz: int, rough := 0.0) -> float:
	var amp := 0.09 * (1.0 + rough)
	return 1.0 - amp * 0.6 + amp * WorldGen.hash01(cx * SIZE + x, cz * SIZE + z, y * 31)

## SMOOTH_BLOCKS as a table by id: `in` on the array was a linear search,
## run for every solid block and again for every corner test.
##
## Built ONCE, when the class loads, and never touched again. Filling it
## on first use instead was a race: chunks are meshed on several worker
## threads, and two of them arriving together had one resizing the array
## while the other wrote into it — an out-of-bounds write on a good day.
static var _smooth_lk: PackedByteArray = _build_smooth_lk()
static func _build_smooth_lk() -> PackedByteArray:
	var table := PackedByteArray()
	table.resize(Blocks.ID_COUNT)
	for id: int in SMOOTH_BLOCKS:
		table[id] = 1
	return table

# ---- the ground's surface ------------------------------------------------
#
## THE GROUND IS A SURFACE, AND IT IS A SURFACE IN THREE DIMENSIONS.
##
## Drawing a face per block is what makes a world of boxes. A step of one
## level leaves the side of a block standing in it. A hillside climbing
## diagonally comes out as a field of little pyramids with holes between
## them, because a cell with no block in it has no face to draw. And the
## inside of anything you dig is a heap of cubes.
##
## So the blocks are not drawn. What is drawn is the boundary between
## MATTER and NOTHING, and the blocks only say where that boundary runs.
## Every place on the lattice it passes through gets ONE POINT, and every
## block face with matter on one side and nothing on the other becomes a
## quad through the four points at its corners.
##
## Two things decide where a point goes, and between them they give the
## whole shape:
##
##   HOW FULL THE GROUND IS THERE — of the eight blocks meeting at the
##   point, how many have matter in them (_fullness). A block on its own
##   is all or nothing, and a surface pulled out of all-or-nothing can
##   only cut corners off: a step comes out as a little bevel and every
##   contour on a hillside reads as a hard ridge. Counting the blocks
##   AROUND a point instead gives a number that changes gradually where
##   the ground does, and the surface is simply where it passes a half.
##
##   IT NEVER LEAVES THE LINE BETWEEN ITSELF AND ITS NEIGHBOUR. A point
##   slides along one axis only — whichever the fullness is changing
##   fastest along — and only as far as the place where the half falls
##   between it and the next point that way (_point, _crossing). That
##   neighbour reads the same two numbers and stops at the same place,
##   so the two of them MEET, which is exactly what a ramp is; and
##   neither leaves the block between them, so neither can pass the
##   other and nothing can fold.
##
##   Letting points chase the surface freely in three dimensions is what
##   tore the first attempt at this apart: either side of a crater wall
##   the point above slid down-and-back while the point below slid
##   up-and-forward, they swapped places, and the face between them
##   folded inside out.
##
## What comes out of those two rules, with no case in the code for any of
## it: flat ground stays flat and exactly where the blocks are; a step of
## one level becomes a ramp two columns wide with its middle exactly
## halfway; a cliff face stays a flat vertical wall with its lip and its
## foot rounded; and it works in EVERY DIRECTION, so the inside of a hole
## you dug, the roof of a cave and the underside of an overhang are the
## same smooth surface as the hillside above them.
##
## IT CANNOT LEAK. Every quad is one block face, and two quads meeting
## along a block edge are built from the same two points, so the surface
## is closed wherever the blocks are.
##
## WHAT BENDS IS A PROPERTY OF THE MATERIAL: see SMOOTH_BLOCKS, and
## Blocks.BUILT_TWIN for the square twins of the ones that are also built
## with. Everything built keeps its corners and is drawn as the box it
## is, and a point that a built block touches does not move at all — so
## the ground meets a floor somebody laid exactly along its edge.

## Is there matter of any kind in this block? Anything solid, and
## anything opaque that is not solid, which is the trap block wearing the
## floor's face: the surface has to stop at those too, or it would be
## drawn straight through one.
func _filled(x: int, y: int, z: int) -> bool:
	var b := _block_at(x, y, z)
	return _lk_solid[b] == 1 or _lk_opaque[b] == 1

## Points and fullnesses are asked for over and over — four points per
## block face, each reading seven fullnesses, and every face beside it
## asking for the same ones — so each is worked out once per chunk.
## Keyed by the lattice point; there is nothing else they depend on.
var _point_cache: Dictionary = {}
var _normal_cache: Dictionary = {}
var _full_cache: Dictionary = {}
## How many points this build actually worked out, as opposed to looked
## up. Read by tests/mesh_watertight.gd, which is where the cache is kept
## honest: without a bound on this nothing notices when a change starts
## asking for the same point over and over again.
var corners_worked := 0

## Room for two rings of points either side of the chunk: a point reads
## how full its neighbours are, and each of those reads the blocks around
## itself, so the answer depends on blocks two out and no further. That
## is what makes two chunks agree about a point on their border without
## either of them seeing the other's workings.
const POINT_KEYS := SIZE + 6

func _point_key(x: int, y: int, z: int) -> int:
	return ((y * POINT_KEYS) + z + 2) * POINT_KEYS + x + 2

## Does anything BUILT meet this point? Then it does not move: the ground
## has to meet the flat square faces of a plank, a pane, a trap or a
## crate exactly, and a point that had smoothed away from one would leave
## a slot down the join or set it standing over a dip.
func _square_at(x: int, y: int, z: int) -> bool:
	for dx: int in [-1, 0]:
		for dy: int in [-1, 0]:
			for dz: int in [-1, 0]:
				var b := _block_at(x + dx, y + dy, z + dz)
				if _lk_smooth[b] != 1 \
						and (_lk_solid[b] == 1 or _lk_opaque[b] == 1):
					return true
	return false

## HOW FULL THE GROUND IS AT THIS POINT: how many of the eight blocks
## meeting here have matter in them, out of eight. See the note above —
## this is the number the whole surface is cut out of.
func _fullness(x: int, y: int, z: int) -> float:
	var key := _point_key(x, y, z)
	var hit: Variant = _full_cache.get(key)
	if hit != null:
		return hit
	var count := 0
	for dx: int in [-1, 0]:
		for dy: int in [-1, 0]:
			for dz: int in [-1, 0]:
				var b := _block_at(x + dx, y + dy, z + dz)
				if _lk_solid[b] == 1 or _lk_opaque[b] == 1:
					count += 1
	# THE ROUGHNESS IS IN THE FIELD, not in the points.
	#
	# A little noise on how full the ground is here, which moves the
	# surface rather than moving a point off it. Every rule below reads
	# this one number, so a roughened surface is still a surface: the two
	# ends of a line read the same two fullnesses and still work out the
	# same crossing, and a step still closes exactly. Nudging the points
	# instead — which is what this replaced — reopened every closed step
	# by a hair, and then every attempt to bound the nudge stopped the
	# roughness doing anything at all.
	#
	# It works underground too, because nothing about it is vertical.
	var value := float(count) * 0.125 \
		+ rough * ROUGH_FIELD * (_swell(x, y, z) - 0.5)
	_full_cache[key] = value
	return value

## How much of the fullness the roughness may swing, at rough = 1. An
## eighth is one block's worth of the eight around a point, so this is a
## fraction of a block of earth appearing and disappearing.
const ROUGH_FIELD := 0.12

## WHERE THE SURFACE PASSES THROUGH THIS POINT: along one axis, as far
## as the half falls between this point and the next one that way. See
## the note at the top of the file, and _crossing.
func _point(x: int, y: int, z: int) -> Vector3:
	var key := _point_key(x, y, z)
	var hit: Variant = _point_cache.get(key)
	if hit != null:
		return hit
	corners_worked += 1
	var here := Vector3(x, y, z)
	if _square_at(x, y, z):
		_point_cache[key] = here
		_normal_cache[key] = Vector3.UP
		return here
	# Which way the ground gets fuller: into it. Both blocks sharing a
	# point work this out the same, so the light runs across the surface
	# instead of stopping at every triangle.
	var slope := Vector3(
		_fullness(x + 1, y, z) - _fullness(x - 1, y, z),
		_fullness(x, y + 1, z) - _fullness(x, y - 1, z),
		_fullness(x, y, z + 1) - _fullness(x, y, z - 1)) * 0.5
	var out := -slope.normalized() if slope.length_squared() > 0.0 else Vector3.UP
	_normal_cache[key] = out
	# NOT "and give up if the ground is level along it". The slope here is
	# a central difference — what is on one side against what is on the
	# other — and in a dip or on a ridge those are the same, so it reads
	# level when the surface plainly crosses. Points in that position
	# stayed exactly where the blocks put them while everything around
	# them slid up to a block away, which tore every steep hillside into
	# spikes. _crossing looks at the two sides separately and comes back
	# with nothing when there is really nothing.
	# UP AND DOWN, AND ONLY UP AND DOWN.
	#
	# A point slides vertically to find the surface, never sideways. That
	# sounds like a restriction and is the opposite: it is what lets this
	# work everywhere. The surface over a hill, the floor of a cave, the
	# roof of one and the bottom of an overhang are all things you can
	# find by moving up or down, and a point sitting on any of them finds
	# its own — nothing here asks which of those it is on, or what is
	# happening three blocks below it.
	#
	# What it leaves alone is the one thing that should be left alone: a
	# wall. A near-vertical face cannot be found by moving up and down,
	# so its points stay where the blocks put them and it stays flat and
	# square — which is what a cliff is, and what was asked for. Its lip
	# and its foot still round off, because those points belong to the
	# ground above and below it as well.
	#
	# Letting a point pick whichever direction the ground was changing
	# fastest along is what shattered the islands. On a steep flank that
	# direction is sideways, neighbouring points disagreed about which
	# sideways, and the hillside came apart into spikes.
	var axis := 1
	# WHERE THE HALF FALLS BETWEEN THIS POINT AND THE NEXT ONE.
	#
	# The point does not go looking for the surface on its own; it takes
	# the one step to the neighbour it is heading for and asks where,
	# between the two of them, the ground stops being more than half
	# full. Straight-line reading of two numbers, which is the oldest
	# trick there is for this.
	#
	# What it buys is that THE NEIGHBOUR WORKS OUT THE SAME PLACE. Both
	# points read the same two fullnesses and land on the same spot, so
	# every step of one level closes exactly instead of leaving a
	# hairline of vertical face — and neither can pass the other, because
	# neither ever leaves the block between them. Chasing the surface
	# independently and clipping the result at half a block, which is
	# what this replaced, left one point clipped and the one beside it
	# not, and even ground came out as a washboard.
	var mine := _fullness(x, y, z)
	# The roughness wobbles WHERE THE HALF IS, not where the point is:
	# one number for the whole line the two points share, so they still
	# agree about it. One per point and they disagree by a hair, which is
	# that hairline of vertical face again.
	var value := here
	var step := _crossing(x, y, z, axis, mine)
	if step != 0.0:
		value[axis] += snappedf(step, POINT_GRID)
	_point_cache[key] = value
	return value

## How far up or down the half falls, and which way.
##
## ONLY TOWARD A NEIGHBOUR THE HALF IS ACTUALLY BETWEEN. One of the two
## is more than half full and the other less, and the surface is
## somewhere on the line between them — that is the only case there is
## anything to find. Heading off toward a neighbour on the same side of
## the half as this point is chasing a surface that is not there, and it
## sent points a whole block into open air.
##
## If both ways straddle, the ground here is one block thick; the point
## goes to the nearer face, which is the one it is part of.
func _crossing(x: int, y: int, z: int, axis: int, mine: float) -> float:
	var best := 0.0
	var found := false
	for way: int in [1, -1]:
		var theirs := _fullness(x + (way if axis == 0 else 0),
			y + (way if axis == 1 else 0), z + (way if axis == 2 else 0))
		# Straddling: one side of the half each, either way round.
		if (mine - HALF_FULL) * (theirs - HALF_FULL) > 0.0:
			continue
		if absf(mine - theirs) < 0.0001:
			continue
		# GO TO THE CROSSING — unless the crossing is all the way over
		# at the other point, in which case that point is the surface
		# here and this one stays where the blocks put it.
		#
		# That one line is the difference between a smooth hillside and a
		# shattered one. A hillside rising half a level per column puts
		# the crossing three quarters of the way along, and BOTH points
		# have to be allowed to reach it or the quarter-block riser
		# between them survives as a hard ridge — a whole hillside of
		# them, running across the slope. On the steep flank of an island
		# the crossing instead lands exactly on the neighbour, and a
		# point let through to it is dragged a full block: three points
		# stack up in one column, the risers between them crush to
		# nothing, and every quad around them stretches into a spike.
		#
		# Both ends of a line work out the same crossing, so they agree
		# about this too: either both go to it and meet, or the far one
		# gives up and the near one arrives.
		var reach := (mine - HALF_FULL) / (mine - theirs)
		if reach < 0.0 or reach > CROSS_LIMIT:
			continue
		var t := float(way) * reach
		if not found or absf(t) < absf(best):
			best = t
			found = true
	return best

## The surface is where the ground stops being more than half full.
const HALF_FULL := 0.5

## How far along a line a point will chase the crossing. Past this the
## crossing belongs to the point at the other end. Above three quarters,
## because a hillside rising half a level per column needs exactly that;
## below one, because at one the crossing IS the other point.
const CROSS_LIMIT := 0.9

## A point lands on a multiple of 1/1024 of a block, which is not
## fussiness: it is what makes two chunks agree about a point on their
## border EXACTLY.
##
## A vertex is held in chunk-local coordinates and 32-bit, so the chunk
## to the west holds a point as 16.0385 and the chunk to the east holds
## the same place as 0.0385. The western one has four more digits in
## front of the point and so four fewer behind it, and the two come out
## about a millionth of a block apart — invisible, and enough that the
## two pieces of ground are not technically the same edge, which is a
## hole as far as anything counting them is concerned. A multiple of
## 1/1024 survives the trip exactly, in either frame.
const POINT_GRID := 1.0 / 1024.0

## Which way the ground faces at this point — see _point, which works it
## out on the way past.
func _point_normal(x: int, y: int, z: int) -> Vector3:
	var key := _point_key(x, y, z)
	if not _normal_cache.has(key):
		_point(x, y, z)
	return _normal_cache[key]

## Would folding this way leave one of the two halves with no area in
## it? See where it is called.
func _splinter(points: PackedVector3Array, through_02: bool) -> bool:
	var a: int = 0 if through_02 else 1
	var b: int = 2 if through_02 else 3
	var c: int = 1 if through_02 else 2
	var d: int = 3 if through_02 else 0
	var span := points[b] - points[a]
	return span.cross(points[c] - points[a]).length_squared() < SPLINTER \
		or span.cross(points[d] - points[a]).length_squared() < SPLINTER

## A ten-thousandth of a block square, either side. Below that a triangle
## is a line with vertices sitting on it.
const SPLINTER := 1e-8

## ONE BLOCK OF GROUND'S SHARE OF THE SURFACE. A quad for each of its
## faces that has nothing on the other side, drawn through the four
## POINTS at that face's corners rather than the corners themselves —
## which is the only difference between this and _add_cube, and the whole
## of what makes the ground ground.
func _add_ground(block: int, x: int, y: int, z: int, cx: int, cz: int,
		key: String) -> void:
	var jitter := _jitter(x, y, z, cx, cz, Blocks.LK_ROUGH[block])
	var emit := Blocks.LK_EMIT[block]
	var base_color := Blocks.LK_COLOR[block]
	var top_color := Blocks.LK_TOP[block]
	for face_index in 6:
		var face: Array = FACES[face_index]
		var n: Vector3i = face[0]
		if _filled(x + n.x, y + n.y, z + n.z):
			continue
		var u: Vector3i = face[1]
		var v: Vector3i = face[2]
		var shade: float = face[3]
		var colour := top_color if n.y == 1 else base_color
		var centre := Vector3(x, y, z) + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		for i in 4:
			var cs: Vector2i = CORNER_SIGNS[i]
			var corner := centre + Vector3(u) * (0.5 * cs.x) + Vector3(v) * (0.5 * cs.y)
			var px := roundi(corner.x)
			var py := roundi(corner.y)
			var pz := roundi(corner.z)
			points.append(_point(px, py, pz))
			normals.append(_point_normal(px, py, pz))
		# Fold along the diagonal whose two points are CLOSEST together:
		# the flattest line across the quad, and so the smallest crease.
		# It follows the ground, turning as the ground turns, rather than
		# ruling the same way everywhere.
		var flat := points[0].distance_squared_to(points[2]) \
			<= points[1].distance_squared_to(points[3])
		# ...unless folding that way leaves a triangle with no area in
		# it. Points slide until they MEET — that is what a ramp is — so
		# a quad can come out with one corner sitting exactly on the line
		# between two others, and a fold through that corner splits it
		# into a real triangle and a splinter. The splinter draws nothing
		# and its three edges match nothing, which is a hole with no
		# width: invisible, and still a hole.
		if _splinter(points, flat):
			flat = not flat
		var tris: Array = [[0, 1, 2], [0, 2, 3]] if flat else [[1, 2, 3], [1, 3, 0]]
		for t: Array in tris:
			_tri(key, [points[t[0]], points[t[1]], points[t[2]]], Vector3(n),
				[colour, colour, colour], shade * jitter, emit,
				[normals[t[0]], normals[t[1]], normals[t[2]]])

## How much of the drop this corner takes, 0 .. 1. One hash of where the
## corner is: its own number, unrelated to the corners beside it, which
## is the whole point.
func _swell(vx: int, wy: int, vz: int) -> float:
	return WorldGen.hash01((_wx0 + vx) * 31 + wy, (_wz0 + vz) * 17 - wy, SWELL_SALT)

## Sides 0 N, 1 E, 2 S, 3 W; each runs between two corners, clockwise
## seen from above: N is NW→NE, E is NE→SE, S is SE→SW, W is SW→NW.
const SIDE_CORNERS := [[0, 1], [1, 2], [2, 3], [3, 0]]
const SIDE_STEP := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CORNER_XZ := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

## LAMPS CLOSE TOGETHER BECOME ONE, and the strongest come first. A dense
## floor of glowstone used to keep the first lamps in walking order — all
## along one side of a hall, the rest dark, which read as the light dying
## as you walked across the room. Merging keeps every chunk's lamp count
## sane and each survivor reaches further; which ones are actually lit at
## any moment is decided globally afterwards — see chunk_view.light_cap.
## What a lit screen reads as, on the one face of a monitor that is one.
const SCREEN_COLOR := Color(0.40, 0.58, 0.76)

const LAMP_MERGE := 7.0
func _merged(lights: Array) -> Array:
	lights.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.energy) > float(b.energy))
	var out: Array = []
	for spec: Dictionary in lights:
		var joined := false
		for kept: Dictionary in out:
			if (kept.pos as Vector3).distance_to(spec.pos) <= LAMP_MERGE:
				kept.energy = minf(float(kept.energy) + float(spec.energy) * 0.5,
					float(kept.energy) * 1.8)
				joined = true
				break
		if not joined:
			out.append(spec)
	return out

## One triangle with a colour per vertex, wound clockwise as seen from
## `normal`'s side, which is the side Godot draws.
## `normals` gives a normal per point, for a surface that should be lit as
## one piece rather than as facets; leave it empty and all three share
## `normal`.
func _tri(key: String, pts: Array, normal: Vector3, cols: Array, brightness: float,
		emit: float, normals: Array = []) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var cb: Color = cols[1]
	var cc: Color = cols[2]
	var na: Vector3 = normals[0] if normals.size() == 3 else normal
	var nb: Vector3 = normals[1] if normals.size() == 3 else normal
	var nc: Vector3 = normals[2] if normals.size() == 3 else normal
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
		var tn := nb
		nb = nc
		nc = tn
	var start: int = _verts[key].size()
	var i := 0
	for pair: Array in [[a, cols[0], na], [b, cb, nb], [c, cc, nc]]:
		var color: Color = pair[1]
		_verts[key].append(pair[0])
		_normals[key].append(pair[2])
		_uvs[key].append(Vector2(0, 0))
		_colors[key].append(Color(color.r * brightness, color.g * brightness, color.b * brightness, color.a))
		_uv2s[key].append(Vector2(0.0, emit))
		i += 1
	_indices[key].append_array([start, start + 1, start + 2])

func _add_cube(block: int, x: int, y: int, z: int, cx: int, cz: int,
		key: String) -> void:
	var base_color := Blocks.LK_COLOR[block]
	var top_color := Blocks.LK_TOP[block]
	var jitter := _jitter(x, y, z, cx, cz, Blocks.LK_ROUGH[block])
	var sway := Blocks.LK_SWAY[block]
	var emit := Blocks.LK_EMIT[block]
	var translucent := key == "trans"
	var is_liquid := Blocks.LK_LIQUID[block] == 1
	# Liquids drop their surface a bit below the block top, like Minecraft.
	var top_y := 0.875 if is_liquid and _block_at(x, y + 1, z) != block else 1.0
	# The surface's arrays once, not a dictionary lookup per append.
	# Packed arrays are shared, so these ARE the surface's arrays.
	var verts: PackedVector3Array = _verts[key]
	var normals: PackedVector3Array = _normals[key]
	var colors: PackedColorArray = _colors[key]
	var uvs: PackedVector2Array = _uvs[key]
	var uv2s: PackedVector2Array = _uv2s[key]
	var indices: PackedInt32Array = _indices[key]
	# Everything a face samples (its neighbour and the AO ring around it)
	# is within one block of this one; away from the chunk's edges that is
	# all in _data, read directly instead of through _block_at.
	var interior := x > 0 and x < SIZE - 1 and z > 0 and z < SIZE - 1 \
		and y > 0 and y < H - 1
	var here := (y * SIZE + z) * SIZE + x

	for face_index in 6:
		var face: Array = FACES[face_index]
		var n: Vector3i = face[0]
		var ahead := here + (n.y * SIZE + n.z) * SIZE + n.x
		var neighbor := _data.decode_u16(ahead << 1) if interior \
			else _block_at(x + n.x, y + n.y, z + n.z)
		if translucent:
			# Translucent faces show against AIR only — never against the
			# same material (no internal water walls), never against an
			# opaque block, and never against a plant.
			#
			# A PLANT USED TO COUNT AS AIR HERE, and that is what put a
			# blue box around every piece of seaweed. A plant standing in
			# water is a cell that is not water, so all six neighbouring
			# water blocks drew a face pointing at it — a complete
			# water-skinned cube around the plant, which read as the plant
			# being in a little air pocket at the bottom of the sea. Most
			# obvious in Isles, which is mostly sea.
			#
			# Water simply carries on through it now. The plant's own
			# crossed quads still draw, so it is a weed in the water
			# rather than a weed in a box.
			if neighbor == block or Blocks.LK_OPAQUE[neighbor] == 1:
				continue
			if Blocks.LK_CROSS[neighbor] == 1:
				continue
			if is_liquid and neighbor == Blocks.ICE:
				continue
		else:
			if Blocks.LK_OPAQUE[neighbor] == 1:
				continue
		var u: Vector3i = face[1]
		var v: Vector3i = face[2]
		var shade: float = face[3]
		var color := top_color if n.y == 1 else base_color
		var origin := Vector3(x, y, z)
		var center := origin + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5
		var half_u := Vector3(u) * 0.5
		var half_v := Vector3(v) * 0.5

		# Ambient occlusion per corner (0 open .. 3 boxed in).
		var ao := PackedFloat32Array([0, 0, 0, 0])
		if not translucent and interior:
			var du := (u.y * SIZE + u.z) * SIZE + u.x
			var dv := (v.y * SIZE + v.z) * SIZE + v.x
			for i in 4:
				var cs: Vector2i = CORNER_SIGNS[i]
				var s1 := _lk_opaque[_data.decode_u16((ahead + du * cs.x) << 1)] == 1
				var s2 := _lk_opaque[_data.decode_u16((ahead + dv * cs.y) << 1)] == 1
				var c := _lk_opaque[_data.decode_u16((ahead + du * cs.x + dv * cs.y) << 1)] == 1
				ao[i] = 3.0 if (s1 and s2) else float(int(s1) + int(s2) + int(c))
		elif not translucent:
			for i in 4:
				var cs: Vector2i = CORNER_SIGNS[i]
				var s1 := _occludes(x + n.x + u.x * cs.x, y + n.y + u.y * cs.x, z + n.z + u.z * cs.x)
				var s2 := _occludes(x + n.x + v.x * cs.y, y + n.y + v.y * cs.y, z + n.z + v.z * cs.y)
				var c := _occludes(x + n.x + u.x * cs.x + v.x * cs.y,
					y + n.y + u.y * cs.x + v.y * cs.y, z + n.z + u.z * cs.x + v.z * cs.y)
				ao[i] = 3.0 if (s1 and s2) else float(int(s1) + int(s2) + int(c))

		var start: int = verts.size()
		var pattern := float(Blocks.LK_PATTERN_TOP[block] if n.y != 0
			else Blocks.LK_PATTERN_SIDE[block])
		var normal := Vector3(n)
		# Leaves sway everywhere; liquids wave only on their surface.
		var vertex_sway := sway
		if is_liquid:
			vertex_sway = 1.0 if n.y == 1 else 0.0
		var uv2 := Vector2(vertex_sway, emit)
		for i in 4:
			var cs: Vector2i = CORNER_SIGNS[i]
			var vert := center + half_u * float(cs.x) + half_v * float(cs.y)
			if top_y != 1.0 and vert.y > y + top_y:
				vert.y = y + top_y
			verts.append(vert)
			normals.append(normal)
			uvs.append(Vector2(pattern + CORNER_U[i], CORNER_V[i]))
			var brightness := shade * jitter * (1.0 - ao_step * ao[i])
			colors.append(Color(color.r * brightness, color.g * brightness,
				color.b * brightness, color.a))
			uv2s.append(uv2)
		# WHICH WAY THE QUAD FOLDS: along the AO gradient, which kills the
		# classic voxel artefact where a corner's shadow bends the wrong
		# way across the diagonal. Godot front faces wind clockwise.
		var order: PackedInt32Array = QUAD_ORDER \
			if ao[0] + ao[2] <= ao[1] + ao[3] else QUAD_ORDER_FLIPPED
		for index in order:
			indices.append(start + index)

## Shaped blocks: a list of sub-boxes per shape, every face emitted (no
## culling/AO — these are small and partial, overdraw is negligible).
## Does a fence/wall/pane arm reach toward this neighbor? (Shapes are the
## Blocks.SHAPE_IDS ints: 1 slab, 2 carpet, 3 stairs, 4 fence, 5 wall,
## 6 pane, 7 door, 8 bed.)
func _shape_connects(shape: int, nx: int, ny: int, nz: int) -> bool:
	var n := _block_at(nx, ny, nz)
	if n <= 0:
		return false
	var n_shape := int(Blocks.LK_SHAPE[n])
	if shape == 6:
		return n_shape == 6 or Blocks.LK_OPAQUE[n] == 1
	if n_shape == 4 or n_shape == 5:
		return true
	return Blocks.LK_OPAQUE[n] == 1

## Turn one box from the canonical facing (north, -Z) into `facing`, a
## quarter turn about the middle of the cell each step. Written once here
## rather than four times per shape in the match below: the stairs above
## spell their four cases out and that was already the longest arm of it.
static func _turn(bmin: Vector3, bmax: Vector3, facing: int) -> Array:
	match posmod(facing, 4):
		1:
			return [Vector3(1.0 - bmax.z, bmin.y, bmin.x),
				Vector3(1.0 - bmin.z, bmax.y, bmax.x)]
		2:
			return [Vector3(1.0 - bmax.x, bmin.y, 1.0 - bmax.z),
				Vector3(1.0 - bmin.x, bmax.y, 1.0 - bmin.z)]
		3:
			return [Vector3(bmin.z, bmin.y, 1.0 - bmax.x),
				Vector3(bmax.z, bmax.y, 1.0 - bmin.x)]
	return [bmin, bmax]

## Every box of a turnable block, put the way round the block is.
##
## A FACING IS WHERE THE FRONT POINTS. The canonical boxes below are
## written with the back at low Z and the front looking down +Z, which is
## quadrant 2, so landing the front on quadrant `f` is `f - 2` quarter
## turns.
##
## That arithmetic used to live the other way up — a facing was the
## direction you were LOOKING when you placed the thing, and the front
## came out opposite it. It reads fine in one sentence and it is a
## double negative everywhere else: every chair the office generator sat
## at a desk ended up with its back to the table, and every monitor
## faced the wall. A generator asking for "this chair faces south" should
## get a chair facing south.
static func _turned(block: int, boxes: Array) -> Array:
	var turns := posmod(Blocks.facing_of(block) - 2, 4)
	if turns == 0:
		return boxes
	var out: Array = []
	for box: Array in boxes:
		var spun := _turn(box[0], box[1], turns)
		# A box may carry a colour of its own — see the note on the draw
		# loop below — and turning it must not lose that.
		if box.size() > 2:
			spun.append(box[2])
		out.append(spun)
	return out

func _add_shape(block: int, shape: int, x: int, y: int, z: int, cx: int, cz: int,
		solid_key := "opaque") -> void:
	var boxes: Array = []
	match shape:
		1:
			boxes = [[Vector3(0, 0, 0), Vector3(1, 0.5, 1)]]
		2:
			boxes = [[Vector3(0, 0, 0), Vector3(1, 0.15, 1)]] \
				if block != Blocks.LILY_PAD \
				else [[Vector3(0.12, 0, 0.12), Vector3(0.88, 0.05, 0.88)]]
		7:
			# Thin full-height panel hugging whichever neighbor is solid
			# (a lone door faces north).
			if _shape_connects(7, x, y, z - 1) or not (
					_shape_connects(7, x - 1, y, z) or _shape_connects(7, x + 1, y, z)):
				boxes = [[Vector3(0, 0, 0), Vector3(1, 1, 0.14)]]
			elif _shape_connects(7, x - 1, y, z):
				boxes = [[Vector3(0, 0, 0), Vector3(0.14, 1, 1)]]
			else:
				boxes = [[Vector3(0.86, 0, 0), Vector3(1, 1, 1)]]
		8:
			boxes = [[Vector3(0, 0, 0), Vector3(1, 0.32, 1)],
				[Vector3(0.05, 0.32, 0.05), Vector3(0.95, 0.55, 0.95)]]
		3:
			boxes = [[Vector3(0, 0, 0), Vector3(1, 0.5, 1)]]
			match Blocks.stairs_facing_of(block):
				0: boxes.append([Vector3(0, 0.5, 0), Vector3(1, 1, 0.5)])
				1: boxes.append([Vector3(0.5, 0.5, 0), Vector3(1, 1, 1)])
				2: boxes.append([Vector3(0, 0.5, 0.5), Vector3(1, 1, 1)])
				3: boxes.append([Vector3(0, 0.5, 0), Vector3(0.5, 1, 1)])
		4:
			# Post always; rails only toward connected neighbors.
			boxes = [[Vector3(0.4, 0, 0.4), Vector3(0.6, 1.0, 0.6)]]
			for rail_y: Array in [[0.42, 0.56], [0.76, 0.9]]:
				if _shape_connects(shape, x + 1, y, z):
					boxes.append([Vector3(0.6, rail_y[0], 0.45), Vector3(1, rail_y[1], 0.55)])
				if _shape_connects(shape, x - 1, y, z):
					boxes.append([Vector3(0, rail_y[0], 0.45), Vector3(0.4, rail_y[1], 0.55)])
				if _shape_connects(shape, x, y, z + 1):
					boxes.append([Vector3(0.45, rail_y[0], 0.6), Vector3(0.55, rail_y[1], 1)])
				if _shape_connects(shape, x, y, z - 1):
					boxes.append([Vector3(0.45, rail_y[0], 0), Vector3(0.55, rail_y[1], 0.4)])
		5:
			boxes = [[Vector3(0.25, 0, 0.25), Vector3(0.75, 1.0, 0.75)]]
			if _shape_connects(shape, x + 1, y, z):
				boxes.append([Vector3(0.75, 0, 0.3), Vector3(1, 0.82, 0.7)])
			if _shape_connects(shape, x - 1, y, z):
				boxes.append([Vector3(0, 0, 0.3), Vector3(0.25, 0.82, 0.7)])
			if _shape_connects(shape, x, y, z + 1):
				boxes.append([Vector3(0.3, 0, 0.75), Vector3(0.7, 0.82, 1)])
			if _shape_connects(shape, x, y, z - 1):
				boxes.append([Vector3(0.3, 0, 0.25), Vector3(0.7, 0.82, 0.75)])
		6:
			# Small core plus arms toward whatever the pane joins onto; a
			# lone pane keeps the old full cross so it isn't invisible.
			var east := _shape_connects(shape, x + 1, y, z)
			var west := _shape_connects(shape, x - 1, y, z)
			var south := _shape_connects(shape, x, y, z + 1)
			var north := _shape_connects(shape, x, y, z - 1)
			if not (east or west or south or north):
				boxes = [[Vector3(0, 0, 0.44), Vector3(1, 1, 0.56)],
					[Vector3(0.44, 0, 0), Vector3(0.56, 1, 1)]]
			else:
				boxes = [[Vector3(0.44, 0, 0.44), Vector3(0.56, 1, 0.56)]]
				if east:
					boxes.append([Vector3(0.56, 0, 0.44), Vector3(1, 1, 0.56)])
				if west:
					boxes.append([Vector3(0, 0, 0.44), Vector3(0.44, 1, 0.56)])
				if south:
					boxes.append([Vector3(0.44, 0, 0.56), Vector3(0.56, 1, 1)])
				if north:
					boxes.append([Vector3(0.44, 0, 0), Vector3(0.56, 1, 0.44)])
		9:
			# DESK. A worktop the full width of the cell on four legs, so
			# one is a desk and a row of them is a bench — which is what
			# an open-plan floor is actually made of.
			#
			# THE TOP IS AT THE TOP OF THE CELL, and that is not a detail:
			# anything you stand ON a desk — a monitor, a plant — begins
			# at the floor of the cell above, so a worktop that stopped at
			# 0.8 left every screen in the building floating a fifth of a
			# block in the air.
			boxes = [[Vector3(0, 0.86, 0), Vector3(1, 1.0, 1)]]
			for lx: float in [0.06, 0.84]:
				for lz: float in [0.06, 0.84]:
					boxes.append([Vector3(lx, 0, lz),
						Vector3(lx + 0.1, 0.86, lz + 0.1)])
		15:
			# MEETING TABLE. Same trick, but on a plinth rather than legs
			# so a run of them reads as one long boardroom table.
			boxes = [[Vector3(0, 0.88, 0), Vector3(1, 1.0, 1)],
				[Vector3(0.28, 0, 0.28), Vector3(0.72, 0.88, 0.72)]]
		12:
			# Storage, and a surface at cell height to stand a plant on.
			boxes = [[Vector3(0.03, 0, 0.03), Vector3(0.97, 0.94, 0.97)],
				[Vector3(0, 0.94, 0), Vector3(1, 1.0, 1)]]
		16:
			# A tub the height of the cell, so what grows out of it starts
			# at the rim rather than hovering over it.
			boxes = [[Vector3(0.16, 0, 0.16), Vector3(0.84, 0.88, 0.84)],
				[Vector3(0.12, 0.88, 0.12), Vector3(0.88, 1.0, 0.88)]]
		10:
			# The four turnable fittings are written once facing NORTH and
			# rotated — see _turn. Canonically the BACK of the thing is at
			# low z, so its front looks down +z.
			boxes = _turned(block, [
				[Vector3(0.22, 0, 0.22), Vector3(0.78, 0.06, 0.78)],
				[Vector3(0.44, 0.06, 0.44), Vector3(0.56, 0.42, 0.56)],
				[Vector3(0.16, 0.42, 0.16), Vector3(0.84, 0.54, 0.84)],
				[Vector3(0.16, 0.54, 0.14), Vector3(0.84, 1.0, 0.26)]])
		11:
			# A MONITOR, AND WHICH END OF IT IS THE SCREEN.
			#
			# The stand used to stick out of the FRONT — the panel at the
			# back of the cell with the foot reaching past it — so after
			# the block was turned to face somebody, what they saw first
			# was the foot and the panel was on the far side. It read as
			# the back of a monitor, which is what it was.
			#
			# Screen at the front, bezel behind it, then the stalk and
			# the foot going back. The screen face is its own colour, so
			# a glance tells you which way one is pointing.
			boxes = _turned(block, [
				[Vector3(0.34, 0, 0.30), Vector3(0.66, 0.06, 0.60)],
				[Vector3(0.46, 0.06, 0.44), Vector3(0.54, 0.44, 0.56)],
				[Vector3(0.08, 0.32, 0.56), Vector3(0.92, 0.95, 0.64)],
				[Vector3(0.12, 0.36, 0.64), Vector3(0.88, 0.91, 0.66),
					SCREEN_COLOR]])
		13:
			boxes = _turned(block, [
				[Vector3(0.04, 0, 0.06), Vector3(0.96, 0.26, 0.94)],
				[Vector3(0.04, 0.26, 0.24), Vector3(0.96, 0.46, 0.96)],
				[Vector3(0.04, 0.26, 0.06), Vector3(0.96, 0.88, 0.24)]])
		14:
			boxes = _turned(block, [
				[Vector3(0.02, 0.08, 0.06), Vector3(0.98, 0.98, 0.14)]])
	var key := "trans" if shape == 6 else solid_key
	var base_color := Blocks.LK_COLOR[block]
	var jitter := _jitter(x, y, z, cx, cz)
	var origin := Vector3(x, y, z)
	for box: Array in boxes:
		var bmin: Vector3 = box[0]
		var bmax: Vector3 = box[1]
		# A THIRD ENTRY IS A COLOUR FOR THAT BOX ALONE. Everything shaped
		# was one flat colour all over, which is fine for a slab or a
		# fence and useless for a monitor: a dark grey slab on a dark grey
		# stand looks identical from the front and the back, so there was
		# no way to tell which way round one was — and that is exactly
		# what somebody looking at a desk needs to be able to tell.
		var color := box[2] as Color if box.size() > 2 else base_color
		for face_index in 6:
			var face: Array = FACES[face_index]
			var n: Vector3i = face[0]
			var u: Vector3i = face[1]
			var v: Vector3i = face[2]
			var shade: float = face[3]
			var center := origin + (bmin + bmax) * 0.5 \
				+ Vector3(n) * ((bmax - bmin) * 0.5)
			var half_u := Vector3(u) * (bmax - bmin) * 0.5
			var half_v := Vector3(v) * (bmax - bmin) * 0.5
			var start: int = _verts[key].size()
			for corner in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				_verts[key].append(center + half_u * float(corner.x) + half_v * float(corner.y))
				_normals[key].append(Vector3(n))
				var brightness := shade * jitter
				_colors[key].append(Color(color.r * brightness, color.g * brightness,
					color.b * brightness, color.a))
				_uvs[key].append(Vector2.ZERO)
				_uv2s[key].append(Vector2.ZERO)
			for index in [0, 2, 1, 0, 3, 2]:
				_indices[key].append(start + index)

func _is_opaque_at(x: int, y: int, z: int) -> bool:
	return _lk_opaque[_block_at(x, y, z)] == 1

## HOW FAR THE GROUND UNDER A BLOCK HAS DROPPED, averaged over the four
## corners it stands on. What a plant — a tuft here, a Kenney model in
## ChunkView — has to come down by to keep its feet in the ground.
func _ground_drop(x: int, y: int, z: int) -> float:
	if _lk_smooth[_block_at(x, y - 1, z)] != 1:
		return 0.0      # not standing on the ground: a ledge, a pot plant
	var sum := 0.0
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		sum += _point(x + int(c.x), y, z + int(c.y)).y
	return float(y) - sum * 0.25

## Which cutout silhouette the plants shader draws for a cross block.
## 0 grass tuft · 1 flower · 2 mushroom · 3 flame · 4 leafy bush ·
## 5 ragged sheet (vines) · 6 grain stalks · 7 bare stick (torch/ladder
## keeps its own look) · 8 solid quad (no cutout).
static func _plant_shape(block: int) -> int:
	match block:
		Blocks.TALL_GRASS, Blocks.FERN:
			return 0
		Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW, Blocks.FLOWER_PINK, \
				Blocks.DAISY, Blocks.BLUEBELL:
			return 1
		Blocks.MUSHROOM:
			return 2
		Blocks.FIRE:
			return 3
		Blocks.SAPLING, Blocks.BERRY_BUSH, Blocks.DEAD_BUSH, \
				Blocks.OFFICE_PLANT, Blocks.OFFICE_PALM:
			return 4
		Blocks.VINE:
			return 5
		Blocks.WHEAT_PLANT, Blocks.CATTAIL:
			return 6
		Blocks.BAMBOO, Blocks.TORCH:
			return 7
		Blocks.LADDER:
			return 9
	return 8

func _add_cross(block: int, x: int, y: int, z: int, cx: int, cz: int) -> void:
	var color := Blocks.LK_COLOR[block]
	# A PLANT RIDES THE GROUND DOWN. It stands on the four corners under
	# it, and if they have dropped and it has not, it is standing in the
	# air. Its own average, so a tuft on a slope leans with nothing and
	# sits at the middle of what it grows out of.
	var root := -_ground_drop(x, y, z)
	var jitter := _jitter(x, y, z, cx, cz)
	var sway := Blocks.LK_SWAY[block]
	var emit := Blocks.LK_EMIT[block]
	var o := Vector3(x, y, z)
	var half: float = CROSS_SIZES.get(block, Vector2(0.6, 0.75)).x * 0.5
	var tall: float = CROSS_SIZES.get(block, Vector2(0.6, 0.75)).y
	var lo := 0.5 - half
	var hi := 0.5 + half
	var quads := [
		[o + Vector3(lo, 0, lo), o + Vector3(hi, 0, hi)],
		[o + Vector3(lo, 0, hi), o + Vector3(hi, 0, lo)],
	]
	# Vines and ladders hang FLAT against the wall they're attached to,
	# like Minecraft — one sheet per adjacent solid face (a free-floating
	# one keeps the X so it doesn't vanish).
	if block == Blocks.VINE or block == Blocks.LADDER:
		var flat: Array = []
		var inset := 0.06
		if _is_opaque_at(x - 1, y, z):
			flat.append([o + Vector3(inset, 0, 0.02), o + Vector3(inset, 0, 0.98)])
		if _is_opaque_at(x + 1, y, z):
			flat.append([o + Vector3(1.0 - inset, 0, 0.02), o + Vector3(1.0 - inset, 0, 0.98)])
		if _is_opaque_at(x, y, z - 1):
			flat.append([o + Vector3(0.02, 0, inset), o + Vector3(0.98, 0, inset)])
		if _is_opaque_at(x, y, z + 1):
			flat.append([o + Vector3(0.02, 0, 1.0 - inset), o + Vector3(0.98, 0, 1.0 - inset)])
		if not flat.is_empty():
			quads = flat
			tall = 1.0
			if block == Blocks.LADDER:
				sway = 0.0
	for quad: Array in quads:
		var a: Vector3 = quad[0]
		var b: Vector3 = quad[1]
		# Plants use an UP normal so they're lit like the ground they grow
		# from instead of like little dark walls.
		var normal := Vector3.UP
		var start: int = _verts["plants"].size()
		var corners := [
			Vector3(a.x, y + root, a.z), Vector3(b.x, y + root, b.z),
			Vector3(b.x, y + root + tall, b.z), Vector3(a.x, y + root + tall, a.z),
		]
		var shape_id := _plant_shape(block)
		var quad_uvs := [Vector2(shape_id, 1), Vector2(shape_id + 0.999, 1),
			Vector2(shape_id + 0.999, 0), Vector2(shape_id, 0)]
		for i in 4:
			_verts["plants"].append(corners[i])
			_normals["plants"].append(normal)
			_uvs["plants"].append(quad_uvs[i])
			var brightness := jitter * (0.85 if i < 2 else 1.0)
			_colors["plants"].append(Color(color.r * brightness, color.g * brightness, color.b * brightness))
			# Only the top two verts sway, so plants stay rooted.
			_uv2s["plants"].append(Vector2(sway if i >= 2 else 0.0, emit))
		for index in [0, 2, 1, 0, 3, 2]:
			_indices["plants"].append(start + index)

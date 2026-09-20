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

## Baked face shading kept subtle - the sun and SSAO do the heavy lifting.
## Per-face shading, BAKED into the vertex colour as a stand-in for the
## sun. Gentler than it was (bottom faces were 0.62): the bake multiplies
## every light, so a ceiling directly over a lamp was drawn at two thirds
## of the brightness of the floor under it, which read as lamps that only
## shone upward. The sun still tells the faces apart; the lamps no longer
## lose on the underside.
## SMOOTHED GROUND, an experiment that can be switched off here.
##
## Natural ground with nothing on it is drawn from a height at each top
## corner rather than as a box — see _heights for the rule — so steps
## are ramps, ridges are ramps with caps and outer corners are rounded
## off, without a single block moving. Buildings are untouched (only
## SMOOTH_BLOCKS qualify) and a block with a plant on top stays square
## so the plant has ground under it.
##
## THE SHAPE IS ONLY A PICTURE. The block is still a whole block to walk
## on and dig — the lowered part can be stood on. That is the price of
## trying this in the mesher alone, and the reason it is a switch.
const SMOOTH_CORNERS := true

## THE GROUND IS A HEIGHT MAP, AND THE CORNERS ARE ITS SAMPLES.
##
## Every corner where blocks meet is a point shared by the eight blocks
## around it, and its height is HOW MUCH GROUND IS UNDER IT: of the four
## blocks directly below, each one missing takes a quarter off. Nothing
## moves sideways — a block is still exactly where it was on the map, and
## collision never hears about any of this.
##
## The offset belongs to the POINT, not to any block, so everything
## touching it draws to where it lands and nothing can come apart. See
## _sink_at, which is the whole rule.
##
## Thinking in blocks is what made the ground pointy. A corner was up, or
## a whole block down, so a step fell its full height at one edge, a lone
## block was a pyramid, a hole was a funnel and a diagonal hillside was a
## field of spikes. Thinking in POINTS, each one carrying the average of
## what is beneath it, makes those the same shapes a height map would
## give: a step is a ramp two blocks wide, a lone block is a low mound, a
## diagonal is a diagonal.
##
## ROUGH is what is added on top: a little per-point noise so that ground
## which the map says is flat is not a plane, and so the bands of a cliff
## face are not ruler-straight. It is the only knob, and 0.0 leaves the
## map alone.
const ROUGH := 0.3
## The sliver a corner always leaves between itself and its own block's
## floor. See _sink_at.
const FLOOR_GAP := 0.004
const SWELL_SALT := 7919

## What counts as GROWN rather than built, and so bends with the ground.
##
## TREE TRUNKS ARE IN IT, and they have to be. A log that kept its corners
## square held the four under it up while the ground a step away fell the
## full DROP, so every tree stood on a little pedestal with the earth
## pulled away around it — read as trees floating over the ground.
##
## LEAVES ARE NOT. A canopy is a loose shell of blocks, and dropping the
## corners of blocks that only touch each other at an edge tears it into
## scraps hanging off the top of a trunk.
const SMOOTH_BLOCKS := [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND,
	Blocks.SANDSTONE, Blocks.SNOW, Blocks.MYCELIUM, Blocks.COBBLE,
	Blocks.LOG, 125, 126, 127, 128, Blocks.WARPED_STEM]

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
# Per build: the shared height of every ground vertex, and every block's
# slope on each axis — see _surface and _axes.
var _surface_cache: Dictionary = {}
var _axes_cache: Dictionary = {}
## This chunk's origin in world blocks, so the drops line up across chunk
## borders. And how far a corner may drop: DROP, unless a test wants the
## bare shape rule on its own.
var _wx0 := 0
var _wz0 := 0
var rough := ROUGH
## Each corner's drop, worked out once and read by the eight blocks
## around it. A flat array rather than a dictionary: a chunk asks
## for these tens of thousands of times, and this is one multiply-add
## against a hashed Vector3i key. (SIZE + 1) points across, because the
## far edge of the last block is a point too.
const SPAN := SIZE + 1
var _drop_lut := PackedFloat32Array()
var _drop_done := PackedByteArray()

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
	_data = data
	_neighbors = neighbors
	_surface_cache.clear()
	if _drop_lut.is_empty():
		_drop_lut.resize(SPAN * SPAN * (H + 1))
		_drop_done.resize(SPAN * SPAN * (H + 1))
	else:
		_drop_done.fill(0)
	_axes_cache.clear()
	_wx0 = cx * SIZE
	_wz0 = cz * SIZE
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
				var shaped := false
				if _smooth(block, x, y, z):
					var h := _heights(x, y, z)
					if h[0] != 1.0 or h[1] != 1.0 or h[2] != 1.0 or h[3] != 1.0:
						_add_shaped(draw, x, y, z, cx, cz, h)
						shaped = true
				if not shaped:
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

## THE SHAPE OF THE GROUND. Every top corner of a block of ground is a
## VERTEX THE GROUND SHARES: up to four blocks meet at it, and they all
## read the same height for it — so nothing here can leave a seam, a
## spike, or a sliver of wall between two blocks that are both ground.
## A block's top is drawn through the four heights at its corners, and
## its open sides up to the line the surface makes across them. A vertex
## is UP (a whole block) if anything at all stands on it, or if any block
## touching it that is not ground says so; a block of ground's own
## opinion of its corner is: on each axis, one side open and the other
## solid means it slopes down toward the open side; both solid or both
## open, it is flat; the corner takes the lower axis. Solid means solid
## — a glowstone or a pane of glass holds a corner up like stone does.
##
## A step's edge is a ramp. A stair is a slope, because each tread's
## back corners are held up by the tread above. A plateau's outer corner
## drops its outer corner and keeps the rest of its top flat, from the
## midline. A lone block, a one-wide ridge and a one-wide hole all stay
## square, because nothing beside them slopes. Every corner is a whole
## block up or down: a rise is always one block over one block. Only
## natural ground with nothing above it is shaped; anything built, and
## anything with something on it, is whole.
func _smooth(block: int, x: int, y: int, z: int) -> bool:
	return SMOOTH_CORNERS and _smoothable()[block] == 1 and _block_at(x, y + 1, z) == Blocks.AIR

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

static func _smoothable() -> PackedByteArray:
	return _smooth_lk

## Corner heights [NW, NE, SE, SW] of a block's top, relative to its
## bottom: 1 is its own top, 0 its bottom.
func _heights(x: int, y: int, z: int) -> PackedFloat64Array:
	# FULL PRECISION, all the way to the vertex. Through a 32-bit array a
	# corner one level up reads `1 + offset`, rounded around 1, while the
	# block above reads the same point as `0 + offset`, rounded around
	# nothing — and the two land a millionth of a block apart. Every
	# height here is rounded exactly once: when it becomes a vertex.
	return PackedFloat64Array([_surface(x, y, z, 0, 0), _surface(x, y, z, 1, 0),
		_surface(x, y, z, 1, 1), _surface(x, y, z, 0, 1)])

## The shared height of the vertex at the (cx, cz) corner of block (x, z)
## on level y — cx and cz each 0 or 1. Cached per vertex and level: four
## blocks ask for each one.
func _surface(x: int, y: int, z: int, cx: int, cz: int) -> float:
	var key := Vector3i(x + cx, y, z + cz)
	if _surface_cache.has(key):
		return _surface_cache[key]
	# A BLOCK'S TOP CORNER IS THE LATTICE POINT ABOVE IT, and where that
	# point sits is decided by _sink_at — how much ground is actually
	# under it — not by this block. Its bottom corners are the points
	# below it, which _add_shaped reads the same way.
	return _remember(key, 1.0 - _sink_at(x + cx, y + 1, z + cz))

func _remember(key: Vector3i, height: float) -> float:
	_surface_cache[key] = height
	return height

## HOW FAR THIS LATTICE POINT SITS BELOW ITS OWN LEVEL, 0 .. 1.
##
## THE POINTS ARE A HEIGHT MAP, and this is the sample. A point's height
## is how much ground is underneath it: of the four blocks directly
## below, each one missing takes a QUARTER off. Three missing and it
## sits a quarter of a block above the level below, not a whole block
## down.
##
## That one line is what makes the ground smooth rather than pointy. The
## rule before it was all-or-nothing — a corner was up, or a whole block
## down — so the edge of a step fell its whole height in one go, a lone
## block became a pyramid, a hole became a funnel, and a diagonal
## hillside came out as a field of spikes. Quarters turn all of those
## into slopes: a one-block step is a ramp two blocks wide, a lone block
## is a low mound, a diagonal is a diagonal.
##
## It is capped at a whole block, so a cliff is still a cliff: what is
## further down than that is drawn by the blocks further down.
##
## SOMETHING STANDING ON THE POINT holds it up — otherwise the floor of
## whatever stands there would part from the ground it stands on — and so
## does anything built, a slab, a fence or a pane among the eight blocks
## around it: those are drawn as boxes and a box cannot follow a bent
## corner. The roughness is added even under a standing block, because
## that is the line between two blocks of a cliff face and a cliff with
## ruler-straight bands reads as brickwork.
func _sink_at(vx: int, wy: int, vz: int) -> float:
	if wy <= 0 or wy >= H or vx < 0 or vx > SIZE or vz < 0 or vz > SIZE:
		return 0.0
	var slot := (wy * SPAN + vz) * SPAN + vx
	if _drop_done[slot] == 1:
		return _drop_lut[slot]
	var missing := 0
	var square := false
	var covered := false
	for nx: int in [vx - 1, vx]:
		for nz: int in [vz - 1, vz]:
			# What is under the point decides its height...
			var below := _block_at(nx, wy - 1, nz)
			if below == Blocks.AIR or _lk_solid[below] != 1:
				missing += 1
			elif _lk_smooth[below] != 1:
				square = true
			# ...and what is over it can hold it up.
			var above := _block_at(nx, wy, nz)
			if above != Blocks.AIR and _lk_solid[above] == 1:
				covered = true
				if _lk_smooth[above] != 1:
					square = true
	var sank := 0.0
	if not square:
		if not covered:
			sank = float(missing) * 0.25
		# The roughness is DOWNWARD like everything else here, and a point
		# with solid ground over it takes it too: that line is where two
		# blocks of a cliff face meet, and a cliff whose bands all rule
		# straight reads as brickwork.
		#
		# Down only, and that is not a style choice. A point that rose
		# above its own level could end up higher than the point above
		# it — a block inside out, its top below its bottom — and the
		# face of such a block has to be clipped where the two cross,
		# which leaves a vertex in the middle of a neighbour's edge and a
		# seam you can see the sky through. Falling only, that cannot
		# happen: every bottom is at or below zero and every top at or
		# above it.
		# NEVER THE WHOLE BLOCK. A corner that fell exactly to its own
		# block's floor met a floor that had itself fallen a hair, which
		# is a block inside out by a thousandth — and the face of one has
		# to be clipped where its top and bottom cross, leaving a vertex
		# in the middle of a neighbour's edge and a seam. A sliver of a
		# block left over costs nothing to look at and cannot invert.
		sank = clampf(sank + rough * _swell(vx, wy, vz), 0.0, 1.0 - FLOOR_GAP)
	_drop_lut[slot] = sank
	_drop_done[slot] = 1
	# Back out of the array, not the variable: the table holds 32-bit
	# floats, so a point worked out here and the same point read from the
	# table later must be the same number to the last bit. Otherwise the
	# shape of a chunk depends on the order its blocks happened to ask,
	# and two chunks disagree about their seam by a millionth.
	return _drop_lut[slot]

## How much of the drop this corner takes, 0 .. 1. One hash of where the
## corner is: its own number, unrelated to the corners beside it, which
## is the whole point (see DROP).
func _swell(vx: int, wy: int, vz: int) -> float:
	return WorldGen.hash01((_wx0 + vx) * 31 + wy, (_wz0 + vz) * 17 - wy, SWELL_SALT)

## One block of ground's own view of one of its corners, 1 up or 0 down.
func _opinion(x: int, y: int, z: int, cx: int, cz: int) -> float:
	var axes := _axes(x, y, z)
	return minf(axes[2 + cx], axes[cz])

## A block's slope on each axis from its four side neighbours alone:
## [north edge, south edge, west edge, east edge], each 1 up or 0 down.
func _axes(x: int, y: int, z: int) -> PackedFloat32Array:
	var key := Vector3i(x, y, z)
	if _axes_cache.has(key):
		return _axes_cache[key]
	var n := _firm_at(x, y, z - 1)
	var e := _firm_at(x + 1, y, z)
	var s := _firm_at(x, y, z + 1)
	var w := _firm_at(x - 1, y, z)
	var axes := PackedFloat32Array([
		0.0 if (not n and s) else 1.0, 0.0 if (not s and n) else 1.0,
		0.0 if (not w and e) else 1.0, 0.0 if (not e and w) else 1.0])
	_axes_cache[key] = axes
	return axes

## Solid, for the shape of the ground: stone, but also glowstone, glass,
## a fence — anything a body cannot pass. Ground next to a glowstone
## used to slope toward it as if it were air, and the glowstone, which
## draws no face against an opaque neighbour, was then open on that side.
func _firm_at(x: int, y: int, z: int) -> bool:
	return _lk_solid[_block_at(x, y, z)] == 1

## Sides 0 N, 1 E, 2 S, 3 W; each runs between two corners, clockwise
## seen from above: N is NW→NE, E is NE→SE, S is SE→SW, W is SW→NW.
const SIDE_CORNERS := [[0, 1], [1, 2], [2, 3], [3, 0]]
const SIDE_STEP := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const CORNER_XZ := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

## One side of a block, against air: the part of it between the ground it
## stands on and the ground on top of it. Both cross the face as straight
## lines — from the height at one corner to the height at the other — and
## the face is whatever lies between them. Neither is cut off at the
## block's own bottom or top: a corner may have dropped (see DROP), so
## the block above it grows down past its own floor to fill the space,
## and a wall that stopped at the block would leave that strip open.
##
## Coloured from the block's side colour at the ground to its top colour
## at the top, so a cut runs green down to a brown foot rather than brown
## all over.
func _side_face(x: int, y: int, z: int, side: int, top0: float, top1: float,
		bot0: float, bot1: float,
		base_color: Color, top_color: Color, brightness: float, emit: float) -> void:
	if top0 <= bot0 and top1 <= bot1:
		return
	var d := top1 - top0
	var db := bot1 - bot0
	# Where the two lines cross, if they do inside the face: past that the
	# ground above has sunk below the ground beneath and there is nothing
	# of the block left to draw.
	var s0 := 0.0
	var s1 := 1.0
	var gap := d - db
	if gap != 0.0:
		var cross := (bot0 - top0) / gap
		if cross > 0.0 and cross < 1.0:
			if top0 <= bot0:
				s0 = cross
			else:
				s1 = cross
	# Around the face: along the ground below, up the far end, back along
	# the surface line, down the near end.
	# AT AN END OF THE FACE, the height IS the corner's height — not the
	# line evaluated there. `a + (b - a) * 1` is not b to the last bit,
	# and the top face of this same block puts its corner at b: a
	# millionth of a block apart is still two faces that do not meet.
	var along := PackedFloat64Array([s0, s1, s1, s0])
	var heights := PackedFloat64Array([
		bot0 if s0 == 0.0 else bot0 + db * s0,
		bot1 if s1 == 1.0 else bot0 + db * s1,
		top1 if s1 == 1.0 else top0 + d * s1,
		top0 if s0 == 0.0 else top0 + d * s0])
	var pair: Array = SIDE_CORNERS[side]
	var c0: Vector2 = CORNER_XZ[pair[0]]
	var c1: Vector2 = CORNER_XZ[pair[1]]
	var o := Vector3(x, y, z)
	var step: Vector2i = SIDE_STEP[side]
	var normal := Vector3(step.x, 0, step.y)
	# ANY point that lands on one already there is dropped, not just one
	# following it. Where the ground above meets the ground below — a
	# ramp's foot, a face that has closed to nothing — two corners of
	# this shape are the same place, and a triangle between them is a
	# sliver with no area: nothing to see, two edges into the mesh that
	# nothing matches, and something for the depth buffer to argue with.
	var world: Array = []
	var cols: Array = []
	for i in along.size():
		var q: float = along[i]
		var at := o + Vector3(lerpf(c0.x, c1.x, q), 0.0, lerpf(c0.y, c1.y, q))
		at.y = float(y) + heights[i]    # once, as in _add_shaped
		var seen := false
		for other: Vector3 in world:
			if other.distance_squared_to(at) < 0.000001:
				seen = true
				break
		if seen:
			continue
		world.append(at)
		cols.append(base_color.lerp(top_color, float(heights[i])))
	for i in range(1, world.size() - 1):
		var ab: Vector3 = world[i] - world[0]
		var ac: Vector3 = world[i + 1] - world[0]
		if ab.cross(ac).length_squared() < 0.00000001:
			continue      # three points in a line: no face, only edges
		_tri("opaque", [world[0], world[i], world[i + 1]], normal,
			[cols[0], cols[i], cols[i + 1]], brightness, emit)

## A shaped block: the top as two triangles split through its higher
## diagonal, each open side up to the surface line, and a bottom when
## there is nothing beneath. Sides against another solid block draw
## nothing: the surface is shared, so there is nothing left bare.
func _add_shaped(block: int, x: int, y: int, z: int, cx: int, cz: int,
		h: PackedFloat64Array) -> void:
	var base_color := Blocks.LK_COLOR[block]
	var top_color := Blocks.LK_TOP[block]
	var jitter := _jitter(x, y, z, cx, cz, Blocks.LK_ROUGH[block])
	var emit := Blocks.LK_EMIT[block]
	var o := Vector3(x, y, z)
	var p: Array = []
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		# THE HEIGHT GOES IN ONCE, at the height it lands. Building
		# Vector3(c.x, h, c.y) and adding the block's corner rounds the
		# height twice — once around 1, once around 31 — and a cube face
		# meeting this one rounds once, so the two put the same point two
		# millionths of a block apart and the mesh has a seam in it.
		var point := o + Vector3(c.x, 0.0, c.y)
		point.y = float(y) + h[i]
		p.append(point)
	# ITS FLOOR IS THE LATTICE TOO: the four points under the block, each
	# with its own offset, exactly as the ground below them draws its top.
	var b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		b[i] = -_sink_at(x + int(c.x), y, z + int(c.y))
	# Split through the diagonal whose two corners are LEVEL, so a block
	# with one corner out of line is a flat triangle and a sloped one —
	# flat from the midline — rather than a ridge from that corner to
	# the far one. Where neither is level, or both are, the higher.
	var d02 := absf(h[0] - h[2])
	var d13 := absf(h[1] - h[3])
	var through_02 := d02 < d13 if d02 != d13 else h[0] + h[2] >= h[1] + h[3]
	var tris: Array = [[0, 1, 2], [0, 2, 3]] if through_02 else [[1, 2, 3], [1, 3, 0]]
	# The same corner shading a cube's top gets. Shaped tops had none,
	# which did not show while they were only the edges of steps — but
	# with rolling ground most of a field is shaped, and ground running up
	# to a wall lost the dark line along its foot.
	var top_cols: Array = []
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		var sx := 1 if c.x > 0.5 else -1
		var sz := 1 if c.y > 0.5 else -1
		var s1 := _occludes(x + sx, y + 1, z)
		var s2 := _occludes(x, y + 1, z + sz)
		var sc := _occludes(x + sx, y + 1, z + sz)
		var ao := 3.0 if (s1 and s2) else float(int(s1) + int(s2) + int(sc))
		var shade := 1.0 - ao_step * ao
		top_cols.append(Color(top_color.r * shade, top_color.g * shade,
			top_color.b * shade, top_color.a))
	for t: Array in tris:
		var a: Vector3 = p[t[0]]
		var bpt: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var n := (bpt - a).cross(c - a).normalized()
		if n.y < 0.0:
			n = -n
		# Lit between a side and a top, by how far it tips.
		var bright := lerpf((SHADE_X + SHADE_Z) * 0.5, SHADE_TOP, clampf(n.y, 0.0, 1.0)) * jitter
		_tri("opaque", [a, bpt, c], n, [top_cols[t[0]], top_cols[t[1]], top_cols[t[2]]],
			bright, emit)
	for side in 4:
		var step: Vector2i = SIDE_STEP[side]
		if _is_opaque_at(x + step.x, y, z + step.y):
			continue
		var pair: Array = SIDE_CORNERS[side]
		var shade := SHADE_Z if side % 2 == 0 else SHADE_X
		_side_face(x, y, z, side, h[pair[0]], h[pair[1]], b[pair[0]], b[pair[1]],
			base_color, top_color, shade * jitter, emit)
	if not _is_opaque_at(x, y - 1, z):
		# Through the same four corners as the sides start from, or the
		# underside would part from them.
		var u: Array = []
		for i in 4:
			var c: Vector2 = CORNER_XZ[i]
			var point := o + Vector3(c.x, 0.0, c.y)
			point.y = float(y) + b[i]   # once, as above
			u.append(point)
		_tri("opaque", [u[0], u[1], u[2]], Vector3.DOWN,
			[base_color, base_color, base_color], SHADE_BOTTOM * jitter, emit)
		_tri("opaque", [u[0], u[2], u[3]], Vector3.DOWN,
			[base_color, base_color, base_color], SHADE_BOTTOM * jitter, emit)

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
func _tri(key: String, pts: Array, normal: Vector3, cols: Array, brightness: float,
		emit: float) -> void:
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[1]
	var c: Vector3 = pts[2]
	var cb: Color = cols[1]
	var cc: Color = cols[2]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	var start: int = _verts[key].size()
	var i := 0
	for pair: Array in [[a, cols[0]], [b, cb], [c, cc]]:
		var color: Color = pair[1]
		_verts[key].append(pair[0])
		_normals[key].append(normal)
		_uvs[key].append(Vector2(0, 0))
		_colors[key].append(Color(color.r * brightness, color.g * brightness, color.b * brightness, color.a))
		_uv2s[key].append(Vector2(0.0, emit))
		i += 1
	_indices[key].append_array([start, start + 1, start + 2])

func _add_cube(block: int, x: int, y: int, z: int, cx: int, cz: int, key: String) -> void:
	var base_color := Blocks.LK_COLOR[block]
	var top_color := Blocks.LK_TOP[block]
	var jitter := _jitter(x, y, z, cx, cz, Blocks.LK_ROUGH[block])
	var sway := Blocks.LK_SWAY[block]
	var emit := Blocks.LK_EMIT[block]
	var translucent := key == "trans"
	var is_liquid := Blocks.LK_LIQUID[block] == 1
	# Liquids drop their surface a bit below the block top, like Minecraft.
	var top_y := 0.875 if is_liquid and _block_at(x, y + 1, z) != block else 1.0
	# THE EIGHT CORNERS OF THIS BLOCK: [x][y][z], each 0 or 1 along the
	# axis. A cube is only a cube when none of them has dropped — which
	# is the case for everything built, and everything walled in by it
	# (see DROP) — and otherwise it is drawn through whatever shape its
	# corners make, the same as the ground around it.
	#
	# WATER KEEPS ITS SURFACE and follows the ground with its underside:
	# its top is the flat sheet it has always been, and its bottom drops
	# with the lake bed, so the water still reaches the ground it sits
	# on rather than leaving a slot under its edge.
	var corner_dy := PackedFloat32Array()
	corner_dy.resize(8)
	var corner_ready := 0
	var bent := true
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
		# Each corner of THIS face, as it fell — for the fold below.
		var face_dy := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
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
			if bent:
				var ci := ((int(vert.x) - x) << 2) | ((int(vert.y) - y) << 1) \
					| (int(vert.z) - z)
				if (corner_ready >> ci) & 1 == 0:
					corner_ready |= 1 << ci
					var ax := (ci >> 2) & 1
					var ay := (ci >> 1) & 1
					var az := ci & 1
					var slot := (((y + ay) * SPAN) + z + az) * SPAN + x + ax
					var fell: float = _drop_lut[slot] if _drop_done[slot] == 1 \
						else _sink_at(x + ax, y + ay, z + az)
					# A liquid's own surface never moves; only what it
					# stands on does.
					corner_dy[ci] = 0.0 if (is_liquid and ay == 1) else -fell
				vert.y += corner_dy[ci]
				face_dy[i] = corner_dy[ci]
			verts.append(vert)
			normals.append(normal)
			uvs.append(Vector2(pattern + CORNER_U[i], CORNER_V[i]))
			var brightness := shade * jitter * (1.0 - ao_step * ao[i])
			colors.append(Color(color.r * brightness, color.g * brightness,
				color.b * brightness, color.a))
			uv2s.append(uv2)
		# WHICH WAY THE QUAD FOLDS. Four corners that have each dropped by
		# their own amount are not a flat shape, so the fold has to go
		# somewhere: along the diagonal whose two corners are CLOSEST in
		# height, which is the flattest line across the face and the
		# smallest crease. It follows the ground, so it changes direction
		# as the ground does rather than ruling the same way everywhere.
		#
		# A face nobody has dropped folds the old way instead: to match
		# the AO gradient, which kills the classic voxel AO artefact.
		# Godot front faces wind clockwise.
		var fold := ao[0] + ao[2] <= ao[1] + ao[3]
		var bend := absf(face_dy[0] - face_dy[2]) - absf(face_dy[1] - face_dy[3])
		if bend != 0.0:
			fold = bend < 0.0
		var order: PackedInt32Array = QUAD_ORDER if fold else QUAD_ORDER_FLIPPED
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
	return (_sink_at(x, y, z) + _sink_at(x + 1, y, z)
		+ _sink_at(x, y, z + 1) + _sink_at(x + 1, y, z + 1)) * 0.25

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

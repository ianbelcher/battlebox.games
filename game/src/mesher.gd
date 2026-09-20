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
const SMOOTH_BLOCKS := [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND,
	Blocks.SANDSTONE, Blocks.SNOW, Blocks.MYCELIUM, Blocks.COBBLE,
	Blocks.CHARRED]

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
	_corner_cache.clear()
	_fill_column_tops()
	# The minimap's block per column, two bytes each like everything else
	# that holds a block id.
	var topmap := PackedByteArray()
	topmap.resize(SIZE * SIZE * 2)
	# How far the ground has dropped under each column's own plants, for
	# the models ChunkView plants (see _ground_drop). Written as the
	# columns are walked, so it costs nothing to carry.
	var roots := PackedFloat32Array()
	roots.resize(SIZE * SIZE)
	# Which block each column's skin is made of, once the walk has found
	# it: the skin is drawn after, in one pass over the columns.
	var skin_here := PackedInt32Array()
	skin_here.resize(SIZE * SIZE)
	skin_here.fill(0)
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
				# ...but never the top of a column of ground, however
				# boxed in it looks. Under a tree trunk every one of its
				# six neighbours is solid, and skipping it left the
				# column with no skin, so the trunk's foot had nothing to
				# stand on and the ground beside it stopped short.
				if float(y + 1) != _top_of(x, z) \
						and x > 0 and x < SIZE - 1 and z > 0 and z < SIZE - 1 \
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
				# THE TOP OF A COLUMN OF GROUND KEEPS EVERYTHING BUT ITS
				# LID. The skin draws its surface, and the wall under its
				# edge where the ground beside it has fallen away (see
				# _add_skin) — but the block is still a block from
				# underneath and from inside: the ceiling of a cave below
				# it, the wall of one beside it. Dropping it whole took
				# the roof off every cave that ran under the surface.
				var is_skin := float(y + 1) == _top_of(x, z)
				if is_skin:
					skin_here[z * SIZE + x] = draw
				_add_cube(draw, x, y, z, cx, cz, solid_key, is_skin)
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
	for z in SIZE:
		for x in SIZE:
			var ground := skin_here[z * SIZE + x]
			if ground != Blocks.AIR:
				_add_skin(x, z, _top_of(x, z), ground)
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

# ---- the skin over the ground ------------------------------------------
#
## THE GROUND IS ONE SKIN, NOT A PILE OF LIDS.
##
## Drawing a top face per block is what puts holes and walls in a
## hillside: a cell with no block in it has no face, so you see down into
## the gap between its neighbours, and a step of one level leaves the side
## of the upper block standing there as a wall. Neither is anything to do
## with how it is lit or how rough it is; it is what "every face belongs
## to a block" means.
##
## So the ground is drawn as a surface in its own right, one piece per
## COLUMN, through four corner heights it shares with the columns around
## it. Where two columns differ by a single level their shared corners
## come out at the same height, so the two pieces meet edge to edge and
## the step is a slope with nothing vertical in it. A gap between stepped
## blocks is spanned rather than left open, because the skin does not
## care whether there is a block under any particular part of it. And a
## diagonal staircase, which used to be a field of little pyramids, comes
## out as one flat plane.
##
## A wall is only drawn where the ground drops TWO levels or more at once
## — see _add_skin — because that is the only place a block face has
## nothing touching it.

## The top of each column of natural ground in this chunk and one ring
## around it, as an absolute height: the y above its highest solid block.
## -1 where there is no ground at all, and for anything built, which is
## drawn as the boxes it is.
var _column_top := PackedFloat32Array()
var _column_held := PackedByteArray()
const COLUMNS := SIZE + 2

func _fill_column_tops() -> void:
	if _column_top.is_empty():
		_column_top.resize(COLUMNS * COLUMNS)
		_column_held.resize(COLUMNS * COLUMNS)
	for iz in COLUMNS:
		for ix in COLUMNS:
			var nx := ix - 1
			var nz := iz - 1
			var found := -1.0
			var held := 0
			# Down from the sky to the first ground. What holds the
			# ground square is what is RESTING on it — the run of solid
			# blocks reaching right down to it, a trunk or a wall — and
			# a gap of air below something breaks that run. A canopy of
			# leaves three blocks up is not standing on anything, and
			# counting it flattened the ground under every tree.
			var standing := 0
			# ...all the way to y = 0. Stopping at 1 left the floor of a
			# flat test world with no top at all, and every rule here
			# reading -1 for it.
			for y in range(H - 1, -1, -1):
				var block := _block_at(nx, y, nz)
				if block == Blocks.AIR or _lk_cross[block] == 1:
					standing = 0
					continue
				if _lk_smooth[block] == 1:
					found = float(y + 1)
					held = standing
					break
				standing = 1 if _lk_solid[block] == 1 else 0
			_column_top[iz * COLUMNS + ix] = found
			_column_held[iz * COLUMNS + ix] = held

## Is something standing on this column's ground — a trunk, a wall, a
## floor somebody laid? Then its corners stay where the blocks are.
func _held_at(nx: int, nz: int) -> bool:
	var ix := nx + 1
	var iz := nz + 1
	if ix < 0 or ix >= COLUMNS or iz < 0 or iz >= COLUMNS:
		return false
	return _column_held[iz * COLUMNS + ix] == 1

func _top_of(nx: int, nz: int) -> float:
	var ix := nx + 1
	var iz := nz + 1
	if ix < 0 or ix >= COLUMNS or iz < 0 or iz >= COLUMNS:
		return -1.0
	return _column_top[iz * COLUMNS + ix]

## THE HEIGHT OF ONE CORNER OF ONE COLUMN'S PIECE OF SKIN.
##
## The average of the columns meeting at that corner — but only the ones
## within a level of this column, so a cliff does not drag the ground
## over the edge of it. Two columns a single level apart therefore agree
## about the corner between them (each has the other inside its reach),
## which is what makes a one-level step a slope; across a cliff they do
## not, and the gap between their answers is the wall.
func _skin_corner(x: int, z: int, cx: int, cz: int, mine: float) -> float:
	# WORKED OUT ONCE PER POINT. Every column asks for its four corners,
	# for the slope at each of them (four more points each), and again for
	# the two it shares with each neighbour — some thirty calls per
	# column, nearly all of them for a point another column has already
	# asked about. Without this the sort below runs seven thousand times a
	# chunk and meshing one takes twice as long.
	#
	# Keyed by the point AND by who is asking, because that is what the
	# answer depends on: across a tear the two sides read it differently,
	# and a cache that forgot the asker would weld a cliff shut.
	var key := (((z + cz + 2) * CORNER_KEYS + x + cx + 2) << 8) | (int(mine) & 0xFF)
	var hit: Variant = _corner_cache.get(key)
	if hit != null:
		return hit
	var value := _corner_height(x, z, cx, cz, mine)
	corners_worked += 1
	_corner_cache[key] = value
	return value

## The points of this chunk plus two rings either side, for the key above.
const CORNER_KEYS := SIZE + 6
var _corner_cache: Dictionary = {}
## How many points this build actually worked out, as opposed to looked
## up. Read by tests/mesh_watertight.gd, which is where the cache is kept
## honest: without a bound on this nothing notices when a change starts
## asking for the same point over and over again.
var corners_worked := 0

func _corner_height(x: int, z: int, cx: int, cz: int, mine: float) -> float:
	# THE COLUMNS THAT CAN REACH EACH OTHER SHARE THE CORNER. Sort the
	# four tops meeting here and walk up them: while each is within a
	# step of the one below, they are the same piece of ground and the
	# corner they share is their average. Where the walk has to jump more
	# than a step, the ground is torn — that is a cliff — and the columns
	# above the tear keep their own corner, with the wall between.
	#
	# Asking from either side of a one-level step gives the same answer,
	# which is what makes it a slope with nothing vertical in it. A tall
	# column nearby cannot spoil that: it is simply on the other side of
	# a tear, and has no say in this corner.
	var tops := PackedFloat64Array()
	for dx: int in [cx - 1, cx]:
		for dz: int in [cz - 1, cz]:
			var other := _top_of(x + dx, z + dz)
			if other >= 0.0:
				tops.append(other)
	if tops.is_empty():
		return mine
	tops.sort()
	var low := tops[0]
	var high := tops[0]
	var total := tops[0]
	var count := 1
	for i in range(1, tops.size()):
		if tops[i] - high > 1.001:
			if mine <= high + 0.001:
				break          # our group ends here
			low = tops[i]
			total = 0.0
			count = 0
		high = tops[i]
		total += tops[i]
		count += 1
	if mine < low - 0.001 or mine > high + 0.001:
		return mine            # not in any group of ours
	# ANYTHING STANDING ON THE GROUND HOLDS THIS CORNER WHERE THE BLOCKS
	# ARE. A trunk, a wall, a floor somebody laid, a crate: they are drawn
	# as the boxes they are, with flat square faces, and ground that had
	# smoothed away from one would leave a slot down the join — or set it
	# standing over a dip. It holds the corner at ITS OWN column's top,
	# not the tallest column in the group, or a trunk in a hollow would be
	# left standing in a hole.
	var held := -1.0
	for dx: int in [cx - 1, cx]:
		for dz: int in [cz - 1, cz]:
			var top := _top_of(x + dx, z + dz)
			if top >= low - 0.001 and top <= high + 0.001 \
					and _held_at(x + dx, z + dz):
				held = maxf(held, top)
	if held >= 0.0:
		return held
	# A CLIFF IS A CLIFF. Where one of the columns at this corner is torn
	# from the rest — two levels or more, which is the one place a
	# vertical face belongs — the ground each side of the tear is drawn
	# as the blocks it is, square faces down the whole height of it, and
	# this corner stays on the lattice so the skin meets them exactly.
	# Smoothing it would leave a lip over the cliff and a seam under it,
	# and a cave coming out of the cliff face would be walled up.
	var west_north := _top_of(x + cx - 1, z + cz - 1)
	var east_north := _top_of(x + cx, z + cz - 1)
	var west_south := _top_of(x + cx - 1, z + cz)
	var east_south := _top_of(x + cx, z + cz)
	if _torn(west_north, east_north) or _torn(west_south, east_south) \
			or _torn(west_north, west_south) or _torn(east_north, east_south):
		return mine
	return total / float(count) - rough * _swell(x + cx, int(high), z + cz)

## Is the ground between these two columns a cliff rather than a step?
## Side by side only — a hillside falls two levels across the diagonal of
## every corner on it, and that is a slope, not a tear.
func _torn(a: float, b: float) -> bool:
	return a >= 0.0 and b >= 0.0 and absf(a - b) > 1.001

## WHERE THE GROUND FACES AT THIS CORNER. The slope of the skin either
## side of it, so the light runs across the surface instead of stopping
## at every triangle. Both columns of a shared corner work out the same
## answer, so neighbouring pieces cannot disagree.
func _skin_normal(x: int, z: int, cx: int, cz: int, mine: float) -> Vector3:
	var west := _skin_corner(x - 1, z, cx, cz, mine)
	var east := _skin_corner(x + 1, z, cx, cz, mine)
	var north := _skin_corner(x, z - 1, cx, cz, mine)
	var south := _skin_corner(x, z + 1, cx, cz, mine)
	return Vector3(west - east, 2.0, north - south).normalized()

## ONE COLUMN'S PIECE OF SKIN: the surface over it, and a wall under its
## edge only where the ground beside it falls away by more than a level.
##
## `top` is the height of the ground here — the y above the column's
## highest block — and `block` what that block is, for its colour.
func _add_skin(x: int, z: int, top: float, block: int) -> void:
	var colour := Blocks.LK_TOP[block]
	var side_colour := Blocks.LK_COLOR[block]
	var jitter := _jitter(x, int(top) - 1, z, _wx0 / SIZE, _wz0 / SIZE,
		Blocks.LK_ROUGH[block])
	var emit := Blocks.LK_EMIT[block]
	var corners := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var normals: Array = []
	var points: Array = []
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		var height := _skin_corner(x, z, int(c.x), int(c.y), top)
		corners[i] = height
		normals.append(_skin_normal(x, z, int(c.x), int(c.y), top))
		var point := Vector3(x + c.x, 0.0, z + c.y)
		point.y = height
		points.append(point)
	# Fold along the diagonal whose corners are closest in height: the
	# flattest line across the piece, and the smallest crease.
	var through_02 := absf(corners[0] - corners[2]) <= absf(corners[1] - corners[3])
	var tris: Array = [[0, 1, 2], [0, 2, 3]] if through_02 else [[1, 2, 3], [1, 3, 0]]
	for t: Array in tris:
		var a: Vector3 = points[t[0]]
		var b: Vector3 = points[t[1]]
		var c2: Vector3 = points[t[2]]
		var flat := (b - a).cross(c2 - a).normalized()
		if flat.y < 0.0:
			flat = -flat
		_tri("opaque", [a, b, c2], flat, [colour, colour, colour],
			SHADE_TOP * jitter, emit,
			[normals[t[0]], normals[t[1]], normals[t[2]]])
	# THE ONLY VERTICAL FACES ABOVE GROUND. Where the neighbour shares our
	# corners — a step of one level, or flat — there is nothing between us
	# to close. Where it is torn away below us, the wall runs from our
	# corners down to ITS corners, exactly, so the two pieces of skin meet
	# along the bottom of it. Blocks do not draw these faces at all: see
	# the note in _add_cube about a face above the ground beside it.
	for side in 4:
		var step: Vector2i = SIDE_STEP[side]
		var beyond := _top_of(x + step.x, z + step.y)
		if beyond < 0.0:
			continue      # no ground there at all: nothing to meet
		if beyond < top - 1.001:
			continue      # a cliff: the blocks draw their own faces
		var pair: Array = SIDE_CORNERS[side]
		var a: Vector3 = points[pair[0]]
		var b: Vector3 = points[pair[1]]
		# The same two corners, as the column over there reads them.
		var theirs: Array = SIDE_CORNERS[(side + 2) % 4]
		var their_a := _skin_corner(x + step.x, z + step.y,
			int(CORNER_XZ[theirs[1]].x), int(CORNER_XZ[theirs[1]].y), beyond)
		var their_b := _skin_corner(x + step.x, z + step.y,
			int(CORNER_XZ[theirs[0]].x), int(CORNER_XZ[theirs[0]].y), beyond)
		if their_a >= a.y - 0.001 and their_b >= b.y - 0.001:
			continue      # they meet us, or stand over us
		var normal := Vector3(step.x, 0.0, step.y)
		var low_a := Vector3(a.x, minf(their_a, a.y), a.z)
		var low_b := Vector3(b.x, minf(their_b, b.y), b.z)
		var shade := (SHADE_Z if side % 2 == 0 else SHADE_X) * jitter
		_tri("opaque", [a, b, low_b], normal,
			[colour, colour, side_colour], shade, emit)
		_tri("opaque", [a, low_b, low_a], normal,
			[colour, side_colour, side_colour], shade, emit)

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

## `skinned` means the ground's own skin draws this block's top: the block
## still draws everything else it owes — see the note where it is called.
func _add_cube(block: int, x: int, y: int, z: int, cx: int, cz: int, key: String,
		skinned := false) -> void:
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
	# Is this block standing on the ground rather than part of it? Its
	# underside is exactly the top of this column of ground.
	var standing := _lk_smooth[block] != 1 and float(y) == _top_of(x, z)

	for face_index in 6:
		var face: Array = FACES[face_index]
		var n: Vector3i = face[0]
		if skinned and n.y == 1:
			continue          # the skin is this block's lid
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
			# ANYTHING STANDING ON THE GROUND IS A WHOLE BOX. A trunk, a
			# wall, a crate: where it touches ground it used to cull, and
			# the two of them shared their sides. They cannot any more —
			# the ground's face there is not a face, it is the skin, a
			# surface that runs on past this block, under it and up the
			# slope beside it. So a block standing on the skin draws all
			# of itself and sits ON the ground rather than being welded
			# into it, and the ground can slope up over its foot without
			# tearing a hole in its side. Hidden faces, six per trunk.
			if not (standing and _lk_smooth[neighbor] == 1):
				if Blocks.LK_OPAQUE[neighbor] == 1:
					continue
			# A FACE ABOVE THE GROUND BESIDE IT IS THE SKIN'S, NOT THIS
			# BLOCK'S. Where a column of ground is cut away, the wall down
			# the side of it is drawn by the skin, which knows where the
			# ground over there actually is (see _add_skin); this block
			# drawing it too would put two faces in the same place, out by
			# whatever the skin had smoothed. Underground — a cave, a
			# tunnel, a cellar — there is no skin, and the block draws its
			# own face as it always has.
			if n.y == 0 and _lk_smooth[block] == 1:
				var beside := _top_of(x + n.x, z + n.z)
				if beside >= _top_of(x, z) - 1.001 \
						and float(y) >= beside - 0.001:
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
	var top := _top_of(x, z)
	if top < 0.0 or absf(top - float(y)) > 0.001:
		return 0.0      # not standing on the skin: a ledge, a pot plant
	var sum := 0.0
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		sum += _skin_corner(x, z, int(c.x), int(c.y), top)
	return top - sum * 0.25

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

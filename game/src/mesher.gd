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
const SMOOTH_BLOCKS := [Blocks.GRASS, Blocks.DIRT, Blocks.STONE, Blocks.SAND,
	Blocks.SANDSTONE, Blocks.SNOW, Blocks.MYCELIUM, Blocks.COBBLE,
	Blocks.LEAVES, Blocks.LEAVES_DARK, Blocks.LEAVES_LIGHT, Blocks.LEAVES_PINK]

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

var _data: PackedByteArray
var _neighbors: Dictionary  # Vector2i (unit offsets) -> PackedByteArray

## Per-surface accumulation.
var _verts := {}
var _normals := {}
var _colors := {}
var _uv2s := {}
var _uvs := {}
var _indices := {}
var lights: Array = []
var teleporters: Array = []   # local-space Vector3i of warp stones

func _init() -> void:
	for key in ["opaque", "plants", "trans"]:
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
		return _data[(y * SIZE + z) * SIZE + x]
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
	return neighbor[(y * SIZE + z) * SIZE + x]

func _occludes(x: int, y: int, z: int) -> bool:
	return _lk_opaque[_block_at(x, y, z)] == 1

## Build all surfaces for a chunk. cx/cz are only used to seed color jitter
## so the pattern doesn't repeat chunk to chunk.
var _lk_opaque := PackedByteArray()
var _lk_solid := PackedByteArray()
# Per build: the shared height of every ground vertex, and every block's
# slope on each axis — see _surface and _axes.
var _surface_cache: Dictionary = {}
var _axes_cache: Dictionary = {}

func build(data: PackedByteArray, neighbors: Dictionary, cx: int, cz: int) -> Dictionary:
	_lk_opaque = Blocks.LK_OPAQUE
	_lk_solid = Blocks.LK_SOLID
	_data = data
	_neighbors = neighbors
	_surface_cache.clear()
	_axes_cache.clear()
	var topmap := PackedByteArray()
	topmap.resize(SIZE * SIZE)
	for y in H:
		# Whole-slab air check runs in C++ — skips most of the sky instantly.
		var slab_off := y * SIZE * SIZE
		if _data.slice(slab_off, slab_off + SIZE * SIZE).count(0) == SIZE * SIZE:
			continue
		for z in SIZE:
			for x in SIZE:
				var block := int(_data[(y * SIZE + z) * SIZE + x])
				if block == Blocks.AIR:
					continue
				topmap[z * SIZE + x] = block
				if Blocks.LK_CROSS[block] == 1:
					if not MODEL_PLANTS.has(block):
						_add_cross(block, x, y, z, cx, cz)
					continue
				var shape := int(Blocks.LK_SHAPE[block])
				if shape != 0:
					_add_shape(block, shape, x, y, z, cx, cz)
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
				var draw := block
				if block == Blocks.TRAP:
					draw = Blocks.disguise_of([
						_block_at(x - 1, y, z), _block_at(x + 1, y, z),
						_block_at(x, y, z - 1), _block_at(x, y, z + 1)])
				var shaped := false
				if _smooth(block, x, y, z):
					var h := _heights(x, y, z)
					if h[0] < 1.0 or h[1] < 1.0 or h[2] < 1.0 or h[3] < 1.0:
						_add_shaped(draw, x, y, z, cx, cz, h)
						shaped = true
				if not shaped:
					_add_cube(draw, x, y, z, cx, cz, "opaque")
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
	for key in ["opaque", "plants", "trans"]:
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
	return SMOOTH_CORNERS and (block in SMOOTH_BLOCKS) and _block_at(x, y + 1, z) == Blocks.AIR

## Corner heights [NW, NE, SE, SW] of a block's top, relative to its
## bottom: 1 is its own top, 0 its bottom.
func _heights(x: int, y: int, z: int) -> PackedFloat32Array:
	return PackedFloat32Array([_surface(x, y, z, 0, 0), _surface(x, y, z, 1, 0),
		_surface(x, y, z, 1, 1), _surface(x, y, z, 0, 1)])

## The shared height of the vertex at the (cx, cz) corner of block (x, z)
## on level y — cx and cz each 0 or 1. Cached per vertex and level: four
## blocks ask for each one.
func _surface(x: int, y: int, z: int, cx: int, cz: int) -> float:
	var key := Vector3i(x + cx, y, z + cz)
	if _surface_cache.has(key):
		return _surface_cache[key]
	var top := 0.0
	for dx: int in [cx - 1, cx]:
		for dz: int in [cz - 1, cz]:
			var nx: int = x + dx
			var nz: int = z + dz
			if _firm_at(nx, y + 1, nz):
				top = 1.0          # something stands on it
			elif _firm_at(nx, y, nz):
				var block := _block_at(nx, y, nz)
				if _smooth(block, nx, y, nz):
					top = maxf(top, _opinion(nx, y, nz, cx - dx, cz - dz))
				else:
					top = 1.0      # built, or with something on it: whole
			if top >= 1.0:
				break
		if top >= 1.0:
			break
	_surface_cache[key] = top
	return top

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

## One side of a block, against air: the part of it under the ground.
## The surface crosses the face as a straight line from the height at
## one corner to the height at the other — unclamped, so it may start
## below the block's bottom or run off above its top — and the face is
## whatever lies between the bottom, the top and that line. Coloured from
## the block's side colour at the ground to its top colour at the top, so
## a cut runs green down to a brown foot rather than brown all over.
func _side_face(x: int, y: int, z: int, side: int, top: Vector2,
		base_color: Color, top_color: Color, brightness: float, emit: float) -> void:
	if top.x <= 0.0 and top.y <= 0.0:
		return
	var d := top.y - top.x
	var s0 := 0.0
	var s1 := 1.0
	if top.x <= 0.0:
		s0 = -top.x / d
	elif top.y <= 0.0:
		s1 = -top.x / d
	# Around the face: along the bottom, up the far end, back along the
	# surface line (with a bend where it runs off the top), down the near end.
	var pts: Array = [Vector2(s0, 0), Vector2(s1, 0),
		Vector2(s1, minf(1.0, top.x + d * s1))]
	if d != 0.0:
		var sk := (1.0 - top.x) / d
		if sk > s0 and sk < s1:
			pts.append(Vector2(sk, 1))
	pts.append(Vector2(s0, minf(1.0, top.x + d * s0)))
	var pair: Array = SIDE_CORNERS[side]
	var c0: Vector2 = CORNER_XZ[pair[0]]
	var c1: Vector2 = CORNER_XZ[pair[1]]
	var o := Vector3(x, y, z)
	var step: Vector2i = SIDE_STEP[side]
	var normal := Vector3(step.x, 0, step.y)
	var world: Array = []
	var cols: Array = []
	for q: Vector2 in pts:
		if not world.is_empty() and (world.back() as Vector3).is_equal_approx(
				o + Vector3(lerpf(c0.x, c1.x, q.x), q.y, lerpf(c0.y, c1.y, q.x))):
			continue
		world.append(o + Vector3(lerpf(c0.x, c1.x, q.x), q.y, lerpf(c0.y, c1.y, q.x)))
		cols.append(base_color.lerp(top_color, q.y))
	for i in range(1, world.size() - 1):
		_tri("opaque", [world[0], world[i], world[i + 1]], normal,
			[cols[0], cols[i], cols[i + 1]], brightness, emit)

## A shaped block: the top as two triangles split through its higher
## diagonal, each open side up to the surface line, and a bottom when
## there is nothing beneath. Sides against another solid block draw
## nothing: the surface is shared, so there is nothing left bare.
func _add_shaped(block: int, x: int, y: int, z: int, cx: int, cz: int,
		h: PackedFloat32Array) -> void:
	var base_color := Blocks.LK_COLOR[block]
	var top_color := Blocks.LK_TOP[block]
	var jitter := _jitter(x, y, z, cx, cz, Blocks.LK_ROUGH[block])
	var emit := Blocks.LK_EMIT[block]
	var o := Vector3(x, y, z)
	var p: Array = []
	for i in 4:
		var c: Vector2 = CORNER_XZ[i]
		p.append(o + Vector3(c.x, h[i], c.y))
	# Split through the diagonal whose two corners are LEVEL, so a block
	# with one corner out of line is a flat triangle and a sloped one —
	# flat from the midline — rather than a ridge from that corner to
	# the far one. Where neither is level, or both are, the higher.
	var d02 := absf(h[0] - h[2])
	var d13 := absf(h[1] - h[3])
	var through_02 := d02 < d13 if d02 != d13 else h[0] + h[2] >= h[1] + h[3]
	var tris: Array = [[0, 1, 2], [0, 2, 3]] if through_02 else [[1, 2, 3], [1, 3, 0]]
	for t: Array in tris:
		var a: Vector3 = p[t[0]]
		var bpt: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var n := (bpt - a).cross(c - a).normalized()
		if n.y < 0.0:
			n = -n
		# Lit between a side and a top, by how far it tips.
		var bright := lerpf((SHADE_X + SHADE_Z) * 0.5, SHADE_TOP, clampf(n.y, 0.0, 1.0)) * jitter
		_tri("opaque", [a, bpt, c], n, [top_color, top_color, top_color], bright, emit)
	for side in 4:
		var step: Vector2i = SIDE_STEP[side]
		if _is_opaque_at(x + step.x, y, z + step.y):
			continue
		var pair: Array = SIDE_CORNERS[side]
		var shade := SHADE_Z if side % 2 == 0 else SHADE_X
		_side_face(x, y, z, side, Vector2(h[pair[0]], h[pair[1]]),
			base_color, top_color, shade * jitter, emit)
	if not _is_opaque_at(x, y - 1, z):
		_tri("opaque", [o, o + Vector3(1, 0, 0), o + Vector3(1, 0, 1)], Vector3.DOWN,
			[base_color, base_color, base_color], SHADE_BOTTOM * jitter, emit)
		_tri("opaque", [o, o + Vector3(1, 0, 1), o + Vector3(0, 0, 1)], Vector3.DOWN,
			[base_color, base_color, base_color], SHADE_BOTTOM * jitter, emit)

## LAMPS CLOSE TOGETHER BECOME ONE, and the strongest come first. A
## chunk keeps a capped number of lamps (chunk_view.light_cap), and it
## used to keep the first ones in walking order — all along one side of
## a hall, the rest dark — which read as the light dying as you walked
## across the room. Merged and sorted, the cap keeps the brightest,
## spread across the chunk, and each reaches further.
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

	for face_index in 6:
		var face: Array = FACES[face_index]
		var n: Vector3i = face[0]
		var neighbor := _block_at(x + n.x, y + n.y, z + n.z)
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
		var corner_signs := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
		if not translucent:
			for i in 4:
				var cs: Vector2i = corner_signs[i]
				var s1 := _occludes(x + n.x + u.x * cs.x, y + n.y + u.y * cs.x, z + n.z + u.z * cs.x)
				var s2 := _occludes(x + n.x + v.x * cs.y, y + n.y + v.y * cs.y, z + n.z + v.z * cs.y)
				var c := _occludes(x + n.x + u.x * cs.x + v.x * cs.y,
					y + n.y + u.y * cs.x + v.y * cs.y, z + n.z + u.z * cs.x + v.z * cs.y)
				ao[i] = 3.0 if (s1 and s2) else float(int(s1) + int(s2) + int(c))

		var start: int = _verts[key].size()
		var pattern := int(Blocks.LK_PATTERN_TOP[block] if n.y != 0
			else Blocks.LK_PATTERN_SIDE[block])
		var face_uvs := [Vector2(pattern, 1), Vector2(pattern + 0.999, 1),
			Vector2(pattern + 0.999, 0), Vector2(pattern, 0)]
		for i in 4:
			var cs: Vector2i = corner_signs[i]
			var vert := center + half_u * float(cs.x) + half_v * float(cs.y)
			if top_y != 1.0 and vert.y > y + top_y:
				vert.y = y + top_y
			_verts[key].append(vert)
			_normals[key].append(Vector3(n))
			_uvs[key].append(face_uvs[i])
			var brightness := shade * jitter * (1.0 - ao_step * ao[i])
			var out := Color(color.r * brightness, color.g * brightness, color.b * brightness, color.a)
			_colors[key].append(out)
			# Leaves sway everywhere; liquids wave only on their surface.
			var vertex_sway := sway
			if is_liquid:
				vertex_sway = 1.0 if n.y == 1 else 0.0
			_uv2s[key].append(Vector2(vertex_sway, emit))
		# Flip the quad diagonal to match the AO gradient (kills the classic
		# voxel AO anisotropy artifact).
		# Godot front faces wind clockwise.
		if ao[0] + ao[2] <= ao[1] + ao[3]:
			for index in [0, 2, 1, 0, 3, 2]:
				_indices[key].append(start + index)
		else:
			for index in [1, 3, 2, 1, 0, 3]:
				_indices[key].append(start + index)

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

func _add_shape(block: int, shape: int, x: int, y: int, z: int, cx: int, cz: int) -> void:
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
	var key := "trans" if shape == 6 else "opaque"
	var color := Blocks.LK_COLOR[block]
	var jitter := _jitter(x, y, z, cx, cz)
	var origin := Vector3(x, y, z)
	for box: Array in boxes:
		var bmin: Vector3 = box[0]
		var bmax: Vector3 = box[1]
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
		Blocks.SAPLING, Blocks.BERRY_BUSH, Blocks.DEAD_BUSH:
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
			Vector3(a.x, y, a.z), Vector3(b.x, y, b.z),
			Vector3(b.x, y + tall, b.z), Vector3(a.x, y + tall, a.z),
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

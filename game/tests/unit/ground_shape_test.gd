extends TestCase
## The shape of the ground, point by point. See the note at the top of
## Mesher, and Mesher._point.
##
## Worth a test because it is a picture, and a wrong picture fails no
## other check. Every one of these started as something visible and
## wrong: a diagonal hillside as a field of pyramids with holes between
## them; then as rows of half-height panels; then as a washboard of hard
## chevron ridges; then as even ground covered in little dark notches
## where every step had reopened by a hair.
##
## The rules the shape is FOR:
##   - flat ground is flat, and exactly where the blocks put it,
##   - a step of one level closes into a ramp, with the two points
##     either side of it landing on the SAME spot,
##   - a hillside rises evenly, whichever way it runs,
##   - a cliff is a flat vertical wall,
##   - the same is true UNDER the ground — a cave roof, the inside of a
##     hole somebody dug — because none of it is a special case,
##   - anything built keeps its corners and the ground meets them,
##   - and the whole thing is closed.

const SIZE := 16

## A BYTE offset: block ids are u16 pairs. See WorldGen.bidx.
func _at(x: int, y: int, z: int) -> int:
	return ((y * SIZE + z) * SIZE + x) << 1

## Ground whose height at each column is `height(x, z)`, out of grass.
func _ground(height: Callable) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H * 2)
	data.fill(Blocks.AIR)
	for z in SIZE:
		for x in SIZE:
			var top: int = height.call(x, z)
			for y in top:
				data.encode_u16(_at(x, y, z), Blocks.GRASS)
	return data

## A built chunk, with the lattice flat unless `rough` says otherwise.
## The roughness is tested on its own further down.
func _built(data: PackedByteArray, rough := 0.0, neighbors := {}, cx := 0) -> Mesher:
	var mesher := Mesher.new()
	mesher.rough = rough
	mesher.build(data, neighbors, cx, 0)
	return mesher

# ---- the shape the blocks ask for ---------------------------------------

func test_flat_ground_is_flat_and_where_the_blocks_put_it() -> void:
	# Four blocks under a point and four empty over it is exactly half
	# full, and half full is where the surface is — so nothing moves.
	var m := _built(_ground(func(_x: int, _z: int) -> int: return 4))
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			equal(m._fullness(x, 4, z), 0.5, "a point on a plain is half full")
			equal(m._point(x, 4, z), Vector3(x, 4, z),
				"...so it stays exactly where the blocks put it")

func test_a_step_of_one_level_closes_into_a_ramp() -> void:
	# THE RULE THE WHOLE SURFACE EXISTS FOR, and the one that was hardest
	# to keep. The point above the step and the point below it both slide
	# toward each other along the line between them, read the same two
	# fullnesses, and stop at the SAME place. Anything that leaves them a
	# hair apart reopens the step as a sliver of vertical face — which is
	# what covered the ground in little dark notches.
	for rough: float in [0.0, Mesher.ROUGH]:
		var m := _built(_ground(func(_x: int, z: int) -> int:
			return 12 if z < 8 else 11), rough)
		var above := m._point(5, 12, 8)
		var below := m._point(5, 11, 8)
		equal(above, below,
			"the two points either side of the step land on the same spot (rough %.2f)" % rough)
		check(above.y > 11.0 and above.y < 12.0,
			"...somewhere between the two levels: %s" % above)

func test_a_hillside_rises_evenly() -> void:
	# Ground climbing diagonally: a step in x AND a step in z at once,
	# which is the shape that came out as a washboard for the longest.
	# Down any line across it the surface has to rise by the same amount
	# every time; a rise that alternates is a field of ridges.
	var m := _built(_ground(func(x: int, z: int) -> int:
		return clampi(20 + int(floor((x + z) * 0.5)), 4, 40)))
	var last := 0.0
	for x in range(4, 12):
		var top: int = clampi(20 + int(floor((x + 8) * 0.5)), 4, 40)
		var here := m._point(x, top, 8).y
		if x > 4:
			check(absf((here - last) - 0.5) < 0.001,
				"the hillside rises half a level per column, evenly (at x=%d: %+.3f)"
					% [x, here - last])
		last = here

func test_a_cliff_is_a_flat_vertical_wall() -> void:
	# The one place a vertical face belongs. All the way up the face the
	# surface stays in the plane of the blocks; only the lip at the top
	# and the foot at the bottom round off.
	var m := _built(_ground(func(_x: int, z: int) -> int: return 16 if z < 8 else 8))
	for y in range(10, 15):
		equal(m._point(5, y, 8).z, 8.0,
			"the face of the cliff is flat at y=%d" % y)

func test_the_roof_of_a_cave_is_smoothed_TOO() -> void:
	# NOTHING HERE KNOWS WHICH WAY IS UP. The surface is the boundary
	# between matter and nothing, so the underside of the rock over a
	# cave is the same kind of surface as the hillside above it — which
	# is the whole reason for drawing it this way rather than as a height
	# map. A square roof with a step in it comes out sloped.
	var data := _ground(func(_x: int, _z: int) -> int: return 20)
	for z in range(4, 12):
		for x in range(4, 12):
			for y in range(6, 12 if z < 8 else 13):
				data.encode_u16(_at(x, y, z), Blocks.AIR)
	var m := _built(data)
	var above := m._point(6, 12, 8)
	var below := m._point(6, 13, 8)
	equal(above, below, "the two points either side of the step in the roof meet")
	check(above.y > 12.0 and above.y < 13.0,
		"...between the two levels, so the roof slopes: %s" % above)

func test_anything_built_keeps_the_ground_square_against_it() -> void:
	# A plank floor laid on the ground. It is drawn as the box it is, and
	# ground that had smoothed away from its flat square faces would
	# leave a slot down the join.
	var data := _ground(func(_x: int, _z: int) -> int: return 4)
	data.encode_u16(_at(8, 4, 8), Blocks.PLANKS)
	var m := _built(data, Mesher.ROUGH)
	for corner: Vector2i in [Vector2i(8, 8), Vector2i(9, 8), Vector2i(9, 9), Vector2i(8, 9)]:
		check(m._square_at(corner.x, 4, corner.y),
			"the points under the planks are held")
		equal(m._point(corner.x, 4, corner.y), Vector3(corner.x, 4, corner.y),
			"...so they do not move at all")

# ---- the roughness -------------------------------------------------------

func test_the_roughness_moves_the_ground_but_not_much() -> void:
	var m := _built(_ground(func(_x: int, _z: int) -> int: return 4), Mesher.ROUGH)
	var lowest := 4.0
	var highest := 4.0
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			var here := m._point(x, 4, z)
			equal(here.x, float(x), "flat ground only ever moves up and down")
			equal(here.z, float(z), "...on both of the other axes")
			check(absf(here.y - 4.0) <= 1.0, "and not by much: %s" % here)
			lowest = minf(lowest, here.y)
			highest = maxf(highest, here.y)
	check(highest - lowest > 0.05,
		"...but it is not a plane (%.3f .. %.3f)" % [lowest, highest])

func test_with_the_roughness_off_the_ground_is_what_the_map_says() -> void:
	var m := _built(_ground(func(_x: int, _z: int) -> int: return 4), 0.0)
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			equal(m._point(x, 4, z), Vector3(x, 4, z),
				"flat ground with no roughness is a plane")

# ---- every point is shared -----------------------------------------------

func test_points_line_up_across_a_chunk_border() -> void:
	# A point on the border is worked out twice, once by each chunk, from
	# its own blocks and nothing else. The two answers have to be the
	# same number — not nearly, exactly, or the two pieces of ground are
	# not the same edge and there is a hole between them.
	var data := _ground(func(x: int, z: int) -> int:
		return 4 + (1 if x % 4 == 0 else 0) + (1 if z % 5 == 0 else 0))
	var west := _built(data, Mesher.ROUGH, {Vector2i(1, 0): data}, 0)
	var east := _built(data, Mesher.ROUGH, {Vector2i(-1, 0): data}, 1)
	for z in range(2, SIZE - 2):
		for y in range(3, 7):
			equal(west._point(SIZE, y, z) + Vector3(-SIZE, 0, 0),
				east._point(0, y, z),
				"the border point at y=%d z=%d reads the same from both chunks" % [y, z])

# ---- and it is closed ----------------------------------------------------

## Every edge of the mesh is shared by exactly two faces: a seam, a
## missing face or a stray sliver all show up here as an edge with
## nothing on its other side. The same property is checked on real
## generated terrain, at scale and in four worlds, by
## tests/mesh_watertight.gd.
func test_the_ground_has_no_holes_in_it() -> void:
	for rough: float in [0.0, Mesher.ROUGH]:
		var data := _ground(func(x: int, z: int) -> int:
			return clampi(6 + int(floor((x + z) * 0.5)), 3, 14))
		# Things that are not ground, on it, beside it and under it.
		data.encode_u16(_at(3, 6, 12), Blocks.GLOWSTONE)
		data.encode_u16(_at(9, 7, 3), Blocks.GLASS)
		data.encode_u16(_at(12, 9, 12), Blocks.PLANKS)
		data.encode_u16(_at(10, 8, 10), Blocks.TALL_GRASS)
		data.encode_u16(_at(5, 4, 5), Blocks.AIR)
		data.encode_u16(_at(2, 4, 2), Blocks.WATER)
		for y in range(9, 13):
			data.encode_u16(_at(11, y, 11), Blocks.LOG)
		_equal_no_holes(data, rough)

func test_a_hole_dug_in_the_ground_has_no_holes_in_it() -> void:
	# What the digger leaves: a crater blown out of a hillside, which is
	# all underside and wall and was a heap of cubes before any of this.
	var data := _ground(func(_x: int, _z: int) -> int: return 16)
	for z in SIZE:
		for x in SIZE:
			for y in range(4, 20):
				if Vector3(x, y, z).distance_to(Vector3(8, 16, 8)) < 5.5:
					data.encode_u16(_at(x, y, z), Blocks.AIR)
	_equal_no_holes(data, Mesher.ROUGH)

func test_a_cave_under_the_ground_has_no_holes_in_it() -> void:
	var data := _ground(func(_x: int, _z: int) -> int: return 20)
	for z in range(3, 13):
		for x in range(3, 13):
			for y in range(6, 12 if (x + z) % 5 < 2 else 13):
				data.encode_u16(_at(x, y, z), Blocks.AIR)
	_equal_no_holes(data, Mesher.ROUGH)

func _equal_no_holes(data: PackedByteArray, rough: float) -> void:
	var mesher := Mesher.new()
	mesher.rough = rough
	var built: Dictionary = mesher.build(data, {}, 0, 0)
	var arrays: Array = built["opaque"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var edges := {}
	for i in range(0, index.size(), 3):
		for k in 3:
			var a := verts[index[i + k]].snapped(Vector3.ONE * 0.00002)
			var b := verts[index[i + (k + 1) % 3]].snapped(Vector3.ONE * 0.00002)
			edges["%s>%s" % [a, b]] = int(edges.get("%s>%s" % [a, b], 0)) + 1
	var open: Array = []
	for key: String in edges.keys():
		var parts := key.split(">")
		if int(edges.get("%s>%s" % [parts[1], parts[0]], 0)) == int(edges[key]):
			continue
		# The rim of the chunk and the floor of the world: what would
		# close those was never meshed. A block of slack because a point
		# is not on the lattice — it slides.
		var a := _point_of(parts[0])
		var b := _point_of(parts[1])
		if (a.y <= 0.001 and b.y <= 0.001) \
				or (a.x <= 1.001 and b.x <= 1.001) \
				or (a.x >= SIZE - 1.001 and b.x >= SIZE - 1.001) \
				or (a.z <= 1.001 and b.z <= 1.001) \
				or (a.z >= SIZE - 1.001 and b.z >= SIZE - 1.001):
			continue
		open.append(key)
	equal(open.size(), 0, "edges with nothing on the other side (rough %.2f): %s"
		% [rough, open.slice(0, 6)])

func _point_of(text: String) -> Vector3:
	var bits := text.substr(1, text.length() - 2).split(", ")
	return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))

# ---- what stands on it ---------------------------------------------------

func test_a_plant_comes_down_with_the_ground_it_stands_on() -> void:
	# Ground with a tuft on it: the tuft's feet are at the average of the
	# four points under it, not at the block's own top, or it stands in
	# the air over a dip.
	var data := _ground(func(_x: int, _z: int) -> int: return 4)
	data.encode_u16(_at(8, 4, 8), Blocks.TALL_GRASS)
	var m := _built(data, Mesher.ROUGH)
	check(absf(m._ground_drop(8, 4, 8)) > 0.0,
		"the ground under the tuft has moved (%.3f)" % m._ground_drop(8, 4, 8))
	# A tuft is one of the plants ChunkView stands as a MODEL rather than
	# as crossed quads, so what the mesher hands over is how far the
	# ground under its column has come down — see Mesher._ground_drop.
	var mesher := Mesher.new()
	mesher.rough = Mesher.ROUGH
	var built: Dictionary = mesher.build(data, {}, 0, 0)
	var roots: PackedFloat32Array = built["roots"]
	check(absf(roots[8 * SIZE + 8]) > 0.0,
		"and the tuft is told about it (%.3f)" % roots[8 * SIZE + 8])

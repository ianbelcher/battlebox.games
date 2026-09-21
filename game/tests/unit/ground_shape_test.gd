extends TestCase
## The shape of the ground, point by point. See Mesher's header and
## Mesher._skin_corner.
##
## Worth a test because it is a picture, and a wrong picture fails no
## other check: a diagonal hillside was a field of pyramids with holes
## between them for a while, then a row of half-height panels with walls
## between them, and the world was "correct" throughout.
##
## The rules pinned here are the ones the shape is FOR:
##   - a step of one level has nothing vertical in it,
##   - a diagonal hillside is a single plane,
##   - a fall of two levels or more is a square cliff,
##   - everything touching a point agrees about where it is,
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

## The four corners of one column's piece of skin, NW, NE, SE, SW, as
## absolute heights — which is how the mesher itself reads them.
func _corners(m: Mesher, x: int, z: int) -> PackedFloat64Array:
	var top := m._top_of(x, z)
	var out := PackedFloat64Array()
	for c: Vector2 in Mesher.CORNER_XZ:
		out.append(m._skin_corner(x, z, int(c.x), int(c.y), top))
	return out

## A hillside rising one block per step diagonally: solid at level y
## where x + z >= 8 + y, so every tread's edge is a diagonal of blocks
## each open on two sides.
func _diagonal(x: int, z: int) -> int:
	return clampi(x + z - 7, 1, 6)

# ---- the shape the blocks ask for ---------------------------------------

func test_a_step_of_one_level_has_nothing_vertical_in_it() -> void:
	# The rule the whole surface exists for. Two columns a single level
	# apart read the SAME height for the corners between them — halfway
	# — so their two pieces of skin meet edge to edge and the step is a
	# ramp two columns wide with no face standing in it.
	var m := _built(_ground(func(_x: int, z: int) -> int: return 2 if z >= 8 else 1))
	var high := _corners(m, 5, 8)       # ground to y = 2
	var low := _corners(m, 5, 7)        # ground to y = 1, one level down
	equal(high[0], 1.5, "the high column's northern corners are halfway down")
	equal(high[1], 1.5, "...both of them")
	equal(high[2], 2.0, "and its southern corners are still up")
	equal(low[3], 1.5, "the low column's southern corners come up to meet them")
	equal(low[2], 1.5, "...both of them")
	equal(high[0], low[3], "so the two columns agree about the corner they share")
	equal(high[1], low[2], "...and about the other one")

func test_a_diagonal_hillside_is_one_plane() -> void:
	# The picture that gave this away: ground climbing diagonally used to
	# come out as a field of little pyramids with holes between them,
	# because a cell with no block in it had no face to draw. Down the
	# fall line the points simply climb, by the same amount each time.
	# A clean diagonal with no floor and no ceiling in the way, so the
	# fall line is a straight climb from end to end.
	var m := _built(_ground(func(x: int, z: int) -> int: return clampi(x + z - 4, 1, 14)))
	var steps: Array = []
	for i in range(4, 10):
		steps.append(m._skin_corner(i, i, 0, 0, m._top_of(i, i)))
	# Two levels per step down the diagonal, because a step diagonally is
	# a step along both axes at once.
	for i in range(1, steps.size()):
		var rise: float = steps[i] - steps[i - 1]
		check(absf(rise - 2.0) < 0.001,
			"the hillside climbs evenly, with no tread flat and none doubled: %s" % [steps])

func test_a_fall_of_two_levels_is_a_square_cliff() -> void:
	# The one place a vertical face belongs. The points on both lips stay
	# on the lattice, so the wall is a wall and the blocks of it are the
	# blocks they are — and a cave coming out of a cliff face is open
	# rather than plastered over.
	var m := _built(_ground(func(_x: int, z: int) -> int: return 4 if z >= 8 else 1))
	var top := _corners(m, 5, 8)
	var foot := _corners(m, 5, 7)
	equal(top[0], 4.0, "the top of the cliff keeps its corner")
	equal(top[1], 4.0, "...both of them")
	equal(foot[3], 1.0, "and the ground at its foot keeps its own")
	equal(foot[2], 1.0, "...both of them")

func test_a_hillside_falling_two_levels_across_a_corner_is_still_a_slope() -> void:
	# ...but only side by side. Any hillside falls two levels across the
	# diagonal of a corner — 3, 2, 2, 1 around one point — and reading
	# that as a cliff would square off every slope in the world.
	var m := _built(_ground(func(x: int, z: int) -> int: return 3 - mini(x, 1) - mini(z, 1)))
	var mid := m._skin_corner(1, 1, 0, 0, m._top_of(1, 1))
	check(absf(mid - 2.0) < 0.001,
		"the point in the middle of the fall is the average of it: %s" % mid)

func test_anything_standing_on_the_ground_stands_flush_on_it() -> void:
	# A trunk, a wall, a crate: the column under it keeps its points
	# where the blocks are, so the thing sits flat on the ground instead
	# of over a dip — and the ground beside it comes up to meet its foot.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	for y in range(3, 7):
		data.encode_u16(_at(8, y, 8), Blocks.LOG)
	var m := _built(data, Mesher.ROUGH)
	check(m._held_at(8, 8), "the column under the trunk is held")
	for c in _corners(m, 8, 8):
		equal(c, 3.0, "every corner under the trunk is at the block's top")
	check(not m._held_at(8, 5), "a column with nothing on it is not")

func test_a_canopy_overhead_does_not_hold_the_ground_down() -> void:
	# Only what RESTS on the ground holds it square. Leaves three blocks
	# up are standing on nothing, and counting them flattened the ground
	# under every tree in the world.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	for z in range(6, 11):
		for x in range(6, 11):
			data.encode_u16(_at(x, 7, z), Blocks.LEAVES)
	var m := _built(data, Mesher.ROUGH)
	check(not m._held_at(8, 8), "the ground under a canopy is ordinary ground")

func test_the_ground_beside_something_square_stays_on_the_lattice() -> void:
	# A glowstone standing on otherwise flat ground. It is not ground, so
	# it is drawn as the box it is, with flat square faces — and the
	# ground NEXT to it has to come up to meet them, or there is a slot
	# down the join.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	data.encode_u16(_at(8, 3, 8), Blocks.GLOWSTONE)
	var m := _built(data, Mesher.ROUGH)
	var beside := _corners(m, 7, 8)
	equal(beside[1], 3.0, "the point the glowstone shares with the ground beside it")
	equal(beside[2], 3.0, "...both of them")
	check(beside[0] < 3.0, "while the ground away from it still rolls")

func test_anything_built_is_not_ground() -> void:
	var data := _ground(func(_x: int, _z: int) -> int: return 2)
	data.encode_u16(_at(8, 1, 8), Blocks.PLANKS)
	var m := _built(data)
	equal(m._top_of(8, 8), 1.0,
		"a floor somebody laid is not the top of a column of ground")

# ---- every point is shared -----------------------------------------------

func test_every_column_touching_a_point_reads_the_same_height_for_it() -> void:
	# The property that makes a seam impossible. Up to four columns meet
	# at a point and all of them draw to it; if any two disagree there is
	# a slit between them, whatever the rest of the rules say.
	for rough: float in [0.0, Mesher.ROUGH]:
		var m := _built(_ground(_diagonal), rough)
		var seams := 0
		for z in range(2, SIZE - 2):
			for x in range(2, SIZE - 2):
				var mine := _corners(m, x, z)
				var east := _corners(m, x + 1, z)
				var south := _corners(m, x, z + 1)
				# Torn columns are allowed to disagree: that IS the cliff.
				if not m._torn(m._top_of(x, z), m._top_of(x + 1, z)):
					if mine[1] != east[0] or mine[2] != east[3]:
						seams += 1
				if not m._torn(m._top_of(x, z), m._top_of(x, z + 1)):
					if mine[3] != south[0] or mine[2] != south[1]:
						seams += 1
		equal(seams, 0, "every column agrees about every point it touches (rough %.2f)" % rough)

func test_points_line_up_across_a_chunk_border() -> void:
	# Ground that repeats every 16 columns across, so the two chunks meet
	# as one hillside rather than at a cliff.
	var data := _ground(func(x: int, z: int) -> int:
		return 3 + (1 if x % 4 == 0 else 0) + (1 if z % 5 == 0 else 0))
	var west := _built(data, Mesher.ROUGH, {Vector2i(1, 0): data}, 0)
	var east := _built(data, Mesher.ROUGH, {Vector2i(-1, 0): data}, 1)
	for z in range(2, SIZE - 2):
		var a := _corners(west, SIZE - 1, z)
		var b := _corners(east, 0, z)
		equal(a[1], b[0], "the border point at z=%d reads the same from both chunks" % z)
		equal(a[2], b[3], "...and its southern neighbour")

# ---- the roughness -------------------------------------------------------

func test_flat_ground_is_roughened_but_not_by_much() -> void:
	var m := _built(_ground(func(_x: int, _z: int) -> int: return 3), Mesher.ROUGH)
	var lowest := 3.0
	var highest := 0.0
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			for c in _corners(m, x, z):
				check(c <= 3.0 and c >= 3.0 - Mesher.ROUGH - 0.0001,
					"a point of flat ground falls at most the roughness: %s" % c)
				lowest = minf(lowest, c)
				highest = maxf(highest, c)
	check(lowest < 2.98 and highest > 2.99,
		"and it is not a plane (%.3f .. %.3f)" % [lowest, highest])

func test_with_the_roughness_off_the_ground_is_exactly_what_the_map_says() -> void:
	var m := _built(_ground(func(_x: int, _z: int) -> int: return 3), 0.0)
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			for c in _corners(m, x, z):
				equal(c, 3.0, "flat ground with no roughness is a plane")

func test_the_roughness_does_not_move_a_cliff_off_the_lattice() -> void:
	# A wall of ground with open ground in front of it: the lip has to
	# stay square or the blocks of the wall show through it.
	var data := _ground(func(x: int, _z: int) -> int: return 8 if x >= 8 else 1)
	var m := _built(data, Mesher.ROUGH)
	for z in range(2, SIZE - 2):
		var lip := _corners(m, 8, z)
		equal(lip[0], 8.0, "the lip of the cliff is on the lattice")
		equal(lip[3], 8.0, "...both corners of it")

# ---- and it is closed ----------------------------------------------------

## Every edge of the mesh is shared by exactly two faces: a seam, a
## missing face or a stray sliver all show up here as an edge with
## nothing on its other side. The same property is checked on real
## generated terrain, at scale, by tests/mesh_watertight.gd.
func test_the_ground_has_no_holes_in_it() -> void:
	for rough: float in [0.0, Mesher.ROUGH]:
		var data := _ground(_diagonal)
		# Things that are not ground, on it, beside it and under it.
		data.encode_u16(_at(3, 1, 12), Blocks.GLOWSTONE)
		data.encode_u16(_at(9, 2, 3), Blocks.GLOWSTONE)
		data.encode_u16(_at(12, 4, 12), Blocks.PLANKS)
		data.encode_u16(_at(10, 3, 10), Blocks.TALL_GRASS)
		data.encode_u16(_at(5, 1, 5), Blocks.AIR)
		data.encode_u16(_at(2, 1, 2), Blocks.WATER)
		for y in range(6, 10):
			data.encode_u16(_at(11, y, 11), Blocks.LOG)
		_equal_no_holes(data, rough)

func test_a_cliff_with_a_cave_in_its_face_has_no_holes_either() -> void:
	# The shape that kept tearing: a tall column of ground beside a low
	# one, with a hollow in the tall one at the height of the face.
	var data := _ground(func(x: int, _z: int) -> int: return 10 if x >= 8 else 3)
	for z in range(4, 12):
		for x in range(8, 12):
			data.encode_u16(_at(x, 5, z), Blocks.AIR)
			data.encode_u16(_at(x, 6, z), Blocks.AIR)
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
			var key := "%s>%s" % [a, b]
			edges[key] = int(edges.get(key, 0)) + 1
	var open: Array = []
	for key: String in edges.keys():
		var parts := key.split(">")
		var back := "%s>%s" % [parts[1], parts[0]]
		if int(edges.get(back, 0)) == int(edges[key]):
			continue
		# The rim of the chunk and the floor of the world: what would
		# close those was never meshed.
		var a := _point(parts[0])
		var b := _point(parts[1])
		if (a.y <= 0.001 and b.y <= 0.001) \
				or (a.x <= 0.001 and b.x <= 0.001) \
				or (a.x >= SIZE - 0.001 and b.x >= SIZE - 0.001) \
				or (a.z <= 0.001 and b.z <= 0.001) \
				or (a.z >= SIZE - 0.001 and b.z >= SIZE - 0.001):
			continue
		open.append(key)
	equal(open.size(), 0, "edges with nothing on the other side (rough %.2f): %s"
		% [rough, open.slice(0, 8)])

func _point(text: String) -> Vector3:
	var bits := text.substr(1, text.length() - 2).split(", ")
	return Vector3(float(bits[0]), float(bits[1]), float(bits[2]))

# ---- what stands on it ---------------------------------------------------

func test_a_plant_comes_down_with_the_ground_it_stands_on() -> void:
	# Ground with a tuft on it: the tuft's feet are at the average of
	# the four points under it, not at the block's own top.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	data.encode_u16(_at(8, 3, 8), Blocks.TALL_GRASS)
	var m := _built(data, Mesher.ROUGH)
	var under := m._ground_drop(8, 3, 8)
	check(under > 0.0, "the ground under the tuft has fallen (%.3f)" % under)
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	var arrays: Array = built["plants"]
	var lowest := 99.0
	for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if absf(v.x - 8.5) < 0.6 and absf(v.z - 8.5) < 0.6:
			lowest = minf(lowest, v.y)
	check(lowest < 3.0 - 0.001,
		"so the tuft's feet are in it, not above it (%.3f)" % lowest)

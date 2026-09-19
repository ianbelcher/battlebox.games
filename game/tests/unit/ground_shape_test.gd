extends TestCase
## The shape of the ground, corner by corner. See Mesher._heights.
##
## Worth a test because it is a picture, and a wrong picture fails no
## other check: a diagonal hillside was a row of pyramids for a while,
## then a row of half-height panels with walls between them, and the
## world was "correct" throughout.

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

## The bare shape rule — whole-block ramps, no rolling — unless `dip`
## says otherwise. The rolling is tested on its own at the bottom.
func _shaped(data: PackedByteArray, dip := 0.0, neighbors := {}, cx := 0) -> Mesher:
	var mesher := Mesher.new()
	mesher.dip = dip
	mesher.build(data, neighbors, cx, 0)
	return mesher

## A hillside rising one block per step diagonally: solid at level y
## where x + z >= 8 + y, so every tread's edge is a diagonal of blocks
## each open on two sides.
func _diagonal(x: int, z: int) -> int:
	return clampi(x + z - 7, 1, 6)

func test_a_diagonal_edge_is_flat_from_the_midline() -> void:
	var m := _shaped(_ground(_diagonal))
	# Block (6, 5) — x + z = 11 — is on the edge of tread 3: (5, 5) and
	# (6, 4) are open, (7, 5) and (6, 6) solid. Its outer corner drops
	# one block and the rest of its top stays up: flat from the midline,
	# never a ridge and never a cut deeper than a block.
	var h := m._heights(6, 3, 5)
	equal(h, PackedFloat32Array([0, 1, 1, 1]),
		"the outer corner drops a block, the other three stay up: %s" % [h])
	# And the tread below reads the same height for the vertex they
	# share: (5, 5) at level 2 meets (6, 5) at level 3 at vertex (6, 5).
	var below := m._heights(5, 2, 5)
	equal(2.0 + below[1], 3.0 + h[0], "one vertex, one height, across levels")

func test_every_corner_is_whole_or_nothing() -> void:
	var m := _shaped(_ground(_diagonal))
	for z in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			var y := _diagonal(x, z) - 1
			for c in m._heights(x, y, z):
				check(c == 0.0 or c == 1.0,
					"a corner is a whole block up or down at (%d,%d): %s" % [x, z, c])

func test_neighbours_never_disagree_about_a_shared_vertex() -> void:
	var m := _shaped(_ground(_diagonal))
	var seams := 0
	for z in range(1, SIZE - 2):
		for x in range(1, SIZE - 2):
			var y := _diagonal(x, z) - 1
			var h := m._heights(x, y, z)
			if _diagonal(x + 1, z) - 1 == y:
				var e := m._heights(x + 1, y, z)
				if h[1] != e[0] or h[2] != e[3]:
					seams += 1
			if _diagonal(x, z + 1) - 1 == y:
				var s := m._heights(x, y, z + 1)
				if h[3] != s[0] or h[2] != s[1]:
					seams += 1
	equal(seams, 0, "two blocks of ground at the same level agree along their shared edge")

func test_a_straight_step_is_a_ramp() -> void:
	var m := _shaped(_ground(func(_x: int, z: int) -> int: return 2 if z >= 8 else 1))
	equal(m._heights(5, 1, 8), PackedFloat32Array([0, 0, 1, 1]),
		"open to the north, solid to the south: the north corners drop")

func test_a_lone_block_stays_a_block() -> void:
	var m := _shaped(_ground(func(x: int, z: int) -> int: return 2 if x == 8 and z == 8 else 1))
	equal(m._heights(8, 1, 8), PackedFloat32Array([1, 1, 1, 1]),
		"nothing beside it slopes, so nothing pulls its corners down")
	# And the ground around it is flat: the block stands on whole corners.
	equal(m._heights(7, 0, 8), PackedFloat32Array([1, 1, 1, 1]),
		"the ground under a block does not dip beside it")

func test_a_one_wide_hole_keeps_its_walls() -> void:
	var m := _shaped(_ground(func(x: int, z: int) -> int: return 1 if x == 8 and z == 8 else 2))
	equal(m._heights(8, 1, 7), PackedFloat32Array([1, 1, 1, 1]),
		"a hole one block wide is a hole, not a funnel")

func test_anything_solid_holds_the_ground_up_beside_it() -> void:
	# A step with a glowstone set into the lower ground right in front
	# of it. Glowstone is not opaque, but it is solid, and the step must
	# not slope toward it as if it were air: the glowstone draws no face
	# against the step, so a slope there would open the glowstone up.
	var data := _ground(func(_x: int, z: int) -> int: return 2 if z >= 8 else 1)
	data[_at(8, 1, 7)] = Blocks.GLOWSTONE
	var m := _shaped(data)
	equal(m._heights(8, 1, 8), PackedFloat32Array([1, 1, 1, 1]),
		"the step stays whole against the glowstone")
	equal(m._heights(7, 1, 8), PackedFloat32Array([0, 1, 1, 1]),
		"and its neighbour keeps the shared corner up")

## Every edge of the ground's mesh is shared by exactly two faces: a
## seam, a missing face or a stray sliver all show up here as an edge
## with nothing on its other side.
func test_the_ground_has_no_holes_in_it() -> void:
	var data := _ground(_diagonal)
	# Things that are not ground, on and beside it.
	data[_at(3, 1, 12)] = Blocks.GLOWSTONE
	data[_at(9, 2, 3)] = Blocks.GLOWSTONE
	data[_at(12, 4, 12)] = Blocks.PLANKS
	data[_at(10, 3, 10)] = Blocks.TALL_GRASS
	data[_at(5, 1, 5)] = Blocks.AIR
	_equal_no_holes(data, 0.0)

func _equal_no_holes(data: PackedByteArray, dip: float) -> void:
	var mesher := Mesher.new()
	mesher.dip = dip
	var built: Dictionary = mesher.build(data, {}, 0, 0)
	var arrays: Array = built["opaque"]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var edges := {}
	for i in range(0, index.size(), 3):
		for k in 3:
			var a := verts[index[i + k]].snapped(Vector3(0.001, 0.001, 0.001))
			var b := verts[index[i + (k + 1) % 3]].snapped(Vector3(0.001, 0.001, 0.001))
			var key := "%s>%s" % [a, b]
			edges[key] = int(edges.get(key, 0)) + 1
	var open: Array = []
	for key: String in edges.keys():
		var parts := key.split(">")
		var back := "%s>%s" % [parts[1], parts[0]]
		if int(edges.get(back, 0)) != int(edges[key]):
			open.append(key)
	equal(open.size(), 0, "edges with nothing on the other side (dip %.2f): %s"
		% [dip, open.slice(0, 8)])

# ---- rolling ground (Mesher.SURFACE_DIP) ---------------------------------

func test_rolling_ground_stays_within_half_a_block_and_actually_rolls() -> void:
	var m := _shaped(_ground(func(_x: int, _z: int) -> int: return 3), Mesher.SURFACE_DIP)
	var lowest := 1.0
	for z in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			for c in m._heights(x, 2, z):
				check(c >= 1.0 - Mesher.SURFACE_DIP - 0.0001 and c <= 1.0,
					"a corner of open ground is between %.2f and 1: %s at (%d,%d)"
					% [1.0 - Mesher.SURFACE_DIP, c, x, z])
				lowest = minf(lowest, c)
	check(lowest < 0.9, "a field of open ground is not flat any more (lowest %.2f)" % lowest)

func test_rolling_neighbours_never_disagree_about_a_shared_vertex() -> void:
	var m := _shaped(_ground(_diagonal), Mesher.SURFACE_DIP)
	var seams := 0
	for z in range(1, SIZE - 2):
		for x in range(1, SIZE - 2):
			var y := _diagonal(x, z) - 1
			var h := m._heights(x, y, z)
			if _diagonal(x + 1, z) - 1 == y:
				var e := m._heights(x + 1, y, z)
				if h[1] != e[0] or h[2] != e[3]:
					seams += 1
			if _diagonal(x, z + 1) - 1 == y:
				var s := m._heights(x, y, z + 1)
				if h[3] != s[0] or h[2] != s[1]:
					seams += 1
	equal(seams, 0, "rolling ground still agrees along every shared edge")

func test_rolling_ground_has_no_holes_in_it() -> void:
	var data := _ground(_diagonal)
	data[_at(3, 1, 12)] = Blocks.GLOWSTONE
	data[_at(9, 2, 3)] = Blocks.GLOWSTONE
	data[_at(12, 4, 12)] = Blocks.PLANKS
	data[_at(10, 3, 10)] = Blocks.TALL_GRASS
	data[_at(5, 1, 5)] = Blocks.AIR
	data[_at(2, 1, 2)] = Blocks.WATER
	_equal_no_holes(data, Mesher.SURFACE_DIP)

func test_anything_built_planted_or_wet_keeps_its_corners_whole() -> void:
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	data[_at(8, 3, 8)] = Blocks.PLANKS        # a block built on the field
	data[_at(4, 3, 4)] = Blocks.TALL_GRASS    # a plant
	data[_at(12, 2, 12)] = Blocks.WATER       # a puddle set into it
	var m := _shaped(data, Mesher.SURFACE_DIP)
	# The corners of the four blocks around each thing, at the vertices
	# they share with it.
	equal(m._heights(7, 2, 8)[1], 1.0, "beside the planks, the shared corner is whole")
	equal(m._heights(7, 2, 8)[2], 1.0, "...both of them")
	equal(m._heights(3, 2, 4)[1], 1.0, "beside the plant's block, whole")
	equal(m._heights(11, 2, 12)[1], 1.0, "beside the water, whole")
	equal(m._heights(11, 2, 12)[2], 1.0, "...both of them")

func test_rolling_ground_lines_up_across_a_chunk_border() -> void:
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	var west := _shaped(data, Mesher.SURFACE_DIP, {Vector2i(1, 0): data}, 0)
	var east := _shaped(data, Mesher.SURFACE_DIP, {Vector2i(-1, 0): data}, 1)
	for z in range(1, SIZE - 1):
		var a := west._heights(SIZE - 1, 2, z)
		var b := east._heights(0, 2, z)
		equal(a[1], b[0], "the border vertex at z=%d reads the same from both chunks" % z)
		equal(a[2], b[3], "...and its southern neighbour")

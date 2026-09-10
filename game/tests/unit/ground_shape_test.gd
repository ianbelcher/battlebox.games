extends TestCase
## The shape of the ground, corner by corner. See Mesher._heights.
##
## Worth a test because it is a picture, and a wrong picture fails no
## other check: a diagonal hillside was a row of pyramids for a while,
## then a row of half-height panels with walls between them, and the
## world was "correct" throughout.

const SIZE := 16

func _at(x: int, y: int, z: int) -> int:
	return (y * SIZE + z) * SIZE + x

## Ground whose height at each column is `height(x, z)`, out of grass.
func _ground(height: Callable) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H)
	data.fill(Blocks.AIR)
	for z in SIZE:
		for x in SIZE:
			var top: int = height.call(x, z)
			for y in top:
				data[_at(x, y, z)] = Blocks.GRASS
	return data

func _shaped(data: PackedByteArray) -> Mesher:
	var mesher := Mesher.new()
	mesher.build(data, {}, 0, 0)
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
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
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
	equal(open.size(), 0, "edges with nothing on the other side: %s" % [open.slice(0, 8)])

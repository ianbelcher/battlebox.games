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

func test_a_diagonal_hillside_is_one_plane() -> void:
	var m := _shaped(_ground(_diagonal))
	# Block (6, 5) is the top of a column four high — x + z = 11 — on the
	# edge of tread 3: (5, 5) and (6, 4) are open, (7, 5) and (6, 6)
	# solid, and the ground beyond its NW corner is two steps down. Its
	# top runs straight from a block below its bottom at NW to its own
	# top at SE.
	var h := m._heights(6, 3, 5)
	equal(h, PackedFloat32Array([-1, 0, 1, 0]),
		"the outer corner cuts a block deep, the far corner is up: %s" % [h])
	# The whole hillside is that plane: every edge block, on every tread,
	# rises one per block along x and along z.
	for z in range(3, 9):
		for x in range(3, 9):
			if x + z < 10 or x + z > 12:
				continue
			var y := x + z - 8
			var c := m._heights(x, y, z)
			var nw := y + c[0]
			check(y + c[1] == nw + 1 and y + c[3] == nw + 1 and y + c[2] == nw + 2,
				"(%d,%d) lies in the plane: %s" % [x, z, c])
	# And the tread below reads the same height for the vertex they
	# share: (4, 5) at level 1 meets (5, 5) at level 2 at vertex (5, 5).
	var below := m._heights(4, 1, 5)
	var above := m._heights(5, 2, 5)
	equal(1.0 + below[1], 2.0 + above[0], "one vertex, one height, across levels")

func test_every_corner_is_whole_or_nothing() -> void:
	var m := _shaped(_ground(_diagonal))
	for z in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			var y := _diagonal(x, z) - 1
			for c in m._heights(x, y, z):
				check(c == -1.0 or c == 0.0 or c == 1.0,
					"whole blocks only at (%d,%d): %s" % [x, z, c])

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

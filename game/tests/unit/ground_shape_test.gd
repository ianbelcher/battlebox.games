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

## The bare shape rule — whole-block ramps, no corner dropped — unless
## `drop` says otherwise. Dropped corners are tested on their own below.
func _shaped(data: PackedByteArray, drop := 0.0, neighbors := {}, cx := 0) -> Mesher:
	var mesher := Mesher.new()
	mesher.drop = drop
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
	equal(h, PackedFloat64Array([0, 1, 1, 1]),
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
	equal(m._heights(5, 1, 8), PackedFloat64Array([0, 0, 1, 1]),
		"open to the north, solid to the south: the north corners drop")

func test_a_lone_block_of_ground_is_a_mound() -> void:
	# THE PRICE OF A SMOOTH DIAGONAL. A corner drops when any of the four
	# columns meeting it is open, and beside a lone block every corner
	# has three open columns — so it comes out as a little mound rather
	# than a cube. Locally it is the same shape as the notch in a
	# diagonal hillside, so no rule can slope one and not the other.
	# Anything BUILT is unaffected: those keep their corners square.
	var m := _shaped(_ground(func(x: int, z: int) -> int: return 2 if x == 8 and z == 8 else 1))
	equal(m._heights(8, 1, 8), PackedFloat64Array([0, 0, 0, 0]),
		"a lone block of natural ground slopes away on every side")
	var planks := _ground(func(_x: int, _z: int) -> int: return 1)
	planks[_at(8, 1, 8)] = Blocks.PLANKS
	var built := _shaped(planks)
	equal(built._heights(8, 1, 8), PackedFloat64Array([1, 1, 1, 1]),
		"...but a block somebody placed is still a block")
	# And the ground around it is flat: the block stands on whole corners.
	equal(m._heights(7, 0, 8), PackedFloat64Array([1, 1, 1, 1]),
		"the ground under a block does not dip beside it")

func test_a_one_wide_hole_is_a_funnel() -> void:
	# The same trade as the lone block above: the corners around a hole
	# one block wide each have an open column, so they fall into it. It
	# is the shape of a diagonal notch seen from the other side.
	var m := _shaped(_ground(func(x: int, z: int) -> int: return 1 if x == 8 and z == 8 else 2))
	var h := m._heights(8, 1, 7)
	equal(h[3], 0.0, "the ground falls into a hole one block wide")
	equal(h[0], 1.0, "and is still whole on its far side")

func test_anything_solid_holds_the_ground_up_beside_it() -> void:
	# A step with a glowstone set into the lower ground right in front
	# of it. Glowstone is not opaque, but it is solid, and the step must
	# not slope toward it as if it were air: the glowstone draws no face
	# against the step, so a slope there would open the glowstone up.
	var data := _ground(func(_x: int, z: int) -> int: return 2 if z >= 8 else 1)
	data[_at(8, 1, 7)] = Blocks.GLOWSTONE
	var m := _shaped(data)
	equal(m._heights(8, 1, 8), PackedFloat64Array([1, 1, 1, 1]),
		"the step stays whole against the glowstone")
	equal(m._heights(7, 1, 8), PackedFloat64Array([0, 1, 1, 1]),
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

func _equal_no_holes(data: PackedByteArray, drop: float) -> void:
	var mesher := Mesher.new()
	mesher.drop = drop
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
	equal(open.size(), 0, "edges with nothing on the other side (drop %.2f): %s"
		% [drop, open.slice(0, 8)])

# ---- corners drop (Mesher.DROP) -----------------------------------------

func test_a_corner_only_ever_drops_and_never_by_more_than_the_limit() -> void:
	var m := _shaped(_ground(func(_x: int, _z: int) -> int: return 3), Mesher.DROP)
	var lowest := 1.0
	for z in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			for c in m._heights(x, 2, z):
				check(c <= 1.0 and c >= 1.0 - Mesher.DROP - 0.0001,
					"a corner is between %.2f and 1, never above: %s at (%d,%d)"
					% [1.0 - Mesher.DROP, c, x, z])
				lowest = minf(lowest, c)
	check(lowest < 0.9, "and some of the ground has dropped (lowest %.2f)" % lowest)

func test_a_corner_with_eight_blocks_around_it_stays_put() -> void:
	# Deep inside a hill: every one of the eight is rock, nothing there
	# is drawn, and the corner is left exactly where it is.
	var m := _shaped(_ground(func(_x: int, _z: int) -> int: return 8), Mesher.DROP)
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			equal(m._drop_at(x, 4, z), 0.0, "a corner walled in on all eight sides stays")
	# ...and one with seven or fewer does drop. The top of that same
	# hill has four blocks under it and air over it.
	var moved := 0
	for z in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			if m._drop_at(x, 8, z) > 0.0:
				moved += 1
	check(moved > 50, "corners with open space beside them drop (%d of 144)" % moved)

func test_every_block_touching_a_corner_reads_the_same_height_for_it() -> void:
	var m := _shaped(_ground(_diagonal), Mesher.DROP)
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
				var s2 := m._heights(x, y, z + 1)
				if h[3] != s2[0] or h[2] != s2[1]:
					seams += 1
			# ...and the tread one level down, which shares this one's
			# foot: one corner, one height, across levels.
			if _diagonal(x + 1, z) - 1 == y - 1:
				var below := m._heights(x + 1, y - 1, z)
				if not is_equal_approx(float(y) + h[1], float(y - 1) + below[0]):
					seams += 1
	equal(seams, 0, "every block touching a corner agrees about it")

func test_ramps_are_no_longer_all_the_same_slope() -> void:
	# A straight step, ramped all along its length. With no drops every
	# one of those ramps is the same plane; with them they tip along
	# their length as well as down.
	var data := _ground(func(_x: int, z: int) -> int: return 2 if z >= 8 else 1)
	var flat := _shaped(data, 0.0)
	var fallen := _shaped(data, Mesher.DROP)
	var flat_slopes := {}
	var dropped_slopes := {}
	for x in range(2, SIZE - 2):
		var f := flat._heights(x, 1, 8)
		var d := fallen._heights(x, 1, 8)
		flat_slopes["%.3f,%.3f,%.3f,%.3f" % [f[0], f[1], f[2], f[3]]] = true
		dropped_slopes["%.3f,%.3f,%.3f,%.3f" % [d[0], d[1], d[2], d[3]]] = true
	equal(flat_slopes.size(), 1, "with no drops every ramp is the same plane")
	check(dropped_slopes.size() > SIZE / 3,
		"with them they vary: %d different ramps" % dropped_slopes.size())

func test_dropped_corners_leave_no_holes() -> void:
	var data := _ground(_diagonal)
	data[_at(3, 1, 12)] = Blocks.GLOWSTONE
	data[_at(9, 2, 3)] = Blocks.GLOWSTONE
	data[_at(12, 4, 12)] = Blocks.PLANKS
	data[_at(10, 3, 10)] = Blocks.TALL_GRASS
	data[_at(5, 1, 5)] = Blocks.AIR
	data[_at(2, 1, 2)] = Blocks.WATER
	data[_at(7, 1, 1)] = Blocks.SLAB_WOOD
	_equal_no_holes(data, Mesher.DROP)

func test_anything_built_keeps_the_corners_around_it_square() -> void:
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	data[_at(8, 3, 8)] = Blocks.PLANKS        # built on the field
	data[_at(4, 3, 4)] = Blocks.SLAB_WOOD     # and a slab, drawn as boxes
	var m := _shaped(data, Mesher.DROP)
	equal(m._drop_at(8, 3, 8), 0.0, "the corner under the planks stays")
	equal(m._drop_at(9, 4, 9), 0.0, "and the one over its far side")
	equal(m._heights(7, 2, 8)[1], 1.0, "so the ground beside it is whole")
	equal(m._heights(7, 2, 8)[2], 1.0, "...both corners")
	equal(m._drop_at(4, 3, 4), 0.0, "the slab holds its corners too")

func test_the_ground_under_water_drops_like_any_other_ground() -> void:
	# A lake: sand under water, open air above. The bed is ordinary
	# ground and rolls like it; the water itself is left alone.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	for z in range(4, 12):
		for x in range(4, 12):
			data[_at(x, 3, z)] = Blocks.WATER
			data[_at(x, 4, z)] = Blocks.WATER
	var m := _shaped(data, Mesher.DROP)
	var moved := 0
	for z in range(6, 10):
		for x in range(6, 10):
			if m._drop_at(x, 3, z) > 0.0:
				moved += 1
	check(moved > 8, "the lake bed drops (%d of 16 corners)" % moved)

func test_dropped_corners_line_up_across_a_chunk_border() -> void:
	var data := _ground(_diagonal)
	var west := _shaped(data, Mesher.DROP, {Vector2i(1, 0): data}, 0)
	var east := _shaped(data, Mesher.DROP, {Vector2i(-1, 0): data}, 1)
	for z in range(1, SIZE - 1):
		var y := _diagonal(SIZE - 1, z) - 1
		if _diagonal(0, z) - 1 != y:
			continue
		var a := west._heights(SIZE - 1, y, z)
		var b := east._heights(0, y, z)
		equal(a[1], b[0], "the border corner at z=%d reads the same from both chunks" % z)
		equal(a[2], b[3], "...and its southern neighbour")

func test_a_cliff_face_varies_from_level_to_level() -> void:
	# A wall of natural stone with open ground in front of it. The drop
	# must change as you go UP the wall, or a cliff moves as one piece
	# and is exactly as square as it was.
	var data := _ground(func(x: int, _z: int) -> int: return 8 if x >= 8 else 1)
	var m := _shaped(data, Mesher.DROP)
	var seen: Array = []
	for level in range(2, 8):
		seen.append(m._drop_at(8, level, 6))
	var different := {}
	for value: float in seen:
		different["%.4f" % value] = true
		check(value >= 0.0 and value <= Mesher.DROP + 0.0001,
			"and none of them drops too far: %s" % value)
	check(different.size() >= 4,
		"the face of a cliff drops by a different amount at each level: %s" % [seen])
	# ...and the blocks of the wall are genuinely different heights, not
	# the same block shifted.
	var tall := 0
	var short := 0
	for vz in range(2, 14):
		for level in range(2, 8):
			var height := 1.0 - m._drop_at(8, level + 1, vz) + m._drop_at(8, level, vz)
			if height > 1.05:
				tall += 1
			elif height < 0.95:
				short += 1
	check(tall > 0 and short > 0,
		"some blocks of the wall are taller and some shorter (%d up, %d down)" % [tall, short])

func test_a_plant_comes_down_with_the_ground_it_stands_on() -> void:
	# Ground with a tuft on it: the tuft's feet are at the average of
	# the four corners under it, not at the block's own top.
	var data := _ground(func(_x: int, _z: int) -> int: return 3)
	data[_at(8, 3, 8)] = Blocks.TALL_GRASS
	var m := _shaped(data, Mesher.DROP)
	var under := m._ground_drop(8, 3, 8)
	check(under > 0.0, "the ground under the tuft has dropped (%.3f)" % under)
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	var arrays: Array = built["plants"]
	var lowest := 99.0
	for v in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if absf(v.x - 8.5) < 0.6 and absf(v.z - 8.5) < 0.6:
			lowest = minf(lowest, v.y)
	check(lowest < 3.0 - 0.001,
		"so the tuft's feet are in it, not above it (%.3f)" % lowest)

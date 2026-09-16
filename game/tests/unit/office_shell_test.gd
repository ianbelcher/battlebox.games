extends TestCase
## THE OFFICE IS A SEALED BOX, and this is the check that it stays one.
##
## The floor plate is one storey of a tower with nothing above it and
## nothing below it worth reaching. The slab over the ceiling used to be
## ordinary concrete, so anybody — and far more often a computer player
## working its way out of somewhere — could dig up through the tiles and
## end up standing on the roof, looking down into the office through the
## hole they came out of. The boundary ring had the same hole in it in
## three of its five bands, and behind that ring is not the outside of the
## building, it is the outside of the world.
##
## Bedrock answers both without a rule to explain, a boundary to draw or
## damage to apply for standing somewhere: the way out is not there.

const SPAN := 3

func _gen() -> WorldGen:
	return WorldGen.new(20260726, "office", 100)

func _block(data: PackedByteArray, lx: int, y: int, lz: int) -> int:
	return data.decode_u16(WorldGen.bidx(lx, y, lz))

func test_nothing_over_the_ceiling_can_be_dug() -> void:
	var gen := _gen()
	var soft := 0
	for cz in range(-SPAN, SPAN):
		for cx in range(-SPAN, SPAN):
			var data := gen.generate_chunk(cx, cz)
			for lz in 16:
				for lx in 16:
					for y in range(WorldGen.OFFICE_CEIL_Y + 1,
							WorldGen.OFFICE_SLAB_TOP + 1):
						if Blocks.is_breakable(_block(data, lx, y, lz)):
							soft += 1
	equal(soft, 0, "every block above the ceiling is unbreakable")

func test_nothing_under_the_floor_can_be_dug() -> void:
	var gen := _gen()
	var soft := 0
	for cz in range(-SPAN, SPAN):
		for cx in range(-SPAN, SPAN):
			var data := gen.generate_chunk(cx, cz)
			for lz in 16:
				for lx in 16:
					for y in WorldGen.OFFICE_FLOOR_Y:
						if Blocks.is_breakable(_block(data, lx, y, lz)):
							soft += 1
	equal(soft, 0, "every block under the floor is unbreakable")

func test_the_shell_has_no_gaps_in_it() -> void:
	var gen := _gen()
	var holes := 0
	for cz in range(-SPAN, SPAN):
		for cx in range(-SPAN, SPAN):
			var data := gen.generate_chunk(cx, cz)
			for lz in 16:
				for lx in 16:
					var wx := cx * 16 + lx
					var wz := cz * 16 + lz
					if not gen.in_bounds(wx, wz):
						continue
					for y in [WorldGen.OFFICE_CEIL_Y + 1, WorldGen.OFFICE_SLAB_TOP]:
						if _block(data, lx, y, lz) == Blocks.AIR:
							holes += 1
	equal(holes, 0, "the slab over the office is solid the whole way across")

func test_the_wall_round_the_world_cannot_be_dug_at_any_height() -> void:
	# A SMALL WORLD ON PURPOSE. The ring is at the edge of the slab, and
	# on the hundred-block world the rest of this file uses it is outside
	# the handful of chunks worth generating in a unit test — so the first
	# version of this checked nothing at all and said so, which is the
	# only reason it is written this way.
	var gen := WorldGen.new(20260726, "office", 50)
	var soft := 0
	var checked := 0
	for cz in range(-3, 3):
		for cx in range(-3, 3):
			var data := gen.generate_chunk(cx, cz)
			for lz in 16:
				for lx in 16:
					var wx := cx * 16 + lx
					var wz := cz * 16 + lz
					# ON the ring AND inside the slab. on_border() answers
					# for a whole line of columns, most of which run off
					# past the corner of the world and are air because
					# there is no world there — which is correct, and is
					# what the first version of this counted as a hole.
					if not (gen.on_border(wx, wz) and gen.in_bounds(wx, wz)):
						continue
					for y in range(0, WorldGen.OFFICE_SLAB_TOP + 1):
						var b := _block(data, lx, y, lz)
						checked += 1
						if b == Blocks.AIR or Blocks.is_breakable(b):
							soft += 1
	check(checked > 0, "the sampled area reaches the edge of the world")
	equal(soft, 0, "the ring is solid and unbreakable floor to roof")

func test_there_is_nothing_at_all_above_the_building() -> void:
	var gen := _gen()
	var stuff := 0
	for cz in range(-SPAN, SPAN):
		for cx in range(-SPAN, SPAN):
			var data := gen.generate_chunk(cx, cz)
			for lz in 16:
				for lx in 16:
					for y in range(WorldGen.OFFICE_SLAB_TOP + 1,
							WorldGen.CHUNK_H):
						if _block(data, lx, y, lz) != Blocks.AIR:
							stuff += 1
	equal(stuff, 0, "no terrain, scatter or landmark over the roof")

## And the room itself is still a room: four blocks of headroom from the
## floor to the tiles, everywhere the floor is open.
func test_the_room_under_it_still_has_its_headroom() -> void:
	var gen := _gen()
	var data := gen.generate_chunk(0, 0)
	var open := 0
	for lz in 16:
		for lx in 16:
			if _block(data, lx, WorldGen.OFFICE_FLOOR_Y + 1, lz) != Blocks.AIR:
				continue
			open += 1
			for y in range(WorldGen.OFFICE_FLOOR_Y + 1, WorldGen.OFFICE_CEIL_Y):
				equal(_block(data, lx, y, lz), Blocks.AIR,
					"clear at (%d, %d, %d)" % [lx, y, lz])
	check(open > 50, "reception is mostly open floor (%d columns)" % open)

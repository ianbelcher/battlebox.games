extends TestCase
## WHICH WAY A TURNABLE BLOCK IS ROUND, pinned.
##
## This exists because the first version of it was backwards and nothing
## said so: `with_facing(chair, 2)` meant "placed by somebody looking
## south", which put the chair's back to the south and its seat to the
## north. Every chair the office generator sat at a table faced away from
## it, every monitor faced a wall, and the generator's code read
## perfectly sensibly at each of those places.
##
## The mesher is the only thing that knows where a box actually ends up,
## so the check has to go through it rather than through the id.

const SIZE := 16

func _at(x: int, y: int, z: int) -> int:
	return ((y * SIZE + z) * SIZE + x) << 1

## Mesh one block on its own and report the bounding box of what came out,
## in the block's own 0..1 space.
func _bounds(block: int) -> AABB:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H * 2)
	data.fill(Blocks.AIR)
	data.encode_u16(_at(8, 4, 8), block)
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	var verts: PackedVector3Array = built["opaque"][Mesh.ARRAY_VERTEX]
	check(verts.size() > 0, "the block meshed into something")
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for v: Vector3 in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo - Vector3(8, 4, 8), hi - lo)

## Which side of the cell a block's TALLEST part leans towards, as a
## quadrant. For a chair or a sofa that is the back, which is behind you
## and so opposite the way it faces; for a monitor it is the screen, which
## is the way it faces. Either way it is the one thing you can see from
## across a room, so it is the thing worth pinning.
func _top_mass_quadrant(block: int) -> int:
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * WorldGen.CHUNK_H * 2)
	data.fill(Blocks.AIR)
	data.encode_u16(_at(8, 4, 8), block)
	var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
	var verts: PackedVector3Array = built["opaque"][Mesh.ARRAY_VERTEX]
	# The centre of mass of everything in the top third of the cell.
	var sum := Vector3.ZERO
	var n := 0
	for v: Vector3 in verts:
		if v.y - 4.0 < 0.62:
			continue
		sum += v - Vector3(8, 4, 8)
		n += 1
	if n == 0:
		return -1
	var c := sum / float(n)
	if absf(c.x - 0.5) > absf(c.z - 0.5):
		return 1 if c.x > 0.5 else 3
	return 2 if c.z > 0.5 else 0

func test_a_chair_seats_you_facing_the_way_it_was_asked_to() -> void:
	for facing in 4:
		var chair := Blocks.with_facing(Blocks.OFFICE_CHAIR, facing)
		equal(Blocks.facing_of(chair), facing, "facing %d survives the round trip" % facing)
		# The back is behind you, so it sits on the OPPOSITE side to the
		# way the chair faces.
		equal(_top_mass_quadrant(chair), posmod(facing + 2, 4),
			"a chair facing %d has its back on the far side" % facing)

func test_a_whiteboard_hangs_on_the_wall_it_faces_away_from() -> void:
	for facing in 4:
		var board := Blocks.with_facing(Blocks.WHITEBOARD, facing)
		equal(_top_mass_quadrant(board), posmod(facing + 2, 4),
			"a board facing %d is mounted on the opposite wall" % facing)

func test_a_sofa_puts_its_back_behind_the_person_on_it() -> void:
	for facing in 4:
		var sofa := Blocks.with_facing(Blocks.SOFA, facing)
		equal(_top_mass_quadrant(sofa), posmod(facing + 2, 4),
			"a sofa facing %d has its back on the far side" % facing)

## Placing a thing points its FRONT at you: you are looking along the
## heading, so the front is the quadrant behind it.
func test_what_you_put_down_looks_back_at_you() -> void:
	var cases := {0: Vector3(0, 0, -1), 1: Vector3(1, 0, 0),
		2: Vector3(0, 0, 1), 3: Vector3(-1, 0, 0)}
	for quad: int in cases:
		var placed := Blocks.orient(Blocks.MONITOR, cases[quad])
		equal(Blocks.facing_of(placed), posmod(quad + 2, 4),
			"looking %d puts the screen back towards you" % quad)

## Stairs keep their own older rule and must not be swept up in this.
func test_stairs_still_climb_the_way_you_face() -> void:
	equal(Blocks.orient(Blocks.STAIRS_WOOD, Vector3(1, 0, 0)),
		Blocks.STAIRS_WOOD + 1, "east")
	equal(Blocks.orient(Blocks.STAIRS_WOOD, Vector3(0, 0, 1)),
		Blocks.STAIRS_WOOD + 2, "south")

## A desk has to be a whole cell tall, or everything stood on it floats.
func test_a_worktop_reaches_the_top_of_its_cell() -> void:
	for block in [Blocks.DESK, Blocks.MEETING_TABLE, Blocks.CABINET,
			Blocks.PLANTER]:
		var box := _bounds(block)
		var top := box.position.y + box.size.y
		check(absf(top - 1.0) < 0.001,
			"%s reaches the top of its cell (got %.2f)"
			% [Blocks.info(block).get("name", "?"), top])

## A MONITOR IS THE OTHER WAY UP FROM THE FURNITURE, and this is the test
## that was missing when the first fix went in. A chair's tall part is its
## back, so it lands opposite the facing; a monitor's tall part is the
## SCREEN, so it lands ON the facing. The geometry had the panel at the
## back of the cell with the stand reaching past it, so a monitor turned
## to face somebody showed them its foot and hid the panel behind it — and
## the chair test passed throughout, because a monitor is not a chair.
func test_a_screen_is_on_the_side_the_monitor_faces() -> void:
	for facing in 4:
		var screen := Blocks.with_facing(Blocks.MONITOR, facing)
		equal(_top_mass_quadrant(screen), facing,
			"a monitor facing %d puts its panel that way" % facing)

## And the stand is behind the screen, not in front of it: the lowest
## part of the block leans the OPPOSITE way to the panel.
func test_the_stand_is_behind_the_screen() -> void:
	for facing in 4:
		var screen := Blocks.with_facing(Blocks.MONITOR, facing)
		var data := PackedByteArray()
		data.resize(SIZE * SIZE * WorldGen.CHUNK_H * 2)
		data.fill(Blocks.AIR)
		data.encode_u16(_at(8, 4, 8), screen)
		var built: Dictionary = Mesher.new().build(data, {}, 0, 0)
		var verts: PackedVector3Array = built["opaque"][Mesh.ARRAY_VERTEX]
		var sum := Vector3.ZERO
		var n := 0
		for v: Vector3 in verts:
			if v.y - 4.0 > 0.2:
				continue          # the foot only
			sum += v - Vector3(8, 4, 8)
			n += 1
		check(n > 0, "the monitor has a foot")
		var c := sum / float(n)
		var quad := (1 if c.x > 0.5 else 3) if absf(c.x - 0.5) > absf(c.z - 0.5) \
			else (2 if c.z > 0.5 else 0)
		equal(quad, posmod(facing + 2, 4),
			"the foot of a monitor facing %d is behind it" % facing)

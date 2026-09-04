extends TestCase
## Whether the name and hearts over a player's head are drawn for a seat.
##
## They used to be drawn for everybody, and a tag floats above the blocks
## its player is behind — so somebody crouched behind a wall was announced
## by the hearts hanging over it. Now a seat only draws a tag while its
## camera has a clear line to the body. These are the rules of that line.

var _solid: Dictionary = {}

func before_each() -> void:
	_solid.clear()

func _opaque_at(cell: Vector3i) -> bool:
	return _solid.has(cell)

func _wall(x: int, z0: int, z1: int, y0: int, y1: int) -> void:
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			_solid[Vector3i(x, y, z)] = true

func test_open_ground_is_in_view() -> void:
	check(OverheadSight.line_clear(Vector3(0.5, 1.5, 0.5), Vector3(12.5, 1.5, 0.5), _opaque_at),
		"nothing between the two points, so the line is clear")

func test_a_wall_between_hides_the_body() -> void:
	_wall(6, -2, 2, 0, 4)
	var eye := Vector3(0.5, 1.6, 0.5)
	var feet := Vector3(12.5, 0.0, 0.5)
	equal(OverheadSight.body_in_view(eye, Vector3(1, 0, 0), false, feet, _opaque_at), false,
		"a wall taller than the body hides it from a first-person camera")

func test_a_head_over_a_low_wall_still_counts() -> void:
	# A parapet up to the chest: the head shows over it, and that is
	# enough — you can see them, so you get their name.
	_wall(6, -2, 2, 0, 0)
	var eye := Vector3(0.5, 1.6, 0.5)
	var feet := Vector3(12.5, 0.0, 0.5)
	check(OverheadSight.body_in_view(eye, Vector3(1, 0, 0), false, feet, _opaque_at),
		"a knee-high wall does not hide a standing body")

func test_the_end_cells_are_never_sampled() -> void:
	# Tall grass around the feet or a camera pressed against a block is not
	# a hiding place; only what lies BETWEEN counts.
	_solid[Vector3i(0, 1, 0)] = true
	_solid[Vector3i(12, 1, 0)] = true
	check(OverheadSight.line_clear(Vector3(0.5, 1.5, 0.5), Vector3(12.5, 1.5, 0.5), _opaque_at),
		"the cells the line starts and ends in do not block it")

func test_an_orthographic_camera_looks_along_its_view_not_at_its_position() -> void:
	# The orbit camera is a plane far off to one side, looking DOWN at a
	# slant. A player under a roof is hidden from it even though the
	# straight line from the camera's own position would miss the roof.
	var forward := Vector3(0, -1, 0)
	var cam_pos := Vector3(-40.0, 30.0, 0.0)
	var feet := Vector3(10.5, 0.0, 0.5)
	# A roof directly over the player.
	for x in range(8, 13):
		for z in range(-2, 3):
			_solid[Vector3i(x, 4, z)] = true
	equal(OverheadSight.body_in_view(cam_pos, forward, true, feet, _opaque_at), false,
		"a roof hides a body from a straight-down orthographic camera")
	check(OverheadSight.body_in_view(cam_pos, forward, false, feet, _opaque_at),
		"the same camera treated as a point off to the side sees under the roof")

func test_the_orthographic_origin_sits_on_the_camera_plane() -> void:
	var origin := OverheadSight.ray_origin(Vector3(0, 10, 0), Vector3(0, -1, 0), true,
		Vector3(5, 2, 7))
	near(origin.x, 5.0, 0.001, "the ray drops straight onto the target")
	near(origin.y, 10.0, 0.001, "and starts level with the camera")
	near(origin.z, 7.0, 0.001, "over the target")
	equal(OverheadSight.ray_origin(Vector3(1, 2, 3), Vector3(0, 0, -1), false, Vector3(9, 9, 9)),
		Vector3(1, 2, 3), "a perspective camera's ray starts at the camera")

func test_layers_name_the_seats_that_saw_you_plus_the_spectator() -> void:
	var mask := OverheadSight.layers_for([0, 2])
	not_equal(mask & RenderLayers.overhead_of(0), 0, "seat 0 saw them")
	equal(mask & RenderLayers.overhead_of(1), 0, "seat 1 did not")
	not_equal(mask & RenderLayers.overhead_of(2), 0, "seat 2 saw them")
	not_equal(mask & RenderLayers.OVERHEAD_SPECTATOR, 0, "the spectator always does")
	equal(OverheadSight.layers_for([]) & ~RenderLayers.OVERHEAD_SPECTATOR, 0,
		"nobody saw them: only the spectator layer is left")
	equal(OverheadSight.layers_for([-1, 9]), RenderLayers.OVERHEAD_SPECTATOR,
		"a slot that is not a seat is ignored")

extends TestCase
## Boats and cars: where they go, and what happens to whoever is standing
## on one.
##
## The passenger case is the reason this file exists. "A number of other
## players can jump on it and will remain in the same place on the boat"
## is a claim about a rotating frame of reference, it is wrong in a way
## that looks like a physics glitch rather than a bug, and there is no
## other way to check it — a headless run has nobody standing on anything
## and a screenshot is one frame of a moving boat.

func test_a_boat_does_twice_a_running_pace() -> void:
	equal(VehicleGeom.BOAT_SPEED, Player.WALK_SPEED * 2.0,
		"twice a run, which is the whole point of getting in one")

func test_a_boat_is_longer_than_it_is_wide() -> void:
	check(VehicleGeom.half_length(VehicleGeom.KIND_BOAT)
			> VehicleGeom.half_width(VehicleGeom.KIND_BOAT),
		"otherwise it is a raft")

# ---- standing on the deck -------------------------------------------

func test_the_middle_of_the_deck_is_on_the_deck() -> void:
	var boat := Vector3(10, 30, -5)
	var feet := boat + Vector3(0, VehicleGeom.deck_height(VehicleGeom.KIND_BOAT), 0)
	check(VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, 0.0, feet),
		"standing in the middle of it counts")

func test_the_water_beside_the_boat_is_not_the_deck() -> void:
	var boat := Vector3(10, 30, -5)
	var beside := boat + Vector3(6.0, VehicleGeom.deck_height(VehicleGeom.KIND_BOAT), 0)
	check(not VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, 0.0, beside),
		"six blocks to the side is in the sea")

func test_a_rider_settling_half_a_block_low_is_still_a_rider() -> void:
	# The failure this guards against: a player's feet dip below the deck
	# for a frame as they land, they stop counting as aboard, and the boat
	# leaves without them at nine blocks a second.
	var boat := Vector3(0, 30, 0)
	var dipped := boat + Vector3(0,
		VehicleGeom.deck_height(VehicleGeom.KIND_BOAT) - 0.3, 0)
	check(VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, 0.0, dipped),
		"a moment of settling must not throw somebody overboard")

func test_standing_well_above_the_boat_is_not_riding_it() -> void:
	var boat := Vector3(0, 30, 0)
	var flying := boat + Vector3(0, 4.0, 0)
	check(not VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, 0.0, flying),
		"flying over a boat is not being in it")

func test_the_deck_turns_with_the_boat() -> void:
	# Along the boat's length, which is on the deck when the boat points
	# one way and over the side when it has turned ninety degrees.
	var boat := Vector3(0, 30, 0)
	var deck_y := VehicleGeom.deck_height(VehicleGeom.KIND_BOAT)
	var astern := boat + Vector3(0, deck_y, 2.3)
	check(VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, 0.0, astern),
		"two blocks aft is on a boat pointing up the z axis")
	check(not VehicleGeom.on_deck(VehicleGeom.KIND_BOAT, boat, PI * 0.5, astern),
		"the same spot is over the side once she has come about")

# ---- riding ----------------------------------------------------------

func test_a_rider_keeps_their_place_when_the_boat_turns() -> void:
	# THE CLAIM, tested directly: stand at the stern, turn the boat a
	# quarter turn, and the stern is where you still are.
	#
	# At yaw 0 the heading is +z (see VehicleGeom.drive), so the bow is up
	# the z axis and 2.2 behind it is -z. Worth spelling out: getting that
	# backwards is what this test caught the first time it ran.
	var boat := Vector3(4, 30, 9)
	var astern := boat + Vector3(0, 0.55, -2.2)
	var local := VehicleGeom.to_local(boat, 0.0, astern)
	var turned := VehicleGeom.to_world(boat, PI * 0.5, local)
	# A quarter turn about y takes -z to +x.
	near(turned.x, boat.x + 2.2, 0.001, "the stern swung round to the east")
	near(turned.z, boat.z, 0.001, "…and is no longer down the z axis")
	near(turned.y, astern.y, 0.001, "and nobody went up or down")

func test_riding_survives_the_boat_moving_and_turning_at_once() -> void:
	var start := Vector3(0, 30, 0)
	var spot := start + Vector3(1.0, 0.55, -2.0)
	var local := VehicleGeom.to_local(start, 0.3, spot)
	var moved := Vector3(20, 30, -6)
	var back := VehicleGeom.to_world(moved, 0.3, local)
	near(back.distance_to(spot + (moved - start)), 0.0, 0.001,
		"the rider went exactly where the boat went")

func test_local_and_world_are_actually_inverses() -> void:
	var boat := Vector3(-7, 31, 12)
	var point := Vector3(-5.5, 31.6, 14.2)
	for yaw in [0.0, 0.7, PI, -2.1, TAU]:
		var round_trip := VehicleGeom.to_world(boat, yaw,
			VehicleGeom.to_local(boat, yaw, point))
		near(round_trip.distance_to(point), 0.0, 0.0001,
			"there and back at yaw %.2f" % yaw)

# ---- driving ---------------------------------------------------------

func test_full_throttle_reaches_the_top_speed_and_no_further() -> void:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var speed := 0.0
	for _i in 200:
		var out := VehicleGeom.drive(VehicleGeom.KIND_BOAT, pos, yaw, speed,
			1.0, 0.0, 1.0 / 60.0)
		pos = out[0]
		yaw = out[1]
		speed = out[2]
	near(speed, VehicleGeom.BOAT_SPEED, 0.01, "it gets there")

func test_letting_go_coasts_to_a_stop_rather_than_stopping_dead() -> void:
	var out := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO, 0.0,
		VehicleGeom.BOAT_SPEED, 0.0, 0.0, 1.0 / 60.0)
	var speed: float = out[2]
	check(speed < VehicleGeom.BOAT_SPEED, "it slows")
	check(speed > VehicleGeom.BOAT_SPEED * 0.9, "but nothing like instantly")

func test_a_stopped_boat_does_not_spin_on_the_spot() -> void:
	# Otherwise a child holding the stick sideways at the jetty makes a
	# fairground ride out of it, and every passenger goes round with them.
	var out := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO, 0.0,
		0.0, 0.0, 1.0, 1.0 / 60.0)
	near(out[1], 0.0, 0.0001, "no way on, no steering")

func test_steering_bites_once_she_is_moving() -> void:
	var out := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO, 0.0,
		VehicleGeom.BOAT_SPEED, 1.0, 1.0, 1.0 / 60.0)
	check(absf(out[1]) > 0.001, "under way, she answers the helm")

func test_reverse_is_slower_than_forward() -> void:
	var back := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO, 0.0,
		0.0, -1.0, 0.0, 1.0)
	var fwd := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO, 0.0,
		0.0, 1.0, 0.0, 1.0)
	check(absf(back[2]) < absf(fwd[2]),
		"astern is for getting off a sandbank, not for racing")

func test_she_travels_the_way_she_is_pointing() -> void:
	var out := VehicleGeom.drive(VehicleGeom.KIND_BOAT, Vector3.ZERO,
		PI * 0.5, 4.0, 1.0, 0.0, 0.25)
	var moved: Vector3 = out[0]
	check(moved.x > 0.5, "pointing east, going east")
	near(moved.z, 0.0, 0.001, "and not sideways")

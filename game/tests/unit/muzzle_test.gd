extends TestCase
## WHERE A SHOT COMES FROM.
##
## This is a size bug that reached a person playing the game, and it is
## worth a test because of how it failed: everything worked. The shot
## left, flew, hit things and did damage. It simply came out of the
## player's ANKLE, because the muzzle was Player.EYE_HEIGHT — a flat 1.62
## blocks — while the eye it was supposed to be at had moved thirteen
## blocks up the body. Nothing logs that, nothing crashes, and every
## other check in the repository stays green.

# ---- a person still fires exactly where a person fired -----------------

func test_a_person_is_unchanged() -> void:
	var eye := Vector3(0, 1.62, 0)
	var fwd := Vector3(0, 0, -1)
	var was := Weapons.shot_ray(eye, fwd, true, 0)
	var now := Weapons.shot_ray(eye, fwd, true, 0, BodySize.PERSON)
	equal(now[0], was[0], "the default size is a person, so nothing moved")
	near((now[0] as Vector3).distance_to(eye), 0.45, 0.0001,
		"and it still starts 0.45 clear of the face")

func test_third_person_is_unchanged_for_a_person() -> void:
	var eye := Vector3(0, 1.62, 0)
	var shot: Array = Weapons.shot_ray(eye, Vector3(0, 0, -1), false, 0, BodySize.PERSON)
	var off: Vector3 = shot[0] - eye
	near(off.y, -0.34, 0.0001, "off the hip, below the eye")
	near(off.z, -0.3, 0.0001, "and a little ahead")

# ---- THE BUG -----------------------------------------------------------

## A SHOT LEAVES THE FACE, AT EVERY SIZE. The clearance is what stops an
## orb spawning inside the shooter's own head, so it has to be measured
## in bodies: 0.45 of a block clears a person's face and is somewhere
## behind the chin of anything four times the size.
func test_the_clearance_grows_with_the_face_it_clears() -> void:
	for size: float in [1.0, 2.0, 4.0, 8.0]:
		var eye := Vector3(0, BodySize.eye(size), 0)
		var shot: Array = Weapons.shot_ray(eye, Vector3(0, 0, -1), true, 0, size)
		var clear: float = (shot[0] as Vector3).distance_to(eye)
		check(clear >= BodySize.half_width(size),
			"at %.0fx a shot starts %.2f out, against a body %.2f half-wide"
				% [size, clear, BodySize.half_width(size)])

## AND IT STILL STARTS ON THE SIGHT LINE. The whole first-person contract
## is "the shot goes where the crosshair points" (see the note above
## Weapons.shot_ray), so however far forward the muzzle is pushed it must
## not move sideways or up off the ray.
func test_first_person_never_leaves_the_sight_line() -> void:
	var dir := Vector3(0.3, 0.2, -1).normalized()
	for size: float in [0.5, 1.0, 4.0, 8.0, 16.0]:
		var eye := Vector3(0, BodySize.eye(size), 0)
		var shot: Array = Weapons.shot_ray(eye, dir, true, 0, size)
		var along: Vector3 = (shot[0] as Vector3) - eye
		near(along.normalized().dot(dir), 1.0, 0.0001,
			"at %.1fx the muzzle is still dead on the sight line" % size)

## The hip offset is a place on a body, so it travels with the body.
func test_the_hip_is_on_the_body_not_at_a_fixed_distance() -> void:
	var dir := Vector3(0, 0, -1)
	var small: Array = Weapons.shot_ray(Vector3.ZERO, dir, false, 0, 1.0)
	var giant: Array = Weapons.shot_ray(Vector3.ZERO, dir, false, 0, 8.0)
	near((giant[0] as Vector3).length() / (small[0] as Vector3).length(), 8.0, 0.001,
		"eight times the body, eight times the offset")

## The drawn muzzle flash is cosmetic, and cosmetic on a giant means a
## giant's arm's length — but it must STILL be nothing once it has blended
## out, or it has stopped being cosmetic and started bending the shot.
func test_the_drawn_lead_scales_and_still_ends_at_nothing() -> void:
	var vel := Vector3(0, 0, -60)
	var small: Vector3 = Weapons.muzzle_lead(vel, 0.0, 1.0)
	var giant: Vector3 = Weapons.muzzle_lead(vel, 0.0, 8.0)
	near(giant.length() / small.length(), 8.0, 0.001, "a giant's arm, not a person's")
	for size: float in [1.0, 8.0]:
		equal(Weapons.muzzle_lead(vel, Weapons.MUZZLE_LEAD, size), Vector3.ZERO,
			"at %.0fx it is back on the true path when the lead is over" % size)

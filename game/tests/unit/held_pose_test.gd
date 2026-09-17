extends TestCase
## WHICH WAY A WEAPON POINTS IN SOMEBODY ELSE'S HAND.
##
## The item is parented to `arm-right` and inherits whatever the clip is
## doing to it, and nothing else decides its direction. The pack raises
## that arm in `holding-right` and lets it hang in `walk`, so a weapon
## that sits right in the hand of somebody standing still is a quarter
## turn out the moment they take a step — muzzle at the floor, sword
## backwards — and everybody spends a round moving.
##
## None of that raises anything: the model loads, the node is parented,
## the clip plays and the console is clean. tests/held_items.tscn is the
## picture; this is the part of it a machine can check.

const PACK := "res://assets/models/chars/character-a.glb"

func _clips() -> Array:
	var scene: PackedScene = load(PACK)
	var inst: Node = scene.instantiate()
	var found: Array = []
	for ap: AnimationPlayer in inst.find_children("*", "AnimationPlayer", true, false):
		found = Array(ap.get_animation_list())
	inst.free()
	return found

## The clips the pack ships are the ones the animation chooser names, and
## a renamed or retired one does not error — it silently stops matching.
func test_every_clip_named_is_one_the_pack_actually_has() -> void:
	var clips := _clips()
	check(clips.size() > 10, "the pack loaded (%d clips)" % clips.size())
	for name: String in AvatarFactory.LOOPING_ANIMS:
		check(name in clips, "'%s' loops and exists" % name)

## EVERYTHING BETWEEN THE WEAPON AND THE BODY COMES BACK OUT, whatever it
## is. Composed with the arm it was measured against, the correction must
## leave exactly the body's own rotation — so the weapon points the same
## way no matter where in a stride the arm, the torso and the root have
## got to.
func test_the_whole_chain_is_cancelled() -> void:
	for body_yaw: float in [0.0, 90.0, -140.0, 180.0]:
		var body := Basis(Vector3.UP, deg_to_rad(body_yaw))
		# An arm that has been swung, on a torso that has been leaned, on
		# a body that is facing somewhere of its own — which is what a
		# sprint really is, and what a correction that only knew about the
		# arm was thirty degrees out on.
		for arm_swing: float in [0.0, -90.0, 45.0, 120.0]:
			for lean: float in [0.0, 18.0, -25.0]:
				var arm := body * Basis(Vector3.RIGHT, deg_to_rad(lean)) \
					* Basis(Vector3.RIGHT, deg_to_rad(arm_swing))
				var out := Basis(arm.get_rotation_quaternion()
					* AvatarFactory.hand_rotation(arm, body))
				check(out.get_rotation_quaternion().angle_to(
						body.get_rotation_quaternion()) < 0.001,
					"arm %.0f, lean %.0f, body %.0f: still the body's facing"
						% [arm_swing, lean, body_yaw])

## AND THE MUZZLE REALLY ENDS UP FACING THE WAY THE BODY IS. The rotations
## above are only arithmetic until something is asked which way -Z came
## out pointing, and -Z is where a weapon is modelled to fire.
func test_the_muzzle_comes_out_facing_the_way_the_body_does() -> void:
	for body_yaw: float in [0.0, 90.0, -140.0]:
		var body := Basis(Vector3.UP, deg_to_rad(body_yaw))
		var forward := -body.z
		for arm_swing: float in [0.0, -90.0, 45.0, 120.0]:
			var arm := body * Basis(Vector3.RIGHT, deg_to_rad(arm_swing))
			var muzzle := Basis(arm.get_rotation_quaternion()
				* AvatarFactory.hand_rotation(arm, body)) * Vector3(0, 0, -1)
			check(muzzle.dot(forward) > 0.999,
				"an arm at %.0f deg fires where the body is looking, not at the floor"
					% arm_swing)

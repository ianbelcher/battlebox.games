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

## THE LIST IS OF REAL CLIP NAMES. A renamed or retired clip does not
## error, it just silently stops matching — and every weapon in the game
## quietly goes back to pointing at the ground.
func test_every_clip_named_is_one_the_pack_actually_has() -> void:
	var clips := _clips()
	check(clips.size() > 10, "the pack loaded (%d clips)" % clips.size())
	for name: String in AvatarFactory.ARM_RAISED_CLIPS:
		check(name in clips, "'%s' is a clip the pack ships" % name)
	for name: String in AvatarFactory.LOOPING_ANIMS:
		check(name in clips, "'%s' loops and exists" % name)

## The clips somebody actually spends a round in are the ones that hang,
## and they are the reason this exists at all.
func test_the_clips_you_move_in_get_the_turn_put_back() -> void:
	for clip: String in ["walk", "sprint", "idle", ""]:
		equal(AvatarFactory.hand_tilt_degrees(clip), Vector3(90, 0, 0),
			"'%s' hangs the arm, so the weapon is turned up" % clip)

func test_a_raised_arm_is_left_alone() -> void:
	for clip: String in ["holding-right", "holding-both", "sit"]:
		equal(AvatarFactory.hand_tilt_degrees(clip), Vector3.ZERO,
			"'%s' already points the weapon where it should go" % clip)

## AND A SWING KEEPS ITS SWORD. Correcting the melee clip would hold the
## blade still while the arm went round it, which is worse than either
## other state and the easiest one to break by tidying the list.
func test_a_swing_carries_the_sword_with_it() -> void:
	equal(AvatarFactory.hand_tilt_degrees("attack-melee-right"), Vector3.ZERO,
		"the sword follows the arm through a swing")

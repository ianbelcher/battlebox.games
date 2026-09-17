extends Node3D
## WHICH WAY A HELD WEAPON ACTUALLY POINTS, as numbers.
##
##     godot --headless --path <game> res://tests/aim_probe.tscn
##
## tests/held_items.tscn is the picture of this and is the better thing to
## look at; this is the picture's arithmetic, and it exists because the
## picture can be misread. A weapon photographed at a three-quarter angle
## looks roughly forward from a long way out of true, which is how a
## correction that put every muzzle a quarter turn UP once survived a
## review of the photographs.
##
## It runs the clips FOR REAL, a frame at a time, and corrects the item
## from `mixer_applied` exactly as Player does — because the timing is
## half the fix. Read the arm from _process instead and the correction is
## a frame behind the arm it is correcting, which does not point the gun
## at the floor but does make it shiver in the hand.
##
## `raw` is the item with no correction at all, and it is the bug: a
## hanging arm fires BACKWARDS (-1.000) and the raised `holding-right`
## arm fires at the FLOOR (0.000). `corrected` must be 1.000, in every
## clip, on every frame.
const CLIPS: Array[String] = ["holding-right", "walk", "idle", "sprint",
	"attack-melee-right"]
const FRAMES_PER_CLIP := 40

var _body: Node3D
var _arm: Node3D
var _item: Node3D
var _correct := true

func _ready() -> void:
	_body = AvatarFactory.build_character({})
	add_child(_body)
	var ap := _body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_arm = _body.find_child("arm-right", true, false)
	_item = ItemFactory.build("weapon", 1)
	_arm.add_child(_item)
	ap.mixer_applied.connect(_steady)
	var want := -global_basis.z
	var overall := 1.0
	for clip: String in CLIPS:
		if not ap.has_animation(clip):
			print("AIM %s: the pack has no such clip" % clip)
			continue
		for corrected: bool in [false, true]:
			_correct = corrected
			ap.stop()
			ap.play(clip)
			var worst := 1.0
			var best := -1.0
			for _frame in FRAMES_PER_CLIP:
				await get_tree().process_frame
				var dot := (-_item.global_basis.z.normalized()).dot(want)
				worst = minf(worst, dot)
				best = maxf(best, dot)
			print("AIM %-18s %-9s over %d frames: worst=%+.3f best=%+.3f"
				% [clip, "corrected" if corrected else "raw", FRAMES_PER_CLIP,
					worst, best])
			if corrected:
				overall = minf(overall, worst)
	print("AIM worst corrected dot in any clip on any frame: %+.3f" % overall)
	get_tree().quit()

## The game's own correction, on the game's own signal. A swing is left
## alone here for the same reason it is left alone there — the sword has
## to travel with the arm — so `attack-melee-right` is expected to read
## like `raw` and is in the list to prove the exception is deliberate.
func _steady() -> void:
	_item.quaternion = AvatarFactory.hand_rotation(_arm.global_basis,
		_body.global_basis) if _correct else Quaternion.IDENTITY

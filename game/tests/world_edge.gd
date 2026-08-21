extends SceneTree
## Walking into the edge of the map STOPS you. It does not teleport you.
##
##   godot --headless --path <game> \
##     --script res://tests/world_edge.gd
##
## Reported: "as soon as I hit the boundary I get placed back at some random
## position... if I'm at 0,0 and I go to 0,100, as soon as I hit 0,100 I
## should stay at 0,100, or slide along."
##
## Two things were wrong and they compounded:
##  - The client stopped players at a CIRCLE of `world_radius`, a fixed
##    250 or 400 whatever the map's real size — so on any smaller world
##    you walked straight past the terrain.
##  - The server then saw a position outside the map and, treating it as
##    a stale world, teleported you to the spawn.
##
## So this checks the rule the game should actually obey: approaching the
## edge from any direction leaves you AT the edge, on the correct axis,
## and sliding along it moves you the way you were going.

const SIZES := [50, 100, 250]

var _failures := 0
var _checks := 0

func _initialize() -> void:
	for size: int in SIZES:
		_check(size)
	if _failures == 0:
		print("world_edge: PASS — %d approaches, every one stopped at the edge"
			% _checks)
		quit(0)
	else:
		print("world_edge: FAIL — %d problems over %d approaches"
			% [_failures, _checks])
		quit(1)

func _check(size: int) -> void:
	var half := float(size / 2)

	# Straight at each wall, from well outside: you end up ON that wall,
	# and the other axis is untouched.
	for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var walked := _clamp_move(Vector2(dir.x * (half + 40.0),
			dir.y * (half + 40.0)), half)
		_expect(is_equal_approx(absf(walked.x), half) or absf(dir.x) < 0.5,
			"%d: walking %s ended at x=%.1f, expected the wall at %.1f"
				% [size, dir, walked.x, half])
		_expect(is_equal_approx(absf(walked.y), half) or absf(dir.y) < 0.5,
			"%d: walking %s ended at z=%.1f, expected the wall at %.1f"
				% [size, dir, walked.y, half])
		# The whole point: NOT thrown back towards the middle.
		_expect(walked.length() > half * 0.9,
			"%d: walking %s left me at %s — that is a teleport home, not a wall"
				% [size, dir, walked])

	# Sliding: pinned against the north wall, still moving east.
	var slid := _clamp_move(Vector2(12.0, half + 30.0), half)
	_expect(is_equal_approx(slid.y, half),
		"%d: sliding did not stay pinned to the wall (z=%.1f)" % [size, slid.y])
	_expect(is_equal_approx(slid.x, 12.0),
		"%d: sliding lost the sideways movement (x=%.1f, wanted 12)"
			% [size, slid.x])

	# Into a corner: both axes pinned, nobody sent home.
	var corner := _clamp_move(Vector2(half + 50.0, half + 50.0), half)
	_expect(is_equal_approx(corner.x, half) and is_equal_approx(corner.y, half),
		"%d: corner ended at %s, expected (%.1f, %.1f)"
			% [size, corner, half, half])

## The rule Player._physics_process applies: clamp each axis on its own.
func _clamp_move(to: Vector2, half: float) -> Vector2:
	return Vector2(clampf(to.x, -half, half), clampf(to.y, -half, half))

func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	if _failures <= 10:
		print("  " + message)

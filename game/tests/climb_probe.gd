extends Node
## WORLD_CLIMB_TEST=<height>: walk into a wall and see whether you get over it.
##
##   WORLD_CLIMB_TEST=6 WORLD_AUTOTEST=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --headless --path game
##
## The bug this exists for is "the climb buzzes just under the lip instead
## of finishing", which is a shape in a height-over-time graph. Nothing
## else in this repository can see it: no error, no crash, the player is
## simply an inch below the top forever. It has been reported twice and
## survived one fix.
##
## Everything is built ABOVE the terrain, on a platform, so the answer does
## not depend on where the player happened to spawn. An earlier version
## used the ground where it found it and gave a different verdict on every
## run, which is worse than no test.
##
## Built through the SERVER rather than into the client's own chunk view:
## the server keeps streaming the authoritative chunk and wipes anything
## drawn locally, and the player walked through where the wall had been.

const WALL_AT := 3             ## blocks ahead of the start
## Generous, because a headless run is time-dilated: physics steps are
## capped per frame, so a climb at one block a second takes far longer
## than a wall-clock second per block. An eight-second window failed
## climbs that were working perfectly and still going up.
const SETTLE_SECONDS := 45.0
const START_AFTER := 6.0

var _t := 0.0
var _phase := 0
var _base := 0.0
var _best := 0.0
var _high := 6
var _held: HeldForward = null
var _heights: Array = []
var _origin := Vector3i.ZERO

## An input that does one thing: pushes forward, forever.
class HeldForward extends InputSlot:
	## Off until the scenery is up: the player has to hover in place while
	## the platform is built under them, and a bot at the controls would
	## walk off before it existed.
	var go := false
	func _init() -> void:
		super(Kind.GAMEPAD, -900)
	func get_move_vector() -> Vector2:
		return Vector2(0, -1) if go else Vector2.ZERO
	func get_look_vector() -> Vector2:
		return Vector2.ZERO
	func is_jump_pressed() -> bool:
		return false
	func is_sneak_pressed() -> bool:
		return false
	func is_lift_pressed() -> bool:
		return false

func _me() -> Player:
	if Game.world == null or Game.world.players == null:
		return null
	for child in Game.world.players.get_children():
		if child is Player and child.is_local:
			return child
	return null

## A WALL, BUILT ON THE GROUND IN FRONT OF THE PLAYER.
##
## On the ground and bottom-up, because the server refuses any block with
## nothing solid beside it. A platform in mid-air — which is what this
## tried first, to be independent of the landscape — cannot be placed at
## all, and every edit came back refused.
##
## HeldForward pushes (0, -1), which with camera_yaw 0 is -z, so the wall
## goes that way.
func _build(world: WorldNode, me: Player) -> void:
	var y := floori(me.position.y)
	var at_z := floori(me.position.z) - WALL_AT
	# Ascending, so each course rests on the one below and every block is
	# supported when it is placed.
	# Narrow and one deep, so even the top course of a ten-block wall is
	# inside WorldNode.EDIT_RANGE. A wider one had its upper courses
	# quietly refused and the test then measured a wall half the height
	# it thought it had built.
	for up in range(0, _high):
		for dx in range(-1, 2):
			for deep in range(0, 1):
				world.send_edit(me.slot,
					Vector3i(floori(me.position.x) + dx, y + up, at_z - deep),
					Blocks.STONE)

func _physics_process(delta: float) -> void:
	_t += delta
	if _t < START_AFTER:
		return
	var me := _me()
	var world: WorldNode = Game.world
	if me == null or world == null or world.chunks == null:
		return
	match _phase:
		0:
			# Take the controls first — the autotest bot is still driving
			# and would walk off before anything is built — but stand
			# still, so the server's idea of where we are settles.
			_high = maxi(int(OS.get_environment("WORLD_CLIMB_TEST")), 2)
			_held = HeldForward.new()
			me.input = _held
			_phase = 1
			_t = 0.0
		1:
			me.input = _held
			if _t < 0.8:
				return          # let the server hear where we are standing
			_origin = Vector3i(floori(me.position.x), floori(me.position.y),
				floori(me.position.z) - WALL_AT)
			_build(world, me)
			_phase = 2
			_t = 0.0
		2:
			me.input = _held
			if _t < 1.0:
				return          # ...and let the wall come back
			if not Blocks.is_solid(world.chunks.get_block(_origin)):
				print("CLIMB: FAIL the wall was never built")
				get_tree().quit(1)
				return
			# HOW TALL DID IT ACTUALLY COME OUT? Blocks beyond
			# WorldNode.EDIT_RANGE are refused, so asking for ten courses
			# can get you six — and measuring against the number that was
			# ASKED for then fails a climb that worked perfectly.
			var built := 0
			while built < _high and Blocks.is_solid(world.chunks.get_block(
					_origin + Vector3i(0, built, 0))):
				built += 1
			if built < _high:
				print("CLIMB: asked for %d courses, the server allowed %d"
					% [_high, built])
			_high = built
			_base = me.position.y
			_best = _base
			_held.go = true
			print("CLIMB: %d-high wall, standing at %.2f, its top is %.2f"
				% [_high, _base, _base + float(_high)])
			_phase = 3
			_t = 0.0
		3:
			me.input = _held
			# EVERY FRAME. Movement is relative to the camera and the
			# split-screen rig keeps turning it, so "hold forward" quietly
			# became "walk in a slow circle".
			me.camera_yaw = 0.0
			me.look_yaw = 0.0
			_best = maxf(_best, me.position.y)
			if int(_t * 4.0) > _heights.size():
				_heights.append(snappedf(me.position.y - _base, 0.01))
			if _t < SETTLE_SECONDS:
				return
			print("CLIMB: heights (quarter-second samples, blocks above start)")
			print("CLIMB: " + str(_heights))
			print("CLIMB: best=%.2f wall=%d final=%.2f"
				% [_best - _base, _high, me.position.y - _base])
			var over: bool = me.position.y - _base >= float(_high) - 0.4
			print("CLIMB: %s got over a %d-block wall"
				% ["ok  " if over else "FAIL", _high])
			_phase = 4
			get_tree().quit(0 if over else 1)

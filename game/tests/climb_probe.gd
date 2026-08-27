extends Node
## WORLD_CLIMB_TEST=<height>: walk into a wall and see whether you get over it.
##
##   WORLD_ROLE=client WORLD_CLIMB_TEST=6 WORLD_AUTOTEST=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --headless --path game
##
## WORLD_ROLE=client is load-bearing and was missing from every copy of
## this line: headless implies SERVER, so without it the command starts a
## second world and connects to nothing at all.
##
## The bug this exists for is "the climb buzzes just under the lip instead
## of finishing", which is a shape in a height-over-time graph. Nothing
## else in this repository can see it: no error, no crash, the player is
## simply an inch below the top forever. It has been reported twice and
## survived one fix.
##
## EVERY WRONG ANSWER THIS HAS EVER GIVEN WAS THE SCENERY, NOT THE CLIMB,
## and each one arrived dressed as a climb verdict. Written down because
## the next person to touch this will otherwise rediscover them one at a
## time, ninety seconds a run:
##
##   An unstreamed chunk reads as STONE (ChunkView.get_block, deliberately,
##   so nobody falls out of a world that has not arrived). A player forty
##   blocks above the landscape therefore stands on phantom rock with
##   `on_floor` true and a height stable to the centimetre.
##
##   Searching a column downward FROM ABOVE the player finds the highest
##   thing in it, which under a tree is the canopy. The wall went up in
##   the branches.
##
##   The spawn is near the sea on this map, and the ground three blocks
##   ahead was routinely a ditch, a hillside or open water — so a fill
##   that needed ground under it was refused, every course of it.
##
##   Standing on a vehicle makes you its DRIVER, and this probe holds the
##   stick forward forever. That is not a walk, it is full throttle.
##
##   Movement is relative to the CAMERA, and the camera is turned by
##   `Game.local_inputs`, which is a different object from the one the
##   player walks on. The autotest bot went on steering while this pushed
##   "forward".
##
##   `START_AFTER` was tested against a timer that is reset at every phase
##   change, so each phase opened with a six-second blackout — and the
##   whole climb happened inside the one at the start of the measuring
##   phase.
##
## Hence the shape of what follows: it lays its own footing rather than
## trusting the landscape, waits for real ground under a settled body,
## takes the seat's input as well as the player's, and gives each of those
## failures its own answer instead of calling it a failed climb.
##
## Built through the SERVER rather than into the client's own chunk view:
## the server keeps streaming the authoritative chunk and wipes anything
## drawn locally, and the player walked through where the wall had been.

## HOW FAR AHEAD THE WALL GOES UP. TWO, and it used to be three.
##
## The walk to the wall was the single largest source of wrong answers
## this probe has given, and none of them were about climbing: the player
## walked off a ledge, into a dip, or into the sea, and the run reported a
## failed climb about a wall it never reached. A run-up buys nothing — a
## climb needs only "blocked, and still pushing" — so the walk is now one
## block, over a footing this file lays itself.
##
## NOT ONE, though, and the reason is the player's own width. A body is
## 0.8 blocks across, so standing at z=91.0 it occupies 90.6 to 91.4 and
## overlaps the column at z=90. Building the wall there builds it INSIDE
## the player, and Player's "a block appeared where you are standing"
## rule then gently lifts them out of it — straight up the six courses to
## the top, before the test had started. The run reported a player
## standing on the summit and called it a levelling failure.
const WALL_AT := 2             ## blocks ahead of the start
## Generous, because a headless run is time-dilated: physics steps are
## capped per frame, so a climb at one block a second takes far longer
## than a wall-clock second per block. An eight-second window failed
## climbs that were working perfectly and still going up.
const SETTLE_SECONDS := 45.0
const START_AFTER := 6.0

var _t := 0.0
## Since the probe started, as opposed to since this phase started.
var _boot := 0.0
var _phase := 0
var _base := 0.0
var _best := 0.0
var _high := 6
var _held: HeldForward = null
var _heights: Array = []
var _origin := Vector3i.ZERO
## How long to wait for the world to arrive and the body to stop moving.
## Generous: a headless client streams chunks on worker threads and the
## whole run is worthless if it starts before they land.
const SETTLE_LIMIT := 60.0

## IS THE GROUND UNDER THE PLAYER REAL YET?
##
## An unstreamed chunk reads as STONE — see ChunkView.get_block, where it
## is deliberate so nobody falls out of a world that has not arrived. The
## consequence for a probe is brutal and completely silent: a player forty
## blocks above the landscape stands on phantom rock, `on_floor` is true,
## the height is stable to the centimetre, and every measurement taken is
## of a place that does not exist. Then the chunk arrives, the floor
## evaporates, and the player drops forty blocks in one frame.
##
## That is what produced a run reporting a six-block wall, a settled
## player, and a climb that never started. So: the player's own chunk and
## all eight around it have to have actually arrived first.
func _streamed(world: WorldNode, me: Player) -> bool:
	var here := Vector2i(floori(me.position.x / 16.0), floori(me.position.z / 16.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not world.chunks.has_chunk(here + Vector2i(dx, dz)):
				return false
	return true

## The y of the block the player is standing ON, once it has settled.
var _floor := 0
## The column the player settled in. Everything is measured and built from
## this, never from `position` re-read a frame later.
var _anchor := Vector2i.ZERO
## How long the player has been at exactly one height, and which.
var _settled_at := INF
var _settled_t := 0.0
## When the last progress line was printed.
var _said := 0.0
## Whether the far side of the wall has been reached.
var _crossed := false
## Per-frame [height above the start, z past the wall], most recent last.
var _frames: Array = []

## An input that does one thing: walks the player due -z, forever.
##
## NOT "pushes the stick forward" — that is what it used to be, and it is
## not the same thing. Movement is taken RELATIVE TO THE CAMERA
## (`dir = move.rotated(UP, camera_yaw)`), and the camera is turned by the
## split-screen rig from `Game.local_inputs`, which is a different object
## from the one the player is walking on. So the autotest bot went on
## quietly spinning the camera while this pushed "forward", and forward
## became whatever direction the camera had reached — measured at a
## quarter turn off, which walked the player twenty-nine blocks sideways
## away from the wall in six seconds while the height trace patiently
## recorded a field.
##
## The stick position is therefore derived from the camera every time it
## is asked for, which is the moment the player uses it. Whatever the
## camera is doing, the body walks due -z.
class HeldForward extends InputSlot:
	## Off until the scenery is up: the player has to stand still while
	## the wall is built beside them, and a bot at the controls would walk
	## off before it existed.
	var go := false
	var body: Player = null
	func _init() -> void:
		super(Kind.GAMEPAD, -900)
	func get_move_vector() -> Vector2:
		if not go:
			return Vector2.ZERO
		var yaw := 0.0 if body == null else float(body.camera_yaw)
		# The inverse of `Vector3(mx, 0, mz).rotated(UP, yaw)` applied to
		# (0, 0, -1). Checked at yaw 0, where it is plain (0, -1).
		return Vector2(sin(yaw), -cos(yaw))
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
## THE FLOOR OF A COLUMN AT THE PLAYER'S OWN LEVEL — searched from their
## feet DOWNWARD, never from above them.
##
## It used to start four blocks ABOVE the player and take the first solid
## block on the way down, which is not the ground: it is the highest thing
## in the window. Under a tree that is the canopy. Measured on a run that
## reported a perfectly good six-block wall and a player that never
## touched it: the player was standing at y=22, the search returned 26,
## and the whole wall was built in the branches five blocks over their
## head. The probe then patiently watched somebody walk about in a wood
## for forty-five seconds and called it a failed climb.
##
## Downward from the feet finds the block being stood on. A column whose
## terrain is HIGHER than the player returns the player's own level, which
## is right too — `_level` then cuts a trench through the hillside at that
## height rather than trying to build on top of it.
##
## Returns `from_y - 1` when the column is empty for the whole search,
## which is a hole deeper than anything worth levelling.
func _ground_at(world: WorldNode, wx: int, wz: int, from_y: int) -> int:
	for y in range(from_y, from_y - 13, -1):
		if Blocks.is_solid(world.chunks.get_block(Vector3i(wx, y, wz))):
			return y
	return from_y - 1

## THE WALL'S FOOTING IS LAID FIRST, and that is not tidiness.
##
## The column in front of the player is whatever the landscape put there,
## and every way it can differ from the ground underfoot has produced a
## confident, wrong verdict from this probe:
##
##   GROUND THAT RISES — the first course lands inside the hillside,
##   placing into solid rock is refused, and every course above it is then
##   unsupported and refused as well. Reported as "the wall was never
##   built" on ground that was perfectly good to climb.
##
##   GROUND THAT FALLS AWAY, or water, or a ravine — nothing solid within
##   thirteen blocks to build from, so the first course hangs in the air
##   and is refused. The spawn on this map is near the sea and this is
##   what it kept getting.
##
## So the footing is BRIDGED rather than found: one block laid at the
## level of the block the player is standing on, in the column beside
## them. The server asks only for a solid NEIGHBOUR, and the player's own
## floor is one — so this works over water, over a chasm and into a
## hillside without caring which it is. Anything standing above it is then
## dug out, and the wall goes up in the slot.
##
## HeldForward pushes (0, -1), which with camera_yaw 0 is -z, so all of
## this runs that way.
func _level(world: WorldNode, me: Player, floor_y: int) -> void:
	# Outward, and the middle of each rank before its sides: every
	# placement then has a neighbour that was placed the step before, and
	# the first has the player's own floor.
	for deep in range(1, WALL_AT + 1):
		for dx in [0, -1, 1]:
			world.send_edit(me.slot,
				Vector3i(_anchor.x + dx, floor_y, _anchor.y - deep), Blocks.STONE)
	# Anything standing above the footing is dug out, or a rising hillside
	# leaves nowhere to put the courses and nowhere to walk.
	for deep in range(1, WALL_AT + 1):
		var cz := _anchor.y - deep
		for dx in range(-1, 2):
			var cx := _anchor.x + dx
			for y in range(floor_y + 1, floor_y + _high + 4):
				if Blocks.is_solid(world.chunks.get_block(Vector3i(cx, y, cz))):
					world.send_edit(me.slot, Vector3i(cx, y, cz), Blocks.AIR)

## A WALL, BUILT IN THAT SLOT.
##
## On the ground and bottom-up, because the server refuses any block with
## nothing solid beside it. A platform in mid-air — which is what this
## tried first, to be independent of the landscape — cannot be placed at
## all, and every edit came back refused.
##
## HeldForward pushes (0, -1), which with camera_yaw 0 is -z, so the wall
## goes that way.
##
## Narrow and one deep, so even the top course of a ten-block wall is
## inside WorldNode.EDIT_RANGE. A wider one had its upper courses quietly
## refused and the test then measured a wall half the height it thought it
## had built.
## FROM THE ANCHOR, NOT FROM THE PLAYER'S POSITION RIGHT NOW.
##
## The corridor is levelled in one frame and the wall raised in a later
## one, and `floori` of a position that has drifted a tenth of a block can
## land in the next column along. When it does, the wall goes up one block
## to the side of where the run then looks for it — and the verdict is
## "the wall was never built" about a wall standing right beside the
## place it was checked. Everything measures from the same fixed pair of
## coordinates, taken once.
func _build(world: WorldNode, me: Player, floor_y: int) -> void:
	var at_z := _anchor.y - WALL_AT
	for up in range(0, _high):
		for dx in range(-1, 2):
			world.send_edit(me.slot,
				Vector3i(_anchor.x + dx, floor_y + 1 + up, at_z), Blocks.STONE)
	print("CLIMB: wall asked for at x=%d..%d, y=%d..%d, z=%d"
		% [_anchor.x - 1, _anchor.x + 1, floor_y + 1, floor_y + _high, at_z])

func _physics_process(delta: float) -> void:
	_t += delta
	_boot += delta
	# THE OPENING WAIT IS THE OPENING WAIT, and only that.
	#
	# This tested `_t`, which is reset to zero at EVERY phase change — so
	# each phase began with a six-second blackout in which this function
	# returned immediately and measured nothing. The player, meanwhile, had
	# already been told to walk. The whole climb therefore happened inside
	# the blackout at the start of the measuring phase, and the first frame
	# that was ever sampled found the player over the wall and on its way
	# down the far side. Every height trace this probe has printed was of
	# the AFTERMATH.
	if _boot < START_AFTER:
		return
	var me := _me()
	var world: WorldNode = Game.world
	if me == null or world == null or world.chunks == null:
		return
	# NOBODY IS DRIVING ANYTHING TODAY.
	#
	# The world puts five boats and three cars out near the spawn, which
	# is where this probe starts, and standing on one makes you its
	# DRIVER — at which point HeldForward's "hold forward, forever" stops
	# being a walk and becomes full throttle. Measured: a run that built a
	# perfectly good wall and then reported on a player who had driven
	# forty-eight blocks away from it in six seconds, on an empty field.
	#
	# `_ride_was` is what the carry is actually based on (being aboard
	# LAST frame), so clearing both every frame is what stops it, whatever
	# order the nodes tick in. A probe about climbing has no business
	# being a probe about boats.
	me.ride_id = ""
	me._ride_was = ""
	match _phase:
		0:
			# Take the controls first — the autotest bot is still driving
			# and would walk off before anything is built — but stand
			# still, so the server's idea of where we are settles.
			_high = maxi(int(OS.get_environment("WORLD_CLIMB_TEST")), 2)
			_held = HeldForward.new()
			_held.body = me
			me.input = _held
			# AND THE SEAT'S REGISTERED INPUT TOO. The split-screen rig
			# reads `Game.local_inputs`, not the player's own slot, so
			# leaving the autotest bot in there leaves it driving the
			# camera, the trigger, the dig button and the flight toggle
			# for the whole run.
			Game.local_inputs[me.slot] = _held
			_phase = 1
			_t = 0.0
		1:
			me.input = _held
			_held.body = me
			# STOOD STILL ON THE GROUND, NOT FLYING, AND NOT MOVING.
			#
			# Three separate things have each produced a confident verdict
			# about a wall that was never there, and all three are this
			# moment:
			#
			#   FLYING. The autotest slot that drives the player before the
			#   probe takes over double-taps its way into flight, and
			#   flight survives the handover — so the scenery was measured
			#   from a player floating forty blocks up.
			#
			#   STILL FALLING. `on_floor` is true for a frame at a time
			#   while a body settles, so a single test of it caught the
			#   player mid-drop.
			#
			#   STILL STREAMING. Chunks arrive after the player does, and
			#   when the ground under them finally exists they are lifted
			#   onto it — a block of movement AFTER everything was
			#   measured, which is exactly the block the last run was out
			#   by.
			#
			# So: not flying, on the floor, and at the same height for a
			# good half second before anything is built.
			me.fly_mode = false
			# NOT ABOARD ANYTHING, and this one cost a whole afternoon.
			#
			# The world puts five boats and three cars out near the spawn,
			# and the spawn is where this probe starts. A deck reads as
			# `on_floor` and holds a perfectly stable height, so the settle
			# test passes on one — and standing on a vehicle makes you its
			# DRIVER, at which point HeldForward's "hold forward forever"
			# stops being a walk and becomes full throttle. The run
			# measured a wall built on solid ground and then reported on a
			# player who had driven a car twenty-nine blocks across the
			# map. Every reading was of an empty field.
			#
			# So: step off, and keep stepping until there is nothing under
			# the feet but world.
			if world.vehicle_view != null \
					and not world.vehicle_view.deck_under(me.position).is_empty():
				me.position += Vector3(5.0, 1.0, 0.0)
				me.ride_id = ""
				_settled_at = INF
				_settled_t = 0.0
				if _t < SETTLE_LIMIT:
					return
			if not _streamed(world, me) or not me.on_floor \
					or absf(me.position.y - _settled_at) > 0.02:
				_settled_at = me.position.y
				_settled_t = 0.0
				if _t < SETTLE_LIMIT:
					return
			else:
				_settled_t += delta
				if _settled_t < 0.6 and _t < SETTLE_LIMIT:
					return
			if _settled_t < 0.6:
				# NOT A CLIMB VERDICT. Every wrong answer this probe has
				# given was really this — the scenery was not what the code
				# thought it was — dressed up as a failed climb, so it gets
				# its own exit and says what actually went wrong.
				print("CLIMB: FAIL the player never settled on real ground "
					+ "(at %.2f, streamed=%s, on_floor=%s)"
					% [me.position.y, str(_streamed(world, me)), str(me.on_floor)])
				get_tree().quit(1)
				return
			# THE FLOOR THE PLAYER IS STANDING ON. Taken from the body
			# rather than from a block search: a settled player's feet ARE
			# the top of the floor, and no search can disagree with that.
			_floor = floori(me.position.y) - 1
			_anchor = Vector2i(floori(me.position.x), floori(me.position.z))
			_level(world, me, _floor)
			_origin = Vector3i(_anchor.x, _floor + 1, _anchor.y - WALL_AT)
			_phase = 2
			_t = 0.0
		2:
			# The clearing first, its answers back from the server, and
			# only THEN the wall. Sending both in one frame means building
			# into cells the server has not been told to empty yet.
			me.input = _held
			if _t < 1.0:
				return
			_build(world, me, _floor)
			_phase = 3
			_t = 0.0
		3:
			me.input = _held
			if _t < 1.5:
				return          # ...and let the wall come back
			var seen: Array = []
			for y in range(_floor - 1, _floor + _high + 3):
				seen.append(world.chunks.get_block(Vector3i(_origin.x, y, _origin.z)))
			print("CLIMB: player at (%.1f,%.2f,%.1f), wall column at (%d,%d) "
				% [me.position.x, me.position.y, me.position.z,
					_origin.x, _origin.z]
				+ "from y=%d is %s" % [_floor - 1, str(seen)])
			if not Blocks.is_solid(world.chunks.get_block(_origin)):
				print("CLIMB: FAIL the wall was never built")
				get_tree().quit(1)
				return
			# HOW TALL DID IT ACTUALLY COME OUT? Blocks beyond
			# WorldNode.EDIT_RANGE are refused, so asking for ten courses
			# can get you six — and measuring against the number that was
			# ASKED for then fails a climb that worked perfectly.
			# EVERY COLUMN OF IT, and the answer is the SHORTEST.
			#
			# The wall is three columns wide and the player is 0.8 wide, so
			# it crosses over two of them — and only the middle one used to
			# be measured. A run where one edge column came out a course
			# short reported a six-block wall, watched the player top out
			# on the five-block side at exactly the right moment, and
			# failed it for being a foot below a lip that was not there.
			var courses: Array = []
			var built := _high
			for dx in range(-1, 2):
				var tall := 0
				while tall < _high and Blocks.is_solid(world.chunks.get_block(
						_origin + Vector3i(dx, tall, 0))):
					tall += 1
				courses.append(tall)
				built = mini(built, tall)
			if built < _high:
				print("CLIMB: asked for %d courses, the server allowed %s"
					% [_high, str(courses)])
			_high = built
			# The top of the corridor, so "blocks above the start" means
			# blocks above the ground the wall stands on.
			_base = float(_floor) + 1.0
			_best = _base
			_held.go = true
			print("CLIMB: %d-high wall, standing at %.2f, its top is %.2f"
				% [_high, _base, _base + float(_high)])
			# AND THE PLAYER HAS TO BE STANDING ON THE THING WE BUILT.
			# Every wrong verdict this probe has given was really a
			# scenery failure wearing a climb verdict's clothes, so that
			# is now its own answer and not a FAIL about climbing.
			if absf(me.position.y - _base) > 0.6:
				print("CLIMB: FAIL the ground was not levelled — "
					+ "standing at %.2f, corridor floor is %.2f"
					% [me.position.y, _base])
				get_tree().quit(1)
				return
			_phase = 4
			_t = 0.0
		4:
			me.input = _held
			_held.body = me
			# EVERY FRAME. Movement is relative to the camera and the
			# split-screen rig keeps turning it, so "hold forward" quietly
			# became "walk in a slow circle".
			me.camera_yaw = 0.0
			me.look_yaw = 0.0
			_best = maxf(_best, me.position.y)
			if int(_t * 4.0) > _heights.size():
				_heights.append(snappedf(me.position.y - _base, 0.01))
			# WHAT THE BODY IS ACTUALLY DOING, a few times over the run.
			# A height trace says a climb stalled; it cannot say whether
			# the player was against the wall, on the floor, or thirty
			# blocks past it walking up a hill — and this probe has
			# reported all three as the same number.
			if _t - _said > 6.0:
				_said = _t
				print("CLIMB: t=%.0fs %s at (%.1f,%.2f,%.1f) wall_z=%d yaw=%.2f "
					% [_t, me.player_id, me.position.x, me.position.y,
						me.position.z, _anchor.y - WALL_AT, me.camera_yaw]
					+ "on_floor=%s climbing=%s mantle=%.2f input=%s"
					% [str(me.on_floor), str(me._climbing), me._top_out,
						me.input.describe()])
			# THE MOMENT IT CROSSES, whatever height that turns out to be.
			# Printed because "it ended up on the far side at a height the
			# pass test never saw" is a contradiction, and the way to
			# settle a contradiction is to write down the number.
			# EVERY FRAME, kept in a ring, so the moment of crossing can be
			# read back rather than guessed at. A quarter-second sample is
			# far too coarse for a move that takes a third of one.
			_frames.append([snappedf(me.position.y - _base, 0.01),
				snappedf(me.position.z - float(_anchor.y - WALL_AT), 0.01)])
			if _frames.size() > 400:
				_frames.remove_at(0)
			if not _crossed and me.position.z < float(_anchor.y - WALL_AT):
				_crossed = true
				print("CLIMB: crossed the wall at t=%.1fs, %.2f above the start "
					% [_t, me.position.y - _base]
					+ "(best so far %.2f, wall is %d)"
					% [_best - _base, _high])
				print("CLIMB: last frames before it, as [height, z past the wall]")
				print("CLIMB: " + str(_frames.slice(maxi(0, _frames.size() - 30))))
			# OVER THE TOP IS THE ANSWER, and the moment it happens.
			#
			# Waiting out the settle window to decide was how the run
			# before this one FAILED a climb it had already completed: the
			# player went over the wall, kept walking, passed the "are you
			# still at the wall" guard four blocks the other side of it,
			# and was failed for leaving. What is being measured is
			# whether it got over. Once it has, there is nothing left to
			# watch.
			if me.position.y - _base >= float(_high) - 0.4:
				print("CLIMB: heights (quarter-second samples, blocks above start)")
				print("CLIMB: " + str(_heights))
				print("CLIMB: best=%.2f wall=%d final=%.2f after %.1fs"
					% [maxf(_best, me.position.y) - _base, _high,
						me.position.y - _base, _t])
				print("CLIMB: ok   got over a %d-block wall" % _high)
				_phase = 5
				get_tree().quit(0)
				return
			# ...AND IT HAS TO STILL BE AT THE WALL. A player that has
			# wandered off SIDEWAYS is not a failed climb, and reporting it
			# as one is how this probe has produced its most confident
			# nonsense. Going past the wall is not wandering off — that is
			# caught above, as a pass.
			if absf(me.position.x - float(_anchor.x)) > 6.0 \
					or me.position.z > float(_anchor.y) + 3.0 \
					or me.position.z < float(_anchor.y - WALL_AT) - 8.0:
				print("CLIMB: FAIL the player left the wall — at (%.1f,%.1f), "
					% [me.position.x, me.position.z]
					+ "wall is at x=%d z=%d, best was %.2f of %d"
					% [_anchor.x, _anchor.y - WALL_AT, _best - _base, _high])
				get_tree().quit(1)
				return
			if _t < SETTLE_SECONDS:
				return
			print("CLIMB: heights (quarter-second samples, blocks above start)")
			print("CLIMB: " + str(_heights))
			print("CLIMB: best=%.2f wall=%d final=%.2f"
				% [_best - _base, _high, me.position.y - _base])
			var over: bool = me.position.y - _base >= float(_high) - 0.4
			print("CLIMB: %s got over a %d-block wall"
				% ["ok  " if over else "FAIL", _high])
			_phase = 5
			get_tree().quit(0 if over else 1)

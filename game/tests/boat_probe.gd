extends Node
## WORLD_BOAT_TEST=1: does standing on a boat actually carry you?
##
##   WORLD_BOAT_TEST=1 WORLD_AUTOTEST=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --headless --path game
##
## The maths behind riding is covered by tests/unit/vehicle_geom_test.gd,
## which needs no world at all. What that CANNOT see is the wiring: does
## the player notice it is standing on a deck, is the deck found under its
## feet, does the carry run in the right order relative to the player's own
## movement, and does any of it survive the boat turning.
##
## So this puts a real player on a real boat in a real world and moves the
## boat underneath them. Two cases, and the second is the one that matters:
##
##   TRAVEL   the boat moves in a straight line and the rider goes with it
##   TURN     the boat spins on the spot and the rider swings round with
##            it, staying on the same spot of the deck
##
## The turn is where a position-delta implementation looks perfect and is
## wrong: everybody slides off the side, because the stern travels further
## than the bow.
##
## Client side, because riding is: the driver's machine owns the boat and
## the rider's machine does the carrying.

const START_AFTER := 7.0
## Measured in PHYSICS FRAMES, not seconds. The carry happens once per
## physics tick, so a case is set up on one tick and read on the next —
## and a test that waited half a second instead gave the player thirty
## ticks in which to walk off the boat on its own.
const SETTLE := 2

## A TURN THE WAY THE HELM DOES IT: a slice of a radian a frame, for long
## enough that anything lost per frame has somewhere to accumulate. At a
## boat's own BOAT_TURN of 1.5 rad/s these forty frames are about two
## thirds of a turn, which is a normal thing to ask of a boat and much
## more than a single-frame snap can ever reveal.
const TURN_FRAMES := 40
const TURN_STEP := 0.026

var _t := 0.0
var _phase := 0
var _ticks := 0
var _vid := ""
var _from := Vector3.ZERO
## Where the rider was standing in the boat's own frame before a turn, and
## which way they were pointing along her.
var _spot := Vector3.ZERO
var _faced := 0.0
var _had := 0
var _waited := 0.0
var _failures := 0
var _quiet: InputSlot = null
var _helm_hard: InputSlot = null

## Throttle open and the wheel hard over. Player._ride reads the move
## vector as [steer, -throttle], so this is "full ahead, turning".
class HelmHard extends InputSlot:
	func _init() -> void:
		super(Kind.GAMEPAD, 98)
	func get_move_vector() -> Vector2:
		return Vector2(1.0, -1.0)
	func get_look_vector() -> Vector2:
		return Vector2.ZERO
	func is_jump_pressed() -> bool:
		return false
	func is_sneak_pressed() -> bool:
		return false
	func is_lift_pressed() -> bool:
		return false

func _ready() -> void:
	print("BOAT: probe armed")

func _report(pass_now: bool, what: String) -> void:
	print("BOAT: %s %s" % ["ok  " if pass_now else "FAIL", what])
	if not pass_now:
		_failures += 1

func _me() -> Player:
	if Game.world == null or Game.world.players == null:
		return null
	for child in Game.world.players.get_children():
		if child is Player and child.is_local:
			return child
	return null

## On the PHYSICS tick, because that is where riding happens.
func _physics_process(delta: float) -> void:
	_t += delta
	if _t < START_AFTER:
		return
	var me := _me()
	var world: WorldNode = Game.world
	if me == null or world == null or world.vehicle_view == null:
		return
	var view: VehicleView = world.vehicle_view
	# THE PLAYER HAS TO STOP DRIVING ITSELF. Under WORLD_AUTOTEST the local
	# seat is a bot pressing buttons at random, and it will happily jump
	# off the boat in the middle of the measurement — which it did.
	if _quiet == null:
		_quiet = InputSlot.new(InputSlot.Kind.GAMEPAD, 99)
		_helm_hard = HelmHard.new()
	# Whatever is driving THIS phase. Every phase but the steering one
	# wants the controls held still; that one wants them held over.
	if me.input != _helm_hard:
		me.input = _quiet
	_ticks += 1
	match _phase:
		0:
			if view.vehicles.is_empty():
				if _t > START_AFTER + 20.0:
					_report(false, "no vehicles ever arrived from the server")
					_finish()
				return
			# ONE NOBODY IS ALREADY DRIVING. This runs as a second client
			# against a world that already has players in it, and the
			# first one aboard keeps the helm — so grabbing whichever
			# boat came first and then asserting the wheel is yours is a
			# test of who got there first, not of whether steering works.
			_vid = ""
			for vid_v: Variant in view.vehicles.keys():
				if view.driver_of(str(vid_v)).is_empty():
					_vid = str(vid_v)
					break
			if _vid.is_empty():
				if _t > START_AFTER + 20.0:
					_report(false, "every vehicle already had a driver")
					_finish()
				return
			_stand_on(me, view, Vector3(0.0, 0.0, 0.0))
			_step()
		1:
			if _ticks < SETTLE:
				return
			var vv: Dictionary = view.at(_vid)
			_report(me.ride_id == _vid,
				"standing on a boat is noticed (ride_id=%s)" % me.ride_id)
			if me.ride_id != _vid:
				print("BOAT: dbg player=%v boat=%v deck=%.2f" % [me.position,
					Vector3(vv.pos), VehicleGeom.deck_at(int(vv.kind), Vector3(vv.pos))])
				_finish()
				return
			_from = me.position
			# Move the boat out from under them by a known amount — more
			# than a rider is standing from the rail, which is the case
			# that used to drop them into the sea.
			vv.pos = Vector3(vv.pos) + Vector3(6.0, 0.0, 0.0)
			# ...and where it is being pulled towards, or the view's own
			# interpolation drags most of the nudge straight back and the
			# measurement comes out at three quarters of the truth. That
			# is this probe's problem, not the game's: a real boat moves
			# because its driver moved it, and the target moves with it.
			vv.target_pos = vv.pos
			_step()
		2:
			if _ticks < SETTLE:
				return
			var went := me.position - _from
			_report(absf(went.x - 6.0) < 0.7 and absf(went.z) < 0.7,
				"a moving boat carries its rider (moved %.2f, %.2f)"
				% [went.x, went.z])
			# Now at the bow, so a spin actually takes them somewhere. A
			# rider dead centre would not move at all and would prove
			# nothing.
			_stand_on(me, view, Vector3(0.0, 0.0, 2.0))
			_from = me.position
			_step()
		3:
			if _ticks < SETTLE:
				return
			var vv: Dictionary = view.at(_vid)
			vv.yaw = float(vv.yaw) + PI * 0.5
			vv.target_yaw = vv.yaw
			_step()
		4:
			if _ticks < SETTLE:
				return
			var vv: Dictionary = view.at(_vid)
			_report(VehicleGeom.on_deck(int(vv.kind), Vector3(vv.pos),
					float(vv.yaw), me.position),
				"a turning boat does not throw its rider off the side")
			var swung := me.position.distance_to(_from)
			_report(swung > 1.0 and swung < 8.0,
				"and the rider swung round with it (%.2f blocks)" % swung)
			# A REAL TURN, not a teleport, and this is the case that was
			# missing. Everything above snaps the yaw round by a quarter
			# turn in ONE frame and then asks whether the rider is still
			# aboard — which a carry can get right while still losing a
			# little of the rider's spot on every frame of a turn that
			# takes a second and a half. Reported from play as "when you
			# turn, your position on the boat moves", and invisible to a
			# single-frame check by construction.
			#
			# So: turn her the way the helm does, a slice at a time, and
			# measure the rider's spot IN THE BOAT'S OWN FRAME at both
			# ends. That number should not move at all.
			_stand_on(me, view, Vector3(0.9, 0.0, 1.8))
			_spot = VehicleGeom.to_local(Vector3(vv.pos), float(vv.yaw),
				me.position)
			_faced = _facing_in_boat(me, vv)
			_step()
		5:
			var turning: Dictionary = view.at(_vid)
			if _ticks <= TURN_FRAMES:
				turning.yaw = float(turning.yaw) + TURN_STEP
				turning.target_yaw = turning.yaw
				return
			if _ticks < TURN_FRAMES + SETTLE:
				return
			var ended := VehicleGeom.to_local(Vector3(turning.pos),
				float(turning.yaw), me.position)
			var slid := Vector2(ended.x - _spot.x, ended.z - _spot.z).length()
			_report(slid < 0.35,
				"a gradual turn leaves the rider on the same spot "
				+ "(slid %.2f blocks: %.2f,%.2f -> %.2f,%.2f over %d frames)"
				% [slid, _spot.x, _spot.z, ended.x, ended.z, TURN_FRAMES])
			# AND FACING THE SAME WAY ALONG HER. Standing on a turning deck
			# turns you: if the bow was ahead of you before the turn it is
			# ahead of you after it. Without this the deck rotates under a
			# body that keeps pointing at the same bit of scenery, which is
			# what "when you turn, your position on the boat moves" turned
			# out to be — the position was never wrong.
			var faced_now := _facing_in_boat(me, turning)
			var swing := absf(wrapf(faced_now - _faced, -PI, PI))
			_report(swing < 0.25,
				"…and still facing the same way along her "
				+ "(turned %.2f rad against the deck over %d frames)"
				% [swing, TURN_FRAMES])
			_step()
		6:
			if _ticks < SETTLE:
				return
			# THE HELM, which is the half this probe never checked. Every
			# test above moves the boat itself and then looks at the
			# rider, so a boat that carried people perfectly and answered
			# nothing at all passed the lot — which is exactly what
			# shipped: "I get on top of them and it pulls me into it but I
			# can't control it".
			var helm: Dictionary = view.at(_vid)
			if view.driver_of(_vid).is_empty() and _ticks < SETTLE * 3:
				# Ask once more and wait. Being carried about by a boat
				# can take you off its deck for a frame, which frees the
				# helm — and the re-board is the game's own path.
				Game.world.sv_vehicle_board.rpc_id(1, _vid, me.slot)
				return
			_report(view.driver_of(_vid) == me.player_id,
				"standing on a boat hands you the helm (driver=%s)"
				% view.driver_of(_vid))
			_report(bool(helm.get("mine", false)),
				"…and this machine knows the helm is its own")
			_from = Vector3(helm.pos)
			_step()
		7:
			# SPEED, not distance travelled. Player._ride drives this same
			# boat every frame with whatever the stick says — nothing,
			# here, because the probe holds the controls still — so a
			# distance measured over several ticks is this probe opening
			# the throttle and the game closing it again, and it comes out
			# at a hundredth of a block however well steering works.
			#
			# One call, and did it take? That is the whole question the
			# helm bug was about: with `mine` false, drive_mine returns
			# false and changes nothing, and the boat carries you about
			# answering none of the controls.
			var before: float = float(view.at(_vid).get("speed", 0.0))
			var answered := view.drive_mine(_vid, 1.0, 0.0, delta)
			var after: float = float(view.at(_vid).get("speed", 0.0))
			_report(answered, "the throttle answers at all")
			_report(after > before,
				"and opening it puts speed on (%.2f → %.2f)" % [before, after])
			_had = view.vehicles.size()
			# PUTTING ONE DOWN, which is the other half nothing covered.
			# The tools tray called `sv_vehicle_place` and no such method
			# existed anywhere, so choosing a boat or a car and clicking
			# did nothing at all, in every mode.
			Game.world.sv_vehicle_place.rpc_id(1, me.slot,
				Vector3i(floori(me.position.x) + 3, floori(me.position.y),
					floori(me.position.z)), VehicleGeom.KIND_CAR)
			_step()
		8:
			# WAIT ON THE ANSWER, not on a tick count. Every other phase
			# here measures something local and two ticks is plenty;
			# this one asked the SERVER for a vehicle and then looked
			# four physics ticks later — about seventy milliseconds — for
			# a round trip that had not happened yet. It passed alone and
			# failed against a busier world, which is the shape of a
			# timing bug in the test rather than in the game.
			if view.vehicles.size() > _had:
				_report(true, "a car can be put down (%d → %d)"
					% [_had, view.vehicles.size()])
				_stand_on(me, view, Vector3(0.9, 0.0, 1.8))
				_step()
				return
			_waited += delta
			if _waited > 4.0:
				_report(false, "a car can be put down (%d → %d after %.1fs)"
					% [_had, view.vehicles.size(), _waited])
				_finish()
		9:
			# DRIVING IT YOURSELF, which every case above leaves out.
			#
			# The turn tests before this move the boat by writing its yaw
			# and then look at the rider — a PASSENGER's path. Steering it
			# is a different route through Player._ride: the helm runs
			# `drive_mine` in the middle of the carry, so the pose the
			# rider is projected out of is the one the driver just changed.
			# A boat that carried passengers perfectly could still slide
			# its own driver about the deck, and nothing here would know.
			#
			# So: hold the stick over, let the real code drive, and measure
			# the driver's own spot in the boat's frame at both ends.
			if _ticks == 1:
				var v0: Dictionary = view.at(_vid)
				_spot = VehicleGeom.to_local(Vector3(v0.pos), float(v0.yaw),
					me.position)
				me.input = _helm_hard
				return
			if _ticks < TURN_FRAMES:
				return
			me.input = _quiet
			var vd: Dictionary = view.at(_vid)
			var now_spot := VehicleGeom.to_local(Vector3(vd.pos),
				float(vd.yaw), me.position)
			var slid := Vector2(now_spot.x - _spot.x,
				now_spot.z - _spot.z).length()
			_report(slid < 0.35,
				"driving it yourself leaves you on the same spot "
				+ "(slid %.2f blocks: %.2f,%.2f -> %.2f,%.2f over %d frames)"
				% [slid, _spot.x, _spot.z, now_spot.x, now_spot.z, TURN_FRAMES])
			_finish()

func _step() -> void:
	_phase += 1
	_ticks = 0

## WHICH WAY THE RIDER IS POINTING, IN THE BOAT'S OWN FRAME.
##
## The heading turned into the boat's frame and read as an angle, so it can
## be compared before and after a turn. A rider who swung round with the
## deck reads the same number at both ends; one the deck rotated underneath
## reads a number that has moved by the whole turn.
func _facing_in_boat(me: Player, v: Dictionary) -> float:
	var local := VehicleGeom.to_local(Vector3.ZERO, float(v.yaw), me.heading)
	return atan2(local.x, local.z)

## Put the player on a spot of the deck, given in the boat's own frame.
func _stand_on(me: Player, view: VehicleView, spot: Vector3) -> void:
	var v: Dictionary = view.at(_vid)
	me.velocity = Vector3.ZERO
	me.fly_mode = false
	var local := spot + Vector3(0.0,
		VehicleGeom.deck_height(int(v.kind)) + 0.05, 0.0)
	me.position = VehicleGeom.to_world(Vector3(v.pos), float(v.yaw), local)

func _finish() -> void:
	print("BOAT: %s" % ("all checks passed" if _failures == 0
		else "%d checks FAILED" % _failures))
	set_process(false)
	get_tree().quit(1 if _failures > 0 else 0)

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

var _t := 0.0
var _phase := 0
var _ticks := 0
var _vid := ""
var _from := Vector3.ZERO
var _failures := 0
var _quiet: InputSlot = null

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
	me.input = _quiet
	_ticks += 1
	match _phase:
		0:
			if view.vehicles.is_empty():
				if _t > START_AFTER + 20.0:
					_report(false, "no vehicles ever arrived from the server")
					_finish()
				return
			_vid = str(view.vehicles.keys()[0])
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
			_finish()

func _step() -> void:
	_phase += 1
	_ticks = 0

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

class_name VehicleDirector
extends Node
## THE BOATS AND CARS, ON THE SERVER.
##
## Which ones exist, where they were last heard to be, and who is at the
## helm. It does not simulate them: the driver's own machine does that and
## says where it got to, the same arrangement every player's body already
## runs on. What this owns is the part that cannot be left to one client —
## the list, the ids, and the rule that a boat has one driver.
##
## The shape and the maths are in VehicleGeom, which has no world in it and
## is tested.

var world: WorldNode = null

## id -> {kind:int, pos:Vector3, yaw:float, driver:String}
var vehicles: Dictionary = {}

## Enough for a fleet and few enough that a room full of children cannot
## fill a bay with them until nothing else can be seen.
const MAX_VEHICLES := 24

var _next := 1

func spawn(kind: int, at_pos: Vector3) -> String:
	if vehicles.size() >= MAX_VEHICLES:
		# The oldest goes. Refusing outright reads as the button being
		# broken; a fleet that quietly recycles reads as a fleet.
		var oldest: String = vehicles.keys()[0]
		vehicles.erase(oldest)
		world.cl_vehicle_gone.rpc(oldest)
	var vid := "v%d" % _next
	_next += 1
	vehicles[vid] = {"kind": kind, "pos": at_pos, "yaw": 0.0, "driver": ""}
	world.cl_vehicle_new.rpc(vid, kind, at_pos, 0.0, "")
	return vid

## Take the helm, if it is free. One driver, and the first aboard gets it —
## no seat to find and nothing to press, because a five-year-old standing
## on a boat expects the boat to go.
func board(vid: String, id: String) -> void:
	if not vehicles.has(vid):
		return
	var v: Dictionary = vehicles[vid]
	if str(v.driver) == id:
		return
	if str(v.driver) != "" and _still_aboard(vid, str(v.driver)):
		return
	v.driver = id
	world.cl_vehicle_helm.rpc(vid, id)

func leave(vid: String, id: String) -> void:
	if not vehicles.has(vid):
		return
	var v: Dictionary = vehicles[vid]
	if str(v.driver) != id:
		return
	v.driver = ""
	world.cl_vehicle_helm.rpc(vid, "")

## Where the driver says it is. Believed, because the driver is believed
## about their own position too — but not blindly: a jump no boat could
## have made in the time is dropped, which is the cheap half of not
## letting one machine teleport an object everybody else is standing on.
func moved(vid: String, id: String, pos: Vector3, yaw: float) -> void:
	if not vehicles.has(vid):
		return
	var v: Dictionary = vehicles[vid]
	if str(v.driver) != id:
		return
	if Vector3(v.pos).distance_to(pos) > MAX_JUMP:
		return
	v.pos = pos
	v.yaw = yaw
	world.cl_vehicle_at.rpc(vid, pos, yaw)

## The furthest a vehicle may move in one report. Reports come about
## fifteen times a second and nothing here does more than eleven blocks a
## second, so a couple of blocks is generous even on a bad connection.
const MAX_JUMP := 6.0

## Is the driver still standing on it? Uses the server's own picture of
## where everybody is, so leaving by any route — walking off, being shot,
## disconnecting — frees the helm without needing to be told.
func _still_aboard(vid: String, id: String) -> bool:
	if not Game.roster.has(id):
		return false
	var v: Dictionary = vehicles[vid]
	var where: Dictionary = world.player_state.get(id, {})
	if where.is_empty():
		return false
	return VehicleGeom.on_deck(int(v.kind), Vector3(v.pos), float(v.yaw),
		Vector3(where.pos))

func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	# A helm nobody is standing at is a helm anybody may take. Checked here
	# rather than when somebody steps off, because most of the ways a
	# driver stops driving are not steps.
	for vid: String in vehicles:
		var v: Dictionary = vehicles[vid]
		if str(v.driver) == "":
			continue
		if not _still_aboard(vid, str(v.driver)):
			v.driver = ""
			world.cl_vehicle_helm.rpc(vid, "")

## Put the thing where it belongs: a boat on the water, a car on the
## ground. The same rule the client uses while driving, applied once when
## one is created, so a boat asked for on dry land goes to the nearest
## water rather than sitting in a field.
func settle(kind: int, at_pos: Vector3) -> Vector3:
	if kind == VehicleGeom.KIND_BOAT:
		var wet := _water_near(at_pos)
		if wet == Vector3.INF:
			return Vector3(at_pos.x, float(WorldGen.SEA_LEVEL) + 0.55, at_pos.z)
		return wet
	var gy := float(world.store.surface_y(floori(at_pos.x), floori(at_pos.z)))
	return Vector3(at_pos.x, gy + 1.0, at_pos.z)

## The nearest open water, searched outwards in rings. Gives up rather
## than searching the whole map: on a dry world there is no answer and
## the caller wants one quickly.
func _water_near(at_pos: Vector3) -> Vector3:
	for radius in [0, 4, 8, 14, 22, 32]:
		for step in 12:
			var angle := TAU * float(step) / 12.0
			var x := at_pos.x + cos(angle) * float(radius)
			var z := at_pos.z + sin(angle) * float(radius)
			if not world.store.inside_world(floori(x), floori(z), 3):
				continue
			var here := world.store.get_block(Vector3i(floori(x),
				WorldGen.SEA_LEVEL, floori(z)))
			if Blocks.is_liquid(here):
				return Vector3(x, float(WorldGen.SEA_LEVEL) + 0.55, z)
	return Vector3.INF

## HOW MANY THE WORLD STARTS WITH.
##
## Water is most of some maps and was, until now, something to be got
## across rather than something to play in — you swim at two thirds of
## walking pace and there is nothing out there. A few boats already
## floating turns the sea into somewhere to go.
##
## They are put out at the world's creation rather than handed out as
## items, because a boat you have to go and find in a menu is a boat
## nobody uses.
const WANT_BOATS := 5
const WANT_CARS := 3

func stock_world() -> void:
	if world == null or world.store == null:
		return
	var half := float(world.store.half_extent())
	var boats := 0
	var cars := 0
	# ONE OF EACH WITHIN SIGHT OF THE SPAWN. A fleet scattered over four
	# hundred blocks of ocean is a fleet nobody ever finds, and a player
	# who has never seen one has no reason to go looking.
	var spawn_at := Vector3(world.spawn_pos)
	var near_water := _water_near(spawn_at)
	if near_water != Vector3.INF:
		spawn(VehicleGeom.KIND_BOAT, near_water)
		boats += 1
	spawn(VehicleGeom.KIND_CAR, settle(VehicleGeom.KIND_CAR,
		spawn_at + Vector3(4.0, 0.0, 4.0)))
	cars += 1
	# A fixed number of attempts, not "until we have enough": a world with
	# no sea in it would otherwise search forever for somewhere to float a
	# boat, at startup, before anybody could join.
	for _try in 260:
		if boats >= WANT_BOATS and cars >= WANT_CARS:
			break
		var x := randf_range(-half + 8.0, half - 8.0)
		var z := randf_range(-half + 8.0, half - 8.0)
		var at_sea := world.store.get_block(Vector3i(floori(x),
			WorldGen.SEA_LEVEL, floori(z)))
		if Blocks.is_liquid(at_sea):
			if boats < WANT_BOATS:
				spawn(VehicleGeom.KIND_BOAT,
					Vector3(x, float(WorldGen.SEA_LEVEL) + 0.55, z))
				boats += 1
			continue
		if cars >= WANT_CARS:
			continue
		var gy := world.store.surface_y(floori(x), floori(z))
		# Cars go where the going is good — sand and grass, not up a
		# mountain, and not in a hole.
		var ground := world.store.get_block(Vector3i(floori(x), gy, floori(z)))
		if ground != Blocks.SAND and ground != Blocks.GRASS:
			continue
		spawn(VehicleGeom.KIND_CAR, Vector3(x, float(gy) + 1.0, z))
		cars += 1
	print("Vehicles: %d boats, %d cars" % [boats, cars])

## Everything, for a client that has just arrived.
func payload() -> Array:
	var out: Array = []
	for vid: String in vehicles:
		var v: Dictionary = vehicles[vid]
		out.append({"id": vid, "kind": int(v.kind), "pos": Vector3(v.pos),
			"yaw": float(v.yaw), "driver": str(v.driver)})
	return out

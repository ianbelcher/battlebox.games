class_name VehicleView
extends Node3D
## THE BOATS AND CARS, ON SCREEN AND UNDER YOUR FEET.
##
## Everybody has one of these — it is the client's copy of every vehicle in
## the world, and it is what Player asks when it wants to know whether
## there is a deck below it.
##
## WHO OWNS A MOVING BOAT. The driver does, on their own machine, exactly
## as every player already owns their own body: they steer it, they send
## where it ended up, and everyone else is told. That is not the safest
## possible arrangement and it is the one this game already runs on, so a
## boat behaves like everything else rather than being the one object in
## the world that lags behind the person moving it.
##
## Everyone else's boats are interpolated towards where they were last
## heard of, at the same rate remote players are, so a boat crossing a bay
## does not arrive in steps.
##
## The shape and the maths are in VehicleGeom, which has no world in it and
## is tested. This file is meshes and bookkeeping.

var world: WorldNode = null

## id -> {kind, pos, yaw, speed, driver, node, target_pos, target_yaw}
var vehicles: Dictionary = {}

const LERP_RATE := 12.0

func _process(delta: float) -> void:
	for vid: String in vehicles:
		var v: Dictionary = vehicles[vid]
		var node: Node3D = v.get("node")
		if node == null:
			continue
		# The one being driven from this machine is already where it
		# should be — it was moved by the hand on the stick. Everything
		# else is chasing a position that arrives fifteen times a second.
		if not bool(v.get("mine", false)):
			v.pos = Vector3(v.pos).lerp(Vector3(v.get("target_pos", v.pos)),
				minf(1.0, delta * LERP_RATE))
			v.yaw = lerp_angle(float(v.yaw),
				float(v.get("target_yaw", v.yaw)), minf(1.0, delta * LERP_RATE))
		node.position = v.pos
		node.rotation.y = v.yaw

## Replace the lot — sent to a client as it joins.
func set_all(payload: Array) -> void:
	for vid: String in vehicles.keys():
		_drop(vid)
	for entry_v: Variant in payload:
		var entry: Dictionary = entry_v
		add_one(str(entry.get("id", "")), int(entry.get("kind", 0)),
			Vector3(entry.get("pos", Vector3.ZERO)), float(entry.get("yaw", 0.0)),
			str(entry.get("driver", "")))

func add_one(vid: String, kind: int, pos: Vector3, yaw: float,
		driver: String) -> void:
	if vid.is_empty() or vehicles.has(vid):
		return
	var node := _build(kind)
	add_child(node)
	node.position = pos
	node.rotation.y = yaw
	vehicles[vid] = {"kind": kind, "pos": pos, "yaw": yaw, "speed": 0.0,
		"driver": driver, "node": node, "target_pos": pos, "target_yaw": yaw,
		"mine": false}

func remove_one(vid: String) -> void:
	_drop(vid)

func _drop(vid: String) -> void:
	if not vehicles.has(vid):
		return
	var node: Node3D = vehicles[vid].get("node")
	if node != null and is_instance_valid(node):
		node.queue_free()
	vehicles.erase(vid)

## Somebody else's boat moved.
func heard_at(vid: String, pos: Vector3, yaw: float) -> void:
	if not vehicles.has(vid):
		return
	var v: Dictionary = vehicles[vid]
	if bool(v.get("mine", false)):
		return          # we are the ones driving it; our own copy is ahead
	v.target_pos = pos
	v.target_yaw = yaw

func set_driver(vid: String, driver: String) -> void:
	if not vehicles.has(vid):
		return
	vehicles[vid].driver = driver
	vehicles[vid].mine = driver != "" and Game.local_player_ids().has(driver)
	if not bool(vehicles[vid].mine):
		# Handing the helm over: stop predicting and start following.
		vehicles[vid].target_pos = vehicles[vid].pos
		vehicles[vid].target_yaw = vehicles[vid].yaw

func driver_of(vid: String) -> String:
	return str(vehicles.get(vid, {}).get("driver", ""))

## THE DECK UNDER A PAIR OF FEET, or an empty id.
##
## Player calls this every frame for every local player, so it is a walk
## over a handful of boats and nothing cleverer. There are never many.
func deck_under(feet: Vector3) -> Dictionary:
	for vid: String in vehicles:
		var v: Dictionary = vehicles[vid]
		if VehicleGeom.on_deck(int(v.kind), Vector3(v.pos), float(v.yaw), feet):
			return {"id": vid, "kind": int(v.kind), "pos": Vector3(v.pos),
				"yaw": float(v.yaw),
				"deck_y": VehicleGeom.deck_at(int(v.kind), Vector3(v.pos))}
	return {}

func at(vid: String) -> Dictionary:
	return vehicles.get(vid, {})

## Drive the one this machine is steering. Returns true if it moved.
func drive_mine(vid: String, throttle: float, steer: float,
		delta: float) -> bool:
	if not vehicles.has(vid):
		return false
	var v: Dictionary = vehicles[vid]
	if not bool(v.get("mine", false)):
		return false
	var out := VehicleGeom.drive(int(v.kind), Vector3(v.pos), float(v.yaw),
		float(v.get("speed", 0.0)), throttle, steer, delta)
	var moved: Vector3 = out[0]
	moved = _sit_on_the_world(int(v.kind), Vector3(v.pos), moved)
	v.pos = moved
	v.yaw = out[1]
	v.speed = out[2]
	return true

## A BOAT FLOATS AND A CAR DRIVES OVER THINGS.
##
## The maths in VehicleGeom is flat — it knows about heading and speed and
## nothing about the world — so this is where the world gets a say. A boat
## is held at the waterline; a car rides whatever it is standing on, and
## refuses a step it would have to climb a cliff to make, which is what
## keeps one from driving up the side of a mountain.
func _sit_on_the_world(kind: int, was: Vector3, want: Vector3) -> Vector3:
	if world == null or world.chunks == null:
		return want
	if kind == VehicleGeom.KIND_BOAT:
		var under := world.chunks.get_block(Vector3i(floori(want.x),
			WorldGen.SEA_LEVEL, floori(want.z)))
		if not Blocks.is_liquid(under):
			# Aground. Stay where she was rather than sailing up the beach.
			return was
		return Vector3(want.x, float(WorldGen.SEA_LEVEL) + 0.55, want.z)
	# A car: find the ground near where it already was.
	var ground := _ground_near(want, was.y)
	if ground == INF or absf(ground - was.y) > CAR_MAX_STEP:
		return was
	return Vector3(want.x, ground, want.z)

## The top of whatever is under this point, searched from around the
## vehicle's current height rather than from the sky — a car in a canyon
## should find the canyon floor, not its rim.
const CAR_MAX_STEP := 1.4
func _ground_near(at_pos: Vector3, from_y: float) -> float:
	for dy in range(3, -5, -1):
		var y := floori(from_y) + dy
		var here := world.chunks.get_block(Vector3i(floori(at_pos.x), y,
			floori(at_pos.z)))
		if Blocks.is_solid(here):
			return float(y) + 1.0
	return INF

# ------------------------------------------------------------------
# Looks
# ------------------------------------------------------------------

## A hull and a deck, built out of boxes.
##
## Deliberately plain. Everything else in this world is made of cubes, so
## a smooth, detailed boat would look like it had been imported from a
## different game — and a shape a child can read at a glance ("that is
## the front") matters more here than detail does.
func _build(kind: int) -> Node3D:
	var root := Node3D.new()
	var boat := kind == VehicleGeom.KIND_BOAT
	var length := VehicleGeom.half_length(kind) * 2.0
	var width := VehicleGeom.half_width(kind) * 2.0
	var deck := VehicleGeom.deck_height(kind)

	var hull_col := Color("8a5a34") if boat else Color("c8503c")
	root.add_child(_box(Vector3(width, deck, length),
		Vector3(0, deck * 0.5, 0), hull_col))
	# A rim, so the deck reads as somewhere you stand IN rather than on.
	var rim := Color("a97544") if boat else Color("e0705c")
	for side in [-1.0, 1.0]:
		root.add_child(_box(Vector3(0.22, 0.5, length),
			Vector3(side * (width * 0.5 - 0.11), deck + 0.25, 0), rim))
	# ...and a blunt end and a pointed one, so which way is forwards is
	# obvious without reading anything.
	root.add_child(_box(Vector3(width * 0.55, 0.5, 0.5),
		Vector3(0, deck + 0.25, length * 0.5 - 0.25), rim))
	if boat:
		# A little sail, purely so it reads as a boat from across a bay.
		root.add_child(_box(Vector3(0.18, 2.4, 0.18),
			Vector3(0, deck + 1.2, -0.2), Color("6b4a30")))
		root.add_child(_box(Vector3(0.08, 1.5, 1.4),
			Vector3(0, deck + 1.5, -0.95), Color("f2f2f2")))
	else:
		# ...and a car gets a cab.
		root.add_child(_box(Vector3(width * 0.8, 0.9, length * 0.4),
			Vector3(0, deck + 0.45, -length * 0.18), Color("2f3a4a")))
	return root

func _box(size: Vector3, at_pos: Vector3, tint: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.85
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at_pos
	return node

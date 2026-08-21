class_name MonsterView
extends Node3D
## Client-side Grumps — the cute-spooky wave-attack monsters. The server
## simulates their march; here they glide, bob menacingly, flash when hit and
## pop in a puff when zapped.

var _nodes: Dictionary = {}   # id -> {node, target, phase}

func update_monsters(payload: Array) -> void:
	var seen := {}
	for entry in payload:
		if not (entry is Array) or entry.size() < 2:
			continue
		var id := int(entry[0])
		var pos: Vector3 = entry[1]
		seen[id] = true
		if _nodes.has(id):
			_nodes[id].target = pos
		else:
			var node := _build()
			node.position = pos
			add_child(node)
			_nodes[id] = {"node": node, "target": pos, "phase": randf() * TAU}
	for id: int in _nodes.keys().duplicate():
		if not seen.has(id):
			_pop(id, false)

func hit(id: int, dead: bool) -> void:
	if not _nodes.has(id):
		return
	if dead:
		_pop(id, true)
		return
	var node: Node3D = _nodes[id].node
	var visual: Node3D = node.get_child(0)
	visual.scale = Vector3(1.25, 0.8, 1.25)
	for mesh in visual.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		var mat := instance.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = true
			mat.emission = Color.WHITE
			mat.emission_energy_multiplier = 1.5
			get_tree().create_timer(0.12).timeout.connect(func() -> void:
				if is_instance_valid(mat):
					mat.emission_energy_multiplier = 0.0)

func _pop(id: int, loud: bool) -> void:
	var node: Node3D = _nodes[id].node
	_nodes.erase(id)
	if loud:
		Sfx.play("pop", 0.0)
		var poof := CPUParticles3D.new()
		poof.position = node.position + Vector3(0, 0.5, 0)
		poof.amount = 16
		poof.lifetime = 0.6
		poof.one_shot = true
		poof.explosiveness = 1.0
		poof.spread = 180.0
		poof.initial_velocity_min = 2.0
		poof.initial_velocity_max = 4.0
		poof.gravity = Vector3(0, -4, 0)
		var mesh := SphereMesh.new()
		mesh.radius = 0.09
		mesh.height = 0.18
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("9a6ddb")
		mesh.material = mat
		poof.mesh = mesh
		add_child(poof)
		poof.emitting = true
		get_tree().create_timer(1.2).timeout.connect(func() -> void:
			if is_instance_valid(poof):
				poof.queue_free())
	node.queue_free()

## Nearest Grump to a world position (orb collision checks).
func nearest_to(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_dist := radius
	for id: int in _nodes.keys():
		var node: Node3D = _nodes[id].node
		var dist: float = (node.position + Vector3(0, 0.5, 0)).distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = id
	return best

## Auto-aim: the Grump this player's zap should hit. First person aims along
## the look ray; isometric just takes the nearest one in front-ish range.
func pick_target(player: Player) -> int:
	var best := -1
	var best_score := 1e9
	for id: int in _nodes.keys():
		var node: Node3D = _nodes[id].node
		var to_monster: Vector3 = node.position - player.position
		var dist := to_monster.length()
		if player.fp_mode:
			if dist > 14.0 or dist < 0.5:
				continue
			var angle := player.look_dir().angle_to(to_monster.normalized())
			if angle < 0.35 and dist < best_score:
				best_score = dist
				best = id
		else:
			if dist < 8.0 and dist < best_score:
				best_score = dist
				best = id
	return best

## A quick glowing bolt from the shooter to the target.
func beam_from(from: Vector3, monster_id: int) -> void:
	if not _nodes.has(monster_id):
		return
	var to: Vector3 = _nodes[monster_id].node.position + Vector3(0, 0.5, 0)
	var beam := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := from.distance_to(to)
	mesh.size = Vector3(0.08, 0.08, length)
	beam.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("7de8e0")
	mat.emission_enabled = true
	mat.emission = Color("7de8e0")
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	add_child(beam)
	beam.look_at_from_position(from.lerp(to, 0.5), to, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(beam, "transparency", 1.0, 0.15)
	tween.tween_callback(func() -> void:
		if is_instance_valid(beam):
			beam.queue_free())

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _nodes.values():
		var node: Node3D = entry.node
		var target: Vector3 = entry.target
		node.position = node.position.lerp(target, minf(1.0, delta * 5.0))
		var to_target := target - node.position
		if Vector2(to_target.x, to_target.z).length() > 0.1:
			node.rotation.y = lerp_angle(node.rotation.y,
				atan2(-to_target.x, -to_target.z), minf(1.0, delta * 5.0))
		var visual: Node3D = node.get_child(0)
		var phase: float = entry.phase
		# Bouncy little menaces: springy hops with squash and stretch.
		var hop := absf(sin(t * 6.5 + phase))
		visual.position.y = hop * 0.3
		var squash := 1.0 + (hop - 0.5) * 0.25
		visual.scale = visual.scale.lerp(Vector3(2.0 - squash, squash, 2.0 - squash), minf(1.0, delta * 8.0))
		if randf() < delta * 0.06:
			Sfx.play("ribbit", -10.0, 0.45)

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat

## A grumpy purple blob: hunched body, angry brows, stub feet, little fangs.
func _build() -> Node3D:
	var root := Node3D.new()
	var visual := Node3D.new()
	root.add_child(visual)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.45
	body_mesh.height = 0.8
	body.mesh = body_mesh
	body.position = Vector3(0, 0.42, 0)
	var body_mat := _mat(Color("6b4a9e"))
	body_mat.emission_enabled = true
	body_mat.emission = Color("8a5fd0")
	body_mat.emission_energy_multiplier = 0.7
	body.material_override = body_mat
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.09
		eye_mesh.height = 0.18
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.17, 0.55, -0.36)
		var eye_mat := _mat(Color("ffd166"))
		eye_mat.emission_enabled = true
		eye_mat.emission = Color("ffd166")
		eye_mat.emission_energy_multiplier = 2.6
		eye.material_override = eye_mat
		visual.add_child(eye)
		var brow := MeshInstance3D.new()
		var brow_mesh := BoxMesh.new()
		brow_mesh.size = Vector3(0.2, 0.05, 0.06)
		brow.mesh = brow_mesh
		brow.position = Vector3(side * 0.17, 0.66, -0.38)
		brow.rotation_degrees = Vector3(0, 0, side * -22.0)
		brow.material_override = _mat(Color("3a2a52"))
		visual.add_child(brow)
		var foot := MeshInstance3D.new()
		var foot_mesh := SphereMesh.new()
		foot_mesh.radius = 0.13
		foot_mesh.height = 0.18
		foot.mesh = foot_mesh
		foot.position = Vector3(side * 0.2, 0.08, 0)
		foot.material_override = _mat(Color("55397d"))
		visual.add_child(foot)
		var fang := MeshInstance3D.new()
		var fang_mesh := BoxMesh.new()
		fang_mesh.size = Vector3(0.06, 0.1, 0.04)
		fang.mesh = fang_mesh
		fang.position = Vector3(side * 0.1, 0.3, -0.4)
		fang.material_override = _mat(Color.WHITE)
		visual.add_child(fang)
	return root

class_name ChunkView
extends Node3D
## Client-side chunk manager: keeps the blocks around the local players
## resident, meshes them (a few per frame so streaming never hitches), spawns
## real OmniLights for lanterns/campfires, and answers collision queries for
## the hand-rolled player physics.

## Chunks kept meshed around each local player; the split screen raises this
## when someone zooms far out so the horizon fills in.
var view_radius := 5
## During matches everything stays resident (prefetched in the lobby).
var match_mode := false
const MAX_INFLIGHT_MESHES := 3
var light_cap := 10
const REQUEST_BATCH := 40
const REQUEST_RETRY_SECONDS := 6.0

var world: Node = null           # set by world.gd; used to send chunk requests

var _data: Dictionary = {}       # Vector2i -> PackedByteArray
var _holders: Dictionary = {}    # Vector2i -> Node3D
var _pending: Dictionary = {}    # Vector2i -> request time (msec)
var _mesh_queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _flickers: Array = []        # [{light, base}]
var _materials: Dictionary = {}
var _focus_chunks: Array[Vector2i] = []
var _teleporters: Dictionary = {}   # Vector2i chunk -> Array[Vector3] world positions

signal first_chunks_ready

var _announced_ready := false

## Meshing runs on a dedicated worker thread: block edits and streaming
## never block the render thread. Jobs carry SNAPSHOTS of the chunk bytes
## (PackedByteArray.duplicate) so the worker never races live edits; the
## main thread only uploads finished arrays (cheap).
var _mesh_threads: Array[Thread] = []
var _mesh_mutex := Mutex.new()
var _mesh_sem := Semaphore.new()
var _mesh_jobs: Array = []
var _mesh_jobs_urgent: Array = []
var _mesh_results: Array = []
var _mesh_exit := false
var _mesh_gen: Dictionary = {}      # cpos -> generation stamp
var _inflight: Dictionary = {}      # cpos -> submit time msec

## Chunks this client has actually received and kept.
func loaded_count() -> int:
	return _data.size()

func _exit_tree() -> void:
	_mesh_exit = true
	for i in _mesh_threads.size():
		_mesh_sem.post()
	for worker: Thread in _mesh_threads:
		worker.wait_to_finish()
	_mesh_threads.clear()

func _mesh_worker() -> void:
	while true:
		_mesh_sem.wait()
		if _mesh_exit:
			return
		_mesh_mutex.lock()
		# Player edits jump every streaming job on every worker.
		var job: Dictionary = {}
		if not _mesh_jobs_urgent.is_empty():
			job = _mesh_jobs_urgent.pop_front()
		elif not _mesh_jobs.is_empty():
			job = _mesh_jobs.pop_front()
		_mesh_mutex.unlock()
		if job.is_empty():
			continue
		var t0 := Time.get_ticks_msec()
		var surfaces: Dictionary = Mesher.new().build(
			job.data, job.neighbors, job.cpos.x, job.cpos.y)
		var build_ms := Time.get_ticks_msec() - t0
		if build_ms > 500:
			push_warning("Slow mesh build: %s took %d ms" % [job.cpos, build_ms])
		_mesh_mutex.lock()
		_mesh_results.append({"cpos": job.cpos, "surfaces": surfaces, "gen": job.gen})
		_mesh_mutex.unlock()

func _ready() -> void:
	for i in 3:
		var worker := Thread.new()
		worker.start(_mesh_worker)
		_mesh_threads.append(worker)
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain.gdshader")
	var plants := ShaderMaterial.new()
	plants.shader = load("res://shaders/plants.gdshader")
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	_materials = {"opaque": terrain, "plants": plants, "trans": water}

func set_water_shine(on: bool) -> void:
	(_materials["trans"] as ShaderMaterial).set_shader_parameter("shine", 1.0 if on else 0.0)

## Queue every resident chunk for a rebuild (AO toggle etc.); the
## time-budgeted mesher spreads the cost over frames.
func remesh_all() -> void:
	for cpos: Vector2i in _data.keys():
		_queue_mesh(cpos)

func has_chunk(cpos: Vector2i) -> bool:
	return _data.has(cpos)

## The world tells us where the local players (or the spectator) are looking.
func set_focus(positions: Array) -> void:
	_focus_chunks.clear()
	for pos: Vector3 in positions:
		var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
		if not _focus_chunks.has(cpos):
			_focus_chunks.append(cpos)
	_refresh_interest()

func _refresh_interest() -> void:
	if _focus_chunks.is_empty() or world == null:
		return
	# Wanted set: circle around each focus.
	var wanted: Dictionary = {}
	for focus in _focus_chunks:
		for dz in range(-view_radius, view_radius + 1):
			for dx in range(-view_radius, view_radius + 1):
				if dx * dx + dz * dz <= view_radius * view_radius + 2:
					wanted[focus + Vector2i(dx, dz)] = true
	# Request whatever is missing, nearest first.
	var missing: Array[Vector2i] = []
	var now := Time.get_ticks_msec()
	for cpos: Vector2i in wanted.keys():
		if _data.has(cpos):
			continue
		if _pending.has(cpos) and now - _pending[cpos] < REQUEST_RETRY_SECONDS * 1000.0:
			continue
		missing.append(cpos)
	if not missing.is_empty():
		missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _dist_to_focus(a) < _dist_to_focus(b))
		var batch: Array = []
		for cpos in missing:
			batch.append(cpos)
			_pending[cpos] = now
			if batch.size() >= REQUEST_BATCH:
				break
		world.request_chunks(batch)
	# Nothing unloads anymore — the whole map is only a few MB, so chunks
	# stay resident forever and moving never re-pulls from the server.
	# Far chunks simply hide, which is what draw distance means.
	var show_r := view_radius
	var hide_r := view_radius + 1   # tight: draw distance means draw distance
	for cpos: Vector2i in _holders.keys():
		var holder: Node3D = _holders[cpos]
		var best := 1e18
		for focus in _focus_chunks:
			var d := cpos - focus
			best = minf(best, float(d.x * d.x + d.y * d.y))
		if holder.visible and best > hide_r * hide_r:
			holder.visible = false
		elif not holder.visible and best <= show_r * show_r:
			holder.visible = true

func _dist_to_focus(cpos: Vector2i) -> float:
	var best := 1e9
	for focus in _focus_chunks:
		best = minf(best, Vector2(cpos - focus).length_squared())
	return best

func receive_chunk(cx: int, cz: int, blob: PackedByteArray) -> void:
	var cpos := Vector2i(cx, cz)
	_pending.erase(cpos)
	var raw := blob.decompress(ChunkStore.RAW_CHUNK_BYTES, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != ChunkStore.RAW_CHUNK_BYTES:
		push_error("Bad chunk payload for %s" % cpos)
		return
	_data[cpos] = raw
	_queue_mesh(cpos)
	# Neighbors were meshed against air where this chunk borders them.
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _data.has(cpos + off):
			_queue_mesh(cpos + off)

## A local player's own edit: apply and remesh the chunk RIGHT NOW so
## breaking/placing feels instant, regardless of how busy the streaming
## mesh queue is. Border chunks still go through the urgent async path.
func apply_edit_now(pos: Vector3i, block: int) -> void:
	if apply_edit(pos, block) < 0:
		return
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	_submit_urgent(cpos)

## Push a chunk straight to the workers' priority queue, bypassing the
## streaming backlog entirely.
func _submit_urgent(cpos: Vector2i) -> void:
	if not _data.has(cpos):
		return
	_mesh_queue.erase(cpos)
	_queued.erase(cpos)
	var nb := {}
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: PackedByteArray = _data.get(cpos + off, PackedByteArray())
		if not n.is_empty():
			nb[off] = n.duplicate()
	var gen: int = int(_mesh_gen.get(cpos, 0)) + 1
	_mesh_gen[cpos] = gen
	_inflight[cpos] = Time.get_ticks_msec()
	_mesh_mutex.lock()
	_mesh_jobs_urgent.append({"cpos": cpos, "data": _data[cpos].duplicate(),
		"neighbors": nb, "gen": gen})
	_mesh_mutex.unlock()
	_mesh_sem.post()

## Applies a replicated edit. Returns the previous block id (or -1 if the
## chunk isn't resident here).
func apply_edit(pos: Vector3i, block: int) -> int:
	if pos.y < 0 or pos.y >= WorldGen.CHUNK_H:
		return -1
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if not _data.has(cpos):
		return -1
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	var data: PackedByteArray = _data[cpos]
	var index := WorldGen.idx(lx, pos.y, lz)
	var old := int(data[index])
	data[index] = block
	_data[cpos] = data
	_queue_mesh(cpos, true)
	# Border edits change neighbor face culling and AO.
	if lx == 0:
		_queue_mesh(cpos + Vector2i(-1, 0), true)
	elif lx == 15:
		_queue_mesh(cpos + Vector2i(1, 0), true)
	if lz == 0:
		_queue_mesh(cpos + Vector2i(0, -1), true)
	elif lz == 15:
		_queue_mesh(cpos + Vector2i(0, 1), true)
	return old

func get_block(pos: Vector3i) -> int:
	if pos.y < 0:
		return Blocks.BEDROCK   # nothing below the world: treat as floor
	if pos.y >= WorldGen.CHUNK_H:
		return Blocks.AIR
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var data: PackedByteArray = _data.get(cpos, PackedByteArray())
	if data.is_empty():
		return Blocks.STONE   # unloaded chunks are solid so nobody falls out
	return data[WorldGen.idx(posmod(pos.x, 16), pos.y, posmod(pos.z, 16))]

## Ground height (top of the highest standable block) at a world column.
func ground_height(wx: int, wz: int) -> int:
	for y in range(WorldGen.CHUNK_H - 1, -1, -1):
		if Blocks.is_solid(get_block(Vector3i(wx, y, wz))):
			return y + 1
	return WorldGen.SEA_LEVEL

func _queue_mesh(cpos: Vector2i, urgent := false) -> void:
	if not _data.has(cpos):
		return
	if _queued.has(cpos):
		# An edit can promote an already-queued chunk to the front.
		if urgent:
			_mesh_queue.erase(cpos)
			_mesh_queue.push_front(cpos)
		return
	_queued[cpos] = true
	if urgent:
		_mesh_queue.push_front(cpos)
	else:
		_mesh_queue.append(cpos)

func _process(_delta: float) -> void:
	# Watchdog: restart any worker that dies, loudly.
	for i in _mesh_threads.size():
		if not _mesh_threads[i].is_alive():
			push_warning("Mesh worker %d not alive — restarting it" % i)
			_mesh_threads[i].wait_to_finish()
			_mesh_exit = false
			_mesh_threads[i] = Thread.new()
			_mesh_threads[i].start(_mesh_worker)
	# Feed the mesh worker (snapshots only — never live arrays)...
	_mesh_mutex.lock()
	var backlog: int = _mesh_jobs.size()
	_mesh_mutex.unlock()
	while backlog < 4 and not _mesh_queue.is_empty():
		# Nearest chunk to a player first — the world grows outward from
		# each player instead of sweeping across the map row by row.
		var best_i := 0
		var best_d := 1e18
		for qi in _mesh_queue.size():
			var qd := _dist_to_focus(_mesh_queue[qi])
			if qd < best_d:
				best_d = qd
				best_i = qi
		var cpos: Vector2i = _mesh_queue[best_i]
		_mesh_queue.remove_at(best_i)
		_queued.erase(cpos)
		if not _data.has(cpos):
			continue
		var neighbors := {}
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: PackedByteArray = _data.get(cpos + off, PackedByteArray())
			if not n.is_empty():
				neighbors[off] = n.duplicate()
		var gen: int = int(_mesh_gen.get(cpos, 0)) + 1
		_mesh_gen[cpos] = gen
		_inflight[cpos] = Time.get_ticks_msec()
		_mesh_mutex.lock()
		_mesh_jobs.append({"cpos": cpos, "data": _data[cpos].duplicate(),
			"neighbors": neighbors, "gen": gen})
		_mesh_mutex.unlock()
		_mesh_sem.post()
		backlog += 1
	# ...and upload whatever it finished — at most a few per frame.
	# Mesh creation happens on the MAIN thread; when a join streams in
	# hundreds of chunks, uploading every finished result in one frame
	# froze the game solid for seconds.
	_mesh_mutex.lock()
	var done: Array = []
	var budget := 3
	while not _mesh_results.is_empty() and budget > 0:
		done.append(_mesh_results.pop_front())
		budget -= 1
	_mesh_mutex.unlock()
	for result: Dictionary in done:
		var rpos: Vector2i = result.cpos
		if not _data.has(rpos) or int(result.get("gen", 0)) != int(_mesh_gen.get(rpos, 0)):
			continue  # superseded by a newer edit or a sync fallback
		_inflight.erase(rpos)
		_topmaps[rpos] = result.surfaces.get("topmap", PackedByteArray())
		_apply_surfaces(rpos, result.surfaces)
	# Stall fallback: if the worker hasn't returned a chunk within 4s,
	# mesh it synchronously so the world never shows stale blocks — but
	# AT MOST ONE per frame. Sync-meshing every overdue chunk at once
	# fed a death spiral (main-thread hitches → more stalls → freeze).
	var now_ms := Time.get_ticks_msec()
	var fallback_done := false
	for spos: Vector2i in _inflight.keys().duplicate():
		if fallback_done or now_ms - int(_inflight[spos]) < 4000:
			continue
		fallback_done = true
		_inflight.erase(spos)
		if not _data.has(spos):
			continue
		push_warning("Mesh worker stalled on %s — meshing synchronously" % spos)
		_mesh_gen[spos] = int(_mesh_gen.get(spos, 0)) + 1
		var nb := {}
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: PackedByteArray = _data.get(spos + off, PackedByteArray())
			if not n.is_empty():
				nb[off] = n
		var sync_surfaces := Mesher.new().build(_data[spos], nb, spos.x, spos.y)
		_topmaps[spos] = sync_surfaces.get("topmap", PackedByteArray())
		_apply_surfaces(spos, sync_surfaces)
	if not _announced_ready and _mesh_queue.is_empty() and done.is_empty() \
			and _data.size() > 8:
		_announced_ready = true
		first_chunks_ready.emit()
	# Campfire/lantern flicker.
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _flickers:
		var light: OmniLight3D = entry.light
		if is_instance_valid(light):
			var base: float = entry.base
			var phase: float = entry.phase
			light.light_energy = base * (0.86 + 0.22 * sin(t * 11.0 + phase) + 0.1 * sin(t * 27.0 + phase * 2.0))

func _apply_surfaces(cpos: Vector2i, surfaces: Dictionary) -> void:
	var warps: Array = []
	for local: Vector3i in surfaces.get("teleporters", []):
		warps.append(Vector3(cpos.x * 16 + local.x, local.y, cpos.y * 16 + local.z))
	if warps.is_empty():
		_teleporters.erase(cpos)
	else:
		_teleporters[cpos] = warps

	var holder: Node3D = _holders.get(cpos)
	if holder != null:
		_forget_flickers(holder)
		holder.queue_free()
	holder = Node3D.new()
	holder.position = Vector3(cpos.x * 16, 0, cpos.y * 16)
	# Born with the right visibility: chunks beyond the draw distance
	# used to pop in visible until the next interest pass.
	holder.visible = _dist_to_focus(cpos) <= float((view_radius + 1) * (view_radius + 1))
	add_child(holder)
	_holders[cpos] = holder

	for key in ["opaque", "plants", "trans"]:
		if not surfaces.has(key):
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[key])
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _materials[key]
		if key != "opaque":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key == "trans":
			instance.transparency = 0.0
		holder.add_child(instance)

	_add_foliage(holder, cpos)

	var lights: Array = surfaces.get("lights", [])
	var count := 0
	for spec: Dictionary in lights:
		if count >= light_cap:
			break
		count += 1
		var light := OmniLight3D.new()
		light.position = spec.pos
		light.light_color = spec.color
		light.light_energy = spec.energy
		light.omni_range = 7.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		holder.add_child(light)
		if spec.flicker:
			_flickers.append({"light": light, "base": spec.energy,
				"phase": float(spec.pos.x) * 1.7 + float(spec.pos.z) * 0.9})
			holder.add_child(_campfire_particles(spec.pos))

func _campfire_particles(pos: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.position = pos - Vector3(0, 0.35, 0)
	particles.amount = 14
	particles.lifetime = 1.1
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, 0.6, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.6, 0.2, 0.8)
	particles.process_material = mat
	var draw := QuadMesh.new()
	draw.size = Vector2(0.16, 0.16)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.45, 0.1)
	draw_mat.emission_energy_multiplier = 2.0
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.material = draw_mat
	particles.draw_pass_1 = draw
	return particles

func _forget_flickers(holder: Node3D) -> void:
	_flickers = _flickers.filter(func(entry: Dictionary) -> bool:
		var light: OmniLight3D = entry.light
		return is_instance_valid(light) and not holder.is_ancestor_of(light))

## Nearest OTHER warp stone (block position) to stand-on position `from`.
func nearest_teleporter(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_dist := 1e9
	for warps: Array in _teleporters.values():
		for pos: Vector3 in warps:
			var dist := from.distance_to(pos)
			if dist > 1.5 and dist < best_dist:
				best_dist = dist
				best = pos
	return best

## Ask for every chunk in a radius right now (match-lobby prefetch).
func prefetch(radius: int) -> void:
	var wanted: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cpos := Vector2i(dx, dz)
			if dx * dx + dz * dz <= radius * radius + 2 and not _data.has(cpos):
				wanted.append(cpos)
				_pending[cpos] = Time.get_ticks_msec()
	for i in range(0, wanted.size(), 38):
		world.request_chunks(wanted.slice(i, i + 38))

## Drop everything (map reset) so the interest loop re-streams the world.
func reset() -> void:
	for cpos: Vector2i in _data.keys().duplicate():
		_drop_chunk(cpos)
	_pending.clear()
	_mesh_queue.clear()
	_queued.clear()

## Top visible block for the minimap (uses cached per-chunk top maps).
var _topmaps: Dictionary = {}
func top_block(wx: int, wz: int) -> int:
	var cpos := Vector2i(floori(wx / 16.0), floori(wz / 16.0))
	var topmap: PackedByteArray = _topmaps.get(cpos, PackedByteArray())
	if topmap.is_empty():
		return -1
	return topmap[posmod(wz, 16) * 16 + posmod(wx, 16)]

func _drop_chunk(cpos: Vector2i) -> void:
	_topmaps.erase(cpos)
	_data.erase(cpos)
	_pending.erase(cpos)
	_teleporters.erase(cpos)
	var holder: Node3D = _holders.get(cpos)
	if holder != null:
		_forget_flickers(holder)
		holder.queue_free()
		_holders.erase(cpos)


# ------------------------------------------------------------------
# Ground foliage: Kenney Nature Kit models via one MultiMesh per plant
# type per chunk — grass, ferns, flowers and mushrooms become real
# little models while staying ordinary diggable blocks underneath.
# ------------------------------------------------------------------
const FOLIAGE_MODELS := {Blocks.TALL_GRASS: "grass_large",
	Blocks.FERN: "grass_leafs", Blocks.FLOWER_RED: "flower_redA",
	Blocks.FLOWER_YELLOW: "flower_yellowA", Blocks.MUSHROOM: "mushroom_red",
	Blocks.FLOWER_PINK: "flower_purpleA", Blocks.DAISY: "flower_yellowB",
	Blocks.BLUEBELL: "flower_purpleB", Blocks.CATTAIL: "grass_leafsLarge",
	Blocks.WHEAT_PLANT: "crops_wheatStageB", Blocks.DEAD_BUSH: "plant_bushSmall",
	Blocks.BERRY_BUSH: "plant_bushDetailed", Blocks.BAMBOO: "crops_bambooStageB"}
const FOLIAGE_SCALES := {Blocks.TALL_GRASS: 1.6, Blocks.FERN: 1.5,
	Blocks.FLOWER_RED: 1.2, Blocks.FLOWER_YELLOW: 1.2, Blocks.MUSHROOM: 1.1,
	Blocks.FLOWER_PINK: 1.2, Blocks.DAISY: 1.2, Blocks.BLUEBELL: 1.2,
	Blocks.CATTAIL: 1.4, Blocks.WHEAT_PLANT: 1.3, Blocks.DEAD_BUSH: 1.1,
	Blocks.BERRY_BUSH: 1.3, Blocks.BAMBOO: 1.5}
var _foliage_meshes: Dictionary = {}

func _foliage_mesh(model: String) -> Mesh:
	if _foliage_meshes.has(model):
		return _foliage_meshes[model]
	var mesh: Mesh = null
	var scene: PackedScene = load("res://assets/models/nature/%s.glb" % model)
	if scene != null:
		var inst := scene.instantiate()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			mesh = (node as MeshInstance3D).mesh
			break
		inst.free()
	_foliage_meshes[model] = mesh
	return mesh

func _add_foliage(holder: Node3D, cpos: Vector2i) -> void:
	# Read the CLIENT's own chunk copy (_data, fed by the server) — the
	# world.store only holds real data on the server side.
	var data: PackedByteArray = _data.get(cpos, PackedByteArray())
	if data.is_empty():
		return
	var buckets: Dictionary = {}
	for i in data.size():
		var block := data[i]
		if not FOLIAGE_MODELS.has(block):
			continue
		var x := i % 16
		var z := (i / 16) % 16
		var y := i / 256
		var yaw := WorldGen.hash01(cpos.x * 16 + x, cpos.y * 16 + z, y) * TAU
		var t := Transform3D(Basis(Vector3.UP, yaw)
			.scaled(Vector3.ONE * float(FOLIAGE_SCALES.get(block, 1.2))),
			Vector3(x + 0.5, y, z + 0.5))
		if not buckets.has(block):
			buckets[block] = []
		(buckets[block] as Array).append(t)
	for block: int in buckets:
		var mesh := _foliage_mesh(str(FOLIAGE_MODELS[block]))
		if mesh == null:
			continue
		var transforms: Array = buckets[block]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for j in transforms.size():
			mm.set_instance_transform(j, transforms[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)

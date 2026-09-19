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
## HOW MANY LAMPS ARE LIT AT ONCE, ACROSS THE WHOLE WORLD — not per chunk.
## The renderer has a real hard limit on lights touching one surface
## (rendering/limits/opengl/max_lights_per_object, 32 here), and this used
## to be enforced per chunk instead: each chunk allowed its own eight (or
## twenty, with the "Lights" video setting on — see main._apply_video),
## taken in mesh-time order, with no say at all in what a NEIGHBOURING
## chunk was allowed. Nothing stopped several busy chunks' quotas from
## summing past the real limit at the border between them, and which
## lamps the renderer then dropped depended on camera angle — a crate's
## light there in one frame, gone the next, several times a second.
##
## Every lamp now exists (still merged by the mesher into fewer, stronger
## ones per chunk) but starts OFF; `_refresh_light_budget` — run on the
## same 0.4s cadence as everything else that reacts to where the players
## are (see World._client_update_focus) — turns on the nearest LIGHT_CAP
## to any local player and nothing else. The choice only moves when a
## player actually walks somewhere; it never depends on which way the
## camera happens to be pointed.
var light_cap := 24:
	set(value):
		light_cap = value
		_refresh_light_budget()
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
## WHERE THIS WORLD'S CEILING IS, or below zero for the outdoor maps that
## have none. Solid blocks at or above it are meshed into their own
## surface and put on RenderLayers.ROOF, which the orbit and map cameras
## decline to draw — see the note there. Set by the world when it learns
## which map it is in.
var roof_y := -1:
	set(value):
		if value == roof_y:
			return
		roof_y = value
		# Everything already on screen was split against the OLD line — or
		# not split at all. A world reset can change which map this is, and
		# a chunk that arrived before the map did would keep its ceiling in
		# the surface the orbit camera draws.
		for cpos: Vector2i in _data.keys():
			_queue_mesh(cpos)
var _focus_chunks: Array[Vector2i] = []
var _focus_positions: Array = []    # Vector3, the raw positions behind _focus_chunks
var _chunk_lamps: Dictionary = {}   # Vector2i -> Array[{light, pos}], pos in world space
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
var _mesh_gen: Dictionary = {}      # cpos -> generation of the latest submitted job
var _applied_gen: Dictionary = {}   # cpos -> generation actually on screen
var _inflight: Dictionary = {}      # cpos -> submit time msec
## When a worker actually PICKED UP each chunk's job, as cpos ->
## [generation, msec], under _mesh_mutex. The stall fallback times from here, not from submission:
## a job still waiting its turn in the queue is not stalled, and on a slow
## machine the queue alone can be longer than the four-second limit —
## which then meshed a chunk synchronously on the main thread, half a
## second of frozen game for work a worker was about to do anyway.
var _mesh_started: Dictionary = {}
## Chunks whose drawn mesh (or lack of one) is older than their blocks.
##
## ONLY CHUNKS NEAR A PLAYER ARE MESHED. The client is sent far more of the
## world than it draws — all of it, in the background, so travel never
## waits on the server — and every chunk it received used to be meshed on
## arrival. A chunk is 200-500 ms of GDScript to mesh on a fast desktop
## (the shaped ground made it dearer again), and well over half of them
## sat hidden past the draw distance: minutes of worker time at the start
## of a game, on machines whose two or four cores are also running the
## game itself. Out of range, a chunk now gets only the cheap summary the
## maps and the warp stones need (_summary_of), stays in here, and is
## meshed properly once somebody comes within MESH_MARGIN chunks of the
## draw distance.
var _mesh_dirty: Dictionary = {}
## How far past the draw distance (in chunks) meshing reaches, so the edge
## is built before anybody can see it.
const MESH_MARGIN := 2
## Set when lamps come or go; the budget is redone once, at the end of the
## frame, however many chunks were uploaded in it.
var _lamps_dirty := false

## Chunks this client has actually received and kept.
func loaded_count() -> int:
	return _data.size()

## How many chunks the current view wants, and how many of those are
## here — so a loading screen can say "38 of 90" rather than spin.
var _wanted_count := 0
var _wanted_here := 0
var _wanted_meshed := 0

func wanted_count() -> int:
	return _wanted_count

func wanted_here() -> int:
	return _wanted_here

## ...and how many of those have been meshed at least once — which is
## what "the world is on screen" actually means. `first_chunks_ready`
## waits for the WHOLE mesh queue to drain, and the queue is refilled by
## the prefetch for the first twenty seconds, so gating arrival on it
## kept the loading screen up long after the ground under the player was
## drawn. This counts only what the view asked for.
func wanted_meshed() -> int:
	return _wanted_meshed

func view_ready() -> bool:
	return _wanted_count > 0 and _wanted_meshed >= _wanted_count

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
		if not job.is_empty() and not job.get("summary", false):
			_mesh_started[job.cpos] = [int(job.gen), Time.get_ticks_msec()]
		_mesh_mutex.unlock()
		if job.is_empty():
			continue
		var t0 := Time.get_ticks_msec()
		var surfaces: Dictionary
		if job.get("summary", false):
			surfaces = _summary_of(job.data)
		else:
			surfaces = Mesher.new().build(job.data, job.neighbors, job.cpos.x,
				job.cpos.y, int(job.get("roof", -1)))
			surfaces["foliage"] = _foliage_of(job.data, job.cpos)
		var build_ms := Time.get_ticks_msec() - t0
		if build_ms > 500:
			push_warning("Slow mesh build: %s took %d ms" % [job.cpos, build_ms])
		_mesh_mutex.lock()
		_mesh_results.append({"cpos": job.cpos, "surfaces": surfaces, "gen": job.gen})
		_mesh_mutex.unlock()

## The eight chunks around one.
const AROUND := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]

func _ready() -> void:
	# One worker per core the game is not already using for its main and
	# render threads, up to three. A fixed three on a dual-core machine
	# puts three GDScript meshers on the same two cores as the frame.
	for i in clampi(OS.get_processor_count() - 2, 1, 3):
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

## The one water material every chunk's water faces share, for anything
## that wants to look like water without being voxels — see KingHillMode's
## rising tide, a single plane rather than a real block anywhere.
func water_material() -> ShaderMaterial:
	return _materials["trans"]

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
	_focus_positions = positions.duplicate()
	for pos: Vector3 in positions:
		var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
		if not _focus_chunks.has(cpos):
			_focus_chunks.append(cpos)
	_refresh_interest()
	_refresh_light_budget()

## NEAREST FIRST. Every lamp exists as a real light the moment its chunk is
## meshed, but only the LIGHT_CAP closest to a local player are ever on —
## see the note on `light_cap`. Cheap to redo from scratch each call: a
## loaded world keeps a few hundred lamps at most, and this only runs on
## the 0.4s focus cadence, not per frame.
func _refresh_light_budget() -> void:
	var lamps: Array[OmniLight3D] = []
	var d2 := PackedFloat32Array()
	for arr: Array in _chunk_lamps.values():
		for entry: Dictionary in arr:
			var light: OmniLight3D = entry.light
			if is_instance_valid(light):
				lamps.append(light)
				d2.append(_nearest_focus_dist2(entry.pos))
	if light_cap <= 0 or _focus_positions.is_empty():
		for light in lamps:
			light.visible = false
		return
	# The distance of the LIGHT_CAP-th nearest lamp, from a sorted copy of
	# the distances — a sort in C++, where a sort_custom over a dictionary
	# per lamp cost ~3 ms, and ran for every chunk with a lamp in it that
	# was uploaded (three a frame while a world streams in).
	var cutoff := INF
	if d2.size() > light_cap:
		var sorted := d2.duplicate()
		sorted.sort()
		cutoff = sorted[light_cap - 1]
	var lit := 0
	for i in lamps.size():
		var on := d2[i] <= cutoff and lit < light_cap
		if on:
			lit += 1
		lamps[i].visible = on

func _nearest_focus_dist2(pos: Vector3) -> float:
	var best := 1e18
	for focus: Vector3 in _focus_positions:
		best = minf(best, focus.distance_squared_to(pos))
	return best

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
	_wanted_count = wanted.size()
	_wanted_here = 0
	_wanted_meshed = 0
	for cpos: Vector2i in wanted.keys():
		if _data.has(cpos):
			_wanted_here += 1
			if _holders.has(cpos):
				_wanted_meshed += 1
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
	# Somebody walked (or zoomed the draw distance) up to chunks that were
	# only summarised: mesh them now.
	for cpos: Vector2i in _mesh_dirty.keys():
		if not _queued.has(cpos) and _in_mesh_range(cpos):
			_queue_mesh(cpos)

func _in_mesh_range(cpos: Vector2i) -> bool:
	var reach := view_radius + MESH_MARGIN
	return _dist_to_focus(cpos) <= float(reach * reach)

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
	for off: Vector2i in AROUND:
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
	# All eight neighbours and the roof line, exactly as the streaming path
	# sends them. This sent four and no roof, so a chunk you had just dug
	# in was rebuilt with its corner ground shaped against air beyond the
	# diagonals and, indoors, its ceiling back in the surface the orbit
	# camera draws — until something else happened to remesh it.
	var nb := {}
	for off: Vector2i in AROUND:
		var n: PackedByteArray = _data.get(cpos + off, PackedByteArray())
		if not n.is_empty():
			nb[off] = n.duplicate()
	var gen: int = int(_mesh_gen.get(cpos, 0)) + 1
	_mesh_gen[cpos] = gen
	_inflight[cpos] = Time.get_ticks_msec()
	_mesh_dirty.erase(cpos)
	_mesh_mutex.lock()
	_mesh_jobs_urgent.append({"cpos": cpos, "data": _data[cpos].duplicate(),
		"neighbors": nb, "gen": gen, "roof": roof_y})
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
	var index := WorldGen.bidx(lx, pos.y, lz)
	var old := data.decode_u16(index)
	data.encode_u16(index, block)
	_data[cpos] = data
	_queue_mesh(cpos, true)
	# Border edits change neighbor face culling, AO and the ground's
	# shape — and a corner edit changes the chunk diagonally beyond it.
	var ex := -1 if lx == 0 else (1 if lx == 15 else 0)
	var ez := -1 if lz == 0 else (1 if lz == 15 else 0)
	if ex != 0:
		_queue_mesh(cpos + Vector2i(ex, 0), true)
	if ez != 0:
		_queue_mesh(cpos + Vector2i(0, ez), true)
	if ex != 0 and ez != 0:
		_queue_mesh(cpos + Vector2i(ex, ez), true)
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
	return data.decode_u16(WorldGen.bidx(posmod(pos.x, 16), pos.y, posmod(pos.z, 16)))

## Ground height (top of the highest standable block) at a world column.
func ground_height(wx: int, wz: int) -> int:
	for y in range(WorldGen.CHUNK_H - 1, -1, -1):
		if Blocks.is_solid(get_block(Vector3i(wx, y, wz))):
			return y + 1
	return WorldGen.SEA_LEVEL

func _queue_mesh(cpos: Vector2i, urgent := false) -> void:
	if not _data.has(cpos):
		return
	_mesh_dirty[cpos] = true
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
		if not _in_mesh_range(cpos):
			# Summary only; it stays dirty until someone comes near.
			var summary_gen: int = int(_mesh_gen.get(cpos, 0)) + 1
			_mesh_gen[cpos] = summary_gen
			_mesh_mutex.lock()
			_mesh_jobs.append({"cpos": cpos, "data": _data[cpos].duplicate(),
				"gen": summary_gen, "summary": true})
			_mesh_mutex.unlock()
			_mesh_sem.post()
			backlog += 1
			continue
		_mesh_dirty.erase(cpos)
		var neighbors := {}
		# All eight, diagonals included: the shape of a corner block reads
		# the block diagonally beyond it.
		for off: Vector2i in AROUND:
			var n: PackedByteArray = _data.get(cpos + off, PackedByteArray())
			if not n.is_empty():
				neighbors[off] = n.duplicate()
		var gen: int = int(_mesh_gen.get(cpos, 0)) + 1
		_mesh_gen[cpos] = gen
		_inflight[cpos] = Time.get_ticks_msec()
		_mesh_mutex.lock()
		_mesh_jobs.append({"cpos": cpos, "data": _data[cpos].duplicate(),
			"neighbors": neighbors, "gen": gen, "roof": roof_y})
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
		var rgen: int = int(result.get("gen", 0))
		# SHOW PROGRESS, DON'T WAIT FOR CALM. This used to require an exact
		# match against the latest submitted gen, so a chunk re-edited
		# before its own mesh came back threw that mesh away rather than
		# show it — and a rapid-fire weapon kept re-editing the chunk it
		# was shooting faster than a build could finish, so nothing
		# appeared until the trigger let up and one build finally won the
		# race. Any result newer than what is already on screen is worth
		# showing now; a fresher one lands right behind it.
		if not _data.has(rpos) or rgen <= int(_applied_gen.get(rpos, -1)):
			continue  # a newer result already showed this chunk
		if result.surfaces.get("summary", false):
			# Nothing drawn, so nothing "on screen" moves on: only what
			# the maps and the warp stones read.
			_topmaps[rpos] = result.surfaces.topmap
			_set_teleporters(rpos, result.surfaces)
			continue
		_applied_gen[rpos] = rgen
		if rgen >= int(_mesh_gen.get(rpos, 0)):
			_inflight.erase(rpos)  # this WAS the latest request
			_mesh_mutex.lock()
			_mesh_started.erase(rpos)
			_mesh_mutex.unlock()
		_topmaps[rpos] = result.surfaces.get("topmap", PackedByteArray())
		_apply_surfaces(rpos, result.surfaces)
	# Stall fallback: if the worker hasn't returned a chunk within 4s,
	# mesh it synchronously so the world never shows stale blocks — but
	# AT MOST ONE per frame. Sync-meshing every overdue chunk at once
	# fed a death spiral (main-thread hitches → more stalls → freeze).
	var now_ms := Time.get_ticks_msec()
	var fallback_done := false
	_mesh_mutex.lock()
	var started: Dictionary = _mesh_started.duplicate()
	_mesh_mutex.unlock()
	for spos: Vector2i in _inflight.keys().duplicate():
		# Only the LATEST job for the chunk counts, and only once a worker
		# has it.
		var picked: Array = started.get(spos, [-1, 0])
		if fallback_done or int(picked[0]) != int(_mesh_gen.get(spos, 0)) \
				or now_ms - int(picked[1]) < 4000:
			continue
		fallback_done = true
		_inflight.erase(spos)
		_mesh_mutex.lock()
		_mesh_started.erase(spos)
		_mesh_mutex.unlock()
		if not _data.has(spos):
			continue
		push_warning("Mesh worker stalled on %s — meshing synchronously" % spos)
		_mesh_gen[spos] = int(_mesh_gen.get(spos, 0)) + 1
		var nb := {}
		for off: Vector2i in AROUND:
			var n: PackedByteArray = _data.get(spos + off, PackedByteArray())
			if not n.is_empty():
				nb[off] = n
		var sync_surfaces := Mesher.new().build(_data[spos], nb, spos.x, spos.y, roof_y)
		sync_surfaces["foliage"] = _foliage_of(_data[spos], spos)
		_applied_gen[spos] = int(_mesh_gen[spos])
		_topmaps[spos] = sync_surfaces.get("topmap", PackedByteArray())
		_apply_surfaces(spos, sync_surfaces)
	if _lamps_dirty:
		_lamps_dirty = false
		_refresh_light_budget()
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

func _set_teleporters(cpos: Vector2i, surfaces: Dictionary) -> void:
	var warps: Array = []
	for local: Vector3i in surfaces.get("teleporters", []):
		warps.append(Vector3(cpos.x * 16 + local.x, local.y, cpos.y * 16 + local.z))
	if warps.is_empty():
		_teleporters.erase(cpos)
	else:
		_teleporters[cpos] = warps

func _apply_surfaces(cpos: Vector2i, surfaces: Dictionary) -> void:
	_set_teleporters(cpos, surfaces)
	var holder: Node3D = _holders.get(cpos)
	if holder != null:
		_forget_flickers(holder)
		holder.queue_free()
	if _chunk_lamps.has(cpos):
		_chunk_lamps.erase(cpos)
		_lamps_dirty = true
	holder = Node3D.new()
	holder.position = Vector3(cpos.x * 16, 0, cpos.y * 16)
	# Born with the right visibility: chunks beyond the draw distance
	# used to pop in visible until the next interest pass.
	holder.visible = _dist_to_focus(cpos) <= float((view_radius + 1) * (view_radius + 1))
	add_child(holder)
	_holders[cpos] = holder

	for key in Mesher.SURFACES:
		if not surfaces.has(key):
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[key])
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		# The roof is the terrain material like everything solid; only the
		# layer it is drawn on differs.
		instance.material_override = _materials["opaque" if key == "roof" else key]
		if key != "opaque":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key == "trans":
			instance.transparency = 0.0
		if key == "roof":
			# Its own layer, so the orbit camera can cut it away and the
			# first-person one cannot. See RenderLayers.ROOF.
			instance.layers = RenderLayers.ROOF
		holder.add_child(instance)

	_add_foliage(holder, surfaces.get("foliage", {}))

	var lights: Array = surfaces.get("lights", [])
	var made: Array = []
	for spec: Dictionary in lights:
		var light := OmniLight3D.new()
		light.position = spec.pos
		light.light_color = spec.color
		light.light_energy = spec.energy * 1.4
		# ELEVEN BLOCKS: enough to light a hall.
		light.omni_range = 11.0
		light.omni_attenuation = 0.9
		light.shadow_enabled = false
		# Off until the budget pass (_refresh_light_budget) turns on
		# whichever lamps are actually nearest a local player.
		light.visible = false
		holder.add_child(light)
		made.append({"light": light, "pos": holder.position + spec.pos})
		if spec.flicker:
			_flickers.append({"light": light, "base": spec.energy,
				"phase": float(spec.pos.x) * 1.7 + float(spec.pos.z) * 0.9})
			holder.add_child(_campfire_particles(spec.pos))
	if not made.is_empty():
		_chunk_lamps[cpos] = made
		_lamps_dirty = true

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
	return topmap.decode_u16((posmod(wz, 16) * 16 + posmod(wx, 16)) << 1)

## One chunk's whole top map (16x16 two-byte block ids, z-major), or
## empty. For the maps, which walk thousands of columns and cannot afford
## top_block's dictionary lookup on every one of them.
func topmap_of(cpos: Vector2i) -> PackedByteArray:
	return _topmaps.get(cpos, PackedByteArray())

func _drop_chunk(cpos: Vector2i) -> void:
	_topmaps.erase(cpos)
	_mesh_dirty.erase(cpos)
	if _chunk_lamps.erase(cpos):
		_lamps_dirty = true
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
## "proc:" names are built by Foliage; the rest are Kenney models,
## recoloured on load (their teal is a placeholder, not a plant colour).
const FOLIAGE_MODELS := {Blocks.TALL_GRASS: "proc:grass",
	Blocks.FERN: "grass_leafs", Blocks.FLOWER_RED: "flower_redA",
	Blocks.FLOWER_YELLOW: "flower_yellowA", Blocks.MUSHROOM: "mushroom_red",
	Blocks.FLOWER_PINK: "flower_purpleA", Blocks.DAISY: "flower_yellowB",
	Blocks.BLUEBELL: "flower_purpleB", Blocks.CATTAIL: "proc:reeds",
	Blocks.WHEAT_PLANT: "crops_wheatStageB", Blocks.DEAD_BUSH: "plant_bushSmall",
	Blocks.BERRY_BUSH: "plant_bushDetailed", Blocks.BAMBOO: "crops_bambooStageB"}
const FOLIAGE_SCALES := {Blocks.TALL_GRASS: 1.0, Blocks.FERN: 1.5,
	Blocks.FLOWER_RED: 1.2, Blocks.FLOWER_YELLOW: 1.2, Blocks.MUSHROOM: 1.1,
	Blocks.FLOWER_PINK: 1.2, Blocks.DAISY: 1.2, Blocks.BLUEBELL: 1.2,
	Blocks.CATTAIL: 1.0, Blocks.WHEAT_PLANT: 1.3, Blocks.DEAD_BUSH: 1.1,
	Blocks.BERRY_BUSH: 1.3, Blocks.BAMBOO: 1.5}
## GRASS IS NOT ONE PLANT. Every grass block was the same model at the
## same size, which is a field of identical stamps and reads as one:
## a plane with tufts on it. Three builds now, dealt by position — the
## ordinary tuft, a thick tussock, a small fine one (see Foliage) — and
## every instance at its own size, so a meadow is grass of different
## heights with the ground showing through, and the blocks underneath
## stop reading as blocks.
const GRASS_VARIANTS := ["proc:grass", "proc:clump", "proc:fine"]
## How much an instance's size wanders from the table above: 0.75 to 1.45
## of it.
const FOLIAGE_SIZE_SPREAD := 0.7
var _foliage_meshes: Dictionary = {}

func _foliage_mesh(model: String) -> Mesh:
	if _foliage_meshes.has(model):
		return _foliage_meshes[model]
	var mesh: Mesh = null
	if model.begins_with("proc:"):
		mesh = Foliage.build(model)
	else:
		var scene: PackedScene = load("res://assets/models/nature/%s.glb" % model)
		if scene != null:
			var inst := scene.instantiate()
			for node in inst.find_children("*", "MeshInstance3D", true, false):
				mesh = (node as MeshInstance3D).mesh
				break
			inst.free()
		Foliage.recolour(mesh)
	_foliage_meshes[model] = mesh
	return mesh

## Where every plant model in a chunk goes: model name -> Array of
## Transform3D. Runs on the MESH WORKERS, beside the mesher — it is a walk
## over every block of the chunk, 3-9 ms of GDScript, and on the main
## thread it was paid again for every chunk uploaded (three a frame while
## streaming) and every edit remesh.
static func _foliage_of(data: PackedByteArray, cpos: Vector2i) -> Dictionary:
	# Bucketed by MODEL rather than by block, because one block can be
	# drawn as any of several models — see GRASS_VARIANTS.
	var buckets: Dictionary = {}
	# ONE BLOCK IS TWO BYTES, so this walks blocks and decodes — it used
	# to index the array raw, which after the widening read every low and
	# high byte as if it were a block id. A floor of Office Carpet (256)
	# has a high byte of 1, which is Grass, so every carpet tile in the
	# building sprouted a tuft at a garbage position.
	for i in WorldGen.CHUNK_BLOCKS:
		var block := data.decode_u16(i * 2)
		if not FOLIAGE_MODELS.has(block):
			continue
		var x := i % 16
		var z := (i / 16) % 16
		var y := i / 256
		var wx := cpos.x * 16 + x
		var wz := cpos.y * 16 + z
		var yaw := WorldGen.hash01(wx, wz, y) * TAU
		var model := str(FOLIAGE_MODELS[block])
		if block == Blocks.TALL_GRASS:
			var pick := WorldGen.hash01(wx, wz, y + 7)
			model = GRASS_VARIANTS[0] if pick < 0.55 else (GRASS_VARIANTS[1] if pick < 0.85
				else GRASS_VARIANTS[2])
		var size := float(FOLIAGE_SCALES.get(block, 1.2)) \
			* (1.0 - FOLIAGE_SIZE_SPREAD * 0.35 + FOLIAGE_SIZE_SPREAD * WorldGen.hash01(wx, wz, y + 11))
		var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size),
			Vector3(x + 0.5, y, z + 0.5))
		if not buckets.has(model):
			buckets[model] = []
		(buckets[model] as Array).append(t)
	return buckets

## What a chunk that is NOT being meshed still has to provide (see
## _mesh_dirty): its top map for the radar and big map, and its warp
## stones for nearest_teleporter(). The same answers Mesher.build gives.
static func _summary_of(data: PackedByteArray) -> Dictionary:
	var topmap := PackedByteArray()
	topmap.resize(256 * 2)
	var teleporters: Array = []
	var slab_bytes := 256 * 2
	for y in WorldGen.CHUNK_H:
		var slab := y * slab_bytes
		# All-air layers (most of the sky) are skipped in C++.
		if data.slice(slab, slab + slab_bytes).count(0) == slab_bytes:
			continue
		for column in 256:
			var block := data.decode_u16(slab + (column << 1))
			if block != Blocks.AIR:
				topmap.encode_u16(column << 1, block)
				if block == Blocks.TELEPORT:
					teleporters.append(Vector3i(column % 16, y, column / 16))
	return {"summary": true, "topmap": topmap, "teleporters": teleporters}

## Plants beyond this (from the camera) are not drawn. A tuft of grass is
## a pixel or two by then and deep in the draw-distance fog, but every
## model in every chunk is its own draw call — over a thousand of them in
## view, hundreds of thousands of blade vertices, for every split-screen
## camera.
const FOLIAGE_VISIBLE_TO := 112.0

## Plant models from _foliage_of's buckets, one MultiMesh per model.
func _add_foliage(holder: Node3D, buckets: Dictionary) -> void:
	for model: String in buckets:
		var mesh := _foliage_mesh(model)
		if mesh == null:
			continue
		var transforms: Array = buckets[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		for j in transforms.size():
			mm.set_instance_transform(j, transforms[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = FOLIAGE_VISIBLE_TO
		mmi.visibility_range_end_margin = 8.0
		holder.add_child(mmi)

class_name SplitScreen
extends Control
## Dynamic 1-4 player split screen. Every cell is a SubViewportContainer whose
## SubViewport shares the root viewport's World3D (the world lives under the
## Game autoload), with its own isometric camera rig and HUD overlay.
##
## 0 players -> one full-screen spectator cell slowly orbiting the spawn with
## a big "press a button to join" prompt. 3 players -> the fourth cell is a
## join hint.

## Camera orbit: fixed pitch, four 90-degree yaw stops (spin to see behind
## things), and stepped zoom. Both tween smoothly toward their snap targets.
const CAM_DISTANCE := 42.4
const CAM_HEIGHT := 37.0
## Default orbit elevation angle — matches the old fixed iso framing.
const DEFAULT_PITCH := 0.718  # atan(37 / 42.4)
## From nearly-on-your-shoulder to a big map-like overview.
const ZOOM_SIZES: Array[float] = [5.0, 7.0, 10.0, 15.0, 22.0, 32.0, 48.0, 70.0, 100.0]
const FP_FOVS: Array[float] = [78.0, 45.0, 20.0, 8.0]
const DEFAULT_ZOOM := 3

var world: Node = null
## While set (msec), never capture the mouse — lets macOS window resizing
## work without the game yanking the cursor back.
var _capture_hold_until := 0

func suppress_capture(ms: int) -> void:
	_capture_hold_until = Time.get_ticks_msec() + ms
var big_map: TextureRect = null
## Set by main.gd while the full-screen world menu is showing.
var world_menu_open := false
var low_fx := false

## Render cheaper: fewer pixels, no MSAA. Applied to current and future cells.
func set_low_fx(low: bool) -> void:
	low_fx = low
	for cell: Dictionary in _cells:
		if cell.viewport != null:
			var viewport: SubViewport = cell.viewport
			viewport.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
			viewport.scaling_3d_scale = 0.7 if low else 1.0
## True while any local player has their menu open — A presses are menu
## clicks then, never join requests.
func any_menu_open() -> bool:
	for cell: Dictionary in _cells:
		if cell.hud != null and cell.hud.is_ui_open():
			return true
	return false

## Shut every player's own menu. Used when the WORLD menu opens, so the
## two are never stacked.
func close_all_menus() -> void:
	for cell: Dictionary in _cells:
		if cell.hud != null and cell.hud.has_method("close_menu"):
			cell.hud.close_menu()

var _cells: Array = []   # [{slot:int(-1=spectator), container, viewport, rig, cam, hud,
                         #   yaw_index, yaw, zoom_index, size, prev_rot, prev_zoom}]
var _orbit_angle := 0.0

func _ready() -> void:
	# set_anchors_and_offsets_preset, NOT set_anchors_preset: inside _ready
	# the parent may still be laid out at size 0, and the anchors-only call
	# keeps offsets that freeze this control at that zero rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Rebuild the cell layout for the current set of local slots.
func update_layout() -> void:
	for cell: Dictionary in _cells:
		cell.container.queue_free()
	_cells.clear()
	if world == null:
		return
	var slots: Array = Game.local_inputs.keys()
	slots.sort()
	var count := slots.size()
	var rects := _layout_rects(maxi(count, 1))
	if count == 0:
		_add_cell(-1, rects[0])
		return
	for i in count:
		_add_cell(slots[i], rects[i])
	if count == 3:
		_add_join_hint(rects[3])

## Anchor rects (in fractions) per cell for a given player count.
	apply_video_to_cells()

func _layout_rects(count: int) -> Array:
	match count:
		1:
			return [Rect2(0, 0, 1, 1)]
		2:
			return [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
		_:
			return [Rect2(0, 0, 0.5, 0.5), Rect2(0.5, 0, 0.5, 0.5),
				Rect2(0, 0.5, 0.5, 0.5), Rect2(0.5, 0.5, 0.5, 0.5)]

func _place(control: Control, frac: Rect2) -> void:
	control.anchor_left = frac.position.x
	control.anchor_top = frac.position.y
	control.anchor_right = frac.position.x + frac.size.x
	control.anchor_bottom = frac.position.y + frac.size.y
	control.offset_left = 1
	control.offset_top = 1
	control.offset_right = -1
	control.offset_bottom = -1

func _add_cell(slot: int, frac: Rect2) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	_place(container, frac)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.world_3d = get_tree().root.find_world_3d()
	viewport.msaa_3d = Viewport.MSAA_DISABLED if low_fx else Viewport.MSAA_2X
	viewport.scaling_3d_scale = 0.7 if low_fx else 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var rig := Node3D.new()
	viewport.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ZOOM_SIZES[DEFAULT_ZOOM]
	cam.near = 0.5
	cam.far = 300.0
	viewport.add_child(cam)
	var hud: Control = null
	if slot >= 0:
		hud = PlayerHud.new()
		hud.slot = slot
		hud.world = world
		container.add_child(hud)
	else:
		container.add_child(_spectator_prompt())
	_cells.append({"slot": slot, "container": container, "viewport": viewport,
		"rig": rig, "cam": cam, "hud": hud,
		"yaw_index": 0, "yaw": Player.ISO_ROT, "zoom_index": DEFAULT_ZOOM,
		"size": ZOOM_SIZES[DEFAULT_ZOOM], "prev_rot": 0, "prev_zoom": 0,
		"fp": true, "prev_view": false, "fp_zoom": 0})

func _spectator_prompt() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	# NO TITLE. The name is on the loading screen the player just watched,
	# and before that on the tab, and before that on the link they
	# followed. Saying it a fourth time in 64-point gold pushed the one
	# thing this screen is FOR — how to start playing — down the page in
	# small print underneath it.
	var prompt := Label.new()
	prompt.text = "Press SPACE or a gamepad's A button to jump in!"
	prompt.add_theme_font_size_override("font_size", 42)
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)
	return center

## With three players the spare quarter becomes a big battle map of the
## whole area (main.gd redraws it alongside the corner minimaps).
func _add_join_hint(frac: Rect2) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_place(panel, frac)
	add_child(panel)
	big_map = TextureRect.new()
	big_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(big_map)
	_cells.append({"slot": -2, "container": panel, "viewport": null,
		"rig": null, "cam": null, "hud": null})

## First-person hand: the held item bottom-right of your own camera, on a
## render layer only your own camera draws.
func _update_viewmodel(cell: Dictionary, player: Player) -> void:
	var cam: Camera3D = cell.cam
	var sig := str(player.held())
	if cell.get("vm_sig", "") != sig:
		cell.vm_sig = sig
		if cell.get("vm") != null and is_instance_valid(cell.vm):
			cell.vm.queue_free()
			cell.vm = null
		var item: Dictionary = player.held()
		if item.kind != "empty":
			var model := ItemFactory.build(str(item.kind), int(item.id))
			model.scale = Vector3(0.9, 0.9, 0.9)
			var vm_layer := RenderLayers.viewmodel_of(player.slot)
			for node in model.find_children("*", "VisualInstance3D", true, false):
				(node as VisualInstance3D).layers = vm_layer
			cam.add_child(model)
			var base := Vector3(0.3, -0.42, -0.72)
			# Long weapons sit further out so you never see their back end.
			if item.kind == "weapon" and int(item.id) in [1, 9]:
				base += Vector3(0.04, -0.04, -0.4)
			model.position = base
			model.rotation_degrees = Vector3(0, 6, 0)
			cell.vm = model
			cell.vm_base = base
	cam.cull_mask = RenderLayers.camera_mask(player.slot)

func _find_player(slot: int) -> Player:
	if world == null or world.players == null:
		return null
	for child in world.players.get_children():
		if child is Player and child.is_local and child.slot == slot:
			return child
	return null

## THE IDLE CAMERA: a hawk, not a security camera.
##
## It used to lock onto the first player it found and orbit them at a fixed
## height, angle and zoom, for as long as nobody joined. Two problems with
## that: it snapped between people as the roster changed, and it was the
## same shot forever — which is what everybody sees FIRST, before they have
## joined, so it is the game's shop window.
##
## Now it drifts. Four slow, independent cycles that never line up, so it
## does not visibly loop:
##
##   - the ORBIT goes round at a steady crawl,
##   - the PITCH sweeps between about 25 and 65 degrees, so the view rises
##     to look across the landscape and drops to look down on it,
##   - the ZOOM breathes in and out, and now and then commits to a proper
##     stoop at whatever it is watching,
##   - and the SUBJECT changes every few seconds — usually somebody
##     playing, sometimes just a corner of the map worth seeing.
##
## The focus EASES to each new subject rather than cutting, which is what
## stops a busy roster turning the shot into a slideshow.
## Wider, and moving enough that you can see it moving. The first version
## was too tight to show the world and too slow to read as anything but a
## still: the pitch took over a minute to sweep once and the zoom moved so
## little that it was impossible to tell it was happening. Doubled the
## framing, doubled the sweep, and gave the zoom a range you notice.
const SPEC_ORBIT_SPEED := 0.10
const SPEC_PITCH_MID := 45.0
const SPEC_PITCH_SWING := 20.0
const SPEC_PITCH_RATE := 0.11
const SPEC_RADIUS := 88.0
const SPEC_ZOOM_MID := 54.0
const SPEC_ZOOM_SWING := 18.0
const SPEC_ZOOM_RATE := 0.085
## How far in a stoop goes, as a fraction of the ordinary framing.
const SPEC_DIVE_TO := 0.42

var _spec_t := 0.0
var _spec_focus := Vector3.INF
var _spec_target := Vector3.INF
var _spec_hold := 0.0
var _spec_zoom := 26.0

func _spectator_camera(cam: Camera3D, delta: float) -> void:
	_spec_t += delta
	_orbit_angle += delta * SPEC_ORBIT_SPEED
	_spec_hold -= delta
	if _spec_hold <= 0.0 or _spec_target == Vector3.INF:
		_spec_hold = randf_range(6.0, 11.0)
		_spec_target = _pick_spectacle()
	if _spec_focus == Vector3.INF:
		_spec_focus = _spec_target
	# Ease, never cut. A hard snap between two people on opposite sides of
	# the map reads as a glitch rather than a camera move.
	_spec_focus = _spec_focus.lerp(_spec_target, clampf(delta * 0.6, 0.0, 1.0))
	var pitch := deg_to_rad(SPEC_PITCH_MID
		+ SPEC_PITCH_SWING * sin(_spec_t * SPEC_PITCH_RATE))
	var flat := cos(pitch)
	var offset := Vector3(cos(_orbit_angle) * flat, sin(pitch),
		sin(_orbit_angle) * flat) * SPEC_RADIUS
	# The stoop: mostly a slow breath, occasionally a genuine drop onto
	# whatever is down there, on a cycle long enough not to feel periodic.
	var breathe := SPEC_ZOOM_MID + SPEC_ZOOM_SWING * sin(_spec_t * SPEC_ZOOM_RATE)
	var dive := maxf(0.0, sin(_spec_t * 0.021))
	_spec_zoom = lerpf(_spec_zoom,
		lerpf(breathe, SPEC_ZOOM_MID * SPEC_DIVE_TO, dive * dive),
		clampf(delta * 0.7, 0.0, 1.0))
	cam.look_at_from_position(_spec_focus + offset, _spec_focus, Vector3.UP)
	cam.size = _spec_zoom

## Somewhere worth pointing the camera next: usually somebody playing,
## sometimes a corner of the world, so an empty server still has a view.
func _pick_spectacle() -> Vector3:
	# IT FLIES THE MAP, it does not shadow people. Following whoever
	# happened to be playing was the old behaviour and the reason this got
	# rewritten: it is a view of the WORLD, shown to somebody deciding
	# whether to join, and a world is more interesting than the back of
	# one player's head. Anybody it happens to pass is a bonus.
	if world == null or world.chunks == null:
		return _someone_to_watch()
	# A random spot inside the map, on the ground rather than under it.
	#
	# `world.chunks` is a ChunkView, NOT the server's ChunkStore: it has
	# `get_block` and nothing else. There is no `half_extent()` or
	# `surface_y()` to call over here — the client's copy of the world's
	# size is `world.client_size`, and the ground has to be found by
	# looking. Reaching for the store's API from a client is a runtime
	# error on a code path nobody exercises until somebody is watching.
	var half := maxf(float(int(world.client_size) / 2) - 20.0, 10.0)
	var spot := Vector3(randf_range(-half, half), 0.0, randf_range(-half, half))
	spot.y = _ground_near(floori(spot.x), floori(spot.z)) + 6.0
	return spot

## The surface in a column, as far as this client knows it. Chunks it has
## not been sent read as air, so this falls back to the spawn's height
## rather than dropping the camera to the floor of the world.
func _ground_near(wx: int, wz: int) -> float:
	var base := 40.0 if world == null else float(Vector3(world.spawn_pos).y)
	if world == null or world.chunks == null:
		return base
	var top := int(base) + 40
	for y in range(top, maxi(top - 90, 2), -1):
		if world.chunks.get_block(Vector3i(wx, y, wz)) != Blocks.AIR:
			return float(y) + 1.0
	return base

## Somewhere worth pointing the idle camera: a real player (humans first,
## then computer players), else the spawn point.
func _someone_to_watch() -> Vector3:
	if world == null:
		return Vector3.ZERO
	var fallback := Vector3(world.spawn_pos)
	if world.players == null:
		return fallback
	var bot_seen := Vector3.INF
	for child in world.players.get_children():
		var p := child as Player
		if p == null:
			continue
		if bool(Game.roster.get(p.player_id, {}).get("bot", false)):
			bot_seen = p.position
			continue
		return p.position
	return bot_seen if bot_seen != Vector3.INF else fallback

func _process(delta: float) -> void:
	_orbit_angle += delta * 0.12
	for cell: Dictionary in _cells:
		if cell.cam == null:
			continue
		var rig: Node3D = cell.rig
		var cam: Camera3D = cell.cam
		if cell.slot < 0:
			_spectator_camera(cam, delta)
			continue
		var player := _find_player(cell.slot)
		if player == null:
			continue
		var input: InputSlot = Game.local_inputs.get(cell.slot)
		# First-person toggle (T / gamepad Y).
		if input != null:
			var view := input.is_view_toggle_pressed()
			if view and not cell.prev_view:
				cell.view_mode = (int(cell.get("view_mode", 0)) + 1) % 3
				cell.fp = int(cell.view_mode) == 2
				Sfx.play("tick", -8.0)
			cell.prev_view = view
		player.set_fp(cell.fp)
		if cell.fp:
			# Sniper zoom: the zoom controls step the FOV down; the mouse
			# slows to match and the crosshair grows (see PlayerHud).
			if input != null:
				var fp_zoom := input.zoom_direction()
				if fp_zoom != 0 and cell.prev_zoom == 0:
					cell.fp_zoom = clampi(int(cell.fp_zoom) + fp_zoom, 0, FP_FOVS.size() - 1)
					Sfx.play("tick", -14.0)
				cell.prev_zoom = fp_zoom
			player.fp_zoom = cell.fp_zoom
			# Through the character's eyes: perspective, own body culled.
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = lerpf(cam.fov, FP_FOVS[cell.fp_zoom], 0.25)
			cam.near = 0.05
			cam.cull_mask = RenderLayers.camera_mask(player.slot)
			var eye: Vector3 = player.position + Vector3(0, Player.EYE_HEIGHT, 0)
			cam.look_at_from_position(eye, eye + player.look_dir(), Vector3.UP)
			_update_viewmodel(cell, player)
			var vm: Node3D = cell.get("vm")
			if vm != null and is_instance_valid(vm):
				# Tuck the gun away while zoomed in (aiming down sights).
				vm.visible = int(cell.get("fp_zoom", 0)) == 0
				# Doom-style bob: the gun sweeps a parabolic arc while running.
				var run := Vector2(player.velocity.x, player.velocity.z).length()
				if not player.on_floor:
					run = 0.0
				cell.bob_amp = lerpf(float(cell.get("bob_amp", 0.0)), clampf(run / 7.0, 0.0, 1.0), minf(1.0, delta * 6.0))
				cell.bob_phase = float(cell.get("bob_phase", 0.0)) + delta * (4.0 + run * 0.9)
				var amp: float = 0.055 * float(cell.bob_amp)
				vm.position = Vector3(cell.get("vm_base", Vector3(0.3, -0.42, -0.72))) \
					+ Vector3(cos(float(cell.bob_phase)) * amp, -absf(sin(float(cell.bob_phase))) * amp * 1.3, 0)
				# Sword rests held UP at guard and sweeps across when swung;
				# other weapons just kick back.
				if str(player.held().kind) == "weapon" and int(player.held().id) == 13:
					# Guard rest with the blade up; a swing winds it higher
					# overhead, then chops it DOWN across the view.
					if player.swing_time <= 0.0:
						vm.rotation_degrees = Vector3(35.0, 6.0, 0.0)
					else:
						var swt := clampf(1.0 - player.swing_time / 0.25, 0.0, 1.0)
						if swt < 0.3:
							vm.rotation_degrees = Vector3(
								lerpf(35.0, 80.0, swt / 0.3), 6.0, 0.0)
						else:
							var sww := minf((swt - 0.3) / 0.7 * 1.2, 1.0)
							vm.rotation_degrees = Vector3(lerpf(80.0, -100.0, sww),
								lerpf(6.0, -30.0, sww), lerpf(0.0, -20.0, sww))
				else:
					vm.rotation_degrees = Vector3(-75.0 * (player.swing_time / 0.25), 6, 0)
			continue
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 0.5
		cam.cull_mask = RenderLayers.camera_mask(-1)
		if cell.get("vm") != null and is_instance_valid(cell.vm):
			cell.vm.queue_free()
			cell.vm = null
			cell.vm_sig = ""
		# Poll this player's spin/zoom controls (edge-latched so one press or
		# stick flick = one step).
		if input != null and (cell.hud == null or not cell.hud.is_ui_open()):
			# Free orbit: the right stick (or Z/X) swings smoothly all the
			# way around the player — no isometric snapping.
			var spin := input.get_look_vector().x
			if input.kind != InputSlot.Kind.GAMEPAD:
				spin = float(input.rotate_direction())
			# 3.6 up from 2.6: with the curve holding the middle back, the
			# top of the stick can afford to be quicker, and spinning
			# round to see who is behind you was taking too long.
			if absf(spin) > 0.02:
				cell.yaw = fposmod(float(cell.yaw) - spin * delta * 3.6, TAU)
			# Right stick up/down orbits vertically too — all the way down
			# to a worm's-eye view from below the character.
			var tilt := -input.get_look_vector().y
			if input.kind == InputSlot.Kind.GAMEPAD and absf(tilt) > 0.02:
				cell.pitch = clampf(float(cell.get("pitch", DEFAULT_PITCH)) \
					+ tilt * delta * 2.2, -0.45, 1.35)
			var zoom := input.zoom_direction()
			if zoom != 0 and cell.prev_zoom == 0:
				cell.zoom_index = clampi(int(cell.zoom_index) - zoom, 0, ZOOM_SIZES.size() - 1)
			cell.prev_zoom = zoom
		cell.size = lerpf(cell.size, ZOOM_SIZES[cell.zoom_index], minf(1.0, delta * 5.0))
		cam.size = cell.size
		player.camera_yaw = cell.yaw
		player.camera_pitch = float(cell.get("pitch", DEFAULT_PITCH))
		# Smooth-follow the player from the current orbit direction.
		rig.position = rig.position.lerp(player.position, minf(1.0, delta * 6.0))
		if int(cell.get("view_mode", 0)) == 1:
			# Top-down map view, north up.
			player.camera_yaw = 0.0
			cam.look_at_from_position(rig.position + Vector3(0.01, CAM_HEIGHT + 20.0, 0.01),
				rig.position, Vector3(0, 0, -1))
			continue
		var yaw: float = cell.yaw
		var pitch := float(cell.get("pitch", DEFAULT_PITCH))
		var orbit_r := sqrt(CAM_DISTANCE * CAM_DISTANCE + CAM_HEIGHT * CAM_HEIGHT)
		var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * orbit_r
		cam.look_at_from_position(rig.position + offset, rig.position + Vector3(0, 1.0, 0), Vector3.UP)
	# Stream more chunks when someone is zoomed way out.
	if world != null and world.chunks != null:
		var max_size := 0.0
		for cell: Dictionary in _cells:
			if cell.cam != null and not cell.get("fp", false):
				max_size = maxf(max_size, float(cell.size))
		world.chunks.view_radius = clampi(
			int(Game.video.get("dist_blocks", 128)) / 16, 3, 13)
	# The mouse belongs to the keyboard player while they're in first person
	# — but never while the window is being resized (macOS fights it).
	var want_capture := false
	for cell: Dictionary in _cells:
		var input: InputSlot = Game.local_inputs.get(cell.slot)
		if cell.get("fp", false) and input != null \
				and input.kind == InputSlot.Kind.KEYBOARD_WASD \
				and (cell.hud == null or not cell.hud.is_ui_open()):
			want_capture = true
	if Time.get_ticks_msec() < _capture_hold_until:
		want_capture = false
	# The world menu needs a real cursor: while it's open nobody holds the
	# mouse captive, or none of its buttons can be clicked at all.
	if world_menu_open:
		want_capture = false
	var target_mode := Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != target_mode:
		Input.mouse_mode = target_mode


## X-Ray Goggles: while held, every other player gets a glowing marker
## drawn through walls — but only on this player's private render layer.
func _update_xray(cell: Dictionary, player: Player) -> void:
	var markers: Dictionary = cell.get("xray", {})
	var holding: bool = str(player.held().kind) == "weapon" and int(player.held().id) == 16
	var seen := {}
	if holding and world != null and world.players != null:
		for child in world.players.get_children():
			if child is Player and child != player:
				seen[child.player_id] = true
				var marker: MeshInstance3D = markers.get(child.player_id)
				if marker == null or not is_instance_valid(marker):
					marker = MeshInstance3D.new()
					var mesh := SphereMesh.new()
					mesh.radius = 0.45
					mesh.height = 0.9
					marker.mesh = mesh
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color(0.5, 1.0, 0.95, 0.6)
					mat.emission_enabled = true
					mat.emission = Color("7de8e0")
					mat.emission_energy_multiplier = 3.0
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mat.no_depth_test = true
					marker.material_override = mat
					marker.layers = RenderLayers.viewmodel_of(player.slot)
					add_child(marker)
					markers[child.player_id] = marker
				marker.position = child.position + Vector3(0, 1.5, 0)
	for id in markers.keys().duplicate():
		if not seen.has(id):
			if is_instance_valid(markers[id]):
				markers[id].queue_free()
			markers.erase(id)
	cell.xray = markers

## Video setting: 3D render resolution as a fraction of window size.
func apply_video_to_cells() -> void:
	set_render_scale(clampf(int(Game.video.get("render_scale", 40)) / 100.0, 0.01, 1.0))
	set_wireframe(bool(Game.video.get("wire", false)))

func set_render_scale(scale_f: float) -> void:
	for cell: Dictionary in _cells:
		if cell.cam != null:
			(cell.cam.get_viewport() as SubViewport).scaling_3d_scale = scale_f

## Video toggle: draw the whole world as wireframes (retro debug look, and
## the ultimate old-computer mode).
func set_wireframe(on: bool) -> void:
	for cell: Dictionary in _cells:
		if cell.cam != null:
			(cell.cam.get_viewport() as SubViewport).debug_draw = \
				Viewport.DEBUG_DRAW_WIREFRAME if on else Viewport.DEBUG_DRAW_DISABLED

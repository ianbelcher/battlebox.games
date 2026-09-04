extends Node
## WORLD_SIGHT_TEST=1: are the names and hearts over other players' heads
## drawn only for the seats that can see the body under them?
##
##   WORLD_ROLE=client WORLD_SIGHT_TEST=1 WORLD_AUTOTEST=2 WORLD_AUTOTEST_HUMAN=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
##
## (A window, or tools/screenshot.sh: the sight pass does nothing on a
## headless run, because nothing is drawn there.)
##
## The tags are drawn by render layer, one per seat, and a seat's layer is
## only set on a tag while that seat's camera has a clear line to the body
## — so somebody hiding behind a wall is not announced by hearts floating
## over it. What this reports, every few seconds, is who is drawn for
## whom, and at the end whether both answers ever came up: a run where
## every tag was always drawn means the pass is not hiding anything, and
## a run where nothing was ever drawn means it is not showing anything.
## It also checks the rules that do not need a wall: a computer player
## never gets a name, and a seat never draws its own tag.

const START_AFTER := 8.0
const EVERY := 3.0

var _t := 0.0
var _said := 0.0
var _shown := 0
var _hidden := 0
var _wrong := 0
var _worst := ""

func _ready() -> void:
	print("SIGHT: probe armed")

func _physics_process(delta: float) -> void:
	_t += delta
	_aim_the_person()
	if _t < START_AFTER:
		return
	var world: WorldNode = Game.world
	if world == null or world.players == null:
		return
	if _t - _said < EVERY:
		return
	_said = _t
	var seats: Array = Game.local_inputs.keys()
	seats.sort()
	var lines: Array[String] = []
	for child in world.players.get_children():
		if not (child is Player):
			continue
		var player: Player = child
		var entry: Dictionary = Game.roster.get(player.player_id, {})
		var is_bot := bool(entry.get("bot", false))
		var state: Dictionary = player.overhead_state()
		var mask := int(state.layers)
		var who: Array[String] = []
		for slot: int in seats:
			var drawn := (mask & RenderLayers.overhead_of(slot)) != 0
			if player.is_local and player.slot == slot:
				if drawn:
					_wrong += 1
					_worst = "%s drawn on its own seat" % str(entry.get("name", player.player_id))
				continue
			if drawn:
				_shown += 1
				who.append(str(slot))
			else:
				_hidden += 1
		if is_bot and not str(state.name).is_empty():
			_wrong += 1
			_worst = "computer player %s has a name over its head" % str(state.name)
		if not is_bot and str(state.name).is_empty() and not world.client_downed.has(player.player_id):
			_wrong += 1
			_worst = "person %s has no name over their head" % str(entry.get("name", player.player_id))
		lines.append("%s%s[%s] seen by seats {%s}%s" % [
			"bot " if is_bot else "", str(entry.get("name", player.player_id)),
			str(state.hearts).replace("\n", "/"), ",".join(who),
			_why_hidden(player, seats, mask)])
	print("SIGHT: t=%.0fs shown=%d hidden=%d | %s%s" % [_t, _shown, _hidden,
		"ok   both drawn and withheld" if _shown > 0 and _hidden > 0 and _wrong == 0
			else ("FAIL " + _worst if _wrong > 0
				else ("never withheld a tag" if _hidden == 0 else "never drew a tag")),
		"" if lines.is_empty() else "\n  " + "\n  ".join(lines)])

## For every seat that is NOT drawing this tag: what is in the way, and
## how far off the body is. A hill twenty blocks off is the feature
## working; the stone that an unloaded chunk reads as would be a bug.
func _why_hidden(player: Player, seats: Array, mask: int) -> String:
	var world: WorldNode = Game.world
	var chunks: ChunkView = world.chunks
	var notes: Array[String] = []
	for slot: int in seats:
		if player.is_local and player.slot == slot:
			continue
		if (mask & RenderLayers.overhead_of(slot)) != 0:
			continue
		var cam := _camera_of(slot)
		if cam == null:
			notes.append("seat %d: no camera" % slot)
			continue
		var feet := player.global_position
		var dist := cam.global_position.distance_to(feet)
		var blocker := ""
		for height in OverheadSight.BODY_POINTS:
			var point := feet + Vector3(0, height, 0)
			var origin := OverheadSight.ray_origin(cam.global_position,
				-cam.global_transform.basis.z,
				cam.projection == Camera3D.PROJECTION_ORTHOGONAL, point)
			var hit: Array = [null]
			var clear := OverheadSight.line_clear(origin, point, func(cell: Vector3i) -> bool:
				var block := chunks.get_block(cell)
				if Blocks.is_opaque(block) and hit[0] == null:
					hit[0] = [cell, block]
				return Blocks.is_opaque(block))
			if not clear and hit[0] != null:
				var h: Array = hit[0]
				blocker = "%s at %s (%.0f from the body)" % [Blocks.display_name(int(h[1])),
					str(h[0]), Vector3(h[0]).distance_to(point)]
		notes.append("seat %d: %.0f away, %s" % [slot, dist,
			"held on from a moment ago" if blocker.is_empty() else "behind " + blocker])
	return "" if notes.is_empty() else " — " + "; ".join(notes)

## The seat's camera is the one wearing the seat's mask. Matching on the
## overhead bit alone picked up the character picker's preview camera,
## whose default mask has every bit set.
func _camera_of(slot: int) -> Camera3D:
	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var cam := node as Camera3D
		if cam.is_current() and (cam.cull_mask == RenderLayers.camera_mask(slot)
				or cam.cull_mask == RenderLayers.orbit_mask(slot)):
			return cam
	return null

## The idle person in seat 0 (WORLD_AUTOTEST_HUMAN) is stood a few blocks
## from another body — another person if there is one, else the nearest
## computer player — and turned to face it, every tick, so a screenshot
## of the run has a tag in it rather than a beach. A local player's
## position is the client's to set, so this is an ordinary move as far
## as the server is concerned.
const STAND_OFF := 6.0

func _aim_the_person() -> void:
	var world: WorldNode = Game.world
	if world == null or world.players == null:
		return
	var me: Player = null
	var nearest: Player = null
	var best := INF
	for child in world.players.get_children():
		if not (child is Player):
			continue
		var p: Player = child
		if p.is_local and p.slot == 0 and not (p.input is BotSlot):
			me = p
	if me == null:
		return
	for child in world.players.get_children():
		if not (child is Player) or child == me:
			continue
		var d: float = me.position.distance_to(child.position)
		var person := not bool(Game.roster.get(child.player_id, {}).get("bot", false))
		if person:
			d -= 10000.0  # a person beats any computer player
		if d < best:
			best = d
			nearest = child
	if nearest == null:
		return
	var away: Vector3 = me.position - nearest.position
	away.y = 0.0
	if away.length() < 0.5:
		away = Vector3(1, 0, 0)
	me.fly_mode = true
	me.velocity = Vector3.ZERO
	me.position = nearest.position + away.normalized() * STAND_OFF + Vector3(0, 0.6, 0)
	var eye := me.position + Vector3(0, Player.EYE_HEIGHT, 0)
	var to := (nearest.position + Vector3(0, 1.0, 0) - eye).normalized()
	me.look_yaw = atan2(-to.x, -to.z)
	me.look_pitch = asin(clampf(to.y, -1.0, 1.0))

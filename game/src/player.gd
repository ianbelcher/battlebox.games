class_name Player
extends Node3D
## One character in the world. Local players run hand-rolled voxel AABB
## physics against the ChunkView data (no physics engine — deterministic,
## cheap, and 16 players cost nothing); remote players glide toward their
## replicated positions. The avatar visual is the shared blob model.

const GRAVITY := 22.0
## HOLD THE LEFT TRIGGER AND GO UP. Brisk enough to clear a wall while you
## hold it, and gravity takes over the instant you let go — unlike flying,
## which parks you in mid-air.
const LIFT_SPEED := 6.0
## WALK INTO A WALL AND CLIMB IT, one block a second.
##
## Auto-hop already handles a single step up. Anything taller than that
## was a trap: a four-year-old who dug straight down could not get out of
## the hole they had just made, and the only way back was an adult. Slow
## on purpose — it is a way out, not a way to scale a tower quickly.
const WALL_CLIMB_SPEED := 1.0
## THE BOAT OR CAR UNDER THIS PLAYER'S FEET, if any, and where they are
## standing on it in the vehicle's own frame.
##
## Keeping the spot in the VEHICLE's frame rather than the world's is what
## makes "everyone stays where they were standing" work when it turns: the
## spot is remembered as "two blocks aft, one to port" and turned back
## into a world position after the vehicle has moved. Doing it as a plain
## position delta carries people along fine in a straight line and slides
## them off the side in a turn.
var ride_id := ""
## How often a rider re-asks for a helm nobody is holding.
const HELM_RETRY_SECONDS := 0.5
var _helm_ask := 0.0
## Where the vehicle was last physics frame, so this frame's motion can be
## worked out and applied to whoever is standing on it.
var _ride_was := ""
var _ride_was_pos := Vector3.ZERO
var _ride_was_yaw := 0.0
## Sent to the server about as often as a position is.
var _ride_send := 0.0
const RIDE_SEND_HZ := 15.0
## HOW FAR ABOVE THE FEET "room above" IS TESTED, and therefore how far a
## top-out has to lift you. Named because it is load-bearing in two places
## that have to agree: the probe below decides when a climb has reached
## the top, and the mantle has to actually clear what the probe measured.
## A lift shorter than this cannot finish a climb by construction,
## whatever else is right.
const STEP_UP_PROBE := 1.05

## FINISHING A CLIMB IS A MANTLE, NOT A HOP — and getting that wrong is
## the whole of "you get to the top of the wall and just bounce".
##
## `room_up` — the space one block up being clear — is what "I have
## reached the top" MEANS, and by construction the lip is then
## STEP_UP_PROBE above the feet. So a top-out has to lift you at least
## that far or you have not topped out at all.
##
## It was a single ballistic shove of 3.8, which under this file's own
## GRAVITY of 22 buys 3.8² / (2 × 22) = 0.33 BLOCKS of rise. A third of
## the way. So the player rose an inch, fell back, `room_up` went false
## again on the way down, the climb re-engaged, and the two of them traded
## places forever. Measured with tests/climb_probe.gd: the height trace
## climbs cleanly to just under the lip and then flattens into a permanent
## 0.4-block oscillation for the rest of the run. That is the bounce — and
## the reason it survived a fix to ClimbRule is that the truth table was
## never the problem. The ARITHMETIC was.
##
## A shove big enough would work — 7.0 clears 1.11 blocks, and that is
## what the kerb hop does — but at the top of a wall it reads as being
## flung into the air by touching one. So this is a held lift instead:
## velocity is pinned for a third of a second, which carries you 1.43
## blocks, over the lip with margin, at a steady climbing pace rather than
## a jump. Once the feet clear the lip the horizontal sweep stops being
## blocked and you simply walk on over the top, which is what the move is
## supposed to look like.
##
## tests/unit/climb_rule_test.gd checks the two numbers against
## STEP_UP_PROBE, so a future edit that makes the lift too small again
## fails a test rather than shipping.
const CLIMB_TOP_LIFT := 4.2       ## blocks per second, held
const CLIMB_TOP_SECONDS := 0.34   ## 4.2 x 0.34 = 1.43 blocks, against 1.05 needed

## Seconds of mantle left. Deliberately NOT re-armed while it runs: one
## window is more than the geometry can ever need, and a lift that can
## renew itself is a lift that walks you up a chimney you are merely
## leaning on.
var _top_out := 0.0
## True while pressed against a wall and rising up it. Read on the frame
## the wall STOPS blocking, which is the moment worth acting on.
var _climbing := false
## How much HEIGHT a bouncy block adds per bounce, and how high it will
## ever throw you. Forty blocks is half the world's height: high enough to
## see the whole island, and a long enough fall back that the trampoline
## is the point of it rather than a way to get somewhere.
##
## Doubled from twenty, which topped out sooner than the children playing
## with it wanted. Nothing else has to change for that: the settling
## behaviour below is a property of the arithmetic, not of the number —
## once a bounce reaches the ceiling, the fall back arrives with exactly
## the energy for that same height, at any ceiling.
const BOUNCE_GAIN_BLOCKS := 1.0
const BOUNCE_CEILING_BLOCKS := 40.0
const JUMP_VELOCITY := 8.6
## RUNNING IS THE DEFAULT, and there is nothing to hold down for it.
##
## There was a sprint, and it did nothing: `is_sprint_pressed()` returns
## false and always has, so the 1.55x branch in _local_move was dead code
## and everybody has been moving at one speed the whole time. Rather than
## bind a button nobody would find, the one speed IS the run — which is
## what a child expects from a stick pushed all the way forward anyway.
##
## 5.6 is Minecraft's sprint, up from 4.6, which was its walk. Sneak
## (Shift, or the left stick pressed in) still halves it, and halving a
## run is a more useful quiet walk than halving a walk was.
const RUN_SPEED := 5.6
## Kept in proportion with the run rather than left where it was. Water
## is already the slow part of the map; making the land faster and not
## the water would have widened that on its own.
const SWIM_SPEED := 3.6

## How fast you fly once you are OUT of the round.
##
## Faster than running, deliberately. Somebody who is out is not playing: they are
## travelling back to its own flag to rejoin, and every second of that is
## dead time for the person holding the controller. It used to share the
## creative-mode flying speed, which is tuned for pottering about building
## things rather than for crossing the map with something to do at the far
## end.
const OUT_FLY_SPEED := 11.0

## THE KNOCKOUT RISE: how far you drift up when you are knocked out, and how
## long it takes. Being out used to leave you standing on the spot you
## died on, at ground level, in the middle of whatever killed you, with no
## sign that anything had changed except that nothing worked any more.
## Floating up out of it says "you are out" without a word of text, and it
## puts you where you can see the map you are about to fly across.
##
## It is a NUDGE, not a cutscene: you keep full control the whole way up
## and any input of your own takes over immediately.
const KNOCKOUT_RISE_BLOCKS := 10.0
const KNOCKOUT_RISE_SECONDS := 3.0
## Being knocked out leaves you FLYING, at the top of the rise. Coming
## back down is the two things flight already does and every player
## already knows: double-tap Ⓐ to stop flying and drop, or hold the left
## trigger and let go of it. No separate falling mode to learn, and no
## mode that only exists while you are knocked out.
var _knockout_rise := 0.0
## Climbing clear of the map, once your whole team is out and there is
## nobody left down there to watch. Height to reach, or INF for "stay
## where you are".
##
## A RISE, NOT A TELEPORT. This used to be `teleport()` straight to the
## spectator height, fired by the HUD the same instant you were knocked
## out — so the graceful ten-block drift was real, ran correctly, and was
## instantly overwritten by a jump of twenty-odd blocks. What a player saw
## was a red screen and then a snap, which is exactly the "the rise is not
## happening at all" it was reported as. It is the same journey now, taken
## at a speed a person can follow.
var _lift_to := INF
const SPECTATOR_LIFT_SPEED := 7.0

## Go up and watch from there. Takes effect after any knockout rise already
## running, because that one is the one with the timing promise on it.
func lift_clear_to(height: float) -> void:
	_lift_to = height

## ARE WE HELD STILL BY A REVIVE? True for the player being picked up AND
## for the team-mate picking them up, so the pair of them stand there for
## the three seconds it takes and it always finishes.
##
## Worked out on the client from state it already has: the server decides
## whether a revive is happening at all, and the same radius it measures
## with decides who is close enough to be part of it. A shade of slack, so
## whoever is holding still is comfortably inside the range being tested.
func revive_locked() -> bool:
	if world == null or world.players == null:
		return false
	if world.revive_progress.has(player_id):
		return true      # being picked up
	if downed or world.out_ids.has(player_id):
		return false     # you cannot pick anybody up in either state
	var my_team := int(Game.roster.get(player_id, {}).get("team", -1))
	for rid: String in world.revive_progress.keys():
		if not world.client_downed.has(rid):
			continue
		if int(Game.roster.get(rid, {}).get("team", -2)) != my_team:
			continue
		for child in world.players.get_children():
			if child is Player and child.player_id == rid \
					and child.position.distance_to(position) \
						< WorldNode.REVIVE_RADIUS + 0.5:
				return true
	return false

## Held still for the beat after taking a flag. Same idea as the revive
## lock: the game is doing something to you, so you stop.
var capture_lock := 0.0

func begin_capture_hold(seconds: float) -> void:
	capture_lock = seconds

func begin_knockout_rise() -> void:
	_knockout_rise = KNOCKOUT_RISE_SECONDS
	# A grapple in flight OUTLIVES you otherwise, and a zip is a teleport:
	# it snaps you to its last waypoint at sixty blocks a second, so being
	# knocked out mid-swing threw the body across the map and started the
	# ten-block drift from wherever it landed. Seen as a jump of twenty-odd
	# blocks in a single frame, half way through the rise.
	grapple_time = 0.0
	carry_time = 0.0
	_grapple_path.clear()
	_climbing = false
	_top_out = 0.0
	_lift_to = INF
const HALF_WIDTH := 0.4
const HEIGHT := 1.8   # Minecraft's exact player height
const SEND_HZ := 12.0
const EDIT_REPEAT := 0.24
## Eye level for first person — near the top of the head, so blocks read
## about waist height like they should.
const EYE_HEIGHT := 1.62  # Minecraft's exact eye line
## Default camera yaw; the split-screen rig updates camera_yaw as the view
## spins so "stick up" always moves away from the camera.
const ISO_ROT := PI / 4.0

enum Anim { IDLE, WALK, AIR, SWIM, FLY, SNEAK }

var player_id := ""
var slot := -1
var is_local := false
var input: InputSlot = null
var world: Node = null

var velocity := Vector3.ZERO
var camera_yaw := ISO_ROT
var camera_pitch := 0.718  # orbit elevation, set by the camera rig
var on_floor := false
var in_water := false
var heading := Vector3(0, 0, -1)
## Minecraft-style loadout: 8 slots holding blocks, structure kits or
## weapons; the held item decides what right-click does.
var slots: Array = [
	{"kind": "weapon", "id": 0}, {"kind": "weapon", "id": 12},
	{"kind": "block", "id": Blocks.PLANKS}, {"kind": "block", "id": Blocks.COBBLE},
	{"kind": "block", "id": Blocks.GLASS}, {"kind": "block", "id": Blocks.LANTERN},
	{"kind": "block", "id": Blocks.BOOM}, {"kind": "block", "id": Blocks.TELEPORT},
]
var selected_slot := 0
var anim: int = Anim.IDLE
var leave_hold := 0.0

## First-person state (driven by the split-screen cell).
var fp_mode := false
var fp_zoom := 0
var look_yaw := 0.0
var look_pitch := 0.0

## Set while this player's picker is open: input drives the UI, not the body.
var ui_locked := false

func held() -> Dictionary:
	return slots[selected_slot]

## Put something picked up in the world into the hotbar, and say where it
## went (-1 if it did not go anywhere).
##
## ONE rule for every kind of pickup, because there used to be three and
## they disagreed: crates found the first empty slot, the block sucker
## overwrote whatever sat next to your hand — a Big Shooter, if that is
## what was there — and everything else made you open the menu and place
## it by hand. Picking something up should mean you are holding it.
##
##   already carrying one  ->  keep the one you have, change nothing
##   a slot is empty       ->  it goes there
##   the bar is full       ->  overwrite the first thing that is not a
##                             weapon; if it is ALL weapons, refuse
##
## Refusing is the right answer for a full bar of weapons: silently
## dropping one of them to make room for a block loses a fight.
func give_item(kind: String, id: int) -> int:
	for i in 8:
		var slot_here: Dictionary = slots[i]
		if str(slot_here.kind) == kind and int(slot_here.id) == id:
			return i
	for i in 8:
		if str(slots[i].kind) == "empty":
			slots[i] = {"kind": kind, "id": id}
			return i
	for i in 8:
		if str(slots[i].kind) != "weapon":
			slots[i] = {"kind": kind, "id": id}
			return i
	return -1

## Flight (double-tap jump toggles; landing exits).
##
## FLY_GRACE_SECONDS is how long after switching flight ON that touching
## the ground will NOT switch it off again — long enough to get clear of
## the block you were standing on.
const FLY_GRACE_SECONDS := 0.45
var _fly_grace := 0.0
var fly_mode := false
var _prev_jump := false
var _last_jump_ms := -10000
var _launch_latched := false
var _shoot_hold := 0.0
# The sky-drop is gone: matches now START players standing on the ground
# beside their team so they can build. See WorldNode._team_start_spot().

var _team_light: OmniLight3D = null

## A soft glow in your team's color so squads read at a glance.
func set_team_glow(team: int) -> void:
	# Retired as a light source — a bright lamp per player washed the
	# whole drop zone white. Team identity lives in the overhead hearts
	# and the radar now; the local player's soft glow gets tinted.
	if _team_light != null:
		_team_light.queue_free()
		_team_light = null
	pass
var downed := false
## Has the death animation already run for this knock-down? Reset when
## the player gets back up.
var _death_played := false
var dropping := false
var _was_in_water := false
## While > 0, horizontal velocity is carried (grapple zips, knockbacks)
## instead of being overwritten by stick input every frame.
var carry_time := 0.0
## Guided grapple zip: fly waypoint to waypoint, stop ON the last one.
var _grapple_path: Array = []
var grapple_time := 0.0
var _reel_accum := 0.0

const GRAPPLE_ZIP := 70.0  # matches the hook's flight speed: the reel-in
                           # takes exactly as long as the shot did

func start_grapple(path: Array) -> void:
	if path.is_empty():
		return
	_grapple_path = path.duplicate()
	var total := position.distance_to(path[0] as Vector3)
	for i in range(1, path.size()):
		total += (path[i - 1] as Vector3).distance_to(path[i] as Vector3)
	grapple_time = total / GRAPPLE_ZIP + 0.6
	carry_time = grapple_time
	on_floor = false
	Sfx.play("warp", -4.0)
var _prev_slot_pick := -1
var _last_note_cell := Vector3i(0, -99, 0)
var _warp_cooldown := 0.0

var _avatar: Node3D
var _tag: Label3D
var _glow: OmniLight3D
var _highlight: MeshInstance3D
var _send_accum := 0.0
var _edit_cooldown := 0.0
var _cycle_latch := false
var _remote_target := Vector3.ZERO
var _remote_yaw := 0.0
var _spawned := false
var _debug_ticks := 0

func setup(p_id: String, entry: Dictionary, p_local: bool, p_input: InputSlot, p_world: Node) -> void:
	player_id = p_id
	slot = int(entry.slot)
	is_local = p_local
	input = p_input
	world = p_world
	_avatar = AvatarFactory.build_character(entry.get("style", {}))
	if _avatar == null:
		_avatar = AvatarFactory.build_character({})
	_avatar.scale = Vector3(1.15, 1.15, 1.15)
	add_child(_avatar)
	_tag = Label3D.new()
	_tag.text = str(entry.name)
	_tag.font_size = 44
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = false
	_tag.modulate = Color.WHITE
	_tag.outline_modulate = Color(0.05, 0.05, 0.1, 0.9)
	_tag.outline_size = 14
	_tag.position = Vector3(0, 2.1, 0)
	_tag.visible = not is_local  # your own tag is pure noise to you
	add_child(_tag)
	# Every character carries a modest warm lantern so night isn't a void —
	# dim enough that it never blooms or floodlights a drop cluster.
	_glow = OmniLight3D.new()
	_glow.light_energy = 0.3
	_glow.omni_range = 7.0
	_glow.light_color = Color(1.0, 0.9, 0.7)
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 1.6, 0)
	add_child(_glow)
	if is_local:
		_highlight = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.04, 1.04, 1.04)
		_highlight.mesh = box
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.22)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		box.material = mat
		_highlight.top_level = true
		_highlight.visible = false
		add_child(_highlight)
	_apply_render_layer()

## Overhead display: hearts in two rows of four, trimmed in team color —
## you read health and side at a glance instead of a name.
func refresh_overhead(hp: int, team_color: Color, downed_now: bool,
		friendly := false) -> void:
	if _tag == null:
		return
	if is_local or (friendly and not downed_now):
		# Your own tag is noise to you, and teammates don't need targets
		# over their heads — enemies do.
		_tag.text = ""
		return
	if downed_now:
		# NOTHING over a downed player. The grey, half-transparent body is
		# the signal now, and it says the same thing from any distance
		# without adding a label to a screen that already has hearts over
		# everybody else. Their team-mate is told who to go for by the
		# prompt on their own HUD, which is where an instruction belongs.
		_tag.text = ""
		return
	hp = clampi(hp, 0, 8)
	var top_row := "".rpad(mini(hp, 4), "♥")
	var bottom_row := "".rpad(maxi(hp - 4, 0), "♥")
	_tag.text = top_row if bottom_row.is_empty() else top_row + "\n" + bottom_row
	_tag.modulate = Color(team_color.darkened(0.12), 0.9)
	_tag.outline_modulate = Color(0.05, 0.05, 0.1, 0.95)

## THE LOOK OF SOMEBODY WHO IS OUT OF THE FIGHT: grey, and half there.
##
## Fading alone was not enough. A faded player still has their team colour,
## their kit and their character on them, so at a glance across a scrap
## they read as somebody you still have to deal with — and working out who
## is actually still in it was the problem. Colour is the thing that says
## "in the game", so taking it away is the thing that says the opposite.
##
## An override rather than a tint, because it has to beat everything: the
## avatars are assembled from parts with their own materials, several of
## them shared between players, and anything short of replacing the
## material leaves somebody's shirt showing through.
static var _knocked_out_skin: StandardMaterial3D = null

## STILL FAINTLY THEIRS. A ghost with no colour at all says "somebody is
## out" and not "one of OURS is out", and on a five-team map that is the
## next thing you want to know — whether the grey shape floating over the
## fight is a team-mate to go and pick up or an enemy to ignore.
##
## A whisper of it, not a shirt. The point of the grey is still that they
## read as out at a glance; if the team colour were strong enough to
## compete with a living player's, that would be undone.
const KNOCKED_OUT_TINT := 0.30

## Cached per team, because every part of every downed player shares one
## material and there are only ever a couple of dozen teams.
static var _knocked_out_skins: Dictionary = {}

static func knocked_out_skin(team := -1) -> StandardMaterial3D:
	if _knocked_out_skins.has(team):
		return _knocked_out_skins[team]
	var grey := Color(0.66, 0.68, 0.74)
	var tinted := grey
	if team >= 0:
		var theirs: Color = WorldNode.TEAM_COLORS[team % WorldNode.TEAM_COLORS.size()]
		tinted = grey.lerp(theirs, KNOCKED_OUT_TINT)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(tinted.r, tinted.g, tinted.b, 0.42)
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.roughness = 1.0
	# Barely lit: a ghost should not pick up the sunset like everyone
	# else, or it goes orange and stops reading as grey at all.
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	skin.emission_enabled = true
	# The glow carries the tint too, so it still reads at night, when the
	# albedo is doing almost nothing.
	skin.emission = Color(tinted.r, tinted.g, tinted.b) * 0.46
	skin.emission_energy_multiplier = 0.5
	_knocked_out_skins[team] = skin
	return skin

func set_knocked_out_look(out_of_it: bool) -> void:
	var team := int(Game.roster.get(player_id, {}).get("team", -1))
	var skin := knocked_out_skin(team) if out_of_it else null
	for node in _avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_override = skin
		# The old fade is off: the material carries the transparency now,
		# and both at once made a ghost almost invisible.
		mesh.transparency = 0.0

func refresh_from_roster(entry: Dictionary) -> void:
	set_team_glow(int(entry.get("team", -1)))
	_tag.text = str(entry.name)
	var team := int(entry.get("team", -1))
	_tag.modulate = WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE
	var style: Dictionary = AvatarFactory.normalize_style(entry.get("style"))
	if str(_avatar.get_meta("style", "")) != str(style):
		var old := _avatar
		_avatar = AvatarFactory.build_character(style)
		_avatar.scale = Vector3(1.15, 1.15, 1.15)
		_avatar.rotation = old.rotation
		add_child(_avatar)
		old.queue_free()
		_apply_render_layer()
		# The held item died with the old avatar's arm — force a rebuild.
		_hand_sig = ""
		_refresh_hand()

## Local players' visuals live on a per-slot render layer so their own
## first-person camera can cull them (everyone else still sees them).
func render_layer_bit() -> int:
	return RenderLayers.body_of(slot)

func _apply_render_layer() -> void:
	if not is_local:
		return
	for node in _avatar.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = render_layer_bit()
	_tag.layers = render_layer_bit()

func set_fp(enabled: bool) -> void:
	if fp_mode == enabled:
		return
	fp_mode = enabled
	# NOT `_avatar.visible = false`. Your body is hidden from YOUR camera
	# by its render layer (see SplitScreen.cull_mask_for) — `visible` is a
	# property of the node, so it would hide you from the person sitting
	# next to you too, and two players on one screen could not see each
	# other. Re-apply the layer instead, which also covers anything added
	# to the avatar since it was built.
	if is_local and _avatar != null:
		_apply_render_layer()
	if enabled:
		look_yaw = atan2(-heading.x, -heading.z)
		look_pitch = -0.2
	else:
		heading = Vector3(-sin(look_yaw), 0, -cos(look_yaw))

## Unit vector the player is looking along in first person.
func look_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(-sin(look_yaw) * cp, sin(look_pitch), -cos(look_yaw) * cp)

## Mouse look for the keyboard player while in first person.
func _input(event: InputEvent) -> void:
	if not (is_local and fp_mode and input != null \
			and input.kind == InputSlot.Kind.KEYBOARD_WASD):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var zoom_slow := 1.0 / (1.0 + fp_zoom * 1.5)
		look_yaw -= event.relative.x * 0.0032 * zoom_slow
		look_pitch = clampf(look_pitch - event.relative.y * 0.0032 * zoom_slow, -1.45, 1.45)

func teleport(pos: Vector3) -> void:
	position = pos
	_remote_target = pos
	velocity = Vector3.ZERO
	_spawned = true

func remote_update(pos: Vector3, yaw: float, p_anim: int) -> void:
	_remote_target = pos
	_remote_yaw = yaw
	var packed := p_anim % 16
	if packed >= 8 and swing_time <= 0.0:
		swing_time = 0.25
	anim = packed % 8
	apply_remote_held(p_anim / 16)
	if not _spawned:
		position = pos
		_spawned = true

var _hand_item: Node3D = null
var _hand_sig := ""

## Show what's in hand on the right arm — yours and everyone else's.
func _held_code() -> int:
	var item := held()
	if item.kind == "weapon":
		return 1 + int(item.id)
	if item.kind == "block":
		return 100
	return 0

func apply_remote_held(code: int) -> void:
	var wanted: Dictionary
	if code == 0:
		wanted = {"kind": "empty", "id": 0}
	elif code == 100:
		wanted = {"kind": "block", "id": Blocks.M_STONE}
	else:
		wanted = {"kind": "weapon", "id": code - 1}
	if str(slots[selected_slot]) != str(wanted) and not is_local:
		slots[selected_slot] = wanted

func _refresh_hand() -> void:
	var item := held()
	var sig := str(item)
	if sig == _hand_sig:
		return
	_hand_sig = sig
	if _hand_item != null:
		_hand_item.queue_free()
		_hand_item = null
	var arm: Node3D = _avatar.find_child("arm-right", true, false)
	if arm == null:
		return
	if item.kind == "empty":
		return
	_hand_item = ItemFactory.build(str(item.kind), int(item.id))
	# Inside the scaled rig: cancel the rig's scale so the item is the size
	# it would be in the world, then sit it at the hand.
	var rig_scale := maxf(arm.get_parent_node_3d().global_basis.get_scale().y, 0.01) \
		/ maxf(scale.y, 0.01)
	_hand_item.scale = Vector3.ONE * (1.0 / maxf(rig_scale, 0.01))
	_hand_item.position = Vector3(0, -1.1, 0.2)
	arm.add_child(_hand_item)
	for node in _hand_item.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = render_layer_bit()

func selected_block() -> int:
	return int(held().id) if held().kind == "block" else -1

func _physics_process(delta: float) -> void:
	if is_local:
		if _spawned and not ui_locked:
			_local_move(delta)
			_local_actions(delta)
		# Safety net: nothing legitimate moves faster than a grapple zip
		# or leaves the island's surroundings. If physics ever blows up
		# (impulse bursts after a frame hitch), clamp instead of flying
		# to the horizon.
		if velocity.length_squared() > 60.0 * 60.0 and grapple_time <= 0.0:
			push_warning("Speed clamp: %s at %.0f m/s" % [player_id, velocity.length()])
			velocity = velocity.limit_length(60.0)
		# The world is a SQUARE slab `client_size` blocks on a side, so a
		# size of 50 means x and z both run -25..+25. Nothing is generated
		# outside it, so this is a hard wall, not a nudge: you simply
		# cannot walk off the edge of the world.
		if world != null and world.match_phase != "SETUP":
			var edge := float(world.client_size) * 0.5
			if edge > 8.0:
				var stopped := false
				if absf(position.x) > edge:
					position.x = signf(position.x) * edge
					velocity.x = 0.0
					stopped = true
				if absf(position.z) > edge:
					position.z = signf(position.z) * edge
					velocity.z = 0.0
					stopped = true
				if stopped:
					carry_time = 0.0
					grapple_time = 0.0
		if absf(position.x) > 900.0 or absf(position.z) > 900.0 \
				or position.y < -40.0 or position.y > WorldGen.CHUNK_H + 120.0:
			push_warning("Bounds clamp: %s at %v" % [player_id, position])
			position.x = clampf(position.x, -900.0, 900.0)
			position.z = clampf(position.z, -900.0, 900.0)
			position.y = clampf(position.y, -40.0, WorldGen.CHUNK_H + 120.0)
			velocity = Vector3.ZERO
			carry_time = 0.0
		if _spawned:
			_send_state(delta)
	else:
		# Teleports (match drops, resets) snap: smoothing across half the
		# map looks like the player being flung at hyperspeed.
		if position.distance_to(_remote_target) > 40.0:
			position = _remote_target
		else:
			position = position.lerp(_remote_target, minf(1.0, delta * 10.0))
		rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(1.0, delta * 10.0))
	swing_time = maxf(0.0, swing_time - delta)
	_refresh_hand()
	_footsteps(delta)
	_animate(delta)

var _step_prev := Vector3.ZERO
var _step_accum := 0.0

## Sprinting is loud — a soft thud every couple of meters that nearby
## players hear too, so nobody sneaks up at full speed. Walking is silent.
func _footsteps(delta: float) -> void:
	var flat := Vector2(position.x - _step_prev.x, position.z - _step_prev.z).length()
	var vertical := absf(position.y - _step_prev.y) > 0.15
	_step_prev = position
	if delta <= 0.0 or flat > 3.0:
		return
	# Walking is audible; creeping (or barely moving) is silent.
	if flat / delta < 3.0 or vertical or downed or fly_mode \
			or (is_local and input != null and input.is_sneak_pressed()):
		_step_accum = 0.0
		return
	_step_accum += flat
	if _step_accum < 2.1:
		return
	_step_accum = 0.0
	var dist := 6.0
	if not is_local:
		dist = 1e9
		for child in get_parent().get_children():
			if child is Player and child.is_local:
				dist = minf(dist, child.position.distance_to(position))
	if dist < 30.0:
		Sfx.play("step", -8.0 - dist * 0.8, 0.9 + randf() * 0.25)

# ------------------------------------------------------------------
# Local physics
# ------------------------------------------------------------------

func _chunks() -> ChunkView:
	return world.chunks

func _solid_at(pos: Vector3) -> bool:
	return Blocks.is_solid(_chunks().get_block(Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))))

## Any solid block overlapping the AABB at a candidate position?
## The deck we are standing on or about to land on, or INF for none.
func _deck_floor(from: Vector3, to: Vector3) -> float:
	if world == null or world.vehicle_view == null:
		return INF
	var found: Dictionary = world.vehicle_view.deck_under(to)
	if found.is_empty():
		return INF
	var deck: float = found.deck_y
	# Coming down through it, or already standing on it. Not while rising
	# through it — you can jump up out of a boat.
	if from.y >= deck - 0.05 or absf(from.y - deck) < 0.35:
		return deck
	return INF

## STANDING ON A BOAT, AND POSSIBLY DRIVING IT.
##
## Runs after this player's own movement, so what it does is add the
## vehicle's motion on top: your walking about the deck is yours, and the
## deck moving under you is the boat's. Both, every frame, which is what
## lets somebody walk to the bow of a boat that is already under way.
##
## The carry is done through the VEHICLE'S OWN FRAME rather than as a
## position delta. In a straight line the two are identical; in a turn the
## delta version slides everybody off the side, because the stern travels
## further than the bow.
func _ride(delta: float) -> void:
	if not is_local or world == null or world.vehicle_view == null:
		_ride_was = ""
		return
	var view: VehicleView = world.vehicle_view
	# CARRY FIRST, ASK AFTERWARDS.
	#
	# This used to look for a deck under the player and only then carry
	# them, which quietly means "you are carried as long as the boat has
	# not gone anywhere" — the deck has to still be under your feet at the
	# moment it is looked for. At walking pace that is true and it works.
	# It stops being true the moment the boat covers more ground in one
	# frame than you were standing from the edge, which is a lag spike, or
	# a fast boat, or a passenger near the rail. Then the rider is dropped
	# into the sea and the boat sails off.
	#
	# Being carried is a consequence of having been aboard LAST frame, so
	# that is what it is based on. Walking off is then still walking off:
	# the deck test below runs on the carried position and finds nothing.
	if not _ride_was.is_empty():
		var was: Dictionary = view.at(_ride_was)
		if was.is_empty():
			_ride_was = ""
		else:
			if view.driver_of(_ride_was) == player_id:
				var helm := input.get_move_vector()
				# Stick forward is throttle, stick sideways is helm.
				# Nothing to learn and nothing to press.
				view.drive_mine(_ride_was, -helm.y, helm.x, delta)
				_ride_send -= delta
				if _ride_send <= 0.0:
					_ride_send = 1.0 / RIDE_SEND_HZ
					world.sv_vehicle_moved.rpc_id(1, _ride_was, slot,
						Vector3(was.pos), float(was.yaw))
			var spot := VehicleGeom.to_local(_ride_was_pos, _ride_was_yaw,
				position)
			position = VehicleGeom.to_world(Vector3(was.pos), float(was.yaw),
				spot)
			# ...AND WHICH WAY YOU ARE POINTING GOES ROUND WITH HER TOO.
			#
			# The carry above is exact — measured at zero drift over a
			# forty-frame turn, as a passenger and at the helm — and it was
			# still reported as "when you turn, your position on the boat
			# moves". It is not the position. It is the FACING: only where
			# you stood was ever carried, so the boat rotated underneath a
			# body that went on pointing the same way at the world, and the
			# camera went on looking there as well.
			#
			# From the seat that is indistinguishable from sliding, and it
			# is why it read as the boat turning about the wrong centre:
			# everything you can see swings around you while you face one
			# way. Standing on a turning deck turns you. It always did in
			# life and it never did here.
			#
			# Rotated through VehicleGeom rather than Godot's own
			# `rotated(UP, …)`, which is the opposite sign convention: the
			# heading has to turn exactly as the position did, and the one
			# way to be sure of that is to use the same function.
			# THE TWO RUN OPPOSITE WAYS, and adding the same delta to both
			# is how this was wrong the first time. `heading` turns the way
			# VehicleGeom turns things; the yaws this file keeps are the
			# other way round, because `heading` is (-sin, -cos) of
			# look_yaw. Caught by the probe rather than by reading it: a
			# 1.04 radian turn came out as 2.08 radians of drift against
			# the deck, which is the shape of a sign flip and nothing else.
			var turned := wrapf(float(was.yaw) - _ride_was_yaw, -PI, PI)
			if absf(turned) > 0.00001:
				heading = VehicleGeom.to_world(Vector3.ZERO, turned, heading)
				var swing := -turned
				look_yaw = wrapf(look_yaw + swing, -PI, PI)
				camera_yaw = wrapf(camera_yaw + swing, -PI, PI)
				rotation.y = wrapf(rotation.y + swing, -PI, PI)
	var found: Dictionary = view.deck_under(position)
	var now_id := str(found.get("id", ""))
	if now_id != ride_id:
		# Stepping off frees the helm; stepping on asks for it. The server
		# decides — see VehicleDirector.board — and it is first aboard,
		# because a five-year-old standing on a boat expects it to go
		# rather than expecting to find a seat and press something.
		if not ride_id.is_empty():
			world.sv_vehicle_leave.rpc_id(1, ride_id, slot)
		ride_id = now_id
		if not ride_id.is_empty():
			world.sv_vehicle_board.rpc_id(1, ride_id, slot)
	if ride_id.is_empty():
		_ride_was = ""
		return
	# ASK AGAIN IF NOBODY IS DRIVING THE THING YOU ARE STANDING ON.
	#
	# The helm is granted by the server as its own message, and the full
	# vehicle list is another — so the two cross. A list built a moment
	# BEFORE the grant, arriving a moment AFTER it, rebuilds every
	# vehicle from a payload that says nobody is driving, and the helm is
	# quietly gone. The boat still carries you; it just stops answering,
	# which is precisely "it pulls me into it but I can't control it".
	#
	# Standing on a driverless vehicle is a state that should never
	# persist, so say so again. Reliable, throttled, and self-healing —
	# it also covers a dropped packet and a join landing mid-handover,
	# which no amount of ordering the two messages would.
	if view.driver_of(ride_id).is_empty():
		_helm_ask -= delta
		if _helm_ask <= 0.0:
			_helm_ask = HELM_RETRY_SECONDS
			world.sv_vehicle_board.rpc_id(1, ride_id, slot)
	else:
		_helm_ask = 0.0
	var v: Dictionary = view.at(ride_id)
	if v.is_empty():
		ride_id = ""
		_ride_was = ""
		return
	# Remembered for next frame's carry: where she was when we last stood
	# on her, in her own frame.
	_ride_was = ride_id
	_ride_was_pos = v.pos
	_ride_was_yaw = v.yaw

## At the helm of the thing we are standing on.
func driving() -> bool:
	if ride_id.is_empty() or world == null or world.vehicle_view == null:
		return false
	return world.vehicle_view.driver_of(ride_id) == player_id

func _collides(at: Vector3) -> bool:
	var min_x := floori(at.x - HALF_WIDTH)
	var max_x := floori(at.x + HALF_WIDTH)
	var min_y := floori(at.y)
	var max_y := floori(at.y + HEIGHT)
	var min_z := floori(at.z - HALF_WIDTH)
	var max_z := floori(at.z + HALF_WIDTH)
	for y in range(min_y, max_y + 1):
		for z in range(min_z, max_z + 1):
			for x in range(min_x, max_x + 1):
				if Blocks.is_solid(_chunks().get_block(Vector3i(x, y, z))):
					return true
	return false

func _local_move(delta: float) -> void:
	# In first person the gamepad right stick steers the look; movement is
	# relative to wherever you're facing (camera_yaw tracks look_yaw).
	if fp_mode:
		var look := input.get_look_vector()
		var zoom_slow := 1.0 / (1.0 + fp_zoom * 1.5)
		# Quicker at the top of the stick to match the orbit camera; the
		# curve in InputSlot is what keeps the fine end usable.
		look_yaw -= look.x * 3.9 * delta * zoom_slow
		look_pitch = clampf(look_pitch - look.y * 3.0 * delta * zoom_slow, -1.45, 1.45)
		camera_yaw = look_yaw
	var move := input.get_move_vector()
	var dir := Vector3(move.x, 0, move.y).rotated(Vector3.UP, camera_yaw)
	# AT THE HELM, the stick steers the boat instead of walking you about
	# on it — otherwise the driver spends the whole voyage trying to walk
	# off the front of their own boat. Everyone else aboard keeps their
	# legs and can move around the deck while it is under way.
	if driving():
		dir = Vector3.ZERO
	var feet := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
	in_water = Blocks.is_liquid(_chunks().get_block(feet))

	# If a block appears where we're standing (a place raced our movement, or
	# a friend walled us in), gently pop upward instead of being entombed.
	# Only once our own chunk is streamed — before that everything is
	# phantom-solid on purpose.
	var own_cpos := Vector2i(floori(position.x / 16.0), floori(position.z / 16.0))
	if _chunks().has_chunk(own_cpos) and _collides(position):
		position.y += 5.0 * delta
		velocity = Vector3.ZERO
		return

	# Double-tap jump toggles flight (tap again or land to come down).
	var jump_now := input.is_jump_pressed()
	if jump_now and not _prev_jump:
		var now := Time.get_ticks_msec()
		# The world's setting, unless this player has been given their own
		# answer — see WorldNode.fly_allowed_for.
		#
		# BEING KNOCKED OUT GRANTS IT. Going down lifts you ten blocks
		# clear of the fight and leaves you flying, so the double-tap has
		# to work while you are down — it is how you turn flight off and
		# drop back to whoever might pick you up.
		var fly_allowed: bool = downed or world.fly_allowed_for(player_id)
		# 650ms, up from 480. A double-tap is a thing a nine-year-old has
		# to do on purpose with a thumb, not a mouse, and under half a
		# second was tighter than it needed to be.
		if now - _last_jump_ms < 650 and not world.survival_active \
				and fly_allowed:
			fly_mode = not fly_mode
			if fly_mode:
				velocity.y = 3.0
				# A MOMENT'S GRACE, and it is the whole reason flight
				# "did not work a lot of the time". Touching the ground
				# cancels flight, deliberately — but a double-tap that
				# lands on the second tap switched flight on and had it
				# cancelled by the same frame's collision, so nothing
				# happened at all and it looked random. It IS random:
				# whether it worked depended on where in the jump arc the
				# second tap fell.
				_fly_grace = FLY_GRACE_SECONDS
				Sfx.play("whoosh", -6.0)
		_last_jump_ms = now
	_prev_jump = jump_now

	carry_time = maxf(0.0, carry_time - delta)
	# Leaving the water is a hop, not a breaching whale.
	if _was_in_water and not in_water and carry_time <= 0.0:
		# Modest hop out of the water — but grapple zips (carry) keep
		# their full arc.
		velocity.y = minf(velocity.y, 3.2)
	_was_in_water = in_water
	# Ladders: touching one lets you climb.
	var body_block := _chunks().get_block(Vector3i(floori(position.x),
		floori(position.y + 0.9), floori(position.z)))
	if body_block == Blocks.LADDER:
		var climb_input := input.get_move_vector().length() > 0.2 or input.is_jump_pressed()
		velocity.y = 3.4 if climb_input else -0.6
		on_floor = false
	if capture_lock > 0.0:
		capture_lock = maxf(0.0, capture_lock - delta)
	if _fly_grace > 0.0:
		_fly_grace = maxf(0.0, _fly_grace - delta)
	var speed := SWIM_SPEED if in_water else RUN_SPEED
	if input.is_sprint_pressed() and on_floor and not downed:
		speed *= 1.55
	elif input.is_sneak_pressed() and on_floor and not downed:
		speed *= 0.5  # creeping: slow and silent
	var feet_soft := _chunks().get_block(feet)
	if feet_soft >= Blocks.M_SNOW and feet_soft < Blocks.MAX_BLOCK:
		speed *= 0.45  # wading through soft snow
	if fly_mode:
		speed = OUT_FLY_SPEED if world.out_ids.has(player_id) else 7.5
	# A REVIVE HOLDS YOU BOTH STILL. Not a slow-down, a stop — for the
	# person being picked up AND the person picking them up.
	#
	# Every attempt to make this work by tuning the DOWNED player's speed
	# failed, because the requirement is contradictory: fast enough that
	# being knocked over is still worth playing, slow enough to be caught
	# by somebody moving at the same speed. It went 4.6 (uncatchable, so a
	# revive never completed) to 1.5 (too slow to reach anything, so being
	# downed meant sitting still) to 2.6, and none of them were right.
	#
	# Once the revive has actually started, neither of you needs to be
	# anywhere else, so neither of you goes anywhere, and the three seconds
	# always finish. Being downed costs you nothing until somebody is
	# actually helping you.
	if revive_locked() or capture_lock > 0.0:
		speed = 0.0
	if carry_time > 0.0:
		# Momentum rules: input only nudges while being flung.
		velocity.x = velocity.x * 0.99 + dir.x * speed * 0.1
		velocity.z = velocity.z * 0.99 + dir.z * speed * 0.1
	else:
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	if dir.length_squared() > 0.01:
		heading = dir.normalized()

	# Downed counts as out for flying: you have been knocked over, you
	# float up out of it (see `begin_knockout_rise`), and the world's
	# no-flying rules are about people who are PLAYING.
	# PER PLAYER, not the world default — see FlyRule. This asked
	# `world.client_fly`, which is only the setting for anybody nobody has
	# decided about, so a player whose flight had been switched off on
	# their own kept flying after being revived.
	var is_out: bool = world.out_ids.has(player_id) or downed
	fly_mode = FlyRule.keeps_flying(fly_mode, world.fly_allowed_for(player_id),
		world.survival_active, is_out)
	if world != null and world.match_phase == "SETUP":
		dropping = true
	# KNOCKED OUT: drift up out of the fight, Tom-and-Jerry fashion.
	#
	# Its own branch, first, and not a special case buried inside flying.
	# It used to be the third option inside `if fly_mode`, below jump and
	# descend — so any input at all cancelled it, a menu open meant
	# _local_move never ran, and the line below this one threw the whole
	# rise away the instant fly_mode was false for a frame. What a player
	# saw was a jump, not a drift.
	#
	# Constant speed, not a lerp toward one: ten blocks over three seconds
	# is the promise, and a ramp makes it nine and a bit.
	if _knockout_rise > 0.0:
		_knockout_rise = maxf(0.0, _knockout_rise - delta)
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = KNOCKOUT_RISE_BLOCKS / KNOCKOUT_RISE_SECONDS
		on_floor = false
		anim = Anim.FLY
	elif _lift_to < INF and position.y < _lift_to:
		# Still climbing out. Nothing else to decide while this runs: you
		# are out of the game and on your way to the seats.
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = SPECTATOR_LIFT_SPEED
		on_floor = false
		anim = Anim.FLY
		if position.y >= _lift_to - 0.5:
			# Arrived. Hand the controls back — a spectator can fly about
			# and follow whoever is still in it.
			_lift_to = INF
			fly_mode = true
	elif fly_mode:
		var vert := 0.0
		if jump_now:
			vert = 5.5
		elif input.is_descend_pressed():
			vert = -5.5
		velocity.y = lerpf(velocity.y, vert, minf(1.0, delta * 8.0))
	elif in_water:
		if carry_time > 0.0:
			# Grapple zips still yank you out of the water.
			velocity.y -= GRAVITY * 0.2 * delta
		else:
			# Real swimming: hold jump to rise, Shift to dive, gentle sink
			# otherwise — dive down, explore, place blocks and build up.
			var swim := -0.5
			if input.is_jump_pressed():
				swim = 3.2
			elif input.is_sprint_pressed() or input.is_descend_pressed():
				swim = -3.4
			velocity.y = lerpf(velocity.y, swim, minf(1.0, delta * 5.0))
	elif input.is_lift_pressed():
		# Held: rise. Released: this branch stops running and the plain
		# gravity below takes over, so you drop rather than hover.
		velocity.y = lerpf(velocity.y, LIFT_SPEED, minf(1.0, delta * 10.0))
		on_floor = false
		anim = Anim.FLY
	elif held().kind == "weapon" and int(held().id) == 11 and velocity.y < 0.5 and not on_floor:
		# Wings held: glide. Gentle fall, big reach — and no shooting hand.
		velocity.y = maxf(velocity.y - GRAVITY * delta * 0.12, -1.6)
		velocity.x *= 1.5
		velocity.z *= 1.5
		anim = Anim.FLY
	else:
		velocity.y -= GRAVITY * delta
		if jump_now and on_floor:
			velocity.y = JUMP_VELOCITY

	# Axis-separated sweep against the voxel grid.
	var next := position
	var blocked_h := false
	if dropping:
		# Everyone glides down at the SAME gentle -3 until touching down —
		# enforced after every glide/wings branch so nothing overrides it.
		if on_floor or in_water:
			dropping = false
		else:
			velocity.y = -3.0
	if grapple_time > 0.0 and not _grapple_path.is_empty():
		# Guided zip along waypoints (off the face, over the edge, onto
		# the top) at constant speed, hard stop at the final point.
		grapple_time -= delta
		var waypoint: Vector3 = _grapple_path[0]
		var to_hook := waypoint - position
		var last := _grapple_path.size() == 1
		if grapple_time <= 0.0:
			if last and to_hook.length() < 2.5:
				position = waypoint
			velocity = Vector3.ZERO
			grapple_time = 0.0
			carry_time = 0.0
			_grapple_path.clear()
		elif to_hook.length() < (1.0 if last else 0.8):
			if last:
				position = waypoint
				velocity = Vector3.ZERO
				grapple_time = 0.0
				carry_time = 0.0
				_grapple_path.clear()
			else:
				_grapple_path.pop_front()
		else:
			velocity = to_hook.normalized() * GRAPPLE_ZIP
			_reel_accum += delta
			if _reel_accum > 0.11:
				_reel_accum = 0.0
				# Reeling whirr: rapid quiet clicks while being pulled.
				Sfx.play("click", -16.0, randf_range(1.5, 1.8))
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var step: float = velocity.dot(axis) * delta
		if absf(step) < 0.0001:
			continue
		var attempt := next + axis * step
		if _collides(attempt):
			blocked_h = true
		else:
			next = attempt
	# The world edge. The slab is SQUARE, so clamp each axis on its own —
	# which is also what makes you SLIDE along the wall when you walk into
	# it at an angle, instead of stopping dead in the corner.
	#
	# This used to be a CIRCLE of world.world_radius, a fixed 250 or 400
	# whatever the map's real size. On any smaller world you walked
	# straight off the terrain, and the server then put you back at the
	# spawn for being outside the map.
	var half: float = world.world_half()
	next.x = clampf(next.x, -half, half)
	next.z = clampf(next.z, -half, half)
	# Kid-friendly auto-hop: walking into a single block steps you up it —
	# and swimming into a bank hops you out of the water.
	var pushing := dir.length_squared() > 0.01
	var room_up := false
	if blocked_h and pushing:
		var up_attempt := next + Vector3(velocity.x * delta, STEP_UP_PROBE,
			velocity.z * delta)
		room_up = not _collides(up_attempt) \
			and not _collides(next + Vector3(0, STEP_UP_PROBE, 0))
	match ClimbRule.decide(blocked_h, pushing, room_up, on_floor, in_water,
			_climbing, downed, fly_mode):
		ClimbRule.STEP_UP:
			# A KERB IS A HOP; THE TOP OF A CLIMB IS A MANTLE. Stepping up
			# off the ground wants a proper little jump, and 7.2 against
			# gravity 22 is 1.18 blocks, which clears a one-block step.
			# Finishing a climb wants to be carried over the lip instead
			# of thrown at it — see CLIMB_TOP_LIFT.
			if _climbing:
				_top_out = CLIMB_TOP_SECONDS
			else:
				velocity.y = 7.2
			_climbing = false
		ClimbRule.CLIMB:
			velocity.y = maxf(velocity.y, WALL_CLIMB_SPEED)
			on_floor = false
			anim = Anim.FLY
			_climbing = true
			_top_out = 0.0
		_:
			if not blocked_h:
				_climbing = false
	# THE MANTLE, held against gravity for its whole window. Setting the
	# velocity once and letting gravity eat it is precisely the bug this
	# replaces, so it is re-applied every frame until the window closes.
	if _top_out > 0.0:
		if downed or fly_mode or in_water:
			_top_out = 0.0
		else:
			_top_out = maxf(0.0, _top_out - delta)
			velocity.y = maxf(velocity.y, CLIMB_TOP_LIFT)
			on_floor = false
			anim = Anim.FLY
	var vertical := velocity.y * delta
	var v_attempt := next + Vector3(0, vertical, 0)
	var deck_y := _deck_floor(next, v_attempt)
	if _knockout_rise > 0.0 or _lift_to < INF:
		# Straight through the roof. Somebody knocked out inside their own
		# fort would otherwise be pinned against its ceiling for the whole
		# three seconds, which is the opposite of a graceful exit — and
		# they are already invisible to everyone still playing.
		next = v_attempt
		on_floor = false
	elif deck_y < INF and velocity.y <= 0.0:
		# A DECK IS A FLOOR. It is not made of blocks, so nothing in the
		# voxel sweep above can see it — without this you fall through the
		# boat you are trying to get into.
		next = Vector3(v_attempt.x, deck_y, v_attempt.z)
		velocity.y = 0.0
		on_floor = true
		if _fly_grace <= 0.0:
			fly_mode = false
	elif _collides(v_attempt):
		var impact := velocity.y
		if velocity.y < 0.0:
			if not on_floor and velocity.y < -8.0:
				Sfx.play("land", -8.0)
			on_floor = true
			if _fly_grace <= 0.0:
				fly_mode = false  # touching down ends flight, like Minecraft
			# Land exactly on top of the block we hit (unless we're inside
			# not-yet-streamed terrain, where we just hold position).
			var landed := next
			landed.y = floorf(v_attempt.y) + 1.001
			if landed.y <= next.y and not _collides(landed):
				next = landed
		velocity.y = 0.0
		# BOUNCY BLOCKS GIVE YOU MORE BACK THAN YOU BROUGHT. Each bounce
		# is one block higher than the last: drop in from five and you
		# come up to six, then seven, then eight, until you top out at
		# BOUNCE_CEILING_BLOCKS.
		#
		# It was 85% of the impact SPEED, which is 72% of the height —
		# every bounce smaller than the one before, so a trampoline was
		# something you died down onto rather than something you played
		# with. Worked in heights rather than speeds because heights are
		# what the rule is about and what a child can see: v = sqrt(2gh)
		# both ways round.
		#
		# It settles rather than running away: once a bounce reaches the
		# ceiling, the fall back from it arrives with exactly the energy
		# for that same height, so it stays there.
		if impact < -3.0:
			var under := Vector3i(floori(next.x), floori(next.y) - 1, floori(next.z))
			if _chunks().get_block(under) == Blocks.BOUNCY:
				var fell := (impact * impact) / (2.0 * GRAVITY)
				var rise := minf(fell + BOUNCE_GAIN_BLOCKS, BOUNCE_CEILING_BLOCKS)
				velocity.y = sqrt(2.0 * GRAVITY * rise)
				on_floor = false
				Sfx.play("boing")
	else:
		next = v_attempt
		on_floor = false
	position = next
	_ride(delta)
	if fp_mode:
		heading = Vector3(-sin(look_yaw), 0, -cos(look_yaw))
		rotation.y = look_yaw
	else:
		rotation.y = lerp_angle(rotation.y, atan2(-heading.x, -heading.z), minf(1.0, delta * 12.0))
	_check_floor_machines(delta)

	if fly_mode:
		anim = Anim.FLY
	elif in_water:
		anim = Anim.SWIM
	elif not on_floor:
		anim = Anim.AIR
	elif input.is_sneak_pressed() and not downed:
		anim = Anim.SNEAK
	elif dir.length_squared() > 0.01:
		anim = Anim.WALK
	else:
		anim = Anim.IDLE

## Blocks that do something when stood on: launch pads, music blocks and
## warp stones (teleport to the nearest other warp stone).
func _check_floor_machines(delta: float) -> void:
	_warp_cooldown = maxf(0.0, _warp_cooldown - delta)
	var below := Vector3i(floori(position.x), floori(position.y) - 1, floori(position.z))
	var block := _chunks().get_block(below)
	if block != Blocks.LAUNCHER:
		_launch_latched = false
	if block != Blocks.NOTE:
		_last_note_cell = NO_TARGET
	if not on_floor:
		return
	match block:
		Blocks.LAUNCHER:
			if not _launch_latched:
				_launch_latched = true
				velocity.y = 17.0
				on_floor = false
				Sfx.play("whoosh")
		Blocks.NOTE:
			if below != _last_note_cell:
				_last_note_cell = below
				var semitone := posmod(below.y * 3 + below.x + below.z, 13)
				Sfx.play("note", -2.0, pow(2.0, semitone / 12.0))
		Blocks.TELEPORT:
			if _warp_cooldown <= 0.0:
				var target: Vector3 = _chunks().nearest_teleporter(Vector3(below))
				if target != Vector3.INF:
					world.fx.burst(below, Blocks.color_of(Blocks.TELEPORT))
					position = target + Vector3(0.5, 1.01, 0.5)
					velocity = Vector3.ZERO
					_warp_cooldown = 3.0
					world.fx.burst(Vector3i(target), Blocks.color_of(Blocks.TELEPORT))
					Sfx.play("warp")

# ------------------------------------------------------------------
# Local actions: dig / place / hotbar / leave
# ------------------------------------------------------------------

## Where this player's camera is actually pointing (orbit rig), as a
## world-space direction.
func camera_look_dir() -> Vector3:
	if fp_mode:
		return look_dir()
	return Vector3(-sin(camera_yaw) * cos(camera_pitch), -sin(camera_pitch),
		-cos(camera_yaw) * cos(camera_pitch)).normalized()

## In the fight, and able to dig, build and shoot? Downed players are
## waiting to be picked up and eliminated players are spectating — neither
## should be able to touch the world, and eliminated players in
## particular were still shooting at everyone from the sky.
func can_act() -> bool:
	if downed:
		return false
	if world != null and world.out_ids.has(player_id):
		return false
	return true

func _local_actions(delta: float) -> void:
	if not can_act():
		return
	_edit_cooldown = maxf(0.0, _edit_cooldown - delta)
	var cycle := input.cycle_direction()
	if cycle != 0 and not _cycle_latch:
		selected_slot = posmod(selected_slot + cycle, 8)
		Sfx.play("tick", -10.0)
	_cycle_latch = cycle != 0

	var dig_target: Vector3i
	var place_target: Vector3i
	if fp_mode:
		var targets := _find_fp_targets()
		dig_target = targets[0]
		place_target = targets[1]
	else:
		dig_target = _find_dig_target()
		place_target = _find_place_target()
	if _highlight != null and held().kind == "weapon":
		_highlight.visible = false
	elif _highlight != null:
		var show := dig_target if input.is_dig_pressed() or not input.is_place_pressed() else place_target
		if input.is_place_pressed():
			show = place_target
		if show != Vector3i(0, -99, 0):
			_highlight.visible = true
			_highlight.global_position = Vector3(show) + Vector3(0.5, 0.5, 0.5)
		else:
			_highlight.visible = false

	if not can_act():
		return  # down or out: no digging, placing or shooting
	var pick := input.slot_pick()
	if pick != _prev_slot_pick and pick >= 0:
		if pick < 8:
			selected_slot = pick
		else:
			selected_slot = posmod(selected_slot + (1 if pick == 11 else -1), 8)
		Sfx.play("tick", -10.0)
	_prev_slot_pick = pick
	if _edit_cooldown > 0.0:
		return
	# In first person the keyboard player can also mouse-click: left digs,
	# right places (mouse is captured for looking anyway).
	var mouse_ok: bool = fp_mode and input.kind == InputSlot.Kind.KEYBOARD_WASD \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var wants_dig: bool = input.is_dig_pressed() \
		or (mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var wants_place: bool = input.is_place_pressed() \
		or (mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if wants_dig:
		# Petting beats digging when a critter is close.
		var critter: int = world.critter_view.nearest_id(position, 1.9)
		if critter >= 0:
			world.sv_pet.rpc_id(1, slot, critter)
			_edit_cooldown = EDIT_REPEAT * 2.0
			return
		if dig_target != Vector3i(0, -99, 0):
			world.send_edit(slot, dig_target, Blocks.AIR)
			_edit_cooldown = EDIT_REPEAT
	elif wants_place:
		var item := held()
		if item.kind == "empty":
			return
		if item.kind == "weapon":
			if int(item.id) == 11:
				return  # Wings work by holding them, not clicking
			if int(item.id) == 13:
				_sword_swing()
				_edit_cooldown = 0.4
				return
			world.orbs.shoot_local(self, int(item.id))
			_edit_cooldown = float(Weapons.spec(int(item.id)).cooldown)
		elif place_target != Vector3i(0, -99, 0):
			if item.kind == "vehicle":
				# Where you are AIMING, not where you are standing. The
				# server settles it onto the water or the ground from
				# there — see VehicleDirector.settle.
				world.sv_vehicle_place.rpc_id(1, slot, place_target, int(item.id))
				_edit_cooldown = 1.0
			elif item.kind == "structure":
				var facing := 0
				if absf(heading.x) > absf(heading.z):
					facing = 1 if heading.x > 0 else 3
				elif heading.z > 0:
					facing = 2
				world.sv_structure.rpc_id(1, slot, place_target, int(item.id),
					randi() % 1000, facing)
				_edit_cooldown = 1.0
			else:
				world.send_edit(slot, place_target,
					Blocks.orient_stairs(selected_block(), heading))
				_edit_cooldown = EDIT_REPEAT

## Sword: a close swing that bonks enemies and chops soft blocks.
var swing_time := 0.0

func _sword_swing() -> void:
	swing_time = 0.25
	Sfx.play("whoosh", -8.0, 1.4)
	var hit_someone := false
	# Swing direction: where you LOOK, not where you last walked — and very
	# close targets count regardless of angle.
	var face3: Vector3 = look_dir() if fp_mode else heading
	var face := Vector2(face3.x, face3.z)
	face = face.normalized() if face.length() > 0.05 else Vector2(0, -1).rotated(camera_yaw)
	for child in world.players.get_children():
		if child is Player and child.player_id != player_id:
			var to_other: Vector3 = child.position - position
			var flat_to := Vector2(to_other.x, to_other.z)
			# THREE BLOCKS, AND THE WHOLE FORWARD HALF. Reach comes down
			# from 4.2 because the swing kills outright now and the range
			# is the only thing holding that in check; the arc opens from
			# a 60-degree cone to a full 180 because a lethal swing that
			# misses somebody standing beside you is just frustrating.
			if to_other.length() < WorldNode.SWORD_REACH \
					and (flat_to.length() < 1.2 or flat_to.normalized().dot(face) > 0.0):
				world.sv_sword_hit.rpc_id(1, slot, child.player_id, child.position)
				hit_someone = true
	var monster: int = world.monster_view.nearest_to(position + heading * 2.0, 2.2)
	if monster >= 0:
		world.sv_zap.rpc_id(1, slot, monster)
		world.monster_view.hit(monster, false)
		hit_someone = true
	if not hit_someone:
		var target := _find_dig_target()
		if target != NO_TARGET and Blocks.hardness(world.chunks.get_block(target)) <= 1:
			world.send_edit(slot, target, Blocks.AIR)

func _front_cell(dy: int) -> Vector3i:
	var front := position + heading * 0.95
	return Vector3i(floori(front.x), floori(position.y + 0.3) + dy, floori(front.z))

const NO_TARGET := Vector3i(0, -99, 0)

## First person: march a ray from the eyes along the look direction. The
## first breakable block is the dig target; the last open cell before it is
## the place target — so you can dig straight up out of a hole, or look down
## and build under your feet mid-jump.
func _find_fp_targets() -> Array:
	var chunks := _chunks()
	var eye := position + Vector3(0, EYE_HEIGHT, 0)
	var dir := look_dir()
	var last_open := NO_TARGET
	var last_cell := Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))
	var t := 0.3
	while t < 6.0:
		var sample := eye + dir * t
		var cell := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		if cell != last_cell:
			last_cell = cell
			var block := chunks.get_block(cell)
			if block != Blocks.AIR and not Blocks.is_liquid(block) and not Blocks.is_cross(block):
				if Blocks.is_breakable(block):
					return [cell, last_open]
				return [NO_TARGET, last_open]
			if Blocks.is_cross(block) and Blocks.is_breakable(block):
				# A plant cell digs the plant AND doubles as the place spot
				# — you build straight through foliage, Minecraft style.
				return [cell, cell if not _cell_overlaps_self(cell) else last_open]
			if not _cell_overlaps_self(cell) and _has_solid_neighbor(cell):
				last_open = cell
		t += 0.12
	return [NO_TARGET, last_open]

## Minecraft rule: blocks need something to hang off.
func _has_solid_neighbor(cell: Vector3i) -> bool:
	for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
			Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if Blocks.is_solid(_chunks().get_block(cell + off)):
			return true
	return false

func _cell_overlaps_self(cell: Vector3i) -> bool:
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var delta := center - (position + Vector3(0, HEIGHT * 0.5, 0))
	return absf(delta.x) < HALF_WIDTH + 0.5 and absf(delta.z) < HALF_WIDTH + 0.5 \
		and delta.y > -HEIGHT * 0.5 - 0.5 and delta.y < HEIGHT * 0.5 + 0.5

func _find_dig_target() -> Vector3i:
	var chunks := _chunks()
	# The flower you're standing in comes first.
	var own := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
	if Blocks.is_cross(chunks.get_block(own)):
		return own
	for dy in [0, 1, -1]:
		var cell := _front_cell(dy)
		var block := chunks.get_block(cell)
		if block != Blocks.AIR and not Blocks.is_liquid(block) and Blocks.is_breakable(block):
			return cell
	# Nothing ahead: dig straight down (staircase into the hill).
	var below := own + Vector3i(0, -1, 0)
	var under := chunks.get_block(below)
	if Blocks.is_breakable(under) and not Blocks.is_liquid(under):
		return below
	return NO_TARGET

func _find_place_target() -> Vector3i:
	var chunks := _chunks()
	var candidates := [_front_cell(0), _front_cell(1), _front_cell(-1)]
	for cell: Vector3i in candidates:
		var block := chunks.get_block(cell)
		if block == Blocks.AIR or Blocks.is_cross(block) or Blocks.is_liquid(block):
			# Never place a block inside yourself.
			var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
			var delta := center - (position + Vector3(0, HEIGHT * 0.5, 0))
			if absf(delta.x) < HALF_WIDTH + 0.5 and absf(delta.z) < HALF_WIDTH + 0.5 \
					and delta.y > -HEIGHT * 0.5 - 0.5 and delta.y < HEIGHT * 0.5 + 0.5:
				continue
			if not _has_solid_neighbor(cell):
				continue
			return cell
	return NO_TARGET

func _send_state(delta: float) -> void:
	_send_accum += delta
	if _send_accum < 1.0 / SEND_HZ:
		return
	_send_accum = 0.0
	world.send_pos(slot, position, rotation.y,
		anim + (8 if swing_time > 0.0 else 0) + _held_code() * 16)
	if OS.get_environment("WORLD_DEBUG") == "1":
		_debug_ticks += 1
		if _debug_ticks % 24 == 0:
			var feet := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
			print("DBG %s pos=%v floor=%s water=%s feet_block=%d" % [
				player_id, position, on_floor, in_water, _chunks().get_block(feet)])

# ------------------------------------------------------------------
# Shared animation
# ------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _avatar != null:
		_animate_kenney(delta)

## Kenney Blocky Characters animate themselves — pick the right clip.
func _animate_kenney(_delta: float) -> void:
	var ap := _avatar.get_meta("ap") as AnimationPlayer
	if not is_instance_valid(ap):
		return
	var want := "idle"
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	# No "die" clip any more: a downed player gets up and walks about
	# looking for a team-mate, so they animate like anyone else. The
	# ghost shimmer, and being invisible to the other side, is what says
	# they are down.
	if swing_time > 0.0:
		want = "attack-melee-right"
	elif anim == Anim.SNEAK:
		want = "sit"
	elif ground_speed > 5.2:
		want = "sprint"
	elif ground_speed > 0.6 or anim == Anim.WALK:
		want = "walk"
	elif held().kind == "weapon":
		want = "holding-right"
	if ap.current_animation != want:
		ap.play(want, 0.18)


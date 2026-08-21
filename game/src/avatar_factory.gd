class_name AvatarFactory
## Builds a player's character out of the Kenney Blocky Characters pack.
##
## All 18 characters in that pack are the SAME six meshes — head, torso,
## two arms, two legs — in the same hierarchy, driven by the same 27
## animation clips. Only the texture differs. That is what makes them
## mixable: take the head and arms from one and the torso and legs from
## another and the result animates exactly like either parent did, because
## the AnimationPlayer addresses nodes by name and the names never move.
##
## A style is {"who": <letter>, "fit": <letter>}:
##   who — head and arms: the person, their face and skin
##   fit — torso and legs: what they are wearing
##
## Skin is never split across one body, so all 18x18 = 324 combinations
## read as a deliberate character rather than a glitch. `fit` defaults to
## `who`, which is the plain pack character — so a style saved before
## outfits existed comes back looking exactly as it did.

## Kenney Blocky Characters (CC0): 18 ready-made kids to pick from.
const KENNEY_CHARS: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h",
	"i", "j", "k", "l", "m", "n", "o", "p", "q", "r"]

## The two halves of a character, by the node names the .glb ships with.
## player.gd finds the held item's parent by "arm-right", and the
## AnimationPlayer's tracks name every one of these, so they are a wire
## format of sorts: renaming one silently stops both.
const SKIN_PARTS: Array[String] = ["head", "arm-left", "arm-right"]
const FIT_PARTS: Array[String] = ["torso", "leg-left", "leg-right"]

## What a HUD swatch may cycle. `sv_cycle_style` checks against this.
const ATTRS: Array[String] = ["who", "fit"]

## Clips that should loop. Everything else in the pack plays once.
const LOOPING_ANIMS: Array[String] = ["idle", "walk", "sprint",
	"holding-right", "sit"]

## who -> {part name -> Mesh}. Built on first use by instantiating the
## character once and lifting its six meshes out; every avatar after that
## is six assignments and no scene instantiation.
static var _parts_cache: Dictionary = {}

static func characters() -> Array:
	return KENNEY_CHARS.duplicate()

static func outfits() -> Array:
	return KENNEY_CHARS.duplicate()

static func model_of(who: String) -> String:
	return "res://assets/models/chars/character-%s.glb" % who

static func portrait_of(who: String) -> String:
	return "res://assets/ui/chars/character-%s.png" % who

static func random_style() -> Dictionary:
	return {"who": KENNEY_CHARS[randi() % KENNEY_CHARS.size()],
		"fit": KENNEY_CHARS[randi() % KENNEY_CHARS.size()]}

## Coerces anything — a fresh style, one saved by an older build, or junk
## off the wire — into {"who", "fit"} naming two real characters.
##
## Styles from before the Kenney pack described a hand-built figure
## ({"body": 3, "shirt": 7, ...}) and styles from before the Little People
## were retired named "p0".."p29". Neither can be drawn any more, so both
## are hashed to a stable pick: a returning player keeps ONE consistent
## look rather than being reshuffled on every join.
static func normalize_style(style) -> Dictionary:
	if not (style is Dictionary):
		return random_style()
	var who := _known(str(style.get("who", "")), style)
	# An outfit is optional, and its absence means "wear your own" — that
	# is what makes every pre-outfit style still render as its pack
	# character rather than a random mix.
	var fit := str(style.get("fit", ""))
	return {"who": who, "fit": fit if fit in KENNEY_CHARS else who}

## A real character letter, or a stable one derived from whatever we were
## given, so the same input always maps to the same character.
static func _known(who: String, style: Dictionary) -> String:
	if who in KENNEY_CHARS:
		return who
	var key := who if not who.is_empty() else str(style)
	return KENNEY_CHARS[absi(key.hash()) % KENNEY_CHARS.size()]

## The six meshes of one pack character, keyed by node name.
static func _parts_of(who: String) -> Dictionary:
	if _parts_cache.has(who):
		return _parts_cache[who]
	var parts: Dictionary = {}
	var scene: PackedScene = load(model_of(who)) as PackedScene \
		if ResourceLoader.exists(model_of(who)) else null
	if scene != null:
		var probe: Node3D = scene.instantiate()
		for part: String in SKIN_PARTS + FIT_PARTS:
			var node := probe.find_child(part, true, false) as MeshInstance3D
			if node != null and node.mesh != null:
				parts[part] = node.mesh
		probe.free()
	_parts_cache[who] = parts
	return parts

static func build_character(style: Dictionary) -> Node3D:
	style = normalize_style(style)
	var who := str(style.who)
	var fit := str(style.fit)
	var scene: PackedScene = load(model_of(who)) as PackedScene \
		if ResourceLoader.exists(model_of(who)) else null
	if scene == null:
		push_error("Character model missing: %s" % model_of(who))
		return _placeholder()
	var inst: Node3D = scene.instantiate()
	# The pack models face +Z and stand about twice our height.
	inst.scale = Vector3.ONE * 0.52
	inst.rotation_degrees = Vector3(0, 180, 0)
	if fit != who:
		var worn := _parts_of(fit)
		for part: String in FIT_PARTS:
			var node := inst.find_child(part, true, false) as MeshInstance3D
			if node != null and worn.has(part):
				node.mesh = worn[part]
	var root := Node3D.new()
	root.add_child(inst)
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		for anim_name: String in LOOPING_ANIMS:
			if ap.has_animation(anim_name):
				ap.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		# "die" must NOT loop. Looping made a downed player fall over, snap
		# upright and fall over again forever — the thing the kids ended up
		# watching instead of the game. Once through, then hold the last
		# frame: down and still.
		if ap.has_animation("die"):
			ap.get_animation("die").loop_mode = Animation.LOOP_NONE
		ap.play("idle")
		root.set_meta("ap", ap)
	root.set_meta("style", str(style))
	return root

## Only reachable if a character model is missing from the build, which
## the Dockerfile's boot check would have caught. It exists so that a
## broken asset is a headless grey figure and a logged error rather than a
## null avatar and a crash in the middle of a game.
static func _placeholder() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8d8d96")
	for spec: Array in [[Vector3(0.5, 0.6, 0.3), 0.35], [Vector3(0.4, 0.4, 0.4), 0.9]]:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = spec[0]
		box.mesh = mesh
		box.material_override = mat
		box.position = Vector3(0, spec[1], 0)
		root.add_child(box)
	return root

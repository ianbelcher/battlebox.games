class_name TitleBackdrop
extends Control
## WHAT IS BEHIND THE FRONT PAGE.
##
## It was a two-stop vertical gradient, and a flat wash is the single
## clearest tell that a screen was laid out rather than designed: there is
## nothing to look at, so every pixel of attention lands on the form
## fields. A title screen is the one screen in a game that is allowed to
## be a picture.
##
## So this draws one, out of the only material this game has:
##
##   sky        a low warm lift near the horizon over near-black
##   ember      one glow, sitting where the Play button sits, so the
##              brightest thing on the screen and the thing you are meant
##              to press are the same place
##   lattice    a faint block grid, fading out as it rises — the world
##              this game is made of, suggested rather than drawn
##   horizon    two ranks of blocky silhouette, the far one lighter than
##              the near one, which is the whole of the depth cue
##   blocks     a dozen real voxel cubes drifting up, slowly, at three
##              speeds
##
## IT IS ALL CHEAP, and it has to be: the browser build meshes chunks on
## the CPU and the screenshot harness runs on software rendering at about
## a frame a second. Nothing here is per-pixel, nothing allocates in
## _process, and the two gradients are textures built once at boot.
##
## NOTHING HERE IS RANDOM AT DRAW TIME. The skyline is generated once from
## a fixed seed into an array; generating it inside _draw would reshuffle
## the mountains on every repaint, which is a horrible thing to watch and
## exactly the kind of bug that only shows up on a resize.

## How far up the screen the skyline reaches, as a fraction of height.
const HORIZON := 0.24
## Blocks across, in each rank. Enough to read as a skyline, few enough
## that the whole thing is a few dozen draw_rect calls.
const COLUMNS := 34
## Drifting cubes. A dozen is a sky with something in it; thirty is snow.
const DRIFTERS := 12
const DRIFT_SEED := 4114

var _sky: GradientTexture2D
var _glow: GradientTexture2D
var _vignette: GradientTexture2D
## Column heights, 0..1 of the horizon band, far rank then near rank.
var _far: PackedFloat32Array = []
var _near: PackedFloat32Array = []
var _cubes: Array[Control] = []
var _time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A backdrop that swallows clicks is a front page whose buttons do
	# nothing, and it looks exactly like a screen that has frozen.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky = _linear([UiTheme.VOID, Color("121116"), Color("17151c")],
		[0.0, 0.62, 1.0])
	# FAINT. The first pass ran this at 0.20 over a glow wider than the
	# window, and the whole page came out the colour of a fire: an accent
	# that covers everything has stopped being an accent.
	_glow = _radial([Color(1.0, 0.373, 0.18, 0.10), Color(1.0, 0.373, 0.18, 0.0)],
		[0.0, 1.0])
	_vignette = _radial([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55)], [0.55, 1.0])
	_build_skyline()
	_build_drifters()

func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DRIFT_SEED
	_far.resize(COLUMNS)
	_near.resize(COLUMNS)
	# The far rank is low and even; the near one is taller and rougher.
	# That difference is what stops the two reading as one wall in two
	# colours — a skyline is only depth if the ranks disagree.
	for i in COLUMNS:
		_far[i] = 0.30 + rng.randf() * 0.30
		_near[i] = 0.45 + rng.randf() * 0.55
	# A gap somebody could walk through, so the near rank is a place
	# rather than a bar chart.
	var gap := 4 + (rng.randi() % (COLUMNS - 10))
	for i in range(gap, gap + 3):
		_near[i] = 0.16 + rng.randf() * 0.08

## Real voxel cubes, the same ones the block picker draws. Actual game
## blocks rather than squares: this is a voxel game's title screen, and
## the material it is made of is the only decoration it needs.
func _build_drifters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = DRIFT_SEED + 1
	var kinds := [Blocks.GRASS, Blocks.BRICK, Blocks.WOOL_RED, Blocks.LEAVES,
		Blocks.SANDSTONE, Blocks.GOLD, Blocks.ICE, Blocks.PUMPKIN]
	for i in DRIFTERS:
		var cube := BlockIcon.new(kinds[i % kinds.size()])
		var side := 26.0 + rng.randf() * 42.0
		cube.size = Vector2(side, side)
		cube.pivot_offset = cube.size * 0.5
		cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Faint. These are scenery behind a page of text, and a bright
		# cube behind a word is a word nobody can read.
		cube.modulate = Color(1, 1, 1, 0.10 + rng.randf() * 0.13)
		cube.set_meta("x", rng.randf())
		cube.set_meta("y", rng.randf())
		cube.set_meta("rise", 0.008 + rng.randf() * 0.020)
		cube.set_meta("spin", (rng.randf() - 0.5) * 0.35)
		add_child(cube)
		_cubes.append(cube)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	var box := size
	for cube: Control in _cubes:
		var y := float(cube.get_meta("y")) - float(cube.get_meta("rise")) * delta
		# Off the top, back on at the bottom. Wrapped rather than reset to
		# a fixed point, so nothing pulses in time with anything else.
		if y < -0.15:
			y += 1.3
		cube.set_meta("y", y)
		cube.position = Vector2(float(cube.get_meta("x")) * box.x,
			y * box.y) - cube.size * 0.5
		cube.rotation = _time * float(cube.get_meta("spin"))

func _draw() -> void:
	var box := size
	if box.x < 2.0 or box.y < 2.0:
		return
	draw_texture_rect(_sky, Rect2(Vector2.ZERO, box), false)
	# THE GLOW SITS WHERE THE PLAY BUTTON SITS. Low and to the left, which
	# is where the eye is being sent anyway — so the brightest place on
	# the screen and the thing to press are the same place, and nothing
	# had to say so.
	var glow := box.x * 0.85
	draw_texture_rect(_glow,
		Rect2(Vector2(box.x * 0.28 - glow * 0.5, box.y * 0.72 - glow * 0.5),
			Vector2(glow, glow)), false)
	_draw_lattice(box)
	_draw_skyline(box)
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, box), false)

## A block grid lying flat, fading out as it goes up. Drawn as plain
## lines with a per-line alpha rather than masked, because a mask needs a
## second pass and this is two loops.
func _draw_lattice(box: Vector2) -> void:
	var top := box.y * (1.0 - HORIZON) - box.y * 0.10
	var step := maxf(28.0, box.x / 30.0)
	var tint := Color(1, 1, 1, 0.05)
	var y := box.y
	while y > top:
		var fade: float = clampf((box.y - y) / maxf(1.0, box.y - top), 0.0, 1.0)
		draw_line(Vector2(0, y), Vector2(box.x, y),
			Color(tint.r, tint.g, tint.b, tint.a * (1.0 - fade)), 1.0)
		y -= step
	var x := 0.0
	while x <= box.x:
		draw_line(Vector2(x, box.y), Vector2(x, top),
			Color(tint.r, tint.g, tint.b, tint.a * 0.55), 1.0)
		x += step

## Two ranks of blocky silhouette. The far one is lighter than the sky
## behind it and the near one is darker than both, which is the whole of
## the depth: nothing is perspective-corrected and nothing needs to be.
func _draw_skyline(box: Vector2) -> void:
	var band := box.y * HORIZON
	var base := box.y
	var width := box.x / float(COLUMNS)
	for i in COLUMNS:
		var h: float = _far[i] * band
		draw_rect(Rect2(i * width, base - h - band * 0.16, width + 1.0,
			h + band * 0.16 + 2.0), Color("17151c"), true)
	for i in COLUMNS:
		var h2: float = _near[i] * band * 0.82
		draw_rect(Rect2(i * width, base - h2, width + 1.0, h2 + 2.0),
			Color("0d0c10"), true)

# ------------------------------------------------------------------
# Gradient textures, built once
# ------------------------------------------------------------------

func _gradient(colors: Array, offsets: Array) -> Gradient:
	var grad := Gradient.new()
	var packed_colors := PackedColorArray()
	var packed_offsets := PackedFloat32Array()
	for c: Color in colors:
		packed_colors.append(c)
	for o: float in offsets:
		packed_offsets.append(o)
	# ORDER MATTERS: setting colors while the old offsets array is still a
	# different length silently truncates one of them.
	grad.offsets = packed_offsets
	grad.colors = packed_colors
	return grad

func _linear(colors: Array, offsets: Array) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = _gradient(colors, offsets)
	tex.fill_from = Vector2(0, 1)
	tex.fill_to = Vector2(0, 0)
	tex.width = 4
	tex.height = 256
	return tex

func _radial(colors: Array, offsets: Array) -> GradientTexture2D:
	var tex := GradientTexture2D.new()
	tex.gradient = _gradient(colors, offsets)
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

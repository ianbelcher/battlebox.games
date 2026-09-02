class_name NeonWordmark
extends Control
## THE NAME OF THE GAME, drawn as the neon sign from the intro video.
##
## The intro ends on a Minecraft field with BATTLEBOX standing in it as a
## neon sign: a heavy connected script in glass tube, white at the core,
## magenta outside and blue within, on a scaffold. The front page then
## said "BATTLEBOX" in the same plain sans as the settings underneath it,
## so the game introduced itself twice in two different voices and the
## second one was nobody's.
##
## WHY THIS IS DRAWN AND NOT A PICTURE OF THE SIGN. Lifting it out of the
## video was the obvious route and it does not survive contact: every
## frame has the sign against a bright daylight field, so there is no key
## to pull, and the scaffold's tubes cross behind the letters. What comes
## out is a rectangle of grass with some letters in it. Drawn, it is sharp
## at any size, it costs nothing, and it can say something other than
## "BattleBox" if it ever needs to.
##
## HOW THE TUBE IS MADE. Godot draws a Label's outline OUTSIDE the glyph
## and the fill inside it, so a transparent fill with a coloured outline
## is a hollow letter — which is what a glass tube is. Stack those, widest
## first, and each narrower ring is drawn over the inside of the one
## before it: magenta, then blue, then a white core, reading outwards as
## the cross-section of a lit tube. The widest layer of all is the same
## colour at low alpha and is the glow it throws.
##
## Every layer is the same Label with the same text at the same size, so
## they cannot drift apart.

## Sorkin Type's Courgette (SIL OFL 1.1), which is the closest open face
## to the sign's letterforms: the same slant, the same single-storey `a`,
## and — the thing that matters for neon — an even stroke weight, because
## a glass tube has one thickness. See NOTICE.
const FACE := "res://assets/fonts/Courgette-Regular.ttf"

## Tube colours, read off the sign itself.
const GLOW := Color(1.0, 0.24, 0.66, 0.30)
const OUTER := Color("ff3fa8")
const INNER := Color("4fc3ff")
const CORE := Color("fff2fb")

## Ring widths as a FRACTION of the type size, widest first. Fractions
## rather than pixels because a tube is a thickness of glass: it has to
## grow with the letters, and at a fixed 26px the glow vanished the moment
## the wordmark was set big enough to be a wordmark.
const RINGS := [0.30, 0.15, 0.075, 0.032]

var _text := "BattleBox"
var _size := 64
var _scale := 1.0
var _labels: Array[Label] = []

func _init(body := "BattleBox") -> void:
	_text = body

## `size` is the cap height in DESIGN pixels; `scale` is the menu scale.
func setup(size: int, scale: float) -> NeonWordmark:
	_size = size
	_scale = scale
	return self

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := load(FACE) as Font
	var colors: Array[Color] = [GLOW, OUTER, INNER, CORE]
	for i in RINGS.size():
		var label := Label.new()
		label.text = _text
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if face != null:
			label.add_theme_font_override("font", face)
		label.add_theme_font_size_override("font_size",
			UiTheme.px(_size, _scale))
		# THE FILL IS INVISIBLE and that is the whole trick: what is left
		# is the ring Godot draws around the glyph, which is a letter made
		# of tube rather than a letter made of ink.
		label.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		label.add_theme_color_override("font_outline_color", colors[i])
		label.add_theme_constant_override("outline_size",
			UiTheme.px(float(RINGS[i]) * _size, _scale))
		add_child(label)
		_labels.append(label)
	custom_minimum_size = _measure(face)

## As wide and as tall as the type actually is, so the column above and
## below it lays out against something real rather than against a Control
## with no size.
func _measure(face: Font) -> Vector2:
	if face == null:
		return Vector2(UiTheme.px(_size * 5, _scale), UiTheme.px(_size, _scale))
	var px := UiTheme.px(_size, _scale)
	var wide := face.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	# Room for the widest ring on every side; an outline is drawn outside
	# the glyph box and would otherwise be clipped by the container.
	var ring := UiTheme.px(float(RINGS[0]) * _size, _scale)
	return Vector2(wide.x + ring * 2.0, px * 1.5 + ring)

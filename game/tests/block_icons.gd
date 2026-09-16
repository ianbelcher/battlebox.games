extends Node2D
## EVERY CHIP IN A PICKER TAB, DRAWN, as one contact sheet.
##
##   WORLD_ICON_CATEGORY=office WORLD_ICON_OUT=/tmp/office.png \
##     godot --path <game> --resolution 900x520 res://tests/block_icons.tscn
##
## BlockIcon has no textures: every chip is hand-drawn, and its `_draw`
## is a match over the block's SHAPE with a `return` after it. A shape
## with no arm of that match draws nothing at all — a blank square in the
## grid, next to a perfectly good name and a perfectly good block. The
## game runs, the picker opens, the block places, and the only thing
## wrong is the one thing a test cannot assert about: the picture.
##
## So this draws a whole tab to a PNG the way weapon_icons.gd renders the
## held models, and it is the check to run after adding blocks — the
## office fittings landed eight new shapes in one go.
##
## Needs a real window; a headless run has no renderer to draw with.

const CHIP := 76
const PAD := 10
const COLUMNS := 10

var _out := ""
var _frames := 0

func _ready() -> void:
	_out = OS.get_environment("WORLD_ICON_OUT")
	if _out.is_empty():
		_out = "/tmp/block_icons.png"
	var category := OS.get_environment("WORLD_ICON_CATEGORY")
	if category.is_empty():
		category = "office"
	var ids: Array = Blocks.picker_category(category)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", PAD)
	grid.add_theme_constant_override("v_separation", PAD)
	grid.position = Vector2(PAD, PAD)
	add_child(grid)
	for id: int in ids:
		# A plate behind each chip, so a chip that draws NOTHING reads as
		# an empty square rather than as the background.
		var plate := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13, 0.14, 0.17)
		style.set_corner_radius_all(8)
		plate.add_theme_stylebox_override("panel", style)
		plate.custom_minimum_size = Vector2(CHIP, CHIP)
		var icon := BlockIcon.new(id, "block")
		icon.custom_minimum_size = Vector2(CHIP, CHIP)
		plate.add_child(icon)
		grid.add_child(plate)
	print("block icons: %d chips in '%s'" % [ids.size(), category])

func _process(_delta: float) -> void:
	# A couple of frames so the grid has laid out and drawn.
	_frames += 1
	if _frames < 4:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out)
	print("wrote ", _out)
	get_tree().quit()

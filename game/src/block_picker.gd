class_name BlockPicker
extends PanelContainer
## Minecraft-style selection view (E / D-pad up), one per split-screen cell.
## A grid of every block plus the prefab structures, with the focused entry's
## name in big letters. Navigate with WASD / stick / D-pad, choose with
## jump/place (or click), close with E again.

var COLUMNS := 10

signal picked(entry: Dictionary)

var entries: Array = []      # {kind: "block"/"structure", id, name, color}
var focus_index := 0
var _title: Label
var _subtitle: Label
var _chips: Array = []
var _scroll: ScrollContainer
var _nav_cooldown := 0.0

var category := "blocks"

## One line under the big name saying what this whole tab is for — the
## difference between "a wall of squares" and a shop page.
const CATEGORY_BLURB := {
	"tools": "Weapons, gadgets and the blocks that do things",
	"building": "Everything you build with",
	"kits": "Whole buildings — place one and it appears",
}

func _init(p_category := "blocks") -> void:
	category = p_category
	if category == "tools":
		# Six, so the rows land where the grouping wants them: the guns,
		# then the getting-about kit, then the markers, then the special
		# blocks. Seven put the Napalm Rocket on the wrong row.
		COLUMNS = 6
	elif category == "kits":
		# 43 kits and counting — 4 columns meant endless scrolling for a
		# child. The chips stay big because fit() sizes them to the space.
		COLUMNS = 8
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.set_border_width_all(0)
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	match category:
		"tools":
			# ORDERED BY WHAT THE THING IS FOR, six to a row:
			#   fighting        sword, the three shooters, the rocket
			#   getting about   grapple, digger
			#   telling people  flare, smoke, sprayer, paint bomb
			#   and the special blocks underneath.
			# The registry's own order is the order of the hotbar and has
			# other jobs to do, so the page states its own.
			for id: int in Weapons.TOOL_PAGE_ORDER:
				var w := Weapons.spec(id)
				if w.get("hidden", false):
					continue
				entries.append({"kind": "weapon", "id": w.id, "name": w.name,
					"color": w.color})
			for block: int in Blocks.SPECIAL_BLOCKS:
				entries.append({"kind": "block", "id": block,
					"name": Blocks.display_name(block),
					"color": Blocks.color_of(block)})
		"kits":
			for i in Structures.count():
				var spec := Structures.spec(i)
				entries.append({"kind": "structure", "id": i,
					"name": spec.name, "color": spec.color})
		_:
			for block in Blocks.picker_category(category):
				entries.append({"kind": "block", "id": block,
					"name": Blocks.display_name(block), "color": Blocks.color_of(block)})

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	# What you are pointing at, in big letters, with what it is underneath.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	box.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = CATEGORY_BLURB.get(category, "")
	_subtitle.add_theme_font_size_override("font_size", 14)
	_subtitle.add_theme_color_override("font_color", UiTheme.INK_FAINT)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_subtitle)
	# Chips keep their size on small screens; the grid scrolls instead of
	# squashing everything to fit.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	# A short category (Tools has two rows) used to sit at the top of a
	# tall black void. Centring it means every tab looks composed.
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(centre)
	# Breathing room, so the selected chip's ring is never sliced off by
	# the edge of the scrolling area.
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	centre.add_child(pad)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	pad.add_child(grid)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(40, 40)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon := BlockIcon.new(int(entry.id), entry.kind)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		chip.add_child(icon)
		var index := i
		chip.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				focus_index = index
				_select()
			elif event is InputEventMouseMotion:
				if focus_index != index:
					focus_index = index
					_refresh())
		grid.add_child(chip)
		_chips.append(chip)


## Scale chips and text so the grid uses the space it's given — tiny
## quarter-screen cells and huge fullscreen windows both read well.
var _chip_px := 44.0

## In a battle you may only choose a weapon you are actually carrying.
## Empty means "anything goes" (creative, and every other tab).
var allowed_ids: Array = []

func set_allowed(ids: Array) -> void:
	allowed_ids = ids
	if visible:
		_refresh()

func _allowed(index: int) -> bool:
	if allowed_ids.is_empty():
		return true
	return int(entries[index].id) in allowed_ids

func fit(avail: Vector2) -> void:
	# Width decides the chip size (the columns must fit); running out of
	# HEIGHT just means the grid scrolls, so chips never shrink for it.
	var chip := clampf((avail.x * 0.92 - 50.0) / COLUMNS - 6.0, 44.0, 130.0)
	_chip_px = chip
	for panel: Panel in _chips:
		panel.custom_minimum_size = Vector2(chip, chip)
		for child in panel.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", int(chip * 0.55))
	_title.add_theme_font_size_override("font_size", int(clampf(chip * 0.72, 24.0, 46.0)))
	_subtitle.add_theme_font_size_override("font_size", int(clampf(chip * 0.26, 13.0, 22.0)))
	if visible:
		_refresh()

var _slot_label := 1
func set_slot_label(n: int) -> void:
	_slot_label = n
	if visible:
		_refresh()

func open(_a := 0, _b := 0) -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false

## Poll navigation/choose from this player's InputSlot; PlayerHud calls this
## every frame while open. Returns true while staying open.
func poll(input: InputSlot, delta: float) -> void:
	_nav_cooldown = maxf(0.0, _nav_cooldown - delta)
	var nav := input.get_ui_vector()
	if _nav_cooldown <= 0.0 and nav.length() > 0.5:
		# Dominant-axis only: a stick rolled toward "up" often tips
		# sideways for a frame — an ambiguous diagonal moves nothing
		# rather than dart left/right first.
		var step := Vector2i(0, 0)
		if absf(nav.x) > absf(nav.y) * 1.35:
			step.x = 1 if nav.x > 0 else -1
		elif absf(nav.y) > absf(nav.x) * 1.35:
			step.y = 1 if nav.y > 0 else -1
		if step == Vector2i(0, 0):
			return
		var next := focus_index + step.x + step.y * COLUMNS
		if step.y == 1 and next >= entries.size() \
				and focus_index / COLUMNS < (entries.size() - 1) / COLUMNS:
			next = entries.size() - 1  # down into a shorter last row
		if next >= 0 and next < entries.size():
			focus_index = next
			_nav_cooldown = 0.16
			Sfx.play("tick", -14.0)
			_refresh()
	if input.is_primary_pressed() or input.is_place_pressed():
		_select()

func _select() -> void:
	if not _allowed(focus_index):
		# Not yours: a flat click rather than the pick sound, so it is
		# obvious nothing happened and why.
		Sfx.play("tick", -18.0)
		return
	Sfx.play("pop", -4.0)
	picked.emit(entries[focus_index])

func _refresh() -> void:
	if entries.is_empty():
		return
	_title.text = str(entries[focus_index].name)
	# Deferred: fit() resizes every chip in the same frame the menu opens,
	# so scrolling now would aim at last frame's layout and leave the
	# selected chip sliced in half by the top edge.
	if _scroll != null and focus_index < _chips.size():
		if focus_index < COLUMNS:
			# Top row: scroll all the way up rather than just far enough to
			# expose the chip, which parks its ring flush against the edge.
			_scroll.set_deferred("scroll_vertical", 0)
		else:
			_scroll.ensure_control_visible.call_deferred(_chips[focus_index])
	for i in _chips.size():
		var chip: Panel = _chips[i]
		# One chip look, two states. The ring is drawn INSIDE the chip so
		# the selected one never grows and never shunts its neighbours.
		var style := StyleBoxFlat.new()
		style.corner_detail = 8
		if i == focus_index:
			style.bg_color = UiTheme.SURFACE_3
			style.border_color = UiTheme.ACCENT
			# The ring is INSIDE the chip and there is no outer glow: the
			# grid auto-scrolls the selected chip flush against its own
			# edge, and anything drawn outside the chip is sliced off there.
			style.set_border_width_all(maxi(3, int(_chip_px * 0.055)))
		else:
			style.bg_color = UiTheme.SURFACE_2
			style.border_color = UiTheme.LINE
			style.set_border_width_all(1)
		# Anything you are not carrying is greyed right back, so the ones
		# you can actually switch to stand out.
		chip.modulate = Color.WHITE if _allowed(i) else Color(1, 1, 1, 0.28)
		style.set_corner_radius_all(maxi(6, int(_chip_px * 0.14)))
		chip.add_theme_stylebox_override("panel", style)

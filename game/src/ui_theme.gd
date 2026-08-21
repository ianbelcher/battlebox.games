class_name UiTheme
extends Object
## One source of truth for how every menu in this game looks.
##
## Both menus (Escape → WorldMenu, X → PlayerHud's picker) used to invent
## their own colours, corner radii, paddings and font sizes at every call
## site, so nothing lined up and nothing matched. Everything visual now
## comes from here: two menus, one look.
##
## HOW TO USE IT: build a Theme for the current scale and hang it on the
## menu's root Control. Every Button / Label / LineEdit / TabContainer
## underneath inherits it, so a call site only says WHAT a control is, not
## how it should be painted:
##
##     _panel.theme = UiTheme.build(scale)
##
## Rebuild and re-assign it when the window resizes — a Theme is a plain
## resource, so swapping it repaints without touching the node tree (which
## is what keeps WorldMenu's "never rebuild rows" rule intact).
##
## Sizes here are DESIGN pixels at scale 1.0. px() multiplies them.

# ------------------------------------------------------------------
# Palette — a cool near-black with one warm accent. Everything the eye
# should land on is gold; everything else recedes.
# ------------------------------------------------------------------

const SCRIM      := Color(0.012, 0.016, 0.030, 0.82)  ## behind a modal
const SURFACE    := Color("0e1119")   ## the panel itself
const SURFACE_2  := Color("171c28")   ## cards, buttons at rest
const SURFACE_3  := Color("222939")   ## hover
const LINE       := Color("2c3448")   ## hairlines and borders
const LINE_SOFT  := Color(1, 1, 1, 0.06)

const INK        := Color("e9edf6")   ## primary text
const INK_DIM    := Color("98a4bd")   ## labels, section headings
const INK_FAINT  := Color("616e8a")   ## notes, disabled

const ACCENT     := Color("ffc94d")   ## selection, focus, brand
const ACCENT_DEEP:= Color("d99f28")   ## pressed
const ON_ACCENT  := Color("191307")   ## text on a gold fill
const DANGER     := Color("ff6b6b")

## Type scale, design px. Anything that puts a number in a font size
## override should take it from here instead of making one up.
const T_TITLE   := 30
const T_TAB     := 21
const T_HEADING := 17
const T_BODY    := 18
const T_LABEL   := 17
const T_NOTE    := 14
const T_HINT    := 15

const R_PANEL   := 18
const R_CARD    := 12
const R_CONTROL := 9

static func px(n: float, sc: float) -> int:
	return maxi(1, int(round(n * sc)))

## Menu scale from the VIEWPORT, never from a control's own size (which is
## 0 during _ready() — that bug baked every font at minimum scale once).
static func scale_for(vp: Vector2) -> float:
	if vp.x < 1.0:
		vp = Vector2(DisplayServer.window_get_size())
	return clampf(minf(vp.x / 1600.0, vp.y / 900.0), 0.75, 3.2)

# ------------------------------------------------------------------
# Stylebox factories
# ------------------------------------------------------------------

static func flat(bg: Color, radius: int, sc: float, border := 0.0,
		border_color := LINE) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(px(radius, sc))
	sb.corner_detail = 8
	if border > 0.0:
		sb.set_border_width_all(maxi(1, int(round(border * sc))))
		sb.border_color = border_color
	return sb

## The modal panel: dark, softly outlined, with a shadow so it reads as a
## sheet floating over the world rather than a hole cut into it.
static func panel_box(sc: float) -> StyleBoxFlat:
	var sb := flat(SURFACE, R_PANEL, sc, 1.0, LINE)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = px(28, sc)
	sb.shadow_offset = Vector2(0, px(8, sc))
	sb.set_content_margin_all(px(22, sc))
	return sb

## A grouped block of settings inside a panel.
static func card_box(sc: float) -> StyleBoxFlat:
	var sb := flat(SURFACE_2, R_CARD, sc, 1.0, LINE_SOFT)
	sb.set_content_margin_all(px(14, sc))
	return sb

## The gold "this one is chosen" fill, for toggle-style buttons.
static func selected_box(sc: float) -> StyleBoxFlat:
	var sb := flat(ACCENT, R_CONTROL, sc)
	sb.content_margin_left = px(16, sc)
	sb.content_margin_right = px(16, sc)
	sb.content_margin_top = px(9, sc)
	sb.content_margin_bottom = px(9, sc)
	return sb

## A pill for keyboard/pad hints: "ESC", "LB", "Ⓐ".
static func hint_box(sc: float) -> StyleBoxFlat:
	var sb := flat(Color(1, 1, 1, 0.07), 999, sc, 1.0, LINE)
	sb.content_margin_left = px(11, sc)
	sb.content_margin_right = px(11, sc)
	sb.content_margin_top = px(4, sc)
	sb.content_margin_bottom = px(4, sc)
	return sb

# ------------------------------------------------------------------
# The Theme
# ------------------------------------------------------------------

## Everything a menu subtree needs. Assign to the menu root; children
## inherit. Rebuild on resize and re-assign.
static func build(sc: float) -> Theme:
	var t := Theme.new()
	t.default_font_size = px(T_BODY, sc)

	# ---- Label
	t.set_font_size("font_size", "Label", px(T_BODY, sc))
	t.set_color("font_color", "Label", INK)

	# ---- Button. One shape, four states, and a focus ring that is drawn
	# OUTSIDE the fill so keyboard focus never shifts a button's size.
	var b_normal := flat(SURFACE_2, R_CONTROL, sc, 1.0, LINE)
	b_normal.content_margin_left = px(16, sc)
	b_normal.content_margin_right = px(16, sc)
	b_normal.content_margin_top = px(9, sc)
	b_normal.content_margin_bottom = px(9, sc)
	var b_hover: StyleBoxFlat = b_normal.duplicate()
	b_hover.bg_color = SURFACE_3
	b_hover.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)
	var b_pressed: StyleBoxFlat = b_normal.duplicate()
	b_pressed.bg_color = ACCENT_DEEP
	b_pressed.border_color = ACCENT
	var b_disabled: StyleBoxFlat = b_normal.duplicate()
	b_disabled.bg_color = Color(SURFACE_2.r, SURFACE_2.g, SURFACE_2.b, 0.5)
	b_disabled.border_color = Color(1, 1, 1, 0.04)
	var b_focus := flat(Color(0, 0, 0, 0), R_CONTROL, sc, 2.0, ACCENT)
	for spec in [["normal", b_normal], ["hover", b_hover], ["pressed", b_pressed],
			["disabled", b_disabled], ["focus", b_focus]]:
		t.set_stylebox(str(spec[0]), "Button", spec[1])
	t.set_font_size("font_size", "Button", px(T_BODY, sc))
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ON_ACCENT)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", INK_FAINT)
	t.set_constant("h_separation", "Button", px(8, sc))

	# ---- LineEdit
	var e_normal := flat(Color(0, 0, 0, 0.35), R_CONTROL, sc, 1.0, LINE)
	e_normal.content_margin_left = px(12, sc)
	e_normal.content_margin_right = px(12, sc)
	e_normal.content_margin_top = px(8, sc)
	e_normal.content_margin_bottom = px(8, sc)
	var e_focus: StyleBoxFlat = e_normal.duplicate()
	e_focus.border_color = ACCENT
	e_focus.set_border_width_all(maxi(1, int(round(2.0 * sc))))
	t.set_stylebox("normal", "LineEdit", e_normal)
	t.set_stylebox("focus", "LineEdit", e_focus)
	t.set_font_size("font_size", "LineEdit", px(T_BODY, sc))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_FAINT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3))

	# ---- TabContainer.
	#
	# These MUST be set on "TabContainer", not on its inner TabBar:
	# TabContainer pushes its own theme values onto that TabBar on every
	# theme change, so direct TabBar overrides are silently thrown away.
	# That is exactly why the world menu's gold tabs never appeared.
	var tab_sel := flat(ACCENT, R_CONTROL, sc)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	# 14, not 20: the player menu carries EIGHT tabs and, in a half-width
	# split-screen cell, roomier tabs pushed "Tools" off the end behind a
	# pair of scroll arrows no child would ever find.
	tab_sel.content_margin_left = px(14, sc)
	tab_sel.content_margin_right = px(14, sc)
	tab_sel.content_margin_top = px(10, sc)
	tab_sel.content_margin_bottom = px(10, sc)
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(1, 1, 1, 0.04)
	var tab_hover: StyleBoxFlat = tab_sel.duplicate()
	tab_hover.bg_color = Color(1, 1, 1, 0.12)
	var tab_disabled: StyleBoxFlat = tab_sel.duplicate()
	tab_disabled.bg_color = Color(1, 1, 1, 0.02)
	var tab_focus := flat(Color(0, 0, 0, 0), R_CONTROL, sc, 2.0, Color.WHITE)
	tab_focus.corner_radius_bottom_left = 0
	tab_focus.corner_radius_bottom_right = 0
	# The page body: a card that the selected tab sits on top of.
	# Rounded on all four corners: the tabs are pills sitting ON the page,
	# not folder flaps cut into its corner, so squaring one corner only
	# looked right when the leftmost tab happened to be the selected one.
	var tab_panel := flat(SURFACE_2, R_CARD, sc, 1.0, LINE_SOFT)
	tab_panel.set_content_margin_all(px(4, sc))
	for type in ["TabContainer", "TabBar"]:
		t.set_stylebox("tab_selected", type, tab_sel)
		t.set_stylebox("tab_unselected", type, tab_un)
		t.set_stylebox("tab_hovered", type, tab_hover)
		t.set_stylebox("tab_disabled", type, tab_disabled)
		t.set_stylebox("tab_focus", type, tab_focus)
		t.set_stylebox("tabbar_background", type, StyleBoxEmpty.new())
		t.set_font_size("font_size", type, px(T_TAB, sc))
		t.set_color("font_selected_color", type, ON_ACCENT)
		t.set_color("font_unselected_color", type, INK_DIM)
		t.set_color("font_hovered_color", type, INK)
		t.set_color("font_disabled_color", type, INK_FAINT)
		t.set_constant("h_separation", type, px(4, sc))
	t.set_stylebox("panel", "TabContainer", tab_panel)
	t.set_constant("side_margin", "TabContainer", 0)

	# ---- Separators: a single hairline, never the chunky default.
	var rule := StyleBoxLine.new()
	rule.color = LINE
	rule.thickness = maxi(1, int(round(sc)))
	t.set_stylebox("separator", "HSeparator", rule)
	t.set_constant("separation", "HSeparator", px(2, sc))
	var vrule: StyleBoxLine = rule.duplicate()
	vrule.vertical = true
	t.set_stylebox("separator", "VSeparator", vrule)

	# ---- Scrollbars: slim, rounded, out of the way — but VISIBLE. A
	# scrollbar's width comes from its stylebox's minimum size, so a
	# stylebox with no content margins is a scrollbar zero pixels wide:
	# content silently ran off the bottom of every tab with nothing on
	# screen to say so.
	var track := flat(Color(1, 1, 1, 0.04), 999, sc)
	track.set_content_margin_all(px(4, sc))
	var grab := flat(Color(1, 1, 1, 0.26), 999, sc)
	grab.set_content_margin_all(px(4, sc))
	var grab_hi := flat(ACCENT, 999, sc)
	grab_hi.set_content_margin_all(px(4, sc))
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)
	return t

# ------------------------------------------------------------------
# Small shared pieces both menus draw the same way
# ------------------------------------------------------------------

## "ESC", "LB", "Ⓐ" — a key cap. Returns the whole pill.
static func key_cap(text: String, sc: float) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", hint_box(sc))
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", px(T_HINT, sc))
	label.add_theme_color_override("font_color", INK_DIM)
	pill.add_child(label)
	return pill

## A hint line: [ESC] Close   ·   [Tab] Move. Pairs are [cap, words, ...].
static func hint_row(pairs: Array, sc: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", px(8, sc))
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in range(0, pairs.size(), 2):
		if i > 0:
			var dot := Label.new()
			dot.text = "·"
			dot.add_theme_font_size_override("font_size", px(T_HINT, sc))
			dot.add_theme_color_override("font_color", INK_FAINT)
			row.add_child(dot)
		row.add_child(key_cap(str(pairs[i]), sc))
		var words := Label.new()
		words.text = str(pairs[i + 1])
		words.add_theme_font_size_override("font_size", px(T_HINT, sc))
		words.add_theme_color_override("font_color", INK_FAINT)
		words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(words)
	return row

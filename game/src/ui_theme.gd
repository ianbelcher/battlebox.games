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
# Palette — GRAPHITE AND EMBER.
#
# It was navy and gold, which is where this started and what it was
# judged on: "the motif is absolutely disgustingly bad". Two problems,
# and they compound. Every dark surface had blue in it, so the whole game
# sat under a cold cast that nothing warmed up; and the one accent was a
# yellow close enough to that blue's complement to vibrate against it.
#
# So the grounds are NEUTRAL now — a true graphite with no hue in it at
# all — and the accent is a single hot ember. Neutral ground is what lets
# one saturated colour carry a whole interface: there is nothing else on
# screen competing to be looked at, so ember means "this is the thing",
# everywhere, without ever being explained.
#
# THREE COLOURS TOTAL, and the third earns its place. LIVE is mint, and
# it says one thing only: there are PEOPLE in here. It is not decoration
# and it is never used for anything else — a game with players in it and
# a game with twenty bots in it have to look different at a glance, and
# a second accent is the cheapest way to say so.
# ------------------------------------------------------------------

## The page behind every panel. Not black — black reads as a hole in a
## screen; this reads as a surface with a light on it somewhere.
const VOID       := Color("0a0a0c")
const SCRIM      := Color(0.02, 0.019, 0.024, 0.86)  ## behind a modal
const SURFACE    := Color("141317")   ## the panel itself
const SURFACE_2  := Color("1e1c23")   ## cards, buttons at rest
const SURFACE_3  := Color("2a2831")   ## hover
const LINE       := Color("34313c")   ## hairlines and borders
const LINE_SOFT  := Color(1, 1, 1, 0.055)
## A LIT TOP EDGE. Drawn as a top-only border in a colour lighter than
## the fill, which is how a real surface catches the light — and the
## cheapest way to stop a flat rectangle reading as flat.
const EDGE       := Color(1, 1, 1, 0.10)

const INK        := Color("f2f1f5")   ## primary text
const INK_DIM    := Color("a5a1af")   ## labels, section headings
const INK_FAINT  := Color("6b6775")   ## notes, disabled

const ACCENT     := Color("ff5f2e")   ## selection, focus, brand
const ACCENT_DEEP:= Color("d94413")   ## pressed
## Ember at low alpha, for the fill behind a chosen tile. A tint rather
## than the full colour: a grid of solid ember tiles is a grid with
## nothing chosen in it.
const ACCENT_SOFT:= Color(1.0, 0.373, 0.18, 0.14)
## Dark on ember, never white. White on this orange is 3.2:1 and dark is
## 5.9:1 — the button a four-year-old is meant to find has to be the most
## legible thing on the screen, not the least.
const ON_ACCENT  := Color("1a0b04")
## PEOPLE ARE IN THERE. This colour means that and nothing else.
const LIVE       := Color("4fd88a")
const DANGER     := Color("ff5c5c")

## Type scale, design px. Anything that puts a number in a font size
## override should take it from here instead of making one up.
## The wordmark, and nothing else. Big, because it is the only thing on
## the front page that is allowed to be.
const T_DISPLAY := 104
const T_TITLE   := 30
const T_TAB     := 21
const T_HEADING := 17
const T_BODY    := 18
const T_LABEL   := 17
const T_NOTE    := 14
const T_HINT    := 15

const R_PANEL   := 14
const R_CARD    := 10
const R_CONTROL := 7

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
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_size = px(34, sc)
	sb.shadow_offset = Vector2(0, px(8, sc))
	sb.set_content_margin_all(px(22, sc))
	return sb

## A grouped block of settings inside a panel. Lit along its top edge
## rather than outlined all round: an outline draws a box, a lit edge
## makes the same rectangle read as a surface lying on the one behind it.
static func card_box(sc: float) -> StyleBoxFlat:
	var sb := lit_box(SURFACE_2, R_CARD, sc)
	sb.set_content_margin_all(px(14, sc))
	return sb

## The ember "this one is chosen" fill, for toggle-style buttons.
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

## A CARD WITH A LIT TOP EDGE. Same fill as card_box, but the hairline
## runs along the top only and in a lighter colour, so the surface reads
## as catching a light from above rather than as a rectangle of flat
## paint. It is one line of code and it is most of the difference between
## "a dark box" and "a surface".
static func lit_box(bg: Color, radius: int, sc: float) -> StyleBoxFlat:
	var sb := flat(bg, radius, sc)
	sb.border_width_top = maxi(1, int(round(sc)))
	sb.border_color = EDGE
	return sb

## A row in a list, with its state marked by a bar down the RIGHT edge.
##
## THE RIGHT EDGE, NOT THE LEFT, and that is a considered choice rather
## than a coin toss: a coloured rail down the left of a rounded card is
## the single most over-used shape in machine-generated interfaces, and
## it looks like one. It also puts the mark at the start of the reading
## order, where it competes with the name; on the right it sits with the
## thing it is actually about — how many people are in there.
static func rail_box(bg: Color, sc: float, rail := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := flat(bg, R_CARD, sc)
	sb.border_width_top = maxi(1, int(round(sc)))
	sb.border_color = EDGE
	if rail.a > 0.0:
		# Godot gives a stylebox ONE border colour, so the rail and the
		# lit edge cannot both be drawn by it. The rail is the louder of
		# the two and wins; the row keeps its shape either way.
		sb.set_border_width_all(0)
		sb.border_width_right = px(3, sc)
		sb.border_color = rail
	return sb

## HEAVIER TYPE THAN THE BUNDLED FONT HAS.
##
## The game ships one weight — the engine's default face plus three
## fallbacks for symbols — so a heading cannot simply ask for bold, and
## for a long time nothing did: every title on every screen was set in
## the same weight as the body text under it, which is why none of them
## read as titles. FontVariation's synthetic embolden thickens the strokes
## of whatever face is actually in use, and works the same on the web
## build (where there are no system fonts to borrow from) as it does here.
##
## `tracking` is glyph spacing in design px — negative tightens a display
## line, positive opens up a small upper-case label, and both are what
## make a wordmark look set rather than typed.
static func heavy(sc: float, embolden := 0.6, tracking := 0.0) -> FontVariation:
	var face := FontVariation.new()
	var theme := ThemeDB.get_default_theme()
	# get_default_theme() has a font on it once Game._install_fallback_fonts
	# has run; ThemeDB.fallback_font is what is there before that, and on
	# the two platforms that skip the install entirely.
	if theme != null and theme.default_font != null:
		face.base_font = theme.default_font
	else:
		face.base_font = ThemeDB.fallback_font
	face.variation_embolden = embolden
	if not is_zero_approx(tracking):
		face.set_spacing(TextServer.SPACING_GLYPH, int(round(tracking * sc)))
	return face

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

class_name ReviveRing
extends Control
## The circle that fills while a team-mate is picking someone up. Drawn in
## the middle of that player's split-screen cell, because a downed friend
## is who you're looking at anyway — and because a bar that fills tells
## you "keep standing here" far better than a number does.

var progress := 0.0   # 0..1

func _draw() -> void:
	if progress <= 0.0:
		return
	var mid := size * 0.5
	var radius := minf(size.x, size.y) * 0.11
	var width := radius * 0.26
	# The unfilled track, then the filled arc growing clockwise from 12.
	draw_arc(mid, radius, 0.0, TAU, 48, Color(0, 0, 0, 0.45), width, true)
	draw_arc(mid, radius, -PI * 0.5, -PI * 0.5 + TAU * clampf(progress, 0.0, 1.0),
		48, Color("6bd98a"), width, true)
	var font := ThemeDB.fallback_font
	var label := "Reviving…"
	var fs := int(radius * 0.42)
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, mid + Vector2(-w * 0.5, radius + fs * 1.6), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0, 0, 0, 0.85))
	draw_string(font, mid + Vector2(-w * 0.5, radius + fs * 1.6), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("d8ffe4"))

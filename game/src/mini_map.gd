class_name MiniMap
extends RefCounted
## The two maps: the always-on radar in the corner of a player's cell, and
## the full-island map on the menu's Map page.
##
## Both are IMAGES built pixel by pixel from the chunk store, not scenes —
## there is nothing to light, nothing to cull, and a 128x128 image costs
## less to rebuild three times a second than a viewport costs to render
## once. The radar's convention is that whatever you are facing is UP.
##
## One of these belongs to each PlayerHud; `hud` is the one it draws for.
## Everything it needs — the world, the seat, whether a menu is covering
## it — is that HUD's, because a radar is a view of one player's situation
## and there are up to four of them on screen at once.

var hud: PlayerHud = null

func _init(owner_hud: PlayerHud) -> void:
	hud = owner_hud

## Side of the square image the map is drawn into. _map_fit is computed
## from it, so the two must never disagree — hence one constant.
const MAP_IMAGE_PX := 320
## How close to the radar's edge the off-map chevrons sit, in source
## pixels of the 128x128 image.
const RADAR_ARROW_INSET := 8.0

var _radar: TextureRect
var _radar_tick := 0
## A BIG map you can move around: pan with the right stick (or drag),
## zoom with up/down on the left stick. The corner radar only ever shows
## what is right around you; this is for working out where to go.
var _map_tex: TextureRect
var _map_centre := Vector2.ZERO
var _map_zoom := 2.0          # blocks per pixel
## The zoom that exactly fits the world: the furthest you may pull out.
var _map_fit := 2.0
var _map_tick := 0.0

## Open the map showing the WHOLE world and nothing but the world.
##
## _map_fit is the blocks-per-pixel at which the world exactly fills the
## image, and it is also the furthest you are allowed to pull back, so
## there is never black around the edges. Centred on the middle of the
## world rather than on the player for the same reason: centred on someone
## standing near an edge, half the view is off the map.
func _reset_map_view() -> void:
	if hud.world != null:
		_map_fit = clampf(float(hud.world.client_size) / float(MAP_IMAGE_PX), 0.02, 8.0)
		_map_zoom = _map_fit
	_map_centre = Vector2.ZERO
	_map_tick = 0.0
## Stick control while the map page is open.
func _poll_map_nav(input: InputSlot, delta: float) -> void:
	var pan := input.get_look_vector()
	if pan.length() > 0.15:
		_map_centre += pan * _map_zoom * 260.0 * delta
	var zoom := input.get_move_vector()
	if absf(zoom.y) > 0.35:
		_map_zoom = clampf(_map_zoom * (1.0 + zoom.y * delta * 1.6),
			_map_fit * 0.12, _map_fit)
	# Redrawn ~25 times a second: it is a 320x320 image built from a
	# cached heightmap, which is cheap, and a map that lags behind the
	# stick feels broken.
	_map_tick -= delta
	if _map_tick <= 0.0:
		_map_tick = 0.04
		_draw_big_map()
func _draw_big_map() -> void:
	if _map_tex == null or hud.world == null or hud.world.chunks == null:
		return
	var size_px := MAP_IMAGE_PX
	var image := Image.create(size_px, size_px, false, Image.FORMAT_RGB8)
	var half := float(int(hud.world.client_size) / 2)
	for py in size_px:
		for px in size_px:
			var wx := int(_map_centre.x + float(px - size_px / 2) * _map_zoom)
			var wz := int(_map_centre.y + float(py - size_px / 2) * _map_zoom)
			image.set_pixel(px, py, _map_ground(wx, wz, half))
	# Everyone playing, as a fat blip — this is a radar, the ground is
	# only there so you can tell where the blips ARE.
	for child in hud.world.players.get_children():
		if child is Player and not hud.world.ghost_ids.has(child.player_id):
			var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
			var tint: Color = WorldNode.TEAM_COLORS[team] if team >= 0 \
				else Color.WHITE
			_map_blip(image, child.position, tint, size_px, child.is_local)
	# Flags last, over the terrain and the player blips: in capture the
	# flag they are the only thing on this map anybody actually needs.
	for entry: Array in hud.world.flags:
		var team: int = int(entry[0])
		var home: Vector3 = entry[1]
		var present: bool = bool(entry[2])
		var tint: Color = WorldNode.TEAM_COLORS[team] if team >= 0 \
			and team < WorldNode.TEAM_COLORS.size() else Color.WHITE
		_map_flag(image, home, tint, size_px, present)
	_map_tex.texture = ImageTexture.create_from_image(image)
## A flag on the big map — as a little flag where it stands, or as a
## chevron pinned to the edge pointing at it when it is off the view.
##
## The chevron is the whole point: zoomed in on your own base you have no
## idea which way the others are, and "somewhere over there" is the single
## most useful thing a map can tell you in this mode.
func _map_flag(image: Image, at: Vector3, tint: Color, size_px: int,
		present: bool) -> void:
	var px := size_px / 2 + int((at.x - _map_centre.x) / _map_zoom)
	var py := size_px / 2 + int((at.z - _map_centre.y) / _map_zoom)
	var edge := 10
	if px >= edge and px < size_px - edge and py >= edge and py < size_px - edge:
		# On the map: a pole with a pennant. Hollowed when the flag has
		# been taken, so a base that has just been robbed reads as robbed.
		for dy in range(-7, 4):
			_map_dot(image, px, py + dy, size_px, Color(0.05, 0.05, 0.07))
		for dy in range(-7, -1):
			var run := 6 - absi(dy + 4) * 2
			for dx in range(1, maxi(run, 1)):
				var solid: bool = present or dx == 1 or absi(dy + 4) >= 2
				_map_dot(image, px + dx, py + dy, size_px,
					tint if solid else Color(0.12, 0.12, 0.16))
		return
	# Off the map: clamp to the rim and point outward.
	var dir := Vector2(float(px - size_px / 2), float(py - size_px / 2))
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var rim := float(size_px) * 0.5 - 12.0
	var cx := float(size_px) * 0.5 + dir.x * rim
	var cy := float(size_px) * 0.5 + dir.y * rim
	# A solid triangle, same size as the flag, nose along `dir`.
	var side := Vector2(-dir.y, dir.x)
	for step in range(0, 9):
		var t := float(step) / 8.0
		var wide := int(round((1.0 - t) * 5.0))
		var bx := cx + dir.x * (float(step) - 4.0)
		var by := cy + dir.y * (float(step) - 4.0)
		for w in range(-wide, wide + 1):
			_map_dot(image, int(round(bx + side.x * float(w))),
				int(round(by + side.y * float(w))), size_px, tint)
func _map_dot(image: Image, x: int, y: int, size_px: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= size_px or y >= size_px:
		return
	image.set_pixel(x, y, c)
func _map_ground(wx: int, wz: int, half: float) -> Color:
	if absf(float(wx)) > half or absf(float(wz)) > half:
		return Color(0.03, 0.035, 0.05)
	var block: int = hud.world.chunks.top_block(wx, wz)
	if block <= 0:
		block = hud.world.overview_block(wx, wz)
	if block <= 0:
		return Color(0.07, 0.08, 0.11)
	# Washed right out: a low-contrast grey-blue wash of the terrain, so
	# the coloured blips are the only strong thing on it. At full colour
	# the map was a speckled mess nobody could read.
	var raw := Blocks.top_color_of(block)
	var grey := raw.get_luminance()
	return Color(grey * 0.42 + 0.10, grey * 0.44 + 0.11, grey * 0.48 + 0.14)
func _map_blip(image: Image, at: Vector3, tint: Color, size_px: int,
		mine: bool) -> void:
	var px := size_px / 2 + int((at.x - _map_centre.x) / _map_zoom)
	var py := size_px / 2 + int((at.z - _map_centre.y) / _map_zoom)
	var r := 5 if mine else 4
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x := px + dx
			var y := py + dy
			if x < 0 or x >= size_px or y < 0 or y >= size_px:
				continue
			var edge: bool = dx * dx + dy * dy > (r - 1) * (r - 1)
			image.set_pixel(x, y, Color.BLACK if edge else tint)
func _update_radar() -> void:
	var player := hud._player()
	if player == null or hud.world == null or hud.world.chunks == null or hud.world.players == null:
		if _radar != null:
			_radar.visible = false
		return
	_radar.visible = not hud._menu.visible
	# On struggling machines rebuild the radar a third as often.
	_radar_tick += 1
	if Engine.get_frames_per_second() < 20 and _radar_tick % 3 != 0:
		return
	var center := player.position
	# Radar convention: whatever you're facing is UP on the map.
	var yaw: float = player.camera_yaw
	# The client has a ChunkView, not the server's store, so the world's
	# extent comes from the battle config it was told about.
	var half_world: int = int(hud.world.client_size) / 2
	# BLOCKS PER PIXEL, following your VIEW zoom. Zooming in means you are
	# looking further away, so the radar pulls BACK to cover more ground.
	# The TIGHT end is the NORMAL view, unchanged at 0.75 blocks a pixel:
	# that is where you spend your time and where you want detail. What
	# the zoom steps do on top has been widened twice now — the spread is
	# 0.75 wide, so full zoom covers twice the ground the normal view
	# does. When you are looking right across the map, the radar should
	# be showing you that much of it.
	# Halved again from 1.5/2.0: at a block and a half per pixel you were
	# looking at 192 blocks of ground and could not tell a house from a
	# hill.
	var span := 0.75 + 0.75 * (float(player.fp_zoom) / 3.0)
	# WHERE YOU SIT ON THE MAP, in pixels from the top. Dead centre while
	# you are just walking about; as you zoom the view in, you slide DOWN
	# the map so more of what is IN FRONT of you fits on it — which is
	# the whole reason you zoomed. Half way up at rest, then four, three
	# and two tenths up at each zoom step.
	var from_bottom := 0.5 - 0.1 * float(player.fp_zoom)
	var eye_row := 128.0 * (1.0 - from_bottom)
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for py in 128:
		for px in 128:
			var off := Vector2(float(px) - 64.0,
				float(py) - eye_row).rotated(-yaw) * span
			var wx := int(center.x + off.x)
			var wz := int(center.z + off.y)
			# Off the edge of the world is BLACK. Both sources will
			# happily answer for a column that does not exist — the
			# chunk store hands back border filler, the overview is a
			# pure function of noise — so the radar drew a whole island
			# around a 50-block map. Ask the world how big it is first.
			var block := 0
			if absi(wx) <= half_world and absi(wz) <= half_world:
				block = hud.world.chunks.top_block(wx, wz)
				if block <= 0:
					block = hud.world.overview_block(wx, wz)
			# WASHED OUT ON PURPOSE. At full colour, with per-block noise
			# on top, this was a speckled mess you could not read anything
			# off. The ground is now a low-contrast grey-blue wash — enough
			# to make out coastlines and buildings — so the only strong
			# colours on the radar are the players.
			var color := Color(0.06, 0.07, 0.1)
			if block > 0:
				var grey := Blocks.top_color_of(block).get_luminance()
				color = Color(grey * 0.42 + 0.10, grey * 0.44 + 0.11,
					grey * 0.48 + 0.14)
			image.set_pixel(px, py, color)
	if hud.world.match_phase == "BATTLE" and hud.world.storm_radius > 0.0:
		var ring: float = hud.world.storm_radius
		for angle_i in 200:
			var a := angle_i * TAU / 200.0
			var rs := Vector2(hud.world.storm_center.x + cos(a) * ring - center.x,
				hud.world.storm_center.z + sin(a) * ring - center.z).rotated(yaw) / span
			var rx := 64 + int(rs.x)
			var ry := int(eye_row) + int(rs.y)
			for ro in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				if rx + ro.x >= 0 and rx + ro.x < 128 and ry + ro.y >= 0 and ry + ro.y < 128:
					image.set_pixel(rx + ro.x, ry + ro.y, Color(1.0, 0.25, 0.2))
	# NO LOOT ON THE RADAR. Every crate drew a gold dot, and with loot
	# rationed by map area that is a screenful of yellow speckle you
	# cannot pick a player out of. Crates carry a coloured beam in the
	# world itself; that is where you look for them.
	var my_team := int(Game.roster.get(Game.player_id(hud.multiplayer.get_unique_id(), hud.slot),
		{}).get("team", -1))
	for child in hud.world.players.get_children():
		if child is Player and child != player and child.visible \
				and not hud.world.ghost_ids.has(child.player_id):
			var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
			var blip_color: Color = WorldNode.TEAM_COLORS[team] if team >= 0 \
				else Color("ff4426")
			if team == my_team and my_team >= 0:
				blip_color = blip_color.lightened(0.4)
			_blip(image, center, yaw, child.position, blip_color, true, span, eye_row)
	# Flags on the radar too — and THIS is the view that turns with you, so
	# a flag off the edge shows as a chevron whose direction swings round
	# as you look about, and points straight up when you are facing it.
	if hud.world != null:
		for entry: Array in hud.world.flags:
			var fteam: int = int(entry[0])
			var fhome: Vector3 = entry[1]
			var ftint: Color = WorldNode.TEAM_COLORS[fteam] if fteam >= 0 \
				and fteam < WorldNode.TEAM_COLORS.size() else Color.WHITE
			_radar_flag(image, center, yaw, fhome, ftint, span, eye_row,
				bool(entry[2]))
	_blip(image, center, yaw, player.position, Color.WHITE, true, span, eye_row)
	_radar.texture = ImageTexture.create_from_image(image)
## A flag on the personal radar: the flag itself where it stands, or a
## chevron out at the edge pointing the way when it is off the map.
## Everything here is already rotated by `yaw`, so the chevron turns with
## the player for free.
##
## TWO THINGS USED TO BE WRONG HERE, and they compounded.
##
## The handover was on `s.length() < 26.0` — a distance in PIXELS on a map
## 128 across. So the icon only appeared within a fifth of the radar's
## radius (about 20 blocks), and a flag plainly drawn on the map still had
## a chevron sitting on top of it pointing at it. The test is now simply
## whether the icon FITS on the image, which is what "on the map" means.
##
## And the chevron was pinned to that same 26 px circle, so every arrow
## huddled round the player in the middle of the radar, covering the
## terrain you were trying to read and all pointing outward from one small
## ring. They belong at the rim: an arrow's whole job is "that way", and it
## says it best from the edge you are looking past.
func _radar_flag(image: Image, center: Vector3, yaw: float, at: Vector3,
		color: Color, span: float, eye_row: float, present := true) -> void:
	var s := Vector2(at.x - center.x, at.z - center.z).rotated(yaw) / span
	var cx := 64.0
	var cy := eye_row
	var px := cx + s.x
	var py := cy + s.y
	var w := float(image.get_width())
	var h := float(image.get_height())
	# Room for the icon's own footprint: it reaches 8 up, 4 down, 2 left
	# and 7 right of its anchor once the outline is counted.
	if px >= 3.0 and px < w - 8.0 and py >= 9.0 and py < h - 5.0:
		_radar_flag_icon(image, int(round(px)), int(round(py)), color, present)
		return
	var dir := s.normalized()
	if dir.length() < 0.001:
		return
	# Walk the direction out until it meets the inset border. A RECTANGLE,
	# not a circle: the radar is square and the player is not always in the
	# middle of it (`eye_row` slides down as you zoom), so a circle would
	# leave arrows floating short of the edge on some headings and clipped
	# off it on others.
	var reach := INF
	if absf(dir.x) > 0.0001:
		var edge_x := (w - 1.0 - RADAR_ARROW_INSET) if dir.x > 0.0 else RADAR_ARROW_INSET
		reach = minf(reach, (edge_x - cx) / dir.x)
	if absf(dir.y) > 0.0001:
		var edge_y := (h - 1.0 - RADAR_ARROW_INSET) if dir.y > 0.0 else RADAR_ARROW_INSET
		reach = minf(reach, (edge_y - cy) / dir.y)
	if not is_finite(reach) or reach <= 0.0:
		return
	var bx := cx + dir.x * reach
	var by := cy + dir.y * reach
	var side := Vector2(-dir.y, dir.x)
	# A dark pass one pixel proud of the chevron, then the chevron, so a
	# team colour never vanishes into terrain of the same shade.
	for pass_i in 2:
		var tint := Color(0.05, 0.05, 0.07) if pass_i == 0 else color
		var grow := 1 if pass_i == 0 else 0
		for step in range(0 - grow, 6 + grow):
			var t := clampf(float(step) / 5.0, 0.0, 1.0)
			var wide := int(round((1.0 - t) * 3.0)) + grow
			for k in range(-wide, wide + 1):
				_radar_dot(image, int(round(bx + dir.x * (float(step) - 2.0) + side.x * float(k))),
					int(round(by + dir.y * (float(step) - 2.0) + side.y * float(k))), tint)
## The flag icon on the radar, at the size the big map draws it. It used to
## be a 1x5 pole with a 3x2 pennant, which on a radar scaled down to a
## corner of the screen is a smudge you cannot tell from a player's blip —
## and the flag is the one thing in this mode you need to find.
##
## `present` false hollows the pennant, so a base whose flag has been taken
## reads as robbed, exactly as it does on the big map.
func _radar_flag_icon(image: Image, px: int, py: int, color: Color,
		present: bool) -> void:
	var dark := Color(0.05, 0.05, 0.07)
	for dy in range(-9, 6):
		for dx in range(-2, 9):
			var ink := hud._flag_ink(dx, dy)
			if ink == 0:
				if hud._flag_ink(dx - 1, dy) > 0 or hud._flag_ink(dx + 1, dy) > 0 \
						or hud._flag_ink(dx, dy - 1) > 0 or hud._flag_ink(dx, dy + 1) > 0:
					_radar_dot(image, px + dx, py + dy, dark)
			elif ink == 1:
				_radar_dot(image, px + dx, py + dy, dark)
			else:
				# Hollow: keep the outer ring of the pennant, drop the fill.
				var solid: bool = present or dx == 1 or absi(dy + 4) >= 2
				_radar_dot(image, px + dx, py + dy,
					color if solid else Color(0.12, 0.12, 0.16))
func _radar_dot(image: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, c)
func _blip(image: Image, center: Vector3, yaw: float, pos: Vector3, color: Color,
		big := false, span := 2.0, eye_row := 64.0) -> void:
	var s := Vector2(pos.x - center.x, pos.z - center.z).rotated(yaw) / span
	var px := 64 + int(s.x)
	var py := int(eye_row) + int(s.y)
	var r := 2 if big else 1
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			if px + dx < 0 or px + dx >= 128 or py + dy < 0 or py + dy >= 128:
				continue
			if absi(dx) > r or absi(dy) > r:
				# One-pixel dark outline so blips read on any terrain.
				if absi(dx) <= r + 1 and absi(dy) <= r + 1:
					image.set_pixel(px + dx, py + dy, Color(0.05, 0.05, 0.08))
			else:
				image.set_pixel(px + dx, py + dy, color)

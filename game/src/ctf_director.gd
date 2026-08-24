class_name CtfDirector
extends Node
## Capture the flag: the bases, the poles, who is carrying what, and the
## score. Server-side only, at World/Ctf.
##
## The client half of CTF is a handful of mirrors on WorldNode — flags,
## ctf_scores, ctf_target — filled by cl_flags. Nothing here draws
## anything, and nothing here is an @rpc: cl_flags and cl_flag_taken stay
## on WorldNode, which is still the only file that says what crosses the
## socket.
##
## Bases are BUILT, not decorated: a mound of team wool with a pole on
## top, stamped into the chunk store like any other edit, then marked
## no-carve so nobody can dig the flag out from under itself.

## The world these flags are planted in.

var world: WorldNode = null


## id -> when they stop being untouchable. A capture cannot be punished:
## being shot during the half second the screen is black would be the
## least fair thing in the game.

var _capture_guard: Dictionary = {}

## Progress toward a flag self-revive, per player. Kept apart from
## `battle.revive_progress` (team-mate pick-ups) so the two cannot add
## up to a double-speed revive when a mate happens to be stood there too.

var _flag_progress: Dictionary = {}

var _bot_out_since: Dictionary = {}

## team -> {"home": Vector3, "pos": Vector3 (INF while taken), "back_at": msec}

var _flags: Dictionary = {}

## THE LEVEL EACH TEAM'S MOUND IS BUILT AT, remembered for the life of the
## world. Cleared with `team_site`, which it belongs to.
##
## This is the fix for bases growing on top of each other. `team_site` is
## deliberately kept between rounds — a team's ground is its ground — but
## the build height was recomputed from `surface_y` every time, and after
## round one the surface at that spot IS THE TOP OF THE LAST MOUND. So
## round two raised a second mound on the summit of the first, round three
## on that, and the flags climbed into the sky one storey a round.
##
## Pinning the level makes a rebuild land exactly on top of the old one,
## block for block, which is the same thing as not rebuilding at all.

var _ctf_base_y: Dictionary = {}

var _revive_pulse_t: Dictionary = {}

func guarded(id: String) -> bool:
	return Time.get_ticks_msec() < int(_capture_guard.get(id, 0))

## Bases, poles and flags — the machinery both flag modes are built on.
func active() -> bool:
	return world.game_mode == "ctf" or world.game_mode == "holdout"

## LAST FLAG STANDING: the same board, one rule different. Losing your
## flag does not cost you a point, it costs you the round. See
## HoldoutRules.
func elimination() -> bool:
	return world.game_mode == "holdout"

## Put a block down as part of building a base, remembering it for one
## bulk broadcast. Skips anything already correct so the payload is walls
## and plinth rather than a thousand air blocks.
func put(pos: Vector3i, block: int, pairs: Array) -> void:
	if pos.y <= 0 or pos.y >= WorldGen.CHUNK_H:
		return
	if world.store.get_block(pos) == block:
		return
	world.store.set_block(pos, block)
	pairs.append([pos, block])

## How tall the mound stands at a given distance from its centre. One block
## per ring, so every approach is a staircase you can simply walk up.
func _ctf_mound_step(dist: float) -> int:
	if dist > float(world.CTF_MOUND_RADIUS):
		return -1
	var drop := int(floor(dist * float(world.CTF_MOUND_HEIGHT + 1)
		/ float(world.CTF_MOUND_RADIUS + 1)))
	return maxi(world.CTF_MOUND_HEIGHT - drop, 0)

## Build one team's mound and pole, and return where its flag stands.
##
## Idempotent at a fixed `_ctf_base_y`: every column in the footprint has
## its top set and everything above it cleared, so building twice leaves
## exactly what building once left.
func _ctf_build_base(team_i: int, centre: Vector3, pairs: Array) -> Vector3:
	var cx := int(round(centre.x))
	var cz := int(round(centre.z))
	if not _ctf_base_y.has(team_i):
		_ctf_base_y[team_i] = world.store.surface_y(cx, cz)
	var base_y := int(_ctf_base_y[team_i])
	var skin: int = world.TEAM_WOOL[team_i % world.TEAM_WOOL.size()]
	for dz in range(-world.CTF_MOUND_RADIUS, world.CTF_MOUND_RADIUS + 1):
		for dx in range(-world.CTF_MOUND_RADIUS, world.CTF_MOUND_RADIUS + 1):
			var step := _ctf_mound_step(Vector2(dx, dz).length())
			if step < 0:
				continue
			var wx := cx + dx
			var wz := cz + dz
			var top := base_y + step
			var ground := world.store.surface_y(wx, wz)
			# Pack up to the mound's height here...
			for y in range(mini(ground + 1, top + 1), top + 1):
				put(Vector3i(wx, y, wz), Blocks.DIRT, pairs)
			# ...cut away anything standing above it, so the slope is
			# walkable and last round's pole cannot survive as a spike...
			for y in range(top + 1, maxi(ground, top) + world.CTF_POLE_HEIGHT + 2):
				put(Vector3i(wx, y, wz), Blocks.AIR, pairs)
			# ...and skin the surface in the team's colour.
			put(Vector3i(wx, top, wz), skin, pairs)
	_ctf_raise_pole(team_i, cx, cz, base_y, pairs)
	# The flag itself is the standing room on the summit, beside the pole.
	return Vector3(cx, base_y + world.CTF_MOUND_HEIGHT + 1, cz)

## The glowing team-coloured pole on the summit — or the empty air where it
## stands while the flag is away.
func _ctf_raise_pole(team_i: int, cx: int, cz: int, base_y: int,
		pairs: Array, present := true) -> void:
	var beacon: int = Blocks.BEACON_TEAM + (team_i % 8)
	var summit := base_y + world.CTF_MOUND_HEIGHT
	for i in world.CTF_POLE_HEIGHT:
		put(Vector3i(cx, summit + 1 + i, cz),
			beacon if present else Blocks.AIR, pairs)

## Raise every team's base and plant its flag. Called once as a round starts.
func build_all_bases() -> void:
	_flags.clear()
	for team_i in world.team_count:
		if not world.battle.team_site.has(team_i):
			world.battle.team_site[team_i] = world.battle.find_team_site(world.battle.team_site.size())
		var pairs: Array = []
		var flag_at := _ctf_build_base(team_i, world.battle.team_site[team_i], pairs)
		_flags[team_i] = {"home": flag_at, "pos": flag_at, "back_at": 0,
			"out": false}
		if not pairs.is_empty():
			world.cl_edits.rpc(pairs)
	refresh_no_carve()
	broadcast_flags()
	# The positions are logged because they must be IDENTICAL from one round
	# to the next in the same world. A mound that climbs a few blocks every
	# round is invisible in a screenshot and obvious in this line.
	var where: Array = []
	for team_i: int in _flags.keys():
		where.append("%d@%v" % [team_i, _flags[team_i].home])
	print("CTF: %d mounds raised | %s" % [_flags.size(), ", ".join(where)])

## Take every flag pole down, for a round in a mode that has no flags.
##
## A FLAG IS A BLOCK, not a marker, so clearing `_flags` — which is all a
## battle royale used to do — left every team's glowing pole standing in
## the world. Anybody who played capture the flag and then a battle in the
## same world found the map dotted with flags belonging to a game that was
## not running: they cannot be picked up, they cannot be scored, and they
## look exactly like something you are supposed to go for.
##
## The mound underneath is left alone. It is terrain, it is walkable, and a
## small coloured hill is not a promise about the rules the way a beacon
## is.
##
## Found by SEARCHING for them rather than from a remembered list. Bases
## are built at a fixed spot per team, but the process that built them may
## be long gone — a server restart keeps the world and forgets everything
## else — so a list would take down the poles it happened to raise and
## leave the ones it inherited.
func strip_flags() -> void:
	var pairs: Array = []
	for team_i: int in world.battle.team_site.keys():
		var centre: Vector3 = world.battle.team_site[team_i]
		var cx := int(round(centre.x))
		var cz := int(round(centre.z))
		# One column each: a pole is one block wide and stands on the
		# summit, so the whole search is a strip of the world's height.
		for y in range(0, WorldGen.CHUNK_H):
			var here := Vector3i(cx, y, cz)
			var found := world.store.get_block(here)
			if found >= Blocks.BEACON_TEAM and found < Blocks.BEACON_TEAM + 8:
				put(here, Blocks.AIR, pairs)
	if not pairs.is_empty():
		world.cl_edits.rpc(pairs)
	_flags.clear()
	broadcast_flags()

## Tell the chunk store which ground a blast's exit ramp may not cut
## through. Everything else that breaks a block asks `can_carve`, but the
## ramp is carved down inside ChunkStore where flags do not exist.
func refresh_no_carve() -> void:
	var zones: Array = []
	for team_i: int in _flags.keys():
		var home: Vector3 = _flags[team_i].get("home", Vector3.INF)
		if home != Vector3.INF:
			zones.append([home.x, home.z, float(world.CTF_MOUND_RADIUS) + 0.5])
	world.store.no_carve = zones

## What every client is told about the flags: team, where its base is,
## whether the flag is standing, and whether it has gone for good.
##
## THE LAST TWO ARE DIFFERENT QUESTIONS and only the first was being
## answered. "Standing" was computed from `back_at` alone — the six-second
## timer a flag spends away after a capture in capture the flag — and a
## flag taken for good in last flag standing never gets a `back_at`, it
## gets `out`. So an eliminated team's flag reported as STANDING for the
## rest of the round: the pole was gone from the world, but the radar
## still drew a flag on their base, and running over there to take it did
## nothing at all, because the flag's position is INF and there is nothing
## left to touch.
##
## That is very probably "I touched another team's flag a number of times
## and it didn't get their flag" — the flag being touched had already been
## taken by somebody else, and only the map still said otherwise.
func _flag_payload() -> Array:
	var payload: Array = []
	for team_i: int in _flags.keys():
		var flag: Dictionary = _flags[team_i]
		var gone: bool = bool(flag.get("out", false))
		var away: bool = int(flag.back_at) > 0
		payload.append([team_i, flag.home, not (away or gone), gone])
	return payload

func broadcast_flags() -> void:
	world.cl_flags.rpc(_flag_payload(), world.ctf_scores, world.ctf_target, world.ctf_caps, world.ctf_lost,
		world.ctf_player_caps)

## The WHOLE pole goes while the flag is away, not just its top block, so a
## base you have just been robbed of reads as robbed from across the map —
## the glow going out is the announcement.
func show_flag(team_i: int, present: bool) -> void:
	var flag: Dictionary = _flags.get(team_i, {})
	if flag.is_empty():
		return
	var home: Vector3 = flag.home
	var pairs: Array = []
	_ctf_raise_pole(team_i, int(home.x), int(home.z),
		int(_ctf_base_y.get(team_i, int(home.y) - world.CTF_MOUND_HEIGHT - 1)),
		pairs, present)
	if not pairs.is_empty():
		world.cl_edits.rpc(pairs)

## THE REVIVE PULSE: the ring on screen and the alarm everyone nearby
## hears, both rate-limited.
##
## These were sent EVERY SERVER TICK — sixty reliable RPCs a second per
## downed player, and sixty overlapping copies of the alarm a second on
## every client within forty blocks. It sounded like a fault and it was
## pure waste on the wire: the ring is a UI element that nobody can read
## faster than about ten times a second, and the alarm is meant to be a
## pulse you can hear a rhythm in.
##
## `frac` is still exact when it matters — the caller sends 0.0 and the
## completion itself unconditionally.
## `personal` sends to that player ALONE. Tagging in at your own flag is
## something you are doing to yourself: broadcasting it made everybody
## within forty blocks hear an alarm and watch a ring fill for a revive
## that had nothing to do with them — including team-mates standing near
## the flag, alive and well, wondering why the game thought they were
## dying. A team-mate PICK-UP still goes to everyone, because that one is
## meant to be heard: it says somebody is stationary and vulnerable.
func revive_pulse(id: String, pos: Vector3, frac: float, delta: float,
		personal := false) -> void:
	var due := float(_revive_pulse_t.get(id, 0.0)) - delta
	if due > 0.0:
		_revive_pulse_t[id] = due
		return
	_revive_pulse_t[id] = 0.45
	if not personal:
		world.cl_revive_progress.rpc(id, frac)
		world.cl_revive_noise.rpc(pos)
		return
	var peer := int(str(id).split(":")[0])
	if peer <= 1:
		return                       # a computer player has nobody to tell
	world.cl_revive_progress.rpc_id(peer, id, frac)
	world.cl_revive_noise.rpc_id(peer, pos)

## STANDING AT YOUR OWN FLAG, COMING BACK. Progress while you are there,
## nothing while you are not, and the same ring and alarm a team-mate
## pick-up uses — you are doing the same thing, just for yourself.
##
## Your flag has to be HOME for this: while somebody is running it back to
## their base there is nothing to touch, which is the pressure that makes
## losing your flag hurt.
func _ctf_flag_channel(id: String, pos: Vector3, flag: Dictionary,
		flag_at: Vector3, delta: float) -> void:
	# Belt and braces: this is only ever called from the out and downed
	# branches, but it is the one place that can start a revive, and a
	# revive starting on a player who is perfectly well is exactly the
	# confusion being fixed.
	if not world.out_ids.has(id) and not world.downed_ids.has(id):
		if _flag_progress.has(id):
			_flag_progress.erase(id)
			_revive_pulse_t.erase(id)
		return
	var here: bool = not flag.is_empty() and int(flag.back_at) == 0 \
		and _at_flag(pos, flag_at)
	if not here:
		if _flag_progress.has(id):
			_flag_progress.erase(id)
			_revive_pulse_t.erase(id)
			world.cl_revive_progress.rpc(id, 0.0)
		return
	var done := float(_flag_progress.get(id, 0.0)) + delta
	_flag_progress[id] = done
	revive_pulse(id, pos, clampf(done / world.CTF_FLAG_REVIVE_SECONDS, 0.0, 1.0),
		delta, true)
	if done >= world.CTF_FLAG_REVIVE_SECONDS:
		_flag_progress.erase(id)
		_revive_pulse_t.erase(id)
		world.cl_revive_progress.rpc(id, 0.0)
		respawn(id)

func tick(delta: float) -> void:
	if _flags.is_empty():
		return
	var now := Time.get_ticks_msec()
	for team_i: int in _flags.keys():
		var flag: Dictionary = _flags[team_i]
		if bool(flag.get("out", false)):
			continue          # taken for good: that team is out
		if int(flag.back_at) > 0 and now >= int(flag.back_at):
			flag.back_at = 0
			flag.pos = flag.home
			show_flag(team_i, true)
			broadcast_flags()
	for id: String in world.player_state.keys():
		var team := int(Game.roster.get(id, {}).get("team", -1))
		if team < 0:
			continue
		var pos: Vector3 = world.player_state[id].get("pos", Vector3.INF)
		if pos == Vector3.INF:
			continue
		# SOMEBODY WHO IS OUT touching their OWN flag comes back. That is the whole
		# respawn rule when reviving is off: fly home, tag up, rejoin.
		if world.out_ids.has(id):
			# Nothing to walk home TO. Their flag has been taken for good,
			# so there is no tag-in to attempt and no backstop to fire —
			# and without this they trudge to where their base was for the
			# rest of the round, which looks exactly like a bot that has
			# lost the plot.
			if elimination() and team_is_out(team):
				continue
			# A computer player WALKS HOME like everybody else. Its goal
			# while it is out is its own flag (see `_ctf_bot_goal`), so
			# the ordinary rule below — touch your flag, tag back in —
			# does the work, and you can watch it make the trip.
			#
			# The timer is only a backstop now. It used to be the whole
			# mechanism: a bot wandered at random wherever it fell and was
			# teleported home eight seconds later, which is why they looked
			# like they had no idea where their base was. Leave it in
			# though — a bot walled into a pit must not be out for the rest
			# of the round — but give it long enough that walking is what
			# normally happens.
			if world.bots.roster.has(id):
				var mine_bot: Dictionary = _flags.get(team, {})
				var bot_flag: Vector3 = mine_bot.get("home", Vector3.INF)
				# The SAME channel a person has to stand through. A bot
				# that tagged in instantly while a player had to hold the
				# spot for three seconds would be the one rule in this
				# mode the computer gets an easier version of.
				_ctf_flag_channel(id, pos, mine_bot, bot_flag, delta)
				if not world.out_ids.has(id):
					var home_spot := home_spot(team,
						maxi(seats_of(team).find(id), 0))
					world.bots.roster[id].pos = home_spot
					world.player_state[id].pos = home_spot
					world.cl_stand.rpc(id, home_spot, false, [], false)
					continue
				var out_since := int(_bot_out_since.get(id, 0))
				if out_since == 0:
					_bot_out_since[id] = now
					out_since = now
				if now - out_since > world.BOT_RETURN_MS:
					_bot_out_since.erase(id)
					respawn(id)
					var back := home_spot(team, maxi(seats_of(team).find(id), 0))
					world.bots.roster[id].pos = back
					world.player_state[id].pos = back
					world.cl_stand.rpc(id, back, false, [], false)
				continue
			var mine: Dictionary = _flags.get(team, {})
			# Typed local, never `mine.home as Vector3`: `as` is for object
			# types, and the analyzer rejects the whole file over it — with
			# no line number, because every script that preloads this one
			# reports the failure instead.
			var mine_at: Vector3 = mine.get("home", Vector3.INF)
			_ctf_flag_channel(id, pos, mine, mine_at, delta)
			continue
		# A DOWNED PLAYER CAN TAG IN AT THEIR OWN FLAG TOO. This used to
		# skip them outright, so being knocked down with no team-mate near
		# enough meant crawling all the way home and then standing on your
		# own flag with nothing happening — which is exactly what happened,
		# and he reported the flag as broken. It is not a special case: it
		# is the same rule the out play by, and being downed is a WORSE
		# position than being out, so it should not have fewer ways back.
		if world.downed_ids.has(id):
			var down_flag: Dictionary = _flags.get(team, {})
			var down_at: Vector3 = down_flag.get("home", Vector3.INF)
			_ctf_flag_channel(id, pos, down_flag, down_at, delta)
			continue
		for other_team: int in _flags.keys():
			if other_team == team:
				continue
			var flag2: Dictionary = _flags[other_team]
			if int(flag2.back_at) > 0:
				continue
			var flag_at2: Vector3 = flag2.pos
			if _at_flag(pos, flag_at2):
				capture(id, team, other_team)
				break

## Standing room on a team's mound, beside their pole.
##
## Not safe_stand(): that finds the highest solid ground, which on the
## summit is the pole itself. And not a flat ring at the flag's height
## either — the mound SLOPES, so a spot three blocks out is a block or two
## lower than the summit, and placing everybody at the same y buried the
## outer seats in the hillside. Each spot is stood on whatever the mound
## actually does at those coordinates.
func seats_of(team_i: int) -> PackedStringArray:
	return world.battle.team_seats.get(team_i, PackedStringArray())

func home_spot(team_i: int, seat: int) -> Vector3:
	var flag: Dictionary = _flags.get(team_i, {})
	if flag.is_empty():
		return world.battle.team_start_spot(team_i, seat)
	var home: Vector3 = flag.home
	# Ring out from the pole, skipping its own column, staying on the mound.
	var reach := world.CTF_MOUND_RADIUS - 1
	var spots: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx == 0 and dz == 0:
				continue
			if Vector2(dx, dz).length() > float(reach):
				continue
			spots.append(Vector2i(dx, dz))
	spots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).length_squared() < Vector2(b).length_squared())
	if spots.is_empty():
		return home
	var pick: Vector2i = spots[seat % spots.size()]
	var sx := int(home.x) + pick.x
	var sz := int(home.z) + pick.y
	var sy := world.bots.walk_y(sx, sz, home.y + 2.0)
	if sy < 0:
		sy = world.store.surface_y(sx, sz)
	return Vector3(sx, float(sy) + 1.0, sz)

## Close enough to a flag to take it.
##
## Measured FLAT, with a separate and generous vertical window, because a
## straight-line distance quietly fails in the one situation that matters:
## the pole stands four blocks tall on top of a mound, so anybody who
## climbs it, jumps at it, or comes in over the top is several blocks above
## the flag's foot and a 2.8-block sphere never reaches them. You are at
## the flag if you are at it on the ground plan and roughly at its level.
func _at_flag(pos: Vector3, flag_at: Vector3) -> bool:
	if flag_at == Vector3.INF:
		return false
	var flat := Vector2(pos.x - flag_at.x, pos.z - flag_at.z).length()
	return flat < world.CTF_FLAG_TOUCH and absf(pos.y - flag_at.y) < world.CTF_FLAG_REACH_Y

func capture(id: String, team: int, from_team: int) -> void:
	world.ctf_caps[team] = int(world.ctf_caps.get(team, 0)) + 1
	world.ctf_lost[from_team] = int(world.ctf_lost.get(from_team, 0)) + 1
	world.ctf_player_caps[id] = int(world.ctf_player_caps.get(id, 0)) + 1
	if elimination():
		# THAT IS THEIR ROUND. No point, no respawning flag, no coming
		# back: the whole reason to dig in is that there is no second
		# chance. Points are settled once, at the end — see
		# MatchDirector.end_holdout.
		knock_out_team(from_team)
		print("HOLDOUT: %s took team %d's flag — team %d is out"
			% [id, from_team, from_team])
		world.battle.check_holdout_over()
		return
	world.ctf_scores[team] = int(world.ctf_scores.get(team, 0)) + 1
	world.ctf_scores[from_team] = int(world.ctf_scores.get(from_team, 0)) - 1
	var flag: Dictionary = _flags[from_team]
	flag.pos = Vector3.INF
	flag.back_at = Time.get_ticks_msec() + world.CTF_FLAG_RETURN_MS
	show_flag(from_team, false)
	broadcast_flags()
	# A capture used to bring the SCORER'S WHOLE TEAM back at once, as a
	# release valve for a losing side. It is gone on purpose. There are
	# exactly two ways back into a round now, and both are something a
	# person does: fly home and touch your own flag, or have a
	# team-mate stand over you and pick you up. Anything that quietly
	# undoes a knockout somewhere else on the map makes knocking anybody
	# down feel like it did not count.

	# Home you go. Without this, touch-to-score lets one player stand on an
	# enemy flag and take it again every time it respawns — the headless
	# run had somebody win 3-0 off a single flag without moving. Sending
	# the capturer back is also what "capturing" ought to mean: you took it
	# somewhere, and now you have to make the trip again.
	var seats: PackedStringArray = world.battle.team_seats.get(team, PackedStringArray())
	var home_spot := home_spot(team, maxi(seats.find(id), 0))
	# HELD, GUARDED, THEN MOVED. The trip home waits for the screen to
	# fade down, so the world changes while nobody can see it — which is
	# the whole trick. `cl_flag_taken` goes first because that is what
	# starts the fade.
	#
	# reset_kit FALSE: you keep everything you were carrying. Being sent
	# home for scoring must never cost you the loot you scored with.
	_capture_guard[id] = Time.get_ticks_msec() + world.CTF_CAPTURE_MSEC
	world.cl_flag_taken.rpc(id, team, from_team)
	var landing := home_spot
	get_tree().create_timer(world.CTF_CAPTURE_FADE).timeout.connect(func() -> void:
		var late: Dictionary = world.player_state.get(id, {})
		if not late.is_empty():
			late.pos = landing
		if world.bots.roster.has(id):
			world.bots.roster[id].pos = landing
		world.cl_stand.rpc(id, landing, false, [], false))
	print("CTF: %s took team %d's flag (scores %s)" % [id, from_team, world.ctf_scores])
	if int(world.ctf_scores.get(team, 0)) >= world.ctf_target:
		world.battle.finish(team)

## EVERY PLAYER ON A TEAM, OUT. Their flag comes down with them, so the
## board shows at a glance who is still in it.
##
## They stay in the world as ghosts and can watch — being out of a round
## should not mean staring at a menu — but nothing they do counts, and the
## way back in at your own flag is closed because there is no longer a
## flag to touch.
func knock_out_team(team: int) -> void:
	for id: String in Game.roster.keys():
		if int(Game.roster[id].get("team", -1)) != team:
			continue
		world.match_alive.erase(id)
		world.downed_ids.erase(id)
		world.battle.revive_progress.erase(id)
		_flag_progress.erase(id)
		_revive_pulse_t.erase(id)
		_bot_out_since.erase(id)
		if not world.out_ids.has(id):
			world.out_ids[id] = true
			world.cl_eliminated.rpc(id)
	if _flags.has(team):
		var gone: Dictionary = _flags[team]
		gone.pos = Vector3.INF
		# MARKED, not timed. `back_at` is an absolute clock reading and
		# `tick` brings a flag back the moment it passes — so "a very long
		# time" is not a way to say "never", it is a way to say "later".
		gone.out = true
		show_flag(team, false)
	broadcast_flags()

## Has this team lost its flag for good? Only ever true in last flag
## standing — in capture the flag a taken flag always comes back.
func team_is_out(team: int) -> bool:
	return bool(_flags.get(team, {}).get("out", false))

## Which teams still have a flag standing.
func teams_holding() -> Array:
	var held: Array = []
	for team_i: int in _flags.keys():
		if not bool(_flags[team_i].get("out", false)):
			held.append(team_i)
	return held

## WHO ACTUALLY SURVIVED THE ROUND, which is not the same question as
## which flags are still up, and the scoring wants this one.
##
## The pot was shared out among `teams_holding()` — every flag not marked
## out. A flag is an object in the world and it does not care whether
## anybody is left behind it, so a side that had been wiped off the field
## still counted as a survivor and still took a share. Five flags standing
## divides the pot five ways and the table gives nothing at all past three,
## so a round that really came down to three teams paid everybody zero.
## That is "there was only three teams left at the end ... that doesn't
## seem to be what happened".
##
## Alive means STANDING: in the round and not on the floor. A side whose
## every player is knocked out at the final whistle did not hold anything,
## whatever its flagpole says.
func teams_surviving() -> Array:
	var left: Array = []
	for team_i: int in _flags.keys():
		if bool(_flags[team_i].get("out", false)):
			continue
		for id: String in world.match_alive.keys():
			if int(Game.roster.get(id, {}).get("team", -1)) != team_i:
				continue
			if world.downed_ids.has(id) or world.out_ids.has(id):
				continue
			left.append(team_i)
			break
	return left

## Back in the game, standing at your own flag.
##
## THERE IS NO WAY BACK ONCE YOUR FLAG IS GONE, and this is the one place
## that has to know it. Every route back into a round ends here — touching
## your own flag, the channel a computer player stands through, and the
## backstop that recovers a bot walled into a pit — and that backstop
## called this unconditionally on a timer. So a team whose flag had been
## taken went out, waited, and then walked back into the round still
## fighting, which is precisely what was reported.
##
## Guarding the junction rather than each of the three routes is the point:
## a fourth route added later cannot forget.
func respawn(id: String) -> void:
	# NOBODY COMES BACK. Guarding the junction rather than each route is
	# the point — touching your own flag, the channel a computer player
	# stands through, and the backstop that recovers a bot walled into a
	# pit all end up here, and a fourth route added later cannot forget.
	if world.no_revive:
		return
	if elimination() and team_is_out(int(Game.roster.get(id, {}).get("team", -1))):
		return
	world.out_ids.erase(id)
	_flag_progress.erase(id)
	_bot_out_since.erase(id)
	world.match_alive[id] = true
	world.downed_ids.erase(id)
	var state: Dictionary = world.player_state.get(id, {})
	if not state.is_empty():
		state.hp = world.MATCH_HP
	world.cl_hearts.rpc(id, world.MATCH_HP)
	world.cl_revived.rpc(id)

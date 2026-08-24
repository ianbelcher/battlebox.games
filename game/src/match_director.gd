class_name MatchDirector
extends Node
## The battle: lobby, drop, storm, damage, revives, elimination, and the
## league table that outlives any one round. Server-side only, at
## World/Match.
##
## What is NOT here is the state a client needs to DRAW the battle —
## match_phase, match_seconds, match_alive, downed_ids, storm_radius, the
## scoreboard. Those stay on WorldNode, because a client has no director
## and mirrors them straight off the wire. The rule the split follows: if
## both ends need to know it, the world owns it; if only the server needs
## it to run the simulation, it lives here.
##
## There is no @rpc in this file. sv_match_start, sv_match_config and every
## cl_* broadcast stay on WorldNode and call in here, so that one file is
## still the whole of the wire protocol.

## The world this battle is fought in.

var world: WorldNode = null


var _last_hit_ms: Dictionary = {}

var _timer := 0.0

var _storm_hurt_ms: Dictionary = {}

var _next_bite_ms := 0

var revive_progress: Dictionary = {}

## Out-of-combat healing: untouched for 8s, a heart every 3s.

var _last_regen_ms: Dictionary = {}

## The spot each team starts the match standing on, chosen once per
## match. Cleared with everything else when a match begins.

var team_site: Dictionary = {}

## team index -> PackedStringArray of member ids, sorted. A player's place
## in this list is their place in the huddle, so it is the same every round.

var team_seats: Dictionary = {}

## Standing in fire costs a heart per tick.

var _burn_ms: Dictionary = {}

## Set the moment a battle is decided, cleared as the next one opens.
## Without it a match whose end is detected twice — several players
## eliminated in the same tick, a timeout landing on the same frame as
## the last knockout — counted two wins for one game, which is exactly
## what was showing on the banner.

var _result_recorded := false

func storm_start_seconds() -> float:
	# Big enough that the wall starts beyond every corner of the arena
	# from wherever this battle's center landed.
	return world.battle_size * 0.75 + Vector2(world.storm_center.x, world.storm_center.z).length()

## The single 20-second pre-battle period: the map resets fresh,
## everyone lands together at the middle so it streams in around them,
## nobody can touch blocks, teams settle — then the drop.
func open_lobby() -> void:
	# The battle scars stay: the world only resets when the HOST picked
	# a different world — otherwise everyone keeps the map they know
	# (and nobody re-streams a thing between battles).
	if not world.selected_map.is_empty() and world.selected_map != world.store.current_map_key \
			and not (world.selected_map == world.store.theme and world.store.current_map_key.is_empty()):
		world._do_world_reset(world.selected_map)
	_assign_stray_humans()
	world.monsters_by_id.clear()
	# Nobody is moved for the LOBBY. Herding every player and computer
	# player onto the spawn point between battles put the whole table in
	# a huddle at the origin for a few seconds, which looked like a bug.
	# _server_match_drop() places everyone at their team's site when the
	# battle actually starts, which is the only placement that matters.
	world.match_phase = "LOBBY"
	_timer = world.LOBBY_SECONDS
	print("%s lobby open" % ("Capture the flag" if world.ctf.active() else "Battle royale"))
	world.cl_match.rpc("LOBBY", world.LOBBY_SECONDS)

func _assign_stray_humans() -> void:
	var counts: Array[int] = []
	counts.resize(world.team_count)
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team >= 0 and team < world.team_count:
			counts[team] += 1
	var changed := false
	for id: String in Game.roster.keys():
		if int(Game.roster[id].get("team", -1)) >= 0:
			continue
		var best := 0
		for t in world.team_count:
			if counts[t] < counts[best]:
				best = t
		Game.roster[id].team = best
		counts[best] += 1
		changed = true
	if changed:
		Game.cl_roster.rpc(Game.roster)

func tick(delta: float) -> void:
	if world.match_phase == "IDLE":
		return
	_timer -= delta
	match world.match_phase:
		"LOBBY":
			if _timer <= 0.0:
				drop_everyone()
		"SETUP":
			if _timer <= 0.0:
				world.match_phase = "BATTLE"
				# Last flag standing has a round length of its own: it is
				# not a storm closing in, it is how long you have to hold
				# what you built.
				_timer = holdout_seconds() \
					if world.ctf.elimination() else world.storm_minutes * 60.0
				world.cl_match.rpc("BATTLE", _timer)
		"BATTLE":
			if world.ctf.elimination():
				# LAST FLAG STANDING runs on a clock, because two teams
				# properly dug in will never finish each other off — and
				# that stalemate is a real result here rather than a
				# failure, so it has to be allowed to end and score.
				world.storm_radius = -1.0
				# NO SECOND SUBTRACTION. `_timer -= delta` already ran at
				# the top of this function, for every phase — so taking it
				# off again here ran the round clock at DOUBLE SPEED. Ten
				# minutes on the display elapsed in five of playing, and
				# the round ended while the clock still read half of what
				# was left. Reported as "counts down from 10 minutes but
				# ends at 4 minutes — a really bad problem".
				_tick_regen()
				_tick_fire()
				world.bots.tick_orbs(delta)
				tick_revives(delta)
				world.ctf.tick(delta)
				world.match_seconds = maxf(0.0, _timer)
				if _timer <= 0.0:
					end_holdout()
				else:
					check_holdout_over()
				return
			if world.ctf.active():
				# No storm and no clock — capture the flag runs until
				# somebody reaches the target score.
				_timer = 9999.0
				world.storm_radius = -1.0
				_tick_regen()
				_tick_fire()
				world.bots.tick_orbs(delta)
				tick_revives(delta)
				world.ctf.tick(delta)
				check_win()
				return
			if world.storm_minutes >= 59.0:
				# Unlimited: the storm never closes and the match only ends
				# when one team is left standing.
				_timer = 9999.0
			var elapsed := 1.0 - clampf(_timer / (world.storm_minutes * 60.0), 0.0, 1.0)
			if elapsed < 0.5:
				# First half: fight freely, no storm anywhere.
				world.storm_radius = -1.0
				world.cl_storm.rpc(-1.0, world.storm_center)
			else:
				var frac := (elapsed - 0.5) * 2.0
				world.storm_radius = lerpf(storm_start_seconds(), world.STORM_END, frac)
				if _timer <= 0.0:
					# Overtime: close on down to a 30-block-wide arena and
					# hold — the battle only ends when one team is left
					# standing (dig fights welcome), never on a countback.
					world.storm_radius = maxf(world.STORM_END + _timer * 0.35, 15.0)
				world.cl_storm.rpc(world.storm_radius, world.storm_center)
				_storm_damage()
				_storm_bite()
			_tick_regen()
			_tick_fire()
			if int(_timer) % 2 == 0 and _timer - floorf(_timer) < 0.02:
				_tick_crate_gravity()
			world.bots.tick_orbs(delta)
			tick_revives(delta)
			check_win()
		"END":
			if _timer <= 0.0:
				# Anybody at all, computer players included. A server with
				# bots on it and nobody watching keeps playing rounds, so
				# the next person through the door finds a live game.
				if world.match_loop and not Game.roster.is_empty():
					open_lobby()
					print("%s loop: fresh lobby open" % ("Capture the flag" if world.ctf.active() else "Battle royale"))
				else:
					world.match_phase = "IDLE"
					world.cl_match.rpc("IDLE", 0.0)

## Everyone gets a team (auto-balanced if unpicked), full hearts, and a drop
## point high above a spread ring. Gliding down is automatic.
func drop_everyone() -> void:
	world.match_phase = "SETUP"
	_timer = 6.0
	world.match_alive.clear()
	world.downed_ids.clear()
	revive_progress.clear()
	world.ctf._flag_progress.clear()
	world.ctf._revive_pulse_t.clear()
	world.bots.orbs.clear()
	# team_site is deliberately NOT cleared. A team's ground is a fixed
	# feature of the world, like a hill: you fortify it in one round and
	# come back to it in the next. Re-rolling it every battle was why a
	# team kept landing in roughly the same quarter of the map but never
	# on the same block, so nothing anyone built was ever there when they
	# came back. It is cleared when the WORLD changes and only then.
	_result_recorded = false
	start_new_scorecard()
	var counts: Array[int] = []
	counts.resize(world.team_count)
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team >= world.team_count:
			Game.roster[id].team = -1
		elif team >= 0:
			counts[team] += 1
	# Teams are settled BEFORE anyone is placed, because where you stand
	# depends on who else is on your team.
	for id: String in Game.roster.keys():
		var e: Dictionary = Game.roster[id]
		if int(e.get("team", -1)) < 0:
			var best := 0
			for t in world.team_count:
				if counts[t] < counts[best]:
					best = t
			e.team = best
			counts[best] += 1

	# Seat order, fixed by SORTED id rather than by roster order. Roster
	# order changes whenever somebody joins, leaves or rejoins, so using it
	# shuffled the same four people around the huddle between rounds even
	# when the team had not changed.
	team_seats.clear()
	for id: String in Game.roster.keys():
		var team_of := int(Game.roster[id].get("team", 0))
		var seats: PackedStringArray = team_seats.get(team_of, PackedStringArray())
		seats.append(id)
		team_seats[team_of] = seats
	for team_of: int in team_seats.keys():
		var seats: PackedStringArray = team_seats[team_of]
		seats.sort()
		team_seats[team_of] = seats

	# Capture the flag raises the bases FIRST, so that placing a team puts
	# them on their own base's floor rather than on the hillside the base
	# is about to be built over.
	if world.ctf.active():
		world.ctf_scores.clear()
		world.ctf_caps.clear()
		world.ctf_lost.clear()
		world.ctf_player_caps.clear()
		for t in world.team_count:
			world.ctf_scores[t] = 0
			world.ctf_caps[t] = 0
			world.ctf_lost[t] = 0
		world.ctf.build_all_bases()
	else:
		# No flags in this mode — so there are none in the world either.
		# Clearing the bookkeeping alone left last round's poles standing
		# where a battle royale had no use for them.
		world.ctf.strip_flags()
		world.store.no_carve = []

	var i := 0
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		world.match_alive[id] = true
		# World resets between battles can drop server-side state for
		# bots — recreate instead of crashing the match start.
		if not world.player_state.has(id):
			world.player_state[id] = {"pos": world.store.safe_stand(Vector3(world.spawn_pos)), "treasures": 0,
				"name": str(entry.get("name", "?")), "hp": world.MATCH_HP}
		var state: Dictionary = world.player_state[id]
		state.hp = world.MATCH_HP
		world.cl_hearts.rpc(id, world.MATCH_HP)
		var team_i := int(entry.get("team", 0))
		# Everyone's place in the huddle comes from WHO they are, not from
		# the order the roster happened to be walked in. Same team, same
		# world, same block — every single round, so the wall you put up
		# last time is the wall you start behind this time.
		var seats_here: PackedStringArray = team_seats.get(team_i, PackedStringArray())
		var seat := maxi(seats_here.find(id), 0)
		var drop := world.ctf.home_spot(team_i, seat) if world.ctf.active() \
			else team_start_spot(team_i, seat)
		world.cl_stand.rpc(id, drop, world.loot_only, Weapons.starting_kit(world.game_mode), true)
		if world.bots.roster.has(id):
			world.bots.roster[id].pos = drop
			# WORLD_BOT_WEAPON=<id>: hand every computer player that weapon
			# at the drop, so the shooting can be tested without waiting
			# for them to find a crate.
			var forced_weapon := OS.get_environment("WORLD_BOT_WEAPON")
			# Capture the flag arms EVERYBODY at the drop — the human kit is
			# `STARTING_KIT_CTF`, which leads with the Little Shooter — so a
			# computer player gets the same gun. Left on the sword it spent
			# the round crate-shopping instead of playing, and lost every
			# exchange with a person who started armed. Battle royale still
			# opens on the sword for both, because there the scramble for
			# crates IS the opening.
			var drop_weapon := 0 if world.ctf.active() else 13
			world.bots.roster[id].weapon = forced_weapon.to_int() \
				if forced_weapon.is_valid_int() else drop_weapon
			world.player_state[id].pos = drop
		i += 1
	# WORLD_BOT_PIT_TEST=<depth>: drop every computer player into a hole
	# that deep and see whether it gets out. After a night of bombing each
	# other the map is craters, and a crater is the one shape digging
	# sideways cannot solve — this is how `_bot_build_out` gets exercised
	# without waiting eight hours for the bots to make their own.
	var pit_env := OS.get_environment("WORLD_BOT_PIT_TEST")
	if pit_env.is_valid_int() and pit_env.to_int() > 0:
		var depth := pit_env.to_int()
		var dug: Array = []
		for bot_id: String in world.bots.roster.keys():
			var at: Vector3 = world.bots.roster[bot_id].pos
			var bx := floori(at.x)
			var bz := floori(at.z)
			var top := floori(at.y)
			for dz2 in range(-1, 2):
				for dx2 in range(-1, 2):
					for y2 in range(top - depth, top + 3):
						var hole := Vector3i(bx + dx2, y2, bz + dz2)
						if hole.y <= 1 or world.store.get_block(hole) == Blocks.AIR:
							continue
						world.store.set_block(hole, Blocks.AIR)
						dug.append(hole)
		if not dug.is_empty():
			world.cl_batch.rpc(dug, Blocks.AIR)
		print("PITTEST: %d bots dropped into %d-block holes" % [world.bots.roster.size(), depth])
	# Fresh loot everywhere so late matches aren't scavenged dry.
	world.crates_by_id.clear()
	var crate_count := world.survival.crate_target()
	var placed := 0
	var attempts := 0
	while placed < crate_count and attempts < crate_count * 12:
		attempts += 1
		var langle2 := randf() * TAU
		# Scatter inside the SLAB, not inside the storm. The storm's
		# starting radius is deliberately bigger than the arena so no red
		# shows at the drop, so using it here threw loot off the map.
		var ldist2 := sqrt(randf()) * float(world.store.half_extent() - 4)
		var lx2 := int(cos(langle2) * ldist2)
		var lz2 := int(sin(langle2) * ldist2)
		var ly2 := world.store.surface_y(lx2, lz2)
		if world.survival.crate_ground_ok(lx2, lz2, ly2):
			var crate_here := Vector3(lx2 + 0.5, ly2 + 1.0, lz2 + 0.5)
			var near_weapon := -1
			var too_close := false
			for other: Dictionary in world.crates_by_id.values():
				var od: float = crate_here.distance_to(other.pos)
				if od < 6.0:
					too_close = true
					break
				if od < 20.0:
					near_weapon = int(other.weapon)
			if too_close:
				continue
			var pool2 := [1, 1, 1, 2, 9, 9, 11, 12, 12, 15, 15, 19]
			var pick: int = pool2[randi() % pool2.size()]
			if pick == near_weapon:
				pick = pool2[randi() % pool2.size()]
			world.crates_by_id[world.survival._next_crate_id] = {"weapon": pick, "pos": crate_here}
			world.survival._next_crate_id += 1
			placed += 1
	print("Battle loot: %d/%d crates placed (%d attempts)" % [placed, crate_count, attempts])
	world.survival.broadcast_crates()
	Game.cl_roster.rpc(Game.roster)
	world.storm_radius = storm_start_seconds()
	# The circle closes on a RANDOM spot each battle, and the wall starts
	# beyond the arena edge so no red is visible at the drop.
	var storm_angle := randf() * TAU
	var storm_dist := randf() * world.battle_size * 0.22
	world.storm_center = Vector3(cos(storm_angle) * storm_dist, 0, sin(storm_angle) * storm_dist)
	# Every battle gets its own time of day, and runs exactly one day.
	#
	# There used to be a `clock = 0.79` on the line under the random one,
	# which quietly won — 0.79 is ten to seven in the evening, so every
	# round anyone ever played started at dusk and got darker. The random
	# line had been dead for as long as it had been there.
	#
	# Fitting the day to the match length is what makes a random start
	# fair: whatever time it opens on, a round sees the same amount of
	# daylight and the same amount of night, and ends where it began.
	world.clock = world._random_clock()
	world.day_length = clampf(world.storm_minutes * 60.0, world.MIN_DAY_SECONDS, 1800.0)
	world.cl_clock.rpc(world.clock, world.day_length)
	world.cl_match.rpc("SETUP", 6.0)
	# Where each team stood, every battle. These coordinates must be
	# IDENTICAL from one round to the next in the same world — that is the
	# whole point of a team having a home to fortify — so printing them is
	# how anyone checks it without having to play two rounds and squint.
	var sites: Array = []
	for team_of: int in team_site.keys():
		sites.append("%d@%v" % [team_of, team_site[team_of]])
	sites.sort()
	print("%s: dropping %d players | team sites: %s"
		% ["Capture the flag" if world.ctf.active() else "Battle royale",
			world.match_alive.size(), ", ".join(sites)])

func _storm_damage() -> void:
	var now := Time.get_ticks_msec()
	for id: String in world.match_alive.keys():
		var state: Dictionary = world.player_state.get(id, {})
		if state.is_empty() or now < int(_storm_hurt_ms.get(id, 0)):
			continue
		var pos: Vector3 = state.pos
		# Outside the wall you are ON THE CLOCK. A short grace band, then
		# damage that speeds up the further out you are: matches used to
		# end by everyone standing in the middle waiting for the storm to
		# get round to it.
		var out := Vector2(pos.x - world.storm_center.x,
			pos.z - world.storm_center.z).length() - world.storm_radius
		if out > 2.0:
			# 1.1s a heart at the edge, down to 0.3s deep out — eight
			# hearts is about nine seconds at the rim, under three if you
			# ignore it completely.
			var bite := clampf(1.1 - out / 40.0, 0.3, 1.1)
			_storm_hurt_ms[id] = now + int(bite * 1000.0)
			state.hp = int(state.get("hp", world.MATCH_HP)) - 1
			world.cl_hearts.rpc(id, state.hp)
			# No knockback from the storm: pushing players while they're
			# already outside fed back into more storm damage and once
			# launched a player 142 km off the map.
			if state.hp <= 0:
				eliminate(id)

## The storm chews the world: surface blocks just outside the wall pop
## away, so the losing ground visibly crumbles.
func _storm_bite() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_bite_ms:
		return
	_next_bite_ms = now + 500
	for n in 6:
		var a := randf() * TAU
		var r := world.storm_radius + randf_range(2.0, 14.0)
		var wx := int(world.storm_center.x + cos(a) * r)
		var wz := int(world.storm_center.z + sin(a) * r)
		var y := world.store.surface_y(wx, wz)
		if y <= WorldGen.SEA_LEVEL or y >= WorldGen.CHUNK_H - 2:
			continue
		var pos := Vector3i(wx, y, wz)
		if world.store.get_block(pos) == Blocks.AIR:
			continue
		world.store.set_block(pos, Blocks.AIR)
		world.cl_edit.rpc(pos, Blocks.AIR, "storm")
		if randf() < 0.12:
			world.cl_boom_fx.rpc(pos)

## Down-but-not-out: if living teammates remain you crawl and can be
## revived (teammate stands close for ~3s); alone, you're out.
func eliminate(id: String, attacker := "") -> void:
	if not world.match_alive.has(id) or world.downed_ids.has(id):
		return
	var team := int(Game.roster.get(id, {}).get("team", -1))
	var has_standing_mate := false
	for other: String in world.match_alive.keys():
		if other != id and not world.downed_ids.has(other) \
				and int(Game.roster.get(other, {}).get("team", -2)) == team:
			has_standing_mate = true
	var fell_at: Vector3 = world.player_state.get(id, {}).get("pos", Vector3.ZERO)
	# Every knockout, downed or out — the computer players read this to
	# work out which approaches have been turning into trenches.
	world.remember_scar(fell_at)
	# Reviving is a mode setting in capture the flag: with it off, a
	# knockout puts you straight OUT and the only way back is
	# your own flag.
	# One rung of one ladder — see ReviveRule.
	var can_revive: bool = ReviveRule.mates_can_lift(world.revive_mode)
	if has_standing_mate and can_revive:
		world.downed_ids[id] = Time.get_ticks_msec()
		world.cl_downed_state.rpc(id, true)
		_emit_feed(id, attacker)
		return
	world.match_alive.erase(id)
	world.downed_ids.erase(id)
	drop_weapons(id, fell_at)
	# out_ids is written by cl_eliminated, which is an authority RPC and
	# therefore never runs on the server itself — so the server had no idea
	# who was out, and "touch your own flag to come back" could never
	# fire for anybody.
	world.out_ids[id] = true
	world.cl_eliminated.rpc(id)
	_emit_feed(id, attacker)
	check_win()

## One feed line per knockout — downs included (that IS the kill as far
## as the scrap that caused it goes; being counted out when your whole
## team goes down doesn't double-report).
func _emit_feed(id: String, attacker := "") -> void:
	# Only an ENEMY knockout scores. Falling in the storm, or a teammate's
	# stray rocket, is nobody's point.
	if not attacker.is_empty() and attacker != id and world.teams_differ(attacker, id):
		credit_frag(attacker)
		broadcast_scoreboard()
	var victim_name := str(Game.roster.get(id, {}).get("name", "?"))
	var attacker_name := str(Game.roster.get(attacker, {}).get("name", ""))
	world.cl_feed.rpc(attacker_name, int(Game.roster.get(attacker, {}).get("team", -1)),
		victim_name, int(Game.roster.get(id, {}).get("team", -1)))

## Where one player of `team_i` STARTS. On the ground, beside their team.
##
## There is no sky drop any more. This is a building game first: a squad
## that starts standing together on solid ground can dig in and put up
## something defensible before anyone finds them, and a first round where
## a team does nothing but build a fort is a perfectly good round. Being
## scattered out of the sky made that impossible.
##
## Each team gets its own quarter of the compass, and a SITE is chosen
## once per team per match — flat, dry, inside the world — then everyone
## on that team is packed into a one-block spiral around it and stood on
## whatever the ground turns out to be underneath them.
func team_start_spot(team_i: int, seat: int) -> Vector3:
	if not team_site.has(team_i):
		team_site[team_i] = find_team_site(team_site.size())
	var centre: Vector3 = team_site[team_i]
	# Ring by ring: 1 in the middle, then 6, then 12 … all one block
	# apart, so even a team of seventeen starts in one huddle.
	#
	# `seat` is the player's fixed place in the team, NOT a running count
	# of who has been placed so far. With a counter, one person missing a
	# round moved everybody else onto somebody else's block.
	var n := seat
	var offset := Vector3.ZERO
	if n > 0:
		var ring := 1
		var placed := 1
		while placed + ring * 6 <= n:
			placed += ring * 6
			ring += 1
		var index := n - placed
		var around := TAU * float(index) / float(ring * 6)
		offset = Vector3(cos(around), 0.0, sin(around)) * float(ring)
	# One chokepoint for every placement: in bounds, on dry ground.
	return world.store.safe_stand(centre + offset)

## A place for a whole team to stand: out on its own bearing, on dry
## level-ish ground, as far from the other teams' sites as we can manage
## in a handful of tries.
func find_team_site(slot: int) -> Vector3:
	var bearing := TAU * float(slot) / float(maxi(world.team_count, 1)) \
		+ randf_range(-0.25, 0.25)
	var best := Vector3.ZERO
	var best_score := -1e9
	for attempt in 40:
		var angle := bearing + randf_range(-0.45, 0.45)
		var dist := float(world.store.half_extent()) * randf_range(0.42, 0.72)
		var wx := int(cos(angle) * dist)
		var wz := int(sin(angle) * dist)
		if not world.store.inside_world(wx, wz, 10):
			continue
		var y := world.store.surface_y(wx, wz)
		if y <= WorldGen.SEA_LEVEL or y >= WorldGen.CHUNK_H - 10:
			continue
		if Blocks.is_liquid(world.store.get_block(Vector3i(wx, y, wz))):
			continue
		# Prefer flat: a team standing on a staircase is no use to anyone.
		var roughness := 0
		for off in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3),
				Vector2i(0, -3), Vector2i(2, 2), Vector2i(-2, -2)]:
			roughness += absi(world.store.surface_y(wx + off.x, wz + off.y) - y)
		var apart := 1e9
		for other: Vector3 in team_site.values():
			apart = minf(apart, Vector2(wx - other.x, wz - other.z).length())
		if apart > 1e8:
			apart = float(world.store.half_extent())
		var score := apart - float(roughness) * 4.0
		if score > best_score:
			best_score = score
			best = Vector3(wx, float(y) + 1.0, wz)
	if best == Vector3.ZERO:
		# Nowhere nice: anywhere inside the world beats nowhere at all.
		return world.store.safe_stand(Vector3(cos(bearing), 0.0, sin(bearing))
			* float(world.store.half_extent()) * 0.5)
	return best

## Crates whose支撑 got blown away settle back to the ground.
func _tick_crate_gravity() -> void:
	var moved := false
	for crate_id: int in world.crates_by_id.keys():
		var cpos: Vector3 = world.crates_by_id[crate_id].pos
		var ground := world.store.surface_y(floori(cpos.x), floori(cpos.z))
		var rest := float(ground) + 1.0
		if cpos.y > rest + 0.5:
			world.crates_by_id[crate_id].pos.y = maxf(cpos.y - 6.0, rest)
			moved = true
		elif cpos.y < rest - 0.05:
			# ...and UP. This only ever fell, so any crate the ground
			# rose under — or that was placed a block low to begin with —
			# stayed half-buried for the rest of the match. Terrain moves
			# under loot all the time now that blasts leave ramps.
			world.crates_by_id[crate_id].pos.y = rest
			moved = true
	if moved:
		world.survival.broadcast_crates()

func _tick_fire() -> void:
	var now := Time.get_ticks_msec()
	for id: String in world.match_alive.keys():
		var state: Dictionary = world.player_state.get(id, {})
		if state.is_empty() or now < int(_burn_ms.get(id, 0)):
			continue
		var foot: Vector3 = state.pos
		if world.store.get_block(Vector3i(floori(foot.x), floori(foot.y), floori(foot.z))) == Blocks.FIRE \
				or world.store.get_block(Vector3i(floori(foot.x), floori(foot.y) + 1, floori(foot.z))) == Blocks.FIRE:
			_burn_ms[id] = now + 1400
			hurt(id, 1, foot)

func _tick_regen() -> void:
	var now := Time.get_ticks_msec()
	for id: String in world.match_alive.keys():
		if world.downed_ids.has(id):
			continue
		if now - int(_last_hit_ms.get(id, 0)) < 8000:
			continue
		var state: Dictionary = world.player_state.get(id, {})
		if state.is_empty() or int(state.get("hp", world.MATCH_HP)) >= world.MATCH_HP:
			continue
		if now - int(_last_regen_ms.get(id, 0)) < 3000:
			continue
		_last_regen_ms[id] = now
		state.hp = int(state.get("hp", world.MATCH_HP)) + 1
		world.cl_hearts.rpc(id, state.hp)

func tick_revives(delta: float) -> void:
	for id: String in world.downed_ids.keys().duplicate():
		# THERE IS NO BLEEDING OUT. Being knocked out is not a countdown:
		# you stay down until a team-mate picks you up, and in capture the
		# flag you can also get yourself back by reaching your own flag.
		# The ONE way to be out for good is for your whole team to be down
		# at the same time, because then there is nobody left who could
		# ever come for you.
		#
		# It used to be both — no rescuer OR forty-five seconds on the
		# floor — and the timer was the part that made being knocked out
		# feel like waiting to be told off. It has gone.
		var team := int(Game.roster.get(id, {}).get("team", -1))
		var rescuer := false
		for other: String in world.match_alive.keys():
			if other != id and not world.downed_ids.has(other) \
					and int(Game.roster.get(other, {}).get("team", -2)) == team:
				rescuer = true
				break
		if not rescuer:
			world.downed_ids.erase(id)
			revive_progress.erase(id)
			world.ctf._flag_progress.erase(id)
			world.ctf._revive_pulse_t.erase(id)
			world.match_alive.erase(id)
			# BEING OUT IS WRITTEN HERE, ON THE SERVER. `cl_eliminated` is
			# an authority RPC, so it never runs on the server itself —
			# `_match_eliminate` knows that and sets `out_ids` directly,
			# but this path, the one you take when you BLEED OUT, did not.
			# So anyone who ran out of time on the floor was in no set at
			# all: not alive, not downed, not out. They could never tag
			# in at their own flag (that rule reads `out_ids`), a bot in
			# that state never walked home, and they were missing from the
			# state a joining client is sent — which is a roster of nine
			# showing four alive and five nowhere.
			world.out_ids[id] = true
			world.cl_revive_progress.rpc(id, 0.0)
			world.cl_eliminated.rpc(id)
			check_win()
			continue
		var pos: Vector3 = world.player_state.get(id, {}).get("pos", Vector3.ZERO)
		var mate_close := false
		for other: String in world.match_alive.keys():
			if other == id or world.downed_ids.has(other):
				continue
			if int(Game.roster.get(other, {}).get("team", -2)) == team \
					and Vector3(world.player_state.get(other, {}).get("pos", Vector3.INF)).distance_to(pos) < world.REVIVE_RADIUS:
				mate_close = true
		if mate_close:
			# REVIVE_SECONDS of standing there, measured in real time. This
			# used to add a fixed amount per server tick, so it finished in
			# about a third of a second — you barely had to touch them.
			revive_progress[id] = float(revive_progress.get(id, 0.0)) + delta
			var frac := clampf(float(revive_progress[id]) / world.REVIVE_SECONDS, 0.0, 1.0)
			# Reviving is LOUD — everyone nearby hears the alarm.
			world.ctf.revive_pulse(id, pos, frac, delta)
			if float(revive_progress[id]) >= world.REVIVE_SECONDS:
				world.downed_ids.erase(id)
				revive_progress.erase(id)
				world.ctf._revive_pulse_t.erase(id)
				var state: Dictionary = world.player_state.get(id, {})
				if not state.is_empty():
					state.hp = world.REVIVE_HP
				# You come back on ONE heart and heal from there, so a
				# pick-up in the open is still a risk worth taking.
				world.cl_hearts.rpc(id, world.REVIVE_HP)
				world.cl_revive_progress.rpc(id, 0.0)
				world.cl_downed_state.rpc(id, false)
				Sfx.play("collect")
				# Logged because the alternative is guessing. The rule that
				# stops computer players walking into a firefight to do
				# this (BOT_REVIVE_DANGER) can just as easily stop them
				# ever doing it at all, and a mode where nobody is ever
				# picked up is a different game from the one intended —
				# but neither shows up anywhere except in this count.
				print("REVIVE: %s picked up" % id)
		elif revive_progress.has(id):
			revive_progress.erase(id)
			# ...but not if the flag is filling the same ring: a downed
			# player stood on their own mound with a team-mate beside them
			# would otherwise have the two paths fight over it every tick.
			if not world.ctf._flag_progress.has(id):
				world.cl_revive_progress.rpc(id, 0.0)

func check_win() -> void:
	var teams_alive: Dictionary = {}
	for id: String in world.match_alive.keys():
		if Game.roster.has(id):
			teams_alive[int(Game.roster[id].get("team", 0))] = true
	if world.match_phase != "BATTLE":
		return
	# A battle is NOT over because the people are out of it — the computer
	# players finish what they started and somebody actually wins, while
	# the humans watch. Nor is it over because the people have GONE: an
	# empty server with computer players on it keeps playing, so whoever
	# turns up next walks into a game already in progress rather than a
	# field of bots standing about waiting to be told to start. Joining
	# mid-round already works — you get the round's kit and a base.
	#
	# Only a completely empty roster stops the loop, because then there is
	# nothing left to simulate.
	if Game.roster.is_empty():
		finish(-2)
		return
	# Capture the flag is decided ON THE SCOREBOARD, never by clearing the
	# other team out: knocking someone down only buys you the time it takes
	# them to get home. Ending it here would turn it back into a battle.
	if world.ctf.active():
		return
	if teams_alive.size() <= 1:
		var winner := -1
		for t in teams_alive.keys():
			winner = t
		finish(winner)

func finish(winner: int) -> void:
	world.match_phase = "END"
	# Long enough to read the table, short enough not to be a wait. The
	# next battle places everyone properly at their team's site, so there
	# is nothing to see in between.
	_timer = 14.0
	var what := "Battle royale"
	if world.ctf.elimination():
		what = "Last flag standing"
	elif world.ctf.active():
		what = "Capture the flag"
	print("%s over: team %d" % [what, winner])
	record_result(winner)
	world.cl_match_end.rpc(winner)

## HOW LONG A ROUND OF LAST FLAG STANDING RUNS.
##
## Ten minutes, unless WORLD_HOLDOUT_MINUTES says otherwise. A mode that
## can only be seen by waiting ten minutes is a mode that never gets
## checked end to end, and the scoring only happens at the very end — so
## the one part most worth testing was the part hardest to reach.
## Read once, not per call: this is reached from the bot goal path, which
## asks how much of the round is left for every computer player deciding
## whether it is still minding the flag — and an environment lookup is a
## syscall, not a variable.
var _holdout_seconds := -1.0

func holdout_seconds() -> float:
	if _holdout_seconds < 0.0:
		var knob := OS.get_environment("WORLD_HOLDOUT_MINUTES")
		_holdout_seconds = knob.to_float() * 60.0 \
			if knob.is_valid_float() and knob.to_float() > 0.0 \
			else HoldoutRules.ROUND_MINUTES * 60.0
	return _holdout_seconds

## How much of the round is left, 1 at the bell and 0 at the whistle.
func holdout_fraction() -> float:
	var whole := holdout_seconds()
	return clampf(_timer / whole, 0.0, 1.0) if whole > 0.0 else 1.0

## Is last flag standing over because only one team still has a flag?
func check_holdout_over() -> void:
	if world.match_phase != "BATTLE" or not world.ctf.elimination():
		return
	if Game.roster.is_empty():
		finish(-2)
		return
	if world.ctf.teams_holding().size() <= 1:
		end_holdout()

## SETTLE THE ROUND. Whoever still has a flag shares the pot, and the
## share depends on how many of them there are — see HoldoutRules.
##
## Points go into the same per-team score capture the flag uses, so they
## accumulate across rounds and the existing scoreboard shows them with no
## second system to build.
##
## The winner reported is the top team, or -1 when more than one held: a
## shared round is a draw and saying otherwise on the end card would be a
## lie about what just happened.
func end_holdout() -> void:
	if world.match_phase != "BATTLE":
		return
	# SURVIVING, not merely holding — see CtfDirector.teams_surviving.
	var held: Array = world.ctf.teams_surviving()
	var each := HoldoutRules.share(held.size())
	for team_v: Variant in held:
		var team := int(team_v)
		world.ctf_scores[team] = int(world.ctf_scores.get(team, 0)) + each
	world.ctf.broadcast_flags()
	print("HOLDOUT: %d team(s) survived of %d holding, %d point(s) each (scores %s)"
		% [held.size(), world.ctf.teams_holding().size(), each, world.ctf_scores])
	finish(int(held[0]) if held.size() == 1 else -1)

## One knockout, for the board.
func credit_frag(attacker_id: String) -> void:
	if attacker_id.is_empty() or not Game.roster.has(attacker_id):
		return
	var who := str(Game.roster[attacker_id].get("name", ""))
	if who.is_empty():
		return
	var row: Dictionary = world.player_frags.get(who, {"total": 0, "last": 0, "team": -1})
	row.total = int(row.total) + 1
	row.last = int(row.last) + 1
	row.team = int(Game.roster[attacker_id].get("team", -1))
	world.player_frags[who] = row

func record_result(winner: int) -> void:
	if _result_recorded:
		return
	_result_recorded = true
	world.matches_played += 1
	if winner >= 0:
		world.team_wins[winner] = int(world.team_wins.get(winner, 0)) + 1
	broadcast_scoreboard()

## Everyone's "this game" column goes back to zero as the next one opens.
func start_new_scorecard() -> void:
	for who: String in world.player_frags.keys():
		world.player_frags[who].last = 0
	broadcast_scoreboard()

func broadcast_scoreboard() -> void:
	world.cl_scoreboard.rpc(world.team_wins, world.player_frags, world.matches_played)

## Match damage between enemies (orbs and blast splash call this).
func hurt(id: String, amount: int, from_pos: Vector3, attacker := "") -> void:
	if world.ctf.guarded(id):
		return
	if world.match_phase != "BATTLE" or not world.match_alive.has(id):
		return
	if world.downed_ids.has(id):
		return  # players who are OUT are untouchable — get back in, or stay out
	var now := Time.get_ticks_msec()
	var mercy := 250 if world.bots.roster.has(id) else 800
	if now - int(_last_hit_ms.get(id, -mercy)) < mercy:
		return  # brief mercy so one volley can't insta-delete you
	_last_hit_ms[id] = now
	var state: Dictionary = world.player_state.get(id, {})
	if state.is_empty():
		return
	state.hp = int(state.get("hp", world.MATCH_HP)) - amount
	world.cl_hearts.rpc(id, state.hp)
	world.cl_bonk.rpc(id, from_pos)
	if state.hp <= 0:
		eliminate(id, attacker)

## Scatter what someone was carrying where they fell, as crates anyone can
## pick up — including them, if a team-mate stands them back up on the spot.
## Off by default: a child who found a blaster should keep it.
func drop_weapons(id: String, at: Vector3) -> void:
	if not world.drop_on_knockout:
		return
	var carried: Array = world.bots.roster[id].get("carried", []) if world.bots.roster.has(id) else []
	if world.bots.roster.has(id) and int(world.bots.roster[id].get("weapon", 13)) != 13:
		carried = [int(world.bots.roster[id].weapon)]
		world.bots.roster[id].weapon = 13
	for weapon: int in carried:
		var spot := world.store.safe_stand(at + Vector3(randf_range(-2.0, 2.0), 0.0,
			randf_range(-2.0, 2.0)))
		world.crates_by_id[world.survival._next_crate_id] = {"weapon": weapon, "pos": spot}
		world.survival._next_crate_id += 1
	if not carried.is_empty():
		world.survival.broadcast_crates()

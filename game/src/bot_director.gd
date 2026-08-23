class_name BotDirector
extends Node
## The computer players: how many there are, where they are trying to get
## to, and everything they do on the way. Server-side only — a client is
## told where a bot is by the same sv_pos/cl_pos path that carries a human,
## so nothing on a client knows or cares which is which.
##
## Lives at World/Bots on the server. It holds NO wire protocol of its own:
## every RPC that touches bots (sv_add_bot, sv_remove_bot, sv_set_bot_team)
## stays on WorldNode and calls in here, so the world node remains the one
## file that describes what goes over the socket.

## The world these bots play in. Reaching back for world.store and
## world.player_state rather than holding copies is deliberate: a bot has
## to see exactly the terrain and the players everyone else sees.

var world: WorldNode = null

## The bots themselves: id -> {slot, pos, yaw, goal, path, skill, ...}.
##
## Their ids are Game.player_id(1, slot) — peer 1, because the server owns
## them — so they sit in Game.roster beside the humans, replicate through
## the same position channel, and every system that walks the roster picks
## them up for free.

var roster: Dictionary = {}

var _next_slot := 100

## Guards re-entry, not just repetition: `spawn()` ends in
## `redistribute()`, which broadcasts the roster, which comes back
## round to the roster-changed handler that called this. Without the flag
## the `roster.is_empty()` test stops it after the FIRST bot.

var _opening_done := false

## Bot shots in flight, read by the world when it draws them. They travel
## exactly like a player's orb — straight
## line at the weapon's speed, stopped by solid blocks, hitting whatever
## they actually touch — because a player's orb is simulated by the
## shooter's client, and a bot has no client to do it.

var orbs: Array = []

func ensure_opening() -> void:
	if not multiplayer.is_server() or _opening_done:
		return
	if not roster.is_empty():
		_opening_done = true      # somebody added their own; leave it
		return
	# Only once somebody real is here. Bots on an empty server would be a
	# match nobody is watching, played to keep a field warm.
	var humans := false
	for id: String in Game.roster.keys():
		if not bool(Game.roster[id].get("bot", false)):
			humans = true
			break
	if not humans:
		return
	_opening_done = true
	for i in world.OPENING_BOTS:
		if Game.roster.size() >= Game.MAX_PLAYERS:
			break
		spawn()
	print("Opening computer players added: %d in world" % Game.roster.size())

## The first phonetic name nobody is using. Taking the FIRST free one
## rather than the next in sequence means removing Bravo and adding a
## computer back gives you Bravo again, not Zulu.
func _next_name() -> String:
	var taken := {}
	for entry: Dictionary in Game.roster.values():
		taken[str(entry.get("name", ""))] = true
	for candidate: String in Game.BOT_NAMES:
		if not taken.has(candidate):
			return candidate
	return "Robot %d" % (Game.roster.size() + 1)

func spawn() -> void:
	if Game.roster.size() >= Game.MAX_PLAYERS:
		return
	var slot := _next_slot
	_next_slot += 1
	var id := Game.player_id(1, slot)
	Game.roster[id] = {"peer": 1, "slot": slot, "name": _next_name(),
		"style": AvatarFactory.random_style(), "team": -1, "bot": true}
	var start := world.store.safe_stand(Vector3(world.spawn_pos), 8.0)
	roster[id] = {"slot": slot, "pos": start, "yaw": 0.0, "think": 0.0,
		"weapon": 13, "shoot_cd": 0.0, "goal": start}
	_apply_skill(roster[id])
	world.player_state[id] = {"pos": start, "treasures": 0, "name": Game.roster[id].name, "hp": 5}
	redistribute()

## Computer players fill up the emptiest team, in name order.
##
## This used to slice them into contiguous blocks of the same size and
## ignore the humans completely, so a team with three people on it got
## just as many computers as an empty one, and 10 computers over 4 teams
## came out 3/3/3/1. Now each one in turn joins whichever team has the
## fewest PLAYERS of any kind, ties going to the leftmost team — so the
## counts along the top of the team grid always explain what happened.
func unpin() -> void:
	for id: String in roster.keys():
		if Game.roster.has(id):
			Game.roster[id].erase("fixed")

func redistribute() -> void:
	var ids: Array = roster.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return str(Game.roster[a].name) < str(Game.roster[b].name))
	var counts: Array[int] = []
	counts.resize(world.team_count)
	# Humans are placed already and are never moved; they set the starting
	# imbalance the computers have to even out.
	for id: String in Game.roster.keys():
		if roster.has(id):
			continue
		var team := int(Game.roster[id].get("team", -1))
		if team >= 0 and team < world.team_count:
			counts[team] += 1
	# A computer somebody put on a team BY HAND stays there. It still
	# counts against that team, so the rest balance around it.
	var free_ids: Array = []
	for id: String in ids:
		if bool(Game.roster[id].get("fixed", false)):
			var team := int(Game.roster[id].get("team", -1))
			if team >= 0 and team < world.team_count:
				counts[team] += 1
				continue
		free_ids.append(id)
	for id: String in free_ids:
		var best := 0
		for t in world.team_count:
			if counts[t] < counts[best]:
				best = t
		Game.roster[id].team = best
		counts[best] += 1
	Game.cl_roster.rpc(Game.roster)

func _bot_nearest_enemy(id: String, pos: Vector3, radius: float) -> String:
	var best := ""
	var best_dist := radius
	for other: String in world.match_alive.keys():
		if other == id or world.downed_ids.has(other) or not world.teams_differ(id, other):
			continue
		var other_state: Dictionary = world.player_state.get(other, {})
		if other_state.is_empty():
			continue
		var d: float = pos.distance_to(other_state.pos)
		if d < best_dist:
			best_dist = d
			best = other
	return best

## How far away an enemy can still be covering a spot. Beyond this nobody
## is realistically shooting at you, whatever the sight lines.

const BOT_REVIVE_DANGER := 34.0
## The same test, for a body that belongs to a PERSON. Far braver, on
## purpose — see _bot_rescue_goal.
const BOT_REVIVE_DANGER_PERSON := 10.0
## How far a bot will travel to attempt a rescue at all.
const BOT_REVIVE_REACH := 34.0
## Team-mates this close to the body count as going in with you.
const BOT_REVIVE_CROWD := 18.0

## IS THIS SPOT UNDER FIRE? Not "is an enemy near it" — is an enemy near it
## WITH A CLEAR LINE TO IT.
##
## The distinction is the whole fix. Standing over a body takes three
## unbroken seconds in the open, so bots walking in while the shooter was
## still there just handed over a second knockout and then a third; play
## watched them queue up to do it. But a plain distance test is far too
## blunt in the other direction — gated on "no enemy within 30 blocks",
## computer players stopped reviving each other AT ALL, measured over a
## full battle royale: zero pick-ups in a round. That is not a fix, it is
## deleting the mechanic.
##
## Cover is what actually decides it, and cover is exactly what
## `clear_shot` already measures. An enemy twenty blocks off with a wall
## between you is not a problem; one at the same range across open ground
## is. So bots will now go in for a team-mate who fell behind something,
## and leave one lying in the open until the shooter moves — which is what
## a person does, and what was asked for: they should get to
## cover to get each other up.
func _under_fire(at: Vector3, ally: String, radius: float) -> bool:
	var eye := at + Vector3(0, 1.0, 0)
	for other: String in world.match_alive.keys():
		if world.downed_ids.has(other) or not world.teams_differ(ally, other):
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty():
			continue
		var epos: Vector3 = st.pos
		if epos.distance_to(at) > radius:
			continue
		if world.clear_shot(epos + Vector3(0, 1.4, 0), eye):
			return true
	return false

## Which body to go and pick up, or INF for none worth attempting.
##
## THE OLD RULE ALMOST NEVER SAID YES. One radius, 34 blocks, and a
## rescue was abandoned if any enemy anywhere inside it had a line to the
## body. On an open map in a busy round that is nearly always true, so
## computer players essentially never picked anybody up — reported as
## "none of my team mates will revive me", which was exactly right.
##
## The radius is now a judgement rather than a constant, and it turns on
## two things the old rule could not see:
##
## A PERSON IS WORTH MORE THAN A BOT. If the body is a human player, the
## bar drops a long way. A child lying on the floor for forty-five seconds
## while their computer team-mates decide it is a bit dangerous is the
## worst version of this game, and there is always another bot.
##
## AND A CROWD CHANGES THE ODDS. If other able team-mates are near the
## body too, going in is a group walking into a fight rather than one bot
## kneeling in the open — so the bar drops for that as well, and they
## arrive together, which is how it should have looked all along.
##
## Nearest first among equals, people before bots, so a bot does not walk
## past somebody to reach somebody further away.
func _bot_rescue_goal(id: String, pos: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_rank := INF
	for mate: String in world.downed_ids.keys():
		if mate == id or world.teams_differ(id, mate) \
				or not world.player_state.has(mate):
			continue
		var body: Vector3 = world.player_state[mate].pos
		var away := pos.distance_to(body)
		if away >= BOT_REVIVE_REACH:
			continue
		var is_person := not bool(Game.roster.get(mate, {}).get("bot", false))
		var danger := BOT_REVIVE_DANGER
		if is_person:
			danger = BOT_REVIVE_DANGER_PERSON
		elif _mates_near(mate, body) >= 2:
			danger = BOT_REVIVE_DANGER * 0.5
		# Only the BODY is tested, not the walk in. Testing the bot's own
		# position too sounds more careful and is actually fatal: a bot in
		# a firefight anywhere then never goes for anybody, and revives
		# stopped happening at all.
		if _under_fire(body, id, danger):
			continue
		# People first, then whoever is closest. The 1000 is simply bigger
		# than any distance on this map.
		var rank := away + (0.0 if is_person else 1000.0)
		if rank < best_rank:
			best_rank = rank
			best = body
	return best

## How many able team-mates are already close to this body — the ones who
## could be going in with you.
func _mates_near(mate: String, body: Vector3) -> int:
	var count := 0
	for other: String in world.match_alive.keys():
		if other == mate or world.downed_ids.has(other) \
				or world.teams_differ(mate, other):
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if not st.is_empty() and Vector3(st.pos).distance_to(body) < BOT_REVIVE_CROWD:
			count += 1
	return count

## Where a knocked-down computer player drags itself. Towards the nearest
## team-mate who could actually pick it up, or failing that directly away
## from whoever put it there. A crawl covers very little ground, so this is
## a few blocks of sense, not an escape.
func _bot_cover_goal(id: String, pos: Vector3) -> Vector3:
	var mate_at := Vector3.INF
	var mate_d := 20.0
	for other: String in world.match_alive.keys():
		if other == id or world.downed_ids.has(other) or not world.teams_differ(id, other):
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty():
			continue
		var d: float = pos.distance_to(st.pos)
		if d < mate_d:
			mate_d = d
			mate_at = st.pos
	if mate_at != Vector3.INF:
		return mate_at
	# Nobody coming: head for your own flag. You will not crawl the whole
	# way, but you will crawl the right way — and in capture the flag your
	# own base is where help lives, so this is both "get to cover" and
	# "get home". Knocked-down players standing exactly where they fell was
	# one of the things that read as broken.
	if world.ctf.active():
		var team := int(Game.roster.get(id, {}).get("team", -1))
		var mine: Dictionary = world.ctf._flags.get(team, {})
		var home: Vector3 = mine.get("home", Vector3.INF)
		if home != Vector3.INF:
			return home
	var threat := _bot_nearest_enemy(id, pos, 30.0)
	if threat != "":
		var away: Vector3 = pos - Vector3(world.player_state[threat].pos)
		away.y = 0.0
		if away.length() > 0.01:
			return pos + away.normalized() * 12.0
	return pos

## A TEAM SPLITS ITSELF UP. Seats are sorted and fixed for the round, so
## every one of these is stable: a bot keeps the same job and the same
## target all round instead of the whole side changing its mind at once.
##
## One keeper per three players, capped at two — below three nobody stays
## home, because a pair with one of them sat at the flag is one attacker,
## and watching your own side not attack was the original complaint.
func _bot_ctf_keepers(team: int) -> int:
	return clampi(world.ctf.seats_of(team).size() / 3, 0, 2)

func _bot_ctf_defends(id: String, team: int) -> bool:
	var seat := world.ctf.seats_of(team).find(id)
	return seat >= 0 and seat < _bot_ctf_keepers(team)

## WHICH ENEMY FLAG THIS ONE IS GOING FOR.
##
## Not "the nearest", which is what it was, and which meant a team moved as
## a single lump: everybody picked the same flag because everybody was
## standing in the same place when they picked. A whole side
## leave together for the near base while blue walked into his — and blue
## did the same thing for the same reason, because his base was nearest to
## theirs.
##
## Raiders are dealt round-robin across the flags that are actually
## standing, in team order, so a side of four with three enemies puts
## somebody on each. `nil` (-1) when every enemy flag is already off its
## pole and there is nothing to run at.
func _bot_ctf_target_team(id: String, team: int) -> int:
	var standing: Array = []
	for other_team: int in world.ctf._flags.keys():
		if other_team == team:
			continue
		if int(world.ctf._flags[other_team].back_at) > 0:
			continue
		standing.append(other_team)
	if standing.is_empty():
		return -1
	standing.sort()
	# Which raider am I? Seats below the keeper count are minding the shop.
	var seat := world.ctf.seats_of(team).find(id)
	var raider := maxi(seat - _bot_ctf_keepers(team), 0)
	return int(standing[raider % standing.size()])

## WHAT A COMPUTER PLAYER IS ACTUALLY TRYING TO DO IN CAPTURE THE FLAG.
##
## There was nothing here at all: the goal ladder went storm, flee, revive,
## loot, hunt, wander, and not one rung of it mentioned a flag. So a round
## of capture the flag was twelve bots wandering around a field with two
## flags nobody was playing for, and any capture that happened was one of
## them blundering into a pole. That is what "the bots are pretty shitty"
## was.
##
## Returns Vector3.INF when it has nothing to say — no teams, no flags, or
## an attacker whose targets have all been taken already — and the caller
## falls through to hunting.
func ctf_goal(id: String, pos: Vector3) -> Vector3:
	if world.ctf._flags.is_empty():
		return Vector3.INF
	var team := int(Game.roster.get(id, {}).get("team", -1))
	if team < 0:
		return Vector3.INF
	var mine: Dictionary = world.ctf._flags.get(team, {})
	var home: Vector3 = mine.get("home", Vector3.INF)
	# A GHOST WALKS HOME. Same rule a person plays by — get to your own
	# flag and tag up. It used to have no idea where home was: a knocked
	# out bot wandered at random until an eight-second timer teleported it
	# back, so on the field it looked like it had forgotten the way and was
	# trying to bring itself round on the spot.
	if world.ghost_ids.has(id):
		return home
	if _bot_ctf_defends(id, team) and home != Vector3.INF:
		# The keeper. Anyone closing on our flag is the job; otherwise
		# patrol around it.
		var raider := ""
		var raid_d := 30.0
		for other: String in world.match_alive.keys():
			if not world.teams_differ(id, other) or world.downed_ids.has(other):
				continue
			var st: Dictionary = world.player_state.get(other, {})
			if st.is_empty():
				continue
			var d: float = home.distance_to(st.pos)
			if d < raid_d:
				raid_d = d
				raider = other
		if raider != "":
			return world.player_state[raider].pos
		# ON PATROL, not on sentry duty. A fixed post meant a keeper
		# reached its spot and then stood perfectly still for the rest of
		# the round, which is indistinguishable from a broken bot — and
		# "they just sort of stand there" is the thing being fixed. Walk a
		# slow circle round the flag instead: about eighteen seconds a lap,
		# started at its own angle so two keepers are never in step.
		var ring := float(absi(id.hash()) % 1000) / 1000.0 * TAU \
			+ float(Time.get_ticks_msec()) * 0.00035
		return home + Vector3(cos(ring), 0, sin(ring)) * 3.5
	# The raider, on the flag it was dealt rather than whichever happens to
	# be closest.
	var target := _bot_ctf_target_team(id, team)
	if target < 0:
		return Vector3.INF
	var best: Vector3 = world.ctf._flags[target].get("pos", Vector3.INF)
	if best == Vector3.INF:
		return best
	return _bot_assault_goal(id, team, best)

## WHERE AN ATTACKER IS ACTUALLY GOING, which is not usually the flag.
##
## It used to be: the flag, plus a couple of blocks of jitter so two
## arriving at once did not stand on each other. That is the whole of what
## "they just run in a straight line at their target" was — they arrived
## one at a time, from wherever they happened to be, over the same ground
## every time, and that ground turned into a trench of craters from
## whoever tried it last.
##
## Now they go in groups, from a side of their own, avoiding wherever the
## last dozen knockouts happened — and one of each group goes underneath.
## The arithmetic for all of that is in BotSquads, which knows nothing
## about the world and can therefore be tested; this is the part that has
## to look things up.
func _bot_assault_goal(id: String, team: int, target: Vector3) -> Vector3:
	var seats: Array = world.ctf.seats_of(team)
	var seat := seats.find(id)
	var keepers := _bot_ctf_keepers(team)
	# Which attacker am I, counting past the ones minding the shop.
	var index := maxi(0, seat - keepers)
	var attackers := maxi(1, seats.size() - keepers)
	var squad := BotSquads.squad_of(index)
	var squads := BotSquads.squad_count(attackers)
	var now := Time.get_ticks_msec()
	var bearing := BotSquads.attack_bearing(squad, squads, float(now) * 0.001,
		target, world.battle_scars)

	# The digger is not part of the gathering: it left earlier and it is
	# taking its own route. See _bot_sap.
	var bot: Dictionary = roster.get(id, {})
	var digging := BotSquads.is_sapper(index) and not bot.is_empty()
	if not bot.is_empty():
		bot.sapping = digging
		bot.sap_at = target
	if digging:
		return target

	var key := "%d:%d" % [team, squad]
	# ALREADY GOING IN: keep going. Without this a squad that reached the
	# push and then lost a member would drop back to gathering, walk out
	# to the rally, and come in again — visible as an attack that turns
	# round and leaves half way.
	if now < int(_squad_push_until.get(key, 0)):
		return _bot_fan_out(id, target)

	var rally := BotSquads.point_on_bearing(target, bearing, BotSquads.RALLY_RANGE)
	rally = world.store.clamp_inside(rally, 4)
	rally.y = float(world.store.surface_y(floori(rally.x), floori(rally.z))) + 1.0

	if not _squad_since.has(key):
		_squad_since[key] = now
	var waited := float(now - int(_squad_since[key])) * 0.001

	var here := 0
	var size := 0
	for other_v: Variant in seats:
		var other := str(other_v)
		var other_seat := seats.find(other)
		if BotSquads.squad_of(maxi(0, other_seat - keepers)) != squad:
			continue
		size += 1
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty() or world.downed_ids.has(other):
			continue
		if Vector3(st.pos).distance_to(rally) < BotSquads.GATHER_RADIUS:
			here += 1
	if BotSquads.ready_to_push(here, size, waited):
		_squad_push_until[key] = now + SQUAD_PUSH_MS
		_squad_since.erase(key)
		return _bot_fan_out(id, target)
	return rally

## A couple of blocks to one side of the flag, so a squad arriving
## together spreads around the mound instead of treading on each other.
func _bot_fan_out(id: String, target: Vector3) -> Vector3:
	var lane := float(absi(id.hash()) % 5) - 2.0
	return target + Vector3(lane, 0.0, float(absi(id.hash() >> 3) % 5) - 2.0)

func _bot_pick_goal(id: String, bot: Dictionary) -> Vector3:
	var pos: Vector3 = bot.pos
	# GETTING HOME COMES FIRST. Before the storm, before a fight, before
	# anything: if you are out of the round, the only thing that matters is
	# reaching your own flag and tagging back in. Nothing below this is a
	# job a ghost can do — it cannot shoot, cannot be shot, cannot pick
	# anyone up and cannot take a flag — so any other goal is a knocked-out
	# computer player wandering the map for no reason, which is exactly
	# what it looked like on the field.
	if world.ctf.active() and world.ghost_ids.has(id):
		var back := ctf_goal(id, pos)
		if back != Vector3.INF:
			return back
	# Knocked down: not a fight any more. Get off the skyline.
	if world.downed_ids.has(id):
		return _bot_cover_goal(id, pos)
	if world.match_phase == "BATTLE" and world.match_alive.has(id):
		# Storm first: get inside.
		if world.storm_radius > 0.0 and Vector2(pos.x - world.storm_center.x,
				pos.z - world.storm_center.z).length() > world.storm_radius - 8.0:
			var inward := (world.storm_center - Vector3(pos.x, 0, pos.z)).normalized() * 20.0
			inward.y = 0
			return pos + inward
		# Hurt? Break contact and look for loot instead of trading.
		var hp := int(world.player_state.get(id, {}).get("hp", 5))
		if hp <= 2:
			var threat := _bot_nearest_enemy(id, pos, 26.0)
			if threat != "":
				var away := (pos - Vector3(world.player_state[threat].pos)).normalized()
				return pos + away * 24.0 + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		# Revive a downed team-mate — BUT NOT INTO A FIREFIGHT.
		#
		# Standing over a body takes three unbroken seconds in the open, so
		# walking in while whoever put them there is still about just hands
		# over a second knockout, and then a third when the next one tries.
		# They were seen queueing up to do exactly that.
		#
		# The danger radius has to be a SHOOTING radius, not a stabbing
		# one. It was 13 blocks, which is nothing: the guns here reach
		# most of the way across a base and the bots' own sight range runs
		# to 55, so an enemy 20 blocks off with a clear line is still
		# killing whoever kneels down. It is 30 now, tested both around the
		# body and around the bot itself, because the walk in is as
		# exposed as the wait.
		#
		# And a bot on its last couple of hearts does not attempt a rescue
		# at all. It is the least likely to survive the attempt and the
		# most likely to become the next body.
		if hp > 2:
			var rescue := _bot_rescue_goal(id, pos)
			if rescue != Vector3.INF:
				return rescue
		# Loot when unarmed.
		if int(bot.weapon) == 13:
			var best_crate := Vector3.INF
			var best_d := 70.0
			for crate: Dictionary in world.crates_by_id.values():
				var d: float = pos.distance_to(crate.pos)
				if d < best_d:
					best_d = d
					best_crate = crate.pos
			if best_crate != Vector3.INF:
				return best_crate
		# CAPTURE THE FLAG IS AN OBJECTIVE MODE, so the objective outranks
		# picking fights. Raiders run at the nearest standing enemy flag and
		# the keeper minds its own — and either way they still shoot at
		# whatever crosses them on the way, because the firing code is
		# separate from this and fires at anything in sight. Hunting stays
		# below as the fallback for when every enemy flag is already off its
		# pole and there is nothing left to run at.
		if world.ctf.active():
			var objective := ctf_goal(id, pos)
			if objective != Vector3.INF:
				return objective
		# Hunt — swordsmen close in, shooters hold their preferred range.
		# NERVE decides whether they commit: a rookie mostly mills about
		# near the fight, a deadly one comes straight at you.
		var nerve: float = float(bot.get("nerve", 0.6))
		var enemy := _bot_nearest_enemy(id, pos, lerpf(16.0, 34.0, nerve))
		if enemy != "" and randf() < 0.35 + nerve * 0.65:
			var epos: Vector3 = world.player_state[enemy].pos
			var standoff := 1.2 if int(bot.weapon) == 13 \
				else randf_range(9.0, 14.0) * lerpf(1.35, 0.8, nerve)
			var jitter := lerpf(7.0, 1.5, nerve)
			return epos + (pos - epos).normalized() * standoff \
				+ Vector3(randf_range(-jitter, jitter), 0, randf_range(-jitter, jitter))
	# Otherwise wander somewhere nearby.
	return pos + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))

## True when a bot can walk from `pos` one step toward `dir` without a
## cliff-face climb or a swim: the ground ahead must be near walkable
## height and dry.
## Punch a hole through whatever a computer player has walked into.
##
## Two blocks tall at head height, right in front of them, and only
## through things a player could dig by hand — so they cannot tunnel out
## of a steel vault, but a hillside, a tree or somebody's wall will not
## hold them for ever. Rate-limited by the same cooldown as shooting so
## this cannot turn into a mining laser.
func _bot_dig_out(id: String, bot: Dictionary, pos: Vector3, dir: Vector2) -> void:
	if float(bot.get("dig_cd", 0.0)) > 0.0:
		return
	bot.dig_cd = 0.8
	if dir == Vector2.ZERO:
		return
	var ahead := Vector2(pos.x, pos.z) + dir.normalized() * 1.1
	var cleared: Array = []
	# Head height and one above, AND the step up — a bot at the bottom of
	# a pit needs the wall in front of it opened at the height it wants
	# to climb to, not just the height it is standing at.
	for dy in [0, 1, 2]:
		var cell := Vector3i(floori(ahead.x), floori(pos.y) + dy, floori(ahead.y))
		if not world.store.inside_world(cell.x, cell.z, 1):
			continue
		var block := world.store.get_block(cell)
		if block == Blocks.AIR or Blocks.is_liquid(block):
			continue
		if not world.can_carve(cell, block) or Blocks.hardness(block) >= 3:
			continue
		world.store.set_block(cell, Blocks.AIR)
		cleared.append(cell)
	if not cleared.is_empty():
		world.cl_batch.rpc(cleared, Blocks.AIR)

## BUILD YOUR WAY OUT. The last resort, after digging has failed.
##
## Digging opens a wall you can walk THROUGH. It does nothing about a hole
## you have to get UP out of — and after a night of computer players
## bombing each other the map is craters, so that is the shape most of them
## end up in. One match had half the roster alive and sitting at
## the bottom of holes; they had been stuck there long enough that the
## world had been rebuilt around them.
##
## Two moves, which between them cover it:
##
## BRIDGE — the next step is a drop rather than a wall, so lay a block at
## the level we are already walking on and carry on across. Nothing else
## in the bot code minds a drop (falls are free, deliberately), so this
## only fires when we are trying to leave and the only way out is over a
## gap.
##
## STAIRS — otherwise place a block in our own feet's cell. `_walk_y` then
## finds it as the floor and `_bot_settle_ground` lifts us onto it, one
## block per go. That is the pillar-up every Minecraft player does by
## reflex, and repeated it walks a bot straight up out of a crater; once
## its eyes clear the rim the ordinary pathfinder can see somewhere to go
## and takes over.
##
## Capped by `climb_left` so a wedged bot cannot build a tower into the
## sky: twelve blocks is deeper than anything a bomb digs, and the budget
## refills the moment it gets somewhere.

const BOT_CLIMB_BUDGET := 12

func _bot_build_out(id: String, bot: Dictionary, pos: Vector3, dir: Vector2) -> void:
	# A ghost cannot touch the world — it goes round, or it waits for the
	# BOT_RETURN_MS backstop.
	if world.ghost_ids.has(id):
		return
	if float(bot.get("build_out_cd", 0.0)) > 0.0:
		return
	bot.build_out_cd = 0.3
	if int(bot.get("climb_left", BOT_CLIMB_BUDGET)) <= 0:
		return
	var feet := floori(pos.y)
	# Candidates in order of preference. Bridging first when there really
	# is a gap, then the step up in our own column.
	var tries: Array = []
	if dir != Vector2.ZERO:
		var ahead := Vector2(pos.x, pos.z) + dir.normalized() * 1.1
		var ax := floori(ahead.x)
		var az := floori(ahead.y)
		if world.store.inside_world(ax, az, 1):
			# A GAP is somewhere you could stand that is well BELOW us.
			# "Nowhere to stand" (-1) is not a gap, it is a WALL — that is
			# solid rock with no headroom in it — and the first version
			# read the two as the same thing. In a pit, which is walls in
			# every direction, it therefore tried to bridge into the rock,
			# failed to place anything, and burned the cooldown doing it.
			# The stairs never got a turn, which is why bots sat in holes
			# laying the odd block sideways instead of climbing out.
			var gy := walk_y(ax, az, pos.y)
			if gy >= 0 and float(gy) < pos.y - 2.5:
				tries.append(Vector3i(ax, feet - 1, az))
			# A STEP UP, ahead at our own feet's level: its top ends up one
			# block above us, which is exactly a stair. Repeated as we walk
			# onto each one, this is a staircase out of a crater — far more
			# use than a one-wide tower, because you arrive at the rim
			# already walking in the direction you wanted to go.
			tries.append(Vector3i(ax, feet, az))
	# Last resort: a block in our own feet's cell, which lifts us one. The
	# pillar-up. In a pit with sheer sides there is nothing else to do.
	tries.append(Vector3i(floori(pos.x), feet, floori(pos.z)))
	for cell: Vector3i in tries:
		if not world.store.inside_world(cell.x, cell.z, 1):
			continue
		if cell.y <= 1 or cell.y >= WorldGen.CHUNK_H - 2:
			continue
		if world.store.get_block(cell) != Blocks.AIR:
			continue
		world.store.set_block(cell, Blocks.DIRT)
		bot.climb_left = int(bot.get("climb_left", BOT_CLIMB_BUDGET)) - 1
		world.cl_batch.rpc([cell], Blocks.DIRT)
		return

func _bot_step_ok(pos: Vector3, dir: Vector2) -> bool:
	var ahead := Vector2(pos.x, pos.z) + dir * 1.6
	var ax := floori(ahead.x)
	var az := floori(ahead.y)
	# Never walk off the map, whatever else is true.
	if not world.store.inside_world(ax, az, 1):
		return false
	if _water_at(ax, az):
		return true
	# Climbing more than a step is a wall. DROPPING IS FINE, however far:
	# jumping off a roof to get out of the storm is the right move, and
	# refusing left computer players standing on buildings watching it
	# close in on them. Getting OUT of a hole is a digging problem, not a
	# reason never to enter one — see _bot_path().
	var gy := walk_y(ax, az, pos.y)
	if gy < 0:
		return false
	return float(gy) - pos.y <= 1.6

## HOW FAR THE PLANNER LOOKS, how much work it will do getting there, and
## the biggest drop it is willing to route somebody off.
##
## The reach was 8 — a 17x17 box — which is enough to see round a building
## and out of a pit and nothing else. Anything bigger than that (a lake, a
## ridge, the side of a hill) is a concave trap: the bot walks straight at
## the goal, hits the obstacle, searches a box too small to contain a way
## round, finds nothing, and digs. 16 covers the things the terrain
## actually builds.
##
## The cost of the bigger box is paid back by FOLLOWING the path instead of
## re-deriving one step of it every 0.6s — see `_bot_replan`. A planned
## route is walked to the end, so the search runs a few times a minute per
## bot rather than twice a second.

const BOT_PATH_REACH := 16

const BOT_PATH_BUDGET := 700

## Drops are free to WALK off — jumping down to get somewhere is right, and
## refusing left computer players stuck on rooftops. But a planner that
## treats a ravine as a shortcut will happily route somebody into one they
## then have to dig out of, so it will not plan a fall bigger than this.

const BOT_PATH_MAX_DROP := 6

## PLAN A ROUTE, as a list of column centres to walk through.
##
## Breadth-first over the local heightmap: a move to a neighbouring column
## is allowed if it is at most one block UP and at most BOT_PATH_MAX_DROP
## down. Returns the chain to whichever explored column ends up nearest the
## goal — so even when the goal itself is unreachable the bot sets off the
## best way it can, rather than walking into the same wall again.
##
## This is what turns "blocked, try eight angles, give up" into actually
## going round things: an eight-angle probe only ever looks 1.6 blocks
## ahead, which cannot see round a corner, let alone out of a pit.
func _bot_path(pos: Vector3, goal: Vector3) -> Array:
	var start := Vector2i(floori(pos.x), floori(pos.z))
	var target := Vector2i(floori(goal.x), floori(goal.z))
	if start == target:
		return []
	var came: Dictionary = {start: start}
	var heights: Dictionary = {start: walk_y(start.x, start.y, pos.y)}
	var queue: Array = [start]
	var head := 0
	var best := start
	var best_d := float(start.distance_squared_to(target))
	var seen := 0
	while head < queue.size() and seen < BOT_PATH_BUDGET:
		# Indexed rather than pop_front(): popping the front of a GDScript
		# Array is O(n), which quietly made the old search quadratic.
		var here: Vector2i = queue[head]
		head += 1
		seen += 1
		var here_y: int = heights[here]
		if here == target:
			best = here
			break
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := Vector2i(here.x + off.x, here.y + off.y)
			if came.has(next):
				continue
			if absi(next.x - start.x) > BOT_PATH_REACH \
					or absi(next.y - start.y) > BOT_PATH_REACH:
				continue
			if not world.store.inside_world(next.x, next.y, 1):
				continue
			var next_y := walk_y(next.x, next.y, float(here_y))
			if next_y < 0:
				continue                              # nowhere to stand
			if next_y - here_y > 1:
				continue                              # a wall
			if here_y - next_y > BOT_PATH_MAX_DROP:
				continue                              # a cliff, not a step
			came[next] = here
			heights[next] = next_y
			queue.append(next)
			var d := float(next.distance_squared_to(target))
			if d < best_d:
				best_d = d
				best = next
	if best == start:
		return []                                     # boxed in completely
	# Walk the chain back, then reverse it into the order to walk.
	var chain: Array = []
	var step: Vector2i = best
	while step != start:
		chain.append(Vector3(float(step.x) + 0.5,
			float(heights[step]) + 1.0, float(step.y) + 0.5))
		var prev: Vector2i = came[step]
		if prev == step:
			break
		step = prev
	chain.reverse()
	return chain

## Ask for a new route, at most so often. The search is the expensive part
## of the bot tick, so it is rate-limited per bot rather than per frame.
func _bot_replan(bot: Dictionary, pos: Vector3, goal: Vector3, delta: float) -> void:
	bot.path_cd = float(bot.get("path_cd", 0.0)) - delta
	if float(bot.path_cd) > 0.0:
		return
	bot.path_cd = 0.6
	bot.path = _bot_path(pos, goal)
	bot.path_goal = goal

## THE FLOOR A BOT COULD STAND ON in this column, given it is currently
## at `from_y`. Returns -1 when there is nowhere to stand.
##
## This exists because surface_y() returns the TOPMOST block, which for
## anything with a roof on it is the roof. A computer player inside a
## castle therefore saw a wall in every direction — nothing was ever
## "one step up" from it — and, worse, the code that keeps a bot on the
## ground lerped it towards surface_y + 1, dragging it up through the
## ceiling onto the battlements. That is why they ended up standing on
## roofs, turning on the spot, at the exact same coordinates for the
## whole match.
##
## Scanning DOWN from just above the bot is also cheaper than surface_y,
## which starts at the top of the world.
func walk_y(wx: int, wz: int, from_y: float) -> int:
	var top := mini(int(from_y) + 2, WorldGen.CHUNK_H - 3)
	for y in range(top, 0, -1):
		var here := world.store.get_block(Vector3i(wx, y, wz))
		if here == Blocks.AIR or Blocks.is_liquid(here):
			continue
		# Two blocks of headroom, or it is not somewhere a body fits.
		if world.store.get_block(Vector3i(wx, y + 1, wz)) != Blocks.AIR:
			return -1
		if world.store.get_block(Vector3i(wx, y + 2, wz)) != Blocks.AIR:
			return -1
		return y
	return -1

func _water_at(wx: int, wz: int) -> bool:
	return world.store.get_block(Vector3i(wx, WorldGen.SEA_LEVEL, wz)) == Blocks.WATER

## HOW GOOD IS THIS COMPUTER PLAYER?
##
## They were all identical: the same aim wobble, the same 1.1s between
## shots, the same 48-block eyesight, the same speed. A table of six
## clones is not a game — you learn one opponent and you have learned all
## of them.
##
## Each one now rolls a skill from 0 (hopeless) to 1 (nasty), and every
## number that matters is derived from it. The roll is deliberately
## spread across the range rather than clustered in the middle, so a
## table of six really does get a couple of pushovers and a couple you
## have to take seriously.
##
##   spread     how wide they miss by
##   (rate of fire comes from the WEAPON — see _bot_shot_delay)
##   sight      how far away they notice you
##   speed      how fast they move
##   nerve      how likely they are to close in rather than mill about

## FLYING, for the computer players allowed it (WorldNode.fly_allowed_for).
##
## Not simply "on if permitted": a bot that flew everywhere would float
## over the whole game at a fixed height and never be anywhere anybody
## could fight it. It uses flight the way a person does — to get somewhere
## it cannot walk to, and to get out of somewhere it is stuck in — and
## comes down when it arrives.
const BOT_FLY_HEIGHT := 7.0        ## cruise, in blocks above local ground
const BOT_FLY_SPEED := 5.0         ## how fast it climbs and descends
const BOT_FLY_CLIMB := 5.0         ## goal this far above ground: fly to it
const BOT_FLY_LAND_RANGE := 3.5    ## this close, flat: come down and finish on foot

## Squad bookkeeping, by "team:squad". `_squad_since` is when a squad
## started waiting at its rally; `_squad_push_until` is how long it stays
## committed once it has gone in, which is what makes the attacks come in
## waves rather than dithering.
var _squad_since: Dictionary = {}
var _squad_push_until: Dictionary = {}
const SQUAD_PUSH_MS := 26_000

## THE SAPPER digs to its objective instead of walking to it.
##
## Underneath, at a depth the fighting overhead cannot reach — which makes
## it the one attacker that does not care how cratered the ground is. It
## comes up wherever it arrives, and mostly it is a nuisance rather than a
## war winner, which is about right: the fun of it is that it happens at
## all.
const SAP_DEPTH := 4.0
const SAP_COOLDOWN := 0.55

const BOT_SKILL_NAMES := ["Rookie", "Steady", "Sharp", "Deadly"]

## How fast a computer player can work its trigger.
##
## `cadence` used to be a flat number of seconds between shots — 2.1 for a
## rookie down to 0.55 for a deadly one — and it took no notice whatever of
## the gun being held. So a bot with a Little Shooter, whose cooldown is
## 0.09s, still fired once every half second while the person shooting back
## at it fired six times in the same window. That is the whole reason bots
## read as target practice: you could stand in the open, hold the trigger
## and walk your fire onto one, and it would answer with a single pop.
##
## Now the WEAPON sets the rhythm, exactly as it does for a person holding
## the button down, and skill only stretches the gaps.
##
## The floor is a balance decision, not a technical one. A hit is one heart
## and a match starts with MATCH_HP of them, so a Little Shooter fired at
## its true 0.09s cooldown empties a player in well under a second.
##
## It was 0.26 with a 2.4x rookie stretch, which still is not a trigger
## held down: the worst bots answered a burst with a shot every two thirds
## of a second, and that is what they read as on the field — one pop, a
## pause, another pop, while you hosed them. A gap you can COUNT is the
## tell. At 0.15 the gun's own rhythm is what you hear, which is the point:
## the bots are supposed to be playing the same game with the same guns.
##
## What keeps them beatable is aim, not rate. Their shots are thrown off by
## `spread` below, they have to hold line of sight to fire at all, and the
## slow guns are still slow — a Big Shooter's 2.0s cooldown is untouched by
## any of this. If they ever need taking down a peg, widen the spread
## before slowing the trigger; a bot that misses is a fair fight, a bot
## that fires once every two seconds is a scarecrow.

const BOT_MIN_SHOT_GAP := 0.15

## Multiplier on the gap for the worst bot, sliding to 1.0 for the best.

const BOT_ROOKIE_SLACK := 1.7

## Seconds a bot waits between shots with the gun it is currently holding.
func _bot_shot_delay(bot: Dictionary) -> float:
	var weapon_cd := float(Weapons.spec(int(bot.get("weapon", 13))).get("cooldown", 1.0))
	var slack := lerpf(BOT_ROOKIE_SLACK, 1.0, float(bot.get("skill", 0.5)))
	return maxf(weapon_cd, BOT_MIN_SHOT_GAP) * slack

## Older saves have bots with no skill on them; give them one on sight so
## a restarted server does not field a table of identical clones.
func _ensure_skill(bot: Dictionary) -> void:
	if not bot.has("skill"):
		_apply_skill(bot)

func _apply_skill(bot: Dictionary) -> void:
	# Flat-ish across [0,1]: randf() alone bunches up once it is used to
	# drive several derived numbers at once.
	var skill := clampf((randf() + randf() * 0.6) / 1.6, 0.0, 1.0)
	bot.skill = skill
	# RADIANS OF SLOP, and the single most important number for how hard
	# the computer players are to play against.
	#
	# At 20 blocks, 0.016 rad is about a third of a block of wander against
	# a player 0.8 wide, so the best bots hit most of what they shoot at;
	# the worst, at 0.115, throw their shots two blocks wide and are mostly
	# noise. That spread across the roster is the point — some of them
	# should be frightening.
	#
	# It has been both too tight and too loose. 0.012 with the old
	# one-shot-every-two-thirds-of-a-second rate was survivable; the same
	# aim with the trigger held down was a laser, so it went to 0.026,
	# which was then too soft at the top end. 0.016 is deliberately
	# nearer the sharp end: if this needs backing off again, move THIS and
	# not the fire rate — a bot that misses is a fair fight, a bot that
	# fires once every two seconds is a scarecrow.
	bot.spread = lerpf(0.115, 0.016, skill)
	bot.sight = lerpf(22.0, 55.0, skill)        # blocks
	bot.speed = lerpf(2.7, 4.1, skill)          # blocks per second
	bot.nerve = lerpf(0.15, 0.9, skill)
	bot.tier = BOT_SKILL_NAMES[clampi(int(skill * 4.0), 0, 3)]

## Put a computer player back on the ground under it, and broadcast where
## it ended up. Both were written once inline at the bottom of the tick;
## the crawl path leaves early and needs them too, so they live here rather
## than as a second copy that can drift.
## WHICH WAY TO WALK THIS TICK. Vector2.ZERO means there is nowhere to go.
##
## Straight at the goal when that works, and it usually does — a planned
## route for every step across open ground would be all cost and no gain.
## The planner is for when the straight line is blocked, and once it has
## produced a route the bot FOLLOWS it: waypoint to waypoint, until the
## route runs out or the goal moves somewhere else.
##
## Following the route is the part that was missing. The old code asked for
## a route, used the first step of it, threw the rest away, and asked again
## 0.6 seconds later — so a bot rounding a corner re-derived the same
## corner over and over, and could oscillate between two routes that were
## equally good from slightly different positions. Now the search runs a
## few times a minute per bot instead of twice a second, which is what pays
## for the much bigger box it searches.
func _bot_steer(bot: Dictionary, pos: Vector3, goal: Vector3, delta: float) -> Vector2:
	var straight := Vector2(goal.x - pos.x, goal.z - pos.z)
	if straight.length() > 0.001:
		straight = straight.normalized()
	# A route in hand is worth following even if the straight line has just
	# come clear — abandoning it at the first opening is how a bot ends up
	# walking back into the bay it just escaped.
	var path: Array = bot.get("path", [])
	var planned: Vector3 = bot.get("path_goal", Vector3.INF)
	if not path.is_empty() and planned != Vector3.INF \
			and Vector2(planned.x - goal.x, planned.z - goal.z).length() > 8.0:
		path = []                       # chasing something else now
		bot.path = path
	if path.is_empty():
		if _bot_step_ok(pos, straight):
			return straight
		_bot_replan(bot, pos, goal, delta)
		path = bot.get("path", [])
		if path.is_empty():
			return Vector2.ZERO
	# Drop waypoints already reached, so a bot that overshoots or gets
	# knocked sideways picks up from the right place rather than doubling
	# back to a corner it is already past.
	while not path.is_empty():
		var wp: Vector3 = path[0]
		if Vector2(wp.x - pos.x, wp.z - pos.z).length() > 1.1:
			break
		path.remove_at(0)
	bot.path = path
	if path.is_empty():
		return straight if _bot_step_ok(pos, straight) else Vector2.ZERO
	var next: Vector3 = path[0]
	var leg := Vector2(next.x - pos.x, next.z - pos.z)
	if leg.length() < 0.001:
		return straight
	leg = leg.normalized()
	if _bot_step_ok(pos, leg):
		return leg
	# The route has gone stale — the world changed, or somebody blew a hole
	# in it. Throw it away and ask again.
	bot.path = []
	_bot_replan(bot, pos, goal, delta)
	var fresh: Array = bot.get("path", [])
	if fresh.is_empty():
		return straight if _bot_step_ok(pos, straight) else Vector2.ZERO
	var first: Vector3 = fresh[0]
	var hop := Vector2(first.x - pos.x, first.z - pos.z)
	if hop.length() < 0.001:
		return Vector2.ZERO
	hop = hop.normalized()
	return hop if _bot_step_ok(pos, hop) else Vector2.ZERO

## KEEPERS BUILD. Watching a defended mound work: "building defences
## around your flag is kind of a good idea and we should try and get
## computer players to sort of do that."
##
## So they do — a broken ring of chest-high cover around the mound, one
## block at a time, whenever nobody is attacking.
##
## THREE THINGS HERE ARE DELIBERATE AND LOAD-BEARING:
##
## They are PILLARS, not a wall — eight of them, seven blocks apart. This
## was a broken ring first, with two columns in five left open, and it put
## the stuck count straight back up: nothing can climb more than 1.6
## blocks, so a two-high ring is a barrier whatever gaps you leave in it,
## and bots pressed into it instead of finding the doors. Separate pillars
## cannot seal anything. Measured: ring 0.05-0.16 of bots not moving,
## pillars back to where it was before they existed.
##
## They are LOW. Two blocks is something to stand behind and shoot over.
##
## And they stand OUTSIDE the mound's protected radius, so they can be
## blown up. Inside it, `can_carve` would make every block indestructible
## and a keeper would slowly build an unbreakable fort around the
## objective, which is a different and much worse game.

const CTF_COVER_RADIUS := 9

const CTF_COVER_HEIGHT := 2

const CTF_COVER_SLOTS := 8

func _bot_build_cover(id: String, bot: Dictionary, team: int, delta: float) -> void:
	bot.build_cd = float(bot.get("build_cd", 0.0)) - delta
	if float(bot.build_cd) > 0.0:
		return
	bot.build_cd = randf_range(1.0, 1.9)
	var flag: Dictionary = world.ctf._flags.get(team, {})
	if flag.is_empty():
		return
	var home: Vector3 = flag.get("home", Vector3.INF)
	if home == Vector3.INF:
		return
	var pick := randi() % CTF_COVER_SLOTS
	var angle := TAU * float(pick) / float(CTF_COVER_SLOTS)
	var wx := floori(home.x + cos(angle) * float(CTF_COVER_RADIUS))
	var wz := floori(home.z + sin(angle) * float(CTF_COVER_RADIUS))
	if not world.store.inside_world(wx, wz, 2):
		return
	var ground := walk_y(wx, wz, home.y + 2.0)
	if ground < 0:
		return
	# One block per go, lowest gap first, so the ring rises evenly rather
	# than one tall pillar appearing before anything else exists.
	for up in CTF_COVER_HEIGHT:
		var cell := Vector3i(wx, ground + 1 + up, wz)
		if world.store.get_block(cell) != Blocks.AIR:
			continue
		var pairs: Array = []
		world.ctf.put(cell, world.TEAM_WOOL[team % world.TEAM_WOOL.size()], pairs)
		if not pairs.is_empty():
			world.cl_edits.rpc(pairs)
		return

## What height a flying computer player should be at, or INF for "it is
## not flying — use the ground rules".
##
## The one thing this must not do is fly ALL the time. A bot permanently
## at cruising height is out of everybody's reach and out of the game; the
## point of giving computer players wings is that they can come at a base
## over its wall instead of queueing at the door.
##
## So there are exactly three reasons to be in the air, and arriving ends
## all of them:
##   the goal is well above the ground here (a mound, a roof, a ledge)
##   walking has stopped working (blocked, or wedged twice over)
##   it is already flying and has not arrived yet — otherwise it would
##   drop out of the sky the moment it cleared the wall
func _bot_cruise_y(id: String, bot: Dictionary, flat: Vector2,
		floor_y: float, delta: float) -> float:
	# A ghost cannot touch the world and a downed bot is crawling; neither
	# has any business in the air.
	if world.downed_ids.has(id) or world.ghost_ids.has(id) \
			or not world.fly_allowed_for(id):
		bot.flying = false
		return INF
	var pos: Vector3 = bot.pos
	var goal: Vector3 = bot.goal
	var needs_height := goal.y - floor_y > BOT_FLY_CLIMB
	var walking_failed := float(bot.get("blocked_t", 0.0)) > 0.8 \
		or int(bot.get("wedged", 0)) >= 1
	var arrived := flat.length() < BOT_FLY_LAND_RANGE
	var flying := bool(bot.get("flying", false))
	if arrived and not needs_height:
		flying = false
	elif needs_height or walking_failed:
		flying = true
	bot.flying = flying
	if not flying:
		return INF
	# High enough to clear what stopped it, and high enough to be ABOVE
	# the goal rather than level with it — coming down onto a mound works,
	# flying into its side does not.
	var cruise := maxf(floor_y + BOT_FLY_HEIGHT, goal.y + 2.0)
	return move_toward(pos.y, cruise, BOT_FLY_SPEED * delta)

## Drive the tunnel forward one bite, on its own cooldown.
##
## Two moves and no more: sink until we are under the fighting, then chew
## towards the objective. Coming back up is not handled and does not need
## to be — the ground rises and falls, so a tunnel held at a fixed depth
## surfaces on its own soon enough.
func _bot_sap(id: String, bot: Dictionary, pos: Vector3) -> void:
	if float(bot.get("dig_cd", 0.0)) > 0.0:
		return
	var target: Vector3 = bot.get("sap_at", Vector3.INF)
	if target == Vector3.INF or world.ghost_ids.has(id) or world.downed_ids.has(id):
		return
	var ground := float(world.store.surface_y(floori(pos.x), floori(pos.z)))
	var want_y := minf(target.y - 1.0, ground - SAP_DEPTH)
	if pos.y > want_y + 1.0:
		# Not deep enough yet: take the floor out from under ourselves.
		bot.dig_cd = SAP_COOLDOWN
		var cleared: Array = []
		for dy in [-1, -2]:
			var cell := Vector3i(floori(pos.x), floori(pos.y) + dy, floori(pos.z))
			if not world.store.inside_world(cell.x, cell.z, 1):
				continue
			var block := world.store.get_block(cell)
			if block == Blocks.AIR or Blocks.is_liquid(block):
				continue
			if not world.can_carve(cell, block) or Blocks.hardness(block) >= 3:
				continue
			world.store.set_block(cell, Blocks.AIR)
			cleared.append(cell)
		if not cleared.is_empty():
			world.cl_batch.rpc(cleared, Blocks.AIR)
		return
	var ahead := Vector2(target.x - pos.x, target.z - pos.z)
	if ahead.length() < 0.001:
		return
	_bot_dig_out(id, bot, pos, ahead.normalized())

func _bot_settle_ground(bot: Dictionary, delta: float) -> void:
	var pos: Vector3 = bot.pos
	var gy := walk_y(floori(pos.x), floori(pos.z), pos.y)
	if gy < 0:
		gy = world.store.surface_y(floori(pos.x), floori(pos.z))
	var floor_y := float(gy) + 1.0
	if _water_at(floori(pos.x), floori(pos.z)):
		# Bots swim: ride the surface instead of sinking to the seabed.
		floor_y = maxf(floor_y, float(WorldGen.SEA_LEVEL) + 0.4)
	if pos.y > floor_y + 3.0:
		# Still airborne (the drop): glide down at human pace (-3,
		# matching Player's drop glide exactly).
		pos.y = maxf(pos.y - 3.0 * delta, floor_y)
	else:
		pos.y = lerpf(pos.y, floor_y, minf(1.0, delta * 8.0))
	bot.pos = pos

func _bot_send_pos(id: String, bot: Dictionary, _delta: float) -> void:
	if float(bot.get("send_t", 0.0)) <= 0.0:
		bot.send_t = 1.0 / 15.0
		world.cl_pos.rpc(id, Vector3(bot.pos), float(bot.yaw), 1)

## Is this computer player mid-way through picking somebody up? The same
## test the people use: a downed team-mate with a revive already running,
## close enough that this bot is what is keeping it running.
func _bot_holding_a_revive(id: String, pos: Vector3) -> bool:
	for rid: String in world.battle.revive_progress.keys():
		if rid == id or not world.downed_ids.has(rid) or world.teams_differ(id, rid):
			continue
		var st: Dictionary = world.player_state.get(rid, {})
		if st.is_empty():
			continue
		if pos.distance_to(st.pos) < world.REVIVE_RADIUS + 0.5:
			return true
	return false

func tick(delta: float) -> void:
	for id: String in roster.keys():
		if not Game.roster.has(id):
			continue
		var bot: Dictionary = roster[id]
		_ensure_skill(bot)
		# A LAST LINE OF DEFENCE, not a substitute for placing them
		# properly: whatever put a computer player outside the world, it
		# does not get to leave them there. Cheap — two integer compares
		# per bot per tick — and it means no future placement path can
		# strand one somewhere it has to be gone looking for.
		var bpos: Vector3 = bot.pos
		if absf(bpos.x) > float(world.store.half_extent()) + 32.0 \
				or absf(bpos.z) > float(world.store.half_extent()) + 32.0:
			var rescued := world.store.safe_stand(Vector3(world.spawn_pos), 10.0)
			bot.pos = rescued
			bot.goal = rescued
			bot.think = 0.0
			if world.player_state.has(id):
				world.player_state[id].pos = rescued
		bot.send_t = float(bot.get("send_t", 0.0)) - delta
		bot.shoot_cd = maxf(0.0, float(bot.shoot_cd) - delta)
		bot.dig_cd = maxf(0.0, float(bot.get("dig_cd", 0.0)) - delta)
		bot.build_out_cd = maxf(0.0, float(bot.get("build_out_cd", 0.0)) - delta)
		bot.think = float(bot.think) - delta
		var pos: Vector3 = bot.pos
		var downed := world.downed_ids.has(id)
		# A REVIVE HOLDS A COMPUTER PLAYER STILL TOO. People are frozen by
		# `Player.revive_locked()`, which runs on the client — and bots
		# have no client, they are moved right here. So the lock never
		# applied to them, and a downed bot went on dragging itself away
		# from the person kneeling down to help it: walking up to one
		# and watched it crawl off.
		#
		# `battle.revive_progress` is set by tick_revives(), which runs earlier
		# in the same tick and only while a rescuer is actually in range,
		# so this is exactly the same condition the people obey.
		if downed and world.battle.revive_progress.has(id):
			_bot_settle_ground(bot, delta)
			var held: Dictionary = world.player_state.get(id, {})
			if not held.is_empty():
				held.pos = bot.pos
			_bot_send_pos(id, bot, delta)
			continue
		# ...and a bot doing the reviving stands still as well, rather than
		# wandering off two seconds into a three-second job.
		if not downed and _bot_holding_a_revive(id, pos):
			_bot_settle_ground(bot, delta)
			var stood: Dictionary = world.player_state.get(id, {})
			if not stood.is_empty():
				stood.pos = bot.pos
			_bot_send_pos(id, bot, delta)
			continue
		if bot.think <= 0.0:
			bot.think = randf_range(0.35, 0.6)
			bot.goal = _bot_pick_goal(id, bot)
		# The tunnel advances every tick, not only when the bot is stuck.
		# That is the whole difference between a sapper and a bot that
		# happens to be digging its way out of a hole.
		if bool(bot.get("sapping", false)):
			_bot_sap(id, bot, pos)
		var to_goal: Vector3 = Vector3(bot.goal) - pos
		var flat := Vector2(to_goal.x, to_goal.z)
		# ARRIVAL IS NOT A FLAT MEASUREMENT. Standing on a ledge with your
		# goal four blocks below it is not having got there — but the flat
		# distance is zero, so the whole movement block below was skipped,
		# and being skipped it never noticed anything was wrong either. A
		# bot that walked onto the lip above a base doorway stopped there
		# for the rest of the round, and this is where several of them
		# were found at the end of a headless match.
		#
		# There is no useful direction to steer in from directly above, so
		# the answer is to stop insisting on this goal: take a fresh one
		# nearby and come at the place from somewhere else.
		if flat.length() <= 0.8 and absf(to_goal.y) > 3.0:
			bot.blocked_t = float(bot.get("blocked_t", 0.0)) + delta
			if float(bot.blocked_t) > 2.0:
				bot.blocked_t = 0.0
				bot.goal = world.store.clamp_inside(pos + Vector3(
					randf_range(-16, 16), 0, randf_range(-16, 16)), 6)
				bot.think = randf_range(0.4, 0.8)
		if flat.length() > 0.8:
			var dir := _bot_steer(bot, pos, Vector3(bot.goal), delta)
			# AIRBORNE: go straight there. The pathfinder walks the
			# ground, so a flying bot asking it for directions gets routed
			# round a wall it is currently above — or told there is no way
			# through at all, which is how it came to be flying.
			if bool(bot.get("flying", false)) and flat.length() > 0.001:
				dir = flat.normalized()
			# A DOWNED BOT CRAWLS. It used to be frozen solid — the whole
			# steering block was gated on `not downed` — so a knocked-down
			# computer player lay in the open, in the middle of whatever
			# had just shot it, until it was finished off or bled out. It
			# gets the same deal a person gets now: drag yourself out of
			# the line of fire and towards someone who can help.
			#
			# It gets the PATHFINDER too. It used to walk straight at its
			# goal and stop dead at the first thing in the way, which is
			# how a knocked-down team-mate ended up being watched pressing
			# into a wall trying to get back to the flag. What it does not
			# get is digging: you cannot tunnel while you are on the floor.
			if downed:
				if dir != Vector2.ZERO:
					var crawl := Player.DOWNED_CRAWL_SPEED
					pos.x += dir.x * crawl * delta
					pos.z += dir.y * crawl * delta
					bot.yaw = atan2(-dir.x, -dir.y)
				bot.pos = pos
				_bot_settle_ground(bot, delta)
				var down_state: Dictionary = world.player_state.get(id, {})
				if not down_state.is_empty():
					down_state.pos = bot.pos
				_bot_send_pos(id, bot, delta)
				continue
			if dir == Vector2.ZERO:
				# No way forward and no route round — boxed in, or in a
				# pit. Dig, and keep digging: they are carrying tools that
				# go through walls, and standing in a hole turning in
				# circles is the most obviously broken thing a computer
				# player can do. Dug towards the GOAL, since there is no
				# steering direction left to use.
				#
				# Not while out of the round, though. A ghost cannot touch
				# anything — that is the whole deal — so one walking home
				# must not chew its way through the landscape to get
				# there. It goes round, or the BOT_RETURN_MS backstop
				# brings it in.
				if not world.ghost_ids.has(id):
					_bot_dig_out(id, bot, pos, flat.normalized())
					# ...and if digging is not getting us anywhere, BUILD.
					# A crater is not a wall problem, it is an up problem,
					# and no amount of tunnelling sideways solves it.
					_bot_build_out(id, bot, pos, flat.normalized())
				bot.think = randf_range(0.3, 0.6)
			if dir != Vector2.ZERO:
				bot.blocked_t = 0.0
				# Moving again: the climbing budget is for getting OUT of
				# somewhere, so it refills the moment it worked.
				bot.climb_left = BOT_CLIMB_BUDGET
				var pace: float = float(bot.get("speed", 3.4))
				pos.x += dir.x * pace * delta
				pos.z += dir.y * pace * delta
				bot.yaw = atan2(-dir.x, -dir.y)
			else:
				# COULD NOT TAKE A STEP AT ALL: nothing forward, no route
				# round it, nothing worth digging. The wedge check below
				# cannot see this one — it only looks at bots more than 2
				# blocks from their goal, so a bot pinned just short of
				# somewhere it can never reach (on a ledge above a base
				# doorway, say) was too close to count as stuck and too far
				# to stop, and pushed at the same wall for the rest of the
				# round. Give it a couple of seconds, then send it somewhere
				# else entirely.
				#
				# Deliberately NOT done by loosening the wedge check's
				# distance instead: that fires on any bot merely moving
				# slowly, and re-rolling the goal of a bot that IS making
				# progress froze the entire field when it was tried.
				bot.blocked_t = float(bot.get("blocked_t", 0.0)) + delta
				if float(bot.blocked_t) > 2.5:
					bot.blocked_t = 0.0
					bot.goal = world.store.clamp_inside(pos + Vector3(
						randf_range(-16, 16), 0, randf_range(-16, 16)), 6)
					bot.think = randf_range(0.5, 1.0)
			# STUCK DETECTION, on its own clock rather than the wander
			# timer's. Distance covered is summed over a fixed window; if
			# a bot has barely moved while still wanting to be somewhere
			# else, it is wedged — pick a new goal, and if it keeps
			# happening, dig. Hanging this off `think` meant the check
			# only ever ran in the last moment of a wander, which is why
			# one could stand in a corner for a whole match.
			bot.moved = float(bot.get("moved", 0.0)) \
				+ pos.distance_to(Vector3(bot.get("last_pos", pos)))
			bot.last_pos = pos
			bot.stuck_t = float(bot.get("stuck_t", 0.0)) + delta
			if float(bot.stuck_t) > 1.1:
				if float(bot.moved) < 0.8 and flat.length() > 2.0:
					bot.wedged = int(bot.get("wedged", 0)) + 1
					if int(bot.wedged) >= 2:
						# Twice in a row against the same thing: go
						# through it rather than round it — and if that is
						# not working either, build.
						#
						# BUILDING HAS TO HAPPEN HERE and not only in the
						# no-direction-at-all branch below. A bot at the
						# bottom of a hole is not directionless: the
						# planner finds plenty of routes around the pit
						# FLOOR and hands one back, so the bot shuffles
						# from wall to wall, never trips the "nowhere to
						# go" case, and never builds itself a way out.
						# Being wedged is the signal that matters.
						# Ghosts never dig or build: they cannot touch the
						# world.
						if not world.ghost_ids.has(id):
							var want := Vector2(bot.goal.x - pos.x,
								bot.goal.z - pos.z)
							if want.length() > 0.001:
								want = want.normalized()
							_bot_dig_out(id, bot, pos, want)
							_bot_build_out(id, bot, pos, want)
						bot.wedged = 0
					bot.goal = world.store.clamp_inside(pos + Vector3(
						randf_range(-14, 14), 0, randf_range(-14, 14)), 6)
					bot.think = randf_range(0.3, 0.7)
				else:
					bot.wedged = 0
				bot.stuck_t = 0.0
				bot.moved = 0.0
		var gy := walk_y(floori(pos.x), floori(pos.z), pos.y)
		if gy < 0:
			gy = world.store.surface_y(floori(pos.x), floori(pos.z))
		var floor_y := float(gy) + 1.0
		if _water_at(floori(pos.x), floori(pos.z)):
			# Bots swim: ride the surface instead of sinking to the seabed.
			floor_y = maxf(floor_y, float(WorldGen.SEA_LEVEL) + 0.4)
		var cruise_y := _bot_cruise_y(id, bot, flat, floor_y, delta)
		if cruise_y < INF:
			pos.y = cruise_y
		elif pos.y > floor_y + 3.0:
			# Still airborne (the drop, or having just landed from a
			# flight): glide down at human pace (-3, matching Player's
			# drop glide exactly).
			pos.y = maxf(pos.y - 3.0 * delta, floor_y)
		else:
			pos.y = lerpf(pos.y, floor_y, minf(1.0, delta * 8.0))
		bot.pos = pos
		var state: Dictionary = world.player_state.get(id, {})
		if not state.is_empty():
			state.pos = pos
		# Fight whatever is in range.
		if world.match_phase == "BATTLE" and world.match_alive.has(id) and not downed:
			var enemy := _bot_nearest_enemy(id, pos, float(bot.get("sight", 48.0)))
			if enemy != "" and bot.shoot_cd <= 0.0:
				var epos: Vector3 = world.player_state[enemy].pos
				var muzzle := pos + Vector3(0, 1.4, 0)
				var aim := epos + Vector3(0, 1.0, 0)
				# Only take the shot if there's something to shoot at —
				# firing into a wall is just noise.
				if int(bot.weapon) != 13 and world.clear_shot(muzzle, aim):
					# The gun's rhythm, not a flat number. Jitter keeps it
					# from sounding like a metronome.
					bot.shoot_cd = _bot_shot_delay(bot) * randf_range(0.88, 1.14)
					var dir := (aim - muzzle).normalized()
					# Aim is imperfect, and HOW imperfect is what mostly
					# separates a rookie from a deadly one. A rookie's
					# rockets land near you; a deadly one's land on you.
					var slop: float = float(bot.get("spread", 0.03))
					dir = (dir + Vector3(randf_range(-slop, slop),
						randf_range(-slop * 0.7, slop * 0.7),
						randf_range(-slop, slop))).normalized()
					world.cl_orb.rpc(id, muzzle, dir, int(bot.weapon))
					# ...and the orb this fires is REAL: the server flies it
					# at the weapon's own speed and it only hurts what it
					# actually reaches. It used to deal damage the instant
					# it was fired, with the flying orb a mere decoration —
					# which is why people were dropping with nothing near
					# them, often through a wall. Now a computer player's
					# shot is the same shot yours is: it takes time to
					# arrive, walls stop it, and you can step out of the
					# way of the slow ones.
					if OS.get_environment("WORLD_ORB_DEBUG") == "1":
						print("BOTORB fired at %s, %.1f blocks away"
							% [enemy, pos.distance_to(epos)])
					spawn_orb(id, muzzle, dir, int(bot.weapon))
				elif int(bot.weapon) == 13 and pos.distance_to(epos) < 2.6:
					# Sword range: close enough to actually swing at you.
					bot.shoot_cd = _bot_shot_delay(bot) * 0.7
					world.cl_pos.rpc(id, pos, bot.yaw, 9)
					world.match_hurt(enemy, 1, pos, id)
		# A KEEPER WITH NOTHING TO SHOOT AT BUILDS. Only while it is
		# actually minding its own flag, actually in the round, and there
		# is nobody in sight — a bot laying blocks mid-firefight would be
		# a bot losing a firefight.
		if world.ctf.active() and not downed and world.match_alive.has(id) \
				and world.match_phase == "BATTLE":
			var my_team := int(Game.roster.get(id, {}).get("team", -1))
			if my_team >= 0 and _bot_ctf_defends(id, my_team) \
					and _bot_nearest_enemy(id, pos, 30.0) == "":
				_bot_build_cover(id, bot, my_team, delta)
		if bot.send_t <= 0.0:
			bot.send_t = 1.0 / 15.0
			world.cl_pos.rpc(id, pos, bot.yaw, 1)

func spawn_orb(shooter: String, from: Vector3, dir: Vector3, kind: int) -> void:
	var speed := float(Weapons.spec(kind).get("speed", 34.0))
	if speed <= 1.0:
		return                      # melee and utility weapons don't fly
	orbs.append({"pos": from, "vel": dir * speed, "shooter": shooter,
		"kind": kind, "age": 0.0})

func tick_orbs(delta: float) -> void:
	if orbs.is_empty():
		return
	for i in range(orbs.size() - 1, -1, -1):
		var orb: Dictionary = orbs[i]
		orb.age = float(orb.age) + delta
		var vel: Vector3 = orb.vel
		# These move up to 70 blocks a second, so step along the path in
		# short hops — a single jump per frame would tunnel through walls
		# and players alike.
		var travel := vel.length() * delta
		var hops := maxi(int(travel / 0.4), 1)
		var step := vel * (delta / float(hops))
		var dead := false
		for _h in hops:
			orb.pos = (orb.pos as Vector3) + step
			var at: Vector3 = orb.pos
			if at.y < -4.0 or at.y > WorldGen.CHUNK_H + 40.0:
				dead = true
				break
			if Blocks.is_solid(world.store.get_block(Vector3i(floori(at.x),
					floori(at.y), floori(at.z)))):
				if OS.get_environment("WORLD_ORB_DEBUG") == "1":
					print("BOTORB stopped by a block after %.2fs" % orb.age)
				dead = true
				break
			for pid: String in world.match_alive.keys():
				if pid == orb.shooter or world.downed_ids.has(pid) \
						or not world.teams_differ(orb.shooter, pid):
					continue
				var target: Vector3 = world.player_state.get(pid, {}).get("pos", Vector3.INF)
				if target.distance_to(at - Vector3(0, 0.8, 0)) < 1.1:
					if OS.get_environment("WORLD_ORB_DEBUG") == "1":
						print("BOTORB hit %s after %.2fs in flight" % [pid, orb.age])
					world.match_hurt(pid, 1, at, orb.shooter)
					dead = true
					break
			if dead:
				break
		if dead or float(orb.age) > 6.0:
			orbs.remove_at(i)


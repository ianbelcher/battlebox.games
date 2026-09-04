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


## Bot shots in flight, read by the world when it draws them. They travel
## exactly like a player's orb — straight
## line at the weapon's speed, stopped by solid blocks, hitting whatever
## they actually touch — because a player's orb is simulated by the
## shooter's client, and a bot has no client to do it.

var orbs: Array = []

## THE TEAM BLACKBOARD: what one side collectively knows and is doing.
##
## Everything here is a fix for the same thing — a computer player that can
## only see out of its own eyes and only reason about its own seat number.
## That is what makes a hundred of them read as a hundred separate
## accidents rather than as four teams: nobody is told anything, so nobody
## can join in with anything.
##
##   `_contacts[team]` is where enemies have actually been seen or felt,
##   with a timestamp — one shared list per side. A bot spotting somebody
##   posts it; a bot being SHOT posts it. Every defender then knows which
##   way the trouble came from without having a line of sight to it, which
##   is the difference between a base that faces the right way and eight
##   bots orbiting a pole.
##
##   `_intel[team]` is what falls out of that, worked out ONCE for the
##   whole side rather than once per bot: how many enemies are on our
##   doorstep and from what bearing, how many of us should therefore stay
##   home, and how many are already committed to each enemy flag. That
##   last one is what "go with them" reads.
##
## REFRESHED ON A TIMER, NOT PER BOT. This is the part that has to survive
## a hundred players: the whole thing is one pass over the roster a couple
## of times a second, and every bot then reads a dictionary instead of
## walking the roster itself. Doing it the obvious way — each bot counting
## its own team-mates when it picks a goal — is a hundred bots times a
## hundred players times twice a second, and that is how a server stops
## being able to hold a hundred players.
##
## NOTHING HERE IS PSYCHIC. A contact only exists because somebody on that
## team saw it or was hit by it, so digging a tunnel towards a base still
## works, and a sniper who has not fired yet has not been reported by
## anybody. That is deliberate: it is the same rule the shooting obeys, and
## sneaking has to keep being worth doing.
var _contacts: Dictionary = {}

var _intel: Dictionary = {}

var _intel_t := 0.0

## How often the blackboard is rebuilt. Twice a second is far quicker than
## anything on it changes and cheap enough not to notice.
const INTEL_EVERY := 0.5

## How long a contact report is worth anything. Longer than an individual
## bot's four-second memory of somebody it saw: a report is what the TEAM
## knows, and a base does not forget which side it was attacked from the
## moment the attacker steps behind a rock.
const CONTACT_MS := 14_000

## The most reports one side keeps. Small on purpose — this is a picture of
## where the fighting is, not a log — and it keeps every read of it cheap.
const CONTACTS_KEPT := 12

## Reports closer together than this are the same report. Without it a
## firefight that lasts four seconds fills the whole list with one place
## and the side goes blind everywhere else.
const CONTACT_MERGE := 7.0

## SOMEBODY ON THIS TEAM HAS SEEN OR FELT AN ENEMY HERE.
##
## Merged onto any recent report nearby rather than appended, so a running
## fight is one contact that keeps its position rather than twelve.
func report(team: int, at: Vector3) -> void:
	if team < 0:
		return
	var now := Time.get_ticks_msec()
	var list: Array = _contacts.get(team, [])
	for entry: Array in list:
		if Vector3(entry[0]).distance_to(at) < CONTACT_MERGE:
			entry[0] = at
			entry[1] = now
			return
	list.append([at, now])
	if list.size() > CONTACTS_KEPT:
		list.remove_at(0)
	_contacts[team] = list

## Rebuild every side's picture of the round. One pass, on a timer.
func _refresh_intel(delta: float) -> void:
	_intel_t -= delta
	if _intel_t > 0.0:
		return
	_intel_t = INTEL_EVERY
	var now := Time.get_ticks_msec()
	for team: int in _contacts.keys():
		var kept: Array = []
		for entry: Array in _contacts[team]:
			if now - int(entry[1]) < CONTACT_MS:
				kept.append(entry)
		_contacts[team] = kept
	# Who is standing, and where — one walk of the roster for every side.
	var sizes: Dictionary = {}
	var mates: Dictionary = {}
	for id: String in world.match_alive.keys():
		if world.out_ids.has(id):
			continue
		var team := int(Game.roster.get(id, {}).get("team", -1))
		if team < 0:
			continue
		sizes[team] = int(sizes.get(team, 0)) + 1
		if not world.downed_ids.has(id):
			var st: Dictionary = world.player_state.get(id, {})
			if not st.is_empty():
				var here: Array = mates.get(team, [])
				here.append(Vector3(st.pos))
				mates[team] = here
	# What each side is committed to attacking, from the bots' own
	# choices rather than from where they happen to be standing. Where
	# they are standing wobbles; what they have decided does not.
	var commit: Dictionary = {}
	for id: String in roster.keys():
		var chosen := int(roster[id].get("target_team", -1))
		if chosen < 0:
			continue
		var team := int(Game.roster.get(id, {}).get("team", -1))
		if team < 0:
			continue
		var by_team: Dictionary = commit.get(team, {})
		by_team[chosen] = int(by_team.get(chosen, 0)) + 1
		commit[team] = by_team
	var standing := _standing_flags()
	for team: int in sizes.keys():
		var home: Vector3 = world.ctf._flags.get(team, {}).get("home", Vector3.INF)
		var threat := 0
		var toward := Vector3.ZERO
		if home != Vector3.INF:
			for entry: Array in _contacts.get(team, []):
				var at: Vector3 = entry[0]
				if Vector2(at.x - home.x, at.z - home.z).length() > BotOrders.HOME_WATCH:
					continue
				threat += 1
				toward += Vector3(at.x - home.x, 0.0, at.z - home.z)
		var size := int(sizes[team])
		var mine := standing.duplicate()
		mine.erase(team)
		var base := SiegeRoles.keepers(size, world.ctf.elimination(),
			world.battle.holdout_pushing())
		var old: Dictionary = _intel.get(team, {})
		_intel[team] = {
			"threat": threat,
			# HOLD THE LAST BEARING when nothing is in sight. A harbour
			# that snaps back to due east the moment an attacker steps
			# behind a wall is a harbour that turns its back on them.
			"bearing": BotHarbour.bearing(Vector3.ZERO, toward,
				float(old.get("bearing", 0.0))),
			"keepers": BotOrders.keepers(size, base, threat, mine.size(),
				world.ctf.elimination()),
			"attackers": BotOrders.attackers(size, base, threat, mine.size(),
				world.ctf.elimination()),
			"standing": mine,
			"commit": commit.get(team, {}),
			"mates": mates.get(team, []),
		}

## Every enemy flag still on its pole, in team order. Team-agnostic: each
## side drops its own out of the list.
func _standing_flags() -> Array:
	var out: Array = []
	for team: int in world.ctf._flags.keys():
		var flag: Dictionary = world.ctf._flags[team]
		if int(flag.back_at) > 0 or bool(flag.get("out", false)):
			continue
		out.append(team)
	out.sort()
	return out

## SOMEBODY JUST SHOT THIS COMPUTER PLAYER.
##
## The one fact the bots never had. `MatchDirector.hurt` took hearts off
## and told nobody, so "they don't seem to care when you shoot them" was
## not indifference — there was nothing to be indifferent about.
##
## Four things happen, and the first is the one you see: it TURNS ROUND.
## Then it re-decides immediately rather than finishing the walk it was
## on, its eyes open past their natural range for a few seconds (see
## BotThreat.sight), and the whole team is told where the shot came from.
func alerted(id: String, from_pos: Vector3, attacker := "") -> void:
	if not roster.has(id):
		return
	var bot: Dictionary = roster[id]
	bot.threat_at = from_pos
	bot.threat_ms = Time.get_ticks_msec()
	bot.threat_id = attacker
	var to_them := Vector2(from_pos.x - float(Vector3(bot.pos).x),
		from_pos.z - float(Vector3(bot.pos).z))
	if to_them.length() > 0.01:
		to_them = to_them.normalized()
		bot.yaw = atan2(to_them.x, to_them.y)
	bot.think = 0.0
	report(int(Game.roster.get(id, {}).get("team", -1)), from_pos)

## A SHOT LANDED HERE AND MISSED. Everybody near enough to have heard it
## take the paint off is now aware of it.
##
## This is the other half of the sniping fix, and the half that matters
## when you are good at it: a hit alerts through `alerted`, but a MISS
## used to be silent, so walking your fire onto a bot from sixty blocks
## warned it of nothing until the moment it lost a heart.
##
## Only player shots come through here — bot fire is simulated in
## `tick_orbs` and there are hundreds of those in the air at once, so
## alerting on every one of them would be a per-orb walk of the whole
## roster. Bots hitting bots still report through `alerted`, which is the
## part that matters.
func shot_landed(shooter: String, at: Vector3, from_pos: Vector3) -> void:
	if shooter.is_empty():
		return
	for id: String in roster.keys():
		if id == shooter or not world.teams_differ(shooter, id):
			continue
		if world.downed_ids.has(id) or world.out_ids.has(id):
			continue
		if Vector3(roster[id].pos).distance_to(at) > BotThreat.NEAR_MISS:
			continue
		alerted(id, from_pos, shooter)

## A fresh round: forget last round's contacts, commitments and minefield.
func round_reset() -> void:
	_contacts.clear()
	_intel.clear()
	_mines.clear()
	for id: String in roster.keys():
		var bot: Dictionary = roster[id]
		bot.threat_ms = 0
		bot.target_team = -1
		bot.target_ms = 0
		bot.shield_left = SHIELD_BUDGET

## THE SEATS PEOPLE ARE NOT IN. A room has Game.player_limit seats, chosen
## with everything else before it existed; the computer players fill
## whichever of them nobody has sat in. Called whenever that could have
## changed — boot, a person arriving or leaving, the host moving the
## number from the Players tab — and it puts the count right in both
## directions: a person arriving in a full room takes a computer's seat,
## and a person leaving hands it back.
##
## Every seat that is not one of OURS counts as taken: a person, a
## computer player driven from somebody's client, anyone. What this owns
## is only the ones it spawned.
func fill() -> void:
	if not multiplayer.is_server():
		return
	var others := 0
	for id: String in Game.roster.keys():
		if not roster.has(id):
			others += 1
	var wanted := clampi(Game.player_limit - others, 0, Game.MAX_PLAYERS - others)
	var before := roster.size()
	while roster.size() < wanted:
		if not _place():
			break
	# The last-named go first, so removing seats takes Zulu before Alpha.
	while roster.size() > wanted:
		var ids: Array = roster.keys()
		ids.sort_custom(func(a: String, b: String) -> bool:
			return str(Game.roster[a].name) < str(Game.roster[b].name))
		remove(str(ids.back()))
	if roster.size() != before:
		print("Computer players: %d -> %d (%d seats, %d others)"
			% [before, roster.size(), Game.player_limit, others])
	redistribute()

## One computer player, out of the room for good: its body, its place in
## the round, its name on the roster.
func remove(id: String) -> void:
	roster.erase(id)
	world.player_state.erase(id)
	world.match_alive.erase(id)
	world.downed_ids.erase(id)
	world.hearts.erase(id)
	Game.roster.erase(id)

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
	if _place():
		redistribute()

## One more computer player in the roster, on no team yet. False when
## the room is full.
func _place() -> bool:
	if Game.roster.size() >= Game.MAX_PLAYERS:
		return false
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
	return true

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

## THE NEAREST ENEMY THIS ONE CAN ACTUALLY SEE.
##
## It was the nearest enemy full stop — distance alone, no line of sight —
## so a computer player noticed you through a hill, chased you through a
## wall, and turned to face you while you were stood behind a building it
## had never had a view of. At the top skill that reached fifty-five
## blocks in every direction, through anything.
##
## It is also what made the quiet walk pointless: creeping silences your
## footsteps, and they were never listening, they were looking through
## the map.
##
## Every caller wants the same thing and always did — who is chasing me,
## who do I run from, is anybody in sight before I start laying blocks —
## so the fix is one function. The comment at the cover-building site has
## said "there is nobody in sight" all along; it is true now.
##
## BOUNDED WORK. A line of sight test is a walk along the ray, and doing
## one per enemy per think for fifty players is real time. Candidates are
## sorted by distance and tested nearest-first, stopping at the first one
## visible — so the usual answer costs one, and the worst case (nobody
## visible at all) is capped. If the six nearest are all behind something,
## nobody is chasing you.
const SIGHT_TRIES := 6

## How long a computer player keeps going to the last place it saw
## somebody. Short: it is "go and look", not "follow you round a corner
## you left ten seconds ago".
const SIGHT_MEMORY_MS := 4000

func _bot_nearest_enemy(id: String, pos: Vector3, radius: float) -> String:
	var near: Array = []
	for other: String in world.match_alive.keys():
		if other == id or world.downed_ids.has(other) or not world.teams_differ(id, other):
			continue
		var other_state: Dictionary = world.player_state.get(other, {})
		if other_state.is_empty():
			continue
		var d: float = pos.distance_to(other_state.pos)
		if d < radius:
			near.append([d, other])
	if near.is_empty():
		return ""
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	# The same two points the SHOT is tested between, so "I can see you"
	# and "I can hit you" cannot disagree.
	var eye := pos + Vector3(0, 1.4, 0)
	var tried := 0
	for entry: Array in near:
		if tried >= SIGHT_TRIES:
			break
		tried += 1
		var at: Vector3 = world.player_state[entry[1]].pos
		if world.clear_shot(eye, at + Vector3(0, 1.0, 0)):
			# TELL THE REST OF THE SIDE. One bot laying eyes on somebody
			# is the only way a team ever learns anything, and it costs a
			# dictionary walk of at most a dozen entries — the sight test
			# above is a hundred times dearer and has already been paid.
			report(int(Game.roster.get(id, {}).get("team", -1)), at)
			return str(entry[1])
	return ""

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
		# ONE PAIR OF HANDS IS ENOUGH. Every able team-mate runs this same
		# search and every one of them used to pick the same nearest body,
		# so a single knockout pulled a whole side out of the fight to walk
		# to one spot — "they'll all stop fighting and then run out to try
		# and help that person". Picking somebody up is a one-player job.
		# Whoever is closest goes and the rest carry on with the round.
		if _closer_mate(id, mate, body, away):
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

## Is somebody else better placed to pick this body up than I am?
##
## Only counts team-mates who would ACTUALLY GO: able, still standing, and
## not minding a flag. A keeper being nearest is not a rescuer being
## nearest, and counting one as though it were leaves the body on the floor
## with everybody waiting for somebody who is never coming. People are not
## counted either — a person may well have their own ideas, and standing
## down on the assumption that a child is about to walk over is how nobody
## gets picked up at all.
func _closer_mate(id: String, mate: String, body: Vector3, away: float) -> bool:
	var team := int(Game.roster.get(id, {}).get("team", -1))
	var rivals: Array = []
	for other: String in world.match_alive.keys():
		if other == id or other == mate or world.downed_ids.has(other) \
				or world.out_ids.has(other) or world.teams_differ(id, other):
			continue
		if not bool(Game.roster.get(other, {}).get("bot", false)):
			continue
		if world.ctf.active() and team >= 0 and _bot_ctf_defends(other, team):
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty():
			continue
		rivals.append(Vector3(st.pos).distance_to(body))
	return not RallyRules.mine_to_take(away, rivals)

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

## How far a knocked-out player will look for somebody to pick them up.
const RALLY_REACH := 20.0

## Where a knocked-out computer player goes. Towards the nearest team-mate
## who could actually pick it up, or failing that away from whoever put it
## there.
##
## THE TEAM TEST HERE WAS INVERTED. It read `not teams_differ(...): continue`,
## which skips your own side and leaves you walking at the nearest ENEMY —
## and since there is usually no enemy within twenty blocks of where you
## went down, it fell through to "head for your own flag" nearly every
## time. That is the whole of "when a bot gets downed it seems to want to
## run all the way back to the flag as opposed to running to the nearest
## player": it was not choosing the flag, it was failing to find anybody.
##
## The consequence was worse than a wasted walk. Rescuers close on a body
## while the body walks away from them, so the two never meet and you end
## up chasing a knocked-out team-mate who runs straight past you. Both
## halves have to move towards each other for a revive to ever happen.
func _bot_cover_goal(id: String, pos: Vector3) -> Vector3:
	var my_team := int(Game.roster.get(id, {}).get("team", -1))
	var others: Array = []
	for other: String in world.match_alive.keys():
		if other == id:
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty():
			continue
		others.append({
			"team": int(Game.roster.get(other, {}).get("team", -1)),
			"pos": Vector3(st.pos),
			"downed": world.downed_ids.has(other),
			"out": world.out_ids.has(other)})
	var pick := RallyRules.pick_up_at(my_team, pos, others, RALLY_REACH)
	if pick >= 0:
		return others[pick].pos
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
## All of this is arithmetic on seat numbers and it lives in SiegeRoles,
## where it can be asked "does a real attack ever leave the base" without
## running a round and watching. That question is not rhetorical: it went
## wrong, and no test here could see it.
## HOW MANY OF THIS SIDE ARE MINDING THE SHOP RIGHT NOW.
##
## Read off the blackboard rather than computed here, for two reasons.
## It is a JUDGEMENT now — the mode's ratio corrected by how many enemies
## the side has actually seen on its own doorstep, which is BotOrders'
## job — and it has to be the SAME judgement for every member of the team
## on the same tick. Recomputing it per bot from live counts means two
## bots on one side can disagree about how many defenders there are, and
## then both of them think they are the third of two.
##
## Falls back to the flat ratio before the first blackboard refresh, which
## is the first half-second of a round.
func _bot_ctf_keepers(team: int) -> int:
	var known: Dictionary = _intel.get(team, {})
	if known.has("keepers"):
		return int(known.keepers)
	return SiegeRoles.keepers(world.ctf.seats_of(team).size(),
		world.ctf.elimination(), world.battle.holdout_pushing())

## How far from its own flag a keeper will go to pick somebody up.
const KEEPER_RESCUE_RANGE := 14.0

## May this one walk to a body, or is it minding a flag?
func _may_leave_post(id: String, body: Vector3) -> bool:
	if not world.ctf.active():
		return true
	var team := int(Game.roster.get(id, {}).get("team", -1))
	if team < 0 or not _bot_ctf_defends(id, team):
		return true
	var home: Vector3 = world.ctf._flags.get(team, {}).get("home", Vector3.INF)
	return home != Vector3.INF and home.distance_to(body) <= KEEPER_RESCUE_RANGE

func _bot_ctf_defends(id: String, team: int) -> bool:
	return SiegeRoles.job(world.ctf.seats_of(team).find(id),
		_bot_ctf_keepers(team)) == SiegeRoles.DEFEND

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
func _bot_ctf_target_team(id: String, team: int, pos: Vector3) -> int:
	var known: Dictionary = _intel.get(team, {})
	var standing: Array = known.get("standing", [])
	if standing.is_empty():
		# OUT IS NOT THE SAME AS AWAY. A flag taken for good in last flag
		# standing is marked `out` and never gets a `back_at`, so testing
		# only `back_at` left raiders being dealt at an eliminated team's
		# flag whose `pos` is INF — "nothing to do", and they wandered off.
		# Every capture idled a share of the survivors and the field went
		# quiet, which is exactly what "the moment they capture the flag
		# all the players hang back" was. `_standing_flags` tests both.
		standing = _standing_flags()
		standing.erase(team)
	if standing.is_empty():
		return -1
	var seats: Array = world.ctf.seats_of(team)
	var index := SiegeRoles.raider_index(seats.find(id), _bot_ctf_keepers(team))
	# THE SCOUTS GO OUT FIRST, one to each standing flag. Everything below
	# is about massing, and massing on its own leaves flags nobody ever
	# walks at — see BotOrders.scout_target.
	var scout := BotOrders.scout_target(index, standing.size())
	if scout >= 0:
		return int(standing[scout])
	var bot: Dictionary = roster.get(id, {})
	if bot.is_empty():
		return int(standing[index % standing.size()])
	var now := Time.get_ticks_msec()
	var chosen := int(bot.get("target_team", -1))
	var held := standing.has(chosen)
	if chosen >= 0 and not BotOrders.may_rethink(now - int(bot.get("target_ms", 0)), held):
		return chosen
	# WHERE IS MY SIDE GOING? Each candidate scored on how far it is and
	# how many of us have already committed to it. This is the whole of
	# "they should see what the other bots are doing and go with them".
	var commit: Dictionary = known.get("commit", {})
	var options: Array = []
	for other_v: Variant in standing:
		var other := int(other_v)
		var at: Vector3 = world.ctf._flags.get(other, {}).get("pos", Vector3.INF)
		options.append({
			"dist": 999.0 if at == Vector3.INF else pos.distance_to(at),
			"friends": int(commit.get(other, 0))})
	var cap := BotOrders.surge_cap(int(known.get("attackers", seats.size())),
		standing.size())
	var pick := BotOrders.pick_target(options, cap)
	if pick < 0:
		return -1
	bot.target_team = int(standing[pick])
	bot.target_ms = now
	return int(bot.target_team)

## HOW FAR OUT THE DEFENDERS STAND. Inside the cover ring at
## CTF_COVER_RADIUS, on the shoulder of the mound, so a defender is behind
## its own wall rather than in front of it. BotHarbour will open this out
## if the guard is too big to fit at that spacing.
##
## AND INSIDE THE FLAG'S OWN RADIUS, which is the part that was wrong. At
## a flat 6.0 the whole guard stood OUTSIDE CtfDirector.CTF_FLAG_TOUCH —
## so a lone keeper, which is what a small team posts, was six blocks from
## the pole it was supposedly minding and contested nothing. An attacker
## could walk onto the flag beside it. Reported as "nobody would protect
## the actual flag", and that is precisely what the number said.
##
## Derived from the touch radius so the two cannot drift apart: a defender
## holding its post is on the flag by construction, and a big guard opens
## outward from there rather than starting outside it.
const HARBOUR_RADIUS := CtfDirector.CTF_FLAG_TOUCH * 0.8

## THE THREE DISTANCES A DEFENDER LIVES BY, and they are three different
## questions that were all being answered with one number.
##
##   WATCH    how far out an enemy is worth REPORTING to the side. Wide:
##            a contact is what the team knows, and knowing costs nothing.
##   ENGAGE   how close one has to be before it is worth LEAVING THE POST
##            for. Just past the cover ring, so it means "at our wall"
##            rather than "somewhere on the horizon".
##   LEASH    and once moving, how far out it may ever get. Inside the
##            wall, so a defender meets an attacker AT the ring and never
##            beyond it.
##
## It used to walk at anything inside thirty blocks on a fourteen-block
## leash. Thirty is four times the mound, three times the cover ring and
## six times the radius that counts as the flag; fourteen puts a defender
## well outside its own wall with the pole unattended behind it. One
## attacker wandering past the far side of a base pulled the whole guard
## off it, which is "all the bots leave the flag and chase others".
##
## Ordered against the ring rather than written as bare numbers, and a
## unit test holds the ordering: a defender that can be drawn further out
## than its own wall is not defending anything.
const KEEPER_WATCH := 30.0
const KEEPER_ENGAGE := float(CTF_COVER_RADIUS) + 3.0
const KEEPER_LEASH := float(CTF_COVER_RADIUS) - 1.0

## A DEFENDED BASE, NOT A MERRY-GO-ROUND.
##
## What this replaces was a circle walked at one lap every eighteen
## seconds. It was written to fix a real thing — a fixed post meant a
## keeper arrived and then stood perfectly still, which is what a broken
## bot looks like — but a ring of computer players orbiting a pole is its
## own complaint, and it is the one that was made: "they just march around
## the flag, it's kind of dumb".
##
## So the guard forms a harbour instead. Each defender holds a sector of
## its own, the sectors cover the whole compass, seat zero always stands
## between the flag and wherever the side has last seen an enemy, and
## anybody with nothing to shoot at faces outwards along their own arc.
## Nobody walks a lap, because walking laps is how you get shot.
##
## Three things it does that the circle could not:
##
##   IT TURNS TO FACE THE TROUBLE. The bearing comes off the team's shared
##   contact reports, so an attack on one side of a base is met by the
##   whole position rotating towards it — including the defenders who
##   never saw anything themselves.
##
##   IT ENGAGES WITHOUT LEAVING. Anyone visible near the flag is closed
##   with, but on a leash: a defender that chases is a defender who has
##   gone.
##
##   IT KEEPS OUT OF ITS OWN WAY. Posts are pushed off any team-mate
##   already standing near them, so two defenders never end up in the same
##   block arguing about it.
func _bot_harbour_goal(id: String, team: int, pos: Vector3,
		home: Vector3) -> Vector3:
	var known: Dictionary = _intel.get(team, {})
	var bot: Dictionary = roster.get(id, {})
	# ANYONE IT CAN SEE comes first. This is a line-of-sight test and not
	# a distance one, and that is load-bearing: it is the last place in
	# this file that used to read an enemy's position through solid rock,
	# so digging a tunnel towards a base turned every defender to face you
	# through thirty blocks of ground. Sneaking has to be worth doing.
	#
	# The same eye and the same test the SHOT uses, so "I can see you" and
	# "I can hit you" cannot disagree — and the same cap on how many are
	# worth asking about, because a ray is not free.
	var near: Array = []
	for other: String in world.match_alive.keys():
		if not world.teams_differ(id, other) or world.downed_ids.has(other):
			continue
		var st: Dictionary = world.player_state.get(other, {})
		if st.is_empty():
			continue
		var d: float = home.distance_to(st.pos)
		if d < KEEPER_WATCH:
			near.append([d, other])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var eye := pos + Vector3(0, 1.4, 0)
	var looked := 0
	for entry: Array in near:
		if looked >= SIGHT_TRIES:
			break
		looked += 1
		var at: Vector3 = world.player_state[entry[1]].pos
		if world.clear_shot(eye, at + Vector3(0, 1.0, 0)):
			# SEEING SOMEBODY IS NOT A REASON TO GO TO THEM.
			#
			# Every enemy within thirty blocks used to be walked at, on a
			# fourteen-block leash. Thirty blocks is four times the mound,
			# three times the cover ring and six times the radius that
			# counts as the flag — so one attacker strolling past the far
			# side of a base drew the entire guard off it, and "all the
			# bots leave the flag and chase others" is exactly that.
			#
			# TELL THE SIDE EITHER WAY. The report is what the team knows
			# and it is worth having at the full watch distance; what is
			# gated is the WALKING. And a defender that holds its post is
			# not passive — the firing code is separate from this and
			# shoots at anything it has a line to, so standing still is
			# standing still and shooting.
			report(team, at)
			if float(entry[0]) <= KEEPER_ENGAGE:
				if not bot.is_empty():
					bot.erase("watch_yaw")
				return BotHarbour.leashed(home, at, KEEPER_LEASH)
			break
	# Nothing worth leaving the post for: hold the position.
	var count := maxi(1, _bot_ctf_keepers(team))
	var seat := maxi(world.ctf.seats_of(team).find(id), 0)
	var bearing := float(known.get("bearing", 0.0))
	var index := seat % count
	var want := home + BotHarbour.post(index, count, bearing, HARBOUR_RADIUS)
	if not bot.is_empty():
		# WATCH YOUR OWN ARC. Set here and used by the movement step once
		# the bot has arrived, because yaw otherwise comes from whichever
		# way it last walked — which at a post it has reached is nothing.
		# This is the difference between eight bots standing about and
		# eight sentries.
		bot.watch_yaw = BotHarbour.facing(index, count, bearing)
	want = BotHarbour.keep_apart(want, _nearby_mates(id, team, want),
		BotHarbour.MIN_GAP)
	want = world.store.clamp_inside(want, 4)
	# STANDING ROOM, NOT THE TOP OF THE PILE. `surface_y` returns the
	# highest block in the column, and by the time a siege is under way
	# that is the roof the defenders themselves put over the base — so a
	# post derived from it sends the whole guard climbing onto its own
	# lid. `walk_y` finds the floor a body actually fits on.
	var stand := walk_y(floori(want.x), floori(want.z), home.y + 2.0)
	if stand < 0:
		stand = world.store.surface_y(floori(want.x), floori(want.z))
	want.y = float(stand) + 1.0
	return want

## The team-mates close enough to `want` to be in the way of it.
##
## Off the blackboard, which already holds every side's standing members —
## so this is a walk of one team's positions rather than of the whole
## roster, and it happens when a goal is chosen rather than every frame.
## The bot's own position is in that list and is deliberately left there:
## it is at most one shove of its own and dropping it means matching
## floats.
const MATES_MIND := 6.0

func _nearby_mates(id: String, team: int, want: Vector3) -> Array:
	var out: Array = []
	var me: Vector3 = roster.get(id, {}).get("pos", Vector3.INF)
	for mate_v: Variant in _intel.get(team, {}).get("mates", []):
		var mate: Vector3 = mate_v
		if me != Vector3.INF and mate.distance_squared_to(me) < 0.01:
			continue
		if Vector2(mate.x - want.x, mate.z - want.z).length() < MATES_MIND:
			out.append(mate)
	return out

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
	# SOMEBODY WHO IS OUT WALKS HOME. Same rule a person plays by — get to your own
	# flag and tag up. It used to have no idea where home was: a knocked
	# out bot wandered at random until an eight-second timer teleported it
	# back, so on the field it looked like it had forgotten the way and was
	# trying to bring itself round on the spot.
	if world.out_ids.has(id):
		# ...ONLY IF THERE IS A WAY BACK IN. With reviving off, touching
		# your own flag does nothing, so every knocked-out computer player
		# on the side walked home and then stood on the pole for the rest
		# of the round. That is most of "two of the five teams were just
		# stuck on their flag, all running into it" — they were not stuck,
		# they had arrived, and arriving was worth nothing.
		#
		# WITH THE DOOR SHUT THEY STOP, and standing still is the whole
		# point rather than a detail. Returning INF sent them down the
		# rest of the ladder to the wander rung, so a side whose flag had
		# been taken spent the remainder of the round touring the map —
		# measured at all five of a knocked-out team still moving a
		# minute later.
		#
		# They cannot be hurt, cannot shoot and cannot take anything, so
		# every step is a body with no business on the field: it costs a
		# position broadcast, it walks through the fight, and the moment
		# anything fails to hide it, it is an opponent you can see and
		# cannot kill. Their round is over. Park them.
		if not world.ctf.flag_route_open(id):
			return pos
		return home
	if _bot_ctf_defends(id, team) and home != Vector3.INF:
		return _bot_harbour_goal(id, team, pos, home)
	# The raider, on the flag it was dealt rather than whichever happens to
	# be closest.
	var target := _bot_ctf_target_team(id, team, pos)
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
	var index := SiegeRoles.raider_index(seat, keepers)
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
		return _bot_fan_out(id, team, target)

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
		if BotSquads.squad_of(SiegeRoles.raider_index(other_seat, keepers)) != squad:
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
		return _bot_fan_out(id, team, target)
	return rally

## SPREAD AROUND THE MOUND, not onto one block of it.
##
## The lane off the bot's own id is what stops a squad walking in as a
## single file, and it is fixed per bot so the shape of the assault is
## stable rather than shimmering. What it cannot do is notice that the
## block it picked is where somebody else is already standing — an id
## hash knows nothing about anybody else — so a squad of three could and
## did arrive stacked.
##
## `keep_apart` is the fix, and it is the same rule the defenders use:
## look at the team-mates actually near the spot and shuffle off them.
## That is the "understand where they're standing in relation to the other
## bots" half of the ask, applied to the attack as well as the defence.
## AND NEVER OUT OF REACH OF THE THING THEY CAME FOR.
##
## Spreading out is right and this is what it cost when nothing bounded
## it: the lane offset is up to 2.83 blocks, `keep_apart` adds up to
## SPREAD_LIMIT on top, and the flag only counts as touched inside
## CtfDirector.CTF_FLAG_TOUCH. Worked out for a squad converging on one
## pole:
##
##     attackers at the flag   goal distance   inside 4.5?
##                         1            2.83   yes
##                         2            4.20   yes
##                         3            4.68   NO
##                         4            5.21   NO
##                         5            6.19   NO
##
## So from three attackers upward they shoved each other out of the only
## radius that scores, stood around it, and fought — and the better they
## got at arriving together, the less able they were to take anything.
## A whole round of last flag standing with not one flag captured, which
## is the mode not happening at all.
##
## The separation is kept — arriving stacked is its own problem — but the
## result is pulled back inside the radius afterwards. Derived from
## CTF_FLAG_TOUCH rather than written out, because the one thing that must
## never drift is this number against that one.
const ASSAULT_HOLD := CtfDirector.CTF_FLAG_TOUCH * 0.6

func _bot_fan_out(id: String, team: int, target: Vector3) -> Vector3:
	var lane := float(absi(id.hash()) % 5) - 2.0
	var want := target + Vector3(lane, 0.0, float(absi(id.hash() >> 3) % 5) - 2.0)
	want = BotHarbour.keep_apart(want, _nearby_mates(id, team, want),
		BotHarbour.MIN_GAP)
	var out := Vector3(want.x - target.x, 0.0, want.z - target.z)
	if out.length() > ASSAULT_HOLD:
		want = target + out.normalized() * ASSAULT_HOLD
		want.y = target.y
	return want

## WHAT TO DO ABOUT THE LAST SHOT THAT CAME AT US, or INF for "nothing
## recent enough to be worth acting on".
##
## The decision itself is BotThreat's — five inputs, five answers, and a
## truth table a unit test can walk. This is the part that has to look
## things up: whether the shooter can be seen from here right now, which
## is the same `clear_shot` the firing uses so that "I can see you" and
## "I can hit you" cannot disagree.
##
## A DEFENDER STILL DOES NOT LEAVE ITS POST. Everything below is leashed
## to the flag for anyone minding one, because "somebody shot at me from
## over there" is otherwise a perfect way to walk a whole guard off a base
## one bot at a time — which is the same failure the rescue rung had, and
## it was reported as a side defending a flag nobody was watching.
func _threat_goal(id: String, bot: Dictionary, pos: Vector3, hp: int) -> Vector3:
	var when := int(bot.get("threat_ms", 0))
	if when <= 0:
		return Vector3.INF
	var age := Time.get_ticks_msec() - when
	if BotThreat.stale(age):
		return Vector3.INF
	var at: Vector3 = bot.get("threat_at", Vector3.INF)
	if at == Vector3.INF:
		return Vector3.INF
	var armed := int(bot.get("weapon", 13)) != 13
	var seen := world.clear_shot(pos + Vector3(0, 1.4, 0), at + Vector3(0, 1.0, 0))
	var action := BotThreat.respond(age, hp, pos.distance_to(at), armed, seen,
		float(bot.get("nerve", 0.6)))
	bot.threat_act = action
	if action == BotThreat.IGNORE:
		return Vector3.INF
	# WHICH WAY ROUND THIS ONE GOES, fixed per bot rather than rolled, so
	# two of them flank opposite sides of the same shooter instead of
	# both drifting the same way and arriving as one target.
	var lane := 1.0 if (absi(id.hash()) % 2) == 0 else -1.0
	var want := at
	if action == BotThreat.RETURN_FIRE:
		# STAND AND TRADE. Not "walk at them" — the firing code below
		# does the shooting and it needs line of sight held, not chased.
		# A step to one side keeps them from being a stationary target
		# without giving up the angle they already have.
		var side := Vector3(pos.z - at.z, 0.0, at.x - pos.x)
		if side.length() > 0.001:
			side = side.normalized()
		want = pos + side * lane * 2.5
	else:
		want = BotThreat.move_to(action, pos, at, lane)
	# ...AND LAY A BLOCK TO GET BEHIND, if that is what the answer was.
	if BotThreat.wants_cover(action):
		_bot_build_shield(id, bot, pos, at)
	bot.erase("watch_yaw")
	var team := int(Game.roster.get(id, {}).get("team", -1))
	if world.ctf.active() and team >= 0 and _bot_ctf_defends(id, team):
		var home: Vector3 = world.ctf._flags.get(team, {}).get("home", Vector3.INF)
		if home != Vector3.INF:
			want = BotHarbour.leashed(home, want, KEEPER_LEASH)
	return world.store.clamp_inside(want, 4)

## HOW MANY BLOCKS ONE COMPUTER PLAYER WILL LAY AS COVER IN A ROUND, and
## how often. Small and slow on purpose: this is a sandbag thrown down
## while somebody shoots at you, not a building project, and a bot that
## can lay unlimited blocks anywhere turns an open field into a maze.
const SHIELD_BUDGET := 10
const SHIELD_EVERY := 1.1

## BUILD SOMETHING TO GET BEHIND, right now, between me and them.
##
## "Building barricades" as an instinct rather than a scripted routine:
## the only thing that triggers it is BotThreat deciding this bot should
## be behind something, so it happens where the fighting is instead of at
## a fixed spot somebody chose in advance.
##
## Two blocks, at chest and head height, one per go — one block is
## something to crouch behind and the second closes the gap you would be
## shot through. In the team's own colour where there is a team, so the
## field ends up showing you who has been fighting where.
func _bot_build_shield(id: String, bot: Dictionary, pos: Vector3,
		toward: Vector3) -> void:
	if float(bot.get("shield_cd", 0.0)) > 0.0:
		return
	bot.shield_cd = SHIELD_EVERY
	if int(bot.get("shield_left", SHIELD_BUDGET)) <= 0:
		return
	# The out cannot touch the world, and neither can somebody on the
	# floor: you do not lay bricks while being picked up.
	if world.out_ids.has(id) or world.downed_ids.has(id):
		return
	var dir := Vector2(toward.x - pos.x, toward.z - pos.z)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var ahead := Vector2(pos.x, pos.z) + dir * 1.6
	var wx := floori(ahead.x)
	var wz := floori(ahead.y)
	if not world.store.inside_world(wx, wz, 2):
		return
	var ground := walk_y(wx, wz, pos.y)
	if ground < 0:
		ground = floori(pos.y) - 1
	var team := int(Game.roster.get(id, {}).get("team", -1))
	var block: int = Blocks.DIRT if team < 0 \
		else world.TEAM_WOOL[team % world.TEAM_WOOL.size()]
	for up in [1, 2]:
		var cell := Vector3i(wx, ground + up, wz)
		if cell.y <= 1 or cell.y >= WorldGen.CHUNK_H - 2:
			continue
		if world.store.get_block(cell) != Blocks.AIR:
			continue
		world.store.set_block(cell, block)
		bot.shield_left = int(bot.get("shield_left", SHIELD_BUDGET)) - 1
		world.cl_batch.rpc([cell], block)
		return

func _bot_pick_goal(id: String, bot: Dictionary) -> Vector3:
	var pos: Vector3 = bot.pos
	# THE SENTRY ARC IS RE-EARNED EVERY TIME. Only the harbour sets it, so
	# clearing it here means a bot that has stopped being a defender —
	# gone to pick somebody up, been sent out by a thinning guard — stops
	# turning to face an arc it is no longer holding.
	bot.erase("watch_yaw")
	# GETTING HOME COMES FIRST. Before the storm, before a fight, before
	# anything: if you are out of the round, the only thing that matters is
	# reaching your own flag and tagging back in. Nothing below this is a
	# job somebody who is OUT can do — they cannot shoot, cannot be shot, cannot pick
	# anyone up and cannot take a flag — so any other goal is a knocked-out
	# computer player wandering the map for no reason, which is exactly
	# what it looked like on the field.
	if world.ctf.active() and world.out_ids.has(id):
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
		var hp := int(world.player_state.get(id, {}).get("hp", 5))
		# SOMEBODY IS SHOOTING AT ME. Above everything except the storm,
		# because it is the most urgent fact a bot can have and because it
		# used not to be a fact at all — see `alerted`. This is the rung
		# that answers both "you can zoom in and shoot at them and they
		# won't do anything" and "when they're being shot at they don't
		# seem to care".
		var answer := _threat_goal(id, bot, pos, hp)
		if answer != Vector3.INF:
			return answer
		# Hurt, with nobody having shot at us recently enough to have left
		# an alert — walked into a fight rather than been ambushed. Break
		# contact and look for loot instead of trading.
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
		#
		# AND A KEEPER DOES NOT LEAVE THE FLAG TO DO IT. This rung sits
		# above the objective rung, so one knockout anywhere on the map
		# emptied the base — which is how a side ends up defending a flag
		# nobody is watching. A keeper still picks up anyone who went down
		# ON the base, because that is not leaving the post, that is the
		# post.
		if hp > 2:
			var rescue := _bot_rescue_goal(id, pos)
			if rescue != Vector3.INF and _may_leave_post(id, rescue):
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
		# THEY REMEMBER WHERE YOU WENT, for a few seconds.
		#
		# Without this, needing line of sight makes them twitch: you step
		# behind a wall, they forget you instantly and wander off, you
		# step out, they charge again. That reads as broken rather than
		# as fair. Losing sight of somebody should mean going to where
		# they were and having a look, which is what a person does.
		if enemy != "":
			bot.saw_at = Vector3(world.player_state[enemy].pos)
			bot.saw_ms = Time.get_ticks_msec()
		elif int(bot.get("saw_ms", 0)) > 0 \
				and Time.get_ticks_msec() - int(bot.saw_ms) < SIGHT_MEMORY_MS:
			return Vector3(bot.get("saw_at", pos))
		if enemy != "" and randf() < 0.35 + nerve * 0.65:
			var epos: Vector3 = world.player_state[enemy].pos
			var standoff := 1.2 if int(bot.weapon) == 13 \
				else randf_range(9.0, 14.0) * lerpf(1.35, 0.8, nerve)
			var jitter := lerpf(7.0, 1.5, nerve)
			return epos + (pos - epos).normalized() * standoff \
				+ Vector3(randf_range(-jitter, jitter), 0, randf_range(-jitter, jitter))
	# NOTHING OF ITS OWN TO DO — so go where the side has seen something.
	#
	# This rung used to be a random walk, and with a hundred players and no
	# flags to organise around it is most of what a battle royale looks
	# like from the outside: "you run off and the other bots just run off
	# in random directions". They are not choosing to split up; nobody has
	# ever told them anything, so a random direction is the only one
	# available.
	#
	# A contact report is somebody on your own side having actually seen or
	# been shot by an enemy. Walking towards the freshest one near you is
	# what a person does when a fight starts across the field, and it costs
	# a walk of at most a dozen entries.
	var rally := _rally_point(id, pos)
	if rally != Vector3.INF:
		return rally
	return pos + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))

## How far a bot will walk towards somewhere its side has reported. Far
## enough to cross most of a map, short enough that a fight at the other
## end of the world is somebody else's.
const RALLY_TO_CONTACT := 90.0

## The freshest thing this side has seen that is worth walking to, spread
## off whoever is already going, or INF for "nobody has seen anything".
func _rally_point(id: String, pos: Vector3) -> Vector3:
	var team := int(Game.roster.get(id, {}).get("team", -1))
	if team < 0:
		return Vector3.INF
	var best := Vector3.INF
	var newest := 0
	for entry: Array in _contacts.get(team, []):
		var at: Vector3 = entry[0]
		if pos.distance_to(at) > RALLY_TO_CONTACT:
			continue
		if int(entry[1]) > newest:
			newest = int(entry[1])
			best = at
	if best == Vector3.INF:
		return best
	# NOT ONTO THE SAME BLOCK. Everybody on the side is reading the same
	# report, so without this they converge on one point and arrive as a
	# single target — which is the opposite of the problem but just as bad
	# to play against.
	var lane := float(absi(id.hash()) % 9) - 4.0
	var want := best + Vector3(lane, 0.0, float(absi(id.hash() >> 4) % 9) - 4.0)
	return BotHarbour.keep_apart(want, _nearby_mates(id, team, want),
		BotHarbour.MIN_GAP)

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
	# Somebody who is OUT cannot touch the world — they go round, or wait for the
	# BOT_RETURN_MS backstop.
	if world.out_ids.has(id):
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
## The highest a flying computer player will ever be above the ground it
## is over. Nothing worth reaching is further up than this, and without a
## ceiling two of them chasing each other climb forever.
const BOT_FLY_CEILING := 20.0

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
	# THE SAME SORT OF PACE AS A PERSON. It was 2.7 to 4.1 against a
	# player's 4.6, so every computer player in the game was slower than
	# everybody at the table and none of them could ever catch anyone.
	# Centred on Player.RUN_SPEED now, and still spread: the worst of them
	# are slower than you and the best are slightly quicker, which is what
	# makes it worth knowing which one you are being chased by.
	bot.speed = lerpf(4.4, 6.0, skill)          # blocks per second
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

## How high and how dense the ring gets, and it depends on the mode.
##
## In capture the flag a flag has to stay TAKEABLE — a base nobody can get
## into is a nil-all draw for the whole round — so it stays at a scatter of
## waist-high cover you can walk between.
##
## Last flag standing is the opposite game: holding what you built IS the
## mode, and there is a clock to stop two dug-in sides staring at each
## other forever. So the ring goes up to head height and twice as dense,
## which reads as a wall with gaps in it rather than eight lonely pillars.
## It is team wool either way, and wool digs out, so a wall is a delay and
## never a lock.
func _cover_height() -> int:
	return 3 if world.ctf.elimination() else 2

func _cover_slots() -> int:
	return 16 if world.ctf.elimination() else 8

## HOW MANY MINES A SIDE PUTS OUT, and how far from its own flag.
##
## "Putting down explosives around the place" — as something the defenders
## decide to do rather than something scripted into the map. A Boom Block
## laid on the ground is already a pressure mine in this game: the world
## arms it, and standing on it sets it off (see TerrainSim.tick_boom_traps).
## Nobody had ever used that on purpose.
##
## THEY GO WELL OUTSIDE THE WALL, and that is not decoration. Defenders
## hold the harbour at HARBOUR_RADIUS and the cover ring stands at
## CTF_COVER_RADIUS, so a minefield at twelve to sixteen blocks is beyond
## everything its own side stands on — otherwise a team spends the round
## blowing itself up, which is funny once.
##
## They are also VISIBLE: a red block sitting on open ground, in the lanes
## the attacks have been coming down. That is the right trade for a game
## children play — you can see it, you can shoot it from a distance, you
## can go round it — and it still makes walking straight at a base cost
## something.
##
## Few of them, and fewer in capture the flag, where a base has to stay
## takeable or the round is a nil-all draw.
const MINE_RING_MIN := 12.0
const MINE_RING_MAX := 16.0
const MINE_CLEAR_OF_MATES := 5.0

var _mines: Dictionary = {}

func _mine_allowance() -> int:
	return 8 if world.ctf.elimination() else 4

## Lay one, if there is a sensible place for it. True when something went
## down, so the caller can spend its build on the wall instead.
##
## Aimed down the bearing the side has actually been attacked from, spread
## either side of it, so a minefield grows where the fighting is rather
## than evenly round a circle nobody walks on.
func _bot_lay_mine(team: int, home: Vector3) -> bool:
	if int(_mines.get(team, 0)) >= _mine_allowance():
		return false
	var bearing := float(_intel.get(team, {}).get("bearing", 0.0)) \
		+ randf_range(-1.1, 1.1)
	var out := randf_range(MINE_RING_MIN, MINE_RING_MAX)
	var wx := floori(home.x + cos(bearing) * out)
	var wz := floori(home.z + sin(bearing) * out)
	if not world.store.inside_world(wx, wz, 2):
		return false
	var ground := walk_y(wx, wz, home.y + 3.0)
	if ground < 0:
		return false
	var cell := Vector3i(wx, ground, wz)
	var under := world.store.get_block(cell)
	# Only ever laid in ground somebody could dig anyway. It replaces the
	# surface block, so it must not be swallowing anything protected — and
	# `can_carve` is the one place in the game that answers that.
	if under == Blocks.AIR or Blocks.is_liquid(under) or not world.can_carve(cell, under):
		return false
	if under == Blocks.BOOM:
		return false
	# NOT UNDER OUR OWN FEET. A team-mate standing there when it arms is
	# a mine laid for nobody.
	var here := Vector3(float(wx) + 0.5, float(ground) + 1.0, float(wz) + 0.5)
	for mate_v: Variant in _intel.get(team, {}).get("mates", []):
		if Vector3(mate_v).distance_to(here) < MINE_CLEAR_OF_MATES:
			return false
	world.store.set_block(cell, Blocks.BOOM)
	world.terrain._boom_armed[cell] = Time.get_ticks_msec() + world.BOOM_ARM_MSEC
	world.cl_batch.rpc([cell], Blocks.BOOM)
	_mines[team] = int(_mines.get(team, 0)) + 1
	return true

## The cooldown is counted down with the others in the step, and CHECKED
## by the caller before it pays for a sight test — see there.
func _bot_build_cover(id: String, bot: Dictionary, team: int, _delta: float) -> void:
	if float(bot.get("build_cd", 0.0)) > 0.0:
		return
	# Quicker in a siege: the whole round is whether the wall went up in
	# time, so a defender that lays a block every second and a half is a
	# defender that loses.
	bot.build_cd = randf_range(0.45, 0.9) if world.ctf.elimination() \
		else randf_range(1.0, 1.9)
	var flag: Dictionary = world.ctf._flags.get(team, {})
	if flag.is_empty():
		return
	var home: Vector3 = flag.get("home", Vector3.INF)
	if home == Vector3.INF:
		return
	# A SHARE OF THE BUILDING TURNS GO ON THE MINEFIELD instead of the
	# wall. One in five: the wall is still what a defender mostly does,
	# and a side that spent every turn laying charges would have a
	# minefield and no cover to shoot from behind.
	if randf() < 0.2 and _bot_lay_mine(team, home):
		return
	var slots := _cover_slots()
	var pick := randi() % slots
	var angle := TAU * float(pick) / float(slots)
	var wx := floori(home.x + cos(angle) * float(CTF_COVER_RADIUS))
	var wz := floori(home.z + sin(angle) * float(CTF_COVER_RADIUS))
	if world.store.inside_world(wx, wz, 2):
		var ground := walk_y(wx, wz, home.y + 2.0)
		# One block per go, lowest gap first, so the ring rises evenly
		# rather than one tall pillar appearing before anything else.
		if ground >= 0:
			for up in _cover_height():
				if _lay(team, Vector3i(wx, ground + 1 + up, wz)):
					return
	# WALLS FIRST, THEN A ROOF. A ring with open sky over it is a wall
	# with a door in the ceiling: everyone here can fly, and the way a
	# base actually falls is somebody coming in over the top of it. So
	# once the wall has no gaps left to fill, the same builder starts
	# putting a lid on.
	if world.ctf.elimination():
		_roof_over(team, home)

## One block, if that cell is empty. True when something went down.
func _lay(team: int, cell: Vector3i) -> bool:
	if world.store.get_block(cell) != Blocks.AIR:
		return false
	var pairs: Array = []
	world.ctf.put(cell, world.TEAM_WOOL[team % world.TEAM_WOOL.size()], pairs)
	if pairs.is_empty():
		return false
	world.cl_edits.rpc(pairs)
	return true

## How far across the lid goes. Smaller than the mound on purpose: the
## outer ring of the base stays open to the sky, so the way in is to walk
## up under the edge of it rather than to be sealed out.
const CTF_ROOF_RADIUS := 5

## A LID OVER THE FLAG, two blocks clear of the top of the pole.
##
## Clear of it because the beacon is how you find a base from across the
## map, and a roof sitting on the pole hides the one thing that is
## supposed to be visible. Two blocks up leaves it glowing over the top.
##
## Team wool, like the walls, and wool digs out — so this is a delay and a
## nuisance, never a seal. That matters: a base nobody can get into is a
## nil-all draw for the whole round.
func _roof_over(team: int, home: Vector3) -> void:
	var y := int(home.y) + CtfDirector.CTF_POLE_HEIGHT + 1
	for _try in 6:
		var dx := randi() % (CTF_ROOF_RADIUS * 2 + 1) - CTF_ROOF_RADIUS
		var dz := randi() % (CTF_ROOF_RADIUS * 2 + 1) - CTF_ROOF_RADIUS
		if Vector2(dx, dz).length() > float(CTF_ROOF_RADIUS):
			continue
		# A LATTICE, NOT A LID. Every cell of the disc got filled, which is
		# a sealed roof over the objective — and a base that cannot be
		# broken into is not a hard game, it is no game: nothing was ever
		# taken, so no side ever had a reason to leave its own flag, and
		# every team sat on it for ten minutes. Half the cells, in a fixed
		# checker, so there are always holes to drop through and it still
		# reads as a roof from underneath.
		if (posmod(dx, 2) == 0) != (posmod(dz, 2) == 0):
			continue
		var rx := floori(home.x) + dx
		var rz := floori(home.z) + dz
		if not world.store.inside_world(rx, rz, 2):
			continue
		if _lay(team, Vector3i(rx, y, rz)):
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
	# Somebody OUT cannot touch the world and a downed bot is crawling; neither
	# has any business in the air.
	if world.downed_ids.has(id) or world.out_ids.has(id) \
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
	# CEILINGED, and it has to be. `goal.y + 2` is there so a bot comes
	# down ONTO a mound rather than flying into its side — but when the
	# goal is another airborne player it becomes a ladder: A climbs to two
	# above B, B climbs to two above A, and the pair of them ratchet into
	# the sky for the rest of the round. Watched it happen: 50, then 62,
	# then 75 blocks up, in three-second samples.
	var cruise := maxf(floor_y + BOT_FLY_HEIGHT, goal.y + 2.0)
	cruise = minf(cruise, floor_y + BOT_FLY_CEILING)
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
	if target == Vector3.INF or world.out_ids.has(id) or world.downed_ids.has(id):
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

## WHERE A KNOCKED-DOWN COMPUTER PLAYER IS VERTICALLY — or INF for "on
## the ground, like everything else".
##
## THE SAME SEQUENCE A PERSON GETS, and no more than that. Ten blocks up
## over three seconds, then back down. A person comes down by stopping
## flying; a computer player has nothing to press, so the end of the rise
## is when it comes down — and it uses the descent already here for the
## drop, at the same three blocks a second a person glides at.
##
## It had an arrangement of its own for a while: hover at ten until a
## rescuer came within thirteen blocks, then descend to meet them. It
## worked, and it was a second set of rules for the players who make up
## most of a room. One set now.
func _bot_downed_y(id: String, pos: Vector3, delta: float) -> float:
	if not world.downed_ids.has(id):
		return INF
	var down_for := float(Time.get_ticks_msec()
		- int(world.downed_ids.get(id, 0))) * 0.001
	if down_for >= Player.KNOCKOUT_RISE_SECONDS:
		# The rise is done. INF hands the way down back to the ordinary
		# ground handling, which glides anything above the floor down.
		return INF
	return pos.y + (Player.KNOCKOUT_RISE_BLOCKS / Player.KNOCKOUT_RISE_SECONDS) * delta

func _bot_settle_ground(id: String, bot: Dictionary, delta: float) -> void:
	var pos: Vector3 = bot.pos
	var gy := walk_y(floori(pos.x), floori(pos.z), pos.y)
	if gy < 0:
		gy = world.store.surface_y(floori(pos.x), floori(pos.z))
	var floor_y := float(gy) + 1.0
	if _water_at(floori(pos.x), floori(pos.z)):
		# Chest deep — see the note in the movement step.
		floor_y = maxf(floor_y, float(WorldGen.SEA_LEVEL) - 1.1)
	var down_y := _bot_downed_y(id, pos, delta)
	if down_y < INF:
		pos.y = down_y
		bot.pos = pos
		return
	if pos.y > floor_y + 3.0:
		# Still airborne (the drop): glide down at human pace (-3,
		# matching Player's drop glide exactly).
		pos.y = maxf(pos.y - 3.0 * delta, floor_y)
	else:
		pos.y = lerpf(pos.y, floor_y, minf(1.0, delta * 8.0))
	bot.pos = pos

## INTO THE BATCH, not onto the wire.
##
## This used to send its own RPC, so a hundred computer players at fifteen
## a second was fifteen hundred packets a second — each one carrying a
## node path and a method id to deliver about fifty bytes of position. The
## overhead was most of the traffic and all of the packet count, and it
## grew with the roster, which is why fifty players felt fine and a
## hundred did not.
##
## They go into a list that WorldNode.cl_pos_batch delivers in one packet
## per tick. See BotDirector._flush_positions.
func _bot_send_pos(id: String, bot: Dictionary, _delta: float) -> void:
	if float(bot.get("send_t", 0.0)) > 0.0:
		return
	bot.send_t = 1.0 / 15.0
	# WALK unless they are in the water or in the air, in which case
	# say so. Everything was sent as WALK, so a computer player in the
	# sea ran on the spot with its head above the waves — half of what
	# made them look like they were walking on it.
	var pose := Player.Anim.WALK
	var here: Vector3 = bot.pos
	if bool(bot.get("flying", false)):
		pose = Player.Anim.FLY
	elif _water_at(floori(here.x), floori(here.z)) \
			and here.y < float(WorldGen.SEA_LEVEL):
		pose = Player.Anim.SWIM
	_pending.append([id, here, float(bot.yaw), int(pose)])

## Everything that moved this frame, in one packet.
##
## Capped, because an unreliable packet that outgrows the MTU is a packet
## that gets fragmented or dropped — and dropping a hundred positions at
## once is far worse than sending two packets. Whatever is left goes next
## frame; it is a position update, and the next one is always more use
## than a retry of the last.
const POS_PER_PACKET := 48

var _pk := 0
var _ent := 0
var _pk_t := 0.0

func _flush_positions() -> void:
	if OS.get_environment("WORLD_NETSTAT") == "1":
		_ent += _pending.size()
		_pk += int(ceil(float(_pending.size()) / float(POS_PER_PACKET)))
		_pk_t += get_process_delta_time()
		if _pk_t >= 5.0:
			print("NET packets/s=%.0f entries/s=%.0f fps=%.1f bots=%d phase=%s"
				% [_pk / _pk_t, _ent / _pk_t,
					1.0 / maxf(get_process_delta_time(), 0.0001),
					roster.size(), world.match_phase])
			_pk = 0
			_ent = 0
			_pk_t = 0.0
	while not _pending.is_empty():
		var take: int = mini(POS_PER_PACKET, _pending.size())
		world.cl_pos_batch.rpc(_pending.slice(0, take))
		_pending = _pending.slice(take)

var _pending: Array = []

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
	# THE TEAM PICTURE FIRST, so every bot in this step reads the same one.
	# Rebuilt on its own timer inside; this call is an integer compare on
	# the frames it does nothing.
	_refresh_intel(delta)
	_tick_bots(delta)
	# One packet for everything that moved, at the END of the step — so a
	# bot that moves and then a second one that moves share a packet
	# rather than each buying their own.
	_flush_positions()

func _tick_bots(delta: float) -> void:
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
		bot.build_cd = maxf(0.0, float(bot.get("build_cd", 0.0)) - delta)
		bot.shield_cd = maxf(0.0, float(bot.get("shield_cd", 0.0)) - delta)
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
			_bot_settle_ground(id, bot, delta)
			var held: Dictionary = world.player_state.get(id, {})
			if not held.is_empty():
				held.pos = bot.pos
			_bot_send_pos(id, bot, delta)
			continue
		# ...and a bot doing the reviving stands still as well, rather than
		# wandering off two seconds into a three-second job.
		if not downed and _bot_holding_a_revive(id, pos):
			_bot_settle_ground(id, bot, delta)
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
		# STOOD AT A POST, WATCHING AN ARC. Yaw otherwise comes from
		# whichever way the bot last walked, which at a post it has
		# reached is nothing at all — so a guard that had arrived faced
		# whatever direction it happened to come in from and stayed that
		# way. This is the difference between eight bots standing about
		# and eight sentries. Eased rather than snapped, so a defender
		# turning to a new threat bearing looks like it turned.
		if flat.length() < 2.0 and bot.has("watch_yaw"):
			bot.yaw = lerp_angle(float(bot.yaw), float(bot.watch_yaw),
				minf(1.0, delta * 3.0))
		if flat.length() <= 0.8 and absf(to_goal.y) > 3.0:
			bot.blocked_t = float(bot.get("blocked_t", 0.0)) + delta
			if float(bot.blocked_t) > 2.0:
				bot.blocked_t = 0.0
				bot.goal = world.store.clamp_inside(pos + Vector3(
					randf_range(-16, 16), 0, randf_range(-16, 16)), 6)
				bot.think = randf_range(0.4, 0.8)
		if flat.length() > 0.8:
			# THE ROUTE IS WORKED OUT A FEW TIMES A SECOND, NOT EVERY
			# FRAME.
			#
			# Steering is the pathfinder: it walks the ground around
			# whatever is in the way and hands back a direction. Measured
			# with ninety-eight computer players, it was 400 of the 870
			# milliseconds a second the whole bot step cost — nearly half
			# — and it was being asked sixty times a second for an answer
			# that changes about ten times a second. Goal-picking, by
			# comparison, cost 1 ms/s, because it is already on a timer.
			#
			# Between recalculations the bot keeps walking the way it was
			# already walking, which is what walking is. The interval is
			# jittered so a hundred of them do not all recompute on the
			# same frame and hand the server one enormous tick.
			bot.steer_t = float(bot.get("steer_t", 0.0)) - delta
			var dir: Vector2 = bot.get("steer_dir", Vector2.ZERO)
			if float(bot.steer_t) <= 0.0:
				bot.steer_t = randf_range(0.10, 0.18)
				dir = _bot_steer(bot, pos, Vector3(bot.goal), delta)
				bot.steer_dir = dir
			# AIRBORNE: go straight there. The pathfinder walks the
			# ground, so a flying bot asking it for directions gets routed
			# round a wall it is currently above — or told there is no way
			# through at all, which is how it came to be flying.
			if bool(bot.get("flying", false)) and flat.length() > 0.001:
				dir = flat.normalized()
			# A DOWNED BOT CRAWLS. It used to be frozen solid — the whole
			# steering block was gated on `not downed` — so a knocked-down
			# computer player lay in the open, in the middle of whatever
			# had just shot it, until its whole team went down with it. It
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
					# THE SAME PACE AS ANYBODY ELSE. Computer players used
					# to crawl at 2.6 while a knocked-out person walked
					# about at full speed — one rule for them and another
					# for everyone else, which is the kind of special
					# handling that makes a room of fifty behave like two
					# different games.
					var crawl: float = float(bot.get("speed", 3.4))
					pos.x += dir.x * crawl * delta
					pos.z += dir.y * crawl * delta
					bot.yaw = atan2(-dir.x, -dir.y)
				bot.pos = pos
				_bot_settle_ground(id, bot, delta)
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
				# Not while out of the round, though. They cannot touch
				# anything — that is the whole deal — so one walking home
				# must not chew its way through the landscape to get
				# there. It goes round, or the BOT_RETURN_MS backstop
				# brings it in.
				if not world.out_ids.has(id):
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
						# The out never dig or build: they cannot touch the
						# world.
						if not world.out_ids.has(id):
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
			#
			# IN it, not ON it. This sat them at sea level plus a little,
			# which puts a whole body clear of the water — a field of
			# computer players walking across the sea, which is what
			# "most players walk on water" was. Chest deep now, so the
			# head and shoulders are out and the rest is under.
			floor_y = maxf(floor_y, float(WorldGen.SEA_LEVEL) - 1.1)
		var down_y := _bot_downed_y(id, pos, delta)
		var cruise_y := _bot_cruise_y(id, bot, flat, floor_y, delta)
		if down_y < INF:
			pos.y = down_y
		elif cruise_y < INF:
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
		#
		# THE COOLDOWN IS CHECKED FIRST, and that ordering is the whole
		# difference between a server that can hold a hundred players and
		# one that cannot.
		#
		# It used to look for a target every frame and THEN ask whether it
		# could shoot — so a bot that fires twice a second paid for a full
		# search sixty times a second. Since targets need line of sight,
		# that search walks a ray to every candidate: at a 55-block sight
		# range that is a hundred-odd block lookups each, up to six
		# candidates, per bot, per frame. Ninety-eight bots came to
		# millions of block reads a second and the server fell to a
		# fraction of real time — measured at 37 position updates a second
		# against a target of 1470.
		#
		# Nothing about the behaviour changes: a bot that cannot fire yet
		# had no use for the answer.
		if world.match_phase == "BATTLE" and world.match_alive.has(id) \
				and not downed and bot.shoot_cd <= 0.0:
			var enemy := _bot_nearest_enemy(id, pos, float(bot.get("sight", 48.0)))
			# NOTHING IN SIGHT, BUT SOMEBODY IS SHOOTING AT ME.
			#
			# This is the other half of "you can zoom in and shoot at them
			# and they won't do anything". Natural eyesight tops out at
			# fifty-five blocks for the best of them and twenty-two for
			# the worst, and a scoped shot comes from further than that —
			# so the bot was not ignoring you, it could not see you, and
			# nothing that happened to it ever said otherwise.
			#
			# THE ANSWER IS ONE RAY, NOT A WIDER SEARCH. Opening the
			# ordinary scan out to BotThreat.ALERT_SIGHT works and costs
			# real time: it admits more candidates, sorts them and casts
			# longer rays, for every bot in every firefight — measured at
			# about a tenth of the whole server step with ninety-nine of
			# them. And it is answering a question the bot does not need
			# to ask, because being shot at TELLS IT WHO AND WHERE. So it
			# tests exactly that one player, once, and only when the
			# ordinary scan came back empty.
			if enemy == "" and int(bot.get("threat_ms", 0)) > 0:
				var whom := str(bot.get("threat_id", ""))
				var age := Time.get_ticks_msec() - int(bot.get("threat_ms", 0))
				var reach := BotThreat.sight(float(bot.get("sight", 48.0)), age)
				if whom != "" and world.match_alive.has(whom) \
						and not world.downed_ids.has(whom) \
						and world.teams_differ(id, whom):
					var where: Vector3 = world.player_state.get(whom, {}).get(
						"pos", Vector3.INF)
					if where != Vector3.INF and pos.distance_to(where) < reach \
							and world.clear_shot(pos + Vector3(0, 1.4, 0),
								where + Vector3(0, 1.0, 0)):
						enemy = whom
			if enemy != "":
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
		# AND THEY START BEFORE THE BELL. Building was gated on BATTLE, so
		# the one stretch of the round with nobody shooting at you — the
		# setup phase, which in last flag standing is the whole point of
		# the mode — was spent standing about. A siege you have not built
		# anything for is just a fight in a field.
		var digging_in: bool = world.match_phase == "SETUP" and world.ctf.elimination()
		if world.ctf.active() and not downed and not world.out_ids.has(id) \
				and ((world.match_phase == "BATTLE" and world.match_alive.has(id)) \
					or digging_in):
			var my_team := int(Game.roster.get(id, {}).get("team", -1))
			# THE COOLDOWN BEFORE THE SIGHT CHECK, for the same reason the
			# shooting does it in that order: "is anybody in sight" walks
			# a ray to every candidate, and asking it sixty times a second
			# for a defender that lays a block twice a second is sixty
			# times the work for the same answer. In last flag standing
			# two thirds of every team are defenders, so this was most of
			# the roster paying it.
			if my_team >= 0 and float(bot.get("build_cd", 0.0)) <= 0.0 \
					and _bot_ctf_defends(id, my_team) \
					and _bot_nearest_enemy(id, pos, 30.0) == "":
				_bot_build_cover(id, bot, my_team, delta)
		if bot.send_t <= 0.0:
			bot.send_t = 1.0 / 15.0
			_pending.append([id, pos, float(bot.yaw), 1])

func spawn_orb(shooter: String, from: Vector3, dir: Vector3, kind: int) -> void:
	var speed := float(Weapons.spec(kind).get("speed", 34.0))
	if speed <= 1.0:
		return                      # melee and utility weapons don't fly
	orbs.append({"pos": from, "vel": dir * speed, "shooter": shooter,
		"kind": kind, "age": 0.0})

## The most hops one orb takes in one frame. See tick_orbs.
const MAX_ORB_HOPS := 8

func tick_orbs(delta: float) -> void:
	if orbs.is_empty():
		return
	# EVERYONE WHO COULD BE HIT, LOOKED UP ONCE FOR THE WHOLE FRAME.
	#
	# The per-orb filter below needs each player's position, and reading
	# it from player_state is a string-keyed dictionary hit. With hundreds
	# of orbs and a hundred players that was sixty thousand dictionary
	# lookups a frame, which costs more than the arithmetic it feeds.
	# Ninety-eight lookups now, and the filter reads a flat array.
	var alive: Array = []
	for pid: String in world.match_alive.keys():
		if world.downed_ids.has(pid):
			continue
		var where: Vector3 = world.player_state.get(pid, {}).get("pos", Vector3.INF)
		if where != Vector3.INF:
			alive.append([pid, where])
	for i in range(orbs.size() - 1, -1, -1):
		var orb: Dictionary = orbs[i]
		orb.age = float(orb.age) + delta
		var vel: Vector3 = orb.vel
		# These move up to 70 blocks a second, so step along the path in
		# short hops — a single jump per frame would tunnel through walls
		# and players alike.
		var travel := vel.length() * delta
		# CAPPED, and the cap is what stops a death spiral. Hops are
		# derived from how far the orb moves this frame, so a server
		# running slowly takes a bigger step, which asks for more hops,
		# which makes it slower still. At eight the step is under a block
		# and a half at any frame rate this thing should ever see.
		var hops := clampi(int(travel / 0.4), 1, MAX_ORB_HOPS)
		var step := vel * (delta / float(hops))
		var from: Vector3 = orb.pos
		# WHO COULD POSSIBLY BE HIT THIS FRAME, worked out ONCE.
		#
		# This test used to run for every alive player on every hop. With a
		# hundred bots shooting there are hundreds of orbs in the air, two
		# dozen hops each, and a hundred players to check — over a million
		# distance tests a frame, and it grows with the SQUARE of the
		# roster because more players means both more orbs and more things
		# to test each one against. That is why fifty was comfortable and a
		# hundred was not: it is not twice the work, it is four times.
		#
		# Almost nobody is ever near an orb's path, so the list is nearly
		# always empty and the inner loop below costs nothing.
		var reach := travel + 2.0
		var near: Array = []
		for entry: Array in alive:
			var who := str(entry[0])
			if who == orb.shooter or not world.teams_differ(orb.shooter, who):
				continue
			if Vector3(entry[1]).distance_to(from) <= reach:
				near.append(entry)
		var dead := false
		for _h in hops:
			orb.pos = (orb.pos as Vector3) + step
			var at: Vector3 = orb.pos
			if at.y < -4.0 or at.y > WorldGen.CHUNK_H + 40.0:
				dead = true
				break
			# Off the map is gone. Without this an orb that hits nothing
			# flies for its full six seconds — at seventy blocks a second
			# that is four hundred blocks, well past the edge of any world
			# here, being simulated the whole way.
			if not world.store.inside_world(floori(at.x), floori(at.z), 0):
				dead = true
				break
			if Blocks.is_solid(world.store.get_block(Vector3i(floori(at.x),
					floori(at.y), floori(at.z)))):
				if OS.get_environment("WORLD_ORB_DEBUG") == "1":
					print("BOTORB stopped by a block after %.2fs" % orb.age)
				dead = true
				break
			for entry: Array in near:
				var target: Vector3 = entry[1]
				if target.distance_to(at - Vector3(0, 0.8, 0)) < 1.1:
					if OS.get_environment("WORLD_ORB_DEBUG") == "1":
						print("BOTORB hit %s after %.2fs in flight" % [entry[0], orb.age])
					world.match_hurt(str(entry[0]), 1, at, orb.shooter)
					dead = true
					break
			if dead:
				break
		# Three seconds, down from six. At seventy blocks a second that is
		# still two hundred blocks — across any world here — and it halves
		# how many are in the air at once, which is what everything above
		# is multiplied by.
		if dead or float(orb.age) > 3.0:
			orbs.remove_at(i)


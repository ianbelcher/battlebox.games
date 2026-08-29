class_name WorldProbes
extends Node
## Dev-only scaffolding: the WORLD_*_TEST hooks that drive the server
## through a scenario on a timer so a headless run can prove something
## that would otherwise need four children and two controllers.
##
## Kept out of world.gd because none of it is the game. Each probe is
## inert unless its environment variable is set, so this node costs one
## `is_valid_int()` per tick in a real server and nothing else.
##
##   WORLD_RESIZE_TEST=<size>   resize mid-session, then check nobody fell
##                              off the map
##   WORLD_WIN_TEST=<team>      hand out knockouts and end the round
##   WORLD_KICK_TEST=1          kick a player and check they are forgotten
##   WORLD_SMOKE_TEST=1         fire a smoke round at the world
##   WORLD_BOTWATCH=1           report computer players that stopped moving
##   WORLD_SWITCH_TEST=<theme>  pick a different world MID-ROUND and check
##                              the ground actually changed under everyone
##   WORLD_CAPTURE_TEST=1       stand the person on an enemy flag and see
##                              whether touching it actually takes it
##   WORLD_ROUNDCLOCK_TEST=1    check the round clock runs at real speed
##   WORLD_ROOF_TEST=1          count what the defenders actually built
##   WORLD_HOLDOUT_SET=<mins>   change the round length through the real
##                              setter, and check the clock follows
##   WORLD_HUDDLE_TEST=1        count who is at home and who is out in the
##                              field, which is "the bots just huddle"
##   WORLD_POLE_TEST=1          turn reviving off, knock a bot out on its
##                              own flag, and check the channel that can
##                              never finish is never started
##   WORLD_SNIPE_TEST=1         shoot a computer player from further away
##                              than it can see and report whether it does
##                              anything at all about it
##   WORLD_SPREAD_TEST=1        how far apart a team's defenders actually
##                              stand, which is "they just march around
##                              the flag"

## The world being probed.
var world: WorldNode = null


## Boom blocks explode after their fuse; fireworks launch. Both checked
## every frame (the lists are tiny).
## The smoke marker times out by itself, so a match that runs long isn't
## still being pointed at a building somebody took ten minutes ago.
## WORLD_RESIZE_TEST=<size>: resize the world after 12s, then report
## every player's position for the next 12s and whether it is on the map.
## This is the exact sequence that kept stranding people — a running
## world with computer players in it, shrunk under them — and it is the
## only way to check it end to end without a person driving the menu.
var _resize_t := 0.0
var _resize_done := false
## WORLD_KICK_TEST=1: kick the first human after 15s. Proves that the ✕
## in the world menu actually gives up that player's SEAT on their own
## machine — the split screen drops to fewer cells, and if they were the
## last one there the join prompt comes back.
var _kick_t := 0.0
var _kick_done := false
## WORLD_WIN_TEST=<team>: hand a few knockouts around, then end the
## battle for that team after 22s. Checks the end-of-match scoreboard
## renders, and that ONE win is recorded for one game — the banner used
## to say two.
var _win_t := 0.0
var _win_done := false
## WORLD_BOT_DEBUG=1: every ten seconds, report how far each computer
## player actually got. "Stuck" is the failure that matters — a bot
## standing in a hole turning on the spot — and it is invisible in a
## screenshot, so it needs a number.
var _watch_t := 0.0
var _watch_from: Dictionary = {}
## WORLD_SMOKE_TEST=1: throw a smoke bomb every second, forever. Each one
## takes the last one down, which is exactly the path that used to strand
## a dozen infinite tweens per bomb on every client and grind them to a
## halt after a few throws.
var _smoke_t := 0.0

func tick_resize(delta: float) -> void:
	var want := OS.get_environment("WORLD_RESIZE_TEST")
	if not want.is_valid_int():
		return
	_resize_t += delta
	# Bring some computer players along: they are the case that broke,
	# and relying on a client to add them made the run flaky.
	if _resize_t > 6.0 and world.bots.roster.size() < 4:
		world.bots.spawn()
	if not _resize_done and _resize_t > 12.0:
		_resize_done = true
		print("RESIZETEST resizing to %s" % want)
		world.sv_match_config(-1, -1, want.to_int())
	if _resize_done and fmod(_resize_t, 3.0) < delta:
		var half := world.store.half_extent()
		var bad := 0
		for id: String in world.player_state.keys():
			var at: Vector3 = world.player_state[id].pos
			var inside := world.store.inside_world(floori(at.x), floori(at.z), 0)
			if not inside:
				bad += 1
			print("RESIZETEST %s %s at (%d,%d) half=%d %s" % [
				str(Game.roster.get(id, {}).get("name", "?")),
				"bot" if world.bots.roster.has(id) else "human",
				floori(at.x), floori(at.z), half,
				"OK" if inside else "*** OFF THE MAP ***"])
		print("RESIZETEST %d of %d off the map" % [bad, world.player_state.size()])
func tick_win(delta: float) -> void:
	var want := OS.get_environment("WORLD_WIN_TEST")
	if not want.is_valid_int() or _win_done:
		return
	_win_t += delta
	if _win_t < 22.0 or world.match_phase != "BATTLE":
		return
	_win_done = true
	# Some knockouts to fill the table with, credited across teams.
	var ids: Array = Game.roster.keys()
	for i in mini(ids.size(), 6):
		var attacker: String = ids[i]
		var victim: String = ids[(i + 3) % ids.size()]
		if world.teams_differ(attacker, victim):
			world.battle.credit_frag(attacker)
	world.battle.broadcast_scoreboard()
	print("WINTEST ending for team %s, frags=%s" % [want, str(world.player_frags)])
	world.battle.finish(want.to_int())
	print("WINTEST wins now %s (should be exactly one for team %s)"
		% [str(world.team_wins), want])
func tick_kick(delta: float) -> void:
	if OS.get_environment("WORLD_KICK_TEST") != "1":
		return
	_kick_t += delta
	if _kick_done or _kick_t < 15.0:
		return
	for id: String in Game.roster.keys():
		if bool(Game.roster[id].get("bot", false)):
			continue
		_kick_done = true
		print("KICKTEST kicking %s (%s)" % [
			str(Game.roster[id].get("name", "?")), id])
		Game.sv_kick_player(id)
		return
func tick_smoke(delta: float) -> void:
	if OS.get_environment("WORLD_SMOKE_TEST") != "1":
		return
	_smoke_t += delta
	if _smoke_t < 1.0:
		return
	_smoke_t = 0.0
	var at := world.store.safe_stand(Vector3(world.spawn_pos), 12.0)
	world._smoke_marker = {"pos": at, "team": randi() % 4,
		"until": Time.get_ticks_msec() + world.SMOKE_MSEC}
	world.cl_smoke.rpc(at, int(world._smoke_marker.team))
func tick_bot_watch(delta: float) -> void:
	if OS.get_environment("WORLD_BOT_DEBUG") != "1":
		return
	_watch_t += delta
	if _watch_t < 10.0:
		return
	_watch_t = 0.0
	var stuck := 0
	var holding := 0
	var moved_total := 0.0
	var counted := 0
	for id: String in world.bots.roster.keys():
		# Only ones that are actually trying to go somewhere. A bot that
		# is out of the match, or lying downed, has every right not to
		# have moved, and counting it made the number meaningless.
		if world.match_phase == "BATTLE" and (not world.match_alive.has(id)
				or world.downed_ids.has(id)):
			continue
		if world.match_phase != "BATTLE" and world.match_phase != "IDLE":
			continue
		counted += 1
		var bot: Dictionary = world.bots.roster[id]
		var at: Vector3 = bot.pos
		var was: Vector3 = _watch_from.get(id, at)
		var gone := Vector2(at.x - was.x, at.z - was.z).length()
		moved_total += gone
		if gone < 2.0:
			# STANDING STILL IS NOT THE SAME AS BEING STUCK, and it used
			# to be: this counted anybody who had not moved, because at
			# the time no computer player ever WANTED to stand anywhere.
			# A defender holding a post in a harbour does, all round, on
			# purpose — so a metric that cannot tell the two apart reports
			# a working guard as a field of broken bots.
			#
			# The difference is whether it is where it was trying to get
			# to. At its goal and not moving is a sentry; two blocks short
			# of a goal it has been failing to reach for ten seconds is
			# the failure this probe exists for.
			var want: Vector3 = bot.get("goal", at)
			if Vector2(at.x - want.x, at.z - want.z).length() < 2.5:
				holding += 1
			else:
				stuck += 1
				print("BOTWATCH %s STUCK at (%d,%d,%d), moved %.1f in 10s, "
					% [str(Game.roster.get(id, {}).get("name", "?")),
						floori(at.x), floori(at.y), floori(at.z), gone]
					+ "wanted (%d,%d) %.1f away"
					% [floori(want.x), floori(want.z),
						Vector2(at.x - want.x, at.z - want.z).length()])
		_watch_from[id] = at
	if counted > 0:
		print("BOTWATCH %d/%d stuck, %d holding a post, average %.1f blocks in 10s"
			% [stuck, counted, holding, moved_total / float(counted)])


## Every probe, once per frame. They are all inert without their
## environment variable, so this is five integer checks on a real server.
## WORLD_REVIVE_TEST=1: knock a computer player down, stand a team-mate on
## top of it, and report every three seconds whether the pick-up is
## progressing. Answers "they come to me to be revived and nothing
## happens" with a number instead of a guess.
var _rev_t := 0.0
var _rev_started := false
var _rev_who := ""

func tick_revive(delta: float) -> void:
	if OS.get_environment("WORLD_REVIVE_TEST") != "1":
		return
	_rev_t += delta
	if _rev_t < 3.0:
		return
	_rev_t = 0.0
	if not _rev_started:
		if world.match_phase != "BATTLE":
			print("REVIVE: waiting, phase=%s" % world.match_phase)
			return
		for id: String in world.match_alive.keys():
			var team := int(Game.roster.get(id, {}).get("team", -1))
			for mate: String in world.match_alive.keys():
				if mate == id or int(Game.roster.get(mate, {}).get("team", -2)) != team:
					continue
				_rev_who = id
				world.battle.eliminate(id, mate)
				var at: Vector3 = world.player_state[id].pos
				world.player_state[mate].pos = at + Vector3(1.0, 0, 0)
				if world.bots.roster.has(mate):
					world.bots.roster[mate].pos = at + Vector3(1.0, 0, 0)
				print("REVIVE: downed %s, stood %s beside it at %v" % [id, mate, at])
				_rev_started = true
				return
		print("REVIVE: nobody had a team-mate")
		return
	var body: Vector3 = world.player_state.get(_rev_who, {}).get("pos", Vector3.INF)
	var team := int(Game.roster.get(_rev_who, {}).get("team", -1))
	var near := 0
	var nearest := 999.0
	for other: String in world.match_alive.keys():
		if other == _rev_who or world.downed_ids.has(other):
			continue
		if int(Game.roster.get(other, {}).get("team", -2)) != team:
			continue
		var d: float = Vector3(world.player_state.get(other, {}).get(
			"pos", Vector3.INF)).distance_to(body)
		nearest = minf(nearest, d)
		if d < world.REVIVE_RADIUS:
			near += 1
	print("REVIVE: downed=%s progress=%.2f body=%v mates_in_range=%d nearest=%.2f out=%s"
		% [world.downed_ids.has(_rev_who),
			float(world.battle.revive_progress.get(_rev_who, -1.0)), body, near,
			nearest, world.out_ids.has(_rev_who)])

## WORLD_SWITCH_TEST=<theme>: choose a world while a round is running.
##
## Picking one used to be remembered and applied at the START of the next
## round, so with the match loop on — the normal way this is played — the
## phase was never idle and choosing Space did nothing whatsoever. It went
## on doing nothing until the SIZE was changed, which reset the world
## through a different path and dragged the new theme along with it.
##
## Checking it needs a running round and a look at the actual ground
## before and after, because "the menu highlighted the one I picked" was
## always true and was never the question.
var _switch_t := 0.0
var _switch_done := false
var _switch_before := ""

func tick_switch(delta: float) -> void:
	var want := OS.get_environment("WORLD_SWITCH_TEST")
	if want.is_empty() or _switch_done or world == null:
		return
	_switch_t += delta
	if _switch_t < 26.0:
		return
	_switch_done = true
	# sv_select_world returns in silence for a name it does not know, so
	# without this an unknown theme reads as "the switch is broken".
	if not (want in WorldGen.THEMES):
		print("SWITCH: %s is not a theme — try one of %s" % [want, WorldGen.THEMES])
		return
	_switch_before = "map=%s theme=%s" % [world.store.current_map_key, world.store.theme]
	var ground_before := _ground_line()
	world.sv_select_world(want)
	print("SWITCH: phase=%s | before %s %s" % [world.match_phase,
		_switch_before, ground_before])
	print("SWITCH: after  map=%s theme=%s %s" % [world.store.current_map_key,
		world.store.theme, _ground_line()])
	print("SWITCH: theme changed=%s ground changed=%s"
		% [str(str(world.store.current_map_key) == want),
			str(ground_before != _ground_line())])

## A fingerprint of the terrain: the surface height along a line through
## the middle. Two different worlds do not agree on this.
func _ground_line() -> String:
	var heights: PackedStringArray = []
	for i in 8:
		var x := -60 + i * 16
		heights.append(str(world.store.surface_y(x, 0)))
	return "ground=[%s]" % ",".join(heights)

## WORLD_CAPTURE_TEST=1: put the person on an enemy flag and report.
##
## "I touched another team's flag a number of times and it didn't take it"
## is not something a headless run reaches by luck — it needs somebody to
## walk across a map and stand in the right square. So this puts them
## there: it writes the position the flag test actually reads, holds it
## for a second so it cannot be missed between frames, and says what the
## test saw.
##
## The position is re-written EVERY frame on purpose. A person's machine
## reports where they are twelve times a second and overwrites it, so
## setting it once and waiting is a race this loses about half the time.
var _cap_t := 0.0
var _cap_hold := 0.0
var _cap_done := false
var _cap_target := -1
var _cap_who := ""
var _cap_took := 0

func tick_capture(delta: float) -> void:
	if OS.get_environment("WORLD_CAPTURE_TEST") != "1" or _cap_done or world == null:
		return
	if world.match_phase != "BATTLE":
		return
	_cap_t += delta
	if _cap_t < 12.0:
		return
	if _cap_who.is_empty():
		for id: String in Game.roster.keys():
			if not world.bots.roster.has(id) and world.player_state.has(id):
				_cap_who = id
				break
		if _cap_who.is_empty():
			print("CAPTURE: nobody at a keyboard to walk in"); _cap_done = true
			return
		var mine := int(Game.roster.get(_cap_who, {}).get("team", -1))
		for team_i: int in world.ctf._flags.keys():
			var f: Dictionary = world.ctf._flags[team_i]
			if team_i != mine and not bool(f.get("out", false)) \
					and int(f.get("back_at", 0)) == 0:
				_cap_target = team_i
				break
		if _cap_target < 0:
			print("CAPTURE: no enemy flag standing"); _cap_done = true
			return
		var flag: Dictionary = world.ctf._flags[_cap_target]
		print("CAPTURE: standing %s (team %d) on team %d's flag at %v"
			% [_cap_who, mine, _cap_target, flag.pos])
		_cap_took = int(world.ctf_caps.get(mine, 0))
		print("CAPTURE: took=%d lost=%d before"
			% [_cap_took, int(world.ctf_lost.get(_cap_target, 0))])
		_sweep_reach(Vector3(flag.pos))
	# TOOK IT, or somebody else did? A flag whose position has gone to
	# infinity has been captured — and in last flag standing that is what a
	# SUCCESSFUL touch looks like, so the old "the flag went while we
	# walked in" was reporting the pass as though it were a miss. Ask the
	# scoreline, which knows whose it was.
	var mine_now := int(Game.roster.get(_cap_who, {}).get("team", -1))
	if int(world.ctf_caps.get(mine_now, 0)) > _cap_took:
		print("CAPTURE: ok — touching it took it (took=%d, team %d out=%s)"
			% [int(world.ctf_caps.get(mine_now, 0)), _cap_target,
				str(world.ctf.team_is_out(_cap_target))])
		_cap_done = true
		return
	var at: Vector3 = world.ctf._flags[_cap_target].get("pos", Vector3.INF)
	if at == Vector3.INF:
		print("CAPTURE: somebody else took it first — inconclusive")
		_cap_done = true
		return
	world.player_state[_cap_who].pos = at
	_cap_hold += delta
	if _cap_hold < 1.0:
		return
	_cap_done = true
	var mine2 := int(Game.roster.get(_cap_who, {}).get("team", -1))
	var got := int(world.ctf_caps.get(mine2, 0))
	print("CAPTURE: %s — took=%d (was %d) lost=%d | team %d out=%s"
		% ["ok" if got > _cap_took else "FAIL standing on it did nothing",
			got, _cap_took, int(world.ctf_lost.get(_cap_target, 0)),
			_cap_target, str(world.ctf.team_is_out(_cap_target))])

## WORLD_ROUNDCLOCK_TEST=1: does the round clock run at ONE second per
## second?
##
## It did not. `_timer -= delta` runs at the top of MatchDirector.tick for
## every phase, and the last-flag branch took it off a SECOND time — so
## ten minutes of clock elapsed in five minutes of playing and the round
## ended with the display still reading half the time left. Nothing else
## here would have noticed: the round starts, the round ends, a winner is
## printed, and every test passes.
##
## Measured against real elapsed time, so a second subtraction anywhere
## shows up as a rate near 2 instead of near 1.
var _clock_t := 0.0
var _clock_from := -1.0
var _clock_said := 0.0

func tick_roundclock(delta: float) -> void:
	if OS.get_environment("WORLD_ROUNDCLOCK_TEST") != "1" or world == null:
		return
	if world.match_phase != "BATTLE":
		return
	# WINDOWED, not cumulative from the first frame of BATTLE. The clock is
	# still the SETUP countdown for a frame or two after the phase flips,
	# so a baseline taken there is a few seconds while the real one is six
	# hundred, and every rate after it is nonsense.
	_clock_t += delta
	if _clock_t - _clock_said < 5.0:
		return
	var window := _clock_t - _clock_said
	_clock_said = _clock_t
	var now_left := float(world.match_seconds)
	if _clock_from < 0.0 or now_left > _clock_from:
		_clock_from = now_left        # first window, or the clock was just set
		return
	var spent := _clock_from - now_left
	_clock_from = now_left
	print("ROUNDCLOCK: %.1fs real → %.1fs off the clock, rate=%.2f (want 1.00)"
		% [window, spent, spent / maxf(0.001, window)])

## WORLD_ROOF_TEST=1: did the defenders actually put a lid on?
##
## Building is the one bot behaviour with no visible output at all — no
## log line, no state, just blocks appearing somewhere nobody is looking.
## So this counts them: the ring around each base and the roof over it,
## which is the only way to tell "they are roofing it" from "the code that
## roofs it never runs".
var _roof_t := 0.0
var _roof_said := 0.0

func tick_roof(delta: float) -> void:
	if OS.get_environment("WORLD_ROOF_TEST") != "1" or world == null:
		return
	if world.match_phase == "IDLE" or world.ctf._flags.is_empty():
		return
	_roof_t += delta
	if _roof_t - _roof_said < 30.0:
		return
	_roof_said = _roof_t
	for team_i: int in world.ctf._flags.keys():
		var home: Vector3 = world.ctf._flags[team_i].get("home", Vector3.INF)
		if home == Vector3.INF:
			continue
		var roof := 0
		var ry := int(home.y) + CtfDirector.CTF_POLE_HEIGHT + 1
		for dz in range(-6, 7):
			for dx in range(-6, 7):
				if world.store.get_block(Vector3i(floori(home.x) + dx, ry,
						floori(home.z) + dz)) != Blocks.AIR:
					roof += 1
		var wall := 0
		for dz2 in range(-11, 12):
			for dx2 in range(-11, 12):
				var d := Vector2(dx2, dz2).length()
				if d < 8.0 or d > 10.5:
					continue
				for up in 4:
					if world.store.get_block(Vector3i(floori(home.x) + dx2,
							int(home.y) + up, floori(home.z) + dz2)) != Blocks.AIR:
						wall += 1
		# AND THE MINEFIELD. Laying charges is the one bot behaviour with
		# no visible output at all — no log line, no state, just red
		# blocks appearing on ground nobody is looking at — so it is
		# counted here beside the wall and the roof for the same reason
		# those are.
		# THE WHOLE DEPTH OF THE APPROACHES, not the flag's own level. The
		# mound stands three blocks proud of the landscape and the mines
		# go twelve to sixteen blocks out, on whatever the ground does
		# there — which is usually well below the summit. Counting two
		# courses at `home.y` found nothing and reported a minefield that
		# was being laid perfectly well.
		var mines := 0
		for dz3 in range(-18, 19):
			for dx3 in range(-18, 19):
				for y3 in range(int(home.y) - 10, int(home.y) + 3):
					if world.store.get_block(Vector3i(floori(home.x) + dx3,
							y3, floori(home.z) + dz3)) == Blocks.BOOM:
						mines += 1
		print("ROOF: t=%.0fs team %d wall=%d roof=%d mines=%d"
			% [_roof_t, team_i, wall, roof, mines])

## WORLD_HOLDOUT_SET=<minutes>: set the round length the way the menu
## does — through sv_ctf_config — and let the round start on it.
##
## Proving the DEFAULT works proves very little: ten minutes is what the
## old hard-coded constant gave too, so the clock reading 600 says nothing
## about whether the setting is what it read.
var _len_done := false
var _len_t := 0.0

func tick_length(delta: float) -> void:
	var want := OS.get_environment("WORLD_HOLDOUT_SET")
	if want.is_empty() or _len_done or world == null:
		return
	_len_t += delta
	if _len_t < 4.0:
		return
	_len_done = true
	world.sv_ctf_config(-1, -1, -1, want.to_int())
	print("HOLDOUT: length set to %d min (world says %.0f)"
		% [want.to_int(), world.holdout_minutes])

## HOW FAR THE FLAG ACTUALLY REACHES, on each side of it.
##
## "It didn't take it when I walked up to it, but it did when I came round
## the other side, almost like the flag's position was two squares away
## from it" is a claim about a SHAPE, and the shape of a touch test is
## measurable: walk out from the pole along each of the four compass
## directions and note the last step that still counts.
##
## If the four numbers match, the reach is a circle centred on the pole and
## the complaint is about something else. If they do not, the circle is
## centred somewhere the pole is not — which is precisely the half-block
## the flag position used to be out by, and it is why this prints all four
## rather than a yes or a no.
func _sweep_reach(flag_at: Vector3) -> void:
	if flag_at == Vector3.INF:
		return
	# WALKED OUT FROM THE POLE, NOT FROM THE FLAG POINT — and that
	# distinction is the entire value of this check.
	#
	# Sweeping outward from `flag_at` measures the touch test's symmetry
	# about its OWN centre, which is symmetric by construction and can
	# never fail. What a player walks up to is the pole they can SEE, so
	# the sweep starts at the middle of the pole's block, worked out from
	# the block itself. If the flag point ever drifts off the pole again
	# the four numbers stop matching, which is what a person feels as
	# "I had to come at it from that side".
	var pole := Vector3(float(floori(flag_at.x)) + 0.5, flag_at.y,
		float(floori(flag_at.z)) + 0.5)
	var legs := {"+x": Vector3(1, 0, 0), "-x": Vector3(-1, 0, 0),
		"+z": Vector3(0, 0, 1), "-z": Vector3(0, 0, -1)}
	var out: Array = []
	for name_v: Variant in legs.keys():
		var step: Vector3 = legs[name_v]
		var reach := 0.0
		for i in 40:
			if not world.ctf._at_flag(pole + step * (float(i) * 0.25), flag_at):
				break
			reach = float(i) * 0.25
		out.append("%s=%.2f" % [str(name_v), reach])
	print("CAPTURE: reach from the pole at %v  %s  (they should all match)"
		% [pole, " ".join(out)])

## WORLD_GHOST_TEST=1, THE SERVER HALF: knock a team out on purpose.
##
## The client half (tests/ghost_probe.gd) asks whether a knocked-out team
## is actually hidden. It cannot answer that until a team has actually
## been knocked out, and waiting for the computer players to manage a
## capture is waiting on luck — thirty seconds of "nobody is out yet" and
## then the run ends.
##
## So this takes a side out through the REAL path, `knock_out_team`, which
## is what a captured flag calls. Not by writing `out_ids` directly: the
## question is what that function leaves behind, and a test that
## reproduces its effects rather than calling it proves nothing about it.
var _ghost_t := 0.0
var _ghost_done := false

func tick_ghost(delta: float) -> void:
	if OS.get_environment("WORLD_GHOST_TEST") != "1" or world == null or _ghost_done:
		return
	if world.match_phase != "BATTLE" or world.ctf._flags.is_empty():
		return
	_ghost_t += delta
	if _ghost_t < 20.0:
		return
	# Whichever side still has a flag and somebody alive to lose it.
	for team_i: int in world.ctf._flags.keys():
		if world.ctf.team_is_out(team_i):
			continue
		var alive := 0
		for id: String in world.match_alive.keys():
			if int(Game.roster.get(id, {}).get("team", -1)) == team_i:
				alive += 1
		if alive <= 0:
			continue
		_ghost_done = true
		print("GHOST: knocking team %d out through knock_out_team (%d alive)"
			% [team_i, alive])
		world.ctf.knock_out_team(team_i)
		return

## WORLD_SIEGE_TEST=1: DOES ANYBODY EVER ACTUALLY REACH A FLAG?
##
## Last flag standing is decided by touching an enemy pole, and a round of
## it came back with not one flag taken from start to finish — "essentially
## battle royale except there's no storm at the end". Nothing errors in
## that round. Every side has attackers, they leave home, they fight, and
## the scoreline stays empty, because attacking and ARRIVING are different
## things and only one of them is visible from the outside.
##
## So this measures the only distance that decides the mode: how close
## anybody actually gets to a flag that is not their own, tracked as a
## running minimum so a single frame inside the radius cannot be missed.
## And the same for the owners, because "nobody would protect the actual
## flag" is the same measurement from the other side.
##
## The number to compare both against is CtfDirector.CTF_FLAG_TOUCH. An
## attacker whose closest approach all round is outside it is a bot that
## did everything but the one thing that scores.
var _siege_t := 0.0
var _siege_said := 0.0
var _siege_near: Dictionary = {}
var _siege_own: Dictionary = {}
## Did anybody actually satisfy the game's own touch test this window?
var _siege_touch: Dictionary = {}

func tick_siege(delta: float) -> void:
	if OS.get_environment("WORLD_SIEGE_TEST") != "1" or world == null:
		return
	if world.match_phase != "BATTLE" or world.ctf._flags.is_empty():
		return
	_siege_t += delta
	for team_i: int in world.ctf._flags.keys():
		var flag: Dictionary = world.ctf._flags[team_i]
		if bool(flag.get("out", false)) or int(flag.back_at) > 0:
			continue
		var at: Vector3 = flag.get("pos", Vector3.INF)
		if at == Vector3.INF:
			continue
		for id: String in world.match_alive.keys():
			if world.downed_ids.has(id) or world.out_ids.has(id):
				continue
			var who: Vector3 = world.player_state.get(id, {}).get("pos", Vector3.INF)
			if who == Vector3.INF:
				continue
			var flat := Vector2(who.x - at.x, who.z - at.z).length()
			var theirs := int(Game.roster.get(id, {}).get("team", -1)) == team_i
			var book := _siege_own if theirs else _siege_near
			if flat < float(book.get(team_i, 9999.0)):
				book[team_i] = flat
			# THE GAME'S OWN TEST, NOT A COPY OF HALF OF IT.
			#
			# The distance above is flat, and `_at_flag` is not: it also
			# wants the player within CTF_FLAG_REACH_Y of the flag's own
			# height. Reporting "in reach" off the flat distance alone
			# therefore counts somebody tunnelling underneath or flying
			# over as having arrived — which reads as eight arrivals and
			# no captures, and sends the next person looking for a bug in
			# the capture code that is really a bug in this line.
			#
			# So the verdict is asked of `_at_flag` itself. A probe that
			# measures nearly the same thing as the game is worse than no
			# probe: it is wrong in a way that looks like data.
			if not theirs and world.ctf._at_flag(who, at):
				_siege_touch[team_i] = true
	if _siege_t - _siege_said < 20.0:
		return
	_siege_said = _siege_t
	var caps := 0
	for team_i: int in world.ctf_caps.keys():
		caps += int(world.ctf_caps[team_i])
	# AIMING AT IT AND REACHING IT ARE DIFFERENT FAILURES, and only one of
	# them is a bug in the orders. A goal that sits outside the touch
	# radius is a bot that would not capture even standing on its own
	# objective — that is the spread bug. A goal ON the flag with the bot
	# still twenty blocks away is a bot being stopped on the way in, which
	# is a wall, a fight, or the terrain, and a different thing entirely.
	var aimed := 9999.0
	for id: String in world.bots.roster.keys():
		var want: Vector3 = world.bots.roster[id].get("goal", Vector3.INF)
		if want == Vector3.INF:
			continue
		for team_j: int in world.ctf._flags.keys():
			if int(Game.roster.get(id, {}).get("team", -1)) == team_j:
				continue
			var flag_j: Vector3 = world.ctf._flags[team_j].get("pos", Vector3.INF)
			if flag_j == Vector3.INF:
				continue
			aimed = minf(aimed, Vector2(want.x - flag_j.x, want.z - flag_j.z).length())
	for team_i: int in world.ctf._flags.keys():
		var enemy := float(_siege_near.get(team_i, 9999.0))
		var owner := float(_siege_own.get(team_i, 9999.0))
		print("SIEGE: t=%.0fs flag %d — nearest enemy %.1f (%s), nearest owner %.1f (%s)"
			% [_siege_t, team_i, enemy,
				"IN REACH" if bool(_siege_touch.get(team_i, false)) else "never got there",
				owner,
				"on it" if owner < CtfDirector.CTF_FLAG_TOUCH else "off it"])
	print("SIEGE: t=%.0fs closest attacker GOAL to any enemy flag: %.1f (%s)"
		% [_siege_t, aimed,
			"aimed to capture" if aimed < CtfDirector.CTF_FLAG_TOUCH
				else "AIMED SHORT — the orders themselves cannot score"])
	print("SIEGE: t=%.0fs touch radius is %.1f, flags taken so far: %d"
		% [_siege_t, CtfDirector.CTF_FLAG_TOUCH, caps])
	_siege_near.clear()
	_siege_own.clear()
	_siege_touch.clear()

## WORLD_POLE_TEST=1: THE POLE TRAP, reproduced on purpose.
##
## Turn reviving OFF through the real setter, knock a computer player out,
## stand it on its own flag, and watch what the flag channel does with it.
##
## What used to happen, and what this exists to keep from coming back: the
## channel ran anyway, because only `respawn` knew the flag route was shut.
## It sent revive progress to the client every frame, which freezes anybody
## it reaches, ran its three seconds, called `respawn`, got nothing, wiped
## the progress and started again. Forever. On the field that is a player
## rooted against their own pole reading "reviving", and — since a computer
## player that is out walks home too — an entire team stacked on the mound
## and not defending it.
##
## Nothing about that raises. The round runs, the clock ticks, and the only
## visible symptom is a number that keeps resetting to zero. So the check
## is: with the route shut, progress must never start at all, and the same
## bot must not still be sat on its own flag a minute later.
var _pole_t := 0.0
var _pole_phase := 0
var _pole_who := ""
var _pole_home := Vector3.INF
var _pole_seen := 0.0
var _pole_started := 0

func tick_pole(delta: float) -> void:
	if OS.get_environment("WORLD_POLE_TEST") != "1" or world == null:
		return
	_pole_t += delta
	match _pole_phase:
		0:
			if world.match_phase != "BATTLE" or world.ctf._flags.is_empty():
				return
			if _pole_t < 8.0:
				return
			# Through the real setter, not by writing the variable: the
			# question is whether the SETTING closes the route, and a test
			# that pokes the field behind it proves nothing about the menu.
			world.sv_ctf_config(ReviveRule.NONE, -1, -1)
			print("POLE: reviving set to %d (%s)"
				% [world.revive_mode, ReviveRule.label(world.revive_mode)])
			_pole_phase = 1
			_pole_t = 0.0
		1:
			if _pole_t < 1.0:
				return
			for id: String in world.bots.roster.keys():
				var team := int(Game.roster.get(id, {}).get("team", -1))
				var home: Vector3 = world.ctf._flags.get(team, {}).get(
					"home", Vector3.INF)
				if team < 0 or home == Vector3.INF or not world.match_alive.has(id):
					continue
				_pole_who = id
				_pole_home = home
				world.battle.eliminate(id)
				print("POLE: knocked %s (team %d) out, out=%s, standing it on "
					% [str(Game.roster.get(id, {}).get("name", "?")), team,
						str(world.out_ids.has(id))]
					+ "its own flag at %v" % home)
				_pole_phase = 2
				_pole_t = 0.0
				return
			print("POLE: no computer player available")
			_pole_phase = 3
		2:
			# Held ON the flag every frame, because that is the position the
			# channel reads and the bot's own movement overwrites it.
			if world.bots.roster.has(_pole_who):
				world.bots.roster[_pole_who].pos = _pole_home
			if world.player_state.has(_pole_who):
				world.player_state[_pole_who].pos = _pole_home
			if float(world.ctf._flag_progress.get(_pole_who, 0.0)) > 0.0:
				_pole_started += 1
			_pole_seen += delta
			if _pole_t < 5.0:
				return
			_pole_t = 0.0
			print("POLE: after %.0fs on its own flag — progress started on %d "
				% [_pole_seen, _pole_started]
				+ "frames, out=%s, %s"
				% [str(world.out_ids.has(_pole_who)),
					"ok   the shut door is never knocked on" if _pole_started == 0
						else "FAIL the channel is running with no way back"])

## WORLD_HUDDLE_TEST=1: are they playing, or standing on their own flag?
##
## "All of the bots now just huddle around the flag and don't do anything"
## is a shape nothing here can see: the round runs, the clock ticks, no
## error appears, and every test passes while nobody attacks anything. So
## count it — per team, how many are near their own base and how many are
## out in the field where an attacker would be.
var _hud_t := 0.0
var _hud_said := 0.0

func tick_huddle(delta: float) -> void:
	if OS.get_environment("WORLD_HUDDLE_TEST") != "1" or world == null:
		return
	if world.match_phase != "BATTLE" or world.ctf._flags.is_empty():
		return
	_hud_t += delta
	if _hud_t - _hud_said < 20.0:
		return
	_hud_said = _hud_t
	var home_n := 0
	var out_n := 0
	var away_n := 0
	for id: String in world.match_alive.keys():
		var team := int(Game.roster.get(id, {}).get("team", -1))
		var mine: Vector3 = world.ctf._flags.get(team, {}).get("home", Vector3.INF)
		var at: Vector3 = world.player_state.get(id, {}).get("pos", Vector3.INF)
		if mine == Vector3.INF or at == Vector3.INF:
			continue
		var d := Vector2(at.x - mine.x, at.z - mine.z).length()
		if d < 14.0:
			home_n += 1
		elif d > 40.0:
			away_n += 1
		else:
			out_n += 1
	print("HUDDLE: t=%.0fs at their own base=%d, in between=%d, out in the field=%d"
		% [_hud_t, home_n, out_n, away_n])

## WORLD_SNIPE_TEST=1: THE COMPLAINT, MEASURED.
##
## "If I'm a player I can just zoom in and shoot at them and they won't do
## anything." That is a claim about a computer player's state after being
## hit, and there was nothing in this repository that could look at it —
## the round runs, hearts come off, no error appears, and the bot walks on
## in the direction it was already going.
##
## So: pick a bot, put a shot into it from well beyond the best eyesight
## in the game, and report the three things that say whether it noticed —
## which way it is FACING relative to the shot, what it DECIDED to do
## about it, and whether it has actually MOVED since. A bot that ignores
## you scores a facing near zero and no decision at all.
var _snipe_t := 0.0
var _snipe_who := ""
var _snipe_from := Vector3.ZERO
var _snipe_was := Vector3.ZERO
var _snipe_fired := false

func tick_snipe(delta: float) -> void:
	if OS.get_environment("WORLD_SNIPE_TEST") != "1" or world == null:
		return
	_snipe_t += delta
	if _snipe_t < 3.0:
		return
	_snipe_t = 0.0
	if world.match_phase != "BATTLE":
		print("SNIPE: waiting, phase=%s" % world.match_phase)
		return
	# FIRE AGAIN whenever the last alert has gone stale, so the decision
	# being reported is always a live one. Shooting once and then reading
	# the same bot two minutes later reports whatever it last decided,
	# which is not the same question at all.
	if _snipe_fired and world.bots.roster.has(_snipe_who):
		var age := Time.get_ticks_msec() \
			- int(world.bots.roster[_snipe_who].get("threat_ms", 0))
		if age > BotThreat.MEMORY_MS + 3000:
			_snipe_fired = false
	if not _snipe_fired:
		for id: String in world.bots.roster.keys():
			if not world.match_alive.has(id) or world.downed_ids.has(id):
				continue
			var at: Vector3 = world.bots.roster[id].pos
			# FROM FURTHER THAN IT CAN POSSIBLY SEE. The point is that
			# eyesight cannot be the thing that saves it.
			_snipe_from = at + Vector3(65.0, 6.0, 0.0)
			_snipe_who = id
			_snipe_was = at
			_snipe_fired = true
			print("SNIPE: %s at %v, shot from %v (%.0f blocks, sight is %.0f)"
				% [str(Game.roster.get(id, {}).get("name", "?")), at, _snipe_from,
					at.distance_to(_snipe_from),
					float(world.bots.roster[id].get("sight", 0.0))])
			world.match_hurt(id, 1, _snipe_from)
			return
		print("SNIPE: no computer player was available to shoot at")
		return
	var bot: Dictionary = world.bots.roster.get(_snipe_who, {})
	if bot.is_empty():
		print("SNIPE: %s left the round" % _snipe_who)
		return
	var here: Vector3 = bot.pos
	# Facing, as how much of a turn it is off the line to the shooter: 1.0
	# is looking straight at it, -1.0 is directly away.
	var to_them := Vector2(_snipe_from.x - here.x, _snipe_from.z - here.z)
	var facing := Vector2(-sin(float(bot.yaw)), -cos(float(bot.yaw)))
	var toward := 0.0
	if to_them.length() > 0.01:
		toward = facing.dot(to_them.normalized())
	var acts := ["ignore", "return fire", "push", "take cover", "withdraw"]
	var act := int(bot.get("threat_act", -1))
	print("SNIPE: %s facing=%+.2f decision=%s moved=%.1f hearts=%d gun=%d %.1fs ago"
		% [str(Game.roster.get(_snipe_who, {}).get("name", "?")), toward,
			acts[act] if act >= 0 and act < acts.size() else "NOTHING AT ALL",
			here.distance_to(_snipe_was),
			int(world.player_state.get(_snipe_who, {}).get("hp", 0)),
			int(bot.get("weapon", 13)),
			float(Time.get_ticks_msec() - int(bot.get("threat_ms", 0))) * 0.001])

## WORLD_SPREAD_TEST=1: are the defenders a position, or a queue?
##
## "They just march around the flag" and "they should spread out and set
## up a platoon harbour" are both claims about the SHAPE a guard makes,
## and a shape is measurable: how far the nearest defender is from each
## other defender, and how much of the compass around the flag has
## somebody covering it. A conga line round a pole scores a tiny nearest
## distance and a couple of quadrants; a harbour scores a real gap and
## all four.
var _spread_t := 0.0
var _spread_said := 0.0

func tick_spread(delta: float) -> void:
	if OS.get_environment("WORLD_SPREAD_TEST") != "1" or world == null:
		return
	if world.match_phase != "BATTLE" or world.ctf._flags.is_empty():
		return
	_spread_t += delta
	if _spread_t - _spread_said < 20.0:
		return
	_spread_said = _spread_t
	for team_i: int in world.ctf._flags.keys():
		var home: Vector3 = world.ctf._flags[team_i].get("home", Vector3.INF)
		if home == Vector3.INF:
			continue
		var guard: Array = []
		for id: String in world.match_alive.keys():
			if int(Game.roster.get(id, {}).get("team", -1)) != team_i:
				continue
			var at: Vector3 = world.player_state.get(id, {}).get("pos", Vector3.INF)
			if at == Vector3.INF or world.downed_ids.has(id):
				continue
			if Vector2(at.x - home.x, at.z - home.z).length() < 16.0:
				guard.append(at)
		if guard.size() < 2:
			print("SPREAD: t=%.0fs team %d has %d on the base"
				% [_spread_t, team_i, guard.size()])
			continue
		var closest := 999.0
		var quadrants := {}
		for a in guard.size():
			quadrants[int(floor((atan2(float(guard[a].z) - home.z,
				float(guard[a].x) - home.x) + TAU) / (TAU / 4.0))) % 4] = true
			for b in range(a + 1, guard.size()):
				closest = minf(closest, Vector3(guard[a]).distance_to(guard[b]))
		print("SPREAD: t=%.0fs team %d guard=%d nearest_pair=%.1f sides_covered=%d/4"
			% [_spread_t, team_i, guard.size(), closest, quadrants.size()])

func tick(delta: float) -> void:
	tick_ghost(delta)
	tick_siege(delta)
	tick_pole(delta)
	tick_snipe(delta)
	tick_spread(delta)
	tick_huddle(delta)
	tick_length(delta)
	tick_roof(delta)
	tick_roundclock(delta)
	tick_capture(delta)
	tick_switch(delta)
	tick_revive(delta)
	tick_resize(delta)
	tick_kick(delta)
	tick_win(delta)
	tick_bot_watch(delta)
	tick_smoke(delta)

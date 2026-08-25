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
		var at: Vector3 = world.bots.roster[id].pos
		var was: Vector3 = _watch_from.get(id, at)
		var gone := Vector2(at.x - was.x, at.z - was.z).length()
		moved_total += gone
		if gone < 2.0:
			stuck += 1
			print("BOTWATCH %s STUCK at (%d,%d,%d), moved %.1f in 10s" % [
				str(Game.roster.get(id, {}).get("name", "?")),
				floori(at.x), floori(at.y), floori(at.z), gone])
		_watch_from[id] = at
	if counted > 0:
		print("BOTWATCH %d/%d stuck, average %.1f blocks in 10s" % [
			stuck, counted, moved_total / float(counted)])


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
		print("ROOF: t=%.0fs team %d wall=%d roof=%d" % [_roof_t, team_i, wall, roof])

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

func tick(delta: float) -> void:
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

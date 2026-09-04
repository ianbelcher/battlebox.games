class_name RoomSetup
## WHAT THIS ROOM WAS ASKED TO BE, read off the environment and applied
## to the world before anybody can connect.
##
## The front page sets a game up BEFORE it exists — mode, map, size, round
## length, how many players it has seats for (see game_setup.gd). The lobby hands those over as environment when it
## starts this process (lobby/lobby.py's settings_env), and this is the
## end of that wire.
##
## BEFORE ANYBODY CONNECTS is the whole point. Every one of these can also
## be changed from the world menu mid-game, and every one of them costs
## something when it is: changing the map resets the world under whoever
## is standing in it, changing the mode ends the round being played. Set
## here they cost nothing, because there is no round and nobody is
## standing anywhere yet.
##
## THE MAP AND THE SIZE ARE NOT HERE. ChunkStore already took them off
## WORLD_THEME and WORLD_SIZE when it generated the terrain, which is a
## step earlier than this — and that is exactly why the world genuinely IS
## the map that was asked for rather than being reset into it a moment
## later. All this does with them is copy the size the store actually
## used, so the world menu's size row agrees with the ground people are
## standing on.
##
## Its own file, and not a dozen lines inside world.gd, because world.gd
## is the wire protocol and is already at the size ceiling the style test
## enforces. Anything that is not an RPC belongs beside it rather than in
## it.

const MODES := ["creative", "battle", "ctf", "holdout"]

## How many seats a room has, when nobody said. Computer players fill
## the ones people are not in, so this is the size of the game.
static func wanted_players(fallback: int) -> int:
	return clampi(EnvConfig.number("WORLD_PLAYERS", fallback), 0, Game.MAX_PLAYERS)

## Apply everything the environment asked for. `world` is the WorldNode;
## untyped because this is a plain helper and typing it would make the two
## files depend on each other in both directions.
static func apply(world: Node) -> void:
	world.battle_size = float(world.store.world_size)
	var wanted := EnvConfig.text("WORLD_MODE", "")
	if wanted in MODES:
		world.game_mode = wanted
		world.match_loop = wanted != "creative"
	var minutes := EnvConfig.number("WORLD_ROUND_MINUTES", 0)
	if minutes > 0:
		# One setting on the front page, two clocks behind it: battle
		# royale's storm and last flag standing's round are different
		# lengths of different things, and only one of them is running.
		if world.game_mode == "holdout":
			world.holdout_minutes = clampf(float(minutes), 1.0, 99.0)
		else:
			world.storm_minutes = clampf(float(minutes), 2.0, 99.0)
	var target := EnvConfig.number("WORLD_CTF_TARGET", 0)
	if target > 0:
		world.ctf_target = clampi(target, 1, 25)
	# HOW MANY SIDES, set before a single computer player is spawned —
	# they are spread across whatever teams exist at the moment they are
	# made, so doing this afterwards would mean redistributing a room full
	# of them. sv_add_team and sv_remove_team go one at a time and each
	# broadcasts; there is nobody here to broadcast to yet.
	var teams := EnvConfig.number("WORLD_TEAMS", 0)
	if teams > 0:
		world.team_count = clampi(teams, 2, 24)
		world.team_names = world.TEAM_NAMES.slice(0, world.team_count)
	# HOW MANY SEATS, dealt evenly across those sides: a hundred over nine
	# teams is ninety-nine, eleven a side. Computer players fill whichever
	# seats people are not in (BotDirector.fill), so this is the size of
	# the game rather than a count of anybody in particular.
	Game.player_limit = GameSetup.seats_for(
		wanted_players(world.DEFAULT_PLAYERS), world.team_count)
	if EnvConfig.has("WORLD_REVIVE"):
		world.revive_mode = clampi(
			EnvConfig.number("WORLD_REVIVE", world.revive_mode),
			ReviveRule.NONE, ReviveRule.MATES_AND_FLAG)
	if EnvConfig.has("WORLD_DROP_KO"):
		world.drop_on_knockout = EnvConfig.flag("WORLD_DROP_KO")
	# WHO CAN FLY, as one of FlyRule's four answers turned back into the
	# pair of defaults the world keeps. Two defaults rather than one
	# because "computers only" and "humans only" cannot be said with a
	# single switch — see FlyRule.
	var flying := EnvConfig.text("WORLD_FLY", "")
	if flying in FlyRule.ANSWERS:
		world.battle_fly = FlyRule.people_fly(flying)
		world.battle_fly_bots = FlyRule.computers_fly(flying)
	print(describe(world))

## One line on the room's stdout saying what it came up as. The lobby
## prefixes it with the room's code, so a log of eight rooms says which
## one is the desert — and a setting that failed to arrive shows up here
## rather than as a child reporting that the map button did nothing.
static func describe(world: Node) -> String:
	var minutes: float = world.holdout_minutes if world.game_mode == "holdout" \
		else world.storm_minutes
	return "ROOM setup mode=%s map=%s size=%d minutes=%d seats=%d teams=%d" % [
		world.game_mode, world.store.theme, world.store.world_size,
		int(minutes), Game.player_limit, world.team_count]

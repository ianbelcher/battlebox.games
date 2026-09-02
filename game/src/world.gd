class_name WorldNode
extends Node
## The world node, added as /root/Game/World on server and clients alike
## (identical path = RPC routing). On the server it owns the ChunkStore, the
## day/night clock, critters, sapling growth and player persistence. On a
## client it owns the ChunkView, player avatars, critters and the sky.
##
## Wire protocol (client -> server sv_*, server -> clients cl_*):
##   sv_hello                      -> cl_world_info(spawn, clock, source, day_length)
##   sv_request_chunks([Vector2i]) -> cl_chunk(cx, cz, zstd_blob) each
##   sv_where(slot)                -> cl_where(slot, pos, treasures)
##   sv_pos(slot, pos, yaw, anim)     (unreliable, ~12 Hz per player)
##   sv_edit(slot, pos, block)     -> cl_edit(pos, block, by_id) + cl_treasures
##   sv_pet(slot, critter_id)      -> cl_pet(critter_id)
##   (server timers)               -> cl_clock(frac, day_length), cl_critters(payload)

const EDIT_RANGE := 10.0
## How often untouched chunks are dropped from the server's cache. Nothing
## is written to disk on this tick — or on any other; see ChunkStore.
const CACHE_TRIM_SECONDS := 60.0
const MAX_CRITTERS := 56
const CRITTERS_PER_PLAYER := 9

signal world_ready
signal treasures_changed
signal edit_applied(pos: Vector3i, block: int, by_id: String)
signal survival_changed
signal hearts_changed
signal survival_ended(seconds: float, bonked: int)
signal match_changed
signal storm_changed
signal map_list_changed
signal battle_config_changed
var client_minutes := 5
var client_size := 250
var client_loot := false
var client_fly := false
var client_fly_bots := false
## Client mirrors of the mode settings the menu draws. See cl_battle_config.
var client_drop := false
var client_revive_mode := ReviveRule.MATES_AND_FLAG
var client_holdout_minutes := HoldoutRules.ROUND_MINUTES
var client_ctf_target := 3
var client_team_names: Array = TEAM_NAMES.slice(0, DEFAULT_TEAMS)
var client_world := ""
var client_mode := "creative"

## EITHER FLAG MODE, as the client sees it. Capture the flag and last
## flag standing are the same board — bases, poles, flags, the panel that
## lists them — and everything that draws that board wants both. The
## server-side twin is CtfDirector.active().
func flag_mode() -> bool:
	return client_mode == "ctf" or client_mode == "holdout"
var map_list: Array = []
## Low-res whole-island backdrop for the radar (192x192, 4 blocks/px) so
## the map shows the world beyond what's rendered, even on slow machines.
var overview := PackedByteArray()

func overview_block(wx: int, wz: int) -> int:
	if overview.is_empty():
		return 0
	var ox := wx / 4 + 96
	var oz := wz / 4 + 96
	if ox < 0 or ox >= 192 or oz < 0 or oz >= 192:
		return 0
	return overview[oz * 192 + ox]

## Server: rough top-block guess from the pure terrain function — cheap,
## no chunk generation needed. Imported maps skip it (no pure function).
func _build_overview() -> void:
	overview = PackedByteArray()
	if store == null or store.source != "procedural":
		return
	overview.resize(192 * 192)
	for oz in 192:
		for ox in 192:
			var wx := (ox - 96) * 4
			var wz := (oz - 96) * 4
			# OUTSIDE THE WORLD IS NOTHING. The generator is a pure
			# function and will happily invent terrain forever, so
			# without this the radar drew a full island — grass, beaches,
			# snow — all round a 50-block world, and on the space map it
			# drew grass and ice over what should be black. Air reads as
			# the radar's background, which is what "off the map" should
			# look like.
			if not store.gen.in_bounds(wx, wz):
				overview[oz * 192 + ox] = Blocks.AIR
				continue
			var h: int = store.gen.height_at(wx, wz)
			h -= store.gen.lake_depth_at(wx, wz, h)
			overview[oz * 192 + ox] = _overview_block_for(h)
## What a column of this height reads as on the radar. Per THEME: the
## space map has no grass and no snow on it, and painting it with the
## classic island palette is why it came out looking like Earth.
func _overview_block_for(h: int) -> int:
	match store.theme:
		"desert":
			return Blocks.SAND if h > WorldGen.SEA_LEVEL else Blocks.WATER
		"space":
			# Grey regolith, and the "sea" is the void between craters.
			return Blocks.STONE if h > WorldGen.SEA_LEVEL else Blocks.AIR
		"sky":
			return Blocks.GRASS if h > WorldGen.SEA_LEVEL else Blocks.AIR
	var block := Blocks.GRASS
	if h <= WorldGen.SEA_LEVEL:
		block = Blocks.WATER
	elif h <= WorldGen.SEA_LEVEL + 2:
		block = Blocks.SAND
	elif h > WorldGen.SEA_LEVEL + 22:
		block = Blocks.SNOW
	return block

signal reset_vote_started
signal reset_result(happened: bool)

## WORLD_FAST=1 shrinks the day and sapling growth for quick testing.
static func fast_mode() -> bool:
	return OS.get_environment("WORLD_FAST") == "1"

## How long a full sunrise-to-sunrise takes when nobody is fighting.
##
## Four minutes, not ten. A day you never see the end of is a day that is
## just "the weather today" — you spend a whole session in the same light.
## At four minutes the sun visibly moves while you build, dusk arrives as
## an event, and being caught out in the dark is a thing that happens and
## then passes.
const IDLE_DAY_SECONDS := 240.0
## Nothing sensible comes of a day shorter than this — the sky strobes.
const MIN_DAY_SECONDS := 45.0

## Seconds per full day/night cycle, right now (WORLD_FAST=1 quarters it).
##
## A BATTLE fits exactly one day into the match, whatever length the match
## is set to: a three-minute round runs dawn → noon → dusk → night → dawn
## and ends where it started. Every round therefore has the same shape and
## the same last-minute darkness, rather than being decided by whatever
## time of day the clock happened to be at when someone pressed Start.
var day_length := 60.0 if fast_mode() else IDLE_DAY_SECONDS

## What time it is when a world (or a battle) begins.
##
## Random, so no two starts feel the same — the world used to open at a
## fixed morning and every battle was hard-set to 0.79, which is a few
## minutes to seven in the evening. Every single round began at dusk and
## went dark, which read as "this game is always night".
##
## WORLD_CLOCK pins it (0 midnight, 0.25 dawn, 0.5 noon, 0.75 dusk) so the
## lighting at a particular hour can be looked at on purpose rather than
## waited for.
static func _random_clock() -> float:
	var forced := OS.get_environment("WORLD_CLOCK")
	if forced.is_valid_float():
		return fposmod(forced.to_float(), 1.0)
	return randf()

static func growth_msec() -> int:
	return 8_000 if fast_mode() else 100_000

# Shared
var spawn_pos := Vector3i(0, 30, 0)
var clock := 0.35            # day fraction: 0 midnight, 0.25 dawn, 0.5 noon
var source := "procedural"
var treasures: Dictionary = {}   # player id -> int (client mirror)
var hearts: Dictionary = {}      # player id -> int, during survival
var survival_active := false
var survival_wave := 0
## Battle royale: IDLE / LOBBY / DROP / BATTLE / END (mirrored on clients).
const TEAM_NAMES := ["Red", "Blue", "Green", "Yellow", "Purple", "Orange",
	"Cyan", "Pink", "Lime", "Navy", "Brown", "White", "Maroon", "Teal",
	"Gold", "Magenta", "Olive", "Sky", "Coral", "Violet", "Mint", "Slate",
	"Peach", "Onyx"]
const TEAM_COLORS := [Color("ff5a5a"), Color("4a9df8"), Color("51c979"),
	Color("ffd166"), Color("9b45e0"), Color("ff9a3d"), Color("46d8d8"),
	Color("ff7ab8"), Color("a8e05f"), Color("3550b8"), Color("a5713f"),
	Color("f0f0f0"), Color("b03040"), Color("2f8f8f"), Color("d8a818"),
	Color("e040e0"), Color("909020"), Color("7ec8ff"), Color("ff8a70"),
	Color("8858d8"), Color("90e8b8"), Color("708098"), Color("ffc8a0"),
	Color("484858")]
## FIVE. With a cap of 50 that is ten a side, and five is also enough
## colours for a table of children to each want a different one.
const DEFAULT_TEAMS := 5
## How many computer players a new world starts with. Enough for a game
## to be a game the moment somebody walks in.
const DEFAULT_BOTS := 5
var team_count := DEFAULT_TEAMS
var selected_map := ""
## "battle" = matches loop continuously · "creative" = free build/play.
var game_mode := "creative"
## Kid-tuned battle health: plenty of hearts, and after any hit you're
## untouchable for a moment — no more getting deleted in one volley.
const MATCH_HP := 8
const MERCY_MS := 2000
## Display names for the teams, A..X by default; renameable from the
## Players view. Size always equals team_count.
## Named after their colour — "Blue" — never "B". A child cannot be asked
## to remember which letter they were.
var team_names: Array = TEAM_NAMES.slice(0, DEFAULT_TEAMS)
var match_phase := "IDLE"
## Soft edge for players: the world's hard chunk bound plus a splash of
## swimmable ocean — nobody drifts into the infinite procedural sea.
## A FIXED number, and nothing to do with how big this world is. Kept
## only for the ocean backdrop's draw distance. Do not use it to decide
## where a player may walk — see world_half().
var world_radius := float(ChunkStore.WORLD_RADIUS_CHUNKS) * 16.0 + 16.0

## Half the playable slab, in blocks, as the CLIENT knows it.
##
## The world is a SQUARE `client_size` on a side centred on the origin,
## and this is the only thing that should decide how far you can walk.
## Players used to be stopped by a CIRCLE of `world_radius` — a constant
## of 250 or 400 whatever the map's real size — so on any smaller world
## you strolled straight past the terrain, and the server, seeing you
## outside the map, put you back at the spawn. Walking to the edge of a
## 250-block world teleported you to the middle of it.
func world_half() -> float:
	return maxf(8.0, float(int(client_size) / 2))
var match_seconds := 0.0
var storm_radius := 0.0
var storm_center := Vector3.ZERO

# Client
## Explosions, fireworks and confetti (client only). See world_fx.gd.
var fx: WorldFx = null
var chunks: ChunkView = null
var players: Node3D = null
var critter_view: CritterView = null
## The boats and cars. `vehicles` is the server's list; `vehicle_view` is
## every client's copy of it, and is also what a Player asks whether there
## is a deck under its feet.
var vehicles: VehicleDirector = null
var vehicle_view: VehicleView = null
var monster_view: MonsterView = null
var orbs: OrbView = null
var crates: CrateView = null
var _storm_wall: MeshInstance3D = null
var sky: DayNight = null
var _ready_announced := false

# Server
var store: ChunkStore = null
## The computer players (server only). See bot_director.gd — every RPC
## that touches bots stays here and calls in there, so this file is still
## the whole of the wire protocol.
var bots: BotDirector = null
## The battle (server only). See match_director.gd.
var battle: MatchDirector = null
## Capture the flag (server only). See ctf_director.gd.
var ctf: CtfDirector = null
## Water, fire, growth and explosions (server only). See terrain_sim.gd.
var terrain: TerrainSim = null
## The animals (server only). See critter_director.gd.
var critters_sim: CritterDirector = null
## Grump raids and supply crates (server only). See survival_director.gd.
var survival: SurvivalDirector = null
## The WORLD_*_TEST dev hooks (server only). See world_probes.gd.
var probes: WorldProbes = null
## Where everyone is, as far as the server is concerned: the one place
## that answers "where is this player". Written by sv_pos for humans and
## by the bot director for computer players, so nothing downstream has to
## care which kind it is looking at.
##
## id -> {pos: Vector3, yaw: float, treasures: int, name: String, ...}
var player_state: Dictionary = {}
var _chunk_send_queues: Dictionary = {}  # peer -> Array[Vector2i]
## Survival ("the attack"): server-side monster sim.
var monsters_by_id: Dictionary = {}       # id -> {pos, hp, next_bonk_ms}
var _downed: Dictionary = {}
var _known_roster_ids: Dictionary = {}

func _ready() -> void:
	if multiplayer.is_server():
		_server_setup()
	else:
		_client_setup()

# ------------------------------------------------------------------
# Server
# ------------------------------------------------------------------

func _server_setup() -> void:
	store = ChunkStore.new()
	bots = BotDirector.new()
	bots.name = "Bots"
	bots.world = self
	add_child(bots)
	battle = MatchDirector.new()
	battle.name = "Match"
	battle.world = self
	add_child(battle)
	ctf = CtfDirector.new()
	ctf.name = "Ctf"
	ctf.world = self
	add_child(ctf)
	terrain = TerrainSim.new()
	terrain.name = "Terrain"
	terrain.world = self
	add_child(terrain)
	critters_sim = CritterDirector.new()
	critters_sim.name = "Critters"
	critters_sim.world = self
	add_child(critters_sim)
	vehicles = VehicleDirector.new()
	vehicles.name = "Vehicles"
	vehicles.world = self
	add_child(vehicles)
	survival = SurvivalDirector.new()
	survival.name = "Survival"
	survival.world = self
	add_child(survival)
	probes = WorldProbes.new()
	probes.name = "Probes"
	probes.world = self
	add_child(probes)
	source = store.source
	spawn_pos = store.find_spawn()
	_build_overview()
	clock = _random_clock()
	print("World spawn at %s, clock %.2f" % [spawn_pos, clock])
	_load_battle_setup()
	RoomSetup.apply(self)
	if vehicles != null:
		vehicles.stock_world()
	# SOMEBODY TO PLAY AGAINST, without anybody having to go and ask for
	# them. A fresh world had nobody in it at all, so the first child in
	# is alone in a field until an adult opens the world menu and presses
	# a button five times.
	#
	# Added here rather than when the first player arrives, so the number
	# is a property of the world and not of who is looking at it — the
	# host can add or remove them from the Players tab like any other.
	for _i in RoomSetup.wanted_bots(DEFAULT_BOTS):
		bots.spawn()
	var trim := Timer.new()
	trim.wait_time = CACHE_TRIM_SECONDS
	trim.timeout.connect(_server_trim_cache)
	add_child(trim)
	trim.start()
	var clock_timer := Timer.new()
	clock_timer.wait_time = 5.0
	clock_timer.timeout.connect(func() -> void: cl_clock.rpc(clock, day_length))
	add_child(clock_timer)
	clock_timer.start()
	var critter_timer := Timer.new()
	critter_timer.wait_time = 0.33
	critter_timer.timeout.connect(critters_sim.tick)
	add_child(critter_timer)
	critter_timer.start()
	var growth_timer := Timer.new()
	growth_timer.wait_time = 7.0
	growth_timer.timeout.connect(terrain.tick_growth)
	add_child(growth_timer)
	growth_timer.start()
	Game.roster_changed.connect(_server_on_roster_changed)

func _process(delta: float) -> void:
	clock = fposmod(clock + delta / maxf(day_length, MIN_DAY_SECONDS), 1.0)
	if not multiplayer.is_server() and match_phase != "IDLE":
		# The server only sends match_seconds at phase transitions — tick
		# it locally so countdowns actually count.
		match_seconds = maxf(0.0, match_seconds - delta)
	if multiplayer.is_server():
		# One day-length rule, in one place. A battle squeezes a whole day
		# into the match; the moment there is no battle it goes back to
		# the idle rate. There are three separate paths back to IDLE (a
		# world reset, switching to creative, the last match ending) and
		# stating the invariant here means none of them can forget.
		var idle_rate := 60.0 if fast_mode() else IDLE_DAY_SECONDS
		if match_phase == "IDLE" and not is_equal_approx(day_length, idle_rate):
			day_length = idle_rate
			cl_clock.rpc(clock, day_length)
		_drain_chunk_queues()
		terrain.dawn_check()
		terrain.tick_bombs()
		terrain.tick_smoke()
		probes.tick(delta)
		# Checked on the tick rather than hung off `roster_changed`: that
		# signal is emitted by the roster BROADCAST, which is a client RPC,
		# so on the server it does not reliably fire at all. The call is a
		# single boolean test once the opening move has been made.
		bots.ensure_opening()
		terrain.tick_boom_traps()
		battle.tick(delta)
		bots.tick(delta)
		terrain._water_accum += delta
		if terrain._water_accum > 0.3:
			terrain._water_accum = 0.0
			terrain.tick_water()
		terrain._fire_accum += delta
		if terrain._fire_accum > 0.8:
			terrain._fire_accum = 0.0
			terrain.tick_fire()

## Drop chunks that can be regenerated exactly, so a server left up for
## days does not hold every chunk anyone ever walked through.
##
## This used to also zstd every edited chunk out to a file, and write the
## world clock alongside it, every 25 seconds. Nothing ever read any of it:
## the world is regenerated from the seed on every boot, and the chunk
## files were deleted at startup. It was compression and disk I/O on the
## server's only thread, on a timer, for a result that was thrown away.
func _server_trim_cache() -> void:
	if match_phase != "IDLE":
		return  # nothing gets dropped out from under a live match
	var dropped := store.trim_cache()
	if dropped > 0:
		print("World: dropped %d regenerable chunks from cache" % dropped)

func _server_on_roster_changed() -> void:
	# Forget players whose roster entries vanished. NOTHING about a player
	# is written to disk — see sv_where().
	for id: String in _known_roster_ids.keys():
		if not Game.roster.has(id):
			player_state.erase(id)
	_known_roster_ids.clear()
	for id: String in Game.roster.keys():
		_known_roster_ids[id] = true

@rpc("any_peer", "reliable")
func sv_hello() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	cl_world_info.rpc_id(peer, spawn_pos, clock, source, day_length)
	cl_map_list.rpc_id(peer, ChunkStore.list_maps())
	cl_overview.rpc_id(peer, overview)
	cl_battle_config.rpc_id(peer, int(storm_minutes), int(battle_size), loot_only,
		battle_fly, team_count, drop_on_knockout, revive_mode, ctf_target,
		battle_fly_bots, int(holdout_minutes))
	cl_teams.rpc_id(peer, team_names)
	cl_mode.rpc_id(peer, game_mode)
	cl_world_sel.rpc_id(peer, selected_map if not selected_map.is_empty() \
		else (store.current_map_key if not store.current_map_key.is_empty() else store.theme))
	var payload: Array = []
	for crate_id: int in crates_by_id.keys():
		payload.append([crate_id, crates_by_id[crate_id].weapon, crates_by_id[crate_id].pos])
	cl_crates.rpc_id(peer, payload)
	if vehicles != null:
		cl_vehicles.rpc_id(peer, vehicles.payload())
	# THE ROUND AS IT STANDS. Everything above describes the world; none of
	# it says whether a game is being played in it, and a round that is
	# already running is exactly what somebody joining a server that has
	# been up all night walks into.
	cl_match_state.rpc_id(peer, match_phase, battle._timer,
		match_alive.keys(), downed_ids.keys(), out_ids.keys())
	# A room created as a battle has been sitting IDLE waiting for the
	# person who created it. This is them.
	_open_round_if_waiting()
	if ctf.active() and not ctf._flags.is_empty():
		cl_flags.rpc_id(peer, ctf._flag_payload(), ctf_scores, ctf_target,
			ctf_caps, ctf_lost, ctf_player_caps)

@rpc("any_peer", "reliable")
func sv_request_chunks(list: Array) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var queue: Array = _chunk_send_queues.get(peer, [])
	for item in list:
		if item is Vector2i and queue.size() < 400:
			queue.append(item)
	_chunk_send_queues[peer] = queue

## Sending is spread over frames so a join burst (~90 chunks) doesn't stall
## the server or overflow the socket buffer.
func _drain_chunk_queues() -> void:
	for peer: int in _chunk_send_queues.keys():
		if not (peer in multiplayer.get_peers()):
			_chunk_send_queues.erase(peer)
			continue
		var queue: Array = _chunk_send_queues[peer]
		var batch: Array = []
		while batch.size() < 6 and not queue.is_empty():
			var cpos: Vector2i = queue.pop_front()
			batch.append([cpos.x, cpos.y, store.get_chunk_compressed(cpos)])
		if batch.size() == 1:
			cl_chunk.rpc_id(peer, batch[0][0], batch[0][1], batch[0][2])
		elif not batch.is_empty():
			cl_chunk_batch.rpc_id(peer, batch)
		if queue.is_empty():
			_chunk_send_queues.erase(peer)

## Relay one packet of somebody's voice to everyone else.
##
## Only the NATIVE builds use this. In a browser the audio goes peer to
## peer and never touches the server; on desktop, Godot's WebRTC needs a
## GDExtension that standard builds do not ship, so the socket that is
## already here carries it and the server hands it on.
##
## Unreliable on purpose: a late voice packet is worth less than nothing —
## it arrives after the moment it belonged to and stalls everything behind
## it. Dropping is the correct failure.
@rpc("any_peer", "unreliable_ordered")
func sv_voice_audio(frame: PackedByteArray) -> void:
	if not multiplayer.is_server():
		return
	# ~40 ms of 16 kHz mono at a byte a sample. Anything much larger is
	# not a voice frame and is not getting relayed to everybody.
	if frame.size() > 2048:
		return
	var from_peer := multiplayer.get_remote_sender_id()
	for peer: int in multiplayer.get_peers():
		if peer != from_peer:
			cl_voice_audio.rpc_id(peer, from_peer, frame)

@rpc("authority", "unreliable_ordered")
func cl_voice_audio(from_peer: int, frame: PackedByteArray) -> void:
	Voice.on_audio(from_peer, frame)

## Carry one WebRTC handshake message from one machine to another.
##
## The server reads nothing and stores nothing: it is a post box, because
## clients in this game only ever have a connection to the server and so
## have no way to reach each other to set the call up. Voice itself never
## touches this server — once the handshake lands, the audio goes machine
## to machine.
@rpc("any_peer", "reliable")
func sv_voice_signal(to_peer: int, payload: String) -> void:
	if not multiplayer.is_server():
		return
	var from_peer := multiplayer.get_remote_sender_id()
	if to_peer <= 1 or to_peer == from_peer:
		return
	if payload.length() > 8192:
		return  # an SDP is a couple of KB; anything larger is not one
	cl_voice_signal.rpc_id(to_peer, from_peer, payload)

@rpc("authority", "reliable")
func cl_voice_signal(from_peer: int, payload: String) -> void:
	Voice.on_signal(from_peer, payload)

@rpc("any_peer", "reliable")
func sv_where(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	var entry: Dictionary = Game.roster.get(id, {})
	if entry.is_empty():
		return
	# NOTHING IS REMEMBERED between sessions. Where you were standing is
	# state that belongs to a world, and this game throws its world away
	# on every restart and every resize — so keeping it on disk only ever
	# meant restoring a position that made no sense in the world that
	# replaced it. Every join is a fresh placement.
	# JOINING A ROUND ALREADY IN PROGRESS.
	#
	# This used to drop you at a random far corner with whatever hotbar you
	# happened to have — the creative blocks — and without adding you to
	# the match at all. So anyone arriving after the drop was a spectator
	# who did not know it: no team kit, nowhere near their base, and not in
	# `match_alive`, which is what decides whether you can be hurt.
	#
	# Everything the drop does for the people who were there at the start
	# has to happen here too, or joining late is a different game.
	if match_phase != "IDLE":
		var team := int(entry.get("team", -1))
		if team < 0:
			# Smallest team, same rule the drop uses.
			var counts: Array[int] = []
			counts.resize(maxi(team_count, 1))
			for other: String in Game.roster.keys():
				var ot := int(Game.roster[other].get("team", -1))
				if ot >= 0 and ot < counts.size():
					counts[ot] += 1
			team = 0
			for t in counts.size():
				if counts[t] < counts[team]:
					team = t
			Game.roster[id].team = team
			Game.cl_roster.rpc(Game.roster)
		var seats: PackedStringArray = battle.team_seats.get(team, PackedStringArray())
		if seats.find(id) < 0:
			seats.append(id)
			battle.team_seats[team] = seats
		var seat := maxi(seats.find(id), 0)
		var spot := ctf.home_spot(team, seat) if ctf.active() \
			else battle.team_start_spot(team, seat)
		player_state[id] = {"pos": spot, "treasures": 0,
			"name": str(entry.name), "hp": MATCH_HP}
		match_alive[id] = true
		cl_treasures.rpc(id, 0)
		cl_hearts.rpc(id, MATCH_HP)
		cl_where.rpc_id(peer, slot, spot, 0)
		cl_stand.rpc(id, spot, loot_only, Weapons.starting_kit(game_mode), true)
		return
	var pos := _far_spawn()
	player_state[id] = {"pos": pos, "treasures": 0, "name": str(entry.name)}
	cl_treasures.rpc(id, 0)
	cl_where.rpc_id(peer, slot, pos, 0)

## Somewhere to stand, well away from everyone already playing — and
## always on the map. Every candidate and the fallback both go through
## ChunkStore.safe_stand(), which is the only thing allowed to decide
## where a person ends up.
func _far_spawn() -> Vector3:
	var others: Array = []
	for state: Dictionary in player_state.values():
		others.append(state.pos)
	if others.is_empty():
		return store.safe_stand(Vector3(spawn_pos), 3.0)
	var best := store.safe_stand(Vector3(spawn_pos), 3.0)
	var best_score := -1e9
	# Scale the search to the WORLD: hunting for a spot 85-125 blocks away
	# on a 50-block map finds nothing and falls through every time.
	var reach := clampf(float(store.half_extent()) * 0.8, 8.0, 125.0)
	for i in 24:
		var anchor: Vector3 = others[randi() % others.size()]
		var angle := randf() * TAU
		var dist := randf_range(reach * 0.5, reach)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		if not store.inside_world(wx, wz, 6):
			continue
		var y := store.surface_y(wx, wz)
		if y <= WorldGen.SEA_LEVEL or y >= WorldGen.CHUNK_H - 8:
			continue
		var nearest := 1e9
		for other: Vector3 in others:
			nearest = minf(nearest, Vector2(wx - other.x, wz - other.z).length())
		if nearest > best_score:
			best_score = nearest
			best = store.safe_stand(Vector3(wx, 0, wz))
	return best

@rpc("any_peer", "unreliable_ordered")
func sv_pos(slot: int, pos: Vector3, yaw: float, anim: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	if not Game.roster.has(id):
		return
	# People send their OWN position, so a client still running in the
	# world that was just replaced will report coordinates from it.
	#
	# But WALKING INTO THE EDGE IS NORMAL and must not be punished. This
	# used to teleport anyone a couple of blocks past the limit back to
	# the spawn, so reaching the boundary of your own map threw you into
	# the middle of it. A position just outside is quietly clamped — per
	# axis, so you slide along the wall — and only one WILDLY outside is
	# treated as a stale world and reset.
	var half := float(store.half_extent())
	if absf(pos.x) > half + 32.0 or absf(pos.z) > half + 32.0:
		pos = store.safe_stand(Vector3(spawn_pos), 6.0)
		cl_where.rpc_id(peer, slot, pos,
			int(player_state.get(id, {}).get("treasures", 0)))
	else:
		pos.x = clampf(pos.x, -half, half)
		pos.z = clampf(pos.z, -half, half)
	var state: Dictionary = player_state.get(id, {"pos": pos, "treasures": 0,
		"name": str(Game.roster[id].name)})
	state.pos = pos
	player_state[id] = state
	cl_pos.rpc(id, pos, yaw, anim)

## PUT IT BACK. A client applies its own edits the instant they are made,
## without waiting for this server to agree — digging has to feel
## immediate. When the server then REFUSES one, that prediction is left
## standing: the block is still here, and gone on the screen of whoever
## tried to dig it.
##
## That is what made a lit Boom Block vanish and leave its sparks hanging
## in the air. Clicking one lights the fuse instead of digging it, which
## is a refusal, and nothing ever told the client so.
##
## Cheap: one cell, to one peer, only when an edit did not happen.
func _refuse_edit(peer: int, pos: Vector3i) -> void:
	cl_edits.rpc_id(peer, [[pos, store.get_block(pos)]])

@rpc("any_peer", "reliable")
func sv_edit(slot: int, pos: Vector3i, block: int) -> void:
	if not multiplayer.is_server():
		return
	if match_phase == "LOBBY" or match_phase == "SETUP":
		return  # pre-battle: run around, touch nothing
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	if not Game.roster.has(id):
		return
	var state: Dictionary = player_state.get(id, {})
	if state.is_empty() or Vector3(pos).distance_to(state.pos) > EDIT_RANGE:
		return
	var current := store.get_block(pos)
	if block == Blocks.AIR:
		if not can_carve(pos, current):
			_refuse_edit(peer, pos)
			return
		# Clicking a Boom Block LIGHTS it. Once lit it stays lit.
		#
		# Clicking a lit one used to snuff the fuse and pick the block up,
		# which sounds reasonable and was in practice a bug: digging
		# repeats every EDIT_REPEAT while the button is held, so lighting
		# a bomb and keeping your finger down defused it a fifth of a
		# second later and the block vanished in your hand. You could
		# barely light one on purpose. A fuse you cannot put out is also
		# simply better — it is a bomb.
		if current == Blocks.BOOM:
			for entry: Dictionary in terrain._bombs:
				if entry.pos == pos:
					_refuse_edit(peer, pos)
					return          # already counting down; leave it be
			terrain._bombs.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 2500})
			cl_fuse_fx.rpc(pos)
			# The digger predicted this block away. It is still here — it
			# is a lit bomb — so tell them.
			_refuse_edit(peer, pos)
			return
		if Blocks.is_collectible(current):
			state.treasures = int(state.treasures) + 1
			player_state[id] = state
			cl_treasures.rpc(id, state.treasures)
	else:
		if not (block in Blocks.HOTBAR):
			_refuse_edit(peer, pos)
			return
		if current != Blocks.AIR and not Blocks.is_cross(current) \
				and not Blocks.is_liquid(current):
			# Cross plants are soft: build straight through them. Anything
			# else is occupied, and the placer has already drawn a block
			# there that is not going to exist.
			_refuse_edit(peer, pos)
			return
		var supported := false
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if Blocks.is_solid(store.get_block(pos + off)):
				supported = true
				break
		if not supported:
			_refuse_edit(peer, pos)
			return
		match block:
			Blocks.SAPLING:
				terrain._saplings.append({"pos": pos, "at_msec": Time.get_ticks_msec()})
			Blocks.FIREWORK:
				terrain._rockets.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 1200})
			Blocks.SPONGE:
				terrain.drain(pos)
			Blocks.BOOM:
				terrain._boom_armed[pos] = Time.get_ticks_msec() + BOOM_ARM_MSEC
	if block != Blocks.BOOM:
		terrain._boom_armed.erase(pos)
	store.set_block(pos, block)
	cl_edit.rpc(pos, block, id)
	if block == Blocks.AIR:
		# Foliage has no roots of its own: dig the block it sat on and the
		# plant above pops with it.
		var above := pos + Vector3i(0, 1, 0)
		if Blocks.is_cross(store.get_block(above)):
			store.set_block(above, Blocks.AIR)
			cl_edit.rpc(above, Blocks.AIR, id)
		terrain.disturb_water([pos])

## Stamp a prefab structure: only air, liquids and plants are overwritten,
## so stamps can't wreck existing builds.
@rpc("any_peer", "reliable")
func sv_structure(slot: int, base: Vector3i, index: int, roll: int, facing := 0) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = player_state.get(id, {})
	if state.is_empty() or Vector3(base).distance_to(state.pos) > 12.0:
		return
	var pairs: Array = []
	for entry: Array in Structures.cells(index, roll, facing):
		var pos: Vector3i = base + (entry[0] as Vector3i)
		if pos.y <= 0 or pos.y >= WorldGen.CHUNK_H:
			continue
		var current := store.get_block(pos)
		if current == Blocks.AIR or Blocks.is_liquid(current) or Blocks.is_cross(current):
			store.set_block(pos, entry[1])
			pairs.append([pos, entry[1]])
	if not pairs.is_empty():
		cl_edits.rpc(pairs)

## Throwing orbs (always on): the shooter simulates the arc; everyone else
## renders it. Hits on players knock them about (no harm); hits on Grumps
## use the survival damage path.
@rpc("any_peer", "unreliable")
func sv_shoot(slot: int, origin: Vector3, dir: Vector3, kind: int) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if Game.roster.has(id):
		cl_orb.rpc(id, origin, dir, kind)

@rpc("authority", "unreliable")
func cl_orb(shooter_id: String, origin: Vector3, dir: Vector3, kind: int) -> void:
	if orbs != null:
		orbs.spawn(shooter_id, origin, dir, kind)
	# Other people's gunfire is audible, scaled by how close it is — so
	# you can HEAR a fight before you see it.
	if not shooter_id in Game.local_player_ids():
		var shot_vol := -_nearest_local_dist(origin) * 0.5
		if shot_vol > -40.0:
			match kind:
				0: Sfx.play("click", shot_vol - 8.0)
				1, 9, 15, 17: Sfx.play("thoomp", shot_vol - 4.0)
				13: pass
				_: Sfx.play("whoosh", shot_vol - 6.0, 1.1)

func _nearest_player_dist(id: String) -> float:
	if players == null:
		return 999.0
	for child in players.get_children():
		if child is Player and child.player_id == id:
			return _nearest_local_dist(child.position)
	return 999.0

## Projectile impact. Pellets pop the single block they hit (or light a Boom
## Block from afar); shells detonate like a lit charge, splashing Grumps too.
@rpc("any_peer", "reliable")
func sv_shot(slot: int, cell: Vector3i, kind: int) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = player_state.get(id, {})
	if state.is_empty() or Vector3(cell).distance_to(state.pos) > 300.0:
		return
	# A SHOT LANDED, AND ANY COMPUTER PLAYER NEAR IT HEARD IT.
	#
	# The other half of "you can zoom in and shoot at them and they won't
	# do anything", and the half that matters when you are good at it: a
	# HIT alerts through `match_hurt`, but a MISS used to be completely
	# silent, so walking your fire onto a bot from sixty blocks warned it
	# of nothing at all until the moment it lost a heart. This is the only
	# place every weapon's impact passes through.
	if match_phase == "BATTLE":
		bots.shot_landed(id, Vector3(cell), state.pos)
	match kind:
		14:  # Flare: a sky light in the shooter's team colour, nothing
			# to break. The colour is what makes it a signal and not just
			# a firework.
			cl_flare.rpc(Vector3(cell), _team_of(id))
			return
		15:  # Big Shooter: one big crater — 4.0, down from 5.6, which is
			# a bit over a third of the volume. It should be the loudest
			# thing on the field, not a terraforming tool.
			terrain.blast(cell, 4.0, [], cell)
			if match_phase == "BATTLE":
				for pid: String in match_alive.keys():
					if pid != id and teams_differ(id, pid) \
							and player_state.has(pid) \
							and Vector3(cell).distance_to(player_state[pid].pos) < 8.0:
						battle.hurt(pid, 3, Vector3(cell), Game.player_id(multiplayer.get_remote_sender_id(), slot))
			return
		1:  # Medium Shooter. 2.6, not 3.4: at the old radius a couple of
			# shots flattened whatever ground a player was standing on,
			# and this is the weapon everyone has most of the time.
			# Halving the VOLUME is what "half" means for a sphere, and
			# this has now been halved twice: 3.4 -> 2.6 -> 2.1.
			terrain.blast(cell, 2.1, [], cell)
			if match_phase == "BATTLE":
				for pid: String in match_alive.keys():
					if pid != id and teams_differ(id, pid) \
							and player_state.has(pid) \
							and Vector3(cell).distance_to(player_state[pid].pos) < 5.0:
						battle.hurt(pid, 2, Vector3(cell), Game.player_id(multiplayer.get_remote_sender_id(), slot))
			for monster_id: int in monsters_by_id.keys().duplicate():
				if Vector3(cell).distance_to(monsters_by_id[monster_id].pos) < 4.5:
					monsters_by_id[monster_id].hp = int(monsters_by_id[monster_id].hp) - 2
					var dead: bool = monsters_by_id[monster_id].hp <= 0
					if dead:
						monsters_by_id.erase(monster_id)
						survival._bonked_count += 1
					cl_zap_hit.rpc(monster_id, dead)
			return
		2:  # Grapple: client-side pull only.
			return
		3:  # Freeze Ray: water -> ice, Grumps frozen solid for a bit.
			var iced: Array = []
			for dy in range(-3, 4):
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						if store.get_block(pos) == Blocks.WATER:
							store.set_block(pos, Blocks.ICE)
							iced.append(pos)
			if not iced.is_empty():
				cl_batch.rpc(iced, Blocks.ICE)
			var now := Time.get_ticks_msec()
			for monster_id: int in monsters_by_id.keys():
				if Vector3(cell).distance_to(monsters_by_id[monster_id].pos) < 4.5:
					monsters_by_id[monster_id].frozen_until = now + 4000
			return
		4:  # Block Sucker: the hit block flies into the shooter's hotbar.
			var block := store.get_block(cell)
			if block != Blocks.AIR and can_carve(cell, block) \
					and Blocks.hardness(block) <= 2 and not Blocks.is_liquid(block):
				store.set_block(cell, Blocks.AIR)
				cl_edit.rpc(cell, Blocks.AIR, id)
				terrain.disturb_water([cell])
				cl_suck.rpc(id, block)
			return
		18:  # Paint Sprayer: ONE block, recoloured, in your team's colour.
			# It used to splat a 3x3x3 ball, which is no use for drawing
			# a line or marking a spot — and painting a whole cube of
			# space meant glass, leaves and anything see-through came
			# back as solid wool, so it read as CREATING blocks out of
			# nothing and filling in holes.
			if _paintable(cell):
				var spray_wool := _team_wool(id)
				store.set_block(cell, spray_wool)
				cl_batch.rpc([cell], spray_wool)
			return
		19:  # Smoke Bomb: a team-coloured "we are going THERE" marker.
			# Exactly one exists in the world at a time — throwing a new
			# one clears whoever's was up before, so the signal is never
			# ambiguous.
			_smoke_marker = {"pos": Vector3(cell), "team": _team_of(id),
				"until": Time.get_ticks_msec() + SMOKE_MSEC}
			cl_smoke.rpc(Vector3(cell), _team_of(id))
			return
		8:  # Paint Bomb: soft terrain becomes random wool.
			var wools := [Blocks.WOOL_RED, Blocks.WOOL_YELLOW, Blocks.WOOL_BLUE,
				Blocks.WOOL_GREEN, Blocks.WOOL_PINK, Blocks.WOOL_PURPLE, Blocks.WOOL_TEAL]
			var pairs: Array = []
			for dy in range(-3, 4):
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						if Vector3(dx, dy, dz).length() > 3.2:
							continue
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						if _paintable(pos):
							var wool: int = wools[randi() % wools.size()]
							store.set_block(pos, wool)
							pairs.append([pos, wool])
			if not pairs.is_empty():
				cl_edits.rpc(pairs)
			return
		9:  # Napalm Rocket: no crater — it sets the impact ablaze and the
			# blast itself hurts (2 hearts close in).
			cl_boom_fx.rpc(cell)
			if match_phase == "BATTLE":
				for pid: String in match_alive.keys():
					if pid != id and teams_differ(id, pid) \
							and player_state.has(pid) \
							and Vector3(cell).distance_to(player_state[pid].pos) < 5.0:
						battle.hurt(pid, 2, Vector3(cell), Game.player_id(multiplayer.get_remote_sender_id(), slot))
			var splashed: Array = []
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					for dy in range(-1, 2):
						var ring := maxi(absi(dx), absi(dz))
						if ring == 2 and randf() > 0.5:
							continue  # ragged outer edge
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						var block := store.get_block(pos)
						if (block == Blocks.AIR or Blocks.is_flammable(block)) \
								and terrain._fires.size() < 160:
							store.set_block(pos, Blocks.FIRE)
							terrain._fires[pos] = Time.get_ticks_msec() + randi_range(6000, 14000)
							splashed.append(pos)
			if not splashed.is_empty():
				cl_batch.rpc(splashed, Blocks.FIRE)
			return
		11:  # Wings do their work while held; the trigger does nothing.
			return
		12:  # (impact does nothing extra — the tunnel was carved at fire time)
			if false:
				pass
			return
		10:  # Grump Whistle: a wild Grump, raid or not (never mid-battle).
			if match_phase != "IDLE":
				return
			if monsters_by_id.size() < 30:
				monsters_by_id[survival._next_monster_id] = {"pos": Vector3(cell) + Vector3(0.5, 1.0, 0.5),
					"hp": 3, "next_bonk_ms": 0}
				survival._next_monster_id += 1
			return
	var current := store.get_block(cell)
	if current == Blocks.AIR or Blocks.is_liquid(current) or not can_carve(cell, current):
		return
	# Pellets only chew through soft materials and wood — stone+ shrugs.
	if Blocks.hardness(current) > 1 and current != Blocks.BOOM:
		return
	if current == Blocks.BOOM:
		for entry: Dictionary in terrain._bombs:
			if entry.pos == cell:
				return
		terrain._bombs.append({"pos": cell, "at_msec": Time.get_ticks_msec() + 2500})
		cl_fuse_fx.rpc(cell)
		return
	if Blocks.is_collectible(current):
		state.treasures = int(state.treasures) + 1
		cl_treasures.rpc(id, state.treasures)
	store.set_block(cell, Blocks.AIR)
	cl_edit.rpc(cell, Blocks.AIR, id)
	terrain.disturb_water([cell])

@rpc("any_peer", "reliable")
func sv_orb_hit(slot: int, target_id: String, hit_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var shooter := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if not Game.roster.has(shooter) or not Game.roster.has(target_id):
		return
	var target_state: Dictionary = player_state.get(target_id, {})
	if target_state.is_empty() or Vector3(target_state.pos).distance_to(hit_pos) > 4.0:
		return
	if match_phase == "BATTLE" and teams_differ(shooter, target_id):
		var shooter_pos: Vector3 = player_state.get(shooter, {}).get("pos", hit_pos)
		battle.hurt(target_id, 1, shooter_pos, shooter)
		cl_hit_ok.rpc_id(multiplayer.get_remote_sender_id())
		return
	cl_bonk.rpc(target_id, hit_pos)

## THE SWORD KILLS OUTRIGHT. That is the entire reason to carry one.
##
## It is the weapon everybody drops into a round holding, and against
## anything that shoots it was a joke: one heart a swing, at arm's length,
## against a Little Shooter putting out seven pellets a second from across
## the field. Nobody chose it, they endured it until they found a crate.
##
## Landing one now means you got inside somebody's guard — three blocks,
## in front of you, while they were presumably shooting at you — and that
## is worth a kill. It makes the opening of a battle royale a real
## standoff rather than a scramble, and it gives a defender on a flag
## mound something to be frightened of.
##
## Routed through `match_hurt` with the full bar rather than a special
## case, so every rule downstream still applies: the downed-vs-out
## decision, capture the flag's revive setting, the feed, the scoring.
@rpc("any_peer", "reliable")
func sv_sword_hit(slot: int, target_id: String, hit_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var attacker := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if not Game.roster.has(attacker) or not Game.roster.has(target_id):
		return
	var target_state: Dictionary = player_state.get(target_id, {})
	if target_state.is_empty():
		return
	# The server checks the reach itself. The client decides WHEN to swing;
	# it does not get to decide who was close enough to be hit by it.
	var attacker_pos: Vector3 = player_state.get(attacker, {}).get("pos", hit_pos)
	if attacker_pos.distance_to(Vector3(target_state.pos)) > SWORD_REACH + 1.2:
		return
	if match_phase != "BATTLE" or not teams_differ(attacker, target_id):
		cl_bonk.rpc(target_id, hit_pos)
		return
	battle.hurt(target_id, MATCH_HP, attacker_pos, attacker)
	cl_hit_ok.rpc_id(multiplayer.get_remote_sender_id())

## Digger: carve a 3x3 tunnel 15 blocks along the aim line, at fire time.
@rpc("any_peer", "reliable")
func sv_dig_tunnel(slot: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = player_state.get(id, {})
	if state.is_empty() or origin.distance_to(state.pos) > 14.0:
		return
	dir = dir.normalized()
	var bored: Array = []
	for step in range(1, 16):
		var center := Vector3i((origin + dir * step).round())
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var pos := center + Vector3i(dx, dy, dz)
					var block := store.get_block(pos)
					if block != Blocks.AIR and can_carve(pos, block) \
							and Blocks.hardness(block) <= 2 and not Blocks.is_liquid(block):
						store.set_block(pos, Blocks.AIR)
						bored.append(pos)
	if not bored.is_empty():
		cl_batch.rpc(bored, Blocks.AIR)
		terrain.disturb_water(bored)

@rpc("any_peer", "reliable")
func sv_shoot_critter(_slot: int, critter_id: int) -> void:
	if multiplayer.is_server() and critters_sim.critters.has(critter_id):
		critters_sim.critters.erase(critter_id)

@rpc("any_peer", "reliable")
func sv_pet(slot: int, critter_id: int) -> void:
	if not multiplayer.is_server():
		return
	if critters_sim.critters.has(critter_id):
		cl_pet.rpc(critter_id)












## HOW LONG A FRESHLY PLACED BOOM BLOCK IS INERT.
##
## Standing on one sets it off — that is the whole point of burying it —
## but you place a block by aiming at your own feet, so without a delay
## every player who laid one would be standing on it the same instant and
## blow themselves up. Two seconds is long enough to step off and not long
## enough for anybody to walk into the trap and survive it.
const BOOM_ARM_MSEC := 2000



const BOOM_RADIUS := 3.2


## ------------------------------------------------------------------
## Team colours: the paint sprayer, the flare and the smoke bomb all
## carry the thrower's team, which is what turns them from decoration
## into signals your side can read across a field.
## ------------------------------------------------------------------

const TEAM_WOOL := [Blocks.WOOL_RED, Blocks.WOOL_BLUE, Blocks.WOOL_GREEN,
	Blocks.WOOL_YELLOW, Blocks.WOOL_PURPLE, Blocks.WOOL_ORANGE,
	Blocks.WOOL_TEAL, Blocks.WOOL_PINK]

## How long one smoke marker stands before it fades by itself.
const SMOKE_MSEC := 45000

## The live marker, or {} for none. Only ever ONE.
var _smoke_marker: Dictionary = {}

func _team_of(id: String) -> int:
	return int(Game.roster.get(id, {}).get("team", -1))

func _team_wool(id: String) -> int:
	var team := _team_of(id)
	if team < 0:
		return Blocks.WOOL_WHITE
	return TEAM_WOOL[team % TEAM_WOOL.size()]

## Soft, plain terrain only — never glass, plants, liquids or anything
## anyone built out of a hard material.
## Paint RECOLOURS a block. It never adds one and never takes one away,
## so what you paint has to already be a plain solid cube: no air, no
## water, no plants, and nothing you can see through. Painting glass or
## leaves turned a window or a canopy into solid wool, which looks
## exactly like the sprayer inventing blocks and filling in holes.
## IS THIS BLOCK ALLOWED TO BE BROKEN, HERE?
##
## Two questions in one: the block's own `unbreakable` flag, and whether it
## belongs to a flag. The beacon pole is unbreakable in the palette, but
## the mound under it is ordinary dirt and wool — and a mound you can dig
## away is not indestructible in any sense that matters, because the first
## thing anybody works out is to mine the hill out from under the other
## team's beacon and leave it hanging. The whole COLUMN is off limits, so
## nobody can tunnel underneath it either.
##
## EVERYTHING THAT REMOVES A BLOCK ON THE SERVER COMES THROUGH HERE:
## digging, every explosive, the block sucker, the tunnelling digger, fire
## charring the ground, and the computer players' dig-out. Adding a new way
## to break the world and not calling this is how the flags start
## disappearing again.
##
## Placing is deliberately still allowed — building on your own mound is
## half the fun and none of the risk.
func can_carve(pos: Vector3i, block: int) -> bool:
	if not Blocks.is_breakable(block):
		return false
	for team_i: int in ctf._flags.keys():
		var home: Vector3 = ctf._flags[team_i].get("home", Vector3.INF)
		if home == Vector3.INF:
			continue
		var gx := absf(float(pos.x) - home.x)
		var gz := absf(float(pos.z) - home.z)
		var reach := float(CtfDirector.CTF_MOUND_RADIUS) + 0.5
		if gx > reach or gz > reach:
			continue                       # cheap box test first
		if Vector2(gx, gz).length() <= reach:
			return false
	return true

func _paintable(pos: Vector3i) -> bool:
	var block := store.get_block(pos)
	if block == Blocks.AIR or Blocks.is_liquid(block) or Blocks.is_cross(block):
		return false
	if not can_carve(pos, block):
		return false
	if not Blocks.is_solid(block) or not Blocks.is_opaque(block):
		return false
	# Anything you could dig. It used to insist on hardness 0, which is
	# soil and sand and not much else — so the sprayer did nothing on
	# stone, cobble, planks, brick or any of the things people actually
	# build with, which is most of what you would want to mark.
	return Blocks.hardness(block) < 3






## Water flow: when blocks vanish next to water (dig, blast), the hole
## fills and the fill keeps going — ponds pour into TNT craters properly.
##
## Water only creeps SIDEWAYS once it has landed on something. Anything
## with air underneath simply falls, like a waterfall; that is why a hole
## punched in the side of a pool now dribbles out and drops, instead of
## the old behaviour where it crawled outwards across flat ground.
const WATER_SPREAD := 10








# --- Server critters ---

## Map reset: any player proposes, EVERY connected machine must agree, then
## the world regenerates with a brand-new random seed.
var _reset_votes: Dictionary = {}
var _reset_deadline_ms := 0

@rpc("any_peer", "reliable")
func sv_reset_request(_slot: int) -> void:
	if not multiplayer.is_server() or not _reset_votes.is_empty():
		return
	var peer := multiplayer.get_remote_sender_id()
	_reset_votes = {peer: true}
	_reset_deadline_ms = Time.get_ticks_msec() + 30_000
	cl_reset_vote.rpc()
	_check_reset_votes()

@rpc("any_peer", "reliable")
func sv_reset_answer(agree: bool) -> void:
	if not multiplayer.is_server() or _reset_votes.is_empty():
		return
	if not agree:
		_reset_votes.clear()
		cl_reset_result.rpc(false)
		return
	_reset_votes[multiplayer.get_remote_sender_id()] = true
	_check_reset_votes()

func _check_reset_votes() -> void:
	if Time.get_ticks_msec() > _reset_deadline_ms:
		_reset_votes.clear()
		cl_reset_result.rpc(false)
		return
	for peer: int in multiplayer.get_peers():
		if not _reset_votes.has(peer):
			return
	_reset_votes.clear()
	_do_world_reset()

@rpc("any_peer", "call_local", "reliable")
func sv_new_map(map_name: String) -> void:
	if not multiplayer.is_server() or match_phase != "IDLE":
		return
	if not _known_map(map_name):
		return
	_do_world_reset(map_name)

## Guard: _do_world_reset() now kicks off a fresh battle when the mode is
## battle royale, and opening a lobby can itself decide the world needs
## resetting. Without this the two would call each other forever.
var _resetting := false

func _do_world_reset(map_name := "", new_size := 0) -> void:
	if _resetting:
		return
	_resetting = true
	var new_seed := randi() % 1000000000
	print("WORLD RESET: new seed %d map=%s size=%d" % [new_seed, map_name,
		new_size if new_size > 0 else store.world_size])
	store.reset_world(new_seed, map_name, new_size)
	spawn_pos = store.find_spawn()
	_build_overview()
	cl_overview.rpc(overview)
	# A new world is a new day, at a new time — and new ground for every
	# team, since the hill they had fortified no longer exists.
	clock = _random_clock()
	battle.team_site.clear()
	# ...and with the site goes the level its mound was built at. Keeping
	# that across a regenerate would raise the next mound at the old
	# world's height, which is anywhere from underground to in mid-air.
	ctf._ctf_base_y.clear()
	survival_active = false
	monsters_by_id.clear()
	terrain._fires.clear()
	terrain._holes.clear()
	terrain._bombs.clear()
	terrain._saplings.clear()
	critters_sim.critters.clear()
	# Loot belongs to the world that was just thrown away. Left behind,
	# crates from a 250-block map hang in the void of a 50-block one —
	# which is exactly the "loot way out there" that was reported.
	crates_by_id.clear()
	survival.broadcast_crates()
	_smoke_marker.clear()
	cl_smoke_clear.rpc()
	# A NEW WORLD IS A CLEAN SLATE. Everything below used to survive a
	# resize and then make no sense in the world that replaced it:
	# positions from a map twice the size, a battle still running over
	# terrain that no longer exists, a league table for a map nobody is
	# playing any more.
	#
	for state: Dictionary in player_state.values():
		state.pos = Vector3.ZERO
	player_state.clear()
	# Computer players keep their position in bots.roster, which is NOT
	# player_state and was not being cleared — so after a regenerate they
	# stood exactly where they had been standing in the world before,
	# which on a smaller map is off the edge of it. Same two names, same
	# two spots, every time. Give each of them somewhere new in the world
	# that now exists.
	for bot_id: String in bots.roster.keys():
		var fresh := store.safe_stand(Vector3(spawn_pos), 10.0)
		bots.roster[bot_id].pos = fresh
		bots.roster[bot_id].goal = fresh
		bots.roster[bot_id].think = randf_range(0.1, 0.5)
		bots.roster[bot_id].last_pos = fresh
		# ...and put their player_state back. Clearing that wholesale
		# above deletes the computer players' entries too, and without
		# one a bot is invisible to everything that walks player_state:
		# the radar, targeting, the crate pickup test.
		player_state[bot_id] = {"pos": fresh, "treasures": 0,
			"name": str(Game.roster.get(bot_id, {}).get("name", "?")), "hp": 5}
	# Any running battle is abandoned; the scoreboard starts again.
	if match_phase != "IDLE":
		match_phase = "IDLE"
		battle._timer = 0.0
		match_alive.clear()
		downed_ids.clear()
		storm_radius = 0.0
		cl_match.rpc("IDLE", 0.0)
		cl_storm.rpc(0.0, Vector3.ZERO)
	reset_scoreboard()
	cl_reset_result.rpc(true)
	cl_world_info.rpc(spawn_pos, clock, source, day_length)
	cl_world_reset.rpc()
	# ...and if we are meant to be playing a match mode, start a fresh
	# round on the new map rather than leaving everyone idle. Capture the
	# flag belongs here as much as battle royale does — it was left out,
	# so regenerating the world in CTF dropped everybody into an empty map
	# with no bases and no way to ask for them back.
	_resetting = false
	if game_mode != "creative":
		match_loop = true
		battle.open_lobby()

# ------------------------------------------------------------------
# Battle royale match
# ------------------------------------------------------------------
const LOBBY_SECONDS := 6.0
const STORM_START := 360.0

## Battle square side in blocks (the storm starts at its edge).
var battle_size := 250.0
## Game-loop mode: matches chain with a countdown + fresh map between.
var match_loop := true


## ENOUGH COMPUTER PLAYERS TO HAVE A GAME, added once, when the first
## person arrives.
##
## A fresh server has nobody on it, so whoever came first got four empty
## teams and a field — and capture the flag with one player is not a game,
## it is a walk to an undefended flag. Three makes it one-a-side across the
## four default teams the moment they arrive.
##
## Only ever on an EMPTY bot list, so it is an opening move and not a rule:
## remove them from the Players tab and they stay removed, and a server
## that has been running all night is not topped up behind your back.
const OPENING_BOTS := 3


@rpc("any_peer", "call_local", "reliable")
func sv_add_bot() -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if Game.roster.size() >= Game.MAX_PLAYERS:
		return
	bots.spawn()
	_save_battle_setup()

## FILL THE ROOM. Adding computer players one at a time is a button press
## each, and the ceiling is a hundred — so getting a full game meant
## clicking the same button ninety-odd times.
##
## Server side, in one call, because it is also ninety-odd round trips
## otherwise and the roster is broadcast after every one of them.
@rpc("any_peer", "reliable")
func sv_fill_bots() -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	var added := 0
	while Game.roster.size() < Game.MAX_PLAYERS:
		bots.spawn()
		added += 1
		# A guard, not a limit: spawn() refusing for any reason would
		# otherwise turn this into a loop that never ends.
		if added > Game.MAX_PLAYERS:
			break
	print("ROSTER: filled with %d computer players (%d of %d)"
		% [added, Game.roster.size(), Game.MAX_PLAYERS])
	bots.redistribute()
	_save_battle_setup()

## Roster-full eviction path (a human needs the seat).
## Someone was kicked: clear every trace so their body and state don't
## linger in a running battle.
func forget_player(id: String) -> void:
	player_state.erase(id)
	match_alive.erase(id)
	downed_ids.erase(id)
	hearts.erase(id)
	cl_eliminated.rpc(id)

func drop_bot(id: String) -> void:
	bots.roster.erase(id)
	player_state.erase(id)
	match_alive.erase(id)
	_save_battle_setup()

@rpc("any_peer", "call_local", "reliable")
func sv_remove_bot(target_id: String = "") -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if bots.roster.is_empty():
		return
	var id := target_id if bots.roster.has(target_id) else str(bots.roster.keys().back())
	bots.roster.erase(id)
	player_state.erase(id)
	match_alive.erase(id)
	Game.roster.erase(id)
	Game.cl_roster.rpc(Game.roster)
	_save_battle_setup()

## The host flips between Battle and Creative. Creative immediately and
## gracefully ends any running battle: nobody dies, weapons are kept,
## the world stays, everyone just goes back to playing.
@rpc("any_peer", "call_local", "reliable")
func sv_set_mode(mode: String) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if mode != "battle" and mode != "creative" and mode != "ctf" \
			and mode != "holdout":
		return
	var changed := game_mode != mode
	game_mode = mode
	match_loop = mode != "creative"
	if mode == "creative" and match_phase != "IDLE":
		match_phase = "IDLE"
		match_alive.clear()
		downed_ids.clear()
		cl_match.rpc("IDLE", 0.0)
	elif mode != "creative" and (match_phase == "IDLE" or changed):
		# PICKING A MODE STARTS THAT MODE, NOW. This used to fire only from
		# IDLE, so choosing capture the flag in the middle of a battle
		# royale round set the variable and left you in the battle — the
		# CTF bases were never built and no flag ever appeared. It looked
		# like the button did nothing, and the only way through was to keep
		# poking at the menu until the old round happened to end and the
		# loop opened a lobby in the new mode. Switching modes is an
		# explicit "we are playing THIS now", so it restarts the round.
		battle.open_lobby()
	cl_mode.rpc(game_mode)
	_save_battle_setup()

@rpc("authority", "call_local", "reliable")
func cl_mode(mode: String) -> void:
	client_mode = mode
	if not multiplayer.is_server():
		battle_config_changed.emit()

## New humans get a balanced team the moment they register.
func auto_team(id: String) -> void:
	if not multiplayer.is_server() or not Game.roster.has(id):
		return
	if int(Game.roster[id].get("team", -1)) >= 0:
		return
	var counts: Array[int] = []
	counts.resize(team_count)
	for other: String in Game.roster.keys():
		var ot := int(Game.roster[other].get("team", -1))
		if ot >= 0 and ot < team_count:
			counts[ot] += 1
	var best := 0
	for t in team_count:
		if counts[t] < counts[best]:
			best = t
	Game.roster[id].team = best
	# The computers even out around whoever just arrived.
	bots.redistribute()

## Teams are managed from the Players view: add/remove columns, rename.
## Computer players redistribute into contiguous, even groups (1,2,3 on
## the first team, 4,5,6 on the next...) whenever the layout changes;
## humans always keep the team they picked.
@rpc("any_peer", "call_local", "reliable")
func sv_add_team() -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if team_count >= 24:
		return
	team_count += 1
	team_names.append(TEAM_NAMES[(team_count - 1) % TEAM_NAMES.size()])
	bots.unpin()
	bots.redistribute()
	cl_teams.rpc(team_names)
	_save_battle_setup()

@rpc("any_peer", "call_local", "reliable")
func sv_remove_team(index: int = -1) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if team_count <= 2:
		return
	var gone := index if index >= 0 and index < team_count else team_count - 1
	team_names.remove_at(gone)
	team_count -= 1
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team == gone:
			Game.roster[id].team = -1
		elif team > gone:
			Game.roster[id].team = team - 1
	bots.unpin()
	bots.redistribute()
	cl_teams.rpc(team_names)
	_save_battle_setup()

@rpc("any_peer", "call_local", "reliable")
func sv_rename_team(index: int, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	if index >= 0 and index < team_names.size() and not new_name.strip_edges().is_empty():
		team_names[index] = new_name.strip_edges().left(10)
		cl_teams.rpc(team_names)
		_save_battle_setup()

@rpc("authority", "call_local", "reliable")
func cl_teams(names: Array) -> void:
	client_team_names = names
	if multiplayer.is_server():
		return
	# The COUNT lives here too. It used to be server-only, so removing a
	# team emptied it everywhere but left the column on screen forever.
	team_count = maxi(names.size(), 1)
	battle_config_changed.emit()

## START THE ROUND WHEN SOMEBODY ARRIVES, not at boot.
##
## A room asked for as battle royale has to actually be playing battle
## royale — but opening the round in _server_setup means it opens while
## the room is still empty, and the lobby only hands the code back to its
## creator once the process is listening. They would arrive a few seconds
## into a round that started without them, which is the one moment in a
## battle royale that matters.
##
## So the first `sv_hello` opens it. Idempotent, because every client
## sends one: only an IDLE phase is opened, and only in a mode that has
## rounds.
func _open_round_if_waiting() -> void:
	if game_mode == "creative" or match_phase != "IDLE" or battle == null:
		return
	battle.open_lobby()

## NOTHING IS KEPT ON DISK. Not where players stood, not the team layout,
## not the game mode — the world itself is thrown away on every restart
## and every resize, so anything remembered from the last one only ever
## made nonsense of the new one, and every bug where somebody turned up
## in the void traced back to state that outlived its world. A restart is
## a clean table: default teams, no computer players, creative mode.
func _save_battle_setup() -> void:
	pass

func _load_battle_setup() -> void:
	pass

func _is_host(_sender: int) -> bool:
	# Family rule: ANYBODY at the table can run battles, change maps and
	# manage teams — young kids can't wait for player 1.
	return true

@rpc("any_peer", "call_local", "reliable")
func sv_set_loop(on: bool) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	match_loop = on

const STORM_END := 20.0
var storm_minutes := 5.0
var loot_only := false
## Flying allowed at all, in EVERY mode — it describes how play works in
## this world, not how a battle works. Stored under its own key ("world_fly")
## because the old battle-only setting defaulted to false, and reusing it
## would have silently turned flying off in creative.
## THE DEFAULT ANSWER for anyone nobody has decided about — and it is two
## answers rather than one, because two of the four things a grown-up
## actually wants to say cannot be said with a single switch. "Computers
## only" is how the bots get to come at a base over its wall while
## everybody at the table plays on the ground; "humans only" is how the
## small ones get a way out of trouble without handing it to twenty bots.
## OFF BY DEFAULT, both of them. It has to be switched on deliberately:
## a game where everybody can fly from the start is a game where nobody
## walks anywhere, climbs anything or has to get past a wall.
var battle_fly := false
var battle_fly_bots := false

## ONE KNOCKOUT AND YOU ARE OUT, in every mode. Off by default.
##
## Being picked up is what keeps a young player in a round they would
## otherwise spend watching, so this is not the default — but "when you're
## done, you're done" is a different and harder game, and some tables want
## it. It overrides everything: no team-mate pick-ups, and no tagging back
## in at your own flag either, because "you cannot be revived" has to mean
## all of it or it means nothing.
## HOW YOU GET BACK UP — one rung of ReviveRule's ladder. This was two
## settings, `ctf_revive` and `no_revive`, in two different cards with an
## unrelated one between them, and they could be set to contradict.
var revive_mode := ReviveRule.MATES_AND_FLAG

## HOW LONG A ROUND OF LAST FLAG STANDING RUNS, in minutes. Battle royale
## has had its own length setting all along; this mode had a constant.
var holdout_minutes := HoldoutRules.ROUND_MINUTES

## WHERE PEOPLE HAVE ACTUALLY BEEN KNOCKED OUT, most recent last.
##
## Read by the computer players when they choose which way to come at a
## base — see BotSquads.lane_cost. It is the only honest answer to "where
## is it dangerous": not where the enemy is standing this instant, but
## where the last dozen fights ended.
##
## Server-side and deliberately short. It is a rolling picture of THIS
## part of the round; a full history would keep steering everyone away
## from ground that has been quiet for ten minutes.
var battle_scars: Array = []
const BATTLE_SCARS_KEPT := 16

func remember_scar(at: Vector3) -> void:
	battle_scars.append(at)
	if battle_scars.size() > BATTLE_SCARS_KEPT:
		battle_scars = battle_scars.slice(battle_scars.size() - BATTLE_SCARS_KEPT)

## MAY THIS PLAYER FLY?
##
## The world's setting is the DEFAULT, and any player may be given a
## different answer — `Game.roster[id].fly`, absent unless somebody has
## said otherwise. Absent rather than filled in at join time on purpose:
## a player who has never been singled out follows the world, so flipping
## the world setting still moves everyone who has not been decided about.
##
## Flying used to be one switch for the whole table, which is the wrong
## shape for what it is actually used for — letting the small ones float
## out of trouble while everybody else plays on the ground, or handing it
## to one team and not the other.
func fly_allowed_for(id: String) -> bool:
	var entry: Dictionary = Game.roster.get(id, {})
	if entry.has("fly"):
		return bool(entry["fly"])   # somebody was decided about by hand
	var is_bot := bool(entry.get("bot", false))
	if multiplayer.is_server():
		return battle_fly_bots if is_bot else battle_fly
	return client_fly_bots if is_bot else client_fly

## Which of the four answers is in force, for lighting the right button.
## Anybody decided about by hand is ignored here — they are shown against
## their own name — so this describes the DEFAULT and nothing else.
func fly_answer() -> String:
	var people: bool = battle_fly if multiplayer.is_server() else client_fly
	var computers: bool = battle_fly_bots if multiplayer.is_server() else client_fly_bots
	return FlyRule.answer_for(people, computers)

## THERE ARE THREE STATES A PLAYER CAN BE IN, and no more: ALIVE, KNOCKED
## OUT, or OUT. Between them they are exhaustive and exclusive.
##
##   alive        in `match_alive`, in neither of the other two
##   knocked out  in `match_alive` AND `downed_ids` — still in the round,
##                waiting for a team-mate, or for their own flag in
##                capture the flag
##   out          in `out_ids` and nothing else — the whole team went
##                down at once, and in battle royale that is permanent
##
## `out_ids` was called `ghost_ids`, which read as a fourth thing rather
## than as a name for the third. The word is still around for the LOOK a
## knocked-out player has, which is a separate idea and now has its own
## name (Player.set_knocked_out_look).
##
## The client keeps its own mirrors — `alive_ids`, `client_downed`,
## `out_ids` — because it draws them.
##
## Who is still in the fight. id -> true.
var match_alive: Dictionary = {}

## Anyone may re-team a computer player from the lobby.
@rpc("any_peer", "reliable")
func sv_set_bot_team(target_id: String, team: int) -> void:
	if not multiplayer.is_server():
		return
	if Game.roster.has(target_id):
		# Anyone can set ANY player's team — grown-ups sort the kids out.
		Game.roster[target_id].team = clampi(team, -1, team_count - 1)
		# Pinned: the auto-balancer leaves a computer alone once someone
		# has put it somewhere on purpose. Adding or removing a team
		# clears every pin, because the layout it was chosen for is gone.
		if bots.roster.has(target_id):
			Game.roster[target_id].fixed = true
		Game.cl_roster.rpc(Game.roster)

@rpc("any_peer", "reliable")
func sv_ctf_config(revive: int, target: int, drop: int, hold_mins := -1) -> void:
	## Settings that belong to a MODE rather than to the arena. `drop` is
	## deliberately cross-mode — losing your weapons on a knockout is a
	## fair question in battle royale too — while revive and the target
	## score only mean anything in capture the flag.
	if not multiplayer.is_server() \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if revive >= 0:
		revive_mode = clampi(revive, ReviveRule.NONE, ReviveRule.MATES_AND_FLAG)
	if target > 0:
		ctf_target = clampi(target, 1, 25)
	if drop >= 0:
		drop_on_knockout = drop == 1
	if hold_mins > 0:
		holdout_minutes = clampf(float(hold_mins), 1.0, 99.0)
		# The clock is read once and remembered, so a length changed
		# mid-round has to say so or the round runs on the old one.
		battle.forget_holdout_length()
	cl_battle_config.rpc(int(storm_minutes), int(battle_size), loot_only,
		battle_fly, team_count, drop_on_knockout, revive_mode, ctf_target,
		battle_fly_bots, int(holdout_minutes))

## Hand flight out, or take it away, from a group at a time.
##
##   scope "all"     everybody in the room
##   scope "bots"    every computer player
##   scope "humans"  every person
##   scope "team"    everyone on `team`
##   scope "one"     the single player whose id is in `who`
##
## Groups rather than a switch each, because that is how it gets used:
## turn it on for all the computer players, then take it off the ones on
## Red. Doing that a player at a time in a room of fifty is not something
## anybody would sit through.
@rpc("any_peer", "reliable")
func sv_set_fly(scope: String, team: int, on: bool, who := "") -> void:
	if not multiplayer.is_server() \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	# THE FOUR GROUP ANSWERS ARE A RESET, not a nudge. They set the
	# default and wipe every individual answer with it — otherwise
	# "Nobody" leaves whoever was singled out earlier still in the air,
	# and the button looks broken to the one person using both halves.
	#
	# Setting the DEFAULT rather than stamping every player is what makes
	# it stick: a computer player added ten seconds later follows the
	# answer too, which is not true of anything that only walks the roster
	# it can see right now.
	if scope in FlyRule.ANSWERS:
		battle_fly = FlyRule.people_fly(scope)
		battle_fly_bots = FlyRule.computers_fly(scope)
		for id: String in Game.roster.keys():
			(Game.roster[id] as Dictionary).erase("fly")
		Game.cl_roster.rpc(Game.roster)
		cl_battle_config.rpc(int(storm_minutes), int(battle_size), loot_only,
			battle_fly, team_count, drop_on_knockout, revive_mode, ctf_target,
			battle_fly_bots, int(holdout_minutes))
		_save_battle_setup()
		return
	# ...and one person at a time, from the ✈ against their name.
	for id: String in Game.roster.keys():
		if scope == "one" and id == who:
			(Game.roster[id] as Dictionary)["fly"] = on
	Game.cl_roster.rpc(Game.roster)
	_save_battle_setup()

# ------------------------------------------------------------------
# Boats and cars
#
# The driver's own machine moves the thing and reports where it got to,
# exactly as every player already does with their own body. The server
# owns the list, the ids and the one-driver rule. See VehicleDirector.
# ------------------------------------------------------------------

## PUT A BOAT OR A CAR WHERE SOMEBODY IS AIMING.
##
## THIS DID NOT EXIST. The tools tray called `sv_vehicle_place` and there
## was no such method anywhere — the old `sv_vehicle_here` was deleted as
## dead code and its replacement never written — so choosing a boat or a
## car and clicking did precisely nothing, in every mode. "They're
## impossible to place, so they're kinda useless at the moment" was a
## plain description of the state of it.
##
## Same rules as placing a block, because that is what it is: within
## reach, and inside the world. The server then settles it down onto the
## water or the ground, so a boat aimed at the sea floats rather than
## sinking and a car aimed at a hillside sits on it.
@rpc("any_peer", "reliable")
func sv_vehicle_place(slot: int, at_cell: Vector3i, kind: int) -> void:
	if not multiplayer.is_server() or vehicles == null:
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if not Game.roster.has(id):
		return
	var spot := Vector3(at_cell) + Vector3(0.5, 0.0, 0.5)
	var from: Vector3 = player_state.get(id, {}).get("pos", spot)
	if from.distance_to(spot) > EDIT_RANGE + 2.0:
		return
	if not store.inside_world(at_cell.x, at_cell.z, 2):
		return
	# spawn() tells every client about the one new vehicle itself. Do NOT
	# also broadcast the whole list here: the two cross, `set_all` rebuilds
	# every entry from a payload built before the spawn, and the new one
	# disappears again a frame after it arrives. Measured — the fleet grew
	# on the server and stayed put on the client.
	vehicles.spawn(clampi(kind, VehicleGeom.KIND_BOAT, VehicleGeom.KIND_CAR),
		vehicles.settle(kind, spot))

@rpc("any_peer", "reliable")
func sv_vehicle_board(vid: String, slot: int) -> void:
	if not multiplayer.is_server() or vehicles == null:
		return
	vehicles.board(vid, Game.player_id(multiplayer.get_remote_sender_id(), slot))

@rpc("any_peer", "reliable")
func sv_vehicle_leave(vid: String, slot: int) -> void:
	if not multiplayer.is_server() or vehicles == null:
		return
	vehicles.leave(vid, Game.player_id(multiplayer.get_remote_sender_id(), slot))

## Unreliable, and for the same reason player positions are: this arrives
## fifteen times a second and the next one is always more use than a
## resend of the last.
@rpc("any_peer", "unreliable")
func sv_vehicle_moved(vid: String, slot: int, at_pos: Vector3, yaw: float) -> void:
	if not multiplayer.is_server() or vehicles == null:
		return
	vehicles.moved(vid, Game.player_id(multiplayer.get_remote_sender_id(), slot),
		at_pos, yaw)

@rpc("authority", "reliable")
func cl_vehicle_new(vid: String, kind: int, at_pos: Vector3, yaw: float,
		driver: String) -> void:
	if vehicle_view == null:
		return
	vehicle_view.add_one(vid, kind, at_pos, yaw, driver)
	vehicle_view.set_driver(vid, driver)

@rpc("authority", "reliable")
func cl_vehicle_gone(vid: String) -> void:
	if vehicle_view != null:
		vehicle_view.remove_one(vid)

@rpc("authority", "reliable")
func cl_vehicle_helm(vid: String, driver: String) -> void:
	if vehicle_view != null:
		vehicle_view.set_driver(vid, driver)

@rpc("authority", "unreliable")
func cl_vehicle_at(vid: String, at_pos: Vector3, yaw: float) -> void:
	if vehicle_view != null:
		vehicle_view.heard_at(vid, at_pos, yaw)

@rpc("authority", "reliable")
func cl_vehicles(payload: Array) -> void:
	if vehicle_view != null:
		vehicle_view.set_all(payload)

@rpc("any_peer", "reliable")
func sv_match_config(minutes: int, loot: int, size: int = -1) -> void:
	# No phase guard: the grown-up gets to re-size the arena, allow flying
	# or change the round length WHILE a battle is running.
	if not multiplayer.is_server() \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if minutes > 0:
		storm_minutes = clampf(float(minutes), 2.0, 99.0)
	if loot >= 0:
		loot_only = loot == 1
	# The world's SIZE is baked into the terrain — it's a square slab cut
	# to this width — so changing it has to rebuild the world. Anything
	# else just moves an invisible line while the old map stays put.
	var resize_to := 0
	if size > 0 and not is_equal_approx(float(size), battle_size):
		battle_size = clampf(float(size), 25.0, 800.0)
		resize_to = int(battle_size)
	cl_battle_config.rpc(int(storm_minutes), int(battle_size), loot_only,
		battle_fly, team_count, drop_on_knockout, revive_mode, ctf_target,
		battle_fly_bots, int(holdout_minutes))
	_save_battle_setup()
	if resize_to > 0:
		_do_world_reset(selected_map, resize_to)

@rpc("any_peer", "reliable")
func sv_match_start(_slot: int) -> void:
	if not multiplayer.is_server() or match_phase != "IDLE" or Game.roster.is_empty() \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	battle.open_lobby()



## World SELECTION (host): remembered, shown highlighted everywhere, and
## applied when the next battle starts — never an instant switch.
@rpc("any_peer", "call_local", "reliable")
func sv_select_world(map_name: String) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if not _known_map(map_name):
		return
	selected_map = map_name
	cl_world_sel.rpc(selected_map)
	_save_battle_setup()
	# PICKING A WORLD TAKES YOU THERE. Immediately, and whatever is
	# running — which is the same rule the world's SIZE has followed all
	# along, a few lines up in sv_match_config: "the grown-up gets to
	# re-size the arena while a battle is running".
	#
	# This used to wait for `match_phase == "IDLE"` and apply on the next
	# round instead. With the match loop on — which is the normal way this
	# game is played — the phase is essentially never IDLE, so picking
	# Space or Skylands did nothing at all, and went on doing nothing
	# until you happened to change the size, which reset the world through
	# the other path and brought the new theme with it. Reported exactly
	# that way: "it doesn't change the actual world until I change the
	# size of the world".
	#
	# _do_world_reset already knows how to interrupt a round — it stands
	# everybody down, clears the board and opens a fresh lobby on the new
	# map — so there was never anything for the guard to protect.
	if map_name != store.current_map_key \
			or (map_name == store.theme and store.current_map_key.is_empty()):
		_do_world_reset(map_name)

@rpc("authority", "call_local", "reliable")
func cl_world_sel(map_name: String) -> void:
	client_world = map_name
	if not multiplayer.is_server():
		map_list_changed.emit()

func _known_map(map_name: String) -> bool:
	if map_name in WorldGen.THEMES:
		return true
	for entry in ChunkStore.list_maps():
		if str(entry.key) == map_name:
			return true
	return false






## Who is down and waiting to be picked up. id -> the msec they went down.
var downed_ids: Dictionary = {}





@rpc("authority", "reliable")
func cl_hit_ok() -> void:
	Sfx.play("bonk", -2.0, 1.35)





## How long a team-mate must stand next to you to pick you up, how close
## they have to be, and how many hearts you come back with.
##
## REVIVE_RADIUS is public because the HUD prompt has to agree with it. It
## did not used to: the prompt appeared at 6 blocks and the revive happened
## at 3, so there was a ring you could stand in where the screen told you
## to hold still and the game was doing nothing.
## HOW FAR A SWORD REACHES, and it is short on purpose: the reward for
## landing one is total, so getting there has to be the hard part.
const SWORD_REACH := 3.0

const REVIVE_SECONDS := 3.0
const REVIVE_RADIUS := 3.0
const REVIVE_HP := 1





# ------------------------------------------------------------------
# The scoreboard
#
# Two tallies that live across matches: how many games each TEAM has won,
# and how many knockouts each PLAYER has. Both belong to the map they
# were set on, so both are wiped when the world is reset — see
# _do_world_reset(). Players coming and going does NOT reset them.
# ------------------------------------------------------------------

## team index -> games won
var team_wins: Dictionary = {}
## player name -> {"total": int, "last": int, "team": int}
##
## Keyed by NAME, not by peer id: a kid who drops out and rejoins gets a
## new id and would otherwise lose their record mid-session.
var player_frags: Dictionary = {}
var matches_played := 0

func reset_scoreboard() -> void:
	team_wins.clear()
	player_frags.clear()
	matches_played = 0
	battle.broadcast_scoreboard()






@rpc("authority", "call_local", "reliable")
func cl_scoreboard(wins: Dictionary, frags: Dictionary, played: int) -> void:
	team_wins = wins
	player_frags = frags
	matches_played = played
	scoreboard_changed.emit()

signal scoreboard_changed


## Can a shot get from `from` to `to` without a block in the way? Walked
## in short steps rather than a proper DDA — plenty for deciding whether
## a computer player can see you, and cheap enough to run per shot.
func clear_shot(from: Vector3, to: Vector3) -> bool:
	if store == null:
		return true
	var span := to - from
	var dist := span.length()
	if dist < 0.001:
		return true
	var steps := int(dist * 2.0)
	var step := span / float(maxi(steps, 1))
	var at := from
	for i in range(1, steps):
		at += step
		var cell := Vector3i(floori(at.x), floori(at.y), floori(at.z))
		var block := store.get_block(cell)
		if block != Blocks.AIR and not Blocks.is_liquid(block) \
				and not Blocks.is_cross(block):
			return false
	return true

func teams_differ(a: String, b: String) -> bool:
	if not (Game.roster.has(a) and Game.roster.has(b)):
		return true
	return int(Game.roster[a].get("team", -1)) != int(Game.roster[b].get("team", -2))

signal match_score_changed
## Flag positions as the clients know them: [[team, home:Vector3, present:bool], ...]
signal flags_changed
signal flag_taken(id: String, team: int, from_team: int)
signal knockout(attacker: String, attacker_team: int, victim: String, victim_team: int)
var out_ids: Dictionary = {}
## Client mirror of the flags, for the HUD map. See cl_flags.
var flags: Array = []
var client_downed: Dictionary = {}
## id -> 0..1 while a team-mate is picking that player up, so everyone can
## see the ring fill rather than guessing whether it's working.
var revive_progress: Dictionary = {}
signal revive_changed
var alive_ids: Dictionary = {}

## THE WHOLE ROUND, HANDED TO SOMEBODY WHO HAS JUST ARRIVED.
##
## `cl_match` only fires on a phase CHANGE, and the alive / downed / out
## sets are only rebuilt on the SETUP transition — so a client joining a
## round already in progress had no picture of it at all. Every team read
## "0 of 6" while the computer players shooting at them were, as far as
## that screen knew, not in the game. Walking into an overnight match
## and found exactly that.
##
## This is the join-time counterpart to `cl_match`: same idea, but it
## carries the sets rather than assuming the client watched them being
## built.
@rpc("authority", "reliable")
func cl_match_state(phase: String, seconds: float, alive: Array,
		downed: Array, out_of_it: Array) -> void:
	match_phase = phase
	match_seconds = seconds
	alive_ids.clear()
	for id: String in alive:
		alive_ids[id] = true
	client_downed.clear()
	for id: String in downed:
		client_downed[id] = true
	out_ids.clear()
	for id: String in out_of_it:
		out_ids[id] = true
	for child in players.get_children():
		if child is Player:
			var is_down: bool = client_downed.has(child.player_id)
			var is_out: bool = out_ids.has(child.player_id)
			child.downed = is_down
			child.set_knocked_out_look(is_down)
			# The fallen are invisible to everyone still playing; the
			# downed only to the other team.
			child.visible = not is_out and ((not is_down) \
				or _my_team_has(child.player_id))
	match_changed.emit()
	match_score_changed.emit()
	_refresh_overheads()

@rpc("authority", "reliable")
func cl_match(phase: String, seconds: float) -> void:
	match_phase = phase
	match_seconds = seconds
	if phase == "SETUP":
		out_ids.clear()
		client_downed.clear()
		revive_progress.clear()
		alive_ids.clear()
		for rid: String in Game.roster.keys():
			alive_ids[rid] = true
		for child in players.get_children():
			if child is Player:
				child.visible = true
				# A fresh match means everyone is UP. Without this, anyone
				# downed when the last battle ended dropped out of the sky
				# still playing their death animation.
				child.downed = false
				child.set_knocked_out_look(false)
		match_score_changed.emit()
		_refresh_overheads()
	elif phase == "IDLE" or phase == "LOBBY":
		out_ids.clear()
		client_downed.clear()
		revive_progress.clear()
		for child in players.get_children():
			if child is Player:
				child.visible = true
				child.downed = false
				child.set_knocked_out_look(false)
	if chunks != null:
		chunks.match_mode = phase != "IDLE"
	match_changed.emit()
	if phase == "SETUP":
		Sfx.play("whoosh")
	elif phase == "BATTLE":
		Sfx.play("boom", -8.0)

@rpc("authority", "reliable")
func cl_storm(radius: float, center: Vector3 = Vector3.ZERO) -> void:
	storm_radius = radius
	storm_center = center
	storm_changed.emit()

@rpc("authority", "reliable")
func cl_stand(id: String, pos: Vector3, loot := false, kit: Array = [],
		reset_kit := true) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# Stood on the ground beside your team, not dropped out of the
			# sky. See _team_start_spot(): this is a building game, and a
			# squad that starts together can put up a fort.
			child.teleport(pos)
			child.fly_mode = false
			child.velocity = Vector3.ZERO
			# The kit is only handed out at the DROP. Everything else that
			# moves a player — capturing a flag, coming back to life —
			# reuses this and must not touch what they are carrying: it
			# reset the bar unconditionally, so a capture cost you every
			# weapon you had found on the way there.
			if reset_kit:
				child.slots = []
				for weapon_id: int in kit:
					child.slots.append({"kind": "weapon", "id": weapon_id})
				while child.slots.size() < 8:
					child.slots.append({"kind": "empty", "id": 0})
				child.selected_slot = 0
			child.downed = false


@rpc("authority", "reliable")
## BACK IN THE ROUND, all the way back.
##
## This used to update the bookkeeping and nothing else, which was fine
## while the only caller was a path that immediately followed up with
## `cl_stand`. It is not fine now that you can tag in at your own flag
## while DOWNED: the server stood the player up and the client left them
## translucent, invisible to the other team, crawling, and unable to shoot
## — revived in the score and still knocked out on screen.
##
## Undo every part of being down, not just the part this file happens to
## own.
func cl_revived(id: String) -> void:
	out_ids.erase(id)
	alive_ids[id] = true
	client_downed.erase(id)
	hearts[id] = MATCH_HP
	hearts_changed.emit()
	match_score_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id:
			child.downed = false
			child.set_knocked_out_look(false)
			child.visible = true
			if child.is_local:
				# Flying was the way home; it is not a way to keep playing.
				child.fly_mode = false
	_refresh_overheads()

@rpc("authority", "reliable")
func cl_downed_state(id: String, is_down: bool) -> void:
	if is_down:
		client_downed[id] = true
	else:
		client_downed.erase(id)
	# Going down changes the team counts, so say so. Only elimination
	# used to, which is why downing half a team moved nothing on screen.
	match_score_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id:
			# GOING DOWN IS THE DEATH SEQUENCE, and it happens here.
			#
			# It used to be: you fell over, stayed where you were, and the
			# ten-block rise came much later, when your whole team went
			# down with you. So the moment that should read as "that
			# player is out of this" read as nothing at all, and a scrap
			# with eight people in it was impossible to follow, because
			# the ones lying in it looked much like the ones still in it.
			#
			# Now the knockout lifts you clear of the fight straight away.
			# You are grey, you are half transparent, you are ten blocks up
			# and out of everybody's way — and then you fly back down to
			# whoever might pick you up. `downed` still gates acting: you
			# cannot shoot, build or take a flag on the way.
			child.downed = is_down
			child.set_knocked_out_look(is_down)
			# ONLY YOUR OWN TEAM SEES A GHOST, and that is the point of
			# there being one. A ghost means "go and pick that up" — it is
			# the whole reason the HELP label could be removed. An enemy
			# ghost means nothing you can act on, and worse, it makes
			# every grey shape a question: mine, or not? So the other
			# side's are simply not drawn.
			# ...AND SOMEBODY WHO IS OUT STAYS PUT AWAY, whatever this
			# message says about being down. This line knew about one of
			# the two states a body can be hidden by, so a player who was
			# OUT and then heard "not down any more" was drawn again —
			# still untouchable, still unable to shoot, still moving.
			# That is an opponent you can see, cannot kill, and who never
			# fires back, which is exactly how it was described from a
			# real game: "they went into some weird mode".
			#
			# `cl_eliminated` hides them and this could un-hide them, so
			# the two have to agree about the whole rule rather than each
			# knowing half of it.
			child.visible = not out_ids.has(id) \
				and ((not is_down) or _my_team_has(id))
			if is_down:
				# THE KNOCKOUT IS SEEN HERE, not only at elimination.
				#
				# It used to fire from `cl_eliminated` alone — which in a
				# battle is not the moment anybody is knocked out. Shooting
				# somebody DOWNS them; elimination is what happens later,
				# when the last of their team goes down too. So the
				# burst played for the last player of a round and almost
				# nobody else: a whole match of knockouts with two puffs
				# of smoke in it, which is exactly what was reported.
				#
				# It fires for everyone, including whoever caused it —
				# that is the entire point. You shot someone; you should
				# be able to see that you did.
				if fx != null:
					fx.knockout(child.position + Vector3(0, 0.9, 0))
				Sfx.play("pop", -4.0)
				# ...and the floor goes with it. Somebody going out is the
				# biggest thing that happens in a round and it sounded
				# like a bubble popping. The same explosion everything
				# else uses, a little louder — the separate deep rumble
				# that used to be here is gone with the rest of them.
				Sfx.play("boom", -5.0)
			if child.is_local and is_down:
				# UP AND OUT OF IT. Ten blocks over three seconds — the
				# same rise elimination used to give, moved to the moment
				# it means something.
				#
				# Flying at the top of it: double-tap Ⓐ to stop and drop,
				# or the left trigger, which is what flight already does.
				child.velocity = Vector3.ZERO
				child.fly_mode = true
				child.begin_knockout_rise()
				Sfx.play("drop", -4.0)
	_refresh_overheads()

## Is `id` on the same team as one of MY players? Downed teammates are
## visible so they can be found and revived; downed enemies are not.
func _my_team_has(id: String) -> bool:
	var their_team := int(Game.roster.get(id, {}).get("team", -1))
	if their_team < 0:
		return false
	for mine: String in Game.local_player_ids():
		if int(Game.roster.get(mine, {}).get("team", -2)) == their_team:
			return true
	return false

@rpc("authority", "unreliable_ordered")
func cl_revive_progress(id: String, frac: float) -> void:
	if frac <= 0.0:
		revive_progress.erase(id)
	else:
		revive_progress[id] = frac
	revive_changed.emit()

@rpc("authority", "unreliable")
func cl_revive_noise(pos: Vector3) -> void:
	var dist := 1e9
	for child in players.get_children():
		if child is Player and child.is_local:
			dist = minf(dist, child.position.distance_to(pos))
	if dist < 40.0:
		Sfx.play("warp", -2.0 - dist * 0.4, 0.6)

@rpc("authority", "reliable")
func cl_feed(attacker_name: String, attacker_team: int,
		victim_name: String, victim_team: int) -> void:
	knockout.emit(attacker_name, attacker_team, victim_name, victim_team)

@rpc("authority", "reliable")
func cl_eliminated(id: String) -> void:
	var was_down := client_downed.has(id)
	client_downed.erase(id)
	hearts[id] = 0
	hearts_changed.emit()
	out_ids[id] = true
	alive_ids.erase(id)
	match_score_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id:
			# Only when this is the FIRST anyone heard of it. A player who
			# was already down has had their burst — being counted out is not a
			# second knockout, and playing it again drew an explosion over
			# a body that had been lying there for half a minute.
			if not was_down:
				if fx != null:
					fx.knockout(child.position + Vector3(0, 0.9, 0))
				Sfx.play("pop", -2.0)
			if child.is_local:
				# Already down and already ten blocks up? Then the rise
				# has been had. Doing it twice sends somebody already up there
				# another ten blocks into the sky for no reason.
				if not was_down:
					child.begin_knockout_rise()
				# Out, but not gone: stay where you fell and wander. You
				# can fly, you cannot touch anything, and nobody can see
				# you — so you can go and watch a team-mate, or talk them
				# onto the spot where you went down. Being flung seventy
				# blocks into the sky meant "out" also meant "bored".
				child.fly_mode = true
				child.velocity = Vector3.ZERO
				Sfx.play("drop", -6.0)
			else:
				# The fallen are invisible to everyone still playing, and
				# must drop the downed pose with it — otherwise they were
				# still running the death animation while hidden, and came
				# back mid-fall if anything made them visible again.
				child.visible = false
			child.downed = false
			child.set_knocked_out_look(false)

signal match_won(winner: int)

@rpc("authority", "reliable")
func cl_match_end(winner: int) -> void:
	match_phase = "END"
	match_changed.emit()
	match_won.emit(winner)
	Sfx.play("cheer")

@rpc("any_peer", "reliable")
func sv_survival_start(_slot: int) -> void:
	if not multiplayer.is_server() or survival_active or Game.roster.is_empty():
		return
	survival_active = true
	survival_wave = 1
	monsters_by_id.clear()
	_downed.clear()
	survival._bonked_count = 0
	survival._started_ms = Time.get_ticks_msec()
	survival._wave_started_ms = survival._started_ms
	for id: String in Game.roster.keys():
		var state: Dictionary = player_state.get(id, {})
		if not state.is_empty():
			state.hp = 5
	print("Survival started with %d players" % Game.roster.size())
	cl_survival.rpc(true, 0.0, 0)
	cl_wave.rpc(1)
	for id: String in Game.roster.keys():
		cl_hearts.rpc(id, 5)


@rpc("any_peer", "reliable")
func sv_zap(slot: int, monster_id: int) -> void:
	if not multiplayer.is_server() or not survival_active:
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = player_state.get(id, {})
	if state.is_empty() or not monsters_by_id.has(monster_id):
		return
	var monster: Dictionary = monsters_by_id[monster_id]
	if Vector3(state.pos).distance_to(monster.pos) > 16.0:
		return
	monster.hp = int(monster.hp) - 1
	var dead: bool = monster.hp <= 0
	if dead:
		monsters_by_id.erase(monster_id)
		survival._bonked_count += 1
	cl_zap_hit.rpc(monster_id, dead)




## Supply crates: keep ~14 scattered on land near-ish players; touching one
## hands over its weapon and it respawns somewhere else.
var crates_by_id: Dictionary = {}





@rpc("authority", "reliable")
func cl_crates(payload: Array) -> void:
	if crates != null:
		crates.update_crates(payload)

@rpc("authority", "reliable")
func cl_crate_taken(id: String, weapon: int) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# Into the bar by the one shared rule — already carrying one
			# and nothing happens, so the bar never fills up with three of
			# the same shooter. The crate is still yours either way;
			# nobody else gets it.
			child.give_item("weapon", weapon)
			# ...and it does NOT become what you are holding. Switching
			# somebody's weapon out from under them mid-fight, because
			# they happened to run over a crate, is how you lose a fight
			# holding a party popper.
			Sfx.play("collect")










# ------------------------------------------------------------------
# Client
# ------------------------------------------------------------------

func _client_setup() -> void:
	fx = WorldFx.new()
	fx.name = "Fx"
	fx.world = self
	add_child(fx)
	chunks = ChunkView.new()
	chunks.name = "Chunks"
	chunks.world = self
	add_child(chunks)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	critter_view = CritterView.new()
	critter_view.name = "Critters"
	add_child(critter_view)
	vehicle_view = VehicleView.new()
	vehicle_view.name = "Vehicles"
	vehicle_view.world = self
	add_child(vehicle_view)
	monster_view = MonsterView.new()
	monster_view.name = "Monsters"
	add_child(monster_view)
	orbs = OrbView.new()
	orbs.name = "Orbs"
	add_child(orbs)
	crates = CrateView.new()
	crates.name = "Crates"
	add_child(crates)
	_storm_wall = MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = 1.0
	wall_mesh.bottom_radius = 1.0
	# Tube only — caps would draw a red roof over the whole arena.
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	# A 12-block wall you can see marching in, not a full-sky red curtain.
	wall_mesh.height = 12.0
	wall_mesh.radial_segments = 96
	_storm_wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.75, 0.12, 0.1, 0.82)
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_storm_wall.material_override = wall_mat
	_storm_wall.visible = false
	add_child(_storm_wall)
	storm_changed.connect(func() -> void:
		_storm_wall.visible = match_phase == "BATTLE" and storm_radius > 0.0
		var wall_top := float(WorldGen.CHUNK_H) + 10.0
		_storm_wall.scale = Vector3(storm_radius, wall_top / 12.0, storm_radius)
		_storm_wall.position = Vector3(storm_center.x, wall_top * 0.5,
			storm_center.z))
	match_changed.connect(func() -> void:
		if match_phase != "BATTLE":
			_storm_wall.visible = false)
	sky = DayNight.new()
	sky.name = "Sky"
	add_child(sky)
	chunks.first_chunks_ready.connect(func() -> void:
		if not _ready_announced:
			_ready_announced = true
			world_ready.emit())
	var focus_timer := Timer.new()
	focus_timer.wait_time = 0.4
	focus_timer.timeout.connect(_client_update_focus)
	add_child(focus_timer)
	focus_timer.start()
	Game.roster_changed.connect(_client_sync_players)
	_client_sync_players()
	sv_hello.rpc_id(1)

## Keep one Player node per roster entry; local ones get their InputSlot and
## ask the server where they should stand (saved spot or the spawn).
func _client_sync_players() -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null or players == null:
		return  # tearing down after a lost connection
	var me := multiplayer.get_unique_id()
	var wanted := {}
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		wanted[id] = true
		var existing: Player = null
		for child in players.get_children():
			if child is Player and child.player_id == id:
				existing = child
				break
		if existing != null:
			existing.refresh_from_roster(entry)
			continue
		var is_local: bool = entry.peer == me and Game.local_inputs.has(entry.slot)
		var player := Player.new()
		player.name = "P_" + id.replace(":", "_")
		var input_slot: InputSlot = Game.local_inputs.get(entry.slot) if is_local else null
		player.setup(id, entry, is_local, input_slot, self)
		players.add_child(player)
		if is_local and input_slot is BotSlot:
			var brain := BotBrain.new()
			brain.player = player
			brain.bot = input_slot
			player.add_child(brain)
		if is_local:
			sv_where.rpc_id(1, int(entry.slot))
			Sfx.play("join")
	for child in players.get_children():
		if child is Player and not wanted.has(child.player_id):
			child.queue_free()

func _client_update_focus() -> void:
	var focus: Array = []
	for child in players.get_children():
		if child is Player and child.is_local:
			focus.append(child.position)
	if focus.is_empty():
		focus.append(Vector3(spawn_pos))
	chunks.set_focus(focus)
	if sky != null:
		sky.set_clock(clock)
		# Rate as well as time: the sky advances its own clock between
		# server syncs, so it has to be running at the same speed or it
		# drifts and then snaps back on every update.
		sky.day_length = day_length

func request_chunks(batch: Array) -> void:
	sv_request_chunks.rpc_id(1, batch)

func send_pos(slot: int, pos: Vector3, yaw: float, anim: int) -> void:
	sv_pos.rpc_id(1, slot, pos, yaw, anim)

func send_edit(slot: int, pos: Vector3i, block: int) -> void:
	# Predict locally: the block changes THIS frame (with an immediate
	# synchronous remesh of its chunk) instead of waiting for the server
	# echo to fight through the mesh queue. The echo re-applies the same
	# value, which is a no-op visually.
	if match_phase == "LOBBY" or match_phase == "SETUP":
		return  # pre-battle lockdown: the server would refuse anyway
	if chunks != null:
		chunks.apply_edit_now(pos, block)
	sv_edit.rpc_id(1, slot, pos, block)

@rpc("authority", "reliable")
func cl_overview(bytes: PackedByteArray) -> void:
	overview = bytes

@rpc("authority", "reliable")
func cl_battle_config(minutes: int, size: int, loot: bool, fly := false,
		teams := -1, drop := false, revive := ReviveRule.MATES_AND_FLAG,
		target := 3, fly_bots := false, hold_mins := 10) -> void:
	client_minutes = minutes
	client_size = size
	client_fly_bots = fly_bots
	client_loot = loot
	client_fly = fly
	client_drop = drop
	client_revive_mode = int(revive)
	client_holdout_minutes = float(hold_mins)
	client_ctf_target = target
	# team_count used to live only on the server, so "Remove a team" left
	# the client drawing a column that no longer existed.
	if teams > 0:
		team_count = teams
	battle_config_changed.emit()

@rpc("authority", "reliable")
func cl_map_list(maps: Array) -> void:
	map_list = maps
	map_list_changed.emit()

@rpc("authority", "reliable")
func cl_world_info(p_spawn: Vector3i, p_clock: float, p_source: String,
		p_day_length: float) -> void:
	spawn_pos = p_spawn
	clock = p_clock
	source = p_source
	day_length = maxf(p_day_length, MIN_DAY_SECONDS)
	if sky != null:
		sky.day_length = day_length
	# Procedural islands end well inside the chunk bound — fence closer so
	# kids don't drift over empty ocean; imported maps keep the full area.
	world_radius = 250.0 if p_source == "procedural" \
		else float(ChunkStore.WORLD_RADIUS_CHUNKS) * 16.0 + 16.0
	print("World info: spawn %s, clock %.2f, source %s" % [spawn_pos, clock, source])
	_client_update_focus()

@rpc("authority", "reliable")
func cl_chunk(cx: int, cz: int, blob: PackedByteArray) -> void:
	if chunks != null:
		chunks.receive_chunk(cx, cz, blob)

@rpc("authority", "reliable")
func cl_chunk_batch(entries: Array) -> void:
	for entry in entries:
		if entry is Array and entry.size() == 3:
			cl_chunk(int(entry[0]), int(entry[1]), entry[2])

@rpc("authority", "reliable")
func cl_where(slot: int, pos: Vector3, count: int) -> void:
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	treasures[id] = count
	for child in players.get_children():
		if child is Player and child.player_id == id:
			child.teleport(pos)
	treasures_changed.emit()

## THE NODE FOR A PLAYER ID, without walking every child to find it.
##
## Player nodes are named after their id, so the scene tree can do this by
## hash. It matters because the callers are the hot path: cl_pos scanned
## every child for every position update, which at a hundred players and
## fifteen updates a second is a hundred and fifty thousand comparisons a
## second on every client — quadratic in the player count, for a lookup
## that is a dictionary hit.
func player_node(id: String) -> Player:
	if players == null:
		return null
	return players.get_node_or_null("P_" + id.replace(":", "_")) as Player

@rpc("authority", "unreliable_ordered")
func cl_pos(id: String, pos: Vector3, yaw: float, anim: int) -> void:
	_place_remote(id, pos, yaw, anim)

## EVERY COMPUTER PLAYER IN ONE PACKET.
##
## This was one RPC per player per tick: a hundred players at fifteen a
## second is fifteen hundred packets a second, each carrying its own node
## path and method id, for about fifty bytes of actual position. The
## overhead was most of the traffic and all of the packet count.
##
## One packet a tick now, whatever the roster size — fifteen a second
## instead of fifteen hundred. The entries are [id, pos, yaw, anim].
@rpc("authority", "unreliable_ordered")
func cl_pos_batch(moves: Array) -> void:
	for move: Array in moves:
		_place_remote(str(move[0]), move[1], float(move[2]), int(move[3]))

func _place_remote(id: String, pos: Vector3, yaw: float, anim: int) -> void:
	var who := player_node(id)
	if who == null or who.is_local:
		return
	who.remote_update(pos, yaw, anim)
	if out_ids.has(id) and who.visible:
		who.visible = false

func _nearest_local_dist(pos: Vector3) -> float:
	var best := 999.0
	if players == null:
		return best
	for child in players.get_children():
		if child is Player and child.is_local:
			best = minf(best, child.position.distance_to(pos))
	return best

@rpc("authority", "reliable")
func cl_edit(pos: Vector3i, block: int, by_id: String) -> void:
	if chunks == null:
		return
	var old := chunks.apply_edit(pos, block)
	edit_applied.emit(pos, block, by_id)
	if by_id.is_empty():
		return  # world magic (tree growth, dawn flowers) is quiet
	# Block sounds fall off with distance from the nearest local player
	# (the storm chews terrain constantly — it should be a distant
	# rumble, not a full-volume drumbeat everywhere).
	var edit_dist := _nearest_local_dist(Vector3(pos))
	var edit_vol := -edit_dist * 0.7
	if block == Blocks.AIR:
		if old == Blocks.CONFETTI:
			# Party popper! Confetti everywhere and a little cheer.
			Sfx.play("cheer", edit_vol)
			for color in [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"), Color("ef8fc0")]:
				fx.burst(pos, color)
			fx.flash_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Color("ffd166"), 3.0)
		elif old > 0 and Blocks.is_collectible(old):
			Sfx.play("collect", edit_vol)
		elif edit_dist < 55.0:
			Sfx.play("dig", edit_vol)
		if old > 0 and old != Blocks.CONFETTI:
			fx.burst(pos, Blocks.color_of(old))
	elif edit_dist < 55.0:
		Sfx.play("place", edit_vol)

## Mixed-block bulk change (structure stamps).
@rpc("authority", "reliable")
func cl_edits(pairs: Array) -> void:
	if chunks == null:
		return
	for entry in pairs:
		if entry is Array and entry.size() == 2 and entry[0] is Vector3i:
			chunks.apply_edit(entry[0], entry[1])
	if not pairs.is_empty() and pairs[0] is Array and pairs[0][0] is Vector3i:
		var stamp_vol := -_nearest_local_dist(Vector3(pairs[0][0])) * 0.6
		Sfx.play("place", stamp_vol)
		Sfx.play("whoosh", stamp_vol - 8.0)

@rpc("authority", "reliable")
func cl_survival(active: bool, seconds: float, bonked: int) -> void:
	survival_active = active
	if active:
		survival_wave = 1
		hearts.clear()
		Sfx.play("boom", -8.0)
	else:
		survival_ended.emit(seconds, bonked)
		Sfx.play("cheer")
	survival_changed.emit()

@rpc("authority", "reliable")
func cl_wave(wave: int) -> void:
	survival_wave = wave
	if wave > 1:
		Sfx.play("whoosh", -4.0, 0.7)
	survival_changed.emit()

@rpc("authority", "unreliable")
func cl_monsters(payload: Array) -> void:
	if monster_view != null:
		monster_view.update_monsters(payload)

@rpc("authority", "reliable")
func cl_zap_hit(monster_id: int, dead: bool) -> void:
	if monster_view != null:
		monster_view.hit(monster_id, dead)

@rpc("authority", "reliable")
func cl_reset_vote() -> void:
	reset_vote_started.emit()

@rpc("authority", "reliable")
func cl_reset_result(happened: bool) -> void:
	reset_result.emit(happened)
	if happened:
		Sfx.play("cheer")

@rpc("authority", "reliable")
func cl_world_reset() -> void:
	if chunks != null:
		chunks.reset()
	# Everyone re-asks where to stand in the new world.
	for slot: int in Game.local_inputs.keys():
		sv_where.rpc_id(1, slot)

@rpc("authority", "reliable")
func cl_suck(id: String, block: int) -> void:
	Sfx.play("collect", -6.0 - _nearest_player_dist(id) * 0.8)
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# Same rule as a crate. This used to drop the block into the
			# slot next to your hand whatever was already in it, so
			# sucking up a stray block could cost you a weapon.
			child.give_item("block", block)

@rpc("authority", "reliable")
func cl_fling(id: String) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			child.velocity.y += 22.0
			child.carry_time = 0.5
			child.on_floor = false
			Sfx.play("whoosh")

@rpc("authority", "reliable")
func cl_party_fx(pos: Vector3i) -> void:
	Sfx.play("cheer", -_nearest_local_dist(Vector3(pos)) * 0.5)
	for color in [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"), Color("ef9fc8")]:
		fx.burst(pos, color)
	fx.flash_light(Vector3(pos), Color("ffd166"), 4.0)

@rpc("authority", "reliable")
func cl_hearts(id: String, hp: int) -> void:
	hearts[id] = hp
	hearts_changed.emit()
	_refresh_overheads()

## Push hearts + team color onto every player's overhead tag.
func _refresh_overheads() -> void:
	if players == null:
		return
	var local_teams: Dictionary = {}
	for lid in Game.local_player_ids():
		local_teams[int(Game.roster.get(lid, {}).get("team", -1))] = true
	for child in players.get_children():
		if child is Player:
			var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
			var team_color: Color = TEAM_COLORS[team] if team >= 0 and \
				team < TEAM_COLORS.size() else Color(1, 1, 1)
			child.refresh_overhead(int(hearts.get(child.player_id, 8)),
				team_color, client_downed.has(child.player_id),
				team >= 0 and local_teams.has(team))

signal local_hurt(id: String, from_pos: Vector3)

@rpc("authority", "reliable")
func cl_bonk(id: String, monster_pos: Vector3) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# A hit should HURT on screen, not launch you across the map.
			var away: Vector3 = child.position - monster_pos
			away.y = 0
			child.velocity += away.normalized() * 3.0 + Vector3.UP * 2.0
			child.velocity = child.velocity.limit_length(18.0)
			child.carry_time = 0.25
			Sfx.play("bonk", 2.0, 0.8)
			local_hurt.emit(id, monster_pos)

@rpc("authority", "reliable")
func cl_downed(id: String) -> void:
	hearts[id] = 0
	hearts_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# Clamped client-side too: this is the one placement the
			# server does not hand down, and spawn_pos arrives over the
			# wire from whatever world the server last built.
			var half := float(int(client_size) / 2 - 4)
			var home := Vector3(clampf(float(spawn_pos.x), -half, half) + 0.5,
				float(spawn_pos.y) + 2.0,
				clampf(float(spawn_pos.z), -half, half) + 0.5)
			child.teleport(home)
			Sfx.play("drop")

## Bulk terrain change (explosions, sponge drains) — one message, not one
## per block.
@rpc("authority", "reliable")
func cl_batch(cells: Array, block: int) -> void:
	if chunks == null:
		return
	for cell in cells:
		if cell is Vector3i:
			chunks.apply_edit(cell, block)

@rpc("authority", "reliable")
func cl_fuse_fx(pos: Vector3i) -> void:
	if chunks == null:
		return
	var sparks := CPUParticles3D.new()
	sparks.position = Vector3(pos) + Vector3(0.5, 1.05, 0.5)
	sparks.amount = 10
	sparks.lifetime = 0.4
	sparks.direction = Vector3.UP
	sparks.spread = 25.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.gravity = Vector3(0, -4, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	sparks.mesh = mesh
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(3.4).timeout.connect(func() -> void:
		if is_instance_valid(sparks):
			sparks.queue_free())

## ------------------------------------------------------------------
## Team signals
## ------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func cl_flare(pos: Vector3, team: int) -> void:
	if orbs == null:
		return
	var tint: Color = TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() \
		else Color("ff9ac0")
	orbs._spawn_flare(pos + Vector3(0.5, 0.5, 0.5), tint)



@rpc("authority", "call_local", "reliable")
func cl_smoke(pos: Vector3, team: int) -> void:
	# `call_local`, so this runs on the SERVER as well — where there is no
	# fx node and no chunk view, because neither is built for a headless
	# world. `chunks` was guarded and `fx` was not, so every smoke round
	# fired threw a script error on the server. Harmless to the game and
	# very loud in a log, which is worse than it sounds: a log full of
	# errors is a log nobody reads the next one in.
	if fx != null:
		fx.drop_smoke_marker()
	if chunks == null:
		return
	var tint: Color = TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() \
		else Color("f0f0f0")
	var centre := pos + Vector3(0.5, 0.5, 0.5)
	var marker := Node3D.new()
	marker.position = centre
	add_child(marker)
	fx._smoke_node = marker
	# A fat column of drifting puffs — readable from the far side of the
	# map without hiding anything, which is the whole point: it marks a
	# place, it is not cover.
	var puff_mat := StandardMaterial3D.new()
	puff_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.5)
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.emission_enabled = true
	puff_mat.emission = tint
	puff_mat.emission_energy_multiplier = 1.6
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 12:
		var puff := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.9 + float(i) * 0.10
		sphere.height = sphere.radius * 2.0
		puff.mesh = sphere
		puff.material_override = puff_mat
		puff.position = Vector3(randf_range(-0.7, 0.7), float(i) * 1.15,
			randf_range(-0.7, 0.7))
		marker.add_child(puff)
	# ONE tween, bound to the MARKER, and killed with it.
	#
	# This used to be fourteen infinite tweens created with the WORLD's
	# create_tween() — so they were bound to the world, not to the puffs.
	# Clearing the marker freed the puffs and left every one of those
	# tweens alive, looping forever over objects that no longer existed,
	# for every smoke bomb anyone had ever thrown. Godot reports each
	# invalid step, and printing errors with backtraces is slow enough
	# that a few bombs' worth brought the client to a halt. Both machines
	# locked up together because both were sent the same cl_smoke.
	fx._smoke_tween = marker.create_tween().set_loops()
	fx._smoke_tween.tween_property(marker, "position:y", centre.y + 0.5, 1.9)
	fx._smoke_tween.tween_property(marker, "position:y", centre.y, 1.9)
	var beam := OmniLight3D.new()
	beam.omni_range = 26.0
	beam.light_energy = 2.2
	beam.light_color = tint
	beam.shadow_enabled = false
	beam.position = Vector3(0, 3.0, 0)
	marker.add_child(beam)
	Sfx.play("pop", -8.0 - _nearest_local_dist(centre) * 0.4)

@rpc("authority", "call_local", "reliable")
func cl_smoke_clear() -> void:
	# Server-side too — see cl_smoke.
	if fx != null:
		fx.drop_smoke_marker()


@rpc("authority", "reliable")
func cl_boom_fx(pos: Vector3i, power := 2.2) -> void:
	if chunks == null:
		return
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	Sfx.play("boom", -_nearest_local_dist(center) * 0.35)
	fx.explosion(center, power)
	fx.flash_light(center, Color(1.0, 0.7, 0.35), 5.0 + power * 1.6,
		clampf(power / 2.2, 1.0, 2.4))
	# Harmless, hilarious: anyone close gets launched.
	for child in players.get_children():
		if child is Player and child.is_local:
			var away: Vector3 = child.position - center
			var dist := away.length()
			if dist < 7.0:
				away.y = 0
				var push := (7.0 - dist) / 7.0
				child.velocity += away.normalized() * 10.0 * push + Vector3.UP * 9.0 * push
				child.velocity = child.velocity.limit_length(30.0)
				child.carry_time = 0.6
				child.on_floor = false

@rpc("authority", "reliable")
func cl_firework_fx(pos: Vector3i) -> void:
	if chunks == null:
		return
	var fw_vol := -_nearest_local_dist(Vector3(pos)) * 0.5
	Sfx.play("whoosh", fw_vol)
	var burst_at := Vector3(pos) + Vector3(0.5, 11.0, 0.5)
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		var colors := [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"),
			Color("51c979"), Color("ef8fc0")]
		Sfx.play("pop", fw_vol)
		Sfx.play("collect", fw_vol - 4.0)
		fx.flash_light(burst_at, colors[randi() % colors.size()], 4.0)
		for ring in 2:
			var burst := CPUParticles3D.new()
			burst.position = burst_at
			burst.amount = 40
			burst.lifetime = 1.2
			burst.one_shot = true
			burst.explosiveness = 1.0
			burst.spread = 180.0
			burst.initial_velocity_min = 5.0 + ring * 3.0
			burst.initial_velocity_max = 7.0 + ring * 3.0
			burst.gravity = Vector3(0, -3, 0)
			var mesh := SphereMesh.new()
			mesh.radius = 0.06
			mesh.height = 0.12
			var mat := StandardMaterial3D.new()
			var color: Color = colors[(randi() + ring) % colors.size()]
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.5
			mesh.material = mat
			burst.mesh = mesh
			add_child(burst)
			burst.emitting = true
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				if is_instance_valid(burst):
					burst.queue_free()))




@rpc("authority", "reliable")
func cl_treasures(id: String, count: int) -> void:
	treasures[id] = count
	treasures_changed.emit()

@rpc("authority", "reliable")
func cl_clock(frac: float, p_day_length: float) -> void:
	clock = frac
	# The rate comes with the time. A client that only heard the time would
	# drift its own sky at the idle rate all the way through a battle,
	# getting further out of step with the server every second, and then
	# jump whenever the next sync landed.
	day_length = maxf(p_day_length, MIN_DAY_SECONDS)
	if sky != null:
		sky.day_length = day_length

@rpc("authority", "unreliable")
func cl_critters(payload: Array) -> void:
	if critter_view != null:
		critter_view.update_critters(payload)

@rpc("authority", "reliable")
func cl_pet(critter_id: int) -> void:
	if critter_view != null:
		critter_view.pet(critter_id)
		Sfx.play("pet")


# ------------------------------------------------------------------
# Capture the flag
# ------------------------------------------------------------------
##
## A third mode beside Just Building and Battle Royale, and the first one
## that scores on something other than knockouts.
##
## Every team gets a BASE — for now a hollow dirt box, dug into the hill it
## stands on so there is never a gap underneath — with the team's FLAG on a
## short wool pole in the middle of it. The team starts inside. Touching an
## enemy flag scores: +1 you, -1 them, and their flag comes back a few
## seconds later. First team to `ctf_target` wins. There is no clock and no
## storm; a round ends on the scoreboard or not at all.
##
## Knockouts do NOT score here, which is the point of the mode: shooting
## someone only buys you the seconds it takes them to get back.





var ctf_target := 3
## Revive ON is the gentle default: knockouts work exactly as they do in
## Battle Royale. Turn it off and a knockout puts you straight OUT, and you have to
## fly home and touch their own flag to rejoin — which is the version that
## makes attacking a distant base a real commitment.
## Cross-mode: does a knockout scatter your weapons where you fell?
var drop_on_knockout := false
var ctf_scores: Dictionary = {}   # team index -> net score (caps - losses)
## Captures MADE by each team, and flags LOST by each team. Kept apart from
## the net score because the table shows all three, and "3 for, 1 against"
## is a different story from "2".
var ctf_caps: Dictionary = {}     # team index -> int
var ctf_lost: Dictionary = {}     # team index -> int
## Who actually ran the flags in. player id -> count.
var ctf_player_caps: Dictionary = {}

## BACKSTOP ONLY. A knocked-out computer player walks to its own flag and
## tags in there, the same way a person does; this is the fuse for one that
## cannot get there — walled in, dropped in a pit — so nobody is out for a
## whole round because of the terrain. It used to be the actual mechanism,
## at 8 seconds, which teleported them home before they had walked anywhere
## and is why they never appeared to know the way.
const BOT_RETURN_MS := 25000























@rpc("authority", "reliable")
func cl_flags(payload: Array, scores: Dictionary, target: int,
		caps: Dictionary = {}, lost: Dictionary = {},
		player_caps: Dictionary = {}) -> void:
	flags = payload
	ctf_scores = scores
	ctf_target = target
	ctf_caps = caps
	ctf_lost = lost
	ctf_player_caps = player_caps
	flags_changed.emit()

@rpc("authority", "reliable")
func cl_flag_taken(id: String, team: int, from_team: int) -> void:
	flag_taken.emit(id, team, from_team)


## Take a heart (or several) off somebody, from an attacker or from the
## world itself. Kept on the world node because it is what every weapon
## RPC and the bot director reach for, and `world.match_hurt(...)` is a
## plainer thing to call than reaching through to the director.
func match_hurt(id: String, amount: int, from_pos: Vector3, attacker := "") -> void:
	if battle != null:
		battle.hurt(id, amount, from_pos, attacker)

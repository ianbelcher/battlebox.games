# How BattleBox is put together

A map of the codebase, and the reasoning behind the parts that would
otherwise look arbitrary.

## The shape of a running game

```
                 TLS terminator          anything that passes upgrades
                       │                 through and leaves headers alone
                     nginx               the browser build
                       │
          ┌────────────┴────────────┐
     /api/rooms                 /ws?room=<code>
          │                         │
          └────────► lobby ◄────────┘        lobby/lobby.py
                       │
        ┌──────────────┼──────────────┐
     room "house"  room "brave-otter"  ...  one headless Godot server each
```

Everything a player touches is on one origin and one port. That is not
tidiness: a page served over https cannot open a plain `ws://` socket at
all, and the browser build needs cross-origin isolation, which only counts
in a secure context.

### A room is a process

Not a compartment inside one. The alternative — N worlds in one server —
would need all ~140 broadcast `rpc()` call sites made room-aware, and
would put every room's bots, water, fire and critters on the single thread
GDScript gives the server.

A process per room buys isolation (a crash takes one game), more than one
core, and cleanup for free: a room that ends is a process that exits, so
there is no teardown path to get wrong and no memory to leak between
games. `game/src/room.gd` is the watchdog that does the exiting;
`lobby/lobby.py` starts them, proxies to them and reaps them.

It cost almost nothing to adopt because the server was already configured
entirely from its environment and already wrote nothing to disk.

### A game is set up before it exists

That last sentence is also what makes the front page work. Mode, map,
world size, round length, capture target, knockout rules, how many teams
and how many players there are seats for are all chosen on the **New game** screen,
before any process has started, and travel like this:

```
lobby_screen.gd  →  lobby_client.gd  →  POST /api/rooms {settings}
                                             ↓
                                        lobby.py: clean_settings()
                                             ↓
                                        settings_env() → WORLD_* env
                                             ↓
                                        a new room process
                                             ↓
                                        chunk_store.gd  reads the map and size
                                        room_setup.gd   reads the rest
```

`game/src/game_setup.gd` is the table of what can be chosen; `lobby.py`
holds a second copy of the same rules, deliberately, because **the
client's copy is not a validator** — anything can POST to that endpoint.

The map and the size are applied a step earlier than everything else, by
`ChunkStore` at generation time, and that is the whole point of doing it
this way: the terrain **is** the map that was asked for. Chosen from
inside a running game instead, the same setting is a world reset
performed on people who are standing in the world.

**And none of it can be changed afterwards.** Every setting above is
gone from both in-game menus — the mode, the map, the world's size, the
round length, the capture target, how you get back up, who can fly.
Changing the mode ended the round everybody was in; changing the map or
the size rebuilt the world under whoever was standing on it; the rest
changed the rules out from under people halfway through. One person idly
reading a menu, everyone else's game over.

The world menu is now three things and no settings: how the round is
going, the code that gets a friend in, and the way out to the front page.
`game/tests/menu_controls.gd` fails if any of the old rows come back.

The always-on world is not special either, beyond not closing when the
last person leaves. It is spawned with settings like any other room,
listed like any other room, and says what it is like any other room.

## The client

| File | What it is |
| --- | --- |
| `main.gd` | The shell: screens, the connect/reconnect loop, the server bootstrap |
| `lobby_screen.gd` | The first screen — who you are, Play, the games running, or set one up |
| `quick_play.gd` | Which game Play puts you in: people first, then the always-open one. Pure; no nodes |
| `title_backdrop.gd` | What is behind it: sky, skyline, drifting blocks |
| `neon_wordmark.gd` | BattleBox, as the neon sign the intro ends on — see `tools/make_wordmark.py` |
| `game_setup.gd` | The table of what a new game can be. Pure; no nodes |
| `lobby_client.gd` | The lobby's JSON API, with no UI in it |
| `ui_theme.gd` | Every colour, radius and font size in every menu |
| `splitscreen.gd` | 1–4 SubViewports sharing one World3D, one camera each |
| `render_layers.gd` | Which camera draws what: your own body, your own held item, and the tags over the heads you can see |
| `overhead_sight.gd` | Whether a seat has a clear line to a body, so a name or hearts never float over the wall somebody is hiding behind — and whether a body is close enough and in front to be worth asking about, which is what keeps a hundred-player room from stuttering. Pure; no nodes |
| `player.gd` | Movement, aim, actions. Hand-rolled voxel AABB, no physics engine |
| `player_hud.gd` | Per-player overlay: hotbar, radar, the picker, the menus |
| `world_menu.gd` | The grown-ups' menu (keyboard and mouse only, on purpose) |
| `chunk_view.gd` | Chunk streaming and meshing on worker threads |
| `mesher.gd` | Face culling, per-vertex AO, the AO-aware quad-diagonal flip |

## The server

`world.gd` **is the wire protocol.** Every `@rpc` in the game is declared
there and nowhere else — 89 of them, `sv_*` client-to-server and `cl_*`
server-to-client. One file therefore describes everything that crosses the
socket, and no RPC ever has to resolve against a node path that exists on
one side and not the other.

The simulation lives in sibling nodes under it, each holding a `world`
back-reference, none declaring an RPC:

| Node | File | Owns |
| --- | --- | --- |
| `World/Bots` | `bot_director.gd` | Computer players: what each one sees, what its team knows, and everything it does about both |
| `World/Match` | `match_director.gd` | The round: lobby, drop, revives, the league table — and it asks the mode what a tick is |
| `World/Ctf` | `ctf_director.gd` | Both flag modes: bases, poles, carrying, scoring |
| `World/Terrain` | `terrain_sim.gd` | Water, fire, growth, explosions |
| `World/Critters` | `critter_director.gd` | Where animals live and where they wander |
| `World/Survival` | `survival_director.gd` | Grump raids and supply crates |
| `World/Probes` | `world_probes.gd` | The `WORLD_*_TEST` dev hooks |
| `World/Fx` | `world_fx.gd` | Client-side bangs and sparkles |

A handful of files carry no state at all and exist purely so the awkward
part of a subsystem can be tested: `render_layers.gd` (who sees whose body
on a split screen), `bot_squads.gd` (how computer players deal themselves
into attacking groups), `bot_orders.gd` (how many of a team stay home, and
which enemy flag the rest join), `bot_harbour.gd` (where each defender
stands, and everybody keeping out of everybody else's way),
`bot_threat.gd` (what a computer player does about being shot at),
`vehicle_geom.gd` (where a boat goes, and where somebody standing on it
ends up when it turns), `climb_rule.gd` (what walking into something does)
and `holdout_rules.gd` (what a round of last flag standing is worth, and
how much of a team stays home). None of them touches an autoload, because
a `--script` run has none — which is exactly why the logic worth checking
has to live somewhere that needs nothing.

The bot ones are all there for the same reason, and it is worth stating
because it is not obvious: the things that go wrong with computer players
are RATIOS AND SHAPES, not exceptions. "They all huddle round the flag"
is a keeper count; "they run off in random directions" is a target
choice; "they just march around the flag" is a set of coordinates. None
of those raises anything, none of them fails a boot, and every one of
them can be asked about directly once the arithmetic is somewhere with no
world behind it.

The rule the split follows: **if both ends need to know it, the world owns
it; if only the server needs it to run the simulation, the director owns
it.** `match_phase` is on the world because a client draws it.
`_storm_hurt_ms` is on the director because nobody else can use it.

`world.gd` was 6,255 lines before this split and is 2,749 after. If you
find yourself adding a two-hundred-line subsystem to it, add a director
instead.

## The platform and the game on it

The world is the **platform**: blocks, digging, building, running,
shooting, vehicles, weather, the wire protocol. It never asks what game
is being played. Everything that makes a round a round is a **mode** —
one file in `game/src/modes/`, a `GameMode` — and **that file owns its
mechanics**. Battle royale's storm is in `battle_mode.gd`, not in the
match director. Capture the flag's scoring is in `ctf_mode.gd`. Last
flag's clock, elimination and end-of-round share-out are in
`holdout_mode.gd`. If two modes want a similar thing, each writes its
own; the day one of them needs to differ, nothing else breaks.

The platform asks the mode at fixed points and does what it is told:

| The seam | What the mode is asked |
| --- | --- |
| The front page (`game_setup.gd`) | its key, label and note; which settings it uses (`has_clock`, `has_target`, `picks_teams`, …) |
| The lobby and the drop (`MatchDirector`) | `deal_teams`, `team_names`, `on_round_start`, `round_seconds`, `kit`, `max_hp` |
| Every battle tick | `tick(world, delta, seconds_left)` — the mode's own machinery — then `on_time_up` and `winner` |
| A knockout | `on_knockout`: the revive ladder, or convert, or respawn |
| A flag touched (`CtfDirector`) | `on_flag_taken`: a point and a flag that comes back, or a side out |
| Hearts growing back | `regen_ms` |
| A late joiner | `joiner_team` |
| The computer players | `flag_loss_is_out`, `defenders_push` |
| The HUD | the predicates and `kicker`, through the client's copy (`world.client_rules`) |

What the mode calls back into are **primitives** — things the world can
do that know nothing about any game: hearts and elimination, the
closing-circle picture every client draws (`storm_radius`,
`storm_center`, `cl_storm`), crumbling ground (`terrain.crumble_ring`),
the flag machinery (bases, poles, carrying, touching, tagging in,
`send_flag_away`, `knock_out_team`), a line across every screen
(`cl_fanfare`), standing a player up again (`battle.stand_again`), the
blocks. The full list is at the bottom of `game_mode.gd`.

**To add a game:** one file extending `GameMode` with the hooks it has
an opinion about, one line in `GameModes.ALL`, its key in `lobby.py`'s
`MODES`. It is then on the front page, validated on the way in, and
playing. **If it needs something the world cannot do** — spawn a thing
at a point, draw a marker, a new kind of touch — add that as a primitive
on the platform, a method any mode may call. Never add an "objective"
that two modes share: that is how last flag standing came to be a set of
`if elimination()` branches inside capture the flag's code, and how the
storm ended up over a flag round — the drop set it for every mode and
only the modes that knew about it cleared it.

A mode must not name the `Game` autoload, or the front page's unit tests
cannot load it; read the roster through `world.roster()`.

## Data, not code

Gameplay is tables, and adding to a table is the intended way to extend
the game:

| File | Add a row to get |
| --- | --- |
| `game_setup.gd` | A new thing to choose when starting a game (add it to `lobby.py` too) |
| `creatures.gd` | A new animal — height, speed, habitat, animation names |
| `blocks.gd` | A new block — colour, whether it glows, whether it can be dug |
| `structures.gd` | A new stampable prefab |
| `weapons.gd` | A new weapon — cooldown, speed, blast |
| `avatar_factory.gd` | Character parts (and the mix-and-match rules) |

If you are writing a `match` over a kind, look for the table first.

## The voxel pipeline

Chunks are 16×16×80, one byte per block. The server generates them from a
seed and holds them in memory; a client asks for what it can see and gets
zstd-compressed blobs over the same socket as everything else.

Meshing runs on worker threads, which in a browser needs `SharedArrayBuffer`,
which needs cross-origin isolation, which needs the two `Cross-Origin-*`
headers in `nginx.conf` **and** a secure context. All four of those look
optional and none of them are.

Meshes are face-culled with per-vertex ambient occlusion, including the
AO-aware quad-diagonal flip that stops the classic dark-corner artefact.
No textures at all: colour comes from per-position jitter, and wind sway
and water are shaders driven by vertex data in UV2.

## Nothing is persisted

Not chunks, not players, not scores. A world is generated into memory at
boot and dies with the process. A restart is a clean table by construction
rather than by a cleanup step, a host has nothing to back up, and a whole
family of "state left over from last time" bugs cannot happen — see
the invariant below.

The one invariant that makes it safe: an **edited** chunk may never be
dropped from the server's cache. It has no file to come back from, so
evicting one would silently regenerate the terrain under somebody's fort.
`ChunkStore.trim_cache()` only ever drops ocean chunks past the edge of
the map.

**The slab is generated ahead of anybody asking for it.** Chunks used to
be made on demand, by the first client to walk somewhere, on the server's
only thread — six of them a frame at ten milliseconds each, which was a
frame of seventy to two hundred milliseconds for as long as anyone was
streaming, and every drop streams. `ChunkStore.warm()` works through the
slab from the middle out in the time the server has spare, and keeps
each chunk's zstd wire form (`_packed`) so sending it to the next client
is a dictionary hit. Memory is bounded by the world, not the uptime: at
most 49×49 chunks of 20 KiB.

## Keeping a hundred seats at thirty ticks

The server runs at thirty ticks a second (`Main.SERVER_TICKS_PER_SECOND`),
and `WORLD_NETSTAT=1` prints where each second of it went, by subsystem,
every five seconds (`tick_stats.gd`). That report is how the following
were found, and the numbers are from a hundred-seat battle royale on a
four-hundred-block world:

- **One roster picture per frame.** Everything a computer player decides
  starts with "who is standing where, on which side"; seven different
  walks of the roster asked it per bot. `BotDirector.refresh_picture()`
  takes it once, splits it by side and buckets it on an 8-block grid, and
  the enemies scan, the rescue rules, the revive tick and the orbs in
  flight all read that. Orbs went from 200 ms/s to 40.
- **Half the bots a frame.** A bot's positions go out at fifteen a second
  whatever the tick rate; `BOT_STRIDE` steps each one every other frame
  with the time that has passed. Nothing visible changes.
- **A look that found nobody is not repeated next frame.** The sight
  search was gated on the weapon cooldown, which a bot with nobody to
  shoot never starts — so it searched sixty times a second. `look_cd`.
- **Rays and columns read one chunk, not one block.** `clear_shot()` and
  `ChunkStore.walkable_y()` hold the chunk they are in.

Before: nine to thirteen ticks a second in a battle. After: the cap.

## Testing

| Layer | Where | Catches |
| --- | --- | --- |
| Unit | `game/tests/unit/`, run by `run_tests.gd` | Logic, tables, pure functions |
| Lobby unit | `lobby/test_lobby.py` | Codes, listing rules, the room heartbeat contract |
| Integration | `tools/integration_test.py` | A real client against a real server, in three modes |
| Rooms | `tools/lobby_test.py` | Create, join through the proxy, reap |
| Asset | `game/tests/ui_glyphs.gd`, `flag_beacons.gd` | Things that fail silently and look fine |

The integration tests exist because of one specific property of Godot: an
RPC sent to a node path that does not exist **does not raise**. The call
lands nowhere, the world stays empty, and the build, the deploy and every
health check stay green. So those tests assert on the state both ends
reached — chunks streamed, roster broadcast, avatars spawned — rather than
on the absence of errors.

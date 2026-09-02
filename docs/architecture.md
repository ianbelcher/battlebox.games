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
world size, round length, capture target, knockout rules and how many
computer players are waiting are all chosen on the **New game** screen,
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

Every one of these can still be changed mid-game from the world menu.
What the front page removes is the need to.

## The client

| File | What it is |
| --- | --- |
| `main.gd` | The shell: screens, the connect/reconnect loop, the server bootstrap |
| `lobby_screen.gd` | The first screen — play, join a running game, or set one up |
| `title_backdrop.gd` | What is behind it: sky, skyline, drifting blocks |
| `game_setup.gd` | The table of what a new game can be. Pure; no nodes |
| `lobby_client.gd` | The lobby's JSON API, with no UI in it |
| `ui_theme.gd` | Every colour, radius and font size in every menu |
| `splitscreen.gd` | 1–4 SubViewports sharing one World3D, one camera each |
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
| `World/Match` | `match_director.gd` | Battle: lobby, drop, storm, revives, the league table |
| `World/Ctf` | `ctf_director.gd` | Both flag modes: bases, poles, carrying, scoring |
| `World/Terrain` | `terrain_sim.gd` | Water, fire, growth, explosions |
| `World/Critters` | `critter_director.gd` | Where animals live and where they wander |
| `World/Survival` | `survival_director.gd` | Grump raids and supply crates |
| `World/Vehicles` | `vehicle_director.gd` | Boats and cars: the fleet, the ids, one driver each |
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
`ChunkStore.trim_cache()` only ever drops chunks that are still exactly as
generated.

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

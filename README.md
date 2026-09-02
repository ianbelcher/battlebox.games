# BattleBox

[![licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478cbf.svg)](https://godotengine.org)

A voxel game that runs in a browser. Built for children; playable at
**[battlebox.games](https://battlebox.games)**, and this repository is the
whole of it — clone it and run your own.

Anyone can start a game, and sets it up before going in: the mode, the
map, how big the world is, how long a round lasts, how many computer
players are waiting in it. A public one is listed for everybody, with
what it is written under its name; a private one gets a two-word code and
is shared as a link. When the last player leaves, a created game closes
itself.

## Running it

Two terminals, one world, no lobby — the quickest loop and what most
changes need:

```sh
# A dedicated server (headless implies the server role)
godot --headless --path game

# A client that joins it
WORLD_ROLE=client WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
```

The whole thing, with a lobby and as many games as you like:

```sh
# The lobby starts a world per game itself
python3 lobby/lobby.py --server "godot --headless --path $PWD/game"

# Clients get the lobby screen and pick a game
WORLD_SERVER_URL=ws://127.0.0.1:9080/ws godot --path game

# Or skip the screen and go straight to one
WORLD_SERVER_URL=ws://127.0.0.1:9080/ws WORLD_ROOM=brave-otter godot --path game
```

Needs [Godot 4.7](https://godotengine.org/download) and Python 3.11+. No
other dependencies: the lobby is standard library only, and the game
bundles its own assets.

### As a container

```sh
.bin/build.sh
BATTLEBOX_IMAGE=battlebox docker compose -f deploy/docker-compose.yml up -d
```

Then put a TLS terminator in front of port 8081 — anything that passes
websocket upgrades through and leaves response headers alone. **It has to
be https**: the browser build meshes chunks on real threads, which needs
`SharedArrayBuffer`, which browsers only give to a cross-origin isolated
page, and isolation only counts in a secure context. Over plain http the
game loads and then dies.

## How it is put together

[`docs/architecture.md`](docs/architecture.md) is the map. In short:

- **`game/src/world.gd` is the wire protocol.** Every `@rpc` in the game is
  declared there and nowhere else, so one file describes everything that
  crosses the socket. The simulation lives in sibling nodes beside it —
  `bot_director`, `match_director`, `ctf_director`, `terrain_sim`,
  `critter_director`, `survival_director` — which hold a `world`
  back-reference and declare no RPCs of their own. A unit test enforces it.
- **A room is a server process**, not a compartment inside one. The lobby
  starts one per game on a private port and proxies `/ws?room=<code>` to
  it. See [`game/src/room.gd`](game/src/room.gd).
- **Gameplay is data.** New animal → `creatures.gd`. New block →
  `blocks.gd`. New prefab → `structures.gd`. Something new to choose when
  starting a game → `game_setup.gd`, and its twin in `lobby/lobby.py`. If
  you are writing a `match` over a kind, there is a table you should be
  adding a row to.
- **A game is configured before it exists.** What the front page chooses
  is sent with the create, turned into `WORLD_*` environment by the lobby
  and applied at boot — so a world is *generated* as the map that was
  asked for rather than reset into it afterwards. See
  [`docs/architecture.md`](docs/architecture.md).
- **Nothing is written to disk.** Not chunks, not players, not scores. A
  world is generated into memory at boot and dies with the process, so a
  restart is a clean table by construction.

```
game/            the Godot project
game/src/        every script; world.gd is the protocol, *_director.gd the
                 simulation, and gameplay is data in creatures.gd,
                 blocks.gd and structures.gd
game/tests/unit/ the unit suite; run_tests.gd finds and runs it
game/tests/      headless harnesses — map renders, the .mca importer test,
                 the kit importer
lobby/           the room registry: registry, process supervisor and
                 websocket proxy, standard-library Python
tools/           the test drivers (integration_test.py, lobby_test.py,
                 boot_test.js), screenshot.sh for looking at the UI
                 without a screen, and offline generators (make_mca.py,
                 fetch_kits.py)
maps/            optional Minecraft saves, one folder each (see its README)
web/             the loading screen the browser build is wrapped in
deploy/          a compose file for running it yourself
docs/            architecture.md
```

## The voxel pipeline

Chunks are 16×16×80, one byte per block. The server generates them from a
seed and holds them in memory; a client asks for what it can see and gets
zstd-compressed blobs over the same socket as everything else. Meshing runs
on worker threads.

No textures at all: colour comes from per-position jitter, and wind sway
and water are shaders driven by vertex data in UV2. Meshes are face-culled
with per-vertex ambient occlusion, including the AO-aware quad-diagonal
flip that avoids the classic dark-corner artefact. Movement is hand-rolled
voxel AABB — there is no physics engine.

The `.mca` importer parses Anvil region files directly in GDScript (NBT,
1.16+ packed palettes, 1.18+ section layout, zlib/gzip) and maps ~200 block
types onto the game's palette. Drop a save in `maps/` and it appears as a
choice; with none there the picker does not appear at all.

## Testing

```sh
# Unit tests. WORLD_TEST_FILTER=<substring> runs a subset.
godot --headless --path game --script res://tests/run_tests.gd

# The lobby's own logic
python3 -m unittest discover -s lobby -p 'test_*.py'

# A real client against a real server, in each mode
python3 tools/integration_test.py
python3 tools/integration_test.py --mode battle
python3 tools/integration_test.py --mode ctf

# Rooms: created, joined through the proxy, and reaped
python3 tools/lobby_test.py

# The Minecraft importer, against a generated region file
python3 tools/make_mca.py /tmp/fixture
WORLD_MCA_DIR=/tmp/fixture godot --headless --path game -s res://tests/test_mca.gd
```

For anything you can see, take a picture of it — no screen required:

```sh
tools/screenshot.sh /tmp/shots
```

That runs the real client under a virtual X server and saves a PNG every
1.5 seconds, so an interface change can be checked rather than guessed at.
`CONTRIBUTING.md` has the details, including why the renderer flag it
passes is load-bearing.

The last two matter more than they look. Booting the project proves the
scripts compile; it does not prove the game works, because an RPC sent to a
node path that no longer exists **does not raise** in Godot. The call lands
nowhere, the world stays empty, and every other check stays green. Those
drivers assert on the state both ends reached instead.

Every `WORLD_*` environment variable the project reads is listed in
[`game/src/env_config.gd`](game/src/env_config.gd), one line each. A unit
test scans the source and fails if that list and the code disagree.

[`CONTRIBUTING.md`](CONTRIBUTING.md) has the rest, including the GDScript
traps that have cost the most time.

## Licence and credits

The code is [MIT](LICENSE). The art, sound, fonts and building kits are
other people's work under their own terms, and [NOTICE](NOTICE) records
which is which — Kenney (CC0) for everything you can see and hear,
Silicon23 (MIT) for the 28 Minecraft builds. Nothing is bundled here that
its licence does not allow to be redistributed.

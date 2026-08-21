# Contributing to BattleBox

This is a game built for a handful of children between four and eight, and
that is the whole design brief. If a change would make it better for a
grown-up and worse for a five-year-old, it is the wrong change.

## Before anything else

```sh
# One terminal: a world
godot --headless --path game

# Another: a client that joins it
WORLD_ROLE=client WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
```

To work on the lobby and multiple games, run that instead:

```sh
python3 lobby/lobby.py --server "godot --headless --path $PWD/game"
WORLD_SERVER_URL=ws://127.0.0.1:9080/ws godot --path game
```

## The checks, and what each of them is for

```sh
# 1. Does it compile? (--export-release does NOT tell you this)
godot --headless --path game --quit-after 240

# 2. Unit tests
godot --headless --path game --script res://tests/run_tests.gd

# 3. The lobby's own logic
python3 -m unittest discover -s lobby -p 'test_*.py'

# 4. A real client against a real server
python3 tools/integration_test.py
python3 tools/integration_test.py --mode battle
python3 tools/integration_test.py --mode ctf

# 5. Rooms: created, joined through the proxy, and reaped
python3 tools/lobby_test.py

# 6. The .mca importer, against a generated region file
python3 tools/make_mca.py /tmp/fixture
WORLD_MCA_DIR=/tmp/fixture godot --headless --path game -s res://tests/test_mca.gd
```

Two more need a real window and so are not in CI. Run them if you are
changing menus or controls — synthetic input goes through the display
server, and headless has none, so both report failure on good code:

```sh
# The menus respond, not just render: Escape opens, clicks land, Tab moves
# the highlight, a joypad button is ignored.
WORLD_MENU_PROBE=1 WORLD_AUTOTEST=1 \
  WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game

# Real gamepad code through the real join path. WORLD_AUTOTEST bots are
# BotSlot, which overrides every button, so bot runs prove nothing about
# controllers — that gap is how the LB-jump regression shipped.
WORLD_FAKE_PADS=2 WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
```

Run at least 1, 2 and 4 before opening a pull request. CI runs all six on
every push and pull request, and the Dockerfile runs them again, so a
green build has actually played the game.

```sh
# The whole image, exactly as CI builds it. Slow the first time: it
# downloads ~1 GB of Godot export templates.
.bin/build.sh
```

**Adding a test is not optional for a behaviour change.** This codebase
has a specific failure mode that nothing else catches: an RPC addressed to
a node path that no longer exists does not raise in Godot. The call lands
nowhere, the world quietly stays empty, and the build, the deploy and the
health checks all stay green. `tools/integration_test.py` asserts on the
STATE both ends reached for exactly that reason. If your change can fail
that way, it needs a check that would notice.

## How the code is laid out

`docs/architecture.md` is the map. The short version:

- **`game/src/world.gd` is the wire protocol.** Every `@rpc` in the game
  lives there and nowhere else, so one file describes everything that
  crosses the socket. The simulation lives in sibling nodes — `bot_director`,
  `match_director`, `ctf_director`, `terrain_sim`, `critter_director`,
  `survival_director`, `world_fx` — which hold a `world` back-reference and
  declare no RPCs of their own. **Keep it that way.** An `@rpc` on a
  director is an RPC that has to resolve against a node path that may only
  exist on one side.
- **Gameplay is data.** New animal? `creatures.gd`. New block? `blocks.gd`.
  New prefab? `structures.gd`. If you are writing a `match` statement over
  a kind, there is probably a table you should be adding a row to.
- **A room is a server process**, not a compartment inside one. See
  `game/src/room.gd`.
- **Nothing is written to disk.** Not chunks, not players, not scores. A
  restart is a clean table on purpose, and a whole family of "state left
  over from last time" bugs cannot happen as a result.

## GDScript, the hard-won parts

- Never `var x := dict.field` or `var x := arr[i].method()`. Variant
  cannot be inferred; type the variable explicitly. This is by far the most
  common parse error in this repo.
- `set_anchors_preset()` inside `_ready()` freezes a control at its
  parent's *current* (often zero) size. Use
  `set_anchors_and_offsets_preset()` for code-built UI.
- After adding a `class_name`, run `godot --headless --path game --import`
  or nothing else will see it.
- A GDScript lambda captures by **value at creation**. A lambda that tries
  to disconnect itself by naming its own variable gets null. Use
  `CONNECT_ONE_SHOT`.
- Godot front faces wind **clockwise**; custom-shader vertex colours arrive
  sRGB and need `pow(c, 2.2)` before `ALBEDO`.

## Style

Match the file you are in. Tabs, typed variables, `snake_case`.

Comments here explain **why**, and especially why something that looks
wrong is not: what was tried, what broke, what a change would cost. That
is the most valuable thing in this repository and the easiest to erode.
A comment restating the line below it is worse than no comment; a comment
recording the afternoon somebody lost is worth keeping forever.

## Art

Everything in `game/assets/` must be redistributable, and `NOTICE` must
say under what terms. Working files that are not — the archive a pack
arrived in, a MagicaVoxel source — go in `source-art/`, which is
gitignored. Kenney (CC0) is the default source and the safest
one. **Do not commit assets from a purchased pack** unless its licence
explicitly permits redistribution — using them in a game and shipping the
raw files in a public repository are different permissions, and most packs
grant only the first.

## What gets turned down

- Anything that can hurt a player outside of ⚔ Attack! and battle mode.
  The world is safe; that is not a default, it is the point.
- Anything that puts a wall of reading in front of a four-year-old.
- Persistence. It has been tried. A world that survives a restart brings
  last session's terrain, teams and time of day back with it, and every one
  of those has been a bug. In-memory is the feature.

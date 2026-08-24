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

## Looking at it

Anything visual — a menu, the lobby, a HUD change, a block icon — should
be **looked at**, not reasoned about. You do not need a screen for that:

```sh
tools/screenshot.sh /tmp/shots          # the first screen
```

That runs the real client under a virtual X server and saves a PNG every
1.5 seconds. Then open the PNGs. Skip the first two or three — they catch
the window mid-build.

Point it wherever you need by setting the same environment variables a
normal run takes:

```sh
# the lobby, against a lobby you have running
WORLD_SERVER_URL=ws://127.0.0.1:9080/ws tools/screenshot.sh /tmp/shots

# in the world, in a particular room, with two bots for company
WORLD_SERVER_URL=ws://127.0.0.1:9080/ws WORLD_ROOM=brave-otter \
  WORLD_AUTOTEST=2 tools/screenshot.sh /tmp/shots 60
```

**Do this before you ship an interface change.** A UI bug is invisible to
everything else here: the unit tests pass, the integration run reaches the
world, the console is clean, and the screen is unreadable. Three real ones
turned up this way in one sitting — a first screen whose text boxes were
twelve pixels tall, a symbol that drew as an empty box, and a `grab_focus`
on a node that was not in the tree yet, which silently cost the Play
button its focus and with it the whole one-press path.

Things worth knowing:

- **`--rendering-method gl_compatibility` is not optional** and the script
  passes it. The default is Forward+, which with no GPU falls to lavapipe,
  and lavapipe *aborts* this project on startup with a C++ backtrace and
  no hint that the renderer is the problem. It is also what the browser
  build uses, so what you photograph is what most players see.
- **Software rendering is slow**, and slowest once local players have
  joined: every chunk is meshed on the CPU behind two or four SubViewports.
  With `WORLD_AUTOTEST` set, give it 60 seconds or you will get two
  screenshots.
- **The log is full of ALSA errors.** There is no sound card. Ignore them;
  the script tells you if there were real script errors.
- **Emoji only render because the fonts are bundled.** They are installed
  everywhere except macOS and Windows, which have their own — so what you
  photograph on Linux is what a browser draws. That was not always true:
  the bundled fonts were web-only, and every screenshot taken here showed
  a tofu box where the game shows a trophy.

One check needs a real browser, because what it tests is entirely about
what a browser will and will not permit:

```sh
# The loading screen: does the intro play with sound on a first visit,
# is that remembered, and does the title screen come back if the browser
# refuses anyway? Run it after touching web/boot.js or web/boot.css.
CHROME_PATH=/path/to/chrome node tools/boot_test.js
```

It is not in CI because the build image has no browser and putting one
there would add hundreds of megabytes to every deploy.
`tools/webtest_play.js` needs one for the same reason.

One check is a TOOL rather than a gate, because it cannot be trusted to
give the same answer twice:

```sh
# Walk into a wall of this height and see whether you get over it.
WORLD_CLIMB_TEST=6 WORLD_AUTOTEST=1 \
  WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --headless --path game
```

It prints a height-over-time graph, which is the only way to see the
failure it exists for: the climb reaching a point just under the lip of a
wall and buzzing there instead of finishing. No error, no crash, the
player is simply an inch short forever.

It is not in CI because it builds its wall in the world where the player
happens to be standing, and that is different every run — on a slope, in
water, or somewhere the server refuses the blocks because they are past
`WorldNode.EDIT_RANGE`. When it says "the wall was never built", that is
what happened; run it again. Compare a run against a run, not against a
remembered number.

Two more checks need a real window and so are not in CI. Run them if you are
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

#!/usr/bin/env python3
"""End-to-end test of the lobby: start it, create games through its API,
join one with a real client, and check the empty ones clean themselves up.

    tools/lobby_test.py [--godot godot]

The unit tests in lobby/test_lobby.py cover the logic. This covers the
parts that only exist when there are processes and sockets: that a created
room really boots, that the websocket proxy carries a whole game's traffic
and not just a handshake, that a private game stays off the public list,
and that a room nobody is in goes away by itself.

That last one is the one worth having. An empty room that does NOT exit is
invisible — the lobby looks healthy, the list looks right, and the box
quietly fills up with abandoned worlds until it runs out of memory.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

# In the repo these are ../game and ../lobby. In the Docker build the
# tools live at /tools and the project at /game, which the same arithmetic
# happens to give — but say so, and let it be overridden, rather than
# leaving a build depending on a coincidence.
REPO = Path(__file__).resolve().parent.parent
GAME = Path(os.environ.get("BATTLEBOX_GAME", REPO / "game"))
LOBBY = Path(os.environ.get("BATTLEBOX_LOBBY", REPO / "lobby" / "lobby.py"))

# Short enough that the reaping test does not dominate the run, long
# enough that a room is not reaped between being created and being joined.
IDLE_EXIT = 12
# A small world so five rooms at once do not need a big machine.
WORLD_SIZE = 96


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def api(base: str, path: str, payload: dict | None = None) -> tuple[int, dict]:
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(
        f"{base}{path}", data=data,
        headers={"Content-Type": "application/json"},
        method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(request, timeout=60) as answer:
            return answer.status, json.loads(answer.read() or b"{}")
    except urllib.error.HTTPError as problem:
        return problem.code, json.loads(problem.read() or b"{}")


class Checks:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passed = 0

    def that(self, ok: bool, described: str) -> bool:
        if ok:
            self.passed += 1
            print(f"  ok  {described}")
        else:
            self.failures.append(described)
            print(f"  FAILED  {described}")
        return ok


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    args = parser.parse_args(argv)

    port = free_port()
    base = f"http://127.0.0.1:{port}"
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    checks = Checks()

    with tempfile.TemporaryDirectory() as scratch:
        log_path = Path(scratch) / "lobby.log"
        with log_path.open("w") as sink:
            lobby = subprocess.Popen(
                [sys.executable, str(LOBBY), "--port", str(port),
                 "--server", f"{args.godot} --headless --path {GAME}",
                 "--idle-exit", str(IDLE_EXIT),
                 "--world-size", str(WORLD_SIZE)],
                env=env, stdout=sink, stderr=subprocess.STDOUT, text=True)
            try:
                return _exercise(args, base, port, checks, lobby, log_path)
            finally:
                lobby.terminate()
                try:
                    lobby.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    lobby.kill()


def _await_line(log_path: Path, needle: str, timeout: float) -> str:
    """Wait for a line on the lobby's own output. The room prints what it
    came up as (see game/src/room_setup.gd) and the lobby prefixes it with
    the room's code, which is the only place the two ends can be compared:
    the API says what was ASKED for, and this says what was BUILT."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in log_path.read_text(errors="replace").splitlines():
            if line.startswith(needle):
                return line
        time.sleep(0.5)
    return ""


def _exercise(args, base: str, port: int, checks: Checks,
              lobby: subprocess.Popen, log_path: Path) -> int:
    print(f"lobby test: on port {port}")
    # The house room has to boot before anything is answerable.
    deadline = time.time() + 120
    while time.time() < deadline:
        if lobby.poll() is not None:
            print("the lobby exited:\n" + log_path.read_text())
            return 1
        try:
            status, health = api(base, "/healthz")
            if status == 200 and health.get("rooms", 0) >= 1:
                break
        except (urllib.error.URLError, ConnectionError, OSError):
            pass
        time.sleep(0.5)
    else:
        print("the lobby never became healthy:\n" + log_path.read_text())
        return 1

    status, listing = api(base, "/api/rooms")
    house = [r for r in listing.get("rooms", []) if r.get("house")]
    checks.that(status == 200 and len(house) == 1,
                "the always-on public game is listed")

    status, public_room = api(base, "/api/rooms",
                              {"name": "Open house", "public": True})
    checks.that(status == 201 and public_room.get("code"),
                f"a public game is created ({public_room.get('code')})")
    # A GAME SET UP BEFORE IT EXISTS. The front page sends these with the
    # create; the lobby turns them into WORLD_* environment and the room
    # is GENERATED as that map rather than reset into it afterwards. The
    # check that matters is the last one: not that the lobby echoed the
    # settings back, but that the process it started actually came up as
    # the thing that was asked for.
    status, made = api(base, "/api/rooms",
                       {"name": "Castle war", "public": True,
                        "settings": {"mode": "ctf", "map": "castles",
                                     "size": 100, "bots": 3, "target": 5}})
    asked = made.get("settings", {})
    checks.that(status == 201 and asked.get("mode") == "ctf"
                and asked.get("map") == "castles",
                f"a game is created as what was asked for ({asked})")
    checks.that(asked.get("size") == 100 and asked.get("bots") == 3,
                f"including its size and its computer players ({asked})")
    _, listing = api(base, "/api/rooms")
    listed = [r for r in listing.get("rooms", [])
              if r.get("code") == made.get("code")]
    checks.that(listed and listed[0].get("settings", {}).get("mode") == "ctf",
                "and the list says what it is, so it can be chosen")
    booted = _await_line(log_path, f"[{made.get('code')}] ROOM setup", 60)
    checks.that("mode=ctf" in booted and "map=castles" in booted
                and "size=100" in booted and "bots=3" in booted,
                f"the room process really booted as that game ({booted.strip()})")

    status, private_room = api(base, "/api/rooms",
                               {"name": "Just us", "public": False})
    checks.that(status == 201 and private_room.get("code"),
                f"a private game is created ({private_room.get('code')})")
    checks.that(public_room.get("code") != private_room.get("code"),
                "two games get two different codes")

    _, listing = api(base, "/api/rooms")
    codes = [r["code"] for r in listing.get("rooms", [])]
    checks.that(public_room["code"] in codes, "the public game is on the list")
    checks.that(private_room["code"] not in codes,
                "the private game is NOT on the list")

    status, _ = api(base, f"/api/rooms/{private_room['code']}")
    checks.that(status == 200,
                "the private game is reachable by its code")
    status, _ = api(base, "/api/rooms/no-such-game")
    checks.that(status == 404, "an unknown code is a 404, not a guess")

    # The real thing: a client, through the proxy, into a named room.
    print(f"  joining {public_room['code']} with a real client...")
    client = subprocess.run(
        [args.godot, "--headless", "--path", str(GAME)],
        env=dict(os.environ,
                 GODOT_SILENCE_ROOT_WARNING="1",
                 WORLD_ROLE="client",
                 WORLD_SERVER_URL=f"ws://127.0.0.1:{port}/ws",
                 WORLD_ROOM=public_room["code"],
                 WORLD_AUTOTEST="2",
                 WORLD_SELFCHECK="14"),
        capture_output=True, text=True, timeout=180)
    report = _last_selfcheck(client.stdout + client.stderr)
    checks.that(report.get("screen") == "world",
                "the client got into the world (not stuck on the lobby)")
    checks.that(int(report.get("chunks", 0)) >= 40,
                f"the proxy carried the world through ({report.get('chunks')} chunks)")
    checks.that(int(report.get("roster", 0)) >= 2,
                "both local players joined that room")

    # A code that is not a room sends the player back to the list rather
    # than into a reconnect loop against a process that will never exist.
    gone = subprocess.run(
        [args.godot, "--headless", "--path", str(GAME)],
        env=dict(os.environ,
                 GODOT_SILENCE_ROOT_WARNING="1",
                 WORLD_ROLE="client",
                 WORLD_SERVER_URL=f"ws://127.0.0.1:{port}/ws",
                 WORLD_ROOM="no-such-game",
                 WORLD_SELFCHECK="26"),
        capture_output=True, text=True, timeout=180)
    back = _last_selfcheck(gone.stdout + gone.stderr)
    checks.that(back.get("screen") == "lobby",
                "a finished game puts the player back on the lobby")
    # The one press the whole first screen is built around. Nothing else
    # can see this: focus is not drawn in any log, only in a stylebox a
    # person has to notice, and when it lands on the wrong control the
    # front page still looks perfect. It has gone wrong twice — once on a
    # node that was not in the tree yet, once on a button inside a hidden
    # panel, which would have joined a game with no code.
    # The front page's one primary button holds focus, so Space or A does
    # the obvious thing without anybody reading a word. It reads "Start a
    # game" now — there were two buttons, and the other one dropped you
    # into a world nothing on the screen had described.
    #
    # Matched on the button's TEXT (see SelfCheck._focused), spaces as
    # underscores, and it still fails on every other control the screen
    # has: Join, Back, Create and play, Start playing.
    checks.that(back.get("focus", "") == "Start_a_game",
                "the front page's main button holds focus, so Space and A "
                f"work (focus={back.get('focus')})")
    checks.that(back.get("room") == "-",
                f"leaving a game forgets its code (room={back.get('room')})")

    print(f"  waiting {IDLE_EXIT + 20}s for the empty games to close...")
    time.sleep(IDLE_EXIT + 20)
    _, listing = api(base, "/api/rooms")
    codes = [r["code"] for r in listing.get("rooms", [])]
    checks.that(public_room["code"] not in codes,
                "an empty game closes itself")
    _, health = api(base, "/healthz")
    checks.that(health.get("rooms") == 1,
                f"only the always-on game is left ({health.get('rooms')} running)")

    print()
    if checks.failures:
        print(f"{len(checks.failures)} checks failed, {checks.passed} passed")
        print("\n--- lobby log ---")
        print(log_path.read_text()[-4000:])
        return 1
    print(f"lobby test: {checks.passed} checks passed")
    return 0


def _last_selfcheck(log: str) -> dict[str, str]:
    for line in reversed(log.splitlines()):
        if line.startswith("SELFCHECK "):
            return dict(
                part.partition("=")[::2] for part in line.split()[1:] if "=" in part
            )
    return {}


if __name__ == "__main__":
    sys.exit(run())

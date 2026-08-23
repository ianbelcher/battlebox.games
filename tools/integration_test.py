#!/usr/bin/env python3
"""Run a real server and a real client against each other, and check that
the world actually arrived.

    tools/integration_test.py [--godot godot] [--seconds 18]

Why this exists: booting the project proves the scripts compile, and
`--export-release` will happily ship a build that serves pages, answers a
websocket and does nothing at all.  The failure mode that matters here is
an RPC addressed to a node path that no longer exists — Godot does not
raise on that, the call simply lands nowhere, and every other check in the
pipeline stays green while the world stays empty.

So this asserts on STATE, not on the absence of errors: the server has
chunks and critters and a roster, and the client has received them.  It is
the check that has to pass before any refactor of the world node is
believed.
"""

from __future__ import annotations

import argparse
import os
import re
import socket
import subprocess
import tempfile
import sys
import time
from pathlib import Path

# In the repo these are ../game and ../lobby. In the Docker build the
# tools live at /tools and the project at /game, which the same arithmetic
# happens to give — but say so, and let it be overridden, rather than
# leaving a build depending on a coincidence.
REPO = Path(__file__).resolve().parent.parent
GAME = Path(os.environ.get("BATTLEBOX_GAME", REPO / "game"))

SELFCHECK = re.compile(r"^SELFCHECK (.*)$", re.MULTILINE)
# Errors that mean the build is broken, as opposed to the ones a headless
# run always produces because it has no rendering device or audio output.
FATAL = re.compile(
    r"SCRIPT ERROR|Parse Error|Compile Error|Failed to load script", re.IGNORECASE
)


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _await_listening(server: subprocess.Popen, log_path: Path, port: int) -> None:
    """Block until the server says it is listening, so the client is not
    dialling a socket that is not there yet."""
    deadline = time.time() + 60
    while time.time() < deadline:
        if server.poll() is not None:
            raise AssertionError(
                f"the server exited with {server.returncode} before listening:\n"
                + log_path.read_text()
            )
        if "listening on" in log_path.read_text():
            return
        time.sleep(0.25)
    raise AssertionError(f"the server never listened on port {port}")


def parse_report(log: str, role: str, while_connected: bool = False) -> dict[str, str]:
    """The SELFCHECK line to judge a process on, as a dict.

    For the server that is the LAST one printed while a client was still
    connected: it reports on a repeating tick, and the reports after the
    client leaves are all truthfully empty.
    """
    reports = []
    for line in SELFCHECK.findall(log):
        fields = {}
        for pair in line.split():
            key, _, value = pair.partition("=")
            fields[key] = value
        reports.append(fields)
    if not reports:
        raise AssertionError(f"the {role} never reported (no SELFCHECK line)")
    if while_connected:
        connected = [r for r in reports if int(r.get("peers", 0)) >= 1]
        if not connected:
            raise AssertionError(
                f"the {role} never saw a peer connect "
                f"(its {len(reports)} reports all had peers=0)"
            )
        return connected[-1]
    return reports[-1]


class Checks:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passed = 0

    def at_least(self, report: dict[str, str], key: str, minimum: int, role: str) -> None:
        raw = report.get(key)
        if raw is None:
            self.failures.append(f"{role}: no '{key}' in the report")
            return
        actual = int(raw)
        if actual < minimum:
            self.failures.append(
                f"{role}: {key}={actual}, expected at least {minimum}"
            )
        else:
            self.passed += 1
            print(f"  ok  {role} {key}={actual} (>= {minimum})")

    def truth(self, held: bool, what: str) -> None:
        """A plain claim, for the checks that are not a number in a report."""
        if held:
            self.passed += 1
            print(f"  ok  {what}")
        else:
            self.failures.append(what)

    def equal(self, report: dict[str, str], key: str, expected: str, role: str) -> None:
        actual = report.get(key)
        if actual != expected:
            self.failures.append(f"{role}: {key}={actual}, expected {expected}")
        else:
            self.passed += 1
            print(f"  ok  {role} {key}={actual}")

    def check_in(self, report: dict[str, str], key: str, allowed: list[str], role: str) -> None:
        actual = report.get(key)
        if actual not in allowed:
            self.failures.append(
                f"{role}: {key}={actual}, expected one of {allowed}"
            )
        else:
            self.passed += 1
            print(f"  ok  {role} {key}={actual}")

    def no_fatal_errors(self, log: str, role: str) -> None:
        hits = [line for line in log.splitlines() if FATAL.search(line)]
        if hits:
            self.failures.append(
                f"{role}: {len(hits)} script errors, first is: {hits[0].strip()}"
            )
        else:
            self.passed += 1
            print(f"  ok  {role} compiled and ran clean")


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    parser.add_argument(
        "--seconds",
        type=int,
        default=18,
        help="how long the client plays before reporting",
    )
    parser.add_argument(
        "--mode",
        default="creative",
        choices=["creative", "battle", "ctf"],
        help="which game mode to play; battle and ctf start a round",
    )
    args = parser.parse_args(argv)

    port = free_port()
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    # The client reports once and quits. The server reports every few
    # seconds and stays up until we stop it, because what is worth
    # measuring about a server is its state WHILE somebody is connected —
    # and a server that outlived the client would report an empty world,
    # while one that died first would leave the client reporting an empty
    # one. Neither would be a bug.
    server_env = dict(
        env,
        WORLD_PORT=str(port),
        WORLD_SELFCHECK="3",
        WORLD_SELFCHECK_REPEAT="1",
    )
    client_env = dict(
        env,
        WORLD_ROLE="client",
        WORLD_AUTOCONNECT=f"ws://127.0.0.1:{port}",
        WORLD_AUTOTEST="2",
        # Ask the server for computer players too, so the run exercises
        # the server-side bot director and not only the client's own bots.
        WORLD_AUTOTEST_SERVER_BOTS="3",
        WORLD_SELFCHECK=str(args.seconds),
    )
    if args.mode != "creative":
        client_env["WORLD_AUTOTEST_MODE"] = args.mode
        client_env["WORLD_AUTOTEST_MATCH"] = "1"
    base = [args.godot, "--headless", "--path", str(GAME)]

    print(
        f"integration: {args.mode} on port {port}, "
        f"client reports after {args.seconds}s"
    )
    # To a file, not a pipe: the server outlives the client, and a full
    # pipe buffer with nobody draining it would wedge it.
    client_log = ""
    with tempfile.TemporaryDirectory() as scratch:
        server_out = Path(scratch) / "server.log"
        with server_out.open("w") as sink:
            server = subprocess.Popen(
                base, env=server_env, stdout=sink, stderr=subprocess.STDOUT, text=True
            )
            try:
                _await_listening(server, server_out, port)
                client = subprocess.run(
                    base,
                    env=client_env,
                    capture_output=True,
                    text=True,
                    timeout=max(30, args.seconds + 45),
                )
                client_log = client.stdout + client.stderr
                # A SECOND CLIENT, on the same live world, for the one
                # thing the first cannot report on: whether standing on a
                # boat actually carries you. See game/tests/boat_probe.gd
                # — it puts a player on a deck and moves the deck.
                boat_env = dict(client_env)
                boat_env.pop("WORLD_SELFCHECK", None)
                boat_env["WORLD_BOAT_TEST"] = "1"
                boat_env["WORLD_AUTOTEST"] = "1"
                boat = subprocess.run(base, env=boat_env, capture_output=True,
                                      text=True, timeout=120)
                boat_log = boat.stdout + boat.stderr
            except subprocess.TimeoutExpired as expired:
                boat_log = ""
                print("the client did not report in time; killing both")
                client_log = (expired.stdout or b"").decode("utf-8", "replace") + \
                    (expired.stderr or b"").decode("utf-8", "replace")
            finally:
                if server.poll() is None:
                    server.kill()
                    server.wait()
        server_log = server_out.read_text()

    checks = Checks()
    checks.no_fatal_errors(server_log, "server")
    checks.no_fatal_errors(client_log, "client")

    try:
        server_report = parse_report(server_log, "server", while_connected=True)
        client_report = parse_report(client_log, "client")
    except AssertionError as problem:
        print(f"\nFAILED: {problem}")
        print("\n--- server log (tail) ---")
        print("\n".join(server_log.splitlines()[-25:]))
        print("\n--- client log (tail) ---")
        print("\n".join(client_log.splitlines()[-25:]))
        return 1

    # The server built a world and is serving it to somebody.
    checks.equal(server_report, "role", "server", "server")
    checks.at_least(server_report, "peers", 1, "server")
    checks.at_least(server_report, "chunks", 60, "server")
    checks.at_least(server_report, "critters", 1, "server")
    checks.at_least(server_report, "edits", 1, "server")
    checks.at_least(server_report, "bots", 3, "server")
    # Three server bots plus the client's two local players.
    checks.at_least(server_report, "roster", 5, "server")

    # And the client received it. `avatars` is the one that catches a
    # broken roster broadcast; `chunks` catches broken chunk streaming.
    checks.equal(client_report, "role", "client", "client")
    checks.at_least(client_report, "roster", 5, "client")
    checks.at_least(client_report, "chunks", 60, "client")
    checks.at_least(client_report, "critters", 1, "client")
    checks.at_least(client_report, "avatars", 5, "client")
    # The two local seats each built a whole PlayerHud — every panel, the
    # hotbar, the radar and every menu page. This is what makes an
    # interface refactor visible to a headless run at all: without it, a
    # HUD that silently stopped building would not fail anything here.
    checks.at_least(client_report, "huds", 2, "client")
    # BOATS AND CARS, on both sides. The server puts a few out when the
    # world is made; the client has to have been told about them, because
    # its copy is also what a player's feet stand on. A fleet the server
    # has and nobody can see is a bug that errors nowhere: the world is
    # right, the picture of it is empty, and you swim past a boat that is
    # not drawn.
    checks.at_least(server_report, "vehicles", 4, "server")
    checks.at_least(client_report, "vehicles", 4, "client")
    # And riding one works. The probe prints its own lines; this turns
    # them into a single check so a failure fails the run.
    for line in boat_log.splitlines():
        if line.startswith("BOAT: ") and " probe armed" not in line:
            print("  " + line)
    checks.truth("BOAT: all checks passed" in boat_log,
                 "riding a boat works (see game/tests/boat_probe.gd)")

    # A round has to have actually started, and people have to be in it.
    # Without this the battle code — a third of what the server does — is
    # never executed by any check in the pipeline.
    if args.mode != "creative":
        checks.equal(server_report, "mode", args.mode, "server")
        checks.equal(client_report, "mode", args.mode, "client")
        # Every phase a started round can be sampled in. Not IDLE: that is
        # the phase a round that never started is in, which is the failure
        # this check exists to catch.
        checks.check_in(
            server_report, "phase", ["LOBBY", "SETUP", "BATTLE", "END"], "server"
        )
        checks.at_least(server_report, "alive", 2, "server")

    print()
    if checks.failures:
        for failure in checks.failures:
            print(f"FAILED: {failure}")
        print(f"\n{len(checks.failures)} checks failed, {checks.passed} passed")
        print("\n--- server report ---")
        print(server_report)
        print("--- client report ---")
        print(client_report)
        return 1

    print(f"integration: {checks.passed} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(run())

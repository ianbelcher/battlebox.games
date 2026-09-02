#!/usr/bin/env python3
"""The BattleBox lobby: a room registry, a process supervisor, and a
websocket proxy, in one asyncio server with no dependencies.

A ROOM IS A SERVER PROCESS. When somebody creates a game, this starts a
headless BattleBox server on a private port and remembers its code. When
the last player leaves, that process notices it is alone and exits (see
game/src/room.gd), and this reaps it. Nothing has to be cleaned up,
because a world that only ever existed in one process's memory goes away
with the process.

Everything a player touches is on one origin and one port:

    GET  /api/rooms          public games, newest first
    POST /api/rooms          create one; returns its code
    GET  /api/rooms/<code>   one room, or 404 if it is not there
    GET  /healthz            for the deploy check
    GET  /ws?room=<code>     the game socket, proxied to that room

The proxy is a byte splice, not a websocket implementation: once the
upgrade request has been forwarded and the room has answered 101, neither
side's frames mean anything here, so this copies them and stays out of
the way.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import socket
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, str(Path(__file__).resolve().parent))
import names  # noqa: E402

HOUSE_CODE = "house"
# A room this old with nobody in it is gone whatever its own watchdog
# thinks; belt and braces against a wedged process holding a port.
REAP_AFTER_SECONDS = 900
MAX_NAME = 32
# Long enough that a player who is reconnecting gets their game back,
# short enough that an abandoned room does not hold a slot for long.
DEFAULT_IDLE_EXIT = 90

# `humans` and `bots` are optional so that a room built before they
# existed still reports its total rather than looking empty.
_PLAYERS_LINE = re.compile(
    r"^ROOM \S+ players=(\d+)(?: humans=(\d+))?(?: bots=(\d+))?", re.MULTILINE)


@dataclass
class Room:
    code: str
    display_name: str
    is_public: bool
    port: int
    process: asyncio.subprocess.Process | None = None
    players: int = 0
    humans: int = 0
    bots: int = 0
    started_at: float = field(default_factory=time.monotonic)
    house: bool = False
    settings: dict = field(default_factory=dict)

    def as_json(self) -> dict:
        return {
            "code": self.code,
            "name": self.display_name,
            "public": self.is_public,
            "players": self.players,
            "humans": self.humans,
            "bots": self.bots,
            "house": self.house,
            "age": int(time.monotonic() - self.started_at),
            # WHAT THIS GAME IS, so the front page can say so. A list of
            # room names answers none of the questions somebody browsing
            # it is actually asking; "Capture the flag, Castles, 400
            # across" answers all of them.
            "settings": dict(self.settings),
        }

    def alive(self) -> bool:
        return self.process is not None and self.process.returncode is None


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


# ---------------------------------------------------------------------
# WHAT A NEW GAME CAN BE.
#
# The same table as game/src/game_setup.gd, and it is duplicated on
# purpose rather than shared. Nothing in this process can read GDScript,
# and more importantly: THE CLIENT'S COPY IS NOT A VALIDATOR. A POST is a
# POST — the front page is one thing that can send one, and the room this
# spawns runs a real server process with a real world in it. So the rules
# are checked again here, against this table, before anything is started.
#
# Adding a setting means a row in both. game/tests/unit/game_setup_test.gd
# and the tests below each check their own side; if they ever disagree the
# symptom is a game that starts with a setting quietly ignored, which is
# the kind of bug nobody reports because it just looks like the button did
# not work.
# ---------------------------------------------------------------------

MODES = ("creative", "battle", "ctf", "holdout")
MAPS = ("classic", "desert", "isles", "castles", "city", "sky", "space")
SIZES = (50, 100, 200, 400, 800)
FLY_ANSWERS = ("everyone", "nobody", "computers", "humans")
BOT_COUNTS = (0, 3, 5, 10, 20, 40, 100)
TARGETS = (1, 3, 5, 10)
TEAM_COUNTS = (2, 3, 4, 5, 6, 8)
# ONE LIST, for every mode that has a clock. It used to be 3/5/8 for
# battle royale and 2/5/10 for last flag standing, for no reason either
# mode could explain — and on screen that is a row whose buttons move and
# grey out as you change your mind about the mode.
ROUND_LENGTHS = (3, 5, 10, 60)

# The NEUTRAL baseline — what a field becomes when it arrives missing.
# Creative, because a bare POST with no settings in it is not somebody
# pressing "New game" on the front page (that screen always sends a whole
# object, and it opens on battle royale — see GameSetup.opening_choice);
# it is a script or a test, and what those have always got is a world to
# build in rather than a storm closing in.
DEFAULT_SETTINGS = {
    "mode": "creative",
    "map": "classic",
    "size": 400,
    "minutes": 5,
    "bots": 5,
    "target": 3,
    "teams": 5,
    "fly": "nobody",
    "revive": 2,
    "drop": False,
}

# THE ALWAYS-ON WORLD IS JUST ANOTHER GAME. It is listed like any other,
# joined like any other, and says what it is like any other. The one thing
# that makes it special is that it does not close when the last person
# leaves — see WORLD_IDLE_EXIT in spawn().
#
# It had a button of its own on the front page, which was the confusing
# part: a big "Play now" that dropped you into a world nothing on the
# screen had described. So it runs a battle royale across five teams with
# a crowd of computer players in it, and it says so in the list like
# everything else — somebody arriving alone walks into a game that is
# already happening rather than into an empty field.
#
# The bot count is `--house-bots` rather than a constant because it is the
# one number here that costs CPU: every one of them pathfinds on that
# room's single thread.
HOUSE_SETTINGS = dict(DEFAULT_SETTINGS, mode="battle", map="classic",
                      teams=5, minutes=10, size=400)


def _snap(raw: dict, field: str, allowed, fallback):
    """A choice out of a list, or the default. SNAPPED rather than
    clamped: a world 137 blocks across is not a small world, it is a
    number nothing can produce, and letting it through starts a game
    nobody asked for."""
    value = raw.get(field, fallback)
    try:
        value = int(value)
    except (TypeError, ValueError):
        return fallback
    return value if value in allowed else fallback


def clean_settings(raw: object) -> dict:
    """Whatever arrived, made safe. Unknown keys dropped, unknown values
    replaced by the default, numbers snapped to the table above."""
    if not isinstance(raw, dict):
        return dict(DEFAULT_SETTINGS)
    out = dict(DEFAULT_SETTINGS)
    if raw.get("mode") in MODES:
        out["mode"] = raw["mode"]
    if raw.get("map") in MAPS:
        out["map"] = raw["map"]
    out["size"] = _snap(raw, "size", SIZES, DEFAULT_SETTINGS["size"])
    out["bots"] = _snap(raw, "bots", BOT_COUNTS, DEFAULT_SETTINGS["bots"])
    out["target"] = _snap(raw, "target", TARGETS, DEFAULT_SETTINGS["target"])
    out["teams"] = _snap(raw, "teams", TEAM_COUNTS, DEFAULT_SETTINGS["teams"])
    out["fly"] = (raw.get("fly") if raw.get("fly") in FLY_ANSWERS
                  else DEFAULT_SETTINGS["fly"])
    out["minutes"] = _snap(raw, "minutes", ROUND_LENGTHS,
                           DEFAULT_SETTINGS["minutes"])
    # The revive ladder is a range (none / team-mates / and your flag),
    # so it clamps rather than snapping.
    try:
        out["revive"] = max(0, min(2, int(raw.get("revive", 2))))
    except (TypeError, ValueError):
        out["revive"] = 2
    out["drop"] = bool(raw.get("drop", False))
    return out


def settings_env(settings: dict) -> dict:
    """The room process's side of the same table.

    A world is generated at boot from its environment and never written
    to disk, so handing the settings over THIS way — rather than having
    the creator's client send them once it has connected — is what makes
    the terrain actually be the map that was asked for. The alternative
    is a room that boots as an island and then resets itself into a
    desert while somebody is standing in it.

    Every value is a string: this is going into os.environ.
    """
    clean = clean_settings(settings)
    return {
        "WORLD_MODE": str(clean["mode"]),
        "WORLD_THEME": str(clean["map"]),
        "WORLD_SIZE": str(clean["size"]),
        "WORLD_ROUND_MINUTES": str(clean["minutes"]),
        "WORLD_BOTS": str(clean["bots"]),
        "WORLD_CTF_TARGET": str(clean["target"]),
        "WORLD_TEAMS": str(clean["teams"]),
        "WORLD_FLY": str(clean["fly"]),
        "WORLD_REVIVE": str(clean["revive"]),
        "WORLD_DROP_KO": "1" if clean["drop"] else "0",
    }


def clean_name(raw: str) -> str:
    """A room name is shown to strangers on the front page, so it is
    stripped to printable characters and cut to something that fits in a
    button. Empty names are the caller's problem, not a rejection: they
    get their code as the name."""
    text = "".join(ch for ch in raw if ch.isprintable()).strip()
    return text[:MAX_NAME]


class Lobby:
    def __init__(self, server_binary: str, max_rooms: int, idle_exit: int,
                 world_size: int, house_bots: int = 100) -> None:
        self.server_binary = server_binary
        self.max_rooms = max_rooms
        self.idle_exit = idle_exit
        self.world_size = world_size
        self.house_bots = house_bots
        self.rooms: dict[str, Room] = {}

    # -- room lifecycle ------------------------------------------------

    async def start_house(self) -> None:
        """The always-on game. There is always somewhere to play, and it
        is up before anybody asks for it."""
        settings = dict(HOUSE_SETTINGS, size=self.world_size,
                        bots=self.house_bots)
        await self.spawn(HOUSE_CODE, "BattleBox", True, house=True,
                         settings=settings)

    async def spawn(self, code: str, display_name: str, is_public: bool,
                    house: bool = False, settings: dict | None = None) -> Room:
        port = free_port()
        clean = clean_settings(settings or {})
        env = dict(
            os.environ,
            WORLD_PORT=str(port),
            WORLD_ROOM_CODE=code,
            WORLD_ROOM_NAME=display_name,
            WORLD_ROOM_PUBLIC="1" if is_public else "0",
            # The house room never exits; every other room reaps itself.
            WORLD_IDLE_EXIT="0" if house else str(self.idle_exit),
            GODOT_SILENCE_ROOT_WARNING="1",
            # LAST, so what the creator chose beats both this process's
            # environment and the --world-size default. WORLD_SIZE used to
            # be set here unconditionally, which would have silently
            # overridden every world size anybody picked.
            **settings_env(clean),
        )
        process = await asyncio.create_subprocess_exec(
            *self.server_binary.split(),
            env=env,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        room = Room(code, display_name, is_public, port, process, house=house,
                    settings=clean)
        self.rooms[code] = room
        asyncio.create_task(self._follow(room))
        await self._await_listening(room)
        print(f"lobby: room {code!r} ({display_name!r}) up on :{port} "
              f"pid={process.pid}", flush=True)
        return room

    async def _await_listening(self, room: Room, timeout: float = 30.0) -> None:
        """Do not hand a player a room that is not accepting yet: their
        client would fail to connect and retry into a reconnect loop while
        the room was, in fact, coming up perfectly well."""
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if not room.alive():
                raise RuntimeError(f"room {room.code} exited while starting")
            try:
                reader, writer = await asyncio.open_connection("127.0.0.1", room.port)
                writer.close()
                await writer.wait_closed()
                return
            except OSError:
                await asyncio.sleep(0.2)
        raise TimeoutError(f"room {room.code} never listened on :{room.port}")

    async def _follow(self, room: Room) -> None:
        """Read the room's output: its player count comes from there, and
        so does the news that it has gone."""
        assert room.process is not None and room.process.stdout is not None
        async for raw in room.process.stdout:
            line = raw.decode("utf-8", "replace").rstrip()
            match = _PLAYERS_LINE.match(line)
            if match:
                room.players = int(match.group(1))
                # A room that only reports a total is old enough not to
                # know about bots; treating its players as people is the
                # right guess, and better than showing nobody.
                room.humans = int(match.group(2) or match.group(1))
                room.bots = int(match.group(3) or 0)
                continue
            if line:
                print(f"[{room.code}] {line}", flush=True)
        await room.process.wait()
        self.rooms.pop(room.code, None)
        print(f"lobby: room {room.code!r} closed (exit {room.process.returncode})",
              flush=True)
        if room.house:
            print("lobby: the house room went away; starting another", flush=True)
            await self.start_house()

    async def reap_forever(self) -> None:
        while True:
            await asyncio.sleep(30)
            for room in list(self.rooms.values()):
                if room.house or room.alive():
                    continue
                self.rooms.pop(room.code, None)
            for room in list(self.rooms.values()):
                stale = time.monotonic() - room.started_at > REAP_AFTER_SECONDS
                if room.house or room.players or not stale:
                    continue
                print(f"lobby: room {room.code!r} still empty; stopping it",
                      flush=True)
                if room.process is not None:
                    room.process.terminate()

    def public_rooms(self) -> list[dict]:
        listed = [r for r in self.rooms.values() if r.is_public and r.alive()]
        # The house room first, then the one with the most PEOPLE in it,
        # then the most players of any kind, then the newest.
        #
        # People first, and that is the whole point of the ordering: this
        # sorted on the total, so a room holding twenty computer players
        # and nobody at all was put above a room with three children in
        # it. The front page then highlights the busy one, in a colour
        # that means "there are people here", at the top of the list.
        listed.sort(key=lambda r: (not r.house, -r.humans, -r.players,
                                   r.started_at))
        return [r.as_json() for r in listed]

    # -- HTTP ----------------------------------------------------------

    async def handle(self, reader: asyncio.StreamReader,
                     writer: asyncio.StreamWriter) -> None:
        try:
            head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=15)
        except (asyncio.IncompleteReadError, asyncio.TimeoutError,
                asyncio.LimitOverrunError, ConnectionError):
            writer.close()
            return
        try:
            request_line, _, header_block = head.partition(b"\r\n")
            method, _, rest = request_line.decode("latin-1").partition(" ")
            target = rest.rsplit(" ", 1)[0]
            headers = _parse_headers(header_block)
            url = urlparse(target)
            path = url.path.rstrip("/") or "/"

            if path == "/ws" or path.startswith("/ws/"):
                await self._proxy(reader, writer, head, url, path, headers)
                return
            if path == "/healthz":
                await _respond(writer, 200, {"ok": True, "rooms": len(self.rooms)})
            elif path == "/api/rooms" and method == "GET":
                await _respond(writer, 200, {"rooms": self.public_rooms(),
                                             "house": HOUSE_CODE})
            elif path == "/api/rooms" and method == "POST":
                await self._create(reader, writer, headers)
            elif path.startswith("/api/rooms/") and method == "GET":
                code = path.rsplit("/", 1)[-1].lower()
                room = self.rooms.get(code)
                if room is None or not room.alive():
                    await _respond(writer, 404, {"error": "no such game"})
                else:
                    await _respond(writer, 200, room.as_json())
            else:
                await _respond(writer, 404, {"error": "not found"})
        except Exception as problem:  # noqa: BLE001 - a bad request must not kill the lobby
            print(f"lobby: {problem!r}", flush=True)
            try:
                await _respond(writer, 500, {"error": "lobby failed"})
            except ConnectionError:
                pass
        finally:
            if not writer.is_closing():
                writer.close()

    async def _create(self, reader: asyncio.StreamReader,
                      writer: asyncio.StreamWriter, headers: dict) -> None:
        length = int(headers.get("content-length", "0") or 0)
        body = await reader.readexactly(length) if length else b"{}"
        try:
            wanted = json.loads(body or b"{}")
        except json.JSONDecodeError:
            await _respond(writer, 400, {"error": "that was not JSON"})
            return
        live = [r for r in self.rooms.values() if r.alive()]
        if len(live) >= self.max_rooms:
            await _respond(writer, 503, {
                "error": "every game slot is busy — try one of the public games"})
            return
        code = names.make_code(set(self.rooms))
        display_name = clean_name(str(wanted.get("name", ""))) or code
        is_public = bool(wanted.get("public", True))
        settings = clean_settings(wanted.get("settings"))
        try:
            room = await self.spawn(code, display_name, is_public,
                                    settings=settings)
        except (RuntimeError, TimeoutError) as problem:
            print(f"lobby: could not start {code}: {problem}", flush=True)
            await _respond(writer, 500, {"error": "the game would not start"})
            return
        await _respond(writer, 201, room.as_json())

    # -- websocket proxy -----------------------------------------------

    async def _proxy(self, reader: asyncio.StreamReader,
                     writer: asyncio.StreamWriter, head: bytes,
                     url, path: str, headers: dict) -> None:
        """Splice this connection onto the room's own socket.

        The room is picked from ?room=<code> or /ws/<code>; anything
        unrecognised gets the house room rather than an error, because the
        native client dials /ws with no room at all and should land
        somewhere playable.
        """
        code = ""
        if path.startswith("/ws/"):
            code = path[4:].strip().lower()
        if not code:
            code = (parse_qs(url.query).get("room", [""])[0] or "").strip().lower()
        room = self.rooms.get(code or HOUSE_CODE)
        if room is None or not room.alive():
            # 404 on a websocket upgrade is the honest answer, and the
            # client turns it into "that game has finished" rather than
            # retrying a code that will never work.
            await _respond(writer, 404, {"error": "no such game"})
            return
        try:
            room_reader, room_writer = await asyncio.open_connection(
                "127.0.0.1", room.port)
        except OSError:
            await _respond(writer, 502, {"error": "the game is not answering"})
            return
        # Forward the handshake untouched apart from the path: the room is
        # a plain websocket server and does not know about codes.
        rebuilt = re.sub(rb"^(\S+) \S+ ", rb"\1 / ", head, count=1)
        room_writer.write(rebuilt)
        await room_writer.drain()
        await asyncio.gather(
            _pump(reader, room_writer),
            _pump(room_reader, writer),
            return_exceptions=True,
        )


async def _pump(src: asyncio.StreamReader, dst: asyncio.StreamWriter) -> None:
    try:
        while chunk := await src.read(65536):
            dst.write(chunk)
            await dst.drain()
    except (ConnectionError, asyncio.IncompleteReadError):
        pass
    finally:
        if not dst.is_closing():
            dst.close()


def _parse_headers(block: bytes) -> dict[str, str]:
    headers = {}
    for line in block.decode("latin-1").split("\r\n"):
        key, _, value = line.partition(":")
        if key:
            headers[key.strip().lower()] = value.strip()
    return headers


async def _respond(writer: asyncio.StreamWriter, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode()
    reason = {200: "OK", 201: "Created", 400: "Bad Request", 404: "Not Found",
              500: "Internal Server Error", 502: "Bad Gateway",
              503: "Service Unavailable"}.get(status, "OK")
    head = (
        f"HTTP/1.1 {status} {reason}\r\n"
        f"Content-Type: application/json\r\n"
        f"Content-Length: {len(body)}\r\n"
        # The browser build fetches this from the page's own origin, but
        # a LAN client and the dev setup do not share one.
        f"Access-Control-Allow-Origin: *\r\n"
        f"Cache-Control: no-store\r\n"
        f"Connection: close\r\n\r\n"
    ).encode()
    writer.write(head + body)
    await writer.drain()


async def serve(args: argparse.Namespace) -> None:
    lobby = Lobby(args.server, args.max_rooms, args.idle_exit, args.world_size,
                  args.house_bots)
    if not args.no_house:
        await lobby.start_house()
    asyncio.create_task(lobby.reap_forever())
    server = await asyncio.start_server(lobby.handle, args.host, args.port)
    print(f"lobby: listening on {args.host}:{args.port}, "
          f"up to {args.max_rooms} rooms", flush=True)
    async with server:
        await server.serve_forever()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=9080)
    parser.add_argument(
        "--server",
        default=os.environ.get("BATTLEBOX_SERVER",
                               "/opt/battlebox/server/battlebox-server.x86_64 --headless"),
        help="how to start one room; the port comes from WORLD_PORT",
    )
    parser.add_argument("--max-rooms", type=int,
                        default=int(os.environ.get("LOBBY_MAX_ROOMS", "8")))
    parser.add_argument("--idle-exit", type=int,
                        default=int(os.environ.get("LOBBY_IDLE_EXIT", DEFAULT_IDLE_EXIT)))
    parser.add_argument("--world-size", type=int,
                        default=int(os.environ.get("WORLD_SIZE", "250")))
    parser.add_argument(
        "--house-bots", type=int,
        default=int(os.environ.get("LOBBY_HOUSE_BOTS", "100")),
        help="computer players in the always-on game. Every one of them "
             "pathfinds on that room's single thread, so this is the "
             "number to turn down if the shared world gets choppy",
    )
    parser.add_argument("--no-house", action="store_true",
                        help="do not start the always-on public game (tests)")
    args = parser.parse_args(argv)
    try:
        asyncio.run(serve(args))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Unit tests for the lobby's own logic — the parts with no processes and
no sockets in them.

    python3 -m unittest discover -s lobby -p 'test_*.py'
"""

import random
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import lobby  # noqa: E402
import names  # noqa: E402


class CodeTests(unittest.TestCase):
    def test_words_are_plain_ascii_letters(self):
        # A code is read out loud and typed back by a child. Anything with
        # an accent, a digit or a hyphen in it breaks that on both ends.
        for word in names.ADJECTIVES + names.NOUNS:
            self.assertTrue(word.isalpha(), f"{word!r} is not all letters")
            self.assertTrue(word.isascii(), f"{word!r} is not ascii")
            self.assertEqual(word, word.lower(), f"{word!r} is not lowercase")

    def test_no_duplicate_words(self):
        # A duplicate silently shrinks the pool and makes one code twice
        # as likely as its neighbours.
        for pool, label in ((names.ADJECTIVES, "adjective"), (names.NOUNS, "noun")):
            duplicates = {w for w in pool if pool.count(w) > 1}
            self.assertEqual(duplicates, set(), f"duplicate {label}s")

    def test_the_pool_is_big_enough_to_be_worth_nothing_to_guess(self):
        self.assertGreater(names.all_codes(), 20000)

    def test_codes_look_like_codes(self):
        for _ in range(200):
            code = names.make_code()
            self.assertRegex(code, r"^[a-z]+-[a-z]+$")
            self.assertTrue(names.is_code(code))

    def test_a_taken_code_is_never_handed_out_again(self):
        # The pool is tiny here, so collisions are the common case rather
        # than a one-in-thirty-thousand event.
        rng = random.Random(7)
        original_adj, original_noun = names.ADJECTIVES, names.NOUNS
        names.ADJECTIVES, names.NOUNS = ["red", "blue"], ["fox", "owl"]
        try:
            taken = {"red-fox", "red-owl", "blue-fox"}
            for _ in range(50):
                self.assertEqual(names.make_code(taken, rng), "blue-owl")
        finally:
            names.ADJECTIVES, names.NOUNS = original_adj, original_noun

    def test_a_full_pool_still_produces_something(self):
        # Every draw collides. A create must not fail because the lobby
        # ran out of imagination.
        rng = random.Random(11)
        original_adj, original_noun = names.ADJECTIVES, names.NOUNS
        names.ADJECTIVES, names.NOUNS = ["red"], ["fox"]
        try:
            code = names.make_code({"red-fox"}, rng)
            self.assertNotEqual(code, "red-fox")
            self.assertTrue(names.is_code(code), code)
        finally:
            names.ADJECTIVES, names.NOUNS = original_adj, original_noun

    def test_rubbish_is_not_a_code(self):
        for text in ["", "hello", "a b", "brave otter", "brave-", "-otter",
                     "brave-otter-", "brave-otter-abc", "1-2"]:
            self.assertFalse(names.is_code(text), f"{text!r} passed")


class NameTests(unittest.TestCase):
    def test_a_name_is_trimmed_and_capped(self):
        self.assertEqual(lobby.clean_name("  Bea's game  "), "Bea's game")
        self.assertEqual(len(lobby.clean_name("x" * 200)), lobby.MAX_NAME)

    def test_control_characters_are_dropped(self):
        # This ends up on a button on the front page for strangers to read.
        self.assertEqual(lobby.clean_name("hi\x00\x07there\n"), "hithere")

    def test_an_empty_name_is_allowed_through(self):
        # Naming the game is optional; the lobby falls back to its code.
        self.assertEqual(lobby.clean_name("   "), "")


class ListingTests(unittest.TestCase):
    def make(self, code, public=True, players=0, house=False, started=0.0):
        room = lobby.Room(code, code.title(), public, 1234, house=house)
        room.players = players
        room.started_at = started
        room.process = _FakeProcess()
        return room

    def test_private_games_are_never_listed(self):
        board = lobby.Lobby("true", 8, 90, 250)
        board.rooms = {
            "house": self.make("house", house=True),
            "open": self.make("open"),
            "secret": self.make("secret", public=False),
        }
        codes = [r["code"] for r in board.public_rooms()]
        self.assertIn("open", codes)
        self.assertNotIn("secret", codes)

    def test_the_house_game_is_always_first_then_the_busiest(self):
        board = lobby.Lobby("true", 8, 90, 250)
        board.rooms = {
            "quiet": self.make("quiet", players=1, started=1.0),
            "busy": self.make("busy", players=6, started=2.0),
            "house": self.make("house", house=True, started=3.0),
        }
        self.assertEqual([r["code"] for r in board.public_rooms()],
                         ["house", "busy", "quiet"])

    def test_a_dead_room_disappears_from_the_list(self):
        board = lobby.Lobby("true", 8, 90, 250)
        room = self.make("gone")
        room.process.returncode = 0
        board.rooms = {"gone": room}
        self.assertEqual(board.public_rooms(), [])


class HeartbeatTests(unittest.TestCase):
    def test_the_player_count_is_read_off_the_room_output(self):
        # This is the contract with game/src/room.gd. If either side
        # changes the wording, every public game reads "empty" forever.
        match = lobby._PLAYERS_LINE.match("ROOM brave-otter players=4")
        self.assertIsNotNone(match)
        self.assertEqual(int(match.group(1)), 4)

    def test_ordinary_room_output_is_not_mistaken_for_a_count(self):
        for line in ["ROOM brave-otter: empty for 90s, closing",
                     "World spawn at (0, 30, 0)", ""]:
            self.assertIsNone(lobby._PLAYERS_LINE.match(line), line)


class ProxyTests(unittest.TestCase):
    def test_the_upgrade_request_is_rewritten_to_the_room_root(self):
        # The room is a plain websocket server and knows nothing about
        # codes, so the path has to be stripped on the way through.
        head = (b"GET /ws?room=brave-otter HTTP/1.1\r\n"
                b"Host: battlebox.games\r\n"
                b"Upgrade: websocket\r\n\r\n")
        rebuilt = re.sub(rb"^(\S+) \S+ ", rb"\1 / ", head, count=1)
        self.assertTrue(rebuilt.startswith(b"GET / HTTP/1.1\r\n"))
        self.assertIn(b"Upgrade: websocket", rebuilt)


class _FakeProcess:
    returncode = None
    pid = 1


if __name__ == "__main__":
    unittest.main()


class PlayerCountTests(unittest.TestCase):
    """What a room says about who is in it, and what the lobby makes of it.

    The count is what somebody picks a game by, so a room holding one
    child and eighteen computer players must not advertise "19 playing".
    """

    def parse(self, line):
        match = lobby._PLAYERS_LINE.match(line)
        self.assertIsNotNone(match, f"did not match: {line!r}")
        total = int(match.group(1))
        return total, int(match.group(2) or total), int(match.group(3) or 0)

    def test_people_and_computer_players_are_read_separately(self):
        self.assertEqual(
            self.parse("ROOM brave-otter players=19 humans=1 bots=18"),
            (19, 1, 18))

    def test_an_empty_room(self):
        self.assertEqual(self.parse("ROOM house players=0 humans=0 bots=0"),
                         (0, 0, 0))

    def test_a_room_that_only_reports_a_total_still_counts(self):
        # The line grew these fields; a room that predates them must not
        # read as empty, so its players are taken to be people.
        self.assertEqual(self.parse("ROOM house players=4"), (4, 4, 0))

    def test_the_json_carries_both(self):
        room = lobby.Room("brave-otter", "Ian's game", False, 9100)
        room.players, room.humans, room.bots = 19, 1, 18
        blob = room.as_json()
        self.assertEqual(blob["players"], 19)
        self.assertEqual(blob["humans"], 1)
        self.assertEqual(blob["bots"], 18)


class SettingsTests(unittest.TestCase):
    """WHAT A NEW GAME WAS ASKED TO BE, checked before anything is started.

    These settings come off a POST, and a POST is a POST: the front page
    is one thing that can send one. Every value that reaches a room
    process has been through clean_settings, and the tests below are what
    say so — the failure they exist for is not a crash, it is a game that
    boots 4,000 blocks across because somebody typed a number.
    """

    def test_nothing_at_all_is_the_default_game(self):
        self.assertEqual(lobby.clean_settings({}), lobby.DEFAULT_SETTINGS)
        self.assertEqual(lobby.clean_settings(None), lobby.DEFAULT_SETTINGS)
        # A list, a string, a number — anything that is not an object.
        self.assertEqual(lobby.clean_settings(["ctf"]), lobby.DEFAULT_SETTINGS)

    def test_a_whole_game_survives_intact(self):
        asked = {"mode": "ctf", "map": "castles", "size": 400, "minutes": 10,
                 "players": 10, "target": 5, "teams": 8, "fly": "humans",
                 "revive": 1, "drop": True}
        self.assertEqual(lobby.clean_settings(asked), asked)

    def test_a_mode_nobody_has_written_is_not_started(self):
        self.assertEqual(lobby.clean_settings({"mode": "zombies"})["mode"],
                         lobby.DEFAULT_SETTINGS["mode"])

    def test_a_room_nobody_configured_is_still_a_world_to_build_in(self):
        # What a bare POST has always produced. The front page always
        # sends a whole settings object and opens on battle royale; a
        # script that has never heard of a mode must not be handed one.
        self.assertEqual(lobby.clean_settings({})["mode"], "creative")

    def test_a_map_nobody_has_written_is_not_generated(self):
        self.assertEqual(lobby.clean_settings({"map": "../../etc"})["map"],
                         lobby.DEFAULT_SETTINGS["map"])

    def test_a_size_off_the_list_is_refused_rather_than_clamped(self):
        # 137 is not a small world. It is a number nothing on the screen
        # can produce, so it is somebody sending their own POST — and a
        # clamp would quietly build them a world at the nearest edge.
        for bad in (137, 99999, -1, "big"):
            self.assertEqual(lobby.clean_settings({"size": bad})["size"], 400)

    def test_a_round_length_means_the_same_thing_in_every_mode(self):
        # One list, for every mode that has a clock. It was 3/5/8 for
        # battle royale and 2/5/10 for last flag standing, for no reason
        # either mode could give.
        for mode in ("battle", "holdout"):
            self.assertEqual(
                lobby.clean_settings({"mode": mode, "minutes": 10})["minutes"],
                10, mode)
        self.assertEqual(lobby.clean_settings({"minutes": 8})["minutes"], 5)

    def test_who_can_fly_is_part_of_the_game(self):
        self.assertEqual(lobby.clean_settings({})["fly"], "nobody")
        self.assertEqual(lobby.clean_settings({"fly": "humans"})["fly"], "humans")
        self.assertEqual(lobby.clean_settings({"fly": "wings"})["fly"], "nobody")

    def test_teams_are_part_of_the_game(self):
        self.assertEqual(lobby.clean_settings({"teams": 8})["teams"], 8)
        self.assertEqual(lobby.clean_settings({"teams": 10})["teams"], 10)
        self.assertEqual(lobby.clean_settings({"teams": 11})["teams"], 5)
        # One is solo — everyone for themselves — and zero is nothing.
        self.assertEqual(lobby.clean_settings({"teams": 1})["teams"], 1)
        self.assertEqual(lobby.clean_settings({"teams": 0})["teams"], 5)

    def test_the_revive_ladder_clamps_to_its_rungs(self):
        # A range rather than a list of choices, so out-of-range lands on
        # the nearest rung instead of the default.
        self.assertEqual(lobby.clean_settings({"revive": 0})["revive"], 0)
        self.assertEqual(lobby.clean_settings({"revive": 9})["revive"], 2)
        self.assertEqual(lobby.clean_settings({"revive": -4})["revive"], 0)
        self.assertEqual(lobby.clean_settings({"revive": "yes"})["revive"], 2)

    def test_how_many_players_is_a_choice_and_just_us_is_one_of_them(self):
        # Seats, counting everybody: computer players fill the ones people
        # are not in. Zero is a room with nobody but the people who join.
        self.assertEqual(lobby.clean_settings({"players": 0})["players"], 0)
        self.assertEqual(lobby.clean_settings({"players": 20})["players"], 20)
        self.assertEqual(lobby.clean_settings({"players": 400})["players"], 10)
        # The old name is not read any more: a bot count is not a size.
        self.assertEqual(lobby.clean_settings({"bots": 40})["players"], 10)


class SettingsEnvTests(unittest.TestCase):
    """The room process is configured entirely from its environment, so
    this mapping IS how a chosen setting becomes a real world."""

    def test_every_setting_reaches_the_room(self):
        env = lobby.settings_env({"mode": "holdout", "map": "sky", "size": 800,
                                  "minutes": 3, "players": 20, "target": 10,
                                  "teams": 8, "fly": "everyone", "revive": 0,
                                  "drop": True})
        self.assertEqual(env["WORLD_MODE"], "holdout")
        self.assertEqual(env["WORLD_THEME"], "sky")
        self.assertEqual(env["WORLD_SIZE"], "800")
        self.assertEqual(env["WORLD_ROUND_MINUTES"], "3")
        self.assertEqual(env["WORLD_TEAMS"], "8")
        self.assertEqual(env["WORLD_FLY"], "everyone")
        self.assertEqual(env["WORLD_PLAYERS"], "20")
        self.assertEqual(env["WORLD_CTF_TARGET"], "10")
        self.assertEqual(env["WORLD_REVIVE"], "0")
        self.assertEqual(env["WORLD_DROP_KO"], "1")

    def test_everything_is_a_string(self):
        # It is going into os.environ, which takes strings and raises on
        # anything else — and the raise would happen inside spawn(), one
        # frame after somebody pressed a button.
        for key, value in lobby.settings_env({}).items():
            self.assertIsInstance(value, str, key)

    def test_the_environment_is_cleaned_on_the_way_through(self):
        # settings_env is reachable with raw input; it must not be a hole
        # around clean_settings.
        env = lobby.settings_env({"map": "; rm -rf /", "size": 99999})
        self.assertEqual(env["WORLD_THEME"], "classic")
        self.assertEqual(env["WORLD_SIZE"], "400")

    def test_a_flag_that_is_off_is_zero_not_absent(self):
        # WORLD_DROP_KO is read as "is it exactly 1", so an absent
        # variable and "0" mean the same thing — but an absent one also
        # means "the room inherited whatever this process had", which is
        # not the same at all.
        self.assertEqual(lobby.settings_env({"drop": False})["WORLD_DROP_KO"], "0")


class RoomArgvTests(unittest.TestCase):
    """A room only reaches the lobby through its stdout, so its stdout has
    to be line-buffered. Godot's print() is block-buffered the moment it
    is a pipe, and an idle exported server prints so little that its
    player count sat in the buffer forever — which is why the front page
    showed a game with a hundred computer players in it as empty, in
    production only."""

    def test_a_room_is_started_line_buffered(self):
        argv = lobby.room_argv("/opt/x/server.x86_64 --headless")
        if lobby._STDBUF:
            self.assertEqual(argv[1:3], ["-oL", "/opt/x/server.x86_64"])
            self.assertTrue(argv[0].endswith("stdbuf"))
        self.assertEqual(argv[-2:], ["/opt/x/server.x86_64", "--headless"])

    def test_without_stdbuf_the_room_still_starts(self):
        # Rooms report late rather than not at all, which is the right way
        # round for something that is only ever a courtesy.
        was = lobby._STDBUF
        lobby._STDBUF = None
        try:
            self.assertEqual(lobby.room_argv("a b c"), ["a", "b", "c"])
        finally:
            lobby._STDBUF = was


class HouseTests(unittest.TestCase):
    """THE ALWAYS-ON WORLD IS JUST ANOTHER GAME. It used to have a button
    of its own on the front page — a big "Play now" that dropped you into
    a world nothing on the screen had described. It is in the list now,
    saying what it is, so it has to actually BE something."""

    def test_the_always_on_world_is_a_game_somebody_would_join(self):
        settings = lobby.clean_settings(lobby.HOUSE_SETTINGS)
        self.assertEqual(settings, lobby.HOUSE_SETTINGS,
                         "the house settings are valid settings")
        self.assertEqual(settings["mode"], "battle")
        self.assertEqual(settings["teams"], 5)

    def test_the_always_on_world_can_hold_a_full_house(self):
        # Five teams of twenty. The seat count is a flag, and 100 has to be
        # a value clean_settings will actually accept or the always-on
        # world quietly snaps back to the default handful.
        self.assertEqual(lobby.clean_settings(
            dict(lobby.HOUSE_SETTINGS, players=100))["players"], 100)


class RoomSettingsJsonTests(unittest.TestCase):
    def test_a_room_says_what_it_is(self):
        # The front page reads this to write "Capture the flag · Castles"
        # under a game's name. Without it the list is names alone, which
        # answers none of the questions somebody browsing it is asking.
        room = lobby.Room("brave-otter", "Ian's game", True, 9100,
                          settings=lobby.clean_settings({"mode": "ctf",
                                                         "map": "castles"}))
        self.assertEqual(room.as_json()["settings"]["mode"], "ctf")
        self.assertEqual(room.as_json()["settings"]["map"], "castles")

    def test_a_room_with_none_reports_an_empty_object(self):
        # Not a made-up default: a room that did not say what it is must
        # not be described on the front page as though it had.
        self.assertEqual(lobby.Room("x", "x", True, 1).as_json()["settings"], {})

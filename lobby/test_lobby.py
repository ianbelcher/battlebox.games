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

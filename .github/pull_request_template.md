**What this changes, and why**

**Checks run** (see CONTRIBUTING.md)
- [ ] `godot --headless --path game --quit-after 240` — it compiles
- [ ] `godot --headless --path game --script res://tests/run_tests.gd`
- [ ] `python3 tools/integration_test.py` — a real client against a real server
- [ ] `python3 tools/lobby_test.py` — only if this touches rooms or the lobby

**Does this add a test?** A behaviour change without one is a behaviour
change nothing will notice breaking. An RPC sent to a node path that no
longer exists does not raise in Godot — it lands nowhere and every other
check stays green.

**Does it add art?** Everything in `game/assets/` must be redistributable
and recorded in `NOTICE`.

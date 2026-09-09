class_name GameMode
extends RefCounted
## WHAT A GAME IS, kept apart from what the world is.
##
## The world — blocks, digging, building, running, shooting, vehicles,
## weather — is the platform, and it never asks what game is being
## played. Everything that makes a round a round is a MODE: whether
## there is a storm, a clock, flags; who is on whose side; what you drop
## in holding; how many hearts; what a knockout means; who has won. The
## platform asks its mode those questions at a handful of seams and does
## what it is told.
##
## THIS IS THE ONLY PLACE A MODE IS DESCRIBED. The front page's table,
## the lobby's twin of it, the server's allowed list, the client's HUD
## and the match director all read the registry (GameModes) — so a new
## mode is one file in this folder and one line in lobby.py, and it
## appears on the front page, survives validation, and plays.
##
## It used to be strings. `game_mode == "ctf"` in one place,
## `ctf.elimination()` in another, `client_mode == "battle"` on the HUD,
## and every one of them a separate opinion about what the modes were —
## which is how the storm ended up over a capture the flag round: the
## drop set it for every mode, and only the modes that knew about it
## cleared it.
##
## Everything here has a default that is the plainest answer, so a mode
## only writes the hooks it has an opinion about. The server hooks take
## the world; the predicates take nothing, because the client asks them
## too and it has no server-side world to hand over.

## Returned by winner() to keep playing.
const CONTINUE := -9

var key := "creative"
var label := "Just building"
var note := "No rounds, nobody gets knocked out"

# ---- what the mode is made of -----------------------------------------

## Rounds at all: a lobby, a drop, an end. Without them there is nothing
## to win and nobody is ever knocked out.
func has_rounds() -> bool:
	return false

## A wall closing in on a spot, with hearts lost outside it.
func has_storm() -> bool:
	return false

## A round that ends when the time runs out — see round_seconds and
## on_time_up.
func has_clock() -> bool:
	return false

## Bases with a flag pole each, and the carrying and scoring that go
## with them (CtfDirector).
func has_flags() -> bool:
	return false

## Losing your flag puts your whole team out of the round.
func flag_loss_is_out() -> bool:
	return false

## A score to reach.
func has_target() -> bool:
	return false

func has_knockouts() -> bool:
	return has_rounds()

## The front page asks how many sides. A mode with fixed sides says no.
func picks_teams() -> bool:
	return has_rounds()

## The front page asks how many hearts the computer players get.
func uses_bot_hearts() -> bool:
	return has_knockouts()

## The line over the round card and the end table.
func kicker() -> String:
	return label.to_upper()

## Names for the sides, or empty for the colours.
func team_names() -> Array:
	return []

# ---- the round, from the server's side ---------------------------------

## After the drop has balanced everybody across the sides: a mode with
## its own idea of who goes where moves them here.
func deal_teams(_world: Node) -> void:
	pass

## The side a player who joins mid-round goes on; `balanced` is the
## smallest team, which is the default answer.
func joiner_team(_world: Node, _id: String, balanced: int) -> int:
	return balanced

## What you are holding at the drop.
func kit(_world: Node, _id: String) -> Array:
	return Weapons.STARTING_KIT

## Hearts, given what the settings say (`base`).
func max_hp(_world: Node, _id: String, base: int) -> int:
	return base

## Milliseconds between hearts growing back, once nobody has hit you
## for a while.
func regen_ms(_world: Node, _id: String) -> int:
	return 3000

## How long a round runs, when it has a clock.
func round_seconds(world: Node) -> float:
	return float(world.storm_minutes) * 60.0

## The clock ran out.
func on_time_up(_world: Node) -> void:
	pass

## Somebody on `id`'s side has just been knocked down. One of:
##   "rules"    the revive ladder decides, as it always has
##   "convert"  they change sides and stand up again over there
##   "respawn"  they stand up again where their side starts
func on_knockout(_world: Node, _id: String) -> String:
	return "rules"

## Every battle tick: CONTINUE, or the team that has won (-1 for nobody).
## `teams_alive` is the sides with somebody still in the round.
func winner(_world: Node, _teams_alive: Array) -> int:
	return CONTINUE

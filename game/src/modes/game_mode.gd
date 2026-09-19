class_name GameMode
extends RefCounted
## WHAT A GAME IS, kept apart from what the world is.
##
## The world — blocks, digging, building, running, shooting, weather,
## the wire — is the PLATFORM, and it never asks what game is
## being played. Everything that makes a round a round is a MODE: one
## file in this folder, and that file OWNS its mechanics. Battle royale's
## storm is in battle_mode.gd, not in the match director. Capture the
## flag's scoring is in ctf_mode.gd. Last flag's clock, elimination and
## end-of-round share are in holdout_mode.gd. If two modes want a
## similar thing, each writes its own; the day one of them needs to
## differ, nothing else breaks.
##
## THE PATTERN FOR A NEW GAME:
##
##   1. A file here extending GameMode, answering the predicates below
##      (what the mode is made of) and writing the hooks it has an
##      opinion about. Everything has a plain default.
##   2. One line in GameModes.ALL, and the key in lobby.py's MODES.
##   3. If the mode needs something the world cannot do — spawn a thing,
##      draw a marker, crumble ground — add that as a PRIMITIVE on the
##      platform (a world or director method any mode may call), never
##      as an objective shared between modes. The primitives a mode
##      leans on today are listed at the bottom of this file.
##
## A mode must not name the Game autoload: a script that does cannot be
## loaded by a --script test run, and the front page's tests load these.
## Read the roster through `world.roster()`.

## Returned by winner() to keep playing.
const CONTINUE := -9

var key := "creative"
var label := "Just building"
var note := "No rounds, nobody gets knocked out"

# ---- what the mode is made of. The platform and the HUD read these; a
# ---- mode answers them and does not have to be told when. ----------------

## Rounds at all: a lobby, a drop, an end.
func has_rounds() -> bool:
	return false

## A round that ends when the clock runs out — see round_seconds and
## on_time_up. (A round with a storm is on a clock too: the storm's.)
func has_clock() -> bool:
	return false

## Bases with a flag pole each, and the carrying and touching that go
## with them. The flag MACHINERY is the platform's (CtfDirector); what a
## taken flag MEANS is the mode's (on_flag_taken).
func has_flags() -> bool:
	return false

## Losing your flag puts your whole side out. Read by the computer
## players (how many stay home) and the HUD (the scoreboard heading).
func flag_loss_is_out() -> bool:
	return false

## A score to reach — the front page asks for it.
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

## DOES THIS MODE WANT COMPUTER PLAYERS AT ALL? Nearly everything does:
## filling the seats people are not in is what makes a room the size it
## was made whether one child is in it or six, and it is why the front
## page asks for a number of players rather than a number of bots.
##
## A mode that says no is saying the people present ARE the game — and
## then the seat count is not a question worth asking, so the front page
## stops asking it and the lobby forces it to nobody-but-us on the way in.
func wants_bots() -> bool:
	return true

## The map the front page moves to when this mode is chosen, or "" to
## leave whatever was already picked alone. NOT A LOCK — every map stays
## in the list — but choosing "Meeting" and being handed a desert island
## is the front page pretending not to know what you just asked for.
func suggests_map() -> String:
	return ""

## The line over the round card.
func kicker() -> String:
	return label.to_upper()

## Names for the sides, or empty for the colours.
func team_names() -> Array:
	return []

# ---- the round, in the order the platform asks -------------------------

## The lobby opened, and again the moment everybody has been dealt and
## dropped: a mode with its own idea of who goes where moves them here.
func deal_teams(_world: Node) -> void:
	pass

## Everybody is placed and the round is about to go live. Set up what
## the round needs: battle royale picks where its storm will close.
func on_round_start(_world: Node) -> void:
	pass

## How long the round runs. Battle royale answers with its storm's
## length; a mode with no clock is never asked.
func round_seconds(world: Node) -> float:
	return float(world.storm_minutes) * 60.0

## Every battle tick, after the world itself has moved (revives, hearts,
## crates, orbs, flags). `seconds_left` is the round clock, and goes
## below zero for a mode that keeps playing past it.
func tick(_world: Node, _delta: float, _seconds_left: float) -> void:
	pass

## The clock ran out. Once.
func on_time_up(_world: Node) -> void:
	pass

## Somebody just went down. One of:
##   "rules"    the revive ladder decides, as it always has
##   "convert"  they change sides and stand up again over there
##   "respawn"  they stand up again where their side starts
##
## `attacker` is who put them there, or "" for the storm, the tide, a
## fall, or anything else with nobody behind it. The match director has
## always known it and used to throw it away here; Giants is the reason
## it now arrives, because "the one who knocked you out grows" cannot be
## written without it.
func on_knockout(_world: Node, _id: String, _attacker: String) -> String:
	return "rules"

## SOMEBODY GOT HIT IN MELEE — the sword, or anything else swung at arm's
## length. What that MEANS is the mode's:
##
##   "kill"   they go down, which is what a sword has always done
##   "tag"    nothing happens to their hearts; the mode has handled it
##   "none"   the swing did not land after all
##
## Tag is the whole reason this is a seam. Its one weapon is a hand, and
## a hand that took hearts off somebody would be a sword with a friendlier
## name; what it actually does is move which player is "it", and that is a
## sentence only tag_mode.gd can write.
func on_melee(_world: Node, _attacker: String, _target: String) -> String:
	return "kill"

## `id` on side `team` just touched `from_team`'s flag. What that means
## is the mode's: a point and a flag that comes back, or a side out of
## the round. Returns whether the capturer is sent home for it.
func on_flag_taken(_world: Node, _id: String, _team: int, _from_team: int) -> bool:
	return true

## WHERE SHOULD THIS COMPUTER PLAYER BE GOING? Vector3.INF for "no
## opinion", which is every mode that has not got one, and then the
## platform's own ladder decides (BotDirector._bot_pick_goal).
##
## THIS SEAM EXISTS BECAUSE OF TAG, and it is the same argument as
## on_melee. The platform's ladder ends in "walk at the nearest enemy",
## which is the right instinct for every mode where meeting an enemy is
## something you want — and precisely the wrong one for the mode where
## the enemy is chasing you. Tag's runners were walking towards the
## person trying to touch them, and a hundred of them doing that at once
## is the heap the mode was reported as. A mode that knows something the
## ladder cannot is the thing that should say so.
##
## Asked above the objective and hunting rungs and below the urgent ones
## (the storm, being shot at), so a mode can redirect the play without
## having to re-implement staying alive.
func bot_goal(_world: Node, _id: String, _pos: Vector3) -> Vector3:
	return Vector3.INF

## Are the defenders leaving their posts to push? The computer players
## ask; a mode with no such moment says no.
func defenders_push(_world: Node) -> bool:
	return false

## After every tick and every knockout: CONTINUE, or the side that has
## won (-1 for nobody). `teams_alive` is the sides with somebody still
## in the round.
func winner(_world: Node, _teams_alive: Array) -> int:
	return CONTINUE

# ---- what the game is played with --------------------------------------

## THE WEAPONS, BLOCKS AND KITS THIS GAME HAS IN IT. See loadout.gd: an
## empty list means everything, so the default here is every game as it
## was before loadouts existed.
##
## Built fresh each call rather than held, because a mode may well want
## to answer differently as a round goes on.
func loadout(_world: Node) -> Loadout:
	return Loadout.everything()

# ---- per player --------------------------------------------------------

## The side a player who joins mid-round goes on; `balanced` is the
## smallest side, which is the default answer.
func joiner_team(_world: Node, _id: String, balanced: int) -> int:
	return balanced

## What you are holding at the drop. Defaults to the loadout's, so a mode
## that states a loadout does not also have to state a kit.
func kit(world: Node, _id: String) -> Array:
	return loadout(world).start

## HOW BIG THIS PLAYER IS at the drop, and every time they stand up
## again. 1.0 is a person. See body_size.gd.
##
## A mode that grows or shrinks somebody mid-round does NOT do it here —
## it calls `world.bodies.set_size(id, size)` when the thing that causes
## it happens. This is only the answer to "how big do they start".
func start_size(_world: Node, _id: String) -> float:
	return BodySize.PERSON

## HOW FAST THIS PLAYER MOVES, as a multiple of a person's pace.
##
## SEPARATE FROM SIZE ON PURPOSE, and the two games that use them are
## exactly why: a giant keeps a person's pace, so being eight times the
## size reads as lumbering rather than as winning twice over; and
## whoever is "it" in Tag is twice the size AND twice the speed, which is
## what makes a chase a chase. One knob could not have served both.
func speed_scale(_world: Node, _id: String) -> float:
	return 1.0

## Hearts, given what the settings say (`base`).
func max_hp(_world: Node, _id: String, base: int) -> int:
	return base

## Milliseconds between hearts growing back.
func regen_ms(_world: Node, _id: String) -> int:
	return 3000

## SOMEBODY WALKED INTO A SUPPLY CRATE. `loot` is a weapon id, or one of
## loadout.gd's special kinds (Loadout.GROWTH).
##
## A weapon has already gone into their hotbar by the time this is
## called; anything else has done nothing at all and is entirely the
## mode's to act on. Returning is not required — this is news, not a
## decision.
func on_crate_taken(_world: Node, _id: String, _loot: int) -> void:
	pass

# ---- THE PRIMITIVES a mode leans on. All on the platform; none of them
# ---- knows what a mode is.
#
#   world.roster()                    who is here: id -> {name, team, bot}
#   world.player_state[id]            {pos, hp, ...} on the server
#   world.match_alive / downed_ids / out_ids
#   world.max_hp(id), world.send_hearts(id)
#   world.bodies.set_size(id, size)   how big somebody is, right now: the
#                                     body, what shots hit, how far they
#                                     reach, and the picture. See
#                                     body_size.gd. Clamped, broadcast,
#                                     and it lifts anybody who has just
#                                     grown into solid rock

#   world.battle.eliminate(id) / put_out(id) / finish(winner)
#   world.battle.seconds_left(), world.battle.team_start_spot(team, seat)
#   world.battle.stand_again(id, switch_sides)   back up where the side starts
#   world.storm_radius / storm_center + world.cl_storm.rpc(...)
#                                     the closing-circle picture every client draws
#   world.terrain.crumble_ring(center, radius, bites)
#   world.ctf.*                       bases, poles, carrying, touching, tag-in;
#                                     send_flag_away(team), knock_out_team(team),
#                                     teams_holding(), teams_surviving()
#   world.ctf_scores / ctf_caps / ctf_lost / ctf_target    the scoreboard
#   world.cl_fanfare.rpc(text, team)  a line across every screen
#   world.team_names, world.cl_teams.rpc(names)
#   world.store                       the blocks

class_name HoldoutMode
extends GameMode
## LAST FLAG STANDING: the same flags as capture the flag, a different
## game on them. Lose your flag and your side is out; the round runs on
## a clock, because two sides properly dug in never finish each other
## off, and whoever still holds a flag at the whistle shares the pot.
##
## THE CLOCK, THE ELIMINATION AND THE SHARE-OUT LIVE HERE. Capture the
## flag's file has nothing to say about any of them and this file has
## nothing to say about points per capture: the two are free to differ.

func _init() -> void:
	key = "holdout"
	label = "Last flag"
	note = "Lose your flag and your team is out"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

func has_flags() -> bool:
	return true

func flag_loss_is_out() -> bool:
	return true

func kicker() -> String:
	return "LAST FLAG STANDING"

func kit(_world: Node, _id: String) -> Array:
	return Weapons.STARTING_KIT_CTF

## How long this round is, remembered so the computer players can ask
## how much of it is left without re-reading the environment.
var _seconds_total := 600.0

## Ten minutes, unless WORLD_HOLDOUT_MINUTES says otherwise: a mode that
## can only be seen by waiting ten minutes is a mode that never gets
## checked end to end.
func round_seconds(world: Node) -> float:
	var knob := OS.get_environment("WORLD_HOLDOUT_MINUTES")
	if knob.is_valid_float() and knob.to_float() > 0.0:
		_seconds_total = knob.to_float() * 60.0
	else:
		_seconds_total = maxf(60.0, float(world.holdout_minutes) * 60.0)
	return _seconds_total

## Is the guard going out? See HoldoutRules.pushing.
func defenders_push(world: Node) -> bool:
	return HoldoutRules.pushing(world.battle.seconds_left(), _seconds_total)

## THAT IS THEIR ROUND. No point, no respawning flag, no coming back: the
## whole reason to dig in is that there is no second chance. Points are
## settled once, at the end. The capturer is not sent home — there is
## nobody left to take it back from them.
func on_flag_taken(world: Node, id: String, team: int, from_team: int) -> bool:
	world.ctf.knock_out_team(from_team)
	world.cl_fanfare.rpc("%s took %s's flag  ·  %s is out" % [
		str(world.roster().get(id, {}).get("name", "Somebody")),
		_side(world, from_team), _side(world, from_team)], team)
	print("HOLDOUT: %s took team %d's flag — team %d is out" % [id, from_team, from_team])
	_over_if_one_left(world)
	return false

func on_time_up(world: Node) -> void:
	_settle(world)

func winner(world: Node, _teams_alive: Array) -> int:
	_over_if_one_left(world)
	return CONTINUE

func _over_if_one_left(world: Node) -> void:
	if world.match_phase != "BATTLE":
		return
	if world.roster().is_empty():
		world.battle.finish(-2)
	elif world.ctf.teams_holding().size() <= 1:
		_settle(world)

## SETTLE THE ROUND. Whoever SURVIVED — in the round and standing, not
## merely with a flagpole up — shares the pot, and the share depends on
## how many of them there are (HoldoutRules). Points go into the same
## per-side score capture the flag uses, so they accumulate across
## rounds on the one scoreboard. The winner reported is the top side, or
## -1 when more than one held: a shared round is a draw.
func _settle(world: Node) -> void:
	if world.match_phase != "BATTLE":
		return
	var held: Array = world.ctf.teams_surviving()
	var each := HoldoutRules.share(held.size())
	for team_v: Variant in held:
		var team := int(team_v)
		world.ctf_scores[team] = int(world.ctf_scores.get(team, 0)) + each
	world.ctf.broadcast_flags()
	print("HOLDOUT: %d team(s) survived of %d holding, %d point(s) each (scores %s)"
		% [held.size(), world.ctf.teams_holding().size(), each, world.ctf_scores])
	world.battle.finish(int(held[0]) if held.size() == 1 else -1)

func _side(world: Node, team: int) -> String:
	var names: Array = world.team_names
	return str(names[team]) if team >= 0 and team < names.size() else "the other side"

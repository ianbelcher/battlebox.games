extends Node
## KNOCK THE PERSON DOWN, ON PURPOSE, THROUGH THE REAL DAMAGE PATH.
##
## Being knocked out is the state most reported and least testable: it is
## reached only by losing a fight, so a headless run reaches it by luck or
## not at all. Three separate runs went by without the autotest player
## going down once, which is why a red overlay nobody could reproduce
## survived two attempts to remove it.
##
## Server side, because damage is. It waits for a battle, finds the human,
## and hits them until they fall — through match_hurt, the same call a
## sword makes, so everything downstream is exactly what a real knockout
## does rather than a flag set by hand.
##
##     WORLD_KNOCKOUT_TEST=<seconds into the battle>

func _ready() -> void:
	var delay := OS.get_environment("WORLD_KNOCKOUT_TEST").to_float()
	var world: Node = null
	var waited := 0
	while world == null and waited < 90:
		await get_tree().create_timer(1.0).timeout
		waited += 1
		world = Game.world
	if world == null:
		print("KNOCKOUT_PROBE: no world after %ds" % waited); return
	while str(world.match_phase) != "BATTLE" and waited < 180:
		await get_tree().create_timer(1.0).timeout
		waited += 1
	if str(world.match_phase) != "BATTLE":
		print("KNOCKOUT_PROBE: never reached BATTLE"); return
	await get_tree().create_timer(maxf(1.0, delay)).timeout
	# NOT the `bot` flag on the roster: a headless autotest player carries
	# it too, so "the human" by that test is nobody at all and the probe
	# quietly did nothing. The real question is who the server is driving —
	# anyone it is not is somebody at a keyboard.
	var victim := ""
	for id: String in Game.roster.keys():
		if not world.bots.roster.has(id) and world.match_alive.has(id):
			victim = id
			break
	if victim.is_empty():
		print("KNOCKOUT_PROBE: nobody human to knock down"); return
	var at: Vector3 = world.player_state.get(victim, {}).get("pos", Vector3.ZERO)
	# FLYING OFF, if asked. The question being tested is whether being
	# picked up takes the wings back off you, and it can only be asked in
	# a game that does not hand them out in the first place.
	# NOBODY COMES BACK, if asked. The question is whether a knockout puts
	# you straight OUT instead of down-and-revivable, and whether the
	# routes back — a team-mate, or your own flag — really are shut.
	if OS.get_environment("WORLD_KNOCKOUT_NOREVIVE") == "1":
		world.no_revive = true
		print("KNOCKOUT_PROBE: reviving switched OFF")
	if OS.get_environment("WORLD_KNOCKOUT_NOFLY") == "1":
		world.battle_fly = false
		world.cl_battle_config.rpc(int(world.storm_minutes), int(world.battle_size),
			world.loot_only, false, world.team_count, world.drop_on_knockout,
			world.ctf_revive, world.ctf_target)
		print("KNOCKOUT_PROBE: flying switched OFF")
	print("KNOCKOUT_PROBE: knocking %s down at %v" % [victim, at])
	# SPACED OUT, not one a frame. MatchDirector.hurt gives a person 800ms
	# of mercy after a hit so one volley cannot delete them — so twenty
	# hits inside a third of a second land as exactly one, and the probe
	# reported "knocked down" while the player walked off on full hearts.
	for i in 12:
		await get_tree().create_timer(0.9).timeout
		if world.downed_ids.has(victim) or world.out_ids.has(victim):
			break
		var now: Vector3 = world.player_state.get(victim, {}).get("pos", at)
		world.match_hurt(victim, 3, now + Vector3(3, 0, 0), "")
	print("KNOCKOUT_PROBE: down=%s out=%s" % [
		str(world.downed_ids.has(victim)), str(world.out_ids.has(victim))])
	# AND THEN PICK THEM UP AGAIN. Being revived is the half that matters
	# for flight: going down hands you wings so you can get out of the
	# fray, and being stood back up has to take them off you again in a
	# game with flying switched off. Long enough first for the ten-block
	# rise to finish and for flight to actually be on.
	await get_tree().create_timer(10.0).timeout
	print("KNOCKOUT_PROBE: reviving %s (battle_fly=%s)"
		% [victim, str(world.battle_fly)])
	world.ctf.respawn(victim)
	await get_tree().create_timer(1.0).timeout
	print("KNOCKOUT_PROBE: after respawn — down=%s out=%s alive=%s"
		% [str(world.downed_ids.has(victim)), str(world.out_ids.has(victim)),
			str(world.match_alive.has(victim))])

class_name BotBrain
extends Node
## Makes computer players actually play: grab crates when hands are empty,
## chase and shoot enemies, stand by downed teammates to revive them, and
## wander otherwise. Attached to bot Player nodes client-side.

var player: Player
var bot: BotSlot

## What a bot will actually fight with. The rest of the kit is movement and
## utility — wings, grapple, digger, flare, block sucker, smoke — and a bot
## holding one of those is a bot standing in the open doing nothing useful
## while somebody shoots it.
const FIGHTING_WEAPONS := [0, 1, 15, 9, 17, 3, 8, 18, 10]

func _ready() -> void:
	var timer := Timer.new()
	# Fast enough to track someone who is strafing. At the old 0.35s a bot
	# aimed a third of a second behind a moving player, which at close
	# range is a clean miss every time.
	timer.wait_time = 0.15
	timer.timeout.connect(_think)
	add_child(timer)
	timer.start()

func _drive_toward(target: Vector3, run := 1.0) -> void:
	var to_target := target - player.position
	var world_dir := Vector2(to_target.x, to_target.z).normalized() * run
	bot.drive = world_dir.rotated(player.camera_yaw)
	bot.drive_until = Time.get_ticks_msec() / 1000.0 + 0.45

func _think() -> void:
	if player == null or not is_instance_valid(player) or player.world == null:
		return
	var world: Node = player.world
	bot.brain_shoot = false
	if player.downed:
		return
	var my_team := int(Game.roster.get(player.player_id, {}).get("team", -1))
	for child in world.players.get_children():
		if child is Player and child != player and child.downed \
				and int(Game.roster.get(child.player_id, {}).get("team", -2)) == my_team \
				and child.position.distance_to(player.position) < 26.0:
			_drive_toward(child.position)
			return
	# Hold the fastest gun in the bag. Cooldown is the only thing that
	# separates them here — there is no damage number to weigh — and with
	# the trigger held down the cooldown IS the threat: a Little Shooter
	# at 0.09s puts out a wall of pellets, a Big Shooter at 2.0s is one
	# thump you can walk around. Bots used to take whatever weapon sat in
	# the lowest slot, and only if their hands were otherwise empty.
	var armed := false
	var best_slot := -1
	var best_cooldown := INF
	for i in 8:
		var it: Dictionary = player.slots[i]
		if it.kind != "weapon" or not FIGHTING_WEAPONS.has(int(it.id)):
			continue
		armed = true
		var cd := float(Weapons.spec(int(it.id)).cooldown)
		if cd < best_cooldown:
			best_cooldown = cd
			best_slot = i
	if best_slot >= 0 and player.selected_slot != best_slot:
		player.selected_slot = best_slot
	var enemy: Player = null
	var best := 34.0
	for child in world.players.get_children():
		if child is Player and child != player and not child.downed \
				and int(Game.roster.get(child.player_id, {}).get("team", -2)) != my_team:
			var d: float = child.position.distance_to(player.position)
			if d < best:
				best = d
				enemy = child
	if enemy != null and (armed or best < 5.0):
		_drive_toward(enemy.position)
		player.heading = (enemy.position - player.position).normalized()
		bot.brain_shoot = best < 26.0
		return
	var has_empty := false
	for it: Dictionary in player.slots:
		if it.kind == "empty":
			has_empty = true
	if has_empty and world.crates != null:
		var target := Vector3.INF
		var crate_best := 70.0
		for entry: Dictionary in world.crates._nodes.values():
			var pos: Vector3 = entry.node.position
			var d: float = pos.distance_to(player.position)
			if d < crate_best:
				crate_best = d
				target = pos
		if target != Vector3.INF:
			_drive_toward(target)

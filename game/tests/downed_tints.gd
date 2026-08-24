extends Node
## WHAT IS ACTUALLY RED ON SCREEN WHILE YOU ARE KNOCKED OUT.
##
## Three times now the answer has been "a different overlay than the one
## that was fixed". There are four reddish full-screen layers in the HUD,
## each with its own trigger, and reading the code cannot tell you which
## one is lit — nor can knocking yourself down by hand, because a state
## set on the client alone is not the state a real knockout produces.
##
## So this one forces nothing. It watches a real battle and, every second,
## prints what every red layer is actually sitting at, next to whether
## this player is down. The line where `downed=true` first appears is the
## answer.
##
##     WORLD_DOWNED_TINTS=1 alongside WORLD_AUTOTEST=1

const LAYERS := ["_vignette", "_storm_tint", "_damage_flash", "_grey"]

var _seen_down := false

func _ready() -> void:
	var hud: Node = null
	while hud == null:
		await get_tree().create_timer(1.0).timeout
		var huds: Array = get_tree().get_nodes_in_group("player_hud")
		if not huds.is_empty():
			hud = huds[0]
	var me: String = Game.player_id(multiplayer.get_unique_id(), hud.slot)
	for tick in 400:
		await get_tree().create_timer(1.0).timeout
		# RE-FETCHED, not captured once. Entering a round replaces the
		# world, and a reference taken before that goes stale — which read
		# as a probe that printed one line and then fell silent.
		var world: Node = Game.world
		# `hud.player` DOES NOT EXIST — PlayerHud reaches its player through
		# a method, not a property, so that guard was false every tick and
		# the probe printed nothing at all while looking like it worked.
		if world == null:
			continue
		var bits: PackedStringArray = []
		for name: String in LAYERS:
			var node: Object = hud.get(name)
			if node == null:
				continue
			var a := 0.0
			if node is ColorRect:
				a = (node as ColorRect).color.a
			elif node is TextureRect:
				a = (node as TextureRect).modulate.a
			bits.append("%s=%.2f" % [name.substr(1), a])
		var down: bool = world.client_downed.has(me)
		var out: bool = world.out_ids.has(me)
		if down or out:
			_seen_down = true
		if not (down or out or _seen_down) and tick % 5 != 0:
			continue          # quiet until something happens, then every tick
		var mine: Node = null
		for child in world.players.get_children():
			if child is Player and child.player_id == me:
				mine = child
				break
		print("TINTS: phase=%s downed=%s out=%s | %s | fly_mode=%s allowed=%s world_fly=%s"
			% [world.match_phase, str(down), str(out), ", ".join(bits),
				str(mine.fly_mode) if mine != null else "?",
				str(world.fly_allowed_for(me)), str(world.client_fly)])

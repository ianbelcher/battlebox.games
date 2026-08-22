class_name WorldFx
extends Node
## The bangs and sparkles: explosion debris, firework shells, confetti,
## smoke columns and the light flashes that go with them. CLIENT-side
## only, at World/Fx — a headless server never builds any of it.
##
## Everything here is fire-and-forget. Each effect builds its own nodes,
## tweens them, and frees them on a timer, because a particle system left
## parented to a block that has since been blown up is a tween looping
## forever over an object that no longer exists.
##
## There is a hard ceiling on simultaneous explosions (MAX_LIVE_BOOMS).
## A browser meshing chunks on worker threads cannot also run twenty
## particle systems, and the failure mode is not a dropped frame — it is
## the tab going away.

## The world these effects happen in.
var world: WorldNode = null

## THE BOOM. Three layers, because one never looked like an explosion.
##
## It was a single 40-piece shower of orange cubes that fell out of the
## air in under a second — the same one whatever had gone off — and it
## read as a puff rather than a bang. What was missing is the part that
## LINGERS: in footage of the game the fireworks throw embers
## that climb, slow to a hover and hang in the air glowing, and that hang
## is what makes it feel like something happened.
##
##   DEBRIS  chunky lumps thrown hard and pulled straight back down. The
##           original effect, now the shortest-lived of the three.
##   EMBERS  small, bright, thrown up and out, then almost weightless with
##           heavy damping so they slow to a drift and glow for seconds.
##   SMOKE   a slow dark bloom that swells and fades, so the flash has
##           something to leave behind.
##
## `power` is the blast radius, so a pellet pops and a Big Shooter shell
## throws a column of sparks over the rooftops.
## How many explosions may be drawing at once. Past this, new ones still
## flash and still make their noise, but skip the expensive layers.
##
## The effect is THREE particle systems and a Big Shooter's are 400-odd
## meshes between them, every one transformed on the CPU because the
## browser build renders through gl_compatibility. One at a time is
## nothing. Twenty at once, which a crowded round produces easily, is a
## stutter — and it lands exactly when the most is happening, which is the
## worst possible moment to spend a frame on decoration.
##
## The cap is a CLIENT-side budget and nothing to do with the server: the
## server works out which blocks went and who was hurt, then sends one
## small message. Every machine draws its own explosions and pays for its
## own.
const MAX_LIVE_BOOMS := 8

## The marker's drift, kept so it can be killed explicitly as well as
## dying with the node it is bound to.
var _smoke_tween: Tween = null
## The one smoke marker. Putting a new one up takes the old one down,
## wherever it was and whoever threw it, so there is never any question
## about which spot the team is being pointed at.
var _smoke_node: Node3D = null
var _live_booms := 0

## Take the marker down, tween and all. Freeing the node alone is what
## left orphaned tweens running over dead objects.
func drop_smoke_marker() -> void:
	if _smoke_tween != null and _smoke_tween.is_valid():
		_smoke_tween.kill()
	_smoke_tween = null
	if is_instance_valid(_smoke_node):
		_smoke_node.queue_free()
	_smoke_node = null
func explosion(center: Vector3, power := 2.2) -> void:
	var scale := clampf(power / 2.2, 0.6, 2.6)
	if _live_booms >= MAX_LIVE_BOOMS:
		return
	_live_booms += 1
	# HEFT: how far past an ordinary bang this is. 0 for a pellet or a
	# Medium Shooter (radius 2.1), about 0.8 for the Big Shooter (4.0), 1
	# for a TNT block (4.5).
	#
	# `scale` alone is linear, so the big gun got a proportionally bigger
	# version of the same puff. The difference between "that exploded" and
	# "get away from that" is not size, it is how long the air stays full
	# afterwards — so heft buys PARTICLES and TIME, on top of the size
	# that scale already buys.
	var heft := clampf((power - 2.6) / 1.8, 0.0, 1.0)

	var debris := CPUParticles3D.new()
	debris.position = center
	debris.amount = int(36.0 * scale * (1.0 + heft * 0.8))
	debris.lifetime = 0.9
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.spread = 180.0
	debris.initial_velocity_min = 6.0 * scale
	debris.initial_velocity_max = 11.0 * scale
	debris.gravity = Vector3(0, -14, 0)
	debris.mesh = BoxMesh.new()
	(debris.mesh as BoxMesh).size = Vector3.ONE * (0.20 * scale)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(1.0, 0.55, 0.2)
	dmat.emission_enabled = true
	dmat.emission = Color(1.0, 0.45, 0.1)
	dmat.emission_energy_multiplier = 2.4
	debris.mesh.material = dmat
	add_child(debris)
	debris.emitting = true

	# THE EMBERS: the layer that sells it. Thrown up and outward, then
	# damped almost to a stop so they hover and cool rather than dropping.
	var embers := CPUParticles3D.new()
	embers.position = center
	embers.amount = int(70.0 * scale * (1.0 + heft * 1.4))
	# Twice as long in the air for the big one. This is the whole
	# difference: a Medium Shooter's sparks are gone in under three
	# seconds, a Big Shooter leaves the sky full for five.
	# 1.3 rather than 1.0 so the BIG SHOOTER specifically lands on double.
	# Its heft is 0.78, not 1 — that is reserved for a TNT block — so a
	# plain doubling of heft left the gun actually complained about short
	# of the two seconds he asked for.
	embers.lifetime = 2.6 * (1.0 + heft * 1.3)
	embers.lifetime_randomness = 0.5
	embers.one_shot = true
	embers.explosiveness = 0.85
	embers.spread = 70.0
	embers.direction = Vector3(0, 1, 0)      # up and out, not a sphere
	embers.initial_velocity_min = 4.0 * scale
	embers.initial_velocity_max = 12.0 * scale * (1.0 + heft * 0.5)
	# Barely any gravity, and heavy drag: this is what turns a shower into
	# a hover. With normal gravity they are just sparks falling over.
	embers.gravity = Vector3(0, -1.1, 0)
	embers.damping_min = 3.0
	embers.damping_max = 6.0
	embers.mesh = BoxMesh.new()
	(embers.mesh as BoxMesh).size = Vector3.ONE * 0.09
	# Small ones fade out; a few big ones live longer, as embers do.
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 1.8
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.55, 0.8))
	fade.add_point(Vector2(1.0, 0.0))
	embers.scale_amount_curve = fade
	# White-hot, cooling through orange to a dull red before it goes out.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.96, 0.80))
	ramp.set_color(1, Color(0.85, 0.20, 0.05))
	ramp.add_point(0.45, Color(1.0, 0.62, 0.18))
	embers.color_ramp = ramp
	var emat := StandardMaterial3D.new()
	emat.vertex_color_use_as_albedo = true
	emat.emission_enabled = true
	emat.emission = Color(1.0, 0.7, 0.3)
	# Hot enough for the glow pass to catch, which is where the bloom
	# around each one comes from.
	emat.emission_energy_multiplier = 5.0
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	embers.mesh.material = emat
	add_child(embers)
	embers.emitting = true

	var smoke := CPUParticles3D.new()
	smoke.position = center
	smoke.amount = int(14.0 * scale * (1.0 + heft))
	smoke.lifetime = 2.0 * (1.0 + heft)
	smoke.one_shot = true
	smoke.explosiveness = 0.9
	smoke.spread = 180.0
	smoke.initial_velocity_min = 0.6
	smoke.initial_velocity_max = 2.4 * scale
	smoke.gravity = Vector3(0, 0.7, 0)       # it rises
	smoke.damping_min = 1.5
	smoke.damping_max = 3.0
	smoke.mesh = SphereMesh.new()
	(smoke.mesh as SphereMesh).radius = 0.5 * scale
	(smoke.mesh as SphereMesh).height = 1.0 * scale
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.6
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.3))
	swell.add_point(Vector2(0.4, 1.0))
	swell.add_point(Vector2(1.0, 0.0))
	smoke.scale_amount_curve = swell
	var smat := StandardMaterial3D.new()
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.10, 0.09, 0.10, 0.42)
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.mesh.material = smat
	add_child(smoke)
	smoke.emitting = true

	# One timer for the lot, at the LONGEST lifetime plus a margin — and it
	# has to be computed, not a constant: the embers now outlive the old
	# fixed 4-second sweep on anything big, and a node freed while it is
	# still emitting takes the effect off the screen mid-burst.
	var sweep := maxf(4.0, float(embers.lifetime) * 1.6 + 1.0)
	get_tree().create_timer(sweep).timeout.connect(func() -> void:
		_live_booms = maxi(0, _live_booms - 1)
		for node in [debris, embers, smoke]:
			if is_instance_valid(node):
				node.queue_free())
func flash_light(center: Vector3, color: Color, energy: float,
		reach := 1.0) -> void:
	var flash := OmniLight3D.new()
	flash.position = center
	flash.light_color = color
	flash.light_energy = energy
	flash.omni_range = 14.0 * reach
	flash.shadow_enabled = false
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.5 * reach)
	tween.tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free())
## SOMEBODY WENT DOWN, AND THE PERSON WHO DID IT SHOULD KNOW.
##
## A knockout used to be silent to the shooter: the body simply stopped
## being there. Across a field, with a storm closing, you could not tell a
## hit from a miss — so you kept shooting at a player who had already
## gone, and never learned which of your shots had worked.
##
## A white burst, big and brief. Deliberately white rather than a team
## colour: it reads as "gone" at any distance and against any terrain,
## and it is the one effect in the game that means that. It touches no
## blocks — nothing here is an explosion, it is an announcement.
func knockout(center: Vector3) -> void:
	var sparks := CPUParticles3D.new()
	sparks.position = center
	sparks.amount = 64
	sparks.lifetime = 0.9
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.spread = 180.0
	sparks.initial_velocity_min = 4.0
	sparks.initial_velocity_max = 11.0
	sparks.gravity = Vector3(0, -6, 0)
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.11
	mesh.height = 0.22
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 1)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	sparks.mesh = mesh
	add_child(sparks)
	sparks.emitting = true

	# A soft shell that swells and fades, so the moment reads even when
	# the individual sparks are too small to pick out at distance.
	var shell := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	shell.mesh = ball
	var shell_mat := StandardMaterial3D.new()
	shell_mat.albedo_color = Color(1, 1, 1, 0.75)
	shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shell.material_override = shell_mat
	shell.position = center
	add_child(shell)
	var swell := create_tween()
	swell.set_parallel(true)
	swell.tween_property(shell, "scale", Vector3.ONE * 7.0, 0.45)
	swell.tween_property(shell_mat, "albedo_color:a", 0.0, 0.45)

	flash_light(center, Color(1, 1, 1), 7.0, 1.4)
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(sparks):
			sparks.queue_free()
		if is_instance_valid(shell):
			shell.queue_free())

func burst(pos: Vector3i, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.position = Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	particles.amount = 14
	# LONG ENOUGH TO ARC AND FALL BACK. At 0.5s they were gone before they
	# had finished going up.
	particles.lifetime = 0.9
	particles.lifetime_randomness = 0.3
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	# THE BITS HAVE TO CLEAR THE BLOCK THEY CAME OUT OF. At 2-4 blocks a
	# second against gravity 14 the fastest of them peaked around 0.57
	# above the emitter — which is the middle of the block, so they topped
	# out level with its lid and the whole shower stayed inside the hole.
	# Nothing escaped, so breaking a block looked like it collapsed rather
	# than burst.
	#
	# 4.5-8 against a floatier 10 puts the peak between half a block and
	# nearly three above the lid: the slow ones just clear it, the quick
	# ones properly pop. The cone stays narrow so they still read as
	# coming out of THAT block rather than spraying over the neighbours.
	particles.spread = 50.0
	particles.initial_velocity_min = 4.5
	particles.initial_velocity_max = 8.0
	particles.gravity = Vector3(0, -10, 0)
	particles.mesh = BoxMesh.new()
	(particles.mesh as BoxMesh).size = Vector3(0.12, 0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	particles.mesh.material = mat
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.8).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())

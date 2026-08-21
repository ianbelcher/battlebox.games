class_name DayNight
extends Node3D
## Sky, sun, moon and the Forward+ environment. This is where the renderer
## gets to show off: real directional shadows, SSAO, glow, subtle volumetric
## fog, and (WORLD_MAXFX=1) SDFGI bounce light. The clock is replicated from
## the server; visuals slide smoothly as it advances.

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var environment: Environment
var sky_material: ProceduralSkyMaterial
var _clock := 0.35
var allow_shadows := true
## The GL Compatibility renderer (LITE mode) has no SSAO/GI, so it reads
## darker — boost light to keep the same friendly look.
var _gl_boost := 1.0

const DAY_TOP := Color("4a9de8")
const DAY_HORIZON := Color("bcd8ee")
const DUSK_TOP := Color("3a4a7a")
const DUSK_HORIZON := Color("f2a05e")
const NIGHT_TOP := Color("0a0e22")
const NIGHT_HORIZON := Color("1c2445")

## The colour night is lit BY, once the sky stops doing it.
##
## Ambient light is taken from the sky, and the night sky is very nearly
## black — which is why night was once unplayably dark. Turning the sky's
## contribution down after dusk and mixing this in instead keeps the
## palette cool and night-like while leaving blocks readable. It is
## deliberately blue: a grey lift just looks like the gamma is broken.
##
## Dim on purpose. The first attempt at this used a much brighter blue and
## lifted the energy on top, which produced a night you could read a book
## by — see the note on MOON_ENERGY.
const NIGHT_AMBIENT := Color("56658c")
## How much of the ambient stops coming from the sky at midnight.
const NIGHT_SKY_PULLBACK := 0.75

## The moon, as a fraction of full sunlight (SUN_ENERGY).
##
## This number was 0.4, then briefly 0.85, which is where night stopped
## looking like night: the sun only reaches 0.42 as it crosses the horizon,
## so a 0.85 moon made MIDNIGHT BRIGHTER THAN DAWN. Walking from 5am to
## 6am, the world got darker as the sun came up. It also cast hard shadows
## at three in the morning from something that was not drawn in the sky.
##
## Keeping it well under the horizon-crossing sun is what makes the whole
## day monotonic: brightest at noon, dimmest in the small hours.
const SUN_ENERGY := 1.4
const MOON_ENERGY := 0.22

## Where the sun's light fades out and the moon's fades in, in elevation
## (sin of the sun's angle: +1 overhead, 0 at the horizon, -1 midnight).
## The two ramps overlap slightly so nothing ever drops into a trough
## between them, which is what a hard cutover produced.
const SUN_SET := -0.12
const SUN_FULL := 0.20
const MOON_HELD_OFF := 0.02
const MOON_FULL := -0.22

## Seconds per full day. Pushed from the world, which fits one whole day
## into a battle — see WorldNode.day_length. The sky runs its own clock
## between server syncs, so it needs the rate, not just the time.
var day_length := 240.0

func _ready() -> void:
	if RenderingServer.get_rendering_device() == null:
		_gl_boost = 1.45
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_bias = 0.03
	sun.light_color = Color(1.0, 0.96, 0.88)
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 90.0
	# Near-white, not blue. The sky shader draws the moon's DISC from this
	# colour times the light's energy, and at the low energy the moon
	# needs (see MOON_ENERGY) a blue-grey disc came out barely above the
	# night sky behind it. White reads as a moon; the light it casts is
	# still cool because everything else at night is.
	moon.light_color = Color(0.88, 0.92, 1.0)
	moon.light_energy = 0.0
	# Starts light-only; _apply() turns the disc on once the moon is up and
	# lit, and off again before daybreak. See the note there.
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 30.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 6.0
	environment.ssao_enabled = true
	environment.ssao_intensity = 1.6
	environment.ssao_radius = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.0
	# Depth fog softens the draw-distance edge exactly like Minecraft;
	# main retunes fog_depth_end whenever the player changes draw distance.
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_curve = 1.6
	environment.fog_depth_begin = 70.0
	environment.fog_depth_end = 128.0
	# The sky itself stays almost clear so the sun and moon shine through.
	environment.fog_sky_affect = 0.08
	# No volumetric fog ever: it fills an orthographic frustum with a flat
	# gray wash (verified). WORLD_MAXFX adds SDFGI bounce light only.
	if OS.get_environment("WORLD_MAXFX") == "1":
		environment.sdfgi_enabled = true
		environment.sdfgi_use_occlusion = true
		environment.sdfgi_cascades = 2
		environment.sdfgi_min_cell_size = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	set_clock(_clock)

func set_clock(clock: float) -> void:
	_clock = clock

## Old-computer mode: drop the expensive post effects, keep the look.
func set_low_fx(low: bool) -> void:
	environment.ssao_enabled = not low
	environment.glow_enabled = not low
	sun.directional_shadow_max_distance = 60.0 if low else 120.0
	moon.shadow_enabled = false if low else moon.shadow_enabled

func _process(delta: float) -> void:
	_clock = fposmod(_clock + delta / maxf(day_length, 1.0), 1.0)
	_apply(_clock)

## clock: 0 midnight, 0.25 dawn, 0.5 noon, 0.75 dusk.
func _apply(clock: float) -> void:
	var sun_angle := (clock - 0.25) * TAU  # 0 at dawn
	var elevation := sin(sun_angle)
	sun.rotation = Vector3(-maxf(elevation, 0.02) * 1.35, 0.8 + cos(sun_angle) * 0.4, 0)
	# Smooth ramps rather than a clamped straight line, so the light never
	# steps and never dips between the two.
	var daylight := smoothstep(SUN_SET, SUN_FULL, elevation)
	sun.light_energy = daylight * SUN_ENERGY * _gl_boost
	sun.shadow_enabled = allow_shadows and daylight > 0.1
	var warmth := clampf(1.0 - elevation * 2.0, 0.0, 1.0)  # low sun = warm
	sun.light_color = Color(1.0, 0.96 - warmth * 0.25, 0.88 - warmth * 0.4)

	var moonlight := smoothstep(MOON_HELD_OFF, MOON_FULL, elevation)
	moon.rotation = Vector3(-maxf(-elevation, 0.02) * 1.2, -0.6, 0)
	moon.light_energy = moonlight * MOON_ENERGY * _gl_boost
	# THERE IS A MOON IN THE SKY NOW, and it is drawn by the sky shader
	# rather than placed in the world — which is the only way it can be
	# right for all four split-screen cameras at once, since they share one
	# World3D and a real object would have the wrong parallax for three of
	# them.
	#
	# It has to be switched off during the day. The disc is drawn from the
	# light's colour times its energy, so a moon that is up but unlit is a
	# BLACK dot on a blue sky — which is why this was disabled outright
	# before, and why it is toggled rather than simply left on.
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if moonlight > 0.05 \
		else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# Faint shadows, and only once the moon is properly up. Hard-edged
	# shadows at 3am from an invisible source were the tell that something
	# was wrong here.
	moon.shadow_enabled = allow_shadows and moonlight > 0.5
	moon.shadow_opacity = 0.5

	var top: Color
	var horizon: Color
	if elevation > 0.15:
		top = DAY_TOP
		horizon = DAY_HORIZON
	elif elevation > -0.12:
		var mix := inverse_lerp(-0.12, 0.15, elevation)
		top = NIGHT_TOP.lerp(DUSK_TOP, mix).lerp(DAY_TOP, maxf(0.0, mix * 2.0 - 1.0))
		horizon = NIGHT_HORIZON.lerp(DUSK_HORIZON, mix).lerp(DAY_HORIZON, maxf(0.0, mix * 2.0 - 1.0))
	else:
		top = NIGHT_TOP
		horizon = NIGHT_HORIZON
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	environment.fog_light_color = horizon
	# The below-horizon half fades gently from the horizon color instead
	# of a flat dark gray slab.
	sky_material.ground_bottom_color = horizon.darkened(0.25)
	sky_material.ground_horizon_color = horizon
	# Ambient is taken from the SKY, and after dusk the sky is nearly black
	# (NIGHT_TOP is #0a0e22), so "ambient energy 0.72" was 0.72 of almost
	# nothing. That is what made night unplayable rather than atmospheric —
	# turning the energy up alone could never have fixed it, because the
	# COLOUR was the problem.
	#
	# So as the sun goes down the sky hands ambient over to a fixed, DIM
	# blue. No energy lift on top of it: that was the other half of making
	# night look like an overcast afternoon.
	var night := 1.0 - daylight
	environment.ambient_light_sky_contribution = 1.0 - night * NIGHT_SKY_PULLBACK
	environment.ambient_light_color = NIGHT_AMBIENT
	environment.ambient_light_energy = (0.72 + daylight * 0.28) * _gl_boost

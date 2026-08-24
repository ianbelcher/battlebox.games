extends Node
## Sound effects: Kenney CC0 samples (assets/sounds) for the physical
## stuff — digging, placing, landing, punches, UI — with synthesized
## bell/marimba tones filling in everything without a good sample.
## Soft bell/marimba tones (sines with gentle harmonics and exponential decay)
## plus looping nature ambients that follow the world clock.

const RATE := 22050
## Ambience (the night crickets) sits below everything else on purpose: it
## is the only sound that never stops, so it is the one that grates.
## -22 dB is about half the loudness of the old -16.
const AMBIENT_DB := -22.0
const PLAYER_POOL := 8

const TIMBRES := {
	"bell": {"ring": 0.9, "h2": 0.35, "h3": 0.12},
	"soft": {"ring": 0.35, "h2": 0.2, "h3": 0.05},
	"thump": {"ring": 0.2, "h2": 0.0, "h3": 0.0},
}

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambients: Dictionary = {}
var _ambient_player: AudioStreamPlayer
var _current_ambient := ""
var _chirps: Array = []
var _bird_timer: Timer

func _ready() -> void:
	for i in PLAYER_POOL:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)
	_streams = {
		"join": _notes([[660, 0.09], [880, 0.1]], 0.5, "soft"),
		"tick": _notes([[1047, 0.1]], 0.35, "soft"),
		"jump": _notes([[440, 0.05], [660, 0.07]], 0.35, "soft"),
		"land": _notes([[180, 0.08]], 0.5, "thump"),
		"dig": _notes([[150, 0.09]], 0.6, "thump"),
		"place": _notes([[520, 0.06], [420, 0.08]], 0.45, "soft"),
		"collect": _notes([[880, 0.07], [1175, 0.08], [1568, 0.12]], 0.5),
		"pet": _notes([[988, 0.07], [1319, 0.09], [1760, 0.14]], 0.45, "soft"),
		"pop": _notes([[988, 0.06]], 0.45, "soft"),
		"splash": _notes([[740, 0.04], [520, 0.05], [620, 0.06]], 0.4, "soft"),
		"boing": _notes([[240, 0.05], [420, 0.06], [660, 0.09]], 0.55, "soft"),
		"drop": _notes([[659, 0.08], [440, 0.1]], 0.45, "soft"),
		"pew": _notes([[1400, 0.03], [900, 0.03], [560, 0.05]], 0.4, "soft"),
		"click": _notes([[2200, 0.02]], 0.28, "thump"),
		"thoomp": _thoomp(),
		"bonk": _notes([[220, 0.06], [160, 0.1]], 0.6, "thump"),
		"baa": _baa(),
		"quack": _quack(),
		"cluck": _cluck(),
		"ribbit": _ribbit(),
		"whoosh": _notes([[320, 0.05], [480, 0.05], [720, 0.06], [1080, 0.1]], 0.4, "soft"),
		"boom": _boom(),
		"rumble": _rumble(),
		"note": _notes([[523, 0.12]], 0.55),
		"warp": _notes([[880, 0.06], [660, 0.06], [440, 0.07], [880, 0.0], [1320, 0.12]], 0.5, "soft"),
		"cheer": _cheer(),
	}
	# Kenney sample overrides: arrays are per-play random variants.
	const KENNEY := {
		"tick": ["click_001", "click_002"],
		"pop": ["pluck_001", "pluck_002"],
		"collect": ["confirmation_002"],
		"join": ["confirmation_001"],
		"drop": ["drop_001", "drop_002"],
		"dig": ["impactMining_000", "impactMining_001", "impactMining_002",
			"impactMining_003", "impactMining_004"],
		"place": ["impactWood_light_000", "impactWood_light_001",
			"impactWood_light_002", "impactWood_light_003"],
		"land": ["impactSoft_heavy_000", "impactSoft_heavy_001",
			"impactSoft_heavy_002"],
		"bonk": ["impactPunch_medium_000", "impactPunch_medium_001",
			"impactPunch_medium_002"],
	}
	for clip: String in KENNEY:
		var variants: Array = []
		for file: String in KENNEY[clip]:
			var stream: AudioStream = load("res://assets/sounds/%s.ogg" % file)
			if stream != null:
				variants.append(stream)
		if not variants.is_empty():
			_streams[clip] = variants
	_ambient_player = AudioStreamPlayer.new()
	# The crickets run ALL NIGHT, unlike every other sound in the game,
	# which is why they wear out their welcome first. Halved from -16 dB.
	_ambient_player.volume_db = AMBIENT_DB
	add_child(_ambient_player)
	_ambients = {
		"step": _step(),
		"crickets": _crickets(8),
	}
	for i in 4:
		_chirps.append(_chirp())
	apply_volume()
	Game.video_changed.connect(apply_volume)
	_bird_timer = Timer.new()
	_bird_timer.one_shot = true
	_bird_timer.timeout.connect(_on_bird_timer)
	add_child(_bird_timer)

const STABLE_PITCH := ["join", "collect", "pet", "cheer", "warp"]

## Soft running footstep: a short low thud with a whisper of noise.
func _step() -> AudioStreamWAV:
	var seconds := 0.09
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var smooth := 0.0
	for i in count:
		var t := float(i) / RATE
		smooth = smooth * 0.9 + (randf() * 2.0 - 1.0) * 0.1
		var env := exp(-t * 42.0) * minf(1.0, i / (0.002 * RATE))
		buf[i] = (sin(TAU * 92.0 * t) * 0.55 + smooth * 0.6) * env
	return _to_wav(buf, 0.5)

## Deep rumble + noise burst for the boom blocks.
func _thoomp() -> AudioStreamWAV:
	# Deep launch whump: fast downward sweep + breath of noise.
	var seconds := 0.5
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	var smooth := 0.0
	for i in count:
		var t := float(i) / RATE
		var frac := t / seconds
		phase += TAU * lerpf(220.0, 55.0, minf(frac * 2.0, 1.0)) / RATE
		smooth = smooth * 0.85 + (randf() * 2.0 - 1.0) * 0.15
		var env := exp(-t * 6.0) * minf(1.0, i / (0.004 * RATE))
		buf[i] = (sin(phase) * 0.9 + smooth * 0.35) * env
	return _to_wav(buf, 0.7)

## AN EXPLOSION.
##
## WHAT MAKES A BANG SOUND LIKE A BANG IS THE FILTER FALLING, not the
## noise and not a bass note under it. Air punches out, the high end dies
## almost immediately, and what is left rolls away downwards. Get that
## sweep right and plain white noise becomes an explosion; get it wrong
## and no amount of low end will save it.
##
## Two earlier goes at this both got it wrong in the same way. The first
## was a burst of noise with a 60 Hz thump: thin, because there was
## nothing below the thump and nothing shaping the noise. The second put a
## pure sine underneath — and a pure sine IS a drone, which is exactly
## what it sounded like: hiss with a hum bolted on.
##
## So there is no oscillator here at all. Every layer is noise through a
## filter, which is what an explosion physically is:
##
##   CRACK  a few milliseconds of high-passed noise — the punch of air
##   BODY   noise through a cutoff falling 3 kHz to 90 Hz in a third of a
##          second, which is the sound of the bang itself
##   TAIL   noise held under about 100 Hz, decaying slowly — the roll
##
## Cascaded one-pole filters, two deep, because a single pole is a gentle
## tilt and tilted noise still sounds like noise. And a little saturation
## on the way out for grit: an explosion is not a clean signal.
func _boom() -> AudioStreamWAV:
	var seconds := 1.9
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var body1 := 0.0
	var body2 := 0.0
	var tail1 := 0.0
	var tail2 := 0.0
	var hp := 0.0
	var was := 0.0
	for i in count:
		var t := float(i) / RATE
		var n := randf() * 2.0 - 1.0
		# THE SWEEP. Everything else is dressing.
		var cut := 90.0 + 2900.0 * exp(-t * 9.0)
		var a := 1.0 - exp(-TAU * cut / RATE)
		body1 += (n - body1) * a
		body2 += (body1 - body2) * a
		var body := body2 * exp(-t * 3.0)
		# The roll, well under everything else and slow to go.
		var low := 52.0 + 48.0 * exp(-t * 1.3)
		var b := 1.0 - exp(-TAU * low / RATE)
		tail1 += (n - tail1) * b
		tail2 += (tail1 - tail2) * b
		var tail := tail2 * exp(-t * 1.15)
		# The punch of air, gone in a few milliseconds.
		hp = 0.86 * (hp + n - was)
		was = n
		var crack := hp * exp(-t * 120.0)
		buf[i] = tanh((body * 3.4 + tail * 9.0 + crack * 0.45) * 1.5)
	return _to_wav(buf, 0.85)

## THE KNOCKOUT: a long, deep roll under everything else.
##
## Noise, not a tone, for the same reason the explosion is — a swept sine
## is a drone however low you put it, and it sat under the game humming.
## This is the same idea as the explosion's tail with the bang taken off:
## noise held under about 70 Hz, slow in, slow out, so it swells and rolls
## away rather than starting and stopping.
##
## Deliberately keeps a little above 120 Hz. A laptop speaker cannot
## reproduce 30 Hz at all, so a pure sub is silence for half the people
## playing; the filter leaves enough of an edge to be heard on anything
## while the weight is there for whoever has the speakers for it.
func _rumble() -> AudioStreamWAV:
	var seconds := 2.2
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var r1 := 0.0
	var r2 := 0.0
	for i in count:
		var t := float(i) / RATE
		var n := randf() * 2.0 - 1.0
		var cut := 38.0 + 60.0 * exp(-t * 1.6)
		var a := 1.0 - exp(-TAU * cut / RATE)
		r1 += (n - r1) * a
		r2 += (r1 - r2) * a
		var env := minf(1.0, t / 0.10) * exp(-maxf(0.0, t - 0.30) * 1.5)
		buf[i] = tanh(r2 * 11.0 * env)
	return _to_wav(buf, 0.9)

## Crowd cheer: a noise swell plus a few descending whoops and claps.
func _cheer() -> AudioStreamWAV:
	var seconds := 1.9
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var smooth := 0.0
	for i in count:
		var t := float(i) / RATE
		smooth = smooth * 0.8 + (randf() * 2.0 - 1.0) * 0.2
		var env := minf(t / 0.3, 1.0) * exp(-maxf(0.0, t - 0.7) * 2.2)
		buf[i] += smooth * env * 0.8
	for whoop in 3:
		var start := 0.08 + whoop * 0.17
		var whoop_len := int(0.34 * RATE)
		var start_i := int(start * RATE)
		var phase := 0.0
		for i in whoop_len:
			var frac := float(i) / whoop_len
			phase += TAU * lerpf(880.0 - whoop * 90.0, 470.0, frac) / RATE
			var env := sin(PI * frac)
			if start_i + i < count:
				buf[start_i + i] += sin(phase) * env * 0.5
	for clap in 14:
		var start_i := int((0.15 + randf() * 1.3) * RATE)
		var clap_len := int(0.009 * RATE)
		for i in clap_len:
			if start_i + i < count:
				buf[start_i + i] += (randf() * 2.0 - 1.0) * (1.0 - float(i) / clap_len) * 0.6
	return _to_wav(buf, 0.6)

## Apply the player's game-volume setting. Master bus rather than each
## player, so it covers the ambience and anything added later for free.
func apply_volume() -> void:
	var pct := clampi(int(Game.video.get("volume", 100)), 0, 100)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, pct <= 0)
	# Percent to decibels, with 100% meaning "unchanged" rather than "loud".
	AudioServer.set_bus_volume_db(bus,
		-80.0 if pct <= 0 else linear_to_db(float(pct) / 100.0))

func play(clip: String, volume_db := 0.0, pitch := 0.0) -> void:
	if _players.is_empty() or not _streams.has(clip):
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	var stream: Variant = _streams[clip]
	if stream is Array:
		stream = stream[randi() % (stream as Array).size()]
	player.stream = stream
	player.volume_db = volume_db
	if pitch > 0.0:
		player.pitch_scale = pitch
	else:
		player.pitch_scale = 1.0 if clip in STABLE_PITCH else randf_range(0.9, 1.1)
	player.play()

## "birds" is a scheduler, not a loop: one-shot chirps at random intervals
## and pitches, so the forest never sings in time.
func play_ambient(clip: String) -> void:
	if clip == _current_ambient:
		return
	_current_ambient = clip
	if _ambient_player == null:
		return
	_bird_timer.stop()
	if clip == "birds":
		_ambient_player.stop()
		_on_bird_timer()
		return
	if clip.is_empty() or not _ambients.has(clip):
		_ambient_player.stop()
		return
	_ambient_player.stream = _ambients[clip]
	_ambient_player.play()

func _on_bird_timer() -> void:
	if _current_ambient != "birds":
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = _chirps[randi() % _chirps.size()]
	player.volume_db = randf_range(-22.0, -14.0)
	player.pitch_scale = randf_range(0.8, 1.3)
	player.play()
	_bird_timer.start(randf_range(0.8, 5.5))

func _notes(notes: Array, volume: float, timbre := "bell") -> AudioStreamWAV:
	var spec: Dictionary = TIMBRES[timbre]
	var ring: float = spec.ring
	var total := ring
	for note: Array in notes:
		total += note[1]
	var count := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var start := 0.0
	for note: Array in notes:
		if note[0] > 0.0:
			_render_note(buf, start, note[0], spec)
		start += note[1]
	return _to_wav(buf, volume)

func _to_wav(buf: PackedFloat32Array, volume: float, loop := false) -> AudioStreamWAV:
	var count := buf.size()
	var peak := 0.0001
	for sample in buf:
		peak = maxf(peak, absf(sample))
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(buf[i] / peak * volume, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = count
	return wav

func _render_note(buf: PackedFloat32Array, start_s: float, freq: float, spec: Dictionary) -> void:
	var ring: float = spec.ring
	var h2: float = spec.h2
	var h3: float = spec.h3
	var start_i := int(start_s * RATE)
	var length := mini(int(ring * RATE), buf.size() - start_i)
	var decay := 5.0 / ring
	var is_thump: bool = h2 == 0.0 and h3 == 0.0
	var w := TAU * freq
	for s in length:
		var t := float(s) / RATE
		var env := exp(-t * decay) * minf(1.0, s / (0.003 * RATE))
		var value: float
		if is_thump:
			value = sin(w * t * (1.0 + 0.6 * exp(-t * 25.0)))
		else:
			value = sin(w * t) \
				+ 0.4 * sin(w * 1.006 * t) \
				+ h2 * sin(w * 2.0 * t) * exp(-t * decay * 0.8) \
				+ h3 * sin(w * 3.01 * t) * exp(-t * decay * 1.6)
		buf[start_i + s] += value * env

func _crickets(chirp_count: int) -> AudioStreamWAV:
	var seconds := 4.0
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	for chirp in chirp_count:
		var start := randf() * (seconds - 0.4)
		var freq := 4100.0 + randf() * 500.0
		for pulse in 3:
			var pulse_start := int((start + pulse * 0.07) * RATE)
			var pulse_len := int(0.035 * RATE)
			for i in pulse_len:
				var t := float(i) / RATE
				var env := sin(PI * i / pulse_len)
				if pulse_start + i < buf.size():
					buf[pulse_start + i] += sin(TAU * freq * t) * env * 0.4
	return _to_wav(buf, 0.5, true)

func _birds() -> AudioStreamWAV:
	var seconds := 4.0
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	for chirp in 6:
		var start := randf() * (seconds - 0.3)
		var f_start := 1900.0 + randf() * 900.0
		var f_end := f_start * (0.75 + randf() * 0.5)
		var chirp_len := int((0.09 + randf() * 0.08) * RATE)
		var chirp_start := int(start * RATE)
		var phase := 0.0
		for i in chirp_len:
			var frac := float(i) / chirp_len
			phase += TAU * lerpf(f_start, f_end, frac) / RATE
			var env := sin(PI * frac)
			if chirp_start + i < buf.size():
				buf[chirp_start + i] += sin(phase) * env * 0.5
	return _to_wav(buf, 0.4, true)

## One randomized birdsong phrase (1-3 sweeping chirps).
func _chirp() -> AudioStreamWAV:
	var seconds := 0.7
	var buf := PackedFloat32Array()
	buf.resize(int(seconds * RATE))
	var chirp_count := 1 + randi() % 3
	for chirp in chirp_count:
		var start := chirp * randf_range(0.14, 0.24)
		var f_start := 1800.0 + randf() * 1200.0
		var f_end := f_start * randf_range(0.7, 1.35)
		var chirp_len := int(randf_range(0.06, 0.13) * RATE)
		var chirp_start := int(start * RATE)
		var phase := 0.0
		for i in chirp_len:
			var frac := float(i) / chirp_len
			phase += TAU * lerpf(f_start, f_end, frac) / RATE
			var env := sin(PI * frac)
			if chirp_start + i < buf.size():
				buf[chirp_start + i] += sin(phase) * env * 0.5
	return _to_wav(buf, 0.4)

## Wobbly sheep bleat.
func _baa() -> AudioStreamWAV:
	var seconds := 0.55
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / RATE
		var env := sin(PI * t / seconds)
		var vibrato := 6.0 * sin(TAU * 7.0 * t)
		buf[i] = sin(TAU * 285.0 * t + vibrato) * env * (0.7 + 0.3 * sin(TAU * 14.0 * t))
	return _to_wav(buf, 0.5)

## Nasal descending duck quack.
func _quack() -> AudioStreamWAV:
	var seconds := 0.22
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / RATE
		var frac := t / seconds
		phase += TAU * lerpf(260.0, 170.0, frac) / RATE
		var env := sin(PI * frac)
		buf[i] = (sin(phase) + 0.5 * sin(phase * 2.0) + 0.3 * sin(phase * 3.0)) * env
	return _to_wav(buf, 0.5)

## Two quick hen pops.
func _cluck() -> AudioStreamWAV:
	var seconds := 0.3
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for pop in 2:
		var start := int(pop * 0.14 * RATE)
		var pop_len := int(0.06 * RATE)
		var phase := 0.0
		for i in pop_len:
			var frac := float(i) / pop_len
			phase += TAU * lerpf(700.0, 350.0, frac) / RATE
			if start + i < count:
				buf[start + i] += sin(phase) * exp(-frac * 5.0)
	return _to_wav(buf, 0.5)

## Low two-note frog croak.
func _ribbit() -> AudioStreamWAV:
	var seconds := 0.4
	var count := int(seconds * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for i in count:
		var t := float(i) / RATE
		var freq := 105.0 if t < 0.2 else 140.0
		var syllable := fmod(t, 0.2) / 0.2
		var env := sin(PI * syllable)
		var buzz := 1.0 if fmod(t * 42.0, 1.0) < 0.6 else 0.35
		buf[i] = sin(TAU * freq * t) * env * buzz
	return _to_wav(buf, 0.55)

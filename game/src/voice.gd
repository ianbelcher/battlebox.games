extends Node
## Voice chat, browser only.
##
## The audio itself lives in web/voice.js — Godot's WebRTC binding carries
## data channels and cannot be given a microphone track, so the browser
## does the capture, the Opus, the echo cancellation and the jitter buffer,
## all of which are horrible by hand. This script is the part that decides
## WHO should be connected to whom and carries the handshake.
##
## ONE ENDPOINT PER MACHINE. A split-screen couch has four seats and ONE
## microphone, so a per-seat voice identity would be a fiction — and a
## harmful one, because it is what a team-only channel would have to be
## built on. Two children on one sofa are already talking to each other;
## pretending the game can separate them would mean promising a nine-year-
## old that the other team cannot hear, which the hardware cannot keep.
##
## So: no team channels, no proximity. Everyone in the world is in one
## call, which is what it actually is. Voice is keyed on the PEER id —
## the game's player ids are "peer:slot", so this is the same identity with
## the seat dropped.
##
## Open mic with a mute, not push-to-talk: a five-year-old is not going to
## hold a key down with the hand that is not driving.
##
## THERE ARE TWO IMPLEMENTATIONS behind one switch.
##
## In a browser, voice.js does everything and this file only decides who
## talks to whom. On the NATIVE builds there is no such luxury: Godot's
## WebRTC classes need a GDExtension that standard builds do not ship, so
## peer-to-peer is not on the table without shipping binaries per platform.
##
## So native captures the microphone itself and sends compressed audio over
## the WebSocket that is already there, and the server relays it. That
## costs the server bandwidth where the browser path costs it none — but
## the numbers are small (one talker is 16 KB/s, and a four-machine room at
## full argument is under 200 KB/s in total) and it works everywhere the
## game already works, with nothing extra to install.

signal state_changed

## Off until the machine says otherwise — and it does, by default: see
## `Game.video.voice_on` and `_auto_join()` below. The browser prompts for
## the microphone as soon as we join, which is the point. Saying no is a
## normal answer and lands on "denied"; nothing else changes.
var state := "off"          # off / asking / on / denied / unsupported
var muted := false
var connected: Array = []   # peer ids we can currently hear
var error := ""

var _poll := 0.0
const POLL_SECONDS := 0.25

func _ready() -> void:
	# Nothing here exists outside a browser. The native builds were dropped
	# on purpose; the server must never touch any of it.
	# A dedicated server has no ears and no microphone.
	if OS.get_environment("WORLD_ROLE") == "server" \
			or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	Game.video_changed.connect(apply_volume)

## Voice exists on every build now; only the machinery differs.
func available() -> bool:
	return true

func _web() -> bool:
	return OS.has_feature("web")

## Ask for the microphone and join the call.
func enable() -> void:
	if _web():
		# The bridge is injected into Godot's generated index.html by the
		# Docker build. A page built any other way has no `window.BBVoice`,
		# and the old code still set "asking" — so the menu sat on "Asking
		# for the microphone…" for the rest of the session with nothing
		# behind it. Now it says what is actually true.
		if str(JavaScriptBridge.eval("window.BBVoice ? '1' : ''", true)) != "1":
			state = "unsupported"
			error = "this page was built without voice support"
			state_changed.emit()
			return
		JavaScriptBridge.eval("BBVoice.enable(%d)"
			% multiplayer.get_unique_id(), true)
		state = "asking"
	else:
		_native_enable()
	apply_volume()
	state_changed.emit()

func disable() -> void:
	if _web():
		JavaScriptBridge.eval("window.BBVoice && BBVoice.disable()", true)
	else:
		_native_disable()
	state = "off"
	connected.clear()
	state_changed.emit()

## Have we already had a go at joining on this connection?
var _auto_tried := false

## Whether this machine WANTS to be in the call, remembered across runs.
## The menu writes it; `_auto_join()` acts on it.
func set_wanted(on: bool) -> void:
	Game.video["voice_on"] = on
	Game.video_changed.emit()
	_auto_tried = on
	if on:
		enable()
	else:
		disable()

## JOIN THE CALL BY OURSELVES, because nobody is going to go looking for
## the setting. Voice used to be off until you found a button on a tab
## called "Video", which for a nine-year-old is the same as not existing.
##
## It has to WAIT FOR THE CONNECTION rather than fire at startup.
## `enable()` hands our peer id to voice.js, which decides who offers to
## whom by comparing ids — so joining before this machine has its real id
## puts everybody on 1 (or 0), the tie-break never resolves and no call is
## ever set up. Polled rather than hung off a signal so that a reconnect
## brings voice back too.
func _auto_join() -> void:
	var live := multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() \
			== MultiplayerPeer.CONNECTION_CONNECTED \
		and multiplayer.get_unique_id() > 1
	if not live:
		_auto_tried = false     # next connection gets a fresh go
		return
	if _auto_tried or state != "off":
		return
	if not bool(Game.video.get("voice_on", true)):
		return
	# NOT UNTIL THE PLAYER HAS ACTUALLY ARRIVED. While the browser's intro
	# video is still up, nobody has touched this page — and asking for a
	# microphone then is wrong three separate ways:
	#
	#  - Chrome expects a user gesture before a permission prompt, and
	#    treats one that comes without it far less kindly.
	#  - Bringing up getUserMedia and the WebRTC stack stalls enough to
	#    put a visible stutter through the video that is playing.
	#  - And it means a live microphone on a page somebody has done
	#    nothing to but open. Someone could load this and be heard before
	#    they were ever in the game. That one is not a polish issue.
	#
	# Dismissing the intro IS the interaction, so this waits for it.
	if Game.boot_overlay_up:
		return
	_auto_tried = true
	enable()

func set_muted(m: bool) -> void:
	muted = m
	if _web():
		JavaScriptBridge.eval("window.BBVoice && BBVoice.setMuted(%s)"
			% ("true" if m else "false"), true)
	state_changed.emit()

func toggle_muted() -> void:
	set_muted(not muted)

## How loud other people are, as a percentage. Kept with the other
## per-machine settings, since it is a property of this room's speakers.
func apply_volume() -> void:
	var pct := clampi(int(Game.video.get("voice_volume", 100)), 0, 100)
	if _web():
		JavaScriptBridge.eval("window.BBVoice && BBVoice.setVolume(%d)"
			% pct, true)
		return
	var db := -80.0 if pct <= 0 else linear_to_db(float(pct) / 100.0)
	for player: AudioStreamPlayer in _heard.values():
		player.volume_db = db

## A handshake message arrived for us from another machine.
func on_signal(from_peer: int, payload: String) -> void:
	if not _web():
		return   # native carries audio itself; there is no handshake
	# Through JSON so a quote in an SDP cannot break out of the call.
	JavaScriptBridge.eval("window.BBVoice && BBVoice.onSignal(%d, %s)"
		% [from_peer, JSON.stringify(payload)], true)

func _process(delta: float) -> void:
	_auto_join()
	if not _web():
		_native_process()
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = POLL_SECONDS
	_sync_peers()
	_drain_outbox()
	_read_status()

## Everyone else in the world, one entry per MACHINE.
##
## A client only ever sees the server in `multiplayer.get_peers()`, so the
## roster is what tells us who else is out there: its ids are "peer:slot",
## and the peer half is the machine.
func _sync_peers() -> void:
	if state != "on":
		return
	var me := multiplayer.get_unique_id()
	var seen: Dictionary = {}
	for id: String in Game.roster.keys():
		var peer := int(str(id).split(":")[0])
		if peer > 1 and peer != me:
			seen[peer] = true
	var ids: Array = seen.keys()
	ids.sort()
	var csv := ",".join(PackedStringArray(ids.map(func(p: int) -> String:
		return str(p))))
	JavaScriptBridge.eval("window.BBVoice && BBVoice.setPeers(%s)"
		% JSON.stringify(csv), true)

func _drain_outbox() -> void:
	var raw := str(JavaScriptBridge.eval(
		"window.BBVoice ? BBVoice.drain() : '[]'", true))
	if raw.is_empty() or raw == "[]":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Array):
		return
	var world: Node = Game.world
	if world == null:
		return
	for entry: Variant in parsed:
		if not (entry is Dictionary):
			continue
		var msg: Dictionary = entry
		world.sv_voice_signal.rpc_id(1, int(msg.get("to", 0)),
			str(msg.get("data", "")))

func _read_status() -> void:
	var raw := str(JavaScriptBridge.eval(
		"window.BBVoice ? BBVoice.status() : ''", true))
	if raw.is_empty():
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return
	var info: Dictionary = parsed
	var new_state := str(info.get("state", state))
	var new_conn: Array = info.get("connected", [])
	var changed: bool = new_state != state or new_conn.size() != connected.size()
	state = new_state
	muted = bool(info.get("muted", muted))
	connected = new_conn
	error = str(info.get("error", ""))
	if changed:
		state_changed.emit()

## What the menu shows on the button.
func summary() -> String:
	match state:
		"on":
			var others := connected.size()
			if muted:
				return "Muted · %d connected" % others
			return "On · %d connected" % others
		"asking":
			return "Asking for the microphone…"
		"denied":
			return "Microphone blocked by the browser"
		"unsupported":
			return "Not available here"
		_:
			return "Off"

# ------------------------------------------------------------------
# The native path
# ------------------------------------------------------------------
##
## Capture the microphone, squeeze it down, and post it through the server.
##
## Sent as 16 kHz mono G.711 µ-law: 16 KB a second while somebody is
## actually talking. That is telephone quality, which is the right target —
## these are children saying "I'm behind the wall", not a podcast — and it
## is one byte per sample with a dozen lines of arithmetic, where Opus
## would mean shipping a GDExtension for three platforms.
##
## Nothing is sent while nobody is speaking. Open mic without that would
## relay room tone from every machine forever.

## What goes over the wire. Anything above this and the bandwidth stops
## being free; anything below and it sounds like a drive-through.
const WIRE_HZ := 16000
## ~40 ms a packet: 25 a second rather than 50, for the same audio.
const FRAME_SAMPLES := 640
## Below this the microphone is a quiet room, not a person.
const SPEAK_THRESHOLD := 0.012
## Keep sending for a moment after they stop, or every sentence loses its
## last syllable and quiet talkers get chopped up.
const HANGOVER_SECONDS := 0.45

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mic_bus := -1
var _pending: PackedFloat32Array = PackedFloat32Array()
var _hangover := 0.0
var _heard: Dictionary = {}        # peer id -> AudioStreamPlayer

func _native_enable() -> void:
	if _mic_player != null:
		state = "on"
		return
	# A bus of its own, MUTED. Routed to Master you hear yourself with a
	# frame of delay, which is unbearable and sounds like a broken game.
	_mic_bus = AudioServer.bus_count
	AudioServer.add_bus(_mic_bus)
	AudioServer.set_bus_name(_mic_bus, "Mic")
	AudioServer.set_bus_mute(_mic_bus, true)
	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_mic_bus, _capture)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Mic"
	add_child(_mic_player)
	_mic_player.play()
	state = "on"
	error = ""

func _native_disable() -> void:
	if _mic_player != null:
		_mic_player.queue_free()
		_mic_player = null
	if _mic_bus > 0 and _mic_bus < AudioServer.bus_count:
		AudioServer.remove_bus(_mic_bus)
	_mic_bus = -1
	_capture = null
	_pending = PackedFloat32Array()
	for player: AudioStreamPlayer in _heard.values():
		player.queue_free()
	_heard.clear()

func _native_process() -> void:
	if state != "on" or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	# Godot mixes at whatever the device wants (usually 44.1 or 48 kHz);
	# the wire is 16. Averaging the samples we drop rather than picking one
	# is the difference between a voice and a kazoo.
	var stride := maxf(float(AudioServer.get_mix_rate()) / float(WIRE_HZ), 1.0)
	var block := _capture.get_buffer(available)
	var pos := 0.0
	while int(pos) < block.size():
		var first := int(pos)
		var last := mini(int(pos + stride), block.size())
		var sum := 0.0
		for i in range(first, maxi(last, first + 1)):
			if i < block.size():
				sum += (block[i].x + block[i].y) * 0.5
		_pending.append(sum / float(maxi(last - first, 1)))
		pos += stride

	while _pending.size() >= FRAME_SAMPLES:
		var frame := _pending.slice(0, FRAME_SAMPLES)
		_pending = _pending.slice(FRAME_SAMPLES)
		_send_frame(frame)
	_prune_heard()

## Drop the playback for anyone who has left, and keep `connected` honest
## so the menu can say how many people are actually on the call. Without
## this, a machine that quits leaves a silent player node behind forever
## and the count only ever goes up.
func _prune_heard() -> void:
	var here: Dictionary = {}
	for id: String in Game.roster.keys():
		here[int(str(id).split(":")[0])] = true
	for peer: int in _heard.keys().duplicate():
		if not here.has(peer):
			forget_peer(peer)
	var now_connected: Array = _heard.keys()
	if now_connected.size() != connected.size():
		connected = now_connected
		state_changed.emit()

func _send_frame(frame: PackedFloat32Array) -> void:
	var loudest := 0.0
	for v: float in frame:
		loudest = maxf(loudest, absf(v))
	if loudest >= SPEAK_THRESHOLD:
		_hangover = HANGOVER_SECONDS
	else:
		_hangover -= float(FRAME_SAMPLES) / float(WIRE_HZ)
	if muted or _hangover <= 0.0:
		return
	var world: Node = Game.world
	if world == null or not multiplayer.has_multiplayer_peer():
		return
	var bytes := PackedByteArray()
	bytes.resize(frame.size())
	for i in frame.size():
		bytes[i] = _ulaw_encode(frame[i])
	world.sv_voice_audio.rpc_id(1, bytes)

## Somebody else's voice arrived. Unreliable, so frames can be missing —
## which is fine and is the point: a late packet is worse than a lost one.
func on_audio(from_peer: int, bytes: PackedByteArray) -> void:
	if _web() or state != "on":
		return
	var player: AudioStreamPlayer = _heard.get(from_peer)
	if player == null:
		player = AudioStreamPlayer.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = float(WIRE_HZ)
		# Enough to ride out a hiccup, short enough not to sound like a
		# delay when somebody answers you.
		gen.buffer_length = 0.25
		player.stream = gen
		add_child(player)
		player.play()
		_heard[from_peer] = player
		apply_volume()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	if playback == null:
		return
	var room := playback.get_frames_available()
	for i in mini(bytes.size(), room):
		var v := _ulaw_decode(bytes[i])
		playback.push_frame(Vector2(v, v))

func forget_peer(peer_id: int) -> void:
	var player: AudioStreamPlayer = _heard.get(peer_id)
	if player != null:
		player.queue_free()
		_heard.erase(peer_id)

# --- G.711 µ-law. Standard, and the reason a telephone sounds like a
# --- telephone rather than like eight-bit noise: it spends its precision
# --- where quiet speech lives instead of spreading it evenly.
const _ULAW_BIAS := 0.0001

func _ulaw_encode(sample: float) -> int:
	var s := clampf(sample, -1.0, 1.0)
	var sign := 0x80 if s < 0.0 else 0x00
	var mag := absf(s)
	var compressed := log(1.0 + 255.0 * mag) / log(256.0)
	var q := int(round(compressed * 127.0))
	return (sign | (127 - clampi(q, 0, 127))) & 0xFF

func _ulaw_decode(byte: int) -> float:
	var sign := -1.0 if (byte & 0x80) != 0 else 1.0
	var q := 127 - (byte & 0x7F)
	var compressed := float(clampi(q, 0, 127)) / 127.0
	var mag := (pow(256.0, compressed) - 1.0) / 255.0
	return sign * mag

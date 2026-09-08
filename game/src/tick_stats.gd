class_name TickStats
extends RefCounted
## WHERE THE SERVER'S FRAME GOES, for WORLD_NETSTAT=1.
##
## "The server is slow" is not a report anybody can act on; "bots_goal is
## 190 ms of every second, and one frame of it took 26" is. Every
## subsystem the world ticks laps this clock, and BotDirector prints the
## totals alongside its packet counts every five seconds.
##
## Two numbers per lap: the total over the window, and the single longest
## lap in it. An average of two milliseconds hides the one frame that
## took a hundred and forty, and that frame is the stutter somebody
## noticed.
##
## Off, every call is one boolean test. It has to be: the laps sit inside
## the per-bot loop.

var on := false
var usec: Dictionary = {}
var worst_usec: Dictionary = {}
var _at := 0

func _init(enabled: bool) -> void:
	on = enabled

func start() -> void:
	if on:
		_at = Time.get_ticks_usec()

func lap(what: String) -> void:
	if not on:
		return
	var now := Time.get_ticks_usec()
	var took := now - _at
	usec[what] = int(usec.get(what, 0)) + took
	if took > int(worst_usec.get(what, 0)):
		worst_usec[what] = took
	_at = now

## The window's report, in milliseconds per second of wall clock and the
## longest single lap of anything that ever took five milliseconds — then
## the slate is wiped for the next window.
func report(window_seconds: float) -> PackedStringArray:
	var lines: PackedStringArray = []
	var parts: PackedStringArray = []
	var seconds := maxf(window_seconds, 0.001)
	for what: String in usec:
		parts.append("%s=%d" % [what, int(int(usec[what]) / 1000.0 / seconds)])
	lines.append("TICK ms/s: %s" % " ".join(parts))
	var spikes: PackedStringArray = []
	for what: String in worst_usec:
		var took := int(worst_usec[what])
		if took >= 5000:
			spikes.append("%s=%d" % [what, took / 1000])
	if not spikes.is_empty():
		lines.append("TICK longest ms: %s" % " ".join(spikes))
	usec.clear()
	worst_usec.clear()
	return lines

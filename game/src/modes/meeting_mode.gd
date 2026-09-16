class_name MeetingMode
extends GameMode
## A MEETING: the office floor, everybody's microphone on, and nothing to
## win.
##
## The rest of the modes in this folder are games — a storm, a flag, a
## rising tide. This one is the platform with the game taken off it, the
## same way BuildMode is, and then three things said about it that
## BuildMode does not say:
##
##   NOBODY IS A COMPUTER PLAYER. Every other mode fills the seats people
##   are not in, because a game the size it was made is better than a game
##   with one child in it. A meeting is the opposite: the people in the
##   room ARE the meeting, and eleven bots wandering between the desks
##   while six people are trying to talk is not company, it is noise. See
##   wants_bots(), which is the seam this needed on the platform.
##
##   NOBODY IS ARMED. The kit is the sprayer, the flare and the grapple —
##   marking a spot, pointing at a spot, and getting across a floor plate
##   quickly. No sword and no shooters: the first thing anybody would do
##   with a sword in a meeting is the last thing the meeting needed.
##
##   IT OPENS ON THE OFFICE. A meeting on a desert island is a perfectly
##   good joke and you can still choose it; it is just not what somebody
##   who picked "Meeting" meant.
##
## Voice is already on by default and already carries the whole room —
## see voice.gd and web/voice.js — so there is nothing here about audio.
## That was the part that would have been hard and it was built years
## before anybody wanted a meeting room to put it in.

func _init() -> void:
	key = "meeting"
	label = "Meeting"
	note = "An office floor, and everyone can talk"

func kicker() -> String:
	return "MEETING"

func wants_bots() -> bool:
	return false

func suggests_map() -> String:
	return "office"

## Marking, pointing, and getting about. See the note at the top.
func kit(_world: Node, _id: String) -> Array:
	return [Weapons.SPRAYER, Weapons.FLARE, Weapons.GRAPPLE]

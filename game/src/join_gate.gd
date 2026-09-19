class_name JoinGate
extends RefCounted
## Decides whether a join button being down right now is somebody asking
## to join, or a leftover from pressing something else.
##
## SEATS ARE TAKEN ON PURPOSE, BY THE DEVICE THAT WANTS ONE. The keyboard
## kept sitting itself down: whoever set the game up on it — Play on the
## lobby screen, a button in the world menu, the final table dismissed —
## got a player, and it had to be kicked before the child holding the
## controller could have that seat. Space is both the keyboard's join
## button and the key that presses a focused button, and the poller took
## the first frame it saw Space down as a press: on arrival it had never
## seen the key before, and while a menu was open it recorded "not
## joining" rather than "held", so the moment the menu shut the same press
## read as brand new.
##
## So a press only counts if it STARTED while joining was open. Anything
## held when the gate lifts — the world appearing, a menu closing — has
## to be let go and pressed again.

## Device keys that were down while joining was closed, and have not been
## released since.
var _needs_release: Dictionary = {}
## Bumped by hold_all(); a key last looked at under an older epoch has not
## been seen since the gate last lifted.
var _epoch := 0
var _seen_epoch: Dictionary = {}

## Treat every device as unseen: whatever is held at its next look is a
## leftover. Call when the join screen appears and whenever a menu that
## was swallowing presses goes away.
func hold_all() -> void:
	_epoch += 1

## True when `pressed` is a join press this device made deliberately.
## `blocked` means joining is closed right now (a menu is open).
func press_counts(key: String, pressed: bool, blocked: bool) -> bool:
	var stale := int(_seen_epoch.get(key, -1)) != _epoch
	_seen_epoch[key] = _epoch
	if not pressed:
		_needs_release.erase(key)
		return false
	if blocked or stale:
		_needs_release[key] = true
		return false
	return not _needs_release.has(key)

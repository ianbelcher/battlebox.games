class_name FlyRule
## WHETHER SOMEBODY IN THE AIR STAYS IN THE AIR.
##
## Being knocked out lifts you ten blocks and hands you wings, so you can
## get out of the fray and fly to a team-mate to be picked up. That is
## deliberate and it works. The question this answers is the one AFTER
## it: you have been picked up, you are back in the round — do you keep
## the wings?
##
## No. If the game has flying switched off, being revived puts you back
## under the same rules as everybody else, and flying home from a knockout
## must not be a way of buying flight for the rest of the round.
##
## The check lived inline in player.gd and read the WORLD default,
## `world.client_fly`, rather than asking whether THIS player may fly.
## Flying is a per-player setting — it exists so the small ones can float
## out of trouble while everybody else plays on the ground — so the world
## default is the wrong question whenever anybody has been singled out,
## and the answer is wrong in both directions: a player with flight turned
## off individually kept it, and a player granted it in a world that has
## it off lost it.

## True when flight continues, false when it is cancelled this frame.
##
## `allowed` is the per-player answer (WorldNode.fly_allowed_for), never
## the world default. `out_of_it` covers both knocked out and out of the
## round — the two states flying is FOR, and the two where no rule about
## people who are playing should apply.
static func keeps_flying(flying: bool, allowed: bool, in_a_raid: bool,
		out_of_it: bool) -> bool:
	if not flying:
		return false
	if out_of_it:
		return true          # the knocked-out may fly whatever the setting
	return allowed and not in_a_raid

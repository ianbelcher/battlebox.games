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

## THE FOUR ANSWERS a grown-up can give for everybody at once, and what
## each one means as a pair of defaults: one for the people, one for the
## computers.
##
## Two defaults rather than one because two of these cannot be said with a
## single switch. "Computers only" is how the bots get to come at a base
## over its wall while everybody at the table plays on the ground, and
## "humans only" is how the small ones get a way out of trouble without
## handing it to twenty bots.
##
## Both directions live here together on purpose. The menu has to turn an
## answer into settings when a button is pressed and settings back into an
## answer to light the right button, and two mappings written apart drift
## until the button you pressed is not the one that lights up.
const ANSWERS := ["everyone", "nobody", "computers", "humans"]

static func people_fly(answer: String) -> bool:
	return answer == "everyone" or answer == "humans"

static func computers_fly(answer: String) -> bool:
	return answer == "everyone" or answer == "computers"

## Which answer is in force, given the two defaults.
static func answer_for(people: bool, computers: bool) -> String:
	if people and computers:
		return "everyone"
	if computers:
		return "computers"
	if people:
		return "humans"
	return "nobody"

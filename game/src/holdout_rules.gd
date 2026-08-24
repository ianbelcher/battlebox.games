class_name HoldoutRules
## LAST FLAG STANDING: capture the flag, except losing your flag puts your
## whole team out of the round.
##
## It turns capture the flag inside out. In capture the flag your own base
## is a place you keep coming back to; here it is the only thing you have,
## and a single successful raid ends you. That makes defending worth more
## than attacking, which is the point of it — a game about building
## something you can hold rather than about running back and forth.
##
## THE ROUND ENDS when one team is left, or when the clock runs out. Both
## are ordinary outcomes: a stalemate between two well-dug-in teams is a
## real result and not a failure, so it scores.
##
## SIX POINTS ARE SHARED between whoever is still standing, and only if
## there are few enough of them to make it an achievement:
##
##   1 team left   6 each     they won it
##   2 teams       3 each     they both held
##   3 teams       2 each     a crowd, but everyone dug in
##   4 or more     0 each     nobody was really under threat
##
## Six because it divides by one, two and three — which is what makes
## "share the round" mean equal shares rather than remainders.
##
## Pure and on its own so the table can be checked. A `--script` run has
## no autoloads, so anything needing the world cannot be tested at all.

const ROUND_POINTS := 6

## How long a round runs before the clock decides it, in minutes. Long
## enough to build something worth holding.
const ROUND_MINUTES := 10.0

## What each surviving team scores. Zero when too many survived for it to
## have been much of a siege.
static func share(survivors: int) -> int:
	if survivors <= 0:
		return 0
	if survivors > 3:
		return 0
	return ROUND_POINTS / survivors

## HOW MUCH OF A TEAM STAYS HOME. Nearly all of it: this mode is about
## holding a base, and a team that empties out to go raiding has already
## lost — there is no coming back from losing your flag.
##
## Never the whole team, though. A base nobody ever leaves is a base
## nobody can be knocked out of, and four teams sitting in four forts
## until the clock runs out is a draw by boredom. One in four goes out,
## with a minimum of one so somebody always does.
static func keepers(team_size: int) -> int:
	if team_size <= 1:
		return team_size
	return maxi(1, team_size - maxi(1, team_size / 4))

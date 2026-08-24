class_name TeamBoard
## FITTING A LOT OF TEAMS INTO A PANEL SIZED FOR A FEW.
##
## Both on-screen boards — the scoreline on the left and the standing
## counts under the map — drew one row per team at a fixed size. That is
## fine at four and unreadable at twenty: twenty rows of 14px runs off the
## bottom of the screen, over the map, and the numbers a player actually
## needs are somewhere in the middle of it.
##
## Two things have to give, and only two. The text gets smaller as the
## board gets longer, down to a floor — past that it is small enough to be
## no use and shrinking further just makes it invisible instead of
## cramped. And when it still will not fit, rows are dropped.
##
## WHICH rows are dropped is the part worth being careful about. Yours is
## never one of them, however badly your team is doing: the one line
## everybody looks for first is their own. Beyond that it is the order the
## caller ranked them in, which is "who is winning" — and the count of
## what was left out is shown, so a board with fifteen teams missing does
## not read as a game with five teams in it.

## The smallest the text is allowed to get. Below this it stops being
## information and becomes texture.
const MIN_PX := 9

## How big to draw the rows, given how many there are.
##
## Full size to six teams — the ordinary game, and it should not shrink
## for a case nobody is in. Then down a point per couple of teams to the
## floor.
static func font_px(teams: int, base: int) -> int:
	if teams <= 6:
		return base
	return maxi(MIN_PX, base - (teams - 6) / 2)

## How many rows there is room for, given the height a panel has and how
## tall a row is. At least one, because a board with nothing on it is
## worse than a board with your own team on it.
static func row_cap(height_px: float, row_px: int) -> int:
	return maxi(1, int(height_px / maxf(1.0, float(row_px))))

## The rows to draw, in order: the ranked list trimmed to fit, with your
## own team kept in whatever happens.
##
## `ranked` is team indices, best first. `mine` is your team, or -1 if you
## have none. Returns at most `cap` of them.
static func visible_rows(ranked: Array, mine: int, cap: int) -> Array:
	if cap <= 0 or ranked.is_empty():
		return []
	if ranked.size() <= cap:
		return ranked.duplicate()
	var out: Array = []
	for t: Variant in ranked:
		if out.size() >= cap:
			break
		out.append(t)
	if mine >= 0 and ranked.has(mine) and not out.has(mine):
		# Yours goes in at the bottom, displacing the last of the ranked
		# ones rather than being appended past the cap.
		out[out.size() - 1] = mine
	return out

## How many did not make it onto the board.
static func hidden(total: int, shown: int) -> int:
	return maxi(0, total - shown)

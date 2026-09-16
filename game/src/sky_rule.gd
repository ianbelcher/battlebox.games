class_name SkyRule
## WHAT THE SKY IS DOING, given the map — and which maps do not run a
## clock at all.
##
## Most worlds turn: the day advances, the sun sets, night falls and the
## lanterns start to matter. Two do not, for opposite reasons, and both
## reasons are about LIGHT RATHER THAN TIME:
##
##   caverns  is always night. Its plain is a roof over everything worth
##            seeing, and the halls underneath are lit by what glows in
##            them; a day up top would only wash out the plain.
##   office   is always mid-morning. Its ceiling panels are emissive
##            faces and NOT real lamps — twenty real ones in a room would
##            take the whole of ChunkView.light_cap and then flicker as
##            people walked about — so what actually lights the floor is
##            the sky coming in through the curtain wall. Let the clock
##            run and a meeting that started in daylight finishes in the
##            dark, which is nobody's idea of a meeting room.
##
## Pure, and here rather than on the world node, for the reason the rest
## of these files are: the world node holds the wire protocol and is
## already at the size the style test will not let it past, and a rule
## this small should be answerable without a world behind it.

## Day fraction: 0 midnight, 0.25 dawn, 0.5 noon. Mid-morning is sun well
## up and still low enough to come in at the windows.
const MORNING := 0.38
const MIDNIGHT := 0.0

## The maps whose clock does not move, and where it is pinned.
const HELD := {"caverns": MIDNIGHT, "office": MORNING}

## WHERE THIS MAP'S CEILING IS, or -1 for the outdoor ones that have
## none. Solid blocks at or above it are meshed into their own surface and
## put on RenderLayers.ROOF, which the orbit camera declines to draw —
## without that, a map with a roof on it renders as a grey plane with the
## player somewhere underneath.
##
## Here rather than in the mesher because it is a fact about a MAP, and
## this is already the file that knows which maps are not landscapes.
static func roof_y(theme: String) -> int:
	return WorldGen.OFFICE_CEIL_Y if theme == "office" else -1

## Does this map's clock move at all?
static func holds_still(theme: String) -> bool:
	return HELD.has(theme)

## Is it night here whatever the hour? The renderer asks, because night
## is more than a clock reading: it swaps what the ambient comes from.
static func always_night(theme: String) -> bool:
	return theme == "caverns"

## Is it daylight here whatever the hour?
static func holds_daylight(theme: String) -> bool:
	return holds_still(theme) and not always_night(theme)

## WHAT O'CLOCK A WORLD OPENS AT, and the only place that decides it.
##
## WORLD_CLOCK first, because that hook exists so a given hour can be
## looked at and nothing should be able to override it. Then the map's
## own hour if it holds one. Then a time of day at random, which is what
## every ordinary world gets and the reason two rooms of the same map do
## not feel like the same room.
static func opening_clock(theme: String) -> float:
	var forced := OS.get_environment("WORLD_CLOCK")
	if forced.is_valid_float():
		return fposmod(forced.to_float(), 1.0)
	return float(HELD[theme]) if HELD.has(theme) else randf()

class_name Creatures
## ==================================================================
## THE CREATURE REGISTRY — the one file to touch when adding, tuning
## or retiring a creature.
##
## TO ADD ONE:    drop its model under assets/models/, then add an
##                entry below with a NEW id. Ids are the network wire
##                format, so never renumber the existing ones.
## TO RETIRE ONE: delete its entry. Leave the model file alone — it
##                simply stops being spawned.
## TO TUNE ONE:   change "height" (in BLOCKS — the model is scaled to
##                match, whatever units it was made in), "speed",
##                "weight" (spawn chance) or its animation names.
##
## Every entry here is a Kenney Cube Pets model except the firefly, which
## has no "model" and is drawn from code as a glowing mote. Ids are the
## network wire format, so the gaps left by retired creatures stay gaps.
## ==================================================================

## How a creature gets around.
const GROUND := 0   # walks the surface, falls when the ground goes
const FLIER := 1    # soars above the terrain
const SWIMMER := 2  # stays in the water
const STILL := 3    # doesn't roam (modelled lying down, so walking looks wrong)

## Where it is allowed to appear.
const LAND := "land"
const WATER := "water"
const SAND := "sand"
const SNOW := "snow"
const FOREST := "forest"
const JUNGLE := "jungle"
const FARM := "farm"
const ANY := "any"

## Standard clip names in the Kenney Cube Pets pack.
const PET_ANIMS := {"idle": "idle", "walk": "walk", "run": "run",
	"eat": "eat", "cheer": "dance"}

const DEFS := {
	# ---------- everyday animals (Kenney Cube Pets, animated) ----------
	# weight 0 = the classic critter table places these, not the roll.
	0: {"name": "Cow", "model": "res://assets/models/pets/animal-cow.glb",
		"height": 1.15, "move": GROUND, "speed": 1.2, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	1: {"name": "Bunny", "model": "res://assets/models/pets/animal-bunny.glb",
		"height": 0.75, "move": GROUND, "speed": 2.2, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	2: {"name": "Bee", "model": "res://assets/models/pets/animal-bee.glb",
		"height": 0.6, "move": GROUND, "speed": 1.6, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "hover": 0.8},
	3: {"name": "Firefly", "move": GROUND, "speed": 0.9, "habitat": LAND,
		"weight": 0.0},  # no model: drawn in code as a glowing mote
	4: {"name": "Beaver", "model": "res://assets/models/pets/animal-beaver.glb",
		"height": 0.8, "move": SWIMMER, "speed": 1.1, "habitat": WATER,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	5: {"name": "Chick", "model": "res://assets/models/pets/animal-chick.glb",
		"height": 0.6, "move": GROUND, "speed": 1.4, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	6: {"name": "Crab", "model": "res://assets/models/pets/animal-crab.glb",
		"height": 0.5, "move": GROUND, "speed": 0.8, "habitat": SAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	7: {"name": "Caterpillar", "model": "res://assets/models/pets/animal-caterpillar.glb",
		"height": 0.5, "move": GROUND, "speed": 1.3, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	8: {"name": "Deer", "model": "res://assets/models/pets/animal-deer.glb",
		"height": 1.2, "move": GROUND, "speed": 1.8, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	9: {"name": "Penguin", "model": "res://assets/models/pets/animal-penguin.glb",
		"height": 0.8, "move": GROUND, "speed": 0.9, "habitat": SNOW,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
	# The Cube Pets parrot has no flight clip — only `walk` and `run`,
	# which are a bird HOPPING. It used to fly the jungle pack's model and
	# spent its whole life padding its feet four blocks above the ground.
	# With the jungle pack gone, it hops along the floor, which is what its
	# animations were always for.
	10: {"name": "Parrot", "model": "res://assets/models/pets/animal-parrot.glb",
		"height": 0.7, "move": GROUND, "speed": 1.5, "habitat": LAND,
		"weight": 0.0, "anims": PET_ANIMS, "yaw": 180.0},
}

static func has(kind: int) -> bool:
	return DEFS.has(kind)

static func def(kind: int) -> Dictionary:
	return DEFS.get(kind, {})

static func model_of(kind: int) -> String:
	return str(DEFS.get(kind, {}).get("model", ""))

static func speed_of(kind: int) -> float:
	return float(DEFS.get(kind, {}).get("speed", 1.2))

static func move_of(kind: int) -> int:
	return int(DEFS.get(kind, {}).get("move", GROUND))

static func anim_of(kind: int, role: String) -> String:
	return str(DEFS.get(kind, {}).get("anims", {}).get(role, ""))

static func fly_height(kind: int) -> float:
	return float(DEFS.get(kind, {}).get("fly_height", 0.0))

## Weighted pick among registry creatures that suit this ground. Returns
## -1 when nothing rolls, and the caller falls back to the classic
## critter table — so a new creature joins the world without displacing
## the ones already in it.
static func roll(habitat: String) -> int:
	var total := 0.0
	for kind: int in DEFS:
		var entry: Dictionary = DEFS[kind]
		var where := str(entry.get("habitat", LAND))
		if float(entry.get("weight", 0.0)) <= 0.0:
			continue
		if where != habitat and where != ANY:
			continue
		total += float(entry.weight)
	if total <= 0.0:
		return -1
	var pick := randf()
	if pick > total:
		return -1  # most rolls leave room for the ordinary animals
	var walked := 0.0
	for kind: int in DEFS:
		var entry: Dictionary = DEFS[kind]
		var where := str(entry.get("habitat", LAND))
		if float(entry.get("weight", 0.0)) <= 0.0:
			continue
		if where != habitat and where != ANY:
			continue
		walked += float(entry.weight)
		if pick <= walked:
			return kind
	return -1

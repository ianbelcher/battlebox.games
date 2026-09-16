class_name Loadout
extends RefCounted
## WHAT A GAME IS PLAYED WITH: which weapons exist in it, which blocks
## you may build from, which prefabs you may stamp, what is in your hands
## at the drop, and what a supply crate may contain.
##
## Every game used to be played with everything, because there was only
## ever one answer and it was `Blocks.HOTBAR` and `Weapons.WEAPONS`. Two
## games have since wanted to say otherwise in ways a kit list cannot:
## a meeting wants nobody armed, and Tag is a game whose ONLY weapon is a
## hand — a sword in it is not a variation on tag, it is a different and
## much worse game that four-year-olds will find in about nine seconds.
##
## EMPTY MEANS EVERYTHING. A mode that does not mention blocks gets every
## block, which is what every mode written before this file did and still
## does, with no line of any of them changed.
##
## WHERE IT IS ENFORCED, and it has to be all three or it is decoration:
##
##   the picker      you cannot choose what is not in the game
##                   (block_picker.gd, through set_allowed)
##   the server      sv_edit refuses a block outside the loadout, so a
##                   client that has been tampered with cannot place one
##   the crates      loot is drawn from this, not from Weapons.CRATE_POOL
##
## The picker alone would be a suggestion. The server alone would be a
## child clicking a block that silently never appears.

## Weapon ids from Weapons.WEAPONS, or [] for every weapon that is not
## hidden. Order is the order they appear on the Tools page.
var weapons: Array = []

## Block ids from Blocks.HOTBAR, or [] for all of it.
var blocks: Array = []

## Structure indices, or [] for every prefab. A game with no kits passes
## a list with nothing in it — see `none()` below for why that is not the
## same as [].
var kits: Array = []

## What is in the hotbar at the drop, in order; slot 0 is what you are
## holding. Weapon ids, like Weapons.STARTING_KIT.
var start: Array = Weapons.STARTING_KIT

## What supply crates may contain, or [] for Weapons.CRATE_POOL. Entries
## are either a weapon id or one of the special loot kinds below, and
## repetition is how rarity is expressed — the same trick CRATE_POOL uses.
var crate_loot: Array = []

## Loot that is not a weapon. A crate holding one of these is drawn
## differently and handed to the mode through on_crate_taken rather than
## dropped into a hotbar slot. GROWTH is Giants'; the constant lives here
## rather than in giants_mode.gd because the crate machinery, which is
## the platform's, has to be able to recognise it on the wire.
const GROWTH := -1

## THE EMPTY LIST PROBLEM, and it is worth a constant rather than a
## comment somewhere that gets lost.
##
## `kits = []` means "every kit in the game", because empty means
## everything everywhere else in this file. A mode that wants NO kits
## therefore cannot say so with a list — so it says so with this, which
## is a list that can never match any real id.
const NONE: Array = [-9999]

static func none() -> Array:
	return NONE.duplicate()

## Everything, which is what every game was before loadouts existed.
static func everything() -> Loadout:
	return Loadout.new()

## The four questions, each answering true for anything when the
## corresponding list is empty.

func allows_weapon(id: int) -> bool:
	return weapons.is_empty() or id in weapons

func allows_block(id: int) -> bool:
	if not (id in Blocks.HOTBAR):
		return false          # not a placeable block in ANY game
	return blocks.is_empty() or id in blocks

func allows_kit(index: int) -> bool:
	return kits.is_empty() or index in kits

## The weapons this game offers, resolved: the mode's list, or every
## weapon that is not hidden.
func weapon_ids() -> Array:
	return weapons.duplicate() if not weapons.is_empty() else Weapons.visible_ids()

## The blocks this game offers, resolved.
func block_ids() -> Array:
	return blocks.duplicate() if not blocks.is_empty() else Blocks.HOTBAR.duplicate()

## What one crate contains. Returns a weapon id, or GROWTH.
func roll_crate() -> int:
	var pool: Array = crate_loot if not crate_loot.is_empty() else Weapons.CRATE_POOL
	if pool.is_empty():
		return Weapons.CRATE_POOL[0]
	return int(pool[randi() % pool.size()])

## Is this game handing out crates at all? A game whose crate list is
## `Loadout.none()` gets none placed, which saves the survival director
## scattering boxes nobody may open.
func has_crates() -> bool:
	return crate_loot != NONE

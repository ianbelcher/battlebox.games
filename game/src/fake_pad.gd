class_name FakePad
extends InputSlot
## A gamepad that isn't there (WORLD_FAKE_PADS=<n>). Everything except the
## button reads comes from the real InputSlot, so the join path, the claim
## keys and the twin-pad divergence check all run exactly as they would
## with hardware — which BotSlot-driven tests never do.

var pad_index := 0

func _init(p_index: int) -> void:
	super(InputSlot.Kind.GAMEPAD, 900 + p_index)
	pad_index = p_index

func describe() -> String:
	return "Fake pad %d" % (pad_index + 1)

## Real pads key off the joypad GUID; there isn't one, so keep it stable
## and distinct per fake pad.
func claim_key() -> String:
	return "fakepad:%d" % pad_index

func legacy_claim_key() -> String:
	return claim_key()

## PRESSES A, rather than holding it forever. Joining is on the RISING
## edge of the button — as it must be, or one press would join, leave and
## rejoin every frame — so a pad that holds A from the first frame gets
## exactly one edge, ever. Four of them produced one player and looked
## like a bug in the join code. It taps, on its own phase, the way a
## person jabs the button.
func is_primary_pressed() -> bool:
	return int(Time.get_ticks_msec() / 500 + pad_index) % 3 != 0

## Every fake pad holds A, so on the buttons alone they are all identical
## and the twin-pad check would call them ghosts of each other forever.
## Real controllers are never bit-identical for long — somebody is always
## brushing a different button — so each fake pad blinks one bit on its
## own phase. Without this the harness proves nothing about joining,
## because the pads look exactly like the duplicates the check exists to
## reject.
func button_mask(buttons: Array) -> int:
	var phase := int(Time.get_ticks_msec() / 160) + pad_index * 3
	return (1 << (phase % maxi(buttons.size(), 1))) | (pad_index << 8)

## WORLD_FAKE_PAD_HOLD=lb|rb: pretend that shoulder button is held down, so
## a headless run can prove LB still only jumps and never cycles the hotbar.
static func _hold() -> String:
	return OS.get_environment("WORLD_FAKE_PAD_HOLD")

func is_jump_pressed() -> bool:
	return _hold() == "lb" or super()

func cycle_direction() -> int:
	# Mirrors InputSlot's gamepad branch: RB only.
	return 1 if _hold() == "rb" else 0

func tab_cycle_direction() -> int:
	match _hold():
		"rb": return 1
		"lb": return -1
	return 0

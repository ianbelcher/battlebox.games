class_name InputSlot
extends RefCounted
## One local player's physical controls: the keyboard (one player, normal
## WASD controls) plus any number of gamepads. Everything is polled directly
## (no InputMap) so slots never fight over actions.
##
##           move        jump    dig        place      picker     spin   zoom     1st person  leave(hold)
## Keyboard  WASD        Space   L-click/G  R-click/F  E          Z / C  X / V    T           Q
## Gamepad   Left stick  A       B          X          D-pad up   R stick ←→ / ↕  Y      Back/Select
##
## The BUMPERS (Tab / Shift+Tab on the keyboard) step through the picker's
## tabs — blocks, kits and your character — and quick-cycle the held item
## when no menu is open. E (or X/Start) opens the full picker with names.
## In first person the right stick looks around; on keyboard the mouse
## looks. T switches first person and overview.

enum Kind { KEYBOARD_WASD, KEYBOARD_ARROWS, GAMEPAD }

## SMALL, and it can be, because of the look curve below.
##
## 0.25 threw away the first quarter of every stick's travel — which is
## exactly the part you aim with — and on a decent pad it is a quarter of
## the range spent guarding against drift that pad does not have.
##
## 0.10 is safe here specifically BECAUSE `look_response()` is steep at
## the bottom: a stick resting at 0.13 clears the deadzone but comes out
## the other side asking for well under a hundredth of full speed, which
## is nothing. The curve is the drift guard; the deadzone only has to
## catch the worst of it.
const DEADZONE := 0.10

var kind: Kind
var device: int = -1  # joypad device id when kind == GAMEPAD

func _init(p_kind: Kind, p_device: int = -1) -> void:
	kind = p_kind
	device = p_device

func describe() -> String:
	match kind:
		Kind.KEYBOARD_WASD:
			return "Keyboard WASD"
		Kind.KEYBOARD_ARROWS:
			return "Keyboard Arrows"
		_:
			return "Gamepad %d" % (device + 1)

## Unique key so the same physical device can't join twice. Also the profile
## key each device's character is saved under.
func claim_key() -> String:
	if kind == Kind.GAMEPAD:
		# Device NUMBERS shuffle between sessions (plug order) which lost
		# kids' saved characters — the controller GUID is stable.
		var guid := Input.get_joy_guid(device)
		if not guid.is_empty():
			return "pad:%s" % guid
		return "pad:%d" % device
	return "kb:%d" % kind

## The old unstable profile key, for one-time migration of saved data.
## The buttons this device is holding, as a bitmask, for the twin-pad
## check in main.gd.
##
## A method on the SLOT rather than a direct `Input.is_joy_button_pressed`
## at the call site, so a simulated pad can answer for itself. It could
## not before: `WORLD_FAKE_PADS` devices do not exist as far as Input is
## concerned, so every fake pad reported "no buttons held", every one
## matched every other, and the join test could never get a second player
## in — which made the harness useless for exactly the bug it should have
## caught.
func button_mask(buttons: Array) -> int:
	var mask := 0
	for i in buttons.size():
		if Input.is_joy_button_pressed(device, int(buttons[i])):
			mask |= 1 << i
	return mask

## WHICH PHYSICAL THING THIS IS, for deciding whether it has already
## joined. Unique per device, always.
##
## NOT the same question as `claim_key()`, and conflating them is what
## stopped a second player joining at all. `claim_key()` answers "whose
## character is this" and keys off the controller GUID so a child gets
## their own character back when they pick up the same pad — but a GUID
## identifies a MODEL, not a unit, so four identical controllers share
## one. The join code treated that shared key as "already claimed" and
## skipped every pad after the first: four pads plugged in, one player
## able to get in.
##
## Device numbers are unique within a session, which is all this needs to
## be right. Profiles keep using `claim_key()`, which already
## disambiguates identical GUIDs with #1/#2 suffixes of its own.
func device_key() -> String:
	if kind == Kind.GAMEPAD:
		return "dev:pad:%d" % device
	return "dev:kb:%d" % kind

func legacy_claim_key() -> String:
	if kind == Kind.GAMEPAD:
		return "pad:%d" % device
	return "kb:%d" % kind

func get_move_vector() -> Vector2:
	var v := Vector2.ZERO
	match kind:
		Kind.KEYBOARD_WASD:
			v.x = _key_axis(KEY_A, KEY_D)
			v.y = _key_axis(KEY_W, KEY_S)
		Kind.KEYBOARD_ARROWS:
			v.x = _key_axis(KEY_LEFT, KEY_RIGHT)
			v.y = _key_axis(KEY_UP, KEY_DOWN)
		Kind.GAMEPAD:
			v.x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
			v.y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
			if v.length() < DEADZONE:
				v = Vector2.ZERO
	return v.limit_length(1.0)

## The big friendly "join" button: Space, Enter, or A. In the world it jumps.
func is_primary_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SPACE)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_ENTER)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_A)

## Jump / fly up: A.
##
## LB used to jump as well, which meant the bumpers could not be a matched
## pair — RB stepped the hotbar forward and LB could not step it back,
## because every jump would have changed what you were holding. LB is the
## backward step now and jumping is A alone, the way it reads on the pad.
func is_jump_pressed() -> bool:
	return is_primary_pressed()

## Dig a block, collect a treasure, pet a critter (and zap Grumps).
func is_dig_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
				or Input.is_physical_key_pressed(KEY_G)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_PERIOD)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_B) \
				or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)

## Place the selected block.
func is_place_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
				or Input.is_physical_key_pressed(KEY_F)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_COMMA)
		_:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5

## Cycle the hotbar selection IN THE WORLD. Returns -1, 0 or +1.
##
## Both bumpers, as a pair: RB forward, LB back — the same thing the D-pad
## does sideways. LB could not do this while it also jumped.
func cycle_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_TAB):
				return 1
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
				return 1
			if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER):
				return -1
	return 0

## Step through the PICKER'S TABS, both ways: LB/RB on a pad, Tab and
## Shift+Tab on the keyboard. Only polled while the menu is open, which is
## exactly when the bumpers are free of their in-world jobs.
func tab_cycle_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_TAB):
				return -1 if Input.is_physical_key_pressed(KEY_SHIFT) else 1
		Kind.GAMEPAD:
			var right := Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER)
			var left := Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER)
			return (1 if right else 0) - (1 if left else 0)
	return 0

## Throw an orb (R / middle click / right trigger) — always available.
func is_shoot_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_R) \
				or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
		Kind.GAMEPAD:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	return false

## Hotbar slot select: number keys 1-8; D-pad left/right cycles on pads.
## Returns 0-7 direct, -1 none, 10/11 cycle prev/next.
func slot_pick() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			for i in 8:
				if Input.is_physical_key_pressed(KEY_1 + i):
					return i
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT):
				return 10
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT):
				return 11
	return -1

## Open the tabbed menu (Esc / Start).
## Open this player's BUILD menu: X on a pad, E on the keyboard. Escape
## is no longer here — it belongs to the whole-table world menu.
func is_menu_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return false
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_START) \
				or Input.is_joy_button_pressed(device, JOY_BUTTON_X)
	return false

## Open/close the block & structure picker (E / D-pad up).
func is_picker_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_E)
		Kind.GAMEPAD:
			return false  # pads open the menu with X/Start
	return false

## Directional input for navigating the picker grid. D-pad left/right is
## reserved for the weapon hotbar (even with a menu open), so the grid
## navigates with the stick plus D-pad up/down.
func get_ui_vector() -> Vector2:
	if kind == Kind.GAMEPAD:
		var v := Vector2.ZERO
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
			v.y = 1.0
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
			v.y = -1.0
		if v == Vector2.ZERO:
			v = get_move_vector()
		return v
	return get_move_vector()

## Sprint is retired — walking is the normal pace now.
## Triggers cycle the menu's TOP-LEVEL group (Build / Game / Options).
## FINE AIM: hold the right stick IN and the look slows to a quarter.
##
## The look curve already gives a gentle bottom end, and that helps with
## the small corrections you make without thinking. It does not help with
## the deliberate ones — lining up on somebody across a field — because
## there the stick is well off centre and firmly in the fast part of the
## curve. A modifier is the answer to that, and it has to be a MODIFIER
## rather than a setting: you want it for the second before you shoot and
## not for the rest of the round.
##
## The right stick's own button, because it is the stick you are already
## holding to aim with. Nothing to reach for.
const PRECISION_SCALE := 0.25

func is_precision_pressed() -> bool:
	match kind:
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK)
	return false

func is_sprint_pressed() -> bool:
	return false

## Creep like Minecraft sneak: slow and SILENT (Shift / click left stick).
func is_sneak_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SHIFT)
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
	return false

## Descend while flying (Shift). The left trigger used to do this too and
## is the LIFT now — it cannot mean both up and down.
func is_descend_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_SHIFT)
	return false

## LIFT: hold the left trigger and rise. Let go and you FALL — this is not
## flying, and that is the point of it. Flying (double-tap A) leaves you
## hanging in the air when you stop pressing, which is a fine way to build
## and a poor way to get out of a hole in a hurry. Hold, rise, release,
## drop.
func is_lift_pressed() -> bool:
	match kind:
		Kind.GAMEPAD:
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.5
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_CTRL)
	return false

## Toggle between the isometric view and first person (T / gamepad Y).
func is_view_toggle_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_T)
		Kind.GAMEPAD:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_Y)
	return false

## First-person look input per frame (gamepad right stick; the keyboard
## looks with the mouse, handled by the player via input events).
## HOW THE LOOK STICK RESPONDS, in two zones.
##
## Linear is the problem: just past the deadzone the stick is already
## asking for a third of full speed, so the smallest nudge you can
## physically make swings the camera past what you were aiming at. A
## power curve (this was t^3) fixes the very bottom but leaves the MIDDLE
## hot — half a stick still asked for an eighth of 223 degrees a second,
## which is where a child actually holds it while lining a shot up.
##
## So: most of the stick's travel is a precision zone that tops out at a
## tenth of full speed, and the last third ramps from there to the whole
## lot. Fine aiming happens in the part of the range you can hold
## steadily; whipping round to look behind you happens at the edge, and
## is EXACTLY as fast as it was — response(1.0) is 1.0, by construction.
const LOOK_PRECISION_EDGE := 0.70
## Speed at that edge, as a fraction of full.
const LOOK_PRECISION_SPEED := 0.10

## Stick travel (0..1, already deadzone-corrected) -> fraction of full
## look speed. Pure maths, so tests/unit/aim_curve_test.gd can check the
## shape rather than anyone having to feel for it.
static func look_response(travel: float) -> float:
	var t := clampf(travel, 0.0, 1.0)
	if t <= 0.0:
		return 0.0
	if t <= LOOK_PRECISION_EDGE:
		# CUBED inside the precision zone, not squared. Squared made the
		# bottom of the stick very slightly hotter than the old curve did
		# — a fifth of a degree a second either way, so nothing anyone
		# could feel, but "gentler for small movements" should mean all of
		# them and the test says so.
		var fine := t / LOOK_PRECISION_EDGE
		return LOOK_PRECISION_SPEED * fine * fine * fine
	var fast := (t - LOOK_PRECISION_EDGE) / (1.0 - LOOK_PRECISION_EDGE)
	return lerpf(LOOK_PRECISION_SPEED, 1.0, fast * fast)

func get_look_vector() -> Vector2:
	if kind != Kind.GAMEPAD:
		return Vector2.ZERO
	var v := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	var mag := v.length()
	if mag < DEADZONE:
		return Vector2.ZERO
	# Rescale from the deadzone edge so the curve starts at nothing rather
	# than at a step: without this the first registered input is already
	# DEADZONE-sized and the fine control is gone before it starts.
	var t := clampf((mag - DEADZONE) / (1.0 - DEADZONE), 0.0, 1.0)
	var scale := PRECISION_SCALE if is_precision_pressed() else 1.0
	# Applied HERE rather than at each camera, so it covers first person,
	# the orbit view and anything added later without being remembered.
	return v.normalized() * look_response(t) * scale

## Spin the camera a quarter turn. Returns -1, 0 or +1 (caller edge-latches).
func rotate_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_Z):
				return -1
			if Input.is_physical_key_pressed(KEY_X):
				return 1
		Kind.KEYBOARD_ARROWS:
			if Input.is_physical_key_pressed(KEY_SEMICOLON):
				return -1
			if Input.is_physical_key_pressed(KEY_APOSTROPHE):
				return 1
		Kind.GAMEPAD:
			var x := Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)
			if x < -0.6:
				return -1
			if x > 0.6:
				return 1
	return 0

## Step the zoom. Returns -1 (out), 0 or +1 (in); caller edge-latches.
func zoom_direction() -> int:
	match kind:
		Kind.KEYBOARD_WASD:
			if Input.is_physical_key_pressed(KEY_C):
				return -1
			if Input.is_physical_key_pressed(KEY_V):
				return 1
		Kind.KEYBOARD_ARROWS:
			if Input.is_physical_key_pressed(KEY_BRACKETLEFT):
				return -1
			if Input.is_physical_key_pressed(KEY_BRACKETRIGHT):
				return 1
		Kind.GAMEPAD:
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
				return 1
			if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN):
				return -1
	return 0

## Leave is HELD (not tapped) so a stray press never drops a kid's character.
func is_leave_pressed() -> bool:
	match kind:
		Kind.KEYBOARD_WASD:
			return Input.is_physical_key_pressed(KEY_Q)
		Kind.KEYBOARD_ARROWS:
			return Input.is_physical_key_pressed(KEY_BACKSPACE)
		_:
			return Input.is_joy_button_pressed(device, JOY_BUTTON_BACK)

func _key_axis(neg: Key, pos: Key) -> float:
	var v := 0.0
	if Input.is_physical_key_pressed(neg):
		v -= 1.0
	if Input.is_physical_key_pressed(pos):
		v += 1.0
	return v

## WORLD_FAKE_PADS=<n>: pretend n gamepads are plugged in, each holding A.
## Controller regressions are invisible to the bot-driven smoke tests —
## BotSlot overrides every button — so this drives the REAL gamepad code
## through the real join path with no hardware attached.
static var fake_pads: int = -1

static func _fake_pad_count() -> int:
	if fake_pads < 0:
		var env := OS.get_environment("WORLD_FAKE_PADS")
		fake_pads = env.to_int() if env.is_valid_int() else 0
	return fake_pads

## All slots that could join right now (used by the drop-in poller).
## One keyboard player only — the arrows layout confused everyone.
static func candidate_slots() -> Array[InputSlot]:
	var slots: Array[InputSlot] = []
	slots.append(InputSlot.new(Kind.KEYBOARD_WASD))
	for device_id in Input.get_connected_joypads():
		slots.append(InputSlot.new(Kind.GAMEPAD, device_id))
	for i in _fake_pad_count():
		slots.append(FakePad.new(i))
	return slots

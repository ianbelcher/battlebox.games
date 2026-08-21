extends Node
## WORLD_MENU_PROBE=1 — drives the Escape menu the way a person does and
## reports what actually happened: Escape opens it, a mouse click lands on
## a tab, a mouse click presses a button, Tab moves the keyboard highlight,
## and a joypad button is IGNORED. Menus are easy to break silently, and
## screenshots only prove they render, not that they respond.
##
## NEEDS A REAL WINDOW. Synthetic input goes through the display server,
## and a --headless run has none — the probe reports "menu never opened"
## on perfectly good code, which is why it is not in CI and why running it
## headless is a wasted afternoon:
##
##   WORLD_MENU_PROBE=1 WORLD_AUTOTEST=1 \
##     WORLD_AUTOCONNECT=ws://127.0.0.1:9081 godot --path game
var _t := 0.0
var _step := 0
var _keylog := 0.0

func _key_watch(delta: float) -> void:
	_keylog += delta
	if _keylog < 1.0:
		return
	_keylog = 0.0
	var pressed: Array = []
	for k in [KEY_E, KEY_ESCAPE, KEY_SPACE, KEY_T, KEY_TAB, KEY_SHIFT, KEY_C]:
		if Input.is_physical_key_pressed(k):
			pressed.append(OS.get_keycode_string(k))
	print("KEYWATCH t=%.0f focused=%s pressed=%s mouse=%d" % [
		Time.get_ticks_msec() / 1000.0,
		get_window().has_focus(), str(pressed), Input.mouse_mode])

func _process(delta: float) -> void:
	_key_watch(delta)
	_t += delta
	if _t < 12.0:
		return
	var main := get_tree().root.get_child(get_tree().root.get_child_count() - 1)
	var menu = main.get("_world_menu") if main else null
	var split = main.get("_split") if main else null
	match _step:
		0:
			print("PROBE menu_node=", menu, " visible=", menu.visible if menu else "n/a")
			print("PROBE local_inputs=", Game.local_inputs.size(),
				" kinds=", Game.local_inputs.values().map(func(i): return i.describe()))
			var cells = split.get("_cells") if split else []
			for c in cells:
				print("PROBE cell slot=", c.get("slot"), " fp=", c.get("fp"),
					" hud_open=", c.hud.is_ui_open() if c.get("hud") else "-")
			print("PROBE mouse_mode=", Input.mouse_mode, " (0=VISIBLE 2=CAPTURED)",
				" world_menu_open=", split.world_menu_open if split else "n/a")
			var ev := InputEventKey.new()
			ev.keycode = KEY_ESCAPE
			ev.physical_keycode = KEY_ESCAPE
			ev.pressed = true
			Input.parse_input_event(ev)
			print("PROBE sent ESCAPE")
		1:
			print("PROBE after esc: visible=", menu.visible if menu else "n/a",
				" mouse_mode=", Input.mouse_mode,
				" world_menu_open=", split.world_menu_open if split else "n/a")
		2:
			if menu == null or not menu.visible:
				print("PROBE FAIL: menu never opened")
				get_tree().quit(1)
				return
			# Find the Battle tab bar and click the second tab.
			var tabs = menu.get("_tabs")
			print("PROBE tabs=", tabs, " current=", tabs.current_tab if tabs else "-",
				" count=", tabs.get_tab_count() if tabs else "-")
			var bar: TabBar = tabs.get_tab_bar()
			var r: Rect2 = bar.get_global_rect()
			var pt := Vector2(r.position.x + r.size.x * 0.28, r.position.y + r.size.y * 0.5)
			print("PROBE tabbar rect=", r, " clicking ", pt,
				" mouse_filter=", bar.mouse_filter, " menu_filter=", menu.mouse_filter)
			for pressed in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = pressed
				mb.position = pt
				mb.global_position = pt
				Input.parse_input_event(mb)
		3:
			var tabs2 = menu.get("_tabs")
			print("PROBE after tab click: current_tab=", tabs2.current_tab if tabs2 else "-")
		4:
			# Now click a real BUTTON inside the visible tab.
			var found: Button = null
			for b in menu.find_children("*", "Button", true, false):
				if (b as Button).is_visible_in_tree():
					found = b
					break
			if found == null:
				print("PROBE FAIL: no visible button in menu")
				get_tree().quit(1)
				return
			var br: Rect2 = found.get_global_rect()
			var bpt := br.get_center()
			print("PROBE clicking button '", found.text, "' at ", bpt,
				" filter=", found.mouse_filter, " disabled=", found.disabled)
			found.pressed.connect(func() -> void: print("PROBE >>> BUTTON PRESS REGISTERED"))
			for pressed in [true, false]:
				var mb := InputEventMouseButton.new()
				mb.button_index = MOUSE_BUTTON_LEFT
				mb.pressed = pressed
				mb.position = bpt
				mb.global_position = bpt
				Input.parse_input_event(mb)
		6:
			# KEYBOARD: is anything focused, and does Tab move it?
			var f1 = get_viewport().gui_get_focus_owner()
			print("PROBE kb focus_owner=", f1, " (", (f1.name if f1 else "NONE"), ")")
			var ev := InputEventKey.new()
			ev.keycode = KEY_TAB
			ev.physical_keycode = KEY_TAB
			ev.pressed = true
			Input.parse_input_event(ev)
		7:
			var f2 = get_viewport().gui_get_focus_owner()
			print("PROBE kb after TAB focus=", f2, " (", (f2.name if f2 else "NONE"), ")")
			# CONTROLLER: must be ignored entirely.
			var jb := InputEventJoypadButton.new()
			jb.button_index = JOY_BUTTON_A
			jb.pressed = true
			jb.device = 0
			Input.parse_input_event(jb)
		8:
			var f3 = get_viewport().gui_get_focus_owner()
			print("PROBE after joypad A focus=", f3, " (", (f3.name if f3 else "NONE"), ")")
			print("PROBE done")
			get_tree().quit()
	_step += 1
	_t = 11.6

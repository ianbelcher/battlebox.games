extends SceneTree
## Can a KEYBOARD user drive the world menu? Godot's UI navigation (Tab,
## arrows, Enter) only reaches controls that can take focus.
func _initialize() -> void:
	var menu := WorldMenu.new()
	var root := Control.new()
	root.size = Vector2(1400, 900)
	get_root().add_child(root)
	root.add_child(menu)
	menu.visible = true
	await process_frame
	await process_frame
	var focusable := 0
	var blocked := 0
	for c in menu.find_children("*", "Control", true, false):
		var ctl := c as Control
		if not (ctl is BaseButton or ctl is LineEdit or ctl is Range or ctl is TabBar):
			continue
		if ctl.focus_mode == Control.FOCUS_NONE:
			blocked += 1
		else:
			focusable += 1
	print("interactive controls: focusable=%d  focus_blocked=%d" % [focusable, blocked])
	print("=> keyboard can navigate: ", focusable > 0)
	quit()

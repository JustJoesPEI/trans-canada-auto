extends SceneTree
## Checks the Controls menu's settings: rebinding a key (InputSetup.rebind)
## moves every action in its row, keeps the arrow keys and the controller,
## is saved and put back, and reset_keys() undoes it; and the mouse settings
## (AimSettings.mouse_sensitivity, invert_y) save and load.
##
##   godot --headless --path . --script res://tools/controls_check.gd
##
## Puts the real controls file back as it was. Exits non-zero on failure.

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok    " if ok else "FAIL  ") + what)


func _keys(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append((ev as InputEventKey).physical_keycode)
	return out


func _has_joy(action: String) -> bool:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion or ev is InputEventJoypadButton:
			return true
	return false


func _run() -> void:
	var setup: Node = root.get_node("InputSetup")
	var path: String = setup.SAVE_PATH
	var kept := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	setup.call("reset_keys")

	_check(_keys("accelerate") == [KEY_W, KEY_UP], "W and Up accelerate to start with")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_I
	ev.pressed = true
	var shared: Array = setup.call("rebind", "forward", ev)
	_check(_keys("accelerate") == [KEY_I, KEY_UP], "forward on I: accelerate is I and Up")
	_check(_keys("move_forward") == [KEY_I, KEY_UP], "forward on I: walking forward is I and Up")
	_check(_has_joy("accelerate"), "the controller's trigger still accelerates")
	_check(shared.is_empty(), "I isn't used by anything else")
	_check(str(setup.call("binding_text", "forward")) == "I", "the row shows I (%s)" % setup.call("binding_text", "forward"))

	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.pressed = true
	shared = setup.call("rebind", "flip", h)
	_check(shared.has("Horn"), "H for flipping says the horn shares it (%s)" % [shared])

	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_MIDDLE
	m.pressed = true
	setup.call("rebind", "fire", m)
	var fire_mouse := false
	for e in InputMap.action_get_events("fire"):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
			fire_mouse = true
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			fire_mouse = false
	_check(fire_mouse, "fire moves from the left mouse button to the middle one")

	# Saved, and put back the next time: clear the map's change, then load.
	for row: Array in setup.REBIND:
		if row[0] == "forward":
			setup.call("_apply", row, {"key": KEY_W}) # as it starts...
	setup.call("_load_keys") # ...and the saved keys come back
	_check(_keys("accelerate").has(KEY_I), "the saved key comes back when the game starts")

	setup.call("reset_keys")
	_check(_keys("accelerate") == [KEY_W, KEY_UP], "reset puts W back")
	_check(str(setup.call("binding_text", "fire")) == "Left mouse button", "reset puts fire back on the left mouse button")

	AimSettings.reset_defaults()
	AimSettings.set_number("mouse_sensitivity", 1.7)
	AimSettings.invert_y = true
	AimSettings.save()
	AimSettings.load_saved()
	_check(is_equal_approx(AimSettings.mouse_sensitivity, 1.7), "mouse sensitivity saves")
	_check(AimSettings.invert_y and AimSettings.y_sign() == -1.0, "inverted looking saves")
	AimSettings.set_number("mouse_sensitivity", 99.0)
	_check(AimSettings.mouse_sensitivity == AimSettings.MOUSE_MAX, "mouse sensitivity stays in range")

	if kept != "":
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(kept)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("%d of %d checks passed" % [_checks - _fails, _checks])
	quit(1 if _fails > 0 else 0)

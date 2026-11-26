extends SceneTree
## Checks the phone (scripts/ui/phone.gd) in the real town: P brings it out
## and pauses the game, the home screen has the Map, Jobs, SpudDash and
## Garage apps, each app fills in, taking a SpudDash order from it starts
## the job and puts the phone away, the Jobs app then shows it and cancels
## it, B goes back to the home screen, and the Map app opens the town map.
##
##   godot --headless --path . --script res://tools/phone_check.gd
##
## With a real renderer, `-- --shots` also saves the home screen and each
## app to /tmp/tca-shots/phone_<app>.png:
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1600x900x24" \
##       godot --rendering-driver vulkan --resolution 1600x900 --path . \
##       --script res://tools/phone_check.gd -- --shots

const SHOTS := "/tmp/tca-shots"

var _failures := 0
var _shots := false
var _phone: Phone


func _initialize() -> void:
	_shots = "--shots" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("PHONE ok   %s" % what)
	else:
		_failures += 1
		print("PHONE FAIL %s" % what)


func _key(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	root.push_input(ev)
	await process_frame


func _pad(button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	root.push_input(ev)
	await process_frame


func _shot(name: String) -> void:
	if not _shots:
		return
	for i in 4:
		await process_frame
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var path := SHOTS.path_join("phone_%s.png" % name)
	root.get_texture().get_image().save_png(path)
	print("PHONE shot %s" % path)


func _text(node: Node) -> String:
	var out: Array[String] = []
	for c in node.find_children("*", "", true, false):
		if c is Label:
			out.append((c as Label).text)
		elif c is Button:
			out.append((c as Button).text)
	return "\n".join(out)


func _run() -> void:
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		menu.set("_open", false)
		menu.set("_started", true)
		var layer: Variant = menu.get("_layer")
		if layer is CanvasLayer:
			(layer as CanvasLayer).visible = false
		var loading: Variant = menu.get("_loading")
		if loading is Control:
			(loading as Control).visible = false
		menu.process_mode = Node.PROCESS_MODE_DISABLED
	var notes := root.get_node_or_null("FieldNotes")
	if notes != null:
		notes.process_mode = Node.PROCESS_MODE_DISABLED
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var world := main.get_node("World")
	if not world.is_built:
		await world.built
	for i in 10:
		await process_frame
	var player := main.get_node("Player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED

	_phone = Phone.find(self)
	_check(_phone != null, "the HUD makes the phone")
	if _phone == null:
		_finish()
		return
	await _key("phone")
	_check(_phone.is_open and paused, "P brings it out and pauses the game")
	_check(_phone.current_app() == "", "on the home screen")
	var home := _text(_phone)
	for app in ["Map", "Jobs", "SpudDash", "Garage"]:
		_check(home.contains(app), "the home screen has %s" % app)
	await _shot("home")

	_phone.show_app("spuddash")
	await process_frame
	var sd := _text(_phone)
	_check(sd.contains("SpudDash") and sd.contains("New orders in about"), "the SpudDash app lists orders")
	await _shot("spuddash")
	var take: Button = null
	for b in _phone.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Route "):
			take = b
			break
	_check(take != null, "with a button to take one")
	if take != null:
		take.pressed.emit()
		await process_frame
		var eco := Economy.find(self)
		_check(not _phone.is_open and not paused, "taking it puts the phone away and the game goes on")
		_check(eco != null and str(eco.jobs.active.get("kind", "")) == "spuddash", "and the run's under way")
		await _key("phone")
		_phone.show_app("jobs")
		await process_frame
		_check(_text(_phone).contains("Cancel the job"), "the Jobs app shows it, with Cancel")
		await _shot("jobs")
		for b in _phone.find_children("*", "Button", true, false):
			if (b as Button).text == "Cancel the job":
				(b as Button).pressed.emit()
				break
		await process_frame
		_check(eco.jobs.active.is_empty() and _text(_phone).contains("No job under way"), "Cancel ends it and the app shows that")

	_phone.show_app("garage")
	await process_frame
	_check(_text(_phone).contains("Garage:"), "the Garage app lists your spaces")
	await _shot("garage")
	await _pad(JOY_BUTTON_B)
	_check(_phone.is_open and _phone.current_app() == "", "B in an app goes back to the home screen")
	await _pad(JOY_BUTTON_B)
	_check(not _phone.is_open and not paused, "B on the home screen puts it away")

	await _key("phone")
	_phone.show_app("map")
	await process_frame
	var map := WorldMap.find(self)
	_check(not _phone.is_open and map != null and map.is_open, "the Map app opens the town map")
	await _key("phone")
	_check(not _phone.is_open, "and the phone stays away while the map's open")
	if map != null:
		map.close()
	_check(not paused, "closing the map lets the game go on")
	_finish()


func _finish() -> void:
	print("PHONE %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)

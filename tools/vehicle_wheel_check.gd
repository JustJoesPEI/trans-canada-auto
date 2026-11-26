extends SceneTree
## Checks the controller layout's driving side in the real town, at the
## Delayed & Lost yard: holding the wheel key (LB) in the driver's seat
## brings up the vehicle wheel (scripts/ui/vehicle_wheel.gd) with only what
## that vehicle can do, picking a slot does it (wipers, the phone, the map,
## switching seats), RB is the handbrake, and in a working vehicle (the
## forklift) the D-pad works the tool instead of opening the phone or map.
##
##   godot --headless --path . --script res://tools/vehicle_wheel_check.gd
##
## With a real renderer, `-- --shots` saves the wheel to
## /tmp/tca-shots/vehicle_wheel.png.

const SHOTS := "/tmp/tca-shots"

var _failures := 0
var _main: Node
var _player: Node3D
var _wheel: VehicleWheel


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("WHEEL ok   %s" % what)
	else:
		_failures += 1
		print("WHEEL FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _pad(button: JoyButton, pressed := true) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await _frames(2)


func _ids() -> Array:
	return _wheel.slots.map(func(e: Dictionary) -> String: return str(e["id"]))


## Hold LB, point at `id`, let go.
func _pick(id: String) -> void:
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_wheel.pointed = _ids().find(id)
	await _pad(JOY_BUTTON_LEFT_SHOULDER, false)


func _model(id: String) -> Car:
	for n in _main.get_children():
		if n is Car and (n as Car).model_id == id and str(n.name).begins_with("Yard"):
			return n
	return null


func _get_in(car: Car) -> void:
	_player.place(Transform3D(Basis.IDENTITY, car.door_point() + Vector3.UP * 0.2))
	await _frames(3)
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)


func _get_out() -> void:
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	var world: WorldBuilder = _main.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	for n in ["FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_player = _main.get_node("Player")
	var yard: Dictionary = world.data.config["work_yard"]
	var base := world.edit_xform(yard, 1.0)
	_player.global_position = base.origin + Vector3.UP
	await world.streamer.prime(Vector2(base.origin.x, base.origin.z), 150.0)
	await _frames(120)
	_wheel = _main.get("vehicle_wheel")
	var phone := Phone.find(self)
	var map := WorldMap.find(self)
	_check(_wheel != null and phone != null and map != null, "the vehicle wheel, the phone and the map are set up")
	if _wheel == null:
		_finish()
		return

	# On foot LB is the weapon wheel, not this one.
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(not _wheel.is_open, "on foot, LB doesn't bring up the vehicle wheel")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, false)

	# A tractor: an ordinary driver's seat with a hitch.
	var tractor := _model("hauler")
	_check(tractor != null, "the yard has a tractor")
	if tractor == null:
		_finish()
		return
	await _get_in(tractor)
	_check(_player.get("vehicle") == tractor, "got in the tractor")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(_wheel.is_open and Engine.time_scale < 1.0, "holding LB in the driver's seat brings up the wheel, time slowed")
	var ids := _ids()
	for id in ["phone", "wipers", "hitch", "seat", "map"]:
		_check(id in ids, "it has %s" % id)
	_check(not "lights" in ids, "but no police lights in a tractor")
	if "--shots" in OS.get_cmdline_user_args():
		_wheel.pointed = ids.find("hitch")
		await _frames(4)
		DirAccess.make_dir_recursive_absolute(SHOTS)
		root.get_texture().get_image().save_png(SHOTS.path_join("vehicle_wheel.png"))
		print("WHEEL shot %s" % SHOTS.path_join("vehicle_wheel.png"))
	_wheel.pointed = -1
	await _pad(JOY_BUTTON_LEFT_SHOULDER, false)
	_check(not _wheel.is_open and is_equal_approx(Engine.time_scale, 1.0), "letting go in the middle does nothing and time's back")

	var pc := PaintCoverage.of(tractor)
	await _pick("wipers")
	_check(pc != null and pc.wiper >= 0.0, "picking Wipers sets the wipers going")

	await _pick("phone")
	_check(phone.is_open, "picking Phone brings the phone out")
	phone.close()
	await _frames(2)
	await _pick("map")
	_check(map.is_open, "picking Map opens the map")
	map.close()
	await _frames(2)

	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(Input.is_action_pressed("handbrake"), "RB is the handbrake")
	_check(not bool(_player.get("passenger")), "and doesn't switch seats in the driver's seat")
	await _pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _pick("seat")
	_check(bool(_player.get("passenger")), "picking Switch seat moves over to the passenger seat")
	await _pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(not _wheel.is_open, "and a passenger's LB is the weapon wheel again")
	await _pad(JOY_BUTTON_LEFT_SHOULDER, false)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER)
	await _pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	_check(not bool(_player.get("passenger")), "a passenger's RB switches back")
	await _get_out()

	# The forklift: the D-pad works the forks.
	var fl := _model("forklift")
	_check(fl != null, "the yard has a forklift")
	if fl != null:
		await _get_in(fl)
		_check(_player.get("vehicle") == fl, "got in the forklift")
		await _pad(JOY_BUTTON_DPAD_UP)
		_check(Input.is_action_pressed("work_up") and not phone.is_open, "D-pad up raises the forks, and leaves the phone away")
		await _pad(JOY_BUTTON_DPAD_UP, false)
		await _pad(JOY_BUTTON_DPAD_DOWN)
		_check(Input.is_action_pressed("work_down") and not map.is_open, "D-pad down lowers them, and leaves the map shut")
		await _pad(JOY_BUTTON_DPAD_DOWN, false)
		await _pad(JOY_BUTTON_LEFT_SHOULDER)
		var fids := _ids()
		_check(_wheel.is_open and "phone" in fids and "map" in fids and not "seat" in fids, "its wheel has the phone and the map, and no seat to switch to")
		_wheel.pointed = -1
		await _pad(JOY_BUTTON_LEFT_SHOULDER, false)
		await _get_out()
	_finish()


func _finish() -> void:
	print("WHEEL %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)

extends SceneTree
## Plays the truck yard the way a player would, with the game's own HUD,
## camera and input handling, and reports what the player would see and
## hear: every prompt, title and controls card as it changes, where the
## camera is, and which work sounds are playing.
##
##   godot --headless --path . --script res://tools/work_check.gd
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/work_check.gd -- --shots --out=/tmp/work
##
## Jobs, in turn: the tractor backs under its trailer (it should couple by
## itself and the camera pull back), drives off with the load loose (it
## should be warned), straps it, backs up (the camera should stay behind,
## the alarm beep); the forklift drives into a pallet, lifts it (the HUD
## should give its weight) and backs out; the tow truck lowers its deck,
## winches the broken-down car up, straps it and raises the deck.
## One "WORK" line per finding, "HUD" lines as the screen changes.

const YardCheck := preload("res://tools/yard_check.gd")

var _args := {}
var _main: Node
var _hud: Hud
var _rig: CameraRig
var _player: PlayerController
var _base: Transform3D
var _seen := {}
var _shot := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()


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
	_hud = _main.get_node("HUD")
	_rig = _main.get_node("CameraRig")
	_player = _main.get_node("Player")
	var yard: Dictionary = world.data.config["work_yard"]
	_base = world.edit_xform(yard, 1.0)
	_player.global_position = _base.origin + Vector3.UP
	_rig.snap_to_target()
	if _args.has("shots"):
		await world.wait_until_settled()
	else:
		await world.streamer.prime(Vector2(_base.origin.x, _base.origin.z), 150.0)
	await _frames(300)
	await _tractor()
	await _forklift()
	await _rollback()
	quit()


# --- watching ----------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await physics_frame
		_watch()


## Print the HUD's prompt, title and card whenever they change.
func _watch() -> void:
	var now := {
		"prompt": ("[%s] %s" % [_hud._prompt_key.text, _hud._prompt_text.text]) if _hud._prompt_panel.visible else "",
		"title": ("%s / %s" % [_hud._title.text, _hud._subtitle.text]) if _hud._title_time > 3.3 else "",
		"card": _card_text(),
	}
	for k: String in now:
		if now[k] != "" and now[k] != _seen.get(k, ""):
			print("HUD %s: %s" % [k, now[k]])
		_seen[k] = now[k]


func _card_text() -> String:
	if not _hud._card.visible:
		return ""
	var keys: String = _hud._card_keys.get_parsed_text().strip_edges().replace("\n", " | ")
	return keys + (" || " + _hud._card_status.text if _hud._card_status.visible else "")


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame


func _hold(action: String, strength := 1.0) -> void:
	Input.action_press(action, strength)


func _let_go() -> void:
	for a in ["accelerate", "brake_reverse", "steer_left", "steer_right", "work_up", "work_down", "aux_in", "aux_out"]:
		Input.action_release(a)


func _model(id: String) -> Car:
	for n in _main.get_children():
		if n is Car and (n as Car).model_id == id and str(n.name).begins_with("Yard"):
			return n
	return null


## Walk up to a vehicle's door and get in with the interact key.
func _get_in(car: Car) -> void:
	_player.place(Transform3D(Basis.IDENTITY, car.door_point() + Vector3.UP * 0.2))
	await _frames(3)
	await _press("interact")
	await _frames(2)
	print("WORK got in the %s: %s" % [car.display_name(), "yes" if _player.vehicle == car else "NO"])


func _get_out() -> void:
	if _player.vehicle != null:
		await _stop(_player.vehicle)
	await _press("interact")
	await _frames(30)
	if _player.vehicle != null:
		print("WORK COULD NOT GET OUT of the %s at %.0f km/h" % [_player.vehicle.display_name(), _player.vehicle.speed * 3.6])


## Brake to a stop: the pedal that brakes depends on which way it's rolling.
func _stop(car: Car) -> void:
	for i in 600:
		if absf(car.speed) < 0.2:
			break
		_let_go()
		_hold("brake_reverse" if car.speed > 0.0 else "accelerate")
		await _frames(1)
	_let_go()
	await _frames(20)


## How far the chase camera's view is turned from the way the car points (degrees).
func _cam_off_heading(car: Car) -> float:
	var f := -_rig.camera.global_basis.z
	var h := -car.global_basis.z
	return rad_to_deg(absf(Vector2(f.x, f.z).angle_to(Vector2(h.x, h.z))))


func _snap(name: String) -> void:
	if not _args.has("shots"):
		return
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := str(_args.get("out", "user://work"))
	DirAccess.make_dir_recursive_absolute(out)
	_shot += 1
	root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, _shot, name])
	print("WORK shot %s" % name)


func _playing(car: Car, what: String) -> bool:
	var wa := car.get_node_or_null("WorkAudio") as WorkAudio
	if wa == null:
		return false
	match what:
		"alarm":
			return wa._alarm != null and wa._alarm.playing
		"hydraulic":
			return wa._hydraulic != null and wa._hydraulic.playing
		"winch":
			return wa._winch != null and wa._winch.playing
	return false


# --- the tractor ---------------------------------------------------------------------------------

func _tractor() -> void:
	var tractor := _model("hauler")
	await _get_in(tractor)
	await _snap("tractor_in")
	var d0 := _rig._user_distance
	var t := 0.0
	var alarm := false
	var worst_cam := 0.0
	while tractor.towing == null and t < 30.0:
		YardCheck.back_under(tractor)
		await _frames(1)
		t += 1.0 / 60.0
		alarm = alarm or _playing(tractor, "alarm")
		if tractor.speed < -0.8:
			worst_cam = maxf(worst_cam, _cam_off_heading(tractor))
	_let_go()
	print("WORK tractor %s after %.1f s backing; alarm beeped: %s; camera up to %.0f deg off the tractor's line while backing" % [
		"coupled by itself" if tractor.towing != null else "DID NOT COUPLE", t, alarm, worst_cam])
	await _frames(40)
	print("WORK camera pulled back from %.1f m to %.1f m for the trailer" % [d0, _rig._user_distance])
	await _snap("coupled")
	# Off with the load loose: there should be a warning.
	_hold("accelerate", 0.7)
	await _frames(360)
	_let_go()
	await _stop(tractor)
	await _snap("stopped_loose")
	await _press("strap")
	await _frames(30)
	# Back up straight a little: the camera should stay behind.
	_hold("brake_reverse", 0.5)
	worst_cam = 0.0
	alarm = false
	for i in 240:
		await _frames(1)
		alarm = alarm or _playing(tractor, "alarm")
		if tractor.speed < -1.5:
			worst_cam = maxf(worst_cam, _cam_off_heading(tractor))
	print("WORK backing the rig at %.0f km/h: camera %.0f deg off the tractor's line at most, alarm %s" % [tractor.speed * 3.6, worst_cam, alarm])
	_let_go()
	await _stop(tractor)
	await _press("hitch")
	await _frames(40)
	print("WORK uncoupled: %s; camera back in to %.1f m" % [tractor.towing == null, _rig._user_distance])
	await _get_out()


# --- the forklift ------------------------------------------------------------------------------

func _forklift() -> void:
	var fl := _model("forklift")
	var tool := fl.tool as ForkliftTool
	# The nearest pallet ahead of it.
	var pallet: Cargo = null
	var best := 1e9
	for n in _main.get_children():
		if n is Cargo:
			var local := fl.global_transform.affine_inverse() * (n as Cargo).global_position
			if local.z < -2.0 and absf(local.x) < 2.0 and -local.z < best:
				best = -local.z
				pallet = n
	await _get_in(fl)
	if _player.vehicle != fl:
		return
	if pallet == null:
		print("WORK forklift: NO PALLET AHEAD")
		await _get_out()
		return
	print("WORK forklift: the %s is %.1f m ahead" % [pallet.display_name(), best])
	# Drive in, steering at it, until the backrest meets it.
	var t := 0.0
	while t < 20.0:
		var local := fl.global_transform.affine_inverse() * pallet.global_position
		if -local.z < 1.06 + 0.62:
			break
		_let_go()
		# Rear-wheel steering: aim the nose at it.
		var steer := clampf(-local.x / maxf(1.0, -local.z) * 3.0, -1.0, 1.0)
		if steer > 0.0:
			_hold("steer_left", steer)
		elif steer < 0.0:
			_hold("steer_right", -steer)
		_hold("accelerate", 0.3 if fl.speed < 1.2 else 0.0)
		await _frames(1)
		t += 1.0 / 60.0
	_let_go()
	_hold("brake_reverse")
	await _frames(20)
	_let_go()
	_hold("work_up")
	var hyd := false
	for i in 300:
		if tool.lift >= 0.25:
			break
		await _frames(1)
		hyd = hyd or _playing(fl, "hydraulic")
	_let_go()
	_hold("aux_in")
	await _frames(90)
	_let_go()
	await _frames(30)
	var l := tool.load_on_forks()
	print("WORK forklift lifted %.2f m, hydraulics whined: %s, on the forks: %s %.0f kg, pallet %.2f m up" % [tool.lift, hyd, str(l["name"]), float(l["mass"]), pallet.global_position.y - fl.global_position.y])
	await _snap("forklift_lifted")
	_hold("brake_reverse", 0.4)
	var alarm := false
	for i in 150:
		await _frames(1)
		alarm = alarm or _playing(fl, "alarm")
	_let_go()
	var on := tool.load_on_forks()
	print("WORK forklift backed out with it: still on the forks %s, alarm %s" % [int(on["count"]) > 0, alarm])
	_hold("work_down")
	await _frames(60)
	_let_go()
	await _get_out()


# --- the tow truck -----------------------------------------------------------------------------

func _rollback() -> void:
	var truck := _model("rollback")
	var tool := truck.tool as RollbackTool
	await _get_in(truck)
	if _player.vehicle != truck:
		return
	_hold("work_down")
	var t := 0.0
	while tool.deck < 1.0 and t < 15.0:
		await _frames(1)
		t += 1.0 / 60.0
	_let_go()
	print("WORK rollback deck down in %.1f s" % t)
	# Try to drive off with it down: the HUD should say why it won't go.
	_hold("accelerate")
	await _frames(30)
	_let_go()
	await _press("hitch")
	await _frames(10)
	var car := tool.hooked as Car
	_hold("aux_in")
	t = 0.0
	var winch := false
	while car != null and t < 40.0:
		await _frames(1)
		t += 1.0 / 60.0
		winch = winch or _playing(truck, "winch")
		if (car.global_transform * Vector3(0, 0.4, -2.3)).distance_to(tool.winch_point()) < 1.1:
			break
	_let_go()
	print("WORK rollback winched the %s up in %.1f s (winch motor heard: %s)" % [car.display_name() if car != null else "NOTHING", t, winch])
	await _snap("winched")
	await _frames(30)
	await _press("strap")
	_hold("work_up")
	t = 0.0
	while tool.deck > 0.0 and t < 15.0:
		await _frames(1)
		t += 1.0 / 60.0
	_let_go()
	await _press("hitch")
	await _frames(30)
	await _snap("loaded")
	print("WORK rollback deck up in %.1f s, car strapped: %s" % [t, not truck.tie_downs.is_empty()])
	await _get_out()

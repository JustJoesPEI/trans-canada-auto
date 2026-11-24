extends SceneTree
## Checks what the player carries and how they use it, headless:
##
##   godot --headless --path . --script res://tools/loadout_check.gd
##
##  * the paint colour: picked in the character creator from the twelve,
##    saved with the look (never anything but one of the twelve), and on
##    the player's shots;
##  * the weapon wheel and what's owned (WeaponWheel, GameState): see
##    _check_wheel;
##  * the passenger seat (PassengerSeat): see _check_passenger.
##
## The player's own saved files are put back as they were afterwards.
## One "LOADOUT" line per check; exits non-zero with "LOADOUT FAIL" lines
## if any fail.

var _failures := 0
var _saved_files := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("LOADOUT ok   %s" % what)
	else:
		_failures += 1
		print("LOADOUT FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	for path: String in [PlayerLook.SAVE_PATH, GameState.SAVE_PATH]:
		_saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	await _check_colour()
	await _setup_pad()
	await _check_wheel()
	await _check_throw()
	await _check_passenger()
	await _check_officer_seat()
	for path: String in _saved_files:
		if _saved_files[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(_saved_files[path])
	if _failures > 0:
		print("LOADOUT %d check(s) failed" % _failures)
		quit(1)
	else:
		print("LOADOUT all checks passed")
		quit(0)


func _check_colour() -> void:
	_check(PaintWeapons.COLOURS.size() == 12 and PaintWeapons.COLOUR_NAMES.size() == 12, "twelve paint colours, each with a name")
	var look := PlayerLook.default_look()
	_check(look["paint"] == PaintWeapons.COLOURS[PaintWeapons.DEFAULT_COLOUR], "a new player paints %s" % PaintWeapons.colour_name(look["paint"]))
	look["paint"] = PaintWeapons.COLOURS[2]
	PlayerLook.save_look(look)
	_check(PlayerLook.load_look()["paint"] == PaintWeapons.COLOURS[2], "the chosen colour is saved with the look")
	# An edited save can't make a colour outside the twelve (a blood red).
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerLook.SAVE_PATH))
	data["look"]["paint"] = "5a0a0a"
	var f := FileAccess.open(PlayerLook.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_check(PaintWeapons.COLOURS.has(PlayerLook.load_look()["paint"]), "a saved colour is always one of the twelve")
	# The creator offers the twelve and changes the look's colour.
	var creator := CharacterCreator.new()
	root.add_child(creator)
	creator.open(PlayerLook.default_look())
	await process_frame
	var swatch: Button = null
	for c in creator.find_children("*", "Button", true, false):
		if c.has_meta("key") and str(c.get_meta("key")) == "paint3":
			swatch = c
	_check(swatch != null, "the character creator has a paint colour row")
	if swatch != null:
		swatch.pressed.emit()
		_check(creator.look["paint"] == PaintWeapons.COLOURS[3], "picking a swatch sets the paint (%s)" % PaintWeapons.colour_name(creator.look["paint"]))
	creator.queue_free()
	# The player's shots are their colour.
	var player: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.paint_colour = PaintWeapons.COLOURS[4]
	_check(PaintShots.colour_of(player, PaintWeapons.ISLANDER) == PaintWeapons.COLOURS[4], "the player's shots are their colour")
	player.queue_free()
	await process_frame



var _shots: PaintShots
var _player: PlayerController
var _rig: CameraRig


## Ground, a wall, PaintShots, and a player with a camera.
func _setup_pad() -> void:
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var fs := CollisionShape3D.new()
	fs.shape = BoxShape3D.new()
	(fs.shape as BoxShape3D).size = Vector3(300, 2, 300)
	fs.position = Vector3(0, -1, 0)
	pad.add_child(fs)
	root.add_child(pad)
	_shots = PaintShots.new()
	root.add_child(_shots)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(_player)
	_rig = (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate()
	root.add_child(_rig)
	_player.camera_rig = _rig
	_rig.target = _player
	_player.place(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	_rig.snap_to_target()
	await _frames(20)


## What's owned, the wheel, and each weapon keeping its own ammo.
func _check_wheel() -> void:
	var gs: Node = root.get_node("GameState")
	gs.call("reset_save")
	_check(gs.call("owns_weapon", "islander") and not gs.call("owns_weapon", "jam_jars"), "a new player owns the Islander only")
	var wheel := WeaponWheel.new()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(wheel)
	wheel.setup(_player)
	await process_frame
	_check(wheel.size.is_equal_approx(root.get_visible_rect().size), "the wheel covers the screen, to draw in the middle (%s)" % str(wheel.size))
	_check(wheel.slot_at(Vector2(0, -1)) == 0 and wheel.slot_at(Vector2(1, -0.3)) == 1 and wheel.slot_at(Vector2(-1, -0.3)) == 4, "the wheel's slots go round clockwise from the top")
	_check(not wheel.select("lobbyist") and str(_player.marker.weapon["id"]) == "islander", "a weapon not owned can't be taken out")
	gs.call("unlock_weapon", "lobbyist")
	gs.call("unlock_weapon", "jam_jars")
	gs.call("load_game")
	_check(gs.call("owns_weapon", "lobbyist") and gs.call("owns_weapon", "jam_jars") and (gs.get("owned_weapons") as Array) == ["islander", "lobbyist", "jam_jars"], "unlocked ones are saved, in the wheel's order")
	var time := Engine.time_scale
	wheel.open()
	_check(wheel.is_open and Engine.time_scale < time and bool(_player.fire_blocked) and not _rig.is_processing(), "open, time slows (%.2f), the view holds and the marker won't fire" % Engine.time_scale)
	wheel.pointed = PaintWeapons.ALL.keys().find("lobbyist")
	wheel.close()
	_check(not wheel.is_open and is_equal_approx(Engine.time_scale, time) and not bool(_player.fire_blocked) and _rig.is_processing(), "closed, time and the view are back")
	_check(str(_player.marker.weapon["id"]) == "lobbyist" and _player.marker.ammo == 100, "letting go takes out the one pointed at (%s)" % str(_player.marker.weapon["id"]))
	_player.marker.ammo = 37
	wheel.select("islander")
	_player.marker.ammo = 12
	wheel.select("lobbyist")
	_check(_player.marker.ammo == 37 and _player.marker.ammo_for("islander") == 12, "each weapon keeps its own ammo")
	# Driving, the wheel won't open.
	var car := Car.new()
	car.model_id = "civique"
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(20, 0.3, 0))
	await _frames(5)
	_player.enter_vehicle(car)
	_check(not wheel.can_open(), "no weapon wheel while driving")
	_player.switch_seat()
	_check(wheel.can_open(), "but a passenger can use it")
	_player.exit_vehicle(root)
	car.queue_free()
	wheel.queue_free()
	await _frames(2)


## Jam Jars: held back while Fire's held (the arc shows), thrown on letting
## go; carried, so none left is none left.
func _check_throw() -> void:
	# A marker of its own (the player's is stepped by the player each frame).
	var m := PaintMarker.new()
	m.shooter = _player
	root.add_child(m)
	m.set_weapon(PaintWeapons.JAM_JARS)
	var arc := ThrowArc.new()
	arc.marker = m
	root.add_child(arc)
	var muzzle := Vector3(0, 1.5, 0)
	var target := Vector3(0, 1.5, -10)
	for i in 10:
		m.trigger = true
		m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, target)
		await process_frame
	_check(m.holding_throw and _shots.in_flight() == 0 and m.ammo == 4, "holding Fire winds up a jar, nothing thrown yet")
	_check(arc.showing and arc.landing.y < 0.1 and arc.landing.z < -6.0, "the arc shows where it'll land (%s)" % str(arc.landing))
	m.trigger = false
	m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, target)
	_check(_shots.in_flight() == 1 and m.ammo == 3, "letting go throws it")
	for i in 3:
		for f in 90: # a jar a second at most: wait, wind up, let go
			m.trigger = f >= 60 and f < 80
			m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, target)
	_check(m.ammo == 0, "four jars and that's all (%d left)" % m.ammo)
	m.reload()
	m.trigger = true
	m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, target)
	m.trigger = false
	m.step(1.0 / 60.0, true, true, 1.0, 0.0, 3.8, muzzle, target)
	_check(m.ammo == 0 and not m.is_reloading(), "they're carried, not reloaded")
	m.refill()
	_check(m.ammo == 4, "refilled (a shop, or the debug key) there are four again")
	arc.queue_free()
	m.queue_free()
	await _frames(120)


## Shooting from cars: the driver can't; a passenger leans out and fires
## at half the rate, with wider spread, not across their own roof.
func _check_passenger() -> void:
	var car := Car.new()
	car.model_id = "civique"
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 30))
	await _frames(30)
	var m := _player.marker
	m.set_weapon(PaintWeapons.ISLANDER)
	_player.enter_vehicle(car)
	Input.action_press("aim")
	Input.action_press("fire")
	await _frames(60)
	_check(_shots.in_flight() == 0 and m.ammo == 40, "the driver can't shoot")
	Input.action_release("fire")
	Input.action_release("aim")
	_player.switch_seat()
	var seat := _player.passenger_seat
	_check(_player.passenger and seat != null and seat.get_parent() == car and _player.get_parent() == seat and car.driver == null, "switching seats puts you in the passenger seat")
	_check(signf(seat.position.x) == -signf(car.seat.position.x) and is_equal_approx(seat.position.z, car.seat.position.z), "it's the driver's seat mirrored")
	# Lean out and aim off to the right (out of the passenger's window).
	_rig.target = _player
	_rig.set_vehicle_mode(false)
	Input.action_press("aim")
	await _frames(int(PassengerSeat.LEAN_TIME * 60.0) + 10)
	_check(seat.lean >= 0.99 and _player.model.seated_lean > 0.99 and _player.aim_amount > 0.99, "holding Aim leans out (%.2f)" % seat.lean)
	_check(_player.model.position.y > 0.3 and signf(_player.model.position.x) == signf(seat.position.x), "up onto the window sill")
	# Look out of the window (the crosshair's where the shots go) and hold
	# Fire for 2 s.
	var out := car.global_transform * Vector3(signf(seat.position.x) * 8.0, 1.0, -2.0)
	var look := (out - _player.global_position) * Vector3(1, 0, 1)
	var yaw := atan2(-look.x, -look.z)
	var ammo0 := m.ammo
	var count := [0] # (a lambda can't change a local)
	m.fired.connect(func() -> void: count[0] += 1)
	for i in 20:
		_rig.yaw = yaw
		_rig.set("_yaw_goal", yaw)
		await physics_frame
	Input.action_press("fire")
	for i in 120:
		_rig.yaw = yaw
		_rig.set("_yaw_goal", yaw)
		await physics_frame
	Input.action_release("fire")
	var fired: int = count[0]
	_check(seat.in_arc(seat.aim_at), "the crosshair's out of the window (%s)" % str(seat.aim_at))
	var want := int(PaintWeapons.ISLANDER["hold_rate"] * PassengerSeat.RATE_MUL * 2.0)
	_check(fired >= want - 1 and fired <= want + 1, "holding Fire, a passenger fires at half the rate (%d in 2 s, standing would be %d)" % [fired, int(PaintWeapons.ISLANDER["hold_rate"] * 2.0)])
	_check(m.spread_mul == PassengerSeat.SPREAD_MUL and m.rate_mul == PassengerSeat.RATE_MUL and ammo0 - m.ammo == fired, "with the passenger's wider spread")
	await _frames(60)
	_check(not seat.in_arc(car.global_transform * Vector3(-signf(seat.position.x) * 8.0, 1.0, 0.0)) and seat.in_arc(out), "they can't shoot across their own car")
	Input.action_release("aim")
	await _frames(30)
	_check(seat.lean <= 0.0 and _player.aim_amount < 0.05, "letting go of Aim sits back in")
	_player.exit_vehicle(root)
	_check(_player.vehicle == null and not _player.passenger and m.rate_mul == 1.0 and m.spread_mul == 1.0 and _player.model.position == Vector3.ZERO, "out of the car, the marker's back to normal")
	_check((_player.global_position - car.global_position).dot(car.global_basis.x) * signf(seat.position.x) > 0.5, "getting out on the passenger's side")
	car.queue_free()
	await _frames(2)


## The seat works for anyone driven by code (an officer, later): a node,
## its model and marker, and three fields set each step.
func _check_officer_seat() -> void:
	var car := Car.new()
	car.model_id = "civique"
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(-30, 0.3, 30))
	var officer := Node3D.new()
	officer.name = "Officer"
	officer.add_to_group("police")
	root.add_child(officer)
	var model := HumanoidModel.new()
	officer.add_child(model)
	var marker := PaintMarker.new()
	marker.shooter = officer
	officer.add_child(marker)
	await _frames(30)
	var seat := PassengerSeat.of(car)
	seat.sit(officer, model, marker)
	var hits: Array[Dictionary] = []
	_shots.hit.connect(func(info: Dictionary) -> void:
		if info.get("shooter") == officer:
			hits.append(info))
	var target := car.global_transform * Vector3(signf(seat.position.x) * 10.0, 0.0, 0.0)
	for i in 90:
		seat.wants_lean = true
		seat.aim_at = target
		seat.trigger = seat.ready_to_fire() and i % 20 < 10
		await physics_frame
	await _frames(60)
	_check(seat.lean >= 0.99 and hits.size() > 0, "a code-driven officer leans out and fires through the same seat (%d hits)" % hits.size())
	var on_car := hits.filter(func(h: Dictionary) -> bool: return h.get("target") == car)
	_check(on_car.is_empty(), "and never paints their own car")
	seat.leave()
	_check(seat.occupant == null and not model.seated and marker.rate_mul == 1.0, "leaving lets go of them")
	car.queue_free()
	officer.queue_free()

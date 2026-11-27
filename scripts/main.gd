extends Node3D
## Wires the scene together: puts the player at the spawn point and the car
## at the curb, points the camera, hands the HUD what it needs, and handles
## getting in and out of the car. The town itself is built by the World node
## (WorldBuilder) before this runs. It also makes the PaintShots node every
## paintball goes through, and shows the marker and the paint on the HUD.

const GET_IN_DISTANCE := 2.4 ## metres from the driver's door
const GET_OUT_SPEED_KMH := 8.0 ## slow down below this to get out
## The speedometer reads a little under the car's true speed. The town stays
## 1:1, but driving "the limit" covers ground faster, so trips feel less long.
## 0.8: the dial says 50 at a true 62 km/h, and a 10-minute drive takes about 8.
## 1.0 is an honest dial.
const SPEEDO_SCALE := 0.8
## Who the player at this machine is, for car ownership (Car.owner_id).
## Cars nobody owns, and this player's own, can be got into; another
## player's can't.
const LOCAL_PLAYER_ID := "local"

@onready var world: WorldBuilder = $World
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var cars: Array[Car] = []
## Loads (pallets, crates) in the world.
var loads: Array[Cargo] = []
## The car made for a "Test here" spot set while playing (replaced by the next one).
var _test_car: Car = null
## Serves the map editor to the browser while running from Godot (F8).
var editor_server: MapEditorServer
## The player's last choice of view in a car, kept for the next time they get in.
var prefer_cockpit := false
## Every paintball in flight, and the splats (scripts/paint).
var paint_shots: PaintShots
## Hold Tab / LB: the weapons owned (scripts/paint/weapon_wheel.gd).
var weapon_wheel: WeaponWheel
## The same key in the driver's seat: the vehicle wheel (scripts/ui/vehicle_wheel.gd).
var vehicle_wheel: VehicleWheel
## Where a lobbed shot will land, while getting ready to let it go.
var throw_arc: ThrowArc
## A crime against the same target again within this (s) is the same crime.
const CRIME_REPEAT := 4.0
## s after someone paints you that painting them back isn't a crime.
const SELF_DEFENCE := 30.0
var _crime_at := {} ## target instance id -> when it was last a crime


func _ready() -> void:
	paint_shots = PaintShots.new()
	paint_shots.name = "PaintShots"
	add_child(paint_shots)
	player.marker.hit_confirmed.connect(hud.paint_hit_tick)
	# Outs only count while you're wanted (no events yet in single player):
	# painted out by the police is caught. Outside a chase paint only paints.
	player.body_paint.can_go_out = Wanted.level > 0
	Wanted.level_changed.connect(func(l: int) -> void: player.body_paint.can_go_out = l > 0)
	player.went_out.connect(_on_player_out)
	Wanted.arrested.connect(func(_r: Dictionary) -> void: player.body_paint.revive())
	paint_shots.hit.connect(_report_paint_crime)
	_setup_weapons()
	# The look chosen in the character creator (or the default one).
	var look := PlayerLook.load_look()
	player.model.set_look(look)
	player.paint_colour = look["paint"]
	# The town builds over the first few frames (see WorldBuilder.build).
	if not world.is_built:
		await world.built
	if world.is_built:
		player.place(world.get_spawn())
		_spawn_cars()
		# Town traffic (scripts/traffic/).
		add_child(TrafficManager.new())
		# People on foot (scripts/people/).
		add_child(PedestrianManager.new())
		# The Island Boo-Boo Bus and the Island Wee-Woo Brigade
		# (scripts/emergency/): sent to people hurt, cars and paint messes.
		add_child(EmergencyServices.new())
	player.camera_rig = camera_rig
	camera_rig.target = player
	camera_rig.snap_to_target()
	# Every look the town doesn't show at once drawn for a few frames behind
	# the loading screen, so its shaders aren't compiled mid-game.
	var warm := ShaderWarmup.new()
	add_child(warm)
	warm.run(get_viewport().get_camera_3d())
	hud.setup(world, player)
	world.edits_reloaded.connect(func(ms: int) -> void: hud.show_title("Map updated", "your edits, in %.1f s" % (ms / 1000.0)))
	world.test_spot_moved.connect(_go_to_test_spot)
	# The car washes (scripts/wanted/): roll through one and the paint comes
	# off, and the wanted level too if no officer saw you go in.
	var washes := CarWashes.new()
	washes.name = "CarWashes"
	washes.setup(world, player, hud)
	add_child(washes)
	# The police (scripts/police/): patrols, the chase, the impound lot.
	var police := PoliceDispatcher.new()
	police.name = "Police"
	add_child(police)
	police.setup(world, self, player, hud)
	var lot := ImpoundLot.new()
	lot.name = "ImpoundLot"
	add_child(lot)
	lot.setup(world, self, player, hud)
	# Money (scripts/economy/): your cars kept between sessions, counters,
	# jobs, and the features built on them.
	var economy := Economy.new()
	economy.name = "Economy"
	add_child(economy)
	economy.setup(world, self, player, hud)
	# Kinbook on the phone: the town's social media, and your chases on it.
	var kinbook := Kinbook.new()
	kinbook.name = "Kinbook"
	add_child(kinbook)
	kinbook.setup(world, player, hud)
	editor_server = MapEditorServer.new()
	editor_server.name = "MapEditorServer"
	editor_server.world = world
	editor_server.player = player
	add_child(editor_server)
	editor_server.start()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The map editor's "Test here" was used while playing: go straight there,
## driving a car of the chosen model if it asked for one.
func _go_to_test_spot(spot: Dictionary) -> void:
	if player.vehicle != null:
		player.exit_vehicle(self)
		player.model.visible = true
		camera_rig.target = player
		camera_rig.set_vehicle_mode(false)
	if _test_car != null:
		cars.erase(_test_car)
		_test_car.queue_free()
		_test_car = null
	if bool(spot.get("car", false)):
		var car := Car.new()
		car.model_id = str(spot.get("model", "civique"))
		if not CarModels.has_model(car.model_id):
			car.model_id = "civique"
		car.paint = Color.from_string(str(CarModels.get_model(car.model_id)["colours"][0]), car.paint)
		car.name = "TestCar"
		car.owner_id = LOCAL_PLAYER_ID
		add_child(car)
		car.global_transform = world.edit_xform(spot, 0.35)
		car.reset_physics_interpolation()
		cars.append(car)
		_watch_straps(car)
		_test_car = car
		player.enter_vehicle(car)
		camera_rig.target = car
		camera_rig.set_vehicle_mode(true)
		_vehicle_camera(car)
		_set_cockpit(prefer_cockpit)
	else:
		player.place(world.edit_xform(spot, 0.6))
	camera_rig.snap_to_target()
	world.streamer.refresh()
	hud.show_title("Test spot", "from the map editor")


## Puts the player in `car`'s driver's seat, with the driving camera (the
## custom shop, after rebuilding the car they're in).
func seat_player(car: Car) -> void:
	player.enter_vehicle(car)
	camera_rig.target = car
	camera_rig.set_vehicle_mode(true)
	_vehicle_camera(car)
	_set_cockpit(prefer_cockpit)


## Gets the player out of whatever they're in, on foot beside it.
func unseat_player() -> void:
	if player.vehicle == null:
		return
	player.exit_vehicle(self)
	player.model.visible = true
	camera_rig.target = player
	camera_rig.set_vehicle_mode(false)


## Puts the player on foot at `xform` (let out in front of the police
## station after Two Years Less a Day): out of any car, which stays where
## it was, the camera behind them, held still until the streets round them
## have loaded.
func send_player_to(xform: Transform3D) -> void:
	if player.vehicle != null:
		player.exit_vehicle(self)
		player.model.visible = true
		camera_rig.target = player
		camera_rig.set_vehicle_mode(false)
	player.place(xform)
	camera_rig.snap_to_target()
	world.streamer.refresh()
	player.set_physics_process(false)
	var t := 0.0
	while not world.streamer.is_settled() and t < 20.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if player.vehicle == null:
		player.set_physics_process(true)


func _spawn_cars() -> void:
	for c: Dictionary in world.car_starts():
		var car := Car.new()
		car.model_id = str(c["model"])
		if not CarModels.has_model(car.model_id):
			car.model_id = "civique"
		var colours: Array = CarModels.get_model(car.model_id)["colours"]
		car.livery = str(c.get("livery", ""))
		car.unit = int(c.get("unit", 0))
		var colour := str(c["colour"]) if str(c["colour"]) != "" else str(colours[0])
		if car.livery != "" and str(c["colour"]) == "":
			colour = str(CarModels.LIVERIES.get(car.livery, {}).get("colour", colour))
		car.paint = Color.from_string(colour, Color.from_string(str(colours[0]), car.paint))
		car.name = "Car_%s_%d" % [car.model_id, cars.size()]
		car.owner_id = LOCAL_PLAYER_ID
		add_child(car)
		car.global_transform = c["xform"]
		car.reset_physics_interpolation()
		cars.append(car)
		_watch_straps(car)
	# The truck yard: out of town, so it waits, held still, until the
	# streets round it are built.
	for c: Dictionary in world.yard_starts():
		if c.has("cargo"):
			var item := Cargo.new()
			item.kind = str(c["cargo"])
			item.name = "Load_%s_%d" % [item.kind, loads.size()]
			add_child(item)
			item.global_transform = c["xform"]
			item.reset_physics_interpolation()
			item.start_parked()
			loads.append(item)
			continue
		var car := Car.new()
		car.model_id = str(c["model"])
		if not CarModels.has_model(car.model_id):
			continue
		var colours: Array = CarModels.get_model(car.model_id)["colours"]
		car.paint = Color.from_string(str(c["colour"]) if str(c["colour"]) != "" else str(colours[0]), Color.WHITE)
		car.name = "Yard_%s_%d" % [car.model_id, cars.size()]
		add_child(car)
		car.global_transform = c["xform"]
		car.reset_physics_interpolation()
		car.start_parked()
		cars.append(car)
		_watch_straps(car)


func _watch_straps(car: Car) -> void:
	car.tie_downs.strap_broke.connect(func(b: RigidBody3D) -> void:
		var what := (b as Cargo).display_name() if b is Cargo else ((b as Car).display_name() if b is Car else "load")
		hud.show_title("A strap snapped", "the %s is loose" % what))
	# Coupling by backing under (or with the key): say so, and pull the
	# camera back to fit the trailer in (or in again once it's dropped).
	car.hitched.connect(func(on: bool) -> void:
		if car != player.vehicle:
			return
		if on:
			hud.show_title("Coupled the %s" % car.towing.display_name(), "the landing legs fold up as you pull away")
		_vehicle_camera(car))


## Painted out: by the police while wanted, that's being caught.
func _on_player_out(_by: Node) -> void:
	if Wanted.level > 0:
		hud.show_title("You're out", "hands up: the police have you")
		await get_tree().create_timer(1.2).timeout
		Wanted.caught()
	else:
		hud.show_title("You're out", "painted: hands up")


## The player's paint landing on someone else is a crime (section 7 of
## docs/design.md): a person is a bystander, a car is someone's car, a
## police car is police.
##
## It only counts once the police know (Wanted): painting the police (or
## their car) counts at once, they're the ones painted; so does anything an
## officer sees you do (PoliceDispatcher.sees_player_now). Anything else is
## unreported until a witness calls it in, and with nobody to call it in it
## never counts. Another hit on the same target within CRIME_REPEAT is the
## same crime. Painting back at someone who painted you first (within
## SELF_DEFENCE s) isn't a crime: they started it.
func _report_paint_crime(info: Dictionary) -> void:
	if info.get("shooter") != player:
		return
	var target: Variant = info.get("target")
	if target == null or not is_instance_valid(target) or target == player or target == player.vehicle:
		return
	var now := PlayerController.clock
	var node := target as Node
	if now - float(node.get_meta("painted_player_at", -1000.0)) < SELF_DEFENCE:
		return
	var id := node.get_instance_id()
	if now - float(_crime_at.get(id, -1000.0)) < CRIME_REPEAT:
		_crime_at[id] = now
		return
	_crime_at[id] = now
	if _crime_at.size() > 64:
		for k: int in _crime_at.keys():
			if now - float(_crime_at[k]) > CRIME_REPEAT:
				_crime_at.erase(k)
	var at: Vector3 = info.get("point", player.global_position)
	var kind := ""
	var against_police := false
	if target is Car:
		var c := target as Car
		against_police = c.police != null and c.police.is_police()
		kind = "paint_car"
	elif str(info.get("kind", "")) == "person":
		against_police = node.has_method("is_police") and bool(node.call("is_police"))
		kind = "paint_bystander"
	else:
		return
	if against_police:
		var force := "city"
		var pu: Variant = node.get_meta("police_unit") if target is Car and node.has_meta("police_unit") else null
		if pu is PoliceUnit:
			force = (pu as PoliceUnit).force
		elif node is Officer:
			force = (node as Officer).force
		Wanted.report_crime({"city": "paint_police", "fip": "paint_fip", "tactical": "paint_tactical"}.get(force, "paint_police"), at)
		return
	Wanted.player_crime(kind, at)


## The chase camera for a vehicle: further back for a big truck, and further
## still with a trailer on.
func _vehicle_camera(car: Car) -> void:
	var cam: Dictionary = car.shape.get("camera", {})
	if cam.is_empty() and car.towing == null:
		return
	var d := float(cam.get("distance", camera_rig.drive_distance))
	if car.towing != null:
		d += float(car.towing.shape["length"]) * 0.45
	camera_rig.set_profile(d, camera_rig.drive_pitch_degrees + (2.0 if car.towing != null else 0.0))
	camera_rig.look_height = float(cam.get("look_height", camera_rig.drive_look_height))


func _process(delta: float) -> void:
	var m := player.marker
	hud.set_paint(m.ammo, int(m.weapon.get("hopper", 40)), m.reload_progress() if m.is_reloading() else -1.0, player.body_paint.hits, player.is_out())
	# The crosshair's ring: the spread the next shot can go in, on screen.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var half := deg_to_rad(cam.fov * 0.5)
		hud.set_spread(tan(deg_to_rad(m.spread_now)) / tan(half) * get_viewport().get_visible_rect().size.y * 0.5)
	hud.set_weapon(str(m.weapon.get("type", m.weapon.get("name", ""))) if player.vehicle == null or player.passenger else "", m.ammo, int(m.weapon.get("hopper", 40)), m.is_carried())
	var car := player.vehicle
	if car != null and player.passenger:
		_passenger_view(car)
		return
	if car != null:
		# Camera swings in behind the car, toward where it's actually going
		# when it slides, and quicker the faster it goes. Both come from the
		# car as drawn this frame (interpolated between physics steps), not
		# its physics-step values: those move in 60-a-second jumps, and as
		# frames come unevenly (a busy street) the view swung in little jerks.
		var heading := car.get_global_transform_interpolated().basis.get_euler().y
		if car.towing != null:
			# Pulling a trailer: sit a little round toward the trailer, so on
			# a tight turn or backing up you can see where its tail is going.
			var th := car.towing.get_global_transform_interpolated().basis.get_euler().y
			heading = lerp_angle(heading, th, 0.3)
		var v := camera_rig.target_velocity()
		# Backing up, "where it's going" is behind it: follow the reverse of
		# that, or the view would swing round to the side.
		if car.speed < 0.0:
			v = -v
		var slide := 0.45 * smoothstep(2.0, 4.0, v.length())
		if slide > 0.0:
			heading = lerp_angle(heading, atan2(-v.x, -v.z), slide)
		camera_rig.follow_yaw = heading
		camera_rig.follow_rate = clampf(1.4 + absf(car.speed) * 0.12, 1.4, 4.5)
		hud.set_speed(absf(car.speed) * 3.6 * SPEEDO_SCALE, _gear_text(car))
		hud.set_crosshair(0.0)
		hud.set_scope(0.0)
		hud.set_windscreen(car.get_node_or_null("PaintCoverage") as PaintCoverage, camera_rig.cockpit, camera_rig.camera)
		_vehicle_hud(car, delta)
	else:
		hud.set_speed(-1.0)
		# From the hip, a smaller crosshair shows where the shots are going.
		hud.set_crosshair(maxf(player.aim_amount, 0.6 if player.hip_firing else 0.0))
		hud.set_scope(camera_rig.scope_amount)
		hud.set_windscreen(null, false, null)
		hud.set_controls([])
		_card_key = Vector4i.ZERO
		# What's in reach (every car's door and deck, the parked cars round
		# about): looked for ten times a second, the answer shown between.
		_foot_prompt_t -= delta
		if _foot_prompt_t <= 0.0:
			_foot_prompt_t = 0.1
			_foot_prompt = _on_foot_prompt()
		hud.set_prompt(_foot_prompt[0], _foot_prompt[1])


## The gear for the speedometer: "R" backing up, the gear number going forward.
func _gear_text(car: Car) -> String:
	if car.spec.get("engine") == null:
		return ""
	if car.gear < 0:
		return "R"
	if (car.spec["gearbox"]["ratios"] as Array).size() <= 1:
		return "F"
	return str(car.gear)


## How the loads on a vehicle and what it pulls are doing (refreshed a few
## times a second; it looks round the deck for them).
var _load_check := 0.0
var _loose := 0
var _strapped := 0
## Warned about driving off with the load loose (until it next stops).
var _warned_loose := false
## How long the flip key has been held in a car that's over (CarRighting).
var _flip_hold := 0.0


func _count_loads(car: Car) -> void:
	_loose = 0
	_strapped = 0
	for v: Car in [car, car.towing]:
		if v == null or v.deck_shapes.is_empty():
			continue
		_loose += v.tie_downs.loose_loads()
		_strapped += v.tie_downs.straps.size()


## The prompt, the controls card and the warnings while driving.
func _vehicle_hud(car: Car, delta: float) -> void:
	var kmh := absf(car.speed) * 3.6
	var stopped := kmh < GET_OUT_SPEED_KMH
	var hauls := not car.deck_shapes.is_empty() or car.shape.has("hitch")
	_load_check -= delta
	if _load_check <= 0.0 and hauls:
		_load_check = 0.25
		_count_loads(car)
	elif not hauls:
		_loose = 0
		_strapped = 0
	var has_load := _loose + _strapped > 0

	# Driving off with the load loose: say so, once.
	if kmh < 2.0:
		_warned_loose = false
	elif kmh > 12.0 and _loose > 0 and not _warned_loose:
		_warned_loose = true
		hud.show_title("The load isn't strapped down", "stop and press %s, or take the corners gently" % hud.key_for("strap"))

	# The controls card, for anything that isn't an ordinary car: made
	# again ten times a second, or at once when what it's about changes
	# (another vehicle, the lights, a trailer or a line on or off).
	_card_t -= delta
	var key := Vector4i(car.get_instance_id(), int(car.police.mode) if car.police != null else -1,
			car.towing.get_instance_id() if car.towing != null else 0, car.tow_line.get_instance_id() if car.tow_line != null else 0)
	if _card_t <= 0.0 or key != _card_key:
		_card_t = 0.1
		_card_key = key
		_controls_card(car, has_load)

	# On its roof or side: hold the flip key to put it back on its wheels.
	if CarRighting.can_right(car):
		_flip_hold = _flip_hold + delta if Input.is_action_pressed("flip_car") else 0.0
		if _flip_hold >= CarRighting.HOLD:
			_flip_hold = 0.0
			CarRighting.right(car)
		else:
			hud.set_prompt(hud.key_for("flip_car"), "Hold: put it back on its wheels" if _flip_hold <= 0.0 else "Flipping it over...")
			return
	else:
		_flip_hold = 0.0

	# The prompt: what to do next, most useful first.
	var near_trailer := Coupling.nearest(car) if car.shape.has("hitch") else {}
	var wants_to_drive := Input.get_action_strength("accelerate") > 0.1 or Input.get_action_strength("brake_reverse") > 0.1
	if not near_trailer.is_empty() and float(near_trailer["gap"]) < 4.0:
		hud.set_prompt(hud.key_for("hitch"), _coupling_hint(car, near_trailer))
	elif car.tool != null and car.tool.holds_still() and wants_to_drive and car.tool.drive_off_hint() != "":
		hud.set_prompt(hud.key_for("work_up"), car.tool.drive_off_hint())
	elif car.tool is ForkliftTool:
		hud.set_prompt(hud.key_for("interact") if stopped else "", ("Get out  ·  " if stopped else "") + car.tool.status())
	elif car.bogged > 0.85 and kmh < 6.0 and car.tow_line == null:
		hud.set_prompt(hud.key_for("hitch"), "Bogged down: ease off and rock it, or put a %s on something" % ("winch" if car.has_winch() else "tow strap"))
	elif stopped and _loose > 0 and absf(car.speed) * 3.6 < 3.0:
		hud.set_prompt(hud.key_for("strap"), "Strap the load down (%d loose)" % _loose)
	elif car.tool != null and not stopped:
		hud.set_prompt("", car.tool.status())
	elif stopped and car.tool != null:
		hud.set_prompt(hud.key_for("interact"), "Get out  ·  " + car.tool.status())
	elif stopped:
		hud.set_prompt(hud.key_for("interact"), "Get out")
	else:
		hud.set_prompt("", "")


## A strap or winch line for the HUD: what it's on and how hard it pulls.
## The controls card's rows and status line for a vehicle (Hud.set_controls).
func _controls_card(car: Car, has_load: bool) -> void:
	var rows: Array = []
	var status: Array[String] = []
	if car.police != null:
		var next: String = ["lights on", "siren on", "lights and siren off"][car.police.mode]
		rows = [[["emergency_lights"], next], [["horn"], "horn"], [["weapon_wheel"], "lights and siren (hold)", "pad"]]
		if car.police.mode == PoliceGear.Mode.LIGHTS:
			status.append("Lights flashing")
		elif car.police.mode == PoliceGear.Mode.SIREN:
			status.append("Lights and siren")
	elif car.tool != null:
		rows = car.tool.controls()
	elif car.shape.has("hitch"):
		rows = [[["hitch"], "uncouple (stopped)" if car.towing != null else "couple (or just back under)"], [["horn"], "air horn"]]
		if car.towing != null and not car.towing.deck_shapes.is_empty():
			rows.append([["strap"], "strap the load / undo (stopped)"])
	# The tow strap and winch: on the card once it's of use (off the
	# pavement, or hooked on).
	if car.tool == null and not car.shape.has("hitch") and (car.tow_line != null or car.ground != GroundMap.PAVED):
		rows.append([["hitch"], ("winch or strap" if car.has_winch() else "tow strap") + (" off" if car.tow_line != null else " on")])
		if car.tow_line != null and car.tow_line.reel_speed > 0.0:
			rows.append([["aux_in", "aux_out"], "winch in / out"])
	if car.tow_line != null:
		status.append(_line_status(car.tow_line))
	if car.towing != null:
		status.append("Pulling the %s" % car.towing.display_name())
	if has_load:
		if _loose == 0:
			status.append("Load strapped down")
		elif _strapped == 0:
			status.append("Load loose: %d unstrapped" % _loose)
		else:
			status.append("%d strapped, %d loose" % [_strapped, _loose])
	hud.set_controls(rows, "\n".join(status))


func _line_status(l: TowLine) -> String:
	var s := ("Winch on the %s" if l.reel_speed > 0.0 else "Strap on the %s") % l.other_name()
	if l.stalled:
		s += ", STALLED"
	elif l.shown_tension > 1500.0:
		s += ", pulling %.0f kN" % (l.shown_tension / 1000.0)
	else:
		s += ", slack"
	return s


## Backing under a trailer: how far to go, and which way it's off.
func _coupling_hint(car: Car, near: Dictionary) -> String:
	var trailer: Car = near["trailer"]
	var rise := float(near["rise"])
	if absf(rise) > Coupling.REACH_UP:
		return "The trailer's nose is too %s for the fifth wheel" % ("high" if rise > 0.0 else "low")
	if car.global_basis.z.dot(trailer.global_basis.z) < 0.5:
		return "Line up straight with the trailer to couple"
	var off := car.global_transform.basis.inverse() * ((trailer.model_point("kingpin") as Vector3) - (car.model_point("hitch") as Vector3))
	var gap := maxf(0.0, off.z) # the pin is still behind the jaws
	var side := ""
	if absf(off.x) > Coupling.THROAT * 0.6:
		side = "  ·  its nose is %.1f m to your %s" % [absf(off.x), "right" if off.x > 0.0 else "left"]
	if float(near["gap"]) <= Coupling.REACH:
		return "Couple the trailer"
	return "Back up %.1f m to couple%s" % [gap, side]


var _foot_prompt := ["", ""]
## The controls card: when it's next made again, and what it was about
## (the vehicle, its lights, what it's pulling, its line).
var _card_t := 0.0
var _card_key := Vector4i.ZERO
var _foot_prompt_t := 0.0


## The prompt on foot: [key, text] for what's in reach.
func _on_foot_prompt() -> Array:
	var deck := _nearest_deck()
	var parked := _nearest_parked()
	var near := _nearest_car()
	if not parked.is_empty() and bool(parked["for_sale"]):
		return [hud.key_for("interact"), UsedLot.sale_prompt(parked)]
	elif near != null and _at_passenger_door(near):
		return [hud.key_for("interact"), "Get in the passenger seat"]
	elif near != null or not parked.is_empty():
		return [hud.key_for("interact"), "Get in"]
	elif deck != null and not deck.tie_downs.is_empty():
		return [hud.key_for("strap"), "Undo the straps"]
	elif deck != null and not deck.tie_downs.loads_on_deck().is_empty():
		return [hud.key_for("strap"), "Strap the load down"]
	return ["", ""]


func _nearest_car() -> Car:
	var best: Car = null
	var best_d := GET_IN_DISTANCE
	for c in cars:
		if not c.drivable or not c.can_enter(LOCAL_PLAYER_ID):
			continue
		var d := c.door_point().distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


## The vehicle with a load deck that the player, on foot, is standing next
## to (within a couple of metres of its deck), or null.
func _nearest_deck() -> Car:
	var p := player.global_position
	for c in cars:
		for deck: CollisionShape3D in c.deck_shapes:
			var local := deck.global_transform.affine_inverse() * p
			var half := (deck.shape as BoxShape3D).size * 0.5
			if absf(local.x) < half.x + 2.0 and absf(local.z) < half.z + 2.0 and local.y > -3.0 and local.y < 2.0:
				return c
	return null


## Strap down (or let go) the loads on a vehicle and anything it's pulling.
func _toggle_straps(vehicles: Array[Car]) -> void:
	var strapped := false
	for v in vehicles:
		strapped = strapped or not v.tie_downs.is_empty()
	if strapped:
		for v in vehicles:
			v.tie_downs.release_all()
		hud.show_title("Straps off", "the load's loose")
		return
	var n := 0
	for v in vehicles:
		n += v.tie_downs.strap_all()
	if n > 0:
		hud.show_title("Strapped down", "%d load%s" % [n, "" if n == 1 else "s"])
	else:
		hud.show_title("Nothing to strap down", "put a load on the deck first")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("hitch") and player.vehicle != null:
		_hitch()
		return
	if event.is_action_pressed("strap"):
		_strap()
		return
	# On a controller the driver switches seats from the vehicle wheel (RB
	# is the handbrake); a passenger's RB switches back.
	if event.is_action_pressed("switch_seat") and player.vehicle != null and (player.passenger or not event is InputEventJoypadButton):
		_switch_seat()
		return
	if event.is_action_pressed("debug_weapons") and DevMode.on():
		_unlock_weapons()
		return
	if event.is_action_pressed("interact"):
		if player.vehicle != null:
			if absf(player.vehicle.speed) * 3.6 < GET_OUT_SPEED_KMH:
				player.model.visible = true
				player.exit_vehicle(self)
				camera_rig.target = player
				camera_rig.set_vehicle_mode(false)
		else:
			var car := _nearest_car()
			var parked := _nearest_parked()
			var as_passenger := car != null and _at_passenger_door(car)
			if not parked.is_empty() and bool(parked["for_sale"]):
				car = _buy_parked_car(parked)
			elif car == null:
				car = _take_parked_car()
			if car != null:
				player.enter_vehicle(car, as_passenger)
				camera_rig.target = car
				camera_rig.set_vehicle_mode(true)
				_vehicle_camera(car)
				_set_cockpit(prefer_cockpit)
				var info := CarModels.get_model(car.model_id)
				# A working vehicle's controls are on its card: say what it's for.
				hud.show_title(car.display_name(), str(info.get("blurb", info["kind"])) if str(car.shape.get("builder", "car")) == "truck" else str(info["kind"]))
	elif event.is_action_pressed("map_editor") and DevMode.on():
		if editor_server != null and editor_server.port != 0:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# After this input event is done, not in the middle of it.
			editor_server.open_in_browser.call_deferred()
			hud.show_title("Map editor", "opening in your browser (or paste 127.0.0.1:%d into it)" % editor_server.port)
		else:
			hud.show_title("Map editor", "run the game from Godot to use it")
	elif event.is_action_pressed("wipers") and player.vehicle != null:
		_wipe()
	elif event.is_action_pressed("camera_view") and player.vehicle != null and not player.passenger:
		if event is InputEventJoypadButton:
			# View: near, far, the driver's seat, and round again.
			if camera_rig.cockpit:
				camera_rig.set_view_step(0)
				prefer_cockpit = false
			elif camera_rig.view_step() == 1:
				prefer_cockpit = true
			else:
				camera_rig.set_view_step(1)
		else:
			prefer_cockpit = not camera_rig.cockpit
		_set_cockpit(prefer_cockpit)
	elif event.is_action_pressed("camera_view") and player.vehicle == null:
		# On foot: near, far, close in, and round again.
		camera_rig.set_view_step(camera_rig.view_step() + 1)
	# A full pause menu arrives with the UI milestone; for now Esc frees the
	# mouse and a click takes it back.
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Couple or uncouple, hook or unhook the winch, a tow strap on or off.
func _hitch() -> void:
	var car := player.vehicle
	var msg := car.hitch_action()
	if msg != "":
		hud.show_title(msg)
		_vehicle_camera(car)


## Strap the load down (or undo it): on the deck you're driving and its
## trailer, or on foot, the deck beside you.
func _strap() -> void:
	var car := player.vehicle
	if car != null:
		if absf(car.speed) * 3.6 > 3.0:
			hud.show_title("Stop first", "then strap the load")
			return
		var both: Array[Car] = [car]
		if car.towing != null:
			both.append(car.towing)
		_toggle_straps(both)
	else:
		var deck := _nearest_deck()
		if deck != null:
			var one: Array[Car] = [deck]
			_toggle_straps(one)


func _wipe() -> void:
	PaintCoverage.of(player.vehicle).wipe()


# --- the vehicle wheel ---------------------------------------------------------------------

## What's on the vehicle wheel for the car you're driving (VehicleWheel):
## only what this vehicle can do.
func _vehicle_wheel_slots() -> Array:
	var car := player.vehicle
	if car == null:
		return []
	var out: Array = []
	var stopped := absf(car.speed) * 3.6 < GET_OUT_SPEED_KMH
	out.append({"id": "phone", "title": "Phone", "sub": "Jobs, SpudDash, Kinbook, your garage", "enabled": true})
	out.append({"id": "wipers", "title": "Wipers", "sub": "Two sweeps clear the paint off the windscreen", "enabled": true})
	if car.police != null:
		var next: String = ["Lights on", "Siren on", "Lights off"][car.police.mode]
		out.append({"id": "lights", "title": next, "sub": "The lights, then the siren, then off", "enabled": true})
	var hitch := _hitch_slot(car)
	if not hitch.is_empty():
		out.append(hitch)
	if not car.deck_shapes.is_empty() or (car.towing != null and not car.towing.deck_shapes.is_empty()):
		out.append({"id": "strap", "title": "Straps", "sub": "Strap the load down, or undo it" + ("" if stopped else " (stop first)"), "enabled": stopped})
	if car.tool == null and car.drivable:
		out.append({"id": "seat", "title": "Switch seat", "sub": "Over to the passenger seat, to lean out and shoot" + ("" if stopped else " (stop first)"), "enabled": stopped})
	out.append({"id": "map", "title": "Map", "sub": "The town map, to set a waypoint", "enabled": true})
	return out


## The hitch slot: what X does in this vehicle now ({} if nothing).
func _hitch_slot(car: Car) -> Dictionary:
	if car.shape.has("hitch"):
		return {"id": "hitch", "title": "Uncouple" if car.towing != null else "Couple", "sub": "The trailer (stopped, or just back under it)", "enabled": true}
	if car.tool is RollbackTool:
		return {"id": "hitch", "title": "Winch hook", "sub": "Hook the winch on, or unhook it", "enabled": true}
	if car.tool != null:
		return {}
	var what := "Winch" if car.has_winch() else "Tow strap"
	return {"id": "hitch", "title": what + (" off" if car.tow_line != null else ""), "sub": "On another vehicle within reach, to pull it out (or take it off)", "enabled": true}


func _vehicle_wheel_chosen(id: String) -> void:
	if player.vehicle == null:
		return
	match id:
		"phone":
			var phone := Phone.find(get_tree())
			if phone != null:
				phone.open()
		"map":
			var map := WorldMap.find(get_tree())
			if map != null:
				map.open()
		"wipers":
			_wipe()
		"lights":
			if player.vehicle.police != null:
				player.vehicle.police.set_mode((player.vehicle.police.mode + 1) % 3)
		"hitch":
			_hitch()
		"strap":
			_strap()
		"seat":
			_switch_seat()


## The car parked along the street or on a dealer's lot whose driver's door
## is in reach, if no drivable car is nearer (see StreetProps.nearest_parked).
func _nearest_parked() -> Dictionary:
	var hit := StreetProps.nearest_parked(get_tree(), player.global_position, GET_IN_DISTANCE)
	if hit.is_empty():
		return hit
	var car := _nearest_car()
	if car != null and car.door_point().distance_to(player.global_position) <= (hit["door"] as Vector3).distance_to(player.global_position):
		return {}
	return hit


## A car for sale on a dealer's lot: pay its price and it's the player's,
## or, short of money, it stays locked on the lot. Null unless bought.
func _buy_parked_car(hit: Dictionary) -> Car:
	var id := str(hit["model_id"])
	# A used lot's beaters are priced by UsedLot; new cars by the model.
	var price := UsedLot.sale_price(hit)
	if not GameState.has_space():
		hud.show_title("No room for another", "You can keep %d vehicle%s. Sell one, or rent a parkade spot." % [GameState.storage_spaces(), "" if GameState.storage_spaces() == 1 else "s"])
		return null
	if not GameState.spend_money(price):
		hud.show_title("Not enough money", "%s is %s; you have %s" % [CarModels.full_name(id), CarModels.dollars(price), CarModels.dollars(GameState.money)])
		return null
	var car := _take_parked_car(hit)
	car.owner_id = LOCAL_PLAYER_ID
	# Yours for keeps: it's where you leave it next time you play.
	var owned := OwnedCars.find(get_tree())
	if owned != null:
		var vid := owned.adopt(car)
		# What it cost, for what it'll sell for (CustomShop.sale_value).
		var mods: Dictionary = GameState.vehicle(vid).get("mods", {})
		mods["paid"] = price
		GameState.set_vehicle(vid, {"mods": mods})
	return car


## Swaps the parked car in reach (or `hit`) for a real one in the same spot,
## same model and paint, that the player can get into. Nobody owns it: it's
## anyone's to drive. Null if there's none in reach. Cars for sale are
## bought instead (_buy_parked_car).
func _take_parked_car(hit := {}) -> Car:
	if hit.is_empty():
		hit = _nearest_parked()
	if hit.is_empty():
		return null
	var c := StreetProps.claim_parked(hit)
	var car := Car.new()
	car.model_id = str(c["model_id"])
	car.paint = c["paint"]
	car.name = "Car_%s_%d" % [car.model_id, cars.size()]
	add_child(car)
	var xf: Transform3D = c["xform"]
	# The parked mesh sits on the road; the car settles onto its springs.
	car.global_transform = Transform3D(xf.basis, xf.origin + xf.basis.y * 0.3)
	car.reset_physics_interpolation()
	cars.append(car)
	# Paint on the parked car goes with it, not left in the air (scripts/paint).
	paint_shots.splats.hand_to_car(car, xf)
	return car


## A parked car about to be hit at speed becomes a real one (Breakaway).
func wake_parked_car(hit: Dictionary) -> void:
	_take_parked_car(hit)


## Driver's seat view or the chase view. In the seat view the driver's head
## is hidden, since the camera is where it would be.
func _set_cockpit(on: bool) -> void:
	# Not for a passenger: the seat view is the driver's eyes, and it hides
	# your own head (which then leans out of the window without one).
	camera_rig.set_cockpit(on and not player.passenger)
	# In the driver's seat you see your own arms on the wheel, not the inside
	# of your head.
	player.model.visible = true
	player.model.hide_head = camera_rig.cockpit



# --- weapons and the passenger seat (scripts/paint) ----------------------------------------

## The weapon wheel, the throw arc, and the debug key that owns every
## weapon (F11; they're sold at Ervin's: Stores).
func _setup_weapons() -> void:
	weapon_wheel = WeaponWheel.new()
	weapon_wheel.name = "WeaponWheel"
	weapon_wheel.setup(player)
	weapon_wheel.chosen.connect(func(id: String) -> void:
		hud.show_title(str(PaintWeapons.get_weapon(id)["name"])))
	hud.add_child(weapon_wheel)
	vehicle_wheel = VehicleWheel.new()
	vehicle_wheel.name = "VehicleWheel"
	vehicle_wheel.setup(player, _vehicle_wheel_slots)
	vehicle_wheel.chosen.connect(_vehicle_wheel_chosen)
	hud.add_child(vehicle_wheel)
	throw_arc = ThrowArc.new()
	throw_arc.name = "ThrowArc"
	throw_arc.marker = player.marker
	add_child(throw_arc)
	if not InputMap.has_action("debug_weapons"):
		InputMap.add_action("debug_weapons")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F11
		InputMap.action_add_event("debug_weapons", k)


## Debug (F11; F7 is the wanted level's): every weapon owned and every hopper and jar full.
func _unlock_weapons() -> void:
	for id: String in PaintWeapons.ALL:
		GameState.unlock_weapon(id)
	player.marker.refill()
	hud.show_title("Every weapon unlocked", "debug key: hold %s for the weapon wheel" % hud.key_for("weapon_wheel"))


## Standing nearer the passenger's door than the driver's.
func _at_passenger_door(car: Car) -> bool:
	if not car.drivable or car.tool != null:
		return false
	var p := player.global_position
	return PassengerSeat.door_point(car).distance_to(p) < car.door_point().distance_to(p)


## Driver's seat to passenger seat or back, stopped (not in a working
## vehicle, which has one seat).
func _switch_seat() -> void:
	var car := player.vehicle
	if car.tool != null or not car.drivable:
		return
	if absf(car.speed) * 3.6 > GET_OUT_SPEED_KMH:
		hud.show_title("Stop first", "then switch seats")
		return
	player.switch_seat()
	camera_rig.target = car
	camera_rig.set_vehicle_mode(true)
	_vehicle_camera(car)
	_set_cockpit(false if player.passenger else prefer_cockpit)
	hud.show_title("Passenger seat" if player.passenger else "Driver's seat",
		("hold %s to lean out and shoot" % hud.key_for("aim")) if player.passenger else "")


## Riding as a passenger: the chase camera on the car, or over the
## shoulder while leaning out to aim (the crosshair with it); a card of
## what you can do.
func _passenger_view(car: Car) -> void:
	var seat := player.passenger_seat
	var leaning := seat != null and (seat.lean > 0.05 or seat.wants_lean)
	if leaning and camera_rig.target != player:
		camera_rig.target = player
		camera_rig.set_vehicle_mode(false)
	elif not leaning and camera_rig.target != car:
		camera_rig.target = car
		camera_rig.set_vehicle_mode(true)
		_vehicle_camera(car)
	if camera_rig.target == car:
		camera_rig.follow_yaw = car.get_global_transform_interpolated().basis.get_euler().y
		camera_rig.follow_rate = clampf(1.4 + absf(car.speed) * 0.12, 1.4, 4.5)
	hud.set_speed(-1.0)
	hud.set_crosshair(player.aim_amount if leaning else 0.0)
	hud.set_windscreen(null, false, null)
	var rows: Array = [[["aim"], "lean out and aim"], [["fire"], "fire (half rate)"], [["weapon_wheel"], "weapon wheel (hold)"]]
	if car.drivable and car.tool == null:
		rows.append([["switch_seat"], "drive (stopped)"])
	var why := ""
	if seat != null and seat.lean >= 0.95 and not seat.in_arc(seat.aim_at):
		why = "Can't shoot across the car"
	hud.set_controls(rows, why)
	_card_key = Vector4i.ZERO
	var stopped := absf(car.speed) * 3.6 < GET_OUT_SPEED_KMH
	hud.set_prompt(hud.key_for("interact") if stopped else "", "Get out" if stopped else "")

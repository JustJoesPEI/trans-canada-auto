extends Node3D
## Wires the scene together: puts the player at the spawn point and the car
## at the curb, points the camera, hands the HUD what it needs, and handles
## getting in and out of the car. The town itself is built by the World node
## (WorldBuilder) before this runs.

const GET_IN_DISTANCE := 2.4 ## metres from the driver's door
const GET_OUT_SPEED_KMH := 8.0 ## slow down below this to get out
## The speedometer reads a little under the car's true speed. The town stays
## 1:1, but driving "the limit" covers ground faster, so trips feel less long.
## 0.8: the dial says 50 at a true 62 km/h, and a 10-minute drive takes about 8.
## 1.0 is an honest dial.
const SPEEDO_SCALE := 0.8

@onready var world: WorldBuilder = $World
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var cars: Array[Car] = []
## Loads (pallets, crates) in the world.
var loads: Array[Cargo] = []
## The car made for a "Test here" spot set while playing (replaced by the next one).
var _test_car: Car = null
## The player's last choice of view in a car, kept for the next time they get in.
var prefer_cockpit := false


func _ready() -> void:
	# The town builds over the first few frames (see WorldBuilder.build).
	if not world.is_built:
		await world.built
	if world.is_built:
		player.place(world.get_spawn())
		_spawn_cars()
	player.camera_rig = camera_rig
	camera_rig.target = player
	camera_rig.snap_to_target()
	hud.setup(world, player)
	world.edits_reloaded.connect(func(ms: int) -> void: hud.show_title("Map updated", "your edits, in %.1f s" % (ms / 1000.0)))
	world.test_spot_moved.connect(_go_to_test_spot)
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


func _spawn_cars() -> void:
	for c: Dictionary in world.car_starts():
		var car := Car.new()
		car.model_id = str(c["model"])
		if not CarModels.has_model(car.model_id):
			car.model_id = "civique"
		var colours: Array = CarModels.get_model(car.model_id)["colours"]
		var colour := str(c["colour"]) if str(c["colour"]) != "" else str(colours[0])
		car.paint = Color.from_string(colour, Color.from_string(str(colours[0]), car.paint))
		car.name = "Car_%s_%d" % [car.model_id, cars.size()]
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


func _process(_delta: float) -> void:
	var car := player.vehicle
	if car != null:
		# Camera swings in behind the car, toward where it's actually going
		# when it slides, and quicker the faster it goes.
		var heading := car.rotation.y
		if car.speed > 3.0:
			var v := car.plane_velocity
			heading = lerp_angle(heading, atan2(-v.x, -v.y), 0.45)
		camera_rig.follow_yaw = heading
		camera_rig.follow_rate = clampf(1.4 + absf(car.speed) * 0.12, 1.4, 4.5)
		hud.set_speed(absf(car.speed) * 3.6 * SPEEDO_SCALE)
		var stopped := absf(car.speed) * 3.6 < GET_OUT_SPEED_KMH
		var near_trailer := Coupling.nearest(car) if car.shape.has("hitch") else {}
		if not near_trailer.is_empty() and float(near_trailer["gap"]) < 3.0:
			hud.set_prompt("T", "Couple the trailer (%.1f m to go)" % float(near_trailer["gap"]) if float(near_trailer["gap"]) > Coupling.REACH else "Couple the trailer")
		elif car.tool != null and car.tool.status() != "" and not stopped:
			hud.set_prompt("", car.tool.status())
		elif stopped and car.tool != null:
			hud.set_prompt("E", "Get out  ·  " + car.tool.status())
		elif stopped:
			hud.set_prompt("E", "Get out")
		else:
			hud.set_prompt("", "")
	else:
		hud.set_speed(-1.0)
		var deck := _nearest_deck()
		if _nearest_car() != null:
			hud.set_prompt("E", "Get in")
		elif deck != null and not deck.tie_downs.is_empty():
			hud.set_prompt("B", "Undo the straps")
		elif deck != null and not deck.tie_downs.loads_on_deck().is_empty():
			hud.set_prompt("B", "Strap the load down")
		else:
			hud.set_prompt("", "")


func _nearest_car() -> Car:
	var best: Car = null
	var best_d := GET_IN_DISTANCE
	for c in cars:
		if not c.drivable:
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
		var car := player.vehicle
		var msg := car.hitch_action()
		if msg != "":
			hud.show_title(msg)
			_vehicle_camera(car)
		return
	if event.is_action_pressed("strap"):
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
			if car != null:
				player.enter_vehicle(car)
				camera_rig.target = car
				camera_rig.set_vehicle_mode(true)
				_vehicle_camera(car)
				_set_cockpit(prefer_cockpit)
				hud.show_title(car.display_name(), car.tool.hint() if car.tool != null else CarModels.get_model(car.model_id)["kind"])
	elif event.is_action_pressed("camera_view") and player.vehicle != null:
		prefer_cockpit = not camera_rig.cockpit
		_set_cockpit(prefer_cockpit)
	# A full pause menu arrives with the UI milestone; for now Esc frees the
	# mouse and a click takes it back.
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Driver's seat view or the chase view. The driver is hidden in the seat
## view, since the camera is where their head would be.
func _set_cockpit(on: bool) -> void:
	camera_rig.set_cockpit(on)
	player.model.visible = not camera_rig.cockpit

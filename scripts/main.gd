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
## Who the player at this machine is, for car ownership (Car.owner_id).
## Cars nobody owns, and this player's own, can be got into; another
## player's can't.
const LOCAL_PLAYER_ID := "local"

@onready var world: WorldBuilder = $World
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var cars: Array[Car] = []
## The car made for a "Test here" spot set while playing (replaced by the next one).
var _test_car: Car = null
## Serves the map editor to the browser while running from Godot (F8).
var editor_server: MapEditorServer
## The player's last choice of view in a car, kept for the next time they get in.
var prefer_cockpit := false


func _ready() -> void:
	# The look chosen in the character creator (or the default one).
	player.model.set_look(PlayerLook.load_look())
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
		if not CarModels.MODELS.has(car.model_id):
			car.model_id = "civique"
		car.paint = Color.from_string(str(CarModels.get_model(car.model_id)["colours"][0]), car.paint)
		car.name = "TestCar"
		car.owner_id = LOCAL_PLAYER_ID
		add_child(car)
		car.global_transform = world.edit_xform(spot, 0.35)
		car.reset_physics_interpolation()
		cars.append(car)
		_test_car = car
		player.enter_vehicle(car)
		camera_rig.target = car
		camera_rig.set_vehicle_mode(true)
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
		if not CarModels.MODELS.has(car.model_id):
			car.model_id = "civique"
		var colours: Array = CarModels.get_model(car.model_id)["colours"]
		var colour := str(c["colour"]) if str(c["colour"]) != "" else str(colours[0])
		car.paint = Color.from_string(colour, Color.from_string(str(colours[0]), car.paint))
		car.name = "Car_%s_%d" % [car.model_id, cars.size()]
		car.owner_id = LOCAL_PLAYER_ID
		add_child(car)
		car.global_transform = c["xform"]
		car.reset_physics_interpolation()
		cars.append(car)


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
		if absf(car.speed) * 3.6 < GET_OUT_SPEED_KMH:
			hud.set_prompt("E", "Get out")
		else:
			hud.set_prompt("", "")
	else:
		hud.set_speed(-1.0)
		var parked := _nearest_parked()
		if not parked.is_empty() and bool(parked["for_sale"]):
			var id := str(parked["model_id"])
			hud.set_prompt("E", "Buy %s  %s" % [CarModels.full_name(id), CarModels.price_text(id)])
		elif _nearest_car() != null or not parked.is_empty():
			hud.set_prompt("E", "Get in")
		else:
			hud.set_prompt("", "")


func _nearest_car() -> Car:
	var best: Car = null
	var best_d := GET_IN_DISTANCE
	for c in cars:
		if not c.can_enter(LOCAL_PLAYER_ID):
			continue
		var d := c.door_point().distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _unhandled_input(event: InputEvent) -> void:
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
			if not parked.is_empty() and bool(parked["for_sale"]):
				car = _buy_parked_car(parked)
			elif car == null:
				car = _take_parked_car()
			if car != null:
				player.enter_vehicle(car)
				camera_rig.target = car
				camera_rig.set_vehicle_mode(true)
				_set_cockpit(prefer_cockpit)
				hud.show_title(car.display_name(), CarModels.get_model(car.model_id)["kind"])
	elif event.is_action_pressed("map_editor"):
		if editor_server != null and editor_server.port != 0:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			# After this input event is done, not in the middle of it.
			editor_server.open_in_browser.call_deferred()
			hud.show_title("Map editor", "opening in your browser (or paste 127.0.0.1:%d into it)" % editor_server.port)
		else:
			hud.show_title("Map editor", "run the game from Godot to use it")
	elif event.is_action_pressed("camera_view") and player.vehicle != null:
		prefer_cockpit = not camera_rig.cockpit
		_set_cockpit(prefer_cockpit)
	# A full pause menu arrives with the UI milestone; for now Esc frees the
	# mouse and a click takes it back.
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	var price := CarModels.price(id)
	if not GameState.spend_money(price):
		hud.show_title("Not enough money", "%s is %s; you have %s" % [CarModels.full_name(id), CarModels.price_text(id), CarModels.dollars(GameState.money)])
		return null
	var car := _take_parked_car(hit)
	car.owner_id = LOCAL_PLAYER_ID
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
	return car


## Driver's seat view or the chase view. In the seat view the driver's head
## is hidden, since the camera is where it would be.
func _set_cockpit(on: bool) -> void:
	camera_rig.set_cockpit(on)
	# In the driver's seat you see your own arms on the wheel, not the inside
	# of your head.
	player.model.visible = true
	player.model.hide_head = camera_rig.cockpit

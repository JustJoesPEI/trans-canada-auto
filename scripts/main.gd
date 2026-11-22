extends Node3D
## Wires the scene together: puts the player at the spawn point and the car
## at the curb, points the camera, hands the HUD what it needs, and handles
## getting in and out of the car. The town itself is built by the World node
## (WorldBuilder) before this runs.

const GET_IN_DISTANCE := 2.4 ## metres from the driver's door
const GET_OUT_SPEED_KMH := 8.0 ## slow down below this to get out

@onready var world: WorldBuilder = $World
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD

var cars: Array[Car] = []


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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _spawn_cars() -> void:
	for c: Dictionary in world.data.config.get("parked_cars", []):
		var car := Car.new()
		car.model_id = str(c.get("model", "civique"))
		var colours: Array = CarModels.get_model(car.model_id)["colours"]
		car.paint = Color.from_string(str(c.get("colour", colours[0])), Color.from_string(str(colours[0]), car.paint))
		car.name = "Car_%s_%d" % [car.model_id, cars.size()]
		add_child(car)
		car.global_transform = world.get_car_spawn(c)
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
		hud.set_speed(absf(car.speed) * 3.6)
		if absf(car.speed) * 3.6 < GET_OUT_SPEED_KMH:
			hud.set_prompt("E", "Get out")
		else:
			hud.set_prompt("", "")
	else:
		hud.set_speed(-1.0)
		if _nearest_car() != null:
			hud.set_prompt("E", "Get in")
		else:
			hud.set_prompt("", "")


func _nearest_car() -> Car:
	var best: Car = null
	var best_d := GET_IN_DISTANCE
	for c in cars:
		var d := c.door_point().distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = c
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if player.vehicle != null:
			if absf(player.vehicle.speed) * 3.6 < GET_OUT_SPEED_KMH:
				player.exit_vehicle(self)
				camera_rig.target = player
				camera_rig.set_vehicle_mode(false)
		else:
			var car := _nearest_car()
			if car != null:
				player.enter_vehicle(car)
				camera_rig.target = car
				camera_rig.set_vehicle_mode(true)
				hud.show_title(car.display_name(), CarModels.get_model(car.model_id)["kind"])
	# A full pause menu arrives with the UI milestone; for now Esc frees the
	# mouse and a click takes it back.
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

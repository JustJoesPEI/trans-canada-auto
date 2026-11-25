class_name OwnedCars
extends Node
## The player's own vehicles (GameState.vehicles) in the town: each one
## that isn't put away in storage is waiting where it was last left, from
## one session to the next. A bought car becomes one (adopt); where it's
## parked is saved when you get out, and every SAVE_GAP seconds while it's
## stopped, so a crash doesn't lose it far.
##
##   OwnedCars.find(tree)       the one in the game (child of Main's Economy)
##   adopt(car) -> id           make a car in the town one of yours (bought)
##   car_for(id)                the Car in the town for an owned vehicle
##   spawn(id, xform) -> Car    put an owned vehicle in the town (the
##                              storage code's "bring it round", say)
##   put_away(id, property)     take it off the street into storage
##
## Mods (GameState vehicle "mods") are the custom shop's: "parts" (CarParts
## ids) are fitted here; anything else is for the shop's own code to apply
## through the `spawned` signal.

signal spawned(car: Car, id: String)

## s between saving where a stopped car is.
const SAVE_GAP := 10.0

var main: Node
var player: Node3D
var _cars := {} ## id -> Car
var _timer := 0.0


static func find(tree: SceneTree) -> OwnedCars:
	return tree.get_first_node_in_group("owned_cars") as OwnedCars if tree != null else null


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


func _ready() -> void:
	add_to_group("owned_cars")


## Puts every owned vehicle that has a spot (and isn't in storage) back
## where it was left.
func setup(m: Node, who: Node3D) -> void:
	main = m
	player = who
	for v: Dictionary in _gs().vehicles:
		var at: Dictionary = v.get("parked", {})
		if str(v.get("stored", "")) != "" or at.is_empty():
			continue
		var xf := Transform3D(Basis(Vector3.UP, float(at.get("yaw", 0.0))), Vector3(float(at["x"]), float(at["y"]) + 0.3, float(at["z"])))
		spawn(str(v["id"]), xf)


## Makes `car` one of the player's: kept in the save from now on. Its id.
func adopt(car: Car) -> String:
	var mods := {"parts": Array(car.parts)} if not car.parts.is_empty() else {}
	var id: String = _gs().add_vehicle(car.model_id, car.paint, mods)
	car.garage_id = id
	_cars[id] = car
	_save_spot(car, true)
	return id


func car_for(id: String) -> Car:
	var c: Variant = _cars.get(id)
	return c as Car if c != null and is_instance_valid(c) else null


## Puts owned vehicle `id` in the town at `xform` (or moves it there if
## it's already out). Null if there's no such vehicle.
func spawn(id: String, xform: Transform3D) -> Car:
	var v: Dictionary = _gs().vehicle(id)
	if v.is_empty():
		return null
	var car := car_for(id)
	if car == null:
		car = Car.new()
		car.model_id = str(v["model"]) if CarModels.has_model(str(v["model"])) else "civique"
		car.paint = Color.html(str(v.get("paint", "#808080")))
		var mods: Dictionary = v.get("mods", {})
		var parts: Array[String] = []
		for p: Variant in mods.get("parts", []):
			parts.append(str(p))
		car.parts = parts
		car.owner_id = str(main.get("LOCAL_PLAYER_ID")) if main != null and main.get("LOCAL_PLAYER_ID") != null else "local"
		car.garage_id = id
		car.name = "Owned_%s_%s" % [car.model_id, id]
		(main if main != null else self).add_child(car)
		if main != null and main.get("cars") is Array:
			(main.get("cars") as Array).append(car)
		_cars[id] = car
	car.global_transform = xform
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	# Held still until the street under it is built.
	car.start_parked()
	if str(v.get("stored", "")) != "":
		_gs().set_vehicle(id, {"stored": ""})
	spawned.emit(car, id)
	return car


## Builds owned vehicle `id` again where it stands, from the save: after
## the custom shop changes its paint or parts, which a Car only reads when
## it's made. The new Car (null if it isn't out). Whoever was driving the
## old one is the caller's to put back in.
func refit(id: String) -> Car:
	var old := car_for(id)
	if old == null:
		return null
	var xf := old.global_transform
	_cars.erase(id)
	if main != null and main.get("cars") is Array:
		(main.get("cars") as Array).erase(old)
	old.garage_id = ""
	old.queue_free()
	var car := spawn(id, xf)
	_save_spot(car, true)
	return car


## Takes owned vehicle `id` off the street into `property`'s storage.
func put_away(id: String, property: String) -> void:
	var car := car_for(id)
	if car != null:
		if player != null and player.get("vehicle") == car:
			return # not with you in it
		if main != null and main.get("cars") is Array:
			(main.get("cars") as Array).erase(car)
		car.queue_free()
		_cars.erase(id)
	_gs().set_vehicle(id, {"stored": property, "parked": {}})


## Forget an owned vehicle that was sold or written off (the Car stays).
func release(id: String) -> void:
	var car := car_for(id)
	if car != null:
		car.garage_id = ""
	_cars.erase(id)
	_gs().remove_vehicle(id)


func _process(delta: float) -> void:
	_timer -= delta
	var in_car: Variant = player.get("vehicle") if player != null else null
	# Getting out saves at once; otherwise every SAVE_GAP seconds.
	for id: String in _cars.keys():
		var car := car_for(id)
		if car == null:
			_cars.erase(id)
			continue
		var was: bool = car.get_meta("_driven", false)
		var now: bool = in_car == car
		car.set_meta("_driven", now)
		if was and not now:
			_save_spot(car, true)
	if _timer > 0.0:
		return
	_timer = SAVE_GAP
	var dirty := false
	for id: String in _cars:
		var car := car_for(id)
		if car != null and car.linear_velocity.length() < 0.5:
			dirty = _save_spot(car, false) or dirty
	if dirty:
		_gs().save_game()


## Records where `car` is. True if it moved since last time.
func _save_spot(car: Car, save: bool) -> bool:
	var p := car.global_position
	var v: Dictionary = _gs().vehicle(car.garage_id)
	if v.is_empty():
		return false
	var old: Dictionary = v.get("parked", {})
	if not old.is_empty() and Vector3(float(old["x"]), float(old["y"]), float(old["z"])).distance_to(p) < 0.5:
		return false
	var yaw := car.global_basis.get_euler().y
	_gs().set_vehicle(car.garage_id, {"parked": {"x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01), "yaw": snappedf(yaw, 0.001)}}, save)
	return true

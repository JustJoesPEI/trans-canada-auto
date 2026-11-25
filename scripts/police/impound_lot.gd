class_name ImpoundLot
extends Node3D
## The impound lot (docs/design.md section 7, "What police paint does to
## your car"): a car the police stalled is towed here when the chase ends.
## Get it back at the pay machine beside the police station for a fee
## (the office is "Open Tuesdays, 10 to 11:30"; outside those hours the
## machine adds a convenience fee), or free in a later session. Your own
## cars are never lost for good. Kept in GameState.impounded.
##
## One node, a child of Main, in group "impound_lot". On foot at the
## machine, the interact key pays and the car is waiting on the street
## out front.

## The fee, and the machine's after-hours "convenience fee" on top.
const FEE := 95
const AFTER_HOURS := 25
## How close to the machine counts as at it (m).
const REACH := 2.6
## The machine stands this far from the station's front (m: right, ahead).
const OFFSET := Vector2(7.0, 2.0)

var world: WorldBuilder
var main: Node
var player: PlayerController
var hud: Node
var machine_xform := Transform3D.IDENTITY
var _sign: Label3D
var _near := false


func _ready() -> void:
	add_to_group("impound_lot")


## The GameState autoload (looked up, so tools that load this before the
## autoloads exist can compile it).
static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


static func find(tree: SceneTree) -> ImpoundLot:
	return tree.get_first_node_in_group("impound_lot") as ImpoundLot if tree != null else null


func setup(w: WorldBuilder, m: Node, p: PlayerController, h: Node) -> void:
	world = w
	main = m
	player = p
	hud = h
	var st: Transform3D = w.get_tree().root.get_node("Wanted").call("station_xform", w)
	machine_xform = Transform3D(st.basis, st * Vector3(OFFSET.x, 0.0, -OFFSET.y))
	var mi := MeshInstance3D.new()
	mi.mesh = PoliceProps.kiosk_mesh()
	WorldLod.limit(mi, 2.0)
	add_child(mi)
	_sign = Label3D.new()
	_sign.text = "IMPOUND LOT\nOpen Tuesdays, 10 to 11:30\nPay at the machine"
	PoliceGear._style(_sign, 0.12, Color(0.95, 0.95, 0.9))
	_sign.position = Vector3(0, 2.25, 0.06)
	_sign.rotation.y = PI
	WorldLod.limit(_sign, 0.6)
	add_child(_sign)
	global_transform = machine_xform


## Tow a car in: it's gone from the street and on the lot's list.
func impound(car: Car) -> void:
	_gs().impounded.append({"model": car.model_id, "paint": car.paint.to_html(), "owner": car.owner_id,
		"session": _gs().session, "parts": car.parts})
	_gs().save_game()
	if main != null and main.get("cars") is Array:
		(main.get("cars") as Array).erase(car)
	car.queue_free()


## What getting the oldest car back costs now (0 if it was towed in an
## earlier session).
func fee_now() -> int:
	if _gs().impounded.is_empty():
		return 0
	var e: Dictionary = _gs().impounded[0]
	if int(e.get("session", 0)) < _gs().session:
		return 0
	return FEE + (0 if office_open() else AFTER_HOURS)


## The office really is open (real time): Tuesdays, 10 to 11:30.
static func office_open() -> bool:
	var t := Time.get_datetime_dict_from_system()
	var minutes := int(t["hour"]) * 60 + int(t["minute"])
	return int(t["weekday"]) == 2 and minutes >= 600 and minutes < 690


func _process(_delta: float) -> void:
	if player == null or hud == null:
		return
	_near = player.vehicle == null and not _gs().impounded.is_empty() and player.global_position.distance_to(machine_xform.origin) < REACH
	if _near:
		var e: Dictionary = _gs().impounded[0]
		var fee := fee_now()
		var what := CarModels.full_name(str(e["model"]))
		var price := "free (it's been a while)" if fee == 0 else ("%s, the office is open!" % CarModels.dollars(fee) if office_open() else "%s, after-hours convenience fee included" % CarModels.dollars(fee))
		hud.call("set_prompt", hud.call("key_for", "interact"), "Get your %s back: %s" % [what, price])


func _unhandled_input(event: InputEvent) -> void:
	if _near and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		release()


## Pay and get the oldest car back, waiting on the street out front. Null
## if there's none or not enough money.
func release() -> Car:
	if _gs().impounded.is_empty():
		return null
	var fee := fee_now()
	if fee > 0 and not _gs().spend_money(fee):
		_title("Not enough money", "The machine wants %s. It does not take IOUs." % CarModels.dollars(fee))
		return null
	var e: Dictionary = _gs().impounded.pop_front()
	_gs().save_game()
	var car := Car.new()
	car.model_id = str(e["model"]) if CarModels.has_model(str(e["model"])) else "civique"
	car.paint = Color.html(str(e.get("paint", "#808080")))
	car.owner_id = str(e.get("owner", ""))
	car.name = "Released_%s" % car.model_id
	main.add_child(car)
	car.global_transform = _release_spot()
	car.reset_physics_interpolation()
	if main.get("cars") is Array:
		(main.get("cars") as Array).append(car)
	_title("Released", "Your %s is out front. They've left a parking ticket on it." % CarModels.full_name(car.model_id))
	return car


func _release_spot() -> Transform3D:
	var p := Vector2(machine_xform.origin.x, machine_xform.origin.z)
	var hit := world.network.nearest_on_streets(p, 150.0)
	if hit.is_empty():
		return Transform3D(machine_xform.basis, machine_xform.origin + Vector3.UP * 0.5)
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var sp: Array = RoadNetwork.sample(e.points, clampf(float(hit["along"]), 8.0, maxf(8.0, e.length - 8.0)))
	var q: Vector2 = sp[0]
	var dir: Vector2 = sp[1]
	q += Vector2(-dir.y, dir.x) * (e.half_width - 1.4)
	var y := world.terrain.h2(q)
	var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, y + 6.0, q.y), Vector3(q.x, y - 4.0, q.y), Layers.GROUND)
	var h := get_world_3d().direct_space_state.intersect_ray(ray)
	if not h.is_empty():
		y = float(h["position"].y)
	return Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(q.x, y + 0.4, q.y))


func _title(t: String, sub: String) -> void:
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", t, sub)

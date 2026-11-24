extends SceneTree
## Checks that police paint in the intake (Car.power_factor) cuts a car's
## top speed by the same share as its power, and that Car.full_top_speed
## matches what the car really does flat out:
##
##   godot --headless --path . --script res://tools/paint_speed_check.gd
##
## Each car is driven flat out on a long flat pad for 60 s at full power and
## again at 2/3 power. Exits non-zero if the painted top speed isn't about
## 2/3 of the clean one, or the estimate is more than 8% off.

const CARS := ["civique", "pony_gt", "halfton"]
const FACTOR := 2.0 / 3.0

var _driver := Node3D.new()
var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var shape := BoxShape3D.new()
	shape.size = Vector3(400, 2, 12000)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, -1, -5900)
	pad.add_child(cs)
	root.add_child(pad)
	root.add_child(_driver)
	for id: String in CARS:
		var clean := await _top(id, 1.0)
		var painted := await _top(id, FACTOR)
		var est := 0.0
		var probe := Car.new()
		probe.model_id = id
		root.add_child(probe)
		est = probe.full_top_speed() * 3.6
		probe.queue_free()
		var ratio := painted / maxf(clean, 0.1)
		var est_err := absf(est - clean) / maxf(clean, 0.1)
		print("PAINTSPEED %s clean %.0f km/h, painted %.0f km/h (x%.2f), estimate %.0f km/h (%.0f%% off)" % [id, clean, painted, ratio, est, est_err * 100.0])
		_check(ratio > FACTOR - 0.05 and ratio < FACTOR + 0.05, "%s painted top speed is about 2/3 of clean" % id)
		_check(est_err < 0.08, "%s full_top_speed matches the real top speed" % id)
	print("PAINTSPEED %s" % ("all checks passed" if _failed == 0 else "%d failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _top(id: String, factor: float) -> float:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))
	car.driver = _driver
	for i in 60:
		await physics_frame
	car.power_factor = factor
	Input.action_press("accelerate", 1.0)
	var top := 0.0
	for i in 60 * 60:
		await physics_frame
		top = maxf(top, car.speed * 3.6)
	Input.action_release("accelerate")
	car.queue_free()
	await physics_frame
	return top


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print(("ok    " if ok else "FAIL  ") + what)

extends SceneTree
## Checks putting a car back on its wheels (CarRighting): a car dropped on
## its roof, and one left on its side, are "over" once they settle, and
## right() stands each up on its wheels, facing the way it pointed, where it
## lay; a car on its wheels, or one leaning on a bank, isn't over.
##
##   godot --headless --path . --script res://tools/flip_check.gd -- [--car=civique]
##
## Exits non-zero on failure.

var _fails := 0
var _checks := 0
var _driver := Node3D.new()


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok    " if ok else "FAIL  ") + what)


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = Vector3(0, -1, 0)
	pad.add_child(cs)
	root.add_child(pad)
	root.add_child(_driver)
	for id: String in ([str(args["car"])] if args.has("car") else ["civique", "halfton"]):
		await _try(id, "roof", Basis(Vector3.FORWARD, PI) * Basis(Vector3.UP, 0.6), Vector3(0, 2.5, 0))
		# On its side it would fall back onto its wheels by itself on a flat
		# pad: righted at once, as if propped there.
		await _try(id, "side", Basis(Vector3.FORWARD, PI * 0.5) * Basis(Vector3.UP, -1.1), Vector3(20, 1.0, 0), 0.0)
		await _upright(id)
	print("%d of %d checks passed" % [_checks - _fails, _checks])
	quit(1 if _fails > 0 else 0)


func _spawn(id: String, xf: Transform3D) -> Car:
	var car := Car.new()
	car.model_id = id
	root.add_child(car)
	car.global_transform = xf
	car.driver = _driver
	return car


func _settle(seconds: float) -> void:
	for i in roundi(seconds * 60.0):
		await physics_frame


func _try(id: String, how: String, basis: Basis, at: Vector3, settle := 4.0) -> void:
	var car := _spawn(id, Transform3D(basis, at))
	await _settle(settle)
	_check(CarRighting.is_over(car), "%s on its %s is over (up %.2f)" % [id, how, car.global_basis.y.dot(Vector3.UP)])
	if settle > 0.0:
		_check(CarRighting.can_right(car), "%s on its %s has settled (%.2f m/s)" % [id, how, car.linear_velocity.length()])
	var was := car.global_position
	var nose := -car.global_basis.z
	nose.y = 0.0
	CarRighting.right(car)
	await _settle(3.0)
	var up := car.global_basis.y.dot(Vector3.UP)
	_check(up > 0.97, "%s from its %s stands on its wheels (up %.3f)" % [id, how, up])
	_check(not CarRighting.is_over(car), "%s from its %s isn't over any more" % [id, how])
	var moved := Vector2(car.global_position.x - was.x, car.global_position.z - was.z).length()
	_check(moved < 1.0, "%s from its %s stays where it lay (moved %.2f m)" % [id, how, moved])
	_check(car.linear_velocity.length() < 0.3, "%s from its %s sits still after (%.2f m/s)" % [id, how, car.linear_velocity.length()])
	if nose.length() > 0.3:
		var fwd := -car.global_basis.z
		fwd.y = 0.0
		_check(fwd.normalized().dot(nose.normalized()) > 0.95, "%s from its %s faces the way it pointed" % [id, how])
	car.queue_free()
	await physics_frame


func _upright(id: String) -> void:
	var car := _spawn(id, Transform3D(Basis.IDENTITY, Vector3(-20, 1.0, 0)))
	await _settle(3.0)
	_check(not CarRighting.is_over(car), "%s on its wheels isn't over" % id)
	car.global_basis = Basis(Vector3.FORWARD, 0.6) # leaning 34 degrees, on a bank
	_check(not CarRighting.is_over(car), "%s leaning 34 degrees isn't over" % id)
	car.queue_free()
	await physics_frame

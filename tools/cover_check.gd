extends SceneTree
## A paintball fight round a police car (Joe: "we kept chasing each other
## around the car and neither one of us could get a good shot off"): one
## officer pinning from behind its cruiser the way the chase sends it
## (PoliceUnit._pin_spot), the player going round the car. Then an officer
## standing well off past the car, the player crouched behind it, and
## standing in the same spot.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/cover_check.gd -- [--old]
##
## Prints, for each: how much of the time the officer had a clear shot,
## its shots and its hits on the player. `--old` moves the officer the way
## it used to (the far side of the car from the player, every step) to
## compare. Fails if going round the car gives the officer a clear shot
## less than a fifth of the time, or crouching behind the car doesn't take
## a good share of the hits off standing there.

var _player: PlayerController
var _hits := 0
var _shots := 0
var _old := false
var _failed := 0


func _initialize() -> void:
	_old = OS.get_cmdline_user_args().has("--old")
	_run.call_deferred()


func _run() -> void:
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(300, 2, 300)
	floor_shape.position = Vector3(0, -1, 0)
	pad.add_child(floor_shape)
	root.add_child(pad)
	var shots := PaintShots.new()
	root.add_child(shots)
	shots.hit.connect(func(info: Dictionary) -> void:
		if bool(info.get("police", false)) and info.get("target") == _player:
			_hits += 1)
	Car.silent = true
	var car := Car.new()
	car.model_id = PoliceUnit.MODELS["city"][0]
	car.livery = PoliceUnit.MODELS["city"][1]
	car.freeze = true
	root.add_child(car)
	car.global_position = Vector3.ZERO
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.input_enabled = false
	root.add_child(_player)
	_player.place(Transform3D(Basis.IDENTITY, Vector3(0, 0, 4.5)))
	await _frames(30)

	var circle: Dictionary = await _fight(car, "round", 14.0)
	print("COVER round the car   clear shot %3d%%  shots %3d  hits %3d" % [roundi(circle["sight"] * 100.0), circle["shots"], circle["hits"]])
	_check(float(circle["sight"]) > 0.2, "going round the car, the officer gets a clear shot a fifth of the time or more")
	var low: Dictionary = await _fight(car, "crouch", 10.0)
	print("COVER crouched behind clear shot %3d%%  shots %3d  hits %3d" % [roundi(low["sight"] * 100.0), low["shots"], low["hits"]])
	var high: Dictionary = await _fight(car, "stand", 10.0)
	print("COVER standing there  clear shot %3d%%  shots %3d  hits %3d" % [roundi(high["sight"] * 100.0), high["shots"], high["hits"]])
	_check(int(low["hits"]) < int(high["hits"]) * 0.7 or int(high["hits"]) == 0, "crouching behind the car takes hits off standing there")
	print("COVER %s" % ("all checks passed" if _failed == 0 else "%d check(s) failed" % _failed))
	quit(1 if _failed > 0 else 0)


func _fight(car: Car, how: String, secs: float) -> Dictionary:
	_player.body_paint.revive()
	_player.body_paint.clear()
	_player.bot_crouch = how == "crouch"
	# The player's side of the car: along its side, a metre off it.
	var side := car.global_basis.x * (float(car.shape["width"]) * 0.5 + 0.8)
	# By the bonnet (low: a standing chest shows over it) for the cover test.
	var by := side + (Vector3.ZERO if how == "round" else -car.global_basis.z * float(car.shape["length"]) * 0.33)
	_player.place(Transform3D(Basis.IDENTITY, car.global_position + by))
	var unit := PoliceUnit.new()
	unit.car = car
	var o := Officer.new()
	o.number = 0
	o.car = car # its own cruiser, as in a chase
	root.add_child(o)
	# Pinning from its car going round; for the cover test, standing well
	# off past the car, looking over it.
	o.global_position = car.global_position - side * (3.0 if how == "round" else 9.0) + (by - side)
	PoliceUnit.apply_foot_tuning(o, 2)
	o.shoot_at = _player
	o.marker.fired.connect(func(_k: float) -> void: _shots += 1)
	_hits = 0
	_shots = 0
	await _frames(2)
	var t := 0.0
	var seen := 0.0
	var dt := 1.0 / 60.0
	# Round the car: an ellipse a metre off its sides and ends, at a walk.
	var half_w := float(car.shape["width"]) * 0.5 + 1.0
	var half_l := float(car.shape["length"]) * 0.5 + 1.0
	var ang := 0.0
	while t < secs:
		var tpos := _player.global_position
		if how == "round":
			ang += dt * 1.9 / ((half_w + half_l) * 0.5)
			var want := car.global_transform * Vector3(cos(ang) * half_w, 0.0, sin(ang) * half_l)
			var to := want - tpos
			to.y = 0.0
			_player.bot_wish = to.limit_length(1.0)
		else:
			_player.bot_wish = Vector3.ZERO
		if _player.is_out():
			_player.body_paint.revive()
		var away := Vector3(car.global_position.x - tpos.x, 0, car.global_position.z - tpos.z).normalized()
		if how != "round":
			o.goal = Vector3.INF
		elif _old:
			o.move_to(car.global_position + away * 2.6, true)
		else:
			o.move_to(unit._pin_spot(o, tpos, away, dt), true)
		if o.firing:
			seen += dt
		await physics_frame
		t += dt
	o.queue_free()
	unit.free()
	_player.bot_wish = Vector3.ZERO
	_player.bot_crouch = false
	await _frames(60)
	return {"sight": seen / secs, "shots": _shots, "hits": _hits}


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("COVER %s %s" % ["ok  " if ok else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await physics_frame

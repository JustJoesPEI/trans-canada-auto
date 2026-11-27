extends SceneTree
## Checks The Garage (scripts/missions/garage_test.gd), Tenner's driving
## test in the Queen Parkade:
##
##   godot --headless --path . --script res://tools/garage_check.gd
##
## Puts the player in a car on the parkade's ground floor, starts the test
## (no talking, no title), and drives each move on the notepad with a
## scripted driver, saying whether it ticked. Then one more test left to
## run out: the meter expires, the parking officer walks up, the ticket's
## paid and the sheet says TICKETED. "GARAGE" lines; it fails (exit code 1)
## if Tenner isn't there, a move can't be ticked, or the ticket doesn't
## come.
##
## --info just prints the parkade's size and where things are.

var _main: Node
var _world: WorldBuilder
var _fail := false
var _trace := OS.get_cmdline_user_args().has("--trace")


## The scripted driver (Car.ai_controls).
class Driver:
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false

	func set_to(t: float, b: float, s: float, h: bool) -> void:
		throttle = t
		brake = b
		steer = s
		handbrake = h


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TrafficManager.autostart = false
	PedestrianManager.autostart = false
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	var eco: Node = null
	while eco == null:
		await process_frame
		eco = _main.get_node_or_null("Economy")
	var gt: GarageTest = null
	for i in 600:
		gt = eco.get_node_or_null("GarageTest") as GarageTest
		if gt != null and gt.tenner != null:
			break
		await process_frame
	if gt == null or gt.tenner == null:
		print("GARAGE FAIL no Tenner (the parkade wasn't found?)")
		_finish(true)
		return
	var lay := gt.lay
	print("GARAGE parkade: %.1f x %.1f m, %d levels, floor %.2f, centre %s, u %s, v %s; Tenner at %s" % [float(lay["hu"]) * 2.0, float(lay["hv"]) * 2.0, int(lay["levels"]), float(lay["floor_y"]), lay["c"], lay["u"], lay["v"], gt.tenner.global_position])
	var c2: Vector2 = lay["c"]
	await _load_streets(c2, 160.0)
	if OS.get_cmdline_user_args().has("--info"):
		_finish(false)
		return
	var player: Node3D = _main.get_node("Player")
	# The roof: the biggest flat space, clear of the ramps. Start at the far
	# end, pointing down the length toward the entrance end.
	var top := int(lay["levels"]) - 1
	var car := Car.new()
	car.model_id = "pony_gt"
	car.paint = Color(0.6, 0.1, 0.1)
	car.owner_id = "local"
	_main.add_child(car)
	var aisle_v := float(lay["hv"]) - Parkade.WALL - Parkade.STALL_DEPTH - 1.8
	var start := Parkade.world_point(lay, -float(lay["hu"]) + 6.0, aisle_v, 0, 0.6)
	var u3 := Vector3((lay["u"] as Vector2).x, 0.0, (lay["u"] as Vector2).y)
	car.global_transform = Transform3D(Basis.looking_at(u3, Vector3.UP), start)
	car.reset_physics_interpolation()
	(_main.get("cars") as Array).append(car)
	await physics_frame
	player.call("enter_vehicle", car)
	for i in 30:
		await physics_frame
	var d := Driver.new()
	car.ai_controls = d
	gt.start_now()
	print("GARAGE running: %s, meter %.0f s" % [gt.is_running(), gt.meter.seconds])
	# Each move from where the last left off; the meter is held at 60 for
	# the check (it's the moves being checked, not the driving).
	# Where each move starts on the roof, in the parkade's (u, v): the
	# middle of the roof is open over the ramp, so the straight runs are
	# down an aisle and the turns are in the far end's bay. [id, u, v,
	# facing +u (1) or -u (-1) or across (0), steps of [throttle, brake,
	# steer, handbrake, seconds]].
	var hu := float(lay["hu"])
	var aisle := -(Parkade.LANE + Parkade.WALL + (float(lay["hv"]) - Parkade.WALL - Parkade.STALL_DEPTH - Parkade.LANE - Parkade.WALL) * 0.5)
	var moves := [
		["burnout", -hu + 12.0, aisle, 1, [[1.0, 1.0, 0.0, false, 2.0]]],
		["speed", -hu + 3.0, aisle, 1, [[1.0, 0.0, 0.0, false, 8.0]]],
		["brake_test", -hu + 3.0, aisle, 1, [[1.0, 0.0, 0.0, false, 4.6], [0.0, 1.0, 0.0, false, 3.0]]],
		["slalom", -hu + 3.0, aisle, 1, [[1.0, 0.0, 0.0, false, 2.2], [0.5, 0.0, 0.7, false, 0.5], [0.5, 0.0, -0.7, false, 0.5], [0.5, 0.0, 0.7, false, 0.5], [0.5, 0.0, -0.7, false, 0.5], [0.5, 0.0, 0.7, false, 0.5], [0.5, 0.0, -0.7, false, 0.5]]],
		["handbrake", 8.0, aisle, -1, [[1.0, 0.0, 0.0, false, 2.6], [0.0, 0.0, -1.0, true, 2.5]]],
		["one_eighty", -hu + 8.0, -6.0, 0, [[0.5, 0.0, 0.0, false, 0.8], [0.45, 0.0, 1.0, false, 7.0]]],
		["three_sixty", -hu + 5.5, -4.5, 1, [[0.45, 0.0, 1.0, false, 12.0]]],
		["reverse_180", 22.0, aisle, 1, [[0.0, 1.0, 0.0, false, 2.6], [0.0, 0.0, -1.0, false, 1.4], [0.6, 0.0, 0.0, false, 1.2]]],
	]
	var v3 := Vector3((lay["v"] as Vector2).x, 0.0, (lay["v"] as Vector2).y)
	for m: Array in moves:
		if not gt.is_running():
			break
		var face := u3 * float(m[3]) if int(m[3]) != 0 else v3
		_reset_car(car, Parkade.world_point(lay, float(m[1]), float(m[2]), top, 0.5), face)
		for i in 30:
			d.set_to(0, 0, 0, true)
			await physics_frame
		await _drive(gt, d, m[4], str(m[0]))
		print("GARAGE %-12s %s" % [m[0], "ticked" if gt.moves_done().has(m[0]) else "NOT ticked"])
		if not gt.moves_done().has(m[0]):
			_fail = true
	# Backing in: straight into a stall on the roof, nose out.
	if gt.is_running():
		var xf := Parkade.stall_xform(lay, top, -1, 5, 0.5)
		var out := -xf.basis.z # its nose, to the aisle
		_reset_car(car, xf.origin + out * 6.5, out)
		for i in 30:
			d.set_to(0, 0, 0, true)
			await physics_frame
		# Reverse: the brake held from a stop reverses.
		await _drive(gt, d, [[0.0, 0.35, 0.0, false, 2.6], [0.0, 1.0, 0.0, false, 0.1], [0.0, 0.0, 0.0, false, 2.0]], "back_in")
		print("GARAGE %-12s %s" % ["back_in", "ticked" if gt.moves_done().has("back_in") else "NOT ticked"])
		if not gt.moves_done().has("back_in"):
			_fail = true
	print("GARAGE moves done: %d of %d, state %s" % [gt.moves_done().size(), GarageLines.LIST.size(), GarageTest.State.keys()[gt.state]])
	# The sheet's up if all were done: close it and try the ticket.
	for i in 30:
		await physics_frame
	if gt.sheet.visible:
		print("GARAGE sheet up after passing: %s" % bool(GarageTest.saved().get("passed", false)))
		gt.sheet.visible = false
		gt._finish_up()
	d.set_to(0, 1, 0, false)
	var money0 := int(root.get_node("GameState").get("money"))
	root.get_node("GameState").call("add_money", 100)
	gt.start_now()
	gt._left = 1.0
	var t := 0.0
	while t < 25.0 and gt.state != GarageTest.State.RESULT:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
	if gt.officer != null:
		print("GARAGE officer at %s, goal %s, car at %s" % [gt.officer.global_position, gt.officer.goal, car.global_position])
	var ticketed: bool = gt.state == GarageTest.State.RESULT and gt._why == "ticket"
	var money1 := int(root.get_node("GameState").get("money"))
	print("GARAGE ticket: %s after %.1f s, officer by the car: %s, paid %d" % [ticketed, t,
		gt.officer != null and gt.officer.global_position.distance_to(car.global_position) < 3.0, money0 + 100 - money1])
	if not ticketed:
		_fail = true
	_finish(_fail)


func _reset_car(car: Car, at: Vector3, facing: Vector3) -> void:
	car.global_transform = Transform3D(Basis.looking_at(facing, Vector3.UP), at)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_physics_interpolation()


## Steps of [throttle, brake, steer, handbrake, seconds], stopping early
## once `id` is ticked. The meter's held up while it's checked.
func _drive(gt: GarageTest, d: Driver, steps: Array, id: String) -> void:
	for s: Array in steps:
		d.set_to(float(s[0]), float(s[1]), float(s[2]), bool(s[3]))
		var t := 0.0
		while t < float(s[4]):
			await physics_frame
			t += 1.0 / Engine.physics_ticks_per_second
			gt._left = 60.0
			if _trace and Engine.get_physics_frames() % 15 == 0:
				var c := gt._car
				var l := gt._local(c.global_position)
				print("  %s t%.1f thr%.2f brk%.2f hb%s spd%.1f yawr%.2f yaw%.0f skid%.2f wheels%d at(%.1f,%.1f,%.2f) gear%d" % [id, t, c.throttle_input(), c.brake_applied, c.handbrake_on, c.speed, c.yaw_rate, rad_to_deg(gt._yaw), c.skid, c.wheels_down, l.x, l.y, l.z, c.gear])
			if gt.moves_done().has(id) or not gt.is_running():
				return


func _load_streets(p: Vector2, radius: float) -> void:
	var s := _world.streamer
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		s._focus = p
		s._has_focus = true
		s._update()
		s._reap()
		s._attach_finished(4)
		var ready := true
		for c in s._cells_within(p, radius):
			if s._dist(c, p) <= radius and not s._near.has(c):
				ready = false
				break
		if ready:
			break
		OS.delay_msec(3)
	await _world.wait_until_settled()


func _finish(failed: bool) -> void:
	print("GARAGE %s" % ("FAIL" if failed else "OK"))
	quit(1 if failed else 0)

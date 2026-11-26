extends SceneTree
## A fast lap of real streets in the real town, with the traffic, the people
## and the lamp posts all there, driven flat out by the autopilot with the
## player in the driver's seat (as the game has it, so traffic and people
## are placed round them). Lists every moment that would feel bad from the
## seat: hard stops (the car losing most of its speed at once), spins,
## launches into the air, getting stuck, and tipping; and how the lap went.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/hot_lap.gd -- [--lap=downtown] [--car=pony_gt] [--kmh=110] [--no-traffic] [--driver=human|autopilot] [--pad]
##
## The "human" driver (the default) drives the way a player does: along the
## route as the GPS draws it, turning in late and cutting corners, the
## throttle flat out or off and the steering full lock or nothing (tapping,
## as on a keyboard; --pad steers smoothly, as on a stick), braking late,
## and never swerving for anything in the way. The autopilot is the police's
## careful driver.
##
## Laps (LAPS): downtown, university, ring. One "LAP" line per event, with
## where it was (game x, z and the street) for tools/shot.sh.

const LAPS := {
	# Round the heart of downtown: down University and Great George, along
	# Grafton, down Prince to the water, along Water Street, up Queen and
	# back along Euston.
	"downtown": [["University Avenue", "Euston Street"], ["University Avenue", "Great George Street"],
		["Great George Street", "Grafton Street"], ["Grafton Street", "Prince Street"], ["Prince Street", "Water Street"],
		["Water Street", "Queen Street"], ["Queen Street", "Euston Street"], ["Euston Street", "University Avenue"]],
	# Up University Avenue to Belvedere, across to North River Road, and back
	# by Kirkwood Drive.
	"university": [["University Avenue", "Euston Street"], ["University Avenue", "Belvedere Avenue"],
		["Belvedere Avenue", "North River Road"], ["North River Road", "Kirkwood Drive"],
		["Kirkwood Drive", "University Avenue"], ["University Avenue", "Euston Street"]],
	# The bypass, as tools/drive_ring.gd has it.
	"ring": [["Riverside Drive", "Grafton Street"], ["Riverside Drive", "St Peters Road"],
		["Arterial Highway", "Upton Road Roundabout"], ["Upton Road", "Nicholas Lane"],
		["Capital Drive", "North River Road"]],
}
## Full-detail chunks within this of the car before the clock moves on.
const STREETS_READY := 150.0

var _main: Node
var _world: WorldBuilder
var _net: RoadNetwork
var _t := 0.0
var _held_ms := 0
var _focus: Node3D = null
var _events: Array[String] = []
var _counts := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var lap_name := str(args.get("lap", "downtown"))
	var model := str(args.get("car", "pony_gt"))
	var kmh := float(args.get("kmh", "110"))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	_net = _world.network
	var title := root.get_node_or_null("TitleMenu")
	if title != null and title.has_method("_resume"):
		title.call("_resume")
	if args.has("no-traffic"):
		for n in get_nodes_in_group("traffic_manager"):
			n.process_mode = Node.PROCESS_MODE_DISABLED
	# The junctions, in order.
	var stops: Array[Vector2] = []
	for leg: Array in LAPS.get(lap_name, []):
		var nid := _net.find_junction(leg[0], leg[1])
		if nid == "":
			print("LAP no junction %s / %s" % leg)
			quit(1)
			return
		stops.append(_net.nodes[nid])
	if stops.size() < 2:
		print("LAP unknown lap %s (laps: %s)" % [lap_name, ", ".join(LAPS.keys())])
		quit(1)
		return
	physics_frame.connect(_track)
	# Start just past the first junction, toward the second.
	var hit := _net.nearest_on_streets(stops[0].lerp(stops[1], 0.05), 60.0)
	var start: Vector2 = hit["pos"]
	var dir: Vector2 = (stops[1] - stops[0]).normalized()
	var player: Node3D = _main.get_node("Player")
	player.global_position = _world.terrain.at(start, 0.5)
	await _world.wait_until_settled()
	var car := Car.new()
	car.model_id = model
	car.paint = Color.from_string(str(CarModels.get_model(model)["colours"][0]), Color.WHITE)
	_main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _world.terrain.at(start, 0.4))
	car.reset_physics_interpolation()
	_main.call("seat_player", car)
	_focus = car
	var arrived := [false]
	var ap: Node
	if str(args.get("driver", "human")) == "autopilot":
		var pilot := CarAutopilot.new()
		pilot.name = "Autopilot"
		pilot.network = _net
		car.add_child(pilot)
		pilot.cruise_speed_kmh = kmh
		pilot.chase_speed_kmh = kmh
		pilot.arrived.connect(func() -> void: arrived[0] = true)
		ap = pilot
	else:
		var human := Human.new()
		human.name = "Human"
		human.net = _net
		human.car = car
		human.top_kmh = kmh
		human.pad = args.has("pad")
		car.add_child(human)
		car.ai_controls = human
		# Steered as the player's car is (not as the computer drivers').
		car.steer_assist = 0 if args.has("no-assist") else 1
		car.traction_assist = car.steer_assist
		human.arrived.connect(func() -> void: arrived[0] = true)
		ap = human
	await _wait(1.5)
	var knocked0 := Breakaway.knocked
	var t0 := _t
	var dist := 0.0
	var top := 0.0
	var last := car.global_position
	var hist: Array = [] # [t, speed] for the last half second
	var air := 0.0
	var stuck := 0.0
	var cooldown := 0.0
	var crashes := 0
	car.crashed.connect(func(_j: float) -> void: crashes += 1)
	var legs := range(1, stops.size())
	if ap is Human:
		# The whole lap as one way, so it sees each turn coming (from leg to
		# leg too) the way a player who knows the lap does.
		(ap as Human).plan_lap(stops)
		legs = [stops.size() - 1]
	for i: int in legs:
		arrived[0] = false
		var leg_t0 := _t
		var goal := stops[i]
		ap.call("drive_to", _world.terrain.at(goal, 0.0))
		while not arrived[0] and _t - leg_t0 < (240.0 if legs.size() > 1 else 900.0):
			await physics_frame
			var p := car.global_position
			dist += Vector2(p.x - last.x, p.z - last.z).length()
			last = p
			var v := absf(car.speed) * 3.6
			top = maxf(top, v)
			hist.append([_t, v, car.linear_velocity.length() * 3.6, float(ap.get("throttle")), float(ap.get("brake")), float(ap.get("steer")), car.wheels_down, car.linear_velocity.y, rad_to_deg(car.angular_velocity.y)])
			while not hist.is_empty() and _t - float(hist[0][0]) > 0.5:
				hist.pop_front()
			cooldown -= 1.0 / 60.0
			var where := "(%.0f, %.0f) %s" % [p.x, p.z, _world.street_name_at(Vector2(p.x, p.z))]
			# A hard stop: most of the speed gone in half a second.
			var was := float(hist[0][1])
			if cooldown <= 0.0 and was > 35.0 and v < was * 0.45:
				_event("hard stop", "%.0f -> %.0f km/h, hit %s at %s" % [was, v, _touching(car), where])
				if args.has("trace"):
					for h: Array in hist:
						if int(round(float(h[0]) * 60.0)) % 5 == 0:
							print("        t %.2f fwd %.0f |v| %.0f thr %.1f brk %.1f st %.1f wheels %d vy %.2f yaw %.0f" % h)
				cooldown = 2.0
			if absf(car.angular_velocity.y) > deg_to_rad(160.0) and cooldown <= 0.0 and v > 20.0:
				_event("spin", "%.0f deg/s at %.0f km/h at %s, touching %s" % [rad_to_deg(absf(car.angular_velocity.y)), v, where, _touching(car)])
				if args.has("trace"):
					for h: Array in hist:
						if int(round(float(h[0]) * 60.0)) % 3 == 0:
							print("        t %.2f fwd %.0f |v| %.0f thr %.1f brk %.1f st %.1f wheels %d vy %.2f yaw %.0f" % h)
				cooldown = 2.0
			if car.wheels_down == 0:
				air += 1.0 / 60.0
			else:
				if air > 0.25:
					_event("airborne", "%.2f s off the ground at %s" % [air, where])
				air = 0.0
			if car.global_basis.y.dot(Vector3.UP) < 0.5 and cooldown <= 0.0:
				_event("tipped", "at %s" % where)
				cooldown = 3.0
			stuck = stuck + 1.0 / 60.0 if v < 3.0 and float(ap.get("throttle")) > 0.3 else 0.0
			if stuck > 3.0:
				_event("stuck", "%s, against %s at %s" % [ap.get("state"), _touching(car), where])
				stuck = -20.0
		if not arrived[0]:
			var cp := car.global_position
			_event("gave up", "leg %d to %s (%.0f, %.0f): at (%.0f, %.0f) %s, %s" % [i, _world.street_name_at(goal), goal.x, goal.y,
				cp.x, cp.z, _world.street_name_at(Vector2(cp.x, cp.z)), ap.call("progress") if ap.has_method("progress") else ""])
	var secs := _t - t0
	print("LAP %s in a %s at up to %.0f km/h: %.2f km in %d:%02d (%.0f km/h average, top %.0f), %d knocks, %d lamp posts and the like knocked over" % [
		lap_name, model, kmh, dist / 1000.0, int(secs) / 60, int(secs) % 60, dist / maxf(secs, 0.1) * 3.6, top, crashes, Breakaway.knocked - knocked0])
	for k: String in _counts:
		print("LAP   %s: %d" % [k, _counts[k]])
	print("LAP (%.0f s waiting for streets to load)" % (_held_ms / 1000.0))
	quit()


func _event(kind: String, text: String) -> void:
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	print("LAP %6.1f s  %-9s %s" % [_t, kind, text])


## What the car's touching: names of the bodies it's in contact with.
func _touching(car: Car) -> String:
	var names: Array[String] = []
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(car.shape.get("width", 1.8)) + 0.6, 1.2, float(car.shape.get("length", 4.4)) + 1.0)
	q.shape = box
	q.transform = Transform3D(car.global_basis, car.global_position + car.global_basis.y * 0.8)
	q.collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.CARGO
	q.exclude = [car.get_rid()]
	for h: Dictionary in space.intersect_shape(q, 6):
		var n := h["collider"] as Node
		var nm := str(n.name)
		if n is StaticBody3D:
			var owner_id := (n as StaticBody3D).shape_find_owner(int(h["shape"]))
			var cs := (n as StaticBody3D).shape_owner_get_owner(owner_id)
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is CylinderShape3D:
				nm += " (r %.2f)" % ((cs as CollisionShape3D).shape as CylinderShape3D).radius
		if not names.has(nm):
			names.append(nm)
	return "nothing" if names.is_empty() else ", ".join(names)


func _track() -> void:
	_t += 1.0 / Engine.physics_ticks_per_second
	if _focus != null and is_instance_valid(_focus):
		_hold_for_streets(Vector2(_focus.global_position.x, _focus.global_position.z))


## As in tools/autopilot_check.gd: faster than real time, the clock waits
## between physics steps for the full-detail chunks round the car.
func _hold_for_streets(p: Vector2) -> void:
	var s := _world.streamer
	if _streets_ready(s, p):
		return
	var t0 := Time.get_ticks_msec()
	while not _streets_ready(s, p) and Time.get_ticks_msec() - t0 < 20000:
		s._focus = p
		s._has_focus = true
		s._update()
		s._reap()
		s._attach_finished(4)
		OS.delay_msec(3)
	_held_ms += Time.get_ticks_msec() - t0


func _streets_ready(s: ChunkStreamer, p: Vector2) -> bool:
	for c in s._cells_within(p, STREETS_READY):
		if s._dist(c, p) <= STREETS_READY and not s._near.has(c):
			return false
	return true


func _wait(secs: float) -> void:
	var until := _t + secs
	while _t < until:
		await physics_frame


## A player-like driver for the lap (see the top): read as ai_controls.
class Human:
	extends Node
	signal arrived
	var net: RoadNetwork
	var car: Car
	var top_kmh := 110.0
	var pad := false
	var throttle := 0.0
	var brake := 0.0
	var steer := 0.0
	var handbrake := false
	var state := "drive"
	var _route: StreetRoute
	var _along := 0.0
	var _back := 0.0
	var _stuck := 0.0
	var _tap := 0.0
	## How hard it'll corner and brake (m/s2): a confident player.
	const LATERAL := 7.0
	const BRAKING := 7.5

	func progress() -> String:
		return "%.0f of %.0f m along its way, %s" % [_along, _route.length, state] if _route != null else state

	var _lap: StreetRoute = null

	func plan_lap(stops: Array[Vector2]) -> void:
		var line := PackedVector2Array()
		var from := Vector2(car.global_position.x, car.global_position.z)
		for i in range(1, stops.size()):
			var leg := StreetRoute.plan(net, from, stops[i])
			if leg == null or leg.is_empty():
				continue
			for k in leg.points.size():
				if line.is_empty() or line[line.size() - 1].distance_to(leg.points[k]) > 0.5:
					line.append(leg.points[k])
			from = stops[i]
		_lap = StreetRoute.along(line)

	func drive_to(goal: Vector3) -> void:
		if _lap != null:
			_route = _lap
			_along = 0.0
			state = "drive"
			return
		var p := Vector2(car.global_position.x, car.global_position.z)
		_route = StreetRoute.plan(net, p, Vector2(goal.x, goal.z))
		_along = 0.0
		state = "drive" if _route != null and not _route.is_empty() else "lost"

	func _physics_process(delta: float) -> void:
		if _route == null or _route.is_empty():
			throttle = 0.0
			brake = 1.0
			return
		var p := Vector2(car.global_position.x, car.global_position.z)
		_along = _route.project(p, _along)
		if _along > _route.length - 10.0:
			_route = null
			arrived.emit()
			return
		var v := absf(car.speed)
		# Backing out of something, a second and a half.
		if _back > 0.0:
			_back -= delta
			state = "reverse"
			throttle = 0.0
			brake = 1.0 # braking, then (stopped) reversing
			return
		_stuck = _stuck + delta if v < 1.0 and throttle > 0.5 else 0.0
		if _stuck > 2.0:
			_stuck = 0.0
			_back = 1.5
			steer = -steer # backing out, the wheel the other way
			# Reverse is brake held once stopped: ai_controls' brake.
			return
		state = "drive"
		var f3 := -car.global_basis.z
		var fwd := Vector2(f3.x, f3.z).normalized()
		var look := 4.0 + v * 0.3
		var to := _route.sample(_along + look) - p
		var ang := atan2(fwd.x * to.y - fwd.y * to.x, fwd.dot(to)) # + to the right (x east, y south)
		var want := clampf(-ang * 2.5, -1.0, 1.0)
		if pad:
			steer = want
		else:
			# Tapping: the key held for a share of each fifth of a second as
			# big as the turn wanted (a light touch is a short tap).
			_tap = fmod(_tap + delta / 0.2, 1.0)
			steer = signf(want) if absf(want) > 0.08 and _tap < absf(want) else 0.0
		# The fastest it can take what's coming, braking in time.
		var limit := top_kmh / 3.6
		var reach := v * v / (2.0 * BRAKING) + 25.0
		var d := 2.0
		while d < reach:
			var a := _route.dir_at(_along + d)
			var b := _route.dir_at(_along + d + 6.0)
			var k := absf(a.angle_to(b)) / 6.0
			if k > 0.002:
				var vc := sqrt(LATERAL / k)
				limit = minf(limit, sqrt(vc * vc + 2.0 * BRAKING * d))
			d += 3.0
		if v > limit + 1.0:
			throttle = 0.0
			brake = 1.0
		elif v < limit - 0.5:
			throttle = 1.0
			brake = 0.0
		else:
			throttle = 0.3
			brake = 0.0

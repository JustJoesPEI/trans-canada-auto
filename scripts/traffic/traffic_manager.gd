class_name TrafficManager
extends Node3D
## Town traffic (design.md section 7½): ordinary cars driving round
## Charlatown to real places, placed and taken away out of every player's
## sight, as many as the time of day, the place and the graphics level
## call for (TrafficDensity), making room for the police.
##
## Each car is a TrafficDriver: a real Car with a CarAutopilot and civil
## driving (CivilDriving) within PHYSICS_RADIUS of the player (the nearest
## PHYSICS_CAP of them), a RoadFollower further off (no physics, drawn by
## TrafficCrowd with the parked-car meshes). Its driver picks a destination
## (TrafficDestinations: a driveway, a lot, a business), drives there by the
## streets and turns in; it's taken away once nobody can see it and another
## appears somewhere else.
##
## What happens to them:
##   * painted (PaintShots.hit on a traffic car): the driver stops and gets
##     out to stare at it (TrafficBystander), or speeds off. main.gd already
##     reports painting any car as "paint_car", so it isn't counted here too.
##   * a stopped one got into by the player: the driver gets out and
##     complains, and it's reported as "take_car" (Wanted). A moving one
##     can't be got into (owner_id "traffic" while it moves).
##   * hit, or a crash nearby: brake, honk, sometimes sit there a while,
##     then carry on, or turn round if the way's blocked.
##   * stuck (held up past their patience, spun, shunted): they drive round,
##     turn round, or K-turn back onto the road (CarAutopilot); one that
##     still gets nowhere, or ends up on its roof, is taken away unseen.
##
## Made by main.gd once the town is built. It stays idle (until `running`
## is set) when `autostart` is false, and when the game was started by a
## headless tool (`--script`), so other checks don't get random traffic.

static var autostart := true

## Placing and taking away cars (off to freeze the traffic there is).
var running := true
## Where "the player" is, if not the Player node (tests).
var focus := Vector3.INF

var main: Node
var world: WorldBuilder
var net: RoadNetwork
var data: StreetData
var player: Node3D
var hud: Node
var dests: TrafficDestinations
var drivers: Array[TrafficDriver] = []
var crowd: TrafficCrowd
var rng := RandomNumberGenerator.new()

## For tests and debugging: every placing and taking away ([time, where,
## seen by a player]), and the most there have been at once.
var spawn_log: Array = []
var removal_log: Array = []
var most := 0
var thefts := 0

var _t := 0.0
var _balance_t := 0.0
var _edges_at := Vector2.INF
var _edges: Array[RoadNetwork.RoadEdge] = []
var _weights := PackedFloat32Array()
var _wsum := 0.0
var _car_of := {} ## Car -> TrafficDriver
var _next_id := 1
var _watched: Car = null
var _ground_ray := PhysicsRayQueryParameters3D.new()
var _bystanders: Array[TrafficBystander] = []


func _ready() -> void:
	name = "Traffic"
	process_physics_priority = -2 # before the autopilots and the followers
	running = autostart and not OS.get_cmdline_args().has("--script")
	main = get_parent()
	world = CarAutopilot.find_world(self)
	net = world.network
	data = world.data
	player = main.get_node_or_null("Player") as Node3D
	hud = main.get_node_or_null("HUD")
	if player != null:
		player.add_to_group(RoadUsers.PEOPLE_GROUP)
	dests = TrafficDestinations.of(net, data)
	crowd = TrafficCrowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	rng.seed = 7471
	_ground_ray.collision_mask = Layers.GROUND
	var shots := get_tree().get_first_node_in_group("paint_shots")
	if shots != null:
		shots.connect("hit", _on_paint_hit)
	_warm_up()


## Builds every traffic look's meshes, one a frame, as the game starts (on
## the title screen), so a model's first car coming near doesn't stop the
## game for a moment while it's built (60-80 ms each, and there are some
## fifty looks).
func _warm_up() -> void:
	for m: Array in TrafficPersonality.MODELS:
		var id := str(m[0])
		# Its far-off look too (the parked-car mesh the crowd draws).
		var v := StreetProps.PARKED_MODELS.find(id)
		if v >= 0:
			StreetProps._parked_mesh(v)
		var cs: Array = CarModels.get_model(id)["colours"]
		for i in mini(TrafficPersonality.COLOURS_PER_MODEL, cs.size()):
			var paint := Color.from_string(str(cs[i]), Color.WHITE)
			if Car.is_warm(id, paint):
				continue
			await get_tree().process_frame
			if not is_inside_tree():
				return
			if i == 0:
				# The first of a model: a whole car, set up and let go at once
				# (never seen, never moved), for what's built once per model
				# rather than per paint (wheels, collision, materials).
				var car := Car.new()
				car.model_id = id
				car.paint = paint
				car.freeze = true
				car.visible = false
				car.process_mode = Node.PROCESS_MODE_DISABLED
				car.position = Vector3(0.0, -5000.0, 0.0)
				add_child(car)
				car.free()
			else:
				Car.warm_meshes(id, paint)


func focus_point() -> Vector3:
	if focus != Vector3.INF:
		return focus
	if player != null and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _physics_process(delta: float) -> void:
	TrafficSignal.advance(delta)
	_t += delta
	_watch_player_car()
	for d: TrafficDriver in drivers.duplicate():
		if d.car != null and not is_instance_valid(d.car):
			_forget(d)
			continue
		if d.car != null and d.car.driver != null:
			_taken(d)
			continue
		d.tick(delta)
		if d.car != null:
			_car_events(d)
	for b: TrafficBystander in _bystanders.duplicate():
		if not is_instance_valid(b):
			_bystanders.erase(b)
		elif b.time_left < -2.0 and not TrafficSight.seen(get_tree(), b.global_position, focus_point()):
			_bystanders.erase(b)
			b.queue_free()
	if not running:
		return
	_balance_t -= delta
	if _balance_t <= 0.0:
		_balance_t = 0.25
		_balance(focus_point())
	most = maxi(most, drivers.size())


func _process(_delta: float) -> void:
	var list: Array = []
	for d: TrafficDriver in drivers:
		if d.follower != null and is_instance_valid(d.follower):
			list.append([d.follower, d.model_index, d.paint])
	crowd.show_followers(list)


# --- how many, and where ----------------------------------------------------------

func _balance(fp: Vector3) -> void:
	var fp2 := Vector2(fp.x, fp.z)
	var lvl := TrafficDensity.level()
	var police := 0
	for n: Node in get_tree().get_nodes_in_group("vehicles"):
		if (n as Car).police != null and (n as Car).ai_controls != null:
			police += 1
	var want := TrafficDensity.target(net, fp2, get_tree(), police)
	# Take away the ones done with, too far off or hopelessly stuck, where
	# nobody can see.
	for d: TrafficDriver in drivers.duplicate():
		if _done_with(d, fp2, lvl) and not _seen(d, fp):
			_remove(d, fp)
	# Too many: the furthest one nobody can see.
	if drivers.size() > want:
		var far: TrafficDriver = null
		var far_d := float(TrafficDensity.SPAWN_MIN)
		for d: TrafficDriver in drivers:
			var dd := Vector2(d.position().x, d.position().z).distance_to(fp2)
			if dd > far_d and not _seen(d, fp):
				far_d = dd
				far = d
		if far != null:
			_remove(far, fp)
	# Too few: one or two more, out of sight.
	for i in 2:
		if drivers.size() >= want:
			break
		for attempt in 4:
			if _try_spawn(fp, lvl):
				break
	_physics_lod(fp2, lvl)


func _done_with(d: TrafficDriver, fp2: Vector2, lvl: int) -> bool:
	if d.state == TrafficDriver.State.GONE:
		return true
	if d.state == TrafficDriver.State.OUT:
		return false
	var p := d.position()
	if p == Vector3.INF:
		return true
	var dist := Vector2(p.x, p.z).distance_to(fp2)
	if dist > float(TrafficDensity.DESPAWN[lvl]):
		return true
	if d.state == TrafficDriver.State.ARRIVED and d.age - d.arrived_at > 1.5:
		return true
	if d.follower != null and not d.follower.moving:
		return true
	if d.stuck_for > 25.0 or d.upside_down > 3.0:
		return true
	return false


func _seen(d: TrafficDriver, fp: Vector3) -> bool:
	var p := d.position()
	return p != Vector3.INF and TrafficSight.seen(get_tree(), p, fp)


## The streets round the player cars can appear on, by how busy they are.
func _refresh_edges(fp2: Vector2, lvl: int) -> void:
	if _edges_at != Vector2.INF and _edges_at.distance_to(fp2) < 60.0:
		return
	_edges_at = fp2
	_edges.clear()
	_weights = PackedFloat32Array()
	_wsum = 0.0
	var r := float(TrafficDensity.SPAWN_MAX[lvl])
	for e in net.edges_near(Rect2(fp2 - Vector2(r, r), Vector2(r, r) * 2.0)):
		var w := TrafficDensity.class_weight(e)
		if w <= 0.0 or e.bridge or e.length < 24.0:
			continue
		# Nearer streets more often (still out of sight): the streets round
		# the player are what has to look busy.
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		w *= 160.0 / (160.0 + mid.distance_to(fp2))
		_edges.append(e)
		_wsum += w * e.length
		_weights.append(_wsum)


func _try_spawn(fp: Vector3, lvl: int) -> bool:
	var fp2 := Vector2(fp.x, fp.z)
	_refresh_edges(fp2, lvl)
	if _edges.is_empty():
		return false
	var pick := rng.randf() * _wsum
	var i := _weights.bsearch(pick)
	var e: RoadNetwork.RoadEdge = _edges[mini(i, _edges.size() - 1)]
	var along := rng.randf_range(10.0, e.length - 10.0)
	var forward := rng.randf() < 0.5
	if e.oneway != 0:
		forward = e.oneway == 1
	var sp: Array = RoadNetwork.sample(e.points, along)
	var dir: Vector2 = (sp[1] as Vector2) * (1.0 if forward else -1.0)
	var pos: Vector2 = (sp[0] as Vector2) + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, forward)
	var dist := pos.distance_to(fp2)
	if dist < TrafficDensity.SPAWN_MIN or dist > float(TrafficDensity.SPAWN_MAX[lvl]):
		return false
	var p3 := Vector3(pos.x, world.terrain.h2(pos), pos.y)
	if TrafficSight.seen(get_tree(), p3, fp):
		return false
	for u: RoadUsers.User in RoadUsers.all(get_tree()):
		if u.pos.distance_to(pos) < 16.0:
			return false
	var dest := dests.pick(rng, pos, 250.0, 1400.0)
	if dest.is_empty():
		return false
	var r := StreetRoute.plan(net, pos, dest["street"], plan_options(dir))
	if r.is_empty() or r.partial or r.gaps > 0 or r.length < 80.0:
		return false
	var d := _new_driver(dest)
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3))
	rf.set_route(r)
	rf.speed = minf(JunctionRules.limit_kmh(e) / 3.6 * 0.8, r.limit_at(0.0))
	if d.character == "chatter":
		d.chat_at = rng.randf_range(60.0, maxf(61.0, r.length - 40.0))
	spawn_log.append([_t, p3, TrafficSight.seen(get_tree(), p3, fp)])
	return true


## How traffic plans its routes: by the rules of the road, gentle corners.
static func plan_options(heading: Vector2) -> Dictionary:
	return {"obey_oneway": true, "heading": heading, "lat_accel": 3.2, "brake_accel": 2.6, "top_speed": 25.0}


func _new_driver(dest: Dictionary) -> TrafficDriver:
	var d := TrafficDriver.new()
	d.id = _next_id
	_next_id += 1
	d.rng.seed = rng.randi()
	d.model_id = TrafficPersonality.pick_model(d.rng)
	d.model_index = maxi(0, StreetProps.PARKED_MODELS.find(d.model_id))
	d.paint = TrafficPersonality.pick_colour(d.rng, d.model_id)
	d.character = TrafficPersonality.pick_character(d.rng, d.model_id, TrafficDensity.current_month(get_tree()))
	d.civil = CivilDriving.new()
	TrafficPersonality.apply(d.civil, d.rng, d.character)
	d.dest = dest
	_set_dest(d, dest)
	drivers.append(d)
	return d


## Where a driver's going: the mouth of the driveway, on the street.
func _set_dest(d: TrafficDriver, dest: Dictionary) -> void:
	d.dest = dest
	d.turned_in = false
	var at: Vector2 = dest["street"]
	d.dest3 = Vector3(at.x, world.terrain.h2(at), at.y)


## A car at its driveway: it turns in, if the way in is clear of walls
## (some mapped driveways run into garages), and parks; else it parks at
## the curb.
func _car_arrived(d: TrafficDriver) -> void:
	if d.car == null or d.turned_in or d.state != TrafficDriver.State.DRIVE:
		d.on_arrived()
		return
	d.turned_in = true
	var inside: Vector2 = d.dest.get("inside", d.dest["street"])
	var gy := _ground_at(Vector3(inside.x, d.car.global_position.y, inside.y))
	if is_nan(gy) or not _way_in_clear(d.car, inside, gy):
		d.on_arrived()
		return
	d.pilot.drive_to(Vector3(inside.x, gy, inside.y))


func _way_in_clear(car: Car, inside: Vector2, gy: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := car.global_position + Vector3.UP * 0.8
	var to := Vector3(inside.x, gy + 0.8, inside.y)
	var q := PhysicsRayQueryParameters3D.create(from, to, Layers.SOLID)
	q.exclude = [car.get_rid()]
	if not space.intersect_ray(q).is_empty():
		return false
	var box := BoxShape3D.new()
	box.size = Vector3(float(car.shape.get("width", 1.8)) + 0.4, 1.2, float(car.shape.get("length", 4.6)) + 0.6)
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = box
	sq.collision_mask = Layers.SOLID
	var d := (to - from)
	sq.transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), to + Vector3.UP * 0.2)
	sq.exclude = [car.get_rid()]
	return space.intersect_shape(sq, 1).is_empty()


func _make_follower(d: TrafficDriver, xf: Transform3D) -> RoadFollower:
	var rf := RoadFollower.new()
	rf.name = "TrafficFar_%d" % d.id
	rf.network = net
	rf.terrain = world.terrain
	rf.speed_kmh = 90.0
	var shape := CarModels.shape_for(d.model_id)
	rf.half_length = float(shape.get("length", 4.6)) * 0.5
	rf.half_width = float(shape.get("width", 1.8)) * 0.5
	add_child(rf)
	rf.global_transform = xf
	rf.civil = d.civil
	d.civil.attach(rf, net, data)
	rf.arrived.connect(d.on_arrived)
	d.follower = rf
	return rf


func _remove(d: TrafficDriver, fp: Vector3) -> void:
	var p := d.position()
	removal_log.append([_t, p, p != Vector3.INF and TrafficSight.seen(get_tree(), p, fp)])
	if d.car != null and is_instance_valid(d.car):
		_drop_car(d.car)
		d.car.queue_free()
	if d.follower != null and is_instance_valid(d.follower):
		d.follower.queue_free()
	if d.bystander != null and is_instance_valid(d.bystander):
		d.bystander.queue_free()
	d.car = null
	d.follower = null
	d.state = TrafficDriver.State.GONE
	drivers.erase(d)


func _forget(d: TrafficDriver) -> void:
	_car_of.erase(d.car)
	d.car = null
	d.state = TrafficDriver.State.GONE
	drivers.erase(d)


func _drop_car(car: Car) -> void:
	_car_of.erase(car)
	var cars: Variant = main.get("cars")
	if cars is Array:
		(cars as Array).erase(car)


# --- near and far -----------------------------------------------------------------

## Full physics for the nearest, within the radius; the road follower for
## the rest.
func _physics_lod(fp2: Vector2, lvl: int) -> void:
	var radius := float(TrafficDensity.PHYSICS_RADIUS[lvl])
	var cap: int = TrafficDensity.PHYSICS_CAP[lvl]
	var cars := 0
	var near: Array = []
	for d: TrafficDriver in drivers:
		var p := d.position()
		if p == Vector3.INF:
			continue
		var dist := Vector2(p.x, p.z).distance_to(fp2)
		if d.car != null:
			cars += 1
			if dist > radius + 40.0 and d.state == TrafficDriver.State.DRIVE:
				if _to_follower(d):
					cars -= 1
		elif d.follower != null and dist < radius and d.state == TrafficDriver.State.DRIVE:
			near.append([dist, d])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var made := 0
	for x: Array in near:
		if cars >= cap or made >= 2:
			break
		if _to_car(x[1]):
			cars += 1
			made += 1


func _ground_at(p: Vector3) -> float:
	_ground_ray.from = p + Vector3.UP * 4.0
	_ground_ray.to = p + Vector3.DOWN * 4.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if hit.is_empty() or str((hit["collider"] as Node).name) == "SafetyFloor":
		return NAN
	return (hit["position"] as Vector3).y


## A far follower becomes a real car, moving as it was.
func _to_car(d: TrafficDriver) -> bool:
	var rf := d.follower
	if rf == null or not rf.moving:
		return false
	var gy := _ground_at(rf.global_position)
	if is_nan(gy):
		return false # the street there isn't built yet
	var car := Car.new()
	car.model_id = d.model_id
	car.paint = d.paint
	car.name = "Traffic_%s_%d" % [d.model_id, d.id]
	car.owner_id = "traffic"
	main.add_child(car)
	var p := rf.global_position
	car.global_transform = Transform3D(rf.global_basis, Vector3(p.x, gy + 0.3, p.z))
	car.reset_physics_interpolation()
	car.linear_velocity = -rf.global_basis.z * rf.speed
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = net
	ap.cruise_speed_kmh = 90.0
	ap.corner_accel = 3.2
	ap.brake_accel = 3.0
	car.add_child(ap)
	ap.civil = d.civil
	d.civil.attach(car, net, data)
	ap.use_civil_driving(true)
	ap.drive_route(rf.route, rf.along, d.dest3)
	ap.arrived.connect(_car_arrived.bind(d))
	car.crashed.connect(_on_crash.bind(d))
	var cars: Variant = main.get("cars")
	if cars is Array:
		(cars as Array).append(car)
	_car_of[car] = d
	rf.queue_free()
	d.follower = null
	d.car = car
	d.pilot = ap
	return true


## A car far from everyone goes back to moving without physics.
func _to_follower(d: TrafficDriver) -> bool:
	var car := d.car
	var ap := d.pilot
	if ap == null or ap.route == null or ap.route.is_empty() or ap.state != "route" or d.upside_down > 0.0:
		return false
	var p := car.global_position
	if ap.route.off_line(Vector2(p.x, p.z), ap.along) > 3.0:
		return false
	var f := -car.global_basis.z
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), p))
	rf.set_route(ap.route)
	rf.along = ap.along
	rf.speed = maxf(car.speed, 0.0)
	rf._place()
	_drop_car(car)
	car.queue_free()
	d.car = null
	d.pilot = null
	return true


# --- what happens to them -----------------------------------------------------------

func _car_events(d: TrafficDriver) -> void:
	if d.civil.want_reroute and d.state == TrafficDriver.State.DRIVE:
		d.civil.want_reroute = false
		turn_round(d)
	if d.getting_out and absf(d.car.speed) < 0.5:
		d.getting_out = false
		_get_out(d, TrafficBystander.Mode.STARE)
	if d.state == TrafficDriver.State.DRIVE and d.stuck_for > 12.0 and d.reroutes < 2 and d.pilot != null and d.pilot._recover <= 0.0:
		turn_round(d)


## Give up on the way ahead: somewhere back the other way.
func turn_round(d: TrafficDriver) -> void:
	if d.pilot == null:
		return
	d.reroutes += 1
	d.stuck_for = 0.0
	var p := d.car.global_position
	var f := -d.car.global_basis.z
	var dest := dests.pick(d.rng, Vector2(p.x, p.z), 200.0, 1200.0, -Vector2(f.x, f.z).normalized())
	if dest.is_empty():
		return
	d.dest = dest
	_set_dest(d, dest)
	d.pilot.drive_to(d.dest3)
	d.civil.hazard = "turn_round"


func _get_out(d: TrafficDriver, how: TrafficBystander.Mode) -> void:
	if d.car == null:
		return
	var car := d.car
	var b := TrafficBystander.new()
	b.name = "Driver_%d" % d.id
	add_child(b)
	var w := float(car.shape.get("width", 1.8))
	var at := car.global_transform * Vector3(-(w * 0.5 + 0.8), 0.0, float(car.shape["seat"][2]))
	var gy := _ground_at(at)
	if not is_nan(gy):
		at.y = gy
	b.setup(car, how, d.rng, Transform3D(car.global_basis, at))
	_bystanders.append(b)
	if how == TrafficBystander.Mode.STARE:
		d.state = TrafficDriver.State.OUT
		d.bystander = b
		d.civil.hold_for(600.0, "out")
		b.done.connect(_back_in.bind(d))


func _back_in(d: TrafficDriver) -> void:
	if d.bystander != null and is_instance_valid(d.bystander):
		_bystanders.erase(d.bystander)
		d.bystander.queue_free()
	d.bystander = null
	if d.car != null and is_instance_valid(d.car) and d.car.driver == null:
		d.state = TrafficDriver.State.DRIVE
		d.civil.release_hold()


## The player got into a traffic car: its driver gets out and complains,
## and that's a crime.
func _taken(d: TrafficDriver) -> void:
	var car := d.car
	if d.pilot != null and is_instance_valid(d.pilot):
		car.ai_controls = null
		d.pilot.queue_free()
	car.owner_id = ""
	if d.bystander != null and is_instance_valid(d.bystander):
		_bystanders.erase(d.bystander)
		d.bystander.queue_free()
		d.bystander = null
	var stay := d.state == TrafficDriver.State.OUT
	d.pilot = null
	_get_out(d, TrafficBystander.Mode.COMPLAIN)
	_car_of.erase(car)
	d.car = null
	d.state = TrafficDriver.State.GONE
	drivers.erase(d)
	thefts += 1
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null:
		wanted.call("report_crime", "take_car", car.global_position)
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", "\"Hey! That's my car!\"", "taking someone's car is a crime" if not stay else "they only got out to look at the paint")


func _on_paint_hit(info: Dictionary) -> void:
	var target: Variant = info.get("target")
	if not (target is Car) or not _car_of.has(target):
		return
	var d: TrafficDriver = _car_of[target]
	if d.state != TrafficDriver.State.DRIVE or d.getting_out:
		if d.bystander != null and is_instance_valid(d.bystander):
			d.bystander.time_left += 3.0 # more to stare at
		return
	d.civil.hazard = "painted"
	if d.rng.randf() < 0.55:
		# Pull up and get out to look.
		d.getting_out = true
		d.civil.hold_for(30.0, "paint")
	else:
		d.civil.rush(1.4, 20.0)
		d.civil._honk(0.8)


func _on_crash(jolt: float, d: TrafficDriver) -> void:
	if d.car == null or not is_instance_valid(d.car) or jolt < 4.0:
		return
	var p := d.car.global_position
	var near := false
	for u: RoadUsers.User in RoadUsers.all(get_tree()):
		if u.node != d.car and not u.person and u.pos.distance_to(Vector2(p.x, p.z)) < 8.0:
			near = true
	if near:
		# Hit by someone: brake, honk, and now and then sit there a while.
		d.civil.react_hit(d.rng.randf_range(6.0, 10.0) if d.rng.randf() < 0.3 else d.rng.randf_range(1.5, 3.0))
	crash_seen(p, d)


## A crash at p: the drivers coming up on it stop for a moment.
func crash_seen(p: Vector3, except: TrafficDriver = null) -> void:
	for o: TrafficDriver in drivers:
		if o == except or o.car == null:
			continue
		var q := o.car.global_position
		var rel := p - q
		if rel.length() > 40.0 or rel.dot(-o.car.global_basis.z) < 0.0:
			continue
		o.civil.react_crash(o.rng.randf_range(1.5, 3.5))
		if o.rng.randf() < 0.3 and rel.length() < 15.0:
			o.civil.want_reroute = true


func _watch_player_car() -> void:
	var v: Car = player.get("vehicle") if player != null else null
	if v == _watched:
		return
	if _watched != null and is_instance_valid(_watched) and _watched.crashed.is_connected(_on_player_crash):
		_watched.crashed.disconnect(_on_player_crash)
	_watched = v
	if v != null and not v.crashed.is_connected(_on_player_crash):
		v.crashed.connect(_on_player_crash)


func _on_player_crash(jolt: float) -> void:
	if jolt >= 5.0 and _watched != null:
		crash_seen(_watched.global_position)

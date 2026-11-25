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
##   * a crime by the player seen from a traffic car (TrafficWitnesses):
##     the driver brakes, honks, speeds off or gets out, and some call it in
##     a few seconds later (Wanted.witness_report), unless the player got
##     out of their sight first or painted their car.
##   * a big police chase (Wanted level 3+, sirens about: TrafficHeat):
##     some drivers ahead turn off into driveways, fewer cars come out
##     ahead of it, and people on foot scatter from paintball fire.
##   * dead in the street (stalled by paint, on its roof, its driver ran
##     off), or the player's own car stalled and left: a rollback comes for
##     it after a while (TrafficTows); the player's goes to the impound lot.
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
## Traffic drivers who saw the player's crimes (TrafficWitnesses).
var witnesses: TrafficWitnesses
## The town buses on their routes (TrafficBuses).
var buses: TrafficBuses
## How traffic takes a big chase (TrafficHeat).
var heat: TrafficHeat
## Rollbacks for cars left dead in the street (TrafficTows).
var tows: TrafficTows
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
	witnesses = TrafficWitnesses.new(self)
	buses = TrafficBuses.new(self)
	heat = TrafficHeat.new(self)
	tows = TrafficTows.new(self)
	crowd = TrafficCrowd.new()
	crowd.name = "Crowd"
	add_child(crowd)
	rng.seed = 7471
	_ground_ray.collision_mask = Layers.GROUND
	var shots := get_tree().get_first_node_in_group("paint_shots")
	if shots != null:
		shots.connect("hit", _on_paint_hit)


## Seconds since traffic started (the manager's own clock).
func clock() -> float:
	return _t


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
	witnesses.tick(delta)
	heat.tick(delta)
	tows.tick(delta)
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
		elif d.follower != null:
			_lift_follower(d)
	for x: Variant in _bystanders.duplicate():
		if not is_instance_valid(x):
			_bystanders.erase(x)
			continue
		var b := x as TrafficBystander
		if b.time_left < -2.0 and not TrafficSight.seen(get_tree(), b.global_position, focus_point()):
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
		if d.follower != null and is_instance_valid(d.follower) and d.model_index >= 0:
			list.append([d.follower, d.model_index, d.paint, d.lift])
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
	if heat.share < 1.0:
		want = roundi(want * heat.share)
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
			var p2 := Vector2(d.position().x, d.position().z)
			var dd := p2.distance_to(fp2)
			if dd > float(TrafficDensity.SPAWN_MIN) and dd + heat.ahead_score(p2, fp2) > far_d and not _seen(d, fp):
				far_d = dd + heat.ahead_score(p2, fp2)
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
	buses.tick(0.25, fp, lvl)


func _done_with(d: TrafficDriver, fp2: Vector2, lvl: int) -> bool:
	if d.state == TrafficDriver.State.GONE:
		return true
	var p := d.position()
	if p == Vector3.INF:
		return true
	var dist := Vector2(p.x, p.z).distance_to(fp2)
	if d.state == TrafficDriver.State.OUT:
		# Left in the street (its driver ran off): away once far enough.
		return d.abandoned and dist > float(TrafficDensity.DESPAWN[lvl])
	if dist > float(TrafficDensity.DESPAWN[lvl]):
		return true
	if d.truck and dist > float(TrafficDensity.PHYSICS_RADIUS[lvl]) + 40.0:
		return true # no far version: away once nobody can see it
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


## A far car is moved along at the ground's height (RoadFollower): it's
## drawn at the street's, a bridge deck or a street raised above the
## ground, wherever the street's collision is built (checked a few times
## a second).
func _lift_follower(d: TrafficDriver) -> void:
	var dt := get_physics_process_delta_time()
	d.lift = move_toward(d.lift, d.lift_target, 6.0 * dt) # up onto a deck smoothly
	d.lift_check -= dt
	if d.lift_check > 0.0:
		return
	d.lift_check = 0.3
	var rf := d.follower
	var y := surface_y(rf.global_position, d.civil.edge_at(rf.along))
	d.lift_target = 0.0 if is_nan(y) else clampf(y - rf.global_position.y, -3.0, 20.0)


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
	if heat.keep_clear(pos, fp2):
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
	# The odd truck: only ever a real vehicle near the player (it has no
	# far version), so only placed within the physics radius.
	var truck := ""
	if dist < float(TrafficDensity.PHYSICS_RADIUS[lvl]) - 15.0 and rng.randf() < TrafficPersonality.TRUCK_ODDS and _truck_count() < TrafficPersonality.TRUCKS_MAX:
		truck = TrafficPersonality.pick_truck(rng)
	var d := _new_driver(dest, truck)
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3))
	rf.set_route(r)
	rf.speed = minf(JunctionRules.limit_kmh(e) / 3.6 * 0.8, r.limit_at(0.0))
	if d.truck and not _to_car(d):
		_remove(d, fp)
		removal_log.pop_back() # never seen: it was never there
		return false
	if d.character == "chatter":
		d.chat_at = rng.randf_range(60.0, maxf(61.0, r.length - 40.0))
	spawn_log.append([_t, p3, TrafficSight.seen(get_tree(), p3, fp)])
	return true


## A bus on route `ri` at p3 heading along dir to the route's junction
## `leg` at goal (TrafficBuses). Null if it can't be placed.
func spawn_bus(p3: Vector3, dir: Vector2, ri: int, leg: int, goal: Vector2) -> TrafficDriver:
	var p := Vector2(p3.x, p3.z)
	var r := StreetRoute.plan(net, p, goal, plan_options(dir))
	if r.is_empty() or r.partial:
		return null
	var d := _new_driver({"street": goal, "inside": goal, "kind": "bus"}, TrafficBuses.MODEL)
	d.character = ""
	d.bus_route = ri
	d.bus_leg = leg
	var c := d.civil
	c.speed_factor = 0.85
	c.headway = 1.8
	c.max_accel = 0.9
	c.patience = 40.0
	c.temper = 0.15
	c.gap_time = 5.5
	c.tourist = false
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3))
	rf.set_route(r)
	rf.speed = minf(8.0, r.limit_at(0.0))
	if not _to_car(d):
		_remove(d, p3)
		removal_log.pop_back()
		return null
	spawn_log.append([_t, p3, TrafficSight.seen(get_tree(), p3, focus_point())])
	return d


## A rollback (TrafficTows) at p3 heading along dir, to pull up at `stop`.
## Null if it can't be placed.
func spawn_tow(p3: Vector3, dir: Vector2, stop: Vector3) -> TrafficDriver:
	var p := Vector2(p3.x, p3.z)
	var r := StreetRoute.plan(net, p, Vector2(stop.x, stop.z), plan_options(dir))
	if r.is_empty() or r.partial:
		return null
	var at := Vector2(stop.x, stop.z)
	var d := _new_driver({"street": at, "inside": at, "kind": "tow"}, "rollback")
	d.character = ""
	d.tow = true
	d.civil.tourist = false
	d.civil.patience = 40.0
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3))
	rf.set_route(r)
	rf.speed = minf(8.0, r.limit_at(0.0))
	if not _to_car(d):
		_remove(d, p3)
		removal_log.pop_back()
		return null
	spawn_log.append([_t, p3, TrafficSight.seen(get_tree(), p3, focus_point())])
	return d


## How traffic plans its routes: by the rules of the road, gentle corners.
static func plan_options(heading: Vector2) -> Dictionary:
	return {"obey_oneway": true, "heading": heading, "lat_accel": 3.2, "brake_accel": 2.6, "top_speed": 25.0}


func _truck_count() -> int:
	var n := 0
	for d: TrafficDriver in drivers:
		if d.truck and d.bus_route < 0 and not d.tow:
			n += 1
	return n


func _new_driver(dest: Dictionary, truck := "") -> TrafficDriver:
	var d := TrafficDriver.new()
	d.id = _next_id
	_next_id += 1
	d.rng.seed = rng.randi()
	d.model_id = truck if truck != "" else TrafficPersonality.pick_model(d.rng)
	d.truck = truck != ""
	d.model_index = -1 if d.truck else maxi(0, StreetProps.PARKED_MODELS.find(d.model_id))
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
	if d.tow and d.state == TrafficDriver.State.DRIVE and not d.turned_in:
		tows.arrived(d)
		return
	if d.bus_route >= 0 and d.car != null and d.state == TrafficDriver.State.DRIVE:
		# On to the next junction of its route.
		var goal := buses.next_stop(d)
		d.dest = {"street": goal, "inside": goal, "kind": "bus"}
		d.dest3 = Vector3(goal.x, world.terrain.h2(goal), goal.y)
		d.pilot.drive_to(d.dest3)
		return
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
	if d.tow:
		tows.truck_gone(d)
	var p := d.position()
	removal_log.append([_t, p, p != Vector3.INF and TrafficSight.seen(get_tree(), p, fp)])
	if d.car != null and is_instance_valid(d.car):
		_drop_car(d.car)
		d.car.queue_free()
	if d.follower != null and is_instance_valid(d.follower):
		d.follower.queue_free()
	if d.bystander != null and is_instance_valid(d.bystander):
		_bystanders.erase(d.bystander)
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


## The top of the street at p (on edge e): the deck on a bridge, else the
## street surface just above the ground (not a bridge passing over it).
## NAN where the street's collision isn't built.
func surface_y(p: Vector3, e: RoadNetwork.RoadEdge) -> float:
	var h := world.terrain.h2(Vector2(p.x, p.z))
	_ground_ray.from = Vector3(p.x, h + (30.0 if e != null and e.bridge else 2.5), p.z)
	_ground_ray.to = Vector3(p.x, h - 4.0, p.z)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_ray)
	if hit.is_empty() or str((hit["collider"] as Node).name) == "SafetyFloor":
		return NAN
	return (hit["position"] as Vector3).y


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
	var gy := surface_y(rf.global_position, d.civil.edge_at(rf.along))
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
	if d.truck or ap == null or ap.route == null or ap.route.is_empty() or ap.state != "route" or d.upside_down > 0.0:
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
	if d.bus_route >= 0 or d.tow:
		# A bus keeps to its route, a tow truck to its job: plan the way to
		# where it's going again, from here.
		d.pilot.drive_to(d.dest3)
		d.civil.hazard = "replan"
		return
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
	# On the curb side, by the front wheel: out of the traffic going by.
	var w := float(car.shape.get("width", 1.8))
	var at := car.global_transform * Vector3(w * 0.5 + 0.9, 0.0, -float(car.shape.get("length", 4.6)) * 0.3)
	var gy := _ground_at(at)
	if not is_nan(gy):
		at.y = gy
	b.setup(car, how, d.rng, Transform3D(car.global_basis, at))
	_bystanders.append(b)
	if how == TrafficBystander.Mode.STARE:
		d.state = TrafficDriver.State.OUT
		d.bystander = b
		d.civil.hold_for(600.0, "out", true)
		b.done.connect(_back_in.bind(d))
		b.ran_off.connect(_ran_off.bind(d))


## A traffic car's no longer its driver's (a tow's taken it on): the car
## stays, as a plain car; the driver's done.
func _release_car(d: TrafficDriver) -> void:
	var car := d.car
	if car == null:
		return
	if d.pilot != null and is_instance_valid(d.pilot):
		car.ai_controls = null
		d.pilot.queue_free()
	car.owner_id = ""
	d.pilot = null
	_car_of.erase(car)
	d.car = null
	d.state = TrafficDriver.State.GONE
	drivers.erase(d)


## Traffic drivers out on the street now.
func bystanders() -> Array[TrafficBystander]:
	var out: Array[TrafficBystander] = []
	for x: Variant in _bystanders:
		if is_instance_valid(x):
			out.append(x as TrafficBystander)
	return out


## A driver out looking at their car ran off (TrafficBystander.scatter):
## the car stays where it is, abandoned.
func _ran_off(d: TrafficDriver) -> void:
	if d.state == TrafficDriver.State.OUT:
		d.abandoned = true
		d.bystander = null
		if d.car != null and is_instance_valid(d.car):
			d.car.owner_id = ""


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
	d.pilot = null
	if not d.abandoned:
		_get_out(d, TrafficBystander.Mode.COMPLAIN)
	_car_of.erase(car)
	d.car = null
	d.state = TrafficDriver.State.GONE
	drivers.erase(d)
	thefts += 1
	witnesses.crime("take_car", car.global_position, car)
	if d.abandoned:
		return # nobody there to shout about it: only if someone saw
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null:
		wanted.call("report_crime", "take_car", car.global_position)
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", "\"Hey! That's my car!\"", "taking someone's car is a crime")


func _on_paint_hit(info: Dictionary) -> void:
	var target: Variant = info.get("target")
	if player != null and info.get("shooter") == player:
		heat.shots_at(info.get("point", player.global_position))
	# The player painting anyone or anything but the world: who saw it?
	if player != null and info.get("shooter") == player and target != null and is_instance_valid(target) and target != player and target != player.get("vehicle"):
		var kind := "paint_car" if target is Car else "paint_bystander"
		if target is Car and (target as Car).police != null:
			kind = "paint_police"
		var at: Vector3 = info.get("point", player.global_position)
		witnesses.crime(kind, at, target)
		if target is Car and _car_of.has(target):
			witnesses.scared(_car_of[target])
	if not (target is Car) or not _car_of.has(target):
		return
	var d: TrafficDriver = _car_of[target]
	if d.state != TrafficDriver.State.DRIVE or d.getting_out:
		if d.bystander != null and is_instance_valid(d.bystander):
			d.bystander.time_left += 3.0 # more to stare at
		return
	d.civil.hazard = "painted"
	if d.rng.randf() < 0.55 and not d.civil.close_behind:
		# Pull up and get out to look (not with someone right behind: they'd
		# go into the back of us).
		d.getting_out = true
		d.civil.hold_for(30.0, "paint", true)
	else:
		d.civil.rush(1.4, 20.0)
		d.civil._honk(0.8)


func _on_crash(jolt: float, d: TrafficDriver) -> void:
	if d.car == null or not is_instance_valid(d.car) or jolt < 4.0 or d.car._age < 1.0:
		return # (settling onto the street when it's made isn't a crash)
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

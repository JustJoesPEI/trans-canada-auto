class_name PedestrianManager
extends Node3D
## People walking round town (Pedestrian): a few dozen at most, round the
## player only, placed and taken away where nobody can see (TrafficSight),
## like the traffic. More downtown than out in the suburbs, by the same
## measure the traffic uses (TrafficDensity.place_share and time_share).
##
## It also does what needs more than one person, or the player:
##   * thoughts: a few at a time over the heads of people near the camera,
##     each person now and then (so the street isn't a wall of text);
##   * two people meeting on the sidewalk sometimes stop to chat;
##   * paint landing near people sends them running; a marker pointed at
##     someone puts their hands up; walking into someone, they step aside;
##   * rides (RideFares): now and then someone near the player's car waves
##     for a lift.
##
## Made by main.gd once the town is built, beside the TrafficManager. Like
## the traffic it stays idle under a headless tool (`--script`) unless
## `running` is set.

static var autostart := true

## People at once round the player (not by graphics: the same for every
## player, like the traffic).
const CAP := 24
## They're placed between these distances of the player (m), out of sight.
const SPAWN_MIN := 45.0
const SPAWN_MAX := 150.0
## Out past this they're taken away (when nobody can see them).
const DESPAWN := 190.0
## Thoughts showing at once, and how near the camera (m).
const THOUGHTS_AT_ONCE := 3
const THOUGHT_RANGE := 32.0
## Paint landing this near sends people running (m).
const SCARE_RADIUS := 14.0

var running := true
var focus := Vector3.INF
var main: Node
var world: WorldBuilder
var net: RoadNetwork
var player: Node3D
var hud: Node
var dests: TrafficDestinations
var fares: RideFares
var people: Array[Pedestrian] = []
var rng := RandomNumberGenerator.new()
## For tests: how many were placed and taken away.
var placed := 0
var removed := 0
var dodges := 0

var _balance_t := 0.0
var _social_t := 0.0
var _edges_at := Vector2.INF
var _edges: Array[RoadNetwork.RoadEdge] = []
var _weights := PackedFloat32Array()
var _wsum := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _bump_t := 0.0
## Where everyone is, by GRID squares (near()): Vector2i -> Array[Pedestrian].
var _grid := {}
var _grid_frame := -1
const GRID := 4.0


func _ready() -> void:
	name = "Pedestrians"
	running = autostart and not OS.get_cmdline_args().has("--script")
	main = get_parent()
	world = CarAutopilot.find_world(self)
	net = world.network
	player = main.get_node_or_null("Player") as Node3D
	hud = main.get_node_or_null("HUD")
	dests = TrafficDestinations.of(net, world.data)
	fares = RideFares.new(self)
	rng.seed = 5309
	_ray.collision_mask = Layers.GROUND
	var shots := get_tree().get_first_node_in_group("paint_shots")
	if shots != null:
		shots.connect("hit", _on_paint_hit)
	_warm_up()


## Builds every look's body, one a frame, so the first of each walking into
## view doesn't stop the game while it's built.
func _warm_up() -> void:
	for i in Pedestrian.LOOKS:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var m := Pedestrian.make_model(i)
		m.visible = false
		add_child(m)
		m.queue_free()


func focus_point() -> Vector3:
	if focus != Vector3.INF:
		return focus
	if player != null and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


## The ground under p (the street, the sidewalk, a deck), or near `prev`.
func ground_y(p: Vector2, prev: float) -> float:
	var top := (prev if prev > -INF else world.terrain.h2(p)) + 2.5
	_ray.from = Vector3(p.x, top, p.y)
	_ray.to = Vector3(p.x, top - 8.0, p.y)
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
	if hit.is_empty():
		return world.terrain.h2(p) + RoadNetwork.SIDEWALK_HEIGHT if prev == -INF else prev
	return (hit["position"] as Vector3).y


## The people within r of `who` (not counting them), from a grid of where
## everyone is made once a physics step.
func near(who: Pedestrian, r: float) -> Array[Pedestrian]:
	var out: Array[Pedestrian] = []
	var p := who.position2()
	if Engine.get_physics_frames() != _grid_frame:
		_make_grid()
	# (Everyone's moved a little since the grid was made: a margin.)
	var reach := r + 0.5
	var lo := Vector2i(floori((p.x - reach) / GRID), floori((p.y - reach) / GRID))
	var hi := Vector2i(floori((p.x + reach) / GRID), floori((p.y + reach) / GRID))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var cell: Variant = _grid.get(Vector2i(x, z))
			if cell == null:
				continue
			for o: Variant in cell:
				if o != who and is_instance_valid(o) and (o as Pedestrian).position2().distance_squared_to(p) < r * r:
					out.append(o as Pedestrian)
	return out


func _make_grid() -> void:
	_grid_frame = Engine.get_physics_frames()
	_grid.clear()
	for x: Variant in people:
		if not is_instance_valid(x):
			continue
		var o := x as Pedestrian
		var q := o.position2()
		var k := Vector2i(floori(q.x / GRID), floori(q.y / GRID))
		var cell: Variant = _grid.get(k)
		if cell == null:
			var list: Array[Pedestrian] = [o]
			_grid[k] = list
		else:
			(cell as Array[Pedestrian]).append(o)


## The Wanted level (0 without the autoload: headless tools), found by
## path so tools that load this before the autoloads still compile.
func wanted_level() -> int:
	var w := get_node_or_null("/root/Wanted")
	return int(w.get("level")) if w != null else 0


## Someone jumped out of a car's way (for tests and the record).
func dodged(_who: Pedestrian, _car: Node) -> void:
	dodges += 1


func _physics_process(delta: float) -> void:
	for x: Variant in people.duplicate():
		if not is_instance_valid(x):
			people.erase(x)
	var fp := focus_point()
	fares.tick(delta)
	_social(delta, fp)
	if not running:
		return
	_balance_t -= delta
	if _balance_t <= 0.0:
		_balance_t = 0.4
		_balance(fp)


func _target(fp: Vector3) -> int:
	var cap := CAP
	var p := Vector2(fp.x, fp.z)
	var share := TrafficDensity.time_share(TrafficDensity.current_hour(get_tree())) * TrafficDensity.place_share(net, p)
	if wanted_level() >= 3:
		share *= 0.5 # people keep off the streets in a big chase
	return clampi(roundi(cap * share), 0, cap)


func _balance(fp: Vector3) -> void:
	var fp2 := Vector2(fp.x, fp.z)
	var want := _target(fp)
	for p: Pedestrian in people.duplicate():
		if p.state == Pedestrian.State.RIDE or p == fares.hailer or p == fares.rider:
			continue
		var d := p.position2().distance_to(fp2)
		var done := d > DESPAWN or (p.state == Pedestrian.State.INSIDE) or p.lost()
		if not done:
			continue
		if TrafficSight.seen(get_tree(), p.global_position, fp):
			if p.state == Pedestrian.State.INSIDE and p.state_t > 20.0:
				# Seen at the door all this time: off somewhere else instead.
				p.set_goal(dests.pick(rng, p.position2(), 80.0, 500.0))
				p.resume_walking()
			continue
		_remove(p)
	# Too many: the furthest nobody can see.
	if people.size() > want:
		var far: Pedestrian = null
		var far_d := SPAWN_MIN
		for p: Pedestrian in people:
			var d := p.position2().distance_to(fp2)
			if d > far_d and not p.busy() and not TrafficSight.seen(get_tree(), p.global_position, fp):
				far_d = d
				far = p
		if far != null:
			_remove(far)
	for i in 2:
		if people.size() >= want:
			break
		for attempt in 4:
			if _try_spawn(fp):
				break


func _remove(p: Pedestrian) -> void:
	removed += 1
	people.erase(p)
	p.queue_free()


func _refresh_edges(fp2: Vector2) -> void:
	if _edges_at != Vector2.INF and _edges_at.distance_to(fp2) < 40.0:
		return
	_edges_at = fp2
	_edges.clear()
	_weights = PackedFloat32Array()
	_wsum = 0.0
	var r := SPAWN_MAX
	for e in net.edges_near(Rect2(fp2 - Vector2(r, r), Vector2(r, r) * 2.0)):
		var walk := 0.0
		for s: int in [1, -1]:
			if Pedestrian.walkable(e, s):
				walk += e.walk(s)
		if walk <= 0.0 or e.length < 12.0:
			continue
		# Busier streets (and wider sidewalks) have more people on them.
		var w := (0.4 + TrafficDensity.class_weight(e)) * walk
		_edges.append(e)
		_wsum += w * e.length
		_weights.append(_wsum)


func _try_spawn(fp: Vector3) -> bool:
	var fp2 := Vector2(fp.x, fp.z)
	_refresh_edges(fp2)
	if _edges.is_empty():
		return false
	var e: RoadNetwork.RoadEdge = _edges[mini(_weights.bsearch(rng.randf() * _wsum), _edges.size() - 1)]
	var side := 1 if rng.randf() < 0.5 else -1
	if not Pedestrian.walkable(e, side):
		side = -side
	var along := rng.randf_range(4.0, e.length - 4.0)
	var pos := _walk_point(e, along, side)
	var dist := pos.distance_to(fp2)
	if dist < SPAWN_MIN or dist > SPAWN_MAX:
		return false
	var p3 := Vector3(pos.x, world.terrain.h2(pos) + 1.0, pos.y)
	if TrafficSight.seen(get_tree(), p3, fp):
		return false
	for o: Pedestrian in people:
		if o.position2().distance_squared_to(pos) < 9.0:
			return false
	var p := Pedestrian.new()
	p.name = "Pedestrian_%d" % placed
	add_child(p)
	p.setup(self, rng.randi())
	p.start(e, along, side, rng.randf() < 0.5, dests.pick(rng, pos, 60.0, 600.0))
	people.append(p)
	placed += 1
	return true


func _walk_point(e: RoadNetwork.RoadEdge, along: float, side: int) -> Vector2:
	var s: Array = RoadNetwork.sample(e.points, along)
	return (s[0] as Vector2) + RoadNetwork._perp(s[1]) * float(side) * net.offset_for(e, RoadNetwork.Level.WALK, side)


# --- what needs more than one ------------------------------------------------------------------

func _social(delta: float, fp: Vector3) -> void:
	for p: Pedestrian in people:
		p.think_wait -= delta
	_bump_t -= delta
	if player != null and is_instance_valid(player) and player.get("vehicle") == null and _bump_t <= 0.0:
		_bump_t = 0.2
		var pp := Vector2(player.global_position.x, player.global_position.z)
		for p: Pedestrian in people:
			if p.position2().distance_squared_to(pp) < 0.8:
				p.bumped(pp)
		# A marker pointed at someone.
		if bool(player.get("aiming")) and float(player.get("aim_amount")) > 0.5:
			var at: Vector3 = player.get("aim_point")
			for p: Pedestrian in people:
				var c := p.global_position + Vector3.UP * 1.0
				if c.distance_to(at) < 1.6 and c.distance_to(player.global_position) < 35.0:
					p.aimed_at()
	_social_t -= delta
	if _social_t > 0.0:
		return
	_social_t = 0.5
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else fp
	# Thoughts: a few at a time, near the camera.
	var showing := 0
	var ready: Array[Pedestrian] = []
	for p: Pedestrian in people:
		if p.global_position.distance_to(eye) > THOUGHT_RANGE:
			continue
		if p.saying:
			showing += 1
		elif p.think_wait <= 0.0 and p.state in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.WAIT_CROSS]:
			ready.append(p)
	if showing < THOUGHTS_AT_ONCE and not ready.is_empty() and rng.randf() < 0.6:
		var p: Pedestrian = ready[rng.randi() % ready.size()]
		var line := PedestrianLines.thought(p.rng, p.kind)
		if wanted_level() >= 2 and rng.randf() < 0.5:
			line = PedestrianLines.pick(p.rng, PedestrianLines.SIRENS)
		p.think(line)
		p.think_wait = rng.randf_range(18.0, 40.0)
	# Two people meeting stop for a chat now and then.
	for a: Pedestrian in people:
		if a.state != Pedestrian.State.WALK or a.chat_wait > 0.0 or a.kind == "jogger" or a.in_road():
			continue
		for b: Pedestrian in near(a, 2.2):
			if b.state != Pedestrian.State.WALK or b.chat_wait > 0.0 or b.kind == "jogger" or b.in_road():
				continue
			if a._heading.dot(b._heading) > -0.3:
				continue
			a.chat_wait = rng.randf_range(30.0, 80.0)
			b.chat_wait = rng.randf_range(30.0, 80.0)
			if rng.randf() < 0.45:
				var lines: Array = PedestrianLines.chat(rng)
				a.chat_with(b, true, lines)
				b.chat_with(a, false, lines)
			break


func _on_paint_hit(info: Dictionary) -> void:
	var at: Vector3 = info.get("point", Vector3.INF)
	if at == Vector3.INF:
		return
	for p: Pedestrian in people.duplicate():
		if p == info.get("target"):
			continue # they said so themselves (take_paint_hit)
		if p.global_position.distance_to(at) < SCARE_RADIUS and p.state != Pedestrian.State.RIDE:
			p.flee(at)

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
##     for a lift;
##   * the buses (TrafficBuses, TransitStops): some people are off to a bus
##     stop (more of them at the rush hours), some are already waiting at
##     one, and they get on when it pulls in on their side; others get
##     off. The bus asks how many are waiting (TrafficBuses.waiting_hook)
##     and stops only if someone is, or someone wants off;
##   * twos: now and then two are placed walking together, one beside the
##     other, and say the odd thing to each other;
##   * things happening in the street (StreetEvents): people near one
##     notice it once, slow down to look or stop and watch, and now and
##     then one of them says something;
##   * witnesses: people who saw the player paint someone remember them a
##     while, and up close say so and back off; now and then one calls it
##     in (Wanted.witness_report), saying so on the phone first;
##   * down: someone hit by the player's car or painted out (Pedestrian
##     DOWN) is reported (`casualty_down`, `struck_by_player`) for the
##     Island Boo-Boo Bus (EmergencyServices), and everyone near a car hit
##     runs for a doorway. No more than DOWN_MAX lie hurt at once (past
##     that a car only knocks people onto their backsides) and no more
##     than PAINTED_MAX wear paint (each one a pass more to draw).
##
## All of it twice a second, over the couple of dozen people there are: no
## searching the world, and nothing new to draw.
##
## Made by main.gd once the town is built, beside the TrafficManager. Like
## the traffic it stays idle under a headless tool (`--script`) unless
## `running` is set.

static var autostart := true

## Someone's down and hurt (struck by the player's car, or painted out).
signal casualty_down(p: Pedestrian)
## The player's car hit someone: "bump" (knocked over) or "struck".
signal struck_by_player(p: Pedestrian, car: Car, kind: String)

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
## Share of the people placed who are off to a bus stop within BUS_REACH
## (and of those, how many are placed already waiting there), by kind.
const BUS_ODDS := {"commuter": 0.5, "teen": 0.35, "senior": 0.3, "stroller": 0.12, "tourist": 0.1, "jogger": 0.0}
const BUS_REACH := 320.0
const WAITING_SHARE := 0.6
## At most this many waiting at one stop, one side.
const WAITING_MAX := 4
## Share of people placed walking with someone, by kind.
const PAIR_ODDS := {"stroller": 0.12, "tourist": 0.3, "senior": 0.15, "teen": 0.15, "commuter": 0.03, "jogger": 0.0}
## People notice things in the street this near the camera (m), and one
## in this many says something.
const NOTICE_RANGE := 45.0
const NOTICE_SAY := 0.3
## Saw the player paint someone within this (m), and remember it this long
## (s); up close (m) they react. Share of crimes one of them calls in.
const WITNESS_RANGE := 35.0
const WITNESS_MEMORY := 120.0
const RECOGNISE_RANGE := 6.0
const CALL_ODDS := 0.35
## Lying hurt at once, at most; people with paint on them, at most.
const DOWN_MAX := 8
const PAINTED_MAX := 10
## Everyone this near a car hitting someone runs (m).
const SCATTER_RADIUS := 32.0

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
var boarded := 0
var got_off := 0
var pairs := 0
var noticed := 0
var witnessed := 0
var calls_made := 0

var _balance_t := 0.0
var _social_t := 0.0
var _edges_at := Vector2.INF
var _edges: Array[RoadNetwork.RoadEdge] = []
var _weights := PackedFloat32Array()
var _wsum := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _bump_t := 0.0
var _pair_chat_t := 20.0
## Calls being made: [person, due (s), where].
var _calls: Array = []
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
	TrafficBuses.waiting_hook = waiting_at
	TrafficBuses.arrived_hook = bus_arrived
	TrafficBuses.boarding_hook = boarding
	var traffic := main.get_node_or_null("Traffic")
	if traffic != null and traffic.has_signal("crime_seen"):
		traffic.connect("crime_seen", _on_crime)
	var wanted := get_node_or_null("/root/Wanted")
	if wanted != null and wanted.has_signal("arrested"):
		wanted.connect("arrested", func(_r: Dictionary) -> void:
			if player != null and is_instance_valid(player):
				StreetEvents.post("arrest", player.global_position, 40.0, 40.0))
	_warm_up()


func _exit_tree() -> void:
	if TrafficBuses.waiting_hook == Callable(self, "waiting_at"):
		TrafficBuses.waiting_hook = Callable()
		TrafficBuses.arrived_hook = Callable()
		TrafficBuses.boarding_hook = Callable()


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


## The car the player's driving, or null.
func player_car() -> Car:
	if player == null or not is_instance_valid(player):
		return null
	return player.get("vehicle") as Car


## Room for one more lying hurt.
func casualty_room() -> bool:
	var n := 0
	for p: Pedestrian in people:
		if is_instance_valid(p) and p.state == Pedestrian.State.DOWN and p.down_kind != "bump":
			n += 1
	return n < DOWN_MAX


## Room for one more person with paint on them.
func paint_room() -> bool:
	var n := 0
	for p: Pedestrian in people:
		if is_instance_valid(p) and p.body_paint != null:
			n += 1
	return n < PAINTED_MAX


## Within `r` of the camera (for lines nobody would be near enough to read).
func near_camera(at: Vector3, r: float) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.global_position.distance_to(at) < r


## Painted out: down (Pedestrian.take_paint_hit).
func went_down(p: Pedestrian) -> void:
	casualty_down.emit(p)


## The player's car hit `p` (Pedestrian._struck_by): everyone near runs,
## a couple of them shouting, and it's reported.
func struck(p: Pedestrian, car: Car, kind: String) -> void:
	var at := p.global_position
	StreetEvents.post("struck", at, 30.0, 35.0)
	var shouts := 0
	for q: Pedestrian in people:
		if q == p or not is_instance_valid(q) or q.state in [Pedestrian.State.DOWN, Pedestrian.State.RIDE, Pedestrian.State.INSIDE] or q.on_bus:
			continue
		if q.global_position.distance_to(at) > SCATTER_RADIUS:
			continue
		q.flee(car.global_position, false)
		if shouts < 2 and rng.randf() < 0.5:
			shouts += 1
			q.say(PedestrianLines.pick(q.rng, EmergencyLines.SCATTER), 2.6)
	struck_by_player.emit(p, car, kind)
	if kind != "bump":
		casualty_down.emit(p)


## Someone jumped out of a car's way (for tests and the record).
func dodged(_who: Pedestrian, _car: Node) -> void:
	dodges += 1


func _physics_process(delta: float) -> void:
	if TickProfile.on:
		var u := Time.get_ticks_usec()
		_timed_physics_process(delta)
		TickProfile.add(&"people on foot", Time.get_ticks_usec() - u)
	else:
		_timed_physics_process(delta)


func _timed_physics_process(delta: float) -> void:
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
		if p.on_bus:
			boarded += 1
			_remove(p) # inside the bus, out of sight
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
	if rng.randf() < 0.25 and _try_spawn_waiting(fp):
		return true
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
	var p := _new_person()
	var place := dests.pick(rng, pos, 60.0, 600.0)
	if rng.randf() < float(BUS_ODDS.get(p.kind, 0.0)) * _bus_hour():
		var stop := _stop_for(pos, p)
		if not stop.is_empty():
			place = stop
	p.start(e, along, side, rng.randf() < 0.5, place)
	if p.bus_stop < 0 and rng.randf() < float(PAIR_ODDS.get(p.kind, 0.0)):
		var c := _new_person(p.kind if rng.randf() < 0.6 else "")
		c.goal = p.goal
		c.follow(p)
		pairs += 1
	return true


func _new_person(kind := "") -> Pedestrian:
	var p := Pedestrian.new()
	p.name = "Pedestrian_%d" % placed
	add_child(p)
	p.setup(self, rng.randi())
	if kind != "" and kind != p.kind:
		p.kind = kind
		var sp: Array = Pedestrian.SPEEDS[kind]
		p.walk_speed = p.rng.randf_range(float(sp[0]), float(sp[1]))
	people.append(p)
	placed += 1
	return p


## More people catch the bus at the rush hours.
func _bus_hour() -> float:
	var h := TrafficDensity.current_hour(get_tree())
	if (h >= 7.0 and h < 9.5) or (h >= 15.5 and h < 18.5):
		return 1.6
	return 0.4 if h < 6.0 or h >= 22.0 else 1.0


## A bus stop near `from` for p to walk to (its place), or empty.
func _stop_for(from: Vector2, p: Pedestrian) -> Dictionary:
	var ts := TransitStops.current
	if ts == null or ts.net != net:
		return {}
	var near := ts.near(from, BUS_REACH)
	if near.is_empty():
		return {}
	var si: int = near[rng.randi() % near.size()]
	var sides: Array = ts.stops[si]["sides"]
	if sides.is_empty():
		return {}
	var side: int = sides[rng.randi() % sides.size()]
	var slot := _waiting_slot(si, side)
	if slot < 0:
		return {}
	return p.bus_place(si, side, slot_point(si, side, slot))


## Someone placed already waiting at a stop (out of sight).
func _try_spawn_waiting(fp: Vector3) -> bool:
	var ts := TransitStops.current
	if ts == null or ts.net != net:
		return false
	var fp2 := Vector2(fp.x, fp.z)
	var near := ts.near(fp2, SPAWN_MAX)
	if near.is_empty():
		return false
	var si: int = near[rng.randi() % near.size()]
	var sides: Array = ts.stops[si]["sides"]
	if sides.is_empty():
		return false
	var side: int = sides[rng.randi() % sides.size()]
	var slot := _waiting_slot(si, side)
	if slot < 0 or rng.randf() > WAITING_SHARE * _bus_hour():
		return false
	var at := slot_point(si, side, slot)
	if at.distance_to(fp2) < SPAWN_MIN:
		return false
	if TrafficSight.seen(get_tree(), Vector3(at.x, world.terrain.h2(at) + 1.0, at.y), fp):
		return false
	var p := _new_person()
	if p.kind == "jogger":
		p.kind = "commuter"
	p.start_waiting(si, side, at)
	return true


## The next free spot at stop si on `side` (-1 if it's full).
func _waiting_slot(si: int, side: int) -> int:
	var n := 0
	for p: Pedestrian in people:
		if p.bus_stop == si and p.bus_side == side:
			n += 1
	return n if n < WAITING_MAX else -1


## Where the slot-th person waits at a stop: along the curb from the sign,
## each a little further on, either way.
func slot_point(si: int, side: int, slot: int) -> Vector2:
	var st: Dictionary = TransitStops.current.stops[si]
	var w: Vector2 = st["wait"][side]
	var k := (slot + 1) / 2
	var sgn := 1.0 if slot % 2 == 1 else -1.0
	return w + (st["dir"] as Vector2) * (0.95 * k * sgn) + RoadNetwork._perp(st["dir"]) * float(side) * rng.randf_range(-0.2, 0.25)


## How many are waiting at stop si on `side` (TrafficBuses asks).
func waiting_at(si: int, side: int) -> int:
	var n := 0
	for p: Pedestrian in people:
		if p.waiting_for_bus(si, side):
			n += 1
	return n


## A bus has pulled in at stop si on `side`: those waiting get on, `off`
## get off. How many get on.
func bus_arrived(si: int, side: int, bus: Node3D, off: int) -> int:
	var on := 0
	for p: Pedestrian in people:
		if p.waiting_for_bus(si, side):
			p.board_bus(bus)
			on += 1
	for i in off:
		get_tree().create_timer(1.0 + i * 1.3, false, true).timeout.connect(_off_bus.bind(bus))
	return on


## How many are walking up to `bus`'s door (TrafficBuses asks before it
## pulls out).
func boarding(bus: Node3D) -> int:
	var n := 0
	for p: Pedestrian in people:
		if p.state == Pedestrian.State.TO_BUS and p._bus == bus:
			n += 1
	return n


## Someone getting off the bus at its door, off somewhere on foot.
func _off_bus(bus: Node3D) -> void:
	if bus == null or not is_instance_valid(bus) or absf(float(bus.get("speed"))) > 0.5:
		return
	var door := TrafficBuses.door(bus)
	var d2 := Vector2(door.x, door.z)
	var hit := net.nearest_on_streets(d2, 25.0)
	if hit.is_empty():
		return
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var side := 1 if (d2 - (hit["pos"] as Vector2)).dot(RoadNetwork._perp(hit["dir"])) >= 0.0 else -1
	if not Pedestrian.walkable(e, side):
		return
	var p := _new_person()
	got_off += 1
	p.start(e, float(hit["along"]), side, rng.randf() < 0.5, dests.pick(rng, d2, 60.0, 500.0))
	p._pos = d2 # from the door, onto the sidewalk
	p._place_node()
	p.reset_physics_interpolation()


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
		if a.state != Pedestrian.State.WALK or a.chat_wait > 0.0 or a.kind == "jogger" or a.in_road() or a.leader != null or a.companion != null:
			continue
		for b: Pedestrian in near(a, 2.2):
			if b.state != Pedestrian.State.WALK or b.chat_wait > 0.0 or b.kind == "jogger" or b.in_road() or b.leader != null or b.companion != null:
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
	_pairs(eye)
	_notice(eye)
	_witnesses(eye)


## Two walking together say something to each other, once in a while.
func _pairs(eye: Vector3) -> void:
	_pair_chat_t -= 0.5
	if _pair_chat_t > 0.0:
		return
	for b: Pedestrian in people:
		var a := b.leader
		if a == null or not is_instance_valid(a) or a.saying or b.saying or a.state != Pedestrian.State.WALK:
			continue
		if a.global_position.distance_to(eye) > THOUGHT_RANGE:
			continue
		_pair_chat_t = rng.randf_range(25.0, 50.0)
		var lines := PedestrianLines.pick_pair(rng, PedestrianLines.PAIR_CHATS)
		a.say(str(lines[0]), 2.8)
		get_tree().create_timer(2.4, false, true).timeout.connect(func() -> void:
			if is_instance_valid(b):
				b.say(str(lines[1]), 2.8))
		return
	_pair_chat_t = 5.0


## Things happening in the street (StreetEvents): who's near enough to
## notice, each once. Out of the camera's range nobody bothers (nobody'd
## see them do it).
func _notice(eye: Vector3) -> void:
	var events := StreetEvents.active()
	if events.is_empty():
		return
	for ev: Dictionary in events:
		var at: Vector2 = ev["pos"]
		if Vector3(at.x, float(ev["y"]), at.y).distance_to(eye) > NOTICE_RANGE + float(ev["radius"]):
			continue
		var spoken := bool(ev.get("spoken", false))
		for p: Pedestrian in people:
			if p.noticed.has(ev["id"]) or p.leader != null or p.busy() or p.saying:
				continue
			if p.state not in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.WAIT_BUS, Pedestrian.State.WAIT_CROSS]:
				continue
			if p.position2().distance_to(at) > float(ev["radius"]):
				continue
			var line := ""
			if not spoken and rng.randf() < NOTICE_SAY:
				spoken = true
				ev["spoken"] = true
				line = PedestrianLines.pick(rng, PedestrianLines.NOTICE.get(ev["kind"], PedestrianLines.NOTICE["crash"]))
			p.notice(ev, line)
			noticed += 1


## The player painted someone (or took a car) at `at` (TrafficManager):
## the people who could see it remember, and turn to look.
func _on_crime(_kind: String, at: Vector3) -> void:
	var now := _now()
	var caller: Pedestrian = null
	for p: Pedestrian in people:
		if p.busy() or p.on_bus or p.global_position.distance_to(at) > WITNESS_RANGE:
			continue
		var eye := p.global_position + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(eye, at + Vector3.UP * 0.8, Layers.SOLID)
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		p.saw_crime_at = now
		p.recognised = false
		witnessed += 1
		if p.state in [Pedestrian.State.WALK, Pedestrian.State.PAUSE, Pedestrian.State.WAIT_BUS] and p.leader == null:
			p.watch(Vector2(at.x, at.z), rng.randf_range(2.5, 5.0))
		if caller == null and p.kind != "teen" and p.leader == null:
			caller = p
	if caller != null and rng.randf() < CALL_ODDS:
		_calls.append([caller, now + rng.randf_range(10.0, 22.0), at])


## Witnesses: up close to the player again, they say so and back off; a
## call being made goes through.
func _witnesses(_eye: Vector3) -> void:
	var now := _now()
	for c: Array in _calls.duplicate():
		var p: Pedestrian = c[0]
		if not is_instance_valid(p) or p.state == Pedestrian.State.FLEE:
			_calls.erase(c)
			continue
		if float(c[1]) - now < 4.0 and not p.saying and p._phone_t <= 0.0:
			p.on_phone(4.5)
			p.say(PedestrianLines.pick(p.rng, PedestrianLines.CALLING), 3.5)
		if now >= float(c[1]):
			_calls.erase(c)
			calls_made += 1
			var w := get_node_or_null("/root/Wanted")
			if w != null and w.has_method("witness_report"):
				w.call("witness_report", c[2])
	if player == null or not is_instance_valid(player) or player.get("vehicle") != null:
		return
	var pp := player.global_position
	for p: Pedestrian in people:
		if p.recognised or now - p.saw_crime_at > WITNESS_MEMORY or p.busy():
			continue
		if p.global_position.distance_to(pp) > RECOGNISE_RANGE:
			continue
		p.recognised = true
		p.say(PedestrianLines.pick(p.rng, PedestrianLines.RECOGNISE), 2.6)
		p.bumped(Vector2(pp.x, pp.z)) # a step away
		p.watch(Vector2(pp.x, pp.z), rng.randf_range(1.5, 3.0))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _on_paint_hit(info: Dictionary) -> void:
	var at: Vector3 = info.get("point", Vector3.INF)
	if at == Vector3.INF:
		return
	for p: Pedestrian in people.duplicate():
		if p == info.get("target"):
			continue # they said so themselves (take_paint_hit)
		if p.global_position.distance_to(at) < SCARE_RADIUS and p.state != Pedestrian.State.RIDE:
			p.flee(at)

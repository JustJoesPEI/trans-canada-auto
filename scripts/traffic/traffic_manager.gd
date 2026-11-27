class_name TrafficManager
extends Node3D
## Town traffic (design.md section 7½): ordinary cars driving round
## Charlatown to real places, placed and taken away out of every player's
## sight, as many as the time of day and the place call for
## (TrafficDensity), making room for the police.
##
## It serves any number of players (`viewers`): the local one, and `others`
## (on a server, every player; in tools, simulated ones). Traffic is
## counted by area (TrafficDensity.cell_targets), so players near each
## other share the same cars.
##
## Each car is a TrafficDriver: a real Car with a CarAutopilot and civil
## driving (CivilDriving) near a player (each player's nearest few,
## shared with players nearby: TrafficDensity.physics_cap and
## physics_radius), a RoadFollower further off (no physics, drawn by
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
## Whether there's a player on this machine (off on a dedicated server, or
## in a tool simulating players: then only `others` count).
var local_viewer := true
## The other players traffic is for (their positions, set each step by
## whatever knows them: the server, or a tool).
var others := PackedVector3Array()

## s for the owner of a taken car to get through to the police.
const OWNER_CALL := Vector2(4.0, 7.0)

## A crime by the player at `at` (kind as Wanted.report_crime), for the
## people on foot who saw it (PedestrianManager).
signal crime_seen(kind: String, at: Vector3)

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
var _look_t := 0.0
## The town buses on their routes (TrafficBuses).
var buses: TrafficBuses
## How traffic takes a big chase (TrafficHeat).
var heat: TrafficHeat
## Rollbacks for cars left dead in the street (TrafficTows).
var tows: TrafficTows
var rng := RandomNumberGenerator.new()

## For tests and debugging: every placing and taking away ([time, where,
## seen by a player]), and the most there have been at once. Only kept
## under a tool (`--script`): in the game they'd grow for as long as it runs.
var spawn_log: Array = []
var removal_log: Array = []
var keep_logs := OS.get_cmdline_args().has("--script")
var most := 0
## How many the areas round the players want, as of the last check.
var wanted := 0.0
var thefts := 0

var _t := 0.0
var _steps := 0
## Far cars (past the physics radius) plan their speed every this many
## physics steps (10 times a second at 60), staggered: with a lot of
## traffic about, planning every car every step was most of its cost.
const FAR_TICK_EVERY := 6
## And they look round for the cars about them this often (s), keeping
## track of the one ahead in between.
const FAR_SCAN_EVERY := 0.3
## On a server, the far cars further than this from every player (m) plan
## half as often again and move every other step, two steps at a time
## (30 times a second: three times as often as a player that far off
## hears of them, design.md section 1). There are hundreds.
const SERVER_SLOW_FAR := 160.0
## How far past the physics radius a server keeps a car's physics (m).
const SERVER_KEEP := 20.0
var _balance_t := 0.0
## Streets to place cars on, by area square: Vector2i -> [edges, cumulative
## weights, total].
var _cell_edges := {}
## The viewers on the ground, and by VIEW_BUCKET squares (for "nearest").
var _v2 := PackedVector2Array()
var _vbuckets := {}
var _vbucket_idx := {} ## the same squares -> the players' indices in _v2
const VIEW_BUCKET := 460.0
var _car_of := {} ## Car -> TrafficDriver
var _next_id := 1
var _watched: Car = null
var _ground_ray := PhysicsRayQueryParameters3D.new()
var _bystanders: Array[TrafficBystander] = []
var _bystander_t := 0.0
## Counts the checks (_balance), for the drivers' seen_now.
var _check_n := 0
## The far followers waiting to be moved this step (_flush_followers), and
## their drivers.
var _batch: Array[TrafficDriver] = []
var _batch_rf: Array = []
var _slow_batch: Array[TrafficDriver] = []
var _slow_batch_rf: Array = []
## The native mover (TcaFollowers), or null (`-- --no-native`, or no library).
static var native_followers := ClassDB.class_exists("TcaFollowers") and not OS.get_cmdline_user_args().has("--no-native")
var _fnat: Object = ClassDB.instantiate("TcaFollowers") if native_followers else null
## A server's placing still to do from the last check (one a step): how
## many more, where, and up to how many in all.
var _spawns_left := 0
var _spawn_short: Array[Vector2i] = []
var _spawn_cum := PackedFloat32Array()
var _spawn_sum := 0.0
var _spawn_want := 0
## Drivers made since their distances to the players were last worked out.
var _unmeasured: Array[TrafficDriver] = []
## Whether the last _try_spawn got as far as planning a route.
var _planned := false


func _ready() -> void:
	name = "Traffic"
	process_physics_priority = -2 # before the autopilots (it moves its own followers)
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
	_warm_up()


## Builds every traffic look's meshes (and the bus's), one a frame, as the
## game starts (on the title screen), so a model's first car coming near
## doesn't stop the game for a moment while it's built (60-80 ms each, and
## there are some fifty looks).
func _warm_up() -> void:
	# The police too (one mesh per force: the unit numbers are labels), so
	# the first cruiser in a chase isn't built mid-chase.
	for force: String in PoliceUnit.MODELS:
		var pm: Array = PoliceUnit.MODELS[force]
		var pp := Color.from_string(str(CarModels.LIVERIES[pm[1]]["colour"]), Color.WHITE)
		if not Car.is_warm(pm[0], pp, pm[1]):
			await get_tree().process_frame
			if not is_inside_tree():
				return
			Car.warm_meshes(pm[0], pp, pm[1])
	# The cars, and the bus (on its routes downtown it's out near the
	# player in most games, and a first bus built in traffic was a 75 ms
	# stop).
	var ids: Array[String] = []
	for m: Array in TrafficPersonality.MODELS:
		ids.append(str(m[0]))
	ids.append(TrafficBuses.MODEL)
	for id: String in ids:
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


## Seconds since traffic started (the manager's own clock).
func clock() -> float:
	return _t


## Every player traffic is for, on this machine and others.
func viewers() -> PackedVector3Array:
	var out := PackedVector3Array()
	if local_viewer:
		out.append(focus_point())
	out.append_array(others)
	return out


## The local player (INF on a server), for what only they can see (the
## camera) or do (a chase, crimes).
func local_point() -> Vector3:
	return focus_point() if local_viewer else Vector3.INF


## The player: the local one, or on a server the first of the others (for
## what's still tied to one player: buses, tows, a big chase).
func focus_point() -> Vector3:
	if not local_viewer:
		return others[0] if not others.is_empty() else Vector3.ZERO
	if focus != Vector3.INF:
		return focus
	if player != null and is_instance_valid(player):
		return player.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


func _physics_process(delta: float) -> void:
	var prof := TickProfile.on
	var u0 := Time.get_ticks_usec() if prof else 0
	TrafficSignal.advance(delta)
	_t += delta
	_watch_player_car()
	_rubberneck(delta)
	witnesses.tick(delta)
	heat.tick(delta)
	tows.tick(delta)
	_steps += 1
	var u_near := 0
	var u_far := 0
	var u_fol := 0
	var u1 := 0
	if prof:
		u1 = Time.get_ticks_usec()
		TickProfile.add(&"traffic: lights, witnesses, heat, tows", u1 - u0)
	# The far followers are moved in batches (_flush_followers), natively
	# where the library's loaded, each batch just before the next driver
	# who looks round (a tick) or anything else that might see them, so
	# everything happens in the same order as moving each in its turn.
	var far_off := TrafficDensity.physics_radius() + 20.0
	var slow_off := SERVER_SLOW_FAR if TrafficDensity.server else INF
	for d: TrafficDriver in drivers.duplicate():
		if d.car != null and not is_instance_valid(d.car):
			_flush_followers(delta)
			_forget(d)
			continue
		if d.car != null and d.car.driver != null:
			_flush_followers(delta)
			_taken(d)
			continue
		if d.car == null and d.follower != null and d.near_dist > far_off:
			# Far off: it plans its speed every few steps, not each one
			# (staggered so they don't all go in the same step).
			d.saved_dt += delta
			var slow := d.near_dist > slow_off
			if (_steps + d.id) % (FAR_TICK_EVERY * 2 if slow else FAR_TICK_EVERY) != 0:
				_queue_follower(d, slow)
				continue
			if prof:
				var a := Time.get_ticks_usec()
				_flush_followers(delta)
				u_fol += Time.get_ticks_usec() - a
			else:
				_flush_followers(delta)
			var b := Time.get_ticks_usec() if prof else 0
			d.civil.scan_every = FAR_SCAN_EVERY
			d.tick(d.saved_dt)
			d.saved_dt = 0.0
			if prof:
				u_far += Time.get_ticks_usec() - b
		else:
			if prof:
				var a2 := Time.get_ticks_usec()
				_flush_followers(delta)
				u_fol += Time.get_ticks_usec() - a2
			else:
				_flush_followers(delta)
			var c := Time.get_ticks_usec() if prof else 0
			d.civil.scan_every = CivilDriving.SCAN_EVERY
			d.tick(delta + d.saved_dt)
			d.saved_dt = 0.0
			if prof:
				u_near += Time.get_ticks_usec() - c
		if d.car != null:
			_car_events(d)
		elif d.follower != null:
			_queue_follower(d, d.near_dist > slow_off)
	if prof:
		var a3 := Time.get_ticks_usec()
		_flush_followers(delta)
		u_fol += Time.get_ticks_usec() - a3
	else:
		_flush_followers(delta)
	var u2 := 0
	if prof:
		u2 = Time.get_ticks_usec()
		TickProfile.add(&"traffic: near drivers' civil ticks", u_near)
		TickProfile.add(&"traffic: far drivers' civil ticks", u_far)
		TickProfile.add(&"traffic: followers moved", u_fol)
		TickProfile.add(&"traffic: driver loop, the rest", u2 - u1 - u_near - u_far - u_fol)
	_bystander_t -= delta
	if _bystander_t <= 0.0:
		_bystander_t = 0.25
		_tidy_bystanders()
	if prof:
		TickProfile.add(&"traffic: bystanders", Time.get_ticks_usec() - u2)
	if not running:
		return
	_balance_t -= delta
	if _balance_t <= 0.0:
		_balance_t = 0.25
		_balance()
	elif _spawns_left > 0:
		var u3 := Time.get_ticks_usec() if prof else 0
		_spawns_left -= 1
		if not _spawn_one(_spawn_short, _spawn_cum, _spawn_sum, _spawn_want):
			_spawns_left = 0
		if prof:
			TickProfile.add(&"balance: placing", Time.get_ticks_usec() - u3)
	most = maxi(most, drivers.size())


## Drivers out on the street who've done staring: taken away once nobody
## can see them (a few times a second: it's a sight line each).
func _tidy_bystanders() -> void:
	var i := _bystanders.size() - 1
	while i >= 0:
		var x: Variant = _bystanders[i]
		if not is_instance_valid(x):
			_bystanders.remove_at(i)
		else:
			var b := x as TrafficBystander
			if b.time_left < -2.0 and not _seen_at(b.global_position):
				_bystanders.remove_at(i)
				b.queue_free()
		i -= 1


func _process(_delta: float) -> void:
	crowd.show_drivers(drivers)


# --- how many, and where ----------------------------------------------------------

func _balance() -> void:
	_check_n += 1
	_balance_check()
	_check_n += 1 # (seen_now is only for within the one check)


func _balance_check() -> void:
	var prof := TickProfile.on
	var u0 := Time.get_ticks_usec() if prof else 0
	var fp := focus_point()
	var fp2 := Vector2(fp.x, fp.z)
	_update_nearness()
	var police := _police_driving()
	var targets := TrafficDensity.cell_targets(net, _v2, get_tree(), police, heat.share)
	var u1 := 0
	if prof:
		u1 = Time.get_ticks_usec()
		TickProfile.add(&"balance: nearness, targets", u1 - u0)
	var want := 0.0
	for c: Vector2i in targets:
		want += float(targets[c])
	wanted = want
	# Take away the ones done with, too far off or hopelessly stuck, where
	# nobody can see.
	for d: TrafficDriver in drivers.duplicate():
		if _done_with(d) and not _seen(d):
			_remove(d)
	# How many in each square now.
	var counts := {}
	var cell_of := {} # driver -> its square, as of this check
	for d: TrafficDriver in drivers:
		var c := _cell_of(d)
		cell_of[d] = c
		counts[c] = int(counts.get(c, 0)) + 1
	var many := 1 + _v2.size() / 6 # more players, more at a time
	# Too many: from the squares furthest over what they want, the one
	# furthest from the players that nobody can see. Each time it's the
	# best of those (the furthest, the first of equals), so they're taken
	# in that order, from a list sorted once: a square's count only goes
	# down as they go, so one passed over is never wanted later.
	if drivers.size() > roundi(want):
		var order: Array = [] # [score, index, driver]
		for k in drivers.size():
			var d := drivers[k]
			var dc: Vector2i = cell_of[d]
			if float(counts.get(dc, 0)) <= float(targets.get(dc, 0.0)) + 0.5 and d.near_dist < TrafficDensity.DESPAWN:
				continue # (and never will be, this check)
			if d.near_dist < TrafficDensity.SPAWN_MIN:
				continue
			var p := d.position()
			order.append([d.near_dist + heat.ahead_score(Vector2(p.x, p.z), fp2), k, d])
		order.sort_custom(func(x: Array, y: Array) -> bool:
			return float(x[0]) > float(y[0]) or (float(x[0]) == float(y[0]) and int(x[1]) < int(y[1])))
		var next := 0
		for i in many:
			if drivers.size() <= roundi(want):
				break
			var far: TrafficDriver = null
			while next < order.size():
				var d: TrafficDriver = order[next][2]
				next += 1
				var c: Vector2i = cell_of[d]
				if float(counts.get(c, 0)) <= float(targets.get(c, 0.0)) + 0.5 and d.near_dist < TrafficDensity.DESPAWN:
					continue
				if not _seen(d):
					far = d
					break
			if far == null:
				break
			var fc: Vector2i = cell_of[far]
			counts[fc] = int(counts.get(fc, 0)) - 1
			_remove(far)
	var u2 := 0
	if prof:
		u2 = Time.get_ticks_usec()
		TickProfile.add(&"balance: taking away", u2 - u1)
	# Too few: a couple more (more with more players), out of sight, in the
	# squares furthest under what they want.
	var short: Array[Vector2i] = []
	var cum := PackedFloat32Array()
	var sum := 0.0
	for c: Vector2i in targets:
		var lack := float(targets[c]) - float(counts.get(c, 0))
		if lack > 0.0:
			sum += lack
			short.append(c)
			cum.append(sum)
	if TrafficDensity.server:
		# A server places them one a step until the next check, not all in
		# this one (each is a route planned: with 48 players, a long step).
		_spawns_left = many + 1
		_spawn_short = short
		_spawn_cum = cum
		_spawn_sum = sum
		_spawn_want = roundi(want)
	else:
		for i in many + 1:
			if not _spawn_one(short, cum, sum, roundi(want)):
				break
	var u3 := 0
	if prof:
		u3 = Time.get_ticks_usec()
		TickProfile.add(&"balance: placing", u3 - u2)
	_physics_lod(Vector2.INF, false)
	var u4 := 0
	if prof:
		u4 = Time.get_ticks_usec()
		TickProfile.add(&"balance: near and far (physics LOD)", u4 - u3)
	buses.tick(0.25, fp)
	if prof:
		TickProfile.add(&"balance: buses", Time.get_ticks_usec() - u4)


## One more car in the squares `short` (cumulative lack `cum`, of `sum`)
## if there are fewer than `want`: false if there are enough already.
func _spawn_one(short: Array[Vector2i], cum: PackedFloat32Array, sum: float, want: int) -> bool:
	if drivers.size() >= want or short.is_empty():
		return false
	for attempt in 4:
		var k := mini(cum.bsearch(rng.randf() * sum), short.size() - 1)
		_planned = false
		if _try_spawn(short[k]):
			break
		if _planned and TrafficDensity.server:
			break # (a route planned for nothing: no more this step)
	return true


## Police cars out driving (computer-driven), which traffic makes room
## for: the dispatcher's units in their cars (without a dispatcher, any
## computer-driven police car).
func _police_driving() -> int:
	var n := 0
	var disp := PoliceDispatcher.find(get_tree())
	if disp != null:
		for u: PoliceUnit in disp.units:
			var c := u.car
			if c != null and is_instance_valid(c) and c.police != null and c.ai_controls != null and c.is_inside_tree():
				n += 1
		return n
	for c: Car in Car.all:
		if c.police != null and c.ai_controls != null and c.listed():
			n += 1
	return n


## Each driver's distance to the nearest player (near_dist), and the
## players by square.
func _update_nearness() -> void:
	var vs := viewers()
	_v2 = PackedVector2Array()
	_vbuckets = {}
	_vbucket_idx = {}
	for v: Vector3 in vs:
		var p := Vector2(v.x, v.z)
		var k := Vector2i(floori(p.x / VIEW_BUCKET), floori(p.y / VIEW_BUCKET))
		if not _vbuckets.has(k):
			_vbuckets[k] = PackedVector2Array()
			_vbucket_idx[k] = PackedInt32Array()
		var arr: PackedVector2Array = _vbuckets[k]
		arr.append(p)
		_vbuckets[k] = arr
		var idx: PackedInt32Array = _vbucket_idx[k]
		idx.append(_v2.size())
		_vbucket_idx[k] = idx
		_v2.append(p)
	for d: TrafficDriver in drivers:
		var p := d.position()
		d.near_dist = INF if p == Vector3.INF else nearest_viewer(Vector2(p.x, p.z))
	_unmeasured.clear()


## Distance from p to the nearest player, or INF past VIEW_BUCKET.
func nearest_viewer(p: Vector2) -> float:
	var k := Vector2i(floori(p.x / VIEW_BUCKET), floori(p.y / VIEW_BUCKET))
	var best := INF
	for x in range(k.x - 1, k.x + 2):
		for z in range(k.y - 1, k.y + 2):
			var arr: Variant = _vbuckets.get(Vector2i(x, z))
			if arr == null:
				continue
			for v: Vector2 in arr:
				best = minf(best, v.distance_squared_to(p))
	best = sqrt(best)
	return best if best <= VIEW_BUCKET else INF


## The players within r of p.
func viewers_near(p: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var k := Vector2i(floori(p.x / VIEW_BUCKET), floori(p.y / VIEW_BUCKET))
	var span := ceili(r / VIEW_BUCKET)
	for x in range(k.x - span, k.x + span + 1):
		for z in range(k.y - span, k.y + span + 1):
			var arr: Variant = _vbuckets.get(Vector2i(x, z))
			if arr == null:
				continue
			for v: Vector2 in arr:
				if v.distance_squared_to(p) <= r * r:
					out.append(v)
	return out


func _cell_of(d: TrafficDriver) -> Vector2i:
	var p := d.position()
	return TrafficDensity.cell_of(Vector2(p.x, p.z)) if p != Vector3.INF else Vector2i(1 << 20, 0)


func _done_with(d: TrafficDriver) -> bool:
	if d.state == TrafficDriver.State.GONE:
		return true
	var p := d.position()
	if p == Vector3.INF:
		return true
	var dist := d.near_dist
	if d.state == TrafficDriver.State.OUT:
		# Left in the street (its driver ran off): away once far enough.
		return d.abandoned and dist > TrafficDensity.DESPAWN
	if dist > TrafficDensity.DESPAWN:
		return true
	if d.truck and dist > TrafficDensity.PHYSICS_RADIUS + 40.0:
		return true # no far version: away once nobody can see it
	if d.state == TrafficDriver.State.ARRIVED and d.age - d.arrived_at > 1.5:
		return true
	if d.follower != null and not d.follower.moving:
		return true
	if d.stuck_for > 25.0 or d.upside_down > 3.0:
		return true
	return false


func _seen(d: TrafficDriver) -> bool:
	if d.seen_mark == _check_n:
		return d.seen_now
	var p := d.position()
	d.seen_now = p != Vector3.INF and _seen_at(p)
	d.seen_mark = _check_n
	return d.seen_now


## Can any player see p (TrafficSight)?
func _seen_at(p: Vector3) -> bool:
	var near := PackedVector3Array()
	if not others.is_empty():
		if _vbuckets.is_empty():
			near = others
		else:
			for v: Vector2 in viewers_near(Vector2(p.x, p.z), TrafficSight.SEE_RANGE):
				near.append(Vector3(v.x, world.terrain.h2(v), v.y))
	return TrafficSight.seen_by_any(get_tree(), p, local_point(), near)


## A far car's follower to move on this step (_flush_followers). One far
## from everyone on a server (`slow`) moves every other step, two steps
## at a time.
func _queue_follower(d: TrafficDriver, slow := false) -> void:
	if not is_instance_valid(d.follower):
		return
	if not slow:
		_batch.append(d)
		_batch_rf.append(d.follower)
	elif (_steps + d.id) % 2 == 0:
		_slow_batch.append(d)
		_slow_batch_rf.append(d.follower)


## The far cars' followers queued so far, moved on one step. Traffic's
## followers don't process themselves (their own _physics_process is off,
## see _make_follower): they're all moved here, as
## RoadFollower._physics_process would (TcaFollowers.step, or its twin
## _move_followers_gd), placed with the line sampled inline.
##
## They're moved at the ground's height and drawn at the street's, a
## bridge deck or a street raised above the ground, wherever the street's
## collision is built (checked a few times a second, `lift`). A server
## draws nothing, so it doesn't look.
func _flush_followers(delta: float) -> void:
	if not _slow_batch_rf.is_empty():
		_move_batch(_slow_batch, _slow_batch_rf, delta * 2.0)
	if not _batch_rf.is_empty():
		_move_batch(_batch, _batch_rf, delta)


func _move_batch(batch: Array[TrafficDriver], rfs: Array, delta: float) -> void:
	var arrived: PackedInt32Array
	if _fnat != null and FollowerParity.on:
		arrived = FollowerParity.step(self, rfs, delta)
	elif _fnat != null:
		arrived = _fnat.call("step", rfs, delta, world.terrain)
	else:
		arrived = _move_followers_gd(rfs, delta)
	for i in arrived:
		(rfs[i] as RoadFollower).arrived.emit()
	if not TrafficDensity.server:
		for d: TrafficDriver in batch:
			_lift(d, delta)
	batch.clear()
	rfs.clear()


## TcaFollowers.step in GDScript: each follower moved on one step. Returns
## the indices of those that arrived (their owner says so).
func _move_followers_gd(followers: Array, delta: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in followers.size():
		var rf: RoadFollower = followers[i]
		if not rf.moving:
			rf.speed = 0.0
			rf.velocity = Vector3.ZERO
		elif _advance_follower(rf, delta):
			out.append(i)
	return out


## A far car drawn up onto the street's surface, smoothly.
func _lift(d: TrafficDriver, delta: float) -> void:
	var rf := d.follower
	d.lift = move_toward(d.lift, d.lift_target, 6.0 * delta) # up onto a deck smoothly
	d.lift_check -= delta
	if d.lift_check > 0.0 or rf.route == null:
		return
	d.lift_check = 0.3
	var y := surface_y(rf.global_position, d.civil.edge_at(rf.along))
	d.lift_target = 0.0 if is_nan(y) else clampf(y - rf.global_position.y, -3.0, 20.0)


## RoadFollower._physics_process for a moving follower (the same speeds,
## holds and arrival), true if it arrived (its `arrived` is left to the
## caller). A copy: a change to RoadFollower._physics_process or
## RoadFollower._place goes here too (and in place_follower, and in their
## native twin, TcaFollowers.step, then tools/native_check.gd).
func _advance_follower(rf: RoadFollower, delta: float) -> bool:
	var route := rf.route
	var along := rf.along
	var want := minf(minf(rf.speed_kmh / 3.6, route.limit_at(along + rf.speed * 0.3)), rf.max_speed)
	if rf.hold_at >= 0.0:
		want = minf(want, sqrt(2.0 * rf.decel * 0.8 * maxf(rf.hold_at - along - 3.0, 0.0)))
		if rf.hold_at - along < 3.5:
			rf.speed = 0.0
			rf.velocity = Vector3.ZERO
			return false
	var speed := move_toward(rf.speed, want, (rf.accel if want > rf.speed else rf.decel) * delta)
	rf.speed = speed
	var before := rf.global_position
	along += maxf(speed, 0.3 if along < route.length - 0.5 and rf.max_speed > 0.3 else 0.0) * delta
	if along >= route.length - 0.5:
		rf.along = route.length
		rf.moving = false
		place_follower(rf)
		rf.speed = 0.0
		rf.velocity = Vector3.ZERO
		return true
	rf.along = along
	var at := place_follower(rf)
	rf.velocity = (at - before) / maxf(delta, 0.0001)
	return false


## Puts a follower where it is along its route, facing along it, at the
## ground's height (as RoadFollower._place: facing along the chord from
## TURN_EASE behind to TURN_EASE ahead). Returns where it now is.
static func place_follower(rf: RoadFollower) -> Vector3:
	var pts := rf.route.points
	var last := pts.size() - 1
	var a := rf.along
	var f := clampf(a / StreetRoute.STEP, 0.0, last)
	var i := mini(int(f), last - 1)
	var p := pts[i].lerp(pts[i + 1], f - i)
	f = clampf((a + RoadFollower.TURN_EASE) / StreetRoute.STEP, 0.0, last)
	i = mini(int(f), last - 1)
	var ahead := pts[i].lerp(pts[i + 1], f - i)
	f = clampf((a - RoadFollower.TURN_EASE) / StreetRoute.STEP, 0.0, last)
	i = mini(int(f), last - 1)
	var d := ahead - pts[i].lerp(pts[i + 1], f - i)
	if d.length_squared() < 0.25:
		d = rf.route.dir_at(a)
	d = d.normalized()
	var y := rf.terrain.h2(p) if rf.terrain != null else rf.global_position.y
	var at := Vector3(p.x, y, p.y)
	rf.global_transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), at)
	return at


## The streets in area square c cars can appear on, by how busy they are:
## [edges, cumulative weights, total].
func _streets_in(c: Vector2i) -> Array:
	var got: Variant = _cell_edges.get(c)
	if got != null:
		return got
	var edges: Array[RoadNetwork.RoadEdge] = []
	var cum := PackedFloat32Array()
	var sum := 0.0
	var rect := Rect2(Vector2(c) * TrafficDensity.CELL, Vector2.ONE * TrafficDensity.CELL)
	for e in net.edges_near(rect):
		var w := TrafficDensity.class_weight(e)
		if w <= 0.0 or e.bridge or e.length < 24.0:
			continue
		sum += w * e.length
		edges.append(e)
		cum.append(sum)
	var out := [edges, cum, sum]
	_cell_edges[c] = out
	return out


## One more car somewhere on the streets of area square c, out of
## everyone's sight. False if this try found nowhere.
func _try_spawn(c: Vector2i) -> bool:
	var fp := focus_point()
	var fp2 := Vector2(fp.x, fp.z)
	var streets := _streets_in(c)
	var edges: Array[RoadNetwork.RoadEdge] = streets[0]
	if edges.is_empty():
		return false
	var i := (streets[1] as PackedFloat32Array).bsearch(rng.randf() * float(streets[2]))
	var e: RoadNetwork.RoadEdge = edges[mini(i, edges.size() - 1)]
	var along := rng.randf_range(10.0, e.length - 10.0)
	var forward := rng.randf() < 0.5
	if e.oneway != 0:
		forward = e.oneway == 1
	var sp: Array = RoadNetwork.sample(e.points, along)
	var dir: Vector2 = (sp[1] as Vector2) * (1.0 if forward else -1.0)
	var pos: Vector2 = (sp[0] as Vector2) + Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, forward)
	if TrafficDensity.cell_of(pos) != c:
		return false # (the street runs on out of the square)
	var dist := nearest_viewer(pos)
	if dist < TrafficDensity.SPAWN_MIN or dist > TrafficDensity.SPAWN_MAX:
		return false
	if local_viewer and heat.keep_clear(pos, fp2):
		return false
	var p3 := Vector3(pos.x, world.terrain.h2(pos), pos.y)
	if _seen_at(p3):
		return false
	for u: RoadUsers.User in RoadUsers.near(get_tree(), pos, 16.0):
		if u.pos.distance_to(pos) < 16.0:
			return false
	var dest := dests.pick(rng, pos, 250.0, 1400.0)
	if dest.is_empty():
		return false
	_planned = true
	var r := StreetRoute.plan(net, pos, dest["street"], plan_options(dir))
	if r.is_empty() or r.partial or r.gaps > 0 or r.length < 80.0:
		return false
	# The odd truck: only ever a real vehicle near the player (it has no
	# far version), so only placed within the physics radius.
	var truck := ""
	if dist < TrafficDensity.PHYSICS_RADIUS - 15.0 and rng.randf() < TrafficPersonality.TRUCK_ODDS and _truck_count() < TrafficPersonality.TRUCKS_MAX:
		truck = TrafficPersonality.pick_truck(rng)
	var d := _new_driver(dest, truck)
	var rf := _make_follower(d, Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), p3))
	rf.set_route(r)
	rf.speed = minf(JunctionRules.limit_kmh(e) / 3.6 * 0.8, r.limit_at(0.0))
	d.near_dist = dist
	if d.truck and not _to_car(d):
		_remove(d)
		removal_log.pop_back() # never seen: it was never there
		return false
	if d.character == "chatter":
		d.chat_at = rng.randf_range(60.0, maxf(61.0, r.length - 40.0))
	if keep_logs:
		spawn_log.append([_t, p3, _seen_at(p3)])
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
		_remove(d)
		removal_log.pop_back()
		return null
	if keep_logs:
		spawn_log.append([_t, p3, _seen_at(p3)])
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
		_remove(d)
		removal_log.pop_back()
		return null
	if keep_logs:
		spawn_log.append([_t, p3, _seen_at(p3)])
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
	_unmeasured.append(d)
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
	rf.set_physics_process(false) # moved by _flush_followers
	rf.global_transform = xf
	rf.civil = d.civil
	d.civil.attach(rf, net, data)
	rf.arrived.connect(d.on_arrived)
	d.follower = rf
	return rf


func _remove(d: TrafficDriver, _fp := Vector3.INF) -> void:
	if d.tow:
		tows.truck_gone(d)
	var p := d.position()
	if keep_logs:
		removal_log.append([_t, p, p != Vector3.INF and _seen_at(p)])
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

## Full physics for each player's nearest, within the radius (shared by
## players near each other); the road follower for the rest, once they're
## past the radius of every player.
##
## In a check (`all` false), only the drivers made since the nearness was
## worked out are measured again: nothing has moved since.
func _physics_lod(_fp2 := Vector2.INF, all := true) -> void:
	if all:
		_update_nearness()
	else:
		for d: TrafficDriver in _unmeasured:
			var p := d.position()
			d.near_dist = INF if p == Vector3.INF else nearest_viewer(Vector2(p.x, p.z))
		_unmeasured.clear()
	var radius := TrafficDensity.physics_radius()
	var cap := TrafficDensity.physics_cap()
	# Past the radius they keep their physics a while (so a car at the edge
	# isn't swapped back and forth): on a server, where nobody sees the
	# swap, a shorter while.
	var keep := radius + (SERVER_KEEP if TrafficDensity.server else 40.0)
	var by_viewer := {} # index in _v2 -> [[distance, driver], ...] within keep
	var cars_by := {} # index in _v2 -> real cars within keep
	for d: TrafficDriver in drivers:
		if d.near_dist > keep:
			if d.car != null and d.state == TrafficDriver.State.DRIVE:
				_to_follower(d)
			continue
		var p := d.position()
		var p2 := Vector2(p.x, p.z)
		for vi in _viewers_round(p2):
			var dist := _v2[vi].distance_to(p2)
			if dist < keep:
				if d.car != null:
					cars_by[vi] = int(cars_by.get(vi, 0)) + 1
				elif dist < radius:
					if not by_viewer.has(vi):
						by_viewer[vi] = []
					(by_viewer[vi] as Array).append([dist, d])
	# Each player's nearest far ones made real, while that player has fewer
	# than the cap (counting the real ones just past the radius, not yet
	# gone back: a car shared by two players counts for both).
	var made := 0
	var budget := 2 + _v2.size() / 3 # new ones per check, spread over checks
	for vi: int in by_viewer:
		var near: Array = by_viewer[vi]
		near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var cars := int(cars_by.get(vi, 0))
		for x: Array in near:
			if cars >= cap or made >= budget:
				break
			var d: TrafficDriver = x[1]
			if d.car == null and d.follower != null and d.state == TrafficDriver.State.DRIVE and _to_car(d):
				cars += 1
				made += 1
				for vj in _v2.size():
					if vj != vi and _v2[vj].distance_to(_v2[vi]) < 2.0 * keep:
						var p := d.position()
						if _v2[vj].distance_to(Vector2(p.x, p.z)) < keep:
							cars_by[vj] = int(cars_by.get(vj, 0)) + 1


## The indices (in _v2) of the players who might be within VIEW_BUCKET of
## p, in order.
func _viewers_round(p: Vector2) -> PackedInt32Array:
	var k := Vector2i(floori(p.x / VIEW_BUCKET), floori(p.y / VIEW_BUCKET))
	var out := PackedInt32Array()
	for x in range(k.x - 1, k.x + 2):
		for z in range(k.y - 1, k.y + 2):
			var idx: Variant = _vbucket_idx.get(Vector2i(x, z))
			if idx != null:
				out.append_array(idx)
	out.sort()
	return out


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
	crime_seen.emit("take_car", car.global_position)
	var wanted := get_node_or_null("/root/Wanted")
	if wanted == null:
		return
	# A crime once the police hear of it (Wanted.player_crime): at once if
	# an officer saw it, else when someone calls it in. Nobody in the car,
	# only the other witnesses can; the owner, standing there, calls it in
	# a few seconds later (wherever you've got to by then).
	var at := car.global_position
	if bool(wanted.call("player_crime", "take_car", at)) or d.abandoned:
		return
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", "\"Hey! That's my car!\"", "they're calling it in")
	wanted.call("phone_call", d, true)
	await get_tree().create_timer(randf_range(OWNER_CALL.x, OWNER_CALL.y)).timeout
	if is_instance_valid(wanted):
		wanted.call("phone_call", d, false)
		wanted.call("witness_report", at, at, "owner")


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
		crime_seen.emit(kind, at)
		if target is Car:
			StreetEvents.post("painted", (target as Car).global_position, 25.0, 25.0)
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
	for u: RoadUsers.User in RoadUsers.near(get_tree(), Vector2(p.x, p.z), 8.0):
		if u.node != d.car and not u.person and u.pos.distance_to(Vector2(p.x, p.z)) < 8.0:
			near = true
	if near:
		# Hit by someone: brake, honk, and now and then sit there a while.
		d.civil.react_hit(d.rng.randf_range(6.0, 10.0) if d.rng.randf() < 0.3 else d.rng.randf_range(1.5, 3.0))
	crash_seen(p, d)


## Drivers going past something in the street (StreetEvents) ease off to
## look: only the real cars near a player, a few times a second.
func _rubberneck(delta: float) -> void:
	_look_t -= delta
	if _look_t > 0.0:
		return
	_look_t = 0.3
	var events := StreetEvents.active()
	if events.is_empty():
		return
	for d: TrafficDriver in drivers:
		if d.car == null or d.state != TrafficDriver.State.DRIVE or d.bus_route >= 0 or d.tow:
			continue
		var q := Vector2(d.car.global_position.x, d.car.global_position.z)
		var f := -d.car.global_basis.z
		var fwd := Vector2(f.x, f.z)
		for ev: Dictionary in events:
			var rel := (ev["pos"] as Vector2) - q
			# Coming up on it or alongside, close enough to see it well.
			if rel.length() < 28.0 and rel.dot(fwd) > -4.0:
				d.civil.look(0.6, 1.2)
				break


## A crash at p: the drivers coming up on it stop for a moment (and the
## people on foot near it look: StreetEvents).
func crash_seen(p: Vector3, except: TrafficDriver = null) -> void:
	StreetEvents.post("crash", p, 35.0, 32.0)
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

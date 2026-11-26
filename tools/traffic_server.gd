extends SceneTree
## Town traffic as a server would run it: for many players at once, with no
## player on this machine. Simulated players stand about town (half spread
## out, half in groups, as parties and events gather them); the town is
## built round each of them (ChunkStreamer.extra_foci), traffic fills in
## round them all (TrafficManager.others), and then it measures what that
## costs a server tick and how busy the streets round each player are.
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/traffic_server.gd -- [--players=48] [--secs=60] [--fill=40] [--move] [--profile] [--budget[=24,50,200]]
##
## With --fixed-fps 60 every frame is one physics step, so the frame time
## is what a server tick costs (it has 16.7 ms at 60 a second). --move has
## the players walk along the streets (the town is built round them as they
## go, which costs frames of its own: leave it off to time traffic alone).
## --profile says where the tick goes (TickProfile: traffic's parts, the
## police, people on foot, the chunk streamer, all the physics scripts,
## and what's left, mostly the physics engine's own step).
## Prints "SERVER ..." lines. With --budget (CI, and after changing
## traffic, the police or the server path) it fails (exit code 1) when a
## tick is over the budget: --budget=average,99th percentile,worst (ms),
## by default BUDGET: twice the aim of 12 and 25 ms on a quiet machine
## (CI machines and shared ones vary), and four times the aim of 50 for
## the worst single tick (a shared machine can stall one); or when the
## native library isn't loaded.

## The default --budget (ms): average, 99th percentile, worst tick.
const BUDGET := [24.0, 50.0, 200.0]

var _main: Node
var _world: WorldBuilder
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var players := 48
	var secs := 60.0
	var fill := 40.0
	var move := false
	var profile := false
	var budget: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--players="):
			players = int(a.trim_prefix("--players="))
		elif a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--fill="):
			fill = float(a.trim_prefix("--fill="))
		elif a == "--move":
			move = true
		elif a == "--profile":
			profile = true
		elif a == "--budget":
			budget = BUDGET.duplicate()
		elif a.begins_with("--budget="):
			budget = []
			for x in a.trim_prefix("--budget=").split(","):
				budget.append(float(x))
	_rng.seed = 4848
	TrafficManager.autostart = false
	PedestrianManager.autostart = false
	TrafficDensity.server = true
	Car.silent = true
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	_world = _main.get_node("World")
	if not _world.is_built:
		await _world.built
	var net := _world.network
	var player: Node3D = _main.get_node("Player")
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.remove_from_group(RoadUsers.PEOPLE_GROUP)
	player.visible = false

	var spots := _pick_spots(net, players)
	var walk: Array = [] # per player: [route, along]
	for p: Vector2 in spots:
		walk.append([null, 0.0])
	var s := _world.streamer
	s.extra_foci = spots
	var t0 := Time.get_ticks_msec()
	while not s.extras_ready() and Time.get_ticks_msec() - t0 < 1800000:
		s._update()
		s._reap()
		s._attach_finished(8)
		await process_frame
	print("SERVER town built round %d players in %.0f s: %d full chunks, %d distant; %.0f MB of memory in use" % [
		players, (Time.get_ticks_msec() - t0) / 1000.0, s.near_count(), s.far_count(), OS.get_static_memory_usage() / 1048576.0])
	if profile:
		TickProfile.add_marks(root)

	var tm: TrafficManager = _main.get_node("Traffic")
	tm.local_viewer = false
	tm.others = _eyes(spots)
	tm.running = true
	var frame_us: Array[int] = []
	var phys_ms := 0.0
	var samples := 0
	var count_sum := 0.0
	var cars_sum := 0.0
	var cars_most := 0
	var drivers_most := 0
	var near_sum := PackedFloat32Array()
	near_sum.resize(players)
	var close_sum := PackedFloat32Array()
	close_sum.resize(players)
	var sample_t := 0.0
	var t := 0.0
	var last := Time.get_ticks_usec()
	var spawned0 := 0
	var removed0 := 0
	var checks0 := 0
	while t < fill + secs:
		await physics_frame
		var dt := 1.0 / Engine.physics_ticks_per_second
		t += dt
		if move:
			_walk(net, spots, walk, dt)
			s.extra_foci = spots
			tm.others = _eyes(spots)
		var now := Time.get_ticks_usec()
		if t > fill:
			if spawned0 == 0:
				spawned0 = tm.spawn_log.size()
				removed0 = tm.removal_log.size()
				checks0 = TrafficSight.checks
			if profile and not TickProfile.on:
				TickProfile.on = true
				TickProfile.reset()
			elif profile:
				TickProfile.tick(now - last)
			frame_us.append(now - last)
			phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			sample_t -= dt
			if sample_t <= 0.0:
				sample_t = 1.0
				samples += 1
				var cars := 0
				for d: TrafficDriver in tm.drivers:
					if d.car != null:
						cars += 1
				count_sum += tm.drivers.size()
				cars_sum += cars
				cars_most = maxi(cars_most, cars)
				for i in players:
					var n := 0
					var c := 0
					for d: TrafficDriver in tm.drivers:
						var p := d.position()
						if p == Vector3.INF:
							continue
						var dd := Vector2(p.x, p.z).distance_to(spots[i])
						if dd < TrafficDensity.SPAWN_MAX:
							n += 1
						if dd < 150.0:
							c += 1
					near_sum[i] += n
					close_sum[i] += c
		drivers_most = maxi(drivers_most, tm.drivers.size())
		last = now
	tm.running = false
	if profile:
		TickProfile.on = false
		var tick_ms := 0.0
		for f in frame_us:
			tick_ms += f / 1000.0
		tick_ms /= maxi(frame_us.size(), 1)
		var scripts_ms := (int(TickProfile._us.get(&"physics scripts (all)", 0)) + int(TickProfile._us.get(&"idle process (all)", 0))) / 1000.0 / maxi(TickProfile._ticks, 1)
		print("SERVER where a tick goes (ms): %s; the physics engine's step and the rest %.2f" % [TickProfile.report(), tick_ms - scripts_ms])
		print("SERVER slow ticks: %s" % TickProfile.report_slow())
	frame_us.sort()
	var n := frame_us.size()
	var sum := 0
	for f in frame_us:
		sum += f
	print("SERVER %d players for %.0f s (after %.0f s to fill): a tick takes %.1f ms on average, %.1f typical, %.1f at the 99th percentile, worst %.1f (%d of %d over 16.7 ms); physics process %.1f ms a tick" % [
		players, secs, fill, sum / 1000.0 / maxi(n, 1), frame_us[n / 2] / 1000.0, frame_us[mini(n - 1, n * 99 / 100)] / 1000.0, frame_us[n - 1] / 1000.0,
		frame_us.filter(func(f: int) -> bool: return f > 16700).size(), n, phys_ms / maxi(n, 1)])
	print("SERVER traffic: %.0f vehicles on average (wanted %.0f, most %d, town limit %d), %.1f with physics (most %d, %d a player); %d placed and %d taken away in the %.0f s, %d sight checks; road users %d" % [
		count_sum / maxi(samples, 1), tm.wanted, drivers_most, TrafficDensity.TOWN_MAX, cars_sum / maxi(samples, 1), cars_most, TrafficDensity.physics_cap(),
		tm.spawn_log.size() - spawned0, tm.removal_log.size() - removed0, secs, TrafficSight.checks - checks0, RoadUsers.all(self).size()])
	var near_avg: Array[float] = []
	var close_avg: Array[float] = []
	for i in players:
		near_avg.append(near_sum[i] / maxi(samples, 1))
		close_avg.append(close_sum[i] / maxi(samples, 1))
	near_avg.sort()
	close_avg.sort()
	print("SERVER round each player: within %.0f m %.0f vehicles (fewest %.0f, most %.0f); within 150 m %.1f (fewest %.1f, most %.1f)" % [
		TrafficDensity.SPAWN_MAX, _mean(near_avg), near_avg[0], near_avg[players - 1], _mean(close_avg), close_avg[0], close_avg[players - 1]])
	var seen_spawns := 0
	for e: Array in tm.spawn_log.slice(spawned0):
		if bool(e[2]):
			seen_spawns += 1
	var seen_removals := 0
	for e: Array in tm.removal_log.slice(removed0):
		if bool(e[2]):
			seen_removals += 1
	print("SERVER placed where a player could see: %d; taken away where one could: %d" % [seen_spawns, seen_removals])
	if budget.size() >= 3:
		var got := [sum / 1000.0 / maxi(n, 1), frame_us[mini(n - 1, n * 99 / 100)] / 1000.0, frame_us[n - 1] / 1000.0]
		const WHAT := ["average", "99th percentile", "worst"]
		var over := PackedStringArray()
		for i in 3:
			if float(got[i]) > float(budget[i]):
				over.append("%s %.1f ms (budget %.0f)" % [WHAT[i], got[i], budget[i]])
		if not ClassDB.class_exists("TcaFollowers") or not CivilDriving.native_on:
			over.append("the native library isn't loaded (native/README.md)")
		print("SERVER budget %s: average %.1f of %.0f ms, 99th percentile %.1f of %.0f, worst %.1f of %.0f%s" % [
			"OK" if over.is_empty() else "FAIL", got[0], budget[0], got[1], budget[1], got[2], budget[2],
			"" if over.is_empty() else "; over: " + ", ".join(over)])
		quit(0 if over.is_empty() else 1)
		return
	quit()


func _mean(a: Array[float]) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / maxi(a.size(), 1)


## Where the players stand: half anywhere on the streets of town, half in
## groups of six (downtown and a few other places).
func _pick_spots(net: RoadNetwork, players: int) -> PackedVector2Array:
	var edges: Array[RoadNetwork.RoadEdge] = []
	var cum := PackedFloat32Array()
	var sum := 0.0
	for e in net.edges:
		if TrafficDensity.class_weight(e) <= 0.0 or e.bridge or e.length < 30.0:
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		if not _world.is_in_play_area(mid):
			continue
		sum += e.length
		edges.append(e)
		cum.append(sum)
	var out := PackedVector2Array()
	var groups := PackedVector2Array()
	var downtown := Vector2.ZERO
	var best := INF
	for nid: String in net.signal_nodes:
		var d := (net.nodes[nid] as Vector2).length()
		if d < best:
			best = d
			downtown = net.nodes[nid]
	groups.append(downtown)
	while out.size() < players:
		var spread := out.size() < players / 2
		var p: Vector2
		if spread or groups.size() <= (out.size() - players / 2) / 6:
			var e: RoadNetwork.RoadEdge = edges[mini(cum.bsearch(_rng.randf() * sum), edges.size() - 1)]
			p = RoadNetwork.sample(e.points, _rng.randf_range(5.0, e.length - 5.0))[0]
			if not spread:
				groups.append(p)
		else:
			# Near the group's spot, on a street.
			var g := groups[(out.size() - players / 2) / 6]
			var e2: RoadNetwork.RoadEdge = null
			for e in net.edges_near(Rect2(g - Vector2(60, 60), Vector2(120, 120))):
				if TrafficDensity.class_weight(e) > 0.0 and _rng.randf() < 0.5:
					e2 = e
			if e2 == null:
				p = g
			else:
				p = RoadNetwork.sample(e2.points, _rng.randf_range(0.0, e2.length))[0]
		out.append(p)
	return out


func _eyes(spots: PackedVector2Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p: Vector2 in spots:
		out.append(Vector3(p.x, _world.terrain.h2(p), p.y))
	return out


## Players walking (well, a brisk 5 m/s) along the streets to somewhere.
func _walk(net: RoadNetwork, spots: PackedVector2Array, walk: Array, dt: float) -> void:
	for i in spots.size():
		var w: Array = walk[i]
		var r: StreetRoute = w[0]
		if r == null or float(w[1]) >= r.length - 2.0:
			var goal := spots[i] + Vector2.from_angle(_rng.randf() * TAU) * 600.0
			r = StreetRoute.plan(net, spots[i], goal, {})
			if r == null or r.is_empty():
				continue
			w[0] = r
			w[1] = 0.0
		w[1] = float(w[1]) + 5.0 * dt
		spots[i] = r.sample(float(w[1]))

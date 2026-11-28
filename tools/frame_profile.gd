extends SceneTree
## Where a player's frame goes on the processor, in the real town as it's
## played: the player standing downtown at the start, the traffic and the
## people on foot out, everything the game runs each physics step and each
## frame (no drawing: run it headless).
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/frame_profile.gd -- [--secs=40] [--no-traffic] [--no-people] [--wanted=4] [--no-rails]
##
## With --fixed-fps 60 every frame is one physics step, so a frame's time is
## what a step costs with the frame's own processing. Prints "FRAME" lines:
## the average, typical (median), 99th percentile and worst, the physics
## scripts' share (TickProfile: traffic's parts, the cars' own physics, the
## people on foot), how many of each kind of thing were running, and the
## slowest frames' biggest parts. --no-traffic and --no-people leave those
## out, to see what each costs by the difference. --wanted=N sets the
## wanted level at the start (the police come for the player, who stands
## still and is watched the whole time, as in a fight). --no-rails keeps
## every near traffic car a real car (TrafficManager, "on rails"), to see
## what the rails save. A laptop processor runs
## this two to three times slower: at 30 fps (Low, when the graphics card
## can't make 60) each drawn frame runs two physics steps, so a typical
## frame here over about 6 ms leaves a laptop no room in its 33 ms.

var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var secs := 40.0
	var traffic := true
	var people := true
	var wanted := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.trim_prefix("--secs="))
		elif a == "--no-traffic":
			traffic = false
		elif a == "--no-people":
			people = false
		elif a.begins_with("--wanted="):
			wanted = int(a.trim_prefix("--wanted="))
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	var world: Node = _main.get_node("World")
	if not world.is_built:
		await world.built
	await world.wait_until_settled()
	var tm: TrafficManager = _main.get_node_or_null("Traffic")
	if tm != null and traffic:
		tm.running = true # (off by default under --script)
	if tm != null and not traffic:
		tm.running = false
		for d: TrafficDriver in tm.drivers.duplicate():
			if d.car != null and is_instance_valid(d.car):
				d.car.queue_free()
		tm.process_mode = Node.PROCESS_MODE_DISABLED
	if not people:
		for n in root.find_children("*", "PedestrianManager", true, false):
			n.process_mode = Node.PROCESS_MODE_DISABLED
			for c in n.get_children():
				c.queue_free()
	var w := root.get_node_or_null("Wanted")
	if wanted > 0 and w != null:
		w.debug_set_level(wanted)
		w.debug_watch(true)
	# Let the traffic and people (and the police) fill in round the player first.
	for i in 60 * 20:
		await physics_frame
	TickProfile.add_marks(root)
	TickProfile.on = true
	TickProfile.reset()
	var frame_us: Array[int] = []
	var phys_ms := 0.0
	var last := Time.get_ticks_usec()
	var t := 0.0
	var counts := {}
	var samples := 0
	# Each frame in two halves: from its physics_frame (the physics
	# scripts, then the physics engine's own step) to its process_frame,
	# and from there (the frame's own scripts, the drawing: none, headless,
	# and the rest of the engine's frame) to the next physics_frame.
	var slow: Array = [] # [frame, physics half, the rest, physics scripts in it] ms
	var at_process := [0]
	var on_process := func() -> void: at_process[0] = Time.get_ticks_usec()
	process_frame.connect(on_process)
	while t < secs:
		var scripts_before := int(TickProfile._us.get(&"cars (Car._physics_process)", 0))
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var now := Time.get_ticks_usec()
		TickProfile.tick(now - last)
		frame_us.append(now - last)
		if now - last > 12000 and slow.size() < 12:
			slow.append([(now - last) / 1000.0, (int(at_process[0]) - last) / 1000.0, (now - int(at_process[0])) / 1000.0,
				(int(TickProfile._us.get(&"cars (Car._physics_process)", 0)) - scripts_before) / 1000.0])
		last = now
		phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		if frame_us.size() % 60 == 0:
			# (Counting walks every node: tens of ms. Left out of the times.)
			samples += 1
			_count(counts)
			last = Time.get_ticks_usec()
	TickProfile.on = false
	var sorted := frame_us.duplicate()
	sorted.sort()
	var total := 0
	for u in frame_us:
		total += u
	var n := frame_us.size()
	print("FRAME %d frames (traffic %s, people %s): %.2f ms on average, %.2f typical, %.2f at the 99th percentile, worst %.1f" % [
		n, "on" if traffic else "off", "on" if people else "off", total / 1000.0 / n, sorted[n / 2] / 1000.0,
		sorted[mini(n - 1, int(n * 0.99))] / 1000.0, sorted[n - 1] / 1000.0])
	print("FRAME where a frame goes (ms): %s" % TickProfile.report())
	print("FRAME slow frames: %s" % TickProfile.report_slow())
	for x: Array in slow:
		print("FRAME slow frame %.1f ms: physics half %.1f, the rest %.1f; the cars' own physics scripts %.1f" % x)
	var parts: PackedStringArray = []
	for k: String in counts:
		parts.append("%s %.1f" % [k, float(counts[k]) / maxi(samples, 1)])
	print("FRAME running on average: %s" % ", ".join(parts))
	quit()


func _count(counts: Dictionary) -> void:
	var tally := {
		"cars": root.find_children("*", "Car", true, false).size(),
		"rigid bodies awake": 0,
		"characters": root.find_children("*", "CharacterBody3D", true, false).size(),
		"3D sounds playing": 0,
		"animation trees": root.find_children("*", "AnimationTree", true, false).size(),
		"animation players": root.find_children("*", "AnimationPlayer", true, false).size(),
		"skeletons": root.find_children("*", "Skeleton3D", true, false).size(),
		"nodes": root.get_tree().get_node_count(),
		"cars on rails": 0,
	}
	for c: Car in Car.all:
		if c.rail:
			tally["cars on rails"] += 1
	for b in root.find_children("*", "RigidBody3D", true, false):
		if not (b as RigidBody3D).sleeping:
			tally["rigid bodies awake"] += 1
	for a in root.find_children("*", "AudioStreamPlayer3D", true, false):
		if (a as AudioStreamPlayer3D).playing:
			tally["3D sounds playing"] += 1
	for k: String in tally:
		counts[k] = int(counts.get(k, 0)) + int(tally[k])

extends SceneTree
## Travels the bypass loop at highway speed and checks the town keeps up:
## up Riverside Drive from the Hillsborough Bridge junction, round the
## Arterial Highway to the Upton Road roundabout, down Upton Road, left onto
## Capital Drive and back into town by North River Road.
##
##   godot --headless --path . --script res://tools/drive_ring.gd -- --kmh=100
##
## A camera (which the chunk streamer follows) moves along the route. Every
## few metres it checks that the spot is inside the play area and that the
## solid street surface is there under it (not just the safety floor), and
## prints a summary. Headless, so it measures the streaming, not drawing.

const LEGS := [
	["Riverside Drive", "Grafton Street"],
	["Riverside Drive", "St Peters Road"],
	["Arterial Highway", "Upton Road Roundabout"],
	["Upton Road", "Nicholas Lane"],
	["Capital Drive", "North River Road"],
]
const FOLLOW := ["Riverside Drive", "Arterial Highway", "Upton Road", "Upton Road Roundabout", "", "Capital Drive", "North River Road"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var kmh := 100.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kmh="):
			kmh = a.get_slice("=", 1).to_float()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: WorldBuilder = main.get_node("World")
	var net := world.network
	var path := PackedVector2Array()
	var prev := ""
	for leg: Array in LEGS:
		var nid := net.find_junction(leg[0], leg[1])
		if nid == "":
			print("RING no junction %s / %s" % leg)
			quit(1)
			return
		if prev != "":
			var part := net.route(prev, nid, FOLLOW)
			if part.is_empty():
				print("RING no route to %s / %s" % leg)
				quit(1)
				return
			path.append_array(part)
		prev = nid
	var total := RoadNetwork.polyline_length(path)
	print("RING route %.1f km" % (total / 1000.0))
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var player: Node3D = main.get_node("Player")
	# Start like a player would: already there, with the town loaded round them.
	cam.global_position = world.terrain.at(path[0], 1.5)
	player.global_position = world.terrain.at(path[0], 0.5)
	await world.wait_until_settled()
	var speed := kmh / 3.6
	var d := 0.0
	var checks := 0
	var solid := 0
	var outside := 0
	var gaps: Array[String] = []
	var outs: Array[String] = []
	var next_check := 0.0
	var t0 := Time.get_ticks_msec()
	var worst_frame := 0
	var last := Time.get_ticks_usec()
	var space := cam.get_world_3d().direct_space_state
	while d < total:
		var dt := 1.0 / 60.0
		await physics_frame
		var now := Time.get_ticks_usec()
		worst_frame = maxi(worst_frame, now - last)
		last = now
		d += speed * dt
		var sp: Array = RoadNetwork.sample(path, d)
		var p: Vector2 = sp[0]
		var at := world.terrain.at(p, 1.5)
		cam.global_position = at
		player.global_position = at + Vector3(0, -1.0, 0)
		if d >= next_check:
			next_check = d + 10.0
			checks += 1
			if not world.is_in_play_area(p):
				outside += 1
				if outs.size() < 8:
					outs.append("%.0f m (%s at %.0f, %.0f)" % [d, world.street_name_at(p), p.x, p.y])
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 20.0, Layers.GROUND)
			var hit := space.intersect_ray(q)
			# The safety floor is 0.4 m under the ground; streets sit on it.
			if not hit.is_empty() and (hit["position"] as Vector3).y > world.terrain.h2(p) - 0.3 and (hit["collider"] as Node).name != "SafetyFloor":
				solid += 1
			elif gaps.size() < 8:
				var e: Dictionary = world.network.nearest_on_streets(p, 30.0)
				var what := "nothing" if hit.is_empty() else "%s at %.1f m" % [(hit["collider"] as Node).name, (hit["position"] as Vector3).y]
				gaps.append("%.0f m (%s%s, ground %.1f m, hit %s)" % [d, world.street_name_at(p), " bridge" if not e.is_empty() and (e["edge"] as RoadNetwork.RoadEdge).bridge else "", world.terrain.h2(p), what])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("RING %d checks at %.0f km/h: street solid under the car %d (%.1f%%), outside the play area %d; took %.0f s real time for %.0f s of driving" % [
		checks, kmh, solid, 100.0 * solid / maxi(checks, 1), outside, secs, total / speed])
	print("RING slowest frame %.0f ms" % (worst_frame / 1000.0))
	if not outs.is_empty():
		print("RING outside the play area at: %s" % ", ".join(outs))
	if not gaps.is_empty():
		print("RING no street collision at: %s" % ", ".join(gaps))
	quit()

class_name FollowerParity
extends RefCounted
## Checks the native far-traffic mover (TcaFollowers) against its GDScript
## twin (TrafficManager._move_followers_gd), for tools/native_check.gd, as
## CivilParity does for the drivers. While `on`, each batch of followers is
## moved the GDScript way first, what that left noted, everything put back
## as it was, then moved natively, and the two compared exactly: where each
## is (its whole transform), how far along, its speed and velocity, whether
## it's still moving, and which arrived. The native one's is what stays.
## `-- --car-parity` turns it on for any tool, with CarParity.

static var on := OS.get_cmdline_user_args().has("--car-parity")
static var steps := 0
static var differences := 0
static var first := ""


static func _state(rf: RoadFollower) -> Array:
	return [rf.global_transform, rf.along, rf.speed, rf.velocity, rf.moving]


static func _put(rf: RoadFollower, s: Array) -> void:
	rf.global_transform = s[0]
	rf.along = s[1]
	rf.speed = s[2]
	rf.velocity = s[3]
	rf.moving = s[4]


## Moves `followers` both ways from the same state, compares, and returns
## which arrived (the native answer).
static func step(tm: TrafficManager, followers: Array, delta: float) -> PackedInt32Array:
	var before: Array = []
	for rf: RoadFollower in followers:
		before.append(_state(rf))
	var gd_arrived := tm._move_followers_gd(followers, delta)
	var gd_after: Array = []
	for i in followers.size():
		gd_after.append(_state(followers[i]))
		_put(followers[i], before[i])
	var arrived: PackedInt32Array = tm._fnat.call("step", followers, delta, tm.world.terrain)
	const WHAT := ["transform", "along", "speed", "velocity", "moving"]
	for i in followers.size():
		steps += 1
		var a := _state(followers[i])
		var b: Array = gd_after[i]
		var diff := ""
		for k in a.size():
			if a[k] != b[k]:
				diff = "%s: native %s, GDScript %s" % [WHAT[k], a[k], b[k]]
				break
		if diff == "" and arrived.has(i) != gd_arrived.has(i):
			diff = "arrived: native %s, GDScript %s" % [arrived.has(i), gd_arrived.has(i)]
		if diff != "":
			differences += 1
			if first == "":
				first = "%s %s" % [(followers[i] as Node).name, diff]
	return arrived

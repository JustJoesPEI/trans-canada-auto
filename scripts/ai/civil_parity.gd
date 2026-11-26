class_name CivilParity
extends RefCounted
## Checks the native computer drivers (TcaCivil, TcaRoadUsers, TcaRoute)
## against the GDScript they replace, for tools/native_check.gd, as
## CarParity does for the car physics. While `on`:
##
##   * each civil driver's step (CivilDriving.want_speed) runs both from the
##     same state: the GDScript twin first, then everything others can see
##     put back as it was (the vars others read, the junction claims, the
##     honk count, the random numbers), then the native one. Everything
##     both leave is compared: the speed, every var the driver remembers,
##     each junction's waiting, the claims. The native one's is what stays.
##   * the road users are gathered both ways at the same moment and
##     compared, user by user;
##   * the autopilot's route queries (CarAutopilot: where along the route it
##     is, how far off it, the corner speed, whether the way ahead is clear)
##     are asked of both, and its steering and pedals toward a point
##     (_drive_at) worked out both ways from the same state.
##
## The first difference is kept in `first` (and printed). `-- --car-parity`
## turns it on for any tool, with CarParity.

static var on := OS.get_cmdline_user_args().has("--car-parity")
static var steps := 0
static var differences := 0
static var user_steps := 0
static var user_differences := 0
static var route_calls := 0
static var route_differences := 0
static var pilot_calls := 0
static var pilot_differences := 0
static var first := ""

## What others read, put back before the native step runs (the native twin
## reads some and hands back what it changes).
const SHARED := ["lateral", "holding", "reason", "honk", "stuck_time", "want_reroute", "leader", "leader_gap", "hazard",
		"passes", "pull_overs", "honks", "close_behind", "_speed_mul", "_creep", "_tailed"]
## And what the driver remembers, compared too.
const OWN := ["_curb_at", "_curb_room", "_time", "_scan_t", "_lead_along", "_stop_at", "_stop_reason", "_creep", "_launch",
		"_siren_t", "_siren_close", "_tailed", "_startle_next", "_hazard_t", "_hazard_seen", "_swerve_until", "_person_at",
		"_hold_until", "_hold_reason", "_hold_aside", "_hold_aside_most", "_honk_until", "_honk_next", "_lat_target",
		"_pass_lat", "_behind_stopped", "_tourist_cap", "_speed_mul", "_speed_mul_until", "_approach_cap"]


static func step(c: CivilDriving, route: StreetRoute, along: float, v: float, top: float, delta: float) -> float:
	var shared := {}
	for k: String in SHARED:
		shared[k] = c.get(k)
	var claims: Dictionary = CivilDriving._claims.duplicate(true)
	var honks0 := CivilDriving.all_honks
	var dice := randi()
	# The GDScript twin.
	seed(dice)
	var gd_want := c._want_speed_gd(route, along, v, top, delta)
	var gd := _gd_state(c)
	gd["claims"] = CivilDriving._claims.duplicate(true)
	gd["all_honks"] = CivilDriving.all_honks
	# Back as it was, for the native one.
	for k: String in SHARED:
		c.set(k, shared[k])
	CivilDriving._claims.clear()
	CivilDriving._claims.merge(claims)
	CivilDriving.all_honks = honks0
	seed(dice)
	var nat_want := c._want_speed_native(along, v, top, delta)
	var nat: Dictionary = c._n.call("get_state")
	nat["claims"] = CivilDriving._claims.duplicate(true)
	nat["all_honks"] = CivilDriving.all_honks
	steps += 1
	var diff := ""
	if not CarParity._same(gd_want, nat_want):
		diff = "speed %s against %s" % [gd_want, nat_want]
	else:
		for k: String in gd:
			if not CarParity._same(gd[k], nat.get(k)):
				diff = "%s: %s against %s" % [k, gd[k], nat.get(k)]
				break
	if diff != "":
		differences += 1
		_note("%s at %s after %d steps: %s" % [c.body.name, c.body.global_position, steps, diff])
	# What others read is the native one's.
	for k: String in SHARED:
		c.set(k, nat[k])
	return nat_want


static func _gd_state(c: CivilDriving) -> Dictionary:
	var s := {}
	for k: String in SHARED:
		s[k] = c.get(k)
	for k: String in OWN:
		s[k] = c.get(k)
	s["leader"] = _valid(c.leader)
	s["_lead_user"] = _valid(c._lead_user.node) if c._lead_user != null else null
	s["_pass_node"] = _valid(c._pass_node)
	s["_stop_j"] = str(c._stop_j.get("nid", "")) if c._stop_at < INF else ""
	var stopped := PackedFloat64Array()
	var wait := PackedFloat64Array()
	var go := []
	for j: Dictionary in c._junctions:
		stopped.append(j["stopped"])
		wait.append(j["wait"])
		go.append(j["go"])
	s["j_stopped"] = stopped
	s["j_wait"] = wait
	s["j_go"] = go
	return s


static func _valid(x: Variant) -> Variant:
	return x if is_instance_valid(x) else null


## RoadUsers' own gathering against the native one's, user by user.
static func compare_users(list: Array[RoadUsers.User], nat: Object) -> void:
	user_steps += 1
	var n: int = nat.call("count")
	var diff := ""
	if n != list.size():
		diff = "%d users against %d" % [list.size(), n]
	else:
		for i in n:
			var u := list[i]
			var a: Array = nat.call("user", i)
			var mine := [u.node, u.pos, u.vel, u.fwd, u.speed, u.half_len, u.half_wid, u.person, u.siren, u.civil]
			for k in mine.size():
				if not CarParity._same(mine[k], a[k]):
					diff = "user %d (%s) field %d: %s against %s" % [i, u.node.name if is_instance_valid(u.node) else "?", k, mine[k], a[k]]
					break
			if diff != "":
				break
	if diff != "":
		user_differences += 1
		_note("road users after %d gatherings: %s" % [user_steps, diff])


## One of the autopilot's route queries, asked of both.
static func route_check(what: String, gd: float, nat: float) -> void:
	route_calls += 1
	if not CarParity._same(gd, nat):
		route_differences += 1
		_note("route %s: %s against %s" % [what, gd, nat])


## The autopilot's steering and pedals (CarAutopilot._drive_at), both
## ways from the same state: what each left.
static func pilot_check(gd: Array, nat: Array) -> void:
	pilot_calls += 1
	if not CarParity._same(gd, nat):
		pilot_differences += 1
		_note("drive_at: %s against %s" % [gd, nat])


static func _note(s: String) -> void:
	if first == "":
		first = s
		print("CIVILPARITY first difference: ", s)

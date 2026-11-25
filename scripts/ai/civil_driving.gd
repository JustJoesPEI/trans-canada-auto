class_name CivilDriving
extends RefCounted
## Ordinary road manners for a computer driver: what a CarAutopilot (or a
## RoadFollower, far from anyone) adds on top of following its route when
## civil driving is switched on (CarAutopilot.use_civil_driving). Town
## traffic always drives this way; police on patrol can too.
##
## Each physics step `want_speed` takes the speed the route allows and
## brings it down for what's ahead; `lateral` says how far to drive left
## (+) or right (-) of the route's line. What it does:
##
##   * Looks ahead along its own route for anything in its lane (cars, the
##     followers far off, a person on foot) and keeps a gap that grows with
##     speed, braking smoothly: the Intelligent Driver Model (Treiber), gap
##     standstill_gap + speed * headway, comfortable braking comfort_brake.
##   * At each junction on the route, the rules from JunctionRules: red and
##     amber lights (TrafficSignal.lamp_at) and stop signs stop it at the
##     line (a stop sign for a full stop first; right on red after a full
##     stop when it's clear, as the Island allows); give-way signs, roundabouts,
##     slip roads and side streets onto bigger ones give way. A left turn
##     waits for a gap in the oncoming traffic. Gaps are time gaps
##     (gap_time, about 4.5 s), accepted a little shorter the longer it has
##     waited, so nobody waits forever. A driver going through a give-way
##     puts a claim on the junction for a few seconds that other give-way
##     drivers respect (two at a four-way stop don't go at once).
##   * Never enters a junction it can't get out of: if what's ahead past it
##     is stopped within a car length of the far side, it waits at the line.
##   * Changes lanes: to the left lane of a one-way street (or the right
##     lane of a wide two-way one) before turning, and out round a stopped
##     car that isn't just queueing (parked across the lane, broken down,
##     stopped to chat), when the other lane is clear. Can't get round it
##     in `patience` seconds: `want_reroute`, and the owner turns round.
##   * Pulls to the right and slows, or stops, for a police car with its
##     siren on coming up behind or toward it; waiting at a red light with
##     one behind, it edges out past the line to let it through.
##   * Reacts after a human moment (`reaction`, about half a second): to a
##     car coming at it in its lane (brakes hard and swerves for the curb),
##     a person in the road (stops, honks), a crash ahead (`react_crash`:
##     stops, then carries on), being hit (`react_hit`: brakes, honks,
##     sometimes waits), and pulling away when the way clears.
##   * Honks (`honk`) by temper: held up for no reason, cut off, someone in
##     the road.
##
## `holding` is true while it's stopped on purpose (a light, a sign, a
## queue, giving way, a siren, a hold_for); `reason` says which. A stopped
## car that isn't holding counts `stuck_time`, for whoever owns it.

const SCAN_EVERY := 0.1
## How far ahead other road users are looked at (metres).
const LOOK := 80.0
## Reasons a stopped car is just waiting its turn (the cars behind queue up
## instead of going round).
const WAITING := ["red", "amber", "stop_sign", "yield", "box", "queue", "siren", "crash", "launch"]

enum Turn { STRAIGHT, LEFT, RIGHT }

# --- the driver ---------------------------------------------------------------

## Share of the speed limit it drives at.
var speed_factor := 0.94
## Time gap to the car ahead (s).
var headway := 1.4
## Bumper-to-bumper gap stopped behind a car (m).
var standstill_gap := 2.4
var max_accel := 1.6 ## m/s^2
var comfort_brake := 2.6 ## m/s^2
## Seconds before it reacts to something new.
var reaction := 0.55
## Seconds held up before it goes round, or turns round.
var patience := 14.0
## 0 never honks .. 1 leans on it.
var temper := 0.35
## Time gap (s) it wants in the traffic it crosses or joins.
var gap_time := 4.5
## Brakes for every junction and sign (the tourist in July).
var tourist := false
## Pulls over for sirens (a police car answering a call doesn't).
var pulls_over := true

# --- what it decided (read by the autopilot or the owner) ----------------------

var lateral := 0.0
var holding := false
var reason := ""
var honk := false
var stuck_time := 0.0
var want_reroute := false
## The road user it's following (null if none within LOOK), and the gap.
var leader: Node3D = null
var leader_gap := INF
## What it last reacted to ("oncoming", "person", "siren", "crash", "hit").
var hazard := ""
## How many times it has: passed something, pulled over, honked (for tests).
var passes := 0
var pull_overs := 0
var honks := 0

var body: Node3D
var net: RoadNetwork
var rules: JunctionRules
var half_len := 2.3
var half_wid := 0.9

var _route: StreetRoute = null
var _junctions: Array[Dictionary] = []
var _limit_end := PackedFloat32Array()
var _limit_kmh := PackedFloat32Array()
var _limit_room := PackedFloat32Array()
var _time := 0.0
var _scan_t := 0.0
var _lead_user: RoadUsers.User = null
var _lead_along := 0.0
var _lead_since := 0.0
var _stop_at := INF
var _stop_reason := ""
var _stop_j: Dictionary = {}
var _creep := false
var _launch := 0.0
var _siren_t := -100.0
var _siren_close := false
var _hazard_t := -100.0 # when the current hazard was first seen
var _hazard_seen := ""
var _swerve_until := -100.0
var _person_at := INF # along of a person in the road
var _hold_until := -100.0
var _hold_reason := ""
var _honk_until := -100.0
var _honk_next := 0.0
var _lat_target := 0.0
var _pass_node: Node3D = null
var _pass_lat := 0.0
var _behind_stopped := 0.0
var _tourist_cap := false
var _speed_mul := 1.0
var _speed_mul_until := -100.0
var _approach_cap := INF

## Junctions with a give-way driver going through: nid -> [body, until].
static var _claims := {}


func _init(who: Node3D = null, network: RoadNetwork = null, data: StreetData = null) -> void:
	if who != null:
		attach(who, network, data)


func attach(who: Node3D, network: RoadNetwork, data: StreetData) -> void:
	body = who
	net = network
	rules = JunctionRules.of(network, data)
	if who is Car:
		half_len = float((who as Car).shape.get("length", 4.6)) * 0.5
		half_wid = float((who as Car).shape.get("width", 1.8)) * 0.5
	elif who is RoadFollower:
		half_len = (who as RoadFollower).half_length
		half_wid = (who as RoadFollower).half_width
	_scan_t = randf() * SCAN_EVERY # spread the drivers' scans over the steps


## Stop where it is for a while (chatting, staring at paint): the cars
## behind go round it.
func hold_for(seconds: float, why: String) -> void:
	_hold_until = _time + seconds
	_hold_reason = why


func release_hold() -> void:
	_hold_until = -100.0


## Drive faster (or slower) than usual for a while (speeding off).
func rush(factor: float, seconds: float) -> void:
	_speed_mul = factor
	_speed_mul_until = _time + seconds


## A crash seen ahead: stop for a moment (after the reaction time), then
## carry on.
func react_crash(seconds := 3.0) -> void:
	hazard = "crash"
	_hold_until = maxf(_hold_until, _time + reaction + seconds)
	_hold_reason = "crash"


## Hit by someone: brake, honk, and (by temper) sit there a while.
func react_hit(wait: float) -> void:
	hazard = "hit"
	_honk(0.9)
	_hold_until = maxf(_hold_until, _time + wait)
	_hold_reason = "crash"


## Honk for a moment.
func _honk(seconds: float) -> void:
	if _time < _honk_next:
		return
	_honk_until = _time + seconds
	_honk_next = _time + seconds + 3.0
	honks += 1


# --- the speed ---------------------------------------------------------------------

## The speed to drive at now (m/s), at `along` on `route` going `v`, when
## the route alone would allow `top`.
func want_speed(route: StreetRoute, along: float, v: float, top: float, delta: float) -> float:
	TrafficSignal.advance(delta)
	_time += delta
	if route != _route:
		_prepare(route)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t += SCAN_EVERY
		_scan(route, along, v)
	honk = _time < _honk_until
	if _time > _speed_mul_until:
		_speed_mul = 1.0
	var v0 := minf(top, _limit_at(along) / 3.6 * speed_factor * _speed_mul)
	if _tourist_cap:
		v0 = minf(v0, 5.5)
	v0 = minf(v0, _approach_cap)
	var acc := max_accel * (1.0 - pow(clampf(v / maxf(v0, 0.3), 0.0, 3.0), 4.0))
	if v > v0 + 0.3:
		# Over the speed for the road (a corner coming, a lower limit): slow
		# down to it firmly, not the gentle drift the free-road term gives
		# (a tenth over is under 1 m/s^2, so a car came into its corner
		# still too fast and braked in the turn).
		acc = minf(acc, maxf((v0 - v) / 0.7, -comfort_brake * 1.4))
	if v0 < 0.31:
		acc = minf(acc, -comfort_brake)
	var hold_reason := ""
	# The car ahead, where it is now.
	leader = null
	leader_gap = INF
	if _lead_user != null and is_instance_valid(_lead_user.node):
		var lp := _lead_user.node.global_position
		var la := route.project(Vector2(lp.x, lp.z), _lead_along, 15.0)
		var gap := la - along - half_len - _lead_user.half_len
		var lv := _lead_user.vel.dot(route.dir_at(la))
		leader = _lead_user.node
		leader_gap = gap
		var a := _idm(v, v0, gap, v - lv, standstill_gap)
		if v < 0.5 and gap < standstill_gap + 1.5 and lv < 0.5:
			a = minf(a, -1.0) # stopped close behind: stay put, don't creep
		if a < acc:
			acc = a
			if v < 1.0 and gap < standstill_gap + 3.0:
				hold_reason = "queue" if _lead_waiting() else ""
	# The line it has to stop at.
	if _stop_at < INF:
		var to_line := _stop_at - along - half_len
		var a := _idm(v, v0, to_line, v, 0.5)
		if v < 0.5 and to_line < 3.0:
			a = minf(a, -1.0) # at the line: stay put
		if a < acc:
			acc = a
			if v < 1.0:
				hold_reason = _stop_reason
	elif _creep:
		v0 = minf(v0, 2.0)
	# Someone in the road.
	if _person_at < INF and _time - _hazard_t > reaction:
		var a := _idm(v, v0, _person_at - along - half_len - 0.5, v, 2.5)
		acc = minf(acc, a)
		if v < 1.0:
			hold_reason = "person"
	# A siren: over to the right, slow, or stop if it's right behind.
	if pulls_over and _time - _siren_t < 1.5 and _time - _hazard_t > reaction * 0.5:
		var cap := 0.0 if _siren_close else 3.0
		acc = minf(acc, max_accel * (1.0 - pow(clampf(v / maxf(cap, 0.3), 0.0, 3.0), 2.0)))
		if cap == 0.0:
			acc = minf(acc, -comfort_brake * 1.2 * signf(v))
		if v < 1.0:
			hold_reason = "siren"
	# A car coming at it: stand on the brakes.
	if _time < _swerve_until:
		acc = minf(acc, -7.0)
		if v < 1.0:
			hold_reason = "hazard"
	if _time < _hold_until:
		acc = minf(acc, -comfort_brake * 1.3 if v > 0.5 else -1.0)
		if v < 1.0:
			hold_reason = _hold_reason
	acc = clampf(acc, -9.0, max_accel)
	var want := clampf(v + acc * 0.8, 0.0, maxf(top, 0.0))
	# Pulling away takes a moment.
	if v < 0.4 and want > 0.6:
		_launch += delta
		if _launch < reaction:
			want = 0.0
			hold_reason = "launch"
	elif v > 1.0:
		_launch = 0.0
	holding = hold_reason != ""
	reason = hold_reason
	if v < 0.5 and not holding:
		stuck_time += delta
	else:
		stuck_time = maxf(0.0, stuck_time - delta * 3.0)
	_steer_lateral(route, along, delta)
	return want


## The Intelligent Driver Model's acceleration behind something `gap`
## metres ahead (bumper to bumper) closing at `dv`.
func _idm(v: float, v0: float, gap: float, dv: float, s0: float) -> float:
	var s := maxf(gap, 0.05)
	var ss := s0 + maxf(0.0, v * headway + v * dv / (2.0 * sqrt(max_accel * comfort_brake)))
	var free := 1.0 - pow(clampf(v / maxf(v0, 0.3), 0.0, 3.0), 4.0)
	return max_accel * (free - (ss / s) * (ss / s))


## The car ahead is waiting its turn (at a light, in a queue, giving way),
## not stopped for nothing: by what its driver says, or for one without a
## computer driver (the player), by its being just short of a junction.
func _lead_waiting() -> bool:
	if _lead_user == null:
		return false
	var c := _lead_user.civil
	if c != null:
		return c.holding and c.reason in WAITING
	for j: Dictionary in _junctions:
		var line := float(j["line"])
		if _lead_along > line - 18.0 and _lead_along < float(j["exit"]) + 4.0:
			return true
	return false


## How far from the route's line to aim (a shift to add to the aim point).
func aim_shift(route: StreetRoute, at: float) -> Vector2:
	if absf(lateral) < 0.02:
		return Vector2.ZERO
	var d := route.dir_at(at)
	return Vector2(d.y, -d.x) * lateral


func _steer_lateral(route: StreetRoute, along: float, delta: float) -> void:
	var target := _lat_target
	var rate := 0.9
	if pulls_over and _time - _siren_t < 1.5:
		target = -_room_right(along)
		rate = 1.4
	if _time < _swerve_until:
		target = -_room_right(along) - 1.2 # onto the curb if need be
		rate = 3.0
	lateral = move_toward(lateral, target, rate * delta)


func _room_right(along: float) -> float:
	var i := _limit_index(along)
	return _limit_room[i] if i >= 0 else 1.0


# --- the route ---------------------------------------------------------------------

## Where on the route each junction and change of street is.
func _prepare(route: StreetRoute) -> void:
	_route = route
	_junctions.clear()
	_limit_end = PackedFloat32Array()
	_limit_kmh = PackedFloat32Array()
	_limit_room = PackedFloat32Array()
	_stop_at = INF
	_lead_user = null
	_lat_target = 0.0
	_pass_node = null
	want_reroute = false
	if route == null or route.is_empty():
		return
	var es := route.edges
	var hint := 0.0
	for i in es.size():
		var e := es[i]
		var end := INF
		var nid := ""
		if i < es.size() - 1:
			var f := es[i + 1]
			if e.b == f.a or e.b == f.b:
				nid = e.b
			elif e.a == f.a or e.a == f.b:
				nid = e.a
			if nid != "":
				var np: Vector2 = net.nodes[nid]
				end = route.project(np, hint, e.length + 80.0)
				hint = end
		_limit_end.append(end)
		_limit_kmh.append(JunctionRules.limit_kmh(e))
		var lane := StreetRoute._lane_offset(e, true)
		var room := e.half_width - lane - half_wid - 0.35
		if e.oneway == 0:
			room = minf(room, e.half_width - StreetRoute._lane_offset(e, false) - half_wid - 0.35)
		_limit_room.append(clampf(room, 0.4, 2.6))
		if nid == "" or end == INF:
			continue
		if net.degree(nid) < 3 and not net.signal_nodes.has(nid):
			continue
		var f2 := es[i + 1]
		var k_in := net.incident_index(nid, e, nid == e.a)
		var k_out := net.incident_index(nid, f2, nid == f2.a)
		if k_in < 0 or k_out < 0:
			continue
		var inc_in: RoadNetwork.Incident = net.incidents[nid][k_in]
		var inc_out: RoadNetwork.Incident = net.incidents[nid][k_out]
		var mouth_in := maxf(net.mouth_distance(nid, k_in), e.half_width * 0.8)
		var mouth_out := maxf(net.mouth_distance(nid, k_out), f2.half_width * 0.8)
		var din := -inc_in.dir
		var dout := inc_out.dir
		var side := dout.dot(Vector2(-din.y, din.x)) # + right
		var turn := Turn.STRAIGHT
		if side > 0.35:
			turn = Turn.RIGHT
		elif side < -0.35 or dout.dot(din) < -0.6:
			turn = Turn.LEFT
		var opposite := false
		for o: RoadNetwork.Incident in net.incidents[nid]:
			if o != inc_in and o.dir.dot(inc_in.dir) < -0.7 and (o.edge.oneway == 0 or (o.edge.oneway == 1) != o.at_start):
				opposite = true
		var top_rank := 0
		for o: RoadNetwork.Incident in net.incidents[nid]:
			if o.edge != e:
				top_rank = maxi(top_rank, JunctionRules.rank(o.edge))
		_junctions.append({
			"nid": nid,
			"at": end,
			"line": end - mouth_in - 1.2,
			"exit": end + mouth_out + 0.5,
			"radius": maxf(mouth_in, mouth_out) + 1.0,
			"in_dir": inc_in.dir,
			"phase": TrafficSignal.phase_of(inc_in.dir),
			"control": rules.control(nid, e),
			"turn": turn,
			"opposite": opposite,
			"ring": f2.roundabout and not e.roundabout,
			"major": top_rank >= 4,
			"in_edge": e,
			"out_edge": f2,
			"stopped": 0.0,
			"wait": 0.0,
			"go": false,
		})


func _limit_index(along: float) -> int:
	for i in _limit_end.size():
		if along <= _limit_end[i]:
			return i
	return _limit_end.size() - 1


func _limit_at(along: float) -> float:
	var i := _limit_index(along)
	return _limit_kmh[i] if i >= 0 else 50.0


# --- looking round -------------------------------------------------------------------

func _scan(route: StreetRoute, along: float, v: float) -> void:
	var users := RoadUsers.all(body.get_tree())
	var me := Vector2(body.global_position.x, body.global_position.z)
	var f3 := -body.global_basis.z
	var fwd := Vector2(f3.x, f3.z).normalized()
	var ahead: Array = [] # [along, user, lateral]
	var person_at := INF
	var oncoming := false
	var siren := false
	var siren_close := false
	for u: RoadUsers.User in users:
		if u.node == body:
			continue
		var rel := u.pos - me
		var d2 := rel.length_squared()
		if d2 > LOOK * LOOK:
			continue
		if u.siren and pulls_over:
			var d := sqrt(d2)
			var behind := rel.dot(fwd) < -1.0
			var closing := (u.vel - fwd * v).dot(-rel / maxf(d, 0.1))
			var toward := rel.dot(fwd) > 0.0 and u.fwd.dot(fwd) < -0.3 and d < 60.0
			if (behind and (closing > 0.5 or d < 30.0)) or toward:
				siren = true
				siren_close = siren_close or (behind and d < 28.0) or (toward and d < 25.0)
		if rel.dot(fwd) < -half_len - 2.0:
			continue
		var au := route.project(u.pos, along, LOOK + 10.0)
		if au <= along + 0.3:
			continue
		var p := route.sample(au)
		var dir := route.dir_at(au)
		var lat := (u.pos - p).dot(Vector2(dir.y, -dir.x))
		var against := u.fwd.dot(dir) < -0.5 and u.speed > 1.0
		if against and body is RoadFollower:
			continue # far off, without a body: they get by each other
		var reach := u.half_wid + half_wid + 0.45
		if u.person:
			reach = half_wid + 0.9
		elif against:
			reach = u.half_wid + half_wid - 0.15 # really in our lane, not just passing
		if absf(lat - lateral) > reach:
			continue
		if u.person:
			person_at = minf(person_at, au)
			continue
		# Really coming at us: closing fast, a few seconds off.
		if against and v + u.speed > 4.0 and au - along < maxf(12.0, (v + u.speed) * 3.0):
			oncoming = true
		ahead.append([au, u, lat])
	ahead.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	# Passing something: it doesn't count while we're out round it.
	if _pass_node != null:
		var still := false
		for x: Array in ahead:
			if (x[1] as RoadUsers.User).node == _pass_node:
				still = true
		if not is_instance_valid(_pass_node):
			_end_pass()
		else:
			var pp := Vector2(_pass_node.global_position.x, _pass_node.global_position.z)
			if (pp - me).dot(fwd) < -(half_len * 2.0 + 4.0) or (not still and absf(lateral - _pass_lat) > 1.0 and (pp - me).dot(fwd) < -half_len * 2.0):
				_end_pass()
	var prev := _lead_user
	_lead_user = null
	for x: Array in ahead:
		var u: RoadUsers.User = x[1]
		if u.node == _pass_node:
			continue
		_lead_user = u
		_lead_along = x[0]
		break
	# Cut off: someone new right in front, much closer than we'd follow.
	if _lead_user != null and prev != null and _lead_user.node != prev.node:
		var gap := _lead_along - along - half_len - _lead_user.half_len
		if v > 4.0 and gap < (standstill_gap + v * headway) * 0.45 and randf() < temper * 1.5:
			hazard = "cut_off"
			_honk(0.6)
	# Something new and dangerous: note when it was first seen.
	var now := ""
	if oncoming:
		now = "oncoming"
	elif person_at < INF:
		now = "person"
	elif siren:
		now = "siren"
	if now != _hazard_seen:
		_hazard_seen = now
		_hazard_t = _time
		if now != "":
			hazard = now
	if oncoming and _time - _hazard_t > reaction:
		_swerve_until = _time + 2.0
	_person_at = person_at
	if person_at < INF and _time - _hazard_t > 1.0 + reaction and v < 2.0 and randf() < 0.5 + temper * 0.5:
		_honk(0.5)
	if siren and _time - _siren_t > 3.0:
		pull_overs += 1
	if siren:
		_siren_t = _time
		_siren_close = siren_close
	_check_pass(route, along, v, users, me, fwd)
	_check_junctions(route, along, v, users, siren)
	_turn_lanes(along)


## What it's doing, for debugging.
func debug_text() -> String:
	var s := "%s/%s" % [reason, hazard]
	if _stop_at < INF and not _stop_j.is_empty():
		var j := _stop_j
		s += " at %s (%s, rule %d, phase %d lamp %d, turn %d, stop line %.0f)" % [j["nid"], (j["in_edge"] as RoadNetwork.RoadEdge).name, j["control"], j["phase"], TrafficSignal.lamp_at(j["nid"], j["phase"]), j["turn"], j["line"]]
	if _lead_user != null:
		s += " behind %s" % _lead_user.node.name
	return s


func _end_pass() -> void:
	_pass_node = null
	_lat_target = 0.0


## Held up behind something that's stopped for no good reason: round it
## when the other lane's clear, or give up and turn round.
func _check_pass(route: StreetRoute, along: float, v: float, users: Array[RoadUsers.User], me: Vector2, fwd: Vector2) -> void:
	if _pass_node != null:
		return
	var u := _lead_user
	if u == null or u.speed > 0.8 or _lead_waiting() or v > 3.0:
		_behind_stopped = 0.0
		return
	var gap := _lead_along - along - half_len - u.half_len
	if gap > 25.0:
		_behind_stopped = 0.0
		return
	_behind_stopped += SCAN_EVERY
	if _behind_stopped > patience * 0.4 and randf() < temper * 0.15:
		_honk(0.7)
	if _behind_stopped > patience:
		want_reroute = true
	if _behind_stopped < 1.5 + patience * 0.1:
		return
	if body is RoadFollower:
		# Far from anyone, without a body: it just gets by.
		_pass_node = u.node
		_pass_lat = 0.0
		passes += 1
		_behind_stopped = 0.0
		return
	# Out round it: past its far side by a margin.
	var lead_lat := 0.0
	var p := route.sample(_lead_along)
	var dir := route.dir_at(_lead_along)
	lead_lat = (u.pos - p).dot(Vector2(dir.y, -dir.x))
	var shift := lead_lat + u.half_wid + half_wid + 0.7
	if shift > 4.5:
		return
	# The way out there has to be clear: nobody coming, nobody alongside.
	var from := along - 6.0
	var to := _lead_along + u.half_len + 25.0
	for o: RoadUsers.User in users:
		if o.node == body or o.node == u.node:
			continue
		if (o.pos - me).length_squared() > 140.0 * 140.0:
			continue
		var ao := route.project(o.pos, maxf(0.0, along - 10.0), 150.0)
		var po := route.sample(ao)
		var d2 := route.dir_at(ao)
		var lo := (o.pos - po).dot(Vector2(d2.y, -d2.x))
		if lo < 0.8 or lo > shift + 3.5:
			continue
		var coming := o.vel.dot(d2) < -0.5
		if ao > from and ao < to:
			return
		if coming and ao > along and ao < to + o.speed * 6.0:
			return
	# And no wall or pole there (parked cars, buildings).
	var space := body.get_world_3d().direct_space_state
	var left := Vector2(fwd.y, -fwd.x)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.SOLID
	var y := body.global_position.y + 0.7
	var a2 := me + left * shift
	var b2 := route.sample(_lead_along + u.half_len + 6.0) + left * shift
	q.from = Vector3(a2.x, y, a2.y)
	q.to = Vector3(b2.x, y, b2.y)
	if not space.intersect_ray(q).is_empty():
		return
	_pass_node = u.node
	_pass_lat = shift
	_lat_target = shift
	passes += 1
	_behind_stopped = 0.0


## The left lane of a one-way street before a left turn, the right lane of
## a wide street before a right one.
func _turn_lanes(along: float) -> void:
	if _pass_node != null:
		return
	_lat_target = 0.0
	for j: Dictionary in _junctions:
		var to_line := float(j["line"]) - along
		if to_line < -2.0:
			continue
		if to_line > 70.0:
			break
		var e: RoadNetwork.RoadEdge = j["in_edge"]
		var turn: int = j["turn"]
		if e.oneway != 0 and e.lanes >= 2:
			if turn == Turn.LEFT:
				_lat_target = minf(e.half_width * 0.5, e.half_width - half_wid - 0.4)
			elif turn == Turn.RIGHT:
				_lat_target = -minf(e.half_width * 0.5, e.half_width - half_wid - 0.4)
		elif e.oneway == 0 and e.lanes >= 4 and turn == Turn.RIGHT:
			_lat_target = -(e.half_width / maxf(1.0, e.lanes / 2.0)) * 0.9
		break


# --- junctions -------------------------------------------------------------------------

func _check_junctions(route: StreetRoute, along: float, v: float, users: Array[RoadUsers.User], siren: bool) -> void:
	_stop_at = INF
	_stop_reason = ""
	_creep = false
	_tourist_cap = false
	_approach_cap = INF
	var look := maxf(60.0, v * v / (2.0 * comfort_brake) + 30.0)
	var front := along + half_len
	var checked := 0
	for j: Dictionary in _junctions:
		var line := float(j["line"])
		if front > float(j["exit"]):
			continue
		var to_line := line - front
		if to_line > look or checked >= 2:
			break
		checked += 1
		var nid: String = j["nid"]
		if tourist and to_line < 22.0 and to_line > -1.0:
			_tourist_cap = true
		if to_line < -0.3:
			# Over the line: through it, whatever happens.
			if not bool(j["go"]):
				j["go"] = true
			continue
		var stop := ""
		var control: int = j["control"]
		match control:
			JunctionRules.Rule.SIGNAL:
				var lamp := TrafficSignal.lamp_at(nid, j["phase"])
				if lamp == 0 and int(j["turn"]) == Turn.RIGHT and float(j["stopped"]) >= 0.9 and _gap_clear(j, users, false):
					pass # right on red, after a full stop, when it's clear (legal on the Island)
				elif lamp == 0:
					stop = "red"
					if int(j["turn"]) == Turn.RIGHT and v < 0.4 and to_line < 3.5:
						j["stopped"] = float(j["stopped"]) + SCAN_EVERY
				elif lamp == 1 and to_line > v * v / (2.0 * 3.2) + 0.5 and not bool(j["go"]):
					stop = "amber"
				elif int(j["turn"]) == Turn.LEFT and bool(j["opposite"]) and not _gap_clear(j, users, true):
					stop = "yield"
			JunctionRules.Rule.STOP:
				if float(j["stopped"]) < 0.9:
					stop = "stop_sign"
					if v < 0.4 and to_line < 3.5:
						j["stopped"] = float(j["stopped"]) + SCAN_EVERY
				elif not _gap_clear(j, users, false):
					stop = "yield"
			JunctionRules.Rule.YIELD:
				# Up to the line slowly enough to stop if it's not clear.
				if to_line < 30.0:
					_approach_cap = minf(_approach_cap, 4.0 + to_line * 0.35)
				if not _gap_clear(j, users, false):
					stop = "yield"
			_:
				if int(j["turn"]) == Turn.LEFT and bool(j["opposite"]) and not _gap_clear(j, users, true):
					stop = "yield"
		if stop == "" and not _room_after(j, along):
			stop = "box"
		if stop != "" and siren and v < 1.5 and stop in ["red", "amber", "stop_sign", "box"]:
			# A siren behind: edge out past the line, to the right, so it
			# can get by (not on into the junction if anything's coming).
			if stop != "box" and _gap_clear(j, users, false, 1.5):
				_creep = true
				_stop_at = line + 5.0
				_stop_reason = "siren"
				return
		if stop != "":
			if v < 0.5 and to_line < 4.0:
				j["wait"] = float(j["wait"]) + SCAN_EVERY
			j["go"] = false
			_stop_at = line
			_stop_reason = stop
			_stop_j = j
			return
		if not bool(j["go"]) and to_line < 12.0:
			j["go"] = true
			if control == JunctionRules.Rule.STOP or control == JunctionRules.Rule.YIELD or int(j["turn"]) == Turn.LEFT:
				_claims[nid] = [body, _time + 3.5 + float(j["radius"]) / maxf(v, 3.0)]


## Is the traffic clear enough to go: nobody moving in the junction, and
## everyone coming at it more than the wanted time gap off. `oncoming_only`
## for a left turn on a green or on the main road: only the traffic coming
## the other way counts.
func _gap_clear(j: Dictionary, users: Array[RoadUsers.User], oncoming_only: bool, need_scale := 1.0) -> bool:
	var nid: String = j["nid"]
	var claim: Variant = _claims.get(nid)
	if claim != null:
		var who: Variant = claim[0]
		if who != body and is_instance_valid(who) and float(claim[1]) > _time:
			return false
	var need := gap_time * need_scale
	if bool(j["major"]):
		need += 0.5
	if oncoming_only:
		need *= 0.85
	need *= lerpf(1.0, 0.55, clampf(float(j["wait"]) / (patience * 1.5), 0.0, 1.0))
	var np: Vector2 = net.nodes[nid]
	var r := float(j["radius"])
	var in_dir: Vector2 = j["in_dir"]
	for u: RoadUsers.User in users:
		if u.node == body:
			continue
		var rel := u.pos - np
		var d := rel.length()
		if d > 110.0:
			continue
		if d > r * 0.6 and rel.dot(in_dir) > 0.75 * d:
			continue # on our way in, behind or beside us
		if u.person:
			if d < r:
				return false
			continue
		var spd := u.vel.length()
		if d < r + 1.0:
			# Moving in the junction, other than straight on ahead of us.
			if spd > 0.8 and u.vel.dot(-in_dir) < 0.7 * spd:
				return false
			continue
		if oncoming_only and rel.dot(-in_dir) < 0.6 * d:
			continue
		var closing := -u.vel.dot(rel / d)
		if closing < 0.8:
			continue
		if (d - r) / closing < need:
			return false
	return true


## Room past the junction for the whole car: what's ahead beyond it isn't
## stopped within a car length of the far side.
func _room_after(j: Dictionary, along: float) -> bool:
	if _lead_user == null:
		return true
	var exit := float(j["exit"])
	if _lead_along < float(j["line"]):
		return true
	var back := _lead_along - _lead_user.half_len
	if back < exit + half_len * 2.0 + 1.0 and _lead_user.speed < 2.0:
		return false
	return true

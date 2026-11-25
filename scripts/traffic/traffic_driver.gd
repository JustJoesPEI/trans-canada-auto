class_name TrafficDriver
extends RefCounted
## One car of town traffic and the person driving it. It's either a real
## Car with a CarAutopilot (near a player) or a RoadFollower moving along the
## streets without physics (further off); the TrafficManager swaps it
## between the two. Either way the same CivilDriving (its road manners and
## personality) drives it, to the same destination.

enum State { DRIVE, ARRIVED, OUT, GONE }

var id := 0
var model_id := "civique"
var model_index := 0 ## in StreetProps.PARKED_MODELS (-1 for a truck)
## A truck: only ever a real vehicle near the player (no far version).
var truck := false
## A bus (TrafficBuses): which route (-1 for none), which junction of it
## it's heading for, and where on this leg its stops are.
var bus_route := -1
var bus_leg := 0
var bus_stops := PackedFloat32Array()
var bus_next_stop := 0
var _bus_route_obj: StreetRoute = null
var _left_stop := true
var _stop_moves := 0
var _stop_orig := -1.0
var paint := Color.WHITE
var character := ""
var civil: CivilDriving
var rng := RandomNumberGenerator.new()
var dest: Dictionary = {}
var dest3 := Vector3.ZERO
## Turned into its driveway (a car near a player does, at the end).
var turned_in := false
## How far above its follower's height a far car is drawn (the street
## surface, a bridge deck), and when to look again.
var lift := 0.0
var lift_target := 0.0
var lift_check := 0.0
var state := State.DRIVE
var follower: RoadFollower = null
var car: Car = null
var pilot: CarAutopilot = null
var bystander: TrafficBystander = null
## Seconds since it last moved 2 m (for "nobody stuck"), not counting
## waiting at a red light or in the queue for one (lights always change),
## or a bus at a stop or a chatter chatting (they go on by themselves).
var stuck_for := 0.0
## Seconds waiting at a light (or in the queue for one) since it last moved.
var light_wait := 0.0
var upside_down := 0.0
var arrived_at := -1.0
var age := 0.0
var reroutes := 0
## A rollback sent for a dead car (TrafficTows).
var tow := false
## Turned off for a big police chase (TrafficHeat).
var cleared_off := false
## Its driver ran off and left it in the street.
var abandoned := false
## Waiting to get out and look at the paint once stopped.
var getting_out := false
## A chatter stops this far along its route (or -1).
var chat_at := -1.0
var _moved_at := Vector2.INF


## The node it is now (the car or the follower).
func node() -> Node3D:
	if car != null and is_instance_valid(car):
		return car
	if follower != null and is_instance_valid(follower):
		return follower
	return null


func position() -> Vector3:
	var n := node()
	return n.global_position if n != null else Vector3.INF


func route() -> StreetRoute:
	if car != null and pilot != null:
		return pilot.route
	if follower != null:
		return follower.route
	return null


func along() -> float:
	if car != null and pilot != null:
		return pilot.along
	if follower != null:
		return follower.along
	return 0.0


func on_arrived() -> void:
	if state == State.DRIVE:
		state = State.ARRIVED
		arrived_at = age


func tick(delta: float) -> void:
	age += delta
	var n := node()
	if n == null:
		state = State.GONE
		return
	var p := Vector2(n.global_position.x, n.global_position.z)
	if _moved_at == Vector2.INF or p.distance_to(_moved_at) > 2.0:
		_moved_at = p
		stuck_for = 0.0
		light_wait = 0.0
	elif state == State.DRIVE and civil.holding and civil.reason in ["red", "amber", "queue", "bus_stop", "chat"]:
		light_wait += delta
	elif state == State.DRIVE:
		stuck_for += delta
	else:
		stuck_for = 0.0
	if follower != null:
		if follower.moving and follower.route != null:
			# (The route's limit falls to 0 at its end; a follower rolls the
			# last metres in at a walking pace.)
			var top := maxf(minf(follower.speed_kmh / 3.6, follower.route.limit_at(follower.along + follower.speed * 0.3)), 1.2)
			follower.max_speed = civil.want_speed(follower.route, follower.along, follower.speed, top, delta)
		civil.want_reroute = false
		return
	if car == null:
		return
	# A stopped traffic car can be got into (and that's a crime); a moving
	# one can't.
	car.owner_id = "traffic" if absf(car.speed) > 1.0 and state != State.OUT else ""
	upside_down = upside_down + delta if car.global_basis.y.y < 0.35 else 0.0
	if bus_route >= 0 and pilot != null and pilot.route != null and state == State.DRIVE:
		if pilot.route != _bus_route_obj:
			# A new leg (or planned again): its stops, from here on.
			_bus_route_obj = pilot.route
			bus_stops = TrafficBuses.stops_on(pilot.route)
			bus_next_stop = 0
			while bus_next_stop < bus_stops.size() and bus_stops[bus_next_stop] < pilot.along + 30.0:
				bus_next_stop += 1
		var stop := bus_stops[bus_next_stop] if bus_next_stop < bus_stops.size() else INF
		if stop < INF and pilot.along >= stop - TrafficBuses.PULL_AHEAD and civil.to_curb < 0.0:
			if civil.near_junction(stop, 30.0) and stop + 30.0 < pilot.route.length - 60.0:
				bus_stops[bus_next_stop] += 30.0 # not at a junction: a little further on
			elif civil.near_junction(stop, 30.0) and _stop_orig >= 0.0:
				# Looked for a free stretch of curb and ran out of street: back
				# to where it was, beside the parked cars.
				bus_stops[bus_next_stop] = _stop_orig
				_stop_moves = 99
			elif civil.near_junction(stop, 30.0):
				bus_next_stop += 1 # no room before the end of the leg: no stop
			else:
				# Coming up to the stop: in to the curb while still rolling
				# (a stopped bus can't move sideways), right in where nobody's
				# parked.
				var clear := TrafficBuses.stop_clear(car, pilot.route, stop - 6.0, civil.net)
				if not clear and _stop_moves < 4 and stop + 25.0 < pilot.route.length - 60.0:
					# Cars parked along the curb there: a stretch further on.
					if _stop_moves == 0:
						_stop_orig = stop
					bus_stops[bus_next_stop] += 25.0
					_stop_moves += 1
				else:
					_stop_moves = 0
					_stop_orig = -1.0
					civil.curb_keep = 0.0 if clear else StreetRoute.PARKING_LANE - 0.25
					civil.to_curb = TrafficBuses.CURB_GAP
		elif stop < INF and pilot.along >= stop:
			bus_next_stop += 1
			civil.hold_for(rng.randf_range(TrafficBuses.DWELL.x, TrafficBuses.DWELL.y), "bus_stop", true, -TrafficBuses.CURB_GAP)
			civil.hazard = "bus_stop"
			_left_stop = false
		elif civil.to_curb >= 0.0 and not civil.hold_active() and not _left_stop and bus_next_stop > 0:
			# Done at the stop: back out into the lane (as it rolls:
			# CivilDriving eases out with speed).
			_left_stop = true
			civil.to_curb = -1.0
			civil.curb_keep = 0.0
	if state == State.DRIVE and chat_at >= 0.0 and pilot != null and pilot.along > chat_at:
		var e := _edge_here()
		if e != null and e.highway in ["residential", "unclassified", "tertiary"]:
			civil.hold_for(rng.randf_range(12.0, 25.0), "chat")
			civil.hazard = "chat"
		chat_at = -1.0


func _edge_here() -> RoadNetwork.RoadEdge:
	var n := node()
	if n == null or civil == null or civil.net == null:
		return null
	var hit := civil.net.nearest_on_streets(Vector2(n.global_position.x, n.global_position.z), 15.0)
	return hit["edge"] if not hit.is_empty() else null

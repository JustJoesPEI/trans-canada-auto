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
var model_index := 0 ## in StreetProps.PARKED_MODELS
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
## waiting at a red light or in the queue for one (lights always change).
var stuck_for := 0.0
## Seconds waiting at a light (or in the queue for one) since it last moved.
var light_wait := 0.0
var upside_down := 0.0
var arrived_at := -1.0
var age := 0.0
var reroutes := 0
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
	elif state == State.DRIVE and civil.holding and civil.reason in ["red", "amber", "queue"]:
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

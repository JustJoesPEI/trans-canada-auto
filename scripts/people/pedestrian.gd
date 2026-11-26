class_name Pedestrian
extends Node3D
## Someone walking round town (PedestrianManager): a person (HumanoidModel,
## one draw call, a shared mesh per look) going somewhere real on foot.
##
## They walk along the sidewalks (RoadNetwork.Level.WALK, the middle of the
## walk), from junction to junction. At each junction they pick the way
## that takes them nearer where they're going (a driveway, lot or shop
## door from TrafficDestinations), with a bit of chance, by turning the
## corner or crossing a street; before stepping off the curb they wait for
## a gap in the traffic (and while they're in the road the drivers see
## them: group RoadUsers.PEOPLE_GROUP). At the place they walk in off the
## sidewalk, crossing to its side of the street first if they have to,
## and once nobody can see them they're gone.
##
## On the way they keep right of people coming the other way, stop to
## chat with someone now and then, check their phone, and think the odd
## thought over their head (PedestrianLines, scheduled by the manager so
## only a few show at once). They jump out of the way of a car coming at
## them, run from paint landing near them (and say so when it hits them:
## the body on Layers.CHARACTERS takes paint, cars pass through it), put
## their hands up when a marker's pointed at them, and say sorry when
## walked into. One in a while is after a ride (RideFares): they wait at
## the curb waving, get in the player's passenger seat (PassengerSeat) and
## get out where they're going.

enum State { WALK, WAIT_CROSS, PAUSE, CHAT, DODGE, FLEE, HAIL, BOARD, RIDE, ENTER, INSIDE }

## How many looks there are (each a shared, cached mesh).
const LOOKS := 32
## [kind, how common].
const KINDS := [["stroller", 4.0], ["commuter", 4.0], ["tourist", 1.5], ["senior", 2.0], ["jogger", 0.8], ["teen", 2.0]]
## Walking speed by kind (m/s): [slowest, quickest].
const SPEEDS := {"stroller": [1.05, 1.3], "commuter": [1.4, 1.65], "tourist": [0.95, 1.2],
	"senior": [0.75, 0.95], "jogger": [2.5, 3.1], "teen": [1.15, 1.45]}
const RUN_SPEED := 4.0
const DODGE_SPEED := 4.6
## Waypoints along a sidewalk this far apart (m), so bends are followed.
const STEP := 5.0
## The longest anyone waits at a curb for a gap (s): the drivers stop for
## people in the road, so after this they just go.
const CROSS_PATIENCE := 14.0
## A thought or a line shows for this long (s).
const SAY_TIME := 3.6
## How far off they're drawn (m).
const DRAW_DISTANCE := 160.0

var manager: PedestrianManager
var net: RoadNetwork
var rng := RandomNumberGenerator.new()
var kind := "stroller"
var look := 0
var walk_speed := 1.3
var state := State.WALK
## For RoadUsers (people in the road): metres per second, flat.
var velocity := Vector3.ZERO
var model: HumanoidModel
## Where they're going: a TrafficDestinations place, or empty.
var goal: Dictionary = {}
## Seconds in the current state.
var state_t := 0.0
## Seconds until they may think out loud again (the manager counts down).
var think_wait := 0.0
## Saying or thinking something right now.
var saying := false
## Ready to stop and chat (not in a hurry, not just chatted).
var chat_wait := 0.0
var chat_partner: Pedestrian = null
## The ride they're after or on (RideFares sets it).
var fare: Dictionary = {}

var _label: Label3D
var _label_t := 0.0
var _body: StaticBody3D
var _path: Array[Vector2] = []
var _cross: Array[bool] = [] ## _cross[i]: getting to _path[i] crosses a street
var _pi := 0
var _pos := Vector2.ZERO
var _y := 0.0
var _y_goal := 0.0
var _ray_t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _heading := Vector2(0.0, -1.0)
var _lat := 0.0
var _lat_goal := 0.0
var _avoid_t := 0.0
var _danger_t := 0.0
## The junction the path ends at ("" if it ends at the goal), the incident
## of its street there and the side of that street they're on.
var _end_node := ""
var _end_inc := -1
var _end_side := 1
var _goal_edge: RoadNetwork.RoadEdge = null
var _goal_along := 0.0
var _goal_side := 1
var _move_dir := Vector2.ZERO
var _speed_now := 0.0
var _pause_in := 0.0
var _pause_len := 0.0
var _hands := 0.0
var _flee_from := Vector2.ZERO
var _crossing := false
## Jumped clear of a car out in the road: crossing (watched for by traffic,
## allowed in the road) until back off it.
var _back_off_road := false
var _resume_state := State.WALK
## Seconds with nowhere to walk (the manager takes them away).
var lost_t := 0.0


func setup(m: PedestrianManager, seed_value: int) -> void:
	manager = m
	net = m.net
	rng.seed = seed_value
	look = rng.randi() % LOOKS
	kind = _pick_kind()
	var sp: Array = SPEEDS[kind]
	walk_speed = rng.randf_range(float(sp[0]), float(sp[1]))
	think_wait = rng.randf_range(3.0, 20.0)
	chat_wait = rng.randf_range(10.0, 40.0)
	_pause_in = rng.randf_range(15.0, 60.0)
	model = make_model(look)
	add_child(model)
	_label = Label3D.new()
	_label.font_size = 34
	_label.pixel_size = 0.006
	_label.outline_size = 8
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, model.height + 0.42, 0.0)
	_label.visible = false
	_label.visibility_range_end = 60.0
	_label.visibility_range_end_margin = 4.0
	add_child(_label)
	# Something for paint to hit (cars and people pass through it).
	_body = StaticBody3D.new()
	_body.collision_layer = Layers.CHARACTERS
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = model.height
	cs.shape = cap
	cs.position = Vector3(0.0, model.height * 0.5, 0.0)
	_body.add_child(cs)
	add_child(_body)
	_ray.collision_mask = Layers.GROUND


## A person of look `i`: the same look always has the same body (one
## cached mesh per look).
static func make_model(i: int) -> HumanoidModel:
	var r := RandomNumberGenerator.new()
	r.seed = 90210 + i * 7919
	var m := HumanoidModel.new()
	m.set_appearance(HumanoidModel.random_appearance(r))
	m.mesh_cache_key = "pedestrian_%d" % i
	m.draw_distance = DRAW_DISTANCE
	return m


func _pick_kind() -> String:
	var total := 0.0
	for k: Array in KINDS:
		total += float(k[1])
	var r := rng.randf() * total
	for k: Array in KINDS:
		r -= float(k[1])
		if r <= 0.0:
			return str(k[0])
	return "stroller"


## Puts them on the sidewalk of e, `along` it on `side`, walking toward b
## (or a), on their way to `place`.
func start(e: RoadNetwork.RoadEdge, along: float, side: int, to_b: bool, place: Dictionary) -> void:
	set_goal(place)
	_pos = walk_point(e, along, side)
	_y = manager.ground_y(_pos, -INF)
	_y_goal = _y
	_plan_leg(e, side, along, to_b)
	if _path.size() > 0:
		var d := _path[0] - _pos
		if d.length() > 0.1:
			_heading = d.normalized()
	_place_node()
	reset_physics_interpolation()


func set_goal(place: Dictionary) -> void:
	goal = place
	_goal_edge = null
	if place.is_empty():
		return
	var at: Vector2 = place["street"]
	var hit := net.nearest_on_streets(at, 30.0)
	if hit.is_empty():
		return
	var e: RoadNetwork.RoadEdge = hit["edge"]
	_goal_edge = e
	_goal_along = float(hit["along"])
	var inside: Vector2 = place.get("inside", at)
	_goal_side = 1 if (inside - at).dot(RoadNetwork._perp(hit["dir"])) >= 0.0 else -1


func position2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


## Busy with something that isn't just walking about (a ride, a fright).
func busy() -> bool:
	return state in [State.DODGE, State.FLEE, State.HAIL, State.BOARD, State.RIDE] or not fare.is_empty()


# --- talking -------------------------------------------------------------------------------

## Shows `text` over their head for `secs`: a thought (pale blue) or said
## out loud (white).
func say(text: String, secs := SAY_TIME, out_loud := true) -> void:
	_label.text = text
	_label.modulate = Color(1.0, 1.0, 1.0) if out_loud else Color(0.74, 0.86, 1.0)
	_label.font_size = 36 if out_loud else 34
	_label.visible = true
	_label_t = secs
	saying = true


func think(text: String) -> void:
	say(text, SAY_TIME, false)


func hush() -> void:
	_label.visible = false
	_label_t = 0.0
	saying = false


## The hail sign over their head, seen from further off.
func show_hail(text: String) -> void:
	say(text, 1.0e9, true)
	_label.modulate = Color(1.0, 0.9, 0.35)
	_label.visibility_range_end = 110.0


# --- reactions -----------------------------------------------------------------------------

## A paintball hit them (PaintShots: anything with take_paint_hit).
func take_paint_hit(_value: int, _shooter: Node, point: Vector3) -> void:
	if state in [State.RIDE, State.BOARD]:
		return
	say(PedestrianLines.pick(rng, PedestrianLines.PAINTED))
	flee(point, false)


## Something frightening at p: run away from it along the sidewalk.
func flee(p: Vector3, shout := true) -> void:
	if state in [State.RIDE, State.BOARD, State.FLEE]:
		return
	manager.fares.lost(self)
	_end_crossing()
	if shout:
		say(PedestrianLines.pick(rng, PedestrianLines.FLEE))
	_flee_from = Vector2(p.x, p.z)
	var away := position2() - _flee_from
	if away.length() < 0.1:
		away = _heading
	_replan(away.normalized())
	_set_state(State.FLEE)


## A marker pointed at them: hands up a moment.
func aimed_at() -> void:
	if state in [State.RIDE, State.BOARD, State.FLEE, State.DODGE] or _hands > 0.0:
		return
	say(PedestrianLines.pick(rng, PedestrianLines.AIMED_AT))
	_hands = 2.2
	_pause(2.2)


## The player walked into them: step aside, say sorry.
func bumped(by: Vector2) -> void:
	if state != State.WALK and state != State.PAUSE:
		return
	var rel := position2() - by
	var right := RoadNetwork._perp(_heading)
	_lat_goal = clampf(_lat + (0.7 if rel.dot(right) >= 0.0 else -0.7), -0.9, 0.9)
	if not saying:
		say(PedestrianLines.pick(rng, PedestrianLines.BUMPED), 2.0)


# --- rides --------------------------------------------------------------------------------

## In a car (RideFares): no paint hits, no walking.
func set_riding(on: bool) -> void:
	_body.collision_layer = 0 if on else Layers.CHARACTERS
	_end_crossing()
	if on:
		_set_state(State.RIDE)
		velocity = Vector3.ZERO


## Out of the car at xf: to their place (`go_in`), or off along the sidewalk.
func get_out_at(xf: Transform3D, go_in: bool) -> void:
	set_riding(false)
	global_transform = Transform3D(Basis.IDENTITY, xf.origin)
	_pos = Vector2(xf.origin.x, xf.origin.z)
	_y = xf.origin.y
	_y_goal = _y
	_lat = 0.0
	_lat_goal = 0.0
	var f := -xf.basis.z
	_heading = Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.1 else _heading
	model.position = Vector3.ZERO
	model.rotation = Vector3.ZERO
	if go_in and not goal.is_empty():
		_path = [goal.get("inside", goal["street"])]
		_cross = [false]
		_pi = 0
		_set_state(State.ENTER)
	else:
		goal = {}
		_goal_edge = null
		_replan(_heading)
		_set_state(State.WALK)
	_place_node()
	reset_physics_interpolation()


## Back to walking (a hail given up).
func resume_walking() -> void:
	fare = {}
	hush()
	_label.visibility_range_end = 60.0
	_replan(_heading)
	_set_state(State.WALK)


## Stop at the curb and wave for a ride, facing `face`.
func hail(text: String) -> void:
	_end_crossing()
	show_hail(text)
	_set_state(State.HAIL)


func board() -> void:
	hush()
	_label.visibility_range_end = 60.0
	_set_state(State.BOARD)


## Nowhere to walk (off the sidewalks).
func lost() -> bool:
	return state == State.WALK and _path.is_empty()


## In a crossing or waiting at the curb for one.
func in_road() -> bool:
	return _crossing or state == State.WAIT_CROSS


# --- every step ----------------------------------------------------------------------------

func _set_state(s: State) -> void:
	state = s
	state_t = 0.0


func _physics_process(delta: float) -> void:
	if manager == null:
		return
	state_t += delta
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0:
			hush()
	if _hands > 0.0:
		_hands -= delta
	chat_wait -= delta
	if state == State.RIDE:
		velocity = Vector3.ZERO
		return
	_danger_t -= delta
	if _danger_t <= 0.0 and state != State.BOARD and state != State.INSIDE:
		_danger_t = 0.1
		_watch_cars()
	_speed_now = 0.0
	match state:
		State.WALK:
			if _back_off_road and not _on_carriageway():
				_back_off_road = false
				_end_crossing()
			_walk(delta, _hurry() * walk_speed)
			_maybe_pause(delta)
		State.WAIT_CROSS:
			_face_dir(_path[_pi] - _pos if _pi < _path.size() else _heading, delta)
			if state_t > CROSS_PATIENCE or _clear_to_cross():
				_begin_crossing()
				_set_state(State.WALK)
		State.PAUSE:
			if state_t > _pause_len:
				_set_state(_resume_state)
		State.CHAT:
			if is_instance_valid(chat_partner):
				_face_dir(chat_partner.position2() - _pos, delta)
			if state_t > _pause_len or not is_instance_valid(chat_partner):
				chat_partner = null
				chat_wait = rng.randf_range(40.0, 90.0)
				_set_state(State.WALK)
		State.DODGE:
			if state_t < 0.55:
				_pos += _move_dir * DODGE_SPEED * delta
				_speed_now = DODGE_SPEED
			elif state_t > 1.6:
				_replan(_heading)
				_set_state(State.WALK)
				if _on_carriageway():
					_back_off_road = true
					_begin_crossing()
		State.FLEE:
			_walk(delta, RUN_SPEED if state_t > 0.3 else 0.0)
			if state_t > 7.0:
				_set_state(State.WALK)
		State.HAIL:
			_face_dir(fare.get("face", _heading), delta)
		State.BOARD:
			var car: Node3D = fare.get("car")
			if car == null or not is_instance_valid(car):
				manager.fares.lost(self)
			else:
				var door := PassengerSeat.door_point(car)
				var to := Vector2(door.x, door.z) - _pos
				if to.length() < 0.5 or state_t > 6.0:
					manager.fares.board(self)
				else:
					_pos += to.normalized() * minf(to.length(), 1.8 * delta)
					_speed_now = 1.8
					_move_dir = to.normalized()
		State.ENTER:
			_walk(delta, walk_speed)
		State.INSIDE:
			pass
	if state == State.RIDE:
		return # just got in (RideFares.board seated them): not on foot now
	_avoid(delta)
	_animate(delta)
	_place_node()


func _hurry() -> float:
	return 1.15 if _crossing else 1.0


func _maybe_pause(delta: float) -> void:
	if kind == "jogger" or _crossing:
		return
	_pause_in -= delta
	if _pause_in > 0.0:
		return
	_pause_in = rng.randf_range(25.0, 70.0) * (0.5 if kind == "tourist" else 1.0)
	_pause(rng.randf_range(2.5, 6.0))


func _pause(secs: float) -> void:
	if state != State.PAUSE:
		_resume_state = state if state in [State.WALK, State.ENTER] else State.WALK
	_pause_len = secs
	_set_state(State.PAUSE)


## Stop and chat with `other` for a while (the manager pairs them up).
func chat_with(other: Pedestrian, opener: bool, lines: Array) -> void:
	chat_partner = other
	_pause_len = rng.randf_range(5.0, 9.0) if opener else other._pause_len
	_set_state(State.CHAT)
	if opener:
		say(str(lines[0]), 3.0)
	else:
		# The reply, a moment later.
		get_tree().create_timer(2.6, false, true).timeout.connect(func() -> void:
			if is_instance_valid(self) and state == State.CHAT:
				say(str(lines[1]), 3.0))


## Moves along the path at `speed`.
func _walk(delta: float, speed: float) -> void:
	if _path.is_empty():
		# Off the sidewalks (nowhere to walk): look again now and then.
		lost_t += delta
		if lost_t > 1.0:
			lost_t = 0.0
			_replan(_heading)
		return
	if _pi >= _path.size():
		_path_done()
		return
	var target := _path[_pi]
	var to := target - _pos
	var step := speed * delta
	_speed_now = speed
	if to.length() > 0.001:
		_move_dir = to.normalized()
	if to.length() <= step:
		_pos = target
		_pi += 1
		if _crossing and (_pi >= _cross.size() or not _cross[_pi]):
			_end_crossing()
		if _pi >= _path.size():
			_path_done()
		elif _cross[_pi] and not _crossing and state != State.FLEE:
			_set_state(State.WAIT_CROSS)
		elif _cross[_pi] and not _crossing:
			_begin_crossing()
	else:
		_pos += _move_dir * step


func _begin_crossing() -> void:
	_crossing = true
	add_to_group(RoadUsers.PEOPLE_GROUP)


## Out on the part of a street cars drive on.
func _on_carriageway() -> bool:
	var hit := net.nearest_on_streets(_pos, 20.0)
	if hit.is_empty():
		return false
	var e: RoadNetwork.RoadEdge = hit["edge"]
	return not e.minor and float(hit["dist"]) < e.half_width - 0.3


func _end_crossing() -> void:
	_crossing = false
	_back_off_road = false
	if is_in_group(RoadUsers.PEOPLE_GROUP):
		remove_from_group(RoadUsers.PEOPLE_GROUP)


## Nothing coming that would get to the crossing before they're over it.
func _clear_to_cross() -> bool:
	if _pi >= _path.size() or _pi == 0:
		return true
	var a := _path[_pi - 1]
	var b := _path[_pi]
	var t_cross := a.distance_to(b) / (walk_speed * 1.15) + 1.0
	for u: RoadUsers.User in RoadUsers.near(get_tree(), (a + b) * 0.5, a.distance_to(b) * 0.5 + 60.0):
		if u.person or u.node == null:
			continue
		var q := Geometry2D.get_closest_point_to_segment(u.pos, a, b)
		var rel := q - u.pos
		var d := rel.length()
		if d > 60.0:
			continue
		if d < u.half_len + 1.5 and u.speed > 0.5:
			return false # right there and moving
		var v := maxf(u.vel.dot(rel / maxf(d, 0.01)), 0.0)
		if v < 0.8:
			continue # stopped, or going away
		if d / v < t_cross + 1.5:
			return false
	return true


## At the end of the path: at a junction (choose a way on) or at the goal.
func _path_done() -> void:
	_end_crossing()
	if state == State.FLEE:
		_replan(_heading)
		if _path.is_empty():
			_set_state(State.PAUSE)
		return
	if state == State.ENTER:
		_set_state(State.INSIDE)
		visible = true
		return
	if _end_node == "":
		if not goal.is_empty():
			_path = [goal.get("inside", goal["street"])]
			_cross = [false]
			_pi = 0
			_set_state(State.ENTER)
		else:
			_replan(-_heading)
		return
	_at_node(_end_node, _end_inc, _end_side)


## Dodges cars coming at them.
func _watch_cars() -> void:
	if state == State.DODGE or state == State.RIDE:
		return
	var me := position2()
	for u: RoadUsers.User in RoadUsers.near(get_tree(), me, 90.0):
		if u.person or u.speed < 2.5:
			continue
		var rel := me - u.pos
		if rel.length_squared() > pow(6.0 + u.speed * 1.4, 2.0):
			continue
		var ahead := rel.dot(u.fwd)
		if ahead < -u.half_len * 0.5 or ahead > u.half_len + u.speed * 1.1 + 1.0:
			continue
		var right := Vector2(-u.fwd.y, u.fwd.x)
		var lat := rel.dot(right)
		if absf(lat) > u.half_wid + 0.9:
			continue
		# In its way: jump clear, to whichever side is nearer.
		manager.fares.lost(self)
		_end_crossing()
		_move_dir = right * (1.0 if lat >= 0.0 else -1.0)
		_heading = -u.fwd
		say(PedestrianLines.pick(rng, PedestrianLines.DODGE), 2.6)
		_hands = 1.0
		_set_state(State.DODGE)
		manager.dodged(self, u.node)
		return


## Keeps right of people coming the other way (Canada: keep right).
func _avoid(delta: float) -> void:
	_avoid_t -= delta
	if _avoid_t <= 0.0 and state == State.WALK and not _crossing:
		_avoid_t = 0.25
		_lat_goal = 0.0
		for o: Pedestrian in manager.near(self, 3.0):
			if o.state == State.RIDE:
				continue
			var rel := o.position2() - position2()
			var ahead := rel.dot(_heading)
			if ahead > 0.3 and ahead < 3.0 and absf(rel.dot(RoadNetwork._perp(_heading))) < 0.9:
				var right := RoadNetwork._perp(_heading)
				_lat_goal = 0.55 if o._heading.dot(_heading) < 0.0 or rel.dot(right) < 0.0 else -0.55
				break
	_lat = move_toward(_lat, _lat_goal, delta * 0.8)


func _face_dir(d: Vector2, delta: float) -> void:
	if d.length() < 0.01:
		return
	_heading = _heading.slerp(d.normalized(), clampf(delta * 5.0, 0.0, 1.0)).normalized()


func _animate(delta: float) -> void:
	if _speed_now > 0.05 and state != State.DODGE and _move_dir != Vector2.ZERO:
		_heading = _heading.slerp(_move_dir, clampf(delta * 7.0, 0.0, 1.0)).normalized()
	var v := _move_dir * _speed_now
	velocity = Vector3(v.x, 0.0, v.y)
	model.set_motion(_speed_now)
	var hands := 0.0
	if _hands > 0.0:
		hands = 0.9
	elif state == State.HAIL:
		hands = 0.75 if fmod(state_t, 1.4) < 0.9 else 0.25 # waving
	elif state == State.CHAT and saying:
		hands = 0.15
	model.hands_up = hands


func _place_node() -> void:
	_ray_t -= get_physics_process_delta_time()
	if _ray_t <= 0.0:
		_ray_t = 0.25 + rng.randf() * 0.1
		_y_goal = manager.ground_y(_pos, _y)
	_y = move_toward(_y, _y_goal, get_physics_process_delta_time() * 2.5)
	var off := RoadNetwork._perp(_heading) * _lat
	global_position = Vector3(_pos.x + off.x, _y, _pos.y + off.y)
	global_basis = Basis(Vector3.UP, atan2(-_heading.x, -_heading.y))


# --- finding the way -----------------------------------------------------------------------

## Where the middle of the sidewalk is, `along` edge e on `side`.
func walk_point(e: RoadNetwork.RoadEdge, along: float, side: int) -> Vector2:
	var s: Array = RoadNetwork.sample(e.points, along)
	return (s[0] as Vector2) + RoadNetwork._perp(s[1]) * float(side) * net.offset_for(e, RoadNetwork.Level.WALK, side)


## A sidewalk anyone would walk along.
static func walkable(e: RoadNetwork.RoadEdge, side: int) -> bool:
	return not e.is_highway() and not e.minor and e.walk(side) >= 0.8 and e.length >= 6.0


## A street anyone would walk across (not a highway or a wide road).
static func crossable(e: RoadNetwork.RoadEdge) -> bool:
	return not e.is_highway() and e.half_width <= 9.0 and not e.roundabout


## How far from junction nid along its incident k the sidewalk ends (clear
## of the streets that meet it).
func _trim(nid: String, k: int) -> float:
	var list: Array = net.incidents.get(nid, [])
	var inc: RoadNetwork.Incident = list[k]
	if list.size() == 1:
		return minf(3.0, inc.edge.length * 0.45)
	var t := 0.0
	for j in list.size():
		if j == k:
			continue
		var o: RoadNetwork.RoadEdge = (list[j] as RoadNetwork.Incident).edge
		t = maxf(t, o.half_width + maxf(o.walk(1), o.walk(-1)))
	return clampf(t + 0.8, 1.0, inc.edge.length * 0.45)


## Where the sidewalk of incident k on (its street's) side `side` ends at nid.
func _end_point(nid: String, k: int, side: int) -> Vector2:
	var inc: RoadNetwork.Incident = net.incidents[nid][k]
	var t := _trim(nid, k)
	return walk_point(inc.edge, t if inc.at_start else inc.edge.length - t, side)


## The corner between incidents k and k+1, if it's a sensible place to
## walk through; else INF.
func _corner(nid: String, k: int) -> Vector2:
	var list: Array = net.incidents[nid]
	if list.size() < 2:
		return Vector2.INF
	var c := net.corner_right(nid, k, RoadNetwork.Level.WALK)
	var v := c - (net.nodes[nid] as Vector2)
	var a: RoadNetwork.Incident = list[k]
	var b: RoadNetwork.Incident = list[(k + 1) % list.size()]
	if v.length() > 30.0 or v.dot(RoadNetwork._perp(a.dir)) < 0.3 or v.dot(RoadNetwork._perp(b.dir)) > -0.3:
		return Vector2.INF
	return c


func _add(p: Vector2, crossing := false) -> void:
	if p == Vector2.INF:
		return
	var last := _path[_path.size() - 1] if _path.size() > 0 else _pos
	if last.distance_to(p) < 0.4:
		return
	_path.append(p)
	_cross.append(crossing)


## Plans walking along e on `side` from `from_along` to the far end (b if
## to_b), stopping at the goal if it's on this street.
func _plan_leg(e: RoadNetwork.RoadEdge, side: int, from_along: float, to_b: bool) -> void:
	_path = []
	_cross = []
	_pi = 0
	_append_leg(e, side, from_along, to_b)


func _append_leg(e: RoadNetwork.RoadEdge, side: int, from_along: float, to_b: bool) -> void:
	var far := e.b if to_b else e.a
	var far_k := net.incident_index(far, e, not to_b)
	var to_along := e.length if to_b else 0.0
	if far_k >= 0:
		var t := _trim(far, far_k)
		to_along = e.length - t if to_b else t
	_end_node = far if far_k >= 0 else ""
	_end_inc = far_k
	_end_side = side
	# The goal on this street, ahead: stop there and go in.
	var stop_at := INF
	if e == _goal_edge and not goal.is_empty():
		if (to_b and _goal_along >= from_along - 0.5) or (not to_b and _goal_along <= from_along + 0.5):
			stop_at = clampf(_goal_along, minf(from_along, to_along), maxf(from_along, to_along))
	var end := stop_at if stop_at != INF else to_along
	var span := absf(end - from_along)
	var n := maxi(1, ceili(span / STEP))
	for i in range(1, n + 1):
		_add(walk_point(e, lerpf(from_along, end, float(i) / n), side))
	if stop_at != INF:
		_end_node = ""
		if side != _goal_side:
			# The place is across the street: cross here (when it's clear).
			_add(walk_point(e, end, -side), true)
	elif far_k < 0:
		_end_node = ""


## At junction nid, arrived along incident i on side s of its street:
## choose the way on.
func _at_node(nid: String, i: int, s: int) -> void:
	var list: Array = net.incidents.get(nid, [])
	var n := list.size()
	_path = []
	_cross = []
	_pi = 0
	if n == 0 or i < 0 or i >= n:
		_replan(-_heading)
		return
	var came: RoadNetwork.Incident = list[i]
	var R := func(k: int) -> int: return RoadNetwork._right_side(list[(k % n + n) % n])
	if n == 1:
		# A dead end: back the other side if there's a sidewalk, else back.
		if walkable(came.edge, -s) and crossable(came.edge):
			_add(_end_point(nid, i, -s), true)
			_append_leg(came.edge, -s, _along_at(nid, i), came.at_start)
		else:
			_append_leg(came.edge, s, _along_at(nid, i), came.at_start)
		return
	var k0 := i if s == int(R.call(i)) else (i - 1 + n) % n
	var here := net.nodes[nid] as Vector2
	var to_goal := Vector2.ZERO
	if not goal.is_empty():
		to_goal = ((goal["street"] as Vector2) - here).normalized()
	var best: Array = []
	var best_score := -INF
	# [sector, crossing incident or -1]
	var options := [[k0, -1], [(k0 + 1) % n, (k0 + 1) % n], [(k0 - 1 + n) % n, k0]]
	for o: Array in options:
		var sector: int = o[0]
		var cross: int = o[1]
		if cross >= 0 and not crossable((list[cross] as RoadNetwork.Incident).edge):
			continue
		for exit: Array in [[sector, int(R.call(sector))], [(sector + 1) % n, -int(R.call(sector + 1))]]:
			var k: int = exit[0]
			var side: int = exit[1]
			var inc: RoadNetwork.Incident = list[k]
			if not walkable(inc.edge, side):
				continue
			var score := inc.dir.dot(to_goal) + rng.randf() * 0.8
			if cross >= 0:
				score -= 0.25
			if inc.edge == came.edge:
				score -= 2.0 # back the way they came
			if score > best_score:
				best_score = score
				best = [sector, cross, k, side]
	if best.is_empty():
		_append_leg(came.edge, s, _along_at(nid, i), came.at_start)
		return
	var sector: int = best[0]
	var cross: int = best[1]
	var k: int = best[2]
	var side: int = best[3]
	if cross >= 0:
		var from_side := int(R.call(cross)) if k0 == cross else -int(R.call(cross))
		_add(_corner(nid, k0))
		_add(_end_point(nid, cross, from_side))
		_add(_end_point(nid, cross, -from_side), true)
	_add(_corner(nid, sector))
	var inc: RoadNetwork.Incident = list[k]
	_add(_end_point(nid, k, side))
	_append_leg(inc.edge, side, _along_at(nid, k), inc.at_start)
	if _path.size() > 0 and _cross[0] and state == State.WALK:
		_set_state(State.WAIT_CROSS)


## Distance along incident k's street where its sidewalk ends at nid.
func _along_at(nid: String, k: int) -> float:
	var inc: RoadNetwork.Incident = net.incidents[nid][k]
	var t := _trim(nid, k)
	return t if inc.at_start else inc.edge.length - t


## Back onto the nearest sidewalk and on along it, the way `prefer` points.
func _replan(prefer: Vector2) -> void:
	var hit := net.nearest_on_streets(_pos, 40.0)
	_path = []
	_cross = []
	_pi = 0
	if hit.is_empty():
		_end_node = ""
		return
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var dir: Vector2 = hit["dir"]
	var side := 1 if (_pos - (hit["pos"] as Vector2)).dot(RoadNetwork._perp(dir)) >= 0.0 else -1
	if not walkable(e, side):
		if walkable(e, -side):
			side = -side
		else:
			_end_node = ""
			return
	_append_leg(e, side, float(hit["along"]), prefer.dot(dir) >= 0.0)

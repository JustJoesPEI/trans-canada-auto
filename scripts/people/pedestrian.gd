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
##
## Some are off to catch a bus (TransitStops, TrafficBuses): they walk to a
## stop, wait at the curb looking up the street for it, walk to its door
## when it pulls in, and are gone; others get off it and walk away. At a
## junction with traffic lights they wait for the walk (the lights for
## the street alongside them), so they gather on the corner and cross
## together, the odd teenager or commuter going on red when it's clear.
## Something happening in the street (StreetEvents: a crash, a tow) makes
## them slow down and look, or stop and watch. Some walk
## in twos (`leader`, `companion`): one leads, the other keeps beside them.
## And someone who saw the player paint someone remembers them for a while.

enum State { WALK, WAIT_CROSS, PAUSE, CHAT, DODGE, FLEE, HAIL, BOARD, RIDE, ENTER, INSIDE, WAIT_BUS, TO_BUS, WATCH }

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
## Between one line of a chat and the next (s).
const CHAT_GAP := 2.6
## How far off they're drawn (m).
const DRAW_DISTANCE := 160.0
## How likely each kind is to cross against the light when it's clear.
const RULE_BENDING := {"teen": 0.5, "jogger": 0.55, "commuter": 0.3, "stroller": 0.08, "tourist": 0.03, "senior": 0.0}
## Seconds a red light has to be clear for before a rule bender goes.
const BEND_AFTER := 4.0
## Waited longer than a whole cycle of the lights (s): anyone goes when
## it's clear.
const LIGHT_PATIENCE := 50.0
## Waiting for a bus this long at most (s), then they walk.
const BUS_PATIENCE := Vector2(150.0, 300.0)
## Side by side, walking in twos (m).
const PAIR_GAP := 0.7

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
## The bus stop they're going to or waiting at (TransitStops) and which
## side of the street, or -1.
var bus_stop := -1
var bus_side := 0
## Got on a bus: out of sight inside it (the manager takes them away).
var on_bus := false
## Walking in twos: the one they keep beside (null if leading or alone),
## and the one keeping beside them.
var leader: Pedestrian = null
var companion: Pedestrian = null
## Crosses on red when it's clear (by kind).
var rule_bender := false
## Saw the player paint someone at this time (the manager's clock), and
## whether they've said so since.
var saw_crime_at := -INF
var recognised := false
## The StreetEvents they've noticed.
var noticed := {}

var _label: Label3D
var _label_t := 0.0
var _body: AnimatableBody3D
var _path: Array[Vector2] = []
var _cross: Array[bool] = [] ## _cross[i]: getting to _path[i] crosses a street
var _pi := 0
var _pos := Vector2.ZERO
var _y := 0.0
var _y_goal := 0.0
var _ray_t := 0.0
## Countdowns to looking again: for a gap to cross in, and for being back
## off the road (each a search of the streets or the traffic, not needed
## every step).
var _cross_t := 0.0
var _road_t := 0.0
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
## Crossings at traffic lights on the path: path index -> [junction, phase
## of the street crossed, the point].
var _signal_at := {}
var _light_t := 0.0
var _bus: Node3D = null
var _bus_stopped := false
var _bus_wait := 0.0
var _look_at := Vector2.ZERO
var _watch_len := 0.0
var _slow_t := 0.0
var _away_t := 0.0
var _away := Vector2.ZERO
var _phone_t := 0.0
## Seconds with nowhere to walk (the manager takes them away).
var lost_t := 0.0


func setup(m: PedestrianManager, seed_value: int) -> void:
	manager = m
	net = m.net
	rng.seed = seed_value
	look = rng.randi() % LOOKS
	kind = _pick_kind()
	rule_bender = rng.randf() < float(RULE_BENDING.get(kind, 0.1))
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
	# Longer lines wrap onto two rows rather than one long strip.
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 620.0
	_label.position = Vector3(0.0, model.height + 0.42, 0.0)
	_label.visible = false
	_label.visibility_range_end = 60.0
	_label.visibility_range_end_margin = 4.0
	add_child(_label)
	# Something for paint to hit (cars and people pass through it). A body
	# that's moved (a static one dragged about every step is the physics
	# engine's slow case), and only in the world while they're out on foot.
	_body = AnimatableBody3D.new()
	_body.sync_to_physics = false
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
	var tree := get_tree() if is_inside_tree() else null
	var hour := TrafficDensity.current_hour(tree) if tree != null else 14.0
	var month := TrafficDensity.current_month(tree) if tree != null else 11
	var total := 0.0
	for k: Array in KINDS:
		total += float(k[1]) * kind_share(str(k[0]), hour, month)
	var r := rng.randf() * total
	for k: Array in KINDS:
		r -= float(k[1]) * kind_share(str(k[0]), hour, month)
		if r <= 0.0:
			return str(k[0])
	return "stroller"


## How much more (or less) of a kind is about at an hour of the day (and,
## for tourists, a month): commuters at the rush hours, joggers early and
## after work, teenagers after school, seniors in the day, tourists in the
## summer.
static func kind_share(k: String, hour: float, month: int) -> float:
	var night := hour < 6.0 or hour >= 22.0
	match k:
		"commuter":
			if (hour >= 7.0 and hour < 9.5) or (hour >= 16.0 and hour < 18.5):
				return 2.4
			if hour >= 11.5 and hour < 13.5:
				return 1.3
			return 0.35 if night else 0.8
		"jogger":
			if hour >= 6.0 and hour < 8.5:
				return 2.5
			if hour >= 17.0 and hour < 20.0:
				return 1.8
			return 0.2 if night else 0.6
		"teen":
			if hour >= 15.0 and hour < 22.0:
				return 2.0
			if hour >= 8.0 and hour < 9.0:
				return 1.3
			return 0.15 if night else 0.6
		"senior":
			if hour >= 9.0 and hour < 16.0:
				return 1.4
			return 0.1 if night else 0.5
		"tourist":
			var season := 3.0 if month in [7, 8] else (1.5 if month in [6, 9] else 0.5)
			return season * (1.3 if hour >= 10.0 and hour < 18.0 else 0.35)
		"stroller":
			return 1.2 if hour >= 10.0 and hour < 20.0 else (0.3 if night else 0.6)
	return 1.0


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
	return state in [State.DODGE, State.FLEE, State.HAIL, State.BOARD, State.RIDE, State.TO_BUS] or not fare.is_empty()


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


# --- the bus ------------------------------------------------------------------------------

## Off to stop si (TransitStops) to wait on `side` at `at`: the place
## they're walking to (for start or set_goal).
func bus_place(si: int, side: int, at: Vector2) -> Dictionary:
	bus_stop = si
	bus_side = side
	var st: Dictionary = TransitStops.current.stops[si]
	return {"street": st["p"], "inside": at, "kind": "bus_stop"}


## Put at stop si on `side`, already waiting there (placed out of sight).
func start_waiting(si: int, side: int, at: Vector2) -> void:
	goal = bus_place(si, side, at)
	_pos = at
	_y = manager.ground_y(_pos, -INF)
	_y_goal = _y
	_heading = _bus_face()
	_wait_for_bus(rng.randf_range(0.3, 1.0))
	_place_node()
	reset_physics_interpolation()


## At the stop: wait (some of the full patience left, if they've waited).
func _wait_for_bus(share := 1.0) -> void:
	_end_crossing()
	_path = []
	_bus_wait = rng.randf_range(BUS_PATIENCE.x, BUS_PATIENCE.y) * share
	_set_state(State.WAIT_BUS)


## Waiting at their stop now.
func waiting_for_bus(si: int, side: int) -> bool:
	return state == State.WAIT_BUS and bus_stop == si and bus_side == side


## The bus has pulled in: to its door.
func board_bus(bus: Node3D) -> void:
	if state == State.TO_BUS:
		return
	_bus = bus
	_bus_stopped = false
	hush()
	_set_state(State.TO_BUS)


## Facing up the street for the bus, a little toward the road.
func _bus_face() -> Vector2:
	var ts := TransitStops.current
	if ts == null or bus_stop < 0 or bus_stop >= ts.stops.size():
		return _heading
	var st: Dictionary = ts.stops[bus_stop]
	var d: Vector2 = (st["dir"] as Vector2) * float(bus_side) # the way the bus goes on this side
	var road := -RoadNetwork._perp(st["dir"]) * float(bus_side)
	return (-d * 0.75 + road * 0.65).normalized()


func _get_on() -> void:
	on_bus = true
	visible = false
	_body.collision_layer = 0
	_end_crossing()
	hush()
	_set_state(State.INSIDE)


func _missed_bus() -> void:
	_bus = null
	if rng.randf() < 0.4:
		say(PedestrianLines.pick(rng, PedestrianLines.BUS_MISSED), 2.5)
	_wait_for_bus(0.5)


# --- walking in twos ------------------------------------------------------------------------

## Walks beside `l` from now on (the manager pairs them as they're placed).
func follow(l: Pedestrian) -> void:
	leader = l
	l.companion = self
	l.walk_speed = minf(l.walk_speed, walk_speed)
	_pos = l._pos - l._heading * 0.2 + RoadNetwork._perp(l._heading) * PAIR_GAP
	_y = l._y
	_y_goal = l._y_goal
	_heading = l._heading
	_place_node()
	reset_physics_interpolation()


## On alone (the one they were with is gone, or ran).
func _part() -> void:
	if is_instance_valid(leader) and leader.companion == self:
		leader.companion = null
	leader = null
	_end_crossing()
	_replan(_heading)
	_set_state(State.WALK)


## Keeping beside the leader. False when they're on their own business
## (dodging, getting on the bus) or have parted.
func _follow(delta: float) -> bool:
	if not is_instance_valid(leader) or leader.state in [State.DODGE, State.FLEE, State.RIDE, State.HAIL, State.BOARD]:
		_part()
		return false
	if state in [State.DODGE, State.FLEE, State.TO_BUS, State.INSIDE]:
		return false
	if leader.state == State.TO_BUS and leader._bus != null:
		board_bus(leader._bus)
		return false
	if leader.state == State.INSIDE:
		if leader.on_bus:
			_part()
			return false
		_set_state(State.INSIDE) # in at the door with them
		return true
	# Walking when they walk, standing (a pause) when they stop.
	var want := State.WALK if leader.state in [State.WALK, State.ENTER] else State.PAUSE
	if state != want:
		_set_state(want)
	# Beside them on the side away from the road (across a street, beside
	# them as they go).
	_away_t -= delta
	if _away_t <= 0.0:
		_away_t = 0.5
		var hit := net.nearest_on_streets(leader._pos, 25.0)
		_away = (leader._pos - (hit["pos"] as Vector2)).normalized() if not hit.is_empty() else RoadNetwork._perp(leader._heading)
	var off := RoadNetwork._perp(leader._heading) * PAIR_GAP * signf(RoadNetwork._perp(leader._heading).dot(_away) + 0.001)
	var target := leader._pos + off - leader._heading * 0.15
	var to := target - _pos
	var d := to.length()
	_speed_now = 0.0
	if d > 0.12:
		var sp := minf(leader._speed_now + clampf(d - 0.1, 0.0, 1.0) * 1.4, RUN_SPEED)
		sp = maxf(sp, 0.5)
		_move_dir = to / d
		_pos += _move_dir * minf(d, sp * delta)
		_speed_now = sp
	elif leader._speed_now < 0.1:
		# Standing with them: facing the way they face (or them, chatting).
		var look := leader._heading
		if leader.state == State.CHAT and is_instance_valid(leader.chat_partner):
			look = leader.chat_partner.position2() - _pos
		_face_dir(look, delta)
	if leader._crossing and not _crossing:
		_begin_crossing()
	elif not leader._crossing and _crossing:
		_end_crossing()
	return true


# --- seeing things --------------------------------------------------------------------------

## Something in the street (StreetEvents): slow down and look, or stop
## and watch; `line` is said if not empty.
func notice(e: Dictionary, line: String) -> void:
	noticed[e["id"]] = true
	var at: Vector2 = e["pos"]
	if state in [State.WALK, State.PAUSE, State.WAIT_BUS] and kind not in ["jogger", "commuter"] and rng.randf() < 0.55:
		watch(at, rng.randf_range(4.0, 10.0))
	elif state == State.WALK:
		_slow_t = rng.randf_range(2.0, 4.0)
		_look_at = at
	if line != "":
		say(line, 3.0)


## Stop and look at `at` for `secs`.
func watch(at: Vector2, secs: float) -> void:
	if state == State.WATCH:
		return
	_resume_state = state if state in [State.WALK, State.WAIT_BUS] else State.WALK
	_look_at = at
	_watch_len = secs
	_set_state(State.WATCH)


## On the phone (calling something in) for `secs`: standing still.
func on_phone(secs: float) -> void:
	_phone_t = secs
	if state == State.WALK:
		_pause(secs)


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
	return state == State.WALK and _path.is_empty() and leader == null


## In a crossing or waiting at the curb for one.
func in_road() -> bool:
	return _crossing or state == State.WAIT_CROSS


# --- every step ----------------------------------------------------------------------------

func _set_state(s: State) -> void:
	if s == State.WAIT_CROSS and state != State.WAIT_CROSS:
		# Waiting on a corner with others: not all on the same spot.
		_lat_goal = rng.randf_range(-0.45, 0.45)
		_light_t = 0.0
	state = s
	state_t = 0.0
	if s == State.WAIT_CROSS:
		_cross_t = 0.0 # look straight away
	# Nothing for paint to hit while they're indoors or in a car: out of
	# the physics world altogether.
	var out := s != State.INSIDE and s != State.RIDE
	if _body != null and (_body.process_mode != Node.PROCESS_MODE_DISABLED) != out:
		_body.process_mode = Node.PROCESS_MODE_INHERIT if out else Node.PROCESS_MODE_DISABLED


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
	if _phone_t > 0.0:
		_phone_t -= delta
	if _slow_t > 0.0:
		_slow_t -= delta
	chat_wait -= delta
	if state == State.RIDE or on_bus:
		velocity = Vector3.ZERO
		return
	_danger_t -= delta
	if _danger_t <= 0.0 and state != State.BOARD and state != State.INSIDE:
		_danger_t = 0.1
		_watch_cars()
	_speed_now = 0.0
	if leader != null and _follow(delta):
		_animate(delta)
		_place_node()
		return
	match state:
		State.WALK:
			if _back_off_road:
				_road_t -= delta
				if _road_t <= 0.0:
					_road_t = 0.1
					if not _on_carriageway():
						_back_off_road = false
						_end_crossing()
			_walk(delta, _hurry() * walk_speed * (0.55 if _slow_t > 0.0 else 1.0))
			_maybe_pause(delta)
		State.WAIT_CROSS:
			_face_dir(_path[_pi] - _pos if _pi < _path.size() else _heading, delta)
			var sig: Array = _signal_at.get(_pi, [])
			if not sig.is_empty() and _pi < _path.size() and (sig[2] as Vector2) == _path[_pi]:
				# Lights: on the walk, or (some) on red when it's clear.
				_light_t -= delta
				if _light_t <= 0.0:
					_light_t = 0.25
					if _walk_light(sig) or (rule_bender and state_t > BEND_AFTER and _clear_to_cross()) \
							or (state_t > LIGHT_PATIENCE and _clear_to_cross()):
						_begin_crossing()
						_set_state(State.WALK)
			elif state_t > CROSS_PATIENCE or _gap_now(delta):
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
			elif state_t > 1.6 and bus_stop >= 0 and not _on_carriageway():
				# Jumped clear while waiting for the bus: back to waiting.
				_wait_for_bus(0.6)
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
		State.WAIT_BUS:
			_face_dir(_bus_face(), delta)
			_bus_wait -= delta
			if _bus_wait <= 0.0:
				# Never came: off on foot.
				bus_stop = -1
				set_goal(manager.dests.pick(rng, position2(), 60.0, 500.0))
				resume_walking()
				if rng.randf() < 0.35:
					think(PedestrianLines.pick(rng, PedestrianLines.BUS_GAVE_UP))
		State.TO_BUS:
			var bus := _bus as Car
			if bus != null and is_instance_valid(bus) and absf(bus.speed) < 0.5:
				_bus_stopped = true
			if bus == null or not is_instance_valid(bus) or (_bus_stopped and absf(bus.speed) > 1.5) or state_t > 30.0:
				_missed_bus()
			else:
				var door := TrafficBuses.door(bus)
				var to := Vector2(door.x, door.z) - _pos
				if to.length() < 0.5:
					_get_on()
					return
				var sp := walk_speed * 1.15
				_move_dir = to.normalized()
				_pos += _move_dir * minf(to.length(), sp * delta)
				_speed_now = sp
		State.WATCH:
			_face_dir(_look_at - _pos, delta)
			if state_t > _watch_len:
				_set_state(_resume_state)
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
	# Long enough for every line, each a moment after the last.
	_pause_len = maxf(rng.randf_range(5.0, 9.0), lines.size() * CHAT_GAP + 2.0) if opener else other._pause_len
	_set_state(State.CHAT)
	# The opener says the even lines, the other the odd ones.
	for i in range(0 if opener else 1, lines.size(), 2):
		var text := str(lines[i])
		if i == 0:
			say(text, 3.0)
			continue
		get_tree().create_timer(i * CHAT_GAP, false, true).timeout.connect(func() -> void:
			if is_instance_valid(self) and state == State.CHAT:
				say(text, 3.0))


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


## A gap in the traffic to cross in (looked for ten times a second).
func _gap_now(delta: float) -> bool:
	_cross_t -= delta
	if _cross_t > 0.0:
		return false
	_cross_t = 0.1
	return _clear_to_cross()


## The walk at lights `sig` ([junction, phase of the street crossed,
## point]): the street alongside on green with time left to get over, the
## one crossed on red, and no car coming that they'd step out in front of.
func _walk_light(sig: Array) -> bool:
	var nid: String = sig[0]
	var crossed: int = sig[1]
	var alongside := 1 - crossed
	if TrafficSignal.lamp_at(nid, crossed) != 0 or TrafficSignal.lamp_at(nid, alongside) != 2:
		return false
	var a := _path[_pi - 1] if _pi > 0 else _pos
	var t_cross := a.distance_to(_path[_pi]) / (walk_speed * 1.15)
	if TrafficSignal.time_to_change(nid, alongside) < t_cross * 0.6:
		return false
	# And nothing turning in across the crossing that would have to brake
	# hard for them (the car behind it mightn't). Cars going straight on
	# alongside it, on their green, don't cross it.
	var b := _path[_pi]
	var along_dir := (b - a).normalized()
	for u: RoadUsers.User in RoadUsers.near(get_tree(), (a + b) * 0.5, a.distance_to(b) * 0.5 + 40.0):
		if u.person or u.node == null or absf(u.speed) < 1.0:
			continue
		if absf(u.fwd.dot(along_dir)) > 0.75:
			continue # alongside
		var q := Geometry2D.get_closest_point_to_segment(u.pos, a, b)
		var rel := q - u.pos
		var d := rel.length()
		if d < u.half_len + 1.5:
			return false # in it now
		# About to get there (a car turning in, one running the amber). One
		# further back on the street crossed is coming up to its red: it'll
		# stop.
		var v := maxf(u.vel.dot(rel / maxf(d, 0.01)), 0.0)
		if v > 0.8 and d < 25.0 and d / v < 3.5:
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
		if bus_stop >= 0:
			_wait_for_bus()
			return
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
	var at_stop := state in [State.WAIT_BUS, State.TO_BUS]
	for u: RoadUsers.User in RoadUsers.near(get_tree(), me, 90.0):
		if u.person or u.speed < 2.5:
			continue
		if at_stop and u.node is Car and (u.node as Car).model_id == TrafficBuses.MODEL:
			continue # the bus pulling in to the curb they're waiting at
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
		# In its way: jump clear, to whichever side is nearer. (Turning on
		# the spot: the step aside from keeping right goes into where they
		# stand, or it'd swap sides with the turn.)
		manager.fares.lost(self)
		_end_crossing()
		_pos += RoadNetwork._perp(_heading) * _lat
		_lat = 0.0
		_lat_goal = 0.0
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
	var angle := 0.0
	if _speed_now > 0.05 and state != State.DODGE and _move_dir != Vector2.ZERO:
		var want := _move_dir
		if _slow_t > 0.0 and state == State.WALK:
			# Walking on slowly, turned toward whatever it is (not past
			# looking over a shoulder).
			var look := (_look_at - _pos).normalized()
			if look.dot(_move_dir) > -0.3:
				want = (_move_dir + look * 0.9).normalized()
		_heading = _heading.slerp(want, clampf(delta * 7.0, 0.0, 1.0)).normalized()
		var left := -RoadNetwork._perp(_heading)
		angle = atan2(_move_dir.dot(left), _move_dir.dot(_heading))
	var v := _move_dir * _speed_now
	velocity = Vector3(v.x, 0.0, v.y)
	model.set_motion(_speed_now, 0.0, 0.0, angle)
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
	var xf := Transform3D(Basis(Vector3.UP, atan2(-_heading.x, -_heading.y)), Vector3(_pos.x + off.x, _y, _pos.y + off.y))
	if xf != global_transform:
		# (Not when standing still: moving the node moves its body too.)
		global_transform = xf


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
	_signal_at.clear()
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
	_signal_at.clear()
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
		if net.signal_nodes.has(nid) and not _path.is_empty() and _cross[_path.size() - 1]:
			# Lights here: they'll wait for the walk.
			_signal_at[_path.size() - 1] = [nid, TrafficSignal.phase_of((list[cross] as RoadNetwork.Incident).dir), _path[_path.size() - 1]]
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

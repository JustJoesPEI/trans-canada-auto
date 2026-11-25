class_name CarAutopilot
extends Node
## A computer driver for any Car: add it as a child of the car and tell it
## where to go. It drives the real car through the same controls a player
## has (throttle, brake, steering, handbrake, via Car.ai_controls), so it
## skids, understeers and bumps into things the way a player would. It
## never moves the car itself.
##
##   drive_to(point)  along the streets to a point, in the right-hand lane,
##                    keeping to one-way streets, and stop there (`arrived`).
##                    With off_road, it may finish (or start) off the street.
##   follow(target)   chase a car or a person (see "Respond and pursue")
##   box_in(target)   come alongside a slow car, cut in across its nose and
##                    stop there, so it's pinned
##   pit(target)      at speed, come up beside its back corner and steer
##                    into it to spin it, then carry on chasing
##   stop()           brake to a stop and hold there
##
## Respond and pursue. A unit sent from far off comes by the streets, like
## real police: RESPOND keeps to the street graph (it ignores one-way signs,
## lights on, but never cuts across a field). Within `pursuit_range` of the
## target it switches to PURSUIT: straight at the target when it's in sight,
## off the road after it (lawns, lots, fields), across open ground when
## that's clearly shorter than the streets, cutting corners. It drops back
## to RESPOND when the target gets beyond `pursuit_drop_range` or has been
## out of sight for `lost_sight_drop` seconds. `chase_mode` lets a
## dispatcher hold either one.
##
## Driving: pure pursuit (steer for a point a speed-dependent distance down
## the line), a speed from the route's corner limits, rays ahead for
## buildings, poles, trees, fences and cars, rays down ahead for drops and
## water, slower on rough ground, a K-turn when the way on is behind it,
## backing out when it's stuck or boxed against something, and planning
## again when it stops getting anywhere. The map's gaps and dead ends are
## handled by StreetRoute (bridged, or as near as the streets go).
##
## Tuned for the town police (the "jaunt" and "rammer" in the "cps" livery).
##
## Civil driving. `use_civil_driving()` switches on ordinary road manners
## (CivilDriving, scripts/ai/civil_driving.gd) for drive_to: it follows the
## car ahead at a gap that grows with speed, stops for red lights and stop
## signs, gives way at roundabouts and side streets, waits for a gap to turn
## left or merge, keeps out of a junction it can't clear, changes lanes to
## turn or to get round a stopped car, pulls over for sirens and reacts to
## hazards, and honks (`horn`). With it on, the pedals are smoothed (no
## flicking between throttle and brake: a jerk limit and a dead band with
## hysteresis), other vehicles are left to it rather than to the rays (which
## then only see walls, poles and parked cars), and waiting on purpose
## doesn't count as getting nowhere. Town traffic (scripts/traffic/) always
## drives this way; police on patrol can too (`civil.pulls_over = false`
## for one answering a call). Off by default: a chase is unchanged.

signal arrived
## The chase changed between responding (false) and pursuing (true).
signal pursuit_changed(on: bool)

enum Mode { IDLE, DRIVE, FOLLOW, BOX_IN, PIT }
enum ChaseMode { AUTO, RESPOND, PURSUIT }

## Speed along the streets when not chasing (km/h).
@export var cruise_speed_kmh := 50.0
## Top speed in a chase (km/h): the police are about as fast as an ordinary
## car (design.md section 7, difficulty targets).
@export var chase_speed_kmh := 140.0
## Top speed off the street: grass, lots, fields (km/h).
@export var offroad_speed_kmh := 55.0
## Corner grip the planner allows for (m/s^2): lower is more careful.
@export var corner_accel := 5.5
## Braking the planner allows for, slowing for corners and stops (m/s^2).
@export var brake_accel := 5.0
## How close to follow behind a target (metres, between centres).
@export var follow_gap := 9.0
## Inside this distance, with the target in sight, a pursuit drives straight
## at it instead of along the streets (twice as far when it's off the road).
@export var direct_range := 60.0
## How much room either side of the car the way to drive straight at
## something needs (m).
const WAY_MARGIN := 0.25
## How far ahead that way has to be clear (m).
const WAY_SWEEP := 30.0
## On the streets, drive straight at the target only when it's within this
## many degrees of straight ahead.
const DIRECT_CONE := 35.0
## AUTO chase: pursue (off road if need be) within this of the target (or
## half as far again once it's in sight)...
@export var pursuit_range := 120.0
## ...and go back to responding by the streets beyond this,
@export var pursuit_drop_range := 200.0
## or after this long without seeing it (seconds).
@export var lost_sight_drop := 4.0
## Who decides between responding and pursuing (a dispatcher can hold one).
@export var chase_mode := ChaseMode.AUTO
## PIT only above this speed (km/h): design.md section 7, level 3.
@export var pit_min_kmh := 55.0
## drive_to keeps to one-way streets (off for a unit responding with its
## siren on).
@export var obey_oneway := true

## The controls, read by the car (Car.ai_controls).
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
## The horn (CarAudio sounds it), from civil driving.
var horn := false
## Road manners (see "Civil driving" above); null when off.
var civil: CivilDriving = null
var _civil_a := 0.0
var _civil_braking := false
var _civil_replan := 0.0

var car: Car
var network: RoadNetwork
var terrain: Terrain
var mode := Mode.IDLE
var target: Node3D = null
var route: StreetRoute = null
## Where along `route` the car is (metres).
var along := 0.0
## Pursuing (true) or responding by the streets (false), in a chase.
var pursuit := false
## What it's doing, for tests and debugging ("route", "offroad", "respond",
## "pursue", "direct", "alongside", "cut", "hold", "line_up", "tap",
## "back_off", "reverse", "turn", "blocked", ...).
var state := ""
## How many times it has backed out of being stuck, and how many times it
## got nowhere along a route (for tests).
var recoveries := 0
var stalls := 0

var _dest := Vector3.ZERO
var _dest_off_road := false
var _arrived := false
var _replan := 0.0
var _stuck := 0.0
var _blocked := 0.0
var _recover := 0.0
var _recover_steer := 0.0
var _turning := 0 # K-turn: 0 none, 1 forward on full lock, -1 backing
var _turn_time := 0.0
var _turn_from := Vector3.ZERO
var _turn_first := false
var _target_vel := Vector3.ZERO
var _target_last := Vector3.ZERO
var _unseen := 0.0
var _shortcut_check := 0.0
## The target's recent trail (see _record_trail).
var _trail := PackedVector2Array()
const TRAIL_STEP := 2.0 ## metres between trail points
const TRAIL_MAX := 120 ## points kept
const TRAIL_NEAR := 12.0 ## follow the trail only from this close to it
const TRAIL_LOOK := 6.0 ## metres ahead on it to steer for, plus 0.35 s of speed
## The box swept by _way_clear (made once).
var _sweep_box: BoxShape3D
var _sweep_query: PhysicsShapeQueryParameters3D
var _phase_time := 0.0
var _pit_side := 0.0
var _pit_yaw0 := 0.0
var _box_side := 0.0
var _progress_best := 0.0
var _progress_time := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ground_ray := PhysicsRayQueryParameters3D.new()
var _wheelbase := 2.8
var _half_len := 2.4
var _half_wid := 0.9
var _street_dist := 0.0 # how far outside the nearest street's curb we are
var _street_check := 0.0
var _bias := 0.0 # steering added for a moment after backing out
var _bias_time := 0.0
var _recover_at := Vector3.INF
var _recover_t := 0.0
var _streak := 0
var _wiggle_time := 0.0
var _recover_still := 0.0
## What the middle ray ahead last hit (for debugging).
var blocker := ""
var _wait_time := 0.0
## A stop line along the route (metres along `route`), or -1 for none:
## the car comes to a stop with its nose short of it and waits there until
## it's cleared (a red light; the police's patrols set it, CarAutopilot
## doesn't read the lights itself).
var hold_at := -1.0


func _ready() -> void:
	car = get_parent() as Car
	assert(car != null, "CarAutopilot must be a child of a Car")
	# Work out the controls before the car reads them, in the same step.
	process_physics_priority = -1
	var sh := car.shape
	_wheelbase = absf(float(sh.get("rear_axle", 1.4)) - float(sh.get("front_axle", -1.4)))
	_half_len = float(sh.get("length", 4.6)) * 0.5
	_half_wid = float(sh.get("width", 1.8)) * 0.5
	var world := find_world(self)
	if network == null and world != null:
		network = world.network
	if terrain == null and world != null:
		terrain = world.terrain
	_ray.collision_mask = Layers.SOLID if civil != null else Layers.SOLID | Layers.VEHICLES
	_ground_ray.collision_mask = Layers.GROUND


## The town this node is in.
static func find_world(from: Node) -> WorldBuilder:
	for n: Node in from.get_tree().root.get_children():
		if n is WorldBuilder:
			return n
		for m: Node in n.get_children():
			if m is WorldBuilder:
				return m
	return null


## The street network of the town this node is in.
static func find_network(from: Node) -> RoadNetwork:
	var w := find_world(from)
	return w.network if w != null else null


# --- orders ---------------------------------------------------------------------

## Switch civil driving (road manners) on or off; returns it, to set the
## driver's personality on.
func use_civil_driving(on := true) -> CivilDriving:
	if on and civil == null:
		var world := find_world(self) if is_inside_tree() else null
		civil = CivilDriving.new(car if car != null else get_parent() as Node3D, network, world.data if world != null else null)
	elif not on:
		civil = null
		horn = false
	_ray.collision_mask = Layers.SOLID if on else Layers.SOLID | Layers.VEHICLES
	return civil


## Drive along the streets to a point and stop there (emits `arrived`).
## With `off_road`, the point may be off the street (a field, a lot): it
## drives the last of the way (or the first, from off the street) straight.
func drive_to(point: Vector3, off_road := false) -> void:
	_take_wheel()
	mode = Mode.DRIVE
	target = null
	_dest = point
	_dest_off_road = off_road
	_arrived = false
	_plan_to(_flat(point), obey_oneway, true, off_road)


## Drive a route already planned, from `at` metres along it, and stop at
## its end (a RoadFollower handing over keeps its plan; `dest` is where
## to plan to again if it has to).
func drive_route(r: StreetRoute, at: float, dest: Vector3) -> void:
	_take_wheel()
	mode = Mode.DRIVE
	target = null
	_dest = dest
	_dest_off_road = false
	_arrived = false
	route = r
	along = at
	_progress_best = at


## Chase a car or a person on foot until told otherwise.
func follow(who: Node3D) -> void:
	_take_wheel()
	mode = Mode.FOLLOW
	_set_target(who)


## Get alongside or ahead of a slow or stopped car and stop across its nose.
func box_in(who: Car) -> void:
	_take_wheel()
	mode = Mode.BOX_IN
	_set_target(who)
	_box_side = 0.0


## Above pit_min_kmh, tap the target's back corner to spin it; below that,
## or after the tap, chase it.
func pit(who: Car) -> void:
	_take_wheel()
	mode = Mode.PIT
	_set_target(who)
	_pit_side = 0.0


## Brake to a stop and hold there (keeps the wheel; set car.ai_controls to
## null, or free this node, to hand the car back).
func stop() -> void:
	_take_wheel()
	mode = Mode.IDLE
	target = null
	route = null
	state = "stop"


func _take_wheel() -> void:
	if car == null:
		car = get_parent() as Car
	car.ai_controls = self
	_stuck = 0.0
	_blocked = 0.0
	_recover = 0.0
	_turning = 0
	_phase_time = 0.0
	_replan = 0.0
	_progress_best = 0.0
	_progress_time = 0.0


func _exit_tree() -> void:
	if car != null and car.ai_controls == self:
		car.ai_controls = null


func _set_target(who: Node3D) -> void:
	if who != target:
		_set_pursuit(chase_mode == ChaseMode.PURSUIT)
	target = who
	_target_last = who.global_position
	var v := _velocity_of(who)
	_target_vel = Vector3.ZERO if v == Vector3.INF else v
	_unseen = 0.0
	route = null
	_replan = 0.0
	state = ""


func _set_pursuit(on: bool) -> void:
	if on != pursuit:
		pursuit = on
		route = null # plan again, the other way
		_replan = 0.0
		pursuit_changed.emit(on)


# --- the loop ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if car == null or car.ai_controls != self or network == null:
		return
	_phase_time += delta
	_recover_t += delta
	_bias_time -= delta
	_street_check -= delta
	if _street_check <= 0.0:
		_street_check = 0.25
		_street_dist = _off_street(_flat(car.global_position))
	if target != null:
		if not is_instance_valid(target):
			stop()
		else:
			# A person moved by code has no velocity of its own: measure it.
			var v := _velocity_of(target)
			if v == Vector3.INF:
				v = (target.global_position - _target_last) / maxf(delta, 0.001)
			_target_vel = _target_vel.lerp(v, 0.3)
			_target_last = target.global_position
			_update_pursuit(delta)
	if _recover > 0.0:
		_do_recover(delta)
		return
	match mode:
		Mode.IDLE:
			_hold_stop()
		Mode.DRIVE:
			_do_drive(delta)
		Mode.FOLLOW:
			_do_follow(delta)
		Mode.BOX_IN:
			_do_box_in(delta)
		Mode.PIT:
			_do_pit(delta)
	_check_stuck(delta)


## Respond or pursue, from how far off the target is and whether it's seen.
func _update_pursuit(delta: float) -> void:
	if chase_mode != ChaseMode.AUTO:
		_set_pursuit(chase_mode == ChaseMode.PURSUIT)
		return
	var d := car.global_position.distance_to(target.global_position)
	var seen := d < pursuit_drop_range and _can_see(target)
	_unseen = 0.0 if seen else _unseen + delta
	# Close, or as near as the streets go with it in plain sight: pursue.
	if not pursuit and (d < pursuit_range or (seen and d < pursuit_range * 1.5)):
		_set_pursuit(true)
	elif pursuit and (d > pursuit_drop_range or _unseen > lost_sight_drop):
		_set_pursuit(false)


func _do_drive(delta: float) -> void:
	if _arrived:
		_hold_stop()
		return
	if route == null or route.is_empty():
		_replan -= delta
		if _replan <= 0.0:
			_plan_to(_flat(_dest), obey_oneway, true, _dest_off_road)
			_replan = 2.0
		_hold_stop()
		return
	state = "route" if _street_dist < 1.0 else "offroad"
	_follow_route(delta, cruise_speed_kmh / 3.6, [])
	var left := route.length - along
	if left < 4.0 and absf(car.speed) < 1.5:
		_arrived = true
		state = "arrived"
		_hold_stop()
		arrived.emit()


## Chase: responding along the streets, or pursuing (straight at it when
## close and seen, off the road after it, along the streets otherwise).
func _do_follow(delta: float) -> void:
	var me := _flat(car.global_position)
	var tp := _flat(target.global_position)
	var dist := me.distance_to(tp)
	var top := chase_speed_kmh / 3.6
	if pursuit:
		var reach := direct_range * (2.0 if _off_street(tp) > 2.0 else 1.0)
		# Straight at it only when a car fits through on the way: seen round
		# a corner isn't the same as a way round it.
		# And only when it's roughly ahead, or off the road: straight at a
		# car that's just turned a corner cuts across the junction and
		# arrives at the side street at an angle, nose into its parked cars
		# (the lanes go round the corner properly).
		var ahead := absf(_fwd2().angle_to(tp - me)) < deg_to_rad(DIRECT_CONE)
		_record_trail(tp)
		if dist < reach and _can_see(target):
			# Close behind it, follow the way it actually went (its trail):
			# that takes a corner the way a car can, where heading straight
			# for it cuts across the junction into the side street's parked
			# cars. Further back, or off the road, straight at it.
			var crumb := _trail_point(me)
			var on_trail := crumb.x < INF and _way_clear(crumb, [target])
			var off_road := _off_street(tp) > 2.0 or _off_street(me) > 2.0
			# On the street with its trail under us, the trail: it goes round
			# corners in the lane, where straight at it cuts the inside of a
			# turn into the parked cars there.
			if on_trail and not off_road:
				_chase_trail(crumb, dist, top)
				return
			if (ahead or off_road) and _way_clear(tp, [target]):
				_chase_direct(me, tp, dist, top)
				return
			if on_trail:
				_chase_trail(crumb, dist, top)
				return
	else:
		_trail.clear()
	_replan -= delta
	var off_end := route == null or route.is_empty() or route.goal.distance_to(tp) > maxf(15.0, dist * 0.15)
	if _replan <= 0.0 and off_end:
		_plan_to(tp, false, false, pursuit)
		_replan = 1.0
		if pursuit:
			_try_shortcut(me, tp)
	elif pursuit and route != null and not route.direct_line:
		_shortcut_check -= delta
		if _shortcut_check <= 0.0:
			_shortcut_check = 1.0
			_try_shortcut(me, tp)
	if route == null or route.is_empty():
		# Between plans (just out of a direct chase, the next plan not due
		# yet): keep on the way it went rather than stopping dead mid-corner.
		if pursuit:
			var crumb2 := _trail_point(me)
			if crumb2.x < INF:
				_chase_trail(crumb2, dist, top)
				return
		_hold_stop()
		state = "no_way"
		return
	if route.direct_line:
		state = "offroad"
	else:
		state = "pursue" if pursuit else "respond"
	if not pursuit and route.length - along < 6.0:
		# As near as the streets go: wait there. Sent here over the radio
		# and close, but it can't see it from the street (a building in the
		# way): after a moment, go and look, off the road if need be.
		_hold_stop()
		state = "respond_wait"
		_wait_time += delta
		if chase_mode == ChaseMode.AUTO and _wait_time > 2.0 and dist < pursuit_range * 1.6:
			_wait_time = 0.0
			_unseen = 0.0
			_set_pursuit(true)
		return
	_wait_time = 0.0
	_follow_route(delta, top, [target])


## Where the target has been lately (its trail, one point every couple of
## metres), so a pursuer can follow it round a corner.
func _record_trail(tp: Vector2) -> void:
	if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(tp) > TRAIL_STEP:
		_trail.append(tp)
		if _trail.size() > TRAIL_MAX:
			_trail.remove_at(0)


## The point on the target's trail to steer for: past the trail point
## nearest the car by a look-ahead that grows with speed. Points behind the
## car are dropped. Vector2(INF, INF) when there's no trail to follow (the
## car is far from it).
func _trail_point(me: Vector2) -> Vector2:
	if _trail.size() < 2:
		return Vector2(INF, INF)
	var best := 0
	var best_d := INF
	for i in _trail.size():
		var d := me.distance_to(_trail[i])
		if d < best_d:
			best_d = d
			best = i
	if best_d > TRAIL_NEAR:
		return Vector2(INF, INF)
	for i in best:
		_trail.remove_at(0)
	var look := TRAIL_LOOK + maxf(car.speed, 0.0) * 0.35
	for p: Vector2 in _trail:
		if me.distance_to(p) >= look:
			return p
	return _trail[_trail.size() - 1]


## Along its trail at a speed that closes to the following gap.
func _chase_trail(crumb: Vector2, dist: float, top: float) -> void:
	var tspeed := Vector2(_target_vel.x, _target_vel.z).length()
	var want := tspeed + clampf((dist - follow_gap) * 0.6, -10.0, 18.0)
	# Close behind, as in a direct chase: no faster than it, and stopped
	# behind it when it stops (not shoving it down the street).
	if dist < follow_gap * 0.8:
		want = minf(want, tspeed * 0.8)
	if tspeed < 1.0 and dist < follow_gap + 2.0:
		_hold_stop()
		state = "stopped_behind"
		route = null
		return
	state = "trail"
	route = null
	_drive_at(crumb, clampf(want, 0.0, top), [target])


## Straight at it: a point just behind it, led by its speed, matching it.
func _chase_direct(me: Vector2, tp: Vector2, dist: float, top: float) -> void:
	var tv := Vector2(_target_vel.x, _target_vel.z)
	var tdir := _heading_of(target, tv)
	var aim := tp - tdir * follow_gap + tv * 0.35
	var turned := absf(_fwd2().angle_to(tdir)) > deg_to_rad(30.0)
	if turned or me.distance_to(aim) < 3.0 or not _way_clear(aim, [target]):
		# It's turning (or just turned a corner): the spot behind it is off
		# to the side or back round the corner, so go for the car itself,
		# following it round.
		aim = tp + tv * 0.3
	var tspeed := tv.length()
	var rel := (aim - me).dot(_fwd2())
	var want := tspeed + clampf(rel * 0.6, -10.0, 18.0)
	if dist < follow_gap * 0.8:
		want = minf(want, tspeed * 0.8)
	if tspeed < 1.0 and dist < follow_gap + 2.0:
		_hold_stop()
		state = "stopped_behind"
		return
	state = "direct"
	route = null
	_drive_at(aim, clampf(want, 0.0, top), [target])


## Across open ground when it's clearly shorter than the streets and the
## way is clear (only where that can be checked: near the car).
func _try_shortcut(me: Vector2, tp: Vector2) -> void:
	if route == null or route.is_empty() or route.direct_line:
		return
	var straight := me.distance_to(tp)
	var left := route.length - along
	if straight > 150.0 or left < straight * 1.6 + 30.0:
		return
	if _line_clear(me, tp):
		route = StreetRoute.direct(me, tp, _plan_opts(false, true, false))
		along = 0.0
		_progress_best = 0.0
		_progress_time = 0.0


## Box in: alongside, then across its nose, then hold.
func _do_box_in(delta: float) -> void:
	var tcar := target as Car
	var me := _flat(car.global_position)
	var tp := _flat(target.global_position)
	var tv := Vector2(_target_vel.x, _target_vel.z)
	var tdir := _heading_of(target, tv)
	var tright := Vector2(-tdir.y, tdir.x)
	var thl := float(tcar.shape.get("length", 4.5)) * 0.5 if tcar != null else 1.0
	var thw := float(tcar.shape.get("width", 1.8)) * 0.5 if tcar != null else 0.5
	var tspeed := maxf(0.0, tv.dot(tdir))
	var dist := me.distance_to(tp)
	if dist > 45.0 or not _can_see(target):
		_do_follow(delta) # catch up first
		return
	if _box_side == 0.0:
		# Come up on the side we're already on.
		_box_side = -1.0 if (me - tp).dot(tright) < 0.5 else 1.0
	var beside := tp + tright * _box_side * (thw + _half_wid + 0.9)
	var nose := tp + tdir * (thl + _half_wid + 0.3)
	var ahead := (me - tp).dot(tdir) # how far ahead of its middle we are
	if state == "hold":
		if dist > thl + _half_len + 6.0:
			state = "alongside"
		else:
			_hold_stop()
			return
	if tspeed > 6.0 or ahead < thl * 0.3:
		# Alongside, a little ahead, at its speed.
		state = "alongside"
		var aim := beside + tdir * (thl * 0.6) + tdir * maxf(6.0, tspeed * 0.5)
		var want := tspeed + clampf((thl * 0.6 - ahead) * 0.8, -6.0, 12.0)
		# Still behind it and not yet out to the side: close slowly, so it
		# pulls out beside it rather than into its back bumper.
		var lat := (me - tp).dot(tright) * _box_side
		var gap_behind := -ahead - thl - _half_len
		if gap_behind > -1.0 and lat < thw + _half_wid + 0.3:
			want = minf(want, tspeed + clampf(gap_behind * 0.5, 0.0, 4.0))
		_drive_at(aim, clampf(want, 2.0, chase_speed_kmh / 3.6), [target])
		return
	# Slow, and we're level with it or ahead: cut across the nose.
	state = "cut"
	var to_nose := me.distance_to(nose)
	var want := clampf(to_nose * 0.9, 0.0, maxf(tspeed + 3.0, 4.0))
	if to_nose < 1.2 or (to_nose < 1.8 and absf(car.speed) < 1.0):
		state = "hold"
		_hold_stop()
		return
	_drive_at(nose + tdir * 0.5 - tright * _box_side * 2.0, want, [target], false, 1.0)


## PIT: line up with our front bumper beside its back wheel, matching
## speed, then steer into it and through.
func _do_pit(delta: float) -> void:
	var tcar := target as Car
	var me := _flat(car.global_position)
	var tp := _flat(target.global_position)
	var tv := Vector2(_target_vel.x, _target_vel.z)
	var tdir := _heading_of(target, tv)
	var tright := Vector2(-tdir.y, tdir.x)
	var tspeed := tv.length()
	var thl := float(tcar.shape.get("length", 4.5)) * 0.5 if tcar != null else 2.2
	var thw := float(tcar.shape.get("width", 1.8)) * 0.5 if tcar != null else 0.9
	var dist := me.distance_to(tp)
	if state == "back_off":
		_do_follow(delta)
		state = "back_off"
		if _phase_time > 2.5:
			state = ""
			_pit_side = 0.0
		return
	if tspeed * 3.6 < pit_min_kmh or dist > 40.0 or not _can_see(target):
		_do_follow(delta)
		return
	if _pit_side == 0.0:
		_pit_side = -1.0 if (me - tp).dot(tright) < 0.0 else 1.0
	var lat := (me - tp).dot(tright) * _pit_side # how far out to our side
	var lon := (me - tp).dot(tdir) # how far ahead of its middle
	var want_lon := -thl + 0.4 - _half_len # our nose just ahead of its back bumper
	var want_lat := thw + _half_wid + 0.45
	if state == "tap":
		var yaw_off := absf(angle_difference(_pit_yaw0, target.global_rotation.y))
		if _phase_time > 1.8 or yaw_off > 0.9 or lon > want_lon + 2.5:
			state = "back_off"
			_phase_time = 0.0
			_do_follow(delta)
			return
		# Turn in toward its back corner, holding our nose at its back
		# wheel (not running on past it, which only shoves it sideways),
		# and push through as it starts to come round.
		steer = _pit_side * (0.6 if lat > want_lat - 0.5 else 1.0)
		_pedals(tspeed + 0.3 + clampf((want_lon - lon) * 1.5, -2.5, 2.5), car.speed)
		if lat < want_lat - 0.3:
			throttle = maxf(throttle, 0.8) # in contact: drive the tail round
		return
	state = "line_up"
	var spot := tp + tdir * want_lon + tright * _pit_side * want_lat
	var aim := spot + tdir * maxf(8.0, tspeed * 0.7)
	var want := tspeed + clampf((want_lon - lon) * 0.7, -6.0, 10.0)
	_drive_at(aim, clampf(want, 0.0, chase_speed_kmh / 3.6), [target])
	if absf(lon - want_lon) < 1.2 and absf(lat - want_lat) < 1.2 and absf(car.speed - tspeed) < 2.5:
		state = "tap"
		_phase_time = 0.0
		_pit_yaw0 = target.global_rotation.y


# --- driving -------------------------------------------------------------------

func _plan_opts(obey: bool, off_road: bool, stop_at_end := true) -> Dictionary:
	return {
		"obey_oneway": obey,
		"off_road": off_road,
		"heading": _fwd2(),
		"lane": 1.0 if obey or not off_road else 0.5,
		"lat_accel": corner_accel,
		"brake_accel": brake_accel,
		"stop_at_end": stop_at_end,
		"top_speed": chase_speed_kmh / 3.6,
	}


func _plan_to(to: Vector2, obey: bool, stop_at_end: bool, off_road: bool) -> void:
	var me := _flat(car.global_position)
	route = StreetRoute.plan(network, me, to, _plan_opts(obey, off_road, stop_at_end))
	along = route.project(me) if not route.is_empty() else 0.0
	_progress_best = along
	_progress_time = 0.0


## Along the route: steer for a point down the line, at the line's limit.
func _follow_route(delta: float, top: float, ignore: Array) -> void:
	var me := _flat(car.global_position)
	_civil_replan -= delta
	along = route.project(me, along)
	if route.off_line(me, along) > 25.0:
		# Lost it (pushed off, overshot a turn): plan again from here.
		_replan_now()
		if route == null or route.is_empty():
			_hold_stop()
			return
	# Getting nowhere along it (the map's wrong here, or something in the
	# way the rays don't see): back out and plan again.
	_progress_time += delta
	if along > _progress_best + 3.0:
		_progress_best = along
		_progress_time = 0.0
	elif civil != null and (civil.holding or civil.lateral != 0.0):
		_progress_time = 0.0 # waiting its turn, or getting round something
	elif _progress_time > 7.0 and route.length - along > 5.0:
		stalls += 1
		_progress_time = 0.0
		_start_recover(-steer)
		return
	var v := absf(car.speed)
	var look := clampf(4.0 + v * 0.55, 6.0, 28.0)
	var aim := route.sample(along + look)
	var want := minf(top, route.limit_at(along + v * 0.35))
	if hold_at >= 0.0:
		# Stop with the nose short of the line.
		var room := hold_at - along - _half_len - 0.8
		want = minf(want, sqrt(2.0 * brake_accel * 0.8 * maxf(room, 0.0)))
		if room < 0.6 and v < 1.5:
			state = "hold_line"
			_hold_stop()
			_progress_time = 0.0
			return
	if along + look >= route.length - 0.5:
		# The end: steer for it, and stop on it.
		aim = route.sample(route.length)
		var left := me.distance_to(aim)
		want = minf(want, sqrt(2.0 * brake_accel * 0.7 * maxf(left - 1.5, 0.0)))
	elif look > 7.0 or v < 4.0:
		# Cutting the corner toward the point ahead would clip a building
		# (off the line after backing out, or a tight downtown corner):
		# steer for a nearer point on the line instead.
		var step := look
		while step > 3.0 and not _way_clear(aim, ignore):
			step *= 0.5
			aim = route.sample(along + step)
	if civil != null:
		want = civil.want_speed(route, along, v, want, delta)
		aim += civil.aim_shift(route, along + look)
		horn = civil.honk
	_drive_at(aim, want, ignore)


## A car-wide way from the front bumper to a point, clear of buildings and
## other solid things (cars aside). A box as wide as the car (plus a little)
## is swept the whole way, so a tree trunk, lamp post or hydrant between
## the car's sides counts: two rays along the sides used to miss them, and
## the car drove straight into one cutting a junction corner.
func _way_clear(to: Vector2, ignore: Array) -> bool:
	var space := car.get_world_3d().direct_space_state
	var xf := car.global_transform
	var ex: Array[RID] = [car.get_rid()]
	for n: Variant in ignore:
		if n is CollisionObject3D and is_instance_valid(n):
			ex.append((n as CollisionObject3D).get_rid())
	if _sweep_box == null:
		_sweep_box = BoxShape3D.new()
		_sweep_query = PhysicsShapeQueryParameters3D.new()
		_sweep_query.collision_mask = Layers.SOLID
	# Wide as the car plus a hand either side, from just above the curbs to
	# roof height, a metre long, swept from the front bumper.
	_sweep_box.size = Vector3((_half_wid + WAY_MARGIN) * 2.0, 1.1, 1.0)
	var from := xf * Vector3(0.0, 1.05, -_half_len)
	var dest := Vector3(to.x, from.y, to.y)
	var motion := dest - from
	if motion.length() < 0.5:
		return true
	# Only the stretch the car is about to drive has to be clear: further on,
	# the steering rays have time to go round a parked car (a long sweep
	# down a curving street always clips the cars along its curb).
	motion = motion.limit_length(WAY_SWEEP)
	_sweep_query.shape = _sweep_box
	_sweep_query.exclude = ex
	_sweep_query.transform = Transform3D(Basis.looking_at(motion.normalized(), Vector3.UP), from)
	_sweep_query.motion = motion
	var frac := space.cast_motion(_sweep_query)
	return frac.size() == 0 or frac[0] >= 1.0


func _replan_now() -> void:
	match mode:
		Mode.DRIVE:
			_plan_to(_flat(_dest), obey_oneway, true, _dest_off_road)
		Mode.IDLE:
			route = null
		_:
			if target != null:
				_plan_to(_flat(target.global_position), false, false, pursuit)


## The steering, throttle and brake to head for a point at a speed.
## `avoid` uses the rays to keep off buildings, cars, drops and water (not
## the `ignore` bodies); `aggression` above 0 lets it steer harder at speed.
func _drive_at(aim: Vector2, want: float, ignore: Array, avoid := true, aggression := 0.0) -> void:
	var xf := car.global_transform
	var local := xf.basis.inverse() * (Vector3(aim.x, xf.origin.y, aim.y) - xf.origin)
	var alpha := atan2(-local.x, -local.z) # + is to the left
	var ld := maxf(Vector2(local.x, local.z).length(), 1.0)
	var v := car.speed
	var dt := get_physics_process_delta_time()
	# Civil, pointing the wrong way (spun, shunted): first see if there's a
	# way on from the way it's facing (round the block) before a K-turn.
	if civil != null and _turning == 0 and mode == Mode.DRIVE and absf(alpha) > deg_to_rad(110.0) and v < 3.0 and _civil_replan <= 0.0:
		_civil_replan = 10.0
		_replan_now()
		_hold_stop()
		return
	# K-turn when the way on is behind us.
	if _turning != 0 or (absf(alpha) > deg_to_rad(110.0) and v < 3.0 and ld > 4.0):
		_k_turn(alpha)
		return
	if absf(alpha) > deg_to_rad(100.0) and v > 3.0:
		# Overshot: stop first, then turn.
		_pedals(0.0, v)
		steer = signf(alpha)
		return
	var delta_wheel := atan(2.0 * _wheelbase * sin(alpha) / ld)
	var s := delta_wheel / _lock_at(absf(v))
	# Catch a slide: steer the way the car is going.
	var lv := xf.basis.inverse() * car.linear_velocity
	if absf(lv.z) > 3.0:
		var beta := atan2(-lv.x, -lv.z)
		s += clampf(beta * 1.2, -0.6, 0.6)
	# Slow for a tight turn the line asked for at the last moment.
	var turn_cap := sqrt(corner_accel * (1.0 + aggression * 0.5) / maxf(absf(2.0 * sin(alpha) / ld), 0.001))
	want = minf(want, maxf(turn_cap, 4.0))
	if _street_dist > 1.0:
		want = minf(want, offroad_speed_kmh / 3.6) # grass, gravel, kerbs
	if _bias_time > 0.0:
		s += _bias # going round what we just backed away from
	var asked := want
	if avoid:
		var av := _avoid(ignore)
		s += av.x
		want = minf(want, av.y)
	steer = clampf(s, -1.0, 1.0)
	handbrake = false
	_pedals(want, v)
	# Wanting to go but something's right in front: after a moment, back
	# off and come at it from the side that's clearer.
	# (Civil driving pulls away gently, asking for less at first.)
	if asked > (0.9 if civil != null else 2.0) and want < (0.5 if civil != null else 1.0) and absf(v) < 1.0:
		_blocked += dt
		state = "blocked"
		if _blocked > 0.7:
			_start_recover(-signf(s) if absf(s) > 0.1 else 1.0)
	else:
		_blocked = maxf(0.0, _blocked - dt)


## The pedals for a wanted speed: a little throttle to hold speed, more to
## gain it, the brake when well over.
func _pedals(want: float, v: float) -> void:
	handbrake = false
	if civil != null and _recover <= 0.0 and _turning == 0:
		_civil_pedals(want, v)
		return
	if want < 0.3:
		_hold_stop_pedals(v)
		return
	var err := want - v
	if v < -0.5:
		# Rolling back: brake (the throttle pedal brakes while reversing).
		throttle = 1.0
		brake = 0.0
		return
	if err > -0.5:
		throttle = clampf(0.12 + err * 0.35, 0.0, 1.0)
		# Don't spin the tyres or push through a corner on full power.
		throttle *= 1.0 - 0.6 * clampf(car.skid, 0.0, 1.0)
		brake = 0.0
	elif err > -2.0:
		throttle = 0.0
		brake = 0.0
	else:
		throttle = 0.0
		brake = clampf(-err * 0.18, 0.1, 1.0)
		if v < 1.2:
			brake = 0.0 # the pedal would reverse it
			handbrake = true


## Civil pedals: the wanted speed as an acceleration, changed no faster
## than a jerk limit, then throttle or brake with a dead band between them
## and hysteresis, so it never flicks from one to the other.
func _civil_pedals(want: float, v: float) -> void:
	var dt := get_physics_process_delta_time()
	if want < 0.3 and v < 1.0:
		_civil_a = 0.0
		_civil_braking = false
		_hold_stop_pedals(v)
		return
	if v < -0.5:
		throttle = 1.0 # rolling back: the throttle pedal brakes it
		brake = 0.0
		return
	var a_des := clampf((want - v) / 0.8, -9.0, 3.0)
	var jerk := 20.0 if a_des < -4.0 else 5.0
	_civil_a = move_toward(_civil_a, a_des, jerk * dt)
	if _civil_braking and _civil_a > -0.15:
		_civil_braking = false
	elif not _civil_braking and _civil_a < -0.6:
		_civil_braking = true
	var full := float((car.spec.get("brakes", {}) as Dictionary).get("force", 9000.0)) / maxf(car.mass, 1.0)
	if _civil_braking:
		throttle = 0.0
		brake = clampf((-_civil_a - 0.25) / maxf(full, 2.0), 0.04, 1.0)
	else:
		brake = 0.0
		throttle = 0.0
		if _civil_a > 0.0:
			throttle = clampf(0.1 + _civil_a * 0.3, 0.0, 0.9) * (1.0 - 0.6 * clampf(car.skid, 0.0, 1.0))


func _hold_stop() -> void:
	steer = move_toward(steer, 0.0, 0.05)
	_hold_stop_pedals(car.speed)


func _hold_stop_pedals(v: float) -> void:
	throttle = 0.0
	if v > 1.2:
		brake = clampf(0.25 + v * 0.06, 0.0, 1.0)
		handbrake = false
	elif v < -1.2:
		throttle = clampf(0.25 - v * 0.06, 0.0, 1.0) # forward pedal brakes in reverse
		brake = 0.0
		handbrake = false
	else:
		brake = 0.0
		handbrake = true


## The wheel lock (radians) the car allows at a speed, as Car._read_controls.
func _lock_at(v: float) -> float:
	var st: Dictionary = car.spec["steering"]
	return deg_to_rad(lerpf(float(st["max_degrees"]), float(st["high_speed_degrees"]), smoothstep(0.0, float(st.get("lock_kmh", 100.0)), v * 3.6)))


const RAY_ANGLES := [0.0, 0.3, -0.3, 0.65, -0.65]

## Rays ahead (at 0, +-17 and +-37 degrees) for things to hit, and down
## ahead for drops and water. Returns (steer to add, top speed for what's
## ahead).
func _avoid(ignore: Array) -> Vector2:
	var v := maxf(car.speed, 0.0)
	var xf := car.global_transform
	var space := car.get_world_3d().direct_space_state
	var ex: Array[RID] = [car.get_rid()]
	for n: Variant in ignore:
		if n is CollisionObject3D and is_instance_valid(n):
			ex.append((n as CollisionObject3D).get_rid())
	_ray.exclude = ex
	var reach := clampf(5.0 + v * 1.1, 7.0, 45.0)
	var origin := xf * Vector3(0.0, 0.7, -_half_len + 0.3)
	var free: Array[float] = [] # 0 blocked at the bumper .. 1 clear
	for a: float in RAY_ANGLES:
		var dir := xf.basis * Vector3(-sin(a), 0.0, -cos(a))
		var r := reach if a == 0.0 else reach * (0.55 if absf(a) < 0.5 else 0.3)
		_ray.from = origin + xf.basis * Vector3(signf(a) * _half_wid * 0.8, 0.0, 0.0)
		_ray.to = _ray.from + dir * r
		var h := space.intersect_ray(_ray)
		free.append(1.0 if h.is_empty() else (_ray.from.distance_to(h["position"]) / r))
		if a == 0.0:
			blocker = "" if h.is_empty() else "%s/%s" % [(h["collider"] as Node).get_parent().name, (h["collider"] as Node).name]
	# The ground ahead: a drop the car can't take, or water, is a wall too.
	var drop_at := _ground_ahead(xf, v)
	if drop_at < INF:
		free[0] = minf(free[0], drop_at / reach)
	var add := 0.0
	var top := INF
	# Something to one side: ease away from it (the near rays count more).
	var left := (1.0 - free[1]) + (1.0 - free[3]) * 0.6
	var right := (1.0 - free[2]) + (1.0 - free[4]) * 0.6
	add += (right - left) * 0.35
	if free[0] < 1.0:
		var room := free[0] * reach - 2.5
		top = sqrt(2.0 * brake_accel * maxf(room, 0.0))
		# Round it on the clearer side.
		var lside := free[1] + free[3]
		var rside := free[2] + free[4]
		add += (0.5 if lside > rside else -0.5) * (1.0 - free[0])
		if maxf(lside, rside) > 1.2 and drop_at == INF and room > 0.5:
			top = maxf(top, 2.0) # creep round it rather than stop dead
	return Vector2(add, top)


## How far ahead the ground stops being drivable (a drop of more than a
## metre or so, or water), or INF.
func _ground_ahead(xf: Transform3D, v: float) -> float:
	var space := car.get_world_3d().direct_space_state
	var last := xf.origin.y
	for d: float in [4.0, 4.0 + v * 0.6]:
		var p := xf * Vector3(0.0, 0.0, -_half_len - d)
		if terrain != null and terrain.h2(_flat(p)) < Terrain.WATER_Y + 0.3 and _off_street(_flat(p)) > 0.0:
			return d
		_ground_ray.from = p + Vector3.UP * 2.5
		_ground_ray.to = p + Vector3.DOWN * 3.0
		var h := space.intersect_ray(_ground_ray)
		if h.is_empty():
			continue # nothing built there yet: can't tell
		var gy := (h["position"] as Vector3).y
		if gy < last - 1.2 - d * 0.15:
			return d
		last = gy
	return INF


## Can we see it: a line from our roof to its, clear of buildings.
func _can_see(who: Node3D) -> bool:
	var space := car.get_world_3d().direct_space_state
	var ex: Array[RID] = [car.get_rid()]
	if who is CollisionObject3D:
		ex.append((who as CollisionObject3D).get_rid())
	# Its middle, and over the top of it (a low wall, a rise, a parked car
	# can hide the one and not the other).
	for h: Vector2 in [Vector2(1.3, 1.0), Vector2(1.6, 1.6)]:
		var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3.UP * h.x, who.global_position + Vector3.UP * h.y, Layers.SOLID)
		q.exclude = ex
		if space.intersect_ray(q).is_empty():
			return true
	return false


## Open ground straight to a point: nothing solid along a car-wide strip,
## and ground to drive on all the way (no big steps, no water).
func _line_clear(from: Vector2, to: Vector2) -> bool:
	var space := car.get_world_3d().direct_space_state
	var d := to - from
	var n := d.normalized()
	var side := Vector2(-n.y, n.x) * (_half_wid + 0.3)
	var y0 := car.global_position.y + 0.8
	var y1 := (target.global_position.y + 0.8) if target != null else y0
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.SOLID
	q.exclude = [car.get_rid()]
	for o: Vector2 in [Vector2.ZERO, side, -side]:
		q.from = Vector3(from.x + o.x, y0, from.y + o.y)
		q.to = Vector3(to.x + o.x, y1, to.y + o.y)
		if not space.intersect_ray(q).is_empty():
			return false
	var last := car.global_position.y
	var steps := int(d.length() / 6.0)
	for i in range(1, steps + 1):
		var p := from + n * (i * 6.0)
		if terrain != null and terrain.h2(p) < Terrain.WATER_Y + 0.3 and _off_street(p) > 0.0:
			return false
		_ground_ray.from = Vector3(p.x, last + 4.0, p.y)
		_ground_ray.to = Vector3(p.x, last - 4.0, p.y)
		var h := space.intersect_ray(_ground_ray)
		if h.is_empty():
			return false
		var gy := (h["position"] as Vector3).y
		if absf(gy - last) > 1.5:
			return false
		last = gy
	return true


## How far p is outside the nearest street's curb (0 on the road).
func _off_street(p: Vector2) -> float:
	var hit := network.nearest_on_streets(p, 60.0)
	if hit.is_empty():
		return 60.0
	return maxf(0.0, float(hit["dist"]) - (hit["edge"] as RoadNetwork.RoadEdge).half_width)


## A K-turn: forward on full lock toward the way on, back on the opposite
## lock when something's in front, until it points the right way. Starting
## with its nose against something, it backs out first, straighter, the
## way it came.
func _k_turn(alpha: float) -> void:
	state = "turn"
	_turn_time += get_physics_process_delta_time()
	var space := car.get_world_3d().direct_space_state
	var xf := car.global_transform
	_ray.exclude = [car.get_rid()]
	if _turning == 0:
		_turn_time = 0.0
		_turn_from = car.global_position
		_turn_first = _front_blocked(xf, 2.5)
		_turning = -1 if _turn_first else 1
	if absf(alpha) < deg_to_rad(45.0):
		_turning = 0
		return
	if _turning == 1:
		var blocked := _front_blocked(xf, 3.0) or _ground_ahead(xf, 0.0) < 4.5
		var jammed := _turn_time > 1.0 and absf(car.speed) < 0.3
		if (blocked or jammed or _turn_time > 4.0) and _turn_time > 0.6:
			_turning = -1
			_turn_time = 0.0
			_turn_from = car.global_position
			return
		steer = signf(alpha)
		_pedals(2.5, car.speed)
	else:
		_ray.from = xf * Vector3(0.0, 0.7, _half_len - 0.3)
		_ray.to = xf * Vector3(0.0, 0.7, _half_len + 2.5)
		var blocked := not space.intersect_ray(_ray).is_empty()
		# Not going back at all (caught on something): forward again.
		var jammed := _turn_time > 1.0 and absf(car.speed) < 0.3
		var far_enough := _turn_first and car.global_position.distance_to(_turn_from) > 4.5
		if (blocked or jammed or far_enough or _turn_time > 3.0) and _turn_time > 0.6:
			_turning = 1
			_turn_first = false
			_turn_time = 0.0
			return
		steer = -signf(alpha) * (0.5 if _turn_first else 1.0)
		_reverse_pedals(3.5 if _turn_first else 2.5)


## Something solid within `reach` of the front bumper, straight ahead or to
## either side of it.
func _front_blocked(xf: Transform3D, reach: float) -> bool:
	var space := car.get_world_3d().direct_space_state
	_ray.exclude = [car.get_rid()]
	for x: float in [-1.0, 0.0, 1.0]:
		_ray.from = xf * Vector3(x * _half_wid * 0.8, 0.7, -_half_len + 0.3)
		_ray.to = xf * Vector3(x * (_half_wid * 0.8 + 0.8), 0.7, -_half_len - reach)
		if not space.intersect_ray(_ray).is_empty():
			return true
	return false


func _reverse_pedals(want: float) -> void:
	handbrake = false
	var v := -car.speed
	if car.speed > 0.6:
		throttle = 0.0
		brake = 0.6
		return
	throttle = 0.0
	brake = clampf(0.3 + (want - v) * 0.3, 0.0, 0.8)


## Stuck (pushing against something and going nowhere): back out.
func _check_stuck(delta: float) -> void:
	if _recover > 0.0:
		return
	if (throttle > 0.3 and absf(car.speed) < 0.7 and _turning == 0) or (_turning != 0 and absf(car.speed) < 0.3 and _turn_time > 1.5):
		_stuck += delta
	else:
		_stuck = maxf(0.0, _stuck - delta * 2.0)
	if _stuck > 1.0:
		_start_recover(-steer if absf(steer) > 0.2 else 1.0)


## Back out for a moment with the wheel the other way, then go again,
## steering round whatever it was. Stuck again in the same place, it backs
## further and tries the other side.
func _start_recover(steer_back: float) -> void:
	_stuck = 0.0
	_blocked = 0.0
	_turning = 0
	recoveries += 1
	var here := car.global_position
	if _recover_at != Vector3.INF and here.distance_to(_recover_at) < 5.0 and _recover_t < 15.0:
		_streak += 1
	else:
		_streak = 0
	_recover_at = here
	_recover_t = 0.0
	var side := signf(steer_back) if steer_back != 0.0 else 1.0
	if _streak % 2 == 1:
		side = -side
	if civil != null and route != null and not route.is_empty():
		# Civil: always back so the nose swings toward the lane (not
		# whichever side worked last), to get out from behind a parked car.
		var me := _flat(car.global_position)
		var to := route.sample(route.project(me, along) + 6.0) - me
		var fwd := _fwd2()
		var left := to.dot(Vector2(fwd.y, -fwd.x))
		if absf(left) > 0.8:
			side = -signf(left)
	_recover = minf(2.4 + 0.9 * _streak, 4.5)
	_recover_steer = side
	# Backing with the wheel one way swings the nose the other: carry on
	# that way going forward.
	_bias = -side * 0.6


func _do_recover(delta: float) -> void:
	_recover -= delta
	# Jammed so it won't back either (a bumper caught on a corner): rock it,
	# a moment forward on the other lock, then back again.
	_wiggle_time -= delta
	if _wiggle_time > 0.0:
		state = "wiggle"
		steer = -_recover_steer
		_pedals(2.0, car.speed)
		throttle = maxf(throttle, 0.6)
		return
	state = "reverse"
	steer = _recover_steer
	_recover_still = _recover_still + delta if absf(car.speed) < 0.3 else 0.0
	if _recover_still > 0.8:
		_recover_still = 0.0
		_wiggle_time = 0.6
		_recover = maxf(_recover, 1.2)
	# Backing into something: stop backing.
	var xf := car.global_transform
	_ray.exclude = [car.get_rid()]
	_ray.from = xf * Vector3(0.0, 0.7, _half_len - 0.3)
	_ray.to = xf * Vector3(0.0, 0.7, _half_len + 1.2)
	if _recover < 2.0 and not car.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty():
		_recover = 0.0
	_reverse_pedals(3.0)
	if _recover <= 0.0:
		_recover = 0.0
		_bias_time = 1.2 + 0.4 * _streak
		_replan_now()
		_replan = 0.5


# --- helpers -------------------------------------------------------------------

func _fwd2() -> Vector2:
	var f := -car.global_basis.z
	return Vector2(f.x, f.z).normalized()


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## A body's velocity, or Vector3.INF for something that hasn't one (a
## person moved by code), to be measured instead.
static func _velocity_of(n: Node3D) -> Vector3:
	if n is RigidBody3D:
		return (n as RigidBody3D).linear_velocity
	if n is CharacterBody3D:
		return (n as CharacterBody3D).velocity
	if n is RoadFollower:
		return (n as RoadFollower).velocity
	return Vector3.INF


## Which way it's heading: a car's nose, else the way it's moving.
static func _heading_of(n: Node3D, vel: Vector2) -> Vector2:
	if (n is Car or n is RoadFollower) or vel.length() < 0.5:
		var f := -n.global_basis.z
		return Vector2(f.x, f.z).normalized()
	return vel.normalized()

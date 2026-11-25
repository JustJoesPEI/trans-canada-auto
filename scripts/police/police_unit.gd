class_name PoliceUnit
extends Node
## One police vehicle and the two officers in it (docs/design.md section
## 7). The dispatcher gives it a role and a place; this carries it out.
##
## Far from the player it's virtual: a RoadFollower moving along the
## streets with no physics, costing next to nothing. Near the player
## (PoliceDispatcher.HANDOVER) it's a real Car driven by a CarAutopilot,
## with its two Officers in the seats; far again and out of sight, it goes
## back to being a follower.
##
## Roles:
##   PATROL     drive the beat legally: cruise speed, one-way streets, and
##              stop at red lights (TrafficSignal.lamp_at)
##   RESPOND    go to a place by road, siren on (the streets only)
##   CHASE      follow the target: CarAutopilot's AUTO chase (by road from
##              far, off the road after it up close), PIT at level 3 and
##              up, boxing in a slow car
##   BLOCK      get ahead to where the target's heading and wait there;
##              box it in when it's slow; throw a paint strip (level 3)
##   FLANK      run the parallel street to a junction beside its way
##   SPOT       hang back and keep it in sight
##   SEARCH     drive slowly to a search point, lights on
##   ROADBLOCK  parked across a street, officers out beside it
##   LEAVE      done here: drive off, and be removed out of sight
##
## Officers get out when the target's on foot (level 2 and up), when the
## target's car has stalled, or when this car stalls under paint; they
## fight as a pair (one pinning from cover behind the car, one flanking)
## and get back in to chase a car that drives off, if theirs still runs.

enum Role { PATROL, RESPOND, CHASE, BLOCK, FLANK, SPOT, SEARCH, ROADBLOCK, LEAVE }
const ROLE_NAMES := ["patrol", "respond", "chase", "block", "flank", "spot", "search", "roadblock", "leave"]

## The model and livery each force drives.
const MODELS := {"city": ["jaunt", "cps"], "fip": ["tahoma", "fip"], "tactical": ["paint_tank", "fip_tactical"]}
## Speeds (km/h). Patrolling, a little under the limit; responding or
## searching (the follower's speed far off); and the chase top speed: the
## city's cruisers no faster than an ordinary car, the FIP's SUVs as quick
## as a fast car (design.md, "Difficulty targets"). Never more when they're
## behind: no rubber-banding.
const CRUISE := {"city": 45.0, "fip": 60.0, "tactical": 40.0}
const SEARCH_KMH := 38.0
const RESPOND_KMH := {"city": 80.0, "fip": 100.0, "tactical": 80.0}
## Heading you off (blockers, flankers): racing to be there first.
const BLOCK_KMH := {"city": 105.0, "fip": 135.0, "tactical": 80.0}
## A blocker waiting at its junction pulls out when you're this close (m)
## and coming its way, into your street this far (m) up from the junction.
const PULL_OUT_RANGE := 150.0
const PULL_OUT_AHEAD := 14.0
const CHASE_KMH := {"city": 110.0, "fip": 150.0, "tactical": 95.0}
## At level 2 (the city's own chase): no faster than this, and round the
## corners at this lateral m/s² (the autopilot's corner_accel; 5.5 above).
const L2_CHASE_KMH := 100.0
## At level 1 (one cruiser answering a call) no faster than this.
const L1_CHASE_KMH := 88.0
const L2_CORNER_ACCEL := 4.6
## Officers' aim: the miss in radians, by level (design.md: "At level 3 and
## up they aim well").
const AIM_ERROR := [0.05, 0.05, 0.04, 0.022, 0.018]
## The passenger leans out from level 3 within this of the target's car (m).
const LEAN_RANGE := 32.0
## Leaning out, they fire this many a second and miss this many times as
## widely as on foot (a moving car, one hand on the roof). Tuned so a car
## takes a couple of minutes of close chasing to stall, not seconds.
const LEAN_RATE := 0.8
const LEAN_MISS := 4.5
const LEAN_CAP := 0.8
## PIT: from level 3, closer than this behind the target, above
## CarAutopilot.pit_min_kmh, no more often than every PIT_COOLDOWN s.
const PIT_RANGE := 22.0
const PIT_COOLDOWN := 14.0
## Box in a car slower than this (km/h) within BOX_RANGE m.
const BOX_KMH := 8.0
const BOX_RANGE := 35.0
## Get out to go after someone on foot within this (m), from level 2.
const DISMOUNT_RANGE := 45.0
## Red lights: look this far ahead along the route for a junction with
## signals (m), and stop this far short of its middle.
const SIGNAL_LOOK := 60.0

var dispatcher: PoliceDispatcher
var force := "city"
var number := 0
var role := Role.PATROL
## Where the role is going (RESPOND, BLOCK, FLANK, SEARCH, PATROL, LEAVE).
var goal := Vector3.INF
## When the goal was last given (dispatcher clock), and arrived there.
var goal_time := 0.0
var arrived := false
## The junction this blocker has pulled out at (INF: none yet).
var _pulled_for := Vector3.INF
var _height_check := 1.0
var _height_fixed_at := -100.0
var follower: RoadFollower = null
var car: Car = null
var pilot: CarAutopilot = null
var officers: Array[Officer] = []
## Officers still in (not painted out), counted while virtual too.
var crew_left := 2
## Both officers out: it no longer counts toward the level's force.
var spent := false
## Officers are out of the car.
var dismounted := false
## Someone in this unit can see the target now (the dispatcher's sight
## check sets it).
var sees := false
## The chase level now (the dispatcher sets it).
var level := 0
## This car is part of a roadblock.
var roadblock: Node = null
## The tactical unit's cannon (a PaintTank), when this is the tank.
var tank: Node = null
## Seconds its real car has been stuck getting nowhere (not waiting on
## purpose): the dispatcher hands a long-stuck one back to a follower.
var stuck_time := 0.0
## Stays a follower until this (dispatcher clock): handed back for being
## stuck, it drives on before it's a real car again.
var virtual_until := 0.0
## Lights off until this clock (a stakeout waiting at a way out).
var quiet_until := 0.0
## A cut-off counted for this blocker's current junction (stats).
var cutoff_counted := false
## Overshooting a turn (a mistake) until this clock: straight on, then back.
var _overshoot_until := -1.0
var _pit_cool := 0.0
var _pit_yaw := 0.0
var _pit_spun := false
var _pit_time := -1.0
var _box := false
var _applied := -1
var _applied_goal := Vector3.INF
var _applied_target: Node3D = null
var _signal_check := 0.0
var _stall_said := false


func _init(the_force := "city", the_number := 0) -> void:
	force = the_force
	number = the_number
	name = "Unit_%s_%d" % [force, number]


func role_name() -> String:
	return ROLE_NAMES[role]


## Where it is.
func position() -> Vector3:
	if car != null:
		return car.global_position
	if follower != null:
		return follower.global_position
	for o in officers:
		if is_instance_valid(o):
			return o.global_position
	return Vector3.INF


## How it's moving (m/s).
func velocity() -> Vector3:
	if car != null:
		return car.linear_velocity
	if follower != null:
		return follower.velocity
	return Vector3.ZERO


func is_physical() -> bool:
	return car != null


## Counts toward the level's force: it has officers in and isn't leaving.
func active() -> bool:
	return not spent and role != Role.LEAVE and roadblock == null


## Officers on foot and still in.
func foot_officers() -> Array[Officer]:
	var out: Array[Officer] = []
	for o in officers:
		if is_instance_valid(o) and o.state == Officer.State.ON_FOOT:
			out.append(o)
	return out


# --- being virtual or real ------------------------------------------------------------------

## Start far off, moving along the streets from `at` facing `dir`.
func start_virtual(at: Vector2, dir: Vector2, parent: Node) -> void:
	follower = RoadFollower.new()
	follower.name = "Follower"
	follower.network = dispatcher.network
	follower.terrain = dispatcher.terrain
	parent.add_child(follower)
	# Far off with no road manners of its own: traffic doesn't wait for it
	# (it would give way to a ghost), as it doesn't wait for traffic.
	follower.remove_from_group("road_followers")
	follower.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), Vector3(at.x, dispatcher.terrain.h2(at), at.y))
	_applied = -1


## Become a real car where the follower is, moving as it was.
func make_physical(parent: Node) -> void:
	if car != null or follower == null:
		return
	var c := _new_car()
	pilot = follower.hand_over(c, parent)
	follower = null
	car = c
	# The follower rides the terrain's height, which can be metres off the
	# street (a cut, an embankment): stand the car on what's really there,
	# ground just under it first (so under a bridge it stays on the street
	# below), else ground above it (it came out under the road).
	var o := c.global_position
	var space := c.get_world_3d().direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.8, o + Vector3.DOWN * 8.0, Layers.GROUND))
	if h.is_empty():
		h = space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 8.0, o + Vector3.UP * 0.8, Layers.GROUND))
	if not h.is_empty() and absf((h["position"] as Vector3).y + 0.35 - o.y) > 1.5:
		c.global_position = Vector3(o.x, (h["position"] as Vector3).y + 0.35, o.z)
		c.reset_physics_interpolation()
	_setup_car()
	_applied = -1


## Become a real car standing at `xf` (roadblocks, tests).
func place_physical(xf: Transform3D, parent: Node) -> void:
	var c := _new_car()
	parent.add_child(c)
	c.global_transform = xf
	c.reset_physics_interpolation()
	pilot = CarAutopilot.new()
	pilot.name = "Autopilot"
	pilot.network = dispatcher.network
	c.add_child(pilot)
	pilot.stop()
	car = c
	_setup_car()
	_applied = -1


func _new_car() -> Car:
	var m: Array = MODELS[force]
	var c := Car.new()
	c.model_id = m[0]
	c.livery = m[1]
	c.unit = number
	c.paint = Color.from_string(str(CarModels.LIVERIES[m[1]]["colour"]), Color.WHITE)
	c.name = "Police_%s_%d" % [force, number]
	return c


func _setup_car() -> void:
	car.add_to_group("police_vehicles")
	car.set_meta("police_unit", self)
	pilot.chase_speed_kmh = CHASE_KMH[force] if level >= 3 or force == "city" else CHASE_KMH["city"]
	pilot.cruise_speed_kmh = CRUISE[force]
	officers.clear()
	for i in crew_left:
		var o := Officer.new()
		o.force = "city" if force == "city" else "fip"
		o.number = number
		o.name = "Officer_%s_%d_%d" % [force, number, i]
		o.went_out.connect(_on_officer_out.bind(o))
		o.done.connect(_on_officer_done.bind(o))
		car.seat.add_child(o)
		o.sit_in(car, i == 1)
		officers.append(o)
	if force == "tactical":
		var t := PaintTank.new()
		t.unit = self
		car.add_child(t)
		tank = t


## Back to a follower where the car is (far off and out of sight). Only
## with everyone in their seats.
func make_virtual(parent: Node) -> bool:
	if car == null or dismounted:
		return false
	for o in officers:
		if is_instance_valid(o) and o.state != Officer.State.SEATED:
			return false
	var xf := car.global_transform
	follower = RoadFollower.new()
	follower.name = "Follower"
	follower.network = dispatcher.network
	follower.terrain = dispatcher.terrain
	parent.add_child(follower)
	# Far off with no road manners of its own: traffic doesn't wait for it
	# (it would give way to a ghost), as it doesn't wait for traffic.
	follower.remove_from_group("road_followers")
	var f := -xf.basis.z
	follower.global_transform = Transform3D(Basis(Vector3.UP, atan2(-f.x, -f.z)), xf.origin)
	follower.speed = maxf(car.speed, 0.0)
	for o in officers:
		if is_instance_valid(o):
			o.queue_free()
	officers.clear()
	car.queue_free()
	car = null
	pilot = null
	tank = null
	_applied = -1
	if stuck_time > 0.0:
		virtual_until = dispatcher.clock + 8.0
	stuck_time = 0.0
	return true


## Remove everything (out of sight, done).
func remove() -> void:
	for o in officers:
		if is_instance_valid(o):
			o.queue_free()
	officers.clear()
	if car != null and is_instance_valid(car):
		car.queue_free()
	if follower != null and is_instance_valid(follower):
		follower.queue_free()
	car = null
	follower = null
	queue_free()


# --- orders ---------------------------------------------------------------------------------

## Give it a role, a place to go and (for CHASE, SPOT, BLOCK) who to chase.
func order(r: Role, where := Vector3.INF, now := 0.0) -> void:
	if now < _overshoot_until and r == Role.CHASE:
		return # still overshooting the turn it missed
	var moved := where != goal and (where == Vector3.INF or goal == Vector3.INF or where.distance_to(goal) > 25.0)
	if moved:
		cutoff_counted = false
	if r != role or moved:
		arrived = false
		goal_time = now
	role = r
	goal = where


## Missed the turn: carry straight on for a few seconds, then back to it.
func overshoot(now: float) -> void:
	if car == null:
		return
	var f := -car.global_basis.z
	var ahead := car.global_position + Vector3(f.x, 0.0, f.z).normalized() * 60.0
	role = Role.RESPOND
	goal = ahead
	_applied = -1
	_overshoot_until = now + 4.0


## Carry out the role (called every physics step by the dispatcher).
func step(delta: float, target: Node3D) -> void:
	_pit_cool -= delta
	if car != null and not is_instance_valid(car):
		car = null
		pilot = null
	if follower != null:
		_step_virtual(target)
	elif car != null:
		_step_physical(delta, target)
	elif not officers.is_empty():
		_step_foot(delta, target)


func _step_virtual(target: Node3D) -> void:
	var f := follower
	var r := role
	if r == Role.CHASE or r == Role.SPOT:
		# Far off: head for where it is, by road.
		var p := dispatcher.known_position()
		if goal == Vector3.INF or p.distance_to(goal) > 40.0:
			goal = p
	if _applied != r or _applied_goal == Vector3.INF or (goal != Vector3.INF and goal.distance_to(_applied_goal) > 30.0) or (not f.moving and not arrived):
		_applied = r
		_applied_goal = goal
		f.obey_oneway = r == Role.PATROL or r == Role.LEAVE
		match r:
			Role.PATROL, Role.LEAVE:
				f.speed_kmh = CRUISE[force]
			Role.SEARCH:
				f.speed_kmh = SEARCH_KMH
			Role.BLOCK, Role.FLANK:
				f.speed_kmh = BLOCK_KMH[force]
			_:
				f.speed_kmh = RESPOND_KMH[force]
		if goal != Vector3.INF:
			f.go_to(goal)
			if not f.moving:
				arrived = true
	if goal != Vector3.INF and not f.moving and f.route != null:
		arrived = true
	# Patrols keep to the lights even far off.
	if r == Role.PATROL and f.route != null and f.moving:
		_signal_check -= get_physics_process_delta_time()
		if _signal_check <= 0.0:
			_signal_check = 0.25
			f.hold_at = _red_light_ahead(f.route, f.along)


func _step_physical(delta: float, target: Node3D) -> void:
	var trying := pilot != null and pilot.mode != CarAutopilot.Mode.IDLE and not dismounted and role != Role.ROADBLOCK \
			and not (pilot.civil != null and pilot.civil.holding) and pilot.state not in ["hold", "stopped_behind", "respond_wait", "arrived", "hold_line"]
	stuck_time = stuck_time + delta if trying and absf(car.speed) < 1.0 else 0.0
	_height_check -= delta
	if _height_check <= 0.0:
		_height_check = 1.0
		_keep_on_ground()
	if car.stalled and not dismounted:
		dismount()
		if not _stall_said:
			_stall_said = true
			dispatcher.radio_say("vehicle_stalled", self)
	if dismounted:
		_step_foot(delta, target)
		return
	_lights()
	var tcar := target as Car
	var tpos := target.global_position if target != null else Vector3.INF
	var dist := car.global_position.distance_to(tpos) if target != null else INF
	# Off after someone on foot, or a stalled car (they rush you).
	if target != null and level >= 2 and dist < DISMOUNT_RANGE and sees and (tcar == null or tcar.stalled) and role != Role.ROADBLOCK:
		if absf(car.speed) < 3.0 or dist < 14.0:
			dismount()
			if tcar == null:
				dispatcher.radio_say("on_foot", self)
			return
		# Pull up near them first.
		pilot.chase_mode = CarAutopilot.ChaseMode.PURSUIT
	_lean(target, tcar, dist)
	match role:
		Role.ROADBLOCK:
			if _applied != role:
				_applied = role
				pilot.stop()
				dismount()
		Role.CHASE, Role.SPOT:
			_drive_chase(target, tcar, dist)
		Role.BLOCK:
			if tcar != null and dist < BOX_RANGE and absf(tcar.speed) * 3.6 < (BOX_KMH * 2.0 if _box else BOX_KMH) and sees:
				_drive_box(tcar)
			elif _pull_out(target, dist):
				pass
			else:
				_drive_to_goal(BLOCK_KMH[force], false)
		Role.FLANK:
			_drive_to_goal(BLOCK_KMH[force], false)
		Role.RESPOND:
			_drive_to_goal(RESPOND_KMH[force], false)
		Role.SEARCH:
			_drive_to_goal(SEARCH_KMH, false)
		Role.PATROL, Role.LEAVE:
			_drive_to_goal(CRUISE[force], true)
	_manners(role == Role.PATROL or role == Role.LEAVE)


## Road manners on patrol (or driving off after a chase): the town's civil
## driving layer (CivilDriving: lights, stop signs, giving way, a safe gap),
## and off for everything with the siren on.
func _manners(on: bool) -> void:
	if on and pilot.civil == null:
		var c := pilot.use_civil_driving(true)
		c.pulls_over = false # a police car doesn't pull over for its own kind
		c.speed_factor = 0.95
	elif not on and pilot.civil != null:
		pilot.use_civil_driving(false)
	pilot.hold_at = -1.0


func _drive_to_goal(kmh: float, legal: bool) -> void:
	if goal == Vector3.INF:
		if pilot.mode != CarAutopilot.Mode.IDLE:
			pilot.stop()
		return
	pilot.cruise_speed_kmh = kmh
	pilot.obey_oneway = legal
	# A call at level 1 is answered along the streets (no cutting across
	# lots and lawns for a paintball complaint).
	pilot.chase_mode = CarAutopilot.ChaseMode.RESPOND if level <= 1 and role == Role.RESPOND else CarAutopilot.ChaseMode.AUTO
	var redo := _applied != role or _applied_goal == Vector3.INF or goal.distance_to(_applied_goal) > 20.0 or pilot.mode != CarAutopilot.Mode.DRIVE
	if redo:
		_applied = role
		_applied_goal = goal
		_box = false
		arrived = false
		pilot.drive_to(goal)
		if not pilot.arrived.is_connected(_on_arrived):
			pilot.arrived.connect(_on_arrived)


## Under the ground (fell through, or came out under it), or resting well
## above it on something it shouldn't be on: back onto the ground where it
## is. Checked once a second; a car in the air from a bump is left alone
## (it's moving up or down).
func _keep_on_ground() -> void:
	if car == null or car.freeze:
		return
	# Not again straight after one (two surfaces stacked, a deck over a
	# lower lot, mustn't bounce it between them).
	if dispatcher.clock - _height_fixed_at < 5.0:
		return
	var o := car.global_position
	var space := car.get_world_3d().direct_space_state
	var above := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 10.0, o + Vector3.UP * 0.3, Layers.GROUND))
	var below := space.intersect_ray(PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.3, o + Vector3.DOWN * 12.0, Layers.GROUND))
	var put := Vector3.INF
	if not above.is_empty() and below.is_empty():
		put = above["position"] # under the road
	elif not below.is_empty() and o.y - (below["position"] as Vector3).y > 2.5 and absf(car.linear_velocity.y) < 0.5:
		# Well above the ground and not moving up or down: fine if it's on
		# something real (a raised lot, a deck), wrong if it's on nothing.
		var q := PhysicsRayQueryParameters3D.create(o + Vector3.UP * 0.3, o + Vector3.DOWN * 1.6, Layers.SOLID | Layers.GROUND | Layers.VEHICLES)
		q.exclude = [car.get_rid()]
		var under := space.intersect_ray(q)
		if under.is_empty():
			put = below["position"]
		elif under["collider"] is Car or (under["collider"] as Node).is_in_group("parked_cars"):
			# Up on another car (a pile-up): off to the side of it, onto the
			# ground, not dropped into it.
			var other := under["collider"] as Node3D
			var side := car.global_position - other.global_position
			side.y = 0.0
			side = side.normalized() if side.length() > 0.1 else car.global_basis.x
			var to := o + side * 3.5
			var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(to + Vector3.UP * 3.0, to + Vector3.DOWN * 12.0, Layers.GROUND))
			if not g.is_empty():
				print("POLICE height_fix %s (%s) was up on %s at (%.0f, %.0f), state %s: moved off to the side" % [name, role_name(), other.name, o.x, o.z, pilot.state if pilot != null else "-"])
				_height_fixed_at = dispatcher.clock
				car.global_position = (g["position"] as Vector3) + Vector3.UP * 0.4
				car.linear_velocity = Vector3.ZERO
				car.reset_physics_interpolation()
				dispatcher.stats["height_fixes"] = int(dispatcher.stats.get("height_fixes", 0)) + 1
			return
	if put == Vector3.INF:
		return
	var pp := dispatcher.player.global_position if dispatcher.player != null else Vector3.ZERO
	print("POLICE height_fix %s (%s) at (%.0f, %.0f): %.1f m %s the ground, %.0f m from the player, state %s" % [
		name, role_name(), o.x, o.z, absf(o.y - put.y), "under" if put.y > o.y else "above", o.distance_to(pp), pilot.state if pilot != null else "-"])
	_height_fixed_at = dispatcher.clock
	car.global_position = Vector3(o.x, put.y + 0.4, o.z)
	car.linear_velocity = Vector3.ZERO
	car.reset_physics_interpolation()
	dispatcher.stats["height_fixes"] = int(dispatcher.stats.get("height_fixes", 0)) + 1


func _on_arrived() -> void:
	arrived = true


## A blocker at its junction with you coming: it pulls out into the street
## you're on, a few car lengths up from the junction, across your way (the
## cut-off). Once per junction. True while it's doing that.
func _pull_out(target: Node3D, dist: float) -> bool:
	if goal == Vector3.INF or target == null:
		return false
	if _pulled_for == goal:
		return true
	var at_junction := arrived or (car != null and car.global_position.distance_to(goal) < 30.0)
	if not at_junction or dist > PULL_OUT_RANGE or dist < 25.0:
		return false
	var tp := target.global_position
	var vel := PoliceDispatcher._velocity_of(target)
	var to_j := Vector2(goal.x - tp.x, goal.z - tp.z)
	if Vector2(vel.x, vel.z).length() < 4.0 or to_j.normalized().dot(Vector2(vel.x, vel.z).normalized()) < 0.6:
		return false
	var p2 := Vector2(goal.x, goal.z) - to_j.normalized() * PULL_OUT_AHEAD
	var hit := dispatcher.network.nearest_on_streets(p2, 15.0)
	if hit.is_empty():
		return false
	var q: Vector2 = hit["pos"]
	_pulled_for = goal
	_applied = role
	_applied_goal = goal
	pilot.cruise_speed_kmh = 40.0
	pilot.drive_to(Vector3(q.x, goal.y, q.y), true)
	dispatcher.stats["pull_outs"] = int(dispatcher.stats.get("pull_outs", 0)) + 1
	return true


func _drive_chase(target: Node3D, tcar: Car, dist: float) -> void:
	if target == null:
		return
	pilot.chase_speed_kmh = CHASE_KMH[force] if (level >= 3 or force == "city") else CHASE_KMH["city"]
	# Level 2 is the city's own: a shakeable tail. Softer round corners and
	# a bit slower flat out, so a decent driver loses it in a minute or two.
	pilot.corner_accel = L2_CORNER_ACCEL if level <= 2 else 5.5
	if level <= 2:
		pilot.chase_speed_kmh = minf(pilot.chase_speed_kmh, L2_CHASE_KMH if level == 2 else L1_CHASE_KMH)
	pilot.follow_gap = 40.0 if role == Role.SPOT else 9.0
	pilot.chase_mode = CarAutopilot.ChaseMode.AUTO
	# A PIT in progress: let it finish, then back to following.
	if _pit_time >= 0.0:
		_pit_time += get_physics_process_delta_time()
		if tcar != null and not _pit_spun and absf(angle_difference(_pit_yaw, tcar.global_rotation.y)) > 0.8:
			_pit_spun = true
			dispatcher.stats["pit_spins"] = int(dispatcher.stats["pit_spins"]) + 1
		if _pit_time > 6.0 or pilot.mode != CarAutopilot.Mode.PIT:
			_pit_time = -1.0
			_applied_target = null
		else:
			return
	if tcar != null and role == Role.CHASE:
		var tk := absf(tcar.speed) * 3.6
		# The PIT is the FIP's (city cruisers box in and lean out).
		if level >= 3 and _pit_cool <= 0.0 and tk > pilot.pit_min_kmh and dist < PIT_RANGE and sees and force == "fip":
			var behind := (car.global_position - tcar.global_position).dot(-tcar.global_basis.z) < 0.0
			if behind:
				_pit_cool = PIT_COOLDOWN
				_pit_time = 0.0
				_pit_yaw = tcar.global_rotation.y
				_pit_spun = false
				pilot.pit(tcar)
				dispatcher.stats["pits"] = int(dispatcher.stats["pits"]) + 1
				dispatcher.radio_say("pit", self)
				return
		# Once boxing in, keep at it until it's really getting away (a nudge
		# from the box-in itself mustn't flip it back to following).
		if (tk < BOX_KMH or (_box and tk < BOX_KMH * 2.0)) and dist < BOX_RANGE and sees and level >= 1:
			_drive_box(tcar)
			return
	if _applied != role or _applied_target != target or pilot.mode != CarAutopilot.Mode.FOLLOW or _box:
		_applied = role
		_applied_target = target
		_box = false
		pilot.follow(target)


func _drive_box(tcar: Car) -> void:
	if not _box or pilot.mode != CarAutopilot.Mode.BOX_IN:
		_box = true
		_applied = role
		pilot.box_in(tcar)


## Lights and siren for the role.
func _lights() -> void:
	if car.police == null:
		return
	var want := PoliceGear.Mode.OFF
	match role:
		Role.RESPOND, Role.CHASE, Role.BLOCK, Role.FLANK, Role.SPOT:
			want = PoliceGear.Mode.SIREN
		Role.SEARCH, Role.ROADBLOCK:
			want = PoliceGear.Mode.LIGHTS
	if level == 0 and role != Role.ROADBLOCK:
		want = PoliceGear.Mode.OFF
	if dispatcher.clock < quiet_until:
		want = PoliceGear.Mode.OFF # staking out: dark, waiting
	if car.police.mode != want:
		car.police.set_mode(want)


## The passenger leans out and paints the target's car from level 3
## (design.md, "Level 3: the chase gets aggressive"): the windscreen first.
func _lean(target: Node3D, tcar: Car, dist: float) -> void:
	if officers.size() < 2:
		return
	var p := officers[1]
	if not is_instance_valid(p) or p.is_out():
		return
	# Only from a moving car (they don't hang out of a parked one), and not
	# past LEAN_CAP: leaning out softens a car up; the Paint Tank or
	# officers on foot finish it.
	var pc := tcar.get_node_or_null("PaintCoverage") as PaintCoverage if tcar != null else null
	var softened := pc != null and pc.police_coverage >= LEAN_CAP
	var want := level >= 3 and tcar != null and dist < LEAN_RANGE and sees and role != Role.ROADBLOCK \
			and absf(car.speed) > 3.0 and not softened
	if want and p.state == Officer.State.SEATED:
		p.lean_out(true)
		p.shoot_at = tcar
		p.aim_error = AIM_ERROR[level] * LEAN_MISS # from a moving car
		p.fire_rate = LEAN_RATE
		p.shoot_range = LEAN_RANGE + 4.0
		dispatcher.radio_say("leaning_out", self, 0.15)
	elif not want and p.state == Officer.State.LEANING:
		p.shoot_at = null
		p.lean_out(false)
	if p.state == Officer.State.LEANING:
		p.shoot_at = tcar


## Red light ahead along a route: the stop line's distance along it, or -1.
func _red_light_ahead(r: StreetRoute, along: float) -> float:
	if r == null or r.is_empty():
		return -1.0
	var net := dispatcher.network
	var me := r.sample(along)
	for nid: String in dispatcher.signals_near(me, SIGNAL_LOOK + 10.0):
		var c: Vector2 = net.nodes[nid]
		var d := r.project(c, along, SIGNAL_LOOK + 10.0)
		if d <= along + 2.0 or d > along + SIGNAL_LOOK:
			continue
		if r.sample(d).distance_to(c) > 6.0:
			continue # the route passes near it, not through it
		# The way in: the way we come from, out from the junction.
		var back := r.sample(maxf(d - 12.0, 0.0)) - c
		if back.length() < 1.0:
			continue
		# The way in we're on, as the junction knows it (its lights are hung
		# by the street's own direction there, which matters on a diagonal).
		var way := back.normalized()
		var best := -2.0
		for inc: RoadNetwork.Incident in net.incidents.get(nid, []):
			if inc.dir.dot(back.normalized()) > best:
				best = inc.dir.dot(back.normalized())
				way = inc.dir
		var phase := TrafficSignal.phase_of(way)
		if TrafficSignal.lamp_at(nid, phase) != 2:
			# Red or amber: stop short of the junction's mouth (amber only
			# if there's room to stop).
			var stop := d - 9.0
			var v := absf(car.speed) if car != null else (follower.speed if follower != null else 0.0)
			var room := stop - along
			if TrafficSignal.lamp_at(nid, phase) == 1 and room < v * v / (2.0 * 4.0):
				continue
			return stop
	return -1.0


# --- on foot --------------------------------------------------------------------------------

## Everyone out of the car.
func dismount() -> void:
	if dismounted:
		return
	dismounted = true
	if pilot != null:
		pilot.stop()
	if car != null and car.police != null:
		car.police.set_mode(PoliceGear.Mode.LIGHTS)
	for o in officers:
		if is_instance_valid(o) and not o.is_out():
			o.lean_out(false)
			o.get_out()


func _step_foot(_delta: float, target: Node3D) -> void:
	var on_foot := foot_officers()
	var tpos := target.global_position if target != null else Vector3.INF
	var tcar := target as Car
	var car_ok := car != null and is_instance_valid(car) and not car.stalled
	# The target drove off in a car: back in ours, if it still runs.
	if car_ok and tcar != null and not tcar.stalled and role != Role.ROADBLOCK and (absf(tcar.speed) > 6.0 or car.global_position.distance_to(tpos) > 40.0):
		var all_in := true
		for o in on_foot:
			o.shoot_at = null
			if o.global_position.distance_to(o.door_point()) < 1.6:
				o.get_in()
			else:
				o.move_to(o.door_point(), true)
				all_in = false
		if all_in:
			dismounted = false
			_applied = -1
		return
	if target == null:
		# Nobody to chase (the chase is over): back in the car if it runs.
		var all_back := true
		for o in on_foot:
			o.shoot_at = null
			if car_ok and role != Role.ROADBLOCK:
				if o.global_position.distance_to(o.door_point()) < 1.6:
					o.get_in()
				else:
					o.move_to(o.door_point(), false)
					all_back = false
			else:
				o.goal = Vector3.INF
				all_back = false
		if all_back and car_ok:
			dismounted = false
			_applied = -1
		return
	var seen := dispatcher.seen_recently()
	var err: float = AIM_ERROR[clampi(level, 0, 4)]
	var rush := tcar != null and tcar.stalled and dispatcher.player_in_car()
	var from := car.global_position if car != null and is_instance_valid(car) else (on_foot[0].global_position if not on_foot.is_empty() else tpos)
	var away := Vector3(from.x - tpos.x, 0, from.z - tpos.z)
	if away.length() < 0.5:
		away = Vector3.FORWARD
	away = away.normalized()
	var partner_out := on_foot.size() < 2
	for i in on_foot.size():
		var o := on_foot[i]
		o.aim_error = err
		o.fire_rate = 2.5 if level <= 2 else 3.5
		o.shoot_range = 34.0 if level <= 2 else 42.0
		o.shoot_at = target if (seen and level >= 1 and target != null) else null
		if target == null:
			o.goal = Vector3.INF
			continue
		if rush:
			# Their car's dead with them in it: straight to the door.
			var door := tcar.door_point()
			o.move_to(door + (o.global_position - door).normalized() * 0.8, true)
			continue
		if role == Role.ROADBLOCK:
			# Beside the roadblock, behind the cars, and not marksmen: a
			# roadblock is a hurdle, not an arrest.
			o.fire_rate = 1.5
			o.aim_error = err * 2.0
			if car != null and is_instance_valid(car):
				o.move_to(car.global_position + away * 2.8 + car.global_basis.x * (2.0 if i == 0 else -2.0), false)
			continue
		var hurt := o.body_paint.hits >= 2 and partner_out
		if hurt:
			# Losing: back off and wait for help.
			o.move_to(tpos + away * 30.0, true)
		elif i == 0:
			# Pinning: from cover behind the car, or at a steady range.
			if car != null and is_instance_valid(car) and car.global_position.distance_to(tpos) < 30.0:
				o.move_to(car.global_position + away * 2.6, true)
			else:
				o.move_to(tpos + away * 14.0, true)
		else:
			# Flanking: round to the side, then in closer.
			var side := away.rotated(Vector3.UP, deg_to_rad(75.0) * (1.0 if number % 2 == 0 else -1.0))
			var spot := tpos + side * 13.0
			if o.global_position.distance_to(spot) < 3.0:
				spot = tpos + side * 7.0
			o.move_to(spot, true)


func _on_officer_out(_by: Node, _o: Officer) -> void:
	crew_left = maxi(0, crew_left - 1)
	if crew_left == 0:
		spent = true
	dispatcher.officer_went_out(self)


func _on_officer_done(_o: Officer) -> void:
	pass

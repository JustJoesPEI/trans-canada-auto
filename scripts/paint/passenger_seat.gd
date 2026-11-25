class_name PassengerSeat
extends Node3D
## The front passenger seat of a car, and shooting from it (docs/design.md
## section 2, "Shooting from cars"): "You can't shoot while you're driving.
## A passenger can lean out and shoot at 0.5x the fire rate with wider
## spread." Made on demand as a child of the Car (`PassengerSeat.of(car)`),
## the driver's seat mirrored across the car.
##
## It holds one occupant and does everything that isn't input: leaning out
## of the window (eased over LEAN_TIME, and only while the car is upright),
## the pose (HumanoidModel.seated_lean: up on the sill, the body out and
## turned to the aim, the marker up), and firing the occupant's PaintMarker
## by the passenger's rules (RATE_MUL, SPREAD_MUL, wider again with the
## car's speed, only within ARC of straight out of the window so nobody
## paints their own roof). The driver's seat has none of this: the driver
## can't shoot.
##
## Who sits here sets three things each physics step: `wants_lean`,
## `aim_at` (a world point) and `trigger`. The player does it from input
## (PlayerController._ride). An officer driven by code (the Police piece)
## does the same from its own brain, e.g.:
##
##     var seat := PassengerSeat.of(cruiser)
##     seat.sit(officer, officer.model, officer.marker)  # officer: a Node3D
##     # each physics step, while the autopilot drives:
##     seat.wants_lean = can_see_suspect
##     seat.aim_at = suspect.global_position + Vector3.UP
##     seat.trigger = seat.ready_to_fire() and rng.randf() < 0.6
##     # getting out:
##     seat.leave()
##     officer.reparent(world)
##
## `sit` puts the person on the seat (reparents them here); `leave` lets go
## of them and puts their pose and marker back as they were; the caller
## puts them back in the world and turns their own collision and movement
## off and on, as PlayerController does. The person's marker must have the
## person as its `shooter`: shots then pass through the car they're in
## (PaintShots.own_bodies).

## Design: "0.5x the fire rate".
const RATE_MUL := 0.5
## "Wider spread", not a number in the design: twice the aimed spread,
## widening further with the car's speed (PaintMarker's RUN_SPREAD at
## SPEED_FOR_FULL_SPREAD).
const SPREAD_MUL := 2.0
const SPEED_FOR_FULL_SPREAD := 20.0 ## m/s (72 km/h)
## s to lean out (and back in).
const LEAN_TIME := 0.3
## How far round from straight out of the window the passenger can aim and
## fire (radians each way): out, forward to just past the bonnet's corner,
## back to just past the boot's. Not across the roof.
const ARC := 1.75
## Where the hips go leaning out, from the seat, in the seat's space:
## up onto the sill and out to the door (m, for a 1.75 m person).
const SILL_OUT := 0.46
const SILL_UP := 0.42
## A car tipped more than this (degrees) can't be leaned out of.
const MAX_TILT := 35.0

## The person in the seat, their look and their marker (null when empty).
var occupant: Node3D
var model: HumanoidModel
var marker: PaintMarker
## Set by whoever sits here, every physics step.
var wants_lean := false
var aim_at := Vector3.ZERO
var trigger := false
## 0 sitting, 1 leant right out (eased).
var lean := 0.0
## 1 for the right-hand seat (the passenger's), -1 for the left.
var side := 1.0

var _car: Node3D


## The car's passenger seat, made the first time it's asked for.
static func of(car: Node3D) -> PassengerSeat:
	var s := car.get_node_or_null("PassengerSeat") as PassengerSeat
	if s == null:
		s = PassengerSeat.new()
		s.name = "PassengerSeat"
		var driver_seat := car.get("seat") as Node3D
		if driver_seat != null:
			var p := driver_seat.position
			s.position = Vector3(-p.x, p.y, p.z)
			s.side = 1.0 if p.x < 0.0 else -1.0
		car.add_child(s)
	return s


## Where the passenger's door is (world space): the driver's, mirrored.
static func door_point(car: Node3D) -> Vector3:
	var shape: Dictionary = car.get("shape")
	var seat_z := float(shape["seat"][2])
	var seat_x := float(shape["seat"][0])
	return car.global_transform * Vector3(-signf(seat_x) * (float(shape["width"]) * 0.5 + 0.3), 0.0, seat_z)


func _ready() -> void:
	_car = get_parent() as Node3D


## Sit `person` here (reparented to the seat, feet where a seated person's
## feet go), with their model and marker.
func sit(person: Node3D, person_model: HumanoidModel, person_marker: PaintMarker) -> void:
	occupant = person
	model = person_model
	marker = person_marker
	lean = 0.0
	wants_lean = false
	trigger = false
	person.reparent(self, false)
	person.position = Vector3(0.0, -model.height / 1.75 * 0.93, 0.0)
	person.rotation = Vector3.ZERO
	if person.has_method("reset_physics_interpolation"):
		person.reset_physics_interpolation()
	model.seated = true
	model.seated_side = side
	model.seated_grips = []
	pose(model, self, 0.0, aim_at)


## Let go of the occupant: sitting straight, marker down and back to its
## own fire rules. The caller takes them out of the car.
func leave() -> void:
	if model != null:
		model.seated_lean = 0.0
		model.aim = 0.0
		model.position = Vector3.ZERO
		model.seated = false
		model.seated_feet = []
	if marker != null:
		marker.trigger = false
		marker.rate_mul = 1.0
		marker.spread_mul = 1.0
		marker.holding_throw = false
	occupant = null
	model = null
	marker = null
	lean = 0.0
	wants_lean = false
	trigger = false


## A clear spot to step out to, the passenger's side first.
func exit_transform() -> Transform3D:
	var car := _car
	var shape: Dictionary = car.get("shape")
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	q.shape = capsule
	q.collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	q.exclude = [(car as CollisionObject3D).get_rid()] if car is CollisionObject3D else []
	var local := Vector3(side * (float(shape["width"]) * 0.5 + 0.5), 0.0, float(shape["seat"][2]))
	var p := car.global_transform * local
	q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
	if space.intersect_shape(q, 1).is_empty():
		return Transform3D(Basis(Vector3.UP, car.global_basis.get_euler().y), p + Vector3.UP * 0.3)
	return car.call("exit_transform")


## True when leant out and the aim is within the window's arc: a shot now
## would go.
func ready_to_fire() -> bool:
	return lean >= 0.95 and in_arc(aim_at)


## Is a world point within the arc a passenger can shoot at?
func in_arc(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	if Vector2(local.x, local.z).length() < 0.3:
		return false
	var yaw := atan2(-local.x, -local.z) # 0 ahead, left positive
	return absf(angle_difference(-side * PI * 0.5, yaw)) <= ARC


func _physics_process(delta: float) -> void:
	if occupant == null or model == null or not is_instance_valid(occupant):
		return
	var upright := _car == null or _car.global_basis.y.dot(Vector3.UP) > cos(deg_to_rad(MAX_TILT))
	var out := occupant.has_method("is_out") and bool(occupant.call("is_out"))
	lean = move_toward(lean, 1.0 if wants_lean and upright and not out else 0.0, delta / LEAN_TIME)
	pose(model, self, lean, aim_at)
	if marker == null:
		return
	marker.rate_mul = RATE_MUL
	marker.spread_mul = SPREAD_MUL
	marker.trigger = trigger
	var speed := 0.0
	if _car != null and "linear_velocity" in _car:
		speed = (_car.get("linear_velocity") as Vector3).length()
	marker.step(delta, not out and ready_to_fire(), lean > 0.5, lean, speed, SPEED_FOR_FULL_SPREAD, PaintMarker.muzzle_of(model), aim_at)
	model.reload = marker.reload_progress() if marker.is_visible_reload() else -1.0


## The passenger's pose at `amount` of the lean (0..1), aiming at `target`
## (world): the model up onto the window sill and turned to the target,
## the marker up, the feet on the floor. Works on any HumanoidModel sat in
## `seat` (its parent's parent, or its parent), the player's or an
## officer's.
static func pose(person_model: HumanoidModel, seat: Node3D, amount: float, target: Vector3) -> void:
	var e := smoothstep(0.0, 1.0, amount)
	var s := 1.0
	if seat is PassengerSeat:
		s = (seat as PassengerSeat).side
	var k := person_model.height / 1.75
	person_model.seated = true
	person_model.seated_side = s
	person_model.seated_lean = amount
	# The model (under its person, who sits at the seat) moves up and out.
	person_model.position = Vector3(s * SILL_OUT * k * e, SILL_UP * k * e, 0.0)
	person_model.aim = 1.0 if amount > 0.5 else 0.0
	var local := seat.global_transform.affine_inverse() * target
	person_model.seated_aim_yaw = atan2(-local.x, -local.z)
	var chest := Vector3(s * SILL_OUT * k, SILL_UP * k + 0.55 * k, 0.0)
	var d := local - chest
	person_model.aim_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	# Feet on the floor in front of the seat (the driver's spots mirrored);
	# leaning out, the legs fold in across the seat, so they stay inside
	# the door while the hips sit on the sill.
	var car := seat.get_parent() as Node3D
	if car != null and car.has_method("pedal_points"):
		var to_model := person_model.global_transform.affine_inverse() * car.global_transform
		var floor: Array = []
		for p: Vector3 in car.call("pedal_points"):
			floor.append(Vector3(-p.x, p.y, p.z))
		if floor.size() == 2:
			floor = [floor[1], floor[0]] # mirrored: the left foot is the right one's spot
			var sp := seat.position
			var feet: Array = []
			for f in 2:
				var tucked := Vector3(sp.x - s * 0.32 * k, sp.y + 0.02, sp.z - 0.3 * k + (0.14 if f == 0 else -0.14) * k * s)
				feet.append(to_model * (floor[f] as Vector3).lerp(tucked, e))
			person_model.seated_feet = feet

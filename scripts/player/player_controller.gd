class_name PlayerController
extends CharacterBody3D
## The player on foot: walk, run, turn, bump into things.
##
## Movement is relative to the camera, so "forward" is always into the
## screen. Controls are tight, for chases and paintball fights: you move
## the way you push straight away (no turning circle, no slowing to turn
## round), starts and stops take a few hundredths of a second, and the body
## snaps round to face the way you're going. Speed still eases in over a
## few frames, so the stride never pops. Physics interpolation (Project
## Settings) keeps it smooth on screens faster than the 60 Hz physics.
##
## Holding Aim raises a paintball marker over the shoulder: the person
## faces whatever is under the crosshair and walks, strafes or backs up
## at a steadier pace without turning away from it.
##
## The Fire input, while aiming, fires the marker (PaintMarker: the
## hopper, reloads, spread). Hits on the player go to BodyPaint: three and
## they're out (hands up, marker down, `is_out()`), and they wear off.
##
## In a car the player drives (no shooting) or rides in the passenger seat
## (PassengerSeat): hold Aim to lean out of the window, Fire to shoot, at
## the passenger's half fire rate and wider spread. Switch seats while
## stopped (main.gd).
##
## Height comes from a downward ray against the GROUND layer instead of floor
## physics, so curbs are stepped up smoothly and never catch the capsule.
## Walls, poles and cars are on SOLID and block normally.

@export_group("Speeds (m/s)")
@export var stroll_speed := 1.0 ## stick barely tilted
@export var walk_speed := 1.9 ## a brisk walk, keyboard or full stick
@export var run_speed := 5.8 ## hold Run
@export_group("Feel")
@export var accel := 55.0 ## m/s² speeding up or changing direction
@export var decel := 70.0 ## m/s² stopping when you let go
@export var turn_time := 0.045 ## seconds for the body to swing round to the way you're moving
@export_group("Aiming")
@export var aim_speed := 2.6 ## walking while aiming (m/s)
@export var aim_run_speed := 3.8 ## holding Run while aiming: a jog
@export_range(0.3, 1.0) var aim_back_factor := 0.8 ## backing up is this much slower
@export var aim_turn_time := 0.03 ## seconds to swing round onto the target
## Firing without aiming (hip fire): how long the body keeps facing the
## crosshair after the last pull, so a burst stays pointed the same way.
@export var hip_hold := 1.0
@export var hip_turn_time := 0.06 ## swinging round to the crosshair from the hip
@export_group("")
@export var gravity := 20.0
@export var step_height := 0.4 ## tallest step the player walks straight up
## This player's paint (one of PaintWeapons.COLOURS, chosen in the character
## creator and saved with the look: PlayerLook "paint").
@export var paint_colour := Color(0.0, 0.8, 0.72) # teal

## Painted out (BodyPaint): by is who did it. Whatever decides what comes
## next (an event's respawn, the Wanted piece) listens and calls
## `body_paint.revive()`.
signal went_out(by: Node)

## How far up the marker comes when firing from the hip (0..1 of the raise).
const HIP_RAISE := 0.85

## Set by main.gd. Movement uses its yaw.
var camera_rig: CameraRig
## When false the player ignores input (menus, sitting in a car).
var input_enabled := true
## Current ground speed (m/s).
var speed := 0.0
## 0..1, how much of a run this is (the camera widens its view with it).
var run_amount := 0.0
## True while Aim is held.
var aiming := false
## 0..1, eased in and out with aiming (the camera moves to the shoulder with it).
var aim_amount := 0.0
## What the crosshair is on, in the world, while aiming.
var aim_point := Vector3.ZERO
## Firing from the hip (Fire without Aim): the marker comes up low, the body
## turns to the crosshair, and shots go wide (PaintMarker.HIP_SPREAD), but
## you keep your full walking and running speed and the camera stays back.
var hip_firing := false
var _hip_left := 0.0

## The car being driven (or ridden in), or null on foot.
var vehicle: Car = null
## Riding in `vehicle`'s passenger seat rather than driving it.
var passenger := false
## The seat when a passenger (PassengerSeat), else null.
var passenger_seat: PassengerSeat
## Holds the trigger off (the weapon wheel is open).
var fire_blocked := false
## The paintball marker (trigger, hopper, reloads).
var marker: PaintMarker
## Paint and hits on this player.
var body_paint: BodyPaint

@onready var model: HumanoidModel = $Model

var _fall_speed := 0.0
var _ground_query: PhysicsRayQueryParameters3D
var _move := Vector3.ZERO ## planar velocity we're trying to make
var _yaw_vel := 0.0
var _last_moved := Vector3.ZERO


## The group the player is in, so anything can find them wherever they are
## in the tree (in a car they're moved under its seat, so a node path from
## the scene breaks).
const GROUP := "player"


func _ready() -> void:
	add_to_group(GROUP)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_ground_query = PhysicsRayQueryParameters3D.new()
	_ground_query.collision_mask = Layers.GROUND
	marker = PaintMarker.new()
	marker.name = "PaintMarker"
	marker.shooter = self
	add_child(marker)
	body_paint = BodyPaint.new()
	body_paint.name = "BodyPaint"
	body_paint.model = model
	body_paint.went_out.connect(func(by: Node) -> void: went_out.emit(by))
	add_child(body_paint)


func _physics_process(delta: float) -> void:
	if passenger:
		_ride(delta)
		return
	var wish := Vector3.ZERO
	var running := false
	if input_enabled:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var yaw := camera_rig.yaw if camera_rig != null else rotation.y
		var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var right := Vector3(cos(yaw), 0.0, -sin(yaw))
		wish = right * input.x - forward * input.y # input.y is negative for forward
		running = Input.is_action_pressed("run")
	# Out, the marker's down: no aiming until you're back in.
	aiming = input_enabled and camera_rig != null and Input.is_action_pressed("aim") and not is_out()
	aim_amount = move_toward(aim_amount, 1.0 if aiming else 0.0, delta / 0.12)
	var fire_held := input_enabled and camera_rig != null and Input.is_action_pressed("fire") and not is_out()
	if fire_held and not aiming:
		_hip_left = hip_hold
	else:
		_hip_left = maxf(0.0, _hip_left - delta)
	hip_firing = not aiming and _hip_left > 0.0
	var aim_yaw := rotation.y
	if aiming or hip_firing:
		aim_point = camera_rig.aim_point(self)
		var to := aim_point - global_position
		to.y = 0.0
		# Something right at our feet: keep facing the way the camera looks.
		aim_yaw = atan2(-to.x, -to.z) if to.length() > 1.0 else camera_rig.yaw

	var amount := minf(1.0, wish.length())
	var target_speed := 0.0
	if amount > 0.05:
		# A light touch on the stick strolls; full tilt walks; Run runs.
		target_speed = lerpf(stroll_speed, walk_speed, smoothstep(0.2, 0.85, amount))
		if aiming:
			target_speed = lerpf(stroll_speed, aim_speed, smoothstep(0.2, 0.85, amount))
			if running:
				target_speed = lerpf(target_speed, aim_run_speed, amount)
			# Backing away from the target is slower than going at it.
			var ahead := wish.normalized().dot(Vector3(-sin(aim_yaw), 0.0, -cos(aim_yaw)))
			target_speed *= lerpf(1.0, aim_back_factor, clampf(-ahead, 0.0, 1.0))
		elif running:
			target_speed = lerpf(target_speed, run_speed, amount)
	var goal: Vector3 = wish.normalized() * target_speed if amount > 0.05 else Vector3.ZERO

	# Head straight for the wanted velocity at a fixed rate: changes of
	# direction cut across instead of curving round, and a reversal at a run
	# goes through a stop in about a tenth of a second.
	var rate := accel if goal.length_squared() > 0.0001 else decel
	_move = _move.move_toward(goal, rate * delta)

	# Face the way we're pushing (or still sliding, when stopping); aiming,
	# face the target whichever way we're going.
	var old_yaw := rotation.y
	var face := goal if goal.length_squared() > 0.0001 else _move
	if aiming or hip_firing:
		var yr := Smooth.spring_angle(rotation.y, _yaw_vel, aim_yaw, aim_turn_time if aiming else hip_turn_time, delta)
		rotation.y = yr[0]
		_yaw_vel = yr[1]
	elif face.length_squared() > 0.0001:
		var yr := Smooth.spring_angle(rotation.y, _yaw_vel, atan2(-face.x, -face.z), turn_time, delta)
		rotation.y = yr[0]
		_yaw_vel = yr[1]
	else:
		_yaw_vel = 0.0

	velocity = _move
	move_and_slide()
	_follow_ground(delta)

	# Against a wall, keep only what we actually managed, so the legs don't
	# pump on the spot and a reversal off a wall starts from rest.
	var moved := get_real_velocity()
	moved.y = 0.0
	if get_slide_collision_count() > 0 and moved.length() < _move.length():
		_move = moved

	speed = moved.length()
	run_amount = clampf((speed - walk_speed) / maxf(0.1, run_speed - walk_speed), 0.0, 1.0) * (1.0 - aim_amount)
	var turn := angle_difference(old_yaw, rotation.y) / maxf(delta, 0.0001)
	var facing := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var accel_ahead := (moved - _last_moved).dot(facing) / maxf(delta, 0.0001)
	_last_moved = moved
	# Which way the legs go relative to the body: only aiming do they step
	# sideways or back; otherwise the body turns to face the way.
	var step_angle := 0.0
	if (aiming or hip_firing) and speed > 0.1:
		var local := global_basis.inverse() * moved
		step_angle = atan2(-local.x, -local.z)
	# From the hip the marker is held lower (part way up the raise).
	model.aim = 1.0 if aiming else (HIP_RAISE if hip_firing else 0.0)
	model.scoped = float(marker.weapon.get("scope_fov", 0.0)) > 0.0
	if aiming or hip_firing:
		var chest := global_position + Vector3.UP * model.height * 0.8
		var d := aim_point - chest
		model.aim_pitch = atan2(d.y, Vector2(d.x, d.z).length())
	model.set_motion(speed, accel_ahead, turn, step_angle)

	# The marker: pull or hold Fire while aiming.
	marker.trigger = input_enabled and not fire_blocked and Input.is_action_pressed("fire")
	if input_enabled and Input.is_action_just_pressed("reload"):
		marker.reload()
	# From the hip counts as ready to fire, with the hip's spread (aim_amount
	# stays low), and keeps the quiet top-up from starting mid-burst.
	marker.step(delta, not is_out(), aiming or hip_firing, aim_amount, speed, aim_run_speed, PaintMarker.muzzle_of(model), aim_point)
	model.reload = marker.reload_progress() if marker.is_visible_reload() else -1.0


func _follow_ground(delta: float) -> void:
	_ground_query.from = global_position + Vector3.UP * (step_height + 0.3)
	_ground_query.to = global_position + Vector3.DOWN * 5.0
	var hit := get_world_3d().direct_space_state.intersect_ray(_ground_query)
	if hit.is_empty():
		# Nothing below within reach: maybe we were put under the ground (a
		# teleport onto a hill). Look from well above and stand on it.
		_ground_query.from = global_position + Vector3.UP * 60.0
		var far := get_world_3d().direct_space_state.intersect_ray(_ground_query)
		if not far.is_empty() and float(far["position"].y) > global_position.y:
			global_position.y = float(far["position"].y)
			_fall_speed = 0.0
			return
		_fall(delta, -INF)
		return
	var ground_y: float = hit["position"].y
	if global_position.y <= ground_y + 0.01:
		# On the ground or at a step up (a curb): rise quickly but not instantly.
		global_position.y = lerpf(global_position.y, ground_y, minf(1.0, 25.0 * delta))
		_fall_speed = 0.0
	else:
		_fall(delta, ground_y)


func _fall(delta: float, floor_y: float) -> void:
	_fall_speed += gravity * delta
	global_position.y = maxf(floor_y, global_position.y - _fall_speed * delta)
	if global_position.y == floor_y:
		_fall_speed = 0.0


# --- paint ---------------------------------------------------------------------------------

## A paintball hit (PaintShots): `value` hits (2 for a head shot).
func take_paint_hit(value: int, shooter: Node, point: Vector3) -> void:
	body_paint.take_hit(value, shooter, point, PaintShots.colour_of(shooter))


## Painted out: hands up, the marker can't fire.
func is_out() -> bool:
	return body_paint != null and body_paint.out


## For PaintShots: a hit here counts double.
func is_head_point(point: Vector3) -> bool:
	return body_paint.is_head_point(point)


## Paint off (the car wash's equivalent for a person: going home, the
## harbour, respawning). Hits and outs are body_paint.revive().
func clean_paint() -> void:
	body_paint.clear()


## Put the player somewhere (spawn, getting out of a car) and settle the camera.
func place(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	speed = 0.0
	_move = Vector3.ZERO
	_last_moved = Vector3.ZERO
	_yaw_vel = 0.0
	_fall_speed = 0.0
	reset_physics_interpolation()


# --- cars -------------------------------------------------------------------------------------

## Sit in the driver's seat and take the wheel, or (`as_passenger`) in the
## passenger seat.
func enter_vehicle(car: Car, as_passenger := false) -> void:
	vehicle = car
	passenger = as_passenger
	input_enabled = as_passenger
	set_physics_process(as_passenger)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	speed = 0.0
	run_amount = 0.0
	aiming = false
	aim_amount = 0.0
	model.aim = 0.0
	hip_firing = false
	_hip_left = 0.0
	if as_passenger:
		passenger_seat = PassengerSeat.of(car)
		passenger_seat.sit(self, model, marker)
		return
	reparent(car.seat, false)
	# The seat node marks the hip joint; the model's origin is at the feet.
	position = Vector3(0.0, -model.height / 1.75 * 0.93, 0.0)
	rotation = Vector3.ZERO
	reset_physics_interpolation()
	model.seated = true
	car.driver = self


## Step out on the driver's side (or wherever there's room).
func exit_vehicle(world_parent: Node) -> void:
	if vehicle == null:
		return
	var car := vehicle
	var spot := passenger_seat.exit_transform() if passenger else car.exit_transform()
	_leave_seat()
	vehicle = null
	reparent(world_parent, false)
	model.seated = false
	model.seated_steer = 0.0
	model.seated_grips = []
	model.seated_feet = []
	model.hide_head = false
	place(spot)
	collision_layer = Layers.CHARACTERS
	collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
	set_physics_process(true)
	input_enabled = true


## Out of whichever seat (still in the car's tree until reparented).
func _leave_seat() -> void:
	if passenger:
		passenger_seat.leave()
		passenger_seat = null
		passenger = false
		aiming = false
		aim_amount = 0.0
	elif vehicle != null:
		vehicle.driver = null


## Driver's seat to passenger seat or back (main.gd: stopped only).
func switch_seat() -> void:
	if vehicle == null:
		return
	var car := vehicle
	var to_passenger := not passenger
	_leave_seat()
	enter_vehicle(car, to_passenger)


## Riding as a passenger: Aim leans out of the window, Fire shoots (the
## seat does the leaning, the pose and the fire rules: PassengerSeat).
func _ride(_delta: float) -> void:
	var seat := passenger_seat
	if seat == null:
		return
	var want := input_enabled and camera_rig != null and Input.is_action_pressed("aim") and not is_out()
	seat.wants_lean = want
	model.scoped = float(marker.weapon.get("scope_fov", 0.0)) > 0.0
	aiming = want and seat.lean > 0.5
	# The camera comes over the shoulder as the body comes out.
	aim_amount = seat.lean if want else move_toward(aim_amount, 0.0, _delta / 0.12)
	if camera_rig != null and seat.lean > 0.0:
		aim_point = camera_rig.aim_point(self, 150.0, [vehicle.get_rid()])
	seat.aim_at = aim_point
	seat.trigger = input_enabled and not fire_blocked and Input.is_action_pressed("fire")
	if input_enabled and Input.is_action_just_pressed("reload"):
		marker.reload()


func _process(_delta: float) -> void:
	if vehicle != null and not passenger:
		model.seated_steer = vehicle.steer_angle / deg_to_rad(vehicle.max_steer_degrees)
		# Hands on the steering wheel and feet on the pedals, wherever this
		# car has them.
		var to_model := model.global_transform.affine_inverse() * vehicle.global_transform
		var grips: Array = []
		for p: Vector3 in vehicle.steering_grips():
			grips.append(to_model * p)
		model.seated_grips = grips
		var feet: Array = []
		for p: Vector3 in vehicle.pedal_points():
			feet.append(to_model * p)
		model.seated_feet = feet

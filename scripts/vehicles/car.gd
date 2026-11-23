class_name Car
extends RigidBody3D
## A drivable car, simulated as a real body on four sprung wheels.
##
## The car is a rigid body with weight, momentum and inertia; gravity,
## collisions and landings are the physics engine's. Each wheel has:
##   * a suspension spring and damper, found by a ray down to the road, which
##     holds the body up, lets it rock, dive, squat and lean, ride over curbs,
##     go light over a crest and leave the ground over a big enough one;
##   * a tyre, which grips along and across the road in proportion to the
##     weight pressing it down (so weight shifting between the wheels is what
##     makes a car understeer, oversteer or slide), and can only give so much
##     grip in all at once (a tyre spinning under power has less left for
##     cornering, which is what lets a rear-drive car step its tail out).
## The engine has a torque curve and drives through a gearbox with an
## automatic shift; top speed is wherever the engine's push meets the air.
##
## Every number comes from the car's model and its fitted parts (CarModels,
## CarParts), so performance parts can change any of it.
##
## Controls come from the driver (see PlayerController.enter_vehicle) through
## the input actions accelerate, brake_reverse, steer_left/right, handbrake.

signal crashed(impact_speed: float)

## Which car this is (an id in CarModels).
@export var model_id := "civique"
@export var paint := Color(0.2, 0.36, 0.34) ## body colour
## Performance parts fitted (ids in CarParts).
@export var parts: Array[String] = []

## Who is driving (the player while seated), or null when parked.
var driver: Node3D = null
## Speed along the way the car points, m/s (negative when reversing).
var speed := 0.0
## 0..1, how fast it's going (full at about 150 km/h), for the camera.
var run_amount := 0.0
var steer_angle := 0.0 ## radians, + is left
var yaw_rate := 0.0 ## radians per second, + is left
var plane_velocity := Vector2.ZERO ## (x, z) in m/s
## The engine and gearbox, for a rev counter or engine sound.
var rpm := 800.0
var gear := 1 ## 1 is first; -1 is reverse
## How many wheels are touching the ground.
var wheels_down := 4
var max_steer_degrees := 34.0

var spec: Dictionary ## the driving settings, from CarParts.build_spec
var shape: Dictionary ## this model's measurements (CarModels)
var wheel_radius := 0.31
var seat: Node3D
## The steering wheel, turned with the front wheels (child of the body).
var steering_wheel: Node3D

var _body: Node3D
var _wheels: Array[Node3D] = [] # steering pivots: FL, FR, RL, RR
var _wheel_meshes: Array[MeshInstance3D] = []
var _steer_rest := Basis.IDENTITY
var _steer_radius := 0.185
var _mounts: Array[Vector3] = [] # where each wheel's suspension ray starts (local)
var _spin: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _compress: Array[float] = [0.0, 0.0, 0.0, 0.0] # metres of spring compression
var _wheel_drop: Array[float] = [0.0, 0.0, 0.0, 0.0] # wheel centre below its mount
var _ray := PhysicsRayQueryParameters3D.new()
var _steer_in := 0.0
var _throttle := 0.0
var _brake := 0.0
var _handbrake := false
var _shift_timer := 0.0
var _parked_time := 0.0
var _last_velocity := Vector3.ZERO
# Settings pulled out of the spec for speed.
var _travel := 0.13
var _k := 30000.0 # spring rate per wheel, N/m
var _c := 2500.0 # damper rate per wheel, N s/m
var _static_load: Array[float] = [0.0, 0.0, 0.0, 0.0] # N each wheel carries at rest
var _anti_roll := 0.5


## Full name for the HUD, e.g. "Hanaka Civique".
func display_name() -> String:
	return CarModels.full_name(model_id)


func _ready() -> void:
	spec = CarParts.build_spec(model_id, parts)
	shape = CarModels.get_model(model_id)["shape"]
	wheel_radius = float(shape["wheel_radius"])
	var body_spec: Dictionary = spec["body"]
	var sus: Dictionary = spec["suspension"]
	mass = float(body_spec["mass"])
	max_steer_degrees = float(spec["steering"]["max_degrees"])
	collision_layer = Layers.VEHICLES
	collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEHICLES | Layers.GROUND
	continuous_cd = true
	can_sleep = false
	# No made-up damping: the car's own air drag, rolling resistance and
	# tyres are what slow it down.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	var mat := PhysicsMaterial.new()
	mat.friction = 0.35
	mat.bounce = 0.15
	physics_material_override = mat
	_ray.collision_mask = Layers.GROUND
	_ray.exclude = [get_rid()]

	# Where the weight sits: between the axles by weight_front, cg_height up.
	var front_z := float(shape["front_axle"])
	var rear_z := float(shape["rear_axle"])
	var wf := float(body_spec["weight_front"])
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, float(body_spec["cg_height"]), lerpf(rear_z, front_z, wf))

	# The body's collision: a box over the wheels, clear of the road.
	var box := BoxShape3D.new()
	var height: float = shape["height"]
	box.size = Vector3(float(shape["width"]) - 0.02, height * 0.62, float(shape["length"]) - 0.05)
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position.y = height * 0.62
	add_child(cs)

	# Suspension: each wheel's static load, and springs tuned to bob at
	# spring_hz with that load on them.
	_travel = float(sus["travel"])
	var g := 9.81
	var hz := float(sus["spring_hz"])
	for i in 4:
		var share := wf if i < 2 else 1.0 - wf
		_static_load[i] = mass * g * share * 0.5
	var corner_mass := mass * 0.25
	_k = corner_mass * pow(TAU * hz, 2.0)
	_c = 2.0 * float(sus["damping"]) * sqrt(_k * corner_mass)
	_anti_roll = float(sus["anti_roll"])

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	var builder := CarBuilder.new(shape, paint)
	mi.mesh = builder.make_body()
	_body.add_child(mi)
	_steer_radius = float(shape.get("wheel_size", 0.185))
	var sw := MeshInstance3D.new()
	sw.name = "SteeringWheel"
	sw.mesh = CarBuilder.steering_wheel_mesh(_steer_radius)
	sw.transform = builder.steering_transform()
	_steer_rest = sw.basis
	_body.add_child(sw)
	steering_wheel = sw
	seat = Node3D.new()
	seat.name = "DriverSeat"
	var sp: Array = shape["seat"]
	seat.position = Vector3(sp[0], sp[1], sp[2]) # driver sits on the left
	_body.add_child(seat)

	for z: float in [front_z, rear_z]:
		for s: float in [-1.0, 1.0]:
			# The ray starts where the wheel centre sits at full bump.
			_mounts.append(Vector3(float(shape["track_half"]) * s, wheel_radius + _travel, z))
			var pivot := Node3D.new()
			pivot.position = Vector3(float(shape["track_half"]) * s, wheel_radius, z)
			add_child(pivot)
			var style: String = shape.get("wheel_style", "alloy10")
			var w := MeshInstance3D.new()
			w.mesh = CarBuilder.wheel_mesh(wheel_radius, float(shape["wheel_width"]), style)
			w.scale = Vector3(s, 1.0, 1.0) # mirror so the hubcap faces out
			pivot.add_child(w)
			# The brake behind it steers with the wheel but doesn't spin.
			var brake := MeshInstance3D.new()
			brake.mesh = CarBuilder.brake_mesh(wheel_radius, float(shape["wheel_width"]), style, Color.html(shape.get("caliper", "#333333")))
			brake.scale = Vector3(s, 1.0, 1.0)
			pivot.add_child(brake)
			_wheels.append(pivot)
			_wheel_meshes.append(w)
	for i in 4:
		_wheel_drop[i] = _travel


## Where the driver's hands hold the steering wheel (0 left, 1 right) and
## the wheel's hub, in the car's own space. They turn with the wheel.
func steering_grips() -> Array[Vector3]:
	var xf := steering_wheel.transform
	return [xf * CarBuilder.steering_grip(0, _steer_radius), xf * CarBuilder.steering_grip(1, _steer_radius), xf.origin]


## Where the driver's feet rest (left on the floor, right on the pedal), in
## the car's own space.
func pedal_points() -> Array[Vector3]:
	var sp: Array = shape["seat"]
	var hip := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	var floor_y := float(shape["stations"][0][2])
	for st: Array in shape["stations"]:
		if float(st[0]) > hip.z:
			break
		floor_y = float(st[2])
	floor_y += 0.03
	var drop := hip.y - (floor_y + 0.09)
	var reach := sqrt(maxf(0.0, 0.76 * 0.76 - drop * drop))
	return [Vector3(hip.x - 0.1, floor_y + 0.09, hip.z - reach * 0.95), Vector3(hip.x + 0.11, floor_y + 0.11, hip.z - reach)]


## Where the driver's door is, for getting in (world space).
func door_point() -> Vector3:
	return global_transform * Vector3(-(float(shape["width"]) * 0.5 + 0.15), 0.0, float(shape["seat"][2]))


## A clear spot beside the car to step out to, driver's side first.
func exit_transform() -> Transform3D:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	q.shape = capsule
	q.collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY
	var ex: Array[RID] = [get_rid()]
	q.exclude = ex
	var sx := float(shape["width"]) * 0.5 + 0.5
	var sz := float(shape["seat"][2])
	var ez := float(shape["length"]) * 0.5 + 0.9
	var yaw := global_basis.get_euler().y
	for local: Vector3 in [Vector3(-sx, 0, sz), Vector3(sx, 0, sz), Vector3(-sx, 0, sz + 1.3), Vector3(sx, 0, sz + 1.3), Vector3(0, 0, -ez), Vector3(0, 0, ez)]:
		var p := global_transform * local
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
		if space.intersect_shape(q, 1).is_empty():
			return Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 0.3)
	return Transform3D(Basis(Vector3.UP, yaw), global_transform * Vector3(-sx, 0, sz) + Vector3.UP * 2.0)


func _physics_process(delta: float) -> void:
	_read_controls(delta)
	# Parked, still and well away from the camera: hold it fixed, so it can't
	# drop through a street that's being dropped or rebuilt round it. Parked
	# cars near the player stay real, so they can be bumped and shoved.
	if driver == null and linear_velocity.length() < 0.3:
		_parked_time += delta
	else:
		_parked_time = 0.0
	var cam := get_viewport().get_camera_3d()
	var far := cam == null or cam.global_position.distance_to(global_position) > 150.0
	var want_freeze := driver == null and _parked_time > 1.5 and far
	if freeze != want_freeze:
		freeze = want_freeze
	if not freeze:
		_suspension_and_tyres(delta)
	var fwd := -global_basis.z
	speed = linear_velocity.dot(fwd)
	plane_velocity = Vector2(linear_velocity.x, linear_velocity.z)
	yaw_rate = angular_velocity.y
	run_amount = clampf(absf(speed) / 42.0, 0.0, 1.0)
	# A hard knock: the velocity changed far more than the tyres could do.
	var jolt := (linear_velocity - _last_velocity).length()
	if jolt > 4.0 and not freeze:
		crashed.emit(jolt)
	_last_velocity = linear_velocity
	_animate(delta)


func _read_controls(delta: float) -> void:
	var steer_target := 0.0
	var accel := 0.0
	var brake_in := 0.0
	_handbrake = false
	if driver != null:
		accel = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake_reverse")
		steer_target = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		_handbrake = Input.is_action_pressed("handbrake")
	var st: Dictionary = spec["steering"]
	# Steering wheel: turns in at its speed, centres a bit faster.
	var rate := float(st["speed"]) if absf(steer_target) > absf(_steer_in) and signf(steer_target) == signf(_steer_in) or _steer_in == 0.0 else float(st["return"])
	_steer_in = move_toward(_steer_in, steer_target, rate * delta)
	var kmh := absf(speed) * 3.6
	var lock := deg_to_rad(lerpf(float(st["max_degrees"]), float(st["high_speed_degrees"]), smoothstep(0.0, 100.0, kmh)))
	steer_angle = _steer_in * lock

	# W/RT drives forward and S/LT brakes; once stopped, S/LT reverses.
	_throttle = 0.0
	_brake = 0.0
	if speed > 0.6:
		_throttle = accel
		_brake = brake_in
	elif speed < -0.6:
		_throttle = -brake_in
		_brake = accel
	elif accel > 0.05:
		_throttle = accel
	elif brake_in > 0.05:
		_throttle = -brake_in
	if driver == null:
		_brake = 1.0
		_handbrake = true


## Engine torque (N m) at an rpm, from the curve.
func _torque_at(at_rpm: float) -> float:
	var curve: Array = spec["engine"]["torque"]
	if at_rpm <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var a: Array = curve[i - 1]
		var b: Array = curve[i]
		if at_rpm <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (at_rpm - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(curve[curve.size() - 1][1])


## The engine and gearbox: rpm from the driven wheels' speed, an automatic
## shift, and the push at the wheels (N, all driven wheels together).
func _drive_force(delta: float) -> float:
	var eng: Dictionary = spec["engine"]
	var box: Dictionary = spec["gearbox"]
	var ratios: Array = box["ratios"]
	var idle := float(eng["idle_rpm"])
	var redline := float(eng["redline_rpm"])
	var final := float(box["final"])
	if _throttle < 0.0:
		gear = -1
	elif gear < 1:
		gear = 1
	var ratio := (float(box["reverse"]) if gear < 0 else float(ratios[gear - 1])) * final
	var wheel_rpm := absf(speed) / wheel_radius * 60.0 / TAU
	var engine_rpm := wheel_rpm * ratio
	# Automatic shifts: up near the redline, down when the revs fall away.
	_shift_timer = maxf(0.0, _shift_timer - delta)
	if gear > 0 and _shift_timer <= 0.0:
		if engine_rpm > redline * 0.94 and gear < ratios.size():
			gear += 1
			_shift_timer = float(box["shift_time"])
		elif gear > 1 and engine_rpm < redline * 0.45 * (1.0 if _throttle > 0.5 else 0.8):
			var lower_rpm := wheel_rpm * float(ratios[gear - 2]) * final
			if lower_rpm < redline * 0.88:
				gear -= 1
				_shift_timer = float(box["shift_time"]) * 0.6
	# Pulling away the clutch slips, so the engine sits above idle.
	rpm = clampf(maxf(engine_rpm, lerpf(idle, idle + 1800.0, absf(_throttle))), idle, redline + 200.0)
	if _throttle == 0.0:
		# Lifting off: the engine holds the car back a little.
		return -signf(speed) * minf(absf(speed) * 40.0, _torque_at(rpm) * 0.15 * ratio / wheel_radius)
	if _shift_timer > 0.0 or engine_rpm > redline:
		return 0.0
	var torque := _torque_at(rpm) * absf(_throttle)
	return signf(_throttle) * torque * ratio * float(box["efficiency"]) / wheel_radius


func _suspension_and_tyres(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var basis := global_basis
	var up := basis.y
	var fwd := -basis.z
	var com := global_transform * center_of_mass
	var tyres: Dictionary = spec["tyres"]
	var brakes: Dictionary = spec["brakes"]
	var body_spec: Dictionary = spec["body"]
	var drivetrain := str(spec["drivetrain"])

	# --- springs: find the road under each wheel -------------------------------
	var hits: Array = [null, null, null, null]
	var loads: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var reach := _travel * 2.0 + wheel_radius
	wheels_down = 0
	for i in 4:
		var from := global_transform * _mounts[i]
		_ray.from = from
		_ray.to = from - up * reach
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			_compress[i] = 0.0
			_wheel_drop[i] = move_toward(_wheel_drop[i], _travel * 2.0, delta * 3.0)
			continue
		wheels_down += 1
		var dist := from.distance_to(hit["position"]) - wheel_radius
		var x := clampf(_travel * 2.0 - dist, 0.0, _travel * 2.0) # compression from full droop
		var x_vel := (x - _compress[i]) / delta
		_compress[i] = x
		_wheel_drop[i] = _travel * 2.0 - x
		# Preloaded so the car sits mid-travel at rest; a stiff bump stop at the top.
		var f := _static_load[i] + _k * (x - _travel) + _c * x_vel
		if x > _travel * 1.85:
			f += _k * 8.0 * (x - _travel * 1.85)
		hits[i] = hit
		loads[i] = maxf(f, 0.0)
	# Anti-roll bars: share load across each axle against the lean.
	for axle in [0, 2]:
		if hits[axle] != null and hits[axle + 1] != null:
			var ar := (_compress[axle] - _compress[axle + 1]) * _k * _anti_roll
			loads[axle] = maxf(0.0, loads[axle] + ar)
			loads[axle + 1] = maxf(0.0, loads[axle + 1] - ar)

	# --- the engine's push and the brakes ------------------------------------------
	var drive := _drive_force(delta)
	var driven: Array[float]
	match drivetrain:
		"fwd":
			driven = [0.5, 0.5, 0.0, 0.0]
		"awd":
			driven = [0.2, 0.2, 0.3, 0.3]
		_:
			driven = [0.0, 0.0, 0.5, 0.5]
	var bias := float(brakes["front_bias"])
	var brake_share: Array[float] = [bias * 0.5, bias * 0.5, (1.0 - bias) * 0.5, (1.0 - bias) * 0.5]
	var downforce := float(body_spec["downforce"]) * speed * speed

	# --- tyres -------------------------------------------------------------------------
	for i in 4:
		if hits[i] == null:
			continue
		var hit: Dictionary = hits[i]
		var n: Vector3 = hit["normal"]
		var p: Vector3 = hit["position"]
		var load := float(loads[i]) + downforce * 0.25
		# Suspension pushes the body up along its own up.
		apply_force(up * float(loads[i]), p - global_position)
		# Which way this wheel points, flat on the road.
		var heading := fwd
		if i < 2:
			heading = fwd.rotated(up, steer_angle)
		var w_fwd := (heading - n * heading.dot(n)).normalized()
		var w_side := w_fwd.cross(n).normalized() # to the right
		var v := linear_velocity + angular_velocity.cross(p - com)
		var vl := v.dot(w_fwd)
		var vs := v.dot(w_side)
		var rear := i >= 2
		var mu := float(tyres["grip"]) * (float(tyres["rear_grip"]) if rear else 1.0)
		if rear and _handbrake:
			mu *= float(brakes["handbrake_rear_grip"])
		var cap := mu * load
		var corner_mass := mass * 0.25
		# Along the road: engine and brakes, no more than the tyre can grip.
		var fx := drive * driven[i]
		var b := _brake * float(brakes["force"]) * brake_share[i]
		if rear and _handbrake:
			b = maxf(b, cap * 0.9)
		# Brakes stop the wheel, never push it backwards.
		fx -= signf(vl) * minf(b, absf(vl) * corner_mass / delta)
		var spinning := absf(fx) > cap
		fx = clampf(fx, -cap, cap)
		# Across the road: the tyre's grip builds with how far it's slipping
		# sideways and levels off at what the road allows.
		var stiff := float(tyres["stiffness"]) * 0.5 * (float(tyres["rear_stiffness"]) if rear else 1.0)
		var slip := atan2(vs, maxf(absf(vl), 2.0))
		var side_cap := sqrt(maxf(cap * cap - fx * fx, pow(float(tyres["spin_grip"]) * cap, 2.0)))
		if spinning:
			side_cap = minf(side_cap, float(tyres["spin_grip"]) * cap * 1.6)
		var fy := -side_cap * tanh(stiff * slip / maxf(side_cap, 1.0))
		# Nearly stopped, a tyre doesn't creep sideways: it simply holds,
		# up to its grip.
		var crawl := 1.0 - smoothstep(0.5, 3.0, absf(vl))
		var hold := clampf(-vs * corner_mass / delta * 0.5, -side_cap, side_cap)
		fy = lerpf(fy, hold, crawl)
		apply_force(w_fwd * fx + w_side * fy, p - global_position)

	# --- air and rolling resistance, at the middle of the car ------------------------
	var air := -linear_velocity * linear_velocity.length() * float(body_spec["drag"])
	var rolling := Vector3.ZERO
	if wheels_down > 0:
		rolling = -fwd * speed * float(body_spec["rolling"])
	apply_central_force(air + rolling)
	if wheels_down > 0 and downforce > 0.0:
		apply_central_force(-up * downforce)


func _animate(delta: float) -> void:
	for i in 4:
		var w := _wheels[i]
		var m := _mounts[i]
		w.position = Vector3(m.x, m.y - _wheel_drop[i], m.z)
		w.rotation.y = steer_angle if i < 2 else 0.0
		_spin[i] -= speed * delta / wheel_radius
		_wheel_meshes[i].rotation.x = _spin[i]
	if steering_wheel != null:
		var turn := steer_angle / deg_to_rad(maxf(1.0, max_steer_degrees)) * CarBuilder.STEER_WHEEL_TURN
		steering_wheel.basis = _steer_rest * Basis(Vector3.BACK, turn)

class_name Car
extends RigidBody3D
## A drivable vehicle, simulated as a real body on sprung wheels: a car, a
## truck, a trailer, a forklift.
##
## The vehicle is a rigid body with weight, momentum and inertia; gravity,
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
## Wheels can stand on another vehicle (a car on a flatbed, a car rolling up
## a tow truck's deck): the tyre grips relative to that deck, and the deck
## feels the weight and the grip pushing back, so a loaded truck really is
## heavier and a car with its brakes on is carried along.
##
## A model has any number of axles (CarModels "axles"): a tandem rear, dual
## tyres, steering at the back (a forklift), no engine at all (a trailer),
## or landing legs that hold a trailer's nose up while it isn't hitched.
## Trucks and trailers couple (Coupling), carry loads that can be strapped
## down (TieDowns), and some have a working part (a tow truck's tilting deck
## and winch, a forklift's mast: VehicleTool).
##
## Every number comes from the model and its fitted parts (CarModels,
## CarParts), so performance parts can change any of it.
##
## Controls come from the driver (see PlayerController.enter_vehicle) through
## the input actions accelerate, brake_reverse, steer_left/right, handbrake.

signal crashed(impact_speed: float)

## Which vehicle this is (an id in CarModels).
@export var model_id := "civique"
@export var paint := Color(0.2, 0.36, 0.34) ## body colour
## Performance parts fitted (ids in CarParts).
@export var parts: Array[String] = []

## Who is driving (the player while seated), or null when parked.
var driver: Node3D = null
## Speed along the way the vehicle points, m/s (negative when reversing).
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
var wheel_radius := 0.31 ## of the driven wheels
var seat: Node3D

## False for things with no seat (trailers).
var drivable := true
## The vehicle pulling this one (a trailer's tractor), and the one this pulls.
var towed_by: Car = null
var towing: Car = null
## Parked with the brakes off, so it can be winched or pushed.
var free_rolling := false
## The working part, if this model has one (tow truck deck, forklift mast).
var tool: VehicleTool = null
## Straps holding loads on this vehicle's deck.
var tie_downs: TieDowns
## Collision shapes that loads sit on (for finding what to strap down).
var deck_shapes: Array[CollisionShape3D] = []

## The brake actually applied this step (0..1) and the handbrake, which a
## trailer follows from its tractor.
var brake_applied := 0.0
var handbrake_on := false

var _body: Node3D
var _wheels: Array[Node3D] = [] # steering pivots, two per axle (left, right)
var _wheel_meshes: Array[Node3D] = [] # what spins (one or two tyres)
var _mounts: Array[Vector3] = [] # where each wheel's suspension ray starts (local)
var _radius: Array[float] = []
var _steer_factor: Array[float] = [] # 1 steers with the wheel, -1 the other way (rear steer), 0 fixed
var _drive_share: Array[float] = []
var _brake_share: Array[float] = []
var _is_front: Array[bool] = []
var _is_leg: Array[bool] = [] # trailer landing legs: hold it up only while unhitched
var _stiff_mul: Array[float] = []
var _travel_of: Array[float] = []
var _k_of: Array[float] = []
var _c_of: Array[float] = []
var _bump_k: Array[float] = []
var _spin: Array[float] = []
var _compress: Array[float] = [] # metres of spring compression
var _wheel_drop: Array[float] = [] # wheel centre below its mount
var _static_load: Array[float] = [] # N each wheel carries at rest
var _hits: Array = []
var _loads: Array[float] = []
var _n := 4
var _wheel_mass := 300.0 # each wheel's share of the mass, for the brakes and the hold at a crawl
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
var _anti_roll := 0.5
var _abs := false
var _has_engine := true
var _part_pivots := {} # part name -> Node3D holding that part's meshes
var _part_shapes := {} # part name -> Array of [CollisionShape3D, rest Transform3D]
var _legs_up := 0.0
var _anchor: Array = [] # where a stopped, braked tyre's contact stuck (in what it stands on), or null
var _anchor_on: Array = []


## Full name for the HUD, e.g. "Hanaka Civique".
func display_name() -> String:
	return CarModels.full_name(model_id)


func _ready() -> void:
	add_to_group("vehicles")
	spec = CarParts.build_spec(model_id, parts)
	shape = CarModels.get_model(model_id)["shape"]
	wheel_radius = float(shape["wheel_radius"])
	drivable = bool(shape.get("drivable", true))
	_has_engine = spec.get("engine") is Dictionary
	var body_spec: Dictionary = spec["body"]
	var sus: Dictionary = spec["suspension"]
	mass = float(body_spec["mass"])
	max_steer_degrees = float(spec["steering"]["max_degrees"])
	_abs = bool(spec["brakes"].get("abs", false))
	collision_layer = Layers.VEHICLES
	collision_mask = Layers.SOLID | Layers.BOUNDARY | Layers.VEHICLES | Layers.GROUND | Layers.CARGO
	continuous_cd = true
	can_sleep = false
	# No made-up damping: the car's own air drag, rolling resistance and
	# tyres are what slow it down.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.05
	var mat := PhysicsMaterial.new()
	mat.friction = float(shape.get("friction", 0.35))
	mat.bounce = 0.15
	physics_material_override = mat
	# Wheels stand on the road, or on another vehicle's deck.
	_ray.collision_mask = Layers.GROUND | Layers.VEHICLES
	_ray.exclude = [get_rid()]

	var axles := _axles()
	# The front of the weight split is the steered axles (or the trailer's
	# legs); the rest is the back.
	var zf := 0.0
	var zr := 0.0
	var nf := 0
	var nr := 0
	for a: Dictionary in axles:
		if _axle_is_front(a):
			zf += float(a["z"])
			nf += 1
		else:
			zr += float(a["z"])
			nr += 1
	zf = zf / nf if nf > 0 else float(shape.get("front_axle", 0.0))
	zr = zr / nr if nr > 0 else float(shape.get("rear_axle", 0.0))
	var wf := float(body_spec["weight_front"])
	var cz := lerpf(zr, zf, wf)
	if nf == 0:
		wf = 0.0
		cz = zr
	elif nr == 0:
		wf = 1.0
		cz = zf
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, float(body_spec["cg_height"]), cz)

	_build_collision()

	# Suspension: each wheel's static load, and springs tuned to bob at
	# spring_hz with the body (and half its rated payload) on them.
	_travel = float(sus["travel"])
	var g := 9.81
	var hz := float(sus["spring_hz"])
	_anti_roll = float(sus["anti_roll"])

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var meshes := _make_meshes()
	var mi := MeshInstance3D.new()
	mi.mesh = meshes["body"]
	_body.add_child(mi)
	var part_meshes: Dictionary = meshes.get("parts", {})
	for pname: String in part_meshes:
		var pivot := _part_pivot(pname)
		var pm := MeshInstance3D.new()
		pm.mesh = part_meshes[pname]
		pivot.add_child(pm)
	seat = Node3D.new()
	seat.name = "DriverSeat"
	var sp: Array = shape["seat"]
	seat.position = Vector3(sp[0], sp[1], sp[2]) # driver sits on the left
	_body.add_child(seat)

	# Wheels, two per axle.
	var drive_total := 0.0
	for a: Dictionary in axles:
		drive_total += _axle_drive(a)
	var spring_wheels := 0
	for a: Dictionary in axles:
		if not bool(a.get("leg", false)):
			spring_wheels += 2
	var corner_mass := (mass + float(body_spec.get("payload", 0.0)) * 0.5) / maxf(1.0, spring_wheels)
	var k := corner_mass * pow(TAU * hz, 2.0)
	var c := 2.0 * float(sus["damping"]) * sqrt(k * corner_mass)
	var bias := float(spec["brakes"]["front_bias"])
	var front_wheels := nf * 2 # carrying the front of the weight (legs too)
	var front_braked := 0
	var rear_wheels := 0
	for a: Dictionary in axles:
		if bool(a.get("leg", false)):
			continue
		if _axle_is_front(a):
			front_braked += 2
		else:
			rear_wheels += 2
	for a: Dictionary in axles:
		var r := float(a.get("radius", wheel_radius))
		var width := float(a.get("width", shape.get("wheel_width", 0.2)))
		var th := float(a.get("track_half", shape.get("track_half", 0.8)))
		var leg := bool(a.get("leg", false))
		var front := _axle_is_front(a)
		var dual := bool(a.get("dual", false))
		var travel := float(a.get("travel", 0.06 if leg else _travel))
		for s: float in [-1.0, 1.0]:
			_is_front.append(front)
			_is_leg.append(leg)
			_radius.append(r)
			_travel_of.append(travel)
			_steer_factor.append(float(a.get("steer", 0.0)))
			_drive_share.append(_axle_drive(a) / drive_total * 0.5 if drive_total > 0.0 else 0.0)
			if leg:
				_brake_share.append(0.0)
			elif front_braked > 0 and rear_wheels > 0:
				_brake_share.append(bias / front_braked if front else (1.0 - bias) / rear_wheels)
			else:
				_brake_share.append(1.0 / maxf(1.0, front_braked + rear_wheels))
			var share := wf / front_wheels if front else (1.0 - wf) / maxi(1, rear_wheels)
			_static_load.append(mass * g * share)
			_k_of.append(k * (3.0 if leg else 1.0))
			_c_of.append(c * (2.0 if leg else 1.0))
			# The bump stop: much stiffer than the spring, but never stiffer
			# than one physics step can follow without bouncing.
			var corner := mass * share
			_bump_k.append(minf(_k_of[_k_of.size() - 1] * 8.0, corner * pow(1.2 * Engine.physics_ticks_per_second, 2.0)))
			_stiff_mul.append(1.6 if dual else 1.0)
			# The ray starts where the wheel centre sits at full bump.
			_mounts.append(Vector3(th * s, r + travel, float(a["z"])))
			var pivot := Node3D.new()
			pivot.position = Vector3(th * s, r, float(a["z"]))
			add_child(pivot)
			var spinner := Node3D.new()
			pivot.add_child(spinner)
			if leg:
				# Landing legs: the foot is drawn with the trailer; nothing spins.
				pass
			elif dual:
				for off: float in [-width * 0.56, width * 0.56]:
					var w := MeshInstance3D.new()
					w.mesh = CarBuilder.wheel_mesh(r, width)
					w.scale = Vector3(s, 1.0, 1.0)
					w.position.x = off
					spinner.add_child(w)
			else:
				var w := MeshInstance3D.new()
				w.mesh = CarBuilder.wheel_mesh(r, width)
				w.scale = Vector3(s, 1.0, 1.0) # mirror so the hubcap faces out
				spinner.add_child(w)
			_wheels.append(pivot)
			_wheel_meshes.append(spinner)
	_n = _mounts.size()
	_wheel_mass = mass / maxf(1.0, spring_wheels)
	for i in _n:
		_spin.append(0.0)
		_compress.append(0.0)
		_wheel_drop.append(_travel_of[i])
		_hits.append(null)
		_loads.append(0.0)
		_anchor.append(null)
		_anchor_on.append(null)
	wheels_down = _n

	tie_downs = TieDowns.new()
	tie_downs.name = "TieDowns"
	add_child(tie_downs)
	var tool_kind := str(shape.get("tool", ""))
	if tool_kind != "":
		tool = VehicleTool.make(tool_kind)
		tool.name = "Tool"
		add_child(tool)
		tool.setup(self)
	if not _part_shapes.is_empty():
		# Moving parts change the shapes; keep the inertia from changing with them.
		var l := float(shape["length"])
		var w2 := float(shape["width"])
		var h := float(shape["height"]) * 0.7
		inertia = Vector3(h * h + l * l, w2 * w2 + l * l, w2 * w2 + h * h) * mass / 12.0


## The axles from the model, or front and rear from its two axle positions.
func _axles() -> Array:
	if shape.has("axles"):
		return shape["axles"]
	var dt := str(spec["drivetrain"])
	return [
		{"z": float(shape["front_axle"]), "steer": 1.0, "drive": 0.4 if dt == "awd" else (1.0 if dt == "fwd" else 0.0)},
		{"z": float(shape["rear_axle"]), "steer": 0.0, "drive": 0.6 if dt == "awd" else (1.0 if dt == "rwd" else 0.0)},
	]


func _axle_is_front(a: Dictionary) -> bool:
	if a.has("front"):
		return bool(a["front"])
	return float(a.get("steer", 0.0)) > 0.0 or bool(a.get("leg", false))


func _axle_drive(a: Dictionary) -> float:
	if a.has("drive"):
		return float(a["drive"])
	return 1.0 if bool(a.get("driven", false)) else 0.0


## The body's collision: a box over the wheels, or the model's own boxes
## (a truck's cab, frame and deck). A box named as a part ("deck", "forks")
## moves with that part; one marked "deck" is a load floor.
func _build_collision() -> void:
	if not shape.has("boxes"):
		var box := BoxShape3D.new()
		var height: float = shape["height"]
		box.size = Vector3(float(shape["width"]) - 0.02, height * 0.62, float(shape["length"]) - 0.05)
		var cs := CollisionShape3D.new()
		cs.shape = box
		cs.position.y = height * 0.62
		add_child(cs)
		return
	for b: Dictionary in shape["boxes"]:
		var box := BoxShape3D.new()
		var sz: Array = b["size"]
		box.size = Vector3(sz[0], sz[1], sz[2])
		var cs := CollisionShape3D.new()
		cs.shape = box
		var p: Array = b["pos"]
		cs.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(float(b.get("tilt", 0.0)))), Vector3(p[0], p[1], p[2]))
		add_child(cs)
		if bool(b.get("deck", false)):
			deck_shapes.append(cs)
		var part := str(b.get("part", ""))
		if part != "":
			if not _part_shapes.has(part):
				_part_shapes[part] = []
			(_part_shapes[part] as Array).append([cs, cs.transform])


func _make_meshes() -> Dictionary:
	if str(shape.get("builder", "car")) == "truck":
		return TruckBuilder.new(shape, paint).build()
	return {"body": CarBuilder.new(shape, paint).make_body()}


func _part_pivot(pname: String) -> Node3D:
	if not _part_pivots.has(pname):
		var n := Node3D.new()
		n.name = "Part_" + pname
		_body.add_child(n)
		_part_pivots[pname] = n
	return _part_pivots[pname]


## Move a working part (its meshes and collision) to where it is now, as a
## transform from its rest position, in the vehicle's frame.
func set_part_transform(pname: String, xform: Transform3D) -> void:
	if _part_pivots.has(pname):
		(_part_pivots[pname] as Node3D).transform = xform
	for entry: Array in _part_shapes.get(pname, []):
		(entry[0] as CollisionShape3D).transform = xform * (entry[1] as Transform3D)


## Start held still (somewhere the town hasn't been built yet): it stays
## put until the camera comes near and there's ground under it.
func start_parked() -> void:
	freeze = true
	_parked_time = 2.0


## True if there's ground (or a vehicle's deck) within a few metres below
## a body, so it's safe to let it fall.
static func ground_below(body: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 2.0, body.global_position + Vector3.DOWN * 3.0, Layers.GROUND)
	return not body.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
	q.collision_mask = Layers.SOLID | Layers.VEHICLES | Layers.BOUNDARY | Layers.CARGO
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


## A point on the vehicle from the model (e.g. "hitch", "kingpin", "tow_front"),
## in world space, or null if it has none.
func model_point(key: String) -> Variant:
	var d: Variant = shape.get(key)
	if d is Dictionary:
		var p: Array = (d as Dictionary)["pos"]
		return global_transform * Vector3(p[0], p[1], p[2])
	return null


## The hitch key while driving: couple or uncouple a trailer, or hook the
## winch. Returns a line for the HUD ("" if there's nothing to do).
func hitch_action() -> String:
	if tool != null:
		var msg := tool.hitch_action()
		if msg != "":
			return msg
	if not shape.has("hitch"):
		return ""
	if towing != null:
		if absf(speed) > 1.0:
			return "Stop before uncoupling"
		var t := towing
		Coupling.uncouple(self)
		return "Uncoupled the %s" % t.display_name()
	if Coupling.try_couple(self):
		return "Coupled the %s" % towing.display_name()
	var n := Coupling.nearest(self)
	if n.is_empty():
		return "No trailer here: back the fifth wheel under a trailer's nose"
	return "Back up %.1f m more under the %s" % [float(n["gap"]), (n["trailer"] as Car).display_name()]


## The bodies this one is joined to (hitched), which its wheels and straps ignore.
func coupled_rids() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if towed_by != null:
		out.append(towed_by.get_rid())
	if towing != null:
		out.append(towing.get_rid())
	return out


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
	var want_freeze := driver == null and _parked_time > 1.5 and far and (towed_by == null or towed_by.freeze)
	if want_freeze and not freeze:
		freeze = true
	elif freeze and not want_freeze and (driver != null or ground_below(self)):
		# Only let go once the street under it has been built.
		freeze = false
	if tool != null:
		tool.physics(delta)
	if _part_pivots.has("legs"):
		# Landing legs fold up once the trailer's on a fifth wheel.
		var want := 0.32 if towed_by != null else 0.0
		if not is_equal_approx(_legs_up, want):
			_legs_up = move_toward(_legs_up, want, delta * 0.6)
			set_part_transform("legs", Transform3D(Basis.IDENTITY, Vector3(0.0, _legs_up, 0.0)))
	if driver != null and towing == null and shape.has("hitch") and speed < 0.0 and speed > -3.0:
		# Backing under a trailer: the plate's throat lines the kingpin up,
		# and the jaws lock as it drops in.
		Coupling.guide(self)
		Coupling.try_couple(self, Coupling.AUTO_LOCK)
	if not freeze:
		_suspension_and_tyres(delta)
		tie_downs.apply(delta)
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
		if towed_by != null:
			# A trailer brakes with its tractor (air brakes and spring brakes).
			_brake = towed_by.brake_applied
			_handbrake = towed_by.handbrake_on
		elif free_rolling:
			_brake = 0.0
			_handbrake = false
		else:
			_brake = 1.0
			_handbrake = true
	if tool != null and tool.holds_still():
		_throttle = 0.0
	brake_applied = _brake
	handbrake_on = _handbrake


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
	if not _has_engine:
		rpm = 0.0
		return 0.0
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
	var slip_rpm := float(eng.get("launch_rpm", idle + 1800.0))
	rpm = clampf(maxf(engine_rpm, lerpf(idle, slip_rpm, absf(_throttle))), idle, redline + 200.0)
	if _throttle == 0.0:
		# Lifting off: the engine holds the car back a little.
		return -signf(speed) * minf(absf(speed) * 40.0 * maxf(1.0, mass / 2500.0), _torque_at(rpm) * 0.15 * ratio / wheel_radius)
	if _shift_timer > 0.0 or engine_rpm > redline:
		return 0.0
	var throttle := absf(_throttle)
	if eng.has("governor_kmh") and _throttle > 0.0:
		# The speed limiter eases the throttle off over the last few km/h.
		throttle *= clampf((float(eng["governor_kmh"]) - speed * 3.6) / 3.0, 0.0, 1.0)
	var torque := _torque_at(rpm) * throttle
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
	var legs_down := towed_by == null
	_ray.exclude = coupled_rids()

	# --- springs: find the road under each wheel -------------------------------
	wheels_down = 0
	for i in _n:
		_hits[i] = null
		_loads[i] = 0.0
		if _is_leg[i] and not legs_down:
			_anchor[i] = null
			_compress[i] = 0.0
			_wheel_drop[i] = 0.0
			continue
		var travel := _travel_of[i]
		var r := _radius[i]
		var reach := travel * 2.0 + r
		var from := global_transform * _mounts[i]
		_ray.from = from
		_ray.to = from - up * reach
		var hit := space.intersect_ray(_ray)
		# Standing on another vehicle only counts on something like a floor.
		if not hit.is_empty() and hit["collider"] is CollisionObject3D and ((hit["collider"] as CollisionObject3D).collision_layer & Layers.GROUND) == 0 and (hit["normal"] as Vector3).y < 0.5:
			hit = {}
		if hit.is_empty():
			_anchor[i] = null
			_compress[i] = 0.0
			_wheel_drop[i] = move_toward(_wheel_drop[i], travel * 2.0, delta * 3.0)
			continue
		if not _is_leg[i]:
			wheels_down += 1
		var dist := from.distance_to(hit["position"]) - r
		var x := clampf(travel * 2.0 - dist, 0.0, travel * 2.0) # compression from full droop
		var x_vel := (x - _compress[i]) / delta
		_compress[i] = x
		_wheel_drop[i] = travel * 2.0 - x
		# Preloaded so the car sits mid-travel at rest; a stiff bump stop at the top.
		var f := _static_load[i] + _k_of[i] * (x - travel) + _c_of[i] * x_vel
		if x > travel * 1.85:
			f += _bump_k[i] * (x - travel * 1.85)
		_hits[i] = hit
		_loads[i] = maxf(f, 0.0)
	# Anti-roll bars: share load across each axle against the lean.
	for axle in range(0, _n, 2):
		if _is_leg[axle]:
			continue
		if _hits[axle] != null and _hits[axle + 1] != null:
			var ar := (_compress[axle] - _compress[axle + 1]) * _k_of[axle] * _anti_roll
			_loads[axle] = maxf(0.0, _loads[axle] + ar)
			_loads[axle + 1] = maxf(0.0, _loads[axle + 1] - ar)

	# --- the engine's push and the brakes ------------------------------------------
	var drive := _drive_force(delta)
	var downforce := float(body_spec["downforce"]) * speed * speed

	# --- tyres -------------------------------------------------------------------------
	for i in _n:
		if _hits[i] == null:
			continue
		var hit: Dictionary = _hits[i]
		var n: Vector3 = hit["normal"]
		var p: Vector3 = hit["position"]
		var load := float(_loads[i]) + downforce * 0.25
		var on := hit["collider"] as RigidBody3D # standing on another vehicle
		# Suspension pushes the body up along its own up.
		var total := up * float(_loads[i])
		# Which way this wheel points, flat on the road.
		var heading := fwd
		if _steer_factor[i] != 0.0:
			heading = fwd.rotated(up, steer_angle * _steer_factor[i])
		var w_fwd := (heading - n * heading.dot(n)).normalized()
		var w_side := w_fwd.cross(n).normalized() # to the right
		var v := linear_velocity + angular_velocity.cross(p - com)
		if on != null:
			# Grip is against the deck, which may be moving.
			v -= PhysicsServer3D.body_get_direct_state(on.get_rid()).get_velocity_at_local_position(p - on.global_position)
		var vl := v.dot(w_fwd)
		var vs := v.dot(w_side)
		var fx := 0.0
		var fy := 0.0
		var rear_wheel := not _is_front[i]
		var held := _is_leg[i] or ((_brake > 0.5 or (_handbrake and rear_wheel)) and absf(_throttle) < 0.05)
		if not held or (_anchor[i] == null and Vector2(vl, vs).length() > 0.25):
			_anchor[i] = null
		elif _anchor[i] == null or _anchor_on[i] != hit["collider"]:
			# Stopped with the brakes on (or a landing leg's foot): the contact
			# patch sticks where it is, in the frame of what it stands on.
			_anchor_on[i] = hit["collider"]
			_anchor[i] = (hit["collider"] as Node3D).global_transform.affine_inverse() * p
		if _anchor[i] != null:
			# Static friction: a stiff spring back to where it stuck, as strong
			# as the grip allows; past that it lets go and slides.
			var mu_hold := 0.7 if _is_leg[i] else float(tyres["grip"]) * (float(tyres["rear_grip"]) if rear_wheel else 1.0)
			var cap_hold := mu_hold * load
			var w := TAU * 1.5
			var stuck := (_anchor_on[i] as Node3D).global_transform * (_anchor[i] as Vector3)
			var err := stuck - p
			err -= n * err.dot(n)
			var v_flat := w_fwd * vl + w_side * vs
			var f := err * _wheel_mass * w * w - v_flat * 2.0 * _wheel_mass * w
			if f.length() > cap_hold:
				f = f.normalized() * cap_hold
				_anchor[i] = null
			fx = f.dot(w_fwd)
			fy = f.dot(w_side)
		elif _is_leg[i]:
			pass
		else:
			var rear := not _is_front[i]
			var mu := float(tyres["grip"]) * (float(tyres["rear_grip"]) if rear else 1.0)
			if rear and _handbrake:
				mu *= float(brakes["handbrake_rear_grip"])
			var cap := mu * load
			# Along the road: engine and brakes, no more than the tyre can grip.
			fx = drive * _drive_share[i]
			var b := _brake * float(brakes["force"]) * _brake_share[i]
			if rear and _handbrake:
				b = maxf(b, cap * 0.9)
			elif _abs:
				# Anti-lock brakes: never more than the tyre can take.
				b = minf(b, cap * 0.92)
			# Brakes stop the wheel, never push it backwards.
			fx -= signf(vl) * minf(b, absf(vl) * _wheel_mass / delta)
			var spinning := absf(fx) > cap
			fx = clampf(fx, -cap, cap)
			# Across the road: the tyre's grip builds with how far it's slipping
			# sideways and levels off at what the road allows.
			var stiff := float(tyres["stiffness"]) * 0.5 * (float(tyres["rear_stiffness"]) if rear else 1.0) * _stiff_mul[i]
			var slip := atan2(vs, maxf(absf(vl), 2.0))
			var side_cap := sqrt(maxf(cap * cap - fx * fx, pow(float(tyres["spin_grip"]) * cap, 2.0)))
			if spinning:
				side_cap = minf(side_cap, float(tyres["spin_grip"]) * cap * 1.6)
			fy = -side_cap * tanh(stiff * slip / maxf(side_cap, 1.0))
			# Nearly stopped, a tyre doesn't creep sideways: it simply holds,
			# up to its grip.
			var crawl := 1.0 - smoothstep(0.5, 3.0, absf(vl))
			var hold := clampf(-vs * _wheel_mass / delta * 0.5, -side_cap, side_cap)
			fy = lerpf(fy, hold, crawl)
		total += w_fwd * fx + w_side * fy
		apply_force(total, p - global_position)
		if on != null and not on.freeze:
			# What pushes the wheel pushes the deck back.
			on.apply_force(-total, p - on.global_position)

	# --- air and rolling resistance, at the middle of the car ------------------------
	var air := -linear_velocity * linear_velocity.length() * float(body_spec["drag"])
	var rolling := Vector3.ZERO
	if wheels_down > 0:
		rolling = -fwd * speed * float(body_spec["rolling"])
	apply_central_force(air + rolling)
	if wheels_down > 0 and downforce > 0.0:
		apply_central_force(-up * downforce)


func _animate(delta: float) -> void:
	for i in _n:
		var w := _wheels[i]
		var m := _mounts[i]
		w.position = Vector3(m.x, m.y - _wheel_drop[i], m.z)
		w.rotation.y = steer_angle * _steer_factor[i]
		_spin[i] -= speed * delta / _radius[i]
		_wheel_meshes[i].rotation.x = _spin[i]

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
## Off the pavement the ground matters (GroundMap): lawn and rough grass
## grip less and hold the car back a little; a farm field, a bog or sand
## lets the tyres sink in. A sunk tyre has to climb out of its own rut all
## the time, so it drags, more the deeper it is and the smaller the wheel;
## spinning it digs it deeper, and rolling on (or rocking back and forth)
## brings it up onto fresh ground again. Sunk past the car's ground
## clearance the underside drags in the mud as well. Big wheels, all-wheel
## drive and a high body get through; a small car crawls. Never quite
## stuck, though: at a crawl the ground never holds back more than the
## driven wheels can push.
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
## Any vehicle carries a tow strap, and the big four-by-fours a winch on
## the front (CarModels "winch"): line_action hooks one to another
## vehicle, or the winch to a tree or post, to pull something out of the
## mud or itself (TowLine).
##
## Controls come from the driver (see PlayerController.enter_vehicle) through
## the input actions accelerate, brake_reverse, steer_left/right, handbrake.

signal crashed(impact_speed: float)
## A wheel hit something hard from below: a curb, a pothole, a landing
## (how fast the suspension was punched upward, m/s).
signal bumped(strength: float)
## A trailer was coupled on (true) or let go (false), by the tractor.
signal hitched(on: bool)

## Which vehicle this is (an id in CarModels).
@export var model_id := "civique"
@export var paint := Color(0.2, 0.36, 0.34) ## body colour
## Performance parts fitted (ids in CarParts).
@export var parts: Array[String] = []
## A fleet's paint and kit (an id in CarModels.LIVERIES, e.g. "cps" for
## the town police), or "" for an ordinary car.
@export var livery := ""
## The fleet's number for this car, on its plate and sides.
@export var unit := 0

## Which player owns this car ("" for nobody's: anyone can get in and
## drive it). A car owned by another player is locked to everyone else.
var owner_id := ""
## The player's own vehicle this is (its GameState.vehicles id), or "" for
## one that isn't kept: see OwnedCars.
var garage_id := ""
## True while a menu has the keys (a drive-thru's card): the driver's
## controls are ignored and the handbrake is on.
var controls_held := false
## Who is driving (the player while seated), or null when parked.
var driver: Node3D = null
## A computer driver (CarAutopilot), or null for the player or parked. When
## set, the controls come from its `throttle`, `brake` (0..1, reverses once
## stopped, like the pedal), `steer` (-1..1, + is left) and `handbrake`
## instead of the input, and the car is driven, not parked.
var ai_controls: Object = null
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
## How hard the tyres are sliding, spinning or locked, 0 to 1 (the worst
## wheel): what the tyre squeal follows.
var skid := 0.0
var max_steer_degrees := 34.0
## What the ground is under the most weight (a GroundMap kind).
var ground := GroundMap.PAVED
## How soft that ground is, 0 (pavement) to 1 (mud), for the sounds.
var ground_soft := 0.0
## 0..1, how hard soft ground is holding the car back against what the
## driven wheels can push (1: crawling, the HUD suggests easing off).
var bogged := 0.0
## How muddy the body is, 0 to 1: builds up off the pavement, wears off
## slowly on it.
var dirt := 0.0
## The colour of that mud (sRGB).
var dirt_colour := Color(0.42, 0.2, 0.13)

var spec: Dictionary ## the driving settings, from CarParts.build_spec
var shape: Dictionary ## this model's measurements (CarModels)
var wheel_radius := 0.31 ## of the driven wheels
var seat: Node3D
## The steering wheel, turned with the front wheels (child of the body), or
## null for something nobody steers (a trailer).
var steering_wheel: Node3D

## False for things with no seat (trailers).
var drivable := true
## The vehicle pulling this one (a trailer's tractor), and the one this pulls.
var towed_by: Car = null
var towing: Car = null
## Parked with the brakes off, so it can be winched or pushed.
var free_rolling := false
## The trailer just dropped here: the jaws won't lock on it again by
## themselves until it's clear of the fifth wheel (or the hitch key is
## pressed), or uncoupling while stopped would couple it straight back.
var dropped: Car = null
## The working part, if this model has one (tow truck deck, forklift mast).
var tool: VehicleTool = null
## The light bar and siren, on a police car (else null).
var police: PoliceGear = null
## Straps holding loads on this vehicle's deck.
var tie_downs: TieDowns
## Collision shapes that loads sit on (for finding what to strap down).
var deck_shapes: Array[CollisionShape3D] = []
## The tow strap or winch cable from this vehicle, while it's hooked on.
var tow_line: TowLine = null

## Paint in the air intake (PaintCoverage, police paint): the share of the
## engine's push that gets through (2/3 from 80% coverage, less on a
## cough), and a stalled engine (100%) that pushes nothing at all. Only the
## drive force reads them.
var power_factor := 1.0
var stalled := false
## How much of their grip the tyres have (1 normally): a police paint strip
## (PaintStrip) takes most of it away for a couple of seconds.
var grip_factor := 1.0
## The body's mesh (what paint is drawn over: PaintCoverage).
var body_mesh: MeshInstance3D

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
var _half_tread: Array[float] = [] # half the width of the tyre (or pair of duals)
var _limited := false # spring limits worked out (see _limit_springs)
var _grip_m: Array[float] = [] # mass a tyre's grip can stop in one step without rocking the body
var _spin: Array[float] = []
var _compress: Array[float] = [] # metres of spring compression
var _wheel_drop: Array[float] = [] # wheel centre below its mount
var _static_load: Array[float] = [] # N each wheel carries at rest
var _hits: Array = []
var _loads: Array[float] = []
var _n := 4
var _wheel_mass := 300.0 # each wheel's share of the mass, for the brakes and the hold at a crawl
var _ray := PhysicsRayQueryParameters3D.new()
## The wheels' mounts, half treads and ray lengths, for WheelProbe (made on
## the first step), and which wheels (landing legs folded up) it skips.
var _p_mounts := PackedVector3Array()
var _p_half := PackedFloat64Array()
var _p_reach := PackedFloat64Array()
var _p_skip := PackedByteArray()
var _has_legs := false
var _steer_in := 0.0
var _throttle := 0.0
var _brake := 0.0
var _handbrake := false
var _shift_timer := 0.0
## Starts as if it had been sitting a while, so a car placed far from the
## camera holds still from the first frame instead of falling before the
## street under it has loaded.
var _parked_time := 2.0
var _last_velocity := Vector3.ZERO
var _age := 0.0
var _builder: CarBuilder # a car's body builder (null for a truck)
var _steer_rest := Basis.IDENTITY
var _steer_radius := 0.185
## Height of the road under each tyre as the tyre feels it (world y), or NAN
## when it's off the ground. It follows what the rays find, but a tyre takes
## a moment to roll up or down a step, so a tyre sat right on a curb's edge
## doesn't flick between the road and the curb from one tick to the next.
var _ground_y: Array[float] = []
# Settings pulled out of the spec for speed.
var _travel := 0.13
var _anti_roll := 0.5
var _abs := false
var _has_engine := true
var _part_pivots := {} # part name -> Node3D holding that part's meshes
var _part_shapes := {} # part name -> Array of [CollisionShape3D, rest Transform3D]
var _legs_up := 0.0
var _lamps := {} # LampGlow kind -> its MeshInstance3D
var _slide: Array[float] = [] # how hard each tyre is sliding, 0..1 (smoke and marks)
var _fx_key: Array[String] = []
var _marking: Array[bool] = []
var _anchor: Array = [] # where a stopped, braked tyre's contact stuck (in what it stands on), or null
var _anchor_on: Array = []
var _kind: Array[int] = [] # GroundMap kind under each tyre
var _sink: Array[float] = [] # how far each tyre has sunk in (m)
var _wheel_spin: Array[float] = [] # how much faster than the ground a spinning tyre turns (m/s)
## Underside height at rest (m): exhaust, axles, sills.
var _belly := 0.2
## The body and near wheels, which get the mud overlay while dirty.
var _dirt_meshes: Array[GeometryInstance3D] = []
var _dirt_shown := -1.0
static var _mud_material: ShaderMaterial
## No engine sounds (a dedicated server: nobody's listening).
static var silent := false
static var _cam_pos := Vector3.INF
static var _cam_frame := -1
## Every car in the tree, kept up as they come and go (in addition to the
## "vehicles" group, which stays the list other code and the native side
## go by: a car held on a rollback's deck is taken out of the group, so
## code standing in for a group scan checks `listed()`). Cheaper than
## asking the tree for the group, which makes a new array each time.
static var all: Array[Car] = []
## The ones with a fifth wheel or a kingpin (tractors and trailers), for
## Coupling.nearest.
static var couplers: Array[Car] = []
var _all_index := -1
var _coupler := false
var _coupled_rids: Array[RID] = []
var _coupled_by := -1 ## instance ids of towed_by and towing for _coupled_rids
var _coupled_to := -1
var _ray_exclude: Array[RID] = []


## Where the camera is this physics step (looked up once a step for every
## car, not by each), or INF without one.
static func camera_position(n: Node) -> Vector3:
	var f := Engine.get_physics_frames()
	if f != _cam_frame:
		_cam_frame = f
		var cam := n.get_viewport().get_camera_3d()
		_cam_pos = cam.global_position if cam != null else Vector3.INF
	return _cam_pos
## The springs, engine, brakes and tyres run natively (TcaCar, native/README.md)
## when the library's loaded; `-- --no-native` runs the GDScript here instead
## (to compare: the two must match).
static var native_physics := ClassDB.class_exists("TcaCar") and not OS.get_cmdline_user_args().has("--no-native")
var _native: Object = null

## A tow strap's length, and how close two tow points must be to put one on.
const STRAP_LENGTH := 9.0
## The long recovery strap from Maple Tire (GameState.items
## "recovery_strap"): the same, further.
const LONG_STRAP_LENGTH := 15.0
## How far the front winch reaches (m), how hard it pulls (N) and how
## fast it winds in (m/s): a twelve-thousand-pound truck winch.
const WINCH_REACH := 25.0
const WINCH_FORCE := 53000.0
const WINCH_SPEED := 0.5

## How much harder a sunk tyre rolls: a share of its load per unit of
## (sink / wheel radius), the slope of the rut it keeps climbing out of.
const SINK_DRAG := 0.5
## A spinning tyre digs in this fast (m/s, spinning hard).
const DIG_RATE := 0.09
## Rolling on, a sunk tyre comes up this far (m) per metre travelled.
const CLIMB_OUT := 0.05
## A tyre spinning in mud pushes this much less (times the ground's softness).
const SPIN_LOSS := 0.35
## At a crawl the soft ground holds back no more than this share of what
## the driven wheels can push, so nothing gets stuck for good. (Not all of
## it: a car sunk deeper at one end is also climbing out of a hole.)
const CRAWL_RESERVE := 0.6


## Full name for the HUD, e.g. "Hanaka Civique".
func display_name() -> String:
	return CarModels.full_name(model_id, livery)


func _enter_tree() -> void:
	if _all_index < 0:
		_all_index = all.size()
		all.append(self)
	if _coupler and not couplers.has(self):
		couplers.append(self)


func _exit_tree() -> void:
	if _all_index >= 0:
		# Swapped out with the last one (the order doesn't matter).
		var last: Car = all[all.size() - 1]
		all[_all_index] = last
		last._all_index = _all_index
		all.resize(all.size() - 1)
		_all_index = -1
	if _coupler:
		couplers.erase(self)


## In the "vehicles" group, as a group scan would find it (Car.all holds
## every car in the tree, including one held on a rollback's deck).
func listed() -> bool:
	return is_in_group(&"vehicles")


func _ready() -> void:
	add_to_group("vehicles")
	spec = CarParts.build_spec(model_id, parts)
	shape = CarModels.shape_for(model_id, livery, unit)
	_coupler = shape.has("hitch") or shape.has("kingpin")
	if _coupler and not couplers.has(self):
		couplers.append(self)
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
	# A little spring in a crash, but none on a load floor (loads would
	# bounce on it for ever).
	mat.bounce = float(shape.get("bounce", 0.0 if shape.has("boxes") else 0.15))
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
	_belly = _underside() * 0.6

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
	body_mesh = mi
	_dirt_meshes.append(mi)
	if meshes.get("detail") != null and (meshes["detail"] as Mesh).get_surface_count() > 0:
		# The interior and small parts: only drawn up close, no shadows.
		var dmi := MeshInstance3D.new()
		dmi.name = "Detail"
		dmi.mesh = meshes["detail"]
		ModelLod.near_only(dmi)
		_body.add_child(dmi)
	# Brake and reversing lights, lit while they're in use.
	var glow: Dictionary = meshes.get("lamps", {})
	for kind: String in glow:
		var lm := MeshInstance3D.new()
		lm.name = "Lamps_" + kind
		lm.mesh = glow[kind]
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lm.visibility_range_end = 250.0
		lm.visible = false
		_body.add_child(lm)
		_lamps[kind] = lm
	var part_meshes: Dictionary = meshes.get("parts", {})
	for pname: String in part_meshes:
		var pivot := _part_pivot(pname)
		var pm := MeshInstance3D.new()
		pm.mesh = part_meshes[pname]
		pivot.add_child(pm)
	if drivable:
		_steer_radius = float(shape.get("wheel_size", 0.185))
		var sw := MeshInstance3D.new()
		sw.name = "SteeringWheel"
		sw.mesh = CarBuilder.steering_wheel_mesh(_steer_radius)
		sw.transform = _steering_transform()
		ModelLod.near_only(sw)
		_steer_rest = sw.basis
		_body.add_child(sw)
		steering_wheel = sw
	seat = Node3D.new()
	seat.name = "DriverSeat"
	var sp: Array = shape["seat"]
	seat.position = Vector3(sp[0], sp[1], sp[2]) # driver sits on the left
	_body.add_child(seat)
	if shape.get("police", false):
		police = PoliceGear.new(self, _builder)
		_body.add_child(police)

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
			_half_tread.append(width * (1.06 if dual else 0.5))
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
			else:
				var style: String = shape.get("wheel_style", "steel6" if shape.has("axles") else "alloy10")
				# Full detail up close, a simpler wheel further off (duals
				# are one mesh), mirrored so the hubcap faces out.
				var dual_off := width * 0.56 if dual else 0.0
				for lod: bool in [false, true]:
					var w := MeshInstance3D.new()
					w.mesh = CarBuilder.wheel_mesh(r, width, style, lod, dual_off)
					w.scale = Vector3(s, 1.0, 1.0)
					if lod:
						ModelLod.far_only(w, ModelLod.WHEEL_RANGE)
					else:
						w.visibility_range_end = ModelLod.WHEEL_RANGE
						w.visibility_range_end_margin = ModelLod.MARGIN
						_dirt_meshes.append(w)
					spinner.add_child(w)
				# The brake behind it steers with the wheel but doesn't spin;
				# hidden behind the spokes, so only drawn up close.
				var brake := MeshInstance3D.new()
				brake.mesh = CarBuilder.brake_mesh(r, width, style, Color.html(shape.get("caliper", "#333333")))
				ModelLod.near_only(brake, ModelLod.WHEEL_RANGE)
				brake.scale = Vector3(s, 1.0, 1.0)
				brake.position.x = -width * 0.56 * s if dual else 0.0 # behind the inner tyre
				pivot.add_child(brake)
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
		_ground_y.append(NAN)
		_grip_m.append(_wheel_mass)
		_slide.append(0.0)
		_marking.append(false)
		_kind.append(GroundMap.PAVED)
		_sink.append(0.0)
		_wheel_spin.append(0.0)
		_fx_key.append("%d/%d" % [get_instance_id(), i])
	wheels_down = _n

	if _has_engine and not silent:
		add_child(CarAudio.new())
	tie_downs = TieDowns.new()
	tie_downs.name = "TieDowns"
	add_child(tie_downs)
	var tool_kind := str(shape.get("tool", ""))
	if tool_kind != "":
		tool = VehicleTool.make(tool_kind)
		tool.name = "Tool"
		add_child(tool)
		tool.setup(self)
	if _has_engine and (str(shape.get("builder", "car")) == "truck" or has_winch()):
		# Alarms, air brakes, hydraulics, the winch, hitching and straps.
		var wa := WorkAudio.new()
		wa.name = "WorkAudio"
		add_child(wa)
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


## How high the bottom of the body is at rest (m): the lowest of the
## lofted body between the axles and the collision boxes.
func _underside() -> float:
	var low := INF
	if shape.has("boxes"):
		for b: Dictionary in shape["boxes"]:
			var p: Array = b["pos"]
			var sz: Array = b["size"]
			if str(b.get("part", "")) == "":
				low = minf(low, float(p[1]) - float(sz[1]) * 0.5)
	else:
		low = float(shape["height"]) * 0.31
	if shape.has("stations"):
		var za := minf(float(shape.get("front_axle", -1.3)), float(shape.get("rear_axle", 1.3)))
		var zb := maxf(float(shape.get("front_axle", -1.3)), float(shape.get("rear_axle", 1.3)))
		for st: Array in shape["stations"]:
			if float(st[0]) >= za and float(st[0]) <= zb:
				low = minf(low, float(st[2]))
	return clampf(low, 0.1, 1.0) if low < INF else 0.3


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


## Built meshes, shared by every vehicle with the same look (ModelLod):
## key -> {"meshes": ..., "builder": CarBuilder or null}.
static var _mesh_cache := {}


func _make_meshes() -> Dictionary:
	var key := warm_meshes(model_id, paint, livery, unit, shape)
	var entry: Dictionary = _mesh_cache[key]
	_builder = entry["builder"]
	return entry["meshes"]


## Builds (once) the meshes of a model in a paint, so the first car of that
## look to appear doesn't hold up a frame building them (some 70 ms each).
## Returns the cache key; `is_warm` says whether they're built already.
static func warm_meshes(model_id: String, paint: Color, livery := "", unit := 0, shape := {}) -> String:
	# A fleet's unit numbers are labels (PoliceGear: both sides and the
	# roof), not part of the mesh: every unit of a livery shares one, and a
	# new unit in a chase doesn't build a whole car mid-frame. Its plate
	# shows the fleet's letters.
	var prefix := _unit_prefix(livery)
	if prefix != "":
		unit = 0
	var key := "%s|%s|%s|%d" % [model_id, paint.to_html(), livery, unit]
	if not _mesh_cache.has(key):
		if shape.is_empty():
			shape = CarModels.shape_for(model_id, livery, unit)
		if prefix != "":
			shape = shape.duplicate()
			shape["plate"] = prefix
		if str(shape.get("builder", "car")) == "truck":
			_mesh_cache[key] = {"meshes": TruckBuilder.new(shape, paint).build(), "builder": null}
		else:
			var b := CarBuilder.new(shape, paint)
			var body := b.make_body()
			var glow := {}
			for kind: String in [LampGlow.BRAKE, LampGlow.REVERSE]:
				var m := LampGlow.build(b.lamps, kind)
				if m != null:
					glow[kind] = m
			_mesh_cache[key] = {"meshes": {"body": body, "detail": b.detail_mesh, "lamps": glow}, "builder": b}
	return key


static func is_warm(model_id: String, paint: Color, livery := "", unit := 0) -> bool:
	if _unit_prefix(livery) != "":
		unit = 0
	return _mesh_cache.has("%s|%s|%s|%d" % [model_id, paint.to_html(), livery, unit])


## The fleet letters a livery puts on its plates ("" for none).
static func _unit_prefix(livery: String) -> String:
	if livery == "" or not CarModels.LIVERIES.has(livery):
		return ""
	return str((CarModels.LIVERIES[livery] as Dictionary).get("shape", {}).get("unit_prefix", ""))


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
	var shapes: Array = _part_shapes.get(pname, [])
	for entry: Array in shapes:
		(entry[0] as CollisionShape3D).transform = xform * (entry[1] as Transform3D)
	if not shapes.is_empty():
		# A part moving its collision (legs down, a deck tilting) wakes the
		# body: asleep, Jolt wouldn't push it off what the part now meets.
		sleeping = false


## Start held still (somewhere the town hasn't been built yet): it stays
## put until the camera comes near and there's ground under it.
func start_parked() -> void:
	freeze = true
	_parked_time = 2.0


## True if the real ground is built within a few metres below a body, so
## it's safe to let it fall. The coarse safety floor a metre under the
## ground (Terrain.build_global) doesn't count: landing on it and then
## having the street appear above would drop the body a metre.
static func ground_below(body: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 2.0, body.global_position + Vector3.DOWN * 3.0, Layers.GROUND)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and str((hit["collider"] as Node).name) != "SafetyFloor"


## Where the steering wheel sits (in the vehicle's space): from the car's
## own body, or for a truck the same rule from its seat ("wheel_rise",
## "wheel_reach", "column_degrees").
func _steering_transform() -> Transform3D:
	if str(shape.get("builder", "car")) != "truck":
		return _builder.steering_transform()
	var sp: Array = shape["seat"]
	var c := Vector3(float(sp[0]), float(sp[1]) + float(shape.get("wheel_rise", 0.36)), float(sp[2]) - float(shape.get("wheel_reach", 0.42)))
	return Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(float(shape.get("column_degrees", 24.0)))), c)


## Where the driver's hands hold the steering wheel (0 left, 1 right) and
## the wheel's hub, in the vehicle's own space. They turn with the wheel.
func steering_grips() -> Array[Vector3]:
	if steering_wheel == null:
		return []
	var xf := steering_wheel.transform
	return [xf * CarBuilder.steering_grip(0, _steer_radius), xf * CarBuilder.steering_grip(1, _steer_radius), xf.origin]


## Where the driver's feet rest (left on the floor, right on the pedal), in
## the vehicle's own space.
func pedal_points() -> Array[Vector3]:
	var sp: Array = shape["seat"]
	var hip := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
	var floor_y := hip.y - 0.45 # a truck's cab floor, below the seat
	if shape.has("stations"):
		floor_y = float(shape["stations"][0][2])
		for st: Array in shape["stations"]:
			if float(st[0]) > hip.z:
				break
			floor_y = float(st[2])
	floor_y += 0.03
	var drop := hip.y - (floor_y + 0.09)
	var reach := sqrt(maxf(0.0, 0.76 * 0.76 - drop * drop))
	return [Vector3(hip.x - 0.1, floor_y + 0.09, hip.z - reach * 0.95), Vector3(hip.x + 0.11, floor_y + 0.11, hip.z - reach)]


## The throttle the engine is getting, -1 (reversing) to 1.
func throttle_input() -> float:
	return _throttle


## True for the moment the gearbox is between gears.
func is_shifting() -> bool:
	return _shift_timer > 0.0 and gear > 0


## True if the player `player_id` may get in: the car is theirs or
## nobody's, and no one else is at the wheel.
func can_enter(player_id: String) -> bool:
	return (owner_id == "" or owner_id == player_id) and driver == null


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


## Springs sized for a full payload can be too much for the empty body: a
## light, narrow trailer would over-correct every physics step and shake
## itself round. So each wheel's spring, damper and bump stop are kept to
## what the body itself (its mass and inertia as felt at that wheel) can
## follow in one step. Far below these limits for a car, so cars are
## unchanged. Done once, on the first physics step, when the engine knows
## the body's inertia.
func _limit_springs(delta: float) -> void:
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	var inv_i: Basis = state.inverse_inertia_tensor
	if state.inverse_mass <= 0.0 or inv_i.x.length_squared() == 0.0:
		# Just woken from being held still: the engine still has it as an
		# immovable body. Wait a step for its real mass and inertia.
		return
	_limited = true
	var com := global_transform * center_of_mass
	var up := global_basis.y
	for i in _n:
		var r := global_transform * _mounts[i] - com
		var arm := r.cross(up)
		var m_eff := 1.0 / (1.0 / mass + arm.dot(inv_i * arm))
		_c_of[i] = minf(_c_of[i], 0.3 * m_eff / delta)
		_k_of[i] = minf(_k_of[i], 0.15 * m_eff / (delta * delta))
		_bump_k[i] = minf(_bump_k[i], 0.6 * m_eff / (delta * delta))
		# The same along the ground: grip pushes at the road, well below the
		# weight, so it rocks the body as well as moving it.
		var worst := 0.0
		for dir: Vector3 in [global_basis.x, global_basis.z]:
			var a := r.cross(dir)
			worst = maxf(worst, a.dot(inv_i * a))
		_grip_m[i] = minf(_wheel_mass, 1.0 / (1.0 / mass + worst))
	if _native != null:
		_native.call("refresh_springs")


## The hitch key while driving: couple or uncouple a trailer, or hook the
## winch. Returns a line for the HUD ("" if there's nothing to do).
func hitch_action() -> String:
	if tool != null:
		var msg := tool.hitch_action()
		if msg != "":
			return msg
	if not shape.has("hitch"):
		return line_action()
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


## The strap you carry: every vehicle has one; with Maple Tire's recovery
## strap it reaches further.
static func strap_length() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var gs := tree.root.get_node_or_null("GameState") if tree != null else null
	return LONG_STRAP_LENGTH if gs != null and int(gs.call("item_count", "recovery_strap")) > 0 else STRAP_LENGTH


## The grip wheel `i`'s ground allows (GroundMap "grip"), with all-terrain
## or mud tyres ("tyres.offroad", CarParts) winning back that share of what
## soft ground takes away.
func _ground_grip(i: int) -> float:
	var gk: Dictionary = GroundMap.KINDS[_kind[i]]
	var g := float(gk["grip"])
	return g + (1.0 - g) * float(spec["tyres"].get("offroad", 0.0)) * float(gk["soft"])


## True if this vehicle has a winch on the front.
func has_winch() -> bool:
	return bool(shape.get("winch", false))


## The winch line that's hooked on now (the tow truck's or the front
## winch's), or null, for the winch's sound.
func winch_line() -> TowLine:
	if tool is RollbackTool:
		return (tool as RollbackTool).line
	if tool is CraneTool:
		return (tool as CraneTool).line
	if tow_line != null and tow_line.reel_speed > 0.0:
		return tow_line
	return null


## Where a strap or cable can go on a body (its own frame): a vehicle's
## front and back tow eyes, a load's front and back.
static func tow_points(b: RigidBody3D) -> Array[Vector3]:
	if b is Car:
		var half := float((b as Car).shape["length"]) * 0.5
		return [Vector3(0.0, 0.4, -half + 0.1), Vector3(0.0, 0.4, half - 0.1)]
	if b is Cargo:
		var s := (b as Cargo).size
		return [Vector3(0.0, 0.15, -s.z * 0.5), Vector3(0.0, 0.15, s.z * 0.5)]
	return [Vector3.ZERO]


## The hitch key in an ordinary vehicle: put the tow strap (or the winch
## cable) on the nearest vehicle, or the winch on a tree or post ahead, or
## take it off again. Returns a line for the HUD.
func line_action() -> String:
	if tow_line != null:
		var what := tow_line.other_name()
		_drop_line()
		return "Unhooked from the %s" % what
	# Someone else's line on this one: take it off.
	for n in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Car
		if v != null and v.tow_line != null and v.tow_line.other == self:
			var who := v.display_name()
			v._drop_line()
			return "Unhooked the %s's line" % who
	var strap := strap_length()
	var mine := tow_points(self)
	var best: RigidBody3D = null
	var best_mine := 0
	var best_at := Vector3.ZERO
	var best_d := strap
	for n in get_tree().get_nodes_in_group("vehicles") + get_tree().get_nodes_in_group("cargo"):
		var b := n as RigidBody3D
		if b == null or b == self or b.freeze or b == towed_by or b == towing:
			continue
		for k in mine.size():
			var here := global_transform * mine[k]
			# The winch reaches further, off the front.
			var reach := WINCH_REACH if k == 0 and has_winch() else strap
			for local: Vector3 in tow_points(b):
				var at := b.global_transform * local
				var d := here.distance_to(at)
				if d < minf(reach, best_d if best != null else reach):
					best = b
					best_mine = k
					best_at = at
					best_d = d
	if best != null:
		var winch := best_mine == 0 and has_winch()
		tow_line = TowLine.make(self, mine[best_mine], best, best_at, not winch)
		var what := tow_line.other_name()
		if best is Car and (best as Car).driver == null:
			# Out of gear with the brakes off, so it can be pulled.
			(best as Car).free_rolling = true
		if winch:
			_set_winch(tow_line)
			return "Winch hooked to the %s: wind it in" % what
		tow_line.length = maxf(tow_line.length, strap)
		return "Strap on the %s: pull away gently" % what
	if has_winch():
		var anchor := _winch_anchor()
		if not anchor.is_empty():
			tow_line = TowLine.make(self, mine[0], anchor["body"], anchor["at"])
			_set_winch(tow_line)
			return "Winch on the %s: wind it in" % tow_line.other_name()
		return "Nothing to hook: a vehicle within %d m, or a tree or post ahead within %d m" % [int(strap), int(WINCH_REACH)]
	return "Nothing to strap to: get within %d m of another vehicle" % int(strap)


func _set_winch(l: TowLine) -> void:
	l.max_force = WINCH_FORCE
	l.reel_speed = WINCH_SPEED
	l.payout_speed = 0.8


## Something solid ahead for the winch: the nearest tree trunk, pole,
## post or wall in a fan in front, within reach.
func _winch_anchor() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var from := global_transform * (tow_points(self)[0] + Vector3(0.0, 0.3, 0.0))
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = Layers.SOLID
	q.exclude = coupled_rids()
	var best := {}
	var best_d := WINCH_REACH
	var fwd := -global_basis.z
	for k in 15:
		var dir := fwd.rotated(Vector3.UP, deg_to_rad(-56.0 + k * 8.0))
		q.from = from
		q.to = from + dir * WINCH_REACH
		var h := space.intersect_ray(q)
		if h.is_empty() or h["collider"] is RigidBody3D:
			continue
		var d := from.distance_to(h["position"])
		if d < best_d:
			best_d = d
			var body := h["collider"] as CollisionObject3D
			if not body.has_meta("anchor_name"):
				body.set_meta("anchor_name", _anchor_name(body))
			best = {"body": body, "at": h["position"]}
	return best


static func _anchor_name(body: Node) -> String:
	var n := String(body.name)
	if n.begins_with("TreeTrunks") or n.contains("Tree"):
		return "tree"
	if n.begins_with("Building"):
		return "building"
	if n.contains("Fence"):
		return "fence"
	if n.contains("Hydrant"):
		return "hydrant"
	if n.contains("Signal") or n.contains("Pole") or n.contains("Light"):
		return "pole"
	return "post"


func _drop_line() -> void:
	if tow_line == null:
		return
	if is_instance_valid(tow_line.other) and tow_line.other is Car:
		var c := tow_line.other as Car
		if c.driver == null:
			c.free_rolling = false
	tow_line.queue_free()
	tow_line = null


## The bodies this one is joined to (hitched), which its wheels and straps ignore.
## (The same array each time until what's hitched changes: don't change it.)
func coupled_rids() -> Array[RID]:
	var a := towed_by.get_instance_id() if towed_by != null else 0
	var b := towing.get_instance_id() if towing != null else 0
	if a != _coupled_by or b != _coupled_to:
		_coupled_by = a
		_coupled_to = b
		var out: Array[RID] = [get_rid()]
		if towed_by != null:
			out.append(towed_by.get_rid())
		if towing != null:
			out.append(towing.get_rid())
		_coupled_rids = out
	return _coupled_rids


func _physics_process(delta: float) -> void:
	_age += delta
	_read_controls(delta)
	# Parked, still and well away from the camera: hold it fixed, so it can't
	# drop through a street that's being dropped or rebuilt round it. Parked
	# cars near the player stay real, so they can be bumped and shoved.
	if driver == null and linear_velocity.length() < 0.3:
		_parked_time += delta
	else:
		_parked_time = 0.0
	var far := camera_position(self).distance_squared_to(global_position) > 150.0 * 150.0
	var want_freeze := driver == null and ai_controls == null and _parked_time > 1.5 and far and (towed_by == null or towed_by.freeze)
	if want_freeze and not freeze:
		freeze = true
	elif freeze and not want_freeze and (driver != null or ground_below(self)):
		# Only let go once the street under it has been built.
		freeze = false
	if freeze and driver == null and ai_controls == null and tool == null and tow_line == null and towing == null and towed_by == null:
		# Held still, parked far off: nothing to move, turn or light (most of
		# the town's real parked cars, every step).
		speed = 0.0
		plane_velocity = Vector2.ZERO
		yaw_rate = 0.0
		skid = 0.0
		_last_velocity = Vector3.ZERO
		return
	if tool != null:
		tool.physics(delta)
	if tow_line != null:
		if not tow_line.valid():
			_drop_line()
		else:
			tow_line.lever = 0.0
			if driver != null and tow_line.reel_speed > 0.0:
				tow_line.lever = Input.get_action_strength("aux_in") - Input.get_action_strength("aux_out")
			tow_line.physics(delta)
	if _part_pivots.has("legs"):
		# Landing legs fold up once the trailer's on a fifth wheel.
		var want := 0.32 if towed_by != null else 0.0
		if not is_equal_approx(_legs_up, want):
			_legs_up = move_toward(_legs_up, want, delta * 0.6)
			set_part_transform("legs", Transform3D(Basis.IDENTITY, Vector3(0.0, _legs_up, 0.0)))
	if dropped != null and (not is_instance_valid(dropped) or (dropped.model_point("kingpin") as Vector3).distance_to(model_point("hitch")) > 1.5):
		dropped = null
	if driver != null and towing == null and dropped == null and shape.has("hitch") and speed < -0.1 and speed > -3.0:
		# Backing under a trailer: the plate's throat lines the kingpin up,
		# and the jaws lock as it drops in.
		Coupling.guide(self)
		Coupling.try_couple(self, Coupling.AUTO_LOCK)
	skid = 0.0
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
	# (Not in its first moments: a car placed already moving, as traffic is,
	# would read its own starting speed as a crash.)
	if jolt > 4.0 and not freeze and _age > 0.1:
		crashed.emit(jolt)
		_jolt_camera(clampf((jolt - 3.0) / 12.0, 0.15, 1.0))
	_last_velocity = linear_velocity
	_animate(delta)
	_update_lamps()
	_update_dirt()


## A knock felt by whoever's driving: the chase camera (or the driver's
## head) shakes, if the camera's on this vehicle.
func _jolt_camera(amount: float) -> void:
	if driver == null:
		return
	var cam := get_viewport().get_camera_3d()
	var rig := cam.get_parent() as CameraRig if cam != null else null
	if rig != null and rig.target == self:
		rig.jolt(amount)


## Rubber on the road and smoke off any tyre sliding hard on the ground
## (not on another vehicle's deck); ruts and flung mud off it.
func _tyre_fx() -> void:
	for i in _n:
		if _is_leg[i]:
			continue
		var hit: Variant = _hits[i]
		if hit != null and _kind[i] != GroundMap.PAVED:
			_mud_fx(i, hit)
			continue
		var on_road := hit != null and not ((hit as Dictionary)["collider"] is RigidBody3D)
		# Weighted by how hard the tyre's pressed down: a wheel the body has
		# rolled the weight off can read as sliding but leaves next to nothing.
		var amount := _slide[i] * clampf(_loads[i] / maxf(_static_load[i], 1.0), 0.0, 1.3)
		if on_road and amount >= 0.4:
			var fx := TyreFx.get_for(self)
			if fx == null:
				return
			var h: Dictionary = hit
			# Smoke needs rubber scrubbing over the road fast: a wheel spun
			# hard, or a slide at speed. Creeping about, a tyre can squeal and
			# mark the road but hardly smokes.
			var scrub := maxf(_wheel_spin[i], absf(speed) * _slide[i])
			var smoke := smoothstep(3.0, 8.0, scrub)
			fx.slide(_fx_key[i], h["position"], h["normal"], _half_tread[i] * 1.8, clampf(amount, 0.0, 1.0), linear_velocity, smoke)
			_marking[i] = true
		elif _marking[i] and (amount < 0.25 or not on_road):
			# Stopped sliding (or left the road): the next mark is a new strip.
			_marking[i] = false
			var fx := TyreFx.get_for(self)
			if fx != null:
				fx.lift(_fx_key[i])


## A tyre off the pavement: a rut where it rolls through soft ground (or
## where it slides or spins on firmer grass), and clods thrown up behind a
## spinning wheel and off one going fast.
func _mud_fx(i: int, hit: Dictionary) -> void:
	var gk: Dictionary = GroundMap.KINDS[_kind[i]]
	var soft := float(gk["soft"])
	var fx := TyreFx.get_for(self)
	if fx == null:
		return
	var key := _fx_key[i] + "r"
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var moving := absf(speed) > 0.3 or _wheel_spin[i] > 0.3
	var marks := soft >= 0.5 or _slide[i] > 0.3 or _wheel_spin[i] > 0.3
	if moving and marks and _loads[i] > _static_load[i] * 0.2:
		var depth := clampf(_sink[i] / 0.1, 0.0, 1.0)
		fx.rut(key, p + n * -minf(_sink[i], 0.05), n, _half_tread[i] * 1.8, soft * (0.35 + 0.5 * depth), gk["mud"])
	elif not moving or not marks:
		fx.lift(key)
	var rate := soft * (_wheel_spin[i] * 0.35 + maxf(0.0, absf(speed) - 4.0) * 0.03)
	if rate > 0.0 and randf() < minf(rate, 1.5):
		var back := global_basis.z * signf(_throttle if _throttle != 0.0 else speed)
		var v := linear_velocity * 0.7 + back * (_wheel_spin[i] * 0.8 + randf_range(0.5, 2.0)) \
			+ Vector3(randf_range(-0.8, 0.8), randf_range(1.5, 3.5), randf_range(-0.8, 0.8))
		var at := p + n * 0.1 + global_basis.z * signf(speed + 0.01) * _radius[i] * 0.5
		fx.fling(at, v, gk["mud"])


## The mud overlay: on while there's mud to show, its amount kept up to
## date (in steps, not every frame).
func _update_dirt() -> void:
	if absf(dirt - _dirt_shown) < 0.02 and not (dirt <= 0.0 and _dirt_shown > 0.0):
		return
	var on := dirt > 0.02
	if _mud_material == null:
		_mud_material = ShaderMaterial.new()
		_mud_material.shader = load("res://shaders/car_mud.gdshader")
	var c := dirt_colour.srgb_to_linear()
	for m in _dirt_meshes:
		var cur := m.material_overlay
		if cur != null and cur != _mud_material and cur is ShaderMaterial:
			# Paint's overlay is on the body (PaintCoverage): the mud rides
			# along as its next pass, so both show.
			(cur as ShaderMaterial).next_pass = _mud_material if on else null
		else:
			m.material_overlay = _mud_material if on else null
		if on:
			m.set_instance_shader_parameter("dirt", dirt)
			m.set_instance_shader_parameter("mud_colour", Vector3(c.r, c.g, c.b))
	_dirt_shown = dirt if on else 0.0


## The mud overlay while there's mud showing, or null: PaintCoverage
## chains it after its own overlay so paint and mud show together.
func mud_overlay() -> Material:
	return _mud_material if _dirt_shown > 0.0 else null


## Brake lights while the brakes are on (a trailer's with its tractor's),
## reversing lights in reverse.
func _update_lamps() -> void:
	if _lamps.is_empty():
		return
	# A computer driver (ai_controls) lights them the same as a person.
	var driven := driver != null or ai_controls != null
	var live := driven or towed_by != null
	var braking := live and brake_applied > 0.05
	var reversing := false
	if driven:
		reversing = gear < 0
	elif towed_by != null:
		reversing = towed_by.gear < 0
	if _lamps.has(LampGlow.BRAKE):
		(_lamps[LampGlow.BRAKE] as Node3D).visible = braking
	if _lamps.has(LampGlow.REVERSE):
		(_lamps[LampGlow.REVERSE] as Node3D).visible = reversing


## True while the brake lights are lit (for tests and the HUD).
func brake_lights_on() -> bool:
	return _lamps.has(LampGlow.BRAKE) and (_lamps[LampGlow.BRAKE] as Node3D).visible


func _read_controls(delta: float) -> void:
	var steer_target := 0.0
	var accel := 0.0
	var brake_in := 0.0
	_handbrake = false
	if ai_controls != null:
		accel = clampf(float(ai_controls.get("throttle")), 0.0, 1.0)
		brake_in = clampf(float(ai_controls.get("brake")), 0.0, 1.0)
		steer_target = clampf(float(ai_controls.get("steer")), -1.0, 1.0)
		_handbrake = bool(ai_controls.get("handbrake"))
		_parked_time = 0.0 # driven: never held still as parked
	elif driver != null and controls_held:
		_handbrake = true # a menu is up (a drive-thru, say): held still
	elif driver != null:
		accel = Input.get_action_strength("accelerate")
		brake_in = Input.get_action_strength("brake_reverse")
		steer_target = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		_handbrake = Input.is_action_pressed("handbrake")
	var st: Dictionary = spec["steering"]
	# Steering wheel: turns in at its speed, centres a bit faster.
	var rate := float(st["speed"]) if absf(steer_target) > absf(_steer_in) and signf(steer_target) == signf(_steer_in) or _steer_in == 0.0 else float(st["return"])
	_steer_in = move_toward(_steer_in, steer_target, rate * delta)
	var kmh := absf(speed) * 3.6
	# Less lock the faster it goes, down to high_speed_degrees by lock_kmh
	# (100 km/h for a road vehicle; a forklift's top speed for a forklift).
	var lock := deg_to_rad(lerpf(float(st["max_degrees"]), float(st["high_speed_degrees"]), smoothstep(0.0, float(st.get("lock_kmh", 100.0)), kmh)))
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
	if driver == null and ai_controls == null:
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
	if not _has_engine or stalled:
		# No engine, or one stalled by paint: nothing drives the wheels and
		# the revs fall to nothing.
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
	if tool != null and driver != null:
		# The hydraulic pump runs off the engine: working the forks or the
		# deck brings the revs up, as a real operator's foot does.
		rpm = maxf(rpm, lerpf(idle, minf(redline * 0.75, idle * 2.2), tool.motion()))
	if _throttle == 0.0:
		# Lifting off: the engine holds the car back a little.
		return -signf(speed) * minf(absf(speed) * 40.0 * maxf(1.0, mass / 2500.0), _torque_at(rpm) * 0.15 * ratio / wheel_radius)
	if _shift_timer > 0.0 or engine_rpm > redline:
		return 0.0
	var throttle := absf(_throttle)
	if eng.has("governor_kmh") and _throttle > 0.0:
		# The speed limiter eases the throttle off over the last few km/h.
		throttle *= clampf((float(eng["governor_kmh"]) - speed * 3.6) / 3.0, 0.0, 1.0)
	if power_factor < 1.0 and _throttle > 0.0:
		# Paint in the intake: less power, and a top speed cut by the same
		# share (power alone only takes off what the air drag gives back,
		# about a sixth), eased off over the last 1 m/s like the governor.
		throttle *= clampf((full_top_speed() * power_factor - speed) / 1.0, 0.0, 1.0)
	var torque := _torque_at(rpm) * throttle * power_factor
	return signf(_throttle) * torque * ratio * float(box["efficiency"]) / wheel_radius


var _full_top_speed := -1.0

## The fastest the vehicle goes flat out on the level, in m/s, worked out
## once from its own engine, gears, air drag and rolling resistance: the
## highest speed where the best gear still pushes harder than the air and
## the tyres hold it back.
func full_top_speed() -> float:
	if _full_top_speed >= 0.0:
		return _full_top_speed
	var eng: Dictionary = spec["engine"]
	var box: Dictionary = spec["gearbox"]
	var ratios: Array = box["ratios"]
	var redline := float(eng["redline_rpm"])
	var body_spec: Dictionary = spec["body"]
	var drag := float(body_spec["drag"])
	var roll := float(body_spec.get("rolling", 0.0))
	var top := 0.0
	var v := 0.5
	while v < 120.0:
		var best := 0.0
		for g in ratios:
			var ratio := float(g) * float(box["final"])
			var r := v / wheel_radius * 60.0 / TAU * ratio
			if r <= redline:
				best = maxf(best, _torque_at(r) * ratio * float(box["efficiency"]) / wheel_radius)
		if best >= drag * v * v + roll * v:
			top = v
		v += 0.25
	if eng.has("governor_kmh"):
		top = minf(top, float(eng["governor_kmh"]) / 3.6)
	_full_top_speed = top
	return top


func _suspension_and_tyres(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var legs_down := towed_by == null
	var ex := coupled_rids()
	if ex != _ray_exclude:
		_ray_exclude = ex
		_ray.exclude = ex # (copied into the query: only when it changes)
	if not _limited:
		_limit_springs(delta)
	# The tyre rests on the highest thing under its tread (WheelProbe).
	if _p_mounts.size() != _n:
		_p_mounts = PackedVector3Array(_mounts)
		_p_half = PackedFloat64Array(_half_tread)
		_p_reach = PackedFloat64Array()
		_p_skip = PackedByteArray()
		_p_skip.resize(_n)
		_has_legs = false
		for i in _n:
			_p_reach.append(_travel_of[i] * 2.0 + _radius[i])
			_has_legs = _has_legs or _is_leg[i]
	if _has_legs:
		for i in _n:
			_p_skip[i] = 1 if _is_leg[i] and not legs_down else 0
	var found := WheelProbe.probe(space, _ray, global_transform, _p_mounts, _p_half, _p_reach, _p_skip)
	if native_physics:
		if _native == null:
			_native = ClassDB.instantiate("TcaCar")
			_native.call("bind", self, GroundMap.KINDS)
		if CarParity.on:
			CarParity.step(self, delta, found, legs_down)
		else:
			_native.call("step", delta, found, legs_down)
		return
	_springs_and_tyres_gd(delta, found, legs_down)


## What happens to the forces worked out below: applied (null), or, while
## CarParity compares this with the native version, kept in this list.
var _forces_out: Variant = null


func _push(f: Vector3, at: Vector3) -> void:
	if _forces_out == null:
		apply_force(f, at)
	else:
		(_forces_out as Array).append(["force", f, at])


func _push_on(on: RigidBody3D, f: Vector3, at: Vector3) -> void:
	if _forces_out == null:
		on.apply_force(f, at)
	else:
		(_forces_out as Array).append(["on", f, at, on])


func _push_central(f: Vector3) -> void:
	if _forces_out == null:
		apply_central_force(f)
	else:
		(_forces_out as Array).append(["central", f])


## The springs, the engine's push, the brakes and the tyres, with the road
## under each wheel found (`found`, WheelProbe). The native TcaCar.step
## does the same (and must match: CarParity, tools/native_check.gd).
func _springs_and_tyres_gd(delta: float, found: Array, legs_down: bool) -> void:
	var basis := global_basis
	var up := basis.y
	var fwd := -basis.z
	var com := global_transform * center_of_mass
	var tyres: Dictionary = spec["tyres"]
	var brakes: Dictionary = spec["brakes"]
	var body_spec: Dictionary = spec["body"]
	# --- springs: find the road under each wheel -------------------------------
	wheels_down = 0
	var punch := 0.0
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
		var from := global_transform * _mounts[i]
		var hit: Dictionary = found[i] if found[i] != null else {}
		if hit.is_empty():
			_anchor[i] = null
			_compress[i] = 0.0
			_ground_y[i] = NAN
			_wheel_drop[i] = move_toward(_wheel_drop[i], travel * 2.0, delta * 3.0)
			continue
		if not _is_leg[i]:
			wheels_down += 1
		_kind[i] = GroundMap.kind_of_hit(hit)
		# Rolling up or off a step takes the tyre a moment, quicker the
		# faster it's rolling; at a standstill it settles over a fraction of
		# a second instead of hopping between the two heights. (Not on a
		# vehicle's deck, which moves: there it's where the deck is.)
		var hit_y: float = (hit["position"] as Vector3).y
		if _kind[i] != GroundMap.PAVED:
			# Uneven ground (the same bumps every time), and a sunk tyre
			# sits that much lower.
			var hp: Vector3 = hit["position"]
			var gk: Dictionary = GroundMap.KINDS[_kind[i]]
			hit_y += float(gk["bump"]) * GroundMap.bump_at(_kind[i], hp.x, hp.z) - _sink[i]
		if is_nan(_ground_y[i]) or up.y < 0.5 or hit["collider"] is RigidBody3D:
			_ground_y[i] = hit_y
		else:
			var pv := linear_velocity + angular_velocity.cross(from - com)
			var rate := 0.3 + 2.5 * Vector2(pv.x, pv.z).length()
			_ground_y[i] = move_toward(_ground_y[i], hit_y, rate * delta)
		var dist := (from.y - _ground_y[i]) / up.y - r
		var x := clampf(travel * 2.0 - dist, 0.0, travel * 2.0) # compression from full droop
		var x_vel := (x - _compress[i]) / delta
		if not _is_leg[i]:
			punch = maxf(punch, x_vel)
		_compress[i] = x
		_wheel_drop[i] = travel * 2.0 - x
		# Preloaded so the car sits mid-travel at rest; a stiff bump stop at the top.
		var f := _static_load[i] + _k_of[i] * (x - travel) + _c_of[i] * x_vel
		if x > travel * 1.85:
			f += _bump_k[i] * (x - travel * 1.85)
		_hits[i] = hit
		_loads[i] = maxf(f, 0.0)
	# (Not in the first moments, while the car is still settling onto the road.)
	if punch > 1.2 and _age > 1.0 and _forces_out == null:
		bumped.emit(punch)
		_jolt_camera(clampf((punch - 1.0) / 6.0, 0.05, 0.4))
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
	var resist := _soft_ground(delta, tyres)

	# --- tyres -------------------------------------------------------------------------
	for i in _n:
		_slide[i] = 0.0
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
		var rear := not _is_front[i]
		var mu := 0.7 if _is_leg[i] else float(tyres["grip"]) * (float(tyres["rear_grip"]) if rear else 1.0) * grip_factor
		mu *= _ground_grip(i)
		var b := 0.0
		if not _is_leg[i]:
			if rear and _handbrake:
				mu *= float(brakes["handbrake_rear_grip"])
			var cap := mu * load
			# Along the road: engine and brakes, no more than the tyre can grip.
			fx = drive * _drive_share[i]
			b = _brake * float(brakes["force"]) * _brake_share[i]
			if rear and _handbrake:
				b = maxf(b, cap * 0.9)
			elif _abs:
				# Anti-lock brakes: never more than the tyre can take.
				b = minf(b, cap * 0.92)
			# Brakes stop the wheel, never push it backwards.
			fx -= signf(vl) * minf(b, absf(vl) * _grip_m[i] / delta)
			var spinning := absf(fx) > cap
			var asked := absf(fx) / maxf(cap, 1.0)
			if spinning:
				# A tyre spinning in mud packs its tread and polishes the
				# rut: it pushes less than one just gripping.
				cap *= 1.0 - SPIN_LOSS * float(GroundMap.KINDS[_kind[i]]["soft"])
			fx = clampf(fx, -cap, cap)
			# Soft ground: pushing through it, and up out of the rut.
			fx -= signf(vl) * minf(resist[i], absf(vl) * _grip_m[i] / delta)
			_dig(i, spinning, asked, load, vl, delta)
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
			var hold := clampf(-vs * _grip_m[i] / delta * 0.5, -side_cap, side_cap)
			fy = lerpf(fy, hold, crawl)
			# How hard this tyre is sliding, for the squeal: pushed past what it
			# can hold sideways, spinning under power, locked under the brakes.
			var moving := smoothstep(1.0, 4.0, v.length())
			var slide := clampf((absf(stiff * slip) / maxf(side_cap, 1.0) - 1.0) * 0.2, 0.0, 1.0)
			if spinning:
				slide = maxf(slide, clampf((asked - 1.0) * 1.5, 0.0, 1.0))
			if rear and _handbrake and absf(vl) > 2.0:
				slide = maxf(slide, 0.6)
			_slide[i] = slide * maxf(moving, 0.6 if spinning else 0.0)
			skid = maxf(skid, _slide[i])
		# Stopped, the tyre (or a landing leg's foot) sticks where it is, in
		# the frame of what it stands on: sideways always, and along the road
		# too while the brakes are on. A stiff spring back to that spot, up to
		# its grip; pushed past that, the spot slides along with it.
		var stopped := absf(vl) < 0.3 and absf(vs) < 0.3
		if not stopped:
			_anchor[i] = null
		elif _anchor[i] == null or _anchor_on[i] != hit["collider"]:
			_anchor_on[i] = hit["collider"]
			_anchor[i] = (hit["collider"] as Node3D).global_transform.affine_inverse() * p
		if _anchor[i] != null:
			var along := _is_leg[i] or (b > 0.0 and absf(_throttle) < 0.05)
			var cap_hold := mu * load
			var w := TAU * 1.5
			var gm := _grip_m[i]
			var stuck := (_anchor_on[i] as Node3D).global_transform * (_anchor[i] as Vector3)
			var err := stuck - p
			err -= n * err.dot(n)
			var v_flat := w_fwd * vl + w_side * vs
			if not along:
				# Free to roll: only the sideways part holds.
				err -= w_fwd * err.dot(w_fwd)
				v_flat = w_side * vs
			var f := err * gm * w * w - v_flat * 2.0 * gm * w
			if f.length() > cap_hold:
				f = f.normalized() * cap_hold
				var reach := cap_hold / (gm * w * w)
				if err.length() > reach:
					_anchor[i] = (_anchor_on[i] as Node3D).global_transform.affine_inverse() * (p + err.normalized() * reach)
			fy = f.dot(w_side)
			if along:
				fx = f.dot(w_fwd)
		elif _is_leg[i]:
			# A leg's foot dragged along: plain sliding friction.
			var flat := w_fwd * vl + w_side * vs
			if flat.length() > 0.001:
				var fr := -flat.normalized() * mu * load
				fx = fr.dot(w_fwd)
				fy = fr.dot(w_side)
		total += w_fwd * fx + w_side * fy
		_push(total, p - global_position)
		if on != null and not on.freeze:
			# What pushes the wheel pushes the deck back.
			_push_on(on, -total, p - on.global_position)

	if _forces_out == null:
		_tyre_fx()
	if resist[_n] > 0.0:
		# The underside dragging through the mud.
		var flat := linear_velocity - up * linear_velocity.dot(up)
		var vf := flat.length()
		if vf > 0.001:
			_push_central(-flat / vf * minf(resist[_n], vf * mass / delta * 0.5))

	# --- air and rolling resistance, at the middle of the car ------------------------
	var air := -linear_velocity * linear_velocity.length() * float(body_spec["drag"])
	var rolling := Vector3.ZERO
	if wheels_down > 0:
		rolling = -fwd * speed * float(body_spec["rolling"])
	_push_central(air + rolling)
	if wheels_down > 0 and downforce > 0.0:
		_push_central(-up * downforce)


## The soft ground's hold on each tyre this step (N, index i), and on the
## underside (index _n), and what the car reports about the ground.
func _soft_ground(delta: float, tyres: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(_n + 1)
	var total := 0.0
	var push := 0.0 # what the driven wheels could push with
	var most := 0.0
	ground = GroundMap.PAVED
	ground_soft = 0.0
	var sunk := 0.0
	var down := 0
	var v := absf(speed)
	for i in _n:
		if _hits[i] == null or _is_leg[i]:
			continue
		var gk: Dictionary = GroundMap.KINDS[_kind[i]]
		var load := _loads[i]
		if load > most:
			most = load
			ground = _kind[i]
		ground_soft = maxf(ground_soft, float(gk["soft"]))
		sunk += _sink[i]
		down += 1
		var r := float(gk["rolling"]) + float(gk["churn"]) * v + SINK_DRAG * _sink[i] / _radius[i]
		out[i] = load * r
		total += out[i]
		if _drive_share[i] > 0.0:
			# (what it pushes with spinning, which is less: see the tyres)
			push += load * float(tyres["grip"]) * _ground_grip(i) * (1.0 - SPIN_LOSS * float(gk["soft"]))
	if down > 0:
		# Sunk past the underside: the floor drags in the mud too.
		var over := sunk / down - (_belly - 0.04)
		if over > 0.0:
			out[_n] = mass * 9.81 * 0.3 * clampf(over / 0.06, 0.0, 1.0)
			total += out[_n]
	# At a crawl, never more than the driven wheels can push against, so
	# a car is never stuck for good (bogged down to walking pace, though).
	var lim := CRAWL_RESERVE * push
	if total > lim and push > 0.0:
		var keep := lerpf(lim / total, 1.0, smoothstep(0.8, 1.8, v))
		for i in _n + 1:
			out[i] *= keep
	bogged = clampf(total / maxf(push, 1.0), 0.0, 1.0) * ground_soft if absf(_throttle) > 0.1 else 0.0
	# Mud on the body: thrown up off soft ground, worn off on pavement.
	if ground_soft > 0.0 and down > 0:
		var spin := 0.0
		for i in _n:
			spin = maxf(spin, _wheel_spin[i])
		dirt = minf(1.0, dirt + delta * ground_soft * ground_soft * (v * 0.004 + spin * 0.01))
		dirt_colour = GroundMap.KINDS[ground]["mud"]
	elif down > 0:
		dirt = maxf(0.0, dirt - delta * v * 0.00015)
	return out


## How far tyre i sinks in: it settles to its depth for the load, digs in
## while it spins, and comes up again as it rolls onto fresh ground.
func _dig(i: int, spinning: bool, asked: float, load: float, vl: float, delta: float) -> void:
	var gk: Dictionary = GroundMap.KINDS[_kind[i]]
	var moved := absf(vl) * delta
	var spin_v := clampf(asked - 1.0, 0.0, 2.0) * 3.0 if spinning else 0.0
	_wheel_spin[i] = move_toward(_wheel_spin[i], spin_v, delta * 20.0)
	if float(gk["sink"]) <= 0.0:
		_sink[i] = move_toward(_sink[i], 0.0, delta * 0.3 + moved * 0.5)
		return
	# Wide, tall tyres sit on top; a heavily loaded one sinks deeper.
	var float_f := sqrt(0.31 / _radius[i]) * sqrt(0.105 / maxf(_half_tread[i], 0.05))
	var settle := float(gk["sink"]) * clampf(load / maxf(_static_load[i], 1.0), 0.0, 2.0) * float_f
	var deepest := minf(settle + float(gk["dig"]) * float_f, _belly + 0.04)
	if spinning:
		_sink[i] = minf(deepest, _sink[i] + DIG_RATE * clampf(asked - 1.0, 0.0, 2.0) * 0.5 * delta)
	elif _sink[i] > settle:
		_sink[i] = move_toward(_sink[i], settle, moved * CLIMB_OUT)
	else:
		_sink[i] = move_toward(_sink[i], settle, delta * 0.2)


func _animate(delta: float) -> void:
	for i in _n:
		var w := _wheels[i]
		var m := _mounts[i]
		w.position = Vector3(m.x, m.y - _wheel_drop[i], m.z)
		w.rotation.y = steer_angle * _steer_factor[i]
		_spin[i] -= (speed + _wheel_spin[i] * signf(_throttle)) * delta / _radius[i]
		_wheel_meshes[i].rotation.x = _spin[i]
	if steering_wheel != null:
		var turn := steer_angle / deg_to_rad(maxf(1.0, max_steer_degrees)) * CarBuilder.STEER_WHEEL_TURN
		steering_wheel.basis = _steer_rest * Basis(Vector3.BACK, turn)

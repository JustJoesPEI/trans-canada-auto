class_name TowLine
extends Node3D
## A line between a vehicle and something else: a winch cable, a tow
## strap. One end is on the vehicle that owns it (a point in its frame,
## which can move, as a tow truck's deck does); the other is on another
## body (a car, a load) or on something fixed (a tree, a post, a pole).
##
## A line only pulls: slack, it does nothing; stretched, it pulls both ends
## together, as hard as it's stretched (CABLE_K for steel, much softer for
## a nylon strap, which stretches and snaps a stuck car out), damped so it
## doesn't twang. A winch can reel it in, up to what its motor can pull
## (it stalls past `max_force`), or pay it out. A strap has a fixed length:
## you pull by driving away.
##
## Drawn as one thin cylinder stretched from end to end (one shared
## material per kind of line).

const CABLE_K := 160000.0 ## N per metre of stretch: steel cable
const STRAP_K := 22000.0 ## a nylon recovery strap, which stretches a fifth or so

var car: RigidBody3D ## the vehicle it's on
var a_local := Vector3.ZERO ## its end on `car`, in car's frame
var other: CollisionObject3D ## what it's hooked to
var b_local := Vector3.ZERO ## the hook, in other's frame
var length := 1.0 ## m, slack up to here
var stiffness := CABLE_K
## What it can pull before the winch stalls (or, for a strap, before it
## stops stretching any harder).
var max_force := 55000.0
## Reeling in and paying out (m/s); 0 for a strap.
var reel_speed := 0.0
var payout_speed := 1.2
## -1 paying out .. 1 reeling in, set by whoever works it.
var lever := 0.0
var tension := 0.0
## Tension steadied for a gauge (N).
var shown_tension := 0.0
## Reeling now (m/s of cable, + in), eased, for the winch's sound.
var reel_rate := 0.0
var stalled := false

var _mesh: MeshInstance3D
static var _materials := {}


## Hooks `owner_car` at `a` (in its frame) to `to` at world point `at`,
## with the slack taken up.
static func make(owner_car: RigidBody3D, a: Vector3, to: CollisionObject3D, at: Vector3, strap := false) -> TowLine:
	var l := TowLine.new()
	l.name = "TowLine"
	l.car = owner_car
	l.a_local = a
	l.other = to
	l.b_local = to.global_transform.affine_inverse() * at
	l.length = (owner_car.global_transform * a).distance_to(at) + 0.05
	if strap:
		l.stiffness = STRAP_K
		l.max_force = 90000.0
	owner_car.add_child(l)
	return l


func _ready() -> void:
	top_level = true
	_mesh = MeshInstance3D.new()
	var strap := stiffness < CABLE_K
	var key := "strap" if strap else "cable"
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		if strap:
			m.albedo_color = Color(0.85, 0.55, 0.08) # bright recovery-strap orange
			m.roughness = 0.9
		else:
			m.albedo_color = Color(0.18, 0.18, 0.19)
			m.metallic = 0.6
			m.roughness = 0.4
		_materials[key] = m
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025 if strap else 0.012
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = _materials[key]
	_mesh.mesh = cyl
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = false
	add_child(_mesh)


func a_point() -> Vector3:
	return car.global_transform * a_local


func b_point() -> Vector3:
	return other.global_transform * b_local


## True while both ends are still there.
func valid() -> bool:
	return is_instance_valid(other) and other.is_inside_tree() and is_instance_valid(car)


## Each physics step, from the vehicle: reel, then pull.
func physics(delta: float) -> void:
	if not valid():
		tension = 0.0
		return
	var a := a_point()
	var b := b_point()
	var span := b - a
	var d := span.length()
	var dir := span / maxf(d, 0.001) # from this end toward the hook
	var want := lever * (reel_speed if lever > 0.0 else payout_speed)
	var full := maxf(reel_speed, 0.1)
	reel_rate = VehicleTool.ease_rate(reel_rate, want, full, delta)
	if reel_rate < 0.0:
		length += -reel_rate * delta
	var body := other as RigidBody3D
	var v_b := Vector3.ZERO
	var m := car.mass
	if body != null:
		v_b = body.linear_velocity + body.angular_velocity.cross(b - body.global_transform * body.center_of_mass)
		m = body.mass * car.mass / (body.mass + car.mass)
	var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	var stretch_rate := (v_b - state.get_velocity_at_local_position(a - car.global_position)).dot(dir)
	var c := 2.0 * 0.7 * sqrt(stiffness * m)
	tension = 0.0
	if d > length:
		tension = maxf(0.0, stiffness * (d - length) + c * stretch_rate)
	if reel_rate > 0.0 and tension < max_force * 0.95:
		length = maxf(0.5, length - reel_rate * delta)
	stalled = false
	if tension > max_force:
		# The winch stalls (the drum slips rather than pull harder); a
		# strap at full stretch.
		tension = max_force
		stalled = reel_speed > 0.0
		length = maxf(length, d - max_force / stiffness)
	shown_tension = lerpf(shown_tension, tension, 1.0 - exp(-delta / 0.4))
	if tension > 0.0:
		if body != null and not body.freeze:
			body.apply_force(-dir * tension, b - body.global_position)
		car.apply_force(dir * tension, a - car.global_position)


func _process(_delta: float) -> void:
	if not valid():
		_mesh.visible = false
		return
	var a := a_point()
	var b := b_point()
	var span := b - a
	var l := span.length()
	if l < 0.01:
		_mesh.visible = false
		return
	# Slack, it sags a little: drawn a touch below the straight line.
	var sag := clampf((length - l) * 0.3, 0.0, 0.6)
	_mesh.visible = true
	var y := span / l
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_mesh.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5 - Vector3.UP * sag)


## The name of what it's hooked to, for the HUD.
func other_name() -> String:
	if other is Car:
		return (other as Car).display_name()
	if other is Cargo:
		return (other as Cargo).display_name()
	return str(other.get_meta("anchor_name", "anchor")) if other != null else ""

class_name CraneTool
extends VehicleTool
## A crane truck's knuckle-boom crane ("picker", TruckModels "crane_truck").
##
## Stopped, the stabiliser legs go down first (work_down): their beams
## slide out of the box under the column and the jacks push the pads onto
## the ground, taking the truck's weight off its springs. The legs are real
## collision, so they're what keeps the truck from tipping when a load
## hangs out to the side. Until they're down the crane doesn't move, and
## while they're down the truck can't drive: the driving controls work the
## crane instead, as a crane's own control stand would.
##
## The crane: the column slews round on its turntable (steering), the
## inner boom luffs up and down (throttle and brake), the outer boom
## unfolds at the knuckle and then telescopes out (aux_in / aux_out), and
## the hook goes up and down on its rope (work_up / work_down). "hitch"
## hooks a load under the hook or lets it go; "handbrake" folds everything
## away and brings the legs up.
##
## The rope is a TowLine from the boom's tip to the top of the load, so the
## load hangs, swings and sets down by real physics, and its weight pulls
## on the truck through the tip. The hoist can lift what the crane is rated
## for at that reach (the "moment" over the reach, up to "max_lift"); past
## that it stalls, as a load-moment limiter stops a real one.

const SLEW_SPEED := 0.35 ## rad/s
const BOOM_SPEED := 0.24 ## rad/s
const REACH_SPEED := 0.2 ## of the whole reach travel per second
const HOIST_UP := 0.55 ## m/s
const HOIST_DOWN := 0.8 ## m/s
const LEGS_SPEED := 0.3 ## of the legs' travel per second
const LEGS_SLIDE := 0.6 ## the first part of the legs' travel slides out, the rest jacks down
## The legs jack this much further on Jolt, which lets bodies sink into
## each other by its "penetration slop" (2 cm) before it pushes them apart:
## a couple of centimetres of jack would be taken up by that, and the truck
## wouldn't rise off its springs.
static var _SLOP := float(ProjectSettings.get_setting("physics/jolt_physics_3d/simulation/penetration_slop", 0.02)) \
		if str(ProjectSettings.get_setting("physics/3d/physics_engine", "")).contains("Jolt") else 0.0
const BOOM_MIN := deg_to_rad(-12.0)
const BOOM_MAX := deg_to_rad(78.0)
const KNUCKLE_FOLDED := deg_to_rad(-158.0) ## the outer boom folded back down beside the inner
const HOOK_MIN := 0.35 ## m of rope below the tip, hook all the way up
const HOOK_MAX := 12.0
const HOOK_REACH := 0.9 ## m from the hook to a load's lifting point to hook it
const G := 9.81

enum Mode { STOWED, LEGS_OUT, WORKING, FOLDING, LEGS_IN }

var mode := Mode.STOWED
var legs := 0.0 ## 0 stowed .. 1 down on the ground
var slew := 0.0 ## radians, 0 with the boom back over the deck, + anticlockwise from above (as steering left turns)
var boom := 0.0 ## the inner boom's angle above level (radians)
var reach := 0.0 ## 0 folded .. 0.5 the knuckle straight .. 1 telescoped all the way
var hook_len := HOOK_MIN ## rope below the tip while nothing's hooked (m)
## The hoist rope while it's hooked to a load.
var line: TowLine = null
var hooked: RigidBody3D:
	get:
		return line.other as RigidBody3D if line != null else null

var _base := Vector3.ZERO
var _pivot := Vector3.ZERO
var _inner := 2.0
var _outer := 2.3
var _extend := 2.5
var _stow := deg_to_rad(68.0)
var _legs_out := 1.2
var _legs_down := 0.35
var _moment := 8500.0
var _max_lift := 2500.0
var _slew_rate := 0.0
var _boom_rate := 0.0
var _reach_rate := 0.0
var _hoist_rate := 0.0
var _held := false # we're holding the car's driving controls
var _hook: MeshInstance3D
var _rope: MeshInstance3D
static var _rope_material: StandardMaterial3D


func setup(owner_car: Car) -> void:
	super.setup(owner_car)
	var c: Dictionary = car.shape["crane"]
	_base = TruckBuilder._v3(c["base"])
	_pivot = _base + TruckBuilder._v3(c["pivot"])
	_inner = float(c["inner"])
	_outer = float(c["outer"])
	_extend = float(c["extend"])
	_stow = deg_to_rad(float(c["stow_degrees"]))
	_legs_out = float(c["legs_out"])
	_legs_down = float(c["legs_down"])
	_moment = float(c["moment"])
	_max_lift = float(c["max_lift"])
	boom = _stow
	_hook = MeshInstance3D.new()
	_hook.name = "CraneHook"
	_hook.mesh = TruckBuilder.crane_hook_mesh()
	_hook.top_level = true
	_hook.visibility_range_end = 120.0
	car.add_child.call_deferred(_hook)
	if _rope_material == null:
		_rope_material = StandardMaterial3D.new()
		_rope_material.albedo_color = Color(0.18, 0.18, 0.19)
		_rope_material.metallic = 0.6
		_rope_material.roughness = 0.4
	_rope = MeshInstance3D.new()
	_rope.name = "CraneRope"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.011
	cyl.bottom_radius = 0.011
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = _rope_material
	_rope.mesh = cyl
	_rope.top_level = true
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rope.visibility_range_end = 120.0
	car.add_child.call_deferred(_rope)
	_place()


# --- where the parts are -----------------------------------------------------------------

## The knuckle's angle (radians, from straight) and how far the outer boom
## is telescoped (m), for a reach of r.
func knuckle_angle(r: float) -> float:
	return lerpf(KNUCKLE_FOLDED, 0.0, clampf(r / 0.5, 0.0, 1.0))


func extension(r: float) -> float:
	return _extend * clampf((r - 0.5) / 0.5, 0.0, 1.0)


func _about(p: Vector3, b: Basis) -> Transform3D:
	return Transform3D(Basis.IDENTITY, p) * Transform3D(b, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -p)


func column_xform() -> Transform3D:
	return _about(_base, Basis(Vector3.UP, slew))


func boom_xform() -> Transform3D:
	return column_xform() * _about(_pivot, Basis(Vector3.RIGHT, -boom))


func jib_xform() -> Transform3D:
	var knuckle := _pivot + Vector3(0.0, 0.0, _inner)
	return boom_xform() * _about(knuckle, Basis(Vector3.RIGHT, -knuckle_angle(reach)))


func ext_xform() -> Transform3D:
	return jib_xform() * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, extension(reach)))


## The sheave at the tip, where the rope comes down (in the truck's frame).
func tip_local() -> Vector3:
	return ext_xform() * (_pivot + Vector3(0.0, -0.1, _inner + _outer + 0.3))


func tip_point() -> Vector3:
	return car.global_transform * tip_local()


## Level distance from the column to the tip (m).
func reach_m() -> float:
	var t := tip_local()
	return Vector2(t.x - _base.x, t.z - _base.z).length()


## What it can lift at the reach it has now (kg).
func capacity() -> float:
	return minf(_max_lift, _moment / maxf(reach_m(), 1.0))


## Where the hook hangs (the rope's end, world).
func hook_point() -> Vector3:
	if line != null and line.valid():
		return line.b_point() + Vector3.UP * 0.55
	return tip_point() + Vector3.DOWN * hook_len


func _place() -> void:
	car.set_part_transform("crane_column", column_xform())
	car.set_part_transform("crane_boom", boom_xform())
	car.set_part_transform("crane_jib", jib_xform())
	car.set_part_transform("crane_ext", ext_xform())
	var slide := _legs_out * clampf(legs / LEGS_SLIDE, 0.0, 1.0)
	var drop := (_legs_down + _SLOP) * clampf((legs - LEGS_SLIDE) / (1.0 - LEGS_SLIDE), 0.0, 1.0)
	car.set_part_transform("leg_l", Transform3D(Basis.IDENTITY, Vector3(-slide, -drop, 0.0)))
	car.set_part_transform("leg_r", Transform3D(Basis.IDENTITY, Vector3(slide, -drop, 0.0)))


## Set the crane directly (for tests and placing a truck): legs 0..1,
## slew and boom in degrees, reach 0..1, the hook's rope in metres.
func set_pose(new_legs: float, slew_degrees: float, boom_degrees: float, new_reach: float, rope := HOOK_MIN) -> void:
	legs = clampf(new_legs, 0.0, 1.0)
	slew = deg_to_rad(slew_degrees)
	boom = clampf(deg_to_rad(boom_degrees), BOOM_MIN, BOOM_MAX)
	reach = clampf(new_reach, 0.0, 1.0)
	hook_len = clampf(rope, HOOK_MIN, HOOK_MAX)
	mode = Mode.WORKING if legs >= 1.0 else Mode.STOWED
	_place()


# --- working it --------------------------------------------------------------------------

func _pressed(action: String) -> bool:
	return car.driver != null and Input.is_action_just_pressed(action)


func physics(delta: float) -> void:
	var stopped := absf(car.speed) < 0.5
	match mode:
		Mode.STOWED:
			if _axis("work_up", "work_down") > 0.5 and stopped:
				mode = Mode.LEGS_OUT
		Mode.LEGS_OUT:
			legs = minf(1.0, legs + LEGS_SPEED * delta)
			if legs >= 1.0:
				mode = Mode.WORKING
				stops += 1
		Mode.WORKING:
			_work(delta)
			if _pressed("handbrake") and line == null:
				mode = Mode.FOLDING
		Mode.FOLDING:
			if _fold(delta):
				mode = Mode.LEGS_IN
		Mode.LEGS_IN:
			legs = maxf(0.0, legs - LEGS_SPEED * delta)
			if legs <= 0.0:
				mode = Mode.STOWED
				stops += 1
	if mode != Mode.WORKING:
		_slew_rate = 0.0
		_boom_rate = 0.0
		_reach_rate = 0.0
		_hoist_rate = 0.0
	# Hold the driving controls (steering, throttle) for the crane while the
	# legs are down; let them go once they're up.
	var hold := legs > 0.0 and car.driver != null
	if hold != _held:
		_held = hold
		car.controls_held = hold
	_place()
	_hoist(delta)


func _work(delta: float) -> void:
	var sw := 0.0
	var up := 0.0
	if car.driver != null:
		sw = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		up = Input.get_action_strength("accelerate") - Input.get_action_strength("brake_reverse")
	_slew_rate = ease_rate(_slew_rate, sw * SLEW_SPEED, SLEW_SPEED, delta)
	_boom_rate = ease_rate(_boom_rate, up * BOOM_SPEED, BOOM_SPEED, delta)
	_reach_rate = ease_rate(_reach_rate, _axis("aux_out", "aux_in") * REACH_SPEED, REACH_SPEED, delta)
	slew = wrapf(slew + _slew_rate * delta, -PI, PI)
	var b := boom + _boom_rate * delta
	boom = clampf(b, BOOM_MIN, BOOM_MAX)
	if boom != b and _boom_rate != 0.0:
		_boom_rate = 0.0
		stops += 1
	var r := reach + _reach_rate * delta
	reach = clampf(r, 0.0, 1.0)
	if reach != r and _reach_rate != 0.0:
		_reach_rate = 0.0
		stops += 1


## Moves everything toward its stowed place; true once it's there.
func _fold(delta: float) -> bool:
	hook_len = move_toward(hook_len, HOOK_MIN, HOIST_UP * delta)
	reach = move_toward(reach, 0.0, REACH_SPEED * delta)
	if reach < 0.35:
		slew = move_toward(slew, 0.0, SLEW_SPEED * delta)
	if absf(slew) < 0.01:
		boom = move_toward(boom, _stow, BOOM_SPEED * delta)
	return hook_len <= HOOK_MIN and reach <= 0.0 and absf(slew) <= 0.0 and is_equal_approx(boom, _stow)


func _hoist(delta: float) -> void:
	var lever := _axis("work_down", "work_up") if mode == Mode.WORKING else 0.0
	if line != null:
		if not line.valid():
			_let_go()
			return
		line.a_local = tip_local()
		line.lever = lever
		line.max_force = capacity() * G * 1.1
		line.physics(delta)
		_hoist_rate = line.reel_rate
		return
	var want := lever * (HOIST_UP if lever > 0.0 else HOIST_DOWN)
	_hoist_rate = ease_rate(_hoist_rate, want, HOIST_DOWN, delta)
	var l := hook_len - _hoist_rate * delta
	hook_len = clampf(l, HOOK_MIN, HOOK_MAX)
	if hook_len != l and _hoist_rate != 0.0:
		_hoist_rate = 0.0
		stops += 1


func _process(_delta: float) -> void:
	if car == null or _hook == null or not _hook.is_inside_tree():
		return
	var tip := tip_point()
	var h := hook_point()
	_hook.global_transform = Transform3D(Basis(Vector3.UP, car.global_rotation.y + slew), h)
	var show_rope := line == null and h.distance_to(tip) > 0.05
	_rope.visible = show_rope
	if show_rope:
		var span := h - tip
		var l := span.length()
		var y := span / l
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		_rope.global_transform = Transform3D(Basis(x, y * l, x.cross(y)), (tip + h) * 0.5)


func holds_still() -> bool:
	return legs > 0.0


## The hitch key: stopped with the crane stowed, put the legs down; with
## it working, hook the load under the hook or let it go.
func hitch_action() -> String:
	match mode:
		Mode.STOWED:
			if absf(car.speed) >= 0.5:
				return "Stop first, then put the legs down"
			mode = Mode.LEGS_OUT
			return "Stabiliser legs going down"
		Mode.WORKING:
			pass
		_:
			return "Wait for the legs"
	if line != null:
		var what := _name_of(hooked)
		_let_go()
		return "Let go of the %s" % what
	var best := _load_under_hook()
	if best == null:
		return "Nothing under the hook: lower it onto the top of a load"
	if car.tie_downs.has(best):
		car.tie_downs.release(best)
	var at := best.global_transform * lift_point(best)
	line = TowLine.make(car, tip_local(), best, at)
	line.reel_speed = HOIST_UP
	line.payout_speed = HOIST_DOWN
	line.max_force = capacity() * G * 1.1
	var kg := best.mass
	var s := "Hooked the %s, %s kg" % [_name_of(best), ForkliftTool._thousands(kg)]
	if kg > capacity():
		s += ": too heavy at this reach, bring the boom in"
	return s


## Where a load is hooked (its frame): the middle of its top, where the
## slings meet.
static func lift_point(b: RigidBody3D) -> Vector3:
	if b is Cargo:
		return Vector3(0.0, (b as Cargo).size.y, 0.0)
	return Vector3.ZERO


func _load_under_hook() -> RigidBody3D:
	var tip := tip_point()
	var hook_end := tip + Vector3.DOWN * (hook_len + 0.55)
	var best: RigidBody3D = null
	var best_d := INF
	for n in car.get_tree().get_nodes_in_group("cargo"):
		var b := n as RigidBody3D
		if b == null or not b.is_inside_tree():
			continue
		var p := b.global_transform * lift_point(b)
		var flat := Vector2(p.x - hook_end.x, p.z - hook_end.z).length()
		var dy := hook_end.y - p.y
		if flat > HOOK_REACH or dy > 0.9 or dy < -0.6:
			continue
		if flat < best_d:
			best_d = flat
			best = b
	return best


func _let_go() -> void:
	if line == null:
		return
	if line.valid():
		# The hook stays where it was: the rope's length now.
		hook_len = clampf(line.a_point().distance_to(line.b_point()) - 0.55, HOOK_MIN, HOOK_MAX)
	line.queue_free()
	line = null


## Folded away with the legs up: ready to drive.
func stowed() -> bool:
	return mode == Mode.STOWED


func motion() -> float:
	if mode == Mode.LEGS_OUT or mode == Mode.LEGS_IN or mode == Mode.FOLDING:
		return 0.8
	return clampf(maxf(maxf(absf(_slew_rate) / SLEW_SPEED, absf(_boom_rate) / BOOM_SPEED), maxf(absf(_reach_rate) / REACH_SPEED, absf(_hoist_rate) / HOIST_DOWN)), 0.0, 1.0)


func reel_motion() -> float:
	return clampf(absf(_hoist_rate) / HOIST_UP, 0.0, 1.0)


func _name_of(b: RigidBody3D) -> String:
	if b is Cargo:
		return (b as Cargo).display_name()
	if b is Car:
		return (b as Car).display_name()
	return "load"


func controls() -> Array:
	match mode:
		Mode.STOWED:
			return [[["work_down"], "stabiliser legs down (stopped)"], [["strap"], "strap the load / undo"], [["horn"], "horn", "pad"]]
		Mode.WORKING:
			return [[["steer_left", "steer_right"], "swing the crane"], [["accelerate", "brake_reverse"], "boom up / down"],
				[["aux_in", "aux_out"], "boom out / in"], [["work_up", "work_down"], "hook up / down"],
				[["hitch"], "let go of the load" if line != null else "hook the load"],
				[["handbrake"], "fold up and raise the legs" if line == null else "(let go first to fold up)"],
				[["strap"], "strap the load / undo"]]
	return [[["strap"], "strap the load / undo"]]


func status() -> String:
	match mode:
		Mode.STOWED:
			return "Crane stowed"
		Mode.LEGS_OUT:
			return "Legs going down"
		Mode.FOLDING:
			return "Folding the crane away"
		Mode.LEGS_IN:
			return "Legs coming up"
	var cap := capacity()
	var s := "Reach %.1f m, lifts %s kg" % [reach_m(), ForkliftTool._thousands(cap)]
	if line != null:
		var kg := hooked.mass if hooked != null else 0.0
		s += "  ·  on the hook: %s, %s kg" % [_name_of(hooked), ForkliftTool._thousands(kg)]
		if line.stalled or kg > cap:
			s += "  ·  TOO HEAVY HERE: bring the boom in"
	else:
		s += "  ·  hook %.1f m down" % hook_len
	return s


## What the drive-off prompt says while it holds the truck still ("" for
## nothing: the driving controls work the crane).
func drive_off_hint() -> String:
	return "" if mode == Mode.WORKING else "Wait for the legs"

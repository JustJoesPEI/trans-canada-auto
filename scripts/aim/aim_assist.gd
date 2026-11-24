class_name AimAssist
extends RefCounted
## Controller aim assist (docs/design.md, "Controllers and aim assist"):
## help the stick with what a stick is bad at, never aim for you. Only
## while aiming, only with a controller, never with a mouse.
##
## - Slowdown: with the crosshair over a target or just beside one, the
##   stick turns the view at 60% speed, so small corrections are easy. It
##   does nothing unless you put the crosshair there yourself, and nothing
##   while turn boost is whipping you round.
## - Tracking: with the crosshair on a target, the view follows 40% of its
##   movement across the view, whether the target moves or you do; you do
##   the other 60%. Full strength to 25 m, fading to nothing at 40 m.
##   Pushing the stick against it switches it off for that axis.
## - Police aim-in snap: starting to aim with an officer within 25 m and 8
##   degrees of the crosshair eases the crosshair onto them over 0.15 s.
##   Officers only, never players or anyone else; `AimSettings.police_snap`
##   turns it off (events do).
##
## All of it checks line of sight (nothing through walls, cars, loads or
## other people), skips anyone who's out, and scales with the Aim assist
## setting: Standard full, Low half (half the slowdown and tracking, and
## the snap's cone halved to 4 degrees), Off none.
##
## Joining in. Anything that can be aimed at puts itself in the group
## "aim_targets" (it must be a Node3D). It may also have:
##   aim_points() -> Array[Vector3]   where on it to aim, in world space
##       (default: its position plus 1.2 m up, about the chest of a person
##       standing on its origin). The help goes to whichever point is
##       nearest the crosshair; the zone round each point is taller than it
##       is wide, like a person.
##   is_out() -> bool   true while it's out of play, and for anyone this
##       player can't hit (bystanders in an event zone): no help onto it.
##   is_police() -> bool   true for officers (the computer, not a person):
##       the only targets the aim-in snap goes to.
## Its collision can be on any layer; a line-of-sight ray that hits the
## target itself (or one of its children) counts as clear.

const GROUP := "aim_targets"
const DEFAULT_HEIGHT := 1.2

const SLOWDOWN := 0.6 ## stick speed over a target, at full strength
const TRACKING := 0.4 ## share of the target's motion across the view that's followed
const TRACK_FULL := 25.0 ## metres: tracking at full strength up to here...
const TRACK_ZERO := 40.0 ## ...and none from here
const REACH := 60.0 ## metres: no slowdown on anything further off
## The zone round an aim point, in metres across at the target's distance:
## inside CORE the crosshair is "on" (full slowdown and tracking), fading to
## nothing at BESIDE. Far off they're kept at least this wide in angle, so a
## distant target isn't a pinhead.
const CORE := 0.45
const BESIDE := 1.1
const CORE_ANGLE := 0.014 ## radians, about 0.8 degrees
const BESIDE_ANGLE := 0.031 ## about 1.8 degrees
## Up and down counts for this much of the miss: the zone is a tall oval.
const UPRIGHT := 0.55
const SLOW_EASE := 0.06 ## seconds for the slowdown to come in and go
const MAX_TRACK_STEP := 0.2 ## radians in a frame: more is a teleport, not motion

const SNAP_RANGE := 25.0
const SNAP_CONE := 0.1396 ## 8 degrees
const SNAP_TIME := 0.15

const LOS_MASK := Layers.GROUND | Layers.SOLID | Layers.VEHICLES | Layers.CHARACTERS | Layers.CARGO

## Multiplier on the stick's turn speed this frame (1 = none).
var slow := 1.0
## What to add to the view's yaw and pitch (radians, pitch positive down)
## this frame for tracking.
var track := Vector2.ZERO
## The target the crosshair is on (being helped), or null.
var target: Node3D = null
## True while the aim-in snap is easing onto an officer.
var snapping := false

var _prev_target: Node3D = null
var _prev_index := -1
var _prev_dir := Vector3.ZERO
var _target_index := -1
var _ray := PhysicsRayQueryParameters3D.new()
var _snap_target: Node3D = null
var _snap_index := 0
var _snap_t := 0.0
var _snap_e := 0.0
var _snap_shoulder := 0.0


func _init() -> void:
	_ray.collision_mask = LOS_MASK


## The assist strength for this frame: 0 unless aiming with a controller,
## then the setting's (1 Standard, 0.5 Low, 0 Off).
static func strength(aiming: bool) -> float:
	if not aiming or not InputDevice.controller:
		return 0.0
	return AimSettings.assist_strength()


## Where on a target to aim (see the class notes).
static func points_of(t: Node3D) -> Array:
	if t.has_method("aim_points"):
		var pts: Variant = t.call("aim_points")
		if pts is Array and not (pts as Array).is_empty():
			return pts
	return [t.global_position + Vector3.UP * DEFAULT_HEIGHT]


static func is_out(t: Node3D) -> bool:
	return t.has_method("is_out") and bool(t.call("is_out"))


static func is_police(t: Node3D) -> bool:
	return t.has_method("is_police") and bool(t.call("is_police"))


## Yaw and pitch (positive down) of a direction, the way the camera rig
## measures its own: yaw 0 looks along -Z.
static func angles_of(d: Vector3) -> Vector2:
	var n := d.normalized()
	return Vector2(atan2(-n.x, -n.z), asin(clampf(-n.y, -1.0, 1.0)))


## Run once a frame. host: any node in the world (for the tree and physics).
## view: the camera, where the crosshair points (-Z). origin: the point the
## view turns about and paint flies from (the shooter's shoulders): lines of
## sight and the targets' motion are measured from here. exclude: the
## shooter's own collision. power: strength() for this frame. boosting:
## turn boost is on. Sets `slow`, `track` and `target`.
func update(host: Node3D, view: Transform3D, origin: Vector3, exclude: Array[RID], power: float, delta: float, boosting := false) -> void:
	track = Vector2.ZERO
	target = null
	_target_index = -1
	var point := Vector3.ZERO
	var on := 0.0
	if power > 0.0:
		var found := _find(host, view, origin, exclude)
		if not found.is_empty():
			target = found["target"]
			_target_index = found["index"]
			point = found["point"]
			on = found["on"]
	if power <= 0.0:
		slow = 1.0
	else:
		var goal := 1.0
		if target != null and not boosting:
			goal = lerpf(1.0, 1.0 - (1.0 - SLOWDOWN) * power, on)
		slow = lerpf(slow, goal, 1.0 - exp(-delta / SLOW_EASE))
	var dir := point - origin
	if target != null and target == _prev_target and _target_index == _prev_index:
		var dist := dir.length()
		var fade := 1.0 - clampf((dist - TRACK_FULL) / (TRACK_ZERO - TRACK_FULL), 0.0, 1.0)
		var k := TRACKING * power * fade * on
		if k > 0.0:
			var a := angles_of(_prev_dir)
			var b := angles_of(dir)
			var step := Vector2(angle_difference(a.x, b.x), b.y - a.y)
			if step.length() < MAX_TRACK_STEP:
				track = step * k
	_prev_target = target
	_prev_index = _target_index
	_prev_dir = dir


## The best target under or beside the crosshair that can be seen:
## {target, index, point, on (0..1)}, or empty.
func _find(host: Node3D, view: Transform3D, origin: Vector3, exclude: Array[RID]) -> Dictionary:
	var fwd := -view.basis.z.normalized()
	var right := view.basis.x.normalized()
	var up := view.basis.y.normalized()
	var found: Array = []
	for node in host.get_tree().get_nodes_in_group(GROUP):
		var t := node as Node3D
		if t == null or not t.is_inside_tree() or is_out(t):
			continue
		if t.global_position.distance_squared_to(origin) > (REACH + 3.0) * (REACH + 3.0):
			continue
		var pts := points_of(t)
		for i in pts.size():
			var p: Vector3 = pts[i]
			if p.distance_to(origin) > REACH:
				continue
			var on := _onness(view.origin, fwd, right, up, p)
			if on > 0.0:
				found.append({"target": t, "index": i, "point": p, "on": on, "dist": p.distance_to(origin)})
	if found.is_empty():
		return {}
	# Most on the crosshair first; nearer first between equals.
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["on"]) - float(b["on"])) > 0.001:
			return float(a["on"]) > float(b["on"])
		return float(a["dist"]) < float(b["dist"]))
	var space := host.get_world_3d().direct_space_state
	for f: Dictionary in found:
		if can_see(space, origin, f["point"], f["target"], exclude):
			return f
	return {}


## 1 with the crosshair on the point, fading to 0 just beside it.
static func _onness(eye: Vector3, fwd: Vector3, right: Vector3, up: Vector3, p: Vector3) -> float:
	var v := p - eye
	var along := v.dot(fwd)
	if along < 1.0:
		return 0.0
	var dx := v.dot(right)
	var dy := v.dot(up) * UPRIGHT
	var miss := sqrt(dx * dx + dy * dy)
	var core := maxf(CORE, along * CORE_ANGLE)
	var beside := maxf(BESIDE, along * BESIDE_ANGLE)
	return 1.0 - smoothstep(core, beside, miss)


## True when nothing but the target itself is between from and the point.
func can_see(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, t: Node3D, exclude: Array[RID]) -> bool:
	_ray.from = from
	_ray.to = to
	_ray.exclude = exclude
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return true
	var col := hit["collider"] as Node
	return col != null and (col == t or t.is_ancestor_of(col))


## Starting to aim: look for an officer to ease onto. dir is where the
## crosshair will point once the view has come up to aim. shoulder: how far
## to the right of origin the crosshair's line runs (the over-the-shoulder
## view), so the snap puts the crosshair itself on them. Returns true when
## the snap starts; then call snap_step() every frame while `snapping`.
func begin_snap(host: Node3D, origin: Vector3, dir: Vector3, exclude: Array[RID], power: float, shoulder := 0.0) -> bool:
	snapping = false
	_snap_target = null
	if power <= 0.0 or not AimSettings.police_snap:
		return false
	var cone := SNAP_CONE * (1.0 if power >= 1.0 else 0.5)
	var best_angle := INF
	var space := host.get_world_3d().direct_space_state
	for node in host.get_tree().get_nodes_in_group(GROUP):
		var t := node as Node3D
		if t == null or not t.is_inside_tree() or not is_police(t) or is_out(t):
			continue
		var pts := points_of(t)
		for i in pts.size():
			var p: Vector3 = pts[i]
			if p.distance_to(origin) > SNAP_RANGE:
				continue
			var angle := dir.angle_to(p - origin)
			if angle <= cone and angle < best_angle and can_see(space, origin, p, t, exclude):
				best_angle = angle
				_snap_target = t
				_snap_index = i
	if _snap_target == null:
		return false
	snapping = true
	_snap_shoulder = shoulder
	_snap_t = 0.0
	_snap_e = 0.0
	return true


## One frame of the snap: what to add to the view's yaw and pitch (positive
## down) from where it's aiming now (yaw, pitch).
func snap_step(origin: Vector3, yaw: float, pitch: float, delta: float) -> Vector2:
	if not snapping:
		return Vector2.ZERO
	if not is_instance_valid(_snap_target) or not _snap_target.is_inside_tree() or is_out(_snap_target):
		cancel_snap()
		return Vector2.ZERO
	_snap_t += delta
	var e := smoothstep(0.0, 1.0, _snap_t / SNAP_TIME)
	var f := 1.0 if e >= 1.0 else (e - _snap_e) / maxf(0.0001, 1.0 - _snap_e)
	_snap_e = e
	var pts := points_of(_snap_target)
	var v: Vector3 = pts[mini(_snap_index, pts.size() - 1)] - origin
	var a := angles_of(v)
	# The crosshair's line is off to the right: turn a little further, so it
	# runs through them rather than beside them.
	var flat := Vector2(v.x, v.z).length()
	if flat > absf(_snap_shoulder) + 0.1:
		a.x += asin(_snap_shoulder / flat)
	if _snap_t >= SNAP_TIME:
		snapping = false
	return Vector2(angle_difference(yaw, a.x), a.y - pitch) * f


func cancel_snap() -> void:
	snapping = false
	_snap_target = null


## Forget everything (not aiming, or the view jumped).
func reset() -> void:
	slow = 1.0
	track = Vector2.ZERO
	target = null
	_prev_target = null
	_prev_index = -1
	cancel_snap()

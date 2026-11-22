class_name CameraRig
extends Node3D
## Third-person follow camera that slides between a classic behind-the-back
## view (zoomed in) and an elevated, nearly overhead view (zoomed out).
##
## Framing: the camera aims a little above the target's head, so the target
## sits in the lower part of the screen with the street ahead in view.
## Zooming changes the height along a curve (closer = lower and behind,
## further = higher), and the mouse or right stick tilts on top of that.
## Movement uses critically damped springs: it keeps up without lag or
## overshoot. Leave the camera alone for a moment while moving and it eases
## back in behind. If a building would come between the target and the
## camera's spot, the camera moves in quickly and eases back out after;
## buildings and tree crowns that still block the view fade out of the way.
## `set_profile()` sets distance and angle together (used when driving).

@export var target: Node3D

@export_group("Framing")
@export var distance := 6.5 ## default metres from the target
@export var min_distance := 3.0
@export var max_distance := 30.0
@export var close_pitch_degrees := 14.0 ## look-down angle when fully zoomed in
@export var far_pitch_degrees := 55.0 ## look-down angle when fully zoomed out
@export var min_pitch_degrees := -12.0 ## below 0 looks up, e.g. at church spires
@export var max_pitch_degrees := 78.0
@export var look_height := 1.45 ## orbit point above the target's feet (about the shoulders)
@export var aim_above := 0.9 ## aim this far above the orbit point at close range, so the target sits low in frame
@export var fov := 58.0
@export var run_fov_boost := 6.0 ## extra degrees of view at a full run
@export var run_pull_back := 1.2 ## extra metres of distance at a full run

@export_group("Motion")
@export var follow_time := 0.11 ## seconds to catch up sideways (lower = tighter)
@export var follow_time_vertical := 0.28 ## steadier up and down (curbs)
@export var look_ahead := 0.4 ## seconds of the target's movement to look ahead
@export var max_look_ahead := 2.2 ## metres
@export var mouse_sensitivity := 0.0024
@export var mouse_smoothing := 0.035 ## seconds; a touch of smoothing on mouse turns
@export var stick_speed := 2.6 ## radians per second at full stick
@export var zoom_step := 1.15
@export var recenter_delay := 1.4 ## seconds without camera input before easing back behind
@export var recenter_time := 0.7 ## seconds it takes to come round

@export_group("Obstacles")
@export var avoid_buildings := true ## move in rather than end up inside a building
@export var fade_buildings := true
@export_range(0.0, 1.0) var faded_amount := 0.75

## Current orbit angle around the target (radians, 0 = camera south of target).
var yaw := 0.0
## When set, the camera drifts to sit behind this yaw (used while driving).
var auto_follow_yaw := false
var follow_yaw := 0.0
## How quickly it swings round to follow_yaw (per second).
var follow_rate := 2.5

@export_group("Driving")
@export var drive_distance := 8.2
@export var drive_pitch_degrees := 18.0
@export var drive_look_height := 1.05
@export var drive_look_ahead := 0.2
@export var drive_max_look_ahead := 3.0
@export var drive_pull_back := 1.6 ## extra metres at speed
@export var drive_aim_above := 0.15

var _on_foot := {}

@onready var camera: Camera3D = $Camera

var _user_distance := 6.5 ## where the player has zoomed to
var _distance := 6.5 ## smoothed, before obstacles
var _distance_vel := 0.0
var _arm := 6.5 ## actual distance after obstacles
var _arm_vel := 0.0
var _pitch_offset := 0.0 ## from mouse / stick, on top of the zoom curve
var _pitch := 0.0
var _yaw_goal := 0.0
var _yaw_vel := 0.0
var _focus := Vector3.ZERO
var _focus_vel := Vector3.ZERO
var _idle := 0.0
var _last_target_pos := Vector3.ZERO
var _target_vel := Vector3.ZERO
var _ahead := Vector3.ZERO
var _ahead_vel := Vector3.ZERO
var _fade_timer := 0.0
var _fade_now: Dictionary = {} ## MeshInstance3D -> true (occluding this check)
var _fade_level: Dictionary = {} ## MeshInstance3D -> current fade 0..1
var _fade_mats: Dictionary = {} ## MeshInstance3D -> its temporary faded materials
var _prop_fade: Dictionary = {} ## GeometryInstance3D (tree crowns) -> current fade
var _prop_now: Dictionary = {}
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	top_level = true
	# The camera moves every rendered frame already; it follows the target's
	# interpolated position instead of being interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_user_distance = distance
	_distance = distance
	_arm = distance
	_ray.collision_mask = Layers.SOLID
	if camera != null:
		camera.fov = fov


## Jump straight to the target with the camera behind it (no smoothing).
func snap_to_target() -> void:
	if target == null:
		return
	yaw = target.global_rotation.y
	_yaw_goal = yaw
	_yaw_vel = 0.0
	_focus = target.global_position + Vector3.UP * look_height
	_focus_vel = Vector3.ZERO
	_last_target_pos = target.global_position
	_target_vel = Vector3.ZERO
	_ahead = Vector3.ZERO
	_ahead_vel = Vector3.ZERO
	_distance = _user_distance
	_arm = _user_distance
	_pitch = _pitch_for(_distance)
	_place_camera()


## Switch between the on-foot camera and the driving camera, which sits
## lower and further back, looks further ahead, and swings behind the car.
func set_vehicle_mode(on: bool) -> void:
	if on:
		if _on_foot.is_empty():
			_on_foot = {"look_height": look_height, "look_ahead": look_ahead, "max_look_ahead": max_look_ahead,
				"run_pull_back": run_pull_back, "aim_above": aim_above, "user_distance": _user_distance, "pitch_offset": _pitch_offset}
		look_height = drive_look_height
		look_ahead = drive_look_ahead
		max_look_ahead = drive_max_look_ahead
		run_pull_back = drive_pull_back
		aim_above = drive_aim_above
		set_profile(drive_distance, drive_pitch_degrees)
		auto_follow_yaw = true
	else:
		if not _on_foot.is_empty():
			look_height = _on_foot["look_height"]
			look_ahead = _on_foot["look_ahead"]
			max_look_ahead = _on_foot["max_look_ahead"]
			run_pull_back = _on_foot["run_pull_back"]
			aim_above = _on_foot["aim_above"]
			_user_distance = _on_foot["user_distance"]
			_pitch_offset = _on_foot["pitch_offset"]
			_on_foot = {}
		auto_follow_yaw = false
	# Pick up the new target smoothly rather than jumping.
	if target != null:
		_last_target_pos = target.global_position


## Set distance and look-down angle together, e.g. pulled back and lower when driving.
func set_profile(new_distance: float, new_pitch_degrees: float) -> void:
	_user_distance = clampf(new_distance, min_distance, max_distance)
	_pitch_offset = deg_to_rad(new_pitch_degrees) - _zoom_pitch(_user_distance)


## Look-down angle the zoom curve gives for a distance.
func _zoom_pitch(d: float) -> float:
	var t := clampf((d - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t) # ease at both ends
	return deg_to_rad(lerpf(close_pitch_degrees, far_pitch_degrees, sqrt(t)))


func _pitch_for(d: float) -> float:
	return clampf(_zoom_pitch(d) + _pitch_offset, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_idle = 0.0
		_yaw_goal -= m.relative.x * mouse_sensitivity
		_pitch_offset += m.relative.y * mouse_sensitivity
		_clamp_offset()
	elif event.is_action_pressed("camera_zoom_in"):
		_user_distance = maxf(min_distance, _user_distance / zoom_step)
		_clamp_offset()
	elif event.is_action_pressed("camera_zoom_out"):
		_user_distance = minf(max_distance, _user_distance * zoom_step)
		_clamp_offset()
	elif event.is_action_pressed("camera_reset"):
		if target != null:
			_yaw_goal = target.global_rotation.y
		_pitch_offset = 0.0
		_user_distance = distance


func _clamp_offset() -> void:
	var base := _zoom_pitch(_user_distance)
	_pitch_offset = clampf(_pitch_offset, deg_to_rad(min_pitch_degrees) - base, deg_to_rad(max_pitch_degrees) - base)


func _process(delta: float) -> void:
	if target == null or camera == null or delta <= 0.0:
		return
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick.length() > 0.1:
		_idle = 0.0
		_yaw_goal -= stick.x * stick_speed * delta
		_pitch_offset += stick.y * stick_speed * 0.6 * delta
		_clamp_offset()
	else:
		_idle += delta

	# How the target is moving, smoothed so a stop doesn't jolt the view.
	# (Interpolated between physics steps, so it's smooth on any screen.)
	var pos := (target as Node3D).get_global_transform_interpolated().origin
	var vel := (pos - _last_target_pos) / delta
	_last_target_pos = pos
	vel.y = 0.0
	if vel.length() > 30.0:
		vel = Vector3.ZERO # teleported (spawn, getting out of a car)
	_target_vel = _target_vel.lerp(vel, 1.0 - exp(-6.0 * delta))
	var moving := _target_vel.length()

	# Heading: mouse and stick set the goal directly; when left alone while
	# moving, the goal eases round behind the way the target is going.
	if auto_follow_yaw and _idle > 0.3:
		_yaw_goal = lerp_angle(_yaw_goal, follow_yaw, 1.0 - exp(-follow_rate * delta))
	elif _idle > recenter_delay and moving > 0.6:
		var behind := atan2(-_target_vel.x, -_target_vel.z)
		var gap := angle_difference(_yaw_goal, behind)
		# Walking straight at the camera is left alone, so it doesn't spin round.
		if absf(gap) < 2.3:
			var strength := clampf(moving / 2.5, 0.35, 1.0) * clampf((_idle - recenter_delay) / 0.6, 0.0, 1.0)
			_yaw_goal += gap * (1.0 - exp(-delta / maxf(0.05, recenter_time) * 2.0 * strength))
	yaw = _damp_angle(yaw, _yaw_goal, mouse_smoothing, delta)

	# Run: pull back a little and widen the view.
	var run: Variant = target.get("run_amount")
	var run_t := float(run) if run != null else 0.0
	var want_distance := _user_distance + run_pull_back * run_t
	var d := _spring(_distance, _distance_vel, want_distance, 0.35, delta)
	_distance = d[0]
	_distance_vel = d[1]
	_pitch = lerpf(_pitch, _pitch_for(_distance), 1.0 - exp(-10.0 * delta))
	camera.fov = lerpf(camera.fov, fov + run_fov_boost * run_t, 1.0 - exp(-3.0 * delta))

	# Look a little ahead of where the target is going.
	var ahead_goal := _target_vel * look_ahead
	if ahead_goal.length() > max_look_ahead:
		ahead_goal = ahead_goal.normalized() * max_look_ahead
	var a := _spring3(_ahead, _ahead_vel, ahead_goal, 0.5, delta)
	_ahead = a[0]
	_ahead_vel = a[1]

	# Follow: tight sideways, softer up and down.
	var goal := pos + Vector3.UP * look_height + _ahead
	var fx := _spring3(Vector3(_focus.x, 0.0, _focus.z), Vector3(_focus_vel.x, 0.0, _focus_vel.z), Vector3(goal.x, 0.0, goal.z), follow_time, delta)
	var fy := _spring(_focus.y, _focus_vel.y, goal.y, follow_time_vertical, delta)
	var fp: Vector3 = fx[0]
	var fv: Vector3 = fx[1]
	_focus = Vector3(fp.x, fy[0], fp.z)
	_focus_vel = Vector3(fv.x, fy[1], fv.z)

	# Keep out of buildings: move in fast, ease back out slowly.
	var arm_goal := _distance
	# Looking steeply down over the rooftops, fading does the job better than
	# moving in, which would make the camera jump as you pass tall buildings.
	if avoid_buildings and _pitch < deg_to_rad(38.0):
		arm_goal = minf(_distance, _clear_distance(_distance))
	var arm_time := 0.04 if arm_goal < _arm else 0.45
	var ar := _spring(_arm, _arm_vel, arm_goal, arm_time, delta)
	_arm = ar[0]
	_arm_vel = ar[1]
	_place_camera()

	if fade_buildings:
		_fade_timer -= delta
		if _fade_timer <= 0.0:
			_fade_timer = 0.1
			_find_occluders()
			_find_prop_occluders()
		_update_fades(delta)
		_update_prop_fades(delta)


func _offset_dir() -> Vector3:
	return Vector3(sin(yaw) * cos(_pitch), sin(_pitch), cos(yaw) * cos(_pitch))


func _place_camera() -> void:
	var pos := _focus + _offset_dir() * _arm
	# Looking up: keep the camera above the street instead of under it.
	var floor_y := (target.global_position.y if target != null else 0.0) + 0.35
	pos.y = maxf(pos.y, floor_y)
	camera.global_position = pos
	# Aim above the orbit point when close in, so the target sits low in the
	# frame with the street ahead visible; far out, aim right at them.
	var closeness := 1.0 - clampf((_arm - min_distance) / (max_distance * 0.5 - min_distance), 0.0, 1.0)
	var aim := _focus + Vector3.UP * aim_above * closeness
	if pos.distance_to(aim) > 0.05:
		camera.look_at(aim, Vector3.UP)


## How far back the camera can sit before a building gets in the way.
## Only buildings count: lamp posts, signs and trees never shove the camera.
func _clear_distance(want: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := _focus
	var to := _focus + _offset_dir() * (want + 0.4)
	var exclude: Array[RID] = []
	for i in 4:
		_ray.from = from
		_ray.to = to
		_ray.exclude = exclude
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return want
		var col: Object = hit["collider"]
		if col != null and col.has_meta("fade_mesh"):
			return maxf(0.8, from.distance_to(hit["position"]) - 0.4)
		exclude.append(hit["rid"])
	return want


# --- critically damped springs ----------------------------------------------------------

## Returns [new value, new velocity]. smooth_time is roughly how long it takes to arrive.
static func _spring(cur: float, vel: float, goal: float, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(0.0001, smooth_time)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + omega * change) * delta
	var new_vel := (vel - omega * temp) * e
	return [goal + (change + temp) * e, new_vel]


static func _spring3(cur: Vector3, vel: Vector3, goal: Vector3, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(0.0001, smooth_time)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + change * omega) * delta
	var new_vel := (vel - temp * omega) * e
	return [goal + (change + temp) * e, new_vel]


func _damp_angle(cur: float, goal: float, smooth_time: float, delta: float) -> float:
	var target_angle := cur + angle_difference(cur, goal)
	var r := _spring(cur, _yaw_vel, target_angle, smooth_time, delta)
	_yaw_vel = r[1]
	return r[0]


# --- fading what's in the way ------------------------------------------------------------

## Ray from the camera to the target's chest and head; every building in the
## way (they carry a "fade_mesh" meta) gets faded.
func _find_occluders() -> void:
	_fade_now.clear()
	var space := get_world_3d().direct_space_state
	var base := target.global_position
	for h: float in [0.9, 1.7]:
		var exclude: Array[RID] = []
		for i in 6:
			_ray.from = camera.global_position
			_ray.to = base + Vector3.UP * h
			_ray.exclude = exclude
			var hit := space.intersect_ray(_ray)
			if hit.is_empty():
				break
			exclude.append(hit["rid"])
			var col: Object = hit["collider"]
			if col != null and col.has_meta("fade_mesh"):
				_fade_now[col.get_meta("fade_mesh")] = true
	for mi: Variant in _fade_now:
		if not _fade_level.has(mi):
			_fade_level[mi] = 0.0


func _update_fades(delta: float) -> void:
	for mi: Variant in _fade_level.keys():
		if not is_instance_valid(mi):
			_fade_level.erase(mi)
			_fade_mats.erase(mi)
			continue
		var goal := faded_amount if _fade_now.has(mi) else 0.0
		var v := move_toward(float(_fade_level[mi]), goal, delta * 3.0)
		# Buildings merged into a chunk mesh fade through their own handle
		# (BuildingFade); a building with a mesh of its own fades directly.
		if (mi as Object).has_method("set_camera_fade"):
			mi.set_camera_fade(v)
		else:
			_set_fade(mi as MeshInstance3D, v)
		if v <= 0.0 and goal <= 0.0:
			_fade_level.erase(mi)
		else:
			_fade_level[mi] = v


## Buildings share one material, so a fading building gets its own copies
## while it fades and goes back to the shared one after. Only the few
## buildings in the way ever have copies, which works on every renderer.
func _set_fade(mi: MeshInstance3D, v: float) -> void:
	if v <= 0.0:
		if _fade_mats.has(mi):
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, null)
			_fade_mats.erase(mi)
		return
	if not _fade_mats.has(mi):
		var mats: Array[ShaderMaterial] = []
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as ShaderMaterial
			if src == null:
				continue
			var copy := src.duplicate() as ShaderMaterial
			mi.set_surface_override_material(i, copy)
			mats.append(copy)
		_fade_mats[mi] = mats
	for m: ShaderMaterial in _fade_mats[mi]:
		m.set_shader_parameter("fade", v)


## Tree crowns (group "camera_fade_props", with a "radius" meta) that sit
## between the camera and the target, or around the camera itself.
func _find_prop_occluders() -> void:
	_prop_now.clear()
	var from := camera.global_position
	var to := target.global_position + Vector3.UP * 1.3
	for node in get_tree().get_nodes_in_group("camera_fade_props"):
		var g := node as GeometryInstance3D
		if g == null:
			continue
		var c := g.global_position
		var r := float(g.get_meta("radius", 2.0))
		var closest := Geometry3D.get_closest_point_to_segment(c, from, to)
		if c.distance_to(closest) < r * 0.95 or c.distance_to(from) < r + 0.8:
			_prop_now[g] = true
			if not _prop_fade.has(g):
				_prop_fade[g] = 0.0


func _update_prop_fades(delta: float) -> void:
	for g: Variant in _prop_fade.keys():
		if not is_instance_valid(g):
			_prop_fade.erase(g)
			continue
		var goal := faded_amount if _prop_now.has(g) else 0.0
		var v := move_toward(float(_prop_fade[g]), goal, delta * 3.0)
		(g as GeometryInstance3D).transparency = v
		if v <= 0.0 and goal <= 0.0:
			_prop_fade.erase(g)
		else:
			_prop_fade[g] = v

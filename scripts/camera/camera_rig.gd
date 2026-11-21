class_name CameraRig
extends Node3D
## Elevated three-quarter follow camera, between an isometric view and a
## classic over-the-shoulder chase camera.
##
## Orbit with the mouse or right stick, zoom with the wheel or D-pad. The
## camera smooths toward its target and looks a little ahead of where it's
## heading. Leave the camera alone for a moment while moving and it swings
## back in behind. Buildings and tree crowns that come between camera and
## target fade out of the way instead of blocking the view.
## `set_profile()` blends to different settings (used when driving).

@export var target: Node3D
@export var distance := 8.5 ## metres from the focus point
@export var min_distance := 5.0
@export var max_distance := 34.0
@export var pitch_degrees := 28.0 ## look-down angle; 90 would be straight down
@export var min_pitch_degrees := -12.0 ## below 0 looks up, e.g. at church spires
@export var max_pitch_degrees := 78.0
@export var look_height := 1.3 ## focus point above the target's origin
@export var follow_sharpness := 9.0 ## higher = tighter follow
@export var mouse_sensitivity := 0.0025
@export var stick_speed := 2.4 ## radians per second at full stick
@export var zoom_step := 1.12
@export var look_ahead := 0.45 ## seconds of the target's movement to look ahead
@export var max_look_ahead := 2.5 ## metres
@export var recenter_delay := 1.6 ## seconds without camera input before swinging back behind
@export var recenter_speed := 1.5 ## how quickly it swings back
@export var fov := 60.0
@export var run_fov_boost := 6.0 ## extra degrees of view at a full run
@export var fade_buildings := true
@export_range(0.0, 1.0) var faded_amount := 0.75

## Current orbit angle around the target (radians, 0 = camera south of target).
var yaw := 0.0
## When set, the camera drifts to sit behind this yaw (used while driving).
var auto_follow_yaw := false
var follow_yaw := 0.0

@onready var camera: Camera3D = $Camera

var _pitch := deg_to_rad(40.0)
var _distance := 13.0
var _target_distance := 13.0
var _target_pitch := deg_to_rad(40.0)
var _focus := Vector3.ZERO
var _fade_timer := 0.0
var _fade_now: Dictionary = {} ## MeshInstance3D -> true (occluding this check)
var _fade_level: Dictionary = {} ## MeshInstance3D -> current fade 0..1
var _fade_mats: Dictionary = {} ## MeshInstance3D -> its temporary faded materials
var _ray := PhysicsRayQueryParameters3D.new()
var _idle := 0.0 ## seconds since the last camera input
var _last_target_pos := Vector3.ZERO
var _target_vel := Vector3.ZERO
var _ahead := Vector3.ZERO
var _prop_fade: Dictionary = {} ## GeometryInstance3D (tree crowns) -> current fade
var _prop_now: Dictionary = {}


func _ready() -> void:
	top_level = true
	_distance = distance
	_target_distance = distance
	_pitch = deg_to_rad(pitch_degrees)
	_target_pitch = _pitch
	_ray.collision_mask = Layers.SOLID
	if camera != null:
		camera.fov = fov


## Jump straight to the target with the camera behind it (no smoothing).
func snap_to_target() -> void:
	if target == null:
		return
	yaw = target.global_rotation.y
	_focus = target.global_position + Vector3.UP * look_height
	_last_target_pos = target.global_position
	_target_vel = Vector3.ZERO
	_ahead = Vector3.ZERO
	_place_camera()


## Blend to a new distance and pitch, e.g. pulled back and lower when driving.
func set_profile(new_distance: float, new_pitch_degrees: float) -> void:
	_target_distance = clampf(new_distance, min_distance, max_distance)
	_target_pitch = deg_to_rad(clampf(new_pitch_degrees, min_pitch_degrees, max_pitch_degrees))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_idle = 0.0
		yaw -= m.relative.x * mouse_sensitivity
		_target_pitch = clampf(_target_pitch + m.relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	elif event.is_action_pressed("camera_zoom_in"):
		_target_distance = maxf(min_distance, _target_distance / zoom_step)
	elif event.is_action_pressed("camera_zoom_out"):
		_target_distance = minf(max_distance, _target_distance * zoom_step)
	elif event.is_action_pressed("camera_reset"):
		if target != null:
			yaw = target.global_rotation.y
		_target_pitch = deg_to_rad(pitch_degrees)
		_target_distance = distance


func _process(delta: float) -> void:
	if target == null or camera == null:
		return
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	yaw -= stick.x * stick_speed * delta
	_target_pitch = clampf(_target_pitch + stick.y * stick_speed * 0.6 * delta,
		deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_idle = 0.0 if stick.length() > 0.1 else _idle + delta

	# How the target is moving, smoothed so a stop doesn't jolt the view.
	var pos := target.global_position
	var vel := (pos - _last_target_pos) / maxf(delta, 0.0001)
	_last_target_pos = pos
	vel.y = 0.0
	if vel.length() > 30.0:
		vel = Vector3.ZERO # teleported (spawn, getting out of a car)
	_target_vel = _target_vel.lerp(vel, 1.0 - exp(-5.0 * delta))
	var moving := _target_vel.length()

	if auto_follow_yaw and stick.length() < 0.1:
		yaw = lerp_angle(yaw, follow_yaw, 1.0 - exp(-2.5 * delta))
	elif _idle > recenter_delay and moving > 0.6:
		# Swing in behind the way the target is heading, faster the faster it
		# goes. Walking straight at the camera is left alone, so it doesn't
		# spin round on you.
		var behind := atan2(-_target_vel.x, -_target_vel.z)
		if absf(angle_difference(yaw, behind)) < 2.3:
			var rate := recenter_speed * clampf(moving / 3.0, 0.3, 1.5)
			yaw = lerp_angle(yaw, behind, 1.0 - exp(-rate * delta))

	# Look a little ahead of where the target is going.
	var ahead_goal := _target_vel * look_ahead
	if ahead_goal.length() > max_look_ahead:
		ahead_goal = ahead_goal.normalized() * max_look_ahead
	_ahead = _ahead.lerp(ahead_goal, 1.0 - exp(-2.0 * delta))

	var goal := pos + Vector3.UP * look_height + _ahead
	var k := 1.0 - exp(-follow_sharpness * delta)
	var ky := 1.0 - exp(-follow_sharpness * 0.5 * delta) # steadier up and down (curbs)
	_focus = Vector3(lerpf(_focus.x, goal.x, k), lerpf(_focus.y, goal.y, ky), lerpf(_focus.z, goal.z, k))
	var blend := 1.0 - exp(-4.0 * delta)
	_distance = lerpf(_distance, _target_distance, blend)
	_pitch = lerpf(_pitch, _target_pitch, blend)
	var run: Variant = target.get("run_amount")
	var run_t := float(run) if run != null else 0.0
	camera.fov = lerpf(camera.fov, fov + run_fov_boost * run_t, 1.0 - exp(-3.0 * delta))
	_place_camera()

	if fade_buildings:
		_fade_timer -= delta
		if _fade_timer <= 0.0:
			_fade_timer = 0.1
			_find_occluders()
			_find_prop_occluders()
		_update_fades(delta)
		_update_prop_fades(delta)


func _place_camera() -> void:
	var offset := Vector3(sin(yaw) * cos(_pitch), sin(_pitch), cos(yaw) * cos(_pitch)) * _distance
	var pos := _focus + offset
	# Looking up: keep the camera above the street instead of under it.
	var floor_y := target.global_position.y + 0.35 if target != null else 0.35
	pos.y = maxf(pos.y, floor_y)
	camera.global_position = pos
	camera.look_at(_focus, Vector3.UP)


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

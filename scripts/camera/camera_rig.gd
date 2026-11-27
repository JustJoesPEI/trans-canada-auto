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
## In a car, `set_cockpit()` swaps the chase view for the driver's seat:
## eyes where the driver's head is, looking out over the hood, with the
## mouse or right stick to look round (it eases back to the road ahead).
##
## The right stick goes through StickFeel (deadzones, response curve, turn
## boost, the player's look and aim sensitivity); the mouse doesn't. While
## the target aims with a controller, AimAssist slows the stick over a
## target, follows part of its motion, and eases onto an officer when the
## aim comes up (see AimAssist). F6 puts down a test target (AimDummy).

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
@export var follow_time := 0.07 ## seconds to catch up sideways (lower = tighter)
@export var follow_time_vertical := 0.28 ## steadier up and down (curbs)
@export var look_ahead := 0.25 ## seconds of the target's movement to look ahead
@export var max_look_ahead := 1.4 ## metres
@export var mouse_sensitivity := 0.0024
@export var mouse_smoothing := 0.012 ## seconds; a touch of smoothing on mouse turns
@export var stick_speed := 2.6 ## radians per second at full stick (times the look sensitivity setting)
@export var zoom_step := 1.15
@export var recenter_delay := 2.5 ## seconds without camera input before easing back behind
@export var recenter_time := 0.7 ## seconds it takes to come round

@export_group("Aiming")
## Over the shoulder while the target aims (its aim_amount, 0..1).
@export var aim_distance := 3.0
@export var aim_shoulder := 0.55 ## metres the view sits to the right, so the crosshair clears the head
@export var aim_fov := 50.0
@export var aim_sensitivity := 0.75 ## mouse and stick turn this much slower, for fine aim (the stick also times the aim sensitivity setting)
@export var aim_min_pitch_degrees := -55.0 ## aiming can look much further up (rooftops, balconies)
@export var aim_level_pitch_degrees := 3.0
## A scoped weapon (its scope_fov), once fully aimed, looks down the scope:
## the view narrows to the scope's and comes in close behind the shoulder,
## so the body is out of the round view. Turning slows with the zoom.
@export var scope_distance := 1.2
## Leaning out of a passenger window (the target's `passenger`): closer in
## and lifted, so the view is from just behind the shoulder, over the roof,
## not from across the car looking through it.
@export var passenger_aim_distance := 1.5
@export var passenger_aim_lift := 0.75
@export var scope_in_time := 0.15 ## s to go in or out of the scope ## raising the aim brings the view to about level, so the crosshair starts on the street ahead, not the road at your feet

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
@export var drive_distance := 7.0
@export var drive_pitch_degrees := 11.0 ## low enough that the ground is seen at a slant, where a grade shows
## How far the view leans into a grade (0 = keeps its tilt, 1 = tips the whole
## grade): up a climb it tips up to show the hill rising ahead, over a crest
## it tips down to show the drop beyond. Partial, so the road still reads as
## sloping against the horizon.
@export var drive_grade_lean := 0.55
@export var drive_grade_time := 0.6 ## seconds to settle into a new grade (a crest shows as a pitch-over)
@export var drive_look_height := 1.05
@export var drive_look_ahead := 0.2
@export var drive_follow_time := 0.11 ## softer than on foot, so the car glides in frame
@export var drive_max_look_ahead := 3.0
@export var drive_pull_back := 0.3 ## extra metres at speed (small: pulling back makes speed feel slower)
@export var drive_aim_above := 0.15
@export var drive_fov := 60.0 ## a touch wider than on foot; much wider stretches the road ahead and makes it look longer
@export var drive_fov_boost := 6.0 ## extra degrees at highway speed
@export var drive_shake := 0.03 ## metres of shake at full speed

@export_group("Driver's seat")
@export var cockpit_fov := 62.0
@export var cockpit_fov_boost := 4.0
@export var cockpit_eye := Vector3(0.0, 0.76, 0.0) ## the eyes, from the car's seat point (the hips)
@export var cockpit_look_back := 0.8 ## seconds after looking round before the view eases back ahead

## A knock felt through the car (a crash, a hard landing), 0..1, dying away.
var _jolt := 0.0
var _jolt_seed := 0.0
var _kick := Vector2.ZERO ## radians the view is kicked up (x) and sideways (y), springing back

## True while looking out from the driver's seat.
var cockpit := false
var _look := Vector2.ZERO ## turn and tilt of the head in the driver's seat (radians)
var _look_idle := 0.0
var _cockpit_rot := Quaternion.IDENTITY

var _on_foot := {}

@onready var camera: Camera3D = $Camera

var _user_distance := 6.5 ## where the player has zoomed to
var _home_distance := 6.5 ## the mode's own distance, which the View steps are of
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
var _grade := 0.0 ## the grade the target is moving along (rise over run), smoothed
var _fade_timer := 0.0
var _fade_now: Dictionary = {} ## MeshInstance3D -> true (occluding this check)
var _fade_level: Dictionary = {} ## MeshInstance3D -> current fade 0..1
var _fade_mats: Dictionary = {} ## MeshInstance3D -> its temporary faded materials
var _prop_fade: Dictionary = {} ## tree crowns (GeometryInstance3D or CrownFade) -> current fade
var _prop_now: Dictionary = {}
var _ray := PhysicsRayQueryParameters3D.new()
var _aim_ray := PhysicsRayQueryParameters3D.new()
var _aim_t := 0.0 ## the target's aim_amount this frame
## 0..1, how far down a scope the view is (the HUD draws the scope with it).
var scope_amount := 0.0
var _scope_fov := 15.0 ## the scope's view, kept while easing out
var _pre_aim_offset := NAN ## the tilt before aiming, put back after
var _feel := StickFeel.new()
var _assist := AimAssist.new()
var _aim_held := false ## Aim held last frame (for the aim-in snap)


func _ready() -> void:
	top_level = true
	# The camera moves every rendered frame already; it follows the target's
	# interpolated position instead of being interpolated itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_user_distance = distance
	_home_distance = distance
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
			_on_foot = {"fov": fov, "run_fov_boost": run_fov_boost, "look_height": look_height, "look_ahead": look_ahead, "max_look_ahead": max_look_ahead,
				"run_pull_back": run_pull_back, "aim_above": aim_above, "follow_time": follow_time, "user_distance": _user_distance, "home_distance": _home_distance, "pitch_offset": _pitch_offset}
		fov = drive_fov
		run_fov_boost = drive_fov_boost
		look_height = drive_look_height
		look_ahead = drive_look_ahead
		max_look_ahead = drive_max_look_ahead
		run_pull_back = drive_pull_back
		aim_above = drive_aim_above
		follow_time = drive_follow_time
		set_profile(drive_distance, drive_pitch_degrees)
		auto_follow_yaw = true
	else:
		cockpit = false
		_look = Vector2.ZERO
		if not _on_foot.is_empty():
			fov = _on_foot["fov"]
			run_fov_boost = _on_foot["run_fov_boost"]
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			look_height = _on_foot["look_height"]
			look_ahead = _on_foot["look_ahead"]
			max_look_ahead = _on_foot["max_look_ahead"]
			run_pull_back = _on_foot["run_pull_back"]
			aim_above = _on_foot["aim_above"]
			follow_time = _on_foot["follow_time"]
			_user_distance = _on_foot["user_distance"]
			_home_distance = _on_foot["home_distance"]
			_pitch_offset = _on_foot["pitch_offset"]
			_on_foot = {}
		auto_follow_yaw = false
	# Pick up the new target smoothly rather than jumping.
	if target != null:
		_last_target_pos = target.global_position


## Look out from the driver's seat (on) or go back to the chase view (off).
## Only works with a car as the target.
func set_cockpit(on: bool) -> void:
	on = on and target != null and target.get("seat") != null
	if on == cockpit:
		return
	cockpit = on
	_look = Vector2.ZERO
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	if on:
		_cockpit_rot = (target as Node3D).global_basis.get_rotation_quaternion()
		camera.fov = cockpit_fov
	else:
		# Pick the chase view up behind the car, without swinging in from wherever it was.
		yaw = follow_yaw if auto_follow_yaw else target.global_rotation.y
		_yaw_goal = yaw
		_yaw_vel = 0.0
		_focus = target.global_position + Vector3.UP * look_height
		_focus_vel = Vector3.ZERO
		_ahead = Vector3.ZERO
		_ahead_vel = Vector3.ZERO
		_distance = _user_distance
		_arm = _user_distance
		_pitch = _pitch_for(_distance)
		camera.fov = fov
		_place_camera()


## Shake the view for a knock: 0.1 a curb, 1 a big crash. Stronger knocks
## override weaker ones still dying away.
func jolt(amount: float) -> void:
	_jolt = maxf(_jolt, clampf(amount, 0.0, 1.0))
	_jolt_seed = randf() * 100.0


## A shot's kick (the weapon's "kick", degrees): the view jumps up and a
## touch to one side and springs back in about a tenth of a second, before
## the next pull, so it gives a shot its weight without walking the aim
## off (no pulling down against it, on a stick or a mouse).
func kick(degrees: float) -> void:
	if degrees <= 0.0:
		return
	var r := deg_to_rad(degrees)
	_kick += Vector2(r, randf_range(-0.3, 0.3) * r)
	_kick.x = minf(_kick.x, deg_to_rad(6.0))


## The view pulled in a few degrees for a moment (putting someone out):
## it eases back out on its own.
func punch(degrees: float) -> void:
	camera.fov = maxf(10.0, camera.fov - degrees)


## The jolt's offset this frame (metres, sideways and up), dying away fast.
func _jolt_offset(delta: float, scale: float) -> Vector2:
	if _jolt <= 0.001:
		_jolt = 0.0
		return Vector2.ZERO
	var t := Time.get_ticks_msec() * 0.001 + _jolt_seed
	var amt := _jolt * _jolt * scale
	var o := Vector2(sin(t * 53.0) * 0.7 + sin(t * 31.0 + 1.1) * 0.3, sin(t * 61.0 + 0.4) * 0.6 + sin(t * 37.0) * 0.4) * amt
	_jolt *= exp(-delta * 7.0)
	return o


## Set distance and look-down angle together, e.g. pulled back and lower when driving.
func set_profile(new_distance: float, new_pitch_degrees: float) -> void:
	_user_distance = clampf(new_distance, min_distance, max_distance)
	_home_distance = _user_distance
	_pitch_offset = deg_to_rad(new_pitch_degrees) - _zoom_pitch(_user_distance)


## The controller's View button steps the camera between set distances, as
## in most open-world games: the mode's own (on foot or the vehicle's),
## then further back, then (on foot) closer in. VIEW_STEPS are of the
## mode's distance.
const VIEW_STEPS: Array[float] = [1.0, 1.6, 0.65]


## Which of VIEW_STEPS the camera is nearest now.
func view_step() -> int:
	var ratio := _user_distance / maxf(_home_distance, 0.01)
	var best := 0
	for i in VIEW_STEPS.size():
		if absf(VIEW_STEPS[i] - ratio) < absf(VIEW_STEPS[best] - ratio):
			best = i
	return best


func set_view_step(i: int) -> void:
	_user_distance = clampf(_home_distance * VIEW_STEPS[posmod(i, VIEW_STEPS.size())], min_distance, max_distance)
	_clamp_offset()


## How the target is moving over the ground (smoothed, from where it is
## drawn each frame, so it changes smoothly between physics steps).
func target_velocity() -> Vector3:
	return _target_vel


## Look-down angle the zoom curve gives for a distance.
func _zoom_pitch(d: float) -> float:
	var t := clampf((d - min_distance) / (max_distance - min_distance), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t) # ease at both ends
	return deg_to_rad(lerpf(close_pitch_degrees, far_pitch_degrees, sqrt(t)))


func _pitch_for(d: float) -> float:
	return clampf(_zoom_pitch(d) + _pitch_offset, _min_pitch(), deg_to_rad(max_pitch_degrees))


func _input(event: InputEvent) -> void:
	InputDevice.note(event)


func _unhandled_input(event: InputEvent) -> void:
	if AimDummy.debug_key(event, self):
		get_viewport().set_input_as_handled()
		return
	if cockpit:
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var mm := event as InputEventMouseMotion
			_look_idle = 0.0
			var ms := mouse_sensitivity * AimSettings.mouse_sensitivity
			_look.x = clampf(_look.x - mm.relative.x * ms, -1.9, 1.9)
			_look.y = clampf(_look.y - mm.relative.y * ms * AimSettings.y_sign(), -0.5, 0.35)
		elif event.is_action_pressed("camera_reset"):
			_look = Vector2.ZERO
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_idle = 0.0
		var sens := mouse_sensitivity * AimSettings.mouse_sensitivity * lerpf(1.0, aim_sensitivity, _aim_t) * _scope_slow()
		_yaw_goal -= m.relative.x * sens
		_pitch_offset += m.relative.y * sens * AimSettings.y_sign()
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
	_pitch_offset = clampf(_pitch_offset, _min_pitch() - base, deg_to_rad(max_pitch_degrees) - base)


func _min_pitch() -> float:
	return deg_to_rad(lerpf(min_pitch_degrees, aim_min_pitch_degrees, _aim_t))


func _process(delta: float) -> void:
	if target == null or camera == null or delta <= 0.0:
		return
	# Raw stick (no deadzone: deadzone 0 here), shaped by StickFeel.
	var stick := StickFeel.shape_with_settings(Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.0))
	stick.y *= AimSettings.y_sign() # inverted looking (the Controls menu)
	if cockpit:
		_process_cockpit(stick, delta)
		return
	_stick_look(stick, delta)
	var aim_v: Variant = target.get("aim_amount")
	var was_aiming := _aim_t > 0.0
	_aim_t = float(aim_v) if aim_v != null else 0.0
	if _aim_t > 0.0 and not was_aiming:
		_pre_aim_offset = _pitch_offset
		_pitch_offset = deg_to_rad(aim_level_pitch_degrees) - _zoom_pitch(_user_distance)
	elif _aim_t <= 0.0 and was_aiming and not is_nan(_pre_aim_offset):
		_pitch_offset = _pre_aim_offset
		_pre_aim_offset = NAN
	var scope_fov := _target_scope_fov()
	if scope_fov > 0.0:
		_scope_fov = scope_fov
	scope_amount = move_toward(scope_amount, 1.0 if scope_fov > 0.0 and _aim_t >= 0.99 else 0.0, delta / scope_in_time)
	if _aim_t > 0.0:
		_idle = 0.0 # aiming: never swing round behind on its own
		_clamp_offset()
	_aim_help(stick, delta)
	_kick *= exp(-delta * 16.0)

	# How the target is moving, smoothed so a stop doesn't jolt the view.
	# (Interpolated between physics steps, so it's smooth on any screen.)
	var pos := (target as Node3D).get_global_transform_interpolated().origin
	var moved := pos - _last_target_pos
	var vel := moved / delta
	_last_target_pos = pos
	var rise := vel.y
	vel.y = 0.0
	# Teleported (spawn, a tow, getting out of a car): a jump no car makes in
	# a frame, even a slow one. (It used to be any speed over 30 m/s, which
	# a car passes at 108 km/h: on the highway the camera lost the car's
	# speed every frame, its look-ahead and swing round behind collapsing
	# and coming back, a chug in the chase view.)
	if moved.length() > 25.0 or vel.length() > 120.0:
		vel = Vector3.ZERO
		rise = 0.0
	# Driving, the grade underfoot (held while crawling, where it can't be read).
	if auto_follow_yaw and vel.length() > 2.0:
		var g := clampf(rise / vel.length(), -0.3, 0.3)
		_grade = lerpf(_grade, g, 1.0 - exp(-delta / drive_grade_time))
	elif not auto_follow_yaw:
		_grade = 0.0
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
	var riding := _target_riding()
	var aim_d := passenger_aim_distance if riding else aim_distance
	var want_distance := lerpf(lerpf(_user_distance + run_pull_back * run_t, aim_d, _aim_t), scope_distance, scope_amount)
	var d := _spring(_distance, _distance_vel, want_distance, lerpf(0.35, 0.1, _aim_t), delta)
	_distance = d[0]
	_distance_vel = d[1]
	# Aiming, the tilt follows the mouse alone, not the zoom curve, so
	# raising the aim doesn't tip the view.
	var pitch_goal := _pitch_for(lerpf(_distance, _user_distance, _aim_t))
	# Driving: lean into the grade (look up a climb, down over a crest).
	pitch_goal -= atan(_grade) * drive_grade_lean * (1.0 - _aim_t)
	_pitch = lerpf(_pitch, pitch_goal, 1.0 - exp(-lerpf(10.0, 40.0, _aim_t) * delta))
	var fov_goal := lerpf(fov + run_fov_boost * run_t * run_t, aim_fov, _aim_t)
	camera.fov = lerpf(camera.fov, fov_goal, 1.0 - exp(-lerpf(3.0, 14.0, _aim_t) * delta))
	if scope_amount > 0.0:
		# Down the scope the view is set straight from the ease, no lag.
		camera.fov = lerpf(camera.fov, _scope_fov, smoothstep(0.0, 1.0, scope_amount))
	if not auto_follow_yaw:
		camera.h_offset = aim_shoulder * smoothstep(0.0, 1.0, _aim_t)
		camera.v_offset = passenger_aim_lift * smoothstep(0.0, 1.0, _aim_t) if riding else 0.0
	# Driving fast: a fine shake, as the road comes up through the car.
	if auto_follow_yaw and drive_shake > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		var amt := drive_shake * run_t * run_t
		var j := _jolt_offset(delta, 0.22)
		camera.h_offset = (sin(t * 37.0) * 0.6 + sin(t * 23.0 + 1.3) * 0.4) * amt + j.x
		camera.v_offset = (sin(t * 41.0 + 0.7) * 0.6 + sin(t * 29.0) * 0.4) * amt + j.y
	elif not auto_follow_yaw and _jolt > 0.0:
		# On foot: a hit knocks the view a little (smaller than a crash).
		var j := _jolt_offset(delta, 0.07)
		camera.h_offset += j.x
		camera.v_offset += j.y

	# Look a little ahead of where the target is going.
	var ahead_goal := _target_vel * look_ahead * (1.0 - _aim_t)
	if ahead_goal.length() > max_look_ahead:
		ahead_goal = ahead_goal.normalized() * max_look_ahead
	var a := _spring3(_ahead, _ahead_vel, ahead_goal, 0.5, delta)
	_ahead = a[0]
	_ahead_vel = a[1]

	# Follow: tight sideways, softer up and down.
	var goal := pos + Vector3.UP * look_height + _ahead
	var fx := _spring3(Vector3(_focus.x, 0.0, _focus.z), Vector3(_focus_vel.x, 0.0, _focus_vel.z), Vector3(goal.x, 0.0, goal.z), follow_time * lerpf(1.0, 0.5, _aim_t), delta)
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


## The right stick (already shaped by StickFeel) turns the view: the look or
## aim sensitivity setting, turn boost on yaw, and the aim assist's slowdown
## (worked out last frame, so it's in place before the stick moves).
## The scope's view of the weapon the target holds (0: none, or not a
## person with a marker).
func _target_scope_fov() -> float:
	var m: Variant = target.get("marker") if target != null else null
	if m is PaintMarker:
		return float((m as PaintMarker).weapon.get("scope_fov", 0.0))
	return 0.0


## The target is a person riding in a passenger seat (leaning out to aim).
func _target_riding() -> bool:
	var p: Variant = target.get("passenger") if target != null else null
	return p is bool and bool(p) and target.get("vehicle") != null


## Down a scope, turning slows by the zoom, so the view moves the same
## across the screen.
func _scope_slow() -> float:
	return lerpf(1.0, _scope_fov / aim_fov, scope_amount)


func _stick_look(stick: Vector2, delta: float) -> void:
	var boost := _feel.update_boost(stick, delta)
	if stick.length() <= 0.0:
		_idle += delta
		return
	_idle = 0.0
	var sens := lerpf(AimSettings.look_sensitivity, AimSettings.aim_sensitivity * aim_sensitivity, _aim_t) * _assist.slow * _scope_slow()
	_yaw_goal -= stick.x * stick_speed * delta * sens * boost
	_pitch_offset += stick.y * stick_speed * 0.6 * delta * sens
	_clamp_offset()


## Aim assist, with a controller while the target holds Aim: the slowdown
## for next frame's stick, tracking, and the aim-in snap onto an officer.
func _aim_help(stick: Vector2, delta: float) -> void:
	var held_v: Variant = target.get("aiming")
	var held := bool(held_v) if held_v != null else _aim_t > 0.5
	var power := AimAssist.strength(held and not auto_follow_yaw)
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var pitch_goal := _zoom_pitch(_user_distance) + _pitch_offset
	if held and not _aim_held:
		# The crosshair as it will be once the view has come up to aim.
		var dir := -Vector3(sin(_yaw_goal) * cos(pitch_goal), sin(pitch_goal), cos(_yaw_goal) * cos(pitch_goal))
		_assist.begin_snap(self, _focus, dir, exclude, power, aim_shoulder)
	_aim_held = held
	if power <= 0.0:
		_assist.reset()
		return
	_assist.update(self, camera.get_camera_transform(), _focus, exclude, power, delta, _feel.boost > 1.01)
	var turn := _assist.track
	# Never fight the stick: pushing against the tracking turns it off.
	if absf(stick.x) > 0.25 and signf(-stick.x) != signf(turn.x):
		turn.x = 0.0
	if absf(stick.y) > 0.25 and signf(stick.y) != signf(turn.y):
		turn.y = 0.0
	if _assist.snapping:
		if stick.length() > 0.35:
			_assist.cancel_snap() # taking over
		else:
			turn += _assist.snap_step(_focus, _yaw_goal, pitch_goal, delta)
	if turn != Vector2.ZERO:
		_yaw_goal += turn.x
		_pitch_offset += turn.y
		_clamp_offset()


## The driver's-seat view: placed at the driver's eyes every frame, turning
## with the car (a touch smoothed, so the road doesn't jitter), plus where
## the player is looking.
func _process_cockpit(stick: Vector2, delta: float) -> void:
	var car := target as Node3D
	var seat := car.get("seat") as Node3D
	if seat == null:
		return
	if stick.length() > 0.0:
		_look_idle = 0.0
		var sens := AimSettings.look_sensitivity
		_look.x = clampf(_look.x - stick.x * stick_speed * sens * delta, -1.9, 1.9)
		_look.y = clampf(_look.y - stick.y * stick_speed * 0.6 * sens * delta, -0.5, 0.35)
	else:
		_look_idle += delta
		if _look_idle > cockpit_look_back:
			_look = _look.lerp(Vector2.ZERO, 1.0 - exp(-4.0 * delta))
	var xf := car.get_global_transform_interpolated()
	var body := seat.get_parent() as Node3D
	var eye := xf * (body.transform * (seat.position + cockpit_eye))
	_cockpit_rot = _cockpit_rot.slerp(xf.basis.get_rotation_quaternion(), 1.0 - exp(-30.0 * delta))
	var b := Basis(_cockpit_rot) * Basis(Vector3.UP, _look.x) * Basis(Vector3.RIGHT, _look.y)
	camera.global_transform = Transform3D(b, eye)
	var run: Variant = target.get("run_amount")
	var run_t := float(run) if run != null else 0.0
	camera.fov = lerpf(camera.fov, cockpit_fov + cockpit_fov_boost * run_t * run_t, 1.0 - exp(-3.0 * delta))
	if drive_shake > 0.0:
		var t := Time.get_ticks_msec() * 0.001
		var amt := drive_shake * 0.4 * run_t * run_t
		# A knock jars your head more than it moves a camera outside.
		var j := _jolt_offset(delta, 0.07)
		camera.h_offset = (sin(t * 37.0) * 0.6 + sin(t * 23.0 + 1.3) * 0.4) * amt + j.x
		camera.v_offset = (sin(t * 41.0 + 0.7) * 0.6 + sin(t * 29.0) * 0.4) * amt + j.y
	# Nothing needs fading from in here; let anything faded come back.
	if not _fade_level.is_empty() or not _prop_fade.is_empty():
		_fade_now.clear()
		_prop_now.clear()
		_update_fades(delta)
		_update_prop_fades(delta)


## An up for looking along `dir`: straight up, unless the view is straight
## up or down (looking down on the target from right above it, the first
## frame before the arm swings out), where "up" is the way the camera faces
## round the target instead (looking_at can't use an up along the view).
func _up_for(dir: Vector3) -> Vector3:
	if dir.length_squared() > 0.0001 and absf(dir.normalized().y) > 0.999:
		return Vector3(-sin(yaw), 0.0, -cos(yaw))
	return Vector3.UP


func _offset_dir() -> Vector3:
	return Vector3(sin(yaw) * cos(_pitch), sin(_pitch), cos(yaw) * cos(_pitch))


func _place_camera() -> void:
	var pos := _focus + _offset_dir() * _arm
	# Looking up: keep the camera above the street instead of under it.
	# Aiming up, stay about waist high rather than down on the pavement,
	# where the player would loom over the whole view.
	var floor_y := _last_target_pos.y + lerpf(0.35, 1.0, _aim_t) # where the target is drawn this frame
	pos.y = maxf(pos.y, floor_y)
	camera.global_position = pos
	# Aim above the orbit point when close in, so the target sits low in the
	# frame with the street ahead visible; far out, aim right at them.
	var closeness := 1.0 - clampf((_arm - min_distance) / (max_distance * 0.5 - min_distance), 0.0, 1.0)
	# Pulled right in by a wall behind, aim lower too: 0.9 m above the
	# shoulders from under a metre back would point the view at the sky.
	var aim := _focus + Vector3.UP * aim_above * closeness * minf(1.0, _arm / 2.5) * (1.0 - _aim_t)
	if pos.distance_to(aim) > 0.05:
		camera.look_at(aim, _up_for(aim - pos))
	if _aim_t > 0.0:
		# Aiming, point exactly along the tilt, even where the camera has had
		# to rise off the floor, so the crosshair goes where the mouse puts it.
		var along := Basis.looking_at(-_offset_dir(), _up_for(-_offset_dir()))
		camera.global_basis = camera.global_basis.slerp(along, _aim_t)
	if _kick.length_squared() > 1e-8:
		camera.rotate_object_local(Vector3.RIGHT, _kick.x)
		camera.rotate_object_local(Vector3.UP, _kick.y)


## What's under the crosshair (the middle of the screen): the first thing
## hit past `shooter` (ground, buildings, cars, people, loads), or a point
## far off along the view when there's nothing. `also`: more to see past
## (the car a passenger leans out of).
func aim_point(shooter: CollisionObject3D, reach := 150.0, also: Array[RID] = []) -> Vector3:
	var view := camera.get_camera_transform() # includes the shoulder offset
	var dir := -view.basis.z
	# Start level with the shooter, so nothing between them and the camera counts.
	var start := view.origin + dir * maxf(0.0, (shooter.global_position - view.origin).dot(dir))
	_aim_ray.from = start
	_aim_ray.to = view.origin + dir * reach
	_aim_ray.collision_mask = Layers.GROUND | Layers.SOLID | Layers.VEHICLES | Layers.CHARACTERS | Layers.CARGO
	_aim_ray.exclude = [shooter.get_rid()] + also
	var hit := get_world_3d().direct_space_state.intersect_ray(_aim_ray)
	return _aim_ray.to if hit.is_empty() else hit["position"]


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
			if col != null and col.has_meta("fade_mesh") and not _inside(col, base):
				_fade_now[col.get_meta("fade_mesh")] = true
	for mi: Variant in _fade_now:
		if not _fade_level.has(mi):
			_fade_level[mi] = 0.0


## True if `p` is inside a building the camera follows people round in
## (a parkade's decks, meta "inside"), so it's never faded from there.
static func _inside(col: Object, p: Vector3) -> bool:
	if not col.has_meta("inside"):
		return false
	var box: Dictionary = col.get_meta("inside")
	var d := Vector2(p.x, p.z) - (box["c"] as Vector2)
	return absf(d.dot(box["u"])) < float(box["hu"]) and absf(d.dot(box["v"])) < float(box["hv"]) \
		and p.y > float(box["y0"]) and p.y < float(box["y1"])


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
			var copy := BuildingFade.faded_copy(src)
			mi.set_surface_override_material(i, copy)
			mats.append(copy)
		_fade_mats[mi] = mats
	for m: ShaderMaterial in _fade_mats[mi]:
		m.set_shader_parameter("fade", v)


var _crown_grid := {} ## Vector2i -> crowns in that CROWN_CELL square
var _crown_count := Vector3i(-1, -1, -1)
const CROWN_CELL := 32.0
## The biggest crown's reach (m), on top of the camera-to-target line.
const CROWN_REACH := 16.0


## Tree crowns (group "camera_fade_props", with a "radius" meta) that sit
## between the camera and the target, or around the camera itself.
func _find_prop_occluders() -> void:
	_prop_now.clear()
	var from := camera.global_position
	var to := target.global_position + Vector3.UP * 1.3
	# The crowns by grid square (they don't move), made again only when the
	# town's crowns change (a chunk in or out): just the squares round the
	# view are looked at, not every crown in town.
	var count := Vector3i(get_tree().get_node_count_in_group("camera_fade_props"), ChunkStreamer.added_near, ChunkStreamer.dropped)
	if count != _crown_count:
		_crown_count = count
		_crown_grid.clear()
		for node in get_tree().get_nodes_in_group("camera_fade_props"):
			var gi := node as Node3D
			if gi == null:
				continue
			var k := Vector2i(floori(gi.global_position.x / CROWN_CELL), floori(gi.global_position.z / CROWN_CELL))
			if not _crown_grid.has(k):
				_crown_grid[k] = []
			(_crown_grid[k] as Array).append(gi)
	var lo := Vector2i(floori((minf(from.x, to.x) - CROWN_REACH) / CROWN_CELL), floori((minf(from.z, to.z) - CROWN_REACH) / CROWN_CELL))
	var hi := Vector2i(floori((maxf(from.x, to.x) + CROWN_REACH) / CROWN_CELL), floori((maxf(from.z, to.z) + CROWN_REACH) / CROWN_CELL))
	var near: Array = []
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var cell: Variant = _crown_grid.get(Vector2i(x, z))
			if cell != null:
				near.append_array(cell)
	for node: Variant in near:
		if not is_instance_valid(node):
			continue
		var g := node as Node3D
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
		# A crown drawn through a MultiMesh fades through its handle (CrownFade).
		if (g as Object).has_method("set_camera_fade"):
			g.set_camera_fade(v)
		else:
			(g as GeometryInstance3D).transparency = v
		if v <= 0.0 and goal <= 0.0:
			_prop_fade.erase(g)
		else:
			_prop_fade[g] = v

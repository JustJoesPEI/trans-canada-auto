extends SceneTree
## Checks the controller aiming and the aim assist without a controller:
## synthetic stick input into StickFeel, AimAssist against test targets in
## a small physics world, and the real camera rig and player driven by fake
## joypad and mouse events.
##
##   godot --headless --path . --script res://tools/aim_check.gd
##
## Prints one line per check and exits non-zero if any fail. It never
## touches the saved settings (user://controls.cfg).

const DT := 1.0 / 60.0
const FOCUS := Vector3(0.0, 1.45, 0.0)

var _fails := 0
var _host: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AimSettings.reset_defaults()
	_host = Node3D.new()
	root.add_child(_host)
	_stick()
	_boost()
	_device()
	await _assist()
	await _snap()
	await _rig()
	print("AIM %s: %d failed" % ["FAIL" if _fails > 0 else "OK", _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _near(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


# --- stick feel --------------------------------------------------------------------------------

func _stick() -> void:
	var expo := AimSettings.Response.EXPONENTIAL
	var lin := AimSettings.Response.LINEAR
	var inner := 0.12
	var outer := 0.05
	_check(StickFeel.shape(Vector2(0.1, 0.0), inner, outer, expo) == Vector2.ZERO, "inside the inner deadzone: nothing")
	_check(StickFeel.shape(Vector2(0.08, -0.08), inner, outer, expo) == Vector2.ZERO, "deadzone is round (0.11 on a diagonal: nothing)")
	_check(StickFeel.shape(Vector2(0.121, 0.0), inner, outer, lin).length() < 0.01, "just past the inner deadzone starts from 0")
	_check(_near(StickFeel.shape(Vector2(0.96, 0.0), inner, outer, expo).x, 1.0, 1e-4), "in the outer deadzone: full")
	_check(_near(StickFeel.shape(Vector2(1.0, 0.0), inner, outer, lin).x, 1.0, 1e-4), "full stick: full")
	var mid := inner + (1.0 - outer - inner) * 0.5
	var lin_mid := StickFeel.shape(Vector2(mid, 0.0), inner, outer, lin).x
	var expo_mid := StickFeel.shape(Vector2(mid, 0.0), inner, outer, expo).x
	_check(_near(lin_mid, 0.5, 1e-3), "linear: half the travel gives half speed (%.3f)" % lin_mid)
	var want := (exp(StickFeel.EXPO * 0.5) - 1.0) / (exp(StickFeel.EXPO) - 1.0)
	_check(_near(expo_mid, want, 1e-3) and expo_mid < 0.3, "exponential: half the travel gives %.3f (slow in the middle)" % expo_mid)
	var diag := StickFeel.shape(Vector2(0.5, 0.5), inner, outer, expo)
	_check(_near(diag.angle(), Vector2(0.5, 0.5).angle(), 1e-4), "shaping keeps the stick's direction")
	var prev := -1.0
	var rising := true
	for i in 101:
		var v := StickFeel.response(i / 100.0, expo)
		rising = rising and v >= prev
		prev = v
	_check(rising and _near(StickFeel.response(0.0, expo), 0.0, 1e-6) and _near(StickFeel.response(1.0, expo), 1.0, 1e-6), "exponential curve runs 0 to 1 without dipping")


func _boost() -> void:
	var feel := StickFeel.new()
	var t := 0.0
	var at_02 := 0.0
	var mid := 0.0
	while t < 0.6:
		var b := feel.update_boost(Vector2(1.0, 0.0), DT)
		t += DT
		if t <= 0.19:
			at_02 = maxf(at_02, b)
		if _near(t, 0.375, DT * 0.5):
			mid = b
	_check(_near(at_02, 1.0, 1e-6), "turn boost: nothing in the first 0.2 s at the edge")
	_check(mid > 1.2 and mid < 1.7, "turn boost: ramping up after 0.2 s (%.2f at 0.375 s)" % mid)
	_check(_near(feel.boost, StickFeel.BOOST_MAX, 1e-3), "turn boost: full %.1fx by 0.55 s" % StickFeel.BOOST_MAX)
	for i in 6:
		feel.update_boost(Vector2(0.6, 0.0), DT)
	_check(_near(feel.boost, 1.0, 1e-6), "turn boost: off the edge it drops within 0.1 s")
	feel.reset()
	var most := 1.0
	for i in 60:
		most = maxf(most, feel.update_boost(Vector2(0.7, 0.7).normalized() * 0.9, DT))
	for i in 60:
		most = maxf(most, feel.update_boost(Vector2(0.0, 1.0), DT))
	_check(_near(most, 1.0, 1e-6), "turn boost: not short of the edge, nor pushing up and down")


func _device() -> void:
	var joy := InputEventJoypadMotion.new()
	joy.axis = JOY_AXIS_RIGHT_X
	joy.axis_value = 0.8
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(12.0, 3.0)
	InputDevice.note(mouse)
	_check(not InputDevice.controller, "device: mouse movement means the mouse")
	InputDevice.note(joy)
	_check(InputDevice.controller, "device: the stick means the controller")
	InputDevice.note(mouse)
	_check(not InputDevice.controller, "device: last input wins (back to the mouse)")
	joy.axis_value = 0.2
	InputDevice.note(joy)
	_check(not InputDevice.controller, "device: a drifting stick doesn't take over")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_W
	InputDevice.note(joy) # still small
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	InputDevice.note(button)
	_check(InputDevice.controller, "device: a controller button means the controller")
	InputDevice.note(key)
	_check(not InputDevice.controller, "device: a key means the keyboard")


# --- assist ----------------------------------------------------------------------------------

## A target standing still with its chest (aim point) level with the
## shooter's shoulders, dist metres ahead.
func _target(dist: float, x := 0.0, police := false) -> AimDummy:
	var d := AimDummy.new()
	d.walking = false
	d.police = police
	_host.add_child(d)
	d.global_position = Vector3(x, FOCUS.y - 1.2, -dist)
	return d


## The camera as the rig places it aiming: 3 m back along the view from the
## shoulders, looking along (yaw, pitch).
func _view(yaw: float, pitch: float, focus := FOCUS) -> Transform3D:
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	return Transform3D(Basis.looking_at(-off, Vector3.UP), focus + off * 3.0)


func _settle(assist: AimAssist, view: Transform3D, power: float, frames := 30) -> void:
	for i in frames:
		assist.update(_host, view, FOCUS, [], power, DT)


func _clear_targets() -> void:
	for d in _host.get_children():
		_host.remove_child(d)
		d.free()


## Share of the target's motion across the view that tracking follows, with
## the target walking sideways at 3 m/s (or the shooter strafing).
func _track_share(dist: float, strafe := false, power := 1.0) -> float:
	var d := _target(dist)
	var assist := AimAssist.new()
	var yaw := 0.0
	var pitch := 0.0
	var focus := FOCUS
	var turned := 0.0
	var moved := 0.0
	for i in 10:
		var before := AimAssist.angles_of(d.aim_points()[0] - focus).x
		if strafe:
			focus.x -= 3.0 * DT
		else:
			d.global_position.x += 3.0 * DT
		var after := AimAssist.angles_of(d.aim_points()[0] - focus).x
		assist.update(_host, _view(yaw, pitch, focus), focus, [], power, DT)
		yaw += assist.track.x
		pitch += assist.track.y
		if i > 0: # the first frame only sees where it is
			turned += assist.track.x
			moved += angle_difference(before, after)
	_clear_targets()
	return turned / moved if absf(moved) > 1e-6 else 0.0


func _assist() -> void:
	await physics_frame
	var assist := AimAssist.new()
	var ahead := _view(0.0, 0.0)
	# Slowdown.
	var t := _target(15.0)
	_settle(assist, ahead, 1.0)
	_check(_near(assist.slow, AimAssist.SLOWDOWN, 0.01), "slowdown: crosshair on a target at 15 m: %.2f" % assist.slow)
	_settle(assist, ahead, 0.5)
	_check(_near(assist.slow, 0.8, 0.01), "slowdown: Low is half (%.2f)" % assist.slow)
	t.global_position.x = 0.75
	_settle(assist, ahead, 1.0)
	_check(assist.slow > AimAssist.SLOWDOWN + 0.02 and assist.slow < 0.98, "slowdown: just beside the target, some (%.2f)" % assist.slow)
	t.global_position.x = 4.0
	_settle(assist, ahead, 1.0)
	_check(_near(assist.slow, 1.0, 0.01), "slowdown: 4 m off to the side, none (%.2f)" % assist.slow)
	t.global_position.x = 0.0
	t.global_position.y += 0.4 # crosshair at the belly: the zone is taller than wide
	_settle(assist, ahead, 1.0)
	_check(_near(assist.slow, AimAssist.SLOWDOWN, 0.02), "slowdown: anywhere on the body (%.2f)" % assist.slow)
	t.global_position.y -= 0.4
	var boosted := AimAssist.new()
	for i in 30:
		boosted.update(_host, ahead, FOCUS, [], 1.0, DT, true)
	_check(_near(boosted.slow, 1.0, 0.01), "slowdown: none while turn boost whips round")
	# Only with a controller, only aiming.
	InputDevice.controller = false
	_check(AimAssist.strength(true) == 0.0, "no assist with the mouse")
	InputDevice.controller = true
	_check(AimAssist.strength(true) == 1.0 and AimAssist.strength(false) == 0.0, "assist with a controller, only while aiming")
	AimSettings.assist = AimSettings.Assist.LOW
	_check(AimAssist.strength(true) == 0.5, "Low setting: half strength")
	AimSettings.assist = AimSettings.Assist.OFF
	_check(AimAssist.strength(true) == 0.0, "Off setting: none")
	AimSettings.reset_defaults()
	_settle(assist, ahead, AimAssist.strength(false))
	_check(assist.slow == 1.0, "not aiming: no slowdown")
	# Out of play.
	t.out = true
	_settle(assist, ahead, 1.0)
	_check(_near(assist.slow, 1.0, 0.01) and assist.target == null, "no assist onto a target that's out")
	t.out = false
	# A wall in the way.
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.SOLID
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	_host.add_child(wall)
	wall.global_position = Vector3(0.0, 1.5, -7.0)
	await physics_frame
	await physics_frame
	_settle(assist, ahead, 1.0)
	_check(_near(assist.slow, 1.0, 0.01) and assist.target == null, "no slowdown through a wall (%.2f)" % assist.slow)
	var moving := 0.0
	for i in 10:
		t.global_position.x += 3.0 * DT
		assist.update(_host, ahead, FOCUS, [], 1.0, DT)
		moving += absf(assist.track.x)
	_check(moving == 0.0, "no tracking through a wall")
	wall.collision_layer = Layers.VEHICLES # a parked car is cover too
	await physics_frame
	t.global_position.x = 0.0
	_settle(assist, ahead, 1.0)
	_check(assist.target == null, "no assist through a car")
	_host.remove_child(wall)
	wall.free()
	await physics_frame
	t.global_position.x = 0.0
	_settle(assist, ahead, 1.0)
	_check(assist.target == t, "with the wall gone, the target is seen again")
	_clear_targets()
	await physics_frame
	# Tracking.
	var near := _track_share(15.0)
	_check(_near(near, AimAssist.TRACKING, 0.04), "tracking: follows %.0f%% of a target walking across at 15 m" % (near * 100.0))
	var strafe := _track_share(15.0, true)
	_check(_near(strafe, AimAssist.TRACKING, 0.04), "tracking: follows %.0f%% when it's you strafing" % (strafe * 100.0))
	var low := _track_share(15.0, false, 0.5)
	_check(_near(low, AimAssist.TRACKING * 0.5, 0.03), "tracking: Low follows %.0f%%" % (low * 100.0))
	var fading := _track_share(32.5)
	_check(fading > 0.12 and fading < 0.28, "tracking: half strength halfway between 25 and 40 m (%.0f%%)" % (fading * 100.0))
	var far := _track_share(45.0)
	_check(absf(far) < 0.005, "tracking: none at 45 m (%.1f%%)" % (far * 100.0))
	var still := _target(15.0)
	var quiet := AimAssist.new()
	var drift := 0.0
	for i in 20:
		quiet.update(_host, ahead, FOCUS, [], 1.0, DT)
		drift += quiet.track.length()
	_check(drift < 1e-6, "tracking: nothing moves when nothing moves")
	_clear_targets()
	await physics_frame


func _snap() -> void:
	var assist := AimAssist.new()
	var dir := Vector3.FORWARD
	# An officer 15 m ahead, 5 degrees to the right.
	var off := deg_to_rad(5.0)
	var cop := _target(15.0 * cos(off), 15.0 * sin(off), true)
	await physics_frame
	_check(assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: an officer 5 degrees off at 15 m")
	var yaw := 0.0
	var pitch := 0.0
	var t := 0.0
	var half := 0.0
	while assist.snapping and t < 1.0:
		var step := assist.snap_step(FOCUS, yaw, pitch, DT)
		yaw += step.x
		pitch += step.y
		t += DT
		if _near(t, AimAssist.SNAP_TIME * 0.5, DT * 0.5):
			half = absf(yaw)
	var want := AimAssist.angles_of(cop.aim_points()[0] - FOCUS)
	_check(_near(yaw, want.x, 0.002) and _near(pitch, want.y, 0.002), "snap: on the officer (%.2f deg off)" % rad_to_deg(Vector2(yaw - want.x, pitch - want.y).length()))
	_check(t <= AimAssist.SNAP_TIME + DT * 1.5, "snap: takes %.2f s" % t)
	_check(half > 0.2 * off and half < 0.8 * off, "snap: eases rather than jumps (%.0f%% at half time)" % (half / off * 100.0))
	cop.police = false
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: never onto anyone who isn't police")
	cop.police = true
	AimSettings.police_snap = false
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: off when an event turns it off")
	AimSettings.police_snap = true
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 0.0), "snap: none with the mouse or assist Off")
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 0.5), "snap: Low halves the cone (5 degrees is outside it)")
	cop.out = true
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: not onto an officer who's out")
	cop.out = false
	_clear_targets()
	off = deg_to_rad(12.0)
	_target(15.0 * cos(off), 15.0 * sin(off), true)
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: not 12 degrees off")
	_clear_targets()
	_target(30.0, 0.0, true)
	_check(not assist.begin_snap(_host, FOCUS, dir, [], 1.0), "snap: not at 30 m")
	_clear_targets()
	await physics_frame


# --- the real camera rig and player --------------------------------------------------------------

func _joy(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _rig() -> void:
	Engine.max_fps = 60
	var ground := StaticBody3D.new()
	ground.collision_layer = Layers.GROUND
	var gs := CollisionShape3D.new()
	var plane := BoxShape3D.new()
	plane.size = Vector3(200.0, 1.0, 200.0)
	gs.shape = plane
	gs.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(gs)
	_host.add_child(ground)
	var player: PlayerController = load("res://scenes/player/player.tscn").instantiate()
	var rig: CameraRig = load("res://scenes/camera/camera_rig.tscn").instantiate()
	_host.add_child(player)
	_host.add_child(rig)
	player.camera_rig = rig
	rig.target = player
	player.global_position = Vector3.ZERO
	rig.snap_to_target()
	await _frames(10)
	# The stick is read raw (the action's own deadzone doesn't cut it off).
	_joy(JOY_AXIS_RIGHT_X, 0.15)
	await _frames(2)
	var raw := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.0)
	_check(_near(raw.x, 0.15, 0.01), "rig: stick read raw below the action deadzone (%.2f)" % raw.x)
	_joy(JOY_AXIS_RIGHT_X, 0.0)
	await _frames(2)
	# Aim with a controller at a target straight down the view.
	var yaw := rig.yaw
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	_joy(JOY_AXIS_TRIGGER_LEFT, 1.0) # LT: aim, and says "controller"
	await _frames(40)
	# Stand a target where the crosshair is, 15 m out.
	var view := rig.camera.get_camera_transform()
	var d := AimDummy.new()
	d.walking = false
	_host.add_child(d)
	d.global_position = view.origin - view.basis.z * (15.0 + 3.0) - Vector3.UP * 1.2
	await _frames(30)
	_check(InputDevice.controller, "rig: LT counts as the controller")
	_check(player.aiming, "rig: the player is aiming")
	_check(rig._assist.target == d and _near(rig._assist.slow, AimAssist.SLOWDOWN, 0.03), "rig: slowdown on the target with a controller (%.2f)" % rig._assist.slow)
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(3.0, 0.0)
	Input.parse_input_event(mouse)
	await _frames(3)
	_check(not InputDevice.controller and rig._assist.slow == 1.0, "rig: none once the mouse moves")
	_joy(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _frames(30)
	# The aim-in snap onto an officer, through the rig.
	d.police = true
	var off := deg_to_rad(5.0)
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	d.global_position = player.global_position + (ahead * cos(off) + side * sin(off)) * 15.0
	await physics_frame
	_joy(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(30)
	# The crosshair's own line (over the shoulder) runs through the officer.
	var cam := rig.camera.get_camera_transform()
	var chest: Vector3 = d.aim_points()[0]
	var on_line := Geometry3D.get_closest_point_to_segment(chest, cam.origin, cam.origin - cam.basis.z * 40.0)
	var lateral := (chest - on_line).dot(cam.basis.x)
	_check(absf(lateral) < 0.1, "rig: aiming in eased the crosshair onto the officer (%.2f m to the side)" % lateral)
	_joy(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _frames(30)
	# And not onto a civilian.
	d.police = false
	yaw = rig.yaw
	ahead = Vector3(-sin(yaw), 0.0, -cos(yaw))
	side = Vector3(cos(yaw), 0.0, -sin(yaw))
	d.global_position = player.global_position + (ahead * cos(off) + side * sin(off)) * 15.0
	await physics_frame
	_joy(JOY_AXIS_TRIGGER_LEFT, 1.0)
	await _frames(30)
	_check(absf(angle_difference(yaw, rig.yaw)) < deg_to_rad(1.0), "rig: no snap onto a civilian (turned %.2f deg)" % rad_to_deg(angle_difference(yaw, rig.yaw)))
	_joy(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await _frames(5)
	# The debug key puts test targets down and clears them.
	_host.remove_child(d)
	d.free()
	var key := InputEventKey.new()
	key.keycode = AimDummy.DEBUG_KEY
	key.pressed = true
	AimDummy.debug_key(key, rig)
	key.shift_pressed = true
	AimDummy.debug_key(key, rig)
	await _frames(3)
	var dummies := get_nodes_in_group(AimDummy.GROUP)
	var cops := dummies.filter(func(n: Node) -> bool: return AimAssist.is_police(n))
	_check(dummies.size() == 2 and cops.size() == 1 and get_nodes_in_group(AimAssist.GROUP).size() == 2, "debug key: F6 a walker, Shift+F6 an officer")
	var start: Vector3 = (dummies[0] as Node3D).global_position
	await _frames(30)
	_check((dummies[0] as Node3D).global_position.distance_to(start) > 0.3, "debug key: the test target walks")
	key.shift_pressed = false
	key.ctrl_pressed = true
	AimDummy.debug_key(key, rig)
	await _frames(2)
	_check(get_nodes_in_group(AimDummy.GROUP).is_empty(), "debug key: Ctrl+F6 clears them")

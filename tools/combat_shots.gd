extends SceneTree
## Pictures of the paintball fight on a test pad, for checking how it
## looks: the view over the shoulder with the crosshair, the paint meter,
## the arrows to whoever hit you and the edges when nearly out, two
## officers shooting (their warning shots, bursts and recoil), and the
## dodge roll from the side. Run with a real renderer:
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
##       godot --rendering-driver vulkan --resolution 1280x720 --path . \
##       --script res://tools/combat_shots.gd -- [--out=/tmp/combat-shots]
##
## Saves OUT/NAME.png for each view and prints the paths.

var _out := "/tmp/combat-shots"
var _player: PlayerController
var _rig: CameraRig
var _hud: CombatHud
var _ring: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.86)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.65)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(200, 2, 200)
	shape.position = Vector3(0, -1, 0)
	pad.add_child(shape)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.37, 0.38)
	ground.material_override = gm
	pad.add_child(ground)
	root.add_child(pad)
	# A wall behind the player, for the warning shots to splat on.
	var wall := StaticBody3D.new()
	wall.collision_layer = Layers.SOLID
	var ws := CollisionShape3D.new()
	ws.shape = BoxShape3D.new()
	(ws.shape as BoxShape3D).size = Vector3(30, 5, 1)
	wall.add_child(ws)
	var wm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 5, 1)
	wm.mesh = bm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.62, 0.32, 0.25)
	wm.material_override = wmat
	wall.add_child(wm)
	root.add_child(wall)
	wall.global_position = Vector3(0, 2.5, 4)

	var shots := PaintShots.new()
	root.add_child(shots)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.input_enabled = false
	root.add_child(_player)
	_player.place(Transform3D.IDENTITY)
	_rig = (load("res://scenes/camera/camera_rig.tscn") as PackedScene).instantiate()
	root.add_child(_rig)
	_rig.target = _player
	_player.camera_rig = _rig
	_rig.snap_to_target()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	_hud = CombatHud.new()
	layer.add_child(_hud)
	_hud.setup(_player)
	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_CENTER)
	_ring.draw.connect(func() -> void:
		var r := clampf(tan(deg_to_rad(_player.marker.spread_now)) / tan(deg_to_rad(_rig.camera.fov * 0.5)) * 360.0, 9.0, 70.0)
		_ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.55), 3.5, true)
		_ring.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1, 1, 1, 0.9), 1.5, true))
	layer.add_child(_ring)

	var officers: Array[Officer] = []
	for i in 2:
		var o := Officer.new()
		o.force = "city"
		o.number = i
		root.add_child(o)
		o.global_position = Vector3((i - 0.5) * 7.0, 0.0, -16.0)
		PoliceUnit.apply_foot_tuning(o, 2)
		o.shoot_at = _player
		officers.append(o)
	# Aim at the left officer and fire paced shots for a while.
	var target := officers[0]
	_player.body_paint.can_go_out = true
	for f in 150:
		_player.bot_aim = target.global_position + Vector3.UP * 1.3
		_player.bot_fire = f % 14 < 2
		await physics_frame
	await _shot("aim_fight")
	# Spamming the trigger: the ring opens.
	for f in 20:
		_player.bot_fire = f % 2 == 0
		await physics_frame
	await _shot("aim_bloom")
	_player.bot_fire = false
	# Nearly out: the meter, the arrows and the edges.
	while _player.body_paint.out_hits - _player.body_paint.hits > 2 and not _player.is_out():
		await physics_frame
	await _shot("nearly_out")
	# The roll, from the side.
	for o in officers:
		o.shoot_at = null
	_player.body_paint.revive()
	_player.bot_aim = Vector3.INF
	await _frames(30)
	_rig.target = null
	_rig.camera.global_position = Vector3(7, 1.4, -1.5)
	_rig.camera.look_at(Vector3(0.5, 0.8, -1.5))
	Engine.max_physics_steps_per_frame = 1
	_player.bot_wish = Vector3(1, 0, 0)
	_player.bot_dodge = true
	# One physics step a drawn frame, so the pictures land where they say
	# (drawing in software is slow, and the game would catch up in steps).
	Engine.max_physics_steps_per_frame = 1
	for i in 6:
		for f in 3:
			await physics_frame
		await _shot("roll_%d" % i, false)
	quit(0)


func _shot(name: String, hud := true) -> void:
	_hud.visible = hud
	_ring.visible = hud
	_ring.queue_redraw()
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	img.save_png(path)
	print("SHOT ", path)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame

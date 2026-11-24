extends SceneTree
## Photographs the loads (Cargo.KINDS) in a row on a plain pad, and a
## flatbed trailer with some of them aboard, for checking how they look:
##
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/cargo_studio.gd -- --out=/tmp/cargo
##
## Saves OUT/cargo_row.png, OUT/cargo_close.png and OUT/cargo_trailer.png.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/cargo"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
			for c in node.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
	var stage := Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	stage.add_child(sun)
	var pad := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.36, 0.35, 0.33)
	pad.material_override = pmat
	stage.add_child(pad)
	var cam := Camera3D.new()
	cam.fov = 50.0
	stage.add_child(cam)
	cam.current = true
	var x := -6.0
	for kind: String in Cargo.KINDS:
		var c := Cargo.new()
		c.kind = kind
		c.freeze = true
		c.position = Vector3(x, 0, 0)
		stage.add_child(c)
		x += 2.2
	var trailer := Car.new()
	trailer.model_id = "flatbed_trailer"
	trailer.paint = Color.html("#3a3d40")
	trailer.position = Vector3(0, 0, -14)
	trailer.rotation.y = PI / 2.0
	stage.add_child(trailer)
	trailer.freeze = true
	trailer.set_physics_process(false)
	var on_deck := ["pallet_bricks", "pallet_boxes", "lumber", "crate", "pallet_sacks"]
	var z := -5.0
	for kind: String in on_deck:
		var c := Cargo.new()
		c.kind = kind
		c.freeze = true
		stage.add_child(c)
		c.global_position = trailer.global_transform * Vector3(0, 1.5, z)
		c.global_rotation.y = trailer.rotation.y
		c.set_strapped(kind == "pallet_bricks")
		z += 4.2 if kind == "lumber" else 2.3
	for shot: Array in [["row", Vector3(-1.0, 3.2, 7.5), Vector3(-0.5, 0.6, 0)], ["close", Vector3(-4.2, 1.9, 3.0), Vector3(-3.0, 0.6, 0)],
			["trailer", Vector3(-9, 5.5, -5), Vector3(0, 1.5, -14)]]:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/cargo_%s.png" % [out, shot[0]])
		print("STUDIO saved cargo_", shot[0])
	quit()

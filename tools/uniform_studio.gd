extends SceneTree
## A photo studio for people in uniform: the officers of each force (and
## any other crew whose look comes from a static `uniform(which, rng)`),
## standing on a pad, shot from the front, the back and close up on the
## head and belt. For checking a uniform without loading the town. Run it
## with a real renderer:
##
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/uniform_studio.gd -- --out=/tmp/uniforms [--who=city,fip]
##
## Saves OUT/WHO_VIEW.png (views: front, back, face, belt).

const VIEWS := {
	# camera, look-at, in the person's space (facing -z)
	"front": [Vector3(-0.9, 1.25, -2.4), Vector3(0, 1.0, 0)],
	"back": [Vector3(0.9, 1.3, 2.4), Vector3(0, 1.05, 0)],
	"face": [Vector3(-0.35, 1.72, -0.7), Vector3(0, 1.68, 0)],
	"belt": [Vector3(0.7, 1.05, -0.85), Vector3(0, 0.98, 0)],
}

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() == 2 else "1"
	_run.call_deferred()


func _run() -> void:
	var out: String = _args.get("out", "/tmp/uniforms")
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
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.76, 0.8)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
	pm.size = Vector2(20, 20)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.36, 0.35, 0.33)
	pad.material_override = pmat
	stage.add_child(pad)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.03
	stage.add_child(cam)
	cam.current = true
	var who: Array = (str(_args.get("who", "city,fip"))).split(",")
	for w: String in who:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(w)
		var m := HumanoidModel.new()
		m.set_appearance(Officer.uniform(w, rng))
		stage.add_child(m)
		var tris := 0
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			tris += mi.mesh.surface_get_array_index_len(0) / 3
		print("STUDIO %s: %d triangles" % [w, tris])
		for v: String in VIEWS:
			cam.position = VIEWS[v][0]
			cam.look_at(VIEWS[v][1])
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s_%s.png" % [out, w, v]
			root.get_texture().get_image().save_png(path)
			print("STUDIO saved ", path)
		m.free()
	quit()

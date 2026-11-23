extends SceneTree
## Art-direction experiments: loads the town once, then for every viewpoint
## renders it in each candidate "look" (lighting, sky, grading, film, trees).
## Nothing here changes the game; it only adjusts the scene at run time.
##
##   godot --path . --rendering-driver vulkan --resolution 1280x720 \
##       --script res://tools/look_lab.gd -- --out=/tmp/looks \
##       --shot=name:x,z,yaw,pitch[,lift] [--looks=current,overcast,...]

const LOOKS := ["current", "assets", "overcast", "golden", "film"]

var _args := {}
var _shots: Array = []
var _main: Node
var _env: Environment
var _sun: DirectionalLight3D
var _post: ColorRect
var _sky_mat: ShaderMaterial
var _orig_env: Environment
var _orig_sun := {}
var _mat_backup: ShaderMaterial
var _assets_on := false
var _leaves: ShaderMaterial
var _orig_leaf_shader: Shader
var _crown_backup := {}
var _card_meshes := {}
var _ground_code := ""
var _ground_lab_code := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "shot":
			_shots.append(kv[1])
		elif kv.size() == 2:
			_args[kv[0]] = kv[1]
	_run.call_deferred()


func _run() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	current_scene = _main
	await process_frame
	var world: Node = _main.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	if world.has_method("wait_until_settled"):
		await world.wait_until_settled()
	_main.get_node("HUD").visible = false
	_env = (_main.get_node("WorldEnvironment") as WorldEnvironment).environment
	_orig_env = _env.duplicate(true)
	_sun = _main.get_node("Sun")
	for p in ["rotation", "light_color", "light_energy", "light_angular_distance", "shadow_blur"]:
		_orig_sun[p] = _sun.get(p)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://tools/look_lab/sky.gdshader")
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	_post = ColorRect.new()
	_post.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = load("res://tools/look_lab/post.gdshader")
	_post.material = pm
	layer.add_child(_post)
	_leaves = (StreetProps._crowns[0] as ArrayMesh).surface_get_material(0)
	_orig_leaf_shader = _leaves.shader
	_ground_code = Terrain.ground_shader().code
	_ground_lab_code = (load("res://tools/look_lab/terrain_ground_lab.gdshader") as Shader).code
	var cards := ShaderMaterial.new()
	cards.shader = load("res://tools/look_lab/leaf_cards.gdshader")
	var palette := [Color(0.22, 0.34, 0.15), Color(0.28, 0.38, 0.17), Color(0.2, 0.3, 0.15), Color(0.31, 0.37, 0.17)]
	var all_crowns: Array[ArrayMesh] = []
	all_crowns.append_array(StreetProps._crowns)
	all_crowns.append_array(StreetProps._light_crowns)
	for i in all_crowns.size():
		var m := all_crowns[i]
		_crown_backup[m] = m.surface_get_arrays(0)
		var light := i >= StreetProps._crowns.size()
		_card_meshes[m] = _card_crown(i, palette[i % 4], 150 if not light else 100, 1.0 if not light else 1.3)
	_mat_backup = cards

	var looks: PackedStringArray = str(_args.get("looks", ",".join(LOOKS))).split(",")
	var out := str(_args.get("out", "user://looks"))
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.far = 4000.0
	root.add_child(cam)
	for s: String in _shots:
		var parts := s.split(":")
		var v := parts[1].split_floats(",")
		var pos := Vector2(v[0], v[1])
		var lift := v[4] if v.size() > 4 else 1.7
		var player: Node3D = _main.get_node("Player")
		var back := Vector2(sin(deg_to_rad(v[2])), cos(deg_to_rad(v[2]))) * 6.0
		player.global_position = world.terrain.at(pos + back, 0.5)
		cam.global_position = world.terrain.at(pos, lift)
		cam.rotation = Vector3(deg_to_rad(v[3]), deg_to_rad(v[2]), 0.0)
		cam.make_current()
		if world.has_method("wait_until_settled"):
			await world.wait_until_settled()
		for look in looks:
			_apply(look)
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s__%s.png" % [out, parts[0], look])
			print("LOOK %s %s" % [parts[0], look])
	quit()


func _reset() -> void:
	for p in _orig_env.get_property_list():
		if p["usage"] & PROPERTY_USAGE_STORAGE:
			_env.set(p["name"], _orig_env.get(p["name"]))
	for p in _orig_sun:
		_sun.set(p, _orig_sun[p])
	_post.visible = false
	_leaves.shader = _orig_leaf_shader
	_assets(false)


## Swaps the tree crowns for leaf-card crowns and the ground for the
## patchier lab ground, in place, so every placed tree and chunk follows.
func _assets(on: bool) -> void:
	if on == _assets_on:
		return
	_assets_on = on
	Terrain.ground_shader().code = _ground_lab_code if on else _ground_code
	for m: ArrayMesh in _crown_backup:
		var mat := m.surface_get_material(0)
		m.clear_surfaces()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _card_meshes[m] if on else _crown_backup[m])
		m.surface_set_material(0, _mat_backup if on else mat)
		if on:
			m.set_meta("orig_mat", mat)
		elif m.has_meta("orig_mat"):
			m.surface_set_material(0, m.get_meta("orig_mat"))


## Arrays for a crown of leaf cards spread through the same ellipsoid the
## blob crowns fill. Normals point out from the middle so the crown shades
## as one soft mass; colour darkens low and deep inside.
func _card_crown(variant: int, leaf: Color, cards: int, grow: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * (variant + 3)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var lobes: Array[Vector3] = []
	for l in 5:
		lobes.append(Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-0.6, 0.9), rng.randf_range(-1.2, 1.2)))
	for c in cards:
		var lobe := lobes[c % lobes.size()]
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.8, 1), rng.randf_range(-1, 1)).normalized()
		var at := lobe * 0.8 + dir * Vector3(1.6, 1.2, 1.6) * pow(rng.randf(), 0.4) * grow
		var size := rng.randf_range(0.9, 1.4) * grow
		var b := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0, TAU))
		var ax := b.x * size * 0.5
		var ay := b.y * size * 0.5
		var base := verts.size()
		var corners := [at - ax - ay, at + ax - ay, at + ax + ay, at - ax + ay]
		var cuv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		var tint := leaf * rng.randf_range(0.95, 1.05)
		for k in 4:
			var pt: Vector3 = corners[k]
			verts.append(pt)
			norms.append((pt - lobe * 0.3).normalized())
			uvs.append(cuv[k])
			var lift := clampf((pt.y + 2.6) / 4.6, 0.0, 1.0)
			var depth := clampf(pt.length() / 2.8, 0.0, 1.0)
			cols.append((tint * (0.4 + 0.35 * lift + 0.4 * depth)).srgb_to_linear())
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


func _sky(params: Dictionary) -> void:
	var sky := Sky.new()
	var m: ShaderMaterial = _sky_mat.duplicate()
	for k in params:
		m.set_shader_parameter(k, params[k])
	sky.sky_material = m
	_env.sky = sky


func _post_fx(params: Dictionary) -> void:
	_post.visible = true
	var m := _post.material as ShaderMaterial
	for k in ["grain", "vignette", "aberration", "green_desat", "lift", "halation", "soft"]:
		m.set_shader_parameter(k, 0.0)
	for k in ["contrast", "saturation"]:
		m.set_shader_parameter(k, 1.0)
	m.set_shader_parameter("shadow_tint", Vector3.ONE)
	m.set_shader_parameter("highlight_tint", Vector3.ONE)
	for k in params:
		m.set_shader_parameter(k, params[k])


func _apply(look: String) -> void:
	_reset()
	if look != "current":
		_assets(true)
	match look:
		"overcast":
			# Maritime overcast: soft directionless light, grey-white sky, damp
			# colours. Hides simple geometry the way a cloudy day does in photos.
			_sky({"zenith": Color(0.6, 0.64, 0.68), "horizon": Color(0.82, 0.83, 0.82),
				"cloud_lit": Color(0.9, 0.9, 0.89), "cloud_shade": Color(0.55, 0.57, 0.6),
				"coverage": 0.8, "softness": 0.35, "energy": 1.05, "sun_glow": 0.08})
			_sun.light_energy = 0.75
			_sun.light_color = Color(0.94, 0.95, 0.97)
			_sun.light_angular_distance = 8.0
			_sun.shadow_blur = 4.0
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			_env.ambient_light_energy = 1.3
			_env.ssao_intensity = 3.2
			_env.ssao_radius = 2.2
			_env.ssao_light_affect = 0.5
			_env.fog_light_color = Color(0.76, 0.78, 0.8)
			_env.fog_density = 0.0028
			_env.fog_aerial_perspective = 0.2
			_env.fog_sky_affect = 0.5
			_env.tonemap_exposure = 1.25
			_env.adjustment_saturation = 0.85
			_env.adjustment_contrast = 1.1
			_post_fx({"green_desat": 0.5, "vignette": 0.25, "grain": 0.025})
		"golden":
			# Late-afternoon sun: long raking shadows, warm light against cool
			# shade, thick air in the distance.
			_sky({"zenith": Color(0.38, 0.5, 0.68), "horizon": Color(0.93, 0.82, 0.68),
				"cloud_lit": Color(1.0, 0.86, 0.72), "cloud_shade": Color(0.55, 0.53, 0.6),
				"coverage": 0.35, "softness": 0.2, "energy": 1.0, "sun_glow": 0.6})
			_sun.rotation = Vector3(-0.26, -1.9, 0.0)
			_sun.light_color = Color(1.0, 0.78, 0.55)
			_sun.light_energy = 3.0
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			_env.ambient_light_energy = 0.45
			_env.fog_light_color = Color(0.88, 0.8, 0.7)
			_env.fog_density = 0.0028
			_env.fog_sun_scatter = 0.35
			_env.fog_aerial_perspective = 0.5
			_env.tonemap_exposure = 1.05
			_env.adjustment_saturation = 0.92
			_post_fx({"green_desat": 0.4, "vignette": 0.35, "grain": 0.02,
				"shadow_tint": Vector3(0.95, 0.99, 1.05), "highlight_tint": Vector3(1.04, 1.0, 0.95)})
		"film":
			# Same midday, shot like a photo: scattered cloud, darker shade,
			# natural greens, colour-negative grade, grain, lens falloff.
			_sky({"zenith": Color(0.4, 0.54, 0.7), "horizon": Color(0.78, 0.8, 0.8),
				"cloud_lit": Color(0.97, 0.96, 0.94), "cloud_shade": Color(0.62, 0.65, 0.7),
				"coverage": 0.42, "softness": 0.25, "energy": 1.0, "sun_glow": 0.25})
			_sun.light_energy = 2.4
			_sun.light_color = Color(1.0, 0.94, 0.86)
			_env.ambient_light_energy = 0.5
			_env.ambient_light_sky_contribution = 0.8
			_env.ssao_intensity = 3.0
			_env.ssao_light_affect = 0.3
			_env.fog_light_color = Color(0.7, 0.75, 0.8)
			_env.fog_density = 0.0022
			_env.tonemap_agx_contrast = 1.3
			_env.adjustment_saturation = 0.88
			_post_fx({"green_desat": 0.6, "vignette": 0.4, "grain": 0.03, "aberration": 0.2,
				"halation": 0.25, "soft": 0.3, "lift": 0.02, "contrast": 1.04,
				"shadow_tint": Vector3(0.95, 1.0, 1.04), "highlight_tint": Vector3(1.04, 1.01, 0.95)})

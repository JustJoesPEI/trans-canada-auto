extends SceneTree
## Renders a line-up of people in different outfits, covering every kind of
## hat, top, bottom and shoe, from the front-left and from behind.
## godot --path . -s tools/char_preview/char_outfits.gd -- <out_dir>
## Writes outfits.png.

const LINEUP := [
	{"hat": {"kind": "cap", "color": Color(0.1, 0.1, 0.12), "print": "spud_kings"},
		"top": {"kind": "tshirt", "color": Color(0.9, 0.9, 0.88), "trim": Color(0.75, 0.75, 0.73), "print": "whos_your_father"},
		"bottom": {"kind": "shorts", "color": Color(0.45, 0.42, 0.33)}, "shoes": {"kind": "sneakers", "color": Color(0.2, 0.2, 0.22)}},
	{"hat": {"kind": "toque", "color": Color(0.15, 0.2, 0.32), "print": "canada_gull"},
		"top": {"kind": "hoodie", "color": Color(0.22, 0.23, 0.25), "print": "spud_co"},
		"bottom": {"kind": "joggers", "color": Color(0.12, 0.12, 0.13)}, "shoes": {"kind": "sneakers", "color": Color(0.86, 0.85, 0.82)}},
	{"hat": {"kind": "none"}, "top": {"kind": "bomber", "color": Color(0.29, 0.33, 0.22), "patch": "canada_gull", "back": "red_mud"},
		"bottom": {"kind": "jeans", "color": Color(0.12, 0.12, 0.13)}, "shoes": {"kind": "boots", "color": Color(0.15, 0.12, 0.1)}},
	{"hat": {"kind": "cap", "color": Color(0.6, 0.12, 0.12), "print": "tom_hurtins"},
		"top": {"kind": "denim", "color": Color(0.3, 0.42, 0.6), "back": "mainlanders"},
		"bottom": {"kind": "trousers", "color": Color(0.15, 0.15, 0.17)}, "shoes": {"kind": "sneakers", "color": Color(0.1, 0.1, 0.1)}},
	{"hat": {"kind": "none"}, "top": {"kind": "varsity", "color": Color(0.12, 0.16, 0.32), "print": "varsity_s", "back": "spud_kings"},
		"bottom": {"kind": "jeans", "color": Color(0.3, 0.38, 0.5)}, "shoes": {"kind": "sneakers", "color": Color(0.86, 0.85, 0.82)}},
	{"hat": {"kind": "toque", "color": Color(0.5, 0.12, 0.12)}, "top": {"kind": "puffer", "color": Color(0.1, 0.1, 0.12), "patch": "canada_gull"},
		"bottom": {"kind": "jeans", "color": Color(0.21, 0.25, 0.34)}, "shoes": {"kind": "boots", "color": Color(0.42, 0.29, 0.17)}},
	{"hat": {"kind": "cap", "color": Color(0.2, 0.3, 0.22), "print": "red_mud"}, "top": {"kind": "flannel", "color": Color(0.6, 0.12, 0.12)},
		"bottom": {"kind": "jeans", "color": Color(0.21, 0.25, 0.34)}, "shoes": {"kind": "boots", "color": Color(0.42, 0.29, 0.17)}},
	{"hat": {"kind": "none"}, "top": {"kind": "longsleeve", "color": Color(0.25, 0.38, 0.28), "print": "pay_to_leave", "back": "potholes"},
		"bottom": {"kind": "trousers", "color": Color(0.33, 0.3, 0.25)}, "shoes": {"kind": "dress", "color": Color(0.25, 0.15, 0.1)}},
	{"hat": {"kind": "none"}, "top": {"kind": "jacket", "color": Color(0.66, 0.16, 0.13), "trim": Color(0.82, 0.8, 0.74), "print": "tca"},
		"bottom": {"kind": "jeans", "color": Color(0.21, 0.25, 0.34)}, "shoes": {"kind": "sneakers", "color": Color(0.16, 0.12, 0.1)}},
]
const LOOKS := [
	{"skin": Color(0.87, 0.69, 0.57), "hair": Color(0.23, 0.16, 0.11), "hair_style": 0},
	{"skin": Color(0.58, 0.4, 0.28), "hair": Color(0.1, 0.08, 0.07), "hair_style": 2},
	{"skin": Color(0.95, 0.8, 0.69), "hair": Color(0.72, 0.58, 0.36), "hair_style": 1},
	{"skin": Color(0.76, 0.57, 0.43), "hair": Color(0.1, 0.08, 0.07), "hair_style": 0},
	{"skin": Color(0.4, 0.27, 0.19), "hair": Color(0.1, 0.08, 0.07), "hair_style": 2},
	{"skin": Color(0.87, 0.69, 0.57), "hair": Color(0.45, 0.3, 0.18), "hair_style": 1},
	{"skin": Color(0.95, 0.8, 0.69), "hair": Color(0.62, 0.6, 0.58), "hair_style": 2},
	{"skin": Color(0.76, 0.57, 0.43), "hair": Color(0.23, 0.16, 0.11), "hair_style": 0},
	{"skin": Color(0.87, 0.69, 0.57), "hair": Color(0.23, 0.16, 0.11), "hair_style": 0},
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	var vp := SubViewport.new()
	vp.size = Vector2i(2400, 560)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.66, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.65)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	vp.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.45, 0.43)
	floor.material_override = fm
	vp.add_child(floor)
	var people := []
	for i in LINEUP.size():
		var m: HumanoidModel = load("res://scripts/characters/humanoid_model.gd").new()
		var look: Dictionary = LOOKS[i].duplicate()
		look["outfit"] = LINEUP[i]
		m.set_appearance(look)
		m.position = Vector3((i - (LINEUP.size() - 1) * 0.5) * 0.78, 0.0, 0.0)
		vp.add_child(m)
		people.append(m)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.0 # metres tall
	vp.add_child(cam)
	var sheet := Image.create(2400, 1120, false, Image.FORMAT_RGBA8)
	for row in 2:
		for m: HumanoidModel in people:
			m.rotation.y = 0.45 if row == 0 else PI
		cam.position = Vector3(0.0, 1.0, -8.0)
		cam.look_at(Vector3(0.0, 0.95, 0.0))
		for f in 20:
			await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(img, Rect2i(0, 0, 2400, 560), Vector2i(0, 560 * row))
	sheet.save_png(out.path_join("outfits.png"))
	quit()

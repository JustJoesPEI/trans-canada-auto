class_name ShaderWarmup
extends Node3D
## Shows every look the town doesn't show at once, for a few frames in front
## of the camera while the loading screen is still up, so its shaders are
## compiled then rather than mid-game the first time one comes into view (a
## hitch of its own each, and slower on Direct3D 12: the hitch log counts
## them, "shader(s) compiled"). The materials' meshes are built already
## (the traffic and police looks on the title screen); this only draws
## them: every car and police look, a police car with its lights going,
## paint and mud on a car, tyre marks, smoke and flung mud, a paint splat,
## a paintball, the throwing arc, a person, and a faded tree crown.
##
## The title menu keeps the loading screen up until `done`. Not run under a
## headless tool (`--script`): nothing's drawn there anyway; a tool that
## draws and wants it (tools/memory_budget.gd) sets `run_in_tools`.
## When it's done it prints how many pipelines it compiled.

static var done := false
static var run_in_tools := false
## Pipelines compiled while it was up, the town's first frames with it (-1
## until it has run).
static var pipelines := -1

const FRAMES := 3
## A car's length apart, in a grid in front of the camera.
const SPACING := 5.0
## [model, livery]: one of each builder and every livery.
const WARM_LOOKS := [["civique", ""], ["halfton", ""], ["rollback", ""], ["hauler", ""],
	["jaunt", "cps"], ["tahoma", "fip"], ["paint_tank", "fip_tactical"]]


func run(cam: Camera3D) -> void:
	if cam == null or (OS.get_cmdline_args().has("--script") and not run_in_tools) or DisplayServer.get_name() == "headless":
		done = true
		return
	var pipes_before := pipelines_compiled()
	name = "ShaderWarmup"
	# Well in front of the camera, where it's looking, behind the loading screen.
	global_transform = cam.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, -1.0, -14.0))
	var made: Array[Node] = []
	var slot := 0
	# Shaders go by kind of material, not by look: a car, a pickup, the
	# trucks and the police liveries cover every car material there is (a
	# paint colour is the same shader). Built now if they aren't yet (well
	# under a second, behind the loading screen); other looks built so far
	# are shown too.
	for v: Array in WARM_LOOKS:
		var livery: String = v[1]
		var paint := Color.WHITE if livery == "" else Color.from_string(str(CarModels.LIVERIES[livery]["colour"]), Color.WHITE)
		Car.warm_meshes(v[0], paint, livery)
	# Every car look built so far.
	for key: String in Car._mesh_cache:
		var meshes: Dictionary = Car._mesh_cache[key]["meshes"]
		for k: String in ["body", "detail"]:
			if meshes.get(k) is Mesh:
				_show(meshes[k], slot, made)
		var lamps: Variant = meshes.get("lamps")
		if lamps is Dictionary:
			for m: Variant in (lamps as Dictionary).values():
				if m is Mesh:
					_show(m, slot, made)
		slot += 1
	# A car with paint on it, and mud over the paint (and mud alone).
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 1.0, 3.0)
	var mud := ShaderMaterial.new()
	mud.shader = load("res://shaders/car_mud.gdshader")
	var painted := _show(box, slot, made)
	var overlay := PaintCoverage.new_overlay_material()
	overlay.next_pass = mud
	painted.material_overlay = overlay
	slot += 1
	_show(box, slot, made).material_overlay = mud
	slot += 1
	# A paint splat, a paintball, the throwing arc, a person's body.
	for mat: Material in [PaintSplats.shared_material(), PaintShots._ball_shader_material(), ThrowArc._shared_material(), BodyBuilder.material()]:
		_show(box, slot, made).material_override = mat
		slot += 1
	# The buildings' faded copies (the camera fades one in its way).
	var mats := Materials.get_shared()
	for m: ShaderMaterial in [mats.building_walls, mats.building_roofs]:
		var fm := BuildingFade.faded_copy(m)
		fm.set_shader_parameter("fade", 0.5)
		_show(box, slot, made).material_override = fm
		slot += 1
	# A real police car with its lights going (its lenses and lights are
	# made with it). No engine sound: it's gone before anyone could hear.
	var was_silent := Car.silent
	Car.silent = true
	var police := Car.new()
	police.model_id = PoliceUnit.MODELS["city"][0]
	police.livery = PoliceUnit.MODELS["city"][1]
	police.paint = Color.from_string(str(CarModels.LIVERIES[police.livery]["colour"]), Color.WHITE)
	police.freeze = true
	police.collision_layer = 0
	police.collision_mask = 0
	police.position = _slot_at(slot)
	slot += 1
	add_child(police)
	made.append(police)
	Car.silent = was_silent
	if police.police != null:
		police.police.set_mode(PoliceGear.Mode.LIGHTS)
	# A person.
	var person := Pedestrian.make_model(0)
	person.position = _slot_at(slot)
	slot += 1
	add_child(person)
	made.append(person)
	# A tree crown faded out (as the camera fades one in its way).
	for n: Node in get_tree().get_nodes_in_group("camera_fade_props"):
		var m: Variant = n.get("mesh") # a MeshInstance3D, or a CrownFade
		if m is Mesh:
			var crown := _show(m as Mesh, slot, made)
			crown.transparency = 0.5
			slot += 1
			break
	# Tyre marks, smoke and flung mud (TyreFx makes its own materials).
	var fx := TyreFx.get_for(self)
	await get_tree().process_frame
	var at := global_transform * _slot_at(slot)
	if fx != null and is_instance_valid(fx):
		fx.slide("warmup", at, Vector3.UP, 0.4, 1.0, -global_basis.z * 10.0, 1.0)
		fx.rut("warmup_r", at + global_basis.x, Vector3.UP, 0.4, 0.8, Color(0.4, 0.2, 0.1))
		fx.fling(at + Vector3.UP, Vector3.UP * 2.0, Color(0.4, 0.2, 0.1))
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	pipelines = pipelines_compiled() - pipes_before
	print("ShaderWarmup: %d pipelines compiled behind the loading screen (the town's first frames with it)" % pipelines)
	# Gone again, all of it (the tyre marks with their node: a fresh one is
	# made when the first real tyre needs it).
	if fx != null and is_instance_valid(fx):
		fx.queue_free()
	for n: Node in made:
		if is_instance_valid(n):
			n.queue_free()
	done = true
	queue_free()


## Pipelines compiled since the game started (every kind).
static func pipelines_compiled() -> int:
	var n := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(k)
	return n


func _slot_at(slot: int) -> Vector3:
	return Vector3(float(slot % 8 - 4) * SPACING, float(slot / 64) * 2.0, -float((slot / 8) % 8) * SPACING)


func _show(mesh: Mesh, slot: int, made: Array[Node]) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = _slot_at(slot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mi)
	made.append(mi)
	return mi

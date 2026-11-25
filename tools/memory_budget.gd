extends SceneTree
## Checks how much graphics memory the whole game takes, against the budget
## for laptops whose graphics share the computer's memory (integrated AMD
## and Intel chips, often with a fixed 512 MB slice of it, which Windows'
## own desktop also draws from). Going over that slice doesn't slow the
## game down, it crashes it (VkResult -10, then "device lost"), so this is
## a hard limit, like the drawing-cost budgets (docs/world_art.md).
##
## It needs a real renderer (the headless one has no graphics memory), and
## the graphics level given on the command line (so it never reads or
## changes the player's saved one). On a desktop:
##
##   godot --rendering-driver vulkan --resolution 1920x1080 --path . \
##       --script res://tools/memory_budget.gd -- --graphics=low
##
## In a cloud container, drawing in software (a few minutes):
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##       godot --rendering-driver vulkan --resolution 1920x1080 --path . \
##       --script res://tools/memory_budget.gd -- --graphics=low
##
## Loads the game, starts it at the spawn, waits for every chunk in range,
## then moves to a couple of other spots in town and does the same. Watches
## the memory every frame and prints one "MEMORY" line per spot (total,
## textures, meshes and other buffers; "other" is mostly room the allocator
## has reserved but not filled) and the peak. On Low it fails ("MEMORY
## FAIL", non-zero exit) if the peak is over BUDGET_MB; on Medium and High
## it only reports. Numbers from the software renderer are close to a real
## card's but not the same: compare runs on the same machine.
##
## --verbose also lists, at the spawn, what holds the memory: every mesh
## (once, however many nodes draw it; MultiMesh instance data per node)
## and every texture reachable from the scene (materials, shader
## parameters, UI), grouped by the node that
## owns it, biggest first. What the renderer holds for itself (screen
## buffers, shadow maps, sky, fonts) and anything drawn straight through
## the RenderingServer shows as the part not accounted for. (Reading the
## textures back adds a little memory, so the spots after it read higher.)
##
## tools/world_budget.gd checks each chunk's own share of the meshes
## (mesh_kb), which is what grows as the town streams in.

## Peak graphics memory on Low at 1920x1080 (MB). When this came in (Nov
## 2026, software renderer): 291-305 MB settled at each spot, peaking at
## 330 MB while the town streamed in round the spawn (new chunks arrive
## before the old ones go). The budget stops it growing; the aim is to get
## well under it, since a 512 MB chip has maybe 300 MB left once Windows'
## desktop and a browser have had theirs.
const BUDGET_MB := 350.0

## Spots to visit after the spawn: [name, x, z] (game metres).
const SPOTS := [
	["east", 600.0, 400.0],
	["north", -300.0, -1700.0],
]

var _peak := 0.0
var _peak_at := ""
var _peak_split := "" ## textures, meshes and buffers at the peak
var _where := "loading"
var _level := ""
var _verbose := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--graphics="):
			_level = a.trim_prefix("--graphics=")
		elif a == "--verbose":
			_verbose = true
	if _level == "":
		printerr("MEMORY give the graphics level to check: -- --graphics=low (or medium, high)")
		quit(2)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		printerr("MEMORY needs a real renderer (see the top of tools/memory_budget.gd); the headless one has no graphics memory")
		quit(2)
		return
	process_frame.connect(_sample)
	_run.call_deferred()


func _mb(monitor: int) -> float:
	return Performance.get_monitor(monitor) / 1048576.0


func _sample() -> void:
	var total := _mb(Performance.RENDER_VIDEO_MEM_USED)
	if total > _peak:
		_peak = total
		_peak_at = _where
		var tex := _mb(Performance.RENDER_TEXTURE_MEM_USED)
		var buf := _mb(Performance.RENDER_BUFFER_MEM_USED)
		_peak_split = "textures=%.0f  meshes and buffers=%.0f  other=%.0f" % [tex, buf, total - tex - buf]


func _report(label: String) -> void:
	var total := _mb(Performance.RENDER_VIDEO_MEM_USED)
	var tex := _mb(Performance.RENDER_TEXTURE_MEM_USED)
	var buf := _mb(Performance.RENDER_BUFFER_MEM_USED)
	print("MEMORY %-8s total=%.0f MB  textures=%.0f  meshes and buffers=%.0f  other=%.0f" % [label, total, tex, buf, total - tex - buf])


func _run() -> void:
	var size := root.get_visible_rect().size
	if Vector2i(size) != Vector2i(1920, 1080):
		print("MEMORY note: the window is %dx%d; the budget is for 1920x1080 (--resolution 1920x1080)" % [size.x, size.y])
	for i in 3:
		await process_frame
	_report("empty")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var world: Node = main.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	_where = "spawn"
	await _settle(world)
	_report("spawn")
	if _verbose:
		_breakdown()
	var player: Node3D = main.get_node("Player")
	for s: Array in SPOTS:
		_where = str(s[0])
		player.global_position = world.terrain.at(Vector2(s[1], s[2]), 0.5)
		await _settle(world)
		_report(_where)
	var level_name := _level.to_lower()
	print("MEMORY peak=%.0f MB (at %s: %s) on %s at %dx%d" % [_peak, _peak_at, _peak_split, level_name, size.x, size.y])
	if level_name == "low" and _peak > BUDGET_MB:
		print("MEMORY FAIL peak %.0f MB over the Low budget of %.0f MB (tools/memory_budget.gd)" % [_peak, BUDGET_MB])
		quit(1)
	elif level_name == "low":
		print("MEMORY within the Low budget of %.0f MB" % BUDGET_MB)
		quit(0)
	else:
		print("MEMORY (only Low has a budget)")
		quit(0)


## Wait until every chunk in range round the focus is in, and a few frames
## more for the streamed meshes to reach the graphics card.
func _settle(world: Node) -> void:
	for i in 10:
		await process_frame
	if world.has_method("wait_until_settled"):
		await world.wait_until_settled()
	for i in 10:
		await process_frame


# --verbose: what holds the memory.

var _seen := {} ## Resource -> true (each mesh and texture counted once)
var _groups := {} ## group -> {"meshes": bytes, "textures": bytes, "nodes": n}
var _big := [] ## [bytes, what, group]
var _skinned := 0 ## skinned mesh instances


func _breakdown() -> void:
	_seen.clear()
	_groups.clear()
	_big.clear()
	_node(root)
	var mesh_total := 0
	var tex_total := 0
	for g: String in _groups:
		mesh_total += int(_groups[g]["meshes"])
		tex_total += int(_groups[g]["textures"])
	var buf := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	var tex := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	print("MEMORY skinned mesh instances: %d" % _skinned)
	print("MEMORY found: meshes %.1f MB of %.1f, textures %.1f MB of %.1f (the rest is the renderer's own or drawn without a node)" % [
		mesh_total / 1048576.0, buf / 1048576.0, tex_total / 1048576.0, tex / 1048576.0])
	var keys := _groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(_groups[a]["meshes"]) + int(_groups[a]["textures"]) > int(_groups[b]["meshes"]) + int(_groups[b]["textures"]))
	for k: String in keys:
		var g: Dictionary = _groups[k]
		if int(g["meshes"]) + int(g["textures"]) < 256 * 1024:
			continue
		print("    %-56s meshes=%6.1f MB  textures=%6.1f MB  nodes=%d" % [k, int(g["meshes"]) / 1048576.0, int(g["textures"]) / 1048576.0, g["nodes"]])
	_big.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	print("MEMORY biggest single meshes and textures:")
	for b: Array in _big.slice(0, 25):
		print("    %6.1f MB  %s  (%s)" % [int(b[0]) / 1048576.0, b[1], b[2]])


func _group_of(n: Node) -> String:
	var parts := str(n.get_path()).trim_prefix("/root/").split("/")
	var re := RegEx.create_from_string("[_@]?-?\\d+")
	var out: PackedStringArray = []
	for p in parts.slice(0, 3):
		out.append(re.sub(p, "", true))
	return "/".join(out)


func _add(group: String, kind: String, bytes: int, what: String) -> void:
	var g: Dictionary = _groups.get(group, {"meshes": 0, "textures": 0, "nodes": 0})
	g[kind] = int(g[kind]) + bytes
	_groups[group] = g
	if bytes >= 512 * 1024:
		_big.append([bytes, what, group])


func _node(n: Node) -> void:
	var group := _group_of(n)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		_mesh(mi.mesh, group)
		# A skinned mesh gets its own copy of the vertices for each instance
		# drawn (the posed shape), on top of the shared mesh.
		if mi.mesh != null and mi.skeleton != NodePath() and mi.get_node_or_null(mi.skeleton) is Skeleton3D:
			var copy := 0
			for si in mi.mesh.get_surface_count():
				var sd: Dictionary = RenderingServer.mesh_get_surface(mi.mesh.get_rid(), si)
				if (sd.get("skin_data", PackedByteArray()) as PackedByteArray).size() > 0:
					copy += (sd.get("vertex_data", PackedByteArray()) as PackedByteArray).size()
			if copy > 0:
				_add(group, "meshes", copy, "posed copy of a skinned mesh")
				_skinned += 1
		for si in mi.get_surface_override_material_count():
			_res(mi.get_surface_override_material(si), group)
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null:
			_mesh(mm.mesh, group)
			var floats := (12 if mm.transform_format == MultiMesh.TRANSFORM_3D else 8) + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)
			_add(group, "meshes", mm.instance_count * floats * 4, "MultiMesh instances x%d" % mm.instance_count)
	if n is GeometryInstance3D:
		_res((n as GeometryInstance3D).material_override, group)
		_res((n as GeometryInstance3D).material_overlay, group)
	# Textures on UI and sprites, and anything else a node holds directly.
	for pr: Dictionary in n.get_property_list():
		if pr["type"] == TYPE_OBJECT and (pr["name"] as String).contains("texture"):
			var v: Variant = n.get(pr["name"])
			if v is Texture:
				_res(v, group)
	if n is Control:
		for sb_name: String in ["panel", "normal", "hover", "pressed"]:
			var sb := (n as Control).get_theme_stylebox(sb_name) if (n as Control).has_theme_stylebox(sb_name) else null
			if sb is StyleBoxTexture:
				_res((sb as StyleBoxTexture).texture, group)
	var g: Dictionary = _groups.get(group, {"meshes": 0, "textures": 0, "nodes": 0})
	g["nodes"] = int(g["nodes"]) + 1
	_groups[group] = g
	for c in n.get_children(true):
		_node(c)


func _mesh(mesh: Mesh, group: String) -> void:
	if mesh == null:
		return
	for si in mesh.get_surface_count():
		_res(mesh.surface_get_material(si), group)
	if _seen.has(mesh):
		return
	_seen[mesh] = true
	var bytes := 0
	for si in mesh.get_surface_count():
		var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), si)
		for k: String in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
			bytes += (sd.get(k, PackedByteArray()) as PackedByteArray).size()
		for l: Dictionary in sd.get("lods", []):
			bytes += (l.get("index_data", PackedByteArray()) as PackedByteArray).size()
	_add(group, "meshes", bytes, "mesh %s" % (mesh.resource_path if mesh.resource_path != "" else mesh.resource_name))


## A material's textures (and a texture itself), each counted once.
func _res(r: Resource, group: String) -> void:
	if r == null or _seen.has(r):
		return
	_seen[r] = true
	if r is Texture2D:
		var img := (r as Texture2D).get_image()
		if img != null:
			_add(group, "textures", img.get_data_size(), "texture %dx%d %s" % [img.get_width(), img.get_height(),
				r.resource_path if r.resource_path != "" else r.get_class()])
		return
	if r is TextureLayered:
		var tl := r as TextureLayered
		var img := tl.get_layer_data(0)
		if img != null:
			_add(group, "textures", img.get_data_size() * tl.get_layers(), "texture array %dx%dx%d %s" % [img.get_width(), img.get_height(), tl.get_layers(), r.resource_path])
		return
	if r is ShaderMaterial:
		var sm := r as ShaderMaterial
		if sm.shader != null:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var v: Variant = sm.get_shader_parameter(u["name"])
				if v is Resource:
					_res(v, group)
		_res(sm.next_pass, group)
	elif r is BaseMaterial3D:
		for pr: Dictionary in r.get_property_list():
			if pr["type"] == TYPE_OBJECT and (pr["name"] as String).ends_with("texture"):
				var v: Variant = r.get(pr["name"])
				if v is Resource:
					_res(v, group)
		_res((r as Material).next_pass, group)

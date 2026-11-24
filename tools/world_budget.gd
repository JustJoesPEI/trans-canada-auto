extends SceneTree
## Measures what the streamed town costs to draw, chunk by chunk, and checks
## it against the budgets (docs/world_art.md has the rules behind them):
##
##   godot --headless --path . --script res://tools/world_budget.gd [-- --verbose] [--at=x,z]
##
## Builds a few sample chunks (downtown, a residential street, the edge of
## town, or the one at --at) the way the streamer does: full detail with the
## close-up facades swapped in, and the distant version. For each it counts
## draw calls (one per surface of every visible mesh instance, MultiMeshes
## counted once), triangles up close (every LOD at its most detailed) and
## far away, triangles cast into shadows, how many different materials it
## uses, and which meshes break a rule (no automatic LODs, a material made
## for one mesh, a small thing drawn to any distance). --verbose breaks the
## counts down by what drew them.
##
## One "WORLD" line per chunk and version; "WORLD FAIL" lines and a non-zero
## exit code for anything over budget.

## Sample chunks: [name, chunk x, chunk z]. The busiest downtown blocks,
## the densest streets of houses in and out of downtown, and a far suburb.
const SAMPLES := [
	["downtown", 0, 0],
	["waterfront", -1, 1],
	["houses", 1, -1],
	["outer houses", 1, -5],
	["suburb", -7, -11],
]

## Per chunk. "calls" counts surfaces drawn (before culling, so a view
## draws fewer); "tris" every triangle at full detail; "far_tris" what's
## left from a few hundred metres (simplest LODs, past every visibility
## range); "shadow_tris" the triangles that can be drawn into the shadow
## map; "materials" different materials; "no_lods" meshes over LOD_MIN
## triangles without automatic LODs; "one_off" materials that copy one
## already made (the same look, not shared); "unbounded" small meshes
## drawn to any distance; build and facade times in ms on one core of the
## machine running it (the cloud build machines are slow; a PC is faster).
## Measured worst when the rules came in (docs/world_art.md): near calls
## 293, tris 831k, far_tris 54k, shadow 322k, materials 24, build 350 ms,
## facades 1,120 ms; far calls 10, tris 64k, far_tris 11k. The headroom is
## for the objects still to be placed.
const BUDGETS := {
	"near": {"calls": 400, "tris": 1200000, "far_tris": 90000, "shadow_tris": 450000, "materials": 32,
		"no_lods": 0, "one_off": 0, "unbounded": 0, "build_ms": 900, "detail_ms": 2500},
	"far": {"calls": 16, "tris": 100000, "far_tris": 25000, "shadow_tris": 0, "materials": 10,
		"no_lods": 0, "one_off": 0, "unbounded": 0, "build_ms": 600},
}
const LOD_MIN := 1000
## Layers laid one on another (the ground carved just under the streets,
## paint on the asphalt, parking stall lines) get no automatic LODs:
## simplifying one on its own would let it poke through or flicker against
## the next. They're stepped by the chunk's near and far versions instead
## (docs/world_art.md, W1).
const LAYERED := ["Ground", "Streets/", "StreetProps/ParkingStalls"]
## A mesh smaller than this (bounding box diagonal, m) is "small" and must
## have a visibility range (it's a pixel or two from a few hundred metres).
const SMALL := 6.0

var _fails := 0
var _verbose := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_verbose = args.has("verbose")
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var t0 := Time.get_ticks_msec()
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	RoadMesher.prepare(net, data)
	var terrain := Terrain.load_from(str(data.config.get("elevation")))
	RoadMesher.seat_bridges(net, terrain)
	RoadMesher.smooth_streets(net, terrain)
	Materials.get_shared()
	StreetProps.prepare()
	ChunkBuilder.coarse_mask = load(str(data.config.get("ground_mask"))) as Texture2D
	print("WORLD setup_ms=%d" % (Time.get_ticks_msec() - t0))
	var samples: Array = SAMPLES
	if args.has("at"):
		var at := str(args["at"]).split_floats(",")
		samples = [["at", floori(at[0] / data.chunk_size), floori(at[1] / data.chunk_size)]]
	for s: Array in samples:
		var cx := int(s[1])
		var cz := int(s[2])
		for lod: bool in [false, true]:
			var t := Time.get_ticks_usec()
			var node := ChunkBuilder.build(data, net, terrain, cx, cz, lod)
			var build_ms := (Time.get_ticks_usec() - t) / 1000.0
			var detail_ms := 0.0
			if not lod and BuildingGenerator.facade_relief:
				# Swap the close-up facades in, as the streamer does.
				t = Time.get_ticks_usec()
				var tiles := ChunkBuilder.build_detail(data, net, terrain, cx, cz)
				detail_ms = (Time.get_ticks_usec() - t) / 1000.0
				var b := node.get_node_or_null("Buildings")
				if b != null:
					for c in b.get_children():
						if c is MeshInstance3D and tiles.has(str(c.name)):
							(c as MeshInstance3D).mesh = tiles[str(c.name)]
			var r := _measure(node, lod)
			r["build_ms"] = build_ms
			r["detail_ms"] = detail_ms
			_report("%s (%d,%d)" % [s[0], cx, cz], "far" if lod else "near", r)
			node.free()
	if _fails > 0:
		print("WORLD FAIL %d over budget (docs/world_art.md)" % _fails)
		quit(1)
	else:
		print("WORLD all within budget")
		quit(0)


func _measure(node: Node, lod: bool) -> Dictionary:
	var r := {"calls": 0, "tris": 0, "far_tris": 0, "shadow_tris": 0, "no_lods": 0, "one_off": 0, "unbounded": 0,
		"materials": 0, "groups": {}, "offenders": []}
	var mat_users := {} # material -> {mesh -> true}
	_walk(node, node, r, mat_users)
	r["materials"] = mat_users.size()
	for m: Material in mat_users:
		# The same look made again as a new material (per chunk or per
		# prop) instead of shared: each one is its own pipeline state and
		# breaks batching.
		var sig := _mat_sig(m)
		if not _mat_seen.has(sig):
			_mat_seen[sig] = m
		elif _mat_seen[sig] != m:
			r["one_off"] += 1
			(r["offenders"] as Array).append("duplicate material %s" % _mat_name(m))
	return r


var _mat_seen := {} ## look -> the first material seen with it


static func _mat_sig(m: Material) -> String:
	if m is ShaderMaterial:
		var sm := m as ShaderMaterial
		var sig := "shader:%s" % (sm.shader.resource_path if sm.shader != null else "")
		if sm.shader != null:
			for u: Dictionary in sm.shader.get_shader_uniform_list():
				var v: Variant = sm.get_shader_parameter(u["name"])
				sig += "|%s=%s" % [u["name"], v.resource_path if v is Resource else str(v)]
		return sig
	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		return "std:%s|%s|%.2f|%.2f|%s|%s|%d|%d" % [m.get_class(), bm.albedo_color.to_html(), bm.roughness, bm.metallic,
			bm.albedo_texture.resource_path if bm.albedo_texture != null else str(bm.albedo_texture),
			bm.emission.to_html() if bm.emission_enabled else "", bm.transparency, bm.cull_mode]
	return "%s:%d" % [m.get_class(), m.get_instance_id()]


func _walk(n: Node, top: Node, r: Dictionary, mat_users: Dictionary) -> void:
	for c in n.get_children():
		_walk(c, top, r, mat_users)
	if not (n is GeometryInstance3D) or not (n as Node3D).visible:
		return
	var gi := n as GeometryInstance3D
	var mesh: Mesh = null
	var count := 1
	if n is MeshInstance3D:
		mesh = (n as MeshInstance3D).mesh
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if mesh == null or count == 0:
		return
	var group := _group(n, top)
	var g: Dictionary = (r["groups"] as Dictionary).get(group, {"calls": 0, "tris": 0, "shadow_tris": 0, "nodes": 0})
	var tris := 0
	var low := 0
	var has_lods := true
	for si in mesh.get_surface_count():
		var t := _surface_tris(mesh, si)
		tris += t
		var lc := _lod_count(mesh, si)
		low += t if lc == 0 else _lod_tris(mesh, si, t)
		if t > LOD_MIN and lc == 0:
			has_lods = false
		var m := gi.material_override
		if m == null and n is MeshInstance3D:
			m = (n as MeshInstance3D).get_surface_override_material(si)
		if m == null:
			m = mesh.surface_get_material(si)
		if m != null:
			if not mat_users.has(m):
				mat_users[m] = {}
			mat_users[m][mesh] = true
	var calls := mesh.get_surface_count()
	r["calls"] += calls
	r["tris"] += tris * count
	var far := gi.visibility_range_end <= 0.0 or gi.visibility_range_end > 400.0
	if far:
		r["far_tris"] += low * count
	if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		r["shadow_tris"] += tris * count
		g["shadow_tris"] += tris * count
	var layered := false
	for l: String in LAYERED:
		if group.begins_with(l):
			layered = true
	if not has_lods and not layered and not (n is MultiMeshInstance3D and tris * count < LOD_MIN):
		r["no_lods"] += 1
		(r["offenders"] as Array).append("no LODs: %s (%d tris)" % [group, tris])
	var aabb := mesh.get_aabb()
	if aabb.size.length() < SMALL and gi.visibility_range_end <= 0.0 and not (n is MultiMeshInstance3D):
		r["unbounded"] += 1
		(r["offenders"] as Array).append("drawn to any distance: %s (%.1f m)" % [group, aabb.size.length()])
	g["calls"] += calls
	g["tris"] += tris * count
	g["nodes"] += 1
	r["groups"][group] = g


## Which part of the chunk drew it: the node path under the chunk root with
## numbers stripped ("StreetProps/Tree", "Buildings/Buildings").
func _group(n: Node, top: Node) -> String:
	var parts: PackedStringArray = []
	var p := n
	while p != null and p != top:
		parts.insert(0, _strip(str(p.name)))
		p = p.get_parent()
	if parts.size() > 3:
		parts = parts.slice(0, 3)
	return "/".join(parts)


static func _strip(s: String) -> String:
	var re := RegEx.create_from_string("[_@]?-?\\d+")
	return re.sub(s, "", true)


static func _surface_tris(mesh: Mesh, si: int) -> int:
	var arrays := mesh.surface_get_arrays(si)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.size() > 0:
		return idx.size() / 3
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


static func _lod_count(mesh: Mesh, si: int) -> int:
	var sd: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), si)
	return (sd.get("lods", []) as Array).size()


static func _lod_tris(mesh: Mesh, si: int, full: int) -> int:
	var rid := mesh.get_rid()
	var sd: Dictionary = RenderingServer.mesh_get_surface(rid, si)
	var lods: Array = sd.get("lods", [])
	if lods.is_empty():
		return full
	var last: Dictionary = lods[-1]
	var bytes: PackedByteArray = last.get("index_data", PackedByteArray())
	var per := 2 if int(sd.get("vertex_count", 0)) <= 65535 else 4
	return bytes.size() / per / 3


static func _mat_name(m: Material) -> String:
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		return (m as ShaderMaterial).shader.resource_path.get_file()
	if m is StandardMaterial3D:
		return "Standard %s" % (m as StandardMaterial3D).albedo_color.to_html(false)
	return m.get_class()


func _report(label: String, kind: String, r: Dictionary) -> void:
	var b: Dictionary = BUDGETS[kind]
	print("WORLD %-22s %-4s calls=%d tris=%d far_tris=%d shadow_tris=%d materials=%d no_lods=%d one_off=%d unbounded=%d build_ms=%.0f detail_ms=%.0f" % [
		label, kind, r["calls"], r["tris"], r["far_tris"], r["shadow_tris"], r["materials"], r["no_lods"], r["one_off"], r["unbounded"], r["build_ms"], r["detail_ms"]])
	for key: String in b:
		if int(r[key]) > int(b[key]):
			_fails += 1
			print("WORLD FAIL %s %s: %s %d over budget %d" % [label, kind, key, r[key], b[key]])
	if _verbose:
		var groups: Dictionary = r["groups"]
		var keys := groups.keys()
		keys.sort_custom(func(a: String, c: String) -> bool: return groups[a]["tris"] > groups[c]["tris"])
		for k: String in keys:
			var g: Dictionary = groups[k]
			print("    %-48s nodes=%4d calls=%4d tris=%8d shadow=%8d" % [k, g["nodes"], g["calls"], g["tris"], g["shadow_tris"]])
		var seen := {}
		for o: String in r["offenders"]:
			seen[o] = int(seen.get(o, 0)) + 1
		for o: String in seen:
			print("    ! %s%s" % [o, "" if seen[o] == 1 else " x%d" % seen[o]])

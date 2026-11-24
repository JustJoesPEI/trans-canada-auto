extends SceneTree
## Measures every vehicle and load model for drawing cost and checks it
## against the budgets (docs/models.md has the rules behind them):
##
##   godot --headless --path . --script res://tools/model_budget.gd [-- --verbose]
##
## For each model: draw calls (one per mesh surface on each visible mesh
## instance), triangles drawn up close and far away (past every
## visibility range), triangles drawn into the shadow map, and how long it
## takes to build (first time, and again once its meshes are cached).
## One "BUDGET" line per model; "BUDGET FAIL" lines and a non-zero exit code
## for anything over budget.

const NEAR := 5.0 ## m: "up close"
const LOD_MIN := 1000 ## a mesh with more triangles than this must have automatic LODs
const FAR := 200.0 ## m: "far away" for the far triangle count

## Budgets: draw calls up close, triangles up close, triangles far away,
## shadow-casting triangles up close, milliseconds to build again (cached).
const BUDGETS := {
	"car": {"no_lods": 0, "calls": 40, "tris": 70000, "far_tris": 20000, "shadow_tris": 45000, "rebuild_ms": 15.0},
	"truck": {"no_lods": 0, "calls": 60, "tris": 110000, "far_tris": 30000, "shadow_tris": 60000, "rebuild_ms": 15.0},
	# Parked cars are drawn by the dozen through MultiMeshes, so their
	# simplest LOD matters most.
	"parked": {"no_lods": 0, "calls": 2, "tris": 10000, "low_tris": 2500},
	"cargo": {"no_lods": 0, "calls": 4, "tris": 6000, "rebuild_ms": 3.0},
	# Held in the hands (the paintball marker): small, one surface.
	"held": {"calls": 1, "tris": 1000, "rebuild_ms": 0.5},
	# Police props (scripts/police/PoliceProps): the OUT vest, paint strips,
	# the harvester roadblock, the Paint Tank's cannon, the impound machine.
	"prop": {"no_lods": 0, "calls": 3, "tris": 12000, "rebuild_ms": 0.5},
}

## Fleet vehicles measured in their livery too (the light bar, the band,
## the crest and the words are extra geometry and draw calls): [model,
## livery, budget]. The Paint Tank is a seven-tonne armoured truck, measured
## with its roof cannon on, against the truck budget.
const FLEETS := [["jaunt", "cps", "car"], ["tahoma", "fip", "car"], ["paint_tank", "fip_tactical", "truck"]]

var _fails := 0
var _verbose := false


func _initialize() -> void:
	_verbose = "--verbose" in OS.get_cmdline_user_args()
	_run.call_deferred()


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var ids: Array = CarModels.MODELS.keys() + TruckModels.MODELS.keys()
	for id: String in ids:
		var m := CarModels.get_model(id)
		var truck := str(m["shape"].get("builder", "car")) == "truck"
		var times: Array[float] = []
		var car: Car
		for i in 2:
			var t0 := Time.get_ticks_usec()
			car = Car.new()
			car.model_id = id
			car.paint = Color.html(m["colours"][0])
			root.add_child(car)
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			if i == 0:
				car.free()
		car.freeze = true
		var r := _measure(car)
		r["ms"] = times[0]
		r["rebuild_ms"] = times[1]
		_report(id, "truck" if truck else "car", r)
		car.free()
		if not truck:
			var t1 := Time.get_ticks_usec()
			var pk := CarBuilder.new(m["shape"], Color.WHITE).make_parked()
			var lt := _lowest_lod_tris(pk)
			var pr := {"calls": pk.get_surface_count(), "tris": _tris(pk), "low_tris": lt, "no_lods": 1 if lt < 0 else 0, "ms": (Time.get_ticks_usec() - t1) / 1000.0}
			_report(id + " (parked)", "parked", pr)
	for fl: Array in FLEETS:
		var times3: Array[float] = []
		var pc: Car
		for i in 2:
			var t0 := Time.get_ticks_usec()
			pc = Car.new()
			pc.model_id = fl[0]
			pc.livery = fl[1]
			pc.unit = 12
			pc.paint = Color.html(str(CarModels.LIVERIES[fl[1]]["colour"]))
			root.add_child(pc)
			if fl[0] == "paint_tank":
				pc.add_child(PaintTank.new())
			times3.append((Time.get_ticks_usec() - t0) / 1000.0)
			if i == 0:
				pc.free()
		pc.freeze = true
		var fr := _measure(pc)
		fr["ms"] = times3[0]
		fr["rebuild_ms"] = times3[1]
		_report("%s (%s)" % [fl[0], fl[1]], fl[2], fr)
		pc.free()
	for pname: String in PoliceProps.budget_meshes():
		var t4 := Time.get_ticks_usec()
		var pm: ArrayMesh = PoliceProps.budget_meshes()[pname]
		var again := (Time.get_ticks_usec() - t4) / 1000.0
		var lt := _lowest_lod_tris(pm)
		_report(pname, "prop", {"calls": pm.get_surface_count(), "tris": _tris(pm), "no_lods": 1 if lt < 0 and _tris(pm) > LOD_MIN else 0, "rebuild_ms": again})
	for kind: String in Cargo.KINDS:
		var times2: Array[float] = []
		var c: Cargo
		for i in 2:
			var t0 := Time.get_ticks_usec()
			c = Cargo.new()
			c.kind = kind
			root.add_child(c)
			times2.append((Time.get_ticks_usec() - t0) / 1000.0)
			if i == 0:
				c.free()
		c.freeze = true
		var cr := _measure(c)
		cr["ms"] = times2[0]
		cr["rebuild_ms"] = times2[1]
		_report(kind, "cargo", cr)
		c.free()
	var t2 := Time.get_ticks_usec()
	var marker := MarkerModel.mesh()
	var ms := (Time.get_ticks_usec() - t2) / 1000.0
	var t3 := Time.get_ticks_usec()
	MarkerModel.mesh()
	_report("paintball marker", "held", {"calls": marker.get_surface_count(), "tris": _tris(marker), "ms": ms, "rebuild_ms": (Time.get_ticks_usec() - t3) / 1000.0})
	print("BUDGET %s" % ("all within budget" if _fails == 0 else "%d over budget" % _fails))
	quit(1 if _fails > 0 else 0)


## Draw calls and triangles of everything visible under a node.
func _measure(n: Node) -> Dictionary:
	var calls := 0
	var tris := 0
	var far_tris := 0
	var far_calls := 0
	var shadow_tris := 0
	var meshes := {}
	var no_lods := 0
	var low_tris := 0
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not _visible(mi):
			continue
		var t := _tris(mi.mesh)
		var sc := mi.mesh.get_surface_count()
		meshes[mi.mesh.get_rid()] = true
		var lt := _lowest_lod_tris(mi.mesh)
		if lt < 0 and t > LOD_MIN:
			no_lods += 1
		var begin := mi.visibility_range_begin
		var end := mi.visibility_range_end
		if begin <= NEAR and (end <= 0.0 or end > NEAR):
			calls += sc
			tris += t
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				for si in sc:
					var mat := mi.get_active_material(si)
					var see_through := mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
					if not see_through:
						shadow_tris += _surface_tris(mi.mesh, si)
		if begin <= FAR and (end <= 0.0 or end > FAR):
			far_tris += t
			far_calls += sc
			low_tris += lt if lt >= 0 else t
	return {"calls": calls, "tris": tris, "far_tris": far_tris, "far_calls": far_calls, "shadow_tris": shadow_tris, "meshes": meshes.size(), "no_lods": no_lods, "low_tris": low_tris}


func _visible(n: Node3D) -> bool:
	while n != null:
		if not n.visible:
			return false
		n = n.get_parent() as Node3D
	return true


## Triangles in the simplest automatic LOD of every surface, or -1 if the
## mesh has none.
static func _lowest_lod_tris(mesh: Mesh) -> int:
	var t := 0
	var any := false
	for si in mesh.get_surface_count():
		var surf := RenderingServer.mesh_get_surface(mesh.get_rid(), si)
		var lods: Array = surf.get("lods", [])
		if lods.is_empty():
			t += _surface_tris(mesh, si)
			continue
		any = true
		var last: Dictionary = lods[lods.size() - 1]
		var bytes: PackedByteArray = last["index_data"]
		var wide := int(surf.get("vertex_count", 0)) > 65535 # 32-bit indices past that
		t += bytes.size() / (4 if wide else 2) / 3
	return t if any else -1


static func _tris(mesh: Mesh) -> int:
	var t := 0
	for si in mesh.get_surface_count():
		t += _surface_tris(mesh, si)
	return t


static func _surface_tris(mesh: Mesh, si: int) -> int:
	var a := mesh.surface_get_arrays(si)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.size() > 0:
		return idx.size() / 3
	return (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func _report(id: String, kind: String, r: Dictionary) -> void:
	var b: Dictionary = BUDGETS[kind]
	var over: Array[String] = []
	for key: String in b:
		if r.has(key) and float(r[key]) > float(b[key]):
			over.append("%s %s > %s" % [key, str(r[key]), str(b[key])])
	var line := "%-26s calls %3d  tris %6d" % [id, r["calls"], r["tris"]]
	if r.has("far_tris"):
		line += "  far %6d (%d calls, simplest LODs %d)  shadow %6d  meshes %d" % [r["far_tris"], r["far_calls"], r["low_tris"], r["shadow_tris"], r["meshes"]]
	if not r.has("far_tris") and r.has("low_tris"):
		line += "  simplest LOD %d" % r["low_tris"]
	if r.has("ms"):
		line += "  build %.1f ms" % r["ms"]
	if r.has("rebuild_ms"):
		line += ", again %.1f ms" % r["rebuild_ms"]
	if over.is_empty():
		print("BUDGET " + line)
	else:
		_fails += 1
		print("BUDGET FAIL " + line + "  [" + ", ".join(over) + "]")

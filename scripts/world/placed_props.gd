class_name PlacedProps
extends RefCounted
## Street furniture placed by hand with the map editor (tools/map_editor.html):
## points of type "prop=<name>" in a chunk, each at its spot and turned to
## its "direction" tag (compass degrees, clockwise from north: the way the
## front of a bench faces, the way a street light's arm reaches). Built by
## StreetProps in full-detail chunks; one MultiMesh per kind, all solid.
##
## Trees, stop signs and traffic signals placed in the editor aren't props:
## they're ordinary natural=tree, highway=stop and highway=traffic_signals
## points and are built with the mapped ones.

## Every kind the editor offers: mesh, collision box half-size and centre
## height, and a turn (degrees) to add so the mesh's front lines up with
## "direction".
const KINDS := ["bench", "picnic_table", "waste_basket", "post_box", "fire_hydrant",
	"heritage_lamp", "street_light", "bollard", "planter", "boulder", "jersey_barrier", "traffic_cone",
	"drive_thru_menu", "drive_thru_speaker", "height_bar"]
## Props are drawn this close (metres); further off they're specks.
const DRAW_DISTANCE := 220.0

static var _ready_shared := false
static var _meshes: Dictionary = {} ## kind -> Mesh
static var _shapes: Dictionary = {} ## kind -> [Shape3D, centre height]
static var _turn: Dictionary = {} ## kind -> extra yaw in degrees

var props: StreetProps


static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	StreetClutter.prepare()
	var mats := Materials.get_shared()
	_meshes["bench"] = _bench()
	_meshes["picnic_table"] = _picnic_table()
	_meshes["waste_basket"] = _bin()
	_meshes["post_box"] = _post_box()
	_meshes["fire_hydrant"] = StreetClutter._hydrant_mesh
	_meshes["heritage_lamp"] = StreetProps._heritage_lamp if StreetProps._heritage_lamp != null else StreetProps._lamp_mesh(mats)
	_meshes["street_light"] = StreetProps._street_light if StreetProps._street_light != null else StreetProps._street_light_mesh(mats)
	_meshes["bollard"] = _bollard()
	_meshes["planter"] = _planter()
	_meshes["boulder"] = StreetProps._rock if StreetProps._rock != null else StreetProps._rock_mesh(mats)
	_meshes["jersey_barrier"] = _jersey_barrier()
	_meshes["traffic_cone"] = _cone()
	_meshes["drive_thru_menu"] = _menu_board(mats)
	_meshes["drive_thru_speaker"] = _speaker_post(mats)
	_meshes["height_bar"] = _height_bar()
	_shape("bench", Vector3(0.85, 0.45, 0.3), 0.45)
	_shape("picnic_table", Vector3(0.95, 0.38, 0.8), 0.38)
	_shape("waste_basket", Vector3(0.28, 0.5, 0.28), 0.5)
	_shape("post_box", Vector3(0.3, 0.62, 0.3), 0.62)
	_shape("fire_hydrant", Vector3(0.17, 0.43, 0.17), 0.43)
	_shape("heritage_lamp", Vector3(0.12, 2.1, 0.12), 2.1)
	_shape("street_light", Vector3(0.14, 4.0, 0.14), 4.0)
	_shape("bollard", Vector3(0.1, 0.5, 0.1), 0.5)
	_shape("planter", Vector3(0.6, 0.35, 0.6), 0.35)
	_shape("boulder", Vector3(0.5, 0.35, 0.5), 0.2)
	_shape("jersey_barrier", Vector3(1.5, 0.41, 0.3), 0.41)
	_shape("traffic_cone", Vector3(0.15, 0.35, 0.15), 0.35)
	_shape("drive_thru_menu", Vector3(1.2, 1.1, 0.2), 1.1)
	_shape("drive_thru_speaker", Vector3(0.35, 0.8, 0.3), 0.8)
	_shape("height_bar", Vector3(0.1, 1.5, 0.1), 1.5)
	# The street light's arm runs along local X.
	_turn["street_light"] = -90.0


static func _shape(kind: String, half: Vector3, y: float) -> void:
	var box := BoxShape3D.new()
	box.size = half * 2.0
	_shapes[kind] = [box, y]


func _init(owner: StreetProps) -> void:
	props = owner


func build(root: Node3D) -> void:
	var by_kind: Dictionary = {}
	var body := StaticBody3D.new()
	body.name = "PlacedProps"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for p in props.chunk.points:
		if not p.type.begins_with("prop="):
			continue
		var kind := p.type.substr(5)
		if not _meshes.has(kind):
			continue
		var yaw := -deg_to_rad(str(p.tags.get("direction", "0")).to_float() + float(_turn.get(kind, 0.0)))
		var at := props.terrain.at(p.pos, 0.0)
		var lift := str(p.tags.get("lift", "0")).to_float()
		var xf := Transform3D(Basis(Vector3.UP, yaw), at + Vector3.UP * lift)
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(xf)
		# The clearance bar's two posts are solid; the lane between is open.
		var offsets: Array = [Vector3(-1.9, 0, 0), Vector3(1.9, 0, 0)] if kind == "height_bar" else [Vector3.ZERO]
		for off: Vector3 in offsets:
			var cs := CollisionShape3D.new()
			cs.shape = _shapes[kind][0]
			cs.transform = Transform3D(xf.basis, xf * off + Vector3.UP * float(_shapes[kind][1]))
			body.add_child(cs)
	if by_kind.is_empty():
		body.free()
		return
	for kind: String in by_kind:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Placed_" + kind
		mmi.multimesh = mm
		mmi.visibility_range_end = DRAW_DISTANCE
		root.add_child(mmi)
	root.add_child(body)


# --- meshes (front faces -Z, standing on y = 0) ---------------------------------------------

static func _kit() -> MeshKit:
	var kit := MeshKit.new()
	kit.use_color = true
	return kit


static func _commit(kit: MeshKit, roughness := 0.7) -> ArrayMesh:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = roughness
	return kit.commit(null, mat)


static func _col(kit: MeshKit, c: Color) -> void:
	kit.color = c.srgb_to_linear()


## Box between two corners.
static func _box(kit: MeshKit, lo: Vector3, hi: Vector3) -> void:
	StreetClutter._cube(kit, (lo + hi) * 0.5, (hi - lo) * 0.5)


## A park bench: three wooden seat slats and two back slats on black iron ends.
static func _bench() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.08, 0.08, 0.08))
	for x: float in [-0.7, 0.7]:
		_box(kit, Vector3(x - 0.03, 0.0, -0.22), Vector3(x + 0.03, 0.44, -0.16))
		_box(kit, Vector3(x - 0.03, 0.0, 0.16), Vector3(x + 0.03, 0.85, 0.22))
		_box(kit, Vector3(x - 0.03, 0.38, -0.22), Vector3(x + 0.03, 0.42, 0.22))
	_col(kit, Color(0.5, 0.33, 0.18))
	for k in 3:
		var z := -0.2 + k * 0.13
		_box(kit, Vector3(-0.85, 0.42, z), Vector3(0.85, 0.46, z + 0.1))
	for k in 2:
		var y := 0.55 + k * 0.16
		_box(kit, Vector3(-0.85, y, 0.2), Vector3(0.85, y + 0.11, 0.24))
	return _commit(kit)


## A picnic table: top and two benches on A-frame legs.
static func _picnic_table() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.55, 0.4, 0.25))
	_box(kit, Vector3(-0.95, 0.72, -0.38), Vector3(0.95, 0.77, 0.38))
	for z: float in [-0.75, 0.55]:
		_box(kit, Vector3(-0.95, 0.43, z), Vector3(0.95, 0.47, z + 0.2))
	for x: float in [-0.7, 0.7]:
		_box(kit, Vector3(x - 0.04, 0.0, -0.75), Vector3(x + 0.04, 0.43, -0.67))
		_box(kit, Vector3(x - 0.04, 0.0, 0.67), Vector3(x + 0.04, 0.43, 0.75))
		_box(kit, Vector3(x - 0.04, 0.4, -0.75), Vector3(x + 0.04, 0.45, 0.75))
		_box(kit, Vector3(x - 0.04, 0.0, -0.05), Vector3(x + 0.04, 0.72, 0.05))
	return _commit(kit, 0.9)


## A dark green litter bin with a black lid.
static func _bin() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.1, 0.25, 0.15))
	StreetProps._lathe(kit, [[0.0, 0.0], [0.24, 0.0], [0.27, 0.9], [0.0, 0.9]], 12)
	_col(kit, Color(0.06, 0.06, 0.06))
	StreetProps._lathe(kit, [[0.0, 0.9], [0.29, 0.9], [0.29, 0.96], [0.18, 1.0], [0.0, 1.0]], 12)
	return _commit(kit, 0.5)


## A red street letter box with a rounded top and a slot facing front.
static func _post_box() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.72, 0.07, 0.06))
	_box(kit, Vector3(-0.28, 0.12, -0.25), Vector3(0.28, 1.05, 0.25))
	StreetProps._lathe(kit, [[0.0, 1.05], [0.3, 1.05], [0.26, 1.16], [0.15, 1.23], [0.0, 1.25]], 12)
	_col(kit, Color(0.15, 0.15, 0.15))
	_box(kit, Vector3(-0.2, 0.0, -0.18), Vector3(0.2, 0.12, 0.18))
	_box(kit, Vector3(-0.16, 0.86, -0.27), Vector3(0.16, 0.9, -0.25))
	return _commit(kit, 0.45)


## A black steel bollard with a yellow reflective band.
static func _bollard() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.07, 0.07, 0.07))
	StreetProps._lathe(kit, [[0.0, 0.0], [0.09, 0.0], [0.09, 0.78], [0.08, 0.84], [0.05, 0.9], [0.0, 0.92]], 10)
	_col(kit, Color(0.9, 0.75, 0.1))
	StreetProps._lathe(kit, [[0.0921, 0.62], [0.0921, 0.7]], 10)
	return _commit(kit, 0.4)


## A square concrete planter with a low shrub.
static func _planter() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.62, 0.6, 0.56))
	_box(kit, Vector3(-0.6, 0.0, -0.6), Vector3(0.6, 0.6, 0.6))
	_col(kit, Color(0.2, 0.34, 0.14))
	StreetProps._lathe(kit, [[0.0, 0.6], [0.5, 0.6], [0.55, 0.8], [0.42, 1.05], [0.2, 1.15], [0.0, 1.17]], 9)
	return _commit(kit, 0.9)


## A concrete jersey barrier, 3 m long along local X.
static func _jersey_barrier() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.7, 0.69, 0.66))
	var prof := [Vector2(-0.3, 0.0), Vector2(0.3, 0.0), Vector2(0.28, 0.08), Vector2(0.2, 0.25), Vector2(0.08, 0.82), Vector2(-0.08, 0.82), Vector2(-0.2, 0.25), Vector2(-0.28, 0.08)]
	for i in prof.size():
		var a: Vector2 = prof[i]
		var b: Vector2 = prof[(i + 1) % prof.size()]
		var mid := (a + b) * 0.5 - Vector2(0.0, 0.35)
		var nz := b.y - a.y
		var ny := -(b.x - a.x)
		if nz * mid.x + ny * mid.y < 0.0:
			nz = -nz
			ny = -ny
		var n := Vector3(0.0, ny, nz).normalized()
		kit.quad(Vector3(-1.5, a.y, a.x), Vector3(1.5, a.y, a.x), Vector3(1.5, b.y, b.x), Vector3(-1.5, b.y, b.x), n)
	for x: float in [-1.5, 1.5]:
		for i in range(1, prof.size() - 1):
			var p0: Vector2 = prof[0]
			var p1: Vector2 = prof[i]
			var p2: Vector2 = prof[i + 1]
			kit.tri(Vector3(x, p0.y, p0.x), Vector3(x, p1.y, p1.x), Vector3(x, p2.y, p2.x), Vector3(signf(x), 0, 0))
	return _commit(kit, 0.95)


## An orange traffic cone with a white band.
static func _cone() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.1, 0.1, 0.1))
	_box(kit, Vector3(-0.19, 0.0, -0.19), Vector3(0.19, 0.03, 0.19))
	_col(kit, Color(0.95, 0.35, 0.05))
	StreetProps._lathe(kit, [[0.0, 0.03], [0.15, 0.03], [0.1, 0.35], [0.0, 0.35]], 12)
	_col(kit, Color(0.95, 0.95, 0.95))
	StreetProps._lathe(kit, [[0.101, 0.35], [0.07, 0.5], [0.0, 0.5]], 12)
	_col(kit, Color(0.95, 0.35, 0.05))
	StreetProps._lathe(kit, [[0.071, 0.5], [0.04, 0.7], [0.0, 0.7]], 12)
	return _commit(kit, 0.6)


## A drive-thru menu board: a dark cabinet on two posts with a lit face
## toward the driver (front, -Z) and a small topper.
static func _menu_board(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.12, 0.12, 0.13))
	for x: float in [-0.8, 0.8]:
		_box(kit, Vector3(x - 0.06, 0.0, -0.06), Vector3(x + 0.06, 0.7, 0.06))
	_box(kit, Vector3(-1.2, 0.7, -0.15), Vector3(1.2, 2.25, 0.15))
	_col(kit, Color(0.6, 0.1, 0.08))
	_box(kit, Vector3(-1.2, 2.25, -0.15), Vector3(1.2, 2.45, 0.15))
	var mesh := _commit(kit, 0.5)
	var face := MeshKit.new()
	face.quad(Vector3(-1.1, 0.8, -0.16), Vector3(1.1, 0.8, -0.16), Vector3(1.1, 2.15, -0.16), Vector3(-1.1, 2.15, -0.16), Vector3(0, 0, -1))
	face.commit(mesh, mats.glow(Color(0.95, 0.9, 0.78), 1.2))
	return mesh


## A drive-thru order post: a pedestal with the speaker box at window
## height and a little canopy, the grille toward the driver (front, -Z).
static func _speaker_post(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.15, 0.15, 0.16))
	_box(kit, Vector3(-0.08, 0.0, -0.08), Vector3(0.08, 1.05, 0.08))
	_box(kit, Vector3(-0.28, 1.05, -0.2), Vector3(0.28, 1.5, 0.2))
	_col(kit, Color(0.6, 0.1, 0.08))
	_box(kit, Vector3(-0.35, 1.5, -0.3), Vector3(0.35, 1.58, 0.25))
	_col(kit, Color(0.05, 0.05, 0.05))
	_box(kit, Vector3(-0.15, 1.2, -0.22), Vector3(0.15, 1.38, -0.2))
	var mesh := _commit(kit, 0.5)
	var lit := MeshKit.new()
	lit.quad(Vector3(-0.2, 1.4, -0.205), Vector3(0.2, 1.4, -0.205), Vector3(0.2, 1.46, -0.205), Vector3(-0.2, 1.46, -0.205), Vector3(0, 0, -1))
	lit.commit(mesh, mats.glow(Color(0.4, 0.8, 1.0), 1.0))
	return mesh


## A clearance bar over a drive-thru lane: two posts 3.8 m apart along local
## X with a yellow and black striped bar at 2.7 m. Its "direction" is the
## way cars drive under it.
static func _height_bar() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.2, 0.2, 0.22))
	for x: float in [-1.9, 1.9]:
		_box(kit, Vector3(x - 0.08, 0.0, -0.08), Vector3(x + 0.08, 3.0, 0.08))
	for k in 12:
		_col(kit, Color(0.95, 0.78, 0.05) if k % 2 == 0 else Color(0.06, 0.06, 0.06))
		var x0 := -1.8 + k * 0.3
		_box(kit, Vector3(x0, 2.6, -0.07), Vector3(x0 + 0.3, 2.8, 0.07))
	return _commit(kit, 0.6)

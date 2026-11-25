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
	"drive_thru_menu", "drive_thru_speaker", "height_bar",
	"dumpster", "propane_cage", "ice_machine", "transformer", "loading_bumper",
	"bus_shelter", "bike_rack", "newspaper_box", "community_mailbox", "mailbox", "utility_pole",
	"gas_pump", "ev_charger", "atm", "cart_corral", "lot_light",
	"playground", "swing_set", "flagpole", "fire_pit", "shed", "trampoline", "lawn_chair",
	"car_wash", "tyre_stack", "oil_drums"]
## Props are drawn this close (metres); further off they're specks.
const DRAW_DISTANCE := 220.0
## A car wash is building-sized: drawn as far as the full-detail chunks it's
## built in reach (Graphics' detail radius on High).
const BUILDING_DISTANCE := 330.0

static var _ready_shared := false
static var _meshes: Dictionary = {} ## kind -> Mesh
static var _shapes: Dictionary = {} ## kind -> Array of [BoxShape3D, local centre]
static var _turn: Dictionary = {} ## kind -> extra yaw in degrees
static var _reach: Dictionary = {} ## kind -> draw distance (m), by its size

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
	_shape("height_bar", Vector3(0.1, 1.5, 0.1), 1.5, -1.9)
	_shape("height_bar", Vector3(0.1, 1.5, 0.1), 1.5, 1.9)
	_more(mats)
	# The drive-through car wash (scripts/wanted/car_wash_model.gd): solid
	# walls, open ends. Driving through it is CarWashes' job.
	_meshes["car_wash"] = CarWashModel.mesh()
	for w: Array in CarWashModel.walls():
		var at: Vector3 = w[1]
		_shape("car_wash", w[0], at.y, at.x, at.z)
	# The street light's arm runs along local X.
	_turn["street_light"] = -90.0
	# Every prop mesh is built once and drawn by the dozen: indexed, with
	# automatic LODs (docs/world_art.md, rule W1). The ones borrowed from
	# StreetProps and StreetClutter are finished there already.
	for kind: String in _meshes:
		var m: Mesh = _meshes[kind]
		if m is ArrayMesh and not _finished(m as ArrayMesh):
			_meshes[kind] = ModelLod.finish(m as ArrayMesh)
	for kind: String in _meshes:
		_reach[kind] = WorldLod.draw_distance(_meshes[kind], DRAW_DISTANCE)
	_reach["car_wash"] = WorldLod.draw_distance(_meshes["car_wash"], BUILDING_DISTANCE)


## True if the mesh already has automatic LODs.
static func _finished(m: ArrayMesh) -> bool:
	return not (RenderingServer.mesh_get_surface(m.get_rid(), 0).get("lods", []) as Array).is_empty() \
		or m.get_surface_count() == 0


static func _shape(kind: String, half: Vector3, y: float, x := 0.0, z := 0.0) -> void:
	var box := BoxShape3D.new()
	box.size = half * 2.0
	if not _shapes.has(kind):
		_shapes[kind] = []
	_shapes[kind].append([box, Vector3(x, y, z)])


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
		for sh: Array in _shapes.get(kind, []):
			var cs := CollisionShape3D.new()
			cs.shape = sh[0]
			cs.transform = Transform3D(xf.basis, xf * (sh[1] as Vector3))
			body.add_child(cs)
	if by_kind.is_empty():
		body.free()
		return
	for kind: String in by_kind:
		TiledMulti.add(root, "Placed_" + kind, _meshes[kind], by_kind[kind], GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			float(_reach.get(kind, DRAW_DISTANCE)))
	root.add_child(body)


# --- meshes (front faces -Z, standing on y = 0) ---------------------------------------------

static func _kit() -> MeshKit:
	var kit := MeshKit.new()
	kit.use_color = true
	return kit


static func _commit(kit: MeshKit, roughness := 0.7) -> ArrayMesh:
	return kit.commit(null, Materials.get_shared().vertex_colour(roughness))


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


# --- the bigger props pack -------------------------------------------------------------------

static func _more(mats: Materials) -> void:
	_meshes["dumpster"] = _dumpster()
	_shape("dumpster", Vector3(0.95, 0.62, 0.65), 0.62)
	_meshes["propane_cage"] = _propane_cage()
	_shape("propane_cage", Vector3(0.6, 0.9, 0.4), 0.9)
	_meshes["ice_machine"] = _ice_machine()
	_shape("ice_machine", Vector3(0.65, 1.0, 0.4), 1.0)
	_meshes["transformer"] = _transformer()
	_shape("transformer", Vector3(0.6, 0.55, 0.6), 0.55)
	_meshes["loading_bumper"] = _loading_bumper()
	_shape("loading_bumper", Vector3(0.15, 0.3, 0.1), 0.9)
	_meshes["bus_shelter"] = _bus_shelter()
	_shape("bus_shelter", Vector3(1.5, 1.2, 0.05), 1.2, 0.0, 0.65)
	_shape("bus_shelter", Vector3(0.05, 1.2, 0.6), 1.2, -1.5, 0.05)
	_shape("bus_shelter", Vector3(0.05, 1.2, 0.6), 1.2, 1.5, 0.05)
	_meshes["bike_rack"] = _bike_rack()
	_shape("bike_rack", Vector3(1.1, 0.42, 0.04), 0.42)
	_meshes["newspaper_box"] = _newspaper_box()
	_shape("newspaper_box", Vector3(0.25, 0.55, 0.23), 0.55)
	_meshes["community_mailbox"] = _community_mailbox()
	_shape("community_mailbox", Vector3(0.55, 0.8, 0.3), 0.8)
	_meshes["mailbox"] = _mailbox()
	_shape("mailbox", Vector3(0.05, 0.6, 0.05), 0.6)
	_meshes["utility_pole"] = StreetProps._utility_pole if StreetProps._utility_pole != null else StreetProps._utility_pole_mesh(mats, true)
	_shape("utility_pole", Vector3(0.15, 5.0, 0.15), 5.0)
	_meshes["gas_pump"] = _gas_pump()
	_shape("gas_pump", Vector3(0.55, 0.95, 0.35), 0.95)
	_meshes["ev_charger"] = _ev_charger()
	_shape("ev_charger", Vector3(0.22, 0.8, 0.18), 0.8)
	_meshes["atm"] = _atm(mats)
	_shape("atm", Vector3(0.42, 0.9, 0.38), 0.9)
	_meshes["cart_corral"] = _cart_corral()
	_shape("cart_corral", Vector3(2.0, 0.55, 0.04), 0.55, 0.0, -0.65)
	_shape("cart_corral", Vector3(2.0, 0.55, 0.04), 0.55, 0.0, 0.65)
	_meshes["lot_light"] = _lot_light(mats)
	_shape("lot_light", Vector3(0.3, 4.5, 0.3), 4.5)
	_meshes["playground"] = _playground()
	_shape("playground", Vector3(0.8, 1.3, 0.8), 1.3)
	_meshes["swing_set"] = _swing_set()
	_shape("swing_set", Vector3(0.1, 1.2, 0.8), 1.2, -1.8)
	_shape("swing_set", Vector3(0.1, 1.2, 0.8), 1.2, 1.8)
	_meshes["flagpole"] = _flagpole()
	_shape("flagpole", Vector3(0.07, 4.5, 0.07), 4.5)
	_meshes["fire_pit"] = _fire_pit()
	_shape("fire_pit", Vector3(0.6, 0.15, 0.6), 0.15)
	_meshes["shed"] = _shed()
	_shape("shed", Vector3(1.2, 1.1, 1.0), 1.1)
	_meshes["trampoline"] = _trampoline()
	_shape("trampoline", Vector3(1.8, 0.45, 1.8), 0.45)
	_meshes["lawn_chair"] = _lawn_chair()
	_shape("lawn_chair", Vector3(0.38, 0.45, 0.45), 0.45)
	_meshes["tyre_stack"] = _tyre_stack()
	_shape("tyre_stack", Vector3(0.36, 0.5, 0.36), 0.5)
	_shape("tyre_stack", Vector3(0.36, 0.25, 0.36), 0.25, 0.78, 0.1)
	_meshes["oil_drums"] = _oil_drums()
	_shape("oil_drums", Vector3(0.6, 0.5, 0.6), 0.5)


static func _cyl(kit: MeshKit, r: float, y0: float, y1: float, segs := 12) -> void:
	StreetProps._lathe(kit, [[0.0, y0], [r, y0], [r, y1], [0.0, y1]], segs)


## Moves the vertices added since `start` by `off` (a lathed part off the axis).
static func _shift(kit: MeshKit, start: int, off: Vector3) -> void:
	var v := kit.verts
	for i in range(start, v.size()):
		v[i] += off
	kit.verts = v


## Used tyres outside a garage: a stack of four and a pair beside it, worn
## black rubber with grey wheels showing in the middle of the top one.
static func _tyre_stack() -> ArrayMesh:
	var kit := _kit()
	var tyre := [[0.17, 0.0], [0.33, 0.0], [0.355, 0.04], [0.36, 0.1], [0.355, 0.16], [0.33, 0.2], [0.17, 0.2]]
	for spot: Vector3 in [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.2, 0.0), Vector3(0.01, 0.4, -0.01), Vector3(-0.01, 0.6, 0.01), Vector3(0.78, 0.0, 0.1), Vector3(0.77, 0.2, 0.11)]:
		_col(kit, Color(0.07, 0.07, 0.075))
		var prof: Array = []
		for q: Array in tyre:
			prof.append([q[0], float(q[1]) + spot.y])
		var start := kit.verts.size()
		StreetProps._lathe(kit, prof, 12)
		_shift(kit, start, Vector3(spot.x, 0.0, spot.z))
		# The hole: the inside of the tread, dark grey.
		_col(kit, Color(0.2, 0.2, 0.21))
		start = kit.verts.size()
		StreetProps._lathe(kit, [[0.171, spot.y + 0.2], [0.171, spot.y + 0.01]], 12)
		_shift(kit, start, Vector3(spot.x, 0.0, spot.z))
	return _commit(kit, 0.9)


## Three steel drums on a wooden pallet: oil and coolant, one red, one
## blue, one black, rings round them and a bung on top.
static func _oil_drums() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.55, 0.45, 0.32))
	_box(kit, Vector3(-0.6, 0.0, -0.6), Vector3(0.6, 0.13, 0.6))
	var drum := [[0.0, 0.13], [0.28, 0.13], [0.29, 0.16], [0.29, 0.4], [0.3, 0.42], [0.29, 0.44], [0.29, 0.66], [0.3, 0.68], [0.29, 0.7], [0.29, 0.97], [0.27, 1.0], [0.0, 1.0]]
	var spots := [Vector2(-0.29, -0.29), Vector2(0.29, -0.29), Vector2(-0.29, 0.29)]
	var colours := [Color(0.62, 0.1, 0.07), Color(0.1, 0.25, 0.55), Color(0.1, 0.1, 0.11)]
	for k in spots.size():
		_col(kit, colours[k])
		var start := kit.verts.size()
		StreetProps._lathe(kit, drum, 12)
		var at: Vector2 = spots[k]
		_shift(kit, start, Vector3(at.x, 0.0, at.y))
		_col(kit, Color(0.6, 0.6, 0.6))
		_box(kit, Vector3(at.x + 0.1, 1.0, at.y - 0.04), Vector3(at.x + 0.16, 1.03, at.y + 0.02))
	return _commit(kit, 0.6)


## A green commercial dumpster with black lids sloping to the back.
static func _dumpster() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.16, 0.4, 0.24))
	_box(kit, Vector3(-0.95, 0.15, -0.6), Vector3(0.95, 1.15, 0.6))
	_col(kit, Color(0.08, 0.08, 0.08))
	for x: float in [-0.94, 0.0]:
		kit.quad(Vector3(x, 1.25, -0.65), Vector3(x + 0.94, 1.25, -0.65), Vector3(x + 0.94, 1.15, 0.62), Vector3(x, 1.15, 0.62), Vector3(0, 1, 0.08).normalized())
	for x: float in [-0.8, 0.8]:
		for z: float in [-0.45, 0.45]:
			_box(kit, Vector3(x - 0.06, 0.0, z - 0.06), Vector3(x + 0.06, 0.15, z + 0.06))
	return _commit(kit, 0.6)


## A steel cage of propane tanks, as outside a gas station or hardware store.
static func _propane_cage() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.92, 0.92, 0.9))
	for x: float in [-0.35, 0.0, 0.35]:
		for y: float in [0.05, 0.95]:
			kit.color = Color(0.92, 0.92, 0.9).srgb_to_linear()
			StreetProps._lathe(kit, [[0.0, y], [0.15, y], [0.15, y + 0.5], [0.08, y + 0.6], [0.0, y + 0.62]], 10)
			kit.color = Color(0.6, 0.6, 0.6).srgb_to_linear()
	_col(kit, Color(0.2, 0.3, 0.55))
	for x: float in [-0.6, 0.6]:
		for z: float in [-0.4, 0.4]:
			_box(kit, Vector3(x - 0.025, 0.0, z - 0.025), Vector3(x + 0.025, 1.8, z + 0.025))
	_box(kit, Vector3(-0.6, 1.78, -0.4), Vector3(0.6, 1.82, 0.4))
	_box(kit, Vector3(-0.6, 0.88, -0.4), Vector3(0.6, 0.92, 0.4))
	for k in 13:
		var x := -0.6 + k * 0.1
		StreetProps._bar(kit, Vector3(x, 0.0, -0.4), Vector3(x, 1.8, -0.4), 0.008)
	_col(kit, Color(0.85, 0.15, 0.1))
	_box(kit, Vector3(-0.4, 1.4, -0.42), Vector3(0.4, 1.65, -0.41))
	return _commit(kit, 0.5)


## A white ice merchandiser with a blue band, front to -Z.
static func _ice_machine() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.92, 0.93, 0.94))
	_box(kit, Vector3(-0.65, 0.0, -0.4), Vector3(0.65, 2.0, 0.4))
	_col(kit, Color(0.1, 0.35, 0.75))
	_box(kit, Vector3(-0.66, 1.5, -0.41), Vector3(0.66, 1.85, 0.41))
	_col(kit, Color(0.7, 0.72, 0.74))
	_box(kit, Vector3(-0.5, 0.25, -0.42), Vector3(0.5, 1.35, -0.4))
	return _commit(kit, 0.4)


## A green pad-mounted transformer on a concrete pad.
static func _transformer() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.6, 0.6, 0.58))
	_box(kit, Vector3(-0.7, 0.0, -0.7), Vector3(0.7, 0.1, 0.7))
	_col(kit, Color(0.33, 0.47, 0.36))
	_box(kit, Vector3(-0.6, 0.1, -0.55), Vector3(0.6, 1.1, 0.55))
	kit.quad(Vector3(-0.6, 1.1, -0.55), Vector3(0.6, 1.1, -0.55), Vector3(0.6, 1.15, 0.55), Vector3(-0.6, 1.15, 0.55), Vector3.UP)
	return _commit(kit, 0.6)


## A black rubber loading-dock bumper, set on a wall at dock height.
static func _loading_bumper() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.06, 0.06, 0.06))
	_box(kit, Vector3(-0.13, 0.6, -0.1), Vector3(0.13, 1.2, 0.0))
	_col(kit, Color(0.85, 0.7, 0.1))
	_box(kit, Vector3(-0.3, 1.25, -0.02), Vector3(0.3, 1.35, 0.0))
	return _commit(kit, 0.8)


## A bus shelter: open to the front (-Z), a glass back and ends, a flat roof.
static func _bus_shelter() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.2, 0.22, 0.24))
	for x: float in [-1.5, 1.5]:
		for z: float in [-0.6, 0.65]:
			_box(kit, Vector3(x - 0.04, 0.0, z - 0.04), Vector3(x + 0.04, 2.4, z + 0.04))
	_box(kit, Vector3(-1.65, 2.4, -0.8), Vector3(1.65, 2.5, 0.75))
	_col(kit, Color(0.62, 0.72, 0.76))
	_box(kit, Vector3(-1.46, 0.15, 0.63), Vector3(1.46, 2.25, 0.66))
	for x: float in [-1.5, 1.5]:
		_box(kit, Vector3(x - 0.015, 0.15, -0.55), Vector3(x + 0.015, 2.25, 0.6))
	_col(kit, Color(0.45, 0.3, 0.2))
	_box(kit, Vector3(-1.0, 0.42, 0.35), Vector3(1.0, 0.47, 0.6))
	return _commit(kit, 0.35)


## A row of five inverted-U bike hoops along local X.
static func _bike_rack() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.55, 0.57, 0.58))
	for k in 5:
		var x := -1.0 + k * 0.5
		StreetProps._bar(kit, Vector3(x, 0.0, 0.3), Vector3(x, 0.55, 0.3), 0.025)
		StreetProps._bar(kit, Vector3(x, 0.0, -0.3), Vector3(x, 0.55, -0.3), 0.025)
		for j in 8:
			var a0 := PI * j / 8.0
			var a1 := PI * (j + 1) / 8.0
			StreetProps._bar(kit, Vector3(x, 0.55 + sin(a0) * 0.3, cos(a0) * 0.3), Vector3(x, 0.55 + sin(a1) * 0.3, cos(a1) * 0.3), 0.025)
	return _commit(kit, 0.35)


## A newspaper vending box on short legs, window to the front.
static func _newspaper_box() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.12, 0.3, 0.6))
	_box(kit, Vector3(-0.25, 0.3, -0.22), Vector3(0.25, 1.1, 0.22))
	_col(kit, Color(0.1, 0.1, 0.1))
	for x: float in [-0.2, 0.2]:
		_box(kit, Vector3(x - 0.02, 0.0, -0.02), Vector3(x + 0.02, 0.3, 0.02))
	_col(kit, Color(0.75, 0.8, 0.82))
	_box(kit, Vector3(-0.18, 0.6, -0.235), Vector3(0.18, 0.95, -0.22))
	return _commit(kit, 0.4)


## A community mailbox: a grey bank of locked boxes on a pedestal.
static func _community_mailbox() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.45, 0.47, 0.48))
	_box(kit, Vector3(-0.15, 0.0, -0.15), Vector3(0.15, 0.4, 0.15))
	_col(kit, Color(0.78, 0.79, 0.8))
	_box(kit, Vector3(-0.55, 0.4, -0.3), Vector3(0.55, 1.6, 0.3))
	_col(kit, Color(0.6, 0.62, 0.63))
	for r in 4:
		for c in 4:
			var x := -0.48 + c * 0.24
			var y := 0.5 + r * 0.27
			_box(kit, Vector3(x, y, -0.31), Vector3(x + 0.2, y + 0.22, -0.3))
	_col(kit, Color(0.7, 0.1, 0.08))
	_box(kit, Vector3(-0.56, 1.6, -0.31), Vector3(0.56, 1.65, 0.31))
	return _commit(kit, 0.45)


## A rural-style mailbox on a wooden post, door to the front.
static func _mailbox() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.42, 0.33, 0.24))
	_box(kit, Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 1.05, 0.05))
	_col(kit, Color(0.1, 0.1, 0.1))
	_box(kit, Vector3(-0.12, 1.05, -0.25), Vector3(0.12, 1.25, 0.25))
	StreetProps._lathe(kit, [[0.0, 1.25], [0.12, 1.25], [0.0, 1.32]], 8)
	_col(kit, Color(0.75, 0.1, 0.08))
	_box(kit, Vector3(0.12, 1.15, 0.05), Vector3(0.14, 1.4, 0.09))
	return _commit(kit, 0.5)


## A gas pump on its concrete island, faces to the front and back.
static func _gas_pump() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.7, 0.7, 0.68))
	_box(kit, Vector3(-0.6, 0.0, -0.4), Vector3(0.6, 0.18, 0.4))
	_col(kit, Color(0.93, 0.93, 0.93))
	_box(kit, Vector3(-0.45, 0.18, -0.25), Vector3(0.45, 1.85, 0.25))
	_col(kit, Color(0.8, 0.12, 0.1))
	_box(kit, Vector3(-0.46, 1.6, -0.26), Vector3(0.46, 1.9, 0.26))
	_col(kit, Color(0.1, 0.1, 0.12))
	for z: float in [-0.26, 0.255]:
		_box(kit, Vector3(-0.25, 1.15, z), Vector3(0.25, 1.45, z + 0.005))
		_box(kit, Vector3(-0.38, 0.55, z), Vector3(-0.3, 0.95, z + 0.005))
		_box(kit, Vector3(0.3, 0.55, z), Vector3(0.38, 0.95, z + 0.005))
	return _commit(kit, 0.45)


## An electric car charger: a slim white post with a green band.
static func _ev_charger() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.6, 0.6, 0.58))
	_box(kit, Vector3(-0.3, 0.0, -0.25), Vector3(0.3, 0.1, 0.25))
	_col(kit, Color(0.94, 0.94, 0.94))
	_box(kit, Vector3(-0.2, 0.1, -0.15), Vector3(0.2, 1.6, 0.15))
	_col(kit, Color(0.15, 0.65, 0.35))
	_box(kit, Vector3(-0.205, 1.3, -0.155), Vector3(0.205, 1.4, 0.155))
	_col(kit, Color(0.08, 0.08, 0.08))
	_box(kit, Vector3(-0.12, 0.9, -0.16), Vector3(0.12, 1.15, -0.15))
	_box(kit, Vector3(0.2, 0.7, -0.05), Vector3(0.26, 0.85, 0.05))
	return _commit(kit, 0.4)


## A free-standing ATM with a lit screen to the front.
static func _atm(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.35, 0.37, 0.4))
	_box(kit, Vector3(-0.4, 0.0, -0.35), Vector3(0.4, 1.75, 0.35))
	_col(kit, Color(0.1, 0.3, 0.6))
	_box(kit, Vector3(-0.42, 1.75, -0.37), Vector3(0.42, 1.95, 0.37))
	_col(kit, Color(0.2, 0.2, 0.22))
	_box(kit, Vector3(-0.3, 0.95, -0.45), Vector3(0.3, 1.05, -0.35))
	var mesh := _commit(kit, 0.4)
	var lit := MeshKit.new()
	lit.quad(Vector3(-0.22, 1.2, -0.355), Vector3(0.22, 1.2, -0.355), Vector3(0.22, 1.5, -0.355), Vector3(-0.22, 1.5, -0.355), Vector3(0, 0, -1))
	lit.commit(mesh, mats.glow(Color(0.5, 0.8, 1.0), 0.8))
	return mesh


## A shopping-cart corral: two rails along local X, open at both ends.
static func _cart_corral() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.6, 0.62, 0.62))
	for z: float in [-0.65, 0.65]:
		for y: float in [0.45, 1.05]:
			StreetProps._bar(kit, Vector3(-2.0, y, z), Vector3(2.0, y, z), 0.025)
		for x: float in [-2.0, 0.0, 2.0]:
			StreetProps._bar(kit, Vector3(x, 0.0, z), Vector3(x, 1.1, z), 0.03)
	StreetProps._bar(kit, Vector3(-2.0, 1.1, -0.65), Vector3(-2.0, 1.1, 0.65), 0.03)
	_col(kit, Color(0.1, 0.35, 0.7))
	_box(kit, Vector3(-2.05, 1.15, -0.4), Vector3(-1.95, 1.6, 0.4))
	return _commit(kit, 0.4)


## A parking-lot light: a tall steel pole on a concrete base with two
## shoebox heads.
static func _lot_light(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.6, 0.6, 0.58))
	_cyl(kit, 0.3, 0.0, 0.7, 10)
	_col(kit, Color(0.45, 0.47, 0.48))
	StreetProps._lathe(kit, [[0.0, 0.7], [0.1, 0.7], [0.07, 9.0], [0.0, 9.0]], 8)
	for s: float in [-1.0, 1.0]:
		_box(kit, Vector3(minf(0.0, s * 0.9), 8.85, -0.05), Vector3(maxf(0.0, s * 0.9), 8.95, 0.05))
		_box(kit, Vector3(s * 0.9 - 0.35, 8.8, -0.25), Vector3(s * 0.9 + 0.35, 9.0, 0.25))
	var mesh := _commit(kit, 0.5)
	var lit := MeshKit.new()
	for s: float in [-1.0, 1.0]:
		lit.quad(Vector3(s * 0.9 - 0.3, 8.79, -0.2), Vector3(s * 0.9 + 0.3, 8.79, -0.2), Vector3(s * 0.9 + 0.3, 8.79, 0.2), Vector3(s * 0.9 - 0.3, 8.79, 0.2), Vector3.DOWN)
	lit.commit(mesh, mats.glow(Color(1.0, 0.95, 0.85), 1.2))
	return mesh


## A small play structure: a deck on four posts, a roof, a ladder at the
## back and a yellow slide down to the front.
static func _playground() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.15, 0.4, 0.7))
	for x: float in [-0.75, 0.75]:
		for z: float in [-0.75, 0.75]:
			_box(kit, Vector3(x - 0.05, 0.0, z - 0.05), Vector3(x + 0.05, 2.6, z + 0.05))
	_col(kit, Color(0.55, 0.4, 0.25))
	_box(kit, Vector3(-0.8, 1.2, -0.8), Vector3(0.8, 1.28, 0.8))
	_col(kit, Color(0.8, 0.15, 0.1))
	for k in 4:
		var a := Vector3(-0.9, 2.6, -0.9).rotated(Vector3.UP, k * PI / 2.0)
		var b := Vector3(-0.9, 2.6, -0.9).rotated(Vector3.UP, (k + 1) * PI / 2.0)
		var n := ((a + b) * 0.5 * Vector3(1, 0, 1)).normalized() + Vector3.UP
		kit.tri(a, b, Vector3(0, 3.2, 0), n.normalized())
	_col(kit, Color(0.95, 0.8, 0.1))
	var s0 := Vector3(0, 1.28, -0.8)
	var s1 := Vector3(0, 0.25, -2.6)
	kit.quad(s0 + Vector3(-0.25, 0, 0), s0 + Vector3(0.25, 0, 0), s1 + Vector3(0.25, 0, 0), s1 + Vector3(-0.25, 0, 0), Vector3(0, 0.87, -0.5))
	for x: float in [-0.25, 0.25]:
		kit.quad(s0 + Vector3(x, 0, 0), s1 + Vector3(x, 0, 0), s1 + Vector3(x, 0.15, 0), s0 + Vector3(x, 0.15, 0), Vector3(signf(x), 0, 0))
	_col(kit, Color(0.15, 0.4, 0.7))
	for k in 5:
		var y := 0.25 + k * 0.24
		_box(kit, Vector3(-0.3, y, 0.78), Vector3(0.3, y + 0.04, 0.84))
	return _commit(kit, 0.5)


## A swing set: two A-frames joined by a top bar along local X, two seats.
static func _swing_set() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.2, 0.45, 0.25))
	for x: float in [-1.8, 1.8]:
		for z: float in [-0.8, 0.8]:
			StreetProps._bar(kit, Vector3(x, 0.0, z), Vector3(x, 2.4, 0.0), 0.04)
	StreetProps._bar(kit, Vector3(-1.8, 2.4, 0.0), Vector3(1.8, 2.4, 0.0), 0.045)
	for x: float in [-0.7, 0.7]:
		_col(kit, Color(0.3, 0.3, 0.3))
		for dx: float in [-0.2, 0.2]:
			StreetProps._bar(kit, Vector3(x + dx, 2.4, 0.0), Vector3(x + dx, 0.5, 0.0), 0.008)
		_col(kit, Color(0.08, 0.08, 0.08))
		_box(kit, Vector3(x - 0.24, 0.47, -0.1), Vector3(x + 0.24, 0.52, 0.1))
	return _commit(kit, 0.5)


## A white flagpole with a red and white flag flying to local +X.
static func _flagpole() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.7, 0.7, 0.68))
	_cyl(kit, 0.3, 0.0, 0.15, 10)
	_col(kit, Color(0.93, 0.93, 0.92))
	StreetProps._lathe(kit, [[0.0, 0.15], [0.07, 0.15], [0.035, 9.0], [0.06, 9.05], [0.0, 9.12]], 8)
	_col(kit, Color(0.8, 0.1, 0.1))
	_box(kit, Vector3(0.05, 7.6, -0.01), Vector3(0.55, 8.85, 0.01))
	_box(kit, Vector3(1.55, 7.6, -0.01), Vector3(2.05, 8.85, 0.01))
	_col(kit, Color(0.95, 0.95, 0.95))
	_box(kit, Vector3(0.55, 7.6, -0.01), Vector3(1.55, 8.85, 0.01))
	return _commit(kit, 0.6)


## A backyard fire pit: a ring of stones round a dark bed.
static func _fire_pit() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.1, 0.09, 0.08))
	_cyl(kit, 0.45, 0.0, 0.05, 12)
	_col(kit, Color(0.5, 0.48, 0.45))
	for k in 12:
		var a := TAU * k / 12.0
		var c := Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
		_box(kit, c + Vector3(-0.12, 0.0, -0.12), c + Vector3(0.12, 0.28, 0.12))
	return _commit(kit, 0.9)


## A small garden shed with a gable roof, door to the front.
static func _shed() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.72, 0.62, 0.48))
	_box(kit, Vector3(-1.2, 0.0, -1.0), Vector3(1.2, 2.0, 1.0))
	for z: float in [-1.0, 1.0]:
		kit.tri(Vector3(-1.2, 2.0, z), Vector3(1.2, 2.0, z), Vector3(0.0, 2.7, z), Vector3(0, 0, signf(z)))
	_col(kit, Color(0.3, 0.25, 0.22))
	for s: float in [-1.0, 1.0]:
		var n := Vector3(s * 0.7, 1.2, 0.0).normalized()
		kit.quad(Vector3(s * 1.35, 1.92, -1.1), Vector3(0.0, 2.75, -1.1), Vector3(0.0, 2.75, 1.1), Vector3(s * 1.35, 1.92, 1.1), n)
	_col(kit, Color(0.55, 0.45, 0.35))
	_box(kit, Vector3(-0.45, 0.0, -1.02), Vector3(0.45, 1.85, -1.0))
	return _commit(kit, 0.8)


## A round backyard trampoline: black mat, blue pad, legs.
static func _trampoline() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.4, 0.42, 0.44))
	for k in 6:
		var a := TAU * k / 6.0
		var c := Vector3(cos(a) * 1.7, 0.0, sin(a) * 1.7)
		StreetProps._bar(kit, c, c + Vector3(0, 0.9, 0), 0.03)
	_col(kit, Color(0.1, 0.1, 0.1))
	_cyl(kit, 1.5, 0.86, 0.88, 20)
	_col(kit, Color(0.1, 0.35, 0.75))
	StreetProps._lathe(kit, [[1.5, 0.88], [1.82, 0.88], [1.82, 0.95], [1.5, 0.95]], 20)
	return _commit(kit, 0.7)


## An Adirondack-style lawn chair facing the front.
static func _lawn_chair() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.85, 0.35, 0.15))
	kit.quad(Vector3(-0.3, 0.35, -0.35), Vector3(0.3, 0.35, -0.35), Vector3(0.3, 0.3, 0.2), Vector3(-0.3, 0.3, 0.2), Vector3.UP)
	kit.quad(Vector3(-0.3, 0.3, 0.2), Vector3(0.3, 0.3, 0.2), Vector3(0.32, 1.0, 0.5), Vector3(-0.32, 1.0, 0.5), Vector3(0, 0.4, -0.9).normalized())
	for x: float in [-0.38, 0.38]:
		_box(kit, Vector3(x - 0.06, 0.6, -0.4), Vector3(x + 0.06, 0.63, 0.25))
		_box(kit, Vector3(x - 0.03, 0.0, -0.35), Vector3(x + 0.03, 0.6, -0.3))
		_box(kit, Vector3(x - 0.03, 0.0, 0.15), Vector3(x + 0.03, 0.35, 0.2))
	return _commit(kit, 0.7)

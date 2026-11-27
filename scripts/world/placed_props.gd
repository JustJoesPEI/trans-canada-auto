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
	"car_wash", "tyre_stack", "oil_drums",
	"cannon", "cow_statue", "bronze_statue", "judges_stand", "gangway_tower",
	"waste_carts", "compost_cart", "patio_set", "patio_table", "soccer_goal", "basketball_hoop", "tennis_net",
	"headstone", "headstone_dark", "marble_tablet", "iron_arch", "swan_lamp"]
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
static var _shadows: Dictionary = {} ## kind -> shadows-only stand-in (ShadowProxy)

## The stand-in each kind casts its shadow with (docs/world_art.md, W6):
## solid things a box or a prism, posts and lamps a post with a head, open
## frames (benches, swings, racks) their own shape in one plain surface. A
## kind not listed gets a BOX.
const SHADOW_SHAPES := {
	"bench": ShadowProxy.Shape.SELF, "picnic_table": ShadowProxy.Shape.SELF,
	"waste_basket": ShadowProxy.Shape.ROUND, "fire_hydrant": ShadowProxy.Shape.ROUND,
	"bollard": ShadowProxy.Shape.ROUND, "traffic_cone": ShadowProxy.Shape.ROUND,
	"oil_drums": ShadowProxy.Shape.SELF, "tyre_stack": ShadowProxy.Shape.ROUND,
	"heritage_lamp": ShadowProxy.Shape.POST, "street_light": ShadowProxy.Shape.POST,
	"lot_light": ShadowProxy.Shape.POST, "flagpole": ShadowProxy.Shape.POST,
	"utility_pole": ShadowProxy.Shape.SELF, "drive_thru_speaker": ShadowProxy.Shape.POST,
	"height_bar": ShadowProxy.Shape.SELF, "bus_shelter": ShadowProxy.Shape.SELF,
	"bike_rack": ShadowProxy.Shape.SELF, "propane_cage": ShadowProxy.Shape.SELF,
	"cart_corral": ShadowProxy.Shape.SELF, "playground": ShadowProxy.Shape.SELF,
	"swing_set": ShadowProxy.Shape.SELF, "trampoline": ShadowProxy.Shape.SELF,
	"lawn_chair": ShadowProxy.Shape.SELF, "fire_pit": ShadowProxy.Shape.ROUND,
	"ev_charger": ShadowProxy.Shape.SELF, "gas_pump": ShadowProxy.Shape.SELF,
	"car_wash": ShadowProxy.Shape.SELF, "boulder": ShadowProxy.Shape.SELF,
	"jersey_barrier": ShadowProxy.Shape.SELF, "planter": ShadowProxy.Shape.SELF,
	"mailbox": ShadowProxy.Shape.SELF, "drive_thru_menu": ShadowProxy.Shape.SELF,
	"cannon": ShadowProxy.Shape.SELF, "cow_statue": ShadowProxy.Shape.SELF, "bronze_statue": ShadowProxy.Shape.SELF,
	"judges_stand": ShadowProxy.Shape.BOX, "gangway_tower": ShadowProxy.Shape.SELF,
	"waste_carts": ShadowProxy.Shape.BOX, "compost_cart": ShadowProxy.Shape.BOX, "patio_set": ShadowProxy.Shape.SELF, "patio_table": ShadowProxy.Shape.SELF,
	"soccer_goal": ShadowProxy.Shape.SELF, "basketball_hoop": ShadowProxy.Shape.SELF, "tennis_net": ShadowProxy.Shape.SELF,
	"headstone": ShadowProxy.Shape.BOX, "headstone_dark": ShadowProxy.Shape.BOX, "marble_tablet": ShadowProxy.Shape.BOX,
	"iron_arch": ShadowProxy.Shape.SELF, "swan_lamp": ShadowProxy.Shape.POST,
}
## Shadows of props this size and up (m, tallest side) are drawn as far as
## the props themselves; smaller ones only within ShadowProxy.DISTANCE.
const SHADOW_FULL_SIZE := 3.0

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
		_shadows[kind] = ShadowProxy.for_mesh(_meshes[kind], SHADOW_SHAPES.get(kind, ShadowProxy.Shape.BOX))
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


## Builds the chunk's placed props, and `extra` beside them: what
## TownDressing worked out (kind -> Array of [Transform3D, solid]).
func build(root: Node3D, extra: Dictionary = {}) -> void:
	var by_kind: Dictionary = {}
	var body := StaticBody3D.new()
	body.name = "PlacedProps"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for kind: String in extra:
		if not _meshes.has(kind):
			continue
		if not by_kind.has(kind):
			by_kind[kind] = []
		for it: Array in extra[kind]:
			var xf: Transform3D = it[0]
			by_kind[kind].append(xf)
			if it[1]:
				for sh: Array in _shapes.get(kind, []):
					var cs := CollisionShape3D.new()
					cs.shape = sh[0]
					cs.transform = Transform3D(xf.basis.orthonormalized(), xf * (sh[1] as Vector3))
					body.add_child(cs)
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
		var reach := float(_reach.get(kind, DRAW_DISTANCE))
		var s: Vector3 = (_meshes[kind] as Mesh).get_aabb().size
		var big := maxf(s.x, maxf(s.y, s.z)) >= SHADOW_FULL_SIZE
		ShadowProxy.add(root, "Placed_" + kind, _meshes[kind], by_kind[kind], reach, _shadows[kind],
			reach if big else ShadowProxy.DISTANCE)
	root.add_child(body)


# --- meshes (front faces -Z, standing on y = 0) ---------------------------------------------

static func _kit() -> MeshKit:
	var kit := MeshKit.new()
	kit.use_color = true
	return kit


## Each roughness is a shared material of its own, and a chunk with a
## dozen kinds of prop would count a dozen (docs/world_art.md W2): so there
## are two, shiny (painted metal, plastic) and matt (wood, stone, fabric),
## the matt one the same as the fences' and hedges' (EditLines).
static func _commit(kit: MeshKit, roughness := 0.7) -> ArrayMesh:
	return kit.commit(null, Materials.get_shared().vertex_colour(0.5 if roughness < 0.65 else 0.85))


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
	_shape("community_mailbox", Vector3(1.2, 0.85, 0.3), 0.85)
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
	_meshes["cannon"] = _cannon()
	_shape("cannon", Vector3(0.55, 0.5, 1.2), 0.5)
	_meshes["cow_statue"] = _cow_statue()
	_shape("cow_statue", Vector3(0.45, 0.75, 1.25), 0.75)
	_meshes["bronze_statue"] = _bronze_statue()
	_shape("bronze_statue", Vector3(0.6, 1.4, 0.6), 1.4)
	_meshes["judges_stand"] = _judges_stand()
	_shape("judges_stand", Vector3(1.6, 3.6, 1.6), 3.6)
	_meshes["gangway_tower"] = _gangway_tower()
	_shape("gangway_tower", Vector3(1.6, 5.0, 1.6), 5.0)
	_meshes["oil_drums"] = _oil_drums()
	_shape("oil_drums", Vector3(0.6, 0.5, 0.6), 0.5)
	_yard_and_park_props()


static func _cyl(kit: MeshKit, r: float, y0: float, y1: float, segs := 12) -> void:
	StreetProps._lathe(kit, [[0.0, y0], [r, y0], [r, y1], [0.0, y1]], segs)


## Moves the vertices added since `start` by `off` (a lathed part off the axis).
static func _shift(kit: MeshKit, start: int, off: Vector3) -> void:
	var v := kit.verts
	for i in range(start, v.size()):
		v[i] += off
	kit.verts = v


## Turns the vertices (and normals) added since `start` by `basis`, then
## moves them by `off`: a lathed part laid on its side (a wheel, a barrel).
static func _turn_part(kit: MeshKit, start: int, basis: Basis, off: Vector3) -> void:
	var v := kit.verts
	var n := kit.normals
	for i in range(start, v.size()):
		v[i] = basis * v[i] + off
		n[i] = (basis * n[i]).normalized()
	kit.verts = v
	kit.normals = n


## A Prince Edward Battery gun on a wooden garrison carriage, muzzle to -Z:
## a black iron barrel with a swell at the muzzle and rings at the breech,
## a brown carriage of two cheeks and an axle, four small iron-rimmed trucks.
static func _cannon() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.33, 0.22, 0.14))
	for x: float in [-0.24, 0.24]:
		_box(kit, Vector3(x - 0.06, 0.18, -0.35), Vector3(x + 0.06, 0.62, 1.05))
	_box(kit, Vector3(-0.3, 0.18, 0.75), Vector3(0.3, 0.34, 1.1))
	_box(kit, Vector3(-0.3, 0.18, -0.4), Vector3(0.3, 0.3, -0.2))
	for z: float in [-0.3, 0.85]:
		_col(kit, Color(0.12, 0.12, 0.12))
		_box(kit, Vector3(-0.42, 0.16, z - 0.04), Vector3(0.42, 0.22, z + 0.04))
		for x: float in [-0.36, 0.36]:
			_col(kit, Color(0.3, 0.2, 0.13))
			var start := kit.verts.size()
			StreetProps._lathe(kit, [[0.0, -0.05], [0.19, -0.05], [0.19, 0.05], [0.0, 0.05]], 10)
			_turn_part(kit, start, Basis(Vector3.BACK, PI / 2.0), Vector3(x, 0.19, z))
	# The barrel along -Z, breech at +Z, resting on the cheeks.
	_col(kit, Color(0.09, 0.09, 0.1))
	var b := kit.verts.size()
	StreetProps._lathe(kit, [[0.0, -0.1], [0.2, -0.1], [0.23, 0.0], [0.23, 0.15], [0.2, 0.2], [0.19, 0.9], [0.15, 1.85], [0.17, 1.9], [0.17, 2.05], [0.11, 2.05], [0.11, 1.95]], 12)
	_turn_part(kit, b, Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.72, 0.95))
	# The knob at the breech.
	b = kit.verts.size()
	StreetProps._lathe(kit, [[0.0, 0.0], [0.07, 0.0], [0.08, 0.1], [0.0, 0.16]], 8)
	_turn_part(kit, b, Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, 0.72, 1.05))
	return _commit(kit, 0.6)


## A life-size fibreglass Holstein on a low plinth, head to -Z: white with
## black patches, a pink nose and udder, black hooves (the creamery's cow).
static func _cow_statue() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.55, 0.55, 0.53))
	_box(kit, Vector3(-0.55, 0.0, -1.35), Vector3(0.55, 0.15, 1.35))
	var white := Color(0.95, 0.95, 0.93)
	var black := Color(0.07, 0.07, 0.08)
	# The barrel of the body: a lathe laid along Z.
	_col(kit, white)
	var b := kit.verts.size()
	StreetProps._lathe(kit, [[0.0, -0.95], [0.25, -0.93], [0.36, -0.7], [0.4, -0.2], [0.4, 0.4], [0.36, 0.8], [0.26, 0.95], [0.0, 0.98]], 10)
	_turn_part(kit, b, Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(0.95, 1.0, 1.15)), Vector3(0.0, 1.08, 0.0))
	# Legs, hooves.
	for x: float in [-0.22, 0.22]:
		for z: float in [-0.65, 0.7]:
			_col(kit, white)
			_box(kit, Vector3(x - 0.07, 0.25, z - 0.07), Vector3(x + 0.07, 0.9, z + 0.07))
			_col(kit, black)
			_box(kit, Vector3(x - 0.08, 0.15, z - 0.08), Vector3(x + 0.08, 0.27, z + 0.08))
	# Black patches standing a little proud of the body.
	_col(kit, black)
	for pt: Array in [[Vector3(0.36, 1.15, 0.25), Vector3(0.06, 0.28, 0.32)], [Vector3(-0.36, 1.05, -0.3), Vector3(0.06, 0.25, 0.28)],
			[Vector3(0.0, 1.5, 0.55), Vector3(0.25, 0.04, 0.22)], [Vector3(-0.34, 1.25, 0.6), Vector3(0.07, 0.18, 0.2)], [Vector3(0.33, 0.95, -0.6), Vector3(0.07, 0.2, 0.18)]]:
		StreetClutter._cube(kit, pt[0], pt[1])
	# Neck and head, the nose pink, ears and horns.
	_col(kit, white)
	_box(kit, Vector3(-0.17, 1.05, -1.25), Vector3(0.17, 1.45, -0.85))
	_col(kit, black)
	_box(kit, Vector3(-0.15, 1.25, -1.55), Vector3(0.15, 1.6, -1.15))
	_col(kit, Color(0.9, 0.62, 0.66))
	_box(kit, Vector3(-0.12, 1.12, -1.68), Vector3(0.12, 1.32, -1.45))
	_col(kit, black)
	for x: float in [-0.25, 0.25]:
		_box(kit, Vector3(x - 0.07, 1.48, -1.3), Vector3(x + 0.07, 1.55, -1.22))
	_col(kit, Color(0.88, 0.86, 0.78))
	for x: float in [-0.12, 0.12]:
		_box(kit, Vector3(x - 0.025, 1.6, -1.32), Vector3(x + 0.025, 1.7, -1.28))
	# The udder and the tail.
	_col(kit, Color(0.9, 0.62, 0.66))
	_box(kit, Vector3(-0.15, 0.62, 0.35), Vector3(0.15, 0.78, 0.65))
	_col(kit, white)
	StreetProps._bar(kit, Vector3(0.0, 1.35, 1.08), Vector3(0.0, 0.55, 1.12), 0.03)
	_col(kit, black)
	_box(kit, Vector3(-0.05, 0.42, 1.08), Vector3(0.05, 0.58, 1.16))
	return _commit(kit, 0.35)


## A bronze girl on a granite plinth, holding wheat stalks to her chest
## (the Holodomor memorial at Confederation Landing), facing -Z.
static func _bronze_statue() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.5, 0.5, 0.49))
	_box(kit, Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.75, 0.5))
	_col(kit, Color(0.58, 0.58, 0.56))
	_box(kit, Vector3(-0.56, 0.75, -0.56), Vector3(0.56, 0.82, 0.56))
	var bronze := Color(0.27, 0.22, 0.15)
	_col(kit, bronze)
	# A thin child's figure: dress, shoulders, head, scarf knot.
	StreetProps._lathe(kit, [[0.0, 0.82], [0.17, 0.82], [0.2, 1.05], [0.15, 1.45], [0.11, 1.75], [0.13, 1.82], [0.0, 1.84]], 10)
	for x: float in [-0.06, 0.06]:
		_box(kit, Vector3(x - 0.035, 0.82, -0.04), Vector3(x + 0.035, 1.0, 0.04))
	StreetProps._lathe(kit, [[0.0, 1.84], [0.08, 1.88], [0.1, 1.98], [0.08, 2.08], [0.0, 2.1]], 8)
	# Arms folded, holding the wheat.
	StreetProps._bar(kit, Vector3(-0.13, 1.72, 0.0), Vector3(-0.07, 1.55, -0.12), 0.03)
	StreetProps._bar(kit, Vector3(0.13, 1.72, 0.0), Vector3(0.07, 1.55, -0.12), 0.03)
	_col(kit, Color(0.42, 0.34, 0.18))
	for k in 5:
		var a := float(k - 2) * 0.05
		StreetProps._bar(kit, Vector3(a * 0.4, 1.35, -0.14), Vector3(a, 1.95, -0.16), 0.008)
		_box(kit, Vector3(a - 0.015, 1.92, -0.175), Vector3(a + 0.015, 2.02, -0.145))
	return _commit(kit, 0.45)


## The racetrack's judges' stand, facing -Z (the track): a white two-storey
## box on posts with green bands, a band of dark glass up top, a green
## pyramid roof and a weathervane.
static func _judges_stand() -> ArrayMesh:
	var kit := _kit()
	var white := Color(0.94, 0.94, 0.92)
	var green := Color(0.13, 0.36, 0.22)
	_col(kit, white)
	for x: float in [-1.3, 1.3]:
		for z: float in [-1.3, 1.3]:
			_box(kit, Vector3(x - 0.1, 0.0, z - 0.1), Vector3(x + 0.1, 2.4, z + 0.1))
	_box(kit, Vector3(-1.5, 2.4, -1.5), Vector3(1.5, 4.6, 1.5))
	_col(kit, green)
	_box(kit, Vector3(-1.53, 2.4, -1.53), Vector3(1.53, 2.6, 1.53))
	_box(kit, Vector3(-1.53, 4.4, -1.53), Vector3(1.53, 4.6, 1.53))
	_col(kit, Color(0.12, 0.15, 0.17))
	_box(kit, Vector3(-1.4, 3.1, -1.52), Vector3(1.4, 4.2, -1.5))
	_box(kit, Vector3(-1.52, 3.1, -1.2), Vector3(-1.5, 4.2, 1.2))
	_box(kit, Vector3(1.5, 3.1, -1.2), Vector3(1.52, 4.2, 1.2))
	# The stair up the back.
	_col(kit, white)
	for k in 10:
		var y := 0.24 * k
		_box(kit, Vector3(0.6, y, 1.5 + 0.25 * (9 - k)), Vector3(1.3, y + 0.06, 1.75 + 0.25 * (9 - k)))
	# The pyramid roof.
	_col(kit, green)
	for k in 4:
		var a := Vector3(-1.8, 4.6, -1.8).rotated(Vector3.UP, k * PI / 2.0)
		var b := Vector3(-1.8, 4.6, -1.8).rotated(Vector3.UP, (k + 1) * PI / 2.0)
		var n := ((a + b) * 0.5 * Vector3(1, 0, 1)).normalized() * 0.8 + Vector3.UP * 0.6
		kit.tri(a, b, Vector3(0, 6.2, 0), n.normalized())
	# The weathervane: a rod and a little horse in black.
	_col(kit, Color(0.08, 0.08, 0.08))
	StreetProps._bar(kit, Vector3(0, 6.2, 0), Vector3(0, 7.1, 0), 0.02)
	_box(kit, Vector3(-0.3, 6.9, -0.01), Vector3(0.25, 7.05, 0.01))
	_box(kit, Vector3(0.18, 7.05, -0.01), Vector3(0.28, 7.2, 0.01))
	return _commit(kit, 0.6)


## A cruise berth's passenger gangway tower, facing -Z (the ship): a green
## steel frame tower with a stair, a cab on top and a covered ramp reaching
## out over the wharf edge.
static func _gangway_tower() -> ArrayMesh:
	var kit := _kit()
	var green := Color(0.18, 0.42, 0.3)
	_col(kit, Color(0.6, 0.6, 0.58))
	_box(kit, Vector3(-1.8, 0.0, -1.8), Vector3(1.8, 0.25, 1.8))
	_col(kit, green)
	for x: float in [-1.4, 1.4]:
		for z: float in [-1.4, 1.4]:
			_box(kit, Vector3(x - 0.12, 0.25, z - 0.12), Vector3(x + 0.12, 9.0, z + 0.12))
	for y: float in [2.5, 5.0, 7.5]:
		for s: float in [-1.4, 1.4]:
			StreetProps._bar(kit, Vector3(-1.4, y, s), Vector3(1.4, y, s), 0.06)
			StreetProps._bar(kit, Vector3(s, y, -1.4), Vector3(s, y, 1.4), 0.06)
	for k in 3:
		var y := 2.5 * k
		StreetProps._bar(kit, Vector3(-1.4, y + 0.25, -1.4), Vector3(1.4, y + 2.5, 1.4), 0.05)
	# The cab and the ramp out to the ship's door, with yellow edges.
	_col(kit, Color(0.92, 0.92, 0.9))
	_box(kit, Vector3(-1.6, 9.0, -1.6), Vector3(1.6, 11.4, 1.6))
	_col(kit, green)
	_box(kit, Vector3(-1.7, 11.4, -1.7), Vector3(1.7, 11.6, 1.7))
	_box(kit, Vector3(-0.8, 9.2, -8.5), Vector3(0.8, 9.35, -1.6))
	_col(kit, Color(0.92, 0.92, 0.9))
	for x: float in [-0.8, 0.8]:
		_box(kit, Vector3(x - 0.05, 9.35, -8.5), Vector3(x + 0.05, 11.2, -1.6))
	_box(kit, Vector3(-0.85, 11.2, -8.5), Vector3(0.85, 11.3, -1.6))
	_col(kit, Color(0.95, 0.78, 0.08))
	_box(kit, Vector3(-0.82, 9.1, -8.55), Vector3(0.82, 9.2, -8.4))
	return _commit(kit, 0.55)


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
	# A Canada Post bank, as every one on the Island has been since the
	# 2015 switch: three grey modules side by side on a concrete pad, a red
	# band across the top, the little doors flat on the front (cheap repeats).
	var kit := _kit()
	_col(kit, Color(0.66, 0.65, 0.62))
	_box(kit, Vector3(-1.35, 0.0, -0.6), Vector3(1.35, 0.1, 0.5))
	for m in 3:
		var x0 := -1.2 + m * 0.8
		_col(kit, Color(0.35, 0.36, 0.38))
		_box(kit, Vector3(x0 + 0.1, 0.1, -0.2), Vector3(x0 + 0.7, 0.45, 0.2))
		_col(kit, Color(0.79, 0.8, 0.8))
		_box(kit, Vector3(x0, 0.45, -0.3), Vector3(x0 + 0.78, 1.6, 0.3))
		_col(kit, Color(0.62, 0.64, 0.65))
		for r in 4:
			for c in 3:
				var x := x0 + 0.06 + c * 0.24
				var y := 0.55 + r * 0.25
				kit.quad(Vector3(x, y, -0.302), Vector3(x + 0.2, y, -0.302), Vector3(x + 0.2, y + 0.21, -0.302), Vector3(x, y + 0.21, -0.302), Vector3(0, 0, -1))
		_col(kit, Color(0.84, 0.17, 0.12))
		_box(kit, Vector3(x0 - 0.005, 1.6, -0.31), Vector3(x0 + 0.785, 1.7, 0.31))
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


## A small garden shed with a gable roof, door to the front: barn red
## with white corner boards and door trim, the Island's usual (CBC photos
## after Fiona: red sheds with white trim behind every other house).
static func _shed() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.56, 0.18, 0.15))
	_box(kit, Vector3(-1.2, 0.0, -1.0), Vector3(1.2, 2.0, 1.0))
	for z: float in [-1.0, 1.0]:
		kit.tri(Vector3(-1.2, 2.0, z), Vector3(1.2, 2.0, z), Vector3(0.0, 2.7, z), Vector3(0, 0, signf(z)))
	_col(kit, Color(0.3, 0.29, 0.28))
	for s: float in [-1.0, 1.0]:
		var n := Vector3(s * 0.7, 1.2, 0.0).normalized()
		kit.quad(Vector3(s * 1.35, 1.92, -1.1), Vector3(0.0, 2.75, -1.1), Vector3(0.0, 2.75, 1.1), Vector3(s * 1.35, 1.92, 1.1), n)
	_col(kit, Color(0.93, 0.92, 0.88))
	for x: float in [-1.2, 1.2]:
		for z: float in [-1.0, 1.0]:
			_box(kit, Vector3(x - 0.06, 0.0, z - 0.06), Vector3(x + 0.06, 2.0, z + 0.06))
	_box(kit, Vector3(-0.55, 0.0, -1.03), Vector3(0.55, 1.95, -1.01))
	_col(kit, Color(0.56, 0.18, 0.15))
	_box(kit, Vector3(-0.45, 0.0, -1.04), Vector3(0.45, 1.85, -1.03))
	_col(kit, Color(0.93, 0.92, 0.88))
	StreetProps._bar(kit, Vector3(-0.42, 0.1, -1.05), Vector3(0.42, 1.8, -1.05), 0.03)
	StreetProps._bar(kit, Vector3(0.42, 0.1, -1.05), Vector3(-0.42, 1.8, -1.05), 0.03)
	return _commit(kit, 0.8)


## A round backyard trampoline: black mat, green pad, legs.
static func _trampoline() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.4, 0.42, 0.44))
	for k in 6:
		var a := TAU * k / 6.0
		var c := Vector3(cos(a) * 1.7, 0.0, sin(a) * 1.7)
		StreetProps._bar(kit, c, c + Vector3(0, 0.9, 0), 0.03)
	_col(kit, Color(0.1, 0.1, 0.1))
	_cyl(kit, 1.5, 0.86, 0.88, 20)
	_col(kit, Color(0.18, 0.55, 0.34))
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


# --- yards, parks, pitches, patios and cemeteries (TownDressing places most of these) ---

static func _yard_and_park_props() -> void:
	_meshes["waste_carts"] = _waste_carts()
	_shape("waste_carts", Vector3(0.3, 0.55, 0.38), 0.55)
	_meshes["compost_cart"] = _waste_carts(true)
	_shape("compost_cart", Vector3(0.3, 0.55, 0.38), 0.55)
	_meshes["patio_set"] = _patio(true)
	_shape("patio_set", Vector3(0.5, 0.37, 0.5), 0.37)
	_meshes["patio_table"] = _patio(false)
	_shape("patio_table", Vector3(0.5, 0.37, 0.5), 0.37)
	_meshes["soccer_goal"] = _soccer_goal()
	_shape("soccer_goal", Vector3(0.06, 1.05, 0.06), 1.05, -3.2)
	_shape("soccer_goal", Vector3(0.06, 1.05, 0.06), 1.05, 3.2)
	_meshes["basketball_hoop"] = _basketball_hoop()
	_shape("basketball_hoop", Vector3(0.1, 1.6, 0.1), 1.6, 0.0, 0.9)
	_meshes["tennis_net"] = _tennis_net()
	_shape("tennis_net", Vector3(6.4, 0.5, 0.05), 0.5)
	_meshes["headstone"] = _headstone(Color(0.55, 0.55, 0.54), false)
	_meshes["headstone_dark"] = _headstone(Color(0.17, 0.17, 0.18), false)
	_meshes["marble_tablet"] = _headstone(Color(0.78, 0.77, 0.73), true)
	for k: String in ["headstone", "headstone_dark", "marble_tablet"]:
		_shape(k, Vector3(0.32, 0.4, 0.1), 0.4)
	_meshes["iron_arch"] = _iron_arch(Materials.get_shared())
	for x: float in [-ARCH_HALF, ARCH_HALF]:
		_shape("iron_arch", Vector3(0.32, 1.1, 0.32), 1.1, x)
	_meshes["swan_lamp"] = _swan_lamp(Materials.get_shared())
	_shape("swan_lamp", Vector3(0.1, 1.9, 0.1), 1.9)


## Waste Watch at the end of the driveway on a black-cart week: the black
## cart, lid shut, handles to the back, and the recycling beside it in two
## translucent blue bags (there's no blue cart on PEI: IWMC kept the bags).
## `compost` is the other week: the green cart on its own.
static func _waste_carts(compost := false) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.18, 0.42, 0.2) if compost else Color(0.07, 0.07, 0.08))
	_box(kit, Vector3(-0.29, 0.06, -0.36), Vector3(0.29, 1.0, 0.34))
	_box(kit, Vector3(-0.31, 1.0, -0.4), Vector3(0.31, 1.06, 0.37))
	_box(kit, Vector3(-0.27, 0.98, 0.34), Vector3(0.27, 1.02, 0.42))
	_col(kit, Color(0.05, 0.05, 0.05))
	for sx: float in [-0.25, 0.25]:
		_box(kit, Vector3(sx - 0.04, 0.0, 0.22), Vector3(sx + 0.04, 0.16, 0.38))
	if not compost:
		_col(kit, Color(0.3, 0.52, 0.85))
		for b: Array in [[Vector3(0.72, 0.0, -0.05), 0.3], [Vector3(1.2, 0.0, 0.1), 0.26]]:
			var c: Vector3 = b[0]
			var r: float = b[1]
			var start := kit.verts.size()
			StreetProps._lathe(kit, [[0.0, 0.0], [r, 0.0], [r * 1.1, r * 1.0], [r * 0.8, r * 1.8], [0.06, r * 2.1], [0.0, r * 2.3]], 7)
			_shift(kit, start, c)
	return _commit(kit, 0.6)


## A café table on a pedestal with four chairs, and with `umbrella` a
## cream market umbrella over it on a pole.
static func _patio(umbrella: bool) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.12, 0.12, 0.12))
	_cyl(kit, 0.04, 0.0, 0.72, 6)
	_cyl(kit, 0.25, 0.0, 0.03, 8)
	_cyl(kit, 0.42, 0.72, 0.75, 12)
	for k in 4:
		var a := TAU * k / 4.0 + PI / 4.0
		var c := Vector3(cos(a), 0.0, sin(a)) * 0.72
		var back := Vector3(cos(a), 0.0, sin(a)) * 0.2
		var side := Vector3(-sin(a), 0.0, cos(a)) * 0.2
		_col(kit, Color(0.12, 0.12, 0.12))
		for corner: Vector3 in [back + side, back - side, -back + side, -back - side]:
			StreetProps._bar(kit, c + corner, c + corner + Vector3.UP * 0.45, 0.015)
		_col(kit, Color(0.22, 0.22, 0.22))
		kit.quad(c - back - side + Vector3.UP * 0.45, c - back + side + Vector3.UP * 0.45, c + back + side + Vector3.UP * 0.45, c + back - side + Vector3.UP * 0.45, Vector3.UP)
		kit.quad(c + back - side + Vector3.UP * 0.45, c + back + side + Vector3.UP * 0.45, c + back * 1.1 + side + Vector3.UP * 0.85, c + back * 1.1 - side + Vector3.UP * 0.85, -back.normalized())
	if umbrella:
		_col(kit, Color(0.85, 0.85, 0.82))
		_cyl(kit, 0.02, 0.75, 2.35, 6)
		_col(kit, Color(0.9, 0.86, 0.74))
		for k in 8:
			var a0 := TAU * k / 8.0
			var a1 := TAU * (k + 1) / 8.0
			var p0 := Vector3(cos(a0), 0.0, sin(a0)) * 1.25 + Vector3.UP * 1.95
			var p1 := Vector3(cos(a1), 0.0, sin(a1)) * 1.25 + Vector3.UP * 1.95
			var top := Vector3.UP * 2.35
			var nn := (p0 - top).cross(p1 - top).normalized()
			if nn.y < 0.0:
				nn = -nn
			kit.tri(p0, top, p1, nn)
			kit.tri(p1, top, p0, -nn)
	return _commit(kit, 0.7)


## A white soccer goal, mouth to the front: posts, crossbar and the frame
## the net hangs from (the net itself is too fine to draw).
static func _soccer_goal() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.93, 0.93, 0.92))
	for x: float in [-3.2, 3.2]:
		StreetProps._bar(kit, Vector3(x, 0.0, 0.0), Vector3(x, 2.15, 0.0), 0.06)
		StreetProps._bar(kit, Vector3(x, 2.1, 0.0), Vector3(x, 0.0, 1.6), 0.025)
		StreetProps._bar(kit, Vector3(x, 0.03, 0.0), Vector3(x, 0.03, 1.6), 0.025)
	StreetProps._bar(kit, Vector3(-3.25, 2.12, 0.0), Vector3(3.25, 2.12, 0.0), 0.06)
	StreetProps._bar(kit, Vector3(-3.2, 0.03, 1.6), Vector3(3.2, 0.03, 1.6), 0.025)
	_col(kit, Color(0.8, 0.8, 0.8))
	for k in 9:
		var x := -3.2 + k * 0.8
		StreetProps._bar(kit, Vector3(x, 2.1, 0.0), Vector3(x, 0.03, 1.6), 0.006)
	return _commit(kit, 0.6)


## A park basketball hoop: a steel pole set back behind the baseline with
## an arm out to a white backboard and an orange rim, facing the court.
static func _basketball_hoop() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.3, 0.32, 0.33))
	StreetProps._bar(kit, Vector3(0, 0, 0.9), Vector3(0, 3.35, 0.9), 0.06)
	StreetProps._bar(kit, Vector3(0, 3.3, 0.9), Vector3(0, 3.3, 0.05), 0.05)
	_col(kit, Color(0.93, 0.93, 0.92))
	_box(kit, Vector3(-0.9, 2.9, -0.02), Vector3(0.9, 3.95, 0.02))
	_col(kit, Color(0.1, 0.1, 0.1))
	_box(kit, Vector3(-0.3, 3.05, -0.03), Vector3(0.3, 3.5, -0.021))
	_col(kit, Color(0.9, 0.4, 0.08))
	for k in 10:
		var a0 := TAU * k / 10.0
		var a1 := TAU * (k + 1) / 10.0
		var c := Vector3(0, 3.05, -0.25)
		StreetProps._bar(kit, c + Vector3(cos(a0), 0, sin(a0)) * 0.23, c + Vector3(cos(a1), 0, sin(a1)) * 0.23, 0.012)
	return _commit(kit, 0.5)


## A tennis net across a court along local X: two green posts, the dark net
## (both faces) and its white tape.
static func _tennis_net() -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.12, 0.3, 0.18))
	for x: float in [-6.4, 6.4]:
		var start := kit.verts.size()
		_cyl(kit, 0.04, 0.0, 1.07, 6)
		_shift(kit, start, Vector3(x, 0, 0))
	_col(kit, Color(0.1, 0.1, 0.1))
	kit.quad(Vector3(-6.35, 0.05, 0), Vector3(6.35, 0.05, 0), Vector3(6.35, 0.93, 0), Vector3(-6.35, 0.93, 0), Vector3(0, 0, 1))
	kit.quad(Vector3(6.35, 0.05, 0), Vector3(-6.35, 0.05, 0), Vector3(-6.35, 0.93, 0), Vector3(6.35, 0.93, 0), Vector3(0, 0, -1))
	_col(kit, Color(0.95, 0.95, 0.94))
	_box(kit, Vector3(-6.35, 0.93, -0.02), Vector3(6.35, 1.0, 0.02))
	return _commit(kit, 0.8)


## A headstone, inscription to the front: a granite slab with a rounded
## top on a low base, or (`tablet`) an old thin marble tablet, taller and
## plain. Scaled per stone where it's placed.
static func _headstone(c: Color, tablet: bool) -> ArrayMesh:
	var kit := _kit()
	_col(kit, c)
	if tablet:
		_box(kit, Vector3(-0.24, -0.1, -0.035), Vector3(0.24, 0.72, 0.035))
		kit.quad(Vector3(-0.24, 0.72, -0.035), Vector3(0.24, 0.72, -0.035), Vector3(0.12, 0.8, -0.035), Vector3(-0.12, 0.8, -0.035), Vector3(0, 0, -1))
		kit.quad(Vector3(0.24, 0.72, 0.035), Vector3(-0.24, 0.72, 0.035), Vector3(-0.12, 0.8, 0.035), Vector3(0.12, 0.8, 0.035), Vector3(0, 0, 1))
		kit.quad(Vector3(-0.12, 0.8, -0.035), Vector3(0.12, 0.8, -0.035), Vector3(0.12, 0.8, 0.035), Vector3(-0.12, 0.8, 0.035), Vector3.UP)
		return _commit(kit, 0.8)
	_box(kit, Vector3(-0.36, -0.1, -0.13), Vector3(0.36, 0.1, 0.13))
	_box(kit, Vector3(-0.3, 0.1, -0.08), Vector3(0.3, 0.62, 0.08))
	# The rounded top: a half-octagon, front and back, and its edge.
	var prev := Vector3(-0.3, 0.62, 0)
	for k in range(1, 5):
		var a := PI - PI * k / 4.0
		var p := Vector3(cos(a) * 0.3, 0.62 + sin(a) * 0.14, 0)
		kit.tri(Vector3(0, 0.62, -0.08), prev + Vector3(0, 0, -0.08), p + Vector3(0, 0, -0.08), Vector3(0, 0, -1))
		kit.tri(Vector3(0, 0.62, 0.08), p + Vector3(0, 0, 0.08), prev + Vector3(0, 0, 0.08), Vector3(0, 0, 1))
		var up := ((prev + p) * 0.5 - Vector3(0, 0.62, 0)).normalized()
		kit.quad(prev + Vector3(0, 0, 0.08), p + Vector3(0, 0, 0.08), p + Vector3(0, 0, -0.08), prev + Vector3(0, 0, -0.08), up)
		prev = p
	return _commit(kit, 0.8)


## Half the span between an iron arch's piers (m).
const ARCH_HALF := 4.75

## The black iron arch over each end of Victoria Row (CBC photos): two grey
## stone piers 9.5 m apart, an iron post up from each, and two curved
## bands between them with upright bars, a row of bulbs along the top
## (lit). Spans local X; the name board is a wall_sign placed on its crown
## (6.1 m up), so the words stay text. Faces -Z, though it reads the same
## from both sides.
static func _iron_arch(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	for x: float in [-ARCH_HALF, ARCH_HALF]:
		_col(kit, Color(0.54, 0.52, 0.47))
		_box(kit, Vector3(x - 0.32, 0.0, -0.32), Vector3(x + 0.32, 2.1, 0.32))
		_col(kit, Color(0.6, 0.58, 0.53))
		_box(kit, Vector3(x - 0.38, 2.1, -0.38), Vector3(x + 0.38, 2.25, 0.38))
		_col(kit, Color(0.05, 0.05, 0.05))
		StreetProps._bar(kit, Vector3(x, 2.25, 0), Vector3(x, 4.6, 0), 0.07)
		_cyl_at(kit, Vector3(x, 4.6, 0), 0.11, 0.22)
	_col(kit, Color(0.05, 0.05, 0.05))
	var bulbs: Array[Vector3] = []
	var steps := 16
	for band: float in [0.0, 0.45]:
		for k in steps:
			var a := _arch_pt(float(k) / steps, band)
			var b := _arch_pt(float(k + 1) / steps, band)
			StreetProps._bar(kit, a, b, 0.045)
	for k in range(1, steps):
		var lo := _arch_pt(float(k) / steps, 0.0)
		var hi := _arch_pt(float(k) / steps, 0.45)
		StreetProps._bar(kit, lo, hi, 0.018)
		if k % 2 == 0:
			bulbs.append(hi + Vector3.UP * 0.08)
	var mesh := _commit(kit, 0.5)
	var lit := MeshKit.new()
	for c: Vector3 in bulbs:
		for f: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1)]:
			lit.quad(c + Vector3(-0.06, -0.06, f.z * 0.05), c + Vector3(0.06, -0.06, f.z * 0.05), c + Vector3(0.06, 0.06, f.z * 0.05), c + Vector3(-0.06, 0.06, f.z * 0.05), f)
	lit.commit(mesh, mats.glow(Color(1.0, 0.9, 0.7), 1.2))
	return mesh


## A point on the arch: t from 0 (west post top) to 1 (east), `up` above
## the lower band. A flat curve, 4.6 m at the posts and 5.6 in the middle.
static func _arch_pt(t: float, up: float) -> Vector3:
	var x := lerpf(-ARCH_HALF, ARCH_HALF, t)
	return Vector3(x, 4.6 + sin(t * PI) * 1.0 + up, 0.0)


static func _cyl_at(kit: MeshKit, c: Vector3, r: float, h: float) -> void:
	var start := kit.verts.size()
	_cyl(kit, r, 0.0, h, 8)
	_shift(kit, start, c)


## The white swan-neck lamp of Confederation Landing and the marina
## promenade (CBC photos): a white post that curves over at the top into a
## neck, with a white globe hanging from its end (lit). The neck reaches
## to local -Z.
static func _swan_lamp(mats: Materials) -> ArrayMesh:
	var kit := _kit()
	_col(kit, Color(0.92, 0.92, 0.9))
	StreetProps._lathe(kit, [[0.0, 0.0], [0.14, 0.0], [0.14, 0.35], [0.08, 0.45], [0.065, 3.6], [0.0, 3.6]], 10)
	var prev := Vector3(0, 3.55, 0)
	for k in range(1, 8):
		var a := PI * 0.5 * k / 7.0
		var p := Vector3(0, 3.55 + sin(a) * 0.55, -(1.0 - cos(a)) * 0.55 - k * 0.04)
		StreetProps._bar(kit, prev, p, 0.05)
		prev = p
	var tip := prev + Vector3(0, -0.05, -0.12)
	StreetProps._bar(kit, prev, tip, 0.045)
	var mesh := _commit(kit, 0.5)
	var glass := MeshKit.new()
	var start := glass.verts.size()
	StreetProps._lathe(glass, [[0.0, -0.36], [0.12, -0.33], [0.18, -0.2], [0.17, -0.08], [0.06, 0.0], [0.0, 0.0]], 10)
	_shift(glass, start, tip)
	glass.commit(mesh, mats.glow(Color(1.0, 0.95, 0.85), 1.0))
	return mesh

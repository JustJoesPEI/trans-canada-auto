class_name BusStopSigns
extends RefCounted
## The bus stops' signs (TransitStops), built per chunk by StreetProps
## (full-detail chunks only): at each curb of a stop with a sidewalk, a grey
## pole with a blue Charlatown Transit plate, a white bus on it, facing up
## and down the street so a driver (or a bus) sees it coming.
##
## One cached mesh (vertex colours, one shared material, automatic LODs),
## drawn through TiledMulti like the hydrants, and only close by: further
## off it's a line a few pixels long. A thin pole to bump into.

## Drawn this close (m).
const DRAW_DISTANCE := 160.0
const POLE_HEIGHT := 2.75

static var _ready_shared := false
static var _mesh: ArrayMesh
static var _shape: CylinderShape3D


static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	_mesh = _make_sign()
	_shape = CylinderShape3D.new()
	_shape.radius = 0.05
	_shape.height = POLE_HEIGHT


static func build(props: StreetProps, root: Node3D) -> void:
	var ts := TransitStops.current
	if ts == null or ts.net != props.net or _mesh == null:
		return
	var xforms: Array = []
	var body: StaticBody3D = null
	for st: Dictionary in ts.stops:
		for side: int in st["sides"]:
			var p: Vector2 = st["sign"][side]
			if not props.inside_area(p) or props.data.erased(p):
				continue
			var at := props.terrain.at(p, RoadNetwork.SIDEWALK_HEIGHT)
			var dir: Vector2 = st["dir"]
			# The plate's faces look up and down the street.
			xforms.append(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), at))
			if body == null:
				body = StaticBody3D.new()
				body.name = "BusStopPoles"
				body.collision_layer = Layers.SOLID
				body.collision_mask = 0
			var cs := CollisionShape3D.new()
			cs.shape = _shape
			cs.position = at + Vector3.UP * POLE_HEIGHT * 0.5
			body.add_child(cs)
	if xforms.is_empty():
		return
	TiledMulti.add(root, "BusStopSigns", _mesh, xforms, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, DRAW_DISTANCE)
	root.add_child(body)


## Pole, blue plate (faces along local z), a white bus on each face.
static func _make_sign() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.use_color = true
	kit.color = Color(0.55, 0.57, 0.58).srgb_to_linear()
	StreetClutter._cube(kit, Vector3(0.0, POLE_HEIGHT * 0.5, 0.0), Vector3(0.035, POLE_HEIGHT * 0.5, 0.035))
	var top := POLE_HEIGHT - 0.06
	var plate_c := Vector3(0.0, top - 0.3, 0.0)
	kit.color = Color(0.07, 0.25, 0.62).srgb_to_linear()
	StreetClutter._cube(kit, plate_c, Vector3(0.23, 0.3, 0.015))
	for face: float in [1.0, -1.0]:
		var z := 0.0165 * face
		var n := Vector3(0.0, 0.0, face)
		# White band at the top (where the route numbers would be read),
		# and the bus: body, dark windows, wheels.
		kit.color = Color(0.95, 0.95, 0.93).srgb_to_linear()
		_flat(kit, plate_c + Vector3(0.0, 0.2, z), Vector2(0.19, 0.055), n)
		_flat(kit, plate_c + Vector3(0.0, -0.06, z), Vector2(0.15, 0.1), n)
		kit.color = Color(0.08, 0.1, 0.14).srgb_to_linear()
		_flat(kit, plate_c + Vector3(0.0, -0.02, z * 1.06), Vector2(0.12, 0.035), n)
		for x: float in [-0.085, 0.085]:
			_flat(kit, plate_c + Vector3(x, -0.165, z * 1.06), Vector2(0.03, 0.025), n)
	return ModelLod.finish(kit.commit(null, Materials.get_shared().vertex_colour(0.5)))


## A flat rectangle centred at c, half size h (x, y), facing n (±z).
static func _flat(kit: MeshKit, c: Vector3, h: Vector2, n: Vector3) -> void:
	var u := Vector3(h.x, 0.0, 0.0) * n.z
	var v := Vector3(0.0, h.y, 0.0)
	kit.quad(c - u - v, c + u - v, c + u + v, c - u + v, n)

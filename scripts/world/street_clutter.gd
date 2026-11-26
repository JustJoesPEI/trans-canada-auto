class_name StreetClutter
extends RefCounted
## Small street furniture built per chunk by StreetProps (full-detail chunks
## only): a fire hydrant at the curb every HYDRANT_SPACING metres on the
## left side of every ordinary street. (Parked cars and power lines are
## StreetProps' own _curb_parking and _power_lines.)

const HYDRANT_SPACING := 95.0
## Hydrants are only drawn this close (metres); further off they're specks.
const DRAW_DISTANCE := 150.0

static var _ready_shared := false
static var _hydrant_mesh: ArrayMesh
static var _hydrant_shape: CylinderShape3D

var props: StreetProps


static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	_hydrant_mesh = _make_hydrant()
	ShadowProxy.for_mesh(_hydrant_mesh, ShadowProxy.Shape.ROUND)
	_hydrant_shape = CylinderShape3D.new()
	_hydrant_shape.radius = 0.18
	_hydrant_shape.height = 0.9


func _init(owner: StreetProps) -> void:
	props = owner


func build(root: Node3D) -> void:
	var net := props.net
	var hydrants: Array = []
	var body := StaticBody3D.new()
	body.name = "Hydrants"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for e in net.edges_near(props.rect):
		if e.is_highway() or e.bridge or e.roundabout or e.walk(-1) <= 0.5:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 12.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 8.0
		if stop <= start:
			continue
		var line := net.side_line(e, -1, RoadNetwork.Level.PROP)
		var scale := RoadNetwork.polyline_length(line) / e.length
		var d := start
		while d < stop:
			var sp: Array = RoadNetwork.sample(line, d * scale)
			# Not in another street or junction, across a driveway, or where
			# the map editor erased it.
			if props.inside_area(sp[0]) and props.net.clear_of_roads(sp[0], 0.2) \
					and not props.data.on_service_road(sp[0]) and not props.data.erased(sp[0]):
				var at := props.terrain.at(sp[0], RoadNetwork.SIDEWALK_HEIGHT)
				hydrants.append(Transform3D(Basis(Vector3.UP, d), at))
				var cs := CollisionShape3D.new()
				cs.shape = _hydrant_shape
				cs.position = at + Vector3.UP * 0.45
				body.add_child(cs)
			d += HYDRANT_SPACING
	if hydrants.is_empty():
		body.free()
		return
	# A hydrant's shadow is a short stub: an eight-sided prism within 40 m.
	ShadowProxy.add(root, "HydrantMeshes", _hydrant_mesh, hydrants, DRAW_DISTANCE,
		ShadowProxy.for_mesh(_hydrant_mesh, ShadowProxy.Shape.ROUND), 40.0)
	Breakaway.mark_shapes(body, "hydrant", root)
	root.add_child(body)


## A fire hydrant: red barrel, yellow bonnet and side caps.
static func _make_hydrant() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.use_color = true
	kit.color = Color(0.62, 0.08, 0.06).srgb_to_linear()
	StreetProps._lathe(kit, [[0.0, 0.0], [0.17, 0.0], [0.17, 0.06], [0.12, 0.08], [0.12, 0.58], [0.15, 0.62], [0.0, 0.62]], 10)
	kit.color = Color(0.85, 0.66, 0.1).srgb_to_linear()
	StreetProps._lathe(kit, [[0.0, 0.62], [0.14, 0.62], [0.12, 0.72], [0.05, 0.8], [0.03, 0.86], [0.0, 0.86]], 10)
	for side: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK]:
		_cube(kit, side * 0.15 + Vector3(0, 0.42, 0), Vector3(0.05, 0.05, 0.05))
	return ModelLod.finish(kit.commit(null, Materials.get_shared().vertex_colour(0.5)))


static func _cube(kit: MeshKit, c: Vector3, h: Vector3) -> void:
	var ax := [Vector3(h.x, 0, 0), Vector3(0, h.y, 0), Vector3(0, 0, h.z)]
	for i in 3:
		for s: float in [1.0, -1.0]:
			var n: Vector3 = ax[i].normalized() * s
			var u: Vector3 = ax[(i + 1) % 3]
			var v: Vector3 = ax[(i + 2) % 3]
			var f: Vector3 = c + ax[i] * s
			kit.quad(f - u - v, f + u - v, f + u + v, f - u + v, n)

class_name StreetClutter
extends RefCounted
## The everyday clutter that makes a street look lived in: wooden utility
## poles with sagging wires between them, and cars parked along the curbs.
## Built per chunk by StreetProps (full-detail chunks only).
##
## Poles run down one side of every ordinary street outside the downtown core
## (where the wires are buried), one every POLE_SPACING metres, with three
## power lines on the crossarm and a lower phone/cable line, sagging between
## poles. Cars park along the curb of streets wide enough for a parking lane,
## about every other space taken. Every random choice is seeded by the street,
## so the town is the same every run.

const POLE_SPACING := 38.0
const POLE_H := 10.5
const CORE_R := 380.0 ## metres from the origin with no overhead wires
const CAR_SLOT := 6.4
const PARK_FROM_CURB := 1.15 ## car's middle, in from the curb line
const PARK_MIN_HALF_WIDTH := 4.2 ## street half width to park on one side
const PARK_BOTH_HALF_WIDTH := 5.2 ## ...and on both sides
const PARKED_PAINT := ["#b9bcbf", "#64686d", "#ebebe8", "#1c1d1f", "#2b3b57", "#6f2421", "#3e4a3d", "#9a958c"]

static var _ready_shared := false
static var _pole_mesh: ArrayMesh
static var _wire_mat: StandardMaterial3D
static var _pole_shape: CylinderShape3D
static var _car_shape: BoxShape3D
## [model id, paint index] -> body mesh; model id -> wheel mesh.
static var _bodies := {}
static var _wheels := {}
static var _models: Array = []

var props: StreetProps


static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	_pole_mesh = _make_pole()
	_wire_mat = StandardMaterial3D.new()
	_wire_mat.albedo_color = Color(0.06, 0.06, 0.06)
	_wire_mat.roughness = 0.6
	_wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pole_shape = CylinderShape3D.new()
	_pole_shape.radius = 0.16
	_pole_shape.height = POLE_H
	_car_shape = BoxShape3D.new()
	_car_shape.size = Vector3(1.8, 1.4, 4.5)
	_models = CarModels.MODELS.keys()
	for id: String in _models:
		var shape: Dictionary = CarModels.MODELS[id]["shape"]
		for k in PARKED_PAINT.size():
			_bodies[[id, k]] = CarBuilder.new(shape, Color.from_string(PARKED_PAINT[k], Color.GRAY)).make_body()
		_wheels[id] = CarBuilder.wheel_mesh(float(shape["wheel_radius"]), float(shape["wheel_width"]))


func _init(owner: StreetProps) -> void:
	props = owner


func build(root: Node3D) -> void:
	var net := props.net
	var poles: Array[Transform3D] = []
	var wires := MeshKit.new()
	var cars := {} # [model, paint] -> Array[Transform3D]
	var wheels := {} # model -> Array[Transform3D]
	var body := StaticBody3D.new()
	body.name = "Clutter"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for e in net.edges_near(props.rect):
		if e.is_highway() or e.bridge or e.roundabout:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 8.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 8.0
		if stop - start < 6.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(e.index * 7919 + 13)
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		# Overhead lines on one side, outside the downtown core.
		if mid.length() > CORE_R and e.walk(1) > 0.5:
			_pole_line(e, start, stop, poles, wires, body)
		# Parked cars on wide enough streets that have sidewalks.
		if e.half_width >= PARK_MIN_HALF_WIDTH and e.lanes <= 2:
			for side: int in [1, -1]:
				if e.walk(side) < 1.0 or (side < 0 and e.half_width < PARK_BOTH_HALF_WIDTH):
					continue
				_park(e, side, start, stop, rng, cars, wheels, body)
	if not poles.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _pole_mesh
		mm.instance_count = poles.size()
		for i in poles.size():
			mm.set_instance_transform(i, poles[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "UtilityPoles"
		mmi.multimesh = mm
		root.add_child(mmi)
	if not wires.is_empty():
		var wi := MeshInstance3D.new()
		wi.name = "Wires"
		wi.mesh = wires.commit(null, _wire_mat)
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(wi)
	for key: Array in cars:
		_multi(root, "ParkedCars", _bodies[key], cars[key])
	for id: String in wheels:
		_multi(root, "ParkedWheels", _wheels[id], wheels[id])
	if body.get_child_count() > 0:
		root.add_child(body)
	else:
		body.free()


func _pole_line(e: RoadNetwork.RoadEdge, start: float, stop: float, poles: Array[Transform3D], wires: MeshKit, body: StaticBody3D) -> void:
	var net := props.net
	var line := net.side_line(e, 1, RoadNetwork.Level.PROP)
	var scale := RoadNetwork.polyline_length(line) / e.length
	var count := maxi(1, int(ceil((stop - start) / POLE_SPACING)))
	var step := (stop - start) / count
	var tops: Array[Array] = [] # per pole: [arm left, arm right, middle, cable]
	for i in count + 1:
		var d := start + i * step
		var sp: Array = RoadNetwork.sample(line, d * scale)
		var at: Vector2 = sp[0]
		if not props.inside_area(at):
			tops.append([])
			continue
		var dir: Vector2 = sp[1]
		var yaw := StreetProps.yaw_along(Vector2(-dir.y, dir.x))
		# A little lean and twist, as real poles have.
		var lean := Basis(Vector3(dir.x, 0, dir.y), deg_to_rad(sin(d * 0.7) * 1.2))
		var basis := lean * Basis(Vector3.UP, yaw)
		var base := props.terrain.at(at, RoadNetwork.SIDEWALK_HEIGHT - 0.3)
		poles.append(Transform3D(basis, base))
		var cs := CollisionShape3D.new()
		cs.shape = _pole_shape
		cs.position = base + Vector3(0, POLE_H * 0.5, 0)
		body.add_child(cs)
		var across := basis * Vector3(1, 0, 0)
		var top := base + basis * Vector3(0, POLE_H - 0.5, 0)
		tops.append([top - across * 0.95 + Vector3.UP * 0.12, top + across * 0.95 + Vector3.UP * 0.12, top + Vector3.UP * 0.62, base + basis * Vector3(0, 6.6, 0) + across * 0.17])
	for i in tops.size() - 1:
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		if a.is_empty() or b.is_empty():
			continue
		for k in 4:
			_wire(wires, a[k], b[k], 0.012 if k < 3 else 0.02, 0.35 + 0.1 * k)


## A sagging wire from a to b: a few straight pieces along a catenary-ish
## curve, each a thin cross of two quads so it shows from any side.
static func _wire(kit: MeshKit, a: Vector3, b: Vector3, r: float, sag: float) -> void:
	var segs := 8
	var prev := a
	for s in range(1, segs + 1):
		var f := float(s) / segs
		var p := a.lerp(b, f) - Vector3.UP * sag * 4.0 * f * (1.0 - f)
		var d := (p - prev).normalized()
		var side := d.cross(Vector3.UP).normalized() * r
		var up := side.cross(d).normalized() * r
		kit.quad(prev - side, p - side, p + side, prev + side, up.normalized())
		kit.quad(prev - up, p - up, p + up, prev + up, side.normalized())
		prev = p


func _park(e: RoadNetwork.RoadEdge, side: int, start: float, stop: float, rng: RandomNumberGenerator, cars: Dictionary, wheels: Dictionary, body: StaticBody3D) -> void:
	var line := props.net.side_line(e, side, RoadNetwork.Level.CURB)
	var scale := RoadNetwork.polyline_length(line) / e.length
	var d := start + rng.randf() * 3.0
	while d < stop - CAR_SLOT * 0.5:
		var taken := rng.randf() < 0.5
		if taken:
			var sp: Array = RoadNetwork.sample(line, d * scale)
			var dir: Vector2 = sp[1]
			# Into the street from the curb line; right-hand traffic, so a car
			# on the right side (+1) faces along a->b and on the left the other way.
			var inward := -Vector2(-dir.y, dir.x) * float(side)
			var at: Vector2 = (sp[0] as Vector2) + inward * (PARK_FROM_CURB + rng.randf_range(-0.08, 0.12))
			if props.inside_area(at):
				var face := dir * float(side)
				var basis := Basis(Vector3.UP, StreetProps.yaw_facing(-face) + rng.randf_range(-0.03, 0.03))
				var origin := props.terrain.at(at, 0.0)
				var id: String = _models[rng.randi() % _models.size()]
				var key := [id, rng.randi() % PARKED_PAINT.size()]
				if not cars.has(key):
					cars[key] = []
				cars[key].append(Transform3D(basis, origin))
				var shape: Dictionary = CarModels.MODELS[id]["shape"]
				var wr := float(shape["wheel_radius"])
				if not wheels.has(id):
					wheels[id] = []
				for z: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
					for s: float in [-1.0, 1.0]:
						var wb := basis * Basis.from_scale(Vector3(s, 1, 1))
						wheels[id].append(Transform3D(wb, origin + basis * Vector3(float(shape["track_half"]) * s, wr, z)))
				var cs := CollisionShape3D.new()
				cs.shape = _car_shape
				cs.transform = Transform3D(basis, origin + Vector3.UP * 0.75)
				body.add_child(cs)
		d += CAR_SLOT


static func _multi(root: Node3D, label: String, mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	root.add_child(mmi)


## A creosoted wooden pole with a crossarm, three insulators and, on some, a
## grey transformer can. Base at y = 0, crossarm across x.
static func _make_pole() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.use_color = true
	kit.color = Color(0.25, 0.2, 0.16).srgb_to_linear()
	StreetProps._lathe(kit, [[0.0, 0.0], [0.15, 0.0], [0.13, POLE_H * 0.5], [0.11, POLE_H], [0.0, POLE_H]], 8)
	kit.color = Color(0.3, 0.25, 0.2).srgb_to_linear()
	_cube(kit, Vector3(0, POLE_H - 0.5, 0), Vector3(1.05, 0.05, 0.05))
	# Diagonal braces under the arm.
	_cube(kit, Vector3(0.3, POLE_H - 0.8, 0.0), Vector3(0.3, 0.02, 0.02), Basis(Vector3.BACK, 0.75))
	_cube(kit, Vector3(-0.3, POLE_H - 0.8, 0.0), Vector3(0.3, 0.02, 0.02), Basis(Vector3.BACK, -0.75))
	kit.color = Color(0.55, 0.6, 0.58).srgb_to_linear()
	for x: float in [-0.95, 0.95]:
		_cube(kit, Vector3(x, POLE_H - 0.4, 0), Vector3(0.04, 0.07, 0.04))
	_cube(kit, Vector3(0, POLE_H + 0.05, 0), Vector3(0.04, 0.07, 0.04))
	# A transformer can and a cable box lower down.
	kit.color = Color(0.5, 0.52, 0.53).srgb_to_linear()
	_cube(kit, Vector3(0, POLE_H - 1.9, 0.33), Vector3(0.23, 0.38, 0.23))
	kit.color = Color(0.15, 0.15, 0.15).srgb_to_linear()
	_cube(kit, Vector3(0.17, 6.6, 0), Vector3(0.05, 0.15, 0.08))
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	return kit.commit(null, mat)


static func _cube(kit: MeshKit, c: Vector3, h: Vector3, b := Basis.IDENTITY) -> void:
	var ax := [b * Vector3(h.x, 0, 0), b * Vector3(0, h.y, 0), b * Vector3(0, 0, h.z)]
	for i in 3:
		for s: float in [1.0, -1.0]:
			var n: Vector3 = ax[i].normalized() * s
			var u: Vector3 = ax[(i + 1) % 3]
			var v: Vector3 = ax[(i + 2) % 3]
			var f: Vector3 = c + ax[i] * s
			kit.quad(f - u - v, f + u - v, f + u + v, f - u + v, n)

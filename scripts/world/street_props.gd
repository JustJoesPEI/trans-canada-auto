class_name StreetProps
extends RefCounted
## Street furniture and trees placed from the data, one chunk at a time:
##   * a street-name sign at every junction (real street names),
##   * stop signs where OSM maps highway=stop,
##   * traffic lights at junctions OSM marks with traffic signals,
##   * trees where OSM maps natural=tree (each crown its own node so the
##     camera can fade it), plus woods filled in where OSM maps a wood or
##     forest, a few trees in parks, and yard trees along residential streets
##     (lighter leafy crowns and spruces, drawn through MultiMeshes),
##   * black heritage lamp posts along downtown's sidewalks, and plain
##     street lights on wooden poles everywhere else.
## Benches and parked cars come in Milestone 3.
##
## The shared meshes are made once (prepare(), on the main thread) and every
## chunk reuses them, so chunks can be built on worker threads.

const SW_H := RoadNetwork.SIDEWALK_HEIGHT

var net: RoadNetwork
var data: StreetData
var terrain: Terrain
var rect: Rect2
var chunk: StreetData.Chunk
var lod := false
var _mats: Materials

# Shared meshes, built once by prepare().
static var _ready_shared := false
static var _pole: CylinderMesh
static var _blade: BoxMesh
static var _stop_face: CylinderMesh
static var _trunks: Array[ArrayMesh] = []
static var _crowns: Array[ArrayMesh] = []
static var _light_crowns: Array[ArrayMesh] = []
static var _spruces: Array[ArrayMesh] = []
static var _heritage_lamp: ArrayMesh
static var _street_light: ArrayMesh
static var _trunk_shape: CylinderShape3D
static var _lamp_shape: CylinderShape3D
static var _pole_shape: CylinderShape3D
static var _parked: Array[ArrayMesh] = [] ## one per model in PARKED_MODELS (see _parked_mesh)
static var _parked_shapes: Array[BoxShape3D] = []
## Only the curbside models are built up front; the rest (seen only on their
## dealers' lots) are built the first time a chunk needs one, on whichever
## chunk builder's thread gets there first, so this lock guards that.
static var _parked_lock := Mutex.new()
## A plain two-box stand-in for each parked model (body and cabin) that only
## casts the shadow: the real car is thousands of triangles, drawn again
## into every shadow cascade it's in, and the shadow on the street looks
## the same from a few dozen triangles.
static var _parked_shadows: Array[Mesh] = []
static var _utility_pole: ArrayMesh
static var _crossarm: ArrayMesh ## the top of a utility pole, for a street-light pole that carries the wires too
static var _wire: BoxMesh
static var _xwalk_board: QuadMesh ## the red CROSS X WALK board hung over the street
static var _xwalk_side: QuadMesh ## the white walking-figure sign on the posts
static var _xwalk_pole: CylinderMesh
static var _twin_light: ArrayMesh
static var _rock: ArrayMesh


## Builds the shared meshes. Call once on the main thread before any chunk.
static func prepare() -> void:
	if _ready_shared:
		return
	_ready_shared = true
	var mats := Materials.get_shared()
	_chain_link = ShaderMaterial.new()
	_chain_link.shader = load("res://shaders/chain_link.gdshader")
	_pole = CylinderMesh.new()
	_pole.top_radius = 0.045
	_pole.bottom_radius = 0.05
	_pole.height = 3.0
	_pole.radial_segments = 8
	_pole.material = mats.plain(Color(0.35, 0.37, 0.38), 0.5, 0.6)
	_blade = BoxMesh.new()
	_blade.size = Vector3(1.6, 0.3, 0.025)
	_blade.material = mats.plain(Color(0.08, 0.36, 0.2), 0.5)
	_stop_face = CylinderMesh.new()
	_stop_face.top_radius = 0.38
	_stop_face.bottom_radius = 0.38
	_stop_face.height = 0.03
	_stop_face.radial_segments = 8
	_stop_face.material = mats.plain(Color(0.75, 0.08, 0.07), 0.5)
	var bark: Material = mats.plain(Color(0.3, 0.26, 0.22), 0.95)
	if BuildingGenerator.facade_relief:
		var photo_bark := ShaderMaterial.new()
		photo_bark.shader = load("res://shaders/bark.gdshader")
		photo_bark.set_shader_parameter("bark", load("res://textures/foliage/bark.jpg"))
		bark = photo_bark
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/foliage.gdshader")
	var palette := [Color(0.22, 0.36, 0.15), Color(0.27, 0.41, 0.17), Color(0.19, 0.32, 0.15), Color(0.3, 0.4, 0.16)]
	var cards := ShaderMaterial.new()
	cards.shader = load("res://shaders/foliage_cards.gdshader")
	cards.set_shader_parameter("leaves", load("res://textures/foliage/leaf_cluster.png"))
	for v in 4:
		if BuildingGenerator.facade_relief:
			_crowns.append(_branchy_crown(v, palette[v], cards, bark, 7, 4, 1.0))
			_light_crowns.append(_branchy_crown(v + 10, palette[v], cards, bark, 5, 3, 1.25))
		else:
			_crowns.append(_crown_mesh(v, palette[v], leaves, 13 + v, 5, 7))
			_light_crowns.append(_crown_mesh(v + 10, palette[v], leaves, 5, 3, 5))
	for v in 3:
		_trunks.append(_trunk_mesh(v, bark, BuildingGenerator.facade_relief))
	var needles := [Color(0.12, 0.22, 0.13), Color(0.15, 0.25, 0.14), Color(0.11, 0.19, 0.12)]
	var needle_cards := ShaderMaterial.new()
	needle_cards.shader = cards.shader
	needle_cards.set_shader_parameter("leaves", load("res://textures/foliage/needle_branch.png"))
	for v in 3:
		if BuildingGenerator.facade_relief:
			_spruces.append(_card_spruce(v, needles[v], needle_cards, bark))
		else:
			_spruces.append(_spruce_mesh(v, needles[v], leaves, bark))
	_heritage_lamp = _lamp_mesh(mats)
	_lamp_shadow = null
	_lamp_shadow_stand_in() # made here, not on the worker threads that build chunks
	_street_light = _street_light_mesh(mats)
	_twin_light = _twin_light_mesh(mats)
	_rock = _rock_mesh(mats)
	_trunk_shape = CylinderShape3D.new()
	_trunk_shape.radius = 0.25
	_trunk_shape.height = 4.0
	_lamp_shape = CylinderShape3D.new()
	_lamp_shape.radius = 0.12
	_lamp_shape.height = 4.0
	_pole_shape = CylinderShape3D.new()
	_pole_shape.radius = 0.15
	_pole_shape.height = 8.0
	# The shared car materials, made here on the main thread so the chunk
	# builders' threads only ever read them.
	for kind: String in ["parked_paint", "gloss", "rough", "satin", "metal", "glass", "rubber"]:
		CarBuilder.material(kind)
	for v in PARKED_MODELS.size():
		var shape: Dictionary = CarModels.get_model(PARKED_MODELS[v])["shape"]
		_parked.append(null)
		_parked_shadows.append(null)
		if v < PARKED_ODDS.size():
			_parked_mesh(v)
		var box := BoxShape3D.new()
		box.size = Vector3(float(shape["width"]) - 0.05, float(shape["height"]) * 0.8, float(shape["length"]) - 0.1)
		_parked_shapes.append(box)
	_utility_pole = _utility_pole_mesh(mats, true)
	_crossarm = _utility_pole_mesh(mats, false)
	_wire = BoxMesh.new()
	_wire.size = Vector3(0.025, 0.025, 1.0)
	_wire.material = mats.plain(Color(0.06, 0.06, 0.06), 0.7)
	_xwalk_board = QuadMesh.new()
	_xwalk_board.size = Vector2(XWALK_BOARD_W, XWALK_BOARD_W * 0.25)
	_xwalk_board.material = _sign_material("res://textures/signs/crosswalk_overhead.png")
	_xwalk_side = QuadMesh.new()
	_xwalk_side.size = Vector2(0.6, 0.6)
	_xwalk_side.material = _sign_material("res://textures/signs/crosswalk_side.png")
	_xwalk_pole = CylinderMesh.new()
	_xwalk_pole.top_radius = 0.07
	_xwalk_pole.bottom_radius = 0.09
	_xwalk_pole.height = XWALK_POLE_H
	_xwalk_pole.radial_segments = 8
	_xwalk_pole.material = mats.plain(Color(0.62, 0.64, 0.64), 0.45, 0.6)
	# Built once and drawn by the hundred: indexed, with automatic LODs, so
	# the ones a little way off (and their shadows) cost a fraction
	# (docs/world_art.md, rule W1).
	for list: Array[ArrayMesh] in [_crowns, _light_crowns, _spruces, _trunks]:
		for i in list.size():
			list[i] = ModelLod.finish(list[i])
	_heritage_lamp = ModelLod.finish(_heritage_lamp)
	_street_light = ModelLod.finish(_street_light)
	_twin_light = ModelLod.finish(_twin_light)
	_rock = ModelLod.finish(_rock)
	_utility_pole = ModelLod.finish(_utility_pole)
	_crossarm = ModelLod.finish(_crossarm)
	if BuildingGenerator.facade_relief:
		StreetClutter.prepare()
	PlacedProps.prepare()
	PlacedSigns.prepare()


func _init(network: RoadNetwork, street_data: StreetData, ground: Terrain, area: Rect2, chunk_data: StreetData.Chunk, low_detail := false) -> void:
	terrain = ground
	net = network
	data = street_data
	rect = area
	chunk = chunk_data
	lod = low_detail
	_mats = Materials.get_shared()


func inside_area(p: Vector2) -> bool:
	return _inside(p)


func _inside(p: Vector2) -> bool:
	return p.x >= rect.position.x and p.x < rect.end.x and p.y >= rect.position.y and p.y < rect.end.y


## Junctions (3 or more streets) whose middle is in this chunk.
func _junctions() -> Array[String]:
	var out: Array[String] = []
	var seen := {}
	for e in net.edges_near(rect):
		for nid: String in [e.a, e.b]:
			if seen.has(nid):
				continue
			seen[nid] = true
			if net.degree(nid) >= 3 and _inside(net.nodes[nid]):
				out.append(nid)
	return out


func build() -> Node3D:
	var root := Node3D.new()
	root.name = "StreetProps"
	if not lod:
		_street_name_signs(root)
		_stop_signs(root)
		_traffic_signals(root)
		_overhead_crosswalks(root)
		_lamps(root)
		_power_lines(root)
		# Stalls first: the cars in busy lots park with the curbside ones.
		_parking_stalls(root)
		_curb_parking(root)
		_dealer_lots(root)
		_fences(root)
		_median_lights(root)
		_basins(root)
		_gantries(root)
		if BuildingGenerator.facade_relief:
			StreetClutter.new(self).build(root)
		PlacedProps.new(self).build(root)
		EditLines.new(self).build(root)
		PlacedSigns.new(self).build(root)
	_trees(root)
	return root


# --- fences -----------------------------------------------------------------------------

static var _chain_link: ShaderMaterial

## Chain-link fences round mapped areas named in map_config.json "fences"
## (an oil terminal, a substation): galvanised posts every 3 m with a top
## rail, the wire mesh between, and strands of barbed wire on top. The fence
## follows the area's outline, inset_m inside it, with a gap wherever a
## street or driveway crosses. Each chunk builds the stretch whose pieces
## have their middles inside it. Solid to cars and people.
func _fences(root: Node3D) -> void:
	var cfg: Dictionary = data.config.get("fences", {})
	if cfg.is_empty():
		return
	var fabric := MeshKit.new()
	var metal := MeshKit.new()
	var faces := PackedVector3Array()
	var rock_bank := MeshKit.new()
	var rocks: Array[Transform3D] = []
	for a in chunk.areas:
		var name := str(a.tags.get("name", ""))
		if name == "" or not cfg.has(name):
			continue
		var f: Dictionary = cfg[name]
		var h := float(f.get("height", 2.2))
		var barbed: bool = f.get("barbed", false)
		var riprap: Dictionary = f.get("riprap", {})
		var ring := a.ring
		if BuildingGenerator._signed_area(ring) < 0.0:
			ring = ring.duplicate()
			ring.reverse()
		var inset := float(f.get("inset_m", 0.0))
		if inset > 0.0:
			var moved := BuildingGenerator._offset_ring(ring, -inset)
			if not moved.is_empty():
				ring = moved
		for i in ring.size():
			var p0 := ring[i]
			var p1 := ring[(i + 1) % ring.size()]
			var length := p0.distance_to(p1)
			if length < 0.3:
				continue
			var pieces := maxi(1, int(ceil(length / 3.0)))
			for k in pieces:
				var q0 := p0.lerp(p1, float(k) / pieces)
				var q1 := p0.lerp(p1, float(k + 1) / pieces)
				var mid := (q0 + q1) * 0.5
				if not _inside(mid) or _on_road(mid, 0.3):
					continue
				var g0 := terrain.h2(q0)
				var g1 := terrain.h2(q1)
				var n := (q1 - q0).normalized()
				var n3 := Vector3(n.y, 0.0, -n.x)
				var u0 := float(i * 1000) + p0.distance_to(q0)
				var u1 := u0 + q0.distance_to(q1)
				fabric.quad(MeshKit.v3(q0, g0 + 0.05), MeshKit.v3(q1, g1 + 0.05), MeshKit.v3(q1, g1 + h), MeshKit.v3(q0, g0 + h), n3,
					Vector2(u0, 0.05), Vector2(u1, 0.05), Vector2(u1, h), Vector2(u0, h))
				faces.append_array(PackedVector3Array([MeshKit.v3(q0, g0 - 0.2), MeshKit.v3(q1, g1 - 0.2), MeshKit.v3(q1, g1 + h),
					MeshKit.v3(q0, g0 - 0.2), MeshKit.v3(q1, g1 + h), MeshKit.v3(q0, g0 + h)]))
				if not riprap.is_empty():
					var hit := net.nearest_on_streets(mid, float(riprap.get("within_m", 30.0)))
					if not hit.is_empty() and (hit["edge"] as RoadNetwork.RoadEdge).name == str(riprap.get("street", "")):
						_riprap(rock_bank, rocks, q0, q1, g0, g1, Vector3(n.y, 0.0, -n.x), riprap)
				var top := h + (0.45 if barbed else 0.05)
				for q: Array in [[q0, g0], [q1, g1]]:
					_bar(metal, MeshKit.v3(q[0], q[1] - 0.2), MeshKit.v3(q[0], q[1] + top), 0.03)
				_bar(metal, MeshKit.v3(q0, g0 + h), MeshKit.v3(q1, g1 + h), 0.02)
				if barbed:
					for y: float in [h + 0.15, h + 0.3, h + 0.45]:
						_bar(metal, MeshKit.v3(q0, g0 + y), MeshKit.v3(q1, g1 + y), 0.006)
	if fabric.verts.is_empty():
		return
	if not rock_bank.verts.is_empty():
		var bank := MeshInstance3D.new()
		bank.name = "Riprap"
		bank.mesh = rock_bank.commit(null, _mats.plain(Color(0.24, 0.24, 0.23), 0.95))
		root.add_child(bank)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _rock
		mm.instance_count = rocks.size()
		for i in rocks.size():
			mm.set_instance_transform(i, rocks[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "RiprapStones"
		mmi.multimesh = mm
		root.add_child(mmi)
	var mi := MeshInstance3D.new()
	mi.name = "Fences"
	mi.mesh = fabric.commit(null, _chain_link)
	metal.commit(mi.mesh as ArrayMesh, _mats.plain(Color(0.46, 0.48, 0.48), 0.45, 0.6))
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "FenceCollision"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


## A bank of armour stone along a stretch of fence, sloping from the fence
## (rise metres up) down to the ground width metres out, the way the oil
## terminal's yard is banked up above the road and the river. A rough slope
## with loose stones scattered over it, seeded by position.
func _riprap(bank: MeshKit, rocks: Array[Transform3D], q0: Vector2, q1: Vector2, g0: float, g1: float, out3: Vector3, cfg: Dictionary) -> void:
	var rise := float(cfg.get("height", 1.0))
	var width := float(cfg.get("width", 4.0))
	var out := Vector2(out3.x, out3.z)
	var f0 := q0 - out * 0.3
	var f1 := q1 - out * 0.3
	var o0 := q0 + out * width
	var o1 := q1 + out * width
	var up := Vector3(out.x * rise, width, out.y * rise).normalized()
	bank.quad(MeshKit.v3(f0, g0 + rise), MeshKit.v3(f1, g1 + rise), MeshKit.v3(o1, terrain.h2(o1) - 0.05), MeshKit.v3(o0, terrain.h2(o0) - 0.05), up)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(q0.x * 4.0), roundi(q0.y * 4.0)))
	var length := q0.distance_to(q1)
	var count := int(length * width * 2.2)
	for k in count:
		var s := rng.randf()
		var across := rng.randf()
		var p := q0.lerp(q1, s) + out * (across * width)
		var y := lerpf(lerpf(g0, g1, s) + rise, terrain.h2(p), across)
		var size := rng.randf_range(0.45, 0.95)
		var basis := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(size, size * rng.randf_range(0.6, 1.0), size * rng.randf_range(0.7, 1.2)))
		rocks.append(Transform3D(basis, Vector3(p.x, y, p.y)))


## A thin square bar from a to b (a post, a rail, a strand of wire).
static func _bar(kit: MeshKit, a: Vector3, b: Vector3, half: float) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized() * half
	var up := side.cross(d).normalized() * half
	var corners := [side + up, -side + up, -side - up, side - up]
	for k in 4:
		var c0: Vector3 = corners[k]
		var c1: Vector3 = corners[(k + 1) % 4]
		kit.quad(a + c0, a + c1, b + c1, b + c0, (c0 + c1).normalized())


# --- parking lots -----------------------------------------------------------------------

const STALL_W := 2.75 ## metres between stall lines
const STALL_FROM := 3.0 ## from the aisle's middle to the start of a stall
const STALL_LEN := 5.4

## Cars in the stalls of busy lots (see _lot_cars), each [Transform3D,
## colour, model], parked by _curb_parking with the cars on the street.
var _lot_cars: Array = []

## White stall lines either side of every mapped parking aisle, where the
## stall lies inside a mapped parking lot (or commercial land) and clear of
## buildings and streets. Lots near a street named in map_config.json
## "busy_lots" get cars in some of their stalls (_lot_cars).
func _parking_stalls(root: Node3D) -> void:
	var lots: Array[PackedVector2Array] = []
	# Mapped lots, and commercial and industrial land (drawn as asphalt):
	# plenty of big stores have their aisles mapped but not the lot itself.
	for a in chunk.areas:
		if a.type in ["amenity=parking", "landuse=commercial", "landuse=retail", "landuse=industrial"]:
			lots.append(a.ring)
	if lots.is_empty():
		return
	var kit := MeshKit.new()
	kit.clip = rect
	kit.use_clip = true
	var aisle_lines: Array[PackedVector2Array] = []
	var mapped := data.aisles_near(rect.grow(12.0))
	for r: StreetData.Road in mapped:
		aisle_lines.append(r.points)
	# Lots with no aisle mapped through them get rows laid out along their
	# length: stalls either side of an aisle, every 16.8 m across the lot.
	# Near a busy street (see _busy_lot_cars) smaller lots get them too, and
	# so does store land drawn as asphalt: the drive-throughs and plazas
	# there are mapped that way and are full of cars.
	var busy := _busy_near()
	for a in chunk.areas:
		var size := absf(BuildingGenerator._signed_area(a.ring))
		var near_busy := false
		if not busy.is_empty() and size >= 120.0 and a.type in ["amenity=parking", "landuse=commercial", "landuse=retail"]:
			var ac := BuildingGenerator._obb(a.ring)["center"] as Vector2
			for n: Array in busy:
				if _line_distance(ac, n[0]) < float(n[1]):
					near_busy = true
		if not near_busy and (a.type != "amenity=parking" or size < 500.0):
			continue
		var has_aisle := false
		for r: StreetData.Road in mapped:
			for q in r.points:
				if Geometry2D.is_point_in_polygon(q, a.ring):
					has_aisle = true
					break
			if has_aisle:
				break
		if has_aisle:
			continue
		var obb := BuildingGenerator._obb(a.ring)
		var c: Vector2 = obb["center"]
		var u: Vector2 = obb["u"]
		var v: Vector2 = obb["v"]
		var hu: float = obb["half_u"]
		var hv: float = obb["half_v"]
		# Rows of stall + aisle + stall, packed across the lot and centred.
		var module := (STALL_FROM + STALL_LEN) * 2.0
		var rows := int(floor(hv * 2.0 / module))
		if rows == 0 and near_busy and hv * 2.0 >= STALL_FROM + STALL_LEN + 1.0:
			# Too narrow for two rows: one row of stalls along one side.
			aisle_lines.append(PackedVector2Array([c - v * (hv - 0.5) - u * hu, c - v * (hv - 0.5) + u * hu]))
			continue
		for k in rows:
			var off := (float(k) - float(rows - 1) * 0.5) * module
			aisle_lines.append(PackedVector2Array([c + v * off - u * hu, c + v * off + u * hu]))
	for line in aisle_lines:
		var length := RoadNetwork.polyline_length(line)
		var d := 4.0
		while d < length - 4.0:
			var sp: Array = RoadNetwork.sample(line, d)
			var at: Vector2 = sp[0]
			var dir: Vector2 = sp[1]
			var side_v := Vector2(-dir.y, dir.x)
			for sd: float in [1.0, -1.0]:
				var p0 := at + side_v * sd * STALL_FROM
				var p1 := at + side_v * sd * (STALL_FROM + STALL_LEN)
				if not (rect.grow(1.0).has_point(p0) or rect.grow(1.0).has_point(p1)):
					continue
				if not _in_any(p0, lots) or not _in_any(p1, lots):
					continue
				var mid := (p0 + p1) * 0.5
				if _in_building(mid, 0.5) or _in_building(p1, 0.5) or not net.clear_of_roads(mid, 0.5):
					continue
				var hw := dir * 0.05
				kit.ground_quad(terrain.at(p0 - hw, -0.05), terrain.at(p1 - hw, -0.05), terrain.at(p1 + hw, -0.05), terrain.at(p0 + hw, -0.05))
			d += STALL_W
	_lot_cars = _busy_lot_cars(aisle_lines, lots)
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "ParkingStalls"
	mi.mesh = kit.commit(null, _mats.paint_white)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Cars in the stalls along `aisle_lines` that are within "reach_m" of a
## street named in map_config.json "busy_lots", one in about "odds" of them:
## the strip malls and drive-throughs down University Avenue are never
## empty (Joe's photos). Nose in, now and then backed in, seeded by the
## stall so the same cars are there every time. A stall belongs to the
## chunk its middle is in.
func _busy_lot_cars(aisle_lines: Array[PackedVector2Array], lots: Array[PackedVector2Array]) -> Array:
	var out: Array = []
	var near := _busy_near()
	if near.is_empty() or aisle_lines.is_empty():
		return out
	# A car dealer's lot holds its stock (_dealer_lots), not customers'
	# cars. (dealer_lots is every lot in the chunk; these are the ones
	# near a dealer.)
	var sale_lots: Array[PackedVector2Array] = []
	for dl: Dictionary in dealers:
		var dc := BuildingGenerator._centre(dl["ring"])
		for lot in dealer_lots:
			if _ring_gap(lot, dl["ring"]) < 2.0 or BuildingGenerator._centre(lot).distance_to(dc) < SALE_REACH:
				sale_lots.append(lot)
	for line in aisle_lines:
		var length := RoadNetwork.polyline_length(line)
		var d := 4.0 + STALL_W * 0.5
		while d < length - 4.0 - STALL_W * 0.5:
			var sp: Array = RoadNetwork.sample(line, d)
			d += STALL_W
			var dir: Vector2 = sp[1]
			var side_v := Vector2(-dir.y, dir.x)
			for sd: float in [1.0, -1.0]:
				var into := side_v * sd
				var c: Vector2 = (sp[0] as Vector2) + into * (STALL_FROM + STALL_LEN * 0.5)
				if not rect.has_point(c):
					continue
				var odds := 0.0
				for n: Array in near:
					if _line_distance(c, n[0]) < float(n[1]):
						odds = maxf(odds, float(n[2]))
				var h := hash(Vector2i(roundi(c.x * 2.0), roundi(c.y * 2.0)))
				if float(h % 1000) / 1000.0 >= odds:
					continue
				var nose := c + into * 2.3
				var tail := c - into * 2.3
				if not _in_any(nose, lots) or not _in_any(tail, lots) or _in_any(c, sale_lots):
					continue
				if _in_building(c, 1.4) or _in_building(nose, 0.4) or not net.clear_of_roads(nose, 1.0) \
						or not net.clear_of_roads(tail, 1.0) or _kept_clear(c) or data.erased(c):
					continue
				var facing := into if (h >> 11) % 6 != 0 else -into
				c += dir * (float((h >> 14) % 100) / 100.0 - 0.5) * 0.3
				var y0 := terrain.at(c - facing * 1.8).y
				var y1 := terrain.at(c + facing * 1.8).y
				var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y) + (float((h >> 17) % 100) / 100.0 - 0.5) * 0.08) \
					* Basis(Vector3.RIGHT, atan2(y1 - y0, 3.6))
				out.append([Transform3D(basis, Vector3(c.x, (y0 + y1) * 0.5 + 0.03, c.y)),
					PARKED_COLOURS[(h >> 7) % PARKED_COLOURS.size()], _pick_model(h)])
	return out


## The streets near this chunk named in map_config.json "busy_lots": each
## [street line, reach_m, odds].
func _busy_near() -> Array:
	var near: Array = []
	var cfg: Dictionary = data.config.get("busy_lots", {})
	if cfg.size() <= 1:
		return near
	for e in net.edges_near(rect.grow(150.0)):
		if cfg.get(e.name) is Dictionary:
			var c: Dictionary = cfg[e.name]
			near.append([e.points, float(c.get("reach_m", 100.0)), float(c.get("odds", 0.5))])
	return near


## Shortest distance from `p` to the polyline `line`.
static func _line_distance(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])))
	return best


static func _in_any(p: Vector2, rings: Array[PackedVector2Array]) -> bool:
	for ring in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


# --- street name signs ------------------------------------------------------------------

static func short_name(street: String) -> String:
	return street.replace(" Street", " St").replace(" Avenue", " Ave").replace(" Road", " Rd")


func _street_name_signs(root: Node3D) -> void:
	for nid: String in _junctions():
		var list: Array = net.incidents[nid]
		# Choose a corner whose two streets have different names.
		for k in list.size():
			var a: RoadNetwork.Incident = list[k]
			var b: RoadNetwork.Incident = list[(k + 1) % list.size()]
			if a.edge.name == b.edge.name or a.edge.name == "" or b.edge.name == "" or a.edge.is_highway() or b.edge.is_highway():
				continue
			var pos := net.corner_right(nid, k, RoadNetwork.Level.PROP)
			if not net.clear_of_roads(pos):
				continue
			var post := _post(root, pos, 3.0)
			_name_blade(post, a.edge.name, a.dir, 2.75)
			_name_blade(post, b.edge.name, b.dir, 2.5)
			break


func _post(root: Node3D, pos: Vector2, height: float) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	body.position = terrain.at(pos, SW_H)
	var mi := MeshInstance3D.new()
	mi.mesh = _pole
	mi.scale = Vector3(1.0, height / 3.0, 1.0)
	mi.position.y = height * 0.5
	WorldLod.limit(mi, height)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.08
	shape.height = height
	cs.shape = shape
	cs.position.y = height * 0.5
	body.add_child(cs)
	root.add_child(body)
	return body


## Yaw that turns local +X to point along ground direction d.
static func yaw_along(d: Vector2) -> float:
	return atan2(-d.y, d.x)


## Yaw that turns local +Z (the side Label3D and our sign faces show) to face
## ground direction n.
static func yaw_facing(n: Vector2) -> float:
	return atan2(n.x, n.y)


func _name_blade(post: Node3D, street: String, dir: Vector2, y: float) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0, y, 0)
	holder.rotation.y = yaw_along(dir)
	# Shift the blade so it hangs out over the street it names.
	var blade := MeshInstance3D.new()
	blade.mesh = _blade
	blade.position.x = 0.75
	WorldLod.limit(blade)
	holder.add_child(blade)
	for side: float in [1.0, -1.0]:
		var label := Label3D.new()
		label.text = short_name(street)
		label.font_size = 64
		label.pixel_size = 0.004
		label.outline_size = 0
		label.modulate = Color(0.95, 0.97, 0.95)
		label.double_sided = false
		label.position = Vector3(0.75, 0.0, 0.016 * side)
		# Each Label3D is its own draw call: only where it can be read.
		WorldLod.limit(label, 0.6)
		if side < 0.0:
			label.rotation.y = PI
		holder.add_child(label)
	post.add_child(holder)


# --- stop signs -----------------------------------------------------------------------------

func _stop_signs(root: Node3D) -> void:
	for p in data.points_of_type("highway=stop"):
		if not _inside(p.pos):
			continue
		var hit := net.nearest_on_streets(p.pos, 2.0)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var along: float = hit["along"]
		var dir: Vector2 = hit["dir"]
		# Traffic stops as it reaches the nearer end of the street.
		var travel := dir if along > e.length * 0.5 else -dir
		var right := Vector2(-travel.y, travel.x)
		var pos: Vector2 = hit["pos"] + right * (e.half_width + 0.5)
		if not net.clear_of_roads(pos):
			continue
		var post := _post(root, pos, 2.4)
		# The sign faces the cars coming toward it.
		var facing := -travel
		var normal := Vector3(facing.x, 0.0, facing.y)
		var face := MeshInstance3D.new()
		face.mesh = _stop_face
		# The octagon is a flat cylinder: point its axis at oncoming traffic.
		face.basis = Basis(Vector3.UP, normal, Vector3.UP.cross(normal))
		face.position = Vector3(0.0, 2.15, 0.0) + normal * 0.05
		# Drivers need to see it coming.
		WorldLod.limit(face, 1.5)
		post.add_child(face)
		var label := Label3D.new()
		label.text = "STOP"
		label.font_size = 40
		label.pixel_size = 0.004
		label.outline_size = 0
		label.double_sided = false
		label.modulate = Color(1, 1, 1)
		label.position = Vector3(0.0, 2.15, 0.0) + normal * 0.075
		label.rotation.y = yaw_facing(facing)
		WorldLod.limit(label, 0.6)
		post.add_child(label)


# --- traffic signals -----------------------------------------------------------------------

const SIGNAL_ARM_Y := 6.9 ## height of the mast arm above the sidewalk
const SIGNAL_POLE_TOP := 5.9 ## where the pole starts curving out into the arm
const SIGNAL_HEAD_W := 1.05 ## a horizontal head, three lamps side by side

## Traffic lights the way the Island hangs them (Joe's photo at St Peters Road
## and Allen Street): on the near right-hand corner of each way in, a
## galvanised pole curves out into a mast arm over the street. A horizontal
## head (red on the left) hangs from the arm over the lanes coming in, and
## near the arm's end a second one faces the traffic coming the other way,
## from the far side of the junction. Lower on the pole, a vertical head faces
## the cars too, and a yellow walk signal faces across the crosswalk.
## All the hardware in a chunk is one mesh per material; each junction's
## lamps are six meshes (red, amber, green for each of its two phases), so
## the controller switches them all with six material changes.
func _traffic_signals(root: Node3D) -> void:
	var metal := MeshKit.new()
	var black := MeshKit.new()
	var yellow := MeshKit.new()
	var walk := MeshKit.new()
	var body := StaticBody3D.new()
	body.name = "SignalPoles"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for nid: String in net.signal_nodes:
		if not _inside(net.nodes[nid]):
			continue
		var controller := TrafficSignal.new()
		controller.name = "Signals_%s" % nid
		root.add_child(controller)
		var lamps: Array = [] # [phase][colour] -> MeshKit
		for ph in 2:
			lamps.append([MeshKit.new(), MeshKit.new(), MeshKit.new()])
		var centre: Vector2 = net.nodes[nid]
		var list: Array = net.incidents[nid]
		for k in list.size():
			var inc: RoadNetwork.Incident = list[k]
			var e := inc.edge
			# Only ways traffic comes in by get lights facing them.
			var inbound := e.oneway == 0 or (e.oneway == 1) != inc.at_start
			if not inbound:
				continue
			var pos := net.corner_left(nid, k, RoadNetwork.Level.PROP)
			if not net.clear_of_roads(pos):
				continue
			# Approaches alternate between two phases by direction.
			var phase := 0 if absf(inc.dir.x) >= absf(inc.dir.y) else 1
			var base := terrain.at(pos, SW_H)
			var across := Vector2(-inc.dir.y, inc.dir.x) # toward the far curb (the drivers' left)
			var mouth := centre + inc.dir * net.mouth_distance(nid, k)
			# Over the middle of the lanes coming in, and over the centre line.
			var lanes_mid := mouth if e.oneway != 0 else mouth - across * e.half_width * 0.5
			var reach_a := (lanes_mid - pos).dot(across)
			var reach_b := (mouth - pos).dot(across) - 0.9
			var opposite := false
			for o: RoadNetwork.Incident in list:
				opposite = opposite or (o != inc and o.dir.dot(inc.dir) < -0.85 and (o.edge.oneway == 0 or (o.edge.oneway == 1) != o.at_start))
			if e.oneway != 0 or not opposite:
				reach_b = 0.0
			var reach := maxf(reach_a, reach_b) + 0.7
			if reach < 2.0:
				continue
			var x3 := Vector3(across.x, 0.0, across.y)
			var f3 := Vector3(inc.dir.x, 0.0, inc.dir.y) # out along the approach, toward the cars
			_signal_pole(metal, base, x3, reach)
			var cs := CollisionShape3D.new()
			cs.shape = _lamp_shape
			cs.position = base + Vector3(0.0, 2.0, 0.0)
			body.add_child(cs)
			var hang := base + Vector3(0.0, SIGNAL_ARM_Y - 0.75, 0.0)
			_signal_head(black, metal, lamps[phase], hang + x3 * reach_a, x3, f3, false, true)
			if reach_b > 0.0:
				# This head is for the other phase-mate coming the other way.
				_signal_head(black, metal, lamps[phase], hang + x3 * reach_b, -x3, -f3, false, true)
			# The pole's own vertical head, on the street side, facing the cars.
			_signal_head(black, metal, lamps[phase], base + Vector3(0.0, 3.4, 0.0) + x3 * 0.33 + f3 * 0.05, x3, f3, true, false)
			# The walk signal faces the people waiting on the far curb.
			_walk_signal(yellow, walk, base + Vector3(0.0, 2.75, 0.0) + x3 * 0.12 - f3 * 0.22, x3)
		var mats := Materials.get_shared()
		for ph in 2:
			var group: Array[MeshInstance3D] = []
			for c in 3:
				var mi := MeshInstance3D.new()
				mi.mesh = (lamps[ph][c] as MeshKit).commit_indexed(null, mats.plain(Color.BLACK))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				# Signals are seen from a long way down the street.
				WorldLod.limit(mi, 3.0)
				root.add_child(mi)
				group.append(mi)
			controller.add_head(group, ph)
	if body.get_child_count() == 0:
		body.free()
		return
	root.add_child(body)
	var mats2 := Materials.get_shared()
	for part: Array in [[metal, mats2.plain(Color(0.62, 0.64, 0.64), 0.45, 0.6), true],
			[black, mats2.plain(Color(0.07, 0.07, 0.07), 0.6), true],
			[yellow, mats2.plain(Color(0.93, 0.72, 0.1), 0.55), true],
			[walk, mats2.glow(Color(1.0, 0.45, 0.1), 1.2), false]]:
		var kit: MeshKit = part[0]
		if kit.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = "SignalHardware"
		mi.mesh = kit.commit_indexed(null, part[1])
		WorldLod.limit(mi, 3.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if part[2] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## A galvanised signal pole at base whose top curves out (toward x3) into a
## mast arm reach metres long, with a cap on the end.
static func _signal_pole(kit: MeshKit, base: Vector3, x3: Vector3, reach: float) -> void:
	var up := Vector3.UP
	_limb(kit, base + Vector3(0, -0.3, 0), base + up * SIGNAL_POLE_TOP, 0.12, 0.1)
	# The bend: a quarter circle from straight up to straight out.
	var r := SIGNAL_ARM_Y - SIGNAL_POLE_TOP
	var prev := base + up * SIGNAL_POLE_TOP
	var n := 5
	for i in range(1, n + 1):
		var a := PI * 0.5 * float(i) / float(n)
		var p := base + up * (SIGNAL_POLE_TOP + sin(a) * r) + x3 * ((1.0 - cos(a)) * r)
		_limb(kit, prev, p, 0.1 - 0.025 * float(i - 1) / float(n), 0.1 - 0.025 * float(i) / float(n))
		prev = p
	var tip := base + up * SIGNAL_ARM_Y + x3 * reach
	if reach > r:
		_limb(kit, prev, tip, 0.075, 0.055)


## One signal head: a black housing and backplate, a visor over each lamp,
## and the three lenses added to the lamp kits (red, amber, green).
## Horizontal heads hang from the arm by a short bar and read red, amber,
## green from the drivers' left; vertical ones stack red on top. at is the
## middle of the housing, x3 the drivers' left, f3 the way the lenses face.
static func _signal_head(black: MeshKit, metal: MeshKit, lamps: Array, at: Vector3, x3: Vector3, f3: Vector3, vertical: bool, hung: bool) -> void:
	var along := Vector3.UP if vertical else -x3 # red end to green end
	var side := x3 if vertical else Vector3.UP
	var long := SIGNAL_HEAD_W * 0.5
	var short := 0.19
	_box(black, at, along * long, side * short, f3 * 0.12)
	# The backplate, a thin black board behind the housing.
	_box(black, at - f3 * 0.13, along * (long + 0.14), side * (short + 0.14), f3 * 0.015)
	if hung:
		_limb(metal, at + Vector3(0, short, 0), at + Vector3(0, 0.75, 0), 0.03, 0.03)
	for i in 3:
		var t := (1.0 - float(i)) * 0.34 if vertical else (float(i) - 1.0) * 0.34
		var c := at + along * t + f3 * 0.125
		# A visor: a short sloping shade over the top of the lens.
		var hood_up := Vector3.UP if vertical else side
		var hood_x := hood_up.cross(f3).normalized()
		var r := 0.14
		black.quad(c + hood_up * r - hood_x * r, c + hood_up * r + hood_x * r, c + hood_up * (r - 0.04) + hood_x * r + f3 * 0.16, c + hood_up * (r - 0.04) - hood_x * r + f3 * 0.16, hood_up)
		_lens(lamps[i], c, f3, hood_up, 0.12)


## A flat round lens (an eight-sided disc) facing f3.
static func _lens(kit: MeshKit, c: Vector3, f3: Vector3, up: Vector3, r: float) -> void:
	var x := up.cross(f3).normalized()
	var n := 8
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		kit.tri(c, c + (x * cos(a0) + up * sin(a0)) * r, c + (x * cos(a1) + up * sin(a1)) * r, f3)


## A yellow pedestrian signal on the pole facing x3, with the orange hand lit.
static func _walk_signal(yellow: MeshKit, glow: MeshKit, at: Vector3, x3: Vector3) -> void:
	var s := Vector3.UP.cross(x3).normalized()
	_box(yellow, at, s * 0.2, Vector3.UP * 0.22, x3 * 0.12)
	var c := at + x3 * 0.125
	glow.quad(c - s * 0.13 - Vector3.UP * 0.14, c + s * 0.13 - Vector3.UP * 0.14, c + s * 0.13 + Vector3.UP * 0.14, c - s * 0.13 + Vector3.UP * 0.14, x3)


## A box round c with half-extent vectors hx, hy, hz (each face its own normal).
static func _box(kit: MeshKit, c: Vector3, hx: Vector3, hy: Vector3, hz: Vector3) -> void:
	for ax: Array in [[hx, hy, hz], [hy, hz, hx], [hz, hx, hy]]:
		var n: Vector3 = ax[0]
		var u: Vector3 = ax[1]
		var v: Vector3 = ax[2]
		for sgn: float in [1.0, -1.0]:
			var m := c + n * sgn
			kit.quad(m - u - v, m + u - v, m + u + v, m - u + v, (n * sgn).normalized())


# --- overhead crosswalk signs ------------------------------------------------------------------

const XWALK_POLE_H := 6.8
const XWALK_WIRE_Y := 6.5
const XWALK_BOARD_W := 3.0
## The overhead signs go on the main roads; smaller streets only get paint.
const XWALK_STREETS := ["trunk", "primary", "secondary", "primary_link", "secondary_link"]

## Where a marked crosswalk crosses a main street (trunk, primary or
## secondary) away from any traffic lights and outside downtown, the Island hangs a red "CROSS X WALK" board over the middle of
## the street on a span wire between two galvanized posts, and each post
## carries a white walking-figure sign facing the traffic (Joe's photos on
## Grafton Street by Holland College).
func _overhead_crosswalks(root: Node3D) -> void:
	var lights: Array[Vector2] = []
	for p in data.points_of_type("highway=traffic_signals"):
		lights.append(p.pos)
	for p in data.points_of_type("highway=crossing"):
		if str(p.tags.get("crossing", "")) == "traffic_signals":
			lights.append(p.pos)
	# Downtown's red-and-white crosswalks don't get them.
	var downtown := float(data.config.get("red_crosswalks_m", 0.0))
	for e in net.edges_near(rect.grow(10.0)):
		if not net.crosswalks.has(e) or not XWALK_STREETS.has(e.highway) or e.bridge:
			continue
		var list: Array = (net.crosswalks[e] as Array).duplicate()
		list.sort()
		var last := -INF
		for along: float in list:
			# Two crosswalks close together (both sides of a side street)
			# share one sign. Decided along the whole street, so the chunk
			# each lands in agrees.
			if along - last < 30.0:
				continue
			last = along
			var smp: Array = RoadNetwork.sample(e.points, along)
			var at: Vector2 = smp[0]
			if not _inside(at) or at.length() < downtown:
				continue
			var near_lights := false
			for q in lights:
				near_lights = near_lights or q.distance_squared_to(at) < 40.0 * 40.0
			if near_lights:
				continue
			var dir: Vector2 = smp[1]
			var right := Vector2(-dir.y, dir.x)
			var ends: Array[Vector2] = []
			for sd: float in [1.0, -1.0]:
				var spot := Vector2.INF
				for extra: float in [0.6, 1.2, 2.0, 3.0]:
					var q := at + right * sd * (e.half_width + extra)
					if net.clear_of_roads(q):
						spot = q
						break
				if spot != Vector2.INF:
					ends.append(spot)
			if ends.size() < 2:
				continue
			_xwalk_span(root, ends[0], ends[1], dir)


func _xwalk_span(root: Node3D, a: Vector2, b: Vector2, dir: Vector2) -> void:
	var tops: Array[Vector3] = []
	for k in 2:
		var pos: Vector2 = [a, b][k]
		var body := StaticBody3D.new()
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		body.position = terrain.at(pos, SW_H)
		var pole := MeshInstance3D.new()
		pole.mesh = _xwalk_pole
		pole.position.y = XWALK_POLE_H * 0.5
		body.add_child(pole)
		var cs := CollisionShape3D.new()
		cs.shape = _lamp_shape
		cs.position.y = 2.0
		body.add_child(cs)
		# The walking-figure sign, both faces, toward the traffic each way.
		for f: float in [1.0, -1.0]:
			var face := MeshInstance3D.new()
			face.mesh = _xwalk_side
			face.position = Vector3(0.0, 2.6, 0.0) + Vector3(dir.x, 0.0, dir.y) * f * 0.09
			face.rotation.y = yaw_facing(dir * f)
			WorldLod.limit(face, 1.0)
			body.add_child(face)
		root.add_child(body)
		tops.append(body.position + Vector3(0.0, XWALK_WIRE_Y, 0.0))
	# The span wire, sagging a little to the board in the middle.
	var mid := (tops[0] + tops[1]) * 0.5 + Vector3(0.0, -0.25, 0.0)
	for k in 2:
		var w := MeshInstance3D.new()
		w.mesh = _wire
		w.transform = _wire_xform(tops[k], mid)
		WorldLod.limit(w, 1.5)
		root.add_child(w)
	# The board, two faces back to back, hung just under the wire.
	var board_h := XWALK_BOARD_W * 0.25
	for f: float in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = _xwalk_board
		face.position = mid + Vector3(0.0, -0.1 - board_h * 0.5, 0.0) + Vector3(dir.x, 0.0, dir.y) * f * 0.02
		face.rotation.y = yaw_facing(dir * f)
		face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		WorldLod.limit(face, 3.0)
		root.add_child(face)


static func _sign_material(path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path) as Texture2D
	m.roughness = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


# --- trees ------------------------------------------------------------------------------------

func _trees(root: Node3D) -> void:
	# Mapped trees: trunks through one MultiMesh per trunk shape; each crown
	# is its own mesh instance so the camera can fade it when it's in the way.
	var trunk_xforms: Array[Array] = [[], [], []]
	var light_xforms: Array[Array] = [[], [], [], []]
	var spruce_xforms: Array[Array] = [[], [], []]
	var trunk_spots := PackedVector3Array()
	for p in chunk.points_of_type("natural=tree"):
		if _on_road(p.pos, 0.3):
			continue # mapped in the roadway: skip rather than block traffic
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(p.id)
		var at := terrain.at(p.pos, -0.05)
		var size := rng.randf_range(0.9, 1.35)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size))
		trunk_xforms[rng.randi() % _trunks.size()].append(Transform3D(basis, at))
		if lod:
			light_xforms[rng.randi() % 4].append(Transform3D(basis, at + Vector3(0, CROWN_Y * size, 0)))
			continue
		var body := StaticBody3D.new()
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		body.position = at
		var crown := MeshInstance3D.new()
		crown.mesh = _crowns[rng.randi() % _crowns.size()]
		crown.transform = Transform3D(basis, Vector3(0.0, CROWN_Y * size, 0.0))
		crown.set_meta("radius", CROWN_R * size)
		crown.add_to_group("camera_fade_props")
		body.add_child(crown)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.22 * size
		shape.height = 4.0 * size
		cs.shape = shape
		cs.position.y = 2.0 * size
		body.add_child(cs)
		root.add_child(body)

	# The lidar's trees, where they really stand (or, without lidar data,
	# planted ones in woods, parks and yards).
	if data.has_lidar:
		_lidar_trees(root, trunk_xforms, light_xforms, spruce_xforms, trunk_spots)
	for spot: Vector4 in ([] as Array[Vector4]) if data.has_lidar else _planted():
		var at := terrain.at(Vector2(spot.x, spot.y), -0.05)
		var size := spot.z
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(int(spot.x * 10.0), int(spot.y * 10.0)))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(size, size, size))
		if spot.w > 0.5:
			spruce_xforms[rng.randi() % _spruces.size()].append(Transform3D(basis, at))
		else:
			trunk_xforms[rng.randi() % _trunks.size()].append(Transform3D(basis, at))
			light_xforms[rng.randi() % 4].append(Transform3D(basis, at + Vector3(0, CROWN_Y * size, 0)))
		trunk_spots.append(at)
	_multi(root, "Trunks", _trunks, trunk_xforms, true)
	_multi(root, "Crowns", _light_crowns, light_xforms, true)
	_multi(root, "Spruces", _spruces, spruce_xforms, true)
	if not lod and not trunk_spots.is_empty():
		# All the chunk's trunks as one shape (six-sided posts), built here on
		# the worker thread, so a wooded chunk joins the scene in one go.
		var faces := PackedVector3Array()
		for at in trunk_spots:
			for k in 6:
				var a0 := TAU * float(k) / 6.0
				var a1 := TAU * float(k + 1) / 6.0
				var p0 := at + Vector3(cos(a0), 0.0, sin(a0)) * 0.25
				var p1 := at + Vector3(cos(a1), 0.0, sin(a1)) * 0.25
				var up := Vector3(0, 4.0, 0)
				faces.append_array([p0, p1, p1 + up, p0, p1 + up, p0 + up])
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.name = "TreeTrunks"
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)


## Trees from the lidar survey: each at its real spot, scaled to its real
## height and crown. A tree whose top hangs over a street gets its trunk
## moved back to the edge of the sidewalk, as real street trees stand. Trees
## mapped one by one in OSM (already planted above) aren't doubled.
func _lidar_trees(root: Node3D, trunk_xforms: Array[Array], light_xforms: Array[Array], spruce_xforms: Array[Array], trunk_spots: PackedVector3Array) -> void:
	var mapped: Array[Vector2] = []
	for p in chunk.points_of_type("natural=tree"):
		mapped.append(p.pos)
	var t := chunk.trees
	for i in range(0, t.size() - 4, 5):
		var p := Vector2(t[i], t[i + 1])
		var h := t[i + 2]
		var r := t[i + 3]
		var conifer := t[i + 4] > 0.5
		if lod and h < 6.0:
			continue
		var skip := false
		for q in mapped:
			if q.distance_to(p) < 3.0:
				skip = true
				break
		if skip:
			continue
		var hit := net.nearest_on_streets(p, 25.0)
		if not hit.is_empty():
			var e: RoadNetwork.RoadEdge = hit["edge"]
			var reach := e.half_width + maxf(e.walk(1), e.walk(-1)) + 0.7
			var d: float = hit["dist"]
			if d < reach:
				var away: Vector2 = p - (hit["pos"] as Vector2)
				if away.length() < 0.01:
					continue
				p = (hit["pos"] as Vector2) + away.normalized() * reach
		if not _inside(p) or _on_road(p, 0.3):
			continue
		var at := terrain.at(p, -0.05)
		var turn := Basis(Vector3.UP, fposmod(p.x * 7.13 + p.y * 3.71, TAU))
		if conifer:
			var sy := clampf(h / 10.5, 0.3, 2.6)
			var sx := clampf(r / 2.4, 0.4, 1.8)
			spruce_xforms[int(absf(p.x * 3.0 + p.y)) % spruce_xforms.size()].append(Transform3D(turn.scaled(Vector3(sx, sy, sx)), at))
		else:
			var vy := clampf(h / 9.0, 0.35, 2.4)
			var vx := clampf(r / 3.4, 0.4, 2.0)
			var b := turn.scaled(Vector3(vx, vy, vx))
			var k := int(absf(p.x * 5.0 + p.y * 3.0))
			trunk_xforms[k % trunk_xforms.size()].append(Transform3D(b, at))
			light_xforms[k % light_xforms.size()].append(Transform3D(b, at + Vector3(0, CROWN_Y * vy, 0)))
		if not lod:
			trunk_spots.append(at)


## One MultiMeshInstance3D per mesh variant that has any instances.
func _multi(root: Node3D, label: String, meshes: Array[ArrayMesh], xforms: Array[Array], shadows: bool) -> void:
	if lod:
		# Far off one shape of each kind is plenty, and it saves draw calls.
		for v in range(1, xforms.size()):
			xforms[0].append_array(xforms[v])
			xforms[v].clear()
	var cast := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows and not lod else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for v in meshes.size():
		# Split into tiles up close, so each is culled and LOD'd on its own.
		TiledMulti.add(root, "%s%d" % [label, v], meshes[v], xforms[v], cast, 0.0, not lod, [], TiledMulti.BIG_TILE)


## True if p is on a street or its sidewalk (plus `pad` metres), or in a
## junction or on a roundabout island.
func _on_road(p: Vector2, pad: float) -> bool:
	if not net.clear_of_roads(p, pad):
		return true
	for e in net.edges_near(Rect2(p - Vector2(2, 2), Vector2(4, 4))):
		if RoadNetwork.distance_to_edge(e, p) < e.half_width + maxf(e.walk(1), e.walk(-1)) + pad:
			return true
	return false


func _in_building(p: Vector2, pad: float) -> bool:
	for b in chunk.buildings:
		if _building_box(b).grow(pad).has_point(p) and (pad > 0.0 or Geometry2D.is_point_in_polygon(p, b.ring)):
			return true
	return false


var _boxes: Dictionary = {}


func _building_box(b: StreetData.Building) -> Rect2:
	if not _boxes.has(b):
		var r := Rect2(b.ring[0], Vector2.ZERO)
		for q in b.ring:
			r = r.expand(q)
		_boxes[b] = r
	return _boxes[b]


## Where to plant trees in this chunk: Vector4(x, z, size, 1 for a spruce).
## Woods are filled in on a jittered grid, parks get a few, and residential
## streets get a yard tree behind the sidewalk every so often. Seeded by
## position, so the same trees grow every time.
func _planted() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rect.position)
	var woods: Array[PackedVector2Array] = []
	var parks: Array[PackedVector2Array] = []
	# Downtown's park trees are mapped one by one in OSM; don't add more.
	var downtown := rect.get_center().length() < float(data.config.get("heritage_district_m", 900.0))
	for a in chunk.areas:
		if a.type in ["natural=wood", "landuse=forest"]:
			woods.append(a.ring)
		elif a.type in ["leisure=park", "landuse=cemetery", "landuse=recreation_ground"] and not downtown:
			parks.append(a.ring)
	var wood_step := 9.0 if lod else 7.0
	if not woods.is_empty() or not parks.is_empty():
		for kind: int in [0, 1]:
			var rings: Array[PackedVector2Array] = woods if kind == 0 else parks
			if rings.is_empty():
				continue
			var step := wood_step if kind == 0 else 22.0
			var y := rect.position.y + step * 0.5
			while y < rect.end.y:
				var x := rect.position.x + step * 0.5
				while x < rect.end.x:
					var p := Vector2(x + rng.randf_range(-0.4, 0.4) * step, y + rng.randf_range(-0.4, 0.4) * step)
					var keep := kind == 0 or rng.randf() < 0.45
					if keep and _inside(p):
						for r in rings:
							if Geometry2D.is_point_in_polygon(p, r):
								if not _on_road(p, 2.5) and not _in_building(p, 1.5):
									var spruce := 1.0 if (kind == 0 and rng.randf() < 0.55) else 0.0
									out.append(Vector4(p.x, p.y, rng.randf_range(0.8, 1.3), spruce))
								break
					x += step
				y += step
	# Yard trees along residential streets.
	for e in net.edges_near(rect):
		if e.highway not in ["residential", "living_street", "unclassified", "tertiary"] or e.walk(1) <= 0.0:
			continue
		var d := 9.0 + rng.randf() * 10.0
		while d < e.length - 9.0:
			for side: int in [1, -1]:
				if rng.randf() > 0.45:
					continue
				var sp: Array = RoadNetwork.sample(e.points, d)
				var dir: Vector2 = sp[1]
				var p: Vector2 = (sp[0] as Vector2) + Vector2(-dir.y, dir.x) * float(side) * (e.half_width + e.walk(side) + rng.randf_range(2.5, 6.0))
				if _inside(p) and not _on_road(p, 1.5) and not _in_building(p, 2.0):
					out.append(Vector4(p.x, p.y, rng.randf_range(0.75, 1.2), 1.0 if rng.randf() < 0.2 else 0.0))
			d += rng.randf_range(16.0, 30.0)
	return out


const CROWN_Y := 6.4 ## height of the middle of the crown, metres (before scaling)
const CROWN_R := 3.4 ## rough radius of the crown, for camera fading


## A crown: a cluster of lumpy blobs in a rounded, slightly flattened mass.
## Normals point out from the crown's middle (blended with each blob's own)
## so light falls across it softly; the shade inside the crown is baked into
## the vertex colours.
static func _crown_mesh(variant: int, leaf: Color, mat: Material, blobs: int, rings: int, segs: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var noise := FastNoiseLite.new()
	noise.seed = variant * 31 + 5
	noise.frequency = 0.9
	# Fewer, bigger blobs for the light crowns used in woods and yards.
	var grow := 1.0 if blobs >= 10 else 1.45
	for b in blobs:
		# Spread blobs over the surface of an ellipsoid, a few inside.
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1.0), rng.randf_range(-1, 1)).normalized()
		var at := dir * Vector3(2.1, 1.6, 2.1) * rng.randf_range(0.55, 1.0) / sqrt(grow)
		var r := rng.randf_range(1.0, 1.45) * grow
		var tint := leaf * rng.randf_range(0.88, 1.12)
		var grid: Array[PackedVector3Array] = []
		var nrm: Array[PackedVector3Array] = []
		for i in rings + 1:
			var lat := PI * float(i) / float(rings)
			var row := PackedVector3Array()
			var nrow := PackedVector3Array()
			for j in segs:
				var lon := TAU * float(j) / float(segs)
				var d := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
				var rr := r * (0.85 + 0.3 * noise.get_noise_3dv(at + d * 1.5))
				var pt := at + d * rr * Vector3(1.0, 0.85, 1.0)
				row.append(pt)
				var out := pt.normalized()
				nrow.append((out * 0.75 + d * 0.35).normalized())
			grid.append(row)
			nrm.append(nrow)
		for i in rings:
			for j in segs:
				var j1 := (j + 1) % segs
				var a := grid[i][j]
				var bb := grid[i][j1]
				var c := grid[i + 1][j1]
				var dd := grid[i + 1][j]
				var face := ((a + bb + c + dd) * 0.25 - at).normalized()
				kit.color = tint
				kit.quad_smooth(a, bb, c, dd, nrm[i][j], nrm[i][j1], nrm[i + 1][j1], nrm[i + 1][j], face)
	# Shade each vertex: darker low down and deep inside the crown.
	for k in kit.verts.size():
		var pt := kit.verts[k]
		var lift := clampf((pt.y + 2.6) / 4.6, 0.0, 1.0)
		var depth := clampf(pt.length() / 3.0, 0.0, 1.0)
		kit.colors[k] = (kit.colors[k] * (0.45 + 0.35 * lift + 0.3 * depth)).srgb_to_linear()
	return kit.commit(null, mat)


## A crown built like a real one: a few main branches climbing out from
## where the trunk's limbs end, each forking into smaller ones, with clumps
## of leaves at their ends and along their outer halves. Each clump is
## three crossed cards from the leaf atlas, so it looks full from any
## angle; the clumps sit near the outside, so the middle stays open and dark
## and sky shows between them. Two surfaces: bark, then leaves.
## Origin at the crown's middle (CROWN_Y up the tree).
static func _branchy_crown(variant: int, leaf: Color, leaves: Material, bark: Material, primaries: int, secondaries: int, grow: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (variant + 11)
	var wood := MeshKit.new()
	var kit := MeshKit.new()
	kit.use_color = true
	var radii := Vector3(2.4, 1.9, 2.4) * grow
	var hue := Color(leaf.r, leaf.g, leaf.b) / maxf(0.01, leaf.get_luminance())
	var spots: Array[Vector4] = [] # clump centre and size
	var base_angle := rng.randf() * TAU
	for p in primaries:
		var a := base_angle + TAU * float(p) / float(primaries) + rng.randf_range(-0.4, 0.4)
		var start := Vector3(cos(a) * 0.6, -1.3, sin(a) * 0.6)
		var dir := Vector3(cos(a), rng.randf_range(0.1, 0.9), sin(a)).normalized()
		var end := dir * radii * rng.randf_range(0.7, 0.85)
		_limb(wood, start, end, 0.07 * grow, 0.035 * grow)
		spots.append(Vector4(end.x, end.y, end.z, rng.randf_range(1.1, 1.4)))
		var pm := start.lerp(end, 0.65)
		spots.append(Vector4(pm.x, pm.y, pm.z, rng.randf_range(1.0, 1.3)))
		for k in secondaries:
			var from := start.lerp(end, rng.randf_range(0.45, 0.85))
			var b := a + rng.randf_range(-0.8, 0.8)
			var dir2 := Vector3(cos(b), rng.randf_range(-0.2, 1.0), sin(b)).normalized()
			var tip := dir2 * radii * rng.randf_range(0.85, 1.0)
			_limb(wood, from, tip, 0.035 * grow, 0.015 * grow)
			spots.append(Vector4(tip.x, tip.y, tip.z, rng.randf_range(1.0, 1.3)))
			for f: float in [0.35, 0.7]:
				var mid := from.lerp(tip, f) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.3, 0.3))
				spots.append(Vector4(mid.x, mid.y, mid.z, rng.randf_range(0.9, 1.2)))
	# Some inside, so the middle isn't empty, and a few on top so the crown
	# is rounded, not a ring.
	for k in 5:
		var inner := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.5), rng.randf_range(-0.5, 0.5)) * radii
		spots.append(Vector4(inner.x, inner.y, inner.z, rng.randf_range(1.1, 1.4)))
	for k in 5:
		var a := rng.randf() * TAU
		var top := Vector3(cos(a) * 0.8, 0.85, sin(a) * 0.8) * radii
		spots.append(Vector4(top.x, top.y, top.z, rng.randf_range(1.2, 1.5)))
	for sp in spots:
		var c := Vector3(sp.x, sp.y, sp.z)
		var size := sp.w * grow
		var basis := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU)
		var cell := Vector2(float(rng.randi() % 2), float(rng.randi() % 2)) * 0.5
		var out := c.normalized() if c.length() > 0.01 else Vector3.UP
		# Shade: darker low down and further in; a little hue per clump.
		var lift := clampf((c.y / radii.y + 1.0) * 0.5, 0.0, 1.0)
		var depth := clampf(c.length() / radii.x, 0.0, 1.0)
		var shade := (0.35 + 0.45 * lift + 0.3 * depth) * rng.randf_range(0.9, 1.1)
		kit.color = Color(lerpf(1.0, hue.r, 0.25), lerpf(1.0, hue.g, 0.25), lerpf(1.0, hue.b, 0.25)) * shade
		for axis in 3:
			var u: Vector3 = basis[(axis + 1) % 3] * size * 0.5
			var v: Vector3 = basis[(axis + 2) % 3] * size * 0.5
			var face: Vector3 = basis[axis]
			var corners: Array[Vector3] = [c - u - v, c + u - v, c + u + v, c - u + v]
			var uv: Array[Vector2] = [cell + Vector2(0, 0.5), cell + Vector2(0.5, 0.5), cell + Vector2(0.5, 0), cell]
			var ns: Array[Vector3] = []
			for q in corners:
				ns.append((q.normalized() * 0.7 + out * 0.3).normalized())
			kit.tri_full(corners[0], corners[1], corners[2], face, ns[0], ns[1], ns[2], uv[0], uv[1], uv[2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			kit.tri_full(corners[0], corners[2], corners[3], face, ns[0], ns[2], ns[3], uv[0], uv[2], uv[3], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
	for k in kit.colors.size():
		kit.colors[k] = kit.colors[k].srgb_to_linear()
	var mesh := wood.commit(null, bark)
	return kit.commit(mesh, leaves)


## A trunk that forks into a few limbs reaching up into the crown.
static func _trunk_mesh(variant: int, mat: Material, slim := false) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 104729 * (variant + 1)
	var kit := MeshKit.new()
	if slim:
		# A slimmer, slightly leaning trunk with a flare at the root; the
		# crown carries its own branches.
		var lean := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		_limb(kit, Vector3(0, -0.2, 0), Vector3(0, 0.35, 0), 0.3, 0.19)
		_limb(kit, Vector3(0, 0.35, 0), Vector3(0, 2.4, 0) + lean * 0.5, 0.19, 0.16)
		_limb(kit, Vector3(0, 2.4, 0) + lean * 0.5, Vector3(0, 4.6, 0) + lean, 0.16, 0.11)
		for k in 3:
			var ang := TAU * float(k) / 3.0 + rng.randf() * 0.8
			var tip := Vector3(cos(ang) * rng.randf_range(0.7, 1.1), rng.randf_range(5.0, 5.6), sin(ang) * rng.randf_range(0.7, 1.1))
			_limb(kit, Vector3(0, 3.6, 0) + lean * 0.8, tip, 0.1, 0.06)
		return kit.commit(null, mat)
	_limb(kit, Vector3(0, -0.2, 0), Vector3(rng.randf_range(-0.2, 0.2), 4.2, rng.randf_range(-0.2, 0.2)), 0.26, 0.16)
	var fork := Vector3(0, 3.6, 0)
	for k in 3 + variant % 2:
		var ang := TAU * float(k) / float(3 + variant % 2) + rng.randf() * 0.8
		var tip := Vector3(cos(ang) * rng.randf_range(1.2, 2.0), rng.randf_range(5.6, 6.8), sin(ang) * rng.randf_range(1.2, 2.0))
		_limb(kit, fork, tip, 0.12, 0.05)
	return kit.commit(null, mat)


## A spruce: a short trunk under stacked cones of dark needles, about as
## tall as a leafy street tree.
static func _spruce_mesh(variant: int, needle: Color, leaves: Material, bark: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15485863 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var tiers := 4
	var height := rng.randf_range(9.0, 12.0)
	var segs := 7
	for t in tiers:
		var f := float(t) / float(tiers)
		var y0 := 1.2 + f * (height - 2.0) * 0.82
		var y1 := y0 + (height - 1.2) * 0.42
		var r := (1.0 - f * 0.78) * rng.randf_range(2.2, 2.7)
		var tint := needle * rng.randf_range(0.9, 1.1)
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var c0 := Vector3(cos(a0), 0.0, sin(a0))
			var c1 := Vector3(cos(a1), 0.0, sin(a1))
			var n0 := (c0 * 0.8 + Vector3.UP * 0.6).normalized()
			var n1 := (c1 * 0.8 + Vector3.UP * 0.6).normalized()
			kit.color = (tint * 0.7).srgb_to_linear()
			var top := Vector3(0, y1, 0)
			var b0 := c0 * r + Vector3(0, y0, 0)
			var b1 := c1 * r + Vector3(0, y0, 0)
			kit.tri_full(b0, b1, top, (c0 + c1).normalized() + Vector3.UP * 0.5, n0, n1, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
			kit.color = (tint * 0.35).srgb_to_linear()
			kit.tri(b0, b1, Vector3(0, y0 + 0.3, 0), Vector3.DOWN)
	var mesh := kit.commit(null, leaves)
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.2, 0), Vector3(0, 2.0, 0), 0.2, 0.14)
	wood.commit(mesh, bark)
	return mesh


## A spruce built from its branches: whorls of drooping branch cards up a
## tapering trunk, long at the bottom and short at the top, each branch two
## crossed cards of the needle-branch texture so it has thickness from any
## side. Inner ends are shaded darker, as the inside of a spruce is.
static func _card_spruce(variant: int, needle: Color, mat: Material, bark: Material) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15485863 * (variant + 1)
	var kit := MeshKit.new()
	kit.use_color = true
	var height := rng.randf_range(9.0, 12.0)
	var base := 0.9
	var step := 0.5
	var whorls := int((height - base - 0.6) / step)
	var hue := Color(needle.r, needle.g, needle.b) / maxf(0.01, needle.get_luminance())
	var tint := Color(lerpf(1.0, hue.r, 0.2), lerpf(1.0, hue.g, 0.2), lerpf(1.0, hue.b, 0.2))
	for w in whorls:
		var f := float(w) / float(whorls)
		var y := base + w * step + rng.randf_range(-0.1, 0.1)
		var count := 5 if f < 0.7 else 4
		var spin := rng.randf() * TAU
		for k in count:
			var a := spin + TAU * float(k) / float(count) + rng.randf_range(-0.25, 0.25)
			var length := (1.0 - f) * rng.randf_range(2.4, 2.9) + 0.45
			var dir := Vector3(cos(a), -0.18 - 0.12 * (1.0 - f), sin(a)).normalized()
			var side := Vector3(-sin(a), 0.0, cos(a))
			var root := Vector3(0, y, 0)
			var tip := root + dir * length
			var half := length * 0.28
			var shade_in := 0.35 + 0.25 * f
			for c in 2:
				# One card lying flat, one tilted up along the branch.
				var wv := side * half if c == 0 else (side * 0.5 + Vector3.UP * 0.86).normalized() * half * 0.8
				var corners: Array[Vector3] = [root - wv, tip - wv, tip + wv, root + wv]
				var uv: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
				var face := dir.cross(wv).normalized()
				if face.y < 0.0:
					face = -face
				var ns: Array[Vector3] = []
				for q in corners:
					var o := Vector3(q.x, 0.0, q.z)
					ns.append((o.normalized() * 0.8 + Vector3.UP * 0.5).normalized() if o.length() > 0.05 else Vector3.UP)
				var cols: Array[Color] = []
				for q in 4:
					var outer := q == 1 or q == 2
					cols.append((tint * (1.0 if outer else shade_in) * rng.randf_range(0.92, 1.05)).srgb_to_linear())
				for tri: Array in [[0, 1, 2], [0, 2, 3]]:
					kit.color = cols[tri[0]]
					var i0: int = tri[0]
					var i1: int = tri[1]
					var i2: int = tri[2]
					kit.tri_full(corners[i0], corners[i1], corners[i2], face, ns[i0], ns[i1], ns[i2], uv[i0], uv[i1], uv[i2], Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
					# Per-corner shade: patch the colours just added.
					# (tri_full may have swapped the last two to fix the winding.)
					var n := kit.colors.size()
					for m in range(n - 3, n):
						for q: int in [i0, i1, i2]:
							if kit.verts[m] == corners[q]:
								kit.colors[m] = cols[q]
	# The leader at the very top: two crossed upright cards.
	var top := Vector3(0, height - 0.9, 0)
	for c in 2:
		var wv := (Vector3.RIGHT if c == 0 else Vector3.BACK) * 0.35
		var tipv := top + Vector3.UP * 1.3
		kit.color = tint.srgb_to_linear()
		kit.quad(top - wv, top + wv, tipv + wv, tipv - wv, Vector3.BACK if c == 0 else Vector3.RIGHT,
			Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	var mesh := kit.commit(null, mat)
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.2, 0), Vector3(0, height * 0.75, 0), 0.22, 0.05)
	wood.commit(mesh, bark)
	return mesh


## A tapered six-sided limb from a to b, smooth shaded.
static func _limb(kit: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var n := 6
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		kit.quad_smooth(a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, d0, d1, d1, d0, (d0 + d1).normalized())


# --- heritage lamp posts ------------------------------------------------------------------------

const LAMP_SPACING := 24.0
const STREET_LIGHT_SPACING := 40.0

## The cast-iron post as (radius, height) going up, turned round the post.
const LAMP_IRON := [
	[0.0, 0.0], [0.17, 0.0], [0.17, 0.08], [0.14, 0.11], [0.14, 0.27], [0.1, 0.34], [0.115, 0.48],
	[0.075, 0.6], [0.09, 0.66], [0.06, 0.74], [0.052, 3.36], [0.078, 3.42], [0.078, 3.5],
	[0.1, 3.56], [0.15, 3.64], [0.15, 3.68], [0.0, 3.68],
]
## The lantern's roof and finial, above the glass.
const LAMP_CAP := [
	[0.0, 4.12], [0.27, 4.12], [0.27, 4.17], [0.13, 4.31], [0.05, 4.4], [0.065, 4.45], [0.03, 4.52], [0.0, 4.54],
]


## One lamp post with two surfaces, iron and the lantern glass, so every
## lamp in town draws in two calls through one MultiMesh.
static func _lamp_mesh(mats: Materials) -> ArrayMesh:
	var iron := MeshKit.new()
	_lathe(iron, LAMP_IRON, 12)
	_lathe(iron, LAMP_CAP, 6)
	# Six thin glazing bars up the corners of the lantern.
	for k in 6:
		var a := TAU * float(k) / 6.0
		var lo := Vector3(cos(a) * 0.15, 3.68, sin(a) * 0.15)
		var hi := Vector3(cos(a) * 0.24, 4.12, sin(a) * 0.24)
		StreetProps._limb(iron, lo, hi, 0.012, 0.012)
	var glass := MeshKit.new()
	_lathe(glass, [[0.0, 3.68], [0.145, 3.68], [0.235, 4.12], [0.0, 4.12]], 6)
	var mesh := iron.commit(null, mats.plain(Color(0.06, 0.065, 0.065), 0.4, 0.5))
	glass.commit(mesh, mats.glow(Color(1.0, 0.88, 0.66), 0.7))
	return mesh


## An ordinary street light: a creosoted wooden pole with a grey arm
## reaching out over the road and a cobra-head lamp on the end. Local +X
## points at the road.
static func _street_light_mesh(mats: Materials) -> ArrayMesh:
	var wood := MeshKit.new()
	_limb(wood, Vector3(0, -0.3, 0), Vector3(0, 8.6, 0), 0.15, 0.11)
	var metal := MeshKit.new()
	_limb(metal, Vector3(0.0, 7.6, 0), Vector3(1.4, 8.15, 0), 0.04, 0.035)
	_limb(metal, Vector3(1.4, 8.15, 0), Vector3(2.3, 8.2, 0), 0.035, 0.035)
	# The head: a shallow rounded box.
	var hx := 2.75
	var head := [Vector3(hx - 0.45, 8.12, -0.17), Vector3(hx + 0.4, 8.12, -0.15), Vector3(hx + 0.4, 8.12, 0.15), Vector3(hx - 0.45, 8.12, 0.17)]
	var top := [Vector3(hx - 0.45, 8.3, -0.14), Vector3(hx + 0.35, 8.24, -0.12), Vector3(hx + 0.35, 8.24, 0.12), Vector3(hx - 0.45, 8.3, 0.14)]
	for k in 4:
		var a: Vector3 = head[k]
		var b: Vector3 = head[(k + 1) % 4]
		var c: Vector3 = top[(k + 1) % 4]
		var d: Vector3 = top[k]
		var out := ((a + b) * 0.5 - Vector3(hx, 8.12, 0)).normalized()
		metal.quad(a, b, c, d, out)
	metal.quad(top[0], top[1], top[2], top[3], Vector3.UP)
	var glass := MeshKit.new()
	glass.quad(head[0] + Vector3(0.08, -0.02, 0.03), head[1] + Vector3(-0.08, -0.02, 0.03), head[2] + Vector3(-0.08, -0.02, -0.03), head[3] + Vector3(0.08, -0.02, -0.03), Vector3.DOWN)
	var mesh := wood.commit(null, mats.plain(Color(0.27, 0.21, 0.16), 0.95))
	metal.commit(mesh, mats.plain(Color(0.55, 0.57, 0.58), 0.45, 0.6))
	glass.commit(mesh, mats.glow(Color(1.0, 0.9, 0.72), 0.5))
	return mesh


## A tall galvanised steel pole for the median of a divided road, with an
## arm curving out each way (local +X and -X) to a cobra-head lamp over
## each carriageway.
static func _twin_light_mesh(mats: Materials) -> ArrayMesh:
	var metal := MeshKit.new()
	_limb(metal, Vector3(0, -0.3, 0), Vector3(0, 10.2, 0), 0.13, 0.08)
	var glass := MeshKit.new()
	for s: float in [1.0, -1.0]:
		var pts := [Vector3(0, 9.6, 0), Vector3(0.35 * s, 10.25, 0), Vector3(0.9 * s, 10.6, 0), Vector3(1.7 * s, 10.72, 0), Vector3(2.4 * s, 10.7, 0)]
		for k in pts.size() - 1:
			_limb(metal, pts[k], pts[k + 1], 0.05, 0.045)
		var hx := 2.8 * s
		var head := [Vector3(hx - 0.45, 10.58, -0.17), Vector3(hx + 0.4, 10.58, -0.15), Vector3(hx + 0.4, 10.58, 0.15), Vector3(hx - 0.45, 10.58, 0.17)]
		var top := [Vector3(hx - 0.45, 10.76, -0.14), Vector3(hx + 0.35, 10.7, -0.12), Vector3(hx + 0.35, 10.7, 0.12), Vector3(hx - 0.45, 10.76, 0.14)]
		for k in 4:
			var a: Vector3 = head[k]
			var b: Vector3 = head[(k + 1) % 4]
			var out := ((a + b) * 0.5 - Vector3(hx, 10.58, 0)).normalized()
			metal.quad(a, b, top[(k + 1) % 4], top[k], out)
		metal.quad(top[0], top[1], top[2], top[3], Vector3.UP)
		glass.quad(head[0] + Vector3(0.08, -0.02, 0.03), head[1] + Vector3(-0.08, -0.02, 0.03), head[2] + Vector3(-0.08, -0.02, -0.03), head[3] + Vector3(0.08, -0.02, -0.03), Vector3.DOWN)
	var mesh := metal.commit(null, mats.plain(Color(0.6, 0.62, 0.62), 0.45, 0.6))
	glass.commit(mesh, mats.glow(Color(1.0, 0.9, 0.72), 0.5))
	return mesh


## A rough, many-faceted stone about a metre across (an octahedron with its
## corners and edges knocked about), for armour stone and boulders.
static func _rock_mesh(mats: Materials) -> ArrayMesh:
	var kit := MeshKit.new()
	# An octahedron with uneven reach, each face split at a pushed-out
	# middle so the stone has 24 facets.
	var px := Vector3(0.55, 0.05, 0.08)
	var nx := Vector3(-0.5, -0.04, -0.06)
	var py := Vector3(0.06, 0.4, 0.03)
	var ny := Vector3(-0.05, -0.33, 0.04)
	var pz := Vector3(0.08, 0.03, 0.5)
	var nz := Vector3(-0.04, 0.02, -0.52)
	var faces := [[px, py, pz], [pz, py, nx], [nx, py, nz], [nz, py, px], [pz, ny, px], [nx, ny, pz], [nz, ny, nx], [px, ny, nz]]
	var k := 0
	for f: Array in faces:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var c: Vector3 = f[2]
		var m := (a + b + c) / 3.0
		m = m.normalized() * (m.length() * (1.18 + 0.12 * float(k % 3)))
		k += 1
		for t: Array in [[a, b, m], [b, c, m], [c, a, m]]:
			var t0: Vector3 = t[0]
			var t1: Vector3 = t[1]
			var t2: Vector3 = t[2]
			var n := (t1 - t0).cross(t2 - t0).normalized()
			if n.dot((t0 + t1 + t2) / 3.0) < 0.0:
				n = -n
			kit.tri(t0, t1, t2, n)
	return kit.commit(null, mats.plain(Color(0.33, 0.32, 0.3), 0.95))


## Turns a (radius, height) profile round the Y axis. Smooth round the
## post, a crisp edge at each step of the profile.
static func _lathe(kit: MeshKit, profile: Array, segs: int) -> void:
	for i in range(profile.size() - 1):
		var r0 := float(profile[i][0])
		var y0 := float(profile[i][1])
		var r1 := float(profile[i + 1][0])
		var y1 := float(profile[i + 1][1])
		if absf(r0 - r1) < 0.0001 and absf(y0 - y1) < 0.0001:
			continue
		# Outward normal of this step of the profile, in (radius, height).
		var n2 := Vector2(y1 - y0, r0 - r1).normalized()
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var c0 := Vector3(cos(a0), 0.0, sin(a0))
			var c1 := Vector3(cos(a1), 0.0, sin(a1))
			var n0 := (c0 * n2.x + Vector3.UP * n2.y).normalized()
			var n1 := (c1 * n2.x + Vector3.UP * n2.y).normalized()
			var face := ((c0 + c1).normalized() * n2.x + Vector3.UP * n2.y).normalized()
			kit.quad_smooth(c0 * r0 + Vector3.UP * y0, c1 * r0 + Vector3.UP * y0, c1 * r1 + Vector3.UP * y1, c0 * r1 + Vector3.UP * y1, n0, n1, n1, n0, face)


## Lamps along the streets, kept clear of the junctions. Downtown (within
## "heritage_district_m" of the origin in map_config.json) gets black
## cast-iron lamp posts on both sides every LAMP_SPACING metres; elsewhere a
## street light on a wooden pole every STREET_LIGHT_SPACING metres, on
## alternating sides. Highways have none. Each kind is one MultiMesh per
## chunk, with one static body for their collision.
## True for a street named in map_config.json "street_power_lines" with
## "downtown": its poles, and the street lights on them, go on inside the
## downtown radius.
func _poles_downtown(street: String) -> bool:
	var cfg: Variant = (data.config.get("street_power_lines", {}) as Dictionary).get(street)
	return cfg is Dictionary and bool((cfg as Dictionary).get("downtown", false))


func _lamps(root: Node3D) -> void:
	var heritage_r := float(data.config.get("heritage_district_m", 900.0))
	var spots: Array[Vector2] = []
	var lights: Array[Transform3D] = []
	for e in net.edges_near(rect):
		if e.is_highway() or e.walk(1) + e.walk(-1) <= 1.2:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 6.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 6.0
		if stop - start < 4.0:
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		# A street whose poles carry on downtown ("street_power_lines"
		# downtown) has its lights on them there too, not cast-iron lamps.
		var heritage := mid.length() < heritage_r and not _poles_downtown(e.name)
		for side: int in [1, -1]:
			if e.walk(side) < 1.0:
				continue
			var line := net.side_line(e, side, RoadNetwork.Level.PROP)
			var line_len := RoadNetwork.polyline_length(line)
			var scale := line_len / e.length
			if heritage:
				var d := start + (LAMP_SPACING * 0.5 if side < 0 else 0.0)
				while d < stop:
					var sp: Array = RoadNetwork.sample(line, d * scale)
					if _inside(sp[0]) and net.clear_of_roads(sp[0], 0.2) and not data.erased(sp[0]):
						spots.append(sp[0])
					d += LAMP_SPACING
			else:
				var d2 := start + (STREET_LIGHT_SPACING * 0.5 if side < 0 else 0.0)
				while d2 < stop:
					var sp2: Array = RoadNetwork.sample(line, d2 * scale)
					var at: Vector2 = sp2[0]
					if _inside(at) and net.clear_of_roads(at, 0.2) and not data.erased(at):
						var dir: Vector2 = sp2[1]
						var to_road := -Vector2(-dir.y, dir.x) * float(side)
						lights.append(Transform3D(Basis(Vector3.UP, StreetProps.yaw_along(to_road)), terrain.at(at, SW_H)))
					d2 += STREET_LIGHT_SPACING * 2.0
	if spots.is_empty() and lights.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "LampPosts"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	if not spots.is_empty():
		var lamp_xf: Array[Transform3D] = []
		for i in spots.size():
			var turn := Basis(Vector3.UP, float(i % 6) * 0.17)
			lamp_xf.append(Transform3D(turn, terrain.at(spots[i], SW_H)))
		TiledMulti.add(root, "Lamps", _heritage_lamp, lamp_xf, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, LAMP_DRAW_DISTANCE)
		# The cast-iron post and lantern are hundreds of triangles; a post
		# and a box throw the same thin shadow.
		TiledMulti.add(root, "Lamps_shadow", _lamp_shadow_stand_in(), lamp_xf, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, LAMP_DRAW_DISTANCE)
		for p in spots:
			var cs := CollisionShape3D.new()
			cs.shape = _lamp_shape
			cs.position = terrain.at(p, SW_H + 2.0)
			body.add_child(cs)
	if not lights.is_empty():
		TiledMulti.add(root, "StreetLights", _street_light, lights, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, LAMP_DRAW_DISTANCE)
		for t in lights:
			var cs2 := CollisionShape3D.new()
			cs2.shape = _pole_shape
			cs2.position = t.origin + Vector3(0, 4.0, 0)
			body.add_child(cs2)
	root.add_child(body)


# --- divided roads, plant basins, sign gantries ---------------------------------------------

## Twin-arm lights down the median of the divided roads named in
## map_config.json "median_lights" (a highway gets no lights otherwise).
## Each is placed from the carriageway heading roughly north or east, halfway
## to the other carriageway, so a pair of carriageways gets one row.
func _median_lights(root: Node3D) -> void:
	var cfg: Dictionary = data.config.get("median_lights", {})
	if cfg.is_empty():
		return
	var xforms: Array[Transform3D] = []
	for e in net.edges_near(rect):
		if not cfg.has(e.name) or e.oneway == 0:
			continue
		var spacing := float((cfg[e.name] as Dictionary).get("spacing", 45.0))
		var pts := e.points
		if e.oneway < 0:
			pts = pts.duplicate()
			pts.reverse()
		var whole := (pts[pts.size() - 1] - pts[0]).normalized()
		if not (whole.y < -0.2 or (absf(whole.y) <= 0.2 and whole.x > 0.0)):
			continue
		# Spaced along the world, not the edge, so lights line up across
		# edges: start at the next multiple of the spacing.
		var d := fposmod(-_along_key(pts[0], whole), spacing)
		while d < e.length - 4.0:
			var sp: Array = RoadNetwork.sample(pts, d)
			d += spacing
			var p: Vector2 = sp[0]
			var t: Vector2 = sp[1]
			var left := Vector2(t.y, -t.x)
			# The other carriageway: the nearest centreline of the same name
			# off to the left. The light stands in the middle of the room
			# left between the two sets of travel lanes (the median and the
			# inside shoulders), if there is any.
			var hit := net.nearest_on_streets(p + left * (e.half_width + 1.0), 40.0)
			if hit.is_empty() or hit["edge"] == e or (hit["edge"] as RoadNetwork.RoadEdge).name != e.name:
				continue
			var other: RoadNetwork.RoadEdge = hit["edge"]
			var apart := ((hit["pos"] as Vector2) - p).dot(left)
			var lanes_here := e.half_width - e.shoulder + 0.4
			var lanes_there := other.half_width - other.shoulder + 0.4
			var room := apart - lanes_here - lanes_there
			if room < 0.0 or apart > 60.0:
				continue
			var m := p + left * (lanes_here + room * 0.5)
			if not _inside(m) or net.in_junction(m):
				continue
			xforms.append(Transform3D(Basis(Vector3.UP, StreetProps.yaw_along(left)), terrain.at(m)))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _twin_light
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MedianLights"
	mmi.multimesh = mm
	root.add_child(mmi)
	var body := StaticBody3D.new()
	body.name = "MedianLightPoles"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for t in xforms:
		var cs := CollisionShape3D.new()
		cs.shape = _pole_shape
		cs.position = t.origin + Vector3(0, 4.0, 0)
		body.add_child(cs)
	root.add_child(body)


## Distance along a road's general direction, so spacing restarts at the
## same places whichever edge a stretch of road is split into.
static func _along_key(p: Vector2, dir: Vector2) -> float:
	return p.dot(dir)


## Treatment tanks: every pond (natural=water) inside a mapped area that has
## "basins" in map_config.json "area_styles" gets a concrete wall standing
## out of the ground round it, a railing on top and the water up near the
## rim, the way the tanks of a sewage plant look from the road.
func _basins(root: Node3D) -> void:
	var styles: Dictionary = data.config.get("area_styles", {})
	var yards: Array = []
	for a in chunk.areas:
		var st: Dictionary = styles.get(str(a.tags.get("name", "")), {})
		if st.get("basins", false):
			yards.append([a.ring, st])
	if yards.is_empty():
		return
	var walls := MeshKit.new()
	var water := MeshKit.new()
	var rails := MeshKit.new()
	var faces := PackedVector3Array()
	for a in chunk.areas:
		if a.type != "natural=water":
			continue
		var c := Vector2.ZERO
		for q in a.ring:
			c += q
		c /= float(a.ring.size())
		if not _inside(c):
			continue
		var st: Dictionary = {}
		for y: Array in yards:
			if Geometry2D.is_point_in_polygon(c, y[0]):
				st = y[1]
		if st.is_empty():
			continue
		var h := float(st.get("basin_height", 1.2))
		var ring := a.ring
		var g := INF
		for q in ring:
			g = minf(g, terrain.h2(q))
		for i in ring.size():
			var p0 := ring[i]
			var p1 := ring[(i + 1) % ring.size()]
			if p0.distance_to(p1) < 0.05:
				continue
			var t := (p1 - p0).normalized()
			var o := Vector2(t.y, -t.x)
			if BuildingGenerator._signed_area(ring) < 0.0:
				o = -o
			var o3 := Vector3(o.x, 0.0, o.y)
			var q0 := p0 + o * 0.3
			var q1 := p1 + o * 0.3
			walls.quad(MeshKit.v3(q0, g - 0.3), MeshKit.v3(q1, g - 0.3), MeshKit.v3(q1, g + h), MeshKit.v3(q0, g + h), o3)
			walls.quad(MeshKit.v3(p0, g + h - 0.5), MeshKit.v3(p1, g + h - 0.5), MeshKit.v3(p1, g + h), MeshKit.v3(p0, g + h), -o3)
			walls.quad(MeshKit.v3(p0, g + h), MeshKit.v3(p1, g + h), MeshKit.v3(q1, g + h), MeshKit.v3(q0, g + h), Vector3.UP)
			faces.append_array(PackedVector3Array([MeshKit.v3(q0, g - 0.3), MeshKit.v3(q1, g - 0.3), MeshKit.v3(q1, g + h + 1.1),
				MeshKit.v3(q0, g - 0.3), MeshKit.v3(q1, g + h + 1.1), MeshKit.v3(q0, g + h + 1.1)]))
			var r0 := p0 + o * 0.15
			var r1 := p1 + o * 0.15
			for y: float in [g + h + 0.55, g + h + 1.05]:
				_bar(rails, MeshKit.v3(r0, y), MeshKit.v3(r1, y), 0.025)
			if i % 2 == 0:
				_bar(rails, MeshKit.v3(r0, g + h), MeshKit.v3(r0, g + h + 1.1), 0.03)
		var idx := Geometry2D.triangulate_polygon(ring)
		for k in range(0, idx.size(), 3):
			water.tri(MeshKit.v3(ring[idx[k]], g + h - 0.35), MeshKit.v3(ring[idx[k + 1]], g + h - 0.35), MeshKit.v3(ring[idx[k + 2]], g + h - 0.35), Vector3.UP)
	if walls.verts.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = "Basins"
	mi.mesh = walls.commit(null, _mats.plain(Color.from_string(str(yards[0][1].get("basin_colour", "#a9a69e")), Color(0.66, 0.65, 0.62)), 0.9))
	water.commit(mi.mesh as ArrayMesh, _mats.plain(Color(0.25, 0.3, 0.27), 0.15))
	rails.commit(mi.mesh as ArrayMesh, _mats.plain(Color(0.85, 0.75, 0.2), 0.5, 0.3))
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = "BasinWalls"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)


## Overhead sign gantries from map_config.json "sign_gantries": a steel
## truss across the carriageway of `street` heading toward the junction of
## `toward`, distance_m before it, carrying green guide signs, with a
## yellow warning sign on a post at the roadside further back.
func _gantries(root: Node3D) -> void:
	for g: Dictionary in data.config.get("sign_gantries", []):
		var toward: Array = g.get("toward", [])
		if toward.size() < 2:
			continue
		var nid := net.find_junction(str(toward[0]), str(toward[1]))
		if nid == "":
			continue
		var target: Vector2 = net.nodes[nid]
		var street := str(g.get("street", ""))
		var dist := float(g.get("distance_m", 100.0))
		# Which way the gantry's traffic is going (the approach it stands over).
		var heading: Vector2 = {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0)}.get(str(g.get("heading", "")), Vector2.ZERO)
		# The carriageway of `street` whose traffic ends nearest the junction.
		var best: RoadNetwork.RoadEdge = null
		var best_d := 80.0
		for e in net.edges_near(Rect2(target - Vector2(dist + 200, dist + 200), Vector2(dist + 200, dist + 200) * 2.0)):
			if e.name != street or e.oneway == 0:
				continue
			var end := e.points[e.points.size() - 1] if e.oneway > 0 else e.points[0]
			var start := e.points[0] if e.oneway > 0 else e.points[e.points.size() - 1]
			if heading != Vector2.ZERO and (end - start).normalized().dot(heading) < 0.5:
				continue
			if end.distance_to(target) < best_d:
				best_d = end.distance_to(target)
				best = e
		if best == null:
			continue
		var pts := best.points
		if best.oneway < 0:
			pts = pts.duplicate()
			pts.reverse()
		var sp: Array = RoadNetwork.sample(pts, maxf(2.0, best.length - dist))
		var p: Vector2 = sp[0]
		var t: Vector2 = sp[1]
		if not _inside(p):
			continue
		var right := Vector2(-t.y, t.x)
		var span := best.half_width + best.shoulder + 1.5
		var a := p - right * span
		var b := p + right * span
		var metal := MeshKit.new()
		var y0 := maxf(terrain.h2(a), terrain.h2(b))
		var deck := 6.2
		var faces := PackedVector3Array()
		for q in [a, b]:
			var gq := terrain.h2(q)
			for off: float in [-0.5, 0.5]:
				_bar(metal, MeshKit.v3(q + t * off, gq - 0.3), MeshKit.v3(q + t * off, y0 + deck + 1.0), 0.09)
			_bar(metal, MeshKit.v3(q - t * 0.5, y0 + deck), MeshKit.v3(q + t * 0.5, y0 + deck), 0.04)
			faces.append_array(StreetProps._post_faces(q, gq, y0 + deck + 1.0, t))
		# The truss: two chords with zig-zag lacing between.
		for y: float in [deck, deck + 1.0]:
			_bar(metal, MeshKit.v3(a, y0 + y), MeshKit.v3(b, y0 + y), 0.06)
		var n := int(ceil(span * 2.0 / 1.0))
		for k in n:
			var q0 := a.lerp(b, float(k) / n)
			var q1 := a.lerp(b, float(k + 1) / n)
			var lo := y0 + deck if k % 2 == 0 else y0 + deck + 1.0
			var hi := y0 + deck + 1.0 if k % 2 == 0 else y0 + deck
			_bar(metal, MeshKit.v3(q0, lo), MeshKit.v3(q1, hi), 0.025)
		var panels := MeshKit.new()
		var signs: Array = g.get("signs", [])
		var face := -t # the signs face oncoming traffic
		var f3 := Vector3(face.x, 0.0, face.y)
		for i in signs.size():
			var sg: Dictionary = signs[i]
			var w := float(sg.get("width", 3.0))
			var hgt := float(sg.get("height", 2.2))
			var at := lerpf(-span * 0.55, span * 0.55, (float(i) + 0.5) / signs.size()) if signs.size() > 1 else 0.0
			var c := p + right * at + face * 0.25
			var bottom := y0 + deck + 0.5 - hgt * 0.5
			panels.quad(MeshKit.v3(c - right * w * 0.5, bottom), MeshKit.v3(c + right * w * 0.5, bottom), MeshKit.v3(c + right * w * 0.5, bottom + hgt), MeshKit.v3(c - right * w * 0.5, bottom + hgt), f3)
			panels.quad(MeshKit.v3(c - right * w * 0.5 - face * 0.05, bottom), MeshKit.v3(c + right * w * 0.5 - face * 0.05, bottom), MeshKit.v3(c + right * w * 0.5 - face * 0.05, bottom + hgt), MeshKit.v3(c - right * w * 0.5 - face * 0.05, bottom + hgt), -f3)
			var label := Label3D.new()
			label.text = str(sg.get("text", ""))
			label.font_size = 64
			label.outline_size = 0
			label.pixel_size = clampf(w * 0.85 / maxf(1.0, _longest_line(label.text) * 64.0 * 0.55), 0.004, 0.02)
			label.modulate = Color.WHITE
			label.double_sided = false
			label.position = MeshKit.v3(c + face * 0.03, bottom + hgt * 0.5)
			label.rotation.y = StreetProps.yaw_facing(face)
			root.add_child(label)
		var mi := MeshInstance3D.new()
		mi.name = "SignGantry"
		mi.mesh = metal.commit(null, _mats.plain(Color(0.62, 0.64, 0.64), 0.45, 0.6))
		panels.commit(mi.mesh as ArrayMesh, _mats.plain(Color(0.0, 0.42, 0.25), 0.6))
		root.add_child(mi)
		# The yellow warning sign on the right, further back.
		var warn: Dictionary = g.get("warning", {})
		if not warn.is_empty():
			var wsp: Array = RoadNetwork.sample(pts, maxf(2.0, best.length - dist - float(warn.get("before_m", 40.0))))
			var wp: Vector2 = (wsp[0] as Vector2) + Vector2(-(wsp[1] as Vector2).y, (wsp[1] as Vector2).x) * (best.half_width + best.shoulder + 1.2)
			var post := _post(root, wp, 2.8)
			var diamond := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.75, 0.75, 0.03)
			box.material = _mats.plain(Color(0.98, 0.78, 0.05), 0.5)
			diamond.mesh = box
			diamond.position = Vector3(0, 2.4, 0.06)
			diamond.rotation.z = PI * 0.25
			post.add_child(diamond)
			post.rotation.y = StreetProps.yaw_facing(-(wsp[1] as Vector2))
			var sym := Label3D.new()
			sym.text = str(warn.get("text", "⟳"))
			sym.font_size = 64
			sym.pixel_size = 0.006
			sym.outline_size = 0
			sym.modulate = Color(0.05, 0.05, 0.05)
			sym.position = Vector3(0, 2.4, 0.09)
			post.add_child(sym)
			if warn.has("tab"):
				var tab := MeshInstance3D.new()
				var tb := BoxMesh.new()
				tb.size = Vector3(0.45, 0.4, 0.03)
				tb.material = box.material
				tab.mesh = tb
				tab.position = Vector3(0, 1.75, 0.06)
				post.add_child(tab)
				var tl := Label3D.new()
				tl.text = str(warn["tab"])
				tl.font_size = 64
				tl.pixel_size = 0.0035
				tl.outline_size = 0
				tl.modulate = Color(0.05, 0.05, 0.05)
				tl.position = Vector3(0, 1.75, 0.09)
				post.add_child(tl)
		if not faces.is_empty():
			var body := StaticBody3D.new()
			body.name = "GantryPosts"
			body.collision_layer = Layers.SOLID
			body.collision_mask = 0
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			root.add_child(body)


static func _longest_line(text: String) -> float:
	var n := 1
	for line in text.split("\n"):
		n = maxi(n, line.length())
	return float(n)


## Collision for a gantry leg: a box 1.2 m along the road, 0.3 m across.
static func _post_faces(q: Vector2, g: float, top: float, t: Vector2) -> PackedVector3Array:
	var side := Vector2(-t.y, t.x)
	var corners := [q + t * 0.6 + side * 0.15, q - t * 0.6 + side * 0.15, q - t * 0.6 - side * 0.15, q + t * 0.6 - side * 0.15]
	var out := PackedVector3Array()
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		out.append_array(PackedVector3Array([MeshKit.v3(a, g), MeshKit.v3(b, g), MeshKit.v3(b, top), MeshKit.v3(a, g), MeshKit.v3(b, top), MeshKit.v3(a, top)]))
	return out


# --- cars parked along the curbs -------------------------------------------------------------

## Every car that can stand parked: the first few along the curbs (as
## often as PARKED_ODDS says), the rest only on their own dealers' lots.
const PARKED_MODELS := ["civique", "halfton", "pony_gt", "jaunt", "rammer",
	"interlude", "cr_eh", "haulux", "pious", "corollary", "grand_caravel", "charlatan", "crown_vista", "bucko",
	"cavalcade", "camarillo", "yukoner", "roadmeister", "sylph", "rouge", "filly", "ironiq", "sole",
	"gadfly", "imprezzo", "hinterland"]
const PARKED_ODDS := [0.45, 0.22, 0.1, 0.13, 0.1] ## how common each curbside model is
## Everyday car colours, as sRGB.
const PARKED_COLOURS := [
	Color(0.92, 0.92, 0.9), Color(0.62, 0.63, 0.64), Color(0.33, 0.34, 0.36), Color(0.08, 0.08, 0.09),
	Color(0.13, 0.2, 0.36), Color(0.5, 0.08, 0.07), Color(0.15, 0.27, 0.2), Color(0.66, 0.6, 0.5),
	Color(0.24, 0.36, 0.52), Color(0.92, 0.92, 0.9), Color(0.62, 0.63, 0.64), Color(0.08, 0.08, 0.09),
]
const PARK_SLOT := 6.5 ## metres of curb per parked car
## Parked cars and overhead wires are only drawn this close (metres).
const PARKED_DRAW_DISTANCE := 150.0
## m: lamp posts and street lights past this are under a pixel or two wide.
const LAMP_DRAW_DISTANCE := 300.0
const WIRE_DRAW_DISTANCE := 260.0
const PARK_CLEAR := 9.0 ## kept clear each side of a junction
const PARK_LANE_CLEAR := 1.5 ## and each side of a lane or lot entrance

## Cars parked against the curb on town streets, so something passes close by
## as you drive, the way it does on real streets. Residential streets get
## a few, downtown streets more. Which side has parking goes by the width:
## a narrow street gets one side, a wide one both, and arterials none,
## except those named in map_config.json "curb_parking".
## Seeded by position, so the same cars are parked every time. All the cars
## of a model in a chunk are one MultiMesh (two draw calls), coloured per
## car, with one static body for their collision.
func _curb_parking(root: Node3D) -> void:
	var heritage_r := float(data.config.get("heritage_district_m", 900.0))
	var xforms: Array[Array] = []
	var colours: Array[Array] = []
	var shapes: Array[Array] = []
	for v in PARKED_MODELS.size():
		xforms.append([])
		colours.append([])
		shapes.append([])
	var body := StaticBody3D.new()
	body.name = "ParkedCars"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var curb_cfg: Dictionary = data.config.get("curb_parking", {})
	for e in net.edges_near(rect):
		if e.is_highway() or e.bridge or e.roundabout:
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		var downtown := mid.length() < heritage_r
		var town_class := e.highway in ["residential", "unclassified"]
		var main_class := e.highway in ["tertiary", "secondary"]
		# A main road named in "curb_parking" gets a few cars along both
		# curbs, on its stretches with at most "max_lanes" lanes.
		var named: Dictionary = curb_cfg.get(e.name) if curb_cfg.get(e.name) is Dictionary else {}
		if not named.is_empty() and (e.oneway != 0 or e.lanes > int(named.get("max_lanes", 99))):
			named = {}
		if not town_class and not (main_class and downtown) and named.is_empty():
			continue
		var width := e.half_width * 2.0
		var sides: Array[int] = []
		if e.oneway != 0:
			if width >= 9.5:
				sides = [1, -1]
			elif width >= 6.0:
				sides = [1]
		elif width >= 10.5:
			sides = [1, -1]
		elif width >= 8.0:
			sides = [1 if (e.name.hash() & 1) == 0 else -1]
		if not named.is_empty():
			sides = [1, -1]
		if sides.is_empty():
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + _park_clear(e.a)
		var stop := e.length - net.mouth_distance(e.b, kb) - _park_clear(e.b)
		if stop - start < PARK_SLOT:
			continue
		var odds := 0.42 if downtown else 0.2
		if not named.is_empty():
			odds = float(named.get("odds", 0.15))
		for side in sides:
			var k := 0
			var d := start + PARK_SLOT * 0.5
			while d < stop:
				var h := hash(Vector3i(e.index, side, k))
				k += 1
				var dd := d
				d += PARK_SLOT
				if float(h % 1000) / 1000.0 > odds:
					continue
				dd += (float((h >> 10) % 100) / 100.0 - 0.5) * 0.8
				var sp: Array = RoadNetwork.sample(e.points, dd)
				var dir: Vector2 = sp[1]
				var right := Vector2(-dir.y, dir.x)
				var at: Vector2 = (sp[0] as Vector2) + right * float(side) * (e.half_width - 1.15)
				if not _inside(at) or net.road_at(at, e, -1.2) != null or net.in_junction(at) or _kept_clear(at) or data.erased(at):
					continue
				# Facing with the traffic on that side of the street.
				var facing := dir
				if (e.oneway == 0 and side < 0) or e.oneway < 0:
					facing = -dir
				var v := _pick_model(h)
				var y0 := terrain.at(at - facing * 1.8).y
				var y1 := terrain.at(at + facing * 1.8).y
				var basis := Basis(Vector3.UP, atan2(-facing.x, -facing.y) + (float((h >> 17) % 100) / 100.0 - 0.5) * 0.05) \
					* Basis(Vector3.RIGHT, atan2(y1 - y0, 3.6))
				var origin := Vector3(at.x, (y0 + y1) * 0.5 + 0.03, at.y)
				_park(body, xforms, colours, shapes, v, Transform3D(basis, origin), PARKED_COLOURS[(h >> 7) % PARKED_COLOURS.size()])
	# And the cars in busy lots' stalls (_parking_stalls), in the same
	# MultiMeshes.
	for car: Array in _lot_cars:
		_park(body, xforms, colours, shapes, car[2], car[0], car[1])
	_add_parked(root, body, xforms, colours, shapes, "Parked_%s", false)


## How far back from a junction parked cars stop: the full clearance at a
## crossroads, only a little either side of a lane or lot entrance.
func _park_clear(nid: String) -> float:
	if net.degree(nid) >= 3 and net.major_degree(nid) < 3:
		return PARK_LANE_CLEAR
	return PARK_CLEAR


# --- cars for sale on dealers' lots ----------------------------------------------------------

## Car dealers built in this chunk (BuildingGenerator.dealers) and the
## parking lots round them (BuildingGenerator.parking).
var dealers: Array = []
var dealer_lots: Array[PackedVector2Array] = []
const SALE_SPACING := 2.9 ## metres between cars side by side
const SALE_ROW := 6.4 ## metres from one row to the next (display rows, packed tight)
const SALE_REACH := 70.0 ## how far from the dealer its lot can reach
const SALE_MAX := 18 ## cars for sale on one dealer's lot (the ones nearest the showroom)
## Showroom-fresh colours: more white, black, silver and red than the street.
const SALE_COLOURS := [
	Color(0.95, 0.95, 0.94), Color(0.06, 0.06, 0.07), Color(0.7, 0.71, 0.73), Color(0.62, 0.05, 0.05),
	Color(0.12, 0.23, 0.45), Color(0.35, 0.36, 0.38), Color(0.95, 0.95, 0.94), Color(0.06, 0.06, 0.07),
	Color(0.7, 0.71, 0.73), Color(0.1, 0.3, 0.22), Color(0.76, 0.42, 0.1), Color(0.2, 0.45, 0.7),
]


## Rows of new cars for sale on the dealer's lot, noses toward the street,
## the way dealers line them up: on the mapped parking next to the dealer,
## or, where the lot isn't mapped, on the ground between the front of the
## building and the street. Same MultiMesh and collision as curb parking.
func _dealer_lots(root: Node3D) -> void:
	if dealers.is_empty():
		return
	var xforms: Array[Array] = []
	var colours: Array[Array] = []
	var shapes: Array[Array] = []
	for v in PARKED_MODELS.size():
		xforms.append([])
		colours.append([])
		shapes.append([])
	var body := StaticBody3D.new()
	body.name = "CarsForSale"
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	for d: Dictionary in dealers:
		var ring: PackedVector2Array = d["ring"]
		var showroom: PackedVector2Array = d["showroom"]
		var fr: Array = d["front"]
		var t: Vector2 = ((fr[1] as Vector2) - (fr[0] as Vector2)).normalized()
		var out := Vector2(t.y, -t.x)
		var stock: Array[int] = []
		for id: Variant in d["stock"]:
			var k := PARKED_MODELS.find(str(id))
			if k >= 0:
				stock.append(k)
		if stock.is_empty():
			stock = [0, 1, 2]
		var centre := BuildingGenerator._centre(ring)
		# The lots: mapped parking touching the dealer, else the ground in
		# front of the building out to the street.
		var lots: Array[PackedVector2Array] = []
		# A big lot that the building stands right against counts however far
		# off its middle is (the cars still go nearest the showroom).
		for lot in dealer_lots:
			var gap := _ring_gap(lot, ring)
			if gap < 12.0 and (gap < 1.0 or BuildingGenerator._centre(lot).distance_to(centre) < SALE_REACH):
				lots.append(lot)
		if lots.is_empty():
			var mid := ((fr[0] as Vector2) + (fr[1] as Vector2)) * 0.5
			var hit := net.nearest_on_streets(mid + out * 8.0, 80.0)
			var reach := 30.0
			if not hit.is_empty():
				var e: RoadNetwork.RoadEdge = hit["edge"]
				reach = clampf(((hit["pos"] as Vector2) - mid).dot(out) - e.half_width - maxf(e.walk(1), e.walk(-1)) - 1.5, 0.0, 45.0)
			# Along the street past both ends of the building, the way a
			# dealer lines its frontage with cars.
			var half := (fr[0] as Vector2).distance_to(fr[1]) * 0.5 + 18.0
			if reach >= 8.0:
				lots.append(PackedVector2Array([mid - t * half, mid + t * half, mid + t * half + out * reach, mid - t * half + out * reach]))
		# Every spot a car could go, then the ones nearest the showroom.
		var spots: Array = []
		var show_c := BuildingGenerator._centre(showroom)
		for lot in lots:
			# Rows parallel to the front, laid out from the building outward.
			var lo_t := INF
			var hi_t := -INF
			var lo_o := INF
			var hi_o := -INF
			var mid0 := (fr[0] as Vector2)
			for q in lot:
				lo_t = minf(lo_t, (q - mid0).dot(t))
				hi_t = maxf(hi_t, (q - mid0).dot(t))
				lo_o = minf(lo_o, (q - mid0).dot(out))
				hi_o = maxf(hi_o, (q - mid0).dot(out))
			var row := 0
			var o := maxf(lo_o, 0.0) + 3.0
			while o < hi_o - 2.0 and row < 8:
				var a := lo_t + 1.6
				while a < hi_t - 1.4:
					var at := mid0 + t * a + out * o
					var h := hash(Vector3i(int(at.x * 10.0), int(at.y * 10.0), 7))
					a += SALE_SPACING
					# Nose toward the street, the car body inside the lot.
					var nose := at + out * 2.4
					var tail := at - out * 2.4
					if not Geometry2D.is_point_in_polygon(nose, lot) or not Geometry2D.is_point_in_polygon(tail, lot):
						continue
					if not net.clear_of_roads(nose, 1.0) or not net.clear_of_roads(tail, 1.0) or not net.clear_of_roads(at, 1.0):
						continue
					if not _off_sidewalks(nose, 0.8) or not _off_sidewalks(at, 1.2):
						continue
					if _in_building(at, 1.6) or _in_building(nose, 1.2) or _in_building(tail, 1.2) or _kept_clear(at):
						continue
					if Geometry2D.is_point_in_polygon(at, showroom) or _ring_gap(PackedVector2Array([nose, tail]), showroom) < 1.5:
						continue
					if h % 9 == 0:
						continue # a gap here and there, where one's been sold
					spots.append([at.distance_to(show_c), at, h])
				o += SALE_ROW
				row += 1
		spots.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for i in mini(SALE_MAX, spots.size()):
			var at: Vector2 = spots[i][1]
			var h: int = spots[i][2]
			var v: int = stock[(h >> 4) % stock.size()]
			var y0 := terrain.at(at - out * 2.4).y
			var y1 := terrain.at(at + out * 2.4).y
			var basis := Basis(Vector3.UP, atan2(-out.x, -out.y)) * Basis(Vector3.RIGHT, atan2(y1 - y0, 4.8))
			var origin := Vector3(at.x, (y0 + y1) * 0.5 + 0.03, at.y)
			_park(body, xforms, colours, shapes, v, Transform3D(basis, origin), SALE_COLOURS[(h >> 9) % SALE_COLOURS.size()])
	_add_parked(root, body, xforms, colours, shapes, "ForSale_%s", true)


## True if p is at least `pad` metres beyond the nearest street's sidewalk
## (or its curb, where it has none).
func _off_sidewalks(p: Vector2, pad: float) -> bool:
	var hit := net.nearest_on_streets(p, 30.0)
	if hit.is_empty():
		return true
	var e: RoadNetwork.RoadEdge = hit["edge"]
	return float(hit["dist"]) >= e.half_width + maxf(e.walk(1), e.walk(-1)) + pad


## Shortest distance between the corners and edges of two rings (0 if
## one has a corner inside the other).
static func _ring_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var best := INF
	for p in a:
		if b.size() >= 3 and Geometry2D.is_point_in_polygon(p, b):
			return 0.0
		for i in b.size():
			best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, b[i], b[(i + 1) % b.size()])))
	for p in b:
		if a.size() >= 3 and Geometry2D.is_point_in_polygon(p, a):
			return 0.0
	return best


## One parked car of model `v` at `xf`: its place in the model's MultiMesh
## and its box in the shared collision body. Skipped where a car has been
## driven off from (see claim_parked), so a rebuilt chunk doesn't put it back.
func _park(body: StaticBody3D, xforms: Array[Array], colours: Array[Array], shapes: Array[Array], v: int, xf: Transform3D, colour: Color) -> void:
	if _is_taken(xf.origin):
		return
	xforms[v].append(xf)
	colours[v].append(colour)
	var cs := CollisionShape3D.new()
	cs.shape = _parked_shapes[v]
	cs.transform = Transform3D(xf.basis, xf.origin + xf.basis.y * _parked_shapes[v].size.y * 0.55)
	body.add_child(cs)
	shapes[v].append(cs)


# --- getting into a parked car ------------------------------------------------------------------

## Spots parked cars have been driven away from (rounded to half a metre).
## Chunks are built on worker threads, so it's behind a mutex.
static var _taken := {}
static var _taken_lock := Mutex.new()


static func _spot_key(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x * 2.0), roundi(p.z * 2.0))


static func _is_taken(p: Vector3) -> bool:
	_taken_lock.lock()
	var t := _taken.has(_spot_key(p))
	_taken_lock.unlock()
	return t


## The parked (or for-sale) car whose driver's door is nearest `pos`, within
## `reach` metres: {"mmi", "index", "door", "model_id", "for_sale"}, or {}
## if there's none. A car for sale is locked until it's bought.
static func nearest_parked(tree: SceneTree, pos: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for n: Node in tree.get_nodes_in_group("parked_cars"):
		var mmi := n as MultiMeshInstance3D
		if mmi == null or not mmi.is_visible_in_tree():
			continue
		var gx := mmi.global_transform
		if not (gx * (mmi.get_meta("bounds") as AABB)).grow(reach).has_point(pos):
			continue
		var shape: Dictionary = CarModels.get_model(str(mmi.get_meta("model_id")))["shape"]
		var door_local := Vector3(-(float(shape["width"]) * 0.5 + 0.15), 0.0, float(shape["seat"][2]))
		var list: Array = mmi.get_meta("xforms")
		for i in list.size():
			if list[i] == null:
				continue # already driven off
			var door: Vector3 = gx * (list[i] as Transform3D) * door_local
			var d := door.distance_to(pos)
			if d < best_d:
				best_d = d
				best = {"mmi": mmi, "index": i, "door": door, "model_id": str(mmi.get_meta("model_id")), "for_sale": bool(mmi.get_meta("for_sale"))}
	return best


## Takes the parked car `hit` (from nearest_parked) off the street, for a
## real Car to stand in its place: hides it, drops its collision box and
## remembers the spot. Returns {"model_id", "paint", "xform"}.
static func claim_parked(hit: Dictionary) -> Dictionary:
	var mmi: MultiMeshInstance3D = hit["mmi"]
	var i: int = hit["index"]
	var list: Array = mmi.get_meta("xforms")
	var local: Transform3D = list[i]
	var xf := mmi.global_transform * local
	var c: Color = (mmi.get_meta("colours") as Array)[i]
	list[i] = null
	mmi.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), local.origin))
	var shadow: MultiMesh = mmi.get_meta("shadow", null)
	if shadow != null:
		shadow.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), local.origin))
	var shapes: Array = mmi.get_meta("shapes")
	if i < shapes.size() and is_instance_valid(shapes[i]):
		(shapes[i] as CollisionShape3D).set_deferred("disabled", true)
	_taken_lock.lock()
	_taken[_spot_key(xf.origin)] = true
	_taken_lock.unlock()
	return {"model_id": str(mmi.get_meta("model_id")), "paint": Color(c.r, c.g, c.b), "xform": xf}


static var _lamp_shadow: Mesh = null


## A post and a lantern box the size of the heritage lamp, for its shadow.
static func _lamp_shadow_stand_in() -> Mesh:
	if _lamp_shadow != null:
		return _lamp_shadow
	var b := _heritage_lamp.get_aabb()
	var h := b.size.y
	var c := b.get_center()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := BoxMesh.new()
	post.size = Vector3(0.14, h * 0.86, 0.14)
	st.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(c.x, b.position.y + h * 0.43, c.z)))
	var lantern := BoxMesh.new()
	lantern.size = Vector3(minf(b.size.x, 0.45), h * 0.16, minf(b.size.z, 0.45))
	st.append_from(lantern, 0, Transform3D(Basis.IDENTITY, Vector3(c.x, b.position.y + h * 0.92, c.z)))
	_lamp_shadow = st.commit()
	_lamp_shadow.surface_set_material(0, Materials.get_shared().shadow_caster())
	return _lamp_shadow


## A body box and a cabin box filling a parked car's bounds, for its shadow.
static func _shadow_stand_in(b: AABB) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := b.size.y
	var c := b.get_center()
	var boxes := [
		AABB(Vector3(b.position.x + b.size.x * 0.03, b.position.y + h * 0.15, b.position.z + b.size.z * 0.01),
			Vector3(b.size.x * 0.94, h * 0.45, b.size.z * 0.98)),
		AABB(Vector3(c.x - b.size.x * 0.42, b.position.y + h * 0.55, c.z - b.size.z * 0.26),
			Vector3(b.size.x * 0.84, h * 0.45, b.size.z * 0.52)),
	]
	for box: AABB in boxes:
		var bm := BoxMesh.new()
		bm.size = box.size
		st.append_from(bm, 0, Transform3D(Basis.IDENTITY, box.get_center()))
	var mesh := st.commit()
	mesh.surface_set_material(0, Materials.get_shared().shadow_caster())
	return mesh


## The cars collected by model into one MultiMesh each, with their shared
## collision body.
## `for_sale` marks a dealer's stock, locked until bought.
func _add_parked(root: Node3D, body: StaticBody3D, xforms: Array[Array], colours: Array[Array], shapes: Array[Array], name_fmt: String, for_sale: bool) -> void:
	if body.get_child_count() == 0:
		body.free()
		return
	root.add_child(body)
	for v in PARKED_MODELS.size():
		if xforms[v].is_empty():
			continue
		# One MultiMesh per model per tile, so the cars down the street
		# drop to their simpler LODs and the ones behind are culled.
		var g := TiledMulti.groups(xforms[v])
		for key: Vector2i in g:
			_add_parked_tile(root, v, key, g[key], xforms[v], colours[v], shapes[v], name_fmt, for_sale)


func _add_parked_tile(root: Node3D, v: int, key: Vector2i, idx: Array, all_xf: Array, all_colours: Array, all_shapes: Array, name_fmt: String, for_sale: bool) -> void:
	var list: Array = []
	var tile_colours: Array = []
	var tile_shapes: Array = []
	for i in idx:
		list.append(all_xf[i])
		tile_colours.append(all_colours[i])
		tile_shapes.append(all_shapes[i])
	# The paint colour goes in the custom data, which only the paint
	# surface reads (shaders/car_paint_parked.gdshader).
	var every := range(list.size())
	var mm := TiledMulti.multimesh(_parked_mesh(v), list, every, tile_colours)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = (name_fmt % PARKED_MODELS[v]) + "_t%d_%d" % [key.x, key.y]
	mmi.set_meta("label", name_fmt % PARKED_MODELS[v])
	mmi.multimesh = mm
	# A parked car is thousands of triangles; past this it's a speck.
	mmi.visibility_range_end = PARKED_DRAW_DISTANCE
	# So the player can get in (see nearest_parked).
	mmi.set_meta("model_id", PARKED_MODELS[v])
	mmi.set_meta("for_sale", for_sale)
	var bounds := AABB((list[0] as Transform3D).origin, Vector3.ZERO)
	for xf: Transform3D in list:
		bounds = bounds.expand(xf.origin)
	mmi.set_meta("bounds", bounds.grow(4.0)) # the car's half-length and its door
	mmi.set_meta("xforms", list)
	mmi.set_meta("colours", tile_colours)
	mmi.set_meta("shapes", tile_shapes)
	mmi.add_to_group("parked_cars")
	root.add_child(mmi)
	# The shadow comes from the stand-in, not the car itself.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smm := TiledMulti.multimesh(_parked_shadows[v], list, every)
	var shadow := MultiMeshInstance3D.new()
	shadow.name = mmi.name + "_shadow"
	shadow.multimesh = smm
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	shadow.visibility_range_end = PARKED_DRAW_DISTANCE
	root.add_child(shadow)
	mmi.set_meta("shadow", smm)


## A parked model's mesh (and its shadow stand-in), built the first time
## it's asked for.
static func _parked_mesh(v: int) -> ArrayMesh:
	_parked_lock.lock()
	if _parked[v] == null:
		var shape: Dictionary = CarModels.get_model(PARKED_MODELS[v])["shape"]
		_parked[v] = CarBuilder.new(shape, Color.WHITE).make_parked()
		_parked_shadows[v] = _shadow_stand_in(_parked[v].get_aabb())
	var mesh := _parked[v]
	_parked_lock.unlock()
	return mesh


func _pick_model(h: int) -> int:
	var r := float((h >> 13) % 100) / 100.0
	for v in PARKED_ODDS.size():
		r -= float(PARKED_ODDS[v])
		if r < 0.0:
			return v
	return 0


func _kept_clear(p: Vector2) -> bool:
	for q in data.keep_clear:
		if q.distance_squared_to(p) < 100.0:
			return true
	return false


# --- power poles and wires ------------------------------------------------------------------

const POWER_SPACING := 40.0
## Where the wires hang on a pole: across the road (local x, +x toward it) and up.
const WIRE_POINTS := [Vector2(-0.8, 8.95), Vector2(-0.3, 8.95), Vector2(0.8, 8.95), Vector2(0.2, 6.4)]
## A main road's heavier bundle (University Avenue in Joe's photos): the
## three on the crossarm, a neutral under it, and two telephone and cable
## lines low on the road side.
const WIRE_POINTS_HEAVY := [Vector2(-0.8, 8.95), Vector2(-0.3, 8.95), Vector2(0.8, 8.95),
	Vector2(0.22, 7.7), Vector2(0.2, 6.4), Vector2(0.2, 5.85)]
const WIRE_SAG := 0.35

## Wooden utility poles along town streets outside downtown (where the
## wires are buried), one side of the street, with the wires strung between
## them. The street lights on that side already stand on wooden poles, so
## those get a crossarm and carry the wires too. Each pole draws the span to
## the next one, so a span crossing into the next chunk is drawn once.
## Streets in map_config.json "street_power_lines" can have them down both
## sides ("both_sides"), carry more wires ("heavy") and keep them inside
## the downtown radius ("downtown").
func _power_lines(root: Node3D) -> void:
	var heritage_r := float(data.config.get("heritage_district_m", 900.0))
	var poles: Array = [] # full poles: Transform3D
	var arms: Array = [] # crossarms on street-light poles
	var wires: Array = []
	var along_highways: Dictionary = data.config.get("highway_power_lines", {})
	var busy_streets: Dictionary = data.config.get("street_power_lines", {})
	for e in net.edges_near(rect):
		# A highway named in "highway_power_lines" gets them too, out past
		# the shoulder on the outer side of the carriageway heading the
		# given way.
		var forced: Dictionary = along_highways.get(e.name, {}) if e.is_highway() and e.oneway != 0 else {}
		var side := 1
		var extra := 0.0
		if not forced.is_empty():
			var tp := e.points if e.oneway > 0 else _reversed(e.points)
			var heading: Vector2 = {"north": Vector2(0, -1), "south": Vector2(0, 1), "east": Vector2(1, 0), "west": Vector2(-1, 0)}.get(str(forced.get("heading", "")), Vector2.ZERO)
			if heading != Vector2.ZERO and (tp[tp.size() - 1] - tp[0]).normalized().dot(heading) < 0.5:
				continue
			side = 1 if e.oneway > 0 else -1
			extra = float(forced.get("offset_m", 2.5))
		elif e.is_highway() or e.bridge or e.roundabout or e.walk(1) < 1.0:
			continue
		if e.highway in ["service", "track", "path", "footway", "cycleway", "living_street", "pedestrian"]:
			continue
		var ka := net.incident_index(e.a, e, true)
		var kb := net.incident_index(e.b, e, false)
		var start := net.mouth_distance(e.a, ka) + 6.0
		var stop := e.length - net.mouth_distance(e.b, kb) - 6.0
		if stop - start < POWER_SPACING * 0.5:
			continue
		# A street named in "street_power_lines" can have a line down both
		# sides, the heavier bundle of wires a main road carries, and keep
		# its poles into the downtown radius where the wires are otherwise
		# buried.
		var busy: Dictionary = busy_streets.get(e.name, {}) if forced.is_empty() else {}
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		var in_heritage := mid.length() < heritage_r
		if in_heritage and not bool(busy.get("downtown", false)):
			continue
		var sides: Array[int] = [side]
		if bool(busy.get("both_sides", false)) and e.walk(-1) >= 1.0:
			sides.append(-side)
		var wire_points: Array = WIRE_POINTS_HEAVY if bool(busy.get("heavy", false)) else WIRE_POINTS
		# The same line and spacing the street lights use (see _lamps), so
		# every other pole lands on a street light. On the far side they
		# start half a spacing in, as the lights there do.
		var lit := e.walk(1) + e.walk(-1) > 1.2 and forced.is_empty()
		for s: int in sides:
			var line := net.side_line(e, s, RoadNetwork.Level.PROP)
			var scale := RoadNetwork.polyline_length(line) / e.length
			var spots: Array = []
			var d := start + (STREET_LIGHT_SPACING * 0.5 if s < 0 else 0.0)
			var k := 0
			while d < stop:
				var sp: Array = RoadNetwork.sample(line, d * scale)
				var dir: Vector2 = sp[1]
				var to_road := -Vector2(-dir.y, dir.x) * float(s)
				var at: Vector2 = (sp[0] as Vector2) - to_road * extra
				if net.clear_of_roads(at, 0.2):
					var xf := Transform3D(Basis(Vector3.UP, StreetProps.yaw_along(to_road)), terrain.at(at, SW_H))
					spots.append([xf, lit and k % 2 == 0])
				d += POWER_SPACING
				k += 1
			for i in spots.size():
				var xf: Transform3D = spots[i][0]
				if not _inside(Vector2(xf.origin.x, xf.origin.z)):
					continue
				(arms if spots[i][1] else poles).append(xf)
				if i + 1 < spots.size():
					var nxt: Transform3D = spots[i + 1][0]
					for wp: Vector2 in wire_points:
						var a := xf * Vector3(wp.x, wp.y, 0.0)
						var b := nxt * Vector3(wp.x, wp.y, 0.0)
						var m := (a + b) * 0.5 - Vector3(0, WIRE_SAG, 0)
						wires.append(_wire_xform(a, m))
						wires.append(_wire_xform(m, b))
	if poles.is_empty() and arms.is_empty():
		return
	_multi(root, "UtilityPoles", [_utility_pole, _crossarm], [poles, arms], true)
	if not wires.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _wire
		mm.instance_count = wires.size()
		for i in wires.size():
			mm.set_instance_transform(i, wires[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Wires"
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = WIRE_DRAW_DISTANCE
		root.add_child(mmi)
	if not poles.is_empty():
		var body := StaticBody3D.new()
		body.name = "UtilityPoleBodies"
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		for t: Transform3D in poles:
			var cs := CollisionShape3D.new()
			cs.shape = _pole_shape
			cs.position = t.origin + Vector3(0, 4.0, 0)
			body.add_child(cs)
		root.add_child(body)


static func _reversed(pts: PackedVector2Array) -> PackedVector2Array:
	var r := pts.duplicate()
	r.reverse()
	return r


## A unit wire box (1 m along z) stretched from a to b.
static func _wire_xform(a: Vector3, b: Vector3) -> Transform3D:
	var along := b - a
	var len := along.length()
	if len < 0.01:
		return Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), a)
	var z := along / len
	var x := Vector3.UP.cross(z).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x)
	return Transform3D(Basis(x, y, z * len), (a + b) * 0.5)


## A creosoted utility pole with a crossarm and insulators (whole = true),
## or just the top part (pole above 8.4 m, crossarm and insulators), to
## sit on a street-light pole. Local +X points at the road.
static func _utility_pole_mesh(mats: Materials, whole: bool) -> ArrayMesh:
	var wood := MeshKit.new()
	if whole:
		_limb(wood, Vector3(0, -0.3, 0), Vector3(0, 9.4, 0), 0.15, 0.11)
	else:
		_limb(wood, Vector3(0, 8.4, 0), Vector3(0, 9.4, 0), 0.115, 0.105)
	_limb(wood, Vector3(-1.0, 8.8, 0), Vector3(1.0, 8.8, 0), 0.06, 0.06)
	var porcelain := MeshKit.new()
	for wp: Vector2 in WIRE_POINTS:
		if wp.y > 8.0:
			_limb(porcelain, Vector3(wp.x, 8.84, 0), Vector3(wp.x, 8.97, 0), 0.04, 0.03)
	var mesh := wood.commit(null, mats.plain(Color(0.3, 0.24, 0.18), 0.95))
	porcelain.commit(mesh, mats.plain(Color(0.55, 0.6, 0.55), 0.4))
	return mesh

class_name ChunkBuilder
extends RefCounted
## Builds one square chunk of the town as a detached Node3D, ready to be
## added to the scene. Safe to run on a worker thread: it reads the shared
## map data but never touches the scene tree.
##
## Full detail (near the player): ground at 4 m with its fine ground mask
## and collision, streets with curbs, paint and collision, buildings with
## cornices and awnings and one collision body each, signs, signals, lamps
## and trees.
##
## Low detail (further off): ground at 10 m with the coarse ground mask,
## asphalt and sidewalk tops, plain buildings (windows still drawn), trees,
## no collision and no shadows.

const FULL_GROUND_STEP := 4.0
const LOD_GROUND_STEP := 10.0

static var coarse_mask: Texture2D


static func chunk_rect(data: StreetData, cx: int, cz: int) -> Rect2:
	return Rect2(cx * data.chunk_size, cz * data.chunk_size, data.chunk_size, data.chunk_size)


static func build(data: StreetData, net: RoadNetwork, terrain: Terrain, cx: int, cz: int, lod: bool) -> Node3D:
	var rect := chunk_rect(data, cx, cz)
	var root := Node3D.new()
	root.name = "%s_%d_%d" % ["Far" if lod else "Near", cx, cz]
	var chunk := data.load_chunk(cx, cz)

	# --- ground ---------------------------------------------------------------
	var mask: Texture2D = null
	var mask_origin := rect.position
	var mask_size := rect.size
	var fine := data.city_dir.path_join("masks/%s.png" % StreetData.chunk_key(cx, cz))
	if not lod and ResourceLoader.exists(fine):
		mask = load(fine) as Texture2D
	if mask == null and coarse_mask != null:
		mask = coarse_mask
		mask_origin = terrain.origin
		mask_size = Vector2((terrain.nx - 1) * terrain.spacing, (terrain.nz - 1) * terrain.spacing)
	var mat := Terrain.ground_material(mask, mask_origin, mask_size)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	# The ground is carved down a little under the streets (a 2 m grid,
	# which both the 4 m and 10 m ground and the 2 m collision sample).
	var carve := net.street_mask(rect, terrain.spacing)
	ground.mesh = terrain.chunk_mesh(rect, LOD_GROUND_STEP if lod else FULL_GROUND_STEP, mat, carve, terrain.spacing)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)
	if not lod:
		var body := StaticBody3D.new()
		body.name = "GroundCollision"
		body.collision_layer = Layers.GROUND
		body.collision_mask = 0
		body.add_child(terrain.chunk_collision(rect, carve))
		root.add_child(body)

	# --- streets, buildings, props ---------------------------------------------
	root.add_child(RoadMesher.new(net, data, terrain, rect, lod).build())
	var buildings := Node3D.new()
	buildings.name = "Buildings"
	root.add_child(buildings)
	var count := BuildingGenerator.new(data, net, terrain).build_chunk(chunk.buildings, buildings, lod, chunk.areas, Vector2i(cx, cz))
	root.add_child(StreetProps.new(net, data, terrain, rect, chunk, lod).build())
	root.set_meta("buildings", count)

	if lod:
		_no_shadows(root)
	return root


## The close-up building mesh for a chunk (see BuildingGenerator.build_detail_mesh).
static func build_detail(data: StreetData, net: RoadNetwork, terrain: Terrain, cx: int, cz: int) -> ArrayMesh:
	var chunk := data.load_chunk(cx, cz)
	return BuildingGenerator.new(data, net, terrain).build_detail_mesh(chunk.buildings, chunk.areas, Vector2i(cx, cz))


static func _no_shadows(node: Node) -> void:
	for c in node.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_no_shadows(c)

class_name GroundAreas
extends RefCounted
## Paints the ground between the streets from OSM: parking lots, lawns and
## parks, brick plazas, and footpaths. These are what make a block read as
## "the lawn in front of Province House" or "a parking lot behind Queen
## Street" instead of one flat colour.
##
## Each kind sits a centimetre above the last, all below the road surface
## (y = 0), so streets and sidewalks always cover them where they overlap.

const Y_PARKING := -0.05
const Y_GRASS := -0.04
const Y_PLAZA := -0.03
const Y_PATH := -0.02

const GRASS_TYPES := ["landuse=grass", "landuse=village_green", "landuse=flowerbed", "landuse=religious",
	"landuse=forest", "leisure=park", "leisure=garden", "leisure=playground", "natural=wood",
	"natural=scrub", "natural=grassland"]
const PLAZA_TYPES := ["highway=pedestrian", "highway=footway", "area:highway=pedestrian",
	"area:highway=footway", "place=square", "leisure=outdoor_seating", "amenity=fountain"]
const PATH_CLASSES := {"footway": 2.2, "pedestrian": 4.0, "path": 1.6, "steps": 2.0}

var data: StreetData


func _init(street_data: StreetData) -> void:
	data = street_data


func build() -> Node3D:
	var root := Node3D.new()
	root.name = "GroundAreas"
	var parking := MeshKit.new()
	var grass := MeshKit.new()
	var plaza := MeshKit.new()
	for a in data.areas:
		var kind := _kind(a)
		match kind:
			"parking":
				_fill(parking, a.ring, Y_PARKING)
			"grass":
				_fill(grass, a.ring, Y_GRASS)
			"plaza":
				_fill(plaza, a.ring, Y_PLAZA)
	var paths := MeshKit.new()
	for r in data.roads:
		if PATH_CLASSES.has(r.highway) and str(r.tags.get("area", "")) != "yes":
			_strip(paths, r.points, float(PATH_CLASSES[r.highway]), Y_PATH)

	var mats := Materials.get_shared()
	_add(root, "Parking", parking, mats.parking)
	_add(root, "Lawns", grass, mats.grass)
	_add(root, "Plazas", plaza, mats.pavers)
	_add(root, "Paths", paths, mats.path_brick)
	return root


func _kind(a: StreetData.GroundArea) -> String:
	var surface := str(a.tags.get("surface", ""))
	if surface == "grass":
		return "grass"
	if surface in ["paving_stones", "brick", "sett", "concrete"] and not a.type == "amenity=parking":
		return "plaza"
	if a.type == "amenity=parking" or surface == "asphalt":
		return "parking"
	if GRASS_TYPES.has(a.type):
		return "grass"
	if PLAZA_TYPES.has(a.type):
		return "plaza"
	return ""


static func _fill(kit: MeshKit, ring: PackedVector2Array, y: float) -> void:
	var idx := Geometry2D.triangulate_polygon(ring)
	for i in range(0, idx.size(), 3):
		kit.ground_tri(MeshKit.v3(ring[idx[i]], y), MeshKit.v3(ring[idx[i + 1]], y), MeshKit.v3(ring[idx[i + 2]], y))


## A flat strip along a polyline, with a square pad at each bend so turns
## have no gaps.
static func _strip(kit: MeshKit, pts: PackedVector2Array, width: float, y: float) -> void:
	var hw := width * 0.5
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_to(b) < 0.01:
			continue
		var d := (b - a).normalized()
		var r := Vector2(-d.y, d.x) * hw
		kit.ground_quad(MeshKit.v3(a + r, y), MeshKit.v3(b + r, y), MeshKit.v3(b - r, y), MeshKit.v3(a - r, y))
		if i > 0:
			var px := Vector2(hw, 0.0)
			var pz := Vector2(0.0, hw)
			kit.ground_quad(MeshKit.v3(a - px - pz, y), MeshKit.v3(a + px - pz, y), MeshKit.v3(a + px + pz, y), MeshKit.v3(a - px + pz, y))


static func _add(root: Node3D, mesh_name: String, kit: MeshKit, mat: Material) -> void:
	if kit.is_empty():
		return
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = kit.commit(null, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

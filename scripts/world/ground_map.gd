class_name GroundMap
extends RefCounted
## What the open ground is to drive on, a square metre at a time: lawn,
## rough grass, a farm field's mud, a bog, sand, a gravel trail or pavement.
##
## Made with the ground masks by tools/make_ground_mask.py, from the same
## OSM areas in the same order, so what a tyre feels is what the ground
## shows. One map per chunk (data/city/ground/X_Z.bin, a byte per metre,
## zlib-compressed); a chunk with no file is rough grass throughout.
##
## A chunk's ground collision carries its map (meta "ground_map"), so a
## tyre's ray hit says what it's on (kind_of_hit). Anything that isn't open
## ground (a street, a sidewalk, a parkade floor, a truck's deck) is paved.

const PAVED := 0
const GRAVEL := 1
const LAWN := 2
const ROUGH := 3
const FIELD := 4
const WET := 5
const SAND := 6

## How each kind drives (index by kind):
##   name     for the HUD and tests
##   grip     times the tyre's grip on pavement
##   rolling  rolling resistance, a share of the weight on the tyre (on
##            top of the car's own rolling resistance)
##   churn    more resistance per m/s: grass and mud pushed aside, so the
##            faster you try to go the harder it holds you back
##   sink     how far (m) a tyre at its usual load settles in, standing
##   dig      how much deeper (m) it can dig itself, spinning
##   bump     how uneven it is (m): tussocks, furrows, ruts
##   soft     0 for firm ground; how much it throws up and marks (0..1)
##   mud      the colour of what sticks and flies off (sRGB)
const KINDS: Array[Dictionary] = [
	{"name": "pavement", "grip": 1.0, "rolling": 0.0, "churn": 0.0, "sink": 0.0, "dig": 0.0, "bump": 0.0, "soft": 0.0, "mud": Color(0.3, 0.3, 0.3)},
	{"name": "gravel", "grip": 0.72, "rolling": 0.012, "churn": 0.0006, "sink": 0.0, "dig": 0.01, "bump": 0.015, "soft": 0.25, "mud": Color(0.55, 0.5, 0.42)},
	{"name": "lawn", "grip": 0.72, "rolling": 0.022, "churn": 0.004, "sink": 0.005, "dig": 0.02, "bump": 0.01, "soft": 0.2, "mud": Color(0.3, 0.32, 0.17)},
	{"name": "rough grass", "grip": 0.66, "rolling": 0.035, "churn": 0.006, "sink": 0.01, "dig": 0.03, "bump": 0.03, "soft": 0.3, "mud": Color(0.36, 0.3, 0.2)},
	# PEI's red clay, ploughed and wet.
	{"name": "field", "grip": 0.42, "rolling": 0.07, "churn": 0.035, "sink": 0.05, "dig": 0.11, "bump": 0.035, "soft": 1.0, "mud": Color(0.42, 0.2, 0.13)},
	{"name": "bog", "grip": 0.36, "rolling": 0.09, "churn": 0.045, "sink": 0.08, "dig": 0.12, "bump": 0.02, "soft": 1.0, "mud": Color(0.2, 0.17, 0.11)},
	{"name": "sand", "grip": 0.5, "rolling": 0.08, "churn": 0.03, "sink": 0.06, "dig": 0.1, "bump": 0.01, "soft": 0.8, "mud": Color(0.72, 0.64, 0.48)},
]

## Metres per cell.
const CELL := 1.0

var origin := Vector2.ZERO
var cells := 0 ## along each side
var data := PackedByteArray() ## kinds, row by row (z), each row along x
var fill := ROUGH ## everywhere, when there's no data


## The map for one chunk (`rect` its square), or one of rough grass if the
## chunk has no file. Safe on a worker thread.
static func load_chunk(city_dir: String, key: String, rect: Rect2) -> GroundMap:
	var m := GroundMap.new()
	m.origin = rect.position
	m.cells = int(round(rect.size.x / CELL))
	var path := city_dir.path_join("ground/%s.bin" % key)
	if FileAccess.file_exists(path):
		var packed := FileAccess.get_file_as_bytes(path)
		var raw := packed.decompress(m.cells * m.cells, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == m.cells * m.cells:
			m.data = raw
	return m


## One kind everywhere (a test pad of mud, say).
static func uniform(kind: int) -> GroundMap:
	var m := GroundMap.new()
	m.fill = kind
	return m


## The kind at world (x, z).
func kind_at(x: float, z: float) -> int:
	if data.is_empty():
		return fill
	var ix := int(floor((x - origin.x) / CELL))
	var iz := int(floor((z - origin.y) / CELL))
	if ix < 0 or iz < 0 or ix >= cells or iz >= cells:
		return fill
	return data[iz * cells + ix]


## Marks a collision body as open ground of this map.
func attach(body: CollisionObject3D) -> void:
	body.set_meta("ground_map", self)


## What a ray hit is to drive on: its body's ground map at the spot, or
## pavement for anything that isn't open ground.
static func kind_of_hit(hit: Dictionary) -> int:
	var body := hit.get("collider") as Object
	if body == null or not body.has_meta("ground_map"):
		return PAVED
	var p: Vector3 = hit["position"]
	return (body.get_meta("ground_map") as GroundMap).kind_at(p.x, p.z)


## How uneven the ground is at (x, z), -1..1, the same every time you pass
## (a tussock stays where it is). Fields are furrowed: ridges across x
## about a metre apart, as the shader draws them.
static func bump_at(kind: int, x: float, z: float) -> float:
	if kind == FIELD:
		return sin(x * TAU / 0.9) * 0.6 + _noise(x * 0.7, z * 0.7) * 0.4
	return _noise(x * 1.3, z * 1.3)


static func _noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := lerpf(_hash(ix, iz), _hash(ix + 1, iz), fx)
	var b := lerpf(_hash(ix, iz + 1), _hash(ix + 1, iz + 1), fx)
	return lerpf(a, b, fz) * 2.0 - 1.0


static func _hash(x: int, z: int) -> float:
	var h := (x * 374761393 + z * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0

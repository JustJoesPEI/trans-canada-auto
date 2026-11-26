class_name CarBuilder
extends RefCounted
## Builds a car's meshes from a shape in CarModels, as a detailed scale
## model: a lofted body with panel gaps, a glasshouse you can see into, a
## full interior (dash and gauges, seats, door cards, console, headliner),
## lamp assemblies with reflectors and lenses, grille, wrap-round bumpers,
## plates, badges, mirrors, wipers, exhausts, and wheels with treaded tyres,
## real spokes, lug nuts and brakes behind them.
##
## The body is one mesh of six surfaces, each a shared material:
##   paint  the body colour (vertex colours are a multiplier on it, so panel
##          gaps are darker paint); one material per colour
##   gloss  clear-coated colours: lamps, gloss-black trim, plates, stripes
##   rough  matte: plastics, rubber, carpet and cloth
##   satin  vinyl and leather: seats, dash top, door tops
##   metal  chrome, polished and brushed metal
##   glass  tinted, see-through windows
## Wheels are shared per size and style (tyre and rim), so is the brake
## behind each (it steers but doesn't spin) and the steering wheel.
##
## Faces -Z (the front), wheels on the ground at y = 0, driver on the left.

const TRIM := Color(0.06, 0.06, 0.065) ## black plastic
const GLOSS_BLACK := Color(0.025, 0.025, 0.028)
const GLASS := Color(0.1, 0.13, 0.15, 0.34)
const CHROME := Color(0.93, 0.93, 0.94)
const PLATE := Color(0.92, 0.92, 0.88)
const PLATE_TEXT := Color(0.12, 0.28, 0.2) ## PEI green
const AMBER := Color(0.95, 0.55, 0.08)
const RED_LAMP := Color(0.62, 0.03, 0.03)
const LENS := Color(0.92, 0.95, 1.0, 0.14)
## A 3 x 5 pixel font for the licence plates.
const PLATE_FONT := {
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", ".##", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "C": ["###", "#..", "#..", "#..", "###"],
	"D": ["##.", "#.#", "#.#", "#.#", "##."], "E": ["###", "#..", "##.", "#..", "###"],
	"G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
	"P": ["###", "#.#", "###", "#..", "#.."], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"X": ["#.#", "#.#", ".#.", "#.#", "#.#"], "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
}
## Radius of the rim as a share of the whole wheel, by style.
const RIM_FRAC := {"mag5": 0.64, "alloy10": 0.68, "steel6": 0.6, "black5": 0.68, "gold10": 0.7, "lace": 0.64, "hubcap": 0.62, "aero": 0.7}
## The wheel styles beyond the first three: the spoke pattern each one uses
## (see _rim_solid) and its colours [face, lip, centre cap].
##   black5  five spokes in gloss gunmetal (a modern sport sedan's)
##   gold10  ten-spoke alloys in gold (a rally car's)
##   lace    an 80s lattice of thin spokes
##   hubcap  a plastic wheel cover with slots round it (an economy car's)
##   aero    a flat two-tone cover with a few cut-outs (an electric car's)
const WHEEL_LOOKS := {
	"black5": ["mag5", Color(0.13, 0.13, 0.14), Color(0.2, 0.2, 0.21), Color(0.1, 0.1, 0.11)],
	"gold10": ["alloy10", Color(0.72, 0.56, 0.22), Color(0.78, 0.62, 0.27), Color(0.12, 0.12, 0.13)],
	"lace": ["lace", Color(0.82, 0.82, 0.84), Color(0.92, 0.92, 0.93), Color(0.9, 0.9, 0.91)],
	"hubcap": ["hubcap", Color(0.68, 0.69, 0.71), Color(0.74, 0.75, 0.77), Color(0.6, 0.61, 0.63)],
	"aero": ["aero", Color(0.55, 0.57, 0.6), Color(0.16, 0.16, 0.17), Color(0.14, 0.14, 0.15)],
}
## The raised white letters on a tyre's sidewall: 2 by 3 glyphs, bit
## column * 3 + row (row 0 at the top). Not real letters, but they read as
## them from a step back.
const TYRE_GLYPHS := [0b101111, 0b111101, 0b011111, 0b111011, 0b110111, 0b101101, 0b111110]
## How far the steering wheel turns, radians, at full lock.
const STEER_WHEEL_TURN := 1.75
## Where the hands hold the wheel: just above "9 and 3", radians above level.
const GRIP_ANGLE := 0.3

static var _materials := {}
## The chunk builders' worker threads read _materials (a dealer's parked cars,
## StreetProps._parked_mesh) while the main thread adds a paint to it for each
## new car colour, so it's behind a lock.
static var _materials_lock := Mutex.new()
static var _wheel_meshes := {}

var shape: Dictionary
var paint: Color
## Parked cars: wheels built in, less detail, body colour from the instance.
var parked := false

var _k := {} # surface name -> MeshKit (the one being built into)
var _main := {} # the body's kits
var _detail := {} # near-only kits: the interior (ModelLod)
## The interior, drawn only up close (ModelLod.near_only); set by make_body.
var detail_mesh: ArrayMesh
## The tail lamps' lenses, for lighting them (LampGlow), and while they're
## being drawn.
var lamps: Array = []
var _log_lamps := false
var _seat_col: Color ## seat shells and bolsters, vinyl or leather
var _insert_col: Color ## seat and door inserts, cloth
var _dash_col: Color ## dash top and upper door panels
var _lower_col: Color ## lower dash and console
var _carpet_col: Color
var _trim_style := "metal" ## the strip across the dash and doors: metal, wood or black


func _init(car_shape: Dictionary, body_colour: Color) -> void:
	shape = car_shape
	paint = body_colour
	var ic: Dictionary = shape.get("interior", {})
	_seat_col = Color.html(ic.get("seat", "#2a2a2c"))
	_insert_col = Color.html(ic.get("insert", ic.get("seat", "#3a3a3c")))
	_dash_col = Color.html(ic.get("dash", "#18181a"))
	_lower_col = Color.html(ic.get("lower", ic.get("dash", "#202022")))
	_carpet_col = Color.html(ic.get("carpet", "#121213"))
	_trim_style = ic.get("trim", "metal")


# --- materials --------------------------------------------------------------------------------

## The body colour, as a glossy metallic paint under a clear coat (Forward+
## draws the clear coat; the Compatibility renderer just skips it).
static func paint_material(colour: Color) -> StandardMaterial3D:
	var key := "paint/" + colour.to_html()
	_materials_lock.lock()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.metallic = 0.45
		m.metallic_specular = 0.6
		m.roughness = 0.3
		m.clearcoat_enabled = true
		m.clearcoat = 1.0
		m.clearcoat_roughness = 0.04
		_materials[key] = m
	var out: StandardMaterial3D = _materials[key]
	_materials_lock.unlock()
	return out


## The other shared materials: gloss, rough, metal, glass, rubber, parked_paint.
static func material(kind: String) -> Material:
	_materials_lock.lock()
	if _materials.has(kind):
		var known: Material = _materials[kind]
		_materials_lock.unlock()
		return known
	var mat: Material
	if kind == "parked_paint":
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/car_paint_parked.gdshader")
		mat = sm
	else:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		match kind:
			"gloss":
				m.roughness = 0.12
				m.metallic_specular = 0.7
				m.clearcoat_enabled = true
				m.clearcoat = 1.0
				m.clearcoat_roughness = 0.03
			"rough":
				m.roughness = 0.8
				m.metallic_specular = 0.35
			"satin":
				# Vinyl and leather: a soft sheen.
				m.roughness = 0.42
				m.metallic_specular = 0.45
			"metal":
				m.metallic = 1.0
				m.roughness = 0.16
			"glass":
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				m.roughness = 0.02
				m.metallic_specular = 1.0
			"rubber":
				m.roughness = 0.9
				m.metallic_specular = 0.25
		mat = m
	_materials[kind] = mat
	_materials_lock.unlock()
	return mat


# --- the body -------------------------------------------------------------------------------

## The body; the interior goes in detail_mesh.
func make_body() -> ArrayMesh:
	_build()
	detail_mesh = _commit_kits(_detail, paint_material(paint))
	return _commit_kits(_main, paint_material(paint))


## Lets go of the kits (every vertex, unindexed, of every surface: some
## 2 MB a look) once the meshes are made and the lamps lit (LampGlow). What
## a car still asks its builder (steering_transform, police_band, outer_x)
## comes from the shape alone.
func release_kits() -> void:
	_k = {}
	_main = {}
	_detail = {}
	lamps = []


## A car parked along a curb: the body with its wheels and a simpler
## interior built in. Its paint comes from each MultiMesh instance's custom
## data (see shaders/car_paint_parked.gdshader), so a whole street of them
## draws in a handful of calls.
func make_parked() -> ArrayMesh:
	parked = true
	_build()
	var style: String = shape.get("wheel_style", "alloy10")
	var r := float(shape["wheel_radius"])
	var w := float(shape["wheel_width"])
	var tyre := _tyre_kit(r, w, style, true)
	var rim := _rim_kit(r, w, style, true)
	var shield := _brake_kits(r, w, style, Color.BLACK, true)[0] as MeshKit
	for z: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for side: float in [-1.0, 1.0]:
			var xf := Transform3D(Basis.IDENTITY, Vector3(float(shape["track_half"]) * side, r, z))
			_append(_k["rough"], tyre, xf, side < 0.0)
			_append(_k["metal"], rim, xf, side < 0.0)
			_append(_k["rough"], shield, xf, side < 0.0)
	return _commit_parked(_main)


## A parked car in two surfaces instead of six: everything opaque in one,
## its finish (paint, gloss, rough, satin, metal) in UV2.x for
## shaders/car_paint_parked.gdshader, and the glass. Parked cars are drawn
## a MultiMesh per model per 50 m tile, so each surface saved is a draw
## call saved many times over (docs/world_art.md, rule W5).
static func _commit_parked(kits: Dictionary) -> ArrayMesh:
	var body := MeshKit.new()
	body.use_color = true
	body.use_uv2 = true
	var finishes := ["paint", "gloss", "rough", "satin", "metal"]
	for f in finishes.size():
		var kit: MeshKit = kits[finishes[f]]
		var start := body.verts.size()
		body.verts.append_array(kit.verts)
		body.normals.append_array(kit.normals)
		body.uvs.append_array(kit.uvs)
		body.colors.append_array(kit.colors)
		body.uv2s.resize(body.verts.size())
		for i in range(start, body.verts.size()):
			body.uv2s[i] = Vector2(float(f), 0.0)
	return ModelLod.finish_kits([[body, material("parked_paint")], [kits["glass"], material("glass")]])


## Where the steering wheel sits (in the car's space): ahead of and above
## the driver's hips, tilted back on its column toward the driver.
func steering_transform() -> Transform3D:
	var sp: Array = shape["seat"]
	var c := Vector3(float(sp[0]), float(sp[1]) + float(shape.get("wheel_rise", 0.36)), float(sp[2]) - float(shape.get("wheel_reach", 0.42)))
	return Transform3D(Basis(Vector3.RIGHT, -deg_to_rad(float(shape.get("column_degrees", 24.0)))), c)


## One indexed surface per material that has anything in it.
static func _commit_kits(kits: Dictionary, paint_mat: Material) -> ArrayMesh:
	var parts := []
	for name: String in ["paint", "gloss", "rough", "satin", "metal", "glass"]:
		parts.append([kits[name], paint_mat if name == "paint" else material(name)])
	return ModelLod.finish_kits(parts)


func _build() -> void:
	for name: String in ["paint", "gloss", "rough", "satin", "metal", "glass"]:
		for kits: Dictionary in [_main, _detail]:
			var kit := MeshKit.new()
			kit.use_color = true
			kits[name] = kit
	_k = _main
	_lower_body()
	if shape.get("flares", false):
		_flares()
	_cabin()
	if shape.has("bed"):
		_bed()
	_front()
	_rear()
	_mirrors()
	_details()
	# The interior: in its own near-only mesh when driven, built in (and
	# simpler) when parked.
	if not parked:
		_k = _detail
	_interior()
	_k = _main
	if shape.get("hood_scoop", false):
		_hood_scoop()
	if shape.get("spoiler", false):
		_spoiler(str(shape["spoiler"]) == "wing")
	if shape.get("stripes", false):
		_stripes()
	if shape.get("cladding", false):
		_cladding()
	if shape.get("woodgrain", false):
		_woodgrain()
	if shape.has("side_stripe"):
		var ss: Array = shape["side_stripe"]
		_side_band(float(ss[0]), float(ss[1]), _nose_z() + 0.25, _tail_z() - 0.15, Color.html(str(ss[2])))
	if shape.get("t_tops", false):
		_t_tops()
	if shape.get("slider", false):
		_slider_track()
	if shape.get("spare", false):
		_spare_tyre()
	if shape.get("police", false):
		_police()


## Paint at a share of full brightness (1 is the body colour itself).
static func _pc(m := 1.0) -> Color:
	return Color(m, m, m)


# --- lower body: a lofted shell, nose to tail ------------------------------------------

## Half a cross-section, from the middle of the underside round the right
## side to the middle of the top, as (fraction of half width, fraction of
## height). The sides bulge a little below the middle and tuck in toward
## the top, and the top has a slight crown, so the body reads as pressed
## steel rather than a box. Mirrored for the left side.
const HALF_SECTION := [
	[0.0, 0.0], [0.86, 0.0], [0.95, 0.05], [0.99, 0.17], [1.0, 0.36], [0.995, 0.56],
	[0.975, 0.74], [0.935, 0.87], [0.85, 0.955], [0.64, 0.995], [0.32, 1.012], [0.0, 1.018],
]
const LOFT_STEP := 0.08 ## metres between rings along the body
const ARCH_STEP := 0.035 ## closer over the wheel arches so they come out round
const SEAM := 0.008 ## half the width of a panel gap


static func _section(w: float, y0: float, y1: float) -> PackedVector2Array:
	var h := y1 - y0
	var pts := PackedVector2Array()
	for p: Array in HALF_SECTION:
		pts.append(Vector2(w * float(p[0]), y0 + h * float(p[1])))
	for i in range(HALF_SECTION.size() - 2, 0, -1):
		var p: Array = HALF_SECTION[i]
		pts.append(Vector2(-w * float(p[0]), y0 + h * float(p[1])))
	return pts


## The stations' [half width, bottom, top] at z, on a smooth curve through
## them that never overshoots (so a pickup's step behind the cab stays a step).
func _station_at(z: float) -> Vector3:
	var st: Array = shape["stations"]
	var n := st.size()
	if z <= float(st[0][0]):
		return Vector3(st[0][1], st[0][2], st[0][3])
	for i in range(n - 1):
		var z0 := float(st[i][0])
		var z1 := float(st[i + 1][0])
		if z > z1:
			continue
		var t := (z - z0) / maxf(0.0001, z1 - z0)
		var out := Vector3.ZERO
		for k in 3:
			var p0 := float(st[maxi(i - 1, 0)][k + 1])
			var p1 := float(st[i][k + 1])
			var p2 := float(st[i + 1][k + 1])
			var p3 := float(st[mini(i + 2, n - 1)][k + 1])
			var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
			out[k] = clampf(v, minf(p1, p2), maxf(p1, p2))
		return out
	return Vector3(st[n - 1][1], st[n - 1][2], st[n - 1][3])


func _arch_radius() -> float:
	return float(shape["wheel_radius"]) + 0.055


## How high the bottom of the body sits at z: lifted into a round arch over
## each wheel.
func _arch_bottom(z: float, y0: float, y1: float) -> float:
	var wr: float = shape["wheel_radius"]
	var r := _arch_radius()
	for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		var dz := z - az
		if absf(dz) < r:
			y0 = maxf(y0, wr + sqrt(r * r - dz * dz))
	return minf(y0, y1 - 0.13)


## Half width of the body's side at (z, y), following the section's bulge.
func _side_x(z: float, y: float) -> float:
	var sv := _station_at(z)
	var y0 := _arch_bottom(z, sv.y, sv.z)
	var f := clampf((y - y0) / maxf(0.01, sv.z - y0), 0.0, 1.0)
	for i in range(HALF_SECTION.size() - 1):
		var a: Array = HALF_SECTION[i]
		var b: Array = HALF_SECTION[i + 1]
		if f <= float(b[1]):
			var t := (f - float(a[1])) / maxf(0.0001, float(b[1]) - float(a[1]))
			return sv.x * lerpf(float(a[0]), float(b[0]), t)
	return 0.0


## Where the panel gaps fall along the body: [z, true for the sides (doors),
## false for the top (hood and trunk lid)].
func _seams() -> Array:
	var cab: Dictionary = shape["cabin"]
	var st: Array = shape["stations"]
	var r := _arch_radius()
	var fa: float = shape["front_axle"]
	var ra: float = shape["rear_axle"]
	var za: float = cab["za"]
	var zd: float = cab["zd"]
	var doors: int = cab.get("doors", 4)
	var out := []
	var door_front := maxf(fa + r + 0.1, za - 0.02)
	out.append([door_front, true])
	if shape.has("bed"):
		out.append([_b_pillar_z() + 0.05, true])
		out.append([zd - 0.05, true])
	elif doors == 4:
		out.append([_b_pillar_z() + 0.05, true])
		out.append([minf(ra - r - 0.06, zd - 0.05), true])
	else:
		out.append([_b_pillar_z() + 0.05, true])
	out.append([za - 0.05, false])
	out.append([float(st[1][0]) + 0.16, false])
	if not shape.has("bed"):
		out.append([zd + 0.07, false])
	return out


func _b_pillar_z() -> float:
	var cab: Dictionary = shape["cabin"]
	var doors: int = cab.get("doors", 4)
	return lerpf(float(cab["zb"]), float(cab["zc"]), 0.42 if doors == 4 else 0.78)


func _lower_body() -> void:
	var paint_kit: MeshKit = _k["paint"]
	var rough: MeshKit = _k["rough"]
	var st: Array = shape["stations"]
	var z_start := float(st[0][0])
	var z_end := float(st[st.size() - 1][0])
	var seams := _seams()
	var r_arch := _arch_radius()
	# Ring positions along the body: every station, close together over the
	# arches, and a pair either side of every panel gap.
	var zs: Array[float] = []
	var z := z_start
	while z < z_end:
		zs.append(z)
		var near_arch := false
		for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
			if absf(z - az) < r_arch + 0.06:
				near_arch = true
		z += (ARCH_STEP if near_arch else LOFT_STEP) * (1.7 if parked else 1.0)
	zs.append(z_end)
	for stn: Array in st:
		zs.append(float(stn[0]))
	var seam_at := {}
	for sm: Array in seams:
		var zz: float = sm[0]
		zs.append(zz - SEAM)
		zs.append(zz + SEAM)
		seam_at[snappedf(zz - SEAM, 0.0001)] = sm[1]
	zs.sort()
	var clean: Array[float] = []
	for v in zs:
		if clean.is_empty() or v - clean[clean.size() - 1] > 0.004:
			clean.append(v)
	zs = clean

	var rings: Array[PackedVector3Array] = []
	for zz in zs:
		var sv := _station_at(zz)
		var y0 := _arch_bottom(zz, sv.y, sv.z)
		var sec := _section(sv.x, y0, sv.z)
		var ring := PackedVector3Array()
		for p in sec:
			ring.append(Vector3(p.x, p.y, zz))
		rings.append(ring)
	var n := rings[0].size()
	# Smooth normals from the neighbouring points round and along the body.
	var normals: Array[PackedVector3Array] = []
	for i in rings.size():
		var nr := PackedVector3Array()
		var prev := rings[maxi(i - 1, 0)]
		var next := rings[mini(i + 1, rings.size() - 1)]
		var mid_y := (rings[i][0].y + rings[i][n / 2].y) * 0.5
		for j in n:
			var t_round := rings[i][(j + 1) % n] - rings[i][(j - 1 + n) % n]
			var t_along := next[j] - prev[j]
			var nn := t_round.cross(t_along).normalized()
			var outward := rings[i][j] - Vector3(0.0, mid_y, rings[i][j].z)
			if nn.dot(outward) < 0.0:
				nn = -nn
			nr.append(nn if nn.length() > 0.5 else outward.normalized())
		normals.append(nr)
	var half := HALF_SECTION.size()
	var sill_black: bool = shape.get("black_sills", true)
	var cab_z0 := float(shape["cabin"]["za"]) + 0.02
	var cab_z1 := float(shape["cabin"]["zd"]) - (0.02 if shape.has("bed") else 0.0)
	for i in range(rings.size() - 1):
		var seam: Variant = seam_at.get(snappedf(zs[i], 0.0001), null)
		for j in n:
			var j1 := (j + 1) % n
			var a := rings[i][j]
			var b := rings[i][j1]
			var c := rings[i + 1][j1]
			var d := rings[i + 1][j]
			var fa := _section_frac(j, half)
			var fb := _section_frac(j1, half)
			# The cabin is open: no body top across it, so the interior shows.
			if minf(fa, fb) >= 0.95 and zs[i] >= cab_z0 and zs[i + 1] <= cab_z1:
				continue
			var kit := paint_kit
			if fa < 0.01 and fb < 0.01:
				kit = rough
				kit.color = TRIM.darkened(0.5) # underside
			elif minf(fa, fb) < 0.06 and sill_black:
				kit = rough
				kit.color = TRIM # sill
			else:
				kit.color = _pc()
				if seam != null:
					var side_seam: bool = seam
					var on_side := minf(fa, fb) > 0.12 and maxf(fa, fb) < 0.9
					var on_top := minf(fa, fb) > 0.9
					if (side_seam and on_side) or (not side_seam and on_top):
						kit.color = _pc(0.12)
			var mid := (a + b + c + d) * 0.25
			var face := Vector3(mid.x, mid.y - 0.6, 0.0)
			kit.quad_smooth(a, b, c, d, normals[i][j], normals[i][j1], normals[i + 1][j1], normals[i + 1][j], _face_normal(a, b, c, face))
		# A step in the top (a pickup's cab back) needs a wall to close it.
		var top_a := rings[i][half - 1].y
		var top_b := rings[i + 1][half - 1].y
		if absf(top_a - top_b) > 0.05:
			var hi := rings[i] if top_a > top_b else rings[i + 1]
			var lo := rings[i + 1] if top_a > top_b else rings[i]
			var nz := Vector3.BACK if top_a > top_b else Vector3.FORWARD
			paint_kit.color = _pc()
			var y_lo := lo[half - 1].y
			for j in range(half - 4, n - half + 4):
				var p0 := hi[j % n]
				var p1 := hi[(j + 1) % n]
				if p0.y < y_lo and p1.y < y_lo:
					continue
				paint_kit.quad(Vector3(p0.x, minf(p0.y, y_lo), p0.z), Vector3(p1.x, minf(p1.y, y_lo), p1.z), p1, p0, nz)
	_cap(rings[0], Vector3.FORWARD)
	_cap(rings[rings.size() - 1], Vector3.BACK)
	_wheel_wells()
	_door_handles(seams)


## Height fraction (0 underside .. 1 top) of point j of a section ring.
static func _section_frac(j: int, half: int) -> float:
	var k := j if j < half else 2 * (half - 1) - j
	return float(HALF_SECTION[k][1])


func _cap(ring: PackedVector3Array, n: Vector3) -> void:
	var kit: MeshKit = _k["paint"]
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	kit.color = _pc()
	for j in ring.size():
		kit.tri(c, ring[j], ring[(j + 1) % ring.size()], n)


static func _face_normal(a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> Vector3:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.length() < 0.5:
		return outward.normalized()
	return nrm if nrm.dot(outward) >= 0.0 else -nrm


## Top surface height of the lower body at z, near the middle (on the crown).
func _top_at(z: float) -> float:
	var sv := _station_at(z)
	var y0 := _arch_bottom(z, sv.y, sv.z)
	return y0 + (sv.z - y0) * 1.014


## Dark liners inside each wheel arch, so you can't see through the car.
func _wheel_wells() -> void:
	var kit: MeshKit = _k["rough"]
	kit.color = Color(0.025, 0.025, 0.025)
	var wr: float = shape["wheel_radius"]
	var r := _arch_radius()
	var x: float = float(shape["track_half"]) - float(shape["wheel_width"]) * 0.5 - 0.04
	var segs := 8 if parked else 14
	for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for s: float in [-1.0, 1.0]:
			var c := Vector3(x * s, wr, az)
			for i in segs:
				var a0 := PI * float(i) / float(segs)
				var a1 := PI * float(i + 1) / float(segs)
				var p0 := c + Vector3(0, sin(a0) * r, cos(a0) * r)
				var p1 := c + Vector3(0, sin(a1) * r, cos(a1) * r)
				kit.quad(Vector3(c.x, 0.15, p0.z), p0, p1, Vector3(c.x, 0.15, p1.z), Vector3(s, 0, 0))
				var w: float = float(shape["width"]) * 0.5
				kit.quad(p0, p1, Vector3(w * s, p1.y, p1.z), Vector3(w * s, p0.y, p0.z), Vector3(0, -sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5)))


## Black plastic arch flares (a pickup's), standing a little proud of the body.
func _flares() -> void:
	var kit: MeshKit = _k["rough"]
	kit.color = TRIM
	var wr: float = shape["wheel_radius"]
	var r := _arch_radius()
	var t := 0.07
	var segs := 16
	for az: float in [float(shape["front_axle"]), float(shape["rear_axle"])]:
		for s: float in [-1.0, 1.0]:
			for i in segs:
				var a0 := PI * float(i) / float(segs)
				var a1 := PI * float(i + 1) / float(segs)
				var pts := []
				for a: float in [a0, a1]:
					var d := Vector2(cos(a), sin(a))
					var zi := az + d.x * r
					var yi := wr + d.y * r
					var zo := az + d.x * (r + t)
					var yo := wr + d.y * (r + t)
					pts.append([Vector3((_side_x(zi, yi) + 0.022) * s, yi, zi), Vector3((_side_x(zo, yo) + 0.006) * s, yo, zo)])
				if (pts[0][0] as Vector3).y < _station_at(az).y + 0.02 and (pts[1][0] as Vector3).y < _station_at(az).y + 0.02:
					continue
				kit.quad(pts[0][0], pts[1][0], pts[1][1], pts[0][1], Vector3(s, 0.2, 0))
				# The flare's inner lip, facing the tyre.
				var in0: Vector3 = pts[0][0]
				var in1: Vector3 = pts[1][0]
				kit.quad(in0, in1, Vector3(in1.x - 0.03 * s, in1.y, in1.z), Vector3(in0.x - 0.03 * s, in0.y, in0.z),
					Vector3(0, -sin((a0 + a1) * 0.5), -cos((a0 + a1) * 0.5)))


## Door handles: a pull standing proud of a shallow dark recess, just ahead
## of the back edge of each door.
func _door_handles(seams: Array) -> void:
	var cab: Dictionary = shape["cabin"]
	var y := float(cab["belt"]) - 0.085
	var doors: Array[float] = []
	for sm: Array in seams:
		if sm[1]:
			doors.append(float(sm[0]))
	doors.sort()
	var style: String = shape.get("handles", "chrome")
	for k in range(1, doors.size()):
		var z: float = doors[k] - 0.15
		var x := _side_x(z, y)
		for s: float in [-1.0, 1.0]:
			var rough: MeshKit = _k["rough"]
			rough.color = Color(0.03, 0.03, 0.03)
			_panel_side(rough, Vector3((x + 0.002) * s, y, z), 0.15, 0.04, Vector3(s, 0, 0))
			var kit: MeshKit = _k["metal"] if style == "chrome" else (_k["paint"] if style == "body" else _k["rough"])
			kit.color = CHROME if style == "chrome" else (_pc() if style == "body" else TRIM)
			_bbox(kit, Vector3((x + 0.012) * s, y + 0.004, z), Vector3(0.008, 0.012, 0.068), 0.006)


# --- cabin ---------------------------------------------------------------------------------

func _cabin() -> void:
	var paint_kit: MeshKit = _k["paint"]
	var win: MeshKit = _k["glass"]
	var gloss: MeshKit = _k["gloss"]
	var rough: MeshKit = _k["rough"]
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var roof: float = cab["roof"]
	var wb: float = cab["wb"]
	var wr: float = cab["wr"]
	var za: float = cab["za"]
	var zb: float = cab["zb"]
	var zc: float = cab["zc"]
	var zd: float = cab["zd"]
	var c_pillar: float = cab.get("c_pillar", 0.22)
	var headliner := _seat_col.lerp(Color(0.62, 0.6, 0.56), 0.6)
	var A := func(s: float) -> Vector3: return Vector3(wb * s, belt, za)
	var Bp := func(s: float) -> Vector3: return Vector3(wr * s, roof, zb)
	var C := func(s: float) -> Vector3: return Vector3(wr * s, roof, zc)
	var D := func(s: float) -> Vector3: return Vector3(wb * s, belt, zd)
	# Windshield and back glass.
	win.color = GLASS
	win.quad(A.call(-1.0), A.call(1.0), Bp.call(1.0), Bp.call(-1.0), Vector3(0, zb - za, -(roof - belt)).normalized())
	win.color = GLASS.darkened(0.15)
	win.quad(C.call(-1.0), C.call(1.0), D.call(1.0), D.call(-1.0), Vector3(0, maxf(0.05, zd - zc), roof - belt).normalized())
	# A black frit band round the windshield and back glass, as on real glass.
	gloss.color = GLOSS_BLACK
	var wn := Vector3(0, zb - za, -(roof - belt)).normalized()
	_glass_band(gloss, A.call(-1.0), A.call(1.0), Bp.call(1.0), Bp.call(-1.0), wn, 0.035)
	var bn := Vector3(0, maxf(0.05, zd - zc), roof - belt).normalized()
	_glass_band(gloss, D.call(1.0), D.call(-1.0), C.call(-1.0), C.call(1.0), bn, 0.035)
	# Roof: a gentle crown across, smooth shaded, and the headliner under it.
	paint_kit.color = _pc()
	var xs := [-1.0, -0.55, 0.0, 0.55, 1.0]
	for k in range(xs.size() - 1):
		var x0: float = xs[k]
		var x1: float = xs[k + 1]
		var y0 := roof + 0.035 * (1.0 - x0 * x0)
		var y1 := roof + 0.035 * (1.0 - x1 * x1)
		var n0 := Vector3(x0 * 0.35, 1.0, 0.0).normalized()
		var n1 := Vector3(x1 * 0.35, 1.0, 0.0).normalized()
		paint_kit.quad_smooth(Vector3(wr * x0, y0, zb), Vector3(wr * x1, y1, zb), Vector3(wr * x1, y1, zc), Vector3(wr * x0, y0, zc), n0, n1, n1, n0, Vector3.UP)
	rough.color = headliner
	rough.quad(Vector3(-wr, roof - 0.01, zb), Vector3(wr, roof - 0.01, zb), Vector3(wr, roof - 0.01, zc), Vector3(-wr, roof - 0.01, zc), Vector3.DOWN)
	# Sides: glass, then pillars laid over it (outside in paint, inside trimmed).
	var trim_kit: MeshKit = _k["metal"] if shape.get("chrome_trim", false) else gloss
	var trim_col := CHROME if shape.get("chrome_trim", false) else GLOSS_BLACK
	for s: float in [-1.0, 1.0]:
		var out := Vector3(s, 0.32, 0.0).normalized()
		var a: Vector3 = A.call(s)
		var b: Vector3 = Bp.call(s)
		var c: Vector3 = C.call(s)
		var d: Vector3 = D.call(s)
		var b_low := Vector3(wb * s, belt, zb)
		var c_low := Vector3(wb * s, belt, zc)
		win.color = GLASS
		win.tri(a, b, b_low, out)
		if shape.get("privacy_glass", false):
			# Dark tinted glass behind the front doors, as on most crossovers.
			var bz := _b_pillar_z()
			var pb := Vector3(wr * s, roof, bz)
			var pb_low := Vector3(wb * s, belt, bz)
			win.quad(b_low, b, pb, pb_low, out)
			win.color = Color(0.03, 0.035, 0.04, 0.82)
			win.quad(pb_low, pb, c, c_low, out)
			if zd - zc > 0.05:
				win.tri(c_low, c, d, out)
			win.color = GLASS
		else:
			win.quad(b_low, b, c, c_low, out)
			if zd - zc > 0.05:
				win.tri(c_low, c, d, out)
		var lift := Vector3(s * 0.006, 0.0, 0.0)
		var inset := Vector3(-s * 0.012, 0.0, 0.0)
		var quads := []
		# A-pillar along the windshield edge.
		quads.append([paint_kit, _pc(), [a, b, b + Vector3(0, 0, 0.08), a + Vector3(0, 0, 0.11)]])
		# B-pillar between the doors (gloss black), or the quarter-window line on a coupe.
		var zb_p := _b_pillar_z()
		var top_b := Vector3(wr * s, roof, zb_p)
		var low_b := Vector3(wb * s, belt, zb_p)
		quads.append([gloss, GLOSS_BLACK, [low_b + Vector3(0, 0, -0.05), top_b + Vector3(0, 0, -0.05), top_b + Vector3(0, 0, 0.05), low_b + Vector3(0, 0, 0.05)]])
		# C-pillar.
		if zd - zc > 0.05:
			quads.append([paint_kit, _pc(), [c + Vector3(0, 0, -c_pillar), c, d, d + Vector3(0, 0, -c_pillar * 1.3)]])
		else:
			quads.append([paint_kit, _pc(), [c_low + Vector3(0, 0, -c_pillar), c + Vector3(0, 0, -c_pillar), c, c_low]])
		# Roof rail.
		quads.append([paint_kit, _pc(), [b + Vector3(0, -0.045, 0), c + Vector3(0, -0.045, 0), c, b]])
		for q: Array in quads:
			var kit: MeshKit = q[0]
			var p: Array = q[2]
			kit.color = q[1]
			kit.quad(p[0] + lift, p[1] + lift, p[2] + lift, p[3] + lift, out)
			# The same pillar seen from inside, trimmed to match the headliner.
			rough.color = headliner
			rough.quad(p[0] + inset, p[1] + inset, p[2] + inset, p[3] + inset, -out)
		# A thin window surround under the roof rail, and the belt moulding.
		trim_kit.color = trim_col
		trim_kit.quad(b + lift * 1.3 + Vector3(0, -0.06, 0), c + lift * 1.3 + Vector3(0, -0.06, 0), c + lift * 1.3 + Vector3(0, -0.045, 0), b + lift * 1.3 + Vector3(0, -0.045, 0), out)
		trim_kit.quad(a + lift * 1.3, d + lift * 1.3, d + lift * 1.3 + Vector3(0, 0.022, 0), a + lift * 1.3 + Vector3(0, 0.022, 0), out)
	# A cab whose back is upright (a pickup) needs a back wall below the glass.
	if zd - zc <= 0.05 and belt > _top_at(zd + 0.06) + 0.05:
		var y0 := _top_at(zd + 0.06)
		paint_kit.color = _pc()
		paint_kit.quad(Vector3(-wb, y0, zd), Vector3(wb, y0, zd), Vector3(wb, belt, zd), Vector3(-wb, belt, zd), Vector3.BACK)


## A band round the inside edge of a pane a-b-c-d (bottom left, bottom
## right, top right, top left), standing just off the glass.
func _glass_band(kit: MeshKit, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, w: float) -> void:
	var off := n * 0.003
	var mid := (a + b + c + d) * 0.25
	var pts := [a, b, c, d]
	for i in 4:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 4]
		var i0 := p0 + (mid - p0).normalized() * w
		var i1 := p1 + (mid - p1).normalized() * w
		kit.quad(p0 + off, p1 + off, i1 + off, i0 + off, n)


# --- a pickup's box --------------------------------------------------------------------------

func _bed() -> void:
	var paint_kit: MeshKit = _k["paint"]
	var rough: MeshKit = _k["rough"]
	var bed: Dictionary = shape["bed"]
	var z0: float = bed["z0"]
	var z1: float = bed["z1"]
	var fl: float = bed["floor"]
	var top: float = bed["top"]
	var t: float = bed["thick"]
	var w: float = float(shape["width"]) * 0.5 - 0.01
	for s: float in [-1.0, 1.0]:
		var xo := w * s
		var xi := (w - t) * s
		paint_kit.color = _pc()
		paint_kit.quad(Vector3(xo, fl - 0.05, z0), Vector3(xo, fl - 0.05, z1), Vector3(xo, top, z1), Vector3(xo, top, z0), Vector3(s, 0, 0))
		rough.color = TRIM.lightened(0.08)
		rough.quad(Vector3(xi, fl, z0), Vector3(xi, fl, z1), Vector3(xi, top, z1), Vector3(xi, top, z0), Vector3(-s, 0, 0))
		# Bed rail caps (black plastic), with stake pockets.
		_bbox(rough, Vector3((w - t * 0.5) * s, top + 0.012, (z0 + z1) * 0.5), Vector3(t * 0.5 + 0.008, 0.014, (z1 - z0) * 0.5), 0.008)
		rough.color = Color(0.02, 0.02, 0.02)
		for zz: float in [z0 + 0.15, z1 - 0.2]:
			rough.quad(Vector3((w - t * 0.7) * s, top + 0.027, zz - 0.04), Vector3((w - t * 0.3) * s, top + 0.027, zz - 0.04),
				Vector3((w - t * 0.3) * s, top + 0.027, zz + 0.04), Vector3((w - t * 0.7) * s, top + 0.027, zz + 0.04), Vector3.UP)
	# Front wall of the box, inside.
	rough.color = TRIM.lightened(0.08)
	rough.quad(Vector3(-w + t, fl, z0 + 0.005), Vector3(w - t, fl, z0 + 0.005), Vector3(w - t, top, z0 + 0.005), Vector3(-w + t, top, z0 + 0.005), Vector3.BACK)
	# Tailgate: back, inside and top, with a handle and a badge.
	paint_kit.color = _pc()
	paint_kit.quad(Vector3(-w, fl - 0.05, z1 + t), Vector3(w, fl - 0.05, z1 + t), Vector3(w, top, z1 + t), Vector3(-w, top, z1 + t), Vector3.BACK)
	paint_kit.color = _pc(0.12)
	for yy: float in [top - 0.006, fl - 0.044]:
		paint_kit.quad(Vector3(-w, yy - 0.004, z1 + t + 0.001), Vector3(w, yy - 0.004, z1 + t + 0.001), Vector3(w, yy + 0.004, z1 + t + 0.001), Vector3(-w, yy + 0.004, z1 + t + 0.001), Vector3.BACK)
	rough.color = TRIM.lightened(0.08)
	rough.quad(Vector3(-w + t, fl, z1), Vector3(w - t, fl, z1), Vector3(w - t, top, z1), Vector3(-w + t, top, z1), Vector3.FORWARD)
	paint_kit.color = _pc()
	paint_kit.quad(Vector3(-w, top, z1), Vector3(w, top, z1), Vector3(w, top, z1 + t), Vector3(-w, top, z1 + t), Vector3.UP)
	var metal: MeshKit = _k["metal"]
	metal.color = CHROME
	_bbox(metal, Vector3(0, top - 0.06, z1 + t + 0.008), Vector3(0.11, 0.025, 0.008), 0.006)
	_badge(Vector3(0, (top + fl) * 0.5 - 0.02, z1 + t + 0.004), Vector3.BACK, 0.3, 0.07)
	# Bed liner floor with raised ribs.
	rough.color = Color(0.07, 0.07, 0.075)
	rough.quad(Vector3(-w + t, fl + 0.004, z0), Vector3(w - t, fl + 0.004, z0), Vector3(w - t, fl + 0.004, z1), Vector3(-w + t, fl + 0.004, z1), Vector3.UP)
	if not parked:
		rough.color = Color(0.09, 0.09, 0.095)
		var ribs := 7
		for i in ribs:
			var x := lerpf(-w + t + 0.12, w - t - 0.12, float(i) / float(ribs - 1))
			_bbox(rough, Vector3(x, fl + 0.012, (z0 + z1) * 0.5), Vector3(0.03, 0.01, (z1 - z0) * 0.5 - 0.03), 0.008)


# --- nose and tail ---------------------------------------------------------------------------

func _nose_z() -> float:
	var st: Array = shape["stations"]
	return float(st[0][0]) - 0.005


func _tail_z() -> float:
	var st: Array = shape["stations"]
	var rz: float = float(st[st.size() - 1][0]) + 0.005
	if shape.has("bed"):
		rz = maxf(rz, float(shape["bed"]["z1"]) + float(shape["bed"]["thick"]) + 0.004)
	return rz


func _bumper_kit() -> Array:
	match str(shape.get("bumper", "black")):
		"chrome":
			return [_k["metal"], CHROME]
		"body":
			return [_k["paint"], _pc()]
	return [_k["rough"], TRIM]


func _front() -> void:
	var st: Array = shape["stations"]
	var fz := _nose_z()
	var hw_nose: float = float(st[1][1])
	var ly: float = shape.get("lights_y", 0.57)
	var by := float(st[0][2]) + 0.1
	var f := Vector3.FORWARD
	var gloss: MeshKit = _k["gloss"]
	var metal: MeshKit = _k["metal"]
	var rough: MeshKit = _k["rough"]
	var truck := shape.has("bed")
	# Bumper, wrapping round the corners.
	var bk: Array = _bumper_kit()
	var bkit: MeshKit = bk[0]
	bkit.color = bk[1]
	_bbox(bkit, Vector3(0, by, fz + 0.06), Vector3(hw_nose * 0.985, 0.095, 0.12), 0.05)
	if truck:
		rough.color = TRIM
		_bbox(rough, Vector3(0, by - 0.11, fz + 0.1), Vector3(hw_nose * 0.9, 0.04, 0.1), 0.02)
	else:
		# Lower air intake, a black mesh.
		gloss.color = GLOSS_BLACK
		_panel(gloss, Vector3(0, by - 0.035, fz - 0.062), hw_nose * 1.0, 0.07, f)
		rough.color = TRIM
		for i in 3:
			_panel(rough, Vector3(0, by - 0.06 + 0.022 * i, fz - 0.064), hw_nose * 0.96, 0.006, f)
	# Plate on the bumper, in a black frame.
	_plate(Vector3(0, by + 0.01, fz - 0.062), f, 0.3, 0.15)
	# Grille between the lamps.
	var grille := str(shape.get("grille", ""))
	var crosshair := grille == "crosshair"
	# "big": a truck's chrome grille on a car (a full-size SUV); "slot": just a
	# thin opening between the lamps; "none": a smooth nose.
	var big := truck or grille == "big"
	var gw := hw_nose * (1.0 if big else (1.02 if crosshair else 0.7))
	var gh := 0.24 if big else (0.21 if crosshair else (0.035 if grille == "slot" else 0.12))
	var gy := ly - (0.0 if big else (0.045 if crosshair else 0.01))
	if grille == "none":
		gw = 0.0
		gh = 0.0
	if gw > 0.0:
		gloss.color = GLOSS_BLACK
		_panel(gloss, Vector3(0, gy, fz - 0.006), gw, gh, f)
	var bars := 0 if gw == 0.0 or grille == "slot" else (4 if big else (5 if crosshair else 3))
	var bar_kit: MeshKit = metal if big or shape.get("chrome_trim", false) else rough
	bar_kit.color = CHROME if bar_kit == metal else Color(0.1, 0.1, 0.11)
	for i in bars:
		var yy := gy - gh * 0.5 + gh * (float(i) + 0.5) / float(bars)
		_bbox(bar_kit, Vector3(0, yy, fz - 0.01), Vector3(gw * 0.5 - 0.02, 0.008 if big else 0.005, 0.006), 0.003)
	if big:
		# A heavy chrome surround and a centre bar.
		metal.color = CHROME
		_frame(metal, Vector3(0, gy, fz - 0.014), gw + 0.04, gh + 0.04, 0.025, f)
		_bbox(metal, Vector3(0, gy, fz - 0.018), Vector3(0.015, gh * 0.5, 0.008), 0.004)
	elif crosshair:
		# A wide grille split in four by a cross (the brand's face), in a
		# surround: satin dark grey, or chrome on a car trimmed in it.
		var ck: MeshKit = metal if shape.get("chrome_trim", false) else rough
		ck.color = CHROME if ck == metal else Color(0.22, 0.23, 0.25)
		_frame(ck, Vector3(0, gy, fz - 0.014), gw + 0.03, gh + 0.03, 0.022, f)
		_bbox(ck, Vector3(0, gy, fz - 0.018), Vector3(gw * 0.5, 0.014, 0.008), 0.004)
		_bbox(ck, Vector3(0, gy, fz - 0.018), Vector3(0.014, gh * 0.5, 0.008), 0.004)
	elif shape.get("chrome_trim", false) and gw > 0.0:
		metal.color = CHROME
		_bbox(metal, Vector3(0, gy + gh * 0.5 + 0.01, fz - 0.01), Vector3(gw * 0.5, 0.008, 0.006), 0.004)
	if not crosshair:
		_badge(Vector3(0, gy + (0.06 if grille == "slot" else 0.0), fz - 0.024), f, 0.1 if not big else 0.16, 0.05 if not big else 0.07)
	# Lamps: a dark housing, chrome reflectors with bulbs, and a clear lens.
	var lamp_w := hw_nose * (0.4 if truck else 0.42)
	var lamp_h := 0.17 if truck else 0.12
	var style: String = shape.get("lamps", "projector")
	match style:
		"round":
			lamp_h = 0.19
			lamp_w = 0.2
		"slim":
			lamp_h = 0.065
			lamp_w = hw_nose * 0.46
		"pixel":
			lamp_h = 0.085
			lamp_w = hw_nose * 0.4
		"popup":
			lamp_h = 0.11
			lamp_w = hw_nose * 0.4
	for s: float in [-1.0, 1.0]:
		var lx := (hw_nose * 0.95 - lamp_w * 0.5 - (0.06 if truck else 0.03)) * s
		if style == "round":
			lx = (hw_nose * 0.95 - lamp_w * 0.5 - 0.09) * s
		var lc := Vector3(lx, ly, fz)
		if style == "popup":
			_popup_lamp(lx, lamp_w, fz)
		else:
			_lamp(style, lc, lx, s, lamp_w, lamp_h)
		# Indicator at the outer end, and an amber side marker round the corner.
		gloss.color = AMBER
		var ix := (hw_nose * 0.95 - 0.035) * s
		_panel(gloss, Vector3(ix, ly - lamp_h * 0.5 - (0.04 if truck else 0.0) + (0.0 if truck else lamp_h * 0.5), fz + (0.0 if truck else 0.01) - 0.026), 0.06, 0.04 if truck else lamp_h * 0.9, f)
		var mz := fz + 0.22
		_panel_side(gloss, Vector3((_side_x(mz, ly) + 0.003) * s, ly, mz), 0.09, 0.03, Vector3(s, 0, 0))
	# Fog lamps in the bumper.
	if not truck and not parked:
		for s: float in [-1.0, 1.0]:
			var fc := Vector3(hw_nose * 0.72 * s, by - 0.03, fz - 0.063)
			gloss.color = GLOSS_BLACK
			_disc(gloss, fc, 0.04, f, 12)
			gloss.color = Color(0.85, 0.87, 0.9)
			_disc(gloss, fc + Vector3(0, 0, -0.002), 0.028, f, 12)


## One headlamp: a dark housing, chrome reflectors with bulbs (round, quad,
## projector, slim, square; or a grid of small lights, "pixel") and a clear lens.
func _lamp(style: String, lc: Vector3, lx: float, s: float, lamp_w: float, lamp_h: float) -> void:
	var gloss: MeshKit = _k["gloss"]
	var metal: MeshKit = _k["metal"]
	var f := Vector3.FORWARD
	var ly := lc.y
	var fz := lc.z
	gloss.color = GLOSS_BLACK
	_bbox(gloss, lc + Vector3(0, 0, 0.01), Vector3(lamp_w * 0.5, lamp_h * 0.5, 0.03), 0.012)
	metal.color = Color(0.78, 0.79, 0.8)
	_panel(metal, lc + Vector3(0, 0, -0.021), lamp_w * 0.94, lamp_h * 0.86, f)
	if style == "pixel":
		# A grid of small square lights in a black strip.
		gloss.color = Color(0.92, 0.94, 0.97)
		for row in 2:
			for col in 6:
				var px := lx + (float(col) - 2.5) * lamp_w / 6.4
				_panel(gloss, Vector3(px, ly + (float(row) - 0.5) * lamp_h * 0.42, fz - 0.024), lamp_w / 9.0, lamp_h * 0.3, f)
		var pg: MeshKit = _k["glass"]
		pg.color = LENS
		_panel(pg, lc + Vector3(0, 0, -0.03), lamp_w, lamp_h, f)
		return
	var bulbs := 2 if style == "quad" else 1
	for bi in bulbs:
		var bx := lx + (lamp_w * (float(bi) + 0.5) / float(bulbs) - lamp_w * 0.5) * (1.0 if bulbs > 1 else 0.0)
		if style == "projector":
			bx = lx - lamp_w * 0.12 * s
		var bc := Vector3(bx, ly, fz - 0.023)
		metal.color = CHROME
		_disc(metal, bc, lamp_h * (0.46 if style == "round" else 0.38), f, 20 if style == "round" else 16)
		if style == "round":
			# A chrome ring round the round lamp.
			_ring(metal, bc + Vector3(0, 0, -0.003), lamp_h * 0.46, lamp_h * 0.5, f, 20)
		gloss.color = Color(0.9, 0.92, 0.95)
		_disc(gloss, bc + Vector3(0, 0, -0.004), lamp_h * (0.16 if style == "projector" else 0.1), f, 12)
	if style == "projector" or style == "slim":
		# A daytime-running light strip along the top of the lamp.
		gloss.color = Color(0.95, 0.97, 1.0)
		_panel(gloss, Vector3(lx + lamp_w * 0.15 * s, ly + lamp_h * 0.3, fz - 0.025), lamp_w * 0.6, 0.016, f)
	if style == "square":
		metal.color = CHROME
		_frame(metal, Vector3(lx, ly, fz - 0.026), lamp_w + 0.02, lamp_h + 0.02, 0.012, f)
	var glass: MeshKit = _k["glass"]
	glass.color = LENS
	_panel(glass, lc + Vector3(0, 0, -0.03), lamp_w, lamp_h, f)


## A pop-up headlamp, closed: a body-colour lid in the hood with its seam
## round it, and a slot across the nose under the lid's front edge.
func _popup_lamp(lx: float, lamp_w: float, fz: float) -> void:
	var gloss: MeshKit = _k["gloss"]
	var z0 := fz + 0.06
	var z1 := fz + 0.34
	var x0 := lx - lamp_w * 0.5
	var x1 := lx + lamp_w * 0.5
	gloss.color = Color(0.02, 0.02, 0.022)
	var w := 0.007
	for zz: float in [z0, z1]:
		var y := _top_at(zz) + 0.004
		gloss.quad(Vector3(x0, y, zz - w), Vector3(x1, y, zz - w), Vector3(x1, y, zz + w), Vector3(x0, y, zz + w), Vector3.UP)
	for xx: float in [x0, x1]:
		var ya := _top_at(z0) + 0.004
		var yb := _top_at(z1) + 0.004
		gloss.quad(Vector3(xx - w, ya, z0), Vector3(xx + w, ya, z0), Vector3(xx + w, yb, z1), Vector3(xx - w, yb, z1), Vector3.UP)
	var ny := _top_at(fz + 0.02) - 0.03
	gloss.quad(Vector3(x0, ny - 0.008, fz - 0.002), Vector3(x1, ny - 0.008, fz - 0.002), Vector3(x1, ny + 0.008, fz - 0.002), Vector3(x0, ny + 0.008, fz - 0.002), Vector3.FORWARD)


func _rear() -> void:
	var st: Array = shape["stations"]
	var rz := _tail_z()
	var hw_tail: float = float(st[st.size() - 2][1])
	var ty: float = shape.get("tail_y", 0.68)
	var by := float(st[st.size() - 1][2]) + 0.1
	var r := Vector3.BACK
	var gloss: MeshKit = _k["gloss"]
	var metal: MeshKit = _k["metal"]
	var rough: MeshKit = _k["rough"]
	var truck := shape.has("bed")
	if truck:
		hw_tail = float(shape["width"]) * 0.5 - 0.01
	# Bumper: a step bumper on the truck.
	var bk: Array = _bumper_kit()
	var bkit: MeshKit = bk[0]
	bkit.color = bk[1]
	_bbox(bkit, Vector3(0, by + 0.01, rz - 0.04), Vector3(hw_tail * 0.98, 0.095, 0.12), 0.05)
	if truck:
		rough.color = TRIM
		_bbox(rough, Vector3(0, by + 0.107, rz + 0.02), Vector3(0.3, 0.004, 0.05), 0.003)
	else:
		rough.color = TRIM
		_bbox(rough, Vector3(0, by - 0.07, rz - 0.02), Vector3(hw_tail * 0.8, 0.035, 0.09), 0.02)
	# Tail lamps.
	_log_lamps = true
	var style: String = shape.get("tails", "bar")
	if style == "racetrack":
		# One lamp right across the back: a dark lens with a ring of red
		# light running round its edge, like a racetrack.
		var tw := hw_tail * 1.9
		var th := 0.12
		var tc := Vector3(0, ty, rz + 0.006)
		gloss.color = Color(0.1, 0.02, 0.02)
		_panel(gloss, tc, tw, th, r)
		gloss.color = RED_LAMP.lightened(0.15)
		for yy: float in [th * 0.5 - 0.018, -th * 0.5 + 0.018]:
			_panel(gloss, tc + Vector3(0, yy, 0.002), tw - 0.06, 0.016, r)
		for s2: float in [-1.0, 1.0]:
			_panel(gloss, tc + Vector3(s2 * (tw * 0.5 - 0.03), 0, 0.002), 0.016, th - 0.02, r)
			gloss.color = Color(0.92, 0.92, 0.9)
			_panel(gloss, tc + Vector3(s2 * (tw * 0.5 - 0.14), 0, 0.003), 0.1, 0.03, r)
			gloss.color = RED_LAMP.lightened(0.15)
			var sz := rz - 0.1
			_panel_side(gloss, Vector3((_side_x(sz, ty) + 0.004) * s2, ty, sz), 0.14, th * 0.8, Vector3(s2, 0, 0))
	for s: float in [-1.0, 1.0]:
		match style:
			"racetrack":
				pass
			"pixel":
				# A cluster of small square red lights in a black panel.
				var tw := hw_tail * 0.5
				var tc := Vector3((hw_tail * 0.96 - tw * 0.5) * s, ty, rz + 0.006)
				gloss.color = GLOSS_BLACK
				_panel(gloss, tc, tw, 0.1, r)
				gloss.color = RED_LAMP.lightened(0.1)
				for row in 2:
					for col in 7:
						_panel(gloss, tc + Vector3((float(col) - 3.0) * tw / 7.4, (float(row) - 0.5) * 0.045, 0.002), tw / 10.0, 0.03, r)
				# The reversing lamp: a slim white bar along the cluster's foot.
				gloss.color = Color(0.92, 0.92, 0.9)
				_panel(gloss, tc + Vector3(0, -0.072, 0.0), tw * 0.6, 0.016, r)
			"tall":
				var tc := Vector3((hw_tail - 0.06) * s, ty, rz + 0.004)
				gloss.color = GLOSS_BLACK
				_panel(gloss, tc, 0.1, 0.34, r)
				gloss.color = RED_LAMP
				_panel(gloss, tc + Vector3(0, 0.05, 0.002), 0.08, 0.2, r)
				gloss.color = Color(0.92, 0.92, 0.9)
				_panel(gloss, tc + Vector3(0, -0.1, 0.002), 0.08, 0.07, r)
				gloss.color = AMBER
				_panel(gloss, tc + Vector3(0, 0.16, 0.002), 0.08, 0.03, r)
			"wrap":
				var tw := hw_tail * 0.46
				var tc := Vector3((hw_tail * 0.97 - tw * 0.5) * s, ty, rz + 0.006)
				gloss.color = RED_LAMP.darkened(0.3)
				_panel(gloss, tc, tw, 0.13, r)
				gloss.color = RED_LAMP
				_panel(gloss, tc + Vector3(0.02 * s, 0.025, 0.002), tw * 0.8, 0.05, r)
				gloss.color = Color(0.92, 0.92, 0.9)
				_panel(gloss, tc + Vector3(-tw * 0.32 * s, -0.035, 0.002), tw * 0.28, 0.035, r)
				# Round the corner onto the side.
				var sz := rz - 0.1
				gloss.color = RED_LAMP
				_panel_side(gloss, Vector3((_side_x(sz, ty) + 0.004) * s, ty, sz), 0.16, 0.11, Vector3(s, 0, 0))
			_:
				# A wide tail panel in three lit sections with dark ribs.
				var tw := hw_tail * 0.78
				var tc := Vector3((hw_tail * 0.98 - tw * 0.5) * s, ty, rz + 0.006)
				gloss.color = GLOSS_BLACK
				_panel(gloss, tc, tw, 0.14, r)
				var cols := [RED_LAMP, RED_LAMP, Color(0.92, 0.92, 0.9)]
				for i in 3:
					gloss.color = cols[i]
					var sx := (tw * 0.5 - tw * (float(i) + 0.5) / 3.0) * s
					_panel(gloss, tc + Vector3(sx, 0, 0.002), tw / 3.0 - 0.02, 0.11, r)
				rough.color = Color(0.03, 0.03, 0.03)
				for k in 4:
					_panel(rough, tc + Vector3(0, -0.04 + 0.027 * k, 0.004), tw, 0.006, r)
		# Red side reflector at the back corner.
		var mz := rz - 0.2
		if not truck:
			gloss.color = RED_LAMP
			_panel_side(gloss, Vector3((_side_x(mz, by + 0.05) + 0.003) * s, by + 0.05, mz), 0.08, 0.025, Vector3(s, 0, 0))
	_log_lamps = false
	# Third brake light.
	var cab: Dictionary = shape["cabin"]
	gloss.color = RED_LAMP
	if truck:
		_bbox(gloss, Vector3(0, float(cab["roof"]) + 0.01, float(cab["zc"]) + 0.005), Vector3(0.14, 0.02, 0.015), 0.006)
		LampGlow.note(lamps, LampGlow.BRAKE, LampGlow.rect(Vector3(0, float(cab["roof"]) + 0.01, float(cab["zc"]) + 0.02), 0.26, 0.03, r), r)
	else:
		var zc := float(cab["zc"])
		_bbox(gloss, Vector3(0, float(cab["roof"]) - 0.02, zc + 0.02), Vector3(0.16, 0.012, 0.012), 0.004)
		LampGlow.note(lamps, LampGlow.BRAKE, LampGlow.rect(Vector3(0, float(cab["roof"]) - 0.02, zc + 0.032), 0.3, 0.02, r), r)
	# Plate, in a recess with a light over it.
	var py := ty - 0.08 if not truck else by + 0.0
	if style == "racetrack":
		py = ty - 0.19
	var pz := rz + 0.008 if not truck else rz + 0.085
	_plate(Vector3(0, py, pz), r, 0.32, 0.16)
	# Badges on the trunk lid.
	if not truck:
		_badge(Vector3(-hw_tail * 0.55, ty + 0.11, rz + 0.004), r, 0.16, 0.03)
		_badge(Vector3(hw_tail * 0.55, ty + 0.11, rz + 0.004), r, 0.12, 0.03)
		_badge(Vector3(0, ty + 0.06, rz + 0.006), r, 0.05, 0.03)
	# Exhaust tips.
	var tips: Array = []
	match str(shape.get("exhaust", "single")):
		"dual":
			tips = [-hw_tail * 0.6, hw_tail * 0.6]
		"side":
			tips = [hw_tail * 0.55]
		"none":
			tips = []
		_:
			tips = [hw_tail * 0.5]
	for x: float in tips:
		var y := by - 0.09
		metal.color = CHROME
		_tube(metal, Vector3(x, y, rz - 0.3), Vector3(x, y, rz + 0.04), 0.038, 12, false)
		rough.color = Color(0.02, 0.02, 0.02)
		_disc(rough, Vector3(x, y, rz + 0.039), 0.032, r, 12)
		# The pipe running back from under the car.
		rough.color = Color(0.16, 0.15, 0.14)
		_tube(rough, Vector3(x * 0.6, y + 0.02, 0.2), Vector3(x, y, rz - 0.28), 0.03, 6, false)


## A licence plate (PEI white with green characters) in a black frame.
func _plate(c: Vector3, n: Vector3, w: float, h: float) -> void:
	var rough: MeshKit = _k["rough"]
	var gloss: MeshKit = _k["gloss"]
	rough.color = TRIM
	_panel(rough, c, w + 0.03, h + 0.03, n)
	gloss.color = PLATE
	_panel(gloss, c + n * 0.003, w, h, n)
	if parked:
		return
	gloss.color = PLATE_TEXT
	# The province's name in a thin line along the top, then the registration.
	_panel(gloss, c + n * 0.005 + Vector3(0, h * 0.37, 0), w * 0.55, h * 0.045, n)
	var text: String = shape.get("plate", "TCA 001")
	var px := w / (float(text.length()) * 4.0 + 1.0) # one font pixel
	var py := h * 0.55 / 5.0
	# Seen from the back, +x is to the right; from the front it's to the left.
	var right := Vector3.RIGHT if n.z > 0.0 else Vector3.LEFT
	var origin := c + n * 0.005 - right * (w * 0.5 - px) + Vector3(0, h * 0.24, 0)
	for i in text.length():
		var glyph: Array = PLATE_FONT.get(text[i], [])
		for row in glyph.size():
			var bits: String = glyph[row]
			for col in bits.length():
				if bits[col] == "#":
					var pc := origin + right * ((float(i) * 4.0 + float(col) + 0.5) * px) - Vector3(0, (float(row) + 0.5) * py, 0)
					_panel(gloss, pc, px * 1.02, py * 1.02, n)


## A small chrome badge, an oval-ish lozenge facing n.
func _badge(c: Vector3, n: Vector3, w: float, h: float) -> void:
	var metal: MeshKit = _k["metal"]
	metal.color = CHROME
	_bbox(metal, c + n * 0.004, Vector3(w * 0.5, h * 0.5, 0.006), minf(h * 0.45, 0.02))


# --- mirrors and small details -------------------------------------------------------------

func _mirrors() -> void:
	var cab: Dictionary = shape["cabin"]
	var truck := shape.has("bed")
	var y := float(cab["belt"]) + 0.07
	var z := float(cab["za"]) + 0.16
	var x := float(cab["wb"]) + 0.12
	var half := Vector3(0.1, 0.075, 0.045) if not truck else Vector3(0.11, 0.12, 0.05)
	for s: float in [-1.0, 1.0]:
		var rough: MeshKit = _k["rough"]
		rough.color = TRIM
		# The arm from the door, then the housing angled back a touch.
		_bbox(rough, Vector3((x - 0.09) * s, y - 0.035, z), Vector3(0.055, 0.02, 0.035), 0.01)
		var basis := Basis(Vector3.UP, -0.12 * s)
		var kit: MeshKit = rough if truck else _k["paint"]
		kit.color = TRIM if truck else _pc()
		_bbox(kit, Vector3(x * s, y, z), half, 0.03, basis)
		# The mirror glass, facing back.
		var metal: MeshKit = _k["metal"]
		metal.color = Color(0.72, 0.76, 0.8)
		var gc := Vector3(x * s, y, z) + basis * Vector3(0, 0, half.z + 0.001)
		var gx := basis * Vector3(half.x - 0.015, 0, 0)
		var gy := Vector3(0, half.y - 0.015, 0)
		metal.quad(gc - gx - gy, gc + gx - gy, gc + gx + gy, gc - gx + gy, basis * Vector3.BACK)
		if not truck:
			# An indicator repeater on the mirror's leading edge.
			_k["gloss"].color = AMBER
			_bbox(_k["gloss"], Vector3((x + half.x * 0.3) * s, y - half.y + 0.01, z - half.z + 0.004), Vector3(half.x * 0.5, 0.006, 0.006), 0.003)


func _details() -> void:
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var roof: float = cab["roof"]
	var za: float = cab["za"]
	var zb: float = cab["zb"]
	var rough: MeshKit = _k["rough"]
	var metal: MeshKit = _k["metal"]
	var paint_kit: MeshKit = _k["paint"]
	# Wipers resting along the foot of the windshield.
	var up_glass := Vector3(0, roof - belt, zb - za).normalized()
	var n_glass := Vector3(0, zb - za, -(roof - belt)).normalized()
	var wb: float = cab["wb"]
	rough.color = Color(0.03, 0.03, 0.035)
	for w: Array in [[-0.32, 0.27, 0.12], [0.24, 0.26, 0.06]]:
		var cx: float = w[0]
		var hl: float = w[1]
		var tilt: float = w[2]
		var dir := (Vector3.RIGHT + up_glass * tilt).normalized()
		var basis := Basis(dir, n_glass, dir.cross(n_glass)).orthonormalized()
		_bbox(rough, Vector3(cx * wb / 0.86, belt, za) + up_glass * 0.06 + n_glass * 0.014, Vector3(hl, 0.006, 0.01), 0.004, basis)
	# Cowl panel in front of the windshield.
	rough.color = Color(0.04, 0.04, 0.045)
	rough.quad(Vector3(-wb * 0.98, belt + 0.004, za - 0.1), Vector3(wb * 0.98, belt + 0.004, za - 0.1), Vector3(wb * 0.98, belt + 0.004, za + 0.005), Vector3(-wb * 0.98, belt + 0.004, za + 0.005), Vector3.UP)
	# Aerial.
	match str(shape.get("antenna", "")):
		"fin":
			paint_kit.color = _pc()
			_bbox(paint_kit, Vector3(0, roof + 0.05, float(cab["zc"]) - 0.12), Vector3(0.025, 0.03, 0.08), 0.02)
		"fender":
			var az := za - 0.25
			var ax := float(shape["width"]) * 0.42
			metal.color = CHROME
			_tube(metal, Vector3(ax, _top_at(az) - 0.04, az), Vector3(ax, _top_at(az) + 0.55, az + 0.04), 0.0035, 5, false)
		"mast":
			var ax2 := wb + 0.02
			metal.color = Color(0.2, 0.2, 0.22)
			_tube(metal, Vector3(ax2, belt, za + 0.02), Vector3(ax2, belt + 0.75, za + 0.08), 0.004, 5, false)
	# Roof rails: two black bars along the roof edges on low feet.
	if shape.get("roof_rails", false):
		var rx := float(cab["wr"]) - 0.09
		var r0 := float(cab["zb"]) + 0.2
		var r1 := float(cab["zc"]) - 0.08
		rough.color = Color(0.04, 0.04, 0.045)
		for s: float in [-1.0, 1.0]:
			_bbox(rough, Vector3(rx * s, roof + 0.075, (r0 + r1) * 0.5), Vector3(0.018, 0.012, (r1 - r0) * 0.5), 0.006)
			for zz: float in [r0 + 0.05, r1 - 0.05]:
				_bbox(rough, Vector3(rx * s, roof + 0.045, zz), Vector3(0.022, 0.03, 0.05), 0.008)
	# Fuel filler door on the right rear quarter.
	var fz: float = shape.get("fuel_z", float(shape["rear_axle"]) + _arch_radius() + 0.16)
	var fy := belt - 0.13
	var fx := _side_x(fz, fy) + 0.003
	paint_kit.color = _pc(0.12)
	var fh := 0.075
	for e: Array in [[Vector3(0, fh, 0), Vector3(0, 0.004, fh)], [Vector3(0, -fh, 0), Vector3(0, 0.004, fh)],
			[Vector3(0, 0, fh), Vector3(0, fh, 0.004)], [Vector3(0, 0, -fh), Vector3(0, fh, 0.004)]]:
		var off: Vector3 = e[0]
		var ext: Vector3 = e[1]
		var c := Vector3(fx, fy, fz) + off
		paint_kit.quad(c + Vector3(0, -ext.y, -ext.z), c + Vector3(0, -ext.y, ext.z), c + Vector3(0, ext.y, ext.z), c + Vector3(0, ext.y, -ext.z), Vector3.RIGHT)
	if parked:
		return
	# Underneath: a rear axle or differential, seen from low down.
	rough.color = Color(0.1, 0.1, 0.1)
	var ra: float = shape["rear_axle"]
	var wr: float = shape["wheel_radius"]
	if str(shape.get("drive", "")) != "fwd":
		_bbox(rough, Vector3(0, wr, ra), Vector3(0.13, 0.1, 0.12), 0.04)
		if shape.has("bed"):
			_tube(rough, Vector3(-float(shape["track_half"]) + 0.12, wr, ra), Vector3(float(shape["track_half"]) - 0.12, wr, ra), 0.045, 8, false)


# --- the interior ----------------------------------------------------------------------------

## Inner half width of the cabin: just inside the door skins all along it.
func _cabin_inner() -> float:
	var cab: Dictionary = shape["cabin"]
	var w := float(cab["wb"]) - 0.06
	var z := float(cab["za"])
	while z < float(cab["zd"]):
		w = minf(w, _station_at(z).x * 0.84)
		z += 0.1
	return w


## A strip of trim in this car's style (brushed metal, wood or piano black),
## as a bevelled box.
func _trim_strip(c: Vector3, h: Vector3) -> void:
	var kit: MeshKit
	match _trim_style:
		"wood":
			kit = _k["gloss"]
			kit.color = Color(0.34, 0.18, 0.08)
		"black":
			kit = _k["gloss"]
			kit.color = GLOSS_BLACK
		_:
			kit = _k["metal"]
			kit.color = Color(0.6, 0.61, 0.63)
	_bbox(kit, c, h, 0.004)


## Evenly spaced lines across a panel (stitching, pleats, vent slats): the
## panel is centred at c, spans ±hu along u and ±hv along v, and faces n.
static func _lines(kit: MeshKit, c: Vector3, u: Vector3, v: Vector3, n: Vector3, hu: float, hv: float, count: int, w: float) -> void:
	for i in count:
		var t := lerpf(-hv, hv, (float(i) + 1.0) / (float(count) + 1.0))
		var m := c + v * t + n * 0.002
		kit.quad(m - u * hu - v * w * 0.5, m + u * hu - v * w * 0.5, m + u * hu + v * w * 0.5, m - u * hu + v * w * 0.5, n)


func _interior() -> void:
	var rough: MeshKit = _k["rough"]
	var satin: MeshKit = _k["satin"]
	var gloss: MeshKit = _k["gloss"]
	var metal: MeshKit = _k["metal"]
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var za: float = cab["za"]
	var zd: float = cab["zd"]
	var sp: Array = shape["seat"]
	var sx := float(sp[0])
	var sy := float(sp[1])
	var sz := float(sp[2])
	var iw := _cabin_inner()
	var floor_y := _station_at(sz).y + 0.03
	var zf := za - 0.08
	var truck := shape.has("bed")
	var zr := zd - 0.04 if truck else zd + 0.12
	var dash_y := belt - 0.015
	var zdash := clampf(sz - 0.6, za + 0.14, sz - 0.4)
	var rear_bench := not truck and zr - sz > 1.0
	var rzs := sz + 0.86

	# Floor, with rubber-edged mats in the footwells; firewall; back wall.
	rough.color = _carpet_col
	rough.quad(Vector3(-iw, floor_y, zf), Vector3(iw, floor_y, zf), Vector3(iw, floor_y, zr), Vector3(-iw, floor_y, zr), Vector3.UP)
	rough.color = _carpet_col.darkened(0.25)
	rough.quad(Vector3(-iw, floor_y, zf), Vector3(iw, floor_y, zf), Vector3(iw, dash_y, zf), Vector3(-iw, dash_y, zf), Vector3.BACK)
	rough.color = _lower_col if truck else _carpet_col
	rough.quad(Vector3(-iw, floor_y, zr), Vector3(iw, floor_y, zr), Vector3(iw, belt, zr), Vector3(-iw, belt, zr), Vector3.FORWARD)
	if not parked:
		var mats := [[absf(sx), zf + 0.06, sz - 0.3]]
		if rear_bench:
			mats.append([absf(sx), sz + 0.28, rzs - 0.3])
		for mt: Array in mats:
			for s: float in [-1.0, 1.0]:
				var mc := Vector3(float(mt[0]) * s, floor_y + 0.004, (float(mt[1]) + float(mt[2])) * 0.5)
				var mh := (float(mt[2]) - float(mt[1])) * 0.5
				rough.color = Color(0.03, 0.03, 0.032)
				_panel(rough, mc, 0.46, mh * 2.0, Vector3.UP)
				rough.color = _carpet_col.darkened(0.4)
				_panel(rough, mc + Vector3(0, 0.001, 0), 0.4, mh * 2.0 - 0.06, Vector3.UP)
	if not truck:
		# The parcel shelf under the back glass, with speakers.
		satin.color = _dash_col
		satin.quad(Vector3(-iw, belt - 0.01, zr), Vector3(iw, belt - 0.01, zr), Vector3(iw, belt - 0.01, zd - 0.1), Vector3(-iw, belt - 0.01, zd - 0.1), Vector3.UP)
		if not parked:
			for s: float in [-1.0, 1.0]:
				rough.color = Color(0.03, 0.03, 0.03)
				_disc(rough, Vector3(iw * 0.6 * s, belt - 0.008, zd + 0.02), 0.07, Vector3.UP, 14)

	# The top of each door, closing the gap between the door card and the
	# body side, then the door cards: carpet at the bottom, a cloth insert,
	# a trim strip, and a vinyl top roll.
	satin.color = _dash_col
	var z := za
	while z < zd - 0.001:
		var z2 := minf(z + 0.1, zd)
		for s: float in [-1.0, 1.0]:
			var xo0 := _station_at(z).x * 0.9
			var xo1 := _station_at(z2).x * 0.9
			satin.quad(Vector3(iw * s, belt - 0.004, z), Vector3(xo0 * s, belt - 0.004, z), Vector3(xo1 * s, belt - 0.004, z2), Vector3(iw * s, belt - 0.004, z2), Vector3.UP)
		z = z2
	var y_low := floor_y + 0.16
	var y_trim := belt - 0.14
	for s: float in [-1.0, 1.0]:
		var x := iw * s
		var inward := Vector3(-s, 0, 0)
		rough.color = _carpet_col
		rough.quad(Vector3(x, floor_y, zf), Vector3(x, floor_y, zr), Vector3(x, y_low, zr), Vector3(x, y_low, zf), inward)
		rough.color = _insert_col
		rough.quad(Vector3(x, y_low, zf), Vector3(x, y_low, zr), Vector3(x, y_trim, zr), Vector3(x, y_trim, zf), inward)
		satin.color = _dash_col
		satin.quad(Vector3(x, y_trim, zf), Vector3(x, y_trim, zr), Vector3(x, belt, zr), Vector3(x, belt, zf), inward)
		_trim_strip(Vector3(x - 0.004 * s, y_trim, (zf + zr) * 0.5), Vector3(0.006, 0.012, (zr - zf) * 0.5 - 0.04))
		if parked:
			continue
		satin.color = _lower_col
		_bbox(satin, Vector3(x - 0.012 * s, y_low, (zf + zr) * 0.5), Vector3(0.016, 0.02, (zr - zf) * 0.5 - 0.02), 0.012)
		# Speaker low on the front door, armrest with window switches, pull.
		var spk := Vector3(x - 0.004 * s, floor_y + 0.25, zdash + 0.25)
		metal.color = Color(0.55, 0.56, 0.58)
		_ring(metal, spk, 0.07, 0.08, inward, 18)
		rough.color = Color(0.025, 0.025, 0.028)
		_disc(rough, spk + inward * 0.001, 0.07, inward, 18)
		satin.color = _seat_col
		_bbox(satin, Vector3(x - 0.04 * s, sy + 0.13, sz - 0.18), Vector3(0.04, 0.03, 0.26), 0.018)
		gloss.color = GLOSS_BLACK
		_bbox(gloss, Vector3(x - 0.045 * s, sy + 0.162, sz - 0.36), Vector3(0.025, 0.004, 0.05), 0.003)
		metal.color = CHROME
		_bbox(metal, Vector3(x - 0.012 * s, y_trim + 0.05, sz - 0.42), Vector3(0.008, 0.016, 0.05), 0.006)
		if rear_bench:
			satin.color = _seat_col
			_bbox(satin, Vector3(x - 0.035 * s, sy + 0.1, rzs), Vector3(0.035, 0.025, 0.16), 0.015)

	# The dashboard: a padded vinyl top under the windshield, rolling down to
	# a face with the gauges in front of the driver, the radio and vents in
	# the middle and a trim strip over the glovebox, tucking back to the
	# firewall.
	var prof := [
		Vector2(za - 0.06, dash_y), Vector2(zdash - 0.07, dash_y + 0.012), Vector2(zdash - 0.015, dash_y - 0.01),
		Vector2(zdash, dash_y - 0.06), Vector2(zdash + 0.01, dash_y - 0.2), Vector2(zdash - 0.08, dash_y - 0.3),
		Vector2(zf + 0.02, dash_y - 0.38),
	]
	for i in range(prof.size() - 1):
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var n := Vector3(0, p1.x - p0.x, -(p1.y - p0.y)).normalized()
		if Vector3(0, p0.y - (dash_y - 0.15), p0.x - zf).dot(n) < 0.0:
			n = -n
		var kit := satin if i < 3 else rough
		kit.color = _dash_col if i < 3 else _lower_col
		kit.quad(Vector3(-iw, p0.y, p0.x), Vector3(iw, p0.y, p0.x), Vector3(iw, p1.y, p1.x), Vector3(-iw, p1.y, p1.x), n)
	# The gauge binnacle: a hood over the dials.
	satin.color = _dash_col.darkened(0.15)
	_bbox(satin, Vector3(sx, dash_y + 0.03, zdash - 0.05), Vector3(0.17, 0.035, 0.07), 0.025)
	# Trim across the passenger's side, with the glovebox under it.
	var gx0 := 0.13
	var gx1 := iw - 0.06
	_trim_strip(Vector3((gx0 + gx1) * 0.5 * -signf(sx), dash_y - 0.075, zdash + 0.012), Vector3((gx1 - gx0) * 0.5, 0.018, 0.006))
	if not parked:
		var face_n := Vector3(0, -0.07, 1).normalized()
		rough.color = _lower_col.darkened(0.35)
		var gb := Vector3((gx0 + gx1) * 0.5 * -signf(sx), dash_y - 0.15, zdash + 0.014)
		_frame(rough, gb, gx1 - gx0 - 0.04, 0.1, 0.005, face_n)
		satin.color = _lower_col.darkened(0.2)
		_bbox(satin, gb + Vector3(0, 0.035, 0.004), Vector3(0.03, 0.008, 0.004), 0.003)
		# Gauges: dark faces, chrome rings, white ticks and an orange needle.
		gloss.color = Color(0.02, 0.02, 0.025)
		_panel(gloss, Vector3(sx, dash_y - 0.06, zdash + 0.004), 0.3, 0.11, Vector3.BACK)
		for gx: float in [-0.075, 0.075]:
			var gc := Vector3(sx + gx, dash_y - 0.06, zdash + 0.007)
			metal.color = CHROME
			_ring(metal, gc, 0.041, 0.047, Vector3.BACK, 20)
			gloss.color = Color(0.05, 0.05, 0.06)
			_disc(gloss, gc + Vector3(0, 0, 0.001), 0.041, Vector3.BACK, 20)
			gloss.color = Color(0.9, 0.9, 0.86)
			for t in 9:
				var tb := Basis(Vector3.BACK, deg_to_rad(-120.0 + 30.0 * float(t)))
				gloss.quad(gc + tb * Vector3(-0.0015, 0.03, 0.002), gc + tb * Vector3(0.0015, 0.03, 0.002), gc + tb * Vector3(0.0015, 0.038, 0.002), gc + tb * Vector3(-0.0015, 0.038, 0.002), Vector3.BACK)
			gloss.color = Color(0.98, 0.42, 0.08)
			var nb := Basis(Vector3.BACK, 0.7 if gx < 0.0 else -0.4)
			gloss.quad(gc + nb * Vector3(-0.002, 0, 0.003), gc + nb * Vector3(0.002, 0, 0.003), gc + nb * Vector3(0.002, 0.034, 0.003), gc + nb * Vector3(-0.002, 0.034, 0.003), Vector3.BACK)
		# Centre stack: a piano-black panel with the radio's display and
		# knobs, the climate knobs under it and a red hazard button.
		gloss.color = GLOSS_BLACK
		_bbox(gloss, Vector3(0, dash_y - 0.13, zdash + 0.01), Vector3(0.12, 0.075, 0.008), 0.006)
		gloss.color = Color(0.2, 0.55, 0.62)
		_panel(gloss, Vector3(0, dash_y - 0.1, zdash + 0.019), 0.1, 0.03, Vector3.BACK)
		metal.color = Color(0.7, 0.71, 0.73)
		for kx: float in [-0.085, 0.085]:
			_tube(metal, Vector3(kx, dash_y - 0.1, zdash + 0.018), Vector3(kx, dash_y - 0.1, zdash + 0.03), 0.012, 10, true)
		for kx2: float in [-0.06, 0.0, 0.06]:
			_tube(metal, Vector3(kx2, dash_y - 0.165, zdash + 0.018), Vector3(kx2, dash_y - 0.165, zdash + 0.03), 0.017, 10, true)
		gloss.color = Color(0.75, 0.08, 0.06)
		_bbox(gloss, Vector3(0, dash_y - 0.135, zdash + 0.02), Vector3(0.012, 0.008, 0.004), 0.003)
		# Vents: in the middle and at each end, slatted, in a bright surround.
		for vx: float in [-0.17, 0.17, -iw + 0.12, iw - 0.12]:
			var vc := Vector3(vx, dash_y - 0.085, zdash + 0.012)
			metal.color = Color(0.6, 0.61, 0.63)
			_frame(metal, vc, 0.11, 0.055, 0.006, Vector3.BACK)
			rough.color = Color(0.02, 0.02, 0.022)
			_panel(rough, vc, 0.1, 0.045, Vector3.BACK)
			rough.color = _lower_col
			_lines(rough, vc, Vector3.RIGHT, Vector3.UP, Vector3.BACK, 0.05, 0.022, 3, 0.005)
	# Steering column into the dash (the wheel itself turns; see Car).
	var st := steering_transform()
	var col := st.basis.z
	satin.color = _dash_col.darkened(0.2)
	_tube(satin, st.origin - col * 0.05, st.origin - col * 0.42, 0.03, 8, false)
	_bbox(satin, st.origin - col * 0.13, Vector3(0.055, 0.05, 0.075), 0.02, st.basis)
	if not parked:
		# Indicator and wiper stalks.
		rough.color = Color(0.04, 0.04, 0.045)
		for s: float in [-1.0, 1.0]:
			var root := st.origin - col * 0.12 + st.basis.x * 0.05 * s
			_tube(rough, root, root + st.basis.x * 0.11 * s + st.basis.y * 0.01, 0.006, 5, true)
	if parked:
		var wheel := _steering_kits(float(shape.get("wheel_size", 0.185)), true)
		_append(rough, wheel[0], st, false)

	# Centre console between the seats: a cloth-lined tray, cupholders, the
	# gear lever in a leather boot, the handbrake, and an armrest lid.
	rough.color = _lower_col
	var cz0 := zdash
	var cz1 := sz + 0.15
	var ctop := sy - 0.02
	_bbox(rough, Vector3(0, (floor_y + ctop) * 0.5, (cz0 + cz1) * 0.5), Vector3(0.1, (ctop - floor_y) * 0.5, (cz1 - cz0) * 0.5), 0.03)
	# A dark tray along the top, edged with thin trim rails.
	var tz := (cz0 + sz - 0.2) * 0.5
	var tl := maxf(0.02, (sz - 0.2 - cz0) * 0.5)
	rough.color = Color(0.025, 0.025, 0.028)
	_panel(rough, Vector3(0, ctop + 0.001, tz), 0.15, tl * 2.0, Vector3.UP)
	for s: float in [-1.0, 1.0]:
		_trim_strip(Vector3(0.085 * s, ctop + 0.004, tz), Vector3(0.006, 0.005, tl))
	satin.color = _seat_col
	_bbox(satin, Vector3(0, ctop + 0.045, sz + 0.06), Vector3(0.095, 0.035, 0.13), 0.025)
	if not parked:
		var gz := sz - 0.28
		satin.color = Color(0.04, 0.04, 0.045)
		# The boot: a squat, rounded lump the lever comes out of.
		_bbox(satin, Vector3(0, ctop + 0.02, gz), Vector3(0.05, 0.025, 0.06), 0.02)
		metal.color = Color(0.6, 0.6, 0.62)
		_tube(metal, Vector3(0, ctop + 0.03, gz), Vector3(0, ctop + 0.15, gz - 0.02), 0.008, 6, false)
		if _trim_style == "wood":
			gloss.color = Color(0.34, 0.18, 0.08)
			_bbox(gloss, Vector3(0, ctop + 0.17, gz - 0.024), Vector3(0.024, 0.028, 0.024), 0.02)
		else:
			satin.color = Color(0.03, 0.03, 0.035)
			_bbox(satin, Vector3(0, ctop + 0.17, gz - 0.024), Vector3(0.024, 0.028, 0.024), 0.02)
		# Handbrake beside it, raised a little toward the back.
		var hb := Basis(Vector3.RIGHT, 0.25)
		satin.color = Color(0.05, 0.05, 0.055)
		_bbox(satin, Vector3(0.035 * -signf(sx), ctop + 0.03, sz - 0.1), Vector3(0.016, 0.016, 0.1), 0.012, hb)
		metal.color = Color(0.7, 0.7, 0.72)
		_tube(metal, Vector3(0.035 * -signf(sx), ctop + 0.03, sz - 0.2) + hb * Vector3(0, 0, -0.01), Vector3(0.035 * -signf(sx), ctop + 0.038, sz - 0.205), 0.006, 6, true)
		rough.color = Color(0.02, 0.02, 0.02)
		for cx: float in [-0.04, 0.04]:
			_disc(rough, Vector3(cx, ctop + 0.004, sz - 0.42), 0.032, Vector3.UP, 12)

	# Seats: driver and passenger, and a bench behind if there's room.
	for s: float in [-1.0, 1.0]:
		_seat(Vector3(absf(sx) * s, sy, sz), floor_y, 0.25)
	if not parked:
		_seatbelt(Vector3(absf(sx) * -signf(sx), sy, sz), iw)
	if rear_bench:
		_bench(Vector3(0, sy, rzs), floor_y, iw - 0.04)

	# Headliner details: rear-view mirror, sun visors, dome light.
	var roof: float = cab["roof"]
	var zb: float = cab["zb"]
	satin.color = Color(0.05, 0.05, 0.05)
	_bbox(satin, Vector3(0, roof - 0.1, zb + 0.07), Vector3(0.12, 0.035, 0.015), 0.012)
	_tube(satin, Vector3(0, roof - 0.07, zb + 0.07), Vector3(0, roof - 0.015, zb + 0.04), 0.008, 5, false)
	if not parked:
		metal.color = Color(0.7, 0.74, 0.78)
		metal.quad(Vector3(-0.11, roof - 0.13, zb + 0.086), Vector3(0.11, roof - 0.13, zb + 0.086), Vector3(0.11, roof - 0.07, zb + 0.086), Vector3(-0.11, roof - 0.07, zb + 0.086), Vector3.BACK)
		var visor := _seat_col.lerp(Color(0.62, 0.6, 0.56), 0.55)
		for s: float in [-1.0, 1.0]:
			rough.color = visor
			_bbox(rough, Vector3(0.36 * s, roof - 0.03, zb + 0.11), Vector3(0.2, 0.012, 0.08), 0.008)
			metal.color = Color(0.7, 0.74, 0.78)
			metal.quad(Vector3(0.36 * s - 0.08, roof - 0.043, zb + 0.07), Vector3(0.36 * s + 0.08, roof - 0.043, zb + 0.07),
				Vector3(0.36 * s + 0.08, roof - 0.043, zb + 0.15), Vector3(0.36 * s - 0.08, roof - 0.043, zb + 0.15), Vector3.DOWN)
		gloss.color = Color(0.95, 0.93, 0.85)
		_bbox(gloss, Vector3(0, roof - 0.015, (zb + float(cab["zc"])) * 0.5), Vector3(0.08, 0.006, 0.04), 0.004)


## A bucket seat: a vinyl shell with a pleated cloth insert in the cushion
## and the back, side bolsters, a headrest on two posts, on a riser with
## runners to the floor. `p` is the occupant's hip point.
func _seat(p: Vector3, floor_y: float, hw: float) -> void:
	var rough: MeshKit = _k["rough"]
	var satin: MeshKit = _k["satin"]
	var metal: MeshKit = _k["metal"]
	var shell := _seat_col
	var top := p.y - 0.085
	# Riser and runners.
	rough.color = _lower_col.darkened(0.4)
	_bbox(rough, Vector3(p.x, (floor_y + top - 0.1) * 0.5, p.z - 0.15), Vector3(hw - 0.07, maxf(0.02, (top - 0.1 - floor_y) * 0.5), 0.2), 0.02)
	if not parked:
		metal.color = Color(0.45, 0.45, 0.47)
		for s: float in [-1.0, 1.0]:
			_bbox(metal, Vector3(p.x + (hw - 0.1) * s, floor_y + 0.012, p.z - 0.15), Vector3(0.012, 0.012, 0.26), 0.004)
	# Cushion: the shell, the insert on top with its pleats, the bolsters.
	satin.color = shell
	_bbox(satin, Vector3(p.x, top - 0.065, p.z - 0.16), Vector3(hw - 0.04, 0.055, 0.27), 0.035)
	rough.color = _insert_col
	var ins := Vector3(p.x, top - 0.006, p.z - 0.17)
	_bbox(rough, ins, Vector3(hw - 0.11, 0.014, 0.23), 0.012)
	if not parked:
		rough.color = _insert_col.darkened(0.35)
		_lines(rough, ins + Vector3(0, 0.012, 0), Vector3.RIGHT, Vector3.BACK, Vector3.UP, hw - 0.115, 0.22, 4, 0.007)
	satin.color = shell
	for s: float in [-1.0, 1.0]:
		_bbox(satin, Vector3(p.x + (hw - 0.045) * s, top - 0.035, p.z - 0.14), Vector3(0.045, 0.07, 0.25), 0.04)
	# Back: shell, insert with pleats, bolsters, then the headrest.
	var back := Basis(Vector3.RIGHT, 0.16)
	var base := Vector3(p.x, top - 0.04, p.z + 0.17)
	satin.color = shell
	_bbox(satin, base + back * Vector3(0, 0.33, 0.005), Vector3(hw - 0.04, 0.33, 0.055), 0.04, back)
	rough.color = _insert_col
	var bins := base + back * Vector3(0, 0.3, -0.055)
	_bbox(rough, bins, Vector3(hw - 0.11, 0.25, 0.012), 0.012, back)
	if not parked:
		rough.color = _insert_col.darkened(0.35)
		_lines(rough, bins + back * Vector3(0, 0, -0.012), back.x, back.y, -back.z, hw - 0.115, 0.24, 5, 0.007)
		# A map pocket on the back.
		rough.color = shell.darkened(0.3)
		_bbox(rough, base + back * Vector3(0, 0.18, 0.062), Vector3(hw - 0.1, 0.1, 0.006), 0.005, back)
	satin.color = shell
	for s: float in [-1.0, 1.0]:
		_bbox(satin, base + back * Vector3((hw - 0.045) * s, 0.28, -0.03), Vector3(0.045, 0.27, 0.075), 0.04, back)
	_bbox(satin, base + back * Vector3(0, 0.77, 0.01), Vector3(0.13, 0.075, 0.05), 0.04, back)
	if not parked:
		rough.color = _insert_col
		_bbox(rough, base + back * Vector3(0, 0.77, -0.04), Vector3(0.1, 0.05, 0.008), 0.006, back)
		metal.color = Color(0.7, 0.7, 0.72)
		for s: float in [-1.0, 1.0]:
			_tube(metal, base + back * Vector3(0.07 * s, 0.64, 0.01), base + back * Vector3(0.07 * s, 0.7, 0.01), 0.006, 5, false)
		# Recline lever on the outer side.
		var out := signf(p.x)
		rough.color = Color(0.04, 0.04, 0.045)
		_bbox(rough, Vector3(p.x + (hw + 0.005) * out, top - 0.06, p.z + 0.02), Vector3(0.008, 0.015, 0.07), 0.005)


## The rear bench: one wide cushion and back, each with a pleated insert per
## seat, and two headrests.
func _bench(p: Vector3, floor_y: float, hw: float) -> void:
	var rough: MeshKit = _k["rough"]
	var satin: MeshKit = _k["satin"]
	satin.color = _seat_col
	_bbox(satin, Vector3(0, p.y - 0.12, p.z - 0.12), Vector3(hw, 0.07, 0.24), 0.05)
	var back := Basis(Vector3.RIGHT, 0.32)
	var base := Vector3(0, p.y - 0.12, p.z + 0.12)
	_bbox(satin, base + back * Vector3(0, 0.27, 0.0), Vector3(hw, 0.27, 0.07), 0.05, back)
	rough.color = _lower_col.darkened(0.3)
	_bbox(rough, Vector3(0, (floor_y + p.y - 0.19) * 0.5, p.z - 0.12), Vector3(hw - 0.02, (p.y - 0.19 - floor_y) * 0.5, 0.22), 0.02)
	for s: float in [-1.0, 1.0]:
		var cx := hw * 0.5 * s
		rough.color = _insert_col
		var ci := Vector3(cx, p.y - 0.045, p.z - 0.13)
		_bbox(rough, ci, Vector3(hw * 0.4, 0.012, 0.19), 0.01)
		var bi := base + back * Vector3(cx, 0.26, -0.07)
		_bbox(rough, bi, Vector3(hw * 0.4, 0.2, 0.012), 0.01, back)
		satin.color = _seat_col
		_bbox(satin, base + back * Vector3(cx, 0.6, 0.0), Vector3(0.12, 0.06, 0.045), 0.035, back)
		if not parked:
			rough.color = _insert_col.darkened(0.35)
			_lines(rough, ci + Vector3(0, 0.012, 0), Vector3.RIGHT, Vector3.BACK, Vector3.UP, hw * 0.4, 0.18, 3, 0.007)
			_lines(rough, bi + back * Vector3(0, 0, -0.012), back.x, back.y, -back.z, hw * 0.4, 0.19, 4, 0.007)


## The passenger's seat belt, lying across the empty seat from the pillar
## to the buckle by the console.
func _seatbelt(p: Vector3, iw: float) -> void:
	var rough: MeshKit = _k["rough"]
	var metal: MeshKit = _k["metal"]
	var out := signf(p.x)
	var back := Basis(Vector3.RIGHT, 0.16)
	var base := Vector3(p.x, p.y - 0.125, p.z + 0.17)
	# Points on the front of the seat back (and cushion), just proud of it.
	var on_back := func(x: float, h: float) -> Vector3:
		return base + back * Vector3(x, h, -0.075)
	var pts: Array[Vector3] = [
		Vector3(iw * out - 0.02 * out, p.y + 0.62, p.z + 0.24),
		on_back.call(0.17 * out, 0.62),
		on_back.call(-0.04 * out, 0.3),
		on_back.call(-0.18 * out, 0.08),
		Vector3(p.x - 0.22 * out, p.y - 0.05, p.z + 0.02),
	]
	rough.color = Color(0.06, 0.06, 0.065)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var along := (b - a).normalized()
		var n := back * Vector3.FORWARD
		var side := along.cross(n).normalized() * 0.022
		rough.quad(a - side, a + side, b + side, b - side, n)
	# The upper anchor on the pillar, and the buckle.
	metal.color = Color(0.6, 0.6, 0.62)
	_bbox(metal, pts[0] + Vector3(0, 0.02, 0), Vector3(0.01, 0.03, 0.025), 0.005)
	_bbox(metal, pts[pts.size() - 1], Vector3(0.018, 0.03, 0.012), 0.006)
	rough.color = Color(0.75, 0.1, 0.08)
	_bbox(rough, pts[pts.size() - 1] + Vector3(0, 0.032, 0), Vector3(0.012, 0.006, 0.009), 0.003)


# --- extras ----------------------------------------------------------------------------------

## A raised scoop in the middle of the hood.
func _hood_scoop() -> void:
	var z := lerpf(float(shape["stations"][2][0]), float(shape["cabin"]["za"]), 0.55)
	var y := _top_at(z)
	var kit: MeshKit = _k["paint"]
	kit.color = _pc(0.95)
	_bbox(kit, Vector3(0, y + 0.02, z), Vector3(0.25, 0.05, 0.27), 0.04)
	var gloss: MeshKit = _k["gloss"]
	gloss.color = GLOSS_BLACK
	_panel(gloss, Vector3(0, y + 0.035, z - 0.271), 0.38, 0.045, Vector3.FORWARD)


## A small wing on the trunk lid, or (wing) a tall rally wing on stilts.
func _spoiler(wing := false) -> void:
	var st: Array = shape["stations"]
	var z := float(st[st.size() - 2][0]) - 0.12
	var y := _top_at(z)
	var w := float(shape["width"]) * (0.45 if wing else 0.42)
	var lift := 0.26 if wing else 0.14
	var kit: MeshKit = _k["paint"]
	kit.color = _pc()
	_bbox(kit, Vector3(0, y + lift, z), Vector3(w, 0.02, 0.13 if wing else 0.1), 0.015, Basis(Vector3.RIGHT, -0.08))
	for s: float in [-1.0, 1.0]:
		_bbox(kit, Vector3(w * 0.8 * s, y + lift * 0.5, z), Vector3(0.022, lift * 0.47, 0.06), 0.012)


## Whether racing stripes on this paint are light (on a dark car) or dark:
## the one thing in a car's mesh that depends on its paint (Car._look_key).
static func light_stripes(colour: Color) -> bool:
	return colour.get_luminance() < 0.6


## Twin racing stripes over the hood, roof and trunk.
func _stripes() -> void:
	var kit: MeshKit = _k["gloss"]
	kit.color = Color(0.95, 0.94, 0.9) if parked or light_stripes(paint) else Color(0.08, 0.08, 0.09)
	var st: Array = shape["stations"]
	var cab: Dictionary = shape["cabin"]
	for s: float in [-1.0, 1.0]:
		var x0 := 0.08 * s
		var x1 := 0.2 * s
		var z := float(st[1][0]) + 0.05
		var z_end := float(st[st.size() - 2][0])
		while z < z_end:
			var z2 := minf(z + 0.1, z_end)
			var ya := _top_at(z) + 0.004
			var yb := _top_at(z2) + 0.004
			var in_cab := z2 > float(cab["za"]) - 0.01 and z < float(cab["zd"]) + 0.01
			if not in_cab and absf(yb - ya) < 0.035 * (z2 - z) / 0.1:
				kit.quad(Vector3(x0, ya, z), Vector3(x1, ya, z), Vector3(x1, yb, z2), Vector3(x0, yb, z2), Vector3.UP)
			z = z2
		var ry := float(cab["roof"]) + 0.035 * (1.0 - pow((x0 + x1) * 0.5 / float(cab["wr"]), 2.0)) + 0.004
		kit.quad(Vector3(x0, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zb"])), Vector3(x1, ry, float(cab["zc"])), Vector3(x0, ry, float(cab["zc"])), Vector3.UP)


## Black plastic cladding along the bottom of the doors and sills (a
## crossover's or a lifted wagon's).
func _cladding() -> void:
	var st: Array = shape["stations"]
	var low := 99.0
	for stn: Array in st:
		low = minf(low, float(stn[2]))
	_side_band(low + 0.03, low + 0.24, _nose_z() + 0.05, _tail_z() - 0.05, Color(0.07, 0.07, 0.075), "rough")


## Fake wood down the sides (a 90s estate wagon's), in a pale frame, with
## a few darker grain lines along it.
func _woodgrain() -> void:
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var z0 := _nose_z() + 0.35
	var z1 := _tail_z() - 0.12
	var y0 := belt - 0.36
	var y1 := belt - 0.06
	_side_band(y0 - 0.025, y1 + 0.025, z0 - 0.03, z1 + 0.02, Color(0.74, 0.62, 0.42))
	_side_band(y0, y1, z0, z1, Color(0.4, 0.22, 0.1))
	if parked:
		return
	for k in 3:
		var yy := lerpf(y0 + 0.05, y1 - 0.05, float(k) / 2.0)
		_side_band(yy, yy + 0.006, z0 + 0.02, z1 - 0.02, Color(0.28, 0.15, 0.07))


## Two removable smoked-glass roof panels either side of a centre bar.
func _t_tops() -> void:
	var cab: Dictionary = shape["cabin"]
	var roof: float = cab["roof"]
	var wr: float = cab["wr"]
	var z0 := float(cab["zb"]) + 0.08
	var z1 := float(cab["zc"]) - 0.12
	var gloss: MeshKit = _k["gloss"]
	gloss.color = Color(0.03, 0.035, 0.04)
	for s: float in [-1.0, 1.0]:
		var xa := 0.1 * s
		var xb := (wr - 0.1) * s
		var ya := roof + 0.035 * (1.0 - pow(xa / wr, 2.0)) + 0.003
		var yb := roof + 0.035 * (1.0 - pow(xb / wr, 2.0)) + 0.003
		gloss.quad(Vector3(xa, ya, z0), Vector3(xb, yb, z0), Vector3(xb, yb, z1), Vector3(xa, ya, z1), Vector3.UP)


## The track a sliding side door runs in, along the rear quarter (a van's).
func _slider_track() -> void:
	var cab: Dictionary = shape["cabin"]
	var y := float(cab["belt"]) - 0.08
	var z0 := _b_pillar_z() + 0.25
	var z1 := float(cab["zd"]) - 0.05
	_side_band(y, y + 0.014, z0, z1, GLOSS_BLACK)


## A full-size spare on the tailgate (an off-roader's), on a black carrier.
func _spare_tyre() -> void:
	var st: Array = shape["stations"]
	var r := float(shape["wheel_radius"]) * 0.96
	var w := float(shape["wheel_width"])
	var style: String = shape.get("wheel_style", "steel6")
	var rz := _tail_z()
	var c := Vector3(0, float(st[st.size() - 1][3]) - 0.05, rz + w * 0.5 + 0.06)
	# The wheel's axle is +x; turn it to point back.
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), c)
	_append(_k["rough"], _tyre_kit(r, w, style, true), xf, false)
	_append(_k["metal"], _rim_kit(r, w, style, true), xf, false)
	var rough: MeshKit = _k["rough"]
	rough.color = TRIM
	_bbox(rough, Vector3(0, c.y, rz + 0.03), Vector3(0.1, 0.1, 0.04), 0.02)

# --- police kit ------------------------------------------------------------------------------

## Where the band down a police car's sides runs: [y bottom, y top, z from,
## z to]. The words on it (PoliceGear) are placed from this too.
func police_band() -> Array:
	var cab: Dictionary = shape["cabin"]
	var belt: float = cab["belt"]
	var z_to := _tail_z() - 0.12
	return [belt - 0.25, belt - 0.07, _nose_z() + 0.3, z_to]


## Half width of the outside of the body at (z, y), counting a pickup's box.
func outer_x(z: float, y: float) -> float:
	if shape.has("bed") and z > float(shape["bed"]["z0"]):
		return float(shape["width"]) * 0.5 - 0.01
	return _side_x(z, y)


## A police car's own kit, built into the body: a band of the fleet's
## colour down both sides (broken by the wheel arches), a push bar on the
## nose and a spotlight on the driver's A-pillar. The light bar and the
## words are PoliceGear's, so they can flash and be read.
func _police() -> void:
	var band := police_band()
	_side_band(band[0], band[1], band[2], band[3], Color.html(str(shape.get("band", "#1b2a4a"))))
	# A thin red pinstripe under it.
	_side_band(float(band[0]) - 0.045, float(band[0]) - 0.02, band[2], band[3], Color(0.7, 0.05, 0.06))
	if shape.has("band_stripe"):
		# A gold edge over the band (the FIP).
		_side_band(float(band[1]) + 0.012, float(band[1]) + 0.034, band[2], band[3], Color.html(str(shape["band_stripe"])))
	if parked:
		return
	if shape.get("crest", false):
		_crest(band)
	_police_kit()


## The FIP's crest on each front door, on the band: a gold roundel ringed
## with green leaves, a crown on top and a potato in the middle (our own,
## close enough to read as federal). Low-segment discs and flat quads in the
## gloss kit, a couple of hundred triangles a side.
func _crest(band: Array) -> void:
	var gloss: MeshKit = _k["gloss"]
	var cab: Dictionary = shape["cabin"]
	var y := (float(band[0]) + float(band[1])) * 0.5 + 0.05
	var z := float(cab["za"]) + 0.42
	var r := 0.15
	var gold := Color.html(str(shape.get("band_stripe", "#e0b13a")))
	for s: float in [-1.0, 1.0]:
		var n := Vector3(s, 0, 0)
		var x := (outer_x(z, y) + 0.014) * s
		var c := Vector3(x, y, z)
		gloss.color = gold
		_disc(gloss, c, r, n, 16)
		gloss.color = Color(0.09, 0.14, 0.32)
		_disc(gloss, c + n * 0.002, r * 0.78, n, 16)
		# The leaves round the ring.
		gloss.color = Color(0.13, 0.42, 0.2)
		for i in 10:
			var a := TAU * (float(i) + 0.5) / 10.0
			if absf(a - PI * 0.5) < 0.5:
				continue # the crown goes at the top
			var p := c + n * 0.003 + Vector3(0, sin(a), cos(a)) * r * 0.9
			var t := Vector3(0, cos(a), -sin(a)) * 0.035
			var o := Vector3(0, sin(a), cos(a)) * 0.016
			gloss.quad(p - t - o, p - t + o, p + t + o, p + t - o, n)
		# The potato: a squashed disc, earth brown, with two eyes.
		gloss.color = Color(0.55, 0.36, 0.18)
		for i in 12:
			var a0 := TAU * float(i) / 12.0
			var a1 := TAU * float(i + 1) / 12.0
			var e := Vector2(r * 0.5, r * 0.32)
			var cc := c + n * 0.004
			gloss.tri(cc, cc + Vector3(0, sin(a0) * e.y, cos(a0) * e.x), cc + Vector3(0, sin(a1) * e.y, cos(a1) * e.x), n)
		gloss.color = Color(0.25, 0.15, 0.07)
		for k: float in [-0.25, 0.3]:
			_disc(gloss, c + n * 0.005 + Vector3(0, 0.01, k * r), 0.011, n, 6)
		# The crown: a gold band and three points.
		gloss.color = gold
		var top := c + n * 0.003 + Vector3(0, r * 0.98, 0)
		gloss.quad(top + Vector3(0, 0, -0.06), top + Vector3(0, 0, 0.06), top + Vector3(0, 0.03, 0.06), top + Vector3(0, 0.03, -0.06), n)
		for k: float in [-0.05, 0.0, 0.05]:
			var b := top + Vector3(0, 0.03, k)
			gloss.tri(b + Vector3(0, 0, -0.02), b + Vector3(0, 0, 0.02), b + Vector3(0, 0.045, 0), n)


## A band of colour down both sides between heights y0 and y1, from z_from
## to z_to, broken where it meets a wheel arch or the gap behind a cab.
func _side_band(y0: float, y1: float, z_from: float, z_to: float, colour: Color, kit_name := "gloss") -> void:
	var gloss: MeshKit = _k[kit_name]
	gloss.color = colour
	for s: float in [-1.0, 1.0]:
		var z := z_from
		# Coarser on a parked car, which is drawn by the dozen.
		while z < z_to - 0.001:
			var z2 := minf(z + (0.12 if parked else 0.05), z_to)
			var clear := true
			for zz: float in [z, z2]:
				var sv := _station_at(zz)
				var on_bed := shape.has("bed") and zz > float(shape["bed"]["z0"]) - 0.02
				var top := float(shape["bed"]["top"]) if on_bed else sv.z
				if _arch_bottom(zz, sv.y, sv.z) > y0 or top < y1 + 0.03:
					clear = false
			if shape.has("bed") and z < float(shape["bed"]["z0"]) + 0.02 and z2 > float(shape["bed"]["z0"]) - 0.06:
				clear = false # the gap between the cab and the box
			if clear:
				# In rows, so it follows the side's bulge instead of cutting into it.
				var o := 0.006
				var rows := 2 if parked else 4
				for k in rows:
					var ya := lerpf(y0, y1, float(k) / rows)
					var yb := lerpf(y0, y1, float(k + 1) / rows)
					gloss.quad(Vector3((outer_x(z, ya) + o) * s, ya, z), Vector3((outer_x(z2, ya) + o) * s, ya, z2),
						Vector3((outer_x(z2, yb) + o) * s, yb, z2), Vector3((outer_x(z, yb) + o) * s, yb, z), Vector3(s, 0, 0))
			z = z2


## The push bar on the nose and the spotlight on the A-pillar.
func _police_kit() -> void:
	var rough: MeshKit = _k["rough"]
	var metal: MeshKit = _k["metal"]
	# Push bar: two uprights off the frame and two rails across, in front
	# of the grille, black.
	var st: Array = shape["stations"]
	var fz := _nose_z() - 0.13
	var by := float(st[0][2]) + 0.02
	var ly: float = shape.get("lights_y", 0.6)
	var top := ly + 0.14
	var hw := float(st[1][1]) * 0.42
	rough.color = Color(0.035, 0.035, 0.038)
	for s: float in [-1.0, 1.0]:
		_tube(rough, Vector3(hw * s, by, fz), Vector3(hw * s, top, fz), 0.028, 8, true)
		_tube(rough, Vector3(hw * s, by + 0.06, fz), Vector3(hw * s, by + 0.06, fz + 0.22), 0.025, 8, false)
	for yy: float in [top - 0.02, (by + top) * 0.5]:
		_tube(rough, Vector3(-hw - 0.02, yy, fz), Vector3(hw + 0.02, yy, fz), 0.022, 8, true)
	_bbox(rough, Vector3(0, by + 0.1, fz), Vector3(hw, 0.06, 0.03), 0.01)
	# Spotlight on the driver's A-pillar.
	var cab: Dictionary = shape["cabin"]
	var sp := Vector3(-float(cab["wb"]) - 0.06, float(cab["belt"]) + 0.16, float(cab["za"]) + 0.12)
	metal.color = Color(0.75, 0.76, 0.78)
	_tube(metal, sp, sp + Vector3(0, 0, -0.16), 0.055, 12, true)
	_tube(metal, sp + Vector3(0.05, 0, 0.0), sp + Vector3(0.1, 0, 0.02), 0.012, 6, false)


# --- shape helpers ---------------------------------------------------------------------------

## A flat rectangle facing ±z (n), centred at c.
func _panel(kit: MeshKit, c: Vector3, w: float, h: float, n: Vector3) -> void:
	var hw := w * 0.5
	var hh := h * 0.5
	if _log_lamps and absf(n.z) > 0.5:
		LampGlow.note(lamps, LampGlow.kind_of(kit.color), LampGlow.rect(c, w, h, n), n)
	if absf(n.z) > 0.5:
		kit.quad(c + Vector3(-hw, -hh, 0), c + Vector3(hw, -hh, 0), c + Vector3(hw, hh, 0), c + Vector3(-hw, hh, 0), n)
	else:
		kit.quad(c + Vector3(-hw, 0, -hh), c + Vector3(hw, 0, -hh), c + Vector3(hw, 0, hh), c + Vector3(-hw, 0, hh), n)


## A flat rectangle on the side of the car (facing ±X), centred at c.
func _panel_side(kit: MeshKit, c: Vector3, length: float, h: float, n: Vector3) -> void:
	var hl := length * 0.5
	var hh := h * 0.5
	if _log_lamps:
		LampGlow.note(lamps, LampGlow.kind_of(kit.color), [c + Vector3(0, -hh, -hl), c + Vector3(0, -hh, hl), c + Vector3(0, hh, hl), c + Vector3(0, hh, -hl)], n)
	kit.quad(c + Vector3(0, -hh, -hl), c + Vector3(0, -hh, hl), c + Vector3(0, hh, hl), c + Vector3(0, hh, -hl), n)


## A rectangular frame (border t wide) facing ±z.
func _frame(kit: MeshKit, c: Vector3, w: float, h: float, t: float, n: Vector3) -> void:
	_panel(kit, c + Vector3(0, h * 0.5 - t * 0.5, 0), w, t, n)
	_panel(kit, c + Vector3(0, -h * 0.5 + t * 0.5, 0), w, t, n)
	_panel(kit, c + Vector3(w * 0.5 - t * 0.5, 0, 0), t, h - t * 2.0, n)
	_panel(kit, c + Vector3(-w * 0.5 + t * 0.5, 0, 0), t, h - t * 2.0, n)


static func _perp(n: Vector3) -> Array:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	return [u, n.cross(u).normalized()]


static func _disc(kit: MeshKit, c: Vector3, r: float, n: Vector3, segs: int) -> void:
	var uv := _perp(n)
	var u: Vector3 = uv[0]
	var v: Vector3 = uv[1]
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		kit.tri(c, c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, n)


static func _ring(kit: MeshKit, c: Vector3, r0: float, r1: float, n: Vector3, segs: int) -> void:
	var uv := _perp(n)
	var u: Vector3 = uv[0]
	var v: Vector3 = uv[1]
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		kit.quad(c + d0 * r0, c + d1 * r0, c + d1 * r1, c + d0 * r1, n)


## A round tube from a to b, smooth shaded, optionally capped.
static func _tube(kit: MeshKit, a: Vector3, b: Vector3, r: float, segs: int, cap: bool) -> void:
	var ax := (b - a).normalized()
	var uv := _perp(ax)
	var u: Vector3 = uv[0]
	var v: Vector3 = uv[1]
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		kit.quad_smooth(a + d0 * r, a + d1 * r, b + d1 * r, b + d0 * r, d0, d1, d1, d0, (d0 + d1).normalized())
	if cap:
		_disc(kit, b, r, ax, segs)
		_disc(kit, a, r, -ax, segs)


## A box with bevelled edges and corners, half size h, bevel b, turned by basis.
static func _bbox(kit: MeshKit, c: Vector3, h: Vector3, b: float, basis := Basis()) -> void:
	b = clampf(b, 0.0005, minf(h.x, minf(h.y, h.z)) * 0.95)
	var inner := h - Vector3(b, b, b)
	var P := func(axis: int, s: Vector3) -> Vector3:
		var p := Vector3(inner.x * s.x, inner.y * s.y, inner.z * s.z)
		p[axis] = h[axis] * s[axis]
		return c + basis * p
	var N := func(v: Vector3) -> Vector3: return (basis * v).normalized()
	var signs := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for axis in 3:
		var o1 := (axis + 1) % 3
		var o2 := (axis + 2) % 3
		for sa: float in [-1.0, 1.0]:
			var corners: Array[Vector3] = []
			for sg: Vector2 in signs:
				var s := Vector3.ZERO
				s[axis] = sa
				s[o1] = sg.x
				s[o2] = sg.y
				corners.append(P.call(axis, s))
			var n := Vector3.ZERO
			n[axis] = sa
			kit.quad(corners[0], corners[1], corners[2], corners[3], N.call(n))
	for a in 3:
		var c2 := (a + 1) % 3
		var e := (a + 2) % 3
		for sa: float in [-1.0, 1.0]:
			for sc: float in [-1.0, 1.0]:
				var s0 := Vector3.ZERO
				s0[a] = sa
				s0[c2] = sc
				s0[e] = -1.0
				var s1 := s0
				s1[e] = 1.0
				var n := Vector3.ZERO
				n[a] = sa
				n[c2] = sc
				kit.quad(P.call(a, s0), P.call(a, s1), P.call(c2, s1), P.call(c2, s0), N.call(n))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				kit.tri(P.call(0, s), P.call(1, s), P.call(2, s), N.call(s))


## Copy src's triangles into dst, moved by xf, mirrored in x first if asked.
static func _append(dst: MeshKit, src: MeshKit, xf: Transform3D, mirror: bool) -> void:
	var n := src.verts.size()
	var order := [0, 2, 1] if mirror else [0, 1, 2]
	for t in range(0, n, 3):
		for o: int in order:
			var i := t + o
			var p := src.verts[i]
			var nn := src.normals[i]
			if mirror:
				p.x = -p.x
				nn.x = -nn.x
			dst.verts.append(xf * p)
			dst.normals.append((xf.basis * nn).normalized())
			dst.uvs.append(Vector2.ZERO)
			dst.colors.append(src.colors[i])


# --- the steering wheel ----------------------------------------------------------------------

## The steering wheel, in its own space: the rim in the XY plane facing +Z
## (toward the driver), three spokes and a padded hub. Two surfaces: the
## leather (rough) and the badge (metal).
static func steering_wheel_mesh(radius := 0.185) -> ArrayMesh:
	var key := "steer/%.3f" % radius
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var kits := _steering_kits(radius, false)
	var mesh := ModelLod.finish_kits([[kits[0], material("rough")], [kits[1], material("metal")]])
	_wheel_meshes[key] = mesh
	return mesh


## Where a hand holds the wheel (0 left, 1 right), in the wheel's space.
static func steering_grip(side: int, radius := 0.185) -> Vector3:
	var a := PI - GRIP_ANGLE if side == 0 else GRIP_ANGLE
	return Vector3(cos(a) * radius, sin(a) * radius, 0.0)


static func _steering_kits(R: float, lod: bool) -> Array:
	var leather := MeshKit.new()
	leather.use_color = true
	var badge := MeshKit.new()
	badge.use_color = true
	var tube := 0.016
	var U := 16 if lod else 40
	var V := 4 if lod else 8
	leather.color = Color(0.045, 0.045, 0.048)
	for i in U:
		var u0 := TAU * float(i) / float(U)
		var u1 := TAU * float(i + 1) / float(U)
		var r0 := Vector3(cos(u0), sin(u0), 0)
		var r1 := Vector3(cos(u1), sin(u1), 0)
		for j in V:
			var v0 := TAU * float(j) / float(V)
			var v1 := TAU * float(j + 1) / float(V)
			var n00 := r0 * cos(v0) + Vector3.BACK * sin(v0)
			var n10 := r1 * cos(v0) + Vector3.BACK * sin(v0)
			var n11 := r1 * cos(v1) + Vector3.BACK * sin(v1)
			var n01 := r0 * cos(v1) + Vector3.BACK * sin(v1)
			leather.quad_smooth(r0 * R + n00 * tube, r1 * R + n10 * tube, r1 * R + n11 * tube, r0 * R + n01 * tube, n00, n10, n11, n01, (n00 + n11).normalized())
	leather.color = Color(0.06, 0.06, 0.065)
	for ang: float in [0.0, PI, -PI * 0.5]:
		var basis := Basis(Vector3.BACK, ang)
		var r_in := 0.055
		var r_out := R - 0.008
		_bbox(leather, basis * Vector3((r_in + r_out) * 0.5, 0, -0.012), Vector3((r_out - r_in) * 0.5, 0.022, 0.008), 0.006, basis)
	leather.color = Color(0.05, 0.05, 0.055)
	_bbox(leather, Vector3(0, -0.005, -0.01), Vector3(0.075, 0.06, 0.028), 0.022)
	badge.color = CHROME
	_bbox(badge, Vector3(0, -0.002, 0.018), Vector3(0.022, 0.014, 0.003), 0.003)
	return [leather, badge]


# --- wheels ----------------------------------------------------------------------------------

## A wheel of the given size and style, axle along X, outer face on +X.
## Mirror it (scale.x = -1) for the left side. Two surfaces: the tyre
## (treaded, with rounded shoulders and a lettered sidewall) and the rim
## (real spokes over the brake, lip, barrel, lug nuts and a centre cap).
## `lod` is the low-detail version for further away (ModelLod.WHEEL_RANGE);
## `dual` > 0 makes a pair of dual tyres that far either side of the middle.
static func wheel_mesh(r: float = 0.31, width: float = 0.2, style := "alloy10", lod := false, dual := 0.0) -> ArrayMesh:
	var key := "wheel/%.3f/%.3f/%s/%s/%.3f" % [r, width, style, lod, dual]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var tyre := _tyre_kit(r, width, style, lod)
	var rim := _rim_kit(r, width, style, lod)
	if dual > 0.0:
		var t2 := MeshKit.new()
		t2.use_color = true
		var r2 := MeshKit.new()
		r2.use_color = true
		for x: float in [-dual, dual]:
			_append(t2, tyre, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), false)
			_append(r2, rim, Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)), false)
		tyre = t2
		rim = r2
	var mesh := ModelLod.finish_kits([[tyre, material("rubber")], [rim, material("metal")]])
	_wheel_meshes[key] = mesh
	return mesh


## What sits behind the spokes and steers with the wheel but doesn't spin:
## the brake disc, the caliper over it and the dust shield.
static func brake_mesh(r: float, width: float, style: String, caliper: Color) -> ArrayMesh:
	var key := "brake/%.3f/%.3f/%s/%s" % [r, width, style, caliper.to_html()]
	if _wheel_meshes.has(key):
		return _wheel_meshes[key]
	var kits := _brake_kits(r, width, style, caliper, false)
	var mesh := ModelLod.finish_kits([[kits[0], material("rough")], [kits[1], material("metal")], [kits[2], material("gloss")]])
	_wheel_meshes[key] = mesh
	return mesh


static func _around(a: float) -> Vector3:
	return Vector3(0.0, sin(a), cos(a))


static func _tyre_kit(r: float, width: float, style: String, lod: bool) -> MeshKit:
	var hw := width * 0.5
	var rf: float = RIM_FRAC.get(style, 0.66)
	var H := 1.0 - rf
	var kit := MeshKit.new()
	kit.use_color = true
	var segs := 16 if lod else 56
	var side_col := Color(0.06, 0.06, 0.062)
	var tread_col := Color(0.045, 0.045, 0.047)
	var groove_col := Color(0.018, 0.018, 0.02)
	# Raised white letters on the muscle car's tyres; on the rest, black
	# letters a shade off the rubber, seen only when the light catches them.
	var white_letters := style == "mag5"
	var letter_col := Color(0.88, 0.87, 0.84) if white_letters else Color(0.074, 0.074, 0.077)
	var gd := 0.03 if style == "steel6" else 0.02
	# Profile points [radius share, x share of half width, notched] and the
	# kind of each strip between them.
	var pts := []
	var kinds := []
	var add := func(rr: float, xx: float, kind: String, notch := false) -> void:
		if not pts.is_empty():
			kinds.append(kind)
		pts.append([rr, xx, notch])
	if lod:
		for p: Array in [[rf, -0.86], [rf + 0.5 * H, -1.0], [0.97, -0.94], [1.0, -0.8], [1.0, 0.8], [0.97, 0.94], [rf + 0.5 * H, 1.0], [rf, 0.86]]:
			add.call(float(p[0]), float(p[1]), "side" if absf(float(p[1])) > 0.85 or kinds.size() < 2 else "tread")
	else:
		var notch := style == "steel6"
		add.call(rf, -0.84, "side")
		add.call(rf + 0.25 * H, -0.97, "side")
		add.call(rf + 0.6 * H, -1.0, "side")
		add.call(rf + 0.86 * H, -0.97, "side")
		add.call(0.985, -0.9, "side")
		add.call(1.0, -0.8, "side", notch)
		add.call(1.0, -0.5, "tread", notch)
		add.call(1.0 - gd, -0.5, "groove")
		add.call(1.0 - gd, -0.42, "groove")
		add.call(1.0, -0.42, "groove")
		add.call(1.0, -0.04, "tread")
		add.call(1.0 - gd, -0.04, "groove")
		add.call(1.0 - gd, 0.04, "groove")
		add.call(1.0, 0.04, "groove")
		add.call(1.0, 0.42, "tread")
		add.call(1.0 - gd, 0.42, "groove")
		add.call(1.0 - gd, 0.5, "groove")
		add.call(1.0, 0.5, "groove", notch)
		add.call(1.0, 0.8, "tread", notch)
		add.call(0.985, 0.9, "side")
		add.call(rf + 0.86 * H, 0.97, "side")
		add.call(rf + 0.72 * H, 0.99, "side")
		if white_letters:
			# Three rows, so the letters have shapes, not one block apiece.
			add.call(rf + 0.62 * H, 0.99, "letters0")
			add.call(rf + 0.52 * H, 0.99, "letters1")
			add.call(rf + 0.42 * H, 0.99, "letters2")
		else:
			add.call(rf + 0.42 * H, 0.99, "letters")
		add.call(rf + 0.2 * H, 0.95, "side")
		add.call(rf, 0.84, "side")
	var rad := func(p: Array, k: int) -> float:
		return (float(p[0]) - (gd if bool(p[2]) and k % 2 == 1 else 0.0)) * r
	# Each strip's outward direction in the profile (x, radial). The profile
	# runs one way round (back bead, tread, front bead), so outward is always
	# the same turn of its direction: below the widest point the sidewall
	# leans in toward the axle, and outward there points a little inward.
	var sn: Array[Vector2] = []
	for i in range(pts.size() - 1):
		var dn := Vector2((float(pts[i][0]) - float(pts[i + 1][0])) * r, (float(pts[i + 1][1]) - float(pts[i][1])) * hw)
		sn.append(dn.normalized() if dn.length() > 0.00001 else Vector2.ZERO)
	# The rounded parts (sidewall into shoulder) share normals where strips
	# meet, so they shade as one curve, not rings; groove edges stay sharp.
	var smooth := func(i: int, j: int) -> Vector2:
		if j < 0 or j >= sn.size() or kinds[i] == "groove" or kinds[j] == "groove":
			return sn[i]
		var m: Vector2 = sn[i] + sn[j]
		return m.normalized() if m.length() > 0.001 else sn[i]
	for i in range(pts.size() - 1):
		var p0: Array = pts[i]
		var p1: Array = pts[i + 1]
		var kind: String = kinds[i]
		var x0 := float(p0[1]) * hw
		var x1 := float(p1[1]) * hw
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var r0: float = rad.call(p0, k)
			var r1: float = rad.call(p1, k)
			match kind:
				"tread":
					kit.color = tread_col
				"groove":
					kit.color = groove_col
				"letters":
					var m := k % (segs / 2)
					kit.color = letter_col if m >= 8 and m < 17 and m % 3 != 2 else side_col
				"letters0", "letters1", "letters2":
					# Letters two columns wide with a gap between, twice
					# round the tyre; each a made-up glyph of 2 by 3.
					var col := k % (segs / 2) - 4
					var row := int(kind.right(1))
					var lit := col >= 0 and col < 21 and col % 3 != 2
					if lit:
						var glyph: int = TYRE_GLYPHS[(col / 3) % TYRE_GLYPHS.size()]
						lit = (glyph >> ((col % 3) * 3 + row)) & 1 == 1
					kit.color = letter_col if lit else side_col
				_:
					kit.color = side_col
			var n2 := Vector2(r0 - r1, x1 - x0) # (x, radial), this quad's own
			if n2.length() < 0.00001:
				continue
			n2 = n2.normalized()
			var e0: Vector2 = smooth.call(i, i - 1) if not bool(p0[2]) else n2
			var e1: Vector2 = smooth.call(i, i + 1) if not bool(p1[2]) else n2
			var d0 := _around(a0)
			var d1 := _around(a1)
			var face := ((d0 + d1).normalized() * n2.y + Vector3.RIGHT * n2.x).normalized()
			kit.quad_smooth(Vector3(x0, 0, 0) + d0 * r0, Vector3(x0, 0, 0) + d1 * r0, Vector3(x1, 0, 0) + d1 * r1, Vector3(x1, 0, 0) + d0 * r1,
				(d0 * e0.y + Vector3.RIGHT * e0.x).normalized(), (d1 * e0.y + Vector3.RIGHT * e0.x).normalized(),
				(d1 * e1.y + Vector3.RIGHT * e1.x).normalized(), (d0 * e1.y + Vector3.RIGHT * e1.x).normalized(), face)
			# Walls between a raised tread block and a notch beside it.
			if bool(p0[2]) and bool(p1[2]):
				var hi := float(p0[0]) * r
				var lo := hi - gd * r
				var t := Vector3(0, cos(a1), -sin(a1)) * (1.0 if k % 2 == 0 else -1.0)
				kit.color = groove_col
				kit.quad(Vector3(x0, 0, 0) + d1 * hi, Vector3(x1, 0, 0) + d1 * hi, Vector3(x1, 0, 0) + d1 * lo, Vector3(x0, 0, 0) + d1 * lo, t)
	return kit


## Is the rim's face solid at this radius share and angle (or open to the
## brake behind)?
static func _rim_solid(style: String, f: float, a: float) -> bool:
	if f > 0.88:
		return true
	if WHEEL_LOOKS.has(style):
		style = WHEEL_LOOKS[style][0]
	match style:
		"lace":
			# Twenty thin spokes and a ring tying them together half way out.
			if f < 0.3 or absf(f - 0.6) < 0.05:
				return true
			var pl := fposmod(a / (TAU / 20.0), 1.0)
			return minf(pl, 1.0 - pl) < 0.18
		"hubcap":
			# Solid, but for a ring of slots near the rim.
			if f < 0.66 or f > 0.82:
				return true
			var ph := fposmod(a / (TAU / 12.0), 1.0)
			return minf(ph, 1.0 - ph) > 0.22
		"aero":
			# Nearly flat, with five small openings.
			if f < 0.5 or f > 0.8:
				return true
			var pa := fposmod(a / (TAU / 5.0), 1.0)
			return minf(pa, 1.0 - pa) > 0.14
		"mag5":
			if f < 0.36:
				return true
			var p := fposmod(a / (TAU / 5.0), 1.0)
			var d := minf(p, 1.0 - p)
			return d < lerpf(0.2, 0.12, (f - 0.36) / 0.52)
		"steel6":
			if f < 0.34:
				return true
			var q := Vector2(cos(a), sin(a)) * f
			for i in 6:
				var ha := (float(i) + 0.5) * TAU / 6.0
				if q.distance_to(Vector2(cos(ha), sin(ha)) * 0.62) < 0.15:
					return false
			return true
		_:
			if f < 0.34:
				return true
			var p2 := fposmod(a / (TAU / 10.0), 1.0)
			var d2 := minf(p2, 1.0 - p2)
			return d2 < lerpf(0.17, 0.13, (f - 0.34) / 0.54)


static func _rim_kit(r: float, width: float, style: String, lod: bool) -> MeshKit:
	var hw := width * 0.5
	var rf: float = RIM_FRAC.get(style, 0.66)
	var rr := r * rf
	var xf := hw * 0.8
	var kit := MeshKit.new()
	kit.use_color = true
	var face_col: Color
	var lip_col: Color
	var barrel_col := Color(0.35, 0.35, 0.36)
	var cap_col: Color
	var lugs := 5
	var dish := 0.2
	match style:
		"mag5":
			face_col = Color(0.8, 0.8, 0.82)
			lip_col = Color(0.95, 0.95, 0.96)
			cap_col = Color(0.92, 0.92, 0.93)
			dish = 0.35
		"steel6":
			face_col = Color(0.24, 0.25, 0.26)
			lip_col = Color(0.82, 0.83, 0.84)
			cap_col = Color(0.93, 0.93, 0.94)
			lugs = 6
			dish = 0.08
		_:
			face_col = Color(0.64, 0.66, 0.68)
			lip_col = Color(0.78, 0.79, 0.8)
			cap_col = Color(0.12, 0.12, 0.13)
	if WHEEL_LOOKS.has(style):
		var look: Array = WHEEL_LOOKS[style]
		face_col = look[1]
		lip_col = look[2]
		cap_col = look[3]
		dish = {"mag5": 0.3, "hubcap": 0.06, "aero": 0.03}.get(look[0], 0.2)
	var A := 30 if lod else 80
	var fracs: Array = [1.0, 0.94, 0.62, 0.3] if lod else [1.0, 0.94, 0.86, 0.77, 0.69, 0.62, 0.55, 0.48, 0.41, 0.34, 0.28]
	var x_at := func(f: float) -> float: return xf - 0.01 - dish * hw * clampf((0.94 - f) / 0.66, 0.0, 1.0)
	var slope := dish * hw / (0.66 * rr)
	var sd := 0.022 # spoke depth
	# Lip: a bright ring stepping in from the tyre, and its rolled edge.
	for k in A:
		var a0 := TAU * float(k) / float(A)
		var a1 := TAU * float(k + 1) / float(A)
		var d0 := _around(a0)
		var d1 := _around(a1)
		kit.color = lip_col
		kit.quad(Vector3(xf + 0.004, 0, 0) + d0 * rr * 1.04, Vector3(xf + 0.004, 0, 0) + d1 * rr * 1.04, Vector3(xf, 0, 0) + d1 * rr * 0.94, Vector3(xf, 0, 0) + d0 * rr * 0.94,
			(Vector3.RIGHT + (d0 + d1).normalized() * 0.15).normalized())
		kit.quad(Vector3(xf, 0, 0) + d0 * rr * 0.94, Vector3(xf, 0, 0) + d1 * rr * 0.94, Vector3(xf - 0.01, 0, 0) + d1 * rr * 0.94, Vector3(xf - 0.01, 0, 0) + d0 * rr * 0.94, -(d0 + d1).normalized())
		# Barrel: the inside of the rim, seen through the spokes.
		kit.color = barrel_col
		kit.quad(Vector3(xf - 0.01, 0, 0) + d0 * rr * 0.94, Vector3(xf - 0.01, 0, 0) + d1 * rr * 0.94, Vector3(-hw * 0.8, 0, 0) + d1 * rr * 0.94, Vector3(-hw * 0.8, 0, 0) + d0 * rr * 0.94, -(d0 + d1).normalized())
	# The face, cell by cell: solid cells are spoke (with walls where they
	# meet an opening), the rest is open to the brake behind.
	var solid := []
	for j in range(1, fracs.size() - 1):
		var row := []
		var fm := (float(fracs[j]) + float(fracs[j + 1])) * 0.5
		for k in A:
			row.append(_rim_solid(style, fm, TAU * (float(k) + 0.5) / float(A)))
		solid.append(row)
	for jj in solid.size():
		var j := jj + 1
		var f0: float = fracs[j]
		var f1: float = fracs[j + 1]
		var x0: float = x_at.call(f0)
		var x1: float = x_at.call(f1)
		for k in A:
			var on: bool = solid[jj][k]
			if lod:
				kit.color = face_col if on else Color(0.04, 0.04, 0.04)
			elif not on:
				continue
			else:
				kit.color = face_col
			var a0 := TAU * float(k) / float(A)
			var a1 := TAU * float(k + 1) / float(A)
			var d0 := _around(a0)
			var d1 := _around(a1)
			var n0 := (Vector3.RIGHT - d0 * slope).normalized()
			var n1 := (Vector3.RIGHT - d1 * slope).normalized()
			var p00 := Vector3(x0, 0, 0) + d0 * rr * f0
			var p01 := Vector3(x0, 0, 0) + d1 * rr * f0
			var p11 := Vector3(x1, 0, 0) + d1 * rr * f1
			var p10 := Vector3(x1, 0, 0) + d0 * rr * f1
			kit.quad_smooth(p00, p01, p11, p10, n0, n1, n1, n0, (n0 + n1).normalized())
			if lod:
				continue
			var back := Vector3(-sd, 0, 0)
			kit.color = face_col.darkened(0.25)
			if not solid[jj][(k - 1 + A) % A]:
				kit.quad(p00, p10, p10 + back, p00 + back, -Vector3(0, cos(a0), -sin(a0)))
			if not solid[jj][(k + 1) % A]:
				kit.quad(p01, p11, p11 + back, p01 + back, Vector3(0, cos(a1), -sin(a1)))
			if jj + 1 < solid.size() and not solid[jj + 1][k]:
				kit.quad(p10, p11, p11 + back, p10 + back, -(d0 + d1).normalized())
			if jj > 0 and not solid[jj - 1][k]:
				kit.quad(p00, p01, p01 + back, p00 + back, (d0 + d1).normalized())
	# Hub: a flat centre with lug nuts round a cap.
	var f_hub: float = fracs[fracs.size() - 1]
	var xh: float = x_at.call(f_hub)
	kit.color = face_col
	# Its edges reach the face's round edge (so no slivers of street show
	# between them), not cut inside it.
	var hub_n := 24 if not lod else 10
	_disc(kit, Vector3(xh, 0, 0), rr * f_hub / cos(PI / float(hub_n)), Vector3.RIGHT, hub_n)
	if lod:
		kit.color = cap_col
		_disc(kit, Vector3(xh + 0.006, 0, 0), rr * 0.13, Vector3.RIGHT, 8)
		return kit
	var lug_r := rr * f_hub * 0.66
	kit.color = Color(0.75, 0.76, 0.78)
	for i in lugs:
		var a := TAU * float(i) / float(lugs)
		var c := Vector3(xh, 0, 0) + _around(a) * lug_r
		_hex(kit, c, 0.0105, 0.014)
	kit.color = cap_col
	var cap_r := rr * f_hub * (0.38 if style != "steel6" else 0.45)
	_tube(kit, Vector3(xh, 0, 0), Vector3(xh + 0.012, 0, 0), cap_r, 16, false)
	_disc(kit, Vector3(xh + 0.012, 0, 0), cap_r, Vector3.RIGHT, 16)
	kit.color = Color(0.9, 0.9, 0.92) if style == "alloy10" else Color(0.1, 0.1, 0.12)
	_disc(kit, Vector3(xh + 0.0125, 0, 0), cap_r * 0.5, Vector3.RIGHT, 12)
	return kit


## A hex nut standing out of the wheel face along +X.
static func _hex(kit: MeshKit, c: Vector3, r: float, h: float) -> void:
	for i in 6:
		var a0 := TAU * float(i) / 6.0
		var a1 := TAU * float(i + 1) / 6.0
		var d0 := _around(a0) * r
		var d1 := _around(a1) * r
		kit.quad(c + d0, c + d1, c + d1 + Vector3(h, 0, 0), c + d0 + Vector3(h, 0, 0), _around((a0 + a1) * 0.5))
		kit.tri(c + Vector3(h, 0, 0), c + d0 + Vector3(h, 0, 0), c + d1 + Vector3(h, 0, 0), Vector3.RIGHT)


static func _brake_kits(r: float, width: float, style: String, caliper: Color, lod: bool) -> Array:
	var hw := width * 0.5
	var rf: float = RIM_FRAC.get(style, 0.66)
	var rr := r * rf
	var rough := MeshKit.new()
	rough.use_color = true
	var metal := MeshKit.new()
	metal.use_color = true
	var gloss := MeshKit.new()
	gloss.use_color = true
	# Dust shield: closes off the back of the wheel, so you see dark metal
	# through the spokes, not the street.
	rough.color = Color(0.035, 0.035, 0.035)
	_disc(rough, Vector3(-hw * 0.55, 0, 0), rr * 0.95, Vector3.RIGHT, 10 if lod else 24)
	if lod:
		return [rough, metal, gloss]
	var dish := 0.35 if style == "mag5" else (0.08 if style == "steel6" else 0.2)
	var xr := hw * 0.8 - 0.01 - dish * hw - 0.022 - 0.014
	# Disc: a machined ring on a darker hat, with an edge. Dull: it sits in
	# the wheel's shadow, and a bright one between the spokes reads as a hole.
	metal.color = Color(0.27, 0.27, 0.28)
	_ring(metal, Vector3(xr, 0, 0), rr * 0.4, rr * 0.8, Vector3.RIGHT, 28)
	metal.color = Color(0.21, 0.21, 0.22)
	_tube(metal, Vector3(xr - 0.022, 0, 0), Vector3(xr, 0, 0), rr * 0.8, 28, false)
	rough.color = Color(0.18, 0.18, 0.19)
	_disc(rough, Vector3(xr + 0.004, 0, 0), rr * 0.4, Vector3.RIGHT, 16)
	# Caliper over the back of the disc, up and toward the rear.
	var a := 0.75
	var radial := _around(a)
	var tangent := Vector3(0, cos(a), -sin(a))
	var basis := Basis(Vector3.RIGHT, radial, tangent)
	gloss.color = caliper
	_bbox(gloss, Vector3(xr - 0.006, 0, 0) + radial * rr * 0.68, Vector3(0.018, 0.036, 0.07), 0.012, basis)
	return [rough, metal, gloss]

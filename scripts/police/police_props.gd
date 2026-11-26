class_name PoliceProps
extends RefCounted
## The police's props, built in code to docs/models.md: each built once and
## shared (cached here), vertex colours on the shared car materials (one
## surface per material), shared vertices and automatic LODs
## (ModelLod.finish_kits), small repeated parts as flat quads.
##
##   vest_mesh()        the bright yellow OUT vest an officer pulls on when
##                      painted out, in the chest bone's space
##   strip_mesh()       a paint strip across the road (flat, no shadow)
##   harvester_mesh()   a potato harvester, for the level 4 roadblocks
##   cannon_mesh()      the Paint Tank's roof paint cannon (turret), and
##   barrel_mesh()      its barrel, which pitches
##
## `budget_meshes()` lists them for tools/model_budget.gd.

const VEST_YELLOW := Color(1.0, 0.86, 0.0)
const VEST_SILVER := Color(0.82, 0.84, 0.86)
const INK := Color(0.05, 0.05, 0.06)
const STRIP_ORANGE := Color(1.0, 0.36, 0.0)
const HARVESTER_RED := Color(0.72, 0.1, 0.08)
const HARVESTER_GREY := Color(0.62, 0.63, 0.6)
const STEEL := Color(0.45, 0.46, 0.47)
const GUNMETAL := Color(0.17, 0.18, 0.18)

## A strip's size (m): across the road, and along it.
const STRIP_LENGTH := 8.0
const STRIP_WIDTH := 1.4
## The harvester's footprint (m): length along its body, width, height.
const HARVESTER_SIZE := Vector3(3.3, 3.6, 9.0)

static var _cache := {}


## Every prop mesh, by name (for the budget check).
static func budget_meshes() -> Dictionary:
	return {"OUT vest": vest_mesh(), "paint strip": strip_mesh(), "potato harvester": harvester_mesh(),
		"paint cannon": cannon_mesh(), "paint cannon barrel": barrel_mesh(), "impound machine": kiosk_mesh()}


static func _kit() -> MeshKit:
	var k := MeshKit.new()
	k.use_color = true
	return k


# --- the OUT vest ---------------------------------------------------------------------------

## Letters as 3x5 blocks, '#' filled.
const _LETTERS := {
	"O": ["###", "#.#", "#.#", "#.#", "###"],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
}


## The vest, in the chest bone's space (the person faces -Z; the chest joint
## is 1.27 m up a 1.75 m person): a yellow tabard round the torso from the
## waist to the shoulders, two silver bands, shoulder straps and OUT in
## black on the front and the back.
static func vest_mesh() -> ArrayMesh:
	if _cache.has("vest"):
		return _cache["vest"]
	var kit := _kit()
	var y0 := -0.3
	var y1 := 0.14
	var rx := 0.215
	var rz := 0.155
	const SIDES := 10
	var ring := func(a: float, y: float) -> Vector3:
		return Vector3(sin(a) * rx, y, -cos(a) * rz)
	kit.color = VEST_YELLOW
	for i in SIDES:
		var a0 := TAU * float(i) / SIDES
		var a1 := TAU * float(i + 1) / SIDES
		var n := Vector3(sin((a0 + a1) * 0.5), 0, -cos((a0 + a1) * 0.5))
		kit.quad(ring.call(a0, y0), ring.call(a1, y0), ring.call(a1, y1), ring.call(a0, y1), n)
	# Over the shoulders: two straps from the front edge to the back edge.
	for s: float in [-1.0, 1.0]:
		var x0 := s * 0.08
		var x1 := s * 0.17
		var top := y1 + 0.09
		kit.quad(Vector3(x0, y1, -rz * 0.85), Vector3(x1, y1, -rz * 0.8), Vector3(x1, top, -0.02), Vector3(x0, top, -0.03), Vector3(0, 0.6, -0.8))
		kit.quad(Vector3(x0, top, -0.03), Vector3(x1, top, -0.02), Vector3(x1, y1, rz * 0.8), Vector3(x0, y1, rz * 0.85), Vector3(0, 0.6, 0.8))
	# Two reflective bands round it.
	kit.color = VEST_SILVER
	for yb: float in [-0.25, -0.16]:
		for i in SIDES:
			var a0 := TAU * float(i) / SIDES
			var a1 := TAU * float(i + 1) / SIDES
			var n := Vector3(sin((a0 + a1) * 0.5), 0, -cos((a0 + a1) * 0.5))
			var g := 1.012
			kit.quad(ring.call(a0, yb) * Vector3(g, 1, g), ring.call(a1, yb) * Vector3(g, 1, g),
				ring.call(a1, yb + 0.035) * Vector3(g, 1, g), ring.call(a0, yb + 0.035) * Vector3(g, 1, g), n)
	# OUT, front and back.
	kit.color = INK
	for back: bool in [false, true]:
		_word(kit, "OUT", Vector3(0, -0.02, (rz + 0.006) * (1.0 if back else -1.0)), 0.026, back)
	var mesh := ModelLod.finish_kits([[kit, CarBuilder.material("rough")]])
	_cache["vest"] = mesh
	return mesh


## Block letters centred at `c` on a flat face facing -Z (or +Z for the
## back, read the right way round from behind), each cell `cell` m.
static func _word(kit: MeshKit, word: String, c: Vector3, cell: float, back: bool) -> void:
	var n := Vector3(0, 0, 1 if back else -1)
	var letter_w := cell * 3.0
	var gap := cell * 0.8
	var total := letter_w * word.length() + gap * (word.length() - 1)
	# Read from in front (looking +Z) a viewer's right is -X; from behind
	# (looking -Z), +X. The letters are symmetric, so only their order turns.
	var dir := 1.0 if back else -1.0
	var x := -total * 0.5
	for ch in word:
		var rows: Array = _LETTERS.get(ch, [])
		for r in rows.size():
			var row: String = rows[r]
			var col := 0
			while col < 3:
				if row[col] != "#":
					col += 1
					continue
				var run := col
				while run < 3 and row[run] == "#":
					run += 1
				var xa := (x + col * cell) * dir
				var xb := (x + run * cell) * dir
				var yt := c.y + cell * 2.5 - r * cell
				kit.quad(Vector3(xa, yt - cell, c.z), Vector3(xb, yt - cell, c.z), Vector3(xb, yt, c.z), Vector3(xa, yt, c.z), n)
				col = run
		x += letter_w + gap


# --- the paint strip ------------------------------------------------------------------------

## A strip of slick evidence paint across a road: orange bars with dark
## gaps, flat on the ground, centred on the origin, across X, along Z.
static func strip_mesh() -> ArrayMesh:
	if _cache.has("strip"):
		return _cache["strip"]
	var kit := _kit()
	var n := Vector3.UP
	var hw := STRIP_LENGTH * 0.5
	var hz := STRIP_WIDTH * 0.5
	const BARS := 12
	for i in BARS:
		var x0 := lerpf(-hw, hw, float(i) / BARS)
		var x1 := lerpf(-hw, hw, float(i + 1) / BARS)
		kit.color = STRIP_ORANGE if i % 2 == 0 else STRIP_ORANGE.darkened(0.35)
		# Slanted bars, like hazard paint.
		kit.quad(Vector3(x0, 0, hz), Vector3(x1, 0, hz), Vector3(x1 + 0.35, 0, -hz), Vector3(x0 + 0.35, 0, -hz), n)
	var mesh := kit.commit_indexed(null, CarBuilder.material("gloss"))
	_cache["strip"] = mesh
	return mesh


# --- the potato harvester -------------------------------------------------------------------

## A trailed two-row potato harvester (our own, red with a grey elevator):
## a drawbar at the front (-Z), the digger and the long elevator boom on
## the right, a big bunker at the back, four big tyres. Origin on the
## ground under its middle. "Red Clay Spud Co." is on its flanks
## (PoliceRoadblock adds the label).
static func harvester_mesh() -> ArrayMesh:
	if _cache.has("harvester"):
		return _cache["harvester"]
	var paint := _kit()
	var rough := _kit()
	var metal := _kit()
	var L := HARVESTER_SIZE.z
	var W := HARVESTER_SIZE.x
	# The chassis and the main body.
	TruckBuilder.box(paint, Vector3(0, 1.25, 0.4), Vector3(W * 0.82, 1.1, L * 0.7), HARVESTER_RED)
	# The bunker on top at the back, flaring out.
	TruckBuilder.box(paint, Vector3(0, 2.45, 1.6), Vector3(W * 0.95, 1.3, L * 0.42), HARVESTER_RED)
	TruckBuilder.box(metal, Vector3(0, 3.14, 1.6), Vector3(W * 0.97, 0.08, L * 0.44), HARVESTER_GREY)
	# The digger at the front, low, and the drawbar to the tractor.
	TruckBuilder.box(metal, Vector3(0, 0.55, -L * 0.36), Vector3(W * 0.7, 0.5, 1.2), HARVESTER_GREY)
	TruckBuilder.box(metal, Vector3(0, 0.6, -L * 0.36 - 1.4), Vector3(0.22, 0.2, 2.2), STEEL)
	TruckBuilder.cylinder(metal, Vector3(0, 0.6, -L * 0.5 - 0.1), Vector3(0, 0.9, -L * 0.5 - 0.1), 0.06, STEEL, 8)
	# The elevator boom: up from the digger along the right side, rails and
	# cross bars (flat quads, not boxes: rule 7).
	var b0 := Vector3(W * 0.5 + 0.15, 1.0, -L * 0.25)
	var b1 := Vector3(W * 0.5 + 0.15, 3.3, L * 0.2)
	for dx: float in [-0.25, 0.25]:
		TruckBuilder.cylinder(metal, b0 + Vector3(dx, 0, 0), b1 + Vector3(dx, 0, 0), 0.05, HARVESTER_GREY, 8)
	metal.color = HARVESTER_GREY.darkened(0.3)
	var along := (b1 - b0)
	var bars := 12
	for i in bars:
		var p := b0 + along * (float(i) + 0.5) / bars
		var f := along.normalized() * 0.06
		metal.quad(p + Vector3(-0.25, 0, 0) - f, p + Vector3(0.25, 0, 0) - f, p + Vector3(0.25, 0, 0) + f, p + Vector3(-0.25, 0, 0) + f, Vector3.UP)
	# Ladders and a rail round the bunker top.
	for s: float in [-1.0, 1.0]:
		TruckBuilder.cylinder(metal, Vector3(s * W * 0.47, 3.18, 1.6 - L * 0.21), Vector3(s * W * 0.47, 3.18, 1.6 + L * 0.21), 0.03, STEEL, 6)
	# Side panels a lighter red, and white chevrons at the back.
	paint.color = HARVESTER_RED.lightened(0.15)
	for s: float in [-1.0, 1.0]:
		var x := s * (W * 0.41 + 0.004)
		paint.quad(Vector3(x, 0.8, -1.8), Vector3(x, 0.8, 2.6), Vector3(x, 1.7, 2.6), Vector3(x, 1.7, -1.8), Vector3(s, 0, 0))
	paint.color = Color(0.95, 0.95, 0.93)
	for i in 4:
		var x := lerpf(-W * 0.4, W * 0.4, (float(i) + 0.5) / 4.0)
		var z := 0.4 + L * 0.35 + 0.004
		paint.quad(Vector3(x - 0.18, 0.75, z), Vector3(x, 0.75, z), Vector3(x + 0.18, 1.35, z), Vector3(x, 1.35, z), Vector3(0, 0, 1))
	# Four big wheels: the cars' tyre and steel wheel, in their simpler
	# version (a prop seen from a car, never close up), mirrored on the left
	# so the hubs face out.
	var tyre := CarBuilder._tyre_kit(0.72, 0.56, "steel6", true)
	var rim := CarBuilder._rim_kit(0.72, 0.56, "steel6", true)
	for z: float in [0.6, 2.0]:
		for s: float in [-1.0, 1.0]:
			var xf := Transform3D(Basis.IDENTITY, Vector3(s * (W * 0.5 - 0.25), 0.72, z))
			CarBuilder._append(rough, tyre, xf, s < 0.0)
			CarBuilder._append(metal, rim, xf, s < 0.0)
	var mesh := ModelLod.finish_kits([[paint, CarBuilder.material("gloss")], [rough, CarBuilder.material("rough")], [metal, CarBuilder.material("metal")]])
	_cache["harvester"] = mesh
	return mesh


# --- the Paint Tank's cannon ----------------------------------------------------------------

## The turret, in its own space (origin on the roof, the gun pointing -Z):
## a ring, a squat armoured housing, a big orange paint drum behind it.
static func cannon_mesh() -> ArrayMesh:
	if _cache.has("cannon"):
		return _cache["cannon"]
	var paint := _kit()
	var metal := _kit()
	TruckBuilder.cylinder(metal, Vector3(0, 0, 0), Vector3(0, 0.12, 0), 0.62, GUNMETAL, 16)
	TruckBuilder.box(paint, Vector3(0, 0.36, -0.05), Vector3(0.95, 0.44, 1.0), GUNMETAL.lightened(0.1))
	TruckBuilder.box(paint, Vector3(0, 0.36, -0.6), Vector3(0.7, 0.36, 0.14), GUNMETAL)
	# The paint drum (Evidence Paint orange) and its feed pipe.
	TruckBuilder.cylinder(paint, Vector3(-0.3, 0.6, 0.55), Vector3(0.3, 0.6, 0.55), 0.32, STRIP_ORANGE, 14)
	TruckBuilder.cylinder(metal, Vector3(0, 0.45, 0.45), Vector3(0, 0.45, 0.05), 0.06, STEEL, 8)
	# Grab rails and a little hazard placard.
	for s: float in [-1.0, 1.0]:
		TruckBuilder.cylinder(metal, Vector3(s * 0.5, 0.62, -0.4), Vector3(s * 0.5, 0.62, 0.3), 0.025, STEEL, 6)
	paint.color = Color(0.95, 0.95, 0.9)
	paint.quad(Vector3(0.476, 0.25, -0.3), Vector3(0.476, 0.25, 0.1), Vector3(0.476, 0.48, 0.1), Vector3(0.476, 0.48, -0.3), Vector3.RIGHT)
	var mesh := ModelLod.finish_kits([[paint, CarBuilder.material("gloss")], [metal, CarBuilder.material("metal")]])
	_cache["cannon"] = mesh
	return mesh


## The barrel, in its own space (the trunnion at the origin, -Z out).
static func barrel_mesh() -> ArrayMesh:
	if _cache.has("barrel"):
		return _cache["barrel"]
	var metal := _kit()
	TruckBuilder.cylinder(metal, Vector3(0, 0, 0.1), Vector3(0, 0, -1.5), 0.1, GUNMETAL, 12)
	TruckBuilder.cylinder(metal, Vector3(0, 0, -1.4), Vector3(0, 0, -1.62), 0.15, STRIP_ORANGE.darkened(0.2), 12)
	TruckBuilder.cylinder(metal, Vector3(-0.14, 0, 0), Vector3(0.14, 0, 0), 0.12, GUNMETAL, 10)
	var mesh := ModelLod.finish_kits([[metal, CarBuilder.material("metal")]])
	_cache["barrel"] = mesh
	return mesh


# --- the impound lot's pay machine ----------------------------------------------------------

## A pay machine on a post with a sign board above it (ImpoundLot), facing -Z.
static func kiosk_mesh() -> ArrayMesh:
	if _cache.has("kiosk"):
		return _cache["kiosk"]
	var paint := _kit()
	var metal := _kit()
	TruckBuilder.box(paint, Vector3(0, 0.75, 0), Vector3(0.55, 1.5, 0.4), Color(0.16, 0.24, 0.42))
	TruckBuilder.box(metal, Vector3(0, 1.15, -0.205), Vector3(0.32, 0.22, 0.01), Color(0.1, 0.12, 0.1))
	TruckBuilder.box(metal, Vector3(0, 0.8, -0.205), Vector3(0.2, 0.05, 0.02), STEEL)
	TruckBuilder.cylinder(metal, Vector3(0.45, 0, 0.1), Vector3(0.45, 2.6, 0.1), 0.04, STEEL, 8)
	TruckBuilder.box(paint, Vector3(0, 2.25, 0.1), Vector3(1.6, 0.62, 0.05), Color(0.62, 0.08, 0.08))
	var mesh := ModelLod.finish_kits([[paint, CarBuilder.material("gloss")], [metal, CarBuilder.material("metal")]])
	_cache["kiosk"] = mesh
	return mesh

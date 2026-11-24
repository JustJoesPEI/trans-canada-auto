class_name PaintCoverage
extends Node
## The paint on one car (docs/design.md section 3, "Cars", and section 7,
## "What police paint does to your car"). A child of the Car, made the first
## time it's hit (`PaintCoverage.of(car)`).
##
## It keeps the last 32 hits in the car's own space (where, which way the
## surface faced, colour, size): that's the car's paint, and all a server
## would need to send. Coverage comes from 24 panels made by cutting the
## car's box up: the top (bonnet, windscreen, roof, boot) in 6 along its
## length, each side in 6, the front and the back in 3 across. Each hit
## fills its panel by its area (one paintball fills a third of a panel; a
## Jam Jar or a paint bomb fills a lot more), what spills over a full panel
## goes to the nearest one that isn't, and coverage is the average. So
## coverage is the share of the car that's been painted however the hits
## land, and keeps counting after the 32 drawn hits have been replaced.
##
## Police paint ("FIP-issue Evidence Paint") is counted on its own
## (`police_coverage`), and that is what gums the car up:
##   50% and up   spotting_factor 2 (the police can spot it twice as far)
##   80% and up   power_factor 2/3, with the odd cough (Car's drive force)
##   100%         stalled
## Player paint only paints (it still counts toward `coverage`, which the
## Escort event and delivery tips use). Hits from the player on a police
## car count as police paint too: the passenger painting them back, by the
## same table.
##
## How it's drawn, and why this way: the car's materials are shared by every
## car of that finish (CarBuilder), so the hits can't go into them without
## a material per car for every car in town. Instead a painted car gets a
## material overlay (GeometryInstance3D.material_overlay) on its body: one
## small ShaderMaterial of its own, shaders/paint_overlay.gdshader, with the
## 32 hits as uniform arrays, drawing each as a splat shape in the body
## mesh's own space. The shared materials and cached meshes stay exactly as
## they are; a car with no paint has no overlay and costs nothing; a painted
## one draws its body once more (a pass per surface, all fragments outside a
## splat discarded). It works on every renderer (no Decal nodes, which the
## Compatibility renderer doesn't draw) and on Low. Decals were also out
## because each is a node with its own cost per hit.
##
## The windscreen: hits on it are also kept as smears (`screen`) in the
## windscreen's own -1..1 x 0..1 space, which the HUD draws over the
## driver's view (WindscreenSmear). `wipe()` runs the wipers: the first
## sweep smears them thin, the second clears them.

## Coverage went up (or was cleared), 0..1.
signal changed(coverage: float)
## A hit landed on the windscreen at `uv` (x -1..1 left to right, y 0..1
## bottom to top).
signal windscreen_hit(uv: Vector2, colour: Color, size: float)

const MAX_HITS := 32 ## design section 3
const PANELS := 24 ## design section 3
## m: the radius of one paintball's splat on a car (not in the design).
const BALL_SIZE := 0.16
## How much of a panel one paintball fills. Not in the design: a third, so
## about 72 balls spread round a car cover it (an officer firing 5 a second
## needs 15 s of hits; three of them, about 5 s).
const BALL_FILL := 1.0 / 3.0
## Police coverage thresholds (design section 7).
const SPOTTED_AT := 0.5
const COUGH_AT := 0.8
const STALL_AT := 0.999 ## 100%, less a rounding error
## Engine power and acceleration down by a third from 80% (design).
const GUMMED_POWER := 2.0 / 3.0
## The cough (not in the design): every 2 to 5 s the engine loses most of
## its power for a moment.
const COUGH_POWER := 0.2
const COUGH_TIME := 0.35
## Windscreen smears drawn at once.
const MAX_SMEARS := 12
## m: the overlay is drawn only within this of the camera. Past it a
## splat is under a pixel or two and the extra pass over the body would be
## wasted (design: a painted truck reads as lit up from 100 m).
## tools/model_budget.gd counts the pass up close, not far away.
const OVERLAY_RANGE := 150.0
## s between checks of the camera's distance.
const RANGE_CHECK := 0.25
## s for each sweep of the wipers.
const SWEEP_TIME := 0.45

static var _shader: Shader

var car: Node3D
## 0..1, how much of the car is painted (all paint).
var coverage := 0.0
## 0..1, how much of it is police paint (what gums the car up).
var police_coverage := 0.0
## How much further the police can spot this car (1, or 2 from 50% police
## paint). The Wanted and Police pieces read it.
var spotting_factor := 1.0
## The hits drawn: {point, normal, colour, size, shape, turn, born (on
## PaintSplats.clock, for the drips)}, car space, oldest first.
var hits: Array[Dictionary] = []
## Paint on the windscreen: {uv, colour, size, strength}.
var screen: Array[Dictionary] = []
## The wipers: -1 parked, else 0..2 through the two sweeps.
var wiper := -1.0

var _fill := PackedFloat32Array()
var _police := PackedFloat32Array()
var _centres: Array[Vector3] = []
var _box := AABB(Vector3(-0.9, 0.0, -2.2), Vector3(1.8, 1.5, 4.4))
var _material: ShaderMaterial
var _overlaid: MeshInstance3D
var _far := false ## past OVERLAY_RANGE: overlay off
var _range_check := 0.0
var _cough_in := 3.0
var _cough_left := 0.0
var _rng := RandomNumberGenerator.new()


## The car's paint, made on the first hit.
static func of(target: Node3D) -> PaintCoverage:
	var pc := target.get_node_or_null("PaintCoverage") as PaintCoverage
	if pc == null:
		pc = PaintCoverage.new()
		pc.name = "PaintCoverage"
		target.add_child(pc)
	return pc


## The share of the car one hit of `size` (m) fills; and back again.
static func fill_for_size(size: float) -> float:
	return BALL_FILL * pow(size / BALL_SIZE, 2.0) / float(PANELS)


static func size_for_fill(share: float) -> float:
	return BALL_SIZE * sqrt(share * float(PANELS) / BALL_FILL)


func _init() -> void:
	_fill.resize(PANELS)
	_police.resize(PANELS)
	_rng.randomize()


func _ready() -> void:
	car = get_parent() as Node3D
	var mi := _body_mesh()
	if mi != null and mi.mesh != null:
		var to_car := _mesh_to_car(mi)
		_box = to_car * mi.mesh.get_aabb()
	_make_centres()
	set_process(false)


## A hit at `local_point` (car space), `size` metres across in radius.
## `police`: FIP evidence paint (or anyone's paint on a police car), which
## counts toward the coverage table. `local_normal`: which way the surface
## faced there, if known (else it's worked out from the car's box): it
## picks the panel. `local_from`: the way the paint came from (back along
## the ball's flight), if known (else the normal): it's drawn projected
## along it, and it's what finds the windscreen.
func add_hit(local_point: Vector3, colour: Color, size: float, police: bool, local_normal := Vector3.ZERO, local_from := Vector3.ZERO) -> void:
	if local_normal.length_squared() < 0.0001:
		local_normal = _box_normal(local_point)
	local_normal = local_normal.normalized()
	local_from = local_normal if local_from.length_squared() < 0.0001 else local_from.normalized()
	hits.append({"point": local_point, "normal": local_from, "colour": colour, "size": size,
		"shape": _rng.randi() % PaintTexture.SHAPES, "turn": _rng.randf() * TAU, "born": PaintSplats.clock})
	while hits.size() > MAX_HITS:
		hits.pop_front()
	var amount := fill_for_size(size) * float(PANELS)
	var panel := panel_of(local_point, local_normal)
	_pour(_fill, panel, amount)
	if police:
		_pour(_police, panel, amount)
	_update_coverage()
	_check_windscreen(local_point, -local_from, colour, size)
	_draw()
	changed.emit(coverage)


## A splash's worth of coverage (`share` of the car, e.g. 0.15 for a Jam
## Jar) centred on `local_point`: one big splat.
func add_coverage(share: float, local_point: Vector3, colour: Color, police: bool, local_normal := Vector3.ZERO, local_from := Vector3.ZERO) -> void:
	add_hit(local_point, colour, size_for_fill(share), police, local_normal, local_from)


## Draw the hits again (after changing one, e.g. its landing time).
func redraw() -> void:
	_draw()


## The car wash: all paint off, the engine runs again.
func clear() -> void:
	hits.clear()
	screen.clear()
	_fill.fill(0.0)
	_police.fill(0.0)
	_update_coverage()
	_draw()
	changed.emit(coverage)


## Run the wipers: two sweeps clear the windscreen.
func wipe() -> void:
	if wiper < 0.0:
		wiper = 0.0
		set_process(true)


## Which of the 24 panels a point (and the way the surface faces there) is on.
func panel_of(p: Vector3, n: Vector3) -> int:
	var lo := _box.position
	var size := _box.size
	var along := clampf((p.z - lo.z) / maxf(size.z, 0.01), 0.0, 0.9999)
	var across := clampf((p.x - lo.x) / maxf(size.x, 0.01), 0.0, 0.9999)
	var a := n.abs()
	if n.y > 0.5:
		return int(along * 6.0) # the top: bonnet to boot
	if a.x >= a.z:
		return (6 if n.x < 0.0 else 12) + int(along * 6.0) # left, right
	return (18 if n.z < 0.0 else 21) + int(across * 3.0) # front, back


## A panel's fill, 0..1 (for checks and a future paint-shop screen).
func panel_fill(i: int) -> float:
	return _fill[i]


func _process(delta: float) -> void:
	var busy := not hits.is_empty() # the overlay's draw range
	if busy:
		_range_check -= delta
		if _range_check <= 0.0:
			_range_check = RANGE_CHECK
			_check_range()
	if wiper >= 0.0:
		busy = true
		var before := wiper
		wiper += delta / SWEEP_TIME
		_wipe_between(before, minf(wiper, 2.0))
		if wiper >= 2.0:
			wiper = -1.0
			var left: Array[Dictionary] = []
			for s in screen:
				if float(s["strength"]) > 0.02:
					left.append(s)
			screen = left
	if police_coverage >= COUGH_AT and police_coverage < STALL_AT:
		busy = true
		if _cough_left > 0.0:
			_cough_left -= delta
		else:
			_cough_in -= delta
			if _cough_in <= 0.0:
				_cough_left = COUGH_TIME
				_cough_in = _rng.randf_range(2.0, 5.0)
		_set_car("power_factor", COUGH_POWER if _cough_left > 0.0 else GUMMED_POWER)
	set_process(busy)


## Where the wiper blade is across the windscreen (-1..1), or NAN parked.
func wiper_x() -> float:
	if wiper < 0.0:
		return NAN
	return lerpf(-1.0, 1.0, wiper) if wiper <= 1.0 else lerpf(1.0, -1.0, wiper - 1.0)


## The blade went from phase `a` to `b`: everything it passed over is
## smeared (first sweep) or cleared (second).
func _wipe_between(a: float, b: float) -> void:
	for s in screen:
		var x := (s["uv"] as Vector2).x
		for sweep in 2:
			var lo := float(sweep)
			var hi := lo + 1.0
			var pa := clampf(a, lo, hi) - lo
			var pb := clampf(b, lo, hi) - lo
			if pb <= pa:
				continue
			var xa := lerpf(-1.0, 1.0, pa) if sweep == 0 else lerpf(1.0, -1.0, pa)
			var xb := lerpf(-1.0, 1.0, pb) if sweep == 0 else lerpf(1.0, -1.0, pb)
			if x >= minf(xa, xb) - 0.05 and x <= maxf(xa, xb) + 0.05:
				s["strength"] = float(s["strength"]) * (0.35 if sweep == 0 else 0.0)
				if sweep == 0:
					s["size"] = float(s["size"]) * 1.4 # smeared out


func _pour(fills: PackedFloat32Array, panel: int, amount: float) -> void:
	var left := amount
	var room := minf(left, 1.0 - fills[panel])
	fills[panel] += room
	left -= room
	while left > 0.0001:
		# The nearest panel that isn't full.
		var best := -1
		var best_d := INF
		for i in PANELS:
			if fills[i] >= 0.9999:
				continue
			var d := _centres[i].distance_squared_to(_centres[panel])
			if d < best_d:
				best_d = d
				best = i
		if best < 0:
			return
		room = minf(left, 1.0 - fills[best])
		fills[best] += room
		left -= room


func _update_coverage() -> void:
	var all := 0.0
	var pol := 0.0
	for i in PANELS:
		all += _fill[i]
		pol += _police[i]
	coverage = clampf(all / float(PANELS), 0.0, 1.0)
	police_coverage = clampf(pol / float(PANELS), 0.0, 1.0)
	spotting_factor = 2.0 if police_coverage >= SPOTTED_AT else 1.0
	if police_coverage >= STALL_AT:
		_set_car("stalled", true)
		_set_car("power_factor", 0.0)
	elif police_coverage >= COUGH_AT:
		_set_car("stalled", false)
		_set_car("power_factor", GUMMED_POWER)
		set_process(true)
	else:
		_set_car("stalled", false)
		_set_car("power_factor", 1.0)


func _set_car(prop: String, value: Variant) -> void:
	if car != null and prop in car:
		car.set(prop, value)


## Did the paint, going `dir` through `p` (car space), meet the windscreen?
## The hit is on the collision box, so it's carried on along its way to the
## glass (the windscreen quad CarBuilder builds from the shape's "cabin").
func _check_windscreen(p: Vector3, dir: Vector3, colour: Color, size: float) -> void:
	if car == null or not "shape" in car:
		return
	var shape: Dictionary = car.get("shape")
	if not shape.has("cabin"):
		return
	var cab: Dictionary = shape["cabin"]
	var belt := float(cab["belt"])
	var roof := float(cab["roof"])
	var za := float(cab["za"])
	var zb := float(cab["zb"])
	var wn := Vector3(0.0, zb - za, -(roof - belt)).normalized() # out of the glass, forward and up
	var facing := dir.dot(wn)
	if facing > -0.05:
		return # going along it or away from it: not into the windscreen
	var s := (Vector3(0.0, belt, za) - p).dot(wn) / facing
	if s < -0.3 or s > 1.2:
		return # the glass is too far behind (or in front of) where it hit
	p += dir * s
	var t := (p.y - belt) / maxf(0.05, roof - belt)
	if t < 0.0 or t > 1.0:
		return
	var half := lerpf(float(cab["wb"]), float(cab["wr"]), t)
	if absf(p.x) > half:
		return
	var uv := Vector2(p.x / half, t)
	screen.append({"uv": uv, "colour": colour, "size": size, "strength": 1.0})
	while screen.size() > MAX_SMEARS:
		screen.pop_front()
	windscreen_hit.emit(uv, colour, size)


## The overlay on the car's body: made on the first hit, dropped when clean.
func _draw() -> void:
	var mi := _body_mesh()
	if mi == null:
		return
	if hits.is_empty():
		if _overlaid != null and is_instance_valid(_overlaid):
			_overlaid.material_overlay = null
		_overlaid = null
		return
	if _material == null:
		_material = new_overlay_material()
	set_process(true) # the overlay's draw range
	var to_mesh := _mesh_to_car(mi).affine_inverse()
	var pos := PackedVector4Array()
	var nrm := PackedVector4Array()
	var col := PackedVector4Array()
	var born := PackedFloat32Array()
	born.resize(PaintCoverage.MAX_HITS)
	born.fill(-1000.0)
	pos.resize(MAX_HITS)
	nrm.resize(MAX_HITS)
	col.resize(MAX_HITS)
	for i in hits.size():
		var h := hits[i]
		var p: Vector3 = to_mesh * (h["point"] as Vector3)
		var n: Vector3 = (to_mesh.basis * (h["normal"] as Vector3)).normalized()
		var c: Color = h["colour"]
		pos[i] = Vector4(p.x, p.y, p.z, float(h["size"]))
		nrm[i] = Vector4(n.x, n.y, n.z, float(h["shape"]))
		col[i] = Vector4(c.r, c.g, c.b, float(h["turn"]))
		born[i] = float(h.get("born", -1000.0))
	_material.set_shader_parameter("hit_pos", pos)
	_material.set_shader_parameter("hit_nrm", nrm)
	_material.set_shader_parameter("hit_col", col)
	_material.set_shader_parameter("hit_born", born)
	_material.set_shader_parameter("hit_count", hits.size())
	_overlaid = mi
	mi.set_meta("paint_range", OVERLAY_RANGE)
	_check_range()


## Overlay on within OVERLAY_RANGE of the camera, off past it.
func _check_range() -> void:
	if _overlaid == null or not is_instance_valid(_overlaid) or hits.is_empty():
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_far = cam != null and car != null and cam.global_position.distance_squared_to(car.global_position) > OVERLAY_RANGE * OVERLAY_RANGE
	var want: Material = null if _far else _material
	if _overlaid.material_overlay != want:
		_overlaid.material_overlay = want


## A fresh overlay material (one per painted car or person; the shader is shared).
static func new_overlay_material(rest_space := false) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://shaders/paint_overlay.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("splat_tex", PaintTexture.texture())
	m.set_shader_parameter("rest_space", rest_space)
	return m


func _body_mesh() -> MeshInstance3D:
	if car == null:
		return null
	var mi: Variant = car.get("body_mesh")
	return mi as MeshInstance3D if mi is MeshInstance3D else null


## The body mesh's space in the car's space (it's on the car's body node).
func _mesh_to_car(mi: MeshInstance3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != car:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Which way the car's box faces nearest a point.
func _box_normal(p: Vector3) -> Vector3:
	var c := _box.get_center()
	var h := _box.size * 0.5
	var d := p - c
	var r := Vector3(d.x / maxf(h.x, 0.01), d.y / maxf(h.y, 0.01) if d.y > 0.0 else -1.0, d.z / maxf(h.z, 0.01))
	var a := r.abs()
	if a.y >= a.x and a.y >= a.z:
		return Vector3.UP
	if a.x >= a.z:
		return Vector3(signf(d.x), 0.0, 0.0)
	return Vector3(0.0, 0.0, signf(d.z))


func _make_centres() -> void:
	_centres.clear()
	var lo := _box.position
	var s := _box.size
	for i in 6:
		_centres.append(Vector3(lo.x + s.x * 0.5, lo.y + s.y, lo.z + s.z * (i + 0.5) / 6.0))
	for side in 2:
		for i in 6:
			_centres.append(Vector3(lo.x + s.x * side, lo.y + s.y * 0.5, lo.z + s.z * (i + 0.5) / 6.0))
	for end in 2:
		for i in 3:
			_centres.append(Vector3(lo.x + s.x * (i + 0.5) / 3.0, lo.y + s.y * 0.5, lo.z + s.z * end))

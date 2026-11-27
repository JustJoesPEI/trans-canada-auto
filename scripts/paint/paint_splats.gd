class_name PaintSplats
extends MultiMeshInstance3D
## Paint on walls, the ground and props (docs/design.md section 3): flat
## quads (two triangles each) in one pooled MultiMesh, laid on the surface
## the ball hit, with the shapes from PaintTexture. The cheap flat quads for
## repeated features of docs/world_art.md: one draw call for every splat in
## town, no shadows, one shared material.
##
## The pool holds as many as the graphics setting allows (High 4000,
## Medium 2000, Low 800); when it's full the oldest goes first. Each lasts
## 20 minutes and fades out over the last 2, in the shader (the landing
## time is in the instance's custom data, so nothing is touched per frame).
##
## Splats never float or flicker: each sits SURFACE_OFFSET off the surface
## and the shader pulls it a little toward the camera; one that would hang
## over an edge (a curb, the corner of a wall) is shrunk until it fits, or
## dropped.

## Fresh paint runs (design section 3, "Drips"): done in the shaders
## (shaders/paint_drips.gdshaderinc), which take each splat's landing time
## and `paint_now`, a global shader uniform this sets once a frame from
## `clock`. A wall splat's quad is laid with its y axis pointing downhill, and
## its custom data says how far the paint may run there (`drip_room`: none
## on the flat or where the surface ends just below it). Cars and people use
## the same clock for their hits (PaintCoverage, BodyPaint).

## Pool size per graphics level (design section 3).
const CAPS := {"HIGH": 4000, "MEDIUM": 2000, "LOW": 800}
const LIFE := 1200.0 ## s (design: 20 min)
const FADE := 120.0 ## s, fading over the last 2 min (design)
## m off the surface along its normal. Not in the design: one centimetre
## clears the texture relief of brick and paving without looking stuck on.
const SURFACE_OFFSET := 0.012
## m: past this they fade out (a 16 cm splat is a couple of pixels there).
const FAR := 90.0
## A corner more than this far off the hit surface means the splat would
## hang off an edge.
const FIT_TOLERANCE := 0.04
## How far below its middle a splat's longest drip can reach, in splat
## radii (matches DRIP_LEN in paint_drips.gdshaderinc).
const DRIP_LEN := 1.2
## s that drips run (design: 20 s; DRIP_TIME in the shader).
const DRIP_TIME := 20.0

## Seconds of play (it stops while the game is paused), the time every
## splat, car hit and body hit is stamped with. Advanced by one pool (the
## first made) and sent to the shaders as `paint_now`.
static var clock := 0.0
static var _ticker: PaintSplats

static var _material: ShaderMaterial
static var _quad: ArrayMesh

## How many splats the pool holds now.
var cap := 0
## How many are showing.
var count := 0

var _next := 0 ## slot the next splat goes in
var _born: PackedFloat32Array = PackedFloat32Array()
## What each slot holds, kept here as well as in the MultiMesh (the
## renderer's copy can't be read back cheaply): for a resize and for checks.
var _xforms: Array[Transform3D] = []
var _colours := PackedColorArray()
var _customs := PackedColorArray() ## (shape, born, turn, drip room)
var _check := 0.0
var _probe := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "PaintSplats"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# One pool for the whole town: never culled by its box (it's always
	# somewhere near; two triangles a splat costs nothing off screen).
	custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))
	material_override = shared_material()
	_probe.collision_mask = Layers.GROUND | Layers.SOLID
	_rng.randomize()
	if _ticker == null or not is_instance_valid(_ticker):
		_ticker = self
	_resize(cap_for_level())


func _exit_tree() -> void:
	if _ticker == self:
		_ticker = null


func _process(delta: float) -> void:
	if _ticker == null or not is_instance_valid(_ticker):
		_ticker = self
	if _ticker == self:
		clock += delta
		RenderingServer.global_shader_parameter_set("paint_now", clock)
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var want := cap_for_level()
	if want != cap:
		_resize(want)
	_expire()


## The pool size for the graphics setting now.
static func cap_for_level() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var gfx: Node = tree.root.get_node_or_null("Graphics") if tree != null else null
	if gfx == null:
		return CAPS["HIGH"]
	var names: Array = gfx.get("Level").keys()
	return int(CAPS.get(str(names[int(gfx.get("level"))]), CAPS["HIGH"]))


## Lay a splat on the surface at `point` facing `normal`, `size` metres in
## radius, in `colour`. Shrinks it to fit the surface (or skips it, on an
## edge too sharp for even a small one). Returns whether one was laid.
func add(point: Vector3, normal: Vector3, colour: Color, size: float, shape := -1, exclude: Array[RID] = []) -> bool:
	if cap <= 0:
		return false
	normal = normal.normalized()
	# x across, y down the surface (n x (n x up) is downhill); the shape's
	# own turn is in the custom data, so the drips still run down.
	var tangent := normal.cross(Vector3.UP if absf(normal.y) < 0.95 else Vector3.RIGHT).normalized()
	var bitangent := normal.cross(tangent)
	size = _fit(point, normal, tangent, bitangent, size, exclude)
	if size <= 0.0:
		return false
	var xf := Transform3D(Basis(tangent * size, bitangent * size, normal), point + normal * SURFACE_OFFSET)
	var room := drip_room(point, normal, bitangent, size, exclude)
	_place(xf, colour, Color(float(shape if shape >= 0 else _rng.randi() % PaintTexture.SHAPES), clock, _rng.randf() * TAU, room))
	return true


## How far fresh paint here may run (0..1 of DRIP_LEN): all the way on a
## wall, less on a slope, none on the flat; none if the surface doesn't go
## on under it (the top of a curb, a ledge), so a drip never hangs in the
## air.
func drip_room(point: Vector3, normal: Vector3, down: Vector3, size: float, exclude: Array[RID] = []) -> float:
	var room := clampf((0.85 - absf(normal.y)) / 0.5, 0.0, 1.0)
	if room <= 0.0 or not is_inside_tree():
		return room
	var space := get_world_3d().direct_space_state
	_probe.exclude = exclude
	var end := point + down * size * (DRIP_LEN + 0.55)
	_probe.from = end + normal * 0.08
	_probe.to = end - normal * 0.08
	var hit := space.intersect_ray(_probe)
	if hit.is_empty() or absf((hit["position"] - point).dot(normal)) > FIT_TOLERANCE:
		return 0.0
	return room


## The drip room of the splat at a slot (for checks).
func drip_room_of(slot: int) -> float:
	return _customs[slot].a


## When the splat at a slot landed, on `clock` (for checks), or -1.
func born_of(slot: int) -> float:
	return _born[slot]


## Every splat gone (rain, a reset).
func clear() -> void:
	for i in cap:
		_hide(i)
	count = 0
	_next = 0
	multimesh.visible_instance_count = 0


## Every splat within `radius` of `at` gone (the Wee-Woo Brigade hosing a
## mess off the street: EmergencyServices). Returns how many.
func clear_near(at: Vector3, radius: float) -> int:
	var n := 0
	var r2 := radius * radius
	for i in cap:
		if _born[i] < 0.0:
			continue
		if _xforms[i].origin.distance_squared_to(at) <= r2:
			_hide(i)
			n += 1
	count = maxi(0, count - n)
	return n


## A street-parked car (a MultiMesh instance in StreetProps, its collision
## a plain box, so a shot at it leaves a world splat here) has been swapped
## for a real `car` standing where it was parked (`parked`, the parked
## car's transform): the splats on it go with it. Each one inside the car's
## box comes out of the pool and goes on the car's own paint (PaintCoverage,
## the same colour, size and landing time, so it keeps dripping), and none
## is left hanging in the air where the car was. Returns how many moved.
func hand_to_car(car: Node3D, parked: Transform3D) -> int:
	if count == 0 or car == null or not "shape" in car:
		return 0
	var shape: Dictionary = car.get("shape")
	var w := float(shape.get("width", 1.8))
	var l := float(shape.get("length", 4.6))
	var h := float(shape.get("height", 1.5))
	var box := AABB(Vector3(-w * 0.5 - 0.1, -0.1, -l * 0.5 - 0.1), Vector3(w + 0.2, h + 0.2, l + 0.2))
	var to_car := parked.affine_inverse()
	var moved := 0
	var pc: PaintCoverage = null
	for n in cap:
		var slot := (_next + n) % cap # oldest first, so the newest stay drawn
		if _born[slot] < 0.0:
			continue
		var xf := _xforms[slot]
		var normal := xf.basis.z.normalized()
		var at := to_car * (xf.origin - normal * SURFACE_OFFSET)
		if not box.has_point(at):
			continue
		if pc == null:
			pc = PaintCoverage.of(car)
		var n_car := (to_car.basis * normal).normalized()
		pc.add_hit(at, _colours[slot], xf.basis.x.length(), false, n_car, n_car)
		pc.hits[-1]["born"] = _born[slot]
		_hide(slot)
		count -= 1
		moved += 1
	if pc != null:
		pc.redraw()
	return moved


## The quad at a splat's slot (for checks).
func transform_of(slot: int) -> Transform3D:
	return _xforms[slot]


## The slot the newest splat is in (for checks), or -1.
func newest_slot() -> int:
	return (_next - 1 + cap) % cap if count > 0 else -1


func _hide(slot: int) -> void:
	_xforms[slot] = Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	multimesh.set_instance_transform(slot, _xforms[slot])
	_born[slot] = -1.0


func _place(xf: Transform3D, colour: Color, custom: Color) -> void:
	if _born[_next] < 0.0:
		count += 1
	multimesh.set_instance_transform(_next, xf)
	multimesh.set_instance_color(_next, colour)
	multimesh.set_instance_custom_data(_next, custom)
	_xforms[_next] = xf
	_colours[_next] = colour
	_customs[_next] = custom
	_born[_next] = custom.g
	_next = (_next + 1) % cap
	# Draw only the slots used so far (the pool fills from the start).
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if count < cap else cap)
	if count >= cap:
		multimesh.visible_instance_count = cap


## How big a splat fits flat on the surface here: checks the four corners
## lie on the same surface, halving the size up to twice.
func _fit(point: Vector3, normal: Vector3, t: Vector3, b: Vector3, size: float, exclude: Array[RID]) -> float:
	if not is_inside_tree():
		return size
	var space := get_world_3d().direct_space_state
	_probe.exclude = exclude
	for attempt in 3:
		var ok := true
		for c: Vector3 in [t + b, t - b, -t + b, -t - b]:
			var corner := point + c * size * 0.7
			_probe.from = corner + normal * 0.08
			_probe.to = corner - normal * 0.08
			var hit := space.intersect_ray(_probe)
			if hit.is_empty() or absf((hit["position"] - point).dot(normal)) > FIT_TOLERANCE:
				ok = false
				break
		if ok:
			return size
		size *= 0.5
	return 0.0


func _expire() -> void:
	if count == 0:
		return
	# Oldest first: from the slot after the newest, round the ring (empty
	# slots, not yet used or already expired, are skipped).
	for n in cap:
		var slot := (_next + n) % cap
		if _born[slot] < 0.0:
			continue
		if clock - _born[slot] < LIFE:
			break
		_hide(slot)
		count -= 1


## A new pool size: keeps the newest splats that fit.
func _resize(new_cap: int) -> void:
	var keep: Array = []
	if multimesh != null and cap > 0:
		for n in cap:
			var slot := (_next + n) % cap # oldest to newest
			if _born[slot] >= 0.0:
				keep.append([_xforms[slot], _colours[slot], _customs[slot]])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _quad_mesh()
	mm.instance_count = new_cap
	mm.visible_instance_count = 0
	multimesh = mm
	cap = new_cap
	_born = PackedFloat32Array()
	_born.resize(cap)
	_born.fill(-1.0)
	_xforms.resize(cap)
	_xforms.fill(Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))
	_colours.resize(cap)
	_customs.resize(cap)
	count = 0
	_next = 0
	for k in range(maxi(0, keep.size() - cap), keep.size()):
		var e: Array = keep[k]
		_place(e[0], e[1], e[2])


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/paint_splat.gdshader")
		_material.set_shader_parameter("splat_tex", PaintTexture.texture())
		_material.set_shader_parameter("life", LIFE)
		_material.set_shader_parameter("fade", FADE)
		_material.set_shader_parameter("fade_far", FAR)
	return _material


## One quad, -1..1 in X and Y, facing +Z (the splat's normal), UV 0..1.
static func _quad_mesh() -> ArrayMesh:
	if _quad != null:
		return _quad
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	# Godot's front faces wind clockwise seen from the front.
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	_quad = ArrayMesh.new()
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad

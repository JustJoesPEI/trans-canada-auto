class_name TyreFx
extends Node3D
## Tyre smoke and skid marks, for every vehicle at once.
##
## A tyre sliding, spinning or locked hard (Car's per-wheel slide) lays a
## dark strip on the road where it touches and puffs smoke. Marks are flat
## quads in one MultiMesh, used as a ring: the oldest are reused once there
## are MAX_MARKS, so the town keeps the last few hundred metres of rubber.
## Smoke is a few hundred soft billboard puffs in another MultiMesh, moved
## here each frame: they drift up, swell and fade. Two draw calls in all,
## however many cars are sliding.
##
## Vehicles reach it with TyreFx.get_for(node); the first call makes it.

const MAX_MARKS := 2400
const MAX_PUFFS := 360
const MARK_STEP := 0.25 ## m between the joins of a mark
const PUFF_LIFE := 1.7 ## seconds

var _marks: MultiMesh
var _next_mark := 0
var _used_marks := 0
## Where each wheel's mark got to: "car id/wheel" -> world position.
var _last := {}
var _puffs: MultiMesh
var _puff_pos: PackedVector3Array
var _puff_vel: PackedVector3Array
var _puff_age: PackedFloat32Array
var _puff_size: PackedFloat32Array
var _puff_alpha: PackedFloat32Array
var _next_puff := 0
var _live_puffs := 0


static var _instance: TyreFx = null


static func get_for(node: Node) -> TyreFx:
	var tree := node.get_tree()
	if tree == null:
		return null
	if _instance == null or not is_instance_valid(_instance) or _instance.is_queued_for_deletion():
		_instance = TyreFx.new()
		_instance.name = "TyreFx"
		tree.root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	top_level = true
	# Marks: one flat strip per step, darkened rubber.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.04, 0.04, 0.045)
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.roughness = 0.9
	mm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material = mm
	_marks = MultiMesh.new()
	_marks.transform_format = MultiMesh.TRANSFORM_3D
	_marks.use_colors = true
	_marks.mesh = plane
	_marks.instance_count = MAX_MARKS
	_marks.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _marks
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 220.0
	# (Marks are spread over the town: no culling box would be right.)
	mi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(mi)

	# Smoke: soft round puffs that always face the camera.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var sm := StandardMaterial3D.new()
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.billboard_keep_scale = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.vertex_color_use_as_albedo = true
	sm.albedo_color = Color(0.86, 0.86, 0.88)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.45, Color(1, 1, 1, 0.55))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	sm.albedo_texture = tex
	quad.material = sm
	_puffs = MultiMesh.new()
	_puffs.transform_format = MultiMesh.TRANSFORM_3D
	_puffs.use_colors = true
	_puffs.mesh = quad
	_puffs.instance_count = MAX_PUFFS
	_puffs.visible_instance_count = 0
	var pi := MultiMeshInstance3D.new()
	pi.multimesh = _puffs
	pi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(pi)
	_puff_pos.resize(MAX_PUFFS)
	_puff_vel.resize(MAX_PUFFS)
	_puff_age.resize(MAX_PUFFS)
	_puff_size.resize(MAX_PUFFS)
	_puff_alpha.resize(MAX_PUFFS)
	for i in MAX_PUFFS:
		_puff_age[i] = PUFF_LIFE


## A tyre at `at` (on the road, with the road's normal `n`) sliding by
## `slide` (0..1) while the car moves at `velocity`. `width` is the tread.
## Call every physics step while it slides; `key` names the wheel.
func slide(key: String, at: Vector3, n: Vector3, width: float, slide_amount: float, velocity: Vector3, smoke := true) -> void:
	if _marks == null:
		return # not in the tree yet
	var p := at + n * 0.012
	var last: Variant = _last.get(key)
	if last == null:
		_last[key] = p
	else:
		var d := p.distance_to(last as Vector3)
		if d > 3.0:
			_last[key] = p # jumped (teleported, or a gap): start afresh
		elif d >= MARK_STEP:
			_mark(last as Vector3, p, n, width, slide_amount)
			_last[key] = p
	if smoke and slide_amount > 0.5 and randf() < slide_amount * 0.55:
		_puff(at + n * 0.15, velocity, slide_amount)


## The tyre has stopped sliding: its next mark starts a new strip.
func lift(key: String) -> void:
	_last.erase(key)


func _mark(a: Vector3, b: Vector3, n: Vector3, width: float, strength: float) -> void:
	var along := b - a
	var len := along.length()
	var z := along / len
	var x := n.cross(z).normalized()
	var y := z.cross(x)
	# End to end: overlapping strips would double up the darkness at the joins.
	var xf := Transform3D(Basis(x * width, y, z * len), (a + b) * 0.5)
	_marks.set_instance_transform(_next_mark, xf)
	_marks.set_instance_color(_next_mark, Color(1, 1, 1, clampf(strength * 0.75, 0.15, 0.7)))
	_next_mark = (_next_mark + 1) % MAX_MARKS
	_used_marks = mini(_used_marks + 1, MAX_MARKS)
	_marks.visible_instance_count = _used_marks


func _puff(at: Vector3, velocity: Vector3, strength: float) -> void:
	var i := _next_puff
	_next_puff = (_next_puff + 1) % MAX_PUFFS
	_puff_pos[i] = at + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
	# Thrown off with some of the car's speed, then the air stops it.
	_puff_vel[i] = velocity * 0.25 + Vector3(randf_range(-0.5, 0.5), randf_range(0.3, 0.8), randf_range(-0.5, 0.5))
	_puff_age[i] = 0.0
	_puff_size[i] = randf_range(0.5, 0.8)
	_puff_alpha[i] = clampf(0.25 + strength * 0.35, 0.0, 0.55)
	_live_puffs += 1


func _process(delta: float) -> void:
	if _live_puffs == 0:
		return
	# The live puffs are packed to the front of the MultiMesh and only those
	# are drawn (a spent one parked at zero size would still be drawn, and a
	# billboard can't make sense of a zero scale).
	var shown := 0
	for i in MAX_PUFFS:
		var age := _puff_age[i]
		if age >= PUFF_LIFE:
			continue
		age += delta
		_puff_age[i] = age
		var v := _puff_vel[i] * exp(-2.5 * delta)
		v.y += 0.4 * delta # warm air rising
		_puff_vel[i] = v
		_puff_pos[i] += v * delta
		var t := minf(age / PUFF_LIFE, 1.0)
		var size := _puff_size[i] * (1.0 + 3.0 * t)
		_puffs.set_instance_transform(shown, Transform3D(Basis.from_scale(Vector3.ONE * size), _puff_pos[i]))
		_puffs.set_instance_color(shown, Color(1, 1, 1, _puff_alpha[i] * (1.0 - t) * (1.0 - t) * minf(1.0, age * 8.0)))
		shown += 1
	_puffs.visible_instance_count = shown
	_live_puffs = shown

class_name TrafficCrowd
extends Node3D
## Draws the traffic that's moving without physics (RoadFollower): one
## MultiMesh per model, of the parked-car meshes (StreetProps._parked_mesh:
## cached, two surfaces, automatic LODs, paint in the custom data), moved
## each frame. No new meshes, no shadows (they're all a way off), and a
## draw distance like the parked cars' (a little longer: moving cars catch
## the eye), applied car by car here: a MultiMesh's own visibility range
## goes by its box as a whole, and this one's cars are spread over town.
## The box is fitted round its cars each frame so it culls and picks its
## level of detail by where they are.
##
## The draw distance reaches past the furthest a car is placed
## (TrafficDensity.SPAWN_MAX), so a car coming toward the player is already
## drawn when it comes into view instead of popping in on the way.

const DRAW_DISTANCE := 440.0

var _mmis := {} ## model index -> MultiMeshInstance3D
## Per model: its instance buffer (FLOATS a car), filled in place each
## frame and handed over in one call, and how many cars it holds now.
var _bufs := {} ## model index -> PackedFloat32Array
var _shown := PackedInt32Array()
var _lo: Array[Vector3] = []
var _hi: Array[Vector3] = []
## A transform (12) and the paint (4).
const FLOATS := 16

## Off on a machine that draws nothing (a server): nothing to show.
var enabled := DisplayServer.get_name() != "headless"


## Draws the far traffic: each driver's follower, by its model, painted,
## lifted to the street surface (`lift`, metres above the follower).
func show_drivers(drivers: Array[TrafficDriver]) -> void:
	if not enabled:
		return
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam != null else Vector3.INF
	var r2 := DRAW_DISTANCE * DRAW_DISTANCE
	var models := StreetProps.PARKED_MODELS.size()
	if _shown.size() != models:
		_shown.resize(models)
		_lo.resize(models)
		_hi.resize(models)
	_shown.fill(0)
	for d: TrafficDriver in drivers:
		var rf := d.follower
		var v := d.model_index
		if rf == null or v < 0 or not is_instance_valid(rf):
			continue
		if c != Vector3.INF and c.distance_squared_to(rf.global_position) > r2:
			continue
		var i := _shown[v]
		var buf: PackedFloat32Array = _buf(v, i + 1)
		var xf := rf.get_global_transform_interpolated()
		var o := xf.origin
		o.y += d.lift
		var b := xf.basis
		var k := i * FLOATS
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = o.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = o.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = o.z
		var p := d.paint
		buf[k + 12] = p.r
		buf[k + 13] = p.g
		buf[k + 14] = p.b
		buf[k + 15] = 1.0
		if i == 0:
			_lo[v] = o
			_hi[v] = o
		else:
			_lo[v] = _lo[v].min(o)
			_hi[v] = _hi[v].max(o)
		_shown[v] = i + 1
	for v: int in _mmis:
		var mmi: MultiMeshInstance3D = _mmis[v]
		var n := _shown[v]
		if n == 0:
			if mmi.multimesh.visible_instance_count != 0:
				mmi.multimesh.visible_instance_count = 0
			continue
		RenderingServer.multimesh_set_buffer(mmi.multimesh.get_rid(), _bufs[v])
		mmi.multimesh.visible_instance_count = n
		mmi.custom_aabb = AABB(_lo[v], _hi[v] - _lo[v]).grow(3.0)


## Model v's buffer, with room for `need` cars (its MultiMesh grown to
## match: the buffer handed over is always the whole MultiMesh's).
func _buf(v: int, need: int) -> PackedFloat32Array:
	var mmi: MultiMeshInstance3D = _mmis.get(v)
	if mmi == null or mmi.multimesh.instance_count < need:
		var keep: PackedFloat32Array = _bufs.get(v, PackedFloat32Array())
		mmi = _mmi(v, need)
		var grown := PackedFloat32Array()
		grown.resize(mmi.multimesh.instance_count * FLOATS)
		for j in keep.size():
			grown[j] = keep[j]
		_bufs[v] = grown
	return _bufs[v]


func _mmi(v: int, need: int) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = _mmis.get(v)
	if mmi != null and mmi.multimesh.instance_count >= need:
		return mmi
	var cap := 8
	while cap < need:
		cap *= 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = StreetProps._parked_mesh(v)
	mm.instance_count = cap
	mm.visible_instance_count = 0
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = "Traffic_%s" % StreetProps.PARKED_MODELS[v]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Each frame's transforms are already the interpolated ones, and a
		# slot holds whichever car is at that place in the list this frame:
		# Godot's own MultiMesh interpolation would blend them again, a tick
		# late, and smear a slot from one car to the next (squashed, skewed
		# cars sliding about).
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mmi)
		_mmis[v] = mmi
	mmi.multimesh = mm
	return mmi

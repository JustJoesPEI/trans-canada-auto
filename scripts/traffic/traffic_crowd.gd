class_name TrafficCrowd
extends Node3D
## Draws the traffic that's moving without physics (RoadFollower): one
## MultiMesh per model, of the parked-car meshes (StreetProps._parked_mesh:
## cached, two surfaces, automatic LODs, paint in the custom data), moved
## each frame. No new meshes, no shadows (they're all a way off), and a
## draw distance like the parked cars' (a little longer: moving cars catch
## the eye).

const DRAW_DISTANCE := 300.0

var _mmis := {} ## model index -> MultiMeshInstance3D


## Draws these followers ([RoadFollower, model index, paint colour]).
func show_followers(list: Array) -> void:
	var by_model := {}
	for x: Array in list:
		var v: int = x[1]
		if not by_model.has(v):
			by_model[v] = []
		(by_model[v] as Array).append(x)
	for v: int in _mmis:
		if not by_model.has(v):
			(_mmis[v] as MultiMeshInstance3D).multimesh.visible_instance_count = 0
	for v: int in by_model:
		var items: Array = by_model[v]
		var mmi := _mmi(v, items.size())
		var mm := mmi.multimesh
		for i in items.size():
			var rf: RoadFollower = items[i][0]
			mm.set_instance_transform(i, rf.get_global_transform_interpolated())
			var c: Color = items[i][2]
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, 1.0))
		mm.visible_instance_count = items.size()


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
		mmi.visibility_range_end = DRAW_DISTANCE
		mmi.visibility_range_end_margin = 8.0
		# Each frame's transforms are already the interpolated ones, and a
		# slot holds whichever car is at that place in the list this frame:
		# Godot's own MultiMesh interpolation would blend them again, a tick
		# late, and smear a slot from one car to the next (squashed, skewed
		# cars sliding about).
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# They move about: don't let the box round them cull them.
		mmi.custom_aabb = AABB(Vector3(-4000, -200, -4000), Vector3(8000, 600, 8000))
		add_child(mmi)
		_mmis[v] = mmi
	mmi.multimesh = mm
	return mmi

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

const DRAW_DISTANCE := 300.0

var _mmis := {} ## model index -> MultiMeshInstance3D


## Draws these followers ([RoadFollower, model index, paint colour, lift:
## metres above the follower, to the street surface]).
func show_followers(list: Array) -> void:
	var by_model := {}
	var cam := get_viewport().get_camera_3d()
	for x: Array in list:
		if cam != null and cam.global_position.distance_to((x[0] as Node3D).global_position) > DRAW_DISTANCE:
			continue
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
		var box := AABB()
		for i in items.size():
			var rf: RoadFollower = items[i][0]
			var xf := rf.get_global_transform_interpolated()
			xf.origin.y += float(items[i][3]) if items[i].size() > 3 else 0.0
			mm.set_instance_transform(i, xf)
			box = AABB(xf.origin, Vector3.ZERO) if i == 0 else box.expand(xf.origin)
			var c: Color = items[i][2]
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, 1.0))
		mm.visible_instance_count = items.size()
		mmi.custom_aabb = box.grow(3.0)


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

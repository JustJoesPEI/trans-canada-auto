class_name CrownFade
extends Node3D
## Lets the camera fade one mapped tree's crown out of the way, though the
## crowns are drawn through tiled MultiMeshes (StreetProps._trees; W3).
##
## One of these stands at each crown's middle, in the group
## "camera_fade_props" with a "radius" meta, where the camera looks for
## crowns between it and the player (CameraRig._find_prop_occluders). It
## draws nothing. While the crown is faded its MultiMesh instance is
## shrunk to nothing and a MeshInstance3D of the same crown stands in its
## place, made see-through; it's freed and the instance put back when the
## fade is over. Only the few crowns in the way ever have one.

var mmi: MultiMeshInstance3D
var index := -1
## The crown's mesh (the shader warm-up draws one faded).
var mesh: Mesh
## The instance's transform in the MultiMesh, put back after a fade.
var _xform := Transform3D()
var _temp: MeshInstance3D


func set_camera_fade(v: float) -> void:
	if not is_instance_valid(mmi) or mmi.multimesh == null or index < 0 or index >= mmi.multimesh.instance_count:
		return
	var mm := mmi.multimesh
	if v <= 0.0:
		if _temp != null:
			_temp.queue_free()
			_temp = null
			mm.set_instance_transform(index, _xform)
		return
	if _temp == null:
		_xform = mm.get_instance_transform(index)
		mm.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ZERO), _xform.origin))
		_temp = MeshInstance3D.new()
		_temp.mesh = mesh
		# Its shadow is still cast by the MultiMesh's shadow stand-in.
		_temp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_temp)
		if is_inside_tree():
			_temp.global_transform = mmi.global_transform * _xform
	_temp.transparency = v

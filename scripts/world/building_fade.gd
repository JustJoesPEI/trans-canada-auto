class_name BuildingFade
extends RefCounted
## Lets the camera fade one building out of a chunk's merged building mesh.
##
## Each building's collision body carries one of these as its "fade_mesh"
## meta. The camera calls set_camera_fade() on it as the building comes
## between it and the player. The chunk's mesh gets its own copies of the
## shared wall and roof materials only while something in it is faded, and
## the shaders dither away just the vertices whose building number
## (CUSTOM0) matches, up to four buildings per chunk at once.

var mesh: MeshInstance3D
var id: float


## A copy of `src` to fade with: for the building shaders, their `_fade`
## version (the shared ones have no discard, so the whole town keeps the
## depth test's early-out; only these copies dither away).
static func faded_copy(src: ShaderMaterial) -> ShaderMaterial:
	var copy := src.duplicate() as ShaderMaterial
	var path := src.shader.resource_path if src.shader != null else ""
	if path.ends_with("/building_wall.gdshader") or path.ends_with("/building_roof.gdshader"):
		copy.shader = load(path.replace(".gdshader", "_fade.gdshader"))
	return copy


func _init(chunk_mesh: MeshInstance3D, building_id: float) -> void:
	mesh = chunk_mesh
	id = building_id


func set_camera_fade(v: float) -> void:
	if not is_instance_valid(mesh):
		return
	var levels: Dictionary = mesh.get_meta("fade_levels", {})
	if v <= 0.0:
		levels.erase(id)
	else:
		levels[id] = v
	mesh.set_meta("fade_levels", levels)
	if levels.is_empty():
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, null)
		return
	# The four most faded buildings in this chunk.
	var order := levels.keys()
	order.sort_custom(func(a: float, b: float) -> bool: return float(levels[a]) > float(levels[b]))
	var ids := Vector4(-1, -1, -1, -1)
	var amounts := Vector4.ZERO
	for k in mini(4, order.size()):
		ids[k] = float(order[k])
		amounts[k] = float(levels[order[k]])
	for i in mesh.mesh.get_surface_count():
		var mat := mesh.get_surface_override_material(i) as ShaderMaterial
		if mat == null:
			var src := mesh.mesh.surface_get_material(i) as ShaderMaterial
			if src == null:
				continue
			mat = faded_copy(src)
			mesh.set_surface_override_material(i, mat)
		mat.set_shader_parameter("fade_ids", ids)
		mat.set_shader_parameter("fade_levels", amounts)

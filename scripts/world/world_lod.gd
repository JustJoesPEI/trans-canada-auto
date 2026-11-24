class_name WorldLod
extends RefCounted
## How far things in the town are drawn (docs/world_art.md, rule W4).
##
## A thing is worth drawing while it's a few pixels on screen. At 900
## pixels high and the game's 70 degree view, a metre is about 640 / d
## pixels at d metres, so something S metres across stops being worth
## drawing (about 6 pixels) at S * PER_METRE. Everything small that's
## repeated (props, clutter, signs) gets a visibility range from its size,
## so adding more of them doesn't add to the cost of the far town.

## m of draw distance per metre of size (about 6 pixels at the cutoff).
const PER_METRE := 100.0
## Nothing is cut off nearer than this (m), however small.
const MIN_DISTANCE := 40.0


## The draw distance for something `size` metres across (its longest side),
## at most `cap`.
static func distance_for(size: float, cap := 300.0) -> float:
	return clampf(size * PER_METRE, MIN_DISTANCE, cap)


## The draw distance for a mesh, from its bounding box.
static func draw_distance(mesh: Mesh, cap := 300.0) -> float:
	if mesh == null:
		return cap
	var s := mesh.get_aabb().size
	return distance_for(maxf(s.x, maxf(s.y, s.z)), cap)


## Gives `gi` a visibility range from its mesh's size (or `size`, if given).
static func limit(gi: GeometryInstance3D, size := -1.0, cap := 300.0) -> void:
	var d := cap
	if size > 0.0:
		d = distance_for(size, cap)
	elif gi is MeshInstance3D:
		d = draw_distance((gi as MeshInstance3D).mesh, cap)
	gi.visibility_range_end = d
	gi.visibility_range_end_margin = 4.0

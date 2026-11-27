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

## The graphics setting's share of every draw distance, set by Graphics
## before the town is built: `near_share` for small things (a draw distance
## of 40 m or less: clutter, litter, small signs), `far_share` for big ones
## (300 m and more: lamps, poles, buildings' props), in between for the
## rest. High draws everything as far as its size says (1 and 1); Low and
## Medium pull the small things in most, since a bench at 40 m is a few
## pixels but there are hundreds of them, and keep the big ones that
## shape the street. One table for everything, applied as each thing joins
## the scene (`apply`), so new detail gets it without asking.
static var near_share := 1.0
static var far_share := 1.0
## However small, nothing is pulled in nearer than this (m) by the setting.
const SETTING_FLOOR := 25.0


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


## A draw distance as the graphics setting draws it (see near_share).
static func for_setting(d: float) -> float:
	if d <= 0.0 or (near_share == 1.0 and far_share == 1.0):
		return d
	var share := lerpf(near_share, far_share, smoothstep(MIN_DISTANCE, 300.0, d))
	return maxf(d * share, minf(d, SETTING_FLOOR))


## Gives `gi`'s visibility range (both ends, so a near version and its
## far stand-in still meet) the graphics setting's share. Called for every
## GeometryInstance3D as it joins the scene (Graphics); safe to call
## again on the same node (a chunk moved, a node re-added): it keeps the
## distances it was given and works from those, unless they've been
## changed since. After a change of setting (F10) it's called again for
## everything, from the distances each thing was first given.
static func apply(gi: GeometryInstance3D) -> void:
	var now := Vector2(gi.visibility_range_begin, gi.visibility_range_end)
	var raw := now
	if gi.has_meta("lod_raw") and now == gi.get_meta("lod_set", Vector2(-1, -1)):
		raw = gi.get_meta("lod_raw") # done before, from these
	elif near_share == 1.0 and far_share == 1.0:
		return
	if raw == Vector2.ZERO:
		return
	var out := Vector2(for_setting(raw.x), for_setting(raw.y))
	gi.set_meta("lod_raw", raw)
	gi.set_meta("lod_set", out)
	gi.visibility_range_begin = out.x
	gi.visibility_range_end = out.y

class_name WheelProbe
extends RefCounted
## Finds the road under a car's wheels (Car._suspension_and_tyres), with the
## native library's TcaWheels.probe when it's loaded (native/README.md) and
## the same thing in GDScript here when it isn't (the web build, an editor
## without the library). The two must give the same answer:
## tools/native_check.gd checks they do.

## The native version, if the library's loaded (and not switched off).
static var native_on := ClassDB.class_exists("TcaWheels")


## For wheel i, rays down from the mount (xf * mounts[i]) at the middle and
## both edges of the tread, reach[i] long; the highest hit (an edge
## counting 3 cm lower: a tyre half up on a curb is up on the curb, but by
## height, not distance, so a leaning body putting one edge nearer flat
## road isn't something to climb), not counting a steep face of something
## that isn't ground (another vehicle's side: standing on another vehicle
## only counts on something like a floor). One hit Dictionary per wheel, or
## null (no road, or skip[i] set).
static func probe(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, xf: Transform3D,
		mounts: PackedVector3Array, half_treads: PackedFloat64Array, reach: PackedFloat64Array, skip: PackedByteArray) -> Array:
	if native_on:
		return ClassDB.class_call_static("TcaWheels", "probe", space, ray, xf, mounts, half_treads, reach, skip, Layers.GROUND)
	return probe_gd(space, ray, xf, mounts, half_treads, reach, skip)


## The GDScript version.
static func probe_gd(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, xf: Transform3D,
		mounts: PackedVector3Array, half_treads: PackedFloat64Array, reach: PackedFloat64Array, skip: PackedByteArray) -> Array:
	var out := []
	out.resize(mounts.size())
	var up := xf.basis.y
	var side := xf.basis.x
	for i in mounts.size():
		if i < skip.size() and skip[i] != 0:
			continue
		var from := xf * mounts[i]
		var hit := {}
		var top := -INF
		for across: float in [0.0, -half_treads[i], half_treads[i]]:
			var f0 := from + side * across
			ray.from = f0
			ray.to = f0 - up * reach[i]
			var h := space.intersect_ray(ray)
			if h.is_empty() or (h["collider"] is CollisionObject3D and ((h["collider"] as CollisionObject3D).collision_layer & Layers.GROUND) == 0 and (h["normal"] as Vector3).y < 0.5):
				continue
			var y := (h["position"] as Vector3).y - (0.0 if across == 0.0 else 0.03)
			if y > top:
				top = y
				hit = h
		if not hit.is_empty():
			out[i] = hit
	return out

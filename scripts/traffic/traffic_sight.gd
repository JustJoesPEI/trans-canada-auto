class_name TrafficSight
extends RefCounted
## Can any player see a spot? Traffic is only placed and taken away where
## nobody can (design.md, 7½ "How many"). The local player: the one camera.
## Other players (the server's view of everyone, or simulated players in a
## tool) have no camera here: they could be looking any way, so for them a
## spot is seen whenever there's a clear line to it (`seen_from`).
## A spot is seen when it's within SEE_RANGE, in front of the camera (with
## a margin, so a car just off the edge of the screen doesn't vanish) and
## not hidden behind a building or the ground. Within NEAR of the player
## it always counts as seen: one look round and it would be.

const SEE_RANGE := 700.0
const NEAR := 45.0

## How many times sight was asked, and how many of those were seen.
static var checks := 0


static func seen(tree: SceneTree, p: Vector3, player_pos := Vector3.INF) -> bool:
	checks += 1
	if player_pos != Vector3.INF and player_pos.distance_to(p) < NEAR:
		return true
	var vp := tree.root.get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return false
	var c := cam.global_position
	if c.distance_to(p) > SEE_RANGE:
		return false
	if c.distance_to(p) < NEAR:
		return true
	# In view: the car's middle and its ends, a little up.
	var any := false
	for o: Vector3 in [Vector3(0, 1.0, 0), Vector3(3.0, 0.8, 0), Vector3(-3.0, 0.8, 0), Vector3(0, 0.8, 3.0), Vector3(0, 0.8, -3.0)]:
		if cam.is_position_in_frustum(p + o):
			any = true
			break
	if not any:
		return false
	# Not behind a building (or a hill).
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(c, p + Vector3.UP * 1.4, Layers.SOLID | Layers.GROUND)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	# Something solid right at the spot (a parked car, the curb) still sees it.
	return (hit["position"] as Vector3).distance_to(p) < 4.0


## Can someone standing at `eye` (their feet) see p, looking any way? Seen
## within NEAR; not past SEE_RANGE; otherwise seen unless a building or
## the ground is in the way.
static func seen_from(world: World3D, p: Vector3, eye: Vector3) -> bool:
	checks += 1
	var d2 := eye.distance_squared_to(p)
	if d2 < NEAR * NEAR:
		return true
	if d2 > SEE_RANGE * SEE_RANGE:
		return false
	var from := eye + Vector3.UP * 1.6
	var q := PhysicsRayQueryParameters3D.create(from, p + Vector3.UP * 1.4, Layers.SOLID | Layers.GROUND)
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(p) < 4.0


## Seen by anyone: the local player (by the camera, as `seen`) if there is
## one (`local` not INF), or any of the others.
static func seen_by_any(tree: SceneTree, p: Vector3, local: Vector3, others: PackedVector3Array) -> bool:
	if local != Vector3.INF and seen(tree, p, local):
		return true
	if others.is_empty():
		return false
	var world := tree.root.get_world_3d()
	for o: Vector3 in others:
		if seen_from(world, p, o):
			return true
	return false

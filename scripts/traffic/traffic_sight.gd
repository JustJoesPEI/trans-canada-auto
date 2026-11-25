class_name TrafficSight
extends RefCounted
## Can any player see a spot? Traffic is only placed and taken away where
## nobody can (design.md, 7½ "How many"). Single player: the one camera.
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

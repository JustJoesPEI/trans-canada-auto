class_name CarRighting
extends RefCounted
## Putting a car that's ended up on its roof or its side back on its wheels,
## from the driver's seat: hold the flip key (R, or A on a controller) for
## HOLD seconds once it's come to rest. The way most open-world games do it,
## so a roll in a chase or a bad landing off a curb costs a few seconds, not
## a walk to the nearest tow.
##
##   CarRighting.is_over(car)    on its roof or side
##   CarRighting.can_right(car)  over, and settled enough to flip back
##   CarRighting.right(car)      upright where it lies, facing the way it
##                               pointed, dropped onto its wheels

## Seconds the key is held.
const HOLD := 0.8
## The body's up has to point this little up to count as over (0.35: about
## 70 degrees over, so a car leaning on a bank isn't over).
const OVER_UP := 0.35
## Settled: slower than this (m/s, and rad/s turning).
const SETTLED_SPEED := 2.5
const SETTLED_SPIN := 1.5
## How far above the ground the car's middle is put back (m): it drops the
## rest of the way onto its springs.
const DROP_HEIGHT := 1.1


static func is_over(car: RigidBody3D) -> bool:
	return car != null and car.global_basis.y.dot(Vector3.UP) < OVER_UP


static func can_right(car: RigidBody3D) -> bool:
	return is_over(car) and car.linear_velocity.length() < SETTLED_SPEED and car.angular_velocity.length() < SETTLED_SPIN


## Stands the car up where it lies. Its heading is the way its nose pointed
## along the ground (or, standing on its nose or tail, the way its roof
## did).
static func right(car: RigidBody3D) -> void:
	var b := car.global_basis
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length() < 0.3:
		fwd = b.y
		fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	var at := car.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 4.0, Layers.GROUND)
	q.exclude = [car.get_rid()]
	var hit := car.get_world_3d().direct_space_state.intersect_ray(q)
	var ground: float = (hit["position"] as Vector3).y if not hit.is_empty() else at.y
	var xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), Vector3(at.x, maxf(at.y, ground + DROP_HEIGHT), at.z))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.global_transform = xf
	PhysicsServer3D.body_set_state(car.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	car.reset_physics_interpolation()

class_name Smooth
extends RefCounted
## Critically damped springs: a value glides to its goal without lag spikes
## or overshoot, easing in and out. smooth_time is roughly how long it takes
## to get there. Each returns [new value, new velocity]; keep the velocity
## and pass it back next time.


static func spring(cur: float, vel: float, goal: float, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(0.0001, smooth_time)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + omega * change) * delta
	return [goal + (change + temp) * e, (vel - omega * temp) * e]


static func spring3(cur: Vector3, vel: Vector3, goal: Vector3, smooth_time: float, delta: float) -> Array:
	var omega := 2.0 / maxf(0.0001, smooth_time)
	var x := omega * delta
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := cur - goal
	var temp := (vel + change * omega) * delta
	return [goal + (change + temp) * e, (vel - temp * omega) * e]


## An angle (radians) taking the short way round.
static func spring_angle(cur: float, vel: float, goal: float, smooth_time: float, delta: float) -> Array:
	return spring(cur, vel, cur + angle_difference(cur, goal), smooth_time, delta)

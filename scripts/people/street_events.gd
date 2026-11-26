class_name StreetEvents
extends RefCounted
## Things happening in the street that people notice: a crash, a tow truck
## winching a car on, a car sitting dead in the road, a painted car, an
## arrest. Whatever makes them posts it here (TrafficManager, TrafficTows,
## PedestrianManager), and the people on foot near it react
## (PedestrianManager, twice a second: slow down and look, or stop and
## watch, and now and then one says something) and the drivers going by
## slow down to look (TrafficManager).
##
## A short list of points with a radius and an end time: nothing is
## searched for, and a person checks only the few events there are. The
## same kind posted again near one still going just keeps that one going.

## Posted again within this of one of the same kind: the same thing (m).
const SAME := 15.0
## Never more than this many at once (the oldest go first).
const MAX := 12

## Each {"id", "kind", "pos": Vector2, "y", "radius", "until": seconds}.
static var list: Array[Dictionary] = []
static var _next_id := 1


## Something worth looking at at `at`, for `secs`, noticed within `radius`.
## Returns its id.
static func post(kind: String, at: Vector3, secs: float, radius := 30.0) -> int:
	var p := Vector2(at.x, at.z)
	var now := _now()
	for e: Dictionary in list:
		if e["kind"] == kind and (e["pos"] as Vector2).distance_to(p) < SAME:
			e["until"] = maxf(float(e["until"]), now + secs)
			e["pos"] = p
			e["y"] = at.y
			return int(e["id"])
	if list.size() >= MAX:
		list.pop_front()
	var id := _next_id
	_next_id += 1
	list.append({"id": id, "kind": kind, "pos": p, "y": at.y, "radius": radius, "until": now + secs})
	return id


## The ones still going.
static func active() -> Array[Dictionary]:
	var now := _now()
	var i := 0
	while i < list.size():
		if float(list[i]["until"]) < now:
			list.remove_at(i)
		else:
			i += 1
	return list


static func clear() -> void:
	list.clear()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

class_name Jobs
extends Node
## Paid work (docs/design.md sections 6 and 6½): one job at a time, a list
## of stops to get to, paid at the end. Food runs, tows, hauls and supply
## drops are all one of these; what differs is where the stops are and
## what has to be true at each, which the code offering the job says.
##
##   Jobs.find(tree)           the one in the game (Economy's)
##   add_source(kind, fn)      fn(near: Vector3, count: int) -> Array of jobs
##                             on offer of that kind near a point
##   offers(kinds, near, n)    jobs on offer, from the sources of `kinds`
##   start(job) -> String      takes a job: "" if it started, else why not
##   cancel()                  gives it up (no pay)
##   active                    the job under way ({} for none)
##   stop()                    its current stop ({} for none)
##
## A job:
##   kind      "spuddash", "tow", "supplies", "freight"... (counted in
##             GameState.jobs_done when finished)
##   company   who it's for, shown over the title ("SpudDash",
##             "Delayed & Lost")
##   title     "Two dozen eggs to 45 Kent Street"
##   client, line   who wants it and their line of text (optional)
##   pay       base pay ($), before the time, condition and GPS factors
##   estimate  seconds it should take (the time factor's reference)
##   gps       the GPS help: "route", "directions" or "address" (Gps modes;
##             less help pays more: GPS_PAY)
##   needs     Callable(player) -> String: "" if the player can do it now,
##             else why not ("You need a tow truck"); checked at start and
##             at each stop (optional)
##   condition Callable(job) -> float 0..1 (the pay's condition factor;
##             optional)
##   cargo     what's carried, named on the job panel ("Food"; optional)
##   cargo_state  Callable(job) -> float 0..1, shown beside it as a percent
##   stops     [{name ("Pick up", "Drop off"), address (text, optional),
##              at: Vector3, radius (m, default 12), wait (s held still in
##              it, default 1.5), in_vehicle (default true: you, in a
##              vehicle; false: on foot; null: either), wrong_way (said
##              once if you're in the zone the other way, optional),
##              near + near_radius (a second spot that counts too, such as
##              the building itself; optional), holding (said once when
##              you're in and it starts counting, optional), check: Callable(stop, job) -> bool
##              (optional, more that must be true), hint (what to do there,
##              shown on the HUD: "Back the trailer up to the dock"),
##              on_reach: Callable(stop, job) (optional: load the order,
##              drop the car...)}]
##   on_finish Callable(job, pay: int) (optional)
##   on_cancel Callable(job) (optional)
##   data      anything the job's own code wants to keep
##
## Pay: pay × time × condition × GPS factor, rounded to the dollar. Time:
## 1.2 at half the estimate or less, 1.0 at it, down to 0.6 at twice it.
## The job's code can add a tip in on_finish (add_money).

signal started(job: Dictionary)
signal stop_reached(job: Dictionary, index: int)
signal finished(job: Dictionary, pay: int)
signal cancelled(job: Dictionary)

const GPS_PAY := {"route": 1.0, "directions": 1.15, "address": 1.35}
const STILL_SPEED := 1.5 ## m/s that counts as stopped in a stop's zone

var player: Node3D
var hud: Node
var active := {}
var index := 0
var _sources := {} ## kind -> Callable
var _t0 := 0.0
var _still := 0.0
var _told := -1 ## the stop whose wrong_way line was said
var _held := -1 ## the stop whose holding line was said
var _timer := 0.0
var _panel: JobPanel


static func find(tree: SceneTree) -> Jobs:
	return tree.get_first_node_in_group("jobs") as Jobs if tree != null else null


func _ready() -> void:
	add_to_group("jobs")


func setup(who: Node3D, h: Node) -> void:
	player = who
	hud = h
	_panel = JobPanel.new()
	_panel.name = "JobPanel"
	if h != null:
		h.add_child(_panel)
	else:
		add_child(_panel)


func add_source(kind: String, fn: Callable) -> void:
	_sources[kind] = fn


func offers(kinds: Array, near: Vector3, n := 4) -> Array:
	var out: Array = []
	for k: String in (kinds if not kinds.is_empty() else _sources.keys()):
		var fn: Variant = _sources.get(k)
		if fn is Callable and (fn as Callable).is_valid():
			var got: Variant = (fn as Callable).call(near, n)
			if got is Array:
				out.append_array(got)
	return out


func stop() -> Dictionary:
	if active.is_empty() or index >= (active["stops"] as Array).size():
		return {}
	return active["stops"][index]


## Seconds since the job started.
func elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0 if not active.is_empty() else 0.0


func start(job: Dictionary) -> String:
	if not active.is_empty():
		return "You're already on a job: %s. Finish it, or cancel it on your phone (Jobs or SpudDash)." % active.get("title", "")
	if (job.get("stops", []) as Array).is_empty():
		return "That job has nowhere to go."
	var why := _needs(job)
	if why != "":
		return why
	active = job
	index = 0
	_t0 = Time.get_ticks_msec() / 1000.0
	_still = 0.0
	_told = -1
	_held = -1
	_point_gps()
	started.emit(job)
	_title(str(job.get("title", "Job")), str(job.get("line", "")))
	return ""


func cancel() -> void:
	if active.is_empty():
		return
	var job := active
	active = {}
	_clear_gps(job)
	var cb: Variant = job.get("on_cancel")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(job)
	cancelled.emit(job)
	_title("Job cancelled", str(job.get("title", "")))


## What the job pays if finished now, and its parts:
## {pay, base, time, condition, gps}.
func pay_now() -> Dictionary:
	if active.is_empty():
		return {}
	var est := maxf(1.0, float(active.get("estimate", 300.0)))
	var r := elapsed() / est
	var time := 1.2 if r <= 0.5 else (lerpf(1.2, 1.0, (r - 0.5) / 0.5) if r <= 1.0 else maxf(0.6, lerpf(1.0, 0.6, (r - 1.0))))
	var cond := 1.0
	var cb: Variant = active.get("condition")
	if cb is Callable and (cb as Callable).is_valid():
		cond = clampf(float((cb as Callable).call(active)), 0.0, 1.0)
	var gps := float(GPS_PAY.get(str(active.get("gps", "route")), 1.0))
	var base := float(active.get("pay", 0))
	return {"pay": roundi(base * time * cond * gps), "base": int(base), "time": time, "condition": cond, "gps": gps}


func _needs(job: Dictionary) -> String:
	var cb: Variant = job.get("needs")
	if cb is Callable and (cb as Callable).is_valid():
		return str((cb as Callable).call(player))
	return ""


func _process(delta: float) -> void:
	if active.is_empty() or player == null or not is_instance_valid(player):
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var step := 0.2
	_timer = step
	var s := stop()
	if s.is_empty():
		return
	var vehicle: Variant = player.get("vehicle")
	var want: Variant = s.get("in_vehicle", true)
	var either := want == null
	var in_vehicle := (vehicle != null) if either else bool(want)
	var body: Node3D = (vehicle as Node3D) if in_vehicle and vehicle is Node3D else player
	var right_way := either or (vehicle != null) == in_vehicle
	var at: Vector3 = s["at"]
	var flat := Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length()
	var near := flat <= float(s.get("radius", 12.0))
	if not near and s.get("near") is Vector3:
		var n: Vector3 = s["near"]
		near = Vector2(body.global_position.x - n.x, body.global_position.z - n.z).length() <= float(s.get("near_radius", 0.0))
	if near and not right_way and _told != index and str(s.get("wrong_way", "")) != "":
		_told = index
		_title(str(s.get("name", "")), str(s["wrong_way"]))
	var speed := (body as RigidBody3D).linear_velocity.length() if body is RigidBody3D else (player.get("velocity") as Vector3).length() if player.get("velocity") is Vector3 else 0.0
	var inside := right_way and near and speed < STILL_SPEED
	if inside:
		var cb: Variant = s.get("check")
		if cb is Callable and (cb as Callable).is_valid() and not bool((cb as Callable).call(s, active)):
			inside = false
	_still = _still + step if inside else 0.0
	if inside and _held != index and str(s.get("holding", "")) != "":
		_held = index
		_title(str(s.get("name", "")), str(s["holding"]))
	if _still >= float(s.get("wait", 1.5)):
		_reach()


func _reach() -> void:
	_still = 0.0
	var s := stop()
	s["done"] = true
	var cb: Variant = s.get("on_reach")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(s, active)
	if active.is_empty():
		return # on_reach cancelled it
	stop_reached.emit(active, index)
	index += 1
	if index >= (active["stops"] as Array).size():
		_finish()
		return
	_point_gps()
	var nxt := stop()
	_title(str(nxt.get("name", "Next stop")), str(nxt.get("address", nxt.get("hint", ""))))


func _finish() -> void:
	var p := pay_now()
	var pay := int(p.get("pay", 0))
	var job := active
	active = {}
	_clear_gps(job)
	var gs := get_tree().root.get_node("GameState")
	gs.call("add_money", pay)
	gs.call("add_job_done", str(job.get("kind", "job")))
	var cb: Variant = job.get("on_finish")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(job, pay)
	finished.emit(job, pay)
	var how := ""
	if float(p.get("time", 1.0)) >= 1.1:
		how = "quick"
	elif float(p.get("time", 1.0)) < 0.9:
		how = "slow"
	_title("Job done: +%s" % CarModels.dollars(pay), ("%s, %s" % [str(job.get("title", "")), how]) if how != "" else str(job.get("title", "")))


func _point_gps() -> void:
	var gps := Gps.find(get_tree())
	var s := stop()
	if gps == null or s.is_empty():
		return
	var label := str(s.get("address", ""))
	if label == "":
		label = str(s.get("name", "Job"))
	gps.set_waypoint(s["at"], label, str(active.get("gps", "route")))
	gps.set_meta("job", true)


func _clear_gps(_job: Dictionary) -> void:
	var gps := Gps.find(get_tree())
	if gps != null and gps.has_meta("job"):
		gps.remove_meta("job")
		gps.clear()


func _title(t: String, sub: String) -> void:
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", t, sub)

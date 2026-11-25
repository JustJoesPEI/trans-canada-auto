class_name SupplyJobs
extends Node
## Building-supply runs for Delayed & Lost Trucking (docs/design.md section
## 6½): jobs of kind "supplies" for the crane truck (TruckModels
## "crane_truck", CraneTool). Pick up at one to three hardware stores (The
## House Depot, Hearth Hardware, Countess Auto), then drop at one to three
## real houses (Addresses): lumber on the lawn, pallets in the driveway,
## some set over the fence from the street.
##
## At each store the order waits on the ground at its loading spot (made
## as you come near): park within reach, put the legs down and lift it onto
## the deck. The stop's done once the store's loads are all on the deck.
## At each house a ring on the ground marks where the load goes; the
## stop's done once the right load sits there on the ground, upright and
## off the hook. The job's condition is the loads': each hard knock (a
## drop, a load sliding into the headboard) and each one left on its side
## takes some off the pay.
##
## A module of Economy: a Jobs source ("supplies"), offered by Delayed &
## Lost's dispatch window (Jobs.offers). Until that window is in the game,
## the crane truck at the yard keeps the orders itself: walk up to it, or
## sit in it, for a card of jobs.

## The stores' loading spots: where the order is set out (x, z), and the
## way the row of loads runs (degrees, 0 along +x). Found from the OSM
## buildings (data/city/chunks): each in the lot in front of the store.
const STORES := [
	{"name": "The House Depot", "at": Vector2(-2214.0, -3062.0), "row": 0.0},
	{"name": "Hearth Hardware", "at": Vector2(370.0, -2342.0), "row": 77.0},
	{"name": "Countess Auto", "at": Vector2(-1846.0, -3886.0), "row": -23.0},
]
## What goes to houses, and where it's set.
const ORDERS := [
	{"kind": "lumber", "where": "lawn"},
	{"kind": "lumber", "where": "fence"},
	{"kind": "pallet_bricks", "where": "driveway"},
	{"kind": "pallet_sacks", "where": "driveway"},
	{"kind": "pallet_boxes", "where": "driveway"},
	{"kind": "pallet_bricks", "where": "fence"},
]
const ZONE_RADIUS := 2.5 ## m: how close to the ring's middle a load must sit
const SPAWN_RANGE := 160.0 ## m: the order is set out once you're this close
const CLEAR_RANGE := 220.0 ## m: loads left behind go once you're this far off
const KNOCK := 3.5 ## m/s change in a step that counts as a knock
const KNOCK_COST := 0.12 ## of the pay, each knock
const TIPPED_COST := 0.25 ## of the pay, each load delivered on its side
const CLIENTS := ["Gallant", "MacLeod", "Arsenault", "Doiron", "MacPhee", "Gaudet", "Murphy", "Bernard", "MacKinnon", "Profitt"]

var economy: Economy
var jobs: Jobs
var _leftovers: Array[RigidBody3D] = []
var _markers := {} ## drop index -> its ring (MeshInstance3D)
var _tick := 0.0
static var _ring_mesh: ArrayMesh


func setup(e: Economy) -> void:
	economy = e
	jobs = e.jobs
	jobs.add_source("supplies", offers)
	jobs.started.connect(_on_started)
	jobs.finished.connect(func(job: Dictionary, _pay: int) -> void: _on_ended(job))
	jobs.cancelled.connect(_on_ended)
	_add_yard_counter.call_deferred()


# --- making jobs -------------------------------------------------------------------------

## Up to n supply jobs, starting from near `near`.
func offers(near: Vector3, n: int) -> Array:
	var out: Array = []
	if economy == null or economy.addresses == null:
		return out
	for i in n:
		var job := make_job(near)
		if not job.is_empty():
			out.append(job)
	return out


## One job: 1–3 stores, then 1–3 houses (at least one load from each store).
func make_job(near: Vector3, stores_n := 0, drops_n := 0) -> Dictionary:
	if stores_n <= 0:
		stores_n = [1, 1, 1, 2, 2, 3].pick_random()
	if drops_n <= 0:
		drops_n = randi_range(1, 3)
	drops_n = clampi(maxi(drops_n, stores_n), 1, 3)
	# The stores, nearest first from where you are, then each next nearest.
	var pool := STORES.duplicate()
	pool.shuffle()
	pool = pool.slice(0, stores_n)
	var route: Array = []
	var from := Vector2(near.x, near.z)
	while not pool.is_empty():
		var best: Dictionary = pool[0]
		for s: Dictionary in pool:
			if from.distance_to(s["at"]) < from.distance_to(best["at"]):
				best = s
		pool.erase(best)
		route.append(best)
		from = best["at"]
	# The loads, a house each, every store with at least one.
	var loads: Array = []
	var drops: Array = []
	var orders := ORDERS.duplicate()
	orders.shuffle()
	var used := {}
	var drop_from: Vector2 = from
	for j in drops_n:
		var o: Dictionary = orders[j % orders.size()]
		var a := {}
		for _try in 12:
			a = economy.addresses.pick(drop_from, 250.0, 2200.0, ["home"])
			if not a.is_empty() and not used.has(Addresses.text(a)) and (a["door"] as Vector2).distance_to(a["road"]) > 6.0:
				break
			a = {}
		if a.is_empty():
			continue
		used[Addresses.text(a)] = true
		var store: int = j % route.size()
		loads.append({"kind": str(o["kind"]), "store": store, "drop": drops.size(), "body": null, "delivered": false, "knocks": 0})
		drops.append({"address": a, "kind": str(o["kind"]), "where": str(o["where"]), "zone": zone_for(a, str(o["where"]))})
		drop_from = Vector2(a["x"], a["z"])
	if drops.is_empty():
		return {}
	var stops: Array = []
	var dist := Vector2(near.x, near.z).distance_to(route[0]["at"])
	var prev: Vector2 = route[0]["at"]
	for i in route.size():
		var s: Dictionary = route[i]
		dist += prev.distance_to(s["at"])
		prev = s["at"]
		var n := 0
		for l: Dictionary in loads:
			n += 1 if int(l["store"]) == i else 0
		stops.append({"name": "Load up", "address": str(s["name"]), "at": _ground(s["at"]), "radius": 18.0, "wait": 2.0,
			"store": i, "check": _loaded_check, "hint": _load_hint(n, n)})
	for d: Dictionary in drops:
		var a: Dictionary = d["address"]
		var road: Vector2 = a["road"]
		dist += prev.distance_to(road)
		prev = road
		stops.append({"name": _drop_name(d), "address": Addresses.text(a), "at": _ground(road), "radius": 20.0, "wait": 2.0,
			"drop": drops.find(d), "check": _dropped_check, "on_reach": _on_dropped, "hint": _drop_hint(d)})
	var first: Dictionary = drops[0]
	var what := _what(loads)
	var pay := clampi(roundi(300.0 + 140.0 * loads.size() + 0.2 * dist + 80.0 * (route.size() - 1)), 500, 1500)
	return {
		"kind": "supplies",
		"company": "Delayed & Lost",
		"title": "%s to %s" % [what, Addresses.text(first["address"])] if drops.size() == 1 else "%s to %d houses" % [what, drops.size()],
		"client": "%s, %s" % [CLIENTS.pick_random(), str(first["address"]["street"])],
		"line": "From %s. Crane truck." % " and ".join(PackedStringArray(route.map(func(s: Dictionary) -> String: return str(s["name"])))),
		"pay": pay,
		"estimate": dist / 8.0 + 150.0 * loads.size(),
		"gps": "route",
		"needs": needs,
		"condition": condition,
		"stops": stops,
		"data": {"stores": route, "drops": drops, "loads": loads, "spawned": {}},
	}


## Where a load goes at an address: a point on the way in from the street,
## far enough in to be off the road and within the crane's reach of a
## truck at the curb. Lumber on the lawn, pallets in the driveway, and
## "fence" as far in as the crane can set it.
static func zone_for(a: Dictionary, where: String) -> Vector2:
	var road: Vector2 = a["road"]
	var door: Vector2 = a["door"]
	var d := road.distance_to(door)
	var s := 0.0
	match where:
		"driveway":
			s = clampf(d * 0.5, 4.5, 6.5)
		"fence":
			s = clampf(d - 2.0, 6.5, 8.5)
		_:
			s = clampf(d - 3.0, 5.0, 7.5)
	s = minf(s, d - 1.5)
	return road + (door - road).normalized() * s


func _ground(p: Vector2, lift := 0.0) -> Vector3:
	var w := economy.world if economy != null else null
	if w != null and w.get("terrain") != null:
		return w.terrain.at(p, lift)
	return Vector3(p.x, lift, p.y)


static func _what(loads: Array) -> String:
	var lumber := 0
	var pallets := 0
	for l: Dictionary in loads:
		if str(l["kind"]) == "lumber":
			lumber += 1
		else:
			pallets += 1
	if pallets == 0:
		return "Lumber" if lumber == 1 else "%d bundles of lumber" % lumber
	if lumber == 0:
		return "A pallet" if pallets == 1 else "%d pallets" % pallets
	return "Lumber and pallets"


static func _drop_name(d: Dictionary) -> String:
	match str(d["where"]):
		"driveway":
			return "Drop in the driveway"
		"fence":
			return "Set over the fence"
	return "Drop on the lawn"


static func _drop_hint(d: Dictionary) -> String:
	var what := str(Cargo.KINDS[d["kind"]]["name"])
	match str(d["where"]):
		"fence":
			return "Too narrow to back in: set the %s over the fence onto the ring with the crane" % what
		"driveway":
			return "Set the %s in the ring in the driveway" % what
	return "Set the %s on the lawn, in the ring" % what


static func _load_hint(left: int, n: int) -> String:
	if left <= 0:
		return "All on: stow the crane and strap it down"
	if left == n:
		return "Legs down, then lift the order onto the deck (%d load%s)" % [n, "" if n == 1 else "s"]
	return "%d more to lift onto the deck" % left


## "" if the player can take a supply job now: in a crane truck, or with
## one close by (the yard's).
func needs(who: Node3D) -> String:
	if who == null:
		return ""
	var v: Variant = who.get("vehicle")
	if v is Car and (v as Car).tool is CraneTool:
		return ""
	for n in who.get_tree().get_nodes_in_group("vehicles"):
		var c := n as Car
		if c != null and c.tool is CraneTool and c.driver == null and c.global_position.distance_to(who.global_position) < 80.0:
			return ""
	return "You need a crane truck: Delayed & Lost has one at the yard on Riverside Drive"


## The loads' state: knocks and loads left on their side.
func condition(job: Dictionary) -> float:
	var c := 1.0
	for l: Dictionary in job["data"]["loads"]:
		c -= KNOCK_COST * int(l["knocks"])
		if bool(l.get("tipped", false)):
			c -= TIPPED_COST
	return clampf(c, 0.3, 1.0)


# --- the stops ---------------------------------------------------------------------------

func _loaded_check(stop: Dictionary, job: Dictionary) -> bool:
	var car := _truck()
	if car == null:
		stop["hint"] = "Come back in the crane truck"
		return false
	var on := {}
	for d: Dictionary in car.tie_downs.loads_on_deck():
		on[d["body"]] = true
	var n := 0
	var left := 0
	for l: Dictionary in job["data"]["loads"]:
		if int(l["store"]) != int(stop["store"]):
			continue
		n += 1
		var b: RigidBody3D = l["body"]
		if b == null or not is_instance_valid(b) or not on.has(b) or _on_hook(b):
			left += 1
	stop["hint"] = _load_hint(left, n)
	return left == 0 and _truck_stowed(car)


func _dropped_check(stop: Dictionary, job: Dictionary) -> bool:
	return _delivered_load(stop, job) != null


## The load sitting in a drop's ring, if there is one.
func _delivered_load(stop: Dictionary, job: Dictionary) -> RigidBody3D:
	var d: Dictionary = job["data"]["drops"][int(stop["drop"])]
	var zone: Vector2 = d["zone"]
	for l: Dictionary in job["data"]["loads"]:
		if bool(l["delivered"]) or str(l["kind"]) != str(d["kind"]):
			continue
		var b: RigidBody3D = l["body"]
		if b == null or not is_instance_valid(b):
			continue
		var p := b.global_position
		if Vector2(p.x, p.z).distance_to(zone) > ZONE_RADIUS or b.linear_velocity.length() > 0.3 or _on_hook(b) or not _on_ground(b):
			continue
		return b
	return null


func _on_dropped(stop: Dictionary, job: Dictionary) -> void:
	var b := _delivered_load(stop, job)
	for l: Dictionary in job["data"]["loads"]:
		if l["body"] == b and b != null:
			l["delivered"] = true
			l["tipped"] = b.global_basis.y.y < 0.85
	_hide_marker(stop)


## On the ground: nothing but the ground (or a wall, a curb) under it, not
## a deck.
func _on_ground(b: RigidBody3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(b.global_position + Vector3.UP * 0.3, b.global_position + Vector3.DOWN * 1.2, Layers.GROUND | Layers.VEHICLES | Layers.SOLID)
	q.exclude = [b.get_rid()]
	var hit := b.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and not (hit["collider"] is Car)


func _on_hook(b: RigidBody3D) -> bool:
	for n in get_tree().get_nodes_in_group("vehicles"):
		var c := n as Car
		if c != null and c.tool is CraneTool and (c.tool as CraneTool).hooked == b:
			return true
	return false


func _truck() -> Car:
	var p := economy.player if economy != null else null
	var v: Variant = p.get("vehicle") if p != null else null
	return v as Car if v is Car and (v as Car).tool is CraneTool else null


## Legs up and crane folded: ready to drive off.
static func _truck_stowed(car: Car) -> bool:
	return car.tool is CraneTool and (car.tool as CraneTool).stowed()


# --- the loads and the rings -------------------------------------------------------------

func _on_started(job: Dictionary) -> void:
	if str(job.get("kind", "")) != "supplies":
		return
	_clear_leftovers(true)


func _on_ended(job: Dictionary) -> void:
	if str(job.get("kind", "")) != "supplies":
		return
	for l: Dictionary in job["data"]["loads"]:
		var b: RigidBody3D = l["body"]
		if b != null and is_instance_valid(b):
			_leftovers.append(b)
	for k: int in _markers.keys():
		(_markers[k] as Node).queue_free()
	_markers.clear()


## Sets out a store's order on its loading spot.
func spawn_order(job: Dictionary, store: int) -> void:
	var data: Dictionary = job["data"]
	if (data["spawned"] as Dictionary).has(store):
		return
	data["spawned"][store] = true
	var s: Dictionary = data["stores"][store]
	var row := Vector2.from_angle(deg_to_rad(float(s["row"])))
	var mine: Array = (data["loads"] as Array).filter(func(l: Dictionary) -> bool: return int(l["store"]) == store)
	for i in mine.size():
		var l: Dictionary = mine[i]
		var at: Vector2 = s["at"] + row * (float(i) - (mine.size() - 1) * 0.5) * 2.4
		var c := Cargo.new()
		c.kind = str(l["kind"])
		c.name = "Supply_%s_%d" % [c.kind, i]
		var parent := economy.main if economy.main != null else self
		parent.add_child(c)
		# Lumber lies across the row, pallets square to it.
		c.global_transform = Transform3D(Basis(Vector3.UP, -row.angle()), _ground(at, 0.05))
		c.reset_physics_interpolation()
		c.start_parked()
		l["body"] = c
		l["v"] = Vector3.ZERO


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.5
	var p := economy.player if economy != null else null
	if p == null or not is_instance_valid(p):
		return
	var here := Vector2(p.global_position.x, p.global_position.z)
	_clear_leftovers(false)
	var job := jobs.active
	if job.is_empty() or str(job.get("kind", "")) != "supplies":
		return
	var data: Dictionary = job["data"]
	for i in (data["stores"] as Array).size():
		if here.distance_to(data["stores"][i]["at"]) < SPAWN_RANGE:
			spawn_order(job, i)
	# The ring at the next drop, once you're close.
	var s := jobs.stop()
	if s.has("drop") and here.distance_to(data["drops"][int(s["drop"])]["zone"]) < SPAWN_RANGE:
		_show_marker(s, data["drops"][int(s["drop"])]["zone"])


func _physics_process(_delta: float) -> void:
	var job := jobs.active if jobs != null else {}
	if job.is_empty() or str(job.get("kind", "")) != "supplies":
		return
	for l: Dictionary in job["data"]["loads"]:
		var b: RigidBody3D = l["body"]
		if b == null or not is_instance_valid(b) or bool(l["delivered"]) or b.freeze:
			continue
		var v := b.linear_velocity
		var before: Vector3 = l.get("v", v)
		l["v"] = v
		if (v - before).length() > KNOCK and Time.get_ticks_msec() - int(l.get("knocked", 0)) > 1000:
			l["knocks"] = int(l["knocks"]) + 1
			l["knocked"] = Time.get_ticks_msec()
			if economy.hud != null and economy.hud.has_method("show_title"):
				economy.hud.call("show_title", "Careful with that", "the %s took a knock" % (b as Cargo).display_name())


func _clear_leftovers(all: bool) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	for b in _leftovers.duplicate():
		if not is_instance_valid(b):
			_leftovers.erase(b)
			continue
		if all or cam == null or cam.global_position.distance_to(b.global_position) > CLEAR_RANGE:
			_leftovers.erase(b)
			b.queue_free()


func _show_marker(stop: Dictionary, zone: Vector2) -> void:
	var key := int(stop["drop"])
	if _markers.has(key):
		return
	var m := MeshInstance3D.new()
	m.name = "DropRing"
	m.mesh = ring_mesh()
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.visibility_range_end = 250.0
	add_child(m)
	m.global_position = _ground(zone, 0.06)
	_markers[key] = m


func _hide_marker(stop: Dictionary) -> void:
	var key := int(stop.get("drop", -1))
	if _markers.has(key):
		(_markers[key] as Node).queue_free()
		_markers.erase(key)


## The drop ring: a flat glowing band on the ground ZONE_RADIUS round, with
## four ticks pointing in. Built once.
static func ring_mesh() -> ArrayMesh:
	if _ring_mesh != null:
		return _ring_mesh
	var k := MeshKit.new()
	var segs := 32
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		k.quad(d0 * (ZONE_RADIUS - 0.18), d1 * (ZONE_RADIUS - 0.18), d1 * ZONE_RADIUS, d0 * ZONE_RADIUS, Vector3.UP)
	for i in 4:
		var d := Vector3.RIGHT.rotated(Vector3.UP, i * PI * 0.5)
		var side := d.cross(Vector3.UP) * 0.12
		k.quad(d * (ZONE_RADIUS - 0.8) - side, d * (ZONE_RADIUS - 0.8) + side, d * (ZONE_RADIUS - 0.2) + side, d * (ZONE_RADIUS - 0.2) - side, Vector3.UP)
	_ring_mesh = ModelLod.finish_kits([[k, Materials.get_shared().glow(Color(1.0, 0.62, 0.12), 1.4)]])
	return _ring_mesh


# --- the orders at the yard --------------------------------------------------------------

## Until Delayed & Lost's dispatch window is in the game, the yard's crane
## truck holds the orders: a counter at it, on foot or sitting in it.
func _add_yard_counter() -> void:
	if economy.get_node_or_null("DelayedLost") != null or economy.counters == null:
		return
	var w := economy.world
	if w == null or not w.has_method("yard_starts"):
		return
	for v: Dictionary in w.yard_starts():
		if str(v.get("model", "")) != "crane_truck":
			continue
		var at: Vector3 = (v["xform"] as Transform3D).origin
		economy.counters.add({"id": "supplies_orders", "title": "Supply orders", "subtitle": "Delayed & Lost: building supplies, crane truck",
			"at": at, "reach": 7.0, "on_foot": true, "in_car": true, "kind": "job_board", "map_name": "Delayed & Lost supply orders",
			"items": _order_items})
		return


func _order_items() -> Array:
	var out: Array = []
	var p := economy.player
	var near := p.global_position if p != null else Vector3.ZERO
	for job: Dictionary in offers(near, 3):
		var stores: Array = job["data"]["stores"]
		out.append({"id": "order_%d" % out.size(), "name": str(job["title"]), "note": "%s · pays about %s" % [str(job["line"]), CarModels.dollars(int(job["pay"]))],
			"price": 0, "action": func(_i: Dictionary) -> String:
				var why := jobs.start(job)
				if why != "":
					return why
				economy.counters.menu.close()
				return "On your way to %s" % str(stores[0]["name"])})
	if out.is_empty():
		out.append({"id": "none", "name": "No orders right now", "price": 0, "enabled": false, "why": "Try again in a bit."})
	return out

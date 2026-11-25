class_name DelayedLost
extends Node
## Delayed & Lost Trucking (docs/design.md section 6½), our Day & Ross, in
## the truck yard on Riverside Drive (map_config.json "work_yard"). An
## Economy module:
##
##   the dispatch window   a Counter at the yard (map: Jobs) listing jobs of
##                         the kinds in KINDS from Jobs.offers, each with its
##                         pay, how long, the truck and the client's line.
##                         Taking one lends the truck it needs, parked in a
##                         free bay, unless you're in one of your own (or one
##                         of the yard's) already. Bringing the lent truck back
##                         is the job's last stop; give the job up and it's
##                         towed back for RETURN_FEE.
##   tows                  a broken-down or badly parked car at a real
##                         address, winched onto the rollback and strapped,
##                         taken to the yard or the impound lot
##   freight               the hauler and a flatbed trailer of pallets (loaded
##                         at the yard, or load it yourself with the forklift
##                         for more), hauled to a big site; pay goes by the
##                         loads still on the trailer at the drop
##   the licence ladder    LICENCES: finished jobs of one kind
##                         (GameState.jobs_done) open the next. No XP.
##   the Surplus counter   the retired fleet (SURPLUS) for sale: yours for
##                         keeps (OwnedCars), parked in a bay
##
## Supply drops are another module's (a source of kind "supplies"); the
## window lists them like the rest. A job taken here may say "truck" (and
## "trailer"): the model it needs, lent if you're not in one; "prepare":
## Callable(job) -> String, run when it's taken (spawn what it needs; ""
## or why not). DelayedLost.licence_why(kind) says what's still locked.
##
## Places in the yard are metres [right, back] from its middle, facing its
## "direction", the same as map_config.json's work_yard entries.

const COMPANY := "Delayed & Lost"
## The kinds of job at the window, in the order they open.
const KINDS: Array[String] = ["tow", "supplies", "freight"]
## The licence ladder: a kind opens after `count` finished jobs of `after`.
const LICENCES := {
	"tow": {"after": "spuddash", "count": 3, "what": "SpudDash runs"},
	"supplies": {"after": "tow", "count": 3, "what": "tows"},
	"freight": {"after": "supplies", "count": 3, "what": "supply drops"},
}
## The fine for leaving a lent truck out when you give a job up.
const RETURN_FEE := 150
## The company's paint, by model, for lent trucks and the yard's fleet:
## white cabs with the navy-and-orange wordmark on the doors, like Day &
## Ross's, navy trailers.
const PAINT := {"hauler": "#f2f2ee", "rollback": "#f2f2ee", "flatbed_trailer": "#1d2f5e", "forklift": "#e3b21b"}
## The logo on each door: model -> [x (out from the middle), y, z] of the
## right door's logo (the left is mirrored), and its width in metres.
const DOOR_LOGO := {
	"hauler": [1.27, 1.85, -0.55, 1.15],
	"rollback": [1.19, 1.5, -2.05, 0.8],
}
## The retired fleet, for sale at the Surplus counter.
const SURPLUS := [
	{"model": "rollback", "price": 24000, "note": "Winch tested twice. Worked once."},
	{"model": "hauler", "price": 42000, "note": "1.2 million km, most of them on purpose."},
	{"model": "flatbed_trailer", "price": 9000, "note": "Deck's straight. Ish."},
	{"model": "forklift", "price": 6500, "note": "Beeps going forward too. No extra charge."},
]

## The window and the Surplus counter, and where to stand.
## (Clear of the lidar trees' trunks, in the drive aisles, like the
## yard's own vehicles.)
const WINDOW_AT := [-15.0, 10.0]
const SURPLUS_AT := [-15.0, 14.0]
## Bays for lent and sold trucks: [right, back, heading].
const BAYS := [[-4.0, -14.0, 0.0], [0.0, -12.0, 0.0], [4.0, -12.0, 0.0], [4.0, 0.0, 0.0], [8.0, 0.0, 0.0], [-14.0, 0.0, 0.0], [-18.0, -3.0, 0.0]]
## Where lent trucks come back to, and tows to the yard are dropped.
const RETURN_AT := [0.0, -5.0]
## How far from RETURN_AT counts as back in the yard (m).
const YARD_REACH := 45.0

## Big sites freight goes to: a name from data/city/locations.json or a
## [longitude, latitude], with the client and their line.
const SITES := [
	{"name": "Maritime Megastore", "place": "Maritime Megastore", "client": "Megastore receiving",
		"lines": ["Forty pallets of Back to School. It's November. Don't ask.", "Seasonal aisle. Which season? Yes."]},
	{"name": "Ervin's Marine Terminal", "lonlat": [-63.1127607, 46.241299], "client": "Ervin's Oil",
		"lines": ["Spare valves. Nothing's leaking. Probably.", "Drums of something. Label fell off. Drive gentle."]},
	{"name": "Red Shores Racetrack & Casino", "place": "Red Shores Racetrack & Casino", "client": "Red Shores",
		"lines": ["New seats for the grandstand. Old ones are a fire hazard and also on fire.", "Bingo supplies. Big night. Big, big night."]},
	{"name": "Charlatown Seaport", "place": "Charlatown Seaport Marina", "client": "The cruise terminal",
		"lines": ["Souvenir lobsters for the cruise ship. Ship leaves at four.", "Five hundred I Heart Charlatown mugs. Breakable. Obviously."]},
]
## Cars that need a tow (rollback payload 4.5 t: no big trucks).
const TOW_CARS := ["civique", "corollary", "cavalcade", "filly", "pious", "sole", "interlude", "grand_caravel", "roadmeister", "jaunt"]
const TOW_LINES := {
	"broken": [
		["Darlene", "Started making a noise like a goose, then stopped making any noise at all."],
		["Kevin", "It's broke down in front of my ex's house. Please hurry."],
		["Mrs. MacPhee", "My grandson says it's the alternator. My grandson is nine."],
		["Brent", "Check engine light's been on since 2019. Today it meant it."],
	],
	"parked": [
		["Bylaw Services", "Parked across three driveways since Tuesday. Bring it in."],
		["Gail next door", "Someone's on my tulips. Again."],
		["Strata council", "Visitor parking means visitors, Gerald."],
	],
}
const LOAD_KINDS := ["pallet_boxes", "pallet_bricks", "pallet_sacks", "crate", "lumber"]

var economy: Economy
var jobs: Jobs
var counters: Counters
var yard := Transform3D.IDENTITY ## the yard's middle, facing its direction
var _board: Array = [] ## offers on the window now
var _board_age := 0.0
var _collect: Array = [] ## lent trucks and leftovers to take away once you're clear of them
var _logo_timer := 0.0
static var _logo_mesh: QuadMesh
static var _logo_mat: StandardMaterial3D
static var _board_mesh: QuadMesh


## `v` as a Car, or null if it isn't one or it's been freed.
static func _car(v: Variant) -> Car:
	return v as Car if is_instance_valid(v) and v is Car else null


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


static func find(tree: SceneTree) -> DelayedLost:
	return tree.get_first_node_in_group("delayed_lost") as DelayedLost if tree != null else null


## "" if `kind` is open at the window, else what it still needs ("3 tows
## first: 1 done").
static func licence_why(kind: String) -> String:
	var l: Dictionary = LICENCES.get(kind, {})
	if l.is_empty():
		return ""
	var done := int(_gs().call("jobs_done_count", str(l["after"])))
	if done >= int(l["count"]):
		return ""
	return "%d %s first (%d done)" % [int(l["count"]), str(l["what"]), done]


func _ready() -> void:
	add_to_group("delayed_lost")


func setup(e: Economy) -> void:
	economy = e
	jobs = e.jobs
	counters = e.counters
	var w := e.world
	if w != null and w.data != null and w.data.config.get("work_yard") is Dictionary:
		var y: Dictionary = w.data.config["work_yard"]
		var c: Array = y["pos"]
		var g := w.data.projection.to_ground(float(c[0]), float(c[1]))
		yard = Transform3D(Basis(Vector3.UP, -deg_to_rad(float(y.get("direction", 0.0)))), w.terrain.at(g, 0.0))
	jobs.add_source("tow", _tow_offers)
	jobs.add_source("freight", _freight_offers)
	jobs.finished.connect(func(j: Dictionary, _pay: int) -> void: _on_job_ended(j, false))
	jobs.cancelled.connect(func(j: Dictionary) -> void: _on_job_ended(j, true))
	counters.add({"id": "delayed_lost_dispatch", "title": "Delayed & Lost dispatch", "subtitle": "Tows, supply drops and freight. Trucks lent.",
		"map_name": "Delayed & Lost Trucking", "at": point(WINDOW_AT), "reach": 6.0, "on_foot": true, "in_car": true, "kind": "job_board",
		"prompt": "Delayed & Lost dispatch", "items": _dispatch_items})
	counters.add({"id": "delayed_lost_surplus", "title": "Delayed & Lost Surplus", "subtitle": "Retired fleet. As described, mostly.",
		"map_name": "Delayed & Lost Surplus", "at": point(SURPLUS_AT), "reach": 3.0, "kind": "dealer", "items": _surplus_items})
	_booth(WINDOW_AT, "DISPATCH")
	_booth(SURPLUS_AT, "SURPLUS SALES")


## A post with a window and the company's board over it, at a counter:
## the impound lot's pay machine (one shared mesh) with the logo on both
## sides of its board and the counter's word under it, its front to the
## yard's middle aisle.
func _booth(at: Array, word: String) -> void:
	var root := Node3D.new()
	root.name = "Booth_" + word.replace(" ", "_")
	add_child(root)
	root.global_transform = Transform3D(yard.basis.rotated(Vector3.UP, -PI * 0.5), point(at))
	var mi := MeshInstance3D.new()
	mi.mesh = PoliceProps.kiosk_mesh()
	WorldLod.limit(mi, 2.0)
	root.add_child(mi)
	# The board is 1.6 by 0.62, 0.05 thick, at z 0.1: covered on both sides.
	if _board_mesh == null:
		_board_mesh = QuadMesh.new()
		_board_mesh.size = Vector2(1.61, 0.63)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load("res://textures/signs/delayed_lost_board.png")
		mat.roughness = 0.5
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_board_mesh.material = mat
	for side: float in [-1.0, 1.0]:
		var logo := MeshInstance3D.new()
		logo.mesh = _board_mesh
		logo.position = Vector3(0, 2.25, 0.1 + side * 0.027)
		logo.rotation.y = 0.0 if side > 0.0 else PI
		logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		logo.visibility_range_end = 80.0
		root.add_child(logo)
	var l := Label3D.new()
	l.text = word
	PoliceGear._style(l, 0.045, Color(0.95, 0.95, 0.9))
	l.position = Vector3(0, 1.36, -0.21)
	l.rotation.y = PI
	l.visibility_range_end = 30.0
	root.add_child(l)


# --- the yard ---------------------------------------------------------------------------------

## A place in the yard ([right, back]) in the town, on the ground.
func point(at: Array, lift := 0.0) -> Vector3:
	var p := yard * Vector3(float(at[0]), 0.0, float(at[1]))
	return _ground(Vector2(p.x, p.z), lift) if economy != null and economy.world != null else p + Vector3.UP * lift


func bay_xform(i: int, lift := 0.35) -> Transform3D:
	var b: Array = BAYS[i]
	return Transform3D(yard.basis.rotated(Vector3.UP, -deg_to_rad(float(b[2]))), point([b[0], b[1]], lift))


func _ground(p: Vector2, lift := 0.0) -> Vector3:
	var w := economy.world if economy != null else null
	if w != null and w.terrain != null:
		return w.terrain.at(p, lift)
	return Vector3(p.x, lift, p.y)


## The first bay with nothing parked in it (-1 if they're all taken). A
## truck put in one this frame isn't in the physics yet: `taken` lists
## bays to skip.
func free_bay(taken: Array = []) -> int:
	var space := get_viewport().world_3d.direct_space_state if get_viewport() != null else null
	for i in BAYS.size():
		if taken.has(i):
			continue
		if space == null:
			return i
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.2, 2.0, 11.0)
		q.shape = box
		q.collision_mask = Layers.VEHICLES | Layers.CARGO
		var xf := bay_xform(i, 1.3)
		q.transform = xf
		if space.intersect_shape(q, 1).is_empty():
			return i
	return -1


## Puts a company vehicle (model, in the company paint) in bay `i`.
func spawn_truck(model: String, i: int, paint := "") -> Car:
	var car := Car.new()
	car.model_id = model
	car.paint = Color.html(paint if paint != "" else str(PAINT.get(model, CarModels.get_model(model)["colours"][0])))
	car.name = "DelayedLost_%s_%d" % [model, Time.get_ticks_msec()]
	var main := economy.main if economy != null and economy.main != null else self
	main.add_child(car)
	car.global_transform = bay_xform(i, 0.35 if model != "flatbed_trailer" else 0.6)
	car.reset_physics_interpolation()
	if main.get("cars") is Array:
		(main.get("cars") as Array).append(car)
	if main.has_method("_watch_straps"):
		main.call("_watch_straps", car)
	if not Car.ground_below(car):
		car.start_parked()
	add_logo(car)
	return car


## The company logo on a truck's doors (DOOR_LOGO), once.
func add_logo(car: Car) -> void:
	if car.has_meta("dl_logo") or not DOOR_LOGO.has(car.model_id):
		return
	car.set_meta("dl_logo", true)
	var d: Array = DOOR_LOGO[car.model_id]
	for s: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.name = "DoorLogo"
		mi.mesh = _logo()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * float(d[3])
		mi.position = Vector3(s * float(d[0]), float(d[1]), float(d[2]))
		# The quad faces +Z; turn it to face out of its side.
		mi.rotation.y = s * PI * 0.5
		mi.visibility_range_end = 60.0
		car.add_child(mi)


## The logo picture on a quad (1 m by 0.5, facing +Z), one for every use.
static func _logo() -> QuadMesh:
	if _logo_mesh == null:
		_logo_mesh = QuadMesh.new()
		_logo_mesh.size = Vector2(1.0, 0.5)
		_logo_mat = StandardMaterial3D.new()
		_logo_mat.albedo_texture = load("res://textures/signs/delayed_lost_door.png")
		_logo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_logo_mat.roughness = 0.45
		_logo_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_logo_mesh.material = _logo_mat
	return _logo_mesh


func _process(delta: float) -> void:
	_board_age += delta
	_logo_timer -= delta
	if _logo_timer <= 0.0:
		_logo_timer = 1.0
		_fleet_logos()
		_collect_left()


## The yard's own trucks (Main's "Yard_" vehicles) wear the logo too.
func _fleet_logos() -> void:
	var main := economy.main if economy != null else null
	if main == null or not (main.get("cars") is Array):
		return
	for c: Variant in main.get("cars"):
		var car := _car(c)
		if car != null and is_instance_valid(car) and str(car.name).begins_with("Yard_") and not car.has_meta("dl_logo"):
			car.set_meta("dl_fleet", true)
			add_logo(car)


## Takes away lent trucks and leftover loads once you're out of them and
## clear of them (or they're somewhere you can't see them go).
func _collect_left() -> void:
	var p := economy.player if economy != null else null
	for v: Variant in _collect.duplicate():
		if v == null or not is_instance_valid(v):
			_collect.erase(v)
			continue
		var n := v as Node3D
		if p != null and (p.get("vehicle") == n or (n is Car and (n as Car).towed_by != null and p.get("vehicle") == (n as Car).towed_by)):
			continue
		if p != null and p.global_position.distance_to(n.global_position) < 40.0:
			continue
		_collect.erase(n)
		remove_body(n)


## Takes a vehicle or load out of the town, letting go of anything holding it.
func remove_body(n: Node3D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var main := economy.main if economy != null else null
	var cars: Array = main.get("cars") if main != null and main.get("cars") is Array else []
	for c: Variant in cars:
		var car := _car(c)
		if car == null or not is_instance_valid(car) or car == n:
			continue
		if n is RigidBody3D and car.tie_downs != null and car.tie_downs.has(n as RigidBody3D):
			car.tie_downs.release(n as RigidBody3D)
		if car.tool is RollbackTool and (car.tool as RollbackTool).hooked == n:
			car.tool.hitch_action()
		if car.towing == n:
			Coupling.uncouple(car)
	if n is Car:
		var car := n as Car
		if car.towing != null:
			Coupling.uncouple(car)
		if car.tie_downs != null:
			car.tie_downs.release_all()
		cars.erase(car)
	n.queue_free()


# --- the dispatch window ----------------------------------------------------------------------

func _dispatch_items() -> Array:
	if _board.is_empty() or _board_age > 300.0:
		_board = jobs.offers(KINDS, yard.origin, 3)
		_board_age = 0.0
	var out: Array = []
	for k: String in KINDS:
		var why := licence_why(k)
		if why != "":
			out.append({"id": "locked_" + k, "name": "%s: locked" % _kind_name(k), "note": "Your %s licence: %s." % [_kind_name(k).to_lower(), why],
				"enabled": false, "why": "Not yet: %s." % why, "why_short": "Locked"})
	for job: Dictionary in _board:
		var k := str(job.get("kind", ""))
		if licence_why(k) != "":
			continue
		var truck := str(job.get("truck", ""))
		var bits: Array[String] = []
		bits.append("Pays about %s" % CarModels.dollars(int(job.get("pay", 0))))
		bits.append("%d min" % maxi(1, roundi(float(job.get("estimate", 300.0)) / 60.0)))
		if truck != "":
			bits.append(CarModels.full_name(truck) + (" and trailer" if job.has("trailer") else ""))
		var note := " · ".join(bits)
		if str(job.get("line", "")) != "":
			note += "\n%s: \"%s\"" % [str(job.get("client", "Client")), str(job["line"])]
		out.append({"id": "job_%d" % out.size(), "name": str(job.get("title", "Job")), "note": note, "price": -1,
			"price_text": "+" + CarModels.dollars(int(job.get("pay", 0))), "job": job, "action": _take_item})
	if out.size() == 0 or _board.is_empty():
		out.append({"id": "none", "name": "Nothing on the board", "note": "Check back in a bit.", "enabled": false, "why": "Nothing on right now."})
	out.append({"id": "refresh", "name": "Ask for other work", "note": "Dispatch shuffles the clipboard.", "price": -1, "price_text": "", "action": func(_i: Dictionary) -> String:
		_board = []
		return "\"Let me see what's fallen behind the radiator.\""})
	return out


func _take_item(item: Dictionary) -> String:
	var job: Dictionary = item["job"]
	var why := take(job)
	if why != "":
		return why
	_board.erase(job)
	counters.menu.close()
	return ""


static func _kind_name(k: String) -> String:
	return {"tow": "Tows", "supplies": "Supply drops", "freight": "Freight", "spuddash": "SpudDash"}.get(k, k.capitalize())


## Takes a job from the window: lends the truck it needs (unless you're in
## one), gets it ready and starts it. "" if it started, else why not.
func take(offer: Dictionary) -> String:
	var kind := str(offer.get("kind", ""))
	var locked := licence_why(kind)
	if locked != "":
		return "Your licence doesn't cover that yet: %s." % locked
	if not jobs.active.is_empty():
		return "You're already on a job: %s. Finish it or cancel it on the map first." % jobs.active.get("title", "")
	var job := offer.duplicate(true)
	var data: Dictionary = job.get("data", {})
	job["data"] = data
	var loans: Array = []
	data["loans"] = loans
	var p := economy.player if economy != null else null
	var in_car: Car = p.get("vehicle") as Car if p != null else null
	var truck := str(job.get("truck", ""))
	if truck != "":
		if in_car != null and in_car.model_id == truck and (in_car.garage_id != "" or in_car.has_meta("dl_fleet") or in_car.has_meta("dl_loan")):
			if in_car.garage_id == "":
				# One of the company's: it comes back at the end.
				loans.append(in_car)
		else:
			var bay := free_bay()
			if bay < 0:
				return "Every bay in the yard's full: move a truck out of the way first."
			var t := spawn_truck(truck, bay)
			t.set_meta("dl_loan", true)
			loans.append(t)
			data["bay"] = bay
	if str(job.get("trailer", "")) != "":
		var bay := free_bay([data.get("bay", -1)])
		if bay < 0:
			_drop(loans)
			return "No bay free for the trailer: move a truck out of the way first."
		var tr := spawn_truck(str(job["trailer"]), bay)
		tr.set_meta("dl_loan", true)
		loans.append(tr)
		data["trailer"] = tr
	var prep: Variant = job.get("prepare")
	if prep is Callable and (prep as Callable).is_valid():
		var err := str((prep as Callable).call(job))
		if err != "":
			_drop(loans)
			_drop(data.get("spawned", []))
			return err
	_lend_stops(job, loans, in_car)
	var orig_needs: Variant = job.get("needs")
	job["needs"] = func(who: Node3D) -> String:
		for l: Variant in loans:
			if is_instance_valid(l) and l is Car:
				return ""
		return str((orig_needs as Callable).call(who)) if orig_needs is Callable and (orig_needs as Callable).is_valid() else ""
	var why := jobs.start(job)
	if why != "":
		_drop(loans)
		_drop(data.get("spawned", []))
		return why
	return ""


## A lent truck adds a first stop (get in it) and a last (bring it back).
func _lend_stops(job: Dictionary, loans: Array, in_car: Car) -> void:
	var stops: Array = job["stops"]
	var cab: Car = null
	for l: Variant in loans:
		var c := _car(l)
		if c != null and bool(CarModels.get_model(c.model_id)["shape"].get("drivable", true)):
			cab = c
			break
	if cab != null and cab != in_car:
		stops.push_front({"name": "Get in the truck", "address": "Delayed & Lost yard", "at": cab.global_position, "radius": 8.0, "wait": 0.3,
			"hint": "The %s in the yard" % cab.display_name(),
			"check": func(_s: Dictionary, _j: Dictionary) -> bool: return economy.player.get("vehicle") == cab})
	if loans.is_empty():
		return
	var back := point(RETURN_AT)
	var returned := func(_s: Dictionary, _j: Dictionary) -> bool:
		for l: Variant in loans:
			if is_instance_valid(l) and l is Node3D and (l as Node3D).global_position.distance_to(back) > YARD_REACH:
				return false
		return true
	var last: Dictionary = stops[stops.size() - 1]
	if (last["at"] as Vector3).distance_to(back) < YARD_REACH:
		# The job ends at the yard anyway: bringing the truck back is that stop.
		var check0: Variant = last.get("check")
		last["check"] = func(s: Dictionary, j: Dictionary) -> bool:
			return returned.call(s, j) and (not (check0 is Callable) or bool((check0 as Callable).call(s, j)))
		return
	stops.append({"name": "Bring the truck back", "address": "Delayed & Lost yard", "at": back, "radius": 22.0, "wait": 1.0,
		"hint": "Park it in the yard" + (" with the trailer" if job.has("trailer") else ""), "check": returned})


func _drop(list: Array) -> void:
	for n: Variant in list:
		if is_instance_valid(n) and n is Node3D and not (n as Node3D).has_meta("dl_fleet"):
			remove_body(n as Node3D)


## A job ended (finished or given up): lent trucks go back, the yard's own
## stay; given up with a lent truck out of the yard, it's towed back for a fee.
func _on_job_ended(job: Dictionary, cancelled: bool) -> void:
	var data: Dictionary = job.get("data", {})
	if not data.has("loans"):
		return
	var fee := false
	for l: Variant in data["loans"]:
		var c := _car(l)
		if c == null or not is_instance_valid(c):
			continue
		if cancelled and c.global_position.distance_to(point(RETURN_AT)) > YARD_REACH:
			fee = true
		if not c.has_meta("dl_fleet"):
			_collect.append(c)
	for n: Variant in data.get("spawned", []):
		if is_instance_valid(n) and n is Node3D:
			_collect.append(n)
	if fee:
		var gs := _gs()
		var take_off := mini(RETURN_FEE, int(gs.get("money")))
		gs.call("add_money", -take_off)
		if economy.hud != null and economy.hud.has_method("show_title"):
			economy.hud.call("show_title", "Truck towed back to the yard", "%s: -%s" % [COMPANY, CarModels.dollars(RETURN_FEE)])


# --- tows --------------------------------------------------------------------------------------

func _tow_offers(near: Vector3, n: int) -> Array:
	var out: Array = []
	var from := Vector2(near.x, near.z)
	for i in n:
		var a := economy.addresses.pick(from, 300.0, 1800.0, ["home", "business", "apartments"]) if economy.addresses != null else {}
		if a.is_empty():
			break
		out.append(tow_job(a, randf() < 0.6, randf() < 0.35))
	return out


## A tow from address `a`: a car broken down at the curb, or badly parked
## half on the lawn; to the yard, or (`impound`) the impound lot.
func tow_job(a: Dictionary, broken: bool, impound: bool) -> Dictionary:
	var model: String = TOW_CARS.pick_random()
	if not CarModels.has_model(model):
		model = "civique"
	var who: Array = (TOW_LINES["broken" if broken else "parked"] as Array).pick_random()
	var lot := ImpoundLot.find(get_tree())
	if lot == null:
		impound = false
	if not broken and lot != null:
		impound = true
	var drop := point(RETURN_AT)
	var drop_name := "Delayed & Lost yard"
	if impound:
		drop = (lot.call("_release_spot") as Transform3D).origin if lot.has_method("_release_spot") else lot.machine_xform.origin
		drop_name = "the impound lot"
	var pick := Vector3(float(a["road"].x), 0.0, float(a["road"].y))
	var dist := Vector2(yard.origin.x, yard.origin.z).distance_to(Vector2(pick.x, pick.z)) + Vector2(pick.x, pick.z).distance_to(Vector2(drop.x, drop.z))
	var pay := clampi(roundi((380.0 + dist * 0.3) / 10.0) * 10 + (80 if impound else 0), 450, 1300)
	var where := Addresses.text(a)
	var car_name := CarModels.full_name(model)
	var data := {"address": a, "model": model, "broken": broken, "knocks": 0.0}
	return {
		"kind": "tow", "company": COMPANY, "truck": "rollback",
		"title": ("Tow a broken-down %s from %s" if broken else "Tow a badly parked %s from %s") % [car_name, where],
		"client": who[0], "line": who[1], "pay": pay, "estimate": 200.0 + dist / 8.0, "gps": "route", "data": data,
		"needs": func(p: Node3D) -> String:
			var v: Variant = p.get("vehicle") if p != null else null
			return "" if v is Car and (v as Car).model_id == "rollback" else "You need a rollback: Delayed & Lost lends one at the yard.",
		"prepare": _prepare_tow,
		"condition": func(j: Dictionary) -> float:
			return clampf(1.0 - float(j["data"].get("knocks", 0.0)), 0.4, 1.0),
		"stops": [
			{"name": "Pick up the %s" % car_name, "address": where, "at": pick, "radius": 16.0, "wait": 1.5,
				"hint": "Deck down (G), hook the winch (T), winch it on (Y), strap it (B), deck up (R)",
				"check": func(_s: Dictionary, j: Dictionary) -> bool: return car_loaded(j)},
			{"name": "Drop it at %s" % drop_name, "address": drop_name, "at": drop, "radius": 20.0, "wait": 1.5,
				"hint": "Park; the crew takes it off",
				"check": func(_s: Dictionary, j: Dictionary) -> bool: return car_loaded(j),
				"on_reach": func(_s: Dictionary, j: Dictionary) -> void:
					var c: Variant = j["data"].get("car")
					if is_instance_valid(c) and c is Node3D:
						remove_body(c as Node3D)},
		],
	}


## Puts the car to tow at its address: at the curb with its hazards on (it
## won't start), or half up on the lawn at an angle.
func _prepare_tow(job: Dictionary) -> String:
	var data: Dictionary = job["data"]
	var a: Dictionary = data["address"]
	var road: Vector2 = a["road"]
	var door: Vector2 = a["door"]
	var into := (door - road).normalized()
	var along := Vector2(-into.y, into.x)
	var half := 4.0
	var w := economy.world if economy != null else null
	if w != null and w.network != null:
		var near := w.network.nearest_on_streets(road, 30.0)
		if not near.is_empty():
			road = near["pos"]
			along = near["dir"]
			half = (near["edge"] as RoadNetwork.RoadEdge).half_width
			into = Vector2(-along.y, along.x) if Vector2(-along.y, along.x).dot(door - road) > 0.0 else Vector2(along.y, -along.x)
	var broken := bool(data["broken"])
	var at := road + into * (half - 1.2 if broken else half + 1.8)
	var dir := along
	if not broken:
		dir = along.rotated(deg_to_rad(randf_range(18.0, 32.0)) * (1.0 if randf() < 0.5 else -1.0))
	var car := Car.new()
	car.model_id = str(data["model"])
	var colours: Array = CarModels.get_model(car.model_id)["colours"]
	car.paint = Color.html(str(colours.pick_random()))
	car.owner_id = "tow_job" # locked: it's somebody else's
	car.name = "TowJob_%s" % car.model_id
	var main := economy.main if economy != null and economy.main != null else self
	main.add_child(car)
	car.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), _ground(at, 0.4))
	car.reset_physics_interpolation()
	if main.get("cars") is Array:
		(main.get("cars") as Array).append(car)
	car.stalled = broken
	car.start_parked()
	car.crashed.connect(func(speed: float) -> void:
		if speed > 3.0:
			data["knocks"] = float(data.get("knocks", 0.0)) + (speed - 3.0) * 0.04)
	data["car"] = car
	data["spawned"] = [car]
	(job["stops"] as Array)[0]["at"] = car.global_position
	return ""


## The car to tow is up on a rollback's deck, strapped, and the deck's up.
func car_loaded(job: Dictionary) -> bool:
	var c: Variant = job["data"].get("car")
	if _car(c) == null:
		return false
	var main := economy.main if economy != null else null
	for t: Variant in (main.get("cars") if main != null and main.get("cars") is Array else []):
		var truck := _car(t)
		if truck != null and is_instance_valid(truck) and truck.tie_downs != null and truck.tie_downs.has(c as RigidBody3D):
			return not (truck.tool is RollbackTool) or (truck.tool as RollbackTool).deck < 0.05
	return false


# --- freight -----------------------------------------------------------------------------------

func _freight_offers(near: Vector3, n: int) -> Array:
	var out: Array = []
	var sites := SITES.duplicate()
	sites.shuffle()
	for s: Dictionary in sites.slice(0, n):
		var at := site_point(s)
		if at == Vector3.INF:
			continue
		out.append(freight_job(s, at, randf() < 0.35))
	return out


## Where a site's drop is: on the street nearest the place.
func site_point(s: Dictionary) -> Vector3:
	var g := Vector2.INF
	var w := economy.world if economy != null else null
	if s.has("lonlat") and w != null and w.data != null:
		g = w.data.projection.to_ground(float(s["lonlat"][0]), float(s["lonlat"][1]))
	elif s.has("place"):
		g = _location(str(s["place"]))
	if g == Vector2.INF:
		return Vector3.INF
	if w != null and w.network != null:
		var near := w.network.nearest_on_streets(g, 250.0)
		if not near.is_empty():
			g = near["pos"]
	return _ground(g)


static var _locations := {}


func _location(name: String) -> Vector2:
	if _locations.is_empty():
		var f := FileAccess.open("res://data/city/locations.json", FileAccess.READ)
		if f != null:
			var j: Variant = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				for l: Dictionary in (j as Dictionary).get("locations", []):
					_locations[str(l["name"])] = Vector2(float(l["x"]), float(l["z"]))
	return _locations.get(name, Vector2.INF)


## A haul to site `s` (at `at`): the hauler and a company trailer, loaded
## at the yard, or loaded by you with the forklift (`self_load`) for more.
func freight_job(s: Dictionary, at: Vector3, self_load: bool) -> Dictionary:
	var dist := Vector2(yard.origin.x, yard.origin.z).distance_to(Vector2(at.x, at.z))
	var count := randi_range(2, 4)
	var pay := clampi(roundi((520.0 + dist * 0.32 + count * 40.0) * (1.15 if self_load else 1.0) / 10.0) * 10, 500, 1500)
	var data := {"site": s["name"], "count": count, "self_load": self_load}
	return {
		"kind": "freight", "company": COMPANY, "truck": "hauler", "trailer": "flatbed_trailer",
		"title": "%d loads to %s%s" % [count, s["name"], " (load it yourself)" if self_load else ""],
		"client": s["client"], "line": (s["lines"] as Array).pick_random(), "pay": pay,
		"estimate": 150.0 + (120.0 if self_load else 0.0) + dist * 2.0 / 9.0, "gps": "route", "data": data,
		"needs": func(p: Node3D) -> String:
			var v: Variant = p.get("vehicle") if p != null else null
			return "" if v is Car and (v as Car).model_id == "hauler" else "You need a hauler: Delayed & Lost lends one at the yard.",
		"prepare": _prepare_freight,
		"condition": func(j: Dictionary) -> float:
			var c := int(j["data"].get("count", 1))
			return float(j["data"].get("delivered", loads_on(j))) / float(maxi(1, c)),
		"stops": [
			{"name": "Hook up the trailer" + (" and load it" if self_load else ""), "address": "Delayed & Lost yard", "at": point(RETURN_AT), "radius": 40.0, "wait": 1.0,
				"hint": ("Forklift the %d loads beside it onto the trailer, " % count if self_load else "") + "back under the trailer (it couples), strap the load (B)",
				"check": func(_s: Dictionary, j: Dictionary) -> bool: return hooked_up(j) and loads_on(j, true) >= int(j["data"]["count"])},
			{"name": "Deliver to %s" % s["name"], "address": str(s["name"]), "at": at, "radius": 25.0, "wait": 1.5,
				"hint": "Pull up with the trailer; their forklift takes the loads off",
				"check": func(_s: Dictionary, j: Dictionary) -> bool: return hooked_up(j),
				"on_reach": func(_s: Dictionary, j: Dictionary) -> void:
					j["data"]["delivered"] = loads_on(j)
					for l: Node3D in _job_loads(j):
						if _on_trailer(j, l):
							remove_body(l)},
		],
	}


## The trailer and its loads: on its deck, or (self_load) on the ground
## beside it, ready for the forklift.
func _prepare_freight(job: Dictionary) -> String:
	var data: Dictionary = job["data"]
	var tr := _car(data.get("trailer"))
	if tr == null:
		return "No trailer to load."
	var count := int(data["count"])
	var loads: Array = []
	var main := economy.main if economy != null and economy.main != null else self
	var xf := tr.global_transform
	for i in count:
		var c := Cargo.new()
		c.kind = LOAD_KINDS[randi() % (LOAD_KINDS.size() - 1)] if i % 2 == 0 else "pallet_boxes"
		c.name = "Freight_%s_%d" % [c.kind, i]
		main.add_child(c)
		var z := -4.5 + 3.0 * i
		if bool(data["self_load"]):
			c.global_transform = Transform3D(xf.basis, xf * Vector3(-3.4, 0.05, z))
		else:
			c.global_transform = Transform3D(xf.basis, xf * Vector3(0.0, 1.55, z))
		c.reset_physics_interpolation()
		if not Car.ground_below(c):
			c.start_parked()
		if main.get("loads") is Array:
			(main.get("loads") as Array).append(c)
		loads.append(c)
	data["loads"] = loads
	data["spawned"] = loads
	(job["stops"] as Array)[0]["at"] = tr.global_position
	return ""


func _job_loads(job: Dictionary) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for l: Variant in job["data"].get("loads", []):
		if is_instance_valid(l) and l is Node3D:
			out.append(l)
	return out


## The job's trailer is coupled to a truck the player's driving.
func hooked_up(job: Dictionary) -> bool:
	var tr := _car(job["data"].get("trailer"))
	return tr != null and is_instance_valid(tr) and tr.towed_by != null and economy.player.get("vehicle") == tr.towed_by


func _on_trailer(job: Dictionary, l: Node3D) -> bool:
	var tr := _car(job["data"].get("trailer"))
	if tr == null or not is_instance_valid(tr):
		return false
	var local := tr.global_transform.affine_inverse() * l.global_position
	return absf(local.x) < 1.6 and absf(local.z) < 8.0 and local.y > 0.9 and local.y < 3.5


## How many of the job's loads are on its trailer (strapped, if `strapped`).
func loads_on(job: Dictionary, strapped := false) -> int:
	var tr := _car(job["data"].get("trailer"))
	var n := 0
	for l in _job_loads(job):
		if _on_trailer(job, l) and (not strapped or (tr.tie_downs != null and tr.tie_downs.has(l as RigidBody3D))):
			n += 1
	return n


# --- the Surplus counter -----------------------------------------------------------------------

func _surplus_items() -> Array:
	var out: Array = []
	var gs := _gs()
	var bay := free_bay()
	for s: Dictionary in SURPLUS:
		var m := str(s["model"])
		var item := {"id": m, "name": CarModels.full_name(m), "note": "%s %s" % [str(CarModels.get_model(m).get("kind", "")), str(s["note"])], "price": int(s["price"]),
			"action": func(_i: Dictionary) -> String: return _sell(m, int(s["price"]))}
		if not bool(gs.call("has_space")):
			item["enabled"] = false
			item["why"] = "No room for another: you can keep %d vehicle%s. Sell one, or get a parkade spot." % [int(gs.call("storage_spaces")), "" if int(gs.call("storage_spaces")) == 1 else "s"]
			item["why_short"] = "No room"
		elif bay < 0:
			item["enabled"] = false
			item["why"] = "Every bay's full: move a truck out of the way first."
			item["why_short"] = "Bays full"
		out.append(item)
	return out


func _sell(model: String, price: int) -> String:
	var bay := free_bay()
	if bay < 0:
		_gs().call("add_money", price)
		return "Every bay's full: move a truck out of the way first. (Refunded.)"
	var car := spawn_truck(model, bay)
	car.owner_id = str(economy.main.get("LOCAL_PLAYER_ID")) if economy.main != null and economy.main.get("LOCAL_PLAYER_ID") != null else "local"
	var owned := economy.owned_cars
	if owned != null:
		owned.adopt(car)
	return "Sold! It's in bay %d. Keys are in it. Probably." % (bay + 1)

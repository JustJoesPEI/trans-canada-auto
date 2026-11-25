class_name PoliceDispatcher
extends Node
## The police (docs/design.md section 7, docs/build_notes piece D): every
## police unit, what each one knows, and what each one does. One of these,
## a child of Main (group "police_dispatcher").
##
## Patrols. Not wanted, a couple of Charlatown Police cruisers patrol the
## streets inside the bypass near you and the FIP patrols the outer ring
## (Riverside Drive, the Arterial Highway, Upton Road, Capital Drive) in
## its SUVs, driving legally: cruise speed, one-way streets, red lights.
##
## The force. Wanted, every level gets the force it always gets (FORCE:
## level 1 one cruiser, 2 four, 3 eight with the FIP called in, 4 eight and
## the Paint Tank). Missing units are placed on a street 300-600 m from you
## that you can't see (behind buildings, behind the camera, or too far off
## to make out), already heading your way. Far off a unit is a RoadFollower
## (no physics); within HANDOVER it becomes a real car; beyond LET_GO and
## out of sight it goes back. Units nobody can see far from the chase are
## removed. An officer painted out, or a unit whose car's stalled and whose
## crew are both out, doesn't count: a replacement comes.
##
## What they know. Only what they've seen or heard (`_perceive`): each car
## and each officer on foot has a sight cone (and a little all-round
## awareness up close) blocked by buildings and cars; a car you're seen
## getting into is the one they look for, and one they haven't seen you in
## is only recognised close up. Shots are heard nearby. What one sees goes
## out over the radio: all of them get _wanted.last_known_position, and the
## dispatcher calls _wanted.police_saw_player while any of them can see you.
##
## What they do (`_assign`). In sight: chasers on you, blockers to the
## junctions ahead of where you're heading, flankers to the side streets
## off them, a spotter hanging back. Lost: the chasers go to where you were
## last seen, then everyone searches the search circle, likely streets
## first (ahead of your last heading) and back past where they lost you.
## Level 3 adds leaning out, PIT, paint strips and roadblocks; level 4 the
## Paint Tank and harvester roadblocks.
##
## Catching you: boxed in (below BOX_KMH for BOX_TIME touching a police
## vehicle), pulled over at level 1 (stopped by a cruiser), your stalled
## car reached by an officer on foot, or painted out on foot (main.gd).
## A stalled car is impounded when the chase ends (ImpoundLot).
##
## MINIMAP HOOK: `map_units()` lists the units for a minimap (positions,
## force, flashing). Nothing draws it yet; the minimap piece reads it.

signal units_changed

## Units per level (design.md, "Wanted levels"), and who they are.
const FORCE := [0, 1, 4, 7, 8]
const MIX := [{}, {"city": 1}, {"city": 4}, {"city": 3, "fip": 4}, {"city": 2, "fip": 6}]
## Patrols near you when you're not wanted.
const PATROL_CITY := 2
const PATROL_FIP := 1
## Where new units appear (m from the player), and how far a far one may be.
const SPAWN_MIN := 300.0
const SPAWN_MAX := 600.0
## At level 1 (one cruiser answering a call) nearer, so it turns up while
## the call's still fresh and there's a cruiser to shake.
const SPAWN_L1 := Vector2(240.0, 360.0)
## At level 1, only a cruiser within this (m) seeing you stops your escape
## clock.
const L1_TAIL := 60.0
## A new unit in a chase you're in sight for comes from somewhere ahead of
## you this often (from behind or the side otherwise).
const SPAWN_AHEAD := 0.5
## A spot further than this counts as out of sight in plain view (a car's a
## few pixels there), and one behind the camera's view further than
## OUT_OF_VIEW does too.
const TOO_FAR_TO_SEE := 520.0
const OUT_OF_VIEW := 360.0
## Virtual to real within this of the player (inside the full-detail
## streets, where there's collision); real to virtual beyond LET_GO when
## nobody can see it.
const HANDOVER := 230.0
const LET_GO := 340.0
## A real police car stuck (backing out, wiggling, blocked) this long where
## you can't see it goes back to being a follower, which drives on.
const STUCK_HAND_BACK := 10.0
## Units further than this from both you and where you were last seen,
## and out of sight, are removed.
const REMOVE := 950.0
## Sight (m) by force, doubled by 50% police paint on your car
## (PaintCoverage.spotting_factor); a cone each side of where they face;
## and all round up close.
const SIGHT := {"city": 95.0, "fip": 108.0, "tactical": 90.0}
const CONE := 65.0
const FOOT_CONE := 80.0
const NEAR_SENSE := 14.0
## A car they haven't seen you in: they only know it's you this close.
const RECOGNISE := 22.0
## Shots heard within this (m).
const HEAR := 70.0
## No one's seen you for this long (s): they've lost you, and search.
const LOST_AFTER := 3.0
## For this long after that, they go to where you'd be by now (your last
## heading and speed), before falling back to searching the circle.
const PREDICT_TIME := 8.0
## When the city calls the FIP in (level 3), its units start coming after
## this long (s, a random time in the range): "ETA: after the paperwork".
const PAPERWORK := Vector2(8.0, 16.0)
## A stakeout waits at the way out of the search circle this long (s).
const STAKEOUT_TIME := 40.0
## Blockers go for a junction this far ahead (m): far enough to get there
## first and be seen waiting, near enough that you're still heading for it.
const BLOCK_MIN := 100.0
const BLOCK_MAX := 320.0
## From level 3, a blocker keeps its junction at least this long (s) once
## sent; at level 2 half that (the city needs its few cars on you).
const BLOCK_COMMIT := 9.0
## When nobody can get to a junction ahead first, a unit far off that
## nobody can see (over BRING_FROM m away) is brought round to a side
## street off it, out of sight: backup that was already in the area. At
## most every BRING_EVERY s.
const BRING_FROM := 450.0
const BRING_EVERY := 15.0
## The search gets round to a car wash near where you were lost as its
## this-many-th look (0 would be first).
const WASH_LOOK_AT := 4
## From level 3, the stakeout waits outside the car wash nearest where you
## were lost (within the circle and this much further, m) this often.
const WASH_STAKEOUT_REACH := 300.0
const WASH_STAKEOUT_CHANCE := 0.5
## A chaser close behind (10-45 m) and fast when you turn at a junction
## misses the turn this often (city, FIP; less at level 4): a mistake a
## good driver can use.
const MISS_TURN := {"city": 0.35, "fip": 0.15}
## Caught by boxing in: slower than this (km/h) for this long (s),
## touching a police vehicle. Pulled over at level 1: stopped this long
## with a cruiser this close (m). Fleeing a cruiser's lights at level 1:
## this long in sight, going faster than FLEE_KMH, makes it level 2.
const BOX_KMH := 5.0
const BOX_TIME := 3.0
## At levels 1-2, two or more cruisers against you: crawling under this
## (km/h) inside the ring still counts (a car creeping at walking pace between
## four cruisers is caught, not still in the chase). Not at 3-4, where
## the chase has enough ways to end already.
const BOX_RING_KMH := 9.0
## For the first BOX_GRACE s at a level (BOX_GRACE_L12_LONGER times that at
## 1-2), a box-in takes
## this much longer.
const BOX_GRACE := 30.0
const BOX_GRACE_FACTOR := 1.5
## ...and at levels 1-2 that opening stretch lasts this many times longer.
const BOX_GRACE_L12_LONGER := 1.5
## At levels 1-2 no box-in catch at all in the first this-many seconds.
const BOX_NONE_FIRST := 20.0
## ...and by level after the testers' runs: a 3-point turn next to one
## cruiser shouldn't be an arrest at level 2.
const BOX_TIME_BY_LEVEL := [3.0, 3.0, 4.0, 7.5, 5.0]
## One police vehicle pinning you runs the box-in clock at this rate (two
## or more, full speed).
const BOX_ONE_RATE := 0.6
## ...by level: easing off from 3 (a long FIP fight is mostly one car on
## you at a time) and none at 4.
const BOX_ONE_RATE_BY_LEVEL := [0.6, 0.6, 0.6, 0.3, 0.0]
const PULL_OVER_TIME := 4.0
const PULL_OVER_RANGE := 14.0
const FLEE_TIME := 12.0
const FLEE_KMH := 30.0
## An officer this close to your stalled car's door for ARREST_TIME (s).
const ARREST_RANGE := 2.6
const ARREST_TIME := 1.5
## Level 3 and 4 extras: how often (s) a roadblock or a paint strip can go
## down, and how far ahead.
const ROADBLOCK_EVERY := 75.0
const ROADBLOCK_MIN := 220.0
## ...and no further than this (inside the full-detail streets, where
## there's ground under the cars).
const ROADBLOCK_MAX := 320.0
## The first roadblock comes this long into a level 3 chase at the earliest.
const ROADBLOCK_FIRST := 15.0
const STRIP_EVERY := 20.0
## How far ahead of you a strip goes down (m).
const STRIP_AHEAD := Vector2(65.0, 110.0)
## The FIP's streets.
const RING_STREETS := ["Riverside Drive", "Arterial Highway", "Upton Road", "Capital Drive"]

var world: WorldBuilder
var _wash_spots: Array[Dictionary] = []
## The Wanted autoload (looked up, not named, so the tools that load this
## script before the autoloads exist can still compile it).
var _wanted: Node
var network: RoadNetwork
var terrain: Terrain
## Where units, cars and props go (Main).
var world_root: Node
var player: PlayerController
var hud: Node
var radio: PoliceRadio
var units: Array[PoliceUnit] = []
var roadblocks: Array[PoliceRoadblock] = []
## Seconds since it started.
var clock := 0.0
var level := 0
## The car they last saw the player in (null: on foot, or not seen yet).
var known_car: Car = null
## Off for tests that drive the police themselves.
var patrols := true
var enabled := true
## What happened, for checks and tuning: counters and the last events.
var stats := {"spawned": 0, "removed": 0, "handovers": 0, "to_virtual": 0, "spawn_rejected": 0,
	"strips": 0, "roadblocks": 0, "caught_by": "", "replaced": 0, "officers_out": 0, "pits": 0,
	"pit_spins": 0, "slicks": 0, "tank_shots": 0, "tank_hits": 0, "washes": 0,
	"missed_turns": 0, "cutoffs": 0, "stakeouts": 0, "blockers_sent": 0, "blockers_brought": 0, "pull_outs": 0, "height_fixes": 0}
## Each spawn: {at, dist, hidden_by} (for checks).
var spawn_log: Array = []

var _last_seen := -1000.0
var _seen_on_foot := -1000.0
var _was_lost := true
var _lost_said := false
var _think := 0.0
var _sight_t := 0.0
var _numbers := {"city": 11, "fip": 3, "tactical": 1}
var _box_t := 0.0
var _pull_t := 0.0
var _bring_next := 0.0
## When (clock) the level last changed.
var _level_since := 0.0
## The highest level this chase has reached (back to 0 when it's over): a
## chase cooled from 3 to 1 isn't ended by pulling over for a cruiser.
var _chase_top := 0
var _flee_t := 0.0
var _arrest_t := 0.0
var _touch_check := 0.0
## Police vehicles pinning the player's car now (_touching_police).
var _touching := 0
var _roadblock_t := 0.0
var _last_roadblock := Vector3.INF
## The FIP units start coming at this clock (the paperwork), -1 before.
var _fip_after := -1.0
var _stakeout: PoliceUnit = null
var _stakeout_until := 0.0
var _paperwork_said := true
## The edge the target was last on, for spotting a turn at a junction.
var _target_edge: RoadNetwork.RoadEdge = null
var _turn_check := 0.0
var _strip_t := 0.0
var _search_points: Array[Vector3] = []
var _search_i := 0
var _search_for := Vector3.INF
var _signal_grid := {}
var _chase_cars: Array[Car] = []
var _radio_t := {}
var _rng := RandomNumberGenerator.new()
var _sight := PhysicsRayQueryParameters3D.new()
var _box_q := PhysicsShapeQueryParameters3D.new()
var _box_shape := BoxShape3D.new()
var _city_edges: Array[RoadNetwork.RoadEdge] = []
var _ring_edges: Array[RoadNetwork.RoadEdge] = []
var _was_caught := false
var _heard_t := -100.0
var _last_vel := Vector3.ZERO


func setup(w: WorldBuilder, root: Node, p: PlayerController, h: Node) -> void:
	_wanted = w.get_tree().root.get_node("Wanted")
	world = w
	network = w.network
	terrain = w.terrain
	world_root = root
	player = p
	hud = h
	radio = PoliceRadio.new()
	radio.name = "PoliceRadio"
	if h != null:
		h.add_child(radio)
	else:
		add_child(radio)
	for nid: String in network.signal_nodes:
		var c: Vector2 = network.nodes[nid]
		var cell := Vector2i(floori(c.x / 100.0), floori(c.y / 100.0))
		if not _signal_grid.has(cell):
			_signal_grid[cell] = []
		(_signal_grid[cell] as Array).append(nid)
	for e in network.edges:
		if e.highway.begins_with("motorway"):
			continue
		var mid: Vector2 = RoadNetwork.sample(e.points, e.length * 0.5)[0]
		if RING_STREETS.has(e.name):
			_ring_edges.append(e)
		elif world.is_in_play_area(mid) and e.length > 30.0:
			_city_edges.append(e)
	_wanted.level_changed.connect(_on_level_changed)
	_wanted.announced.connect(_on_announced)
	if p != null and p.marker != null:
		p.marker.fired.connect(_on_player_fired)


func _ready() -> void:
	add_to_group("police_dispatcher")
	_rng.randomize()
	_sight.collision_mask = Layers.SOLID | Layers.VEHICLES
	_box_q.shape = _box_shape
	_box_q.collision_mask = Layers.VEHICLES


func _w3d() -> World3D:
	return (world_root as Node3D).get_world_3d()


static func find(tree: SceneTree) -> PoliceDispatcher:
	return tree.get_first_node_in_group("police_dispatcher") as PoliceDispatcher if tree != null else null


# --- what the units ask -----------------------------------------------------------------

## What to chase: the player's car, or the player on foot.
func target_body() -> Node3D:
	if player == null:
		return null
	return player.vehicle if player.vehicle != null else player


func player_in_car() -> bool:
	return player != null and player.vehicle != null


## Where they think the player is.
func known_position() -> Vector3:
	return _wanted.last_known_position


## Someone saw the player within the last `within` seconds.
func seen_recently(within := LOST_AFTER) -> bool:
	return clock - _last_seen <= within


## Junctions with traffic lights within `r` of p.
func signals_near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var c0 := Vector2i(floori((p.x - r) / 100.0), floori((p.y - r) / 100.0))
	var c1 := Vector2i(floori((p.x + r) / 100.0), floori((p.y + r) / 100.0))
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			for nid: String in _signal_grid.get(Vector2i(x, y), []):
				if (network.nodes[nid] as Vector2).distance_to(p) <= r:
					out.append(nid)
	return out


## A new unit of a force (not placed yet).
func new_unit(force: String) -> PoliceUnit:
	var n: int = _numbers[force]
	_numbers[force] = n + 1
	var u := PoliceUnit.new(force, n)
	u.dispatcher = self
	u.level = level
	add_child(u)
	units.append(u)
	units_changed.emit()
	return u


## Take a unit away now.
func drop_unit(u: PoliceUnit) -> void:
	units.erase(u)
	stats["removed"] = int(stats["removed"]) + 1
	u.remove()
	units_changed.emit()


## Say something on the radio (no more than once every `every` s a topic).
func radio_say(topic: String, u: PoliceUnit = null, chance := 1.0, every := 12.0) -> void:
	if radio == null or _rng.randf() > chance:
		return
	if clock - float(_radio_t.get(topic, -1000.0)) < every:
		return
	_radio_t[topic] = clock
	_update_radio_vars()
	radio.say(topic, u.number if u != null else 0)


func _update_radio_vars() -> void:
	var p: Vector3 = _wanted.last_known_position
	var street := world.street_name_at(Vector2(p.x, p.z), 40.0) if world != null else ""
	radio.vars["street"] = street if street != "" else "the corner of nowhere and nothing"
	var c := known_car if known_car != null and is_instance_valid(known_car) else player.vehicle if player != null else null
	if c != null:
		radio.vars["car"] = str(CarModels.get_model(c.model_id)["model"])
		radio.vars["colour"] = _colour_name(c.paint)
	else:
		radio.vars["car"] = "pedestrian"
		radio.vars["colour"] = "suspicious"
	radio.vars["count"] = _active().size()


static func _colour_name(c: Color) -> String:
	if c.s < 0.18:
		return "white" if c.v > 0.75 else ("grey" if c.v > 0.3 else "black")
	var h := c.h * 360.0
	if h < 20.0 or h >= 340.0:
		return "red"
	if h < 45.0:
		return "orange"
	if h < 70.0:
		return "yellow"
	if h < 165.0:
		return "green"
	if h < 255.0:
		return "blue"
	return "purple"


## MINIMAP HOOK: the units to show, [{pos: Vector3, force, flashing}].
## Officers who are out are left off (design.md: "their dot gone").
func map_units() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units:
		if u.spent:
			continue
		var p := u.position()
		if p == Vector3.INF:
			continue
		out.append({"pos": p, "force": u.force, "flashing": level >= 1 and u.role != PoliceUnit.Role.PATROL})
	return out


# --- each step ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not enabled or world == null:
		return
	clock += delta
	level = _wanted.level
	var target := target_body() if level > 0 else null
	for u: PoliceUnit in units.duplicate():
		if not is_instance_valid(u):
			units.erase(u)
			continue
		u.level = level
		u.step(delta, target)
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.2
		if level > 0:
			_perceive()
		else:
			for u in units:
				u.sees = false
	if level > 0:
		_check_caught(delta)
		_turn_check -= delta
		if _turn_check <= 0.0:
			_turn_check = 0.25
			_watch_turns()
		if player != null and player.vehicle != null and not _chase_cars.has(player.vehicle):
			_chase_cars.append(player.vehicle)
	_think -= delta
	if _think <= 0.0:
		_think = 0.5
		if level > 0:
			_keep_force()
			_assign()
			_extras()
		elif patrols:
			_keep_patrols()
		_handovers()
		_cleanup()
		if not _tow_when_left.is_empty():
			_tow_check()


# --- perception --------------------------------------------------------------------------

## Who can see the player now; tells Wanted while anyone can.
func _perceive() -> void:
	var t := target_body()
	if t == null:
		return
	var in_car := player.vehicle != null
	var pts: Array[Vector3] = []
	if in_car:
		pts = [t.global_position + Vector3.UP * 0.9, t.global_transform * Vector3(0, float(player.vehicle.shape.get("height", 1.4)) * 0.9, 0)]
	else:
		pts = [t.global_position + Vector3.UP * 1.0, t.global_position + Vector3.UP * 1.6]
	var factor := 1.0
	if in_car:
		var pc := player.vehicle.get_node_or_null("PaintCoverage") as PaintCoverage
		if pc != null:
			factor = pc.spotting_factor
	var exclude: Array[RID] = [player.get_rid()]
	if in_car:
		exclude.append(player.vehicle.get_rid())
	var any := false
	for u in units:
		u.sees = false
		if u.spent and u.foot_officers().is_empty():
			continue
		var range_m: float = SIGHT[u.force] * factor
		if u.car != null and not u.dismounted and u.crew_left > 0:
			var eye := u.car.global_transform * Vector3(0, 1.35, -0.4)
			var fwd := -u.car.global_basis.z
			if _can_see(eye, fwd, CONE, range_m, pts, _plus(exclude, u.car.get_rid())):
				u.sees = true
		for o in u.foot_officers():
			if u.sees:
				break
			if _can_see(o.eye(), o.facing(), FOOT_CONE, range_m * 0.85, pts, _plus(exclude, o.get_rid())):
				u.sees = true
		if u.sees:
			any = true
	if not any:
		return
	# A car they haven't seen the player in is only them close up, unless
	# they just saw them on foot (getting in).
	if in_car and player.vehicle != known_car:
		var close := false
		for u in units:
			if u.sees and u.position().distance_to(t.global_position) < RECOGNISE:
				close = true
		if clock - _seen_on_foot < 2.5 or close or known_car == null and clock - _last_seen > 1000.0:
			var switched := known_car != null
			known_car = player.vehicle
			if switched:
				radio_say("switched_car", null, 1.0, 5.0)
		else:
			for u in units:
				u.sees = false
			return
	if not in_car:
		_seen_on_foot = clock
	# At level 1 a cruiser trailing you far back isn't a pursuit: your
	# escape clock runs unless one's within L1_TAIL m.
	if level == 1:
		var near := false
		for u in units:
			if u.sees and u.position().distance_to(t.global_position) < L1_TAIL:
				near = true
		if not near:
			return
	var was_lost := not seen_recently(6.0)
	_last_seen = clock
	_lost_said = false
	_wanted.police_saw_player(player.global_position)
	_last_vel = _velocity_of(t)
	if was_lost:
		var who: PoliceUnit = null
		for u in units:
			if u.sees:
				who = u
				break
		radio_say("spotted", who, 1.0, 8.0)


static func _plus(list: Array[RID], rid: RID) -> Array[RID]:
	var out: Array[RID] = list.duplicate()
	out.append(rid)
	return out


func _can_see(eye: Vector3, fwd: Vector3, cone_deg: float, range_m: float, pts: Array[Vector3], exclude: Array[RID]) -> bool:
	var d := eye.distance_to(pts[0])
	if d > range_m:
		return false
	var to := pts[0] - eye
	to.y = 0.0
	if d > NEAR_SENSE and fwd.dot(to.normalized()) < cos(deg_to_rad(cone_deg)):
		return false
	_sight.exclude = exclude
	for p in pts:
		_sight.from = eye
		_sight.to = p
		if _w3d().direct_space_state.intersect_ray(_sight).is_empty():
			return true
	return false


static func _velocity_of(n: Node3D) -> Vector3:
	if n is RigidBody3D:
		return (n as RigidBody3D).linear_velocity
	if n is CharacterBody3D:
		return (n as CharacterBody3D).velocity
	return Vector3.ZERO


## The player fired: officers near enough hear it.
func _on_player_fired() -> void:
	if level == 0 or player == null:
		return
	var p := player.global_position
	for u in units:
		var q := u.position()
		if q != Vector3.INF and q.distance_to(p) < HEAR and (u.car != null or not u.officers.is_empty()):
			_wanted.last_known_position = p
			if not seen_recently():
				radio_say("heard_shots", u, 1.0, 15.0)
				_heard_t = clock
				_search_points.clear()
			return


# --- the force ---------------------------------------------------------------------------

func _active() -> Array[PoliceUnit]:
	var out: Array[PoliceUnit] = []
	for u in units:
		if u.active() and u.force != "tactical":
			out.append(u)
	return out


## Keeps the level's force: spawns what's missing, sends extras away.
func _keep_force() -> void:
	var mix: Dictionary = MIX[clampi(level, 0, 4)]
	var have := {"city": [], "fip": []}
	for u in _active():
		(have[u.force] as Array).append(u)
	var p := player.global_position
	for force: String in ["city", "fip"]:
		var want := int(mix.get(force, 0))
		var list: Array = have[force]
		# The FIP comes "after the paperwork" when the city calls it in.
		if force == "fip" and clock < _fip_after and list.size() < want:
			continue
		if force == "fip" and _fip_after > 0.0 and clock >= _fip_after and not _paperwork_said:
			_paperwork_said = true
			radio_say("paperwork", null, 1.0, 0.0)
		# Furthest first to go.
		list.sort_custom(func(a: PoliceUnit, b: PoliceUnit) -> bool: return a.position().distance_to(p) > b.position().distance_to(p))
		while list.size() > want:
			var u: PoliceUnit = list.pop_front()
			u.order(PoliceUnit.Role.LEAVE, _leave_point(u), clock)
		if list.size() < want:
			var u := _spawn(force)
			if u != null and clock > 5.0 and int(stats["officers_out"]) > 0:
				stats["replaced"] = int(stats["replaced"]) + 1
				radio_say("replacement", u, 0.6, 20.0)
	# The tactical unit's Paint Tank at level 4.
	var tank: PoliceUnit = null
	for u in units:
		if u.force == "tactical" and u.role != PoliceUnit.Role.LEAVE and not u.spent:
			tank = u
	if level >= 4 and tank == null:
		_spawn("tactical")
	elif level < 4 and tank != null:
		tank.order(PoliceUnit.Role.LEAVE, _leave_point(tank), clock)


func _keep_patrols() -> void:
	var p := player.global_position
	var pp := Vector2(p.x, p.z)
	var counts := {"city": 0, "fip": 0}
	for u in units:
		if u.role == PoliceUnit.Role.PATROL and not u.spent:
			counts[u.force] = int(counts[u.force]) + 1
			if u.arrived or u.goal == Vector3.INF or clock - u.goal_time > 120.0:
				u.order(PoliceUnit.Role.PATROL, _patrol_point(u.force, Vector2(u.position().x, u.position().z)), clock)
		elif u.role != PoliceUnit.Role.LEAVE and u.roadblock == null:
			# A chase unit after the chase: back on patrol if a patrol's
			# wanted, else away.
			var f := u.force
			var want := PATROL_CITY if f == "city" else PATROL_FIP
			if f != "tactical" and int(counts[f]) < want:
				counts[f] = int(counts[f]) + 1
				u.order(PoliceUnit.Role.PATROL, _patrol_point(f, Vector2(u.position().x, u.position().z)), clock)
			else:
				u.order(PoliceUnit.Role.LEAVE, _leave_point(u), clock)
	if int(counts["city"]) < PATROL_CITY and world.is_in_play_area(pp):
		_spawn("city", true)
	if int(counts["fip"]) < PATROL_FIP and _near_ring(pp, 900.0):
		_spawn("fip", true)


func _near_ring(p: Vector2, r: float) -> bool:
	for e in _ring_edges:
		if e.bounds.grow(r).has_point(p) and RoadNetwork.distance_to_edge(e, p) < r:
			return true
	return false


## A place on the beat: a city street inside the bypass, or a stretch of
## the ring for the FIP, within reach of the player.
func _patrol_point(force: String, from: Vector2) -> Vector3:
	var pool := _ring_edges if force == "fip" else _city_edges
	var p := player.global_position
	var pp := Vector2(p.x, p.z)
	for tries in 30:
		var e: RoadNetwork.RoadEdge = pool[_rng.randi() % pool.size()]
		var q: Vector2 = RoadNetwork.sample(e.points, _rng.randf_range(0.2, 0.8) * e.length)[0]
		var dp := q.distance_to(pp)
		if dp < 700.0 and q.distance_to(from) > 150.0:
			return Vector3(q.x, terrain.h2(q), q.y)
	var e2: RoadNetwork.RoadEdge = pool[_rng.randi() % pool.size()]
	var q2: Vector2 = RoadNetwork.sample(e2.points, e2.length * 0.5)[0]
	return Vector3(q2.x, terrain.h2(q2), q2.y)


## Somewhere well away from the player, by road, to drive off to.
func _leave_point(u: PoliceUnit) -> Vector3:
	var p := u.position()
	var away := p - player.global_position
	away.y = 0.0
	if away.length() < 1.0:
		away = Vector3.FORWARD
	var q := p + away.normalized() * 600.0
	var hit := network.nearest_on_streets(Vector2(q.x, q.z), 400.0)
	if hit.is_empty():
		return q
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var s: Vector2 = RoadNetwork.sample(e.points, float(hit["along"]))[0]
	return Vector3(s.x, terrain.h2(s), s.y)


## How far from the player new units go (m): SPAWN_MIN-SPAWN_MAX, nearer
## at level 1.
func _spawn_range() -> Vector2:
	return SPAWN_L1 if level == 1 else Vector2(SPAWN_MIN, SPAWN_MAX)


## A new unit on a street SPAWN_MIN-SPAWN_MAX m from the player, out of
## their sight, heading for where they are (or, for a patrol, its beat).
func _spawn(force: String, patrol := false) -> PoliceUnit:
	var prefer := Vector3.INF
	if force == "tactical" and player != null:
		# The tank is slow: it's placed ahead of where you're going.
		var t := target_body()
		prefer = t.global_position + _velocity_of(t) * 25.0
	elif not patrol and player != null and level == 1:
		# The cruiser answering a call comes from the way you're going.
		var t := target_body()
		prefer = t.global_position + _velocity_of(t) * 12.0
	elif not patrol and player != null and level >= 2 and seen_recently() and _rng.randf() < SPAWN_AHEAD:
		# Backup coming from the way you're going, not only from behind.
		var t := target_body()
		prefer = t.global_position + _velocity_of(t) * 30.0
	var spot := _spawn_spot(force, prefer)
	if spot.is_empty():
		return null
	var u := new_unit(force)
	u.start_virtual(spot["at"], spot["dir"], world_root)
	stats["spawned"] = int(stats["spawned"]) + 1
	spawn_log.append({"at": spot["at"], "dist": spot["dist"], "hidden_by": spot["hidden_by"], "force": force, "clock": clock, "level": level})
	if patrol:
		u.order(PoliceUnit.Role.PATROL, _patrol_point(force, spot["at"]), clock)
	else:
		u.order(PoliceUnit.Role.RESPOND, _wanted.last_known_position, clock)
	return u


func _spawn_spot(force: String, prefer := Vector3.INF) -> Dictionary:
	var p := player.global_position
	var pp := Vector2(p.x, p.z)
	var pool: Array[RoadNetwork.RoadEdge] = []
	for e in network.edges_near(Rect2(pp - Vector2(SPAWN_MAX, SPAWN_MAX), Vector2(SPAWN_MAX, SPAWN_MAX) * 2.0)):
		if e.highway.begins_with("motorway") or e.bridge:
			continue
		if force == "fip" and level == 0 and not RING_STREETS.has(e.name):
			continue
		pool.append(e)
	if pool.is_empty():
		return {}
	var toward: Vector3 = _wanted.last_known_position if level > 0 else p
	var best := {}
	var found := 0
	for tries in 40:
		var e: RoadNetwork.RoadEdge = pool[_rng.randi() % pool.size()]
		var along := _rng.randf_range(0.1, 0.9) * e.length
		var sp: Array = RoadNetwork.sample(e.points, along)
		var q: Vector2 = sp[0]
		var d := q.distance_to(pp)
		if d < _spawn_range().x or d > _spawn_range().y:
			continue
		if force == "city" and not world.is_in_play_area(q):
			continue
		var hidden := _hidden_from_player(Vector3(q.x, terrain.h2(q), q.y), d)
		if hidden == "":
			stats["spawn_rejected"] = int(stats["spawn_rejected"]) + 1
			continue
		# Face along the street toward where it's going, in the lane.
		var dir: Vector2 = sp[1]
		var tw := Vector2(toward.x, toward.z) - q
		if tw.dot(dir) < 0.0:
			dir = -dir
		var lane := Vector2(-dir.y, dir.x) * StreetRoute._lane_offset(e, true if e.oneway == 0 else e.oneway == 1)
		var spot := {"at": q + lane, "dir": dir, "dist": d, "hidden_by": hidden}
		if prefer == Vector3.INF:
			return spot
		# With a preference, the best of a few.
		var score := q.distance_to(Vector2(prefer.x, prefer.z))
		if best.is_empty() or score < float(best["score"]):
			best = spot
			best["score"] = score
		found += 1
		if found >= 8:
			break
	return best


## Whether a spot can't be seen from the player or the camera: "" if it
## can, else why not ("building", "behind", "far").
func _hidden_from_player(at: Vector3, d: float) -> String:
	var eyes: Array[Vector3] = [player.global_position + Vector3.UP * 1.6]
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		eyes.append(cam.global_position)
	var target := at + Vector3.UP * 1.2
	var blocked_all := true
	for eye in eyes:
		_sight.from = eye
		_sight.to = target
		_sight.collision_mask = Layers.SOLID
		_sight.exclude = [player.get_rid()]
		var clear := _w3d().direct_space_state.intersect_ray(_sight).is_empty()
		_sight.collision_mask = Layers.SOLID | Layers.VEHICLES
		if clear:
			blocked_all = false
	if blocked_all:
		return "building"
	if d > TOO_FAR_TO_SEE:
		return "far"
	if cam != null and d > OUT_OF_VIEW:
		var to := (target - cam.global_position).normalized()
		if (-cam.global_basis.z).dot(to) < cos(deg_to_rad(cam.fov * 0.5 + 15.0)):
			return "behind"
	return ""


## Followers near the player become real cars; real ones far off and out
## of sight become followers again.
func _handovers() -> void:
	var p := player.global_position
	for u in units:
		var q := u.position()
		if q == Vector3.INF:
			continue
		var d := q.distance_to(p)
		if u.follower != null and d < HANDOVER and clock >= u.virtual_until and _ground_at(q):
			u.make_physical(world_root)
			stats["handovers"] = int(stats["handovers"]) + 1
		elif u.car != null and u.roadblock == null and (d > LET_GO or u.stuck_time > STUCK_HAND_BACK) and _hidden_from_player(q, d) != "":
			if u.make_virtual(world_root):
				stats["to_virtual"] = int(stats["to_virtual"]) + 1


func _ground_at(q: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(q + Vector3.UP * 6.0, q + Vector3.DOWN * 6.0, Layers.GROUND)
	return not _w3d().direct_space_state.intersect_ray(ray).is_empty()


## Units nobody can see, far from the chase, and spent or leaving ones out
## of sight, are removed; out officers who've done their exit go too.
func _cleanup() -> void:
	var p := player.global_position
	var lk: Vector3 = _wanted.last_known_position
	for u: PoliceUnit in units.duplicate():
		var q := u.position()
		if q == Vector3.INF:
			drop_unit(u)
			continue
		var d := q.distance_to(p)
		for o: Officer in u.officers.duplicate():
			if is_instance_valid(o) and o.exit_finished() and o.get_parent() != null and not (o.get_parent() is Node3D and o.get_parent().name.ends_with("Seat")):
				if o.global_position.distance_to(p) > 45.0 or _hidden_from_player(o.global_position, o.global_position.distance_to(p)) != "":
					u.officers.erase(o)
					PoliceUnit._silence(o)
					o.queue_free()
		if u.roadblock != null:
			continue
		var far := d > REMOVE and (level == 0 or q.distance_to(lk) > REMOVE)
		var gone := (u.role == PoliceUnit.Role.LEAVE and d > LET_GO) or (u.spent and d > 60.0) or far
		if gone and (u.follower != null or _hidden_from_player(q, d) != ""):
			drop_unit(u)
	for rb: PoliceRoadblock in roadblocks.duplicate():
		if not is_instance_valid(rb):
			roadblocks.erase(rb)
			continue
		var d := rb.global_position.distance_to(p)
		if (level < 3 or clock - rb.made_at > 90.0 or d > ROADBLOCK_MAX + 150.0) and _hidden_from_player(rb.global_position, d) != "":
			roadblocks.erase(rb)
			rb.clear()


# --- roles -------------------------------------------------------------------------------

## Who does what in a chase.
func _assign() -> void:
	var units_now := _active()
	for u in units:
		if u.force == "tactical" and u.role != PoliceUnit.Role.LEAVE and not u.spent:
			units_now.append(u)
	if units_now.is_empty():
		return
	var t := target_body()
	var seen := seen_recently()
	var tp: Vector3 = t.global_position if seen else _wanted.last_known_position
	units_now.sort_custom(func(a: PoliceUnit, b: PoliceUnit) -> bool: return a.position().distance_to(tp) < b.position().distance_to(tp))
	if seen:
		_search_points.clear()
		_was_lost = false
		var n_chase: int = [0, 1, 2, 2, 3][level]
		var n_block: int = [0, 0, 1, 1, 2][level]
		var n_flank: int = [0, 0, 1, 1, 2][level]
		var n_spot: int = [0, 0, 0, 1, 1][level]
		var vel := _velocity_of(t)
		var ahead := _junctions_ahead(tp, vel, 3)
		var flank := _flank_points(tp, vel, ahead)
		var free := units_now.duplicate()
		# The tank heads you off (it's slow), or chases up close.
		for u in units_now:
			if u.force == "tactical":
				free.erase(u)
				var d := u.position().distance_to(tp)
				if d < 120.0 or ahead.is_empty():
					u.order(PoliceUnit.Role.CHASE, tp, clock)
				elif u.role == PoliceUnit.Role.BLOCK and u.goal != Vector3.INF and _still_ahead(u.goal, tp, vel):
					pass # committed to its junction while you're still heading for it
				else:
					u.order(PoliceUnit.Role.BLOCK, ahead[0], clock)
		# Blockers already heading you off keep their junction while you're
		# still going that way (no churn: a cut-off needs time to happen).
		var kept := 0
		for u: PoliceUnit in free.duplicate():
			if kept >= n_block:
				break
			# (And for at least BLOCK_COMMIT s once sent, whatever you do:
			# no re-tasking every time you wiggle.)
			var commit := BLOCK_COMMIT if level >= 3 else BLOCK_COMMIT * 0.5
			var committed := clock - u.goal_time < commit and u.goal.distance_to(tp) < BLOCK_MAX * 1.3
			if u.role == PoliceUnit.Role.BLOCK and u.goal != Vector3.INF and u.force != "tactical" \
					and u.position().distance_to(tp) > 60.0 and (committed or _still_ahead(u.goal, tp, vel)) \
					and u.goal.distance_to(tp) < BLOCK_MAX * 1.3:
				free.erase(u)
				kept += 1
		# Chasers: the nearest.
		for i in mini(n_chase, free.size()):
			var u: PoliceUnit = free.pop_front()
			u.order(PoliceUnit.Role.CHASE if u.position().distance_to(tp) < 400.0 else PoliceUnit.Role.RESPOND, tp, clock)
		# Blockers: a junction further ahead that someone can get to before
		# you do (by a rough time over the distances), the one who'll be there
		# soonest. Nobody can: no cut-off this time.
		var far_ahead := _junctions_ahead(tp, vel, 6)
		var car_v := maxf(Vector2(vel.x, vel.z).length(), 8.0)
		for k in n_block - kept:
			if free.is_empty():
				break
			var pick: PoliceUnit = null
			var pick_at := Vector3.INF
			var pick_margin := 0.0
			for j in far_ahead:
				var dj := j.distance_to(tp)
				if dj < BLOCK_MIN or dj > BLOCK_MAX or _blocked_already(j):
					continue
				var car_eta := dj / car_v
				for u: PoliceUnit in free:
					# Not one already on the car (it'd park in front of it).
					if u.force == "tactical" or u.position().distance_to(tp) < 80.0:
						continue
					var u_eta := u.position().distance_to(j) * 1.35 / (float(PoliceUnit.BLOCK_KMH[u.force]) / 3.6)
					var margin := car_eta - u_eta
					if margin > 1.0 and margin > pick_margin:
						pick = u
						pick_at = j
						pick_margin = margin
			if pick == null:
				pick = _bring_round(free, far_ahead, tp)
				if pick == null:
					break
				pick_at = pick.goal
			free.erase(pick)
			if pick.role != PoliceUnit.Role.BLOCK or pick.goal.distance_to(pick_at) > 30.0:
				stats["blockers_sent"] = int(stats["blockers_sent"]) + 1
			pick.order(PoliceUnit.Role.BLOCK, pick_at, clock)
		for k in mini(n_flank, flank.size()):
			if free.is_empty():
				break
			var best := _nearest_to(free, flank[k])
			free.erase(best)
			best.order(PoliceUnit.Role.FLANK, flank[k], clock)
		for k in n_spot:
			if free.is_empty():
				break
			var u: PoliceUnit = free.pop_front()
			u.order(PoliceUnit.Role.SPOT, tp, clock)
		for u: PoliceUnit in free:
			u.order(PoliceUnit.Role.CHASE if u.position().distance_to(tp) < 300.0 else PoliceUnit.Role.RESPOND, tp, clock)
		return
	# Lost: first to where they were seen, then the search.
	var since := clock - _last_seen
	if not _lost_said and _last_seen > 0.0:
		_lost_said = true
		radio_say("lost", units_now[0], 1.0, 10.0)
	if since < LOST_AFTER + _predict_time() or _last_seen < 0.0:
		# Just lost: to where they'd be by now, the way they were going
		# (snapped to the street), the nearest straight on, the rest to the
		# junctions ahead of that.
		var guess := _predicted(since)
		var ahead := _junctions_ahead(guess, _last_vel, 2)
		var k := 0
		for u in units_now:
			var spot := guess if k == 0 or ahead.is_empty() else ahead[(k - 1) % ahead.size()]
			u.order(PoliceUnit.Role.RESPOND, spot, clock)
			k += 1
		return
	if _search_points.is_empty() or _search_for.distance_to(_wanted.last_known_position) > 30.0:
		_plan_search()
		radio_say("searching", null, 0.7, 25.0)
	# One unit stakes out the way out ahead of where they were going: the
	# junction at the edge of the circle, waiting there, lights off.
	if _stakeout == null or not is_instance_valid(_stakeout) or not units_now.has(_stakeout) or clock > _stakeout_until:
		_stakeout = null
		var exit := _circle_exit()
		# From level 3 they know the car washes: now and then the stakeout
		# waits outside the one nearest where you were lost instead (in
		# plain view, lights off: you can see it and go elsewhere).
		var wash := _nearest_wash_way_in(_wanted.last_known_position, _wanted.search_radius + WASH_STAKEOUT_REACH)
		if level >= 3 and wash != Vector3.INF and _rng.randf() < WASH_STAKEOUT_CHANCE:
			exit = wash
		if exit != Vector3.INF and units_now.size() >= 3:
			_stakeout = _nearest_to(units_now, exit)
			_stakeout.order(PoliceUnit.Role.SEARCH, exit, clock)
			_stakeout_until = clock + STAKEOUT_TIME
			_stakeout.quiet_until = _stakeout_until
			stats["stakeouts"] = int(stats["stakeouts"]) + 1
	for u in units_now:
		if u == _stakeout:
			continue
		var done := u.arrived or u.role != PoliceUnit.Role.SEARCH or clock - u.goal_time > 35.0
		if done and not _search_points.is_empty():
			var pt := _search_points[_search_i % _search_points.size()]
			_search_i += 1
			# Every fourth look is back past where they lost you.
			if _search_i % 4 == 0:
				pt = _wanted.last_known_position
			u.order(PoliceUnit.Role.SEARCH, pt, clock)


## The target turning at a junction: now and then a chaser behind misses
## the turn and overshoots (radio: "Missed the turn!"), and blockers in
## place at the junction ahead as it comes are counted (cut-offs).
func _watch_turns() -> void:
	var t := target_body()
	if t == null or not seen_recently():
		return
	var tp := t.global_position
	var hit := network.nearest_on_streets(Vector2(tp.x, tp.z), 15.0)
	if hit.is_empty():
		return
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var turned := _target_edge != null and e != _target_edge and e.name != _target_edge.name
	_target_edge = e
	for u in units:
		if u.car == null or u.dismounted:
			continue
		var d := u.car.global_position.distance_to(tp)
		# Close behind and fast, so it visibly sails past the junction.
		if turned and u.role == PoliceUnit.Role.CHASE and d > 10.0 and d < 45.0 and absf(u.car.speed) > 12.0 and u.force in MISS_TURN:
			var p: float = MISS_TURN[u.force] * (0.6 if level >= 4 else 1.0)
			if _rng.randf() < p:
				u.overshoot(clock)
				stats["missed_turns"] = int(stats["missed_turns"]) + 1
				radio_say("missed_turn", u, 1.0, 20.0)
		if u.role == PoliceUnit.Role.BLOCK and not u.cutoff_counted and d < 60.0 and _still_ahead(u.car.global_position, tp, _velocity_of(t)):
			u.cutoff_counted = true
			stats["cutoffs"] = int(stats["cutoffs"]) + 1


## Whether a point is still ahead of someone at p going vel (within 60
## degrees of the way they're going, and not passed).
func _still_ahead(point: Vector3, p: Vector3, vel: Vector3) -> bool:
	var to := Vector2(point.x - p.x, point.z - p.z)
	var v := Vector2(vel.x, vel.z)
	if v.length() < 2.0 or to.length() < 15.0:
		return to.length() >= 15.0
	return to.normalized().dot(v.normalized()) > 0.5


## How long the "where they'd be by now" guess runs: shorter at level 2
## (the city guesses less well, and a lost tail should stay lost).
func _predict_time() -> float:
	return PREDICT_TIME * (0.6 if level <= 2 else 1.0)


## Where the player would be `since` seconds after they were last seen,
## going on the way they were going (at most PREDICT_TIME of it), on the
## nearest street.
func _predicted(since: float) -> Vector3:
	var p: Vector3 = _wanted.last_known_position + _last_vel * minf(since, _predict_time())
	var hit := network.nearest_on_streets(Vector2(p.x, p.z), 80.0)
	if hit.is_empty():
		return _wanted.last_known_position
	var q: Vector2 = RoadNetwork.sample((hit["edge"] as RoadNetwork.RoadEdge).points, float(hit["along"]))[0]
	return Vector3(q.x, terrain.h2(q), q.y)


## The street toward `from` out of junction j: its width (for picking the
## bottleneck to block).
func _street_width_toward(j: Vector3, from: Vector3) -> float:
	var jj := Vector2(j.x, j.z)
	var hit := network.nearest_on_streets(jj + (Vector2(from.x, from.z) - jj).normalized() * 25.0, 20.0)
	return 99.0 if hit.is_empty() else (hit["edge"] as RoadNetwork.RoadEdge).half_width


## The junction on the edge of the search circle in the direction they were
## going when lost (where a stakeout waits), or INF.
func _circle_exit() -> Vector3:
	var c := _wanted.last_known_position as Vector3
	var v := Vector2(_last_vel.x, _last_vel.z)
	if v.length() < 2.0:
		return Vector3.INF
	var r := maxf(float(_wanted.search_radius), 120.0)
	var aim := Vector2(c.x, c.z) + v.normalized() * r
	var best := ""
	var best_d := INF
	for nid: String in network.nodes:
		if network.degree(nid) < 3:
			continue
		var q: Vector2 = network.nodes[nid]
		var d := q.distance_to(aim)
		if d < best_d:
			best_d = d
			best = nid
	if best == "" or best_d > r * 0.6:
		return Vector3.INF
	var q2: Vector2 = network.nodes[best]
	return Vector3(q2.x, terrain.h2(q2), q2.y)


func _nearest_to(list: Array, p: Vector3) -> PoliceUnit:
	var best: PoliceUnit = list[0]
	for u: PoliceUnit in list:
		if u.position().distance_to(p) < best.position().distance_to(p):
			best = u
	return best


## A far-off, unseen unit moved to a side street of the first junction
## ahead in range that nobody holds, out of sight of the player, and sent
## to block it. Null if there's no such unit or spot.
func _bring_round(free: Array, ahead: Array[Vector3], tp: Vector3) -> PoliceUnit:
	if clock < _bring_next:
		return null
	var far: PoliceUnit = null
	for u: PoliceUnit in free:
		if u.follower == null or u.force == "tactical":
			continue
		var d := u.position().distance_to(tp)
		if d > BRING_FROM and (far == null or d > far.position().distance_to(tp)):
			far = u
	if far == null:
		return null
	for j in ahead:
		var dj := j.distance_to(tp)
		if dj < BLOCK_MIN + 40.0 or dj > BLOCK_MAX or _blocked_already(j):
			continue
		var spot := _side_spot(j, tp)
		if spot.is_empty():
			continue
		_bring_next = clock + BRING_EVERY
		far.follower.queue_free()
		far.follower = null
		far.start_virtual(spot["at"], spot["dir"], world_root)
		far.order(PoliceUnit.Role.BLOCK, j, clock)
		stats["blockers_brought"] = int(stats["blockers_brought"]) + 1
		return far
	return null


## A spot 40-80 m up a side street off junction j (not the one toward
## `from`), facing the junction, that the player can't see; or {}.
func _side_spot(j: Vector3, from: Vector3) -> Dictionary:
	var jj := Vector2(j.x, j.z)
	var hit := network.nearest_on_streets(jj, 10.0)
	if hit.is_empty():
		return {}
	var e0: RoadNetwork.RoadEdge = hit["edge"]
	var nid := e0.a if (network.nodes[e0.a] as Vector2).distance_to(jj) < (network.nodes[e0.b] as Vector2).distance_to(jj) else e0.b
	var to_from := (Vector2(from.x, from.z) - jj).normalized()
	var p := player.global_position
	for inc: RoadNetwork.Incident in network.incidents.get(nid, []):
		if inc.dir.dot(to_from) > 0.7 or inc.edge.length < 50.0 or inc.edge.bridge or inc.edge.highway.begins_with("motorway"):
			continue
		var along := minf(_rng.randf_range(40.0, 80.0), inc.edge.length - 5.0)
		var at := along if inc.at_start else inc.edge.length - along
		var sp: Array = RoadNetwork.sample(inc.edge.points, at)
		var q: Vector2 = sp[0]
		var q3 := Vector3(q.x, terrain.h2(q), q.y)
		var d := q3.distance_to(p)
		if d < 120.0 or _hidden_from_player(q3, d) == "":
			continue
		return {"at": q, "dir": (jj - q).normalized()}
	return {}


## The spot 25 m outside the way in of the car wash nearest `p` within
## `r`, or INF.
func _nearest_wash_way_in(p: Vector3, r: float) -> Vector3:
	if world != null and _wash_spots.is_empty():
		_wash_spots = CarWashes.find_spots(world)
	var best := Vector3.INF
	var bd := r
	for sp: Dictionary in _wash_spots:
		var o: Vector3 = (sp["xform"] as Transform3D).origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < bd:
			bd = d
			best = CarWashes.way_in(sp, 25.0)
	return best


## A blocker already has this junction.
func _blocked_already(j: Vector3) -> bool:
	for u in units:
		if u.role == PoliceUnit.Role.BLOCK and u.goal != Vector3.INF and u.goal.distance_to(j) < 30.0:
			return true
	return false


## The junctions the player's heading for, nearest first: along the street
## they're on in the way they're going, then straight on as near as the
## streets go. Points on the ground.
func _junctions_ahead(p: Vector3, vel: Vector3, count: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var pp := Vector2(p.x, p.z)
	var hit := network.nearest_on_streets(pp, 60.0)
	if hit.is_empty():
		return out
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var dir := Vector2(vel.x, vel.z)
	if dir.length() < 2.0:
		var t := target_body()
		var f := -t.global_basis.z if t != null else Vector3.FORWARD
		dir = Vector2(f.x, f.z)
	dir = dir.normalized()
	var na: Vector2 = network.nodes[e.a]
	var nb: Vector2 = network.nodes[e.b]
	var nid := e.a if (na - pp).dot(dir) > (nb - pp).dot(dir) else e.b
	var came := e
	for i in count + 2:
		var c: Vector2 = network.nodes[nid]
		if network.degree(nid) >= 3 and c.distance_to(pp) > 50.0:
			out.append(Vector3(c.x, terrain.h2(c), c.y))
			if out.size() >= count:
				break
		# Straight on: the way out that turns least.
		var best: RoadNetwork.Incident = null
		var best_dot := -2.0
		for inc: RoadNetwork.Incident in network.incidents.get(nid, []):
			if inc.edge == came:
				continue
			var dd := inc.dir.dot(dir)
			if dd > best_dot:
				best_dot = dd
				best = inc
		if best == null:
			break
		dir = best.dir
		came = best.edge
		nid = best.edge.b if best.at_start else best.edge.a
	return out


## The side streets off the first junction ahead: where flankers wait.
func _flank_points(p: Vector3, vel: Vector3, ahead: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if ahead.is_empty():
		return out
	var j := Vector2(ahead[0].x, ahead[0].z)
	var hit := network.nearest_on_streets(j, 10.0)
	if hit.is_empty():
		return out
	var dir := Vector2(vel.x, vel.z).normalized()
	var nid := ""
	for k: String in [(hit["edge"] as RoadNetwork.RoadEdge).a, (hit["edge"] as RoadNetwork.RoadEdge).b]:
		if (network.nodes[k] as Vector2).distance_to(j) < 2.0:
			nid = k
	if nid == "":
		return out
	for inc: RoadNetwork.Incident in network.incidents.get(nid, []):
		if absf(inc.dir.dot(dir)) < 0.6:
			var q := j + inc.dir * minf(70.0, inc.edge.length * 0.6)
			out.append(Vector3(q.x, terrain.h2(q), q.y))
	return out


## Points to look at in the search circle: along the streets in it, the
## likely ones first (ahead of the way they were going when lost).
func _plan_search() -> void:
	_search_for = _wanted.last_known_position
	_search_points.clear()
	_search_i = 0
	var c := Vector2(_search_for.x, _search_for.z)
	var r := maxf(_wanted.search_radius, 100.0)
	var heading := Vector2(_last_vel.x, _last_vel.z)
	var likely := c + (heading.normalized() * r * 0.5 if heading.length() > 2.0 else Vector2.ZERO)
	var pts: Array = []
	for e in network.edges_near(Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)):
		var d := 0.0
		while d < e.length:
			var q: Vector2 = RoadNetwork.sample(e.points, d)[0]
			if q.distance_to(c) <= r:
				pts.append([q.distance_to(likely) + _rng.randf() * r * 0.4, q])
			d += 45.0
	# Dead ends and the ends of lots: where someone hides. A little nearer
	# the front of the list than their distance alone puts them.
	for nid: String in network.nodes:
		var q: Vector2 = network.nodes[nid]
		if network.degree(nid) == 1 and q.distance_to(c) <= r:
			pts.append([q.distance_to(likely) * 0.7 + _rng.randf() * r * 0.4, q])
	pts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in mini(pts.size(), 24):
		var q: Vector2 = pts[i][1]
		_search_points.append(Vector3(q.x, terrain.h2(q), q.y))
	# From level 3 they know about the car washes: one near where you were
	# lost gets a look, a few looks in (not first: a quick wash still works).
	if level >= 3 and world != null:
		if _wash_spots.is_empty():
			_wash_spots = CarWashes.find_spots(world)
		for sp: Dictionary in _wash_spots:
			var o: Vector3 = (sp["xform"] as Transform3D).origin
			if Vector2(o.x, o.z).distance_to(c) <= r + 150.0:
				_search_points.insert(mini(WASH_LOOK_AT, _search_points.size()), CarWashes.way_in(sp, 10.0))


# --- level 3 and 4 extras ----------------------------------------------------------------

func _extras() -> void:
	if level < 3 or not seen_recently():
		return
	var t := target_body()
	var vel := _velocity_of(t)
	_strip_t -= 0.5
	_roadblock_t -= 0.5
	# A paint strip: a blocker ahead of the player, the player coming at it.
	if _strip_t <= 0.0 and player.vehicle != null and vel.length() > 8.0:
		for u in units:
			if u.role != PoliceUnit.Role.BLOCK or u.car == null or u.force == "tactical":
				continue
			var to := u.car.global_position - t.global_position
			var d := to.length()
			if d < 200.0 and d > 80.0 and to.normalized().dot(vel.normalized()) > 0.7:
				# On the road ahead along the street, not along the heading
				# (which misses on a bend), far enough off to be seen and
				# steered round (STRIP_AHEAD m, a few seconds at chase speed).
				var at := _road_ahead(t.global_position, vel, clampf(d * 0.7, STRIP_AHEAD.x, STRIP_AHEAD.y))
				if at != Vector3.INF and _lay_strip(at, Vector2(vel.x, vel.z).normalized()):
					_strip_t = STRIP_EVERY
					radio_say("strip", u, 1.0, 15.0)
					break
	# A roadblock a few junctions ahead, out of sight.
	if _roadblock_t <= 0.0 and roadblocks.size() < 2:
		var ahead := _junctions_ahead(t.global_position, vel, 4)
		# The bottleneck first: the junction ahead whose street in is narrowest.
		var fits: Array[Vector3] = []
		for j in ahead:
			var d := j.distance_to(t.global_position)
			if d < ROADBLOCK_MIN or d > ROADBLOCK_MAX or j.distance_to(_last_roadblock) < 30.0:
				continue
			if not _ground_at(j):
				continue
			fits.append(j)
		fits.sort_custom(func(a: Vector3, b: Vector3) -> bool: return _street_width_toward(a, t.global_position) < _street_width_toward(b, t.global_position))
		for j in fits:
			if _make_roadblock(j, t.global_position):
				_roadblock_t = ROADBLOCK_EVERY
				_last_roadblock = j
				break


## A point `dist` m further along the street p is on, the way vel goes
## (stopping short of the street's end), or INF.
func _road_ahead(p: Vector3, vel: Vector3, dist: float) -> Vector3:
	var hit := network.nearest_on_streets(Vector2(p.x, p.z), 20.0)
	if hit.is_empty():
		return Vector3.INF
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var along := float(hit["along"])
	var dir: Vector2 = RoadNetwork.sample(e.points, along)[1]
	var sign := 1.0 if dir.dot(Vector2(vel.x, vel.z)) >= 0.0 else -1.0
	var to := clampf(along + sign * dist, 4.0, maxf(4.0, e.length - 4.0))
	if absf(to - along) < dist * 0.5:
		return Vector3.INF # the street ends first: not here
	var q: Vector2 = RoadNetwork.sample(e.points, to)[0]
	return Vector3(q.x, p.y, q.y)


func _lay_strip(at: Vector3, dir: Vector2) -> bool:
	var hit := network.nearest_on_streets(Vector2(at.x, at.z), 15.0)
	if hit.is_empty():
		return false
	var e: RoadNetwork.RoadEdge = hit["edge"]
	var sp: Array = RoadNetwork.sample(e.points, float(hit["along"]))
	var q: Vector2 = sp[0]
	var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, at.y + 5.0, q.y), Vector3(q.x, at.y - 6.0, q.y), Layers.GROUND)
	var h := _w3d().direct_space_state.intersect_ray(ray)
	if h.is_empty():
		return false
	var road: Vector2 = sp[1]
	if road.dot(dir) < 0.0:
		road = -road
	# On a street wider than the strip it's thrown across one side or the
	# other (now and then the middle), leaving a gap to aim for.
	var spare := e.half_width - PoliceProps.STRIP_LENGTH * 0.5
	var at_pos: Vector3 = h["position"]
	if spare > 0.5 and _rng.randf() < 0.75:
		var right := Vector3(-road.y, 0.0, road.x)
		at_pos += right * spare * (1.0 if _rng.randf() < 0.5 else -1.0)
	PaintStrip.lay(world_root, at_pos, road)
	stats["strips"] = int(stats["strips"]) + 1
	return true


## Two cars (or, at level 4, now and then a harvester and two SUVs) across
## the street leading out of junction `j` toward the player, out of sight.
func _make_roadblock(j: Vector3, from: Vector3) -> bool:
	var jj := Vector2(j.x, j.z)
	var fp := Vector2(from.x, from.z)
	# The street from the junction back toward the player.
	var hit := network.nearest_on_streets(jj + (fp - jj).normalized() * 30.0, 20.0)
	if hit.is_empty():
		return false
	var e: RoadNetwork.RoadEdge = hit["edge"]
	if e.half_width > 9.0 or e.highway.begins_with("motorway"):
		return false
	var along := float(hit["along"])
	var sp: Array = RoadNetwork.sample(e.points, along)
	var q: Vector2 = sp[0]
	var dir: Vector2 = sp[1]
	if dir.dot(fp - q) < 0.0:
		dir = -dir
	var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, j.y + 6.0, q.y), Vector3(q.x, j.y - 6.0, q.y), Layers.GROUND)
	var h := _w3d().direct_space_state.intersect_ray(ray)
	if h.is_empty():
		return false
	var at: Vector3 = h["position"]
	if _hidden_from_player(at, at.distance_to(player.global_position)) == "":
		return false
	# Not on top of parked cars (or any other car): a street lined with them
	# where the cars would go is the wrong spot.
	if _cars_in_footprint(at, dir, e.half_width):
		return false
	var which := "harvester" if level >= 4 and _rng.randf() < 0.5 else "cars"
	var rb := PoliceRoadblock.build(self, world_root, at, dir, e.half_width, which, "fip")
	roadblocks.append(rb)
	stats["roadblocks"] = int(stats["roadblocks"]) + 1
	radio_say("harvester" if which == "harvester" else "roadblock", rb.units[0] if not rb.units.is_empty() else null, 1.0, 10.0)
	return true


## Parked or moving cars within the stretch of street a roadblock at `at`
## (street running along `dir`) would take.
func _cars_in_footprint(at: Vector3, dir: Vector2, half_width: float) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(half_width * 2.0, 2.0, 12.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), at + Vector3.UP * 1.2 + Vector3(dir.x, 0, dir.y) * 2.0)
	q.collision_mask = Layers.SOLID | Layers.VEHICLES
	for r: Dictionary in _w3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = r["collider"]
		if c is Car or (c is Node and (c as Node).name.begins_with("ParkedCars")):
			return true
	return false


# --- catching ----------------------------------------------------------------------------

func _check_caught(delta: float) -> void:
	var car := player.vehicle
	if car != null:
		var kmh := absf(car.speed) * 3.6
		_touch_check -= delta
		if _touch_check <= 0.0:
			_touch_check = 0.1
			_touching = _touching_police(car)
		# Pinned by two, the clock runs at full speed; by one, at half (a
		# single cruiser against a car turning round isn't an arrest yet).
		# A twitch over the speed doesn't reset it: it runs back down.
		var ring := level <= 2 and _touching >= 2 and kmh < BOX_RING_KMH
		if _touching > 0 and (kmh < BOX_KMH or ring):
			# At level 4, one car alone doesn't count: one side's clear,
			# you can still get out (a long fight, not a scrape at a corner).
			_box_t += delta * (1.0 if _touching >= 2 else float(BOX_ONE_RATE_BY_LEVEL[clampi(level, 0, 4)]))
			var need: float = BOX_TIME_BY_LEVEL[clampi(level, 0, 4)]
			if clock - _level_since < (BOX_GRACE * BOX_GRACE_L12_LONGER if level <= 2 else BOX_GRACE):
				need *= BOX_GRACE_FACTOR # the opening seconds: room to get away
			if _box_t >= need and not (level <= 2 and clock - _level_since < BOX_NONE_FIRST):
				_catch("boxed_in")
				return
		elif level <= 3 and kmh > BOX_KMH * 2.0:
			_box_t = 0.0 # got going again: a slow corner isn't a box-in
		else:
			_box_t = maxf(0.0, _box_t - delta * 1.5)
		# A stalled car, an officer at the door.
		if car.stalled:
			radio_say("car_stalled", null, 1.0, 30.0)
			var near := false
			for o in get_tree().get_nodes_in_group("officers"):
				var of := o as Officer
				if of.state == Officer.State.ON_FOOT and of.global_position.distance_to(car.door_point()) < ARREST_RANGE + 1.0:
					near = true
			_arrest_t = _arrest_t + delta if near else 0.0
			if _arrest_t >= ARREST_TIME:
				_catch("stalled_car")
				return
	else:
		_box_t = 0.0
		_arrest_t = 0.0
	var speed := _velocity_of(target_body()).length() * 3.6
	# Level 1: stop for the cruiser and that's that.
	if level == 1:
		var close := false
		var lights := false
		for u in units:
			if u.car != null and u.sees and u.car.global_position.distance_to(player.global_position) < PULL_OVER_RANGE:
				close = true
			if u.car != null and u.sees and u.car.global_position.distance_to(player.global_position) < 60.0:
				lights = true
		_pull_t = _pull_t + delta if close and speed < 3.0 and _chase_top <= 1 else 0.0
		if _pull_t >= PULL_OVER_TIME:
			_catch("pulled_over")
			return
		_flee_t = _flee_t + delta if lights and speed > FLEE_KMH else maxf(0.0, _flee_t - delta)
		if _flee_t >= FLEE_TIME:
			_flee_t = 0.0
			_wanted.report_crime("flee", player.global_position)


func _touching_police(car: Car) -> int:
	# Pinned: a police vehicle against the sides (within a metre at levels
	# 1-2, half a metre above) or the
	# ends (a metre), or stopped across the nose or tail within 3 m (a
	# box-in stops just short). You can still back out inside BOX_TIME.
	var hl := float(car.shape.get("length", 4.5)) * 0.5
	_box_shape.size = Vector3(float(car.shape.get("width", 1.8)) + (2.0 if level <= 2 else 1.0), 1.2, hl * 2.0 + 6.0)
	_box_q.transform = Transform3D(car.global_basis, car.global_transform * Vector3(0, 0.8, 0))
	_box_q.exclude = [car.get_rid()]
	var inv := car.global_transform.affine_inverse()
	var count := 0
	for r: Dictionary in _w3d().direct_space_state.intersect_shape(_box_q, 8):
		var c := r["collider"] as Car
		if c == null or not c.is_in_group("police_vehicles"):
			continue
		# Nosing up to a roadblock isn't being boxed in: it's a roadblock.
		var pu: Variant = c.get_meta("police_unit", null)
		if pu is PoliceUnit and (pu as PoliceUnit).roadblock != null:
			continue
		var local := inv * c.global_position
		# Its half extent along our length (end on, its length; across us,
		# its width).
		var ax := absf(c.global_basis.z.dot(car.global_basis.z))
		var their_hl := lerpf(float(c.shape.get("width", 2.0)), float(c.shape.get("length", 4.8)), ax) * 0.5
		var end_gap := absf(local.z) - hl - their_hl
		if end_gap < 1.0 or absf(c.speed) < 1.5:
			count += 1
	return count


func _catch(how: String) -> void:
	_reset_catch()
	stats["caught_by"] = how
	_was_caught = true
	radio_say("boxed_in" if how == "boxed_in" else ("pulled_over" if how == "pulled_over" else "caught"), null, 1.0, 0.0)
	_wanted.caught()


# --- the chase starting and ending -------------------------------------------------------

## Something happened to an officer: count it.
func officer_went_out(u: PoliceUnit) -> void:
	stats["officers_out"] = int(stats["officers_out"]) + 1
	radio_say("officer_out", u, 1.0, 4.0)


func _reset_catch() -> void:
	_box_t = 0.0
	_pull_t = 0.0
	_flee_t = 0.0
	_arrest_t = 0.0
	_touching = 0
	_touch_check = 0.0


func _on_level_changed(l: int) -> void:
	_level_since = clock
	if l == 0:
		_reset_catch()
		_chase_top = 0
	_chase_top = maxi(_chase_top, l)
	match l:
		1:
			if not seen_recently():
				radio_say("call_in", null, 1.0, 0.0)
		2:
			radio_say("level_2", null, 1.0, 0.0)
		3:
			radio_say("fip_called", null, 1.0, 0.0)
			if _fip_after < 0.0 or clock > _fip_after + 120.0:
				_fip_after = clock + _rng.randf_range(PAPERWORK.x, PAPERWORK.y)
				_paperwork_said = false
			_roadblock_t = maxf(_roadblock_t, ROADBLOCK_FIRST)
		4:
			radio_say("level_4", null, 1.0, 0.0)
		0:
			_chase_over()
	for u in units:
		u.level = l


func _on_announced(title: String, _sub: String) -> void:
	if title.contains("Overreach is over"):
		radio_say("overtime", null, 1.0, 0.0)


func _chase_over() -> void:
	if not _was_caught:
		radio_say("escaped", null, 1.0, 0.0)
	else:
		radio_say("caught", null, 0.6, 0.0)
	_was_caught = false
	known_car = null
	_last_seen = -1000.0
	_search_points.clear()
	for rb in roadblocks:
		if is_instance_valid(rb):
			rb.clear()
	roadblocks.clear()
	# A stalled car is impounded when the chase ends (a moment later: caught,
	# the panels move the player out of it first).
	var cars := _chase_cars.duplicate()
	_chase_cars.clear()
	_impound_later(cars)
	for u in units:
		if u.role != PoliceUnit.Role.PATROL:
			u.order(PoliceUnit.Role.LEAVE, _leave_point(u), clock)


func _impound_later(cars: Array[Car]) -> void:
	if is_inside_tree():
		await get_tree().create_timer(2.5, false).timeout
	var lot := ImpoundLot.find(get_tree()) if is_inside_tree() else null
	if lot == null or level > 0:
		return
	for c in cars:
		if is_instance_valid(c) and c.stalled:
			if player.vehicle == c:
				# Still sitting in it: it's towed once they get out.
				_tow_when_left.append(c)
				continue
			lot.impound(c)
			radio_say("impound", null, 1.0, 0.0)


## Stalled cars the player sat in when the chase ended: towed once they
## step out (and walk off a little).
var _tow_when_left: Array[Car] = []


func _tow_check() -> void:
	for c: Car in _tow_when_left.duplicate():
		if not is_instance_valid(c) or not c.stalled:
			_tow_when_left.erase(c)
		elif player.vehicle != c and player.global_position.distance_to(c.global_position) > 15.0:
			_tow_when_left.erase(c)
			var lot := ImpoundLot.find(get_tree())
			if lot != null:
				lot.impound(c)
				radio_say("impound", null, 1.0, 0.0)

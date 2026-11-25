class_name RideFares
extends RefCounted
## Giving people rides: the first small job in town (PedestrianManager).
##
## Now and then, while the player is driving (and not wanted), someone on
## the sidewalk ahead stops at the curb and waves, with what they'll pay
## over their head ("Need a lift! $48"). Pull up beside them and stop: they
## walk to the passenger door and get in (PassengerSeat), say where they're
## going (a real place: TrafficDestinations), and the GPS gets the way
## there. They talk on the way (too fast, a crash, lost, small talk). Stop
## near the place and they get out, pay and walk in.
##
## The pay is what they offered, more for a quick ride and less for a slow
## one or for every knock on the way:
##     pay = offer x time x 0.85^crashes x (0.9 if driven like the Gold Cup)
## where time is 1.2 at well under the expected time, 1.0 at it, down to
## 0.6 at twice it. Getting out of the car, the police after you, or
## parking them on the curb by driving at them (they jump clear) loses the
## fare: no pay.

## The first hail comes this long after the start (s), the rest between
## these after the last ride ends.
const FIRST_HAIL := 20.0
const HAIL_GAP := [35.0, 70.0]
## Someone hails from this far off the player's car (m).
const HAIL_NEAR := 35.0
const HAIL_FAR := 130.0
## They give up waving after this (s), or once the player's this far off (m).
const HAIL_PATIENCE := 120.0
const HAIL_LOSE := 230.0
## Close enough to get in: their door this near them, the car this slow.
const PICKUP_REACH := 9.0
const PICKUP_SPEED := 1.6
## At the place: this near it, this slow.
const DROP_REACH := 26.0
const DROP_SPEED := 2.2
## The offer: a base and so much a metre (straight line).
const BASE_PAY := 12.0
const PAY_PER_M := 0.05
## Expected speed along the streets (m/s), for the time factor.
const EXPECTED_SPEED := 9.0

var manager: PedestrianManager
var hailer: Pedestrian = null
var rider: Pedestrian = null
var car: Car = null
## Rides finished and money made (for tests and the record).
var rides := 0
var earned := 0

var _hail_in := FIRST_HAIL
var _announced := false
var _tipped := false
var _ride_t := 0.0
var _expected := 60.0
var _crashes := 0
var _fast := 0
var _talk_in := 0.0
var _fast_said := -100.0
var _slow_said := false
var _police_said := false
var _street := ""


func _init(m: PedestrianManager) -> void:
	manager = m


## The car the player is driving (not riding in), or null.
func _player_car() -> Car:
	var pl := manager.player
	if pl == null or not is_instance_valid(pl) or bool(pl.get("passenger")):
		return null
	var v: Variant = pl.get("vehicle")
	return v as Car if v is Car else null


func tick(delta: float) -> void:
	if rider != null:
		_riding(delta)
	elif hailer != null:
		_hailing(delta)
	else:
		var c := _player_car()
		if c == null or manager.wanted_level() > 0 or not manager.running:
			return
		_hail_in -= delta
		if _hail_in <= 0.0:
			_hail_in = 5.0 # try again soon if nobody's about
			_pick_hailer(c)


func _pick_hailer(c: Car) -> void:
	var cp := Vector2(c.global_position.x, c.global_position.z)
	var fwd := -c.global_basis.z
	var ahead := Vector2(fwd.x, fwd.z).normalized()
	var best: Pedestrian = null
	var best_score := -INF
	for p: Pedestrian in manager.people:
		if p.state != Pedestrian.State.WALK or p.kind == "jogger" or p.in_road() or not p.fare.is_empty():
			continue
		var rel := p.position2() - cp
		var d := rel.length()
		if d < HAIL_NEAR or d > HAIL_FAR:
			continue
		# Ahead of the car, by the street it's on, is best.
		var score := rel.normalized().dot(ahead) * 2.0 - d / HAIL_FAR + manager.rng.randf() * 0.5
		if score > best_score:
			best_score = score
			best = p
	if best == null:
		return
	var from := best.position2()
	var dest := manager.dests.pick(manager.rng, from, 400.0, 1600.0)
	if dest.is_empty():
		return
	var offer := roundi(BASE_PAY + from.distance_to(dest["street"]) * PAY_PER_M)
	var street := manager.net.nearest_on_streets(from, 30.0)
	var face := best._heading
	if not street.is_empty():
		face = ((street["pos"] as Vector2) - from).normalized()
	best.fare = {"dest": dest, "offer": offer, "face": face, "since": 0.0}
	best.set_goal(dest)
	best.hail("%s  %s" % [PedestrianLines.pick(best.rng, PedestrianLines.HAIL), CarModels.dollars(offer)])
	hailer = best
	_announced = false


func _hailing(delta: float) -> void:
	if not is_instance_valid(hailer) or hailer.fare.is_empty():
		_end_hail()
		return
	hailer.fare["since"] = float(hailer.fare["since"]) + delta
	var c := _player_car()
	var hp := hailer.global_position
	if hailer.state == Pedestrian.State.BOARD:
		if c != hailer.fare.get("car") or c == null or absf(c.speed) > PICKUP_SPEED * 2.0:
			lost(hailer) # drove off on them
		return
	if hailer.state != Pedestrian.State.HAIL:
		_end_hail()
		return
	var far := c == null or c.global_position.distance_to(hp) > HAIL_LOSE
	if float(hailer.fare["since"]) > HAIL_PATIENCE or (far and float(hailer.fare["since"]) > 20.0) or manager.wanted_level() > 0:
		hailer.resume_walking()
		_end_hail()
		return
	if c == null:
		return
	var d := c.global_position.distance_to(hp)
	# The waving and their shout say it all; only the very first time, a
	# small tip in the corner says how.
	if not _announced and d < 60.0 and manager.hud != null:
		_announced = true
		if rides == 0 and not _tipped:
			_tipped = true
			manager.hud.show_tip("Someone's waving for a ride: stop beside them")
	if absf(c.speed) < PICKUP_SPEED and PassengerSeat.door_point(c).distance_to(hp) < PICKUP_REACH:
		var seat := PassengerSeat.of(c)
		if seat.occupant == null:
			hailer.fare["car"] = c
			hailer.board()


func _end_hail() -> void:
	hailer = null
	_hail_in = manager.rng.randf_range(float(HAIL_GAP[0]) * 0.5, float(HAIL_GAP[1]) * 0.5)


## Someone after a ride lost it (a fright, a car at them): back to walking.
func lost(p: Pedestrian) -> void:
	if p != hailer or p == rider:
		return
	if p.state == Pedestrian.State.HAIL or p.state == Pedestrian.State.BOARD:
		p.resume_walking()
	else:
		p.fare = {}
	_end_hail()


## At the door: in they get.
func board(p: Pedestrian) -> void:
	var c: Car = p.fare.get("car")
	if c == null or not is_instance_valid(c):
		lost(p)
		return
	var seat := PassengerSeat.of(c)
	if seat.occupant != null:
		lost(p)
		return
	hailer = null
	rider = p
	car = c
	p.set_riding(true)
	seat.sit(p, p.model, null)
	var dest: Dictionary = p.fare["dest"]
	var at: Vector2 = dest["street"]
	var hit := manager.net.nearest_on_streets(at, 30.0)
	_street = str((hit["edge"] as RoadNetwork.RoadEdge).name) if not hit.is_empty() else ""
	if _street == "":
		_street = "Just up the road"
	var from := Vector2(c.global_position.x, c.global_position.z)
	_expected = from.distance_to(at) * 1.35 / EXPECTED_SPEED + 25.0
	_ride_t = 0.0
	_crashes = 0
	_fast = 0
	_fast_said = -100.0
	_slow_said = false
	_police_said = false
	_talk_in = manager.rng.randf_range(15.0, 30.0)
	p.say(PedestrianLines.pick(p.rng, PedestrianLines.BOARD) % _street, 4.0)
	var gps := Gps.find(manager.get_tree())
	if gps != null:
		gps.set_waypoint(Vector3(at.x, manager.world.terrain.h2(at), at.y), "Drop-off: %s" % _street)
	if manager.hud != null:
		manager.hud.show_title("Fare to %s" % _street, "about %s · the GPS has the way" % CarModels.dollars(int(p.fare["offer"])))
	if not c.crashed.is_connected(_on_crash):
		c.crashed.connect(_on_crash)


func _on_crash(impact: float) -> void:
	if rider == null or impact < 4.0:
		return
	_crashes += 1
	rider.say(PedestrianLines.pick(rider.rng, PedestrianLines.RIDE_CRASH), 3.0)


func _riding(delta: float) -> void:
	if not is_instance_valid(rider):
		_end_ride()
		return
	if car == null or not is_instance_valid(car):
		manager.people.erase(rider)
		rider.queue_free()
		_end_ride()
		return
	_ride_t += delta
	var speed := absf(car.speed)
	var driving := _player_car() == car
	# The player got out, or the police are after us: out at the first stop.
	if not driving or manager.wanted_level() > 0:
		if manager.wanted_level() > 0 and not _police_said:
			_police_said = true
			rider.say(PedestrianLines.pick(rider.rng, PedestrianLines.RIDE_POLICE), 3.5)
		if speed < 1.0:
			_drop(false)
		return
	var dest: Dictionary = rider.fare["dest"]
	var at: Vector2 = dest["street"]
	var here := Vector2(car.global_position.x, car.global_position.z)
	if here.distance_to(at) < DROP_REACH and speed < DROP_SPEED:
		_drop(true)
		return
	# Talk on the way.
	if speed > 22.0 and _ride_t - _fast_said > 8.0:
		_fast_said = _ride_t
		_fast += 1
		rider.say(PedestrianLines.pick(rider.rng, PedestrianLines.RIDE_FAST), 3.0)
	elif not _slow_said and _ride_t > _expected * 1.4:
		_slow_said = true
		rider.say(PedestrianLines.pick(rider.rng, PedestrianLines.RIDE_SLOW), 3.5)
	else:
		_talk_in -= delta
		if _talk_in <= 0.0:
			_talk_in = manager.rng.randf_range(25.0, 45.0)
			if not rider.saying:
				rider.say(PedestrianLines.pick(rider.rng, PedestrianLines.RIDE_CHAT), 3.5)


## Out of the car: paid (`arrived`), or not.
func _drop(arrived: bool) -> void:
	var p := rider
	var c := car
	var seat := PassengerSeat.of(c)
	var xf := seat.exit_transform()
	seat.leave()
	p.reparent(manager)
	p.get_out_at(xf, arrived)
	var gps := Gps.find(manager.get_tree())
	if gps != null and gps.active and gps.place.begins_with("Drop-off"):
		gps.clear()
	if arrived:
		var time := 1.0
		var r := _ride_t / maxf(_expected, 1.0)
		if r < 1.0:
			time = lerpf(1.2, 1.0, clampf((r - 0.5) / 0.5, 0.0, 1.0))
		else:
			time = lerpf(1.0, 0.6, clampf(r - 1.0, 0.0, 1.0))
		var mult := time * pow(0.85, _crashes) * (0.9 if _fast > 1 else 1.0)
		var pay := maxi(5, roundi(float(p.fare["offer"]) * mult))
		var gs := manager.get_node_or_null("/root/GameState")
		if gs != null:
			gs.call("add_money", pay)
		rides += 1
		earned += pay
		var lines: Array = PedestrianLines.PAID_GOOD if mult >= 0.95 else (PedestrianLines.PAID_OK if mult >= 0.7 else PedestrianLines.PAID_BAD)
		var line := PedestrianLines.pick(p.rng, lines)
		p.say(line, 4.0)
		if manager.hud != null:
			manager.hud.show_title("Fare paid: %s" % CarModels.dollars(pay), "\"%s\"" % line)
	else:
		p.say(PedestrianLines.pick(p.rng, PedestrianLines.BAIL), 3.5)
		if manager.hud != null:
			manager.hud.show_title("Your passenger got out", "no fare")
	p.fare = {}
	_end_ride()


func _end_ride() -> void:
	if car != null and is_instance_valid(car) and car.crashed.is_connected(_on_crash):
		car.crashed.disconnect(_on_crash)
	rider = null
	car = null
	_hail_in = manager.rng.randf_range(float(HAIL_GAP[0]), float(HAIL_GAP[1]))

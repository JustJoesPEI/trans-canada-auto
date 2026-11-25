class_name CarWashes
extends Node
## The car washes as the game sees them: the pay-and-spray (design.md
## section 7, "Getting away"). Roll a car into a bay ("prop=car_wash" points
## placed in data/edits.json, drawn by PlacedProps with CarWashModel) and
## stay in it for WASH_SECONDS: the paint comes off (the car's
## PaintCoverage, if it has one, is cleared), and if no officer saw you go
## in, or saw you while you were in there, so does the wanted level, at
## every level. If they saw, it's a clean car and they're waiting outside.
##
## One node for all of them, checking the player's car against each bay a
## few metres at a time: no physics areas, nothing per chunk.

## Seconds in the bay to come out clean (a slow roll through its 14 m).
const WASH_SECONDS := 8.0
## How far up and down from the floor a car still counts as inside (m).
const HEIGHT_SLACK := 3.0

## Each bay: {"xform": Transform3D (floor centre, -Z the way out), "name",
## "line" (what the HUD says the first time you go in)}.
var spots: Array[Dictionary] = []
var world: Node = null
var player: Node = null
var hud: Node = null

## The bay the car is in now (-1: none), how long it's been in, whether an
## officer saw it go in or while inside, and whether it's done.
var _in := -1
var _time := 0.0
var _seen := false
var _done := false


## Hooks it up to the town (for the bays), the player (whose car it
## watches) and the HUD (for the titles and the suds bar).
func setup(w: Node, p: Node, h: Node) -> void:
	world = w
	player = p
	hud = h
	spots = find_spots(w)
	# On the minimap, to find them when you need one.
	var mm: Variant = h.get("minimap") if h != null else null
	if mm is Node and (mm as Node).has_method("set_marker"):
		for i in spots.size():
			(mm as Node).call("set_marker", "car_wash_%d" % i, "car_wash", (spots[i]["xform"] as Transform3D).origin)


## Every car wash bay placed on the map, from the hand edits.
static func find_spots(w: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if w == null or w.get("data") == null:
		return out
	var edits: Dictionary = w.get("data").get("edits")
	for f: Variant in edits.get("new_features", []):
		if not (f is Dictionary) or not (f as Dictionary).has("pos"):
			continue
		var tags: Dictionary = (f as Dictionary).get("tags", {})
		if str(tags.get("type", "")) != "prop=car_wash":
			continue
		var xf: Transform3D = w.call("edit_xform", {"pos": f["pos"], "direction": str(tags.get("direction", "0")).to_float()}, 0.0)
		out.append({"xform": xf, "name": str(tags.get("name", "Car wash")), "line": str(tags.get("tca:line", ""))})
	return out


## Where to line up to drive into a bay: a car length outside its way in
## (the bay's +Z end; -Z is the way out), on the bay's floor. The side
## walls are solid, so a driver (a player, or a computer one heading for a
## wash) gets here first and then drives straight in.
static func way_in(spot: Dictionary, clear := 6.0) -> Vector3:
	var xf: Transform3D = spot["xform"]
	return xf.origin + xf.basis.z * (CarWashModel.HALF_LENGTH + clear)


## Which bay `at` is in (-1 for none).
func bay_at(at: Vector3) -> int:
	for i in spots.size():
		var local: Vector3 = (spots[i]["xform"] as Transform3D).affine_inverse() * at
		if absf(local.x) <= CarWashModel.HALF_WIDTH and absf(local.z) <= CarWashModel.HALF_LENGTH \
				and absf(local.y) <= HEIGHT_SLACK:
			return i
	return -1


func _physics_process(delta: float) -> void:
	var car: Node3D = player.get("vehicle") if player != null else null
	update(delta, car)


## One step: `car` is the player's car (null on foot). Returns what
## happened: "" (nothing new), "enter", "leave", "washed" (paint off, not
## wanted), "cleared" (paint and wanted level gone), "seen" (paint off,
## they saw you go in).
func update(delta: float, car: Node3D) -> String:
	var bay := bay_at(car.global_position) if car != null else -1
	var wanted := _wanted()
	if bay != _in:
		var left := _in >= 0
		_in = bay
		_time = 0.0
		_done = false
		_seen = wanted != null and bool(wanted.call("seen_recently"))
		_wash_bar(-1.0)
		if bay < 0:
			return "leave" if left else ""
		_title(str(spots[bay]["name"]), "Roll through slowly: about %d seconds of suds." % roundi(WASH_SECONDS))
		return "enter"
	if bay < 0 or _done:
		return ""
	_time += delta
	if wanted != null and bool(wanted.call("seen_recently")):
		_seen = true
	_wash_bar(_time / WASH_SECONDS)
	if _time < WASH_SECONDS:
		return ""
	_done = true
	_wash_bar(-1.0)
	wash_paint(car)
	var level := int(wanted.get("level")) if wanted != null else 0
	if level == 0:
		_title("Squeaky clean", _line(bay, "That red dirt never really comes out, though."))
		return "washed"
	if _seen or not bool(wanted.call("car_wash")):
		_title("They saw you go in", "Clean car, same wanted level. They're waiting outside.")
		return "seen"
	_title("Squeaky clean", "Nobody saw you go in. The paint's gone, and so are they.")
	return "cleared"


## Takes the paint off a car: clear() on its PaintCoverage, if the paint
## piece has given it one. True if there was one to clear.
static func wash_paint(car: Node) -> bool:
	if car == null:
		return false
	var pc := car.get_node_or_null("PaintCoverage")
	if pc == null:
		for c in car.get_children():
			var s: Variant = c.get_script()
			if s is Script and (s as Script).get_global_name() == &"PaintCoverage":
				pc = c
				break
	if pc == null or not pc.has_method("clear"):
		return false
	pc.call("clear")
	return true


func _line(bay: int, fallback: String) -> String:
	var l := str(spots[bay].get("line", ""))
	return l if l != "" else fallback


func _wanted() -> Node:
	return get_tree().root.get_node_or_null("Wanted") if is_inside_tree() else null


func _title(t: String, sub: String) -> void:
	if hud != null and hud.has_method("show_title"):
		hud.call("show_title", t, sub)


func _wash_bar(amount: float) -> void:
	var wh: Variant = hud.get("wanted_hud") if hud != null else null
	if wh is Node and (wh as Node).has_method("set_wash"):
		(wh as Node).call("set_wash", amount)

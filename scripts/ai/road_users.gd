class_name RoadUsers
extends RefCounted
## Everything a computer driver has to watch out for on the road, gathered
## once per physics step and shared by every driver (CivilDriving): the
## cars (group "vehicles": driven, computer-driven and parked ones), the
## vehicles moving without physics (RoadFollower, group "road_followers"),
## and people on foot (group "people_on_foot": the player while walking,
## pedestrians while they're crossing a street).
##
## Each entry is a User: where it is, how it's moving and how big it is, on
## the ground plane (Vector2(x, z)). Rebuilt lazily: the first driver to ask
## in a physics step pays for it, the rest read the same list, reusing the
## entries. On a server (TrafficDensity.server) it's gathered every
## SERVER_REFRESH_EVERY physics steps instead (a step-old position is a
## few tenths of a metre at town speeds). With a lot of
## traffic about (a server with many players), asking for the ones `near` a
## spot reads a grid of them rather than the whole list.

const PEOPLE_GROUP := "people_on_foot"
const FOLLOWER_GROUP := "road_followers"


class User:
	var node: Node3D
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var fwd := Vector2.UP
	var speed := 0.0 ## along fwd (m/s), negative backing up
	var half_len := 2.3
	var half_wid := 0.9
	var person := false
	## A police vehicle with its siren on.
	var siren := false
	## Its civil driver, if it has one (for "is it waiting on purpose").
	var civil: CivilDriving = null


static var _frame := -1
static var _list: Array[User] = []
static var _by_node := {}
## The users by grid square (GRID metres), built with the list.
static var _grid := {}
const GRID := 64.0
const SERVER_REFRESH_EVERY := 2


## Every road user this physics step (or the one before).
static func all(tree: SceneTree) -> Array[User]:
	var f := Engine.get_physics_frames()
	if f >= _frame and f - _frame < (SERVER_REFRESH_EVERY if TrafficDensity.server else 1):
		return _list
	_frame = f
	_list = []
	var old := _by_node
	_by_node = {}
	_grid = {}
	for n: Node in tree.get_nodes_in_group("vehicles"):
		var c := n as Car
		if c == null or not c.is_inside_tree():
			continue
		var u := _entry(old, c)
		var p := c.global_position
		u.pos = Vector2(p.x, p.z)
		u.vel = c.plane_velocity
		var f3 := -c.global_basis.z
		u.fwd = Vector2(f3.x, f3.z).normalized()
		u.speed = c.speed
		u.half_len = float(c.shape.get("length", 4.6)) * 0.5
		u.half_wid = float(c.shape.get("width", 1.8)) * 0.5
		u.siren = c.police != null and c.police.mode == PoliceGear.Mode.SIREN
		var ap := c.ai_controls as CarAutopilot
		u.civil = ap.civil if ap != null else null
		_add(u)
	for n: Node in tree.get_nodes_in_group(FOLLOWER_GROUP):
		var rf := n as RoadFollower
		if rf == null or not rf.is_inside_tree():
			continue
		var u := _entry(old, rf)
		var p := rf.global_position
		u.pos = Vector2(p.x, p.z)
		u.vel = Vector2(rf.velocity.x, rf.velocity.z)
		var f3 := -rf.global_basis.z
		u.fwd = Vector2(f3.x, f3.z).normalized()
		u.speed = rf.speed
		u.half_len = rf.half_length
		u.half_wid = rf.half_width
		u.civil = rf.civil
		_add(u)
	for n: Node in tree.get_nodes_in_group(PEOPLE_GROUP):
		var b := n as Node3D
		if b == null or not b.is_inside_tree() or not b.is_visible_in_tree() or b.get("vehicle") != null:
			continue
		var u := _entry(old, b)
		var p := b.global_position
		u.pos = Vector2(p.x, p.z)
		var v := Vector3.ZERO
		if b is CharacterBody3D:
			v = (b as CharacterBody3D).velocity
		elif b.get("velocity") is Vector3:
			v = b.get("velocity") # a pedestrian crossing (Pedestrian)
		u.vel = Vector2(v.x, v.z)
		var f3 := -b.global_basis.z
		u.fwd = Vector2(f3.x, f3.z).normalized()
		u.speed = u.vel.length()
		u.half_len = 0.35
		u.half_wid = 0.35
		u.person = true
		_add(u)
	return _list


## The entry it had last time (filled in afresh), or a new one.
static func _entry(old: Dictionary, n: Node3D) -> User:
	var u: User = old.get(n)
	if u == null:
		u = User.new()
		u.node = n
	return u


static func _add(u: User) -> void:
	_list.append(u)
	_by_node[u.node] = u
	var k := Vector2i(floori(u.pos.x / GRID), floori(u.pos.y / GRID))
	var cell: Variant = _grid.get(k)
	if cell == null:
		var a: Array[User] = [u]
		_grid[k] = a
	else:
		(cell as Array).append(u)


## The road users this step within about `radius` of p: every one within
## it, and some a little further (whole grid squares), so check the
## distance as before.
static func near(tree: SceneTree, p: Vector2, radius: float) -> Array[User]:
	all(tree)
	var lo := Vector2i(floori((p.x - radius) / GRID), floori((p.y - radius) / GRID))
	var hi := Vector2i(floori((p.x + radius) / GRID), floori((p.y + radius) / GRID))
	var out: Array[User] = []
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			var cell: Variant = _grid.get(Vector2i(x, z))
			if cell != null:
				out.append_array(cell)
	return out


## The entry for a node this step, or null.
static func of(tree: SceneTree, n: Node) -> User:
	all(tree)
	return _by_node.get(n)

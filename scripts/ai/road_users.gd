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
## in a physics step pays for it, the rest read the same list.

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


## Every road user this physics step.
static func all(tree: SceneTree) -> Array[User]:
	var f := Engine.get_physics_frames()
	if f == _frame:
		return _list
	_frame = f
	_list = []
	_by_node = {}
	for n: Node in tree.get_nodes_in_group("vehicles"):
		var c := n as Car
		if c == null or not c.is_inside_tree():
			continue
		var u := User.new()
		u.node = c
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
		if ap != null:
			u.civil = ap.civil
		_add(u)
	for n: Node in tree.get_nodes_in_group(FOLLOWER_GROUP):
		var rf := n as RoadFollower
		if rf == null or not rf.is_inside_tree():
			continue
		var u := User.new()
		u.node = rf
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
		var u := User.new()
		u.node = b
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


static func _add(u: User) -> void:
	_list.append(u)
	_by_node[u.node] = u


## The entry for a node this step, or null.
static func of(tree: SceneTree, n: Node) -> User:
	all(tree)
	return _by_node.get(n)

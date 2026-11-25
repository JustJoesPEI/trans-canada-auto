class_name RoadFollower
extends Node3D
## A vehicle moving along the streets without physics: a position and a
## heading advanced along a StreetRoute at a speed, slowing for corners the
## way a driver would. Costs next to nothing, so it's for units nobody can
## see (police heading in from far off, or searching a far corner). When it
## comes near the player, `hand_over` puts a real Car where it is, moving
## as it was, with a CarAutopilot carrying on to the same place.
##
## With civil driving (`civil`, set by its owner) it keeps its distance,
## stops at lights and gives way like a car would: the owner works out
## `max_speed` from it each step (CivilDriving.want_speed). It's in group
## "road_followers" so other drivers see it (RoadUsers).
##
## Its height comes from the terrain (the street collision may not be built
## out there), so on a bridge it runs at ground level until handed over.

signal arrived

## Speed along the streets (km/h).
@export var speed_kmh := 50.0
## How quickly it gets up to speed and slows (m/s^2), roughly a car's.
@export var accel := 2.5
@export var decel := 5.0
## Keep to one-way streets (off for a chase).
@export var obey_oneway := true

var network: RoadNetwork
var terrain: Terrain
var route: StreetRoute = null
var along := 0.0
var speed := 0.0 ## m/s now
var velocity := Vector3.ZERO
var destination := Vector3.ZERO
var moving := false
## A cap on its speed (m/s) set from outside each step (civil driving).
var max_speed := INF
## Its road manners, if it has any (see above).
var civil: CivilDriving = null
## Its size, for the drivers round it (a car's, by default).
var half_length := 2.3
var half_width := 0.9

## How far either side of where it is (m) the heading is averaged over.
const TURN_EASE := 2.5


func _ready() -> void:
	add_to_group(RoadUsers.FOLLOWER_GROUP)
	if network == null:
		network = CarAutopilot.find_network(self)
	if terrain == null:
		for n: Node in get_tree().root.get_children():
			var w: Node = n if n is WorldBuilder else n.get_node_or_null("World")
			if w is WorldBuilder:
				terrain = (w as WorldBuilder).terrain
				break


## Head along the streets to a point (from where it is now).
func go_to(point: Vector3) -> void:
	destination = point
	var f := -global_basis.z
	route = StreetRoute.plan(network, Vector2(global_position.x, global_position.z), Vector2(point.x, point.z), {
		"obey_oneway": obey_oneway, "heading": Vector2(f.x, f.z)})
	along = 0.0
	moving = not route.is_empty()
	if moving:
		_place()


## Drive a given route instead of planning one.
func set_route(r: StreetRoute) -> void:
	route = r
	along = 0.0
	moving = not r.is_empty()
	if moving:
		destination = Vector3(r.goal.x, global_position.y, r.goal.y)
		_place()


func _physics_process(delta: float) -> void:
	if not moving:
		speed = 0.0
		velocity = Vector3.ZERO
		return
	var want := minf(minf(speed_kmh / 3.6, route.limit_at(along + speed * 0.3)), max_speed)
	speed = move_toward(speed, want, (accel if want > speed else decel) * delta)
	var before := global_position
	along += maxf(speed, 0.3 if along < route.length - 0.5 and max_speed > 0.3 else 0.0) * delta
	if along >= route.length - 0.5:
		along = route.length
		moving = false
		_place()
		speed = 0.0
		velocity = Vector3.ZERO
		arrived.emit()
		return
	_place()
	velocity = (global_position - before) / maxf(delta, 0.0001)


func _place() -> void:
	var p := route.sample(along)
	# Facing along the chord from a little behind to a little ahead: it
	# turns smoothly round the line's corners, where the line's own
	# direction turns all at once at each of its points (and a far-off car
	# snapped round with it, every 2 m of a tight turn).
	var d := route.sample(along + TURN_EASE) - route.sample(along - TURN_EASE)
	if d.length_squared() < 0.25:
		d = route.dir_at(along)
	d = d.normalized()
	var y := global_position.y
	if terrain != null:
		y = terrain.h2(p)
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.y)), Vector3(p.x, y, p.y))


## Put a real car here, moving as this was, driven on to the same place.
## The car is added to `parent` (this node's parent by default), and this
## follower is freed. Returns the car's autopilot.
func hand_over(car: Car, parent: Node = null) -> CarAutopilot:
	if parent == null:
		parent = get_parent()
	if car.get_parent() == null:
		parent.add_child(car)
	car.global_transform = Transform3D(global_basis, global_position + Vector3.UP * 0.35)
	car.reset_physics_interpolation()
	# The one moment a car's velocity is set: it appears already moving.
	car.linear_velocity = velocity
	car.angular_velocity = Vector3.ZERO
	var ap := CarAutopilot.new()
	ap.name = "Autopilot"
	ap.network = network
	ap.cruise_speed_kmh = speed_kmh
	car.add_child(ap)
	if moving:
		ap.drive_to(destination)
	else:
		ap.stop()
	queue_free()
	return ap

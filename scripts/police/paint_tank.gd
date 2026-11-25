class_name PaintTank
extends Node3D
## The FIP Tactical Unit's paint cannon, on the roof of the Paint Tank
## (docs/design.md section 7, "Level 4: Federal Overreach"). A child of the
## tank's Car. The turret turns to the target and the barrel lifts for the
## range; it fires a big slow paint round through PaintShots every
## RELOAD seconds when it has a clear shot. One hit on a car puts it at
## 80% police paint at once (HIT_COVERAGE: the engine coughs, top speed
## down a third), and the round bursts over a big patch of road
## (SPLAT_SIZE), which stays like an event's aftermath.

const RELOAD := 9.0
## After a hit on a car it holds fire this long: an 80% car is a moment,
## with time to run for a wash, not a death sentence.
const HOLD_AFTER_HIT := 25.0
## Fires at a target within this (m), and not closer than MIN_RANGE (the
## crew aren't allowed to hit themselves).
const RANGE := 80.0
const MIN_RANGE := 8.0
## A hit on a car tops its police paint up to this (design.md).
const HIT_COVERAGE := 0.8
## m: the splat of road a round leaves.
const SPLAT_SIZE := 2.6

## The cannon's round, as a PaintShots weapon: a lobbed bomb that bursts
## where it lands. The direct hit's coverage is topped up to HIT_COVERAGE
## by `_on_hit`.
const CANNON := {
	"id": "paint_cannon", "name": "Paint Cannon", "kind": "bomb",
	"speed": 48.0, "spread": 0.6,
	"hit_value": 2,
	"colour": null, "police": true,
	"splash_radius": 6.0, "splash_hits": 2,
	"car_coverage": 0.2, "splash_car_coverage": 0.25,
	"splat_size": 1.4,
	"gravity_scale": 1.0, "life": 5.0, "fuse": 0.0,
	"fire_rate": 0.25, "hold_rate": 0.0, "hopper": 999, "reload_time": 0.0,
}

var unit: PoliceUnit
var _turret: MeshInstance3D
var _barrel: MeshInstance3D
var _wait := 2.0
var _connected := false
var _sight := PhysicsRayQueryParameters3D.new()
## Hits on cars so far (for checks).
var hits := 0
var shots := 0
## The physics frame of the last direct hit: a round can report its hit on
## a car twice (two of its shapes) in one step.
var _hit_frame := -1


func _ready() -> void:
	add_to_group("police")
	var car := get_parent() as Car
	var roof := float(car.shape["cabin"]["roof"])
	position = Vector3(0, roof, 0.2)
	_turret = MeshInstance3D.new()
	_turret.name = "Turret"
	_turret.mesh = PoliceProps.cannon_mesh()
	add_child(_turret)
	_barrel = MeshInstance3D.new()
	_barrel.name = "Barrel"
	_barrel.mesh = PoliceProps.barrel_mesh()
	_barrel.position = Vector3(0, 0.42, -0.55)
	_turret.add_child(_barrel)
	_sight.collision_mask = Layers.SOLID


func _physics_process(delta: float) -> void:
	var car := get_parent() as Car
	if car == null or unit == null or unit.dispatcher == null:
		return
	_connect()
	var target := unit.dispatcher.target_body()
	if target == null or unit.level < 4 or car.stalled:
		return
	var aim := target.global_position + Vector3.UP * 0.9
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
	var muzzle := _barrel.global_transform * Vector3(0, 0, -1.6)
	var d := muzzle.distance_to(aim)
	var t := d / float(CANNON["speed"])
	aim += vel * t
	# Turn the turret (in the car's space) and lift the barrel for the drop.
	var local := car.global_transform.affine_inverse() * aim - position
	var yaw := atan2(-local.x, -local.z)
	_turret.rotation.y = lerp_angle(_turret.rotation.y, yaw, minf(1.0, 3.0 * delta))
	var flat := Vector2(local.x, local.z).length()
	var pitch := _launch_angle(flat, local.y - 0.42, float(CANNON["speed"]))
	if is_nan(pitch):
		return
	_barrel.rotation.x = lerpf(_barrel.rotation.x, pitch, minf(1.0, 3.0 * delta))
	_wait -= delta
	if _wait > 0.0 or d > RANGE or d < MIN_RANGE or not unit.sees:
		return
	if absf(angle_difference(_turret.rotation.y, yaw)) > 0.12:
		return
	_sight.from = muzzle
	_sight.to = aim
	_sight.exclude = [car.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(_sight).is_empty():
		return
	var ps := PaintShots.find(get_tree())
	if ps == null:
		return
	_wait = RELOAD
	shots += 1
	unit.dispatcher.stats["tank_shots"] = int(unit.dispatcher.stats["tank_shots"]) + 1
	ps.fire(muzzle, -_barrel.global_basis.z, self, CANNON)


## The lower of the two angles a round at `speed` takes to land `up` m
## higher at `flat` m away (NAN if it can't reach).
static func _launch_angle(flat: float, up: float, speed: float) -> float:
	var g := PaintWeapons.GRAVITY
	var v2 := speed * speed
	var disc := v2 * v2 - g * (g * flat * flat + 2.0 * up * v2)
	if disc < 0.0:
		return NAN
	return atan((v2 - sqrt(disc)) / (g * flat))


func _connect() -> void:
	if _connected:
		return
	var ps := PaintShots.find(get_tree())
	if ps == null:
		return
	_connected = true
	ps.hit.connect(_on_hit)


func _on_hit(info: Dictionary) -> void:
	if info.get("shooter") != self or str(info.get("weapon", "")) != "paint_cannon":
		return
	var ps := PaintShots.find(get_tree())
	if bool(info.get("splash", false)):
		return
	var target: Variant = info.get("target")
	if target is Car and is_instance_valid(target):
		var c := target as Car
		if Engine.get_physics_frames() - _hit_frame < 30:
			return
		_hit_frame = Engine.get_physics_frames()
		var pc := PaintCoverage.of(c)
		var need := HIT_COVERAGE - pc.police_coverage
		if need > 0.0:
			pc.add_coverage(need, c.to_local(info["point"]), PaintWeapons.POLICE_COLOUR, true)
		hits += 1
		_wait = maxf(_wait, HOLD_AFTER_HIT)
		unit.dispatcher.stats["tank_hits"] = int(unit.dispatcher.stats["tank_hits"]) + 1
		unit.dispatcher.radio_say("tank_hit", unit)
	# The big splat on the road where it came down.
	if ps != null:
		var p: Vector3 = info["point"]
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0, Layers.GROUND)
		var h := get_world_3d().direct_space_state.intersect_ray(q)
		if not h.is_empty():
			ps.splats.add(h["position"], h["normal"], PaintWeapons.POLICE_COLOUR, SPLAT_SIZE)
			for i in 3:
				var o := Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
				ps.splats.add((h["position"] as Vector3) + o, h["normal"], PaintWeapons.POLICE_COLOUR, SPLAT_SIZE * 0.6)

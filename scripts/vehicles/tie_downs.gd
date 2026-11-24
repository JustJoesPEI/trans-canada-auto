class_name TieDowns
extends Node
## Straps holding loads (pallets, crates, a car on a tow truck) to a
## vehicle's deck.
##
## Unstrapped, a load is held only by friction: brake or corner harder than
## about half a g and it slides, and it can go over the side. A strap holds
## the load where it was strapped, relative to the deck (the deck may be a
## moving part, like a tow truck's), with a stiff spring and damper. It
## pulls the deck just as hard the other way, so the load's weight and
## momentum go into the truck through the straps as well as the floor.
##
## Each strap has a breaking force: a load is held through ordinary hard
## driving, but a crash or a really violent stop can snap the straps, and
## then it's loose again.

signal strap_broke(body: RigidBody3D)

## Breaking force of one ratchet strap (N). Real 2-inch straps break at
## about 45 kN; working loads are a third of that.
const STRAP_BREAK := 30000.0
## How stiffly a strap holds (how quickly a load springs back, Hz).
const HOLD_HZ := 4.5
const HOLD_DAMPING := 0.9
## A strap only snaps when it's been over its limit this long (s), so one
## frame's spike from a bump doesn't.
const BREAK_TIME := 0.06

var car: Car
## One entry per strapped load: body, deck (the CollisionShape3D it sits on),
## rel (the load's transform in the deck's frame), straps (how many), over.
var straps: Array[Dictionary] = []


func _ready() -> void:
	car = get_parent() as Car


func is_empty() -> bool:
	return straps.is_empty()


func has(body: RigidBody3D) -> bool:
	for s in straps:
		if s["body"] == body:
			return true
	return false


## Everything sitting on this vehicle's decks that could be strapped.
func loads_on_deck() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if car.deck_shapes.is_empty():
		return out
	var space := car.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = Layers.CARGO | Layers.VEHICLES
	q.exclude = car.coupled_rids()
	var seen := {}
	for deck: CollisionShape3D in car.deck_shapes:
		var size := (deck.shape as BoxShape3D).size
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, 2.6, size.z)
		q.shape = box
		var x := deck.global_transform
		q.transform = Transform3D(x.basis, x * Vector3(0.0, size.y * 0.5 + 1.35, 0.0))
		for r: Dictionary in space.intersect_shape(q, 128):
			var b := r["collider"] as RigidBody3D
			if b == null or seen.has(b) or b.freeze:
				continue
			if b is Car and (b as Car).driver != null:
				continue
			seen[b] = true
			out.append({"body": b, "deck": deck})
	return out


## Strap down everything on the deck. Returns how many loads were strapped.
func strap_all() -> int:
	var count := 0
	for l in loads_on_deck():
		var b: RigidBody3D = l["body"]
		if has(b):
			continue
		var deck: CollisionShape3D = l["deck"]
		# Two straps for a light load, more for a heavy one.
		var n := clampi(ceili(b.mass / 1200.0) + 1, 2, 6)
		straps.append({"body": b, "deck": deck, "rel": deck.global_transform.affine_inverse() * b.global_transform,
			"straps": n, "over": 0.0})
		if b.has_method("set_strapped"):
			b.call("set_strapped", true)
		count += 1
	return count


func release_all() -> int:
	var count := straps.size()
	for s in straps:
		var b: RigidBody3D = s["body"]
		if is_instance_valid(b) and b.has_method("set_strapped"):
			b.call("set_strapped", false)
	straps.clear()
	return count


func release(body: RigidBody3D) -> void:
	for i in range(straps.size() - 1, -1, -1):
		if straps[i]["body"] == body:
			straps.remove_at(i)
	if is_instance_valid(body) and body.has_method("set_strapped"):
		body.call("set_strapped", false)


## Called by the vehicle every physics step.
func apply(delta: float) -> void:
	if straps.is_empty():
		return
	var car_state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	# Every strap pulls on the same deck, and a long deck turns easily near
	# its ends (a quarter of its mass, there), so each strap is tuned against
	# its share of that, and of the deck's inertia. Stiff enough to hold,
	# soft enough for one physics step to handle with many loads aboard.
	var count := float(straps.size())
	var car_inv: Vector3 = car_state.inverse_inertia
	var car_inertia := 1.0 / maxf(0.000001, maxf(car_inv.x, maxf(car_inv.y, car_inv.z)))
	for i in range(straps.size() - 1, -1, -1):
		var s := straps[i]
		var b: RigidBody3D = s["body"]
		if not is_instance_valid(b) or not b.is_inside_tree():
			straps.remove_at(i)
			continue
		if b.freeze:
			continue
		var target := (s["deck"] as CollisionShape3D).global_transform * (s["rel"] as Transform3D)
		# Held between the two bodies. The damping is kept to what one
		# physics step can take without ringing.
		var m := 1.0 / (1.0 / b.mass + 4.0 * count / car.mass)
		var w := TAU * HOLD_HZ
		var k := m * w * w
		var c := minf(2.0 * HOLD_DAMPING * m * w, 0.8 * m / delta)
		# Held at the load's centre of mass, so holding it doesn't twist it.
		var com := b.center_of_mass if b.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM else Vector3.ZERO
		var at := b.global_transform * com
		var v_rel := b.linear_velocity - car_state.get_velocity_at_local_position(at - car.global_position)
		var force := (target * com - at) * k - v_rel * c
		# Turning: the same, about the load's own size.
		var q := (target.basis.orthonormalized() * b.global_basis.orthonormalized().inverse()).get_rotation_quaternion()
		var ang := q.get_angle()
		if ang > PI:
			ang -= TAU
		var axis := q.get_axis() if absf(ang) > 0.0001 else Vector3.UP
		# The load's own inertia (its easiest axis to turn about), from the engine.
		var inv: Vector3 = PhysicsServer3D.body_get_direct_state(b.get_rid()).inverse_inertia
		var inertia := 1.0 / (maxf(inv.x, maxf(inv.y, inv.z)) + count / car_inertia)
		var cr := minf(2.0 * HOLD_DAMPING * inertia * w, 0.8 * inertia / delta)
		var torque := axis * ang * inertia * w * w - (b.angular_velocity - car.angular_velocity) * cr
		# Too much for the straps: they let go.
		if force.length() > STRAP_BREAK * float(s["straps"]):
			s["over"] = float(s["over"]) + delta
			if float(s["over"]) > BREAK_TIME:
				straps.remove_at(i)
				if b.has_method("set_strapped"):
					b.call("set_strapped", false)
				strap_broke.emit(b)
				continue
		else:
			s["over"] = 0.0
		b.apply_central_force(force)
		b.apply_torque(torque)
		car.apply_force(-force, at - car.global_position)
		car.apply_torque(-torque)

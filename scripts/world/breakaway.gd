class_name Breakaway
extends RefCounted
## Street furniture that gives way to a car, the way it does in the other
## series: lamp posts, street lights, the median's twin lights, hydrants,
## sign posts and crosswalk poles. A thin pole hit by a car is not a wall:
## above MIN_KMH it snaps off at the foot and falls, and the car carries on
## having lost a slice of its speed (more for a heavy cast-iron lamp than a
## sign post, less for a heavy truck). Below that it's solid, so you can
## nose up to one parking. Trees, buildings, traffic signals (their poles
## and heads are drawn merged, chunk by chunk) and wooden utility poles
## (they hold the wires) stay solid.
##
## Building a prop:
##   Breakaway.mark_shapes(body, kind)  every CollisionShape3D child of a
##       body of many poles, each drawn as an instance of the MultiMeshes in
##       its chunk labelled KINDS[kind].labels (TiledMulti's "label" meta,
##       or the node's name), standing where its shape's foot is (a shape's
##       own "breakaway" meta, if it has one, is its kind instead)
##   Breakaway.mark_whole(body, kind)   a body that is one pole and draws
##       itself (its own MeshInstance3D children)
## Driving: Car calls Breakaway.check(car, delta) each physics step while
## it's moving faster than MIN_KMH: a look one step ahead for marked poles
## (on their own layer, Layers.BREAKAWAY, as well as SOLID), which are
## knocked over before the car's body can touch them.
##
## A knocked pole is hidden (its instance scaled to nothing, or its body
## hidden), its collision is off, and a falling copy (the same mesh, so no
## new model) tips over away from the car. The copy hits the ground and
## the buildings but not cars, so a pole lying in the road never stops the
## next one, and it's gone after DEBRIS_SECONDS. The pole's back when its
## chunk is next built.

const MIN_KMH := 18.0
## Seconds a fallen pole lies there.
const DEBRIS_SECONDS := 25.0
## A car of this mass (kg) loses the kind's `loss`; heavier ones lose less,
## lighter ones more (within 0.4 to 1.3 times it).
const REF_MASS := 1400.0

## kind -> labels (the MultiMeshes it's drawn in), loss (the share of the
## car's speed it costs), mass (kg, of the falling copy).
const KINDS := {
	"lamp": {"labels": ["Lamps", "Lamps_shadow"], "loss": 0.22, "mass": 160.0},
	"street_light": {"labels": ["StreetLights", "StreetLights_shadow"], "loss": 0.2, "mass": 140.0},
	"median_light": {"labels": ["MedianLights", "MedianLights_shadow"], "loss": 0.25, "mass": 180.0},
	"hydrant": {"labels": ["HydrantMeshes", "HydrantMeshes_shadow"], "loss": 0.15, "mass": 90.0},
	"post": {"labels": [], "loss": 0.05, "mass": 25.0},
	"crosswalk": {"labels": [], "loss": 0.08, "mass": 45.0},
}

## Knocked over so far, this run (for tests and the record).
static var knocked := 0


static func mark_shapes(body: StaticBody3D, kind: String) -> void:
	body.collision_layer = Layers.SOLID | Layers.BREAKAWAY
	body.set_meta("breakaway", kind)


static func mark_whole(body: StaticBody3D, kind: String) -> void:
	body.collision_layer = Layers.SOLID | Layers.BREAKAWAY
	body.set_meta("breakaway", kind)
	body.set_meta("breakaway_whole", true)


## The look ahead, for a car moving at speed: anything marked that its box
## will be touching next step is knocked over now.
static func check(car: RigidBody3D, delta: float) -> void:
	var v := car.linear_velocity
	if v.length_squared() < (MIN_KMH / 3.6) * (MIN_KMH / 3.6):
		return
	var box: BoxShape3D = car.get_meta("breakaway_box") if car.has_meta("breakaway_box") else _box_for(car)
	if box == null:
		return
	# Kept on the car, not in a static: physics things held by statics at
	# quit outlive the physics server.
	var query: PhysicsShapeQueryParameters3D = car.get_meta("breakaway_query") if car.has_meta("breakaway_query") else null
	if query == null:
		query = PhysicsShapeQueryParameters3D.new()
		query.collision_mask = Layers.BREAKAWAY
		query.collide_with_areas = false
		car.set_meta("breakaway_query", query)
	query.shape = box
	var centre: Vector3 = car.get_meta("breakaway_centre")
	# Where the box will be a step and a half on (and the half-step margin
	# covers a pole met side-on at the corners).
	query.transform = Transform3D(car.global_basis, car.global_transform * centre + v * delta * 1.5)
	query.exclude = [car.get_rid()]
	var hits := car.get_world_3d().direct_space_state.intersect_shape(query, 4)
	for h: Dictionary in hits:
		var body := h["collider"] as StaticBody3D
		if body == null or not body.has_meta("breakaway"):
			continue
		var cs: CollisionShape3D
		if body.has_meta("breakaway_whole"):
			cs = null
		else:
			var owner_id := body.shape_find_owner(int(h["shape"]))
			cs = body.shape_owner_get_owner(owner_id) as CollisionShape3D
			if cs == null or cs.disabled:
				continue
		if cs != null and cs.has_meta("parked"):
			_wake_parked(cs)
			continue
		var at := cs.global_position if cs != null else body.global_position
		# Only a car coming at it fast enough: not one sliding past slowly.
		var to := at - car.global_position
		to.y = 0.0
		if to.length() > 0.01 and v.dot(to.normalized()) < MIN_KMH / 3.6 * 0.7:
			continue
		knock(car, body, cs)


## Parked cars along the curbs and in the lots (StreetProps) are marked
## too, as kind "parked": one about to be hit is swapped for a real car in
## the same spot, by the scene's wake_parked_car(hit) (main.gd: the same
## swap as getting into one), and the hit is then car against car, so it's
## shoved and the car that hit it loses what a real shunt costs, rather
## than stopping dead. (Looked up each time, not kept in a static: a static
## holding the scene's function outlives it at quit and corrupts memory.)
static func _wake_parked(cs: CollisionShape3D) -> void:
	var at: Array = cs.get_meta("parked")
	var mmi := at[0] as MultiMeshInstance3D
	var i: int = at[1]
	var scene := mmi.get_tree().current_scene if mmi != null and is_instance_valid(mmi) and mmi.is_inside_tree() else null
	if scene == null or not scene.has_method("wake_parked_car"):
		return
	var list: Array = mmi.get_meta("xforms")
	if i >= list.size() or list[i] == null:
		return
	cs.remove_meta("parked")
	knocked += 1
	scene.call("wake_parked_car", {"mmi": mmi, "index": i})
	# Off now, not at the end of the step: the real car stands there.
	cs.disabled = true


## Knocks the pole (cs in body, or the whole body when cs is null) over,
## away from the car, and takes its slice of the car's speed.
static func knock(car: RigidBody3D, body: StaticBody3D, cs: CollisionShape3D) -> void:
	var kind := str(cs.get_meta("breakaway", body.get_meta("breakaway")) if cs != null else body.get_meta("breakaway"))
	var spec: Dictionary = KINDS.get(kind, KINDS["post"])
	var root := body.get_parent() as Node3D
	var v := car.linear_velocity
	var foot: Vector3
	var debris := RigidBody3D.new()
	debris.collision_layer = 0 # nothing hits it...
	debris.collision_mask = Layers.GROUND | Layers.SOLID # ...it lands on the street
	debris.mass = float(spec["mass"])
	debris.can_sleep = true
	var height := 1.0
	if cs == null:
		# One pole, drawing itself: hide it, and the falling copy is its
		# meshes.
		foot = body.global_position
		for c in body.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = true
				var s := (c as CollisionShape3D).shape
				if s is CylinderShape3D:
					height = maxf(height, (s as CylinderShape3D).height)
			elif c is MeshInstance3D:
				var mi := (c as MeshInstance3D).duplicate() as MeshInstance3D
				debris.add_child(mi)
		for c in body.get_children():
			if c is Node3D and not (c is CollisionShape3D):
				(c as Node3D).visible = false
		body.collision_layer = 0
		debris.global_transform = body.global_transform
	else:
		cs.disabled = true
		var s := cs.shape
		height = (s as CylinderShape3D).height if s is CylinderShape3D else 2.0
		var foot_local := cs.position - Vector3(0.0, height * 0.5, 0.0)
		foot = root.global_transform * foot_local if root != null else cs.global_position
		var shown := _hide_instances(root, spec["labels"], foot_local)
		if shown.is_empty():
			debris.free()
			debris = null
		else:
			for mesh_xf: Array in shown:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh_xf[0]
				mi.transform = Transform3D((mesh_xf[1] as Transform3D).basis, Vector3.ZERO)
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				debris.add_child(mi)
			debris.global_transform = Transform3D(Basis.IDENTITY, foot)
	knocked += 1
	# The car pays for it, and is nudged a little off the line it hit at.
	var scale := clampf(REF_MASS / maxf(car.mass, 100.0), 0.4, 1.3)
	var keep := 1.0 - float(spec["loss"]) * scale
	var flat := Vector3(v.x, 0.0, v.z)
	car.linear_velocity = Vector3(v.x * keep, v.y, v.z * keep)
	var side := (foot - car.global_position).dot(car.global_basis.x)
	car.angular_velocity.y += clampf(-side, -1.0, 1.0) * 0.5 * float(spec["loss"]) * scale
	if car.has_signal("crashed"):
		car.emit_signal("crashed", flat.length() * (1.0 - keep) * 0.6)
	if debris == null or root == null:
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, height, 0.3)
	var dcs := CollisionShape3D.new()
	dcs.shape = shape
	dcs.position.y = height * 0.5
	debris.add_child(dcs)
	debris.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	debris.center_of_mass = Vector3(0.0, height * 0.45, 0.0)
	root.add_child(debris)
	debris.global_position = foot + Vector3.UP * 0.05
	# Off its foot the way the car was going, tipping over that way.
	var dir := flat.normalized() if flat.length() > 0.1 else -car.global_basis.z
	debris.linear_velocity = dir * flat.length() * 0.45 + Vector3.UP * 1.2
	debris.angular_velocity = Vector3.UP.cross(dir) * clampf(flat.length() / height, 1.0, 4.0)
	debris.get_tree().create_timer(DEBRIS_SECONDS).timeout.connect(debris.queue_free)


## Hides the instances of the MultiMeshes labelled `labels` in `root` that
## stand at `foot` (root's space). Returns [mesh, instance transform] for
## each, for the falling copy.
static func _hide_instances(root: Node3D, labels: Array, foot: Vector3) -> Array:
	var out: Array = []
	if root == null:
		return out
	for c in root.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var label := str(mmi.get_meta("label", mmi.name))
		if not labels.has(label):
			continue
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			if Vector2(xf.origin.x - foot.x, xf.origin.z - foot.z).length_squared() > 0.5 * 0.5:
				continue
			if xf.basis.determinant() == 0.0:
				continue # already down
			if not label.ends_with("_shadow"):
				out.append([mm.mesh, xf])
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), xf.origin))
	return out


## The box the look ahead sweeps: the car's own collision box(es), all in
## one (kept on the car as metas).
static func _box_for(car: RigidBody3D) -> BoxShape3D:
	var aabb := AABB()
	var first := true
	for c in car.get_children():
		var cs := c as CollisionShape3D
		if cs == null:
			continue
		var local := AABB()
		if cs.shape is BoxShape3D:
			var sz := (cs.shape as BoxShape3D).size
			local = AABB(-sz * 0.5, sz)
		elif cs.shape is ConvexPolygonShape3D:
			var pts := (cs.shape as ConvexPolygonShape3D).points
			if pts.is_empty():
				continue
			local = AABB(pts[0], Vector3.ZERO)
			for q in pts:
				local = local.expand(q)
		else:
			continue
		var b := cs.transform * local
		aabb = b if first else aabb.merge(b)
		first = false
	if first:
		return null
	var box := BoxShape3D.new()
	box.size = aabb.size + Vector3(0.1, 0.0, 0.1)
	car.set_meta("breakaway_box", box)
	car.set_meta("breakaway_centre", aabb.get_center())
	return box

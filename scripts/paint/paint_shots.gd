class_name PaintShots
extends Node3D
## Every paintball, jar and paint bomb in flight, and what happens where
## they land (docs/design.md sections 2 and 3). One of these, a child of
## Main, in the group "paint_shots"; anyone who shoots calls `fire`.
##
## Balls aren't nodes or rigid bodies: each is a few numbers, moved each
## physics step under gravity with a ray from where it was to where it is
## now, and all of them are drawn by one MultiMesh (a short bright streak
## along the flight). A hit on:
##   * a person (anything with `take_paint_hit`): hits on them, a head hit
##     counting double, and a splat on their body;
##   * a car: a hit on its PaintCoverage, in the car's own space;
##   * anything else that stands still: a splat on the wall or ground
##     (PaintSplats). A splat on something that moves (a pallet) would
##     float off it, so those only get painted when they're cars or people.
## Splash weapons (Jam Jars, Tourist Season) burst: hits on everyone within
## the radius, coverage on every car in it, and splats round about.
##
## `hit` reports every hit, for the shooter's feedback (HUD tick, thwack)
## and the Wanted piece (a crime to report).

## info: target (the Node hit, or null for the world), point, normal,
## shooter, value (hits on a person; 0 otherwise), colour, kind ("car",
## "person", "world"), weapon (its id), police (it was police paint),
## splash (it came from a burst), out (it put the person out).
signal hit(info: Dictionary)

## Most balls in flight at once (the oldest drops when there are more).
const MAX_BALLS := 384
## What a ball can hit.
const MASK := Layers.GROUND | Layers.SOLID | Layers.VEHICLES | Layers.CHARACTERS | Layers.CARGO
## m: how big a ball is drawn (a real one is 17 mm across; drawn bigger so
## it shows), and its streak per m/s of speed.
const BALL_RADIUS := 0.022
const STREAK_PER_SPEED := 0.006
const MAX_STREAK := 0.5
## m: a jar and a paint bomb in flight.
const LOB_RADIUS := 0.07
## World splats thrown round a burst (Jam Jar, paint bomb).
const BURST_SPLATS := 10

var splats: PaintSplats

var _balls: Array[Dictionary] = []
var _draw: MultiMeshInstance3D
var _ray := PhysicsRayQueryParameters3D.new()
var _rng := RandomNumberGenerator.new()

static var _ball_mesh: ArrayMesh
static var _ball_material: ShaderMaterial


func _ready() -> void:
	add_to_group("paint_shots")
	_rng.randomize()
	_ray.collision_mask = MASK
	splats = PaintSplats.new()
	add_child(splats)
	_draw = MultiMeshInstance3D.new()
	_draw.name = "Balls"
	_draw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw.custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _ball_streak_mesh()
	mm.instance_count = MAX_BALLS
	mm.visible_instance_count = 0
	_draw.multimesh = mm
	_draw.material_override = _ball_shader_material()
	add_child(_draw)


## The PaintShots in the scene (or null).
static func find(tree: SceneTree) -> PaintShots:
	return tree.get_first_node_in_group("paint_shots") as PaintShots if tree != null else null


## Fire one shot from `origin` toward `dir`, by `shooter`, with `weapon`
## (a PaintWeapons dictionary). `spread_mul` widens the weapon's spread
## (running, from the hip, leaning out of a car: PaintMarker works it out).
func fire(origin: Vector3, dir: Vector3, shooter: Node, weapon: Dictionary, spread_mul := 1.0) -> void:
	dir = dir.normalized()
	if dir.length_squared() < 0.5:
		return
	var spread := deg_to_rad(float(weapon.get("spread", 0.0)) * spread_mul)
	if spread > 0.0:
		# Uniform over the cone's disc.
		var side := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var off := sqrt(_rng.randf()) * spread
		dir = dir.rotated(side, off).rotated(dir, _rng.randf() * TAU).normalized()
	var exclude: Array[RID] = []
	for n: CollisionObject3D in own_bodies(shooter):
		exclude.append(n.get_rid())
	var police := _is_police(shooter, weapon)
	_balls.append({
		"pos": origin, "prev": origin, "vel": dir * float(weapon.get("speed", 75.0)),
		"weapon": weapon, "shooter": shooter, "exclude": exclude, "age": 0.0,
		"colour": colour_of(shooter, weapon), "police": police, "resting": false,
	})
	while _balls.size() > MAX_BALLS:
		_balls.pop_front()


## What a shooter's own shots go through: the shooter, and the car they're
## in (their `vehicle`, or the Car they sit in: a passenger leaning out).
static func own_bodies(shooter: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if shooter == null or not is_instance_valid(shooter):
		return out
	if shooter is CollisionObject3D:
		out.append(shooter as CollisionObject3D)
	var car: Variant = shooter.get("vehicle")
	var n: Node = shooter.get_parent()
	while car == null and n != null:
		if n is Car:
			car = n
		n = n.get_parent()
	if car is CollisionObject3D and not out.has(car):
		out.append(car as CollisionObject3D)
	return out


## How many shots are in flight.
func in_flight() -> int:
	return _balls.size()


## The paint a shooter's shots are: the weapon's own, the police's orange,
## the shooter's chosen colour (`paint_colour`), or one of the twelve picked
## from who they are.
static func colour_of(shooter: Node, weapon := {}) -> Color:
	if weapon.get("colour") is Color:
		return weapon["colour"]
	if shooter != null and is_instance_valid(shooter):
		if shooter.is_in_group("police"):
			return PaintWeapons.POLICE_COLOUR
		var c: Variant = shooter.get("paint_colour")
		if c is Color:
			return c
		return PaintWeapons.COLOURS[absi(hash(shooter.name)) % PaintWeapons.COLOURS.size()]
	return PaintWeapons.COLOURS[0]


func _is_police(shooter: Node, weapon: Dictionary) -> bool:
	return bool(weapon.get("police", false)) or (shooter != null and is_instance_valid(shooter) and shooter.is_in_group("police"))


func _physics_process(delta: float) -> void:
	if _balls.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := 0
	while i < _balls.size():
		var b := _balls[i]
		var w: Dictionary = b["weapon"]
		b["age"] = float(b["age"]) + delta
		var done := false
		if not bool(b["resting"]):
			var p: Vector3 = b["pos"]
			var v: Vector3 = b["vel"]
			v.y -= PaintWeapons.GRAVITY * float(w.get("gravity_scale", 1.0)) * delta
			var next := p + v * delta
			b["prev"] = p
			b["vel"] = v
			_ray.from = p
			_ray.to = next
			_ray.exclude = b["exclude"]
			var h := space.intersect_ray(_ray)
			if h.is_empty():
				b["pos"] = next
			else:
				b["pos"] = h["position"]
				done = _land(b, h)
		else:
			b["prev"] = b["pos"]
		var fuse := float(w.get("fuse", 0.0))
		if not done and fuse > 0.0 and float(b["age"]) >= fuse:
			_burst(b, b["pos"], null)
			done = true
		if not done and float(b["age"]) >= float(w.get("life", 2.0)):
			if str(w.get("kind", "ball")) != "ball":
				_burst(b, b["pos"], null)
			done = true
		if done:
			_balls.remove_at(i)
		else:
			i += 1


func _process(_delta: float) -> void:
	var mm := _draw.multimesh
	var n := _balls.size()
	mm.visible_instance_count = n
	if n == 0:
		return
	var f := Engine.get_physics_interpolation_fraction()
	for i in n:
		var b := _balls[i]
		var at: Vector3 = (b["prev"] as Vector3).lerp(b["pos"], f)
		var v: Vector3 = b["vel"]
		var speed := v.length()
		var lob := str((b["weapon"] as Dictionary).get("kind", "ball")) != "ball"
		var r := LOB_RADIUS if lob else BALL_RADIUS
		var back := (-v / speed) if speed > 0.1 else Vector3.BACK
		var side := back.cross(Vector3.UP if absf(back.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := back.cross(side)
		var streak := r * 2.0 if lob or bool(b["resting"]) else clampf(speed * STREAK_PER_SPEED, r * 2.0, MAX_STREAK)
		mm.set_instance_transform(i, Transform3D(Basis(side * r, up * r, back * streak), at))
		mm.set_instance_color(i, b["colour"])


## A shot met something. Returns true when it's done (it burst or splatted).
func _land(b: Dictionary, h: Dictionary) -> bool:
	var w: Dictionary = b["weapon"]
	var kind := str(w.get("kind", "ball"))
	var point: Vector3 = h["position"]
	var normal: Vector3 = h["normal"]
	var target := _target_of(h["collider"])
	if kind == "grenade":
		# A jar stops where it lands and bursts when its fuse runs out.
		b["resting"] = true
		b["pos"] = point + normal * LOB_RADIUS
		b["vel"] = Vector3.ZERO
		return false
	var info := _direct(b, target, h["collider"], point, normal)
	if kind == "bomb":
		_burst(b, point, info.get("target"))
	return true


## A direct hit on a person, a car or the world.
func _direct(b: Dictionary, target: Node, collider: Object, point: Vector3, normal: Vector3) -> Dictionary:
	var w: Dictionary = b["weapon"]
	var shooter: Node = b["shooter"] if is_instance_valid(b["shooter"]) else null
	var colour: Color = b["colour"]
	var info := {"target": target, "point": point, "normal": normal, "shooter": shooter, "value": 0,
		"colour": colour, "kind": "world", "weapon": str(w.get("id", "")), "police": bool(b["police"]),
		"splash": false, "out": false}
	if target != null and target.has_method("take_paint_hit"):
		var value := int(w.get("hit_value", 1))
		if value > 0 and target.has_method("is_head_point") and bool(target.call("is_head_point", point)):
			value *= 2
		info["kind"] = "person"
		info["value"] = value
		_hit_person(target, value, shooter, point, info)
	elif target is Car:
		var car := target as Car
		var police := bool(b["police"]) or car.police != null
		info["kind"] = "car"
		info["police"] = police
		var share := float(w.get("car_coverage", 0.0))
		var size := PaintCoverage.size_for_fill(share) if share > 0.0 else PaintCoverage.BALL_SIZE * float(w.get("splat_size", 0.16)) / 0.16
		var inv := car.global_basis.inverse()
		PaintCoverage.of(car).add_hit(car.to_local(point), colour, size, police, inv * normal, inv * -(b["vel"] as Vector3))
	else:
		info["target"] = null
		if collider is StaticBody3D or collider is CSGShape3D:
			splats.add(point, normal, colour, float(w.get("splat_size", 0.16)), -1, b["exclude"])
	hit.emit(info)
	return info


func _hit_person(target: Node, value: int, shooter: Node, point: Vector3, info: Dictionary) -> void:
	var was_out := target.has_method("is_out") and bool(target.call("is_out"))
	target.call("take_paint_hit", value, shooter, point)
	info["out"] = not was_out and target.has_method("is_out") and bool(target.call("is_out"))


## A burst (a Jam Jar's fuse, a paint bomb landing): hits on everyone in
## the splash, coverage on cars in it, splats round about.
func _burst(b: Dictionary, at: Vector3, direct: Variant) -> void:
	var w: Dictionary = b["weapon"]
	var radius := float(w.get("splash_radius", 0.0))
	if radius <= 0.0:
		return
	var shooter: Node = b["shooter"] if is_instance_valid(b["shooter"]) else null
	var colour: Color = b["colour"]
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = Layers.CHARACTERS | Layers.VEHICLES
	var seen := {}
	for r: Dictionary in space.intersect_shape(q, 64):
		var target := _target_of(r["collider"])
		if target == null or target == direct or seen.has(target):
			continue
		seen[target] = true
		var body := target as Node3D
		# Where the splash meets it: a ray from the burst to its middle.
		var centre := body.global_position + Vector3.UP * 0.9
		_ray.from = at
		_ray.to = centre + (centre - at).normalized() * 2.0
		_ray.exclude = []
		var h := space.intersect_ray(_ray)
		var point := centre
		var normal := (at - centre).normalized()
		if not h.is_empty() and _target_of(h["collider"]) == target:
			point = h["position"]
			normal = h["normal"]
		var info := {"target": target, "point": point, "normal": normal, "shooter": shooter, "value": 0,
			"colour": colour, "kind": "world", "weapon": str(w.get("id", "")), "police": bool(b["police"]),
			"splash": true, "out": false}
		if target.has_method("take_paint_hit"):
			info["kind"] = "person"
			info["value"] = int(w.get("splash_hits", 0))
			_hit_person(target, int(w.get("splash_hits", 0)), shooter, point, info)
		elif target is Car:
			var car := target as Car
			info["kind"] = "car"
			info["police"] = bool(b["police"]) or car.police != null
			var inv := car.global_basis.inverse()
			PaintCoverage.of(car).add_coverage(float(w.get("splash_car_coverage", 0.0)), car.to_local(point), colour, info["police"], inv * normal, inv * (at - point))
		else:
			continue
		hit.emit(info)
	# Paint thrown round: rays out and down from the burst.
	_ray.collision_mask = Layers.GROUND | Layers.SOLID
	_ray.exclude = []
	for i in BURST_SPLATS:
		var d := Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 0.2), _rng.randf_range(-1.0, 1.0)).normalized()
		_ray.from = at
		_ray.to = at + d * radius
		var h := space.intersect_ray(_ray)
		if not h.is_empty() and h["collider"] is StaticBody3D:
			splats.add(h["position"], h["normal"], colour, float(w.get("splat_size", 0.3)) * _rng.randf_range(0.4, 1.0))
	_ray.collision_mask = MASK


## The person or car a collider belongs to, or null for the world.
func _target_of(collider: Object) -> Node:
	var n := collider as Node
	while n != null and n != self:
		if n.has_method("take_paint_hit") or n is Car:
			return n
		n = n.get_parent()
	return null


## A short streak: a nose, a ring of four, a tail (8 triangles). Its own
## space: 1 across (scaled to the ball), the ball at z = 0 and the tail at
## z = 1 (scaled to the streak), so the transform's z axis points back
## along the flight.
static func _ball_streak_mesh() -> ArrayMesh:
	if _ball_mesh != null:
		return _ball_mesh
	var v := PackedVector3Array([Vector3(0, 0, -0.06), Vector3(1, 0, 0.04), Vector3(0, 1, 0.04), Vector3(-1, 0, 0.04), Vector3(0, -1, 0.04), Vector3(0, 0, 1)])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(0, 0.1), Vector2(0, 0.1), Vector2(0, 0.1), Vector2(0, 0.1), Vector2(0, 1)])
	var idx := PackedInt32Array()
	for k in 4:
		var a := 1 + k
		var c := 1 + (k + 1) % 4
		idx.append_array([0, a, c, a, 5, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	_ball_mesh = ArrayMesh.new()
	_ball_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _ball_mesh


static func _ball_shader_material() -> ShaderMaterial:
	if _ball_material == null:
		_ball_material = ShaderMaterial.new()
		_ball_material.shader = load("res://shaders/paint_ball.gdshader")
	return _ball_material

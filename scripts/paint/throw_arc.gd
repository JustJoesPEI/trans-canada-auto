class_name ThrowArc
extends MeshInstance3D
## Where a lobbed shot will go, drawn while you get ready to let it go: the
## arc a Jam Jar will fly while Fire is held (PaintMarker.holding_throw),
## and a paint bomb's while aiming the Tourist Season, with a ring on the
## ground the size of its splash where it lands. The arc is worked out the
## way PaintShots flies it (the weapon's speed and gravity, stepped and
## ray-cast against the world), so it ends where the shot will.
##
## One for the player (main.gd); `marker` is whose. Rebuilt each frame
## only while it shows: a strip of a few dozen dashes and one ring, one
## draw call, no shadow, nothing otherwise.

## s between points along the arc: PaintShots' own step (60 Hz physics).
const STEP := 1.0 / 60.0
## m: how wide the dashes are drawn.
const WIDTH := 0.07
const COLOUR := Color(1.0, 1.0, 1.0, 0.85)

static var _material: StandardMaterial3D

var marker: PaintMarker
## Where it lands, while it shows (for checks).
var landing := Vector3.ZERO
var showing := false

var _im := ImmediateMesh.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _shared_material()
	_ray.collision_mask = PaintShots.MASK
	top_level = true
	# Drawn wherever it is (it's rebuilt round the shot each frame).
	custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 4000, 40000))


var _points := PackedVector3Array()
var _from := Vector3.INF
var _at := Vector3.INF
var _w := {}
var _since := 0


func _process(_delta: float) -> void:
	_im.clear_surfaces()
	showing = false
	if marker == null or not is_instance_valid(marker) or not marker.last_ready:
		return
	var w := marker.weapon
	var kind := str(w.get("kind", "ball"))
	if not (kind == "grenade" and marker.holding_throw) and not (kind == "bomb" and marker.ammo > 0):
		return
	# The path is a ray a step over the whole flight (up to a few hundred):
	# worked out again only when the aim has moved, or every few frames
	# (something may have driven into it), and the same line drawn between.
	_since += 1
	if _since >= 3 or _points.is_empty() or marker.last_muzzle.distance_squared_to(_from) > 0.0025 \
			or marker.last_target.distance_squared_to(_at) > 0.0025 or w != _w:
		_since = 0
		_from = marker.last_muzzle
		_at = marker.last_target
		_w = w
		_points = path(_from, _at, w)
	var points := _points
	if points.size() < 2:
		return
	showing = true
	landing = points[-1]
	_draw(points, float(w.get("splash_radius", 0.0)))


## The points a shot of `w` from `from` aimed at `at` passes through, to
## where it first hits something (or its life runs out).
func path(from: Vector3, at: Vector3, w: Dictionary) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	if not is_inside_tree():
		return pts
	var space := get_world_3d().direct_space_state
	var shooter: Node = marker.shooter if marker != null else null
	var exclude: Array[RID] = []
	for n: CollisionObject3D in PaintShots.own_bodies(shooter):
		exclude.append(n.get_rid())
	_ray.exclude = exclude # (the property hands out a copy: set it whole)
	var v := (at - from).normalized() * float(w.get("speed", 20.0))
	var g := PaintWeapons.GRAVITY * float(w.get("gravity_scale", 1.0))
	var p := from
	var t := 0.0
	var life := float(w.get("life", 2.0))
	while t < life:
		# The same step PaintShots takes, so it lands where the shot will.
		v.y -= g * STEP
		var next := p + v * STEP
		_ray.from = p
		_ray.to = next
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			pts.append(hit["position"])
			return pts
		pts.append(next)
		p = next
		t += STEP
	return pts


func _draw(points: PackedVector3Array, ring: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam != null else points[0] + Vector3.UP * 5.0
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Dashes: every other step, a flat strip turned to the camera.
	for i in range(0, points.size() - 1, 2):
		var a := points[i]
		var b := points[i + 1]
		var side := (b - a).cross(eye - a).normalized() * WIDTH * 0.5
		_quad(a - side, a + side, b + side, b - side)
	if ring > 0.0:
		# The splash: a ring on the ground round where it lands.
		var c := points[-1] + Vector3.UP * 0.05
		for s in 40:
			var a0 := TAU * s / 40.0
			var a1 := TAU * (s + 1) / 40.0
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			_quad(c + d0 * (ring - WIDTH), c + d0 * ring, c + d1 * ring, c + d1 * (ring - WIDTH))
	_im.surface_end()


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v: Vector3 in [a, b, c, a, c, d]:
		_im.surface_set_color(COLOUR)
		_im.surface_add_vertex(v)


static func _shared_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.vertex_color_use_as_albedo = true
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material.no_depth_test = false
	return _material

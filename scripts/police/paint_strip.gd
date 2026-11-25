class_name PaintStrip
extends Node3D
## The spoof of a spike strip (docs/design.md section 7, level 3): a strip
## of slick Evidence Paint thrown across the road. A car whose wheels cross
## it loses most of its grip (Car.grip_factor) for SLICK_TIME seconds after
## it last touched it. You can see it, and drive round it. It dries after
## LIFE seconds. Police cars slide on it too: it's paint.
##
## Its origin is on the road; the strip runs across X (the road), Z along it.

## Share of grip a slicked car keeps, and for how long (s) after the strip.
const SLICK_GRIP := 0.22
const SLICK_TIME := 2.0
const LIFE := 35.0

## Cars on it or still slick: Car -> seconds left.
var slick := {}
var _age := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("paint_strips")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = PoliceProps.strip_mesh()
	_mesh.position = Vector3.UP * 0.035
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	WorldLod.limit(_mesh, PoliceProps.STRIP_LENGTH)
	add_child(_mesh)


## Lay one at `at` (on the ground), across a road running along `road_dir`.
static func lay(parent: Node, at: Vector3, road_dir: Vector2) -> PaintStrip:
	var s := PaintStrip.new()
	parent.add_child(s)
	s.global_transform = Transform3D(Basis(Vector3.UP, atan2(-road_dir.x, -road_dir.y)), at)
	return s


func _physics_process(delta: float) -> void:
	_age += delta
	var inv := global_transform.affine_inverse()
	var hx := PoliceProps.STRIP_LENGTH * 0.5
	var hz := PoliceProps.STRIP_WIDTH * 0.5
	if _age < LIFE:
		for n in get_tree().get_nodes_in_group("vehicles"):
			var c := n as Car
			if c == null:
				continue
			var local := inv * c.global_position
			if absf(local.y) > 2.0:
				continue
			# Its wheels over the strip: within half its length either way.
			var reach := float(c.shape.get("length", 4.5)) * 0.5
			if absf(local.x) < hx + 0.5 and absf(local.z) < hz + reach:
				if not slick.has(c) and c.driver != null:
					var d := PoliceDispatcher.find(get_tree())
					if d != null:
						d.stats["slicks"] = int(d.stats["slicks"]) + 1
				slick[c] = SLICK_TIME
	for c: Variant in slick.keys():
		if not is_instance_valid(c):
			slick.erase(c)
			continue
		var t := float(slick[c]) - delta
		if t <= 0.0:
			(c as Car).grip_factor = 1.0
			slick.erase(c)
		else:
			slick[c] = t
			(c as Car).grip_factor = SLICK_GRIP
	if _age >= LIFE:
		_mesh.transparency = clampf((_age - LIFE) / 3.0, 0.0, 1.0)
		if _age > LIFE + 3.0 and slick.is_empty():
			queue_free()


func _exit_tree() -> void:
	for c: Variant in slick.keys():
		if is_instance_valid(c):
			(c as Car).grip_factor = 1.0
	slick.clear()

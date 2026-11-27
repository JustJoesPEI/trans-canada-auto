class_name Responder
extends Node3D
## A paramedic or a firefighter on foot (EmergencyUnit): out of the truck,
## across to someone or something, back again. A person (HumanoidModel,
## one shared mesh per look), walking straight lines over the ground (the
## few metres between a parked truck and a sidewalk need no more), saying
## things over their head, and, for a rinse or the hose, spraying water.
##
## Roles: "medic" (the Island Boo-Boo Bus), "captain", "kevin" and
## "firefighter" (the Island Wee-Woo Brigade). Kevin holds the hose: a
## line from the truck's pump panel to his hands.
##
## No collision of their own: they're a minute's visit, paint passes
## through them, and nothing needs to bump into them.

const WALK := 1.5
const RUN := 3.4
## How many looks per role (each a shared, cached mesh).
const LOOKS := 3
## Lines show this far from the camera at most (m).
const SAY_RANGE := 45.0

var role := "medic"
var model: HumanoidModel
## Where they're walking to (INF: standing), and whether at a run.
var goal := Vector3.INF
var running := false
## What they turn to face while standing (INF: the way they were going).
var face := Vector3.INF
## 0..1: an arm up (a wave, pointing, working on someone).
var gesture := 0.0

var _label: Label3D
var _label_t := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _ray_t := 0.0
var _ground := NAN
var _heading := Vector2(0.0, -1.0)
var _speed := 0.0
var _spray: CPUParticles3D = null
var _spray_t := 0.0
var _spray_at := Vector3.ZERO
var _hose: MeshInstance3D = null
var _hose_from: Node3D = null
var _hose_offset := Vector3.ZERO

static var _water_mat: StandardMaterial3D
static var _hose_mat: StandardMaterial3D
static var _hose_mesh: CylinderMesh
static var _drop_mesh: QuadMesh


func setup(r: String, look: int) -> void:
	role = r
	name = "Responder_%s" % r
	model = make_model(r, look)
	add_child(model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 34
	_label.pixel_size = 0.006
	_label.outline_size = 8
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.width = 620.0
	_label.position = Vector3(0.0, model.height + 0.42, 0.0)
	_label.modulate = _colour_of(r)
	_label.visible = false
	_label.visibility_range_end = SAY_RANGE
	add_child(_label)
	_ray.collision_mask = Layers.GROUND


## A body in the role's uniform: look `i` of LOOKS (cached by key).
static func make_model(r: String, i: int) -> HumanoidModel:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("responder_%s_%d" % [r, i])
	var look := HumanoidModel.random_appearance(rng)
	look["outfit"] = uniform(r)
	var m := HumanoidModel.new()
	m.set_appearance(look)
	m.mesh_cache_key = "responder_%s_%d" % [r, i]
	m.draw_distance = 160.0
	return m


## What each role wears (Outfit.UNIFORM_KINDS). A paramedic of the Island
## Boo-Boo Bus: a dark green uniform with a lime and silver band across the
## chest and round the upper arms, the Boo-Boo Bus's patch on both
## shoulders, PARAMEDIC across the back, a belt with the radio, gloves and
## shears, navy cargo trousers with bands round the shins, boots. The Island
## Wee-Woo Brigade: tan turnout coat and bunker pants with lime and silver
## bands, the Brigade's patch on both shoulders and IWWB across the back,
## and the traditional helmet: yellow with a black shield for the crew,
## white with a red one for the captain.
static func uniform(r: String) -> Dictionary:
	if r == "medic":
		return {
			"hat": {"kind": "none", "color": Color(0.1, 0.1, 0.1)},
			"top": {"kind": "medic", "color": Color(0.06, 0.22, 0.13), "trim": Color(0.8, 0.88, 0.08),
				"back": "paramedic_back", "patch": "ibbb_patch"},
			"bottom": {"kind": "trousers", "color": Color(0.07, 0.09, 0.15), "bands": Color(0.8, 0.88, 0.08)},
			"shoes": {"kind": "boots", "color": Color(0.04, 0.04, 0.045)},
		}
	var captain := r == "captain"
	return {
		"hat": {"kind": "fire_helmet", "color": Color(0.95, 0.95, 0.93) if captain else Color(0.92, 0.74, 0.06),
			"trim": Color(0.62, 0.06, 0.05) if captain else Color(0.07, 0.07, 0.08)},
		"top": {"kind": "turnout", "color": Color(0.56, 0.47, 0.3), "trim": Color(0.82, 0.9, 0.12),
			"back": "iwwb_back", "patch": "iwwb_patch"},
		"bottom": {"kind": "turnout", "color": Color(0.53, 0.44, 0.28), "bands": Color(0.82, 0.9, 0.12)},
		"shoes": {"kind": "boots", "color": Color(0.05, 0.05, 0.055)},
	}


## Builds every look's body once (behind the loading screen), so the first
## crew out of a truck doesn't stop the game while theirs are built.
static func warm_looks(parent: Node) -> void:
	for r: String in ["medic", "captain", "kevin", "firefighter"]:
		for i in LOOKS:
			await parent.get_tree().process_frame
			if not parent.is_inside_tree():
				return
			var m := make_model(r, i)
			m.visible = false
			parent.add_child(m)
			m.queue_free()


static func _colour_of(r: String) -> Color:
	if r == "medic":
		return Color(0.82, 1.0, 0.75)
	return Color(1.0, 0.82, 0.6)


func move_to(p: Vector3, run := false) -> void:
	goal = p
	running = run


func at_goal() -> bool:
	if goal == Vector3.INF:
		return true
	var d := Vector2(goal.x - global_position.x, goal.z - global_position.z)
	return d.length() < 0.35


## Says `text` over their head for `secs`, if anyone's near enough to read it.
func say(text: String, secs := 3.6) -> void:
	if text == "":
		return
	_label.text = text
	_label.visible = true
	_label_t = secs


## Water from their hands at `at` for `secs`: a rinse (small) or the hose
## (big).
func spray_at(at: Vector3, secs: float, big := false) -> void:
	if _spray == null:
		_spray = CPUParticles3D.new()
		_spray.name = "Spray"
		_spray.local_coords = false
		_spray.mesh = _drop()
		_spray.material_override = _water()
		_spray.lifetime = 0.7
		_spray.direction = Vector3(0.0, 0.0, -1.0)
		_spray.gravity = Vector3(0.0, -9.8, 0.0)
		_spray.scale_amount_min = 0.5
		_spray.scale_amount_max = 1.2
		_spray.position = Vector3(0.0, 1.15 * model.height / 1.75, -0.35)
		WorldLod.limit(_spray, 1.0, 120.0)
		add_child(_spray)
	_spray.amount = 90 if big else 40
	_spray.spread = 5.0 if big else 9.0
	var dist := Vector2(at.x - global_position.x, at.z - global_position.z).length()
	# Fast enough to carry the distance, dropping a little on the way.
	var v := clampf(dist * 1.6 + 3.0, 4.0, 16.0) if big else clampf(dist * 2.0 + 2.0, 3.0, 7.0)
	_spray.initial_velocity_min = v * 0.9
	_spray.initial_velocity_max = v * 1.1
	_spray_at = at
	_spray_t = secs
	_spray.emitting = true
	face = at


func spraying() -> bool:
	return _spray_t > 0.0


## Holding the hose: a line from `from` (the truck, `offset` in its space)
## to their hands, until drop_hose().
func hold_hose(from: Node3D, offset: Vector3) -> void:
	_hose_from = from
	_hose_offset = offset
	if _hose == null:
		_hose = MeshInstance3D.new()
		_hose.name = "Hose"
		_hose.mesh = _hose_line()
		_hose.material_override = _hose_material()
		_hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hose.top_level = true
		WorldLod.limit(_hose, 1.0, 120.0)
		add_child(_hose)
	_hose.visible = true


func drop_hose() -> void:
	_hose_from = null
	if _hose != null:
		_hose.visible = false


func _physics_process(delta: float) -> void:
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0:
			_label.visible = false
	var p := Vector2(global_position.x, global_position.z)
	var want := Vector2.ZERO
	if goal != Vector3.INF:
		var to := Vector2(goal.x, goal.z) - p
		var d := to.length()
		if d > 0.3:
			var sp := RUN if running else WALK
			want = to / d * minf(sp, d * 3.0)
		else:
			goal = Vector3.INF
	_speed = move_toward(_speed, want.length(), 8.0 * delta)
	if want.length() > 0.01:
		p += want.normalized() * _speed * delta
		_heading = _heading.slerp(want.normalized(), clampf(delta * 8.0, 0.0, 1.0)).normalized()
	elif face != Vector3.INF:
		var f := Vector2(face.x, face.z) - p
		if f.length() > 0.1:
			_heading = _heading.slerp(f.normalized(), clampf(delta * 6.0, 0.0, 1.0)).normalized()
	# The ground, looked for a few times a second.
	_ray_t -= delta
	if _ray_t <= 0.0 or is_nan(_ground):
		_ray_t = 0.2
		_ray.from = Vector3(p.x, global_position.y + 1.5, p.y)
		_ray.to = Vector3(p.x, global_position.y - 4.0, p.y)
		var hit := get_world_3d().direct_space_state.intersect_ray(_ray)
		if not hit.is_empty():
			_ground = (hit["position"] as Vector3).y
	var y := global_position.y if is_nan(_ground) else move_toward(global_position.y, _ground, 4.0 * delta)
	global_transform = Transform3D(Basis(Vector3.UP, atan2(-_heading.x, -_heading.y)), Vector3(p.x, y, p.y))
	model.set_motion(_speed)
	var hands := gesture
	if _spray_t > 0.0 or _hose_from != null:
		hands = maxf(hands, 0.45) # holding the nozzle up and out
	model.hands_up = hands
	_step_spray(delta)
	_step_hose()


func _step_spray(delta: float) -> void:
	if _spray == null or _spray_t <= 0.0:
		return
	_spray_t -= delta
	var from := _spray.global_position
	var to := _spray_at - from
	if to.length() > 0.1:
		# The particles go along -Z of the emitter: point it at the target,
		# tipped up a little for the drop.
		var aim := (to.normalized() + Vector3.UP * 0.08 * to.length() / 6.0).normalized()
		_spray.global_basis = Basis.looking_at(aim, Vector3.UP if absf(aim.y) < 0.95 else Vector3.FORWARD)
	if _spray_t <= 0.0:
		_spray.emitting = false


func _step_hose() -> void:
	if _hose == null or not _hose.visible:
		return
	if _hose_from == null or not is_instance_valid(_hose_from):
		drop_hose()
		return
	var a := _hose_from.global_transform * _hose_offset
	var b := global_position + global_basis * Vector3(0.0, 0.95 * model.height / 1.75, -0.3)
	var d := b - a
	var l := d.length()
	if l < 0.05:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_hose.global_transform = Transform3D(Basis(x, y * l, z), (a + b) * 0.5)


static func _water() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.albedo_color = Color(0.82, 0.9, 1.0, 0.55)
		_water_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return _water_mat


static func _drop() -> QuadMesh:
	if _drop_mesh == null:
		_drop_mesh = QuadMesh.new()
		_drop_mesh.size = Vector2(0.09, 0.09)
	return _drop_mesh


static func _hose_material() -> StandardMaterial3D:
	if _hose_mat == null:
		_hose_mat = StandardMaterial3D.new()
		_hose_mat.albedo_color = Color(0.85, 0.66, 0.12)
		_hose_mat.roughness = 0.8
	return _hose_mat


## A unit-long cylinder along y, stretched between the truck and the hands.
static func _hose_line() -> CylinderMesh:
	if _hose_mesh == null:
		_hose_mesh = CylinderMesh.new()
		_hose_mesh.top_radius = 0.035
		_hose_mesh.bottom_radius = 0.035
		_hose_mesh.height = 1.0
		_hose_mesh.radial_segments = 8
		_hose_mesh.rings = 1
	return _hose_mesh

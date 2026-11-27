class_name Responder
extends Node3D
## A paramedic or a firefighter on foot (EmergencyUnit): out of the truck,
## across to someone or something, back again. A person (HumanoidModel,
## one shared mesh per look), walking straight lines over the ground (the
## few metres between a parked truck and a sidewalk need no more), saying
## things over their head, and, for a rinse or the hose, spraying water.
##
## Roles: "medic" (the Island Boo-Boo Bus), "captain", "kevin" and
## "firefighter" (the Island Wee-Woo Brigade). Kevin holds the hose: it
## comes off the truck's pump panel, lies along the ground where he's
## dragged it, and up over his shoulder while he walks it out (under his
## arm on the nozzle). A paramedic kneels by whoever's down, a hand on
## them, and rinses paint off with a spray bottle. They climb out of the
## truck when it pulls up and back in when the job's done.
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
## 0..1: an arm up (a wave, pointing).
var gesture := 0.0
## Someone on the ground they're seeing to (world: their shoulder), or INF:
## down on one knee beside them, a hand on them.
var tend := Vector3.INF
## In the truck (board()): sat in a seat, carried with it.
var aboard := false

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
var _hose: MultiMeshInstance3D = null
var _hose_from: Node3D = null
var _hose_offset := Vector3.ZERO
## Where the hose lies on the ground, from the truck out to him (world).
var _trail: Array[Vector3] = []

## Most pieces of hose drawn (one instance each, one draw call in all), and
## how far apart he lays the points it lies along (m).
const HOSE_PIECES := 48
const HOSE_STEP := 0.7

static var _water_mat: StandardMaterial3D
static var _hose_mat: StandardMaterial3D
static var _hose_mesh: CylinderMesh
static var _drop_mesh: QuadMesh
static var _mist_mesh: QuadMesh


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


## Out of the truck: standing at `at` (world, facing `yaw`), having climbed
## out of the seat at `seat` (the model's world transform sat there).
func climb_out_at(at: Vector3, yaw: float, seat: Transform3D) -> void:
	aboard = false
	_heading = Vector2(-sin(yaw), -cos(yaw))
	_ground = at.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	reset_physics_interpolation()
	model.seated = false
	model.climb_out(seat)


## Into the truck's seat at `seat` (in `truck`'s space: the model's origin
## sat there), climbing in by `door` (world).
func board(truck: Node3D, seat: Transform3D, door: Vector3) -> void:
	var from := global_position
	aboard = true
	goal = Vector3.INF
	drop_hose()
	tend = Vector3.INF
	model.task = ""
	model.hands_up = 0.0
	model.set_motion(0.0)
	_speed = 0.0
	reparent(truck, false)
	transform = seat
	reset_physics_interpolation()
	model.seated = true
	model.climb_in(from, door)


## Out of the truck or in it, and not still climbing.
func settled() -> bool:
	return not model.climbing()


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
	# A bottle's is a fine mist, the hose's a heavy stream.
	_spray.mesh = _drop() if big else _mist()
	_spray.lifetime = 0.7 if big else 0.4
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
		_hose = MultiMeshInstance3D.new()
		_hose.name = "Hose"
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _hose_line()
		mm.instance_count = HOSE_PIECES
		mm.visible_instance_count = 0
		_hose.multimesh = mm
		_hose.material_override = _hose_material()
		_hose.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hose.top_level = true
		_hose.global_transform = Transform3D.IDENTITY
		WorldLod.limit(_hose, 1.0, 120.0)
		add_child(_hose)
	_hose.visible = true
	# Off the pump panel and down to the ground beside the truck.
	var pump := from.global_transform * offset
	_trail = [pump, _on_ground(pump + (pump - from.global_position).normalized() * 0.3)]


func drop_hose() -> void:
	_hose_from = null
	_trail.clear()
	if _hose != null:
		_hose.visible = false


## A point dropped to the ground under it (the ground last found under
## them, near enough over the few metres a hose runs).
func _on_ground(p: Vector3) -> Vector3:
	var y := global_position.y if is_nan(_ground) else _ground
	return Vector3(p.x, y + 0.035, p.z)


func _physics_process(delta: float) -> void:
	if _label_t > 0.0:
		_label_t -= delta
		if _label_t <= 0.0:
			_label.visible = false
	if aboard or model.climbing():
		# In the truck, or climbing in or out of it: the truck has them.
		_step_spray(delta)
		_step_hose()
		return
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
	model.hands_up = gesture
	# What the hands are doing.
	if _hose_from != null:
		if _spray_t > 0.0:
			model.task = "hose"
			model.task_at = _spray_at
		elif _speed > 0.4:
			model.task = "hose_drag"
		else:
			model.task = "hose"
			model.task_at = Vector3.INF
	elif _spray_t > 0.0:
		model.task = "rinse"
		model.task_at = _spray_at
	elif tend != Vector3.INF and _speed < 0.4:
		model.task = "kneel"
		model.task_at = tend
	else:
		model.task = ""
	# The hose is laid where he walks.
	if _hose_from != null and _trail.size() >= 2:
		var here := _on_ground(global_position)
		if here.distance_to(_trail[_trail.size() - 1]) > HOSE_STEP and _trail.size() < HOSE_PIECES - 8:
			_trail.append(here)
	_step_spray(delta)
	_step_hose()


func _step_spray(delta: float) -> void:
	if _spray == null or _spray_t <= 0.0:
		return
	_spray_t -= delta
	# Out of the bottle or the nozzle, once it's in hand.
	if model.task in ["hose", "rinse"]:
		_spray.global_position = model.prop_tip().origin
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
	# Off the truck, along the ground where it's been laid, to his heels,
	# up his back and over the shoulder (or under the arm) to the nozzle.
	var pts: Array[Vector3] = []
	pts.append(_hose_from.global_transform * _hose_offset)
	for i in range(1, _trail.size()):
		pts.append(_trail[i])
	var body := model.hose_points()
	if body.is_empty():
		body = [global_position + global_basis * Vector3(0.0, 0.95 * model.height / 1.75, -0.3)]
	var heels := _on_ground(global_position + global_basis * Vector3(0.12, 0.0, 0.5))
	if pts[pts.size() - 1].distance_to(heels) > 0.25:
		pts.append(heels)
	for i in range(body.size() - 1, -1, -1):
		pts.append(body[i])
	var mm := _hose.multimesh
	var n := 0
	for i in range(pts.size() - 1):
		if n >= HOSE_PIECES:
			break
		var a := pts[i]
		var d := pts[i + 1] - a
		var l := d.length()
		if l < 0.02:
			continue
		var y := d / l
		var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		# A shade longer than the gap, so the joins don't show.
		mm.set_instance_transform(n, Transform3D(Basis(x, y * (l + 0.03), z), a + d * 0.5))
		n += 1
	mm.visible_instance_count = n


static func _water() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_mat.albedo_color = Color(0.82, 0.9, 1.0, 0.55)
		_water_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	return _water_mat


static func _mist() -> QuadMesh:
	if _mist_mesh == null:
		_mist_mesh = QuadMesh.new()
		_mist_mesh.size = Vector2(0.03, 0.03)
	return _mist_mesh


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

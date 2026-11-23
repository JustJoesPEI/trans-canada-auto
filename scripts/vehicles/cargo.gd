class_name Cargo
extends RigidBody3D
## A load: a pallet of something, a crate, a bundle of lumber. A plain
## rigid body with real weight that slides on a deck when the truck brakes
## or corners harder than friction can hold, tips if it's tall and narrow,
## and falls off if nothing stops it. Strap it down (TieDowns) to keep it.
##
## Pallets are built the way real ones are: three runners under a top deck,
## with gaps between the runners for the forks, so a forklift picks one up
## by sliding its forks in and lifting.
##
## Faces -Z like the vehicles; sits with its bottom at y = 0.
##
## KINDS: "mass" (kg, all in), "goods" (the size of what's carried: width,
## height, length in metres), "pallet" (on a standard pallet) or "skids"
## (on two runners the forks fit between), and how it's drawn.

const KINDS := {
	"pallet_boxes": {
		"name": "pallet of boxes", "pallet": true, "mass": 520.0,
		"goods": [1.12, 1.0, 1.25], "colour": "#b08a5a",
	},
	"pallet_bricks": {
		"name": "pallet of bricks", "pallet": true, "mass": 1450.0,
		"goods": [1.05, 0.78, 1.15], "colour": "#9c4a32",
	},
	"pallet_sacks": {
		"name": "pallet of feed sacks", "pallet": true, "mass": 900.0,
		"goods": [1.15, 0.95, 1.2], "colour": "#d8cfb4",
	},
	"pallet_empty": {
		"name": "empty pallet", "pallet": true, "mass": 25.0,
		"goods": [0.0, 0.0, 0.0], "colour": "#a88c62",
	},
	"crate": {
		"name": "crate", "pallet": false, "mass": 380.0,
		"goods": [1.3, 1.2, 1.3], "colour": "#8a6a43", "skids": true,
	},
	"lumber": {
		"name": "bundle of lumber", "pallet": false, "mass": 1150.0,
		"goods": [1.15, 0.62, 3.66], "colour": "#d9b77e", "skids": true, "boards": true,
	},
}

const PALLET_W := 1.0 # across the fork openings (x)
const PALLET_L := 1.2 # along the forks (z)
const RUNNER_H := 0.1 # the fork opening is this tall
const TOP_H := 0.025
const SKID_H := 0.1 # crates and bundles sit on skids the forks fit between

@export var kind := "pallet_boxes"

## The whole thing's outside size, for straps and hooks.
var size := Vector3.ONE
var strapped := false

var _straps: MeshInstance3D
var _far_time := 0.0


func display_name() -> String:
	return str(KINDS.get(kind, KINDS["pallet_boxes"])["name"])


func _ready() -> void:
	add_to_group("cargo")
	var k: Dictionary = KINDS.get(kind, KINDS["pallet_boxes"])
	mass = float(k["mass"])
	collision_layer = Layers.CARGO
	collision_mask = Layers.GROUND | Layers.SOLID | Layers.VEHICLES | Layers.CARGO | Layers.BOUNDARY
	var mat := PhysicsMaterial.new()
	mat.friction = 0.5 # wood on steel
	mat.bounce = 0.05
	physics_material_override = mat
	can_sleep = true
	# No made-up damping: it would drag against the world, not the deck, so a
	# loaded truck would feel a brake the size of its load.
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.1
	var l: Array = k["goods"]
	var goods := Vector3(l[0], l[1], l[2])
	var base := 0.0
	var kit := MeshKit.new()
	kit.use_color = true
	var wood := Color(0.62, 0.49, 0.33)
	if bool(k["pallet"]):
		base = RUNNER_H + TOP_H
		for x: float in [-PALLET_W * 0.5 + 0.05, 0.0, PALLET_W * 0.5 - 0.05]:
			_box_shape(Vector3(0.1, RUNNER_H, PALLET_L), Vector3(x, RUNNER_H * 0.5, 0.0))
			_box(kit, Vector3(x, RUNNER_H * 0.5, 0.0), Vector3(0.1, RUNNER_H, PALLET_L), wood.darkened(0.12))
		_box_shape(Vector3(PALLET_W, TOP_H, PALLET_L), Vector3(0.0, RUNNER_H + TOP_H * 0.5, 0.0))
		for i in 7:
			var z := -PALLET_L * 0.5 + 0.07 + i * (PALLET_L - 0.14) / 6.0
			_box(kit, Vector3(0.0, RUNNER_H + TOP_H * 0.5, z), Vector3(PALLET_W, TOP_H, 0.12), wood.lightened(0.04 * (i % 2)))
		size = Vector3(maxf(PALLET_W, goods.x), base + goods.y, maxf(PALLET_L, goods.z))
	elif bool(k.get("skids", false)):
		base = SKID_H
		for x: float in [-goods.x * 0.5 + 0.06, goods.x * 0.5 - 0.06]:
			_box_shape(Vector3(0.1, SKID_H, goods.z), Vector3(x, SKID_H * 0.5, 0.0))
			_box(kit, Vector3(x, SKID_H * 0.5, 0.0), Vector3(0.1, SKID_H, goods.z), wood.darkened(0.2))
		size = Vector3(goods.x, base + goods.y, goods.z)
	if goods.y > 0.0:
		_box_shape(goods, Vector3(0.0, base + goods.y * 0.5, 0.0))
		_load_mesh(kit, k, goods, base)
	var mi := MeshInstance3D.new()
	mi.mesh = kit.commit(null, CarBuilder.paint_material())
	add_child(mi)
	# Weight sits in the middle of the load.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, base + goods.y * 0.45 if goods.y > 0.0 else RUNNER_H * 0.6, 0.0)
	_straps = MeshInstance3D.new()
	var sk := MeshKit.new()
	sk.use_color = true
	var orange := Color(0.95, 0.48, 0.08)
	var top := size.y + 0.012
	var hx := size.x * 0.5 + 0.012
	for z: float in [-size.z * 0.28, size.z * 0.28]:
		_box(sk, Vector3(0.0, top, z), Vector3(size.x + 0.024, 0.01, 0.05), orange)
		for sx: float in [-1.0, 1.0]:
			_box(sk, Vector3(hx * sx, top * 0.5, z), Vector3(0.01, top, 0.05), orange)
	_straps.mesh = sk.commit(null, CarBuilder.paint_material())
	_straps.visible = false
	add_child(_straps)


func set_strapped(on: bool) -> void:
	strapped = on
	if _straps != null:
		_straps.visible = on


func _physics_process(delta: float) -> void:
	# Far from the camera and at rest: hold it still, so it can't fall
	# through ground that's being streamed out (as parked cars do).
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(global_position) > 150.0
	if far and (sleeping or linear_velocity.length() < 0.2):
		_far_time += delta
	else:
		_far_time = 0.0
	var want := far and _far_time > 1.0 and not strapped
	if want and not freeze:
		freeze = true
	elif freeze and not want and Car.ground_below(self):
		freeze = false


## Start held still (somewhere the town hasn't been built yet): it stays
## put until the camera comes near and there's ground under it.
func start_parked() -> void:
	freeze = true
	_far_time = 2.0


func _box_shape(s: Vector3, at: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = s
	var cs := CollisionShape3D.new()
	cs.shape = b
	cs.position = at
	add_child(cs)


func _load_mesh(kit: MeshKit, k: Dictionary, goods: Vector3, base: float) -> void:
	var c := Color.from_string(str(k["colour"]), Color.TAN)
	var centre := Vector3(0.0, base + goods.y * 0.5, 0.0)
	if bool(k.get("boards", false)):
		# A bundle of boards: rows of ends showing at the front and back.
		_box(kit, centre, goods, c)
		var rows := 6
		var cols := 8
		for r in rows:
			for q in cols:
				var x := -goods.x * 0.5 + (q + 0.5) * goods.x / cols
				var y := base + (r + 0.5) * goods.y / rows
				for sz: float in [-1.0, 1.0]:
					_box(kit, Vector3(x, y, sz * (goods.z * 0.5 + 0.003)), Vector3(goods.x / cols - 0.012, goods.y / rows - 0.012, 0.004), c.darkened(0.15 + 0.05 * ((r + q) % 2)))
		return
	if str(kind) == "pallet_boxes":
		# Cartons stacked three high, a little uneven.
		var layers := 3
		for r in layers:
			for ix in 2:
				for iz in 2:
					var bx := goods.x / 2.0
					var bz := goods.z / 2.0
					var by := goods.y / layers
					var cc := c.darkened(0.04 * ((ix + iz + r) % 3))
					_box(kit, Vector3(-goods.x * 0.5 + (ix + 0.5) * bx, base + (r + 0.5) * by, -goods.z * 0.5 + (iz + 0.5) * bz), Vector3(bx - 0.02, by - 0.015, bz - 0.02), cc)
	elif str(kind) == "pallet_sacks" or str(kind) == "pallet_bricks":
		# Sacks five high, or bricks in courses with mortar-dark joints.
		var layers := 5 if str(kind) == "pallet_sacks" else 9
		for r in layers:
			var by := goods.y / layers
			_box(kit, Vector3(0.0, base + (r + 0.5) * by, 0.0), Vector3(goods.x - 0.04 * (r % 2), by - 0.02, goods.z - 0.04 * ((r + 1) % 2)), c.darkened(0.03 * (r % 2)))
	else:
		_box(kit, centre, goods, c)
		if str(kind) == "crate":
			# Battens round the edges.
			var dark := c.darkened(0.25)
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(kit, centre + Vector3(0.0, sy * (goods.y * 0.5 - 0.05), sz * (goods.z * 0.5 + 0.005)), Vector3(goods.x + 0.01, 0.1, 0.02), dark)
					_box(kit, centre + Vector3(sy * (goods.x * 0.5 + 0.005), 0.0, sz * (goods.z * 0.5 - 0.05)), Vector3(0.02, goods.y + 0.01, 0.1), dark)


## A plain box into a kit, all six faces.
static func _box(kit: MeshKit, c: Vector3, s: Vector3, colour: Color) -> void:
	TruckBuilder.box(kit, c, s, colour)

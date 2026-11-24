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
var _kits := {} # surface -> MeshKit, while building the mesh


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
	mat.bounce = 0.0
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
	for sname: String in ["rough", "gloss", "steel", "glass"]:
		var kit := MeshKit.new()
		kit.use_color = true
		_kits[sname] = kit
	var wood := Color(0.62, 0.49, 0.33)
	if bool(k["pallet"]):
		base = RUNNER_H + TOP_H
		for x: float in [-PALLET_W * 0.5 + 0.05, 0.0, PALLET_W * 0.5 - 0.05]:
			_box_shape(Vector3(0.1, RUNNER_H, PALLET_L), Vector3(x, RUNNER_H * 0.5, 0.0))
		_box_shape(Vector3(PALLET_W, TOP_H, PALLET_L), Vector3(0.0, RUNNER_H + TOP_H * 0.5, 0.0))
		_pallet_mesh(wood)
		size = Vector3(maxf(PALLET_W, goods.x), base + goods.y, maxf(PALLET_L, goods.z))
	elif bool(k.get("skids", false)):
		base = SKID_H
		for x: float in [-goods.x * 0.5 + 0.06, goods.x * 0.5 - 0.06]:
			_box_shape(Vector3(0.1, SKID_H, goods.z), Vector3(x, SKID_H * 0.5, 0.0))
			_box(_kits["rough"], Vector3(x, SKID_H * 0.5, 0.0), Vector3(0.1, SKID_H, goods.z), wood.darkened(0.2))
			# The skids' end grain, darker.
			for sz: float in [-1.0, 1.0]:
				_box(_kits["rough"], Vector3(x, SKID_H * 0.5, sz * (goods.z * 0.5 + 0.002)), Vector3(0.1, SKID_H - 0.01, 0.004), wood.darkened(0.35))
		size = Vector3(goods.x, base + goods.y, goods.z)
	if goods.y > 0.0:
		_box_shape(goods, Vector3(0.0, base + goods.y * 0.5, 0.0))
		_load_mesh(k, goods, base)
	var mi := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	for sname: String in ["rough", "gloss", "steel", "glass"]:
		var kit: MeshKit = _kits[sname]
		if not kit.is_empty():
			kit.commit(mesh, TruckBuilder.surface_material(sname))
	mi.mesh = mesh
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
	_straps.mesh = sk.commit(null, CarBuilder.material("rough"))
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


## A stringer pallet: three stringers with the fork notches' shadow, seven
## top boards, three bottom boards, and nail heads.
func _pallet_mesh(wood: Color) -> void:
	var r: MeshKit = _kits["rough"]
	var st: MeshKit = _kits["steel"]
	var xs := [-PALLET_W * 0.5 + 0.05, 0.0, PALLET_W * 0.5 - 0.05]
	for x: float in xs:
		_box(r, Vector3(x, RUNNER_H * 0.5, 0.0), Vector3(0.1, RUNNER_H - 0.002, PALLET_L), wood.darkened(0.12))
		# End grain, darker.
		for sz: float in [-1.0, 1.0]:
			_box(r, Vector3(x, RUNNER_H * 0.5, sz * (PALLET_L * 0.5 + 0.001)), Vector3(0.096, RUNNER_H - 0.006, 0.002), wood.darkened(0.3))
	for i in 7:
		var z := -PALLET_L * 0.5 + 0.07 + i * (PALLET_L - 0.14) / 6.0
		var c := wood.lightened(0.05 * ((i * 3) % 2)).darkened(0.04 * ((i * 5) % 3))
		_box(r, Vector3(0.0, RUNNER_H + TOP_H * 0.5, z), Vector3(PALLET_W, TOP_H, 0.12), c)
		for x: float in xs:
			for nz: float in [-0.03, 0.03]:
				_box(st, Vector3(x, RUNNER_H + TOP_H + 0.001, z + nz), Vector3(0.012, 0.002, 0.012), Color(0.3, 0.3, 0.3))
	# Bottom boards (no collision: the forks pass over them).
	for z: float in [-PALLET_L * 0.5 + 0.07, 0.0, PALLET_L * 0.5 - 0.07]:
		_box(r, Vector3(0.0, 0.009, z), Vector3(PALLET_W, 0.018, 0.14), wood.darkened(0.08))


func _load_mesh(k: Dictionary, goods: Vector3, base: float) -> void:
	var r: MeshKit = _kits["rough"]
	var g: MeshKit = _kits["gloss"]
	var st: MeshKit = _kits["steel"]
	var c := Color.from_string(str(k["colour"]), Color.TAN)
	var centre := Vector3(0.0, base + goods.y * 0.5, 0.0)
	var top := base + goods.y
	match str(kind):
		"lumber":
			_lumber(goods, base, c)
		"pallet_boxes":
			# Cartons stacked three high, a little uneven, taped and
			# labelled, with corner boards under the stretch wrap.
			var layers := 3
			for row in layers:
				for ix in 2:
					for iz in 2:
						var bx := goods.x / 2.0
						var bz := goods.z / 2.0
						var by := goods.y / layers
						var cc := c.darkened(0.04 * ((ix + iz + row) % 3))
						var jog := Vector3(0.006 * ((ix + row) % 2), 0.0, -0.006 * ((iz + row) % 2))
						var bc := Vector3(-goods.x * 0.5 + (ix + 0.5) * bx, base + (row + 0.5) * by, -goods.z * 0.5 + (iz + 0.5) * bz) + jog
						var bs := Vector3(bx - 0.02, by - 0.015, bz - 0.02)
						_box(r, bc, bs, cc)
						# Tape across the top seam, and down the ends.
						_box(g, bc + Vector3(0, bs.y * 0.5 + 0.001, 0), Vector3(0.05, 0.002, bs.z + 0.002), cc.lightened(0.25))
						for sz: float in [-1.0, 1.0]:
							_box(g, bc + Vector3(0, bs.y * 0.5 - 0.05, sz * (bs.z * 0.5 + 0.001)), Vector3(0.05, 0.1, 0.002), cc.lightened(0.25))
						# A label on the outward faces: white, with lines of print.
						var out := Vector3(signf(bc.x), 0, 0)
						var lc := bc + Vector3(out.x * (bs.x * 0.5 + 0.0015), 0.02, 0.0)
						_box(g, lc, Vector3(0.002, 0.1, 0.14), Color(0.95, 0.95, 0.92))
						for li in 3:
							_box(g, lc + Vector3(out.x * 0.0012, 0.03 - li * 0.022, -0.02 * (li % 2)), Vector3(0.002, 0.008, 0.09 - 0.02 * li), Color(0.15, 0.15, 0.15))
						var oz := signf(bc.z)
						var fc := bc + Vector3(0.0, -0.04, oz * (bs.z * 0.5 + 0.0015))
						_arrows(g, fc, oz)
			# Corner boards up the four vertical edges.
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var e := Vector3(sx * (goods.x * 0.5 - 0.005), centre.y, sz * (goods.z * 0.5 - 0.005))
					_box(r, e + Vector3(-sx * 0.02, 0, 0.0), Vector3(0.05, goods.y - 0.02, 0.006), Color(0.55, 0.45, 0.3))
					_box(r, e + Vector3(0, 0, -sz * 0.02), Vector3(0.006, goods.y - 0.02, 0.05), Color(0.55, 0.45, 0.3))
			_wrap(goods, base)
		"pallet_bricks":
			# Courses of bricks, every brick's face showing in the mortar-dark
			# block, steel bands round it both ways.
			_box(r, centre, goods - Vector3(0.01, 0.0, 0.01), c.darkened(0.45))
			var courses := 10
			var bh := goods.y / courses
			for row in courses:
				var y := base + (row + 0.5) * bh
				for face in 4:
					var along := goods.z if face < 2 else goods.x
					var bl := 0.215 if (row + face) % 2 == 0 else 0.1025
					var n := int(along / 0.225)
					var off := 0.0 if row % 2 == 0 else 0.11
					for i in n:
						var t := -along * 0.5 + 0.01 + off + i * 0.225 + bl * 0.5
						if t + bl * 0.5 > along * 0.5:
							continue
						var shade := c.darkened(0.08 * ((i * 7 + row * 3 + face) % 3)).lightened(0.05 * ((i + row) % 2))
						if face < 2:
							var sx := -1.0 if face == 0 else 1.0
							_box(r, Vector3(sx * goods.x * 0.5, y, t), Vector3(0.006, bh - 0.012, bl), shade)
						else:
							var sz := -1.0 if face == 2 else 1.0
							_box(r, Vector3(t, y, sz * goods.z * 0.5), Vector3(bl, bh - 0.012, 0.006), shade)
			# The top course, seen from above: bricks on their beds.
			var nx := int(goods.x / 0.225)
			var nz := int(goods.z / 0.11)
			for i in nx:
				for j in nz:
					var shade := c.darkened(0.08 * ((i * 5 + j * 3) % 3)).lightened(0.04 * ((i + j) % 2))
					var bx0 := -nx * 0.1125 + (i + 0.5) * 0.225
					_box(r, Vector3(bx0, top + 0.002, -nz * 0.055 + (j + 0.5) * 0.11), Vector3(0.213, 0.004, 0.1), shade)
			for bx: float in [-goods.x * 0.28, goods.x * 0.28]:
				_band(st, Vector3(bx, 0, 0), goods, base, true, Color(0.55, 0.56, 0.58))
			for bz: float in [-goods.z * 0.28, goods.z * 0.28]:
				_band(st, Vector3(0, 0, bz), goods, base, false, Color(0.55, 0.56, 0.58))
		"pallet_sacks":
			# Plump sacks five layers high, laid crosswise in turns, each with
			# a printed band.
			var layers := 5
			var sh := goods.y / layers
			for row in layers:
				var y := base + (row + 0.5) * sh
				var cross := row % 2 == 1
				for i in 3:
					var sc := c.darkened(0.03 * ((i + row) % 3))
					var pos: Vector3
					var half: Vector3
					if cross:
						pos = Vector3(-goods.x * 0.5 + (i + 0.5) * goods.x / 3.0, y, 0.0)
						half = Vector3(goods.x / 6.0 - 0.008, sh * 0.5, goods.z * 0.5 - 0.01)
					else:
						pos = Vector3(0.0, y, -goods.z * 0.5 + (i + 0.5) * goods.z / 3.0)
						half = Vector3(goods.x * 0.5 - 0.01, sh * 0.5, goods.z / 6.0 - 0.008)
					r.color = sc
					CarBuilder._bbox(r, pos, half, minf(half.y, 0.07) * 0.95)
					# The printed band across the sack's top.
					var flat := maxf(0.0, minf(half.y, 0.07) * 0.95)
					var band := Vector3((half.x - flat) * 2.0, 0.003, 0.06) if not cross else Vector3(0.06, 0.003, (half.z - flat) * 2.0)
					_box(g, pos + Vector3(0, half.y + 0.0015, 0), band, Color(0.15, 0.4, 0.2) if (i + row) % 2 == 0 else Color(0.7, 0.15, 0.1))
			_wrap(goods, base)
		"crate":
			# Planks on every face, battens round the edges, cross braces on
			# the sides, stencilled arrows.
			_box(r, centre, goods, c)
			var dark := c.darkened(0.25)
			var planks := 7
			for i in range(1, planks):
				var y := base + goods.y * float(i) / planks
				for sx: float in [-1.0, 1.0]:
					_box(r, Vector3(sx * (goods.x * 0.5 + 0.001), y, 0), Vector3(0.002, 0.006, goods.z - 0.02), c.darkened(0.4))
				for sz: float in [-1.0, 1.0]:
					_box(r, Vector3(0, y, sz * (goods.z * 0.5 + 0.001)), Vector3(goods.x - 0.02, 0.006, 0.002), c.darkened(0.4))
			for i in range(1, planks):
				var x := -goods.x * 0.5 + goods.x * float(i) / planks
				_box(r, Vector3(x, top + 0.001, 0), Vector3(0.006, 0.002, goods.z - 0.02), c.darkened(0.4))
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					_box(r, centre + Vector3(0.0, sy * (goods.y * 0.5 - 0.05), sz * (goods.z * 0.5 + 0.012)), Vector3(goods.x + 0.02, 0.1, 0.024), dark)
					_box(r, centre + Vector3(sy * (goods.x * 0.5 + 0.012), 0.0, sz * (goods.z * 0.5 - 0.05)), Vector3(0.024, goods.y + 0.02, 0.1), dark)
					_box(r, centre + Vector3(sy * (goods.x * 0.5 + 0.012), sz * (goods.y * 0.5 - 0.05), 0.0), Vector3(0.024, 0.1, goods.z + 0.02), dark)
			# Diagonal braces on the two long sides.
			var diag := sqrt(goods.y * goods.y + goods.z * goods.z) - 0.2
			var ang := atan2(goods.y, goods.z)
			for sx: float in [-1.0, 1.0]:
				r.color = dark
				CarBuilder._bbox(r, centre + Vector3(sx * (goods.x * 0.5 + 0.012), 0, 0), Vector3(0.012, 0.045, diag * 0.5 - 0.04), 0.004, Basis(Vector3.RIGHT, ang))
			for sz: float in [-1.0, 1.0]:
				_arrows(g, centre + Vector3(0.18, 0.08, sz * (goods.z * 0.5 + 0.025)), sz)
				# FRAGILE: a red bar of stencilling.
				_box(g, centre + Vector3(-0.2, -0.15, sz * (goods.z * 0.5 + 0.025)), Vector3(0.36, 0.06, 0.002), Color(0.6, 0.08, 0.05))
		_:
			_box(r, centre, goods, c)


## Two "this side up" arrows stencilled on a face facing ±z (sz).
func _arrows(g: MeshKit, c: Vector3, sz: float) -> void:
	var col := Color(0.12, 0.12, 0.12)
	for dx: float in [-0.04, 0.04]:
		var p := c + Vector3(dx, 0, sz * 0.001)
		_box(g, p, Vector3(0.014, 0.06, 0.002), col)
		g.color = col
		var t := p + Vector3(0, 0.03, sz * 0.002)
		g.tri(t + Vector3(-0.025, 0, 0), t + Vector3(0.025, 0, 0), t + Vector3(0, 0.035, 0), Vector3(0, 0, sz))
	_box(g, c + Vector3(0, -0.045, sz * 0.001), Vector3(0.1, 0.008, 0.002), col)


## A steel band round the load, the long way (along z) or across.
func _band(kit: MeshKit, at: Vector3, goods: Vector3, base: float, along_z: bool, col: Color) -> void:
	var w := 0.025
	var t := 0.004
	var top := base + goods.y
	if along_z:
		_box(kit, Vector3(at.x, top + t * 0.5, 0), Vector3(w, t, goods.z + t * 2.0), col)
		for sz: float in [-1.0, 1.0]:
			_box(kit, Vector3(at.x, base + goods.y * 0.5, sz * (goods.z * 0.5 + t * 0.5)), Vector3(w, goods.y, t), col)
	else:
		_box(kit, Vector3(0, top + t * 0.5, at.z), Vector3(goods.x + t * 2.0, t, w), col)
		for sx: float in [-1.0, 1.0]:
			_box(kit, Vector3(sx * (goods.x * 0.5 + t * 0.5), base + goods.y * 0.5, at.z), Vector3(t, goods.y, w), col)


## Stretch wrap round the sides of a load: a faint, shiny film.
func _wrap(goods: Vector3, base: float) -> void:
	var k: MeshKit = _kits["glass"]
	k.color = Color(0.9, 0.94, 1.0, 0.16)
	var y0 := base - 0.01
	var y1 := base + goods.y * 0.92
	var hx := goods.x * 0.5 + 0.012
	var hz := goods.z * 0.5 + 0.012
	for sx: float in [-1.0, 1.0]:
		k.quad(Vector3(sx * hx, y0, -hz), Vector3(sx * hx, y0, hz), Vector3(sx * hx, y1, hz), Vector3(sx * hx, y1, -hz), Vector3(sx, 0, 0))
	for sz: float in [-1.0, 1.0]:
		k.quad(Vector3(-hx, y0, sz * hz), Vector3(hx, y0, sz * hz), Vector3(hx, y1, sz * hz), Vector3(-hx, y1, sz * hz), Vector3(0, 0, sz))


## A bundle of lumber: boards in rows, their ends showing (each a little
## different, the far ends in the end sealer's colour), stickers between some layers,
## and plastic bands round it.
func _lumber(goods: Vector3, base: float, c: Color) -> void:
	var r: MeshKit = _kits["rough"]
	var g: MeshKit = _kits["gloss"]
	var rows := 6
	var cols := 8
	var rh := goods.y / rows
	var cw := goods.x / cols
	for row in rows:
		for q in cols:
			var x := -goods.x * 0.5 + (q + 0.5) * cw
			var y := base + (row + 0.5) * rh
			var bc := c.darkened(0.06 * ((row * 3 + q * 5) % 3)).lightened(0.04 * ((row + q * 2) % 2))
			_box(r, Vector3(x, y, 0.0), Vector3(cw - 0.006, rh - 0.008, goods.z - 0.01 * ((q + row) % 3)), bc)
			for sz: float in [-1.0, 1.0]:
				var end := Vector3(x, y, sz * ((goods.z - 0.01 * ((q + row) % 3)) * 0.5 + 0.002))
				# The far end is dipped in the mill's end sealer.
				_box(r, end, Vector3(cw - 0.012, rh - 0.014, 0.004), bc.darkened(0.15) if sz < 0.0 else bc.lerp(Color(0.2, 0.42, 0.72), 0.6))
				# A ring of grain on the end.
				_box(r, end + Vector3(0.01 * ((q % 2) * 2 - 1), 0.005, sz * 0.001), Vector3(cw * 0.35, 0.004, 0.003), bc.darkened(0.3))
		# Stickers: thin strips across, between every second row.
		if row % 2 == 1 and row < rows - 1:
			for sz2: float in [-goods.z * 0.38, 0.0, goods.z * 0.38]:
				_box(r, Vector3(0, base + (row + 1) * rh, sz2), Vector3(goods.x + 0.01, 0.012, 0.035), c.darkened(0.35))
	# The mill's stencil on the sides.
	for sx: float in [-1.0, 1.0]:
		_box(g, Vector3(sx * (goods.x * 0.5 + 0.002), base + goods.y * 0.55, -0.6), Vector3(0.002, 0.12, 0.7), Color(0.1, 0.25, 0.5))
	for bz: float in [-goods.z * 0.3, goods.z * 0.3]:
		_band(g, Vector3(0, 0, bz), goods, base, false, Color(0.92, 0.92, 0.9))


## A plain box into a kit, all six faces.
static func _box(kit: MeshKit, c: Vector3, s: Vector3, colour: Color) -> void:
	TruckBuilder.box(kit, c, s, colour)

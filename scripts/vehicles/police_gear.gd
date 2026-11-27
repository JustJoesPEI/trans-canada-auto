class_name PoliceGear
extends Node3D
## What makes a police car one, beyond its paint (CarBuilder._police builds
## the band and push bar into the body): a red and blue light bar on the
## roof, a pair of lights in the grille, the words down the sides and on
## the back, and the siren.
##
## Press L (emergency_lights) in the driver's seat to go through: lights,
## lights and siren, off. The lights flash red-left, blue-right in a quick
## double pulse and throw their colour on everything round the car.
##
## A child of the car's body, so it rocks and leans with it.

const RED := Color(1.0, 0.06, 0.04)
const BLUE := Color(0.03, 0.12, 1.0)
const FLASH_HZ := 1.6 ## full red-blue cycles a second
const SIREN_DB := -4.0

enum Mode { OFF, LIGHTS, SIREN }

var car: Car
var builder: CarBuilder
var mode := Mode.OFF

var _lenses: Array[StandardMaterial3D] = [] # [red, blue]
var _grille: Array[StandardMaterial3D] = []
var _glow: Array[OmniLight3D] = []
var _siren: AudioStreamPlayer3D
var _t := 0.0


func _init(the_car: Car, the_builder: CarBuilder) -> void:
	car = the_car
	builder = the_builder
	name = "PoliceGear"


func _ready() -> void:
	var shape := car.shape
	var cab: Dictionary = shape["cabin"]
	var roof := float(cab["roof"]) + 0.035
	var bar_z := lerpf(float(cab["zb"]), float(cab["zc"]), 0.18 if not shape.has("bed") else 0.3)
	var bar_w := minf(float(cab["wr"]) * 2.0 - 0.06, 1.3)
	_light_bar(Vector3(0, roof, bar_z), bar_w)
	_grille_lights()
	_words()
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = load("res://sounds/cars/shared/siren.ogg")
	if _siren.stream is AudioStreamOggVorbis:
		(_siren.stream as AudioStreamOggVorbis).loop = true
	_siren.volume_db = SIREN_DB
	_siren.unit_size = 14.0
	_siren.max_db = 6.0
	# Out of earshot past this (it had no limit: every cruiser's siren on
	# the map was mixed, wherever it was).
	_siren.max_distance = 600.0
	_siren.position = Vector3(0, float(shape["lights_y"]), float(shape["front_axle"]))
	add_child(_siren)
	_apply(0.0, 0.0)


## A police car's (an ambulance's or a fire engine's gear, EmergencyGear,
## says no): painting it is painting the police.
func is_police() -> bool:
	return true


func _unhandled_input(event: InputEvent) -> void:
	if car.driver != null and event.is_action_pressed("emergency_lights"):
		set_mode((mode + 1) % 3)
		get_viewport().set_input_as_handled()


func set_mode(m: int) -> void:
	mode = m as Mode
	if mode == Mode.SIREN:
		if not _siren.playing:
			_siren.play()
	else:
		_siren.stop()
	if mode == Mode.OFF:
		_apply(0.0, 0.0)


func _process(delta: float) -> void:
	if mode == Mode.OFF:
		return
	_t += delta * FLASH_HZ
	var ph := fposmod(_t, 1.0)
	# Each half of the cycle is one colour's turn: two quick pulses.
	var red := _pulse(ph * 2.0) if ph < 0.5 else 0.0
	var blue := _pulse(ph * 2.0 - 1.0) if ph >= 0.5 else 0.0
	# Only when it changes: a few times a second, not every frame (four
	# materials and two lights set each time).
	if red != _shown_red or blue != _shown_blue:
		_apply(red, blue)


static func _pulse(p: float) -> float:
	return 1.0 if (p < 0.16 or (p > 0.24 and p < 0.4)) else 0.0


var _shown_red := -1.0
var _shown_blue := -1.0


func _apply(red: float, blue: float) -> void:
	_shown_red = red
	_shown_blue = blue
	var on := [red, blue]
	for i in 2:
		var lit: float = on[i]
		_lenses[i].emission_energy_multiplier = 0.1 + lit * 2.4
		if i < _grille.size():
			# The grille pair flashes the other way round.
			var g: float = on[1 - i]
			_grille[i].emission_energy_multiplier = 0.05 + g * 2.4
		_glow[i].light_energy = lit * 2.2
		_glow[i].visible = lit > 0.0


## The bar: a black base on two feet, a lens the length of it (red on the
## driver's side, blue on the other), each half under its own light.
func _light_bar(at: Vector3, w: float) -> void:
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.04, 0.04, 0.045)
	base_mat.roughness = 0.55
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.05, 0.3)
	base.mesh = bm
	base.material_override = base_mat
	base.position = at + Vector3(0, 0.055, 0)
	add_child(base)
	for s: float in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.06, 0.04, 0.32)
		foot.mesh = fm
		foot.material_override = base_mat
		foot.position = at + Vector3(s * (w * 0.5 - 0.12), 0.02, 0)
		add_child(foot)
	var cols := [RED, BLUE]
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var mat := _lens_material(cols[i])
		_lenses.append(mat)
		var lens := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(w * 0.5 - 0.03, 0.075, 0.27)
		lens.mesh = lm
		lens.material_override = mat
		lens.position = at + Vector3(s * (w * 0.25 - 0.005), 0.118, 0)
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lens)
		var glow := OmniLight3D.new()
		glow.light_color = cols[i]
		glow.omni_range = 11.0
		glow.omni_attenuation = 1.3
		glow.shadow_enabled = false
		glow.position = at + Vector3(s * w * 0.3, 0.2, 0)
		glow.visible = false
		add_child(glow)
		_glow.append(glow)
	# A white takedown light in the middle, facing ahead.
	var mid := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.05, 0.072, 0.272)
	mid.mesh = mm
	var mid_mat := _lens_material(Color(0.95, 0.95, 0.92))
	mid_mat.emission_energy_multiplier = 0.1
	mid.material_override = mid_mat
	mid.position = at + Vector3(0, 0.118, 0)
	add_child(mid)


## Two small lights flashing behind the grille.
func _grille_lights() -> void:
	var shape := car.shape
	var st: Array = shape["stations"]
	var fz := float(st[0][0]) - 0.03
	var ly := float(shape["lights_y"])
	var hw := float(st[1][1])
	var truck := shape.has("bed")
	var cols := [RED, BLUE]
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var mat := _lens_material(cols[i])
		_grille.append(mat)
		var g := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.11, 0.035, 0.02)
		g.mesh = gm
		g.material_override = mat
		g.position = Vector3(s * hw * (0.3 if truck else 0.22), ly - (0.06 if truck else 0.0), fz)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(g)


func _lens_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c.darkened(0.4)
	m.roughness = 0.15
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.15
	return m


## POLICE on the band down each side, the town's name behind it, the unit
## number on the rear quarter and POLICE across the back.
func _words() -> void:
	var shape := car.shape
	var band := builder.police_band()
	var h := float(band[1]) - float(band[0])
	# A label is centred on its whole line, descenders and all, so capitals
	# sit high: drop them to the band's middle.
	var y_mid := (float(band[0]) + float(band[1])) * 0.5 - h * 0.1
	var cab: Dictionary = shape["cabin"]
	var doors_mid := lerpf(float(cab["za"]), float(cab["zc"]), 0.38 if not shape.has("bed") else 0.55)
	var word := str(shape.get("band_text", "POLICE"))
	var fleet := str(shape.get("fleet_text", ""))
	var unit := int(shape.get("unit", 0))
	for s: float in [-1.0, 1.0]:
		# Turned to face out of each side, so it reads the right way round from either.
		_label(word, Vector3(s * (_clear_x(doors_mid, y_mid, word.length() * h * 0.72 * 0.7) + 0.012), y_mid, doors_mid), s, h * 0.72, Color.WHITE)
		if fleet != "":
			var fz := doors_mid + (0.88 if not shape.has("bed") else 1.4)
			_label(fleet, Vector3(s * (_clear_x(fz, y_mid, fleet.length() * h * 0.42 * 0.7) + 0.012), y_mid, fz), s, h * 0.42, Color.WHITE)
		if unit > 0:
			var uz := float(shape["rear_axle"]) + (0.6 if not shape.has("bed") else 0.55)
			var uy := float(band[1]) + 0.11
			if not shape.has("bed"):
				uz = float(shape["rear_axle"])
				uy = float(band[0]) - 0.12
			_label(str(unit), Vector3(s * (builder.outer_x(uz, uy) + 0.012), uy, uz), s, 0.13, Color(0.1, 0.16, 0.3))
	# Across the back: the tailgate, or the hatch under the glass.
	var tail_z := float(shape["stations"][shape["stations"].size() - 1][0]) + 0.02
	# On a hatch the plate is in the middle, so the word goes beside it.
	var ty := float(shape["tail_y"]) - 0.1
	var tx := -0.38
	if shape.has("bed"):
		var bed: Dictionary = shape["bed"]
		tail_z = float(bed["z1"]) + float(bed["thick"]) + 0.012
		ty = float(bed["floor"]) + 0.07
		tx = 0.0
	# The unit number big on the roof, for the helicopter.
	if unit > 0:
		var roof_label := Label3D.new()
		roof_label.text = str(unit)
		_style(roof_label, 0.32, Color(0.1, 0.16, 0.3))
		roof_label.position = Vector3(0, float(cab["roof"]) + 0.045, lerpf(float(cab["zb"]), float(cab["zc"]), 0.62))
		roof_label.rotation = Vector3(-PI * 0.5, 0, 0)
		add_child(roof_label)
	var back := Label3D.new()
	back.text = str(shape.get("back_text", word))
	_style(back, 0.065 if not shape.has("bed") else 0.1, Color(0.1, 0.16, 0.3))
	back.position = Vector3(tx, ty, tail_z)
	add_child(back)


## How far out a flat label as long as `length`, centred at z, must stand
## to clear the body all along it.
func _clear_x(z: float, y: float, length: float) -> float:
	var x := 0.0
	for k in 7:
		x = maxf(x, builder.outer_x(z + length * (float(k) / 6.0 - 0.5), y))
	return x


func _label(text: String, pos: Vector3, side: float, height: float, colour: Color) -> void:
	var l := Label3D.new()
	l.text = text
	_style(l, height, colour)
	l.position = pos + Vector3(side * 0.008, 0, 0)
	# Label3D shows its text toward +Z: turn that to face out of this side.
	l.rotation.y = side * PI * 0.5
	add_child(l)


static func _style(l: Label3D, height: float, colour: Color) -> void:
	l.font_size = 96
	l.outline_size = 0
	# Capital letters are about 0.72 of the font size.
	l.pixel_size = height / (96.0 * 0.72)
	l.modulate = colour
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

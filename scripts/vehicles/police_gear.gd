class_name PoliceGear
extends Node3D
## What makes a police car one, beyond its paint and kit (CarBuilder._police
## builds the band, the light bar's housing, the push bar and the rest into
## the body): the lenses that flash (the bar's, the grille's, the push
## bar's and the visor and rear deck lights inside), the words down the
## sides and on the back, and the siren.
##
## The lenses are two meshes per model and livery, built once
## (CarBuilder.flash_meshes): one lit on the red half of the cycle, one on
## the blue. Every car draws them with one shared material and says how lit
## its own are with an instance uniform.
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

## The two flashing meshes of each model and livery: key -> [A, B].
static var _flash_cache := {}
static var _lens_mat: ShaderMaterial

var _flash: Array[MeshInstance3D] = [] # [red half, blue half]
var _glow: Array[OmniLight3D] = []
var _siren: AudioStreamPlayer3D
var _t := 0.0


func _init(the_car: Car, the_builder: CarBuilder) -> void:
	car = the_car
	builder = the_builder
	name = "PoliceGear"


func _ready() -> void:
	var shape := car.shape
	_lenses()
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
		if i < _flash.size():
			_flash[i].set_instance_shader_parameter("lit", lit)
		_glow[i].light_energy = lit * 2.2
		_glow[i].visible = lit > 0.0


## The flashing lenses (built once per model and livery) and the two
## lights that throw their colour round, one over each half of the bar.
func _lenses() -> void:
	var lb := builder.light_bar()
	var at: Vector3 = lb["at"]
	var cols := [RED, BLUE]
	if not TrafficDensity.server:
		if _lens_mat == null:
			_lens_mat = ShaderMaterial.new()
			_lens_mat.shader = load("res://shaders/police_lens.gdshader")
		var key := "%s|%s" % [car.model_id, car.livery]
		if not _flash_cache.has(key):
			_flash_cache[key] = builder.flash_meshes(_lens_mat)
		for i in 2:
			var mi := MeshInstance3D.new()
			mi.name = "Flash" + ("Red" if i == 0 else "Blue")
			mi.mesh = _flash_cache[key][i]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if str(car.shape.get("bar_lens", "")) == "clear":
				mi.set_instance_shader_parameter("clear_lens", 1.0)
			add_child(mi)
			_flash.append(mi)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var glow := OmniLight3D.new()
		glow.light_color = cols[i]
		glow.omni_range = 11.0
		glow.omni_attenuation = 1.3
		glow.shadow_enabled = false
		glow.position = at + Vector3(s * float(lb["w"]) * 0.3, 0.2, 0)
		glow.visible = false
		add_child(glow)
		_glow.append(glow)


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
		if word != "":
			_label(word, Vector3(s * (_clear_x(doors_mid, y_mid, word.length() * h * 0.72 * 0.7) + 0.012), y_mid, doors_mid), s, h * 0.72, Color.WHITE)
		if fleet != "":
			var fz := doors_mid + (0.88 if not shape.has("bed") else 1.4)
			_label(fleet, Vector3(s * (_clear_x(fz, y_mid, fleet.length() * h * 0.42 * 0.7) + 0.012), y_mid, fz), s, h * 0.42, Color.WHITE)
		if unit > 0:
			var uz := float(shape["rear_axle"]) + (0.6 if not shape.has("bed") else 0.55)
			var uy := float(band[1]) + 0.11
			var ucol := Color(0.1, 0.16, 0.3)
			if str(shape.get("unit_at", "")) == "fender":
				# On the front fender, ahead of the door (Charlottetown's).
				uz = builder.side_anchor("front_fender")
				uy = float(shape["cabin"]["belt"]) - 0.13
				ucol = Color.html(str(shape.get("unit_colour", "#14224a")))
			elif not shape.has("bed"):
				# On the band, behind the rear wheel, in white.
				uz = float(shape["rear_axle"]) + 0.5
				for dd: Array in shape.get("decals", []):
					if str(dd[1]) == "behind_doors":
						# Clear of the words laid behind the doors.
						var e := CarBuilder.livery_entry(str(dd[0]))
						uz = maxf(uz, builder.side_anchor("behind_doors") + float(dd[2]) + float(dd[4]) * float(e.get("aspect", 4.0)) * 0.5 + 0.15)
				if fleet != "":
					# Clear of the fleet's name.
					var fz2 := doors_mid + 0.88
					uz = maxf(uz, fz2 + fleet.length() * h * 0.42 * 0.35 + 0.22)
				uy = y_mid
				ucol = Color.WHITE
				if uz > float(band[3]) - 0.12:
					continue # no room: the roof carries it
			var uh := 0.075 if str(shape.get("unit_at", "")) == "fender" else h * 0.6
			_label(str(unit), Vector3(s * (_clear_x(uz, uy, 0.2, uh) + 0.012), uy, uz), s, uh, ucol)
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
func _clear_x(z: float, y: float, length: float, height := 0.0) -> float:
	var x := 0.0
	for k in 7:
		for dy: float in [-0.5, 0.0, 0.5]:
			x = maxf(x, builder.outer_x(z + length * (float(k) / 6.0 - 0.5), y + dy * height))
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

class_name EmergencyGear
extends PoliceGear
## The lights, words and siren of a fire engine or an ambulance (the
## Island Wee-Woo Brigade, the Island Boo-Boo Bus): what PoliceGear is to a
## cruiser, laid out from the model's shape instead of a car's cabin.
##
## Car makes one for a model whose shape has "beacons", and it sits in the
## same `car.police` slot, so everything that makes way for a siren
## (SirenLane, RoadUsers, the traffic pulling over) and the player's light
## switch work the same. It isn't the police: `is_police()` is false, so
## painting one isn't painting a cruiser and nobody chases you for it as if
## it were.
##
## shape["beacons"]: lenses, each {"pos": [x, y, z], "size": [x, y, z],
## "group": 0 or 1, "colour": "#rrggbb"}. The two groups flash in turn, a
## quick double pulse each (PoliceGear's rhythm), and each throws its
## light (shape["glow"]: one colour per group) round about.
## shape["words"]: {"text", "pos", "face" ("left", "right", "back",
## "front", "up") or "normal" (facing out of a sloping face), "height",
## "colour", "font", "outline" (a colour) and "outline_size", "mirror"},
## Label3Ds like a cruiser's.
## shape["siren_pitch"]: the siren's pitch (the brigade's is lower).

## The lettering, as real services have it: a plain bold sans for the
## ambulance (Liberation Sans Bold), gold-leaf slab serif for the fire
## department (Alfa Slab One), both OFL, imported as distance-field fonts
## so they stay crisp at any distance. A word picks one with "font"
## ("sans", the default, or "slab").
const FONTS := {"sans": "res://branding/fonts/LiberationSans-Bold.ttf", "slab": "res://branding/fonts/AlfaSlabOne-Regular.ttf"}
static var _fonts := {}

## The two groups' lenses, one mesh each per model, built once
## (flash_meshes) and drawn with the cruisers' shared lens material; each
## vehicle says how lit its own are with an instance uniform.
static var _beacon_cache := {}
var _flash_groups: Array[MeshInstance3D] = []


func _init(the_car: Car) -> void:
	super(the_car, null)
	name = "EmergencyGear"


func is_police() -> bool:
	return false


func _ready() -> void:
	var shape := car.shape
	if not TrafficDensity.server:
		if _lens_mat == null:
			_lens_mat = ShaderMaterial.new()
			_lens_mat.shader = load("res://shaders/police_lens.gdshader")
		if not _beacon_cache.has(car.model_id):
			_beacon_cache[car.model_id] = flash_meshes(shape.get("beacons", []), _lens_mat)
		for g in 2:
			var mi := MeshInstance3D.new()
			mi.name = "Beacons%d" % g
			mi.mesh = _beacon_cache[car.model_id][g]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			_flash_groups.append(mi)
	# A light per group, over the middle of the roof, for the colour it
	# throws on the street.
	var glow: Array = shape.get("glow", ["#ff2010", "#f0f0ff"])
	var top := float(shape.get("height", 3.0))
	for i in 2:
		var l := OmniLight3D.new()
		l.light_color = Color.from_string(str(glow[i]), RED)
		l.omni_range = 13.0
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.position = Vector3((-0.6 if i == 0 else 0.6), top + 0.2, 0.0)
		l.visible = false
		add_child(l)
		_glow.append(l)
	for w: Dictionary in shape.get("words", []):
		_word(w)
	_siren = AudioStreamPlayer3D.new()
	_siren.stream = load("res://sounds/cars/shared/siren.ogg")
	if _siren.stream is AudioStreamOggVorbis:
		(_siren.stream as AudioStreamOggVorbis).loop = true
	_siren.volume_db = SIREN_DB
	_siren.pitch_scale = float(shape.get("siren_pitch", 1.0)) * randf_range(0.97, 1.03)
	_siren.unit_size = 14.0
	_siren.max_db = 6.0
	_siren.max_distance = 600.0
	_siren.position = Vector3(0, 1.0, float(shape["front_axle"]))
	add_child(_siren)
	_apply(0.0, 0.0)


func _apply(a: float, b: float) -> void:
	_shown_red = a
	_shown_blue = b
	var on := [a, b]
	for i in 2:
		var lit: float = on[i]
		if i < _flash_groups.size():
			_flash_groups[i].set_instance_shader_parameter("lit", lit)
		if i < _glow.size():
			_glow[i].light_energy = lit * 2.4
			_glow[i].visible = lit > 0.0 and _glow_allowed


## The beacons as two meshes, one per group: each lens an LED module (a
## bright LED panel in a dimmer bezel on every face that shows, in its own
## colour), the colours in the vertex colours for the shared lens shader.
static func flash_meshes(beacons: Array, mat: Material) -> Array:
	var kits := [MeshKit.new(), MeshKit.new()]
	for k: MeshKit in kits:
		k.use_color = true
	for bdef: Dictionary in beacons:
		var g := clampi(int(bdef.get("group", 0)), 0, 1)
		var col := Color.from_string(str(bdef.get("colour", "#ff2010")), RED)
		var p: Array = bdef["pos"]
		var sz: Array = bdef.get("size", [0.2, 0.08, 0.2])
		var c := Vector3(p[0], p[1], p[2])
		var h := Vector3(sz[0], sz[1], sz[2]) * 0.5
		var kit: MeshKit = kits[g]
		for n: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP]:
			var u := Vector3.UP.cross(n).normalized() if absf(n.y) < 0.5 else Vector3.RIGHT
			var v := n.cross(u).normalized() if absf(n.y) < 0.5 else Vector3.BACK
			var hu := absf(h.dot(u))
			var hv := absf(h.dot(v))
			var fc := c + n * absf(h.dot(n))
			if hu < 0.005 or hv < 0.005:
				continue
			CarBuilder._led_face(kit, fc, u, v, hu, hv, n, col)
	return [ModelLod.finish_kits([[kits[0], mat]]), ModelLod.finish_kits([[kits[1], mat]])]


static func lettering_font(which := "sans") -> Font:
	if not _fonts.has(which):
		var f := FontVariation.new()
		f.base_font = load(str(FONTS.get(which, FONTS["sans"]))) as Font
		f.spacing_glyph = 1 if which == "sans" else 0
		_fonts[which] = f
	return _fonts[which]


func _word(w: Dictionary) -> void:
	var l := Label3D.new()
	l.text = str(w["text"])
	_style(l, float(w.get("height", 0.2)), Color.from_string(str(w.get("colour", "#ffffff")), Color.WHITE))
	l.font = lettering_font(str(w.get("font", "sans")))
	l.font_size = 64
	if w.has("outline"):
		# Gold leaf's dark edge, or a white edge round a word on a stripe.
		l.outline_size = int(w.get("outline_size", 8))
		l.outline_modulate = Color.from_string(str(w["outline"]), Color.BLACK)
	var p: Array = w["pos"]
	l.position = Vector3(p[0], p[1], p[2])
	match str(w.get("face", "right")):
		"right":
			l.rotation.y = PI * 0.5
		"left":
			l.rotation.y = -PI * 0.5
		"back":
			l.rotation.y = 0.0
		"front":
			l.rotation.y = PI
		"up":
			# On the hood, reading from in front (and, mirrored, in a mirror).
			l.rotation = Vector3(-PI * 0.5, PI, 0.0)
	if w.has("normal"):
		# Laid on a sloping face: facing out along `normal`, upright along it.
		var nv: Array = w["normal"]
		var z := Vector3(nv[0], nv[1], nv[2]).normalized()
		var y := (Vector3.UP - z * z.dot(Vector3.UP)).normalized()
		l.basis = Basis(y.cross(z), y, z)
	if bool(w.get("mirror", false)):
		l.scale.x = -1.0
		l.double_sided = true
	WorldLod.limit(l, 0.4)
	add_child(l)

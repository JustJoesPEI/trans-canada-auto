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
## "colour", "mirror"}, Label3Ds like a cruiser's.
## shape["siren_pitch"]: the siren's pitch (the brigade's is lower).

## Each group's lens materials (one per colour in it).
var _groups: Array = [[], []]


func _init(the_car: Car) -> void:
	super(the_car, null)
	name = "EmergencyGear"


func is_police() -> bool:
	return false


func _ready() -> void:
	var shape := car.shape
	var mats := {}
	for bdef: Dictionary in shape.get("beacons", []):
		var g := clampi(int(bdef.get("group", 0)), 0, 1)
		var col := Color.from_string(str(bdef.get("colour", "#ff2010")), RED)
		var key := "%d_%s" % [g, col.to_html(false)]
		if not mats.has(key):
			var m := _lens_material(col)
			mats[key] = m
			(_groups[g] as Array).append(m)
		var lens := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz: Array = bdef.get("size", [0.2, 0.08, 0.2])
		bm.size = Vector3(sz[0], sz[1], sz[2])
		lens.mesh = bm
		lens.material_override = mats[key]
		var p: Array = bdef["pos"]
		lens.position = Vector3(p[0], p[1], p[2])
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		WorldLod.limit(lens, 0.3)
		add_child(lens)
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
	_siren.pitch_scale = float(shape.get("siren_pitch", 1.0))
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
		for m: StandardMaterial3D in _groups[i]:
			m.emission_energy_multiplier = 0.1 + lit * 2.6
		if i < _glow.size():
			_glow[i].light_energy = lit * 2.4
			_glow[i].visible = lit > 0.0


func _word(w: Dictionary) -> void:
	var l := Label3D.new()
	l.text = str(w["text"])
	_style(l, float(w.get("height", 0.2)), Color.from_string(str(w.get("colour", "#ffffff")), Color.WHITE))
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

class_name Materials
extends RefCounted
## One shared set of materials for the whole town, so thousands of pieces of
## geometry draw with a handful of materials.

static var _shared: Materials

var asphalt: StandardMaterial3D
var concrete: StandardMaterial3D
var lot_ground: StandardMaterial3D
var paint_yellow: StandardMaterial3D
var paint_white: StandardMaterial3D
var building_walls: ShaderMaterial
var building_roofs: ShaderMaterial

var _plain: Dictionary = {}


static func get_shared() -> Materials:
	if _shared == null:
		_shared = Materials.new()
	return _shared


func _init() -> void:
	asphalt = _noisy(Color(0.25, 0.25, 0.26), 0.92, 0.72, 11)
	concrete = _noisy(Color(0.66, 0.64, 0.6), 0.95, 0.85, 23)
	lot_ground = _noisy(Color(0.38, 0.44, 0.3), 1.0, 0.7, 37)
	paint_yellow = plain(Color(0.86, 0.69, 0.18), 0.7)
	paint_white = plain(Color(0.9, 0.9, 0.87), 0.7)
	building_walls = ShaderMaterial.new()
	building_walls.shader = load("res://shaders/building_wall.gdshader")
	building_roofs = ShaderMaterial.new()
	building_roofs.shader = load("res://shaders/building_roof.gdshader")


## A flat-coloured material, cached so equal colours share one material.
func plain(c: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), roughness, metallic]
	if _plain.has(key):
		return _plain[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	m.metallic = metallic
	_plain[key] = m
	return m


## A glowing material for lamps and signal lights.
func glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Colour with a gentle seamless noise so large flat areas don't look plastic.
## Street meshes use UV = metres * 0.25 and uv1_scale halves that, so the
## texture repeats every 8 m.
func _noisy(c: Color, roughness: float, low: float, noise_seed: int) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(low, low, low))
	ramp.set_color(1, Color(1, 1, 1))
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = tex
	m.roughness = roughness
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	return m

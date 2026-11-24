class_name Materials
extends RefCounted
## One shared set of materials for the whole town, so thousands of pieces of
## geometry draw with a handful of materials.

static var _shared: Materials

var asphalt: ShaderMaterial
var concrete: ShaderMaterial
var lot_ground: StandardMaterial3D
var grass: StandardMaterial3D
var parking: StandardMaterial3D
var pavers: ShaderMaterial
var path_brick: ShaderMaterial
var brick_road: ShaderMaterial
var paint_yellow: ShaderMaterial
var paint_white: ShaderMaterial
var paint_red: ShaderMaterial
var building_walls: ShaderMaterial
var building_roofs: ShaderMaterial

var _plain: Dictionary = {}
## The chunk builders' worker threads all ask plain() for materials at once.
var _plain_lock := Mutex.new()


static func get_shared() -> Materials:
	if _shared == null:
		_shared = Materials.new()
	return _shared


func _init() -> void:
	asphalt = ShaderMaterial.new()
	asphalt.shader = load("res://shaders/asphalt.gdshader")
	concrete = ShaderMaterial.new()
	concrete.shader = load("res://shaders/sidewalk.gdshader")
	# Lots without anything mapped: worn grass and gravel, not a lawn.
	lot_ground = _noisy(Color(0.46, 0.46, 0.38), 1.0, 0.68, 37)
	grass = _noisy(Color(0.33, 0.46, 0.24), 1.0, 0.72, 41)
	parking = _noisy(Color(0.31, 0.31, 0.32), 0.9, 0.75, 53)
	var paving := load("res://shaders/paving.gdshader") as Shader
	# Squares and plazas: grey-buff stone flags. Paths: weathered brick.
	pavers = ShaderMaterial.new()
	pavers.shader = paving
	pavers.set_shader_parameter("brick_color", Color(0.64, 0.61, 0.56))
	pavers.set_shader_parameter("joint_color", Color(0.5, 0.48, 0.45))
	pavers.set_shader_parameter("brick_length", 0.6)
	pavers.set_shader_parameter("brick_width", 0.4)
	path_brick = ShaderMaterial.new()
	path_brick.shader = paving
	path_brick.set_shader_parameter("brick_color", Color(0.55, 0.4, 0.35))
	brick_road = ShaderMaterial.new()
	brick_road.shader = paving
	brick_road.set_shader_parameter("brick_color", Color(0.5, 0.36, 0.32))
	brick_road.set_shader_parameter("brick_length", 0.24)
	brick_road.set_shader_parameter("brick_width", 0.12)
	var paint := load("res://shaders/road_paint.gdshader") as Shader
	paint_yellow = ShaderMaterial.new()
	paint_yellow.shader = paint
	paint_yellow.set_shader_parameter("paint_color", Color(0.86, 0.66, 0.16))
	paint_white = ShaderMaterial.new()
	paint_white.shader = paint
	paint_white.set_shader_parameter("paint_color", Color(0.88, 0.88, 0.85))
	paint_red = ShaderMaterial.new()
	paint_red.shader = paint
	paint_red.set_shader_parameter("paint_color", Color(0.68, 0.14, 0.12))
	building_walls = ShaderMaterial.new()
	building_walls.shader = load("res://shaders/building_wall.gdshader")
	if BuildingGenerator.facade_relief:
		building_walls.set_shader_parameter("use_photo", true)
		building_walls.set_shader_parameter("wall_albedo", load("res://textures/facade/walls_albedo.jpg"))
		building_walls.set_shader_parameter("wall_hr", load("res://textures/facade/walls_height_rough.jpg"))
	building_roofs = ShaderMaterial.new()
	building_roofs.shader = load("res://shaders/building_roof.gdshader")


## A flat-coloured material, cached so equal colours share one material.
## Safe to call from the chunk builders' worker threads.
func plain(c: Color, roughness := 0.8, metallic := 0.0) -> StandardMaterial3D:
	var key := "%s/%.2f/%.2f" % [c.to_html(), roughness, metallic]
	_plain_lock.lock()
	var m: StandardMaterial3D = _plain.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = roughness
		m.metallic = metallic
		_plain[key] = m
	_plain_lock.unlock()
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

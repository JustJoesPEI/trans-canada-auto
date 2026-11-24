class_name PaintTexture
extends RefCounted
## The splat shapes: four of them in a 2 x 2 atlas, one grey channel (how
## much paint), made once in code and shared by the world splats, the car
## and body paint and the windscreen smear. 256 x 256 in L8 with mipmaps is
## 87 KB on the graphics card, about what one compressed 512 px photo costs,
## so it's left uncompressed (a compressed single channel would cost the
## same and blur the edges). docs/world_art.md W8: mipmapped, small.
##
## Each shape is a lumpy blob with a few droplets thrown out round it and,
## on two of them, a couple of streaks where the ball hit at an angle. The
## edge is soft over a couple of pixels so the splat reads clean at any
## distance without aliasing.

const CELL := 128
const SHAPES := 4

static var _texture: ImageTexture


static func texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(CELL * 2, CELL * 2, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	for s in SHAPES:
		rng.seed = 7919 * (s + 3)
		_draw_shape(img, (s % 2) * CELL, (s / 2) * CELL, rng, s)
	img.generate_mipmaps()
	_texture = ImageTexture.create_from_image(img)
	return _texture


## Where shape `index` sits in the atlas, as (u offset, v offset); each cell
## is half the texture across.
static func cell_offset(index: int) -> Vector2:
	index = posmod(index, SHAPES)
	return Vector2(float(index % 2) * 0.5, float(index / 2) * 0.5)


static func _draw_shape(img: Image, ox: int, oy: int, rng: RandomNumberGenerator, s: int) -> void:
	# The main blob: a radius that wobbles round the circle (a few sine
	# lobes of random phase).
	var lobes: Array[Vector3] = [] # (frequency, amplitude, phase)
	for i in 5:
		lobes.append(Vector3(float(rng.randi_range(2, 9)), rng.randf_range(0.03, 0.09), rng.randf() * TAU))
	var base := 0.52 if s != 3 else 0.45
	# Droplets: (centre x, centre y, radius) in the cell's -1..1 space.
	var drops: Array[Vector3] = []
	for i in rng.randi_range(5, 9):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.62, 0.92)
		drops.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.025, 0.07)))
	# Streaks: thin lobes thrown out one way (an angled hit).
	var streaks: Array[Vector2] = [] # (angle, length)
	if s == 1 or s == 3:
		var dir := rng.randf() * TAU
		for i in 3:
			streaks.append(Vector2(dir + rng.randf_range(-0.35, 0.35), rng.randf_range(0.75, 0.95)))
	for y in CELL:
		for x in CELL:
			var p := Vector2((x + 0.5) / CELL * 2.0 - 1.0, (y + 0.5) / CELL * 2.0 - 1.0)
			var r := p.length()
			var a := atan2(p.y, p.x)
			var edge := base
			for l in lobes:
				edge += sin(a * l.x + l.z) * l.y
			# Distance outside the shape, in cell units; negative inside.
			var d := r - edge
			for st in streaks:
				var along := p.dot(Vector2(cos(st.x), sin(st.x)))
				var across := absf(p.cross(Vector2(cos(st.x), sin(st.x))))
				if along > 0.0 and along < st.y:
					var w := 0.06 * (1.0 - along / st.y)
					d = minf(d, across - w)
			for dr in drops:
				d = minf(d, Vector2(dr.x, dr.y).distance_to(p) - dr.z)
			# Keep clear of the cell's edge so mipmaps don't bleed into the next shape.
			d = maxf(d, r - 0.97)
			var v := clampf(0.5 - d * CELL * 0.35, 0.0, 1.0)
			img.set_pixel(ox + x, oy + y, Color(v, v, v))

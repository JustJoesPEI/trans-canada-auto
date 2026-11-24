class_name CarWashModel
extends RefCounted
## The drive-through car wash bay: two long walls, a roof, a blue fascia
## with soap bubbles over each open end, two tall spinning-brush rollers and
## an overhead brush inside, yellow guide rails on the floor and a striped
## sign on the roof. One vertex-coloured surface on a shared material, built
## once and drawn as a placed prop ("prop=car_wash", PlacedProps), which
## gives it its automatic LODs, its draw distance and its collision (the two
## walls). Its "direction" is the way cars drive through: in at the back
## (+Z) and out the front (-Z).
##
## The game side (driving through clears your paint and, unseen, your
## wanted level) is CarWashes; the sizes here are what it measures against.

## Inside the bay, from the middle: half the width between the walls, and
## half the length (m). A car this far in is "in the wash".
const HALF_WIDTH := 2.5
const HALF_LENGTH := 7.0
const WALL := 0.3
const WALL_HEIGHT := 4.0
## Clearance under the fascia at each end (m).
const CLEAR := 3.3

const BLUE := Color(0.12, 0.42, 0.78)
const WHITE := Color(0.95, 0.95, 0.93)
const WALL_COLOUR := Color(0.86, 0.84, 0.78)
const GLASS := Color(0.16, 0.22, 0.28)
const BRUSH := Color(0.2, 0.55, 0.95)
const RAIL := Color(0.95, 0.78, 0.08)
const TRIM := Color(0.25, 0.26, 0.28)


## The mesh (front faces -Z, standing on y = 0). PlacedProps finishes it
## (indexed, automatic LODs) with the rest of its kinds.
static func mesh() -> ArrayMesh:
	var kit := MeshKit.new()
	kit.use_color = true
	var outer := HALF_WIDTH + WALL
	# The walls, with a dark band of windows along the outside of each.
	_col(kit, WALL_COLOUR)
	for s: float in [-1.0, 1.0]:
		_box(kit, Vector3(s * HALF_WIDTH if s > 0.0 else -outer, 0.0, -HALF_LENGTH), Vector3(outer if s > 0.0 else -HALF_WIDTH, WALL_HEIGHT, HALF_LENGTH))
	_col(kit, GLASS)
	for s: float in [-1.0, 1.0]:
		var x := s * (outer + 0.01)
		var n := Vector3(s, 0.0, 0.0)
		for k in 4:
			var z0 := -HALF_LENGTH + 0.8 + k * 3.25
			var a := Vector3(x, 2.0, z0)
			var b := Vector3(x, 2.0, z0 + 2.6)
			var c := Vector3(x, 2.9, z0 + 2.6)
			var d := Vector3(x, 2.9, z0)
			kit.quad(a, b, c, d, n)
	# The roof, a little proud of the walls all round.
	_col(kit, TRIM)
	_box(kit, Vector3(-outer - 0.2, WALL_HEIGHT, -HALF_LENGTH - 0.2), Vector3(outer + 0.2, WALL_HEIGHT + 0.25, HALF_LENGTH + 0.2))
	# A blue fascia over each open end, with soap bubbles on its face.
	for s: float in [-1.0, 1.0]:
		_col(kit, BLUE)
		_box(kit, Vector3(-HALF_WIDTH, CLEAR, s * HALF_LENGTH - 0.15), Vector3(HALF_WIDTH, WALL_HEIGHT, s * HALF_LENGTH + 0.15))
		_col(kit, WHITE)
		_box(kit, Vector3(-HALF_WIDTH, CLEAR, s * HALF_LENGTH - 0.17), Vector3(HALF_WIDTH, CLEAR + 0.1, s * HALF_LENGTH + 0.17))
		for b: Vector3 in [Vector3(-1.7, 3.75, 0.2), Vector3(-1.1, 3.55, 0.14), Vector3(-0.5, 3.8, 0.12),
				Vector3(0.4, 3.6, 0.18), Vector3(1.2, 3.78, 0.13), Vector3(1.8, 3.55, 0.16)]:
			_disc(kit, Vector3(b.x, b.y, s * (HALF_LENGTH + 0.16)), b.z, Vector3(0.0, 0.0, s))
	# The sign on the roof over the way in: blue, white and red stripes.
	for k in 3:
		_col(kit, [BLUE, WHITE, Color(0.85, 0.15, 0.12)][k])
		var y0 := WALL_HEIGHT + 0.25 + k * 0.4
		_box(kit, Vector3(-1.8, y0, HALF_LENGTH - 0.4), Vector3(1.8, y0 + 0.4, HALF_LENGTH - 0.1))
	_col(kit, TRIM)
	for x: float in [-1.2, 1.2]:
		_box(kit, Vector3(x - 0.05, WALL_HEIGHT + 0.25, HALF_LENGTH - 0.6), Vector3(x + 0.05, WALL_HEIGHT + 1.2, HALF_LENGTH - 0.5))
	# Inside: two tall brush rollers by the walls and one overhead.
	_col(kit, BRUSH)
	for x: float in [-HALF_WIDTH + 0.4, HALF_WIDTH - 0.4]:
		var at := Vector3(x, 0.0, -1.5)
		var from := kit.verts.size()
		StreetProps._lathe(kit, [[0.0, 0.25], [0.32, 0.35], [0.34, 2.4], [0.3, 2.6], [0.0, 2.6]], 10)
		var moved := kit.verts
		for i in range(from, moved.size()):
			moved[i] += at
		kit.verts = moved
	StreetProps._bar(kit, Vector3(-HALF_WIDTH + 0.1, 2.75, 1.5), Vector3(HALF_WIDTH - 0.1, 2.75, 1.5), 0.3)
	_col(kit, TRIM)
	for x: float in [-HALF_WIDTH + 0.4, HALF_WIDTH - 0.4]:
		_box(kit, Vector3(x - 0.06, 2.6, -1.56), Vector3(x + 0.06, WALL_HEIGHT, -1.44))
	# Yellow guide rails along the floor.
	_col(kit, RAIL)
	for x: float in [-1.25, 1.25]:
		_box(kit, Vector3(x - 0.08, 0.0, -HALF_LENGTH + 0.5), Vector3(x + 0.08, 0.12, HALF_LENGTH - 0.5))
	return kit.commit(null, Materials.get_shared().vertex_colour(0.6))


## The collision boxes PlacedProps gives it: [half size, centre] per wall.
static func walls() -> Array:
	var half := Vector3(WALL * 0.5, WALL_HEIGHT * 0.5, HALF_LENGTH)
	return [[half, Vector3(-HALF_WIDTH - WALL * 0.5, WALL_HEIGHT * 0.5, 0.0)],
		[half, Vector3(HALF_WIDTH + WALL * 0.5, WALL_HEIGHT * 0.5, 0.0)]]


static func _col(kit: MeshKit, c: Color) -> void:
	kit.color = c.srgb_to_linear()


static func _box(kit: MeshKit, lo: Vector3, hi: Vector3) -> void:
	StreetClutter._cube(kit, (lo + hi) * 0.5, (hi - lo) * 0.5)


## A flat round dot (a soap bubble) facing n.
static func _disc(kit: MeshKit, c: Vector3, r: float, n: Vector3) -> void:
	var u := Vector3.RIGHT * r
	var v := Vector3.UP * r
	var segs := 8
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var p0 := c + u * cos(a0) + v * sin(a0)
		var p1 := c + u * cos(a1) + v * sin(a1)
		kit.tri(c, p0, p1, n)

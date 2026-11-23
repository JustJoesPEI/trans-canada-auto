class_name PlacedSigns
extends RefCounted
## Signs placed in the map editor: points of type "sign=<kind>" in a chunk.
## "direction" is the compass bearing the sign's face looks toward (where
## the drivers who read it come from), "text" what it says ("|" or a new
## line starts another line), and for the ones you design yourself
## "colour", "text_colour", "width", "height" and "lift"; a billboard can
## show advertising artwork instead, named by "ad" (see Ads), and takes
## turns with others: the rest of its brand's, or the "ads" list ("a|b|c"). Built by
## StreetProps in full-detail chunks; posts are solid.
##
## Road signs: speed_limit, stop, yield, no_parking, one_way, do_not_enter,
## school_zone, pedestrian, parking, street_name, custom.
## Business signs: pylon (a tall pole sign), monument (a low sign on a
## base), wall_sign (flat on a wall, no post), billboard.

const KINDS := ["speed_limit", "stop", "yield", "no_parking", "one_way", "do_not_enter",
	"school_zone", "pedestrian", "parking", "street_name", "custom",
	"pylon", "monument", "wall_sign", "billboard"]
## Default text for the kinds that have some.
const DEFAULT_TEXT := {"speed_limit": "50", "stop": "STOP", "street_name": "Street Name", "custom": "SIGN",
	"pylon": "BUSINESS", "monument": "BUSINESS", "wall_sign": "BUSINESS", "billboard": "YOUR AD HERE"}
## Signs are drawn this close (metres).
const DRAW_DISTANCE := 260.0

const WHITE := Color(0.95, 0.95, 0.93)
const BLACK := Color(0.05, 0.05, 0.05)
const RED := Color(0.75, 0.08, 0.07)
const FLUO := Color(0.72, 0.9, 0.1) ## fluorescent yellow-green school and crossing signs
const BLUE := Color(0.08, 0.27, 0.6)
const GREEN := Color(0.08, 0.36, 0.2)
const STEEL := Color(0.55, 0.57, 0.58)

static var _materials: Dictionary = {}
static var _materials_lock := Mutex.new()
static var _xwalk_mat: StandardMaterial3D


## Shared things made on the main thread before any chunk is built
## (called from StreetProps.prepare).
static func prepare() -> void:
	if _xwalk_mat == null:
		_xwalk_mat = StreetProps._sign_material("res://textures/signs/crosswalk_side.png")

var props: StreetProps


func _init(owner: StreetProps) -> void:
	props = owner


func build(root: Node3D) -> void:
	for p in props.chunk.points:
		if p.type.begins_with("sign="):
			var kind := p.type.substr(5)
			if kind in KINDS:
				root.add_child(_sign(kind, p))


## One material per colour, shared. Chunks are built on several threads at
## once, so the cache is locked.
static func _mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	_materials_lock.lock()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.55
		_materials[key] = m
	var out: StandardMaterial3D = _materials[key]
	_materials_lock.unlock()
	return out


func _sign(kind: String, p: StreetData.MapPoint) -> Node3D:
	var t := p.tags
	var text := str(t.get("text", DEFAULT_TEXT.get(kind, ""))).replace(" | ", "\n").replace("|", "\n").replace("\\n", "\n")
	var bg := Color.from_string(str(t.get("colour", "")), Color(0, 0, 0, 0))
	var fg := Color.from_string(str(t.get("text_colour", "")), Color(0, 0, 0, 0))
	var d := deg_to_rad(str(t.get("direction", "0")).to_float())
	var holder := Node3D.new()
	holder.name = "Sign_" + kind
	var lift := str(t.get("lift", "0")).to_float()
	holder.position = props.terrain.at(p.pos, lift)
	holder.rotation.y = StreetProps.yaw_facing(Vector2(sin(d), -cos(d)))
	var w := str(t.get("width", "0")).to_float()
	var h := str(t.get("height", "0")).to_float()
	match kind:
		"speed_limit":
			_post(holder, 2.6, 0.04)
			_box(holder, Vector3(0.62, 0.78, 0.02), Vector3(0, 2.2, 0.05), BLACK)
			_box(holder, Vector3(0.58, 0.74, 0.03), Vector3(0, 2.2, 0.05), WHITE)
			_text(holder, "MAXIMUM", Vector3(0, 2.45, 0.07), Vector2(0.5, 0.14), BLACK, false)
			_text(holder, text, Vector3(0, 2.15, 0.07), Vector2(0.5, 0.42), BLACK, false)
		"stop":
			_post(holder, 2.4, 0.04)
			_disc(holder, 0.38, 8, Vector3(0, 2.15, 0.05), RED, PI / 8.0)
			_text(holder, text, Vector3(0, 2.15, 0.075), Vector2(0.55, 0.22), WHITE, false)
		"yield":
			_post(holder, 2.3, 0.04)
			_disc(holder, 0.5, 3, Vector3(0, 2.05, 0.05), RED, 0.0)
			_disc(holder, 0.3, 3, Vector3(0, 2.07, 0.07), WHITE, 0.0)
		"no_parking":
			_post(holder, 2.4, 0.04)
			_box(holder, Vector3(0.45, 0.6, 0.03), Vector3(0, 2.1, 0.05), WHITE)
			_ring(holder, 0.19, Vector3(0, 2.15, 0.07), RED)
			_text(holder, "P", Vector3(0, 2.15, 0.072), Vector2(0.25, 0.25), BLACK, false)
			_bar(holder, Vector3(0, 2.15, 0.08), 0.38, 0.035, -PI / 4.0, RED)
			_text(holder, text if text != "" else "", Vector3(0, 1.88, 0.07), Vector2(0.4, 0.1), RED, false)
		"one_way":
			_post(holder, 2.8, 0.04)
			_box(holder, Vector3(0.9, 0.3, 0.02), Vector3(0, 2.5, 0.05), BLACK)
			# A white arrow pointing right (as seen by the driver).
			_bar(holder, Vector3(-0.08, 2.5, 0.065), 0.55, 0.07, 0.0, WHITE)
			_disc(holder, 0.12, 3, Vector3(0.27, 2.5, 0.065), WHITE, PI / 2.0)
			_text(holder, "ONE WAY", Vector3(-0.04, 2.5, 0.08), Vector2(0.4, 0.075), BLACK, false)
		"do_not_enter":
			_post(holder, 2.4, 0.04)
			_disc(holder, 0.32, 24, Vector3(0, 2.1, 0.05), RED, 0.0)
			_bar(holder, Vector3(0, 2.1, 0.07), 0.46, 0.1, 0.0, WHITE)
		"school_zone":
			_post(holder, 2.6, 0.04)
			_disc(holder, 0.42, 5, Vector3(0, 2.15, 0.05), FLUO, PI)
			_text(holder, text if text != "" else "SCHOOL", Vector3(0, 2.1, 0.08), Vector2(0.55, 0.15), BLACK, false)
		"pedestrian":
			_post(holder, 2.6, 0.04)
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.6, 0.6)
			qm.material = _xwalk_mat
			q.mesh = qm
			q.position = Vector3(0, 2.2, 0.06)
			holder.add_child(q)
		"parking":
			_post(holder, 2.4, 0.04)
			_box(holder, Vector3(0.45, 0.6, 0.03), Vector3(0, 2.1, 0.05), BLUE)
			_text(holder, text if text != "" else "P", Vector3(0, 2.1, 0.07), Vector2(0.35, 0.4), WHITE, false)
		"street_name":
			_post(holder, 2.9, 0.045)
			_box(holder, Vector3(1.6, 0.3, 0.025), Vector3(0.75, 2.7, 0), GREEN)
			_text(holder, text, Vector3(0.75, 2.7, 0.016), Vector2(1.45, 0.2), WHITE, true, 0.016)
		"custom":
			var cw := w if w > 0.0 else 0.9
			var ch := h if h > 0.0 else 0.6
			var top := 2.0 + ch
			_post(holder, top, 0.045)
			_box(holder, Vector3(cw, ch, 0.03), Vector3(0, top - ch * 0.5, 0.05), bg if bg.a > 0.0 else WHITE)
			_text(holder, text, Vector3(0, top - ch * 0.5, 0.07), Vector2(cw * 0.9, ch * 0.8), fg if fg.a > 0.0 else BLACK, false)
		"pylon":
			var ph := h if h > 0.0 else 7.0
			var pw := w if w > 0.0 else 2.6
			var cab := pw * 0.6
			_post(holder, ph - cab, 0.2, STEEL, true)
			_box(holder, Vector3(pw, cab, 0.45), Vector3(0, ph - cab * 0.5, 0), bg if bg.a > 0.0 else RED)
			_text(holder, text, Vector3(0, ph - cab * 0.5, 0.23), Vector2(pw * 0.88, cab * 0.75), fg if fg.a > 0.0 else WHITE, true, 0.23)
		"monument":
			var mw := w if w > 0.0 else 2.6
			var mh := h if h > 0.0 else 1.3
			_box(holder, Vector3(mw + 0.3, 0.35, 0.7), Vector3(0, 0.1, 0), Color(0.55, 0.52, 0.48), true)
			_box(holder, Vector3(mw, mh, 0.4), Vector3(0, 0.27 + mh * 0.5, 0), bg if bg.a > 0.0 else Color(0.25, 0.27, 0.3), true)
			_text(holder, text, Vector3(0, 0.27 + mh * 0.5, 0.21), Vector2(mw * 0.88, mh * 0.75), fg if fg.a > 0.0 else WHITE, true, 0.21)
		"wall_sign":
			var ww := w if w > 0.0 else 3.0
			var wh := h if h > 0.0 else 0.8
			var y := 3.6 if lift <= 0.0 else 0.0
			_box(holder, Vector3(ww, wh, 0.15), Vector3(0, y, 0.08), bg if bg.a > 0.0 else Color(0.12, 0.12, 0.14))
			_text(holder, text, Vector3(0, y, 0.165), Vector2(ww * 0.92, wh * 0.78), fg if fg.a > 0.0 else WHITE, false)
		"billboard":
			# With "ad" naming artwork in textures/ads/ (see Ads), the face shows
			# it, sized to its 3.2 : 1 shape; otherwise text on a colour.
			var ad := str(t.get("ad", ""))
			var has_ad := Ads.has(ad)
			var bw := w if w > 0.0 else (9.6 if has_ad else 6.0)
			var bh := h if h > 0.0 else (bw / 3.2 if has_ad else 3.0)
			for x: float in [-bw * 0.3, bw * 0.3]:
				_post(holder, 4.0, 0.18, STEEL, true, Vector3(x, 0, -0.2))
			_box(holder, Vector3(bw + 0.2, bh + 0.2, 0.25), Vector3(0, 4.0 + bh * 0.5, 0), Color(0.3, 0.3, 0.3))
			if has_ad:
				# Boards take turns: a brand's go round its billboards, the
				# tourism board's round the list in their "ads" tag.
				var turns := Ads.rotation(ad, str(t.get("ads", "")))
				var face: MeshInstance3D
				if turns.size() > 1:
					face = Ads.rotating_panel(turns, Vector2(bw, bh), fposmod(p.pos.x * 0.0131 + p.pos.y * 0.0077, 1.0))
				else:
					face = Ads.panel(ad, Vector2(bw, bh))
				face.position = Vector3(0, 4.0 + bh * 0.5, 0.13)
				holder.add_child(face)
			else:
				_box(holder, Vector3(bw, bh, 0.27), Vector3(0, 4.0 + bh * 0.5, 0), bg if bg.a > 0.0 else WHITE)
				_text(holder, text, Vector3(0, 4.0 + bh * 0.5, 0.14), Vector2(bw * 0.9, bh * 0.75), fg if fg.a > 0.0 else BLACK, true, 0.14)
	return holder


## A pole from the ground to `top`, solid.
func _post(holder: Node3D, top: float, radius: float, colour := STEEL, square := false, at := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	if square:
		var b := BoxMesh.new()
		b.size = Vector3(radius * 2.0, top + 0.3, radius * 2.0)
		b.material = _mat(colour)
		mi.mesh = b
	else:
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = top + 0.3
		c.radial_segments = 8
		c.material = _mat(colour)
		mi.mesh = c
	mi.position = at + Vector3(0, (top - 0.3) * 0.5, 0)
	mi.visibility_range_end = DRAW_DISTANCE
	holder.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.SOLID
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(radius * 2.0, 0.12), top, maxf(radius * 2.0, 0.12))
	cs.shape = shape
	cs.position = at + Vector3(0, top * 0.5, 0)
	body.add_child(cs)
	holder.add_child(body)


func _box(holder: Node3D, size: Vector3, at: Vector3, colour: Color, solid := false) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(colour)
	mi.mesh = b
	mi.position = at
	mi.visibility_range_end = DRAW_DISTANCE
	holder.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.SOLID
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = at
		body.add_child(cs)
		holder.add_child(body)


## A flat polygon (octagon, triangle, circle...) facing +Z, with a grey
## back. With spin 0 a corner points straight down; spin turns it
## anticlockwise as seen from the front.
func _disc(holder: Node3D, radius: float, sides: int, at: Vector3, colour: Color, spin: float) -> void:
	var front := MeshKit.new()
	var back := MeshKit.new()
	for k in sides:
		var a0 := spin - PI / 2.0 + TAU * k / sides
		var a1 := spin - PI / 2.0 + TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0), sin(a0), 0.0) * radius
		var p1 := Vector3(cos(a1), sin(a1), 0.0) * radius
		front.tri(Vector3(0, 0, 0.01), p0 + Vector3(0, 0, 0.01), p1 + Vector3(0, 0, 0.01), Vector3.BACK)
		back.tri(Vector3(0, 0, -0.01), p0 - Vector3(0, 0, 0.01), p1 - Vector3(0, 0, 0.01), Vector3.FORWARD)
	var mesh := front.commit(null, _mat(colour))
	back.commit(mesh, _mat(STEEL))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.visibility_range_end = DRAW_DISTANCE
	holder.add_child(mi)


## A circle outline: a ring of short bars.
func _ring(holder: Node3D, radius: float, at: Vector3, colour: Color) -> void:
	for k in 16:
		var a := TAU * (k + 0.5) / 16.0
		_bar(holder, at + Vector3(cos(a), sin(a), 0) * radius, TAU * radius / 16.0 + 0.01, 0.035, a + PI / 2.0, colour)


## A flat bar facing +Z, `length` long, turned `angle` in the sign's plane.
func _bar(holder: Node3D, at: Vector3, length: float, thick: float, angle: float, colour: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(length, thick, 0.01)
	b.material = _mat(colour)
	mi.mesh = b
	mi.basis = Basis(Vector3.BACK, angle)
	mi.position = at
	mi.visibility_range_end = DRAW_DISTANCE
	holder.add_child(mi)


## Text sized to fit `box` (width, height in metres), on the front (and
## the back too when `both`, `back` metres behind the middle).
func _text(holder: Node3D, text: String, at: Vector3, box: Vector2, colour: Color, both: bool, back := 0.0) -> void:
	if text.strip_edges() == "":
		return
	var lines := text.split("\n")
	var longest := 1
	for l in lines:
		longest = maxi(longest, l.length())
	var font := 64
	# Roughly 0.6 em per character and 1.2 em per line.
	var px := minf(box.x / (longest * font * 0.62), box.y / (lines.size() * font * 1.15))
	for side: float in ([1.0, -1.0] if both else [1.0]):
		var label := Label3D.new()
		label.text = text
		label.font_size = font
		label.pixel_size = px
		label.outline_size = 0
		label.modulate = colour
		label.double_sided = false
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.visibility_range_end = DRAW_DISTANCE
		if side > 0.0:
			label.position = at
		else:
			label.position = Vector3(at.x, at.y, at.z - 2.0 * back - 0.002)
			label.rotation.y = PI
		holder.add_child(label)

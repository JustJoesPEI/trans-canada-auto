class_name KinbookArt
extends RefCounted
## Kinbook's pictures, drawn in code (no image files): profile pictures
## (initials in a circle, the grey head for Anonymous), the reaction
## icons, and the photos people put up with their posts, the way a phone
## photo on Kinbook looks: a bit off-centre, sometimes a thumb in it.
##
## pic_for(post) picks a photo from what the post's about (a cat, the
## pothole, the cones, a truck...), or "" for a post that's only words.
## A post can name its own with "pic" ("" for none). Each picture is a
## Control that draws itself at whatever size it's given.

const BOLD_FONT := "res://branding/fonts/LiberationSans-Bold.ttf"

## Profile picture colours (picked from the name, so a person keeps theirs).
const AVATAR_COLOURS := [Color("#e4572e"), Color("#3a86ff"), Color("#8338ec"), Color("#2a9d8f"), Color("#f4a261"),
	Color("#d62828"), Color("#118ab2"), Color("#6a994e"), Color("#bc4b51"), Color("#5e548e"), Color("#e76f51"), Color("#457b9d")]
## Backgrounds for a short post with no photo (the big words on colour).
const BACKDROPS := [[Color("#c0247a"), Color("#f0605d")], [Color("#5b2bb5"), Color("#2f80ed")], [Color("#0f766e"), Color("#22c1c3")],
	[Color("#d9480f"), Color("#f59f00")], [Color("#1f2937"), Color("#4b5563")]]

## What a photo's about, from the words in the post: the first that
## matches. [picture, regex].
const SUBJECTS := [
	["pothole", "\\b(pothole|bernard)\\b"],
	["cones", "\\bcones?\\b"],
	["cat", "\\b(cats?|gary|mittens)\\b"],
	["dog", "\\bdog\\b"],
	["blob", "\\b(goat|chicken|rabbit)\\b"],
	["casserole", "\\bcasserole\\b"],
	["air_fryer", "\\bair fryer\\b"],
	["cheese", "\\bcheese\\b"],
	["fish", "\\b(fish|halibut|trout)\\b"],
	["boat", "\\bboat\\b"],
	["bingo", "\\b(bingo|dauber)\\b"],
	["sign", "\\blawn sign\\b"],
	["church", "\\bchurch\\b"],
	["sink", "\\bsink\\b"],
	["deck", "\\bdeck\\b"],
	["lights", "\\b(police cars|cop cars|cruiser|fire truck|sirens|boo-boo bus|wee-woo brigade)\\b"],
	["truck", "\\b(truck|halfton|winch)\\b"],
]

## Every photo there's a drawing for.
const PHOTOS := ["pothole", "cones", "cat", "dog", "blob", "casserole", "air_fryer", "cheese", "fish", "boat", "bingo",
	"sign", "church", "sink", "deck", "lights", "truck", "chase", "jar"]

static var _bold: Font
static var _res := {}


static func bold_font() -> Font:
	if _bold == null:
		_bold = load(BOLD_FONT) as Font
	return _bold


static func _font() -> Font:
	return ThemeDB.fallback_font


## The photo for a post, or "" for words only.
static func pic_for(post: Dictionary) -> String:
	if post.has("pic"):
		return str(post["pic"])
	if str(post.get("by", "")).begins_with("Dale S."):
		return "sign"
	var text := (str(post.get("title", "")) + " " + str(post.get("text", ""))).to_lower()
	for s: Array in SUBJECTS:
		if not _res.has(s[0]):
			var re := RegEx.new()
			re.compile(s[1])
			_res[s[0]] = re
		if (_res[s[0]] as RegEx).search(text) != null:
			return str(s[0])
	return "jar" if bool(post.get("chipin", false)) or post.has("raised") else ""


## A number that stays the same for the same words (picks colours and
## which way a photo's off).
static func seed_of(text: String) -> int:
	return absi(hash(text))


# --- profile pictures -------------------------------------------------------------------------

static func initials(who: String) -> String:
	var parts := who.replace("(", "").replace(")", "").replace("'s", "").split(" ", false)
	var out := ""
	for p: String in parts:
		if out.length() >= 2:
			break
		if p.length() > 0 and p[0] == p[0].to_upper() and p[0] != p[0].to_lower():
			out += p[0]
	return out if out != "" else who.left(1).to_upper()


## A round profile picture `d` px across. "Anonymous" (and "") get the
## grey head; `square` is a group's or a page's (rounded square), and
## `label` is what's on it instead of the initials.
static func avatar(who: String, d: float, square := false, colour := Color(0, 0, 0, 0), label := "") -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d, d)
	c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var anon := who == "" or who == "Anonymous" or who == "Anonymous member"
	var col: Color = colour if colour.a > 0.0 else AVATAR_COLOURS[seed_of(who) % AVATAR_COLOURS.size()]
	if who.begins_with("Dale S."):
		col = Color("#f77f00")
	var text := label if label != "" else initials(who)
	c.draw.connect(func() -> void:
		var r := d * 0.5
		var mid := Vector2(r, r)
		if anon:
			c.draw_circle(mid, r, Color("#c9ccd1"))
			c.draw_circle(mid + Vector2(0, -r * 0.18), r * 0.36, Color("#f0f2f5"))
			_ellipse(c, mid + Vector2(0, r * 0.78), Vector2(r * 0.68, r * 0.5), Color("#f0f2f5"))
			return
		if square:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col
			sb.set_corner_radius_all(int(d * 0.22))
			sb.anti_aliasing = true
			c.draw_style_box(sb, Rect2(Vector2.ZERO, Vector2(d, d)))
		else:
			c.draw_circle(mid, r, col)
		var fs := int(d * (0.42 if text.length() < 2 else 0.36 if text.length() == 2 else 0.3))
		var f := bold_font()
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(f, Vector2(r - w * 0.5, r + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	return c


## The reaction icons in front of the like count: two or three of like,
## love, haha and angry, overlapping.
static func reactions(kinds: Array, d: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(d + (kinds.size() - 1) * d * 0.72, d)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func() -> void:
		for i in range(kinds.size() - 1, -1, -1):
			_reaction(c, str(kinds[i]), Vector2(d * 0.5 + i * d * 0.72, d * 0.5), d * 0.5))
	return c


static func _reaction(c: Control, kind: String, at: Vector2, r: float) -> void:
	c.draw_circle(at, r + 1.5, Color.WHITE)
	match kind:
		"love":
			c.draw_circle(at, r, Color("#f33e58"))
			c.draw_circle(at + Vector2(-r * 0.24, -r * 0.12), r * 0.27, Color.WHITE)
			c.draw_circle(at + Vector2(r * 0.24, -r * 0.12), r * 0.27, Color.WHITE)
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.5, -r * 0.02), at + Vector2(r * 0.5, -r * 0.02), at + Vector2(0, r * 0.52)]), Color.WHITE)
		"haha", "angry":
			var angry := kind == "angry"
			c.draw_circle(at, r, Color("#e9710f") if angry else Color("#f7b125"))
			var eye := Color("#3b2314")
			if angry:
				c.draw_line(at + Vector2(-r * 0.55, -r * 0.35), at + Vector2(-r * 0.12, -r * 0.18), eye, maxf(1.0, r * 0.14))
				c.draw_line(at + Vector2(r * 0.55, -r * 0.35), at + Vector2(r * 0.12, -r * 0.18), eye, maxf(1.0, r * 0.14))
				c.draw_arc(at + Vector2(0, r * 0.55), r * 0.32, PI * 1.15, PI * 1.85, 8, eye, maxf(1.0, r * 0.14))
			else:
				c.draw_arc(at + Vector2(-r * 0.32, -r * 0.1), r * 0.16, PI, TAU, 6, eye, maxf(1.0, r * 0.13))
				c.draw_arc(at + Vector2(r * 0.32, -r * 0.1), r * 0.16, PI, TAU, 6, eye, maxf(1.0, r * 0.13))
				c.draw_colored_polygon(_arc_pts(at + Vector2(0, r * 0.12), r * 0.48, 0.0, PI, 10), eye)
		_:
			c.draw_circle(at, r, Color("#1b74e4"))
			# The thumb: a fist and a thumb up.
			c.draw_rect(Rect2(at + Vector2(-r * 0.5, -r * 0.08), Vector2(r * 0.22, r * 0.55)), Color.WHITE)
			var fist := StyleBoxFlat.new()
			fist.bg_color = Color.WHITE
			fist.set_corner_radius_all(int(maxf(1.0, r * 0.15)))
			c.draw_style_box(fist, Rect2(at + Vector2(-r * 0.2, -r * 0.1), Vector2(r * 0.66, r * 0.6)))
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-r * 0.18, -r * 0.08), at + Vector2(r * 0.02, -r * 0.62),
				at + Vector2(r * 0.22, -r * 0.55), at + Vector2(r * 0.16, -r * 0.08)]), Color.WHITE)


# --- photos -----------------------------------------------------------------------------------

## A photo for a post: full width, `h` px high, drawn to its size.
## `colour` is for the chase photo (your car's paint).
static func photo(kind: String, h: float, sd: int, colour := Color(0.75, 0.1, 0.1)) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.clip_contents = true
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_meta("kinbook_photo", kind)
	c.draw.connect(func() -> void: draw_photo(c, kind, c.size, sd, colour))
	return c


static func draw_photo(c: Control, kind: String, s: Vector2, sd: int, colour: Color) -> void:
	var w := s.x
	var h := s.y
	# Phone photos are never quite straight: shift everything a little.
	var off := Vector2(float(sd % 7 - 3) * w * 0.012, float(sd % 5 - 2) * h * 0.01)
	c.draw_set_transform(off, 0.0, Vector2.ONE)
	match kind:
		"pothole": _pothole(c, w, h)
		"cones": _cones(c, w, h)
		"cat": _cat(c, w, h, sd)
		"dog": _dog(c, w, h)
		"blob": _blob(c, w, h)
		"casserole": _casserole(c, w, h)
		"air_fryer": _air_fryer(c, w, h)
		"cheese": _cheese(c, w, h)
		"fish": _fish(c, w, h)
		"boat": _boat(c, w, h)
		"bingo": _bingo(c, w, h)
		"sign": _sign(c, w, h)
		"church": _church(c, w, h)
		"sink": _sink(c, w, h)
		"deck": _deck(c, w, h)
		"lights": _lights(c, w, h, sd)
		"truck": _truck(c, w, h, sd)
		"chase": _chase(c, w, h, colour)
		_: _jar(c, w, h)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# A thumb over the corner, one photo in five.
	if sd % 5 == 0 and kind != "jar":
		var at := Vector2(w * (0.04 if sd % 2 == 0 else 0.96), h * 1.02)
		for i in 6:
			_ellipse(c, at, Vector2(w * 0.13, h * 0.34) * (1.0 - i * 0.08), Color(0.86, 0.6, 0.52, 0.3))
	# A soft dark edge, like a phone camera.
	for i in 4:
		var t := 1.0 + i * 2.0
		c.draw_rect(Rect2(Vector2(t, t) * 0.5, s - Vector2(t, t)), Color(0, 0, 0, 0.05), false, t)


static func _ellipse(c: Control, at: Vector2, r: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(at + Vector2(cos(a) * r.x, sin(a) * r.y))
	c.draw_colored_polygon(pts, col)


static func _arc_pts(at: Vector2, r: float, from: float, to: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(from, to, float(i) / n)
		pts.append(at + Vector2(cos(a), sin(a)) * r)
	return pts


## A band from `top` to `bottom` (fractions of h), shading `a` to `b`.
static func _band(c: Control, w: float, h: float, top: float, bottom: float, a: Color, b: Color) -> void:
	c.draw_polygon(PackedVector2Array([Vector2(-20, top * h), Vector2(w + 20, top * h), Vector2(w + 20, bottom * h), Vector2(-20, bottom * h)]),
		PackedColorArray([a, a, b, b]))


static func _sky(c: Control, w: float, h: float, bottom: float) -> void:
	_band(c, w, h, -0.1, bottom, Color("#6fa8dc"), Color("#cfe2f3"))


static func _grass(c: Control, w: float, h: float, top: float) -> void:
	_band(c, w, h, top, 1.1, Color("#7fb24a"), Color("#4f7f2a"))


static func _cone(c: Control, base: Vector2, size: float) -> void:
	c.draw_rect(Rect2(base + Vector2(-size * 0.42, -size * 0.1), Vector2(size * 0.84, size * 0.1)), Color("#2b2b2b"))
	var top := base + Vector2(0, -size)
	var pts := PackedVector2Array([top + Vector2(-size * 0.07, 0), top + Vector2(size * 0.07, 0), base + Vector2(size * 0.3, -size * 0.1), base + Vector2(-size * 0.3, -size * 0.1)])
	c.draw_colored_polygon(pts, Color("#ff6b1a"))
	for f: float in [0.35, 0.62]:
		var y := lerpf(top.y, base.y - size * 0.1, f)
		var half := lerpf(size * 0.07, size * 0.3, f)
		c.draw_rect(Rect2(Vector2(base.x - half, y), Vector2(half * 2.0, size * 0.1)), Color(1, 1, 1, 0.92))


static func _road(c: Control, w: float, h: float, horizon: float) -> void:
	_band(c, w, h, horizon, 1.1, Color("#8a8d91"), Color("#5c5f63"))
	# The centre line going off into the distance.
	for i in 5:
		var t0 := pow(float(i) / 5.0, 1.6)
		var t1 := pow((float(i) + 0.55) / 5.0, 1.6)
		var y0 := lerpf(horizon * h, h * 1.05, t0)
		var y1 := lerpf(horizon * h, h * 1.05, t1)
		var hw0 := lerpf(1.0, w * 0.025, t0)
		var hw1 := lerpf(1.0, w * 0.025, t1)
		c.draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5 - hw0, y0), Vector2(w * 0.5 + hw0, y0), Vector2(w * 0.5 + hw1, y1), Vector2(w * 0.5 - hw1, y1)]), Color("#f2c230"))


static func _pothole(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.3)
	# Houses along Kirkwood.
	for i in 4:
		var x := w * (0.05 + i * 0.26)
		var col: Color = [Color("#d8c7a0"), Color("#a9c1d9"), Color("#e8e2d4"), Color("#c99a8a")][i]
		c.draw_rect(Rect2(x, h * 0.14, w * 0.2, h * 0.17), col)
		c.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.01, h * 0.14), Vector2(x + w * 0.1, h * 0.05), Vector2(x + w * 0.21, h * 0.14)]), Color("#5a4a42"))
	_road(c, w, h, 0.3)
	_ellipse(c, Vector2(w * 0.44, h * 0.72), Vector2(w * 0.26, h * 0.16), Color("#3d3f42"))
	_ellipse(c, Vector2(w * 0.44, h * 0.73), Vector2(w * 0.22, h * 0.12), Color("#25272a"))
	_ellipse(c, Vector2(w * 0.47, h * 0.75), Vector2(w * 0.13, h * 0.06), Color(0.55, 0.65, 0.75, 0.55))
	_cone(c, Vector2(w * 0.8, h * 0.9), h * 0.36)


static func _cones(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.28)
	c.draw_rect(Rect2(-10, h * 0.2, w + 20, h * 0.1), Color("#b7b2a6"))
	_road(c, w, h, 0.3)
	for i in 5:
		var t := float(i) / 4.0
		_cone(c, Vector2(lerpf(w * 0.12, w * 0.86, t), lerpf(h * 0.96, h * 0.48, t)), lerpf(h * 0.5, h * 0.2, t))


static func _cat(c: Control, w: float, h: float, sd: int) -> void:
	# Siding behind, the neighbour's deck rail in front.
	c.draw_rect(Rect2(-10, -10, w + 20, h + 20), Color("#e7dcc4"))
	for i in 9:
		c.draw_line(Vector2(-10, h * (0.08 + i * 0.075)), Vector2(w + 10, h * (0.08 + i * 0.075)), Color("#cbbd9f"), 2.0)
	c.draw_rect(Rect2(-10, h * 0.74, w + 20, h * 0.3), Color("#8b5a2b"))
	c.draw_rect(Rect2(-10, h * 0.7, w + 20, h * 0.06), Color("#6e4420"))
	var fur: Color = [Color("#1d1d1f"), Color("#e07b24"), Color("#8d8f94")][sd % 3]
	var cx := w * 0.52
	_ellipse(c, Vector2(cx, h * 0.6), Vector2(h * 0.24, h * 0.2), fur)
	_ellipse(c, Vector2(cx, h * 0.64), Vector2(h * 0.09, h * 0.12), Color("#f4f1ea"))
	var head := Vector2(cx, h * 0.33)
	c.draw_colored_polygon(PackedVector2Array([head + Vector2(-h * 0.15, -h * 0.02), head + Vector2(-h * 0.12, -h * 0.2), head + Vector2(-h * 0.02, -h * 0.1)]), fur)
	c.draw_colored_polygon(PackedVector2Array([head + Vector2(h * 0.15, -h * 0.02), head + Vector2(h * 0.12, -h * 0.2), head + Vector2(h * 0.02, -h * 0.1)]), fur)
	_ellipse(c, head, Vector2(h * 0.16, h * 0.14), fur)
	# Eyes half shut: judging you.
	for sx: float in [-1.0, 1.0]:
		var e := head + Vector2(sx * h * 0.065, -h * 0.01)
		_ellipse(c, e, Vector2(h * 0.035, h * 0.022), Color("#e8d33a"))
		c.draw_rect(Rect2(e + Vector2(-h * 0.04, -h * 0.03), Vector2(h * 0.08, h * 0.022)), fur)
		c.draw_line(e + Vector2(-h * 0.04, -h * 0.008), e + Vector2(h * 0.04, -h * 0.008), Color(0, 0, 0, 0.8), 1.5)
	c.draw_colored_polygon(PackedVector2Array([head + Vector2(-h * 0.015, h * 0.04), head + Vector2(h * 0.015, h * 0.04), head + Vector2(0, h * 0.06)]), Color("#d98a94"))
	# The tail over the rail.
	c.draw_polyline(_arc_pts(Vector2(cx + h * 0.3, h * 0.72), h * 0.12, PI, PI * 1.9, 10), fur, h * 0.05)


static func _dog(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.4)
	_grass(c, w, h, 0.4)
	var fur := Color("#8a5a35")
	_ellipse(c, Vector2(w * 0.45, h * 0.62), Vector2(h * 0.32, h * 0.17), fur)
	for x: float in [-0.22, -0.1, 0.12, 0.24]:
		c.draw_rect(Rect2(w * 0.45 + x * h, h * 0.68, h * 0.07, h * 0.22), fur)
	var head := Vector2(w * 0.45 + h * 0.34, h * 0.42)
	_ellipse(c, head, Vector2(h * 0.14, h * 0.12), fur)
	_ellipse(c, head + Vector2(h * 0.12, h * 0.04), Vector2(h * 0.08, h * 0.06), fur.lightened(0.15))
	_ellipse(c, head + Vector2(-h * 0.06, h * 0.02), Vector2(h * 0.05, h * 0.11), fur.darkened(0.35))
	c.draw_circle(head + Vector2(h * 0.03, -h * 0.03), h * 0.018, Color.BLACK)
	# The ball he won't give back.
	c.draw_circle(head + Vector2(h * 0.2, h * 0.1), h * 0.07, Color("#d4e33a"))
	c.draw_polyline(_arc_pts(Vector2(w * 0.45 - h * 0.36, h * 0.5), h * 0.1, PI * 0.9, PI * 1.6, 8), fur, h * 0.05)


## Something on four legs, maybe. Nobody could hold the phone still.
static func _blob(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.45)
	_grass(c, w, h, 0.45)
	for i in 8:
		var k := 1.0 - i * 0.1
		_ellipse(c, Vector2(w * 0.5 + i * 2.0, h * 0.58), Vector2(h * 0.4, h * 0.26) * k, Color(0.55, 0.45, 0.35, 0.16))
	for i in 5:
		_ellipse(c, Vector2(w * 0.5 + h * 0.3, h * 0.42), Vector2(h * 0.16, h * 0.14) * (1.0 - i * 0.15), Color(0.5, 0.4, 0.3, 0.18))


static func _check_cloth(c: Control, w: float, h: float, a: Color, b: Color) -> void:
	c.draw_rect(Rect2(-10, -10, w + 20, h + 20), a)
	var n := 9
	var sq := w / n
	for i in n + 1:
		for j in int(h / sq) + 2:
			if (i + j) % 2 == 0:
				c.draw_rect(Rect2(i * sq - 5, j * sq - 5, sq, sq), b)


static func _casserole(c: Control, w: float, h: float) -> void:
	_check_cloth(c, w, h, Color("#f5f0e8"), Color("#d94b4b"))
	var at := Vector2(w * 0.5, h * 0.54)
	_ellipse(c, at + Vector2(6, 8), Vector2(w * 0.38, h * 0.38), Color(0, 0, 0, 0.18))
	_ellipse(c, at, Vector2(w * 0.38, h * 0.38), Color("#f7f7f2"))
	_ellipse(c, at, Vector2(w * 0.32, h * 0.3), Color("#c98a3c"))
	for i in 14:
		var a := i * 2.4
		var r := (i % 5) * 0.05 + 0.05
		_ellipse(c, at + Vector2(cos(a) * w * r, sin(a) * h * r), Vector2(w * 0.035, h * 0.03), Color("#9c5f22"))
	for i in 9:
		var a := i * 1.7 + 0.5
		_ellipse(c, at + Vector2(cos(a) * w * 0.18, sin(a) * h * 0.15), Vector2(w * 0.03, h * 0.025), Color("#efc768"))
	# The handles: the dish she paid for.
	_ellipse(c, at + Vector2(-w * 0.4, 0), Vector2(w * 0.05, h * 0.09), Color("#e9e9e2"))
	_ellipse(c, at + Vector2(w * 0.4, 0), Vector2(w * 0.05, h * 0.09), Color("#e9e9e2"))


static func _counter(c: Control, w: float, h: float, top: float) -> void:
	c.draw_rect(Rect2(-10, -10, w + 20, top * h + 10), Color("#e9e4da"))
	for i in 6:
		c.draw_line(Vector2(w * i / 5.0, 0), Vector2(w * i / 5.0, top * h), Color("#d6cfc1"), 2.0)
	_band(c, w, h, top, 1.1, Color("#b98a5a"), Color("#8f6337"))


static func _air_fryer(c: Control, w: float, h: float) -> void:
	_counter(c, w, h, 0.72)
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#232427")
	box.set_corner_radius_all(int(h * 0.12))
	box.anti_aliasing = true
	var r := Rect2(w * 0.5 - h * 0.3, h * 0.12, h * 0.6, h * 0.72)
	c.draw_style_box(box, r)
	c.draw_circle(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.2), h * 0.07, Color("#4a4c52"))
	c.draw_line(r.position + Vector2(r.size.x * 0.5, r.size.y * 0.2), r.position + Vector2(r.size.x * 0.54, r.size.y * 0.13), Color("#d0d0d0"), 2.0)
	c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.12, r.size.y * 0.42), Vector2(r.size.x * 0.76, r.size.y * 0.46)), Color("#2f3034"))
	c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.3, r.size.y * 0.55), Vector2(r.size.x * 0.4, r.size.y * 0.08)), Color("#55575d"))
	# The name on it, mostly scrubbed off.
	var y := r.position.y + r.size.y * 0.76
	c.draw_polyline(PackedVector2Array([Vector2(r.position.x + r.size.x * 0.25, y), Vector2(r.position.x + r.size.x * 0.33, y - 5),
		Vector2(r.position.x + r.size.x * 0.4, y + 2), Vector2(r.position.x + r.size.x * 0.5, y - 4), Vector2(r.position.x + r.size.x * 0.58, y + 1)]),
		Color(1, 1, 1, 0.35), 2.0)


static func _cheese(c: Control, w: float, h: float) -> void:
	_counter(c, w, h, 0.45)
	# The cheese, and a domino for scale.
	var cheese := Rect2(w * 0.3, h * 0.56, h * 0.28, h * 0.14)
	c.draw_rect(cheese.grow(1), Color("#d9a61e"))
	c.draw_rect(cheese, Color("#f4c542"))
	c.draw_rect(Rect2(cheese.position, Vector2(cheese.size.x, cheese.size.y * 0.25)), Color(1, 1, 1, 0.35))
	var dom := Rect2(w * 0.3 + h * 0.36, h * 0.56, h * 0.28, h * 0.14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#151515")
	sb.set_corner_radius_all(3)
	c.draw_style_box(sb, dom)
	c.draw_line(dom.position + Vector2(dom.size.x * 0.5, 2), dom.position + Vector2(dom.size.x * 0.5, dom.size.y - 2), Color("#aaaaaa"), 1.0)
	for p: Vector2 in [Vector2(0.2, 0.3), Vector2(0.32, 0.7), Vector2(0.68, 0.5), Vector2(0.82, 0.25), Vector2(0.82, 0.75)]:
		c.draw_circle(dom.position + dom.size * p, h * 0.014, Color.WHITE)
	# The price sticker.
	var tag := Rect2(w * 0.3, h * 0.3, h * 0.34, h * 0.15)
	c.draw_rect(tag, Color("#fff36b"))
	var fs := int(h * 0.1)
	c.draw_string(bold_font(), tag.position + Vector2(h * 0.03, tag.size.y * 0.75), "$6.49", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#c0161d"))


static func _water(c: Control, w: float, h: float, top: float) -> void:
	_band(c, w, h, top, 1.1, Color("#3f7fae"), Color("#1d4f77"))
	for i in 7:
		var y := lerpf(top * h + 6.0, h, float(i) / 7.0)
		for j in 5:
			var x := w * (j * 0.22 + (i % 2) * 0.1)
			c.draw_arc(Vector2(x, y), w * 0.03, PI * 1.1, PI * 1.9, 6, Color(1, 1, 1, 0.3), 1.5)


static func _fish(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.5)
	_water(c, w, h, 0.5)
	# Him, in plaid, holding the fish up where his face is. No faces.
	var body := Rect2(w * 0.5 - h * 0.34, h * 0.58, h * 0.68, h * 0.5)
	c.draw_rect(body, Color("#b3261e"))
	for i in 6:
		c.draw_line(Vector2(body.position.x + i * body.size.x / 5.0, body.position.y), Vector2(body.position.x + i * body.size.x / 5.0, h), Color(0.1, 0.05, 0.05, 0.6), 3.0)
	for i in 4:
		c.draw_line(Vector2(body.position.x, body.position.y + i * h * 0.12), Vector2(body.end.x, body.position.y + i * h * 0.12), Color(0.1, 0.05, 0.05, 0.6), 3.0)
	var skin := Color("#e8b48e")
	c.draw_rect(Rect2(w * 0.5 - h * 0.3, h * 0.36, h * 0.1, h * 0.26), skin)
	c.draw_rect(Rect2(w * 0.5 + h * 0.2, h * 0.36, h * 0.1, h * 0.26), skin)
	var fish := Vector2(w * 0.5, h * 0.34)
	c.draw_colored_polygon(PackedVector2Array([fish + Vector2(h * 0.36, 0), fish + Vector2(h * 0.56, -h * 0.13), fish + Vector2(h * 0.56, h * 0.13)]), Color("#6d7f6a"))
	_ellipse(c, fish, Vector2(h * 0.42, h * 0.15), Color("#8a9c84"))
	_ellipse(c, fish + Vector2(0, h * 0.04), Vector2(h * 0.36, h * 0.07), Color("#c9d1c0"))
	c.draw_circle(fish + Vector2(-h * 0.3, -h * 0.03), h * 0.025, Color.BLACK)
	for x: float in [-0.12, 0.0, 0.12]:
		c.draw_circle(fish + Vector2(x * h, -h * 0.05), h * 0.015, Color(0.25, 0.3, 0.25, 0.7))
	_ellipse(c, Vector2(w * 0.5 - h * 0.25, h * 0.36), Vector2(h * 0.07, h * 0.05), skin)
	_ellipse(c, Vector2(w * 0.5 + h * 0.25, h * 0.36), Vector2(h * 0.07, h * 0.05), skin)


static func _boat(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.5)
	c.draw_rect(Rect2(-10, h * 0.44, w + 20, h * 0.07), Color("#6b8f5a"))
	# The boat: mostly under, the mast leaning.
	var at := Vector2(w * 0.5, h * 0.62)
	c.draw_set_transform(at, -0.32, Vector2.ONE)
	c.draw_colored_polygon(PackedVector2Array([Vector2(-h * 0.5, -h * 0.05), Vector2(h * 0.5, -h * 0.12), Vector2(h * 0.38, h * 0.12), Vector2(-h * 0.4, h * 0.14)]), Color("#f1f1ee"))
	c.draw_rect(Rect2(-h * 0.5, -h * 0.07, h * 1.0, h * 0.05), Color("#2a5d8f"))
	c.draw_rect(Rect2(-h * 0.02, -h * 0.6, h * 0.03, h * 0.55), Color("#ddd"))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_water(c, w, h, 0.6)
	for i in 5:
		c.draw_arc(Vector2(w * 0.4 + i * w * 0.05, h * (0.64 - i * 0.02)), h * 0.015, 0, TAU, 8, Color(1, 1, 1, 0.7), 1.5)


static func _bingo(c: Control, w: float, h: float) -> void:
	c.draw_rect(Rect2(-10, -10, w + 20, h + 20), Color("#7a5a3a"))
	var card := Rect2(w * 0.5 - h * 0.42, h * 0.06, h * 0.84, h * 0.9)
	c.draw_rect(card, Color("#fbf8ef"))
	var f := bold_font()
	var cell := card.size.x / 5.0
	var top := card.position.y + h * 0.14
	var fs := int(h * 0.09)
	for i in 5:
		var letter := "BINGO"[i]
		var lw := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		c.draw_string(f, Vector2(card.position.x + cell * (i + 0.5) - lw * 0.5, card.position.y + h * 0.11), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#c0161d"))
	var rows := 5
	var ch := (card.end.y - top - h * 0.02) / rows
	for i in 6:
		c.draw_line(Vector2(card.position.x + i * cell, top), Vector2(card.position.x + i * cell, top + ch * rows), Color("#b9b2a2"), 1.0)
	for j in 6:
		c.draw_line(Vector2(card.position.x, top + j * ch), Vector2(card.end.x, top + j * ch), Color("#b9b2a2"), 1.0)
	# Purple dauber. Every square. Some people.
	var daubed := [0, 2, 6, 7, 12, 13, 14, 17, 19, 21, 24]
	for k: int in daubed:
		var at := Vector2(card.position.x + cell * (k % 5 + 0.5), top + ch * (k / 5 + 0.5))
		c.draw_circle(at, minf(cell, ch) * 0.4, Color(0.55, 0.2, 0.7, 0.75))
	for k in 25:
		if not k in daubed:
			var n := str(k % 5 * 15 + 1 + (k * 7) % 15)
			var nw := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.6)).x
			c.draw_string(_font(), Vector2(card.position.x + cell * (k % 5 + 0.5) - nw * 0.5, top + ch * (k / 5 + 0.68)), n, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.6), Color("#333"))


static func _sign(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.55)
	c.draw_rect(Rect2(-10, h * 0.42, w + 20, h * 0.14), Color("#d9d2c3"))
	_grass(c, w, h, 0.55)
	var sign := Rect2(w * 0.5 - h * 0.42, h * 0.18, h * 0.84, h * 0.48)
	c.draw_line(Vector2(sign.position.x + sign.size.x * 0.25, sign.end.y), Vector2(sign.position.x + sign.size.x * 0.25, h * 0.9), Color("#777"), 2.0)
	c.draw_line(Vector2(sign.position.x + sign.size.x * 0.75, sign.end.y), Vector2(sign.position.x + sign.size.x * 0.75, h * 0.9), Color("#777"), 2.0)
	c.draw_rect(sign, Color("#f77f00"))
	c.draw_rect(sign.grow(-h * 0.03), Color("#ff9a2e"), false, 2.0)
	var f := bold_font()
	var fs := int(h * 0.15)
	var t := "DALE S."
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(f, Vector2(sign.position.x + (sign.size.x - tw) * 0.5, sign.position.y + sign.size.y * 0.48), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	var t2 := "ORANGE PARTY  ·  DISTRICT 9"
	var fs2 := int(h * 0.065)
	var tw2 := f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	if tw2 > sign.size.x * 0.88:
		fs2 = maxi(6, int(fs2 * sign.size.x * 0.88 / tw2))
		tw2 = f.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	c.draw_string(f, Vector2(sign.position.x + (sign.size.x - tw2) * 0.5, sign.position.y + sign.size.y * 0.78), t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color("#4a2300"))


static func _church(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.78)
	_grass(c, w, h, 0.78)
	var x := w * 0.5
	var body := Rect2(x - h * 0.3, h * 0.42, h * 0.6, h * 0.38)
	c.draw_rect(body, Color("#f6f4ee"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(body.position.x - 6, body.position.y), Vector2(body.end.x + 6, body.position.y), Vector2(x, h * 0.26)]), Color("#3d4a5c"))
	c.draw_rect(Rect2(x - h * 0.08, h * 0.12, h * 0.16, h * 0.32), Color("#f6f4ee"))
	c.draw_colored_polygon(PackedVector2Array([Vector2(x - h * 0.1, h * 0.12), Vector2(x + h * 0.1, h * 0.12), Vector2(x, -h * 0.06)]), Color("#3d4a5c"))
	c.draw_rect(Rect2(x - h * 0.06, h * 0.62, h * 0.12, h * 0.18), Color("#9c2a2a"))
	for sx: float in [-0.2, 0.2]:
		c.draw_rect(Rect2(x + sx * h - h * 0.035, h * 0.5, h * 0.07, h * 0.14), Color("#8fb3d9"))


static func _sink(c: Control, w: float, h: float) -> void:
	c.draw_rect(Rect2(-10, -10, w + 20, h + 20), Color("#dfe7e8"))
	var tile := h * 0.14
	for i in int(w / tile) + 2:
		c.draw_line(Vector2(i * tile, 0), Vector2(i * tile, h * 0.55), Color("#c3cdcf"), 1.0)
	for j in 5:
		c.draw_line(Vector2(0, j * tile), Vector2(w, j * tile), Color("#c3cdcf"), 1.0)
	c.draw_rect(Rect2(-10, h * 0.55, w + 20, h * 0.5), Color("#8d6e53"))
	_ellipse(c, Vector2(w * 0.5, h * 0.62), Vector2(h * 0.48, h * 0.16), Color("#f4f6f7"))
	_ellipse(c, Vector2(w * 0.5, h * 0.63), Vector2(h * 0.4, h * 0.11), Color("#c9d0d4"))
	c.draw_rect(Rect2(w * 0.5 - h * 0.025, h * 0.28, h * 0.05, h * 0.24), Color("#b8bec4"))
	c.draw_rect(Rect2(w * 0.5 - h * 0.025, h * 0.28, h * 0.16, h * 0.04), Color("#b8bec4"))
	# The drip. Fix it Garth.
	for i in 3:
		_ellipse(c, Vector2(w * 0.5 + h * 0.12, h * (0.37 + i * 0.07)), Vector2(h * 0.012, h * 0.02), Color("#5ba3d9"))


static func _deck(c: Control, w: float, h: float) -> void:
	_sky(c, w, h, 0.5)
	_grass(c, w, h, 0.5)
	# The house, with a door a metre up and nothing under it.
	c.draw_rect(Rect2(-10, h * 0.05, w * 0.36, h * 0.6), Color("#cfd8dc"))
	for i in 9:
		c.draw_line(Vector2(-10, h * (0.08 + i * 0.065)), Vector2(w * 0.35, h * (0.08 + i * 0.065)), Color("#b0bec5"), 1.5)
	c.draw_rect(Rect2(w * 0.12, h * 0.15, w * 0.1, h * 0.3), Color("#6d4c41"))
	# The deck, out in the yard.
	var pts := PackedVector2Array([Vector2(w * 0.45, h * 0.66), Vector2(w * 0.95, h * 0.6), Vector2(w * 1.0, h * 0.82), Vector2(w * 0.42, h * 0.9)])
	c.draw_colored_polygon(pts, Color("#a1714a"))
	for i in 7:
		var t := float(i) / 7.0
		c.draw_line(pts[0].lerp(pts[3], t), pts[1].lerp(pts[2], t), Color("#7b5232"), 1.5)
	c.draw_line(Vector2(w * 0.47, h * 0.66), Vector2(w * 0.47, h * 0.46), Color("#7b5232"), 3.0)
	c.draw_line(Vector2(w * 0.93, h * 0.6), Vector2(w * 0.93, h * 0.42), Color("#7b5232"), 3.0)
	c.draw_line(Vector2(w * 0.47, h * 0.48), Vector2(w * 0.93, h * 0.44), Color("#7b5232"), 3.0)


static func _glow(c: Control, at: Vector2, r: float, col: Color) -> void:
	for i in 6:
		c.draw_circle(at, r * (1.0 - i * 0.15), Color(col, 0.14 + i * 0.04))


static func _lights(c: Control, w: float, h: float, sd: int) -> void:
	_band(c, w, h, -0.1, 0.62, Color("#0b1020"), Color("#1c2438"))
	_band(c, w, h, 0.62, 1.1, Color("#2a2e36"), Color("#16181d"))
	for i in 5:
		var x := w * (0.05 + i * 0.23)
		c.draw_rect(Rect2(x, h * 0.3, w * 0.16, h * 0.33), Color("#151a28"))
		c.draw_rect(Rect2(x + w * 0.03, h * 0.38, w * 0.04, h * 0.05), Color(1.0, 0.85, 0.5, 0.6))
	var reds := Color("#ff2a2a")
	var other := Color("#3a6bff") if sd % 2 == 0 else Color("#ffffff")
	_glow(c, Vector2(w * 0.38, h * 0.6), h * 0.2, reds)
	_glow(c, Vector2(w * 0.56, h * 0.58), h * 0.18, other)
	_glow(c, Vector2(w * 0.78, h * 0.62), h * 0.12, reds)
	_glow(c, Vector2(w * 0.15, h * 0.64), h * 0.08, Color(1, 0.9, 0.6))
	for i in 8:
		c.draw_line(Vector2(w * 0.3 + i * 6, h * 0.8), Vector2(w * 0.3 + i * 6 + 12, h * 0.95), Color(reds, 0.12), 3.0)


static func _pickup(c: Control, at: Vector2, k: float, paint: Color, lifted: bool) -> void:
	var lift := k * 0.12 if lifted else 0.0
	var wheel := k * (0.17 if lifted else 0.13)
	c.draw_rect(Rect2(at + Vector2(-k * 0.75, -k * 0.38 - lift), Vector2(k * 1.5, k * 0.24)), paint)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-k * 0.2, -k * 0.38 - lift), at + Vector2(-k * 0.12, -k * 0.62 - lift),
		at + Vector2(k * 0.3, -k * 0.62 - lift), at + Vector2(k * 0.42, -k * 0.38 - lift)]), paint)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-k * 0.12, -k * 0.4 - lift), at + Vector2(-k * 0.07, -k * 0.57 - lift),
		at + Vector2(k * 0.27, -k * 0.57 - lift), at + Vector2(k * 0.36, -k * 0.4 - lift)]), Color("#3a4a5a"))
	c.draw_line(at + Vector2(-k * 0.75, -k * 0.38 - lift), at + Vector2(-k * 0.22, -k * 0.38 - lift), paint.darkened(0.3), 2.0)
	c.draw_rect(Rect2(at + Vector2(k * 0.68, -k * 0.34 - lift), Vector2(k * 0.07, k * 0.06)), Color("#ffe9a8"))
	for x: float in [-0.48, 0.5]:
		c.draw_circle(at + Vector2(x * k, -wheel), wheel, Color("#151515"))
		c.draw_circle(at + Vector2(x * k, -wheel), wheel * 0.45, Color("#9aa0a6"))


static func _truck(c: Control, w: float, h: float, sd: int) -> void:
	_sky(c, w, h, 0.55)
	_band(c, w, h, 0.55, 1.1, Color("#7d8085"), Color("#5a5d61"))
	for i in 4:
		c.draw_line(Vector2(w * (0.1 + i * 0.28), h * 0.62), Vector2(w * (0.02 + i * 0.28), h), Color(1, 1, 1, 0.7), 2.0)
	var paints := [Color("#f2f2f0"), Color("#1a1a1c"), Color("#8c2318"), Color("#2f4f6f")]
	var paint: Color = paints[sd % paints.size()]
	_pickup(c, Vector2(w * 0.5, h * 0.9), h * 0.85, paint, paint.v < 0.2)


static func _chase(c: Control, w: float, h: float, paint: Color) -> void:
	_band(c, w, h, -0.1, 0.5, Color("#7a8796"), Color("#b8c0c8"))
	_band(c, w, h, 0.5, 1.1, Color("#6f7276"), Color("#4c4f53"))
	_glow(c, Vector2(w * 0.12, h * 0.6), h * 0.16, Color("#ff2a2a"))
	_glow(c, Vector2(w * 0.24, h * 0.58), h * 0.14, Color("#3a6bff"))
	# You, going by too fast for the phone.
	var at := Vector2(w * 0.6, h * 0.82)
	var k := h * 0.8
	for i in 5:
		var y := at.y - k * (0.12 + i * 0.07)
		c.draw_line(Vector2(at.x - k * 1.25 - i * 8, y), Vector2(at.x - k * 0.55, y), Color(1, 1, 1, 0.35), 2.0)
	for i in 3:
		var dx := -i * k * 0.08
		var col := Color(paint, 0.35 if i > 0 else 1.0)
		c.draw_rect(Rect2(at + Vector2(-k * 0.55 + dx, -k * 0.3), Vector2(k * 1.1, k * 0.2)), col)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(-k * 0.32 + dx, -k * 0.3), at + Vector2(-k * 0.18 + dx, -k * 0.48),
			at + Vector2(k * 0.2 + dx, -k * 0.48), at + Vector2(k * 0.36 + dx, -k * 0.3)]), col)
	c.draw_colored_polygon(PackedVector2Array([at + Vector2(-k * 0.26, -k * 0.31), at + Vector2(-k * 0.15, -k * 0.45),
		at + Vector2(k * 0.18, -k * 0.45), at + Vector2(k * 0.3, -k * 0.31)]), Color("#33404d"))
	for x: float in [-0.34, 0.34]:
		c.draw_circle(at + Vector2(x * k, -k * 0.1), k * 0.1, Color("#151515"))
		c.draw_circle(at + Vector2(x * k, -k * 0.1), k * 0.045, Color("#888"))


## A ChipIn with nothing else to show: the jar, and not much in it.
static func _jar(c: Control, w: float, h: float) -> void:
	_counter(c, w, h, 0.7)
	var jar := Rect2(w * 0.5 - h * 0.22, h * 0.16, h * 0.44, h * 0.66)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.8, 0.9, 0.95, 0.45)
	sb.border_color = Color(1, 1, 1, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(h * 0.06))
	sb.anti_aliasing = true
	c.draw_style_box(sb, jar)
	c.draw_rect(Rect2(jar.position.x + h * 0.03, jar.position.y - h * 0.05, jar.size.x - h * 0.06, h * 0.07), Color("#9a9fa6"))
	for p: Vector2 in [Vector2(0.35, 0.92), Vector2(0.62, 0.93), Vector2(0.5, 0.87)]:
		_ellipse(c, jar.position + jar.size * p, Vector2(h * 0.05, h * 0.02), Color("#d6b04a"))
	var label := Rect2(jar.position + Vector2(0, jar.size.y * 0.32), Vector2(jar.size.x, jar.size.y * 0.22))
	c.draw_rect(label, Color("#fff8e1"))
	var f := bold_font()
	var fs := int(h * 0.07)
	var t := "CHIPIN"
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	c.draw_string(f, Vector2(label.position.x + (label.size.x - tw) * 0.5, label.position.y + label.size.y * 0.68), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#2e7d32"))

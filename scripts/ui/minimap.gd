class_name Minimap
extends Control
## The minimap, bottom left: a round map of the streets and the water
## round the player, turned so up is the way the camera looks, with a white
## rim that turns red while you're wanted. On it: you (an arrow), and what
## other code puts there through a small API:
##
##   Minimap.find(get_tree())          the one on the HUD (or null)
##   set_marker(id, kind, at)          a fixed icon at a world point; kinds:
##                                     "car_wash", "police_station" (shown
##                                     on the rim, pointing the way, when off
##                                     the map)
##   remove_marker(id)
##   track(node, kind)                 an icon that follows a Node3D; kinds:
##                                     "police", "fip" (a unit; dropped when
##                                     the node goes)
##   untrack(node)
##   set_search_circle(centre, radius) the wanted level's search circle
##   clear_search_circle()             (WantedHud keeps these up to date)
##   set_caption(text)                 a line over the map ("" hides it)
##
## The waypoint (Gps) shows too: the route to it in the waypoint colour,
## and its pin, on the rim pointing the way while it's off the map.
##
## Drawing cost: the streets (RoadNetwork's centrelines, each drawn its own
## width) and a coarse water mask are drawn once, into cached 2D drawing
## split into TILE squares, so the renderer skips the ones off screen; each
## frame only their transform changes (where you are, which way the camera
## looks, the zoom), and a round clip cuts them to the disc. Only the icons,
## the arrow and the rim are drawn again each frame (a few dozen shapes).
## The water mask is built on a worker thread from the terrain's heights
## (ground below Terrain.WATER_Y), so loading doesn't stall.
##
## Same look as the rest of the HUD: a dark translucent disc, white
## streets and text, Bebas Neue for letters.

## px across at 1600 x 900 (scaled with the screen's height).
const DIAMETER := 220.0
## px from the screen's bottom left corner.
const MARGIN := Vector2(24, 24)
## m from the middle to the rim on foot, and when driving fast.
const RANGE_FOOT := 180.0
const RANGE_FAST := 380.0
const FAST := 30.0 ## m/s at which it's zoomed right out
## m: streets are cut into squares this size for drawing (culled off screen).
const TILE := 400.0
## m per pixel of the water mask.
const WATER_CELL := 10.0
## Streets are never drawn thinner than this (m), so lanes still show
## zoomed out.
const MIN_WIDTH := 7.0
const NAME_FONT := "res://branding/fonts/BebasNeue-Regular.ttf"

const BACK := Color(0.08, 0.09, 0.1, 0.84)
const STREET := Color(0.78, 0.79, 0.78, 0.85)
const YOU := Color(1.0, 0.86, 0.45) ## the HUD's accent, so the arrow shows on the streets
const HIGHWAY := Color(1.0, 0.86, 0.45, 0.9)
const WATER := Color(0.2, 0.42, 0.62, 0.75)
const RIM := Color(1, 1, 1, 0.95)
const RED := Color(0.95, 0.2, 0.18)
const WASH := Color(0.35, 0.75, 1.0)
const POLICE_BLUE := Color(0.25, 0.45, 1.0)
const FIP := Color(0.9, 0.85, 0.55)

## The person whose map this is (the player), and the town.
var player: Node3D
var world: Node
## m from the middle to the rim now.
var range_m := RANGE_FOOT
## Markers: id -> {kind, at: Vector3}. Tracked: [{node, kind}].
var markers := {}
var tracked: Array[Dictionary] = []
var search_centre := Vector3.ZERO
var search_radius := 0.0
## True while the rim is red (wanted).
var alarm := false

var _disc: Control
var _map: Node2D ## turned and scaled about the middle
var _shift: Node2D ## moves the world so the player is at the middle
var _search: Node2D
var _icons: Control
var _caption: Label
var _font: Font
var _water_task := -1
var _water_image: Image
var _water_rect := Rect2()
var _t := 0.0
var _route: Node2D
## The water mask once it's made (WorldMap draws it too), and where it lies.
var water_texture: ImageTexture
var water_rect := Rect2()


## The minimap on the HUD, or null.
static func find(tree: SceneTree) -> Minimap:
	return tree.get_first_node_in_group("minimap") as Minimap if tree != null else null


func _ready() -> void:
	add_to_group("minimap")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := FontVariation.new()
	f.base_font = load(NAME_FONT) as Font
	f.spacing_glyph = 1
	_font = f
	_disc = Control.new()
	_disc.name = "Disc"
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_disc.draw.connect(func() -> void: _disc.draw_circle(_disc.size * 0.5, _disc.size.x * 0.5, BACK))
	add_child(_disc)
	_map = Node2D.new()
	_map.name = "Map"
	_disc.add_child(_map)
	_shift = Node2D.new()
	_shift.name = "World"
	_map.add_child(_shift)
	_search = Node2D.new()
	_search.name = "Search"
	_search.draw.connect(_draw_search)
	_route = Node2D.new()
	_route.name = "Route"
	_route.draw.connect(_draw_route)
	_icons = Control.new()
	_icons.name = "Icons"
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icons.draw.connect(_draw_icons)
	add_child(_icons)
	_caption = Label.new()
	_caption.add_theme_font_override("font", _font)
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_caption.add_theme_constant_override("outline_size", 5)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.visible = false
	add_child(_caption)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _exit_tree() -> void:
	# The search circle joins the map once the streets are drawn; if the
	# game ends before that, it's freed here.
	if _search != null and not _search.is_inside_tree() and _search.get_parent() == null:
		_search.free()
		_search = null
	if _route != null and _route.get_parent() == null:
		_route.free()
		_route = null


## Hook it to the town and the player. The streets are drawn once the town
## is built (WorldBuilder.network).
func setup(w: Node, who: Node3D) -> void:
	world = w
	player = who
	if w != null and bool(w.get("is_built")):
		_build_map()
	elif w != null and w.has_signal("built"):
		w.connect("built", _build_map, CONNECT_ONE_SHOT)


func set_marker(id: String, kind: String, at: Vector3) -> void:
	markers[id] = {"kind": kind, "at": at}


func remove_marker(id: String) -> void:
	markers.erase(id)


func track(node: Node3D, kind: String) -> void:
	untrack(node)
	tracked.append({"node": node, "kind": kind})


func untrack(node: Node3D) -> void:
	for i in range(tracked.size() - 1, -1, -1):
		if tracked[i]["node"] == node:
			tracked.remove_at(i)


func set_search_circle(centre: Vector3, radius: float) -> void:
	if centre.is_equal_approx(search_centre) and is_equal_approx(radius, search_radius):
		return
	search_centre = centre
	search_radius = radius
	if _search != null:
		_search.queue_redraw()


func clear_search_circle() -> void:
	if search_radius <= 0.0:
		return
	search_radius = 0.0
	if _search != null:
		_search.queue_redraw()


func set_caption(text: String) -> void:
	_caption.text = text
	_caption.visible = text != ""


## Where a world point is on the minimap now (px, in this control), and
## whether it's inside the disc.
func to_map(p: Vector3) -> Vector2:
	return _map.transform * _shift.transform * Vector2(p.x, p.z)


func _layout() -> void:
	var k := get_viewport_rect().size.y / 900.0
	var d := DIAMETER * k
	size = Vector2(d, d)
	position = Vector2(MARGIN.x * k, get_viewport_rect().size.y - MARGIN.y * k - d)
	_disc.size = size
	_icons.size = size
	_caption.size = Vector2(d + 80.0, 26.0)
	_caption.position = Vector2(-40.0, -30.0 * k)


func _process(delta: float) -> void:
	_t += delta
	_poll_water()
	if player == null or not is_instance_valid(player) or not is_visible_in_tree():
		return
	var p := player.global_position
	var speed := 0.0
	var car: Variant = player.get("vehicle")
	if car is RigidBody3D:
		speed = (car as RigidBody3D).linear_velocity.length()
	var want := lerpf(RANGE_FOOT, RANGE_FAST, smoothstep(4.0, FAST, speed))
	range_m = lerpf(range_m, want, 1.0 - exp(-1.5 * delta))
	# Up is the way the camera looks.
	var fwd := Vector2(0, -1)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var f := -cam.global_basis.z
		if Vector2(f.x, f.z).length() > 0.01:
			fwd = Vector2(f.x, f.z).normalized()
	var r := size.x * 0.5
	_map.position = Vector2(r, r)
	_map.rotation = -PI * 0.5 - fwd.angle()
	_map.scale = Vector2.ONE * (r / range_m)
	_shift.position = -Vector2(p.x, p.z)
	var wanted := get_tree().root.get_node_or_null("Wanted")
	alarm = wanted != null and int(wanted.get("level")) > 0
	_icons.queue_redraw()
	var gps := Gps.find(get_tree())
	if _route != null and gps != null and (gps.active or _route.has_meta("drawn")):
		_route.queue_redraw()


# --- the map, drawn once ----------------------------------------------------------------------

func _build_map() -> void:
	var net: RoadNetwork = world.get("network") if world != null else null
	if net == null:
		return
	var tiles := {} # Vector2i -> Array[RoadEdge]
	for e in net.edges:
		var c := e.bounds.get_center()
		var key := Vector2i(floori(c.x / TILE), floori(c.y / TILE))
		if not tiles.has(key):
			tiles[key] = []
		(tiles[key] as Array).append(e)
	for key: Vector2i in tiles:
		var node := Node2D.new()
		node.name = "Streets_%d_%d" % [key.x, key.y]
		var list: Array = tiles[key]
		node.draw.connect(func() -> void:
			for e: RoadNetwork.RoadEdge in list:
				var col := HIGHWAY if e.is_highway() else STREET
				node.draw_polyline(e.points, col, maxf(MIN_WIDTH, e.half_width * 2.0)))
		_shift.add_child(node)
	_shift.add_child(_route)
	_shift.add_child(_search)
	var terrain: Terrain = world.get("terrain")
	if terrain != null and terrain.nx > 0:
		_water_task = WorkerThreadPool.add_task(_make_water.bind(terrain))


## The water: a small mask, one pixel per WATER_CELL metres, of where the
## ground is below the water line (on a worker thread).
func _make_water(terrain: Terrain) -> void:
	var w := int(float(terrain.nx - 1) * terrain.spacing / WATER_CELL)
	var h := int(float(terrain.nz - 1) * terrain.spacing / WATER_CELL)
	var img := Image.create(w, h, false, Image.FORMAT_LA8)
	for y in h:
		for x in w:
			var gx := terrain.origin.x + (x + 0.5) * WATER_CELL
			var gz := terrain.origin.y + (y + 0.5) * WATER_CELL
			if terrain.height_at(gx, gz) < Terrain.WATER_Y:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	_water_image = img
	_water_rect = Rect2(terrain.origin, Vector2(w, h) * WATER_CELL)


func _poll_water() -> void:
	if _water_task < 0 or not WorkerThreadPool.is_task_completed(_water_task):
		return
	WorkerThreadPool.wait_for_task_completion(_water_task)
	_water_task = -1
	if _water_image == null:
		return
	var tex := ImageTexture.create_from_image(_water_image)
	water_texture = tex
	water_rect = _water_rect
	var water := Node2D.new()
	water.name = "Water"
	water.draw.connect(func() -> void: water.draw_texture_rect(tex, _water_rect, false, WATER))
	_shift.add_child(water)
	_shift.move_child(water, 0) # under the streets
	_water_image = null


# --- drawn each frame --------------------------------------------------------------------------

## The search circle, in world space (so it turns and clips with the map).
func _draw_search() -> void:
	if search_radius <= 0.0:
		return
	var c := Vector2(search_centre.x, search_centre.z)
	_search.draw_circle(c, search_radius, Color(RED, 0.22))
	var px := range_m / (size.x * 0.5) # metres per pixel
	_search.draw_arc(c, search_radius, 0.0, TAU, 64, RED, 2.0 * px)


## The way to the waypoint, in world space like the streets.
func _draw_route() -> void:
	var gps := Gps.find(get_tree())
	_route.set_meta("drawn", gps != null and gps.shows_route())
	if gps == null or not gps.shows_route():
		return
	var pts := gps.route_ahead()
	if pts.size() < 2:
		return
	var px := range_m / (size.x * 0.5)
	_route.draw_polyline(pts, Color(0, 0, 0, 0.55), 7.0 * px, true)
	_route.draw_polyline(pts, HudStyle.WAYPOINT, 4.5 * px, true)


func _draw_icons() -> void:
	var r := size.x * 0.5
	var mid := Vector2(r, r)
	var k := size.x / DIAMETER
	# Fixed markers: inside, where they are; outside, on the rim pointing
	# the way (the car washes and the station are worth finding).
	for id: String in markers:
		var m: Dictionary = markers[id]
		var at := to_map(m["at"])
		var off := at - mid
		var edge := off.length() > r - 10.0 * k
		if edge:
			at = mid + off.normalized() * (r - 10.0 * k)
		_icon(str(m["kind"]), at, k, edge)
	for i in range(tracked.size() - 1, -1, -1):
		var t: Dictionary = tracked[i]
		if not is_instance_valid(t["node"]):
			tracked.remove_at(i)
			continue
		var at := to_map((t["node"] as Node3D).global_position)
		if at.distance_to(mid) < r - 6.0 * k:
			_icon(str(t["kind"]), at, k, false)
	# The waypoint's pin: on the rim, pointing the way, while off the map.
	var gps := Gps.find(get_tree())
	if gps != null and gps.shows_pin():
		var at := to_map(gps.target)
		var off := at - mid
		if off.length() > r - 14.0 * k:
			var dir := off.normalized()
			var tip := mid + dir * (r - 3.0 * k)
			var side := dir.orthogonal()
			_icons.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12.0 * k + side * 7.0 * k, tip - dir * 12.0 * k - side * 7.0 * k]), HudStyle.WAYPOINT)
			_icons.draw_circle(tip - dir * 16.0 * k, 5.5 * k, Color(0, 0, 0, 0.8))
			_icons.draw_circle(tip - dir * 16.0 * k, 3.5 * k, HudStyle.WAYPOINT)
		else:
			MapIcons.pin(_icons, at, k * 0.9)
	# You: an arrow the way you face (up is the camera's way).
	if player != null:
		var face := -player.global_basis.z
		var car: Variant = player.get("vehicle")
		if car is Node3D:
			face = -(car as Node3D).global_basis.z
		var a := (to_map(player.global_position + face) - to_map(player.global_position)).angle() + PI * 0.5
		MapIcons.arrow(_icons, mid, a, k)
	# North on the rim.
	var north := (to_map(player.global_position + Vector3(0, 0, -100)) - mid).normalized() if player != null else Vector2.UP
	var n_at := mid + north * (r - 1.0 * k)
	_icons.draw_circle(n_at, 9.0 * k, Color(0.08, 0.09, 0.1, 0.9))
	var fs := int(15 * k)
	var nw := _font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	_icons.draw_string(_font, n_at + Vector2(-nw.x * 0.5, nw.y * 0.32), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	# The rim: white, red (pulsing) while wanted.
	var rim := RIM
	if alarm:
		rim = RED.lerp(Color(1.0, 0.45, 0.4), 0.5 + 0.5 * sin(_t * 6.0))
	_icons.draw_arc(mid, r - 1.5 * k, 0.0, TAU, 72, rim, 3.0 * k, true)


func _icon(kind: String, at: Vector2, k: float, on_rim: bool) -> void:
	var dark := Color(0, 0, 0, 0.75)
	match kind:
		"car_wash":
			# A droplet.
			var drop := PackedVector2Array([at + Vector2(0, -8.5 * k)])
			for s in 13:
				# Round the bottom from just right of the top to just left of it.
				var a := -PI * 0.5 + 0.6 + (TAU - 1.2) * s / 12.0
				drop.append(at + Vector2(cos(a), sin(a)) * 5.5 * k + Vector2(0, 1.5 * k))
			_icons.draw_circle(at + Vector2(0, 1.5 * k), 7.5 * k, dark)
			_icons.draw_colored_polygon(drop, WASH)
		"police_station":
			# A shield.
			var w := 12.0 * k
			var h := 14.0 * k
			var o := at - Vector2(w, h) * 0.5
			var shield := PackedVector2Array([o + Vector2(w * 0.5, 0), o + Vector2(w, h * 0.12), o + Vector2(w, h * 0.5),
				o + Vector2(w * 0.5, h), o + Vector2(0, h * 0.5), o + Vector2(0, h * 0.12)])
			_icons.draw_circle(at, 9.5 * k, dark)
			_icons.draw_colored_polygon(shield, POLICE_BLUE)
			_icons.draw_circle(at + Vector2(0, -0.5 * k), 2.0 * k, Color.WHITE)
		"police":
			# A unit: flashing red and blue.
			var c := RED if fmod(_t, 0.5) < 0.25 else POLICE_BLUE
			_icons.draw_circle(at, 6.0 * k, dark)
			_icons.draw_circle(at, 4.5 * k, c)
		"fip":
			_icons.draw_rect(Rect2(at - Vector2(6, 6) * k, Vector2(12, 12) * k), dark)
			_icons.draw_rect(Rect2(at - Vector2(4.5, 4.5) * k, Vector2(9, 9) * k), FIP)
		_:
			_icons.draw_circle(at, 5.0 * k, dark)
			_icons.draw_circle(at, 3.5 * k, Color.WHITE)
	if on_rim:
		_icons.draw_arc(at, 10.5 * k, 0.0, TAU, 16, Color(1, 1, 1, 0.5), 1.0 * k)

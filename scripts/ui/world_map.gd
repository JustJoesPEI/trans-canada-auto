class_name WorldMap
extends CanvasLayer
## The town map, full screen: M (or the controller's Share button, or Map
## in the pause menu) opens and closes it. North is up. On it: the streets
## and the water, the named places (data/city/locations.json, made by
## tools/make_locations.py, plus the police station and the car washes the
## game puts on the minimap), you, police units, and the waypoint with the
## way there (Gps).
##
## Mouse: drag to move, wheel to zoom (round the pointer), click a place or
## a street to set the waypoint there, click the waypoint (or right click)
## to clear it; the list on the right picks a place by name, nearest first,
## and the buttons over it narrow it to one kind. Keys: WASD / arrows move,
## + / - zoom. Controller: left stick moves, the triggers zoom, A sets the
## waypoint under the cross in the middle, X clears it, LB / RB jump to the
## previous or next place in the list, B closes.
##
## Shown by default: places you can do something at (the counters: stores,
## job boards, dealers, parking, your place; food pickups; the police and
## the car washes) and the big landmarks to find your way by (parks,
## water, the civic buildings). The rest (churches, schools, banks, other
## brands' gas stations and shops: scenery, design section 6½) are points
## of interest, behind a toggle that's off until you turn it on.
##
## The game is paused while it's open (like the note box).
##
## Drawing cost: like the minimap, the streets are drawn once into cached
## 2D drawing split into tiles (drawn again only when the zoom changes, so
## they keep a width you can see), the water is the minimap's mask
## texture; each frame only the icons and labels in view are drawn.

const LAYER := 70 ## over the HUD, under the pause menu (80)
const TILE := 500.0
const SIDE_WIDTH := 360.0 ## the list on the right (px at 1600 x 900)
## px per metre: the furthest out and in.
const ZOOM_MIN := 0.08
const ZOOM_MAX := 3.0
const ZOOM_START := 0.45
## Zoom at which every place's name shows (otherwise only on hover and the
## big ones: parks, schools, landmarks).
const ALL_NAMES := 0.9
const PAN_SPEED := 900.0 ## px a second with the stick or keys
const CLICK_SLOP := 6.0 ## px a press can move and still be a click
const PICK := 15.0 ## px from an icon that picks it

const BACK := Color(0.05, 0.06, 0.07, 0.97)
const LAND := Color(0.11, 0.12, 0.12)
const STREET := Color(0.62, 0.63, 0.62)
const MINOR := Color(0.38, 0.39, 0.38)
const HIGHWAY := Color(1.0, 0.86, 0.45, 0.95)
const WATER := Color(0.16, 0.32, 0.48)

## What each kind of place looks like: [colour, filter group, label].
const KINDS := {
	"park": [Color(0.36, 0.7, 0.36), "outdoors", "Park"],
	"golf": [Color(0.36, 0.7, 0.36), "outdoors", "Golf course"],
	"cemetery": [Color(0.55, 0.6, 0.58), "outdoors", "Cemetery"],
	"water": [Color(0.3, 0.6, 0.9), "outdoors", "Pond"],
	"marina": [Color(0.3, 0.6, 0.9), "outdoors", "Marina"],
	"sport": [Color(0.3, 0.72, 0.62), "outdoors", "Sports"],
	"school": [Color(0.95, 0.6, 0.25), "landmarks", "School"],
	"landmark": [Color(1.0, 0.86, 0.45), "landmarks", "Landmark"],
	"church": [Color(0.75, 0.62, 0.95), "landmarks", "Church"],
	"coffee": [Color(0.72, 0.5, 0.33), "food", "Coffee"],
	"food": [Color(0.95, 0.42, 0.3), "food", "Food"],
	"grocery": [Color(0.3, 0.78, 0.78), "shops", "Groceries"],
	"shop": [Color(0.3, 0.78, 0.78), "shops", "Shop"],
	"cinema": [Color(0.3, 0.78, 0.78), "shops", "Cinema"],
	"gas": [Color(0.9, 0.3, 0.3), "services", "Gas"],
	"bank": [Color(0.5, 0.8, 0.4), "services", "Bank"],
	"hotel": [Color(0.6, 0.65, 0.95), "services", "Hotel"],
	"dealer": [Color(0.45, 0.65, 1.0), "services", "Car dealer"],
	"car_wash": [Color(0.35, 0.75, 1.0), "services", "Car wash"],
	"police_station": [Color(0.25, 0.45, 1.0), "services", "Police"],
	# The money side (docs/design.md section 6½): where to work, buy, keep cars.
	"job_board": [Color(1.0, 0.86, 0.45), "work", "Jobs"],
	"custom_shop": [Color(0.95, 0.55, 0.2), "services", "Custom shop"],
	"parkade": [Color(0.45, 0.65, 1.0), "services", "Parking"],
	"property": [Color(0.78, 0.49, 1.0), "services", "Your place"],
}
const GROUPS := [["all", "All"], ["work", "Work"], ["landmarks", "Landmarks"], ["outdoors", "Outdoors"], ["food", "Food"], ["shops", "Shops"], ["services", "Services"]]
## Kinds that are only scenery (points of interest, hidden by default)
## unless the game puts a counter there: those come in as game places.
const POI_KINDS := ["church", "school", "cemetery", "bank", "hotel", "gas", "shop", "grocery", "cinema"]
## Kinds whose names show zoomed out.
const BIG := ["park", "school", "landmark", "golf", "marina", "sport", "water", "police_station"]

## The town and the player.
var world: Node
var player: Node3D
var gps: Gps
var minimap: Minimap
## Is it up?
var is_open := false
## Every place: {name, kind, at: Vector2}.
var places: Array[Dictionary] = []
## px per metre now, and the world point (x, z) in the middle of the view.
var zoom := ZOOM_START
var centre := Vector2.ZERO
## The player last used a controller.
var pad := false

var _root: Control
var _view: Control ## the map area (clips)
var _cam: Node2D ## world -> view
var _tiles: Array[Node2D] = []
var _water: Node2D
var _route: Node2D
var _overlay: Control
var _side: PanelContainer
var _list: Tree
var _list_places: Array[Dictionary] = [] ## what each list row is
var _group := "all"
var _group_buttons := {}
## Points of interest shown too (the toggle).
var show_poi := false
var _poi_button: Button
var _wp_name: Label
var _wp_dist: Label
var _wp_clear: Button
var _hint: Label
var _street_label: Label
var _font: Font
var _drawn_zoom := -1.0
var _dragging := false
var _press_at := Vector2.ZERO
var _press_centre := Vector2.ZERO
var _pressed := false
var _hover := -1 ## index in places under the pointer
var _list_pick := -1
var _was_captured := false
var _was_paused := false
var _built := false
var _dot_textures := {}
var _tab_bar: HBoxContainer
var _tab_buttons := {}
var _tabs := {} ## id -> {title, build: Callable(VBoxContainer)}
var _tab := "places"
var _places_box: VBoxContainer
var _tab_scroll: ScrollContainer
var _tab_box: VBoxContainer


static func find(tree: SceneTree) -> WorldMap:
	return tree.get_first_node_in_group("world_map") as WorldMap if tree != null else null


func _ready() -> void:
	add_to_group("world_map")
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = HudStyle.heading_font()
	_build_ui()
	visible = false


func setup(w: Node, who: Node3D, g: Gps, mm: Minimap) -> void:
	world = w
	player = who
	gps = g
	minimap = mm
	if gps != null:
		gps.changed.connect(_on_gps)
	if w != null and bool(w.get("is_built")):
		_build_map()
	elif w != null and w.has_signal("built"):
		w.connect("built", _build_map, CONNECT_ONE_SHOT)


# --- opening and closing -----------------------------------------------------------------------

## Something else has the screen (the pause menu, the note box, the
## character creator, the loading screen): the map stays shut.
func _blocked() -> bool:
	var tree := get_tree()
	var menu := tree.root.get_node_or_null("TitleMenu")
	if menu != null and (bool(menu.get("_open")) or (menu.get("_loading") is Control and (menu.get("_loading") as Control).visible)):
		return true
	var notes := tree.root.get_node_or_null("FieldNotes")
	if notes != null and notes.get("_panel") is Control and (notes.get("_panel") as Control).visible:
		return true
	return tree.paused and not is_open


func open() -> void:
	if is_open or _blocked():
		return
	is_open = true
	visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout()
	if player != null and is_instance_valid(player):
		centre = _here()
	if gps != null and gps.active:
		# Both you and the waypoint in view, if they fit.
		var t := Vector2(gps.target.x, gps.target.z)
		var span := (t - centre).abs() * 2.0 + Vector2(300, 300)
		zoom = clampf(minf(_view.size.x / span.x, _view.size.y / span.y), ZOOM_MIN, ZOOM_START)
		centre = (centre + t) * 0.5
	_fill_list()
	refresh_tab()
	_update_waypoint_panel()
	_update_hint()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = _was_paused
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


# --- input -------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		if not pad:
			pad = true
			_update_hint()
	elif event is InputEventKey or event is InputEventMouseButton:
		if pad:
			pad = false
			_update_hint()
	if not is_open:
		if event.is_action_pressed("map") and not _blocked():
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause") or (event is InputEventJoypadButton and event.is_pressed() and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.is_pressed():
		var bi := (event as InputEventJoypadButton).button_index
		if bi == JOY_BUTTON_DPAD_LEFT or bi == JOY_BUTTON_DPAD_RIGHT:
			_step_tab(-1 if bi == JOY_BUTTON_DPAD_LEFT else 1)
			get_viewport().set_input_as_handled()
			return
		if _tab != "places" and bi in [JOY_BUTTON_A, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			return # the tab's buttons: focus moves with the D-pad, A presses
		match bi:
			JOY_BUTTON_A:
				_click(_view.size * 0.5)
			JOY_BUTTON_X:
				if gps != null:
					gps.clear()
			JOY_BUTTON_RIGHT_SHOULDER:
				_step_list(1)
			JOY_BUTTON_LEFT_SHOULDER:
				_step_list(-1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.is_pressed():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_EQUAL or k == KEY_KP_ADD:
			_zoom_at(_view.size * 0.5, 1.35)
		elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
			_zoom_at(_view.size * 0.5, 1.0 / 1.35)
		elif k == KEY_C or k == KEY_HOME:
			centre = _here()
		elif k == KEY_DELETE or k == KEY_BACKSPACE:
			if gps != null:
				gps.clear()


func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.2)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_at = mb.position
				_press_centre = centre
			else:
				if _pressed and not _dragging:
					_click(mb.position)
				_pressed = false
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if gps != null:
				gps.clear()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed and (mm.position - _press_at).length() > CLICK_SLOP:
			_dragging = true
		if _dragging:
			centre = _press_centre - (mm.position - _press_at) / zoom
		_hover = _place_at(mm.position)


func _zoom_at(at: Vector2, factor: float) -> void:
	var before := _to_world(at)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	centre += before - _to_world(at)


## A click (or A) at `at` in the view: on the waypoint, clears it; on a
## place, sets it there; elsewhere, on the nearest street.
func _click(at: Vector2) -> void:
	if gps == null:
		return
	if gps.active and _to_view(Vector2(gps.target.x, gps.target.z)).distance_to(at) < PICK:
		gps.clear()
		return
	var i := _place_at(at)
	if i >= 0:
		_set_to(places[i])
		return
	var p := _to_world(at)
	var name := ""
	var net: RoadNetwork = world.get("network") if world != null else null
	if net != null:
		var hit := net.nearest_on_streets(p, maxf(30.0, 24.0 / zoom))
		if not hit.is_empty():
			p = hit["pos"]
			name = (hit["edge"] as RoadNetwork.RoadEdge).name
	gps.set_waypoint(Vector3(p.x, _ground_y(p), p.y), name)


func _set_to(place: Dictionary) -> void:
	var at: Vector2 = place["at"]
	gps.set_waypoint(Vector3(at.x, _ground_y(at), at.y), str(place["name"]))


func _ground_y(p: Vector2) -> float:
	var terrain: Terrain = world.get("terrain") if world != null else null
	return terrain.height_at(p.x, p.y) if terrain != null and terrain.nx > 0 else 0.0


func _step_list(d: int) -> void:
	if _list_places.is_empty():
		return
	_list_pick = posmod(_list_pick + d, _list_places.size())
	var row := _list.get_root().get_child(_list_pick)
	row.select(0)
	_list.scroll_to_item(row)
	centre = _list_places[_list_pick]["at"]
	zoom = maxf(zoom, 0.6)


func _on_list_clicked(_at: Vector2, button: int) -> void:
	var row := _list.get_selected()
	var index := row.get_index() if row != null else -1
	if button != MOUSE_BUTTON_LEFT or index < 0 or index >= _list_places.size():
		return
	_list_pick = index
	var place := _list_places[index]
	centre = place["at"]
	zoom = maxf(zoom, 0.6)
	if gps != null:
		_set_to(place)


# --- each frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	# Stick and keys move the map.
	var move := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back"))
	if move.length() > 0.05:
		centre += move * PAN_SPEED * delta / zoom
	var zin := Input.get_action_strength("accelerate") if pad else 0.0
	var zout := Input.get_action_strength("brake_reverse") if pad else 0.0
	if zin - zout != 0.0:
		_zoom_at(_view.size * 0.5, pow(3.0, (zin - zout) * delta))
	if pad:
		_hover = _place_at(_view.size * 0.5)
	_clamp_centre()
	_cam.position = _view.size * 0.5 - centre * zoom
	_cam.scale = Vector2.ONE * zoom
	if not is_equal_approx(zoom, _drawn_zoom):
		# Streets keep a width you can see: drawn again at this zoom.
		_drawn_zoom = zoom
		for t in _tiles:
			t.queue_redraw()
		_route.queue_redraw()
	_overlay.queue_redraw()
	_update_waypoint_panel()


## Keeps the view on the mapped ground: no further out than the elevation
## data reaches (the water is only known inside it, so past its edge the
## map would show a hard line where the sea stops), and the centre where
## the view stays inside it.
func _clamp_centre() -> void:
	var r := _extent()
	if r.size.x <= 0.0 or _view.size.x <= 0.0:
		return
	zoom = clampf(maxf(zoom, maxf(_view.size.x / r.size.x, _view.size.y / r.size.y)), ZOOM_MIN, ZOOM_MAX)
	var half := _view.size * 0.5 / zoom
	for axis in 2:
		var lo := r.position[axis] + half[axis]
		var hi := r.end[axis] - half[axis]
		centre[axis] = r.get_center()[axis] if lo > hi else clampf(centre[axis], lo, hi)


## The mapped ground (x, z): the elevation data's extent, or without it
## the play area's.
func _extent() -> Rect2:
	var terrain: Terrain = world.get("terrain") if world != null else null
	if terrain != null and terrain.nx > 1 and terrain.nz > 1:
		return Rect2(terrain.origin, Vector2(terrain.nx - 1, terrain.nz - 1) * terrain.spacing)
	var b := _bounds()
	return b.grow(500.0) if b.size.x > 0.0 else Rect2()


## The play area's extent (x, z), or an empty rect.
func _bounds() -> Rect2:
	var ring: PackedVector2Array = world.get("boundary") if world != null and world.get("boundary") != null else PackedVector2Array()
	if ring.size() > 2:
		var r := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			r = r.expand(p)
		return r
	return Rect2()


func _here() -> Vector2:
	if player == null or not is_instance_valid(player):
		return centre
	var p := player.global_position
	return Vector2(p.x, p.z)


func _to_view(p: Vector2) -> Vector2:
	return (p - centre) * zoom + _view.size * 0.5


func _to_world(v: Vector2) -> Vector2:
	return (v - _view.size * 0.5) / zoom + centre


func _place_at(at: Vector2) -> int:
	var best := -1
	var best_d := PICK
	for i in places.size():
		if not _shown(places[i]):
			continue
		var d := _to_view(places[i]["at"]).distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


func _shown(place: Dictionary) -> bool:
	if not show_poi and is_poi(place):
		return false
	return _group == "all" or _group_of(str(place["kind"])) == _group


## A place that's only scenery: hidden unless points of interest are on.
static func is_poi(place: Dictionary) -> bool:
	return not bool(place.get("game", false)) and POI_KINDS.has(str(place["kind"]))


func set_show_poi(on: bool) -> void:
	show_poi = on
	if _poi_button != null:
		_poi_button.set_pressed_no_signal(on)
	_fill_list()
	if _overlay != null:
		_overlay.queue_redraw()


static func _group_of(kind: String) -> String:
	return str((KINDS.get(kind, [Color.WHITE, "services", ""]) as Array)[1])


static func kind_colour(kind: String) -> Color:
	return (KINDS.get(kind, [Color.WHITE]) as Array)[0]


func _on_gps() -> void:
	if _route != null:
		_route.queue_redraw()
	if is_open:
		_update_waypoint_panel()


# --- the map, drawn once (and again on a zoom) ---------------------------------------------------

func _build_map() -> void:
	if _built:
		return
	_built = true
	var net: RoadNetwork = world.get("network") if world != null else null
	if net != null:
		var tiles := {}
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
			# Lanes first, then streets, highways on top.
			list.sort_custom(func(a: RoadNetwork.RoadEdge, b: RoadNetwork.RoadEdge) -> bool: return _rank(a) < _rank(b))
			node.draw.connect(func() -> void:
				var px := 1.0 / maxf(zoom, 0.0001) # metres per pixel
				for e: RoadNetwork.RoadEdge in list:
					var col := HIGHWAY if e.is_highway() else (MINOR if e.minor else STREET)
					var least := (2.6 if e.is_highway() else (1.0 if e.minor else 1.6)) * px
					node.draw_polyline(e.points, col, maxf(least, e.half_width * 2.0), true))
			_cam.add_child(node)
			_tiles.append(node)
	_route = Node2D.new()
	_route.name = "Route"
	_route.draw.connect(_draw_route)
	_cam.add_child(_route)
	_load_places()


static func _rank(e: RoadNetwork.RoadEdge) -> int:
	return 0 if e.minor else (2 if e.is_highway() else 1)


## The water: the minimap's mask, once it's made (it's made off the main
## thread while the town loads).
func _poll_water() -> void:
	if _water != null or minimap == null or minimap.water_texture == null:
		return
	var tex := minimap.water_texture
	var rect := minimap.water_rect
	_water = Node2D.new()
	_water.name = "Water"
	_water.draw.connect(func() -> void: _water.draw_texture_rect(tex, rect, false, WATER))
	_cam.add_child(_water)
	_cam.move_child(_water, 0)


func _load_places() -> void:
	places.clear()
	var dir := "res://data/city"
	var data: Variant = world.get("data") if world != null else null
	if data is StreetData and (data as StreetData).city_dir != "":
		dir = (data as StreetData).city_dir
	var f := FileAccess.open(dir.path_join("locations.json"), FileAccess.READ)
	if f != null:
		var j: Variant = JSON.parse_string(f.get_as_text())
		if j is Dictionary:
			for e: Dictionary in (j as Dictionary).get("locations", []):
				var at := Vector2(float(e["x"]), float(e["z"]))
				if world != null and world.has_method("is_in_play_area") and not bool(world.call("is_in_play_area", at)):
					continue
				places.append({"name": str(e["name"]), "kind": str(e["kind"]), "at": at})
	_add_game_places()


## The places the game itself marks: the police station and car washes
## (from the minimap's markers, as they're placed).
func _add_game_places() -> void:
	for i in range(places.size() - 1, -1, -1):
		if bool(places[i].get("game", false)):
			places.remove_at(i)
	var counters := Counters.find(get_tree())
	if counters != null:
		for pl in counters.map_places():
			if KINDS.has(str(pl["kind"])):
				places.append(pl)
				# The same place from locations.json goes: the counter's is the one.
				for i in range(places.size() - 2, -1, -1):
					var o := places[i]
					if not bool(o.get("game", false)) and str(o["name"]) == str(pl["name"]) and (o["at"] as Vector2).distance_to(pl["at"]) < 120.0:
						places.remove_at(i)
	if minimap == null:
		return
	var washes := 0
	for id: String in minimap.markers:
		var m: Dictionary = minimap.markers[id]
		var kind := str(m["kind"])
		if not KINDS.has(kind):
			continue
		var at3: Vector3 = m["at"]
		var name := "Charlatown Police Services" if kind == "police_station" else str(KINDS[kind][2])
		if kind == "car_wash":
			washes += 1
			name = "Car wash %d" % washes if minimap.markers.size() > 2 else "Car wash"
		places.append({"name": name, "kind": kind, "at": Vector2(at3.x, at3.z), "game": true})


# --- drawing each frame ------------------------------------------------------------------------

func _draw_route() -> void:
	if gps == null or not gps.shows_route():
		return
	var px := 1.0 / maxf(zoom, 0.0001)
	var pts := gps.route_ahead()
	if pts.size() > 1:
		_route.draw_polyline(pts, Color(0, 0, 0, 0.6), 8.0 * px, true)
		_route.draw_polyline(pts, HudStyle.WAYPOINT, 5.0 * px, true)


func _draw_overlay() -> void:
	_poll_water()
	var k := _root.size.y / 900.0
	var view := Rect2(Vector2.ZERO, _view.size).grow(20.0)
	var names := zoom >= ALL_NAMES
	var fs := int(15 * k)
	# Places: icons, and names where they fit: the one under the pointer
	# first, then the big ones (parks, schools, landmarks), then the rest
	# zoomed in; a name that would cover one already drawn is left off.
	var on_screen: Array[int] = []
	for i in places.size():
		var pl := places[i]
		if _shown(pl) and view.has_point(_to_view(pl["at"])):
			on_screen.append(i)
			MapIcons.draw(_overlay, str(pl["kind"]), _to_view(pl["at"]), k * (1.25 if i == _hover else 1.0), _font)
	on_screen.sort_custom(func(a: int, b: int) -> bool: return _label_rank(a) < _label_rank(b))
	var taken: Array[Rect2] = []
	for i in on_screen:
		var pl := places[i]
		var hot := i == _hover
		if not (hot or names or (BIG.has(str(pl["kind"])) and zoom >= 0.3)):
			continue
		var size := fs if not hot else int(fs * 1.15)
		var text := str(pl["name"])
		var at := _to_view(pl["at"]) + Vector2(12 * k, 5 * k)
		var box := Rect2(at + Vector2(-2, -size * 0.8), _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size) + Vector2(4, 2))
		var clear := true
		for r in taken:
			if r.intersects(box):
				clear = false
				break
		if clear or hot:
			taken.append(box)
			_name(text, at, size, Color.WHITE if hot else Color(1, 1, 1, 0.85))
	# Police units.
	if minimap != null:
		for t: Dictionary in minimap.tracked:
			if not is_instance_valid(t["node"]):
				continue
			var p := (t["node"] as Node3D).global_position
			var at := _to_view(Vector2(p.x, p.z))
			if view.has_point(at):
				_overlay.draw_circle(at, 6.0 * k, Color(0, 0, 0, 0.75))
				_overlay.draw_circle(at, 4.5 * k, Minimap.RED if str(t["kind"]) == "police" else Minimap.FIP)
		# The search circle.
		if minimap.search_radius > 0.0:
			var c := _to_view(Vector2(minimap.search_centre.x, minimap.search_centre.z))
			_overlay.draw_circle(c, minimap.search_radius * zoom, Color(Minimap.RED, 0.18))
			_overlay.draw_arc(c, minimap.search_radius * zoom, 0.0, TAU, 64, Minimap.RED, 2.0, true)
	# The waypoint.
	if gps != null and gps.shows_pin():
		var w := _to_view(Vector2(gps.target.x, gps.target.z))
		MapIcons.pin(_overlay, w, k * 1.2)
	# You.
	if player != null and is_instance_valid(player):
		var face := -player.global_basis.z
		var car: Variant = player.get("vehicle")
		if car is Node3D:
			face = -(car as Node3D).global_basis.z
		MapIcons.arrow(_overlay, _to_view(_here()), Vector2(face.x, face.z).angle() + PI * 0.5, k * 1.2)
	# The controller's cross in the middle.
	if pad:
		var m := _view.size * 0.5
		for d: Vector2 in [Vector2(1, 0), Vector2(0, 1)]:
			_overlay.draw_line(m - d * 14.0 * k, m - d * 5.0 * k, Color.WHITE, 2.0)
			_overlay.draw_line(m + d * 5.0 * k, m + d * 14.0 * k, Color.WHITE, 2.0)
	_draw_scale(k)


## Which names go on first: the one under the pointer, then the big kinds.
func _label_rank(i: int) -> int:
	if i == _hover:
		return 0
	return 1 if BIG.has(str(places[i]["kind"])) else 2


func _name(text: String, at: Vector2, size: int, colour: Color) -> void:
	_overlay.draw_string_outline(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.85))
	_overlay.draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


## A scale bar and N, bottom left of the view.
func _draw_scale(k: float) -> void:
	var metres := 50.0
	for m: float in [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0]:
		if m * zoom <= 160.0 * k:
			metres = m
	var o := Vector2(28 * k, _view.size.y - 30 * k)
	var w := metres * zoom
	_overlay.draw_rect(Rect2(o + Vector2(-8, -24) * k, Vector2(w + 16 * k, 34 * k)), Color(0, 0, 0, 0.45))
	_overlay.draw_line(o, o + Vector2(w, 0), Color.WHITE, 2.0)
	_overlay.draw_line(o + Vector2(0, -6 * k), o + Vector2(0, 2 * k), Color.WHITE, 2.0)
	_overlay.draw_line(o + Vector2(w, -6 * k), o + Vector2(w, 2 * k), Color.WHITE, 2.0)
	_overlay.draw_string(_font, o + Vector2(0, -9 * k), HudStyle.distance_text(metres), HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), Color.WHITE)
	var n := Vector2(_view.size.x - 34 * k, 40 * k)
	_overlay.draw_circle(n, 16 * k, Color(0, 0, 0, 0.55))
	_overlay.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -12) * k, n + Vector2(6, 2) * k, n + Vector2(-6, 2) * k]), Minimap.RED)
	var nw := _font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k))
	_overlay.draw_string(_font, n + Vector2(-nw.x * 0.5, 13 * k), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), Color.WHITE)


# --- the panel on the right --------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = BACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	_view = Control.new()
	_view.name = "View"
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_view_input)
	_view.draw.connect(func() -> void: _view.draw_rect(Rect2(Vector2.ZERO, _view.size), LAND))
	_root.add_child(_view)
	_cam = Node2D.new()
	_cam.name = "Camera"
	_view.add_child(_cam)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_view.add_child(_overlay)

	_side = PanelContainer.new()
	_side.name = "Side"
	var sb := HudStyle.panel()
	sb.set_corner_radius_all(0)
	sb.bg_color = Color(0.07, 0.08, 0.09, 0.98)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_side.add_theme_stylebox_override("panel", sb)
	_root.add_child(_side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_side.add_child(col)
	var title := HudStyle.label(44, true, Color.WHITE, false)
	title.text = "Charlatown"
	col.add_child(title)
	_street_label = HudStyle.label(16, false, HudStyle.DIM, false)
	col.add_child(_street_label)

	# The waypoint.
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.WAYPOINT))
	col.add_child(wp)
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 2)
	wp.add_child(wcol)
	var whead := HBoxContainer.new()
	wcol.add_child(whead)
	var wl := HudStyle.label(15, true, HudStyle.WAYPOINT, false)
	wl.text = "Waypoint"
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	whead.add_child(wl)
	_wp_clear = _small_button("Clear", func() -> void:
		if gps != null:
			gps.clear())
	whead.add_child(_wp_clear)
	_wp_name = HudStyle.label(22, true, Color.WHITE, false)
	_wp_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wcol.add_child(_wp_name)
	_wp_dist = HudStyle.label(15, false, HudStyle.DIM, false)
	wcol.add_child(_wp_dist)

	# Tabs: Places (the list below), and whatever the money side adds
	# (add_tab). The bar shows once there's more than one.
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	_tab_bar.visible = false
	col.add_child(_tab_bar)
	var places_tab := _small_button("Places", func() -> void: show_tab("places"))
	places_tab.toggle_mode = true
	places_tab.button_pressed = true
	_tab_buttons["places"] = places_tab
	_tab_bar.add_child(places_tab)
	_places_box = VBoxContainer.new()
	_places_box.add_theme_constant_override("separation", 10)
	_places_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_places_box)
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_scroll.visible = false
	col.add_child(_tab_scroll)
	_tab_box = VBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 8)
	_tab_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_scroll.add_child(_tab_box)

	# The kinds.
	var groups := HFlowContainer.new()
	groups.add_theme_constant_override("h_separation", 6)
	groups.add_theme_constant_override("v_separation", 6)
	_places_box.add_child(groups)
	for g: Array in GROUPS:
		var id := str(g[0])
		var b := _small_button(str(g[1]), func() -> void: _set_group(id))
		b.toggle_mode = true
		b.button_pressed = id == _group
		_group_buttons[id] = b
		groups.add_child(b)
	_poi_button = _small_button("Points of interest", func() -> void: set_show_poi(_poi_button.button_pressed))
	_poi_button.toggle_mode = true
	_poi_button.button_pressed = show_poi
	_poi_button.tooltip_text = "Churches, schools, banks and other places that are only scenery"
	groups.add_child(_poi_button)

	_list = Tree.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.focus_mode = Control.FOCUS_NONE
	_list.columns = 2
	_list.hide_root = true
	_list.select_mode = Tree.SELECT_ROW
	_list.scroll_horizontal_enabled = false
	_list.set_column_expand(0, true)
	_list.set_column_expand(1, false)
	_list.set_column_custom_minimum_width(1, 74)
	_list.add_theme_font_size_override("font_size", 16)
	_list.add_theme_color_override("font_color", Color(0.92, 0.93, 0.94))
	_list.add_theme_color_override("font_hovered_color", Color.WHITE)
	_list.add_theme_color_override("font_selected_color", Color.WHITE)
	var empty := StyleBoxEmpty.new()
	_list.add_theme_stylebox_override("panel", empty)
	_list.add_theme_stylebox_override("focus", empty)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.07)
	hover.set_corner_radius_all(5)
	_list.add_theme_stylebox_override("hovered", hover)
	var sel := StyleBoxFlat.new()
	sel.bg_color = Color(HudStyle.WAYPOINT, 0.3)
	sel.set_corner_radius_all(5)
	_list.add_theme_stylebox_override("selected", sel)
	_list.add_theme_stylebox_override("selected_focus", sel)
	_list.add_theme_constant_override("v_separation", 8)
	_list.add_theme_constant_override("h_separation", 8)
	_list.add_theme_constant_override("item_margin", 0)
	_list.add_theme_constant_override("inner_item_margin_left", 4)
	_list.add_theme_constant_override("inner_item_margin_right", 4)
	_list.add_theme_constant_override("draw_guides", 0)
	_list.add_theme_constant_override("draw_relationship_lines", 0)
	_list.item_mouse_selected.connect(_on_list_clicked)
	_places_box.add_child(_list)

	_hint = HudStyle.label(14, false, HudStyle.DIM, false)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	get_viewport().size_changed.connect(_layout)
	_layout()


# --- tabs --------------------------------------------------------------------------------------

## A tab on the map's side panel (apps go on the Phone): `build` is called
## with an empty VBoxContainer each time the tab is shown (and on
## refresh_tab), to fill it. Use make_button for buttons in it.
func add_tab(id: String, title: String, build: Callable) -> void:
	_tabs[id] = {"title": title, "build": build}
	if not _tab_buttons.has(id):
		var b := _small_button(title, func() -> void: show_tab(id))
		b.toggle_mode = true
		_tab_buttons[id] = b
		_tab_bar.add_child(b)
	_tab_bar.visible = true


func remove_tab(id: String) -> void:
	_tabs.erase(id)
	if _tab_buttons.has(id):
		(_tab_buttons[id] as Button).queue_free()
		_tab_buttons.erase(id)
	if _tab == id:
		show_tab("places")
	_tab_bar.visible = _tabs.size() > 0


func show_tab(id: String) -> void:
	if id != "places" and not _tabs.has(id):
		id = "places"
	_tab = id
	for t: String in _tab_buttons:
		(_tab_buttons[t] as Button).set_pressed_no_signal(t == id)
	_places_box.visible = id == "places"
	_tab_scroll.visible = id != "places"
	refresh_tab()


## The tab shown now ("places" for the list of places).
func current_tab() -> String:
	return _tab


## Builds the shown tab again (after something in it changed).
func refresh_tab() -> void:
	if _tab == "places":
		return
	for c in _tab_box.get_children():
		_tab_box.remove_child(c)
		c.queue_free()
	var t: Dictionary = _tabs.get(_tab, {})
	var build: Variant = t.get("build")
	if build is Callable and (build as Callable).is_valid():
		(build as Callable).call(_tab_box)
	if pad:
		for c in _tab_box.find_children("*", "Button", true, false):
			(c as Button).grab_focus.call_deferred()
			break


func _step_tab(d: int) -> void:
	var ids: Array = ["places"]
	ids.append_array(_tabs.keys())
	if ids.size() < 2:
		return
	show_tab(ids[posmod(ids.find(_tab) + d, ids.size())])


## A button for a tab, in the map's style; works with the mouse and, on a
## controller, with the D-pad and A.
func make_button(text: String, action: Callable) -> Button:
	var b := _small_button(text, action)
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(HudStyle.ACCENT, 0.35)
	focus.set_corner_radius_all(5)
	focus.content_margin_left = 10
	focus.content_margin_right = 10
	focus.content_margin_top = 3
	focus.content_margin_bottom = 2
	b.add_theme_stylebox_override("focus", focus)
	return b


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HudStyle.heading_font())
	b.add_theme_font_size_override("font_size", 17)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	normal.content_margin_top = 3
	normal.content_margin_bottom = 2
	var hot := normal.duplicate() as StyleBoxFlat
	hot.bg_color = Color(1, 1, 1, 0.16)
	var on := normal.duplicate() as StyleBoxFlat
	on.bg_color = HudStyle.ACCENT
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.1, 0.1))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.1, 0.1, 0.1))
	b.pressed.connect(action)
	return b


func _set_group(id: String) -> void:
	_group = id
	for g: String in _group_buttons:
		(_group_buttons[g] as Button).set_pressed_no_signal(g == id)
	_fill_list()


func _layout() -> void:
	if _root == null or not is_inside_tree():
		return
	var vp := get_viewport().get_visible_rect().size
	var k := vp.y / 900.0
	var side := SIDE_WIDTH * k
	_view.position = Vector2.ZERO
	_view.size = Vector2(vp.x - side, vp.y)
	_side.position = Vector2(vp.x - side, 0)
	_side.size = Vector2(side, vp.y)
	_view.queue_redraw()


## The list: every place of the kind picked, nearest first.
func _fill_list() -> void:
	_add_game_places()
	var here := _here()
	_list_places = []
	for pl in places:
		if _shown(pl):
			_list_places.append(pl)
	_list_places.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["at"] as Vector2).distance_squared_to(here) < (b["at"] as Vector2).distance_squared_to(here))
	_list.clear()
	var top := _list.create_item()
	for pl in _list_places:
		var d := (pl["at"] as Vector2).distance_to(here)
		var row := _list.create_item(top)
		row.set_text(0, str(pl["name"]))
		row.set_icon(0, _dot(str(pl["kind"])))
		row.set_tooltip_text(0, "%s  ·  %s" % [pl["name"], KINDS.get(str(pl["kind"]), [0, 0, ""])[2]])
		row.set_text(1, HudStyle.distance_text(d))
		row.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		row.set_custom_color(1, HudStyle.DIM)
	_list_pick = -1
	if world != null and world.has_method("street_name_at") and bool(world.get("is_built")):
		var s := str(world.call("street_name_at", here))
		_street_label.text = ("You're on %s" % s) if s != "" else ""


## A small round swatch of a kind's colour, for the list.
func _dot(kind: String) -> Texture2D:
	if _dot_textures.has(kind):
		return _dot_textures[kind]
	var n := 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := kind_colour(kind)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(n, n) * 0.5)
			img.set_pixel(x, y, Color(c, clampf(n * 0.5 - d, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_dot_textures[kind] = tex
	return tex


func _update_waypoint_panel() -> void:
	var on := gps != null and gps.active
	_wp_clear.visible = on
	if not on:
		_wp_name.text = "None set"
		_wp_dist.text = "Click a place or a street" if not pad else "Press A on a place or a street"
		return
	_wp_name.text = gps.title()
	if not gps.shows_pin():
		_wp_dist.text = "Find it by the street signs"
		return
	var how := "along the streets" if gps.route.size() > 1 else "as the crow flies"
	_wp_dist.text = "%s %s" % [HudStyle.distance_text(gps.remaining), how]


func _update_hint() -> void:
	if _hint == null:
		return
	if pad:
		_hint.text = "Left stick move  ·  LT / RT zoom  ·  A set waypoint  ·  X clear  ·  LB / RB next place  ·  B close"
	else:
		_hint.text = "Drag move  ·  Wheel zoom  ·  Click set waypoint  ·  Right click clear  ·  C centre on you  ·  M / Esc close"
	_update_waypoint_panel()

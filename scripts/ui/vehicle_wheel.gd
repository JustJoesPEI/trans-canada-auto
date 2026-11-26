class_name VehicleWheel
extends Control
## The vehicle wheel: in the driver's seat, holding the Weapon wheel key
## (Tab, or LB on a controller) brings up this wheel in its place, with the
## things a driver does now and then: wipers, the police lights, hitching
## a trailer or a tow strap, strapping the load down, switching seats, and
## the phone and the map (the D-pad works a working vehicle's tool, so
## they're here too). Point with the mouse or the right stick (the left
## one still steers) and let go to do it; let go in the middle to do
## nothing. Time runs at SLOW_TIME while it's up and the view holds still,
## like the weapon wheel (scripts/paint/weapon_wheel.gd), whose look it
## shares.
##
## What's on it comes from `entries` (main.gd): an Array of {id, title,
## sub, enabled}, asked for each time it opens. Picking one emits chosen.

signal chosen(id: String)

const SLOW_TIME := 0.4
## px at 1600 x 900: the wheel's outer and inner radius.
const OUTER := 210.0
const INNER := 92.0
const MOUSE_PICK := 24.0
const STICK_PICK := 0.45
const NAME_FONT := "res://branding/fonts/BebasNeue-Regular.ttf"
const PANEL := Color(0.08, 0.09, 0.1, 0.86)
const PANEL_LIT := Color(0.18, 0.2, 0.22, 0.94)
const GOLD := Color(1.0, 0.86, 0.45)

var player: Node3D
## Asked for the slots each time it opens: () -> Array of {id, title, sub, enabled}.
var entries: Callable
var is_open := false
## The slot pointed at, or -1.
var pointed := -1
var slots: Array = []

var _mouse := Vector2.ZERO
var _font: Font
var _time_before := 1.0
var _camera_was := true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FontVariation.new()
	f.base_font = load(NAME_FONT) as Font
	f.spacing_glyph = 1
	_font = f
	visible = false


func setup(who: Node3D, list: Callable) -> void:
	player = who
	entries = list


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var held := InputMap.has_action("weapon_wheel") and Input.is_action_pressed("weapon_wheel") and get_tree().paused == false
	if held and not is_open and can_open():
		open()
	elif is_open and (not held or not can_open()):
		close(not held)
	if not is_open:
		return
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.0)
	if stick.length() > STICK_PICK:
		pointed = slot_at(stick)
	elif _mouse.length() > MOUSE_PICK:
		pointed = slot_at(_mouse)
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_mouse += (event as InputEventMouseMotion).relative
		if _mouse.length() > OUTER:
			_mouse = _mouse.normalized() * OUTER
		get_viewport().set_input_as_handled() # the view holds still


## In the driver's seat, not out.
func can_open() -> bool:
	if player.has_method("is_out") and bool(player.call("is_out")):
		return false
	for card in get_tree().get_nodes_in_group("counter_menu"):
		if (card as CanvasLayer).visible:
			return false # LB closes the till's card at a drive-thru
	return player.get("vehicle") != null and not bool(player.get("passenger"))


func open() -> void:
	slots = entries.call() if entries.is_valid() else []
	if slots.is_empty():
		return
	is_open = true
	visible = true
	_mouse = Vector2.ZERO
	pointed = -1
	_time_before = Engine.time_scale
	Engine.time_scale = SLOW_TIME
	var rig: Node = player.get("camera_rig")
	if rig != null:
		_camera_was = rig.is_processing()
		rig.set_process(false)
	queue_redraw()


## Put it away; `take` does the one pointed at (if it can be done now).
func close(take := true) -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	Engine.time_scale = _time_before
	var rig: Node = player.get("camera_rig")
	if rig != null:
		rig.set_process(_camera_was)
	if take and pointed >= 0 and pointed < slots.size() and bool(slots[pointed].get("enabled", true)):
		chosen.emit(str(slots[pointed]["id"]))


## Which slot a direction points at (x right, y down, as on screen).
func slot_at(dir: Vector2) -> int:
	var n := maxi(1, slots.size())
	var a := fposmod(atan2(dir.x, -dir.y), TAU)
	return int(roundf(a / (TAU / n))) % n


func _draw() -> void:
	if not is_open:
		return
	var area := size if size.x > 1.0 and size.y > 1.0 else get_viewport_rect().size
	var k := minf(area.x / 1600.0, area.y / 900.0)
	var mid := area * 0.5
	var n := slots.size()
	var step := TAU / n
	draw_circle(mid, (OUTER + 26.0) * k, Color(0, 0, 0, 0.25))
	for i in n:
		var e: Dictionary = slots[i]
		var on := bool(e.get("enabled", true))
		var lit := i == pointed
		var a0 := -PI * 0.5 + (i - 0.5) * step + 0.03
		var a1 := -PI * 0.5 + (i + 0.5) * step - 0.03
		var poly := PackedVector2Array()
		for s in 13:
			poly.append(mid + Vector2.from_angle(lerpf(a0, a1, s / 12.0)) * OUTER * k)
		for s in 13:
			poly.append(mid + Vector2.from_angle(lerpf(a1, a0, s / 12.0)) * INNER * k)
		draw_colored_polygon(poly, PANEL_LIT if lit else PANEL)
		var edge := poly.duplicate()
		edge.append(poly[0])
		draw_polyline(edge, Color(1, 1, 1, 0.9) if lit else Color(1, 1, 1, 0.18), 2.0 if lit else 1.0, true)
		var at := mid + Vector2.from_angle(-PI * 0.5 + i * step) * (INNER + OUTER) * 0.5 * k
		var title := str(e["title"]).to_upper()
		var fs := int((24 if n <= 6 else 21) * k)
		var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, at + Vector2(-tw * 0.5, 0.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if on else Color(1, 1, 1, 0.35))
	# The middle: the pointed one's name and what it does now.
	draw_circle(mid, (INNER - 8.0) * k, Color(0.05, 0.06, 0.07, 0.82))
	if pointed >= 0 and pointed < n:
		var e: Dictionary = slots[pointed]
		var title := str(e["title"]).to_upper()
		var fs := int(22 * k)
		var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, mid + Vector2(-tw * 0.5, -14.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GOLD if bool(e.get("enabled", true)) else Color(1, 1, 1, 0.5))
		draw_multiline_string(ThemeDB.fallback_font, mid + Vector2(-(INNER - 20.0) * k, 8.0 * k), str(e.get("sub", "")), HORIZONTAL_ALIGNMENT_CENTER, (INNER - 20.0) * 2.0 * k, int(12 * k), 3, Color(1, 1, 1, 0.8))
	else:
		var hint := "Let go here for nothing"
		var hfs := int(12 * k)
		draw_multiline_string(ThemeDB.fallback_font, mid + Vector2(-(INNER - 20.0) * k, 0.0), hint, HORIZONTAL_ALIGNMENT_CENTER, (INNER - 20.0) * 2.0 * k, hfs, 2, Color(1, 1, 1, 0.55))

class_name WeaponWheel
extends Control
## The weapon wheel (docs/design.md section 2, "Markers and throwables you
## can buy": "a weapon wheel (hold a key) swaps between them"). Hold the
## Weapon wheel key (Tab, or RB on a controller) and a wheel of the five
## comes up in the middle of the screen; point at one with the mouse or
## either stick and let go to take it out. Ones you don't own yet are
## there, greyed and locked, so you know what's to come. While it's open
## time runs at SLOW_TIME (single player), the view holds still and the
## marker doesn't fire.
##
## It works on whoever `setup` gives it (the player): on foot, or leaning
## out of a passenger seat; not while driving. What's owned is
## GameState.owned_weapons; the switch is PaintMarker.switch_to, which
## keeps each weapon's ammo.
##
## Drawn like the rest of the HUD: dark translucent panels, white text,
## Bebas Neue for the names.

## A weapon was taken out.
signal chosen(id: String)

## Time while it's open (1 is normal). Not in the design: "slows a little".
const SLOW_TIME := 0.3
## px at 1600 x 900: the wheel's outer and inner radius.
const OUTER := 210.0
const INNER := 92.0
## px of mouse movement (or stick tilt, 0..1) before a slot is picked.
const MOUSE_PICK := 24.0
const STICK_PICK := 0.45
const NAME_FONT := "res://branding/fonts/BebasNeue-Regular.ttf"
const PANEL := Color(0.08, 0.09, 0.1, 0.86)
const PANEL_LIT := Color(0.18, 0.2, 0.22, 0.94)
const GOLD := Color(1.0, 0.86, 0.45)
## What each one is for, under its name in the middle (design's "How it plays").
const BLURBS := {
	"islander": "Semi-auto. The one everybody starts with.",
	"farmhand": "Scoped pump action. Slow, dead accurate, hits count 2.",
	"lobbyist": "Full auto. Sprays 15 a second, empties fast.",
	"jam_jars": "Hold Fire to wind up, let go to throw. Bursts after 1.5 s.",
	"tourist_season": "Lobs paint bombs. Big splash, slow to reload.",
}

var player: Node3D
## True while it's up.
var is_open := false
## The slot pointed at (index into PaintWeapons.ALL), or -1.
var pointed := -1

var _ids: Array = PaintWeapons.ALL.keys()
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


## Who it changes the weapon of: a PlayerController (marker, vehicle,
## camera_rig, and PassengerSeat when a passenger).
func setup(who: Node3D) -> void:
	player = who


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var held := InputMap.has_action("weapon_wheel") and Input.is_action_pressed("weapon_wheel") and get_tree().paused == false
	if held and not is_open and can_open():
		open()
	elif is_open and (not held or not can_open()):
		close(held == false)
	if not is_open:
		return
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down", 0.0)
	var left := Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
	if left.length() > stick.length():
		stick = left
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


## On foot, or a passenger; not driving, not out.
func can_open() -> bool:
	if player.has_method("is_out") and bool(player.call("is_out")):
		return false
	var car: Variant = player.get("vehicle")
	if car != null:
		return bool(player.get("passenger"))
	return true


func open() -> void:
	is_open = true
	visible = true
	_mouse = Vector2.ZERO
	pointed = _ids.find(_current_id())
	_time_before = Engine.time_scale
	Engine.time_scale = SLOW_TIME
	player.set("fire_blocked", true)
	var rig: Node = player.get("camera_rig")
	if rig != null:
		_camera_was = rig.is_processing()
		rig.set_process(false)
	queue_redraw()


## Put it away; `take` takes out the one pointed at (if it's owned).
func close(take := true) -> void:
	is_open = false
	visible = false
	Engine.time_scale = _time_before
	player.set("fire_blocked", false)
	var rig: Node = player.get("camera_rig")
	if rig != null:
		rig.set_process(_camera_was)
	if take and pointed >= 0:
		select(str(_ids[pointed]))


## Take out a weapon by id, if it's owned. Returns whether it changed.
func select(id: String) -> bool:
	if not _owns(id) or id == _current_id():
		return false
	var marker: PaintMarker = player.get("marker")
	marker.switch_to(PaintWeapons.get_weapon(id))
	chosen.emit(id)
	return true


## Which slot a direction points at (x right, y down, as on screen).
func slot_at(dir: Vector2) -> int:
	var n := _ids.size()
	# Slot 0 at the top, going round clockwise.
	var a := fposmod(atan2(dir.x, -dir.y), TAU)
	return int(roundf(a / (TAU / n))) % n


func _current_id() -> String:
	var marker: PaintMarker = player.get("marker")
	return str(marker.weapon.get("id", "islander")) if marker != null else "islander"


func _owns(id: String) -> bool:
	var gs := get_tree().root.get_node_or_null("GameState")
	return id == "islander" or (gs != null and bool(gs.call("owns_weapon", id)))


func _draw() -> void:
	if not is_open:
		return
	var area := size if size.x > 1.0 and size.y > 1.0 else get_viewport_rect().size
	var k := minf(area.x / 1600.0, area.y / 900.0)
	var mid := area * 0.5
	var n := _ids.size()
	var step := TAU / n
	var marker: PaintMarker = player.get("marker")
	# The dim behind, and each slot as a ring segment.
	draw_circle(mid, (OUTER + 26.0) * k, Color(0, 0, 0, 0.25))
	for i in n:
		var id := str(_ids[i])
		var owned := _owns(id)
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
		var w := PaintWeapons.get_weapon(id)
		var at := mid + Vector2.from_angle(-PI * 0.5 + i * step) * (INNER + OUTER) * 0.5 * k
		var name := str(w["type"]).to_upper()
		var fs := int(24 * k)
		var tw := _font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Color.WHITE if owned else Color(1, 1, 1, 0.35)
		draw_string(_font, at + Vector2(-tw * 0.5, 0.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var sub := "LOCKED" if not owned else ("%d / %d" % [marker.ammo_for(id), int(w["hopper"])] if marker != null else "")
		var sfs := int(15 * k)
		var sw := ThemeDB.fallback_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		draw_string(ThemeDB.fallback_font, at + Vector2(-sw * 0.5, 20.0 * k), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, GOLD if owned and lit else Color(1, 1, 1, 0.55 if owned else 0.3))
		if id == _current_id():
			draw_circle(at + Vector2(0, -30.0 * k), 3.5 * k, GOLD)
	# The middle: the pointed one's name and what it does.
	draw_circle(mid, (INNER - 8.0) * k, Color(0.05, 0.06, 0.07, 0.82))
	if pointed >= 0:
		var id := str(_ids[pointed])
		var w := PaintWeapons.get_weapon(id)
		var title := str(w["type"]).to_upper()
		var fs := int(22 * k)
		var tw := _font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(_font, mid + Vector2(-tw * 0.5, -22.0 * k), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var nick := '"%s"' % str(w["name"])
		var nfs := int(13 * k)
		var nw := ThemeDB.fallback_font.get_string_size(nick, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs).x
		draw_string(ThemeDB.fallback_font, mid + Vector2(-nw * 0.5, -4.0 * k), nick, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, GOLD)
		var blurb := str(BLURBS.get(id, "")) + ("" if _owns(id) else " Sold at Ervin's.")
		draw_multiline_string(ThemeDB.fallback_font, mid + Vector2(-(INNER - 20.0) * k, 16.0 * k), blurb, HORIZONTAL_ALIGNMENT_CENTER, (INNER - 20.0) * 2.0 * k, int(12 * k), 3, Color(1, 1, 1, 0.8))

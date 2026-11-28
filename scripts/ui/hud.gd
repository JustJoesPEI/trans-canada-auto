class_name Hud
extends CanvasLayer
## Minimal on-screen information, in one look (HudStyle):
##   * the street you are on and the way you're heading (top left), with a
##     small line of key hints under it that fades after a while (on foot
##     when the game starts, the driving keys the first time you drive),
##   * your money (bottom right, over the weapon and the speedometer), with what came in or went out beside it,
##   * a prompt when there's something to use, like "E  Get in" (bottom centre),
##   * your speed in km/h and the gear while driving (bottom right),
##   * a crosshair while aiming (centre), with a tick when your paint hits
##     someone, and the balls left in the hopper beside it,
##   * the paint meter (CombatHud: hits taken, arrows to whoever hit you), and OUT when you're out,
##     with the armour plates you're wearing in a bar over them (Armour),
##   * the weapon in hand and its ammo (bottom right, on foot or riding),
##   * paint on your windscreen while driving (WindscreenSmear),
##   * the wanted level (top centre: WantedHud),
##   * the minimap (bottom left: Minimap), with the search circle on it,
##     and over it the waypoint: the next turn with an arrow ("200 m, Turn
##     right onto Grafton Street"), where it's going and how far (Gps),
##     and a marker on the screen over the spot (the route itself is only
##     drawn on the minimap and the map),
##   * the town map, full screen, on M (WorldMap), where the waypoint is set,
##   * the OpenStreetMap credit the map data requires (bottom right).

## s the key hints stay up, and fades over.
const HELP_TIME := 10.0
const HELP_FADE := 1.5
## px from the screen's edges.
const EDGE := Vector2(24, 18)
## The armour bar's plates, and how long a broken one flashes (s).
const ARMOUR_COLOUR := Color(0.55, 0.82, 1.0)
const ARMOUR_FLASH := 0.6

var _world: WorldBuilder
var _player: Node3D
var _street: Label
var _heading: Label
var _street_name := ""
var _street_fade := 1.0
var _help: RichTextLabel
var _help_kind := ""
var _help_time := HELP_TIME
var _drove := false
var _timer := 0.0
var _prompt_panel: PanelContainer
var _prompt_key: Label
var _prompt_text: Label
var _speed_panel: PanelContainer
var _speed: Label
var _speed_unit: Label
var _speed_bar: Control
var _speed_kmh := 0.0
var _title: Label
var _subtitle: Label
var _title_time := 0.0
var _title_top := 70.0
var _gear: Label
var _card: VBoxContainer
var _card_keys: RichTextLabel
var _card_status: Label
var _crosshair: Control
var _scope: Control ## the scope's round view, while looking down one
# What the card shows now (a copy of the rows, and pad or keys), so it's
# only rebuilt on a change: compared as they are, not made into a string.
var _card_rows: Array = []
var _card_pad := false
var _ammo: Label
var _out: Label
var _hits_taken := 0
var _armour: Control
var _plates := 0
var _plates_broke := 0 ## how many the last hit broke, flashing
var _plate_flash := 0.0 ## s left of the flash
var _armour_seen := 0.0 ## s left showing the bar after a change
var _tick_time := 0.0 ## s left of the crosshair's hit tick
var _tick_kind := ""
var _tick_out := false
var _tick_head := false
## px: the crosshair ring's radius, opened out to the shot's spread.
var _ring := 9.0
## The paint fight round the crosshair: the meter, hit arrows, the edges.
var combat: CombatHud
var _smear: WindscreenSmear
var _money: Label
var _money_delta: Label
var _money_shown := 0.0
var _money_delta_time := 0.0
var _bottom_right: VBoxContainer
var _waypoint: PanelContainer
var _waypoint_name: Label
var _waypoint_dist: Label
var _marker: Control
var _turn_icon: Control
var _turn_dist: Label
var _turn_text: Label
var _turn := {}
var _map_hint: HBoxContainer
var _map_key: Label
## How long the hit tick shows (s).
const TICK_TIME := 0.18
## The player last used a controller (true) or the keyboard and mouse.
var pad := false
## The wanted level, the search circle and the car wash's suds bar.
var wanted_hud: WantedHud
## The round map, bottom left.
var minimap: Minimap
## The waypoint and the route to it.
var gps: Gps
## The town map (M).
var world_map: WorldMap
var phone: Phone
var _weapon_panel: PanelContainer
var _weapon_name: Label
var _weapon_ammo: Label


func _ready() -> void:
	add_to_group("hud")
	# Under everything else: paint on the windscreen.
	_smear = WindscreenSmear.new()
	_smear.visible = false
	add_child(_smear)
	gps = Gps.new()
	gps.name = "Gps"
	add_child(gps)
	gps.arrived.connect(func(place: String) -> void: show_title("You've arrived", place if place != "" else "at the waypoint"))
	_build_marker()
	_build_street()
	var credit := HudStyle.label(11, false, Color(1, 1, 1, 0.6))
	add_child(credit)
	credit.text = "Map data © OpenStreetMap contributors. Elevation: NRCan HRDEM, Open Government Licence – Canada"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.add_theme_constant_override("outline_size", 3)
	credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	credit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	credit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	credit.position += Vector2(-EDGE.x, -6)
	_build_prompt()
	_build_bottom_right()
	_build_card()
	_build_scope()
	move_child(_scope, 0) # under the rest of the HUD
	_build_crosshair()
	_build_paint()
	_title = HudStyle.label(48, true)
	_title.add_theme_constant_override("outline_size", 8)
	add_child(_title)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_subtitle = HudStyle.label(18)
	add_child(_subtitle)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	_subtitle.grow_horizontal = Control.GROW_DIRECTION_BOTH
	set_title_top(-1.0)
	minimap = Minimap.new()
	minimap.name = "Minimap"
	add_child(minimap)
	_build_waypoint()
	wanted_hud = WantedHud.new()
	add_child(wanted_hud)
	world_map = WorldMap.new()
	world_map.name = "WorldMap"
	add_child(world_map)
	phone = Phone.new()
	phone.name = "Phone"
	add_child(phone)
	_show_help("foot")
	get_viewport().size_changed.connect(_layout_minimap_bits)
	_layout_minimap_bits.call_deferred()


## A title across the top of the screen for a few seconds, e.g. the car's
## name when you get in.
func show_title(title: String, subtitle := "") -> void:
	_title.text = title
	_subtitle.text = subtitle
	_title_time = 3.5


## Moves the titles down to start at `y` (px from the top), out from under
## the wanted level; negative puts them back.
func set_title_top(y: float) -> void:
	_title_top = 70.0 if y < 0.0 else y
	_title.position.y = _title_top
	_subtitle.position.y = _title_top + 54.0


## Show a prompt like "E  Get in", or hide it with an empty text.
func set_prompt(key: String, text: String) -> void:
	# Several things set it in a frame (the game, then a shop counter or the
	# impound lot it's near): the last one wins, put up once at the end of
	# the frame, so the label isn't laid out twice a frame.
	_prompt_next = [key, text]
	if not _prompt_queued:
		_prompt_queued = true
		_show_prompt.call_deferred()


var _prompt_next := ["", ""]
var _prompt_queued := false


func _show_prompt() -> void:
	_prompt_queued = false
	var key: String = _prompt_next[0]
	var text: String = _prompt_next[1]
	_prompt_panel.visible = text != ""
	_prompt_key.text = key
	_prompt_key.visible = key != ""
	_prompt_text.text = text


## Looking down a scope (0..1, CameraRig.scope_amount): black round a
## circle, with a fine reticle.
func set_scope(amount: float) -> void:
	_scope.visible = amount > 0.01
	_scope.modulate.a = amount


## Fade the crosshair in (1) or out (0), with the aim.
func set_crosshair(amount: float) -> void:
	_crosshair.visible = amount > 0.01
	_crosshair.modulate.a = amount


## The ring opens to where the next shot can go: `px` is the spread's
## radius on screen (PaintMarker.spread_now through the view).
func set_spread(px: float) -> void:
	var r := clampf(px, 9.0, 70.0)
	if absf(r - _ring) > 0.25:
		_ring = r
		_crosshair.queue_redraw()


var _ammo_shown := [-2, -1, -1] ## reload %, ammo, hopper as shown
var _ammo_warn := -1 ## 1 warning, 0 not, -1 not set yet
var _weapon_shown := []


## The marker and the hits on you: balls left (shown with the crosshair),
## the reload's progress (0..1, or negative when not reloading), the hits
## taken (the meter: CombatHud) and whether you're out.
func set_paint(ammo: int, hopper: int, reload: float, hits: int, out: bool) -> void:
	# Called every frame: the text and its colour only when they change
	# (setting either lays the label out again).
	var pct := roundi(reload * 100.0) if reload >= 0.0 else -1
	var warn := ammo <= hopper / 8 and reload < 0.0
	if pct != _ammo_shown[0] or ammo != _ammo_shown[1] or hopper != _ammo_shown[2]:
		_ammo_shown = [pct, ammo, hopper]
		_ammo.text = ("reloading %d%%" % pct) if pct >= 0 else ("%d / %d" % [ammo, hopper])
	if int(warn) != _ammo_warn:
		_ammo_warn = int(warn)
		_ammo.add_theme_color_override("font_color", HudStyle.WARN if warn else HudStyle.TEXT)
	_ammo.visible = _crosshair.visible or reload >= 0.0
	_hits_taken = hits
	_out.visible = out


## The armour plates worn (Armour), and how many a hit just broke (they
## flash). The bar shows with the paint meter, while aiming, and for a few
## seconds after a change.
func set_armour(plates: int, broke := 0) -> void:
	_plates = plates
	_armour_seen = 4.0
	if broke > 0:
		_plates_broke = broke
		_plate_flash = ARMOUR_FLASH
	_armour.queue_redraw()


## The weapon in hand (its name, "" to hide the panel) and its ammo:
## balls in the hopper, or jars left for a carried throwable.
func set_weapon(weapon_name: String, ammo: int, hopper: int, carried := false) -> void:
	_weapon_panel.visible = weapon_name != ""
	if weapon_name == "":
		return
	# Every frame too: only what changed.
	var shown := [weapon_name, ammo, hopper, carried]
	if shown == _weapon_shown:
		return
	_weapon_shown = shown
	_weapon_name.text = weapon_name.to_upper()
	_weapon_ammo.text = ("%d left" % ammo) if carried else ("%d / %d" % [ammo, hopper])
	_weapon_ammo.add_theme_color_override("font_color", HudStyle.WARN if ammo <= maxi(1, hopper / 8) else HudStyle.TEXT)


## Your paint hit something: a tick on the crosshair (bigger for an out,
## yellow and a touch bigger for a head hit).
func paint_hit_tick(kind: String, out: bool, head := false) -> void:
	_tick_time = TICK_TIME * (2.0 if out else (1.4 if head else 1.0))
	_tick_kind = kind
	_tick_out = out
	_tick_head = head
	_crosshair.queue_redraw()


## Paint on the windscreen of the car you're in (null on foot).
func set_windscreen(pc: PaintCoverage, cockpit: bool, camera: Camera3D) -> void:
	_smear.show_car(pc, cockpit, camera)


## Show the speedometer (km/h) and the gear ("4", "R"), or hide it with
## a negative speed.
func set_speed(kmh: float, gear := "") -> void:
	_speed_panel.visible = kmh >= 0.0
	if kmh >= 0.0:
		if not _drove:
			# The first time behind the wheel: the driving keys.
			_drove = true
			_show_help("drive")
		_speed.text = "%d" % roundi(kmh)
		_gear.text = gear
		_gear.visible = gear != ""
		if absf(kmh - _speed_kmh) > 0.5:
			_speed_kmh = kmh
			_speed_bar.queue_redraw()


## The key (or controller button) for an action, as the player would
## press it now: "T", "Page Up", "RB", "X".
func key_for(action: String) -> String:
	if not InputMap.has_action(action):
		return action
	for ev in InputMap.action_get_events(action):
		if pad:
			if ev is InputEventJoypadButton:
				return PAD_BUTTONS.get((ev as InputEventJoypadButton).button_index, "?")
			if ev is InputEventJoypadMotion:
				var m := ev as InputEventJoypadMotion
				return PAD_AXES.get(m.axis, "Stick")
		elif ev is InputEventKey:
			return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			return MOUSE_BUTTONS.get((ev as InputEventMouseButton).button_index, "Wheel")
	return "?"


## Xbox-style names for the buttons.
const PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L-stick", JOY_BUTTON_RIGHT_STICK: "R-stick",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_MISC1: "Share",
}
const PAD_AXES := {JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT"}
const MOUSE_BUTTONS := {MOUSE_BUTTON_LEFT: "Left click", MOUSE_BUTTON_RIGHT: "Right click"}

## The key hints under the street name: [action(s), what it does], a short
## word each so they fit on a line or two.
const HELP_FOOT := [
	[["move_forward", "move_left", "move_back", "move_right"], "walk"],
	[["run"], "run"],
	[["aim"], "aim"],
	[["fire"], "fire"],
	[["dodge"], "roll"],
	[["crouch"], "crouch"],
	[["weapon_wheel"], "weapons"],
	[["interact"], "get in"],
	[["map"], "map"],
	[["phone"], "phone"],
	[["pause"], "menu"],
]
const HELP_DRIVE := [
	[["accelerate"], "go"],
	[["brake_reverse"], "brake"],
	[["handbrake"], "handbrake"],
	[["horn"], "horn"],
	[["wipers"], "wipers"],
	[["weapon_wheel"], "car menu"],
	[["camera_view"], "view"],
	[["interact"], "get out"],
	[["map"], "map"],
	[["phone"], "phone"],
]
## How many hints on each line (the top left's, a working vehicle's).
const HELP_PER_LINE := 4
const CARD_PER_LINE := 2


## The key hints for a working vehicle: rows of [actions, what they do]
## (two actions read "R / G"), or [actions, what, "pad"] for a row shown
## only to controller players, and a status line under them. An empty list
## hides it.
func set_controls(rows: Array, status := "") -> void:
	_card.visible = not rows.is_empty()
	if rows.is_empty():
		_card_rows = []
		return
	if rows != _card_rows or pad != _card_pad:
		_card_rows = rows.duplicate(true)
		_card_pad = pad
		var hints: Array[String] = []
		for r: Array in rows:
			if r.size() > 2 and str(r[2]) == "pad" and not pad:
				continue # on the keyboard that key does something else here
			var keys: Array = r[0]
			var names: Array[String] = []
			for a: String in keys:
				names.append(key_for(a))
			if names.has("?"):
				continue # nothing on this device (on a controller: the vehicle wheel)
			var text := " / ".join(names)
			if names.size() == 2 and names[0].begins_with("D-pad ") and names[1].begins_with("D-pad "):
				text = "%s / %s" % [names[0], names[1].trim_prefix("D-pad ")]
			hints.append(_hint(text, str(r[1])))
		_card_keys.text = _hint_lines(hints, CARD_PER_LINE)
	_card_status.text = status
	_card_status.visible = status != ""


## One key hint: the key(s) in gold, then what they do, in bbcode.
static func _hint(keys: String, what: String) -> String:
	return "[color=#%s]%s[/color] %s" % [HudStyle.ACCENT.to_html(false), keys.replace("[", "[lb]"), what]


## Key hints, `per_line` to a line.
static func _hint_lines(hints: Array[String], per_line: int) -> String:
	var lines: Array[String] = []
	for i in range(0, hints.size(), per_line):
		lines.append("   ".join(hints.slice(i, i + per_line)))
	return "\n".join(lines)


## Small dim key hints with an outline, no panel (the top left's and the
## working vehicle's).
static func _hint_label() -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.add_theme_font_size_override("normal_font_size", 13)
	l.add_theme_color_override("default_color", Color(HudStyle.DIM, 0.85))
	l.add_theme_color_override("font_outline_color", HudStyle.OUTLINE)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_constant_override("line_separation", 2)
	return l


func _input(event: InputEvent) -> void:
	var was := pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != was:
		_map_key.text = key_for("map")
		if _help.visible and _help_kind != "tip":
			_fill_help()


static func _panel_style() -> StyleBoxFlat:
	return HudStyle.panel()


# --- building ----------------------------------------------------------------------------------

## Top left: the street in Bebas Neue, the way you're heading under it in
## gold, and the key hints under those.
func _build_street() -> void:
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	add_child(col)
	col.position = EDGE
	_street = HudStyle.label(34, true)
	col.add_child(_street)
	_heading = HudStyle.label(15, true, HudStyle.ACCENT)
	_heading.add_theme_constant_override("outline_size", 4)
	col.add_child(_heading)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	col.add_child(gap)
	# No panel: small dim text with an outline, so it reads on sky and snow
	# without covering the street.
	_help = _hint_label()
	col.add_child(_help)


func _show_help(kind: String) -> void:
	_help_kind = kind
	_help_time = HELP_TIME
	_help.visible = true
	_help.modulate.a = 1.0
	_fill_help()


## A quiet one-line tip in the key-hint spot (top left), fading out like
## the hints: for nudges that shouldn't take over the screen.
func show_tip(text: String) -> void:
	_help_kind = "tip"
	_help_time = 6.0
	_help.visible = true
	_help.modulate.a = 1.0
	_help.text = text


func _fill_help() -> void:
	var hints: Array[String] = []
	for r: Array in (HELP_DRIVE if _help_kind == "drive" else HELP_FOOT):
		var names: Array[String] = []
		for a: String in r[0]:
			var n := key_for(a)
			if not names.has(n):
				names.append(n)
		if names.has("?"):
			continue # nothing on this device (on a controller: the vehicle wheel)
		var text := "".join(names) if names.size() == 4 and not pad else " / ".join(names)
		if pad and names.size() == 4:
			text = "L-stick"
		hints.append(_hint(text, str(r[1])))
	_help.text = _hint_lines(hints, HELP_PER_LINE)


## Bottom right, over the weapon and the speedometer: the money, and what
## came in or went out beside it.
func _build_money() -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	_bottom_right.add_child(row)
	_money_delta = HudStyle.label(22, true, HudStyle.GOOD)
	_money_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_money_delta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_money_delta.modulate.a = 0.0
	row.add_child(_money_delta)
	_money = HudStyle.label(36, true, Color(0.93, 0.97, 0.9))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_money)
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs != null:
		_money_shown = float(int(gs.get("money")))
		gs.connect("money_changed", _on_money)
	_money.text = CarModels.dollars(roundi(_money_shown))


func _on_money(amount: int) -> void:
	var d := amount - roundi(_money_shown)
	if d == 0:
		return
	_money_delta.text = ("+" if d > 0 else "") + CarModels.dollars(d)
	_money_delta.add_theme_color_override("font_color", HudStyle.GOOD if d > 0 else HudStyle.WARN)
	_money_delta_time = 3.0


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_prompt_panel.add_child(row)
	_prompt_key = HudStyle.key_label("", 20)
	row.add_child(_prompt_key)
	_prompt_text = Label.new()
	_prompt_text.add_theme_font_size_override("font_size", 20)
	row.add_child(_prompt_text)
	add_child(_prompt_panel)
	_prompt_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE)
	_prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_panel.position.y -= 90
	_prompt_panel.visible = false


## Bottom right, stacked: the money over the weapon over the speedometer.
func _build_bottom_right() -> void:
	_bottom_right = VBoxContainer.new()
	_bottom_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_right.add_theme_constant_override("separation", 8)
	_bottom_right.alignment = BoxContainer.ALIGNMENT_END
	add_child(_bottom_right)
	_build_money()
	_build_weapon()
	_build_speed()
	_bottom_right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE)
	_bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_right.position += Vector2(-EDGE.x, -34)


## The speedometer: the speed big in Bebas Neue, km/h small beside it, the
## gear in a gold box, and a thin bar under them that fills to 120 km/h.
func _build_speed() -> void:
	_speed_panel = PanelContainer.new()
	_speed_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	_speed_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	_speed_panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	_gear = Label.new()
	_gear.add_theme_font_override("font", HudStyle.heading_font())
	_gear.add_theme_font_size_override("font_size", 24)
	_gear.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	var gb := StyleBoxFlat.new()
	gb.bg_color = HudStyle.ACCENT
	gb.set_corner_radius_all(5)
	gb.content_margin_left = 8
	gb.content_margin_right = 8
	_gear.add_theme_stylebox_override("normal", gb)
	_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gear.custom_minimum_size.x = 30
	_gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_gear)
	_speed = Label.new()
	_speed.add_theme_font_override("font", HudStyle.heading_font())
	_speed.add_theme_font_size_override("font_size", 54)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed.custom_minimum_size.x = 76
	row.add_child(_speed)
	_speed_unit = Label.new()
	_speed_unit.text = "KM/H"
	_speed_unit.add_theme_font_override("font", HudStyle.heading_font())
	_speed_unit.add_theme_font_size_override("font_size", 17)
	_speed_unit.add_theme_color_override("font_color", HudStyle.DIM)
	_speed_unit.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_speed_unit)
	_speed_bar = Control.new()
	_speed_bar.custom_minimum_size = Vector2(170, 5)
	_speed_bar.draw.connect(func() -> void:
		var s := _speed_bar.size
		_speed_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.12))
		var f := clampf(_speed_kmh / 120.0, 0.0, 1.0)
		_speed_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(s.x * f, s.y)), HudStyle.ACCENT.lerp(HudStyle.WARN, smoothstep(0.6, 1.0, f))))
	col.add_child(_speed_bar)
	_bottom_right.add_child(_speed_panel)
	_speed_panel.visible = false


## A small ring and dot in the middle of the screen, outlined so it shows
## on sky and on snow.
func _build_scope() -> void:
	_scope = Control.new()
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope.visible = false
	_scope.draw.connect(func() -> void:
		var area := _scope.size
		var mid := area * 0.5
		var r := area.y * 0.44
		var far := area.length()
		# Everything outside the circle black (one very wide ring), a soft
		# dark rim just inside it.
		_scope.draw_arc(mid, r + far * 0.5, 0.0, TAU, 96, Color.BLACK, far)
		_scope.draw_arc(mid, r - 6.0, 0.0, TAU, 96, Color(0, 0, 0, 0.35), 12.0, true)
		# The reticle: fine lines across, thick posts at the edges, a gap in
		# the middle for the crosshair.
		var line := Color(0, 0, 0, 0.85)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_scope.draw_line(mid + d * 16.0, mid + d * r * 0.6, line, 1.5, true)
			_scope.draw_line(mid + d * r * 0.6, mid + d * r, line, 5.0, true)
			for k in 4:
				var at := mid + d * (16.0 + r * 0.12 * (k + 1))
				var side := Vector2(d.y, d.x) * 4.0
				_scope.draw_line(at - side, at + side, line, 1.5, true))
	_scope.resized.connect(_scope.queue_redraw)
	add_child(_scope)


func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.visible = false
	_crosshair.draw.connect(func() -> void:
		var dark := Color(0, 0, 0, 0.55)
		var light := Color(1, 1, 1, 0.9)
		_crosshair.draw_arc(Vector2.ZERO, _ring, 0.0, TAU, 40, dark, 3.5, true)
		_crosshair.draw_arc(Vector2.ZERO, _ring, 0.0, TAU, 40, light, 1.5, true)
		_crosshair.draw_circle(Vector2.ZERO, 2.6, dark)
		_crosshair.draw_circle(Vector2.ZERO, 1.6, light)
		if _tick_time > 0.0:
			# The hit tick: four short marks round the ring, white on a
			# person, grey on a car, bigger and orange for an out.
			var tick := Color(1.0, 0.55, 0.15) if _tick_out else (Color(1.0, 0.9, 0.2) if _tick_head else (Color(1, 1, 1) if _tick_kind == "person" else Color(0.75, 0.78, 0.8)))
			var r0 := _ring + (4.0 if not _tick_out else 5.0)
			var r1 := _ring + (10.0 if not _tick_out else 16.0) + (3.0 if _tick_head else 0.0)
			for k in 4:
				var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * k)
				_crosshair.draw_line(d * r0, d * r1, dark, 4.5, true)
				_crosshair.draw_line(d * r0, d * r1, tick, 2.2, true))
	add_child(_crosshair)


## The balls left, by the crosshair; OUT (the meter is CombatHud), low in the middle.
func _build_paint() -> void:
	_ammo = HudStyle.label(16)
	add_child(_ammo)
	_ammo.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_ammo.position += Vector2(26, 16)
	_ammo.visible = false
	# The paint meter, the arrows to whoever hit you and the edges when
	# nearly out (CombatHud).
	combat = CombatHud.new()
	combat.name = "CombatHud"
	add_child(combat)
	# The armour: a plate per segment over the paint meter; a plate that breaks
	# flashes white and swells as it goes.
	_armour = Control.new()
	_armour.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_armour.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_armour.position.y -= 174
	_armour.visible = false
	_armour.draw.connect(func() -> void:
		var w := 22.0
		var gap := 5.0
		var x0 := -(w * BodyPaint.ARMOUR_MAX + gap * (BodyPaint.ARMOUR_MAX - 1)) * 0.5
		var f := clampf(_plate_flash / ARMOUR_FLASH, 0.0, 1.0)
		for i in BodyPaint.ARMOUR_MAX:
			var r := Rect2(x0 + i * (w + gap), -4.0, w, 8.0)
			_armour.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
			var broken := i >= _plates and i < _plates + _plates_broke and f > 0.0
			if broken:
				_armour.draw_rect(r.grow(3.0 * (1.0 - f)), Color(1, 1, 1, f))
			else:
				_armour.draw_rect(r, ARMOUR_COLOUR if i < _plates else Color(1, 1, 1, 0.2)))
	add_child(_armour)
	_out = HudStyle.label(72, true, Color(1.0, 0.55, 0.15))
	_out.add_theme_constant_override("outline_size", 10)
	add_child(_out)
	_out.text = "OUT"
	_out.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_out.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_out.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_out.position += Vector2(0, 50)
	_out.visible = false


## The weapon panel, bottom right (over the speedometer while riding):
## its name in Bebas Neue and the ammo.
func _build_weapon() -> void:
	_weapon_panel = PanelContainer.new()
	_weapon_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	_weapon_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_weapon_panel.add_child(row)
	_weapon_name = Label.new()
	_weapon_name.add_theme_font_override("font", HudStyle.heading_font())
	_weapon_name.add_theme_font_size_override("font_size", 28)
	row.add_child(_weapon_name)
	_weapon_ammo = Label.new()
	_weapon_ammo.add_theme_font_size_override("font_size", 20)
	_weapon_ammo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_weapon_ammo)
	_bottom_right.add_child(_weapon_panel)
	_weapon_panel.visible = false


## A working vehicle's key hints, down the left side: small text, no
## panel, with its status (load, tow line) under them.
func _build_card() -> void:
	_card = VBoxContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_constant_override("separation", 3)
	_card_keys = _hint_label()
	_card.add_child(_card_keys)
	_card_status = HudStyle.label(13, false, Color(0.8, 0.92, 1.0, 0.9))
	_card_status.add_theme_constant_override("outline_size", 4)
	_card.add_child(_card_status)
	add_child(_card)
	_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE)
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.position += Vector2(24, 60)
	_card.visible = false


## Over the minimap: the waypoint's name and how far along the streets;
## and beside it, the key for the map.
func _build_waypoint() -> void:
	_waypoint = PanelContainer.new()
	_waypoint.add_theme_stylebox_override("panel", HudStyle.panel(HudStyle.WAYPOINT))
	_waypoint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_waypoint.add_child(col)
	# The next turn: an arrow, how far, what to do.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	_turn_icon = Control.new()
	_turn_icon.custom_minimum_size = Vector2(44, 44)
	_turn_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_icon.draw.connect(_draw_turn)
	row.add_child(_turn_icon)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", -4)
	row.add_child(tcol)
	_turn_dist = HudStyle.label(30, true, Color.WHITE, false)
	tcol.add_child(_turn_dist)
	_turn_text = HudStyle.label(16, false, Color.WHITE, false)
	_turn_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_turn_text.custom_minimum_size.x = 230
	tcol.add_child(_turn_text)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.1)
	line.custom_minimum_size.y = 1
	col.add_child(line)
	# Where it's going, and how far in all.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	col.add_child(foot)
	_waypoint_name = HudStyle.label(17, true, HudStyle.WAYPOINT.lightened(0.35), false)
	_waypoint_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_waypoint_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_waypoint_name.custom_minimum_size.x = 150
	foot.add_child(_waypoint_name)
	_waypoint_dist = HudStyle.label(15, false, HudStyle.DIM, false)
	foot.add_child(_waypoint_dist)
	add_child(_waypoint)
	_waypoint.visible = false
	_map_hint = HBoxContainer.new()
	_map_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_hint.add_theme_constant_override("separation", 6)
	_map_key = HudStyle.key_label(key_for("map"), 14)
	_map_hint.add_child(_map_key)
	var t := HudStyle.label(15, true, Color(1, 1, 1, 0.85))
	t.text = "Map"
	_map_hint.add_child(t)
	add_child(_map_hint)


func _layout_minimap_bits() -> void:
	if minimap == null:
		return
	# The waypoint just over the minimap, the map key just right of its foot.
	_waypoint.size = Vector2.ZERO
	_waypoint.position = minimap.position + Vector2(0, -_waypoint.get_combined_minimum_size().y - 34)
	_map_hint.size = Vector2.ZERO
	_map_hint.position = minimap.position + Vector2(minimap.size.x + 8, minimap.size.y - _map_hint.get_combined_minimum_size().y)


## The waypoint panel from the GPS: the next turn, the place, how far.
func _update_turn() -> void:
	_waypoint_name.text = gps.title()
	_waypoint_dist.text = HudStyle.distance_text(gps.remaining) if gps.shows_pin() else ""
	var t := gps.next_turn
	if not gps.shows_turns():
		t = {"turn": "address", "dist": 0.0, "onto": ""}
	elif gps.route.size() < 2 or t.is_empty():
		t = {"turn": "off", "dist": gps.remaining, "onto": ""}
	var kind := str(t["turn"])
	_turn_dist.text = HudStyle.distance_text(float(t["dist"])) if kind != "continue" else "Follow the route"
	if kind == "address":
		_turn_dist.text = "Find it"
	var what := Gps.turn_text(t)
	var onto := str(t.get("onto", ""))
	match kind:
		"off":
			what = "Off the streets: head for the pin"
		"address":
			what = "By the street signs: no GPS on this one"
		"arrive":
			what = "Arrive at %s" % gps.title()
		"continue":
			what = "Continue on %s" % _street_name if _street_name != "" else "Continue"
		"roundabout":
			what = "Roundabout, exit onto %s" % onto if onto != "" else "Roundabout"
		_:
			if onto != "" and onto != _street_name:
				what += " onto %s" % onto
	_turn_text.text = what
	if t.hash() != _turn.hash():
		_turn = t
		_turn_icon.queue_redraw()
	_layout_minimap_bits()


## The arrow for the next turn: up, bent left or right as sharp as the turn,
## round for a U-turn or a roundabout, a pin to arrive.
func _draw_turn() -> void:
	var c := _turn_icon.size * 0.5
	var kind := str(_turn.get("turn", ""))
	var col := Color.WHITE
	_turn_icon.draw_circle(c, 21.0, Color(HudStyle.WAYPOINT, 0.28))
	if kind in ["arrive", "off", "address", ""]:
		MapIcons.pin(_turn_icon, c + Vector2(0, 11), 1.3)
		return
	var w := 4.0
	var pts := PackedVector2Array()
	var tip_dir := Vector2.UP
	if kind == "roundabout":
		_turn_icon.draw_arc(c + Vector2(0, -2), 7.0, 0.0, TAU, 24, Color(1, 1, 1, 0.55), 3.0, true)
		pts = PackedVector2Array([c + Vector2(0, 16), c + Vector2(0, 5)])
		_turn_icon.draw_polyline(pts, col, w, true)
		var a := float(_turn.get("angle", 0.0))
		tip_dir = Vector2.UP.rotated(clampf(a, -PI * 0.75, PI * 0.75))
		var out := c + Vector2(0, -2) + tip_dir * 7.0
		pts = PackedVector2Array([out, out + tip_dir * 6.0])
	elif kind == "u-turn":
		var left := float(_turn.get("angle", 0.0)) < 0.0
		var sx := -1.0 if left else 1.0
		pts = PackedVector2Array([c + Vector2(-5 * sx, 15), c + Vector2(-5 * sx, -3)])
		for i in range(1, 9):
			var a := PI - PI * i / 8.0
			pts.append(c + Vector2(-5 * sx, -3) + Vector2(cos(a) * 5.0 * sx + 5.0 * sx, -sin(a) * 6.0))
		pts.append(c + Vector2(5 * sx, 6))
		tip_dir = Vector2.DOWN
	else:
		var a := 0.0
		if kind != "continue":
			a = clampf(float(_turn.get("angle", 0.0)), -PI * 0.8, PI * 0.8)
		var mid := c + Vector2(0, 2)
		tip_dir = Vector2.UP.rotated(a)
		pts = PackedVector2Array([c + Vector2(0, 16), mid, mid + tip_dir * 11.0])
	_turn_icon.draw_polyline(pts, col, w, true)
	var tip := pts[pts.size() - 1] + tip_dir * 6.0
	var side := tip_dir.orthogonal()
	_turn_icon.draw_colored_polygon(PackedVector2Array([tip, tip - tip_dir * 9.0 + side * 7.0, tip - tip_dir * 9.0 - side * 7.0]), col)


## A marker on the screen over the waypoint, with how far it is; at the
## screen's edge, pointing the way, while it's off screen or behind you.
func _build_marker() -> void:
	_marker = Control.new()
	_marker.name = "WaypointMarker"
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.draw.connect(_draw_marker)
	add_child(_marker)


func _draw_marker() -> void:
	if gps == null or not gps.active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp := _marker.size
	var at := gps.target + Vector3(0, 4.0, 0)
	var behind := cam.is_position_behind(at)
	var p := cam.unproject_position(at)
	if behind:
		p = vp - p # mirrored, so it points round the right way
	# Kept inside the screen however small it is (a tiny window, or a
	# headless tool's zero-size one), so the box below never turns inside out.
	var margin := Vector2(40, 60).min(vp * 0.25)
	var inner := Rect2(margin, vp - margin * 2.0)
	var edge := behind or not inner.has_point(p)
	var font := HudStyle.heading_font()
	if edge:
		# On the edge: an arrowhead toward it.
		var mid := vp * 0.5
		var dir := (p - mid).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.DOWN
		var t := INF
		for axis in 2:
			if absf(dir[axis]) > 1e-4:
				t = minf(t, (inner.size[axis] * 0.5) / absf(dir[axis]))
		p = mid + dir * t
		var side := dir.orthogonal()
		_marker.draw_colored_polygon(PackedVector2Array([p + dir * 14.0, p - dir * 4.0 + side * 10.0, p - dir * 4.0 - side * 10.0]), Color(0, 0, 0, 0.6))
		_marker.draw_colored_polygon(PackedVector2Array([p + dir * 11.0, p - dir * 2.0 + side * 7.5, p - dir * 2.0 - side * 7.5]), HudStyle.WAYPOINT)
		p -= dir * 26.0
	else:
		# Over the spot: a diamond.
		var d := PackedVector2Array([p + Vector2(0, -11), p + Vector2(9, 0), p + Vector2(0, 11), p + Vector2(-9, 0)])
		var o := d.duplicate()
		o.append(d[0])
		_marker.draw_polyline(o, Color(0, 0, 0, 0.8), 4.0, true)
		_marker.draw_colored_polygon(d, HudStyle.WAYPOINT)
		_marker.draw_circle(p, 3.0, Color.WHITE)
		p += Vector2(0, 30)
	var text := HudStyle.distance_text(gps.remaining)
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	var at2 := p + Vector2(-size.x * 0.5, 6.0 if edge else 0.0)
	_marker.draw_string_outline(font, at2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 5, Color(0, 0, 0, 0.85))
	_marker.draw_string(font, at2, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


func setup(world: WorldBuilder, player: Node3D) -> void:
	_world = world
	_player = player
	minimap.setup(world, player)
	gps.setup(world, player)
	world_map.setup(world, player, gps, minimap)
	combat.setup(player)
	# Where Two Years Less a Day lets you out: the police station.
	var wanted := get_tree().root.get_node_or_null("Wanted")
	if wanted != null and wanted.has_method("station_xform"):
		minimap.set_marker("police_station", "police_station", (wanted.call("station_xform", world) as Transform3D).origin)


func _process(delta: float) -> void:
	if _tick_time > 0.0:
		_tick_time -= delta
		_crosshair.queue_redraw()
	if _plate_flash > 0.0:
		_plate_flash -= delta
		_armour.queue_redraw()
	_armour_seen = maxf(0.0, _armour_seen - delta)
	_armour.visible = (_plates > 0 or _plate_flash > 0.0) and (_hits_taken > 0 or _ammo.visible or _armour_seen > 0.0)
	# Titles: fade in quickly, sink a little into place, fade out.
	_title_time -= delta
	var ta := clampf(_title_time / 0.6, 0.0, 1.0) * clampf((3.5 - _title_time) / 0.15, 0.0, 1.0)
	_title.modulate.a = ta
	_subtitle.modulate.a = ta * 0.9
	var drop := 10.0 * (1.0 - clampf((3.5 - _title_time) / 0.25, 0.0, 1.0))
	_title.position.y = _title_top - drop
	_subtitle.position.y = _title_top + 54.0 - drop * 0.6
	# The key hints fade after a while.
	if _help.visible:
		_help_time -= delta
		_help.modulate.a = clampf(_help_time / HELP_FADE, 0.0, 1.0)
		if _help_time <= 0.0:
			_help.visible = false
	# The street name fades in when it changes.
	if _street_fade < 1.0:
		_street_fade = minf(1.0, _street_fade + delta * 3.0)
		_street.modulate.a = _street_fade
	# Money counts up (or down) to what it is.
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs != null:
		var m := float(int(gs.get("money")))
		if not is_equal_approx(m, _money_shown):
			var step := maxf(1.0, absf(m - _money_shown) * minf(1.0, delta * 4.0))
			_money_shown = move_toward(_money_shown, m, step)
			_money.text = CarModels.dollars(roundi(_money_shown))
	if _money_delta_time > 0.0:
		_money_delta_time -= delta
		_money_delta.modulate.a = clampf(_money_delta_time / 0.8, 0.0, 1.0)
	# The waypoint.
	var wp := gps != null and gps.active
	_waypoint.visible = wp
	_marker.visible = wp and gps.shows_pin()
	if wp:
		_marker.queue_redraw()
	_timer -= delta
	if _timer > 0.0 or _world == null or _player == null or not _world.is_built:
		return
	_timer = 0.25
	var p := _player.global_position
	var s := _world.street_name_at(Vector2(p.x, p.z))
	if s != _street_name:
		_street_name = s
		_street.text = s
		_street_fade = 0.0
		_street.modulate.a = 0.0
	var face := -_player.global_basis.z
	var car: Variant = _player.get("vehicle")
	if car is Node3D:
		face = -(car as Node3D).global_basis.z
	var c := HudStyle.compass(Vector2(face.x, face.z))
	_heading.text = ("Heading %s" % c) if c != "" else ""
	if wp:
		_update_turn()

extends Node
## Field notes: press N in the game to leave a note about the spot you're
## at, for whoever is working on the town ("this house is yellow with a red
## door", "build a gazebo here").
##
## Each note records the text, where you're standing (street, game metres,
## latitude and longitude), which way you're facing, and what's in the
## middle of the screen: a building's OSM id and name, or the spot on the
## ground. The note is copied to the clipboard, ready to paste into a chat,
## and added to notes.txt (and notes.json) in the game's user folder; F9
## opens that folder. A numbered pin marks each note's spot in the town, and
## stays there next time.
##
## While the note box is open the game is paused, so typing doesn't walk
## the player. Nothing here changes the town or gameplay.

const TXT_PATH := "user://notes.txt"
const JSON_PATH := "user://notes.json"

var _notes: Array = []
var _layer: CanvasLayer
var _panel: PanelContainer
var _edit: LineEdit
var _where: Label
var _toast: Label
var _toast_time := 0.0
var _pending: Dictionary = {}
var _was_captured := false
var _pins: Node3D
var _pins_placed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_ui()


func _process(delta: float) -> void:
	if _toast.visible:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.visible = false
	# Put the pins in once the town is there.
	if not _pins_placed and _world() != null and _world().is_built:
		_pins_placed = true
		for n: Dictionary in _notes:
			_add_pin(n)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _panel.visible:
		if k.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_N and _world() != null and _world().is_built:
		_open()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_F9:
		OS.shell_open(ProjectSettings.globalize_path("user://"))
		get_viewport().set_input_as_handled()


# --- taking a note --------------------------------------------------------------

func _open() -> void:
	_pending = _look()
	_where.text = _describe_place(_pending)
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	_edit.text = ""
	_panel.visible = true
	_edit.grab_focus()


func _close() -> void:
	_panel.visible = false
	_edit.release_focus()
	get_tree().paused = false
	if _was_captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _submit(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		_close()
		return
	var n := _pending.duplicate()
	n["number"] = _notes.size() + 1
	n["text"] = text
	n["time"] = Time.get_datetime_string_from_system(false, true)
	_notes.append(n)
	var line := _format(n)
	DisplayServer.clipboard_set(line)
	var f := FileAccess.open(TXT_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(TXT_PATH) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_string(line + "\n\n")
		f.close()
	var j := FileAccess.open(JSON_PATH, FileAccess.WRITE)
	if j != null:
		j.store_string(JSON.stringify(_notes, " "))
		j.close()
	_add_pin(n)
	_close()
	_show_toast("Note %d saved and copied. Paste it into your chat with Claude, or send notes.txt (F9 opens its folder)." % n["number"])


## Where the player is and what the camera is pointing at.
func _look() -> Dictionary:
	var world := _world()
	var out := {}
	var scene := get_tree().current_scene
	var player := scene.get_node_or_null("Player") as Node3D
	var body: Node3D = player
	if player != null and player.get("vehicle") != null:
		body = player.get("vehicle")
	var at: Vector3 = body.global_position if body != null else Vector3.ZERO
	out["x"] = snappedf(at.x, 0.1)
	out["z"] = snappedf(at.z, 0.1)
	out["street"] = world.street_name_at(Vector2(at.x, at.z), 40.0)
	var ll: Vector2 = world.data.projection.to_lon_lat(Vector2(at.x, at.z))
	out["lat"] = snappedf(ll.y, 0.000001)
	out["lon"] = snappedf(ll.x, 0.000001)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return out
	var fwd := -cam.global_basis.z
	out["facing"] = int(round(fposmod(rad_to_deg(atan2(fwd.x, -fwd.z)), 360.0)))
	# What's in the middle of the screen, out to 400 m.
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + fwd * 400.0, Layers.GROUND | Layers.SOLID)
	if body is CollisionObject3D:
		q.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var p: Vector3 = hit["position"]
		var col := hit["collider"] as Object
		out["aim_x"] = snappedf(p.x, 0.1)
		out["aim_z"] = snappedf(p.z, 0.1)
		out["aim_y"] = snappedf(p.y, 0.1)
		var all: Vector2 = world.data.projection.to_lon_lat(Vector2(p.x, p.z))
		out["aim_lat"] = snappedf(all.y, 0.000001)
		out["aim_lon"] = snappedf(all.x, 0.000001)
		out["aim_dist"] = int(round(cam.global_position.distance_to(p)))
		if col != null and col.has_meta("osm_id"):
			out["building"] = str(col.get_meta("osm_id"))
			if col.has_meta("name"):
				out["building_name"] = str(col.get_meta("name"))
	return out


static func _compass(deg: int) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(round(deg / 45.0)) % 8]


func _describe_place(n: Dictionary) -> String:
	var s := "On %s" % n["street"] if str(n.get("street", "")) != "" else "Here"
	if n.has("building"):
		s += ", looking at a building" + (" (%s)" % n["building_name"] if n.has("building_name") else "")
	elif n.has("aim_dist"):
		s += ", looking at a spot %d m away" % n["aim_dist"]
	return s


## The note as plain text, for the clipboard and notes.txt.
func _format(n: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("Charlottetown note %d (%s): %s" % [n["number"], n["time"], n["text"]])
	if n.has("aim_lat"):
		var what := "the ground"
		if n.has("building"):
			what = "building OSM way %s%s" % [n["building"], " \"%s\"" % n["building_name"] if n.has("building_name") else ""]
		lines.append("  Looking at: %s, %d m away, at %.6f, %.6f (game x %.1f, z %.1f)" % [what, n["aim_dist"], n["aim_lat"], n["aim_lon"], n["aim_x"], n["aim_z"]])
	var street := str(n.get("street", ""))
	lines.append("  Standing: %sat %.6f, %.6f (game x %.1f, z %.1f), facing %s (%d degrees)" % [
		("on %s " % street) if street != "" else "", n["lat"], n["lon"], n["x"], n["z"], _compass(int(n.get("facing", 0))), int(n.get("facing", 0))])
	return "\n".join(lines)


# --- pins -------------------------------------------------------------------------------

func _add_pin(n: Dictionary) -> void:
	var world := _world()
	if world == null or not world.is_built:
		return
	if _pins == null:
		_pins = Node3D.new()
		_pins.name = "NotePins"
		add_child(_pins)
	var spot := Vector2(float(n.get("aim_x", n["x"])), float(n.get("aim_z", n["z"])))
	var base := world.terrain.at(spot, 0.0)
	if n.has("aim_y"):
		base.y = maxf(base.y, float(n["aim_y"]))
	var pin := Node3D.new()
	pin.position = base
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.06
	cyl.height = 3.0
	pole.mesh = cyl
	pole.position.y = 1.5
	pole.material_override = Materials.get_shared().glow(Color(1.0, 0.45, 0.1), 1.2)
	pin.add_child(pole)
	var label := Label3D.new()
	label.text = str(n["number"])
	label.font_size = 96
	label.pixel_size = 0.006
	label.outline_size = 18
	label.modulate = Color(1.0, 0.6, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 3.5
	pin.add_child(label)
	_pins.add_child(pin)


# --- odds and ends ------------------------------------------------------------------------

func _world() -> WorldBuilder:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("World") as WorldBuilder


func _load() -> void:
	if not FileAccess.file_exists(JSON_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(JSON_PATH))
	if d is Array:
		_notes = d


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_time = 6.0


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(0, 120)
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var title := Label.new()
	title.text = "Leave a note about this spot"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	_where = Label.new()
	_where.add_theme_font_size_override("font_size", 16)
	_where.modulate = Color(0.85, 0.85, 0.85)
	box.add_child(_where)
	_edit = LineEdit.new()
	_edit.placeholder_text = "e.g. this house is yellow with a red door"
	_edit.add_theme_font_size_override("font_size", 18)
	_edit.text_submitted.connect(_submit)
	box.add_child(_edit)
	var hint := Label.new()
	hint.text = "Enter to save, Esc to cancel. Aim the middle of the screen at what you mean."
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.75, 0.75, 0.75)
	box.add_child(hint)
	_layer.add_child(_panel)
	# Centre it horizontally whatever the window size.
	_panel.resized.connect(func() -> void: _panel.position.x = (_panel.get_viewport_rect().size.x - _panel.size.x) * 0.5)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.position = Vector2(24, 64)
	_toast.visible = false
	_layer.add_child(_toast)

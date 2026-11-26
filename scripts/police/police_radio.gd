class_name PoliceRadio
extends Control
## The police radio on the HUD: short lines during a chase (RadioLines),
## at the top left under the street name, the newest at the bottom, each
## fading after a few seconds. `say(topic)` picks an exchange it hasn't
## used lately and queues it; lines come out one at a time with a pause
## between, so an exchange (the city and the FIP bickering) reads as one.
##
## Game rules never wait on it: it's only words. A server would send the
## topic and the dice, and each client would show it.

## Seconds a line stays up, and between lines.
const SHOW_TIME := 7.0
const GAP := 1.6
## Lines on screen at once.
const MAX_SHOWN := 4
## Topics waiting beyond this many lines are dropped (the moment's passed).
const MAX_QUEUE := 6

## Fills {street}, {colour}, {car}, {count} (set by the dispatcher).
var vars := {}
## The lines said, for checks: [speaker, text]. Every one under a tool
## (`--script`); in the game only the last LOG_KEEP, or it grows all game.
var log: Array = []
const LOG_KEEP := 50
var _tool := OS.get_cmdline_args().has("--script")

var _queue: Array = [] # [who, text, unit]
var _shown: Array = [] # [Label, time left]
var _wait := 0.0
var _recent := {} # topic -> Array of indices used lately
var _rng := RandomNumberGenerator.new()
var _box: VBoxContainer


func _ready() -> void:
	_rng.randomize()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(24, 58)
	size = Vector2(560, 200)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 2)
	add_child(_box)


## Say something on `topic` (a RadioLines topic), from `unit` (its number,
## for "CITY 12"). Returns the lines queued.
func say(topic: String, unit := 0, extra := {}) -> Array:
	var options := RadioLines.topic(topic)
	if options.is_empty():
		return []
	var used: Array = _recent.get(topic, [])
	var pick := -1
	for tries in 6:
		pick = _rng.randi() % options.size()
		if not used.has(pick):
			break
	used.append(pick)
	while used.size() > maxi(1, options.size() - 2):
		used.pop_front()
	_recent[topic] = used
	var v := vars.duplicate()
	v.merge(extra, true)
	if not v.has("unit"):
		v["unit"] = unit
	var out: Array = []
	for line: Array in options[pick]:
		if _queue.size() >= MAX_QUEUE:
			break
		var text := RadioLines.fill(str(line[1]), v)
		_queue.append([str(line[0]), text, unit])
		out.append(text)
	return out


func _process(delta: float) -> void:
	for i in range(_shown.size() - 1, -1, -1):
		var s: Array = _shown[i]
		s[1] = float(s[1]) - delta
		var l: Label = s[0]
		l.modulate.a = clampf(float(s[1]) / 1.2, 0.0, 1.0)
		if float(s[1]) <= 0.0:
			l.queue_free()
			_shown.remove_at(i)
	_wait -= delta
	if _wait > 0.0 or _queue.is_empty():
		return
	var q: Array = _queue.pop_front()
	_wait = GAP
	var who := RadioLines.speaker(str(q[0]), int(q[2]) if str(q[0]) in ["city", "fip"] else 0)
	log.append([who, str(q[1])])
	if log.size() > LOG_KEEP and not _tool:
		log.pop_front()
	if not is_inside_tree():
		return
	var l := Label.new()
	l.text = "%s:  %s" % [who, q[1]]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", _colour_of(str(q[0])))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	_box.add_child(l)
	_shown.append([l, SHOW_TIME])
	while _shown.size() > MAX_SHOWN:
		var old: Array = _shown.pop_front()
		(old[0] as Label).queue_free()


static func _colour_of(who: String) -> Color:
	match who:
		"fip", "fip_hq":
			return Color(1.0, 0.85, 0.45)
		"tac":
			return Color(1.0, 0.6, 0.35)
	return Color(0.75, 0.88, 1.0)

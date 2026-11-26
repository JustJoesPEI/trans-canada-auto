class_name Kinbook
extends Node
## Kinbook, the town's social media, as a phone app (KinbookLines has the
## words). A feed of Charlatown Rants & Raves, Are We Dating the Same
## Fella? and shared ChipIn fundraisers, with the comments under each.
## Your own chases end up on it: a post when a chase gets going (level 2
## and up), and another when you're caught or get away, with your car and
## the street, the way the town would have it up in ten minutes.
##
## Only words: nothing waits on it. The feed moves on a few posts each time
## you come back to it after a while.

## Posts shown at once (yours first, then the town's).
const SHOWN := 10
## Your posts kept.
const YOURS_KEPT := 3
## Coming back after this long (s) moves the feed along.
const MOVE_ON := 90.0

var world: Node
var player: Node3D
var hud: Node

## Your posts, newest first: {group, text, likes, comments, made (s)}.
var yours: Array = []

var _rng := RandomNumberGenerator.new()
var _order: Array = [] # the town's posts, shuffled: ["post" or "chipin", index, ago]
var _start := 0
var _last_look := -1000.0
var _wanted: Node
var _peak := 0 # the highest level in the chase going on
var _vars := {}
var _arrested := false


func setup(w: Node, p: Node3D, h: Node) -> void:
	world = w
	player = p
	hud = h
	_rng.randomize()
	for i in KinbookLines.POSTS.size():
		_order.append(["post", i])
	for i in KinbookLines.CHIPINS.size():
		_order.append(["chipin", i])
	_shuffle(_order)
	for o: Array in _order:
		o.append(KinbookLines.AGO[_rng.randi() % KinbookLines.AGO.size()])
	_wanted = get_tree().root.get_node_or_null("Wanted")
	if _wanted != null:
		_wanted.level_changed.connect(_on_level)
		_wanted.arrested.connect(func(_r: Dictionary) -> void: _arrested = true)
	var phone := Phone.find(get_tree())
	if phone != null:
		phone.add_app("kinbook", "Kinbook", Color(0.3, 0.45, 0.85), _build_tab)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi() % (i + 1)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- your chases ------------------------------------------------------------------------------

func _on_level(level: int) -> void:
	if level > 0:
		_note_vars()
		if level >= 2 and _peak < 2:
			post_about_you("chase")
		_peak = maxi(_peak, level)
		_arrested = false
		return
	# Back to 0: caught (the arrest comes right after) or got away.
	if _peak >= 2:
		_settle.call_deferred()
	_peak = 0


func _settle() -> void:
	post_about_you("caught" if _arrested else "escaped")
	_arrested = false


## What the town would say about you: the car and the street, now.
func _note_vars() -> void:
	var street := ""
	if _wanted != null and world != null and world.has_method("street_name_at"):
		var p: Vector3 = _wanted.get("last_known_position")
		street = world.street_name_at(Vector2(p.x, p.z), 40.0)
	if street != "":
		_vars["street"] = street
	elif not _vars.has("street"):
		_vars["street"] = "downtown"
	var c: Node = player.get("vehicle") if player != null and is_instance_valid(player) else null
	if c is Car:
		_vars["car"] = str(CarModels.get_model((c as Car).model_id)["model"])
		_vars["colour"] = PoliceDispatcher._colour_name((c as Car).paint)
	else:
		_vars["car"] = "guy on foot"
		_vars["colour"] = "sketchy"


## Puts a post about you at the top of the feed ("chase", "caught",
## "escaped"), with a quiet tip that you're on it.
func post_about_you(what: String) -> void:
	var options: Array = KinbookLines.ABOUT_YOU.get(what, [])
	if options.is_empty():
		return
	if _vars.is_empty():
		_note_vars()
	var pick: Dictionary = options[_rng.randi() % options.size()]
	var comments: Array = []
	for c: Array in pick["comments"]:
		comments.append([c[0], KinbookLines.fill(str(c[1]), _vars), c.size() > 2 and bool(c[2])])
	yours.push_front({"group": "rants", "text": KinbookLines.fill(str(pick["text"]), _vars),
		"likes": _rng.randi_range(40, 300), "comments": comments, "made": _now()})
	while yours.size() > YOURS_KEPT:
		yours.pop_back()
	if hud != null and hud.has_method("show_tip"):
		hud.show_tip("Kinbook: you're on Rants & Raves.")


# --- the app ----------------------------------------------------------------------------------

func _build_tab(box: VBoxContainer) -> void:
	if _now() - _last_look > MOVE_ON and _last_look > 0.0:
		_start = (_start + 3) % maxi(1, _order.size())
	_last_look = _now()
	box.add_child(_text("Everybody you know, and their business.", 14, HudStyle.DIM))
	var shown := 0
	for y: Dictionary in yours:
		_add_post(box, y, _ago(float(y["made"])))
		shown += 1
	var i := 0
	while shown < SHOWN and i < _order.size():
		var o: Array = _order[(_start + i) % _order.size()]
		if o[0] == "post":
			_add_post(box, KinbookLines.POSTS[o[1]], str(o[2]))
		else:
			_add_chipin(box, KinbookLines.CHIPINS[o[1]], str(o[2]))
		shown += 1
		i += 1


func _ago(made: float) -> String:
	var mins := int((_now() - made) / 60.0)
	return "Just now" if mins < 1 else "%d min" % mins


func _add_post(box: VBoxContainer, post: Dictionary, ago: String) -> void:
	box.add_child(_gap(10))
	var group := str(KinbookLines.GROUPS.get(str(post["group"]), ""))
	box.add_child(_text(group, 15, HudStyle.ACCENT, true))
	box.add_child(_text("Anonymous member  ·  %s" % ago, 13, HudStyle.DIM))
	box.add_child(_text(str(post["text"]), 15, HudStyle.TEXT))
	box.add_child(_text("%d likes  ·  %d comments" % [int(post.get("likes", 0)), _comment_count(post)], 13, HudStyle.DIM))
	_add_comments(box, post)


func _add_chipin(box: VBoxContainer, f: Dictionary, ago: String) -> void:
	box.add_child(_gap(10))
	box.add_child(_text("%s shared a ChipIn  ·  %s" % [f["by"], ago], 13, HudStyle.DIM))
	box.add_child(_text(str(f["title"]), 16, HudStyle.ACCENT, true))
	var raised := int(f["raised"])
	var goal := int(f["goal"])
	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = mini(raised, goal)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(200, 8)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	back.set_corner_radius_all(4)
	var fill := back.duplicate() as StyleBoxFlat
	fill.bg_color = HudStyle.GOOD
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	box.add_child(_text("%s raised of %s" % [CarModels.dollars(raised), CarModels.dollars(goal)], 13, HudStyle.GOOD if raised >= goal else HudStyle.DIM))
	box.add_child(_text(str(f["text"]), 15, HudStyle.TEXT))
	_add_comments(box, f)


## The comments under a post: replies indented under the one before, and
## the admin's last word on a thread that got out of hand.
func _add_comments(box: VBoxContainer, post: Dictionary) -> void:
	for c: Array in post.get("comments", []):
		var reply := c.size() > 2 and bool(c[2])
		var l := _text(str(c[1]), 14 if not reply else 13, Color(0.86, 0.88, 0.9))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var indent := Control.new()
		indent.custom_minimum_size.x = 22.0 if reply else 0.0
		row.add_child(indent)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_text(str(c[0]), 12 if reply else 13, HudStyle.ACCENT.lerp(Color.WHITE, 0.45)))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 170.0
		col.add_child(l)
		row.add_child(col)
		box.add_child(row)
	if bool(post.get("closed", false)):
		box.add_child(_text("Comments turned off by admin.", 13, HudStyle.WARN))


## A believable comment count: far more than the ones shown.
func _comment_count(post: Dictionary) -> int:
	return int(post.get("likes", 0)) / 3 + (post.get("comments", []) as Array).size()


func _text(text: String, size: int, colour: Color, heading := false) -> Label:
	var l := HudStyle.label(size, heading, colour, false)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	return c

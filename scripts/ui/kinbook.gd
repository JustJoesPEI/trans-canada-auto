class_name Kinbook
extends Node
## Kinbook, the town's social media, as a phone app (docs/kinbook.md). A
## feed, newest first, from four places:
##   - the running stories (KinbookStories.STORIES): one post comes out
##     every few minutes of play, and where each story's got to is saved,
##     so Paulette's very hard time carries on next session;
##   - new posts made from parts (KinbookGen) every minute or so of play;
##   - the written posts (KinbookLines.POSTS and CHIPINS, KinbookStories.WALL),
##     there from the start with older times;
##   - your own chases: a post when a chase gets going (level 2 and up),
##     and another when you're caught or get away, with your car and the
##     street, the way the town would have it up in ten minutes.
##
## Only words: nothing waits on it. New posts come while you play (the
## game's paused while the phone's out), so there's always something new
## next time you look.

## Posts shown at once.
const SHOWN := 14
## Your posts kept.
const YOURS_KEPT := 3
## Seconds of play between story posts, and between made-up posts.
const STORY_EVERY := 240.0
const MADE_EVERY := 70.0
## Made-up posts kept (the oldest go).
const MADE_KEPT := 24
## Story posts that come out at the start of a session after the first
## (the town carried on while you were away).
const WHILE_AWAY := 2

var world: Node
var player: Node3D
var hud: Node

## Your posts, newest first: {group, text, likes, comments, t (unix s)}.
var yours: Array = []

var _rng := RandomNumberGenerator.new()
## Everything else in the feed: {post, t (unix s), made (true for KinbookGen's)}.
var _feed: Array = []
var _used := {} # KinbookGen's posts made this session
var _story_t := 0.0
var _made_t := 0.0
var _wanted: Node
var _peak := 0 # the highest level in the chase going on
var _vars := {}
var _arrested := false


func setup(w: Node, p: Node3D, h: Node) -> void:
	world = w
	player = p
	hud = h
	_rng.randomize()
	var now := _now()
	for post: Dictionary in KinbookLines.POSTS + KinbookLines.CHIPINS + KinbookStories.WALL:
		_feed.append({"post": post, "t": now - _rng.randf_range(20.0 * 60.0, 3.0 * 86400.0), "made": false})
	# Story posts already out (kept in the save), then a couple more for
	# the time away.
	var state := _state()
	var returning := not (state.get("out", []) as Array).is_empty()
	var last_t := 0.0
	for o: Variant in state.get("out", []):
		if o is Array and (o as Array).size() >= 3:
			last_t = maxf(last_t, float(o[2]))
			var post := _story_post(str(o[0]), int(o[1]))
			if not post.is_empty():
				_feed.append({"post": post, "t": float(o[2]), "made": false})
	if returning:
		# After the last one you saw, however long ago that was.
		advance_stories(WHILE_AWAY, maxf(last_t + 60.0, now - _rng.randf_range(10.0 * 60.0, 2.0 * 3600.0)))
	else:
		advance_stories(1, now - 40.0 * 60.0)
	for i in 3:
		_add_made(now - _rng.randf_range(60.0, 40.0 * 60.0))
	_wanted = get_tree().root.get_node_or_null("Wanted")
	if _wanted != null:
		_wanted.level_changed.connect(_on_level)
		_wanted.arrested.connect(func(_r: Dictionary) -> void: _arrested = true)
	var phone := Phone.find(get_tree())
	if phone != null:
		phone.add_app("kinbook", "Kinbook", Color(0.3, 0.45, 0.85), _build_tab)


func _process(delta: float) -> void:
	_story_t += delta
	_made_t += delta
	if _story_t >= STORY_EVERY:
		_story_t = 0.0
		var out := advance_stories(1, _now())
		if not out.is_empty() and hud != null and hud.has_method("show_tip"):
			var by := str((out[0] as Dictionary).get("by", ""))
			hud.show_tip("Kinbook: %s posted." % by if by != "" else "Kinbook: something's going on in Rants & Raves.")
	if _made_t >= MADE_EVERY:
		_made_t = 0.0
		_add_made(_now())


func _now() -> float:
	return Time.get_unix_time_from_system()


# --- the stories ------------------------------------------------------------------------------

func _state() -> Dictionary:
	var gs := get_tree().root.get_node_or_null("GameState") if is_inside_tree() else null
	if gs == null:
		return {}
	var k: Variant = gs.get("kinbook")
	if not k is Dictionary:
		k = {}
		gs.set("kinbook", k)
	if not (k as Dictionary).get("stories") is Dictionary:
		k["stories"] = {}
	if not (k as Dictionary).get("out") is Array:
		k["out"] = []
	return k


func _story_post(id: String, index: int) -> Dictionary:
	var story: Array = KinbookStories.STORIES.get(id, [])
	return story[index] if index >= 0 and index < story.size() else {}


## Puts the next post of `n` stories in the feed (from time `t`, a minute
## apart so they read in order), mostly from stories already going, and
## saves how far they've got. Returns the posts.
func advance_stories(n: int, t: float) -> Array:
	var state := _state()
	if state.is_empty():
		return []
	var progress: Dictionary = state["stories"]
	var out: Array = []
	for i in n:
		var going: Array[String] = []
		var fresh: Array[String] = []
		for id: String in KinbookStories.STORIES:
			var at := int(progress.get(id, 0))
			if at >= (KinbookStories.STORIES[id] as Array).size():
				continue
			if at > 0:
				going.append(id)
			else:
				fresh.append(id)
		if going.is_empty() and fresh.is_empty():
			break
		var pool := going if not going.is_empty() and (fresh.is_empty() or _rng.randf() < 0.7 or going.size() >= 3) else fresh
		var id := pool[_rng.randi() % pool.size()]
		var index := int(progress.get(id, 0))
		progress[id] = index + 1
		var at_t := minf(t + i * 60.0, _now())
		(state["out"] as Array).append([id, index, at_t])
		var post := _story_post(id, index)
		_feed.append({"post": post, "t": at_t, "made": false})
		out.append(post)
	var gs := get_tree().root.get_node_or_null("GameState")
	if gs != null and not out.is_empty():
		gs.call("save_game")
	return out


func _add_made(t: float) -> void:
	_feed.append({"post": KinbookGen.post(_rng, _used), "t": t, "made": true})
	var made := _feed.filter(func(e: Dictionary) -> bool: return e["made"])
	if made.size() > MADE_KEPT:
		made.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
		_feed.erase(made[0])


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
		"likes": _rng.randi_range(40, 300), "comments": comments, "t": _now()})
	while yours.size() > YOURS_KEPT:
		yours.pop_back()
	if hud != null and hud.has_method("show_tip"):
		hud.show_tip("Kinbook: you're on Rants & Raves.")


# --- the app ----------------------------------------------------------------------------------

## The feed, newest first: {post, t}.
func feed() -> Array:
	var all: Array = []
	for y: Dictionary in yours:
		all.append({"post": y, "t": float(y["t"])})
	all.append_array(_feed)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) > float(b["t"]))
	return all.slice(0, SHOWN)


func _build_tab(box: VBoxContainer) -> void:
	box.add_child(_text("Everybody you know, and their business.", 14, HudStyle.DIM))
	for e: Dictionary in feed():
		var post: Dictionary = e["post"]
		if bool(post.get("chipin", false)) or post.has("raised"):
			_add_chipin(box, post, _ago(float(e["t"])))
		else:
			_add_post(box, post, _ago(float(e["t"])))


func _ago(t: float) -> String:
	var s := _now() - t
	if s < 60.0:
		return "Just now"
	if s < 3600.0:
		return "%d min" % int(s / 60.0)
	if s < 86400.0:
		return "%d h" % int(s / 3600.0)
	if s < 2.0 * 86400.0:
		return "Yesterday"
	return "%d d" % int(s / 86400.0)


func _add_post(box: VBoxContainer, post: Dictionary, ago: String) -> void:
	box.add_child(_gap(10))
	var group := str(post.get("group", "rants"))
	var by := str(post.get("by", ""))
	if group == "wall":
		box.add_child(_text(by, 15, HudStyle.ACCENT, true))
		box.add_child(_text("Kinbook friends  ·  %s" % ago, 13, HudStyle.DIM))
	else:
		box.add_child(_text(str(KinbookLines.GROUPS.get(group, "")), 15, HudStyle.ACCENT, true))
		var who := by if by != "" and group != "dating" else "Anonymous member"
		box.add_child(_text("%s  ·  %s" % [who, ago], 13, HudStyle.DIM))
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
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		var indent := Control.new()
		indent.custom_minimum_size.x = 22.0 if reply else 0.0
		row.add_child(indent)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", -2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_text(str(c[0]), 12 if reply else 13, HudStyle.ACCENT.lerp(Color.WHITE, 0.45)))
		var l := _text(str(c[1]), 13 if reply else 14, Color(0.86, 0.88, 0.9))
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

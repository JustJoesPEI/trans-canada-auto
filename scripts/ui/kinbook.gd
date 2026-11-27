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
## It looks like the social media it is: cards with profile pictures, a
## photo when the post's about something you could take a picture of
## (KinbookArt draws them, from the words), reactions, and the comments in
## bubbles. Nothing waits on it. New posts come while you play (the game's
## paused while the phone's out), so there's always something new next
## time you look.

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
var _paint := Color(0, 0, 0, 0) # your car's, for the photo of it (clear on foot: no photo)


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
		_paint = (c as Car).paint
	else:
		_vars["car"] = "guy on foot"
		_vars["colour"] = "sketchy"
		_paint = Color(0, 0, 0, 0)


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
	# Somebody got a photo, if you were in a car.
	yours.push_front({"group": "rants", "text": KinbookLines.fill(str(pick["text"]), _vars),
		"likes": _rng.randi_range(40, 300), "comments": comments, "t": _now(),
		"pic": "chase" if _paint.a > 0.0 else "", "paint": _paint})
	while yours.size() > YOURS_KEPT:
		yours.pop_back()
	if hud != null and hud.has_method("show_tip"):
		hud.show_tip("Kinbook: you're on Rants & Raves.")


## A post about something in town (KinbookLines.SCENES: "brigade",
## "boo_boo") on {street}, into the feed with the made-up posts. No tip:
## it isn't about you.
func post_scene(what: String, street: String) -> void:
	var options: Array = KinbookLines.SCENES.get(what, [])
	if options.is_empty():
		return
	var v := {"street": street if street != "" else "downtown"}
	var pick: Dictionary = options[_rng.randi() % options.size()]
	var comments: Array = []
	for c: Array in pick["comments"]:
		comments.append([c[0], KinbookLines.fill(str(c[1]), v), c.size() > 2 and bool(c[2])])
	var post := {"group": str(pick.get("group", "rants")), "text": KinbookLines.fill(str(pick["text"]), v),
		"likes": int(pick.get("likes", 30)), "comments": comments, "pic": "lights"}
	_feed.append({"post": post, "t": _now(), "made": true})


# --- the app ----------------------------------------------------------------------------------

## The feed, newest first: {post, t}.
func feed() -> Array:
	var all: Array = []
	for y: Dictionary in yours:
		all.append({"post": y, "t": float(y["t"])})
	all.append_array(_feed)
	all.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) > float(b["t"]))
	return all.slice(0, SHOWN)


## The app looks like the social media it is: a light page, a card per
## post with the poster's picture, a photo when there is one, the
## reactions and comment count, and the comments in bubbles under it.
const PAGE := Color("#f0f2f5")
const CARD := Color.WHITE
const INK := Color("#050505")
const GREY := Color("#65676b")
const BUBBLE := Color("#f0f2f5")
const BLUE := Color("#1b74e4")
const RULE := Color("#e4e6eb")
## The groups' pictures: [text, colour].
const GROUP_PICS := {"rants": ["R&R", Color("#c0392b")], "dating": ["?!", Color("#d63384")]}
## Reactions on each kind of post, most first.
const REACTIONS := {"rants": ["like", "haha", "angry"], "dating": ["haha", "love", "angry"],
	"wall": ["like", "love", "haha"], "chipin": ["like", "love", "haha"]}
## A post this short with no photo goes up as big words on colour.
const BIG_WORDS := 60

## The width the feed's laid out to (the phone's screen, less its edges).
var _w := 320.0


func _build_tab(box: VBoxContainer) -> void:
	var phone := Phone.find(get_tree()) if is_inside_tree() else null
	var body: Variant = phone.get("_body") if phone != null else null
	if body is Control and (body as Control).size.x > 100.0:
		_w = (body as Control).size.x - 24.0 - 36.0 - 14.0
	var page := PanelContainer.new()
	var sb := _box_style(PAGE, 12)
	sb.content_margin_bottom = 8
	page.add_theme_stylebox_override("panel", sb)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	page.add_child(col)
	col.add_child(_masthead())
	for e: Dictionary in feed():
		var post: Dictionary = e["post"]
		col.add_child(_card(post, _ago(float(e["t"]))))


## The blue bar and the "What's on your mind?" box.
func _masthead() -> Control:
	var out := VBoxContainer.new()
	out.add_theme_constant_override("separation", 0)
	var bar := PanelContainer.new()
	var sb := _box_style(BLUE, 0)
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	bar.add_child(v)
	v.add_child(_l("kinbook", 26, Color.WHITE, true, false))
	v.add_child(_l("Everybody you know, and their business.", 12, Color(1, 1, 1, 0.85)))
	out.add_child(bar)
	var comp := PanelContainer.new()
	comp.add_theme_stylebox_override("panel", _box_style(CARD, 0, 12, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	comp.add_child(row)
	row.add_child(KinbookArt.avatar("Anonymous", 36))
	var pill := PanelContainer.new()
	var ps := _box_style(Color.WHITE, 18, 14, 7)
	ps.border_color = Color("#ced0d4")
	ps.set_border_width_all(1)
	pill.add_theme_stylebox_override("panel", ps)
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.add_child(_l("What's on your mind?", 14, GREY, false, false))
	row.add_child(pill)
	out.add_child(comp)
	return out


## One post (or ChipIn) as a card.
func _card(post: Dictionary, ago: String) -> Control:
	var chipin := bool(post.get("chipin", false)) or post.has("raised")
	var group := "chipin" if chipin else str(post.get("group", "rants"))
	var by := str(post.get("by", ""))
	var sd := KinbookArt.seed_of(str(post.get("title", "")) + str(post.get("text", "")))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box_style(CARD, 0, 0, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	card.add_child(v)

	# Who, where, when.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var name_text := by
	var meta := ago
	if chipin:
		head.add_child(KinbookArt.avatar(by, 40))
		meta = "ChipIn fundraiser  ·  %s" % ago
	elif group == "wall":
		head.add_child(KinbookArt.avatar(by, 40))
		meta = "%s  ·  Friends" % ago
	else:
		var gp: Array = GROUP_PICS.get(group, ["K", BLUE])
		head.add_child(KinbookArt.avatar(str(gp[0]), 40, true, gp[1], str(gp[0])))
		name_text = str(KinbookLines.GROUPS.get(group, ""))
		var who := by if by != "" and group != "dating" else "Anonymous member"
		meta = "%s  ·  %s" % [who, ago]
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_l(name_text, 15, INK, true))
	names.add_child(_l(meta, 12, GREY))
	head.add_child(names)
	var dots := _l("···", 18, GREY, true, false)
	dots.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(dots)
	v.add_child(_pad(head, 12))

	# What they said, and the photo.
	var text := str(post.get("text", ""))
	var pic := KinbookArt.pic_for(post)
	if pic == "" and group == "wall" and text.length() <= BIG_WORDS:
		v.add_child(_big_words(text, sd))
	else:
		v.add_child(_pad(_l(text, 15, INK), 12))
		if pic != "":
			var paint: Variant = post.get("paint")
			v.add_child(KinbookArt.photo(pic, roundf(_w * 0.58), sd, paint if paint is Color else Color(0.75, 0.1, 0.1)))
	if chipin:
		v.add_child(_pad(_chipin_box(post), 12))

	# Reactions and the count, then the buttons.
	var comments: Array = post.get("comments", [])
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 5)
	var kinds: Array = REACTIONS.get(group, REACTIONS["rants"])
	stats.add_child(KinbookArt.reactions(kinds.slice(0, 2 + sd % 2), 18))
	var likes := int(post.get("likes", 0))
	var first := str((comments[0] as Array)[0]) if not comments.is_empty() else ""
	var count := _l("%d comments" % _comment_count(post), 13, GREY, false, false)
	var lt := _l(str(likes), 13, GREY, false, false)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# "Darlene M. and 133 others", when it fits.
	if first != "" and not first.begins_with("Anonymous") and likes > 1:
		var long := "%s and %d others" % [first, likes - 1]
		var font := lt.get_theme_font("font")
		var room := _w - 24.0 - 50.0 - font.get_string_size(count.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x - 10.0
		if font.get_string_size(long, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x <= room:
			lt.text = long
	stats.add_child(lt)
	stats.add_child(count)
	v.add_child(_pad(stats, 12))
	v.add_child(_pad(_rule(), 12))
	var actions := HBoxContainer.new()
	for a: String in ["Like", "Comment", "Share"]:
		var b := _l(a, 14, GREY, true, false)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)
	v.add_child(_pad(actions, 12))
	v.add_child(_pad(_rule(), 12))

	# The comments: the point of the whole thing.
	var thread := VBoxContainer.new()
	thread.add_theme_constant_override("separation", 6)
	for c: Array in comments:
		thread.add_child(_comment(c, by))
	if bool(post.get("closed", false)):
		var shut := PanelContainer.new()
		shut.add_theme_stylebox_override("panel", _box_style(Color("#fff4e5"), 8, 10, 5))
		shut.add_child(_l("Comments turned off by admin.", 13, Color("#8a4b00"), true))
		thread.add_child(shut)
	v.add_child(_pad(thread, 12))
	return card


## A short post with no photo: big words on colour, centred.
func _big_words(text: String, sd: int) -> Control:
	var pair: Array = KinbookArt.BACKDROPS[sd % KinbookArt.BACKDROPS.size()]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.custom_minimum_size.y = roundf(_w * 0.5)
	panel.draw.connect(func() -> void:
		var s := panel.size
		panel.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([pair[0], pair[0].lerp(pair[1], 0.5), pair[1], pair[0].lerp(pair[1], 0.5)])))
	var l := _l(text, 22, Color.WHITE, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_child(l)
	panel.add_child(m)
	return panel


## A ChipIn's title, how it's going, and the button.
func _chipin_box(f: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.add_child(_l(str(f.get("title", "")), 16, INK, true))
	var raised := int(f.get("raised", 0))
	var goal := maxi(1, int(f.get("goal", 1)))
	var bar := ProgressBar.new()
	bar.max_value = goal
	bar.value = mini(raised, goal)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("background", _box_style(RULE, 4))
	bar.add_theme_stylebox_override("fill", _box_style(Color("#31a24c"), 4))
	v.add_child(bar)
	var done := raised >= goal
	v.add_child(_l("%s raised of %s" % [CarModels.dollars(raised), CarModels.dollars(goal)], 13,
		Color("#31a24c") if done else GREY, done))
	var give := PanelContainer.new()
	give.add_theme_stylebox_override("panel", _box_style(Color("#e7f3ff"), 6, 10, 6))
	var gl := _l("Chip In", 14, BLUE, true, false)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	give.add_child(gl)
	v.add_child(give)
	return v


## A comment: their picture and a grey bubble with their name over what
## they said; a reply sits in under the one before, smaller.
func _comment(c: Array, author: String) -> Control:
	var reply := c.size() > 2 and bool(c[2])
	var who := str(c[0])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var indent := 38.0 if reply else 0.0
	if reply:
		var gap := Control.new()
		gap.custom_minimum_size.x = indent - 6.0
		row.add_child(gap)
	var d := 26.0 if reply else 32.0
	row.add_child(KinbookArt.avatar(who, d))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", _box_style(BUBBLE, 14, 11, 6))
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bubble)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 0)
	bubble.add_child(inner)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.add_child(_l(who, 13, INK, true, false))
	if author != "" and who == author:
		name_row.add_child(_l("Author", 11, BLUE, true, false))
	inner.add_child(name_row)
	# The bubble's as wide as what they said, up to the width there is.
	var most := _w - 24.0 - indent - d - 6.0 - 22.0
	var l := _l(str(c[1]), 14, INK, false, false)
	var wide := l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	if wide > most:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = most
	inner.add_child(l)
	var under := _l("Like     Reply", 11, GREY, true, false)
	var um := MarginContainer.new()
	um.add_theme_constant_override("margin_left", 11)
	um.add_child(under)
	col.add_child(um)
	return row


## A believable comment count: far more than the ones shown.
func _comment_count(post: Dictionary) -> int:
	return int(post.get("likes", 0)) / 3 + (post.get("comments", []) as Array).size()


## A label: the body font, or bold for names; wrapping unless `wrap` is off.
func _l(text: String, size: int, colour: Color, bold := false, wrap := true) -> Label:
	var l := HudStyle.label(size, false, colour, false)
	if bold:
		l.add_theme_font_override("font", KinbookArt.bold_font())
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _pad(node: Control, side: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", side)
	m.add_theme_constant_override("margin_right", side)
	m.add_child(node)
	return m


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = RULE
	r.custom_minimum_size.y = 1
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _box_style(colour: Color, radius: int, h_margin := 0, v_margin := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = colour
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	sb.content_margin_left = h_margin
	sb.content_margin_right = h_margin
	sb.content_margin_top = v_margin
	sb.content_margin_bottom = v_margin
	return sb


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

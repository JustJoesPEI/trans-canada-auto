extends SceneTree
## Checks Kinbook (scripts/ui/kinbook.gd) and the people-on-foot lines
## (scripts/people/pedestrian_lines.gd), headless and without the town:
##
##   godot --headless --path . --script res://tools/kinbook_check.gd
##
## Kinbook goes on the phone; a chase that reaches level 2 puts a post
## about you at the top with the car and street filled in, and getting
## caught or getting away adds another; the feed shows the town's posts
## and ChipIns under yours, every blank filled. The pedestrian lines: every
## chat is two to four lines, every ride line with a street has one "%s",
## and pick() doesn't repeat a line said lately. One "KINBOOK" line per
## check; exits non-zero with "KINBOOK FAIL" lines if any fail.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("KINBOOK ok   %s" % what)
	else:
		_failures += 1
		print("KINBOOK FAIL %s" % what)


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_check_pedestrians()
	var gs := root.get_node("GameState")
	var had_save := FileAccess.file_exists("user://savegame.json")
	var saved := FileAccess.get_file_as_bytes("user://savegame.json") if had_save else PackedByteArray()
	gs.call("reset_save")
	_check_content()
	await _check_kinbook()
	await _check_stories(gs)
	if had_save:
		var f := FileAccess.open("user://savegame.json", FileAccess.WRITE)
		f.store_buffer(saved)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://savegame.json"))
	gs.call("load_game")
	print("KINBOOK %s" % ("all checks passed" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_pedestrians() -> void:
	var ok := true
	for c: Array in PedestrianLines.CHATS:
		ok = ok and c.size() >= 2 and c.size() <= 4
	_check(ok, "every chat is 2 to 4 lines (%d chats)" % PedestrianLines.CHATS.size())
	ok = true
	for l: String in PedestrianLines.BOARD:
		ok = ok and l.count("%s") == 1
	_check(ok, "every boarding line has one street")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	var repeats := 0
	for i in 20:
		var l := PedestrianLines.pick(rng, PedestrianLines.ANYONE)
		if seen.has(l):
			repeats += 1
		seen[l] = true
	_check(repeats == 0, "20 thoughts in a row without a repeat (%d)" % repeats)
	var total := PedestrianLines.ANYONE.size()
	for k: String in PedestrianLines.BY_KIND:
		total += (PedestrianLines.BY_KIND[k] as Array).size()
	_check(total >= 150, "plenty of thoughts (%d)" % total)


func _check_kinbook() -> void:
	var phone := Phone.new()
	root.add_child(phone)
	var kb := Kinbook.new()
	root.add_child(kb)
	kb.setup(null, null, null)
	await process_frame
	_check(phone.get("_apps").has("kinbook"), "Kinbook is on the phone")
	var wanted := root.get_node_or_null("Wanted")
	_check(wanted != null, "Wanted is there")
	if wanted == null:
		return
	wanted.set("play_panels", false)
	wanted.call("_set_level", 1)
	_check(kb.yours.is_empty(), "nothing posted at level 1")
	wanted.call("_set_level", 2)
	_check(kb.yours.size() == 1, "a post when the chase reaches level 2")
	wanted.call("_set_level", 3)
	_check(kb.yours.size() == 1, "only one chase post per chase")
	wanted.call("caught")
	await process_frame
	var first := str(kb.yours[0]["text"]) if not kb.yours.is_empty() else ""
	_check(kb.yours.size() == 2 and (first.contains("caught") or first.contains("got the")),
		"a caught post after the arrest: %s" % str(kb.yours[0]["text"]).left(60))
	wanted.call("_set_level", 2)
	wanted.call("clear")
	await process_frame
	_check(kb.yours.size() == 3, "a got-away post when the chase ends without an arrest")
	var blanks := false
	for y: Dictionary in kb.yours:
		blanks = blanks or str(y["text"]).contains("{")
	_check(not blanks, "every blank filled in")
	var box := VBoxContainer.new()
	kb._build_tab(box)
	var texts: Array[String] = []
	for c in box.find_children("*", "Label", true, false):
		texts.append((c as Label).text)
	var joined := "\n".join(texts)
	_check(joined.contains("Charlatown Rants & Raves"), "the feed shows Rants & Raves")
	_check(not joined.contains("{"), "no blanks anywhere in the feed")
	_check(texts.size() > 60, "a full feed (%d lines)" % texts.size())
	var ok := true
	for p: Dictionary in KinbookLines.POSTS + KinbookLines.CHIPINS:
		ok = ok and (p.get("comments", []) as Array).size() >= 2 and not (p["comments"][0] as Array).size() > 2
	_check(ok, "every post has a thread, and none starts with a reply")
	box.free()


## Every written post is whole, and the made-up ones don't run dry.
func _check_content() -> void:
	var bad: Array[String] = []
	var all: Array = KinbookLines.POSTS + KinbookLines.CHIPINS + KinbookStories.WALL
	for id: String in KinbookStories.STORIES:
		all.append_array(KinbookStories.STORIES[id])
	for p: Dictionary in all:
		var text := str(p.get("text", ""))
		if text == "" or text.contains("{") or (p.get("comments", []) as Array).size() < 2:
			bad.append(text.left(40))
		elif str(p.get("group", "")) == "wall" and str(p.get("by", "")) == "":
			bad.append("no poster: " + text.left(30))
		elif ((p["comments"] as Array)[0] as Array).size() > 2:
			bad.append("starts with a reply: " + text.left(30))
	_check(bad.is_empty(), "%d written posts, all whole %s" % [all.size(), bad])
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var used := {}
	var blanks := 0
	var kinds := {}
	for i in 300:
		var p := KinbookGen.post(rng, used)
		if (str(p.get("text", "")) + str(p.get("comments", []))).contains("{"):
			blanks += 1
		kinds[str(p.get("group", "chipin"))] = true
	_check(blanks == 0, "300 made-up posts, every blank filled (%d)" % blanks)
	_check(used.size() >= 280, "300 made-up posts, %d different" % used.size())
	_check(kinds.size() >= 4, "made-up posts of every kind %s" % [kinds.keys()])


## Stories come out one post at a time, keep their place in the save, and
## pick up from there next session.
func _check_stories(gs: Node) -> void:
	gs.set("kinbook", {})
	var kb := Kinbook.new()
	root.add_child(kb)
	kb.setup(null, null, null)
	var k: Dictionary = gs.get("kinbook")
	var out: Array = k.get("out", [])
	_check(out.size() == 1, "a new player gets the first story post (%d)" % out.size())
	kb.advance_stories(5, Time.get_unix_time_from_system())
	_check((k["out"] as Array).size() == 6, "five more story posts")
	var progress: Dictionary = k["stories"]
	var total := 0
	for id: String in progress:
		total += int(progress[id])
	_check(total == 6, "the save counts six posts out")
	var json := FileAccess.get_file_as_string("user://savegame.json")
	_check(json.contains("\"kinbook\""), "story progress is in the save file")
	kb.queue_free()
	await process_frame
	gs.call("load_game")
	var kb2 := Kinbook.new()
	root.add_child(kb2)
	kb2.setup(null, null, null)
	var k2: Dictionary = gs.get("kinbook")
	_check((k2["out"] as Array).size() == 6 + Kinbook.WHILE_AWAY, "next session carries on, plus %d for the time away" % Kinbook.WHILE_AWAY)
	var all_out := 0
	for i in 200:
		all_out += kb2.advance_stories(1, Time.get_unix_time_from_system()).size()
	var story_posts := 0
	for id: String in KinbookStories.STORIES:
		story_posts += (KinbookStories.STORIES[id] as Array).size()
	_check((k2["out"] as Array).size() == story_posts, "every story runs to its end and stops (%d posts)" % story_posts)
	var in_order := true
	var seen_at := {}
	for o: Array in k2["out"]:
		var key := str(o[0])
		if seen_at.has(key) and float(o[2]) < float(seen_at[key]):
			in_order = false
		seen_at[key] = float(o[2])
	_check(in_order, "each story's posts come out in time order")
	var texts := ""
	for e: Dictionary in kb2.feed():
		texts += str(e["post"].get("text", ""))
	_check(texts != "" and not texts.contains("{"), "the feed after all of it reads right")
	kb2.queue_free()

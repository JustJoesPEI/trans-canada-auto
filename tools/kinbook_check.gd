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
	await _check_kinbook()
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

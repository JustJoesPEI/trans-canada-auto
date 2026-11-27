extends SceneTree
## Checks the wanted level's rules (scripts/wanted/, design.md section 7)
## without the town or the police:
##
##   godot --headless --path . --script res://tools/wanted_check.gd
##
## Crimes raise the level, the escape clock drops it one level at a time
## only while unseen, being seen restarts it, the car wash clears it only
## when unseen (and washes the paint either way), caught() fines within
## the 10% cap and clears, and the case falls apart about one time in
## eight. Prints "WANTED FAIL" lines and exits non-zero on any failure.
## The save file is put back exactly as it was.

const SAVE := "user://savegame.json"

var _fails := 0
var _checks := 0
var W: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	var had_save := FileAccess.file_exists(SAVE)
	var save_bytes := FileAccess.get_file_as_bytes(SAVE) if had_save else PackedByteArray()
	var money_before: int = root.get_node("GameState").get("money")
	W = root.get_node_or_null("Wanted")
	_check(W != null, "the Wanted autoload exists")
	if W != null:
		W.auto_tick = false
		W.play_panels = false
		var me := Node3D.new()
		root.add_child(me)
		W.target = me
		_crimes()
		_reporting()
		_escape(me)
		_car_wash(me)
		_caught()
		_dismissals()
		_lines()
		me.free()
		await _player_in_a_car()
	# Put the save back as it was.
	var gs := root.get_node("GameState")
	gs.set("money", money_before)
	if had_save:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_buffer(save_bytes)
		f.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("WANTED %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("WANTED FAIL ", what)


func _reset() -> void:
	W.clear()
	W.clock = 0.0
	W._last_seen = -1000.0
	W.debug_watching = false


func _tick(seconds: float, step := 0.1) -> void:
	var t := 0.0
	while t < seconds - 0.0001:
		W.tick(step)
		t += step


func _crimes() -> void:
	_reset()
	var at := Vector3(10, 0, 10)
	_check(W.level == 0 and W.search_radius == 0.0, "starts at level 0")
	W.report_crime("paint_bystander", at)
	_check(W.level == 1, "painting a bystander: level 1 (got %d)" % W.level)
	_check(W.level_name() == "Someone called your mother", "level 1's name")
	_check(W.last_known_position == at, "the crime puts the circle on it")
	while W.heat + 1.0 < W.HEAT_FOR_LEVEL[2]:
		W.report_crime("paint_car", at)
	_check(W.level == 1, "a few short stays at 1 (got %d, heat %.0f)" % [W.level, W.heat])
	W.report_crime("paint_car", at)
	_check(W.level == 2, "a few more: level 2 (got %d)" % W.level)
	while W.heat + 1.0 < W.HEAT_FOR_LEVEL[3]:
		W.report_crime("paint_bystander", at)
	_check(W.level == 2, "keeping it up, short of 3 (got %d)" % W.level)
	W.report_crime("paint_bystander", at)
	_check(W.level == 3, "keeping it up at 2: level 3 (got %d)" % W.level)
	# Painting the police climbs fastest: two officers put out from level 2.
	_reset()
	W.report_crime("paint_police", at)
	W.report_crime("police_out", at)
	W.report_crime("paint_police", at)
	W.report_crime("police_out", at)
	_check(W.level == 3, "painting two officers out: level 3 (got %d, heat %.0f)" % [W.level, W.heat])
	_reset()
	W.report_crime("paint_bystander", at)
	_check(W.level == 1 and W.heat == W.HEAT_FOR_LEVEL[1], "one bystander: level 1, heat at its step")
	_reset()
	W.report_crime("paint_police", at)
	_check(W.level == 2, "painting a cop: straight to 2 (got %d)" % W.level)
	_reset()
	W.report_crime("flee", at)
	_check(W.level == 2, "driving off from a cop's lights: 2")
	_reset()
	W.report_crime("car_meet", at)
	_check(W.level == 2, "shooting at a car meet: 2")
	_reset()
	W.report_crime("paint_fip", at)
	_check(W.level == 3, "painting the FIP: straight to 3 (got %d)" % W.level)
	_check(W.search_radius > W.SEARCH_RADIUS[2], "the circle is bigger at 3 than 2")
	# 90 s more at 3 with the police on you: level 4.
	var t := 0.0
	while t < W.LEVEL_4_AFTER + 1.0 and W.level == 3:
		W.police_saw_player(at)
		W.tick(0.5)
		t += 0.5
	_check(W.level == 4, "about 90 s more at level 3: level 4 (got %d after %.0f s)" % [W.level, t])
	_check(t >= W.LEVEL_4_AFTER - 1.0, "not before 90 s (%.0f s)" % t)
	_check(W.level_name() == "Federal Overreach", "level 4's name")
	# A crime never lowers the level.
	W.report_crime("paint_bystander", at)
	_check(W.level == 4, "a small crime doesn't lower it")
	# Overtime: five minutes at 4 and the tactical unit goes home.
	_reset()
	W.report_crime("paint_tactical", at)
	_check(W.level == 4, "painting the tactical unit: 4")
	t = 0.0
	while t < W.OVERTIME_SECONDS + 2.0 and W.level == 4:
		W.police_saw_player(at)
		W.tick(1.0)
		t += 1.0
	_check(W.level == 3, "over the overtime budget: back to 3 (got %d)" % W.level)
	t = 0.0
	while t < W.LEVEL_4_AFTER * 2.0:
		W.police_saw_player(at)
		W.tick(1.0)
		t += 1.0
	_check(W.level == 3, "and it doesn't come straight back to 4 on time alone")
	_reset()
	W.report_crime("no_such_crime", at)
	_check(W.level == 1, "an unknown crime counts as a small one")
	_reset()


func _escape(me: Node3D) -> void:
	var levels_seen: Array[int] = []
	W.level_changed.connect(func(l: int) -> void: levels_seen.append(l))
	_reset()
	me.global_position = Vector3(0, 0, 0)
	W.report_crime("paint_fip", Vector3.ZERO)
	_check(W.level == 3, "set up at 3")
	levels_seen.clear()
	# Far outside the circle, out of sight.
	me.global_position = Vector3(5000, 0, 0)
	_tick(W.ESCAPE_SECONDS[3] - 1.0)
	_check(W.level == 3, "not yet: still 3 after %.0f s" % (W.ESCAPE_SECONDS[3] - 1.0))
	# Seen again: the clock starts over.
	W.police_saw_player(me.global_position)
	_check(W.seen_recently(), "seen_recently right after being seen")
	_check(W.escape_time == 0.0, "being seen restarts the clock")
	# They saw you there, so that's the new middle of the circle: get clear of it.
	me.global_position = Vector3(-5000, 0, 0)
	_tick(W.ESCAPE_SECONDS[3] - 1.0)
	_check(W.level == 3, "seen resets the timer: still 3 a full 89 s later")
	_tick(3.0)
	_check(W.level == 2, "then out of sight long enough: one level down to 2 (got %d)" % W.level)
	_check(levels_seen == [2], "dropped one level at a time (%s)" % str(levels_seen))
	_tick(W.ESCAPE_SECONDS[2] + 0.5)
	_check(W.level == 1, "another 60 s: 1 (got %d)" % W.level)
	_tick(W.ESCAPE_SECONDS[1] + 0.5)
	_check(W.level == 0, "another 20 s: 0 (got %d)" % W.level)
	_check(levels_seen == [2, 1, 0], "one level at a time all the way (%s)" % str(levels_seen))
	# While seen, it never drops.
	_reset()
	W.report_crime("paint_bystander", Vector3.ZERO)
	for i in 600:
		W.police_saw_player(me.global_position)
		W.tick(0.1)
	_check(W.level == 1, "seen the whole time: no escape at all")
	# Inside the circle the clock runs slower.
	_reset()
	W.report_crime("paint_bystander", Vector3.ZERO)
	me.global_position = Vector3(5, 0, 5)
	_tick(W.ESCAPE_SECONDS[1] + 1.0)
	_check(W.level == 1, "hiding inside the circle is slower")
	_tick(W.ESCAPE_SECONDS[1])
	_check(W.level == 0, "but works in the end")
	# Speed never counts: nothing to report, nothing changes.
	_check(not W.CRIMES.has("speeding"), "speeding is not a crime")
	_reset()


func _car_wash(me: Node3D) -> void:
	# The rule itself.
	_reset()
	W.report_crime("paint_fip", Vector3.ZERO)
	W.police_saw_player(Vector3.ZERO)
	_check(not W.car_wash(), "seen going in: the wash does nothing")
	_check(W.level == 3, "still 3 after a seen wash")
	_check(W.wash_wait() < 0.0, "hardly seen at level 3: the HUD says waiting won't make the wash work")
	# A real chase: they've had you in sight a while.
	for i in int(W.WASH_SEEN) + 1:
		W.police_saw_player(Vector3.ZERO)
		W.tick(1.0)
	W.tick(W.SEEN_MEMORY + 0.5)
	_check(not W.car_wash(), "at level 3, just out of sight: too soon, the wash does nothing")
	_check(W.level == 3, "still 3 after a too-soon wash")
	_check(W.wash_wait() > 0.0, "too soon: the HUD counts down to the wash working (%.0f s)" % W.wash_wait())
	W.tick(maxf(W.WASH_UNSEEN / W.INSIDE_CIRCLE_RATE, W.WASH_MIN_CHASE) + 1.0) # inside the search circle its clock runs slower; and a chase this long
	_check(W.wash_wait() == 0.0, "unseen a while: the HUD says the wash works now")
	_check(W.car_wash(), "unseen a while: the wash clears it")
	_check(W.level == 0, "level 0 after an unseen wash")
	# The bay, with a stand-in car and a stand-in PaintCoverage.
	var washes := CarWashes.new()
	root.add_child(washes)
	washes.spots = [{"xform": Transform3D(Basis.IDENTITY, Vector3(100, 0, 100)), "name": "Test wash", "line": ""}]
	var car := Node3D.new()
	root.add_child(car)
	var pc := Node.new()
	pc.name = "PaintCoverage"
	pc.set_script(_coverage_script())
	car.add_child(pc)
	car.global_position = Vector3(0, 0, 0)
	_check(washes.update(0.1, car) == "", "outside the bay: nothing")
	# Unseen, all the way through.
	_reset()
	W.report_crime("paint_police", Vector3.ZERO)
	W.tick(2.0)
	car.global_position = Vector3(100, 0, 106)
	_check(washes.update(0.1, car) == "enter", "rolling in")
	var got := ""
	for i in 100:
		var r: String = washes.update(0.1, car)
		if r != "":
			got = r
			break
	_check(got == "cleared", "unseen through the wash: cleared (got '%s')" % got)
	_check(W.level == 0, "and the level is 0")
	_check(int(pc.get("cleared")) == 1, "the paint came off (PaintCoverage.clear called)")
	car.global_position = Vector3.ZERO
	washes.update(0.1, car)
	# Seen while inside: paint off, level stays.
	_reset()
	W.report_crime("paint_police", Vector3.ZERO)
	W.tick(2.0)
	car.global_position = Vector3(100, 0, 100)
	washes.update(0.1, car)
	got = ""
	for i in 100:
		if i == 20:
			W.police_saw_player(car.global_position)
		var r: String = washes.update(0.1, car)
		W.tick(0.1)
		if r != "":
			got = r
			break
	_check(got == "seen", "seen while inside: no clearing (got '%s')" % got)
	_check(W.level == 2, "the level stays when they saw (got %d)" % W.level)
	_check(int(pc.get("cleared")) == 2, "the paint still comes off")
	# Driving straight through in a second clears nothing.
	car.global_position = Vector3.ZERO
	washes.update(0.1, car)
	_reset()
	W.report_crime("paint_bystander", Vector3.ZERO)
	W.tick(2.0)
	car.global_position = Vector3(100, 0, 100)
	washes.update(0.1, car)
	washes.update(1.0, car)
	car.global_position = Vector3.ZERO
	_check(washes.update(0.1, car) == "leave", "blasting through: out again")
	_check(W.level == 1, "too quick: still wanted")
	# A car with no paint coverage at all is fine.
	var bare := Node3D.new()
	_check(not CarWashes.wash_paint(bare), "no PaintCoverage: nothing to clear, no error")
	bare.free()
	car.free()
	washes.free()
	_reset()


func _coverage_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar cleared := 0\nfunc clear() -> void:\n\tcleared += 1\n"
	s.reload()
	return s


func _caught() -> void:
	var gs := root.get_node("GameState")
	_reset()
	_check(W.caught().is_empty(), "caught at level 0: nothing happens")
	for lvl in range(1, 5):
		for cash: int in [0, 9, 100, 349, 1000, 1000000]:
			_reset()
			gs.set("money", cash)
			W.debug_set_level(lvl)
			W.rng.seed = 1 # the first roll of seed 1 isn't a dismissal (checked below)
			var r: Dictionary = W.caught()
			_check(W.level == 0, "caught clears the level")
			_check(bool(r.get("ticket", false)) == (lvl == 1), "level 1 is a ticket, the rest jail (level %d)" % lvl)
			if bool(r["dismissed"]):
				_check(int(r["fine"]) == 0 and int(gs.get("money")) == cash, "dismissed: no fine")
				continue
			var fine := int(r["fine"])
			_check(fine <= floori(cash * 0.1), "fine %d within 10%% of %d" % [fine, cash])
			_check(fine == mini(W.FINES[lvl], floori(cash * 0.1)), "fine is the level's, capped (%d at level %d, cash %d)" % [fine, lvl, cash])
			_check(int(gs.get("money")) == cash - fine, "the fine is taken from cash")
	for lvl in range(1, 4):
		_check(W.FINES[lvl] < W.FINES[lvl + 1], "fines grow with the level")
	_check(W.FINES[4] == 85, "Fine: $85 at level 4")
	gs.set("money", 0)


## A crime only counts once the police hear of it.
func _reporting() -> void:
	_reset()
	var at := Vector3(40, 0, 40)
	W.unreported_crime("paint_bystander", at)
	_check(W.level == 0 and W.unreported.size() == 1, "unseen, unreported: no stars yet")
	W.phone_call(self, true)
	_check(W.being_called_in(), "a witness on the phone shows")
	W.phone_call(self, false)
	_check(not W.being_called_in(), "and stops when they hang up")
	W.witness_report(at + Vector3(300, 0, 0))
	_check(W.level == 0 and W.unreported.size() == 1, "a call about somewhere else doesn't report it")
	W.witness_report(at + Vector3(10, 0, 0))
	_check(W.level == 1 and W.unreported.is_empty(), "a witness gets through: level 1 (got %d)" % W.level)
	_check(W.last_known_position.distance_to(at + Vector3(10, 0, 0)) < 0.01, "the circle goes where they saw you")
	# A driver who lost you: where they last saw you, the crimes where it happened.
	_reset()
	W.unreported_crime("paint_car", at)
	W.witness_report(at + Vector3(400, 0, 0), at)
	_check(W.level == 1 and W.last_known_position.x > at.x + 300.0, "a call matches the crime where it happened, the circle where they lost you")
	# Nobody calls: forgotten.
	_reset()
	W.unreported_crime("paint_bystander", at)
	_tick(W.UNREPORTED_MEMORY + 1.0, 1.0)
	_check(W.unreported.is_empty(), "nobody called: forgotten after %.0f s" % W.UNREPORTED_MEMORY)
	W.witness_report(at)
	_check(W.level == 0, "a late call about nothing: still 0")
	# Wanted and in sight, the police are watching: it counts.
	_reset()
	W.report_crime("paint_bystander", at)
	W.police_saw_player(at)
	var h: float = W.heat
	W.unreported_crime("paint_bystander", at)
	_check(W.heat > h and W.unreported.is_empty(), "in sight, a crime counts at once")
	# Dropping a level cools the heat to its step.
	_reset()
	W.report_crime("paint_police", at)
	W.report_crime("police_out", at)
	_tick(W.ESCAPE_SECONDS[2] / W.INSIDE_CIRCLE_RATE + 1.0, 0.5)
	_check(W.level == 1 and W.heat == W.HEAT_FOR_LEVEL[1], "down a level, heat back to its step (%d, %.0f)" % [W.level, W.heat])


func _dismissals() -> void:
	var gs := root.get_node("GameState")
	W.rng.seed = 12345
	var n := 8000
	var dismissed := 0
	for i in n:
		gs.set("money", 1000)
		W.debug_set_level(1 + i % 4)
		var r: Dictionary = W.caught()
		if bool(r["dismissed"]):
			dismissed += 1
			_check(int(r["fine"]) == 0, "a dismissed case has no fine")
	var rate := float(dismissed) / n
	print("WANTED dismissals: %d of %d (%.3f, aim 0.125)" % [dismissed, n, rate])
	_check(absf(rate - 0.125) < 0.015, "about one in eight dismissed (%.3f)" % rate)
	gs.set("money", 0)


func _lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p: Array = JailLines.panels({"level": 2, "dismissed": false, "fine": 55}, rng)
	_check(p.size() == 3 and str(p[0]["caption"]) == "Two years less a day." and str(p[1]["caption"]) == "Time served: less a day.", "the three panels")
	_check(str(p[2]["caption"]).contains("$55"), "the fine on the last panel")
	p = JailLines.panels({"level": 4, "dismissed": false, "fine": 85}, rng)
	_check(p.size() == 4 and str(p[3]["caption"]) == "Cost to taxpayers: $4.2 million. Fine: $85.", "the level 4 panel")
	p = JailLines.panels({"level": 3, "dismissed": true, "fine": 0}, rng)
	_check(JailLines.DISMISSALS.has(str(p[1]["caption"])), "a dismissal line")
	for k: String in JailLines.ART:
		_check(ResourceLoader.exists(JailLines.ART[k]), "panel art %s exists" % k)
	_check(ResourceLoader.exists(JailPanels.FONT), "the caption font is in the game")
	_check(JailLines.dollars(4200000) == "$4,200,000", "dollars()")


## The player is found wherever they are: in a car they're moved under its
## seat, and a lookup by path used to lose them, so the search circle
## thought they were always inside it (the escape clock at half speed).
func _player_in_a_car() -> void:
	W.target = null
	var player := Node3D.new()
	player.add_to_group(PlayerController.GROUP)
	root.add_child(player)
	var car := Node3D.new()
	root.add_child(car)
	player.reparent(car)
	await process_frame
	W.debug_set_level(2)
	W.last_known_position = Vector3.ZERO
	car.global_position = Vector3(W.search_radius + 300.0, 0.0, 0.0)
	_check(W.player_position().distance_to(car.global_position) < 0.5, "the player is followed into a car (by group, not by path)")
	_check(not W.inside_search_circle(), "far from where they were seen, in a car, is outside the search circle")
	W.debug_set_level(0)
	W.target = null
	car.free()

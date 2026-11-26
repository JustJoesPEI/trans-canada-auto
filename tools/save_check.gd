extends SceneTree
## Checks the save file survives being damaged (GameState.save_game,
## load_game): saves write through a temporary file with the last good save
## kept as a backup, and a damaged save falls back to that backup instead of
## starting over.
##
##   godot --headless --path . --script res://tools/save_check.gd
##
## Puts the real save files back as they were. Exits non-zero on failure.

var _fails := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print(("ok    " if ok else "FAIL  ") + what)


func _run() -> void:
	var gs: Node = root.get_node("GameState")
	var paths: Array[String] = [gs.SAVE_PATH, gs.BACKUP_PATH, gs.SAVE_PATH + ".damaged", gs.SAVE_PATH + ".tmp"]
	var kept := {}
	for p in paths:
		if FileAccess.file_exists(p):
			kept[p] = FileAccess.get_file_as_bytes(p)
	var money_before: int = gs.money

	gs.money = 111
	gs.save_game()
	gs.money = 222
	gs.save_game()
	_check(FileAccess.file_exists(gs.SAVE_PATH) and not FileAccess.file_exists(gs.SAVE_PATH + ".tmp"), "a save is written whole, no temporary file left")
	_check(FileAccess.file_exists(gs.BACKUP_PATH), "the previous save is kept as a backup")

	# Damage the save, as a crash mid-write could.
	var f := FileAccess.open(gs.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{\"version\": 1, \"money\": 22")
	f.close()
	gs.money = 0
	gs.load_game()
	_check(gs.money == 111, "a damaged save falls back to the last good one (money %d)" % gs.money)
	_check(FileAccess.file_exists(gs.SAVE_PATH + ".damaged"), "the damaged save is kept aside")
	gs.money = 333
	gs.save_game()
	gs.money = 0
	gs.load_game()
	_check(gs.money == 333, "and saving carries on from there")

	# In the game, saves wait for the end of the frame and go on a worker.
	gs.deferred_saves = true
	gs.money = 444
	gs.save_game()
	gs.money = 555
	gs.save_game()
	_check(int(gs._read_save(gs.SAVE_PATH).get("money", 0)) == 333, "a save in the game waits for the end of the frame")
	await process_frame
	gs.flush_save()
	_check(int(gs._read_save(gs.SAVE_PATH).get("money", 0)) == 555, "then the frame's changes are one save (money %d)" % int(gs._read_save(gs.SAVE_PATH).get("money", 0)))
	_check(int(gs._read_save(gs.BACKUP_PATH).get("money", 0)) == 333 and not FileAccess.file_exists(gs.SAVE_PATH + ".tmp"), "written whole, the save before it kept as the backup")
	gs.money = 666
	gs.save_game()
	gs.flush_save()
	_check(int(gs._read_save(gs.SAVE_PATH).get("money", 0)) == 666, "flush_save (quitting) writes one still waiting")
	gs.deferred_saves = false

	# Put everything back.
	for p in paths:
		if kept.has(p):
			var w := FileAccess.open(p, FileAccess.WRITE)
			w.store_buffer(kept[p])
			w.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	gs.money = money_before
	print("SAVE %d checks, %d failed" % [_checks, _fails])
	quit(1 if _fails > 0 else 0)

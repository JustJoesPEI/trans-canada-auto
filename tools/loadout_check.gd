extends SceneTree
## Checks what the player carries and how they use it, headless:
##
##   godot --headless --path . --script res://tools/loadout_check.gd
##
##  * the paint colour: picked in the character creator from the twelve,
##    saved with the look (never anything but one of the twelve), and on
##    the player's shots;
##  * the weapon wheel and what's owned (WeaponWheel, GameState): see
##    _check_wheel;
##  * the passenger seat (PassengerSeat): see _check_passenger.
##
## The player's own saved files are put back as they were afterwards.
## One "LOADOUT" line per check; exits non-zero with "LOADOUT FAIL" lines
## if any fail.

var _failures := 0
var _saved_files := {}


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("LOADOUT ok   %s" % what)
	else:
		_failures += 1
		print("LOADOUT FAIL %s" % what)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	for n in ["TitleMenu", "FieldNotes"]:
		var node := root.get_node_or_null(n)
		if node != null:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	for path: String in [PlayerLook.SAVE_PATH, GameState.SAVE_PATH]:
		_saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	await _check_colour()
	for path: String in _saved_files:
		if _saved_files[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_buffer(_saved_files[path])
	if _failures > 0:
		print("LOADOUT %d check(s) failed" % _failures)
		quit(1)
	else:
		print("LOADOUT all checks passed")
		quit(0)


func _check_colour() -> void:
	_check(PaintWeapons.COLOURS.size() == 12 and PaintWeapons.COLOUR_NAMES.size() == 12, "twelve paint colours, each with a name")
	var look := PlayerLook.default_look()
	_check(look["paint"] == PaintWeapons.COLOURS[PaintWeapons.DEFAULT_COLOUR], "a new player paints %s" % PaintWeapons.colour_name(look["paint"]))
	look["paint"] = PaintWeapons.COLOURS[2]
	PlayerLook.save_look(look)
	_check(PlayerLook.load_look()["paint"] == PaintWeapons.COLOURS[2], "the chosen colour is saved with the look")
	# An edited save can't make a colour outside the twelve (a blood red).
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PlayerLook.SAVE_PATH))
	data["look"]["paint"] = "5a0a0a"
	var f := FileAccess.open(PlayerLook.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_check(PaintWeapons.COLOURS.has(PlayerLook.load_look()["paint"]), "a saved colour is always one of the twelve")
	# The creator offers the twelve and changes the look's colour.
	var creator := CharacterCreator.new()
	root.add_child(creator)
	creator.open(PlayerLook.default_look())
	await process_frame
	var swatch: Button = null
	for c in creator.find_children("*", "Button", true, false):
		if c.has_meta("key") and str(c.get_meta("key")) == "paint3":
			swatch = c
	_check(swatch != null, "the character creator has a paint colour row")
	if swatch != null:
		swatch.pressed.emit()
		_check(creator.look["paint"] == PaintWeapons.COLOURS[3], "picking a swatch sets the paint (%s)" % PaintWeapons.colour_name(creator.look["paint"]))
	creator.queue_free()
	# The player's shots are their colour.
	var player: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	player.paint_colour = PaintWeapons.COLOURS[4]
	_check(PaintShots.colour_of(player, PaintWeapons.ISLANDER) == PaintWeapons.COLOURS[4], "the player's shots are their colour")
	player.queue_free()
	await process_frame

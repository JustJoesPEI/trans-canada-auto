class_name DevMode
extends RefCounted
## Developer mode: the tools for making the game, kept out of players' way.
## Off for players. On by itself when the game runs from the Godot editor,
## or started with `-- --dev`; and switched on in a shared build by
## clicking the version number in the menu's corner seven times (it's
## remembered, in user://settings.cfg, and Settings then has a switch to
## turn it off again).
##
## What it unlocks (each checks `DevMode.on()`):
##   F3   the frame rate and draw-call overlay (Graphics)
##   F10  steps the graphics setting (Graphics; players use Settings)
##   F11  every weapon, every hopper full (main.gd)
##   F6   aim practice dummies (AimDummy)
##   F4, F5, F7  get caught, the wanted level up and down, a cop watching (Wanted)
##   N    a field note about the spot you're at; F9 opens the notes folder (FieldNotes)
##   F8   the map editor, in the browser (running from Godot only)
## The Controls page lists them while it's on.

const SAVE_PATH := "user://settings.cfg"
## Clicks on the version number that turn it on.
const TAPS := 7

static var _on := -1


## Whether the developer tools are on.
static func on() -> bool:
	if _on < 0:
		_on = 1 if _forced() or _saved() else 0
	return _on == 1


## On without asking: from the editor, or started with --dev.
static func _forced() -> bool:
	return OS.has_feature("editor") or OS.get_cmdline_user_args().has("--dev") or OS.get_cmdline_args().has("--dev")


static func _saved() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and bool(cfg.get_value("dev", "on", false))


## Turns it on or off, and remembers (from the editor or --dev it stays on
## for this run either way).
static func set_on(value: bool) -> void:
	_on = 1 if value or _forced() else 0
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("dev", "on", value)
	cfg.save(SAVE_PATH)

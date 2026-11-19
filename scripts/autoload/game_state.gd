extends Node
## Game-wide state that outlives any one scene: money and the save file.
##
## Kept deliberately small. Systems read and change state through these
## functions and listen to the signals, so the HUD never has to poll.

signal money_changed(amount: int)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var money: int = 0


func _ready() -> void:
	load_game()


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	save_game()


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "money": money}, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		money = int(parsed.get("money", 0))
		money_changed.emit(money)


func reset_save() -> void:
	money = 0
	money_changed.emit(money)
	save_game()

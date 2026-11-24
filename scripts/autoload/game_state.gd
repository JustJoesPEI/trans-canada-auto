extends Node
## Game-wide state that outlives any one scene: money, the markers and
## throwables owned, and the save file.
##
## Weapons owned (design section 2, "Markers and throwables you can buy"):
## everyone has the Islander; the rest are bought (there's no shop yet).
## Until there is, F11 in the game owns them all and fills them up (main.gd,
## a debug key).
## Kept deliberately small. Systems read and change state through these
## functions and listen to the signals, so the HUD never has to poll.

signal money_changed(amount: int)
## A weapon was bought or unlocked.
signal weapons_changed

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var money: int = 0
## Ids (PaintWeapons.ALL) of the weapons owned, in the wheel's order.
var owned_weapons: Array[String] = ["islander"]


func _ready() -> void:
	load_game()


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)
	save_game()


## Pays `amount` if there's enough money; false (and nothing spent) if not.
func spend_money(amount: int) -> bool:
	if amount > money:
		return false
	add_money(-amount)
	return true


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "money": money, "weapons": owned_weapons}, "\t"))


func owns_weapon(id: String) -> bool:
	return owned_weapons.has(id)


## Own a weapon (bought, or the debug key). Kept in PaintWeapons.ALL's order.
func unlock_weapon(id: String) -> void:
	if owns_weapon(id) or not PaintWeapons.ALL.has(id):
		return
	var list: Array[String] = []
	for w: String in PaintWeapons.ALL:
		if w == id or owned_weapons.has(w):
			list.append(w)
	owned_weapons = list
	weapons_changed.emit()
	save_game()


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		money = int(parsed.get("money", 0))
		money_changed.emit(money)
		var list: Array[String] = ["islander"]
		var saved: Variant = parsed.get("weapons", [])
		if saved is Array:
			for w: String in PaintWeapons.ALL:
				if w != "islander" and (saved as Array).has(w):
					list.append(w)
		owned_weapons = list


func reset_save() -> void:
	money = 0
	owned_weapons = ["islander"]
	money_changed.emit(money)
	weapons_changed.emit()
	save_game()

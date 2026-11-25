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
## Cars the police impounded (ImpoundLot): {model, paint (html), owner,
## session (the session it was towed in)}. Kept in the save.
var impounded: Array = []
## Counts up each time the game starts: a car towed in an earlier session
## comes back free (design.md section 7).
var session := 0
## Ids (PaintWeapons.ALL) of the weapons owned, in the wheel's order.
var owned_weapons: Array[String] = ["islander"]


func _ready() -> void:
	load_game()
	session += 1
	save_game()


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


## The last save that read back whole, kept beside the save.
const BACKUP_PATH := "user://savegame.bak.json"


## Writes the save safely: to a temporary file first, then swapped in, with
## the previous save kept as a backup. A crash or power cut mid-write can
## then never leave a half-written save as the only copy.
func save_game() -> void:
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "money": money, "weapons": owned_weapons,
		"impounded": impounded, "session": session}, "\t"))
	f.close()
	if _read_save(SAVE_PATH) is Dictionary:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BACKUP_PATH))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


## The save at `path` as a Dictionary, or null if it's missing or damaged.
static func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data if json.data is Dictionary else null


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
	var parsed: Variant = _read_save(SAVE_PATH)
	if parsed == null:
		# Damaged: keep it aside (so it can be looked at) and fall back to
		# the last good save, rather than starting over and overwriting it.
		push_warning("The save file was damaged; using the last good copy.")
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(SAVE_PATH + ".damaged"))
		parsed = _read_save(BACKUP_PATH)
		if parsed != null:
			DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP_PATH), ProjectSettings.globalize_path(SAVE_PATH))
	if parsed is Dictionary:
		money = int(parsed.get("money", 0))
		impounded = parsed.get("impounded", []) if parsed.get("impounded", []) is Array else []
		session = int(parsed.get("session", 0))
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
	impounded = []
	owned_weapons = ["islander"]
	money_changed.emit(money)
	weapons_changed.emit()
	save_game()

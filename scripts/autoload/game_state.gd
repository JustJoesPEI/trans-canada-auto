extends Node
## Game-wide state that outlives any one scene: money, the markers and
## throwables owned, and the save file.
##
## Weapons owned (design section 2, "Markers and throwables you can buy"):
## everyone has the Islander; the rest are bought at Ervin's (Stores). F11
## in the game owns them all and fills them up (main.gd, a debug key).
## Kept deliberately small. Systems read and change state through these
## functions and listen to the signals, so the HUD never has to poll.
##
## The money side (docs/design.md section 6½, "Money: jobs, stores and
## property"):
##   vehicles    the cars and trucks you own: {id, model, paint (html),
##               mods (Dictionary, the custom shop's), parked (where it was
##               left: {x, y, z, yaw}, or {} for "no spot yet"), stored
##               (the storage it's kept in: a property id, or "")}
##   properties  ids of the places you own or rent (parkade passes, the
##               hotel suite...), each worth some storage spaces
##   jobs_done   finished jobs by kind ("spuddash", "tow"...): the licence
##               ladder at Delayed & Lost counts these
##   items       consumables and gear by id -> how many (armour, tow
##               straps...), for the stores to fill and other systems to use
##   home        the property you start the game at ("" for the default)

signal money_changed(amount: int)
## A weapon was bought or unlocked.
signal weapons_changed
## A vehicle was bought, sold, changed or moved.
signal vehicles_changed
signal properties_changed
signal items_changed
signal job_done(kind: String)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 2

var money: int = 0
## Cars the police impounded (ImpoundLot): {model, paint (html), owner,
## session (the session it was towed in)}. Kept in the save.
var impounded: Array = []
## Counts up each time the game starts: a car towed in an earlier session
## comes back free (design.md section 7).
var session := 0
## Ids (PaintWeapons.ALL) of the weapons owned, in the wheel's order.
var owned_weapons: Array[String] = ["islander"]
var vehicles: Array = []
var properties: Array[String] = []
var jobs_done: Dictionary = {}
var items: Dictionary = {}
var home := ""
## Storage spaces everyone has without owning anything: the one car you
## can leave on the street.
const FREE_SPACES := 1
## Storage spaces each property gives, by id (filled in by the property
## code as it's built: Properties.SPACES).
static var property_spaces: Dictionary = {}


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


## Saves wait for the end of the frame (everything changed in a frame is
## one save) and are written on a worker, so a purchase or a car parked
## doesn't stop the game for the write, the read-back of the old save and
## the copy. Headless tools (`--script`) save at once instead: they check
## the file straight after and put the real one back before they quit.
var deferred_saves := not OS.get_cmdline_args().has("--script")
var _dirty := false
var _seq := 0 ## counts saves, so a slow write never lands over a newer one
var _writes: Array[int] = [] ## WorkerThreadPool tasks writing saves
static var _write_lock := Mutex.new()
static var _written_seq := 0


## Saves the game: at once, or at the end of this frame (deferred_saves).
func save_game() -> void:
	if not deferred_saves:
		_seq += 1
		_write(_snapshot(), _seq, _paths())
		return
	if not _dirty:
		_dirty = true
		_flush.call_deferred()


## Writes any save still waiting and waits for every write to finish: on
## quitting, and before reading the save back.
func flush_save() -> void:
	if _dirty:
		_flush()
	for t in _writes:
		WorkerThreadPool.wait_for_task_completion(t)
	_writes.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		flush_save()


func _flush() -> void:
	if not _dirty:
		return
	_dirty = false
	_seq += 1
	# Finished writes let go of.
	for i in range(_writes.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_writes[i]):
			WorkerThreadPool.wait_for_task_completion(_writes[i])
			_writes.remove_at(i)
	_writes.append(WorkerThreadPool.add_task(_write.bind(_snapshot(), _seq, _paths()), false, "save"))


## A copy of everything saved, for a worker to write while the game
## carries on changing the real thing.
func _snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "money": money, "weapons": owned_weapons.duplicate(),
		"impounded": impounded.duplicate(true), "session": session, "vehicles": vehicles.duplicate(true),
		"properties": properties.duplicate(), "jobs_done": jobs_done.duplicate(true), "items": items.duplicate(true), "home": home}


static func _paths() -> PackedStringArray:
	return PackedStringArray([ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BACKUP_PATH)])


## Writes the save safely: to a temporary file first, then swapped in, with
## the previous save kept as a backup. A crash or power cut mid-write can
## then never leave a half-written save as the only copy. Any thread; one
## write at a time, and never an older save over a newer one.
static func _write(data: Dictionary, seq: int, paths: PackedStringArray) -> void:
	var text := JSON.stringify(data, "\t")
	_write_lock.lock()
	if seq > _written_seq:
		var save := paths[0]
		var tmp := save + ".tmp"
		var f := FileAccess.open(tmp, FileAccess.WRITE)
		if f == null:
			push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		else:
			f.store_string(text)
			f.close()
			if _read_save(save) is Dictionary:
				DirAccess.copy_absolute(save, paths[1])
			DirAccess.rename_absolute(tmp, save)
			_written_seq = seq
	_write_lock.unlock()


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
	# What's on disk is the truth now: no write still to land over it, and
	# nothing waiting from before.
	for t in _writes:
		WorkerThreadPool.wait_for_task_completion(t)
	_writes.clear()
	_dirty = false
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
		vehicles = parsed.get("vehicles", []) if parsed.get("vehicles", []) is Array else []
		var props: Array[String] = []
		for id: Variant in (parsed.get("properties", []) if parsed.get("properties", []) is Array else []):
			props.append(str(id))
		properties = props
		jobs_done = parsed.get("jobs_done", {}) if parsed.get("jobs_done", {}) is Dictionary else {}
		items = parsed.get("items", {}) if parsed.get("items", {}) is Dictionary else {}
		home = str(parsed.get("home", ""))
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
	vehicles = []
	properties = []
	jobs_done = {}
	items = {}
	home = ""
	money_changed.emit(money)
	weapons_changed.emit()
	vehicles_changed.emit()
	properties_changed.emit()
	items_changed.emit()
	save_game()


# --- vehicles ------------------------------------------------------------------------------------

## Owns a vehicle of `model` painted `paint`: its new id.
func add_vehicle(model: String, paint: Color, mods := {}) -> String:
	var id := "v%d_%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	vehicles.append({"id": id, "model": model, "paint": paint.to_html(false), "mods": mods.duplicate(true), "parked": {}, "stored": ""})
	vehicles_changed.emit()
	save_game()
	return id


## The vehicle with `id` ({} if none). Change it with set_vehicle.
func vehicle(id: String) -> Dictionary:
	for v: Dictionary in vehicles:
		if str(v["id"]) == id:
			return v
	return {}


## Changes some of a vehicle's fields (paint, mods, parked, stored...).
func set_vehicle(id: String, fields: Dictionary, save := true) -> void:
	for v: Dictionary in vehicles:
		if str(v["id"]) == id:
			v.merge(fields, true)
			vehicles_changed.emit()
			if save:
				save_game()
			return


func remove_vehicle(id: String) -> void:
	for i in vehicles.size():
		if str(vehicles[i]["id"]) == id:
			vehicles.remove_at(i)
			vehicles_changed.emit()
			save_game()
			return


## How many vehicles you can keep: FREE_SPACES plus each property's.
func storage_spaces() -> int:
	var n := FREE_SPACES
	for p in properties:
		n += int(property_spaces.get(p, 0))
	return n


## Room for one more vehicle.
func has_space() -> bool:
	return vehicles.size() < storage_spaces()


# --- properties, jobs, items --------------------------------------------------------------------

func owns_property(id: String) -> bool:
	return properties.has(id)


func add_property(id: String) -> void:
	if properties.has(id):
		return
	properties.append(id)
	properties_changed.emit()
	vehicles_changed.emit() # more room
	save_game()


func remove_property(id: String) -> void:
	if properties.has(id):
		properties.erase(id)
		if home == id:
			home = ""
		properties_changed.emit()
		vehicles_changed.emit()
		save_game()


func set_home(id: String) -> void:
	home = id
	save_game()


func jobs_done_count(kind: String) -> int:
	return int(jobs_done.get(kind, 0))


func add_job_done(kind: String) -> void:
	jobs_done[kind] = jobs_done_count(kind) + 1
	job_done.emit(kind)
	save_game()


func item_count(id: String) -> int:
	return int(items.get(id, 0))


## Adds (or with a negative `n`, uses up) some of an item. False, and no
## change, if there aren't enough to use.
func add_item(id: String, n := 1) -> bool:
	var have := item_count(id)
	if have + n < 0:
		return false
	if have + n == 0:
		items.erase(id)
	else:
		items[id] = have + n
	items_changed.emit()
	save_game()
	return true

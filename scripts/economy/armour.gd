class_name Armour
extends Node
## The player's armour (docs/design.md section 6½, decided: "consumable,
## like body armour in other games"): plates worn on the player's
## BodyPaint, which take paint hits before any count toward an out, one
## hit each. Bought at Ervin's (Stores), up to BodyPaint.ARMOUR_MAX, and
## kept in GameState.items["armour"] so they last between sessions.
##
## A plate breaking plays a crack (PaintSounds.plate_break) and flashes
## the HUD's armour bar (Hud.set_armour).

const ITEM := "armour"

var body: BodyPaint
var hud: Node
var _gs: Node
var _audio: AudioStreamPlayer


func setup(b: BodyPaint, h: Node) -> void:
	body = b
	hud = h
	_gs = get_tree().root.get_node("GameState")
	_audio = AudioStreamPlayer.new()
	_audio.name = "PlateSound"
	add_child(_audio)
	body.set_armour(int(_gs.call("item_count", ITEM)))
	body.armour_changed.connect(_on_worn)
	body.plates_broke.connect(_on_broke)
	_gs.connect("items_changed", _on_items)
	_show(0)


## Plates worn now.
func plates() -> int:
	return body.armour if body != null else 0


## Plates that would still fit.
func room() -> int:
	return BodyPaint.ARMOUR_MAX - plates()


## Puts on up to `n` more plates: how many went on.
func add_plates(n: int) -> int:
	var add := mini(n, room())
	if add <= 0:
		return 0
	_gs.call("add_item", ITEM, add)
	return add


## Plates changed on the body (a hit broke some): the save follows.
func _on_worn(p: int) -> void:
	var kept := int(_gs.call("item_count", ITEM))
	if p != kept:
		_gs.call("add_item", ITEM, p - kept)
	_show(0)


func _on_broke(n: int) -> void:
	_show(n)
	if _audio != null and _audio.is_inside_tree():
		_audio.stream = PaintSounds.plate_break()
		_audio.volume_db = -5.0
		_audio.play()


## The save changed (a plate bought, a save loaded): the body follows.
func _on_items() -> void:
	var c := clampi(int(_gs.call("item_count", ITEM)), 0, BodyPaint.ARMOUR_MAX)
	if body != null and c != body.armour:
		body.set_armour(c)


func _show(broke: int) -> void:
	if hud != null and hud.has_method("set_armour"):
		hud.call("set_armour", plates(), broke)

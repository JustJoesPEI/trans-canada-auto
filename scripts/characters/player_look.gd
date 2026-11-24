class_name PlayerLook
extends RefCounted
## The player's look, chosen in the character creator and remembered
## between games in user://character.json: skin, hair, height, build and
## outfit (see Outfit), as an appearance Dictionary for HumanoidModel, and
## "paint", the colour of the player's paintballs (one of the twelve in
## PaintWeapons.COLOURS; PlayerController.paint_colour).

const SAVE_PATH := "user://character.json"
const VERSION := 1

## Choices offered in the creator.
const SKINS := [Color(0.96, 0.82, 0.71), Color(0.92, 0.75, 0.62), Color(0.87, 0.69, 0.57), Color(0.8, 0.6, 0.46),
	Color(0.7, 0.51, 0.37), Color(0.58, 0.4, 0.28), Color(0.47, 0.32, 0.22), Color(0.36, 0.24, 0.17)]
const HAIRS := [Color(0.07, 0.06, 0.05), Color(0.23, 0.16, 0.11), Color(0.4, 0.26, 0.15), Color(0.6, 0.42, 0.24),
	Color(0.78, 0.62, 0.38), Color(0.62, 0.24, 0.12), Color(0.62, 0.6, 0.58), Color(0.9, 0.88, 0.84)]
const HAIR_STYLES := ["Short", "Long", "Close-cropped"]
## Cloth colours: everyday ones first, then louder ones.
const CLOTHS := [Color(0.95, 0.95, 0.93), Color(0.78, 0.74, 0.66), Color(0.55, 0.55, 0.53), Color(0.25, 0.25, 0.27),
	Color(0.1, 0.1, 0.12), Color(0.21, 0.25, 0.34), Color(0.3, 0.42, 0.6), Color(0.15, 0.2, 0.32),
	Color(0.25, 0.38, 0.28), Color(0.29, 0.33, 0.22), Color(0.4, 0.35, 0.28), Color(0.45, 0.3, 0.18),
	Color(0.66, 0.16, 0.13), Color(0.5, 0.12, 0.12), Color(0.85, 0.45, 0.15), Color(0.75, 0.6, 0.2),
	Color(0.4, 0.28, 0.42), Color(0.86, 0.55, 0.62), Color(0.2, 0.55, 0.6), Color(0.92, 0.85, 0.3)]
const HEIGHT_RANGE := Vector2(1.6, 1.95)
const BUILD_RANGE := Vector2(0.88, 1.18)


## The look a new player starts with: the red fall jacket and jeans.
static func default_look() -> Dictionary:
	return {
		"skin": Color(0.87, 0.69, 0.57),
		"hair": Color(0.23, 0.16, 0.11),
		"hair_style": 0,
		"height": 1.75,
		"build": 1.0,
		"outfit": Outfit.default_outfit(),
		"paint": PaintWeapons.COLOURS[PaintWeapons.DEFAULT_COLOUR],
	}


## A random look from the creator's choices.
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := HumanoidModel.random_appearance(rng)
	look["skin"] = SKINS[rng.randi() % SKINS.size()]
	look["hair"] = HAIRS[rng.randi() % HAIRS.size()]
	look["paint"] = PaintWeapons.COLOURS[rng.randi() % PaintWeapons.COLOURS.size()]
	return look


## The saved look, or the default one.
static func load_look() -> Dictionary:
	var look := default_look()
	if not FileAccess.file_exists(SAVE_PATH):
		return look
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not (parsed is Dictionary):
		return look
	var saved: Dictionary = (parsed as Dictionary).get("look", {})
	for key: String in ["skin", "hair"]:
		if saved.has(key):
			look[key] = Color.from_string(str(saved[key]), look[key])
	if saved.has("paint"):
		look["paint"] = PaintWeapons.COLOURS[PaintWeapons.nearest_colour(Color.from_string(str(saved["paint"]), look["paint"]))]
	look["hair_style"] = clampi(int(saved.get("hair_style", 0)), 0, HAIR_STYLES.size() - 1)
	look["height"] = clampf(float(saved.get("height", 1.75)), HEIGHT_RANGE.x, HEIGHT_RANGE.y)
	look["build"] = clampf(float(saved.get("build", 1.0)), BUILD_RANGE.x, BUILD_RANGE.y)
	var outfit := {}
	var o: Variant = saved.get("outfit", {})
	if o is Dictionary:
		for slot: String in Outfit.SLOTS:
			var g: Variant = (o as Dictionary).get(slot, {})
			if not (g is Dictionary):
				continue
			var garment := {}
			for key: String in g:
				var v: Variant = g[key]
				garment[key] = Color.from_string(str(v), Color.BLACK) if key in ["color", "trim"] else str(v)
			outfit[slot] = garment
	look["outfit"] = Outfit.complete(outfit)
	return look


static func save_look(look: Dictionary) -> void:
	var outfit := {}
	for slot: String in Outfit.SLOTS:
		var g: Dictionary = (look["outfit"] as Dictionary)[slot]
		var garment := {}
		for key: String in g:
			var v: Variant = g[key]
			garment[key] = (v as Color).to_html(false) if v is Color else v
		outfit[slot] = garment
	var data := {"version": VERSION, "look": {
		"skin": (look["skin"] as Color).to_html(false), "hair": (look["hair"] as Color).to_html(false),
		"hair_style": look["hair_style"], "height": look["height"], "build": look["build"], "outfit": outfit,
		"paint": (look.get("paint", PaintWeapons.COLOURS[PaintWeapons.DEFAULT_COLOUR]) as Color).to_html(false)}}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save the character: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data, "\t"))


## A deep copy, so the creator can change a look without touching the
## player's until Done.
static func copy(look: Dictionary) -> Dictionary:
	return look.duplicate(true)

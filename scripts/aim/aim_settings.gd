class_name AimSettings
extends RefCounted
## The controller aiming settings: aim assist (Standard, Low or Off), look
## and aim sensitivity, the response curve and the stick's deadzones. Set in
## the Controls menu and saved in user://controls.cfg, the way the graphics
## setting is saved. None of it changes the mouse.
##
## Everything is static, so the camera, the aim assist and the menu all read
## the same values without an autoload; the saved file is read the first
## time anything asks (`ensure_loaded()`).

enum Assist { STANDARD, LOW, OFF }
enum Response { EXPONENTIAL, LINEAR }

const SAVE_PATH := "user://controls.cfg"
const SECTION := "controller"

const DEFAULT_LOOK := 1.0
const DEFAULT_AIM := 1.0
const DEFAULT_INNER := 0.12 ## most sticks rest within 0.1 of the middle
const DEFAULT_OUTER := 0.05 ## the last 5% of the throw counts as full

## Slider ranges for the menu.
const SENSITIVITY_MIN := 0.3
const SENSITIVITY_MAX := 2.5
const INNER_MAX := 0.35
const OUTER_MAX := 0.25

static var assist: Assist = Assist.STANDARD
static var curve: Response = Response.EXPONENTIAL
## Multipliers on the stick's turn speed, looking round and aiming.
static var look_sensitivity := DEFAULT_LOOK
static var aim_sensitivity := DEFAULT_AIM
## Stick travel (0..1 from the middle) ignored at the middle, and the part
## at the edge that counts as full.
static var inner_deadzone := DEFAULT_INNER
static var outer_deadzone := DEFAULT_OUTER
## The police aim-in snap. Not saved: events turn it off while they run
## (and put it back after).
static var police_snap := true

static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_saved()


## How strong the assist is: 1 Standard, 0.5 Low, 0 Off.
static func assist_strength() -> float:
	ensure_loaded()
	match assist:
		Assist.STANDARD:
			return 1.0
		Assist.LOW:
			return 0.5
	return 0.0


static func assist_label() -> String:
	ensure_loaded()
	return ["Standard", "Low", "Off"][assist]


static func curve_label() -> String:
	ensure_loaded()
	return ["Exponential", "Linear"][curve]


## The number settings by name (look_sensitivity, aim_sensitivity,
## inner_deadzone, outer_deadzone), for the menu's sliders.
static func get_number(key: String) -> float:
	ensure_loaded()
	match key:
		"look_sensitivity":
			return look_sensitivity
		"aim_sensitivity":
			return aim_sensitivity
		"inner_deadzone":
			return inner_deadzone
		"outer_deadzone":
			return outer_deadzone
	return 0.0


static func set_number(key: String, v: float) -> void:
	ensure_loaded()
	match key:
		"look_sensitivity":
			look_sensitivity = clampf(v, SENSITIVITY_MIN, SENSITIVITY_MAX)
		"aim_sensitivity":
			aim_sensitivity = clampf(v, SENSITIVITY_MIN, SENSITIVITY_MAX)
		"inner_deadzone":
			inner_deadzone = clampf(v, 0.0, INNER_MAX)
		"outer_deadzone":
			outer_deadzone = clampf(v, 0.0, OUTER_MAX)


## Back to the defaults (not saved; call save() to keep them).
static func reset_defaults() -> void:
	_loaded = true
	assist = Assist.STANDARD
	curve = Response.EXPONENTIAL
	look_sensitivity = DEFAULT_LOOK
	aim_sensitivity = DEFAULT_AIM
	inner_deadzone = DEFAULT_INNER
	outer_deadzone = DEFAULT_OUTER


static func load_saved() -> void:
	reset_defaults()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var a := str(cfg.get_value(SECTION, "aim_assist", "standard"))
	assist = Assist.LOW if a == "low" else (Assist.OFF if a == "off" else Assist.STANDARD)
	curve = Response.LINEAR if str(cfg.get_value(SECTION, "curve", "exponential")) == "linear" else Response.EXPONENTIAL
	look_sensitivity = clampf(float(cfg.get_value(SECTION, "look_sensitivity", DEFAULT_LOOK)), SENSITIVITY_MIN, SENSITIVITY_MAX)
	aim_sensitivity = clampf(float(cfg.get_value(SECTION, "aim_sensitivity", DEFAULT_AIM)), SENSITIVITY_MIN, SENSITIVITY_MAX)
	inner_deadzone = clampf(float(cfg.get_value(SECTION, "inner_deadzone", DEFAULT_INNER)), 0.0, INNER_MAX)
	outer_deadzone = clampf(float(cfg.get_value(SECTION, "outer_deadzone", DEFAULT_OUTER)), 0.0, OUTER_MAX)


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # keep anything else in the file
	cfg.set_value(SECTION, "aim_assist", ["standard", "low", "off"][assist])
	cfg.set_value(SECTION, "curve", "linear" if curve == Response.LINEAR else "exponential")
	cfg.set_value(SECTION, "look_sensitivity", look_sensitivity)
	cfg.set_value(SECTION, "aim_sensitivity", aim_sensitivity)
	cfg.set_value(SECTION, "inner_deadzone", inner_deadzone)
	cfg.set_value(SECTION, "outer_deadzone", outer_deadzone)
	cfg.save(SAVE_PATH)

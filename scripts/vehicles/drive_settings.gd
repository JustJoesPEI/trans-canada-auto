class_name DriveSettings
extends RefCounted
## The player's driving help, switched in the Controls menu and saved in
## user://controls.cfg ("driving"), the way the aim settings are:
##
##   steering   full lock at speed is as much as the tyres can use there
##              (Car._assisted_lock), with the full lock back for catching
##              a slide or on the handbrake
##   traction   the throttle eased once the tail is well out
##              (Car._traction_help), except on the handbrake
##
## Both on to start. Off, the car is all its own: its whole lock and all
## its power, for those who'd rather catch it themselves. The help only
## ever takes something away (lock, power), so a good driver with it off is
## quicker. Neither touches the computer drivers.

const SAVE_PATH := "user://controls.cfg"
const SECTION := "driving"

static var steering := true
static var traction := true
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		steering = bool(cfg.get_value(SECTION, "steering_help", true))
		traction = bool(cfg.get_value(SECTION, "traction_help", true))


static func steering_on() -> bool:
	ensure_loaded()
	return steering


static func traction_on() -> bool:
	ensure_loaded()
	return traction


static func save() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH) # keep the rest of the file
	cfg.set_value(SECTION, "steering_help", steering)
	cfg.set_value(SECTION, "traction_help", traction)
	cfg.save(SAVE_PATH)


static func reset_defaults() -> void:
	_loaded = true
	steering = true
	traction = true

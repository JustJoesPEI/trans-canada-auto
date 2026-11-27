class_name Rumble
extends RefCounted
## The controller's rumble for the paintball fight: a tap for each shot
## (heavier for the bigger markers), a knock for a hit that lands, a thump
## for being hit. Only while a controller is what's being used
## (InputDevice) and Vibration is on in the Controls menu (AimSettings).
##
## `weak` is the small fast motor (a buzz), `strong` the big one (a thud),
## both 0..1; `secs` how long. A pulse doesn't cut a stronger one short.

static var _until := 0.0
static var _level := 0.0


static func pulse(weak: float, strong: float, secs: float) -> void:
	if not InputDevice.controller:
		return
	AimSettings.ensure_loaded()
	if not AimSettings.vibration:
		return
	var now := Time.get_ticks_msec() * 0.001
	var level := maxf(weak, strong)
	if now < _until and level < _level:
		return
	_until = now + secs
	_level = level
	for d in Input.get_connected_joypads():
		Input.start_joy_vibration(d, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), secs)

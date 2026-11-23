extends Node
## The game's overall sound volume, set from the menu (Sound: 100%, 75%,
## 50%, 25%, Off) and remembered in user://sound.cfg.
##
## It also puts a limiter on the master bus, so a crash on top of a
## screaming engine on top of squealing tyres never clips.

const SAVE_PATH := "user://sound.cfg"
## The steps the menu button goes through, as shares of full volume.
const STEPS: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]

var volume := 1.0


func _ready() -> void:
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		volume = clampf(float(cfg.get_value("sound", "volume", 1.0)), 0.0, 1.0)
	_apply()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	_apply()
	var cfg := ConfigFile.new()
	cfg.set_value("sound", "volume", volume)
	cfg.save(SAVE_PATH)


## The next step down (and from Off back to full), for the menu button.
func next_step() -> void:
	for s in STEPS:
		if s < volume - 0.01:
			set_volume(s)
			return
	set_volume(STEPS[0])


func label() -> String:
	return "Off" if volume <= 0.0 else "%d%%" % roundi(volume * 100.0)


func _apply() -> void:
	AudioServer.set_bus_mute(0, volume <= 0.0)
	# Volume by ear: half the slider is about half as loud, not half the signal.
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001) ** 1.6) if volume > 0.0 else -80.0)

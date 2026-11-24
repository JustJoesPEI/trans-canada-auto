extends Node
## The game's overall sound volume, set from the menu (Sound: 100%, 75%,
## 50%, 25%, Off) and remembered in user://sound.cfg.
##
## It also puts a limiter on the master bus, so a crash on top of a
## screaming engine on top of squealing tyres never clips, and keeps the
## PlayerCar bus: the car you're driving plays through it, and from the
## driver's seat it's muffled the way a car's body muffles everything
## outside it (set_interior).

const SAVE_PATH := "user://sound.cfg"
## The steps the menu button goes through, as shares of full volume.
const STEPS: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]

## The bus the player's own car plays through (see CarAudio).
const CAR_BUS := "PlayerCar"
## From the driver's seat: where the body starts holding sound back (Hz;
## above it the treble falls away, about 12 dB by twice that), how much the
## cabin booms in the low end, and a level drop, since the seat is also
## closer to the engine than the chase camera.
const INTERIOR_CUTOFF := 1400.0
const INTERIOR_BOOM := 0.35
const INTERIOR_DB := -5.0

var volume := 1.0
var interior := 0.0 ## 0 outside, 1 in the driver's seat

var _car_bus := -1
var _lowpass: AudioEffectLowPassFilter
var _boom: AudioEffectLowShelfFilter


func _ready() -> void:
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	_make_car_bus()
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


## How far inside the car the listener is, 0 (outside) to 1 (driver's seat).
func set_interior(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if is_equal_approx(amount, interior) or _car_bus < 0:
		return
	interior = amount
	var on := amount > 0.001
	AudioServer.set_bus_effect_enabled(_car_bus, 0, on)
	AudioServer.set_bus_effect_enabled(_car_bus, 1, on)
	_lowpass.cutoff_hz = 20000.0 * pow(INTERIOR_CUTOFF / 20000.0, amount)
	_boom.gain = 1.0 + INTERIOR_BOOM * amount
	AudioServer.set_bus_volume_db(_car_bus, INTERIOR_DB * amount)


func _make_car_bus() -> void:
	_car_bus = AudioServer.get_bus_index(CAR_BUS)
	if _car_bus < 0:
		AudioServer.add_bus()
		_car_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_car_bus, CAR_BUS)
		AudioServer.set_bus_send(_car_bus, "Master")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	_lowpass.db = AudioEffectFilter.FILTER_12DB
	_lowpass.resonance = 0.6
	_boom = AudioEffectLowShelfFilter.new()
	_boom.cutoff_hz = 160.0
	AudioServer.add_bus_effect(_car_bus, _lowpass, 0)
	AudioServer.add_bus_effect(_car_bus, _boom, 1)
	AudioServer.set_bus_effect_enabled(_car_bus, 0, false)
	AudioServer.set_bus_effect_enabled(_car_bus, 1, false)


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

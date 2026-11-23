class_name CarParts
extends RefCounted
## Performance parts, and putting a car's driving settings together.
##
## A car drives from its model's "drive" settings (CarModels) with any parts
## fitted on top. A part is a list of changes to those settings, each named
## by its path ("engine.torque", "suspension.spring_hz") and one of:
##   "mul": multiply the number (or every torque value) by this
##   "add": add this to it
##   "set": replace it
## Parts are applied in the order they're fitted. There's no garage yet;
## these are here so one can be added without touching the physics.

const PARTS := {
	"sport_springs": {
		"name": "Sport springs",
		"about": "Stiffer springs and firmer dampers: less lean and dive, a busier ride.",
		"changes": {"suspension.spring_hz": {"mul": 1.25}, "suspension.damping": {"mul": 1.15}, "suspension.travel": {"mul": 0.85}},
	},
	"anti_roll_bars": {
		"name": "Heavy anti-roll bars",
		"about": "Keeps the car flat in corners.",
		"changes": {"suspension.anti_roll": {"mul": 1.6}},
	},
	"performance_tyres": {
		"name": "Performance tyres",
		"about": "Softer, stickier rubber: more grip, sharper turn-in.",
		"changes": {"tyres.grip": {"mul": 1.12}, "tyres.stiffness": {"mul": 1.15}},
	},
	"intake_exhaust": {
		"name": "Intake and exhaust",
		"about": "Breathes better: about 8% more pull all through the revs.",
		"changes": {"engine.torque": {"mul": 1.08}},
	},
	"engine_tune": {
		"name": "Engine tune",
		"about": "More pull up top and a higher rev limit.",
		"changes": {"engine.torque": {"mul": 1.12}, "engine.redline_rpm": {"add": 400.0}},
	},
	"short_gearing": {
		"name": "Short final drive",
		"about": "Quicker off the line and through the gears, at the cost of top speed.",
		"changes": {"gearbox.final": {"mul": 1.12}},
	},
	"big_brakes": {
		"name": "Big brakes",
		"about": "Bigger rotors and calipers: stops harder.",
		"changes": {"brakes.force": {"mul": 1.25}},
	},
	"weight_reduction": {
		"name": "Weight reduction",
		"about": "Lighter seats and panels: about 6% lighter.",
		"changes": {"body.mass": {"mul": 0.94}},
	},
}


## The full driving settings for a model with these parts fitted.
static func build_spec(model_id: String, parts: Array = []) -> Dictionary:
	var spec: Dictionary = (CarModels.get_model(model_id)["drive"] as Dictionary).duplicate(true)
	for part_id: Variant in parts:
		var part: Dictionary = PARTS.get(str(part_id), {})
		var changes: Dictionary = part.get("changes", {})
		for path: String in changes:
			_apply(spec, path, changes[path])
	return spec


static func _apply(spec: Dictionary, path: String, change: Dictionary) -> void:
	var keys := path.split(".")
	var holder: Variant = spec
	for i in range(keys.size() - 1):
		if not (holder is Dictionary) or not (holder as Dictionary).has(keys[i]):
			push_warning("CarParts: no setting %s" % path)
			return
		holder = (holder as Dictionary)[keys[i]]
	var last := keys[keys.size() - 1]
	if not (holder is Dictionary) or not (holder as Dictionary).has(last):
		push_warning("CarParts: no setting %s" % path)
		return
	var value: Variant = holder[last]
	if value is Array:
		# A torque curve: change the newton metres, keep the rpm.
		var curve: Array = (value as Array).duplicate(true)
		for point: Array in curve:
			point[1] = _change(float(point[1]), change)
		holder[last] = curve
	else:
		holder[last] = _change(float(value), change)


static func _change(v: float, change: Dictionary) -> float:
	if change.has("set"):
		return float(change["set"])
	if change.has("mul"):
		v *= float(change["mul"])
	if change.has("add"):
		v += float(change["add"])
	return v

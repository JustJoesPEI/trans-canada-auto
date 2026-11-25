class_name TrafficPersonality
extends RefCounted
## Who's driving: a few settings per driver so traffic doesn't move like a
## train (how fast, how close, how patient, how quick to honk), and now and
## then one of the local characters:
##
##   slow_pickup  an old pickup doing well under the limit, never in a hurry
##   chatter      stops in the lane for a while to talk to someone (the
##                cars behind go round)
##   tourist      brakes for every junction and street sign; common in July
##                and August, rare the rest of the year
##   rusher       late for something: quicker, closer, honks
##   nervous      slow to go, wants big gaps
##
## And the mix of cars: the everyday models, in their own colours (each
## model's first three, so the cached meshes stay few).

## [model, how common]. All are PARKED_MODELS (the far ones are drawn with
## the parked-car meshes).
const MODELS := [["civique", 10.0], ["corollary", 9.0], ["pious", 6.0], ["halfton", 7.0],
	["cr_eh", 7.0], ["grand_caravel", 5.0], ["haulux", 4.0], ["jaunt", 5.0], ["interlude", 3.0],
	["sole", 3.0], ["filly", 2.0], ["ironiq", 2.0], ["hinterland", 3.0], ["charlatan", 2.0],
	["rammer", 3.0], ["yukoner", 2.0], ["crown_vista", 1.5], ["bucko", 1.0]]
const PICKUPS := ["halfton", "haulux", "rammer"]
## The odd truck (TruckModels): a tractor unit running back to the yard, a
## tow truck. Only near the player, never more than TRUCKS_MAX at once.
const TRUCKS := [["rollback", 2.0], ["hauler", 1.0]]
const TRUCK_ODDS := 0.08
const TRUCKS_MAX := 2


static func pick_truck(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for m: Array in TRUCKS:
		total += float(m[1])
	var r := rng.randf() * total
	for m: Array in TRUCKS:
		r -= float(m[1])
		if r <= 0.0:
			return str(m[0])
	return str(TRUCKS[0][0])


## Colours used per model (its first n).
const COLOURS_PER_MODEL := 3


static func pick_model(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for m: Array in MODELS:
		total += float(m[1])
	var r := rng.randf() * total
	for m: Array in MODELS:
		r -= float(m[1])
		if r <= 0.0:
			return str(m[0])
	return "civique"


static func pick_colour(rng: RandomNumberGenerator, model: String) -> Color:
	var cs: Array = CarModels.get_model(model)["colours"]
	var c := str(cs[rng.randi() % mini(COLOURS_PER_MODEL, cs.size())])
	return Color.from_string(c, Color.WHITE)


## Which character, if any ("" for an ordinary driver).
static func pick_character(rng: RandomNumberGenerator, model: String, month: int) -> String:
	var r := rng.randf()
	var tourist := 0.18 if month in [7, 8] else (0.06 if month in [6, 9] else 0.015)
	if r < tourist:
		return "tourist"
	r -= tourist
	if model in PICKUPS and r < 0.12:
		return "slow_pickup"
	r -= 0.12 if model in PICKUPS else 0.0
	if r < 0.035:
		return "chatter"
	r -= 0.035
	if r < 0.07:
		return "rusher"
	r -= 0.07
	if r < 0.06:
		return "nervous"
	return ""


## Sets a driver's settings: an ordinary spread, then the character's.
static func apply(c: CivilDriving, rng: RandomNumberGenerator, character: String) -> void:
	c.speed_factor = rng.randf_range(0.87, 1.0)
	c.headway = rng.randf_range(1.1, 1.8)
	c.standstill_gap = rng.randf_range(2.0, 3.0)
	c.max_accel = rng.randf_range(1.3, 2.0)
	c.comfort_brake = rng.randf_range(2.3, 3.0)
	c.reaction = rng.randf_range(0.4, 0.75)
	c.patience = rng.randf_range(8.0, 22.0)
	c.temper = rng.randf_range(0.05, 0.7)
	c.gap_time = rng.randf_range(3.8, 5.2)
	match character:
		"slow_pickup":
			c.speed_factor = rng.randf_range(0.68, 0.76)
			c.max_accel = 1.0
			c.patience = 30.0
			c.temper = 0.05
		"tourist":
			c.tourist = true
			c.speed_factor = rng.randf_range(0.78, 0.88)
			c.reaction = 0.8
			c.gap_time = 5.5
			c.temper = 0.0
		"rusher":
			c.speed_factor = rng.randf_range(1.03, 1.1)
			c.headway = 0.9
			c.standstill_gap = 1.6
			c.max_accel = 2.3
			c.patience = 6.0
			c.temper = 0.95
			c.gap_time = 3.4
		"nervous":
			c.speed_factor = 0.82
			c.headway = 2.2
			c.reaction = 0.85
			c.gap_time = 6.0
			c.temper = 0.05
			c.patience = 25.0

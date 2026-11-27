class_name WitnessDescription
extends RefCounted
## What a witness tells the police when their call gets through (Wanted
## "witness_called"; PoliceDispatcher reads it out on the radio): your car,
## or on foot your jacket, as they saw it when it happened, and not always
## right. A caller who gets your car exactly right (its colour and its
## model) tells the police which car to look for (PoliceDispatcher.known_car);
## one who gets it wrong sends them after the wrong one, so changing cars
## after a crime is worth it. docs/voice.md: the caller is never the joke
## for who they are; the mistakes are the honest kind anyone makes.
##
## look: {in_car: bool, model_id: String, paint: Color, top: Color} as
## Wanted saw it at the crime. who: the caller's kind (a person on foot's
## kind, "driver", "owner").

## Odds the caller gets the colour wrong, and gives no model, by who.
const WRONG_COLOUR := {"senior": 0.35, "teen": 0.15, "driver": 0.15, "owner": 0.0}
const NO_MODEL := {"senior": 0.6, "tourist": 0.5, "driver": 0.1, "owner": 0.0}
const DEFAULT_WRONG := 0.25
const DEFAULT_NO_MODEL := 0.35

## The colour people mix it up with.
const NEXT_TO := {"red": ["orange", "purple"], "orange": ["red", "yellow"], "yellow": ["orange", "green"],
	"green": ["blue", "yellow"], "blue": ["green", "purple"], "purple": ["blue", "red"],
	"white": ["grey"], "grey": ["white", "black"], "black": ["grey", "blue"]}

## How they hedge a colour they're not sure of: {said} what they said,
## {other} the one it might also be.
const HEDGES := ["{said}. Or {other}. \"Somewhere in there.\"", "{said}, maybe {other}. \"It was bright out.\"",
	"{said}. \"Or it was the light.\""]
## A car they couldn't name: {colour}, {kind}.
const VAGUE_CARS := ["a {colour} car, \"the normal kind\"", "a {colour} {kind}, they think",
	"a {colour} car. \"Not a truck. Fairly sure not a truck.\""]


## {text, right_car}: what they said, and whether it's the car to look for.
static func build(look: Dictionary, who: String, rng: RandomNumberGenerator) -> Dictionary:
	var in_car := bool(look.get("in_car", false))
	var true_colour := PoliceDispatcher._colour_name(look.get("paint", Color.GRAY) if in_car else look.get("top", Color.GRAY))
	var said := true_colour
	var wrong := rng.randf() < float(WRONG_COLOUR.get(who, DEFAULT_WRONG))
	if wrong:
		var opts: Array = NEXT_TO.get(true_colour, ["grey"])
		said = str(opts[rng.randi() % opts.size()])
	var colour_text := said
	if wrong and rng.randf() < 0.5:
		colour_text = str(HEDGES[rng.randi() % HEDGES.size()]).format({"said": said, "other": true_colour})
	if not in_car:
		var text := "someone in a %s jacket with a paintball marker" % said
		if wrong and colour_text != said:
			text = "someone in a jacket: %s" % colour_text
		return {"text": text, "right_car": false}
	var m := CarModels.get_model(str(look.get("model_id", "civique")))
	var model := str(m.get("model", "car"))
	var kind := str(m.get("kind", "car")).split(",")[0].to_lower()
	if rng.randf() < float(NO_MODEL.get(who, DEFAULT_NO_MODEL)):
		return {"text": str(VAGUE_CARS[rng.randi() % VAGUE_CARS.size()]).format({"colour": said, "kind": kind}), "right_car": false}
	if wrong and colour_text != said:
		return {"text": "a %s, %s" % [model, colour_text], "right_car": false}
	return {"text": "a %s %s" % [said, model], "right_car": not wrong}

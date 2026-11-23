class_name Outfit
extends RefCounted
## What a person is wearing: one garment in each slot (hat, top, bottom,
## shoes), each a kind from the lists below and its colours.
##
## An outfit is plain data, a Dictionary, so it can be saved, sent over the
## network or edited in a menu. BodyBuilder makes the clothes part of the
## person's single mesh, so whatever they wear they're still one draw call,
## nothing pokes through, and the clothes move with the body.
##
##   {
##     "hat":    {"kind": "toque", "color": Color(...)},
##     "top":    {"kind": "hoodie", "color": Color(...), "trim": Color(...),
##                "print": "gentle_island", "back": "", "patch": ""},
##     "bottom": {"kind": "jeans", "color": Color(...)},
##     "shoes":  {"kind": "boots", "color": Color(...), "trim": Color(...)},
##   }
##
## "trim" is the second colour: a T-shirt's collar, a hoodie's cuffs, a
## bomber's knit bands, a varsity jacket's sleeves, a flannel's plaid, a
## shoe's sole. Leave it out to get a shade that goes with the main colour.
##
## Tops and hats can carry prints from PRINTS (names, "" for none): "print"
## on the front (big on a T-shirt or hoodie, a small logo on the chest of a
## jacket, on the front of a cap or toque), "back" across the back, and
## "patch" on the left sleeve.

## Kinds for each slot, in menu order, with the names shown to players.
const KINDS := {
	"hat": {"none": "No hat", "toque": "Toque", "cap": "Ball cap"},
	"top": {"tshirt": "T-shirt", "longsleeve": "Long-sleeve shirt", "hoodie": "Hoodie", "flannel": "Flannel shirt",
		"jacket": "Fall jacket", "bomber": "Bomber jacket", "denim": "Jean jacket", "varsity": "Varsity jacket",
		"puffer": "Puffer jacket"},
	"bottom": {"jeans": "Jeans", "trousers": "Trousers", "joggers": "Joggers", "shorts": "Shorts"},
	"shoes": {"sneakers": "Sneakers", "boots": "Boots", "dress": "Dress shoes"},
}

const SLOTS := ["hat", "top", "bottom", "shoes"]

## Graphics that can go on clothes, in the order of their tiles on
## textures/clothing/prints.png (drawn by tools/make_clothing_prints.py).
## All made-up Island brands and sayings.
const PRINTS := {
	"spud_or_die": "Spud or Die (Red Clay Spud Co.)",
	"canada_gull": "Canada Gull: Protect Your Fries",
	"gentle_island": "The Gentle Island* (*not after last call)",
	"cfa": "C.F.A. Came From Away",
	"whos_your_father": "Who's Your Father?",
	"pay_to_leave": "Free to Get On. Pay to Leave.",
	"spud_kings": "Spud Kings hockey",
	"varsity_s": "Varsity S",
	"mussel_beach": "Mussel Beach: No Shellfish Excuses",
	"potholes": "I Survived the Potholes",
	"tom_hurtins": "Tom Hurtin's",
	"crack_em": "Crack 'Em Open Lobster Supper Club",
	"island_time": "Island Time (we won't)",
	"mainlanders": "Mainlanders Go Home",
	"red_mud": "Red Mud Racing",
	"tca": "Trans-Canada Auto",
}

## Which kinds of top take which prints.
const FRONT_BIG := ["tshirt", "longsleeve", "hoodie"] # "print" is the big chest graphic
const HAS_PATCH := ["bomber", "puffer", "jacket", "denim"] # can have a sleeve patch


## Tile number on the prints sheet, or -1 for none.
static func print_tile(name: String) -> int:
	return PRINTS.keys().find(name)


## The player's starting look: red fall jacket, jeans, sneakers.
static func default_outfit() -> Dictionary:
	return {
		"hat": {"kind": "none", "color": Color(0.15, 0.2, 0.32)},
		"top": {"kind": "jacket", "color": Color(0.66, 0.16, 0.13), "trim": Color(0.82, 0.8, 0.74)},
		"bottom": {"kind": "jeans", "color": Color(0.21, 0.25, 0.34)},
		"shoes": {"kind": "sneakers", "color": Color(0.16, 0.12, 0.1), "trim": Color(0.86, 0.84, 0.8)},
	}


## Fills in anything missing (a slot, a kind, a colour) so the builder can
## rely on every field being there. Unknown kinds fall back to the default.
static func complete(outfit: Dictionary) -> Dictionary:
	var base := default_outfit()
	var out := {}
	for slot: String in SLOTS:
		var g: Dictionary = (base[slot] as Dictionary).duplicate()
		var given: Dictionary = outfit.get(slot, {})
		for key: String in given:
			g[key] = given[key]
		if not (KINDS[slot] as Dictionary).has(g["kind"]):
			g["kind"] = base[slot]["kind"]
		if not given.has("trim"):
			g["trim"] = default_trim(slot, g["kind"], g["color"])
		for key: String in ["print", "back", "patch"]:
			if not g.has(key) or not PRINTS.has(g[key]):
				g[key] = ""
		out[slot] = g
	return out


## A second colour that suits the first, for garments given only one.
static func default_trim(slot: String, kind: String, color: Color) -> Color:
	match slot:
		"top":
			match kind:
				"hoodie", "puffer":
					return color.darkened(0.25)
				"bomber":
					return color.darkened(0.55) # the knit bands
				"varsity":
					return Color(0.92, 0.89, 0.82) # cream leather sleeves
				"flannel":
					return Color(0.1, 0.1, 0.12) # buffalo check
				"denim":
					return Color(0.72, 0.45, 0.2) # copper buttons, orange stitching
			return color.lightened(0.15)
		"shoes":
			return Color(0.86, 0.84, 0.8) if kind == "sneakers" else Color(0.08, 0.07, 0.06)
	return color.darkened(0.2)


## Older looks gave only colours (top, under, bottom, shoes, hat): a jacket,
## jeans, sneakers and, if the hat colour isn't clear, a toque.
static func from_colours(look: Dictionary) -> Dictionary:
	var hat: Color = look.get("hat", Color(0, 0, 0, 0))
	var o := {
		"hat": {"kind": "toque" if hat.a > 0.0 else "none", "color": Color(hat.r, hat.g, hat.b)},
		"top": {"kind": "jacket", "color": look.get("top", Color(0.66, 0.16, 0.13)), "trim": look.get("under", Color(0.82, 0.8, 0.74))},
		"bottom": {"kind": "jeans", "color": look.get("bottom", Color(0.21, 0.25, 0.34))},
		"shoes": {"kind": "sneakers", "color": look.get("shoes", Color(0.16, 0.12, 0.1))},
	}
	return complete(o)


## Everyday clothes for a pedestrian in Charlottetown in late fall: mostly
## jackets and hoodies, jeans, a fair few toques and ball caps, and plenty
## of local brands.
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var tops := [Color(0.2, 0.33, 0.45), Color(0.55, 0.18, 0.16), Color(0.25, 0.38, 0.28), Color(0.78, 0.74, 0.66),
		Color(0.25, 0.25, 0.27), Color(0.7, 0.52, 0.22), Color(0.4, 0.28, 0.42), Color(0.85, 0.85, 0.83), Color(0.12, 0.13, 0.15)]
	var denim := [Color(0.21, 0.25, 0.34), Color(0.17, 0.2, 0.3), Color(0.3, 0.38, 0.5), Color(0.12, 0.12, 0.13)]
	var cloth := [Color(0.4, 0.35, 0.28), Color(0.33, 0.33, 0.3), Color(0.15, 0.15, 0.17), Color(0.45, 0.42, 0.36)]
	var hats := [Color(0.15, 0.2, 0.32), Color(0.5, 0.12, 0.12), Color(0.82, 0.8, 0.74), Color(0.2, 0.3, 0.22), Color(0.12, 0.12, 0.13)]
	var top_kind: String = _pick(rng, {"jacket": 2.5, "hoodie": 3.0, "puffer": 1.5, "bomber": 1.0, "denim": 1.0,
		"flannel": 1.2, "varsity": 0.4, "longsleeve": 1.0, "tshirt": 0.8})
	var bottom_kind: String = _pick(rng, {"jeans": 5.0, "trousers": 2.0, "joggers": 1.5, "shorts": 0.4})
	var shoe_kind: String = _pick(rng, {"sneakers": 5.0, "boots": 2.5, "dress": 1.0})
	var hat_kind: String = _pick(rng, {"none": 5.0, "toque": 2.5, "cap": 1.5})
	var bottoms: Array = denim if bottom_kind == "jeans" else cloth
	var shoe_colours := [Color(0.1, 0.1, 0.1), Color(0.45, 0.33, 0.22), Color(0.86, 0.85, 0.82), Color(0.25, 0.2, 0.16)]
	var top := {"kind": top_kind, "color": tops[rng.randi() % tops.size()]}
	var sayings := ["spud_or_die", "canada_gull", "gentle_island", "cfa", "whos_your_father", "pay_to_leave", "spud_kings",
		"mussel_beach", "potholes", "tom_hurtins", "crack_em", "island_time", "mainlanders", "red_mud", "tca"]
	match top_kind:
		"tshirt", "longsleeve", "hoodie":
			if rng.randf() < 0.7:
				top["print"] = sayings[rng.randi() % sayings.size()]
		"varsity":
			top["color"] = [Color(0.12, 0.16, 0.32), Color(0.45, 0.1, 0.12), Color(0.1, 0.25, 0.15)][rng.randi() % 3]
			top["print"] = "varsity_s"
			top["back"] = "spud_kings"
		"puffer":
			top["patch"] = "canada_gull"
		"bomber":
			top["color"] = [Color(0.29, 0.33, 0.22), Color(0.1, 0.12, 0.16), Color(0.12, 0.12, 0.12)][rng.randi() % 3]
			if rng.randf() < 0.5:
				top["patch"] = "canada_gull"
			if rng.randf() < 0.25:
				top["back"] = ["spud_kings", "tca", "red_mud", "spud_or_die"][rng.randi() % 4]
		"denim":
			top["color"] = [Color(0.3, 0.42, 0.6), Color(0.22, 0.3, 0.45), Color(0.5, 0.6, 0.72)][rng.randi() % 3]
			if rng.randf() < 0.3:
				top["back"] = ["spud_or_die", "red_mud", "mainlanders", "crack_em"][rng.randi() % 4]
		"flannel":
			top["color"] = [Color(0.6, 0.12, 0.12), Color(0.15, 0.3, 0.2), Color(0.2, 0.3, 0.5), Color(0.75, 0.6, 0.2)][rng.randi() % 4]
	var hat := {"kind": hat_kind, "color": hats[rng.randi() % hats.size()]}
	if hat_kind == "cap" and rng.randf() < 0.6:
		hat["print"] = ["spud_kings", "spud_or_die", "tca", "red_mud", "canada_gull", "tom_hurtins"][rng.randi() % 6]
	return complete({
		"hat": hat,
		"top": top,
		"bottom": {"kind": bottom_kind, "color": bottoms[rng.randi() % bottoms.size()]},
		"shoes": {"kind": shoe_kind, "color": shoe_colours[rng.randi() % shoe_colours.size()]},
	})


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for w: float in weights.values():
		total += w
	var r := rng.randf() * total
	for key: String in weights:
		r -= float(weights[key])
		if r <= 0.0:
			return key
	return weights.keys()[0]

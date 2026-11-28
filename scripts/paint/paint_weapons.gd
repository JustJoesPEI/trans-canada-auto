class_name PaintWeapons
extends RefCounted
## The markers and throwables (docs/design.md section 2, "Markers and
## throwables you can buy"), as plain data that `PaintShots.fire` reads, and
## the twelve paint colours (section 3, "Colours").
##
## A weapon is a Dictionary so the server can send it, a shop can list it and
## a part can change one number without a class per weapon. Fields:
##
##   id, name          what it is, and what it's called in the game
##   type              what kind of weapon it is, in plain words; the main
##                     label everywhere (the name alone doesn't say)
##   kind              "ball" (bursts where it lands), "grenade" (thrown,
##                     bursts after `fuse` seconds wherever it is) or
##                     "bomb" (lobbed, bursts on impact)
##   speed             m/s out of the barrel (or the hand)
##   spread            degrees, the cone a ball can leave in, aimed and
##                     standing still (PaintMarker widens it running and
##                     from the hip)
##   hit_value         hits a direct hit on a person counts as (a head hit
##                     counts double)
##   colour            null: the shooter's own paint colour
##   splash_radius     m; 0 for a ball, which paints only what it hits
##   splash_hits       hits on each person inside the splash
##   car_coverage      share of a car's coverage a direct hit fills (0..1);
##                     0 means "one ball's worth" (PaintCoverage.BALL_FILL)
##   splash_car_coverage   the same for cars caught in the splash
##   splat_size        m, radius of the splat a ball leaves on a wall
##   gravity_scale     1 is real gravity
##   life              s a ball flies before it's dropped
##   fuse              s, a grenade's burst time
##   fire_rate         most shots a second pulling as fast as you can
##   hold_rate         shots a second holding the trigger (0: one per pull)
##   hopper            shots before a reload
##   reload_time       s
##   scope_fov         degrees of view through its scope once fully aimed
##                     (0: no scope, aiming stays over the shoulder)
##   kick              degrees the view jumps up on a shot and springs
##                     back from (CameraRig.kick), so a shot has weight;
##                     it's back before the next pull, so it never drags
##                     the aim (fair on a stick and a mouse alike)
##   bloom             degrees each shot adds to the spread, easing off
##                     over about a fifth of a second (BLOOM_EASE): paced
##                     shots stay tight, spamming the trigger opens up,
##                     and the crosshair's ring shows it
##   rumble            [weak, strong, seconds] for a shot on a controller

## Real gravity, m/s². The Islander's ball at 75 m/s has dropped about 1 m
## by 35 m and 3 m by 60 m (design: "drops noticeably past about 35 m and
## isn't worth shooting past 60 m").
const GRAVITY := 9.81

const ISLANDER := {
	"id": "islander", "name": "The Islander", "type": "Paintball gun", "kind": "ball",
	"speed": 75.0, # design
	"spread": 0.6, # not in the design: about 0.5 m wide at 50 m when aimed and still
	"hit_value": 1,
	"colour": null,
	"splash_radius": 0.0, "splash_hits": 0,
	"car_coverage": 0.0, "splash_car_coverage": 0.0,
	"splat_size": 0.16, # not in the design: a 16 cm splat reads as a paintball hit
	"gravity_scale": 1.0, "life": 2.0,
	"fuse": 0.0,
	"fire_rate": 8.0, "hold_rate": 5.0, # design
	"hopper": 40, "reload_time": 1.6, # design
	"kick": 0.55, "bloom": 0.22, "rumble": [0.22, 0.0, 0.05],
}

const FARMHAND := {
	"id": "farmhand", "name": "The Farmhand", "type": "Sniper rifle", "kind": "ball",
	# Design: 1.5 a second, very accurate, out to 80 m, hits count 3 (of a
	# player's 8: three to the body, two to the head; an officer's 4 goes
	# in two, or one to the head). The
	# speed and the lighter drop are what make 80 m reachable (not in the
	# design): at 90 m/s with 0.7 g it drops about 2.5 m by 80 m.
	"speed": 90.0, "spread": 0.15,
	"hit_value": 3,
	"colour": null,
	"splash_radius": 0.0, "splash_hits": 0,
	"car_coverage": 0.0, "splash_car_coverage": 0.0,
	"splat_size": 0.2,
	"gravity_scale": 0.7, "life": 2.5,
	"fuse": 0.0,
	"fire_rate": 1.5, "hold_rate": 0.0,
	"hopper": 12, "reload_time": 2.2, # not in the design
	# A scope: aimed, the view goes down it, about 3.3x the shoulder view's
	# 50 degrees, so a person at 80 m is easy to see. Not in the design.
	"scope_fov": 15.0,
	"kick": 2.2, "bloom": 0.0, "rumble": [0.15, 0.55, 0.12],
}

const LOBBYIST := {
	"id": "lobbyist", "name": "The Lobbyist", "type": "Rapid-fire gun", "kind": "ball",
	# Design: 15 a second, wide spread, a 100-ball hopper, hits count 1.
	"speed": 70.0, "spread": 3.5,
	"hit_value": 1,
	"colour": null,
	"splash_radius": 0.0, "splash_hits": 0,
	"car_coverage": 0.0, "splash_car_coverage": 0.0,
	"splat_size": 0.14,
	"gravity_scale": 1.0, "life": 2.0,
	"fuse": 0.0,
	"fire_rate": 15.0, "hold_rate": 15.0,
	"hopper": 100, "reload_time": 2.4, # reload not in the design
	"kick": 0.3, "bloom": 0.25, "rumble": [0.3, 0.0, 0.04],
}

const JAM_JARS := {
	"id": "jam_jars", "name": "Mustard Pickles", "type": "Paint grenades", "kind": "grenade",
	# Design: carry 4, thrown, burst after 1.5 s: 4 hits (half a player's
	# meter, an officer out) on everyone within 3 m and +15% coverage on a car.
	# A jar of mustard pickles, because every Island pantry has one. The
	# burst is 3.5 m now (Joe: it should feel like a grenade went off), with
	# a big splat under it and globs thrown round (PaintShots._burst).
	"speed": 16.0, "spread": 1.5, # a throw, not in the design
	"hit_value": 0, # the jar itself doesn't count; the burst does
	"colour": null,
	"splash_radius": 3.5, "splash_hits": 4,
	"car_coverage": 0.15, "splash_car_coverage": 0.15,
	"splat_size": 0.85, "globs": 16, "bang": 1.0,
	"gravity_scale": 1.0, "life": 1.5,
	"fuse": 1.5,
	"fire_rate": 1.0, "hold_rate": 0.0,
	"hopper": 4, "reload_time": 0.0, # carried, not reloaded
	"kick": 0.0, "bloom": 0.0, "rumble": [0.0, 0.25, 0.08],
}

const TOURIST_SEASON := {
	"id": "tourist_season", "name": "Tourist Season", "type": "Bomb launcher", "kind": "bomb",
	# Design: lobs paint bombs, 4 hits on everyone within 5 m, a direct hit
	# on a car is +30% coverage, 4 rounds, slow to reload. A car caught in
	# the splash gets +10% (not in the design).
	"speed": 32.0, "spread": 0.8,
	"hit_value": 4,
	"colour": null,
	"splash_radius": 5.0, "splash_hits": 4,
	"car_coverage": 0.3, "splash_car_coverage": 0.1,
	"splat_size": 0.8, "globs": 12, "bang": 1.2,
	"gravity_scale": 1.0, "life": 4.0,
	"fuse": 0.0,
	"fire_rate": 1.2, "hold_rate": 0.0,
	"hopper": 4, "reload_time": 4.0, # "slow to reload": not a number in the design
	"kick": 3.0, "bloom": 0.0, "rumble": [0.25, 0.8, 0.18],
}

## Every weapon by id.
const ALL := {
	"islander": ISLANDER, "farmhand": FARMHAND, "lobbyist": LOBBYIST,
	"jam_jars": JAM_JARS, "tourist_season": TOURIST_SEASON,
}

## The twelve player paint colours: bright, saturated, each reads apart from
## the others, and none of them is a dark red (nothing that looks like
## blood). Design section 3, "Colours".
const COLOURS: Array[Color] = [
	Color(1.0, 0.45, 0.0), # neon orange
	Color(0.0, 0.8, 0.72), # teal
	Color(1.0, 0.2, 0.62), # hot pink
	Color(0.55, 1.0, 0.1), # lime
	Color(0.1, 0.42, 1.0), # electric blue
	Color(1.0, 0.92, 0.05), # yellow
	Color(0.68, 0.3, 1.0), # violet
	Color(0.0, 0.85, 1.0), # cyan
	Color(1.0, 0.62, 0.78), # bubblegum
	Color(0.15, 0.95, 0.45), # spring green
	Color(1.0, 0.72, 0.2), # tangerine
	Color(0.95, 0.95, 1.0), # bright white
]

## What each of the twelve is called (the character creator shows it).
const COLOUR_NAMES: Array[String] = ["Neon orange", "Teal", "Hot pink", "Lime", "Electric blue", "Yellow",
	"Violet", "Cyan", "Bubblegum", "Spring green", "Tangerine", "Bright white"]

## The colour a new player starts with (teal).
const DEFAULT_COLOUR := 1

## The FIP's evidence paint: the orange that gets you spotted ("you're the
## orange car"). Not one of the twelve, so nobody's own colour is the police's.
const POLICE_COLOUR := Color(1.0, 0.36, 0.0)


static func get_weapon(id: String) -> Dictionary:
	return ALL.get(id, ISLANDER)


## The plain label and the name together, for a shop card or a message:
## 'Sniper rifle, "The Farmhand"'.
static func full_label(w: Dictionary) -> String:
	return '%s, "%s"' % [str(w.get("type", w.get("name", ""))), str(w.get("name", ""))]


## Which of the twelve is nearest `c` (a saved colour is always one of
## them, so an edited save can't make a blood red).
static func nearest_colour(c: Color) -> int:
	var best := DEFAULT_COLOUR
	var best_d := INF
	for i in COLOURS.size():
		var o := COLOURS[i]
		var d := absf(o.r - c.r) + absf(o.g - c.g) + absf(o.b - c.b)
		if d < best_d:
			best_d = d
			best = i
	return best


static func colour_name(c: Color) -> String:
	return COLOUR_NAMES[nearest_colour(c)]

class_name StickFeel
extends RefCounted
## How the right stick turns the view (looking round and aiming), the part
## that makes most of the difference to aiming with a controller
## (docs/design.md, "Controllers and aim assist").
##
## - Deadzones, round rather than square, so diagonals feel the same as
##   straight pushes: inside the inner deadzone the stick does nothing, in
##   the outer band at the edge it's full, and the travel between is
##   stretched to 0..1.
## - A response curve on that: exponential by default, (e^(k t) - 1) /
##   (e^k - 1), which keeps the middle of the throw slow for small
##   corrections and still reaches full speed at the edge; or linear.
## - Turn boost: hold the stick sideways at the edge for 0.2 s and the turn
##   speed ramps up (to 1.9 times over 0.35 s), so you can whip round to
##   someone behind you. Easing off the edge drops it straight away.
##
## The mouse never goes through any of this.

## How bent the exponential curve is (higher: slower in the middle).
## Half stick gives 22% speed, three-quarters 49%.
const EXPO := 2.5

const BOOST_EDGE := 0.98 ## shaped stick at least this far out...
const BOOST_SIDEWAYS := 0.8 ## ...and pushed at least this much sideways
const BOOST_DELAY := 0.2 ## seconds at the edge before it starts
const BOOST_RAMP := 0.35 ## seconds to build to full
const BOOST_MAX := 1.9 ## times the normal turn speed
const BOOST_DROP := 0.08 ## seconds to fall back, off the edge

## The current turn-boost multiplier for yaw (1 = none).
var boost := 1.0
var _edge_time := 0.0


## The stick (raw, -1..1 each way) after the deadzones and the curve.
static func shape(raw: Vector2, inner: float, outer: float, curve: AimSettings.Response) -> Vector2:
	var m := raw.length()
	if m <= inner or m <= 0.0:
		return Vector2.ZERO
	var t := clampf((m - inner) / maxf(0.001, 1.0 - outer - inner), 0.0, 1.0)
	return raw / m * response(t, curve)


## The response curve alone, 0..1 in and out.
static func response(t: float, curve: AimSettings.Response) -> float:
	if curve == AimSettings.Response.LINEAR:
		return t
	return (exp(EXPO * t) - 1.0) / (exp(EXPO) - 1.0)


## shape() with the player's settings.
static func shape_with_settings(raw: Vector2) -> Vector2:
	AimSettings.ensure_loaded()
	return shape(raw, AimSettings.inner_deadzone, AimSettings.outer_deadzone, AimSettings.curve)


## Call once a frame with the shaped stick; returns the yaw multiplier.
func update_boost(shaped: Vector2, delta: float) -> float:
	var at_edge := shaped.length() >= BOOST_EDGE and absf(shaped.x) >= BOOST_SIDEWAYS
	if at_edge:
		_edge_time += delta
		boost = 1.0 + (BOOST_MAX - 1.0) * smoothstep(0.0, 1.0, (_edge_time - BOOST_DELAY) / BOOST_RAMP)
	else:
		_edge_time = 0.0
		boost = move_toward(boost, 1.0, (BOOST_MAX - 1.0) * delta / BOOST_DROP)
	return boost


func reset() -> void:
	boost = 1.0
	_edge_time = 0.0

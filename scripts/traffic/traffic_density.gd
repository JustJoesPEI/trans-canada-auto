class_name TrafficDensity
extends RefCounted
## How much traffic there is: a cap, a share of it by the time of day, and more of it where the streets are busier (downtown, the
## Arterial) than out in the suburbs.
##
## The game has no clock of its own yet. Until it does, the hour is
## `hour` (early afternoon by default), or the `hour` of a node in group
## "game_clock" if there is one, so a day/night cycle only has to put itself
## in that group. The month (for the tourists) is the real one.

## The hour of day (0-24) when no "game_clock" node says otherwise.
static var hour := 13.0
## The month (1-12) when no "game_clock" node says otherwise.
static var month := int(Time.get_date_dict_from_system().get("month", 7))

## None of this depends on the graphics settings: traffic is the same for
## every player (for multiplayer), and graphics only change how it's drawn.

## Traffic vehicles at once, near any player.
const CAP := 80
## Of those, how many get full physics (the nearest): the costly ones, so
## only the cars close enough to touch.
const PHYSICS_CAP := 12
## Full physics within this of a player (m). Past it, they move along the
## streets without physics (RoadFollower), drawn as the parked-car meshes.
const PHYSICS_RADIUS := 130.0
## On a dedicated server (`server`), which draws nothing: physics only for
## the cars a player could touch in the next second or two, the nearest
## few. It's what a server can afford for 48 players (tools/traffic_server.gd),
## and nobody there sees the swap. What's simulated is the same for every
## player either way: there's one traffic, the server's.
static var server := false
const SERVER_PHYSICS_CAP := 4
const SERVER_PHYSICS_RADIUS := 80.0
## They're placed and taken away between these distances of a player (m),
## and only where no player can see.
const SPAWN_MIN := 70.0
const SPAWN_MAX := 380.0
## Out past this they're taken away (when nobody can see them).
const DESPAWN := 450.0

## Share of the cap by hour: [hour, share], straight lines between.
const BY_HOUR := [[0.0, 0.2], [3.0, 0.07], [5.5, 0.15], [7.0, 0.6], [8.0, 1.0], [9.0, 0.75],
	[12.0, 0.9], [15.0, 0.92], [16.5, 1.0], [18.0, 0.8], [20.0, 0.5], [22.0, 0.33], [24.0, 0.2]]
## How busy each class of street is (per metre), for where cars appear and
## how many there are round a player.
const CLASS_WEIGHT := {"motorway": 2.5, "trunk": 2.5, "primary": 2.2, "secondary": 1.8,
	"tertiary": 1.3, "residential": 0.55, "unclassified": 0.5, "living_street": 0.2}
## Street weight within PLACE_RADIUS of a player that counts as a busy
## downtown (full share of the cap); quieter places get less, down to
## PLACE_MIN.
const PLACE_RADIUS := 300.0
const PLACE_BUSY := 7000.0
const PLACE_MIN := 0.55


## 0 on Low graphics, 1 on High (the Graphics autoload, found by path so
## headless tools that load this before the autoloads still compile). For
## drawing only: how much traffic there is never depends on it.
static func level() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var g := tree.root.get_node_or_null("Graphics") if tree != null else null
	return 0 if g != null and int(g.get("level")) == 0 else 1


## How many of each player's nearest get full physics, and within what.
static func physics_cap() -> int:
	return SERVER_PHYSICS_CAP if server else PHYSICS_CAP


static func physics_radius() -> float:
	return SERVER_PHYSICS_RADIUS if server else PHYSICS_RADIUS


static func current_hour(tree: SceneTree) -> float:
	var clock := tree.get_first_node_in_group("game_clock") if tree != null else null
	if clock != null and clock.get("hour") != null:
		return float(clock.get("hour"))
	return hour


static func current_month(tree: SceneTree) -> int:
	var clock := tree.get_first_node_in_group("game_clock") if tree != null else null
	if clock != null and clock.get("month") != null:
		return int(clock.get("month"))
	return month


## Share of the cap at an hour.
static func time_share(h: float) -> float:
	h = fposmod(h, 24.0)
	for i in range(BY_HOUR.size() - 1):
		var a: Array = BY_HOUR[i]
		var b: Array = BY_HOUR[i + 1]
		if h <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (h - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(BY_HOUR[0][1])


static func class_weight(e: RoadNetwork.RoadEdge) -> float:
	if e.bridge and e.length < 30.0:
		return 0.0
	if e.highway.ends_with("_link"):
		return 0.6
	return float(CLASS_WEIGHT.get(e.highway, 0.0))


## Share of the cap for how busy the streets round p are.
static func place_share(net: RoadNetwork, p: Vector2) -> float:
	var sum := 0.0
	for e in net.edges_near(Rect2(p - Vector2(PLACE_RADIUS, PLACE_RADIUS), Vector2(PLACE_RADIUS, PLACE_RADIUS) * 2.0)):
		sum += e.length * class_weight(e)
	return clampf(sum / PLACE_BUSY, PLACE_MIN, 1.0)


## How many traffic vehicles there should be round a player at p, with
## `police` police vehicles about: traffic makes room for the police (each
## police vehicle takes one traffic car's place), never the other way round.
static func target(net: RoadNetwork, p: Vector2, tree: SceneTree, police: int) -> int:
	var cap := CAP
	var n := roundi(cap * time_share(current_hour(tree)) * place_share(net, p))
	return clampi(mini(n, cap - police), 0, cap)


# --- by area, for many players ---------------------------------------------------
#
# With more than one player (a server), traffic is counted by area, not by
# player: the town is cut into CELL squares, and each square near a player
# wants a share of that player's `target`, by how busy its streets are and
# how near the player it is (nearer streets get more, as `place` weights
# them). A square near two players wants the larger of their two shares,
# not both added: ten players downtown share the same cars, they don't
# bring ten lots. With one player it comes to the same count as before.

## Side of an area square (m).
const CELL := 100.0
## How much nearer streets count than far ones (as TrafficManager placed
## them before: weight * NEAR_FALLOFF / (NEAR_FALLOFF + distance)).
const NEAR_FALLOFF := 160.0
## Most traffic vehicles the whole town has at once, however many players.
const TOWN_MAX := 1500

static var _cell_w := {} ## Vector2i -> street weight in that square
static var _cell_w_net: RoadNetwork = null


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


## Street weight in each square (metres of street times class_weight),
## worked out once per street network.
static func cell_weights(net: RoadNetwork) -> Dictionary:
	if _cell_w_net == net:
		return _cell_w
	_cell_w_net = net
	_cell_w = {}
	for e: RoadNetwork.RoadEdge in net.edges:
		var w := class_weight(e)
		if w <= 0.0 or e.bridge or e.length < 24.0:
			continue
		# Along it in 10 m steps, each step's weight in the square it's in.
		var steps := maxi(1, ceili(e.length / 10.0))
		var each := e.length / steps * w
		for i in steps:
			var p: Vector2 = RoadNetwork.sample(e.points, (i + 0.5) * e.length / steps)[0]
			var c := cell_of(p)
			_cell_w[c] = float(_cell_w.get(c, 0.0)) + each
	return _cell_w


## How many traffic vehicles each square wants, for players at `viewers`
## (ground positions), with `police` police vehicles about and `share` of
## the usual (a big chase thins them): Vector2i -> float (a fraction is
## the odds of one more).
static func cell_targets(net: RoadNetwork, viewers: PackedVector2Array, tree: SceneTree, police: int, share := 1.0) -> Dictionary:
	var weights := cell_weights(net)
	var out := {}
	var r := SPAWN_MAX
	var reach := ceili(r / CELL)
	if server:
		# Each player's share of the squares round them, by where they are
		# to within SERVER_SPOT metres, worked out once per spot (48 players'
		# streets were a long step every check).
		if _spot_net != net or _spot_cache.size() > 20000:
			_spot_net = net
			_spot_cache = {}
		var hour := time_share(current_hour(tree))
		for v: Vector2 in viewers:
			var key := Vector2i(floori(v.x / SERVER_SPOT), floori(v.y / SERVER_SPOT))
			var spot: Array = _spot_cache.get(key, [])
			if spot.is_empty():
				spot = _spot(net, weights, (Vector2(key) + Vector2(0.5, 0.5)) * SERVER_SPOT, r, reach)
				_spot_cache[key] = spot
			var n := roundi(CAP * hour * float(spot[0]))
			var want := clampi(mini(n, CAP - police), 0, CAP) * share
			if want <= 0.0:
				continue
			var shares: Dictionary = spot[1]
			for c: Vector2i in shares:
				var t: float = want * float(shares[c])
				if t > float(out.get(c, 0.0)):
					out[c] = t
	for v: Vector2 in (PackedVector2Array() if server else viewers):
		var want := target(net, v, tree, police) * share
		if want <= 0.0:
			continue
		var vc := cell_of(v)
		var mine := {}
		var sum := 0.0
		for x in range(vc.x - reach, vc.x + reach + 1):
			for z in range(vc.y - reach, vc.y + reach + 1):
				var c := Vector2i(x, z)
				var w := float(weights.get(c, 0.0))
				if w <= 0.0:
					continue
				var d := cell_center(c).distance_to(v)
				if d > r:
					continue
				w *= NEAR_FALLOFF / (NEAR_FALLOFF + d)
				mine[c] = w
				sum += w
		if sum <= 0.0:
			continue
		for c: Vector2i in mine:
			var t: float = want * float(mine[c]) / sum
			if t > float(out.get(c, 0.0)):
				out[c] = t
	# The town's own limit, whatever the players.
	var total := 0.0
	for c: Vector2i in out:
		total += float(out[c])
	if total > TOWN_MAX:
		var k := TOWN_MAX / total
		for c: Vector2i in out:
			out[c] = float(out[c]) * k
	return out


## On a server, a player's spot is this many metres square (cell_targets).
const SERVER_SPOT := 20.0
static var _spot_cache := {} ## spot -> [place_share, {square: share of the spot's traffic}]
static var _spot_net: RoadNetwork = null


## For players at p: how busy the place is (place_share) and how their
## traffic is shared out over the squares round them (as cell_targets
## shares it, the shares adding up to 1; none if there's no street).
static func _spot(net: RoadNetwork, weights: Dictionary, p: Vector2, r: float, reach: int) -> Array:
	var vc := cell_of(p)
	var mine := {}
	var sum := 0.0
	for x in range(vc.x - reach, vc.x + reach + 1):
		for z in range(vc.y - reach, vc.y + reach + 1):
			var c := Vector2i(x, z)
			var w := float(weights.get(c, 0.0))
			if w <= 0.0:
				continue
			var d := cell_center(c).distance_to(p)
			if d > r:
				continue
			w *= NEAR_FALLOFF / (NEAR_FALLOFF + d)
			mine[c] = w
			sum += w
	var shares := {}
	if sum > 0.0:
		for c: Vector2i in mine:
			shares[c] = float(mine[c]) / sum
	return [place_share(net, p), shares]

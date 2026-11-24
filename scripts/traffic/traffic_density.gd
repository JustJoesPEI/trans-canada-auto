class_name TrafficDensity
extends RefCounted
## How much traffic there is: a cap by graphics level, a share of it by the
## time of day, and more of it where the streets are busier (downtown, the
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

## Traffic vehicles at once, near any player: [Low, High].
const CAP := [16, 32]
## Of those, how many get full physics (the nearest): [Low, High].
const PHYSICS_CAP := [7, 14]
## Full physics within this of a player (m): [Low, High]. Past it, they move
## along the streets without physics (RoadFollower), drawn as the parked-car
## meshes.
const PHYSICS_RADIUS := [110.0, 150.0]
## They're placed and taken away between these distances of a player (m),
## and only where no player can see.
const SPAWN_MIN := 70.0
const SPAWN_MAX := [300.0, 420.0]
## Out past this they're taken away (when nobody can see them).
const DESPAWN := [360.0, 500.0]

## Share of the cap by hour: [hour, share], straight lines between.
const BY_HOUR := [[0.0, 0.2], [3.0, 0.07], [5.5, 0.15], [7.0, 0.6], [8.0, 1.0], [9.0, 0.75],
	[12.0, 0.8], [15.0, 0.85], [16.5, 1.0], [18.0, 0.8], [20.0, 0.5], [22.0, 0.33], [24.0, 0.2]]
## How busy each class of street is (per metre), for where cars appear and
## how many there are round a player.
const CLASS_WEIGHT := {"motorway": 2.5, "trunk": 2.5, "primary": 2.2, "secondary": 1.8,
	"tertiary": 1.3, "residential": 0.55, "unclassified": 0.5, "living_street": 0.2}
## Street weight within PLACE_RADIUS of a player that counts as a busy
## downtown (full share of the cap); quieter places get less, down to
## PLACE_MIN.
const PLACE_RADIUS := 300.0
const PLACE_BUSY := 7000.0
const PLACE_MIN := 0.3


## 0 on Low graphics, 1 on High (the Graphics autoload, found by path so
## headless tools that load this before the autoloads still compile).
static func level() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var g := tree.root.get_node_or_null("Graphics") if tree != null else null
	return 0 if g != null and int(g.get("level")) == 0 else 1


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
	var cap: int = CAP[level()]
	var n := roundi(cap * time_share(current_hour(tree)) * place_share(net, p))
	return clampi(mini(n, cap - police), 0, cap)

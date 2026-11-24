class_name JunctionRules
extends RefCounted
## Who gives way to whom where streets meet, read from the map the same way
## the street furniture is placed (StreetProps), so a driver stops where a
## stop sign stands and obeys the lights that are hung:
##
##   SIGNAL   the junction has traffic lights (RoadNetwork.signal_nodes);
##            each way in reads its phase with TrafficSignal.lamp_at
##   STOP     a stop sign (OSM highway=stop) on this way in: stop, then
##            give way to everyone
##   YIELD    a give-way sign (highway=give_way), a way onto a roundabout,
##            a slip road, or a smaller street joining a bigger one (a
##            residential street onto the Arterial): give way to traffic on
##            the bigger street
##   NONE     equals meeting, or the bigger street: carry on (a left turn
##            still waits for a gap in the oncoming traffic)
##
## Worked out once per network and cached.

enum Rule { NONE, SIGNAL, STOP, YIELD }

static var _cache := {}

var net: RoadNetwork
## "edge index@node" -> Rule for the signs that face a way in.
var _signs := {}


static func of(network: RoadNetwork, data: StreetData) -> JunctionRules:
	var key := network.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var r := JunctionRules.new()
	r.net = network
	if data != null:
		r._read_signs(data, "highway=stop", Rule.STOP)
		r._read_signs(data, "highway=give_way", Rule.YIELD)
	_cache[key] = r
	return r


func _read_signs(data: StreetData, type: String, control: Rule) -> void:
	for p in data.points_of_type(type):
		var hit := net.nearest_on_streets(p.pos, 2.0)
		if hit.is_empty():
			continue
		var e: RoadNetwork.RoadEdge = hit["edge"]
		var along: float = hit["along"]
		# As StreetProps._stop_signs: traffic stops at the nearer end.
		var nid := e.b if along > e.length * 0.5 else e.a
		if net.degree(nid) < 3 and not net.signal_nodes.has(nid):
			continue
		_signs["%d@%s" % [e.index, nid]] = control


## How traffic coming in along `e` into junction `nid` is controlled.
func control(nid: String, e: RoadNetwork.RoadEdge) -> Rule:
	if net.signal_nodes.has(nid):
		return Rule.SIGNAL
	var sign: Variant = _signs.get("%d@%s" % [e.index, nid])
	if sign != null:
		return sign
	if net.degree(nid) < 3:
		return Rule.NONE
	var mine := rank(e)
	var onto_ring := false
	var top := -1
	for inc: RoadNetwork.Incident in net.incidents[nid]:
		if inc.edge == e:
			continue
		onto_ring = onto_ring or inc.edge.roundabout
		top = maxi(top, rank(inc.edge))
	if onto_ring and not e.roundabout:
		return Rule.YIELD
	if e.roundabout:
		return Rule.NONE # on the ring: right of way
	if e.highway.ends_with("_link") and top > mine:
		return Rule.YIELD
	if top >= mine + 1 and top >= 3:
		return Rule.YIELD # onto a main road
	if top >= mine + 2:
		return Rule.YIELD
	return Rule.NONE


## How important a street is (higher gives way less).
static func rank(e: RoadNetwork.RoadEdge) -> int:
	if e.roundabout:
		return 6
	var h := e.highway
	if h.ends_with("_link"):
		return 1
	match h:
		"motorway", "trunk":
			return 5
		"primary":
			return 4
		"secondary":
			return 3
		"tertiary":
			return 2
		"service", "living_street":
			return 0
	return 1


## The speed limit along a street (km/h): Island town limits by class.
static func limit_kmh(e: RoadNetwork.RoadEdge) -> float:
	if e == null:
		return 50.0
	if e.roundabout:
		return 30.0
	var h := e.highway
	if h.ends_with("_link"):
		return 50.0
	match h:
		"motorway":
			return 90.0
		"trunk":
			return 80.0
		"primary":
			return 60.0
		"secondary", "tertiary":
			return 50.0
		"service", "living_street":
			return 20.0
	return 40.0

class_name GeoProjection
extends RefCounted
## Converts WGS84 latitude/longitude to Godot world metres and back.
##
## A local tangent-plane projection around a fixed origin: accurate to a few
## centimetres across a few kilometres, which covers all of Charlottetown.
## Godot axes: +X = east, -Z = north, +Y = up. One unit = one metre.
## Ground positions are passed around as Vector2(x, z).

var origin_lat: float
var origin_lon: float
var _m_per_deg_lat: float
var _m_per_deg_lon: float


func _init(lat: float, lon: float) -> void:
	origin_lat = lat
	origin_lon = lon
	var phi := deg_to_rad(lat)
	# Standard series for the WGS84 ellipsoid.
	_m_per_deg_lat = 111132.92 - 559.82 * cos(2.0 * phi) + 1.175 * cos(4.0 * phi)
	_m_per_deg_lon = 111412.84 * cos(phi) - 93.5 * cos(3.0 * phi)


## Longitude/latitude (GeoJSON order) to a ground position Vector2(x, z).
func to_ground(lon: float, lat: float) -> Vector2:
	return Vector2((lon - origin_lon) * _m_per_deg_lon, -(lat - origin_lat) * _m_per_deg_lat)


func to_world(lon: float, lat: float, height: float = 0.0) -> Vector3:
	var g := to_ground(lon, lat)
	return Vector3(g.x, height, g.y)


## Ground position back to Vector2(lon, lat).
func to_lon_lat(ground: Vector2) -> Vector2:
	return Vector2(origin_lon + ground.x / _m_per_deg_lon, origin_lat - ground.y / _m_per_deg_lat)

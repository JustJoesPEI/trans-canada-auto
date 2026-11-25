class_name GroundCache
extends RefCounted
## The ground as the game shapes it at startup, saved so the shipped game
## can load it instead of working it out again: the survey heights with the
## hills raised (Terrain.RELIEF), the ground built up at bridge ends
## (RoadMesher.seat_bridges) and smoothed under the streets
## (RoadMesher.smooth_streets), plus the bridge-end heights those leave in
## the road network. That's most of the wait at startup (13 of the 22 s on
## an AMD Ryzen laptop), and it comes out the same every time from the same
## map data.
##
## tools/bake_ground.gd writes it (the build workflow runs it before
## exporting); it isn't committed (data/baked/ is in .gitignore). The file
## starts with a key made from every map file the ground depends on and
## VERSION, and is only used when the key matches, so new map data never
## gets old ground. A change to how the ground is shaped (the code) must
## bump VERSION, since the code can't be hashed in an exported game. Run
## from the editor the game never uses it (it works the ground out as
## before, and live map edits re-shape it), so a stale file there can't
## mislead.

const PATH := "res://data/baked/ground.bin"
## Bump when RELIEF, seat_bridges, smooth_streets or anything they use
## changes how the ground comes out.
const VERSION := 1


## The key for this map data: VERSION and the md5 of every file the ground
## and the streets it's smoothed under are made from.
static func key(data: StreetData) -> String:
	var files: Array[String] = [
		data.config_path,
		str(data.config.get("elevation", "res://data/elevation.json")),
		data.city_dir.path_join("index.json"),
		data.city_dir.path_join("roads.geojson"),
		str(data.config.get("edits", "")),
		str(data.config.get("street_fit", "")),
	]
	var elev := str(data.config.get("elevation", "res://data/elevation.json"))
	var elev_info: Variant = JSON.parse_string(FileAccess.get_file_as_string(elev)) if FileAccess.file_exists(elev) else null
	if elev_info is Dictionary:
		files.append(elev.get_base_dir().path_join(str((elev_info as Dictionary).get("file", "elevation.bin"))))
	var s := "v%d|relief %s %s %s" % [VERSION, Terrain.RELIEF, Terrain.RELIEF_BLUR_M, Terrain.RELIEF_SHORE_M]
	for f in files:
		s += "|" + (FileAccess.get_md5(f) if f != "" and FileAccess.file_exists(f) else "-")
	return s.md5_text()


## Saves the shaped ground and the bridge-end heights.
static func save(terrain: Terrain, net: RoadNetwork, data_key: String, path := PATH) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var heights := terrain.heights_bytes()
	var packed := heights.compress(FileAccess.COMPRESSION_ZSTD)
	f.store_pascal_string(data_key)
	f.store_32(terrain.nx)
	f.store_32(terrain.nz)
	f.store_32(heights.size())
	f.store_32(packed.size())
	f.store_buffer(packed)
	var ends := var_to_bytes(net.bridge_end_h)
	f.store_32(ends.size())
	f.store_buffer(ends)
	f.close()
	return OK


## Whether there's a saved ground for this key (read from its first bytes).
static func has(data_key: String, path := PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	return f != null and f.get_pascal_string() == data_key


## Puts the saved ground into `terrain` (loaded without its relief raised)
## and the bridge-end heights into `net`. False, changing nothing, if the
## file is missing, for other map data or the wrong size.
static func apply(terrain: Terrain, net: RoadNetwork, data_key: String, path := PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_pascal_string() != data_key:
		return false
	if int(f.get_32()) != terrain.nx or int(f.get_32()) != terrain.nz:
		return false
	var size := int(f.get_32())
	var heights := f.get_buffer(int(f.get_32())).decompress(size, FileAccess.COMPRESSION_ZSTD)
	var ends: Variant = bytes_to_var(f.get_buffer(int(f.get_32())))
	if heights.size() != terrain.nx * terrain.nz * 2 or not (ends is Dictionary):
		return false
	terrain.set_heights_bytes(heights)
	net.bridge_end_h = ends
	return true

class_name Ads
extends RefCounted
## Advertising artwork: window posters and billboards, one picture each in
## textures/ads/ (drawn by tools/make_ads.py), known by name, e.g.
## "tim_hardlys_bagel". A world brand lists the posters for its shop windows
## in data/map_config.json ("posters"); a billboard (a sign=billboard point
## from the map editor) shows one when its "ad" tag names it.

const DIR := "res://textures/ads/"

## ad -> WeakRef to its material: the posters and billboards using an ad
## hold it (their quad's material, a rotator's override), so when the last
## of them goes with its chunk the material and its picture are let go,
## instead of every ad seen on a drive staying in memory (some 20 MB).
static var _mats: Dictionary = {}
static var _mats_lock := Mutex.new()
## Pictures asked for on a worker (fetch) and not yet collected: path ->
## when asked (ms). A billboard whose chunk goes before its next turn never
## collects its fetch, and the loader would hold that picture for ever.
static var _pending: Dictionary = {}
## Collected anyway (and dropped, unless something's using it) this long
## after asking: a turn comes a couple of seconds after its fetch.
const PENDING_MS := 15000


## Whether there's artwork by this name.
static func has(ad: String) -> bool:
	return ad != "" and ResourceLoader.exists(DIR + ad + ".png")


## Starts loading an ad's picture on a worker (material() then finds it
## loaded instead of loading it there and then).
static func fetch(ad: String) -> void:
	var path := DIR + ad + ".png"
	_mats_lock.lock()
	_sweep()
	if not ResourceLoader.has_cached(path) and not _pending.has(path):
		if ResourceLoader.load_threaded_request(path) == OK:
			_pending[path] = Time.get_ticks_msec()
	_mats_lock.unlock()


## Collects the fetches nobody came for (see _pending). Under the lock.
static func _sweep() -> void:
	var now := Time.get_ticks_msec()
	for path: String in _pending.keys():
		if now - int(_pending[path]) < PENDING_MS:
			continue
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		ResourceLoader.load_threaded_get(path) # and let it go
		_pending.erase(path)


## How many ads have a material alive (for tests and the memory budget).
static func live_count() -> int:
	_mats_lock.lock()
	var n := 0
	for ad: String in _mats:
		if (_mats[ad] as WeakRef).get_ref() != null:
			n += 1
	_mats_lock.unlock()
	return n


## The shared material for an ad (printed paper or vinyl: a little sheen).
## Chunks are built on several threads at once, so the cache is locked.
## Hold on to it (a mesh's material, an override) while it's in use: the
## cache only knows of it while something does.
static func material(ad: String) -> StandardMaterial3D:
	_mats_lock.lock()
	var out: StandardMaterial3D = null
	if _mats.has(ad):
		out = (_mats[ad] as WeakRef).get_ref() as StandardMaterial3D
	if out == null:
		out = StandardMaterial3D.new()
		var path := DIR + ad + ".png"
		# Fetched ahead (fetch()): collected from the worker; else loaded now.
		var st := ResourceLoader.load_threaded_get_status(path)
		if _pending.has(path) and (st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_IN_PROGRESS):
			out.albedo_texture = ResourceLoader.load_threaded_get(path)
		else:
			out.albedo_texture = load(path)
		_pending.erase(path)
		out.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		out.roughness = 0.45
		_mats[ad] = weakref(out)
	_sweep()
	_mats_lock.unlock()
	return out


## A flat picture `size` metres across facing +Z, centred on its node.
static func panel(ad: String, size: Vector2) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.material = material(ad)
	var mi := MeshInstance3D.new()
	mi.name = "Ad_" + ad
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static var _families: Dictionary = {}
static var _families_lock := Mutex.new()


## The ads a billboard takes turns showing, starting with `ad`. `listed` is
## the billboard's "ads" tag, names split by "|", when it has one (the
## tourism board's say which jokes go round where). Otherwise a brand's
## board goes round all of that brand's billboards: every ad named like it
## up to "_bb_" (tim_hardlys_bb_large, tim_hardlys_bb_ready, ...).
static func rotation(ad: String, listed: String) -> PackedStringArray:
	var out := PackedStringArray()
	if listed != "":
		for a in listed.split("|", false):
			if has(a.strip_edges()):
				out.append(a.strip_edges())
		return out
	var cut := ad.find("_bb_")
	if cut < 0:
		return PackedStringArray([ad]) if has(ad) else out
	var prefix := ad.substr(0, cut + 4)
	_families_lock.lock()
	if not _families.has(prefix):
		var names := PackedStringArray()
		for f in ResourceLoader.list_directory(DIR):
			if f.begins_with(prefix) and f.ends_with(".png"):
				names.append(f.trim_suffix(".png"))
		names.sort()
		_families[prefix] = names
	var family: PackedStringArray = _families[prefix]
	_families_lock.unlock()
	var start := maxi(0, family.find(ad))
	for i in family.size():
		out.append(family[(start + i) % family.size()])
	return out


## A billboard face like panel(), that takes turns showing `ads`. `phase`
## (0 to 1) staggers boards so they don't all change at once.
static func rotating_panel(ads: PackedStringArray, size: Vector2, phase: float) -> MeshInstance3D:
	var mi := panel(ads[0], size)
	mi.set_script(AdRotator)
	mi.set("ads", ads)
	mi.set("phase", phase)
	return mi

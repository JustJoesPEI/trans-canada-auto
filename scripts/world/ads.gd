class_name Ads
extends RefCounted
## Advertising artwork: window posters and billboards, one picture each in
## textures/ads/ (drawn by tools/make_ads.py), known by name, e.g.
## "tim_hardlys_bagel". A world brand lists the posters for its shop windows
## in data/map_config.json ("posters"); a billboard (a sign=billboard point
## from the map editor) shows one when its "ad" tag names it.

const DIR := "res://textures/ads/"

static var _mats: Dictionary = {}
static var _mats_lock := Mutex.new()


## Whether there's artwork by this name.
static func has(ad: String) -> bool:
	return ad != "" and ResourceLoader.exists(DIR + ad + ".png")


## The shared material for an ad (printed paper or vinyl: a little sheen).
## Chunks are built on several threads at once, so the cache is locked.
static func material(ad: String) -> StandardMaterial3D:
	_mats_lock.lock()
	if not _mats.has(ad):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(DIR + ad + ".png")
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.roughness = 0.45
		_mats[ad] = m
	var out: StandardMaterial3D = _mats[ad]
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
	# Every ad in its turn loaded now, with the chunk (on a worker), not on
	# the main thread when its turn comes round.
	for ad in ads:
		material(ad)
	var mi := panel(ads[0], size)
	mi.set_script(AdRotator)
	mi.set("ads", ads)
	mi.set("phase", phase)
	return mi

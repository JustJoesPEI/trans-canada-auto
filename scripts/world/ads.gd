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

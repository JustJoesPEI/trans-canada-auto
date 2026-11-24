class_name LampGlow
extends RefCounted
## Brake and reversing lights that light up.
##
## As a builder draws a vehicle's tail lamps it notes each red and white
## lens (`note`); `build` turns those into a thin glowing overlay just in
## front of the lenses, one mesh for the brake lights and one for the
## reversing lights. The meshes are built once per model and cached with
## its other meshes, share one material each, and the vehicle only shows or
## hides them (Car._update_lamps), so lighting up costs one draw call while
## they're on and nothing while they're off.

const BRAKE := "brake"
const REVERSE := "reverse"

static var _materials := {}


## How a lens colour lights: "brake" for red, "reverse" for white, "" for
## anything else (amber, black trim).
static func kind_of(c: Color) -> String:
	if c.r > 0.45 and c.g < 0.2 and c.b < 0.2:
		return BRAKE
	if c.r > 0.85 and c.g > 0.85 and c.b > 0.8 and c.a > 0.9:
		return REVERSE
	return ""


## A lens to light: its outline (corners in order, a convex shape) and the
## way it faces.
static func note(log: Array, kind: String, outline: Array, n: Vector3) -> void:
	if kind == "":
		return
	log.append({"kind": kind, "pts": outline, "n": n})


## A flat rectangle facing ±z or ±x (w across, h up), as an outline.
static func rect(c: Vector3, w: float, h: float, n: Vector3) -> Array:
	var u := Vector3.RIGHT if absf(n.z) > 0.5 else Vector3.BACK
	var v := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
	if absf(n.y) > 0.5:
		u = Vector3.RIGHT
	return [c - u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 - v * h * 0.5, c + u * w * 0.5 + v * h * 0.5, c - u * w * 0.5 + v * h * 0.5]


## A round lens as an outline.
static func disc(c: Vector3, r: float, n: Vector3, segs := 10) -> Array:
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u).normalized()
	var out := []
	for i in segs:
		var a := TAU * i / segs
		out.append(c + (u * cos(a) + v * sin(a)) * r)
	return out


## The glowing overlay for one kind of lamp, or null if the model has none.
static func build(log: Array, kind: String) -> ArrayMesh:
	var kit := MeshKit.new()
	for e: Dictionary in log:
		if e["kind"] != kind:
			continue
		var n: Vector3 = e["n"]
		var pts: Array = e["pts"]
		# Just proud of the lens, so it draws over it without fighting.
		var lift := n * 0.004
		var a: Vector3 = pts[0] + lift
		for i in range(1, pts.size() - 1):
			var b: Vector3 = pts[i] + lift
			var c: Vector3 = pts[i + 1] + lift
			# Wound to face n.
			if (b - a).cross(c - a).dot(n) < 0.0:
				kit.tri(a, b, c, n)
			else:
				kit.tri(a, c, b, n)
	if kit.is_empty():
		return null
	return kit.commit_indexed(null, material(kind))


static func material(kind: String) -> Material:
	if not _materials.has(kind):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var c := Color(1.0, 0.1, 0.06) if kind == BRAKE else Color(1.0, 0.97, 0.9)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.5 if kind == BRAKE else 1.5
		_materials[kind] = m
	return _materials[kind]

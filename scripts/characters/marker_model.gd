class_name MarkerModel
extends RefCounted
## A paintball marker (the gun), held while aiming. Built once and shared by
## everyone holding one: one surface on a shared material, vertex colours,
## shared vertices and automatic LODs (docs/models.md).
##
## Its own space: the muzzle points along -Z, up is +Y, and the origin is
## where the right hand holds the grip. The left hand goes on the foregrip
## at FOREGRIP.

## Where the left hand holds it.
const FOREGRIP := Vector3(0.0, -0.01, -0.25)
## The mouth of the hopper, where a pod is poured in on a reload.
const HOPPER_TOP := Vector3(0.0, 0.212, -0.04)
## A paint pod's length (its own space: the open end at the origin, the
## tube along +Y, so held upright it hangs from the fingers).
const POD_LENGTH := 0.12
const POD := Color(0.82, 0.84, 0.86)

const BODY := Color(0.07, 0.07, 0.08)
const TRIM := Color(0.2, 0.21, 0.23)
const HOPPER := Color(0.95, 0.62, 0.08)
const TANK := Color(0.55, 0.57, 0.6)

static var _mesh: ArrayMesh
static var _scoped_mesh: ArrayMesh
static var _pod_mesh: ArrayMesh


## The marker; `scoped` adds a scope on rings over the barrel, ahead of the
## loader (the Farmhand's). Each is built once.
static func mesh(scoped := false) -> ArrayMesh:
	if scoped and _scoped_mesh != null:
		return _scoped_mesh
	if not scoped and _mesh != null:
		return _mesh
	var kit := MeshKit.new()
	kit.use_color = true
	# Body over the grip, the barrel out the front, the loader on top.
	TruckBuilder.box(kit, Vector3(0.0, 0.065, -0.06), Vector3(0.036, 0.06, 0.3), BODY)
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.07, -0.21), Vector3(0.0, 0.07, -0.52), 0.013, TRIM, 10)
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.07, -0.5), Vector3(0.0, 0.07, -0.535), 0.017, BODY, 10)
	TruckBuilder.cone(kit, Vector3(0.0, 0.1, -0.05), Vector3(0.0, 0.2, -0.04), 0.035, 0.05, HOPPER, 12)
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.2, -0.04), Vector3(0.0, 0.212, -0.04), 0.045, BODY, 12)
	# Grip, trigger guard and the foregrip.
	TruckBuilder.block(kit, [
		Vector3(-0.015, -0.08, 0.01), Vector3(0.015, -0.08, 0.01), Vector3(0.015, 0.04, -0.015), Vector3(-0.015, 0.04, -0.015),
		Vector3(-0.015, -0.08, 0.045), Vector3(0.015, -0.08, 0.045), Vector3(0.015, 0.04, 0.02), Vector3(-0.015, 0.04, 0.02),
	], BODY)
	TruckBuilder.box(kit, Vector3(0.0, 0.025, -0.045), Vector3(0.012, 0.012, 0.05), TRIM)
	TruckBuilder.box(kit, Vector3(0.0, 0.0, -0.25), Vector3(0.026, 0.07, 0.035), BODY)
	# Air tank back along the forearm to the shoulder, as a stock.
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.02, 0.05), Vector3(0.0, 0.02, 0.27), 0.03, TANK, 12)
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.02, 0.0), Vector3(0.0, 0.02, 0.05), 0.016, TRIM, 8)
	if scoped:
		# Two rings up off the body, the tube, and the wider lens bells.
		for z: float in [-0.14, -0.2]:
			TruckBuilder.box(kit, Vector3(0.0, 0.11, z), Vector3(0.014, 0.03, 0.014), TRIM)
		TruckBuilder.cylinder(kit, Vector3(0.0, 0.135, -0.11), Vector3(0.0, 0.135, -0.3), 0.016, BODY, 10)
		TruckBuilder.cone(kit, Vector3(0.0, 0.135, -0.3), Vector3(0.0, 0.135, -0.35), 0.016, 0.024, BODY, 10)
		TruckBuilder.cylinder(kit, Vector3(0.0, 0.135, -0.11), Vector3(0.0, 0.135, -0.095), 0.02, BODY, 10)
		_scoped_mesh = ModelLod.finish_kits([[kit, CarBuilder.material("satin")]])
		return _scoped_mesh
	_mesh = ModelLod.finish_kits([[kit, CarBuilder.material("satin")]])
	return _mesh


## A paint pod, the tube of balls a reload pours into the hopper: a clear
## grey tube with the paint showing through, and a lid. Same rules as the
## marker: built once, one surface, shared material, automatic LODs.
static func pod_mesh() -> ArrayMesh:
	if _pod_mesh != null:
		return _pod_mesh
	var kit := MeshKit.new()
	kit.use_color = true
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.0, 0.0), Vector3(0.0, POD_LENGTH, 0.0), 0.026, POD, 10)
	TruckBuilder.cylinder(kit, Vector3(0.0, 0.015, 0.0), Vector3(0.0, POD_LENGTH - 0.01, 0.0), 0.0265, HOPPER, 10)
	TruckBuilder.cylinder(kit, Vector3(0.0, -0.008, 0.0), Vector3(0.0, 0.0, 0.0), 0.029, BODY, 10)
	_pod_mesh = ModelLod.finish_kits([[kit, CarBuilder.material("satin")]])
	return _pod_mesh

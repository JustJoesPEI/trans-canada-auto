class_name HandProps
extends RefCounted
## Small things people hold while they work (HumanoidModel.task): an
## officer's notebook and pen, a phone, a paramedic's rinse bottle, a
## firefighter's hose nozzle. Same rules as the marker (docs/models.md):
## each built once and shared, one surface on a shared material, vertex
## colours, shared vertices and automatic LODs.
##
## Each one's own space: held at the origin (where the palm closes), the
## business end along -Z (the bottle's and the nozzle's spray, the top of
## the notebook and the phone), the face up along +Y.

## Where the spray comes out, in the prop's own space.
const BOTTLE_TIP := Vector3(0.0, 0.09, -0.06)
const NOZZLE_TIP := Vector3(0.0, 0.0, -0.31)
## Where the left hand goes on the nozzle (the bale), and the hose's
## coupling at the back.
const NOZZLE_BALE := Vector3(0.0, 0.0, -0.2)
const NOZZLE_BACK := Vector3(0.0, 0.0, 0.06)

const PAPER := Color(0.93, 0.92, 0.86)
const COVER := Color(0.08, 0.09, 0.14)
const BLACK := Color(0.05, 0.05, 0.06)
const SCREEN := Color(0.22, 0.36, 0.52)
const BOTTLE := Color(0.78, 0.86, 0.92)
const TRIGGER := Color(0.12, 0.55, 0.3)
const BRASS := Color(0.74, 0.58, 0.24)
const RED := Color(0.62, 0.08, 0.06)

static var _meshes := {}


## The prop called `name` ("notepad", "pen", "phone", "bottle", "nozzle").
static func mesh(name: String) -> ArrayMesh:
	if _meshes.has(name):
		return _meshes[name]
	var kit := MeshKit.new()
	kit.use_color = true
	match name:
		"notepad":
			# A flip-top notebook: the black cover folded back under the
			# pad, the pages, and the wire across the top.
			TruckBuilder.box(kit, Vector3(0.0, -0.004, 0.0), Vector3(0.085, 0.006, 0.13), COVER)
			TruckBuilder.box(kit, Vector3(0.0, 0.002, 0.004), Vector3(0.08, 0.008, 0.12), PAPER)
			TruckBuilder.cylinder(kit, Vector3(-0.04, 0.004, -0.062), Vector3(0.04, 0.004, -0.062), 0.005, BLACK, 6)
		"pen":
			TruckBuilder.cone(kit, Vector3(0.0, 0.0, 0.07), Vector3(0.0, 0.0, -0.06), 0.005, 0.004, BLACK, 6)
			TruckBuilder.cone(kit, Vector3(0.0, 0.0, -0.06), Vector3(0.0, 0.0, -0.075), 0.004, 0.001, PAPER, 6)
		"phone":
			TruckBuilder.box(kit, Vector3(0.0, 0.0, 0.0), Vector3(0.07, 0.009, 0.145), BLACK)
			# The screen: a flat quad just off the face.
			kit.color = SCREEN
			kit.quad(Vector3(-0.031, 0.0047, 0.066), Vector3(0.031, 0.0047, 0.066), Vector3(0.031, 0.0047, -0.066), Vector3(-0.031, 0.0047, -0.066), Vector3.UP)
		"bottle":
			# A trigger sprayer: the bottle hangs below the hand, the head
			# and nozzle over the fingers.
			TruckBuilder.cylinder(kit, Vector3(0.0, -0.17, 0.02), Vector3(0.0, -0.01, 0.02), 0.035, BOTTLE, 10)
			TruckBuilder.cone(kit, Vector3(0.0, -0.01, 0.02), Vector3(0.0, 0.03, 0.02), 0.035, 0.015, BOTTLE, 10)
			TruckBuilder.box(kit, Vector3(0.0, 0.07, -0.01), Vector3(0.03, 0.05, 0.1), TRIGGER)
			TruckBuilder.box(kit, Vector3(0.0, 0.03, -0.04), Vector3(0.012, 0.05, 0.012), TRIGGER)
			TruckBuilder.cylinder(kit, Vector3(0.0, 0.09, -0.05), BOTTLE_TIP, 0.008, BLACK, 6)
		"nozzle":
			# A combination nozzle: the coupling, the barrel, the bale
			# handle on top, the pistol grip below and the bumper at the
			# tip.
			TruckBuilder.cylinder(kit, NOZZLE_BACK, Vector3(0.0, 0.0, -0.04), 0.038, BRASS, 10)
			TruckBuilder.cone(kit, Vector3(0.0, 0.0, -0.04), Vector3(0.0, 0.0, -0.27), 0.03, 0.026, BLACK, 10)
			TruckBuilder.cylinder(kit, Vector3(0.0, 0.0, -0.27), NOZZLE_TIP, 0.042, RED, 12)
			TruckBuilder.box(kit, Vector3(0.0, 0.05, -0.16), Vector3(0.018, 0.016, 0.14), BRASS)
			TruckBuilder.box(kit, Vector3(0.0, -0.07, -0.03), Vector3(0.028, 0.1, 0.035), BLACK)
	_meshes[name] = ModelLod.finish_kits([[kit, CarBuilder.material("satin")]])
	return _meshes[name]


## Every prop, for tools/model_budget.gd.
static func budget_meshes() -> Dictionary:
	var out := {}
	for n: String in ["notepad", "pen", "phone", "bottle", "nozzle"]:
		out[n] = mesh(n)
	return out

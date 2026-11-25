class_name PoliceRoadblock
extends Node3D
## A roadblock a few junctions ahead of the player (docs/design.md section
## 7, level 3): two police vehicles across the street, lights on, officers
## out behind them. There's always a way round: the cars leave the
## sidewalk on one side (and often a lane) open, and the cars are real
## bodies that a heavy enough push will move. At level 4 some are the
## harvester kind: a potato harvester across the road with an SUV either
## side ("Very PEI"); you go round, through a yard, or back.
##
## Its origin is the middle of the street, -Z along the street toward the
## player (the way they'll come from).

var dispatcher: PoliceDispatcher
var units: Array[PoliceUnit] = []
var kind := "cars"
var harvester: StaticBody3D = null
## When it was set up (dispatcher clock).
var made_at := 0.0


## Sets one up at `at` (street middle) on a street running along `dir`
## (toward the player), `half_width` m from the middle to each curb.
static func build(d: PoliceDispatcher, parent: Node, at: Vector3, dir: Vector2, half_width: float, which: String, force: String) -> PoliceRoadblock:
	var rb := PoliceRoadblock.new()
	rb.dispatcher = d
	rb.kind = which
	rb.name = "Roadblock"
	parent.add_child(rb)
	rb.global_transform = Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.y)), at)
	rb.made_at = d.clock
	var across := rb.global_basis.x
	var along := -rb.global_basis.z
	var yaw := atan2(-dir.x, -dir.y)
	if which == "harvester":
		rb._place_harvester(at, yaw)
		# An SUV at each end of it, nose out, along the curbs.
		for s: float in [-1.0, 1.0]:
			var p := at + across * s * (PoliceProps.HARVESTER_SIZE.z * 0.5 + 1.6) + along * 1.5
			rb._add_unit(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5 * s), p + Vector3.UP * 0.4), force)
	else:
		# Two cars nose to tail across the street from the left curb,
		# angled a little, leaving the right side's sidewalk (and a lane on
		# a wide street) as the way round.
		var left := -half_width + 1.3
		for i in 2:
			var x := left + 1.2 + i * 2.6
			var p := at + across * x + along * (i * 0.8)
			rb._add_unit(Transform3D(Basis(Vector3.UP, yaw + PI * 0.5 + (0.25 if i == 0 else -0.25)), p + Vector3.UP * 0.4), force)
	return rb


func _add_unit(xf: Transform3D, force: String) -> void:
	var u := dispatcher.new_unit(force)
	u.roadblock = self
	u.order(PoliceUnit.Role.ROADBLOCK, xf.origin, dispatcher.clock)
	u.place_physical(xf, dispatcher.world_root)
	units.append(u)


func _place_harvester(at: Vector3, yaw: float) -> void:
	harvester = StaticBody3D.new()
	harvester.name = "Harvester"
	harvester.collision_layer = Layers.SOLID
	harvester.collision_mask = 0
	add_child(harvester)
	# Across the street: its length along the road's across.
	harvester.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), at)
	var mi := MeshInstance3D.new()
	mi.mesh = PoliceProps.harvester_mesh()
	WorldLod.limit(mi, PoliceProps.HARVESTER_SIZE.z)
	harvester.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PoliceProps.HARVESTER_SIZE.x * 0.85, 2.2, PoliceProps.HARVESTER_SIZE.z * 0.8)
	cs.shape = box
	cs.position = Vector3(0, 1.4, 0.3)
	harvester.add_child(cs)
	for s: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "RED CLAY SPUD CO."
		PoliceGear._style(l, 0.22, Color(0.97, 0.95, 0.9))
		l.position = Vector3(s * (PoliceProps.HARVESTER_SIZE.x * 0.41 + 0.02), 1.25, 0.4)
		l.rotation.y = s * PI * 0.5
		WorldLod.limit(l, 0.6)
		harvester.add_child(l)


## Takes it all away.
func clear() -> void:
	for u in units:
		if is_instance_valid(u):
			dispatcher.drop_unit(u)
	units.clear()
	queue_free()

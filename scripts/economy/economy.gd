class_name Economy
extends Node
## Money in the town (docs/design.md section 6½, "Money: jobs, stores and
## property"): one node, a child of Main, holding the shared pieces every
## money feature builds on, and the features themselves as modules.
##
##   Economy.find(tree)
##   owned_cars   OwnedCars: the vehicles you own, kept between sessions
##   counters     Counters: places to buy things or pick up work
##   jobs         Jobs: the job under way, and where jobs come from
##   addresses    Addresses: real street addresses to deliver to
##   world, main, player, hud
##
## A feature (SpudDash, Delayed & Lost, the stores, the custom shop,
## property...) is a script in scripts/economy/ with
##     extends Node
##     func setup(economy: Economy) -> void
## listed in MODULES: it's made, added as a child of this node and set up
## once the town is built, after the shared pieces. It registers its
## counters, job sources and map tabs there, and keeps to its own files.

## The feature modules, in the order they're set up.
const MODULES: Array[String] = [
	"res://scripts/economy/custom_shop.gd",
	"res://scripts/economy/used_lot.gd",
]

var world: WorldBuilder
var main: Node
var player: Node3D
var hud: Node
var owned_cars: OwnedCars
var counters: Counters
var jobs: Jobs
var addresses: Addresses


static func find(tree: SceneTree) -> Economy:
	return tree.get_first_node_in_group("economy") as Economy if tree != null else null


func _ready() -> void:
	add_to_group("economy")


func setup(w: WorldBuilder, m: Node, p: Node3D, h: Node) -> void:
	world = w
	main = m
	player = p
	hud = h
	addresses = Addresses.load_for(w)
	owned_cars = OwnedCars.new()
	owned_cars.name = "OwnedCars"
	add_child(owned_cars)
	owned_cars.setup(m, p)
	counters = Counters.new()
	counters.name = "Counters"
	add_child(counters)
	counters.setup(p, h)
	jobs = Jobs.new()
	jobs.name = "Jobs"
	add_child(jobs)
	jobs.setup(p, h)
	_add_jobs_tab()
	for path in MODULES:
		var script := load(path) as Script
		if script == null:
			push_warning("Economy: can't load module %s" % path)
			continue
		var mod: Node = script.new()
		mod.name = path.get_file().get_basename().to_pascal_case()
		add_child(mod)
		if mod.has_method("setup"):
			mod.call("setup", self)


## The map's Jobs tab: the job under way (with Cancel), and how many of each
## kind you've done.
func _add_jobs_tab() -> void:
	var map := WorldMap.find(get_tree())
	if map == null:
		return
	map.add_tab("jobs", "Jobs", func(box: VBoxContainer) -> void:
		var head := HudStyle.label(22, true, Color.WHITE, false)
		box.add_child(head)
		if jobs.active.is_empty():
			head.text = "No job under way"
			var how := HudStyle.label(15, false, HudStyle.DIM, false)
			how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			how.text = "Pick one up at a job board, or on your phone."
			box.add_child(how)
		else:
			var job := jobs.active
			head.text = str(job.get("title", "Job"))
			head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var info := HudStyle.label(15, false, HudStyle.DIM, false)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var s := jobs.stop()
			info.text = "%s\nNext: %s %s\nPays %s if you finish now" % [str(job.get("company", "")), str(s.get("name", "")), str(s.get("address", "")), CarModels.dollars(int(jobs.pay_now().get("pay", 0)))]
			box.add_child(info)
			box.add_child(map.make_button("Cancel the job", func() -> void:
				jobs.cancel()
				map.refresh_tab()))
		var done: Dictionary = get_tree().root.get_node("GameState").get("jobs_done")
		if not done.is_empty():
			var tally := HudStyle.label(15, false, HudStyle.DIM, false)
			var parts: Array[String] = []
			for k: String in done:
				parts.append("%s %d" % [k, int(done[k])])
			tally.text = "Done so far: " + ", ".join(parts)
			tally.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(tally))

extends SceneTree
## Checks how much graphics memory the whole game takes, against the budget
## for laptops whose graphics share the computer's memory (integrated AMD
## and Intel chips, often with a fixed 512 MB slice of it, which Windows'
## own desktop also draws from). Going over that slice doesn't slow the
## game down, it crashes it (VkResult -10, then "device lost"), so this is
## a hard limit, like the drawing-cost budgets (docs/world_art.md).
##
## It needs a real renderer (the headless one has no graphics memory), and
## the graphics level given on the command line (so it never reads or
## changes the player's saved one). On a desktop:
##
##   godot --rendering-driver vulkan --resolution 1920x1080 --path . \
##       --script res://tools/memory_budget.gd -- --graphics=low
##
## In a cloud container, drawing in software (a few minutes):
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##       godot --rendering-driver vulkan --resolution 1920x1080 --path . \
##       --script res://tools/memory_budget.gd -- --graphics=low
##
## Loads the game, starts it at the spawn, waits for every chunk in range,
## then moves to a couple of other spots in town and does the same. Watches
## the memory every frame and prints one "MEMORY" line per spot (total,
## textures, meshes and other buffers; "other" is mostly room the allocator
## has reserved but not filled) and the peak. On Low it fails ("MEMORY
## FAIL", non-zero exit) if the peak is over BUDGET_MB; on Medium and High
## it only reports. Numbers from the software renderer are close to a real
## card's but not the same: compare runs on the same machine.
##
## tools/world_budget.gd checks each chunk's own share of the meshes
## (mesh_kb), which is what grows as the town streams in.

## Peak graphics memory on Low at 1920x1080 (MB). When this came in (Nov
## 2026, software renderer): 291-305 MB settled at each spot, peaking at
## 330 MB while the town streamed in round the spawn (new chunks arrive
## before the old ones go). The budget stops it growing; the aim is to get
## well under it, since a 512 MB chip has maybe 300 MB left once Windows'
## desktop and a browser have had theirs.
const BUDGET_MB := 350.0

## Spots to visit after the spawn: [name, x, z] (game metres).
const SPOTS := [
	["east", 600.0, 400.0],
	["north", -300.0, -1700.0],
]

var _peak := 0.0
var _peak_at := ""
var _where := "loading"
var _level := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with("--graphics="):
			_level = a.trim_prefix("--graphics=")
	if _level == "":
		printerr("MEMORY give the graphics level to check: -- --graphics=low (or medium, high)")
		quit(2)
		return
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		printerr("MEMORY needs a real renderer (see the top of tools/memory_budget.gd); the headless one has no graphics memory")
		quit(2)
		return
	process_frame.connect(_sample)
	_run.call_deferred()


func _mb(monitor: int) -> float:
	return Performance.get_monitor(monitor) / 1048576.0


func _sample() -> void:
	var total := _mb(Performance.RENDER_VIDEO_MEM_USED)
	if total > _peak:
		_peak = total
		_peak_at = _where


func _report(label: String) -> void:
	var total := _mb(Performance.RENDER_VIDEO_MEM_USED)
	var tex := _mb(Performance.RENDER_TEXTURE_MEM_USED)
	var buf := _mb(Performance.RENDER_BUFFER_MEM_USED)
	print("MEMORY %-8s total=%.0f MB  textures=%.0f  meshes and buffers=%.0f  other=%.0f" % [label, total, tex, buf, total - tex - buf])


func _run() -> void:
	var size := root.get_visible_rect().size
	if Vector2i(size) != Vector2i(1920, 1080):
		print("MEMORY note: the window is %dx%d; the budget is for 1920x1080 (--resolution 1920x1080)" % [size.x, size.y])
	for i in 3:
		await process_frame
	_report("empty")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var world: Node = main.get_node("World")
	if not world.is_built:
		await world.built
	var menu := root.get_node_or_null("TitleMenu")
	if menu != null:
		await process_frame
		menu.call("_resume")
	_where = "spawn"
	await _settle(world)
	_report("spawn")
	var player: Node3D = main.get_node("Player")
	for s: Array in SPOTS:
		_where = str(s[0])
		player.global_position = world.terrain.at(Vector2(s[1], s[2]), 0.5)
		await _settle(world)
		_report(_where)
	var level_name := _level.to_lower()
	print("MEMORY peak=%.0f MB (at %s) on %s at %dx%d" % [_peak, _peak_at, level_name, size.x, size.y])
	if level_name == "low" and _peak > BUDGET_MB:
		print("MEMORY FAIL peak %.0f MB over the Low budget of %.0f MB (tools/memory_budget.gd)" % [_peak, BUDGET_MB])
		quit(1)
	elif level_name == "low":
		print("MEMORY within the Low budget of %.0f MB" % BUDGET_MB)
		quit(0)
	else:
		print("MEMORY (only Low has a budget)")
		quit(0)


## Wait until every chunk in range round the focus is in, and a few frames
## more for the streamed meshes to reach the graphics card.
func _settle(world: Node) -> void:
	for i in 10:
		await process_frame
	if world.has_method("wait_until_settled"):
		await world.wait_until_settled()
	for i in 10:
		await process_frame

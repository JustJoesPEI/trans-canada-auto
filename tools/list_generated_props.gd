extends SceneTree
## Lists where the game puts its own street furniture (hydrants, heritage
## lamps, street lights and parked cars, which it places along the streets
## itself rather than reading from the map data) into
## data/city/generated_props.json, so the map editor can show them and you
## can erase the ones in the wrong place. Run it again after big street
## edits, since the spots follow the streets:
##
##   godot --path . --script res://tools/list_generated_props.gd
##
## Not --headless: without a renderer Godot doesn't keep the MultiMesh
## positions this reads. It builds every chunk in full detail (a minute or
## two) and quits by itself.

const OUT := "res://data/city/generated_props.json"
const KINDS := {"HydrantMeshes": "hydrant", "Lamps": "heritage_lamp", "StreetLights": "street_light"}


func _init() -> void:
	var data := StreetData.load_from("res://data/map_config.json")
	var net := RoadNetwork.new(data)
	var terrain := Terrain.load_from(str(data.config.get("elevation", "res://data/elevation.json")))
	StreetProps.prepare()
	var out := {"hydrant": [], "heritage_lamp": [], "street_light": [], "parked_car": []}
	var keys: Array = data.chunk_keys.keys()
	keys.sort()
	var done := 0
	for key: String in keys:
		var xz := key.split("_")
		var node := ChunkBuilder.build(data, net, terrain, int(xz[0]), int(xz[1]), false)
		for mmi: Node in node.find_children("*", "MultiMeshInstance3D", true, false):
			var label := str(mmi.get_meta("label", mmi.name))
			var kind := str(KINDS.get(label, "parked_car" if label.begins_with("Parked_") else ""))
			if kind == "":
				continue
			var mm: MultiMesh = (mmi as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var o := mm.get_instance_transform(i).origin
				out[kind].append([snappedf(o.x, 0.1), snappedf(o.z, 0.1)])
		node.free()
		done += 1
		if done % 50 == 0:
			print("%d of %d chunks" % [done, keys.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"_comment": "Where the game places its own hydrants, lamps, street lights and parked cars, for the map editor. Made by tools/list_generated_props.gd; the game doesn't read it.",
		"props": out}))
	f.close()
	for k: String in out:
		print("%s: %d" % [k, (out[k] as Array).size()])
	quit()

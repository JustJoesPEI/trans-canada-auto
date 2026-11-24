extends SceneTree
## Screenshots of the character creator without starting the game: as it
## opens, and again after changing the outfit (varsity jacket, cap, joggers)
## with the preview walking. Writes creator1.png and creator2.png to <dir>.
##   godot --path . --resolution 1280x720 -s tools/char_preview/creator_shot.gd -- <dir>
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var c := CharacterCreator.new()
	layer.add_child(c)
	c.open(PlayerLook.default_look())
	for f in 8: await process_frame
	root.get_texture().get_image().save_png(out + "/creator1.png")
	# Change things the way the buttons do.
	var o: Dictionary = c.look["outfit"]
	o["top"]["kind"] = "varsity"; o["top"]["color"] = PlayerLook.CLOTHS[7]; o["top"]["trim"] = PlayerLook.CLOTHS[0]
	o["top"]["print"] = "varsity_s"; o["top"]["back"] = "spud_kings"
	o["hat"]["kind"] = "cap"; o["hat"]["print"] = "red_mud"; o["hat"]["color"] = PlayerLook.CLOTHS[4]
	o["bottom"]["kind"] = "joggers"; o["bottom"]["color"] = PlayerLook.CLOTHS[3]
	c.look["skin"] = PlayerLook.SKINS[6]; c.look["height"] = 1.9
	c._frame_camera()
	c._changed(true)
	c._toggle_walk()
	c._scroll.scroll_vertical = 520
	for f in 8: await process_frame
	root.get_texture().get_image().save_png(out + "/creator2.png")
	quit()

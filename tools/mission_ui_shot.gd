extends SceneTree
## Screenshots of the missions' screens without loading the town: the title
## card mid-way, the notepad with some moves crossed out and the meter, the
## caption bar, and the road test sheet. Over a plain concrete-grey
## background. Saves to /tmp/tca-shots/mission_*.png.
##
##   VK_ICD_FILENAMES=/opt/lavapipe/lvp_icd.json xvfb-run -a -s "-screen 0 1920x1080x24" \
##       godot --rendering-driver vulkan --resolution 1920x1080 --path . --script res://tools/mission_ui_shot.gd

var _layer: CanvasLayer
var _frame := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/tca-shots")
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.42, 0.41)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	# A stand-in for the parkade: a deck, a far wall, a column or two.
	var deck := ColorRect.new()
	deck.color = Color(0.3, 0.3, 0.3)
	deck.position = Vector2(0, 560)
	deck.size = Vector2(1920, 520)
	bg.add_child(deck)
	for x: float in [300.0, 980.0, 1600.0]:
		var c := ColorRect.new()
		c.color = Color(0.55, 0.55, 0.52)
		c.position = Vector2(x, 120)
		c.size = Vector2(70, 460)
		bg.add_child(c)
	_layer = CanvasLayer.new()
	root.add_child(_layer)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			# The title menu's loading screen would cover everything.
			var menu := root.get_node_or_null("TitleMenu")
			if menu != null:
				menu.queue_free()
		2:
			var card := TitleCard.new()
			card.name = "Card"
			_layer.add_child(card)
			card.show_card("garage", GarageLines.TITLE, GarageLines.TITLE_SUB, GarageLines.TITLE_CREDIT)
		70:
			_shot("mission_title")
		75:
			_layer.get_node("Card").queue_free()
			var pad := Notepad.new()
			pad.name = "Pad"
			_layer.add_child(pad)
			pad.head = GarageLines.PAD_HEAD
			pad.sub = GarageLines.PAD_SUB
			pad.set_list(GarageLines.LIST)
			pad.slap_in()
			var meter := MeterDisplay.new()
			meter.name = "Meter"
			_layer.add_child(meter)
			meter.visible = true
			meter.seconds = 37.4
			var cap := CaptionBar.new()
			cap.name = "Cap"
			_layer.add_child(cap)
		80:
			var pad: Notepad = _layer.get_node("Pad")
			pad.cross_out("burnout")
			pad.cross_out("handbrake")
			pad.cross_out("three_sixty")
			(_layer.get_node("Cap") as CaptionBar).mumble(GarageLines.NAME, GarageLines.MUMBLES[1], 30.0)
		110:
			(_layer.get_node("Pad") as Notepad).cross_out("speed")
			(_layer.get_node("Pad") as Notepad).write_extra(GarageLines.PAD_ROOF)
		170:
			_shot("mission_notepad")
		175:
			(_layer.get_node("Cap") as CaptionBar).say(GarageLines.NAME, GarageLines.INTRO[2])
		230:
			_shot("mission_caption")
		235:
			for n: String in ["Pad", "Meter", "Cap"]:
				_layer.get_node(n).queue_free()
			var sheet := ScoreSheet.new()
			sheet.name = "Sheet"
			_layer.add_child(sheet)
			var rows: Array = []
			for i in GarageLines.LIST.size():
				var it: Array = GarageLines.LIST[i]
				rows.append([str(it[1]), i != 4])
			sheet.show_sheet({"rows": rows, "passed": false, "stamp": GarageLines.FAILED,
				"lines": ["Vehicle: Filly (beige)", "Meter: 0:00, expired", "Signalled: never"],
				"remarks": [GarageLines.hit_remark(1), GarageLines.verdict(false, "", false)], "money": "Ticket: -$25"})
		320:
			_shot("mission_sheet")
		322:
			return true
	return false


func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("/tmp/tca-shots/%s.png" % name)
	print("saved /tmp/tca-shots/%s.png" % name)

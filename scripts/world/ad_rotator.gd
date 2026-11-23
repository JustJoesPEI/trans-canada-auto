class_name AdRotator
extends MeshInstance3D
## A billboard face that takes turns showing its ads, a new one every
## PERIOD seconds, the way the boards out by the highway do. Made by
## Ads.rotating_panel.

const PERIOD := 10.0

var ads: PackedStringArray = []
## Where in the turn this board starts (0 to 1), so neighbours differ.
var phase := 0.0
var _shown := -1


func _process(_delta: float) -> void:
	if ads.size() < 2:
		return
	var turn := int(floor(Time.get_ticks_msec() / 1000.0 / PERIOD + phase * ads.size())) % ads.size()
	if turn != _shown:
		_shown = turn
		material_override = Ads.material(ads[turn])

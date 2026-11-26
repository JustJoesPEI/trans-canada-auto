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
	var at := Time.get_ticks_msec() / 1000.0 / PERIOD + phase * ads.size()
	var turn := int(floor(at)) % ads.size()
	# The next ad's picture fetched on a worker a couple of seconds before
	# its turn, so the turn doesn't load it on the main thread (and only the
	# next one: they're not all held at once).
	if fmod(at, 1.0) > 0.75:
		var next := (turn + 1) % ads.size()
		if next != _fetching:
			_fetching = next
			Ads.fetch(ads[next])
	if turn != _shown:
		_shown = turn
		material_override = Ads.material(ads[turn])


var _fetching := -1

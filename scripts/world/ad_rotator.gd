class_name AdRotator
extends MeshInstance3D
## A billboard face that takes turns showing its ads, a new one every
## PERIOD seconds, the way the boards out by the highway do. Made by
## Ads.rotating_panel.
##
## One board (`_ticker`) does the per-frame work for them all, and each
## board only does anything at its next change (`_next`: fetching the next
## picture, or turning to it), not a callback a frame for each.

const PERIOD := 10.0

var ads: PackedStringArray = []
## Where in the turn this board starts (0 to 1), so neighbours differ.
var phase := 0.0
var _shown := -1
var _fetching := -1
## When (s, Time.get_ticks_msec) this board next has something to do.
var _next := 0.0

static var _all: Array[AdRotator] = []
static var _ticker: AdRotator = null


func _enter_tree() -> void:
	_all.append(self)
	_next = 0.0 # look straight away
	if is_node_ready():
		_pick_ticker()


func _ready() -> void:
	_pick_ticker()


func _exit_tree() -> void:
	_all.erase(self)
	if _ticker == self:
		_ticker = null
		set_process(false)
		for b: AdRotator in _all:
			if b.is_node_ready():
				b._pick_ticker()
				break


func _pick_ticker() -> void:
	if _ticker == null or not is_instance_valid(_ticker) or not _ticker.is_inside_tree():
		_ticker = self
	set_process(_ticker == self)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for b: AdRotator in _all:
		if now >= b._next:
			b._turn(now)


func _turn(now: float) -> void:
	if ads.size() < 2:
		_next = now + 1.0
		return
	var n := ads.size()
	var at := now / PERIOD + phase * n
	var turn := int(floor(at)) % n
	var frac := fmod(at, 1.0)
	# The next ad's picture fetched on a worker a couple of seconds before
	# its turn, so the turn doesn't load it on the main thread (and only the
	# next one: they're not all held at once).
	if frac > 0.75:
		var next := (turn + 1) % n
		if next != _fetching:
			_fetching = next
			Ads.fetch(ads[next])
	if turn != _shown:
		_shown = turn
		material_override = Ads.material(ads[turn])
	# Next: the fetch at three quarters of the way through the turn, or the
	# turn itself.
	var due: float = floorf(at) + (0.75 if frac <= 0.75 else 1.0)
	_next = (due - phase * n) * PERIOD + 0.001

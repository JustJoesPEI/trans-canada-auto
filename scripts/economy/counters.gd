class_name Counters
extends Node
## Every place you can buy something or pick up work (docs/design.md
## section 6½): a spot in the town, and a short list on a card when you
## press the interact key there. No interiors and no new screens: Ervin's
## till, a Maple Tire counter, the Delayed & Lost dispatch window, a
## drive-thru speaker are all one of these.
##
##   Counters.find(tree)          the one in the game (Economy's)
##   add(spec) -> id              a counter; spec:
##     id        unique ("ervins_3"); a new add with the same id replaces it
##     title     on the prompt and the card ("Ervin's")
##     subtitle  a line under the title on the card (optional)
##     at        Vector3, where to stand (or stop the car)
##     reach     m from `at` that counts (default 3)
##     on_foot   usable on foot (default true)
##     in_car    usable from a car: a drive-thru (default false)
##     kind      map icon kind (WorldMap.KINDS), "" for none
##     map_name  the name on the map (default title)
##     items     Callable() -> Array of items, built each time the card
##               opens or after a purchase, so it can show what's left
##     prompt    the prompt's text (default title)
##   remove(id)
##   open_card(id)                 open a counter's card from code
##
## An item: {id, name, note (a line under it), price (int, 0 for free),
## enabled (default true), why (shown instead of the price when not),
## action: Callable(item) -> String}. Choosing an enabled item pays the
## price (refused if you're short) and calls `action`, whose return is
## shown on the card ("" for nothing). The card stays open to buy more.

signal bought(counter_id: String, item_id: String)

var player: Node3D
var hud: Node
var _counters := {} ## id -> spec
var _near := "" ## the counter you're at
var menu: CounterMenu


static func find(tree: SceneTree) -> Counters:
	return tree.get_first_node_in_group("counters") as Counters if tree != null else null


func _ready() -> void:
	add_to_group("counters")
	menu = CounterMenu.new()
	menu.name = "CounterMenu"
	menu.chosen.connect(_on_chosen)
	add_child(menu)


func setup(who: Node3D, h: Node) -> void:
	player = who
	hud = h


func add(spec: Dictionary) -> String:
	var s := spec.duplicate()
	s["id"] = str(spec.get("id", "counter_%d" % _counters.size()))
	s["title"] = str(spec.get("title", "Counter"))
	s["reach"] = float(spec.get("reach", 3.0))
	s["on_foot"] = bool(spec.get("on_foot", true))
	s["in_car"] = bool(spec.get("in_car", false))
	s["kind"] = str(spec.get("kind", ""))
	_counters[s["id"]] = s
	return s["id"]


func remove(id: String) -> void:
	_counters.erase(id)
	if _near == id:
		_near = ""
	if menu.counter_id == id:
		menu.close()


func has(id: String) -> bool:
	return _counters.has(id)


func spec(id: String) -> Dictionary:
	return _counters.get(id, {})


## The counter the player can use now ("" for none).
func near() -> String:
	return _near


## Counters with a map icon, for WorldMap: {name, kind, at: Vector2}.
func map_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _counters:
		var s: Dictionary = _counters[id]
		if str(s["kind"]) == "":
			continue
		var at: Vector3 = s["at"]
		out.append({"name": str(s.get("map_name", s["title"])), "kind": str(s["kind"]), "at": Vector2(at.x, at.z), "game": true})
	return out


func _process(_delta: float) -> void:
	_near = ""
	if player == null or not is_instance_valid(player) or menu.visible:
		return
	var in_car: Variant = player.get("vehicle")
	var p := player.global_position
	var best := INF
	for id: String in _counters:
		var s: Dictionary = _counters[id]
		if (in_car != null and not bool(s["in_car"])) or (in_car == null and not bool(s["on_foot"])):
			continue
		var d := p.distance_to(s["at"])
		if d < float(s["reach"]) and d < best:
			best = d
			_near = id
	if _near != "" and hud != null and hud.has_method("set_prompt"):
		var s: Dictionary = _counters[_near]
		hud.call("set_prompt", hud.call("key_for", "interact"), str(s.get("prompt", s["title"])))


func _unhandled_input(event: InputEvent) -> void:
	if _near != "" and not menu.visible and event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		open_card(_near)


func open_card(id: String) -> void:
	if not _counters.has(id):
		return
	var s: Dictionary = _counters[id]
	menu.open(id, str(s["title"]), str(s.get("subtitle", "")), _items(id), player)


func _items(id: String) -> Array:
	var s: Dictionary = _counters.get(id, {})
	var c: Variant = s.get("items")
	if c is Callable and (c as Callable).is_valid():
		var got: Variant = (c as Callable).call()
		return got if got is Array else []
	return []


func _on_chosen(counter_id: String, item: Dictionary) -> void:
	if not bool(item.get("enabled", true)):
		menu.say(str(item.get("why", "Not now.")))
		return
	var price := int(item.get("price", 0))
	var gs := get_tree().root.get_node("GameState")
	if price > 0 and not bool(gs.call("spend_money", price)):
		menu.say("Not enough money: that's %s, you have %s." % [CarModels.dollars(price), CarModels.dollars(int(gs.get("money")))])
		return
	var msg := ""
	var act: Variant = item.get("action")
	if act is Callable and (act as Callable).is_valid():
		var r: Variant = (act as Callable).call(item)
		msg = str(r) if r != null else ""
	bought.emit(counter_id, str(item.get("id", "")))
	if not menu.visible:
		return # the action closed it (a job started, say)
	menu.set_items(_items(counter_id))
	if msg != "":
		menu.say(msg)

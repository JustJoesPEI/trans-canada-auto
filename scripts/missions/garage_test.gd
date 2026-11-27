class_name GarageTest
extends Node
## The Garage: Tenner's driving test on the ground floor of the Queen
## Parkade (the one with the stunt ramp on the roof). A homage to the first
## mission of a 1999 car chase game: a parking garage, sixty seconds, a
## list of stunts, and a generation of kids who never got past it. The
## words are GarageLines'.
##
## How it goes:
##   * Tenner stands by his brown Charlatan, backed into the last stall by
##     the way in, with his lines over his head while you're near, a
##     sandwich board out front, an icon on the map and a post on Kinbook.
##     Nothing rings your phone.
##   * Talk to him in a car (his counter card) and he tells you about it
##     (the caption bar), feeds the meter, and the title card plays
##     (TitleCard, the "garage" style).
##   * Sixty seconds on the meter (MeterDisplay) for the moves on his
##     notepad (Notepad), any order, anywhere in the parkade; each is
##     scratched out as you do it, and he mumbles about the old game while
##     you drive (the caption bar, never in the way).
##   * Off the roof ramp: "ROOF??" in red on the pad, and the test's over.
##     Out of the parkade or out of the car: over. Meter out: a parking
##     officer walks up and writes you a ticket (TICKET_FINE).
##   * The result as a road test sheet (ScoreSheet), stamped HIRED, FAILED
##     or TICKETED. Again, or done. Passing pays (PAY_FIRST, then PAY_BEST
##     for a new best time) and gets you on Kinbook.
##
## A module of Economy (Economy.MODULES). Kept in GameState.missions
## ["garage"]: {passed, best (seconds used), tries}.

const PARKADE_ID := "28326012" ## the Queen Parkade
const SECONDS := 60.0
const PAY_FIRST := 300
const PAY_BEST := 100
const COUNTER_ID := "mission_garage"
const MINIMAP_ID := "mission_garage"
## Tenner's car: a Charlatan in brown (every car was brown).
const CAR_MODEL := "charlatan"
const CAR_PAINT := Color(0.36, 0.22, 0.12)
## m: how near you have to be for his lines over his head.
const NEAR := 26.0
## The moves, as they're checked.
const SLALOM_FLIPS := 4 ## swerves either way...
const SLALOM_SECS := 5.0 ## ...within this
const SPEED_KMH := 60.0 ## on the dial (main.gd's SPEEDO_SCALE)
const BRAKE_FROM_KMH := 40.0
const BURNOUT_SECS := 1.2

enum State { IDLE, INTRO, TITLE, RUNNING, TICKET, RESULT }

var economy: Economy
var lay: Dictionary
var tenner: MissionPerson
var officer: MissionPerson
var tenner_car: Car
var state := State.IDLE

var _ui: CanvasLayer
var caption: CaptionBar
var pad: Notepad
var meter: MeterDisplay
var card: TitleCard
var sheet: ScoreSheet

var _car: Car ## the player's, for this test
var _left := SECONDS
var _done := {} ## move id -> true
var _roof := false
var _hits := 0
var _why := "" ## how it ended: "" (passed or not finished), "ticket", "left", "roof", "car"
var _mumbled: Array[int] = []
var _mumble_t := 0.0
var _crash_t := 0.0
var _said_low := false
var _bubble_t := 0.0
var _bubble_i := 0
var _outside_t := 0.0
var _ticket_t := 0.0
# The moves' state (see _check_moves).
var _yaw := 0.0 ## turned so far this test (radians, + left)
var _burn := 0.0
var _hb := {} ## handbrake turn: {t, yaw}
var _turn := {} ## one-eighty without the handbrake: {t, yaw, hb}
var _rev := {} ## reverse one-eighty: {t, yaw}
var _spin := {} ## three-sixty: {t, yaw}
var _flips: Array[float] = []
var _flip_sign := 0.0
var _brake := {} ## brake test: {t}
var _still := 0.0
var _t := 0.0


static func _gs() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("GameState")


static func saved() -> Dictionary:
	var m: Dictionary = _gs().get("missions")
	return m.get("garage", {})


static func _save(d: Dictionary) -> void:
	var m: Dictionary = _gs().get("missions")
	m["garage"] = d
	_gs().call("save_game")


func setup(e: Economy) -> void:
	economy = e
	if e.world == null or e.world.data == null:
		return
	lay = Parkade.find(e.world.data, e.world.network, e.world.terrain, PARKADE_ID)
	if lay.is_empty():
		return
	_build_ui()
	_place_tenner()
	_place_board()
	economy.counters.add({"id": COUNTER_ID, "title": GarageLines.CARD_TITLE, "subtitle": GarageLines.CARD_SUB,
		"at": tenner.global_position, "reach": 6.0, "on_foot": true, "in_car": true, "kind": "mission",
		"map_name": "The Garage", "prompt": "Talk to Tenner", "items": _items})
	var mm := Minimap.find(get_tree())
	if mm != null:
		mm.set_marker(MINIMAP_ID, "mission", tenner.global_position)


# --- where things are ------------------------------------------------------------------------

## The stalls on the +v side of the ground floor: [first's u, how many].
func _stall_count() -> int:
	return int(Parkade._stalls(lay)[1])


func _place_tenner() -> void:
	var n := _stall_count()
	# His car backed into the last stall by the way in, on the side away
	# from the stair tower's end; Tenner standing in the aisle beside its
	# nose, looking down the parkade.
	var car_xf := Parkade.stall_xform(lay, 0, 1, n - 1)
	tenner_car = Car.new()
	tenner_car.model_id = CAR_MODEL if CarModels.has_model(CAR_MODEL) else "civique"
	tenner_car.paint = CAR_PAINT
	tenner_car.owner_id = "tenner"
	tenner_car.name = "TennerCar"
	add_child(tenner_car)
	tenner_car.global_transform = car_xf
	tenner_car.reset_physics_interpolation()
	tenner_car.start_parked()
	tenner = MissionPerson.new()
	tenner.name = "Tenner"
	tenner.setup(tenner_look(), "mission_tenner", Color(1.0, 0.86, 0.55))
	add_child(tenner)
	var stand := Parkade.aisle_xform(lay, 0, 1, n - 2).origin
	var down := Parkade.world_point(lay, 0.0, float(lay["hv"]) * 0.5, 0)
	tenner.place(stand, down)


## Tenner: a 70s TV cop. Brown jacket, sideburns, aviators, boots.
static func tenner_look() -> Dictionary:
	return {
		"skin": Color(0.87, 0.69, 0.57), "hair": Color(0.2, 0.13, 0.08), "hair_style": 0,
		"height": 1.8, "build": 1.06, "sideburns": true, "shades": Color(0.1, 0.07, 0.04),
		"outfit": {
			"hat": {"kind": "none", "color": Color(0.1, 0.1, 0.1)},
			"top": {"kind": "jacket", "color": Color(0.29, 0.16, 0.07)},
			"bottom": {"kind": "trousers", "color": Color(0.24, 0.19, 0.14)},
			"shoes": {"kind": "boots", "color": Color(0.16, 0.1, 0.06)},
		},
	}


## The parking officer: a navy cap, a hi-vis jacket, navy trousers.
static func officer_look() -> Dictionary:
	return {
		"skin": Color(0.76, 0.57, 0.43), "hair": Color(0.1, 0.08, 0.07), "hair_style": 2,
		"height": 1.72, "build": 1.0,
		"outfit": {
			"hat": {"kind": "cap", "color": Color(0.08, 0.1, 0.2)},
			"top": {"kind": "jacket", "color": Color(0.86, 0.92, 0.16)},
			"bottom": {"kind": "trousers", "color": Color(0.08, 0.1, 0.2)},
			"shoes": {"kind": "dress", "color": Color(0.05, 0.05, 0.05)},
		},
	}


## The sandwich board on the apron out front, against the pier between
## the two ways in, facing the street.
func _place_board() -> void:
	PlacedProps.prepare()
	var holder := Node3D.new()
	holder.name = "GarageBoard"
	add_child(holder)
	var p := Parkade.world_point(lay, float(lay["hu"]) + 0.9, 0.0, 0)
	var out: Vector2 = lay["u"]
	holder.global_transform = Transform3D(Basis(Vector3.UP, StreetProps.yaw_facing(out)), p)
	var board := MeshInstance3D.new()
	board.mesh = PlacedProps._meshes.get("sandwich_board")
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	WorldLod.limit(board, 1.0)
	holder.add_child(board)
	var label := Label3D.new()
	label.text = GarageLines.BOARD
	label.font_size = 64
	# Sized to fit the board's face (0.48 x 0.62 m), as PlacedSigns does.
	var longest := 1
	for l in GarageLines.BOARD.split("\n"):
		longest = maxi(longest, l.length())
	var rows := GarageLines.BOARD.split("\n").size()
	label.pixel_size = minf(0.46 / (longest * 64 * 0.62), 0.6 / (rows * 64 * 1.15))
	# A dark edge the board's colour hides the chalk scribbles behind the words.
	label.outline_size = 18
	label.outline_modulate = Color(0.16, 0.15, 0.14)
	label.modulate = Color(0.95, 0.95, 0.9)
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visibility_range_end = 60.0
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.position = Vector3(0, 0.55, 0.17)
	label.rotation.x = -deg_to_rad(16.5)
	holder.add_child(label)


## Where `p` is in the parkade: Vector3(along u, across v, level), and
## whether it's inside (a little slack round the walls).
func _local(p: Vector3) -> Vector3:
	var d := Vector2(p.x, p.z) - (lay["c"] as Vector2)
	return Vector3(d.dot(lay["u"]), d.dot(lay["v"]), (p.y - float(lay["floor_y"])) / Parkade.STOREY)


func _inside(p: Vector3) -> bool:
	var l := _local(p)
	return absf(l.x) < float(lay["hu"]) + 1.5 and absf(l.y) < float(lay["hv"]) + 1.0 \
		and l.z > -0.6 and l.z < float(lay["levels"]) - 1.0 + 1.2


# --- the UI ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "GarageUi"
	_ui.layer = 60 # under the counter card (65)
	add_child(_ui)
	pad = Notepad.new()
	_ui.add_child(pad)
	meter = MeterDisplay.new()
	_ui.add_child(meter)
	caption = CaptionBar.new()
	_ui.add_child(caption)
	card = TitleCard.new()
	_ui.add_child(card)
	sheet = ScoreSheet.new()
	_ui.add_child(sheet)
	sheet.again.connect(func() -> void: _start(true))
	sheet.closed.connect(_finish_up)


func _items() -> Array:
	var p: Node3D = economy.player
	var car: Car = p.get("vehicle") if p != null else null
	var again := bool(saved().get("passed", false)) or int(saved().get("tries", 0)) > 0
	var item := {"id": "take", "name": GarageLines.TAKE_AGAIN if again else GarageLines.TAKE, "note": GarageLines.TAKE_NOTE, "price": 0}
	if car == null or bool(p.get("passenger")):
		item["enabled"] = false
		item["why"] = GarageLines.NEED_CAR
	else:
		item["action"] = func(_i: Dictionary) -> String:
			_start.call_deferred(again)
			return ""
	return [item]


# --- the test --------------------------------------------------------------------------------

func _start(again: bool) -> void:
	var p: Node3D = economy.player
	_car = p.get("vehicle") if p != null else null
	if _car == null:
		_finish_up()
		return
	if economy.counters.menu != null:
		economy.counters.menu.close()
	sheet.visible = false
	_hold(true)
	state = State.INTRO
	tenner.hush()
	tenner.face = _car.global_position
	var lines: Array[String] = GarageLines.AGAIN.duplicate() if again else GarageLines.INTRO.duplicate()
	for line in lines:
		caption.say(GarageLines.NAME, line)
		await caption.finished
		if state != State.INTRO:
			return
	caption.say(GarageLines.NAME, GarageLines.METER)
	MissionSounds.play(_ui, MissionSounds.coin(), -6.0)
	await caption.finished
	if state != State.INTRO:
		return
	state = State.TITLE
	card.show_card("garage", GarageLines.TITLE, GarageLines.TITLE_SUB, GarageLines.TITLE_CREDIT)
	await card.done
	if state != State.TITLE:
		return
	_begin()


func _begin() -> void:
	_left = SECONDS
	_done.clear()
	_roof = false
	_hits = 0
	_why = ""
	_mumbled.clear()
	_mumble_t = 6.0
	_crash_t = 0.0
	_said_low = false
	_outside_t = 0.0
	_yaw = 0.0
	_burn = 0.0
	_hb = {}
	_turn = {}
	_rev = {}
	_spin = {}
	_flips.clear()
	_flip_sign = 0.0
	_brake = {}
	_still = 0.0
	_t = 0.0
	pad.head = GarageLines.PAD_HEAD
	pad.sub = GarageLines.PAD_SUB
	pad.set_list(GarageLines.LIST)
	pad.slap_in()
	meter.seconds = _left
	meter.visible = true
	var d := saved()
	d["tries"] = int(d.get("tries", 0)) + 1
	_save(d)
	if _car != null and not _car.crashed.is_connected(_on_crash):
		_car.crashed.connect(_on_crash)
	_hold(false)
	state = State.RUNNING


func _hold(on: bool) -> void:
	if _car != null and is_instance_valid(_car):
		_car.controls_held = on


func _on_crash(impact: float) -> void:
	if state != State.RUNNING or impact < 3.0:
		return
	_hits += 1
	if _crash_t <= 0.0:
		_crash_t = 4.0
		caption.mumble(GarageLines.NAME, GarageLines.CRASH[randi() % GarageLines.CRASH.size()], 2.6)


func _physics_process(delta: float) -> void:
	if tenner == null:
		return
	var p: Node3D = economy.player
	match state:
		State.IDLE:
			_idle(delta, p)
		State.RUNNING:
			_running(delta, p)
		State.TICKET:
			_ticketing(delta)


## Waiting: watching you if you're about, a line over his head now and then.
func _idle(delta: float, p: Node3D) -> void:
	if p == null:
		return
	var near := p.global_position.distance_to(tenner.global_position) < NEAR
	tenner.face = p.global_position if near else Vector3.INF
	_bubble_t -= delta
	if near and _bubble_t <= 0.0:
		_bubble_t = randf_range(6.0, 9.0)
		tenner.say(GarageLines.WAITING[_bubble_i % GarageLines.WAITING.size()], 4.0)
		_bubble_i += 1


func _running(delta: float, p: Node3D) -> void:
	_t += delta
	_left -= delta
	meter.seconds = _left
	_crash_t -= delta
	if _car == null or not is_instance_valid(_car) or p.get("vehicle") != _car:
		_end("car")
		return
	tenner.face = _car.global_position
	_check_moves(delta)
	if state != State.RUNNING:
		return
	# The roof ramp: in the air off the top deck, near the lip.
	var l := _local(_car.global_position)
	if not _roof and _car.wheels_down == 0 and l.z > float(lay["levels"]) - 1.4 and not (lay.get("jump", {}) as Dictionary).is_empty():
		var lip := Parkade.jump_lip(lay)
		if Vector2(l.x, l.y).distance_to(lip) < 9.0:
			_roof = true
			pad.write_extra(GarageLines.PAD_ROOF)
			caption.mumble(GarageLines.NAME, GarageLines.DONE["roof"], 3.0)
	if not _inside(_car.global_position):
		_outside_t += delta
		if _outside_t > (1.5 if _roof else 0.6):
			_end("roof" if _roof else "left")
			return
	else:
		_outside_t = 0.0
	if _done.size() >= GarageLines.LIST.size():
		_end("")
		return
	if _left <= 10.0 and not _said_low:
		_said_low = true
		caption.mumble(GarageLines.NAME, GarageLines.LOW, 3.0)
	if _left <= 0.0:
		_left = 0.0
		meter.seconds = 0.0
		_start_ticket()
		return
	# His mumbling, when nothing else is being said.
	_mumble_t -= delta
	if _mumble_t <= 0.0 and not caption.visible:
		_mumble_t = randf_range(7.0, 10.0)
		var pick := -1
		for i in 10:
			var k := randi() % GarageLines.MUMBLES.size()
			if not _mumbled.has(k):
				pick = k
				break
		if pick >= 0:
			_mumbled.append(pick)
			caption.mumble(GarageLines.NAME, GarageLines.MUMBLES[pick], 5.0)


## Ticks a move off (once), with his line about it.
func _tick(id: String) -> void:
	if _done.has(id):
		return
	_done[id] = true
	pad.cross_out(id)
	caption.mumble(GarageLines.NAME, str(GarageLines.DONE.get(id, "")), 2.6)
	_mumble_t = maxf(_mumble_t, 4.0)


## How the car's moving, against each move on the list.
func _check_moves(delta: float) -> void:
	var c := _car
	var dyaw := c.yaw_rate * delta
	_yaw += dyaw
	var spd := c.speed ## m/s, + forward
	var kmh := absf(spd) * 3.6 * 0.8 ## what the dial says (main.gd SPEEDO_SCALE)
	# Burnout: foot down, barely moving, tyres spinning (or the brake held
	# against the throttle, which is how a car without the power does it).
	var spinning := c.throttle_input() > 0.6 and kmh < 25.0 and c.skid > 0.45
	var brake_stand := c.throttle_input() > 0.6 and c.brake_applied > 0.3 and kmh < 10.0
	if spinning or brake_stand:
		_burn += delta
		if _burn >= BURNOUT_SECS:
			_tick("burnout")
	else:
		_burn = maxf(0.0, _burn - delta * 0.5)
	# Handbrake turn: the handbrake on going forward, and round 150 degrees.
	if _hb.is_empty() and c.handbrake_on and spd > 4.0:
		_hb = {"t": _t, "yaw": _yaw}
	if not _hb.is_empty():
		if absf(_yaw - float(_hb["yaw"])) >= deg_to_rad(150.0):
			_tick("handbrake")
			_hb = {}
		elif _t - float(_hb["t"]) > 3.5:
			_hb = {}
	# One-eighty: turned round going forward, without the handbrake.
	if _turn.is_empty() and spd > 3.0 and absf(c.yaw_rate) > 0.7:
		_turn = {"t": _t, "yaw": _yaw, "hb": c.handbrake_on}
	if not _turn.is_empty():
		if c.handbrake_on:
			_turn["hb"] = true
		if absf(_yaw - float(_turn["yaw"])) >= deg_to_rad(160.0):
			if not bool(_turn["hb"]):
				_tick("one_eighty")
			_turn = {}
		elif _t - float(_turn["t"]) > 4.5 or spd < -0.5:
			_turn = {}
	# Reverse one-eighty: backing up fast, then swung round to go forward.
	if _rev.is_empty() and spd < -4.0:
		_rev = {"t": _t, "yaw": _yaw}
	if not _rev.is_empty():
		if spd < -4.0 and absf(c.yaw_rate) < 0.3:
			_rev = {"t": _t, "yaw": _yaw} # still straight back: start from here
		if absf(_yaw - float(_rev["yaw"])) >= deg_to_rad(135.0) and spd > -1.5:
			_tick("reverse_180")
			_rev = {}
		elif _t - float(_rev["t"]) > 3.5:
			_rev = {}
	# Three-sixty: all the way round in one go.
	if _spin.is_empty() and absf(c.yaw_rate) > 0.6:
		_spin = {"t": _t, "yaw": _yaw}
	if not _spin.is_empty():
		if absf(_yaw - float(_spin["yaw"])) >= deg_to_rad(330.0):
			_tick("three_sixty")
			_spin = {}
		elif absf(c.yaw_rate) < 0.25 or _t - float(_spin["t"]) > 10.0:
			_spin = {}
	# Slalom: swerving left and right, quickly, at a decent lick.
	if kmh > 15.0 and absf(c.yaw_rate) > 0.35:
		var s := signf(c.yaw_rate)
		if s != _flip_sign:
			_flip_sign = s
			_flips.append(_t)
	while not _flips.is_empty() and _t - _flips[0] > SLALOM_SECS:
		_flips.remove_at(0)
	if _flips.size() >= SLALOM_FLIPS + 1:
		_tick("slalom")
	# Speed: the dial at 60.
	if kmh >= SPEED_KMH:
		_tick("speed")
	# Brake test: hard on the brakes from 40, to a stop.
	if _brake.is_empty() and kmh >= BRAKE_FROM_KMH and spd > 0.0 and c.brake_applied > 0.5:
		_brake = {"t": _t}
	if not _brake.is_empty():
		if c.brake_applied < 0.2 and kmh > 3.0:
			_brake = {}
		elif kmh < 1.0:
			_tick("brake_test")
			_brake = {}
		elif _t - float(_brake["t"]) > 4.0:
			_brake = {}
	# Backed into a stall: stopped in one, nose out to the aisle.
	if absf(spd) < 0.3:
		_still += delta
		if _still > 0.8 and _in_stall_nose_out(c):
			_tick("back_in")
	else:
		_still = 0.0


func _in_stall_nose_out(c: Car) -> bool:
	var l := _local(c.global_position)
	if absf(l.z - roundf(l.z)) > 0.25:
		return false
	var hv: float = lay["hv"]
	var side := signf(l.y)
	var mid := hv - Parkade.WALL - Parkade.STALL_DEPTH * 0.5
	if absf(absf(l.y) - mid) > 1.4:
		return false
	var st := Parkade._stalls(lay)
	var first: float = st[0]
	var n: int = st[1]
	var i := roundi((l.x - first) / Parkade.STALL_WIDTH)
	if i < 0 or i >= n:
		return false
	if absf(l.x - (first + i * Parkade.STALL_WIDTH)) > 0.9:
		return false
	# Nose to the aisle: forward points across, toward the middle.
	var fwd3 := -c.global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z).normalized()
	var aisle := (lay["v"] as Vector2) * -side
	return fwd.dot(aisle) > 0.85


# --- the ticket ------------------------------------------------------------------------------

func _start_ticket() -> void:
	state = State.TICKET
	_why = "ticket"
	_ticket_t = 0.0
	_hold(true)
	if officer == null:
		officer = MissionPerson.new()
		officer.name = "ParkingOfficer"
		officer.setup(officer_look(), "mission_parking_officer", Color(0.95, 1.0, 0.6))
		add_child(officer)
	officer.visible = true
	# From a few metres off, toward the middle of the parkade, to the
	# driver's window.
	var at := _car.global_position
	var l := _local(at)
	var toward := Parkade.world_point(lay, l.x, 0.0, roundi(l.z))
	var from := at + (toward - at).normalized() * 7.0 if toward.distance_to(at) > 1.0 else at + Vector3(4, 0, 0)
	from.y = at.y
	officer.place(from, at)
	officer.move_to(_car.door_point())
	officer.face = _car.global_position
	caption.hide_now()


func _ticketing(delta: float) -> void:
	_ticket_t += delta
	if officer == null:
		return
	if officer.at_goal():
		officer.face = _car.global_position if _car != null and is_instance_valid(_car) else officer.face
		officer.gesture = 0.35
		if _ticket_t > 0.0 and not officer.has_meta("said0"):
			officer.set_meta("said0", true)
			_ticket_t = 0.0
			caption.mumble(GarageLines.OFFICER, GarageLines.TICKET[0], 2.4)
			officer.say(GarageLines.TICKET[0], 2.4)
		elif officer.has_meta("said0") and not officer.has_meta("said1") and _ticket_t > 2.4:
			officer.set_meta("said1", true)
			caption.mumble(GarageLines.OFFICER, GarageLines.TICKET[1], 3.6)
			officer.say(GarageLines.TICKET[1], 3.6)
		elif officer.has_meta("said1") and _ticket_t > 6.4:
			officer.remove_meta("said0")
			officer.remove_meta("said1")
			_end("ticket")
	elif _ticket_t > 12.0:
		_end("ticket")


# --- the end ---------------------------------------------------------------------------------

func _end(why: String) -> void:
	if state == State.RESULT:
		return
	state = State.RESULT
	_why = why
	_hold(true)
	if _car != null and is_instance_valid(_car) and _car.crashed.is_connected(_on_crash):
		_car.crashed.disconnect(_on_crash)
	pad.slide_out()
	meter.visible = false
	caption.hide_now()
	var passed := why == "" and _done.size() >= GarageLines.LIST.size()
	var used := SECONDS - maxf(_left, 0.0)
	var d := saved()
	var first_try := passed and not bool(d.get("passed", false)) and int(d.get("tries", 0)) <= 1
	var money := ""
	var gs := _gs()
	if passed:
		var best := float(d.get("best", INF))
		var pay := 0
		if not bool(d.get("passed", false)):
			pay = PAY_FIRST
		elif used < best:
			pay = PAY_BEST
		if used < best:
			d["best"] = used
		d["passed"] = true
		_save(d)
		if pay > 0:
			gs.call("add_money", pay)
			money = "Paid: +%s" % CarModels.dollars(pay)
		_kinbook("garage_pass")
	elif why == "ticket":
		var fine := mini(GarageLines.TICKET_FINE, int(gs.get("money")))
		if fine > 0:
			gs.call("add_money", -fine)
		money = "Parking ticket: -%s" % CarModels.dollars(GarageLines.TICKET_FINE)
		_kinbook("garage_ticket")
	var rows: Array = []
	for it: Array in GarageLines.LIST:
		rows.append([str(it[1]), _done.has(str(it[0]))])
	if _roof:
		rows.append([GarageLines.ROOF_ROW, true])
	var left_s := maxi(0, ceili(_left))
	var remarks: Array[String] = [GarageLines.hit_remark(_hits), GarageLines.verdict(passed, why, first_try)]
	if passed and money == "":
		remarks.append(GarageLines.NOT_BEST)
	elif passed and float(d.get("best", INF)) == used and int(d.get("tries", 0)) > 1:
		remarks.append(GarageLines.BEST)
	var stamp := GarageLines.HIRED if passed else (GarageLines.TICKETED if why == "ticket" else GarageLines.FAILED)
	var car_name := _car.display_name() if _car != null and is_instance_valid(_car) else "on foot"
	sheet.show_sheet({"rows": rows, "passed": passed, "stamp": stamp, "money": money,
		"lines": ["Vehicle: %s" % car_name, ("Meter: %d:%02d left" % [left_s / 60, left_s % 60]) if why != "ticket" else "Meter: expired",
			"Signalled: never"],
		"remarks": remarks})
	tenner.say(GarageLines.verdict(passed, why, first_try), 6.0)


## Closing the sheet: back to the town.
func _finish_up() -> void:
	state = State.IDLE
	_hold(false)
	caption.hide_now()
	pad.visible = false
	meter.visible = false
	if officer != null:
		officer.move_to(officer.global_position + (officer.global_position - tenner.global_position).normalized() * 30.0)
		var o := officer
		get_tree().create_timer(15.0).timeout.connect(func() -> void:
			if o != null and is_instance_valid(o) and state != State.TICKET:
				o.visible = false)


func _kinbook(what: String) -> void:
	var kb := economy.main.get_node_or_null("Kinbook") if economy.main != null else null
	if kb != null and kb.has_method("post_about_you"):
		kb.call("post_about_you", what)


## For the check tool: skip the talking and the title, straight to the
## meter running.
func start_now() -> void:
	var p: Node3D = economy.player
	_car = p.get("vehicle") if p != null else null
	if _car != null:
		_begin()


func is_running() -> bool:
	return state == State.RUNNING


func moves_done() -> Array:
	return _done.keys()

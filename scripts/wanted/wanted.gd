extends Node
## The wanted level (autoload "Wanted"): docs/design.md section 7.
##
## Pure rules, no police. A crime only counts once the police know about
## it, the way it works in the big crime games: one an officer sees (or is
## the victim of) counts at once (report_crime); any other waits as
## unreported (unreported_crime) until a witness gets through on the phone
## (witness_report), and with nobody to call it in it never counts. Each
## crime adds heat; the level is a step on the heat (HEAT_FOR_LEVEL), so a
## calm player stays low and a rampage climbs fast, and painting the
## police (and putting them out) climbs fastest. Whoever can see the
## player says so (police_saw_player, called by the police piece), and out
## of sight the level drops one at a time on a timer.
##
## Caught at level 1 is a ticket, not jail: a small fine on the spot
## (stop for the cruiser and take it, or run and make it a chase). caught() plays
## Two Years Less a Day, takes the fine and clears it all. The car wash asks
## seen_recently(). Speed and driving never count: nothing here looks at
## how you drive.
##
## Single player for now, but written so a server could own it: the rules
## are plain data and timers, and the HUD and the panels only listen.
## Nothing here is saved: every session starts clean.
##
## Debug (debug builds only): F5 raises the level, Shift+F5 lowers it, F7 makes a
## pretend officer watch the player (police_saw_player every frame) until
## pressed again, F4 gets you caught. From code or the remote debugger:
## Wanted.debug_set_level(3), Wanted.debug_watch(true), Wanted.caught().

signal level_changed(level: int)
## The island-wide crackdown (design.md, 5+ players wanted). Single player:
## never emitted yet.
signal crackdown_changed(on: bool)
## Whether police can see the player now (for the HUD's flashing).
signal seen_changed(seen: bool)
## Something worth a title on the HUD: the FIP called in, overtime, the wash.
signal announced(title: String, subtitle: String)
## After caught(): what happened ({level, fine, dismissed, cash_before, ...}).
signal arrested(result: Dictionary)
## A witness got through (after `announced`): where they saw the player,
## what the player looked like to them (look_now() at the crime), and who
## called (a person on foot's kind, "driver", "owner"). The police piece
## reads out their description (WitnessDescription).
signal witness_called(at: Vector3, look: Dictionary, who: String)

## The names of the levels (design.md, "Wanted levels").
const NAMES := ["", "Someone called your mother", "Charlatown Police", "The FIP", "Federal Overreach"]
const MAX_LEVEL := 4

## Out of sight this long (s) drops a level, by level (design.md, "Getting away").
const ESCAPE_SECONDS := [0.0, 20.0, 60.0, 60.0, 90.0]
## The search circle round the last known position (m), bigger each level.
const SEARCH_RADIUS := [0.0, 120.0, 200.0, 320.0, 450.0]
## Inside the search circle the escape clock runs at this rate: they're
## searching right there, so hiding near where they lost you is slow going
## (design.md: "hiding near where they lost you rarely works").
const INSIDE_CIRCLE_RATE := 0.5
## "Seen" lasts this long (s) after the last report of it: one officer's
## glance covers the frames between sight checks.
const SEEN_MEMORY := 1.0
## Heat at which each level starts: a couple of people painted is 1, a
## few more (or a cop) is 2, a fight with the police is 3, a war with the
## FIP is 4 (as well as the time at 3: LEVEL_4_AFTER).
const HEAT_FOR_LEVEL := [0.0, 1.0, 5.0, 14.0, 30.0]
## An unreported crime waits this long (s) for a call before it's
## forgotten, and a call reports the ones within this of where it saw (m).
const UNREPORTED_MEMORY := 90.0
const REPORT_REACH := 90.0
## Level 3 becomes 4 after this long at level 3 with the police on you
## (design.md: "about 90 s more"; longer after the testers' runs, so a long
## level 3 fight isn't always lost at level 4). Time only counts while they've seen you
## in the last CHASE_MEMORY seconds: lying low runs the escape clock instead.
const LEVEL_4_AFTER := 260.0
const CHASE_MEMORY := 10.0
## Unseen this long (s) before a car wash clears level 3 or 4.
const WASH_UNSEEN := 20.0
## Level 4 reached from a level 3 chase drops back to 3 after this long
## unseen (s).
const ESCAPE_4_FROM_3 := 60.0
## At level 2, in sight this long (s) to start the escape clock again (a
## shorter glimpse halves it).
const RESPOT_FULL := 5.0
## ...and not in the first this-many seconds at level 3+ (no free level 3:
## straight from the crime into a wash round the corner).
const WASH_MIN_CHASE := 150.0
## ...and they must have had you in sight this long (s) in the chase: a
## chase nobody ever saw isn't one you wash away.
const WASH_SEEN := 10.0
## The tactical unit "exceeds its overtime budget" after this long at level
## 4 and goes home, dropping you to 3 (design.md, "Level 4").
const OVERTIME_SECONDS := 300.0
## The least each kind of crime puts you at, and the heat it adds.
const CRIMES := {
	"paint_bystander": {"min": 1, "heat": 1.0},
	"paint_car": {"min": 1, "heat": 1.0},
	# Taking a stopped traffic car from its driver (scripts/traffic/).
	"take_car": {"min": 1, "heat": 2.0},
	"paint_police": {"min": 2, "heat": 3.0},
	# Putting an officer out (PoliceDispatcher.officer_went_out).
	"police_out": {"min": 2, "heat": 4.0},
	"car_meet": {"min": 2, "heat": 2.0},
	"flee": {"min": 2, "heat": 2.0},
	"paint_fip": {"min": 3, "heat": 4.0},
	"fip_out": {"min": 3, "heat": 5.0},
	"paint_tactical": {"min": 4, "heat": 4.0},
	# Hitting people on foot with a car (EmergencyServices counts them,
	# and reports it straight away: a car on the sidewalk needs no
	# witness): one, then three, then six or more in a couple of minutes.
	"hit_pedestrian": {"min": 1, "heat": 2.0},
	"hit_pedestrians": {"min": 2, "heat": 3.0},
	"hit_spree": {"min": 3, "heat": 5.0},
}
## What the ticket's for (caught at level 1). docs/voice.md.
const TICKET_LINES := [
	"Disturbing the peace with a recreational device. Payable at City Hall, Tuesdays.",
	"He wrote it slowly, so you'd both know who was in charge.",
	"He was going to let you off with a warning. Then he remembered the quota.",
	"\"Mischief, paint-related.\" There's a box for it now.",
]
const WARNING_LINES := [
	"Let off with a warning. He's not doing the paperwork for this.",
	"Let off with a warning. His shift ends in four minutes.",
]

## Fines by level, before the cap. Caught at level 4 it's $85 (the panel's
## joke: "Cost to taxpayers: $4.2 million. Fine: $85."), so the rest climb
## to it.
const FINES := [0, 35, 55, 70, 85]
## The fine is never more than this share of your cash (design.md).
const FINE_CAP := 0.10
## About one arrest in eight, the case falls apart: no fine.
const DISMISS_CHANCE := 0.125

## Where you're let out: in front of Charlottetown Police Services, 10
## Kirkwood Drive (OSM way 404245466, "amenity=police"), on the walk
## between its front and the street, facing Kirkwood Drive. [lon, lat] and
## compass degrees, like the map editor's spots.
const STATION_POS := [-63.1360339, 46.2446644]
const STATION_DIRECTION := 336.0

var level := 0
## Where police (or a witness) last put the player. The middle of the
## search circle.
var last_known_position := Vector3.ZERO
## How many times a witness has called it in (witness_report).
var witness_calls := 0
## The search circle's radius now (m); 0 when not wanted.
var search_radius := 0.0
## Out of sight for this long at this level, on the escape clock (s, scaled
## by INSIDE_CIRCLE_RATE inside the circle).
var escape_time := 0.0
## How much trouble you're in: crimes add to it (CRIMES "heat"), and the
## level is the highest HEAT_FOR_LEVEL step it's reached. Set back to the
## level's step when the level drops.
var heat := 0.0
## Crimes nobody's told the police about yet: {kind, at, t}.
var unreported: Array[Dictionary] = []
## Witnesses on the phone right now (any object as a key): the HUD shows
## "Someone's calling it in" while there are any and it would matter.
var callers := {}
## True while a witness's call is putting crimes on the books (so the
## police radio reads the witness's description, not its own call-in line).
var reporting := false
## Seconds at level 3 with the police on you, toward level 4.
var heat_time := 0.0
## When (clock) this chase got to level 3 or above (-1: it hasn't).
var high_since := -1.0
## This level 4 came up from a level 3 chase (not straight from a crime).
var up_from_3 := false
## How long they've had you in sight this time (s).
var _seen_for := 0.0
## Time in sight (s) this chase, since level 0.
var seen_in_chase := 0.0
## Seconds at level 4, toward the overtime budget.
var overtime := 0.0
## The tactical unit went home on overtime: level 4 only comes back by
## painting it, until you're below level 3.
var overtime_spent := false
var crackdown := false

## What `seen_recently` measures against: game seconds since start (the
## clock tick() advances).
var clock := 0.0
var _last_seen := -1000.0
var _was_seen := false

## Who's wanted: the player node (or anything with a global_position).
## Found as the current scene's "Player" when left null.
var target: Node3D = null
## Runs the rules each physics frame. Tests turn it off and call tick().
var auto_tick := true
## Play the jail panels and move the player to the station on caught().
## Tests turn it off.
var play_panels := true
## The dice for the dismissals (seed it for tests).
var rng := RandomNumberGenerator.new()

## Debug: a pretend officer watching the player (F7).
var debug_watching := false


func _ready() -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


## Advances the rules by `delta` seconds: the escape clock out of sight,
## level 3 heating up to 4, the overtime budget at 4.
func tick(delta: float) -> void:
	clock += delta
	if debug_watching and level > 0:
		var p := player_position()
		police_saw_player(p)
	var seen := seen_recently()
	if seen != _was_seen:
		_was_seen = seen
		seen_changed.emit(seen)
	if not unreported.is_empty() and clock - float(unreported[0]["t"]) > UNREPORTED_MEMORY:
		unreported = unreported.filter(func(c: Dictionary) -> bool: return clock - float(c["t"]) <= UNREPORTED_MEMORY)
	if level == 0:
		return
	if level == 4:
		overtime += delta
		if overtime >= OVERTIME_SECONDS:
			overtime_spent = true
			_set_level(3)
			announced.emit("Federal Overreach is over", "The tactical unit has exceeded its overtime budget. The Paint Tank is going home.")
			return
	if level == 3 and not overtime_spent and seen_recently(CHASE_MEMORY):
		heat_time += delta
		if heat_time >= LEVEL_4_AFTER:
			_set_level(4)
			return
	if seen:
		if not debug_watching:
			seen_in_chase += delta
		# At level 2 a glimpse (a blocker turning out, a stakeout) costs half
		# the escape clock; staying in sight RESPOT_FULL s costs all of it.
		# From 3 any sighting starts it again.
		if level <= 2 and _seen_for < RESPOT_FULL:
			if _seen_for == 0.0:
				escape_time *= 0.5
			_seen_for += delta
		else:
			escape_time = 0.0
		return
	_seen_for = 0.0
	escape_time += delta * (INSIDE_CIRCLE_RATE if inside_search_circle() else 1.0)
	if escape_time >= _escape_seconds():
		_set_level(level - 1)
		if level == 0:
			announced.emit("You lost them", "Wanted level cleared. Nobody saw a thing.")
		else:
			announced.emit("They're losing you", "Down to: %s" % NAMES[level])


## A crime at `at`. Raises the level as the design's table says (kinds:
## "paint_bystander", "paint_car", "paint_police", "paint_fip", "flee",
## "car_meet", "take_car" (a traffic car taken from its driver); and
## "paint_tactical", the tactical unit's vehicle, straight to 4; and
## "hit_pedestrian", "hit_pedestrians" and "hit_spree", people hit with a
## car: one, three, six or more). Every crime puts the search circle on it and restarts the escape
## clock. Speed is never a crime.
func report_crime(kind: String, at: Vector3) -> void:
	if not CRIMES.has(kind):
		push_warning("Wanted.report_crime: unknown crime '%s', counted as painting a bystander" % kind)
		kind = "paint_bystander"
	var c: Dictionary = CRIMES[kind]
	last_known_position = at
	escape_time = 0.0
	heat += float(c["heat"])
	var want := maxi(level, maxi(int(c["min"]), level_for_heat(heat)))
	if want > level:
		_set_level(want)
	# Never below the level's own step (a crime that set the level from
	# its minimum starts the heat there).
	heat = maxf(heat, HEAT_FOR_LEVEL[level])


## Heat past this level's step: how far over it the player's pushed it
## (the dispatcher sends more for it).
func heat_over() -> float:
	return maxf(0.0, heat - HEAT_FOR_LEVEL[level])


## The level `h` heat reaches.
static func level_for_heat(h: float) -> int:
	var l := 0
	for i in range(1, MAX_LEVEL + 1):
		if h >= HEAT_FOR_LEVEL[i]:
			l = i
	return l


## A crime nobody with a badge saw: it waits for a witness to call it in
## (witness_report). While wanted and in sight it's simply a crime (the
## police are watching): report_crime.
func unreported_crime(kind: String, at: Vector3) -> void:
	if level > 0 and seen_recently():
		report_crime(kind, at)
		return
	unreported.append({"kind": kind, "at": at, "t": clock, "look": look_now()})


## What the player looks like right now, to a witness: in a car (its
## model and colour, and the car itself) or on foot (their jacket).
func look_now() -> Dictionary:
	var t := _target()
	var look := {"in_car": false, "top": Color.GRAY}
	if t == null:
		return look
	var car: Variant = t.get("vehicle")
	if car is Node3D and is_instance_valid(car):
		look["in_car"] = true
		look["car"] = car
		look["model_id"] = str((car as Node3D).get("model_id"))
		look["paint"] = (car as Node3D).get("paint")
		return look
	var m: Variant = t.get("model")
	if m is Node:
		var outfit: Dictionary = (m as Node).get("outfit") if (m as Node).get("outfit") is Dictionary else {}
		var top: Variant = (outfit.get("top", {}) as Dictionary).get("color", (m as Node).get("top"))
		if top is Color:
			look["top"] = top
	return look


## A crime by the player against anyone but the police: it counts at once
## if an officer can see the player do it (PoliceDispatcher.sees_player_now,
## which then says so on the radio), else it waits for a witness. True if
## it counted now.
func player_crime(kind: String, at: Vector3) -> bool:
	var d := get_tree().get_first_node_in_group("police_dispatcher") if is_inside_tree() else null
	if d != null and d.has_method("sees_player_now") and bool(d.call("sees_player_now")):
		report_crime(kind, at)
		d.call("saw_crime")
		return true
	unreported_crime(kind, at)
	return false


## A witness started (on) or finished or gave up (off) calling it in.
func phone_call(who: Object, on: bool) -> void:
	if on:
		callers[who] = clock
	else:
		callers.erase(who)


## Someone's on the phone to the police about you, and it'll matter.
func being_called_in() -> bool:
	for k: Variant in callers.keys():
		if not is_instance_valid(k):
			callers.erase(k)
	return not callers.is_empty() and (level > 0 or not unreported.is_empty())


## An officer can see the player at `at` (the police piece calls this every
## sight check while any of them can). Moves the search circle, keeps the
## chase on and stops the escape clock.
func police_saw_player(at: Vector3) -> void:
	last_known_position = at
	_last_seen = clock
	escape_time = 0.0
	if not _was_seen:
		_was_seen = true
		seen_changed.emit(true)


## A witness (a traffic driver, someone on foot) got through: they saw the
## player at `at` a few seconds ago (and the crime at `crime_at`, if they
## lost you since). Every unreported crime near the crime now
## counts (report_crime); and wanted or not, the search circle goes there
## and the escape clock starts again. With nothing to report and not
## wanted, the police thank them for calling.
func witness_report(at: Vector3, crime_at := Vector3.INF, who := "") -> void:
	var near := at if crime_at == Vector3.INF else crime_at
	var told: Array[Dictionary] = []
	for c in unreported:
		if Vector2(near.x - (c["at"] as Vector3).x, near.z - (c["at"] as Vector3).z).length() <= REPORT_REACH:
			told.append(c)
	var was := level
	var look: Dictionary = {}
	reporting = true
	for c in told:
		unreported.erase(c)
		report_crime(str(c["kind"]), c["at"])
		look = c.get("look", look)
	reporting = false
	if level == 0:
		return
	last_known_position = at
	escape_time = 0.0
	witness_calls += 1
	if was == 0:
		announced.emit("Someone called it in", "a witness gave the police your description")
	else:
		announced.emit("A witness called it in", "the police know where you were seen")
	witness_called.emit(at, look if not look.is_empty() else look_now(), who)


## True if any officer saw the player in the last `within` seconds (by
## default, "the last moment"). The car wash asks this.
func seen_recently(within := SEEN_MEMORY) -> bool:
	return clock - _last_seen <= within


## Inside the search circle now.
func inside_search_circle() -> bool:
	if level == 0:
		return false
	var p := player_position()
	return Vector2(p.x - last_known_position.x, p.z - last_known_position.z).length() <= search_radius


## Seconds left to lie low before the level drops, at the rate the clock
## runs where the player is now (slower inside the circle); 0 when not wanted.
func escape_left() -> float:
	if level == 0:
		return 0.0
	var rate := INSIDE_CIRCLE_RATE if inside_search_circle() else 1.0
	return maxf(0.0, _escape_seconds() - escape_time) / rate


func level_name(l := -1) -> String:
	return NAMES[clampi(level if l < 0 else l, 0, MAX_LEVEL)]


## Where the wanted player is now.
func player_position() -> Vector3:
	var t := _target()
	return t.global_position if t != null else last_known_position


func _target() -> Node3D:
	if target != null and is_instance_valid(target):
		return target
	# By group, not by path: in a car the player is moved under the car's
	# seat, and a lookup by path then found nobody, so the search circle
	# thought you were always inside it and the escape clock ran at half
	# speed.
	target = get_tree().get_first_node_in_group(PlayerController.GROUP) as Node3D if is_inside_tree() else null
	return target


## The fine for being caught at `at_level` with `cash`: the level's fine,
## never more than FINE_CAP of the cash (whole dollars, rounded down).
static func fine_for(at_level: int, cash: int) -> int:
	var base: int = FINES[clampi(at_level, 0, MAX_LEVEL)]
	return clampi(mini(base, floori(maxi(cash, 0) * FINE_CAP)), 0, base)


## The police caught the player. Rolls for the case falling apart, takes
## the fine (or not), clears the level, plays Two Years Less a Day and lets
## the player out in front of the station. Returns what happened:
## {level, dismissed, fine, cash_before, panels (the captions shown)}.
## Does nothing (and returns {}) when not wanted.
func caught() -> Dictionary:
	if level == 0:
		return {}
	var at_level := level
	var dismissed := rng.randf() < DISMISS_CHANCE
	var cash := GameState.money
	var fine := 0 if dismissed else fine_for(at_level, cash)
	if fine > 0:
		GameState.spend_money(fine)
	var result := {"level": at_level, "dismissed": dismissed, "fine": fine, "cash_before": cash,
		"crackdown": crackdown}
	if at_level == 1:
		# Level 1 is a ticket on the spot, not a night in the cells.
		result["ticket"] = true
		result["panels"] = []
		clear()
		arrested.emit(result)
		if fine > 0:
			announced.emit("A ticket: $%d" % fine, TICKET_LINES[rng.randi() % TICKET_LINES.size()])
		else:
			announced.emit("Let off", WARNING_LINES[rng.randi() % WARNING_LINES.size()])
		return result
	result["panels"] = JailLines.panels(result, rng)
	clear()
	arrested.emit(result)
	if play_panels and is_inside_tree():
		JailPanels.play(get_tree(), result)
	return result


## Back to level 0, the clocks and the circle with it (caught, the car wash,
## a new session).
func clear() -> void:
	heat = 0.0
	unreported.clear()
	heat_time = 0.0
	overtime = 0.0
	overtime_spent = false
	escape_time = 0.0
	_set_level(0)


## The car wash: clears the level unless an officer saw you go in. True if
## it cleared one.
func car_wash() -> bool:
	if level == 0 or seen_recently() or wash_too_soon():
		return false
	clear()
	return true


## How long unseen to drop a level: ESCAPE_SECONDS, less at a level 4 that
## grew out of a long level 3 chase (that fight's been long enough already).
func _escape_seconds() -> float:
	if level == 4 and up_from_3:
		return ESCAPE_4_FROM_3
	return ESCAPE_SECONDS[level]


## At level 3 and up a wash only clears you once they've been without you
## for a while (WASH_UNSEEN s): straight from the chase into the nearest
## wash is too soon, they're still combing the streets round it.
func wash_too_soon() -> bool:
	return level >= 3 and (escape_time < WASH_UNSEEN or clock - high_since < WASH_MIN_CHASE or seen_in_chase < WASH_SEEN)


## How long until a car wash would clear the level, if nobody sees you
## between now and then (for the HUD): 0 now, the seconds left of the
## waits in wash_too_soon(), or -1 when waiting won't do it (at level 3 or
## 4 they've hardly seen you, so they haven't a car to look out for: lose
## them the long way). Seen right now, it's the wait from once they lose you.
func wash_wait() -> float:
	if level < 3:
		return 0.0
	if seen_in_chase < WASH_SEEN:
		return -1.0
	var unseen := WASH_UNSEEN if seen_recently() else maxf(0.0, WASH_UNSEEN - escape_time) / (INSIDE_CIRCLE_RATE if inside_search_circle() else 1.0)
	var chase := maxf(0.0, WASH_MIN_CHASE - (clock - high_since)) if high_since >= 0.0 else 0.0
	return maxf(unseen, chase)


## Where caught() lets the player out, as the world's transform: the front
## of the police station. Needs the map loaded (world.data.projection).
func station_xform(world: Node) -> Transform3D:
	if world == null or not world.has_method("edit_xform"):
		return Transform3D.IDENTITY
	return world.call("edit_xform", {"pos": STATION_POS, "direction": STATION_DIRECTION}, 0.05)


func _set_level(l: int) -> void:
	l = clampi(l, 0, MAX_LEVEL)
	if l < 3:
		overtime_spent = false
	if l < 3:
		high_since = -1.0
		up_from_3 = false
	elif l == 4 and level == 3:
		up_from_3 = true
	elif high_since < 0.0:
		high_since = clock
	if l < level:
		# Dropping a level cools you to its step: the next crime starts
		# from there.
		heat = HEAT_FOR_LEVEL[l]
	if l != level:
		escape_time = 0.0
		if l != 3:
			heat_time = 0.0
		if l != 4:
			overtime = 0.0
	if l == 0:
		_last_seen = -1000.0
		seen_in_chase = 0.0
	var changed := l != level
	level = l
	search_radius = SEARCH_RADIUS[level]
	if changed:
		level_changed.emit(level)


# --- debug ------------------------------------------------------------------------------------

## Debug: straight to a level (0 to 4), the circle on the player.
func debug_set_level(l: int) -> void:
	last_known_position = player_position()
	_set_level(l)


## Debug: a pretend officer watches the player (on) or looks away (off).
func debug_watch(on: bool) -> void:
	debug_watching = on


func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_F5:
			# Shift+F5 lowers it (F6 is the aim test target's key).
			debug_set_level(level - 1 if k.shift_pressed else level + 1)
			announced.emit("Debug: wanted level %d" % level, level_name() if level > 0 else "not wanted")
		KEY_F7:
			debug_watch(not debug_watching)
			announced.emit("Debug: a cop %s" % ("is watching you" if debug_watching else "looked away"), "F7 again to %s" % ("look away" if debug_watching else "watch"))
		KEY_F4:
			caught()
		_:
			return
	get_viewport().set_input_as_handled()

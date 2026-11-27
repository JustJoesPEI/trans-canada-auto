extends SceneTree
## Measures a paintball fight with the police on a bare test pad: a
## scripted player against two officers on foot, tuned as the chase tunes
## them (PoliceUnit.apply_foot_tuning), at each wanted level. Run with a
## fixed frame rate so it runs as fast as the machine can:
##
##   godot --headless --fixed-fps 60 --path . --script res://tools/gunfight_check.gd -- [--trials=10] [--levels=1,2,3,4] [--range=20]
##
## Three fights at each level, each `trials` times with a different seed:
##
##   stand    the player stands in the open and doesn't shoot: how long
##            two officers take to paint them out
##   strafe   the player strafes side to side, aiming, and doesn't shoot
##   duel     the player strafes and shoots back like a decent player (paced
##            pulls at the chest, allowing for the drop, a miss of about
##            `skill` m at 20 m): who wins, and how long it takes
##
## Prints one GUNFIGHT line per fight and level: how often the player went
## out, the median time to it, the officers' hit rate, and in a duel the
## player's win rate and the median length of a fight. What we aim for
## (docs/design.md, "Shooting your way out"): standing still in the open is
## a mistake you have a few seconds to fix; strafing buys a lot more; a
## decent player wins most fights at levels 1-2 and about half at 4.

const MAX_FIGHT := 30.0 ## s before a fight is called a draw

var _rng := RandomNumberGenerator.new()
var _shots: PaintShots
var _player: PlayerController
var _police_shots := 0
var _police_hits := 0
var _range := 20.0
var _skill := 0.3


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var trials := int(args.get("trials", "10"))
	_range = float(args.get("range", "20"))
	_skill = float(args.get("skill", "0.3"))
	var levels: Array[int] = []
	for l in str(args.get("levels", "1,2,3,4")).split(","):
		levels.append(int(l))

	var pad := StaticBody3D.new()
	pad.collision_layer = Layers.GROUND
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = BoxShape3D.new()
	(floor_shape.shape as BoxShape3D).size = Vector3(300, 2, 300)
	floor_shape.position = Vector3(0, -1, 0)
	pad.add_child(floor_shape)
	root.add_child(pad)
	_shots = PaintShots.new()
	root.add_child(_shots)
	_shots.hit.connect(_on_hit)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	_player.input_enabled = false
	root.add_child(_player)
	_player.place(Transform3D.IDENTITY)
	await _frames(30)

	for level in levels:
		for fight: String in ["stand", "strafe", "duel"]:
			var outs: Array[float] = []
			var wins := 0
			var lengths: Array[float] = []
			_police_shots = 0
			_police_hits = 0
			for t in trials:
				_rng.seed = hash("%s_%d_%d" % [fight, level, t])
				var r: Dictionary = await _fight(level, fight)
				if bool(r["out"]):
					outs.append(float(r["time"]))
				if bool(r["won"]):
					wins += 1
				lengths.append(float(r["time"]))
			var acc := float(_police_hits) / maxf(1.0, float(_police_shots))
			var line := "GUNFIGHT level %d %-6s out %2d/%d  median out %5.1f s  officers hit %3d%%" % [
				level, fight, outs.size(), trials, _median(outs), roundi(acc * 100.0)]
			if fight == "duel":
				line += "  player won %2d/%d  median fight %5.1f s" % [wins, trials, _median(lengths)]
			print(line)
	quit(0)


func _on_hit(info: Dictionary) -> void:
	if bool(info.get("police", false)) and info.get("target") == _player:
		_police_hits += 1


## One fight: two officers `_range` m off, 8 m apart.
func _fight(level: int, fight: String) -> Dictionary:
	_player.body_paint.revive()
	_player.body_paint.clear()
	_player.marker.refill()
	_player.place(Transform3D.IDENTITY)
	_player.bot_wish = Vector3.ZERO
	_player.bot_aim = Vector3.INF
	_player.bot_fire = false
	var officers: Array[Officer] = []
	for i in 2:
		var o := Officer.new()
		o.force = "fip" if level >= 3 else "city"
		o.number = i
		root.add_child(o)
		o.global_position = Vector3((i - 0.5) * 8.0, 0.0, -_range)
		PoliceUnit.apply_foot_tuning(o, level)
		o.shoot_at = _player
		o.marker.fired.connect(func(_k: float) -> void: _police_shots += 1)
		officers.append(o)
	await _frames(2)
	var t := 0.0
	var dir := 1.0
	var turn_in := _rng.randf_range(0.6, 1.4)
	var pull := 0.0
	var won := false
	while t < MAX_FIGHT and not _player.is_out():
		var alive := officers.filter(func(o: Officer) -> bool: return not o.is_out())
		if alive.is_empty():
			won = true
			break
		var target: Officer = alive[0]
		if fight != "stand":
			turn_in -= 1.0 / 60.0
			if turn_in <= 0.0:
				dir = -dir
				turn_in = _rng.randf_range(0.6, 1.4)
			_player.bot_wish = Vector3(dir, 0, 0)
			_player.bot_aim = _aim_at(target)
		if fight == "duel":
			# Paced pulls, about four a second, each aimed afresh.
			pull -= 1.0 / 60.0
			_player.bot_fire = pull <= 0.0
			if pull <= 0.0:
				pull = _rng.randf_range(0.2, 0.3)
				_player.bot_aim = _aim_at(target, true)
		await physics_frame
		t += 1.0 / 60.0
	for o in officers:
		o.queue_free()
	_player.bot_aim = Vector3.INF
	_player.bot_fire = false
	_player.bot_wish = Vector3.ZERO
	# Let what's in flight land before the next fight.
	await _frames(60)
	return {"out": _player.is_out(), "won": won, "time": t}


## Where a decent player aims: the chest, up for the drop, with a miss.
func _aim_at(o: Officer, shot := false) -> Vector3:
	var p := o.global_position + Vector3.UP * 1.25
	var d := _player.global_position.distance_to(p)
	var fly := d / 75.0
	p.y += 0.5 * PaintWeapons.GRAVITY * fly * fly
	if shot:
		var miss := _skill * d / 20.0
		p += Vector3(_rng.randfn(0.0, miss), _rng.randfn(0.0, miss), 0.0)
	return p


func _median(a: Array[float]) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return b[b.size() / 2]


func _frames(n: int) -> void:
	for i in n:
		await physics_frame

class_name PaintMarker
extends Node
## The marker someone is holding: the trigger, the hopper, reloading, and
## how wide the shots go (docs/design.md section 2, "Feel"). A child of
## the player; the player sets `trigger` from the Fire input each physics
## step and calls `step`. Officers can use one the same way.
##
## Semi-automatic: each pull fires one ball, up to the weapon's fire_rate
## (8 a second for the Islander) if you pull fast; holding the trigger
## fires at its hold_rate (5 a second). A pull made a moment too soon is
## kept and fired as soon as it can be, so fast pulls never feel eaten.
## The hopper holds 40; a reload takes 1.6 s (Reload key, or pulling on an
## empty hopper), and when you're not aiming it tops itself up on its own.
##
## Spread: the weapon's own while aimed and standing still, wider moving
## (RUN_SPREAD at a jog), widest from the hip (HIP_SPREAD, while the marker
## is still coming up).

## A shot went (for the HUD and sound).
signal fired
## The shooter's shot hit something: kind is "person" or "car", out is
## true when it put a person out.
signal hit_confirmed(kind: String, out: bool)

## Spread multipliers (not in the design, which only orders them).
const RUN_SPREAD := 2.5 ## at a jog while aiming (aim_run_speed)
const HIP_SPREAD := 4.0 ## the marker not yet up
const MOVING_FROM := 0.3 ## m/s: slower than this is standing still
## s without aiming before the hopper starts topping itself up.
const TOPUP_DELAY := 0.6
## s a pull made too early is kept for.
const PULL_BUFFER := 0.15
## Where the barrel ends, in MarkerModel's space.
const MUZZLE := Vector3(0.0, 0.07, -0.535)

var weapon: Dictionary = PaintWeapons.ISLANDER
var ammo := int(PaintWeapons.ISLANDER["hopper"])
## s left of a reload (or a top-up), 0 when not reloading.
var reload_left := 0.0
## The trigger is held (set by the owner every physics step).
var trigger := false
## The shooter (whose shots these are, and whose body they leave from).
var shooter: Node3D

var _was_trigger := false
var _since_shot := 99.0
var _pull_wait := -1.0
var _not_aiming := 0.0
var _topping_up := false
var _audio: AudioStreamPlayer
var _connected := false


func _ready() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "MarkerSounds"
	_audio.max_polyphony = 4
	add_child(_audio)


## Change weapon (the weapon wheel, later): a full hopper of the new one.
func set_weapon(w: Dictionary) -> void:
	weapon = w
	ammo = int(w.get("hopper", 40))
	reload_left = 0.0
	_topping_up = false


## True while reloading or topping up.
func is_reloading() -> bool:
	return reload_left > 0.0


## 0..1 through the reload.
func reload_progress() -> float:
	var t := float(weapon.get("reload_time", 1.6))
	return 1.0 - reload_left / t if reload_left > 0.0 and t > 0.0 else 1.0


## Start a reload (the Reload key).
func reload() -> void:
	if ammo >= int(weapon.get("hopper", 40)) or reload_left > 0.0:
		return
	reload_left = float(weapon.get("reload_time", 1.6))
	_topping_up = false
	if reload_left <= 0.0:
		ammo = int(weapon.get("hopper", 40))


## One physics step. `can_fire`: not out, not in a car. `aiming`: Aim held;
## `aim_amount` 0..1 how far the marker is up; `speed` m/s on the ground;
## `jog_speed` the speed that counts as a full run; `muzzle` where the ball
## leaves; `target` what the crosshair is on.
func step(delta: float, can_fire: bool, aiming: bool, aim_amount: float, speed: float, jog_speed: float, muzzle: Vector3, target: Vector3) -> void:
	_connect_hits()
	_since_shot += delta
	var hopper := int(weapon.get("hopper", 40))
	if reload_left > 0.0:
		reload_left -= delta
		if reload_left <= 0.0:
			reload_left = 0.0
			ammo = hopper
			_topping_up = false
	if aiming:
		_not_aiming = 0.0
		if _topping_up:
			# Raised the marker mid top-up: it's not done.
			reload_left = 0.0
			_topping_up = false
	else:
		_not_aiming += delta
		if _not_aiming >= TOPUP_DELAY and ammo < hopper and reload_left <= 0.0 and float(weapon.get("reload_time", 0.0)) > 0.0:
			reload_left = float(weapon["reload_time"])
			_topping_up = true

	var pulled := trigger and not _was_trigger
	_was_trigger = trigger
	if pulled:
		_pull_wait = PULL_BUFFER
	elif _pull_wait >= 0.0:
		_pull_wait -= delta
	if not can_fire or not aiming:
		_pull_wait = -1.0
		return
	var rate := float(weapon.get("fire_rate", 8.0))
	var hold := float(weapon.get("hold_rate", 0.0))
	var want := false
	if _pull_wait >= 0.0 and _since_shot >= 1.0 / maxf(rate, 0.01):
		want = true
	elif trigger and hold > 0.0 and _since_shot >= 1.0 / hold:
		want = true
	if not want or reload_left > 0.0:
		return
	_pull_wait = -1.0
	if ammo <= 0:
		reload()
		return
	var spread := lerpf(HIP_SPREAD, 1.0, clampf(aim_amount, 0.0, 1.0))
	if speed > MOVING_FROM:
		spread *= lerpf(1.0, RUN_SPREAD, clampf(speed / maxf(jog_speed, 0.1), 0.0, 1.0))
	var shots := PaintShots.find(get_tree())
	if shots == null:
		return
	var from := _clear_muzzle(muzzle)
	shots.fire(from, target - muzzle, shooter, weapon, spread)
	ammo -= 1
	_since_shot = 0.0
	_play(PaintSounds.pop(), -12.0)
	fired.emit()


## Where a person's marker shoots from: its barrel, once it's up; the
## right shoulder before that.
static func muzzle_of(model: HumanoidModel) -> Vector3:
	if model.skeleton != null:
		var m := model.skeleton.get_node_or_null("Marker") as Node3D
		if m != null and m.visible:
			return m.global_transform * MUZZLE
	return model.global_transform * Vector3(0.25, model.height * 0.8, -0.4)


## The barrel can be through a wall the shooter is pressed up against: then
## the ball leaves from where the wall is, not from the far side of it.
func _clear_muzzle(muzzle: Vector3) -> Vector3:
	if shooter == null or not shooter.is_inside_tree():
		return muzzle
	var q := PhysicsRayQueryParameters3D.create(shooter.global_position + Vector3.UP * 1.3, muzzle, PaintShots.MASK)
	if shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	var h := shooter.get_world_3d().direct_space_state.intersect_ray(q)
	if h.is_empty():
		return muzzle
	return (h["position"] as Vector3) - (muzzle - q.from).normalized() * 0.02


func _connect_hits() -> void:
	if _connected:
		return
	var shots := PaintShots.find(get_tree())
	if shots == null:
		return
	_connected = true
	shots.hit.connect(_on_hit)


func _on_hit(info: Dictionary) -> void:
	if info.get("shooter") != shooter or shooter == null:
		return
	var kind := str(info["kind"])
	if kind != "person" and kind != "car":
		return
	var out := bool(info.get("out", false))
	if kind == "person":
		_play(PaintSounds.out_confirm() if out else PaintSounds.thwack(), -4.0 if out else -6.0)
	hit_confirmed.emit(kind, out)


func _play(stream: AudioStream, db: float) -> void:
	if _audio == null or not _audio.is_inside_tree():
		return
	_audio.stream = stream
	_audio.volume_db = db
	_audio.play()

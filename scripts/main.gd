extends Node3D
## Wires the scene together: puts the player at the spawn point, points the
## camera at them and hands the HUD what it needs. The town itself is built
## by the World node (WorldBuilder) before this runs.

@onready var world: WorldBuilder = $World
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: Hud = $HUD


func _ready() -> void:
	if world.is_built:
		player.place(world.get_spawn())
	player.camera_rig = camera_rig
	camera_rig.target = player
	camera_rig.snap_to_target()
	hud.setup(world, player)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# A full pause menu arrives with the UI milestone; for now Esc frees the
	# mouse and a click takes it back.
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

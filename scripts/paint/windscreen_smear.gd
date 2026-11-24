class_name WindscreenSmear
extends Control
## Paint on the windscreen of the car you're driving, over your view
## (docs/design.md section 3, "Windscreen", and the 0–50% row of section
## 7): the view blurred behind a film of the paint, where the ball hit.
## The paint itself is the car's (PaintCoverage.screen); this only draws
## it, and the wiper blade while the wipers run (PaintCoverage.wipe).
##
## From the driver's seat each smear sits where that spot of the glass is
## on screen. In the chase view you're not looking through the glass, but
## a painted windscreen still costs you: the smears show over the road
## ahead of the car (the middle of the screen, above the car), laid out as
## they are on the glass, a little fainter (CHASE_STRENGTH), so the chase
## view is no way round it.
##
## One Control, one shared material (shaders/paint_smear.gdshader), a
## textured rectangle per smear; nothing at all when the glass is clean.

## How strong the smears are in the chase view (not in the design).
const CHASE_STRENGTH := 0.6
## Screen pixels per metre of splat radius, in the chase view.
const CHASE_SCALE := 520.0
## The smear is this much bigger than the splat on the glass (from the
## inside it's close, out of focus and spread).
const INSIDE_SPREAD := 1.1

static var _material: ShaderMaterial

var coverage: PaintCoverage
var cockpit := false
var camera: Camera3D

var _blade: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/paint_smear.gdshader")
	material = _material
	_blade = Control.new()
	_blade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blade.draw.connect(_draw_blade)
	add_child(_blade)


## Show this car's windscreen (or nothing, with null).
func show_car(pc: PaintCoverage, in_cockpit: bool, cam: Camera3D) -> void:
	coverage = pc
	cockpit = in_cockpit
	camera = cam
	var on := pc != null and (not pc.screen.is_empty() or pc.wiper >= 0.0)
	visible = on
	if on:
		queue_redraw()
		_blade.queue_redraw()


func _draw() -> void:
	if coverage == null:
		return
	var tex := PaintTexture.texture()
	var cell := Vector2(tex.get_width(), tex.get_height()) * 0.5
	for i in coverage.screen.size():
		var s: Dictionary = coverage.screen[i]
		var spot := _on_screen(s["uv"], float(s["size"]))
		if spot.z <= 0.0:
			continue
		var c: Color = s["colour"]
		c.a = float(s["strength"]) * (1.0 if cockpit else CHASE_STRENGTH)
		var r := spot.z
		var src := Rect2(PaintTexture.cell_offset(i) * Vector2(tex.get_width(), tex.get_height()), cell)
		draw_texture_rect_region(tex, Rect2(Vector2(spot.x, spot.y) - Vector2(r, r), Vector2(r, r) * 2.0), src, c)


func _draw_blade() -> void:
	if coverage == null or coverage.wiper < 0.0:
		return
	var x := coverage.wiper_x()
	var root := _on_screen(Vector2(clampf(x * 0.6, -0.6, 0.6), 0.0), 0.05)
	var tip := _on_screen(Vector2(x, 0.95), 0.05)
	if root.z <= 0.0 or tip.z <= 0.0:
		return
	_blade.draw_line(Vector2(root.x, root.y), Vector2(tip.x, tip.y), Color(0.04, 0.04, 0.05, 0.9), 7.0, true)


## A spot on the glass (x -1..1, y 0..1 up) and a radius in metres, to a
## point on screen and a radius in pixels (z <= 0: not on screen).
func _on_screen(uv: Vector2, size: float) -> Vector3:
	var view := get_viewport_rect().size
	if cockpit and camera != null and coverage != null and coverage.car != null and "shape" in coverage.car:
		var cab: Dictionary = (coverage.car.get("shape") as Dictionary).get("cabin", {})
		if not cab.is_empty():
			var t := uv.y
			var half := lerpf(float(cab["wb"]), float(cab["wr"]), t)
			var local := Vector3(uv.x * half, lerpf(float(cab["belt"]), float(cab["roof"]), t), lerpf(float(cab["za"]), float(cab["zb"]), t))
			var world := coverage.car.global_transform * local
			if camera.is_position_behind(world):
				return Vector3(0, 0, -1)
			var p := camera.unproject_position(world)
			var edge := camera.unproject_position(world + camera.global_basis.x * size * INSIDE_SPREAD)
			return Vector3(p.x, p.y, maxf(8.0, p.distance_to(edge)))
	return Vector3(view.x * (0.5 + uv.x * 0.3), view.y * (0.6 - uv.y * 0.32), size * CHASE_SCALE)

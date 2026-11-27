extends SceneTree
## Checks the fleet cars' lettering, crests and unit numbers, the things
## that kept going wrong by eye: anything laid over a wheel arch, across a
## panel seam, standing off the body or sunk into it, and anything the
## builder had to move or shrink to fit (CarBuilder.fit_on_side). Headless:
##
##   godot --headless --path . --script res://tools/livery_check.gd
##
## Prints a LIVERY line per word placed (where it asked to go and where it
## went), FAIL lines for anything wrong, and exits non-zero if any.

const FLEETS := [["jaunt", "cps"], ["tahoma", "fip"], ["paint_tank", "fip_tactical"]]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for fl: Array in FLEETS:
		var model: String = fl[0]
		var livery: String = fl[1]
		var shape := CarModels.shape_for(model, livery, 12)
		var paint := Color.html(str(CarModels.LIVERIES[livery]["colour"]))
		var b := CarBuilder.new(shape, paint)
		b.make_body()
		print("== %s (%s)" % [model, livery])
		for p: Array in b.side_panels():
			print("   panel %-8s z %.2f .. %.2f" % [p[0], p[1], p[2]])
		for f: Dictionary in b.fit_log:
			if f.get("no_room", false):
				_fail("%s (%s): no room for %s on %s" % [model, livery, f["what"], f["panel"]])
				continue
			if float(f["h"]) < float(f["h_asked"]) * 0.75:
				_fail("%s (%s): %s shrunk to %d%% to fit %s" % [model, livery, f["what"], roundi(100.0 * float(f["h"]) / float(f["h_asked"])), f["panel"]])
			print("LIVERY %-11s on %-8s h %.3f -> %.3f  y %.3f -> %.3f%s" % [f["what"], f["panel"], f["h_asked"], f["h"],
				f["y_asked"], f["y"], "  (moved to fit)" if f["moved"] else ""])
		_check_letters(b, model, livery)
		# The unit numbers, placed by PoliceGear when the car is made.
		var car := Car.new()
		car.model_id = model
		car.livery = livery
		car.unit = 12
		car.paint = paint
		root.add_child(car)
		if car.police != null:
			var gb := car.police.builder
			for f: Dictionary in gb.fit_log:
				if f["what"] == "unit":
					print("LIVERY unit        on %-8s h %.3f -> %.3f  y %.3f -> %.3f%s" % [f["panel"], f["h_asked"], f["h"],
						f["y_asked"], f["y"], "  (moved to fit)" if f["moved"] else ""])
			for l: Label3D in car.police.find_children("*", "Label3D", false, false):
				_check_label(b, l, model)
		car.free()
	print("LIVERY %s" % ("OK" if _fails == 0 else "%d FAIL" % _fails))
	quit(1 if _fails > 0 else 0)


func _fail(msg: String) -> void:
	_fails += 1
	print("FAIL ", msg)


## Every corner of the lettering: on the side (not the hood), clear of the
## arches, off the paint by a few millimetres, and not across a seam.
func _check_letters(b: CarBuilder, model: String, livery: String) -> void:
	var kit: MeshKit = b._main["letters"]
	var seams: Array[float] = []
	for sm: Array in b._seams():
		if sm[1]:
			seams.append(float(sm[0]))
	var bad := {}
	for v: Vector3 in kit.verts:
		var ox := b.outer_x(v.z, v.y)
		if absf(v.x) < ox - 0.08:
			continue # across the hood
		var sv := b._station_at(v.z)
		var arch := b._arch_bottom(v.z, sv.y, sv.z)
		if v.y < arch + 0.02:
			bad["over a wheel arch at z %.2f" % v.z] = true
		var gap := absf(v.x) - ox
		if gap < 0.0 or gap > 0.02:
			bad["%.3f m off the body at z %.2f y %.2f" % [gap, v.z, v.y]] = true
		for z: float in seams:
			if absf(v.z - z) < 0.015:
				bad["across the seam at z %.2f" % z] = true
	for k: String in bad:
		_fail("%s (%s): lettering %s" % [model, livery, k])


## A label (unit number, back text) flat on the side must clear the body
## over its whole face and not hang over an arch.
func _check_label(b: CarBuilder, l: Label3D, model: String) -> void:
	if absf(l.rotation.y) < 0.1 or l.text.length() > 4:
		return # the back's words and the roof's number
	var h := l.pixel_size * 96.0 * 0.72
	var length := h * 0.62 * l.text.length()
	var p := l.position
	for k in 5:
		for dy: float in [-0.5, 0.5]:
			var z := p.z + length * (float(k) / 4.0 - 0.5)
			var y := p.y + dy * h
			if absf(p.x) < b.outer_x(z, y) - 0.002:
				_fail("%s: label %s sinks into the body at z %.2f" % [model, l.text, z])
				return
			var sv := b._station_at(z)
			if y < b._arch_bottom(z, sv.y, sv.z) + 0.02:
				_fail("%s: label %s over a wheel arch" % [model, l.text])
				return

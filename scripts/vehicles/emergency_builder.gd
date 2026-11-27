class_name EmergencyBuilder
extends RefCounted
## The emergency vehicles' bodies, built on a TruckBuilder (its cab, nose,
## frame and axles, and its shared surfaces): the Island Boo-Boo Bus's
## box ambulance ("ambulance", a high-roof van) and the Island Wee-Woo Brigade's pumper
## ("fire_engine"). TruckBuilder.build() calls these by "look".
##
## The flashing lenses, the words down the sides and the siren are
## EmergencyGear's (a child of the car, like a cruiser's PoliceGear): the
## mesh carries the housings they sit in. Small parts (seams, handles,
## gauges, rungs, the roll-up doors' ribs) go in the near-only detail mesh.
##
## Faces -Z, wheels on the ground at y = 0, driver on the left (-x).

const WHITE := Color(0.94, 0.94, 0.92)
const STRIPE_RED := Color(0.78, 0.07, 0.06)
## High-visibility yellow-green and red: the checks down an ambulance's
## sides.
const HI_VIS := Color(0.78, 0.9, 0.05)
const ALU := Color(0.74, 0.75, 0.76)
const HOSE_YELLOW := Color(0.85, 0.66, 0.12)
const HOSE_RED := Color(0.62, 0.08, 0.06)

## The fire engine's body behind the cab.
const ENG_BODY := {"z0": -2.3, "z1": 4.55, "y0": 0.55, "y1": 2.4, "hw": 1.23}


# --- the Island Boo-Boo Bus ------------------------------------------------------------------

## The Island's ambulances are high-roof vans: white, a lime band and a
## dark green stripe low down the sides, the lime panel with PARAMEDIC
## high up behind the cab, the service's name mirrored across the front
## of the roof, checks on the back doors. (From Joe's photo of a real one;
## the names on it are ours.)
const LIME := Color(0.78, 0.86, 0.05)
const GREEN := Color(0.04, 0.3, 0.17)

## A high-roof van ambulance: a short sloping nose, the windscreen raked
## back into the tall roof, the cab doors and the side door, the back
## doors with their windows and checks, and the lights round the roof.
static func ambulance(b: TruckBuilder) -> void:
	var hw := float(b.shape["width"]) * 0.5 - 0.02
	var fa := float(b.shape["front_axle"])
	var ra := float(b.shape["rear_axle"])
	var wr := float(b.shape["wheel_radius"])
	var nose := -3.42
	var back := 3.4
	var belt := 1.16 # the top of the lower body, where the glass starts
	var roof := 2.8
	var sill := wr * 2.0 + 0.06 # the top of the wheel wells
	var low := 0.4 # the bottom of the body
	var ws := -2.45 # the foot of the windscreen
	var cap := -1.25 # where the windscreen's rake reaches the roof
	var wa := ar_r(wr)
	# Lower body: above the wheels the whole length; below, between the
	# wells.
	b._prof("paint", -hw, hw, Vector2(nose + 0.05, sill), Vector2(back, sill), Vector2(back, belt), Vector2(ws, belt), b.paint, 0.0)
	# The nose: the hood falling to the bumper.
	b._prof("paint", -hw + 0.06, hw - 0.06, Vector2(nose, low + 0.1), Vector2(ws, low + 0.1), Vector2(ws, belt), Vector2(nose + 0.12, 0.98), b.paint, 0.08)
	for seg: Array in [[nose + 0.1, fa - wa], [fa + wa, ra - wa], [ra + wa, back]]:
		var z0 := float(seg[0])
		var z1 := float(seg[1])
		b._box("paint", Vector3(0, (low + sill) * 0.5, (z0 + z1) * 0.5), Vector3(hw * 2.0, sill - low, z1 - z0), b.paint)
	for z: float in [fa, ra]:
		b._box("rough", Vector3(0, (low + sill) * 0.5, z), Vector3(hw * 2.0 - 0.5, sill - low, wa * 2.0), TruckBuilder.DARK)
		for s: float in [-1.0, 1.0]:
			b._arch("rough", z, wr + 0.02, wa - 0.03, wa, minf((hw - 0.25) * s, (hw + 0.01) * s), maxf((hw - 0.25) * s, (hw + 0.01) * s), 0.0, PI, Color(0.12, 0.12, 0.13), 14)
	# Upper body: one block from the windscreen's foot up its rake to the
	# high roof and back, its edges rounded over.
	b._prof("paint", -hw, hw, Vector2(ws, belt), Vector2(back, belt), Vector2(back, roof), Vector2(cap, roof), b.paint, 0.07)
	var rz := func(y: float) -> float: return ws + (cap - ws) * (y - belt) / (roof - belt)
	# Glass: the windscreen, the cab's side windows, one in the side door
	# and two in the back doors.
	var wt := 2.02
	var g := Color(0.07, 0.09, 0.11, 0.88)
	var n_ws := Vector3(0, cap - ws, -(roof - belt)).normalized()
	b._quad("glass", Vector3(-hw + 0.1, belt + 0.06, rz.call(belt + 0.06) - 0.01), Vector3(hw - 0.1, belt + 0.06, rz.call(belt + 0.06) - 0.01),
		Vector3(hw - 0.12, wt, rz.call(wt) - 0.01), Vector3(-hw + 0.12, wt, rz.call(wt) - 0.01), n_ws, g)
	b._detail = true
	for s: float in [-1.0, 1.0]:
		b._tube("rough", Vector3(0.05 * s, belt + 0.08, rz.call(belt + 0.08) - 0.02), Vector3(0.75 * s, belt + 0.1, rz.call(belt + 0.1) - 0.02), 0.008, TruckBuilder.RUBBER, 5)
	b._detail = false
	var cz0: float = rz.call(1.95) + 0.08
	var cz1 := -1.25
	for s: float in [-1.0, 1.0]:
		var x := (hw + 0.004) * s
		var n := Vector3(s, 0, 0)
		b._quad("glass", Vector3(x, belt + 0.08, cz0), Vector3(x, belt + 0.08, cz1), Vector3(x, 1.95, cz1), Vector3(x, 1.95, cz0), n, g)
		# The cab door's outline, handle, and a mirror on two arms.
		_door_outline(b, hw, s, cz0 - 0.12, cz1 + 0.05, low + 0.1, 1.98)
		b._detail = true
		b._bev("rough", Vector3(x + 0.012 * s, 1.05, cz1 - 0.12), Vector3(0.012, 0.025, 0.08), 0.01, TruckBuilder.DARK)
		b._detail = false
		var head := Vector3((hw + 0.24) * s, 1.55, cz0 + 0.05)
		b._rod("rough", [Vector3(hw * s, 1.32, cz0 + 0.02), Vector3((hw + 0.2) * s, 1.38, cz0 + 0.04)], 0.012, TruckBuilder.RUBBER)
		b._bev("rough", head, Vector3(0.04, 0.17, 0.08), 0.02, TruckBuilder.RUBBER)
		b._plate("metal", head + Vector3(0, 0, 0.081), 0.07, 0.3, Vector3.BACK, TruckBuilder.MIRROR)
	# The curb side's sliding door, with its window.
	var sd0 := -1.05
	var sd1 := 0.35
	_door_outline(b, hw, 1.0, sd0, sd1, low + 0.1, 2.12)
	b._quad("glass", Vector3(hw + 0.004, 1.35, sd0 + 0.15), Vector3(hw + 0.004, 1.35, sd1 - 0.15), Vector3(hw + 0.004, 1.95, sd1 - 0.15), Vector3(hw + 0.004, 1.95, sd0 + 0.15), Vector3.RIGHT, g)
	b._detail = true
	b._box("rough", Vector3(hw + 0.006, 2.16, (sd0 + sd1) * 0.5 + 0.4), Vector3(0.01, 0.02, sd1 - sd0 + 0.8), TruckBuilder.DARK) # its track
	b._detail = false
	# The livery: a dark green stripe over a lime band, low down, the whole
	# length; the lime panel high behind the cab (PARAMEDIC goes on it);
	# lime across the front of the roof (the name, mirrored).
	for s: float in [-1.0, 1.0]:
		var x := (hw + 0.003) * s
		var n := Vector3(s, 0, 0)
		b._quad("gloss", Vector3(x, 0.66, nose + 0.35), Vector3(x, 0.66, back - 0.03), Vector3(x, 0.92, back - 0.03), Vector3(x, 0.92, nose + 0.35), n, LIME)
		b._quad("gloss", Vector3(x, 0.92, nose + 0.3), Vector3(x, 0.92, back - 0.03), Vector3(x, 1.06, back - 0.03), Vector3(x, 1.06, nose + 0.3), n, GREEN)
		b._quad("gloss", Vector3(x + 0.001 * s, 2.3, -1.15), Vector3(x + 0.001 * s, 2.3, 0.85), Vector3(x + 0.001 * s, 2.68, 0.85), Vector3(x + 0.001 * s, 2.68, -1.15), n, LIME)
	var hz: float = rz.call(2.38) - 0.008
	var hz2: float = rz.call(2.7) - 0.008
	b._quad("gloss", Vector3(-hw + 0.08, 2.38, hz), Vector3(hw - 0.08, 2.38, hz), Vector3(hw - 0.08, 2.7, hz2), Vector3(-hw + 0.08, 2.7, hz2), n_ws, LIME)
	# The nose: grille, headlamps, bumper, plate.
	var gz := nose + 0.02
	b._prof("rough", -0.42, 0.42, Vector2(gz, 0.62), Vector2(gz + 0.1, 0.62), Vector2(gz + 0.16, 0.92), Vector2(gz + 0.06, 0.92), Color(0.05, 0.05, 0.055))
	b._detail = true
	for i in 3:
		b._box("metal", Vector3(0, 0.7 + i * 0.08, gz + 0.02), Vector3(0.8, 0.018, 0.02), TruckBuilder.CHROME)
	b._detail = false
	b._disc("metal", Vector3(0, 0.78, gz - 0.005), 0.07, Vector3.FORWARD, TruckBuilder.CHROME, 16)
	for s: float in [-1.0, 1.0]:
		b._lamp(Vector3(0.68 * s, 0.86, nose + 0.12), 0.32, 0.12, Vector3.FORWARD, TruckBuilder.LAMP, TruckBuilder.DARK)
		b._lamp(Vector3(0.68 * s, 0.74, nose + 0.12), 0.18, 0.04, Vector3.FORWARD, TruckBuilder.AMBER, TruckBuilder.DARK)
	b._bev("rough", Vector3(0, 0.48, nose + 0.06), Vector3(hw - 0.02, 0.1, 0.1), 0.05, Color(0.16, 0.16, 0.17))
	b._plate("gloss", Vector3(0.0, 0.48, nose - 0.042), 0.3, 0.15, Vector3.FORWARD, Color(0.92, 0.92, 0.88))
	# The back: two doors with windows, checks on the lower half, tall
	# lamps up the corners, the step and the plate.
	var bz := back + 0.003
	for s: float in [-1.0, 1.0]:
		var x0 := 0.03 * s
		var x1 := (hw - 0.14) * s
		b._quad("glass", Vector3(x1, 1.55, bz), Vector3(x0 + 0.08 * s, 1.55, bz), Vector3(x0 + 0.08 * s, 2.15, bz), Vector3(x1, 2.15, bz), Vector3.BACK, g)
		var cs := 0.16
		var i := 0
		var cy := 0.62
		while cy + cs <= 1.3:
			var j := i
			var cx := 0.04
			while cx + cs <= hw - 0.16:
				var col := LIME if j % 2 == 0 else GREEN
				var xa := cx * s
				var xb := (cx + cs) * s
				b._quad("gloss", Vector3(maxf(xa, xb), cy, bz), Vector3(minf(xa, xb), cy, bz), Vector3(minf(xa, xb), cy + cs, bz), Vector3(maxf(xa, xb), cy + cs, bz), Vector3.BACK, col)
				cx += cs
				j += 1
			cy += cs
			i += 1
		var tx := (hw - 0.07) * s
		b._lamp(Vector3(tx, 1.15, bz + 0.012), 0.08, 0.3, Vector3.BACK, TruckBuilder.RED, TruckBuilder.RUBBER)
		b._lamp(Vector3(tx, 0.92, bz + 0.012), 0.08, 0.12, Vector3.BACK, TruckBuilder.AMBER, TruckBuilder.RUBBER)
		b._lamp(Vector3(tx, 0.78, bz + 0.012), 0.08, 0.1, Vector3.BACK, TruckBuilder.LAMP, TruckBuilder.RUBBER)
		b._detail = true
		b._bev("rough", Vector3(0.12 * s, 1.35, bz + 0.012), Vector3(0.06, 0.018, 0.012), 0.008, TruckBuilder.DARK)
		b._detail = false
	b._detail = true
	b._box("paint", Vector3(0, (low + roof) * 0.5, bz), Vector3(0.008, roof - low - 0.2, 0.008), b.paint.darkened(0.5))
	b._detail = false
	b._box("steel", Vector3(0, 0.45, back + 0.16), Vector3(1.5, 0.08, 0.3), TruckBuilder.DARK)
	b._diamonds(Vector3(0, 0.491, back + 0.16), Vector3.RIGHT * 1.46, Vector3.BACK * 0.28, Vector3.UP, TruckBuilder.GALV)
	b._plate("gloss", Vector3(0.0, 0.58, bz + 0.002), 0.3, 0.15, Vector3.BACK, Color(0.92, 0.92, 0.88))
	# The roof: the air conditioner, and the light housings at the corners
	# (the lenses are EmergencyGear's).
	b._bev("paint", Vector3(0.0, roof + 0.09, 1.2), Vector3(0.4, 0.09, 0.5), 0.04, WHITE.darkened(0.05))
	for s: float in [-1.0, 1.0]:
		b._box("rough", Vector3((hw - 0.2) * s, roof + 0.05, cap + 0.25), Vector3(0.34, 0.1, 0.2), TruckBuilder.RUBBER)
		b._box("rough", Vector3((hw - 0.2) * s, roof - 0.1, back - 0.04), Vector3(0.3, 0.14, 0.1), TruckBuilder.RUBBER)


## How far a wheel well reaches either side of the axle (m).
static func ar_r(wr: float) -> float:
	return wr + 0.12


## A door's outline (a dark seam) on the side of a box at x = ±hw.
static func _door_outline(b: TruckBuilder, hw: float, s: float, z0: float, z1: float, y0: float, y1: float) -> void:
	var x := (hw + 0.002) * s
	var seam := b.paint.darkened(0.45)
	b._detail = true
	b._box("paint", Vector3(x, (y0 + y1) * 0.5, z0), Vector3(0.006, y1 - y0, 0.008), seam)
	b._box("paint", Vector3(x, (y0 + y1) * 0.5, z1), Vector3(0.006, y1 - y0, 0.008), seam)
	b._box("paint", Vector3(x, y0, (z0 + z1) * 0.5), Vector3(0.006, 0.008, z1 - z0), seam)
	b._box("paint", Vector3(x, y1, (z0 + z1) * 0.5), Vector3(0.006, 0.008, z1 - z0), seam)
	b._detail = false


# --- the Island Wee-Woo Brigade --------------------------------------------------------------

## A pumper: a flat-fronted crew cab over the front axle, the pump panel
## behind it with its gauges and valves, roll-up compartment doors down
## both sides, the hose bed and the ladder on top, the deck gun, and the
## tailboard at the back.
static func fire_engine(b: TruckBuilder) -> void:
	var hw := float(b.shape["width"]) * 0.5 - 0.02
	var fa := float(b.shape["front_axle"])
	var ra := float(b.shape["rear_axle"])
	var wr := float(b.shape["wheel_radius"])
	var front := -4.85
	# The cab, flat-fronted, sitting up over the front wheels.
	b._cab({"hw": hw, "cz0": front + 0.08, "cz1": -2.38, "y0": 1.12, "roof": 3.0, "rake": 0.14, "floor": 1.2, "belt": 2.02,
		"door": 0.42, "steps": [0.5, 0.86], "clutch": false, "trim": "#3a3c40", "dash": "#1e1f21", "seat": "#1d1d20", "cloth": "#2e3034"})
	# Below the cab: the front, the fenders over the wheels, the skirts.
	var cy0 := 1.12
	b._box("paint", Vector3(0, (0.48 + cy0) * 0.5, front + 0.2), Vector3(hw * 2.0, cy0 - 0.48, 0.32), b.paint)
	var ar := wr + 0.16
	for s: float in [-1.0, 1.0]:
		var xi := (hw - 0.35) * s
		var xo := hw * s
		b._arch("paint", fa, wr + 0.02, wr + 0.08, ar, minf(xi, xo), maxf(xi, xo), 0.0, PI, b.paint, 16)
		b._arch("rough", fa, wr + 0.02, wr + 0.06, wr + 0.08, minf(xi, xo) + 0.01, maxf(xi, xo) - 0.01, 0.0, PI, TruckBuilder.RUBBER, 12)
		# Panels in front of and behind the arch, down to the skirt.
		b._box("paint", Vector3((hw - 0.175) * s, (0.48 + cy0) * 0.5, (front + 0.36 + fa - ar) * 0.5), Vector3(0.35, cy0 - 0.48, fa - ar - front - 0.36), b.paint)
		b._box("paint", Vector3((hw - 0.175) * s, (0.62 + cy0) * 0.5, (fa + ar - 2.38) * 0.5), Vector3(0.35, cy0 - 0.62, -2.38 - fa - ar), b.paint)
	# The front: a chrome grille plate, quad headlamps, turn signals, the
	# long chrome bumper with its centre hose well, and the siren speaker.
	b._bev("metal", Vector3(0, 0.84, front - 0.005), Vector3(0.62, 0.22, 0.02), 0.02, TruckBuilder.CHROME)
	b._detail = true
	for i in 7:
		b._box("rough", Vector3(0, 0.68 + i * 0.05, front - 0.028), Vector3(1.12, 0.018, 0.01), TruckBuilder.DARK)
	b._detail = false
	for s: float in [-1.0, 1.0]:
		for lx: float in [0.82, 1.02]:
			b._lamp(Vector3(lx * s, 0.95, front - 0.02), 0.15, 0.15, Vector3.FORWARD, TruckBuilder.LAMP, TruckBuilder.CHROME, true)
		b._lamp(Vector3(0.92 * s, 0.72, front - 0.02), 0.3, 0.07, Vector3.FORWARD, TruckBuilder.AMBER, TruckBuilder.CHROME)
	var bump_z := front - 0.32
	b._bev("metal", Vector3(0, 0.5, bump_z), Vector3(hw + 0.02, 0.13, 0.3), 0.04, TruckBuilder.CHROME)
	b._box("rough", Vector3(0, 0.64, bump_z + 0.02), Vector3(1.0, 0.02, 0.5), TruckBuilder.DARK)
	for i in 3:
		b._box("rough", Vector3(-0.3 + i * 0.3, 0.68, bump_z), Vector3(0.24, 0.06, 0.42), HOSE_RED.darkened(0.1 * i))
	b._cyl("rough", Vector3(-0.62, 0.5, bump_z - 0.31), Vector3(-0.62, 0.5, bump_z - 0.33), 0.14, TruckBuilder.DARK, 14)
	b._detail = true
	b._disc("metal", Vector3(-0.62, 0.5, bump_z - 0.335), 0.12, Vector3.FORWARD, TruckBuilder.STEEL, 14)
	b._detail = false
	# The frame and axles.
	b._frame(front + 0.1, 4.75, 0.98)
	b._front_axle(fa, wr, 1.04, 0.98, front + 0.5, -2.8)
	b._drive_axle(ra, wr, 0.9, 0.98)
	b._cyl("steel", Vector3(0, 0.56, -2.6), Vector3(0, 0.54, ra - 0.2), 0.05, TruckBuilder.STEEL, 10)
	# The body: the upper boxes the length of it, lower ones either side of
	# the rear wheels, the fender between them.
	var eb: Dictionary = ENG_BODY
	var z0 := float(eb["z0"])
	var z1 := float(eb["z1"])
	var y0 := float(eb["y0"])
	var y1 := float(eb["y1"])
	var bw := float(eb["hw"])
	var well0 := ra - ar - 0.05
	var well1 := ra + ar + 0.05
	var mid := wr * 2.0 + 0.1 # the top of the wheel well
	b._bev("paint", Vector3(0, (mid + y1) * 0.5, (z0 + z1) * 0.5), Vector3(bw, (y1 - mid) * 0.5, (z1 - z0) * 0.5), 0.03, b.paint)
	b._box("paint", Vector3(0, (y0 + mid) * 0.5, (z0 + well0) * 0.5), Vector3(bw * 2.0, mid - y0, well0 - z0), b.paint)
	b._box("paint", Vector3(0, (y0 + mid) * 0.5, (well1 + z1) * 0.5), Vector3(bw * 2.0, mid - y0, z1 - well1), b.paint)
	b._box("rough", Vector3(0, (y0 + mid) * 0.5, ra), Vector3(1.0, mid - y0, well1 - well0), TruckBuilder.DARK)
	for s: float in [-1.0, 1.0]:
		var xo := (bw + 0.02) * s
		var xi := (bw - 0.42) * s
		b._arch("metal", ra, wr + 0.02, ar - 0.06, ar, minf(xi, xo), maxf(xi, xo), 0.0, PI, TruckBuilder.CHROME, 16)
	# The white band down the sides and the gold line under it.
	for s: float in [-1.0, 1.0]:
		var x := (bw + 0.003) * s
		var n := Vector3(s, 0, 0)
		b._quad("gloss", Vector3(x, 2.18, z0 + 0.05), Vector3(x, 2.18, z1 - 0.05), Vector3(x, 2.34, z1 - 0.05), Vector3(x, 2.34, z0 + 0.05), n, WHITE)
		b._quad("gloss", Vector3(x, 2.15, z0 + 0.05), Vector3(x, 2.15, z1 - 0.05), Vector3(x, 2.17, z1 - 0.05), Vector3(x, 2.17, z0 + 0.05), n, Color(0.9, 0.72, 0.2))
		# On the cab, the band carries on.
		var cx := (hw + 0.003) * s
		b._quad("gloss", Vector3(cx, 1.5, front + 0.25), Vector3(cx, 1.5, -2.42), Vector3(cx, 1.66, -2.42), Vector3(cx, 1.66, front + 0.25), n, WHITE)
	# The pump panel: chrome behind the cab, gauges and valve handles, the
	# intake on its side.
	var pz0 := z0 + 0.06
	var pz1 := z0 + 0.9
	for s: float in [-1.0, 1.0]:
		var x := (bw + 0.006) * s
		var n := Vector3(s, 0, 0)
		b._quad("metal", Vector3(x, 0.75, pz0), Vector3(x, 0.75, pz1), Vector3(x, 2.1, pz1), Vector3(x, 2.1, pz0), n, TruckBuilder.CHROME)
		b._cyl("metal", Vector3(x, 1.0, (pz0 + pz1) * 0.5), Vector3(x + 0.2 * s, 1.0, (pz0 + pz1) * 0.5), 0.12, TruckBuilder.CHROME, 16)
		b._detail = true
		b._ring("metal", Vector3(x + 0.205 * s, 1.0, (pz0 + pz1) * 0.5), 0.08, 0.12, n, TruckBuilder.STEEL, 14)
		for i in 4:
			var gz := pz0 + 0.14 + i * 0.19
			b._disc("gloss", Vector3(x + 0.004 * s, 1.85, gz), 0.06, n, Color(0.95, 0.95, 0.92), 14)
			b._ring("metal", Vector3(x + 0.005 * s, 1.85, gz), 0.06, 0.07, n, TruckBuilder.CHROME, 14)
			b._box("rough", Vector3(x + 0.007 * s, 1.87, gz), Vector3(0.004, 0.04, 0.006), TruckBuilder.DARK)
		for i in 3:
			var vz := pz0 + 0.2 + i * 0.25
			var col := [STRIPE_RED, Color(0.15, 0.3, 0.75), Color(0.95, 0.78, 0.1)][i] as Color
			b._rod("metal", [Vector3(x, 1.5, vz), Vector3(x + 0.12 * s, 1.5, vz), Vector3(x + 0.12 * s, 1.38, vz)], 0.012, TruckBuilder.CHROME)
			b._bev("gloss", Vector3(x + 0.12 * s, 1.35, vz), Vector3(0.02, 0.03, 0.02), 0.015, col)
		b._detail = false
	# Roll-up compartment doors (brushed aluminium, ribbed), the latch bar
	# at the foot of each.
	var doors := [[pz1 + 0.08, well0 - 0.08, y0 + 0.08, 2.08], [well0 + 0.05, well1 - 0.05, mid + 0.06, 2.08], [well1 + 0.08, z1 - 0.12, y0 + 0.08, 2.08]]
	for s: float in [-1.0, 1.0]:
		var x := (bw + 0.004) * s
		var n := Vector3(s, 0, 0)
		for d: Array in doors:
			var dz0 := float(d[0])
			var dz1 := float(d[1])
			var dy0 := float(d[2])
			var dy1 := float(d[3])
			b._quad("satin", Vector3(x, dy0, dz0), Vector3(x, dy0, dz1), Vector3(x, dy1, dz1), Vector3(x, dy1, dz0), n, ALU)
			b._box("metal", Vector3(x + 0.01 * s, dy0 + 0.06, (dz0 + dz1) * 0.5), Vector3(0.02, 0.05, dz1 - dz0 - 0.1), TruckBuilder.CHROME)
			b._detail = true
			var y := dy0 + 0.12
			while y < dy1 - 0.02:
				b._quad("satin", Vector3(x + 0.002 * s, y, dz0 + 0.01), Vector3(x + 0.002 * s, y, dz1 - 0.01), Vector3(x + 0.002 * s, y + 0.008, dz1 - 0.01), Vector3(x + 0.002 * s, y + 0.008, dz0 + 0.01), n, ALU.darkened(0.25))
				y += 0.06
			b._detail = false
	# The top: a walkway of diamond plate behind the cab, the deck gun, the
	# hose bed with its folds of hose, and the ladder on its rack.
	b._tread(Vector3(0, y1 + 0.006, pz0 + 0.45), bw * 2.0 - 0.1, 0.85)
	var gun := Vector3(0.0, y1 + 0.02, pz0 + 0.45)
	b._cyl("metal", gun, gun + Vector3.UP * 0.22, 0.09, TruckBuilder.CHROME, 14)
	b._bev("paint", gun + Vector3(0, 0.3, 0), Vector3(0.09, 0.09, 0.09), 0.07, Color(0.9, 0.72, 0.2))
	b._cyl("metal", gun + Vector3(0, 0.3, 0), gun + Vector3(0, 0.48, -0.32), 0.06, TruckBuilder.CHROME, 12)
	b._cone("metal", gun + Vector3(0, 0.48, -0.32), gun + Vector3(0, 0.56, -0.62), 0.065, 0.035, TruckBuilder.CHROME, 12)
	var hz0 := pz1 + 0.15
	var hz1 := z1 - 0.05
	for s: float in [-1.0, 1.0]:
		b._box("metal", Vector3((bw - 0.03) * s, y1 + 0.12, (hz0 + hz1) * 0.5), Vector3(0.05, 0.24, hz1 - hz0), TruckBuilder.CHROME)
	for i in 4:
		var x := -0.8 + i * 0.53
		b._bev("rough", Vector3(x, y1 + 0.1, (hz0 + hz1) * 0.5 + 0.1), Vector3(0.24, 0.1, (hz1 - hz0) * 0.5 - 0.05), 0.06, HOSE_YELLOW if i % 2 == 0 else HOSE_RED)
	b._detail = true
	for i in 4:
		var x := -0.8 + i * 0.53
		var z := hz0 + 0.2
		while z < hz1 - 0.1:
			b._box("rough", Vector3(x, y1 + 0.205, z), Vector3(0.46, 0.006, 0.02), (HOSE_YELLOW if i % 2 == 0 else HOSE_RED).darkened(0.25))
			z += 0.3
	b._detail = false
	# The ladder, on a rack over the driver's side.
	var lx := -bw + 0.25
	var ly := y1 + 0.42
	var lz0 := pz0 + 0.1
	var lz1 := z1 + 0.15
	for rx: float in [lx - 0.2, lx + 0.2]:
		b._box("metal", Vector3(rx, ly, (lz0 + lz1) * 0.5), Vector3(0.05, 0.09, lz1 - lz0), ALU)
	b._detail = true
	var rz := lz0 + 0.15
	while rz < lz1 - 0.1:
		b._cyl("metal", Vector3(lx - 0.18, ly, rz), Vector3(lx + 0.18, ly, rz), 0.016, ALU, 6)
		rz += 0.3
	b._detail = false
	for z: float in [lz0 + 0.3, (lz0 + lz1) * 0.5, lz1 - 0.4]:
		b._box("steel", Vector3(lx, (y1 + ly) * 0.5 - 0.04, z), Vector3(0.5, ly - y1 - 0.05, 0.06), TruckBuilder.DARK)
	# The back: the tailboard step, the hose bed's open end, grab rails,
	# lamps, chevrons on the back of the body.
	b._box("steel", Vector3(0, 0.5, z1 + 0.22), Vector3(bw * 2.0, 0.12, 0.44), TruckBuilder.DARK)
	b._diamonds(Vector3(0, 0.561, z1 + 0.22), Vector3.RIGHT * (bw * 2.0 - 0.04), Vector3.BACK * 0.42, Vector3.UP, TruckBuilder.GALV)
	var tz := z1 + 0.003
	for i in 6:
		var cy := y0 + 0.15 + i * 0.12
		var col := Color(0.95, 0.78, 0.1) if i % 2 == 0 else STRIPE_RED
		for s: float in [-1.0, 1.0]:
			var ax := 0.08 * s
			var bx := (bw - 0.1) * s
			b._quad("gloss", Vector3(bx, cy + 0.08, tz), Vector3(ax, cy, tz), Vector3(ax, cy + 0.12, tz), Vector3(bx, cy + 0.2, tz), Vector3.BACK, col)
	for s: float in [-1.0, 1.0]:
		b._rod("metal", [Vector3(0.7 * s, 1.1, z1), Vector3(0.7 * s, 1.1, z1 + 0.08), Vector3(0.7 * s, 2.0, z1 + 0.08), Vector3(0.7 * s, 2.0, z1)], 0.016, TruckBuilder.CHROME)
		var tx := (bw - 0.1) * s
		b._lamp(Vector3(tx, 1.95, tz + 0.012), 0.14, 0.14, Vector3.BACK, TruckBuilder.RED, TruckBuilder.RUBBER, true)
		b._lamp(Vector3(tx, 1.75, tz + 0.012), 0.14, 0.14, Vector3.BACK, TruckBuilder.AMBER, TruckBuilder.RUBBER, true)
		b._lamp(Vector3(tx, 1.56, tz + 0.012), 0.11, 0.11, Vector3.BACK, TruckBuilder.LAMP, TruckBuilder.RUBBER, true)
	b._plate("gloss", Vector3(0.0, 0.75, tz + 0.002), 0.3, 0.15, Vector3.BACK, Color(0.92, 0.92, 0.88))
	b._plate("gloss", Vector3(0.0, 0.75, tz + 0.004), 0.26, 0.03, Vector3.BACK, Color(0.12, 0.28, 0.2))
	# The cab roof: a black light bar housing (the lenses are the gear's),
	# an air horn either side, and a light housing at each top corner of
	# the body.
	b._bev("rough", Vector3(0, 3.04, front + 0.55), Vector3(0.95, 0.04, 0.16), 0.02, TruckBuilder.DARK)
	for s: float in [-1.0, 1.0]:
		b._cone("metal", Vector3(0.55 * s, 3.08, front + 0.85), Vector3(0.55 * s, 3.08, front + 0.45), 0.03, 0.07, TruckBuilder.CHROME, 10)
		for z: float in [z0 + 0.05, z1 - 0.05]:
			b._box("rough", Vector3((bw - 0.1) * s, y1 - 0.1, z), Vector3(0.16, 0.16, 0.06), TruckBuilder.RUBBER)

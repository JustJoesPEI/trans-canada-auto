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
	# Hollow behind the hood, so the cab and the patient compartment have
	# room down to their floors: walls along the sides, the firewall and
	# the back, each a few centimetres thick (the tops of the side walls
	# are the window sills).
	for sx: float in [-1.0, 1.0]:
		b._prof("paint", (hw - 0.03) * sx, hw * sx, Vector2(ws, sill), Vector2(back, sill), Vector2(back, belt), Vector2(ws, belt), b.paint, 0.0)
	b._prof("paint", -hw, hw, Vector2(ws - 0.03, sill), Vector2(ws, sill), Vector2(ws, belt), Vector2(ws - 0.03, belt), b.paint, 0.0)
	b._prof("paint", -hw, hw, Vector2(back - 0.03, sill), Vector2(back, sill), Vector2(back, belt), Vector2(back - 0.03, belt), b.paint, 0.0)
	# The nose: the hood falling to the bumper.
	# The nose: full width up to the headlamps, so the band runs on along
	# it flush; then the hood, short and steep, rounded at its shoulders,
	# into the foot of the windscreen.
	_van_nose(b, hw, nose, ws, low + 0.1, belt)
	for seg: Array in [[nose + 0.3, fa - wa], [fa + wa, ra - wa], [ra + wa, back]]:
		var z0 := float(seg[0])
		var z1 := float(seg[1])
		b._box("paint", Vector3(0, (low + sill) * 0.5, (z0 + z1) * 0.5), Vector3(hw * 2.0, sill - low, z1 - z0), b.paint)
	for z: float in [fa, ra]:
		b._box("rough", Vector3(0, (low + sill) * 0.5, z), Vector3(hw * 2.0 - 0.6, sill - low, wa * 2.0), TruckBuilder.DARK)
		for s: float in [-1.0, 1.0]:
			# A black liner inside the opening, and a body-coloured lip round
			# it standing a little proud of the side.
			b._arch("rough", z, wr + 0.04, wa - 0.04, wa, minf((hw - 0.3) * s, (hw - 0.01) * s), maxf((hw - 0.3) * s, (hw - 0.01) * s), 0.0, PI, Color(0.05, 0.05, 0.055), 16)
			b._arch("paint", z, wr + 0.04, wa, wa + 0.05, minf((hw - 0.04) * s, (hw + 0.025) * s), maxf((hw - 0.04) * s, (hw + 0.025) * s), 0.0, PI, b.paint, 16)
			# Mud flap behind the wheel.
			b._box("rough", Vector3((hw - 0.15) * s, 0.42, z + wa - 0.02), Vector3(0.26, 0.32, 0.012), TruckBuilder.RUBBER)
	# Upper body: lofted back from the windscreen's foot, up its rake to
	# the high roof, with the roof's edges rounded over as a van's are
	# (crisp at the A-pillars, where the glass is flat).
	var rz := func(y: float) -> float: return ws + (cap - ws) * (y - belt) / (roof - belt)
	# Glass: the windscreen, the cab's side windows, one in the side door
	# and two in the back doors.
	var wt := 2.02
	var g := Color(0.07, 0.09, 0.11, 0.55)
	var n_ws := Vector3(0, cap - ws, -(roof - belt)).normalized()
	b._quad("glass", Vector3(-hw + 0.1, belt + 0.06, rz.call(belt + 0.06) - 0.01), Vector3(hw - 0.1, belt + 0.06, rz.call(belt + 0.06) - 0.01),
		Vector3(hw - 0.12, wt, rz.call(wt) - 0.01), Vector3(-hw + 0.12, wt, rz.call(wt) - 0.01), n_ws, g)
	# A black rubber surround round the windscreen, and the A-pillars.
	var ofs := n_ws * 0.004
	for y: float in [belt + 0.05, wt + 0.01]:
		b._quad("rough", Vector3(-hw + 0.08, y - 0.02, rz.call(y - 0.02)) + ofs, Vector3(hw - 0.08, y - 0.02, rz.call(y - 0.02)) + ofs,
			Vector3(hw - 0.08, y + 0.02, rz.call(y + 0.02)) + ofs, Vector3(-hw + 0.08, y + 0.02, rz.call(y + 0.02)) + ofs, n_ws, TruckBuilder.RUBBER)
	for s: float in [-1.0, 1.0]:
		var xa := (hw - 0.13) * s
		var xb := (hw - 0.02) * s
		b._quad("rough", Vector3(minf(xa, xb), belt + 0.05, rz.call(belt + 0.05)) + ofs, Vector3(maxf(xa, xb), belt + 0.05, rz.call(belt + 0.05)) + ofs,
			Vector3(maxf(xa, xb), wt + 0.02, rz.call(wt + 0.02)) + ofs, Vector3(minf(xa, xb), wt + 0.02, rz.call(wt + 0.02)) + ofs, n_ws, Color(0.06, 0.06, 0.065))
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
		_door_outline(b, hw, s, cz0 - 0.12, cz1 + 0.05, sill + 0.03, 1.98)
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
	# The upper body, with openings where the glass is: the cab's side
	# windows, the side door's, the two in the back doors.
	var side_windows := []
	for s: float in [-1.0, 1.0]:
		side_windows.append([s, cz0, cz1, belt + 0.08, 1.95])
	side_windows.append([1.0, sd0 + 0.15, sd1 - 0.15, 1.35, 1.95])
	var back_windows := []
	for s: float in [-1.0, 1.0]:
		back_windows.append([minf(0.11 * s, (hw - 0.14) * s), maxf(0.11 * s, (hw - 0.14) * s), 1.55, 2.15])
	_van_upper(b, hw, ws, cap, back, belt, roof, side_windows, back_windows)
	_door_outline(b, hw, 1.0, sd0, sd1, low + 0.18, 2.12)
	b._tread(Vector3(hw - 0.1, low - 0.02, (sd0 + sd1) * 0.5), 0.24, sd1 - sd0 - 0.1)
	# The patient compartment's windows are a lighter tint, so the
	# stretcher and cabinets show through.
	var g2 := Color(0.08, 0.1, 0.12, 0.5)
	b._quad("glass", Vector3(hw + 0.004, 1.35, sd0 + 0.15), Vector3(hw + 0.004, 1.35, sd1 - 0.15), Vector3(hw + 0.004, 1.95, sd1 - 0.15), Vector3(hw + 0.004, 1.95, sd0 + 0.15), Vector3.RIGHT, g2)
	b._detail = true
	b._box("rough", Vector3(hw + 0.006, 2.16, (sd0 + sd1) * 0.5 + 0.4), Vector3(0.01, 0.02, sd1 - sd0 + 0.8), TruckBuilder.DARK) # its track
	b._detail = false
	# The livery: a dark green stripe over a lime band, low down, the whole
	# length; the lime panel high behind the cab (PARAMEDIC goes on it);
	# lime across the front of the roof (the name, mirrored).
	for s: float in [-1.0, 1.0]:
		var x := (hw + 0.003) * s
		var n := Vector3(s, 0, 0)
		# Above the wheel lips, from the cab back: a wide lime band with a
		# dark green line along its top.
		b._quad("gloss", Vector3(x, 0.98, ws + 0.03), Vector3(x, 0.98, back - 0.03), Vector3(x, 1.16, back - 0.03), Vector3(x, 1.16, ws + 0.03), n, LIME)
		b._quad("gloss", Vector3(x, 1.16, ws + 0.03), Vector3(x, 1.16, back - 0.03), Vector3(x, 1.23, back - 0.03), Vector3(x, 1.23, ws + 0.03), n, GREEN)
		# Below them, between the wheels: a black rocker panel and a step
		# under the side door.
		b._quad("rough", Vector3(x, low + 0.02, fa + wa + 0.08), Vector3(x, low + 0.02, ra - wa - 0.08), Vector3(x, low + 0.16, ra - wa - 0.08), Vector3(x, low + 0.16, fa + wa + 0.08), n, Color(0.12, 0.12, 0.13))
		b._quad("gloss", Vector3(x + 0.001 * s, 2.3, -1.15), Vector3(x + 0.001 * s, 2.3, 0.85), Vector3(x + 0.001 * s, 2.6, 0.85), Vector3(x + 0.001 * s, 2.6, -1.15), n, LIME)
	var hz: float = rz.call(2.38) - 0.008
	var hz2: float = rz.call(2.7) - 0.008
	b._quad("gloss", Vector3(-hw + 0.08, 2.38, hz), Vector3(hw - 0.08, 2.38, hz), Vector3(hw - 0.08, 2.7, hz2), Vector3(-hw + 0.08, 2.7, hz2), n_ws, LIME)
	# The Star of Life, big, behind the IBBB on each side.
	for s: float in [-1.0, 1.0]:
		star_of_life(b, hw, s, 2.78, 1.78, 0.38)
	# The nose: grille, headlamps, bumper, plate.
	var gz := nose - 0.035
	b._prof("rough", -0.42, 0.42, Vector2(gz, 0.62), Vector2(gz + 0.1, 0.62), Vector2(gz + 0.16, 0.92), Vector2(gz + 0.06, 0.92), Color(0.05, 0.05, 0.055))
	b._detail = true
	for i in 3:
		b._box("metal", Vector3(0, 0.7 + i * 0.08, gz + 0.02), Vector3(0.8, 0.018, 0.02), TruckBuilder.CHROME)
	b._detail = false
	b._disc("metal", Vector3(0, 0.78, gz - 0.005), 0.07, Vector3.FORWARD, TruckBuilder.CHROME, 16)
	for y: float in [0.6, 0.94]:
		b._bev("metal", Vector3(0, y, gz - 0.005), Vector3(0.46, 0.022, 0.02), 0.012, TruckBuilder.CHROME)
	for x: float in [-0.45, 0.45]:
		b._bev("metal", Vector3(x, 0.77, gz - 0.005), Vector3(0.022, 0.18, 0.02), 0.012, TruckBuilder.CHROME)
	for s: float in [-1.0, 1.0]:
		# Headlamp units flush on the corners: dark chrome housings on the
		# front and wrapping back along the side, the lamps in them, the
		# turn signal at the outer edge.
		var hx := 0.7 * s
		b._plate("gloss", Vector3(hx, 0.86, nose - 0.004), 0.42, 0.2, Vector3.FORWARD, Color(0.2, 0.21, 0.23))
		b._plate("gloss", Vector3((nose_hw(hw, nose, nose + 0.24) + 0.003) * s, 0.86, nose + 0.24), 0.2, 0.2, Vector3(s, 0, 0), Color(0.2, 0.21, 0.23))
		for k: float in [-0.08, 0.06]:
			b._disc("gloss", Vector3(hx + k * s, 0.87, nose - 0.008), 0.055, Vector3.FORWARD, TruckBuilder.LAMP, 14)
			b._ring("metal", Vector3(hx + k * s, 0.87, nose - 0.009), 0.055, 0.068, Vector3.FORWARD, TruckBuilder.CHROME, 14)
		b._plate("gloss", Vector3(hx + 0.16 * s, 0.86, nose - 0.008), 0.07, 0.15, Vector3.FORWARD, TruckBuilder.AMBER)
		b._plate("gloss", Vector3(hw * s + 0.005 * s, 0.86, nose + 0.3), 0.1, 0.15, Vector3(s, 0, 0), TruckBuilder.AMBER)
		b._disc("gloss", Vector3(0.62 * s, 0.5, nose - 0.075), 0.05, Vector3.FORWARD, TruckBuilder.LAMP, 12)
	# A two-tone bumper: black lower, wrapping round, a step in the middle.
	b._bev("rough", Vector3(0, 0.5, nose + 0.04), Vector3(hw - 0.01, 0.12, 0.12), 0.06, Color(0.14, 0.14, 0.15))
	for s: float in [-1.0, 1.0]:
		b._bev("rough", Vector3((hw - 0.08) * s, 0.5, nose + 0.24), Vector3(0.08, 0.12, 0.16), 0.05, Color(0.14, 0.14, 0.15))
	b._plate("gloss", Vector3(0.0, 0.48, nose - 0.042), 0.3, 0.15, Vector3.FORWARD, Color(0.92, 0.92, 0.88))
	# The back: two doors with windows, checks on the lower half, tall
	# lamps up the corners, the step and the plate.
	var bz := back + 0.003
	for s: float in [-1.0, 1.0]:
		var x0 := 0.03 * s
		var x1 := (hw - 0.14) * s
		b._quad("glass", Vector3(x1, 1.55, bz), Vector3(x0 + 0.08 * s, 1.55, bz), Vector3(x0 + 0.08 * s, 2.15, bz), Vector3(x1, 2.15, bz), Vector3.BACK, g2)
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
	# The light bar across the front of the roof: a black base on feet (the
	# lenses on it are EmergencyGear's), and housings at the back corners.
	b._bev("rough", Vector3(0, roof + 0.04, cap + 0.27), Vector3(0.92, 0.035, 0.13), 0.02, TruckBuilder.DARK)
	for s: float in [-1.0, 1.0]:
		b._box("rough", Vector3(0.7 * s, roof + 0.01, cap + 0.27), Vector3(0.06, 0.03, 0.3), TruckBuilder.DARK)
		b._box("rough", Vector3((hw - 0.2) * s, roof - 0.1, back - 0.04), Vector3(0.3, 0.14, 0.1), TruckBuilder.RUBBER)
	_ambulance_details(b, hw, back, belt, roof, low, sd0, sd1, cz1)
	_ambulance_inside(b, hw, ws, back, belt, roof, low)


## Half the nose's width at z: the front corners rounded off in plan.
static func nose_hw(hw: float, nose: float, z: float) -> float:
	var t := clampf((z - nose) / 0.28, 0.0, 1.0)
	return hw - 0.08 * (1.0 - sqrt(1.0 - (1.0 - t) * (1.0 - t)))


## The van's nose as a loft from the bumper face back to the foot of the
## windscreen: the hood low at the front and rising to the glass, its
## shoulders rolled over, the front corners rounded in plan.
static func _van_nose(b: TruckBuilder, hw: float, nose: float, ws: float, y0: float, belt: float) -> void:
	var kit := b._k("paint")
	kit.color = b.paint
	var zs: Array[float] = []
	for d: float in [0.0, 0.015, 0.04, 0.08, 0.13, 0.2, 0.28]:
		zs.append(nose + d)
	for t: float in [0.25, 0.5, 0.75, 1.0]:
		zs.append(lerpf(nose + 0.28, ws, t))
	var top := func(z: float) -> float:
		# 0.98 at the front, 1.08 a little back, the belt at the glass.
		var u := clampf((z - nose) / 0.42, 0.0, 1.0)
		var a := lerpf(0.98, 1.08, sin(u * PI * 0.5))
		return lerpf(a, belt, clampf((z - nose - 0.42) / (ws - nose - 0.42), 0.0, 1.0)) if z > nose + 0.42 else a
	var rings: Array = []
	for z in zs:
		var w := nose_hw(hw, nose, z)
		var t: float = top.call(z)
		var r := 0.09
		var ring: Array = []
		ring.append([Vector3(-w, y0, z), Vector3.LEFT])
		for k in 5:
			var a := PI - (PI * 0.5) * float(k) / 4.0
			var d := Vector3(cos(a), sin(a), 0)
			ring.append([Vector3(-w + r, t - r, z) + d * r, d])
		for k in 5:
			var a := PI * 0.5 - (PI * 0.5) * float(k) / 4.0
			var d := Vector3(cos(a), sin(a), 0)
			ring.append([Vector3(w - r, t - r, z) + d * r, d])
		ring.append([Vector3(w, y0, z), Vector3.RIGHT])
		rings.append(ring)
	for i in rings.size() - 1:
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		for j in ra.size() - 1:
			var face := (ra[j][1] as Vector3) + (ra[j + 1][1] as Vector3)
			# Round the front: the normals near the face lean forward.
			var lean := 1.0 - clampf((float(zs[i]) - nose) / 0.2, 0.0, 1.0)
			var lean_b := 1.0 - clampf((float(zs[i + 1]) - nose) / 0.2, 0.0, 1.0)
			var na := ((ra[j][1] as Vector3) + Vector3(0, 0, -0.8 * lean)).normalized()
			var nb := ((ra[j + 1][1] as Vector3) + Vector3(0, 0, -0.8 * lean)).normalized()
			var nc := ((rb[j + 1][1] as Vector3) + Vector3(0, 0, -0.8 * lean_b)).normalized()
			var nd := ((rb[j][1] as Vector3) + Vector3(0, 0, -0.8 * lean_b)).normalized()
			kit.quad_smooth(ra[j][0], ra[j + 1][0], rb[j + 1][0], rb[j][0], na, nb, nc, nd, face)
	# The front face.
	var first: Array = rings[0]
	var c := Vector3(0, (y0 + 0.98) * 0.5, nose)
	for j in first.size() - 1:
		kit.tri(c, first[j][0], first[j + 1][0], Vector3.FORWARD)
	kit.tri(c, first[first.size() - 1][0], first[0][0], Vector3.FORWARD)


## The van's cab interior: TruckBuilder's, set up for this cab (its front
## face is the windscreen's line, its ceiling the shelf over the
## windscreen, its back the partition).
static func _van_cab_interior(b: TruckBuilder, hw: float, ws: float, belt: float, roof: float, fl: float) -> void:
	var cap := -1.25
	var ceiling := 2.12
	b._hw = hw
	b._y0 = belt
	b._cz0 = ws
	b._roof = ceiling
	b._rake = (cap - ws) * (ceiling - belt) / (roof - belt)
	b._cz1 = -1.08
	b._floor = fl
	b._belt = belt
	b._wb = belt + 0.08
	b._wt = 2.0
	b._zb = lerpf(ws, -1.08, 0.6)
	b._cab_interior({"trim": "#3a3c40", "dash": "#1c1d20", "seat": "#1d1d20", "cloth": "#2e3136", "hump": 0.0, "stick": false, "firewall": ws + 0.03})


## The van's upper body: a loft of rounded-roof sections from the foot of
## the windscreen to the back (each a rectangle from the belt up to the
## rake or the roof, its top corners rounded, more so as the roof takes
## over from the windscreen), its flat sides and back built separately
## with real openings at the windows so the inside shows, and lined.
## side_windows: [side, z0, z1, y0, y1]; back_windows: [x0, x1, y0, y1].
static func _van_upper(b: TruckBuilder, hw: float, ws: float, cap: float, back: float, belt: float, roof: float,
		side_windows: Array, back_windows: Array) -> void:
	var kit := b._k("paint")
	kit.color = b.paint
	var zs: Array[float] = []
	for i in 9:
		zs.append(lerpf(ws, cap, float(i) / 8.0))
	for z: float in [cap + 0.12, cap + 0.3, back]:
		zs.append(z)
	var top_at := func(z: float) -> float:
		return minf(roof, belt + (roof - belt) * clampf((z - ws) / (cap - ws), 0.0, 1.0))
	var r_at := func(z: float) -> float:
		var r := lerpf(0.04, 0.22, smoothstep(cap - 0.35, cap + 0.25, z))
		return minf(r, maxf(0.002, (float(top_at.call(z)) - belt) * 0.45))
	var rings: Array = []
	for z in zs:
		var top: float = top_at.call(z)
		var r: float = r_at.call(z)
		var ring: Array = [] # [point, normal]
		for k in 6:
			var a := PI - (PI * 0.5) * float(k) / 5.0
			var d := Vector3(cos(a), sin(a), 0)
			ring.append([Vector3(-hw + r, top - r, z) + d * r, d])
		for k in 6:
			var a := PI * 0.5 - (PI * 0.5) * float(k) / 5.0
			var d := Vector3(cos(a), sin(a), 0)
			ring.append([Vector3(hw - r, top - r, z) + d * r, d])
		rings.append(ring)
	for i in rings.size() - 1:
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		for j in ra.size() - 1:
			var a0: Vector3 = ra[j][0]
			var a1: Vector3 = ra[j + 1][0]
			var b1: Vector3 = rb[j + 1][0]
			var b0: Vector3 = rb[j][0]
			var face := (ra[j][1] as Vector3) + (ra[j + 1][1] as Vector3)
			if (a1 - a0).length() < 0.0005 and (b1 - b0).length() < 0.0005:
				continue
			kit.quad_smooth(a0, a1, b1, b0, ra[j][1], ra[j + 1][1], rb[j + 1][1], rb[j][1], face if face.length() > 0.01 else Vector3.UP)
	# The flat sides, from the belt up to where the roof's curve starts,
	# with the windows left open.
	var wall_top := func(z: float) -> float: return float(top_at.call(z)) - float(r_at.call(z))
	for s: float in [-1.0, 1.0]:
		var holes := []
		for w: Array in side_windows:
			if float(w[0]) == s:
				holes.append(w)
		var cuts: Array[float] = []
		cuts.append_array(zs)
		for w: Array in holes:
			cuts.append(float(w[1]))
			cuts.append(float(w[2]))
		cuts.sort()
		for i in cuts.size() - 1:
			var za: float = cuts[i]
			var zb: float = cuts[i + 1]
			if zb - za < 0.001:
				continue
			var ys: Array[float] = [belt]
			for w: Array in holes:
				if float(w[1]) < zb - 0.001 and float(w[2]) > za + 0.001:
					ys.append(float(w[3]))
					ys.append(float(w[4]))
			ys.sort()
			ys.append(INF) # the wall's top, which slopes along the rake
			for k in ys.size() - 1:
				var y0: float = ys[k]
				var y1: float = ys[k + 1]
				var open := false
				for w: Array in holes:
					if float(w[1]) < zb - 0.001 and float(w[2]) > za + 0.001 and y0 >= float(w[3]) - 0.001 and (y1 <= float(w[4]) + 0.001):
						open = true
				if open:
					continue
				var ta: float = wall_top.call(za)
				var tb: float = wall_top.call(zb)
				var ya1 := minf(y1, ta)
				var yb1 := minf(y1, tb)
				if ya1 - y0 < 0.001 and yb1 - y0 < 0.001:
					continue
				var x := hw * s
				kit.quad(Vector3(x, y0, za), Vector3(x, y0, zb), Vector3(x, maxf(y0, yb1), zb), Vector3(x, maxf(y0, ya1), za), Vector3(s, 0, 0))
	# The back, with the doors' windows open: a grid round them up to the
	# roof's curve, and the curve itself fanned in.
	var bt: float = wall_top.call(back)
	var xs: Array[float] = [-hw, hw]
	var bys: Array[float] = [belt, bt]
	for w: Array in back_windows:
		xs.append(float(w[0]))
		xs.append(float(w[1]))
		bys.append(float(w[2]))
		bys.append(float(w[3]))
	xs.sort()
	bys.sort()
	for i in xs.size() - 1:
		for k in bys.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var y0: float = bys[k]
			var y1: float = bys[k + 1]
			if x1 - x0 < 0.001 or y1 - y0 < 0.001:
				continue
			var open := false
			for w: Array in back_windows:
				if x0 >= float(w[0]) - 0.001 and x1 <= float(w[1]) + 0.001 and y0 >= float(w[2]) - 0.001 and y1 <= float(w[3]) + 0.001:
					open = true
			if not open:
				kit.quad(Vector3(x1, y0, back), Vector3(x0, y0, back), Vector3(x0, y1, back), Vector3(x1, y1, back), Vector3.BACK)
	var last: Array = rings[rings.size() - 1]
	var c := Vector3(0, bt, back)
	for j in last.size() - 1:
		kit.tri(c, last[j][0], last[j + 1][0], Vector3.BACK)
	# The lining inside, facing in, so through a window you see the far
	# wall and the ceiling, not out the other side: pale grey, as a patient
	# compartment's walls are.
	var lining := Color(0.86, 0.87, 0.86)
	var li := hw - 0.035
	var z0 := cap - 0.05
	var lk := b._k("satin")
	lk.color = lining
	for s: float in [-1.0, 1.0]:
		var x := li * s
		lk.quad(Vector3(x, belt - 0.4, z0), Vector3(x, belt - 0.4, back - 0.035), Vector3(x, roof - 0.06, back - 0.035), Vector3(x, roof - 0.06, z0), Vector3(-s, 0, 0))
	lk.quad(Vector3(-li, roof - 0.06, z0), Vector3(li, roof - 0.06, z0), Vector3(li, roof - 0.06, back - 0.035), Vector3(-li, roof - 0.06, back - 0.035), Vector3.DOWN)
	lk.quad(Vector3(-li, belt - 0.4, back - 0.035), Vector3(li, belt - 0.4, back - 0.035), Vector3(li, roof - 0.06, back - 0.035), Vector3(-li, roof - 0.06, back - 0.035), Vector3.FORWARD)
	# In the cab, a darker lining from the windscreen back to the partition.
	# Its top follows the rake, under the glass, so none of it shows outside.
	lk.color = Color(0.2, 0.21, 0.23)
	for s: float in [-1.0, 1.0]:
		var x := li * s
		for i in 6:
			var za := lerpf(ws + 0.05, z0, float(i) / 6.0)
			var zb := lerpf(ws + 0.05, z0, float(i + 1) / 6.0)
			var ta := minf(2.15, float(wall_top.call(za)) - 0.03)
			var tb := minf(2.15, float(wall_top.call(zb)) - 0.03)
			lk.quad(Vector3(x, belt - 0.4, za), Vector3(x, belt - 0.4, zb), Vector3(x, tb, zb), Vector3(x, ta, za), Vector3(-s, 0, 0))


## The small parts that make it a van rather than a box: handles on the
## side door and back doors, the back doors' hinges and their rubber seal,
## a grab handle by the side door, reflective red and white tape round the
## back, a drip rail over the side door, and the cab steps.
static func _ambulance_details(b: TruckBuilder, hw: float, back: float, belt: float, roof: float, low: float, sd0: float, sd1: float, cz1: float) -> void:
	var bz := back + 0.003
	b._detail = true
	# The sliding door's handle, and a grab handle inside its opening.
	b._bev("rough", Vector3(hw + 0.014, 1.08, sd0 + 0.12), Vector3(0.012, 0.025, 0.09), 0.01, TruckBuilder.DARK)
	b._rod("metal", [Vector3(hw + 0.005, 0.9, sd1 + 0.06), Vector3(hw + 0.05, 0.9, sd1 + 0.06), Vector3(hw + 0.05, 1.5, sd1 + 0.06), Vector3(hw + 0.005, 1.5, sd1 + 0.06)], 0.014, TruckBuilder.CHROME, 6)
	# Hinges down the outer edges of the back doors, and their latch.
	for s: float in [-1.0, 1.0]:
		for y: float in [0.75, 1.45, 2.2]:
			b._bev("rough", Vector3((hw - 0.02) * s, y, bz + 0.02), Vector3(0.03, 0.06, 0.02), 0.01, TruckBuilder.DARK)
		# The seal round each door.
		b._box("rough", Vector3((hw - 0.075) * s, (low + 0.2 + roof - 0.25) * 0.5, bz + 0.001), Vector3(0.012, roof - low - 0.45, 0.004), TruckBuilder.RUBBER)
	# A drip rail over the side door.
	b._box("rough", Vector3(hw + 0.01, 2.2, (sd0 + sd1) * 0.5), Vector3(0.02, 0.015, sd1 - sd0 + 0.2), TruckBuilder.DARK)
	b._detail = false
	# Reflective tape round the back: red and white blocks down the
	# outer edges and across the top.
	var i := 0
	var y := 0.62
	while y < roof - 0.25:
		for s: float in [-1.0, 1.0]:
			var col := TruckBuilder.RED if (i + int(s > 0.0)) % 2 == 0 else Color(0.96, 0.96, 0.94)
			var x0 := (hw - 0.065) * s
			var x1 := (hw - 0.005) * s
			b._quad("gloss", Vector3(maxf(x0, x1), y, bz + 0.002), Vector3(minf(x0, x1), y, bz + 0.002), Vector3(minf(x0, x1), y + 0.15, bz + 0.002), Vector3(maxf(x0, x1), y + 0.15, bz + 0.002), Vector3.BACK, col)
		y += 0.17
		i += 1
	var x := -hw + 0.1
	i = 0
	while x < hw - 0.25:
		var col := TruckBuilder.RED if i % 2 == 0 else Color(0.96, 0.96, 0.94)
		b._quad("gloss", Vector3(x + 0.15, roof - 0.22, bz + 0.002), Vector3(x, roof - 0.22, bz + 0.002), Vector3(x, roof - 0.17, bz + 0.002), Vector3(x + 0.15, roof - 0.17, bz + 0.002), Vector3.BACK, col)
		x += 0.17
		i += 1
	# Cab steps under the front doors.
	for s: float in [-1.0, 1.0]:
		b._tread(Vector3((hw - 0.12) * s, low - 0.02, cz1 - 0.42), 0.22, 0.5)


## Near-only, seen through the glass: the cab's two seats and dash, and
## the patient compartment: the stretcher on its mount down the curb side
## (frame, folding legs, wheels, mattress with the head raised, a sheet,
## the side rails), the bench along the other wall, the attendant's seat
## at the head, cabinets with glass doors, the oxygen bottle, the monitor
## on its bracket and the ceiling lights.
static func _ambulance_inside(b: TruckBuilder, hw: float, ws: float, back: float, belt: float, roof: float, low: float) -> void:
	b._detail = true
	var fl := float(b.shape["wheel_radius"]) * 2.0 + 0.065 # the floor, at the sill
	var wall := hw - 0.06
	# The cab: the trucks' full interior (dash, cluster, centre stack and
	# radio, column and pedals, door cards, overhead shelf, seats, mats),
	# fitted to the van's windscreen and its cab ceiling.
	_van_cab_interior(b, hw, ws, belt, roof, fl)
	# On the dash's middle, the light and siren controller and the radio
	# head, with their buttons; a laptop on a pole for the attendant.
	b._bev("rough", Vector3(0.0, belt + 0.12, ws + 0.62), Vector3(0.12, 0.04, 0.05), 0.012, Color(0.06, 0.06, 0.065))
	for i in 6:
		var col := [Color(0.85, 0.15, 0.1), Color(0.9, 0.9, 0.85), TruckBuilder.AMBER][i % 3] as Color
		b._plate("gloss", Vector3(-0.09 + i * 0.036, belt + 0.13, ws + 0.67), 0.024, 0.02, Vector3.BACK, col.darkened(0.3))
	b._tube("rough", Vector3(0.32, fl, -1.95), Vector3(0.32, belt + 0.1, -1.95), 0.016, TruckBuilder.DARK, 6)
	b._bev("rough", Vector3(0.32, belt + 0.2, -1.97), Vector3(0.15, 0.1, 0.012), 0.005, Color(0.08, 0.08, 0.09), Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, -0.25))
	# The partition behind the cab, with its window.
	b._box("satin", Vector3(0, (fl + roof) * 0.5, -1.1), Vector3(hw * 2.0 - 0.1, roof - fl - 0.1, 0.03), Color(0.85, 0.86, 0.84))
	# The floor.
	b._box("rough", Vector3(0, fl - 0.01, (-1.1 + back) * 0.5), Vector3(hw * 2.0 - 0.1, 0.02, back + 1.05), Color(0.32, 0.34, 0.36))
	b._box("rough", Vector3(0, fl - 0.01, (ws + 0.05 - 1.1) * 0.5), Vector3(hw * 2.0 - 0.1, 0.02, -1.1 - ws - 0.05), Color(0.06, 0.06, 0.065))
	# The stretcher, curb side, head toward the front.
	var sx := 0.25
	var z0 := -0.35
	var z1 := 1.75
	var top := fl + 0.62
	var alu := ALU
	for e: float in [-0.25, 0.25]:
		b._tube("metal", Vector3(sx + e, top - 0.06, z0), Vector3(sx + e, top - 0.06, z1), 0.016, alu, 6)
	for z: float in [z0 + 0.25, z1 - 0.25]:
		# The folding legs and their wheels.
		for e: float in [-0.22, 0.22]:
			b._tube("metal", Vector3(sx + e, top - 0.06, z), Vector3(sx + e, fl + 0.08, z + 0.12), 0.014, alu, 6)
			b._cyl("rough", Vector3(sx + e - 0.02, fl + 0.05, z + 0.12), Vector3(sx + e + 0.02, fl + 0.05, z + 0.12), 0.05, TruckBuilder.RUBBER, 8)
	# The mattress: flat at the foot, the back raised at the head.
	var knee := z0 + 0.65
	b._bev("satin", Vector3(sx, top + 0.02, (knee + z1) * 0.5), Vector3(0.26, 0.05, (z1 - knee) * 0.5), 0.03, Color(0.1, 0.16, 0.32))
	var back_rest := Basis(Vector3.RIGHT, 0.55)
	b._bev("satin", Vector3(sx, top + 0.18, (z0 + knee) * 0.5 + 0.03), Vector3(0.26, 0.05, (knee - z0) * 0.5), 0.03, Color(0.1, 0.16, 0.32), back_rest)
	# A white sheet folded over the foot, a pillow at the head, the rails.
	b._bev("satin", Vector3(sx, top + 0.075, z1 - 0.35), Vector3(0.27, 0.012, 0.3), 0.01, Color(0.94, 0.95, 0.96))
	b._bev("satin", Vector3(sx, top + 0.3, z0 + 0.2), Vector3(0.18, 0.04, 0.08), 0.035, Color(0.94, 0.95, 0.96), back_rest)
	for e: float in [-0.29, 0.29]:
		b._tube("metal", Vector3(sx + e, top + 0.14, knee), Vector3(sx + e, top + 0.14, z1 - 0.2), 0.012, alu, 6)
		b._tube("metal", Vector3(sx + e, top - 0.04, knee), Vector3(sx + e, top + 0.14, knee), 0.012, alu, 6)
		b._tube("metal", Vector3(sx + e, top - 0.04, z1 - 0.2), Vector3(sx + e, top + 0.14, z1 - 0.2), 0.012, alu, 6)
	# The orange straps across it.
	for z: float in [knee + 0.2, z1 - 0.7]:
		b._box("rough", Vector3(sx, top + 0.078, z), Vector3(0.54, 0.008, 0.05), Color(0.92, 0.45, 0.08))
	# The bench along the street side, the attendant's seat at the head.
	b._bev("satin", Vector3(-wall + 0.25, fl + 0.42, 0.9), Vector3(0.22, 0.06, 0.85), 0.03, Color(0.1, 0.16, 0.32))
	b._bev("satin", Vector3(-wall + 0.04, fl + 0.75, 0.9), Vector3(0.04, 0.28, 0.85), 0.03, Color(0.1, 0.16, 0.32))
	b._box("satin", Vector3(-wall + 0.25, (fl + fl + 0.36) * 0.5, 0.9), Vector3(0.44, 0.36, 1.7), Color(0.85, 0.86, 0.84))
	b._bev("satin", Vector3(0.25, fl + 0.45, -0.85), Vector3(0.2, 0.05, 0.2), 0.03, Color(0.1, 0.16, 0.32))
	b._bev("satin", Vector3(0.25, fl + 0.75, -1.02), Vector3(0.2, 0.25, 0.04), 0.03, Color(0.1, 0.16, 0.32))
	# Cabinets along the street side's upper wall, glass-fronted, and a
	# row over the curb side.
	for e: Array in [[-1.0, -0.6, 2.6], [1.0, 1.9, 3.2]]:
		var side: float = e[0]
		var cz0: float = e[1]
		var cz1: float = e[2]
		var cx := side * (wall - 0.15)
		b._box("satin", Vector3(cx, roof - 0.45, (cz0 + cz1) * 0.5), Vector3(0.3, 0.5, cz1 - cz0), Color(0.88, 0.89, 0.87))
		var z := cz0 + 0.05
		while z < cz1 - 0.3:
			b._quad("glass", Vector3(cx - side * 0.151, roof - 0.65, z), Vector3(cx - side * 0.151, roof - 0.65, z + 0.36), Vector3(cx - side * 0.151, roof - 0.25, z + 0.36), Vector3(cx - side * 0.151, roof - 0.25, z), Vector3(-side, 0, 0), Color(0.6, 0.7, 0.75, 0.4))
			z += 0.4
	# The oxygen bottle, green, strapped by the head; the monitor on its
	# bracket over the bench.
	b._cyl("gloss", Vector3(-wall + 0.12, fl, -0.95), Vector3(-wall + 0.12, fl + 0.9, -0.95), 0.09, Color(0.1, 0.45, 0.2), 12)
	b._cyl("metal", Vector3(-wall + 0.12, fl + 0.9, -0.95), Vector3(-wall + 0.12, fl + 0.98, -0.95), 0.03, TruckBuilder.CHROME, 8)
	b._bev("rough", Vector3(-wall + 0.12, fl + 1.3, -0.3), Vector3(0.1, 0.13, 0.16), 0.02, Color(0.15, 0.15, 0.17))
	b._plate("gloss", Vector3(-wall + 0.225, fl + 1.32, -0.3), 0.22, 0.16, Vector3.RIGHT, Color(0.06, 0.2, 0.12))
	# Ceiling lights.
	for z: float in [-0.4, 0.9, 2.2]:
		b._plate("gloss", Vector3(0, roof - 0.09, z), 0.5, 0.3, Vector3.DOWN, Color(0.98, 0.98, 0.95))
	b._detail = false


## The Star of Life on a side at x = ±hw (s the side): a blue six-armed
## star edged in white, the white staff and serpent up the middle, centred
## at (cz, cy), r from the middle to an arm's end. Flat quads.
static func star_of_life(b: TruckBuilder, hw: float, s: float, cz: float, cy: float, r: float) -> void:
	var n := Vector3(s, 0, 0)
	var blue := Color(0.05, 0.2, 0.62)
	for layer: Array in [[0.002, r + 0.03, 0.17 * r + 0.03, WHITE], [0.004, r, 0.17 * r, blue]]:
		var x := (hw + float(layer[0])) * s
		var len_: float = layer[1]
		var half_w: float = layer[2]
		for k in 3:
			var a := PI * 0.5 + k * PI / 3.0
			var d := Vector2(cos(a), sin(a)) # (z, y) along the arm
			var p := Vector2(-d.y, d.x) * half_w
			var c := Vector2(cz, cy)
			var q := [c - d * len_ - p, c - d * len_ + p, c + d * len_ + p, c - (-d * len_) - p]
			var v: Array = []
			for e: Vector2 in q:
				v.append(Vector3(x, e.y, e.x))
			# Wind them to face out of this side.
			if s > 0.0:
				b._quad("gloss", v[0], v[1], v[2], v[3], n, layer[3])
			else:
				b._quad("gloss", v[3], v[2], v[1], v[0], n, layer[3])
	# The staff, and the serpent as a zigzag round it.
	var x2 := (hw + 0.006) * s
	b._quad("gloss", Vector3(x2, cy - r * 0.72, cz - 0.018), Vector3(x2, cy - r * 0.72, cz + 0.018), Vector3(x2, cy + r * 0.72, cz + 0.018), Vector3(x2, cy + r * 0.72, cz - 0.018), n, WHITE)
	for i in 4:
		var y0 := cy - r * 0.55 + i * r * 0.28
		var dz := 0.07 * r * (1.0 if i % 2 == 0 else -1.0)
		b._quad("gloss", Vector3(x2 + 0.001 * s, y0, cz - dz), Vector3(x2 + 0.001 * s, y0 + 0.03, cz - dz), Vector3(x2 + 0.001 * s, y0 + r * 0.28 + 0.03, cz + dz), Vector3(x2 + 0.001 * s, y0 + r * 0.28, cz + dz), n, WHITE)


## A Maltese cross, the fire service's badge, on a side at x = ±hw: four
## arms flaring out from the middle, gold edged in black, with a red
## centre. Flat quads.
static func maltese_cross(b: TruckBuilder, hw: float, s: float, cz: float, cy: float, r: float) -> void:
	var n := Vector3(s, 0, 0)
	var gold := Color(0.93, 0.74, 0.25)
	for layer: Array in [[0.002, r + 0.018, Color(0.08, 0.04, 0.02)], [0.004, r, gold]]:
		var x := (hw + float(layer[0])) * s
		var rr: float = layer[1]
		for k in 4:
			var a := k * PI * 0.5
			var d := Vector2(cos(a), sin(a))
			var p := Vector2(-d.y, d.x)
			var c := Vector2(cz, cy)
			# Narrow at the middle, flaring to the tips, with a notch.
			var pts := [c + p * rr * 0.12, c + d * rr + p * rr * 0.55, c + d * rr * 0.8, c + d * rr - p * rr * 0.55, c - p * rr * 0.12]
			var v: Array = []
			for e: Vector2 in pts:
				v.append(Vector3(x, e.y, e.x))
			for t: Array in [[0, 1, 2], [0, 2, 4], [2, 3, 4]]:
				var aa: Vector3 = v[t[0]]
				var bb: Vector3 = v[t[1]]
				var cc: Vector3 = v[t[2]]
				if (bb - aa).cross(cc - aa).dot(n) < 0.0:
					b._quad("gloss", aa, cc, bb, bb, n, layer[2])
				else:
					b._quad("gloss", aa, bb, cc, cc, n, layer[2])
	b._disc("gloss", Vector3((hw + 0.006) * s, cy, cz), r * 0.26, n, Color(0.62, 0.06, 0.04), 16)


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
		"door": 0.42, "steps": [], "clutch": false, "crew_window": true, "trim": "#3a3c40", "dash": "#1e1f21", "seat": "#1d1d20", "cloth": "#2e3034"})
	# Below the cab: the front, the fenders over the wheels, the skirts.
	var cy0 := 1.12
	# (Flush with the cab's face, so the grille runs up both as one.)
	b._box("paint", Vector3(0, (0.48 + cy0) * 0.5, front + 0.24), Vector3(hw * 2.0, cy0 - 0.48, 0.32), b.paint)
	var ar := wr + 0.16
	for s: float in [-1.0, 1.0]:
		var xi := (hw - 0.35) * s
		var xo := hw * s
		b._arch("paint", fa, wr + 0.02, wr + 0.08, ar, minf(xi, xo), maxf(xi, xo), 0.0, PI, b.paint, 16)
		b._arch("rough", fa, wr + 0.02, wr + 0.06, wr + 0.08, minf(xi, xo) + 0.01, maxf(xi, xo) - 0.01, 0.0, PI, TruckBuilder.RUBBER, 12)
		# Panels in front of and behind the arch, down to the skirt.
		b._box("paint", Vector3((hw - 0.175) * s, (0.48 + cy0) * 0.5, (front + 0.36 + fa - ar) * 0.5), Vector3(0.35, cy0 - 0.48, fa - ar - front - 0.36), b.paint)
		b._box("paint", Vector3((hw - 0.175) * s, (0.62 + cy0) * 0.5, (fa + ar - 2.38) * 0.5), Vector3(0.35, cy0 - 0.62, -2.38 - fa - ar), b.paint)
	# Steps up to the cab doors, ahead of the front wheels (a cab-over's
	# door is over the wheel), on a bracket off the frame, and a grab rail.
	for s: float in [-1.0, 1.0]:
		var stz := (front + 0.38 + fa - ar) * 0.5
		for sy: float in [0.5, 0.82]:
			b._tread(Vector3((hw - 0.14) * s, sy, stz), 0.26, fa - ar - front - 0.5)
		b._box("steel", Vector3((hw - 0.28) * s, 0.66, stz), Vector3(0.03, 0.36, fa - ar - front - 0.5), TruckBuilder.DARK)
	# The front: a tall chrome grille from the bumper up toward the
	# windscreen, following the cab's slight rake; rectangular headlamp
	# bezels either side of it at mid height, turn signals over them.
	var fz := func(y: float) -> float: return front + 0.08 + 0.14 * maxf(y - cy0, 0.0) / (3.0 - cy0) - 0.006
	var gy0 := 0.62
	var gy1 := 1.98
	var gw := 0.5
	# The dark mesh behind, then the chrome surround and the slats.
	b._blk("rough", [Vector3(-gw, gy0, fz.call(gy0) - 0.004), Vector3(gw, gy0, fz.call(gy0) - 0.004), Vector3(gw, gy1, fz.call(gy1) - 0.004), Vector3(-gw, gy1, fz.call(gy1) - 0.004),
		Vector3(-gw, gy0, fz.call(gy0) + 0.02), Vector3(gw, gy0, fz.call(gy0) + 0.02), Vector3(gw, gy1, fz.call(gy1) + 0.02), Vector3(-gw, gy1, fz.call(gy1) + 0.02)], Color(0.03, 0.03, 0.035))
	for x: float in [-gw - 0.03, gw + 0.03]:
		b._blk("metal", [Vector3(x - 0.035, gy0 - 0.03, fz.call(gy0) - 0.03), Vector3(x + 0.035, gy0 - 0.03, fz.call(gy0) - 0.03), Vector3(x + 0.035, gy1 + 0.03, fz.call(gy1) - 0.03), Vector3(x - 0.035, gy1 + 0.03, fz.call(gy1) - 0.03),
			Vector3(x - 0.035, gy0 - 0.03, fz.call(gy0) + 0.01), Vector3(x + 0.035, gy0 - 0.03, fz.call(gy0) + 0.01), Vector3(x + 0.035, gy1 + 0.03, fz.call(gy1) + 0.01), Vector3(x - 0.035, gy1 + 0.03, fz.call(gy1) + 0.01)], TruckBuilder.CHROME)
	for y: float in [gy0 - 0.03, gy1 + 0.03]:
		b._bev("metal", Vector3(0, y, fz.call(y) - 0.012), Vector3(gw + 0.065, 0.035, 0.02), 0.012, TruckBuilder.CHROME)
	var sy := gy0 + 0.08
	while sy < gy1 - 0.04:
		b._box("metal", Vector3(0, sy, fz.call(sy) - 0.012), Vector3(gw * 2.0, 0.022, 0.012), TruckBuilder.CHROME.darkened(0.08))
		sy += 0.1
	# The maker's badge on the grille's top bar, and the Brigade's cross
	# under the windscreen.
	b._bev("metal", Vector3(0, gy1 + 0.03, fz.call(gy1) - 0.04), Vector3(0.14, 0.035, 0.012), 0.012, TruckBuilder.CHROME)
	for s: float in [-1.0, 1.0]:
		var hx := 0.86 * s
		var hy := 1.3
		var hz: float = fz.call(hy)
		b._bev("metal", Vector3(hx, hy, hz - 0.01), Vector3(0.24, 0.12, 0.02), 0.015, TruckBuilder.CHROME)
		b._box("rough", Vector3(hx, hy, hz - 0.025), Vector3(0.44, 0.2, 0.01), TruckBuilder.DARK)
		for lx: float in [-0.1, 0.1]:
			b._lamp(Vector3(hx + lx, hy, hz - 0.035), 0.15, 0.15, Vector3.FORWARD, TruckBuilder.LAMP, TruckBuilder.CHROME, true)
		b._lamp(Vector3(hx, 1.5, fz.call(1.5) - 0.02), 0.4, 0.07, Vector3.FORWARD, TruckBuilder.AMBER, TruckBuilder.CHROME)
		b._lamp(Vector3(hx, 1.1, fz.call(1.1) - 0.02), 0.18, 0.06, Vector3.FORWARD, TruckBuilder.LAMP, TruckBuilder.CHROME)
	var bump_z := front - 0.32
	b._bev("metal", Vector3(0, 0.5, bump_z), Vector3(hw + 0.02, 0.13, 0.3), 0.04, TruckBuilder.CHROME)
	b._box("rough", Vector3(0, 0.64, bump_z + 0.02), Vector3(1.0, 0.02, 0.5), TruckBuilder.DARK)
	for i in 3:
		b._box("rough", Vector3(-0.3 + i * 0.3, 0.68, bump_z), Vector3(0.24, 0.06, 0.42), HOSE_RED.darkened(0.1 * i))
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
	# The Brigade's Maltese cross on the cab doors, under the band.
	for s: float in [-1.0, 1.0]:
		maltese_cross(b, hw, s, -4.16, 1.3, 0.19)
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
	_engine_details(b, bw, z0, z1, y0, y1, mid, pz0, pz1, doors, bump_z, gun)
	_engine_crew_cab(b, hw)


## Near-only, seen through the cab's glass: the crew's half of the cab
## behind the front seats. Two crew seats against the back wall with an
## air pack (SCBA) in each seat back, its cylinder, backplate and straps;
## a helmet on each seat and the captain's white one on the dash; the
## console between the front seats with the radios in their chargers;
## the officer's laptop on its mount and the light and siren controller;
## a medical bag and a tool box on the floor; a grab rail across the roof.
static func _engine_crew_cab(b: TruckBuilder, hw: float) -> void:
	b._detail = true
	var fl := 1.2
	var sz: float = b.shape["seat"][2]
	var back := -2.45
	var black := Color(0.05, 0.05, 0.055)
	var vinyl := Color(0.12, 0.12, 0.13)
	for s: float in [-1.0, 1.0]:
		var x := 0.55 * s
		var cz := back - 0.3
		# The seat: a cushion on a box, and a back with the pack's recess.
		b._box("satin", Vector3(x, fl + 0.2, cz), Vector3(0.5, 0.4, 0.45), Color(0.2, 0.2, 0.22))
		b._bev("satin", Vector3(x, fl + 0.44, cz - 0.02), Vector3(0.24, 0.05, 0.23), 0.03, vinyl)
		b._bev("satin", Vector3(x - 0.17 * s, fl + 0.8, back - 0.08), Vector3(0.06, 0.32, 0.06), 0.03, vinyl)
		b._bev("satin", Vector3(x + 0.17 * s, fl + 0.8, back - 0.08), Vector3(0.06, 0.32, 0.06), 0.03, vinyl)
		# The air pack: a cylinder in the recess, its black backplate, the
		# shoulder straps, the regulator hose.
		var pc := Vector3(x, fl + 0.8, back - 0.14)
		b._cyl("gloss", pc + Vector3(0, -0.28, 0), pc + Vector3(0, 0.3, 0), 0.085, Color(0.22, 0.24, 0.27), 12)
		b._cyl("gloss", pc + Vector3(0, -0.05, 0), pc + Vector3(0, 0.05, 0), 0.087, Color(0.95, 0.75, 0.1), 12)
		b._cyl("metal", pc + Vector3(0, -0.28, 0), pc + Vector3(0, -0.34, 0), 0.03, TruckBuilder.CHROME, 8)
		b._box("rough", pc + Vector3(0, 0, -0.1), Vector3(0.24, 0.62, 0.02), black)
		for e: float in [-0.08, 0.08]:
			b._box("rough", pc + Vector3(e, 0.05, -0.115), Vector3(0.05, 0.58, 0.012), Color(0.1, 0.1, 0.11))
		b._tube("rough", pc + Vector3(0.1 * s, -0.3, 0), pc + Vector3(0.14 * s, 0.1, -0.12), 0.012, black, 6)
		# A helmet on the seat: the dome, the brim, the reflective band.
		_helmet(b, Vector3(x, fl + 0.55, cz), Color(0.06, 0.06, 0.065))
	_helmet(b, Vector3(0.45, 2.05, -4.35), Color(0.94, 0.94, 0.92))
	# The console between the front seats: the radios standing in their
	# chargers, the laptop on its mount for the officer.
	b._box("satin", Vector3(0, fl + 0.3, sz + 0.15), Vector3(0.28, 0.6, 0.55), Color(0.14, 0.14, 0.15))
	for i in 4:
		var rc := Vector3(-0.09 + i * 0.06, fl + 0.68, sz + 0.25)
		b._box("rough", rc, Vector3(0.04, 0.16, 0.035), black)
		b._cyl("rough", rc + Vector3(0, 0.08, 0), rc + Vector3(0, 0.15, 0), 0.006, black, 5)
	b._tube("rough", Vector3(0.18, fl + 0.6, sz - 0.05), Vector3(0.3, fl + 0.95, sz - 0.25), 0.016, TruckBuilder.DARK, 6)
	b._bev("rough", Vector3(0.36, fl + 1.02, sz - 0.3), Vector3(0.15, 0.1, 0.012), 0.005, Color(0.08, 0.08, 0.09), Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, -0.25))
	b._plate("gloss", Vector3(0.355, fl + 1.025, sz - 0.288), 0.26, 0.15, (Basis(Vector3.UP, -0.5) * Basis(Vector3.RIGHT, -0.25)) * Vector3.BACK, Color(0.08, 0.16, 0.24))
	# The light and siren controller on the dash, before the officer.
	b._bev("rough", Vector3(0.25, 2.1, -4.45), Vector3(0.13, 0.04, 0.05), 0.012, black)
	for i in 6:
		var col := [Color(0.85, 0.15, 0.1), Color(0.9, 0.9, 0.85), TruckBuilder.AMBER][i % 3] as Color
		b._plate("gloss", Vector3(0.16 + i * 0.036, 2.11, -4.4), 0.024, 0.02, Vector3.BACK, col.darkened(0.3))
	# On the floor: the medical bag (red) and a tool box.
	b._bev("satin", Vector3(0.0, fl + 0.12, back - 0.75), Vector3(0.22, 0.12, 0.14), 0.05, Color(0.62, 0.08, 0.06))
	b._bev("rough", Vector3(0.0, fl + 0.12, back - 1.05), Vector3(0.24, 0.1, 0.1), 0.02, Color(0.75, 0.6, 0.1))
	# A grab rail along the roof for the crew.
	b._rod("metal", [Vector3(-0.6, 2.9, back - 0.15), Vector3(-0.6, 2.86, back - 0.3), Vector3(0.6, 2.86, back - 0.3), Vector3(0.6, 2.9, back - 0.15)], 0.014, TruckBuilder.CHROME, 6)
	b._detail = false


## A firefighter's helmet: the dome, the long brim, a reflective band and
## the front shield.
static func _helmet(b: TruckBuilder, c: Vector3, col: Color) -> void:
	b._bev("gloss", c + Vector3(0, 0.07, 0), Vector3(0.1, 0.07, 0.12), 0.07, col)
	b._bev("gloss", c + Vector3(0, 0.005, 0.03), Vector3(0.15, 0.008, 0.19), 0.006, col)
	b._box("gloss", c + Vector3(0, 0.035, 0), Vector3(0.205, 0.022, 0.245), Color(0.95, 0.85, 0.2))
	b._bev("gloss", c + Vector3(0, 0.1, -0.125), Vector3(0.035, 0.045, 0.006), 0.005, Color(0.95, 0.8, 0.3))


## What makes a pumper read as one up close: the chrome Q siren on the
## bumper, the crosslays (hose loaded across the body over the pump, red
## and yellow, the nozzles hanging at the ends), the discharges on the pump
## panel with their coloured caps, chrome trim round every compartment and
## a drip rail over each, scene lights high on the body, the deck gun's
## pipe and handwheel, reflective tape along the sill, and grab rails by
## the pump panel.
static func _engine_details(b: TruckBuilder, bw: float, z0: float, z1: float, y0: float, y1: float, mid: float,
		pz0: float, pz1: float, doors: Array, bump_z: float, gun: Vector3) -> void:
	# The Q siren: a chrome drum on the bumper's left, its slotted face, a
	# red beacon on top.
	var qs := Vector3(-0.62, 0.66, bump_z - 0.05)
	b._cyl("metal", qs + Vector3(0, 0, -0.16), qs + Vector3(0, 0, 0.12), 0.15, TruckBuilder.CHROME, 18)
	b._disc("rough", qs + Vector3(0, 0, -0.165), 0.13, Vector3.FORWARD, TruckBuilder.DARK, 18)
	b._detail = true
	for i in 7:
		var a := TAU * float(i) / 7.0
		var d := Vector3(cos(a), sin(a), 0)
		b._box("metal", qs + Vector3(0, 0, -0.17) + d * 0.065, Vector3(0.02, 0.02, 0.01) + Vector3(absf(d.y), absf(d.x), 0) * 0.08, TruckBuilder.CHROME)
	b._detail = false
	b._disc("metal", qs + Vector3(0, 0, -0.172), 0.035, Vector3.FORWARD, TruckBuilder.CHROME, 10)
	# The crosslays: two loads of hose across the top over the pump panel,
	# their ends hanging out each side with a nozzle.
	for e: Array in [[pz0 + 0.15, STRIPE_RED], [pz0 + 0.78, HOSE_YELLOW]]:
		var cz: float = e[0]
		var col: Color = e[1]
		var hy := y1 + 0.13
		b._bev("rough", Vector3(0, hy, cz), Vector3(bw - 0.04, 0.12, 0.13), 0.06, col)
		b._detail = true
		var xx := -bw + 0.15
		while xx < bw - 0.1:
			b._box("rough", Vector3(xx, hy, cz - 0.131), Vector3(0.01, 0.2, 0.004), col.darkened(0.3))
			xx += 0.12
		b._detail = false
		for s: float in [-1.0, 1.0]:
			var x := (bw + 0.02) * s
			b._rod("rough", [Vector3(x - 0.04 * s, hy, cz), Vector3(x, y1 - 0.05, cz), Vector3(x, y1 - 0.5, cz + 0.05)], 0.035, col, 8)
			b._cone("metal", Vector3(x, y1 - 0.5, cz + 0.05), Vector3(x, y1 - 0.72, cz + 0.06), 0.04, 0.025, TruckBuilder.CHROME, 10)
			b._cyl("rough", Vector3(x, y1 - 0.53, cz + 0.05), Vector3(x, y1 - 0.58, cz + 0.05), 0.05, Color(0.1, 0.1, 0.11), 10)
	# Discharges on the pump panel: chrome elbows with coloured caps, and a
	# panel light over the gauges.
	var caps := [Color(0.15, 0.3, 0.75), Color(0.95, 0.78, 0.1), STRIPE_RED, Color(0.1, 0.55, 0.25)]
	for s: float in [-1.0, 1.0]:
		var x := (bw + 0.006) * s
		for i in 2:
			var dz := pz0 + 0.22 + i * 0.42
			var base := Vector3(x, 0.92, dz)
			b._cyl("metal", base, base + Vector3(0.1 * s, -0.06, 0), 0.05, TruckBuilder.CHROME, 12)
			b._cyl("gloss", base + Vector3(0.1 * s, -0.06, 0), base + Vector3(0.14 * s, -0.08, 0), 0.06, caps[i + (2 if s > 0.0 else 0)], 12)
		b._bev("rough", Vector3(x + 0.03 * s, 2.06, (pz0 + pz1) * 0.5), Vector3(0.03, 0.025, (pz1 - pz0) * 0.4), 0.015, TruckBuilder.DARK)
		b._plate("gloss", Vector3(x + 0.03 * s, 2.034, (pz0 + pz1) * 0.5), 0.05, (pz1 - pz0) * 0.75, Vector3.DOWN, TruckBuilder.LAMP)
		# Grab rails either side of the panel.
		for zz: float in [pz0 - 0.02, pz1 + 0.02]:
			b._rod("metal", [Vector3(x, 0.8, zz), Vector3(x + 0.07 * s, 0.8, zz), Vector3(x + 0.07 * s, 1.95, zz), Vector3(x, 1.95, zz)], 0.016, TruckBuilder.CHROME, 8)
	# Chrome trim round each compartment, a drip rail over it.
	for s: float in [-1.0, 1.0]:
		var x := (bw + 0.008) * s
		for d: Array in doors:
			var dz0 := float(d[0]) - 0.03
			var dz1 := float(d[1]) + 0.03
			var dy0 := float(d[2]) - 0.03
			var dy1 := float(d[3]) + 0.03
			for zz: float in [dz0, dz1]:
				b._box("metal", Vector3(x, (dy0 + dy1) * 0.5, zz), Vector3(0.012, dy1 - dy0, 0.03), TruckBuilder.CHROME)
			b._box("metal", Vector3(x, dy0, (dz0 + dz1) * 0.5), Vector3(0.012, 0.03, dz1 - dz0), TruckBuilder.CHROME)
			b._bev("metal", Vector3(x + 0.015 * s, dy1 + 0.02, (dz0 + dz1) * 0.5), Vector3(0.025, 0.012, (dz1 - dz0) * 0.5), 0.008, TruckBuilder.CHROME)
		# Scene lights high on the body, fore and aft.
		for zz: float in [z0 + 1.15, z1 - 0.45]:
			b._bev("rough", Vector3((bw + 0.03) * s, y1 - 0.22, zz), Vector3(0.03, 0.08, 0.16), 0.015, TruckBuilder.DARK)
			b._plate("gloss", Vector3((bw + 0.061) * s, y1 - 0.22, zz), 0.28, 0.12, Vector3(s, 0, 0), TruckBuilder.LAMP)
		# Reflective tape along the sill, red and white.
		var zt := z0 + 0.05
		var k := 0
		while zt < z1 - 0.1:
			var col := STRIPE_RED if k % 2 == 0 else Color(0.96, 0.96, 0.94)
			var za := zt
			var zb := minf(zt + 0.3, z1 - 0.05)
			var ty := y0 + 0.02
			if za < float(doors[1][1]) + 0.05 and zb > float(doors[1][0]) - 0.05:
				ty = mid + 0.0 # over the wheel, the tape steps up
			b._quad("gloss", Vector3(x + 0.003 * s, ty, za), Vector3(x + 0.003 * s, ty, zb), Vector3(x + 0.003 * s, ty + 0.05, zb), Vector3(x + 0.003 * s, ty + 0.05, za), Vector3(s, 0, 0), col)
			zt += 0.3
			k += 1
	# The deck gun's supply pipe up from the pump, its handwheel.
	b._rod("metal", [Vector3(0, y1 - 0.4, gun.z + 0.35), Vector3(0, y1 + 0.05, gun.z + 0.35), Vector3(0, y1 + 0.05, gun.z)], 0.07, TruckBuilder.CHROME, 12)
	b._ring("metal", gun + Vector3(0.12, 0.3, 0), 0.08, 0.1, Vector3.RIGHT, TruckBuilder.CHROME, 16)
	b._cyl("metal", gun + Vector3(0.09, 0.3, 0), gun + Vector3(0.12, 0.3, 0), 0.015, TruckBuilder.CHROME, 6)

class_name CarModels
extends RefCounted
## The cars of the game: made-up brands that nod to real ones, the way GTA
## does it. Each entry is everything that makes a model itself: its name,
## its shape (read by CarBuilder) and how it drives (read by Car).
##
## Shape measurements are in metres, front of the car toward -z, wheels on
## the ground at y = 0. "stations" loft the lower body from nose to tail as
## [z, half width, bottom y, top y]. "cabin" is the glasshouse: belt and roof
## heights, half widths at the belt and roof, and the z of the windshield
## foot, windshield top, rear glass top and rear glass foot.
##
## The rest of "shape" dresses the model (all optional): "seat" is the
## driver's hip point; "wheel_style" (mag5, alloy10 or steel6) and
## "caliper" colour; "bumper" (black, body or chrome); "lamps" (quad,
## projector or square) and "tails" (bar, wrap or tall); "handles" (chrome,
## body or black); "exhaust" (single, dual or side); "antenna" (fender, fin
## or mast); "chrome_trim" round the windows; "flares" on the arches;
## "interior" colours {seat, insert, dash, lower, carpet} and "trim" style
## (metal, wood or black); "plate" text; and the steering
## wheel's "wheel_size", "wheel_rise" and "wheel_reach" from the hips and
## "column_degrees" of tilt.
##
## "drive" is how it drives, in parts, so performance parts can change any
## of it (see CarParts):
##   body        mass (kg), weight_front (share on the front axle), cg_height
##               (m), drag (N per (m/s)^2), rolling (N per m/s), downforce
##               (N per (m/s)^2, spread over both axles)
##   engine      idle_rpm, redline_rpm, torque: [rpm, newton metres] points
##   gearbox     ratios (1st up), final drive, reverse, shift_time (s),
##               efficiency (share of the engine's torque reaching the wheels)
##   drivetrain  fwd, rwd or awd
##   tyres       grip (1.0 is a good tyre on dry pavement), rear_grip (rear
##               grip relative to the front), stiffness (N per radian of
##               slip, front pair), rear_stiffness (relative), spin_grip
##               (sideways grip a spinning or locked tyre keeps)
##   suspension  spring_hz (how quickly the body bobs: higher is stiffer),
##               damping (0.2 bouncy, 0.5 firm), travel (m each way),
##               anti_roll (how much the anti-roll bars resist lean)
##   brakes      force (N, all four), front_bias, handbrake_rear_grip
##   steering    max_degrees (at a crawl), high_speed_degrees (at 100 km/h),
##               speed and return (how fast the wheel turns and centres)

const MODELS := {
	"pony_gt": {
		"brand": "Dunmore",
		"model": "Pony GT",
		"kind": "Two-door coupe, rear-wheel drive",
		"blurb": "A loud, light-footed pony car. Rear-wheel drive and plenty of power: it'll hang its tail out if you ask it to.",
		"colours": ["#b3261e", "#1f3f7a", "#e8e4d8", "#1a1a1a", "#d9a21b"],
		"shape": {
			"length": 4.62, "width": 1.84, "height": 1.32,
			"wheel_radius": 0.33, "wheel_width": 0.24, "track_half": 0.83,
			"front_axle": -1.38, "rear_axle": 1.32,
			"stations": [
				[-2.31, 0.84, 0.27, 0.56], [-2.26, 0.89, 0.24, 0.66], [-2.0, 0.91, 0.24, 0.73],
				[-1.2, 0.92, 0.25, 0.8], [-0.45, 0.92, 0.25, 0.86], [0.75, 0.92, 0.25, 0.88],
				[1.45, 0.92, 0.26, 0.9], [2.1, 0.9, 0.27, 0.89], [2.27, 0.87, 0.28, 0.78], [2.31, 0.84, 0.3, 0.64],
			],
			"cabin": {"belt": 0.86, "roof": 1.32, "wb": 0.86, "wr": 0.66, "za": -0.5, "zb": 0.22, "zc": 0.85, "zd": 1.62,
				"doors": 2, "c_pillar": 0.18},
			"hood_scoop": true, "spoiler": true, "stripes": true,
			"seat": [-0.4, 0.43, 0.4], "lights_y": 0.58, "tail_y": 0.72,
			# Polished five-spoke mags on raised-white-letter tyres, red calipers.
			"wheel_style": "mag5", "caliper": "#a8231a",
			"bumper": "black", "lamps": "quad", "tails": "bar", "handles": "black", "exhaust": "dual",
			"antenna": "fender", "drive": "rwd", "plate": "PNY 347",
			"interior": {"seat": "#1d1d20", "insert": "#7a1c17", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "metal"}, "wheel_size": 0.18, "wheel_rise": 0.35,
		},
		"drive": {
			# Light, loud and rear-driven: a big V8 and short gearing.
			"body": {"mass": 1480.0, "weight_front": 0.53, "cg_height": 0.46, "drag": 0.38, "rolling": 14.0, "downforce": 0.12},
			"engine": {"idle_rpm": 850.0, "redline_rpm": 7000.0,
				"torque": [[1000.0, 330.0], [2500.0, 430.0], [4500.0, 520.0], [6000.0, 480.0], [7000.0, 420.0]]},
			"gearbox": {"ratios": [3.6, 2.4, 1.75, 1.36, 1.12, 1.0], "final": 3.55, "reverse": 3.2, "shift_time": 0.2, "efficiency": 0.86},
			"drivetrain": "rwd",
			"tyres": {"grip": 1.02, "rear_grip": 1.06, "stiffness": 90000.0, "rear_stiffness": 1.25, "spin_grip": 0.4},
			"suspension": {"spring_hz": 1.9, "damping": 0.42, "travel": 0.12, "anti_roll": 0.55},
			"brakes": {"force": 13000.0, "front_bias": 0.64, "handbrake_rear_grip": 0.42},
			"steering": {"max_degrees": 37.0, "high_speed_degrees": 5.5, "speed": 3.2, "return": 5.5},
		},
	},
	"civique": {
		"brand": "Hanaka",
		"model": "Civique",
		"kind": "Four-door sedan, front-wheel drive",
		"blurb": "The sensible one. Front-wheel drive, light steering, and it goes where you point it. Half the Island learned to drive in one.",
		"colours": ["#2f5a56", "#8c8f93", "#6b1f24", "#e9e7e1", "#25324a"],
		"shape": {
			"length": 4.72, "width": 1.8, "height": 1.42,
			"wheel_radius": 0.31, "wheel_width": 0.2, "track_half": 0.81,
			"front_axle": -1.35, "rear_axle": 1.35,
			"stations": [
				[-2.36, 0.83, 0.3, 0.6], [-2.31, 0.87, 0.27, 0.69], [-2.1, 0.89, 0.27, 0.77],
				[-1.5, 0.9, 0.28, 0.84], [-0.8, 0.9, 0.28, 0.9], [0.9, 0.9, 0.28, 0.92],
				[1.55, 0.89, 0.28, 0.91], [2.15, 0.87, 0.29, 0.88], [2.31, 0.84, 0.3, 0.72], [2.36, 0.81, 0.32, 0.62],
			],
			"cabin": {"belt": 0.9, "roof": 1.41, "wb": 0.86, "wr": 0.69, "za": -0.82, "zb": -0.06, "zc": 0.78, "zd": 1.45,
				"doors": 4, "c_pillar": 0.26},
			"seat": [-0.38, 0.53, 0.18], "lights_y": 0.57, "tail_y": 0.68,
			# Ten-spoke alloys, body-colour bumpers, wrap-round tail lamps.
			"wheel_style": "alloy10", "caliper": "#8c8e92",
			"bumper": "body", "lamps": "projector", "tails": "wrap", "handles": "body", "exhaust": "single",
			"chrome_trim": true, "antenna": "fin", "drive": "fwd", "plate": "RCL 902",
			"interior": {"seat": "#45464a", "insert": "#7a7b80", "dash": "#232428", "lower": "#45464b", "carpet": "#2a2a2e", "trim": "black"},
		},
		"drive": {
			# The sensible one: a small four, five speeds, front-wheel drive.
			"body": {"mass": 1350.0, "weight_front": 0.6, "cg_height": 0.52, "drag": 0.42, "rolling": 15.0, "downforce": 0.0},
			"engine": {"idle_rpm": 800.0, "redline_rpm": 6600.0,
				"torque": [[1000.0, 125.0], [2500.0, 160.0], [4300.0, 178.0], [5800.0, 168.0], [6600.0, 145.0]]},
			"gearbox": {"ratios": [3.3, 1.95, 1.36, 1.03, 0.8], "final": 4.1, "reverse": 3.2, "shift_time": 0.25, "efficiency": 0.88},
			"drivetrain": "fwd",
			"tyres": {"grip": 1.0, "rear_grip": 1.12, "stiffness": 82000.0, "rear_stiffness": 1.3, "spin_grip": 0.4},
			"suspension": {"spring_hz": 1.6, "damping": 0.38, "travel": 0.13, "anti_roll": 0.5},
			"brakes": {"force": 10500.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.5},
		},
	},
	"halfton": {
		"brand": "Fjord",
		"model": "Halfton 150",
		"kind": "Pickup truck, rear-wheel drive",
		"blurb": "A full-size pickup with a big engine and a light back end. Soft, tall and heavy: it leans in the corners and the box can step out on a wet day.",
		"colours": ["#3b4a3a", "#c9c3b4", "#7a1d1a", "#1d2b44", "#4a4a4c"],
		"shape": {
			"length": 5.55, "width": 2.02, "height": 1.92,
			"wheel_radius": 0.4, "wheel_width": 0.27, "track_half": 0.88,
			"front_axle": -1.78, "rear_axle": 1.7,
			"stations": [
				[-2.78, 0.94, 0.48, 0.92], [-2.72, 0.99, 0.42, 1.08], [-2.4, 1.0, 0.42, 1.18],
				[-1.3, 1.0, 0.44, 1.24], [-0.6, 1.0, 0.44, 1.27], [0.45, 1.0, 0.44, 1.28],
				# Behind the cab the body drops to the floor of the box.
				[0.5, 1.0, 0.44, 0.98], [2.6, 1.0, 0.45, 0.98], [2.74, 0.98, 0.48, 0.98], [2.78, 0.95, 0.52, 0.96],
			],
			"cabin": {"belt": 1.27, "roof": 1.92, "wb": 0.96, "wr": 0.86, "za": -0.62, "zb": -0.18, "zc": 0.42, "zd": 0.46,
				"doors": 2, "c_pillar": 0.06},
			"bed": {"z0": 0.5, "z1": 2.76, "floor": 0.98, "top": 1.28, "thick": 0.07},
			"seat": [-0.42, 0.95, 0.03], "lights_y": 0.98, "tail_y": 1.05,
			# Six-hole steel wheels on chunky all-terrains, chrome bumpers and
			# grille, black arch flares and towing mirrors.
			"wheel_style": "steel6", "caliper": "#1c1c1c", "flares": true,
			"bumper": "chrome", "lamps": "square", "tails": "tall", "handles": "black", "exhaust": "side",
			"antenna": "mast", "drive": "rwd", "fuel_z": 0.85, "plate": "HAY 150",
			"interior": {"seat": "#7d6a4e", "insert": "#a8926e", "dash": "#3b342b", "lower": "#6e5f48", "carpet": "#3d352b", "trim": "wood"}, "wheel_size": 0.2, "wheel_rise": 0.37, "column_degrees": 28.0,
		},
		"drive": {
			# Heavy, tall and soft, with a big lazy V8 and a light back end.
			"body": {"mass": 2150.0, "weight_front": 0.56, "cg_height": 0.78, "drag": 0.75, "rolling": 22.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 5800.0,
				"torque": [[1000.0, 420.0], [2500.0, 520.0], [3800.0, 545.0], [5000.0, 500.0], [5800.0, 430.0]]},
			"gearbox": {"ratios": [4.2, 2.8, 2.05, 1.6, 1.3], "final": 3.73, "reverse": 3.3, "shift_time": 0.3, "efficiency": 0.85},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.92, "rear_grip": 1.1, "stiffness": 115000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.3, "damping": 0.33, "travel": 0.18, "anti_roll": 0.35},
			"brakes": {"force": 15500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.46},
			"steering": {"max_degrees": 33.0, "high_speed_degrees": 4.5, "speed": 2.6, "return": 5.0},
		},
	},
}


static func get_model(id: String) -> Dictionary:
	return MODELS.get(id, MODELS["civique"])


static func full_name(id: String) -> String:
	var m := get_model(id)
	return "%s %s" % [m["brand"], m["model"]]

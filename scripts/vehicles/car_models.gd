class_name CarModels
extends RefCounted
## The cars of the game: made-up brands that nod to real ones, the way GTA
## does it. Each make is sold only at its own dealers (map_config.json
## "brands", "stock"). Each entry is everything that makes a model itself: its name,
## its shape (read by CarBuilder) and how it drives (read by Car).
##
## Shape measurements are in metres, front of the car toward -z, wheels on
## the ground at y = 0. "stations" loft the lower body from nose to tail as
## [z, half width, bottom y, top y]. "cabin" is the glasshouse: belt and roof
## heights, half widths at the belt and roof, and the z of the windshield
## foot, windshield top, rear glass top and rear glass foot.
##
## The rest of "shape" dresses the model (all optional): "seat" is the
## driver's hip point; "grille" (crosshair: wide, split in four);
## "roof_rails"; "privacy_glass" (dark behind the front doors); "wheel_style" (mag5, alloy10 or steel6) and
## "caliper" colour; "bumper" (black, body or chrome); "lamps" (quad,
## projector or square) and "tails" (bar, wrap, tall or racetrack); "handles" (chrome,
## body or black); "exhaust" (single, dual or side); "antenna" (fender, fin
## or mast); "chrome_trim" round the windows; "flares" on the arches;
## "interior" colours {seat, insert, dash, lower, carpet} and "trim" style
## (metal, wood or black); "plate" text; and the steering
## wheel's "wheel_size", "wheel_rise" and "wheel_reach" from the hips and
## "column_degrees" of tilt.
##
## "sound" borrows another model's engine sounds (CarAudio; "" for an
## electric car's silence) and "pops" sets how keen it is to crackle.
## More dressing: "lamps" also round, slim, pixel or popup; "tails" pixel;
## "grille" big, slot or none; "wheel_style" also black5, gold10, lace,
## hubcap or aero; "spoiler" true or "wing"; "cladding", "woodgrain",
## "t_tops", "slider" (a van's sliding door track), "spare" (on the back)
## and "side_stripe" [y0, y1, colour]; "exhaust" none.
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
		"brand": "Fjord",
		"model": "Pony GT",
		"kind": "Two-door coupe, rear-wheel drive",
		"price": 38500,
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
		"price": 24500,
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
		"price": 46000,
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
	"jaunt": {
		"brand": "Dodgy",
		"model": "Jaunt",
		"kind": "Mid-size crossover, all-wheel drive",
		"blurb": "A seven-seat crossover with a V6 and a long roof. Not quick, not slow, everywhere. The town cops drive them too.",
		"colours": ["#9a9ea3", "#1c1d20", "#6e1418", "#e8e8e6", "#2c3e57"],
		"price": 34500,
		"shape": {
			"length": 4.89, "width": 1.83, "height": 1.69,
			"wheel_radius": 0.36, "wheel_width": 0.23, "track_half": 0.8,
			"front_axle": -1.46, "rear_axle": 1.43,
			"stations": [
				[-2.44, 0.78, 0.45, 0.86], [-2.4, 0.84, 0.4, 0.96], [-2.2, 0.88, 0.38, 1.03],
				[-1.5, 0.905, 0.37, 1.11], [-1.15, 0.91, 0.37, 1.14], [0.9, 0.915, 0.38, 1.16],
				[1.7, 0.91, 0.39, 1.16], [2.2, 0.885, 0.41, 1.15], [2.36, 0.85, 0.44, 1.12], [2.44, 0.8, 0.5, 1.07],
			],
			# Slab sides and a high belt, so the glass is a short band; a raked
			# windshield, a flat roof, a thick D-pillar and a raked hatch.
			"cabin": {"belt": 1.16, "roof": 1.69, "wb": 0.84, "wr": 0.66, "za": -1.05, "zb": -0.1, "zc": 1.96, "zd": 2.33,
				"doors": 4, "c_pillar": 0.45},
			"seat": [-0.4, 0.76, 0.1], "lights_y": 0.94, "tail_y": 0.98,
			# The crosshair grille between swept lamps, ten-spoke alloys,
			# body-colour bumpers and one racetrack tail lamp across the back.
			"grille": "crosshair", "roof_rails": true, "privacy_glass": true,
			"wheel_style": "alloy10", "caliper": "#3a3b3e",
			"bumper": "body", "lamps": "projector", "tails": "racetrack", "handles": "body", "exhaust": "dual",
			"antenna": "fin", "drive": "awd", "plate": "DGY 360",
			"interior": {"seat": "#2a2b2e", "insert": "#3e3f44", "dash": "#1d1e21", "lower": "#2e2f33", "carpet": "#1f1f22", "trim": "black"},
			"wheel_size": 0.19, "wheel_rise": 0.36, "column_degrees": 24.0,
		},
		"drive": {
			# A 3.6 V6, six speeds, all-wheel drive, and nearly two tonnes.
			"body": {"mass": 1950.0, "weight_front": 0.58, "cg_height": 0.64, "drag": 0.52, "rolling": 18.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 6400.0,
				"torque": [[1000.0, 240.0], [2500.0, 300.0], [4300.0, 353.0], [5600.0, 335.0], [6400.0, 300.0]]},
			"gearbox": {"ratios": [4.46, 2.51, 1.56, 1.14, 0.85, 0.67], "final": 3.83, "reverse": 3.2, "shift_time": 0.25, "efficiency": 0.85},
			"drivetrain": "awd",
			"tyres": {"grip": 0.96, "rear_grip": 1.1, "stiffness": 95000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.38, "travel": 0.15, "anti_roll": 0.45},
			"brakes": {"force": 14000.0, "front_bias": 0.64, "handbrake_rear_grip": 0.48},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
	"rammer": {
		"brand": "Dodgy",
		"model": "Rammer 1500",
		"kind": "Crew cab pickup, four-wheel drive",
		"blurb": "A crew cab pickup with a big Hemi and a short box. Tall, heavy and quicker than it has any right to be.",
		"colours": ["#1a1a1c", "#e8e8e6", "#7d1a1d", "#5a5d61", "#24364f"],
		"price": 52000,
		"shape": {
			"length": 5.82, "width": 2.08, "height": 1.97,
			"wheel_radius": 0.41, "wheel_width": 0.28, "track_half": 0.88,
			"front_axle": -1.86, "rear_axle": 1.81,
			"stations": [
				[-2.91, 0.95, 0.52, 1.02], [-2.85, 1.01, 0.46, 1.2], [-2.5, 1.03, 0.45, 1.28],
				[-1.4, 1.04, 0.46, 1.32], [-0.8, 1.04, 0.46, 1.34], [1.08, 1.04, 0.46, 1.35],
				# Behind the cab the body drops to the floor of the box.
				[1.13, 1.04, 0.46, 1.02], [2.7, 1.04, 0.47, 1.02], [2.84, 1.02, 0.5, 1.02], [2.88, 0.99, 0.54, 1.0],
			],
			"cabin": {"belt": 1.34, "roof": 1.97, "wb": 0.99, "wr": 0.9, "za": -0.82, "zb": -0.32, "zc": 1.05, "zd": 1.09,
				"doors": 4, "c_pillar": 0.06},
			"bed": {"z0": 1.13, "z1": 2.82, "floor": 1.02, "top": 1.36, "thick": 0.07},
			"seat": [-0.44, 1.0, -0.15], "lights_y": 1.06, "tail_y": 1.12,
			# Six-hole wheels on all-terrains, a chrome grille and bumpers,
			# black arch flares.
			"wheel_style": "steel6", "caliper": "#1c1c1c", "flares": true,
			"bumper": "chrome", "lamps": "square", "tails": "tall", "handles": "body", "exhaust": "side",
			"antenna": "fin", "drive": "awd", "fuel_z": 1.45, "plate": "RAM 157",
			"interior": {"seat": "#25262a", "insert": "#3a3b40", "dash": "#1b1c1f", "lower": "#2a2b2f", "carpet": "#1d1d20", "trim": "metal"},
			"wheel_size": 0.2, "wheel_rise": 0.37, "column_degrees": 26.0,
		},
		"drive": {
			# A 5.7 Hemi V8, eight speeds, four-wheel drive, two and a half tonnes.
			"body": {"mass": 2450.0, "weight_front": 0.57, "cg_height": 0.8, "drag": 0.78, "rolling": 24.0, "downforce": 0.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 5800.0,
				"torque": [[1000.0, 430.0], [2500.0, 520.0], [3950.0, 556.0], [5000.0, 520.0], [5800.0, 450.0]]},
			"gearbox": {"ratios": [4.71, 3.14, 2.11, 1.67, 1.29, 1.0, 0.84, 0.67], "final": 3.21, "reverse": 3.3, "shift_time": 0.22, "efficiency": 0.84},
			"drivetrain": "awd",
			"tyres": {"grip": 0.92, "rear_grip": 1.1, "stiffness": 120000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.35, "damping": 0.35, "travel": 0.18, "anti_roll": 0.38},
			"brakes": {"force": 17500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.46},
			"steering": {"max_degrees": 33.0, "high_speed_degrees": 4.4, "speed": 2.6, "return": 5.0},
		},
	},
	"interlude": {
		# Our 1988-91 Honda Prelude: a low, wide coupe with pop-up lamps and a huge glasshouse.
		"brand": "Hanaka",
		"model": "Interlude",
		"kind": "Two-door coupe, front-wheel drive",
		"price": 24000,
		"blurb": "A low, wide 80s coupe with pop-up lamps and a glasshouse like a fishbowl. A revvy four up front: it turns in like it's on rails.",
		"colours": ["#a8a9ad", "#7a1a22", "#e8e6df", "#1a1a1c", "#2a4466"],
		"sound": "civique",
		"shape": {
			"length": 4.46, "width": 1.7, "height": 1.29, "wheel_radius": 0.29, "wheel_width": 0.19,
			"track_half": 0.74, "front_axle": -1.29, "rear_axle": 1.27,
			"stations": [
				[-2.23, 0.773, 0.28, 0.5], [-2.18, 0.816, 0.25, 0.6], [-1.93, 0.837, 0.25, 0.666],
				[-1.383, 0.85, 0.26, 0.743], [-0.669, 0.85, 0.26, 0.79], [0.847, 0.85, 0.26, 0.815],
				[1.45, 0.846, 0.27, 0.84], [1.98, 0.825, 0.28, 0.83], [2.18, 0.79, 0.29, 0.8],
				[2.23, 0.765, 0.31, 0.7],
			],
			"cabin": {"belt": 0.82, "roof": 1.29, "wb": 0.8, "wr": 0.64, "za": -0.62, "zb": 0.16, "zc": 0.98, "zd": 1.62, "doors": 2, "c_pillar": 0.14},
			"seat": [-0.38, 0.4, 0.3], "lights_y": 0.56, "tail_y": 0.68, "grille": "slot", "wheel_style": "alloy10",
			"caliper": "#3a3a3c", "bumper": "body", "lamps": "popup", "tails": "bar", "handles": "black",
			"exhaust": "single", "antenna": "fender", "drive": "fwd", "plate": "PRL 088",
			"interior": {"seat": "#3c3d41", "insert": "#5c5d62", "dash": "#202124", "lower": "#3a3b3f", "carpet": "#232326", "trim": "black"},
			"wheel_size": 0.18, "wheel_rise": 0.34,
		},
		"drive": {
			"body": {"mass": 1180.0, "weight_front": 0.62, "cg_height": 0.48, "drag": 0.38, "rolling": 14.0, "downforce": 0.0},
			"engine": {"idle_rpm": 850.0, "redline_rpm": 7200.0, "torque": [[1000.0, 130.0], [3000.0, 165.0], [5000.0, 185.0], [6500.0, 175.0], [7200.0, 155.0]]},
			"gearbox": {"ratios": [3.17, 1.86, 1.26, 0.97, 0.78], "final": 4.27, "reverse": 3.0, "shift_time": 0.22, "efficiency": 0.88},
			"drivetrain": "fwd",
			"tyres": {"grip": 1.0, "rear_grip": 1.08, "stiffness": 85000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.8, "damping": 0.4, "travel": 0.12, "anti_roll": 0.55},
			"brakes": {"force": 10500.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.2, "speed": 3.2, "return": 5.5},
		},
	},
	"rcv": {
		# Our Honda CR-V: the sensible compact crossover.
		"brand": "Hanaka",
		"model": "RC-V",
		"kind": "Compact crossover, all-wheel drive",
		"price": 35500,
		"blurb": "The Civique's sensible big sibling: tall, roomy and all-wheel drive. A small turbo four and a smooth automatic. It will never surprise you.",
		"colours": ["#7d8186", "#e9e7e1", "#1f2a3d", "#5e1a1e", "#3b4a3a"],
		"sound": "civique",
		"shape": {
			"length": 4.7, "width": 1.86, "height": 1.68, "wheel_radius": 0.36, "wheel_width": 0.23,
			"track_half": 0.81, "front_axle": -1.36, "rear_axle": 1.34,
			"stations": [
				[-2.35, 0.846, 0.41, 0.86], [-2.3, 0.893, 0.38, 0.96], [-2.05, 0.916, 0.38, 1.009],
				[-1.457, 0.93, 0.39, 1.065], [-0.705, 0.93, 0.39, 1.1], [0.893, 0.93, 0.39, 1.115],
				[1.528, 0.925, 0.4, 1.13], [2.1, 0.902, 0.41, 1.12], [2.3, 0.865, 0.42, 1.09],
				[2.35, 0.837, 0.44, 0.99],
			],
			"cabin": {"belt": 1.1, "roof": 1.68, "wb": 0.86, "wr": 0.7, "za": -1.0, "zb": -0.12, "zc": 1.85, "zd": 2.25, "doors": 4, "c_pillar": 0.32},
			"seat": [-0.39, 0.72, 0.08], "lights_y": 0.86, "tail_y": 0.98, "roof_rails": true, "privacy_glass": true,
			"cladding": true, "flares": true, "wheel_style": "alloy10", "caliper": "#5a5b5e", "chrome_trim": true,
			"bumper": "body", "lamps": "slim", "tails": "tall", "handles": "body", "exhaust": "dual",
			"antenna": "fin", "drive": "awd", "plate": "CRV 517",
			"interior": {"seat": "#3c3d41", "insert": "#5c5d62", "dash": "#202124", "lower": "#3a3b3f", "carpet": "#232326", "trim": "black"},
			"wheel_size": 0.19, "wheel_rise": 0.36,
		},
		"drive": {
			"body": {"mass": 1620.0, "weight_front": 0.6, "cg_height": 0.6, "drag": 0.5, "rolling": 17.0, "downforce": 0.0},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 6200.0, "torque": [[1000.0, 160.0], [1700.0, 240.0], [4500.0, 240.0], [5600.0, 215.0], [6200.0, 185.0]]},
			"gearbox": {"ratios": [3.4, 2.1, 1.5, 1.15, 0.9, 0.72], "final": 4.0, "reverse": 3.1, "shift_time": 0.18, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 0.97, "rear_grip": 1.1, "stiffness": 92000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.38, "travel": 0.15, "anti_roll": 0.45},
			"brakes": {"force": 13500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
	"haulux": {
		# Our 1984-88 Toyota Hilux: a small square 4x4 pickup that can't be killed.
		"brand": "Toyola",
		"model": "Haulux",
		"kind": "Compact pickup, four-wheel drive",
		"price": 22000,
		"blurb": "A small, square 80s pickup with a solid front axle and a four that will outlive you. Slow on the highway, unstoppable everywhere else.",
		"colours": ["#b8302a", "#e6e2d6", "#1d2b44", "#3c3c3e", "#6d7a5a"],
		"sound": "civique",
		"shape": {
			"length": 4.43, "width": 1.69, "height": 1.72, "wheel_radius": 0.37, "wheel_width": 0.24,
			"track_half": 0.73, "front_axle": -1.42, "rear_axle": 1.2,
			"stations": [
				[-2.215, 0.8, 0.52, 0.92], [-2.16, 0.84, 0.47, 1.04], [-1.9, 0.845, 0.47, 1.08],
				[-1.2, 0.845, 0.48, 1.1], [-0.6, 0.845, 0.48, 1.12], [0.38, 0.845, 0.48, 1.12],
				[0.43, 0.845, 0.48, 0.92], [2.0, 0.845, 0.49, 0.92], [2.14, 0.84, 0.51, 0.92],
				[2.18, 0.82, 0.55, 0.9],
			],
			"cabin": {"belt": 1.12, "roof": 1.72, "wb": 0.8, "wr": 0.72, "za": -0.82, "zb": -0.4, "zc": 0.33, "zd": 0.36, "doors": 2, "c_pillar": 0.06},
			"bed": {"z0": 0.43, "z1": 2.16, "floor": 0.92, "top": 1.16, "thick": 0.06}, "seat": [-0.38, 0.86, 0.02],
			"lights_y": 0.92, "tail_y": 0.98, "wheel_style": "steel6", "caliper": "#1c1c1c", "flares": true,
			"bumper": "chrome", "lamps": "square", "tails": "tall", "handles": "black", "exhaust": "side",
			"antenna": "fender", "drive": "awd", "fuel_z": 0.15, "plate": "HLX 884",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"wheel_size": 0.19, "wheel_rise": 0.36, "column_degrees": 30.0,
		},
		"drive": {
			"body": {"mass": 1450.0, "weight_front": 0.57, "cg_height": 0.72, "drag": 0.62, "rolling": 20.0, "downforce": 0.0},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 5200.0, "torque": [[1000.0, 150.0], [2400.0, 188.0], [3400.0, 192.0], [4600.0, 170.0], [5200.0, 150.0]]},
			"gearbox": {"ratios": [3.93, 2.33, 1.45, 1.0, 0.85], "final": 4.1, "reverse": 4.2, "shift_time": 0.3, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 0.92, "rear_grip": 1.08, "stiffness": 95000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.4, "damping": 0.32, "travel": 0.18, "anti_roll": 0.3},
			"brakes": {"force": 11500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 33.0, "high_speed_degrees": 4.8, "speed": 2.6, "return": 5.0},
		},
	},
	"pious": {
		# Our 2004-09 Toyota Prius: the hybrid wedge with the cut-off tail.
		"brand": "Toyola",
		"model": "Pious",
		"kind": "Hybrid hatchback, front-wheel drive",
		"price": 27000,
		"blurb": "The hybrid with the chopped-off tail. Pulls away on electric shove, then runs out of puff by the highway. Nobody has ever been late in one.",
		"colours": ["#c4c6c9", "#2c4f6e", "#e9e7e1", "#3f5a3f", "#6a1e22"],
		"sound": "civique",
		"shape": {
			"length": 4.45, "width": 1.72, "height": 1.49, "wheel_radius": 0.31, "wheel_width": 0.19,
			"track_half": 0.75, "front_axle": -1.35, "rear_axle": 1.35,
			"stations": [
				[-2.225, 0.783, 0.31, 0.56], [-2.175, 0.826, 0.28, 0.66], [-1.925, 0.847, 0.28, 0.73],
				[-1.379, 0.86, 0.29, 0.81], [-0.667, 0.86, 0.29, 0.86], [0.846, 0.86, 0.29, 0.93],
				[1.446, 0.856, 0.3, 1.0], [1.975, 0.834, 0.31, 0.99], [2.175, 0.8, 0.32, 0.98],
				[2.225, 0.774, 0.34, 0.88],
			],
			"cabin": {"belt": 0.92, "roof": 1.49, "wb": 0.82, "wr": 0.64, "za": -1.0, "zb": -0.1, "zc": 0.68, "zd": 2.08, "doors": 4, "c_pillar": 0.16},
			"seat": [-0.38, 0.6, 0.1], "lights_y": 0.58, "tail_y": 0.86, "grille": "slot", "wheel_style": "aero",
			"caliper": "#5a5b5e", "bumper": "body", "lamps": "projector", "tails": "wrap", "handles": "body",
			"exhaust": "single", "antenna": "fin", "drive": "fwd", "plate": "ECO 404",
			"interior": {"seat": "#3c3d41", "insert": "#5c5d62", "dash": "#202124", "lower": "#3a3b3f", "carpet": "#232326", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 1330.0, "weight_front": 0.6, "cg_height": 0.52, "drag": 0.36, "rolling": 12.0, "downforce": 0.0},
			"engine": {"idle_rpm": 1000.0, "redline_rpm": 5200.0, "torque": [[1000.0, 300.0], [2000.0, 270.0], [3200.0, 210.0], [4400.0, 170.0], [5200.0, 150.0]]},
			"gearbox": {"ratios": [2.8, 1.9, 1.4, 1.05, 0.8], "final": 3.27, "reverse": 3.0, "shift_time": 0.12, "efficiency": 0.9},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.94, "rear_grip": 1.12, "stiffness": 78000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.6, "damping": 0.36, "travel": 0.13, "anti_roll": 0.45},
			"brakes": {"force": 10500.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.5},
		},
	},
	"corollo": {
		# Our Toyota Corolla: the plain, reliable compact sedan.
		"brand": "Toyola",
		"model": "Corollo",
		"kind": "Four-door sedan, front-wheel drive",
		"price": 23000,
		"blurb": "Plain, quiet, and it starts every morning for twenty years. Hubcaps, a small four and an automatic. The Civique's sensible rival.",
		"colours": ["#9a9da1", "#e9e7e1", "#1c1d20", "#24364f", "#7a1d22"],
		"sound": "civique",
		"shape": {
			"length": 4.64, "width": 1.78, "height": 1.46, "wheel_radius": 0.31, "wheel_width": 0.2,
			"track_half": 0.78, "front_axle": -1.36, "rear_axle": 1.34,
			"stations": [
				[-2.32, 0.81, 0.32, 0.56], [-2.27, 0.854, 0.29, 0.66], [-2.02, 0.877, 0.29, 0.741],
				[-1.438, 0.89, 0.3, 0.833], [-0.696, 0.89, 0.3, 0.89], [0.882, 0.89, 0.3, 0.91],
				[1.508, 0.886, 0.31, 0.93], [2.07, 0.863, 0.32, 0.92], [2.27, 0.828, 0.33, 0.74],
				[2.32, 0.801, 0.35, 0.64],
			],
			"cabin": {"belt": 0.92, "roof": 1.46, "wb": 0.84, "wr": 0.67, "za": -0.85, "zb": -0.08, "zc": 0.8, "zd": 1.48, "doors": 4, "c_pillar": 0.24},
			"seat": [-0.38, 0.55, 0.16], "lights_y": 0.57, "tail_y": 0.66, "grille": "slot", "wheel_style": "hubcap",
			"caliper": "#5a5b5e", "chrome_trim": true, "bumper": "body", "lamps": "slim", "tails": "wrap",
			"handles": "body", "exhaust": "single", "antenna": "fin", "drive": "fwd", "plate": "CRL 115",
			"interior": {"seat": "#1d1d20", "insert": "#2c2d31", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 1300.0, "weight_front": 0.61, "cg_height": 0.53, "drag": 0.4, "rolling": 14.0, "downforce": 0.0},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 6400.0, "torque": [[1000.0, 120.0], [2500.0, 155.0], [4400.0, 173.0], [5600.0, 162.0], [6400.0, 140.0]]},
			"gearbox": {"ratios": [3.6, 2.1, 1.42, 1.0, 0.8, 0.66], "final": 4.0, "reverse": 3.2, "shift_time": 0.25, "efficiency": 0.87},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.97, "rear_grip": 1.12, "stiffness": 80000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.37, "travel": 0.13, "anti_roll": 0.48},
			"brakes": {"force": 10500.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.5},
		},
	},
	"caravel": {
		# Our 1996-2007 Dodge Grand Caravan, built in Windsor: the minivan.
		"brand": "Dodgy",
		"model": "Caravel",
		"kind": "Minivan, front-wheel drive",
		"price": 28000,
		"blurb": "The minivan. Sliding doors, seven seats, a V6 and a four-speed automatic. Drives like a couch on a boat, and half the country grew up in the back of one.",
		"colours": ["#6c1e24", "#c4c6c9", "#2e4a3c", "#e9e7e1", "#2a3550"],
		"sound": "jaunt",
		"shape": {
			"length": 5.09, "width": 2.0, "height": 1.75, "wheel_radius": 0.34, "wheel_width": 0.22,
			"track_half": 0.84, "front_axle": -1.62, "rear_axle": 1.48,
			"stations": [
				[-2.545, 0.901, 0.36, 0.72], [-2.495, 0.95, 0.33, 0.82], [-2.245, 0.975, 0.33, 0.893],
				[-1.578, 0.99, 0.34, 0.978], [-0.763, 0.99, 0.34, 1.03], [0.967, 0.99, 0.34, 1.045],
				[1.654, 0.985, 0.35, 1.06], [2.295, 0.96, 0.36, 1.05], [2.495, 0.921, 0.37, 1.02],
				[2.545, 0.891, 0.39, 0.92],
			],
			"cabin": {"belt": 1.03, "roof": 1.75, "wb": 0.92, "wr": 0.8, "za": -1.6, "zb": -0.6, "zc": 2.25, "zd": 2.47, "doors": 4, "c_pillar": 0.32},
			"seat": [-0.42, 0.72, -0.4], "lights_y": 0.76, "tail_y": 0.92, "grille": "crosshair", "slider": true,
			"roof_rails": true, "privacy_glass": true, "wheel_style": "hubcap", "caliper": "#3a3b3e",
			"chrome_trim": true, "bumper": "body", "lamps": "projector", "tails": "tall", "handles": "body",
			"exhaust": "single", "antenna": "fender", "drive": "fwd", "plate": "VAN 007",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"wheel_size": 0.19, "wheel_rise": 0.36, "column_degrees": 26.0,
		},
		"drive": {
			"body": {"mass": 2000.0, "weight_front": 0.6, "cg_height": 0.66, "drag": 0.6, "rolling": 19.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 5800.0, "torque": [[1000.0, 240.0], [2500.0, 290.0], [3800.0, 305.0], [5000.0, 270.0], [5800.0, 230.0]]},
			"gearbox": {"ratios": [2.84, 1.57, 1.0, 0.69], "final": 3.62, "reverse": 2.2, "shift_time": 0.35, "efficiency": 0.84},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.93, "rear_grip": 1.12, "stiffness": 90000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.2, "damping": 0.3, "travel": 0.15, "anti_roll": 0.35},
			"brakes": {"force": 13500.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.6, "speed": 2.6, "return": 5.0},
		},
	},
	"charlatan": {
		# Our Dodge Charger: a big rear-drive sedan with a supercharged V8 and the racetrack tail lamp.
		"brand": "Dodgy",
		"model": "Charlatan SRT",
		"kind": "Four-door sport sedan, rear-wheel drive",
		"price": 58000,
		"blurb": "A full-size family sedan with a supercharged V8 crammed under the hood. Heavy, loud and furious in a straight line. Corners are a suggestion.",
		"colours": ["#1a1a1c", "#b3261e", "#e8e8e6", "#3d5a2a", "#5a5d61"],
		"sound": "rammer",
		"pops": 1.0,
		"shape": {
			"length": 5.1, "width": 1.9, "height": 1.48, "wheel_radius": 0.35, "wheel_width": 0.27,
			"track_half": 0.81, "front_axle": -1.58, "rear_axle": 1.5,
			"stations": [
				[-2.55, 0.864, 0.3, 0.66], [-2.5, 0.912, 0.27, 0.76], [-2.25, 0.936, 0.27, 0.837],
				[-1.581, 0.95, 0.28, 0.925], [-0.765, 0.95, 0.28, 0.98], [0.969, 0.95, 0.28, 0.99],
				[1.657, 0.945, 0.29, 1.0], [2.3, 0.921, 0.3, 0.99], [2.5, 0.883, 0.31, 0.86],
				[2.55, 0.855, 0.33, 0.76],
			],
			"cabin": {"belt": 0.98, "roof": 1.48, "wb": 0.86, "wr": 0.67, "za": -0.75, "zb": 0.08, "zc": 0.92, "zd": 1.7, "doors": 4, "c_pillar": 0.3},
			"seat": [-0.4, 0.54, 0.2], "lights_y": 0.67, "tail_y": 0.77, "grille": "crosshair", "hood_scoop": true,
			"spoiler": true, "wheel_style": "black5", "caliper": "#c22a1e", "bumper": "body", "lamps": "projector",
			"tails": "racetrack", "handles": "body", "exhaust": "dual", "antenna": "fin", "drive": "rwd",
			"plate": "SRT 707",
			"interior": {"seat": "#1d1d20", "insert": "#2c2d31", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 2000.0, "weight_front": 0.56, "cg_height": 0.52, "drag": 0.42, "rolling": 16.0, "downforce": 0.08},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 6200.0, "torque": [[1000.0, 430.0], [2500.0, 680.0], [4000.0, 820.0], [5200.0, 790.0], [6200.0, 700.0]]},
			"gearbox": {"ratios": [4.71, 3.14, 2.11, 1.67, 1.29, 1.0, 0.84, 0.67], "final": 2.62, "reverse": 3.3, "shift_time": 0.15, "efficiency": 0.86},
			"drivetrain": "rwd",
			"tyres": {"grip": 1.04, "rear_grip": 1.04, "stiffness": 105000.0, "rear_stiffness": 1.25, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.7, "damping": 0.42, "travel": 0.13, "anti_roll": 0.5},
			"brakes": {"force": 18000.0, "front_bias": 0.62, "handbrake_rear_grip": 0.42},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
	"crown_vista": {
		# Our 1998-2011 Ford Crown Victoria: a long, square body-on-frame V8 sedan. Ex-cop cars and taxis.
		"brand": "Fjord",
		"model": "Crown Vista",
		"kind": "Full-size sedan, rear-wheel drive",
		"price": 36000,
		"blurb": "Five and a half metres of sedan on a truck frame, with a V8 and a bench's worth of room. Floats over bumps, wallows in corners, and slides like a dream.",
		"colours": ["#e8e6df", "#1a1a1c", "#2b3e30", "#5a1e22", "#9fa3a8"],
		"sound": "halfton",
		"shape": {
			"length": 5.39, "width": 1.99, "height": 1.46, "wheel_radius": 0.34, "wheel_width": 0.23,
			"track_half": 0.83, "front_axle": -1.56, "rear_axle": 1.5,
			"stations": [
				[-2.695, 0.901, 0.33, 0.66], [-2.645, 0.95, 0.3, 0.76], [-2.395, 0.975, 0.3, 0.83],
				[-1.671, 0.99, 0.31, 0.91], [-0.808, 0.99, 0.31, 0.96], [1.024, 0.99, 0.31, 0.97],
				[1.752, 0.985, 0.32, 0.98], [2.445, 0.96, 0.33, 0.97], [2.645, 0.921, 0.34, 0.88],
				[2.695, 0.891, 0.36, 0.78],
			],
			"cabin": {"belt": 0.96, "roof": 1.46, "wb": 0.9, "wr": 0.72, "za": -0.72, "zb": 0.02, "zc": 1.05, "zd": 1.62, "doors": 4, "c_pillar": 0.32},
			"seat": [-0.42, 0.55, 0.15], "lights_y": 0.67, "tail_y": 0.78, "wheel_style": "hubcap",
			"caliper": "#3a3b3e", "chrome_trim": true, "bumper": "body", "lamps": "square", "tails": "bar",
			"handles": "chrome", "exhaust": "dual", "antenna": "fender", "drive": "rwd", "plate": "CVC 461",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"column_degrees": 26.0,
		},
		"drive": {
			"body": {"mass": 1880.0, "weight_front": 0.55, "cg_height": 0.55, "drag": 0.5, "rolling": 17.0, "downforce": 0.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 5600.0, "torque": [[1000.0, 330.0], [2500.0, 390.0], [4000.0, 405.0], [5000.0, 370.0], [5600.0, 320.0]]},
			"gearbox": {"ratios": [2.84, 1.55, 1.0, 0.7], "final": 3.27, "reverse": 2.3, "shift_time": 0.3, "efficiency": 0.85},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.95, "rear_grip": 1.02, "stiffness": 88000.0, "rear_stiffness": 1.22, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.1, "damping": 0.28, "travel": 0.17, "anti_roll": 0.32},
			"brakes": {"force": 14500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.42},
			"steering": {"max_degrees": 36.0, "high_speed_degrees": 5.0, "speed": 2.7, "return": 5.0},
		},
	},
	"bucko": {
		# Our Ford Bronco (2021 on): a boxy two-door 4x4 with round lamps and a spare on the back.
		"brand": "Fjord",
		"model": "Bucko",
		"kind": "Two-door off-roader, four-wheel drive",
		"price": 48000,
		"blurb": "A box on big tyres with round eyes and a spare on its back. Slow to turn and tall in the wind, and it doesn't care what's under it.",
		"colours": ["#2d6b78", "#d9a21b", "#e8e6df", "#3b4a3a", "#1a1a1c"],
		"sound": "jaunt",
		"shape": {
			"length": 4.41, "width": 1.93, "height": 1.85, "wheel_radius": 0.41, "wheel_width": 0.3,
			"track_half": 0.84, "front_axle": -1.27, "rear_axle": 1.23,
			"stations": [
				[-2.205, 0.9, 0.55, 1.02], [-2.17, 0.95, 0.5, 1.12], [-1.95, 0.96, 0.5, 1.14],
				[-1.2, 0.965, 0.5, 1.15], [-0.6, 0.965, 0.5, 1.16], [0.8, 0.965, 0.5, 1.16], [1.5, 0.965, 0.51, 1.16],
				[1.95, 0.96, 0.52, 1.16], [2.06, 0.95, 0.54, 1.15], [2.1, 0.92, 0.58, 1.12],
			],
			"cabin": {"belt": 1.15, "roof": 1.85, "wb": 0.92, "wr": 0.86, "za": -0.72, "zb": -0.48, "zc": 1.92, "zd": 2.02, "doors": 2, "c_pillar": 0.3},
			"seat": [-0.42, 0.88, -0.05], "lights_y": 0.92, "tail_y": 1.0, "spare": true, "flares": true,
			"wheel_style": "steel6", "caliper": "#1c1c1c", "bumper": "black", "lamps": "round", "tails": "tall",
			"handles": "black", "exhaust": "single", "antenna": "mast", "drive": "awd", "plate": "BKO 021",
			"interior": {"seat": "#1d1d20", "insert": "#2c2d31", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"},
			"wheel_size": 0.19, "wheel_rise": 0.37, "column_degrees": 26.0,
		},
		"drive": {
			"body": {"mass": 2100.0, "weight_front": 0.55, "cg_height": 0.82, "drag": 0.78, "rolling": 24.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 5800.0, "torque": [[1000.0, 380.0], [2500.0, 540.0], [3500.0, 540.0], [4800.0, 470.0], [5800.0, 400.0]]},
			"gearbox": {"ratios": [4.7, 2.99, 2.15, 1.8, 1.52, 1.28, 1.0, 0.85, 0.69, 0.64], "final": 3.73, "reverse": 4.9, "shift_time": 0.2, "efficiency": 0.84},
			"drivetrain": "awd",
			"tyres": {"grip": 0.9, "rear_grip": 1.06, "stiffness": 100000.0, "rear_stiffness": 1.28, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.3, "damping": 0.3, "travel": 0.2, "anti_roll": 0.28},
			"brakes": {"force": 15500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.4, "speed": 2.5, "return": 4.8},
		},
	},
	"cavalcade": {
		# Our 1995-2005 Chevrolet Cavalier coupe: the cheap first car, aftermarket wing and all.
		"brand": "Chevalet",
		"model": "Cavalcade",
		"kind": "Two-door coupe, front-wheel drive",
		"price": 19000,
		"blurb": "The first car of half the kids in the province: cheap, light and a little tinny, with a wing on the trunk that does nothing at all.",
		"colours": ["#b3261e", "#2a4466", "#e8e6df", "#1a1a1c", "#4e6a2e"],
		"sound": "civique",
		"shape": {
			"length": 4.6, "width": 1.73, "height": 1.34, "wheel_radius": 0.3, "wheel_width": 0.19,
			"track_half": 0.75, "front_axle": -1.33, "rear_axle": 1.31,
			"stations": [
				[-2.3, 0.787, 0.3, 0.52], [-2.25, 0.83, 0.27, 0.62], [-2.0, 0.852, 0.27, 0.697],
				[-1.426, 0.865, 0.28, 0.785], [-0.69, 0.865, 0.28, 0.84], [0.874, 0.865, 0.28, 0.86],
				[1.495, 0.861, 0.29, 0.88], [2.05, 0.839, 0.3, 0.87], [2.25, 0.804, 0.31, 0.78],
				[2.3, 0.778, 0.33, 0.68],
			],
			"cabin": {"belt": 0.86, "roof": 1.34, "wb": 0.82, "wr": 0.64, "za": -0.62, "zb": 0.12, "zc": 0.88, "zd": 1.58, "doors": 2, "c_pillar": 0.2},
			"seat": [-0.38, 0.45, 0.28], "lights_y": 0.53, "tail_y": 0.69, "grille": "slot", "spoiler": true,
			"wheel_style": "hubcap", "caliper": "#3a3a3c", "bumper": "body", "lamps": "square", "tails": "bar",
			"handles": "black", "exhaust": "single", "antenna": "fender", "drive": "fwd", "plate": "CAV 095",
			"interior": {"seat": "#3c3d41", "insert": "#5c5d62", "dash": "#202124", "lower": "#3a3b3f", "carpet": "#232326", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 1220.0, "weight_front": 0.62, "cg_height": 0.5, "drag": 0.42, "rolling": 14.0, "downforce": 0.0},
			"engine": {"idle_rpm": 800.0, "redline_rpm": 5800.0, "torque": [[1000.0, 140.0], [2500.0, 175.0], [3600.0, 183.0], [4800.0, 168.0], [5800.0, 140.0]]},
			"gearbox": {"ratios": [3.58, 2.02, 1.35, 0.98, 0.69], "final": 3.94, "reverse": 3.3, "shift_time": 0.28, "efficiency": 0.87},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.95, "rear_grip": 1.12, "stiffness": 78000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.34, "travel": 0.13, "anti_roll": 0.4},
			"brakes": {"force": 10000.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.5},
		},
	},
	"camarillo": {
		# Our 1982-92 Chevrolet Camaro IROC-Z: an 80s wedge with T-tops and a glass hatch.
		"brand": "Chevalet",
		"model": "Camarillo IROQ",
		"kind": "Two-door hatchback coupe, rear-wheel drive",
		"price": 34000,
		"blurb": "A long, low 80s wedge with T-tops, a glass hatch and a small-block V8. Heavier than the Pony GT and happier cruising, but it'll still light up the rears.",
		"colours": ["#1a1a1c", "#b3261e", "#e8e6df", "#2a4466", "#c8a23a"],
		"sound": "pony_gt",
		"pops": 0.6,
		"shape": {
			"length": 4.77, "width": 1.85, "height": 1.27, "wheel_radius": 0.32, "wheel_width": 0.25,
			"track_half": 0.79, "front_axle": -1.42, "rear_axle": 1.32,
			"stations": [
				[-2.385, 0.837, 0.27, 0.5], [-2.335, 0.883, 0.24, 0.6], [-2.085, 0.906, 0.24, 0.67],
				[-1.479, 0.92, 0.25, 0.75], [-0.715, 0.92, 0.25, 0.8], [0.906, 0.92, 0.25, 0.83],
				[1.55, 0.915, 0.26, 0.86], [2.135, 0.892, 0.27, 0.85], [2.335, 0.856, 0.28, 0.84],
				[2.385, 0.828, 0.3, 0.74],
			],
			"cabin": {"belt": 0.8, "roof": 1.27, "wb": 0.84, "wr": 0.64, "za": -0.42, "zb": 0.38, "zc": 0.95, "zd": 1.95, "doors": 2, "c_pillar": 0.16},
			"seat": [-0.4, 0.38, 0.45], "lights_y": 0.5, "tail_y": 0.7, "grille": "slot", "t_tops": true,
			"spoiler": true, "side_stripe": [0.4, 0.44, "#c8c9cc"], "wheel_style": "lace", "caliper": "#3a3a3c",
			"bumper": "body", "lamps": "quad", "tails": "bar", "handles": "black", "exhaust": "dual",
			"antenna": "fender", "drive": "rwd", "plate": "IRQ 350",
			"interior": {"seat": "#5a1c1c", "insert": "#7a2a28", "dash": "#3a1414", "lower": "#4e1a1a", "carpet": "#2e1010", "trim": "black"},
			"wheel_size": 0.18, "wheel_rise": 0.33,
		},
		"drive": {
			"body": {"mass": 1530.0, "weight_front": 0.56, "cg_height": 0.46, "drag": 0.4, "rolling": 15.0, "downforce": 0.0},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 5600.0, "torque": [[1000.0, 330.0], [2400.0, 440.0], [3200.0, 455.0], [4400.0, 410.0], [5600.0, 330.0]]},
			"gearbox": {"ratios": [2.95, 1.94, 1.34, 1.0, 0.73], "final": 3.42, "reverse": 2.9, "shift_time": 0.25, "efficiency": 0.86},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.98, "rear_grip": 1.04, "stiffness": 88000.0, "rear_stiffness": 1.22, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.7, "damping": 0.36, "travel": 0.12, "anti_roll": 0.5},
			"brakes": {"force": 12500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.42},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.2, "speed": 2.9, "return": 5.3},
		},
	},
	"yukoner": {
		# Our GMC Yukon / Chevrolet Tahoe: a huge three-row SUV with a big chrome grille.
		"brand": "General Motorworks",
		"model": "Yukoner",
		"kind": "Full-size SUV, four-wheel drive",
		"price": 68000,
		"blurb": "The biggest thing in the driveway: three rows, a V8 and a grille you could see from space. Planted on the highway; in a hurry, it leans like a ship.",
		"colours": ["#1a1a1c", "#e8e8e6", "#5a5d61", "#24364f", "#4a1a1c"],
		"sound": "halfton",
		"shape": {
			"length": 5.35, "width": 2.06, "height": 1.94, "wheel_radius": 0.41, "wheel_width": 0.28,
			"track_half": 0.89, "front_axle": -1.76, "rear_axle": 1.4,
			"stations": [
				[-2.675, 0.95, 0.52, 1.04], [-2.62, 1.0, 0.46, 1.2], [-2.3, 1.02, 0.45, 1.27],
				[-1.4, 1.03, 0.46, 1.31], [-0.8, 1.03, 0.46, 1.33], [1.0, 1.03, 0.46, 1.34], [1.9, 1.03, 0.47, 1.34],
				[2.45, 1.02, 0.49, 1.33], [2.6, 1.0, 0.52, 1.3], [2.675, 0.97, 0.56, 1.24],
			],
			"cabin": {"belt": 1.32, "roof": 1.94, "wb": 0.98, "wr": 0.88, "za": -0.85, "zb": -0.3, "zc": 2.45, "zd": 2.6, "doors": 4, "c_pillar": 0.4},
			"seat": [-0.44, 0.98, -0.15], "lights_y": 1.04, "tail_y": 1.12, "grille": "big", "roof_rails": true,
			"privacy_glass": true, "wheel_style": "alloy10", "caliper": "#3a3b3e", "chrome_trim": true,
			"bumper": "body", "lamps": "slim", "tails": "tall", "handles": "chrome", "exhaust": "dual",
			"antenna": "fin", "drive": "awd", "plate": "YKN 530",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"wheel_size": 0.2, "wheel_rise": 0.37, "column_degrees": 26.0,
		},
		"drive": {
			"body": {"mass": 2600.0, "weight_front": 0.53, "cg_height": 0.82, "drag": 0.8, "rolling": 25.0, "downforce": 0.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 5800.0, "torque": [[1000.0, 400.0], [2500.0, 490.0], [4100.0, 519.0], [5000.0, 480.0], [5800.0, 420.0]]},
			"gearbox": {"ratios": [4.56, 2.97, 2.08, 1.69, 1.27, 1.0, 0.85, 0.69, 0.64, 0.6], "final": 3.23, "reverse": 4.0, "shift_time": 0.2, "efficiency": 0.85},
			"drivetrain": "awd",
			"tyres": {"grip": 0.93, "rear_grip": 1.08, "stiffness": 120000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.3, "damping": 0.34, "travel": 0.18, "anti_roll": 0.38},
			"brakes": {"force": 18500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 33.0, "high_speed_degrees": 4.4, "speed": 2.5, "return": 4.8},
		},
	},
	"roadmeister": {
		# Our 1991-96 Buick Roadmaster Estate: a land-yacht wagon with fake wood down the sides.
		"brand": "General Motorworks",
		"model": "Roadmeister Estate",
		"kind": "Full-size station wagon, rear-wheel drive",
		"price": 29000,
		"blurb": "Five and a half metres of wagon, fake wood down both sides and a Corvette's V8 under the hood. The family's whole summer fits in the back.",
		"colours": ["#2a3550", "#5a1e22", "#e6e2d6", "#3b4a3a", "#8c8f93"],
		"sound": "halfton",
		"shape": {
			"length": 5.5, "width": 2.0, "height": 1.53, "wheel_radius": 0.34, "wheel_width": 0.23,
			"track_half": 0.84, "front_axle": -1.6, "rear_axle": 1.4,
			"stations": [
				[-2.75, 0.91, 0.33, 0.66], [-2.7, 0.96, 0.3, 0.76], [-2.45, 0.985, 0.3, 0.837],
				[-1.705, 1.0, 0.31, 0.925], [-0.825, 1.0, 0.31, 0.98], [1.045, 1.0, 0.31, 0.99],
				[1.788, 0.995, 0.32, 1.0], [2.5, 0.97, 0.33, 0.99], [2.7, 0.93, 0.34, 0.96], [2.75, 0.9, 0.36, 0.86],
			],
			"cabin": {"belt": 0.99, "roof": 1.53, "wb": 0.92, "wr": 0.76, "za": -0.7, "zb": 0.05, "zc": 2.52, "zd": 2.66, "doors": 4, "c_pillar": 0.34},
			"seat": [-0.42, 0.56, 0.12], "lights_y": 0.67, "tail_y": 0.82, "woodgrain": true, "roof_rails": true,
			"wheel_style": "lace", "caliper": "#3a3b3e", "chrome_trim": true, "bumper": "chrome", "lamps": "square",
			"tails": "tall", "handles": "chrome", "exhaust": "single", "antenna": "fender", "drive": "rwd",
			"plate": "EST 094",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"column_degrees": 26.0,
		},
		"drive": {
			"body": {"mass": 2050.0, "weight_front": 0.54, "cg_height": 0.58, "drag": 0.55, "rolling": 18.0, "downforce": 0.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 5500.0, "torque": [[1000.0, 340.0], [2400.0, 430.0], [3200.0, 450.0], [4400.0, 400.0], [5500.0, 320.0]]},
			"gearbox": {"ratios": [3.06, 1.63, 1.0, 0.7], "final": 2.93, "reverse": 2.3, "shift_time": 0.32, "efficiency": 0.85},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.94, "rear_grip": 1.04, "stiffness": 88000.0, "rear_stiffness": 1.24, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.05, "damping": 0.27, "travel": 0.17, "anti_roll": 0.3},
			"brakes": {"force": 14500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.42},
			"steering": {"max_degrees": 36.0, "high_speed_degrees": 5.0, "speed": 2.6, "return": 5.0},
		},
	},
	"sylph": {
		# Our 1989-94 Nissan 240SX (S13): a light rear-drive coupe with pop-up lamps. Easy to drift.
		"brand": "Nissun",
		"model": "Sylph 240",
		"kind": "Two-door coupe, rear-wheel drive",
		"price": 26000,
		"blurb": "Light, balanced and rear-wheel drive, with pop-up lamps and a torquey four. Not fast, but it'll go sideways on command and stay there.",
		"colours": ["#e8e6df", "#b3261e", "#1a1a1c", "#3d4a5c", "#7d8186"],
		"sound": "civique",
		"pops": 0.4,
		"shape": {
			"length": 4.52, "width": 1.69, "height": 1.29, "wheel_radius": 0.3, "wheel_width": 0.21,
			"track_half": 0.74, "front_axle": -1.27, "rear_axle": 1.2,
			"stations": [
				[-2.26, 0.769, 0.28, 0.48], [-2.21, 0.811, 0.25, 0.58], [-1.96, 0.832, 0.25, 0.657],
				[-1.401, 0.845, 0.26, 0.745], [-0.678, 0.845, 0.26, 0.8], [0.859, 0.845, 0.26, 0.83],
				[1.469, 0.841, 0.27, 0.86], [2.01, 0.82, 0.28, 0.85], [2.21, 0.786, 0.29, 0.82],
				[2.26, 0.76, 0.31, 0.72],
			],
			"cabin": {"belt": 0.84, "roof": 1.29, "wb": 0.8, "wr": 0.62, "za": -0.55, "zb": 0.22, "zc": 0.88, "zd": 1.62, "doors": 2, "c_pillar": 0.18},
			"seat": [-0.38, 0.4, 0.32], "lights_y": 0.55, "tail_y": 0.7, "grille": "slot", "spoiler": true,
			"wheel_style": "black5", "caliper": "#3a3a3c", "bumper": "body", "lamps": "popup", "tails": "bar",
			"handles": "black", "exhaust": "single", "antenna": "fender", "drive": "rwd", "plate": "S13 240",
			"interior": {"seat": "#2e3a55", "insert": "#45557a", "dash": "#232b3e", "lower": "#2e3a52", "carpet": "#1e2536", "trim": "metal"},
			"wheel_size": 0.18, "wheel_rise": 0.34,
		},
		"drive": {
			"body": {"mass": 1250.0, "weight_front": 0.54, "cg_height": 0.46, "drag": 0.4, "rolling": 14.0, "downforce": 0.0},
			"engine": {"idle_rpm": 800.0, "redline_rpm": 6500.0, "torque": [[1000.0, 160.0], [2500.0, 200.0], [4400.0, 210.0], [5600.0, 195.0], [6500.0, 165.0]]},
			"gearbox": {"ratios": [3.32, 1.9, 1.31, 1.0, 0.76], "final": 4.08, "reverse": 3.38, "shift_time": 0.2, "efficiency": 0.87},
			"drivetrain": "rwd",
			"tyres": {"grip": 1.0, "rear_grip": 0.98, "stiffness": 86000.0, "rear_stiffness": 1.15, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.8, "damping": 0.4, "travel": 0.12, "anti_roll": 0.6},
			"brakes": {"force": 11000.0, "front_bias": 0.64, "handbrake_rear_grip": 0.36},
			"steering": {"max_degrees": 40.0, "high_speed_degrees": 5.5, "speed": 3.4, "return": 5.6},
		},
	},
	"rouge": {
		# Our Nissan Rogue (2021 on): the everyday compact crossover.
		"brand": "Nissun",
		"model": "Rouge",
		"kind": "Compact crossover, all-wheel drive",
		"price": 33000,
		"blurb": "The most ordinary car on the road, and proud of it: all-wheel drive, a smooth automatic, split headlamps and room for the dog.",
		"colours": ["#7a1d22", "#c4c6c9", "#1c1d20", "#e9e7e1", "#2f4a5e"],
		"sound": "civique",
		"shape": {
			"length": 4.65, "width": 1.84, "height": 1.7, "wheel_radius": 0.36, "wheel_width": 0.23,
			"track_half": 0.8, "front_axle": -1.35, "rear_axle": 1.36,
			"stations": [
				[-2.325, 0.837, 0.41, 0.88], [-2.275, 0.883, 0.38, 0.98], [-2.025, 0.906, 0.38, 1.029],
				[-1.442, 0.92, 0.39, 1.085], [-0.698, 0.92, 0.39, 1.12], [0.884, 0.92, 0.39, 1.13],
				[1.511, 0.915, 0.4, 1.14], [2.075, 0.892, 0.41, 1.13], [2.275, 0.856, 0.42, 1.08],
				[2.325, 0.828, 0.44, 0.98],
			],
			"cabin": {"belt": 1.12, "roof": 1.7, "wb": 0.85, "wr": 0.69, "za": -1.0, "zb": -0.15, "zc": 1.8, "zd": 2.22, "doors": 4, "c_pillar": 0.36},
			"seat": [-0.39, 0.72, 0.08], "lights_y": 0.88, "tail_y": 0.98, "grille": "big", "roof_rails": true,
			"privacy_glass": true, "cladding": true, "flares": true, "wheel_style": "alloy10", "caliper": "#5a5b5e",
			"bumper": "body", "lamps": "slim", "tails": "wrap", "handles": "body", "exhaust": "single",
			"antenna": "fin", "drive": "awd", "plate": "RGE 221",
			"interior": {"seat": "#1d1d20", "insert": "#2c2d31", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"},
			"wheel_size": 0.19, "wheel_rise": 0.36,
		},
		"drive": {
			"body": {"mass": 1640.0, "weight_front": 0.6, "cg_height": 0.62, "drag": 0.5, "rolling": 17.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 6400.0, "torque": [[1000.0, 180.0], [2500.0, 230.0], [4000.0, 245.0], [5400.0, 225.0], [6400.0, 190.0]]},
			"gearbox": {"ratios": [3.6, 2.2, 1.55, 1.15, 0.9, 0.72], "final": 4.0, "reverse": 3.1, "shift_time": 0.18, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 0.96, "rear_grip": 1.1, "stiffness": 92000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.38, "travel": 0.15, "anti_roll": 0.44},
			"brakes": {"force": 13500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
	"filly": {
		# Our 1984-87 Hyundai Pony: the tiny boxy hatch that sold by the hundred thousand in Canada.
		"brand": "Hyunsung",
		"model": "Filly",
		"kind": "Five-door hatchback, rear-wheel drive",
		"price": 9000,
		"blurb": "A tiny, boxy 80s hatch that cost less than a good used truck. Light as a bicycle and about as powerful; it rusts if you look at it.",
		"colours": ["#c4b48a", "#7a1d22", "#e6e2d6", "#3d5a7a", "#5c6b4a"],
		"sound": "civique",
		"shape": {
			"length": 4.03, "width": 1.56, "height": 1.36, "wheel_radius": 0.28, "wheel_width": 0.16,
			"track_half": 0.67, "front_axle": -1.2, "rear_axle": 1.14,
			"stations": [
				[-2.015, 0.72, 0.3, 0.6], [-1.97, 0.76, 0.27, 0.7], [-1.75, 0.775, 0.27, 0.78],
				[-1.2, 0.78, 0.28, 0.82], [-0.6, 0.78, 0.28, 0.86], [0.8, 0.78, 0.28, 0.87], [1.4, 0.78, 0.29, 0.87],
				[1.8, 0.775, 0.3, 0.86], [1.95, 0.76, 0.32, 0.82], [2.015, 0.74, 0.35, 0.74],
			],
			"cabin": {"belt": 0.86, "roof": 1.36, "wb": 0.74, "wr": 0.64, "za": -0.62, "zb": 0.06, "zc": 1.6, "zd": 1.92, "doors": 4, "c_pillar": 0.26},
			"seat": [-0.34, 0.5, 0.0], "lights_y": 0.6, "tail_y": 0.7, "wheel_style": "hubcap", "caliper": "#3a3a3c",
			"chrome_trim": true, "bumper": "black", "lamps": "square", "tails": "bar", "handles": "chrome",
			"exhaust": "single", "antenna": "fender", "drive": "rwd", "plate": "PNY 085",
			"interior": {"seat": "#8a7556", "insert": "#a89070", "dash": "#4a3f31", "lower": "#7a684e", "carpet": "#463c30", "trim": "wood"},
			"wheel_size": 0.19, "column_degrees": 28.0,
		},
		"drive": {
			"body": {"mass": 900.0, "weight_front": 0.53, "cg_height": 0.5, "drag": 0.45, "rolling": 12.0, "downforce": 0.0},
			"engine": {"idle_rpm": 850.0, "redline_rpm": 5800.0, "torque": [[1000.0, 80.0], [2400.0, 100.0], [3500.0, 106.0], [4800.0, 96.0], [5800.0, 80.0]]},
			"gearbox": {"ratios": [3.79, 2.17, 1.41, 1.0], "final": 3.91, "reverse": 3.7, "shift_time": 0.3, "efficiency": 0.87},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.9, "rear_grip": 1.06, "stiffness": 62000.0, "rear_stiffness": 1.25, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.4, "damping": 0.3, "travel": 0.13, "anti_roll": 0.3},
			"brakes": {"force": 8000.0, "front_bias": 0.64, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 36.0, "high_speed_degrees": 5.2, "speed": 3.0, "return": 5.5},
		},
	},
	"ionix": {
		# Our Hyundai Ioniq 5: a retro-futuristic electric hatch with pixel lamps.
		"brand": "Hyunsung",
		"model": "Ionix 5",
		"kind": "Electric hatchback, all-wheel drive",
		"price": 55000,
		"blurb": "An 80s hatchback redrawn for the future, with pixel lamps and two electric motors. Silent, heavy and quicker off the line than anything on the lot.",
		"colours": ["#8a8d84", "#d8d6cf", "#22303a", "#4a6a7a", "#c9b07a"],
		"sound": "",
		"shape": {
			"length": 4.64, "width": 1.89, "height": 1.6, "wheel_radius": 0.37, "wheel_width": 0.25,
			"track_half": 0.82, "front_axle": -1.5, "rear_axle": 1.5,
			"stations": [
				[-2.32, 0.86, 0.4, 0.82], [-2.27, 0.91, 0.36, 0.92], [-2.05, 0.94, 0.35, 0.98],
				[-1.4, 0.945, 0.35, 1.02], [-0.8, 0.945, 0.35, 1.04], [0.9, 0.945, 0.35, 1.05],
				[1.6, 0.945, 0.36, 1.05], [2.05, 0.94, 0.38, 1.04], [2.22, 0.92, 0.4, 1.02], [2.32, 0.89, 0.44, 0.98],
			],
			"cabin": {"belt": 1.03, "roof": 1.6, "wb": 0.87, "wr": 0.72, "za": -1.0, "zb": -0.2, "zc": 1.9, "zd": 2.25, "doors": 4, "c_pillar": 0.34},
			"seat": [-0.4, 0.66, 0.05], "lights_y": 0.82, "tail_y": 0.92, "grille": "none", "wheel_style": "aero",
			"caliper": "#3a3b3e", "bumper": "body", "lamps": "pixel", "tails": "pixel", "handles": "body",
			"exhaust": "none", "antenna": "fin", "drive": "awd", "plate": "EV 0005",
			"interior": {"seat": "#cfcbc2", "insert": "#a8a49b", "dash": "#3a3a3c", "lower": "#bcb8ae", "carpet": "#2e2e30", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 2100.0, "weight_front": 0.5, "cg_height": 0.5, "drag": 0.42, "rolling": 13.0, "downforce": 0.0},
			"engine": {"idle_rpm": 1.0, "redline_rpm": 15500.0, "torque": [[0.0, 600.0], [4500.0, 600.0], [8000.0, 380.0], [12000.0, 245.0], [15500.0, 170.0]], "launch_rpm": 1.0},
			"gearbox": {"ratios": [1.0], "final": 10.65, "reverse": 10.65, "shift_time": 0.0, "efficiency": 0.92},
			"drivetrain": "awd",
			"tyres": {"grip": 0.98, "rear_grip": 1.08, "stiffness": 98000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.4, "travel": 0.14, "anti_roll": 0.5},
			"brakes": {"force": 16500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
	"sole": {
		# Our Kia Soul: a boxy, upright hatch.
		"brand": "Kyo",
		"model": "Sole",
		"kind": "Boxy hatchback, front-wheel drive",
		"price": 23000,
		"blurb": "A toaster on wheels, in the best way: tall seats, square sides and more room inside than it looks. Front-wheel drive and nothing to prove.",
		"colours": ["#d9a21b", "#e9e7e1", "#1c1d20", "#2a7a6e", "#7a1d22"],
		"sound": "civique",
		"shape": {
			"length": 4.14, "width": 1.8, "height": 1.61, "wheel_radius": 0.33, "wheel_width": 0.21,
			"track_half": 0.79, "front_axle": -1.3, "rear_axle": 1.3,
			"stations": [
				[-2.07, 0.83, 0.36, 0.78], [-2.02, 0.87, 0.32, 0.88], [-1.8, 0.89, 0.32, 0.94],
				[-1.3, 0.9, 0.33, 0.98], [-0.8, 0.9, 0.33, 1.0], [0.8, 0.9, 0.33, 1.02], [1.4, 0.9, 0.34, 1.02],
				[1.85, 0.89, 0.36, 1.01], [2.0, 0.87, 0.38, 0.98], [2.07, 0.85, 0.42, 0.94],
			],
			"cabin": {"belt": 1.0, "roof": 1.61, "wb": 0.84, "wr": 0.76, "za": -0.95, "zb": -0.32, "zc": 1.72, "zd": 1.95, "doors": 4, "c_pillar": 0.3},
			"seat": [-0.38, 0.66, -0.05], "lights_y": 0.78, "tail_y": 0.9, "grille": "slot", "privacy_glass": true,
			"wheel_style": "alloy10", "caliper": "#5a5b5e", "bumper": "body", "lamps": "projector", "tails": "tall",
			"handles": "body", "exhaust": "single", "antenna": "fin", "drive": "fwd", "plate": "SOL 315",
			"interior": {"seat": "#1d1d20", "insert": "#2c2d31", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"},
			"wheel_size": 0.19, "wheel_rise": 0.35,
		},
		"drive": {
			"body": {"mass": 1300.0, "weight_front": 0.61, "cg_height": 0.58, "drag": 0.5, "rolling": 15.0, "downforce": 0.0},
			"engine": {"idle_rpm": 750.0, "redline_rpm": 6500.0, "torque": [[1000.0, 140.0], [2500.0, 175.0], [4700.0, 190.0], [5800.0, 178.0], [6500.0, 155.0]]},
			"gearbox": {"ratios": [4.65, 2.83, 1.84, 1.39, 1.0, 0.77], "final": 3.51, "reverse": 3.4, "shift_time": 0.25, "efficiency": 0.87},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.96, "rear_grip": 1.12, "stiffness": 80000.0, "rear_stiffness": 1.3, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.38, "travel": 0.14, "anti_roll": 0.42},
			"brakes": {"force": 11000.0, "front_bias": 0.66, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.5},
		},
	},
	"gadfly": {
		# Our Kia Stinger GT: a long fastback sport sedan, the sleeper.
		"brand": "Kyo",
		"model": "Gadfly GT",
		"kind": "Fastback sport sedan, all-wheel drive",
		"price": 52000,
		"blurb": "A long, low fastback from the brand nobody expects it from. Twin turbos, all-wheel drive with a rear bias, and a back end that will play if you ask.",
		"colours": ["#9a1e1e", "#1c1d20", "#c4c6c9", "#2a3f6a", "#e9e7e1"],
		"sound": "jaunt",
		"pops": 0.6,
		"shape": {
			"length": 4.83, "width": 1.87, "height": 1.4, "wheel_radius": 0.34, "wheel_width": 0.25,
			"track_half": 0.81, "front_axle": -1.47, "rear_axle": 1.43,
			"stations": [
				[-2.415, 0.851, 0.3, 0.56], [-2.365, 0.898, 0.27, 0.66], [-2.115, 0.921, 0.27, 0.744],
				[-1.497, 0.935, 0.28, 0.84], [-0.725, 0.935, 0.28, 0.9], [0.918, 0.935, 0.28, 0.91],
				[1.57, 0.93, 0.29, 0.92], [2.165, 0.907, 0.3, 0.91], [2.365, 0.87, 0.31, 0.84],
				[2.415, 0.842, 0.33, 0.74],
			],
			"cabin": {"belt": 0.91, "roof": 1.4, "wb": 0.84, "wr": 0.64, "za": -0.78, "zb": 0.0, "zc": 0.88, "zd": 2.05, "doors": 4, "c_pillar": 0.22},
			"seat": [-0.4, 0.48, 0.22], "lights_y": 0.57, "tail_y": 0.76, "wheel_style": "black5",
			"caliper": "#c22a1e", "bumper": "body", "lamps": "slim", "tails": "wrap", "handles": "body",
			"exhaust": "dual", "antenna": "fin", "drive": "awd", "plate": "GT 3300",
			"interior": {"seat": "#6a1e1e", "insert": "#1d1d20", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "metal"},
		},
		"drive": {
			"body": {"mass": 1830.0, "weight_front": 0.54, "cg_height": 0.5, "drag": 0.4, "rolling": 15.0, "downforce": 0.05},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 6500.0, "torque": [[1000.0, 330.0], [1800.0, 510.0], [4500.0, 510.0], [5800.0, 450.0], [6500.0, 390.0]]},
			"gearbox": {"ratios": [4.8, 2.9, 1.86, 1.38, 1.0, 0.8, 0.65, 0.53], "final": 3.73, "reverse": 3.4, "shift_time": 0.15, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 1.04, "rear_grip": 1.03, "stiffness": 100000.0, "rear_stiffness": 1.22, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.75, "damping": 0.44, "travel": 0.12, "anti_roll": 0.55},
			"brakes": {"force": 16500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.4},
			"steering": {"max_degrees": 35.0, "high_speed_degrees": 5.0, "speed": 3.0, "return": 5.4},
		},
	},
	"imprezzo": {
		# Our 2004-07 Subaru WRX STI: rally blue, gold wheels, a hood scoop and a big wing.
		"brand": "Subtaru",
		"model": "Imprezzo WRZ",
		"kind": "Four-door sedan, all-wheel drive",
		"price": 42000,
		"blurb": "A plain little sedan with a turbo flat-four, all-wheel drive and a wing you could serve dinner on. On a gravel road nothing on the Island can touch it.",
		"colours": ["#1f3f9e", "#e9e7e1", "#9fa3a8", "#1a1a1c", "#6a1e22"],
		"sound": "civique",
		"pops": 0.8,
		"shape": {
			"length": 4.47, "width": 1.74, "height": 1.42, "wheel_radius": 0.32, "wheel_width": 0.23,
			"track_half": 0.76, "front_axle": -1.3, "rear_axle": 1.32,
			"stations": [
				[-2.235, 0.792, 0.3, 0.54], [-2.185, 0.835, 0.27, 0.64], [-1.935, 0.857, 0.27, 0.724],
				[-1.386, 0.87, 0.28, 0.82], [-0.67, 0.87, 0.28, 0.88], [0.849, 0.87, 0.28, 0.9],
				[1.453, 0.866, 0.29, 0.92], [1.985, 0.844, 0.3, 0.91], [2.185, 0.809, 0.31, 0.78],
				[2.235, 0.783, 0.33, 0.68],
			],
			"cabin": {"belt": 0.9, "roof": 1.42, "wb": 0.82, "wr": 0.64, "za": -0.76, "zb": 0.0, "zc": 0.86, "zd": 1.46, "doors": 4, "c_pillar": 0.22},
			"seat": [-0.38, 0.5, 0.18], "lights_y": 0.55, "tail_y": 0.69, "hood_scoop": true, "spoiler": "wing",
			"wheel_style": "gold10", "caliper": "#c9a227", "bumper": "body", "lamps": "projector", "tails": "wrap",
			"handles": "body", "exhaust": "dual", "antenna": "fin", "drive": "awd", "plate": "WRZ 555",
			"interior": {"seat": "#1d1d20", "insert": "#2a3a6a", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "metal"},
		},
		"drive": {
			"body": {"mass": 1500.0, "weight_front": 0.58, "cg_height": 0.5, "drag": 0.42, "rolling": 15.0, "downforce": 0.06},
			"engine": {"idle_rpm": 850.0, "redline_rpm": 7000.0, "torque": [[1000.0, 180.0], [2800.0, 330.0], [4000.0, 400.0], [5600.0, 360.0], [7000.0, 290.0]]},
			"gearbox": {"ratios": [3.64, 2.24, 1.52, 1.13, 0.92, 0.78], "final": 3.9, "reverse": 3.55, "shift_time": 0.18, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 1.06, "rear_grip": 1.04, "stiffness": 98000.0, "rear_stiffness": 1.25, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.75, "damping": 0.42, "travel": 0.14, "anti_roll": 0.55},
			"brakes": {"force": 14500.0, "front_bias": 0.62, "handbrake_rear_grip": 0.45},
			"steering": {"max_degrees": 36.0, "high_speed_degrees": 5.2, "speed": 3.2, "return": 5.5},
		},
	},
	"hinterland": {
		# Our Subaru Outback: the lifted all-wheel-drive wagon everyone on the Island actually drives.
		"brand": "Subtaru",
		"model": "Hinterland",
		"kind": "Lifted station wagon, all-wheel drive",
		"price": 38000,
		"blurb": "A wagon on stilts with plastic armour round the bottom and all-wheel drive that never gives up. Every second driveway in the province has one.",
		"colours": ["#3b4a3a", "#8c8f93", "#e9e7e1", "#2a3550", "#6a4a2a"],
		"sound": "civique",
		"shape": {
			"length": 4.82, "width": 1.84, "height": 1.6, "wheel_radius": 0.35, "wheel_width": 0.22,
			"track_half": 0.8, "front_axle": -1.4, "rear_axle": 1.35,
			"stations": [
				[-2.41, 0.837, 0.39, 0.68], [-2.36, 0.883, 0.36, 0.78], [-2.11, 0.906, 0.36, 0.857],
				[-1.494, 0.92, 0.37, 0.945], [-0.723, 0.92, 0.37, 1.0], [0.916, 0.92, 0.37, 1.02],
				[1.567, 0.915, 0.38, 1.04], [2.16, 0.892, 0.39, 1.03], [2.36, 0.856, 0.4, 1.0],
				[2.41, 0.828, 0.42, 0.9],
			],
			"cabin": {"belt": 1.02, "roof": 1.6, "wb": 0.85, "wr": 0.7, "za": -0.95, "zb": -0.12, "zc": 2.05, "zd": 2.32, "doors": 4, "c_pillar": 0.3},
			"seat": [-0.39, 0.66, 0.1], "lights_y": 0.7, "tail_y": 0.9, "roof_rails": true, "cladding": true,
			"flares": true, "wheel_style": "alloy10", "caliper": "#5a5b5e", "chrome_trim": true, "bumper": "body",
			"lamps": "projector", "tails": "tall", "handles": "body", "exhaust": "dual", "antenna": "fin",
			"drive": "awd", "plate": "OBK 250",
			"interior": {"seat": "#3c3d41", "insert": "#5c5d62", "dash": "#202124", "lower": "#3a3b3f", "carpet": "#232326", "trim": "black"},
		},
		"drive": {
			"body": {"mass": 1650.0, "weight_front": 0.59, "cg_height": 0.6, "drag": 0.5, "rolling": 17.0, "downforce": 0.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 6200.0, "torque": [[1000.0, 180.0], [2500.0, 225.0], [4400.0, 240.0], [5400.0, 225.0], [6200.0, 195.0]]},
			"gearbox": {"ratios": [3.6, 2.2, 1.55, 1.15, 0.9, 0.72], "final": 3.9, "reverse": 3.1, "shift_time": 0.18, "efficiency": 0.86},
			"drivetrain": "awd",
			"tyres": {"grip": 1.0, "rear_grip": 1.06, "stiffness": 92000.0, "rear_stiffness": 1.25, "spin_grip": 0.42},
			"suspension": {"spring_hz": 1.5, "damping": 0.38, "travel": 0.16, "anti_roll": 0.42},
			"brakes": {"force": 13500.0, "front_bias": 0.64, "handbrake_rear_grip": 0.5},
			"steering": {"max_degrees": 34.0, "high_speed_degrees": 4.8, "speed": 2.9, "return": 5.3},
		},
	},
}

## Liveries: a fleet's paint and kit over any model. "police" adds the
## light bar, push bar, the band down the sides and the words on it (see
## CarBuilder._police and PoliceGear); "shape" entries override the model's.
const LIVERIES := {
	"cps": {
		"fleet": "Charlatown Police",
		"_comment": "Charlatown Police Services (our Charlottetown Police Services): white with a navy band, POLICE on the doors, a red and blue light bar. The real service's colours are white and blue.",
		"colour": "#f2f2f0",
		"shape": {"police": true, "band": "#1b2a4a", "band_text": "POLICE", "fleet_text": "CHARLATOWN", "unit_prefix": "CPS",
			"bumper": "black", "chrome_trim": false, "roof_rails": false, "wheel_style": "steel6", "caliper": "#1c1c1c",
			"interior": {"seat": "#1d1d20", "insert": "#2a2b2f", "dash": "#18181b", "lower": "#232326", "carpet": "#141416", "trim": "black"}},
	},
}


static func get_model(id: String) -> Dictionary:
	if TruckModels.MODELS.has(id):
		return TruckModels.MODELS[id]
	return MODELS.get(id, MODELS["civique"])


## True for any vehicle the game knows: the cars here and the working
## vehicles in TruckModels.
static func has_model(id: String) -> bool:
	return MODELS.has(id) or TruckModels.MODELS.has(id)


## The model's shape with a livery's changes on top ("" for none), and
## the unit number on its plate.
static func shape_for(id: String, livery := "", unit := 0) -> Dictionary:
	var base: Dictionary = get_model(id)["shape"]
	if livery == "" or not LIVERIES.has(livery):
		return base
	var out := base.duplicate(true)
	var over: Dictionary = LIVERIES[livery].get("shape", {})
	for k: String in over:
		out[k] = over[k]
	if over.has("unit_prefix"):
		out["plate"] = "%s %d" % [over["unit_prefix"], unit]
		out["unit"] = unit
	return out


## What a new one costs at a dealer, in dollars.
static func price(id: String) -> int:
	return int(get_model(id).get("price", 25000))


## A car's price for the HUD, e.g. "$24,500".
static func price_text(id: String) -> String:
	return dollars(price(id))


## An amount of money for the HUD, e.g. "$24,500".
static func dollars(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-$" if amount < 0 else "$") + s + out


static func full_name(id: String, livery := "") -> String:
	var m := get_model(id)
	if livery != "" and LIVERIES.has(livery):
		return "%s %s %s" % [LIVERIES[livery]["fleet"], m["brand"], m["model"]]
	return "%s %s" % [m["brand"], m["model"]]

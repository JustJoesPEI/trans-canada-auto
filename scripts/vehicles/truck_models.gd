class_name TruckModels
extends RefCounted
## The working vehicles: a tractor unit, a flatbed trailer, a rollback tow
## truck, a crane truck, a forklift and a city bus. Same layout as CarModels (CarModels.get_model finds
## these too), with what a truck needs on top:
##
##   axles     one entry per axle: z, track_half (to the middle of the tyre,
##             or of a pair of duals), radius, width, steer (1 steers, -1
##             steers the other way, as at the back of a forklift, 0 fixed),
##             driven, dual (two tyres a side), front (counts as the front of
##             the weight split; by default the steered axles are the front),
##             leg (a trailer's landing legs: they hold its nose up while it
##             isn't hitched, and fold away when it is), travel
##   boxes     the body's collision, as boxes: size, pos, tilt (degrees, about
##             x: + drops the back end), deck (a load floor, for straps),
##             part (moves with a working part: "deck", "forks", "mast")
##   hitch     where a trailer couples on (kind "fifth_wheel"); a trailer has
##             a matching "kingpin"
##   tool      the working part: "rollback" (tilt-and-slide deck and a winch),
##             "forklift" (lift and tilt the forks) or "crane" (a knuckle-boom
##             crane on stabiliser legs, CraneTool); its settings are under
##             the same name
##   camera    how far back the chase camera sits, and how high it looks
##   builder   "truck": drawn by TruckBuilder (by "look") instead of CarBuilder
##   drivable  false for a trailer (no seat)
##
## In "drive": body.payload is what it's rated to carry (kg; the springs are
## sized for half of it on top of the empty weight), brakes.abs keeps the
## wheels from locking, engine.launch_rpm is where a diesel pulls away, and
## engine.governor_kmh is where the speed limiter cuts in. A trailer has no
## engine or gearbox: it brakes when its tractor does.

const MODELS := {
	"hauler": {
		"brand": "Westerly",
		"model": "Hauler 579",
		"kind": "Tractor unit, 6x4: back under a trailer and it couples (T)",
		"blurb": "A long-nose highway tractor with a tandem drive axle and a ten-speed. Back it under a trailer's nose and the fifth wheel locks on.",
		"colours": ["#9e1b1b", "#1d3f6e", "#e9e6dc", "#20262b", "#c7a12a"],
		"shape": {
			"builder": "truck", "look": "tractor",
			"length": 7.2, "width": 2.5, "height": 3.25,
			"wheel_radius": 0.52, "wheel_width": 0.28, "track_half": 1.03,
			"front_axle": -2.7, "rear_axle": 2.3,
			"axles": [
				{"z": -2.7, "track_half": 1.03, "steer": 1.0},
				{"z": 1.65, "track_half": 0.92, "dual": true, "driven": true},
				{"z": 2.95, "track_half": 0.92, "dual": true, "driven": true},
			],
			"boxes": [
				{"size": [2.3, 1.15, 1.9], "pos": [0.0, 1.25, -2.6]}, # hood
				{"size": [2.5, 2.3, 2.1], "pos": [0.0, 2.0, -0.6]}, # cab
				{"size": [1.0, 0.36, 4.2], "pos": [0.0, 0.86, 1.6]}, # frame
				{"size": [1.6, 0.16, 1.1], "pos": [0.0, 1.145, 2.2]}, # fifth wheel plate, top 1.225
				{"size": [1.4, 0.1, 0.7], "pos": [0.0, 1.07, 2.95], "tilt": 14.0}, # its ramp
			],
			"hitch": {"kind": "fifth_wheel", "pos": [0.0, 1.225, 2.2]},
			"seat": [-0.55, 1.75, -0.55],
			"wheel_size": 0.23, "wheel_rise": 0.34, "wheel_reach": 0.42, "column_degrees": 34.0,
			"camera": {"distance": 13.0, "look_height": 2.4},
			"backup_alarm": true, "air_brakes": true, "horn": "air",
		},
		"drive": {
			"body": {"mass": 8800.0, "weight_front": 0.56, "cg_height": 1.05, "drag": 4.2, "rolling": 85.0, "downforce": 0.0, "payload": 16000.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 2100.0, "launch_rpm": 1100.0, "governor_kmh": 105.0,
				"torque": [[700.0, 1500.0], [1100.0, 2500.0], [1500.0, 2500.0], [1800.0, 2250.0], [2100.0, 1750.0]]},
			"gearbox": {"ratios": [12.8, 9.25, 6.76, 4.9, 3.58, 2.61, 1.89, 1.38, 1.0, 0.73], "final": 3.55, "reverse": 12.0, "shift_time": 0.55, "efficiency": 0.9},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.82, "rear_grip": 1.0, "stiffness": 320000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.7, "damping": 0.38, "travel": 0.12, "anti_roll": 0.7},
			"brakes": {"force": 72000.0, "front_bias": 0.32, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 42.0, "high_speed_degrees": 4.0, "speed": 1.8, "return": 3.2},
		},
	},
	"flatbed_trailer": {
		"brand": "Fundy",
		"model": "48 ft Flatbed",
		"kind": "Trailer",
		"blurb": "Forty-eight feet of steel deck on a spread tandem. Load it with the forklift, strap it down (B), and mind the swing in the corners.",
		"colours": ["#3a3d40", "#6d1f1f", "#24415e"],
		"shape": {
			"builder": "truck", "look": "flat_trailer", "drivable": false,
			"length": 14.63, "width": 2.6, "height": 1.5,
			"wheel_radius": 0.52, "wheel_width": 0.28, "track_half": 0.92,
			"front_axle": -4.8, "rear_axle": 5.4,
			"axles": [
				{"z": -4.8, "track_half": 0.95, "radius": 0.06, "width": 0.3, "leg": true},
				{"z": 4.75, "track_half": 0.92, "dual": true},
				{"z": 6.0, "track_half": 0.92, "dual": true},
			],
			"boxes": [
				{"size": [2.6, 0.26, 14.63], "pos": [0.0, 1.37, 0.0], "deck": true}, # deck: underside 1.24, top 1.5
				{"size": [0.9, 0.3, 10.0], "pos": [0.0, 1.09, 2.3]}, # main beams over the axles
			],
			"kingpin": {"kind": "fifth_wheel", "pos": [0.0, 1.24, -6.4]},
			"seat": [0.0, 1.5, 0.0],
			"friction": 0.55,
		},
		"drive": {
			"body": {"mass": 5200.0, "weight_front": 0.55, "cg_height": 1.15, "drag": 1.6, "rolling": 70.0, "downforce": 0.0, "payload": 20000.0},
			"engine": null,
			"drivetrain": "none",
			"tyres": {"grip": 0.82, "rear_grip": 1.0, "stiffness": 300000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.8, "damping": 0.4, "travel": 0.11, "anti_roll": 0.8},
			"brakes": {"force": 95000.0, "front_bias": 0.0, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 0.0, "high_speed_degrees": 0.0, "speed": 1.0, "return": 1.0},
		},
	},
	"rollback": {
		"brand": "Fjord",
		"model": "F-550 Rollback",
		"kind": "Tow truck: G/R tilt the deck, T hooks the winch, Y/H winch in and out",
		"blurb": "A medium-duty chassis with a 20-foot steel deck that tilts and slides back to the road. Hook the winch to a car, pull it up, strap it down (B), and away you go.",
		"colours": ["#e9e7e1", "#c22a1f", "#1d2b44", "#e3b21b"],
		"shape": {
			"builder": "truck", "look": "rollback",
			"length": 9.9, "width": 2.4, "height": 2.65,
			"wheel_radius": 0.42, "wheel_width": 0.24, "track_half": 1.0,
			"front_axle": -3.5, "rear_axle": 1.35,
			"axles": [
				{"z": -3.5, "track_half": 1.0, "steer": 1.0},
				{"z": 1.35, "track_half": 0.86, "dual": true, "driven": true},
			],
			"boxes": [
				{"size": [2.2, 0.85, 1.6], "pos": [0.0, 1.12, -3.75]}, # hood
				{"size": [2.35, 1.75, 1.7], "pos": [0.0, 1.62, -2.1]}, # cab
				{"size": [0.95, 0.3, 6.6], "pos": [0.0, 0.8, 0.3]}, # frame
				{"size": [2.4, 0.12, 6.1], "pos": [0.0, 1.16, 2.5], "deck": true, "part": "deck"},
				{"size": [2.4, 0.9, 0.1], "pos": [0.0, 1.67, -0.5], "part": "deck"}, # headboard
			],
			"rollback": {"pivot": [0.0, 0.95, 3.6], "slide": 3.0, "deck_rear": 5.55, "deck_bottom": 1.1, "winch": [0.0, 1.45, -0.3]},
			"tool": "rollback",
			"seat": [-0.5, 1.3, -2.0],
			"wheel_size": 0.2, "wheel_reach": 0.42, "column_degrees": 28.0,
			"camera": {"distance": 10.0, "look_height": 2.0},
			"friction": 0.6,
			"backup_alarm": true, "horn_pitch": 0.86,
		},
		"drive": {
			"body": {"mass": 6400.0, "weight_front": 0.44, "cg_height": 0.95, "drag": 2.6, "rolling": 55.0, "downforce": 0.0, "payload": 4500.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 3200.0, "launch_rpm": 1400.0, "governor_kmh": 120.0,
				"torque": [[800.0, 680.0], [1600.0, 1100.0], [2200.0, 1060.0], [2800.0, 900.0], [3200.0, 760.0]]},
			"gearbox": {"ratios": [3.1, 1.81, 1.41, 1.0, 0.71, 0.61], "final": 4.88, "reverse": 3.0, "shift_time": 0.4, "efficiency": 0.88},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.86, "rear_grip": 1.0, "stiffness": 210000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.6, "damping": 0.36, "travel": 0.12, "anti_roll": 0.6},
			"brakes": {"force": 44000.0, "front_bias": 0.58, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 40.0, "high_speed_degrees": 4.5, "speed": 2.0, "return": 3.8},
		},
	},
	"crane_truck": {
		"brand": "Fjord",
		"model": "F-750 Picker",
		"kind": "Crane truck: G puts the legs out, then the crane works off the driving controls",
		"blurb": "A short flat deck with a knuckle-boom crane behind the cab, the lumberyard's delivery truck. Put the legs down, swing the boom out, and set a pallet over the fence.",
		"colours": ["#e9e7e1", "#1d3f6e", "#2f5d3a", "#9e1b1b"],
		"shape": {
			"builder": "truck", "look": "crane_truck",
			"length": 9.2, "width": 2.45, "height": 3.9,
			"wheel_radius": 0.45, "wheel_width": 0.25, "track_half": 1.02,
			"front_axle": -3.5, "rear_axle": 1.95,
			"axles": [
				{"z": -3.5, "track_half": 1.02, "steer": 1.0},
				{"z": 1.95, "track_half": 0.88, "dual": true, "driven": true},
			],
			"boxes": [
				{"size": [2.2, 0.85, 1.6], "pos": [0.0, 1.12, -3.75]}, # hood
				{"size": [2.35, 1.75, 1.7], "pos": [0.0, 1.62, -2.1]}, # cab
				{"size": [0.95, 0.3, 7.4], "pos": [0.0, 0.83, 0.55]}, # frame
				{"size": [0.95, 1.0, 0.85], "pos": [0.0, 1.5, -0.72]}, # the crane's base
				{"size": [2.45, 0.14, 4.3], "pos": [0.0, 1.2, 2.1], "deck": true}, # deck: top 1.27, z -0.05 to 4.25
				{"size": [0.5, 0.45, 0.5], "pos": [-0.95, 0.55, -0.72], "part": "leg_l"}, # stabiliser pads
				{"size": [0.5, 0.45, 0.5], "pos": [0.95, 0.55, -0.72], "part": "leg_r"},
			],
			# The crane (CraneTool): the slewing column on the frame at "base",
			# the boom's pivot above it, the inner and outer booms, how far the
			# outer one telescopes, the legs' travel out and down, and what it
			# can lift: "moment" kg at a metre of reach, never more than
			# "max_lift" kg.
			"crane": {"base": [0.0, 1.0, -0.72], "pivot": [0.0, 1.05, 0.12], "inner": 2.0, "outer": 2.3, "extend": 2.5,
				"stow_degrees": 68.0, "legs_out": 1.2, "legs_down": 0.35, "moment": 8500.0, "max_lift": 2500.0},
			"tool": "crane",
			"seat": [-0.5, 1.3, -2.0],
			"wheel_size": 0.2, "wheel_reach": 0.42, "column_degrees": 28.0,
			"camera": {"distance": 11.0, "look_height": 2.4},
			"friction": 0.6,
			"backup_alarm": true, "horn_pitch": 0.84,
		},
		"drive": {
			"body": {"mass": 7400.0, "weight_front": 0.5, "cg_height": 1.0, "drag": 2.8, "rolling": 60.0, "downforce": 0.0, "payload": 5500.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 3000.0, "launch_rpm": 1300.0, "governor_kmh": 110.0,
				"torque": [[800.0, 750.0], [1500.0, 1200.0], [2100.0, 1150.0], [2600.0, 980.0], [3000.0, 820.0]]},
			"gearbox": {"ratios": [3.1, 1.81, 1.41, 1.0, 0.71, 0.61], "final": 5.13, "reverse": 3.0, "shift_time": 0.42, "efficiency": 0.88},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.86, "rear_grip": 1.0, "stiffness": 230000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.6, "damping": 0.38, "travel": 0.12, "anti_roll": 0.65},
			"brakes": {"force": 50000.0, "front_bias": 0.55, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 40.0, "high_speed_degrees": 4.5, "speed": 2.0, "return": 3.8},
		},
	},
	"transit_bus": {
		"brand": "Charlatown Transit",
		"model": "Lowfloor 40",
		"kind": "City bus: big, slow, and wider than you'd think",
		"blurb": "A forty-foot low-floor city bus on the town routes. It stops at every stop, takes its time pulling out, and makes a very good wall.",
		"colours": ["#e9e7e1", "#f0ede4"],
		"shape": {
			"builder": "truck", "look": "bus",
			"length": 12.2, "width": 2.55, "height": 3.1,
			"wheel_radius": 0.5, "wheel_width": 0.28, "track_half": 1.04,
			"front_axle": -3.55, "rear_axle": 2.85,
			"axles": [
				{"z": -3.55, "track_half": 1.04, "steer": 1.0},
				{"z": 2.85, "track_half": 0.9, "dual": true, "driven": true},
			],
			"boxes": [
				{"size": [2.5, 2.6, 12.0], "pos": [0.0, 1.68, 0.0]},
			],
			"seat": [-0.72, 1.3, -5.0],
			"wheel_size": 0.24, "wheel_rise": 0.3, "wheel_reach": 0.45, "column_degrees": 40.0,
			"camera": {"distance": 16.0, "look_height": 2.8},
			"backup_alarm": true, "air_brakes": true, "horn": "air", "horn_pitch": 0.9,
		},
		"drive": {
			"body": {"mass": 12500.0, "weight_front": 0.38, "cg_height": 1.15, "drag": 5.0, "rolling": 110.0, "downforce": 0.0, "payload": 6000.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 2400.0, "launch_rpm": 1100.0, "governor_kmh": 90.0,
				"torque": [[700.0, 900.0], [1100.0, 1450.0], [1500.0, 1450.0], [2000.0, 1250.0], [2400.0, 1000.0]]},
			"gearbox": {"ratios": [3.4, 1.91, 1.42, 1.0, 0.75, 0.64], "final": 5.6, "reverse": 4.0, "shift_time": 0.5, "efficiency": 0.88},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.8, "rear_grip": 1.0, "stiffness": 330000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.3, "damping": 0.4, "travel": 0.12, "anti_roll": 0.75},
			"brakes": {"force": 95000.0, "front_bias": 0.4, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 44.0, "high_speed_degrees": 4.0, "speed": 1.6, "return": 3.0},
		},
	},
	"forklift": {
		"brand": "Hoister",
		"model": "H50 Forklift",
		"kind": "Forklift: R/G raise and lower, Y/H tilt the mast",
		"blurb": "Five thousand pounds of lift on solid tyres, steering at the back. Slide the forks into a pallet, lift, tilt back, and set it down on a deck.",
		"colours": ["#e2a91a", "#d14b1b", "#2a5c3a"],
		"shape": {
			"builder": "truck", "look": "forklift",
			"length": 3.55, "width": 1.2, "height": 2.15,
			"wheel_radius": 0.33, "wheel_width": 0.22, "track_half": 0.46,
			"front_axle": -0.55, "rear_axle": 1.0,
			"axles": [
				{"z": -0.55, "track_half": 0.46, "radius": 0.33, "width": 0.22, "driven": true, "front": true},
				{"z": 1.0, "track_half": 0.4, "radius": 0.26, "width": 0.18, "steer": -1.0, "front": false},
			],
			"boxes": [
				{"size": [1.12, 0.55, 1.75], "pos": [0.0, 0.55, 0.15]}, # chassis
				{"size": [1.16, 0.75, 0.6], "pos": [0.0, 0.85, 1.05]}, # counterweight
				{"size": [1.1, 0.06, 1.35], "pos": [0.0, 2.12, 0.1]}, # overhead guard
				{"size": [0.86, 2.05, 0.14], "pos": [0.0, 1.13, -0.9], "part": "mast"},
				{"size": [1.0, 1.0, 0.06], "pos": [0.0, 0.62, -1.03], "part": "forks"}, # carriage and backrest
				{"size": [0.12, 0.045, 1.07], "pos": [-0.3, 0.06, -1.6], "part": "forks"},
				{"size": [0.12, 0.045, 1.07], "pos": [0.3, 0.06, -1.6], "part": "forks"},
			],
			"forklift": {"pivot": [0.0, 0.3, -0.85], "max_lift": 3.1, "lift_speed": 0.42, "tilt_forward": 6.0, "tilt_back": 10.0, "tilt_speed": 4.0, "capacity": 2300.0},
			"tool": "forklift",
			"seat": [0.0, 1.0, 0.3],
			"wheel_size": 0.16, "wheel_rise": 0.33, "wheel_reach": 0.4, "column_degrees": 40.0,
			"camera": {"distance": 6.0, "look_height": 1.6},
			"friction": 0.5,
			"backup_alarm": true, "horn": "buzz",
		},
		"drive": {
			"body": {"mass": 4100.0, "weight_front": 0.42, "cg_height": 0.55, "drag": 0.9, "rolling": 60.0, "downforce": 0.0, "payload": 2300.0},
			"engine": {"idle_rpm": 800.0, "redline_rpm": 2800.0, "launch_rpm": 1500.0,
				"torque": [[800.0, 150.0], [1500.0, 185.0], [2200.0, 180.0], [2800.0, 160.0]]},
			"gearbox": {"ratios": [17.5], "final": 1.0, "reverse": 17.5, "shift_time": 0.3, "efficiency": 0.85},
			"drivetrain": "fwd",
			"tyres": {"grip": 0.9, "rear_grip": 1.0, "stiffness": 70000.0, "rear_stiffness": 1.0, "spin_grip": 0.5},
			# No real suspension: solid tyres on a rigid frame, so very stiff springs.
			"suspension": {"spring_hz": 6.0, "damping": 0.55, "travel": 0.04, "anti_roll": 0.0},
			"brakes": {"force": 22000.0, "front_bias": 0.8, "handbrake_rear_grip": 0.6},
			# Full lock for manoeuvring at a walk, easing to a third of it at
			# full speed, so it carves round instead of spinning on the spot.
			"steering": {"max_degrees": 72.0, "high_speed_degrees": 26.0, "lock_kmh": 18.0, "speed": 2.4, "return": 3.0},
		},
	},
	"ambulance": {
		"_comment": "The Island Boo-Boo Bus (IBBB), the Island's paramedics. Built from Joe's photo of an Island ambulance: a high-roof van, white, a lime band and dark green stripe low down, a lime PARAMEDIC panel behind the cab, the name mirrored across the front of the roof, lime and green checks on the back doors. The names are ours. Fleet only: it turns up when someone's hurt (EmergencyServices).",
		"brand": "Mercy-Bends",
		"model": "Sprainter 3500 Ambulance",
		"kind": "Ambulance: L for the lights and siren",
		"blurb": "A high-roof van with the Island Boo-Boo Bus. A stretcher, a defibrillator, and a box of bandages in every size but the one you need.",
		"colours": ["#f1f1ee"],
		"shape": {
			"builder": "truck", "look": "ambulance",
			"length": 7.0, "width": 2.02, "height": 2.95,
			"wheel_radius": 0.37, "wheel_width": 0.22, "track_half": 0.86,
			"front_axle": -2.05, "rear_axle": 1.75,
			"axles": [
				{"z": -2.05, "track_half": 0.86, "steer": 1.0},
				{"z": 1.75, "track_half": 0.84, "driven": true},
			],
			"boxes": [
				{"size": [1.9, 0.7, 1.0], "pos": [0.0, 0.8, -2.95]}, # nose
				{"size": [2.0, 2.4, 5.85], "pos": [0.0, 1.6, 0.47]}, # body
			],
			"seat": [-0.45, 1.0, -1.65],
			"wheel_size": 0.19, "wheel_reach": 0.4, "column_degrees": 30.0,
			"camera": {"distance": 8.0, "look_height": 1.9},
			"friction": 0.6,
			"backup_alarm": true, "horn_pitch": 1.0, "siren_pitch": 1.06,
			"beacons": [
				{"pos": [-0.75, 2.9, -0.98], "size": [0.22, 0.08, 0.18], "group": 0, "colour": "#ff1a0a"},
				{"pos": [-0.50, 2.9, -0.98], "size": [0.22, 0.08, 0.18], "group": 0, "colour": "#f4f4ff"},
				{"pos": [0.50, 2.9, -0.98], "size": [0.22, 0.08, 0.18], "group": 1, "colour": "#f4f4ff"},
				{"pos": [0.75, 2.9, -0.98], "size": [0.22, 0.08, 0.18], "group": 1, "colour": "#ff1a0a"},
				{"pos": [-0.79, 2.7, 3.37], "size": [0.26, 0.1, 0.05], "group": 1, "colour": "#ff1a0a"},
				{"pos": [-1.000, 2.55, -1.3], "size": [0.03, 0.12, 0.14], "group": 0, "colour": "#ff1a0a"},
				{"pos": [-1.000, 2.55, 3.2], "size": [0.03, 0.12, 0.22], "group": 1, "colour": "#ff1a0a"},
				{"pos": [-0.30, 0.8, -3.42], "size": [0.12, 0.04, 0.02], "group": 0, "colour": "#ff1a0a"},
				{"pos": [0.79, 2.7, 3.37], "size": [0.26, 0.1, 0.05], "group": 0, "colour": "#ff1a0a"},
				{"pos": [1.000, 2.55, -1.3], "size": [0.03, 0.12, 0.14], "group": 1, "colour": "#ff1a0a"},
				{"pos": [1.000, 2.55, 3.2], "size": [0.03, 0.12, 0.22], "group": 0, "colour": "#ff1a0a"},
				{"pos": [0.30, 0.8, -3.42], "size": [0.12, 0.04, 0.02], "group": 1, "colour": "#f4f4ff"},
			],
			"glow": ["#ff2010", "#f4f4ff"],
			"words": [
				{"text": "PARAMEDIC", "pos": [1.012, 2.49, -0.15], "face": "right", "height": 0.22, "colour": "#0a4d2b"},
				{"text": "PARAMEDIC", "pos": [-1.012, 2.49, -0.15], "face": "left", "height": 0.22, "colour": "#0a4d2b"},
				{"text": "IBBB", "pos": [1.015, 1.55, 1.3], "face": "right", "height": 0.3, "colour": "#0a4d2b"},
				{"text": "IBBB", "pos": [-1.015, 1.55, 0.6], "face": "left", "height": 0.3, "colour": "#0a4d2b"},
				{"text": "ISLAND BOO-BOO BUS", "pos": [-1.015, 1.28, 0.6], "face": "left", "height": 0.09, "colour": "#0a4d2b"},
				{"text": "ISLAND BOO-BOO BUS", "pos": [1.015, 1.28, 1.3], "face": "right", "height": 0.09, "colour": "#0a4d2b"},
				{"text": "BOO-BOO BUS", "pos": [0.0, 2.54, -1.47], "normal": [0.0, 1.2, -1.64], "height": 0.17, "colour": "#0a4d2b", "mirror": true},
				{"text": "BOO-BOO BUS", "pos": [0.0, 1.11, -2.75], "face": "up", "height": 0.12, "colour": "#0a4d2b", "mirror": true},
				{"text": "IBBB", "pos": [0.0, 2.45, 3.41], "face": "back", "height": 0.2, "colour": "#0a4d2b"},
				{"text": "STAY BACK. WE'VE SEEN YOUR DRIVING.", "pos": [0.0, 1.42, 3.41], "face": "back", "height": 0.05, "colour": "#0a4d2b"},
			],
		},
		"drive": {
			"body": {"mass": 4100.0, "weight_front": 0.48, "cg_height": 0.95, "drag": 1.9, "rolling": 42.0, "downforce": 0.0, "payload": 1200.0},
			"engine": {"idle_rpm": 700.0, "redline_rpm": 4200.0, "launch_rpm": 1400.0, "governor_kmh": 140.0,
				"torque": [[800.0, 420.0], [1600.0, 620.0], [2600.0, 640.0], [3600.0, 560.0], [4200.0, 470.0]]},
			"gearbox": {"ratios": [3.1, 1.81, 1.41, 1.0, 0.71, 0.61], "final": 4.3, "reverse": 3.0, "shift_time": 0.35, "efficiency": 0.88},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.9, "rear_grip": 1.0, "stiffness": 190000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.6, "damping": 0.38, "travel": 0.13, "anti_roll": 0.65},
			"brakes": {"force": 40000.0, "front_bias": 0.6, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 40.0, "high_speed_degrees": 4.8, "speed": 2.2, "return": 4.0},
		},
	},
	"fire_engine": {
		"_comment": "The Island Wee-Woo Brigade (IWWB), the Island's fire department: a pumper with a flat-fronted crew cab, red with a white band and a gold line, chrome pump panel, roll-up doors, the hose bed and a ladder on top. Fleet only (EmergencyServices).",
		"brand": "Pierson",
		"model": "Enforcer Pumper",
		"kind": "Fire engine: L for the lights and siren",
		"blurb": "Fifteen tonnes, a 1,250-gallon-a-minute pump, 750 gallons of water, and a crew of four who'd like you to know this isn't a police job.",
		"colours": ["#b3140f"],
		"shape": {
			"builder": "truck", "look": "fire_engine",
			"length": 10.1, "width": 2.5, "height": 3.25,
			"wheel_radius": 0.5, "wheel_width": 0.3, "track_half": 1.04,
			"front_axle": -3.75, "rear_axle": 2.6,
			"axles": [
				{"z": -3.75, "track_half": 1.04, "steer": 1.0},
				{"z": 2.6, "track_half": 0.9, "dual": true, "driven": true},
			],
			"boxes": [
				{"size": [2.46, 2.45, 2.45], "pos": [0.0, 1.78, -3.6]}, # cab
				{"size": [2.46, 1.85, 6.85], "pos": [0.0, 1.475, 1.125]}, # body
				{"size": [2.5, 0.3, 0.6], "pos": [0.0, 0.5, -5.0]}, # bumper
				{"size": [2.46, 0.12, 0.44], "pos": [0.0, 0.5, 4.77]}, # tailboard
			],
			"seat": [-0.55, 1.65, -3.75],
			"wheel_size": 0.23, "wheel_rise": 0.32, "wheel_reach": 0.44, "column_degrees": 36.0,
			"camera": {"distance": 14.0, "look_height": 2.8},
			"friction": 0.6,
			"backup_alarm": true, "air_brakes": true, "horn": "air", "horn_pitch": 0.82, "siren_pitch": 0.9,
			"beacons": [
				{"pos": [-0.75, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 0, "colour": "#ff1a0a"},
				{"pos": [-0.45, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 1, "colour": "#f4f4ff"},
				{"pos": [-0.15, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 0, "colour": "#ff1a0a"},
				{"pos": [0.15, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 0, "colour": "#f4f4ff"},
				{"pos": [0.45, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 1, "colour": "#ff1a0a"},
				{"pos": [0.75, 3.11, -4.3], "size": [0.28, 0.1, 0.3], "group": 0, "colour": "#f4f4ff"},
				{"pos": [-0.50, 1.02, -4.88], "size": [0.14, 0.05, 0.02], "group": 0, "colour": "#ff1a0a"},
				{"pos": [-1.245, 2.3, -2.25], "size": [0.03, 0.14, 0.14], "group": 1, "colour": "#ff1a0a"},
				{"pos": [-1.245, 2.3, 1.1], "size": [0.03, 0.14, 0.14], "group": 0, "colour": "#ff1a0a"},
				{"pos": [-1.13, 2.3, 4.535], "size": [0.14, 0.14, 0.03], "group": 0, "colour": "#ff1a0a"},
				{"pos": [0.50, 1.02, -4.88], "size": [0.14, 0.05, 0.02], "group": 1, "colour": "#ff1a0a"},
				{"pos": [1.245, 2.3, -2.25], "size": [0.03, 0.14, 0.14], "group": 0, "colour": "#ff1a0a"},
				{"pos": [1.245, 2.3, 1.1], "size": [0.03, 0.14, 0.14], "group": 1, "colour": "#ff1a0a"},
				{"pos": [1.13, 2.3, 4.535], "size": [0.14, 0.14, 0.03], "group": 1, "colour": "#ff1a0a"},
			],
			"glow": ["#ff2010", "#f4f4ff"],
			"words": [
				{"text": "IWWB", "pos": [1.235, 1.84, -3.7], "face": "right", "height": 0.24, "colour": "#e8c04a"},
				{"text": "IWWB", "pos": [-1.235, 1.84, -3.7], "face": "left", "height": 0.24, "colour": "#e8c04a"},
				{"text": "ENGINE 3", "pos": [1.235, 1.58, -3.7], "face": "right", "height": 0.1, "colour": "#b3140f"},
				{"text": "ENGINE 3", "pos": [-1.235, 1.58, -3.7], "face": "left", "height": 0.1, "colour": "#b3140f"},
				{"text": "ISLAND WEE-WOO BRIGADE", "pos": [1.235, 2.26, 1.1], "face": "right", "height": 0.11, "colour": "#b3140f"},
				{"text": "ISLAND WEE-WOO BRIGADE", "pos": [-1.235, 2.26, 1.1], "face": "left", "height": 0.11, "colour": "#b3140f"},
				{"text": "WEE-WOO", "pos": [0.0, 1.62, -4.75], "face": "front", "height": 0.2, "colour": "#f4f4f0"},
				{"text": "ENGINE 3", "pos": [0.0, 2.25, 4.56], "face": "back", "height": 0.14, "colour": "#e8c04a"},
				{"text": "YES, WE ALSO DO TRAFFIC", "pos": [0.0, 2.06, 4.56], "face": "back", "height": 0.07, "colour": "#f4f4f0"},
			],
		},
		"drive": {
			"body": {"mass": 15000.0, "weight_front": 0.42, "cg_height": 1.2, "drag": 4.8, "rolling": 110.0, "downforce": 0.0, "payload": 3000.0},
			"engine": {"idle_rpm": 650.0, "redline_rpm": 2300.0, "launch_rpm": 1100.0, "governor_kmh": 110.0,
				"torque": [[700.0, 1100.0], [1100.0, 1750.0], [1500.0, 1750.0], [1900.0, 1550.0], [2300.0, 1250.0]]},
			"gearbox": {"ratios": [3.5, 1.9, 1.43, 1.0, 0.75, 0.64], "final": 5.3, "reverse": 4.0, "shift_time": 0.5, "efficiency": 0.88},
			"drivetrain": "rwd",
			"tyres": {"grip": 0.84, "rear_grip": 1.0, "stiffness": 340000.0, "rear_stiffness": 1.0, "spin_grip": 0.45},
			"suspension": {"spring_hz": 1.4, "damping": 0.4, "travel": 0.12, "anti_roll": 0.8},
			"brakes": {"force": 110000.0, "front_bias": 0.42, "handbrake_rear_grip": 0.5, "abs": true},
			"steering": {"max_degrees": 44.0, "high_speed_degrees": 4.0, "speed": 1.7, "return": 3.0},
		},
	},
}

class_name TruckModels
extends RefCounted
## The working vehicles: a tractor unit, a flatbed trailer, a rollback tow
## truck and a forklift. Same layout as CarModels (CarModels.get_model finds
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
##   tool      the working part: "rollback" (tilt-and-slide deck and a winch)
##             or "forklift" (lift and tilt the forks); its settings are under
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
			"steering": {"max_degrees": 72.0, "high_speed_degrees": 30.0, "speed": 2.4, "return": 3.0},
		},
	},
}

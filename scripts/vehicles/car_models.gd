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
			"seat": [-0.4, 0.46, 0.38], "lights_y": 0.58, "tail_y": 0.72,
		},
		"drive": {
			"mass": 1480.0, "drivetrain": "rwd", "engine_force": 8600.0, "engine_power": 185000.0,
			"top_speed_kmh": 195.0, "brake_force": 13000.0, "grip": 1.02, "rear_grip_bias": 1.1,
			"cornering_stiffness": 90000.0, "rear_stiffness_ratio": 1.28, "yaw_inertia": 2050.0,
			"cg_to_front": 1.3, "cg_to_rear": 1.4, "cg_height": 0.46, "max_steer_degrees": 37.0,
			"high_speed_steer_degrees": 5.5, "handbrake_rear_grip": 0.45,
			"pitch_per_g": 0.04, "roll_per_g": 0.05, "body_settle_time": 0.13,
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
			"seat": [-0.38, 0.55, 0.18], "lights_y": 0.57, "tail_y": 0.68,
		},
		"drive": {
			"mass": 1350.0, "drivetrain": "fwd", "engine_force": 6400.0, "engine_power": 92000.0,
			"top_speed_kmh": 165.0, "brake_force": 10500.0, "grip": 1.0, "rear_grip_bias": 1.15,
			"cornering_stiffness": 82000.0, "rear_stiffness_ratio": 1.3, "yaw_inertia": 2100.0,
			"cg_to_front": 1.2, "cg_to_rear": 1.5, "cg_height": 0.52, "max_steer_degrees": 34.0,
			"high_speed_steer_degrees": 5.0, "handbrake_rear_grip": 0.52,
			"pitch_per_g": 0.045, "roll_per_g": 0.06, "body_settle_time": 0.16,
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
				"doors": 4, "c_pillar": 0.06},
			"bed": {"z0": 0.5, "z1": 2.76, "floor": 0.98, "top": 1.28, "thick": 0.07},
			"seat": [-0.42, 0.95, -0.05], "lights_y": 0.98, "tail_y": 1.05,
		},
		"drive": {
			"mass": 2150.0, "drivetrain": "rwd", "engine_force": 10500.0, "engine_power": 165000.0,
			"top_speed_kmh": 170.0, "brake_force": 15500.0, "grip": 0.92, "rear_grip_bias": 1.14,
			"cornering_stiffness": 115000.0, "rear_stiffness_ratio": 1.35, "yaw_inertia": 4400.0,
			"cg_to_front": 1.55, "cg_to_rear": 1.93, "cg_height": 0.78, "max_steer_degrees": 33.0,
			"high_speed_steer_degrees": 4.5, "handbrake_rear_grip": 0.48,
			"pitch_per_g": 0.07, "roll_per_g": 0.1, "body_settle_time": 0.22,
		},
	},
}


static func get_model(id: String) -> Dictionary:
	return MODELS.get(id, MODELS["civique"])


static func full_name(id: String) -> String:
	var m := get_model(id)
	return "%s %s" % [m["brand"], m["model"]]

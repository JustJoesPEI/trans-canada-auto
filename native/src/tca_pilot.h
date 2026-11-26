#pragma once

#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace godot {

// A CarAutopilot's steering and pedals toward a point: the native twin of
// CarAutopilot._drive_at_gd (with _avoid, _ground_ahead, _off_street,
// _lock_at, _pedals, _civil_pedals and _hold_stop_pedals) and _way_clear_gd
// in scripts/ai/car_autopilot.gd, which it must match exactly
// (CivilParity). The autopilot hands over what it has (its controls and
// what it remembers for them) and takes back what this works out; what's
// left for it to do (plan again, a K-turn, back out) it does itself.
class TcaPilot : public RefCounted {
	GDCLASS(TcaPilot, RefCounted)

	Object *pilot = nullptr; // the CarAutopilot (it holds this)
	RigidBody3D *car = nullptr;
	double max_degrees = 30.0, high_speed_degrees = 30.0, lock_kmh = 100.0, brake_force = 9000.0;
	double half_len = 2.4, half_wid = 0.9, wheelbase = 2.8, water_y = 0.0, way_margin = 0.25, way_sweep = 30.0;
	int64_t solid = 1, ground = 1;
	Ref<PhysicsRayQueryParameters3D> ray, ground_ray;
	Ref<BoxShape3D> sweep_box;
	Ref<PhysicsShapeQueryParameters3D> sweep_query;
	String blocker, blocker_shadow;

	// The controls while working them out.
	struct Controls {
		double steer, throttle, brake;
		bool handbrake;
		double civil_a;
		bool civil_braking;
	};
	void pedals(Controls &c, double want, double v, bool civil_on, double recover, int64_t turning, double skid, double dt) const;
	void civil_pedals(Controls &c, double want, double v, double skid, double dt) const;
	static void hold_stop_pedals(Controls &c, double v);
	double lock_at(double v) const;
	Vector2 avoid(const TypedArray<RID> &ex, double speed, double brake_accel, int64_t mask, Object *terrain, Object *network);
	double ground_ahead(const Transform3D &xf, double v, Object *terrain, Object *network);
	double off_street(const Vector2 &p, Object *network) const;
	TypedArray<RID> excluding(const Array &ignore) const;

protected:
	static void _bind_methods();

public:
	TcaPilot();
	// To an autopilot and its car: the car's steering ([max_degrees,
	// high_speed_degrees, lock_kmh]) and brake force, its half length, half
	// width and wheelbase, Terrain.WATER_Y, the solid and ground layers, and
	// WAY_MARGIN and WAY_SWEEP.
	void bind(Object *p_pilot, Object *p_car, const PackedFloat64Array &p_steering, double p_brake_force,
			double p_half_len, double p_half_wid, double p_wheelbase, double p_water_y, int64_t p_solid, int64_t p_ground,
			double p_way_margin, double p_way_sweep);
	// _drive_at: [what's left to do (0 nothing, 1 plan again, 2 a K-turn,
	// 3 back out), its number (the K-turn's angle, the side to back out
	// to), steer, throttle, brake, handbrake, _blocked, _civil_a,
	// _civil_braking, whether it's now "blocked"]. `blocker` it hands back
	// itself.
	PackedFloat64Array drive_at(const Vector2 &p_aim, double p_want, const Array &p_ignore, bool p_avoid, double p_aggression,
			double p_speed, double p_skid, bool p_civil, int64_t p_turning, bool p_mode_drive, double p_civil_replan,
			double p_street_dist, double p_bias_time, double p_bias, double p_recover,
			double p_steer, double p_throttle, double p_brake, bool p_handbrake, double p_blocked, double p_civil_a, bool p_civil_braking,
			double p_corner_accel, double p_brake_accel, double p_offroad_kmh, int64_t p_ray_mask, double p_dt,
			Object *p_terrain, Object *p_network);
	bool way_clear(const Vector2 &p_to, const Array &p_ignore);
};

} // namespace godot

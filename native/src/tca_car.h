#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

#include <vector>

namespace godot {

// A car's springs, engine, brakes, soft ground and tyres for one physics
// step: the native twin of Car._suspension_and_tyres (after the road under
// the wheels is found), _drive_force, _soft_ground and _dig in
// scripts/vehicles/car.gd, which it must match. It works on the car's own
// per-wheel arrays (bound once: Godot arrays are shared, so the car and
// everything that reads them see the same values) and its properties.
class TcaCar : public RefCounted {
	GDCLASS(TcaCar, RefCounted)

	// One kind of ground (GroundMap.KINDS).
	struct Kind {
		double grip, rolling, churn, sink, dig, bump, soft;
		Variant mud;
	};
	// The car's settings (its spec, which doesn't change: new parts make a
	// new car), read once.
	struct Spec {
		double grip, rear_grip, stiffness, rear_stiffness, spin_grip, offroad;
		double brake_force, handbrake_rear_grip;
		double downforce, drag, rolling;
		bool has_engine_spec;
		double idle, redline, final_ratio, reverse, shift_time, launch_rpm, efficiency, governor_kmh;
		bool has_governor;
		std::vector<double> ratios;
		std::vector<double> torque_rpm, torque_nm;
	};
	// Each wheel: what doesn't change, and what it remembers between steps.
	struct Wheel {
		bool leg, front;
		double travel, radius, static_load, k, c, bump_k, steer_factor, drive_share, brake_share, grip_m, stiff_mul, half_tread;
		Vector3 mount;
		Variant hit, anchor, anchor_on;
		double load = 0.0, compress = 0.0, wheel_drop = 0.0, ground_y = NAN, sink = 0.0, wheel_spin = 0.0, slide = 0.0;
		int64_t kind = 0;
	};

	RigidBody3D *car = nullptr;
	std::vector<Kind> kinds;
	Spec sp;
	std::vector<Wheel> w;
	int64_t n = 0;
	// The car's per-wheel arrays others read (TyreFx, the tools, the forklift,
	// tests), written back each step.
	Array a_hits, a_loads, a_anchor, a_anchor_on, a_compress, a_wheel_drop, a_ground_y, a_kind, a_sink, a_wheel_spin, a_slide;
	Array a_k_of, a_c_of, a_bump_k, a_grip_m;
	// While recording (CarParity): the forces kept, not applied.
	bool recording = false;
	Array recorded;
	void push(const Vector3 &f, const Vector3 &at);
	void push_on(RigidBody3D *on, const Vector3 &f, const Vector3 &at);
	void push_central(const Vector3 &f);

	double drive_force(double delta, double speed, double throttle);
	double torque_at(double at_rpm) const;
	PackedFloat32Array soft_ground(double delta, double speed, double throttle);
	void dig(int64_t i, bool spinning, double asked, double load, double vl, double delta, double belly);
	double ground_grip(int64_t i) const;
	static int64_t kind_of_hit(const Dictionary &hit);

protected:
	static void _bind_methods();

public:
	// Binds to a car (its arrays, once they're made) and GroundMap.KINDS.
	void bind(RigidBody3D *p_car, const Array &p_kinds);
	// The springs and grip again, after Car._limit_springs has capped them.
	void refresh_springs();
	// One step: `found` is WheelProbe.probe's answer for each wheel.
	void step(double p_delta, const Array &p_found, bool p_legs_down);
	// For CarParity: keep the forces in a list instead of applying them (and
	// leave out the camera jolt and the tyre marks), and hand that list over.
	void set_recording(bool p_on);
	Array take_forces();

	// GroundMap.bump_at and its noise, for the uneven ground.
	static double bump_at(int64_t p_kind, double p_x, double p_z);
	static double noise(double p_x, double p_z);
	static double hash(int64_t p_x, int64_t p_z);
};

} // namespace godot

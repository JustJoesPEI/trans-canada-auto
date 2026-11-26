#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <vector>

namespace godot {

// A StreetRoute's line and speed limits, for the queries a driver makes
// every step: the native twin of StreetRoute.project, sample, dir_at,
// limit_at and off_line (scripts/ai/street_route.gd), and of
// CarAutopilot._corner_speed. Made once per route (StreetRoute.native()):
// a route's line doesn't change once it's planned.
class TcaRoute : public RefCounted {
	GDCLASS(TcaRoute, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double STEP = 2.0; // StreetRoute.STEP

	std::vector<Vector2> pts;
	std::vector<float> lim;

	void set_line(const PackedVector2Array &p_points, const PackedFloat32Array &p_limit);
	double project(const Vector2 &p_p, double p_hint, double p_ahead) const;
	Vector2 sample(double p_d) const;
	Vector2 dir_at(double p_d) const;
	double limit_at(double p_d) const;
	double off_line(const Vector2 &p_p, double p_d) const;
	// CarAutopilot._corner_speed: how fast to be going at `along` doing `v`.
	double corner_speed(double p_along, double p_v, double p_brake_accel, double p_corner_brake, double p_corner_lag) const;
	int64_t size() const { return (int64_t)pts.size(); }
};

} // namespace godot

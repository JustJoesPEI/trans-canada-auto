#include "tca_route.h"

#include "tca_math.h"

#include <godot_cpp/core/class_db.hpp>

using namespace godot;
using namespace tca;

void TcaRoute::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_line", "points", "limit"), &TcaRoute::set_line);
	ClassDB::bind_method(D_METHOD("project", "p", "hint", "ahead"), &TcaRoute::project);
	ClassDB::bind_method(D_METHOD("sample", "d"), &TcaRoute::sample);
	ClassDB::bind_method(D_METHOD("dir_at", "d"), &TcaRoute::dir_at);
	ClassDB::bind_method(D_METHOD("limit_at", "d"), &TcaRoute::limit_at);
	ClassDB::bind_method(D_METHOD("off_line", "p", "d"), &TcaRoute::off_line);
	ClassDB::bind_method(D_METHOD("corner_speed", "along", "v", "brake_accel", "corner_brake", "corner_lag"), &TcaRoute::corner_speed);
}

void TcaRoute::set_line(const PackedVector2Array &p_points, const PackedFloat32Array &p_limit) {
	pts.assign(p_points.ptr(), p_points.ptr() + p_points.size());
	lim.assign(p_limit.ptr(), p_limit.ptr() + p_limit.size());
}

double TcaRoute::project(const Vector2 &p_p, double p_hint, double p_ahead) const {
	int64_t n = size();
	int64_t i0 = 0;
	int64_t i1 = n - 2;
	if (p_hint >= 0.0) {
		i0 = maxi(0, to_int((p_hint - 10.0) / STEP));
		i1 = mini(n - 2, to_int((p_hint + p_ahead) / STEP) + 1);
	}
	double best = INFINITY;
	double best_d = 0.0;
	for (int64_t i = i0; i < i1 + 1; i++) {
		const Vector2 &a = pts[i];
		const Vector2 &b = pts[i + 1];
		Vector2 q = closest_on_segment(p_p, a, b);
		double dd = dist2(p_p, q);
		if (dd < best) {
			best = dd;
			best_d = (double)i * STEP + (double)dist(a, q);
		}
	}
	return best_d;
}

Vector2 TcaRoute::sample(double p_d) const {
	int64_t n = size();
	if (n < 2) {
		return n == 1 ? pts[0] : Vector2();
	}
	double f = clampf(p_d / STEP, 0.0, (double)n - 1.0);
	int64_t i = mini(to_int(f), n - 2);
	return lerp2(pts[i], pts[i + 1], (float)(f - (double)i));
}

Vector2 TcaRoute::dir_at(double p_d) const {
	if (size() < 2) {
		return Vector2();
	}
	int64_t i = clampi(to_int(p_d / STEP), 0, size() - 2);
	return nrm(pts[i + 1] - pts[i]);
}

double TcaRoute::limit_at(double p_d) const {
	int64_t n = size();
	if (n < 2 || (int64_t)lim.size() < n) {
		return 0.0;
	}
	double f = clampf(p_d / STEP, 0.0, (double)n - 1.0);
	int64_t i = mini(to_int(f), n - 2);
	return lerpf((double)lim[i], (double)lim[i + 1], f - (double)i);
}

double TcaRoute::off_line(const Vector2 &p_p, double p_d) const {
	return (double)dist(p_p, sample(p_d));
}

double TcaRoute::corner_speed(double p_along, double p_v, double p_brake_accel, double p_corner_brake, double p_corner_lag) const {
	double b = p_brake_accel * p_corner_brake;
	double start = p_along + p_v * p_corner_lag;
	double best = INFINITY;
	double reach = p_v * p_corner_lag + p_v * p_v / (2.0 * b) + 6.0;
	double d = p_along;
	while (d <= p_along + reach) {
		double l = limit_at(d);
		best = minf(best, std::sqrt(l * l + 2.0 * b * maxf(d - start, 0.0)));
		d += STEP;
	}
	return best;
}

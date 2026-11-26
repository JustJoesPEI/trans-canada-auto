#include "tca_followers.h"

#include "tca_math.h"
#include "tca_route.h"

#include <cmath>

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;
using namespace tca;

namespace {
struct Names {
	StringName route, along, speed, speed_kmh, max_speed, hold_at, accel, decel, moving, terrain, velocity, length, native_var, native_fn;
	StringName cm, origin, spacing, nx, nz;
	Names() :
			route("route"), along("along"), speed("speed"), speed_kmh("speed_kmh"), max_speed("max_speed"), hold_at("hold_at"),
			accel("accel"), decel("decel"), moving("moving"), terrain("terrain"), velocity("velocity"), length("length"),
			native_var("_native"), native_fn("native"), cm("_cm"), origin("origin"), spacing("spacing"), nx("nx"), nz("nz") {}
};
Names *names = nullptr;

// A Vector2 lerp as the engine's (Math::lerp per component, real_t weight).
inline Vector2 at_along(const std::vector<Vector2> &pts, int64_t last, double a) {
	double f = clampf(a / TcaFollowers::STEP, 0.0, (double)last);
	int64_t i = mini(to_int(f), last - 1);
	// GDScript's negative index counts from the end (a line of one point).
	int64_t n = (int64_t)pts.size();
	const Vector2 &p0 = pts[(size_t)(i < 0 ? i + n : i)];
	const Vector2 &p1 = pts[(size_t)(i + 1 < 0 ? i + 1 + n : i + 1)];
	return lerp2(p0, p1, (float)(f - (double)i));
}
} // namespace

TcaFollowers::TcaFollowers() {
	if (names == nullptr) {
		names = memnew(Names);
	}
}

void TcaFollowers::_bind_methods() {
	ClassDB::bind_method(D_METHOD("step", "followers", "delta", "terrain"), &TcaFollowers::step);
}

bool TcaFollowers::read_ground(Object *p_terrain) {
	if (p_terrain == nullptr) {
		return false;
	}
	// The heights each call (an edit can re-shape them); the grid they're
	// on only when it's another terrain.
	cm = p_terrain->get(names->cm);
	const uint64_t id = p_terrain->get_instance_id();
	if (id != grid_of) {
		grid_of = id;
		origin = p_terrain->get(names->origin);
		spacing = p_terrain->get(names->spacing);
		nx = p_terrain->get(names->nx);
		nz = p_terrain->get(names->nz);
	}
	return true;
}

// Terrain.height_at.
double TcaFollowers::height_at(double x, double z) const {
	if (cm.is_empty()) {
		return 0.0;
	}
	double fx = clampf((x - (double)origin.x) / spacing, 0.0, (double)(nx - 1) - 0.001);
	double fz = clampf((z - (double)origin.y) / spacing, 0.0, (double)(nz - 1) - 0.001);
	int64_t ix = to_int(fx);
	int64_t iz = to_int(fz);
	double tx = fx - (double)ix;
	double tz = fz - (double)iz;
	int64_t i = (iz * nx + ix) * 2;
	int64_t row = nx * 2;
	const uint8_t *b = cm.ptr();
	int64_t size = cm.size();
	auto s16 = [&](int64_t k) -> double {
		if (k < 0 || k + 1 >= size) {
			return 0.0; // (PackedByteArray.decode_s16 out of range)
		}
		return (double)(int16_t)(uint16_t)(b[k] | (b[k + 1] << 8));
	};
	double a = s16(i);
	double bb = s16(i + 2);
	double c = s16(i + row);
	double d = s16(i + row + 2);
	return lerpf(lerpf(a, bb, tx), lerpf(c, d, tx), tz) * 0.01;
}

PackedInt32Array TcaFollowers::step(const Array &p_followers, double p_delta, Object *p_terrain) {
	PackedInt32Array arrived;
	const bool have_ground = read_ground(p_terrain);
	const uint64_t ground_id = p_terrain != nullptr ? p_terrain->get_instance_id() : 0;
	const int64_t n = p_followers.size();
	for (int64_t k = 0; k < n; k++) {
		Node3D *rf = Object::cast_to<Node3D>(p_followers[k]);
		if (rf == nullptr) {
			continue;
		}
		// TrafficManager._step_follower: one that's stopped stays stopped.
		if (!bool(rf->get(names->moving))) {
			rf->set(names->speed, 0.0);
			rf->set(names->velocity, Vector3());
			continue;
		}
		// _advance_follower.
		Object *route = rf->get(names->route);
		if (route == nullptr) {
			continue;
		}
		Variant nat = route->get(names->native_var);
		if (nat.get_type() == Variant::NIL) {
			nat = route->call(names->native_fn);
		}
		TcaRoute *tr = Object::cast_to<TcaRoute>(nat);
		if (tr == nullptr) {
			continue;
		}
		const double length = route->get(names->length);
		double along = rf->get(names->along);
		const double speed0 = rf->get(names->speed);
		const double max_speed = rf->get(names->max_speed);
		const double decel = rf->get(names->decel);
		double want = minf(minf(double(rf->get(names->speed_kmh)) / 3.6, tr->limit_at(along + speed0 * 0.3)), max_speed);
		const double hold_at = rf->get(names->hold_at);
		if (hold_at >= 0.0) {
			want = minf(want, std::sqrt(2.0 * decel * 0.8 * maxf(hold_at - along - 3.0, 0.0)));
			if (hold_at - along < 3.5) {
				rf->set(names->speed, 0.0);
				rf->set(names->velocity, Vector3());
				continue;
			}
		}
		const double speed = move_toward(speed0, want, (want > speed0 ? double(rf->get(names->accel)) : decel) * p_delta);
		rf->set(names->speed, speed);
		const Vector3 before = rf->get_global_position();
		along += maxf(speed, along < length - 0.5 && max_speed > 0.3 ? 0.3 : 0.0) * p_delta;
		const bool done = along >= length - 0.5;
		rf->set(names->along, done ? length : along);
		if (done) {
			rf->set(names->moving, false);
		}
		// place_follower.
		const std::vector<Vector2> &pts = tr->pts;
		const int64_t last = (int64_t)pts.size() - 1;
		Vector3 at;
		if (last >= 0) {
			const double a = done ? length : along;
			Vector2 p = at_along(pts, last, a);
			Vector2 ahead = at_along(pts, last, a + TURN_EASE);
			Vector2 d = ahead - at_along(pts, last, a - TURN_EASE);
			if (len2(d) < 0.25) {
				d = tr->dir_at(a);
			}
			d = nrm(d);
			double y;
			Variant tv = rf->get(names->terrain);
			Object *t = tv;
			if (t == nullptr) {
				y = rf->get_global_position().y;
			} else if (have_ground && t->get_instance_id() == ground_id) {
				y = height_at(p.x, p.y);
			} else {
				TcaFollowers other;
				other.read_ground(t);
				y = other.height_at(p.x, p.y);
			}
			at = Vector3(p.x, (float)y, p.y);
			rf->set_global_transform(Transform3D(Basis(Vector3(0, 1, 0), (float)std::atan2(-(double)d.x, -(double)d.y)), at));
		}
		if (done) {
			rf->set(names->speed, 0.0);
			rf->set(names->velocity, Vector3());
			arrived.push_back((int32_t)k);
			continue;
		}
		rf->set(names->velocity, (at - before) / (float)maxf(p_delta, 0.0001));
	}
	return arrived;
}

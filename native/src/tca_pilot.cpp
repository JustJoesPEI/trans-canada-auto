#include "tca_pilot.h"

#include "tca_math.h"

#include <cmath>

#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

using namespace godot;
using namespace tca;

namespace {
struct Names {
	StringName blocker, h2, nearest_on_streets, half_width;
	Variant position, collider, edge, dist;
	Names() :
			blocker("blocker"), h2("h2"), nearest_on_streets("nearest_on_streets"), half_width("half_width"),
			position(String("position")), collider(String("collider")), edge(String("edge")), dist(String("dist")) {}
};
Names *names = nullptr;
// CarAutopilot.RAY_ANGLES
const double RAY_ANGLES[5] = { 0.0, 0.3, -0.3, 0.65, -0.65 };
} // namespace

// GDScript deg_to_rad of a float.
static inline double deg_to_rad(double d) { return d * (Math_PI / 180.0); }

static inline double smoothstep(double from, double to, double s) {
	if (Math::is_equal_approx(from, to)) {
		if (from <= to) {
			return s <= from ? 0.0 : 1.0;
		}
		return s <= to ? 1.0 : 0.0;
	}
	double t = clampf((s - from) / (to - from), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

TcaPilot::TcaPilot() {
	if (names == nullptr) {
		names = memnew(Names);
	}
	ray.instantiate();
	ground_ray.instantiate();
}

void TcaPilot::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "pilot", "car", "steering", "brake_force", "half_len", "half_wid", "wheelbase", "water_y", "solid", "ground", "way_margin", "way_sweep"), &TcaPilot::bind);
	ClassDB::bind_method(D_METHOD("drive_at", "aim", "want", "ignore", "avoid", "aggression", "speed", "skid", "civil", "turning", "mode_drive",
								 "civil_replan", "street_dist", "bias_time", "bias", "recover", "steer", "throttle", "brake", "handbrake", "blocked",
								 "civil_a", "civil_braking", "corner_accel", "brake_accel", "offroad_kmh", "ray_mask", "dt", "terrain", "network"),
			&TcaPilot::drive_at);
	ClassDB::bind_method(D_METHOD("way_clear", "to", "ignore"), &TcaPilot::way_clear);
}

void TcaPilot::bind(Object *p_pilot, Object *p_car, const PackedFloat64Array &p_steering, double p_brake_force,
		double p_half_len, double p_half_wid, double p_wheelbase, double p_water_y, int64_t p_solid, int64_t p_ground,
		double p_way_margin, double p_way_sweep) {
	pilot = p_pilot;
	car = Object::cast_to<RigidBody3D>(p_car);
	if (p_steering.size() >= 3) {
		max_degrees = p_steering[0];
		high_speed_degrees = p_steering[1];
		lock_kmh = p_steering[2];
	}
	brake_force = p_brake_force;
	half_len = p_half_len;
	half_wid = p_half_wid;
	wheelbase = p_wheelbase;
	water_y = p_water_y;
	solid = p_solid;
	ground = p_ground;
	way_margin = p_way_margin;
	way_sweep = p_way_sweep;
	ground_ray->set_collision_mask((uint32_t)ground);
	blocker_shadow = pilot != nullptr ? String(pilot->get(names->blocker)) : String();
	blocker = blocker_shadow;
}

TypedArray<RID> TcaPilot::excluding(const Array &ignore) const {
	TypedArray<RID> ex;
	ex.push_back(car->get_rid());
	for (int64_t i = 0; i < ignore.size(); i++) {
		CollisionObject3D *co = Object::cast_to<CollisionObject3D>(ignore[i].get_validated_object());
		if (co != nullptr) {
			ex.push_back(co->get_rid());
		}
	}
	return ex;
}

double TcaPilot::lock_at(double v) const {
	return deg_to_rad(lerpf(max_degrees, high_speed_degrees, smoothstep(0.0, lock_kmh, v * 3.6)));
}

void TcaPilot::hold_stop_pedals(Controls &c, double v) {
	c.throttle = 0.0;
	if (v > 1.2) {
		c.brake = clampf(0.25 + v * 0.06, 0.0, 1.0);
		c.handbrake = false;
	} else if (v < -1.2) {
		c.throttle = clampf(0.25 - v * 0.06, 0.0, 1.0);
		c.brake = 0.0;
		c.handbrake = false;
	} else {
		c.brake = 0.0;
		c.handbrake = true;
	}
}

void TcaPilot::civil_pedals(Controls &c, double want, double v, double skid, double dt) const {
	if (want < 0.3 && v < 1.0) {
		c.civil_a = 0.0;
		c.civil_braking = false;
		hold_stop_pedals(c, v);
		return;
	}
	if (v < -0.5) {
		c.throttle = 1.0;
		c.brake = 0.0;
		return;
	}
	double a_des = clampf((want - v) / 0.8, -9.0, 3.0);
	double jerk = a_des < -4.0 ? 20.0 : 5.0;
	c.civil_a = move_toward(c.civil_a, a_des, jerk * dt);
	if (c.civil_braking && c.civil_a > -0.15) {
		c.civil_braking = false;
	} else if (!c.civil_braking && c.civil_a < -0.6) {
		c.civil_braking = true;
	}
	double full = brake_force / maxf((double)car->get_mass(), 1.0);
	if (c.civil_braking) {
		c.throttle = 0.0;
		c.brake = clampf((-c.civil_a - 0.25) / maxf(full, 2.0), 0.04, 1.0);
	} else {
		c.brake = 0.0;
		c.throttle = 0.0;
		if (c.civil_a > 0.0) {
			c.throttle = clampf(0.1 + c.civil_a * 0.3, 0.0, 0.9) * (1.0 - 0.6 * clampf(skid, 0.0, 1.0));
		}
	}
}

void TcaPilot::pedals(Controls &c, double want, double v, bool civil_on, double recover, int64_t turning, double skid, double dt) const {
	c.handbrake = false;
	if (civil_on && recover <= 0.0 && turning == 0) {
		civil_pedals(c, want, v, skid, dt);
		return;
	}
	if (want < 0.3) {
		hold_stop_pedals(c, v);
		return;
	}
	double err = want - v;
	if (v < -0.5) {
		c.throttle = 1.0;
		c.brake = 0.0;
		return;
	}
	if (err > -0.5) {
		c.throttle = clampf(0.12 + err * 0.35, 0.0, 1.0);
		c.throttle *= 1.0 - 0.6 * clampf(skid, 0.0, 1.0);
		c.brake = 0.0;
	} else if (err > -2.0) {
		c.throttle = 0.0;
		c.brake = 0.0;
	} else {
		c.throttle = 0.0;
		c.brake = clampf(-err * 0.18, 0.1, 1.0);
		if (v < 1.2) {
			c.brake = 0.0;
			c.handbrake = true;
		}
	}
}

double TcaPilot::off_street(const Vector2 &p, Object *network) const {
	const Dictionary hit = network->call(names->nearest_on_streets, p, 60.0);
	if (hit.is_empty()) {
		return 60.0;
	}
	Object *e = hit[names->edge];
	return maxf(0.0, double(hit[names->dist]) - double(e->get(names->half_width)));
}

double TcaPilot::ground_ahead(const Transform3D &xf, double v, Object *terrain, Object *network) {
	PhysicsDirectSpaceState3D *space = car->get_world_3d()->get_direct_space_state();
	double last = xf.origin.y;
	const double ds[2] = { 4.0, 4.0 + v * 0.6 };
	for (double d : ds) {
		Vector3 p = xf.xform(Vector3(0.0f, 0.0f, (float)(-half_len - d)));
		Vector2 fp(p.x, p.z);
		if (terrain != nullptr && double(terrain->call(names->h2, fp)) < water_y + 0.3 && off_street(fp, network) > 0.0) {
			return d;
		}
		ground_ray->set_from(p + Vector3(0, 1, 0) * 2.5f);
		ground_ray->set_to(p + Vector3(0, -1, 0) * 3.0f);
		const Dictionary h = space->intersect_ray(ground_ray);
		if (h.is_empty()) {
			continue;
		}
		double gy = Vector3(h[names->position]).y;
		if (gy < last - 1.2 - d * 0.15) {
			return d;
		}
		last = gy;
	}
	return INFINITY;
}

Vector2 TcaPilot::avoid(const TypedArray<RID> &ex, double speed, double brake_accel, int64_t mask, Object *terrain, Object *network) {
	double v = maxf(speed, 0.0);
	Transform3D xf = car->get_global_transform();
	PhysicsDirectSpaceState3D *space = car->get_world_3d()->get_direct_space_state();
	ray->set_exclude(ex);
	ray->set_collision_mask((uint32_t)mask);
	double reach = clampf(5.0 + v * 1.1, 7.0, 45.0);
	Vector3 origin = xf.xform(Vector3(0.0f, 0.7f, (float)(-half_len + 0.3)));
	double free[5];
	for (int k = 0; k < 5; k++) {
		double a = RAY_ANGLES[k];
		Vector3 dir = xf.basis.xform(Vector3((float)(-std::sin(a)), 0.0f, (float)(-std::cos(a))));
		double r = a == 0.0 ? reach : reach * (absf(a) < 0.5 ? 0.55 : 0.3);
		Vector3 from = origin + xf.basis.xform(Vector3((float)(signf(a) * half_wid * 0.8), 0.0f, 0.0f));
		ray->set_from(from);
		ray->set_to(from + dir * (float)r);
		const Dictionary h = space->intersect_ray(ray);
		free[k] = h.is_empty() ? 1.0 : ((double)from.distance_to(Vector3(h[names->position])) / r);
		if (a == 0.0) {
			if (h.is_empty()) {
				blocker = String();
			} else {
				Node *col = Object::cast_to<Node>((Object *)h[names->collider]);
				Node *par = col != nullptr ? col->get_parent() : nullptr;
				blocker = (par != nullptr ? String(par->get_name()) : String()) + "/" + (col != nullptr ? String(col->get_name()) : String());
			}
		}
	}
	double drop_at = ground_ahead(xf, v, terrain, network);
	if (drop_at < INFINITY) {
		free[0] = minf(free[0], drop_at / reach);
	}
	double add = 0.0;
	double top = INFINITY;
	double left = (1.0 - free[1]) + (1.0 - free[3]) * 0.6;
	double right = (1.0 - free[2]) + (1.0 - free[4]) * 0.6;
	add += (right - left) * 0.35;
	if (free[0] < 1.0) {
		double room = free[0] * reach - 2.5;
		top = std::sqrt(2.0 * brake_accel * maxf(room, 0.0));
		double lside = free[1] + free[3];
		double rside = free[2] + free[4];
		add += (lside > rside ? 0.5 : -0.5) * (1.0 - free[0]);
		if (maxf(lside, rside) > 1.2 && drop_at == INFINITY && room > 0.5) {
			top = maxf(top, 2.0);
		}
	}
	return Vector2((float)add, (float)top);
}

PackedFloat64Array TcaPilot::drive_at(const Vector2 &p_aim, double p_want, const Array &p_ignore, bool p_avoid, double p_aggression,
		double p_speed, double p_skid, bool p_civil, int64_t p_turning, bool p_mode_drive, double p_civil_replan,
		double p_street_dist, double p_bias_time, double p_bias, double p_recover,
		double p_steer, double p_throttle, double p_brake, bool p_handbrake, double p_blocked, double p_civil_a, bool p_civil_braking,
		double p_corner_accel, double p_brake_accel, double p_offroad_kmh, int64_t p_ray_mask, double p_dt,
		Object *p_terrain, Object *p_network) {
	Controls c{ p_steer, p_throttle, p_brake, p_handbrake, p_civil_a, p_civil_braking };
	double blocked = p_blocked;
	double act = 0.0, act_arg = 0.0;
	bool now_blocked = false;
	double want = p_want;
	const double v = p_speed;
	auto out = [&]() {
		PackedFloat64Array o;
		o.resize(10);
		double *w = o.ptrw();
		w[0] = act;
		w[1] = act_arg;
		w[2] = c.steer;
		w[3] = c.throttle;
		w[4] = c.brake;
		w[5] = c.handbrake ? 1.0 : 0.0;
		w[6] = blocked;
		w[7] = c.civil_a;
		w[8] = c.civil_braking ? 1.0 : 0.0;
		w[9] = now_blocked ? 1.0 : 0.0;
		if (pilot != nullptr && blocker != blocker_shadow) {
			blocker_shadow = blocker;
			pilot->set(names->blocker, blocker);
		}
		return o;
	};
	Transform3D xf = car->get_global_transform();
	Basis inv = xf.basis.inverse();
	Vector3 local = inv.xform(Vector3(p_aim.x, xf.origin.y, p_aim.y) - xf.origin);
	double alpha = std::atan2((double)-local.x, (double)-local.z);
	double ld = maxf((double)len(Vector2(local.x, local.z)), 1.0);
	// Civil, pointing the wrong way: plan again first.
	if (p_civil && p_turning == 0 && p_mode_drive && absf(alpha) > deg_to_rad(110.0) && v < 3.0 && p_civil_replan <= 0.0) {
		act = 1.0;
		return out();
	}
	// K-turn.
	if (p_turning != 0 || (absf(alpha) > deg_to_rad(110.0) && v < 3.0 && ld > 4.0)) {
		act = 2.0;
		act_arg = alpha;
		return out();
	}
	if (absf(alpha) > deg_to_rad(100.0) && v > 3.0) {
		pedals(c, 0.0, v, p_civil, p_recover, p_turning, p_skid, p_dt);
		c.steer = signf(alpha);
		return out();
	}
	double delta_wheel = std::atan(2.0 * wheelbase * std::sin(alpha) / ld);
	double s = delta_wheel / lock_at(absf(v));
	Vector3 lv = inv.xform(car->get_linear_velocity());
	if (absf(lv.z) > 3.0) {
		double beta = std::atan2((double)-lv.x, (double)-lv.z);
		s += clampf(beta * 1.2, -0.6, 0.6);
	}
	double turn_cap = std::sqrt(p_corner_accel * (1.0 + p_aggression * 0.5) / maxf(absf(2.0 * std::sin(alpha) / ld), 0.001));
	want = minf(want, maxf(turn_cap, 4.0));
	if (p_street_dist > 1.0) {
		want = minf(want, p_offroad_kmh / 3.6);
	}
	if (p_bias_time > 0.0) {
		s += p_bias;
	}
	double asked = want;
	if (p_avoid) {
		Vector2 av = avoid(excluding(p_ignore), v, p_brake_accel, p_ray_mask, p_terrain, p_network);
		s += av.x;
		want = minf(want, av.y);
	}
	c.steer = clampf(s, -1.0, 1.0);
	c.handbrake = false;
	pedals(c, want, v, p_civil, p_recover, p_turning, p_skid, p_dt);
	if (asked > (p_civil ? 0.6 : 2.0) && want < (p_civil ? 0.5 : 1.0) && absf(v) < 1.0) {
		blocked += p_dt;
		now_blocked = true;
		if (blocked > 0.7) {
			act = 3.0;
			act_arg = absf(s) > 0.1 ? -signf(s) : 1.0;
		}
	} else {
		blocked = maxf(0.0, blocked - p_dt);
	}
	return out();
}

bool TcaPilot::way_clear(const Vector2 &p_to, const Array &p_ignore) {
	PhysicsDirectSpaceState3D *space = car->get_world_3d()->get_direct_space_state();
	Transform3D xf = car->get_global_transform();
	TypedArray<RID> ex = excluding(p_ignore);
	if (sweep_box.is_null()) {
		sweep_box.instantiate();
		sweep_query.instantiate();
		sweep_query->set_collision_mask((uint32_t)solid);
	}
	sweep_box->set_size(Vector3((float)((half_wid + way_margin) * 2.0), 1.1f, 1.0f));
	Vector3 from = xf.xform(Vector3(0.0f, 1.05f, (float)-half_len));
	Vector3 dest(p_to.x, from.y, p_to.y);
	Vector3 motion = dest - from;
	if ((double)motion.length() < 0.5) {
		return true;
	}
	motion = motion.limit_length((float)way_sweep);
	sweep_query->set_shape(sweep_box);
	sweep_query->set_exclude(ex);
	sweep_query->set_transform(Transform3D(Basis::looking_at(motion.normalized(), Vector3(0, 1, 0)), from));
	sweep_query->set_motion(motion);
	PackedFloat32Array frac = space->cast_motion(sweep_query);
	return frac.size() == 0 || (double)frac[0] >= 1.0;
}

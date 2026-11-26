#include "tca_car.h"

#include <cmath>

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

// As in car.gd.
static const double SINK_DRAG = 0.5;
static const double DIG_RATE = 0.09;
static const double CLIMB_OUT = 0.05;
static const double SPIN_LOSS = 0.35;
static const double CRAWL_RESERVE = 0.6;
static const int64_t PAVED = 0;
static const int64_t FIELD = 4;

// GDScript's own helpers, exactly.
static inline double signf(double x) { return x == 0.0 ? 0.0 : (x < 0.0 ? -1.0 : 1.0); }
static inline double clampf(double x, double lo, double hi) { return x < lo ? lo : (x > hi ? hi : x); }
static inline double lerpf(double a, double b, double w) { return a + (b - a) * w; }
static inline double move_toward(double from, double to, double delta) {
	return std::abs(to - from) <= delta ? to : from + signf(to - from) * delta;
}
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
static inline double num(const Variant &v) { return double(v); }
static inline double dget(const Dictionary &d, const char *k) { return double(d[k]); }
static inline double dget(const Dictionary &d, const char *k, double def) { return d.has(k) ? double(d[k]) : def; }

namespace {
struct Names {
	StringName spec, tyres, brakes, body, engine, gearbox;
	StringName speed, steer_angle, throttle, brake, handbrake, abs, grip_factor, power_factor, stalled, has_engine;
	StringName gear, shift_timer, rpm, wheel_radius, tool, driver, age, wheels_down, skid, anti_roll, belly;
	StringName ground, ground_soft, bogged, dirt, dirt_colour;
	StringName position, normal, collider, bumped, jolt_camera, tyre_fx, full_top_speed, motion, ground_map, kind_at;
	Names() :
			spec("spec"), tyres("tyres"), brakes("brakes"), body("body"), engine("engine"), gearbox("gearbox"),
			speed("speed"), steer_angle("steer_angle"), throttle("_throttle"), brake("_brake"), handbrake("_handbrake"), abs("_abs"),
			grip_factor("grip_factor"), power_factor("power_factor"), stalled("stalled"), has_engine("_has_engine"),
			gear("gear"), shift_timer("_shift_timer"), rpm("rpm"), wheel_radius("wheel_radius"), tool("tool"), driver("driver"),
			age("_age"), wheels_down("wheels_down"), skid("skid"), anti_roll("_anti_roll"), belly("_belly"),
			ground("ground"), ground_soft("ground_soft"), bogged("bogged"), dirt("dirt"), dirt_colour("dirt_colour"),
			position("position"), normal("normal"), collider("collider"), bumped("bumped"), jolt_camera("_jolt_camera"),
			tyre_fx("_tyre_fx"), full_top_speed("full_top_speed"), motion("motion"), ground_map("ground_map"), kind_at("kind_at") {}
};
Names *names = nullptr;
} // namespace

void TcaCar::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "car", "kinds"), &TcaCar::bind);
	ClassDB::bind_method(D_METHOD("refresh_springs"), &TcaCar::refresh_springs);
	ClassDB::bind_method(D_METHOD("step", "delta", "found", "legs_down"), &TcaCar::step);
	ClassDB::bind_method(D_METHOD("set_recording", "on"), &TcaCar::set_recording);
	ClassDB::bind_method(D_METHOD("take_forces"), &TcaCar::take_forces);
	ClassDB::bind_static_method("TcaCar", D_METHOD("bump_at", "kind", "x", "z"), &TcaCar::bump_at);
}

void TcaCar::bind(RigidBody3D *p_car, const Array &p_kinds) {
	if (names == nullptr) {
		names = memnew(Names);
	}
	car = p_car;
	if (car == nullptr) {
		return;
	}
	kinds.clear();
	for (int64_t i = 0; i < p_kinds.size(); i++) {
		const Dictionary k = p_kinds[i];
		kinds.push_back({ dget(k, "grip"), dget(k, "rolling"), dget(k, "churn"), dget(k, "sink"), dget(k, "dig"), dget(k, "bump"), dget(k, "soft"), k["mud"] });
	}
	const Dictionary spec = car->get(names->spec);
	const Dictionary tyres = spec[names->tyres];
	const Dictionary brakes = spec[names->brakes];
	const Dictionary body = spec[names->body];
	sp.grip = dget(tyres, "grip");
	sp.rear_grip = dget(tyres, "rear_grip");
	sp.stiffness = dget(tyres, "stiffness");
	sp.rear_stiffness = dget(tyres, "rear_stiffness");
	sp.spin_grip = dget(tyres, "spin_grip");
	sp.offroad = dget(tyres, "offroad", 0.0);
	sp.brake_force = dget(brakes, "force");
	sp.handbrake_rear_grip = dget(brakes, "handbrake_rear_grip");
	sp.downforce = dget(body, "downforce");
	sp.drag = dget(body, "drag");
	sp.rolling = dget(body, "rolling");
	sp.has_engine_spec = spec.get("engine", Variant()).get_type() == Variant::DICTIONARY;
	sp.ratios.clear();
	sp.torque_rpm.clear();
	sp.torque_nm.clear();
	if (sp.has_engine_spec) {
		const Dictionary eng = spec[names->engine];
		const Dictionary box = spec[names->gearbox];
		sp.idle = dget(eng, "idle_rpm");
		sp.redline = dget(eng, "redline_rpm");
		sp.launch_rpm = dget(eng, "launch_rpm", sp.idle + 1800.0);
		sp.has_governor = eng.has("governor_kmh");
		sp.governor_kmh = dget(eng, "governor_kmh", 0.0);
		const Array curve = eng["torque"];
		for (int64_t i = 0; i < curve.size(); i++) {
			const Array pt = curve[i];
			sp.torque_rpm.push_back(num(pt[0]));
			sp.torque_nm.push_back(num(pt[1]));
		}
		sp.final_ratio = dget(box, "final");
		sp.reverse = dget(box, "reverse");
		sp.shift_time = dget(box, "shift_time");
		sp.efficiency = dget(box, "efficiency");
		const Array ratios = box["ratios"];
		for (int64_t i = 0; i < ratios.size(); i++) {
			sp.ratios.push_back(num(ratios[i]));
		}
	}
#define BIND(m_field, m_name) m_field = car->get(m_name)
	BIND(a_hits, "_hits");
	BIND(a_loads, "_loads");
	BIND(a_anchor, "_anchor");
	BIND(a_anchor_on, "_anchor_on");
	BIND(a_compress, "_compress");
	BIND(a_wheel_drop, "_wheel_drop");
	BIND(a_ground_y, "_ground_y");
	BIND(a_kind, "_kind");
	BIND(a_sink, "_sink");
	BIND(a_wheel_spin, "_wheel_spin");
	BIND(a_slide, "_slide");
	BIND(a_k_of, "_k_of");
	BIND(a_c_of, "_c_of");
	BIND(a_bump_k, "_bump_k");
	BIND(a_grip_m, "_grip_m");
#undef BIND
	const Array is_leg = car->get("_is_leg");
	const Array is_front = car->get("_is_front");
	const Array travel_of = car->get("_travel_of");
	const Array radius = car->get("_radius");
	const Array mounts = car->get("_mounts");
	const Array static_load = car->get("_static_load");
	const Array steer_factor = car->get("_steer_factor");
	const Array drive_share = car->get("_drive_share");
	const Array brake_share = car->get("_brake_share");
	const Array stiff_mul = car->get("_stiff_mul");
	const Array half_tread = car->get("_half_tread");
	n = mounts.size();
	w.assign(n, Wheel());
	for (int64_t i = 0; i < n; i++) {
		Wheel &x = w[i];
		x.leg = is_leg[i];
		x.front = is_front[i];
		x.travel = travel_of[i];
		x.radius = radius[i];
		x.mount = mounts[i];
		x.static_load = static_load[i];
		x.steer_factor = steer_factor[i];
		x.drive_share = drive_share[i];
		x.brake_share = brake_share[i];
		x.stiff_mul = stiff_mul[i];
		x.half_tread = half_tread[i];
		// What it remembers, as it stands (a car can be handed over mid-life).
		x.hit = a_hits[i];
		x.anchor = a_anchor[i];
		x.anchor_on = a_anchor_on[i];
		x.load = a_loads[i];
		x.compress = a_compress[i];
		x.wheel_drop = a_wheel_drop[i];
		x.ground_y = a_ground_y[i];
		x.kind = a_kind[i];
		x.sink = a_sink[i];
		x.wheel_spin = a_wheel_spin[i];
		x.slide = a_slide[i];
	}
	refresh_springs();
}

void TcaCar::set_recording(bool p_on) {
	recording = p_on;
}

Array TcaCar::take_forces() {
	Array out = recorded;
	recorded = Array();
	return out;
}

void TcaCar::push(const Vector3 &f, const Vector3 &at) {
	if (!recording) {
		car->apply_force(f, at);
		return;
	}
	Array r;
	r.push_back("force");
	r.push_back(f);
	r.push_back(at);
	recorded.push_back(r);
}

void TcaCar::push_on(RigidBody3D *on, const Vector3 &f, const Vector3 &at) {
	if (!recording) {
		on->apply_force(f, at);
		return;
	}
	Array r;
	r.push_back("on");
	r.push_back(f);
	r.push_back(at);
	r.push_back(on);
	recorded.push_back(r);
}

void TcaCar::push_central(const Vector3 &f) {
	if (!recording) {
		car->apply_central_force(f);
		return;
	}
	Array r;
	r.push_back("central");
	r.push_back(f);
	recorded.push_back(r);
}

void TcaCar::refresh_springs() {
	for (int64_t i = 0; i < n; i++) {
		w[i].k = a_k_of[i];
		w[i].c = a_c_of[i];
		w[i].bump_k = a_bump_k[i];
		w[i].grip_m = a_grip_m[i];
	}
}

double TcaCar::hash(int64_t x, int64_t z) {
	int64_t h = (x * 374761393 + z * 668265263) & 0x7fffffff;
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff;
	return double(h & 0xffff) / 65535.0;
}

double TcaCar::noise(double x, double z) {
	int64_t ix = int64_t(std::floor(x));
	int64_t iz = int64_t(std::floor(z));
	double fx = x - ix;
	double fz = z - iz;
	fx = fx * fx * (3.0 - 2.0 * fx);
	fz = fz * fz * (3.0 - 2.0 * fz);
	double a = lerpf(hash(ix, iz), hash(ix + 1, iz), fx);
	double b = lerpf(hash(ix, iz + 1), hash(ix + 1, iz + 1), fx);
	return lerpf(a, b, fz) * 2.0 - 1.0;
}

double TcaCar::bump_at(int64_t p_kind, double x, double z) {
	if (p_kind == FIELD) {
		return std::sin(x * Math_TAU / 0.9) * 0.6 + noise(x * 0.7, z * 0.7) * 0.4;
	}
	return noise(x * 1.3, z * 1.3);
}

int64_t TcaCar::kind_of_hit(const Dictionary &hit) {
	Object *body = hit.get(names->collider, Variant());
	if (body == nullptr || !body->has_meta(names->ground_map)) {
		return PAVED;
	}
	Object *map = body->get_meta(names->ground_map);
	const Vector3 p = hit[names->position];
	return int64_t(map->call(names->kind_at, p.x, p.z));
}

double TcaCar::ground_grip(int64_t i) const {
	const Kind &gk = kinds[w[i].kind];
	return gk.grip + (1.0 - gk.grip) * sp.offroad * gk.soft;
}

double TcaCar::torque_at(double at_rpm) const {
	const size_t m = sp.torque_rpm.size();
	if (at_rpm <= sp.torque_rpm[0]) {
		return sp.torque_nm[0];
	}
	for (size_t i = 1; i < m; i++) {
		if (at_rpm <= sp.torque_rpm[i]) {
			return lerpf(sp.torque_nm[i - 1], sp.torque_nm[i], (at_rpm - sp.torque_rpm[i - 1]) / (sp.torque_rpm[i] - sp.torque_rpm[i - 1]));
		}
	}
	return sp.torque_nm[m - 1];
}

double TcaCar::drive_force(double delta, double speed, double throttle_in) {
	const Names &N = *names;
	if (!bool(car->get(N.has_engine)) || bool(car->get(N.stalled))) {
		car->set(N.rpm, 0.0);
		return 0.0;
	}
	const double idle = sp.idle;
	const double redline = sp.redline;
	const double wheel_radius = car->get(N.wheel_radius);
	int64_t gear = car->get(N.gear);
	if (throttle_in < 0.0) {
		gear = -1;
	} else if (gear < 1) {
		gear = 1;
	}
	const double ratio = (gear < 0 ? sp.reverse : sp.ratios[gear - 1]) * sp.final_ratio;
	const double wheel_rpm = std::abs(speed) / wheel_radius * 60.0 / Math_TAU;
	const double engine_rpm = wheel_rpm * ratio;
	double shift_timer = std::max(0.0, double(car->get(N.shift_timer)) - delta);
	if (gear > 0 && shift_timer <= 0.0) {
		if (engine_rpm > redline * 0.94 && gear < int64_t(sp.ratios.size())) {
			gear += 1;
			shift_timer = sp.shift_time;
		} else if (gear > 1 && engine_rpm < redline * 0.45 * (throttle_in > 0.5 ? 1.0 : 0.8)) {
			const double lower_rpm = wheel_rpm * sp.ratios[gear - 2] * sp.final_ratio;
			if (lower_rpm < redline * 0.88) {
				gear -= 1;
				shift_timer = sp.shift_time * 0.6;
			}
		}
	}
	car->set(N.gear, gear);
	car->set(N.shift_timer, shift_timer);
	// (`ratio` stays the gear it started the step in, as in car.gd.)
	double rpm = clampf(std::max(engine_rpm, lerpf(idle, sp.launch_rpm, std::abs(throttle_in))), idle, redline + 200.0);
	Object *tool = car->get(N.tool);
	if (tool != nullptr && Object::cast_to<Object>(car->get(N.driver)) != nullptr) {
		rpm = std::max(rpm, lerpf(idle, std::min(redline * 0.75, idle * 2.2), double(tool->call(N.motion))));
	}
	car->set(N.rpm, rpm);
	if (throttle_in == 0.0) {
		return -signf(speed) * std::min(std::abs(speed) * 40.0 * std::max(1.0, double(car->get_mass()) / 2500.0), torque_at(rpm) * 0.15 * ratio / wheel_radius);
	}
	if (shift_timer > 0.0 || engine_rpm > redline) {
		return 0.0;
	}
	double throttle = std::abs(throttle_in);
	if (sp.has_governor && throttle_in > 0.0) {
		throttle *= clampf((sp.governor_kmh - speed * 3.6) / 3.0, 0.0, 1.0);
	}
	const double power_factor = car->get(N.power_factor);
	if (power_factor < 1.0 && throttle_in > 0.0) {
		throttle *= clampf((double(car->call(N.full_top_speed)) * power_factor - speed) / 1.0, 0.0, 1.0);
	}
	const double torque = torque_at(rpm) * throttle * power_factor;
	return signf(throttle_in) * torque * ratio * sp.efficiency / wheel_radius;
}

PackedFloat32Array TcaCar::soft_ground(double delta, double speed, double throttle) {
	const Names &N = *names;
	// (A PackedFloat32Array, as in car.gd: the values are rounded to 32 bits.)
	PackedFloat32Array out;
	out.resize(n + 1);
	float *o = out.ptrw();
	for (int64_t i = 0; i <= n; i++) {
		o[i] = 0.0f;
	}
	double total = 0.0;
	double push = 0.0;
	double most = 0.0;
	int64_t ground = PAVED;
	double ground_soft = 0.0;
	double sunk = 0.0;
	int64_t down = 0;
	const double v = std::abs(speed);
	for (int64_t i = 0; i < n; i++) {
		const Wheel &x = w[i];
		if (x.hit.get_type() == Variant::NIL || x.leg) {
			continue;
		}
		const Kind &gk = kinds[x.kind];
		const double load = x.load;
		if (load > most) {
			most = load;
			ground = x.kind;
		}
		ground_soft = std::max(ground_soft, gk.soft);
		sunk += x.sink;
		down += 1;
		const double r = gk.rolling + gk.churn * v + SINK_DRAG * x.sink / x.radius;
		o[i] = float(load * r);
		total += double(o[i]);
		if (x.drive_share > 0.0) {
			push += load * sp.grip * ground_grip(i) * (1.0 - SPIN_LOSS * gk.soft);
		}
	}
	const double mass = car->get_mass();
	if (down > 0) {
		const double over = sunk / down - (double(car->get(N.belly)) - 0.04);
		if (over > 0.0) {
			o[n] = float(mass * 9.81 * 0.3 * clampf(over / 0.06, 0.0, 1.0));
			total += double(o[n]);
		}
	}
	const double lim = CRAWL_RESERVE * push;
	if (total > lim && push > 0.0) {
		const double keep = lerpf(lim / total, 1.0, smoothstep(0.8, 1.8, v));
		for (int64_t i = 0; i <= n; i++) {
			o[i] = float(double(o[i]) * keep);
		}
	}
	car->set(N.ground, ground);
	car->set(N.ground_soft, ground_soft);
	car->set(N.bogged, std::abs(throttle) > 0.1 ? clampf(total / std::max(push, 1.0), 0.0, 1.0) * ground_soft : 0.0);
	if (ground_soft > 0.0 && down > 0) {
		double spin = 0.0;
		for (int64_t i = 0; i < n; i++) {
			spin = std::max(spin, w[i].wheel_spin);
		}
		const double dirt = car->get(N.dirt);
		car->set(N.dirt, std::min(1.0, dirt + delta * ground_soft * ground_soft * (v * 0.004 + spin * 0.01)));
		car->set(N.dirt_colour, kinds[ground].mud);
	} else if (down > 0) {
		const double dirt = car->get(N.dirt);
		car->set(N.dirt, std::max(0.0, dirt - delta * v * 0.00015));
	}
	return out;
}

void TcaCar::dig(int64_t i, bool spinning, double asked, double load, double vl, double delta, double belly) {
	Wheel &x = w[i];
	const Kind &gk = kinds[x.kind];
	const double moved = std::abs(vl) * delta;
	const double spin_v = spinning ? clampf(asked - 1.0, 0.0, 2.0) * 3.0 : 0.0;
	x.wheel_spin = move_toward(x.wheel_spin, spin_v, delta * 20.0);
	if (gk.sink <= 0.0) {
		x.sink = move_toward(x.sink, 0.0, delta * 0.3 + moved * 0.5);
		return;
	}
	const double float_f = std::sqrt(0.31 / x.radius) * std::sqrt(0.105 / std::max(x.half_tread, 0.05));
	const double settle = gk.sink * clampf(load / std::max(x.static_load, 1.0), 0.0, 2.0) * float_f;
	const double deepest = std::min(settle + gk.dig * float_f, belly + 0.04);
	if (spinning) {
		x.sink = std::min(deepest, x.sink + DIG_RATE * clampf(asked - 1.0, 0.0, 2.0) * 0.5 * delta);
	} else if (x.sink > settle) {
		x.sink = move_toward(x.sink, settle, moved * CLIMB_OUT);
	} else {
		x.sink = move_toward(x.sink, settle, delta * 0.2);
	}
}

void TcaCar::step(double delta, const Array &found, bool legs_down) {
	if (car == nullptr || n == 0) {
		return;
	}
	const Names &N = *names;
	const Transform3D xf = car->get_global_transform();
	const Basis basis = xf.basis;
	const Vector3 up = basis.get_column(1);
	const Vector3 fwd = -basis.get_column(2);
	const Vector3 com = xf.xform(car->get_center_of_mass());
	const Vector3 lin = car->get_linear_velocity();
	const Vector3 ang = car->get_angular_velocity();
	const double speed = car->get(N.speed);
	const double age = car->get(N.age);
	const double steer_angle = car->get(N.steer_angle);
	const double throttle = car->get(N.throttle);
	const double brake = car->get(N.brake);
	const bool handbrake = car->get(N.handbrake);
	const bool abs_on = car->get(N.abs);
	const double grip_factor = car->get(N.grip_factor);
	const double anti_roll = car->get(N.anti_roll);
	const double belly = car->get(N.belly);

	// --- springs: the road under each wheel ---
	int64_t wheels_down = 0;
	double punch = 0.0;
	for (int64_t i = 0; i < n; i++) {
		Wheel &x = w[i];
		x.hit = Variant();
		x.load = 0.0;
		if (x.leg && !legs_down) {
			x.anchor = Variant();
			x.compress = 0.0;
			x.wheel_drop = 0.0;
			continue;
		}
		const double travel = x.travel;
		const double r = x.radius;
		const Vector3 from = xf.xform(x.mount);
		const Variant fv = found[i];
		if (fv.get_type() == Variant::NIL) {
			x.anchor = Variant();
			x.compress = 0.0;
			x.ground_y = NAN;
			x.wheel_drop = move_toward(x.wheel_drop, travel * 2.0, delta * 3.0);
			continue;
		}
		const Dictionary hit = fv;
		if (!x.leg) {
			wheels_down += 1;
		}
		x.kind = kind_of_hit(hit);
		const Vector3 hp = hit[N.position];
		double hit_y = hp.y;
		if (x.kind != PAVED) {
			hit_y += kinds[x.kind].bump * bump_at(x.kind, hp.x, hp.z) - x.sink;
		}
		Object *col = hit[N.collider];
		if (std::isnan(x.ground_y) || up.y < 0.5 || Object::cast_to<RigidBody3D>(col) != nullptr) {
			x.ground_y = hit_y;
		} else {
			const Vector3 pv = lin + ang.cross(from - com);
			const double rate = 0.3 + 2.5 * Vector2(pv.x, pv.z).length();
			x.ground_y = move_toward(x.ground_y, hit_y, rate * delta);
		}
		const double dist = (double(from.y) - x.ground_y) / up.y - r;
		const double cx = clampf(travel * 2.0 - dist, 0.0, travel * 2.0);
		const double x_vel = (cx - x.compress) / delta;
		if (!x.leg) {
			punch = std::max(punch, x_vel);
		}
		x.compress = cx;
		x.wheel_drop = travel * 2.0 - cx;
		double f = x.static_load + x.k * (cx - travel) + x.c * x_vel;
		if (cx > travel * 1.85) {
			f += x.bump_k * (cx - travel * 1.85);
		}
		x.hit = hit;
		x.load = std::max(f, 0.0);
	}
	car->set(N.wheels_down, wheels_down);
	if (punch > 1.2 && age > 1.0 && !recording) {
		car->emit_signal(N.bumped, punch);
		car->call(N.jolt_camera, clampf((punch - 1.0) / 6.0, 0.05, 0.4));
	}
	// Anti-roll bars.
	for (int64_t axle = 0; axle < n; axle += 2) {
		if (w[axle].leg) {
			continue;
		}
		if (w[axle].hit.get_type() != Variant::NIL && w[axle + 1].hit.get_type() != Variant::NIL) {
			const double ar = (w[axle].compress - w[axle + 1].compress) * w[axle].k * anti_roll;
			w[axle].load = std::max(0.0, w[axle].load + ar);
			w[axle + 1].load = std::max(0.0, w[axle + 1].load - ar);
		}
	}

	// --- the engine's push and the brakes ---
	const double drive = drive_force(delta, speed, throttle);
	const double downforce = sp.downforce * speed * speed;
	const PackedFloat32Array resist = soft_ground(delta, speed, throttle);

	// --- tyres ---
	const Vector3 origin = xf.origin;
	double skid = car->get(N.skid);
	for (int64_t i = 0; i < n; i++) {
		Wheel &x = w[i];
		x.slide = 0.0;
		if (x.hit.get_type() == Variant::NIL) {
			continue;
		}
		const Dictionary hit = x.hit;
		const Vector3 nrm = hit[N.normal];
		const Vector3 p = hit[N.position];
		const double load = x.load + downforce * 0.25;
		Object *col = hit[N.collider];
		RigidBody3D *on = Object::cast_to<RigidBody3D>(col);
		const bool leg = x.leg;
		Vector3 total = up * real_t(x.load);
		Vector3 heading = fwd;
		if (x.steer_factor != 0.0) {
			heading = fwd.rotated(up, real_t(steer_angle * x.steer_factor));
		}
		const Vector3 w_fwd = (heading - nrm * heading.dot(nrm)).normalized();
		const Vector3 w_side = w_fwd.cross(nrm).normalized();
		Vector3 v = lin + ang.cross(p - com);
		if (on != nullptr) {
			PhysicsDirectBodyState3D *st = PhysicsServer3D::get_singleton()->body_get_direct_state(on->get_rid());
			v -= st->get_velocity_at_local_position(p - on->get_global_position());
		}
		const double vl = v.dot(w_fwd);
		const double vs = v.dot(w_side);
		double fx = 0.0;
		double fy = 0.0;
		const bool rear = !x.front;
		double mu = leg ? 0.7 : sp.grip * (rear ? sp.rear_grip : 1.0) * grip_factor;
		mu *= ground_grip(i);
		double b = 0.0;
		const double gm_i = x.grip_m;
		if (!leg) {
			if (rear && handbrake) {
				mu *= sp.handbrake_rear_grip;
			}
			double cap = mu * load;
			fx = drive * x.drive_share;
			b = brake * sp.brake_force * x.brake_share;
			if (rear && handbrake) {
				b = std::max(b, cap * 0.9);
			} else if (abs_on) {
				b = std::min(b, cap * 0.92);
			}
			fx -= signf(vl) * std::min(b, std::abs(vl) * gm_i / delta);
			const bool spinning = std::abs(fx) > cap;
			const double asked = std::abs(fx) / std::max(cap, 1.0);
			if (spinning) {
				cap *= 1.0 - SPIN_LOSS * kinds[x.kind].soft;
			}
			fx = clampf(fx, -cap, cap);
			fx -= signf(vl) * std::min(double(resist[i]), std::abs(vl) * gm_i / delta);
			dig(i, spinning, asked, load, vl, delta, belly);
			const double stiff = sp.stiffness * 0.5 * (rear ? sp.rear_stiffness : 1.0) * x.stiff_mul;
			const double slip = std::atan2(vs, std::max(std::abs(vl), 2.0));
			double side_cap = std::sqrt(std::max(cap * cap - fx * fx, std::pow(sp.spin_grip * cap, 2.0)));
			if (spinning) {
				side_cap = std::min(side_cap, sp.spin_grip * cap * 1.6);
			}
			fy = -side_cap * std::tanh(stiff * slip / std::max(side_cap, 1.0));
			const double crawl = 1.0 - smoothstep(0.5, 3.0, std::abs(vl));
			const double hold = clampf(-vs * gm_i / delta * 0.5, -side_cap, side_cap);
			fy = lerpf(fy, hold, crawl);
			const double moving = smoothstep(1.0, 4.0, v.length());
			double sl = clampf((std::abs(stiff * slip) / std::max(side_cap, 1.0) - 1.0) * 0.2, 0.0, 1.0);
			if (spinning) {
				sl = std::max(sl, clampf((asked - 1.0) * 1.5, 0.0, 1.0));
			}
			if (rear && handbrake && std::abs(vl) > 2.0) {
				sl = std::max(sl, 0.6);
			}
			x.slide = sl * std::max(moving, spinning ? 0.6 : 0.0);
			skid = std::max(skid, x.slide);
		}
		// Stopped: the tyre sticks where it is, in the frame of what it stands on.
		const bool stopped = std::abs(vl) < 0.3 && std::abs(vs) < 0.3;
		if (!stopped) {
			x.anchor = Variant();
		} else if (x.anchor.get_type() == Variant::NIL || Object::cast_to<Object>(x.anchor_on) != col) {
			x.anchor_on = col;
			x.anchor = Object::cast_to<Node3D>(col)->get_global_transform().affine_inverse().xform(p);
		}
		if (x.anchor.get_type() != Variant::NIL) {
			const bool along = leg || (b > 0.0 && std::abs(throttle) < 0.05);
			const double cap_hold = mu * load;
			const double wn = Math_TAU * 1.5;
			const double gm = gm_i;
			Node3D *on3 = Object::cast_to<Node3D>(x.anchor_on);
			const Vector3 stuck = on3->get_global_transform().xform(Vector3(x.anchor));
			Vector3 err = stuck - p;
			err -= nrm * err.dot(nrm);
			Vector3 v_flat = w_fwd * real_t(vl) + w_side * real_t(vs);
			if (!along) {
				err -= w_fwd * err.dot(w_fwd);
				v_flat = w_side * real_t(vs);
			}
			Vector3 f = err * real_t(gm) * real_t(wn) * real_t(wn) - v_flat * real_t(2.0) * real_t(gm) * real_t(wn);
			if (f.length() > cap_hold) {
				f = f.normalized() * real_t(cap_hold);
				const double reach = cap_hold / (gm * wn * wn);
				if (err.length() > reach) {
					x.anchor = on3->get_global_transform().affine_inverse().xform(p + err.normalized() * real_t(reach));
				}
			}
			fy = f.dot(w_side);
			if (along) {
				fx = f.dot(w_fwd);
			}
		} else if (leg) {
			const Vector3 flat = w_fwd * real_t(vl) + w_side * real_t(vs);
			if (flat.length() > 0.001) {
				const Vector3 fr = -flat.normalized() * real_t(mu) * real_t(load);
				fx = fr.dot(w_fwd);
				fy = fr.dot(w_side);
			}
		}
		total += w_fwd * real_t(fx) + w_side * real_t(fy);
		push(total, p - origin);
		if (on != nullptr && !on->is_freeze_enabled()) {
			push_on(on, -total, p - on->get_global_position());
		}
	}
	car->set(N.skid, skid);

	// Back to the car's arrays, for what reads them (TyreFx first).
	for (int64_t i = 0; i < n; i++) {
		const Wheel &x = w[i];
		a_hits[i] = x.hit;
		a_loads[i] = x.load;
		a_anchor[i] = x.anchor;
		a_anchor_on[i] = x.anchor_on;
		a_compress[i] = x.compress;
		a_wheel_drop[i] = x.wheel_drop;
		a_ground_y[i] = x.ground_y;
		a_kind[i] = x.kind;
		a_sink[i] = x.sink;
		a_wheel_spin[i] = x.wheel_spin;
		a_slide[i] = x.slide;
	}
	if (!recording) {
		car->call(N.tyre_fx);
	}
	if (double(resist[n]) > 0.0) {
		// The underside dragging through the mud.
		const Vector3 flat = lin - up * lin.dot(up);
		const double vf = flat.length();
		if (vf > 0.001) {
			push_central(-flat / real_t(vf) * real_t(std::min(double(resist[n]), vf * double(car->get_mass()) / delta * 0.5)));
		}
	}
	// --- air and rolling resistance ---
	const Vector3 air = -lin * lin.length() * real_t(sp.drag);
	Vector3 rolling;
	if (wheels_down > 0) {
		rolling = -fwd * real_t(speed) * real_t(sp.rolling);
	}
	push_central(air + rolling);
	if (wheels_down > 0 && downforce > 0.0) {
		push_central(-up * real_t(downforce));
	}
}

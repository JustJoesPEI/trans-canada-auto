#include "tca_civil.h"

#include "tca_math.h"

#include <cmath>
#include <unordered_map>

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using namespace tca;

// As in civil_driving.gd.
static const double LOOK = 80.0;
enum { STRAIGHT = 0, LEFT = 1, RIGHT = 2 }; // CivilDriving.Turn

namespace {
struct Names {
	StringName lateral, holding, reason, honk, stuck_time, want_reroute, leader, leader_gap, hazard, passes, pull_overs, honks, close_behind;
	StringName nearest_on_streets, half_width, speed_mul, creep, tailed;
	Variant edge, dist;
	// The reasons and hazards it says.
	String empty, queue, red, amber, stop_sign, yield, box, siren, crash, launch, person, hazard_s, oncoming, near_miss, cut_off, siren_crossing, bus_stop, startled, startled_eased, hit;
	Names() :
			lateral("lateral"), holding("holding"), reason("reason"), honk("honk"), stuck_time("stuck_time"), want_reroute("want_reroute"),
			leader("leader"), leader_gap("leader_gap"), hazard("hazard"), passes("passes"), pull_overs("pull_overs"), honks("honks"),
			close_behind("close_behind"), nearest_on_streets("nearest_on_streets"), half_width("half_width"),
			speed_mul("_speed_mul"), creep("_creep"), tailed("_tailed"),
			edge(String("edge")), dist(String("dist")),
			empty(""), queue("queue"), red("red"), amber("amber"), stop_sign("stop_sign"), yield("yield"), box("box"), siren("siren"),
			crash("crash"), launch("launch"), person("person"), hazard_s("hazard"), oncoming("oncoming"), near_miss("near_miss"),
			cut_off("cut_off"), siren_crossing("siren_crossing"), bus_stop("bus_stop"), startled("startled"),
			startled_eased("startled_eased"), hit("hit") {}
};
Names *names = nullptr;
// Each CivilDriving's twin, by the CivilDriving's instance id (for "is the
// car ahead waiting its turn").
std::unordered_map<uint64_t, TcaCivil *> *registry = nullptr;
// JunctionRules.Rule's SIGNAL, STOP, YIELD; TrafficSignal's times.
int64_t RULE_SIGNAL = 0, RULE_STOP = 1, RULE_YIELD = 2;
double GREEN_TIME = 14.0, AMBER_TIME = 3.5, ALL_RED_TIME = 1.5;
int64_t SOLID = 1;
} // namespace

TcaCivil *TcaCivil::of(uint64_t p_civil_id) {
	if (registry == nullptr || p_civil_id == 0) {
		return nullptr;
	}
	auto it = registry->find(p_civil_id);
	return it == registry->end() ? nullptr : it->second;
}

TcaCivil::TcaCivil() {
	if (names == nullptr) {
		names = memnew(Names);
	}
	if (registry == nullptr) {
		registry = new std::unordered_map<uint64_t, TcaCivil *>();
	}
	ray.instantiate();
}

TcaCivil::~TcaCivil() {
	if (registry != nullptr && civil_id != 0) {
		auto it = registry->find(civil_id);
		if (it != registry->end() && it->second == this) {
			registry->erase(it);
		}
	}
}

void TcaCivil::_bind_methods() {
	ClassDB::bind_method(D_METHOD("bind", "civil", "body", "net", "claims", "rules", "solid", "follower", "signal_times"), &TcaCivil::bind);
	ClassDB::bind_method(D_METHOD("set_settings", "settings"), &TcaCivil::set_settings);
	ClassDB::bind_method(D_METHOD("set_scan_t", "t"), &TcaCivil::set_scan_t);
	ClassDB::bind_method(D_METHOD("set_route", "route", "limit_end", "limit_kmh", "limit_room", "junctions", "nids"), &TcaCivil::set_route);
	ClassDB::bind_method(D_METHOD("step", "along", "v", "top", "delta", "clock", "scan_every", "to_curb", "curb_keep", "want_reroute", "hazard"), &TcaCivil::step);
	ClassDB::bind_method(D_METHOD("hold_for", "seconds", "why", "aside", "aside_most"), &TcaCivil::hold_for);
	ClassDB::bind_method(D_METHOD("hold_active"), &TcaCivil::hold_active);
	ClassDB::bind_method(D_METHOD("release_hold"), &TcaCivil::release_hold);
	ClassDB::bind_method(D_METHOD("rush", "factor", "seconds"), &TcaCivil::rush);
	ClassDB::bind_method(D_METHOD("startle", "seconds"), &TcaCivil::startle);
	ClassDB::bind_method(D_METHOD("react_crash", "seconds"), &TcaCivil::react_crash);
	ClassDB::bind_method(D_METHOD("react_hit", "wait"), &TcaCivil::react_hit);
	ClassDB::bind_method(D_METHOD("honk_for", "seconds"), &TcaCivil::honk_for);
	ClassDB::bind_method(D_METHOD("curb_room", "along", "curb_keep"), &TcaCivil::curb_room);
	ClassDB::bind_method(D_METHOD("debug_info"), &TcaCivil::debug_info);
	ClassDB::bind_method(D_METHOD("get_state"), &TcaCivil::get_state);
}

void TcaCivil::bind(Object *p_civil, Object *p_body, Object *p_net, const Dictionary &p_claims, const PackedInt64Array &p_rules, int64_t p_solid, bool p_follower, const PackedFloat64Array &p_signal_times) {
	if (registry != nullptr && civil_id != 0) {
		registry->erase(civil_id);
	}
	civil = p_civil;
	civil_id = p_civil != nullptr ? p_civil->get_instance_id() : 0;
	if (civil_id != 0) {
		(*registry)[civil_id] = this;
	}
	body = Object::cast_to<Node3D>(p_body);
	body_id = body != nullptr ? body->get_instance_id() : 0;
	net = p_net;
	claims = p_claims;
	is_follower = p_follower;
	if (p_rules.size() >= 3) {
		RULE_SIGNAL = p_rules[0];
		RULE_STOP = p_rules[1];
		RULE_YIELD = p_rules[2];
	}
	SOLID = p_solid;
	if (p_signal_times.size() >= 3) {
		GREEN_TIME = p_signal_times[0];
		AMBER_TIME = p_signal_times[1];
		ALL_RED_TIME = p_signal_times[2];
	}
}

void TcaCivil::set_settings(const PackedFloat64Array &p_s) {
	if (p_s.size() < 13) {
		return;
	}
	speed_factor = p_s[0];
	headway = p_s[1];
	standstill_gap = p_s[2];
	max_accel = p_s[3];
	comfort_brake = p_s[4];
	reaction = p_s[5];
	patience = p_s[6];
	temper = p_s[7];
	gap_time = p_s[8];
	tourist = p_s[9] != 0.0;
	pulls_over = p_s[10] != 0.0;
	half_len = p_s[11];
	half_wid = p_s[12];
}

void TcaCivil::set_route(const Ref<TcaRoute> &p_route, const PackedFloat32Array &p_end, const PackedFloat32Array &p_kmh, const PackedFloat32Array &p_room, const PackedFloat64Array &p_j, const PackedStringArray &p_nids) {
	// As CivilDriving._prepare leaves things.
	route = p_route;
	junctions.clear();
	limit_end.assign(p_end.ptr(), p_end.ptr() + p_end.size());
	limit_kmh.assign(p_kmh.ptr(), p_kmh.ptr() + p_kmh.size());
	limit_room.assign(p_room.ptr(), p_room.ptr() + p_room.size());
	curb_at = -INFINITY;
	stop_at = INFINITY;
	lead_user.reset();
	lat_target = 0.0;
	pass_node = 0;
	want_reroute = false;
	const int64_t W = 16;
	int64_t nj = p_nids.size();
	for (int64_t k = 0; k < nj && (k + 1) * W <= p_j.size(); k++) {
		const double *x = p_j.ptr() + k * W;
		Junction j;
		j.nid = p_nids[k];
		j.nid_v = j.nid;
		j.line = x[0];
		j.exit = x[1];
		j.radius = x[2];
		j.in_dir = Vector2((float)x[3], (float)x[4]);
		j.phase = (int64_t)x[5];
		j.control = (int64_t)x[6];
		j.turn = (int64_t)x[7];
		j.opposite = x[8] != 0.0;
		j.major = x[9] != 0.0;
		j.sig_offset = x[10];
		j.e_oneway = (int64_t)x[11];
		j.e_lanes = (int64_t)x[12];
		j.e_half_width = x[13];
		j.np = Vector2((float)x[14], (float)x[15]);
		junctions.push_back(j);
	}
}

Node3D *TcaCivil::node_of(uint64_t p_id) const {
	if (p_id == 0) {
		return nullptr;
	}
	return Object::cast_to<Node3D>(ObjectDB::get_instance(p_id));
}

// --- back to the CivilDriving ---------------------------------------------------

void TcaCivil::write_back() {
	if (civil == nullptr) {
		return;
	}
#define WB(m_f)                         \
	if (m_f != shadow.m_f) {            \
		shadow.m_f = m_f;               \
		civil->set(names->m_f, m_f);    \
	}
	WB(lateral)
	WB(holding)
	WB(reason)
	WB(honk)
	WB(stuck_time)
	WB(want_reroute)
	WB(leader_gap)
	if (hazard_dirty || hazard != shadow.hazard) {
		hazard_dirty = false;
		shadow.hazard = hazard;
		civil->set(names->hazard, hazard);
	}
	WB(passes)
	WB(pull_overs)
	WB(honks)
	WB(close_behind)
	WB(speed_mul)
	WB(creep)
	WB(tailed)
#undef WB
	if (leader != shadow.leader) {
		shadow.leader = leader;
		Object *o = leader != 0 ? ObjectDB::get_instance(leader) : nullptr;
		civil->set(names->leader, o != nullptr ? Variant(o) : Variant());
	}
}

// --- orders --------------------------------------------------------------------

void TcaCivil::hold_for(double p_seconds, const String &p_why, bool p_aside, double p_aside_most) {
	hold_until = time + p_seconds;
	hold_reason = p_why;
	hold_aside = p_aside;
	hold_aside_most = p_aside_most;
}

bool TcaCivil::hold_active() const {
	return time < hold_until;
}

void TcaCivil::release_hold() {
	hold_until = -100.0;
	hold_aside = false;
}

void TcaCivil::do_rush(double factor, double seconds) {
	speed_mul = factor;
	speed_mul_until = time + seconds;
}

void TcaCivil::rush(double p_factor, double p_seconds) {
	do_rush(p_factor, p_seconds);
}

void TcaCivil::do_startle(double seconds) {
	if (close_behind) {
		do_rush(0.6, seconds + 1.0);
		hazard = names->startled_eased;
		hazard_dirty = true;
	} else {
		hold_until = maxf(hold_until, time + reaction + seconds);
		hold_reason = names->startled;
	}
}

void TcaCivil::startle(double p_seconds) {
	do_startle(p_seconds);
	write_back();
}

void TcaCivil::react_crash(double p_seconds) {
	hazard = names->crash;
	hazard_dirty = true;
	hold_until = maxf(hold_until, time + reaction + p_seconds);
	hold_reason = names->crash;
	write_back();
}

void TcaCivil::react_hit(double p_wait) {
	hazard = names->hit;
	hazard_dirty = true;
	do_honk(0.9);
	hold_until = maxf(hold_until, time + p_wait);
	hold_reason = names->crash;
	write_back();
}

bool TcaCivil::do_honk(double seconds) {
	if (time < honk_next) {
		return false;
	}
	honk_until = time + seconds;
	honk_next = time + seconds + 3.0;
	honks += 1;
	return true;
}

bool TcaCivil::honk_for(double p_seconds) {
	bool r = do_honk(p_seconds);
	write_back();
	return r;
}

// --- the speed -----------------------------------------------------------------

double TcaCivil::step(double p_along, double p_v, double p_top, double p_delta, double p_clock, double p_scan_every, double p_to_curb, double p_curb_keep, bool p_want_reroute, const String &p_hazard) {
	const double along = p_along, v = p_v, top = p_top, delta = p_delta;
	clock = p_clock;
	scan_every = p_scan_every;
	to_curb = p_to_curb;
	curb_keep = p_curb_keep;
	want_reroute = p_want_reroute;
	shadow.want_reroute = p_want_reroute;
	hazard = p_hazard;
	shadow.hazard = p_hazard;
	hazard_dirty = false;
	time += delta;
	scan_t -= delta;
	if (scan_t <= 0.0) {
		scan_t += scan_every;
		scan(along, v);
	}
	honk = time < honk_until;
	if (time > speed_mul_until) {
		speed_mul = 1.0;
	}
	double v0 = minf(top, limit_at(along) / 3.6 * speed_factor * speed_mul);
	if (tourist_cap) {
		v0 = minf(v0, 5.5);
	}
	v0 = minf(v0, approach_cap);
	double acc = max_accel * (1.0 - std::pow(clampf(v / maxf(v0, 0.3), 0.0, 3.0), 4.0));
	if (v > v0 + 0.3) {
		acc = minf(acc, maxf((v0 - v) / 0.7, -comfort_brake * 1.4));
	}
	if (v0 < 0.31) {
		acc = minf(acc, -comfort_brake);
	}
	const String *hold_r = &names->empty;
	// The car ahead, where it is now.
	leader = 0;
	leader_gap = INFINITY;
	Node3D *ln = lead_user ? node_of(lead_user->node) : nullptr;
	if (ln != nullptr) {
		Vector3 lp = ln->get_global_position();
		double la = route->project(Vector2(lp.x, lp.z), lead_along, 15.0);
		double gap = la - along - half_len - lead_user->half_len;
		double lv = dot(lead_user->vel, route->dir_at(la));
		leader = lead_user->node;
		leader_gap = gap;
		double a = idm(v, v0, gap, v - lv, standstill_gap);
		if (v < 0.5 && gap < standstill_gap + 1.5 && lv < 0.5) {
			a = minf(a, -1.0); // stopped close behind: stay put, don't creep
		}
		if (a < acc) {
			acc = a;
			if (v < 1.0 && gap < standstill_gap + 8.0) {
				hold_r = lead_waiting() ? &names->queue : &names->empty;
			}
		}
	}
	// The line it has to stop at.
	if (stop_at < INFINITY) {
		double to_line = stop_at - along - half_len;
		double a = idm(v, v0, to_line, v, 0.5);
		if (v < 0.5 && to_line < 3.0) {
			a = minf(a, -1.0);
		}
		if (a < acc) {
			acc = a;
			if (v < 1.0) {
				hold_r = &stop_reason;
			}
		}
	} else if (creep) {
		v0 = minf(v0, 2.0);
	}
	// Someone in the road.
	if (person_at < INFINITY && time - hazard_t > reaction) {
		double a = idm(v, v0, person_at - along - half_len - 0.5, v, 2.5);
		acc = minf(acc, a);
		if (v < 1.0) {
			hold_r = &names->person;
		}
	}
	// A siren.
	if (pulls_over && time - siren_t < 1.5 && time - hazard_t > reaction * 0.5) {
		double cap = siren_close ? 0.0 : 3.0;
		if (tailed) {
			cap = 3.0;
		}
		acc = minf(acc, max_accel * (1.0 - std::pow(clampf(v / maxf(cap, 0.3), 0.0, 3.0), 2.0)));
		if (cap == 0.0) {
			acc = minf(acc, -comfort_brake * 1.2 * signf(v));
		} else if (tailed && v < cap && leader_gap > standstill_gap + 3.0 && stop_at == INFINITY) {
			acc = maxf(acc, 0.6);
		}
		if (v < 1.0) {
			hold_r = &names->siren;
		}
	}
	// A car coming at it.
	if (time < swerve_until) {
		acc = minf(acc, -7.0);
		if (v < 1.0) {
			hold_r = &names->hazard_s;
		}
	}
	if (time < hold_until) {
		acc = minf(acc, v > 0.5 ? -comfort_brake * 1.3 : -1.0);
		if (v < 1.0) {
			hold_r = &hold_reason;
		}
	}
	acc = clampf(acc, -9.0, max_accel);
	double want = clampf(v + acc * 0.8, 0.0, maxf(top, 0.0));
	// Pulling away takes a moment.
	if (v < 0.4 && want > 0.6) {
		launch += delta;
		if (launch < reaction) {
			want = 0.0;
			hold_r = &names->launch;
		}
	} else if (v > 1.0) {
		launch = 0.0;
	}
	reason = *hold_r;
	holding = !reason.is_empty();
	if (v < 0.5 && !holding) {
		stuck_time += delta;
	} else {
		stuck_time = maxf(0.0, stuck_time - delta * 3.0);
	}
	steer_lateral(along, delta, v);
	write_back();
	return want;
}

double TcaCivil::idm(double v, double v0, double gap, double dv, double s0) const {
	double s = maxf(gap, 0.05);
	double ss = s0 + maxf(0.0, v * headway + v * dv / (2.0 * std::sqrt(max_accel * comfort_brake)));
	double free = 1.0 - std::pow(clampf(v / maxf(v0, 0.3), 0.0, 3.0), 4.0);
	return max_accel * (free - (ss / s) * (ss / s));
}

static bool is_waiting(const String &r) {
	return r == names->red || r == names->amber || r == names->stop_sign || r == names->yield || r == names->box ||
			r == names->queue || r == names->siren || r == names->crash || r == names->launch;
}

bool TcaCivil::lead_waiting() const {
	if (!lead_user) {
		return false;
	}
	if (lead_user->civil.get_type() != Variant::NIL) {
		String r;
		bool h = TcaRoadUsers::civil_holding(*lead_user, &r);
		return h && is_waiting(r);
	}
	for (const Junction &j : junctions) {
		if (lead_along > j.line - 18.0 && lead_along < j.exit + 4.0) {
			return true;
		}
	}
	return false;
}

void TcaCivil::steer_lateral(double along, double delta, double v) {
	double target = lat_target;
	double rate = 0.9;
	if (pulls_over && time - siren_t < 1.5) {
		target = -room_right(along);
		rate = 1.4;
	}
	if (to_curb >= 0.0) {
		target = minf(target, -maxf(0.0, curb_room_at(along) - to_curb));
	}
	if (hold_aside && time < hold_until) {
		if (hold_aside_most < 0.0) {
			target = -maxf(0.0, curb_room_at(along) + hold_aside_most);
		} else {
			target = -minf(room_right(along), hold_aside_most);
		}
	}
	if (time < swerve_until) {
		target = -room_right(along) - 1.2;
		rate = 3.0;
	}
	if (absf(target) < absf(lateral) && absf(v) < 4.0) {
		rate = minf(rate, 0.1 + absf(v) * 0.25);
	}
	lateral = move_toward(lateral, target, rate * delta);
}

double TcaCivil::room_right(double along) const {
	int64_t i = limit_index(along);
	return i >= 0 ? (double)limit_room[i] : 1.0;
}

double TcaCivil::curb_room_at(double along) {
	if (route.is_null() || net == nullptr) {
		return room_right(along);
	}
	if (absf(along - curb_at) > 4.0) {
		curb_at = along;
		Vector2 p = route->sample(along);
		const Dictionary hit = net->call(names->nearest_on_streets, p, 25.0);
		if (hit.is_empty()) {
			curb_room_v = room_right(along);
		} else {
			Object *e = hit[names->edge];
			curb_room_v = double(e->get(names->half_width)) - double(hit[names->dist]) - half_wid;
		}
	}
	return maxf(0.0, curb_room_v - curb_keep);
}

double TcaCivil::curb_room(double p_along, double p_curb_keep) {
	curb_keep = p_curb_keep;
	return curb_room_at(p_along);
}

int64_t TcaCivil::limit_index(double along) const {
	for (size_t i = 0; i < limit_end.size(); i++) {
		if (along <= (double)limit_end[i]) {
			return (int64_t)i;
		}
	}
	return (int64_t)limit_end.size() - 1;
}

double TcaCivil::limit_at(double along) const {
	int64_t i = limit_index(along);
	return i >= 0 ? (double)limit_kmh[i] : 50.0;
}

// --- looking round ---------------------------------------------------------------

void TcaCivil::scan(double along, double v) {
	TcaRoadUsers *ru = TcaRoadUsers::singleton;
	Vector3 bp = body->get_global_position();
	Vector2 me(bp.x, bp.z);
	if (ru != nullptr) {
		ru->ensure(body->get_tree());
		ru->near(me, LOOK + 120.0, users);
	} else {
		users.clear();
	}
	Vector3 f3 = -body->get_global_basis().get_column(2);
	Vector2 fwd = nrm(Vector2(f3.x, f3.z));
	Vector2 side_dir(fwd.y, -fwd.x);
	ahead.clear();
	double next_line = INFINITY;
	for (const Junction &j : junctions) {
		if (along + half_len < j.exit) {
			next_line = j.line;
			break;
		}
	}
	bool in_junction = along + half_len > next_line;
	double p_at = INFINITY;
	bool oncoming = false, tailed_now = false, behind_close = false, siren = false, siren_close_now = false;
	double siren_behind_d = INFINITY;
	const Vector2 fwd_v = fwd * (float)v;
	for (int32_t ui : users) {
		const TcaRoadUsers::User &u = *ru->list[ui];
		if (u.node == body_id) {
			continue;
		}
		Vector2 rel = u.pos - me;
		double d2 = len2(rel);
		if (d2 > LOOK * LOOK) {
			continue;
		}
		double ahead_by = dot(rel, fwd);
		bool is_car = u.civil.get_type() == Variant::NIL && !u.siren && !u.person && u.is_car;
		if (u.siren && pulls_over) {
			double d = std::sqrt(d2);
			bool behind = ahead_by < -1.0;
			double closing = dot(u.vel - fwd_v, -rel / (float)maxf(d, 0.1));
			bool toward = ahead_by > 0.0 && dot(u.fwd, fwd) < -0.3 && d < 60.0;
			if ((behind && (closing > 0.5 || d < 30.0)) || toward) {
				siren = true;
				siren_close_now = siren_close_now || (behind && d < 28.0) || (toward && d < 25.0);
				if (behind) {
					siren_behind_d = minf(siren_behind_d, d);
				}
			}
		}
		// Whipped past close by someone in a hurry.
		if (is_car && d2 < 64.0) {
			double side = absf(dot(rel, side_dir)) - half_wid - u.half_wid;
			double closing = len(u.vel - fwd_v);
			if (side < 1.2 && absf(ahead_by) < half_len + u.half_len && closing > 11.0 && time > startle_next) {
				startle_next = time + 6.0;
				hazard = names->near_miss;
				if (UtilityFunctions::randf() < 0.35 + temper) {
					do_honk(0.5 + temper * 0.6);
				}
				if (UtilityFunctions::randf() < 0.4) {
					do_startle(0.4);
				}
			}
		}
		if (ahead_by < -half_len - 2.0 && !u.person && ahead_by > -half_len - u.half_len - maxf(14.0, maxf(u.speed, 0.0) * 2.0) && absf(dot(rel, side_dir)) < half_wid + u.half_wid && dot(u.fwd, fwd) > 0.5) {
			behind_close = true;
		}
		if (ahead_by < -half_len - 2.0) {
			if (is_car && ahead_by > -half_len - u.half_len - 9.0 && absf(dot(rel, side_dir)) < half_wid + u.half_wid && dot(u.fwd, fwd) > 0.5) {
				tailed_now = true;
			}
			continue;
		}
		double au = route->project(u.pos, along, LOOK + 10.0);
		if (au <= along + 0.3) {
			continue;
		}
		Vector2 p = route->sample(au);
		Vector2 dir = route->dir_at(au);
		double lat = dot(u.pos - p, Vector2(dir.y, -dir.x));
		bool against = dot(u.fwd, dir) < -0.5 && u.speed > 1.0;
		if (against && is_follower) {
			continue;
		}
		if (against && au > next_line - 1.0 && !in_junction) {
			continue;
		}
		double reach = u.half_wid + half_wid + 0.45;
		if (u.person) {
			reach = half_wid + 0.9;
		} else if (against) {
			reach = u.half_wid + half_wid - 0.15;
		}
		if (absf(lat - lateral) > reach) {
			continue;
		}
		if (u.person) {
			p_at = minf(p_at, au);
			continue;
		}
		if (against && !in_junction && v + u.speed > 4.0 && au - along < maxf(12.0, (v + u.speed) * 3.0)) {
			oncoming = true;
		}
		ahead.push_back({ au, ui, lat });
	}
	struct ByAlong {
		bool operator()(const Ahead &a, const Ahead &b) const { return a.along < b.along; }
	};
	Sorter<Ahead, ByAlong> sorter;
	sorter.sort(ahead.data(), (int64_t)ahead.size());
	// Passing something: it doesn't count while we're out round it.
	Node3D *pn = node_of(pass_node);
	if (pn != nullptr) {
		bool still = false;
		for (const Ahead &x : ahead) {
			if (ru->list[x.user]->node == pass_node) {
				still = true;
			}
		}
		Vector3 pp3 = pn->get_global_position();
		Vector2 pp(pp3.x, pp3.z);
		if (dot(pp - me, fwd) < -(half_len * 2.0 + 4.0) || (!still && absf(lateral - pass_lat) > 1.0 && dot(pp - me, fwd) < -half_len * 2.0)) {
			end_pass();
		}
	}
	TcaRoadUsers::UserRef prev = lead_user;
	lead_user.reset();
	for (const Ahead &x : ahead) {
		const TcaRoadUsers::UserRef &u = ru->list[x.user];
		if (u->node == pass_node) {
			continue;
		}
		lead_user = u;
		lead_along = x.along;
		break;
	}
	// Cut off.
	if (lead_user && prev && lead_user->node != prev->node) {
		double gap = lead_along - along - half_len - lead_user->half_len;
		if (v > 4.0 && gap < (standstill_gap + v * headway) * 0.45 && UtilityFunctions::randf() < temper * 1.5) {
			hazard = names->cut_off;
			do_honk(0.6);
		}
	}
	// Something new and dangerous: note when it was first seen.
	const String *now = &names->empty;
	if (oncoming) {
		now = &names->oncoming;
	} else if (p_at < INFINITY) {
		now = &names->person;
	} else if (siren) {
		now = &names->siren;
	}
	if (*now != hazard_seen) {
		hazard_seen = *now;
		hazard_t = time;
		if (!now->is_empty()) {
			hazard = *now;
		}
	}
	if (oncoming && time - hazard_t > reaction) {
		swerve_until = time + 2.0;
	}
	person_at = p_at;
	tailed = tailed_now;
	close_behind = behind_close;
	if (p_at < INFINITY && time - hazard_t > 1.0 + reaction && v < 2.0 && UtilityFunctions::randf() < 0.5 + temper * 0.5) {
		do_honk(0.5);
	}
	if (siren && tailed_now && siren_behind_d > 30.0 && siren_behind_d < INFINITY) {
		siren = false;
	}
	if (siren && time - siren_t > 3.0) {
		pull_overs += 1;
	}
	if (siren) {
		siren_t = time;
		siren_close = siren_close_now;
	}
	check_pass(along, v, me, fwd);
	check_junctions(along, v, siren);
	turn_lanes(along);
}

void TcaCivil::end_pass() {
	pass_node = 0;
	lat_target = 0.0;
}

void TcaCivil::check_pass(double along, double v, const Vector2 &me, const Vector2 &fwd) {
	if (node_of(pass_node) != nullptr) {
		return;
	}
	TcaRoadUsers *ru = TcaRoadUsers::singleton;
	const TcaRoadUsers::UserRef u = lead_user;
	if (!u || u->speed > 0.8 || lead_waiting() || v > 3.0) {
		behind_stopped = 0.0;
		return;
	}
	double gap = lead_along - along - half_len - u->half_len;
	if (gap > 25.0) {
		behind_stopped = 0.0;
		return;
	}
	behind_stopped += scan_every;
	if (behind_stopped > patience * 0.4 && UtilityFunctions::randf() < temper * 0.15) {
		do_honk(0.7);
	}
	if (behind_stopped > patience) {
		want_reroute = true;
	}
	bool at_stop = false;
	if (u->civil.get_type() != Variant::NIL) {
		String r;
		at_stop = TcaRoadUsers::civil_holding(*u, &r) && r == names->bus_stop;
	}
	if (behind_stopped < (at_stop ? 1.0 : 1.5 + patience * 0.1)) {
		return;
	}
	if (is_follower) {
		pass_node = u->node;
		pass_lat = 0.0;
		passes += 1;
		behind_stopped = 0.0;
		return;
	}
	// Out round it: past its far side by a margin.
	Vector2 p = route->sample(lead_along);
	Vector2 dir = route->dir_at(lead_along);
	double lead_lat = dot(u->pos - p, Vector2(dir.y, -dir.x));
	double shift = lead_lat + u->half_wid + half_wid + 0.7;
	if (shift > 4.5) {
		return;
	}
	// The way out there has to be clear.
	double from = along - 6.0;
	double to = lead_along + u->half_len + 25.0;
	for (int32_t oi : users) {
		const TcaRoadUsers::User &o = *ru->list[oi];
		if (o.node == body_id || o.node == u->node) {
			continue;
		}
		if ((double)len2(o.pos - me) > 140.0 * 140.0) {
			continue;
		}
		double ao = route->project(o.pos, maxf(0.0, along - 10.0), 150.0);
		Vector2 po = route->sample(ao);
		Vector2 d2 = route->dir_at(ao);
		double lo = dot(o.pos - po, Vector2(d2.y, -d2.x));
		if (lo < 0.8 || lo > shift + 3.5) {
			continue;
		}
		bool coming = dot(o.vel, d2) < -0.5;
		if (ao > from && ao < to) {
			return;
		}
		if (coming && ao > along && ao < to + o.speed * 5.0) {
			return;
		}
	}
	// And no wall or pole there.
	PhysicsDirectSpaceState3D *space = body->get_world_3d()->get_direct_space_state();
	Vector2 left(fwd.y, -fwd.x);
	ray->set_collision_mask((uint32_t)SOLID);
	double y = (double)body->get_global_position().y + 0.7;
	Vector2 a2 = me + left * (float)shift;
	Vector2 b2 = route->sample(lead_along + u->half_len + 6.0) + left * (float)shift;
	ray->set_from(Vector3(a2.x, (float)y, a2.y));
	ray->set_to(Vector3(b2.x, (float)y, b2.y));
	if (!space->intersect_ray(ray).is_empty()) {
		return;
	}
	pass_node = u->node;
	pass_lat = shift;
	lat_target = shift;
	passes += 1;
	behind_stopped = 0.0;
}

void TcaCivil::turn_lanes(double along) {
	if (node_of(pass_node) != nullptr) {
		return;
	}
	lat_target = 0.0;
	for (const Junction &j : junctions) {
		double to_line = j.line - along;
		if (to_line < -2.0) {
			continue;
		}
		if (to_line > 70.0) {
			break;
		}
		if (j.e_oneway != 0 && j.e_lanes >= 2) {
			if (j.turn == LEFT) {
				lat_target = minf(j.e_half_width * 0.5, j.e_half_width - half_wid - 0.4);
			} else if (j.turn == RIGHT) {
				lat_target = -minf(j.e_half_width * 0.5, j.e_half_width - half_wid - 0.4);
			}
		} else if (j.e_oneway == 0 && j.e_lanes >= 4 && j.turn == RIGHT) {
			lat_target = -(j.e_half_width / maxf(1.0, (double)j.e_lanes / 2.0)) * 0.9;
		}
		break;
	}
}

// --- junctions -------------------------------------------------------------------

int64_t TcaCivil::lamp(const Junction &j) const {
	// TrafficSignal.lamp_for
	double t = clock + j.sig_offset;
	double half = GREEN_TIME + AMBER_TIME + ALL_RED_TIME;
	double local = std::fmod(t, half * 2.0) - half * (double)j.phase;
	if (local < 0.0 || local >= half) {
		return 0;
	}
	if (local < GREEN_TIME) {
		return 2;
	}
	if (local < GREEN_TIME + AMBER_TIME) {
		return 1;
	}
	return 0;
}

void TcaCivil::check_junctions(double along, double v, bool siren) {
	stop_at = INFINITY;
	stop_reason = names->empty;
	creep = false;
	tourist_cap = false;
	approach_cap = INFINITY;
	double look = maxf(60.0, v * v / (2.0 * comfort_brake) + 30.0);
	double front = along + half_len;
	int64_t checked = 0;
	for (size_t ji = 0; ji < junctions.size(); ji++) {
		Junction &j = junctions[ji];
		double line = j.line;
		if (front > j.exit) {
			continue;
		}
		double to_line = line - front;
		if (to_line > look || checked >= 2) {
			break;
		}
		checked += 1;
		if (tourist && to_line < 22.0 && to_line > -1.0) {
			tourist_cap = true;
		}
		if (to_line < -0.3) {
			if (!j.go) {
				j.go = true;
			}
			continue;
		}
		const String *stop = &names->empty;
		int64_t control = j.control;
		if (control == RULE_SIGNAL) {
			int64_t lp = lamp(j);
			if (lp == 0 && j.turn == RIGHT && j.stopped >= 0.9 && gap_clear(j, false)) {
				// right on red, after a full stop, when it's clear
			} else if (lp == 0) {
				stop = &names->red;
				if (j.turn == RIGHT && v < 0.4 && to_line < 3.5) {
					j.stopped = j.stopped + scan_every;
				}
			} else if (lp == 1 && to_line > v * v / (2.0 * 3.2) + 0.5 && !j.go) {
				stop = &names->amber;
			} else if (j.turn == LEFT && j.opposite && !gap_clear(j, true)) {
				stop = &names->yield;
			}
		} else if (control == RULE_STOP) {
			if (j.stopped < 0.9) {
				stop = &names->stop_sign;
				if (v < 0.4 && to_line < 3.5) {
					j.stopped = j.stopped + scan_every;
				}
			} else if (!gap_clear(j, false)) {
				stop = &names->yield;
			}
		} else if (control == RULE_YIELD) {
			if (to_line < 30.0) {
				approach_cap = minf(approach_cap, 4.0 + to_line * 0.35);
			}
			if (!gap_clear(j, false)) {
				stop = &names->yield;
			}
		} else {
			if (j.turn == LEFT && j.opposite && !gap_clear(j, true)) {
				stop = &names->yield;
			}
		}
		if (stop->is_empty() && !room_after(j, along)) {
			stop = &names->box;
		}
		if (stop->is_empty() && siren_crossing(j)) {
			stop = &names->siren;
			if (hazard != names->siren_crossing) {
				hazard = names->siren_crossing;
				if (UtilityFunctions::randf() < 0.3 + temper * 0.5) {
					do_honk(0.4);
				}
			}
		}
		if (!stop->is_empty() && siren && v < 1.5 && (stop == &names->red || stop == &names->amber || stop == &names->stop_sign || stop == &names->box)) {
			if (stop != &names->box && gap_clear(j, false, 1.5)) {
				creep = true;
				stop_at = line + 5.0;
				stop_reason = names->siren;
				return;
			}
		}
		if (!stop->is_empty()) {
			if (v < 0.5 && to_line < 40.0) {
				j.wait = j.wait + scan_every * (siren ? 3.0 : 1.0);
			}
			j.go = false;
			stop_at = line;
			stop_reason = *stop;
			stop_j = (int64_t)ji;
			return;
		}
		if (!j.go && to_line < 12.0) {
			j.go = true;
			if (control == RULE_STOP || control == RULE_YIELD || j.turn == LEFT) {
				Array claim;
				claim.push_back(body);
				claim.push_back(time + 3.5 + j.radius / maxf(v, 3.0));
				claims[j.nid_v] = claim;
			}
		}
	}
}

bool TcaCivil::gap_clear(Junction &j, bool oncoming_only, double need_scale) {
	TcaRoadUsers *ru = TcaRoadUsers::singleton;
	double waited = j.wait;
	const Variant claim = claims.get(j.nid_v, Variant());
	if (claim.get_type() != Variant::NIL && waited < 15.0) {
		const Array c = claim;
		const Variant who = c[0];
		if (who.get_validated_object() != nullptr && who.get_validated_object() != (Object *)body && double(c[1]) > time) {
			return false;
		}
	}
	double need = gap_time * need_scale;
	if (j.major) {
		need += 0.5;
	}
	if (oncoming_only) {
		need *= 0.85;
	}
	need *= lerpf(1.0, 0.5, clampf(waited / patience, 0.0, 1.0));
	if (waited > 12.0) {
		need = minf(need, 1.6);
	}
	if (waited > 15.0) {
		need = minf(need, 0.8);
	}
	const Vector2 np = j.np;
	const double r = j.radius;
	const Vector2 in_dir = j.in_dir;
	for (int32_t ui : users) {
		const TcaRoadUsers::User &u = *ru->list[ui];
		if (u.node == body_id) {
			continue;
		}
		Vector2 rel = u.pos - np;
		double d = len(rel);
		if (d > 110.0) {
			continue;
		}
		if (d > r * 0.6 && dot(rel, in_dir) > 0.75 * d) {
			continue;
		}
		if (u.person) {
			if (d < r) {
				return false;
			}
			continue;
		}
		double spd = len(u.vel);
		if (d < r + 1.0) {
			if (spd > 0.8 && dot(u.vel, -in_dir) < 0.7 * spd) {
				return false;
			}
			continue;
		}
		if (oncoming_only && dot(rel, -in_dir) < 0.6 * d) {
			continue;
		}
		double closing = -dot(u.vel, rel / (float)d);
		if (closing < 0.8) {
			continue;
		}
		if ((d - r) / closing < need) {
			return false;
		}
	}
	return true;
}

bool TcaCivil::siren_crossing(const Junction &j) const {
	TcaRoadUsers *ru = TcaRoadUsers::singleton;
	const Vector2 np = j.np;
	const Vector2 in_dir = j.in_dir;
	const double r = j.radius;
	for (int32_t ui : users) {
		const TcaRoadUsers::User &u = *ru->list[ui];
		if (!u.siren || u.node == body_id) {
			continue;
		}
		Vector2 rel = u.pos - np;
		double d = len(rel);
		if (d > 80.0) {
			continue;
		}
		if (d > r && dot(rel, in_dir) > 0.7 * d) {
			continue;
		}
		if (d < r + 2.0) {
			return true;
		}
		double closing = -dot(u.vel, rel / (float)d);
		if (closing > 3.0 && (d - r) / closing < 6.0) {
			return true;
		}
	}
	return false;
}

bool TcaCivil::room_after(const Junction &j, double along) const {
	if (!lead_user) {
		return true;
	}
	if (lead_along < j.line) {
		return true;
	}
	double back = lead_along - lead_user->half_len;
	if (back < j.exit + half_len * 2.0 + 1.0 && lead_user->speed < 2.0) {
		return false;
	}
	return true;
}

// --- for CivilDriving.debug_text and CivilParity ------------------------------------

Array TcaCivil::debug_info() const {
	Array a;
	a.push_back(stop_at < INFINITY ? stop_j : (int64_t)-1);
	Node3D *ln = lead_user ? node_of(lead_user->node) : nullptr;
	a.push_back(ln != nullptr ? Variant(ln) : Variant());
	return a;
}

Dictionary TcaCivil::get_state() const {
	Dictionary s;
	auto obj = [](uint64_t id) -> Variant {
		Object *o = id != 0 ? ObjectDB::get_instance(id) : nullptr;
		return o != nullptr ? Variant(o) : Variant();
	};
	s["lateral"] = lateral;
	s["holding"] = holding;
	s["reason"] = reason;
	s["honk"] = honk;
	s["stuck_time"] = stuck_time;
	s["want_reroute"] = want_reroute;
	s["leader"] = obj(leader);
	s["leader_gap"] = leader_gap;
	s["hazard"] = hazard;
	s["passes"] = passes;
	s["pull_overs"] = pull_overs;
	s["honks"] = honks;
	s["close_behind"] = close_behind;
	s["_curb_at"] = curb_at;
	s["_curb_room"] = curb_room_v;
	s["_time"] = time;
	s["_scan_t"] = scan_t;
	s["_lead_user"] = lead_user ? obj(lead_user->node) : Variant();
	s["_lead_along"] = lead_along;
	s["_stop_at"] = stop_at;
	s["_stop_reason"] = stop_reason;
	s["_stop_j"] = (stop_at < INFINITY && stop_j >= 0 && stop_j < (int64_t)junctions.size()) ? junctions[stop_j].nid : String();
	s["_creep"] = creep;
	s["_launch"] = launch;
	s["_siren_t"] = siren_t;
	s["_siren_close"] = siren_close;
	s["_tailed"] = tailed;
	s["_startle_next"] = startle_next;
	s["_hazard_t"] = hazard_t;
	s["_hazard_seen"] = hazard_seen;
	s["_swerve_until"] = swerve_until;
	s["_person_at"] = person_at;
	s["_hold_until"] = hold_until;
	s["_hold_reason"] = hold_reason;
	s["_hold_aside"] = hold_aside;
	s["_hold_aside_most"] = hold_aside_most;
	s["_honk_until"] = honk_until;
	s["_honk_next"] = honk_next;
	s["_lat_target"] = lat_target;
	s["_pass_node"] = obj(pass_node);
	s["_pass_lat"] = pass_lat;
	s["_behind_stopped"] = behind_stopped;
	s["_tourist_cap"] = tourist_cap;
	s["_speed_mul"] = speed_mul;
	s["_speed_mul_until"] = speed_mul_until;
	s["_approach_cap"] = approach_cap;
	PackedFloat64Array stopped, wait;
	Array go;
	for (const Junction &j : junctions) {
		stopped.push_back(j.stopped);
		wait.push_back(j.wait);
		go.push_back(j.go);
	}
	s["j_stopped"] = stopped;
	s["j_wait"] = wait;
	s["j_go"] = go;
	return s;
}

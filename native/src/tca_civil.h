#pragma once

#include "tca_road_users.h"
#include "tca_route.h"

#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

#include <vector>

namespace godot {

// A computer driver's road manners, each physics step: the native twin of
// CivilDriving.want_speed and everything it calls (_scan, _check_pass,
// _turn_lanes, _check_junctions, _gap_clear, _siren_crossing,
// _room_after, _lead_waiting, _steer_lateral, curb_room, _idm) in
// scripts/ai/civil_driving.gd, which it must match exactly (CivilParity).
// The CivilDriving keeps its settings and what others read of it (it
// hands them over when they change, and gets back what changed); what it
// remembers between steps is kept here. Its route (where the junctions and
// limits are: CivilDriving._prepare) comes from the CivilDriving.
class TcaCivil : public RefCounted {
	GDCLASS(TcaCivil, RefCounted)

public:
	// What others read (CivilDriving's own vars, kept in step with these).
	double lateral = 0.0;
	bool holding = false;
	String reason;
	bool honk = false;
	double stuck_time = 0.0;
	bool want_reroute = false;
	uint64_t leader = 0;
	double leader_gap = INFINITY;
	String hazard;
	int64_t passes = 0, pull_overs = 0, honks = 0;
	bool close_behind = false;
	// Set from an order (react_hit...): hand it back even if it's as it was.
	bool hazard_dirty = false;

	static TcaCivil *of(uint64_t p_civil_id);

protected:
	static void _bind_methods();

private:
	struct Junction {
		String nid;
		Variant nid_v;
		double line, exit, radius, sig_offset;
		Vector2 in_dir, np;
		int64_t phase, control, turn;
		bool opposite, major;
		int64_t e_oneway, e_lanes;
		double e_half_width;
		double stopped = 0.0, wait = 0.0;
		bool go = false;
	};
	struct Ahead {
		double along;
		int32_t user;
		double lat;
	};

	Object *civil = nullptr; // the CivilDriving (it holds this)
	uint64_t civil_id = 0;
	uint64_t body_id = 0;
	Node3D *body = nullptr;
	Object *net = nullptr;
	bool is_follower = false;
	Dictionary claims; // CivilDriving._claims, shared
	Ref<PhysicsRayQueryParameters3D> ray;

	// Settings (CivilDriving's).
	double speed_factor = 0.94, headway = 1.4, standstill_gap = 2.4, max_accel = 1.6, comfort_brake = 2.6, reaction = 0.55;
	double patience = 14.0, temper = 0.35, gap_time = 4.5;
	bool tourist = false, pulls_over = true;
	double half_len = 2.3, half_wid = 0.9;
	double scan_every = 0.1, to_curb = -1.0, curb_keep = 0.0;

	// The route.
	Ref<TcaRoute> route;
	std::vector<Junction> junctions;
	std::vector<float> limit_end, limit_kmh, limit_room;

	// What it remembers.
	double curb_at = -INFINITY, curb_room_v = 0.0;
	double time = 0.0, scan_t = 0.0;
	TcaRoadUsers::UserRef lead_user;
	double lead_along = 0.0;
	double stop_at = INFINITY;
	String stop_reason;
	int64_t stop_j = -1;
	bool creep = false;
	double launch = 0.0;
	double siren_t = -100.0;
	bool siren_close = false;
	bool tailed = false;
	double startle_next = 0.0;
	double hazard_t = -100.0;
	String hazard_seen;
	double swerve_until = -100.0;
	double person_at = INFINITY;
	double hold_until = -100.0;
	String hold_reason;
	bool hold_aside = false;
	double hold_aside_most = INFINITY;
	double honk_until = -100.0, honk_next = 0.0;
	double lat_target = 0.0;
	uint64_t pass_node = 0;
	double pass_lat = 0.0;
	double behind_stopped = 0.0;
	bool tourist_cap = false;
	double speed_mul = 1.0, speed_mul_until = -100.0;
	double approach_cap = INFINITY;

	// What was last written to the CivilDriving's own vars.
	struct Shadow {
		double lateral = 0.0;
		bool holding = false;
		String reason;
		bool honk = false;
		double stuck_time = 0.0;
		bool want_reroute = false;
		uint64_t leader = 0;
		double leader_gap = INFINITY;
		String hazard;
		int64_t passes = 0, pull_overs = 0, honks = 0;
		bool close_behind = false;
		double speed_mul = 1.0;
		bool creep = false, tailed = false;
	} shadow;

	std::vector<int32_t> users; // the scan's (indices into TcaRoadUsers.list)
	std::vector<Ahead> ahead;

	void write_back();
	bool do_honk(double seconds);
	void do_startle(double seconds);
	void do_rush(double factor, double seconds);
	double idm(double v, double v0, double gap, double dv, double s0) const;
	bool lead_waiting() const;
	void steer_lateral(double along, double delta, double v);
	double room_right(double along) const;
	double curb_room_at(double along);
	int64_t limit_index(double along) const;
	double limit_at(double along) const;
	void scan(double along, double v);
	void end_pass();
	void check_pass(double along, double v, const Vector2 &me, const Vector2 &fwd);
	void turn_lanes(double along);
	void check_junctions(double along, double v, bool siren);
	bool gap_clear(Junction &j, bool oncoming_only, double need_scale = 1.0);
	bool siren_crossing(const Junction &j) const;
	bool room_after(const Junction &j, double along) const;
	int64_t lamp(const Junction &j) const;
	Node3D *node_of(uint64_t p_id) const;

	double clock = 0.0;

public:
	TcaCivil();
	~TcaCivil();
	// To a CivilDriving: its body, the street network, the junction claims
	// (CivilDriving._claims), the junction rules' values (`rules`:
	// [SIGNAL, STOP, YIELD]), the solid layer, whether the body is a
	// RoadFollower, and TrafficSignal's times ([GREEN, AMBER, ALL_RED]).
	void bind(Object *p_civil, Object *p_body, Object *p_net, const Dictionary &p_claims, const PackedInt64Array &p_rules, int64_t p_solid, bool p_follower, const PackedFloat64Array &p_signal_times);
	void set_settings(const PackedFloat64Array &p_s);
	void set_scan_t(double p_t) { scan_t = p_t; }
	// A new route: its line (or null), where each street ends along it and
	// its limit and room, and the junctions (16 numbers each: line, exit,
	// radius, in_dir x and y, phase, control, turn, opposite, major, the
	// signal clock's offset, the way in's oneway, lanes and half width, and
	// the node's x and z) with their nodes' ids.
	void set_route(const Ref<TcaRoute> &p_route, const PackedFloat32Array &p_end, const PackedFloat32Array &p_kmh, const PackedFloat32Array &p_room, const PackedFloat64Array &p_j, const PackedStringArray &p_nids);
	double step(double p_along, double p_v, double p_top, double p_delta, double p_clock, double p_scan_every, double p_to_curb, double p_curb_keep, bool p_want_reroute, const String &p_hazard);

	void hold_for(double p_seconds, const String &p_why, bool p_aside, double p_aside_most);
	bool hold_active() const;
	void release_hold();
	void rush(double p_factor, double p_seconds);
	void look(double p_factor, double p_seconds);
	void startle(double p_seconds);
	void react_crash(double p_seconds);
	void react_hit(double p_wait);
	bool honk_for(double p_seconds);
	double curb_room(double p_along, double p_curb_keep);
	// For debug_text: [the junction stopped for (index), or -1; the leader's node, or null]
	Array debug_info() const;
	// Everything, by CivilDriving's names (CivilParity).
	Dictionary get_state() const;
};

} // namespace godot

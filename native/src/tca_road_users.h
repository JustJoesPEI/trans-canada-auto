#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/scene_tree.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <memory>
#include <unordered_map>
#include <vector>

namespace godot {

class TcaCivil;

// The road users every computer driver watches (cars, the followers far
// off without physics, people on foot), gathered once per physics step:
// the native twin of RoadUsers.all and RoadUsers.near
// (scripts/ai/road_users.gd). One of them, shared (RoadUsers makes it).
// Entries are kept from one gathering to the next for the same node, as
// RoadUsers keeps its User objects: a driver's leader is the entry it saw,
// updated while its node is still about.
class TcaRoadUsers : public RefCounted {
	GDCLASS(TcaRoadUsers, RefCounted)

public:
	struct User {
		uint64_t node = 0; // instance id
		Vector2 pos, vel, fwd = Vector2(0, -1);
		double speed = 0.0, half_len = 2.3, half_wid = 0.9;
		bool person = false, siren = false;
		bool is_car = false; // a Car (not a follower or a person)
		Variant civil; // its CivilDriving, if any
		uint64_t civil_id = 0;
	};
	typedef std::shared_ptr<User> UserRef;

	static TcaRoadUsers *singleton;

	std::vector<UserRef> list;
	// Users near a point, as RoadUsers.near lists them (grid square by grid
	// square), into `out` (indices into `list`).
	void near(const Vector2 &p_p, double p_radius, std::vector<int32_t> &out) const;
	// Gathers them if this step's aren't gathered yet; returns the gathering's number.
	int64_t ensure(SceneTree *p_tree);
	// Whether a civil driver is holding, and why (its native twin's, or its own).
	static bool civil_holding(const User &u, String *r_reason);

protected:
	static void _bind_methods();

private:
	static constexpr double GRID = 64.0; // RoadUsers.GRID
	Ref<Script> car_script, follower_script, autopilot_script, density_script;
	int64_t siren_mode = 0;
	int64_t refresh_every_server = 2;
	StringName vehicles_group, follower_group, people_group;
	int64_t frame = -1;
	int64_t generation = 0;
	std::unordered_map<uint64_t, UserRef> by_node;
	std::unordered_map<int64_t, std::vector<int32_t>> grid;
	std::vector<int64_t> used_cells;
	// What each node is (worked out once per node): 1 Car, 2 RoadFollower, 3 CarAutopilot, 0 none.
	std::unordered_map<uint64_t, int> kind_of;

	int kind(Object *p_obj, uint64_t p_id);
	static bool inherits(Object *p_obj, const Ref<Script> &p_script);
	UserRef entry(const std::unordered_map<uint64_t, UserRef> &p_old, uint64_t p_id);
	void add(const UserRef &p_u);
	static int64_t cell_key(int64_t x, int64_t z) { return (x << 32) ^ (z & 0xffffffff); }

public:
	TcaRoadUsers();
	~TcaRoadUsers();
	// The scripts it tells cars and followers by, PoliceGear.Mode.SIREN, the
	// groups, and RoadUsers.SERVER_REFRESH_EVERY.
	void setup(const Ref<Script> &p_car, const Ref<Script> &p_follower, const Ref<Script> &p_autopilot, const Ref<Script> &p_density,
			int64_t p_siren_mode, const StringName &p_vehicles, const StringName &p_followers, const StringName &p_people, int64_t p_refresh_server);
	int64_t ensure_gd(Object *p_tree);
	// Gathers them now, whatever the step (CivilParity, alongside RoadUsers' own).
	int64_t gather(Object *p_tree);
	int64_t count() const { return (int64_t)list.size(); }
	// [node, pos, vel, fwd, speed, half_len, half_wid, person, siren, civil]
	Array user(int64_t p_i) const;
	PackedInt32Array near_indices(const Vector2 &p_p, double p_radius) const;
	int64_t index_of(Object *p_node) const;
};

} // namespace godot

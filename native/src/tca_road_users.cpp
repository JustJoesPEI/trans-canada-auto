#include "tca_road_users.h"

#include "tca_civil.h"
#include "tca_math.h"

#include <cmath>

#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;
using namespace tca;

namespace {
struct Names {
	StringName plane_velocity, speed, shape, police, mode, ai_controls, civil, velocity, half_length, half_width, vehicle, server, holding, reason;
	Variant length, width;
	Names() :
			plane_velocity("plane_velocity"), speed("speed"), shape("shape"), police("police"), mode("mode"), ai_controls("ai_controls"),
			civil("civil"), velocity("velocity"), half_length("half_length"), half_width("half_width"), vehicle("vehicle"), server("server"),
			holding("holding"), reason("reason"), length(String("length")), width(String("width")) {}
};
Names *names = nullptr;
} // namespace

TcaRoadUsers *TcaRoadUsers::singleton = nullptr;

TcaRoadUsers::TcaRoadUsers() {
	if (names == nullptr) {
		names = memnew(Names);
	}
	singleton = this;
}

TcaRoadUsers::~TcaRoadUsers() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

void TcaRoadUsers::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "car", "follower", "autopilot", "density", "siren_mode", "vehicles", "followers", "people", "refresh_server"), &TcaRoadUsers::setup);
	ClassDB::bind_method(D_METHOD("ensure", "tree"), &TcaRoadUsers::ensure_gd);
	ClassDB::bind_method(D_METHOD("gather", "tree"), &TcaRoadUsers::gather);
	ClassDB::bind_method(D_METHOD("count"), &TcaRoadUsers::count);
	ClassDB::bind_method(D_METHOD("user", "i"), &TcaRoadUsers::user);
	ClassDB::bind_method(D_METHOD("near_indices", "p", "radius"), &TcaRoadUsers::near_indices);
	ClassDB::bind_method(D_METHOD("index_of", "node"), &TcaRoadUsers::index_of);
}

void TcaRoadUsers::setup(const Ref<Script> &p_car, const Ref<Script> &p_follower, const Ref<Script> &p_autopilot, const Ref<Script> &p_density,
		int64_t p_siren_mode, const StringName &p_vehicles, const StringName &p_followers, const StringName &p_people, int64_t p_refresh_server) {
	car_script = p_car;
	follower_script = p_follower;
	autopilot_script = p_autopilot;
	density_script = p_density;
	siren_mode = p_siren_mode;
	vehicles_group = p_vehicles;
	follower_group = p_followers;
	people_group = p_people;
	refresh_every_server = p_refresh_server;
}

bool TcaRoadUsers::inherits(Object *p_obj, const Ref<Script> &p_script) {
	if (p_script.is_null()) {
		return false;
	}
	Ref<Script> s = p_obj->get_script();
	while (s.is_valid()) {
		if (s == p_script) {
			return true;
		}
		s = s->get_base_script();
	}
	return false;
}

int TcaRoadUsers::kind(Object *p_obj, uint64_t p_id) {
	auto it = kind_of.find(p_id);
	if (it != kind_of.end()) {
		return it->second;
	}
	int k = 0;
	if (inherits(p_obj, car_script)) {
		k = 1;
	} else if (inherits(p_obj, follower_script)) {
		k = 2;
	} else if (inherits(p_obj, autopilot_script)) {
		k = 3;
	}
	kind_of[p_id] = k;
	return k;
}

TcaRoadUsers::UserRef TcaRoadUsers::entry(const std::unordered_map<uint64_t, UserRef> &p_old, uint64_t p_id) {
	auto it = p_old.find(p_id);
	if (it != p_old.end()) {
		return it->second;
	}
	UserRef u = std::make_shared<User>();
	u->node = p_id;
	return u;
}

void TcaRoadUsers::add(const UserRef &p_u) {
	int32_t i = (int32_t)list.size();
	list.push_back(p_u);
	by_node[p_u->node] = p_u;
	int64_t key = cell_key((int64_t)std::floor((double)p_u->pos.x / GRID), (int64_t)std::floor((double)p_u->pos.y / GRID));
	std::vector<int32_t> &cell = grid[key];
	if (cell.empty()) {
		used_cells.push_back(key);
	}
	cell.push_back(i);
}

static inline Vector2 flat_fwd(Node3D *n) {
	Vector3 f3 = -n->get_global_basis().get_column(2);
	return nrm(Vector2(f3.x, f3.z));
}

int64_t TcaRoadUsers::ensure(SceneTree *p_tree) {
	int64_t f = (int64_t)Engine::get_singleton()->get_physics_frames();
	if (f >= frame) {
		if (f - frame < 1) {
			return generation;
		}
		if (f - frame < refresh_every_server && density_script.is_valid() && bool(density_script->get(names->server))) {
			return generation;
		}
	}
	frame = f;
	return gather(p_tree);
}

int64_t TcaRoadUsers::ensure_gd(Object *p_tree) {
	return ensure(Object::cast_to<SceneTree>(p_tree));
}

int64_t TcaRoadUsers::gather(Object *p_tree) {
	SceneTree *tree = Object::cast_to<SceneTree>(p_tree);
	frame = (int64_t)Engine::get_singleton()->get_physics_frames();
	generation++;
	list.clear();
	std::unordered_map<uint64_t, UserRef> old;
	old.swap(by_node);
	for (int64_t k : used_cells) {
		grid[k].clear();
	}
	used_cells.clear();
	if (tree == nullptr) {
		return generation;
	}
	// Cars.
	TypedArray<Node> vs = tree->get_nodes_in_group(vehicles_group);
	for (int64_t i = 0; i < vs.size(); i++) {
		Node3D *c = Object::cast_to<Node3D>((Object *)vs[i]);
		if (c == nullptr) {
			continue;
		}
		uint64_t id = c->get_instance_id();
		if (kind(c, id) != 1 || !c->is_inside_tree()) {
			continue;
		}
		UserRef u = entry(old, id);
		Vector3 p = c->get_global_position();
		u->pos = Vector2(p.x, p.z);
		u->vel = c->get(names->plane_velocity);
		u->fwd = flat_fwd(c);
		u->speed = c->get(names->speed);
		const Dictionary shape = c->get(names->shape);
		u->half_len = double(shape.get(names->length, 4.6)) * 0.5;
		u->half_wid = double(shape.get(names->width, 1.8)) * 0.5;
		u->is_car = true;
		u->siren = false;
		const Variant police = c->get(names->police);
		if (police.get_type() == Variant::OBJECT && police.get_validated_object() != nullptr) {
			u->siren = int64_t(((Object *)police)->get(names->mode)) == siren_mode;
		}
		u->civil = Variant();
		u->civil_id = 0;
		const Variant ap = c->get(names->ai_controls);
		if (ap.get_type() == Variant::OBJECT && ap.get_validated_object() != nullptr) {
			Object *apo = ap;
			if (kind(apo, apo->get_instance_id()) == 3) {
				u->civil = apo->get(names->civil);
				if (u->civil.get_type() == Variant::OBJECT) {
					u->civil_id = ((Object *)u->civil)->get_instance_id();
				} else {
					u->civil = Variant();
				}
			}
		}
		add(u);
	}
	// The followers, without physics.
	TypedArray<Node> fs = tree->get_nodes_in_group(follower_group);
	for (int64_t i = 0; i < fs.size(); i++) {
		Node3D *rf = Object::cast_to<Node3D>((Object *)fs[i]);
		if (rf == nullptr) {
			continue;
		}
		uint64_t id = rf->get_instance_id();
		if (kind(rf, id) != 2 || !rf->is_inside_tree()) {
			continue;
		}
		UserRef u = entry(old, id);
		Vector3 p = rf->get_global_position();
		u->pos = Vector2(p.x, p.z);
		Vector3 v = rf->get(names->velocity);
		u->vel = Vector2(v.x, v.z);
		u->fwd = flat_fwd(rf);
		u->speed = rf->get(names->speed);
		u->is_car = false;
		u->half_len = rf->get(names->half_length);
		u->half_wid = rf->get(names->half_width);
		u->civil = rf->get(names->civil);
		u->civil_id = 0;
		if (u->civil.get_type() == Variant::OBJECT) {
			u->civil_id = ((Object *)u->civil)->get_instance_id();
		} else {
			u->civil = Variant();
		}
		add(u);
	}
	// People on foot.
	TypedArray<Node> ps = tree->get_nodes_in_group(people_group);
	for (int64_t i = 0; i < ps.size(); i++) {
		Node3D *b = Object::cast_to<Node3D>((Object *)ps[i]);
		if (b == nullptr || !b->is_inside_tree() || !b->is_visible_in_tree()) {
			continue;
		}
		const Variant veh = b->get(names->vehicle);
		if (veh.get_type() == Variant::OBJECT ? veh.get_validated_object() != nullptr : veh.get_type() != Variant::NIL) {
			continue;
		}
		UserRef u = entry(old, b->get_instance_id());
		Vector3 p = b->get_global_position();
		u->pos = Vector2(p.x, p.z);
		Vector3 v;
		CharacterBody3D *cb = Object::cast_to<CharacterBody3D>(b);
		if (cb != nullptr) {
			v = cb->get_velocity();
		} else {
			const Variant bv = b->get(names->velocity);
			if (bv.get_type() == Variant::VECTOR3) {
				v = bv;
			}
		}
		u->vel = Vector2(v.x, v.z);
		u->fwd = flat_fwd(b);
		u->speed = len(u->vel);
		u->half_len = 0.35;
		u->half_wid = 0.35;
		u->person = true;
		u->is_car = false;
		add(u);
	}
	return generation;
}

void TcaRoadUsers::near(const Vector2 &p_p, double p_radius, std::vector<int32_t> &out) const {
	out.clear();
	int64_t lox = (int64_t)std::floor(((double)p_p.x - p_radius) / GRID);
	int64_t loz = (int64_t)std::floor(((double)p_p.y - p_radius) / GRID);
	int64_t hix = (int64_t)std::floor(((double)p_p.x + p_radius) / GRID);
	int64_t hiz = (int64_t)std::floor(((double)p_p.y + p_radius) / GRID);
	for (int64_t x = lox; x < hix + 1; x++) {
		for (int64_t z = loz; z < hiz + 1; z++) {
			auto it = grid.find(cell_key(x, z));
			if (it != grid.end()) {
				out.insert(out.end(), it->second.begin(), it->second.end());
			}
		}
	}
}

bool TcaRoadUsers::civil_holding(const User &u, String *r_reason) {
	TcaCivil *c = TcaCivil::of(u.civil_id);
	if (c != nullptr) {
		if (r_reason != nullptr) {
			*r_reason = c->reason;
		}
		return c->holding;
	}
	Object *o = u.civil;
	if (r_reason != nullptr) {
		*r_reason = o->get(names->reason);
	}
	return o->get(names->holding);
}

Array TcaRoadUsers::user(int64_t p_i) const {
	Array a;
	if (p_i < 0 || p_i >= (int64_t)list.size()) {
		return a;
	}
	const User &u = *list[p_i];
	a.push_back(ObjectDB::get_instance(u.node));
	a.push_back(u.pos);
	a.push_back(u.vel);
	a.push_back(u.fwd);
	a.push_back(u.speed);
	a.push_back(u.half_len);
	a.push_back(u.half_wid);
	a.push_back(u.person);
	a.push_back(u.siren);
	a.push_back(u.civil);
	return a;
}

PackedInt32Array TcaRoadUsers::near_indices(const Vector2 &p_p, double p_radius) const {
	std::vector<int32_t> out;
	near(p_p, p_radius, out);
	PackedInt32Array r;
	r.resize((int64_t)out.size());
	for (size_t i = 0; i < out.size(); i++) {
		r[(int64_t)i] = out[i];
	}
	return r;
}

int64_t TcaRoadUsers::index_of(Object *p_node) const {
	if (p_node == nullptr) {
		return -1;
	}
	uint64_t id = p_node->get_instance_id();
	for (size_t i = 0; i < list.size(); i++) {
		if (list[i]->node == id) {
			return (int64_t)i;
		}
	}
	return -1;
}

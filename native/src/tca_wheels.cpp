#include "tca_wheels.h"

#include <godot_cpp/classes/collision_object3d.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

void TcaWheels::_bind_methods() {
	ClassDB::bind_static_method("TcaWheels", D_METHOD("probe", "space", "ray", "xf", "mounts", "half_treads", "reach", "skip", "ground_layer"), &TcaWheels::probe);
}

Array TcaWheels::probe(PhysicsDirectSpaceState3D *p_space, const Ref<PhysicsRayQueryParameters3D> &p_ray, const Transform3D &p_xf,
		const PackedVector3Array &p_mounts, const PackedFloat64Array &p_half_treads, const PackedFloat64Array &p_reach,
		const PackedByteArray &p_skip, int64_t p_ground_layer) {
	Array out;
	const int64_t n = p_mounts.size();
	out.resize(n);
	if (p_space == nullptr || p_ray.is_null()) {
		return out;
	}
	static const StringName s_position("position");
	static const StringName s_normal("normal");
	static const StringName s_collider("collider");
	const Vector3 up = p_xf.basis.get_column(1);
	const Vector3 side = p_xf.basis.get_column(0);
	for (int64_t i = 0; i < n; i++) {
		if (i < p_skip.size() && p_skip[i] != 0) {
			continue;
		}
		const Vector3 from = p_xf.xform(p_mounts[i]);
		const double ht = p_half_treads[i];
		const double reach = p_reach[i];
		const double across[3] = { 0.0, -ht, ht };
		Dictionary best;
		double top = -INFINITY;
		for (int k = 0; k < 3; k++) {
			const Vector3 f0 = from + side * across[k];
			p_ray->set_from(f0);
			p_ray->set_to(f0 - up * reach);
			Dictionary h = p_space->intersect_ray(p_ray);
			if (h.is_empty()) {
				continue;
			}
			// Standing on another vehicle only counts on something like a floor.
			Object *col = h[s_collider];
			CollisionObject3D *co = Object::cast_to<CollisionObject3D>(col);
			const Vector3 nrm = h[s_normal];
			if (co != nullptr && (co->get_collision_layer() & p_ground_layer) == 0 && nrm.y < 0.5) {
				continue;
			}
			const Vector3 pos = h[s_position];
			const double y = double(pos.y) - (across[k] == 0.0 ? 0.0 : 0.03);
			if (y > top) {
				top = y;
				best = h;
			}
		}
		if (!best.is_empty()) {
			out[i] = best;
		}
	}
	return out;
}

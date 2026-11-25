#pragma once

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>

namespace godot {

// A car's wheels (Car in scripts/vehicles/car.gd).
class TcaWheels : public RefCounted {
	GDCLASS(TcaWheels, RefCounted)

protected:
	static void _bind_methods();

public:
	// The road under each wheel: for wheel i, rays down from the mount
	// (xf * mounts[i]) at the middle and both edges of the tread, reach[i]
	// long; the highest hit (an edge counting 3 cm lower), not counting a
	// steep face of something that isn't ground (another vehicle's side).
	// Skipped wheels (skip[i] != 0) get null. Matches the springs loop in
	// Car._suspension_and_tyres.
	static Array probe(PhysicsDirectSpaceState3D *p_space, const Ref<PhysicsRayQueryParameters3D> &p_ray, const Transform3D &p_xf,
			const PackedVector3Array &p_mounts, const PackedFloat64Array &p_half_treads, const PackedFloat64Array &p_reach,
			const PackedByteArray &p_skip, int64_t p_ground_layer);
};

} // namespace godot

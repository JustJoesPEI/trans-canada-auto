#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

// Traffic's far cars moved along their routes, all in one call: the
// native twin of TrafficManager._advance_follower and place_follower
// (scripts/traffic/traffic_manager.gd), RoadFollower._physics_process for
// a follower moved by its owner. Each follower keeps its own state in its
// vars (route, along, speed, velocity, moving, ...), as the GDScript twin
// leaves them, for everyone else that reads them (RoadUsers, the civil
// drivers, TrafficManager).
class TcaFollowers : public RefCounted {
	GDCLASS(TcaFollowers, RefCounted)

protected:
	static void _bind_methods();

public:
	static constexpr double STEP = 2.0; // StreetRoute.STEP
	static constexpr double TURN_EASE = 2.5; // RoadFollower.TURN_EASE

	TcaFollowers();
	// Moves each of `followers` (valid RoadFollowers) on one step of `delta`,
	// on `terrain`'s ground (the Terrain they all share). Returns the
	// indices of those that arrived this step, for their owner to say so
	// (their `arrived` signal), in order.
	PackedInt32Array step(const Array &p_followers, double p_delta, Object *p_terrain);

private:
	// The ground (Terrain.height_at), read once a call.
	PackedByteArray cm;
	Vector2 origin;
	double spacing = 2.0;
	int64_t nx = 0, nz = 0;
	bool read_ground(Object *p_terrain);
	double height_at(double x, double z) const;
};

} // namespace godot

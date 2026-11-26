# Native library

The hottest parts of the car physics and the computer drivers in C++ (a
GDExtension), so a server can run traffic and 48 players' cars. Each
native function has a GDScript twin it must match exactly; the game uses
the native one when the library is loaded and the GDScript one otherwise
(an editor without the library).

    native/build.sh

builds `native/bin/` for Linux and Windows (needs `scons` and, for Windows
from Linux, `mingw-w64`). Then

    godot --headless --fixed-fps 60 --path . --script res://tools/native_check.gd

compares every native function with its twin in the real town and times
both.

| Native | GDScript twin | What |
|---|---|---|
| `TcaWheels.probe` | `WheelProbe.probe_gd` | the road under each wheel |
| `TcaCar.step` | `Car._springs_and_tyres_gd` | springs, engine, brakes, soft ground, tyres |
| `TcaCivil.step` | `CivilDriving._want_speed_gd` (with `_scan`, `_check_pass`, `_turn_lanes`, `_check_junctions`, `_gap_clear`, `_siren_crossing`, `_room_after`, `_lead_waiting`, `_steer_lateral`, `_curb_room_gd`, `_idm`) | a civil driver's speed and lane each step: following, lights and signs, giving way, passing, sirens, hazards |
| `TcaCivil` orders (`hold_for`, `rush`, `startle`, `react_crash`, `react_hit`, `honk_for`, `curb_room`) | the same on `CivilDriving` (`_startle_gd`, `_rush_gd`, `_honk_gd`, `_curb_room_gd`) | what others tell a driver between steps |
| `TcaRoadUsers.gather`, `near` | `RoadUsers._all_gd`, `near` | the cars, followers and people every driver watches |
| `TcaRoute.project`, `sample`, `dir_at`, `limit_at`, `off_line` | `StreetRoute.project`, `sample`, `dir_at`, `limit_at`, `off_line` | where along a route a point is, and the route there |
| `TcaRoute.corner_speed` | `CarAutopilot._corner_speed` | how fast to go now to slow for the corners ahead |
| `TcaPilot.drive_at` | `CarAutopilot._drive_at_gd` (with `_avoid`, `_ground_ahead`, `_off_street`, `_lock_at`, `_pedals`, `_civil_pedals`, `_hold_stop_pedals`) | the steering and pedals toward a point, the rays ahead |
| `TcaPilot.way_clear` | `CarAutopilot._way_clear_gd` | a car-wide sweep to a point |
| `TcaFollowers.step` | `TrafficManager._move_followers_gd` (with `_advance_follower`, `place_follower`, `Terrain.height_at`) | the far traffic moved along its routes without physics, all of a batch in one call |

`TcaCar` must give exactly what the GDScript gives, bit for bit:
`native_check.gd` runs both on every traffic car every step from the same
state (`CarParity`) and compares every force and value; `-- --car-parity`
does the same in any other tool, and `-- --no-native` runs the GDScript
alone. A change to the car physics goes in both, then `native_check.gd`.

The computer drivers are checked the same way (`CivilParity`, on with
`CarParity`): each civil driver's step runs both twins from the same state
(everything others can see put back between them: the vars others read,
the junction claims, the honk count, the random numbers), and everything
both leave is compared, down to each junction's waiting time; the road
users are gathered both ways at the same moment and compared user by user;
the autopilot's route queries and its steering and pedals are worked out
both ways. A change to how computer drivers drive goes in both, then
`native_check.gd`.

The far traffic is checked the same way too (`FollowerParity`, on with
`CarParity`): each batch of followers is moved the GDScript way, put
back, moved natively, and the two compared exactly (transform, along,
speed, velocity, moving, arrival). TrafficManager queues the followers it
moves and hands them over in a batch just before the next driver looks
round (a civil tick), so everything happens in the same order as moving
each in its turn: a driver reads the car ahead where it really is.

How the twins share their state. A `CivilDriving` keeps its settings and
what others read of it (`holding`, `reason`, `hazard`, `lateral`, ...) in
its own vars; its native `TcaCivil` keeps what it remembers between steps.
The settings go over when they change, the vars others can set (`hazard`,
`want_reroute`, `scan_every`, `to_curb`, `curb_keep`) go with each step,
and the native one sets back only what changed. The orders (`hold_for`,
`react_hit`, ...) go to both. Inside the GDScript twin, the orders it gives
itself call the `_gd` versions, so running it never touches the native
one. `CarAutopilot._drive_at` works the same way: both twins only work out
the controls; what's left to do after (plan again, a K-turn, back out) the
autopilot does itself.

Writing a twin: GDScript's `float` is a 64-bit double and `Vector2` and
`Vector3` are 32-bit floats; a double meeting a vector (`v * x`, `v / x`)
is made a float first, and a float out of a vector (`dot`, `length`) is
widened to a double. `tca_math.h` has GDScript's helpers exactly (`signf`,
`move_toward`, ...), the engine's `Vector2` maths (godot-cpp's differs for
vectors that aren't finite), and `Array.sort_custom`'s sort (so equal
keys come out in the same order). `PackedFloat32Array` values are floats.
Keep names (`StringName`, `Dictionary` keys) made once, in a heap struct,
not function-local statics; read settings once at bind; and keep
property gets and sets by name to the few that must cross over.

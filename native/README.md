# Native library

The hottest parts of the car physics in C++ (a GDExtension), so a server
can run traffic and 48 players' cars. Each native function has a GDScript
twin it must match exactly; the game uses the native one when the library
is loaded and the GDScript one otherwise (an editor without the library).

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

`TcaCar` must give exactly what the GDScript gives, bit for bit:
`native_check.gd` runs both on every traffic car every step from the same
state (`CarParity`) and compares every force and value; `-- --car-parity`
does the same in any other tool, and `-- --no-native` runs the GDScript
alone. A change to the car physics goes in both, then `native_check.gd`.

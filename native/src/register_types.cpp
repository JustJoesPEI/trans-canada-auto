// The game's native library: the hot loops of the car physics and the
// computer drivers, in C++.
// Every class here has a GDScript twin it must match (native/README.md):
// the game uses the native one when the library is loaded, and the
// GDScript one otherwise (the web build, an editor without the library).

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "tca_car.h"
#include "tca_civil.h"
#include "tca_pilot.h"
#include "tca_road_users.h"
#include "tca_route.h"
#include "tca_wheels.h"

using namespace godot;

static void initialize(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(TcaWheels);
	GDREGISTER_CLASS(TcaCar);
	GDREGISTER_CLASS(TcaRoute);
	GDREGISTER_CLASS(TcaRoadUsers);
	GDREGISTER_CLASS(TcaCivil);
	GDREGISTER_CLASS(TcaPilot);
}

static void uninitialize(ModuleInitializationLevel p_level) {
}

extern "C" {
GDExtensionBool GDE_EXPORT tca_native_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize);
	init_obj.register_terminator(uninitialize);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}

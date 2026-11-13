#include "juce_engine.h"
#include <godot_cpp/godot.hpp>
using namespace godot;
void initialize_bridge(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<JuceEngine>();
}
void uninitialize_bridge(ModuleInitializationLevel) {}
extern "C" {
GDExtensionBool GDE_EXPORT juce_bridge_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_bridge);
    init.register_terminator(uninitialize_bridge);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}

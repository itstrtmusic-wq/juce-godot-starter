#include "juce_engine.h"
#include <godot_cpp/godot.hpp>
using namespace godot;
void register_juce_api();
namespace {
// One JUCE runtime per loaded extension, initialized on Godot's main thread.
std::unique_ptr<juce::ScopedJuceInitialiser_GUI> juce_runtime;
}
void initialize_bridge(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        juce_runtime = std::make_unique<juce::ScopedJuceInitialiser_GUI>();
        ClassDB::register_class<JuceEngine>();
        register_juce_api();
    }
}
void uninitialize_bridge(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) juce_runtime.reset();
}
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

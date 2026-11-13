cmake_minimum_required(VERSION 3.22)
project(juce_godot_bridge VERSION 0.2.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(FetchContent)
# A 4.5 baseline uses Godot's forward-compatible GDExtension ABI.
# Compatibility with later versions must still be checked in the target editor.
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/build_profile.json" CACHE PATH "")
set(GODOTCPP_DISABLE_EXCEPTIONS OFF CACHE BOOL "JUCE headers require exceptions" FORCE)
set(GODOTCPP_USE_HOT_RELOAD OFF CACHE BOOL "" FORCE)
FetchContent_Declare(godot_cpp GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git GIT_TAG e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77 GIT_SHALLOW FALSE)
FetchContent_MakeAvailable(godot_cpp)
# Compile only the JUCE modules needed by this bridge. No JUCE UI or juceaide.
FetchContent_Declare(juce GIT_REPOSITORY https://github.com/juce-framework/JUCE.git GIT_TAG f72bad64d29715216226685810c5196bd0d79d77 GIT_SHALLOW FALSE SOURCE_SUBDIR unused)
FetchContent_MakeAvailable(juce)
option(BRIDGE_NO_AUDIO_DEVICE "Disable Linux audio backends for headless CI only" OFF)
add_library(bridge_juce STATIC
    ${juce_SOURCE_DIR}/modules/juce_core/juce_core.cpp
    ${juce_SOURCE_DIR}/modules/juce_core/juce_core_CompilationTime.cpp
    ${juce_SOURCE_DIR}/modules/juce_events/juce_events.cpp
    ${juce_SOURCE_DIR}/modules/juce_audio_basics/juce_audio_basics.cpp
    ${juce_SOURCE_DIR}/modules/juce_audio_devices/juce_audio_devices.cpp
    ${juce_SOURCE_DIR}/modules/juce_audio_formats/juce_audio_formats.cpp
    ${juce_SOURCE_DIR}/modules/juce_dsp/juce_dsp.cpp)
target_include_directories(bridge_juce PUBLIC ${juce_SOURCE_DIR}/modules)
target_compile_definitions(bridge_juce PUBLIC JUCE_GLOBAL_MODULE_SETTINGS_INCLUDED=1 JUCE_STANDALONE_APPLICATION=0 JUCE_WEB_BROWSER=0 JUCE_USE_CURL=0 JUCE_MODAL_LOOPS_PERMITTED=0 JUCE_USE_WINDOWS_MEDIA_FORMAT=0)
if(WIN32)
    target_link_libraries(bridge_juce PUBLIC winmm ole32 oleaut32 uuid ws2_32 version advapi32 shlwapi)
elseif(UNIX AND NOT APPLE)
    target_link_libraries(bridge_juce PUBLIC pthread dl rt)
    if(BRIDGE_NO_AUDIO_DEVICE)
        target_compile_definitions(bridge_juce PUBLIC JUCE_ALSA=0 JUCE_JACK=0)
    else()
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(ALSA REQUIRED IMPORTED_TARGET alsa)
        target_link_libraries(bridge_juce PUBLIC PkgConfig::ALSA)
    endif()
else()
    message(FATAL_ERROR "This starter targets Windows and Linux validation only")
endif()
add_library(juce_bridge SHARED src/juce_engine.cpp src/register_types.cpp src/juce_api.cpp src/dsp_graph.cpp src/juce_dsp_network.cpp src/generated_bindings.cpp)
target_link_libraries(juce_bridge PRIVATE godot-cpp bridge_juce)
set_target_properties(juce_bridge PROPERTIES PREFIX "" OUTPUT_NAME "juce_bridge"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/demo/addons/juce_bridge/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/demo/addons/juce_bridge/bin")
foreach(config DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set_target_properties(juce_bridge PROPERTIES RUNTIME_OUTPUT_DIRECTORY_${config} "${CMAKE_CURRENT_SOURCE_DIR}/demo/addons/juce_bridge/bin" LIBRARY_OUTPUT_DIRECTORY_${config} "${CMAKE_CURRENT_SOURCE_DIR}/demo/addons/juce_bridge/bin")
endforeach()
enable_testing()
add_executable(tone_test tests/tone_test.cpp)
target_include_directories(tone_test PRIVATE src)
target_link_libraries(tone_test PRIVATE bridge_juce)
add_test(NAME tone_test COMMAND tone_test)

add_executable(dsp_graph_test tests/dsp_graph_test.cpp src/dsp_graph.cpp)
target_include_directories(dsp_graph_test PRIVATE src)
target_link_libraries(dsp_graph_test PRIVATE bridge_juce)
add_test(NAME dsp_graph_test COMMAND dsp_graph_test)

find_package(Python3 COMPONENTS Interpreter REQUIRED)
add_test(NAME bindings_manifest_current COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/generate_bindings.py" --check)

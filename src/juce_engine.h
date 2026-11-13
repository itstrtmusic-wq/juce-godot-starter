#pragma once
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <juce_audio_devices/juce_audio_devices.h>
#include <atomic>
#include "tone.h"

namespace godot {
class JuceEngine : public Node, private juce::AudioIODeviceCallback {
    GDCLASS(JuceEngine, Node)
    // Destruction order keeps JUCE alive until after device shutdown.
    juce::ScopedJuceInitialiser_GUI juce_runtime;
    juce::AudioDeviceManager devices;
    Tone tone;
    std::atomic<float> frequency{440.0f}, gain{0.05f}, peak{0.0f};
    std::atomic<bool> tone_enabled{false}, running{false};
    String last_error;
    void audioDeviceIOCallbackWithContext(const float* const*, int,
        float* const*, int, int, const juce::AudioIODeviceCallbackContext&) override;
    void audioDeviceAboutToStart(juce::AudioIODevice*) override;
    void audioDeviceStopped() override;
protected:
    static void _bind_methods();
public:
    JuceEngine() = default;
    ~JuceEngine() override;
    PackedStringArray get_output_devices();
    bool start_audio(const String& output_device = "", double sample_rate = 48000.0, int buffer_size = 256);
    void stop_audio();
    bool is_running() const;
    void set_frequency(float hz);
    void set_gain(float linear);
    void set_tone_enabled(bool enabled);
    float get_peak() const;
    String get_last_error() const;
    Dictionary get_device_info();
};
}

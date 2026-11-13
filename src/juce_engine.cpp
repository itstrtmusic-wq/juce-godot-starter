#include "juce_engine.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>

using namespace godot;
static_assert(std::atomic<float>::is_always_lock_free);
static_assert(std::atomic<bool>::is_always_lock_free);

void JuceEngine::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_output_devices"), &JuceEngine::get_output_devices);
    ClassDB::bind_method(D_METHOD("start_audio", "output_device", "sample_rate", "buffer_size"), &JuceEngine::start_audio, DEFVAL(""), DEFVAL(48000.0), DEFVAL(256));
    ClassDB::bind_method(D_METHOD("stop_audio"), &JuceEngine::stop_audio);
    ClassDB::bind_method(D_METHOD("is_running"), &JuceEngine::is_running);
    ClassDB::bind_method(D_METHOD("set_frequency", "hz"), &JuceEngine::set_frequency);
    ClassDB::bind_method(D_METHOD("set_gain", "linear"), &JuceEngine::set_gain);
    ClassDB::bind_method(D_METHOD("set_tone_enabled", "enabled"), &JuceEngine::set_tone_enabled);
    ClassDB::bind_method(D_METHOD("get_peak"), &JuceEngine::get_peak);
    ClassDB::bind_method(D_METHOD("get_last_error"), &JuceEngine::get_last_error);
    ClassDB::bind_method(D_METHOD("get_device_info"), &JuceEngine::get_device_info);
    ADD_SIGNAL(MethodInfo("audio_started"));
    ADD_SIGNAL(MethodInfo("audio_stopped"));
    ADD_SIGNAL(MethodInfo("audio_error", PropertyInfo(Variant::STRING, "message")));
}
JuceEngine::~JuceEngine() {
    devices.removeAudioCallback(this);
    devices.closeAudioDevice();
}
PackedStringArray JuceEngine::get_output_devices() {
    // Names from JUCE's default backend only; startup uses that same backend.
    const auto& types = devices.getAvailableDeviceTypes();
    PackedStringArray result;
    if (types.isEmpty()) return result;
    auto* type = types.getFirst();
    type->scanForDevices();
    for (const auto& name : type->getDeviceNames(false))
        result.append(String::utf8(name.toRawUTF8()));
    return result;
}
bool JuceEngine::start_audio(const String& output_device, double sample_rate, int buffer_size) {
    stop_audio();
    last_error = "";
    if (!std::isfinite(sample_rate) || sample_rate < 8000.0 || sample_rate > 384000.0 || buffer_size < 16 || buffer_size > 8192) {
        last_error = "Invalid sample rate or buffer size.";
    } else {
        juce::AudioDeviceManager::AudioDeviceSetup setup;
        setup.outputDeviceName = juce::String::fromUTF8(output_device.utf8().get_data());
        setup.sampleRate = sample_rate;
        setup.bufferSize = buffer_size;
        setup.useDefaultInputChannels = false;
        setup.useDefaultOutputChannels = true;
        auto error = devices.initialise(0, 2, nullptr, false, {}, &setup);
        if (error.isNotEmpty()) last_error = String::utf8(error.toRawUTF8());
        else if (devices.getCurrentAudioDevice() == nullptr) last_error = "No output audio device is available.";
    }
    if (!last_error.is_empty()) {
        devices.closeAudioDevice();
        emit_signal("audio_error", last_error);
        return false;
    }
    devices.addAudioCallback(this);
    emit_signal("audio_started");
    return true;
}
void JuceEngine::stop_audio() {
    const bool was_running = running.load();
    devices.removeAudioCallback(this);
    devices.closeAudioDevice();
    running.store(false);
    peak.store(0.0f);
    if (was_running) emit_signal("audio_stopped");
}
bool JuceEngine::is_running() const { return running.load(); }
void JuceEngine::set_frequency(float hz) { if (std::isfinite(hz)) frequency.store(std::clamp(hz, 20.0f, 20000.0f)); }
void JuceEngine::set_gain(float value) { if (std::isfinite(value)) gain.store(std::clamp(value, 0.0f, 1.0f)); }
void JuceEngine::set_tone_enabled(bool enabled) { tone_enabled.store(enabled); }
float JuceEngine::get_peak() const { return peak.load(); }
String JuceEngine::get_last_error() const { return last_error; }
Dictionary JuceEngine::get_device_info() {
    Dictionary result;
    if (auto* device = devices.getCurrentAudioDevice()) {
        result["name"] = String::utf8(device->getName().toRawUTF8());
        result["sample_rate"] = device->getCurrentSampleRate();
        result["buffer_size"] = device->getCurrentBufferSizeSamples();
        result["output_latency_samples"] = device->getOutputLatencyInSamples();
    }
    return result;
}
void JuceEngine::audioDeviceAboutToStart(juce::AudioIODevice* device) {
    tone.prepare(device->getCurrentSampleRate());
    running.store(true);
}
void JuceEngine::audioDeviceStopped() { running.store(false); peak.store(0.0f); }
void JuceEngine::audioDeviceIOCallbackWithContext(const float* const*, int,
    float* const* output, int channels, int samples, const juce::AudioIODeviceCallbackContext&) {
    // No Godot API calls, locks, allocations, or signals on the audio thread.
    peak.store(tone.render(output, channels, samples, frequency.load(), gain.load(), tone_enabled.load()));
}

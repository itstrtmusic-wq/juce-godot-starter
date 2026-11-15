#pragma once
#include "juce_api.h"
#include "dsp_graph.h"
#include "juce_midi_sequencer.h"
namespace godot {
class JuceDSPNetwork : public RefCounted {
    GDCLASS(JuceDSPNetwork, RefCounted)
protected: static void _bind_methods();
public:
    bridge::DSPGraph graph;
    PackedStringArray get_supported_node_types() const;
    bool add_node(const String& id, const String& type);
    bool remove_node(const String& id);
    bool connect_nodes(const String& source, const String& destination, float gain = 1.0f);
    bool disconnect_nodes(const String& source, const String& destination);
    PackedStringArray get_node_ids() const;
    Array get_nodes() const;
    Array get_connections() const;
    bool connect_parameter(const String& source, const String& destination, const String& parameter, float depth = 1.0f, float offset = 0.0f, int channel = 0);
    bool disconnect_parameter(const String& source, const String& destination, const String& parameter);
    Array get_modulation_connections() const;
    Dictionary get_effective_parameters(const String& id) const;
    Dictionary export_patch() const;
    bool load_patch(const Dictionary& patch);
    bool save_patch(const String& path, bool overwrite = false);
    bool load_patch_file(const String& path);
    bool set_parameter(const String& id, const String& parameter, float value);
    Dictionary get_parameters(const String& id) const;
    bool prepare(double sample_rate, int max_block_size = 512, int channels = 2);
    bool reset() { return graph.reset(); }
    bool process(const Ref<JuceAudioBuffer>& buffer) { return buffer.is_valid() && graph.process_offline(buffer->native()); }
    bool is_active() const { return graph.active.load(); }
    String get_last_error() const { return String::utf8(graph.last_error().c_str()); }
};
class JuceAudioDeviceManager : public RefCounted, private juce::AudioIODeviceCallback {
    GDCLASS(JuceAudioDeviceManager, RefCounted)
    juce::AudioDeviceManager devices;
    Ref<JuceDSPNetwork> network;
    Ref<JuceMidiSequencer> sequencer;
    Ref<JuceDSPNetwork> post_network;
    bool owns_post = false;
    std::atomic<bool> running{false};
    std::atomic<float> peak{0.0f};
    bool owns_graph = false;
    int channels = 2;
    String error;
    void audioDeviceIOCallbackWithContext(const float* const*,int,float* const*,int,int,const juce::AudioIODeviceCallbackContext&) override;
    void audioDeviceAboutToStart(juce::AudioIODevice*) override;
    void audioDeviceStopped() override { running.store(false); peak.store(0); }
    PackedStringArray device_names(bool input);
protected: static void _bind_methods();
public:
    ~JuceAudioDeviceManager() override { stop_audio(); }
    PackedStringArray get_output_devices() { return device_names(false); }
    PackedStringArray get_input_devices() { return device_names(true); }
    bool set_network(const Ref<JuceDSPNetwork>& value);
    bool set_sequencer(const Ref<JuceMidiSequencer>& value);
    bool set_post_network(const Ref<JuceDSPNetwork>& value);
    bool start_audio(const String& output_device = "", double sample_rate = 48000.0, int buffer_size = 256, const String& input_device = "", bool enable_input = false);
    void stop_audio();
    bool is_running() const { return running.load(); }
    float get_peak() const { return peak.load(); }
    Dictionary get_device_info();
    String get_last_error() const { return error; }
};
}

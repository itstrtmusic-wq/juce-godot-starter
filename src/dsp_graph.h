#pragma once
#include <juce_dsp/juce_dsp.h>
#include <atomic>
#include <memory>
#include <string>
#include <string_view>
#include <vector>
#include <array>

namespace bridge {
// This core knows nothing about Godot. Structural edits and prepare occur off the audio thread.
class DSPGraph {
public:
    struct Parameter { const char* name; float low, high; std::atomic<float> value, effective; Parameter(const char* n, float lo, float hi, float v) : name(n), low(lo), high(hi), value(v), effective(v) {} };
    struct Node;
    struct Edge { Node* source; float gain; };
    struct Modulation { Node* source; Parameter* target; float depth, offset; int channel; };
    struct Node {
        std::string id, type;
        std::vector<std::unique_ptr<Parameter>> parameters;
        std::vector<Edge> inputs;
        std::vector<Modulation> modulations;
        juce::AudioBuffer<float> buffer, delay;
        juce::SingleThreadedIIRFilter filters[2];
        juce::Reverb reverb;
        juce::ADSR envelope;
        juce::dsp::Compressor<float> compressor;
        juce::dsp::Chorus<float> chorus;
        juce::dsp::Phaser<float> phaser;
        juce::dsp::Limiter<float> limiter;
        juce::dsp::NoiseGate<float> noise_gate;
        bool old_gate = false;
        juce::SmoothedValue<float> gain;
        juce::dsp::Oscillator<float> oscillator;
        int delay_cursor = 0, waveform = 0;
        float old_frequency = -1, old_q = -1, old_gain = -1000;
        Node(const std::string& id, const std::string& type);
        Parameter* parameter(std::string_view name) const;
        float value(const char* name) const;
    };
private:
    std::vector<std::unique_ptr<Node>> nodes;
    std::vector<Node*> order;
    double rate = 48000.0;
    int max_block = 0, channels = 0;
    bool prepared = false;
    Node* output_node = nullptr;
    std::string error;
    bool build_order();
    void run_node(Node&, int samples) noexcept;
    bool fail(const char* message) { error = message; return false; }
public:
    std::atomic<bool> active{false};
    DSPGraph();
    static const std::vector<std::string>& supported_types();
    Node* find(const std::string& id) const;
    bool add_node(const std::string& id, const std::string& type);
    bool remove_node(const std::string& id);
    bool connect(const std::string& source, const std::string& destination, float gain);
    bool disconnect(const std::string& source, const std::string& destination);
    bool connect_parameter(const std::string& source, const std::string& destination, const std::string& parameter, float depth, float offset, int channel);
    bool disconnect_parameter(const std::string& source, const std::string& destination, const std::string& parameter);
    bool replace_with(DSPGraph& replacement);
    void clear_error() { error.clear(); }
    bool report_error(const std::string& message) { error = message; return false; }
    bool set_parameter(const std::string& id, const std::string& parameter, float value);
    std::vector<std::string> node_ids() const;
    bool prepare(double sample_rate, int max_block_size, int num_channels, bool report_error = true);
    bool reset();
    bool process_offline(juce::AudioBuffer<float>& buffer);
    // Pointers may alias; all input is copied before any output is written.
    bool render(const float* const* input, int input_channels, float* const* output, int output_channels, int samples) noexcept;
    const std::string& last_error() const { return error; }
};
}

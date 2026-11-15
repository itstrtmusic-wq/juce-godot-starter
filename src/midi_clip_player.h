#pragma once
#include <juce_audio_basics/juce_audio_basics.h>
#include <array>
#include <atomic>
#include <vector>
#include <string>

namespace bridge {
// One main-thread producer/consumer and one audio-thread consumer/producer.
template <typename T, size_t Capacity> class MidiQueue {
    std::array<T, Capacity> data{};
    std::atomic<size_t> write{0}, read{0};
public:
    bool push(const T& value) noexcept {
        const auto w = write.load(std::memory_order_relaxed), next = (w + 1) % Capacity;
        if (next == read.load(std::memory_order_acquire)) return false;
        data[w] = value; write.store(next, std::memory_order_release); return true;
    }
    bool pop(T& value) noexcept {
        const auto r = read.load(std::memory_order_relaxed);
        if (r == write.load(std::memory_order_acquire)) return false;
        value = data[r]; read.store((r + 1) % Capacity, std::memory_order_release); return true;
    }
    void clear() noexcept { read.store(0); write.store(0); } // Only with audio stopped.
};

class MidiClipPlayer {
public:
    struct Note { int note = 60, channel = 1; double start = 0, length = 1; float velocity = 0.8f; };
    struct Input { int type = 0, channel = 1, note = 0; float value = 0; }; // 1 on, 2 off, 3 CC
    struct Recorded { int note = 0, channel = 1; double start = 0, length = 0; float velocity = 0; };
    static constexpr int max_notes = 4096, voice_count = 32;
    std::atomic<bool> active{false};
    std::atomic<double> bpm{120.0}, published_beat{0}, published_elapsed{0};
    std::atomic<bool> requested_play{false}, recording{false}, looping{true}, metronome{false};
    std::atomic<bool> published_playing{false};
    std::atomic<float> volume_db{-9.0f};
    std::atomic<int> waveform{1};
    std::atomic<uint64_t> input_drops{0}, recording_drops{0}, rendered_samples{0};
private:
    struct Event { double beat; int id; bool on; };
    struct Voice {
        juce::ADSR envelope;
        int note = -1, channel = 1, clip_id = -1;
        bool held = false;
        double phase = 0, step = 0;
        float velocity = 0;
        uint64_t age = 0;
    };
    struct Held { double start = -1; float velocity = 0; };
    std::array<Voice, voice_count> voices;
    std::array<Held, 16 * 128> held_recording;
    std::array<bool, 16> pedal{};
    MidiQueue<Input, 1024> incoming;
    MidiQueue<Recorded, 4097> completed;
    std::vector<Note> notes;
    std::vector<Event> events;
    std::atomic<bool> stop_requested{false}, panic_requested{false};
    double rate = 48000, length = 16, beat = 0, elapsed = 0;
    int channels = 0, click_left = 0, last_tick = -1;
    double click_phase = 0, click_frequency = 1320;
    size_t cursor = 0;
    uint64_t age = 0;
    bool prepared = false, playing = false, capturing = false;
    std::string error;
    void reset_voices() noexcept;
    void release_clip() noexcept;
    void start_voice(int note, int channel, float velocity, int clip_id) noexcept;
    void handle_input(const Input&) noexcept;
    void finish_note(int channel, int note) noexcept;
    void finish_recording() noexcept;
    float synth_sample(int shape) noexcept;
public:
    bool load_clip(const std::vector<Note>& replacement, double length_beats);
    const std::vector<Note>& get_notes() const { return notes; }
    double get_length() const { return length; }
    bool prepare(double sample_rate, int num_channels, bool for_device = false);
    bool render(float* const* output, int num_channels, int samples) noexcept;
    bool is_prepared() const { return prepared; }
    int get_channels() const { return channels; }
    void play() { requested_play.store(true); }
    void stop() { requested_play.store(false); stop_requested.store(true); }
    void panic() { panic_requested.store(true); }
    void device_stopped(); // Called after the audio callback has been detached.
    bool queue_input(const Input& input);
    bool read_recorded(Recorded& note) { return completed.pop(note); }
    const std::string& last_error() const { return error; }
};
}

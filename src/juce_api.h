#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_audio_formats/juce_audio_formats.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <deque>

namespace godot {
juce::File juce_file_path(const String& path);
inline String gd_string(const juce::String& s) { return String::utf8(s.toRawUTF8()); }
inline bool valid_rate(double v) { return std::isfinite(v) && v >= 8000.0 && v <= 384000.0; }

class JUCE : public RefCounted {
    GDCLASS(JUCE, RefCounted)
protected: static void _bind_methods();
public:
    static String get_version() { return gd_string(juce::SystemStats::getJUCEVersion()); }
    static Dictionary get_api_manifest();
    static PackedStringArray get_supported_classes();
    static float decibels_to_gain(float db, float minus_infinity_db = -100.0f) { return juce::Decibels::decibelsToGain(db, minus_infinity_db); }
    static float gain_to_decibels(float gain, float minus_infinity_db = -100.0f) { return juce::Decibels::gainToDecibels(gain, minus_infinity_db); }
    static double midi_note_to_hz(int note, double a4_frequency = 440.0) { return juce::MidiMessage::getMidiNoteInHertz(note, a4_frequency); }
};

class JuceAudioBuffer : public RefCounted {
    GDCLASS(JuceAudioBuffer, RefCounted)
    juce::AudioBuffer<float> data;
protected: static void _bind_methods();
public:
    juce::AudioBuffer<float>& native() { return data; }
    const juce::AudioBuffer<float>& native() const { return data; }
    bool set_size(int channels, int samples, bool keep_existing = false);
    int get_num_channels() const { return data.getNumChannels(); }
    int get_num_samples() const { return data.getNumSamples(); }
    void clear() { data.clear(); }
    float get_sample(int ch, int sample) const { return ch >= 0 && ch < get_num_channels() && sample >= 0 && sample < get_num_samples() ? data.getSample(ch, sample) : 0.0f; }
    bool set_sample(int ch, int sample, float value);
    PackedFloat32Array get_channel(int channel) const;
    bool set_channel(int channel, const PackedFloat32Array& samples);
    void apply_gain(float gain) { if (std::isfinite(gain)) data.applyGain(gain); }
    void apply_gain_ramp(float start, float end) { if (std::isfinite(start) && std::isfinite(end)) data.applyGainRamp(0, get_num_samples(), start, end); }
    float get_rms_level(int channel) const { return channel >= 0 && channel < get_num_channels() ? data.getRMSLevel(channel, 0, get_num_samples()) : 0.0f; }
    float get_magnitude(int channel) const { return channel >= 0 && channel < get_num_channels() ? data.getMagnitude(channel, 0, get_num_samples()) : 0.0f; }
    bool copy_from(const Ref<JuceAudioBuffer>& source);
    bool add_from(const Ref<JuceAudioBuffer>& source, float gain = 1.0f);
    void reverse() { data.reverse(0, get_num_samples()); }
    Ref<JuceAudioBuffer> duplicate_buffer() const;
};

class JuceMidiMessage : public RefCounted {
    GDCLASS(JuceMidiMessage, RefCounted)
protected: static void _bind_methods();
public:
    juce::MidiMessage data;
    static Ref<JuceMidiMessage> wrap(const juce::MidiMessage& message);
    static Ref<JuceMidiMessage> note_on(int channel, int note, float velocity);
    static Ref<JuceMidiMessage> note_off(int channel, int note);
    static Ref<JuceMidiMessage> controller_event(int channel, int controller, int value);
    static Ref<JuceMidiMessage> pitch_wheel(int channel, int value);
    static Ref<JuceMidiMessage> program_change(int channel, int program);
    static Ref<JuceMidiMessage> tempo_event(int microseconds_per_quarter_note);
    static Ref<JuceMidiMessage> from_bytes(const PackedByteArray& bytes, double timestamp = 0.0);
    PackedByteArray get_raw_data() const;
    String get_description() const { return gd_string(data.getDescription()); }
    int get_channel() const { return data.getChannel(); }
    void set_channel(int channel) { if (channel >= 1 && channel <= 16 && data.getChannel() != 0) data.setChannel(channel); }
    int get_note_number() const { return data.isNoteOnOrOff() ? data.getNoteNumber() : -1; }
    void set_note_number(int note) { if (data.isNoteOnOrOff()) data.setNoteNumber(std::clamp(note, 0, 127)); }
    float get_velocity() const { return data.isNoteOnOrOff() ? data.getFloatVelocity() : 0.0f; }
    void set_velocity(float v) { if (data.isNoteOnOrOff() && std::isfinite(v)) data.setVelocity(std::clamp(v, 0.0f, 1.0f)); }
    double get_timestamp() const { return data.getTimeStamp(); }
    void set_timestamp(double t) { if (std::isfinite(t)) data.setTimeStamp(t); }
    bool is_note_on() const { return data.isNoteOn(); }
    bool is_note_off() const { return data.isNoteOff(); }
    bool is_controller() const { return data.isController(); }
    int get_controller_number() const { return data.isController() ? data.getControllerNumber() : -1; }
    int get_controller_value() const { return data.isController() ? data.getControllerValue() : -1; }
    bool is_pitch_wheel() const { return data.isPitchWheel(); }
    int get_pitch_wheel_value() const { return data.isPitchWheel() ? data.getPitchWheelValue() : -1; }
    bool is_program_change() const { return data.isProgramChange(); }
    int get_program_change_number() const { return data.isProgramChange() ? data.getProgramChangeNumber() : -1; }
    bool is_tempo_meta_event() const { return data.isTempoMetaEvent(); }
    double get_tempo_seconds_per_quarter_note() const { return data.isTempoMetaEvent() ? data.getTempoSecondsPerQuarterNote() : 0.0; }
};
class JuceMidiBuffer : public RefCounted {
    GDCLASS(JuceMidiBuffer, RefCounted)
protected: static void _bind_methods();
public:
    juce::MidiBuffer data;
    bool add_event(const Ref<JuceMidiMessage>& message, int sample_position);
    Array get_events() const;
    int get_num_events() const { return data.getNumEvents(); }
    bool is_empty() const { return data.isEmpty(); }
    void clear() { data.clear(); }
    bool add_events(const Ref<JuceMidiBuffer>& source, int start_sample, int num_samples, int sample_delta = 0);
};
class JuceMidiMessageSequence : public RefCounted {
    GDCLASS(JuceMidiMessageSequence, RefCounted)
protected: static void _bind_methods();
public:
    juce::MidiMessageSequence data;
    bool add_event(const Ref<JuceMidiMessage>& message, double adjustment = 0.0);
    Array get_events() const;
    int get_num_events() const { return data.getNumEvents(); }
    double get_start_time() const { return data.getStartTime(); }
    double get_end_time() const { return data.getEndTime(); }
    void clear() { data.clear(); }
    void sort() { data.sort(); }
    void update_matched_pairs() { data.updateMatchedPairs(); }
};
class JuceMidiFile : public RefCounted {
    GDCLASS(JuceMidiFile, RefCounted)
    juce::MidiFile data;
    String error;
protected: static void _bind_methods();
public:
    JuceMidiFile() { data.setTicksPerQuarterNote(960); }
    bool read_file(const String& path);
    bool write_file(const String& path, bool overwrite = false);
    int get_num_tracks() const { return data.getNumTracks(); }
    Ref<JuceMidiMessageSequence> get_track(int index) const;
    bool add_track(const Ref<JuceMidiMessageSequence>& sequence);
    void clear() { data.clear(); }
    bool set_ticks_per_quarter_note(int ticks) { if (ticks < 1 || ticks > 32767) return false; data.setTicksPerQuarterNote(ticks); return true; }
    int get_time_format() const { return data.getTimeFormat(); }
    void convert_timestamp_ticks_to_seconds() { data.convertTimestampTicksToSeconds(); }
    String get_last_error() const { return error; }
};
class JuceFile : public RefCounted {
    GDCLASS(JuceFile, RefCounted)
    juce::File data;
protected: static void _bind_methods();
public:
    void set_path(const String& path) { data = juce_file_path(path); }
    String get_full_path_name() const { return gd_string(data.getFullPathName()); }
    String get_file_name() const { return gd_string(data.getFileName()); }
    String get_file_extension() const { return gd_string(data.getFileExtension()); }
    bool exists() const { return data.exists(); }
    bool exists_as_file() const { return data.existsAsFile(); }
    bool is_directory() const { return data.isDirectory(); }
    int64_t get_size() const { return data.getSize(); }
    String load_as_string() const { return gd_string(data.loadFileAsString()); }
    bool replace_with_text(const String& text) { return data.replaceWithText(juce::String::fromUTF8(text.utf8().get_data())); }
    bool append_text(const String& text) { return data.appendText(juce::String::fromUTF8(text.utf8().get_data())); }
    bool create_directory() { return data.createDirectory().wasOk(); }
    Ref<JuceFile> get_child_file(const String& path) const;
    Ref<JuceFile> get_parent_directory() const;
    PackedStringArray find_child_files(const String& wildcard = "*", bool recursive = false) const;
};
class JuceAudioFormatManager : public RefCounted {
    GDCLASS(JuceAudioFormatManager, RefCounted)
    juce::AudioFormatManager data;
    String error;
protected: static void _bind_methods();
public:
    JuceAudioFormatManager() { data.registerBasicFormats(); }
    String get_wildcard_for_all_formats() const { return gd_string(data.getWildcardForAllFormats()); }
    Dictionary read_file(const String& path, int max_samples = 10000000);
    bool write_wav(const String& path, const Ref<JuceAudioBuffer>& buffer, double sample_rate, int bits_per_sample = 24, bool overwrite = false);
    String get_last_error() const { return error; }
};
class JuceADSR : public RefCounted {
    GDCLASS(JuceADSR, RefCounted)
    juce::ADSR data;
protected: static void _bind_methods();
public:
    bool set_sample_rate(double rate) { if (!valid_rate(rate)) return false; data.setSampleRate(rate); return true; }
    bool set_parameters(float attack, float decay, float sustain, float release);
    void note_on() { data.noteOn(); }
    void note_off() { data.noteOff(); }
    void reset() { data.reset(); }
    bool is_active() const { return data.isActive(); }
    float get_next_sample() { return data.getNextSample(); }
    bool apply_to_buffer(const Ref<JuceAudioBuffer>& buffer);
};
class JuceReverb : public RefCounted {
    GDCLASS(JuceReverb, RefCounted)
    juce::Reverb data;
protected: static void _bind_methods();
public:
    JuceReverb() { data.setSampleRate(48000.0); }
    bool set_sample_rate(double rate) { if (!valid_rate(rate)) return false; data.setSampleRate(rate); return true; }
    bool set_parameters(const Dictionary& parameters);
    Dictionary get_parameters() const;
    void reset() { data.reset(); }
    bool process(const Ref<JuceAudioBuffer>& buffer);
};
class JuceIIRFilter : public RefCounted {
    GDCLASS(JuceIIRFilter, RefCounted)
    juce::SingleThreadedIIRFilter data;
protected: static void _bind_methods();
public:
    bool make_low_pass(double rate, double hz, double q = 0.70710678);
    bool make_high_pass(double rate, double hz, double q = 0.70710678);
    bool make_band_pass(double rate, double hz, double q = 0.70710678);
    bool make_notch(double rate, double hz, double q = 0.70710678);
    bool make_peak_filter(double rate, double hz, double q, double gain);
    void reset() { data.reset(); }
    float process_sample(float sample) { return std::isfinite(sample) ? data.processSingleSampleRaw(sample) : 0.0f; }
    bool process(const Ref<JuceAudioBuffer>& buffer, int channel = 0);
};
class JuceRandom : public RefCounted {
    GDCLASS(JuceRandom, RefCounted)
    juce::Random data;
protected: static void _bind_methods();
public:
    void set_seed(int64_t seed) { data.setSeed(seed); }
    int next_int(int upper_bound) { return upper_bound > 0 ? data.nextInt(upper_bound) : 0; }
    int64_t next_int64() { return data.nextInt64(); }
    float next_float() { return data.nextFloat(); }
    double next_double() { return data.nextDouble(); }
    bool next_bool() { return data.nextBool(); }
};
class JuceSmoothedValue : public RefCounted {
    GDCLASS(JuceSmoothedValue, RefCounted)
    juce::SmoothedValue<float> data;
protected: static void _bind_methods();
public:
    bool reset(double rate, double seconds) { if (!valid_rate(rate) || !std::isfinite(seconds) || seconds < 0.0 || seconds > 3600.0) return false; data.reset(rate, seconds); return true; }
    void set_current_and_target_value(float v) { if (std::isfinite(v)) data.setCurrentAndTargetValue(v); }
    void set_target_value(float v) { if (std::isfinite(v)) data.setTargetValue(v); }
    float get_next_value() { return data.getNextValue(); }
    float get_current_value() const { return data.getCurrentValue(); }
    bool is_smoothing() const { return data.isSmoothing(); }
    float skip(int samples) { return samples >= 0 ? data.skip(samples) : data.getCurrentValue(); }
    bool apply_gain(const Ref<JuceAudioBuffer>& buffer);
};
class JuceMidiInput : public RefCounted, private juce::MidiInputCallback {
    GDCLASS(JuceMidiInput, RefCounted)
    std::unique_ptr<juce::MidiInput> device;
    juce::CriticalSection mutex;
    std::deque<juce::MidiMessage> messages;
    std::atomic<int64_t> dropped{0};
    String error;
    void handleIncomingMidiMessage(juce::MidiInput*, const juce::MidiMessage&) override;
protected: static void _bind_methods();
public:
    ~JuceMidiInput() override { close_device(); }
    static Array get_available_devices();
    bool open_device(const String& identifier);
    void close_device();
    bool is_open() const { return device != nullptr; }
    Array read_events();
    int64_t get_dropped_event_count() const { return dropped.load(); }
    String get_last_error() const { return error; }
};
class JuceMidiOutput : public RefCounted {
    GDCLASS(JuceMidiOutput, RefCounted)
    std::unique_ptr<juce::MidiOutput> device;
    String error;
protected: static void _bind_methods();
public:
    static Array get_available_devices();
    bool open_device(const String& identifier);
    void close_device() { device.reset(); }
    bool is_open() const { return device != nullptr; }
    bool send_message_now(const Ref<JuceMidiMessage>& message);
    bool send_buffer_now(const Ref<JuceMidiBuffer>& buffer);
    String get_last_error() const { return error; }
};
}

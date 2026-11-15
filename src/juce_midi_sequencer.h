#pragma once
#include "juce_api.h"
#include "midi_clip_player.h"

namespace godot {
class JuceMidiSequencer : public RefCounted {
    GDCLASS(JuceMidiSequencer, RefCounted)
    String error;
protected:
    static void _bind_methods();
public:
    bridge::MidiClipPlayer engine;
    bool load_clip(const Array& notes, double length_beats = 16.0);
    Dictionary export_clip() const;
    bool set_bpm(double value);
    double get_bpm() const { return engine.bpm.load(); }
    void set_looping(bool enabled) { engine.looping.store(enabled); }
    void set_metronome(bool enabled) { engine.metronome.store(enabled); }
    void set_recording(bool enabled) { engine.recording.store(enabled); }
    bool set_volume_db(float value);
    bool set_waveform(int value);
    bool set_channel_settings(int channel, const Dictionary& settings);
    Dictionary get_channel_settings(int channel) const;
    PackedFloat32Array get_channel_peaks() const;
    bool play() { if (!engine.is_prepared()) { error = "Start the audio device or prepare offline before Play"; return false; } engine.play(); error = ""; return true; }
    void stop() { engine.stop(); }
    void panic() { engine.panic(); }
    bool queue_midi(const Ref<JuceMidiMessage>& message);
    Array read_recorded_notes();
    Dictionary get_transport() const;
    bool prepare(double sample_rate, int channels = 2);
    bool process(const Ref<JuceAudioBuffer>& buffer);
    String get_last_error() const { return error; }
};
}

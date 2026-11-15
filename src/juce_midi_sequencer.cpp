#include "juce_midi_sequencer.h"
namespace godot {
namespace {
bool number(const Variant& value) {
    return (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) && std::isfinite(double(value));
}
bool integer(const Variant& value) { return number(value) && double(value) == std::floor(double(value)); }
Dictionary note_dict(int note, int channel, double start, double length, float velocity) {
    Dictionary d; d["note"] = note; d["channel"] = channel; d["start"] = start; d["length"] = length; d["velocity"] = velocity; return d;
}
}
bool JuceMidiSequencer::load_clip(const Array& input, double length) {
    error = "";
    if (input.size() > bridge::MidiClipPlayer::max_notes) { error = "Clip exceeds 4096 notes"; return false; }
    std::vector<bridge::MidiClipPlayer::Note> notes;
    notes.reserve(size_t(input.size()));
    for (const Variant& raw : input) {
        if (raw.get_type() != Variant::DICTIONARY) { error = "Each clip note must be a dictionary"; return false; }
        const Dictionary d = raw;
        bool valid = d.has("note") && d.has("start") && d.has("length") && d.has("velocity");
        for (const Variant& key : d.keys()) if (key.get_type() != Variant::STRING ||
            (String(key) != "note" && String(key) != "start" && String(key) != "length" && String(key) != "velocity" && String(key) != "channel")) valid = false;
        if (!valid || !integer(d["note"]) || double(d["note"]) < 0 || double(d["note"]) > 127 ||
            !number(d["start"]) || !number(d["length"]) || !number(d["velocity"]) ||
            (d.has("channel") && (!integer(d["channel"]) || double(d["channel"]) < 1 || double(d["channel"]) > 16))) {
            error = "Invalid clip note schema"; return false;
        }
        notes.push_back({int(d["note"]), d.has("channel") ? int(d["channel"]) : 1,
            double(d["start"]), double(d["length"]), float(double(d["velocity"]))});
    }
    if (!engine.load_clip(notes, length)) { error = String::utf8(engine.last_error().c_str()); return false; }
    return true;
}
Dictionary JuceMidiSequencer::export_clip() const {
    Dictionary d; Array notes;
    for (const auto& n : engine.get_notes()) notes.append(note_dict(n.note, n.channel, n.start, n.length, n.velocity));
    d["length_beats"] = engine.get_length(); d["notes"] = notes; return d;
}
bool JuceMidiSequencer::set_bpm(double value) {
    if (!std::isfinite(value) || value < 20 || value > 300) { error = "BPM must be 20–300"; return false; }
    engine.bpm.store(value); error = ""; return true;
}
bool JuceMidiSequencer::set_volume_db(float value) {
    if (!std::isfinite(value) || value < -60 || value > 0) { error = "Volume must be -60–0 dB"; return false; }
    engine.volume_db.store(value); error = ""; return true;
}
bool JuceMidiSequencer::set_waveform(int value) {
    if (value < 0 || value > 3) { error = "Waveform must be 0–3"; return false; }
    engine.waveform.store(value); error = ""; return true;
}
bool JuceMidiSequencer::queue_midi(const Ref<JuceMidiMessage>& message) {
    if (!engine.is_prepared()) { error = "Start the audio device or prepare offline before queueing MIDI"; return false; }
    if (message.is_null()) { error = "MIDI message is null"; return false; }
    const auto& m = message->data;
    bridge::MidiClipPlayer::Input input;
    input.channel = m.getChannel();
    if (m.isNoteOn()) { input.type = 1; input.note = m.getNoteNumber(); input.value = m.getFloatVelocity(); }
    else if (m.isNoteOff()) { input.type = 2; input.note = m.getNoteNumber(); }
    else if (m.isController() && (m.getControllerNumber() == 64 || m.getControllerNumber() == 120 || m.getControllerNumber() == 123)) {
        input.type = 3; input.note = m.getControllerNumber(); input.value = float(m.getControllerValue());
    } else { error = "Sequencer input supports notes, sustain, all-notes-off and all-sound-off"; return false; }
    if (!engine.queue_input(input)) { error = "MIDI input queue is full or message is invalid; panic scheduled"; return false; }
    error = ""; return true;
}
Array JuceMidiSequencer::read_recorded_notes() {
    Array result; bridge::MidiClipPlayer::Recorded n;
    while (engine.read_recorded(n)) result.append(note_dict(n.note, n.channel, n.start, n.length, n.velocity));
    return result;
}
Dictionary JuceMidiSequencer::get_transport() const {
    Dictionary d;
    d["bpm"] = engine.bpm.load(); d["beat"] = engine.published_beat.load();
    d["elapsed_beats"] = engine.published_elapsed.load(); d["playing"] = engine.requested_play.load();
    d["recording"] = engine.recording.load(); d["looping"] = engine.looping.load();
    d["active"] = engine.active.load(); d["sample_position"] = int64_t(engine.rendered_samples.load());
    d["input_drops"] = int64_t(engine.input_drops.load()); d["recording_drops"] = int64_t(engine.recording_drops.load());
    return d;
}
bool JuceMidiSequencer::prepare(double rate, int channels) {
    if (!engine.prepare(rate, channels)) { error = String::utf8(engine.last_error().c_str()); return false; }
    error = ""; return true;
}
bool JuceMidiSequencer::process(const Ref<JuceAudioBuffer>& buffer) {
    if (engine.active.load() || !engine.is_prepared() || buffer.is_null() || buffer->get_num_channels() != engine.get_channels()) {
        error = "Offline processing requires a stopped, prepared sequencer and matching channels"; return false;
    }
    auto& data = buffer->native();
    for (int offset = 0; offset < data.getNumSamples(); offset += 8192) {
        float* outputs[2] = {data.getWritePointer(0) + offset, nullptr};
        if (data.getNumChannels() == 2) outputs[1] = data.getWritePointer(1) + offset;
        if (!engine.render(outputs, data.getNumChannels(), std::min(8192, data.getNumSamples() - offset))) return false;
    }
    error = ""; return true;
}
}

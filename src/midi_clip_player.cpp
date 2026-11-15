#include "midi_clip_player.h"
#include <algorithm>
#include <cmath>

namespace bridge {
static_assert(std::atomic<double>::is_always_lock_free && std::atomic<uint64_t>::is_always_lock_free,
              "The MIDI audio engine requires lock-free timeline atomics");

bool MidiClipPlayer::load_clip(const std::vector<Note>& replacement, double beats) {
    error.clear();
    if (active.load()) { error = "Stop the audio device before replacing a clip"; return false; }
    if (!std::isfinite(beats) || beats < 1 || beats > 256 || replacement.size() > max_notes) {
        error = "Clip length must be 1–256 beats, with at most 4096 notes"; return false;
    }
    std::vector<Event> candidate;
    candidate.reserve(replacement.size() * 2);
    for (size_t i = 0; i < replacement.size(); ++i) {
        const auto& n = replacement[i];
        if (n.note < 0 || n.note > 127 || n.channel < 1 || n.channel > 16 ||
            !std::isfinite(n.start) || !std::isfinite(n.length) || !std::isfinite(n.velocity) ||
            n.start < 0 || n.length <= 0 || n.start + n.length <= n.start || n.start + n.length > beats + 1e-9 ||
            n.velocity <= 0 || n.velocity > 1) {
            error = "Invalid clip note, time, channel or velocity"; return false;
        }
        candidate.push_back({n.start, int(i), true});
        candidate.push_back({std::min(beats, n.start + n.length), int(i), false});
    }
    std::sort(candidate.begin(), candidate.end(), [](const Event& a, const Event& b) {
        if (a.beat != b.beat) return a.beat < b.beat;
        if (a.on != b.on) return !a.on; // Adjacent notes release before retriggering.
        return a.id < b.id;
    });
    notes = replacement; events = std::move(candidate); length = beats;
    device_stopped(); prepared = false;
    return true;
}

void MidiClipPlayer::reset_voices() noexcept {
    for (auto& v : voices) { v.envelope.reset(); v.note = -1; v.held = false; }
    pedal.fill(false);
}

bool MidiClipPlayer::prepare(double sample_rate, int num_channels, bool for_device) {
    error.clear();
    if (active.load() && !for_device) { error = "Stop audio before preparing"; return false; }
    if (!std::isfinite(sample_rate) || sample_rate < 8000 || sample_rate > 384000 ||
        num_channels < 1 || num_channels > 2) { error = "Invalid sample rate or channel count"; return false; }
    rate = sample_rate; channels = num_channels;
    for (auto& v : voices) {
        v.envelope.setSampleRate(rate);
        v.envelope.setParameters({0.005f, 0.08f, 0.75f, 0.1f});
    }
    device_stopped();
    input_drops.store(0); recording_drops.store(0);
    prepared = true;
    return true;
}

void MidiClipPlayer::device_stopped() {
    finish_recording(); reset_voices();
    incoming.clear();
    requested_play.store(false); published_playing.store(false);
    recording.store(false); stop_requested.store(false); panic_requested.store(false);
    playing = capturing = false; beat = elapsed = 0; cursor = 0; last_tick = -1; click_left = 0;
    published_beat.store(0); published_elapsed.store(0); rendered_samples.store(0);
}

bool MidiClipPlayer::queue_input(const Input& input) {
    if (input.channel < 1 || input.channel > 16 || input.note < 0 || input.note > 127 ||
        !std::isfinite(input.value) || input.value < 0 || input.value > (input.type == 3 ? 127 : 1) ||
        input.type < 1 || input.type > 3) return false;
    if (incoming.push(input)) return true;
    input_drops.fetch_add(1);
    panic_requested.store(true); // Overflow must not strand a missing note-off.
    return false;
}

void MidiClipPlayer::finish_note(int channel, int note) noexcept {
    auto& held = held_recording[size_t((channel - 1) * 128 + note)];
    if (held.start < 0) return;
    if (elapsed > held.start && !completed.push({note, channel, held.start, elapsed - held.start, held.velocity}))
        recording_drops.fetch_add(1);
    held.start = -1;
}

void MidiClipPlayer::finish_recording() noexcept {
    for (int ch = 1; ch <= 16; ++ch) for (int note = 0; note < 128; ++note) finish_note(ch, note);
}

void MidiClipPlayer::start_voice(int note, int channel, float strength, int clip_id) noexcept {
    Voice* chosen = nullptr;
    for (auto& v : voices) if (!v.envelope.isActive()) { chosen = &v; break; }
    if (!chosen) chosen = &*std::min_element(voices.begin(), voices.end(), [](const Voice& a, const Voice& b) { return a.age < b.age; });
    auto& v = *chosen;
    v.envelope.reset(); v.note = note; v.channel = channel; v.clip_id = clip_id;
    v.held = true; v.velocity = strength; v.phase = 0; v.age = ++age;
    v.step = std::min(0.45, juce::MidiMessage::getMidiNoteInHertz(note) / rate);
    v.envelope.noteOn();
}

void MidiClipPlayer::handle_input(const Input& input) noexcept {
    if (input.type == 1 && input.value > 0) {
        for (auto& v : voices) if (v.clip_id < 0 && v.note == input.note && v.channel == input.channel && v.held) {
            v.held = false; v.envelope.noteOff();
        }
        start_voice(input.note, input.channel, input.value, -1);
        if (capturing) {
            finish_note(input.channel, input.note);
            held_recording[size_t((input.channel - 1) * 128 + input.note)] = {elapsed, input.value};
        }
    } else if (input.type == 2 || (input.type == 1 && input.value == 0)) {
        for (auto& v : voices) if (v.clip_id < 0 && v.note == input.note && v.channel == input.channel && v.held) {
            v.held = false;
            if (!pedal[size_t(input.channel - 1)]) v.envelope.noteOff();
        }
        if (capturing) finish_note(input.channel, input.note);
    } else if (input.type == 3 && input.note == 64) {
        pedal[size_t(input.channel - 1)] = input.value >= 64;
        if (input.value < 64) for (auto& v : voices)
            if (v.clip_id < 0 && v.channel == input.channel && !v.held) v.envelope.noteOff();
    } else if (input.type == 3 && (input.note == 120 || input.note == 123)) {
        for (auto& v : voices) if (v.clip_id < 0 && v.channel == input.channel) {
            v.envelope.reset(); v.note = -1; v.held = false;
        }
        pedal[size_t(input.channel - 1)] = false;
        if (capturing) for (int note = 0; note < 128; ++note) finish_note(input.channel, note);
    }
}

void MidiClipPlayer::release_clip() noexcept {
    for (auto& v : voices) if (v.clip_id >= 0 && v.held) { v.held = false; v.envelope.noteOff(); }
}

float MidiClipPlayer::synth_sample(int shape) noexcept {
    float sum = 0;
    for (auto& v : voices) if (v.envelope.isActive()) {
        double value;
        if (shape == 1) value = 1.0 - 4.0 * std::abs(v.phase - 0.5);
        else if (shape == 2) value = 2.0 * v.phase - 1.0;
        else if (shape == 3) value = v.phase < 0.5 ? 1.0 : -1.0;
        else value = std::sin(v.phase * juce::MathConstants<double>::twoPi);
        sum += float(value) * v.velocity * v.envelope.getNextSample() * 0.025f;
        v.phase += v.step; if (v.phase >= 1) v.phase -= 1;
    }
    return sum;
}

bool MidiClipPlayer::render(float* const* output, int count, int samples) noexcept {
    if (!prepared || count != channels || samples < 0 || samples > 8192) return false;
    const double tempo = bpm.load(), step = tempo / (60.0 * rate);
    const float gain = juce::Decibels::decibelsToGain(volume_db.load());
    const int shape = waveform.load();
    if (stop_requested.exchange(false)) {
        finish_recording(); reset_voices(); playing = capturing = false;
        beat = elapsed = 0; cursor = 0; last_tick = -1; click_left = 0;
    }
    if (panic_requested.exchange(false)) {
        finish_recording(); reset_voices();
        Input discard;
        for (int i = 0; i < 1023 && incoming.pop(discard); ++i) {}
    }
    if (requested_play.load() && !playing) {
        reset_voices(); beat = elapsed = 0; cursor = 0; last_tick = -1; playing = true;
        rendered_samples.store(0);
    }
    const bool capture_now = recording.load() && playing;
    if (capturing && !capture_now) finish_recording();
    capturing = capture_now;
    Input input;
    // Bounded drain: at most the queue's capacity, even if the producer keeps writing.
    for (int i = 0; i < 1023 && incoming.pop(input); ++i) handle_input(input);
    const bool click_enabled = metronome.load();
    if (!click_enabled) click_left = 0;
    uint64_t advanced = 0;
    for (int sample = 0; sample < samples; ++sample) {
        if (playing && beat + 1e-10 >= length) {
            release_clip();
            if (looping.load()) { beat = std::max(0.0, beat - length); cursor = 0; last_tick = -1; }
            else {
                finish_recording(); capturing = playing = false; requested_play.store(false); recording.store(false); beat = length;
            }
        }
        if (playing) {
            while (cursor < events.size() && events[cursor].beat <= beat + 1e-10) {
                const auto& event = events[cursor++]; const auto& note = notes[size_t(event.id)];
                if (event.on) start_voice(note.note, note.channel, note.velocity, event.id);
                else for (auto& v : voices) if (v.clip_id == event.id && v.held) { v.held = false; v.envelope.noteOff(); }
            }
            const int tick = int(std::floor(beat + 1e-10));
            if (tick != last_tick) {
                last_tick = tick;
                if (click_enabled) { click_left = int(rate * 0.025); click_phase = 0; click_frequency = tick % 4 == 0 ? 1760 : 1320; }
            }
            beat += step; elapsed += step; ++advanced;
        }
        float value = synth_sample(shape);
        if (click_enabled && click_left > 0) {
            value += float(std::sin(click_phase)) * 0.12f * float(click_left) / float(rate * 0.025);
            click_phase += juce::MathConstants<double>::twoPi * click_frequency / rate; --click_left;
        }
        value = std::clamp(value * gain, -1.0f, 1.0f);
        for (int ch = 0; ch < count; ++ch) if (output[ch]) output[ch][sample] = value;
    }
    // Publish a callback ending exactly on the clip edge without a stale position.
    if (playing && beat + 1e-10 >= length) {
        release_clip();
        if (looping.load()) { beat = std::max(0.0, beat - length); cursor = 0; last_tick = -1; }
        else { finish_recording(); capturing = playing = false; requested_play.store(false); recording.store(false); beat = length; }
    }
    rendered_samples.fetch_add(advanced);
    published_playing.store(playing); published_beat.store(std::min(beat, length)); published_elapsed.store(elapsed);
    return true;
}
}

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
    for (auto& ch : channel_settings) ch.peak.store(0);
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
    bool solo = false;
    for (auto& ch : channel_settings) solo |= ch.solo.load();
    for (int i = 0; i < 16; ++i) {
        const auto& ch = channel_settings[size_t(i)];
        gain_ramps[size_t(i)].reset(rate, 0.005);
        pan_ramps[size_t(i)].reset(rate, 0.005);
        gain_ramps[size_t(i)].setCurrentAndTargetValue(ch.mute.load() || (solo && !ch.solo.load()) ? 0 : juce::Decibels::decibelsToGain(ch.volume_db.load()));
        pan_ramps[size_t(i)].setCurrentAndTargetValue(ch.pan.load());
    }
    master_ramp.reset(rate, 0.005);
    master_ramp.setCurrentAndTargetValue(juce::Decibels::decibelsToGain(volume_db.load()));
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
    v.kind = channel_settings[size_t(channel - 1)].waveform.load();
    v.life = 0; v.noise = uint32_t(v.age * 2654435761u) | 1u; v.previous_noise = 0;
    v.envelope.setParameters(v.kind >= 4
        ? juce::ADSR::Parameters(0.001f, v.kind == 6 ? 0.055f : 0.18f, 0.0f, 0.04f)
        : juce::ADSR::Parameters(0.005f, 0.08f, 0.75f, 0.1f));
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
            if (!pedal[size_t(input.channel - 1)] && v.kind < 4) v.envelope.noteOff();
        }
        if (capturing) finish_note(input.channel, input.note);
    } else if (input.type == 3 && input.note == 64) {
        pedal[size_t(input.channel - 1)] = input.value >= 64;
        if (input.value < 64) for (auto& v : voices)
            if (v.clip_id < 0 && v.channel == input.channel && !v.held && v.kind < 4) v.envelope.noteOff();
    } else if (input.type == 3 && (input.note == 120 || input.note == 123)) {
        for (auto& v : voices) if (v.clip_id < 0 && v.channel == input.channel) {
            v.envelope.reset(); v.note = -1; v.held = false;
        }
        pedal[size_t(input.channel - 1)] = false;
        if (capturing) for (int note = 0; note < 128; ++note) finish_note(input.channel, note);
    }
}

void MidiClipPlayer::release_clip() noexcept {
    for (auto& v : voices) if (v.clip_id >= 0 && v.held) { v.held = false; if (v.kind < 4) v.envelope.noteOff(); }
}

void MidiClipPlayer::synth_sample(int shape, const float* gains, const float* pans, float* peaks, float& left, float& right) noexcept {
    float values[16] = {};
    for (auto& v : voices) if (v.envelope.isActive()) {
        const float envelope = v.envelope.getNextSample();
        if (v.kind >= 4 && v.life > 0 && envelope <= 0) {
            v.envelope.reset(); v.note = -1; v.held = false; continue;
        }
        double value;
        const int kind = v.kind < 0 ? shape : v.kind;
        double increment = v.step;
        if (kind >= 4) {
            v.noise ^= v.noise << 13; v.noise ^= v.noise >> 17; v.noise ^= v.noise << 5;
            const float noise = float(double(v.noise) / 2147483648.0 - 1.0);
            if (kind == 4) {
                increment = std::min(0.45, v.step * (0.7 + 2.8 * std::exp(-double(v.life) / (rate * 0.018))));
                value = std::sin(v.phase * juce::MathConstants<double>::twoPi);
            } else if (kind == 5) value = noise * 0.8 + std::sin(v.phase * juce::MathConstants<double>::twoPi * 3.0) * 0.2;
            else if (kind == 6) value = (noise - v.previous_noise * 0.94f) * 0.52;
            else value = noise * (v.life < int(rate * 0.03) ? (int(v.life / (rate * 0.006)) % 2 ? 0.2 : 1.0) : 0.65);
            v.previous_noise = noise;
        } else if (kind == 1) value = 1.0 - 4.0 * std::abs(v.phase - 0.5);
        else if (kind == 2) value = 2.0 * v.phase - 1.0;
        else if (kind == 3) value = v.phase < 0.5 ? 1.0 : -1.0;
        else value = std::sin(v.phase * juce::MathConstants<double>::twoPi);
        values[v.channel - 1] += float(value) * v.velocity * envelope * (kind >= 4 ? 0.15f : 0.06f);
        ++v.life; v.phase += increment; if (v.phase >= 1) v.phase -= 1;
    }
    left = right = 0;
    for (int ch = 0; ch < 16; ++ch) {
        const float value = values[ch] * gains[ch];
        peaks[ch] = std::max(peaks[ch], std::abs(value));
        left += value * (pans[ch] > 0 ? 1 - pans[ch] : 1);
        right += value * (pans[ch] < 0 ? 1 + pans[ch] : 1);
    }
}

bool MidiClipPlayer::render(float* const* output, int count, int samples) noexcept {
    if (!prepared || count != channels || samples < 0 || samples > 8192) return false;
    const double tempo = bpm.load(), step = tempo / (60.0 * rate);
    master_ramp.setTargetValue(juce::Decibels::decibelsToGain(volume_db.load()));
    const int shape = waveform.load();
    float gains[16], pans[16], peaks[16] = {};
    bool any_solo = false;
    for (auto& ch : channel_settings) any_solo |= ch.solo.load();
    for (int ch = 0; ch < 16; ++ch) {
        const auto& settings = channel_settings[size_t(ch)];
        gains[ch] = settings.mute.load() || (any_solo && !settings.solo.load()) ? 0 : juce::Decibels::decibelsToGain(settings.volume_db.load());
        pans[ch] = settings.pan.load();
        gain_ramps[size_t(ch)].setTargetValue(gains[ch]);
        pan_ramps[size_t(ch)].setTargetValue(pans[ch]);
    }
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
                else for (auto& v : voices) if (v.clip_id == event.id && v.held) { v.held = false; if (v.kind < 4) v.envelope.noteOff(); }
            }
            const int tick = int(std::floor(beat + 1e-10));
            if (tick != last_tick) {
                last_tick = tick;
                if (click_enabled) { click_left = int(rate * 0.025); click_phase = 0; click_frequency = tick % 4 == 0 ? 1760 : 1320; }
            }
            beat += step; elapsed += step; ++advanced;
        }
        float left, right;
        for (int ch = 0; ch < 16; ++ch) {
            gains[ch] = gain_ramps[size_t(ch)].getNextSample();
            pans[ch] = pan_ramps[size_t(ch)].getNextSample();
        }
        synth_sample(shape, gains, pans, peaks, left, right);
        if (click_enabled && click_left > 0) {
            const float click = float(std::sin(click_phase)) * 0.12f * float(click_left) / float(rate * 0.025);
            left += click; right += click;
            click_phase += juce::MathConstants<double>::twoPi * click_frequency / rate; --click_left;
        }
        const float gain = master_ramp.getNextSample();
        if (count == 1) { if (output[0]) output[0][sample] = std::clamp((left + right) * 0.5f * gain, -1.0f, 1.0f); }
        else {
            if (output[0]) output[0][sample] = std::clamp(left * gain, -1.0f, 1.0f);
            if (output[1]) output[1][sample] = std::clamp(right * gain, -1.0f, 1.0f);
        }
    }
    // Publish a callback ending exactly on the clip edge without a stale position.
    if (playing && beat + 1e-10 >= length) {
        release_clip();
        if (looping.load()) { beat = std::max(0.0, beat - length); cursor = 0; last_tick = -1; }
        else { finish_recording(); capturing = playing = false; requested_play.store(false); recording.store(false); beat = length; }
    }
    rendered_samples.fetch_add(advanced);
    for (int ch = 0; ch < 16; ++ch) channel_settings[size_t(ch)].peak.store(peaks[ch]);
    published_playing.store(playing); published_beat.store(std::min(beat, length)); published_elapsed.store(elapsed);
    return true;
}
}

#include "juce_api.h"
#include <godot_cpp/classes/json.hpp>
#include <limits>
#include <cstring>
namespace godot {
juce::File juce_file_path(const String& path) {
    auto full = ProjectSettings::get_singleton()->globalize_path(path);
    return juce::File::getCurrentWorkingDirectory().getChildFile(juce::String::fromUTF8(full.utf8().get_data()));
}
bool JuceAudioBuffer::set_size(int channels, int samples, bool keep) {
    if (channels < 1 || channels > 32 || samples < 0 || int64_t(channels) * samples > 16000000) return false;
    data.setSize(channels, samples, keep, true, false);
    if (!keep) data.clear();
    return true;
}
bool JuceAudioBuffer::set_sample(int ch, int sample, float value) {
    if (ch < 0 || ch >= get_num_channels() || sample < 0 || sample >= get_num_samples() || !std::isfinite(value)) return false;
    data.setSample(ch, sample, value); return true;
}
PackedFloat32Array JuceAudioBuffer::get_channel(int channel) const {
    PackedFloat32Array result;
    if (channel < 0 || channel >= get_num_channels()) return result;
    result.resize(get_num_samples());
    if (get_num_samples() > 0) std::memcpy(result.ptrw(), data.getReadPointer(channel), get_num_samples() * sizeof(float));
    return result;
}
bool JuceAudioBuffer::set_channel(int channel, const PackedFloat32Array& samples) {
    if (channel < 0 || channel >= get_num_channels() || samples.size() != get_num_samples()) return false;
    for (int i = 0; i < samples.size(); ++i) if (!std::isfinite(samples[i])) return false;
    if (samples.size() > 0) data.copyFrom(channel, 0, samples.ptr(), get_num_samples());
    return true;
}
bool JuceAudioBuffer::copy_from(const Ref<JuceAudioBuffer>& source) {
    if (source.is_null()) return false;
    if (source.ptr() != this) data.makeCopyOf(source->native());
    return true;
}
bool JuceAudioBuffer::add_from(const Ref<JuceAudioBuffer>& source, float gain) {
    if (source.is_null() || !std::isfinite(gain) || source->get_num_channels() != get_num_channels() || source->get_num_samples() != get_num_samples()) return false;
    for (int ch = 0; ch < get_num_channels(); ++ch) data.addFrom(ch, 0, source->native(), ch, 0, get_num_samples(), gain);
    return true;
}
Ref<JuceAudioBuffer> JuceAudioBuffer::duplicate_buffer() const {
    Ref<JuceAudioBuffer> result; result.instantiate(); result->native().makeCopyOf(data); return result;
}
Ref<JuceMidiMessage> JuceMidiMessage::wrap(const juce::MidiMessage& m) { Ref<JuceMidiMessage> r; r.instantiate(); r->data = m; return r; }
static bool midi_channel(int c) { return c >= 1 && c <= 16; }
Ref<JuceMidiMessage> JuceMidiMessage::note_on(int c, int n, float v) {
    if (!midi_channel(c) || n < 0 || n > 127 || !std::isfinite(v)) return {};
    return wrap(juce::MidiMessage::noteOn(c, n, std::clamp(v, 0.0f, 1.0f)));
}
Ref<JuceMidiMessage> JuceMidiMessage::note_off(int c, int n) { if (!midi_channel(c) || n < 0 || n > 127) return {}; return wrap(juce::MidiMessage::noteOff(c, n)); }
Ref<JuceMidiMessage> JuceMidiMessage::controller_event(int c, int controller, int value) { if (!midi_channel(c) || controller < 0 || controller > 127 || value < 0 || value > 127) return {}; return wrap(juce::MidiMessage::controllerEvent(c, controller, value)); }
Ref<JuceMidiMessage> JuceMidiMessage::pitch_wheel(int c, int value) { if (!midi_channel(c) || value < 0 || value > 16383) return {}; return wrap(juce::MidiMessage::pitchWheel(c, value)); }
Ref<JuceMidiMessage> JuceMidiMessage::program_change(int c, int program) { if (!midi_channel(c) || program < 0 || program > 127) return {}; return wrap(juce::MidiMessage::programChange(c, program)); }
Ref<JuceMidiMessage> JuceMidiMessage::tempo_event(int us) { if (us < 1 || us > 0xffffff) return {}; return wrap(juce::MidiMessage::tempoMetaEvent(us)); }
Ref<JuceMidiMessage> JuceMidiMessage::from_bytes(const PackedByteArray& bytes, double timestamp) {
    if (bytes.is_empty() || bytes.size() > 65536 || !std::isfinite(timestamp)) return {};
    int status = bytes[0];
    if (status >= 0x80 && status < 0xf0) {
        const int size = (status & 0xe0) == 0xc0 ? 2 : 3;
        if (bytes.size() != size) return {};
        for (int i = 1; i < size; ++i) if (bytes[i] > 127) return {};
    } else if (status == 0xf0) {
        if (bytes.size() < 2 || bytes[bytes.size() - 1] != 0xf7) return {};
        for (int i = 1; i < bytes.size() - 1; ++i) if (bytes[i] > 127) return {};
    } else if (status >= 0xf8 && status <= 0xfe) {
        if (bytes.size() != 1) return {};
    } else return {}; // Meta-events use typed factories; incomplete/system-common raw messages are rejected.
    return wrap(juce::MidiMessage(bytes.ptr(), int(bytes.size()), timestamp));
}
PackedByteArray JuceMidiMessage::get_raw_data() const {
    PackedByteArray r; r.resize(data.getRawDataSize());
    if (r.size()) std::memcpy(r.ptrw(), data.getRawData(), r.size()); return r;
}
bool JuceMidiBuffer::add_event(const Ref<JuceMidiMessage>& m, int sample) { if (m.is_null() || sample < 0) return false; return data.addEvent(m->data, sample); }
Array JuceMidiBuffer::get_events() const {
    Array result;
    for (const auto event : data) { Dictionary item; item["sample_position"] = event.samplePosition; item["message"] = JuceMidiMessage::wrap(event.getMessage()); result.append(item); }
    return result;
}
bool JuceMidiBuffer::add_events(const Ref<JuceMidiBuffer>& src, int start, int count, int delta) {
    if (src.is_null() || src.ptr() == this || start < 0 || count < 0 || int64_t(start) + count > INT32_MAX) return false;
    // Add individually to validate translated positions without signed overflow.
    for (const auto event : src->data) if (event.samplePosition >= start && int64_t(event.samplePosition) < int64_t(start) + count) {
        const int64_t target = int64_t(event.samplePosition) + delta;
        if (target < 0 || target > INT32_MAX) return false;
    }
    data.addEvents(src->data, start, count, delta); return true;
}
bool JuceMidiMessageSequence::add_event(const Ref<JuceMidiMessage>& m, double adjustment) { if (m.is_null() || !std::isfinite(adjustment) || !std::isfinite(m->data.getTimeStamp() + adjustment)) return false; data.addEvent(m->data, adjustment); return true; }
Array JuceMidiMessageSequence::get_events() const { Array r; for (int i = 0; i < data.getNumEvents(); ++i) r.append(JuceMidiMessage::wrap(data.getEventPointer(i)->message)); return r; }
bool JuceMidiFile::read_file(const String& path) {
    error = ""; auto file = juce_file_path(path);
    if (file.getSize() > 64000000) { error = "MIDI file exceeds 64 MB limit"; return false; }
    auto stream = file.createInputStream();
    juce::MidiFile replacement;
    if (!stream || !replacement.readFrom(*stream)) { error = "Cannot read MIDI file"; return false; }
    data = replacement; return true;
}
bool JuceMidiFile::write_file(const String& path, bool overwrite) {
    error = ""; auto target = juce_file_path(path);
    if (target.exists() && !overwrite) { error = "Target exists; explicitly enable overwrite"; return false; }
    juce::TemporaryFile temp(target); auto stream = temp.getFile().createOutputStream();
    if (!stream || !data.writeTo(*stream)) { error = "Cannot write MIDI file"; return false; }
    stream->flush(); const bool ok = stream->getStatus().wasOk(); stream.reset();
    if (!ok || !temp.overwriteTargetFileWithTemporary()) { error = "Cannot replace destination MIDI file"; return false; }
    return true;
}
Ref<JuceMidiMessageSequence> JuceMidiFile::get_track(int index) const { if (index < 0 || index >= data.getNumTracks()) return {}; Ref<JuceMidiMessageSequence> r; r.instantiate(); r->data = *data.getTrack(index); return r; }
bool JuceMidiFile::add_track(const Ref<JuceMidiMessageSequence>& s) { if (s.is_null()) return false; data.addTrack(s->data); return true; }
Ref<JuceFile> JuceFile::get_child_file(const String& path) const { Ref<JuceFile> r; r.instantiate(); r->data = data.getChildFile(juce::String::fromUTF8(path.utf8().get_data())); return r; }
Ref<JuceFile> JuceFile::get_parent_directory() const { Ref<JuceFile> r; r.instantiate(); r->data = data.getParentDirectory(); return r; }
PackedStringArray JuceFile::find_child_files(const String& wildcard, bool recursive) const { PackedStringArray r; for (const auto& f : data.findChildFiles(juce::File::findFiles, recursive, juce::String::fromUTF8(wildcard.utf8().get_data()))) r.append(gd_string(f.getFullPathName())); return r; }
Dictionary JuceAudioFormatManager::read_file(const String& path, int max_samples) {
    Dictionary r; error = "";
    auto reader = std::unique_ptr<juce::AudioFormatReader>(data.createReaderFor(juce_file_path(path)));
    if (!reader) { error = "Unsupported or unreadable audio file"; return r; }
    if (max_samples < 1 || reader->lengthInSamples < 0 || reader->lengthInSamples > max_samples || reader->numChannels < 1 || reader->numChannels > 32 || reader->lengthInSamples * reader->numChannels > 16000000) { error = "Audio file exceeds requested size or buffer allocation limit"; return r; }
    Ref<JuceAudioBuffer> buffer; buffer.instantiate();
    if (!buffer->set_size(int(reader->numChannels), int(reader->lengthInSamples)) || !reader->read(&buffer->native(), 0, buffer->get_num_samples(), 0, true, true)) { error = "Cannot decode audio file"; return r; }
    r["buffer"] = buffer; r["sample_rate"] = reader->sampleRate; r["bits_per_sample"] = int(reader->bitsPerSample); return r;
}
bool JuceAudioFormatManager::write_wav(const String& path, const Ref<JuceAudioBuffer>& buffer, double rate, int bits, bool overwrite) {
    error = "";
    if (buffer.is_null() || buffer->get_num_channels() < 1 || !valid_rate(rate) || (bits != 16 && bits != 24 && bits != 32)) { error = "Invalid WAV parameters"; return false; }
    auto target = juce_file_path(path);
    if (target.exists() && !overwrite) { error = "Target exists; explicitly enable overwrite"; return false; }
    juce::TemporaryFile temp(target); std::unique_ptr<juce::OutputStream> stream = temp.getFile().createOutputStream();
    if (!stream) { error = "Cannot create WAV output"; return false; }
    juce::WavAudioFormat format;
    auto writer = format.createWriterFor(stream, juce::AudioFormatWriterOptions{}.withSampleRate(rate).withNumChannels(buffer->get_num_channels()).withBitsPerSample(bits));
    if (!writer) { error = "Cannot create WAV writer"; return false; }
    const bool ok = writer->writeFromAudioSampleBuffer(buffer->native(), 0, buffer->get_num_samples()); writer.reset();
    if (!ok || !temp.overwriteTargetFileWithTemporary()) { error = "Cannot finish WAV output"; return false; } return true;
}
bool JuceADSR::set_parameters(float a, float d, float s, float r) {
    if (!std::isfinite(a) || !std::isfinite(d) || !std::isfinite(s) || !std::isfinite(r) || a < 0 || d < 0 || r < 0 || s < 0 || s > 1 || a > 3600 || d > 3600 || r > 3600) return false;
    data.setParameters({a,d,s,r}); return true;
}
bool JuceADSR::apply_to_buffer(const Ref<JuceAudioBuffer>& b) { if (b.is_null()) return false; data.applyEnvelopeToBuffer(b->native(), 0, b->get_num_samples()); return true; }
bool JuceReverb::set_parameters(const Dictionary& p) {
    auto v = data.getParameters();
    const char* keys[] = {"room_size","damping","wet_level","dry_level","width","freeze_mode"};
    float* values[] = {&v.roomSize,&v.damping,&v.wetLevel,&v.dryLevel,&v.width,&v.freezeMode};
    for (int i = 0; i < 6; ++i) if (p.has(keys[i])) { float x = p[keys[i]]; if (!std::isfinite(x) || x < 0 || x > 1) return false; *values[i] = x; }
    for (const Variant& key : p.keys()) { bool found = false; for (auto k : keys) if (String(key) == k) found = true; if (!found) return false; }
    data.setParameters(v); return true;
}
Dictionary JuceReverb::get_parameters() const { auto p = data.getParameters(); Dictionary r; r["room_size"]=p.roomSize; r["damping"]=p.damping; r["wet_level"]=p.wetLevel; r["dry_level"]=p.dryLevel; r["width"]=p.width; r["freeze_mode"]=p.freezeMode; return r; }
bool JuceReverb::process(const Ref<JuceAudioBuffer>& b) {
    if (b.is_null() || b->get_num_channels() < 1 || b->get_num_channels() > 2) return false;
    if (b->get_num_channels() == 1) data.processMono(b->native().getWritePointer(0), b->get_num_samples());
    else data.processStereo(b->native().getWritePointer(0), b->native().getWritePointer(1), b->get_num_samples()); return true;
}
static bool valid_filter(double rate, double hz, double q) { return valid_rate(rate) && std::isfinite(hz) && hz > 0 && hz < rate * 0.5 && std::isfinite(q) && q >= 0.01 && q <= 100; }
bool JuceIIRFilter::make_low_pass(double r, double h, double q) { if (!valid_filter(r,h,q)) return false; data.setCoefficients(juce::IIRCoefficients::makeLowPass(r,h,q)); return true; }
bool JuceIIRFilter::make_high_pass(double r, double h, double q) { if (!valid_filter(r,h,q)) return false; data.setCoefficients(juce::IIRCoefficients::makeHighPass(r,h,q)); return true; }
bool JuceIIRFilter::make_band_pass(double r, double h, double q) { if (!valid_filter(r,h,q)) return false; data.setCoefficients(juce::IIRCoefficients::makeBandPass(r,h,q)); return true; }
bool JuceIIRFilter::make_notch(double r, double h, double q) { if (!valid_filter(r,h,q)) return false; data.setCoefficients(juce::IIRCoefficients::makeNotchFilter(r,h,q)); return true; }
bool JuceIIRFilter::make_peak_filter(double r, double h, double q, double gain) { if (!valid_filter(r,h,q) || !std::isfinite(gain) || gain <= 0 || gain > 100) return false; data.setCoefficients(juce::IIRCoefficients::makePeakFilter(r,h,q,float(gain))); return true; }
bool JuceIIRFilter::process(const Ref<JuceAudioBuffer>& b, int channel) { if (b.is_null() || channel < 0 || channel >= b->get_num_channels()) return false; data.processSamples(b->native().getWritePointer(channel), b->get_num_samples()); return true; }
bool JuceSmoothedValue::apply_gain(const Ref<JuceAudioBuffer>& b) { if (b.is_null()) return false; data.applyGain(b->native(), b->get_num_samples()); return true; }
static Array midi_devices(const juce::Array<juce::MidiDeviceInfo>& devices) { Array r; for (auto& d : devices) { Dictionary v; v["identifier"]=gd_string(d.identifier); v["name"]=gd_string(d.name); r.append(v); } return r; }
Array JuceMidiInput::get_available_devices() { juce::ScopedJuceInitialiser_GUI runtime; return midi_devices(juce::MidiInput::getAvailableDevices()); }
bool JuceMidiInput::open_device(const String& id) { close_device(); error=""; device=juce::MidiInput::openDevice(juce::String::fromUTF8(id.utf8().get_data()),this); if (!device) { error="Cannot open MIDI input"; return false; } dropped.store(0); device->start(); return true; }
void JuceMidiInput::close_device() { if (device) device->stop(); device.reset(); const juce::ScopedLock lock(mutex); messages.clear(); }
void JuceMidiInput::handleIncomingMidiMessage(juce::MidiInput*, const juce::MidiMessage& m) {
    const juce::ScopedLock lock(mutex);
    if (messages.size() >= 256 || m.getRawDataSize() > 4096) { dropped.fetch_add(1); return; } messages.push_back(m);
}
Array JuceMidiInput::read_events() { std::deque<juce::MidiMessage> ready; { const juce::ScopedLock lock(mutex); ready.swap(messages); } Array r; for (auto& m : ready) r.append(JuceMidiMessage::wrap(m)); return r; }
Array JuceMidiOutput::get_available_devices() { juce::ScopedJuceInitialiser_GUI runtime; return midi_devices(juce::MidiOutput::getAvailableDevices()); }
bool JuceMidiOutput::open_device(const String& id) { close_device(); error=""; device=juce::MidiOutput::openDevice(juce::String::fromUTF8(id.utf8().get_data())); if (!device) error="Cannot open MIDI output"; return device != nullptr; }
bool JuceMidiOutput::send_message_now(const Ref<JuceMidiMessage>& m) { if (!device || m.is_null()) return false; device->sendMessageNow(m->data); return true; }
bool JuceMidiOutput::send_buffer_now(const Ref<JuceMidiBuffer>& b) { if (!device || b.is_null()) return false; device->sendBlockOfMessagesNow(b->data); return true; }
}

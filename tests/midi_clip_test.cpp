#include "midi_clip_player.h"
#include <cstdlib>
#include <iostream>
#include <cmath>
#include <new>
#include <limits>

static bool audit = false;
static int allocations = 0;
void* operator new(std::size_t n) { if (audit) ++allocations; if (auto* p = std::malloc(n ? n : 1)) return p; throw std::bad_alloc(); }
void* operator new[](std::size_t n) { return ::operator new(n); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }
static void check(bool ok, const char* text) { if (!ok) { std::cerr << text << '\n'; std::exit(1); } }
using Player = bridge::MidiClipPlayer;
static void render(Player& p, std::vector<float>& samples, int block) {
    for (size_t i = 0; i < samples.size(); i += size_t(block)) {
        float* output[] = {samples.data() + i};
        check(p.render(output, 1, int(std::min(size_t(block), samples.size() - i))), "render");
    }
}
static int first_sound(const std::vector<float>& samples) {
    for (size_t i = 0; i < samples.size(); ++i) if (std::abs(samples[i]) > 1e-9f) return int(i);
    return -1;
}
int main() {
    Player a, b;
    std::vector<Player::Note> notes{{60,1,0.01,0.1,0.8f},{64,1,0.5,0.25,0.7f},{67,1,0.5,0.5,0.8f}};
    check(a.load_clip(notes, 4) && b.load_clip(notes, 4), "clip load");
    auto invalid = notes; invalid[0].velocity = std::numeric_limits<float>::quiet_NaN();
    check(!a.load_clip(invalid, 4) && a.get_notes().size() == 3, "invalid load rollback");
    a.active.store(true); check(!a.load_clip({}, 4) && !a.prepare(48000,1), "active mutation guards"); a.active.store(false);
    check(a.prepare(48000,1) && b.prepare(48000,1), "prepare"); a.play(); b.play();
    std::vector<float> x(96000), y(96000);
    allocations = 0; audit = true; render(a,x,127); audit = false;
    check(allocations == 0, "allocation-free audio rendering");
    render(b,y,511);
    check(x == y, "clip playback independent of callback block size");
    check(first_sound(x) == 240, "note onset at exact target sample");
    for (float value : x) check(std::isfinite(value) && std::abs(value) <= 1, "bounded samples");

    Player tempo;
    check(tempo.load_clip({{60,1,2.5,0.1,1}}, 8) && tempo.prepare(48000,1), "tempo setup");
    tempo.play(); std::vector<float> second(48000); render(tempo,second,128);
    check(first_sound(second) == -1 && std::abs(tempo.published_beat.load()-2) < 1e-8, "120 BPM beat progression");
    tempo.bpm.store(60); render(tempo,second,128);
    check(first_sound(second) == 24000 && std::abs(tempo.published_beat.load()-3) < 1e-8, "live BPM preserves beat position and reschedules future notes");

    Player loop;
    check(loop.load_clip({{60,1,0.25,0.1,1}},2) && loop.prepare(48000,1), "loop setup");
    loop.play(); render(loop,x,1024);
    check(first_sound(x) == 6000 && std::abs(x[54000]) > 1e-9f, "loop events repeat on sample timeline");
    check(std::abs(loop.published_beat.load()) < 1e-8, "loop-edge position published without waiting for another callback");
    loop.looping.store(false); loop.stop(); render(loop,second,256); loop.play(); render(loop,x,256);
    check(!loop.requested_play.load(), "one-shot clip stops at end");

    Player rec;
    check(rec.load_clip({},4) && rec.prepare(48000,1), "record setup");
    rec.play(); rec.recording.store(true);
    check(rec.queue_input({1,1,60,0.75f}), "record note-on queue");
    render(rec,second,128); // Two beats at 120 BPM.
    check(rec.queue_input({2,1,60,0}), "record note-off queue");
    std::vector<float> block(128); render(rec,block,128);
    Player::Recorded take;
    check(rec.read_recorded(take) && take.note == 60 && take.start == 0 && std::abs(take.length-2) < 1e-8, "native note recording in beats");
    check(!rec.read_recorded(take), "record queue drains once");
    check(rec.queue_input({1,1,64,1}), "held record note"); render(rec,block,128);
    rec.device_stopped();
    check(rec.read_recorded(take) && take.note == 64 && take.length > 0, "stopping finalizes held recorded notes");

    Player overflow;
    check(overflow.prepare(48000,1), "overflow setup");
    for (int i=0;i<1023;++i) check(overflow.queue_input({1,1,60,1}), "fill input queue");
    check(!overflow.queue_input({2,1,60,0}), "queue overflow reported");
    render(overflow,block,128);
    check(first_sound(block) == -1 && overflow.input_drops.load() == 1, "overflow panic prevents stranded note-on");
    check(overflow.queue_input({1,1,60,1}) && overflow.queue_input({3,1,64,127}), "sustain setup");
    render(overflow,second,128);
    check(overflow.queue_input({2,1,60,0}), "sustain release key"); render(overflow,second,128);
    check(first_sound(second) >= 0, "pedal sustains live voice");
    check(overflow.queue_input({3,1,64,0}), "pedal off"); render(overflow,second,128); render(overflow,second,128);
    check(first_sound(second) == -1, "pedal release completes envelope");
    overflow.metronome.store(true); overflow.play(); render(overflow,block,128);
    check(first_sound(block) >= 0, "native metronome click");
    overflow.stop(); render(overflow,block,128); check(first_sound(block) == -1, "stop silences metronome and voices");
    std::cout << "MIDI clip: exact sample onset, block invariance, live tempo, looping, recording, sustain, overflow and allocation checks passed\n";
}

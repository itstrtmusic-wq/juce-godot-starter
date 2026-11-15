#include "midi_clip_player.h"
#include <cstdlib>
#include <iostream>
#include <cmath>
#include <new>
#include <limits>
#include <memory>

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
    // Each player owns bounded queues; keep fixtures off Windows' 1 MiB stack.
    auto a_storage = std::make_unique<Player>(), b_storage = std::make_unique<Player>();
    auto& a = *a_storage; auto& b = *b_storage;
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

    auto tempo_storage = std::make_unique<Player>(); auto& tempo = *tempo_storage;
    check(tempo.load_clip({{60,1,2.5,0.1,1}}, 8) && tempo.prepare(48000,1), "tempo setup");
    tempo.play(); std::vector<float> second(48000); render(tempo,second,128);
    check(first_sound(second) == -1 && std::abs(tempo.published_beat.load()-2) < 1e-8, "120 BPM beat progression");
    tempo.bpm.store(60); render(tempo,second,128);
    check(first_sound(second) == 24000 && std::abs(tempo.published_beat.load()-3) < 1e-8, "live BPM preserves beat position and reschedules future notes");

    auto loop_storage = std::make_unique<Player>(); auto& loop = *loop_storage;
    check(loop.load_clip({{60,1,0.25,0.1,1}},2) && loop.prepare(48000,1), "loop setup");
    loop.play(); render(loop,x,1024);
    check(first_sound(x) == 6000 && std::abs(x[54000]) > 1e-9f, "loop events repeat on sample timeline");
    check(std::abs(loop.published_beat.load()) < 1e-8, "loop-edge position published without waiting for another callback");
    loop.looping.store(false); loop.stop(); render(loop,second,256); loop.play(); render(loop,x,256);
    check(!loop.requested_play.load(), "one-shot clip stops at end");

    auto rec_storage = std::make_unique<Player>(); auto& rec = *rec_storage;
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

    auto overflow_storage = std::make_unique<Player>(); auto& overflow = *overflow_storage;
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
    auto mixer_storage = std::make_unique<Player>(); auto& mixed = *mixer_storage;
    check(mixed.prepare(48000,2), "stereo mixer prepare");
    mixed.channel_settings[0].pan.store(-1);
    check(mixed.queue_input({1,1,60,1}), "pan source");
    float l[512] = {}, r[512] = {}; float* stereo[] = {l,r};
    check(mixed.render(stereo,2,512), "stereo render");
    bool left_sound = false;
    for(int i=0;i<512;++i){left_sound |= std::abs(l[i])>0.00001f;check(r[i]==0,"hard-left balance silences right");}
    check(left_sound && mixed.channel_settings[0].peak.load()>0, "channel peak metering");
    mixed.channel_settings[0].mute.store(true);
    check(mixed.render(stereo,2,512), "mute render");
    for(int i=256;i<512;++i)check(l[i]==0&&r[i]==0,"muted channel is silent after its 5 ms ramp");
    mixed.channel_settings[0].mute.store(false);
    mixed.channel_settings[1].solo.store(true);
    check(mixed.queue_input({1,2,64,0.8f})&&mixed.render(stereo,2,512),"solo render");
    check(mixed.channel_settings[0].peak.load()==0&&mixed.channel_settings[1].peak.load()>0,"solo excludes other channels");
    for(int kind=4;kind<=7;++kind){
        auto drum=std::make_unique<Player>();
        drum->channel_settings[0].waveform.store(kind);
        check(drum->prepare(48000,1)&&drum->queue_input({1,1,36,1}),"drum prepare");
        allocations=0;audit=true;render(*drum,second,128);audit=false;
        check(allocations==0&&first_sound(second)>=0,"allocation-free percussion produces sound");
        for(float value:second)check(std::isfinite(value)&&std::abs(value)<=1,"percussion bounded");
        check(std::abs(second.back())<1e-8f,"percussion terminates without requiring a note-off");
    }
    std::cout << "MIDI clip: exact sample onset, block invariance, live tempo, looping, recording, sustain, overflow and allocation checks passed\n";
}

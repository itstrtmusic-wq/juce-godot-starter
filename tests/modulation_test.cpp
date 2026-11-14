#include "dsp_graph.h"
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <new>

static bool audit = false;
static int allocations = 0;
void* operator new(std::size_t count) { if (audit) ++allocations; if (auto* p = std::malloc(count ? count : 1)) return p; throw std::bad_alloc(); }
void* operator new[](std::size_t count) { return ::operator new(count); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }
static void check(bool ok, const char* message) { if (!ok) { std::cerr << message << '\n'; std::exit(1); } }
int main() {
    bridge::DSPGraph g;
    check(g.add_node("level", "gain") && g.add_node("control", "constant"), "modulation nodes");
    check(g.set_parameter("control", "value", 0.5f) && g.set_parameter("level", "gain_db", -12.0f), "base settings");
    check(g.connect("input", "level", 1) && g.connect("level", "output", 1), "audio path");
    check(g.connect_parameter("control", "level", "gain_db", 12, 0, 0), "parameter path");
    check(!g.connect_parameter("control", "level", "gain_db", 12, 0, 0), "duplicate rejected");
    check(g.prepare(48000, 128, 1), "prepare modulated graph");
    juce::AudioBuffer<float> block(1, 1024);
    juce::FloatVectorOperations::fill(block.getWritePointer(0), 1, 1024);
    { const float* input[] = {block.getReadPointer(0)}; float* output[] = {block.getWritePointer(0)};
      check(g.render(input,1,output,1,128), "first-block modulation");
      check(g.find("level")->parameter("gain_db")->effective.load() == -6, "parameter dependencies order sources before targets on the first block"); }
    juce::FloatVectorOperations::fill(block.getWritePointer(0), 1, 1024);
    check(g.process_offline(block), "modulated render");
    auto* parameter = g.find("level")->parameter("gain_db");
    check(parameter->value.load() == -12 && parameter->effective.load() == -6, "base and effective parameter separation");
    check(std::abs(block.getSample(0, 1023) - std::pow(10.0f, -6.0f / 20)) < 0.0001f, "numerical modulation result");
    g.active.store(true);
    check(!g.disconnect_parameter("control", "level", "gain_db"), "active topology guard");
    check(g.set_parameter("control", "value", 100), "live control update");
    float source[128] = {}; float output[128] = {}; const float* inputs[] = {source}; float* outputs[] = {output};
    audit = true; const bool rendered = g.render(inputs, 1, outputs, 1, 128); audit = false;
    check(rendered && allocations == 0, "allocation-free native modulation render");
    check(parameter->effective.load() == 24, "effective range clamp");
    check(g.set_parameter("control", "value", -100), "negative modulation");
    check(g.render(inputs, 1, outputs, 1, 128) && parameter->effective.load() == -100, "lower range clamp");
    g.active.store(false);
    check(g.remove_node("control") && g.find("level")->modulations.empty(), "source removal cleans parameter routes");
    check(g.prepare(48000,128,1) && g.render(inputs,1,outputs,1,128), "graph remains valid after source removal");

    bridge::DSPGraph cycles;
    check(cycles.add_node("a","gain") && cycles.add_node("b","gain") && cycles.connect("a","b",1), "mixed-cycle nodes");
    check(!cycles.connect_parameter("b","a","gain_db",1,0,0), "mixed audio/parameter cycle rejected");
    check(cycles.find("a")->modulations.empty(), "rejected route rolls back");
    check(cycles.connect_parameter("a","b","gain_db",1,0,1), "stereo modulation route");
    check(!cycles.prepare(48000,128,1), "missing source channel rejected");
    check(cycles.prepare(48000,128,2), "stereo source channel accepted");
    check(!cycles.connect_parameter("a","a","gain_db",1,0,0), "self-route rejected");

    bridge::DSPGraph lfo;
    check(lfo.add_node("slow","lfo") && lfo.connect("slow","output",1) && lfo.prepare(48000,128,1), "LFO setup");
    juce::AudioBuffer<float> wave(1,48000); wave.clear();
    check(lfo.process_offline(wave), "LFO render");
    check(std::abs(wave.getRMSLevel(0,0,48000) - std::sqrt(0.5f)) < 0.001f, "LFO amplitude/frequency behavior");
    check(std::abs(wave.getSample(0,12000)) > 0.99f && std::abs(wave.getSample(0,24000)) < 0.001f, "LFO quarter/half-cycle timing");

    bridge::DSPGraph replacement;
    check(replacement.add_node("source","constant") && replacement.set_parameter("source","value",0.25f) && replacement.connect("source","output",1), "replacement setup");
    g.active.store(true); check(!g.replace_with(replacement), "active patch replacement rejected"); g.active.store(false);
    check(g.replace_with(replacement) && !g.find("level") && g.find("source"), "transactional graph replacement");
    check(!g.process_offline(wave), "replaced graph requires preparation");
    check(g.prepare(48000,128,1) && g.process_offline(wave) && wave.getSample(0,47999)==0.25f, "replacement owns correct output node");
    std::cout << "Modulation: routing, exact gain, clamping, live updates, cycle rollback, channel validation, LFO timing, replacement and allocation checks passed\n";
}

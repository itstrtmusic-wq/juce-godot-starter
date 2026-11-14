#include "dsp_graph.h"
#include <algorithm>
#include <cmath>
#include <functional>
#include <unordered_map>

namespace bridge {
const std::vector<std::string>& DSPGraph::supported_types() {
    static const std::vector<std::string> types = {"gain","mix","constant","add","multiply","tanh","clip","abs","sin","oscillator","low_pass","high_pass","band_pass","notch","peak","low_shelf","high_shelf","delay","reverb","compressor","adsr","lfo","chorus","phaser","limiter","noise_gate"}; return types;
}
DSPGraph::Node::Node(const std::string& name, const std::string& kind) : id(name), type(kind) {
    auto p = [&](const char* n, float lo, float hi, float initial) { parameters.push_back(std::make_unique<Parameter>(n,lo,hi,initial)); };
    if (type != "input" && type != "output") p("bypass",0,1,0);
    if (type == "lfo") { p("rate_hz",0.01f,40,1); p("amplitude",0,1,1); p("offset",-1,1,0); p("waveform",0,3,0); }
    if (type == "chorus") { p("rate_hz",0.01f,99,1); p("depth",0,1,0.25f); p("centre_delay_ms",1,100,7); p("feedback",-0.99f,0.99f,0); p("mix",0,1,0.5f); }
    if (type == "phaser") { p("rate_hz",0.01f,99,1); p("depth",0,1,0.5f); p("centre_frequency",20,20000,1300); p("feedback",-0.99f,0.99f,0); p("mix",0,1,0.5f); }
    if (type == "limiter") { p("threshold_db",-100,0,-1); p("release_ms",0.01f,5000,100); }
    if (type == "noise_gate") { p("threshold_db",-100,0,-60); p("ratio",1,100,10); p("attack_ms",0.01f,1000,5); p("release_ms",0.01f,5000,100); }
    if (type == "compressor") { p("threshold_db",-100,0,-18); p("ratio",1,100,4); p("attack_ms",0.01f,1000,10); p("release_ms",0.01f,5000,100); }
    if (type == "adsr") { p("attack",0,10,0.01f); p("decay",0,10,0.1f); p("sustain",0,1,0.8f); p("release",0,10,0.2f); p("gate",0,1,0); }
    if (type == "gain") p("gain_db",-100,24,0);
    if (type == "constant" || type == "add") p("value",-100,100,0);
    if (type == "multiply") p("value",-100,100,1);
    if (type == "tanh") p("drive",0,100,1);
    if (type == "clip") p("threshold",0.001f,100,1);
    if (type == "oscillator") { p("frequency",0,20000,440); p("gain",0,1,0.1f); p("waveform",0,3,0); }
    if (type == "low_pass" || type == "high_pass" || type == "band_pass" || type == "notch" || type == "peak" || type == "low_shelf" || type == "high_shelf") { p("frequency",10,20000,1000); p("q",0.1f,20,0.70710678f); p("gain_db",-48,24,0); }
    if (type == "delay") { p("delay_ms",0,2000,250); p("feedback",-0.99f,0.99f,0.35f); p("mix",0,1,0.5f); }
    if (type == "reverb") { p("room_size",0,1,0.5f); p("damping",0,1,0.5f); p("wet_level",0,1,0.33f); p("dry_level",0,1,0.4f); p("width",0,1,1); p("freeze_mode",0,1,0); }
    if (type == "oscillator" || type == "lfo") oscillator.initialise([this](float x) {
        if (waveform == 1) return 2.0f / juce::MathConstants<float>::pi * std::asin(std::sin(x));
        if (waveform == 2) return x / juce::MathConstants<float>::pi;
        if (waveform == 3) return x < 0 ? -1.0f : 1.0f;
        return std::sin(x);
    });
}
DSPGraph::Parameter* DSPGraph::Node::parameter(std::string_view name) const { for (auto& p : parameters) if (name == p->name) return p.get(); return nullptr; }
float DSPGraph::Node::value(const char* name) const { auto* p = parameter(name); return p ? p->effective.load(std::memory_order_relaxed) : 0.0f; }
DSPGraph::DSPGraph() { nodes.push_back(std::make_unique<Node>("input","input")); nodes.push_back(std::make_unique<Node>("output","output")); output_node=nodes.back().get(); build_order(); }
DSPGraph::Node* DSPGraph::find(const std::string& id) const { for (auto& n : nodes) if (n->id == id) return n.get(); return nullptr; }
bool DSPGraph::add_node(const std::string& id, const std::string& type) {
    error.clear();
    if (active.load()) return fail("Stop audio before editing nodes");
    if (id.empty() || id.size() > 128 || find(id) || nodes.size() >= 64) return fail("Invalid, duplicate or excessive node ID (64 total nodes maximum)");
    if (std::find(supported_types().begin(), supported_types().end(), type) == supported_types().end()) return fail("Unsupported node type");
    nodes.push_back(std::make_unique<Node>(id,type)); prepared = false; return build_order();
}
bool DSPGraph::remove_node(const std::string& id) {
    error.clear(); if (active.load()) return fail("Stop audio before editing nodes");
    auto* target = find(id); if (!target || id == "input" || id == "output") return fail("Cannot remove node");
    for (auto& n : nodes) n->inputs.erase(std::remove_if(n->inputs.begin(),n->inputs.end(),[&](const Edge& e){return e.source == target;}),n->inputs.end());
    for (auto& n : nodes) n->modulations.erase(std::remove_if(n->modulations.begin(), n->modulations.end(), [&](const Modulation& m){return m.source == target;}), n->modulations.end());
    nodes.erase(std::remove_if(nodes.begin(),nodes.end(),[&](auto& n){return n.get()==target;}),nodes.end()); prepared=false; return build_order();
}
bool DSPGraph::build_order() {
    std::vector<Node*> result; std::unordered_map<Node*,int> marks;
    std::function<bool(Node*)> visit = [&](Node* n) { if (marks[n] == 1) return false; if (marks[n] == 2) return true; marks[n]=1; for (auto& e : n->inputs) if (!visit(e.source)) return false; for (auto& m : n->modulations) if (!visit(m.source)) return false; marks[n]=2; result.push_back(n); return true; };
    for (auto& n : nodes) if (!visit(n.get())) return fail("Feedback cycles are not supported; use a delay node's internal feedback parameter");
    order.swap(result); return true;
}
bool DSPGraph::connect(const std::string& src, const std::string& dst, float gain_value) {
    error.clear(); if (active.load()) return fail("Stop audio before editing connections");
    auto* s=find(src); auto* d=find(dst);
    if (!s || !d || s==d || src=="output" || dst=="input" || !std::isfinite(gain_value) || std::abs(gain_value)>100) return fail("Invalid connection");
    size_t total=0; for(auto& n:nodes) total+=n->inputs.size()+n->modulations.size(); if(total>=256) return fail("Connection limit reached");
    for(auto& e:d->inputs) if(e.source==s) return fail("Connection already exists");
    d->inputs.push_back({s,gain_value}); if(!build_order()) {d->inputs.pop_back(); return false;} prepared=false; return true;
}
bool DSPGraph::disconnect(const std::string& src, const std::string& dst) {
    error.clear(); if(active.load()) return fail("Stop audio before editing connections"); auto* s=find(src);auto* d=find(dst); if(!s||!d)return fail("Unknown node");
    auto it=std::find_if(d->inputs.begin(),d->inputs.end(),[&](const Edge& e){return e.source==s;}); if(it==d->inputs.end())return fail("Connection does not exist");d->inputs.erase(it);prepared=false;return build_order();
}
bool DSPGraph::connect_parameter(const std::string& source, const std::string& destination, const std::string& parameter, float depth, float offset, int channel) {
    error.clear();
    if (active.load()) return fail("Stop audio before editing modulation connections");
    auto* src = find(source); auto* dst = find(destination);
    auto* target = dst ? dst->parameter(parameter) : nullptr;
    if (!src || !dst || src == dst || source == "output" || !target || parameter == "waveform" || channel < 0 || channel > 1 || !std::isfinite(depth) || !std::isfinite(offset) || std::abs(depth) > 1000000 || std::abs(offset) > 1000000)
        return fail("Invalid modulation connection, range or target parameter");
    size_t total = 0; for (auto& n : nodes) total += n->inputs.size() + n->modulations.size();
    if (total >= 256) return fail("Connection limit reached");
    for (auto& m : dst->modulations) if (m.source == src && m.target == target) return fail("Modulation connection already exists");
    dst->modulations.push_back({src, target, depth, offset, channel});
    if (!build_order()) { dst->modulations.pop_back(); return false; }
    prepared = false; return true;
}
bool DSPGraph::disconnect_parameter(const std::string& source, const std::string& destination, const std::string& parameter) {
    error.clear(); if (active.load()) return fail("Stop audio before editing modulation connections");
    auto* src = find(source); auto* dst = find(destination); auto* target = dst ? dst->parameter(parameter) : nullptr;
    if (!src || !dst || !target) return fail("Unknown modulation endpoint");
    auto it = std::find_if(dst->modulations.begin(), dst->modulations.end(), [&](const Modulation& m){ return m.source == src && m.target == target; });
    if (it == dst->modulations.end()) return fail("Modulation connection does not exist");
    dst->modulations.erase(it); prepared = false; return build_order();
}
bool DSPGraph::replace_with(DSPGraph& replacement) {
    if (active.load() || replacement.active.load()) return fail("Stop audio before replacing a patch");
    if (&replacement == this) return fail("Cannot replace a graph with itself");
    nodes.swap(replacement.nodes); order.swap(replacement.order); std::swap(output_node, replacement.output_node);
    // A patch contains settings/topology, not live processor state or device configuration.
    prepared = false; max_block = channels = 0;
    replacement.prepared = false; replacement.max_block = replacement.channels = 0;
    error.clear(); return true;
}
bool DSPGraph::set_parameter(const std::string& id, const std::string& name, float v) {
    error.clear();auto* n=find(id);auto* p=n?n->parameter(name):nullptr;
    if(!p||!std::isfinite(v)||v<p->low||v>p->high) return fail("Unknown parameter or out-of-range value");
    if(name=="waveform" && std::floor(v)!=v) return fail("Waveform must be an integer from 0 to 3");
    p->value.store(v,std::memory_order_relaxed);return true;
}
std::vector<std::string> DSPGraph::node_ids() const {std::vector<std::string> r;for(auto& n:nodes)r.push_back(n->id);return r;}
bool DSPGraph::prepare(double sample_rate,int block,int count,bool report_error) {
    if(report_error) error.clear();
    if(!std::isfinite(sample_rate)||sample_rate<8000||sample_rate>384000||block<1||block>8192||count<1||count>2)return report_error ? fail("Invalid sample rate, block size or channel count") : false;
    for (auto& n : nodes) for (auto& m : n->modulations) if (m.channel >= count)
        return report_error ? fail("Modulation source channel is unavailable in this channel configuration") : false;
    int64_t total=int64_t(nodes.size())*block*count;
    for(auto& n:nodes)if(n->type=="delay")total+=int64_t(sample_rate*2+2)*count;
    for(auto& n:nodes)if(n->type=="chorus")total+=int64_t(sample_rate*0.13+2)*count+block;
    for(auto& n:nodes)if(n->type=="phaser")total+=block;
    if(total>16000000)return report_error ? fail("Graph exceeds 64 MB buffer limit") : false;
    rate=sample_rate;max_block=block;channels=count;
    for(auto& n:nodes) {
        for (auto& p : n->parameters) p->effective.store(p->value.load(std::memory_order_relaxed), std::memory_order_relaxed);
        n->buffer.setSize(count,block);n->buffer.clear();
        for(auto& filter:n->filters)filter.reset();
        n->old_frequency=-1;n->old_q=-1;n->old_gain=-1000;
        n->gain.reset(rate,0.005);n->gain.setCurrentAndTargetValue(juce::Decibels::decibelsToGain(n->value("gain_db")));
        if(n->type=="adsr"){n->envelope.setSampleRate(rate);n->envelope.reset();n->old_gate=false;}
        if(n->type=="compressor"){n->compressor.prepare({rate,juce::uint32(block),juce::uint32(count)});n->compressor.reset();}
        if(n->type=="chorus") n->chorus.prepare({rate,juce::uint32(block),juce::uint32(count)});
        if(n->type=="phaser") n->phaser.prepare({rate,juce::uint32(block),juce::uint32(count)});
        if(n->type=="limiter") n->limiter.prepare({rate,juce::uint32(block),juce::uint32(count)});
        if(n->type=="noise_gate") n->noise_gate.prepare({rate,juce::uint32(block),juce::uint32(count)});
        if(n->type=="reverb"){n->reverb.setSampleRate(rate);n->reverb.reset();}
        if(n->type=="delay"){n->delay.setSize(count,int(rate*2)+2);n->delay.clear();n->delay_cursor=0;}
        if(n->type=="oscillator" || n->type=="lfo"){n->waveform=int(n->value("waveform"));n->oscillator.prepare({rate,juce::uint32(block),juce::uint32(count)});n->oscillator.setFrequency(n->value(n->type=="lfo" ? "rate_hz" : "frequency"),true);}
    }
    prepared=true;return true;
}
bool DSPGraph::reset() { if(active.load())return fail("Stop audio before resetting graph state");if(!prepared)return fail("Prepare the graph first");return prepare(rate,max_block,channels); }
void DSPGraph::run_node(Node& n,int samples) noexcept {
    const auto& type=n.type;
    if(n.value("bypass")>=0.5f)return;
    if(type=="adsr"){
        n.envelope.setParameters({n.value("attack"),n.value("decay"),n.value("sustain"),n.value("release")});
        const bool gate=n.value("gate")>=0.5f;if(gate!=n.old_gate){if(gate)n.envelope.noteOn();else n.envelope.noteOff();n.old_gate=gate;}
        if(n.inputs.empty())for(int ch=0;ch<channels;++ch)juce::FloatVectorOperations::fill(n.buffer.getWritePointer(ch),1,samples);
        n.envelope.applyEnvelopeToBuffer(n.buffer,0,samples);
    } else if(type=="compressor"){
        n.compressor.setThreshold(n.value("threshold_db"));n.compressor.setRatio(n.value("ratio"));n.compressor.setAttack(n.value("attack_ms"));n.compressor.setRelease(n.value("release_ms"));
        auto block=juce::dsp::AudioBlock<float>(n.buffer).getSubBlock(0,size_t(samples));juce::dsp::ProcessContextReplacing<float> context(block);n.compressor.process(context);
    } else if(type=="chorus" || type=="phaser" || type=="limiter" || type=="noise_gate") {
        auto block=juce::dsp::AudioBlock<float>(n.buffer).getSubBlock(0,size_t(samples)); juce::dsp::ProcessContextReplacing<float> context(block);
        if(type=="chorus") {n.chorus.setRate(n.value("rate_hz"));n.chorus.setDepth(n.value("depth"));n.chorus.setCentreDelay(n.value("centre_delay_ms"));n.chorus.setFeedback(n.value("feedback"));n.chorus.setMix(n.value("mix"));n.chorus.process(context);}
        else if(type=="phaser") {n.phaser.setRate(n.value("rate_hz"));n.phaser.setDepth(n.value("depth"));n.phaser.setCentreFrequency(std::min(n.value("centre_frequency"),float(rate*0.45)));n.phaser.setFeedback(n.value("feedback"));n.phaser.setMix(n.value("mix"));n.phaser.process(context);}
        else if(type=="limiter") {n.limiter.setThreshold(n.value("threshold_db"));n.limiter.setRelease(n.value("release_ms"));n.limiter.process(context);}
        else {n.noise_gate.setThreshold(n.value("threshold_db"));n.noise_gate.setRatio(n.value("ratio"));n.noise_gate.setAttack(n.value("attack_ms"));n.noise_gate.setRelease(n.value("release_ms"));n.noise_gate.process(context);}
    } else if(type=="gain") { n.gain.setTargetValue(juce::Decibels::decibelsToGain(n.value("gain_db")));n.gain.applyGain(n.buffer,samples); }
    else if(type=="constant"||type=="add"||type=="multiply"||type=="tanh"||type=="clip"||type=="abs"||type=="sin") {
        float v=n.value("value");const float drive=n.value("drive"),threshold=n.value("threshold");
        for(int ch=0;ch<channels;++ch){auto* dst=n.buffer.getWritePointer(ch);for(int i=0;i<samples;++i){const float x=dst[i];
            if(type=="constant")dst[i]=v;else if(type=="add")dst[i]=x+v;else if(type=="multiply")dst[i]=x*v;
            else if(type=="tanh")dst[i]=std::tanh(x*drive);else if(type=="clip")dst[i]=std::clamp(x,-threshold,threshold);else if(type=="abs")dst[i]=std::abs(x);else dst[i]=std::sin(x);
        }}
    } else if(type=="oscillator" || type=="lfo") {
        n.waveform=int(n.value("waveform"));n.oscillator.setFrequency(std::min(n.value(type=="lfo" ? "rate_hz" : "frequency"),float(rate*0.45)));
        // A source emits its oscillator independently; connect a mix node for additive synthesis.
        n.buffer.clear(0,samples);
        auto block=juce::dsp::AudioBlock<float>(n.buffer).getSubBlock(0,size_t(samples));
        juce::dsp::ProcessContextReplacing<float> context(block);n.oscillator.process(context);n.buffer.applyGain(0,samples,n.value(type=="lfo" ? "amplitude" : "gain"));
        if(type=="lfo"){const float offset=n.value("offset");for(int ch=0;ch<channels;++ch)juce::FloatVectorOperations::add(n.buffer.getWritePointer(ch),offset,samples);}
    } else if(type=="delay") {
        const int size=n.delay.getNumSamples();const int delay_samples=std::clamp(int(n.value("delay_ms")*rate/1000.0),1,size-1);
        const float feedback=n.value("feedback"),wet=n.value("mix");
        for(int i=0;i<samples;++i){const int read=(n.delay_cursor-delay_samples+size)%size;for(int ch=0;ch<channels;++ch){const float dry=n.buffer.getSample(ch,i),delayed=n.delay.getSample(ch,read);n.delay.setSample(ch,n.delay_cursor,dry+delayed*feedback);n.buffer.setSample(ch,i,dry*(1-wet)+delayed*wet);}n.delay_cursor=(n.delay_cursor+1)%size;}
    } else if(type=="reverb") {
        juce::Reverb::Parameters p;p.roomSize=n.value("room_size");p.damping=n.value("damping");p.wetLevel=n.value("wet_level");p.dryLevel=n.value("dry_level");p.width=n.value("width");p.freezeMode=n.value("freeze_mode");n.reverb.setParameters(p);
        if(channels==1)n.reverb.processMono(n.buffer.getWritePointer(0),samples);else n.reverb.processStereo(n.buffer.getWritePointer(0),n.buffer.getWritePointer(1),samples);
    } else if(type=="low_pass"||type=="high_pass"||type=="band_pass"||type=="notch"||type=="peak"||type=="low_shelf"||type=="high_shelf") {
        float hz=std::min(n.value("frequency"),float(rate*0.45)),q=n.value("q"),db=n.value("gain_db");
        if(hz!=n.old_frequency||q!=n.old_q||db!=n.old_gain){juce::IIRCoefficients c;
            if(type=="low_pass")c=juce::IIRCoefficients::makeLowPass(rate,hz,q);else if(type=="high_pass")c=juce::IIRCoefficients::makeHighPass(rate,hz,q);else if(type=="band_pass")c=juce::IIRCoefficients::makeBandPass(rate,hz,q);else if(type=="notch")c=juce::IIRCoefficients::makeNotchFilter(rate,hz,q);else if(type=="peak")c=juce::IIRCoefficients::makePeakFilter(rate,hz,q,juce::Decibels::decibelsToGain(db));else if(type=="low_shelf")c=juce::IIRCoefficients::makeLowShelf(rate,hz,q,juce::Decibels::decibelsToGain(db));else c=juce::IIRCoefficients::makeHighShelf(rate,hz,q,juce::Decibels::decibelsToGain(db));
            for(auto& f:n.filters)f.setCoefficients(c);n.old_frequency=hz;n.old_q=q;n.old_gain=db;}
        for(int ch=0;ch<channels;++ch)n.filters[ch].processSamples(n.buffer.getWritePointer(ch),samples);
    }
}
bool DSPGraph::render(const float* const* input,int in_channels,float* const* output,int out_channels,int samples) noexcept {
    if(!prepared||samples<0||samples>max_block||out_channels!=channels)return false;
    if (samples == 0) return true;
    for(auto* n:order){
        for (auto& p : n->parameters) {
            const float base = p->value.load(std::memory_order_relaxed);
            double effective = base;
            for (auto& m : n->modulations) if (m.target == p.get()) {
                const float source = m.source->buffer.getSample(m.channel, 0);
                if (std::isfinite(source)) effective += double(source) * m.depth + m.offset;
            }
            p->effective.store(float(std::clamp(effective, double(p->low), double(p->high))), std::memory_order_relaxed);
        }
        n->buffer.clear(0,samples);
        if(n->type=="input") {for(int ch=0;ch<std::min(channels,in_channels);++ch)if(input&&input[ch])n->buffer.copyFrom(ch,0,input[ch],samples);}
        else {
            if(n->type=="multiply" && !n->inputs.empty()){
                for(int ch=0;ch<channels;++ch){float* dst=n->buffer.getWritePointer(ch);for(int i=0;i<samples;++i){float product=1;for(auto& e:n->inputs)product*=e.source->buffer.getSample(ch,i)*e.gain;dst[i]=product;}}
            } else for(auto& e:n->inputs)for(int ch=0;ch<channels;++ch)n->buffer.addFrom(ch,0,e.source->buffer,ch,0,samples,e.gain);
            run_node(*n,samples);
        }
    }
    auto* result=output_node;
    for(int ch=0;ch<channels;++ch)if(output[ch])juce::FloatVectorOperations::copy(output[ch],result->buffer.getReadPointer(ch),samples);
    return true;
}
bool DSPGraph::process_offline(juce::AudioBuffer<float>& buffer) {
    error.clear();if(active.load())return fail("Cannot process offline while this graph is attached to running audio");if(!prepared||buffer.getNumChannels()!=channels)return fail("Prepare the graph with the buffer's channel count first");
    for(int offset=0;offset<buffer.getNumSamples();offset+=max_block){const int count=std::min(max_block,buffer.getNumSamples()-offset);const float* in[2]={};float* out[2]={};for(int ch=0;ch<channels;++ch){out[ch]=buffer.getWritePointer(ch,offset);in[ch]=out[ch];}if(!render(in,channels,out,channels,count))return false;}return true;
}
}

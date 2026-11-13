#include "dsp_graph.h"
#include <iostream>
#include <cstdlib>
#include <cmath>
#include <limits>
#include <new>
static bool audit=false;
static int allocations=0;
void* operator new(std::size_t n){if(audit)++allocations;if(auto* p=std::malloc(n?n:1))return p;throw std::bad_alloc();}
void* operator new[](std::size_t n){return ::operator new(n);}
void operator delete(void* p) noexcept {std::free(p);}
void operator delete[](void* p) noexcept {std::free(p);}
void operator delete(void* p,std::size_t) noexcept {std::free(p);}
void operator delete[](void* p,std::size_t) noexcept {std::free(p);}
static void check(bool condition,const char* message){if(!condition){std::cerr<<message<<'\n';std::exit(1);}}
int main(){
    bridge::DSPGraph graph;
    check(graph.add_node("level","gain"),"add gain");
    check(graph.connect("input","level",1),"connect input");
    check(graph.connect("level","output",1),"connect output");
    check(graph.set_parameter("level","gain_db",-6.0205999f),"set gain");
    check(!graph.set_parameter("level","typo",1),"unknown parameter rejected");
    check(!graph.set_parameter("level","gain_db",std::numeric_limits<float>::quiet_NaN()),"NaN rejected");
    check(graph.prepare(48000,128,2),"prepare");
    juce::AudioBuffer<float> buffer(2,1000);for(int ch=0;ch<2;++ch)for(int i=0;i<1000;++i)buffer.setSample(ch,i,1);
    check(graph.process_offline(buffer),"offline multi-block process");
    check(std::abs(buffer.getSample(0,999)-0.5f)<0.0001f,"gain numerical result");
    graph.active.store(true);
    check(!graph.add_node("blocked","mix"),"active topology edit rejected");
    check(!graph.reset(),"active reset rejected");
    check(!graph.process_offline(buffer),"active offline process rejected");
    check(graph.set_parameter("level","gain_db",0),"active scalar update accepted");
    float l[128]={},r[128]={};const float* in[]={l,r};float* out[]={l,r};
    audit=true;const bool rendered=graph.render(in,2,out,2,128);audit=false;
    check(rendered,"native render");check(allocations==0,"render allocated via new");graph.active.store(false);
    check(graph.add_node("a","mix")&&graph.add_node("b","mix"),"cycle nodes");
    check(graph.connect("a","b",1),"first cycle edge");check(!graph.connect("b","a",1),"cycle rejected");
    check(graph.prepare(48000,128,2),"graph valid after rejected cycle");
    bridge::DSPGraph delay;
    check(delay.add_node("echo","delay")&&delay.connect("input","echo",1)&&delay.connect("echo","output",1),"delay topology");
    check(delay.set_parameter("echo","delay_ms",10)&&delay.set_parameter("echo","mix",1)&&delay.set_parameter("echo","feedback",0.5f),"delay parameters");
    check(delay.prepare(48000,64,1),"delay prepare");juce::AudioBuffer<float> impulse(1,1500);impulse.clear();impulse.setSample(0,0,1);
    check(delay.process_offline(impulse),"delay process");check(impulse.getSample(0,0)==0,"delay wet input");check(std::abs(impulse.getSample(0,480)-1)<0.00001f,"first echo");check(std::abs(impulse.getSample(0,960)-0.5f)<0.00001f,"feedback echo");
    bridge::DSPGraph filter;
    for(const auto& type:bridge::DSPGraph::supported_types()){
        bridge::DSPGraph g;check(g.add_node("fx",type)&&g.connect("input","fx",1)&&g.connect("fx","output",1),"node topology");
        check(g.prepare(48000,128,2),"node prepare");float a[128]={},b[128]={};a[0]=b[0]=1;const float* ins[]={a,b};float* outs[]={a,b};
        allocations=0;audit=true;const bool ok=g.render(ins,2,outs,2,128);audit=false;check(ok,"node render");check(allocations==0,"node render allocated via new");
        for(int i=0;i<128;++i)check(std::isfinite(a[i])&&std::isfinite(b[i]),"node non-finite output");
    }
    bridge::DSPGraph parallel;
    check(parallel.add_node("dry","mix")&&parallel.add_node("wet","mix"),"parallel nodes");check(parallel.connect("input","dry",0.25f)&&parallel.connect("input","wet",0.75f)&&parallel.connect("dry","output",1)&&parallel.connect("wet","output",1),"parallel routing");check(parallel.prepare(48000,64,1),"parallel prepare");juce::AudioBuffer<float> one(1,1);one.setSample(0,0,1);check(parallel.process_offline(one)&&std::abs(one.getSample(0,0)-1)<0.00001f,"parallel sum");
    bridge::DSPGraph modulation;
    check(modulation.add_node("a","constant")&&modulation.add_node("b","constant")&&modulation.add_node("product","multiply"),"modulation nodes");
    check(modulation.set_parameter("a","value",0.5f)&&modulation.set_parameter("b","value",0.25f),"constant values");
    check(modulation.connect("a","product",1)&&modulation.connect("b","product",1)&&modulation.connect("product","output",1),"product routing");
    check(modulation.prepare(48000,64,1),"product prepare");one.setSample(0,0,0);check(modulation.process_offline(one)&&std::abs(one.getSample(0,0)-0.125f)<0.00001f,"sample-wise multiplication");
    bridge::DSPGraph oscillator;
    check(oscillator.add_node("osc","oscillator")&&oscillator.connect("osc","output",1)&&oscillator.prepare(48000,128,1),"oscillator setup");
    juce::AudioBuffer<float> wave(1,48000);wave.clear();check(oscillator.process_offline(wave),"oscillator render");int crossings=0;for(int i=1;i<48000;++i)if(wave.getSample(0,i-1)<=0&&wave.getSample(0,i)>0)++crossings;check(std::abs(crossings-440)<=1,"oscillator frequency");
    bridge::DSPGraph envelope;
    check(envelope.add_node("env","adsr")&&envelope.connect("env","output",1)&&envelope.set_parameter("env","gate",1)&&envelope.prepare(48000,128,1),"envelope setup");
    juce::AudioBuffer<float> env(1,48000);env.clear();check(envelope.process_offline(env),"envelope render");check(std::abs(env.getSample(0,47999)-0.8f)<0.001f,"envelope sustain");check(envelope.set_parameter("env","gate",0)&&envelope.process_offline(env),"envelope release");check(env.getSample(0,47999)==0,"envelope release reaches silence");
    std::cout<<"DSP graph: numerical gain, block splitting, parallel routing, cycle rejection, active ownership, delay feedback, all node types and render allocation checks passed\n";
}

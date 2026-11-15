#include "juce_dsp_network.h"
namespace godot {
static std::string native_string(const String& s) {return s.utf8().get_data();}
PackedStringArray JuceDSPNetwork::get_supported_node_types() const {PackedStringArray r;for(auto& type:bridge::DSPGraph::supported_types())r.append(String::utf8(type.c_str()));return r;}
bool JuceDSPNetwork::add_node(const String& id,const String& type){return graph.add_node(native_string(id),native_string(type));}
bool JuceDSPNetwork::remove_node(const String& id){return graph.remove_node(native_string(id));}
bool JuceDSPNetwork::connect_nodes(const String& src,const String& dst,float gain){return graph.connect(native_string(src),native_string(dst),gain);}
bool JuceDSPNetwork::disconnect_nodes(const String& src,const String& dst){return graph.disconnect(native_string(src),native_string(dst));}
PackedStringArray JuceDSPNetwork::get_node_ids() const {PackedStringArray r;for(auto& id:graph.node_ids())r.append(String::utf8(id.c_str()));return r;}
bool JuceDSPNetwork::set_parameter(const String& id,const String& parameter,float value){return graph.set_parameter(native_string(id),native_string(parameter),value);}
Dictionary JuceDSPNetwork::get_parameters(const String& id) const {Dictionary r;auto* n=graph.find(native_string(id));if(n)for(auto& p:n->parameters)r[p->name]=p->value.load(std::memory_order_relaxed);return r;}
Array JuceDSPNetwork::get_nodes() const {Array result;for(const auto& id:graph.node_ids()){auto* n=graph.find(id);Dictionary item;item["id"]=String::utf8(id.c_str());item["type"]=String::utf8(n->type.c_str());Dictionary parameters;for(auto& p:n->parameters){Dictionary info;info["value"]=p->value.load(std::memory_order_relaxed);info["min"]=p->low;info["max"]=p->high;parameters[p->name]=info;}item["parameters"]=parameters;result.append(item);}return result;}
Array JuceDSPNetwork::get_connections() const {Array result;for(const auto& id:graph.node_ids()){auto* n=graph.find(id);for(const auto& edge:n->inputs){Dictionary item;item["source"]=String::utf8(edge.source->id.c_str());item["destination"]=String::utf8(id.c_str());item["gain"]=edge.gain;result.append(item);}}return result;}
bool JuceDSPNetwork::prepare(double rate,int size,int channels){if(graph.active.load())return false;return graph.prepare(rate,size,channels);}
PackedStringArray JuceAudioDeviceManager::device_names(bool input){PackedStringArray r;const auto& types=devices.getAvailableDeviceTypes();if(!types.isEmpty()){auto* type=types.getFirst();type->scanForDevices();for(auto& name:type->getDeviceNames(input))r.append(gd_string(name));}return r;}
bool JuceAudioDeviceManager::set_network(const Ref<JuceDSPNetwork>& value){error="";if(owns_graph||running.load()){error="Stop audio before replacing the network";return false;}sequencer.unref();network=value;return true;}
bool JuceAudioDeviceManager::set_sequencer(const Ref<JuceMidiSequencer>& value){error="";if(owns_graph||running.load()){error="Stop audio before replacing the sequencer";return false;}network.unref();sequencer=value;return true;}
bool JuceAudioDeviceManager::start_audio(const String& output,double rate,int size,const String& input,bool enable_input){
    stop_audio();error="";
    if(network.is_null()&&sequencer.is_null()){error="Set a DSP network or MIDI sequencer before starting audio";return false;}
    if(sequencer.is_valid()&&enable_input){error="MIDI sequencer output does not accept live audio input";return false;}
    if(!valid_rate(rate)||size<16||size>8192){error="Invalid sample rate or buffer size";return false;}
    bool expected=false;
    auto& active=sequencer.is_valid()?sequencer->engine.active:network->graph.active;
    if(!active.compare_exchange_strong(expected,true)){error="Audio source already belongs to another running device manager";return false;}
    owns_graph=true;
    juce::AudioDeviceManager::AudioDeviceSetup setup;setup.outputDeviceName=juce::String::fromUTF8(output.utf8().get_data());setup.inputDeviceName=juce::String::fromUTF8(input.utf8().get_data());setup.sampleRate=rate;setup.bufferSize=size;setup.useDefaultInputChannels=enable_input;setup.useDefaultOutputChannels=true;
    auto failure=devices.initialise(enable_input?2:0,2,nullptr,false,{},&setup);
    if(failure.isNotEmpty())error=gd_string(failure);
    else if(devices.getCurrentAudioDevice()==nullptr)error="No audio device is available";
    if(!error.is_empty()){stop_audio();return false;}
    devices.addAudioCallback(this);
    if(!running.load()){error="Cannot prepare DSP network for the device; check graph limits";stop_audio();return false;}
    return true;
}
void JuceAudioDeviceManager::stop_audio(){devices.removeAudioCallback(this);devices.closeAudioDevice();running.store(false);peak.store(0);if(owns_graph){if(network.is_valid())network->graph.active.store(false);if(sequencer.is_valid()){sequencer->engine.device_stopped();sequencer->engine.active.store(false);}owns_graph=false;}}
void JuceAudioDeviceManager::audioDeviceAboutToStart(juce::AudioIODevice* device){
    channels=device->getActiveOutputChannels().countNumberOfSetBits();
    running.store(sequencer.is_valid()?sequencer->engine.prepare(device->getCurrentSampleRate(),channels,true):network.is_valid()&&network->graph.prepare(device->getCurrentSampleRate(),device->getCurrentBufferSizeSamples(),channels,false));
}
void JuceAudioDeviceManager::audioDeviceIOCallbackWithContext(const float* const* input,int inputs,float* const* output,int outputs,int samples,const juce::AudioIODeviceCallbackContext&){
    if(!running.load()||!(sequencer.is_valid()?sequencer->engine.render(output,outputs,samples):network->graph.render(input,inputs,output,outputs,samples))){for(int ch=0;ch<outputs;++ch)if(output[ch])juce::FloatVectorOperations::clear(output[ch],samples);peak.store(0);return;}
    float value=0;for(int ch=0;ch<outputs;++ch)if(output[ch])for(int i=0;i<samples;++i){if(!std::isfinite(output[ch][i]))output[ch][i]=0;value=std::max(value,std::abs(output[ch][i]));}peak.store(value);
}
Dictionary JuceAudioDeviceManager::get_device_info(){Dictionary r;if(auto* d=devices.getCurrentAudioDevice()){r["name"]=gd_string(d->getName());r["sample_rate"]=d->getCurrentSampleRate();r["buffer_size"]=d->getCurrentBufferSizeSamples();r["input_channels"]=d->getActiveInputChannels().countNumberOfSetBits();r["output_channels"]=d->getActiveOutputChannels().countNumberOfSetBits();r["output_latency_samples"]=d->getOutputLatencyInSamples();}return r;}
}

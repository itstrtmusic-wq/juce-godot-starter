#pragma once
#include "juce_api.h"
#include <juce_dsp/juce_dsp.h>

namespace godot {
// Shared ownership/validation for standalone offline JUCE processors.
// All methods run on the calling Godot thread; these instances are separate from graph nodes.
template <typename Processor>
struct PreparedEffect {
    Processor processor;
    bool prepared = false;
    double sample_rate = 48000.0;
    int max_block = 0, channels = 0;
    String error;
    bool fail(const String& message) { error = message; return false; }
    bool prepare(double rate, int block, int count) {
        if (!valid_rate(rate) || block < 1 || block > 8192 || count < 1 || count > 2)
            return fail("Expected valid sample rate, block size 1..8192, and one or two channels");
        processor.prepare({rate, juce::uint32(block), juce::uint32(count)});
        sample_rate = rate; max_block = block; channels = count; prepared = true; error = "";
        return true;
    }
    bool reset() {
        if (!prepared) return fail("Prepare the processor first");
        processor.reset(); error = ""; return true;
    }
    bool process(const Ref<JuceAudioBuffer>& buffer) {
        if (!prepared || buffer.is_null() || buffer->get_num_channels() != channels)
            return fail("Prepare the processor with the buffer's channel count first");
        auto whole = juce::dsp::AudioBlock<float>(buffer->native());
        for (int offset = 0; offset < buffer->get_num_samples(); offset += max_block) {
            auto block = whole.getSubBlock(size_t(offset), size_t(std::min(max_block, buffer->get_num_samples() - offset)));
            juce::dsp::ProcessContextReplacing<float> context(block);
            processor.process(context);
        }
        error = ""; return true;
    }
};
}

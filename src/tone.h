#pragma once
#include <juce_audio_basics/juce_audio_basics.h>
#include <algorithm>
#include <cmath>

// Audio-thread-owned state. Control-thread values arrive as snapshots per block.
class Tone {
    double phase = 0.0;
    double rate = 48000.0;
    juce::SmoothedValue<float> gain;
public:
    void prepare(double sample_rate) {
        rate = sample_rate > 0.0 ? sample_rate : 48000.0;
        phase = 0.0;
        gain.reset(rate, 0.005);
        gain.setCurrentAndTargetValue(0.0f);
    }
    float render(float* const* outputs, int channels, int samples,
                 float frequency, float level, bool enabled) {
        const double hz = std::clamp(double(frequency), 20.0, std::min(20000.0, rate * 0.45));
        const double step = juce::MathConstants<double>::twoPi * hz / rate;
        gain.setTargetValue(enabled ? std::clamp(level, 0.0f, 1.0f) : 0.0f);
        float peak = 0.0f;
        for (int i = 0; i < samples; ++i) {
            const float value = float(std::sin(phase)) * gain.getNextValue();
            phase += step;
            if (phase >= juce::MathConstants<double>::twoPi)
                phase -= juce::MathConstants<double>::twoPi;
            for (int ch = 0; ch < channels; ++ch)
                if (outputs[ch] != nullptr) outputs[ch][i] = value;
            peak = std::max(peak, std::abs(value));
        }
        return peak;
    }
};

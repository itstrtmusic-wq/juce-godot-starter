#include "tone.h"
#include <cstdlib>
#include <iostream>
#include <vector>
static void check(bool condition, const char* message) {
    if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
int main() {
    Tone tone;
    tone.prepare(48000.0);
    std::vector<float> left(48000), right(48000);
    float* outputs[] = {left.data(), right.data()};
    const float peak = tone.render(outputs, 2, 48000, 440.0f, 0.1f, true);
    double energy = 0.0;
    int crossings = 0;
    for (int i = 1000; i < 48000; ++i) {
        check(std::isfinite(left[i]), "Non-finite output");
        check(left[i] == right[i], "Stereo outputs differ");
        energy += left[i] * left[i];
        if (left[i - 1] <= 0.0f && left[i] > 0.0f) ++crossings;
    }
    check(peak > 0.099f && peak <= 0.101f, "Incorrect peak");
    const double rms = std::sqrt(energy / 47000.0);
    check(rms > 0.070 && rms < 0.072, "Incorrect RMS");
    check(std::abs(crossings - 440.0 * 47000.0 / 48000.0) < 2.0, "Incorrect frequency");
    tone.render(outputs, 2, 48000, 440.0f, 0.1f, false);
    for (int i = 1000; i < 48000; ++i) check(left[i] == 0.0f, "Mute did not settle");
    tone.prepare(44100.0);
    check(tone.render(outputs, 2, 48000, 999999.0f, 999.0f, true) <= 1.0f, "Gain clamp failed");
    float* sparse[] = {nullptr, right.data()};
    tone.render(sparse, 2, 48000, 440.0f, 0.05f, true);
    std::cout << "Tone frequency, stereo, RMS, peak, mute, clamping and null channel checks passed\n";
}

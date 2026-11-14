# Validation

## API and DSP-network release 0.3

Local validation uses Linux x86_64, GCC 14.2, JUCE 8.0.9, godot-cpp 4.5 bindings and Godot 4.6.3. Linux audio-device backends are deliberately disabled in this headless validation build.

Native tests check tone behavior and DSP-graph gain values, multi-block rendering, parallel routing, cycle rejection, parameter validation, active-state restrictions, delay timing and feedback. Modulation tests additionally check first-block dependency ordering, numerical modulation depth, base/effective separation, range clamping, mixed-route cycle rollback, active structural guards, stereo source-channel validation, LFO timing and native graph replacement. Each supported DSP node is rendered under an operator-new allocation audit and checked for finite output. A manifest test checks that generated registration code and API documentation match bindings/api.json.

GDScript integration checks every declared class/method, buffer ownership, invalid MIDI bytes, MIDI file timing, WAV encode/decode, UTF-8 paths/text, file overwrite protection, standalone processors, graph processing/introspection, device startup failure, legacy class registration, the offline rendering examples and main-scene startup. Version 0.3 adds standalone effect preparation/range/transaction checks, numerical compressor/limiter behavior, parameter modulation, invalid-patch rollback, JSON-number handling, UTF-8 patch paths, save/load round trips and malformed-file protection. Tests check output markers and engine errors as well as exit status, because a failed Godot assertion alone may leave the editor process running.

The integration runner also checks a fresh empty project and a fresh extension-only project. Editor checks allow bounded startup iterations before exit to avoid Godot's documented first-import documentation race ([Godot #111048](https://github.com/godotengine/godot/issues/111048)); the API and DSP tests remain enabled.

The Windows workflow builds with MSVC on windows-2022, runs native tests, downloads Godot 4.5.1 and runs GDScript integration tests before uploading its artifact. **Only a successful workflow run for the commit being downloaded establishes those Windows checks have passed.**

Not tested here: Windows 11 audio hardware, MIDI hardware, microphone monitoring, exact Godot 4.7 compatibility, latency under load, exported PCK resource access, hot-plug behavior or every possible graph/parameter combination. There are no real-time GDScript audio callbacks or plugin-hosting bindings in this release.

## Original 0.1 starter

The original tone starter compiled and passed its offline audio tests on Windows in the first repository workflow. It also loaded and passed its smoke test on Linux with Godot 4.6.3. That older result does not validate the newly added API classes; use the checks above for version 0.3.

# JUCE for GDScript — API + DSP networks

Version **0.6.0** exposes **23 reference-counted classes and 228 methods**, plus the legacy tone-demo class. Build your own audio tools in GDScript using JUCE buffers, MIDI, files, envelopes, filters, reverb, chorus, phaser, dynamics and editable native DSP networks with modulation and patch persistence.

This is a growing, explicitly documented JUCE binding layer. It is **not the entire JUCE C++ API**. GUI/window classes, AudioProcessor/AudioProcessorGraph, third-party plugin hosting, arbitrary C++ templates and GDScript callbacks on real-time audio threads are not bound. The custom `JuceDSPNetwork` is a graph of native JUCE processors; it does not claim to wrap JUCE's AudioProcessorGraph.

- [MIDI recorder, piano roll and live BPM](docs/MIDI_CLIPS.md) — open `demo/examples/clip_recorder.tscn` and press F6.
- [Start here: using the API in Godot](docs/GETTING_STARTED.md)
- [On-screen MIDI piano and FL-style typing keys](docs/MIDI_KEYBOARD.md) — open `demo/examples/typing_keyboard.tscn` and press F6.
- [All supported classes and methods](docs/API_REFERENCE.md)
- [DSP networks: nodes, parameters, routing and live audio](docs/DSP_NETWORKS.md)
- [Binding manifest](bindings/api.json), also available at runtime through `JUCE.get_api_manifest()`
- [Executable GDScript examples](demo/examples)

## MIDI clip transport in 0.6

`JuceMidiSequencer` adds sample-timed playback of a beat-based clip, live BPM changes, looping, a metronome, a 32-voice audition instrument and bounded MIDI recording queues. The optional Godot clip studio records typing/mouse notes and supports piano-roll editing, quantization, JSON clips and standard MIDI export. The native API can also render clips offline.

## API-only edition

The visual graph editor, editor plugin and graph-document format have been removed. DSP networks, modulation and native JSON patches remain available through GDScript. The original slider demo is the main scene again.

## Modulation, processors and patches

- Native LFO nodes can drive effect parameters through `connect_parameter()`. Audio and parameter routes share cycle detection; scalar base settings remain independent from the modulated values.
- New graph nodes: `lfo`, `chorus`, `phaser`, `limiter` and `noise_gate` — **26 node types** total.
- Standalone `JuceChorus`, `JucePhaser`, `JuceCompressor`, `JuceLimiter` and `JuceNoiseGate` expose JUCE DSP processors directly to GDScript.
- `export_patch()`, `load_patch()`, `save_patch()` and `load_patch_file()` save/reconstruct networks. Invalid loads leave the current graph untouched. See the [patch format](docs/PATCH_FORMAT.md) in `docs` below.

```gdscript
# Add this to a network containing a node named "filter" with a frequency parameter.
fx.add_node("slow", "lfo")
fx.set_parameter("slow", "rate_hz", 0.75)
fx.connect_parameter("slow", "filter", "frequency", 1500.0)
# Each block: cutoff = base cutoff + LFO × 1500 Hz, clamped to the parameter's range.
fx.save_patch("user://my_effect.json")
```

Modulation uses the first sample of a source channel once per audio block. This is control-rate modulation; audio-rate parameter modulation and sample-accurate automation are not implemented. `multiply` still supports sample-by-sample signal multiplication. Read the [modulation guide](docs/DSP_NETWORKS.md#parameter-modulation) and [patch format](docs/PATCH_FORMAT.md) for full semantics.

## Write your effect in GDScript

```gdscript
var fx := JuceDSPNetwork.new()
fx.add_node("filter", "low_pass")
fx.add_node("drive", "tanh")
fx.add_node("echo", "delay")
fx.connect_nodes("input", "filter")
fx.connect_nodes("filter", "drive")
fx.connect_nodes("drive", "echo")
fx.connect_nodes("echo", "output")
fx.set_parameter("filter", "frequency", 1800.0)
fx.set_parameter("drive", "drive", 3.0)
fx.set_parameter("echo", "delay_ms", 375.0)
fx.set_parameter("echo", "feedback", 0.4)

# Offline: process a JUCE buffer that you created or decoded from an audio file.
var buffer := JuceAudioBuffer.new()
buffer.set_size(2, 48000)
fx.prepare(48000.0, 512, 2)
fx.process(buffer)

# Or run the network on live audio input/output.
# Keep the device and network in member variables while audio is running.
var device := JuceAudioDeviceManager.new()
device.set_network(fx)
# output name, sample rate, block size, input name, enable input
if not device.start_audio("", 48000.0, 256, "", true):
    push_error(device.get_last_error())

# Numeric parameters can change during playback.
fx.set_parameter("filter", "frequency", 900.0)
# Stop before adding/removing nodes or changing connections.
device.stop_audio()
```

In this example the offline buffer starts silent. Use `JuceAudioFormatManager.read_file()` to get recorded audio, fill channels with PackedFloat32Array, or add an `oscillator` node for a generated source. `demo/examples/offline_processing.gd` renders a complete generated sound into a WAV file. `custom_effect.gd` processes live input with parallel dry and wet paths. `midi_synth.gd` builds a monophonic instrument with an oscillator and ADSR envelope. `modulated_effect.gd` adds a native LFO and chorus; `preset_render.gd` saves/reloads the patch and renders its sound without hardware.

## General JUCE objects

```gdscript
var note := JuceMidiMessage.note_on(1, 60, 0.8)
var midi := JuceMidiBuffer.new()
midi.add_event(note, 128)

var filter := JuceIIRFilter.new()
filter.make_low_pass(48000.0, 1200.0)
filter.process(buffer, 0) # Standalone processing on the calling thread.

var envelope := JuceADSR.new()
envelope.set_sample_rate(48000.0)
envelope.set_parameters(0.01, 0.1, 0.8, 0.2)
envelope.note_on()
envelope.apply_to_buffer(buffer)

var formats := JuceAudioFormatManager.new()
formats.write_wav("user://render.wav", buffer, 48000.0)
```

Standalone processor wrappers run synchronously/offline. The DSP network owns separate native processor instances for real-time use. Python generation creates registrations and documentation for the explicit native wrappers; it does not automatically translate every JUCE header into a working binding.

## Download and use on Windows 11

1. Open [Actions → Windows addon build](https://github.com/itstrtmusic-wq/juce-godot-starter/actions/workflows/windows-build.yml).
2. Choose the latest successful run, then download the **juce-godot-windows-x86_64** artifact. You may need to sign in.
3. Extract the artifact and the packaged ZIP inside it. Import **demo/project.godot**.
4. Run the demo. It assembles an oscillator/input → filter → distortion → reverb → gain → clip network entirely from GDScript. Sliders control native processor parameters.
5. For another project, copy **demo/addons/juce_bridge** into that project's `addons` folder, then reopen the editor. No EditorPlugin needs enabling.

The build includes the DLL, so no C++ tools are needed to use it. Close Godot before replacing/rebuilding the DLL; native hot reload is disabled. Live microphone monitoring should use headphones to avoid acoustic feedback.

## Build the source on Windows

Install Visual Studio 2022 Community or Build Tools with **Desktop development with C++**, MSVC v143 and a Windows SDK. Install Git, Python 3 and CMake 3.22+ on PATH, reopen PowerShell, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
```

CMake downloads pinned JUCE 8.0.9 and godot-cpp 4.5 sources. The script compiles the DLL and runs native tests. For editor integration tests, run:

```powershell
python tools/run_godot_tests.py --godot "C:\Path\To\Godot.exe"
```

The build targets x86_64 and standard single-precision Godot. GDExtension uses a 4.5 baseline for intended forward compatibility. The Windows workflow checks both Godot 4.5.1 and 4.7. Windows 11 audio hardware requires direct testing; see the validation record for scope.

## What can run where

Use these objects from Godot's main thread. MIDI input queues native messages for `read_events()`; your script can then handle them and emit its own Godot signals. The queue holds at most 256 messages, up to 4096 bytes each, and reports dropped events.

Audio callbacks execute the prepared DSP network in C++. They do not call GDScript, allocate graph buffers, take graph mutexes, or emit Godot signals. Parameters transfer through lock-free atomic floats. Graph topology is immutable while a device owns it. Parameters update per block; this is not sample-accurate automation. Standalone wrapper objects are not shared with the live graph.

Audio buffers are copied/owned, with no exposed native pointers. Each standalone buffer is bounded to 16 million float samples. Graph preparation enforces a 16-million-float buffer estimate, with additional native processor bookkeeping overhead. Audio file reads reject files larger than the requested frame limit or allocation limit; streaming audio-file playback is not implemented. WAV writing is explicit about overwrite and uses a temporary file before replacement. Paths accept `res://`, `user://` or filesystem paths; exported `res://` resources inside PCK files must first be copied to `user://` for JUCE to read them.

## Extending the API

`bindings/api.json` is the source of truth for names, default arguments and coverage. Its reviewed `effect` entries generate the common standalone JUCE processor adapters, range metadata and parameter validation as well. Implement a wrapper in `src/juce_api.*` or another native source, add its method entries, then run:

```sh
python tools/generate_bindings.py
```

The generator updates native ClassDB registrations and the API reference. Native tests and GDScript integration tests check generated coverage, data round trips and DSP behavior. Adding genuinely new native processor implementations still requires a C++ implementation and a rebuilt DLL; assembling supported nodes into new effects does not.

Dependencies retain their own licences. JUCE is available under AGPLv3 or a commercial JUCE licence; choose the appropriate licence before distributing a JUCE-based product. godot-cpp uses MIT.

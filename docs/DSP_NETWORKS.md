# Custom DSP networks from GDScript

`JuceDSPNetwork` lets GDScript define audio signal flow while a C++ graph executes JUCE processors. This is a custom graph implementation, not a binding of `juce::AudioProcessorGraph`.

Every network starts with reserved `input` and `output` nodes and **no connections**. An unconnected output produces silence. Add processors, connect them, set numeric parameters, then either prepare/process buffers offline or attach the network to `JuceAudioDeviceManager` for real-time audio.

```gdscript
var fx := JuceDSPNetwork.new()
fx.add_node("left_branch", "gain")
fx.add_node("right_branch", "reverb")
fx.connect_nodes("input", "left_branch", 0.5)
fx.connect_nodes("input", "right_branch", 0.5)
fx.connect_nodes("left_branch", "output")
fx.connect_nodes("right_branch", "output")
```

Connections carry complete mono/stereo audio blocks with a fixed scalar gain. Most nodes sum incoming connections before processing. `multiply` multiplies its inputs sample by sample instead, enabling amplitude modulation and envelope/control-signal combinations. `connect_parameter()` adds control-rate parameter routes (see below). Arbitrary channel maps are not implemented; `multiply` can still combine signals sample by sample.

All structural methods return a success boolean. `get_last_error()` explains graph errors. Cycles, duplicate IDs/connections, invalid parameters and connections into `input` or out of `output` are rejected. A rejected cycle leaves the previous topology intact. Multiple connections from the same source to the same destination are not allowed; use a mix node if you need another path.

## Supported nodes and parameters

Every added processor has `bypass` from 0 to 1, default 0. Values >= 0.5 pass the node's incoming signal through without advancing its processor state. Reserved input/output nodes do not have this parameter.

| Node type | Parameters: default [range] | Behavior |
| --- | --- | --- |
| `gain` | `gain_db`: 0 [-100, 24] | JUCE gain smoothing with a 5 ms ramp. |
| `mix` | none | Sum incoming signals. |
| `constant` | `value`: 0 [-100, 100] | Replace incoming audio with a DC signal. |
| `add` | `value`: 0 [-100, 100] | Add a constant to the summed signal. |
| `multiply` | `value`: 1 [-100, 100] | Multiply incoming signals together, then multiply by value. No inputs produces zero. |
| `tanh` | `drive`: 1 [0, 100] | Soft saturation: tanh(input × drive). |
| `clip` | `threshold`: 1 [0.001, 100] | Clamp to ±threshold; this is a hard clipper, not a look-ahead limiter. |
| `abs` | none | Absolute sample value. |
| `sin` | none | Sine of each sample, for waveshaping. |
| `oscillator` | `frequency`: 440 [0, 20000]; `gain`: 0.1 [0, 1]; `waveform`: 0 [integer 0–3] | JUCE DSP oscillator. 0 sine, 1 triangle, 2 saw, 3 square. Replaces incoming audio. |
| `low_pass`, `high_pass`, `band_pass`, `notch` | `frequency`: 1000 [10, 20000]; `q`: 0.7071 [0.1, 20]; `gain_db`: 0 [-48, 24] | JUCE IIR filters; gain_db is unused for these four types. |
| `peak`, `low_shelf`, `high_shelf` | `frequency`: 1000 [10, 20000]; `q`: 0.7071 [0.1, 20]; `gain_db`: 0 [-48, 24] | JUCE IIR EQ filters. |
| `delay` | `delay_ms`: 250 [0, 2000]; `feedback`: 0.35 [-0.99, 0.99]; `mix`: 0.5 [0, 1] | Native delay ring using a JUCE audio buffer. Minimum actual delay is one sample. |
| `reverb` | `room_size`: 0.5; `damping`: 0.5; `wet_level`: 0.33; `dry_level`: 0.4; `width`: 1; `freeze_mode`: 0. All [0, 1]. | JUCE mono/stereo reverb. |
| `compressor` | `threshold_db`: -18 [-100, 0]; `ratio`: 4 [1, 100]; `attack_ms`: 10 [0.01, 1000]; `release_ms`: 100 [0.01, 5000] | JUCE DSP compressor with separate channel detector state. |
| `lfo` | `rate_hz`: 1 [0.01, 40]; `amplitude`: 1 [0, 1]; `offset`: 0 [-1, 1]; `waveform`: 0 [integer 0–3] | Native JUCE DSP oscillator at modulation rates. Same waveform numbering as oscillator; replaces incoming audio. |
| `chorus` | `rate_hz`: 1 [0.01, 99]; `depth`: 0.25 [0, 1]; `centre_delay_ms`: 7 [1, 100]; `feedback`: 0 [-0.99, 0.99]; `mix`: 0.5 [0, 1] | JUCE DSP chorus, also usable for flanging/vibrato by changing delay, feedback and mix. |
| `phaser` | `rate_hz`: 1 [0.01, 99]; `depth`: 0.5 [0, 1]; `centre_frequency`: 1300 [20, 20000]; `feedback`: 0 [-0.99, 0.99]; `mix`: 0.5 [0, 1] | JUCE DSP phaser; centre frequency is clamped below Nyquist. |
| `limiter` | `threshold_db`: -1 [-100, 0]; `release_ms`: 100 [0.01, 5000] | JUCE limiter: two compressors, makeup gain, and a final hard clip at ±1. Threshold is the dynamics threshold, not a selectable final output ceiling. No look-ahead. |
| `noise_gate` | `threshold_db`: -60 [-100, 0]; `ratio`: 10 [1, 100]; `attack_ms`: 5 [0.01, 1000]; `release_ms`: 100 [0.01, 5000] | JUCE DSP noise gate. |
| `adsr` | `attack`: 0.01 [0, 10]; `decay`: 0.1 [0, 10]; `sustain`: 0.8 [0, 1]; `release`: 0.2 [0, 10]; `gate`: 0 [0, 1] | JUCE envelope; time values in seconds. Rising gate triggers note-on, falling gate triggers note-off. Applies to incoming audio; with no inputs emits the envelope itself. |

Filter/oscillator frequency is further clamped below the actual device Nyquist frequency. Oscillator saw/square/triangle functions are simple waveforms without band-limiting or oversampling. Distortion and nonlinear math nodes have no oversampling. Fast filter/delay/waveform parameter changes may produce discontinuities; only gain and oscillator-frequency changes have built-in smoothing. There is no implicit output limiter; design your gain staging or add a clip or limiter node.

`get_supported_node_types()` returns all 26 supported type strings. `get_nodes()` returns each node's ID, type, and parameter value/min/max metadata; `get_connections()` returns source, destination and gain dictionaries. These let you build your own Godot GraphEdit UI or save a patch description in GDScript. Network patches can now be saved and loaded; a visual graph editor is not included. See [patch format](PATCH_FORMAT.md).

## Parameter modulation

```gdscript
fx.add_node("slow", "lfo")
fx.set_parameter("slow", "rate_hz", 0.75)
fx.set_parameter("filter", "frequency", 2200.0)
fx.connect_parameter("slow", "filter", "frequency", 1600.0, 0.0, 0)
```

`connect_parameter(source, destination, parameter, depth=1, offset=0, channel=0)` adds a dependency from a node's audio output to a numeric target parameter. At the start of that target's processing in every block:

`effective = clamp(base + sum(source[channel][0] * depth + offset), parameter_min, parameter_max)`

Each source has already rendered the current block. This is **block-rate control modulation**, not per-sample filter-coefficient modulation. Block size affects the control update rate and may affect the rendered sound. Smooth fast changes yourself where necessary. Audio-rate multiplication is available through `multiply` nodes.

`set_parameter()` and `get_parameters()` operate on the base settings. `get_effective_parameters(id)` returns the most recently evaluated control values, read through atomics. Processor-specific frequency clamping below Nyquist may further restrict the actual frequency. Before first rendering, effective values are defaults or the values copied during preparation.

A target may sum several routes from different source nodes. Duplicate source/destination/parameter routes are rejected. `waveform` is not a modulation target; set it directly with an integer. Other threshold-like parameters such as `gate` and `bypass` can be modulated using their existing >=0.5 rule. Source channel must be 0 or 1 and must exist in the channel configuration passed to `prepare()`. Non-finite source samples contribute nothing for that route.

Audio and modulation edges share topological sorting, cycle detection and the 256-connection budget. A rejected cycle leaves the old network intact. Add/remove parameter routes only while stopped. `disconnect_parameter(source, destination, parameter)` removes a route; removing a source node also removes its outgoing parameter routes. `get_modulation_connections()` returns the full route descriptions for your own UI/persistence tools. Depth and offset must be finite with absolute values no larger than 1,000,000.

## Offline audio

```gdscript
var formats := JuceAudioFormatManager.new()
var loaded := formats.read_file("user://input.wav")
if loaded.is_empty():
    push_error(formats.get_last_error())
    return
var buffer: JuceAudioBuffer = loaded.buffer
if not fx.prepare(loaded.sample_rate, 512, buffer.get_num_channels()):
    push_error(fx.get_last_error())
    return
fx.process(buffer)
formats.write_wav("user://processed.wav", buffer, loaded.sample_rate)
```

`prepare(rate, max_block_size, channels)` allocates all graph audio/delay buffers and resets processor state. `process(buffer)` splits larger buffers into blocks and processes in place. State persists across calls; use `reset()` between independent renders. To render a reverb/delay tail, process additional zero-filled audio after the source ends. Offline scripts may generate or alter samples freely; this is synchronous work on the caller thread.

## Live audio

```gdscript
# Keep these as member variables, not temporary locals.
var audio := JuceAudioDeviceManager.new()
audio.set_network(fx)
# Set enable_input to true for microphone/interface input; false for a source-only graph.
if not audio.start_audio("", 48000.0, 256, "", true):
    push_error(audio.get_last_error())
```

Empty device names select defaults. Enumerate names using `get_output_devices()` and `get_input_devices()`. This version exposes JUCE's first backend only, normally WASAPI shared on Windows; ASIO is not enabled. Drivers may adjust the requested rate and buffer size. Read actual values with `get_device_info()`. No resampling into Godot's own audio buses occurs: JUCE owns its audio device.

`input` receives actual device input, or silence if input is disabled/unavailable. The network is prepared automatically for the actual device sample rate, block size and output channel count. Only mono/stereo output is supported. Missing input channels become silence. Use headphones for microphone monitoring to avoid feedback through speakers.

During playback, `set_parameter()` uses atomic writes and can control effects from Godot sliders, MIDI handlers or automation code. The audio thread samples these values per block. Gain ramps are 5 ms; parameters are not scheduled to exact sample positions. GDScript MIDI polling introduces frame scheduling latency; the provided MIDI instrument example is monophonic, not a full MIDI synth engine.

Stop audio before changing topology, preparing/resetting the graph, or processing it offline. Only one running device manager can own a graph at a time. A manager retains the network while it runs. Stop audio in `_exit_tree()`; destruction also stops callbacks before releasing native objects.

## Limits and real-time behavior

The graph supports at most 64 total nodes, 256 audio/modulation connections, 8192 samples per block, two output channels and a 16-million-float preparation budget for graph buffers, custom delays and estimates of modulation-effect buffers. JUCE processor state and bookkeeping add overhead beyond that estimate. Recursive audio feedback connections are rejected; delay nodes implement their own bounded internal feedback. There is no sample-accurate event scheduling, arbitrary DSP code compiler, plugin node, convolution node, custom GDScript node callback or hot-swapped topology in this version.

The render path uses prepared buffers, native processor state and atomic parameter reads. Native tests audit `operator new` during rendering for every node type; they also check gain, routing, delay feedback, topology validation and active-state restrictions. This is not a formal guarantee against every possible platform/library allocation or driver glitch.

# GDScript binding reference

API version: **0.4.0**. 22 classes and 209 methods are declared below.

Generated from `bindings/api.json`. These are explicit supported bindings, not a complete JUCE wrapper. Use `JUCE.get_api_manifest()` to inspect this surface at runtime.

All objects are owned Godot reference-counted objects. Factories can return null on invalid input; processing/configuration methods generally return a success boolean. Audio, MIDI and file data are copied when crossing ownership boundaries. ClassDB also exposes native return and argument types in the editor.

See [DSP networks](DSP_NETWORKS.md) for graph topology, node parameters, automation and live-input setup. See [examples](../demo/examples) for executable GDScript.

## JUCE

Static utilities and an exact manifest of the supported binding surface.

JUCE implementation: `Framework utilities`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `static get_version()` | `—` |
| `static get_api_manifest()` | `—` |
| `static get_supported_classes()` | `—` |
| `static decibels_to_gain(db, minus_infinity_db)` | `float(-100.0)` |
| `static gain_to_decibels(gain, minus_infinity_db)` | `float(-100.0)` |
| `static midi_note_to_hz(note, a4_frequency)` | `double(440.0)` |

## JuceAudioBuffer

Owned float audio data; channel copies use PackedFloat32Array.

JUCE implementation: `juce::AudioBuffer<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `set_size(channels, samples, keep_existing)` | `false` |
| `get_num_channels()` | `—` |
| `get_num_samples()` | `—` |
| `clear()` | `—` |
| `get_sample(channel, sample)` | `—` |
| `set_sample(channel, sample, value)` | `—` |
| `get_channel(channel)` | `—` |
| `set_channel(channel, samples)` | `—` |
| `apply_gain(gain)` | `—` |
| `apply_gain_ramp(start_gain, end_gain)` | `—` |
| `get_rms_level(channel)` | `—` |
| `get_magnitude(channel)` | `—` |
| `copy_from(source)` | `—` |
| `add_from(source, gain)` | `float(1.0)` |
| `reverse()` | `—` |
| `duplicate_buffer()` | `—` |

## JuceMidiMessage

Owned MIDI value. Factory methods are static; timestamps are preserved.

JUCE implementation: `juce::MidiMessage`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `static note_on(channel, note, velocity)` | `—` |
| `static note_off(channel, note)` | `—` |
| `static controller_event(channel, controller, value)` | `—` |
| `static pitch_wheel(channel, value)` | `—` |
| `static program_change(channel, program)` | `—` |
| `static tempo_event(microseconds_per_quarter_note)` | `—` |
| `static from_bytes(bytes, timestamp)` | `double(0.0)` |
| `get_raw_data()` | `—` |
| `get_description()` | `—` |
| `get_channel()` | `—` |
| `set_channel(channel)` | `—` |
| `get_note_number()` | `—` |
| `set_note_number(note)` | `—` |
| `get_velocity()` | `—` |
| `set_velocity(velocity)` | `—` |
| `get_timestamp()` | `—` |
| `set_timestamp(timestamp)` | `—` |
| `is_note_on()` | `—` |
| `is_note_off()` | `—` |
| `is_controller()` | `—` |
| `get_controller_number()` | `—` |
| `get_controller_value()` | `—` |
| `is_pitch_wheel()` | `—` |
| `get_pitch_wheel_value()` | `—` |
| `is_program_change()` | `—` |
| `get_program_change_number()` | `—` |
| `is_tempo_meta_event()` | `—` |
| `get_tempo_seconds_per_quarter_note()` | `—` |

## JuceMidiBuffer

Timestamped MIDI events in sample positions, independent of message timestamps.

JUCE implementation: `juce::MidiBuffer`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `add_event(message, sample_position)` | `—` |
| `get_events()` | `—` |
| `get_num_events()` | `—` |
| `is_empty()` | `—` |
| `clear()` | `—` |
| `add_events(source, start_sample, num_samples, sample_delta)` | `int(0)` |

## JuceMidiMessageSequence

Sorted MIDI sequence for use with MIDI files.

JUCE implementation: `juce::MidiMessageSequence`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `add_event(message, time_adjustment)` | `double(0.0)` |
| `get_events()` | `—` |
| `get_num_events()` | `—` |
| `get_start_time()` | `—` |
| `get_end_time()` | `—` |
| `clear()` | `—` |
| `sort()` | `—` |
| `update_matched_pairs()` | `—` |

## JuceMidiFile

Read and write standard MIDI files. Track access returns an owned copy.

JUCE implementation: `juce::MidiFile`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `read_file(path)` | `—` |
| `write_file(path, overwrite)` | `false` |
| `get_num_tracks()` | `—` |
| `get_track(index)` | `—` |
| `add_track(sequence)` | `—` |
| `clear()` | `—` |
| `set_ticks_per_quarter_note(ticks)` | `—` |
| `get_time_format()` | `—` |
| `convert_timestamp_ticks_to_seconds()` | `—` |
| `get_last_error()` | `—` |

## JuceFile

Filesystem paths accept Godot res:// and user:// paths. No raw pointers exposed.

JUCE implementation: `juce::File`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `set_path(path)` | `—` |
| `get_full_path_name()` | `—` |
| `get_file_name()` | `—` |
| `get_file_extension()` | `—` |
| `exists()` | `—` |
| `exists_as_file()` | `—` |
| `is_directory()` | `—` |
| `get_size()` | `—` |
| `load_as_string()` | `—` |
| `replace_with_text(text)` | `—` |
| `append_text(text)` | `—` |
| `create_directory()` | `—` |
| `get_child_file(relative_path)` | `—` |
| `get_parent_directory()` | `—` |
| `find_child_files(wildcard, recursive)` | `String("*"), false` |

## JuceAudioFormatManager

Read audio into an owned buffer; safely write WAV files. Reads are bounded.

JUCE implementation: `juce::AudioFormatManager / WavAudioFormat`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `get_wildcard_for_all_formats()` | `—` |
| `read_file(path, max_samples)` | `int(10000000)` |
| `write_wav(path, buffer, sample_rate, bits_per_sample, overwrite)` | `int(24), false` |
| `get_last_error()` | `—` |

## JuceADSR

Sample-accurate envelope; buffer processing is offline on the caller thread.

JUCE implementation: `juce::ADSR`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `set_sample_rate(sample_rate)` | `—` |
| `set_parameters(attack, decay, sustain, release)` | `—` |
| `note_on()` | `—` |
| `note_off()` | `—` |
| `reset()` | `—` |
| `is_active()` | `—` |
| `get_next_sample()` | `—` |
| `apply_to_buffer(buffer)` | `—` |

## JuceReverb

Mono/stereo reverb with JUCE parameter names converted to snake_case.

JUCE implementation: `juce::Reverb`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `set_sample_rate(sample_rate)` | `—` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |

## JuceIIRFilter

One filter instance holds one channel of state. Use another instance for another channel.

JUCE implementation: `juce::SingleThreadedIIRFilter / IIRCoefficients`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `make_low_pass(sample_rate, frequency, q)` | `double(0.70710678)` |
| `make_high_pass(sample_rate, frequency, q)` | `double(0.70710678)` |
| `make_band_pass(sample_rate, frequency, q)` | `double(0.70710678)` |
| `make_notch(sample_rate, frequency, q)` | `double(0.70710678)` |
| `make_peak_filter(sample_rate, frequency, q, gain)` | `—` |
| `reset()` | `—` |
| `process_sample(sample)` | `—` |
| `process(buffer, channel)` | `int(0)` |

## JuceRandom

Independent seeded random generator.

JUCE implementation: `juce::Random`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `set_seed(seed)` | `—` |
| `next_int(upper_bound)` | `—` |
| `next_int64()` | `—` |
| `next_float()` | `—` |
| `next_double()` | `—` |
| `next_bool()` | `—` |

## JuceSmoothedValue

Linear parameter smoothing, usable offline or when pre-rendering buffers.

JUCE implementation: `juce::SmoothedValue<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `reset(sample_rate, ramp_seconds)` | `—` |
| `set_current_and_target_value(value)` | `—` |
| `set_target_value(value)` | `—` |
| `get_next_value()` | `—` |
| `get_current_value()` | `—` |
| `is_smoothing()` | `—` |
| `skip(num_samples)` | `—` |
| `apply_gain(buffer)` | `—` |

## JuceMidiInput

Native MIDI input callback queues messages; drain with read_events() on the Godot thread.

JUCE implementation: `juce::MidiInput`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `static get_available_devices()` | `—` |
| `open_device(identifier)` | `—` |
| `close_device()` | `—` |
| `is_open()` | `—` |
| `read_events()` | `—` |
| `get_dropped_event_count()` | `—` |
| `get_last_error()` | `—` |

## JuceMidiOutput

Immediate MIDI output; no GDScript runs on a JUCE callback thread.

JUCE implementation: `juce::MidiOutput`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `static get_available_devices()` | `—` |
| `open_device(identifier)` | `—` |
| `close_device()` | `—` |
| `is_open()` | `—` |
| `send_message_now(message)` | `—` |
| `send_buffer_now(buffer)` | `—` |
| `get_last_error()` | `—` |

## JuceDSPNetwork

Editable directed acyclic DSP graph. Connections and preparation change only while stopped; numeric parameters support live updates.

JUCE implementation: `Native graph of JUCE DSP processors`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `get_supported_node_types()` | `—` |
| `add_node(id, type)` | `—` |
| `remove_node(id)` | `—` |
| `connect_nodes(source, destination, gain)` | `float(1.0)` |
| `disconnect_nodes(source, destination)` | `—` |
| `get_node_ids()` | `—` |
| `set_parameter(id, parameter, value)` | `—` |
| `get_parameters(id)` | `—` |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `is_active()` | `—` |
| `get_last_error()` | `—` |
| `get_nodes()` | `—` |
| `get_connections()` | `—` |
| `connect_parameter(source, destination, parameter, depth, offset, channel)` | `float(1.0), float(0.0), int(0)` |
| `disconnect_parameter(source, destination, parameter)` | `—` |
| `get_modulation_connections()` | `—` |
| `get_effective_parameters(id)` | `—` |
| `export_patch()` | `—` |
| `load_patch(patch)` | `—` |
| `save_patch(path, overwrite)` | `false` |
| `load_patch_file(path)` | `—` |

## JuceAudioDeviceManager

Executes a JuceDSPNetwork using native audio callbacks, with optional live audio input.

JUCE implementation: `juce::AudioDeviceManager`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `get_output_devices()` | `—` |
| `get_input_devices()` | `—` |
| `set_network(network)` | `—` |
| `start_audio(output_device, sample_rate, buffer_size, input_device, enable_input)` | `String(""), double(48000.0), int(256), String(""), false` |
| `stop_audio()` | `—` |
| `is_running()` | `—` |
| `get_peak()` | `—` |
| `get_device_info()` | `—` |
| `get_last_error()` | `—` |

## JuceChorus

Owned standalone Chorus processor. Prepare before processing mono/stereo buffers; larger buffers are split into prepared blocks.

JUCE implementation: `juce::dsp::Chorus<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `get_parameter_info()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `get_last_error()` | `—` |

| Parameter | Default | Min | Max |
| --- | --- | --- | --- |
| `rate_hz` | 1 | 0.01 | 99 |
| `depth` | 0.25 | 0 | 1 |
| `centre_delay_ms` | 7 | 1 | 100 |
| `feedback` | 0 | -0.99 | 0.99 |
| `mix` | 0.5 | 0 | 1 |

## JucePhaser

Owned standalone Phaser processor. Prepare before processing mono/stereo buffers; larger buffers are split into prepared blocks.

JUCE implementation: `juce::dsp::Phaser<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `get_parameter_info()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `get_last_error()` | `—` |

| Parameter | Default | Min | Max |
| --- | --- | --- | --- |
| `rate_hz` | 1 | 0.01 | 99 |
| `depth` | 0.5 | 0 | 1 |
| `centre_frequency` | 1300 | 20 | 20000 |
| `feedback` | 0 | -0.99 | 0.99 |
| `mix` | 0.5 | 0 | 1 |

## JuceCompressor

Owned standalone Compressor processor. Prepare before processing mono/stereo buffers; larger buffers are split into prepared blocks.

JUCE implementation: `juce::dsp::Compressor<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `get_parameter_info()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `get_last_error()` | `—` |

| Parameter | Default | Min | Max |
| --- | --- | --- | --- |
| `threshold_db` | -18 | -100 | 0 |
| `ratio` | 4 | 1 | 100 |
| `attack_ms` | 10 | 0.01 | 1000 |
| `release_ms` | 100 | 0.01 | 5000 |

## JuceLimiter

Owned standalone Limiter processor. Prepare before processing mono/stereo buffers; larger buffers are split into prepared blocks.

JUCE implementation: `juce::dsp::Limiter<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `get_parameter_info()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `get_last_error()` | `—` |

| Parameter | Default | Min | Max |
| --- | --- | --- | --- |
| `threshold_db` | -1 | -100 | 0 |
| `release_ms` | 100 | 0.01 | 5000 |

## JuceNoiseGate

Owned standalone NoiseGate processor. Prepare before processing mono/stereo buffers; larger buffers are split into prepared blocks.

JUCE implementation: `juce::dsp::NoiseGate<float>`.

| Method | Defaults for trailing arguments |
| --- | --- |
| `prepare(sample_rate, max_block_size, channels)` | `int(512), int(2)` |
| `set_parameters(parameters)` | `—` |
| `get_parameters()` | `—` |
| `get_parameter_info()` | `—` |
| `reset()` | `—` |
| `process(buffer)` | `—` |
| `get_last_error()` | `—` |

| Parameter | Default | Min | Max |
| --- | --- | --- | --- |
| `threshold_db` | -60 | -100 | 0 |
| `ratio` | 10 | 1 | 100 |
| `attack_ms` | 5 | 0.01 | 1000 |
| `release_ms` | 100 | 0.01 | 5000 |

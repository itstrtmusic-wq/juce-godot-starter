# Using JUCE from GDScript

This addon exposes a supported set of JUCE features as Godot classes. You write GDScript to create and control them; the compiled extension performs the DSP in C++. You do not need to write C++ to combine the supported processors into effects.

## 1. Install the compiled addon

On Windows 11, download the **juce-godot-windows-x86_64** artifact from a successful [Windows addon build](https://github.com/itstrtmusic-wq/juce-godot-starter/actions/workflows/windows-build.yml) for the API-only edition, version 0.5 or later. Extract the download, then extract the ZIP inside it.

Open the included `demo/project.godot` in standard Godot 4.7, x86_64. Open `res://main.tscn` and press F6 to try the slider demo. F5 opens the new DAW workspace. Select an output and click **Start DSP network**. The oscillator source makes a test tone; the live-input source needs an instrument or microphone.

To use the API in your own project, close Godot, copy the package's `demo/addons/juce_bridge` folder into your project's `addons` folder and reopen Godot. The folder must include `juce_bridge.gdextension` and `bin/juce_bridge.dll`. A Git clone contains source code; it does not include the compiled DLL. No editor plugin needs enabling.

If updating an older installation, replace the old addon folder rather than overlaying it, so removed editor scripts and `plugin.cfg` do not remain. Disable the old **JUCE DSP Graph** plugin first if you enabled it. Keep any presets you want separately; the API loads native DSP JSON patches, not `.jucegraph` documents.

An “Identifier JuceDSPNetwork not declared” error usually means the extension did not load. Check Godot's Output for the DLL/extension error and restart after installing the compiled addon.

## 2. Understand the three main objects

| Object | Purpose |
| --- | --- |
| `JuceDSPNetwork` | Holds your processors, their connections and parameter values. |
| `JuceAudioDeviceManager` | Opens the audio device and runs the network in real time. |
| `JuceAudioBuffer` | Holds samples for processing or rendering offline. |

A network is a sound path you describe in code. `input` and `output` already exist, but start disconnected. A processor changes audio; an oscillator generates audio. Nothing reaches your speakers until a path reaches `output` and a device is running.

There are also standalone classes for MIDI, files, buffers and processors. See the [class and method reference](API_REFERENCE.md). The standalone processors run on the calling thread; they are separate from the instances inside a live network.

## 3. Make your first sound

Create a new scene with a plain **Node** as its root. Attach [first_sound.gd](../demo/examples/first_sound.gd), then press **F6** to run that scene. In your own project, copy the example script from the package first. Start with your speaker/headphone volume low.

The example builds this path:

```text
Oscillator → Low-pass filter → Volume → Output
```

Its essential operations are:

```gdscript
var network := JuceDSPNetwork.new()
network.add_node("tone", "oscillator")
network.add_node("filter", "low_pass")
network.connect_nodes("tone", "filter")
network.connect_nodes("filter", "output")
network.set_parameter("tone", "gain", 0.05)
network.set_parameter("tone", "frequency", 220.0)
network.set_parameter("filter", "frequency", 1800.0)
```

This fragment defines a sound; the complete example also starts/stops the device and checks errors.

- `"tone"` is an **ID you choose**, used to refer to that specific processor. Two oscillators need different IDs.
- `"oscillator"` is a **supported processor type**. An arbitrary new type name will fail.
- `"frequency"` is a **parameter name** accepted by that type. Oscillator frequency sets pitch; filter frequency sets cutoff.
- `connect_nodes(source, destination)` makes a directed audio connection. Multiple incoming paths normally sum together.
- `set_parameter(id, name, value)` changes a setting. Frequencies are in Hz; `gain_db` is in decibels. Check units and ranges in the [node table](DSP_NETWORKS.md#supported-nodes-and-parameters).

The full example keeps `network` and `audio` in member variables, so they remain available while sound runs. `_exit_tree()` stops audio when the scene closes. `start_audio("", 48000.0, 256, "", false)` requests default output, 48 kHz, 256-sample blocks and no live input. The driver may adjust these settings; `get_device_info()` reports the actual settings.

JUCE opens its own audio device. Godot's Master bus volume and AudioStreamPlayer do not control this sound. If silent, inspect Output for errors, check the selected device and Windows volume mixer, and use `audio.get_peak()` to see whether the network is producing a signal. Set the example's exported `output_device` to an exact name printed by `get_output_devices()` if needed.

## 4. Control an effect with your own Godot UI

In the first-sound scene, add an **HSlider** under the root. Set Min Value to `20`, Max Value to `20000`, Step to `1` and Value to `1800`.

Select the slider, open its **Signals** panel and connect `value_changed` to the root Node. Use this handler:

```gdscript
func _on_h_slider_value_changed(value: float) -> void:
    set_cutoff(value)
```

`set_cutoff()` is already in the example script and calls:

```gdscript
network.set_parameter("filter", "frequency", hz)
```

Move the slider while the scene runs. Lower cutoff makes the tone darker. A sine wave has little high-frequency content, so for a clearer demonstration add this inside `_build_sound()`'s boolean chain before the connections:

```gdscript
and network.set_parameter("tone", "waveform", 2.0) # Saw wave
```

You can use knobs, buttons, MIDI or automation to call the same method. Godot owns your interface; JUCE runs the sound processing.

## 5. Turn the example into a live effect

The oscillator makes its own sound. To process an instrument/microphone instead, change the first audio connection in `_build_sound()` from:

```gdscript
network.connect_nodes("tone", "filter")
```

to:

```gdscript
network.connect_nodes("input", "filter")
```

Then change the device start call to enable input:

```gdscript
audio.start_audio(output_device, 48000.0, 256, "", true)
```

The empty input-device name selects the default input. Enumerate `audio.get_input_devices()` and pass an exact name as the fourth argument to select another input. The unused oscillator can stay disconnected or be removed from the construction code. Use headphones when monitoring a microphone.

To add distortion, add a `"tanh"` processor and route `filter → drive → volume` instead of `filter → volume`. Its `"drive"` parameter controls saturation. See [custom_effect.gd](../demo/examples/custom_effect.gd) for a fuller live-input effect.

## 6. Change parameters, structure and presets

While audio runs, change numeric parameters with `set_parameter()`. Stop with `audio.stop_audio()` before adding/removing processors, changing connections, loading a patch or processing offline. Reattach/start the device when editing is complete. These structural operations return false if the graph is active; inspect `network.get_last_error()`.

For moving parameters automatically, add a native LFO and connect it to a parameter while stopped:

```gdscript
network.add_node("slow", "lfo")
network.set_parameter("slow", "rate_hz", 0.5)
network.set_parameter("filter", "frequency", 2200.0)
network.connect_parameter("slow", "filter", "frequency", 1600.0)
```

This moves cutoff around its base setting by approximately ±1600 Hz. It uses one control value per audio block. [modulated_effect.gd](../demo/examples/modulated_effect.gd) is a complete runnable example.

Save and load native presets:

```gdscript
if not network.save_patch("user://my_effect.json", true):
    push_error(network.get_last_error()) # true explicitly allows overwriting

# Stop playback before loading.
audio.stop_audio()
if not network.load_patch_file("user://my_effect.json"):
    push_error(network.get_last_error())
```

`user://` is Godot's writable application-data folder. Use **Project → Open User Data Folder** to find saved files. Loading a patch does not start playback; start the device again when ready.

## 7. Discover what is available

```gdscript
print(network.get_supported_node_types())
print(network.get_nodes())
print(network.get_connections())
print(JUCE.get_api_manifest())
```

The API exposes 23 reference-counted classes and 232 methods, plus the legacy tone-demo class. It covers the supported buffers, MIDI, file operations and DSP processors; it does not expose every JUCE C++ function. GDScript controls native processors but is not called once per audio sample. New native processor implementations require extending/rebuilding the binding; new combinations of supported processors are entirely GDScript.

Next, read the [DSP network guide](DSP_NETWORKS.md) for all 26 processor types, [API reference](API_REFERENCE.md) for method signatures, and [offline_processing.gd](../demo/examples/offline_processing.gd) to generate a WAV without opening an audio device.

For an on-screen instrument you can also play with computer keys, try the [MIDI keyboard example](MIDI_KEYBOARD.md). Its reusable Godot Control emits JUCE MIDI messages and its optional preview uses a native 16-voice synth assembled through this API.

To record and edit those notes, try the [MIDI clip studio](MIDI_CLIPS.md), including a live BPM control and native note playback.

The [DAW workspace](DAW_WORKSPACE.md) combines the controls into a modern pattern-based interface with a channel rack, arrangement and native mixer.

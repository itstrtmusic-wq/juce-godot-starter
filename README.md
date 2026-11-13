# JUCE audio bridge for Godot — starter 0.1

A small native GDExtension that makes JUCE audio device management and a sine-wave test tone available to GDScript. The demo builds its UI in Godot. JUCE owns audio output independently of Godot's audio mixer.

This is a starting point for a DAW engine, not a wrapper for the entire JUCE API. It does not yet provide tracks, recording, MIDI, transport, file playback, DSP effect chains, ASIO, or VST hosting.

## Download a Windows build from GitHub

Once this source is uploaded to GitHub, its Windows addon build workflow runs on pushes to `main` and pull requests. It can also be started manually from the Actions tab.

Open **Actions → Windows addon build**, choose a successful run, and download **juce-godot-windows-x86_64** from its Artifacts section. GitHub may require you to sign in. Extract the artifact and the packaged ZIP inside it, then import `project.godot`. The packaged demo includes the compiled DLL; you do not need a compiler to run that build. Artifact availability is subject to repository retention settings.

A successful workflow verifies Windows compilation and offline audio tests. Windows audio hardware and Godot 4.7 still need testing on your machine.

## Windows 11 setup (64-bit Godot)

You do not need to edit C++ to run the demo, but you do need to compile the native DLL once.

1. Install **Visual Studio 2022 Community** or **Build Tools for Visual Studio 2022**. Select **Desktop development with C++**, including the MSVC v143 compiler and a Windows SDK.
2. Install **Git**, **Python 3**, and **CMake 3.22 or newer**, and make them available on PATH. Reopen PowerShell afterward. `python --version`, `git --version`, and `cmake --version` should work.
3. Extract this project into a writable folder. In that folder, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
   ```

   The command downloads pinned JUCE and godot-cpp sources from GitHub and builds the DLL. The first build takes longer.
4. Import `demo/project.godot` in Godot. Run the project, choose an output device, click **Start audio**, then enable the test tone. Tone starts disabled and gain defaults to 0.05.
5. To use the bridge in another project, copy `demo/addons/juce_bridge` into that project's `addons` folder after building, then reopen the editor. There is no EditorPlugin to enable; the `.gdextension` registers the class.

Close Godot before rebuilding the DLL: native hot reload is disabled so an active audio callback cannot outlive its library. This build targets Windows x86_64, not Windows ARM64 or Godot builds using double precision.

## Godot 4.7 compatibility

The bridge uses godot-cpp's pinned 4.5 baseline and declares Godot 4.5 as its minimum. GDExtension's forward compatibility is intended to support later Godot 4 versions. The available validation engine is **Godot 4.6.3 on Linux**, not Godot 4.7 on Windows. Windows compilation, Windows audio hardware, and your exact 4.7 editor remain unverified. If your editor reports an ABI/load error, preserve its exact output so the bindings can be adjusted.

## GDScript API

```gdscript
extends Node

var audio: Node

func _ready():
    audio = ClassDB.instantiate("JuceEngine")
    add_child(audio)
    audio.connect("audio_error", func(message): push_error(message))
    audio.set_frequency(220.0)
    audio.set_gain(0.05)
    audio.set_tone_enabled(true)
    if not audio.start_audio("", 48000.0, 256):
        push_error(audio.get_last_error())

func _exit_tree():
    if is_instance_valid(audio):
        audio.stop_audio()
```

| Method | Meaning |
| --- | --- |
| `get_output_devices()` | Output names for JUCE's first available backend; WASAPI shared on a normal Windows build. |
| `start_audio(device = "", sample_rate = 48000, buffer_size = 256)` | Opens stereo output; empty name selects the default. Returns a success boolean. Restarts an existing stream. |
| `stop_audio()` | Closes the stream; safe to call repeatedly. |
| `is_running()` | Current callback/device state. |
| `set_frequency(hz)` | Tone frequency, clamped to 20–20,000 Hz and below Nyquist during rendering. |
| `set_gain(linear)` | Linear gain clamped to 0–1, with a 5 ms ramp. Non-finite parameter values are ignored. |
| `set_tone_enabled(enabled)` | Ramps the tone in/out without closing the device. |
| `get_peak()` | Absolute peak from the most recent audio block, 0–1. Poll from `_process`. |
| `get_last_error()` | Most recent startup error. |
| `get_device_info()` | Actual name, sample rate, buffer size and output latency in samples; empty if closed. |

Signals: `audio_started`, `audio_stopped`, and `audio_error(message)`. These report explicit start/stop operations on the calling Godot thread. They do not report every hardware hot-plug or asynchronous runtime error. Poll `is_running()` for the current state.

Use a single engine instance. Call its API on Godot's main thread. Keep it alive while audio runs; adding it as a child handles its lifetime. Destruction closes the device even without an explicit stop.

Device support varies: a requested sample rate or buffer size may be adjusted by the driver. Check `get_device_info()` after starting. This starter exposes the first backend only, has no ASIO SDK dependency, and does not route JUCE sound through Godot's buses or effects.

## Audio-thread boundary

The JUCE callback renders the sine wave and uses JUCE's SmoothedValue for gain changes. It reads lock-free atomic control parameters and writes a lock-free peak value. It performs no GDScript calls, Godot API calls, allocations, signal emissions or mutex locking. Gain ramps reduce discontinuities when toggling/muting. Frequency changes are block updates and are not yet smoothed.

For additional callbacks, pass events through a bounded queue and drain them on Godot's main thread. Never invoke GDScript directly from JUCE's real-time audio callback. A full processing graph will also need a safe mechanism to replace graph state without destroying objects on the audio thread.

## Validation

`build_windows.ps1` runs the offline tone tests after building. Tests check frequency, stereo equality, RMS/peak level, mute settling, gain limiting and null output channels, using explicit checks that remain active in Release.

Additional commands after building:

```powershell
# Use the path to your own Godot executable.
Godot.exe --headless --path demo --editor --import
Godot.exe --headless --path demo --script res://smoke_test.gd
```

The smoke test checks class registration, parameter calls, invalid startup handling, error signals and repeated shutdown. It does not open audio hardware.

Linux CI can build with `-DBRIDGE_NO_AUDIO_DEVICE=ON` to validate without ALSA development headers. This deliberately disables all Linux audio-device backends; do not use that option for real audio playback. Normal Linux builds require ALSA development headers and pkg-config.

## Extending toward a DAW

A useful next milestone is file playback plus a small JUCE DSP effect chain, then tracks/routing and transport. MIDI instruments, recording and VST3 hosting are separate additions. Plugin hosting also requires decisions about plugin scanning, crashes and editor windows. They are not provided by exposing a few more methods.

Dependencies are pinned to JUCE 8.0.9 and godot-cpp godot-4.5-stable. JUCE is available under AGPLv3 or a commercial JUCE licence; choose a suitable licence before distributing a JUCE-based product. godot-cpp uses the MIT licence. Dependency sources downloaded by CMake contain their respective licence texts.

# Validation record

Validated in this session on Linux x86_64 with GCC 14.2, CMake 4.4.4, JUCE 8.0.9, godot-cpp 4.5 bindings and Godot 4.6.3.

- Native bridge compiled and linked successfully, with Linux audio-device backends explicitly disabled for headless validation.
- CTest tone test passed: frequency, RMS, peak, stereo, mute, gain clamping, null output channels.
- Godot imported the project and loaded the extension.
- GDScript smoke test passed: registration, parameter calls, invalid startup, error signal, shutdown, no-device enumeration and no-device startup failure.
- Demo main scene ran headlessly for five frames with no script errors.

Not verified: Windows compilation, Windows 11 audio playback, Godot 4.7, real device latency, device hot-plug behavior. No Windows DLL is included. Run build_windows.ps1 on Windows before importing the addon.

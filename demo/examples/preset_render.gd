extends SceneTree
## Run: Godot --headless --path demo --script res://examples/preset_render.gd
## Save a modulated DSP patch, reload it, then render a WAV without opening audio hardware.

func _initialize() -> void:
    var network := JuceDSPNetwork.new()
    network.add_node("tone", "oscillator")
    network.add_node("filter", "low_pass")
    network.add_node("slow", "lfo")
    network.add_node("chorus", "chorus")
    network.add_node("level", "gain")
    network.add_node("guard", "limiter")
    network.connect_nodes("tone", "filter")
    network.connect_nodes("filter", "chorus")
    network.connect_nodes("chorus", "level")
    network.connect_nodes("level", "guard")
    network.connect_nodes("guard", "output")
    network.set_parameter("tone", "frequency", 110.0)
    network.set_parameter("tone", "waveform", 1.0)
    network.set_parameter("tone", "gain", 0.05)
    network.set_parameter("filter", "frequency", 2200.0)
    network.set_parameter("level", "gain_db", -12.0)
    network.connect_parameter("slow", "filter", "frequency", 1600.0)
    var patch_path := "user://modulated_effect.json"
    if not network.save_patch(patch_path, true):
        push_error(network.get_last_error())
        quit(1)
        return
    var loaded := JuceDSPNetwork.new()
    if not loaded.load_patch_file(patch_path) or not loaded.prepare(48000.0, 128, 2):
        push_error(loaded.get_last_error())
        quit(1)
        return
    var buffer := JuceAudioBuffer.new()
    if not buffer.set_size(2, 96000) or not loaded.process(buffer):
        push_error("Could not render the patch")
        quit(1)
        return
    var formats := JuceAudioFormatManager.new()
    var output_path := "user://modulated_effect.wav"
    if not formats.write_wav(output_path, buffer, 48000.0, 24, true):
        push_error(formats.get_last_error())
        quit(1)
        return
    print("Saved patch and rendered: ", ProjectSettings.globalize_path(output_path))
    quit(0)

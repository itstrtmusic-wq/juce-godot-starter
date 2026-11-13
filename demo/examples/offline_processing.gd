extends SceneTree
## Run: Godot --headless --path demo --script res://examples/offline_processing.gd
## Builds an oscillator/filter/delay network in GDScript and renders a WAV.

func _initialize() -> void:
    var network := JuceDSPNetwork.new()
    network.add_node("osc", "oscillator")
    network.add_node("filter", "low_pass")
    network.add_node("echo", "delay")
    network.connect_nodes("osc", "filter")
    network.connect_nodes("filter", "echo")
    network.connect_nodes("echo", "output")
    network.set_parameter("osc", "frequency", 220.0)
    network.set_parameter("osc", "gain", 0.05)
    network.set_parameter("filter", "frequency", 1800.0)
    network.set_parameter("echo", "delay_ms", 250.0)
    var buffer := JuceAudioBuffer.new()
    buffer.set_size(2, 48000 * 2)
    network.prepare(48000.0, 512, 2)
    network.process(buffer)
    var formats := JuceAudioFormatManager.new()
    var path := "user://custom_effect_render.wav"
    if not formats.write_wav(path, buffer, 48000.0, 24, true):
        push_error(formats.get_last_error())
        quit(1)
        return
    print("Rendered: ", ProjectSettings.globalize_path(path))
    quit(0)

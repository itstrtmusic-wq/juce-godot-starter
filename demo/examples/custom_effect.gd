extends Node
## Attach to a node to run a custom native effect on your default live audio input.
## No C++ edits or GDScript audio-thread callback are needed.

var network: JuceDSPNetwork
var device: JuceAudioDeviceManager

func _ready() -> void:
    network = JuceDSPNetwork.new()
    device = JuceAudioDeviceManager.new()
    network.add_node("low_cut", "high_pass")
    network.add_node("drive", "tanh")
    network.add_node("delay", "delay")
    network.add_node("wet_level", "gain")
    network.add_node("dry_level", "gain")
    network.add_node("guard", "clip")
    # Parallel dry and distorted/delayed paths sum at the output guard.
    network.connect_nodes("input", "low_cut")
    network.connect_nodes("low_cut", "drive")
    network.connect_nodes("drive", "delay")
    network.connect_nodes("delay", "wet_level")
    network.connect_nodes("wet_level", "guard")
    network.connect_nodes("input", "dry_level")
    network.connect_nodes("dry_level", "guard")
    network.connect_nodes("guard", "output")
    network.set_parameter("low_cut", "frequency", 100.0)
    network.set_parameter("drive", "drive", 3.0)
    network.set_parameter("delay", "delay_ms", 375.0)
    network.set_parameter("delay", "feedback", 0.4)
    network.set_parameter("delay", "mix", 1.0)
    network.set_parameter("wet_level", "gain_db", -12.0)
    network.set_parameter("dry_level", "gain_db", -6.0)
    network.set_parameter("guard", "threshold", 0.9)
    device.set_network(network)
    if not device.start_audio("", 48000.0, 256, "", true):
        push_error(device.get_last_error())

func set_drive(amount: float) -> void:
    # Bind a Godot slider to this function. Scalar updates work during playback.
    network.set_parameter("drive", "drive", amount)

func _exit_tree() -> void:
    if device != null:
        device.stop_audio()

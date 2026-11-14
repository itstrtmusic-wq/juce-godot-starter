extends Node
## A native LFO sweeps the cutoff of a JUCE filter while GDScript handles controls.
## Attach to a node and run. Enable monitor_input to use an audio interface instead of the test tone.

@export var monitor_input := false
var network: JuceDSPNetwork
var audio: JuceAudioDeviceManager

func _ready() -> void:
    network = JuceDSPNetwork.new()
    audio = JuceAudioDeviceManager.new()
    network.add_node("tone", "oscillator")
    network.add_node("filter", "low_pass")
    network.add_node("slow", "lfo")
    network.add_node("chorus", "chorus")
    network.add_node("level", "gain")
    network.add_node("guard", "limiter")
    network.set_parameter("tone", "frequency", 110.0)
    network.set_parameter("tone", "waveform", 1.0)
    network.set_parameter("tone", "gain", 0.05)
    network.set_parameter("filter", "frequency", 2200.0)
    network.set_parameter("slow", "rate_hz", 0.75)
    network.set_parameter("chorus", "mix", 0.25)
    network.set_parameter("level", "gain_db", -12.0)
    var origin := "input" if monitor_input else "tone"
    network.connect_nodes(origin, "filter")
    network.connect_nodes("filter", "chorus")
    network.connect_nodes("chorus", "level")
    network.connect_nodes("level", "guard")
    network.connect_nodes("guard", "output")
    # effective cutoff = base cutoff + first LFO sample in each block × 1600 Hz.
    network.connect_parameter("slow", "filter", "frequency", 1600.0)
    audio.set_network(network)
    if not audio.start_audio("", 48000.0, 128, "", monitor_input):
        push_error(audio.get_last_error())

func set_lfo_speed(hz: float) -> void:
    network.set_parameter("slow", "rate_hz", hz)

func save_preset(path: String) -> bool:
    return network.save_patch(path) # Existing files require explicit overwrite=true.

func _exit_tree() -> void:
    if audio != null:
        audio.stop_audio()

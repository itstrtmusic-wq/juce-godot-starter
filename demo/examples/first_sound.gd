extends Node
## Attach this script to a Node in a new scene, then press F6.
## JUCE owns the audio device; this does not use Godot's audio buses.

@export var output_device := "" # Empty means the default output device.
var network := JuceDSPNetwork.new()
var audio := JuceAudioDeviceManager.new()

func _ready() -> void:
    if not _build_sound():
        push_error(network.get_last_error())
        return
    print("JUCE outputs: ", audio.get_output_devices())
    if not audio.set_network(network):
        push_error(audio.get_last_error())
        return
    if not audio.start_audio(output_device, 48000.0, 256, "", false):
        push_error(audio.get_last_error())
        return
    print("JUCE running: ", audio.get_device_info())

func _build_sound() -> bool:
    # Node IDs are names you choose; node types are names supported by the API.
    return (
        network.add_node("tone", "oscillator")
        and network.add_node("filter", "low_pass")
        and network.add_node("volume", "gain")
        and network.set_parameter("tone", "frequency", 220.0)
        and network.set_parameter("tone", "gain", 0.1)
        and network.set_parameter("filter", "frequency", 1800.0)
        and network.set_parameter("volume", "gain_db", -12.0)
        and network.connect_nodes("tone", "filter")
        and network.connect_nodes("filter", "volume")
        and network.connect_nodes("volume", "output")
    )

# Connect your own HSlider's value_changed signal to this method.
func set_cutoff(hz: float) -> void:
    if not network.set_parameter("filter", "frequency", hz):
        push_error(network.get_last_error())

func _exit_tree() -> void:
    audio.stop_audio()

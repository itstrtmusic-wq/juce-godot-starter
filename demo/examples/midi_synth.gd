extends Node
## A monophonic MIDI synth assembled from native DSP nodes in GDScript.
## Connect a MIDI controller before running this example.

var network: JuceDSPNetwork
var audio: JuceAudioDeviceManager
var midi: JuceMidiInput
var held_note := -1

func _ready() -> void:
    network = JuceDSPNetwork.new()
    audio = JuceAudioDeviceManager.new()
    midi = JuceMidiInput.new()
    network.add_node("osc", "oscillator")
    network.add_node("envelope", "adsr")
    network.add_node("filter", "low_pass")
    network.connect_nodes("osc", "envelope")
    network.connect_nodes("envelope", "filter")
    network.connect_nodes("filter", "output")
    network.set_parameter("osc", "waveform", 1.0)
    network.set_parameter("osc", "gain", 0.08)
    network.set_parameter("filter", "frequency", 2500.0)
    audio.set_network(network)
    if not audio.start_audio():
        push_error(audio.get_last_error())
        return
    var devices := JuceMidiInput.get_available_devices()
    if devices.is_empty():
        push_warning("No MIDI input device. Connect a controller and run again.")
    elif not midi.open_device(devices[0].identifier):
        push_error(midi.get_last_error())

func _process(_delta: float) -> void:
    if midi == null:
        return
    for message in midi.read_events():
        if message.is_note_on():
            held_note = message.get_note_number()
            network.set_parameter("osc", "frequency", JUCE.midi_note_to_hz(held_note))
            network.set_parameter("envelope", "gate", 1.0)
        elif message.is_note_off() and message.get_note_number() == held_note:
            network.set_parameter("envelope", "gate", 0.0)
            held_note = -1

func _exit_tree() -> void:
    if midi != null:
        midi.close_device()
    if audio != null:
        audio.stop_audio()

extends RefCounted
## Small 16-voice preview instrument made entirely from the existing GDScript API.
## MIDI events are handled on the main thread; native DSP performs the audio work.

const VOICE_COUNT := 16
const RELEASE_SECONDS := 0.18
var network := JuceDSPNetwork.new()
var audio := JuceAudioDeviceManager.new()
var last_error := ""
var _voices: Array[Dictionary] = []
var _sustain := false
var _built := false
var _reuse_guard_us := 20000

func build_network() -> bool:
    if _built:
        return true
    if not network.add_node("master", "gain") or not network.add_node("guard", "limiter"):
        return _graph_error()
    network.set_parameter("master", "gain_db", -9.0)
    network.set_parameter("guard", "threshold_db", -1.0)
    network.connect_nodes("master", "guard")
    network.connect_nodes("guard", "output")
    for index in VOICE_COUNT:
        var osc := "osc_%d" % index
        var env := "env_%d" % index
        if not network.add_node(osc, "oscillator") or not network.add_node(env, "adsr"):
            return _graph_error()
        network.set_parameter(osc, "waveform", 1.0)
        network.set_parameter(osc, "gain", 0.0)
        network.set_parameter(env, "attack", 0.008)
        network.set_parameter(env, "decay", 0.12)
        network.set_parameter(env, "sustain", 0.7)
        network.set_parameter(env, "release", RELEASE_SECONDS)
        if not network.connect_nodes(osc, env) or not network.connect_nodes(env, "master"):
            return _graph_error()
        _voices.append({"osc": osc, "env": env, "note": -1, "held": false, "ready_at": 0})
    _built = true
    return true

func _graph_error() -> bool:
    last_error = network.get_last_error()
    return false

func start(output_device := "") -> bool:
    stop()
    last_error = ""
    if not build_network():
        return false
    if not audio.set_network(network) or not audio.start_audio(output_device):
        last_error = audio.get_last_error()
        return false
    var info := audio.get_device_info()
    # Give note-off a full callback to be observed before recycling its voice.
    _reuse_guard_us = maxi(20000, ceili(2e6 * float(info.buffer_size) / float(info.sample_rate)))
    return true

func stop() -> void:
    audio.stop_audio()
    panic()

func panic() -> void:
    _sustain = false
    for voice in _voices:
        network.set_parameter(voice.env, "gate", 0.0)
        network.set_parameter(voice.osc, "gain", 0.0)
        voice.note = -1
        voice.held = false
        voice.ready_at = Time.get_ticks_usec() + _reuse_guard_us

func handle_midi(message: JuceMidiMessage) -> bool:
    if not _built:
        return false
    if message.is_note_on():
        return _note_on(message.get_note_number(), message.get_velocity())
    if message.is_note_off():
        for voice in _voices:
            if voice.note == message.get_note_number() and voice.held:
                voice.held = false
                if not _sustain:
                    _release(voice)
    elif message.is_controller():
        if message.get_controller_number() == 64:
            _sustain = message.get_controller_value() >= 64
            if not _sustain:
                for voice in _voices:
                    if voice.note >= 0 and not voice.held:
                        _release(voice)
        elif message.get_controller_number() in [120, 123]:
            panic()
    return true

func _note_on(note: int, strength: float) -> bool:
    for voice in _voices:
        if voice.note == note and voice.held:
            _release(voice)
    for voice in _voices:
        if voice.note == -1 and Time.get_ticks_usec() >= int(voice.ready_at):
            voice.note = note
            voice.held = true
            network.set_parameter(voice.osc, "frequency", JUCE.midi_note_to_hz(note))
            network.set_parameter(voice.osc, "gain", 0.04 * strength)
            network.set_parameter(voice.env, "gate", 1.0)
            return true
    # Do not steal/retrigger a voice inside the same block: gates are block-rate.
    last_error = "Preview voice limit reached. MIDI events still reach your instrument."
    return false

func _release(voice: Dictionary) -> void:
    network.set_parameter(voice.env, "gate", 0.0)
    voice.note = -1
    voice.held = false
    voice.ready_at = Time.get_ticks_usec() + int(RELEASE_SECONDS * 1e6) + _reuse_guard_us

func set_waveform(value: int) -> void:
    for voice in _voices:
        network.set_parameter(voice.osc, "waveform", clampi(value, 0, 3))

func set_volume(db: float) -> void:
    network.set_parameter("master", "gain_db", db)

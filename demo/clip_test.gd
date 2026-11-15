extends SceneTree

const Clip = preload("res://addons/juce_bridge/ui/midi_clip.gd")
const Roll = preload("res://addons/juce_bridge/ui/piano_roll.gd")

# Device adapter drives the real native renderer deterministically without hardware.
class OfflineDevice extends RefCounted:
    var running := false
    var sequence: RefCounted
    func get_output_devices() -> PackedStringArray:
        return PackedStringArray(["Offline test"])
    func set_sequencer(value: RefCounted) -> bool:
        sequence = value
        return true
    func start_audio(_name := "") -> bool:
        running = sequence.prepare(48000.0, 2)
        return running
    func stop_audio() -> void:
        if running:
            sequence.stop()
            render(128)
        running = false
    func is_running() -> bool:
        return running
    func get_last_error() -> String:
        return "Offline device failed"
    func get_peak() -> float:
        return 0
    func render(samples: int) -> JuceAudioBuffer:
        var buffer := JuceAudioBuffer.new()
        assert(buffer.set_size(2, samples))
        assert(sequence.process(buffer), sequence.get_last_error())
        return buffer

var canvas: Control

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_document()
    _test_api()
    await _test_roll()
    await _test_workflow()
    print("JUCE clip: documents, MIDI export, native API, piano-roll input, BPM and record/stop/play workflow passed")
    quit(0)

func _test_document() -> void:
    var clip = Clip.new()
    var id: int = clip.add_note(60, 0.13, 0.63, 0.75)
    assert(id > 0 and clip.is_dirty())
    assert(clip.set_bpm(97.5))
    assert(not clip.set_bpm(NAN))
    assert(not clip.set_bpm(0))
    clip.quantize(0.25)
    assert(clip.notes[0].start == 0.25 and clip.notes[0].length == 0.5)
    clip.undo()
    assert(clip.notes[0].start == 0.13)
    clip.redo()
    assert(clip.notes[0].start == 0.25)
    var before: Dictionary = clip.document()
    var broken := before.duplicate(true)
    broken.notes[0].note = 129
    assert(not clip.load_document(broken) and clip.document() == before)
    broken = before.duplicate(true)
    broken.bpm = true
    assert(not clip.load_document(broken) and clip.document() == before)
    assert(not clip.set_length(0.5))

    var prefix := "user://clip_test_音_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    var path := prefix + ".midiclip.json"
    assert(clip.save_file(path) and not clip.is_dirty())
    assert(not clip.save_file(path))
    var loaded = Clip.new()
    assert(loaded.load_file(path))
    assert(loaded.document() == clip.document())
    assert(clip.export_midi(prefix + ".mid"))
    var midi := JuceMidiFile.new()
    assert(midi.read_file(prefix + ".mid") and midi.get_num_tracks() == 1)
    var events: Array = midi.get_track(0).get_events()
    assert(events.size() >= 3)
    var found_note := false
    var found_tempo := false
    for event in events:
        if event.is_note_on():
            assert(event.get_note_number() == 60 and abs(event.get_timestamp() - 240) < 0.01)
            found_note = true
        if event.is_tempo_meta_event():
            found_tempo = true
    assert(found_note and found_tempo)
    for suffix in [".midiclip.json", ".mid"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))

    var take = Clip.new()
    take.begin_take()
    take.add_recorded({"note": 64, "channel": 1, "start": 15.5, "length": 1.0, "velocity": 0.8})
    take.end_take()
    assert(take.notes.size() == 2 and take.notes[0].length == 0.5 and take.notes[1].start == 0)
    take.undo()
    assert(take.notes.is_empty()) # Whole take is one undo step.

func _test_api() -> void:
    var player := JuceMidiSequencer.new()
    assert(player.set_bpm(80) and player.get_bpm() == 80)
    assert(not player.set_bpm(INF) and not player.set_bpm(301))
    assert(not player.set_volume_db(1) and not player.set_waveform(4))
    var notes := [{"note": 60, "start": 0.5, "length": 0.5, "velocity": 0.8}]
    assert(player.load_clip(notes, 4))
    var original := player.export_clip()
    assert(not player.load_clip([{"note": 60.5, "start": 0, "length": 1, "velocity": 1}], 4))
    assert(player.export_clip() == original)
    assert(player.prepare(48000, 2))
    player.set_looping(false)
    player.play()
    var buffer := JuceAudioBuffer.new()
    assert(buffer.set_size(2, 48000))
    assert(player.process(buffer) and buffer.get_magnitude(0) > 0.001)
    assert(abs(player.get_transport().beat - 80.0 / 60.0) < 0.00001)
    assert(not player.queue_midi(JuceMidiMessage.program_change(1, 1)))
    var device := JuceAudioDeviceManager.new()
    assert(device.set_sequencer(player))
    assert(not device.start_audio("", -1))
    assert(not player.get_transport().active)
    assert(not device.start_audio("", 48000.0, 256, "", true))
    assert(not player.get_transport().active)
    device.stop_audio()
    assert(device.set_network(JuceDSPNetwork.new()))

func _test_roll() -> void:
    canvas = Roll.new()
    canvas.position = Vector2(10, 10)
    canvas.size = Vector2(900, 320)
    root.add_child(canvas)
    var clip = Clip.new()
    canvas.set_document(clip)
    await process_frame
    var point: Vector2 = canvas.position + Vector2(150, 110)
    _mouse(point, true)
    _mouse(point, false)
    assert(clip.notes.size() == 1)
    var first: Dictionary = clip.notes[0].duplicate()
    assert(is_zero_approx(fposmod(first.start, 0.25)))
    var rect: Rect2 = canvas.note_rect(first)
    var move_point := rect.position + Vector2(3, 8) + canvas.position
    _mouse(move_point, true)
    _motion(move_point + Vector2(48, -18))
    _mouse(move_point + Vector2(48, -18), false)
    assert(clip.notes[0].start == first.start + 1 and clip.notes[0].note == first.note + 1)
    rect = canvas.note_rect(clip.notes[0])
    var edge := rect.position + Vector2(rect.size.x - 2, 8) + canvas.position
    _mouse(edge, true)
    _motion(edge + Vector2(24, 0))
    _mouse(edge + Vector2(24, 0), false)
    assert(clip.notes[0].length == first.length + 0.5)
    _key(KEY_DELETE, true)
    assert(clip.notes.is_empty())
    clip.undo()
    assert(clip.notes.size() == 1)
    canvas.queue_free()
    await process_frame

func _test_workflow() -> void:
    var demo = load("res://examples/clip_recorder.tscn").instantiate()
    var device := OfflineDevice.new()
    demo.audio = device
    root.add_child(demo)
    await process_frame
    assert(demo.start_transport(true))
    _key(KEY_Z, true)
    device.render(12000) # Half a beat at 120 BPM.
    demo._bpm.value = 60
    assert(demo.player.get_bpm() == 60)
    device.render(12000) # Quarter of a beat at 60 BPM.
    _key(KEY_Z, false)
    device.render(128)
    demo.stop_transport()
    assert(demo.model.notes.size() == 1)
    assert(demo.model.notes[0].note == 60)
    assert(abs(demo.model.notes[0].length - 0.75) < 0.00001)
    assert(demo.model.bpm == 60)
    assert(demo.start_transport(false))
    var sound := device.render(24000)
    assert(sound.get_magnitude(0) > 0.001)
    demo.stop_transport()
    demo.model.undo()
    assert(demo.model.notes.is_empty())
    demo.queue_free()
    await process_frame

func _mouse(point: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.global_position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.pressed = pressed
    root.push_input(event)

func _motion(point: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = point
    event.global_position = point
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(event)

func _key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    root.push_input(event)

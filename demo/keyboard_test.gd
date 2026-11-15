extends SceneTree

const Keyboard = preload("res://addons/juce_bridge/ui/midi_keyboard.gd")
const Synth = preload("res://examples/keyboard_synth.gd")
var piano: Control
var events: Array[JuceMidiMessage] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    root.size = Vector2i(1100, 800)
    piano = Keyboard.new()
    piano.position = Vector2(20, 20)
    piano.size = Vector2(900, 270)
    root.add_child(piano)
    piano.midi_message.connect(func(message: JuceMidiMessage): events.append(message))
    await process_frame

    # Real viewport key dispatch, echo suppression, chords and release pairs.
    _key(KEY_Z, true)
    _key(KEY_Z, true, true)
    _key(KEY_C, true)
    _key(KEY_B, true)
    assert(piano.get_active_notes() == [60, 64, 67])
    assert(events.size() == 3)
    assert(events[0].is_note_on() and events[0].get_note_number() == 60)
    assert(abs(events[0].get_velocity() - 100.0 / 127.0) < 0.01)
    _key(KEY_Z, false)
    _key(KEY_C, false)
    _key(KEY_B, false)
    assert(piano.get_active_notes().is_empty())
    assert(events.size() == 6 and events[5].is_note_off())

    # Q and comma are aliases for C5; releasing one must not stop the other.
    events.clear()
    _key(KEY_Q, true)
    _key(KEY_COMMA, true)
    assert(events.size() == 1 and events[0].get_note_number() == 72)
    _key(KEY_Q, false)
    assert(piano.get_active_notes() == [72])
    _key(KEY_COMMA, false)
    assert(events.size() == 2 and events[1].is_note_off())

    events.clear()
    _key(KEY_Z, true, false, true)
    assert(events.is_empty()) # Ctrl+Z remains an application shortcut.
    var field := LineEdit.new()
    field.position = Vector2(20, 400)
    field.size = Vector2(180, 36)
    root.add_child(field)
    field.grab_focus()
    _key(KEY_Z, true)
    assert(piano.get_active_notes().is_empty())
    field.release_focus()
    _key(KEY_Z, true)
    field.grab_focus()
    _key(KEY_Z, false)
    assert(piano.get_active_notes().is_empty()) # Key-up survives a focus change.
    field.release_focus()
    field.queue_free()

    events.clear()
    _key(KEY_SPACE, true)
    _key(KEY_Z, true)
    _key(KEY_Z, false)
    assert(piano.is_sustain_down())
    assert(events[0].is_controller() and events[0].get_controller_value() == 127)
    assert(events[2].is_note_off()) # Real MIDI note-off is still sent under sustain.
    _key(KEY_SPACE, false)
    assert(not piano.is_sustain_down())
    assert(events[3].get_controller_value() == 0)

    _key(KEY_Z, true)
    _key(KEY_BRACKETRIGHT, true)
    assert(piano.base_note == 72 and piano.get_active_notes().is_empty())
    _key(KEY_Z, false)
    piano.base_note = 60
    assert(piano.set_key_mapping({KEY_A: 4}))
    assert(not piano.set_key_mapping({KEY_A: 999}))
    assert(not piano.set_key_mapping({KEY_SPACE: 0}))
    _key(KEY_A, true)
    assert(piano.get_active_notes() == [64])
    _key(KEY_A, false)
    assert(piano.set_key_mapping(Keyboard.DEFAULT_MAPPING))

    # Black keys win overlap tests. Mouse + typing use independent hold sources.
    var black: Rect2 = piano.get_note_rect(61)
    assert(piano.get_note_at_position(black.get_center()) == 61)
    var white: Rect2 = piano.get_note_rect(60)
    var c_point := Vector2(white.get_center().x, white.end.y - 65)
    _mouse_button(c_point + piano.position, true)
    assert(piano.get_active_notes() == [60])
    _key(KEY_Z, true)
    _mouse_button(Vector2(1000, 600), false)
    assert(piano.get_active_notes() == [60])
    _key(KEY_Z, false)
    assert(piano.get_active_notes().is_empty())

    _mouse_button(black.get_center() + piano.position, true)
    var d: Rect2 = piano.get_note_rect(62)
    _mouse_motion(Vector2(d.get_center().x, d.end.y - 65) + piano.position)
    assert(piano.get_active_notes() == [62])
    _mouse_button(Vector2(1000, 600), false)
    assert(piano.get_active_notes().is_empty())

    _key(KEY_Z, true)
    piano.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    assert(piano.get_active_notes().is_empty())
    _key(KEY_Z, true)
    piano.hide()
    assert(piano.get_active_notes().is_empty())
    piano.show()
    _key(KEY_Z, true)
    piano.typing_enabled = false
    assert(piano.get_active_notes().is_empty())
    _key(KEY_Z, true)
    assert(piano.get_active_notes().is_empty())
    piano.typing_enabled = true

    _test_synth()
    piano.queue_free()
    await process_frame
    # The actual example scene must load and clean up without opening hardware.
    var demo = load("res://examples/typing_keyboard.tscn").instantiate()
    root.add_child(demo)
    await process_frame
    demo.queue_free()
    await process_frame
    print("JUCE keyboard: typing, chords, aliases, mouse, sustain, focus and polyphonic rendering passed")
    quit(0)

func _test_synth() -> void:
    var synth = Synth.new()
    assert(synth.build_network())
    assert(synth.network.prepare(48000.0, 256, 2))
    var buffer := JuceAudioBuffer.new()
    assert(buffer.set_size(2, 12000))
    assert(synth.handle_midi(JuceMidiMessage.note_on(1, 60, 0.8)))
    assert(synth.handle_midi(JuceMidiMessage.note_on(1, 64, 0.8)))
    assert(synth.handle_midi(JuceMidiMessage.note_on(1, 67, 0.8)))
    var held := 0
    for voice in synth._voices:
        if voice.held:
            held += 1
    assert(held == 3)
    assert(synth.network.process(buffer))
    assert(buffer.get_rms_level(0) > 0.001)
    for sample in buffer.get_channel(0):
        assert(is_finite(sample) and abs(sample) <= 1.0)

    assert(synth.handle_midi(JuceMidiMessage.controller_event(1, 64, 127)))
    for note in [60, 64, 67]:
        assert(synth.handle_midi(JuceMidiMessage.note_off(1, note)))
    for voice in synth._voices:
        if voice.note >= 0:
            assert(not voice.held and synth.network.get_parameters(voice.env).gate == 1.0)
    assert(synth.network.process(buffer))
    assert(buffer.get_rms_level(0) > 0.001)
    assert(synth.handle_midi(JuceMidiMessage.controller_event(1, 64, 0)))
    assert(synth.network.process(buffer))
    assert(synth.network.process(buffer))
    assert(buffer.get_magnitude(0) < 0.00001)
    assert(synth.handle_midi(JuceMidiMessage.note_on(1, 72, 1.0)))
    synth.panic()
    assert(synth.network.process(buffer))
    assert(buffer.get_magnitude(0) == 0.0)

    # Exhaustion is explicit; it must not steal a held voice or leave a stuck gate.
    var full = Synth.new()
    assert(full.build_network())
    for note in range(48, 48 + Synth.VOICE_COUNT):
        assert(full.handle_midi(JuceMidiMessage.note_on(1, note, 1.0)))
    assert(not full.handle_midi(JuceMidiMessage.note_on(1, 90, 1.0)))
    full.panic()
    for voice in full._voices:
        assert(voice.note == -1 and full.network.get_parameters(voice.env).gate == 0.0)

func _key(code: int, pressed: bool, echo := false, ctrl := false) -> void:
    var event := InputEventKey.new()
    event.physical_keycode = code
    event.keycode = code
    event.pressed = pressed
    event.echo = echo
    event.ctrl_pressed = ctrl
    root.push_input(event)

func _mouse_button(point: Vector2, pressed: bool) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.global_position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
    event.pressed = pressed
    root.push_input(event)

func _mouse_motion(point: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = point
    event.global_position = point
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(event)

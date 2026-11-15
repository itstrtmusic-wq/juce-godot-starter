extends SceneTree

const Project = preload("res://addons/juce_bridge/ui/daw_project.gd")
const View = preload("res://addons/juce_bridge/ui/daw_pattern_view.gd")

class OfflineDevice extends RefCounted:
    var sequence: RefCounted
    var post: RefCounted
    var running := false
    var peak := 0.0
    var sample_rate := 48000.0
    func set_sequencer(value: RefCounted) -> bool:
        sequence = value
        return true
    func set_post_network(value: RefCounted) -> bool:
        post = value
        return true
    func start_audio(_name := "", rate := 48000.0, block := 256) -> bool:
        sample_rate = rate
        running = sequence.prepare(rate, 2) and post.prepare(rate, block, 2)
        return running
    func stop_audio() -> void:
        if running:
            sequence.stop()
            render(128)
        running = false
        peak = 0
    func is_running() -> bool:
        return running
    func get_peak() -> float:
        return peak
    func get_output_devices() -> PackedStringArray:
        return PackedStringArray(["Offline test"])
    func get_device_info() -> Dictionary:
        return {"sample_rate": sample_rate, "name": "Offline test"}
    func get_last_error() -> String:
        return "Offline device error"
    func render(frames: int) -> JuceAudioBuffer:
        var buffer := JuceAudioBuffer.new()
        assert(buffer.set_size(2, frames))
        assert(sequence.process(buffer))
        assert(post.process(buffer))
        peak = maxf(buffer.get_magnitude(0), buffer.get_magnitude(1))
        return buffer

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    _test_project()
    _test_api()
    await _test_workspace()
    print("JUCE workspace: project round trips, arrangement, patterns, live mixer, effects, typing, recording, windows and viewport editing passed")
    quit(0)

func _test_project() -> void:
    var project = Project.new()
    project.demo()
    assert(project.patterns.size() == 4 and project.placements.size() == 18)
    var compiled: Array = project.compile_song()
    assert(compiled.size() > 100)
    var seq := JuceMidiSequencer.new()
    assert(seq.load_clip(compiled, project.song_length))
    var baseline: Dictionary = project.document()
    project.toggle_step(0, 0, 1)
    assert(project.document() != baseline)
    project.undo()
    assert(project.document() == baseline)
    project.begin_edit()
    assert(project.set_channel(4, "volume_db", -12))
    assert(project.set_channel(4, "pan", 0.5))
    project.end_edit()
    project.undo()
    assert(project.document() == baseline)
    var invalid := baseline.duplicate(true)
    invalid.channels[0].pan = 2
    assert(not project.load_document(invalid) and project.document() == baseline)
    invalid = baseline.duplicate(true)
    invalid.patterns[0].clip.notes[0].note = 300
    assert(not project.load_document(invalid) and project.document() == baseline)
    invalid = baseline.duplicate(true)
    invalid.effects[0] = {"type": "delay", "parameters": {"feedback": "bad"}}
    assert(not project.load_document(invalid) and project.document() == baseline)
    invalid = baseline.duplicate(true)
    invalid.placements[0].start = 999
    assert(not project.load_document(invalid) and project.document() == baseline)
    var prefix := "user://workspace_音_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    assert(project.save_file(prefix + ".daw.json"))
    assert(not project.save_file(prefix + ".daw.json"))
    var copy = Project.new()
    assert(copy.load_file(prefix + ".daw.json"))
    # JSON numeric types and native Float32 velocities are normalized on load.
    assert(copy.patterns.size() == project.patterns.size())
    assert(copy.compile_song().size() == compiled.size())
    assert(copy.channels == project.channels and copy.effects == project.effects)
    assert(copy.document() == project.document())
    DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + ".daw.json"))
    var view = View.new()
    view.setup(copy)
    view.select(0, 6)
    var id: int = view.add_note(60, 5, 1, 0.8)
    assert(id > 0 and copy.patterns[0].length_beats == 8)
    assert(view.notes.size() == 1 and view.notes[0].channel == 7)
    copy.undo()
    assert(copy.patterns[0].length_beats == 4)

func _test_api() -> void:
    var seq := JuceMidiSequencer.new()
    assert(seq.set_channel_settings(1, {"volume_db": -12.0, "pan": -1.0, "mute": false, "solo": false, "waveform": 4}))
    var before := seq.get_channel_settings(1)
    assert(not seq.set_channel_settings(1, {"pan": 2, "volume_db": -20}))
    assert(seq.get_channel_settings(1) == before)
    assert(not seq.set_channel_settings(0, {}) and not seq.set_channel_settings(17, {}))
    assert(not seq.set_channel_settings(1, {"mute": 1}) and not seq.set_channel_settings(1, {5: 1}))
    assert(seq.get_channel_peaks().size() == 16)
    var device := JuceAudioDeviceManager.new()
    var fx := JuceDSPNetwork.new()
    assert(fx.connect_nodes("input", "output"))
    assert(device.set_sequencer(seq) and device.set_post_network(fx))
    assert(not device.start_audio("", -1))
    assert(not fx.is_active() and not seq.get_transport().active)
    assert(device.set_network(JuceDSPNetwork.new()))
    assert(not device.start_audio()) # Post network only applies to a sequencer source.
    assert(device.set_post_network(null))
    device.stop_audio()

func _test_workspace() -> void:
    root.size = Vector2i(1680, 980)
    var scene = load("res://daw_studio.tscn").instantiate()
    var device := OfflineDevice.new()
    scene.audio = device
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame
    assert(scene._windows.rack.visible and not scene._windows.piano.visible)
    # Real step-button input changes the pattern and can be undone.
    var grid: Control = scene.rack._widgets[0].steps
    var point := grid.get_global_rect().position + Vector2(grid.size.x / 16 * 1.5, grid.size.y / 2)
    var count: int = scene.project.patterns[0].notes.size()
    _mouse(point, true)
    _mouse(point, false)
    assert(scene.project.patterns[0].notes.size() == count + 1)
    scene._edit(func(): scene.project.undo())
    assert(scene.project.patterns[0].notes.size() == count)
    # Playlist paint, move, resize and erase use actual viewport mouse events.
    var playlist: Control = scene.playlist
    var start := playlist.get_global_rect().position + Vector2(playlist.LEFT + 8 * playlist.beat_width + 5, playlist.TOP + playlist.LANE * 4 + 12)
    var instances: int = scene.project.placements.size()
    _mouse(start, true)
    _mouse(start, false)
    assert(scene.project.placements.size() == instances + 1)
    var placed: Dictionary = scene.project.placements.back().duplicate()
    var rect: Rect2 = playlist.clip_rect(placed)
    var drag := playlist.get_global_rect().position + rect.position + Vector2(10, 20)
    _mouse(drag, true)
    _motion(drag + Vector2(4 * playlist.beat_width, 0), Vector2(4 * playlist.beat_width, 0))
    _mouse(drag + Vector2(4 * playlist.beat_width, 0), false)
    assert(scene.project.placements.back().start == placed.start + 4)
    rect = playlist.clip_rect(scene.project.placements.back())
    var edge := playlist.get_global_rect().position + rect.position + Vector2(rect.size.x - 2, 18)
    _mouse(edge, true)
    _motion(edge + Vector2(4 * playlist.beat_width, 0), Vector2(4 * playlist.beat_width, 0))
    _mouse(edge + Vector2(4 * playlist.beat_width, 0), false)
    assert(scene.project.placements.back().length == 8)
    rect = playlist.clip_rect(scene.project.placements.back())
    _mouse(playlist.get_global_rect().position + rect.position + Vector2(10, 20), true, MOUSE_BUTTON_RIGHT)
    _mouse(playlist.get_global_rect().position + rect.position + Vector2(10, 20), false, MOUSE_BUTTON_RIGHT)
    assert(scene.project.placements.size() == instances)
    scene._tempo.get_line_edit().grab_focus()
    scene._tempo.get_line_edit().text = "96.0"
    assert(scene.start_transport(false))
    assert(scene.player.get_bpm() == 96.0) # Play commits the typed BPM first.
    var sound := device.render(24000)
    assert(sound.get_rms_level(0) > 0.0001)
    for sample in sound.get_channel(0):
        assert(is_finite(sample) and abs(sample) <= 1.0001)
    scene._tempo.value = 100
    assert(scene.player.get_bpm() == 100)
    scene.mixer._widgets[4].slider.value = -15
    assert(abs(scene.player.get_channel_settings(5).volume_db + 15) < 0.001)
    scene._channel_changed(4, "solo", true)
    device.render(512) # Let the 5 ms gain ramps settle before checking silence.
    device.render(2048)
    assert(scene.player.get_channel_peaks()[0] == 0)
    scene._channel_changed(4, "solo", false)
    scene._effect_parameter(7, "threshold_db", -3)
    assert(scene.post.get_parameters("slot_7").threshold_db == -3)
    scene.stop_transport()
    # Fresh take with typing capture while the on-screen piano window is hidden.
    scene._new_project()
    assert(not scene.song_mode) # Empty projects play the rack without arranging first.
    scene.select_channel(6, false)
    scene._tempo.value = 120
    assert(scene.start_transport(true))
    _key(KEY_Z, true)
    device.render(12000)
    _key(KEY_Z, false)
    device.render(128)
    scene.stop_transport()
    assert(scene.project.patterns[0].notes.size() == 1)
    assert(scene.project.patterns[0].notes[0].note == 60 and scene.project.patterns[0].notes[0].channel == 7)
    scene._edit(func(): scene.project.undo())
    assert(scene.project.patterns[0].notes.is_empty())
    scene._toggle_window("piano")
    await process_frame
    await process_frame
    assert(scene._windows.piano.visible)
    # Move the rack window by dragging its real title bar.
    scene._show_window("rack")
    var window: Control = scene._windows.rack
    var original: Vector2 = window.position
    var title_point: Vector2 = window._header.get_global_rect().position + Vector2(150, 12)
    _mouse(title_point, true)
    _motion(title_point + Vector2(20, 10), Vector2(20, 10))
    _mouse(title_point + Vector2(20, 10), false)
    assert(window.position.distance_to(original + Vector2(20, 10)) < 1)
    window.toggle_maximize()
    assert(window.position == Vector2.ZERO)
    window.toggle_maximize()
    assert(window.position.distance_to(original + Vector2(20, 10)) < 1)
    root.size = Vector2i(1120, 720)
    await process_frame
    await scene._default_layout()
    scene._show_window("mixer")
    assert(scene._windows.mixer.position.y + scene._windows.mixer.size.y <= scene._desktop.size.y + 1)
    assert(scene._windows.rack.position.y + scene._windows.rack.size.y <= scene._desktop.size.y + 1)
    scene.queue_free()
    await process_frame

func _mouse(point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.global_position = point
    event.button_index = button
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
    event.pressed = pressed
    root.push_input(event)

func _motion(point: Vector2, relative: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = point
    event.global_position = point
    event.relative = relative
    event.button_mask = MOUSE_BUTTON_MASK_LEFT
    root.push_input(event)

func _key(code: int, pressed: bool) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.pressed = pressed
    root.push_input(event)

extends Control
## One MIDI clip: native playback/record timestamps, Godot editing and controls.

const Clip = preload("res://addons/juce_bridge/ui/midi_clip.gd")
const Roll = preload("res://addons/juce_bridge/ui/piano_roll.gd")
const Piano = preload("res://addons/juce_bridge/ui/midi_keyboard.gd")
const ACCENT := Color("41d6b0")
const MUTED := Color("a1b0c4")
var model: RefCounted
var player := JuceMidiSequencer.new()
var audio: RefCounted = JuceAudioDeviceManager.new()
var roll: Control
var piano: Control
var _bpm: SpinBox
var _bars: SpinBox
var _velocity: SpinBox
var _outputs: OptionButton
var _record: Button
var _monitor: Button
var _loop: CheckButton
var _metro: CheckButton
var _position: Label
var _status: Label
var _title: Label
var _meter: ProgressBar
var _file: FileDialog
var _confirm: ConfirmationDialog
var _pending: Callable
var _file_action := ""
var _path := ""
var _recording := false
var _was_playing := false
var _audio_started := false
var _old_auto_quit := true

func _ready() -> void:
    if DisplayServer.get_name() != "headless":
        get_window().min_size = Vector2i(1000, 800)
        get_window().size = Vector2i(1280, 900)
    _build_ui()
    _new_document()
    _old_auto_quit = get_tree().auto_accept_quit
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(_close_requested)
    call_deferred("_fit")

func _build_ui() -> void:
    var background := ColorRect.new()
    background.color = Color("101620")
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 20)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 10)
    margin.add_child(column)
    column.add_child(_label("JUCE / MIDI CLIP STUDIO", 12, ACCENT))
    _title = _label("Untitled clip", 25)
    column.add_child(_title)

    var transport := _bar(column)
    transport.add_child(_button("▶ Play", func(): start_transport(false)))
    transport.add_child(_button("■ Stop", stop_transport))
    _record = _button("● Record", func(): pass)
    _record.toggle_mode = true
    _record.toggled.connect(func(enabled: bool):
        if enabled:
            start_transport(true)
        else:
            stop_transport()
    )
    transport.add_child(_record)
    transport.add_child(_label("BPM", 14, ACCENT))
    _bpm = _spin(20, 300, 0.1, 120)
    _bpm.value_changed.connect(func(value: float):
        model.set_bpm(value)
        player.set_bpm(value)
    )
    transport.add_child(_bpm)
    _loop = CheckButton.new()
    _loop.text = "Loop"
    _loop.button_pressed = true
    _loop.focus_mode = Control.FOCUS_NONE
    _loop.toggled.connect(player.set_looping)
    transport.add_child(_loop)
    _metro = CheckButton.new()
    _metro.text = "Metronome"
    _metro.focus_mode = Control.FOCUS_NONE
    _metro.toggled.connect(player.set_metronome)
    transport.add_child(_metro)
    _position = _label("1 : 1.00", 16, Color("ffcb72"))
    transport.add_child(_position)

    var files := _bar(column)
    files.add_child(_button("New", func(): _discard_then(_new_document)))
    files.add_child(_button("Demo phrase", func(): _discard_then(_demo_phrase)))
    files.add_child(_button("Open", func(): _discard_then(func(): _show_file("open"))))
    files.add_child(_button("Save", save_document))
    files.add_child(_button("Save as", func(): _show_file("save")))
    files.add_child(_button("Export MIDI", func(): _show_file("midi")))
    files.add_child(_button("Undo", func(): _edit(func(): model.undo())))
    files.add_child(_button("Redo", func(): _edit(func(): model.redo())))

    var editing := _bar(column)
    editing.add_child(_label("Grid", 14, MUTED))
    var snap := OptionButton.new()
    snap.focus_mode = Control.FOCUS_NONE
    for name in ["1/4", "1/8", "1/16", "1/32", "1/64"]:
        snap.add_item(name)
    snap.selected = 2
    snap.item_selected.connect(func(index: int):
        roll.grid = pow(0.5, index)
        roll.queue_redraw()
    )
    editing.add_child(snap)
    editing.add_child(_button("Quantize", func(): _edit(func(): model.quantize(roll.grid))))
    editing.add_child(_label("Bars", 14, MUTED))
    _bars = _spin(0.25, 64, 0.25, 4)
    _bars.value_changed.connect(func(value: float):
        stop_transport()
        if not model.set_length(value * 4.0):
            _set_status(model.last_error, true)
            _sync_document()
    )
    editing.add_child(_bars)
    editing.add_child(_button("−", func(): roll.zoom(1.0 / 1.25)))
    editing.add_child(_button("+", func(): roll.zoom(1.25)))
    editing.add_child(_button("Fit", _fit))
    editing.add_child(_label("Selected velocity", 14, MUTED))
    _velocity = _spin(1, 127, 1, 100)
    _velocity.editable = false
    _velocity.value_changed.connect(_change_velocity)
    editing.add_child(_velocity)

    roll = Roll.new()
    roll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    roll.edit_requested.connect(stop_transport)
    roll.selection_changed.connect(_select_note)
    column.add_child(roll)
    column.add_child(_label("Click to draw · Drag to move · Drag a note’s right edge to resize · Right-click / Delete to remove", 12, MUTED))

    var monitor := _bar(column)
    _monitor = _button("Monitor keys", _toggle_monitor)
    monitor.add_child(_monitor)
    _outputs = OptionButton.new()
    _outputs.custom_minimum_size.x = 220
    _outputs.focus_mode = Control.FOCUS_NONE
    _outputs.add_item("Default output")
    for name in audio.get_output_devices():
        _outputs.add_item(name)
    _outputs.item_selected.connect(func(_index: int): stop_transport())
    monitor.add_child(_outputs)
    monitor.add_child(_label("Key velocity", 13, MUTED))
    var key_velocity := _spin(1, 127, 1, 100)
    key_velocity.value_changed.connect(func(value: float): piano.velocity = int(value))
    monitor.add_child(key_velocity)
    monitor.add_child(_button("Oct −", func(): piano.base_note -= 12))
    monitor.add_child(_button("Oct +", func(): piano.base_note += 12))
    monitor.add_child(_button("Panic", func():
        piano.all_notes_off()
        player.panic()
    ))
    var volume := HSlider.new()
    volume.custom_minimum_size.x = 100
    volume.min_value = -60
    volume.max_value = 0
    volume.value = -9
    volume.focus_mode = Control.FOCUS_NONE
    volume.tooltip_text = "Instrument volume in dB"
    volume.value_changed.connect(func(value: float): player.set_volume_db(value))
    monitor.add_child(_label("Level", 13, MUTED))
    monitor.add_child(volume)
    piano = Piano.new()
    piano.custom_minimum_size.y = 180
    column.add_child(piano)
    # The piano's _ready() establishes its default min height; use compact demo sizing.
    piano.custom_minimum_size.y = 180
    piano.midi_message.connect(_on_midi)
    column.add_child(_label("Z–M / Q–U play notes · Space sustains · [ / ] shift octaves · Ctrl+S saves · Ctrl+Z undoes", 12, MUTED))
    _meter = ProgressBar.new()
    _meter.max_value = 1.0
    _meter.show_percentage = false
    _meter.custom_minimum_size.y = 5
    column.add_child(_meter)
    _status = _label("Draw notes, load the demo phrase, or press Record and play the typing keys.", 12, MUTED)
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_status)

    _file = FileDialog.new()
    _file.access = FileDialog.ACCESS_FILESYSTEM
    _file.size = Vector2i(800, 560)
    _file.file_selected.connect(_file_selected)
    add_child(_file)
    _confirm = ConfirmationDialog.new()
    _confirm.title = "Unsaved MIDI clip"
    _confirm.dialog_text = "Discard unsaved changes? Save the clip first if you want to keep it."
    _confirm.ok_button_text = "Discard changes"
    _confirm.confirmed.connect(func():
        var action := _pending
        _pending = Callable()
        if action.is_valid():
            action.call()
    )
    add_child(_confirm)

func _bar(parent: Node) -> HFlowContainer:
    var bar := HFlowContainer.new()
    bar.add_theme_constant_override("h_separation", 8)
    parent.add_child(bar)
    return bar

func _label(text: String, font_size: int, color := Color("e9edf3")) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label

func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size.y = 30
    button.pressed.connect(action)
    return button

func _spin(low: float, high: float, step: float, value: float) -> SpinBox:
    var spin := SpinBox.new()
    spin.min_value = low
    spin.max_value = high
    spin.step = step
    spin.value = value
    spin.custom_minimum_size.x = 80
    return spin

func _new_document() -> void:
    stop_transport()
    model = Clip.new()
    model.changed.connect(_sync_document)
    roll.set_document(model)
    _path = ""
    _sync_document()

func _demo_phrase() -> void:
    _new_document()
    var notes: Array = []
    var chords := [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
    for bar in 4:
        for pitch in chords[bar]:
            notes.append({"note": pitch, "start": bar * 4.0, "length": 3.0, "velocity": 0.7})
    for index in 8:
        notes.append({"note": [72, 74, 76, 79, 76, 74, 71, 72][index],
            "start": index * 2.0, "length": 0.75, "velocity": 0.85})
    model.load_document({"type": "juce_midi_clip", "schema_version": 1,
        "bpm": 120.0, "length_beats": 16.0, "notes": notes})
    _fit()

func _sync_document() -> void:
    if model == null:
        return
    _bpm.set_value_no_signal(model.bpm)
    _bars.set_value_no_signal(model.length_beats / 4.0)
    player.set_bpm(model.bpm)
    _title.text = ("Untitled clip" if _path.is_empty() else _path.get_file()) + (" *" if model.is_dirty() else "")
    _select_note(roll.selected)

func _fit() -> void:
    if is_instance_valid(roll):
        roll.fit_clip()

func _prepare_audio() -> bool:
    if not player.load_clip(model.native_notes(), model.length_beats):
        _set_status(player.get_last_error(), true)
        return false
    player.set_bpm(model.bpm)
    player.set_looping(_loop.button_pressed)
    player.set_metronome(_metro.button_pressed)
    if not audio.set_sequencer(player):
        _set_status(audio.get_last_error(), true)
        return false
    var output := "" if _outputs.selected == 0 else _outputs.get_item_text(_outputs.selected)
    if not audio.start_audio(output):
        _set_status(audio.get_last_error(), true)
        return false
    _monitor.text = "Audio enabled"
    _audio_started = true
    return true

func start_transport(recording := false) -> bool:
    stop_transport()
    if not _prepare_audio():
        return false
    _recording = recording
    if recording:
        model.begin_take()
    _record.set_pressed_no_signal(recording)
    _record.text = "● Recording" if recording else "● Record"
    roll.editable = not recording
    _select_note(roll.selected)
    player.set_recording(recording)
    player.play()
    piano.grab_focus()
    _was_playing = true
    _set_status("Recording notes in beats. Stop commits the take." if recording else "Playing the clip on the native audio timeline. Change BPM while it plays.")
    return true

func _drain_recording() -> void:
    for note in player.read_recorded_notes():
        model.add_recorded(note)
        if model.notes.size() >= 4096:
            _set_status("Clip reached its 4096-note limit. Stop and save your take.", true)

func stop_transport() -> void:
    # Detaching callbacks finalizes held recorded notes before the take is committed.
    audio.stop_audio()
    if model != null:
        _drain_recording()
        if _recording:
            model.end_take()
    _recording = false
    _was_playing = false
    _audio_started = false
    if is_instance_valid(piano):
        piano.all_notes_off()
    if is_instance_valid(_record):
        _record.set_pressed_no_signal(false)
        _record.text = "● Record"
        _monitor.text = "Monitor keys"
        roll.editable = true
        roll.set_playhead(-1)
        _position.text = "1 : 1.00"
        if model != null:
            _select_note(roll.selected)

func _toggle_monitor() -> void:
    if audio.is_running():
        stop_transport()
        _set_status("Stopped.")
    elif _prepare_audio():
        piano.grab_focus()
        _set_status("Monitoring typing and mouse notes. Press Record to capture a take.")

func _on_midi(message: JuceMidiMessage) -> void:
    if audio.is_running():
        if not player.queue_midi(message):
            _set_status(player.get_last_error(), true)
    elif message.is_note_on():
        _set_status("Press Monitor keys to audition, or Record to capture your playing.")

func _select_note(id: int) -> void:
    var note: Dictionary = model.find_note(id) if model != null else {}
    _velocity.editable = not note.is_empty() and not _recording
    if not note.is_empty():
        _velocity.set_value_no_signal(roundf(note.velocity * 127.0))

func _change_velocity(value: float) -> void:
    var note: Dictionary = model.find_note(roll.selected)
    if note.is_empty():
        return
    stop_transport()
    model.update_note(note.id, note.note, note.start, note.length, value / 127.0)

func _edit(action: Callable) -> void:
    stop_transport()
    action.call()

func _discard_then(action: Callable) -> void:
    stop_transport()
    if model != null and model.is_dirty():
        _pending = action
        _confirm.popup_centered()
    else:
        action.call()

func save_document() -> void:
    stop_transport()
    if _path.is_empty():
        _show_file("save")
    elif model.save_file(_path, true):
        _set_status("Saved " + _path)
    else:
        _set_status(model.last_error, true)

func _show_file(action: String) -> void:
    stop_transport()
    _file_action = action
    _file.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action == "open" else FileDialog.FILE_MODE_SAVE_FILE
    _file.filters = PackedStringArray(["*.mid ; Standard MIDI file"]) if action == "midi" else PackedStringArray(["*.midiclip.json ; JUCE MIDI clip"])
    _file.current_file = "my_clip.mid" if action == "midi" else "my_clip.midiclip.json"
    _file.title = "Open clip" if action == "open" else ("Export MIDI" if action == "midi" else "Save clip")
    _file.popup_centered()

func _file_selected(path: String) -> void:
    if _file_action == "open":
        if model.load_file(path):
            _path = path
            _sync_document()
            _fit()
            _set_status("Opened " + path)
        else:
            _set_status(model.last_error, true)
    elif _file_action == "save":
        if model.save_file(path, true):
            _path = path
            _sync_document()
            _set_status("Saved " + path)
        else:
            _set_status(model.last_error, true)
    elif not model.export_midi(path, true):
        _set_status(model.last_error, true)
    else:
        _set_status("Exported " + path)

func _close_requested() -> void:
    _discard_then(func(): get_tree().quit())

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo or _file.visible or _confirm.visible:
        return
    if event.ctrl_pressed or event.meta_pressed:
        if event.keycode == KEY_S:
            save_document()
        elif event.keycode == KEY_Z:
            _edit(func(): model.redo() if event.shift_pressed else model.undo())
        elif event.keycode == KEY_Y:
            _edit(func(): model.redo())
        else:
            return
        get_viewport().set_input_as_handled()

func _set_status(text: String, error := false) -> void:
    if is_instance_valid(_status):
        _status.text = text
        _status.add_theme_color_override("font_color", Color("ff9b91") if error else MUTED)

func _process(_delta: float) -> void:
    if model == null:
        return
    if _audio_started and not audio.is_running():
        stop_transport()
        _set_status("Audio device stopped. Check the output and start again.", true)
        return
    _drain_recording()
    var state := player.get_transport()
    if state.playing:
        roll.set_playhead(state.beat)
        _position.text = "%d : %.2f" % [floori(state.beat / 4.0) + 1, fposmod(state.beat, 4.0) + 1]
    elif _was_playing:
        stop_transport()
        _set_status("Clip finished.")
    if state.input_drops > 0 or state.recording_drops > 0:
        _set_status("MIDI queue overflow: input %d, recorded notes %d. Stop and review the take." % [state.input_drops, state.recording_drops], true)
    _meter.value = audio.get_peak()

func _exit_tree() -> void:
    audio.stop_audio()
    if is_instance_valid(piano):
        piano.all_notes_off()
    if get_tree() != null:
        get_tree().auto_accept_quit = _old_auto_quit

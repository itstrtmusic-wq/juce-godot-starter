extends Control
## Open typing_keyboard.tscn and press F6. Start preview to hear the native synth.

const Keyboard = preload("res://addons/juce_bridge/ui/midi_keyboard.gd")
const PreviewSynth = preload("res://examples/keyboard_synth.gd")
const BG := Color("101620")
const TEXT := Color("e9edf3")
const MUTED := Color("9baac0")
const ACCENT := Color("41d6b0")

var keyboard: Control
var synth: RefCounted
var _status: Label
var _notes: Label
var _octave: Label
var _play: Button
var _outputs: OptionButton
var _meter: ProgressBar
var _sustain: Button
var _waveform: OptionButton
var _volume: HSlider

func _ready() -> void:
    synth = PreviewSynth.new()
    var built: bool = synth.build_network()
    _build_ui()
    if not built:
        _set_status(synth.last_error, true)

func _build_ui() -> void:
    var background := ColorRect.new()
    background.color = BG
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 24)
    add_child(margin)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 16)
    margin.add_child(column)
    column.add_child(_label("JUCE / GDSCRIPT INSTRUMENTS", 12, ACCENT))
    column.add_child(_label("Your keyboard. Your instrument.", 28))
    column.add_child(_label("Click the piano or play the physical QWERTY keys. Chords work too.", 14, MUTED))

    var audio_bar := HFlowContainer.new()
    audio_bar.add_theme_constant_override("h_separation", 12)
    column.add_child(audio_bar)
    _play = _button("▶  Start preview", _toggle_preview)
    audio_bar.add_child(_play)
    _outputs = OptionButton.new()
    _outputs.custom_minimum_size.x = 240
    _outputs.focus_mode = Control.FOCUS_NONE
    _outputs.add_item("Default output")
    for name in synth.audio.get_output_devices():
        _outputs.add_item(name)
    _outputs.item_selected.connect(func(_index: int):
        keyboard.all_notes_off()
        synth.stop()
        _play.text = "▶  Start preview"
        _set_status("Output changed. Start preview when ready.")
    )
    audio_bar.add_child(_outputs)
    audio_bar.add_child(_button("Panic / Esc", func(): keyboard.all_notes_off()))

    var controls := HFlowContainer.new()
    controls.add_theme_constant_override("h_separation", 12)
    column.add_child(controls)
    controls.add_child(_label("Octave", 14, MUTED))
    controls.add_child(_button("−", func(): keyboard.base_note -= 12))
    _octave = _label("C4", 18, ACCENT)
    controls.add_child(_octave)
    controls.add_child(_button("+", func(): keyboard.base_note += 12))
    _sustain = _button("Sustain / Space", func(): pass)
    _sustain.toggle_mode = true
    _sustain.toggled.connect(func(enabled: bool): keyboard.set_sustain(enabled))
    controls.add_child(_sustain)
    var typing := _button("Typing enabled", func(): pass)
    typing.toggle_mode = true
    typing.button_pressed = true
    typing.toggled.connect(func(enabled: bool):
        keyboard.typing_enabled = enabled
        typing.text = "Typing enabled" if enabled else "Typing disabled"
    )
    controls.add_child(typing)

    var settings := HFlowContainer.new()
    settings.add_theme_constant_override("h_separation", 12)
    column.add_child(settings)
    settings.add_child(_label("Velocity", 14, MUTED))
    var strength := SpinBox.new()
    strength.min_value = 1
    strength.max_value = 127
    strength.value = 100
    strength.value_changed.connect(func(value: float): keyboard.velocity = int(value))
    settings.add_child(strength)
    settings.add_child(_label("Wave", 14, MUTED))
    _waveform = OptionButton.new()
    _waveform.focus_mode = Control.FOCUS_NONE
    for name in ["Sine", "Triangle", "Saw", "Square"]:
        _waveform.add_item(name)
    _waveform.selected = 1
    _waveform.item_selected.connect(func(value: int): synth.set_waveform(value))
    settings.add_child(_waveform)
    settings.add_child(_label("Preview volume", 14, MUTED))
    _volume = HSlider.new()
    _volume.custom_minimum_size.x = 140
    _volume.focus_mode = Control.FOCUS_NONE
    _volume.min_value = -40
    _volume.max_value = 0
    _volume.value = -9
    _volume.value_changed.connect(func(value: float): synth.set_volume(value))
    settings.add_child(_volume)

    _notes = _label("Ready for your first note", 16, ACCENT)
    column.add_child(_notes)
    keyboard = Keyboard.new()
    keyboard.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(keyboard)
    keyboard.midi_message.connect(_on_midi_message)
    keyboard.note_on.connect(func(_note: int, _velocity: float): _update_notes())
    keyboard.note_off.connect(func(_note: int): _update_notes())
    keyboard.octave_changed.connect(func(_value: int): _octave.text = Keyboard.note_name(keyboard.base_note))
    keyboard.sustain_changed.connect(func(enabled: bool): _sustain.set_pressed_no_signal(enabled))
    var hint := _label("Z S X D C V G B H N J M  →  lower octave\nQ 2 W 3 E R 5 T 6 Y 7 U  →  upper octave\n[ / ] shift octaves  ·  Space holds sustain  ·  Esc releases everything", 14, MUTED)
    column.add_child(hint)
    _meter = ProgressBar.new()
    _meter.max_value = 1.0
    _meter.show_percentage = false
    _meter.custom_minimum_size.y = 6
    column.add_child(_meter)
    _status = _label("MIDI controller ready. Start preview to hear the 16-voice JUCE synth.", 13, MUTED)
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    column.add_child(_status)

func _label(text: String, font_size: int, color := TEXT) -> Label:
    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label

func _button(text: String, action: Callable) -> Button:
    var button := Button.new()
    button.text = text
    button.focus_mode = Control.FOCUS_NONE
    button.custom_minimum_size.y = 34
    button.pressed.connect(action)
    return button

func _toggle_preview() -> void:
    keyboard.all_notes_off()
    if synth.audio.is_running():
        synth.stop()
        _play.text = "▶  Start preview"
        _set_status("Preview stopped. MIDI signals remain available.")
        return
    var output := "" if _outputs.selected == 0 else _outputs.get_item_text(_outputs.selected)
    if not synth.start(output):
        _set_status(synth.last_error, true)
        return
    synth.set_waveform(_waveform.selected)
    synth.set_volume(_volume.value)
    _play.text = "■  Stop preview"
    _set_status("Playing through " + str(synth.audio.get_device_info().get("name", "JUCE output")))

func _on_midi_message(message: JuceMidiMessage) -> void:
    # Connect this same signal to your own instrument/recorder instead of the preview.
    if synth.audio.is_running() and not synth.handle_midi(message):
        _set_status(synth.last_error, true)

func _update_notes() -> void:
    if not is_instance_valid(_notes):
        return
    var names: Array[String] = []
    for note in keyboard.get_active_notes():
        names.append(Keyboard.note_name(note))
    _notes.text = " + ".join(names) if not names.is_empty() else "Ready for your next note"

func _set_status(text: String, error := false) -> void:
    _status.text = text
    _status.add_theme_color_override("font_color", Color("ff9b91") if error else MUTED)

func _process(_delta: float) -> void:
    if _meter != null:
        _meter.value = synth.audio.get_peak()

func _exit_tree() -> void:
    if is_instance_valid(keyboard):
        keyboard.all_notes_off()
    if synth != null:
        synth.stop()

extends Control
## A pattern-based DAW workspace. The native sequencer owns audio time.

const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
const Project = preload("res://addons/juce_bridge/ui/daw_project.gd")
const EditorWindow = preload("res://addons/juce_bridge/ui/daw_window.gd")
const PatternView = preload("res://addons/juce_bridge/ui/daw_pattern_view.gd")
const Playlist = preload("res://addons/juce_bridge/ui/daw_playlist.gd")
const Rack = preload("res://addons/juce_bridge/ui/daw_rack.gd")
const Mixer = preload("res://addons/juce_bridge/ui/daw_mixer.gd")
const Browser = preload("res://addons/juce_bridge/ui/daw_browser.gd")
const Roll = preload("res://addons/juce_bridge/ui/piano_roll.gd")
const Piano = preload("res://addons/juce_bridge/ui/midi_keyboard.gd")
const Knob = preload("res://addons/juce_bridge/ui/daw_knob.gd")
const Clip = preload("res://addons/juce_bridge/ui/midi_clip.gd")
const FX_TYPES := Project.EFFECT_TYPES
const WAVE_NAMES := ["Sine", "Triangle", "Saw", "Square", "Kick", "Snare", "Closed hat", "Clap"]

@export var start_with_demo := true
var project: RefCounted = Project.new()
var player := JuceMidiSequencer.new()
var audio: RefCounted = JuceAudioDeviceManager.new()
var post: JuceDSPNetwork
var selected_pattern := 0
var selected_channel := 0
var song_mode := true
var playlist: Control
var rack: Control
var mixer: Control
var roll: Control
var piano: Control
var view: RefCounted
var _desktop: Control
var _windows: Dictionary = {}
var _view_buttons: Dictionary = {}
var _browser_panel: PanelContainer
var _browser: Tree
var _search: LineEdit
var _title: Label
var _status: Label
var _clock: Button
var _tempo: SpinBox
var _pattern: OptionButton
var _pattern_mode: Button
var _song_mode: Button
var _play: Button
var _record: Button
var _loop: Button
var _metro: Button
var _typing: Button
var _velocity: SpinBox
var _pattern_length: SpinBox
var _fx_rows: Array[Dictionary] = []
var _fx_parameters: VBoxContainer
var _fx_title: Label
var _fx_widgets: Dictionary = {}
var _selected_fx := 7
var _fx_signature := ""
var _browser_signature := ""
var _mix_signature := ""
var _file: FileDialog
var _file_action := ""
var _path := ""
var _confirm: ConfirmationDialog
var _pending: Callable
var _settings: AcceptDialog
var _output: OptionButton
var _rate: OptionButton
var _buffer: OptionButton
var _instrument: AcceptDialog
var _channel_name: LineEdit
var _channel_wave: OptionButton
var _channel_note: SpinBox
var _recording := false
var _audio_started := false
var _was_playing := false
var _show_seconds := false
var _actual_rate := 48000.0
var _old_auto_quit := true
var _rename: AcceptDialog
var _rename_text: LineEdit
var _master_knob: Control
var _fitted: Dictionary = {}

func _ready() -> void:
    theme = Look.create()
    focus_mode = Control.FOCUS_ALL
    if DisplayServer.get_name() != "headless":
        var usable := DisplayServer.screen_get_usable_rect().size
        get_window().min_size = Vector2i(1040, 640)
        get_window().size = Vector2i(mini(1680, usable.x - 24), mini(980, usable.y - 48)).max(get_window().min_size)
    if start_with_demo:
        project.demo()
    _build_ui()
    project.changed.connect(_refresh)
    _refresh()
    _old_auto_quit = get_tree().auto_accept_quit
    get_tree().auto_accept_quit = false
    get_window().close_requested.connect(func(): _guard(func(): get_tree().quit()))
    call_deferred("_default_layout")

func _build_ui() -> void:
    var background := ColorRect.new()
    background.color = Look.BG
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var column := VBoxContainer.new()
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    column.add_theme_constant_override("separation", 3)
    add_child(column)
    _build_transport(column)
    _build_tools(column)
    var workspace := HBoxContainer.new()
    workspace.add_theme_constant_override("separation", 5)
    workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(workspace)
    _build_browser(workspace)
    _desktop = Control.new()
    _desktop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _desktop.clip_contents = true
    workspace.add_child(_desktop)
    _build_editors()
    var footer := PanelContainer.new()
    footer.custom_minimum_size.y = 23
    column.add_child(footer)
    _status = Look.label("Ready · Space plays / stops · F5 Playlist · F6 Channel rack · F7 Piano roll · F9 Mixer", 11, Look.MUTED)
    _status.clip_text = true
    footer.add_child(_status)
    _build_dialogs()

func _build_transport(parent: Node) -> void:
    var panel := PanelContainer.new()
    parent.add_child(panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 2)
    panel.add_child(column)
    var menus := HBoxContainer.new()
    column.add_child(menus)
    menus.add_child(Look.label("  JUCE STUDIO  ", 13, Look.ORANGE))
    _menu(menus, "FILE", ["New project", "Open project", "Save", "Save as", "Import MIDI clip", "Export MIDI", "Demo project"], [
        func(): _guard(_new_project), func(): _guard(func(): _choose_file("open")), save_project,
        func(): _choose_file("save"), func(): _choose_file("import"), func(): _choose_file("midi"), func(): _guard(_demo_project)])
    _menu(menus, "EDIT", ["Undo", "Redo", "Panic / release notes"], [func(): _edit(func(): project.undo()), func(): _edit(func(): project.redo()), _panic])
    _menu(menus, "ADD", ["Synth", "Kick", "Snare", "Closed hat", "Clap"], [func(): _add_channel(1), func(): _add_channel(4), func(): _add_channel(5), func(): _add_channel(6), func(): _add_channel(7)])
    _menu(menus, "PATTERNS", ["New pattern", "Duplicate pattern", "Rename pattern", "Quantize current channel"], [_new_pattern, _duplicate_pattern, _rename_pattern, _quantize])
    _menu(menus, "VIEW", ["Playlist  F5", "Channel rack  F6", "Piano roll  F7", "Browser  Alt+F8", "Mixer  F9", "Typing piano", "Reset layout"], [
        func(): _toggle_window("playlist"), func(): _toggle_window("rack"), func(): _toggle_window("piano"), _toggle_browser,
        func(): _toggle_window("mixer"), func(): _toggle_window("keyboard"), _default_layout])
    _menu(menus, "OPTIONS", ["Audio settings", "Instrument settings", "Save workspace layout", "Restore workspace layout"], [_show_settings, _show_instrument, _save_layout, _restore_layout])
    _menu(menus, "TOOLS", ["Fill each step", "Fill each 2 steps", "Fill each 4 steps", "Clear first bar", "Fit playlist", "Fit piano roll"], [
        func(): _fill(1), func(): _fill(2), func(): _fill(4), func(): _fill(0), func(): playlist.fit_song(), func(): roll.fit_clip()])
    var stretch := Control.new()
    stretch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    menus.add_child(stretch)
    _title = Look.label("Night Drive", 12, Look.MUTED)
    _title.clip_text = true
    _title.custom_minimum_size.x = 160
    menus.add_child(_title)
    var bar := HBoxContainer.new()
    bar.add_theme_constant_override("separation", 5)
    column.add_child(bar)
    _pattern_mode = _toggle(bar, "PAT", func(): _set_mode(false), "Play the selected pattern")
    _song_mode = _toggle(bar, "SONG", func(): _set_mode(true), "Play the playlist arrangement")
    _play = _toggle(bar, "▶", _play_action, "Play / stop · Space")
    bar.add_child(Look.button("■", stop_transport, "Stop and rewind"))
    _record = _toggle(bar, "●", func():
        if _recording:
            stop_transport()
        else:
            start_transport(true)
    , "Record typing keys into the selected pattern · Ctrl+R" )
    _record.add_theme_color_override("font_color", Color("dd8276"))
    bar.add_child(Look.label("TEMPO", 9, Look.MUTED))
    _tempo = _spin(20, 300, 0.1, project.bpm)
    _tempo.custom_minimum_size.x = 86
    _tempo.value_changed.connect(func(value: float): project.set_bpm(value))
    bar.add_child(_tempo)
    _clock = Look.button("001:01:000", func(): _show_seconds = not _show_seconds, "Switch between bars and elapsed time")
    _clock.custom_minimum_size.x = 142
    _clock.add_theme_font_size_override("font_size", 21)
    _clock.add_theme_color_override("font_color", Color("d0e2c2"))
    _clock.add_theme_stylebox_override("normal", Look.box(Color("26332e")))
    bar.add_child(_clock)
    _metro = _toggle(bar, "MET", func(): player.set_metronome(_metro.button_pressed), "Metronome")
    _loop = _toggle(bar, "LOOP", func(): player.set_looping(_loop.button_pressed), "Loop playback")
    _loop.set_pressed_no_signal(true)
    _typing = _toggle(bar, "⌨", func(): piano.typing_enabled = _typing.button_pressed, "Typing keyboard to piano · Ctrl+T")
    _typing.set_pressed_no_signal(true)
    bar.add_child(Look.button("AUDIO", _show_settings, "Choose output device, sample rate and buffer"))
    var master = Knob.new()
    _master_knob = master
    master.minimum = -60
    master.maximum = 0
    master.default_value = -9
    master.suffix = " dB master"
    master.set_value_no_signal(project.master_db)
    master.drag_started.connect(project.begin_edit)
    master.drag_finished.connect(project.end_edit)
    master.value_changed.connect(func(value: float):
        project.master_db = value
        project.remember()
    )
    bar.add_child(master)
    bar.add_child(Look.label("MASTER", 9, Look.MUTED))

func _build_tools(parent: Node) -> void:
    var panel := PanelContainer.new()
    parent.add_child(panel)
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 5)
    panel.add_child(row)
    row.add_child(Look.button("BROWSER", _toggle_browser))
    row.add_child(Look.button("+", _new_pattern, "New pattern · F4"))
    _pattern = OptionButton.new()
    _pattern.custom_minimum_size.x = 180
    _pattern.clip_text = true
    _pattern.focus_mode = Control.FOCUS_NONE
    _pattern.item_selected.connect(select_pattern)
    row.add_child(_pattern)
    row.add_child(Look.button("▸", _duplicate_pattern, "Duplicate pattern"))
    row.add_child(Look.button("Rename", _rename_pattern))
    var snap := OptionButton.new()
    for name in ["Bar", "Beat", "1/2 beat", "1/4 beat"]:
        snap.add_item(name)
    snap.selected = 1
    snap.focus_mode = Control.FOCUS_NONE
    snap.item_selected.connect(func(index: int):
        playlist.grid = [4.0, 1.0, 0.5, 0.25][index]
    )
    row.add_child(snap)
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(spacer)
    for item in [["playlist", "▤ PLAYLIST", "F5"], ["rack", "▦ RACK", "F6"], ["piano", "♮ PIANO", "F7"], ["mixer", "▥ MIXER", "F9"]]:
        var key: String = item[0]
        _view_buttons[key] = _toggle(row, item[1], func(): _toggle_window(key), item[2])

func _menu(parent: Node, text: String, items: Array, actions: Array) -> void:
    var menu := MenuButton.new()
    menu.text = text
    menu.flat = true
    menu.focus_mode = Control.FOCUS_NONE
    menu.add_theme_font_size_override("font_size", 10)
    parent.add_child(menu)
    for item in items:
        menu.get_popup().add_item(item)
    menu.get_popup().id_pressed.connect(func(index: int): actions[index].call())

func _toggle(parent: Node, text: String, action: Callable, tip := "") -> Button:
    var button := Look.button(text, action, tip)
    button.toggle_mode = true
    parent.add_child(button)
    return button

func _spin(low: float, high: float, step: float, value: float) -> SpinBox:
    var spin := SpinBox.new()
    spin.min_value = low
    spin.max_value = high
    spin.step = step
    spin.value = value
    spin.custom_minimum_size.x = 72
    return spin

func _build_browser(parent: Node) -> void:
    _browser_panel = PanelContainer.new()
    _browser_panel.custom_minimum_size.x = 212
    parent.add_child(_browser_panel)
    var column := VBoxContainer.new()
    _browser_panel.add_child(column)
    column.add_child(Look.label("BROWSER  ·  All", 12, Look.TEXT))
    _search = LineEdit.new()
    _search.placeholder_text = "Search patterns, sounds, effects"
    _search.text_changed.connect(func(_text: String): _rebuild_browser())
    column.add_child(_search)
    _browser = Browser.new()
    _browser.hide_root = true
    _browser.focus_mode = Control.FOCUS_NONE
    _browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _browser.item_selected.connect(_browser_selected)
    _browser.item_activated.connect(_browser_activated)
    column.add_child(_browser)
    column.add_child(Look.button("Open project / import clip", func(): _guard(func(): _choose_file("open"))))

func _window(key: String, caption: String, minimum: Vector2) -> Control:
    var window = EditorWindow.new()
    window.caption = caption
    _desktop.add_child(window)
    window.custom_minimum_size = minimum
    window.open_changed.connect(func(open: bool):
        if _view_buttons.has(key):
            _view_buttons[key].set_pressed_no_signal(open)
    )
    _windows[key] = window
    return window

func _build_editors() -> void:
    var window := _window("playlist", "Playlist — Arrangement", Vector2(640, 300))
    var tools := HBoxContainer.new()
    window.body.add_child(tools)
    tools.add_child(Look.label("Arrangement", 11, Look.MUTED))
    tools.add_child(Look.button("Fit", func(): playlist.fit_song()))
    tools.add_child(Look.label("SONG BARS", 9, Look.MUTED))
    var bars := _spin(1, 64, 1, project.song_length / 4)
    bars.value_changed.connect(func(value: float):
        stop_transport()
        var length := value * 4
        for clip in project.placements:
            if clip.start + clip.length > length:
                bars.set_value_no_signal(project.song_length / 4)
                _set_status("Move or remove clips beyond the new song length first.", true)
                return
        project.song_length = length
        project.remember()
    )
    tools.add_child(bars)
    tools.add_child(Look.label("Paint current pattern · Drag clips · Right-click deletes", 10, Look.MUTED))
    playlist = Playlist.new()
    playlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(playlist)
    playlist.setup(project)
    playlist.edit_requested.connect(stop_transport)
    playlist.pattern_opened.connect(func(index: int):
        select_pattern(index)
        _show_window("piano")
    )
    playlist.track_mute_requested.connect(func(index: int):
        _edit(func():
            project.tracks[index].mute = not project.tracks[index].mute
            project.remember()
        )
    )
    window = _window("rack", "Channel rack", Vector2(700, 240))
    rack = Rack.new()
    rack.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(rack)
    rack.setup(project)
    rack.channel_selected.connect(select_channel)
    rack.channel_changed.connect(_channel_changed)
    rack.step_changed.connect(func(channel: int, step: int): _edit(func(): project.toggle_step(selected_pattern, channel, step)))
    rack.context_action.connect(_rack_context)
    rack.edit_started.connect(project.begin_edit)
    rack.edit_finished.connect(project.end_edit)
    window = _window("piano", "Piano roll", Vector2(720, 370))
    var bar := HBoxContainer.new()
    window.body.add_child(bar)
    bar.add_child(Look.label("SNAP", 9, Look.MUTED))
    var snap := OptionButton.new()
    for name in ["1/4", "1/8", "1/16", "1/32", "1/64"]:
        snap.add_item(name)
    snap.selected = 2
    snap.focus_mode = Control.FOCUS_NONE
    snap.item_selected.connect(func(index: int):
        roll.grid = pow(0.5, index)
        roll.queue_redraw()
    )
    bar.add_child(snap)
    bar.add_child(Look.button("Quantize", _quantize))
    bar.add_child(Look.button("Fit", func(): roll.fit_clip()))
    bar.add_child(Look.label("BARS", 9, Look.MUTED))
    _pattern_length = _spin(0.25, 64, 0.25, 1)
    _pattern_length.value_changed.connect(func(value: float):
        stop_transport()
        if not project.patterns[selected_pattern].set_length(value * 4):
            _set_status(project.patterns[selected_pattern].last_error, true)
            _refresh()
    )
    bar.add_child(_pattern_length)
    bar.add_child(Look.label("VELOCITY", 9, Look.MUTED))
    _velocity = _spin(1, 127, 1, 100)
    _velocity.value_changed.connect(_note_velocity)
    bar.add_child(_velocity)
    roll = Roll.new()
    roll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(roll)
    view = PatternView.new()
    view.setup(project)
    roll.set_document(view)
    roll.edit_requested.connect(stop_transport)
    roll.selection_changed.connect(_note_selected)
    window = _window("mixer", "Mixer", Vector2(620, 320))
    var mixer_body := HBoxContainer.new()
    mixer_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(mixer_body)
    mixer = Mixer.new()
    mixer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mixer_body.add_child(mixer)
    mixer.setup(project)
    mixer.channel_selected.connect(func(index: int):
        if index >= 0:
            select_channel(index, false)
    )
    mixer.channel_changed.connect(_channel_changed)
    mixer.master_changed.connect(func(value: float):
        project.master_db = value
        project.remember()
    )
    mixer.edit_started.connect(project.begin_edit)
    mixer.edit_finished.connect(project.end_edit)
    _build_fx_slots(mixer_body)
    window = _window("effects", "Master effect controls", Vector2(420, 300))
    _fx_title = Look.label("Effect", 13, Look.ORANGE)
    window.body.add_child(_fx_title)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(scroll)
    _fx_parameters = VBoxContainer.new()
    _fx_parameters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_fx_parameters)
    window = _window("keyboard", "Typing piano — Space plays / stops", Vector2(680, 210))
    var keys_bar := HBoxContainer.new()
    window.body.add_child(keys_bar)
    keys_bar.add_child(Look.button("Oct −", func(): piano.base_note -= 12))
    keys_bar.add_child(Look.button("Oct +", func(): piano.base_note += 12))
    var sustain := _toggle(keys_bar, "Sustain", func(): piano.set_sustain(not piano.is_sustain_down()))
    keys_bar.add_child(Look.button("Monitor", _monitor_keys))
    keys_bar.add_child(Look.button("Panic", _panic))
    piano = Piano.new()
    piano.capture_when_hidden = true
    piano.space_sustain = false
    piano.size_flags_vertical = Control.SIZE_EXPAND_FILL
    window.body.add_child(piano)
    piano.custom_minimum_size.y = 130
    piano.sustain_changed.connect(func(enabled: bool): sustain.set_pressed_no_signal(enabled))
    piano.midi_message.connect(_midi)

func _build_fx_slots(parent: Node) -> void:
    var column := VBoxContainer.new()
    column.custom_minimum_size.x = 195
    parent.add_child(column)
    column.add_child(Look.label("MASTER EFFECTS", 10, Look.MUTED))
    for slot in 8:
        var row := HBoxContainer.new()
        row.add_theme_constant_override("separation", 2)
        column.add_child(row)
        var power := Look.button("●", func():
            var data: Dictionary = project.effects[slot]
            if not data.type.is_empty():
                _effect_parameter(slot, "bypass", 0.0 if data.parameters.get("bypass", 0.0) >= 0.5 else 1.0)
        , "Bypass effect")
        row.add_child(power)
        var type := OptionButton.new()
        type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        type.custom_minimum_size.x = 128
        type.focus_mode = Control.FOCUS_NONE
        for name in FX_TYPES:
            type.add_item("Slot %d" % (slot + 1) if name.is_empty() else name.replace("_", " ").capitalize())
        type.item_selected.connect(func(index: int):
            _edit(func():
                project.effects[slot] = {"type": FX_TYPES[index], "parameters": {}}
                project.remember()
            )
            _selected_fx = slot
            _rebuild_effect_parameters()
        )
        row.add_child(type)
        row.add_child(Look.button("›", func():
            _selected_fx = slot
            _rebuild_effect_parameters()
            _show_window("effects")
        , "Open effect controls"))
        _fx_rows.append({"power": power, "type": type})

func _refresh() -> void:
    if _title == null:
        return
    selected_pattern = clampi(selected_pattern, 0, project.patterns.size() - 1)
    selected_channel = clampi(selected_channel, 0, project.channels.size() - 1)
    _title.text = project.title + (" *" if project.is_dirty() else "")
    get_window().title = project.title + " — JUCE Studio"
    _tempo.set_value_no_signal(project.bpm)
    _master_knob.set_value_no_signal(project.master_db)
    player.set_bpm(project.bpm)
    _pattern.clear()
    for i in project.names.size():
        _pattern.add_item("%02d  %s" % [i + 1, project.names[i]])
    _pattern.selected = selected_pattern
    _pattern_length.set_value_no_signal(project.patterns[selected_pattern].length_beats / 4)
    playlist.selected_pattern = selected_pattern
    playlist.queue_redraw()
    rack.pattern_index = selected_pattern
    rack.selected = selected_channel
    rack.refresh()
    mixer.refresh()
    _pattern_mode.set_pressed_no_signal(not song_mode)
    _song_mode.set_pressed_no_signal(song_mode)
    _windows.piano.set_caption("Piano roll — %s · %s" % [project.channels[selected_channel].name, project.names[selected_pattern]])
    _windows.rack.set_caption("Channel rack — " + project.names[selected_pattern])
    if view.pattern_index != selected_pattern or view.channel_index != selected_channel:
        roll.selected = -1
        view.select(selected_pattern, selected_channel)
    var signature := JSON.stringify([project.names, project.channels.map(func(channel: Dictionary): return channel.name)])
    if signature != _browser_signature:
        _browser_signature = signature
        _rebuild_browser()
    for i in 8:
        var effect: Dictionary = project.effects[i]
        _fx_rows[i].type.selected = maxi(0, FX_TYPES.find(effect.type))
        _fx_rows[i].power.add_theme_color_override("font_color", Look.MUTED if effect.type.is_empty() or effect.parameters.get("bypass", 0.0) >= 0.5 else Look.GREEN)
    var fx_signature := JSON.stringify([project.effects.map(func(effect: Dictionary): return effect.type), _selected_fx])
    if fx_signature != _fx_signature:
        _fx_signature = fx_signature
        _rebuild_effect_parameters()
    _apply_mix()
    _note_selected(roll.selected)

func _apply_mix() -> void:
    var signature := JSON.stringify([project.channels, project.master_db])
    if signature == _mix_signature:
        return
    _mix_signature = signature
    player.set_volume_db(project.master_db)
    for index in 16:
        var settings: Dictionary = project.channel_settings(index) if index < project.channels.size() else {
            "volume_db": 0.0, "pan": 0.0, "waveform": -1, "mute": true, "solo": false}
        player.set_channel_settings(index + 1, settings)

func _channel_changed(index: int, key: String, value: Variant) -> void:
    if not project.set_channel(index, key, value):
        _set_status(project.last_error, true)

func select_channel(index: int, open_piano := false) -> void:
    grab_focus()
    selected_channel = clampi(index, 0, project.channels.size() - 1)
    piano.midi_channel = selected_channel + 1
    piano.base_note = 36 if project.channels[selected_channel].waveform >= 4 else 60
    roll.selected = -1
    view.select(selected_pattern, selected_channel)
    rack.selected = selected_channel
    mixer.selected = selected_channel
    _refresh()
    if open_piano:
        _show_window("piano")
        roll.fit_clip()

func select_pattern(index: int) -> void:
    if _recording:
        _set_status("Stop the take before selecting another pattern.")
        return
    grab_focus()
    if not song_mode and _was_playing:
        stop_transport()
    selected_pattern = clampi(index, 0, project.patterns.size() - 1)
    roll.selected = -1
    view.select(selected_pattern, selected_channel)
    _refresh()

func _set_mode(song: bool) -> void:
    grab_focus()
    if song != song_mode:
        stop_transport()
        song_mode = song
    _refresh()

func _play_action() -> void:
    if _was_playing:
        stop_transport()
    else:
        start_transport(false)

func _prepare_audio() -> bool:
    var notes: Array = project.compile_song() if song_mode else project.patterns[selected_pattern].native_notes()
    if song_mode and not project.last_error.is_empty():
        _set_status(project.last_error, true)
        return false
    var length: float = project.song_length if song_mode else project.patterns[selected_pattern].length_beats
    if not player.load_clip(notes, length):
        _set_status(player.get_last_error(), true)
        return false
    post = project.build_effects()
    if post == null:
        _set_status(project.last_error, true)
        return false
    player.set_bpm(project.bpm)
    player.set_looping(_loop.button_pressed)
    player.set_metronome(_metro.button_pressed)
    _mix_signature = ""
    _apply_mix()
    if not audio.set_sequencer(player) or not audio.set_post_network(post):
        _set_status(audio.get_last_error(), true)
        return false
    var output := "" if _output.selected == 0 else _output.get_item_text(_output.selected)
    if not audio.start_audio(output, _rate.get_selected_id(), _buffer.get_selected_id()):
        _set_status(audio.get_last_error(), true)
        return false
    _actual_rate = float(audio.get_device_info().get("sample_rate", 48000))
    _audio_started = true
    return true

func start_transport(recording := false) -> bool:
    _tempo.apply()
    grab_focus() # Commit numeric text edits before preparing the transport.
    stop_transport()
    if recording:
        song_mode = false
        _refresh()
    if not _prepare_audio():
        _play.set_pressed_no_signal(false)
        _record.set_pressed_no_signal(false)
        return false
    _recording = recording
    if recording:
        project.begin_edit()
        project.patterns[selected_pattern].begin_take()
    player.set_recording(recording)
    if not player.play():
        _set_status(player.get_last_error(), true)
        stop_transport()
        return false
    _was_playing = true
    _play.set_pressed_no_signal(true)
    _record.set_pressed_no_signal(recording)
    _pattern.disabled = recording
    roll.editable = not recording
    if piano.is_visible_in_tree():
        piano.grab_focus()
    else:
        grab_focus()
    _set_status("Recording into " + project.names[selected_pattern] + " · Stop commits the take" if recording else (
        "Playing the arrangement" if song_mode else "Playing " + project.names[selected_pattern]))
    return true

func _drain_recorded() -> void:
    for note in player.read_recorded_notes():
        project.patterns[selected_pattern].add_recorded(note)

func stop_transport() -> void:
    audio.stop_audio()
    if _recording:
        _drain_recorded()
        project.patterns[selected_pattern].end_take()
        project.end_edit()
    _recording = false
    _audio_started = false
    _was_playing = false
    if is_instance_valid(piano):
        piano.all_notes_off()
    if is_instance_valid(_play):
        _play.set_pressed_no_signal(false)
        _record.set_pressed_no_signal(false)
        _pattern.disabled = false
        roll.editable = true
        roll.set_playhead(-1)
        playlist.playhead = -1
        playlist.queue_redraw()
        rack.update_beat(-1)
        _clock.text = "001:01:000"

func _midi(message: JuceMidiMessage) -> void:
    if _modal_open() and message.is_note_on():
        return
    if not audio.is_running() and message.is_note_on():
        if not _prepare_audio():
            return
    if audio.is_running() and not player.queue_midi(message):
        _set_status(player.get_last_error(), true)

func _monitor_keys() -> void:
    if not audio.is_running() and not _prepare_audio():
        return
    if piano.is_visible_in_tree():
        piano.grab_focus()
    else:
        grab_focus()
    _set_status("Monitoring " + project.channels[selected_channel].name)

func _panic() -> void:
    piano.all_notes_off()
    player.panic()
    _set_status("All notes released")

func _edit(action: Callable) -> void:
    stop_transport()
    project.finish_edits()
    action.call()
    _fx_signature = ""
    _refresh()

func _new_pattern() -> void:
    stop_transport()
    var index: int = project.add_pattern()
    if index >= 0:
        select_pattern(index)

func _duplicate_pattern() -> void:
    stop_transport()
    project.begin_edit()
    var index: int = project.duplicate_pattern(selected_pattern)
    project.end_edit()
    if index >= 0:
        select_pattern(index)

func _add_channel(waveform: int) -> void:
    var index: int = project.add_channel(WAVE_NAMES[waveform], waveform)
    if index < 0:
        _set_status("This workspace supports 16 instrument channels.", true)
    else:
        select_channel(index, false)

func _fill(interval: int) -> void:
    _edit(func(): project.fill_steps(selected_pattern, selected_channel, interval))

func _rack_context(channel: int, action: int) -> void:
    select_channel(channel, action == 0)
    if action == 1:
        _show_instrument()
    elif action >= 2:
        _fill([1, 2, 4, 0][action - 2])

func _quantize() -> void:
    _edit(func():
        project.begin_edit()
        var clip: RefCounted = project.patterns[selected_pattern]
        for note in clip.notes.duplicate(true):
            if note.channel == selected_channel + 1:
                var start := clampf(snappedf(note.start, roll.grid), 0, clip.length_beats - roll.grid)
                var end := clampf(snappedf(note.start + note.length, roll.grid), start + roll.grid, clip.length_beats)
                clip.update_note(note.id, note.note, start, end - start, note.velocity)
        project.end_edit()
    )

func _note_selected(id: int) -> void:
    var note: Dictionary = view.find_note(id)
    _velocity.editable = not note.is_empty() and not _recording
    if not note.is_empty():
        _velocity.set_value_no_signal(roundf(note.velocity * 127))

func _note_velocity(value: float) -> void:
    var note: Dictionary = view.find_note(roll.selected)
    if not note.is_empty():
        _edit(func(): view.update_note(note.id, note.note, note.start, note.length, value / 127.0))

func _effect_parameter(slot: int, key: String, value: float) -> void:
    project.effects[slot].parameters[key] = value
    project.remember()
    if _audio_started and post != null:
        post.set_parameter("slot_%d" % slot, key, value)

func _rebuild_effect_parameters() -> void:
    if _fx_parameters == null:
        return
    for child in _fx_parameters.get_children():
        _fx_parameters.remove_child(child)
        child.queue_free()
    _fx_widgets.clear()
    var effect: Dictionary = project.effects[_selected_fx]
    _fx_title.text = "Slot %d · %s" % [_selected_fx + 1, effect.type.replace("_", " ").capitalize()]
    if effect.type.is_empty():
        _fx_parameters.add_child(Look.label("Choose an effect in a master mixer slot.", 12, Look.MUTED))
        return
    var graph: JuceDSPNetwork = project.build_effects()
    if graph == null:
        return
    var params: Dictionary = {}
    for node in graph.get_nodes():
        if node.id == "slot_%d" % _selected_fx:
            params = node.parameters
    for key in params:
        if effect.type == "low_pass" and key == "gain_db":
            continue # The legacy filter gain parameter is only used by EQ types.
        var row := HBoxContainer.new()
        _fx_parameters.add_child(row)
        var label := Look.label(str(key).replace("_", " ").capitalize(), 12)
        label.custom_minimum_size.x = 140
        row.add_child(label)
        var knob = Knob.new()
        knob.minimum = params[key].min
        knob.maximum = params[key].max
        knob.default_value = params[key].value
        knob.set_value_no_signal(params[key].value)
        knob.custom_minimum_size = Vector2(38, 38)
        var value := Look.label("%.2f" % params[key].value, 12, Look.ORANGE)
        knob.value_changed.connect(func(next: float):
            _effect_parameter(_selected_fx, key, next)
            value.text = "%.2f" % next
        )
        knob.drag_started.connect(project.begin_edit)
        knob.drag_finished.connect(project.end_edit)
        row.add_child(knob)
        row.add_child(value)
        _fx_widgets[key] = knob

func _rebuild_browser() -> void:
    if _browser == null:
        return
    _browser.clear()
    var root := _browser.create_item()
    var current := _folder(root, "CURRENT PROJECT")
    for index in project.names.size():
        _browser_item(current, "▸  " + project.names[index], {"kind": "pattern", "index": index})
    var instruments := _folder(root, "GENERATORS")
    for index in WAVE_NAMES.size():
        _browser_item(instruments, "◈  " + WAVE_NAMES[index], {"kind": "instrument", "waveform": index})
    var effects := _folder(root, "EFFECTS")
    for type in FX_TYPES:
        if not type.is_empty():
            _browser_item(effects, "◇  " + type.replace("_", " ").capitalize(), {"kind": "effect", "type": type})
    var files := _folder(root, "PROJECT FILES")
    _browser_item(files, "Open project…", {"kind": "open"})
    _browser_item(files, "Import MIDI clip…", {"kind": "import"})

func _folder(parent: TreeItem, text: String) -> TreeItem:
    var item := _browser.create_item(parent)
    item.set_text(0, text)
    item.set_custom_color(0, Look.ORANGE)
    item.set_selectable(0, false)
    return item

func _browser_item(parent: TreeItem, text: String, data: Dictionary) -> void:
    if not _search.text.is_empty() and not text.to_lower().contains(_search.text.to_lower()):
        return
    var item := _browser.create_item(parent)
    item.set_text(0, text)
    item.set_metadata(0, data)
    item.set_tooltip_text(0, "Drag patterns into the playlist; double-click sounds or effects to load them")

func _browser_selected() -> void:
    var item := _browser.get_selected()
    if item == null:
        return
    var data: Variant = item.get_metadata(0)
    if data is Dictionary and data.get("kind") == "pattern":
        select_pattern(data.index)

func _browser_activated() -> void:
    var item := _browser.get_selected()
    if item == null or not item.get_metadata(0) is Dictionary:
        return
    var data: Dictionary = item.get_metadata(0)
    match data.get("kind"):
        "pattern":
            select_pattern(data.index)
            _show_window("piano")
        "instrument":
            project.begin_edit()
            project.set_channel(selected_channel, "waveform", data.waveform)
            project.set_channel(selected_channel, "name", WAVE_NAMES[data.waveform])
            if data.waveform >= 4:
                project.channels[selected_channel].note = [36, 38, 42, 39][data.waveform - 4]
            project.end_edit()
            select_channel(selected_channel, false)
        "effect":
            for slot in 8:
                if project.effects[slot].type.is_empty():
                    _edit(func():
                        project.effects[slot] = {"type": data.type, "parameters": {}}
                        project.remember()
                    )
                    _selected_fx = slot
                    _rebuild_effect_parameters()
                    _show_window("mixer")
                    return
            _set_status("All eight master effect slots are occupied.")
        "open":
            _guard(func(): _choose_file("open"))
        "import":
            _choose_file("import")

func _toggle_window(key: String) -> void:
    if _windows[key].visible:
        _windows[key].set_open(false)
    else:
        _show_window(key)

func _show_window(key: String) -> void:
    var window: Control = _windows[key]
    window.position.x = clampf(window.position.x, 0, maxf(0, _desktop.size.x - window.size.x))
    window.position.y = clampf(window.position.y, 0, maxf(0, _desktop.size.y - window.size.y))
    window.set_open(true)
    if not _fitted.get(key, false):
        _fit_editor(key)

func _fit_editor(key: String) -> void:
    await get_tree().process_frame
    if not is_inside_tree() or not _windows[key].visible:
        return
    if key == "piano":
        roll.fit_clip()
    elif key == "playlist":
        playlist.fit_song()
    _fitted[key] = true

func _toggle_browser() -> void:
    _browser_panel.visible = not _browser_panel.visible

func _default_layout() -> void:
    await get_tree().process_frame
    if not is_inside_tree():
        return
    var available := _desktop.size
    var top := clampf(available.y * 0.49, 300, 430)
    _windows.playlist.position = Vector2(5, 4)
    _windows.playlist.size = Vector2(available.x - 10, top)
    _windows.rack.size = Vector2(710, maxf(240, available.y - top - 22))
    _windows.rack.position = Vector2(5, minf(top + 12, maxf(0, available.y - _windows.rack.size.y - 5)))
    _windows.mixer.size = Vector2(maxf(630, available.x - 735), maxf(330, available.y - top - 22))
    _windows.mixer.position = Vector2(maxf(5, available.x - _windows.mixer.size.x - 5), minf(top + 12, maxf(0, available.y - _windows.mixer.size.y - 5)))
    _windows.piano.position = Vector2(20, 30)
    _windows.piano.size = Vector2(maxf(720, available.x - 40), maxf(400, available.y - 80))
    _windows.keyboard.position = Vector2(30, maxf(0, available.y - 280))
    _windows.keyboard.size = Vector2(minf(960, available.x - 50), 250)
    _windows.effects.position = Vector2(250, 120)
    _windows.effects.size = Vector2(480, 420)
    for key in _windows:
        _windows[key].set_open(key in ["playlist", "rack"] or (key == "mixer" and available.x >= 1340))
    _fitted.clear()
    await get_tree().process_frame
    if not is_inside_tree():
        return
    playlist.fit_song()
    _fitted.playlist = true
    select_channel(selected_channel, false)

func _build_dialogs() -> void:
    _file = FileDialog.new()
    _file.access = FileDialog.ACCESS_FILESYSTEM
    _file.size = Vector2i(820, 580)
    _file.file_selected.connect(_file_selected)
    add_child(_file)
    _confirm = ConfirmationDialog.new()
    _confirm.title = "Unsaved project"
    _confirm.dialog_text = "Discard unsaved changes? Save the project first to keep them."
    _confirm.ok_button_text = "Discard changes"
    _confirm.confirmed.connect(func():
        var action := _pending
        _pending = Callable()
        if action.is_valid():
            action.call()
    )
    add_child(_confirm)
    _settings = AcceptDialog.new()
    _settings.title = "Audio settings"
    _settings.min_size = Vector2i(440, 230)
    var box := VBoxContainer.new()
    _settings.add_child(box)
    box.add_child(Look.label("Output device"))
    _output = OptionButton.new()
    _output.add_item("Default output")
    box.add_child(_output)
    box.add_child(Look.label("Sample rate"))
    _rate = OptionButton.new()
    for rate in [44100, 48000, 96000]:
        _rate.add_item(str(rate) + " Hz", rate)
    _rate.selected = 1
    box.add_child(_rate)
    box.add_child(Look.label("Buffer size"))
    _buffer = OptionButton.new()
    for frames in [128, 256, 512, 1024]:
        _buffer.add_item(str(frames) + " samples", frames)
    _buffer.selected = 1
    box.add_child(_buffer)
    box.add_child(Look.label("Smaller buffers reduce latency and need more CPU headroom.", 11, Look.MUTED))
    add_child(_settings)
    _instrument = AcceptDialog.new()
    _instrument.title = "Instrument settings"
    _instrument.min_size = Vector2i(360, 220)
    box = VBoxContainer.new()
    _instrument.add_child(box)
    box.add_child(Look.label("Name"))
    _channel_name = LineEdit.new()
    _channel_name.max_length = 64
    box.add_child(_channel_name)
    box.add_child(Look.label("Generator"))
    _channel_wave = OptionButton.new()
    _channel_wave.add_item("Global waveform")
    for name in WAVE_NAMES:
        _channel_wave.add_item(name)
    box.add_child(_channel_wave)
    box.add_child(Look.label("Step-sequencer note (MIDI number)"))
    _channel_note = _spin(0, 127, 1, 60)
    box.add_child(_channel_note)
    _instrument.confirmed.connect(func():
        project.begin_edit()
        project.set_channel(selected_channel, "name", _channel_name.text)
        project.set_channel(selected_channel, "waveform", _channel_wave.selected - 1)
        project.channels[selected_channel].note = int(_channel_note.value)
        project.end_edit()
        select_channel(selected_channel, false)
    )
    add_child(_instrument)
    _rename = AcceptDialog.new()
    _rename.title = "Rename pattern"
    _rename_text = LineEdit.new()
    _rename_text.custom_minimum_size.x = 300
    _rename_text.max_length = 64
    _rename.add_child(_rename_text)
    _rename.confirmed.connect(func():
        if not _rename_text.text.strip_edges().is_empty():
            project.names[selected_pattern] = _rename_text.text.strip_edges()
            project.remember()
    )
    add_child(_rename)
    for dialog in [_file, _confirm, _settings, _instrument, _rename]:
        dialog.visibility_changed.connect(_sync_typing)

func _modal_open() -> bool:
    return (is_instance_valid(_file) and _file.visible) or (is_instance_valid(_confirm) and _confirm.visible) \
        or (is_instance_valid(_settings) and _settings.visible) or (is_instance_valid(_instrument) and _instrument.visible) \
        or (is_instance_valid(_rename) and _rename.visible)

func _sync_typing() -> void:
    if piano != null:
        piano.typing_enabled = _typing.button_pressed and not _modal_open()

func _show_settings() -> void:
    stop_transport()
    var previous := "" if _output.selected == 0 else _output.get_item_text(_output.selected)
    _output.clear()
    _output.add_item("Default output")
    for name in audio.get_output_devices():
        _output.add_item(name)
        if name == previous:
            _output.selected = _output.item_count - 1
    _settings.popup_centered()

func _show_instrument() -> void:
    stop_transport()
    var channel: Dictionary = project.channels[selected_channel]
    _channel_name.text = channel.name
    _channel_wave.selected = channel.waveform + 1
    _channel_note.set_value_no_signal(channel.note)
    _instrument.popup_centered()
    _channel_name.grab_focus()

func _rename_pattern() -> void:
    _rename_text.text = project.names[selected_pattern]
    _rename.popup_centered()
    _rename_text.grab_focus()
    _rename_text.select_all()

func _guard(action: Callable) -> void:
    stop_transport()
    project.finish_edits()
    if project.is_dirty():
        _pending = action
        _confirm.popup_centered()
    else:
        action.call()

func _new_project() -> void:
    song_mode = false
    var empty = Project.new()
    project.load_document(empty.document())
    project.reset_history()
    selected_pattern = 0
    selected_channel = 0
    _path = ""
    _refresh()
    select_channel(0, false)

func _demo_project() -> void:
    _new_project()
    project.demo()
    song_mode = true
    _refresh()
    playlist.fit_song()

func save_project() -> void:
    _tempo.apply()
    grab_focus()
    stop_transport()
    project.finish_edits()
    if _path.is_empty():
        _choose_file("save")
    elif project.save_file(_path, true):
        _set_status("Saved " + _path)
    else:
        _set_status(project.last_error, true)

func _choose_file(action: String) -> void:
    stop_transport()
    _file_action = action
    _file.file_mode = FileDialog.FILE_MODE_OPEN_FILE if action in ["open", "import"] else FileDialog.FILE_MODE_SAVE_FILE
    if action == "midi":
        _file.filters = PackedStringArray(["*.mid ; Standard MIDI"])
        _file.current_file = "song.mid"
    elif action == "import":
        _file.filters = PackedStringArray(["*.midiclip.json ; JUCE MIDI clip"])
        _file.current_file = ""
    else:
        _file.filters = PackedStringArray(["*.daw.json ; JUCE Studio project"])
        _file.current_file = "" if action == "open" else project.title + ".daw.json"
    _file.popup_centered()

func _file_selected(path: String) -> void:
    match _file_action:
        "open":
            if project.load_file(path):
                song_mode = not project.placements.is_empty()
                _path = path
                selected_pattern = 0
                select_channel(0, false)
                _refresh()
                playlist.fit_song()
                _set_status("Opened " + path)
            else:
                _set_status(project.last_error, true)
        "save":
            if project.save_file(path, true):
                _path = path
                _set_status("Saved " + path)
            else:
                _set_status(project.last_error, true)
        "import":
            var clip = Clip.new()
            if not clip.load_file(path):
                _set_status(clip.last_error, true)
                return
            if project.patterns.size() >= 64:
                _set_status("The project already has 64 patterns.", true)
                return
            project.begin_edit()
            var maximum_channel := 1
            for note in clip.notes:
                maximum_channel = maxi(maximum_channel, note.channel)
            while project.channels.size() < maximum_channel:
                project.add_channel("Synth %d" % (project.channels.size() + 1), 1)
            var index: int = project.add_pattern(path.get_file().trim_suffix(".midiclip.json"))
            clip.bpm = project.bpm
            project.patterns[index].load_document(clip.document())
            project.end_edit()
            select_pattern(index)
            _set_status("Imported " + path)
        "midi":
            var clip = Clip.new()
            var notes: Array = project.compile_song() if song_mode else project.patterns[selected_pattern].native_notes()
            if song_mode and not project.last_error.is_empty():
                _set_status(project.last_error, true)
                return
            if not clip.load_document({"type": "juce_midi_clip", "schema_version": 1, "bpm": project.bpm,
                "length_beats": project.song_length if song_mode else project.patterns[selected_pattern].length_beats, "notes": notes}):
                _set_status(clip.last_error, true)
            elif not clip.export_midi(path, true):
                _set_status(clip.last_error, true)
            else:
                _set_status("Exported " + path)

func _save_layout() -> void:
    var config := ConfigFile.new()
    for key in _windows:
        var window: Control = _windows[key]
        config.set_value(key, "position", window.position)
        config.set_value(key, "size", window.size)
        config.set_value(key, "visible", window.visible)
    if config.save("user://juce_studio_layout.cfg") == OK:
        _set_status("Workspace layout saved")

func _restore_layout() -> void:
    var config := ConfigFile.new()
    if config.load("user://juce_studio_layout.cfg") != OK:
        _set_status("No saved workspace layout yet.")
        return
    for key in _windows:
        var window: Control = _windows[key]
        var position: Variant = config.get_value(key, "position", window.position)
        var dimensions: Variant = config.get_value(key, "size", window.size)
        if position is Vector2 and dimensions is Vector2 and position.is_finite() and dimensions.is_finite():
            window.size = dimensions.max(window.custom_minimum_size).min(_desktop.size.max(window.custom_minimum_size))
            window.position = position.clamp(Vector2.ZERO, (_desktop.size - Vector2(120, 40)).max(Vector2.ZERO))
            window.set_open(bool(config.get_value(key, "visible", window.visible)))
    _set_status("Workspace layout restored")

func _input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and not _modal_open():
        _panic()
        get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo or _modal_open():
        return
    var focus := get_viewport().gui_get_focus_owner()
    if (focus is LineEdit or focus is TextEdit or focus is SpinBox) and not ((event.ctrl_pressed or event.meta_pressed) and event.keycode in [KEY_S, KEY_O, KEY_N]):
        return
    if event.ctrl_pressed or event.meta_pressed:
        match event.keycode:
            KEY_S: save_project()
            KEY_O: _guard(func(): _choose_file("open"))
            KEY_N: _guard(_new_project)
            KEY_Z: _edit(func(): project.redo() if event.shift_pressed else project.undo())
            KEY_Y: _edit(func(): project.redo())
            KEY_R: start_transport(true)
            KEY_T:
                _typing.set_pressed_no_signal(not _typing.button_pressed)
                _sync_typing()
            _: return
    else:
        match event.keycode:
            KEY_SPACE: _play_action()
            KEY_F4: _new_pattern()
            KEY_F5: _toggle_window("playlist")
            KEY_F6: _toggle_window("rack")
            KEY_F7: _toggle_window("piano")
            KEY_F8: _toggle_browser()
            KEY_F9: _toggle_window("mixer")
            _: return
    get_viewport().set_input_as_handled()

func _set_status(text: String, error := false) -> void:
    if is_instance_valid(_status):
        _status.text = text
        _status.add_theme_color_override("font_color", Color("e99a8e") if error else Look.MUTED)

func _process(delta: float) -> void:
    if _clock == null:
        return
    if _audio_started and not audio.is_running():
        stop_transport()
        _set_status("Audio device stopped. Check Audio settings and try again.", true)
        return
    if _recording:
        _drain_recorded()
    var state := player.get_transport()
    if state.playing:
        if _show_seconds:
            var seconds: float = state.sample_position / _actual_rate
            _clock.text = "%02d:%02d:%03d" % [int(seconds) / 60, int(seconds) % 60, int(fposmod(seconds, 1.0) * 1000)]
        else:
            _clock.text = "%03d:%02d:%03d" % [floori(state.beat / 4) + 1, floori(fposmod(state.beat, 4)) + 1, floori(fposmod(state.beat, 1.0) * 96)]
        var local := -1.0
        if song_mode:
            playlist.playhead = state.beat
            for item in project.placements:
                if item.pattern == selected_pattern and state.beat >= item.start and state.beat < item.start + item.length:
                    local = fposmod(state.beat - item.start, project.patterns[selected_pattern].length_beats)
                    break
        else:
            local = state.beat
        roll.set_playhead(local)
        rack.update_beat(local)
        playlist.queue_redraw()
    elif _was_playing:
        stop_transport()
    mixer.update_meters(player.get_channel_peaks(), audio.get_peak(), delta)
    if state.input_drops > 0 or state.recording_drops > 0:
        _set_status("MIDI queue overflow; stop and review the recorded take.", true)

func _exit_tree() -> void:
    audio.stop_audio()
    if is_instance_valid(piano):
        piano.all_notes_off()
    if get_tree() != null:
        get_tree().auto_accept_quit = _old_auto_quit

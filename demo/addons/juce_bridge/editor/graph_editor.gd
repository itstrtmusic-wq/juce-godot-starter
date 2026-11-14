@tool
extends Control
## Reusable visual editor. The native API remains independent of this UI.
signal patch_changed(patch: Dictionary)
signal topology_edit_requested

const Document = preload("res://addons/juce_bridge/editor/graph_document.gd")
const Block = preload("res://addons/juce_bridge/editor/graph_block.gd")
const Look = preload("res://addons/juce_bridge/editor/graph_theme.gd")
const CATALOG := {
    "oscillator": ["Oscillator", "Generators", "Sine, triangle, saw or square test source."],
    "lfo": ["LFO", "Generators", "Slow modulation source. Connect Control out to a parameter."],
    "constant": ["Constant", "Generators", "A constant signal or control value."],
    "low_pass": ["Low-pass filter", "Filters & EQ", "Roll off high frequencies."],
    "high_pass": ["High-pass filter", "Filters & EQ", "Remove low frequencies and rumble."],
    "band_pass": ["Band-pass filter", "Filters & EQ", "Keep a band around the centre frequency."],
    "notch": ["Notch filter", "Filters & EQ", "Cut a narrow band of frequencies."],
    "peak": ["Peak EQ", "Filters & EQ", "Boost or cut around a chosen frequency."],
    "low_shelf": ["Low shelf", "Filters & EQ", "Boost or cut the low end."],
    "high_shelf": ["High shelf", "Filters & EQ", "Boost or cut the high end."],
    "gain": ["Gain", "Dynamics", "Adjust signal level with a short gain ramp."],
    "compressor": ["Compressor", "Dynamics", "Control dynamic range."],
    "limiter": ["Limiter", "Dynamics", "Two-stage dynamics with a final clip at ±1."],
    "noise_gate": ["Noise gate", "Dynamics", "Reduce signals below the threshold."],
    "adsr": ["ADSR envelope", "Dynamics", "Gate-controlled envelope for instruments and effects."],
    "delay": ["Delay", "Space & motion", "Echo with internal feedback and a wet/dry mix."],
    "reverb": ["Reverb", "Space & motion", "JUCE mono/stereo room reverb."],
    "chorus": ["Chorus", "Space & motion", "Modulated delay for chorus, flanging or vibrato."],
    "phaser": ["Phaser", "Space & motion", "Sweeping all-pass filter stages."],
    "tanh": ["Soft distortion", "Math & shaping", "Smooth saturation: tanh(input × drive)."],
    "clip": ["Hard clip", "Math & shaping", "Clamp the signal to a chosen threshold."],
    "mix": ["Mix", "Math & shaping", "Sum incoming audio paths."],
    "multiply": ["Multiply", "Math & shaping", "Multiply incoming signals sample by sample."],
    "add": ["Add offset", "Math & shaping", "Add a constant to the signal."],
    "abs": ["Absolute", "Math & shaping", "Return the absolute sample value."],
    "sin": ["Sine shaper", "Math & shaping", "Apply sine to each incoming sample."]
}
@export var manage_window_close := false
@export var enable_recovery := false
@export var recovery_name := "juce_graph_preview_recovery.json"

var document := Document.new()
var graph: GraphEdit
var blocks: Dictionary = {}
var selected_id := ""
var selected_link: Dictionary = {}
var _device: RefCounted
var _available := false
var _playing := false
var _building := false
var _changing_inspector := false
var _clearing_inspector := false
var _dragging_connection := false
var _block_serial := 0
var _status: Label
var _document_title: Label
var _counts: Label
var _play: Button
var _stop: Button
var _undo: Button
var _redo: Button
var _meter: ProgressBar
var _peak_label: Label
var _palette: VBoxContainer
var _search: LineEdit
var _inspector: VBoxContainer
var _parameter_controls: Dictionary = {}
var _context: PopupMenu
var _context_position := Vector2.ZERO
var _context_types: Array = []
var _parameter_timer: Timer
var _recovery_timer: Timer
var _save_dialog: FileDialog
var _open_dialog: FileDialog
var _export_dialog: FileDialog
var _discard: ConfirmationDialog
var _discard_action: Callable
var _pending_exit := false
var _discard_exit := false
var _audio_dialog: AcceptDialog
var _output_menu: OptionButton
var _input_menu: OptionButton
var _rate_menu: OptionButton
var _buffer_menu: OptionButton
var _capture: CheckButton
var _old_auto_quit := true
var _last_recovery_text := ""
var _startup_pending := true

func _ready() -> void:
    theme = Look.create()
    custom_minimum_size = Vector2(960, 620)
    _available = document.initialize()
    if _available:
        _device = ClassDB.instantiate("JuceAudioDeviceManager")
    _build_ui()
    document.changed.connect(_on_document_changed)
    document.parameter_changed.connect(_on_parameter_changed)
    if _available:
        _rebuild_graph()
        _set_status("Connect teal audio ports. Use violet Control out to modulate a parameter.")
    else:
        _set_status(document.last_error, true)
        _show_empty_inspector("Native addon missing", document.last_error)
    if manage_window_close and not Engine.is_editor_hint():
        _old_auto_quit = get_tree().auto_accept_quit
        get_tree().auto_accept_quit = false
    call_deferred("_finish_startup")

func _finish_startup() -> void:
    await get_tree().process_frame
    await get_tree().process_frame
    if not is_inside_tree() or not _available or not _startup_pending:
        return
    _startup_pending = false
    if recovery_enabled() and _recover():
        _apply_view()
        _set_status("Recovered an unsaved network. Save it to keep a named copy.")
    else:
        fit_graph()
        inspect_node("filter")

func _button(caption: String, action: Callable, tip := "") -> Button:
    var button := Button.new()
    button.text = caption
    button.tooltip_text = tip
    button.pressed.connect(action)
    return button

func _panel(color := Look.PANEL, padding := 12) -> PanelContainer:
    var panel := PanelContainer.new()
    panel.add_theme_stylebox_override("panel", Look.box(color, Look.LINE, 8, padding))
    return panel

func _build_ui() -> void:
    var background := ColorRect.new()
    background.color = Look.BG
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)
    var margin := MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for edge in ["left", "right", "top", "bottom"]:
        margin.add_theme_constant_override("margin_" + edge, 14)
    add_child(margin)
    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margin.add_child(root)
    var toolbar := _panel()
    root.add_child(toolbar)
    var top := HBoxContainer.new()
    top.add_theme_constant_override("separation", 10)
    toolbar.add_child(top)
    top.add_child(Look.label("JUCE", 22, Look.AUDIO))
    top.add_child(Look.label("/ GRAPH", 22))
    top.add_child(Look.label("   EFFECT DESIGNER", 11, Look.MUTED))
    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(spacer)
    var new_menu := MenuButton.new()
    new_menu.text = "New ▾"
    var popup := new_menu.get_popup()
    popup.add_item("Modulated filter", 0)
    popup.add_item("Live input effect", 1)
    popup.add_item("Blank network", 2)
    popup.id_pressed.connect(func(index: int): _confirm_discard(func(): new_network(["filter", "live_input", "blank"][index])))
    top.add_child(new_menu)
    top.add_child(_button("Open", func(): _confirm_discard(func(): _open_dialog.popup_centered_ratio(0.75)), "Open a graph document or import a DSP patch · Ctrl+O"))
    var save_menu := MenuButton.new()
    save_menu.text = "Save ▾"
    save_menu.get_popup().add_item("Save", 0)
    save_menu.get_popup().add_item("Save as…", 1)
    save_menu.get_popup().id_pressed.connect(func(index: int):
        if index == 0:
            save()
        else:
            save_as()
    )
    top.add_child(save_menu)
    top.add_child(_button("Export DSP", func(): _export_dialog.popup_centered_ratio(0.75), "Export a native JUCE DSP patch without editor layout"))
    top.add_child(_button("Audio settings", _show_audio_settings))
    _play = _button("▶  Preview", start_preview, "Play this network through JUCE")
    _play.add_theme_stylebox_override("normal", Look.box(Color("214b42"), Look.AUDIO, 6, 9))
    top.add_child(_play)
    _stop = _button("■  Stop", stop_preview)
    top.add_child(_stop)
    var sub := HBoxContainer.new()
    root.add_child(sub)
    _document_title = Look.label("Untitled effect", 16)
    _document_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _document_title.clip_text = true
    _document_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    sub.add_child(_document_title)
    _counts = Look.label("", 12, Look.MUTED)
    sub.add_child(_counts)
    _undo = _button("Undo", undo, "Undo · Ctrl+Z")
    _redo = _button("Redo", redo, "Redo · Ctrl+Shift+Z")
    sub.add_child(_undo)
    sub.add_child(_redo)
    sub.add_child(_button("Arrange", arrange, "Arrange by signal dependencies"))
    sub.add_child(_button("Fit", fit_graph, "Fit the whole network in view"))
    var body := HBoxContainer.new()
    body.add_theme_constant_override("separation", 10)
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body)
    var library := _panel()
    library.custom_minimum_size.x = 208
    body.add_child(library)
    var library_box := VBoxContainer.new()
    library_box.add_theme_constant_override("separation", 10)
    library.add_child(library_box)
    library_box.add_child(Look.label("NODE LIBRARY", 12, Look.MUTED))
    _search = LineEdit.new()
    _search.placeholder_text = "Search processors…"
    _search.text_changed.connect(func(_query: String): _populate_palette())
    library_box.add_child(_search)
    var library_scroll := ScrollContainer.new()
    library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    library_box.add_child(library_scroll)
    _palette = VBoxContainer.new()
    _palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _palette.add_theme_constant_override("separation", 5)
    library_scroll.add_child(_palette)
    library_box.add_child(Look.label("Click a node to add it.\nRight-click the canvas\nfor a quick-add menu.", 11, Look.MUTED))
    var canvas := VBoxContainer.new()
    canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body.add_child(canvas)
    var legend := HBoxContainer.new()
    legend.add_child(Look.label("●  Audio", 12, Look.AUDIO))
    legend.add_child(Look.label("    ◇  Modulation", 12, Look.CONTROL))
    var legend_gap := Control.new()
    legend_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    legend.add_child(legend_gap)
    legend.add_child(Look.label("MMB pan · Wheel zoom", 11, Look.MUTED))
    canvas.add_child(legend)
    graph = GraphEdit.new()
    graph.name = "DSPCanvas"
    graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
    graph.custom_minimum_size = Vector2(400, 300)
    graph.zoom_min = 0.25
    graph.zoom_max = 2.0
    graph.grid_pattern = GraphEdit.GRID_PATTERN_DOTS
    graph.snapping_distance = 20
    graph.minimap_size = Vector2(170, 100)
    graph.minimap_opacity = 0.8
    graph.show_arrange_button = false
    graph.show_grid_buttons = false
    graph.connection_lines_thickness = 2.4
    graph.right_disconnects = true
    graph.add_valid_right_disconnect_type(0)
    graph.add_valid_right_disconnect_type(1)
    graph.connection_request.connect(_connection_request)
    graph.disconnection_request.connect(_disconnection_request)
    graph.delete_nodes_request.connect(_delete_graph_nodes)
    graph.node_selected.connect(func(node: Node):
        if not _building:
            inspect_node(node.dsp_id)
    )
    graph.end_node_move.connect(_commit_history)
    graph.begin_node_move.connect(_flush_parameter_history)
    graph.popup_request.connect(_show_context)
    graph.gui_input.connect(_canvas_input)
    graph.connection_drag_started.connect(func(_n: StringName, _p: int, _out: bool): _dragging_connection = true)
    graph.connection_drag_ended.connect(func(): _dragging_connection = false)
    graph.scroll_offset_changed.connect(func(offset: Vector2):
        if not _building:
            document.view.scroll_x = clampf(offset.x, -100000, 100000)
            document.view.scroll_y = clampf(offset.y, -100000, 100000)
    )
    canvas.add_child(graph)
    var help := Look.label("Drag from an output port to an input. Select a block or cable to edit it.", 12, Look.MUTED)
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    canvas.add_child(help)
    var inspector_panel := _panel()
    inspector_panel.custom_minimum_size.x = 294
    body.add_child(inspector_panel)
    var inspector_scroll := ScrollContainer.new()
    inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    inspector_panel.add_child(inspector_scroll)
    _inspector = VBoxContainer.new()
    _inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _inspector.add_theme_constant_override("separation", 12)
    inspector_scroll.add_child(_inspector)
    _show_empty_inspector()
    var bottom := HBoxContainer.new()
    root.add_child(bottom)
    _status = Look.label("", 12, Look.MUTED)
    _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    bottom.add_child(_status)
    bottom.add_child(Look.label("OUTPUT", 10, Look.MUTED))
    _meter = ProgressBar.new()
    _meter.custom_minimum_size = Vector2(140, 12)
    _meter.max_value = 1
    _meter.show_percentage = false
    bottom.add_child(_meter)
    _peak_label = Look.label("−∞ dB", 12, Look.AUDIO)
    _peak_label.custom_minimum_size.x = 66
    bottom.add_child(_peak_label)
    _parameter_timer = Timer.new()
    _parameter_timer.one_shot = true
    _parameter_timer.wait_time = 0.3
    _parameter_timer.timeout.connect(_commit_history)
    add_child(_parameter_timer)
    _recovery_timer = Timer.new()
    _recovery_timer.wait_time = 3.0
    _recovery_timer.timeout.connect(save_recovery)
    add_child(_recovery_timer)
    _recovery_timer.start()
    _build_dialogs()
    _populate_palette()
    _update_chrome()

func _build_dialogs() -> void:
    _context = PopupMenu.new()
    _context.id_pressed.connect(func(index: int): add_processor(_context_types[index], _context_position))
    add_child(_context)
    _save_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save graph", "*.jucegraph ; JUCE graph document")
    _save_dialog.current_file = "My effect.jucegraph"
    _save_dialog.file_selected.connect(func(path: String):
        _flush_parameter_history()
        if document.save_file(path, true):
            _clear_recovery()
            _set_status("Saved " + path.get_file())
        else:
            _set_status(document.last_error, true)
    )
    _open_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open graph or DSP patch", "*.jucegraph,*.json ; Graph documents and DSP patches")
    _open_dialog.file_selected.connect(open_file)
    _export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Export native DSP patch", "*.json ; JUCE DSP patch")
    _export_dialog.current_file = "My effect.json"
    _export_dialog.file_selected.connect(func(path: String):
        if not _available:
            return
        if document.network.save_patch(path, true):
            _set_status("Exported DSP patch " + path.get_file())
        else:
            _set_status(document.network.get_last_error(), true)
    )
    _discard = ConfirmationDialog.new()
    _discard.title = "Unsaved network"
    _discard.dialog_text = "This effect has unsaved changes. Discard them?"
    _discard.ok_button_text = "Discard changes"
    _discard.cancel_button_text = "Keep editing"
    _discard.confirmed.connect(func():
        _discard_exit = _pending_exit
        _clear_recovery()
        if _discard_action.is_valid():
            _discard_action.call()
    )
    add_child(_discard)
    _audio_dialog = AcceptDialog.new()
    _audio_dialog.title = "Audio preview settings"
    _audio_dialog.min_size = Vector2i(450, 340)
    var audio_box := VBoxContainer.new()
    audio_box.add_theme_constant_override("separation", 12)
    _audio_dialog.add_child(audio_box)
    audio_box.add_child(Look.label("Output device"))
    _output_menu = OptionButton.new()
    _output_menu.add_item("Default output")
    audio_box.add_child(_output_menu)
    _capture = CheckButton.new()
    _capture.text = "Enable live audio input"
    audio_box.add_child(_capture)
    audio_box.add_child(Look.label("Input device"))
    _input_menu = OptionButton.new()
    _input_menu.add_item("Default input")
    audio_box.add_child(_input_menu)
    var options := HBoxContainer.new()
    audio_box.add_child(options)
    _rate_menu = OptionButton.new()
    for rate in [48000, 44100, 96000]:
        _rate_menu.add_item("%d Hz" % rate, rate)
    options.add_child(_rate_menu)
    _buffer_menu = OptionButton.new()
    for count in [256, 128, 512, 1024]:
        _buffer_menu.add_item("%d samples" % count, count)
    options.add_child(_buffer_menu)
    var hint := Look.label("Use headphones when monitoring a microphone.\nChanges apply the next time you start Preview.", 12, Look.MUTED)
    hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    audio_box.add_child(hint)
    add_child(_audio_dialog)

func _file_dialog(mode: FileDialog.FileMode, caption: String, filter_text: String) -> FileDialog:
    var dialog := FileDialog.new()
    dialog.file_mode = mode
    dialog.access = FileDialog.ACCESS_FILESYSTEM
    dialog.title = caption
    dialog.filters = PackedStringArray([filter_text])
    dialog.current_dir = ProjectSettings.globalize_path("user://")
    add_child(dialog)
    return dialog

func _populate_palette() -> void:
    for child in _palette.get_children():
        _palette.remove_child(child)
        child.queue_free()
    var query := _search.text.strip_edges().to_lower()
    var category := ""
    for kind in CATALOG:
        if not document.definitions.has(kind):
            continue
        var entry: Array = CATALOG[kind]
        if not query.is_empty() and not (String(entry[0]) + " " + String(entry[1]) + " " + String(entry[2])).to_lower().contains(query):
            continue
        if category != entry[1]:
            category = entry[1]
            var section := Look.label(category.to_upper(), 10, Look.MUTED)
            section.custom_minimum_size.y = 28
            section.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
            _palette.add_child(section)
        var button := _button(entry[0], func(): add_processor(kind), entry[2])
        button.alignment = HORIZONTAL_ALIGNMENT_LEFT
        button.add_theme_color_override("font_color", _accent(kind))
        _palette.add_child(button)
    if _palette.get_child_count() == 0:
        _palette.add_child(Look.label("No matching processors", 12, Look.MUTED))

func _accent(kind: String) -> Color:
    if kind == "lfo":
        return Look.CONTROL
    var category: String = CATALOG.get(kind, ["", "", ""])[1]
    if category == "Filters & EQ":
        return Color("9fc2ff")
    if category == "Dynamics":
        return Color("f4c88c")
    if category == "Space & motion":
        return Color("bda7f7")
    if category == "Math & shaping":
        return Color("eea5c9")
    return Look.AUDIO

func _title(id: String) -> String:
    var alias: String = document.titles.get(id, "")
    if not alias.is_empty():
        return alias
    if id == "input":
        return "Audio input"
    if id == "output":
        return "Audio output"
    var kind: String = document.records[id].type
    return CATALOG.get(kind, [kind.capitalize(), "", ""])[0]

func _rebuild_graph() -> void:
    _building = true
    graph.clear_connections()
    for block in blocks.values():
        graph.remove_child(block)
        block.queue_free()
    blocks.clear()
    for id in document.records:
        var info: Dictionary = document.records[id]
        var block := Block.new()
        block.name = "block_%d" % _block_serial
        _block_serial += 1
        block.configure(info, _title(id), _accent(info.type))
        block.position_offset = document.positions.get(id, Vector2.ZERO)
        block.remove_requested.connect(func(node_id: String): remove_processors([node_id]))
        block.position_offset_changed.connect(func():
            if not _building:
                document.move_node(id, block.position_offset)
        )
        graph.add_child(block)
        blocks[id] = block
    for edge in document.network.get_connections():
        var source: GraphNode = blocks[edge.source]
        var destination: GraphNode = blocks[edge.destination]
        var input: int = destination.input_for()
        if input >= 0:
            graph.connect_node(source.name, 0, destination.name, input)
    for edge in document.network.get_modulation_connections():
        var source: GraphNode = blocks[edge.source]
        var destination: GraphNode = blocks[edge.destination]
        var input: int = destination.input_for(edge.parameter)
        if input >= 0:
            graph.connect_node(source.name, 1, destination.name, input)
    _building = false
    if document.records.has(selected_id):
        blocks[selected_id].selected = true
        inspect_node(selected_id)
    elif not selected_link.is_empty():
        inspect_link(selected_link)
    else:
        _show_empty_inspector()
    _update_chrome()

func _on_document_changed(structural: bool) -> void:
    if structural:
        _rebuild_graph()
    _update_chrome()
    patch_changed.emit(document.network.export_patch())

func _on_parameter_changed(id: String, parameter: String, value: float) -> void:
    if blocks.has(id):
        blocks[id].update_parameter(parameter, value)
    if selected_id != id or not _parameter_controls.has(parameter):
        return
    var controls: Dictionary = _parameter_controls[parameter]
    _changing_inspector = true
    if controls.has("toggle"):
        controls.toggle.set_pressed_no_signal(value >= 0.5)
    elif controls.has("choices"):
        controls.choices.select(int(value))
    else:
        controls.spin.value = value
        controls.slider.value = _to_normalized(value, controls.low, controls.high, controls.logarithmic)
    _changing_inspector = false

func _clear_inspector() -> void:
    _clearing_inspector = true
    _parameter_controls.clear()
    for child in _inspector.get_children():
        _inspector.remove_child(child)
        child.queue_free()
    _clearing_inspector = false

func _show_empty_inspector(caption := "Build something new", message := "Select a block to edit its sound.\nSelect a cable to change routing gain or modulation depth.") -> void:
    _clear_inspector()
    _inspector.add_child(Look.label("INSPECTOR", 11, Look.MUTED))
    _inspector.add_child(Look.label(caption, 18))
    var description := Look.label(message, 13, Look.MUTED)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    description.custom_minimum_size.x = 258
    _inspector.add_child(description)

func inspect_node(id: String) -> void:
    if not document.records.has(id):
        return
    _flush_parameter_history()
    selected_id = id
    selected_link = {}
    _clear_inspector()
    _inspector.add_child(Look.label("PROCESSOR", 11, Look.MUTED))
    var info: Dictionary = document.records[id]
    var heading := Look.label(_title(id), 20, _accent(info.type))
    heading.clip_text = true
    heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    heading.tooltip_text = _title(id)
    _inspector.add_child(heading)
    var kind_label := Look.label(info.type + "  /  " + id, 11, Look.MUTED)
    kind_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    kind_label.tooltip_text = id
    _inspector.add_child(kind_label)
    if id in ["input", "output"]:
        var text := "This port receives live audio when input is enabled in Audio settings." if id == "input" else "All incoming audio paths are summed and sent to the JUCE output device."
        var hint := Look.label(text, 13, Look.MUTED)
        hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _inspector.add_child(hint)
        return
    var description := Look.label(CATALOG.get(info.type, ["", "", "Native DSP processor"])[2], 12, Look.MUTED)
    description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _inspector.add_child(description)
    var alias := LineEdit.new()
    alias.text = document.titles.get(id, "")
    alias.placeholder_text = "Give this block a title…"
    alias.max_length = 80
    alias.text_submitted.connect(func(text: String): document.set_title(id, text))
    alias.focus_exited.connect(func():
        if not _building and not _clearing_inspector and is_instance_valid(alias) and alias.is_inside_tree() and alias.text != document.titles.get(id, ""):
            document.set_title(id, alias.text)
    )
    _inspector.add_child(alias)
    for parameter in info.parameters:
        _parameter_row(id, parameter, info.parameters[parameter])
    var note := Look.label("◇ Violet ports accept modulation.\nParameters update live during Preview.\nWiring changes stop Preview.", 11, Look.MUTED)
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _inspector.add_child(note)
    _inspector.add_child(_button("Delete processor", func(): remove_processors([id])))

func _parameter_row(id: String, key: String, parameter: Dictionary) -> void:
    if key in ["bypass", "gate"]:
        var toggle := CheckButton.new()
        toggle.text = key.capitalize()
        toggle.button_pressed = float(parameter.value) >= 0.5
        toggle.toggled.connect(func(on: bool): _apply_parameter(id, key, 1.0 if on else 0.0))
        _inspector.add_child(toggle)
        _parameter_controls[key] = {"toggle": toggle}
        return
    if key == "waveform":
        _inspector.add_child(Look.label("Waveform", 12, Look.MUTED))
        var choices := OptionButton.new()
        for caption in ["Sine", "Triangle", "Saw", "Square"]:
            choices.add_item(caption)
        choices.selected = int(parameter.value)
        choices.item_selected.connect(func(index: int): _apply_parameter(id, key, float(index)))
        _inspector.add_child(choices)
        _parameter_controls[key] = {"choices": choices}
        return
    var row := HBoxContainer.new()
    var caption := Look.label(key.replace("_", " ").capitalize(), 12)
    if key == "gain_db" and document.records[id].type in ["low_pass", "high_pass", "band_pass", "notch"]:
        caption.text = "Gain dB (EQ only)"
        caption.tooltip_text = "This parameter is unused for this filter type; use a Peak or Shelf node for EQ gain."
    caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(caption)
    var spin := SpinBox.new()
    spin.custom_minimum_size.x = 110
    spin.min_value = parameter.min
    spin.max_value = parameter.max
    spin.step = 1.0 if key in ["frequency", "centre_frequency"] else 0.001
    spin.value = parameter.value
    row.add_child(spin)
    _inspector.add_child(row)
    var slider := HSlider.new()
    slider.min_value = 0
    slider.max_value = 1
    slider.step = 0.0005
    var logarithmic: bool = float(parameter.min) > 0 and float(parameter.max) / float(parameter.min) >= 100
    slider.value = _to_normalized(float(parameter.value), float(parameter.min), float(parameter.max), logarithmic)
    _inspector.add_child(slider)
    _parameter_controls[key] = {"spin": spin, "slider": slider, "low": float(parameter.min), "high": float(parameter.max), "logarithmic": logarithmic}
    spin.value_changed.connect(func(value: float):
        if _changing_inspector:
            return
        _changing_inspector = true
        slider.value = _to_normalized(value, float(parameter.min), float(parameter.max), logarithmic)
        _changing_inspector = false
        _apply_parameter(id, key, value)
    )
    slider.value_changed.connect(func(value: float):
        if _changing_inspector:
            return
        var real_value := _from_normalized(value, float(parameter.min), float(parameter.max), logarithmic)
        _changing_inspector = true
        spin.value = real_value
        _changing_inspector = false
        _apply_parameter(id, key, real_value)
    )

static func _to_normalized(value: float, low: float, high: float, logarithmic: bool) -> float:
    return clampf(log(maxf(value, low) / low) / log(high / low), 0, 1) if logarithmic else inverse_lerp(low, high, value)

static func _from_normalized(value: float, low: float, high: float, logarithmic: bool) -> float:
    return low * pow(high / low, value) if logarithmic else lerpf(low, high, value)

func _apply_parameter(id: String, key: String, value: float) -> void:
    if not document.set_parameter(id, key, value, false):
        _set_status(document.last_error, true)
        return
    _parameter_timer.start()
    _update_chrome()

func _connection_description(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> Dictionary:
    var source := graph.get_node_or_null(NodePath(from_node))
    var destination := graph.get_node_or_null(NodePath(to_node))
    if source == null or destination == null or from_port < 0 or from_port >= source.output_ports.size() or to_port < 0 or to_port >= destination.input_ports.size():
        return {}
    var out: Dictionary = source.output_ports[from_port]
    var input: Dictionary = destination.input_ports[to_port]
    if out.kind != input.kind:
        return {}
    var link := {"kind": input.kind, "source": source.dsp_id, "destination": destination.dsp_id}
    if input.kind == "control":
        link.parameter = input.parameter
    return link

func _connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    var link := _connection_description(from_node, from_port, to_node, to_port)
    if link.is_empty():
        _set_status("Connect audio to audio, or Control out to a violet parameter port.", true)
        return
    _stop_for_edit()
    var ok: bool
    if link.kind == "audio":
        ok = document.connect_audio(link.source, link.destination)
    else:
        ok = document.connect_control(link.source, link.destination, link.parameter)
    if ok:
        inspect_link(link)
        _set_status("Connected. Select the cable to edit " + ("its gain." if link.kind == "audio" else "modulation depth and offset."))
    else:
        _set_status(document.last_error, true)

func _disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
    var link := _connection_description(from_node, from_port, to_node, to_port)
    if not link.is_empty():
        _stop_for_edit()
        selected_link = {}
        if not document.disconnect_link(link):
            _set_status(document.last_error, true)

func _canvas_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not _dragging_connection:
        var wire := graph.get_closest_connection_at_point(event.position, 9.0)
        if not wire.is_empty():
            var link := _connection_description(wire.from_node, wire.from_port, wire.to_node, wire.to_port)
            if not link.is_empty():
                inspect_link(link)

func inspect_link(link: Dictionary) -> void:
    var entries: Array = document.network.get_connections() if link.kind == "audio" else document.network.get_modulation_connections()
    var found: Dictionary = {}
    for entry in entries:
        if entry.source == link.source and entry.destination == link.destination and (link.kind == "audio" or entry.parameter == link.parameter):
            found = entry
            break
    if found.is_empty():
        selected_link = {}
        _show_empty_inspector()
        return
    _flush_parameter_history()
    selected_id = ""
    selected_link = link.duplicate()
    _clear_inspector()
    _inspector.add_child(Look.label("CONNECTION", 11, Look.MUTED))
    _inspector.add_child(Look.label("Audio route" if link.kind == "audio" else "Parameter modulation", 19, Look.AUDIO if link.kind == "audio" else Look.CONTROL))
    var path := Look.label(_title(link.source) + "\n↓\n" + _title(link.destination) + (" · " + String(link.parameter) if link.kind == "control" else ""), 14)
    path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _inspector.add_child(path)
    var inputs: Dictionary = {}
    var keys := ["gain"] if link.kind == "audio" else ["depth", "offset"]
    for key in keys:
        _inspector.add_child(Look.label(String(key).capitalize(), 12, Look.MUTED))
        var spin := SpinBox.new()
        spin.min_value = -100 if key == "gain" else -1000000
        spin.max_value = 100 if key == "gain" else 1000000
        spin.step = 0.001
        spin.value = found[key]
        _inspector.add_child(spin)
        inputs[key] = spin
    var channel: OptionButton
    if link.kind == "control":
        _inspector.add_child(Look.label("Source channel", 12, Look.MUTED))
        channel = OptionButton.new()
        channel.add_item("Channel 1 (left)")
        channel.add_item("Channel 2 (right)")
        channel.selected = int(found.channel)
        _inspector.add_child(channel)
        var formula := Look.label("effective = base + source × depth + offset\nClamped to the parameter range.\nControl updates once per audio block.", 12, Look.MUTED)
        formula.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        _inspector.add_child(formula)
    _inspector.add_child(_button("Apply connection settings", func():
        var values: Dictionary = {}
        for key in inputs:
            values[key] = inputs[key].value
        if link.kind == "control":
            values.channel = channel.selected
        _stop_for_edit()
        if document.update_link(link, values):
            inspect_link(link)
            _set_status("Connection settings updated.")
        else:
            _set_status(document.last_error, true)
    ))
    _inspector.add_child(_button("Remove connection", func():
        _stop_for_edit()
        selected_link = {}
        if document.disconnect_link(link):
            _show_empty_inspector()
    ))

func _show_context(at_position: Vector2) -> void:
    _context_position = (at_position + graph.scroll_offset) / graph.zoom
    _context.clear()
    _context_types.clear()
    for kind in CATALOG:
        if document.definitions.has(kind):
            _context_types.append(kind)
            _context.add_item(CATALOG[kind][0], _context_types.size() - 1)
    _context.position = Vector2i(graph.get_screen_position() + at_position)
    _context.popup()

func add_processor(kind: String, position := Vector2.INF) -> String:
    if not _available:
        return ""
    _stop_for_edit()
    var point: Vector2 = (graph.scroll_offset + graph.size * 0.45) / graph.zoom if position == Vector2.INF else position
    var id := document.add_processor(kind, point)
    if id.is_empty():
        _set_status(document.last_error, true)
    else:
        inspect_node(id)
        _set_status("Added " + CATALOG[kind][0] + ". Drag its ports to connect it.")
    return id

func _delete_graph_nodes(names: Array[StringName]) -> void:
    var ids: Array = []
    for node_name in names:
        var node := graph.get_node_or_null(NodePath(node_name))
        if node != null:
            ids.append(node.dsp_id)
    remove_processors(ids)

func remove_processors(ids: Array) -> void:
    _stop_for_edit()
    selected_id = ""
    selected_link = {}
    if not document.remove_processors(ids):
        _set_status(document.last_error, true)
    else:
        _set_status("Processor removed. Its connections were removed too.")

func _stop_for_edit() -> void:
    _flush_parameter_history()
    topology_edit_requested.emit()
    if _playing:
        stop_preview()
        _set_status("Preview stopped for a wiring change. Press Preview to listen again.")

func _commit_history() -> void:
    if _available:
        document.commit_history()
        _update_chrome()

func _flush_parameter_history() -> void:
    if _parameter_timer != null and not _parameter_timer.is_stopped():
        _parameter_timer.stop()
        _commit_history()

func undo() -> void:
    _stop_for_edit()
    document.undo()

func redo() -> void:
    _stop_for_edit()
    document.redo()

func arrange() -> void:
    if not _available:
        return
    _flush_parameter_history()
    document.auto_arrange()
    call_deferred("fit_graph")

func fit_graph() -> void:
    if blocks.is_empty() or graph.size.x <= 0:
        return
    var bounds := Rect2()
    var first := true
    for block in blocks.values():
        var rect := Rect2(block.position_offset, block.size.max(block.get_combined_minimum_size()))
        bounds = rect if first else bounds.merge(rect)
        first = false
    bounds = bounds.grow(55)
    graph.zoom = clampf(minf((graph.size.x - 35) / maxf(bounds.size.x, 1), (graph.size.y - 60) / maxf(bounds.size.y, 1)), 0.25, 1.0)
    graph.scroll_offset = bounds.position * graph.zoom - (graph.size - bounds.size * graph.zoom) * 0.5
    _capture_view()

func _capture_view() -> void:
    document.view = {"zoom": graph.zoom, "scroll_x": clampf(graph.scroll_offset.x, -100000, 100000), "scroll_y": clampf(graph.scroll_offset.y, -100000, 100000)}

func _apply_view() -> void:
    var saved_view: Dictionary = document.view.duplicate()
    graph.zoom = saved_view.zoom
    graph.scroll_offset = Vector2(saved_view.scroll_x, saved_view.scroll_y)

func new_network(preset := "blank") -> void:
    if not _available:
        return
    _stop_for_edit()
    selected_id = ""
    selected_link = {}
    if document.new_document(preset):
        _startup_pending = false
        call_deferred("fit_graph")
        _set_status("Live input effect ready. Enable live input in Audio settings and use headphones." if preset == "live_input" else "New network. Add processors from the library and wire their ports.")
    else:
        _set_status(document.last_error, true)

func open_file(path: String) -> bool:
    if not _available:
        return false
    _stop_for_edit()
    selected_id = ""
    selected_link = {}
    if not document.load_file(path):
        _set_status(document.last_error, true)
        return false
    _startup_pending = false
    _clear_recovery()
    if document.current_path.is_empty():
        call_deferred("fit_graph")
    else:
        _apply_view()
    _update_chrome()
    _set_status("Opened " + path.get_file())
    return true

func save() -> void:
    if not _available:
        return
    _capture_view()
    _flush_parameter_history()
    if document.current_path.is_empty():
        save_as()
    elif document.save_file(document.current_path, true):
        _clear_recovery()
        _set_status("Saved " + document.current_path.get_file())
    else:
        _set_status(document.last_error, true)

func save_as() -> void:
    if not _available:
        return
    _capture_view()
    _flush_parameter_history()
    _save_dialog.current_file = document.current_path.get_file() if not document.current_path.is_empty() else "My effect.jucegraph"
    if not document.current_path.is_empty():
        _save_dialog.current_dir = ProjectSettings.globalize_path(document.current_path.get_base_dir())
    _save_dialog.popup_centered_ratio(0.75)

func _confirm_discard(action: Callable, exiting := false) -> void:
    _flush_parameter_history()
    if _available and document.is_dirty():
        _discard_action = action
        _pending_exit = exiting
        _discard.popup_centered()
    else:
        action.call()

func _show_audio_settings() -> void:
    if not _available:
        return
    var old_output := _output_menu.get_item_text(_output_menu.selected)
    var old_input := _input_menu.get_item_text(_input_menu.selected)
    _output_menu.clear()
    _input_menu.clear()
    _output_menu.add_item("Default output")
    _input_menu.add_item("Default input")
    for name in _device.get_output_devices():
        _output_menu.add_item(name)
        if name == old_output:
            _output_menu.selected = _output_menu.item_count - 1
    for name in _device.get_input_devices():
        _input_menu.add_item(name)
        if name == old_input:
            _input_menu.selected = _input_menu.item_count - 1
    _audio_dialog.popup_centered()

func start_preview() -> bool:
    if not _available:
        return false
    _flush_parameter_history()
    var output := "" if _output_menu.selected == 0 else _output_menu.get_item_text(_output_menu.selected)
    var input := "" if _input_menu.selected == 0 else _input_menu.get_item_text(_input_menu.selected)
    if not _device.set_network(document.network):
        _set_status(_device.get_last_error(), true)
        return false
    if not _device.start_audio(output, _rate_menu.get_selected_id(), _buffer_menu.get_selected_id(), input, _capture.button_pressed):
        _set_status(_device.get_last_error(), true)
        return false
    _playing = true
    _set_status("Preview running · " + str(_device.get_device_info().get("name", "JUCE output")))
    _update_chrome()
    return true

func stop_preview() -> void:
    if _device != null:
        _device.stop_audio()
    _playing = false
    if _status != null:
        _set_status("Preview stopped.")
        _update_chrome()

func get_network() -> RefCounted:
    return document.network

func _update_chrome() -> void:
    if _play == null:
        return
    _play.disabled = not _available or _playing
    _stop.disabled = not _playing
    _undo.disabled = not _available or not document.can_undo()
    _redo.disabled = not _available or not document.can_redo()
    _document_title.text = (document.current_path.get_file() if not document.current_path.is_empty() else "Untitled effect") + ("  *" if document.is_dirty() else "")
    if _available:
        _counts.text = "%d blocks  ·  %d audio  ·  %d control   " % [document.records.size(), document.network.get_connections().size(), document.network.get_modulation_connections().size()]

func _set_status(message: String, error := false) -> void:
    _status.text = message
    _status.tooltip_text = message
    _status.add_theme_color_override("font_color", Look.ERROR if error else Look.MUTED)

func _process(_delta: float) -> void:
    if _device == null or _meter == null:
        return
    var peak: float = _device.get_peak()
    _meter.value = minf(peak, 1.0)
    _peak_label.text = "%.1f dB" % linear_to_db(peak) if peak > 0.00001 else "−∞ dB"
    _peak_label.modulate = Look.ERROR if peak >= 0.999 else Look.AUDIO
    if _playing and not _device.is_running():
        _device.stop_audio()
        _playing = false
        _update_chrome()
        _set_status("Audio device stopped. Check Audio settings and restart Preview.", true)

func _unhandled_key_input(event: InputEvent) -> void:
    if not is_visible_in_tree() or not _available or not event is InputEventKey or not event.pressed or event.echo:
        return
    var focus := get_viewport().gui_get_focus_owner()
    if focus != null and focus != self and not is_ancestor_of(focus):
        return
    var command: bool = event.ctrl_pressed or event.meta_pressed
    if command and event.keycode == KEY_Z:
        redo() if event.shift_pressed else undo()
    elif command and event.keycode == KEY_Y:
        redo()
    elif command and event.keycode == KEY_S:
        if event.shift_pressed:
            save_as()
        else:
            save()
    elif command and event.keycode == KEY_O:
        _confirm_discard(func(): _open_dialog.popup_centered_ratio(0.75))
    else:
        return
    get_viewport().set_input_as_handled()

func recovery_enabled() -> bool:
    return enable_recovery and (not Engine.is_editor_hint() or bool(get_meta("plugin_host", false)))

func save_recovery() -> void:
    if not _available or _discard_exit or not recovery_enabled() or not document.is_dirty():
        return
    _capture_view()
    var path := "user://" + recovery_name
    var data := {"document": document.export_document(), "source_path": document.current_path}
    var text := JSON.stringify(data)
    if text == _last_recovery_text and FileAccess.file_exists(path):
        return
    if Document.write_json_file(path, data, true).is_empty():
        _last_recovery_text = text

func _recover() -> bool:
    var path := "user://" + recovery_name
    if not FileAccess.file_exists(path):
        return false
    var result: Dictionary = Document.read_json_file(path)
    if not result.ok or not result.data.get("document") is Dictionary:
        return false
    if not document.load_document(result.data.document):
        return false
    var source_path: Variant = result.data.get("source_path", "")
    document.current_path = source_path if source_path is String else ""
    _update_chrome()
    return true

func _clear_recovery() -> void:
    _last_recovery_text = ""
    if recovery_enabled():
        DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + recovery_name))

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST and manage_window_close and not Engine.is_editor_hint():
        _confirm_discard(func(): get_tree().quit(), true)

func _exit_tree() -> void:
    if _device != null:
        _device.stop_audio()
    save_recovery()
    if manage_window_close and not Engine.is_editor_hint() and get_tree() != null:
        get_tree().auto_accept_quit = _old_auto_quit

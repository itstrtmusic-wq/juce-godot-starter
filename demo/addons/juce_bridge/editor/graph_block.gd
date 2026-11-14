@tool
extends GraphNode

signal remove_requested(id: String)
const Look = preload("res://addons/juce_bridge/editor/graph_theme.gd")
var dsp_id := ""
var dsp_type := ""
var input_ports: Array = []
var output_ports: Array = []
var _value_labels: Dictionary = {}

func configure(info: Dictionary, display_title: String, accent: Color) -> void:
    dsp_id = info.id
    dsp_type = info.type
    title = display_title
    custom_minimum_size = Vector2(222, 0)
    resizable = false
    add_theme_stylebox_override("panel", Look.node_style(accent, false))
    add_theme_stylebox_override("panel_selected", Look.node_style(accent, true))
    add_theme_stylebox_override("titlebar", Look.box(Color("26354a"), Color.TRANSPARENT, 7, 10))
    add_theme_stylebox_override("titlebar_selected", Look.box(Color("304660"), accent, 7, 10))
    add_theme_font_size_override("title_font_size", 16)
    for child in get_titlebar_hbox().get_children(true):
        if child is Label:
            child.clip_text = true
            child.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            child.custom_minimum_size.x = 70
    var badge := Look.label(dsp_type.replace("_", " ").to_upper(), 10, accent)
    badge.tooltip_text = dsp_id
    get_titlebar_hbox().add_child(badge)
    if dsp_id not in ["input", "output"]:
        var close := Button.new()
        close.text = "×"
        close.flat = true
        close.focus_mode = Control.FOCUS_NONE
        close.tooltip_text = "Delete this processor"
        close.pressed.connect(func(): remove_requested.emit(dsp_id))
        get_titlebar_hbox().add_child(close)
    var has_input := dsp_type not in ["input", "oscillator", "constant", "lfo"]
    var has_output := dsp_type != "output"
    _row("Audio in" if has_input else "", "Audio out" if has_output else "", has_input, 0, has_output, 0)
    if has_input:
        input_ports.append({"kind": "audio"})
    if has_output:
        output_ports.append({"kind": "audio"})
        _row("", "Control out  ◇", false, 1, true, 1)
        output_ports.append({"kind": "control"})
    for parameter in info.parameters:
        if parameter == "waveform":
            continue
        var value: float = info.parameters[parameter].value
        var row := HBoxContainer.new()
        row.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.custom_minimum_size.y = 23
        var name_label := Look.label(parameter.replace("_", " ").capitalize(), 12, Look.CONTROL)
        name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(name_label)
        var value_label := Look.label(format_value(parameter, value), 12, Look.MUTED)
        value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
        row.add_child(value_label)
        _value_labels[parameter] = value_label
        add_child(row)
        set_slot(get_child_count() - 1, true, 1, Look.CONTROL, false, 0, Look.AUDIO)
        input_ports.append({"kind": "control", "parameter": parameter})
    if dsp_type in ["input", "output"]:
        var note := Look.label("Audio settings → enable input" if dsp_type == "input" else "JUCE audio device", 11, Look.MUTED)
        note.mouse_filter = Control.MOUSE_FILTER_IGNORE
        add_child(note)
    update_parameter("bypass", float(info.parameters.get("bypass", {}).get("value", 0)))

func _row(left: String, right: String, enable_left: bool, left_type: int, enable_right: bool, right_type: int) -> void:
    var row := HBoxContainer.new()
    row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.custom_minimum_size.y = 25
    var a := Look.label(left, 12, Look.AUDIO if left_type == 0 else Look.CONTROL)
    a.mouse_filter = Control.MOUSE_FILTER_IGNORE
    a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(a)
    var b := Look.label(right, 12, Look.AUDIO if right_type == 0 else Look.CONTROL)
    b.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(b)
    add_child(row)
    set_slot(get_child_count() - 1, enable_left, left_type, Look.AUDIO if left_type == 0 else Look.CONTROL, enable_right, right_type, Look.AUDIO if right_type == 0 else Look.CONTROL)

func update_parameter(parameter: String, value: float) -> void:
    if _value_labels.has(parameter):
        _value_labels[parameter].text = format_value(parameter, value)
    if parameter == "bypass":
        self_modulate = Color(1, 1, 1, 0.55 if value >= 0.5 else 1.0)

func input_for(parameter := "") -> int:
    for index in input_ports.size():
        if parameter.is_empty() and input_ports[index].kind == "audio":
            return index
        if not parameter.is_empty() and input_ports[index].get("parameter", "") == parameter:
            return index
    return -1

static func format_value(parameter: String, value: float) -> String:
    if parameter in ["bypass", "gate"]:
        return "On" if value >= 0.5 else "Off"
    if parameter.ends_with("db"):
        return "%.1f dB" % value
    if parameter.ends_with("ms"):
        return "%.1f ms" % value
    if parameter in ["frequency", "centre_frequency", "rate_hz"]:
        return "%.2f kHz" % (value / 1000) if value >= 1000 else "%.2f Hz" % value
    return "%.3f" % value

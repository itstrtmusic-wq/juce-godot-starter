extends VBoxContainer

signal channel_selected(index: int, open_piano: bool)
signal channel_changed(index: int, key: String, value: Variant)
signal step_changed(channel: int, step: int)
signal context_action(channel: int, action: int)
signal edit_started
signal edit_finished
const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
const Knob = preload("res://addons/juce_bridge/ui/daw_knob.gd")
const Steps = preload("res://addons/juce_bridge/ui/daw_steps.gd")
var project: RefCounted
var pattern_index := 0
var selected := 0
var _rows: VBoxContainer
var _widgets: Array[Dictionary] = []
var _count := -1
var _filter := 0

func _ready() -> void:
    var bar := HBoxContainer.new()
    add_child(bar)
    var filter := OptionButton.new()
    for name in ["All channels", "Drums", "Instruments"]:
        filter.add_item(name)
    filter.focus_mode = Control.FOCUS_NONE
    filter.item_selected.connect(func(index: int):
        _filter = index
        refresh()
    )
    bar.add_child(filter)
    bar.add_child(Look.label("PAN   VOL", 9, Look.MUTED))
    var fill := Control.new()
    fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bar.add_child(fill)
    bar.add_child(Look.label("1              2              3              4", 10, Look.MUTED))
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    _rows = VBoxContainer.new()
    _rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _rows.add_theme_constant_override("separation", 2)
    scroll.add_child(_rows)

func setup(value: RefCounted) -> void:
    project = value
    project.changed.connect(refresh)
    refresh()

func refresh() -> void:
    if _rows == null or project == null:
        return
    if _count != project.channels.size():
        for child in _rows.get_children():
            _rows.remove_child(child)
            child.queue_free()
        _widgets.clear()
        for index in project.channels.size():
            _add_row(index)
        _count = project.channels.size()
    pattern_index = clampi(pattern_index, 0, project.patterns.size() - 1)
    for index in _widgets.size():
        var data: Dictionary = project.channels[index]
        var row: Dictionary = _widgets[index]
        row.row.visible = _filter == 0 or (_filter == 1 and data.waveform >= 4) or (_filter == 2 and data.waveform < 4)
        row.name.text = data.name
        row.name.add_theme_color_override("font_color", Look.ORANGE if selected == index else Look.TEXT)
        row.led.add_theme_color_override("font_color", Look.MUTED if data.mute else Look.GREEN)
        row.pan.set_value_no_signal(data.pan)
        row.volume.set_value_no_signal(data.volume_db)
        row.steps.clip = project.patterns[pattern_index]
        row.steps.queue_redraw()

func _add_row(index: int) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 3)
    _rows.add_child(row)
    var led := Look.button("●", func(): channel_changed.emit(index, "mute", not project.channels[index].mute), "Mute / enable channel")
    led.custom_minimum_size.x = 22
    row.add_child(led)
    var pan = Knob.new()
    pan.minimum = -1
    pan.maximum = 1
    pan.default_value = 0
    pan.value_changed.connect(func(value: float): channel_changed.emit(index, "pan", value))
    pan.drag_started.connect(func(): edit_started.emit())
    pan.drag_finished.connect(func(): edit_finished.emit())
    row.add_child(pan)
    var volume = Knob.new()
    volume.minimum = -60
    volume.maximum = 6
    volume.default_value = 0
    volume.suffix = " dB"
    volume.value_changed.connect(func(value: float): channel_changed.emit(index, "volume_db", value))
    volume.drag_started.connect(func(): edit_started.emit())
    volume.drag_finished.connect(func(): edit_finished.emit())
    row.add_child(volume)
    var name := Look.button("Channel", func(): channel_selected.emit(index, false))
    name.custom_minimum_size.x = 112
    name.clip_text = true
    name.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
            channel_selected.emit(index, true)
    )
    row.add_child(name)
    row.add_child(Look.label("%02d" % (index + 1), 10, Look.MUTED))
    var steps = Steps.new()
    steps.channel = index + 1
    steps.step_clicked.connect(func(step: int): step_changed.emit(index, step))
    row.add_child(steps)
    var menu := MenuButton.new()
    menu.text = "⋮"
    menu.focus_mode = Control.FOCUS_NONE
    var popup := menu.get_popup()
    for text in ["Piano roll", "Instrument settings", "Fill each step", "Fill each 2 steps", "Fill each 4 steps", "Clear first bar"]:
        popup.add_item(text)
    popup.id_pressed.connect(func(action: int): context_action.emit(index, action))
    row.add_child(menu)
    _widgets.append({"row": row, "led": led, "pan": pan, "volume": volume, "name": name, "steps": steps})

func update_beat(beat: float) -> void:
    for row in _widgets:
        if floori(row.steps.beat * 4) != floori(beat * 4):
            row.steps.beat = beat
            row.steps.queue_redraw()

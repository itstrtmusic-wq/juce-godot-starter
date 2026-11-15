extends HBoxContainer

signal channel_selected(index: int)
signal channel_changed(index: int, key: String, value: Variant)
signal master_changed(value: float)
signal edit_started
signal edit_finished
const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
const Knob = preload("res://addons/juce_bridge/ui/daw_knob.gd")
var project: RefCounted
var selected := -1
var _strips: HBoxContainer
var _widgets: Array[Dictionary] = []
var _master: Dictionary
var _count := -1

func _ready() -> void:
    _master = _strip(-1, self)
    var scroll := ScrollContainer.new()
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    add_child(scroll)
    _strips = HBoxContainer.new()
    _strips.add_theme_constant_override("separation", 2)
    _strips.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.add_child(_strips)

func setup(value: RefCounted) -> void:
    project = value
    project.changed.connect(refresh)
    refresh()

func _strip(index: int, parent: Node) -> Dictionary:
    var panel := PanelContainer.new()
    panel.custom_minimum_size.x = 47
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    parent.add_child(panel)
    var column := VBoxContainer.new()
    column.add_theme_constant_override("separation", 2)
    panel.add_child(column)
    var select := Look.button("M" if index < 0 else str(index + 1), func():
        selected = index
        channel_selected.emit(index)
        refresh()
    )
    column.add_child(select)
    var name := Look.label("MASTER" if index < 0 else "Insert", 9)
    name.custom_minimum_size.x = 36
    name.clip_text = true
    column.add_child(name)
    var pan: Control
    if index >= 0:
        pan = Knob.new()
        pan.minimum = -1
        pan.maximum = 1
        pan.default_value = 0
        pan.value_changed.connect(func(value: float): channel_changed.emit(index, "pan", value))
        pan.drag_started.connect(func(): edit_started.emit())
        pan.drag_finished.connect(func(): edit_finished.emit())
        column.add_child(pan)
    else:
        var space := Control.new()
        space.custom_minimum_size.y = 28
        column.add_child(space)
    var levels := HBoxContainer.new()
    levels.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(levels)
    var slider := VSlider.new()
    slider.min_value = -60
    slider.max_value = 0 if index < 0 else 6
    slider.step = 0.1
    slider.focus_mode = Control.FOCUS_NONE
    slider.size_flags_vertical = Control.SIZE_EXPAND_FILL
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size.y = 95
    slider.drag_started.connect(func(): edit_started.emit())
    slider.drag_ended.connect(func(_changed: bool): edit_finished.emit())
    slider.value_changed.connect(func(value: float):
        if index < 0:
            master_changed.emit(value)
        else:
            channel_changed.emit(index, "volume_db", value)
    )
    levels.add_child(slider)
    var meter := ProgressBar.new()
    meter.max_value = 1
    meter.show_percentage = false
    meter.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
    meter.custom_minimum_size.x = 7
    meter.size_flags_vertical = Control.SIZE_EXPAND_FILL
    levels.add_child(meter)
    var value_label := Look.label("0.0", 9, Look.MUTED)
    column.add_child(value_label)
    var buttons := HBoxContainer.new()
    column.add_child(buttons)
    var mute: Button
    var solo: Button
    if index >= 0:
        mute = Look.button("M", func(): channel_changed.emit(index, "mute", not project.channels[index].mute), "Mute")
        solo = Look.button("S", func(): channel_changed.emit(index, "solo", not project.channels[index].solo), "Solo")
        mute.toggle_mode = true
        solo.toggle_mode = true
        buttons.add_child(mute)
        buttons.add_child(solo)
    return {"panel": panel, "name": name, "select": select, "pan": pan, "slider": slider, "meter": meter, "value": value_label, "mute": mute, "solo": solo}

func refresh() -> void:
    if project == null or _strips == null:
        return
    if _count != project.channels.size():
        for child in _strips.get_children():
            _strips.remove_child(child)
            child.queue_free()
        _widgets.clear()
        for i in project.channels.size():
            _widgets.append(_strip(i, _strips))
        _count = project.channels.size()
    _master.slider.set_value_no_signal(project.master_db)
    _master.value.text = "%.1f" % project.master_db
    for i in _widgets.size():
        var strip: Dictionary = _widgets[i]
        var data: Dictionary = project.channels[i]
        strip.name.text = data.name
        strip.name.tooltip_text = data.name
        strip.pan.set_value_no_signal(data.pan)
        strip.slider.set_value_no_signal(data.volume_db)
        strip.value.text = "%.1f" % data.volume_db
        strip.mute.set_pressed_no_signal(data.mute)
        strip.solo.set_pressed_no_signal(data.solo)
        strip.select.add_theme_color_override("font_color", Look.ORANGE if selected == i else Look.TEXT)

func update_meters(peaks: PackedFloat32Array, master: float, delta: float) -> void:
    _master.meter.value = maxf(master, _master.meter.value - delta * 1.8)
    for i in _widgets.size():
        var value: float = peaks[i] if i < peaks.size() else 0.0
        _widgets[i].meter.value = maxf(value, _widgets[i].meter.value - delta * 1.8)

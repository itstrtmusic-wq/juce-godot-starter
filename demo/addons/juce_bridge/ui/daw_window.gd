extends Panel

signal open_changed(open: bool)
const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
var caption := "Editor"
var body: VBoxContainer
var _caption: Label
var _header: HBoxContainer
var _moving := false
var _resizing := false
var _anchor := Vector2.ZERO
var _original := Rect2()
var _restored := Rect2()
var _maximized := false

func _ready() -> void:
    custom_minimum_size = Vector2(300, 160)
    clip_contents = true
    add_theme_stylebox_override("panel", Look.box(Look.PANEL))
    var column := VBoxContainer.new()
    column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    column.offset_left = 4
    column.offset_right = -4
    column.offset_top = 3
    column.offset_bottom = -3
    column.add_theme_constant_override("separation", 0)
    add_child(column)
    var header := HBoxContainer.new()
    _header = header
    header.custom_minimum_size.y = 26
    header.mouse_filter = Control.MOUSE_FILTER_STOP
    header.gui_input.connect(_header_input)
    column.add_child(header)
    header.add_child(Look.label("▸", 13, Look.ORANGE))
    _caption = Look.label(caption, 12)
    _caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
    header.add_child(_caption)
    header.add_child(Look.button("□", toggle_maximize, "Maximize / restore"))
    header.add_child(Look.button("×", func(): set_open(false), "Close this panel"))
    body = VBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 4)
    column.add_child(body)
    var grip := Control.new()
    grip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
    grip.position = Vector2(-14, -14)
    grip.size = Vector2(14, 14)
    grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
    grip.gui_input.connect(func(event: InputEvent):
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            _resizing = true
            _anchor = get_parent().get_global_transform_with_canvas().affine_inverse() * (grip.get_global_transform_with_canvas() * event.position)
            _original = Rect2(position, size)
            move_to_front()
            grip.accept_event()
    )
    add_child(grip)
    get_parent().resized.connect(func():
        if _maximized:
            position = Vector2.ZERO
            size = get_parent().size
    )

func set_caption(text: String) -> void:
    caption = text
    if _caption != null:
        _caption.text = text

func set_open(enabled: bool) -> void:
    visible = enabled
    if enabled:
        move_to_front()
    open_changed.emit(enabled)

func toggle_maximize() -> void:
    if _maximized:
        position = _restored.position
        size = _restored.size
    else:
        _restored = Rect2(position, size)
        position = Vector2.ZERO
        size = get_parent().size
    _maximized = not _maximized
    move_to_front()

func _header_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        move_to_front()
        if event.double_click:
            toggle_maximize()
        elif not _maximized:
            _moving = true
            _anchor = get_parent().get_global_transform_with_canvas().affine_inverse() * (_header.get_global_transform_with_canvas() * event.position)
            _original = Rect2(position, size)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and (_moving or _resizing):
        var point: Vector2 = get_parent().get_global_transform_with_canvas().affine_inverse() * event.position
        if _moving:
            position = _original.position + point - _anchor
            position.x = clampf(position.x, 0, maxf(0, get_parent().size.x - 120))
            position.y = clampf(position.y, 0, maxf(0, get_parent().size.y - 30))
        else:
            size = (_original.size + point - _anchor).max(get_combined_minimum_size())
    elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _moving = false
        _resizing = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _moving = false
        _resizing = false

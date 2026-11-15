extends Control

signal value_changed(value: float)
signal drag_started
signal drag_finished
var minimum := 0.0
var maximum := 1.0
var default_value := 0.5
var suffix := ""
var value := 0.5
var accent := Color("b7c4c8")
var _dragging := false

func _ready() -> void:
    custom_minimum_size = Vector2(28, 28)
    mouse_default_cursor_shape = Control.CURSOR_VSIZE
    mouse_filter = Control.MOUSE_FILTER_STOP

func set_value_no_signal(next: float) -> void:
    value = clampf(next, minimum, maximum)
    tooltip_text = "%.2f%s · Drag vertically; Shift for fine control; double-click resets" % [value, suffix]
    queue_redraw()

func _change(next: float) -> void:
    set_value_no_signal(next)
    value_changed.emit(value)

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            drag_started.emit()
            if event.double_click:
                _change(default_value)
                drag_finished.emit()
            else:
                _dragging = true
        elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
            drag_started.emit()
            _change(value + (maximum - minimum) / 100.0 * (-1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1))
            drag_finished.emit()
        accept_event()

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and _dragging:
        _change(value - event.relative.y * (maximum - minimum) / 160.0 * (0.15 if event.shift_pressed else 1.0))
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _dragging:
        _dragging = false
        drag_finished.emit()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _dragging:
        _dragging = false
        drag_finished.emit()

func _draw() -> void:
    var center := size * 0.5
    var radius := minf(size.x, size.y) * 0.34
    draw_circle(center + Vector2(0, 1), radius + 2, Color("232a2d"))
    draw_circle(center, radius, Color("626d73"))
    var amount := inverse_lerp(minimum, maximum, value) if maximum > minimum else 0.0
    var angle := lerpf(PI * 0.75, PI * 2.25, amount)
    draw_arc(center, radius + 2, PI * 0.75, angle, 28, accent, 2, true)
    draw_line(center, center + Vector2(cos(angle), sin(angle)) * radius * 0.75, Color("e2e8e9"), 2, true)

extends Control
## Reusable single-clip editor. The document owns edits; the native engine owns time.

signal edit_requested
signal selection_changed(id: int)
const Piano = preload("res://addons/juce_bridge/ui/midi_keyboard.gd")
const LEFT := 60.0
const TOP := 30.0
const ROW := 18.0
const TEAL := Color("41d6b0")
var document: RefCounted
var grid := 0.25
var beat_width := 48.0
var playhead := -1.0
var selected := -1
var editable := true
var _horizontal: HScrollBar
var _vertical: VScrollBar
var _drag: Dictionary = {}
var _original: Dictionary = {}
var _anchor := Vector2.ZERO
var _kind := ""
var _panning := false
var _pan_origin := Vector2.ZERO

func _ready() -> void:
    custom_minimum_size = Vector2(630, 230)
    clip_contents = true
    focus_mode = Control.FOCUS_ALL
    _horizontal = HScrollBar.new()
    _horizontal.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _horizontal.offset_left = LEFT
    _horizontal.offset_right = -16
    _horizontal.offset_top = -16
    _horizontal.value_changed.connect(func(_value: float): queue_redraw())
    add_child(_horizontal)
    _vertical = VScrollBar.new()
    _vertical.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    _vertical.offset_top = TOP
    _vertical.offset_left = -16
    _vertical.offset_bottom = -16
    _vertical.value_changed.connect(func(_value: float): queue_redraw())
    add_child(_vertical)
    resized.connect(_layout_scrollbars)
    _layout_scrollbars()
    _vertical.value = (127 - 72) * ROW

func set_document(value: RefCounted) -> void:
    if document != null and document.changed.is_connected(_on_changed):
        document.changed.disconnect(_on_changed)
    document = value
    document.changed.connect(_on_changed)
    _on_changed()

func _on_changed() -> void:
    if selected >= 0 and document.find_note(selected).is_empty():
        selected = -1
        selection_changed.emit(-1)
    _layout_scrollbars()
    queue_redraw()

func _layout_scrollbars() -> void:
    if _horizontal == null:
        return
    _horizontal.max_value = (document.length_beats if document != null else 16.0) * beat_width
    _horizontal.page = maxf(1, size.x - LEFT - 16)
    _vertical.max_value = 128 * ROW
    _vertical.page = maxf(1, size.y - TOP - 16)
    queue_redraw()

func fit_clip() -> void:
    if document != null:
        beat_width = clampf((size.x - LEFT - 16) / document.length_beats, 16, 160)
        _layout_scrollbars()
        _horizontal.value = 0

func zoom(factor: float) -> void:
    var beat := _horizontal.value / beat_width
    beat_width = clampf(beat_width * factor, 16, 160)
    _layout_scrollbars()
    _horizontal.value = beat * beat_width

func set_playhead(beat: float) -> void:
    playhead = beat
    queue_redraw()

func _area() -> Rect2:
    return Rect2(LEFT, TOP, maxf(0, size.x - LEFT - 16), maxf(0, size.y - TOP - 16))

func note_rect(note: Dictionary) -> Rect2:
    return Rect2(LEFT + note.start * beat_width - _horizontal.value,
        TOP + (127 - int(note.note)) * ROW - _vertical.value,
        maxf(3, note.length * beat_width), ROW - 2)

func _at(point: Vector2) -> Dictionary:
    if not _area().has_point(point) or document == null:
        return {}
    for index in range(document.notes.size() - 1, -1, -1):
        var note: Dictionary = document.notes[index]
        if note_rect(note).has_point(point):
            return note.duplicate()
    return {}

func _beat_at(point: Vector2) -> float:
    return (point.x - LEFT + _horizontal.value) / beat_width

func _pitch_at(point: Vector2) -> int:
    return clampi(127 - floori((point.y - TOP + _vertical.value) / ROW), 0, 127)

func _gui_input(event: InputEvent) -> void:
    if document == null:
        return
    if event is InputEventMouseButton:
        if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
            var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
            if event.ctrl_pressed:
                zoom(1.2 if direction < 0 else 1.0 / 1.2)
            elif event.shift_pressed:
                _horizontal.value += direction * 64
            else:
                _vertical.value += direction * ROW * 3
            accept_event()
            return
        if event.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = event.pressed
            _anchor = event.position
            _pan_origin = Vector2(_horizontal.value, _vertical.value)
            accept_event()
            return
        if not event.pressed or not _area().has_point(event.position) or not editable:
            return
        grab_focus()
        var hit := _at(event.position)
        if event.button_index == MOUSE_BUTTON_RIGHT:
            if not hit.is_empty():
                edit_requested.emit()
                document.remove_note(hit.id)
            accept_event()
        elif event.button_index == MOUSE_BUTTON_LEFT:
            edit_requested.emit()
            _anchor = event.position
            if hit.is_empty():
                selected = -1
                var start := clampf(floorf(_beat_at(event.position) / grid) * grid, 0, document.length_beats - grid)
                _drag = {"id": -1, "note": _pitch_at(event.position), "start": start,
                    "length": minf(grid, document.length_beats - start), "velocity": 0.8, "channel": 1}
                _kind = "create"
            else:
                selected = hit.id
                _drag = hit.duplicate()
                var bounds := note_rect(hit)
                _kind = "resize" if event.position.x >= bounds.end.x - minf(8, bounds.size.x * 0.3) else "move"
            _original = _drag.duplicate()
            selection_changed.emit(selected)
            queue_redraw()
            accept_event()
    elif event is InputEventMouseMotion:
        if _panning:
            var delta: Vector2 = event.position - _anchor
            _horizontal.value = _pan_origin.x - delta.x
            _vertical.value = _pan_origin.y - delta.y
        elif _drag.is_empty():
            var hit := _at(event.position)
            mouse_default_cursor_shape = Control.CURSOR_ARROW if hit.is_empty() else (
                Control.CURSOR_HSIZE if event.position.x >= note_rect(hit).end.x - minf(8, note_rect(hit).size.x * 0.3) else Control.CURSOR_MOVE)

func _input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and not _drag.is_empty():
        var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
        if _kind == "move":
            _drag.start = clampf(snappedf(_original.start + (point.x - _anchor.x) / beat_width, grid), 0, document.length_beats - _original.length)
            _drag.note = clampi(int(_original.note) - roundi((point.y - _anchor.y) / ROW), 0, 127)
        else:
            var end := snappedf(_beat_at(point), grid)
            _drag.length = clampf(end - _drag.start, minf(grid, document.length_beats - _drag.start), document.length_beats - _drag.start)
        queue_redraw()
    elif event is InputEventMouseButton and not event.pressed:
        if event.button_index == MOUSE_BUTTON_MIDDLE:
            _panning = false
        if event.button_index == MOUSE_BUTTON_LEFT and not _drag.is_empty():
            if _kind == "create":
                selected = document.add_note(_drag.note, _drag.start, _drag.length, _drag.velocity)
            else:
                document.update_note(selected, _drag.note, _drag.start, _drag.length, _drag.velocity)
            _drag.clear()
            selection_changed.emit(selected)
            queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE and has_focus() and editable:
        if selected >= 0:
            edit_requested.emit()
            document.remove_note(selected)
        get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _drag.clear()
        _panning = false
        queue_redraw()

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("111a27"))
    if _horizontal == null or document == null:
        return
    var area := _area()
    var font := get_theme_default_font()
    for pitch in range(128):
        var y := TOP + (127 - pitch) * ROW - _vertical.value
        var row := Rect2(LEFT, y, area.size.x, ROW).intersection(area)
        if not row.has_area():
            continue
        var black: bool = pitch % 12 in [1, 3, 6, 8, 10]
        draw_rect(row, Color("141f2d") if black else Color("192635"))
        var key := Rect2(0, y, LEFT - 1, ROW - 1).intersection(Rect2(0, TOP, LEFT, area.size.y))
        draw_rect(key, Color("263448") if black else Color("cad3df"))
        draw_string(font, Vector2(4, y + 13), Piano.note_name(pitch), HORIZONTAL_ALIGNMENT_LEFT, LEFT - 8, 10,
            Color("c3cfdf") if black else Color("233044"))
    var first := maxi(0, floori(_horizontal.value / beat_width / grid))
    var last := mini(ceili(document.length_beats / grid), ceili((_horizontal.value + area.size.x) / beat_width / grid))
    for index in range(first, last + 1):
        var beat := index * grid
        var x := LEFT + beat * beat_width - _horizontal.value
        var strong := is_zero_approx(fposmod(beat, 4))
        draw_line(Vector2(x, TOP), Vector2(x, area.end.y), Color("40556c") if strong else Color("26384b"))
    for note in document.notes:
        if _drag.is_empty() or note.id != selected:
            _draw_note(note, area, font, note.id == selected)
    if not _drag.is_empty():
        _draw_note(_drag, area, font, true)
    if playhead >= 0:
        var x := LEFT + playhead * beat_width - _horizontal.value
        if x >= LEFT and x <= area.end.x:
            draw_line(Vector2(x, TOP), Vector2(x, area.end.y), Color("ffcb72"), 2)
    # Draw the ruler last so scrolling notes never cover it.
    draw_rect(Rect2(0, 0, size.x, TOP), Color("0c131e"))
    for beat in range(ceili(document.length_beats) + 1):
        var x := LEFT + beat * beat_width - _horizontal.value
        if x >= LEFT and x <= area.end.x:
            draw_string(font, Vector2(x + 4, 20), "%d" % (beat / 4 + 1) if beat % 4 == 0 else "·",
                HORIZONTAL_ALIGNMENT_LEFT, 50, 12, Color("b0bfd1"))
    draw_string(font, Vector2(5, 20), "4 / 4", HORIZONTAL_ALIGNMENT_LEFT, 48, 11, Color("8a9bb0"))

func _draw_note(note: Dictionary, area: Rect2, font: Font, is_selected: bool) -> void:
    var rect := note_rect(note).intersection(area)
    if not rect.has_area():
        return
    draw_rect(rect, TEAL.lightened(0.2) if is_selected else TEAL.darkened(0.2))
    if is_selected:
        draw_rect(rect, Color("e0fff6"), false, 1)
    draw_rect(Rect2(rect.position, Vector2(rect.size.x * float(note.velocity), 2)), Color("e0fff6"))
    if rect.size.x > 30:
        draw_string(font, rect.position + Vector2(4, 12), Piano.note_name(note.note),
            HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 10, Color("102e2b"))

extends Control

signal edit_requested
signal pattern_opened(index: int)
signal track_mute_requested(index: int)
const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
const LEFT := 106.0
const TOP := 28.0
const LANE := 39.0
var project: RefCounted
var selected_pattern := 0
var selected_clip := -1
var playhead := -1.0
var beat_width := 32.0
var grid := 1.0
var _scroll: HScrollBar
var _vertical: VScrollBar
var _drag: Dictionary = {}
var _origin: Dictionary = {}
var _anchor := Vector2.ZERO
var _kind := "move"

func _ready() -> void:
    custom_minimum_size = Vector2(600, 230)
    clip_contents = true
    focus_mode = Control.FOCUS_ALL
    _scroll = HScrollBar.new()
    _scroll.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
    _scroll.offset_left = LEFT
    _scroll.offset_right = -14
    _scroll.offset_top = -14
    _scroll.value_changed.connect(func(_value: float): queue_redraw())
    add_child(_scroll)
    _vertical = VScrollBar.new()
    _vertical.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
    _vertical.offset_top = TOP
    _vertical.offset_left = -14
    _vertical.offset_bottom = -14
    _vertical.value_changed.connect(func(_value: float): queue_redraw())
    add_child(_vertical)
    resized.connect(_layout)
    _layout()

func setup(value: RefCounted) -> void:
    project = value
    project.changed.connect(_layout)
    _layout()

func _layout() -> void:
    if _scroll != null and project != null:
        _scroll.max_value = project.song_length * beat_width
        _scroll.page = maxf(1, size.x - LEFT - 14)
        _vertical.max_value = 8 * LANE
        _vertical.page = maxf(1, size.y - TOP - 14)
    queue_redraw()

func fit_song() -> void:
    beat_width = clampf((size.x - LEFT - 14) / project.song_length, 12, 100)
    _layout()
    _scroll.value = 0

func _area() -> Rect2:
    return Rect2(LEFT, TOP, maxf(0, size.x - LEFT - 14), maxf(0, size.y - TOP - 14))

func clip_rect(item: Dictionary) -> Rect2:
    return Rect2(LEFT + item.start * beat_width - _scroll.value,
        TOP + item.track * LANE - _vertical.value + 2, item.length * beat_width, LANE - 4)

func _hit(point: Vector2) -> Dictionary:
    if not _area().has_point(point):
        return {}
    for i in range(project.placements.size() - 1, -1, -1):
        if clip_rect(project.placements[i]).has_point(point):
            return project.placements[i].duplicate()
    return {}

func _start_at(point: Vector2) -> float:
    return snappedf((point.x - LEFT + _scroll.value) / beat_width, grid)

func _track_at(point: Vector2) -> int:
    return clampi(floori((point.y - TOP + _vertical.value) / LANE), 0, 7)

func _gui_input(event: InputEvent) -> void:
    if project == null or not event is InputEventMouseButton or not event.pressed:
        return
    if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
        var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1
        if event.ctrl_pressed:
            beat_width = clampf(beat_width * (0.85 if direction > 0 else 1.18), 12, 100)
        elif event.shift_pressed:
            _scroll.value += direction * 64
        else:
            _vertical.value += direction * LANE
        _layout()
        accept_event()
        return
    if event.position.x < LEFT and event.position.y > TOP:
        track_mute_requested.emit(_track_at(event.position))
        accept_event()
        return
    if not _area().has_point(event.position):
        return
    grab_focus()
    var item := _hit(event.position)
    if event.button_index == MOUSE_BUTTON_RIGHT:
        if not item.is_empty():
            edit_requested.emit()
            project.remove_placement(item.id)
    elif event.button_index == MOUSE_BUTTON_LEFT:
        if event.double_click and not item.is_empty():
            pattern_opened.emit(item.pattern)
        elif item.is_empty():
            edit_requested.emit()
            selected_clip = project.add_placement(selected_pattern, maxf(0, _start_at(event.position)), _track_at(event.position))
        else:
            edit_requested.emit()
            selected_clip = item.id
            _drag = item.duplicate()
            _origin = item.duplicate()
            _anchor = event.position
            _kind = "resize" if event.position.x >= clip_rect(item).end.x - 8 else "move"
    queue_redraw()
    accept_event()

func _input(event: InputEvent) -> void:
    if _drag.is_empty():
        return
    if event is InputEventMouseMotion:
        var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
        if _kind == "resize":
            _drag.length = clampf(_start_at(point) - _drag.start, grid, project.song_length - _drag.start)
        else:
            _drag.start = clampf(snappedf(_origin.start + (point.x - _anchor.x) / beat_width, grid), 0, project.song_length - _drag.length)
            _drag.track = _track_at(point)
        queue_redraw()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        project.change_placement(_drag.id, _drag.start, _drag.track, _drag.length)
        _drag.clear()
        queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
    if has_focus() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_DELETE:
        edit_requested.emit()
        project.remove_placement(selected_clip)
        get_viewport().set_input_as_handled()

func _can_drop_data(point: Vector2, data: Variant) -> bool:
    return _area().has_point(point) and data is Dictionary and data.get("kind") == "pattern" \
        and data.get("index") is int and data.index >= 0 and data.index < project.patterns.size()

func _drop_data(point: Vector2, data: Variant) -> void:
    edit_requested.emit()
    selected_clip = project.add_placement(data.index, maxf(0, _start_at(point)), _track_at(point))

func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color("2d3539"))
    if project == null or _scroll == null:
        return
    var area := _area()
    var font := get_theme_default_font()
    for track in 8:
        var y := TOP + track * LANE - _vertical.value
        var row := Rect2(LEFT, y, area.size.x, LANE - 1).intersection(area)
        if not row.has_area():
            continue
        draw_rect(row, Color("343e43") if track % 2 == 0 else Color("30393e"))
        draw_rect(Rect2(0, maxf(TOP, y), LEFT - 1, minf(LANE - 1, area.end.y - maxf(TOP, y))), Color("454f55"))
        draw_circle(Vector2(12, y + 16), 3, Color("697277") if project.tracks[track].mute else Look.GREEN)
        draw_string(font, Vector2(23, y + 20), project.tracks[track].name, HORIZONTAL_ALIGNMENT_LEFT, LEFT - 27, 11, Look.TEXT)
    for beat in range(ceili(project.song_length) + 1):
        var x := LEFT + beat * beat_width - _scroll.value
        if x >= LEFT and x <= area.end.x:
            draw_line(Vector2(x, TOP), Vector2(x, area.end.y), Color("556168") if beat % 4 == 0 else Color("3b474d"))
    for item in project.placements:
        if _drag.is_empty() or item.id != _drag.id:
            _draw_clip(item, area, font)
    if not _drag.is_empty():
        _draw_clip(_drag, area, font)
    if playhead >= 0:
        var x := LEFT + playhead * beat_width - _scroll.value
        if x >= LEFT and x <= area.end.x:
            draw_line(Vector2(x, TOP), Vector2(x, area.end.y), Look.ORANGE, 2)
    draw_rect(Rect2(0, 0, size.x, TOP), Color("465159"))
    for bar in ceili(project.song_length / 4):
        var x := LEFT + bar * 4 * beat_width - _scroll.value
        if x >= LEFT and x <= area.end.x:
            draw_string(font, Vector2(x + 4, 19), str(bar + 1), HORIZONTAL_ALIGNMENT_LEFT, 32, 11, Look.TEXT)

func _draw_clip(item: Dictionary, area: Rect2, font: Font) -> void:
    var rect := clip_rect(item).intersection(area)
    if not rect.has_area():
        return
    var color := Color.from_string(project.colors[item.pattern], Color("8ca8a0"))
    draw_rect(rect, color.darkened(0.42))
    draw_rect(Rect2(rect.position, Vector2(rect.size.x, 13)), color.darkened(0.12))
    draw_string(font, rect.position + Vector2(4, 11), project.names[item.pattern], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 6, 10, Color("e4e8e8"))
    if item.id == selected_clip:
        draw_rect(rect, Look.ORANGE, false, 1)
    var clip: RefCounted = project.patterns[item.pattern]
    for repeat in ceili(item.length / clip.length_beats):
        for note in clip.notes:
            var start: float = note.start + repeat * clip.length_beats
            if start >= item.length:
                continue
            var x := clip_rect(item).position.x + start * beat_width
            var y := rect.position.y + 17 + fposmod(127 - note.note, 12) * 0.9
            if x >= rect.position.x and x <= rect.end.x:
                draw_line(Vector2(x, y), Vector2(minf(rect.end.x, x + maxf(2, minf(note.length, item.length - start) * beat_width)), y), color.lightened(0.3), 1)

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        _drag.clear()

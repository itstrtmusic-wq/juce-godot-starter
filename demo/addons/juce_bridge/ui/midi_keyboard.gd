extends Control
## Reusable piano controller. Emits MIDI values; it does not open an audio device.

signal midi_message(message: JuceMidiMessage)
signal note_on(note: int, velocity: float)
signal note_off(note: int)
signal sustain_changed(enabled: bool)
signal octave_changed(octave: int)

# Physical US-QWERTY positions, in semitones above base_note.
const DEFAULT_MAPPING := {
    KEY_Z: 0, KEY_S: 1, KEY_X: 2, KEY_D: 3, KEY_C: 4, KEY_V: 5,
    KEY_G: 6, KEY_B: 7, KEY_H: 8, KEY_N: 9, KEY_J: 10, KEY_M: 11,
    KEY_Q: 12, KEY_2: 13, KEY_W: 14, KEY_3: 15, KEY_E: 16, KEY_R: 17,
    KEY_5: 18, KEY_T: 19, KEY_6: 20, KEY_Y: 21, KEY_7: 22, KEY_U: 23,
    KEY_I: 24, KEY_9: 25, KEY_O: 26, KEY_0: 27, KEY_P: 28,
    KEY_COMMA: 12, KEY_L: 13, KEY_PERIOD: 14, KEY_SEMICOLON: 15, KEY_SLASH: 16,
}
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
const TEAL := Color("41d6b0")
const DISPLAY_NOTES := 36

@export_range(0, 84, 12) var base_note := 60:
    set(value):
        var snapped := clampi(value, 0, 84)
        snapped -= snapped % 12
        if snapped == base_note:
            return
        if is_node_ready():
            all_notes_off()
        base_note = snapped
        queue_redraw()
        octave_changed.emit(floori(base_note / 12.0) - 1)

@export_range(1, 16) var midi_channel := 1:
    set(value):
        if value == midi_channel:
            return
        if is_node_ready():
            all_notes_off()
        midi_channel = clampi(value, 1, 16)

@export_range(1, 127) var velocity := 100
@export var typing_enabled := true:
    set(value):
        if typing_enabled == value:
            return
        if is_node_ready():
            all_notes_off()
        typing_enabled = value

var _mapping := DEFAULT_MAPPING.duplicate()
var _sources: Dictionary = {} # Source token -> original note (independent of transpose).
var _notes: Dictionary = {} # Note -> set of sources holding it.
var _sustained: Dictionary = {}
var _held_keys: Dictionary = {}
var _sustain := false
var _space_down := false
var _mouse_down := false
var _hover_note := -1
var _rects: Dictionary = {}

func _ready() -> void:
    custom_minimum_size = Vector2(630, 220)
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    resized.connect(queue_redraw)
    mouse_exited.connect(func():
        _hover_note = -1
        queue_redraw()
    )
    visibility_changed.connect(func():
        if not is_visible_in_tree():
            all_notes_off()
    )

static func note_name(note: int) -> String:
    return "%s%d" % [NOTE_NAMES[posmod(note, 12)], floori(note / 12.0) - 1]

func get_key_mapping() -> Dictionary:
    return _mapping.duplicate()

func set_key_mapping(mapping: Dictionary) -> bool:
    for key in mapping:
        if typeof(key) != TYPE_INT or typeof(mapping[key]) != TYPE_INT:
            return false
        if key <= 0 or mapping[key] < 0 or mapping[key] >= DISPLAY_NOTES:
            return false
        if key in [KEY_SPACE, KEY_ESCAPE, KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
            return false # Reserved controller shortcuts.
    all_notes_off()
    _mapping = mapping.duplicate()
    queue_redraw()
    return true

func press_note(note: int, strength := 1.0, source := "external") -> void:
    if note < 0 or note > 127 or not is_finite(strength) or strength <= 0.0:
        return
    if _sources.get(source, -1) == note:
        return
    release_source(source)
    _sources[source] = note
    if not _notes.has(note):
        _notes[note] = {}
    var first: bool = _notes[note].is_empty()
    _notes[note][source] = true
    _sustained.erase(note)
    if first:
        strength = clampf(strength, 1.0 / 127.0, 1.0)
        note_on.emit(note, strength)
        midi_message.emit(JuceMidiMessage.note_on(midi_channel, note, strength))
    queue_redraw()

func release_source(source: String) -> void:
    if not _sources.has(source):
        return
    var note: int = _sources[source]
    _sources.erase(source)
    _notes[note].erase(source)
    if _notes[note].is_empty():
        _notes.erase(note)
        if _sustain:
            _sustained[note] = true
        note_off.emit(note)
        midi_message.emit(JuceMidiMessage.note_off(midi_channel, note))
    queue_redraw()

func set_sustain(enabled: bool) -> void:
    if enabled == _sustain:
        return
    _sustain = enabled
    if not enabled:
        _sustained.clear()
    midi_message.emit(JuceMidiMessage.controller_event(midi_channel, 64, 127 if enabled else 0))
    sustain_changed.emit(enabled)
    queue_redraw()

func is_sustain_down() -> bool:
    return _sustain

func get_active_notes() -> Array:
    var result := _notes.keys()
    result.sort()
    return result

func all_notes_off() -> void:
    for source in _sources.keys():
        release_source(source)
    set_sustain(false)
    _sustained.clear()
    _held_keys.clear()
    _space_down = false
    _mouse_down = false
    midi_message.emit(JuceMidiMessage.controller_event(midi_channel, 123, 0))
    queue_redraw()

func _input(event: InputEvent) -> void:
    # Releases must work even if another Control consumed the corresponding press,
    # focus moved to a text field, or the pointer left the piano.
    if event is InputEventKey and not event.pressed:
        var key: int = event.physical_keycode if event.physical_keycode else event.keycode
        if _held_keys.has(key):
            release_source(_held_keys[key])
            _held_keys.erase(key)
            get_viewport().set_input_as_handled()
        elif key == KEY_SPACE and _space_down:
            _space_down = false
            set_sustain(false)
            get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        if _mouse_down:
            release_source("mouse")
            _mouse_down = false
    elif event is InputEventMouseMotion and _mouse_down:
        var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
        _play_mouse_at(local)

func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if not typing_enabled or not is_visible_in_tree():
        return
    if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
        return
    var focused := get_viewport().gui_get_focus_owner()
    if focused is LineEdit or focused is TextEdit or focused is SpinBox:
        return
    var key: int = event.physical_keycode if event.physical_keycode else event.keycode
    if key == KEY_ESCAPE:
        all_notes_off()
    elif key == KEY_BRACKETLEFT:
        base_note -= 12
    elif key == KEY_BRACKETRIGHT:
        base_note += 12
    elif key == KEY_SPACE:
        _space_down = true
        set_sustain(true)
    elif _mapping.has(key):
        if not _held_keys.has(key):
            var source := "key:%d" % key
            _held_keys[key] = source
            press_note(base_note + int(_mapping[key]), velocity / 127.0, source)
    else:
        return
    get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        grab_focus()
        _mouse_down = true
        _play_mouse_at(event.position)
        accept_event()
    elif event is InputEventMouseMotion:
        _hover_note = get_note_at_position(event.position)
        queue_redraw()

func _play_mouse_at(point: Vector2) -> void:
    var note := get_note_at_position(point)
    if note < 0:
        release_source("mouse")
    else:
        press_note(note, velocity / 127.0, "mouse")

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
        all_notes_off()

func _exit_tree() -> void:
    all_notes_off()

func _is_black(note: int) -> bool:
    return posmod(note, 12) in [1, 3, 6, 8, 10]

func _layout_keys() -> void:
    _rects.clear()
    var white_count := 0
    for note in range(base_note, base_note + DISPLAY_NOTES):
        if not _is_black(note):
            white_count += 1
    var width := size.x / white_count
    var index := 0
    for note in range(base_note, base_note + DISPLAY_NOTES):
        if _is_black(note):
            _rects[note] = Rect2(index * width - width * 0.31, 0, width * 0.62, size.y * 0.61)
        else:
            _rects[note] = Rect2(index * width, 0, width, size.y)
            index += 1

func get_note_rect(note: int) -> Rect2:
    _layout_keys()
    return _rects.get(note, Rect2())

func get_note_at_position(point: Vector2) -> int:
    if not Rect2(Vector2.ZERO, size).has_point(point):
        return -1
    _layout_keys()
    # Black keys overlap whites and must win hit testing.
    for black in [true, false]:
        for note in _rects:
            if _is_black(note) == black and _rects[note].has_point(point):
                return note
    return -1

func _draw() -> void:
    _layout_keys()
    for black in [false, true]:
        for note in _rects:
            if _is_black(note) == black:
                _draw_key(note, _rects[note], black)

func _draw_key(note: int, bounds: Rect2, black: bool) -> void:
    var held := _notes.has(note)
    var latched := _sustained.has(note)
    var fill := Color("222a38") if black else Color("e9edf3")
    if held:
        fill = TEAL if black else Color("a2efdb")
    elif latched:
        fill = Color("337966") if black else Color("bcded6")
    elif note == _hover_note:
        fill = fill.lightened(0.14) if black else Color("d2e7e3")
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = Color("111822")
    style.set_border_width_all(1)
    style.corner_radius_bottom_left = 5
    style.corner_radius_bottom_right = 5
    draw_style_box(style, bounds.grow(-0.5))
    var color := Color("e9edf3") if black and not held else Color("263246")
    var font := get_theme_default_font()
    var labels: Array[String] = []
    for key in _mapping:
        if base_note + int(_mapping[key]) == note:
            var symbols := {KEY_COMMA: ",", KEY_PERIOD: ".", KEY_SEMICOLON: ";", KEY_SLASH: "/"}
            labels.append(symbols.get(key, OS.get_keycode_string(key)))
    # At narrow sizes show the first shortcut; all aliases remain playable.
    var caption := "·".join(labels)
    if font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x > bounds.size.x - 6:
        caption = labels[0] if not labels.is_empty() else ""
    draw_string(font, Vector2(bounds.position.x, bounds.end.y - 30), caption,
        HORIZONTAL_ALIGNMENT_CENTER, bounds.size.x, 12, color)
    draw_string(font, Vector2(bounds.position.x, bounds.end.y - 12), note_name(note),
        HORIZONTAL_ALIGNMENT_CENTER, bounds.size.x, 11, color.lightened(0.15))

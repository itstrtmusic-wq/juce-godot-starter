extends RefCounted
## Beat-based document used by the piano roll. Native playback takes a snapshot.

signal changed
var notes: Array[Dictionary] = []
var bpm := 120.0
var length_beats := 16.0
var last_error := ""
var _next_id := 1
var _history: Array[Dictionary] = []
var _history_index := -1
var _saved: Dictionary = {}
var _taking := false

func _init() -> void:
    _remember()
    _saved = document()

func document() -> Dictionary:
    return {"type": "juce_midi_clip", "schema_version": 1, "bpm": bpm,
        "length_beats": length_beats, "notes": native_notes()}

func native_notes() -> Array:
    var result: Array = []
    for note in notes:
        var copy := note.duplicate()
        copy.erase("id")
        result.append(copy)
    return result

func is_dirty() -> bool:
    return document() != _saved

func _remember() -> void:
    if _taking:
        changed.emit()
        return
    var snapshot := document()
    if _history_index >= 0 and _history[_history_index] == snapshot:
        return
    _history.resize(_history_index + 1)
    _history.append(snapshot)
    if _history.size() > 100:
        _history.pop_front()
    _history_index = _history.size() - 1
    changed.emit()

func begin_take() -> void:
    _taking = true

func end_take() -> void:
    _taking = false
    _remember()

func _apply(data: Dictionary) -> void:
    bpm = float(data.bpm)
    length_beats = float(data.length_beats)
    notes.clear()
    for raw in data.notes:
        var note: Dictionary = raw.duplicate()
        note["id"] = _next_id
        _next_id += 1
        notes.append(note)

func load_document(data: Variant) -> bool:
    if not data is Dictionary:
        return _fail("Clip must be a JSON object.")
    for key in data:
        if key not in ["type", "schema_version", "bpm", "length_beats", "notes"]:
            return _fail("Unknown clip field: " + str(key))
    if data.get("type") != "juce_midi_clip" or not _number(data.get("schema_version")) or data.schema_version != 1:
        return _fail("Unsupported clip format.")
    if not _number(data.get("bpm")) or data.bpm < 20 or data.bpm > 300:
        return _fail("BPM must be 20–300.")
    if not _number(data.get("length_beats")) or not data.get("notes") is Array:
        return _fail("Missing clip length or note array.")
    var check := JuceMidiSequencer.new()
    if not check.load_clip(data.notes, float(data.length_beats)):
        return _fail(check.get_last_error())
    var normalized := check.export_clip()
    normalized["bpm"] = float(data.bpm)
    _apply(normalized)
    _remember()
    last_error = ""
    return true

func _number(value: Variant) -> bool:
    return (value is int or value is float) and is_finite(float(value))

func _fail(message: String) -> bool:
    last_error = message
    return false

func set_bpm(value: float) -> bool:
    if not is_finite(value) or value < 20 or value > 300:
        return _fail("BPM must be 20–300.")
    bpm = value
    _remember()
    return true

func set_length(value: float) -> bool:
    if not is_finite(value) or value < 1 or value > 256:
        return _fail("Clip length must be 1–256 beats.")
    for note in notes:
        if note.start + note.length > value + 0.000000001:
            return _fail("Some notes extend beyond this length. Move or delete them first.")
    length_beats = value
    _remember()
    return true

func add_note(pitch: int, start: float, duration: float, velocity := 0.8, channel := 1) -> int:
    if notes.size() >= 4096 or not _valid_note(pitch, start, duration, velocity, channel):
        last_error = "Invalid note or clip exceeds 4096 notes."
        return -1
    var id := _next_id
    _next_id += 1
    notes.append({"id": id, "note": pitch, "start": start, "length": duration,
        "velocity": velocity, "channel": channel})
    _remember()
    return id

func _valid_note(pitch: int, start: float, duration: float, strength: float, channel: int) -> bool:
    return pitch >= 0 and pitch <= 127 and channel >= 1 and channel <= 16 \
        and is_finite(start) and is_finite(duration) and is_finite(strength) \
        and start >= 0 and duration > 0 and start + duration > start and start + duration <= length_beats + 0.000000001 \
        and strength > 0 and strength <= 1

func find_note(id: int) -> Dictionary:
    for note in notes:
        if note.id == id:
            return note.duplicate()
    return {}

func update_note(id: int, pitch: int, start: float, duration: float, strength: float) -> bool:
    for note in notes:
        if note.id == id and _valid_note(pitch, start, duration, strength, note.channel):
            note.note = pitch
            note.start = start
            note.length = duration
            note.velocity = strength
            _remember()
            return true
    return _fail("Note change is outside the clip or parameter range.")

func remove_note(id: int) -> void:
    for index in notes.size():
        if notes[index].id == id:
            notes.remove_at(index)
            _remember()
            return

func add_recorded(recorded: Dictionary) -> void:
    # A held note crossing the loop edge becomes two editable notes.
    var start := fposmod(float(recorded.start), length_beats)
    var duration := minf(float(recorded.length), length_beats)
    if duration < 0.000001:
        return
    var first := minf(duration, length_beats - start)
    add_note(int(recorded.note), start, first, float(recorded.velocity), int(recorded.channel))
    if duration > first + 0.000001:
        add_note(int(recorded.note), 0, duration - first, float(recorded.velocity), int(recorded.channel))

func quantize(grid: float) -> void:
    if not is_finite(grid) or grid < 0.0625 or grid > 4:
        return
    for note in notes:
        var start := clampf(snappedf(note.start, grid), 0, maxf(0, length_beats - grid))
        var end := clampf(snappedf(note.start + note.length, grid), start + minf(grid, length_beats - start), length_beats)
        note.start = start
        note.length = end - start
    _remember()

func undo() -> void:
    if _history_index > 0 and not _taking:
        _history_index -= 1
        _apply(_history[_history_index])
        changed.emit()

func redo() -> void:
    if _history_index + 1 < _history.size() and not _taking:
        _history_index += 1
        _apply(_history[_history_index])
        changed.emit()

func save_file(path: String, overwrite := false) -> bool:
    var file := JuceFile.new()
    file.set_path(path)
    if file.is_directory() or (file.exists() and not overwrite):
        return _fail("Choose another name or explicitly allow overwrite.")
    if not file.replace_with_text(JSON.stringify(document(), "  ")):
        return _fail("Could not write clip file.")
    _saved = document()
    changed.emit()
    return true

func load_file(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > 2097152:
        return _fail("Clip is missing or exceeds 2 MiB.")
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK:
        return _fail("Invalid clip JSON.")
    if not load_document(parser.data):
        return false
    _saved = document()
    changed.emit()
    return true

func export_midi(path: String, overwrite := false) -> bool:
    var sequence := JuceMidiMessageSequence.new()
    sequence.add_event(JuceMidiMessage.tempo_event(roundi(60000000.0 / bpm)))
    for note in notes:
        var on := JuceMidiMessage.note_on(note.channel, note.note, maxf(1.0 / 127.0, note.velocity))
        on.set_timestamp(note.start * 960.0)
        var off := JuceMidiMessage.note_off(note.channel, note.note)
        off.set_timestamp((note.start + note.length) * 960.0)
        sequence.add_event(on)
        sequence.add_event(off)
    var file := JuceMidiFile.new()
    file.set_ticks_per_quarter_note(960)
    file.add_track(sequence)
    if not file.write_file(path, overwrite):
        return _fail(file.get_last_error())
    return true

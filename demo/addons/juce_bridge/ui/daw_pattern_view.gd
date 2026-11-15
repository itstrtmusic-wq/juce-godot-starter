extends RefCounted

signal changed
var project: RefCounted
var pattern_index := 0
var channel_index := 0
var length_beats: float:
    get:
        return maxf(16, project.patterns[pattern_index].length_beats)
var notes: Array:
    get:
        var result: Array = []
        for note in project.patterns[pattern_index].notes:
            if note.channel == channel_index + 1:
                result.append(note)
        return result

func setup(value: RefCounted) -> void:
    project = value
    project.changed.connect(_project_changed)

func _project_changed() -> void:
    pattern_index = clampi(pattern_index, 0, project.patterns.size() - 1)
    channel_index = clampi(channel_index, 0, project.channels.size() - 1)
    changed.emit()

func select(pattern: int, channel: int) -> void:
    pattern_index = pattern
    channel_index = channel
    changed.emit()

func find_note(id: int) -> Dictionary:
    for note in notes:
        if note.id == id:
            return note.duplicate()
    return {}

func add_note(pitch: int, start: float, duration: float, velocity := 0.8) -> int:
    project.begin_edit()
    _extend(start + duration)
    var id: int = project.patterns[pattern_index].add_note(pitch, start, duration, velocity, channel_index + 1)
    project.end_edit()
    return id

func update_note(id: int, pitch: int, start: float, duration: float, velocity: float) -> bool:
    project.begin_edit()
    _extend(start + duration)
    var ok: bool = project.patterns[pattern_index].update_note(id, pitch, start, duration, velocity)
    project.end_edit()
    return ok

func _extend(end: float) -> void:
    if end > project.patterns[pattern_index].length_beats:
        project.patterns[pattern_index].set_length(minf(256, ceilf(end / 4.0) * 4.0))

func remove_note(id: int) -> void:
    project.patterns[pattern_index].remove_note(id)

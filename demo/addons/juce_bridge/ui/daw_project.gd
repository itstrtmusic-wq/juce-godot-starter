extends RefCounted
## Patterns, arrangement and mixer state. Playback compiles an immutable MIDI clip.

signal changed
const Clip = preload("res://addons/juce_bridge/ui/midi_clip.gd")
const Look = preload("res://addons/juce_bridge/ui/daw_theme.gd")
const EFFECT_TYPES := ["", "low_pass", "peak", "tanh", "delay", "reverb", "chorus", "phaser", "compressor", "noise_gate", "limiter"]
var title := "Untitled project"
var bpm := 128.0
var song_length := 32.0
var channels: Array[Dictionary] = []
var patterns: Array[RefCounted] = []
var names: Array[String] = []
var colors: Array[String] = []
var placements: Array[Dictionary] = []
var tracks: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var master_db := -9.0
var last_error := ""
var _saved: Dictionary = {}
var _history: Array[Dictionary] = []
var _index := -1
var _depth := 0
var _applying := false
var _next_id := 1

func _init() -> void:
    _applying = true
    var labels := ["Kick", "Snare", "Closed hat", "Clap", "Sub bass", "Lead", "Keys", "Pad"]
    var modes := [4, 5, 6, 7, 0, 2, 1, 0]
    var pitches := [36, 38, 42, 39, 36, 72, 60, 60]
    for i in 8:
        channels.append({"name": labels[i], "waveform": modes[i], "volume_db": -4.0 if i < 4 else 0.0,
            "pan": 0.0, "mute": false, "solo": false, "note": pitches[i], "color": Look.COLORS[i]})
        tracks.append({"name": "Track %d" % (i + 1), "mute": false})
        effects.append({"type": "", "parameters": {}})
    effects[7] = {"type": "limiter", "parameters": {"threshold_db": -1.0}}
    _add_pattern("Pattern 1", 4.0)
    _applying = false
    remember()
    mark_saved()

func document() -> Dictionary:
    var clips: Array = []
    for i in patterns.size():
        clips.append({"name": names[i], "color": colors[i], "clip": patterns[i].document()})
    var instances: Array = []
    for placement in placements:
        var copy := placement.duplicate()
        copy.erase("id")
        instances.append(copy)
    return {"type": "juce_daw_project", "schema_version": 1, "title": title, "bpm": bpm,
        "song_length": song_length, "channels": channels.duplicate(true), "patterns": clips,
        "placements": instances, "tracks": tracks.duplicate(true), "effects": effects.duplicate(true), "master_db": master_db}

func mark_saved() -> void:
    _saved = document()
    changed.emit()

func is_dirty() -> bool:
    return document() != _saved

func begin_edit() -> void:
    _depth += 1

func end_edit() -> void:
    _depth = maxi(0, _depth - 1)
    remember()

func finish_edits() -> void:
    _depth = 0
    remember()

func reset_history() -> void:
    _history.clear()
    _index = -1
    _depth = 0
    remember()
    mark_saved()

func remember() -> void:
    if _applying:
        return
    if _depth == 0:
        var data := document()
        if _index < 0 or _history[_index] != data:
            _history.resize(_index + 1)
            _history.append(data)
            if _history.size() > 60:
                _history.pop_front()
            _index = _history.size() - 1
    changed.emit()

func undo() -> void:
    if _depth == 0 and _index > 0:
        _index -= 1
        _apply(_history[_index])
        changed.emit()

func redo() -> void:
    if _depth == 0 and _index + 1 < _history.size():
        _index += 1
        _apply(_history[_index])
        changed.emit()

func _add_pattern(name: String, length: float) -> int:
    var clip = Clip.new()
    clip.bpm = bpm
    clip.length_beats = length
    clip.changed.connect(remember)
    patterns.append(clip)
    names.append(name.left(64))
    colors.append(Look.COLORS[(patterns.size() - 1) % Look.COLORS.size()])
    return patterns.size() - 1

func add_pattern(name := "") -> int:
    if patterns.size() >= 64:
        last_error = "The project supports 64 patterns."
        return -1
    var index := _add_pattern(name if not name.is_empty() else "Pattern %d" % (patterns.size() + 1), 4.0)
    remember()
    return index

func duplicate_pattern(index: int) -> int:
    if index < 0 or index >= patterns.size() or patterns.size() >= 64:
        return -1
    var next := _add_pattern(names[index] + " copy", patterns[index].length_beats)
    patterns[next].load_document(patterns[index].document())
    remember()
    return next

func set_bpm(value: float) -> bool:
    if not is_finite(value) or value < 20 or value > 300:
        return false
    bpm = value
    for pattern in patterns:
        pattern.bpm = value
    remember()
    return true

func set_channel(index: int, key: String, value: Variant) -> bool:
    if index < 0 or index >= channels.size():
        return false
    if key in ["volume_db", "pan", "mute", "solo", "waveform"]:
        var validator := JuceMidiSequencer.new()
        if not validator.set_channel_settings(index + 1, {key: value}):
            last_error = validator.get_last_error()
            return false
    elif key == "name":
        if not value is String or value.is_empty() or value.length() > 64:
            return false
    else:
        return false
    channels[index][key] = value
    remember()
    return true

func channel_settings(index: int) -> Dictionary:
    var result: Dictionary = channels[index].duplicate()
    for key in ["name", "note", "color"]:
        result.erase(key)
    return result

func add_channel(name := "Synth", waveform := 1) -> int:
    if channels.size() >= 16:
        return -1
    channels.append({"name": name, "waveform": waveform, "volume_db": 0.0, "pan": 0.0,
        "mute": false, "solo": false, "note": [36, 38, 42, 39][waveform - 4] if waveform >= 4 and waveform <= 7 else 60,
        "color": Look.COLORS[channels.size() % 8]})
    remember()
    return channels.size() - 1

func toggle_step(pattern: int, channel: int, step: int) -> void:
    if pattern < 0 or pattern >= patterns.size() or channel < 0 or channel >= channels.size() or step < 0 or step > 15:
        return
    var clip: RefCounted = patterns[pattern]
    var start := step * 0.25
    if start >= clip.length_beats:
        return
    begin_edit()
    var found := false
    for note in clip.notes.duplicate():
        if note.channel == channel + 1 and absf(note.start - start) < 0.001:
            clip.remove_note(note.id)
            found = true
    if not found:
        clip.add_note(channels[channel].note, start, minf(0.18, clip.length_beats - start), 0.85, channel + 1)
    end_edit()

func fill_steps(pattern: int, channel: int, interval: int) -> void:
    begin_edit()
    var clip: RefCounted = patterns[pattern]
    for note in clip.notes.duplicate():
        if note.channel == channel + 1 and note.start < 4:
            clip.remove_note(note.id)
    if interval > 0:
        for step in range(0, 16, interval):
            clip.add_note(channels[channel].note, step * 0.25, 0.18, 0.85, channel + 1)
    end_edit()

func add_placement(pattern: int, start: float, track: int, length := -1.0) -> int:
    if pattern < 0 or pattern >= patterns.size() or track < 0 or track >= tracks.size() or placements.size() >= 128:
        return -1
    if length < 0:
        length = patterns[pattern].length_beats
    if not is_finite(start) or not is_finite(length) or start < 0 or length <= 0 or start + length > song_length + 0.000001:
        last_error = "Place clips inside the song region (up to 256 beats)."
        return -1
    var id := _next_id
    _next_id += 1
    placements.append({"id": id, "pattern": pattern, "start": start, "track": track, "length": length})
    remember()
    return id

func change_placement(id: int, start: float, track: int, length: float) -> bool:
    if start < 0 or length <= 0 or start + length > song_length + 0.000001 or track < 0 or track >= tracks.size():
        return false
    for item in placements:
        if item.id == id:
            item.start = start
            item.track = track
            item.length = length
            remember()
            return true
    return false

func remove_placement(id: int) -> void:
    for i in placements.size():
        if placements[i].id == id:
            placements.remove_at(i)
            remember()
            return

func compile_song() -> Array:
    var notes: Array = []
    for item in placements:
        if tracks[item.track].mute:
            continue
        var pattern: RefCounted = patterns[item.pattern]
        for repeat in ceili(item.length / pattern.length_beats):
            var offset: float = repeat * pattern.length_beats
            for note in pattern.native_notes():
                var start: float = offset + note.start
                if start >= item.length:
                    continue
                if notes.size() >= 4096:
                    last_error = "Arrangement exceeds the native 4096-note playback limit."
                    return []
                var copy: Dictionary = note.duplicate()
                copy.start = item.start + start
                copy.length = minf(note.length, item.length - start)
                notes.append(copy)
    last_error = ""
    return notes

func build_effects() -> JuceDSPNetwork:
    var fx := JuceDSPNetwork.new()
    var previous := "input"
    for i in effects.size():
        if effects[i].type.is_empty():
            continue
        var id := "slot_%d" % i
        if not fx.add_node(id, effects[i].type):
            last_error = fx.get_last_error()
            return null
        for key in effects[i].parameters:
            var value: Variant = effects[i].parameters[key]
            if not key is String or not (value is int or value is float) or not is_finite(float(value)):
                last_error = "Effect parameters must be finite numbers."
                return null
            if not fx.set_parameter(id, key, effects[i].parameters[key]):
                last_error = fx.get_last_error()
                return null
        fx.connect_nodes(previous, id)
        previous = id
    fx.connect_nodes(previous, "output")
    return fx

func save_file(path: String, overwrite := false) -> bool:
    var file := JuceFile.new()
    file.set_path(path)
    var text := JSON.stringify(document(), "  ")
    if text.to_utf8_buffer().size() > 8388608:
        last_error = "Project exceeds the 8 MiB file limit."
        return false
    if file.is_directory() or (file.exists() and not overwrite) or not file.replace_with_text(text):
        last_error = "Cannot save the project; choose a writable file and confirm overwrite."
        return false
    mark_saved()
    return true

func load_file(path: String) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > 8388608:
        last_error = "Project is missing or exceeds 8 MiB."
        return false
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK or not load_document(parser.data):
        if last_error.is_empty():
            last_error = "Invalid project JSON."
        return false
    reset_history()
    return true

func load_document(data: Variant) -> bool:
    last_error = ""
    # Validate into an isolated candidate so a bad file cannot replace the session.
    if not data is Dictionary or data.get("type") != "juce_daw_project" or not _number(data.get("schema_version"), 1, 1):
        last_error = "Unsupported project format."
        return false
    if not _number(data.get("bpm"), 20, 300) or not _number(data.get("song_length"), 4, 256) or not _number(data.get("master_db"), -60, 0):
        last_error = "Invalid BPM, song length or master level."
        return false
    if not data.get("title") is String or data.title.length() > 128:
        return false
    for field in ["channels", "patterns", "placements", "tracks", "effects"]:
        if not data.get(field) is Array:
            return false
    if data.channels.size() < 1 or data.channels.size() > 16 or data.patterns.is_empty() or data.patterns.size() > 64 or data.placements.size() > 128 or data.tracks.size() != 8 or data.effects.size() != 8:
        last_error = "Project exceeds the supported channel, pattern, track or clip counts."
        return false
    var validator := JuceMidiSequencer.new()
    for channel in data.channels:
        if not channel is Dictionary or not channel.get("name") is String or not channel.get("color") is String or not _number(channel.get("note"), 0, 127) or channel.note != floorf(channel.note):
            return false
        var settings: Dictionary = channel.duplicate()
        for key in ["name", "color", "note"]:
            settings.erase(key)
        if not validator.set_channel_settings(1, settings) or settings.size() != 5:
            return false
    for pattern in data.patterns:
        if not pattern is Dictionary or not pattern.get("name") is String or not pattern.get("color") is String:
            return false
        var clip = Clip.new()
        if not clip.load_document(pattern.get("clip")):
            last_error = clip.last_error
            return false
        for note in clip.notes:
            if note.channel > data.channels.size():
                return false
    for track in data.tracks:
        if not track is Dictionary or not track.get("name") is String or not track.get("mute") is bool:
            return false
    for item in data.placements:
        if not item is Dictionary or not _number(item.get("pattern"), 0, data.patterns.size() - 1) or item.pattern != floorf(item.pattern) or not _number(item.get("track"), 0, 7) or item.track != floorf(item.track):
            return false
        if not _number(item.get("start"), 0, data.song_length) or not _number(item.get("length"), 0.000001, data.song_length) or item.start + item.length > data.song_length + 0.000001:
            return false
    for effect in data.effects:
        if not effect is Dictionary or not effect.get("type") is String or not effect.get("parameters") is Dictionary:
            return false
        if effect.type not in EFFECT_TYPES or (effect.type.is_empty() and not effect.parameters.is_empty()):
            last_error = "Unsupported workspace effect type."
            return false
    var candidate = get_script().new()
    candidate.effects.assign(data.effects.duplicate(true))
    if candidate.build_effects() == null:
        last_error = "Invalid master effects."
        return false
    _apply(data)
    remember()
    last_error = ""
    return true

func _number(value: Variant, low: float, high: float) -> bool:
    return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func _apply(data: Dictionary) -> void:
    _applying = true
    title = data.title
    bpm = float(data.bpm)
    song_length = float(data.song_length)
    master_db = float(data.master_db)
    channels.assign(data.channels.duplicate(true))
    for channel in channels:
        channel.waveform = int(channel.waveform)
        channel.note = int(channel.note)
        channel.volume_db = float(channel.volume_db)
        channel.pan = float(channel.pan)
    tracks.assign(data.tracks.duplicate(true))
    effects.assign(data.effects.duplicate(true))
    for effect in effects:
        for key in effect.parameters:
            effect.parameters[key] = float(effect.parameters[key])
    patterns.clear()
    names.clear()
    colors.clear()
    for item in data.patterns:
        var i := _add_pattern(item.name, item.clip.length_beats)
        colors[i] = item.color
        patterns[i].load_document(item.clip)
        patterns[i].bpm = bpm
    placements.clear()
    for raw in data.placements:
        var copy: Dictionary = raw.duplicate()
        copy.pattern = int(copy.pattern)
        copy.track = int(copy.track)
        copy.start = float(copy.start)
        copy.length = float(copy.length)
        copy["id"] = _next_id
        _next_id += 1
        placements.append(copy)
    _applying = false

func demo() -> void:
    begin_edit()
    title = "Night Drive"
    names[0] = "Drums"
    for step in [0, 4, 8, 12]:
        toggle_step(0, 0, step)
    for step in [4, 12]:
        toggle_step(0, 1, step)
        toggle_step(0, 3, step)
    for step in range(0, 16, 2):
        toggle_step(0, 2, step)
    var bass := _add_pattern("Bass", 8)
    var chords := _add_pattern("Chords", 8)
    var lead := _add_pattern("Lead", 8)
    for i in 4:
        patterns[bass].add_note([36, 36, 43, 41][i], i * 2.0, 1.5, 0.8, 5)
        for pitch in [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]][i]:
            patterns[chords].add_note(pitch, i * 2.0, 1.75, 0.65, 7)
    for i in 8:
        patterns[lead].add_note([72, 74, 76, 79, 76, 74, 71, 72][i], float(i), 0.65, 0.75, 6)
    for beat in range(0, 32, 4):
        add_placement(0, beat, 0)
    for index in [bass, chords]:
        for beat in range(0, 32, 8):
            add_placement(index, beat, index)
    add_placement(lead, 16, 3)
    add_placement(lead, 24, 3)
    end_edit()
    reset_history()

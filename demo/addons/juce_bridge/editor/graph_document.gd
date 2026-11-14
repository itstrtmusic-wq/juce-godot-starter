@tool
extends RefCounted
## UI-independent editable DSP document. Native validation remains authoritative.

signal changed(structural: bool)
signal parameter_changed(id: String, parameter: String, value: float)

const LIMIT_BYTES := 2097152
const HISTORY_LIMIT := 100
var network: RefCounted
var definitions: Dictionary = {}
var records: Dictionary = {}
var positions: Dictionary = {}
var titles: Dictionary = {}
var view := {"zoom": 1.0, "scroll_x": 0.0, "scroll_y": 0.0}
var current_path := ""
var last_error := ""
var _history: Array = []
var _cursor := -1
var _saved_fingerprint := ""
var _serial := 1

func initialize() -> bool:
    if not ClassDB.class_exists("JuceDSPNetwork"):
        return _fail("Native JUCE addon not loaded. Download a compiled build or build the DLL first.")
    network = ClassDB.instantiate("JuceDSPNetwork")
    if not network.has_method("connect_parameter"):
        network = null
        return _fail("This editor requires the JUCE API version 0.3 or newer.")
    var probe: RefCounted = ClassDB.instantiate("JuceDSPNetwork")
    for kind in network.get_supported_node_types():
        var id: String = "definition_" + kind
        if probe.add_node(id, kind):
            for info in probe.get_nodes():
                if info.id == id:
                    definitions[kind] = info.parameters.duplicate(true)
                    break
    return new_document("filter")

func _fail(message: String) -> bool:
    last_error = message
    return false

func _refresh() -> void:
    records.clear()
    for info in network.get_nodes():
        records[info.id] = info
    for id in positions.keys():
        if not records.has(id):
            positions.erase(id)
            titles.erase(id)

func _finish(structural: bool, history := true) -> bool:
    last_error = ""
    if structural:
        _refresh()
    if history:
        commit_history()
    changed.emit(structural)
    return true

func add_processor(kind: String, position: Vector2) -> String:
    if not definitions.has(kind):
        _fail("Unknown processor type: " + kind)
        return ""
    var id := "%s_%d" % [kind, _serial]
    while records.has(id):
        _serial += 1
        id = "%s_%d" % [kind, _serial]
    _serial += 1
    if not network.add_node(id, kind):
        _fail(network.get_last_error())
        return ""
    positions[id] = position.clamp(Vector2(-50000, -50000), Vector2(50000, 50000))
    _finish(true)
    return id

func remove_processors(ids: Array) -> bool:
    var removed: Dictionary = {}
    for raw in ids:
        var id := String(raw)
        if records.has(id) and id not in ["input", "output"]:
            removed[id] = true
    if removed.is_empty():
        return _fail("Input and Output are permanent. Select a processor to delete.")
    var patch: Dictionary = network.export_patch()
    patch.nodes = patch.nodes.filter(func(n: Dictionary): return not removed.has(n.id))
    patch.connections = patch.connections.filter(func(e: Dictionary): return not removed.has(e.source) and not removed.has(e.destination))
    patch.modulations = patch.modulations.filter(func(e: Dictionary): return not removed.has(e.source) and not removed.has(e.destination))
    return replace_patch(patch)

func connect_audio(source: String, destination: String, gain := 1.0) -> bool:
    if not network.connect_nodes(source, destination, gain):
        return _fail(network.get_last_error())
    return _finish(true)

func connect_control(source: String, destination: String, parameter: String, depth := 1.0, offset := 0.0, channel := 0) -> bool:
    if not network.connect_parameter(source, destination, parameter, depth, offset, channel):
        return _fail(network.get_last_error())
    return _finish(true)

func disconnect_link(link: Dictionary) -> bool:
    var ok: bool
    if link.kind == "audio":
        ok = network.disconnect_nodes(link.source, link.destination)
    else:
        ok = network.disconnect_parameter(link.source, link.destination, link.parameter)
    if not ok:
        return _fail(network.get_last_error())
    return _finish(true)

func replace_patch(patch: Dictionary) -> bool:
    if not network.load_patch(patch):
        return _fail(network.get_last_error())
    return _finish(true)

func update_link(link: Dictionary, values: Dictionary) -> bool:
    var patch: Dictionary = network.export_patch()
    var links: Array = patch.connections if link.kind == "audio" else patch.modulations
    var found := false
    for entry in links:
        if entry.source == link.source and entry.destination == link.destination:
            if link.kind == "control" and entry.parameter != link.parameter:
                continue
            for key in values:
                entry[key] = values[key]
            found = true
            break
    if not found:
        return _fail("This connection no longer exists.")
    return replace_patch(patch)

func set_parameter(id: String, parameter: String, value: float, history := true) -> bool:
    if not network.set_parameter(id, parameter, value):
        return _fail(network.get_last_error())
    var actual: float = network.get_parameters(id)[parameter]
    records[id].parameters[parameter].value = actual
    parameter_changed.emit(id, parameter, actual)
    return _finish(false, history)

func set_title(id: String, title: String) -> bool:
    if not records.has(id) or title.length() > 80:
        return _fail("Use a title with at most 80 characters.")
    titles[id] = title.strip_edges()
    return _finish(true)

func move_node(id: String, position: Vector2) -> void:
    if records.has(id):
        positions[id] = position.clamp(Vector2(-50000, -50000), Vector2(50000, 50000))

func export_document() -> Dictionary:
    var layout: Dictionary = {}
    for id in records:
        var point: Vector2 = positions.get(id, Vector2.ZERO)
        layout[id] = {"x": point.x, "y": point.y, "title": titles.get(id, "")}
    return {"editor_version": 1, "patch": network.export_patch(), "layout": layout, "view": view.duplicate()}

func _fingerprint(data: Dictionary) -> String:
    return JSON.stringify({"patch": data.patch, "layout": data.layout})

func is_dirty() -> bool:
    return network != null and _fingerprint(export_document()) != _saved_fingerprint

func mark_saved() -> void:
    _saved_fingerprint = _fingerprint(export_document())
    changed.emit(false)

func commit_history() -> void:
    var data := export_document()
    if _cursor >= 0 and _fingerprint(_history[_cursor]) == _fingerprint(data):
        return
    _history = _history.slice(0, _cursor + 1)
    _history.append(data.duplicate(true))
    if _history.size() > HISTORY_LIMIT:
        _history.pop_front()
    _cursor = _history.size() - 1

func _reset_history() -> void:
    _history.clear()
    _cursor = -1
    commit_history()

func can_undo() -> bool:
    return _cursor > 0

func can_redo() -> bool:
    return _cursor >= 0 and _cursor < _history.size() - 1

func undo() -> bool:
    if not can_undo():
        return false
    if not _restore(_history[_cursor - 1]):
        return false
    _cursor -= 1
    changed.emit(true)
    return true

func redo() -> bool:
    if not can_redo():
        return false
    if not _restore(_history[_cursor + 1]):
        return false
    _cursor += 1
    changed.emit(true)
    return true

static func _number(value: Variant) -> bool:
    return (value is float or value is int) and is_finite(float(value))

func _restore(data: Dictionary) -> bool:
    var patch: Dictionary
    var layout: Dictionary = {}
    var next_view := {"zoom": 1.0, "scroll_x": 0.0, "scroll_y": 0.0}
    if data.has("editor_version"):
        if not _number(data.editor_version) or data.editor_version != 1 or not data.get("patch") is Dictionary or not data.get("layout", {}) is Dictionary or not data.get("view", {}) is Dictionary:
            return _fail("Unsupported graph document version or invalid layout.")
        patch = data.patch
        layout = data.get("layout", {})
        var raw_view: Dictionary = data.get("view", {})
        for key in next_view:
            var value: Variant = raw_view.get(key, next_view[key])
            if not _number(value) or abs(float(value)) > 100000:
                return _fail("Invalid canvas view.")
            next_view[key] = float(value)
        if next_view.zoom < 0.25 or next_view.zoom > 2.0:
            return _fail("Canvas zoom must be between 25% and 200%.")
    else:
        patch = data
    if layout.size() > 128:
        return _fail("Graph layout exceeds the node limit.")
    var next_positions: Dictionary = {}
    var next_titles: Dictionary = {}
    for id in layout:
        if not id is String or not layout[id] is Dictionary:
            return _fail("Invalid node layout.")
        var item: Dictionary = layout[id]
        if not _number(item.get("x", 0)) or not _number(item.get("y", 0)) or abs(float(item.get("x", 0))) > 50000 or abs(float(item.get("y", 0))) > 50000 or not item.get("title", "") is String or String(item.get("title", "")).length() > 80:
            return _fail("Invalid node position or title.")
        next_positions[id] = Vector2(float(item.get("x", 0)), float(item.get("y", 0)))
        next_titles[id] = item.get("title", "")
    # Native patch validation is transactional, including audio/control cycle checks.
    if not network.load_patch(patch):
        return _fail(network.get_last_error())
    positions = next_positions
    titles = next_titles
    view = next_view
    _refresh()
    _fill_missing_positions()
    last_error = ""
    return true

func load_document(data: Dictionary, saved := false) -> bool:
    if not _restore(data):
        return false
    current_path = ""
    _saved_fingerprint = _fingerprint(export_document()) if saved else ""
    _reset_history()
    changed.emit(true)
    return true

func _arranged_positions() -> Dictionary:
    var levels: Dictionary = {}
    for id in records:
        levels[id] = 0
    var links: Array = network.get_connections() + network.get_modulation_connections()
    for _pass in records.size():
        var progressed := false
        for link in links:
            var level: int = levels[link.source] + 1
            if level > levels[link.destination]:
                levels[link.destination] = level
                progressed = true
        if not progressed:
            break
    var groups: Dictionary = {}
    for id in records:
        var level: int = levels[id]
        if not groups.has(level):
            groups[level] = []
        groups[level].append(id)
    var ordered: Array = groups.keys()
    ordered.sort()
    var result: Dictionary = {}
    var x := 70.0
    for level in ordered:
        var ids: Array = groups[level]
        for index in ids.size():
            result[ids[index]] = Vector2(x + floori(index / 4.0) * 285, 70 + (index % 4) * 310)
        x += maxf(1, ceilf(ids.size() / 4.0)) * 285
    return result

func _fill_missing_positions() -> void:
    var arranged := _arranged_positions()
    for id in records:
        if not positions.has(id):
            positions[id] = arranged[id]

func auto_arrange() -> void:
    positions = _arranged_positions()
    _finish(true)

func new_document(preset := "blank") -> bool:
    var patch := {"schema_version": 1, "nodes": [], "connections": [], "modulations": []}
    var layout := {"input": {"x": 50, "y": 50}, "output": {"x": 940, "y": 320}}
    if preset == "filter":
        patch.nodes = [
            {"id": "tone", "type": "oscillator", "parameters": {"frequency": 110.0, "gain": 0.06, "waveform": 1.0}},
            {"id": "filter", "type": "low_pass", "parameters": {"frequency": 2200.0}},
            {"id": "level", "type": "gain", "parameters": {"gain_db": -12.0}},
            {"id": "slow", "type": "lfo", "parameters": {"rate_hz": 0.75}}
        ]
        patch.connections = [{"source": "tone", "destination": "filter"}, {"source": "filter", "destination": "level"}, {"source": "level", "destination": "output"}]
        patch.modulations = [{"source": "slow", "destination": "filter", "parameter": "frequency", "depth": 1600.0}]
        layout.merge({"tone": {"x": 50, "y": 330, "title": "Test oscillator"}, "filter": {"x": 350, "y": 330, "title": "Moving low-pass"}, "level": {"x": 650, "y": 330, "title": "Output level"}, "slow": {"x": 350, "y": 30, "title": "Cutoff motion"}})
    elif preset == "live_input":
        patch.nodes = [{"id": "filter", "type": "high_pass", "parameters": {"frequency": 80.0}}, {"id": "drive", "type": "tanh", "parameters": {"drive": 2.0}}, {"id": "level", "type": "gain", "parameters": {"gain_db": -12.0}}]
        patch.connections = [{"source": "input", "destination": "filter"}, {"source": "filter", "destination": "drive"}, {"source": "drive", "destination": "level"}, {"source": "level", "destination": "output"}]
        layout = {"input": {"x": 50, "y": 160}, "filter": {"x": 350, "y": 160}, "drive": {"x": 650, "y": 160}, "level": {"x": 950, "y": 160}, "output": {"x": 1250, "y": 160}}
    elif preset != "blank":
        return _fail("Unknown starter network.")
    if not _restore({"editor_version": 1, "patch": patch, "layout": layout}):
        return false
    current_path = ""
    _saved_fingerprint = _fingerprint(export_document())
    _reset_history()
    changed.emit(true)
    return true

static func read_json_file(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {"ok": false, "error": "Cannot open this file."}
    if file.get_length() > LIMIT_BYTES:
        file.close()
        return {"ok": false, "error": "Graph files must be smaller than 2 MiB."}
    var text := file.get_as_text()
    file.close()
    var parser := JSON.new()
    if parser.parse(text) != OK or not parser.data is Dictionary:
        return {"ok": false, "error": "Invalid JSON graph file."}
    return {"ok": true, "data": parser.data}

static func write_json_file(path: String, data: Dictionary, overwrite := false) -> String:
    var absolute := ProjectSettings.globalize_path(path)
    if DirAccess.dir_exists_absolute(absolute):
        return "Choose a file, not a folder."
    if FileAccess.file_exists(path) and not overwrite:
        return "This file already exists."
    var text := JSON.stringify(data, "  ")
    if text.to_utf8_buffer().size() > LIMIT_BYTES:
        return "Graph files must be smaller than 2 MiB."
    var temporary := "%s.partial-%d-%d" % [absolute, OS.get_process_id(), Time.get_ticks_usec()]
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return "Cannot write to this folder."
    file.store_string(text)
    file.flush()
    var error := file.get_error()
    file.close()
    if error != OK:
        DirAccess.remove_absolute(temporary)
        return "Could not finish writing the file."
    if DirAccess.rename_absolute(temporary, absolute) != OK:
        DirAccess.remove_absolute(temporary)
        return "Could not replace the graph file."
    return ""

func load_file(path: String) -> bool:
    var result := read_json_file(path)
    if not result.ok:
        return _fail(result.error)
    var editor_file: bool = result.data.has("editor_version")
    if not load_document(result.data, editor_file):
        return false
    current_path = path if editor_file else ""
    changed.emit(false)
    return true

func save_file(path: String, overwrite := false) -> bool:
    var error := write_json_file(path, export_document(), overwrite)
    if not error.is_empty():
        return _fail(error)
    current_path = path
    last_error = ""
    mark_saved()
    return true

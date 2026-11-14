extends SceneTree

const GraphScene = preload("res://addons/juce_bridge/editor/graph_editor.tscn")
const Document = preload("res://addons/juce_bridge/editor/graph_document.gd")

func _initialize() -> void:
    call_deferred("run")

func run() -> void:
    root.size = Vector2i(1600, 1000)
    var editor: Control = GraphScene.instantiate()
    root.add_child(editor)
    for _frame in 8:
        await process_frame
    assert(editor._available)
    var doc: RefCounted = editor.document
    assert(doc.definitions.size() == 26)
    assert(doc.records.size() == 6)
    assert(editor.blocks.size() == 6)
    assert(editor.graph.get_connection_list().size() == 4)
    assert(not doc.is_dirty())
    for block in editor.blocks.values():
        assert(block.input_ports.size() == block.get_input_port_count())
        assert(block.output_ports.size() == block.get_output_port_count())
    var delay: String = editor.add_processor("delay", Vector2(640, 650))
    assert(not delay.is_empty())
    assert(doc.records.has(delay) and doc.is_dirty())
    var source: GraphNode = editor.blocks.tone
    var target: GraphNode = editor.blocks[delay]
    editor.graph.connection_request.emit(source.name, 0, target.name, target.input_for())
    assert(doc.network.get_connections().size() == 4)
    source = editor.blocks[delay]
    target = editor.blocks.filter
    editor.graph.connection_request.emit(source.name, 0, target.name, target.input_for())
    assert(doc.network.get_connections().size() == 5)
    var before_cycle: Dictionary = doc.network.export_patch()
    source = editor.blocks.filter
    target = editor.blocks.tone
    editor.graph.connection_request.emit(source.name, 1, target.name, target.input_for("frequency"))
    assert(doc.network.export_patch() == before_cycle)
    source = editor.blocks.slow
    target = editor.blocks[delay]
    editor.graph.connection_request.emit(source.name, 1, target.name, target.input_for("delay_ms"))
    assert(doc.network.get_modulation_connections().size() == 2)
    assert(editor.graph.get_connection_list().size() == 7)
    var link := {"kind": "control", "source": "slow", "destination": delay, "parameter": "delay_ms"}
    editor.inspect_link(link)
    assert(not editor.selected_link.is_empty())
    assert(doc.update_link(link, {"depth": 90.0, "offset": 10.0, "channel": 0}))
    assert(doc.network.get_modulation_connections()[1].depth == 90.0)
    editor.remove_processors([delay])
    assert(not doc.records.has(delay))
    assert(doc.network.get_connections().size() == 3)
    assert(doc.network.get_modulation_connections().size() == 1)
    editor.undo()
    assert(doc.records.has(delay))
    assert(doc.positions[delay] == Vector2(640, 650))
    assert(doc.network.get_connections().size() == 5)
    editor.redo()
    assert(not doc.records.has(delay))
    editor.undo()
    editor.inspect_node("filter")
    var controls: Dictionary = editor._parameter_controls.frequency
    controls.spin.value = 1300.0
    assert(doc.network.get_parameters("filter").frequency == 1300.0)
    controls.slider.value = 0.5
    assert(doc.network.get_parameters("filter").frequency != 1300.0)
    editor._flush_parameter_history()
    assert(doc.set_parameter("filter", "frequency", 900.0))
    assert(editor._parameter_controls.frequency.spin.value == 900.0)
    assert(doc.set_title("filter", "Warmth · 音"))
    assert(editor.blocks.filter.title == "Warmth · 音")
    doc.move_node("filter", Vector2(-70, 420))
    doc.commit_history()
    doc.view = {"zoom": 1.25, "scroll_x": 100.0, "scroll_y": 120.0}
    var document: Dictionary = doc.export_document()
    var prefix := "user://graph_ui_音_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
    var path := prefix + ".jucegraph"
    assert(doc.save_file(path))
    assert(not doc.is_dirty())
    assert(not doc.save_file(path))
    assert(doc.set_parameter("filter", "frequency", 1100.0))
    assert(doc.save_file(path, true))
    assert(not doc.is_dirty())
    assert(editor.open_file(path))
    assert(is_equal_approx(editor.graph.zoom, 1.25))
    assert(editor.graph.scroll_offset.is_equal_approx(Vector2(100, 120)))
    assert(doc.positions.filter == Vector2(-70, 420))
    assert(doc.titles.filter == "Warmth · 音")
    assert(doc.network.get_parameters("filter").frequency == 1100.0)
    var startup: Control = GraphScene.instantiate()
    root.add_child(startup)
    assert(startup.open_file(path))
    for _frame in 4:
        await process_frame
    assert(is_equal_approx(startup.graph.zoom, 1.25), "Startup fitting overwrote an embedded host's loaded view")
    startup.free()
    var valid: Dictionary = doc.export_document()
    var bad := valid.duplicate(true)
    bad.layout.filter.x = NAN
    assert(not doc.load_document(bad))
    assert(doc.export_document() == valid)
    bad = valid.duplicate(true)
    bad.patch.connections.append({"source": "filter", "destination": "tone"})
    assert(not doc.load_document(bad))
    assert(doc.export_document() == valid)
    assert(doc.network.save_patch(prefix + ".json"))
    assert(editor.open_file(prefix + ".json"))
    assert(doc.current_path.is_empty() and doc.is_dirty())
    assert(doc.network.get_parameters("filter").frequency == 1100.0)
    # Valid DSP IDs need not be valid Godot Node names. Render them using safe internal names.
    var unusual := {"schema_version": 1, "nodes": [{"id": "a/b:音", "type": "gain"}], "connections": [{"source": "input", "destination": "a/b:音"}, {"source": "a/b:音", "destination": "output"}]}
    assert(doc.load_document(unusual))
    assert(editor.blocks.has("a/b:音"))
    assert(doc.positions.input.x < doc.positions["a/b:音"].x and doc.positions["a/b:音"].x < doc.positions.output.x)
    assert(editor.graph.get_connection_list().size() == 2)
    assert(editor.blocks["a/b:音"].name != "a/b:音")
    # A saved document is accepted by a new instance, without depending on the widget.
    var other := Document.new()
    assert(other.initialize())
    assert(other.load_document(valid))
    assert(other.export_document().patch == valid.patch)
    assert(other.export_document().layout == valid.layout)
    assert(not other.remove_processors(["input", "output"]))
    var scratch := FileAccess.open(prefix + "_broken.json", FileAccess.WRITE)
    scratch.store_string("{ broken")
    scratch.close()
    var previous: Dictionary = doc.export_document()
    assert(not editor.open_file(prefix + "_broken.json"))
    assert(doc.export_document() == previous)
    for suffix in [".jucegraph", ".json", "_broken.json"]:
        DirAccess.remove_absolute(ProjectSettings.globalize_path(prefix + suffix))
    assert(doc.set_title("a/b:音", "A very long title " + "x".repeat(55)))
    editor.inspect_node("a/b:音")
    root.size = Vector2i(1080, 720)
    for _frame in 4:
        await process_frame
    assert(editor.get_combined_minimum_size().x <= 1080, "Editor minimum width exceeds the supported window width")
    assert(editor._inspector.get_global_rect().end.x <= 1080, "Inspector overflows the smaller viewport")
    editor.free()
    print("JUCE graph editor: ports, routing, cycle rejection, controls, undo/redo, layouts, Unicode IDs and transactional file round trips passed")
    quit(0)

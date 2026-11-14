extends SceneTree

const GraphScene = preload("res://addons/juce_bridge/editor/graph_editor.tscn")

func _initialize() -> void:
    call_deferred("run")

func mouse_move(point: Vector2, held := false) -> void:
    var event := InputEventMouseMotion.new()
    event.position = point
    event.global_position = point
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
    Input.parse_input_event(event)

func mouse_button(point: Vector2, down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.position = point
    event.global_position = point
    event.button_index = MOUSE_BUTTON_LEFT
    event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
    event.pressed = down
    Input.parse_input_event(event)

func click(point: Vector2) -> void:
    mouse_move(point)
    await process_frame
    mouse_button(point, true)
    await process_frame
    mouse_button(point, false)
    await process_frame

func drag(from: Vector2, to: Vector2) -> void:
    mouse_move(from)
    await process_frame
    mouse_button(from, true)
    await process_frame
    for index in range(1, 13):
        mouse_move(from.lerp(to, index / 12.0), true)
        await process_frame
    mouse_button(to, false)
    for _frame in 3:
        await process_frame

func key(code: Key, command := false) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.physical_keycode = code
    event.ctrl_pressed = command
    event.pressed = true
    Input.parse_input_event(event)
    await process_frame
    event.pressed = false
    Input.parse_input_event(event)
    await process_frame

func run() -> void:
    root.size = Vector2i(1600, 1000)
    var editor: Control = GraphScene.instantiate()
    root.add_child(editor)
    for _frame in 8:
        await process_frame
    await click(editor._search.get_global_rect().get_center())
    for character in "delay":
        var typed := InputEventKey.new()
        typed.keycode = character.to_upper().unicode_at(0)
        typed.physical_keycode = typed.keycode
        typed.unicode = character.unicode_at(0)
        typed.pressed = true
        Input.parse_input_event(typed)
        await process_frame
        typed.pressed = false
        Input.parse_input_event(typed)
    await process_frame
    assert(editor._search.text == "delay")
    var delay_button: Button
    for button in editor._palette.find_children("*", "Button", true, false):
        if button.text == "Delay":
            delay_button = button
    assert(delay_button != null)
    await click(delay_button.get_global_rect().get_center())
    var delay: String = editor.selected_id
    assert(editor.document.records[delay].type == "delay", "Palette click added the wrong processor")
    editor.blocks[delay].position_offset = Vector2(650, 630)
    editor.document.commit_history()
    editor._search.text = ""
    editor._populate_palette()
    editor.fit_graph()
    for _frame in 4:
        await process_frame
    var a: GraphNode = editor.blocks.tone
    var b: GraphNode = editor.blocks[delay]
    var from: Vector2 = a.get_global_transform_with_canvas() * a.get_output_port_position(0)
    var to: Vector2 = b.get_global_transform_with_canvas() * b.get_input_port_position(b.input_for())
    await drag(from, to)
    assert(editor.document.network.get_connections().size() == 4, "Mouse drag did not create a native audio connection")
    a = editor.blocks.tone
    b = editor.blocks[delay]
    from = a.get_global_transform_with_canvas() * a.get_output_port_position(0)
    to = b.get_global_transform_with_canvas() * b.get_input_port_position(b.input_for())
    var local_from: Vector2 = editor.graph.get_global_transform_with_canvas().affine_inverse() * from
    var local_to: Vector2 = editor.graph.get_global_transform_with_canvas().affine_inverse() * to
    var line: PackedVector2Array = editor.graph.get_connection_line(local_from, local_to)
    var middle: Vector2 = editor.graph.get_global_transform_with_canvas() * line[line.size() / 2]
    await click(middle)
    assert(editor.selected_link.get("source", "") == "tone" and editor.selected_link.get("destination", "") == delay, "Cable picking did not open its inspector")
    var spins: Array[Node] = editor._inspector.find_children("*", "SpinBox", true, false)
    assert(spins.size() == 1)
    spins[0].value = 0.25
    var apply: Button
    for button in editor._inspector.find_children("*", "Button", true, false):
        if button.text == "Apply connection settings":
            apply = button
    assert(apply != null)
    await click(apply.get_global_rect().get_center())
    var found := false
    for edge in editor.document.network.get_connections():
        if edge.source == "tone" and edge.destination == delay:
            assert(edge.gain == 0.25)
            found = true
    assert(found, "Connection disappeared during inspector update")
    var block: GraphNode = editor.blocks[delay]
    await click(block.get_titlebar_hbox().get_global_rect().get_center())
    await key(KEY_DELETE)
    assert(not editor.document.records.has(delay), "Delete key did not delete the selected processor")
    await key(KEY_Z, true)
    assert(editor.document.records.has(delay), "Ctrl+Z did not restore the deleted processor")
    block = editor.blocks.filter
    await click(block.get_titlebar_hbox().get_global_rect().get_center())
    assert(editor.selected_id == "filter")
    var slider: HSlider = editor._parameter_controls.frequency.slider
    var old_value: float = editor.document.network.get_parameters("filter").frequency
    await click(slider.get_global_rect().position + Vector2(slider.size.x * 0.32, slider.size.y * 0.5))
    assert(editor.document.network.get_parameters("filter").frequency != old_value, "Inspector slider did not update the native parameter")
    editor._flush_parameter_history()
    var external := Button.new()
    external.text = "Host control outside the graph"
    root.add_child(external)
    external.grab_focus()
    var history_before: int = editor.document._cursor
    await key(KEY_Z, true)
    assert(editor.document._cursor == history_before, "Graph shortcuts intercepted another host control's input")
    external.free()
    var capture_path := OS.get_environment("JUCE_GRAPH_CAPTURE")
    if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
        editor.new_network("filter")
        editor.inspect_node("filter")
        for _frame in 5:
            await process_frame
        await RenderingServer.frame_post_draw
        assert(root.get_texture().get_image().save_png(capture_path) == OK)
    editor.free()
    print("JUCE graph interactions: mouse wiring, cable picking, connection settings, Delete, Ctrl+Z and live parameter controls passed")
    quit(0)

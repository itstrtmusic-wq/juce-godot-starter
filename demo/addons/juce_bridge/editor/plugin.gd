@tool
extends EditorPlugin

const GraphScene = preload("res://addons/juce_bridge/editor/graph_editor.tscn")
var _panel: Control

func _enter_tree() -> void:
    _panel = GraphScene.instantiate()
    _panel.name = "JUCEGraphMainScreen"
    _panel.set_meta("plugin_host", true)
    _panel.enable_recovery = true
    _panel.recovery_name = "juce_graph_editor_recovery.json"
    get_editor_interface().get_editor_main_screen().add_child(_panel)
    _panel.hide()

func _has_main_screen() -> bool:
    return true

func _get_plugin_name() -> String:
    return "JUCE Graph"

func _get_plugin_icon() -> Texture2D:
    return get_editor_interface().get_base_control().get_theme_icon("VisualShader", "EditorIcons")

func _make_visible(visible: bool) -> void:
    if is_instance_valid(_panel):
        _panel.visible = visible
        if not visible:
            _panel.stop_preview()

func _get_unsaved_status(_for_scene: String) -> String:
    if is_instance_valid(_panel) and _panel.document.is_dirty():
        return "JUCE Graph has unsaved changes. Save to the current file, or preserve an unnamed graph in recovery."
    return ""

func _save_external_data() -> void:
    if not is_instance_valid(_panel) or not _panel.document.is_dirty():
        return
    if _panel.document.current_path.is_empty() or not _panel.document.save_file(_panel.document.current_path, true):
        _panel.save_recovery()

func _exit_tree() -> void:
    if is_instance_valid(_panel):
        _panel.save_recovery()
        _panel.stop_preview()
        _panel.get_parent().remove_child(_panel)
        _panel.queue_free()

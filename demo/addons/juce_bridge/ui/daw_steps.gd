extends Control

signal step_clicked(step: int)
var clip: RefCounted
var channel := 1
var beat := -1.0

func _ready() -> void:
    custom_minimum_size = Vector2(304, 25)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        step_clicked.emit(clampi(floori(event.position.x / (size.x / 16)), 0, 15))
        accept_event()

func _draw() -> void:
    var width := size.x / 16
    for step in 16:
        var active := false
        if clip != null:
            for note in clip.notes:
                if note.channel == channel and absf(note.start - step * 0.25) < 0.001:
                    active = true
                    break
        var rect := Rect2(step * width + 2, 3, width - 4, size.y - 6)
        var fill := Color("b18466") if active else (Color("61686a") if step / 4 % 2 == 0 else Color("4b5358"))
        draw_style_box(preload("res://addons/juce_bridge/ui/daw_theme.gd").box(fill, Color("2b3337"), 2), rect)
        draw_line(rect.position + Vector2(2, 1), rect.position + Vector2(rect.size.x - 2, 1), fill.lightened(0.2))
        if beat >= 0 and int(fposmod(beat, 4) * 4) == step:
            draw_rect(Rect2(step * width + 2, size.y - 3, width - 4, 2), Color("edb46f"))

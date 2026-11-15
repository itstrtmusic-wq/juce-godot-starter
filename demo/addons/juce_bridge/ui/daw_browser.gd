extends Tree

func _get_drag_data(_point: Vector2) -> Variant:
    var item := get_selected()
    if item == null:
        return null
    var data: Variant = item.get_metadata(0)
    if not data is Dictionary or data.get("kind") != "pattern":
        return null
    var label := Label.new()
    label.text = item.get_text(0)
    set_drag_preview(label)
    return data.duplicate()

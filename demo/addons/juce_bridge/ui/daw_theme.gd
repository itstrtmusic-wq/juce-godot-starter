extends RefCounted

const BG := Color("292e32")
const PANEL := Color("3d464d")
const DARK := Color("202629")
const TEXT := Color("d3d8d9")
const MUTED := Color("929fa5")
const ORANGE := Color("e7a35d")
const GREEN := Color("a4cb7c")
const COLORS := ["bd7959", "bfa574", "a6b67d", "8ab6a2", "779ba9", "8d90b6", "a384a6", "b69090"]

static func box(color: Color, border := Color("252b2e"), radius := 3) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 7
    style.content_margin_right = 7
    style.content_margin_top = 3
    style.content_margin_bottom = 3
    return style

static func create() -> Theme:
    var theme := Theme.new()
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["Segoe UI", "Arial", "DejaVu Sans"])
    theme.default_font = font
    theme.default_font_size = 12
    for type in ["Label", "Button", "OptionButton", "MenuButton", "CheckButton", "SpinBox"]:
        theme.set_color("font_color", type, TEXT)
    for type in ["Button", "OptionButton", "MenuButton"]:
        theme.set_stylebox("normal", type, box(Color("475159")))
        theme.set_stylebox("hover", type, box(Color("56616a")))
        theme.set_stylebox("pressed", type, box(Color("646e72"), ORANGE))
        theme.set_stylebox("focus", type, StyleBoxEmpty.new())
        theme.set_color("font_pressed_color", type, ORANGE)
        theme.set_color("font_hover_color", type, Color.WHITE)
    theme.set_stylebox("panel", "PanelContainer", box(PANEL))
    theme.set_stylebox("normal", "LineEdit", box(DARK))
    theme.set_stylebox("focus", "LineEdit", box(DARK, ORANGE))
    theme.set_color("font_color", "LineEdit", TEXT)
    theme.set_stylebox("panel", "Tree", box(Color("30383d")))
    theme.set_stylebox("selected", "Tree", box(Color("505d63"), Color("505d63")))
    theme.set_stylebox("selected_focus", "Tree", box(Color("505d63"), ORANGE))
    theme.set_color("font_color", "Tree", TEXT)
    for type in ["HScrollBar", "VScrollBar"]:
        theme.set_stylebox("scroll", type, box(Color("262d31")))
        theme.set_stylebox("grabber", type, box(Color("626f75")))
        theme.set_stylebox("grabber_highlight", type, box(Color("7a878c")))
    theme.set_stylebox("background", "ProgressBar", box(DARK))
    theme.set_stylebox("fill", "ProgressBar", box(GREEN, GREEN, 1))
    var handle := GradientTexture2D.new()
    handle.width = 18
    handle.height = 9
    handle.gradient = Gradient.new()
    handle.gradient.colors = PackedColorArray([Color("c4cdcf"), Color("77858b")])
    handle.fill_from = Vector2.ZERO
    handle.fill_to = Vector2(0, 1)
    theme.set_icon("grabber", "VSlider", handle)
    theme.set_icon("grabber_highlight", "VSlider", handle)
    theme.set_color("background", "DawPianoRoll", Color("252d31"))
    theme.set_color("white_row", "DawPianoRoll", Color("353f44"))
    theme.set_color("black_row", "DawPianoRoll", Color("2e373b"))
    theme.set_color("line", "DawPianoRoll", Color("404b50"))
    theme.set_color("bar_line", "DawPianoRoll", Color("59646a"))
    theme.set_color("ruler", "DawPianoRoll", Color("414d53"))
    theme.set_color("note", "DawPianoRoll", Color("a6cd8b"))
    return theme

static func label(text: String, size := 12, color := TEXT) -> Label:
    var node := Label.new()
    node.text = text
    node.add_theme_font_size_override("font_size", size)
    node.add_theme_color_override("font_color", color)
    return node

static func button(text: String, action: Callable, tip := "") -> Button:
    var node := Button.new()
    node.text = text
    node.tooltip_text = tip
    node.focus_mode = Control.FOCUS_NONE
    node.custom_minimum_size.y = 25
    node.pressed.connect(func():
        var focused := node.get_viewport().gui_get_focus_owner()
        if focused is LineEdit and focused.get_parent() is SpinBox:
            focused.get_parent().apply()
        if focused is LineEdit or focused is SpinBox:
            focused.release_focus()
        action.call()
    )
    return node

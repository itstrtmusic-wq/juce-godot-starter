@tool
extends RefCounted

const BG := Color("10151f")
const PANEL := Color("171e2b")
const FIELD := Color("202a3a")
const LINE := Color("303e53")
const TEXT := Color("e0e7f3")
const MUTED := Color("91a0b7")
const AUDIO := Color("71e6c4")
const CONTROL := Color("baa0ff")
const ERROR := Color("ff8892")

static func box(color: Color, border := Color.TRANSPARENT, radius := 6, padding := 10) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = color
    style.border_color = border
    style.set_border_width_all(1 if border.a > 0 else 0)
    style.set_corner_radius_all(radius)
    style.content_margin_left = padding
    style.content_margin_right = padding
    style.content_margin_top = padding
    style.content_margin_bottom = padding
    return style

static func create() -> Theme:
    var theme := Theme.new()
    theme.default_font_size = 14
    theme.set_color("font_color", "Label", TEXT)
    theme.set_color("font_color", "Button", TEXT)
    theme.set_color("font_hover_color", "Button", Color.WHITE)
    theme.set_color("font_disabled_color", "Button", Color("5d6a80"))
    for type in ["Button", "OptionButton", "MenuButton"]:
        theme.set_stylebox("normal", type, box(FIELD, LINE, 6, 9))
        theme.set_stylebox("hover", type, box(Color("2b3a4d"), Color("52677f"), 6, 9))
        theme.set_stylebox("pressed", type, box(Color("254c45"), AUDIO, 6, 9))
        theme.set_stylebox("disabled", type, box(Color("1a2230"), Color("263042"), 6, 9))
        theme.set_stylebox("focus", type, box(Color.TRANSPARENT, AUDIO, 6, 9))
    theme.set_stylebox("normal", "LineEdit", box(Color("101824"), LINE, 5, 9))
    theme.set_stylebox("focus", "LineEdit", box(Color("152332"), AUDIO, 5, 9))
    theme.set_color("font_color", "LineEdit", TEXT)
    theme.set_color("font_placeholder_color", "LineEdit", MUTED)
    theme.set_color("caret_color", "LineEdit", AUDIO)
    theme.set_color("font_color", "CheckButton", TEXT)
    theme.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 8, 8))
    theme.set_color("font_color", "PopupMenu", TEXT)
    theme.set_stylebox("hover", "PopupMenu", box(FIELD, Color.TRANSPARENT, 4, 6))
    theme.set_stylebox("panel", "AcceptDialog", box(PANEL, LINE, 9, 14))
    theme.set_stylebox("panel", "GraphEdit", box(BG, LINE, 8, 0))
    theme.set_stylebox("menu_panel", "GraphEdit", box(Color("182130"), LINE, 6, 6))
    theme.set_color("grid_major", "GraphEdit", Color("2a3446"))
    theme.set_color("grid_minor", "GraphEdit", Color("1b2535"))
    theme.set_stylebox("background", "ProgressBar", box(Color("0d1420"), LINE, 3, 0))
    theme.set_stylebox("fill", "ProgressBar", box(AUDIO, Color.TRANSPARENT, 3, 0))
    theme.set_stylebox("slider", "HSlider", box(Color("2d394e"), Color.TRANSPARENT, 2, 2))
    theme.set_stylebox("grabber_area", "HSlider", box(AUDIO, Color.TRANSPARENT, 2, 2))
    theme.set_stylebox("grabber_area_highlight", "HSlider", box(AUDIO.lightened(0.2), Color.TRANSPARENT, 2, 2))
    return theme

static func node_style(accent: Color, selected: bool) -> StyleBoxFlat:
    var style := box(Color("1b2636"), accent if selected else Color("3c4d65"), 8, 12)
    style.border_width_left = 3
    if not selected:
        style.border_color = accent.darkened(0.35)
    style.shadow_color = Color(0, 0, 0, 0.3)
    style.shadow_size = 5
    return style

static func label(text: String, size := 14, color := TEXT) -> Label:
    var result := Label.new()
    result.text = text
    result.add_theme_font_size_override("font_size", size)
    result.add_theme_color_override("font_color", color)
    return result

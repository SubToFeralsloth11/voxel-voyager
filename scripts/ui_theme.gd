class_name UiTheme
## Builds the shared dark sci-fi UI theme in code.

const ACCENT := Color(0.35, 0.9, 1.0)
const PANEL := Color(0.04, 0.06, 0.1, 0.86)


static func panel_style(border := ACCENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(14)
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.1, 0.16, 0.24)
	normal.border_color = Color(0.25, 0.5, 0.65)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(3)
	normal.set_content_margin_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.28, 0.4)
	hover.border_color = ACCENT
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.2, 0.45, 0.6)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.08, 0.09, 0.12)
	disabled.border_color = Color(0.2, 0.22, 0.26)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.85, 0.95, 1.0))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.45, 0.5))
	t.set_color("font_color", "Label", Color(0.88, 0.95, 1.0))
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 4)
	return t


static func bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(220, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	return b


static func label(text := "", size := 17, color := Color(0.88, 0.95, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

class_name GalaxyMap
extends Control
## Galaxy map overlay: shows nearby stars, warp range, visited systems and
## the Architect's Core signal. Click a star to select it, then warp.

const VIEW_RADIUS := 8
const CELL_PX := 58.0

var world: World
var selected := Vector2i.ZERO
var _info: Label
var _warp_button: Button
var _error: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -330
	panel.offset_top = 20
	panel.offset_right = -20
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(290, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(UiTheme.label("GALAXY MAP", 22, UiTheme.ACCENT))
	_info = UiTheme.label("", 15)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	_error = UiTheme.label("", 14, Color(1.0, 0.6, 0.45))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_error)
	_warp_button = Button.new()
	_warp_button.text = "ENGAGE WARP"
	_warp_button.custom_minimum_size = Vector2(0, 42)
	_warp_button.pressed.connect(_on_warp)
	box.add_child(_warp_button)
	var close_b := Button.new()
	close_b.text = "Close  [G / Esc]"
	close_b.pressed.connect(func() -> void: world.close_map())
	box.add_child(close_b)


func open() -> void:
	selected = Game.system_cell
	visible = true
	_update_panel()


func close() -> void:
	visible = false


func _to_screen(cell_pos: Vector2) -> Vector2:
	var origin := Galaxy.star_pos(Game.system_cell)
	return size * 0.5 - Vector2(160, 0) + (cell_pos - origin) * CELL_PX


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click: Vector2 = event.position
		var best_d := 18.0
		for cell in Galaxy.systems_near(Game.system_cell, VIEW_RADIUS):
			var d := click.distance_to(_to_screen(Galaxy.star_pos(cell)))
			if d < best_d:
				best_d = d
				selected = cell
				Sfx.play("ui")
		_update_panel()
		accept_event()


func _update_panel() -> void:
	var name := Galaxy.system_name(selected)
	var core_locked := selected == Galaxy.CORE_CELL and Game.fragments.size() < Game.FRAGMENTS_NEEDED
	if core_locked:
		name = "Unknown Signal"
	var lines := [name]
	if selected == Game.system_cell:
		lines.append("You are here.")
	else:
		lines.append("Distance: %.1f ly" % Galaxy.distance(Game.system_cell, selected))
	if Game.visited.has(Galaxy.cell_key(selected)):
		var data := Galaxy.system_data(selected)
		lines.append("Planets: %d    Visited" % data["planets"].size())
	elif core_locked:
		lines.append("A faint, structured signal. Decode %d more beacons to resolve it." % (Game.FRAGMENTS_NEEDED - Game.fragments.size()))
	else:
		lines.append("Unexplored")
	lines.append("")
	lines.append("Warp range: %s" % ("%.1f ly" % Game.warp_range() if Game.warp_range() > 0.0 else "no warp drive"))
	lines.append("Fuel: %d / %d  (warp costs %d)" % [int(Game.fuel), int(Game.max_fuel()), int(Game.WARP_FUEL_COST)])
	_info.text = "\n".join(lines)
	var err := world.warp_error(selected)
	_error.text = err
	_warp_button.disabled = err != ""
	queue_redraw()


func _on_warp() -> void:
	var err := world.warp_to(selected)
	_error.text = err


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.04, 0.94))
	var font := get_theme_default_font()
	var here := Galaxy.star_pos(Game.system_cell)
	var here_px := _to_screen(here)
	if Game.warp_range() > 0.0:
		draw_circle(here_px, Game.warp_range() * CELL_PX, Color(0.3, 0.8, 1.0, 0.07))
		draw_arc(here_px, Game.warp_range() * CELL_PX, 0, TAU, 96, Color(0.3, 0.8, 1.0, 0.5), 1.5)
	var cells := Galaxy.systems_near(Game.system_cell, VIEW_RADIUS)
	var core_known := Game.fragments.size() >= Game.FRAGMENTS_NEEDED
	for cell in cells:
		var p := _to_screen(Galaxy.star_pos(cell))
		var col := Color(0.55, 0.6, 0.7)
		var r := 4.0
		if Game.visited.has(Galaxy.cell_key(cell)):
			col = Color(0.5, 1.0, 0.7)
		if cell == Galaxy.CORE_CELL:
			col = Color(1.0, 0.8, 0.3) if core_known else Color(0.85, 0.5, 1.0)
			r = 6.0
			draw_arc(p, 12.0 + 3.0 * sin(Time.get_ticks_msec() / 300.0), 0, TAU, 32, col, 1.5)
		draw_circle(p, r, col)
		if cell == selected:
			draw_arc(p, 11.0, 0, TAU, 32, Color.WHITE, 2.0)
		var label := Galaxy.system_name(cell)
		if cell == Galaxy.CORE_CELL and not core_known:
			label = "???"
		draw_string(font, p + Vector2(8, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.darkened(0.1))
	draw_arc(here_px, 9.0, 0, TAU, 32, Color(0.3, 0.9, 1.0), 2.5)
	if selected != Game.system_cell:
		draw_dashed_line(here_px, _to_screen(Galaxy.star_pos(selected)), Color(1, 1, 1, 0.5), 1.5, 6.0)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## The tree is paused while the map is open, so the map closes itself.
func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("galaxy_map")):
		get_viewport().set_input_as_handled()
		world.close_map()

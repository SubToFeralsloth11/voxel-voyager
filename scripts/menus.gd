class_name Menus
extends Control
## Title screen, pause menu and ending screen.

var world: World
var _title: Control
var _pause: Control
var _ending: Control
var _continue: Button
var _ending_stats: Label
var _sens: HSlider
var _title_error: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = _build_title()
	_pause = _build_pause()
	_ending = _build_ending()
	hide_all()


func _center_panel(width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(width, 0)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	return box


func _button(box: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(func() -> void:
		Sfx.play("ui")
		action.call())
	box.add_child(b)
	return b


func _build_title() -> Control:
	var box := _center_panel(420)
	var t := UiTheme.label("VOXEL VOYAGER", 44, UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var s := UiTheme.label("a tiny-planet space adventure", 16, Color(0.75, 0.85, 1.0))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(s)
	box.add_child(HSeparator.new())
	_button(box, "New Game", world.start_new_game)
	_continue = _button(box, "Continue", world.continue_game)
	_button(box, "Quit", func() -> void: get_tree().quit())
	_title_error = UiTheme.label("", 15, Color(1.0, 0.5, 0.45))
	_title_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_error)
	return box.get_parent()


func _build_pause() -> Control:
	var box := _center_panel(380)
	var t := UiTheme.label("PAUSED", 32, UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	_button(box, "Resume", world.resume)
	_button(box, "Save game", func() -> void:
		var ok := Game.save_game()
		Game.notify("Game saved." if ok else "Save failed!", Color(0.6, 1.0, 0.7) if ok else Color(1, 0.4, 0.4)))
	_button(box, "Toggle controls help", world.hud.toggle_help)
	box.add_child(UiTheme.label("Mouse sensitivity", 15))
	_sens = HSlider.new()
	_sens.min_value = 0.0008
	_sens.max_value = 0.006
	_sens.step = 0.0001
	_sens.value_changed.connect(func(v: float) -> void: Game.mouse_sensitivity = v)
	box.add_child(_sens)
	_button(box, "Quit to title", world.quit_to_title)
	return box.get_parent()


func _build_ending() -> Control:
	var box := _center_panel(560)
	var t := UiTheme.label("THE ARCHITECT'S CORE", 34, Color(1.0, 0.85, 0.35))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var story := UiTheme.label("The monolith wakes. Five fragments sing in harmony and the core of the galaxy opens to you: a map of every world the Architects ever built. Your voyage is just beginning.", 16)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(story)
	_ending_stats = UiTheme.label("", 15, Color(0.75, 0.9, 1.0))
	_ending_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_ending_stats)
	_button(box, "Keep exploring", func() -> void:
		hide_all()
		world.resume_after_ending())
	_button(box, "Quit to title", world.quit_to_title)
	return box.get_parent()


func hide_all() -> void:
	_title.visible = false
	_pause.visible = false
	_ending.visible = false


func show_title() -> void:
	hide_all()
	_continue.disabled = not Game.has_save()
	_title_error.text = ""
	_title.visible = true


func show_title_error(text: String) -> void:
	_title_error.text = text


func show_pause() -> void:
	hide_all()
	_sens.set_value_no_signal(Game.mouse_sensitivity)
	_pause.visible = true


func show_ending() -> void:
	hide_all()
	_ending_stats.text = "Systems visited: %d    Blocks mined: %d\nAsteroids cracked: %d    Drones destroyed: %d    Credits: %d" % [
		Game.visited.size(), Game.blocks_mined, Game.asteroids_destroyed, Game.drones_destroyed, Game.credits]
	_ending.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if _pause.visible and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		world.resume()

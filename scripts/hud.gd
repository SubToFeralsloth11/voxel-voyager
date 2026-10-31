class_name Hud
extends Control
## In-flight / on-foot heads-up display: status bars, cargo, navigation
## markers, crosshair, context prompts, notifications and the help panel.

const HELP_TEXT := """[b]SHIP[/b]
Mouse - steer    W/S - thrust    A/D - strafe
Space/Ctrl - up/down    Q/E - roll    Shift - boost
Left click - laser (crack asteroids, fight drones)
R (hold, aim at planet) - scan    G - galaxy map
F - dock at outpost / step outside when landed

[b]ON FOOT[/b]
WASD - walk    Shift - sprint    Space - jump / jetpack
Left click (hold) - mine    Right click - build (uses stone)
F - board ship / activate beacon

[b]GOAL[/b]  Mine and sell ore, upgrade your ship, buy a warp
drive and decode 5 ancient beacons to find the Architect's Core.
H - toggle this help    Esc - pause"""

var world: World

var _info: Label
var _cargo: Label
var _nav: Label
var _prompt: Label
var _status_title: Label
var _bar1: ProgressBar
var _bar2: ProgressBar
var _bar3: ProgressBar
var _bar1_label: Label
var _bar2_label: Label
var _bar3_label: Label
var _notes: VBoxContainer
var _help: PanelContainer
var _progress: ProgressBar
var _flash: ColorRect
var _help_timer := 0.0
var _message_cooldown := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top_left := VBoxContainer.new()
	_place(top_left, Control.PRESET_TOP_LEFT, Vector2(18, 14))
	add_child(top_left)
	_info = UiTheme.label("", 20, Color(1.0, 0.9, 0.5))
	top_left.add_child(_info)
	_cargo = UiTheme.label("", 16)
	top_left.add_child(_cargo)

	var bottom_left := VBoxContainer.new()
	_place(bottom_left, Control.PRESET_BOTTOM_LEFT, Vector2(18, -150))
	bottom_left.add_theme_constant_override("separation", 3)
	add_child(bottom_left)
	_status_title = UiTheme.label("SHIP", 15, UiTheme.ACCENT)
	bottom_left.add_child(_status_title)
	_bar1_label = UiTheme.label("", 14)
	_bar1 = UiTheme.bar(Color(0.4, 0.9, 0.5))
	_bar2_label = UiTheme.label("", 14)
	_bar2 = UiTheme.bar(Color(1.0, 0.7, 0.25))
	_bar3_label = UiTheme.label("", 14)
	_bar3 = UiTheme.bar(Color(0.4, 0.75, 1.0))
	for n: Control in [_bar1_label, _bar1, _bar2_label, _bar2, _bar3_label, _bar3]:
		bottom_left.add_child(n)

	_nav = UiTheme.label("", 16)
	_nav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_nav, Control.PRESET_TOP_RIGHT, Vector2(-420, 14), Vector2(400, 120))
	add_child(_nav)

	_prompt = UiTheme.label("", 20, Color(1, 1, 1))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt, Control.PRESET_CENTER_BOTTOM, Vector2(-400, -110), Vector2(800, 30))
	add_child(_prompt)

	_progress = UiTheme.bar(UiTheme.ACCENT)
	_progress.custom_minimum_size = Vector2(120, 8)
	_place(_progress, Control.PRESET_CENTER, Vector2(-60, 30), Vector2(120, 8))
	_progress.max_value = 1.0
	add_child(_progress)

	_notes = VBoxContainer.new()
	_place(_notes, Control.PRESET_CENTER_TOP, Vector2(-380, 16), Vector2(760, 0))
	_notes.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_notes)
	Game.notified.connect(_on_notified)

	_help = PanelContainer.new()
	_place(_help, Control.PRESET_CENTER_RIGHT, Vector2(-490, -200))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(440, 0)
	rt.text = HELP_TEXT
	rt.add_theme_font_size_override("normal_font_size", 14)
	rt.add_theme_font_size_override("bold_font_size", 15)
	_help.add_child(rt)
	_help.visible = false
	add_child(_help)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.8, 0.95, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)


func _place(c: Control, preset: Control.LayoutPreset, pos: Vector2, sz := Vector2.ZERO) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y


func show_help(auto_hide: bool) -> void:
	_help.visible = true
	_help_timer = 14.0 if auto_hide else 0.0


func toggle_help() -> void:
	_help.visible = not _help.visible
	_help_timer = 0.0


func warp_flash() -> void:
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 1.0, 0.9)
	tween.tween_property(_flash, "color:a", 0.0, 0.8)


func flash_message(text: String, color: Color) -> void:
	if _message_cooldown > 0.0:
		return
	_message_cooldown = 2.5
	Game.notify(text, color)


func _on_notified(text: String, color: Color) -> void:
	var l := UiTheme.label(text, 17, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(760, 0)
	_notes.add_child(l)
	while _notes.get_child_count() > 4:
		var old := _notes.get_child(0)
		_notes.remove_child(old)
		old.queue_free()
	var tween := l.create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(l, "modulate:a", 0.0, 1.0)
	tween.tween_callback(l.queue_free)


func _process(delta: float) -> void:
	_message_cooldown -= delta
	if _help_timer > 0.0:
		_help_timer -= delta
		if _help_timer <= 0.0:
			_help.visible = false
	if world == null or world.ship == null:
		return
	_info.text = "%d cr    Fragments %d/%d" % [Game.credits, Game.fragments.size(), Game.FRAGMENTS_NEEDED]
	var parts := []
	for ore: String in Game.ORE_ORDER:
		if Game.cargo.has(ore):
			parts.append("%s %d" % [Game.ORES[ore]["name"], Game.cargo[ore]])
	_cargo.text = "Cargo %d/%d   %s" % [Game.cargo_count(), Game.cargo_capacity(), "  ".join(parts)]
	_prompt.text = world.prompt_text()
	var on_foot := world.mode == World.Mode.FOOT and world.player != null
	if on_foot:
		var pl := world.player
		_status_title.text = "SUIT"
		_set_bar(_bar1, _bar1_label, "Health", pl.health, 100.0)
		_set_bar(_bar2, _bar2_label, "Oxygen" + (" (breathable)" if pl.planet and pl.planet.breathable else ""), pl.oxygen, Player.MAX_OXYGEN)
		_set_bar(_bar3, _bar3_label, "Jetpack", pl.jet_fuel * 100.0, 100.0)
		_progress.visible = pl.mining_progress > 0.0
		_progress.value = pl.mining_progress
	else:
		_status_title.text = "SHIP"
		_set_bar(_bar1, _bar1_label, "Hull", Game.hull, Game.max_hull())
		_set_bar(_bar2, _bar2_label, "Fuel" + (" (EMPTY - emergency thrusters)" if Game.fuel <= 0.0 else ""), Game.fuel, Game.max_fuel())
		_bar3.visible = false
		_bar3_label.visible = false
		_progress.visible = world.scan_target != null
		_progress.value = world.scan_progress
	_bar3.visible = on_foot
	_bar3_label.visible = on_foot
	_nav.text = _nav_text()
	queue_redraw()


func _set_bar(bar: ProgressBar, label: Label, title: String, value: float, max_value: float) -> void:
	bar.max_value = max_value
	bar.value = value
	label.text = "%s  %d / %d" % [title, int(ceil(value)), int(max_value)]


func _nav_text() -> String:
	var lines := [world.system["name"]]
	var ship := world.ship
	if world.mode == World.Mode.FOOT and world.player:
		var p := world.player.planet
		if p:
			lines.append(p.planet_name)
			lines.append("Gravity %.1f" % p.surface_gravity)
		lines.append("Ship %.0f m" % world.player.global_position.distance_to(ship.global_position))
		return "\n".join(lines)
	lines.append("Speed %.0f m/s" % ship.velocity.length())
	var p := world.nearest_planet(ship.global_position)
	if p:
		lines.append("%s  alt %.0f m" % [p.planet_name, maxf(0.0, p.altitude(ship.global_position))])
	if world.scan_target:
		lines.append("Scanning %s..." % world.scan_target.planet_name)
	return "\n".join(lines)


func _draw() -> void:
	if world == null or world.ship == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := size * 0.5
	var cross_col := Color(1, 1, 1, 0.8)
	draw_line(center + Vector2(-8, 0), center + Vector2(-3, 0), cross_col, 2.0)
	draw_line(center + Vector2(3, 0), center + Vector2(8, 0), cross_col, 2.0)
	draw_line(center + Vector2(0, -8), center + Vector2(0, -3), cross_col, 2.0)
	draw_line(center + Vector2(0, 3), center + Vector2(0, 8), cross_col, 2.0)
	var on_foot := world.mode == World.Mode.FOOT
	for p in world.planets:
		if not on_foot:
			var col: Color = p.type_info["top"].lerp(Color.WHITE, 0.4)
			var tag := p.planet_name + (" [scanned]" if Game.scanned.has(p.key) else "")
			_marker(cam, p.global_position, tag, col, p.radius)
		if p.has_beacon and Game.scanned.has(p.key):
			var done := Game.fragments.has(p.key)
			var label := "Monolith" if p.is_core else ("Beacon (decoded)" if done else "Beacon")
			if not on_foot or world.player.planet == p:
				_marker(cam, p.beacon_world(), label, Color(1.0, 0.85, 0.3) if p.is_core else Color(0.3, 1.0, 0.85), 0.0)
	if not on_foot:
		_marker(cam, world.station.global_position, "Trade Outpost", Color(1.0, 0.7, 0.35), 0.0)
	else:
		_marker(cam, world.ship.global_position, "Ship", Color(0.6, 0.9, 1.0), 0.0)


func _marker(cam: Camera3D, pos: Vector3, text: String, col: Color, body_radius: float) -> void:
	var dist := cam.global_position.distance_to(pos) - body_radius
	var screen: Vector2
	var on_screen := not cam.is_position_behind(pos)
	if on_screen:
		screen = cam.unproject_position(pos)
		on_screen = Rect2(Vector2.ZERO, size).grow(-20).has_point(screen)
	if not on_screen:
		var local := cam.global_transform.affine_inverse() * pos
		var dir := Vector2(local.x, -local.y)
		if dir.length() < 0.001:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var half := size * 0.5 - Vector2(40, 40)
		var scale_to_edge := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
		screen = size * 0.5 + dir * scale_to_edge
	var font := get_theme_default_font()
	var s := 6.0
	var pts := PackedVector2Array([screen + Vector2(0, -s), screen + Vector2(s, 0), screen + Vector2(0, s), screen + Vector2(-s, 0), screen + Vector2(0, -s)])
	draw_polyline(pts, col, 2.0)
	var dist_text := "%.0f m" % maxf(dist, 0.0) if dist < 1000.0 else "%.1f km" % (dist / 1000.0)
	draw_string_outline(font, screen + Vector2(10, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	draw_string(font, screen + Vector2(10, -2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
	draw_string_outline(font, screen + Vector2(10, 13), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
	draw_string(font, screen + Vector2(10, 13), dist_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col.darkened(0.15))

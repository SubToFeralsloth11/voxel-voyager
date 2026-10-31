class_name ShopPanel
extends PanelContainer
## Trade outpost screen: sell cargo, refuel, repair and buy ship upgrades.

var world: World
var _body: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(640, 0)
	offset_left = -320
	offset_right = 320
	offset_top = -262
	offset_bottom = 338
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 8)
	add_child(_body)
	Game.changed.connect(_refresh)


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	visible = false


func _refresh() -> void:
	if not visible:
		return
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_body.add_child(UiTheme.label("TRADE OUTPOST - %s" % world.system["name"], 24, UiTheme.ACCENT))
	_body.add_child(UiTheme.label("Credits: %d cr" % Game.credits, 20, Color(1.0, 0.9, 0.5)))

	var cargo_row := HBoxContainer.new()
	var parts := []
	for ore: String in Game.ORE_ORDER:
		if Game.cargo.has(ore):
			parts.append("%s x%d" % [Game.ORES[ore]["name"], Game.cargo[ore]])
	var cargo_text := "Hold empty" if parts.is_empty() else ", ".join(parts)
	var cl := UiTheme.label("Cargo %d/%d: %s" % [Game.cargo_count(), Game.cargo_capacity(), cargo_text], 16)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cargo_row.add_child(cl)
	cargo_row.add_child(_button("Sell all (+%d cr)" % Game.cargo_value(), Game.cargo_count() > 0, _sell))
	_body.add_child(cargo_row)

	var service := HBoxContainer.new()
	service.add_theme_constant_override("separation", 10)
	service.add_child(_button("Refuel (%d cr)" % Game.refuel_cost(), Game.fuel < Game.max_fuel() and Game.credits > 0, _refuel))
	service.add_child(_button("Repair (%d cr)" % Game.repair_cost(), Game.hull < Game.max_hull() and Game.credits > 0, _repair))
	_body.add_child(service)
	_body.add_child(HSeparator.new())
	_body.add_child(UiTheme.label("SHIP UPGRADES", 18, UiTheme.ACCENT))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	for id: String in Game.UPGRADE_ORDER:
		var info: Dictionary = Game.UPGRADES[id]
		var lvl := Game.level(id)
		var max_lvl: int = info["max"]
		var name_l := UiTheme.label("%s  Lv %d/%d" % [info["name"], lvl, max_lvl], 16)
		name_l.custom_minimum_size = Vector2(230, 0)
		grid.add_child(name_l)
		var desc := UiTheme.label(info["desc"], 13, Color(0.7, 0.78, 0.85))
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(desc)
		if lvl >= max_lvl:
			grid.add_child(_button("MAX", false, func() -> void: pass))
		else:
			var cost := Game.upgrade_cost(id)
			grid.add_child(_button("%d cr" % cost, Game.credits >= cost, _buy.bind(id)))
	_body.add_child(grid)
	_body.add_child(HSeparator.new())
	var hint := "Warp drive range: %.1f ly" % Game.warp_range() if Game.warp_range() > 0.0 else "Tip: a Warp Drive lets you jump to other star systems (G)."
	_body.add_child(UiTheme.label(hint, 14, Color(0.7, 0.85, 1.0)))
	var undock := _button("Undock  [Esc]", true, world.undock)
	undock.custom_minimum_size = Vector2(0, 40)
	_body.add_child(undock)


func _button(text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(120, 0)
	b.pressed.connect(action)
	return b


func _sell() -> void:
	var earned := Game.sell_all()
	Sfx.play("sell")
	Game.notify("Sold cargo for %d cr." % earned, Color(1.0, 0.9, 0.5))


func _refuel() -> void:
	Game.refuel()
	Sfx.play("ui")


func _repair() -> void:
	Game.repair()
	Sfx.play("ui")


func _buy(id: String) -> void:
	if Game.buy_upgrade(id):
		Sfx.play("sell")
		Game.notify("Installed %s level %d." % [Game.UPGRADES[id]["name"], Game.level(id)], Color(0.6, 1.0, 0.7))

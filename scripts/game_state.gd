extends Node
## Global game state (autoload "Game"): economy, upgrades, progress,
## voxel edits per planet and save/load.

signal changed
signal notified(text: String, color: Color)

const SAVE_PATH := "user://voxel_voyager_save.json"
const SAVE_VERSION := 1
const WARP_FUEL_COST := 30.0
const FRAGMENTS_NEEDED := 5

const ORES := {
	"stone": {"name": "Stone", "value": 1, "color": Color(0.62, 0.62, 0.66)},
	"iron": {"name": "Iron", "value": 6, "color": Color(0.85, 0.55, 0.38)},
	"ice": {"name": "Ice", "value": 4, "color": Color(0.7, 0.92, 1.0)},
	"gold": {"name": "Gold", "value": 18, "color": Color(1.0, 0.82, 0.25)},
	"crystal": {"name": "Crystal", "value": 35, "color": Color(0.85, 0.45, 1.0)},
}
const ORE_ORDER := ["stone", "iron", "ice", "gold", "crystal"]

const UPGRADES := {
	"engine": {"name": "Ion Engines", "desc": "+25% thrust and top speed", "cost": 120, "max": 5},
	"tank": {"name": "Fuel Tanks", "desc": "+40 fuel capacity", "cost": 90, "max": 5},
	"hull": {"name": "Hull Plating", "desc": "+50 hull integrity", "cost": 110, "max": 5},
	"cargo": {"name": "Cargo Hold", "desc": "+25 cargo capacity", "cost": 80, "max": 5},
	"laser": {"name": "Mining Laser", "desc": "Faster mining, longer reach", "cost": 100, "max": 5},
	"warp": {"name": "Warp Drive", "desc": "Jump between stars; each level adds range", "cost": 350, "max": 4},
}
const UPGRADE_ORDER := ["engine", "tank", "hull", "cargo", "laser", "warp"]

var credits := 0
var cargo: Dictionary = {}
var upgrades: Dictionary = {}
var fuel := 100.0
var hull := 100.0
var fragments: Array = []
var scanned: Dictionary = {}
var visited: Dictionary = {}
var system_cell := Vector2i.ZERO
var edits: Dictionary = {}
var won := false
var blocks_mined := 0
var asteroids_destroyed := 0
var drones_destroyed := 0
var mouse_sensitivity := 0.0025


func _ready() -> void:
	_setup_input()
	new_game()


func _setup_input() -> void:
	var keys := {
		"forward": [KEY_W], "back": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"up": [KEY_SPACE], "down": [KEY_CTRL, KEY_C], "boost": [KEY_SHIFT],
		"roll_left": [KEY_Q], "roll_right": [KEY_E], "interact": [KEY_F],
		"scan": [KEY_R], "galaxy_map": [KEY_G, KEY_M], "help": [KEY_H], "pause": [KEY_ESCAPE],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for code: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "place": MOUSE_BUTTON_RIGHT}
	for action: String in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mev := InputEventMouseButton.new()
		mev.button_index = mouse[action]
		InputMap.action_add_event(action, mev)


func new_game() -> void:
	credits = 50
	cargo = {}
	upgrades = {}
	for id: String in UPGRADE_ORDER:
		upgrades[id] = 0
	fragments = []
	scanned = {}
	visited = {}
	system_cell = Vector2i.ZERO
	edits = {}
	won = false
	blocks_mined = 0
	asteroids_destroyed = 0
	drones_destroyed = 0
	fuel = max_fuel()
	hull = max_hull()
	changed.emit()


func notify(text: String, color := Color.WHITE) -> void:
	notified.emit(text, color)


# --- derived stats -----------------------------------------------------------

func level(id: String) -> int:
	return int(upgrades.get(id, 0))


func max_fuel() -> float:
	return 100.0 + 40.0 * level("tank")


func max_hull() -> float:
	return 100.0 + 50.0 * level("hull")


func cargo_capacity() -> int:
	return 30 + 25 * level("cargo")


func thrust_mult() -> float:
	return 1.0 + 0.25 * level("engine")


func laser_speed() -> float:
	return 1.0 + 0.45 * level("laser")


func laser_range() -> float:
	return 6.0 + 1.5 * level("laser")


## Warp range in galaxy-map cells; 0 means no warp drive installed.
func warp_range() -> float:
	var lvl := level("warp")
	return 0.0 if lvl == 0 else 1.9 + 1.1 * lvl


func upgrade_cost(id: String) -> int:
	return int(round(UPGRADES[id]["cost"] * pow(1.75, level(id))))


func cargo_count() -> int:
	var total := 0
	for ore: String in cargo:
		total += int(cargo[ore])
	return total


func cargo_value() -> int:
	var total := 0
	for ore: String in cargo:
		total += int(cargo[ore]) * int(ORES[ore]["value"])
	return total


func refuel_cost() -> int:
	return int(ceil((max_fuel() - fuel) * 0.5))


func repair_cost() -> int:
	return int(ceil((max_hull() - hull) * 0.8))


# --- mutations ---------------------------------------------------------------

## Adds ore to the hold, clamped to capacity. Returns how many were stored.
func add_cargo(ore: String, amount := 1) -> int:
	var stored := mini(amount, cargo_capacity() - cargo_count())
	if stored <= 0:
		return 0
	cargo[ore] = int(cargo.get(ore, 0)) + stored
	changed.emit()
	return stored


func take_cargo(ore: String, amount := 1) -> bool:
	if int(cargo.get(ore, 0)) < amount:
		return false
	cargo[ore] = int(cargo[ore]) - amount
	if cargo[ore] == 0:
		cargo.erase(ore)
	changed.emit()
	return true


func sell_all() -> int:
	var earned := cargo_value()
	credits += earned
	cargo = {}
	changed.emit()
	return earned


func buy_upgrade(id: String) -> bool:
	if level(id) >= int(UPGRADES[id]["max"]):
		return false
	var cost := upgrade_cost(id)
	if credits < cost:
		return false
	credits -= cost
	upgrades[id] = level(id) + 1
	if id == "tank":
		fuel += 40.0
	elif id == "hull":
		hull += 50.0
	changed.emit()
	return true


## Refuels as much as the player can afford. Returns credits spent.
func refuel() -> int:
	var units := minf(max_fuel() - fuel, credits / 0.5)
	var cost := int(ceil(units * 0.5))
	if units <= 0.0:
		return 0
	fuel = minf(max_fuel(), fuel + units)
	credits = maxi(0, credits - cost)
	changed.emit()
	return cost


## Repairs as much hull as the player can afford. Returns credits spent.
func repair() -> int:
	var units := minf(max_hull() - hull, credits / 0.8)
	var cost := int(ceil(units * 0.8))
	if units <= 0.0:
		return 0
	hull = minf(max_hull(), hull + units)
	credits = maxi(0, credits - cost)
	changed.emit()
	return cost


func use_fuel(amount: float) -> void:
	if amount <= 0.0:
		return
	fuel = maxf(0.0, fuel - amount)


func damage_hull(amount: float) -> void:
	hull = maxf(0.0, hull - amount)
	changed.emit()


func planet_edits(key: String) -> Dictionary:
	if not edits.has(key):
		edits[key] = {}
	return edits[key]


# --- save / load -------------------------------------------------------------

func has_save(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func save_game(path := SAVE_PATH) -> bool:
	var edit_out := {}
	for key: String in edits:
		var cells := {}
		var planet: Dictionary = edits[key]
		for c: Vector3i in planet:
			cells["%d,%d,%d" % [c.x, c.y, c.z]] = planet[c]
		if not cells.is_empty():
			edit_out[key] = cells
	var data := {
		"version": SAVE_VERSION,
		"credits": credits, "cargo": cargo, "upgrades": upgrades,
		"fuel": fuel, "hull": hull, "fragments": fragments,
		"scanned": scanned.keys(), "visited": visited.keys(),
		"system": [system_cell.x, system_cell.y], "edits": edit_out, "won": won,
		"stats": [blocks_mined, asteroids_destroyed, drones_destroyed],
		"sensitivity": mouse_sensitivity,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true


func load_game(path := SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		return false
	var d: Dictionary = parsed
	new_game()
	credits = int(d.get("credits", 0))
	for ore: String in d.get("cargo", {}):
		if ORES.has(ore):
			cargo[ore] = int(d["cargo"][ore])
	for id: String in d.get("upgrades", {}):
		if UPGRADES.has(id):
			upgrades[id] = clampi(int(d["upgrades"][id]), 0, int(UPGRADES[id]["max"]))
	fuel = clampf(float(d.get("fuel", max_fuel())), 0.0, max_fuel())
	hull = clampf(float(d.get("hull", max_hull())), 1.0, max_hull())
	fragments = Array(d.get("fragments", []))
	for k: String in d.get("scanned", []):
		scanned[k] = true
	for k: String in d.get("visited", []):
		visited[k] = true
	var sys: Array = d.get("system", [0, 0])
	system_cell = Vector2i(int(sys[0]), int(sys[1]))
	var edit_in: Dictionary = d.get("edits", {})
	for key: String in edit_in:
		var planet := {}
		for ck: String in edit_in[key]:
			var parts := ck.split(",")
			planet[Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))] = int(edit_in[key][ck])
		edits[key] = planet
	won = bool(d.get("won", false))
	var stats: Array = d.get("stats", [0, 0, 0])
	blocks_mined = int(stats[0])
	asteroids_destroyed = int(stats[1])
	drones_destroyed = int(stats[2])
	mouse_sensitivity = float(d.get("sensitivity", mouse_sensitivity))
	changed.emit()
	return true

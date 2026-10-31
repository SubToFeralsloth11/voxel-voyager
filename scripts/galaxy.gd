class_name Galaxy
## Deterministic procedural galaxy. Every star system is a pure function of
## its grid cell, so nothing about the universe needs to be saved.

const CORE_CELL := Vector2i(5, -4)
const STAR_CHANCE := 46

const PLANET_TYPES := {
	"verdant": {
		"label": "Verdant", "top": Color(0.36, 0.72, 0.3), "soil": Color(0.48, 0.33, 0.2),
		"rock": Color(0.46, 0.46, 0.5), "atmo": Color(0.45, 0.72, 1.0), "breathable": true,
		"ores": {"iron": 40, "gold": 8, "crystal": 3}, "lava": 0.0,
	},
	"desert": {
		"label": "Desert", "top": Color(0.92, 0.76, 0.46), "soil": Color(0.82, 0.56, 0.32),
		"rock": Color(0.62, 0.42, 0.3), "atmo": Color(1.0, 0.72, 0.42), "breathable": false,
		"ores": {"iron": 30, "gold": 22}, "lava": 0.0,
	},
	"frozen": {
		"label": "Frozen", "top": Color(0.93, 0.96, 1.0), "soil": Color(0.7, 0.86, 0.96),
		"rock": Color(0.5, 0.56, 0.68), "atmo": Color(0.75, 0.88, 1.0), "breathable": false,
		"ores": {"ice": 90, "iron": 15, "crystal": 6}, "lava": 0.0,
	},
	"volcanic": {
		"label": "Volcanic", "top": Color(0.2, 0.17, 0.18), "soil": Color(0.36, 0.16, 0.11),
		"rock": Color(0.26, 0.22, 0.23), "atmo": Color(1.0, 0.38, 0.16), "breathable": false,
		"ores": {"gold": 38, "iron": 22}, "lava": 0.12,
	},
	"crystal": {
		"label": "Crystalline", "top": Color(0.58, 0.42, 0.78), "soil": Color(0.36, 0.26, 0.52),
		"rock": Color(0.26, 0.21, 0.36), "atmo": Color(0.85, 0.5, 1.0), "breathable": false,
		"ores": {"crystal": 45, "gold": 10}, "lava": 0.0,
	},
	"barren": {
		"label": "Barren", "top": Color(0.64, 0.64, 0.62), "soil": Color(0.52, 0.52, 0.52),
		"rock": Color(0.4, 0.4, 0.43), "atmo": null, "breathable": false,
		"ores": {"iron": 55, "gold": 6}, "lava": 0.0,
	},
}
const TYPE_KEYS := ["verdant", "desert", "frozen", "volcanic", "crystal", "barren"]
const STAR_COLORS := [
	Color(1.0, 0.86, 0.55), Color(1.0, 0.62, 0.36), Color(0.72, 0.82, 1.0),
	Color(1.0, 1.0, 0.9), Color(1.0, 0.48, 0.42),
]
const SYLLABLES := [
	"ka", "lo", "ve", "ri", "zan", "tor", "mi", "qua", "sel", "dra", "nox", "bel",
	"ix", "or", "um", "tha", "ser", "vi", "kor", "ae", "lun", "pha", "gor", "eon",
]


## Deterministic non-negative integer hash of four ints.
static func hash4(a: int, b: int, c: int, d: int) -> int:
	var h := a * 374761393 + b * 668265263 + c * 2246822519 + d * 3266489917
	h = (h ^ (h >> 15)) * 2246822519
	h = (h ^ (h >> 13)) * 3266489917
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func cell_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func has_star(cell: Vector2i) -> bool:
	if cell == Vector2i.ZERO or cell == CORE_CELL:
		return true
	return hash4(cell.x, cell.y, 1, 99) % 100 < STAR_CHANCE


## Star position on the galaxy map, in cell units (jittered inside its cell).
static func star_pos(cell: Vector2i) -> Vector2:
	if cell == Vector2i.ZERO:
		return Vector2(0.5, 0.5)
	var jx := float(hash4(cell.x, cell.y, 2, 7) % 1000) / 1000.0
	var jy := float(hash4(cell.x, cell.y, 3, 7) % 1000) / 1000.0
	return Vector2(cell) + Vector2(0.2 + jx * 0.6, 0.2 + jy * 0.6)


static func distance(a: Vector2i, b: Vector2i) -> float:
	return star_pos(a).distance_to(star_pos(b))


static func systems_near(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if has_star(cell):
				out.append(cell)
	return out


static func make_name(seed_value: int, syllables: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var name := ""
	for i in syllables:
		name += SYLLABLES[rng.randi() % SYLLABLES.size()]
	return name.capitalize()


static func system_name(cell: Vector2i) -> String:
	if cell == Vector2i.ZERO:
		return "Sol Prima"
	if cell == CORE_CELL:
		return "The Architect's Core"
	return make_name(hash4(cell.x, cell.y, 5, 5), 2 + hash4(cell.x, cell.y, 6, 6) % 2)


static func planet_key(cell: Vector2i, index: int) -> String:
	return "%d,%d:%d" % [cell.x, cell.y, index]


## Full description of a star system. Positions are in world units with the
## star at the origin.
static func system_data(cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash4(cell.x, cell.y, 17, 3)
	var is_home := cell == Vector2i.ZERO
	var is_core := cell == CORE_CELL
	var data := {
		"cell": cell,
		"name": system_name(cell),
		"star_color": Color(0.8, 0.5, 1.0) if is_core else STAR_COLORS[rng.randi() % STAR_COLORS.size()],
		"star_radius": rng.randf_range(55.0, 85.0),
		"planets": [],
		"is_core": is_core,
	}
	var count := 1 if is_core else (4 if is_home else rng.randi_range(2, 5))
	var orbit: float = data["star_radius"] * 3.0 + 120.0
	for i in count:
		orbit += rng.randf_range(190.0, 290.0)
		var angle := rng.randf() * TAU
		var type: String
		if is_core:
			type = "crystal"
		elif is_home:
			type = ["verdant", "barren", "desert", "frozen"][i]
		else:
			type = TYPE_KEYS[rng.randi() % TYPE_KEYS.size()]
		var planet := {
			"index": i,
			"key": planet_key(cell, i),
			"name": "%s %s" % [data["name"], ["I", "II", "III", "IV", "V", "VI"][i]],
			"type": type,
			"radius": 44.0 if is_core else float(rng.randi_range(22, 40)),
			"pos": Vector3(cos(angle) * orbit, rng.randf_range(-40.0, 40.0), sin(angle) * orbit),
			"seed": hash4(cell.x, cell.y, i, 1234),
			"has_beacon": is_core or (is_home and (i == 0 or i == 2)) or (not is_home and rng.randf() < 0.55),
			"core": is_core,
		}
		data["planets"].append(planet)
	var first: Dictionary = data["planets"][0]
	var to_star: Vector3 = -(first["pos"] as Vector3).normalized()
	var side := to_star.cross(Vector3.UP).normalized()
	data["station_pos"] = first["pos"] + (side * 0.8 + to_star * 0.6).normalized() * (first["radius"] + 110.0)
	data["belt_radius"] = orbit + 170.0
	data["belt_count"] = 0 if is_core else (34 if is_home or rng.randf() < 0.65 else 0)
	data["drone_count"] = 0 if is_home or is_core else (rng.randi_range(2, 4) if rng.randf() < 0.7 else 0)
	return data

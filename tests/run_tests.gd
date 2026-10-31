extends Node
## Headless test suite, run as a scene so autoloads exist:
##   tests/run.sh   (wraps: godot --headless --path . res://tests/run_tests.tscn)

const TEST_SAVE := "user://test_save.json"

var _failures := 0
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: ", msg)


func game() -> Node:
	return get_node("/root/Game")


func _ready() -> void:
	test_galaxy_is_deterministic()
	test_home_system_layout()
	test_core_reachable_with_first_warp_drive()
	test_terrain_layers()
	test_mining_and_building()
	test_mining_into_hidden_chunk()
	test_cargo_and_economy()
	test_upgrades()
	test_save_load_roundtrip()
	print("%d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func test_galaxy_is_deterministic() -> void:
	var a := Galaxy.system_data(Vector2i(3, -2))
	var b := Galaxy.system_data(Vector2i(3, -2))
	check(a["name"] == b["name"], "system name stable")
	check(a["planets"].size() == b["planets"].size(), "planet count stable")
	for i in a["planets"].size():
		check(a["planets"][i]["pos"] == b["planets"][i]["pos"], "planet %d position stable" % i)
		check(a["planets"][i]["type"] == b["planets"][i]["type"], "planet %d type stable" % i)
	check(Galaxy.system_name(Vector2i(1, 1)) != Galaxy.system_name(Vector2i(2, 7)), "different systems get different names")


func test_home_system_layout() -> void:
	var home := Galaxy.system_data(Vector2i.ZERO)
	check(home["planets"].size() == 4, "home has 4 planets")
	check(home["planets"][0]["type"] == "verdant", "first home planet is verdant")
	var beacons := 0
	for p: Dictionary in home["planets"]:
		if p["has_beacon"]:
			beacons += 1
	check(beacons >= 2, "home has at least two beacons")
	check(home["belt_count"] > 0, "home has an asteroid belt")
	check(home["drone_count"] == 0, "home has no hostile drones")
	for p: Dictionary in home["planets"]:
		var d: float = (p["pos"] as Vector3).distance_to(home["station_pos"])
		check(d > p["radius"] + 60.0, "station clear of %s" % p["name"])


func test_core_reachable_with_first_warp_drive() -> void:
	game().upgrades["warp"] = 1
	var reach: float = game().warp_range()
	game().upgrades["warp"] = 0
	check(reach > 0.0, "level 1 warp has range")
	var frontier: Array[Vector2i] = [Vector2i.ZERO]
	var seen := {Vector2i.ZERO: true}
	var stars := Galaxy.systems_near(Vector2i.ZERO, 12)
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for s in stars:
			if not seen.has(s) and Galaxy.distance(cur, s) <= reach:
				seen[s] = true
				frontier.append(s)
	check(seen.has(Galaxy.CORE_CELL), "core system reachable by hopping with a level-1 warp drive")
	var beacon_planets := 0
	for s: Vector2i in seen:
		if s == Galaxy.CORE_CELL:
			continue
		for p: Dictionary in Galaxy.system_data(s)["planets"]:
			if p["has_beacon"]:
				beacon_planets += 1
	check(beacon_planets >= 5, "enough beacons reachable to collect 5 fragments")


func _make_planet(index := 0, radius_override := 0.0) -> VoxelPlanet:
	var data: Dictionary = Galaxy.system_data(Vector2i.ZERO)["planets"][index].duplicate()
	if radius_override > 0.0:
		data["radius"] = radius_override
		data["key"] = "test:big"
	game().edits.erase(data["key"])
	var planet := VoxelPlanet.new()
	planet.setup(data)
	add_child(planet)
	return planet


func _surface_cell(planet: VoxelPlanet, dir: Vector3i) -> Vector3i:
	var c := Vector3i.ZERO
	while planet.base_type(c + dir) != VoxelPlanet.Block.AIR:
		c += dir
	return c


func test_terrain_layers() -> void:
	var planet := _make_planet(1)
	check(planet.base_type(Vector3i.ZERO) == VoxelPlanet.Block.BEDROCK, "planet core is bedrock")
	check(planet.base_type(Vector3i(0, int(planet.radius * 2), 0)) == VoxelPlanet.Block.AIR, "space above is air")
	var top := _surface_cell(planet, Vector3i(1, 0, 0))
	var t := planet.base_type(top)
	check(t == VoxelPlanet.Block.TOP, "outermost solid block is topsoil (got %d)" % t)
	check(planet.base_type(top - Vector3i(5, 0, 0)) != VoxelPlanet.Block.TOP, "deeper blocks are not topsoil")
	var r := float(top.x)
	check(r > planet.radius - planet.amplitude - 1.0 and r < planet.radius + planet.amplitude + 1.0, "surface within terrain amplitude")
	planet.free()


func _chunk_vertex_count(planet: VoxelPlanet, cell: Vector3i) -> int:
	var cc := Vector3i(cell.x >> 4, cell.y >> 4, cell.z >> 4)
	var body := planet.get_node_or_null("Chunk_%d_%d_%d" % [cc.x, cc.y, cc.z])
	if body == null:
		return -1
	var mesh: ArrayMesh = (body.get_child(0) as MeshInstance3D).mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


func test_mining_and_building() -> void:
	var planet := _make_planet(0)
	var top := _surface_cell(planet, Vector3i(0, 0, 1))
	check(planet.mine(top) == VoxelPlanet.Block.AIR, "cannot mine before terrain is built")
	planet.build_now()
	check(planet.built, "planet reports built after build_now")
	var before := _chunk_vertex_count(planet, top)
	check(before > 0, "surface chunk has geometry")
	check(planet.mine(top) == VoxelPlanet.Block.TOP, "mining topsoil returns TOP")
	check(planet.get_block(top) == VoxelPlanet.Block.AIR, "mined block becomes air")
	check(planet.mine(top) == VoxelPlanet.Block.AIR, "mining air does nothing")
	check(_chunk_vertex_count(planet, top) != before, "chunk mesh rebuilt after mining")
	check(planet.place(top, VoxelPlanet.Block.BUILT), "can place into the hole")
	check(planet.get_block(top) == VoxelPlanet.Block.BUILT, "placed block is BUILT")
	check(not planet.place(top, VoxelPlanet.Block.BUILT), "cannot place into a filled cell")
	check(planet.mine(Vector3i.ZERO) == VoxelPlanet.Block.AIR, "bedrock is unminable")
	if planet.has_beacon:
		var bc: Vector3i = planet.beacon_cells.keys()[0]
		check(planet.mine(bc) == VoxelPlanet.Block.AIR, "beacon is unminable")
	check(game().edits[planet.key].has(top), "edit recorded in game state")
	planet.free()


func test_mining_into_hidden_chunk() -> void:
	var planet := _make_planet(1, 40.0)
	planet.build_now()
	var deep := Vector3i(0, 8, 0)
	var t := planet.get_block(deep)
	check(t != VoxelPlanet.Block.AIR, "deep cell is solid")
	check(_chunk_vertex_count(planet, deep) == -1, "fully buried chunk is not meshed up front")
	check(planet.mine(deep) == t, "mining a buried block returns its type")
	check(_chunk_vertex_count(planet, deep) > 0, "buried chunk gets meshed when opened")
	planet.free()


func test_cargo_and_economy() -> void:
	var g := game()
	g.new_game()
	var cap: int = g.cargo_capacity()
	check(g.add_cargo("iron", cap + 10) == cap, "cargo clamps to capacity")
	check(g.add_cargo("gold", 1) == 0, "full hold stores nothing")
	var expected: int = cap * int(g.ORES["iron"]["value"])
	var credits_before: int = g.credits
	check(g.sell_all() == expected, "sell_all returns cargo value")
	check(g.credits == credits_before + expected, "credits increase by sale value")
	check(g.cargo_count() == 0, "hold empty after selling")
	g.fuel = 0.0
	g.credits = 10
	g.refuel()
	check(is_equal_approx(g.fuel, 20.0) and g.credits == 0, "partial refuel spends all credits (fuel %.1f, cr %d)" % [g.fuel, g.credits])
	g.add_cargo("stone", 2)
	check(g.take_cargo("stone") and int(g.cargo["stone"]) == 1, "take_cargo removes one")
	check(not g.take_cargo("gold"), "cannot take missing cargo")


func test_upgrades() -> void:
	var g := game()
	g.new_game()
	check(g.warp_range() == 0.0, "no warp range without drive")
	g.credits = 0
	check(not g.buy_upgrade("engine"), "cannot buy without credits")
	g.credits = 100000
	var cost: int = g.upgrade_cost("tank")
	var fuel_before: float = g.fuel
	check(g.buy_upgrade("tank"), "buy tank upgrade")
	check(g.credits == 100000 - cost, "upgrade deducts cost")
	check(g.fuel == fuel_before + 40.0 and g.max_fuel() == 140.0, "tank upgrade raises fuel and capacity")
	check(g.upgrade_cost("tank") > cost, "upgrade cost rises per level")
	for i in 10:
		g.buy_upgrade("warp")
	check(g.level("warp") == int(g.UPGRADES["warp"]["max"]), "upgrade stops at max level")


func test_save_load_roundtrip() -> void:
	var g := game()
	g.new_game()
	g.credits = 1234
	g.cargo = {"gold": 3}
	g.upgrades["laser"] = 2
	g.fragments = ["0,0:0"]
	g.scanned = {"0,0:2": true}
	g.visited = {"0,0": true, "1,0": true}
	g.system_cell = Vector2i(1, 0)
	g.edits = {"0,0:0": {Vector3i(1, -2, 30): 0, Vector3i(4, 5, 6): 9}}
	check(g.save_game(TEST_SAVE), "save succeeds")
	g.new_game()
	check(g.load_game(TEST_SAVE), "load succeeds")
	check(g.credits == 1234, "credits restored")
	check(int(g.cargo.get("gold", 0)) == 3, "cargo restored")
	check(g.level("laser") == 2, "upgrades restored")
	check(g.fragments == ["0,0:0"], "fragments restored")
	check(g.scanned.has("0,0:2") and g.visited.has("1,0"), "scan/visit flags restored")
	check(g.system_cell == Vector2i(1, 0), "system restored")
	var e: Dictionary = g.edits.get("0,0:0", {})
	check(e.get(Vector3i(1, -2, 30), -1) == 0 and e.get(Vector3i(4, 5, 6), -1) == 9, "voxel edits restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	check(not g.load_game(TEST_SAVE), "loading a missing save fails cleanly")

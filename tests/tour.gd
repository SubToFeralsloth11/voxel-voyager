extends Node
## Scripted smoke tour of the real game, driving the actual input actions.
## Saves screenshots to /tmp/vv_shots and prints a CHECK line per step.
## Run windowed: godot --path . res://tests/tour.tscn

const OUT := "/tmp/vv_shots"

var world: World
var failures := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("TOUR TIMEOUT")
		get_tree().quit(2))
	world = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	_run()


func check(cond: bool, msg: String) -> void:
	print("CHECK %s: %s" % ["ok" if cond else "FAIL", msg])
	if not cond:
		failures += 1


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func _run() -> void:
	await frames(40)
	await shot("01_title")

	world.start_new_game()
	await seconds(1.5)
	await shot("02_space")
	check(world.mode == World.Mode.SHIP, "new game starts in the ship")

	# Fly (by input) toward the station and dock.
	var ship := world.ship
	var station_dir := (world.station.global_position - ship.global_position).normalized()
	ship.global_basis = Basis.looking_at(station_dir, Vector3.UP)
	Input.action_press("forward")
	await seconds(0.8)
	Input.action_release("forward")
	check(ship.velocity.length() > 10.0, "thrust accelerates the ship (%.1f m/s)" % ship.velocity.length())
	check(Game.fuel < Game.max_fuel(), "thrust burns fuel")
	await seconds(1.5)
	check(world.station.can_dock(ship), "reached docking range by flying")
	world.interact()
	await frames(10)
	check(world.mode == World.Mode.DOCKED, "docked at outpost")
	await shot("03_shop")
	world.undock()

	# Head to the home planet and let it build its voxels.
	var planet := world.planets[0]
	var dir := (ship.global_position - planet.global_position).normalized()
	ship.global_position = planet.global_position + dir * (planet.radius + 70.0)
	ship.global_basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	ship.velocity = Vector3.ZERO
	ship.snap_camera()
	var t0 := Time.get_ticks_msec()
	while not planet.built and Time.get_ticks_msec() - t0 < 15000:
		await frames(1)
	check(planet.built, "planet voxels built in %d ms" % (Time.get_ticks_msec() - t0))
	await frames(5)
	await shot("04_planet")

	# Scan it by holding R.
	Input.action_press("scan")
	await seconds(World.SCAN_TIME + 0.4)
	Input.action_release("scan")
	check(Game.scanned.has(planet.key), "holding R scans the planet in view")

	# Descend and land under gravity.
	ship.global_position = planet.global_position + dir * (planet.surface_height(dir) + 6.0)
	ship.snap_camera()
	t0 = Time.get_ticks_msec()
	while not ship.landed and Time.get_ticks_msec() - t0 < 8000:
		await frames(1)
	check(ship.landed, "ship lands under planet gravity")
	await shot("05_landed")

	world.interact()
	await frames(5)
	check(world.mode == World.Mode.FOOT, "stepped outside")
	var player := world.player
	await seconds(1.5)
	check(player.is_on_floor(), "astronaut stands on the planet")
	var alt0 := planet.altitude(player.global_position)
	await shot("06_on_foot")

	# Walk forward.
	var p0 := player.global_position
	Input.action_press("forward")
	await seconds(2.0)
	Input.action_release("forward")
	var walked := player.global_position.distance_to(p0)
	var alt1 := planet.altitude(player.global_position)
	check(walked > 4.0, "walked %.1f m" % walked)
	check(absf(alt1 - alt0) < 4.0, "stayed on the surface (alt %.1f -> %.1f)" % [alt0, alt1])

	# Look down and mine with the real input.
	var mined0 := Game.blocks_mined
	player._pitch = -1.2
	Input.action_press("fire")
	await seconds(1.5)
	await shot("07_mining")
	await seconds(1.5)
	Input.action_release("fire")
	check(Game.blocks_mined > mined0, "mined %d blocks by holding fire" % (Game.blocks_mined - mined0))

	# Beacon decoding: teleport next to the beacon and press F.
	if planet.has_beacon:
		player.global_position = planet.beacon_world() + planet.beacon_up * 2.0 + _tangent(planet.beacon_up) * 1.6
		player.velocity = Vector3.ZERO
		await seconds(1.0)
		world.interact()
		await frames(5)
		check(Game.fragments.has(planet.key), "decoded the beacon (dist %.1f, prompt '%s')" % [
			player.global_position.distance_to(planet.beacon_world()), world.prompt_text()])
		player._pitch = 0.3
		await frames(3)
		await shot("08_beacon")

	# Back to the ship and take off.
	player.global_position = ship.global_position + ship.global_basis.x * 3.6
	await frames(3)
	world.interact()
	await frames(5)
	check(world.mode == World.Mode.SHIP, "boarded ship")
	Input.action_press("up")
	await seconds(1.0)
	Input.action_release("up")
	check(not ship.landed, "took off")

	# Crack an asteroid with the laser.
	var rock: Asteroid = null
	for n in get_tree().get_nodes_in_group("asteroid"):
		rock = n
		break
	if rock:
		var rp := rock.global_position
		ship.global_position = rp + Vector3(0, 0, 30)
		ship.global_basis = Basis.looking_at(rp - ship.global_position, Vector3.UP)
		ship.velocity = Vector3.ZERO
		ship.snap_camera()
		var cargo0 := Game.cargo_count()
		Input.action_press("fire")
		await seconds(0.4)
		await shot("09_laser")
		t0 = Time.get_ticks_msec()
		while is_instance_valid(rock) and Time.get_ticks_msec() - t0 < 6000:
			await frames(1)
		Input.action_release("fire")
		check(not is_instance_valid(rock), "laser destroyed the asteroid")
		ship.velocity = Vector3.ZERO
		await seconds(3.0)
		check(Game.cargo_count() > cargo0, "tractor collected ore (%d -> %d)" % [cargo0, Game.cargo_count()])

	# Galaxy map and warp.
	Game.upgrades["warp"] = 1
	Game.fuel = Game.max_fuel()
	world.open_map()
	var target := Vector2i.ZERO
	for cell in Galaxy.systems_near(Vector2i.ZERO, 3):
		if world.warp_error(cell) == "":
			target = cell
			break
	world.galaxy_map.selected = target
	world.galaxy_map._update_panel()
	await frames(3)
	await shot("10_map")
	check(target != Vector2i.ZERO, "a star is in warp range")
	check(world.warp_to(target) == "", "warp accepted")
	await seconds(2.5)
	check(Game.system_cell == target and world.mode == World.Mode.SHIP, "arrived in %s" % world.system["name"])
	await seconds(1.0)
	await shot("11_new_system")

	world.pause()
	await frames(3)
	await shot("12_pause")
	world.resume()

	print("TOUR DONE failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _tangent(up: Vector3) -> Vector3:
	return up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()

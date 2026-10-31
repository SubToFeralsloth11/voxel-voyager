class_name World
extends Node3D
## Root game controller: builds the current star system, owns the ship and
## astronaut, routes mode changes (flying, on foot, docked, map, menus),
## warping, scanning and respawns.

enum Mode { TITLE, SHIP, FOOT, DOCKED, MAP, WARP, PAUSED, ENDING }

const SCAN_RANGE := 950.0
const SCAN_TIME := 1.4
const SCAN_CONE := 0.93
const ENTER_SHIP_RANGE := 6.5
const BEACON_RANGE := 4.5

var mode := Mode.TITLE
var system: Dictionary
var star_radius := 70.0
var planets: Array[VoxelPlanet] = []
var station: Station
var ship: Ship
var player: Player
var hud: Hud
var menus: Menus
var shop: ShopPanel
var galaxy_map: GalaxyMap
var scan_target: VoxelPlanet = null
var scan_progress := 0.0

var _system_root: Node3D
var _sun_light: DirectionalLight3D
var _star_mesh: MeshInstance3D
var _mode_before_pause := Mode.SHIP
var _title_cam: Camera3D
var _title_angle := 0.0
var _respawning := false


func _ready() -> void:
	_setup_environment()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var theme := UiTheme.make()
	hud = Hud.new()
	hud.world = self
	hud.theme = theme
	layer.add_child(hud)
	shop = ShopPanel.new()
	shop.world = self
	shop.theme = theme
	layer.add_child(shop)
	galaxy_map = GalaxyMap.new()
	galaxy_map.world = self
	galaxy_map.theme = theme
	layer.add_child(galaxy_map)
	menus = Menus.new()
	menus.world = self
	menus.theme = theme
	layer.add_child(menus)
	_title_cam = Camera3D.new()
	_title_cam.far = 9000.0
	add_child(_title_cam)
	show_title()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/space_sky.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_sun_light = DirectionalLight3D.new()
	_sun_light.shadow_enabled = true
	_sun_light.directional_shadow_max_distance = 260.0
	_sun_light.light_energy = 1.1
	add_child(_sun_light)


# --- system lifecycle --------------------------------------------------------

func load_system(cell: Vector2i) -> void:
	if _system_root:
		_system_root.queue_free()
		remove_child(_system_root)
	planets.clear()
	scan_target = null
	_system_root = Node3D.new()
	_system_root.name = "System"
	add_child(_system_root)
	system = Galaxy.system_data(cell)
	star_radius = system["star_radius"]
	Game.system_cell = cell
	Game.visited[Galaxy.cell_key(cell)] = true
	var star_color: Color = system["star_color"]
	_star_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = star_radius
	sphere.height = star_radius * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = star_color
	sm.emission_enabled = true
	sm.emission = star_color
	sm.emission_energy_multiplier = 3.0
	sphere.material = sm
	_star_mesh.mesh = sphere
	_star_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_system_root.add_child(_star_mesh)
	_sun_light.light_color = star_color.lerp(Color.WHITE, 0.5)
	for pdata: Dictionary in system["planets"]:
		var planet := VoxelPlanet.new()
		planet.name = "Planet%d" % pdata["index"]
		planet.setup(pdata)
		_system_root.add_child(planet)
		planets.append(planet)
	station = Station.new()
	station.position = system["station_pos"]
	_system_root.add_child(station)
	_spawn_belt()
	_spawn_drones()
	if ship == null:
		ship = Ship.new()
		ship.world = self
		ship.destroyed.connect(_on_ship_destroyed)
		add_child(ship)
	_reset_ship_near_station()


func _spawn_belt() -> void:
	var count: int = system["belt_count"]
	if count == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Galaxy.hash4(Game.system_cell.x, Game.system_cell.y, 404, 1)
	var meshes := []
	var ores := ["iron", "ice", "gold", "crystal", "iron", "ice"]
	for i in 6:
		var ore: String = ores[i]
		var radius := rng.randf_range(2.5, 5.0)
		var base := Color(0.42, 0.4, 0.4) if ore != "ice" else Color(0.65, 0.75, 0.85)
		var cells := VoxelMesher.blob_cells(rng, radius, base, Game.ORES[ore]["color"])
		meshes.append([VoxelMesher.mesh_from_cells(cells, 1.0, Vector3(0.5, 0.5, 0.5)), ore, radius])
	var belt: float = system["belt_radius"]
	for i in count:
		var pick: Array = meshes[rng.randi() % meshes.size()]
		var a := rng.randf() * TAU
		var r := belt + rng.randf_range(-40.0, 40.0)
		var rock := Asteroid.new()
		rock.world = self
		rock.position = Vector3(cos(a) * r, rng.randf_range(-18.0, 18.0), sin(a) * r)
		rock.setup(pick[0], pick[1], pick[2], rng)
		rock.add_to_group("asteroid")
		_system_root.add_child(rock)


func _spawn_drones() -> void:
	var count: int = system["drone_count"]
	var rng := RandomNumberGenerator.new()
	rng.seed = Galaxy.hash4(Game.system_cell.x, Game.system_cell.y, 505, 1)
	for i in count:
		var planet: VoxelPlanet = planets[rng.randi() % planets.size()]
		var drone := Drone.new()
		drone.world = self
		var offset := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.4), rng.randf_range(-1, 1)).normalized()
		drone.position = planet.position + offset * (planet.radius * 2.2 + 40.0)
		_system_root.add_child(drone)


func _reset_ship_near_station() -> void:
	var to_planet: Vector3 = planets[0].position - station.position
	ship.velocity = Vector3.ZERO
	ship.landed = false
	ship.docked = false
	ship.global_position = station.position - to_planet.normalized() * 70.0 + Vector3(0, 12, 0)
	ship.global_basis = Basis.looking_at(to_planet.normalized(), Vector3.UP)
	ship.snap_camera()


# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and _star_mesh and is_instance_valid(_star_mesh):
		var dir := cam.global_position - _star_mesh.global_position
		if dir.length() > 0.1:
			_sun_light.global_basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
	match mode:
		Mode.TITLE:
			_title_angle += delta * 0.05
			if planets.size() > 0:
				var p := planets[0]
				var off := Vector3(cos(_title_angle), 0.35, sin(_title_angle)) * (p.radius * 3.2)
				_title_cam.global_position = p.global_position + off
				_title_cam.look_at(p.global_position, Vector3.UP)
		Mode.SHIP:
			_update_scan(delta)


## Map, pause and ending menus handle their own keys while the tree is paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if mode == Mode.DOCKED:
			undock()
		elif mode in [Mode.SHIP, Mode.FOOT]:
			pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("help") and mode in [Mode.SHIP, Mode.FOOT]:
		hud.toggle_help()
	if event.is_action_pressed("galaxy_map") and mode == Mode.SHIP:
		open_map()
	if event.is_action_pressed("interact"):
		interact()
	if event is InputEventMouseButton and event.pressed and mode in [Mode.SHIP, Mode.FOOT] \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Context action on [F]: dock, leave/enter ship, activate beacons.
func interact() -> void:
	match mode:
		Mode.SHIP:
			if station.can_dock(ship):
				dock()
			elif ship.landed:
				exit_ship()
		Mode.FOOT:
			var beacon := nearby_beacon()
			if beacon:
				activate_beacon(beacon)
			elif player.global_position.distance_to(ship.global_position) < ENTER_SHIP_RANGE:
				enter_ship()


func prompt_text() -> String:
	match mode:
		Mode.SHIP:
			if station.can_dock(ship):
				return "[F] Dock at trade outpost"
			if station.global_position.distance_to(ship.global_position) < Station.DOCK_RADIUS:
				return "Slow down to dock"
			if ship.landed:
				return "[F] Step outside    [Space/W] Take off"
		Mode.FOOT:
			var beacon := nearby_beacon()
			if beacon:
				if beacon.is_core and Game.fragments.size() < Game.FRAGMENTS_NEEDED:
					return "The monolith is dormant (%d/%d signal fragments)" % [Game.fragments.size(), Game.FRAGMENTS_NEEDED]
				if Game.fragments.has(beacon.key) and not beacon.is_core:
					return "Beacon already decoded"
				return "[F] Activate %s" % ("the Architect's Monolith" if beacon.is_core else "ancient beacon")
			if player.global_position.distance_to(ship.global_position) < ENTER_SHIP_RANGE:
				return "[F] Board ship"
	return ""


func nearest_planet(pos: Vector3) -> VoxelPlanet:
	var best: VoxelPlanet = null
	var best_d := INF
	for p in planets:
		var d := pos.distance_to(p.global_position) - p.radius
		if d < best_d:
			best_d = d
			best = p
	return best


func nearby_beacon() -> VoxelPlanet:
	if player == null or player.planet == null or not player.planet.has_beacon:
		return null
	if player.global_position.distance_to(player.planet.beacon_world()) < BEACON_RANGE:
		return player.planet
	return null


# --- actions -----------------------------------------------------------------

func collect_block(planet: VoxelPlanet, cell: Vector3i) -> void:
	var t := planet.get_block(cell)
	var drop: String = VoxelPlanet.DROPS.get(t, "")
	if drop != "" and Game.cargo_count() >= Game.cargo_capacity():
		hud.flash_message("Cargo hold full! Sell at a trade outpost.", Color(1, 0.6, 0.4))
		return
	if planet.mine(cell) == VoxelPlanet.Block.AIR:
		return
	Game.blocks_mined += 1
	Sfx.play("mine")
	if drop != "":
		Game.add_cargo(drop)
		Sfx.play("pickup")


func spawn_pickup(pos: Vector3, ore: String, vel: Vector3) -> void:
	var p := Pickup.new()
	_system_root.add_child(p)
	p.global_position = pos
	p.setup(ore, vel, ship)


func spawn_debris(pos: Vector3, size: float) -> void:
	var parts := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.48, 0.46)
	box.material = mat
	parts.mesh = box
	parts.amount = int(10 + size * 4)
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.lifetime = 1.6
	parts.direction = Vector3.UP
	parts.spread = 180.0
	parts.initial_velocity_min = 4.0
	parts.initial_velocity_max = 14.0
	parts.gravity = Vector3.ZERO
	parts.scale_amount_min = 0.5
	parts.scale_amount_max = 1.4
	_system_root.add_child(parts)
	parts.global_position = pos
	parts.emitting = true
	get_tree().create_timer(2.0).timeout.connect(parts.queue_free)


func activate_beacon(planet: VoxelPlanet) -> void:
	if planet.is_core:
		if Game.fragments.size() < Game.FRAGMENTS_NEEDED:
			return
		Sfx.play("beacon")
		Game.won = true
		Game.save_game()
		_set_mode(Mode.ENDING)
		menus.show_ending()
		return
	if Game.fragments.has(planet.key):
		return
	Game.fragments.append(planet.key)
	Game.credits += 150
	Game.changed.emit()
	Sfx.play("beacon")
	var have := Game.fragments.size()
	if have >= Game.FRAGMENTS_NEEDED:
		Game.notify("Signal fragment %d/%d decoded! The Architect's Core is calling. Find it on the galaxy map." % [have, Game.FRAGMENTS_NEEDED], Color(1.0, 0.85, 0.3))
	else:
		Game.notify("Signal fragment %d/%d decoded! +150 cr" % [have, Game.FRAGMENTS_NEEDED], Color(0.4, 1.0, 0.9))


func _update_scan(delta: float) -> void:
	if not Input.is_action_pressed("scan") or not ship.controls_enabled:
		scan_progress = 0.0
		scan_target = null
		return
	var target := _scan_candidate()
	if target != scan_target:
		scan_target = target
		scan_progress = 0.0
		if target:
			Sfx.play("scan")
	if target == null:
		return
	scan_progress += delta / SCAN_TIME
	if scan_progress >= 1.0:
		_complete_scan(target)
		scan_progress = 0.0
		scan_target = null


func _scan_candidate() -> VoxelPlanet:
	var cam := ship.cam
	var fwd := -cam.global_basis.z
	var best: VoxelPlanet = null
	var best_dot := SCAN_CONE
	for p in planets:
		var to := p.global_position - cam.global_position
		if to.length() - p.radius > SCAN_RANGE:
			continue
		var d := fwd.dot(to.normalized())
		if d > best_dot:
			best_dot = d
			best = p
	return best


func _complete_scan(p: VoxelPlanet) -> void:
	var first := not Game.scanned.has(p.key)
	Game.scanned[p.key] = true
	p.set_scanned(true)
	var info := "%s: %s world, gravity %.1f. Resources: %s." % [
		p.planet_name, p.type_info["label"], p.surface_gravity, ", ".join(p.resource_names())]
	if p.breathable:
		info += " Breathable air."
	if p.has_beacon:
		info += " ANCIENT BEACON DETECTED!" if not p.is_core else " THE ARCHITECT'S MONOLITH!"
	if first:
		Game.credits += 25
		Game.changed.emit()
		info += " (+25 cr discovery)"
	Game.notify(info, Color(0.6, 0.9, 1.0))


# --- mode changes ------------------------------------------------------------

func _set_mode(m: Mode) -> void:
	mode = m
	var captured := m in [Mode.SHIP, Mode.FOOT]
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
	if ship:
		ship.controls_enabled = m == Mode.SHIP
	if player:
		player.controls_enabled = m == Mode.FOOT
	hud.visible = m not in [Mode.TITLE, Mode.ENDING]
	hud.set_menu_overlay(m in [Mode.DOCKED, Mode.MAP, Mode.PAUSED], m == Mode.PAUSED)
	get_tree().paused = m in [Mode.PAUSED, Mode.MAP, Mode.ENDING]


func show_title() -> void:
	load_system(Vector2i.ZERO)
	_title_cam.current = true
	_set_mode(Mode.TITLE)
	menus.show_title()


func start_new_game() -> void:
	Game.new_game()
	_begin(Vector2i.ZERO)
	hud.show_help(true)
	Game.notify("Welcome, voyager! Mine, trade, upgrade, and decode the ancient beacons.", Color(0.6, 1.0, 0.8))


func continue_game() -> void:
	if not Game.load_game():
		menus.show_title_error("Save file could not be loaded.")
		return
	_begin(Game.system_cell)


func _begin(cell: Vector2i) -> void:
	_remove_player()
	load_system(cell)
	ship.piloted = true
	ship.cam.current = true
	menus.hide_all()
	_set_mode(Mode.SHIP)
	Game.notify("Entering the %s system." % system["name"], Color(0.8, 0.9, 1.0))


func pause() -> void:
	_mode_before_pause = mode
	_set_mode(Mode.PAUSED)
	menus.show_pause()


func resume() -> void:
	menus.hide_all()
	_set_mode(_mode_before_pause)


func quit_to_title() -> void:
	get_tree().paused = false
	_remove_player()
	shop.close()
	galaxy_map.close()
	show_title()


func exit_ship() -> void:
	if not ship.landed:
		return
	var planet := nearest_planet(ship.global_position)
	player = Player.new()
	player.world = self
	player.died.connect(_on_player_died)
	add_child(player)
	var up := (ship.global_position - planet.global_position).normalized()
	player.global_position = _free_spot(ship.global_position + ship.global_basis.x * 3.6 + up * 1.2, up)
	player.global_basis = ship.global_basis
	player.planet = planet
	player.cam.current = true
	ship.piloted = false
	Sfx.set_engine(0.0)
	_set_mode(Mode.FOOT)
	if not planet.breathable:
		Game.notify("No breathable air here. Watch your oxygen.", Color(1.0, 0.8, 0.5))


func enter_ship() -> void:
	_remove_player()
	ship.piloted = true
	ship.cam.current = true
	ship.snap_camera()
	Sfx.play("ui")
	_set_mode(Mode.SHIP)


## First position at or above `pos` (stepping along `up`) where the
## astronaut's capsule overlaps nothing, so it never spawns inside terrain.
func _free_spot(pos: Vector3, up: Vector3) -> Vector3:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	var space := get_world_3d().direct_space_state
	var basis := VoxelPlanet.basis_for_up(up)
	for i in 16:
		query.transform = Transform3D(basis, pos + up * i)
		if space.intersect_shape(query, 1).is_empty():
			return pos + up * i
	return pos + up * 16.0


func _remove_player() -> void:
	if player:
		player.queue_free()
		player = null
	Sfx.loop_laser(false)


func dock() -> void:
	ship.docked = true
	ship.velocity = Vector3.ZERO
	Sfx.play("land")
	_set_mode(Mode.DOCKED)
	shop.open()
	Game.save_game()


func undock() -> void:
	shop.close()
	ship.docked = false
	var away := (ship.global_position - station.global_position).normalized()
	ship.velocity = away * 12.0
	_set_mode(Mode.SHIP)


func open_map() -> void:
	_set_mode(Mode.MAP)
	galaxy_map.open()


func close_map() -> void:
	galaxy_map.close()
	_set_mode(Mode.SHIP)


## Starts a warp jump. Returns an error message, or "" on success.
func warp_to(cell: Vector2i) -> String:
	var err := warp_error(cell)
	if err != "":
		return err
	Game.fuel -= Game.WARP_FUEL_COST
	galaxy_map.close()
	_set_mode(Mode.WARP)
	Sfx.play("warp")
	hud.warp_flash()
	var tween := create_tween()
	tween.tween_property(ship.cam, "fov", 150.0, 0.9).set_ease(Tween.EASE_IN)
	tween.tween_callback(_finish_warp.bind(cell))
	return ""


func _finish_warp(cell: Vector2i) -> void:
	load_system(cell)
	ship.cam.fov = 72.0
	_set_mode(Mode.SHIP)
	Game.notify("Warp complete: %s system." % system["name"], Color(0.8, 0.9, 1.0))



func resume_after_ending() -> void:
	_set_mode(Mode.FOOT if player else Mode.SHIP)


func warp_error(cell: Vector2i) -> String:
	if cell == Game.system_cell:
		return "You are already here."
	if Game.warp_range() <= 0.0:
		return "No warp drive installed. Buy one at a trade outpost."
	if Galaxy.distance(Game.system_cell, cell) > Game.warp_range():
		return "Out of warp range. Upgrade the warp drive or hop via closer stars."
	if Game.fuel < Game.WARP_FUEL_COST:
		return "Need %d fuel to warp." % int(Game.WARP_FUEL_COST)
	return ""


func _on_ship_destroyed() -> void:
	if _respawning:
		return
	_respawning = true
	Sfx.play("explode")
	spawn_debris(ship.global_position, 5.0)
	Game.cargo = {}
	Game.hull = Game.max_hull() * 0.5
	Game.fuel = maxf(Game.fuel, Game.max_fuel() * 0.5)
	Game.changed.emit()
	hud.warp_flash()
	if mode == Mode.FOOT:
		enter_ship()
	_reset_ship_near_station()
	Game.notify("Hull breached! Your ship was towed to the outpost. Cargo lost.", Color(1, 0.4, 0.35))
	_respawning = false


func _on_player_died() -> void:
	if mode != Mode.FOOT:
		return
	var planet := player.planet
	enter_ship()
	if planet:
		Game.notify("Suit failure! You were dragged back to your ship.", Color(1, 0.45, 0.4))

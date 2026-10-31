class_name Ship
extends CharacterBody3D
## The player's ship: arcade six-degree-of-freedom flight with drag, planet
## gravity, landing, a mining/combat laser and a chase camera.

signal destroyed

const ACCEL := 45.0
const DRAG := 0.7
const ATMO_DRAG := 1.3
const BOOST := 2.4
const ROLL_SPEED := 1.9
const IMPACT_SAFE := 22.0
const LASER_RANGE := 260.0
const LASER_DPS := 22.0
const CAM_OFFSET := Vector3(0, 2.8, 11.0)

var world: World
var piloted := true
var landed := false
var docked := false
var controls_enabled := true
var boosting := false
var throttle := 0.0
var firing := false
var cam: Camera3D

var _mouse := Vector2.ZERO
var _cam_quat := Quaternion.IDENTITY
var _laser: MeshInstance3D
var _flames: Array[MeshInstance3D] = []
var _engine_light: OmniLight3D
var _mine_progress := 0.0
var _heat_warned := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_build_model()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.6, 1.5, 5.2)
	shape.shape = box
	add_child(shape)
	cam = Camera3D.new()
	cam.top_level = true
	cam.far = 9000.0
	cam.fov = 72.0
	add_child(cam)
	_cam_quat = global_basis.get_rotation_quaternion()
	snap_camera()


func _build_model() -> void:
	var body := Color(0.86, 0.88, 0.92)
	var accent := Color(1.0, 0.45, 0.2)
	var dark := Color(0.2, 0.22, 0.28)
	_box(Vector3(1.6, 1.0, 4.4), Vector3(0, 0, 0), body)
	_box(Vector3(1.2, 0.7, 1.4), Vector3(0, 0.15, -2.6), body)
	_box(Vector3(1.0, 0.5, 1.3), Vector3(0, 0.6, -0.9), Color(0.35, 0.8, 1.0), 0.6)
	_box(Vector3(4.6, 0.25, 1.8), Vector3(0, -0.2, 0.6), body)
	_box(Vector3(0.5, 0.6, 1.2), Vector3(2.3, 0.05, 0.9), accent)
	_box(Vector3(0.5, 0.6, 1.2), Vector3(-2.3, 0.05, 0.9), accent)
	_box(Vector3(0.25, 1.1, 1.0), Vector3(0, 0.95, 1.6), accent)
	_box(Vector3(0.7, 0.7, 0.6), Vector3(0.55, 0, 2.4), dark)
	_box(Vector3(0.7, 0.7, 0.6), Vector3(-0.55, 0, 2.4), dark)
	_box(Vector3(0.3, 0.3, 0.8), Vector3(0, -0.45, -2.9), dark)
	for x: float in [0.55, -0.55]:
		var flame := _box(Vector3(0.5, 0.5, 1.0), Vector3(x, 0, 3.2), Color(0.4, 0.8, 1.0), 4.0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flames.append(flame)
	_engine_light = OmniLight3D.new()
	_engine_light.light_color = Color(0.4, 0.8, 1.0)
	_engine_light.omni_range = 8.0
	_engine_light.position = Vector3(0, 0, 3.8)
	add_child(_engine_light)
	_laser = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.18, 0.18, 1.0)
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1.0, 0.35, 0.3)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.3, 0.25)
	lm.emission_energy_multiplier = 4.0
	beam.material = lm
	_laser.mesh = beam
	_laser.top_level = true
	_laser.visible = false
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_laser)


func _box(size: Vector3, pos: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if piloted and controls_enabled and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += (event as InputEventMouseMotion).relative


func _physics_process(delta: float) -> void:
	firing = false
	if docked:
		velocity = Vector3.ZERO
		_mouse = Vector2.ZERO
		_update_effects(delta, 0.0)
		return
	var active := piloted and controls_enabled
	var planet := world.nearest_planet(global_position) if world else null
	if landed:
		velocity = Vector3.ZERO
		_mouse = Vector2.ZERO
		if active and (Input.is_action_pressed("up") or Input.is_action_pressed("forward")):
			take_off()
		_update_effects(delta, 0.0)
		return
	var input := Vector3.ZERO
	var roll := 0.0
	if active:
		input = Vector3(
			Input.get_axis("left", "right"),
			Input.get_axis("down", "up"),
			Input.get_axis("forward", "back"))
		roll = Input.get_axis("roll_right", "roll_left")
		rotate_object_local(Vector3.UP, -_mouse.x * Game.mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -_mouse.y * Game.mouse_sensitivity)
		rotate_object_local(Vector3.FORWARD, -roll * ROLL_SPEED * delta)
		orthonormalize()
	_mouse = Vector2.ZERO
	if input.length() > 1.0:
		input = input.normalized()
	boosting = active and Input.is_action_pressed("boost") and input.z < 0.0 and Game.fuel > 0.0
	var accel := ACCEL * Game.thrust_mult()
	if Game.fuel <= 0.0:
		accel *= 0.35
	if boosting:
		accel *= BOOST
	velocity += global_basis * input * accel * delta
	Game.use_fuel((4.0 if boosting else 0.3) * input.length() * delta)
	var drag := DRAG
	if planet:
		velocity += planet.gravity_at(global_position) * delta
		if planet.has_atmosphere() and planet.altitude(global_position) < planet.radius * 0.35:
			drag = ATMO_DRAG
	velocity -= velocity * drag * delta
	throttle = input.length() * (2.0 if boosting else 1.0)
	_move(delta, planet)
	if active and roll == 0.0 and planet and not landed:
		_auto_level(planet, delta)
	if active and Input.is_action_pressed("fire"):
		_fire_laser(delta)
	_check_heat(delta)
	_update_effects(delta, throttle)


func _move(delta: float, planet: VoxelPlanet) -> void:
	var motion := velocity * delta
	for i in 3:
		var col := move_and_collide(motion)
		if col == null:
			return
		var n := col.get_normal()
		var impact := -velocity.dot(n)
		var hit_planet := col.get_collider() is Node and (col.get_collider() as Node).get_parent() is VoxelPlanet
		if hit_planet and planet:
			var up := (global_position - planet.global_position).normalized()
			if n.dot(up) > 0.55 and impact < IMPACT_SAFE and velocity.length() < 16.0:
				land(planet)
				return
		if impact > IMPACT_SAFE:
			take_damage((impact - IMPACT_SAFE) * 1.3)
			Sfx.play("hit")
			velocity += n * impact * 0.35
		velocity = velocity.slide(n) * 0.9
		motion = col.get_remainder().slide(n)


func land(planet: VoxelPlanet) -> void:
	landed = true
	velocity = Vector3.ZERO
	var up := (global_position - planet.global_position).normalized()
	var fwd := (-global_basis.z).slide(up).normalized()
	if fwd.length() < 0.1:
		fwd = up.cross(Vector3.RIGHT).normalized()
	global_basis = Basis.looking_at(fwd, up)
	Sfx.play("land")
	Game.notify("Landed on %s. [F] to step outside." % planet.planet_name, Color(0.6, 1.0, 0.7))


func take_off() -> void:
	landed = false
	velocity = global_basis.y * 9.0
	global_position += global_basis.y * 0.5
	Sfx.play("ui")


func _auto_level(planet: VoxelPlanet, delta: float) -> void:
	if planet.altitude(global_position) > 40.0:
		return
	var up := (global_position - planet.global_position).normalized()
	var cur := global_basis.y
	var axis := cur.cross(up)
	if axis.length() < 0.001:
		return
	var angle := cur.angle_to(up)
	global_basis = (Basis(axis.normalized(), minf(angle, 1.2 * delta)) * global_basis).orthonormalized()


func _fire_laser(delta: float) -> void:
	firing = true
	var from := global_transform * Vector3(0, -0.45, -3.3)
	var to := from - global_basis.z * LASER_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var end := to
	if not hit.is_empty():
		end = hit["position"]
		var collider: Object = hit["collider"]
		if collider.has_method("take_laser"):
			collider.call("take_laser", LASER_DPS * Game.laser_speed() * delta)
		elif collider is Node and (collider as Node).get_parent() is VoxelPlanet:
			_mine_planet((collider as Node).get_parent() as VoxelPlanet, hit, delta)
	_show_beam(from, end)
	Sfx.loop_laser(true)


func _mine_planet(planet: VoxelPlanet, hit: Dictionary, delta: float) -> void:
	_mine_progress += delta * Game.laser_speed() * 0.9
	if _mine_progress < 0.5:
		return
	_mine_progress = 0.0
	var cell := planet.world_to_cell(hit["position"] - (hit["normal"] as Vector3) * 0.5)
	world.collect_block(planet, cell)


func _show_beam(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	_laser.visible = true
	_laser.global_transform = Transform3D(Basis.looking_at(to - from, global_basis.y), (from + to) * 0.5)
	_laser.scale = Vector3(1, 1, length)


func _check_heat(delta: float) -> void:
	if world == null:
		return
	var star_dist := global_position.length()
	var danger := world.star_radius * 2.6
	if star_dist < danger:
		var heat := 1.0 - (star_dist - world.star_radius) / (danger - world.star_radius)
		take_damage(clampf(heat, 0.1, 1.0) * 25.0 * delta)
		_heat_warned -= delta
		if _heat_warned <= 0.0:
			_heat_warned = 3.0
			Game.notify("WARNING: Hull overheating! Move away from the star.", Color(1, 0.4, 0.3))
			Sfx.play("alert")


func take_damage(amount: float) -> void:
	if amount <= 0.0 or Game.hull <= 0.0:
		return
	Game.damage_hull(amount)
	if Game.hull <= 0.0:
		destroyed.emit()


func _update_effects(delta: float, power: float) -> void:
	if not firing:
		_laser.visible = false
		if piloted:
			Sfx.loop_laser(false)
	for f in _flames:
		var target := 0.08 + power * 1.4
		f.scale.z = lerpf(f.scale.z, target, 1.0 - exp(-10.0 * delta))
		f.position.z = 2.7 + f.scale.z * 0.5
	_engine_light.light_energy = 0.4 + power * 2.0
	Sfx.set_engine(power if piloted else 0.0)


func _process(delta: float) -> void:
	if not cam.current:
		return
	var target := global_basis.get_rotation_quaternion()
	_cam_quat = _cam_quat.slerp(target, 1.0 - exp(-7.0 * delta)).normalized()
	_place_camera()
	var speed_fov := 72.0 + clampf(velocity.length() / 6.0, 0.0, 22.0)
	cam.fov = lerpf(cam.fov, speed_fov, 1.0 - exp(-4.0 * delta))


func snap_camera() -> void:
	_cam_quat = global_basis.get_rotation_quaternion()
	_place_camera()


func _place_camera() -> void:
	var b := Basis(_cam_quat)
	cam.global_position = global_position + b * CAM_OFFSET
	cam.look_at(global_position + b * Vector3(0, 1.4, -20.0), b.y)

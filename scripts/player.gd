class_name Player
extends CharacterBody3D
## First-person astronaut that walks on spherical voxel planets: radial
## gravity, auto step-up, jetpack, mining laser and block placement.

signal died

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const JUMP_SPEED := 6.5
const JET_ACCEL := 16.0
const MAX_OXYGEN := 100.0
const OXYGEN_DRAIN := 1.1
const STEP_HEIGHT := 1.05

var world: World
var planet: VoxelPlanet
var controls_enabled := true
var health := 100.0
var oxygen := MAX_OXYGEN
var jet_fuel := 1.0
var mining_progress := 0.0
var target_cell := Vector3i.ZERO
var target_planet: VoxelPlanet = null
var target_normal := Vector3.ZERO
var head: Node3D
var cam: Camera3D

var _mouse := Vector2.ZERO
var _pitch := 0.0
var _highlight: MeshInstance3D
var _beam: MeshInstance3D
var _tool: Node3D
var _o2_warned := false
var _place_cooldown := 0.0
var _cargo_warned := 0.0


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape.shape = capsule
	add_child(shape)
	head = Node3D.new()
	head.position = Vector3(0, 0.6, 0)
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 78.0
	cam.near = 0.05
	cam.far = 9000.0
	head.add_child(cam)
	_build_tool()
	_build_highlight()
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.3


func _build_tool() -> void:
	_tool = Node3D.new()
	_tool.position = Vector3(0.2, -0.16, -0.5)
	_tool.scale = Vector3.ONE * 0.5
	cam.add_child(_tool)
	for part: Array in [[Vector3(0.12, 0.12, 0.42), Vector3.ZERO, Color(0.85, 0.86, 0.9), 0.0],
			[Vector3(0.08, 0.16, 0.1), Vector3(0, -0.12, 0.1), Color(0.25, 0.25, 0.3), 0.0],
			[Vector3(0.07, 0.07, 0.08), Vector3(0, 0, -0.24), Color(0.3, 1.0, 0.85), 3.0]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = part[2]
		if part[3] > 0.0:
			mat.emission_enabled = true
			mat.emission = part[2]
			mat.emission_energy_multiplier = part[3]
		box.material = mat
		mi.mesh = box
		mi.position = part[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_tool.add_child(mi)
	_beam = MeshInstance3D.new()
	var beam := BoxMesh.new()
	beam.size = Vector3(0.04, 0.04, 1.0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.4, 1.0, 0.9)
	beam.material = bm
	_beam.mesh = beam
	_beam.top_level = true
	_beam.visible = false
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)


func _build_highlight() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var s := 1.02
	var o := -0.01
	var corners := []
	for i in 8:
		corners.append(Vector3(o + s * (i & 1), o + s * ((i >> 1) & 1), o + s * ((i >> 2) & 1)))
	for e: Array in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	im.surface_set_material(0, mat)
	_highlight = MeshInstance3D.new()
	_highlight.mesh = im
	_highlight.top_level = true
	_highlight.visible = false
	add_child(_highlight)


func _unhandled_input(event: InputEvent) -> void:
	if controls_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse += (event as InputEventMouseMotion).relative


func up_vector() -> Vector3:
	if planet == null:
		return global_basis.y
	return (global_position - planet.global_position).normalized()


func _physics_process(delta: float) -> void:
	if world:
		planet = world.nearest_planet(global_position)
	var up := up_vector()
	_align_to(up, delta)
	up_direction = up
	if controls_enabled:
		rotate_object_local(Vector3.UP, -_mouse.x * Game.mouse_sensitivity)
		_pitch = clampf(_pitch - _mouse.y * Game.mouse_sensitivity, -1.5, 1.5)
		head.rotation.x = _pitch
	_mouse = Vector2.ZERO

	var gravity := planet.gravity_at(global_position) if planet else Vector3.ZERO
	var vertical := up * velocity.dot(up)
	var horizontal := velocity - vertical
	var wish := Vector3.ZERO
	if controls_enabled:
		var input := Input.get_vector("left", "right", "forward", "back")
		wish = global_basis * Vector3(input.x, 0, input.y)
	var speed := SPRINT_SPEED if controls_enabled and Input.is_action_pressed("boost") else WALK_SPEED
	var control := 12.0 if is_on_floor() else 3.0
	horizontal = horizontal.lerp(wish * speed, 1.0 - exp(-control * delta))
	vertical += gravity * delta
	if is_on_floor():
		jet_fuel = minf(1.0, jet_fuel + delta * 0.5)
		if controls_enabled and Input.is_action_just_pressed("up"):
			vertical = up * JUMP_SPEED
			Sfx.play("jump")
	elif controls_enabled and Input.is_action_pressed("up") and jet_fuel > 0.0:
		jet_fuel = maxf(0.0, jet_fuel - delta * 0.35)
		vertical += up * JET_ACCEL * delta
		if vertical.dot(up) > 7.0:
			vertical = up * 7.0
	velocity = horizontal + vertical
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and wish.length() > 0.1 and is_on_wall():
		_try_step(up, wish.normalized())

	_update_oxygen(delta)
	_update_tool(delta)


func _align_to(up: Vector3, delta: float) -> void:
	var cur := global_basis.y
	var axis := cur.cross(up)
	if axis.length() < 0.0001:
		return
	var angle := cur.angle_to(up)
	var turn := angle if angle < 0.5 else minf(angle, 6.0 * delta)
	global_basis = (Basis(axis.normalized(), turn) * global_basis).orthonormalized()


func _try_step(up: Vector3, dir: Vector3) -> void:
	var lifted := global_transform.translated(up * STEP_HEIGHT)
	if test_move(global_transform, up * STEP_HEIGHT):
		return
	if test_move(lifted, dir * 0.4):
		return
	global_position += up * STEP_HEIGHT + dir * 0.2


func _update_oxygen(delta: float) -> void:
	if planet and planet.breathable:
		oxygen = minf(MAX_OXYGEN, oxygen + delta * 10.0)
		_o2_warned = false
	else:
		oxygen = maxf(0.0, oxygen - OXYGEN_DRAIN * delta)
	if oxygen < 25.0 and not _o2_warned:
		_o2_warned = true
		Game.notify("Oxygen low! Return to your ship.", Color(1.0, 0.6, 0.3))
		Sfx.play("alert")
	if oxygen <= 0.0:
		health -= 12.0 * delta
	if health <= 0.0:
		health = 0.0
		controls_enabled = false
		died.emit()


func _update_tool(delta: float) -> void:
	_place_cooldown -= delta
	_cargo_warned -= delta
	target_planet = null
	_beam.visible = false
	if not controls_enabled:
		_highlight.visible = false
		return
	var from := cam.global_position
	var to := from - cam.global_basis.z * Game.laser_range()
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var collider: Object = hit.get("collider")
	if hit.is_empty() or not (collider is Node and (collider as Node).get_parent() is VoxelPlanet):
		_highlight.visible = false
		mining_progress = 0.0
		return
	var p: VoxelPlanet = (collider as Node).get_parent()
	var normal: Vector3 = hit["normal"]
	var cell := p.world_to_cell(hit["position"] - normal * 0.5)
	if cell != target_cell:
		mining_progress = 0.0
	target_cell = cell
	target_planet = p
	target_normal = normal
	_highlight.visible = true
	_highlight.global_transform = Transform3D(Basis.IDENTITY, p.global_position + Vector3(cell))
	if Input.is_action_pressed("fire"):
		var t := p.get_block(cell)
		if p.can_mine(t):
			mining_progress += delta * Game.laser_speed() / float(VoxelPlanet.HARDNESS.get(t, 1.0))
			_beam.visible = true
			var muzzle := _tool.global_transform * Vector3(0, 0, -0.28)
			var end: Vector3 = hit["position"]
			_beam.global_transform = Transform3D(Basis.looking_at(end - muzzle, up_vector()), (muzzle + end) * 0.5)
			_beam.scale = Vector3(1, 1, muzzle.distance_to(end))
			Sfx.loop_laser(true)
			if mining_progress >= 1.0:
				mining_progress = 0.0
				world.collect_block(p, cell)
		else:
			mining_progress = 0.0
	else:
		mining_progress = 0.0
	if not _beam.visible:
		Sfx.loop_laser(false)
	if Input.is_action_pressed("place") and _place_cooldown <= 0.0:
		_place_cooldown = 0.25
		try_place(p, p.world_to_cell(hit["position"] + normal * 0.5))


func try_place(p: VoxelPlanet, cell: Vector3i) -> bool:
	if int(Game.cargo.get("stone", 0)) <= 0:
		if _cargo_warned <= 0.0:
			_cargo_warned = 2.0
			Game.notify("Need stone in cargo to build blocks.", Color(1, 0.8, 0.5))
		return false
	var center := p.cell_center(cell)
	var rel := center - global_position
	var up := up_vector()
	var along := rel.dot(up)
	if (rel - up * along).length() < 0.95 and along > -1.45 and along < 1.45:
		return false
	if p.place(cell, VoxelPlanet.Block.BUILT):
		Game.take_cargo("stone")
		Sfx.play("place")
		return true
	return false


func refill() -> void:
	oxygen = MAX_OXYGEN
	health = 100.0
	jet_fuel = 1.0

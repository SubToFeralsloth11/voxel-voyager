class_name Drone
extends CharacterBody3D
## Hostile voxel sentry drone. Patrols its post, chases the piloted ship
## when it comes near and fires slow, dodgeable plasma bolts.

const AGGRO_RANGE := 260.0
const LEASH_RANGE := 520.0
const PREFERRED_DIST := 45.0
const SPEED := 38.0
const FIRE_INTERVAL := 1.7
const BOLT_SPEED := 85.0
const BOLT_DAMAGE := 7.0
const MAX_HEALTH := 40.0

var world: World
var home := Vector3.ZERO
var health := MAX_HEALTH
var _fire_timer := 1.0
var _patrol_angle := 0.0
var _visual: MeshInstance3D
var _bolts: Array[Node3D] = []
var _bolt_mesh: BoxMesh


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	home = global_position
	_patrol_angle = randf() * TAU
	var cells := {}
	var hull := Color(0.25, 0.22, 0.3)
	var eye := Color(1.0, 0.2, 0.25, 0.0)
	for z in range(-2, 3):
		for y in range(-1, 2):
			for x in range(-2, 3):
				if absi(x) + absi(y) + absi(z) <= 3:
					cells[Vector3i(x, y, z)] = hull
	for x: int in [-3, 3]:
		for z in range(-1, 2):
			cells[Vector3i(x, 0, z)] = Color(0.5, 0.15, 0.2)
	cells[Vector3i(0, 0, -3)] = eye
	_visual = MeshInstance3D.new()
	_visual.mesh = VoxelMesher.mesh_from_cells(cells, 0.8, Vector3(0.5, 0.5, 0.5))
	add_child(_visual)
	var col := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 2.4
	col.shape = ball
	add_child(col)
	_bolt_mesh = BoxMesh.new()
	_bolt_mesh.size = Vector3(0.5, 0.5, 2.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.3, 0.35)
	_bolt_mesh.material = mat


func _exit_tree() -> void:
	for b in _bolts:
		if is_instance_valid(b):
			b.queue_free()


func _physics_process(delta: float) -> void:
	_update_bolts(delta)
	var ship := world.ship if world else null
	var hunting := ship != null and ship.piloted and not ship.docked and not ship.landed \
		and ship.global_position.distance_to(global_position) < AGGRO_RANGE \
		and ship.global_position.distance_to(home) < LEASH_RANGE
	var desired: Vector3
	if hunting:
		var away := (global_position - ship.global_position).normalized()
		desired = ship.global_position + away * PREFERRED_DIST
		look_at(ship.global_position, Vector3.UP if absf(away.y) < 0.95 else Vector3.RIGHT)
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			_fire_timer = FIRE_INTERVAL
			_fire(ship)
	else:
		_patrol_angle += delta * 0.3
		desired = home + Vector3(cos(_patrol_angle), 0.2 * sin(_patrol_angle * 2.0), sin(_patrol_angle)) * 30.0
		var dir := desired - global_position
		if dir.length() > 1.0:
			look_at(global_position + dir, Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.RIGHT)
	var to := desired - global_position
	var wish := to.normalized() * minf(SPEED, to.length() * 1.5)
	velocity = velocity.lerp(wish, 1.0 - exp(-2.0 * delta))
	move_and_slide()


func _fire(ship: Ship) -> void:
	var bolt := MeshInstance3D.new()
	bolt.mesh = _bolt_mesh
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(bolt)
	var lead := ship.global_position + ship.velocity * (global_position.distance_to(ship.global_position) / BOLT_SPEED) * 0.5
	var dir := (lead - global_position).normalized()
	bolt.global_position = global_position + dir * 3.0
	bolt.look_at(bolt.global_position + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	bolt.set_meta("vel", dir * BOLT_SPEED)
	bolt.set_meta("life", 4.0)
	_bolts.append(bolt)
	Sfx.play("zap")


func _update_bolts(delta: float) -> void:
	var ship := world.ship if world else null
	for b: Node3D in _bolts.duplicate():
		var life: float = b.get_meta("life") - delta
		b.set_meta("life", life)
		b.global_position += (b.get_meta("vel") as Vector3) * delta
		var hit := ship != null and ship.piloted and not ship.docked \
			and b.global_position.distance_to(ship.global_position) < 3.2
		if hit:
			ship.take_damage(BOLT_DAMAGE)
			Sfx.play("hit")
		if hit or life <= 0.0:
			_bolts.erase(b)
			b.queue_free()


func take_laser(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		for i in 4:
			var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * 6.0
			world.spawn_pickup(global_position, "gold" if i < 3 else "crystal", v)
		world.spawn_debris(global_position, 3.0)
		Game.drones_destroyed += 1
		Game.credits += 40
		Game.notify("Sentry drone destroyed! +40 cr bounty", Color(1.0, 0.85, 0.4))
		Game.changed.emit()
		Sfx.play("explode")
		queue_free()

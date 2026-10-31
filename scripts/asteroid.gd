class_name Asteroid
extends StaticBody3D
## Voxel asteroid. Shoot it with the ship laser to crack it into ore pickups.

var world: World
var ore := "iron"
var health := 10.0
var size := 3.0
var _visual: MeshInstance3D
var _spin := Vector3.ZERO
var _flash := 0.0


func setup(mesh: Mesh, ore_id: String, radius: float, rng: RandomNumberGenerator) -> void:
	ore = ore_id
	size = radius
	health = 6.0 + radius * 3.0
	_visual = MeshInstance3D.new()
	_visual.mesh = mesh
	add_child(_visual)
	var col := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = radius * 0.9
	col.shape = ball
	add_child(col)
	_spin = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
	_visual.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


func _process(delta: float) -> void:
	_visual.rotation += _spin * delta
	if _flash > 0.0:
		_flash -= delta
		_visual.scale = Vector3.ONE * (1.0 + 0.06 * sin(_flash * 60.0))


func take_laser(amount: float) -> void:
	health -= amount
	_flash = 0.15
	if health <= 0.0:
		_shatter()


func _shatter() -> void:
	var count := 2 + int(size)
	for i in count:
		var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(3.0, 9.0)
		world.spawn_pickup(global_position + v * 0.3, ore if randf() < 0.75 else "stone", v)
	world.spawn_debris(global_position, size)
	Game.asteroids_destroyed += 1
	Sfx.play("explode")
	queue_free()

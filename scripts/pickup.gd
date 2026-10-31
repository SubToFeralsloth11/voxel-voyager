class_name Pickup
extends Node3D
## Floating ore cube dropped by asteroids and drones. Drifts, then gets
## pulled into the ship by its tractor field and stored as cargo.

const MAGNET_RANGE := 32.0
const COLLECT_RANGE := 4.0
const LIFETIME := 90.0

var ore := "iron"
var velocity := Vector3.ZERO
var ship: Ship
var _age := 0.0
var _spin := Vector3.ZERO


func setup(ore_id: String, start_velocity: Vector3, target: Ship) -> void:
	ore = ore_id
	velocity = start_velocity
	ship = target
	_spin = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.9
	var mat := StandardMaterial3D.new()
	var col: Color = Game.ORES[ore]["color"]
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.5
	box.material = mat
	mi.mesh = box
	add_child(mi)


func _process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		queue_free()
		return
	rotation += _spin * delta
	velocity *= exp(-0.8 * delta)
	if is_instance_valid(ship) and ship.piloted and not ship.docked:
		var to_ship := ship.global_position - global_position
		var dist := to_ship.length()
		if dist < COLLECT_RANGE:
			if Game.add_cargo(ore) > 0:
				Sfx.play("pickup")
				queue_free()
				return
			velocity = -to_ship.normalized() * 3.0
		elif dist < MAGNET_RANGE and Game.cargo_count() < Game.cargo_capacity():
			velocity = velocity.lerp(to_ship / dist * 40.0 + ship.velocity, 1.0 - exp(-4.0 * delta))
	global_position += velocity * delta

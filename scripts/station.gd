class_name Station
extends Node3D
## Trade outpost built from low-poly blocks with a slowly spinning ring.
## The ship docks by flying slowly into DOCK_RADIUS.

const DOCK_RADIUS := 48.0
const DOCK_MAX_SPEED := 22.0

var _ring: AnimatableBody3D
var _lights: Array[MeshInstance3D] = []
var _time := 0.0


func _ready() -> void:
	var hub := StaticBody3D.new()
	add_child(hub)
	var grey := Color(0.7, 0.72, 0.78)
	var dark := Color(0.28, 0.3, 0.36)
	var orange := Color(1.0, 0.55, 0.2)
	_block(hub, Vector3(10, 10, 10), Vector3.ZERO, grey)
	_block(hub, Vector3(4, 22, 4), Vector3.ZERO, dark)
	_block(hub, Vector3(14, 2, 14), Vector3(0, 6, 0), grey)
	_block(hub, Vector3(14, 2, 14), Vector3(0, -6, 0), grey)
	_block(hub, Vector3(1, 8, 1), Vector3(0, 15, 0), dark)
	_block(hub, Vector3(18, 0.4, 5), Vector3(14, 0, 0), Color(0.2, 0.35, 0.8), 0.4)
	_block(hub, Vector3(18, 0.4, 5), Vector3(-14, 0, 0), Color(0.2, 0.35, 0.8), 0.4)
	_ring = AnimatableBody3D.new()
	add_child(_ring)
	for i in 12:
		var a := TAU * i / 12.0
		var pos := Vector3(cos(a) * 24.0, 0, sin(a) * 24.0)
		var seg := _block(_ring, Vector3(6, 3, 12.5), pos, grey if i % 2 == 0 else dark)
		seg.rotation.y = -a
		seg.get_meta("shape").rotation.y = -a
	for i in 8:
		var a := TAU * i / 8.0
		var light := _block(hub, Vector3(1, 1, 1), Vector3(cos(a) * 7.2, 7.4, sin(a) * 7.2), orange, 3.0)
		_lights.append(light)
	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.8, 0.6)
	omni.omni_range = 60.0
	omni.light_energy = 1.5
	add_child(omni)


func _block(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = pos
	parent.add_child(col)
	mi.set_meta("shape", col)
	return mi


func _physics_process(delta: float) -> void:
	_time += delta
	_ring.rotate_y(delta * 0.12)
	for i in _lights.size():
		_lights[i].visible = int(_time * 2.0 + i) % 3 != 0


func can_dock(ship: Ship) -> bool:
	return ship.global_position.distance_to(global_position) < DOCK_RADIUS \
		and ship.velocity.length() < DOCK_MAX_SPEED

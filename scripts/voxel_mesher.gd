class_name VoxelMesher
extends RefCounted
## Accumulates voxel cube faces into packed arrays (an instance per mesh) and
## holds shared helpers: face tables, the vertex-colour material and a mesher
## for small free-floating voxel objects (asteroids, drones).

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
	Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Per face: [origin, u, v] with u x v == normal, so origin, +u, +u+v, +v
## run counter-clockwise seen from outside.
const FACES := [
	[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
	[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
	[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)],
]

static var _material: ShaderMaterial

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
## Triangle soup for ConcavePolygonShape3D; filled only when `with_faces`.
var faces := PackedVector3Array()
var with_faces := false


func _init(collect_faces := false) -> void:
	with_faces = collect_faces


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://shaders/voxel.gdshader")
	return _material


## Appends one quad as two clockwise triangles (Godot's front-face winding).
func emit_face(cell: Vector3, f: int, col: Color, scale := 1.0) -> void:
	var face: Array = FACES[f]
	var p0: Vector3 = (cell + face[0]) * scale
	var u: Vector3 = face[1] * scale
	var v: Vector3 = face[2] * scale
	var p1 := p0 + u
	var p2 := p0 + u + v
	var p3 := p0 + v
	var base := verts.size()
	verts.append(p0)
	verts.append(p1)
	verts.append(p2)
	verts.append(p3)
	var n := Vector3(DIRS[f])
	for i in 4:
		normals.append(n)
		colors.append(col)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base)
	indices.append(base + 3)
	indices.append(base + 2)
	if with_faces:
		faces.append(p0)
		faces.append(p2)
		faces.append(p1)
		faces.append(p0)
		faces.append(p3)
		faces.append(p2)


func is_empty() -> bool:
	return verts.is_empty()


func to_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = verts
	surface[Mesh.ARRAY_NORMAL] = normals
	surface[Mesh.ARRAY_COLOR] = colors
	surface[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	mesh.surface_set_material(0, material())
	return mesh


## Meshes a sparse set of cells (Vector3i -> Color) offset by -center.
static func mesh_from_cells(cells: Dictionary, scale := 1.0, center := Vector3.ZERO) -> ArrayMesh:
	var m := VoxelMesher.new()
	for c: Vector3i in cells:
		for f in 6:
			if not cells.has(c + DIRS[f]):
				m.emit_face(Vector3(c) - center, f, cells[c], scale)
	return m.to_mesh()


## Random lumpy voxel blob of the given radius, coloured from `base` with
## glowing `accent` speckles. Used for asteroids.
static func blob_cells(rng: RandomNumberGenerator, radius: float, base: Color, accent: Color) -> Dictionary:
	var cells := {}
	var r := int(ceil(radius)) + 1
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.35
	for z in range(-r, r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var p := Vector3(x, y, z)
				if p.length() <= radius * (0.8 + 0.35 * noise.get_noise_3dv(p)):
					var col: Color
					if rng.randf() < 0.12:
						col = accent
						col.a = 0.35
					else:
						col = base * rng.randf_range(0.85, 1.1)
						col.a = 1.0
					cells[Vector3i(x, y, z)] = col
	return cells

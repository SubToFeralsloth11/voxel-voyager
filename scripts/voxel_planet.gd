class_name VoxelPlanet
extends Node3D
## A small spherical voxel world. Terrain is a pure function of the planet
## seed plus the player's edits (Game.edits). Far away it is drawn as a
## low-poly proxy sphere; once the camera comes close, every chunk that can
## show faces is meshed on worker threads and swapped in.

enum Block { AIR, TOP, SOIL, ROCK, IRON, ICE, GOLD, CRYSTAL, BEACON, BUILT, BEDROCK, LAVA }

const CHUNK := 16
const PAD := CHUNK + 2
const PAD2 := PAD * PAD
const OFFSETS: Array[int] = [1, -1, PAD, -PAD, PAD2, -PAD2]
const BUILD_DISTANCE := 750.0
const NODES_PER_FRAME := 8
const BEACON_HEIGHT := 4

const DROPS := {
	Block.ROCK: "stone", Block.BUILT: "stone", Block.IRON: "iron", Block.ICE: "ice",
	Block.GOLD: "gold", Block.CRYSTAL: "crystal",
}
const HARDNESS := {
	Block.TOP: 0.3, Block.SOIL: 0.35, Block.ROCK: 0.7, Block.IRON: 1.0, Block.ICE: 0.5,
	Block.GOLD: 1.3, Block.CRYSTAL: 1.7, Block.BUILT: 0.4, Block.LAVA: 0.8,
}
const ORE_BLOCKS := {"iron": Block.IRON, "ice": Block.ICE, "gold": Block.GOLD, "crystal": Block.CRYSTAL}

var data: Dictionary
var key: String
var planet_name: String
var type_info: Dictionary
var radius := 30.0
var amplitude := 5.0
var surface_gravity := 9.0
var breathable := false
var has_beacon := false
var is_core := false
var built := false
var beacon_cells: Dictionary = {}
var beacon_local := Vector3.ZERO
var beacon_up := Vector3.UP

var _seed := 0
var _noise := FastNoiseLite.new()
var _edits: Dictionary
var _palette: Dictionary = {}
var _ore_table: Array = []
var _lava_rate := 0.0
var _chunks: Dictionary = {}
var _build_list: Array[Vector3i] = []
var _results: Array = []
var _results_mutex := Mutex.new()
var _task_id := -1
var _applied := 0
var _proxy: MeshInstance3D
var _proxy_body: StaticBody3D
var _beam: MeshInstance3D


func setup(planet_data: Dictionary) -> void:
	data = planet_data
	key = data["key"]
	planet_name = data["name"]
	type_info = Galaxy.PLANET_TYPES[data["type"]]
	radius = data["radius"]
	amplitude = radius * 0.16
	surface_gravity = clampf(radius / 30.0 * 9.0, 6.5, 13.5)
	breathable = type_info["breathable"]
	has_beacon = data["has_beacon"]
	is_core = data["core"]
	_seed = data["seed"]
	position = data["pos"]
	_noise.seed = _seed
	_noise.frequency = 0.045
	_noise.fractal_octaves = 3
	_edits = Game.planet_edits(key)
	_lava_rate = type_info["lava"]
	_palette = {
		Block.TOP: type_info["top"], Block.SOIL: type_info["soil"], Block.ROCK: type_info["rock"],
		Block.IRON: Color(0.85, 0.52, 0.34, 1.0), Block.ICE: Color(0.72, 0.93, 1.0, 0.8),
		Block.GOLD: Color(1.0, 0.82, 0.2, 0.6), Block.CRYSTAL: Color(0.85, 0.4, 1.0, 0.25),
		Block.BEACON: Color(1.0, 0.85, 0.3, 0.0) if is_core else Color(0.3, 1.0, 0.85, 0.0),
		Block.BUILT: Color(0.8, 0.8, 0.85, 1.0), Block.BEDROCK: Color(0.12, 0.1, 0.12, 1.0),
		Block.LAVA: Color(1.0, 0.45, 0.1, 0.0),
	}
	var acc := 0
	for ore: String in type_info["ores"]:
		acc += int(type_info["ores"][ore])
		_ore_table.append([acc, ORE_BLOCKS[ore]])
	if has_beacon:
		_place_beacon()
	_make_proxy()


func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_task_id)
		_task_id = -1


# --- terrain function --------------------------------------------------------

func surface_height(dir: Vector3) -> float:
	var n := clampf(_noise.get_noise_3dv(dir * radius), -1.0, 1.0)
	return radius + n * amplitude


func base_type(c: Vector3i) -> int:
	if beacon_cells.has(c):
		return Block.BEACON
	var p := Vector3(c) + Vector3(0.5, 0.5, 0.5)
	var d := p.length()
	if d > radius + amplitude + 1.0:
		return Block.AIR
	if d < 3.5:
		return Block.BEDROCK
	var depth := 99.0
	if d > radius - amplitude - 4.0:
		var h := surface_height(p / d)
		if d > h:
			return Block.AIR
		depth = h - d
	if depth < 1.0:
		if _lava_rate > 0.0 and Galaxy.hash4(c.x, c.y, c.z, _seed) % 1000 < int(_lava_rate * 1000.0):
			return Block.LAVA
		return Block.TOP
	if depth < 3.5:
		return Block.SOIL
	var roll := Galaxy.hash4(c.x >> 1, c.y >> 1, c.z >> 1, _seed + 7) % 1000
	if Galaxy.hash4(c.x, c.y, c.z, _seed + 3) % 10 < 7:
		for entry: Array in _ore_table:
			if roll < entry[0]:
				return entry[1]
	return Block.ROCK


func get_block(c: Vector3i) -> int:
	return int(_edits.get(c, base_type(c)))


func block_color(t: int, c: Vector3i) -> Color:
	var col: Color = _palette[t]
	var shade := 0.9 + float(Galaxy.hash4(c.x, c.y, c.z, 11) % 100) / 100.0 * 0.18
	return Color(col.r * shade, col.g * shade, col.b * shade, col.a)


func _place_beacon() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + 99
	var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
	var axis := 0
	if absf(dir.y) >= absf(dir.x) and absf(dir.y) >= absf(dir.z):
		axis = 1
	elif absf(dir.z) >= absf(dir.x):
		axis = 2
	var step := Vector3i.ZERO
	step[axis] = 1 if dir[axis] > 0.0 else -1
	var c := Vector3i((dir * (radius - amplitude - 2.0)).floor())
	while base_type(c + step) != Block.AIR:
		c += step
	var height := BEACON_HEIGHT * (2 if is_core else 1)
	for i in height:
		beacon_cells[c + step * (i + 1)] = true
	beacon_up = Vector3(step)
	beacon_local = Vector3(c + step) + Vector3(0.5, 0.5, 0.5)


# --- build pipeline ----------------------------------------------------------

func _process(_delta: float) -> void:
	if built:
		return
	if _task_id == -1:
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(global_position) < BUILD_DISTANCE + radius:
			start_build()
		return
	_apply_results(NODES_PER_FRAME)


func start_build() -> void:
	if _task_id != -1 or built or not _build_list.is_empty():
		return
	var bound := int(ceil((radius + amplitude + BEACON_HEIGHT * 2 + 3.0) / CHUNK))
	var edited_chunks := {}
	for c: Vector3i in _edits:
		edited_chunks[_chunk_of(c)] = true
	for z in range(-bound, bound):
		for y in range(-bound, bound):
			for x in range(-bound, bound):
				var cc := Vector3i(x, y, z)
				if edited_chunks.has(cc) or _chunk_may_show(cc):
					_build_list.append(cc)
	_task_id = WorkerThreadPool.add_group_task(_build_task, _build_list.size(), -1, false, "planet " + key)


## Synchronous build, used by tests and the tour.
func build_now() -> void:
	start_build()
	if _task_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_task_id)
		_task_id = -1
	_apply_results(1 << 30)


func _chunk_may_show(cc: Vector3i) -> bool:
	var lo := Vector3(cc * CHUNK)
	var hi := lo + Vector3.ONE * CHUNK
	var nearest := Vector3(clampf(0.0, lo.x, hi.x), clampf(0.0, lo.y, hi.y), clampf(0.0, lo.z, hi.z)).length()
	var farthest := Vector3(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.y), absf(hi.y)), maxf(absf(lo.z), absf(hi.z))).length()
	if nearest > radius + amplitude + BEACON_HEIGHT * 2 + 2.0:
		return false
	return farthest >= radius - amplitude - 2.0


func _build_task(index: int) -> void:
	var cc := _build_list[index]
	var types := _compute_types(cc)
	var mesher := _mesh_chunk(cc, types)
	_results_mutex.lock()
	_results.append([cc, types, mesher])
	_results_mutex.unlock()


func _apply_results(limit: int) -> void:
	_results_mutex.lock()
	var batch := _results.slice(0, limit)
	_results = _results.slice(limit)
	_results_mutex.unlock()
	for r: Array in batch:
		_apply_chunk(r[0], r[1], r[2])
		_applied += 1
	if _applied < _build_list.size():
		return
	if _task_id != -1:
		WorkerThreadPool.wait_for_group_task_completion(_task_id)
		_task_id = -1
	built = true
	_proxy.visible = false
	_proxy_body.queue_free()
	_proxy_body = null


func _compute_types(cc: Vector3i) -> PackedByteArray:
	var types := PackedByteArray()
	types.resize(PAD * PAD * PAD)
	var origin := cc * CHUNK - Vector3i.ONE
	var i := 0
	for z in PAD:
		for y in PAD:
			for x in PAD:
				types[i] = get_block(origin + Vector3i(x, y, z))
				i += 1
	return types


func _mesh_chunk(cc: Vector3i, types: PackedByteArray) -> VoxelMesher:
	var mesher := VoxelMesher.new(true)
	var origin := cc * CHUNK
	for z in CHUNK:
		for y in CHUNK:
			for x in CHUNK:
				var idx := (x + 1) + (y + 1) * PAD + (z + 1) * PAD2
				var t := types[idx]
				if t == Block.AIR:
					continue
				var cell := origin + Vector3i(x, y, z)
				var col := Color.BLACK
				var colored := false
				for f in 6:
					if types[idx + OFFSETS[f]] != Block.AIR:
						continue
					if not colored:
						col = block_color(t, cell)
						colored = true
					mesher.emit_face(Vector3(cell), f, col)
	return mesher


func _apply_chunk(cc: Vector3i, types: PackedByteArray, mesher: VoxelMesher) -> void:
	var entry: Dictionary = _chunks.get(cc, {})
	if entry.is_empty():
		var body := StaticBody3D.new()
		body.name = "Chunk_%d_%d_%d" % [cc.x, cc.y, cc.z]
		var mi := MeshInstance3D.new()
		var shape := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		concave.backface_collision = true
		shape.shape = concave
		body.add_child(mi)
		body.add_child(shape)
		add_child(body)
		entry = {"body": body, "mesh": mi, "shape": shape}
		_chunks[cc] = entry
	entry["types"] = types
	(entry["mesh"] as MeshInstance3D).mesh = mesher.to_mesh()
	var shape_node: CollisionShape3D = entry["shape"]
	(shape_node.shape as ConcavePolygonShape3D).set_faces(mesher.faces)
	shape_node.disabled = mesher.faces.is_empty()


# --- editing -----------------------------------------------------------------

static func _chunk_of(c: Vector3i) -> Vector3i:
	return Vector3i(c.x >> 4, c.y >> 4, c.z >> 4)


func world_to_cell(world_pos: Vector3) -> Vector3i:
	return Vector3i((world_pos - global_position).floor())


func cell_center(c: Vector3i) -> Vector3:
	return global_position + Vector3(c) + Vector3(0.5, 0.5, 0.5)


func can_mine(t: int) -> bool:
	return t != Block.AIR and t != Block.BEACON and t != Block.BEDROCK


## Removes a block. Returns the removed block type (AIR if nothing happened).
func mine(c: Vector3i) -> int:
	if not built:
		return Block.AIR
	var t := get_block(c)
	if not can_mine(t):
		return Block.AIR
	_set_block(c, Block.AIR)
	return t


func place(c: Vector3i, t: int) -> bool:
	if not built or get_block(c) != Block.AIR:
		return false
	_set_block(c, t)
	return true


func _set_block(c: Vector3i, t: int) -> void:
	_edits[c] = t
	var home := _chunk_of(c)
	var local := c - home * CHUNK
	var affected: Array[Vector3i] = [home]
	for axis in 3:
		var step := Vector3i.ZERO
		step[axis] = 1
		if local[axis] == 0:
			affected.append(home - step)
		elif local[axis] == CHUNK - 1:
			affected.append(home + step)
	for cc in affected:
		var entry: Dictionary = _chunks.get(cc, {})
		var types: PackedByteArray
		if entry.is_empty():
			types = _compute_types(cc)
		else:
			types = entry["types"]
			var l := c - cc * CHUNK + Vector3i.ONE
			types[l.x + l.y * PAD + l.z * PAD2] = t
		_apply_chunk(cc, types, _mesh_chunk(cc, types))


# --- queries -----------------------------------------------------------------

## Gravity acceleration (world-space vector) this planet exerts at a point.
func gravity_at(world_pos: Vector3) -> Vector3:
	var to_center := global_position - world_pos
	var dist := to_center.length()
	if dist > radius * 5.0 or dist < 0.01:
		return Vector3.ZERO
	var strength := surface_gravity
	if dist > radius:
		strength *= pow(radius / dist, 2.0)
	return to_center / dist * strength


func influence_radius() -> float:
	return radius * 5.0


func has_atmosphere() -> bool:
	return type_info["atmo"] != null


func altitude(world_pos: Vector3) -> float:
	var rel := world_pos - global_position
	return rel.length() - surface_height(rel.normalized())


func beacon_world() -> Vector3:
	return global_position + beacon_local


func resource_names() -> Array:
	var names := []
	for ore: String in type_info["ores"]:
		names.append(Game.ORES[ore]["name"])
	return names


func set_scanned(value: bool) -> void:
	if _beam:
		_beam.visible = value


# --- visuals -----------------------------------------------------------------

func _make_proxy() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 18
	sphere.rings = 9
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/lowpoly.gdshader")
	mat.set_shader_parameter("albedo", type_info["top"])
	sphere.material = mat
	_proxy = MeshInstance3D.new()
	_proxy.mesh = sphere
	add_child(_proxy)
	_proxy_body = StaticBody3D.new()
	var col := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = radius - amplitude
	col.shape = ball
	_proxy_body.add_child(col)
	add_child(_proxy_body)
	if has_atmosphere():
		var halo := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = radius * 1.35
		hs.height = radius * 2.7
		hs.radial_segments = 32
		hs.rings = 16
		var hm := ShaderMaterial.new()
		hm.shader = preload("res://shaders/atmosphere.gdshader")
		hm.set_shader_parameter("tint", type_info["atmo"])
		hs.material = hm
		halo.mesh = hs
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
	if has_beacon:
		_beam = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.5
		cyl.bottom_radius = 0.5
		cyl.height = 600.0
		cyl.radial_segments = 6
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var beam_col: Color = _palette[Block.BEACON]
		bm.albedo_color = Color(beam_col.r, beam_col.g, beam_col.b, 0.35)
		cyl.material = bm
		_beam.mesh = cyl
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var top := beacon_local + beacon_up * (BEACON_HEIGHT * (2 if is_core else 1) + 300.0)
		_beam.transform = Transform3D(_basis_for_up(beacon_up), top)
		_beam.visible = Game.scanned.has(key)
		add_child(_beam)
		var light := OmniLight3D.new()
		light.light_color = beam_col
		light.light_energy = 2.0
		light.omni_range = 14.0
		light.position = beacon_local + beacon_up * BEACON_HEIGHT
		add_child(light)


static func _basis_for_up(up: Vector3) -> Basis:
	var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	return Basis(x, up, x.cross(up)).orthonormalized()

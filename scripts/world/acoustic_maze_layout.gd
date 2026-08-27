class_name AcousticMazeLayout
extends RefCounted

## One deterministic layout owns the hard-maze regression, authoritative collision/probes, and
## client presentation. Changing the seed or dimensions therefore cannot silently leave the test
## and playable field with different topology.

const WIDTH := 11
const HEIGHT := 11
const CELL_SIZE := 4.0
const WALL_THICKNESS := 0.32
const WALL_HEIGHT := 3.4
const LISTENER_HEIGHT := 1.6
const SEED := 0x5CA7_2026
const ENTRANCE_CELL := 5 # Center cell on the south edge.
const ENTRANCE_WIDTH := 2.6
const WORLD_POSITION := Vector3(150.0, 0.02, -10.0)
const WORLD_CLEARANCE_MARGIN := 0.5
const EXTERIOR_PROBE_OFFSET := CELL_SIZE * 0.5
const EXTERIOR_PROBE_CONNECT_RADIUS := CELL_SIZE * 2.1
const INTERIOR_AUTO_CONNECT_LAYER := 1 << 1
const EXTERIOR_AUTO_CONNECT_LAYER := 1 << 2
const WORLD_AUTO_CONNECT_LAYER := 1

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.RIGHT,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.UP,
]

static var _adjacency: Array[Array] = []
static var _structural_boxes: Array[Dictionary] = []
static var _exterior_probe_descriptors: Array[Dictionary] = []


static func cell_count() -> int:
	return WIDTH * HEIGHT


static func adjacency() -> Array[Array]:
	_ensure_adjacency()
	return _adjacency


static func cell_position(cell: int) -> Vector3:
	var coordinate := cell_coordinate(cell)
	return Vector3(
		(float(coordinate.x) - float(WIDTH - 1) * 0.5) * CELL_SIZE,
		LISTENER_HEIGHT,
		(float(coordinate.y) - float(HEIGHT - 1) * 0.5) * CELL_SIZE
	)


static func entrance_position() -> Vector3:
	var position := cell_position(ENTRANCE_CELL)
	position.z = -float(HEIGHT) * CELL_SIZE * 0.5 - 1.0
	return position


static func exit_cell() -> int:
	return int(_farthest_cell(ENTRANCE_CELL).get("cell", cell_count() - 1))


static func entrance_route_distance_cells() -> int:
	return int(_farthest_cell(ENTRANCE_CELL).get("distance", 0))


static func exit_position() -> Vector3:
	return cell_position(exit_cell())


static func structural_boxes() -> Array[Dictionary]:
	if not _structural_boxes.is_empty():
		return _structural_boxes
	_ensure_adjacency()
	var total_width := float(WIDTH) * CELL_SIZE
	var total_depth := float(HEIGHT) * CELL_SIZE
	_append_box(
		&"MazeFloor",
		Vector3(0.0, -WALL_THICKNESS * 0.5, 0.0),
		Vector3(total_width + WALL_THICKNESS, WALL_THICKNESS, total_depth + WALL_THICKNESS),
		&"floor"
	)
	_append_box(
		&"MazeRoof",
		Vector3(0.0, WALL_HEIGHT + WALL_THICKNESS * 0.5, 0.0),
		Vector3(total_width + WALL_THICKNESS, WALL_THICKNESS, total_depth + WALL_THICKNESS),
		&"roof"
	)
	_append_box(
		&"MazeWestWall",
		Vector3(-total_width * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, total_depth + WALL_THICKNESS),
		&"wall"
	)
	_append_box(
		&"MazeEastWall",
		Vector3(total_width * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, total_depth + WALL_THICKNESS),
		&"wall"
	)
	_append_box(
		&"MazeNorthWall",
		Vector3(0.0, WALL_HEIGHT * 0.5, total_depth * 0.5),
		Vector3(total_width + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
		&"wall"
	)
	_append_south_wall_with_entrance(total_width, total_depth)

	for y: int in range(HEIGHT):
		for x: int in range(WIDTH):
			var cell := cell_index(Vector2i(x, y))
			if x + 1 < WIDTH:
				var right := cell_index(Vector2i(x + 1, y))
				if not _adjacency[cell].has(right):
					var a := cell_position(cell)
					var b := cell_position(right)
					_append_box(
						StringName("MazeWallX_%02d_%02d" % [x, y]),
						Vector3((a.x + b.x) * 0.5, WALL_HEIGHT * 0.5, a.z),
						Vector3(WALL_THICKNESS, WALL_HEIGHT, CELL_SIZE + WALL_THICKNESS),
						&"wall"
					)
			if y + 1 < HEIGHT:
				var down := cell_index(Vector2i(x, y + 1))
				if not _adjacency[cell].has(down):
					var a := cell_position(cell)
					var b := cell_position(down)
					_append_box(
						StringName("MazeWallZ_%02d_%02d" % [x, y]),
						Vector3(a.x, WALL_HEIGHT * 0.5, (a.z + b.z) * 0.5),
						Vector3(CELL_SIZE + WALL_THICKNESS, WALL_HEIGHT, WALL_THICKNESS),
						&"wall"
					)
	return _structural_boxes


static func probe_descriptors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(cell_count())
	for cell: int in range(cell_count()):
		result[cell] = {
			"name": "MazeProbe_%03d" % cell,
			"probe_id": "maze_%03d" % cell,
			"position": cell_position(cell),
			"auto_connect_layer": INTERIOR_AUTO_CONNECT_LAYER,
			"auto_connect_mask": INTERIOR_AUTO_CONNECT_LAYER,
			# Each sample owns its corridor cell and overlaps its cardinal neighbors only near
			# the opening between them. This prevents a zero-width diagonal corner seam from
			# becoming an endpoint shortcut while keeping transitions continuous at doorways.
			"attachment_influence_half_extents": Vector3(
				CELL_SIZE * 0.5,
				WALL_HEIGHT,
				CELL_SIZE * 0.5
			),
			"attachment_influence_boundary_fade": CELL_SIZE * 0.1875,
		}
	return result


static func exterior_probe_descriptors() -> Array[Dictionary]:
	if not _exterior_probe_descriptors.is_empty():
		return _exterior_probe_descriptors
	var half_width := float(WIDTH) * CELL_SIZE * 0.5 + EXTERIOR_PROBE_OFFSET
	var half_depth := float(HEIGHT) * CELL_SIZE * 0.5 + EXTERIOR_PROBE_OFFSET
	_append_exterior_probe(&"MazeEntranceExteriorProbe", &"maze_exterior_entrance", Vector3(
		0.0,
		LISTENER_HEIGHT,
		-half_depth
	), ENTRANCE_CELL, true)
	var horizontal_steps := roundi(half_width / CELL_SIZE)
	for step: int in range(1, horizontal_steps + 1):
		for side: int in [-1, 1]:
			var transmission_cell := (
				cell_index(Vector2i(ENTRANCE_CELL + side * step, 0))
				if step < horizontal_steps
				else -1
			)
			_append_exterior_probe(
				StringName("MazeSouthExteriorProbe_%s_%02d" % ["W" if side < 0 else "E", step]),
				StringName("maze_exterior_south_%s_%02d" % ["w" if side < 0 else "e", step]),
				Vector3(float(side * step) * CELL_SIZE, LISTENER_HEIGHT, -half_depth),
				transmission_cell
			)
	var vertical_steps := roundi((half_depth * 2.0) / CELL_SIZE)
	for step: int in range(1, vertical_steps + 1):
		var z := -half_depth + float(step) * CELL_SIZE
		for side: int in [-1, 1]:
			_append_exterior_probe(
				StringName("Maze%sExteriorProbe_%02d" % ["West" if side < 0 else "East", step]),
				StringName("maze_exterior_%s_%02d" % ["west" if side < 0 else "east", step]),
				Vector3(float(side) * half_width, LISTENER_HEIGHT, z),
				(
					cell_index(Vector2i(0 if side < 0 else WIDTH - 1, step - 1))
					if step < vertical_steps
					else -1
				)
			)
	for step: int in range(1, horizontal_steps * 2):
		var x := -half_width + float(step) * CELL_SIZE
		_append_exterior_probe(
			StringName("MazeNorthExteriorProbe_%02d" % step),
			StringName("maze_exterior_north_%02d" % step),
			Vector3(x, LISTENER_HEIGHT, half_depth),
			cell_index(Vector2i(step - 1, HEIGHT - 1))
		)
	return _exterior_probe_descriptors


static func _append_exterior_probe(
	probe_name: StringName,
	probe_id: StringName,
	position: Vector3,
	transmission_cell := -1,
	is_open_aperture := false
) -> void:
	var descriptor := {
		"name": probe_name,
		"probe_id": probe_id,
		"position": position,
		"auto_connect_radius": EXTERIOR_PROBE_CONNECT_RADIUS,
		"sample_reflections": false,
		"environment_influence_radius": CELL_SIZE,
		"auto_connect_layer": EXTERIOR_AUTO_CONNECT_LAYER,
		"auto_connect_mask": EXTERIOR_AUTO_CONNECT_LAYER | WORLD_AUTO_CONNECT_LAYER,
		# Perimeter probes describe pressure after it has crossed the maze shell. They must not
		# become endpoint shortcuts for listeners or sources that are physically inside that shell.
		# The graph still permits the directed exterior-to-interior radiation edge, so outdoor
		# listeners hear an indoor source while interior routing remains on the corridor graph.
		"attachment_exclusion_center_offset": Vector3(0.0, WALL_HEIGHT * 0.5, 0.0) - position,
		"attachment_exclusion_half_extents": Vector3(
			float(WIDTH) * CELL_SIZE * 0.5 + WALL_THICKNESS,
			WALL_HEIGHT,
			float(HEIGHT) * CELL_SIZE * 0.5 + WALL_THICKNESS
		),
	}
	if transmission_cell >= 0:
		descriptor["transmission_cell"] = transmission_cell
		descriptor["is_open_aperture"] = is_open_aperture
	_exterior_probe_descriptors.append(descriptor)


static func local_bounds() -> AABB:
	var total_width := float(WIDTH) * CELL_SIZE + WALL_THICKNESS
	var total_depth := float(HEIGHT) * CELL_SIZE + WALL_THICKNESS
	return AABB(
		Vector3(-total_width * 0.5, -WALL_THICKNESS, -total_depth * 0.5),
		Vector3(total_width, WALL_HEIGHT + WALL_THICKNESS * 2.0, total_depth)
	)


static func create_acoustic_material() -> AcousticMaterial:
	var material := AcousticMaterial.new()
	material.material_id = &"maze_reinforced_concrete"
	material.transmission_gain = Vector3(0.34, 0.055, 0.008)
	material.absorption = Vector3(0.07, 0.14, 0.32)
	material.scattering = 0.24
	material.transmission_volume_db = -10.0
	material.transmission_lowpass_hz = 1250.0
	material.resonance = 0.12
	material.reverb_send = 0.34
	return material


static func cell_coordinate(cell: int) -> Vector2i:
	return Vector2i(cell % WIDTH, cell / WIDTH)


static func cell_index(coordinate: Vector2i) -> int:
	return coordinate.y * WIDTH + coordinate.x


static func coordinate_is_valid(coordinate: Vector2i) -> bool:
	return (
		coordinate.x >= 0
		and coordinate.y >= 0
		and coordinate.x < WIDTH
		and coordinate.y < HEIGHT
	)


static func _ensure_adjacency() -> void:
	if not _adjacency.is_empty():
		return
	_adjacency.resize(cell_count())
	for cell: int in range(cell_count()):
		_adjacency[cell] = []
	var visited := PackedByteArray()
	visited.resize(cell_count())
	var stack: Array[int] = [0]
	visited[0] = 1
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	while not stack.is_empty():
		var cell := stack[stack.size() - 1]
		var choices: Array[int] = []
		var coordinate := cell_coordinate(cell)
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor_coordinate := coordinate + direction
			if not coordinate_is_valid(neighbor_coordinate):
				continue
			var neighbor := cell_index(neighbor_coordinate)
			if visited[neighbor] == 0:
				choices.append(neighbor)
		if choices.is_empty():
			stack.pop_back()
			continue
		var next_cell := choices[random.randi_range(0, choices.size() - 1)]
		_adjacency[cell].append(next_cell)
		_adjacency[next_cell].append(cell)
		visited[next_cell] = 1
		stack.append(next_cell)


static func _farthest_cell(start: int) -> Dictionary:
	_ensure_adjacency()
	var distances := PackedInt32Array()
	distances.resize(cell_count())
	distances.fill(-1)
	var queue := PackedInt32Array([start])
	distances[start] = 0
	var read_index := 0
	while read_index < queue.size():
		var cell := queue[read_index]
		read_index += 1
		for neighbor_value: Variant in _adjacency[cell]:
			var neighbor := int(neighbor_value)
			if distances[neighbor] >= 0:
				continue
			distances[neighbor] = distances[cell] + 1
			queue.append(neighbor)
	var farthest := start
	for cell: int in range(distances.size()):
		if distances[cell] > distances[farthest]:
			farthest = cell
	return {"cell": farthest, "distance": distances[farthest]}


static func _append_south_wall_with_entrance(total_width: float, total_depth: float) -> void:
	var entrance_x := cell_position(ENTRANCE_CELL).x
	var wall_min_x := -total_width * 0.5 - WALL_THICKNESS * 0.5
	var wall_max_x := total_width * 0.5 + WALL_THICKNESS * 0.5
	var opening_min_x := entrance_x - ENTRANCE_WIDTH * 0.5
	var opening_max_x := entrance_x + ENTRANCE_WIDTH * 0.5
	var left_width := opening_min_x - wall_min_x
	var right_width := wall_max_x - opening_max_x
	_append_box(
		&"MazeSouthWallWest",
		Vector3(wall_min_x + left_width * 0.5, WALL_HEIGHT * 0.5, -total_depth * 0.5),
		Vector3(left_width, WALL_HEIGHT, WALL_THICKNESS),
		&"wall"
	)
	_append_box(
		&"MazeSouthWallEast",
		Vector3(opening_max_x + right_width * 0.5, WALL_HEIGHT * 0.5, -total_depth * 0.5),
		Vector3(right_width, WALL_HEIGHT, WALL_THICKNESS),
		&"wall"
	)


static func _append_box(
	name: StringName,
	position: Vector3,
	size: Vector3,
	material_id: StringName
) -> void:
	_structural_boxes.append({
		"name": name,
		"position": position,
		"size": size,
		"material_id": material_id,
	})

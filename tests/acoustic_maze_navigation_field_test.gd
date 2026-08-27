extends SceneTree

const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const REPORT_PATH := "res://tests/generated/acoustic_maze_navigation_field.json"
const MAZE_WIDTH := LAYOUT.WIDTH
const MAZE_HEIGHT := LAYOUT.HEIGHT
const CELL_SIZE := LAYOUT.CELL_SIZE
const WALL_THICKNESS := LAYOUT.WALL_THICKNESS
const WALL_HEIGHT := LAYOUT.WALL_HEIGHT
const LISTENER_HEIGHT := LAYOUT.LISTENER_HEIGHT
const MAZE_SEED := LAYOUT.SEED
const SOURCE_MAX_DISTANCE := 700.0
const SOURCE_GAIN_DB := 12.0
const FIRST_LISTENER_ID := 5_200_000
const MIN_BRANCH_ADVANTAGE_DB := 0.0
const MIN_HALL_ROUTE_FRACTION := 0.75

const CARDINAL_DIRECTIONS: Array[Vector2i] = LAYOUT.CARDINAL_DIRECTIONS

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var adjacency := _generate_perfect_maze()
	var first_end := _farthest_cell(0, adjacency)
	var start_cell := int(first_end.get("cell", 0))
	var second_end := _farthest_cell(start_cell, adjacency)
	var exit_cell := int(second_end.get("cell", _cell_count() - 1))
	var route := _shortest_route(start_cell, exit_cell, adjacency)
	var exit_distances := _distances_from(exit_cell, adjacency)

	var world := _build_maze_world(adjacency)
	root.add_child(world)
	await physics_frame
	await process_frame
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	await physics_frame

	var source_modifier := AcousticPathModifier.new()
	source_modifier.modifier_id = &"maze_exit_alarm"
	source_modifier.volume_db = SOURCE_GAIN_DB
	source_modifier.band_gain = Vector3(1.0, 0.97, 0.9)
	source_modifier.reverb_send = 0.12
	var source_position := _cell_position(exit_cell)
	var source_attachment := service.create_source_attachment(source_position)
	var measurements: Array[Dictionary] = []
	measurements.resize(_cell_count())
	var audible_count := 0
	var hall_cell_count := 0
	var graph_dominant_cell_count := 0
	var direct_dominant_cell_count := 0
	for cell: int in range(_cell_count()):
		var listener_position := _cell_position(cell)
		var result := service.calculate_listener_result(
			FIRST_LISTENER_ID + cell,
			listener_position,
			source_position,
			SOURCE_MAX_DISTANCE,
			source_modifier,
			1.0,
			false,
			[],
			0,
			0.0,
			{},
			source_attachment
		)
		var listener_field := service._fields_by_listener.get(
			FIRST_LISTENER_ID + cell
		) as AcousticPropagationField
		var graph_only_result := service.graph.sample_source_attached(
			listener_field,
			source_position,
			source_attachment.probes,
			source_attachment.probe_count,
			SOURCE_MAX_DISTANCE,
			source_modifier,
			1.0,
			listener_position,
			false,
			source_attachment.visibility_confirmed
		)
		service.graph.apply_environment_to_result(
			graph_only_result,
			listener_position,
			source_position,
			listener_field,
			int(graph_only_result.get("source_probe_index", -1))
		)
		var audible := bool(result.get("audible", false))
		if audible:
			audible_count += 1
		if float(result.get("reverb_send", 0.0)) >= 0.08:
			hall_cell_count += 1
		var route_kind := str(result.get("route_kind", &"none"))
		if (
			route_kind == "graph"
			or float(result.get("route_graph_energy_weight", 0.0)) >= 0.5
		):
			graph_dominant_cell_count += 1
		elif audible:
			direct_dominant_cell_count += 1
		measurements[cell] = _measurement(
			cell,
			result,
			graph_only_result,
			exit_distances[cell]
		)

	var junctions := _analyze_route_junctions(
		route,
		adjacency,
		measurements,
		exit_distances,
		&"volume_db"
	)
	var graph_junctions := _analyze_route_junctions(
		route,
		adjacency,
		measurements,
		exit_distances,
		&"graph_only_volume_db"
	)
	var volume_navigation := _navigate_by_neighbor_volume(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		exit_distances,
		&"volume_db",
		&"apparent_position"
	)
	var direction_navigation := _navigate_by_apparent_direction(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		exit_distances,
		&"volume_db",
		&"apparent_position"
	)
	var graph_volume_navigation := _navigate_by_neighbor_volume(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		exit_distances,
		&"graph_only_volume_db",
		&"graph_only_apparent_position"
	)
	var graph_direction_navigation := _navigate_by_apparent_direction(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		exit_distances,
		&"graph_only_volume_db",
		&"graph_only_apparent_position"
	)
	var wall_shortcuts := _wall_shortcut_traps(
		route,
		adjacency,
		measurements,
		exit_distances
	)
	var graph_state := service.get_debug_state()
	var report := {
		"schema_version": 1,
		"maze": {
			"width": MAZE_WIDTH,
			"height": MAZE_HEIGHT,
			"cell_size": CELL_SIZE,
			"seed": MAZE_SEED,
			"start_cell": _cell_array(start_cell),
			"exit_cell": _cell_array(exit_cell),
			"route_cell_count": route.size(),
			"open_edges": _serialized_edges(adjacency),
		},
		"source": {
			"position": _vector_array(source_position),
			"maximum_distance": SOURCE_MAX_DISTANCE,
			"gain_db": SOURCE_GAIN_DB,
		},
		"graph": graph_state,
		"summary": {
			"audible_cell_count": audible_count,
			"hall_cell_count": hall_cell_count,
			"graph_dominant_cell_count": graph_dominant_cell_count,
			"direct_dominant_cell_count": direct_dominant_cell_count,
			"junction_count": junctions.size(),
			"minimum_correct_branch_advantage_db": _minimum_branch_advantage(
				junctions
			),
			"graph_minimum_correct_branch_advantage_db": (
				_minimum_branch_advantage(graph_junctions)
			),
			"volume_navigation_reached_exit": bool(
				volume_navigation.get("reached_exit", false)
			),
			"direction_navigation_reached_exit": bool(
				direction_navigation.get("reached_exit", false)
			),
			"graph_volume_navigation_reached_exit": bool(
				graph_volume_navigation.get("reached_exit", false)
			),
			"graph_direction_navigation_reached_exit": bool(
				graph_direction_navigation.get("reached_exit", false)
			),
			"wall_shortcut_trap_count": wall_shortcuts.size(),
			"runtime_seconds": (
				float(Time.get_ticks_msec() - started_msec) * 0.001
			),
		},
		"expected_route": _serialized_cells(route),
		"junctions": junctions,
		"graph_junctions": graph_junctions,
		"wall_shortcut_traps": wall_shortcuts,
		"volume_navigation": volume_navigation,
		"direction_navigation": direction_navigation,
		"graph_volume_navigation": graph_volume_navigation,
		"graph_direction_navigation": graph_direction_navigation,
		"measurements": _serialized_measurements(measurements),
	}
	_expect(_save_report(report), "the complete maze acoustic field serializes as JSON")
	_expect(
		service.graph.probe_count() == _cell_count()
		and int(graph_state.get("directed_edge_count", -1))
		== (_cell_count() - 1) * 2,
		"the collision bake recovers exactly the perfect-maze air topology"
	)
	_expect(
		route.size() >= 45 and junctions.size() >= 6,
		"the deterministic field contains a long route with many tempting branches"
	)
	_expect(
		audible_count == _cell_count(),
		"the loud exit source reaches every navigable maze cell"
	)
	_expect(
		float(hall_cell_count) / float(_cell_count()) >= MIN_HALL_ROUTE_FRACTION,
		"most maze cells receive a collision-derived indoor hall response"
	)
	_expect(
		graph_dominant_cell_count > direct_dominant_cell_count,
		"the routed hall—not one first-wall transmission sample—dominates a multi-wall maze"
	)
	_expect(
		bool(graph_volume_navigation.get("reached_exit", false)),
		"the isolated baked graph has a monotonically useful loudness gradient"
	)
	_expect(
		bool(graph_direction_navigation.get("reached_exit", false)),
		"the isolated baked graph points through every correct opening"
	)
	_expect(
		_minimum_branch_advantage(junctions) >= MIN_BRANCH_ADVANTAGE_DB,
		"the next cell on the true route is the loudest open branch at every junction"
	)
	_expect(
		bool(volume_navigation.get("reached_exit", false))
		and (volume_navigation.get("trace", []) as Array).size() == route.size(),
		"a navigator using only neighboring sound levels reaches the exit without a detour"
	)
	_expect(
		bool(direction_navigation.get("reached_exit", false))
		and (direction_navigation.get("trace", []) as Array).size() == route.size(),
		"the apparent sound direction points through the correct sequence of openings"
	)
	_expect(
		wall_shortcuts.size() >= 4
		and _wall_shortcuts_reject_false_direction(wall_shortcuts),
		"nearby source-side cells behind walls cannot steal direction from the open route"
	)
	print(
		"Acoustic maze: %d cells, route %d, junctions %d, branch margin %.3f dB, volume=%s, direction=%s"
		% [
			_cell_count(),
			route.size(),
			junctions.size(),
			_minimum_branch_advantage(junctions),
			str(volume_navigation.get("reached_exit", false)),
			str(direction_navigation.get("reached_exit", false)),
		]
	)
	await _finish(world, service)


func _generate_perfect_maze() -> Array[Array]:
	return LAYOUT.adjacency()


func _build_maze_world(_adjacency: Array[Array]) -> Node3D:
	var world := Node3D.new()
	world.name = "AcousticMazeField"
	var shell := StaticBody3D.new()
	shell.name = "ReflectiveMazeShell"
	shell.set_meta(&"acoustic_boundary", true)
	shell.set_meta(&"acoustic_material", _maze_material())
	world.add_child(shell)
	for descriptor: Dictionary in LAYOUT.structural_boxes():
		_add_box(
			shell,
			descriptor.get("position", Vector3.ZERO),
			descriptor.get("size", Vector3.ONE)
		)
	for descriptor: Dictionary in LAYOUT.probe_descriptors():
		var probe := AcousticProbe3D.new()
		probe.name = str(descriptor.get("name", "MazeProbe"))
		probe.probe_id = StringName(str(descriptor.get("probe_id", "")))
		probe.position = descriptor.get("position", Vector3.ZERO)
		probe.auto_connect_radius = float(descriptor.get(
			"auto_connect_radius",
			CELL_SIZE * 1.08
		))
		probe.auto_connect_layer = int(descriptor.get("auto_connect_layer", 1))
		probe.auto_connect_mask = int(descriptor.get("auto_connect_mask", 0x7fffffff))
		probe.environment_influence_radius = float(descriptor.get(
			"environment_influence_radius",
			CELL_SIZE * 0.92
		))
		probe.reflection_sample_distance = 22.0
		probe.attachment_influence_center_offset = descriptor.get(
			"attachment_influence_center_offset",
			Vector3.ZERO
		)
		probe.attachment_influence_half_extents = descriptor.get(
			"attachment_influence_half_extents",
			Vector3.ZERO
		)
		probe.attachment_influence_boundary_fade = float(descriptor.get(
			"attachment_influence_boundary_fade",
			0.0
		))
		world.add_child(probe)
	return world


func _maze_material() -> AcousticMaterial:
	return LAYOUT.create_acoustic_material()


func _add_box(body: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.position = position
	collision.shape = shape
	body.add_child(collision)


func _analyze_route_junctions(
	route: Array[int],
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	exit_distances: PackedInt32Array,
	volume_key: StringName
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route_index: int in range(route.size() - 1):
		var cell := route[route_index]
		var previous := route[route_index - 1] if route_index > 0 else -1
		var correct := route[route_index + 1]
		var alternatives: Array[int] = []
		for neighbor_value: Variant in adjacency[cell]:
			var neighbor := int(neighbor_value)
			if neighbor != previous and neighbor != correct:
				alternatives.append(neighbor)
		if alternatives.is_empty():
			continue
		var correct_volume := float(measurements[correct].get(volume_key, -80.0))
		var loudest_wrong_volume := -INF
		var loudest_wrong := -1
		for alternative: int in alternatives:
			var alternative_volume := float(
				measurements[alternative].get(volume_key, -80.0)
			)
			if alternative_volume > loudest_wrong_volume:
				loudest_wrong_volume = alternative_volume
				loudest_wrong = alternative
		result.append({
			"cell": _cell_array(cell),
			"distance_to_exit_cells": exit_distances[cell],
			"correct_cell": _cell_array(correct),
			"correct_volume_db": correct_volume,
			"loudest_wrong_cell": _cell_array(loudest_wrong),
			"loudest_wrong_volume_db": loudest_wrong_volume,
			"correct_advantage_db": correct_volume - loudest_wrong_volume,
			"wrong_cells": _serialized_cells(alternatives),
		})
	return result


func _navigate_by_neighbor_volume(
	start_cell: int,
	exit_cell: int,
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	exit_distances: PackedInt32Array,
	volume_key: StringName,
	apparent_key: StringName
) -> Dictionary:
	var current := start_cell
	var previous := -1
	var trace: Array[Dictionary] = []
	for step: int in range(_cell_count()):
		trace.append(_navigation_step(
			current, measurements, exit_distances, volume_key, apparent_key
		))
		if current == exit_cell:
			return {"reached_exit": true, "trace": trace}
		var chosen := -1
		var chosen_volume := -INF
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if neighbor == previous:
				continue
			var volume := float(measurements[neighbor].get(volume_key, -80.0))
			if volume > chosen_volume:
				chosen_volume = volume
				chosen = neighbor
		if chosen < 0:
			break
		if exit_distances[chosen] != exit_distances[current] - 1:
			return {
				"reached_exit": false,
				"failure": {
					"reason": "loudest_neighbor_is_not_on_exit_route",
					"cell": _cell_array(current),
					"chosen_cell": _cell_array(chosen),
					"chosen_volume_db": chosen_volume,
				},
				"trace": trace,
			}
		previous = current
		current = chosen
	return {"reached_exit": false, "trace": trace}


func _navigate_by_apparent_direction(
	start_cell: int,
	exit_cell: int,
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	exit_distances: PackedInt32Array,
	volume_key: StringName,
	apparent_key: StringName
) -> Dictionary:
	var current := start_cell
	var previous := -1
	var trace: Array[Dictionary] = []
	for step: int in range(_cell_count()):
		trace.append(_navigation_step(
			current, measurements, exit_distances, volume_key, apparent_key
		))
		if current == exit_cell:
			return {"reached_exit": true, "trace": trace}
		var current_position := _cell_position(current)
		var apparent: Vector3 = measurements[current].get(
			apparent_key,
			current_position
		)
		var heard_direction := (apparent - current_position).normalized()
		var chosen := -1
		var chosen_alignment := -INF
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if neighbor == previous:
				continue
			var neighbor_direction := (
				_cell_position(neighbor) - current_position
			).normalized()
			var alignment := heard_direction.dot(neighbor_direction)
			if alignment > chosen_alignment:
				chosen_alignment = alignment
				chosen = neighbor
		if chosen < 0:
			break
		if exit_distances[chosen] != exit_distances[current] - 1:
			return {
				"reached_exit": false,
				"failure": {
					"reason": "apparent_direction_does_not_point_down_exit_route",
					"cell": _cell_array(current),
					"chosen_cell": _cell_array(chosen),
					"chosen_alignment": chosen_alignment,
					"apparent_position": _vector_array(apparent),
				},
				"trace": trace,
			}
		previous = current
		current = chosen
	return {"reached_exit": false, "trace": trace}


func _wall_shortcut_traps(
	route: Array[int],
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	exit_distances: PackedInt32Array
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route_index: int in range(route.size() - 1):
		var cell := route[route_index]
		var correct := route[route_index + 1]
		var coordinate := _cell_coordinate(cell)
		for direction: Vector2i in CARDINAL_DIRECTIONS:
			var neighbor_coordinate := coordinate + direction
			if not _coordinate_is_valid(neighbor_coordinate):
				continue
			var wall_neighbor := _cell_index(neighbor_coordinate)
			if adjacency[cell].has(wall_neighbor):
				continue
			if exit_distances[cell] - exit_distances[wall_neighbor] < 8:
				continue
			var current_position := _cell_position(cell)
			var apparent: Vector3 = measurements[cell].get(
				"apparent_position",
				current_position
			)
			var heard_direction := (apparent - current_position).normalized()
			var correct_direction := (
				_cell_position(correct) - current_position
			).normalized()
			var wall_direction := (
				_cell_position(wall_neighbor) - current_position
			).normalized()
			result.append({
				"cell": _cell_array(cell),
				"correct_cell": _cell_array(correct),
				"wall_neighbor": _cell_array(wall_neighbor),
				"wall_neighbor_is_closer_by_cells": (
					exit_distances[cell] - exit_distances[wall_neighbor]
				),
				"correct_alignment": heard_direction.dot(correct_direction),
				"wall_alignment": heard_direction.dot(wall_direction),
			})
	return result


func _wall_shortcuts_reject_false_direction(shortcuts: Array[Dictionary]) -> bool:
	for shortcut: Dictionary in shortcuts:
		if (
			float(shortcut.get("correct_alignment", -1.0))
			<= float(shortcut.get("wall_alignment", 1.0))
		):
			return false
	return true


func _measurement(
	cell: int,
	result: Dictionary,
	graph_only_result: Dictionary,
	exit_distance: int
) -> Dictionary:
	return {
		"cell": _cell_array(cell),
		"position": _vector_array(_cell_position(cell)),
		"distance_to_exit_cells": exit_distance,
		"audible": bool(result.get("audible", false)),
		"volume_db": float(result.get("volume_db", -80.0)),
		"path_length": float(result.get("path_length", 0.0)),
		"range_path_length": float(result.get("range_path_length", 0.0)),
		"route_kind": str(result.get("route_kind", &"none")),
		"apparent_position": result.get("apparent_position", _cell_position(cell)),
		"reverb_send": float(result.get("reverb_send", 0.0)),
		"reverb_decay_seconds": float(result.get("reverb_decay_seconds", 0.0)),
		"environment_enclosure": float(result.get("environment_enclosure", 0.0)),
		"guided_gain_db": float(result.get("guided_propagation_gain_db", 0.0)),
		"lowpass_hz": float(result.get("lowpass_hz", 20000.0)),
		"route_graph_energy_weight": float(
			result.get("route_graph_energy_weight", 0.0)
		),
		"route_direct_energy_weight": float(
			result.get("route_direct_energy_weight", 0.0)
		),
		"graph_only_volume_db": float(graph_only_result.get("volume_db", -80.0)),
		"graph_only_path_length": float(graph_only_result.get("path_length", 0.0)),
		"graph_only_apparent_position": graph_only_result.get(
			"apparent_position", _cell_position(cell)
		),
	}


func _navigation_step(
	cell: int,
	measurements: Array[Dictionary],
	exit_distances: PackedInt32Array,
	volume_key: StringName,
	apparent_key: StringName
) -> Dictionary:
	return {
		"cell": _cell_array(cell),
		"distance_to_exit_cells": exit_distances[cell],
		"volume_db": float(measurements[cell].get(volume_key, -80.0)),
		"apparent_position": _vector_array(measurements[cell].get(
			apparent_key, _cell_position(cell)
		)),
	}


func _farthest_cell(start: int, adjacency: Array[Array]) -> Dictionary:
	var distances := _distances_from(start, adjacency)
	var farthest := start
	for cell: int in range(distances.size()):
		if distances[cell] > distances[farthest]:
			farthest = cell
	return {"cell": farthest, "distance": distances[farthest]}


func _distances_from(start: int, adjacency: Array[Array]) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(_cell_count())
	distances.fill(-1)
	var queue := PackedInt32Array([start])
	distances[start] = 0
	var read_index := 0
	while read_index < queue.size():
		var cell := queue[read_index]
		read_index += 1
		for neighbor_value: Variant in adjacency[cell]:
			var neighbor := int(neighbor_value)
			if distances[neighbor] >= 0:
				continue
			distances[neighbor] = distances[cell] + 1
			queue.append(neighbor)
	return distances


func _shortest_route(
	start: int,
	exit_cell: int,
	adjacency: Array[Array]
) -> Array[int]:
	var distances := _distances_from(exit_cell, adjacency)
	var route: Array[int] = [start]
	var current := start
	while current != exit_cell and route.size() <= _cell_count():
		var next_cell := -1
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if distances[neighbor] == distances[current] - 1:
				next_cell = neighbor
				break
		if next_cell < 0:
			break
		current = next_cell
		route.append(current)
	return route


func _serialized_edges(adjacency: Array[Array]) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	for cell: int in range(adjacency.size()):
		for neighbor_value: Variant in adjacency[cell]:
			var neighbor := int(neighbor_value)
			if neighbor <= cell:
				continue
			edges.append({"a": _cell_array(cell), "b": _cell_array(neighbor)})
	return edges


func _serialized_cells(cells: Array) -> Array[Array]:
	var result: Array[Array] = []
	result.resize(cells.size())
	for index: int in range(cells.size()):
		result[index] = _cell_array(int(cells[index]))
	return result


func _serialized_measurements(
	measurements: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(measurements.size())
	for index: int in range(measurements.size()):
		var measurement := measurements[index].duplicate(false)
		measurement["apparent_position"] = _vector_array(
			measurement.get("apparent_position", Vector3.ZERO)
		)
		measurement["graph_only_apparent_position"] = _vector_array(
			measurement.get("graph_only_apparent_position", Vector3.ZERO)
		)
		result[index] = measurement
	return result


func _minimum_branch_advantage(junctions: Array[Dictionary]) -> float:
	if junctions.is_empty():
		return -INF
	var result := INF
	for junction: Dictionary in junctions:
		result = minf(
			result,
			float(junction.get("correct_advantage_db", -INF))
		)
	return result


func _cell_position(cell: int) -> Vector3:
	return LAYOUT.cell_position(cell)


func _cell_coordinate(cell: int) -> Vector2i:
	return LAYOUT.cell_coordinate(cell)


func _cell_index(coordinate: Vector2i) -> int:
	return LAYOUT.cell_index(coordinate)


func _cell_array(cell: int) -> Array[int]:
	if cell < 0:
		return [-1, -1]
	var coordinate := _cell_coordinate(cell)
	return [coordinate.x, coordinate.y]


func _coordinate_is_valid(coordinate: Vector2i) -> bool:
	return LAYOUT.coordinate_is_valid(coordinate)


func _cell_count() -> int:
	return LAYOUT.cell_count()


func _save_report(report: Dictionary) -> bool:
	var directory := DirAccess.open("res://")
	if directory == null:
		return false
	directory.make_dir_recursive(REPORT_PATH.get_base_dir().trim_prefix("res://"))
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	return true


static func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] " + message)
		return
	failure_count += 1
	push_error("[FAIL] " + message)


func _finish(world: Node, service: Node) -> void:
	if is_instance_valid(service):
		service.queue_free()
	if is_instance_valid(world):
		world.queue_free()
	await process_frame
	if failure_count == 0:
		print("Acoustic maze navigation tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Acoustic maze navigation tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

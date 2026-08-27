extends SceneTree

## One persistent listener moves at a simulated 5 m/s in 25 cm server ticks: through the forest,
## beside the maze shell, around the real entrance, and down the actual generated corridor route.
## Every tick records both rendered output and the exact baked graph path that produced it.

const WORLD_SCENE := "res://scenes/server/server_world.tscn"
const RADIO_PATH := "res://resources/world/maze_exit_beacon_radio.tres"
const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const REPORT_PATH := "res://tests/generated/acoustic_maze_forest_speed_probe_report.json"
const LISTENER_ID := 6_130_000
const SOURCE_ID := 6_130_001
const LISTENER_HEIGHT := 1.7
const SAMPLE_SPACING := 0.25
const SERVER_TICK_HZ := 20.0
const MAX_NEIGHBOR_STEP_DB := 2.55
const MAX_NEIGHBOR_BAND_STEP_DB := 4.05
const FOREST_START := Vector3(94.0, LISTENER_HEIGHT, -16.0)
const WEST_CLEARANCE_X := 126.0
const SOUTH_CLEARANCE_Z := -34.5

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await physics_frame
	await process_frame
	var maze := world.get_node_or_null("AcousticMaze") as Node3D
	var radio := load(RADIO_PATH) as RadioItemDefinition
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	await physics_frame
	_expect(
		maze != null and radio != null and service.graph.probe_count() > 0,
		"speed probe uses the production maze, radio, collision bake, and propagation graph"
	)
	if maze == null or radio == null or service.graph.probe_count() <= 0:
		await _finish(world, service)
		return

	var source_body := maze.get("exit_radio") as CollisionObject3D
	var source_local := LAYOUT.exit_position()
	source_local.y = 0.05
	var source_transform := (
		source_body.global_transform
		if source_body != null
		else maze.global_transform * Transform3D(
			Basis.from_euler(Vector3(0.0, PI, 0.0)),
			source_local
		)
	)
	var source_position := radio.get_speaker_world_position(source_transform)
	var source_exclusions: Array[RID] = []
	if source_body != null:
		source_exclusions.append(source_body.get_rid())
	var source_attachment := service.create_source_attachment(
		source_position,
		source_exclusions
	)

	var path: Array[Dictionary] = []
	var west_start := Vector3(WEST_CLEARANCE_X, LISTENER_HEIGHT, FOREST_START.z)
	var southwest := Vector3(WEST_CLEARANCE_X, LISTENER_HEIGHT, SOUTH_CLEARANCE_Z)
	var entrance_outside := maze.global_transform * LAYOUT.entrance_position()
	entrance_outside.y = LISTENER_HEIGHT
	entrance_outside.z = SOUTH_CLEARANCE_Z
	var entrance_inside := maze.global_transform * LAYOUT.cell_position(LAYOUT.ENTRANCE_CELL)
	entrance_inside.y = LISTENER_HEIGHT
	_append_segment(path, FOREST_START, west_start, &"forest_approach")
	_append_segment(path, west_start, southwest, &"wall_adjacent")
	_append_segment(path, southwest, entrance_outside, &"shell_to_entrance")
	_append_segment(path, entrance_outside, entrance_inside, &"entrance_crossing")
	var adjacency := LAYOUT.adjacency()
	var maze_cells := _shortest_route(
		LAYOUT.ENTRANCE_CELL,
		LAYOUT.exit_cell(),
		adjacency,
		_distances_from(LAYOUT.exit_cell(), adjacency)
	)
	var previous_inside := entrance_inside
	for route_index: int in range(1, maze_cells.size()):
		var next_inside := maze.global_transform * LAYOUT.cell_position(maze_cells[route_index])
		next_inside.y = LISTENER_HEIGHT
		_append_segment(path, previous_inside, next_inside, &"maze_corridor")
		previous_inside = next_inside

	var measurements: Array[Dictionary] = []
	var outside_route_count := 0
	var invalid_outside_route_count := 0
	var clean_open_route_count := 0
	var open_deviation_route_count := 0
	var applied_deviation_route_count := 0
	var bent_route_count := 0
	var applied_bent_route_count := 0
	var concrete_route_count := 0
	var largest_neighbor_step_db := 0.0
	var largest_neighbor_band_step_db := 0.0
	var previous_audible_volume := INF
	var previous_audible_bands := Vector3(INF, INF, INF)
	var near_wall_measurement: Dictionary = {}
	for sample_index: int in range(path.size()):
		var waypoint := path[sample_index]
		var position: Vector3 = waypoint.get("position", Vector3.ZERO)
		var result := service.calculate_listener_result(
			LISTENER_ID,
			position,
			source_position,
			radio.maximum_hearing_distance,
			radio.source_modifier,
			AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
			false,
			source_exclusions,
			SOURCE_ID,
			0.0,
			{},
			source_attachment
		)
		var field := service._fields_by_listener.get(LISTENER_ID) as AcousticPropagationField
		var graph_result: Dictionary = {"audible": false}
		var route_debug: Dictionary = {}
		if field != null:
			graph_result = service.graph.sample_source_attached(
				field,
				source_position,
				source_attachment.probes,
				source_attachment.probe_count,
				radio.maximum_hearing_distance,
				radio.source_modifier,
				AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
				position,
				false,
				source_attachment.visibility_confirmed
			)
			var source_probe := int(graph_result.get("source_probe_index", -1))
			route_debug = service.graph.debug_route(field, source_probe)
		var direct_debug := service._sample_direct_path(
			LISTENER_ID,
			position,
			source_position,
			source_exclusions,
			SOURCE_ID
		)
		var phase := StringName(str(waypoint.get("phase", &"unknown")))
		var outside := phase in [
			&"forest_approach",
			&"wall_adjacent",
			&"shell_to_entrance",
		]
		var boundary_count := _maze_boundary_transition_count(route_debug)
		var uses_open_entrance := _uses_open_entrance(route_debug)
		var uses_concrete := _uses_modifier(route_debug, "maze_reinforced_concrete")
		var deviation_count := int(route_debug.get("deviation_count", 0))
		var expected_deviation_gain: Vector3 = route_debug.get(
			"deviation_band_gain",
			Vector3.ONE
		)
		var field_band_gain := Vector3.ONE
		if field != null:
			var source_probe := int(graph_result.get("source_probe_index", -1))
			if source_probe >= 0 and source_probe < field.band_gains.size():
				field_band_gain = field.band_gains[source_probe]
		var deviation_applied := (
			deviation_count > 0
			and field_band_gain.x <= expected_deviation_gain.x + 0.01
			and field_band_gain.y <= expected_deviation_gain.y + 0.01
			and field_band_gain.z <= expected_deviation_gain.z + 0.01
		)
		if deviation_count > 0 and not uses_concrete:
			bent_route_count += 1
			applied_bent_route_count += int(deviation_applied)
		var route_expectation_matches := true
		if outside and bool(graph_result.get("audible", false)):
			outside_route_count += 1
			route_expectation_matches = (
				boundary_count == 1
				and (
					uses_concrete
					or (
						uses_open_entrance
						and deviation_count > 0
						and expected_deviation_gain.z < expected_deviation_gain.y
						and expected_deviation_gain.y < expected_deviation_gain.x
						and deviation_applied
					)
				)
			)
			invalid_outside_route_count += int(not route_expectation_matches)
			concrete_route_count += int(uses_concrete)
			if uses_open_entrance:
				open_deviation_route_count += int(deviation_count > 0)
				applied_deviation_route_count += int(deviation_applied)
				clean_open_route_count += int(not deviation_applied)

		var audible := bool(result.get("audible", false))
		var volume_db := (
			float(result.get("volume_db", -80.0)) + radio.playback_volume_db
			if audible else -80.0
		)
		if audible and is_finite(previous_audible_volume):
			largest_neighbor_step_db = maxf(
				largest_neighbor_step_db,
				absf(volume_db - previous_audible_volume)
			)
		var heard_bands: Vector3 = result.get("band_gain", Vector3.ONE)
		if audible and previous_audible_bands.is_finite():
			largest_neighbor_band_step_db = maxf(
				largest_neighbor_band_step_db,
				_max_band_delta_db(previous_audible_bands, heard_bands)
			)
		previous_audible_volume = volume_db if audible else INF
		previous_audible_bands = heard_bands if audible else Vector3(INF, INF, INF)
		if (
			phase == &"wall_adjacent"
			and absf(position.z - source_position.z) < 0.14
		):
			near_wall_measurement = {
				"direct": direct_debug,
				"result": result,
				"position": position,
			}
		measurements.append(_serialize_measurement(
			sample_index,
			phase,
			position,
			result,
			graph_result,
			direct_debug,
			route_debug,
			boundary_count,
			uses_open_entrance,
			uses_concrete,
			deviation_applied,
			route_expectation_matches,
			field_band_gain
		))

	var near_wall_direct := near_wall_measurement.get("direct", {}) as Dictionary
	var near_wall_modifier := near_wall_direct.get("modifier") as AcousticPathModifier
	var near_wall_bands := (
		near_wall_modifier.band_gain
		if near_wall_modifier != null
		else Vector3.ONE
	)
	var report := {
		"schema_version": 1,
		"world_scene": WORLD_SCENE,
		"source_position": _vector_array(source_position),
		"sample_spacing_m": SAMPLE_SPACING,
		"simulated_server_tick_hz": SERVER_TICK_HZ,
		"simulated_speed_mps": SAMPLE_SPACING * SERVER_TICK_HZ,
		"path_cell_count": maze_cells.size(),
		"sample_count": measurements.size(),
		"outside_route_count": outside_route_count,
		"invalid_outside_route_count": invalid_outside_route_count,
		"concrete_route_count": concrete_route_count,
		"open_deviation_route_count": open_deviation_route_count,
		"applied_deviation_route_count": applied_deviation_route_count,
		"bent_route_count": bent_route_count,
		"applied_bent_route_count": applied_bent_route_count,
		"clean_open_route_count": clean_open_route_count,
		"largest_neighbor_step_db": largest_neighbor_step_db,
		"largest_neighbor_band_step_db": largest_neighbor_band_step_db,
		"near_wall_static_boundary_crossings": int(near_wall_direct.get(
			"static_boundary_crossing_count",
			0
		)),
		"near_wall_transmission_band_gain": _vector_array(near_wall_bands),
		"measurements": measurements,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) * 0.001,
	}
	_expect(_save_report(report), "moving-probe route and sound log serializes for inspection")
	_expect(measurements.size() > 900, "one persistent probe traverses a dense forest-to-source path")
	_expect(outside_route_count > 100, "the log audits a substantial outdoor approach")
	_expect(
		invalid_outside_route_count == 0,
		"every outdoor graph route crosses the maze shell once via concrete or the real entrance"
	)
	_expect(
		bent_route_count > 100
		and applied_bent_route_count == bent_route_count,
		"the generated corridor route applies frequency-dependent loss at its geometric bends"
	)
	_expect(
		clean_open_route_count == 0
		and applied_deviation_route_count == open_deviation_route_count,
		"no many-corner entrance route reaches the forest with clean outdoor EQ"
	)
	_expect(
		int(near_wall_direct.get("static_boundary_crossing_count", 0)) > 0
		and near_wall_bands.x > near_wall_bands.y
		and near_wall_bands.y > near_wall_bands.z,
		"the wall-adjacent reference keeps the expected colored concrete transmission"
	)
	_expect(
		largest_neighbor_step_db <= MAX_NEIGHBOR_STEP_DB,
		"the cure preserves the 25 cm continuous-output slew bound"
	)
	_expect(
		largest_neighbor_band_step_db <= MAX_NEIGHBOR_BAND_STEP_DB,
		"the new bend spectrum is interpolated instead of switching at route boundaries"
	)
	print(
		"Maze speed probe: %d samples, %d outside routes, %d concrete, %d/%d bent routes and %d/%d entrance routes filtered, max level/band step %.3f/%.3f dB"
		% [
			measurements.size(),
			outside_route_count,
			concrete_route_count,
			applied_bent_route_count,
			bent_route_count,
			applied_deviation_route_count,
			open_deviation_route_count,
			largest_neighbor_step_db,
			largest_neighbor_band_step_db,
		]
	)
	await _finish(world, service)


func _serialize_measurement(
	sample_index: int,
	phase: StringName,
	position: Vector3,
	result: Dictionary,
	graph_result: Dictionary,
	direct_debug: Dictionary,
	route_debug: Dictionary,
	boundary_count: int,
	uses_open_entrance: bool,
	uses_concrete: bool,
	deviation_applied: bool,
	expectation_matches: bool,
	field_band_gain: Vector3
) -> Dictionary:
	var route_positions: Array[Array] = []
	for route_position: Vector3 in route_debug.get("positions", PackedVector3Array()):
		route_positions.append(_vector_array(route_position))
	var result_bands: Vector3 = result.get("band_gain", Vector3.ONE)
	var graph_bands: Vector3 = graph_result.get("band_gain", Vector3.ONE)
	var deviation_bands: Vector3 = route_debug.get("deviation_band_gain", Vector3.ONE)
	return {
		"sample": sample_index,
		"time_seconds": float(sample_index) / SERVER_TICK_HZ,
		"phase": str(phase),
		"position": _vector_array(position),
		"expected_character": (
			"concrete_transmission"
			if uses_concrete
			else "entrance_diffraction" if uses_open_entrance else "interior_route"
		),
		"expectation_matches": expectation_matches,
		"heard": {
			"audible": bool(result.get("audible", false)),
			"volume_db": float(result.get("volume_db", -80.0)),
			"path_length_m": float(result.get("path_length", 0.0)),
			"route_kind": str(result.get("route_kind", &"silent")),
			"graph_energy_weight": float(result.get("route_graph_energy_weight", 0.0)),
			"direct_energy_weight": float(result.get("route_direct_energy_weight", 0.0)),
			"band_gain": _vector_array(result_bands),
			"lowpass_hz": float(result.get("lowpass_hz", 0.0)),
			"reverb_send": float(result.get("reverb_send", 0.0)),
			"apparent_position": _vector_array(result.get("apparent_position", position)),
		},
		"direct": {
			"blocked": bool(direct_debug.get("blocked", false)),
			"occlusion": float(direct_debug.get("occlusion", 0.0)),
			"static_boundary_crossings": int(direct_debug.get(
				"static_boundary_crossing_count",
				0
			)),
		},
		"graph": {
			"audible": bool(graph_result.get("audible", false)),
			"volume_db": float(graph_result.get("volume_db", -80.0)),
			"path_length_m": float(graph_result.get("path_length", 0.0)),
			"band_gain": _vector_array(graph_bands),
			"field_band_gain": _vector_array(field_band_gain),
			"source_probe": int(graph_result.get("source_probe_index", -1)),
			"boundary_transition_count": boundary_count,
			"uses_open_entrance": uses_open_entrance,
			"uses_concrete": uses_concrete,
			"deviation_count": int(route_debug.get("deviation_count", 0)),
			"deviation_degrees": rad_to_deg(float(route_debug.get(
				"deviation_radians",
				0.0
			))),
			"expected_deviation_band_gain": _vector_array(deviation_bands),
			"deviation_applied": deviation_applied,
			"probe_ids_source_to_listener": Array(route_debug.get(
				"probe_ids",
				PackedStringArray()
			)),
			"probe_positions_source_to_listener": route_positions,
			"edge_modifier_ids": Array(route_debug.get(
				"edge_modifier_ids",
				PackedStringArray()
			)),
		},
	}


func _append_segment(
	path: Array[Dictionary],
	from_position: Vector3,
	to_position: Vector3,
	phase: StringName
) -> void:
	var distance := from_position.distance_to(to_position)
	var steps := maxi(ceili(distance / SAMPLE_SPACING), 1)
	var first_step := 0 if path.is_empty() else 1
	for step: int in range(first_step, steps + 1):
		path.append({
			"position": from_position.lerp(to_position, float(step) / float(steps)),
			"phase": phase,
		})


func _maze_boundary_transition_count(route_debug: Dictionary) -> int:
	var ids := route_debug.get("probe_ids", PackedStringArray()) as PackedStringArray
	var result := 0
	for route_index: int in range(ids.size() - 1):
		var left := str(ids[route_index])
		var right := str(ids[route_index + 1])
		result += int(
			(_is_interior_maze_probe(left) and _is_exterior_maze_probe(right))
			or (_is_exterior_maze_probe(left) and _is_interior_maze_probe(right))
		)
	return result


func _uses_open_entrance(route_debug: Dictionary) -> bool:
	var ids := route_debug.get("probe_ids", PackedStringArray()) as PackedStringArray
	for route_index: int in range(ids.size() - 1):
		var left := str(ids[route_index])
		var right := str(ids[route_index + 1])
		if (
			(left == "maze_005" and right == "maze_exterior_entrance")
			or (right == "maze_005" and left == "maze_exterior_entrance")
		):
			return true
	return false


func _uses_modifier(route_debug: Dictionary, fragment: String) -> bool:
	for modifier_id: String in route_debug.get(
		"edge_modifier_ids",
		PackedStringArray()
	):
		if fragment in modifier_id:
			return true
	return false


func _is_interior_maze_probe(probe_id: String) -> bool:
	return probe_id.begins_with("maze_") and not probe_id.begins_with("maze_exterior_")


func _is_exterior_maze_probe(probe_id: String) -> bool:
	return probe_id.begins_with("maze_exterior_")


func _distances_from(start: int, adjacency: Array[Array]) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(LAYOUT.cell_count())
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
	adjacency: Array[Array],
	distances: PackedInt32Array
) -> Array[int]:
	var route: Array[int] = [start]
	var current := start
	while current != exit_cell and route.size() <= LAYOUT.cell_count():
		var next := -1
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if distances[neighbor] == distances[current] - 1:
				next = neighbor
				break
		if next < 0:
			break
		current = next
		route.append(current)
	return route


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _max_band_delta_db(previous: Vector3, current: Vector3) -> float:
	var result := 0.0
	for band_index: int in range(3):
		result = maxf(result, absf(
			linear_to_db(maxf(previous[band_index], AcousticPropagationGraph.MIN_GAIN))
			- linear_to_db(maxf(current[band_index], AcousticPropagationGraph.MIN_GAIN))
		))
	return result


func _save_report(report: Dictionary) -> bool:
	var directory := ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	return true


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)


func _finish(world: Node3D, service: ServerAcousticService) -> void:
	service.queue_free()
	world.queue_free()
	await process_frame
	if failure_count == 0:
		print("Maze/forest speed-probe tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Maze/forest speed-probe tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

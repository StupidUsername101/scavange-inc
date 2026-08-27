extends SceneTree

const WORLD_SCENE := "res://scenes/server/server_world.tscn"
const RADIO_PATH := "res://resources/world/maze_exit_beacon_radio.tres"
const LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const REPORT_PATH := "res://tests/generated/acoustic_maze_forest_quarter_meter_report.json"
const FIELD_PATH := "res://tests/generated/acoustic_maze_forest_quarter_meter_field.bin"
const SPACING := 0.25
const MIN_X := 94.0
const MAX_X := 184.0
const MIN_Z := -44.0
const MAX_Z := 24.0
const LISTENER_HEIGHT := 1.7
const FOREST_EDGE_X := 115.0
const CLEARING_X := 120.0
const TRACE_ROW_SPACING := 1.0
const BYTES_PER_SAMPLE := 16
const FIRST_MAZE_LISTENER_ID := 6_100_000
const FIRST_GRID_LISTENER_ID := 6_110_000
const FIRST_TRACE_LISTENER_ID := 6_120_000
const CONTINUOUS_SOURCE_ID := 6_100_001
const MIN_USABLE_MAZE_VOLUME_DB := -65.0
const MAX_FOREST_GAIN_DB := 1.5
const MAX_QUARTER_METER_STEP_DB := 2.55
# Broadband gain discrimination for speech-shaped noise has a median JND of 1.5 dB (95% CI
# 1.2..1.8 dB): https://pmc.ncbi.nlm.nih.gov/articles/PMC6351966/. The routed graph gradient and
# production apparent-direction solvers remain exact; this allowance applies only to the raw scalar
# level where a real, strongly coloured one-wall transmission path competes with the long corridor.
const MAX_IMPERCEPTIBLE_FALSE_BRANCH_GAIN_DB := 1.5

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var world := (load(WORLD_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await physics_frame
	await process_frame
	var maze := world.get_node_or_null("AcousticMaze") as Node3D
	var nature := world.get_node_or_null("WorldNature") as Node3D
	var radio := load(RADIO_PATH) as RadioItemDefinition
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	await physics_frame
	_expect(
		maze != null and nature != null and radio != null
		and service.graph.probe_count() > 0,
		"quarter-metre audit uses the active maze, forest, radio, and production graph"
	)
	if maze == null or nature == null or radio == null or service.graph.probe_count() <= 0:
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
	var maze_result := _measure_maze(
		service,
		maze,
		radio,
		source_position,
		source_attachment,
		source_exclusions
	)
	var cell_only := OS.get_environment("SCAVANGE_MAZE_FOREST_AUDIT_MODE") == "cells"
	var grid_result: Dictionary = {}
	var forest_trace: Dictionary = {}
	if not cell_only:
		grid_result = _measure_grid(
			service,
			world,
			radio,
			source_position,
			source_attachment,
			source_exclusions,
			started_msec
		)
		forest_trace = _trace_forest(
			service,
			world,
			radio,
			source_position,
			source_attachment,
			source_exclusions
		)

	var report := {
		"schema_version": 1,
		"world_scene": WORLD_SCENE,
		"spacing_m": SPACING,
		"source_position": _vector_array(source_position),
		"maze": maze_result,
		"grid": grid_result,
		"forest_trace": forest_trace,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) * 0.001,
	}
	_expect(_save_report(report), "combined maze/forest field serializes its diagnostics")
	_expect(
		int(maze_result.get("audible_cell_count", 0)) == LAYOUT.cell_count(),
		"the production beacon remains audible in every maze cell"
	)
	_expect(
		float(maze_result.get("minimum_route_volume_db", -80.0))
		>= MIN_USABLE_MAZE_VOLUME_DB,
		"the correct maze route never falls below a practically usable level"
	)
	_expect(
		bool((maze_result.get("graph_volume_navigation", {}) as Dictionary).get(
			"reached_exit", false
		)),
		"the baked pressure gradient leads through the real corridor without an exterior shortcut"
	)
	_expect(
		bool((maze_result.get("direction_navigation", {}) as Dictionary).get(
			"reached_exit", false
		)),
		"production apparent direction leads through the real corridor instead of exterior walls"
	)
	_expect(
		float(maze_result.get("minimum_junction_advantage_db", -INF))
		>= -MAX_IMPERCEPTIBLE_FALSE_BRANCH_GAIN_DB,
		"wall transmission never makes a false production branch perceptibly louder than the routed branch"
	)
	if not cell_only:
		_expect(
			int(grid_result.get("sample_count", 0)) >= 95_000,
			"the 25 cm field covers the full maze shell and surrounding forest"
		)
		_expect(
			float(forest_trace.get("largest_forest_gain_db", INF))
			<= MAX_FOREST_GAIN_DB,
			"the connected forest cannot regain the old farther-away loudness hotspot"
		)
		_expect(
			float(forest_trace.get("largest_neighbor_step_db", INF))
			<= MAX_QUARTER_METER_STEP_DB,
			"quarter-metre forest movement remains continuously dezippered"
		)
	print(
		"Maze/forest 25 cm: cells %d/%d, min %.2f dB, baked gradient=%s, rendered direction=%s, forest gain %.3f dB"
		% [
			int(maze_result.get("audible_cell_count", 0)),
			LAYOUT.cell_count(),
			float(maze_result.get("minimum_route_volume_db", -80.0)),
			str((maze_result.get("graph_volume_navigation", {}) as Dictionary).get("reached_exit", false)),
			str((maze_result.get("direction_navigation", {}) as Dictionary).get("reached_exit", false)),
			float(forest_trace.get("largest_forest_gain_db", 0.0)),
		]
	)
	await _finish(world, service)


func _measure_maze(
	service: ServerAcousticService,
	maze: Node3D,
	radio: RadioItemDefinition,
	source_position: Vector3,
	source_attachment: AcousticSourceAttachment,
	source_exclusions: Array[RID]
) -> Dictionary:
	var adjacency := LAYOUT.adjacency()
	var exit_cell := LAYOUT.exit_cell()
	var start_cell := LAYOUT.ENTRANCE_CELL
	var distances := _distances_from(exit_cell, adjacency)
	var route := _shortest_route(start_cell, exit_cell, adjacency, distances)
	var measurements: Array[Dictionary] = []
	measurements.resize(LAYOUT.cell_count())
	var audible_count := 0
	for cell: int in range(LAYOUT.cell_count()):
		var position := maze.global_transform * LAYOUT.cell_position(cell)
		var result := service.calculate_listener_result(
			FIRST_MAZE_LISTENER_ID + cell,
			position,
			source_position,
			radio.maximum_hearing_distance,
			radio.source_modifier,
			AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
			false,
			source_exclusions,
			0,
			0.0,
			{},
			source_attachment
		)
		var listener_field := service._fields_by_listener.get(
			FIRST_MAZE_LISTENER_ID + cell
		) as AcousticPropagationField
		var graph_result := service.graph.sample_source_attached(
			listener_field,
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
		service.graph.apply_environment_to_result(
			graph_result,
			position,
			source_position,
			listener_field,
			int(graph_result.get("source_probe_index", -1))
		)
		var direct_path := service._sample_direct_path(
			FIRST_MAZE_LISTENER_ID + cell,
			position,
			source_position,
			source_exclusions,
			0
		)
		var direct_modifier := direct_path.get("modifier") as AcousticPathModifier
		var audible := bool(result.get("audible", false))
		audible_count += int(audible)
		measurements[cell] = {
			"cell": _cell_array(cell),
			"position": position,
			"audible": audible,
			"volume_db": (
				float(result.get("volume_db", -80.0)) + radio.playback_volume_db
				if audible else -80.0
			),
			"apparent_position": result.get("apparent_position", position),
			"route": str(result.get("route_kind", &"silent")),
			"graph_weight": float(result.get("route_graph_energy_weight", 0.0)),
			"path_length": float(result.get("path_length", 0.0)),
			"reverb_send": float(result.get("reverb_send", 0.0)),
			"band_gain": result.get("band_gain", Vector3.ONE),
			"lowpass_hz": float(result.get("lowpass_hz", 20000.0)),
			"direct_static_boundary_crossing_count": int(direct_path.get(
				"static_boundary_crossing_count",
				0
			)),
			"direct_modifier_volume_db": (
				direct_modifier.volume_db if direct_modifier != null else 0.0
			),
			"direct_modifier_band_gain": (
				direct_modifier.band_gain if direct_modifier != null else Vector3.ONE
			),
			"graph_only_volume_db": (
				float(graph_result.get("volume_db", -80.0)) + radio.playback_volume_db
			),
			"graph_only_path_length": float(graph_result.get("path_length", 0.0)),
			"graph_only_guided_path_length": float(
				graph_result.get("guided_path_length", 0.0)
			),
			"graph_only_guided_gain_db": float(
				graph_result.get("guided_propagation_gain_db", 0.0)
			),
			"graph_only_environment_enclosure": float(
				graph_result.get("environment_enclosure", 0.0)
			),
			"graph_only_modifier_ids": Array(
				graph_result.get("modifier_ids", PackedStringArray())
			),
			"graph_only_field_volume_db": (
				listener_field.volume_db[int(graph_result.get("source_probe_index", -1))]
				if int(graph_result.get("source_probe_index", -1)) >= 0
				else -80.0
			),
			"graph_only_apparent_position": graph_result.get(
				"apparent_position",
				position
			),
			"listener_probe": int(result.get("listener_origin_probe_index", -1)),
			"source_probe": int(result.get("source_probe_index", -1)),
		}
	var volume_navigation := _navigate_by_volume(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		distances
	)
	var direction_navigation := _navigate_by_direction(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		distances
	)
	var graph_volume_navigation := _navigate_by_volume(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		distances,
		&"graph_only_volume_db"
	)
	var graph_direction_navigation := _navigate_by_direction(
		start_cell,
		exit_cell,
		adjacency,
		measurements,
		distances,
		&"graph_only_apparent_position",
		&"graph_only_volume_db"
	)
	var junctions := _junctions(route, adjacency, measurements)
	var minimum_route_volume := INF
	for cell: int in route:
		minimum_route_volume = minf(
			minimum_route_volume,
			float(measurements[cell].get("volume_db", -80.0))
		)
	var serialized_measurements: Array[Dictionary] = []
	for measurement: Dictionary in measurements:
		var serialized := measurement.duplicate(false)
		serialized["position"] = _vector_array(measurement.get("position", Vector3.ZERO))
		serialized["apparent_position"] = _vector_array(
			measurement.get("apparent_position", Vector3.ZERO)
		)
		serialized["graph_only_apparent_position"] = _vector_array(
			measurement.get("graph_only_apparent_position", Vector3.ZERO)
		)
		serialized["band_gain"] = _vector_array(
			measurement.get("band_gain", Vector3.ONE)
		)
		serialized["direct_modifier_band_gain"] = _vector_array(
			measurement.get("direct_modifier_band_gain", Vector3.ONE)
		)
		var listener_probe := int(measurement.get("listener_probe", -1))
		serialized["listener_probe_id"] = str(service.graph.get_probe_id(listener_probe))
		serialized["listener_probe_allows_attachment"] = service.graph.probe_allows_attachment(
			listener_probe,
			measurement.get("position", Vector3.ZERO)
		)
		serialized_measurements.append(serialized)
	return {
		"seed": LAYOUT.SEED,
		"start_cell": _cell_array(start_cell),
		"exit_cell": _cell_array(exit_cell),
		"route": _serialized_cells(route),
		"route_cell_count": route.size(),
		"audible_cell_count": audible_count,
		"minimum_route_volume_db": minimum_route_volume,
		"minimum_junction_advantage_db": _minimum_junction_advantage(junctions),
		"junctions": junctions,
		"volume_navigation": volume_navigation,
		"direction_navigation": direction_navigation,
		"graph_volume_navigation": graph_volume_navigation,
		"graph_direction_navigation": graph_direction_navigation,
		"measurements": serialized_measurements,
	}


func _measure_grid(
	service: ServerAcousticService,
	world: Node3D,
	radio: RadioItemDefinition,
	source_position: Vector3,
	source_attachment: AcousticSourceAttachment,
	source_exclusions: Array[RID],
	started_msec: int
) -> Dictionary:
	var x_count := roundi((MAX_X - MIN_X) / SPACING) + 1
	var z_count := roundi((MAX_Z - MIN_Z) / SPACING) + 1
	var sample_count := x_count * z_count
	var file := FileAccess.open(FIELD_PATH, FileAccess.WRITE)
	if file == null:
		return {}
	var row := PackedByteArray()
	row.resize(z_count * BYTES_PER_SAMPLE)
	var space_state := world.get_world_3d().direct_space_state
	var point_query := PhysicsPointQueryParameters3D.new()
	point_query.collide_with_areas = false
	point_query.collide_with_bodies = true
	var occupied_count := 0
	var audible_count := 0
	for x_index: int in range(x_count):
		var x := MIN_X + float(x_index) * SPACING
		for z_index: int in range(z_count):
			var position := Vector3(
				x,
				LISTENER_HEIGHT,
				MIN_Z + float(z_index) * SPACING
			)
			var occupied := _occupied(space_state, point_query, position)
			var sample := _sample(
				service,
				FIRST_GRID_LISTENER_ID + x_index,
				position,
				radio,
				source_position,
				source_attachment,
				source_exclusions,
				occupied
			)
			occupied_count += int(occupied)
			audible_count += int(not occupied and bool(sample.get("audible", false)))
			_store_sample(row, z_index * BYTES_PER_SAMPLE, sample)
		file.store_buffer(row)
		if x_index % 40 == 0 or x_index == x_count - 1:
			print(
				"Maze/forest 25 cm field: %d/%d columns, %d/%d samples, %.1f s"
				% [
					x_index + 1,
					x_count,
					(x_index + 1) * z_count,
					sample_count,
					float(Time.get_ticks_msec() - started_msec) * 0.001,
				]
			)
	file.close()
	return {
		"path": FIELD_PATH,
		"bytes_per_sample": BYTES_PER_SAMPLE,
		"sample_order": "x-major; z changes fastest",
		"min_x": MIN_X,
		"max_x": MAX_X,
		"min_z": MIN_Z,
		"max_z": MAX_Z,
		"x_count": x_count,
		"z_count": z_count,
		"sample_count": sample_count,
		"occupied_count": occupied_count,
		"audible_count": audible_count,
	}


func _trace_forest(
	service: ServerAcousticService,
	world: Node3D,
	radio: RadioItemDefinition,
	source_position: Vector3,
	source_attachment: AcousticSourceAttachment,
	source_exclusions: Array[RID]
) -> Dictionary:
	var row_count := roundi((8.0 - -42.0) / TRACE_ROW_SPACING) + 1
	var x_count := roundi((127.5 - MIN_X) / SPACING) + 1
	var largest_gain := -INF
	var largest_step := 0.0
	var rows_over_limit := 0
	var worst: Dictionary = {}
	var space_state := world.get_world_3d().direct_space_state
	var point_query := PhysicsPointQueryParameters3D.new()
	point_query.collide_with_areas = false
	point_query.collide_with_bodies = true
	for row_index: int in range(row_count):
		var z := -42.0 + float(row_index) * TRACE_ROW_SPACING
		var clearing: Dictionary = {}
		var forest_peak: Dictionary = {}
		var previous: Dictionary = {}
		for step: int in range(x_count):
			var x := 127.5 - float(step) * SPACING
			var position := Vector3(x, LISTENER_HEIGHT, z)
			var occupied := _occupied(space_state, point_query, position)
			var sample := _sample(
				service,
				FIRST_TRACE_LISTENER_ID + row_index,
				position,
				radio,
				source_position,
				source_attachment,
				source_exclusions,
				occupied
			)
			if not previous.is_empty() and not occupied and not bool(previous.get("occupied", true)):
				largest_step = maxf(
					largest_step,
					absf(float(sample.get("volume_db", -80.0)) - float(previous.get("volume_db", -80.0)))
				)
			previous = sample
			if occupied or not bool(sample.get("audible", false)):
				continue
			if x <= CLEARING_X and clearing.is_empty():
				clearing = sample
			if x <= FOREST_EDGE_X and (
				forest_peak.is_empty()
				or float(sample.get("volume_db", -80.0)) > float(forest_peak.get("volume_db", -80.0))
			):
				forest_peak = sample
		if clearing.is_empty() or forest_peak.is_empty():
			continue
		var gain := float(forest_peak.get("volume_db", -80.0)) - float(clearing.get("volume_db", -80.0))
		rows_over_limit += int(gain > MAX_FOREST_GAIN_DB)
		if gain > largest_gain:
			largest_gain = gain
			worst = {
				"z": z,
				"gain_db": gain,
				"clearing": _report_sample(clearing),
				"forest": _report_sample(forest_peak),
			}
	return {
		"row_count": row_count,
		"spacing_m": SPACING,
		"largest_forest_gain_db": maxf(largest_gain, 0.0),
		"largest_neighbor_step_db": largest_step,
		"rows_over_limit": rows_over_limit,
		"worst": worst,
	}


func _sample(
	service: ServerAcousticService,
	listener_id: int,
	position: Vector3,
	radio: RadioItemDefinition,
	source_position: Vector3,
	source_attachment: AcousticSourceAttachment,
	source_exclusions: Array[RID],
	occupied: bool
) -> Dictionary:
	if occupied:
		return {"occupied": true, "audible": false, "volume_db": -80.0}
	var result := service.calculate_listener_result(
		listener_id,
		position,
		source_position,
		radio.maximum_hearing_distance,
		radio.source_modifier,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		false,
		source_exclusions,
		CONTINUOUS_SOURCE_ID,
		0.0,
		{},
		source_attachment
	)
	var audible := bool(result.get("audible", false))
	return {
		"occupied": false,
		"audible": audible,
		"volume_db": float(result.get("volume_db", -80.0)) + radio.playback_volume_db if audible else -80.0,
		"path_length": float(result.get("path_length", 0.0)),
		"source_distance": position.distance_to(source_position),
		"listener_probe": int(result.get("listener_origin_probe_index", -1)),
		"source_probe": int(result.get("source_probe_index", -1)),
		"direct_occlusion": float(result.get("direct_occlusion", 0.0)),
		"graph_weight": float(result.get("route_graph_energy_weight", 0.0)),
		"reverb_send": float(result.get("reverb_send", 0.0)),
		"route": str(result.get("route_kind", &"silent")),
	}


func _navigate_by_volume(
	start: int,
	exit_cell: int,
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	distances: PackedInt32Array,
	volume_key: StringName = &"volume_db"
) -> Dictionary:
	var current := start
	var previous := -1
	var trace: Array[Array] = []
	for _step: int in range(LAYOUT.cell_count()):
		trace.append(_cell_array(current))
		if current == exit_cell:
			return {"reached_exit": true, "trace": trace}
		var chosen := -1
		var loudest := -INF
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if neighbor == previous:
				continue
			var volume := float(measurements[neighbor].get(volume_key, -80.0))
			if volume > loudest:
				loudest = volume
				chosen = neighbor
		if chosen < 0 or distances[chosen] != distances[current] - 1:
			return {
				"reached_exit": false,
				"trace": trace,
				"failure_cell": _cell_array(current),
				"chosen_cell": _cell_array(chosen),
			}
		previous = current
		current = chosen
	return {"reached_exit": false, "trace": trace}


func _navigate_by_direction(
	start: int,
	exit_cell: int,
	adjacency: Array[Array],
	measurements: Array[Dictionary],
	distances: PackedInt32Array,
	apparent_position_key: StringName = &"apparent_position",
	volume_key: StringName = &"volume_db"
) -> Dictionary:
	var current := start
	var previous := -1
	var trace: Array[Array] = []
	for _step: int in range(LAYOUT.cell_count()):
		trace.append(_cell_array(current))
		if current == exit_cell:
			return {"reached_exit": true, "trace": trace}
		var current_position: Vector3 = measurements[current].get("position", Vector3.ZERO)
		var apparent: Vector3 = measurements[current].get(
			apparent_position_key,
			current_position
		)
		var heard := (apparent - current_position).normalized()
		var chosen := -1
		var best_alignment := -INF
		var chosen_volume := -INF
		for neighbor_value: Variant in adjacency[current]:
			var neighbor := int(neighbor_value)
			if neighbor == previous:
				continue
			var neighbor_position: Vector3 = measurements[neighbor].get("position", current_position)
			var alignment := heard.dot((neighbor_position - current_position).normalized())
			var volume := float(measurements[neighbor].get(volume_key, -80.0))
			if (
				alignment > best_alignment + 0.05
				or (
					absf(alignment - best_alignment) <= 0.05
					and volume > chosen_volume
				)
			):
				best_alignment = alignment
				chosen_volume = volume
				chosen = neighbor
		if chosen < 0 or distances[chosen] != distances[current] - 1:
			return {
				"reached_exit": false,
				"trace": trace,
				"failure_cell": _cell_array(current),
				"chosen_cell": _cell_array(chosen),
				"alignment": best_alignment,
				"apparent_position": _vector_array(apparent),
			}
		previous = current
		current = chosen
	return {"reached_exit": false, "trace": trace}


func _junctions(
	route: Array[int],
	adjacency: Array[Array],
	measurements: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for route_index: int in range(route.size() - 1):
		var cell := route[route_index]
		var previous := route[route_index - 1] if route_index > 0 else -1
		var correct := route[route_index + 1]
		var loudest_wrong := -INF
		var wrong_cell := -1
		for neighbor_value: Variant in adjacency[cell]:
			var neighbor := int(neighbor_value)
			if neighbor == previous or neighbor == correct:
				continue
			var volume := float(measurements[neighbor].get("volume_db", -80.0))
			if volume > loudest_wrong:
				loudest_wrong = volume
				wrong_cell = neighbor
		if wrong_cell < 0:
			continue
		var correct_volume := float(measurements[correct].get("volume_db", -80.0))
		result.append({
			"cell": _cell_array(cell),
			"correct": _cell_array(correct),
			"wrong": _cell_array(wrong_cell),
			"correct_volume_db": correct_volume,
			"wrong_volume_db": loudest_wrong,
			"advantage_db": correct_volume - loudest_wrong,
		})
	return result


func _minimum_junction_advantage(junctions: Array[Dictionary]) -> float:
	if junctions.is_empty():
		return -INF
	var result := INF
	for junction: Dictionary in junctions:
		result = minf(result, float(junction.get("advantage_db", -INF)))
	return result


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


func _occupied(
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsPointQueryParameters3D,
	position: Vector3
) -> bool:
	query.position = position
	return not space_state.intersect_point(query, 1).is_empty()


func _store_sample(bytes: PackedByteArray, offset: int, sample: Dictionary) -> void:
	bytes.encode_s16(offset, clampi(roundi(float(sample.get("volume_db", -80.0)) * 100.0), -8000, 32767))
	bytes.encode_u16(offset + 2, clampi(roundi(float(sample.get("path_length", 0.0)) * 100.0), 0, 65535))
	bytes.encode_u16(offset + 4, clampi(roundi(float(sample.get("source_distance", 0.0)) * 100.0), 0, 65535))
	bytes.encode_u16(offset + 6, clampi(int(sample.get("listener_probe", -1)) + 1, 0, 65535))
	bytes.encode_u16(offset + 8, clampi(int(sample.get("source_probe", -1)) + 1, 0, 65535))
	bytes[offset + 10] = roundi(clampf(float(sample.get("direct_occlusion", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 11] = roundi(clampf(float(sample.get("graph_weight", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 12] = roundi(clampf(float(sample.get("reverb_send", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 13] = (
		int(bool(sample.get("audible", false)))
		| (int(bool(sample.get("occupied", false))) << 1)
		| (_route_code(str(sample.get("route", "silent"))) << 2)
	)
	bytes[offset + 14] = 0
	bytes[offset + 15] = 0


func _route_code(route: String) -> int:
	match route:
		"direct": return 1
		"transmitted": return 2
		"graph": return 3
		"parallel": return 4
	return 0


func _report_sample(sample: Dictionary) -> Dictionary:
	return {
		"volume_db": sample.get("volume_db", -80.0),
		"path_length": sample.get("path_length", 0.0),
		"source_distance": sample.get("source_distance", 0.0),
		"listener_probe": sample.get("listener_probe", -1),
		"source_probe": sample.get("source_probe", -1),
		"direct_occlusion": sample.get("direct_occlusion", 0.0),
		"graph_weight": sample.get("graph_weight", 0.0),
		"reverb_send": sample.get("reverb_send", 0.0),
		"route": sample.get("route", "silent"),
	}


func _serialized_cells(cells: Array) -> Array[Array]:
	var result: Array[Array] = []
	for cell_value: Variant in cells:
		result.append(_cell_array(int(cell_value)))
	return result


func _cell_array(cell: int) -> Array[int]:
	if cell < 0:
		return [-1, -1]
	var coordinate := LAYOUT.cell_coordinate(cell)
	return [coordinate.x, coordinate.y]


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


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
		print("Maze/forest quarter-metre tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Maze/forest quarter-metre tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

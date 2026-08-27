extends SceneTree

const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const RADIO_DEFINITION_PATH := "res://resources/world/maze_exit_beacon_radio.tres"
const MAZE_LAYOUT := preload("res://scripts/world/acoustic_maze_layout.gd")
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")

const REPORT_PATH := "res://tests/generated/forest_maze_dense_probe_report.json"
const FIELD_PATH := "res://tests/generated/forest_maze_dense_probe_field.bin"
const LISTENER_HEIGHT := 1.7
const GRID_SPACING := 0.1
const REGION_MIN_X := 94.0
const REGION_MAX_X := 127.5
const REGION_MIN_Z := -42.0
const REGION_MAX_Z := 8.0
const OUTWARD_TRACE_Z_SPACING := 0.5
const FOREST_EDGE_X := NATURE_LAYOUT.FOREST_MAX.x
const CLEARING_REFERENCE_X := 120.0
const BYTES_PER_SAMPLE := 20
const GRID_FIRST_LISTENER_ID := 4_820_000
const TRACE_FIRST_LISTENER_ID := 4_840_000
const CONTINUOUS_SOURCE_ID := 4_810_001
const MAX_REPORTED_ANOMALIES := 192
const REPORT_STEP_THRESHOLD_DB := 0.2
const HARD_NEIGHBOR_STEP_DB := 1.05
const MATERIAL_FARTHER_RISE_DB := 1.5

var failure_count := 0
var assertion_count := 0
var largest_steps: Array[Dictionary] = []
var largest_farther_rises: Array[Dictionary] = []
var largest_probe_switches: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var world := (
		(load(SERVER_WORLD_PATH) as PackedScene).instantiate() as Node3D
	)
	root.add_child(world)
	await physics_frame
	await process_frame

	var maze := world.get_node_or_null("AcousticMaze") as Node3D
	var nature := world.get_node_or_null("WorldNature") as Node3D
	var radio := load(RADIO_DEFINITION_PATH) as RadioItemDefinition
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	await physics_frame
	_expect(
		maze != null
		and nature != null
		and radio != null
		and service.graph.probe_count() > 0,
		"forest audit uses the active world, maze beacon, nature collision, and baked graph"
	)
	if maze == null or nature == null or radio == null or service.graph.probe_count() <= 0:
		await _finish(world, service)
		return

	var exit_local := MAZE_LAYOUT.exit_position()
	exit_local.y = 0.05
	var radio_transform := Transform3D(
		Basis.from_euler(Vector3(0.0, PI, 0.0)),
		maze.global_transform * exit_local
	)
	var source_position := radio.get_speaker_world_position(radio_transform)
	var entrance_position := maze.global_transform * MAZE_LAYOUT.entrance_position()
	entrance_position.y = LISTENER_HEIGHT
	var source_attachment := service.create_source_attachment(source_position)
	var x_count := roundi((REGION_MAX_X - REGION_MIN_X) / GRID_SPACING) + 1
	var z_count := roundi((REGION_MAX_Z - REGION_MIN_Z) / GRID_SPACING) + 1
	var sample_count := x_count * z_count
	var field_file := FileAccess.open(FIELD_PATH, FileAccess.WRITE)
	_expect(field_file != null, "forest audit opens its compact binary field")
	if field_file == null:
		await _finish(world, service)
		return

	var row_bytes := PackedByteArray()
	row_bytes.resize(z_count * BYTES_PER_SAMPLE)
	var previous_row: Array[Dictionary] = []
	previous_row.resize(z_count)
	var space_state := world.get_world_3d().direct_space_state
	var point_query := PhysicsPointQueryParameters3D.new()
	point_query.collide_with_areas = false
	point_query.collide_with_bodies = true
	var valid_count := 0
	var audible_count := 0
	var occupied_count := 0
	var largest_grid_step_db := 0.0
	var largest_grid_farther_rise_db := 0.0
	var largest_grid_probe_switch_db := 0.0

	for x_index: int in range(x_count):
		var x := REGION_MIN_X + float(x_index) * GRID_SPACING
		var listener_id := GRID_FIRST_LISTENER_ID + x_index
		var previous_sample: Dictionary = {}
		for z_index: int in range(z_count):
			var z := REGION_MIN_Z + float(z_index) * GRID_SPACING
			var position := Vector3(x, LISTENER_HEIGHT, z)
			var occupied := _point_is_occupied(space_state, point_query, position)
			var sample := _sample(
				service,
				listener_id,
				position,
				source_position,
				entrance_position,
				radio,
				source_attachment,
				occupied
			)
			if occupied:
				occupied_count += 1
			else:
				valid_count += 1
				audible_count += int(sample.get("audible", false))
			_store_sample(row_bytes, z_index * BYTES_PER_SAMPLE, sample)
			if not previous_sample.is_empty():
				var along := _analyze_pair(previous_sample, sample, &"z_walk")
				largest_grid_step_db = maxf(
					largest_grid_step_db,
					float(along.get("step_db", 0.0))
				)
				largest_grid_farther_rise_db = maxf(
					largest_grid_farther_rise_db,
					float(along.get("farther_rise_db", 0.0))
				)
				largest_grid_probe_switch_db = maxf(
					largest_grid_probe_switch_db,
					float(along.get("probe_switch_step_db", 0.0))
				)
			var previous_cross: Dictionary = previous_row[z_index]
			if not previous_cross.is_empty():
				_analyze_pair(previous_cross, sample, &"x_static")
			previous_sample = sample
			previous_row[z_index] = sample
		field_file.store_buffer(row_bytes)
		if x_index % 40 == 0 or x_index == x_count - 1:
			print(
				"Forest 10 cm audit: %d/%d columns, %d/%d samples, %.1f s"
				% [
					x_index + 1,
					x_count,
					(x_index + 1) * z_count,
					sample_count,
					float(Time.get_ticks_msec() - started_msec) / 1000.0,
				]
			)
	field_file.close()

	var outward_trace := _trace_horizontal_motion(
		service,
		space_state,
		point_query,
		source_position,
		entrance_position,
		radio,
		source_attachment
	)
	_sort_anomalies(largest_steps, &"step_db")
	_sort_anomalies(largest_farther_rises, &"farther_rise_db")
	_sort_anomalies(largest_probe_switches, &"probe_switch_step_db")
	var report := {
		"schema_version": 1,
		"world_scene": SERVER_WORLD_PATH,
		"source": {
			"definition": RADIO_DEFINITION_PATH,
			"position": _vector_array(source_position),
			"maze_exit_cell": MAZE_LAYOUT.exit_cell(),
			"maximum_distance": radio.maximum_hearing_distance,
			"playback_volume_db": radio.playback_volume_db,
		},
		"maze_entrance_position": _vector_array(entrance_position),
		"grid": {
			"spacing_m": GRID_SPACING,
			"min_x": REGION_MIN_X,
			"max_x": REGION_MAX_X,
			"min_z": REGION_MIN_Z,
			"max_z": REGION_MAX_Z,
			"listener_y": LISTENER_HEIGHT,
			"x_count": x_count,
			"z_count": z_count,
			"sample_order": "x-major; z changes fastest",
			"forest_edge_x": FOREST_EDGE_X,
		},
		"binary_field": {
			"path": FIELD_PATH,
			"bytes_per_sample": BYTES_PER_SAMPLE,
			"fields": [
				"volume_centidb:int16",
				"source_distance_cm:uint16",
				"entrance_distance_cm:uint16",
				"path_length_cm:uint16",
				"listener_probe_plus_one:uint16",
				"source_probe_plus_one:uint16",
				"diffuse_gain_centidb:int16",
				"guided_gain_centidb:uint16",
				"reverb_0_to_255:uint8",
				"enclosure_0_to_255:uint8",
				"occlusion_0_to_255:uint8",
				"flags:uint8 (audible, occupied, route<<2)",
			],
		},
		"summary": {
			"sample_count": sample_count,
			"valid_count": valid_count,
			"occupied_count": occupied_count,
			"audible_count": audible_count,
			"largest_grid_step_db": largest_grid_step_db,
			"largest_grid_farther_rise_db": largest_grid_farther_rise_db,
			"largest_grid_probe_switch_db": largest_grid_probe_switch_db,
			"elapsed_seconds": (
				float(Time.get_ticks_msec() - started_msec) / 1000.0
			),
		},
		"horizontal_motion": outward_trace,
		"largest_steps": largest_steps,
		"largest_farther_rises": largest_farther_rises,
		"largest_probe_switches": largest_probe_switches,
	}
	_expect(_save_report(report), "forest audit serializes its field diagnosis")
	_expect(
		sample_count >= 160_000 and is_equal_approx(GRID_SPACING, 0.1),
		"more than 160,000 ten-centimetre listeners cover the forest west of the maze"
	)
	_expect(
		float(outward_trace.get("largest_neighbor_step_db", INF))
		<= HARD_NEIGHBOR_STEP_DB,
		"a walking listener cannot receive a hard ten-centimetre output step"
	)
	_expect(
		float(outward_trace.get("largest_forest_gain_over_clearing_db", INF))
		<= MATERIAL_FARTHER_RISE_DB,
		"moving farther into the forest cannot become materially louder than the nearer maze clearing"
	)
	print(
		"Forest/maze report: %s (%d samples, step %.3f dB, forest gain %.3f dB)"
		% [
			ProjectSettings.globalize_path(REPORT_PATH),
			sample_count,
			float(outward_trace.get("largest_neighbor_step_db", 0.0)),
			float(outward_trace.get("largest_forest_gain_over_clearing_db", 0.0)),
		]
	)
	await _finish(world, service)


func _sample(
	service: ServerAcousticService,
	listener_id: int,
	position: Vector3,
	source_position: Vector3,
	entrance_position: Vector3,
	radio: RadioItemDefinition,
	source_attachment: AcousticSourceAttachment,
	occupied: bool
) -> Dictionary:
	var sample := {
		"position": position,
		"occupied": occupied,
		"audible": false,
		"volume_db": AcousticPathModifier.MIN_VOLUME_DB,
		"source_distance": position.distance_to(source_position),
		"entrance_distance": position.distance_to(entrance_position),
		"route_code": 0,
		"route_kind": &"occupied" if occupied else &"silent",
		"listener_probe": -1,
		"source_probe": -1,
	}
	if occupied:
		return sample
	var result := service.calculate_listener_result(
		listener_id,
		position,
		source_position,
		radio.maximum_hearing_distance,
		radio.source_modifier,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		false,
		[],
		CONTINUOUS_SOURCE_ID,
		0.0,
		{},
		source_attachment
	)
	var audible := bool(result.get("audible", false))
	var direct_path := service._sample_direct_path(
		listener_id,
		position,
		source_position,
		[],
		CONTINUOUS_SOURCE_ID
	)
	var route_kind := StringName(str(result.get("route_kind", &"silent")))
	sample.merge({
		"audible": audible,
		"volume_db": (
			float(result.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
			+ radio.playback_volume_db
			if audible
			else AcousticPathModifier.MIN_VOLUME_DB
		),
		"route_code": _route_code(route_kind),
		"route_kind": route_kind,
		"listener_probe": int(result.get("listener_origin_probe_index", -1)),
		"source_probe": int(result.get("source_probe_index", -1)),
		"path_length": float(result.get("path_length", 0.0)),
		"diffuse_gain_db": float(result.get("diffuse_field_gain_db", 0.0)),
		"guided_gain_db": float(result.get("guided_propagation_gain_db", 0.0)),
		"reverb_send": float(result.get("reverb_send", 0.0)),
		"environment_enclosure": float(result.get("environment_enclosure", 0.0)),
		"direct_occlusion": float(direct_path.get("occlusion", 0.0)),
		"static_crossings": int(direct_path.get("static_boundary_crossing_count", 0)),
		"graph_weight": float(result.get("route_graph_energy_weight", 0.0)),
		"direct_weight": float(result.get("route_direct_energy_weight", 1.0)),
		"parallel_gain_db": float(result.get("parallel_route_gain_db", 0.0)),
	}, true)
	return sample


func _trace_horizontal_motion(
	service: ServerAcousticService,
	space_state: PhysicsDirectSpaceState3D,
	point_query: PhysicsPointQueryParameters3D,
	source_position: Vector3,
	entrance_position: Vector3,
	radio: RadioItemDefinition,
	source_attachment: AcousticSourceAttachment
) -> Dictionary:
	var z_count := roundi(
		(REGION_MAX_Z - REGION_MIN_Z) / OUTWARD_TRACE_Z_SPACING
	) + 1
	var x_count := roundi((REGION_MAX_X - REGION_MIN_X) / GRID_SPACING) + 1
	var sample_count := 0
	var largest_neighbor_step_db := 0.0
	var largest_farther_rise_db := 0.0
	var largest_forest_gain_over_clearing_db := -INF
	var rows_with_forest_gain := 0
	var worst_forest_gain: Dictionary = {}
	for z_index: int in range(z_count):
		var z := REGION_MIN_Z + float(z_index) * OUTWARD_TRACE_Z_SPACING
		var clearing_reference: Dictionary = {}
		var forest_peak: Dictionary = {}
		var quietest_outward: Dictionary = {}
		var previous: Dictionary = {}
		for direction_index: int in range(2):
			var east_to_west := direction_index == 0
			var listener_id := (
				TRACE_FIRST_LISTENER_ID + z_index * 2 + direction_index
			)
			previous = {}
			for step_index: int in range(x_count):
				var x_index := step_index if not east_to_west else x_count - 1 - step_index
				var x := REGION_MIN_X + float(x_index) * GRID_SPACING
				var position := Vector3(x, LISTENER_HEIGHT, z)
				var occupied := _point_is_occupied(
					space_state,
					point_query,
					position
				)
				var sample := _sample(
					service,
					listener_id,
					position,
					source_position,
					entrance_position,
					radio,
					source_attachment,
					occupied
				)
				sample_count += 1
				if not previous.is_empty():
					var pair := _analyze_pair(
						previous,
						sample,
						&"x_outward" if east_to_west else &"x_inward"
					)
					largest_neighbor_step_db = maxf(
						largest_neighbor_step_db,
						float(pair.get("step_db", 0.0))
					)
					largest_farther_rise_db = maxf(
						largest_farther_rise_db,
						float(pair.get("farther_rise_db", 0.0))
					)
				previous = sample
				if not east_to_west or occupied or not bool(sample.get("audible", false)):
					continue
				if x <= CLEARING_REFERENCE_X and clearing_reference.is_empty():
					clearing_reference = sample
				if x <= FOREST_EDGE_X:
					if (
						forest_peak.is_empty()
						or float(sample.get("volume_db", -80.0))
						> float(forest_peak.get("volume_db", -80.0))
					):
						forest_peak = sample
				if quietest_outward.is_empty() or (
					float(sample.get("volume_db", -80.0))
					< float(quietest_outward.get("volume_db", -80.0))
				):
					quietest_outward = sample
				elif (
					float(sample.get("source_distance", 0.0))
					> float(quietest_outward.get("source_distance", INF))
					and float(sample.get("entrance_distance", 0.0))
					> float(quietest_outward.get("entrance_distance", INF))
				):
					var rebound := (
						float(sample.get("volume_db", -80.0))
						- float(quietest_outward.get("volume_db", -80.0))
					)
					largest_farther_rise_db = maxf(largest_farther_rise_db, rebound)
		if not clearing_reference.is_empty() and not forest_peak.is_empty():
			var forest_gain := (
				float(forest_peak.get("volume_db", -80.0))
				- float(clearing_reference.get("volume_db", -80.0))
			)
			if forest_gain > 0.5:
				rows_with_forest_gain += 1
			if forest_gain > largest_forest_gain_over_clearing_db:
				largest_forest_gain_over_clearing_db = forest_gain
				worst_forest_gain = {
					"z": z,
					"gain_db": forest_gain,
					"clearing": _report_sample(clearing_reference),
					"forest_peak": _report_sample(forest_peak),
				}
	return {
		"sample_count": sample_count,
		"row_count": z_count,
		"row_spacing_m": OUTWARD_TRACE_Z_SPACING,
		"step_spacing_m": GRID_SPACING,
		"largest_neighbor_step_db": largest_neighbor_step_db,
		"largest_farther_rise_db": largest_farther_rise_db,
		"largest_forest_gain_over_clearing_db": maxf(
			largest_forest_gain_over_clearing_db,
			0.0
		),
		"rows_with_forest_gain_over_half_db": rows_with_forest_gain,
		"worst_forest_gain": worst_forest_gain,
	}


func _analyze_pair(left: Dictionary, right: Dictionary, axis: StringName) -> Dictionary:
	if (
		bool(left.get("occupied", true))
		or bool(right.get("occupied", true))
		or not bool(left.get("audible", false))
		or not bool(right.get("audible", false))
	):
		return {}
	var left_volume := float(left.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
	var right_volume := float(right.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB))
	var step_db := absf(right_volume - left_volume)
	var farther: Dictionary = {}
	var nearer: Dictionary = {}
	if (
		float(right.get("source_distance", 0.0))
		> float(left.get("source_distance", INF))
		and float(right.get("entrance_distance", 0.0))
		> float(left.get("entrance_distance", INF))
	):
		farther = right
		nearer = left
	elif (
		float(left.get("source_distance", 0.0))
		> float(right.get("source_distance", INF))
		and float(left.get("entrance_distance", 0.0))
		> float(right.get("entrance_distance", INF))
	):
		farther = left
		nearer = right
	var farther_rise_db := (
		maxf(
			float(farther.get("volume_db", -80.0))
			- float(nearer.get("volume_db", -80.0)),
			0.0
		)
		if not farther.is_empty()
		else 0.0
	)
	var probe_switch := int(left.get("listener_probe", -1)) != int(
		right.get("listener_probe", -1)
	)
	var anomaly := {
		"axis": axis,
		"step_db": step_db,
		"farther_rise_db": farther_rise_db,
		"probe_switch_step_db": step_db if probe_switch else 0.0,
		"left": _report_sample(left),
		"right": _report_sample(right),
	}
	if step_db >= REPORT_STEP_THRESHOLD_DB:
		_track_anomaly(largest_steps, anomaly, &"step_db")
	if farther_rise_db >= REPORT_STEP_THRESHOLD_DB:
		_track_anomaly(largest_farther_rises, anomaly, &"farther_rise_db")
	if probe_switch and step_db >= REPORT_STEP_THRESHOLD_DB:
		_track_anomaly(largest_probe_switches, anomaly, &"probe_switch_step_db")
	return anomaly


func _report_sample(sample: Dictionary) -> Dictionary:
	return {
		"position": _vector_array(sample.get("position", Vector3.ZERO)),
		"volume_db": sample.get("volume_db", -80.0),
		"source_distance": sample.get("source_distance", 0.0),
		"entrance_distance": sample.get("entrance_distance", 0.0),
		"route": str(sample.get("route_kind", &"missing")),
		"listener_probe": sample.get("listener_probe", -1),
		"source_probe": sample.get("source_probe", -1),
		"path_length": sample.get("path_length", 0.0),
		"static_crossings": sample.get("static_crossings", 0),
		"direct_occlusion": sample.get("direct_occlusion", 0.0),
		"graph_weight": sample.get("graph_weight", 0.0),
		"direct_weight": sample.get("direct_weight", 1.0),
		"parallel_gain_db": sample.get("parallel_gain_db", 0.0),
		"diffuse_gain_db": sample.get("diffuse_gain_db", 0.0),
		"guided_gain_db": sample.get("guided_gain_db", 0.0),
		"reverb_send": sample.get("reverb_send", 0.0),
		"environment_enclosure": sample.get("environment_enclosure", 0.0),
	}


func _track_anomaly(
	target: Array[Dictionary],
	anomaly: Dictionary,
	key: StringName
) -> void:
	if target.size() >= MAX_REPORTED_ANOMALIES:
		var smallest := float(target[target.size() - 1].get(key, 0.0))
		if float(anomaly.get(key, 0.0)) <= smallest:
			return
	target.append(anomaly)
	_sort_anomalies(target, key)
	if target.size() > MAX_REPORTED_ANOMALIES:
		target.pop_back()


func _sort_anomalies(target: Array[Dictionary], key: StringName) -> void:
	target.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get(key, 0.0)) > float(right.get(key, 0.0))
	)


func _store_sample(bytes: PackedByteArray, offset: int, sample: Dictionary) -> void:
	bytes.encode_s16(offset, clampi(roundi(float(sample.get("volume_db", -80.0)) * 100.0), -32768, 32767))
	bytes.encode_u16(offset + 2, _centimeters(sample.get("source_distance", 0.0)))
	bytes.encode_u16(offset + 4, _centimeters(sample.get("entrance_distance", 0.0)))
	bytes.encode_u16(offset + 6, _centimeters(sample.get("path_length", 0.0)))
	bytes.encode_u16(offset + 8, clampi(int(sample.get("listener_probe", -1)) + 1, 0, 65535))
	bytes.encode_u16(offset + 10, clampi(int(sample.get("source_probe", -1)) + 1, 0, 65535))
	bytes.encode_s16(offset + 12, clampi(roundi(float(sample.get("diffuse_gain_db", 0.0)) * 100.0), -32768, 32767))
	bytes.encode_u16(offset + 14, clampi(roundi(float(sample.get("guided_gain_db", 0.0)) * 100.0), 0, 65535))
	bytes[offset + 16] = roundi(clampf(float(sample.get("reverb_send", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 17] = roundi(clampf(float(sample.get("environment_enclosure", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 18] = roundi(clampf(float(sample.get("direct_occlusion", 0.0)), 0.0, 1.0) * 255.0)
	bytes[offset + 19] = (
		int(bool(sample.get("audible", false)))
		| (int(bool(sample.get("occupied", false))) << 1)
		| (clampi(int(sample.get("route_code", 0)), 0, 15) << 2)
	)


func _point_is_occupied(
	space_state: PhysicsDirectSpaceState3D,
	query: PhysicsPointQueryParameters3D,
	position: Vector3
) -> bool:
	query.position = position
	return not space_state.intersect_point(query, 1).is_empty()


func _centimeters(value: Variant) -> int:
	return clampi(roundi(maxf(float(value), 0.0) * 100.0), 0, 65535)


func _route_code(route: StringName) -> int:
	match route:
		&"direct":
			return 1
		&"transmitted":
			return 2
		&"graph":
			return 3
		&"parallel":
			return 4
	return 0


func _save_report(report: Dictionary) -> bool:
	var directory := ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	return true


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


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
		print("Forest/maze dense probe tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Forest/maze dense probe tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

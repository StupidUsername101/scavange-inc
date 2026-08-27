extends SceneTree

const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const RADIO_DEFINITION_PATH := "res://resources/items/radios/portable_radio.tres"
const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")

const REPORT_STEM := "res://tests/generated/tunnel_acoustic_centimeter_report"
const FIELD_STEM := "res://tests/generated/tunnel_acoustic_centimeter_field"
const LISTENER_HEIGHT := 1.7
const GRID_SPACING := 0.01
const REGION_MIN_X := -1.0
const REGION_MAX_X := 25.0
const REGION_MIN_Z := 30.0
const REGION_MAX_Z := 70.0
const CONTINUOUS_SOURCE_ID := 3_290_001
const FIRST_LISTENER_ID := 3_300_000
const CROSS_AXIS_FIRST_LISTENER_ID := 3_400_000
const CROSS_AXIS_ROW_SPACING := 0.25
const BYTES_PER_SAMPLE := 16
const MAX_REPORTED_ANOMALIES := 256
const ANOMALY_STEP_DB := 0.15
const MAX_ALLOWED_SAME_REGIME_STEP_DB := 0.30
const MAX_ALLOWED_FARTHER_RISE_DB := 0.12
const MAX_ALLOWED_PROBE_SWITCH_STEP_DB := 0.75

var failure_count := 0
var assertion_count := 0
var _largest_anomalies: Array[Dictionary] = []
var _largest_same_regime_anomalies: Array[Dictionary] = []
var _largest_farther_rise_anomalies: Array[Dictionary] = []
var _largest_probe_switch_anomalies: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var audit_label := _audit_label()
	var report_path := REPORT_STEM + audit_label + ".json"
	var field_path := FIELD_STEM + audit_label + ".bin"
	var world := (
		(load(SERVER_WORLD_PATH) as PackedScene).instantiate() as Node3D
	)
	root.add_child(world)
	await physics_frame
	await process_frame
	var complex := world.get_node_or_null("IndustrialAcousticComplex") as Node3D
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	await physics_frame
	var radio := load(RADIO_DEFINITION_PATH) as RadioItemDefinition
	_expect(
		complex != null and radio != null and service.graph.probe_count() > 0,
		"centimetre audit uses the complete active map and baked tunnel graph"
	)
	if complex == null or radio == null or service.graph.probe_count() <= 0:
		_finish(world, service)
		return

	var source_position := complex.to_global(
		LAYOUT.TUNNEL_CENTER + Vector3(0.0, LISTENER_HEIGHT, 0.0)
	)
	var audit_mode := OS.get_environment("SCAVANGE_TUNNEL_AUDIT_MODE").strip_edges()
	if audit_mode == "setup":
		print("Tunnel cm audit setup complete; script parsed without scanning.")
		_finish(world, service)
		return
	if audit_mode == "cross":
		var cross_only_result := _audit_cross_axis_motion(
			service,
			source_position,
			radio
		)
		_expect(
			float(cross_only_result.get("largest_same_regime_step_db", INF))
			<= MAX_ALLOWED_SAME_REGIME_STEP_DB,
			"cross-tunnel motion cannot jump within one acoustic regime"
		)
		_expect(
			float(cross_only_result.get("largest_farther_rise_db", INF))
			<= MAX_ALLOWED_FARTHER_RISE_DB,
			"cross-tunnel motion cannot create a farther loudness hotspot"
		)
		_expect(
			float(cross_only_result.get("largest_probe_switch_step_db", INF))
			<= MAX_ALLOWED_PROBE_SWITCH_STEP_DB,
			"cross-tunnel probe ownership remains continuous"
		)
		print("Tunnel cm cross-motion audit: %s" % JSON.stringify(cross_only_result))
		_finish(world, service)
		return
	var x_count := roundi((REGION_MAX_X - REGION_MIN_X) / GRID_SPACING) + 1
	var z_count := roundi((REGION_MAX_Z - REGION_MIN_Z) / GRID_SPACING) + 1
	var sample_count := x_count * z_count
	var field_file := FileAccess.open(field_path, FileAccess.WRITE)
	_expect(field_file != null, "centimetre audit opens its compact field log")
	if field_file == null:
		_finish(world, service)
		return

	# One row buffer is reused for the complete scan. The binary field is exhaustive without
	# allocating ten million dictionaries or writing a multi-gigabyte JSON document.
	var row_bytes := PackedByteArray()
	row_bytes.resize(z_count * BYTES_PER_SAMPLE)
	var previous_volumes := PackedFloat32Array()
	var previous_distances := PackedFloat32Array()
	var previous_route_codes := PackedByteArray()
	var previous_blocked := PackedByteArray()
	var previous_occlusions := PackedFloat32Array()
	var previous_listener_probes := PackedInt32Array()
	var previous_audible := PackedByteArray()
	previous_volumes.resize(z_count)
	previous_distances.resize(z_count)
	previous_route_codes.resize(z_count)
	previous_blocked.resize(z_count)
	previous_occlusions.resize(z_count)
	previous_listener_probes.resize(z_count)
	previous_audible.resize(z_count)
	previous_volumes.fill(-80.0)
	previous_distances.fill(INF)
	previous_listener_probes.fill(-1)

	var audible_count := 0
	var any_step_count := 0
	var same_regime_step_count := 0
	var farther_rise_count := 0
	var probe_switch_step_count := 0
	var largest_same_regime_step_db := 0.0
	var largest_farther_rise_db := 0.0
	var largest_probe_switch_step_db := 0.0
	var largest_any_step_db := 0.0
	var static_cross_same_regime_step_db := 0.0
	var static_cross_farther_rise_db := 0.0
	var static_cross_probe_switch_step_db := 0.0
	var static_cross_any_step_db := 0.0
	var static_cross_anomaly_count := 0
	for x_index: int in range(x_count):
		var listener_id := FIRST_LISTENER_ID + x_index
		var x := REGION_MIN_X + float(x_index) * GRID_SPACING
		var left_volume := -80.0
		var left_distance := INF
		var left_route_code := 0
		var left_blocked := false
		var left_occlusion := 0.0
		var left_listener_probe := -1
		var left_audible := false
		for z_index: int in range(z_count):
			var z := REGION_MIN_Z + float(z_index) * GRID_SPACING
			var listener_position := Vector3(x, LISTENER_HEIGHT, z)
			var result := service.calculate_listener_result(
				listener_id,
				listener_position,
				source_position,
				radio.maximum_hearing_distance,
				radio.source_modifier,
				1.0,
				false,
				[],
				CONTINUOUS_SOURCE_ID
			)
			var audible := bool(result.get("audible", false))
			var volume_db := (
				float(result.get("volume_db", -80.0))
				+ radio.playback_volume_db
				if audible
				else -80.0
			)
			var direct_distance := listener_position.distance_to(source_position)
			var route_code := _route_code(result.get("route_kind", &"missing"))
			var direct_occlusion := float(result.get("direct_occlusion", 0.0))
			var blocked := direct_occlusion > 0.0001
			var source_probe := int(result.get("source_probe_index", -1))
			var listener_probe := int(result.get(
				"listener_origin_probe_index",
				_listener_origin_probe(
					service,
					listener_id,
					source_probe
				)
			)
			)
			if audible:
				audible_count += 1
			_store_sample(
				row_bytes,
				z_index * BYTES_PER_SAMPLE,
				volume_db,
				float(result.get("guided_propagation_gain_db", 0.0)),
				float(result.get("path_length", 0.0)),
				float(result.get("range_path_length", 0.0)),
				listener_probe,
				source_probe,
				float(result.get("lowpass_hz", 20000.0)),
				float(result.get("reverb_send", 0.0)),
				audible,
				blocked,
				route_code,
				direct_occlusion
			)

			if z_index > 0:
				var along_result := _analyze_neighbor(
					Vector3(x, LISTENER_HEIGHT, z - GRID_SPACING),
					left_volume,
					left_distance,
					left_route_code,
					left_blocked,
					left_occlusion,
					left_listener_probe,
					left_audible,
					listener_position,
					volume_db,
					direct_distance,
					route_code,
					blocked,
					direct_occlusion,
					listener_probe,
					audible,
					result,
					&"z"
				)
				largest_same_regime_step_db = maxf(
					largest_same_regime_step_db,
					float(along_result.get("same_regime_step_db", 0.0))
				)
				largest_farther_rise_db = maxf(
					largest_farther_rise_db,
					float(along_result.get("farther_rise_db", 0.0))
				)
				largest_probe_switch_step_db = maxf(
					largest_probe_switch_step_db,
					float(along_result.get("probe_switch_step_db", 0.0))
				)
				largest_any_step_db = maxf(
					largest_any_step_db,
					float(along_result.get("any_step_db", 0.0))
				)
				any_step_count += int(along_result.get("any_step", false))
				same_regime_step_count += int(along_result.get("same_regime_step", false))
				farther_rise_count += int(along_result.get("farther_rise", false))
				probe_switch_step_count += int(along_result.get("probe_switch_step", false))
			if x_index > 0:
				var cross_result := _analyze_neighbor(
					Vector3(x - GRID_SPACING, LISTENER_HEIGHT, z),
					previous_volumes[z_index],
					previous_distances[z_index],
					previous_route_codes[z_index],
					previous_blocked[z_index] != 0,
					previous_occlusions[z_index],
					previous_listener_probes[z_index],
					previous_audible[z_index] != 0,
					listener_position,
					volume_db,
					direct_distance,
					route_code,
					blocked,
					direct_occlusion,
					listener_probe,
					audible,
					result,
					&"x_static",
					false
				)
				static_cross_same_regime_step_db = maxf(
					static_cross_same_regime_step_db,
					float(cross_result.get("same_regime_step_db", 0.0))
				)
				static_cross_farther_rise_db = maxf(
					static_cross_farther_rise_db,
					float(cross_result.get("farther_rise_db", 0.0))
				)
				static_cross_probe_switch_step_db = maxf(
					static_cross_probe_switch_step_db,
					float(cross_result.get("probe_switch_step_db", 0.0))
				)
				static_cross_any_step_db = maxf(
					static_cross_any_step_db,
					float(cross_result.get("any_step_db", 0.0))
				)
				static_cross_anomaly_count += int(cross_result.get("any_step", false))

			left_volume = volume_db
			left_distance = direct_distance
			left_route_code = route_code
			left_blocked = blocked
			left_occlusion = direct_occlusion
			left_listener_probe = listener_probe
			left_audible = audible
			previous_volumes[z_index] = volume_db
			previous_distances[z_index] = direct_distance
			previous_route_codes[z_index] = route_code
			previous_blocked[z_index] = 1 if blocked else 0
			previous_occlusions[z_index] = direct_occlusion
			previous_listener_probes[z_index] = listener_probe
			previous_audible[z_index] = 1 if audible else 0
		field_file.store_buffer(row_bytes)
		if x_index % 25 == 0 or x_index == x_count - 1:
			print(
				"Tunnel cm audit: %d/%d columns, %d/%d samples, %.1f s"
				% [
					x_index + 1,
					x_count,
					(x_index + 1) * z_count,
					sample_count,
					float(Time.get_ticks_msec() - started_msec) / 1000.0,
				]
			)
	field_file.close()
	var cross_axis_motion := _audit_cross_axis_motion(
		service,
		source_position,
		radio
	)
	var normative_same_regime_step_db := maxf(
		largest_same_regime_step_db,
		float(cross_axis_motion.get("largest_same_regime_step_db", 0.0))
	)
	var normative_farther_rise_db := maxf(
		largest_farther_rise_db,
		float(cross_axis_motion.get("largest_farther_rise_db", 0.0))
	)
	var normative_probe_switch_step_db := maxf(
		largest_probe_switch_step_db,
		float(cross_axis_motion.get("largest_probe_switch_step_db", 0.0))
	)

	_sort_anomalies(_largest_anomalies)
	_sort_anomalies(_largest_same_regime_anomalies)
	_sort_anomalies(_largest_farther_rise_anomalies)
	_sort_anomalies(_largest_probe_switch_anomalies)
	var report := {
		"schema_version": 1,
		"world_scene": SERVER_WORLD_PATH,
		"source_position": _vector_array(source_position),
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
		},
		"binary_field": {
			"path": field_path,
			"bytes_per_sample": BYTES_PER_SAMPLE,
			"little_endian_fields": [
				"volume_centidb:int16",
				"guided_gain_centidb:uint16",
				"path_length_cm:uint16",
				"range_path_length_cm:uint16",
				"listener_probe_plus_one:uint16",
				"source_probe_plus_one:uint16",
				"lowpass_div_100_hz:uint8",
				"reverb_0_to_255:uint8",
				"flags:uint8 (audible, blocked, route<<2)",
				"direct_occlusion_0_to_255:uint8",
			],
		},
		"summary": {
			"sample_count": sample_count,
			"audible_count": audible_count,
			"any_step_count": any_step_count,
			"same_regime_step_count": (
				same_regime_step_count
				+ int(cross_axis_motion.get("same_regime_step_count", 0))
			),
			"farther_rise_count": (
				farther_rise_count
				+ int(cross_axis_motion.get("farther_rise_count", 0))
			),
			"probe_switch_step_count": (
				probe_switch_step_count
				+ int(cross_axis_motion.get("probe_switch_step_count", 0))
			),
			"largest_same_regime_step_db": normative_same_regime_step_db,
			"largest_farther_rise_db": normative_farther_rise_db,
			"largest_probe_switch_step_db": normative_probe_switch_step_db,
			"largest_any_step_db": largest_any_step_db,
			"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) / 1000.0,
		},
		"movement_z_axis": {
			"row_spacing_m": GRID_SPACING,
			"largest_same_regime_step_db": largest_same_regime_step_db,
			"largest_farther_rise_db": largest_farther_rise_db,
			"largest_probe_switch_step_db": largest_probe_switch_step_db,
		},
		"movement_x_axis": cross_axis_motion,
		"static_cross_axis_diagnostics": {
			"note": "Adjacent independently cached z-walk columns are logged, but are not sideways movement.",
			"anomaly_count": static_cross_anomaly_count,
			"largest_any_step_db": static_cross_any_step_db,
			"largest_same_regime_step_db": static_cross_same_regime_step_db,
			"largest_farther_rise_db": static_cross_farther_rise_db,
			"largest_probe_switch_step_db": static_cross_probe_switch_step_db,
		},
		"largest_anomalies": _largest_anomalies,
		"largest_same_regime_anomalies": _largest_same_regime_anomalies,
		"largest_farther_rise_anomalies": _largest_farther_rise_anomalies,
		"largest_probe_switch_anomalies": _largest_probe_switch_anomalies,
	}
	_expect(
		_save_report(report, report_path),
		"centimetre audit serializes detailed anomaly metadata"
	)
	_expect(
		sample_count > 10_000_000 and is_equal_approx(GRID_SPACING, 0.01),
		"more than ten million listener samples cover every centimetre of the northern tunnel field"
	)
	_expect(
		normative_same_regime_step_db <= MAX_ALLOWED_SAME_REGIME_STEP_DB,
		"same-route tunnel levels cannot jump across one centimetre"
	)
	_expect(
		normative_farther_rise_db <= MAX_ALLOWED_FARTHER_RISE_DB,
		"a farther centimetre cannot become materially louder in the same acoustic regime"
	)
	_expect(
		normative_probe_switch_step_db <= MAX_ALLOWED_PROBE_SWITCH_STEP_DB,
		"probe ownership changes cannot create a tunnel loudness hotspot"
	)
	print(
		"Tunnel cm audit complete: %d samples, any %.3f dB, same %.3f dB, rise %.3f dB, switch %.3f dB"
		% [
			sample_count,
			largest_any_step_db,
			normative_same_regime_step_db,
			normative_farther_rise_db,
			normative_probe_switch_step_db,
		]
	)
	_finish(world, service)


func _audit_cross_axis_motion(
	service: ServerAcousticService,
	source_position: Vector3,
	radio: RadioItemDefinition
) -> Dictionary:
	var x_count := roundi((REGION_MAX_X - REGION_MIN_X) / GRID_SPACING) + 1
	var z_count := roundi(
		(REGION_MAX_Z - REGION_MIN_Z) / CROSS_AXIS_ROW_SPACING
	) + 1
	var same_regime_step_count := 0
	var farther_rise_count := 0
	var probe_switch_step_count := 0
	var largest_same_regime_step_db := 0.0
	var largest_farther_rise_db := 0.0
	var largest_probe_switch_step_db := 0.0
	for z_index: int in range(z_count):
		var z := REGION_MIN_Z + float(z_index) * CROSS_AXIS_ROW_SPACING
		for direction_index: int in range(2):
			var direction := 1 if direction_index == 0 else -1
			var listener_id := (
				CROSS_AXIS_FIRST_LISTENER_ID + z_index * 2 + direction_index
			)
			var previous_position := Vector3.ZERO
			var previous_volume := -80.0
			var previous_distance := INF
			var previous_route := 0
			var previous_blocked := false
			var previous_occlusion := 0.0
			var previous_listener_probe := -1
			var previous_audible := false
			for offset: int in range(x_count):
				var x_index := offset if direction > 0 else x_count - 1 - offset
				var x := REGION_MIN_X + float(x_index) * GRID_SPACING
				var listener_position := Vector3(x, LISTENER_HEIGHT, z)
				var result := service.calculate_listener_result(
					listener_id,
					listener_position,
					source_position,
					radio.maximum_hearing_distance,
					radio.source_modifier,
					1.0,
					false,
					[],
					CONTINUOUS_SOURCE_ID
				)
				var audible := bool(result.get("audible", false))
				var volume_db := (
					float(result.get("volume_db", -80.0))
					+ radio.playback_volume_db
					if audible
					else -80.0
				)
				var direct_distance := listener_position.distance_to(source_position)
				var route_code := _route_code(result.get("route_kind", &"missing"))
				var direct_occlusion := float(result.get("direct_occlusion", 0.0))
				var blocked := direct_occlusion > 0.0001
				var source_probe := int(result.get("source_probe_index", -1))
				var listener_probe := int(result.get(
					"listener_origin_probe_index",
					_listener_origin_probe(service, listener_id, source_probe)
				))
				if offset > 0:
					var neighbor := _analyze_neighbor(
						previous_position,
						previous_volume,
						previous_distance,
						previous_route,
						previous_blocked,
						previous_occlusion,
						previous_listener_probe,
						previous_audible,
						listener_position,
						volume_db,
						direct_distance,
						route_code,
						blocked,
						direct_occlusion,
						listener_probe,
						audible,
						result,
						&"x_motion"
					)
					largest_same_regime_step_db = maxf(
						largest_same_regime_step_db,
						float(neighbor.get("same_regime_step_db", 0.0))
					)
					largest_farther_rise_db = maxf(
						largest_farther_rise_db,
						float(neighbor.get("farther_rise_db", 0.0))
					)
					largest_probe_switch_step_db = maxf(
						largest_probe_switch_step_db,
						float(neighbor.get("probe_switch_step_db", 0.0))
					)
					same_regime_step_count += int(neighbor.get("same_regime_step", false))
					farther_rise_count += int(neighbor.get("farther_rise", false))
					probe_switch_step_count += int(neighbor.get("probe_switch_step", false))
				previous_position = listener_position
				previous_volume = volume_db
				previous_distance = direct_distance
				previous_route = route_code
				previous_blocked = blocked
				previous_occlusion = direct_occlusion
				previous_listener_probe = listener_probe
				previous_audible = audible
		if z_index % 20 == 0 or z_index == z_count - 1:
			print("Tunnel cm x-motion audit: %d/%d rows" % [z_index + 1, z_count])
	return {
		"row_spacing_m": CROSS_AXIS_ROW_SPACING,
		"directions_per_row": 2,
		"sample_count": z_count * x_count * 2,
		"same_regime_step_count": same_regime_step_count,
		"farther_rise_count": farther_rise_count,
		"probe_switch_step_count": probe_switch_step_count,
		"largest_same_regime_step_db": largest_same_regime_step_db,
		"largest_farther_rise_db": largest_farther_rise_db,
		"largest_probe_switch_step_db": largest_probe_switch_step_db,
	}


func _analyze_neighbor(
	position_a: Vector3,
	volume_a: float,
	distance_a: float,
	route_a: int,
	blocked_a: bool,
	occlusion_a: float,
	listener_probe_a: int,
	audible_a: bool,
	position_b: Vector3,
	volume_b: float,
	distance_b: float,
	route_b: int,
	blocked_b: bool,
	occlusion_b: float,
	listener_probe_b: int,
	audible_b: bool,
	result_b: Dictionary,
	axis: StringName,
	record_anomaly := true
) -> Dictionary:
	if not audible_a or not audible_b:
		return {}
	var step_db := absf(volume_b - volume_a)
	var any_step := step_db > ANOMALY_STEP_DB
	var same_regime := (
		route_a == route_b
		and blocked_a == blocked_b
		and absf(occlusion_a - occlusion_b) < 0.03
	)
	var probe_switch := listener_probe_a != listener_probe_b
	var farther_is_b := distance_b > distance_a
	var farther_rise_db := (
		volume_b - volume_a
		if farther_is_b
		else volume_a - volume_b
	)
	var same_regime_step := same_regime and not probe_switch and step_db > ANOMALY_STEP_DB
	var farther_rise := (
		same_regime
		and not probe_switch
		and farther_rise_db > MAX_ALLOWED_FARTHER_RISE_DB
	)
	var probe_switch_step := (
		probe_switch and same_regime and step_db > ANOMALY_STEP_DB
	)
	if record_anomaly and (any_step or farther_rise):
		var anomaly := {
			"axis": str(axis),
			"position_a": _vector_array(position_a),
			"position_b": _vector_array(position_b),
			"volume_a_db": volume_a,
			"volume_b_db": volume_b,
			"step_db": step_db,
			"farther_rise_db": farther_rise_db,
			"route_a": route_a,
			"route_b": route_b,
			"blocked_a": blocked_a,
			"blocked_b": blocked_b,
			"direct_occlusion_a": occlusion_a,
			"direct_occlusion_b": occlusion_b,
			"listener_probe_a": listener_probe_a,
			"listener_probe_b": listener_probe_b,
			"result_b": _result_diagnostics(result_b),
			"severity_db": maxf(step_db, maxf(farther_rise_db, 0.0)),
		}
		_record_anomaly(anomaly)
		if same_regime_step:
			_record_ranked_anomaly(_largest_same_regime_anomalies, anomaly)
		if farther_rise:
			_record_ranked_anomaly(_largest_farther_rise_anomalies, anomaly)
		if probe_switch_step:
			_record_ranked_anomaly(_largest_probe_switch_anomalies, anomaly)
	return {
		"any_step": any_step,
		"any_step_db": step_db,
		"same_regime_step": same_regime_step,
		"same_regime_step_db": step_db if same_regime and not probe_switch else 0.0,
		"farther_rise": farther_rise,
		"farther_rise_db": maxf(farther_rise_db, 0.0) if same_regime and not probe_switch else 0.0,
		"probe_switch_step": probe_switch_step,
		"probe_switch_step_db": step_db if probe_switch and same_regime else 0.0,
	}


func _record_anomaly(anomaly: Dictionary) -> void:
	_record_ranked_anomaly(_largest_anomalies, anomaly)


func _record_ranked_anomaly(
	target: Array[Dictionary],
	anomaly: Dictionary
) -> void:
	if target.size() < MAX_REPORTED_ANOMALIES:
		target.append(anomaly)
		return
	var smallest_index := 0
	var smallest_severity := float(target[0].get("severity_db", 0.0))
	for anomaly_index: int in range(1, target.size()):
		var severity := float(
			target[anomaly_index].get("severity_db", 0.0)
		)
		if severity < smallest_severity:
			smallest_severity = severity
			smallest_index = anomaly_index
	if float(anomaly.get("severity_db", 0.0)) > smallest_severity:
		target[smallest_index] = anomaly


func _sort_anomalies(target: Array[Dictionary]) -> void:
	target.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left.get("severity_db", 0.0)) > float(
				right.get("severity_db", 0.0)
			)
	)


func _listener_origin_probe(
	service: ServerAcousticService,
	listener_id: int,
	source_probe: int
) -> int:
	var field := service._fields_by_listener.get(listener_id) as AcousticPropagationField
	if (
		field == null
		or source_probe < 0
		or source_probe >= field.origin_probes.size()
	):
		return -1
	return field.origin_probes[source_probe]


func _result_diagnostics(result: Dictionary) -> Dictionary:
	return {
		"route_kind": str(result.get("route_kind", &"missing")),
		"direct_occlusion": result.get("direct_occlusion", 0.0),
		"path_length": result.get("path_length", 0.0),
		"range_path_length": result.get("range_path_length", 0.0),
		"guided_path_length": result.get("guided_path_length", 0.0),
		"guided_gain_db": result.get("guided_propagation_gain_db", 0.0),
		"route_guided_strength": result.get("route_guided_strength", 0.0),
		"diffuse_gain_db": result.get("diffuse_field_gain_db", 0.0),
		"environment_enclosure": result.get("environment_enclosure", 0.0),
		"reverb_send": result.get("reverb_send", 0.0),
		"lowpass_hz": result.get("lowpass_hz", 20000.0),
		"modifier_ids": Array(result.get("modifier_ids", PackedStringArray())),
	}


func _store_sample(
	buffer: PackedByteArray,
	offset: int,
	volume_db: float,
	guided_gain_db: float,
	path_length: float,
	range_path_length: float,
	listener_probe: int,
	source_probe: int,
	lowpass_hz: float,
	reverb_send: float,
	audible: bool,
	blocked: bool,
	route_code: int,
	direct_occlusion: float
) -> void:
	_store_u16(buffer, offset, clampi(roundi(volume_db * 100.0), -32768, 32767) & 0xffff)
	_store_u16(buffer, offset + 2, clampi(roundi(guided_gain_db * 100.0), 0, 65535))
	_store_u16(buffer, offset + 4, clampi(roundi(path_length * 100.0), 0, 65535))
	_store_u16(buffer, offset + 6, clampi(roundi(range_path_length * 100.0), 0, 65535))
	_store_u16(buffer, offset + 8, clampi(listener_probe + 1, 0, 65535))
	_store_u16(buffer, offset + 10, clampi(source_probe + 1, 0, 65535))
	buffer[offset + 12] = clampi(roundi(lowpass_hz / 100.0), 0, 255)
	buffer[offset + 13] = clampi(roundi(clampf(reverb_send, 0.0, 1.0) * 255.0), 0, 255)
	buffer[offset + 14] = (
		(1 if audible else 0)
		| ((1 if blocked else 0) << 1)
		| (clampi(route_code, 0, 3) << 2)
	)
	buffer[offset + 15] = clampi(
		roundi(clampf(direct_occlusion, 0.0, 1.0) * 255.0),
		0,
		255
	)


func _store_u16(buffer: PackedByteArray, offset: int, value: int) -> void:
	buffer[offset] = value & 0xff
	buffer[offset + 1] = (value >> 8) & 0xff


func _route_code(route: Variant) -> int:
	match StringName(str(route)):
		&"direct":
			return 1
		&"graph":
			return 2
		&"parallel":
			return 3
	return 0


func _save_report(report: Dictionary, report_path: String) -> bool:
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true


func _audit_label() -> String:
	var requested := OS.get_environment("SCAVANGE_TUNNEL_AUDIT_LABEL").strip_edges()
	if requested.is_empty():
		return ""
	var sanitized := ""
	for character: String in requested:
		if character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789-_":
			sanitized += character.to_lower()
	return "_" + sanitized if not sanitized.is_empty() else ""


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _expect(condition: bool, description: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % description)
		return
	failure_count += 1
	push_error("[FAIL] %s" % description)


func _finish(world: Node, service: Node) -> void:
	if service != null:
		service.free()
	if world != null:
		world.free()
	if failure_count == 0:
		print("Tunnel centimetre audit passed: %d assertions" % assertion_count)
		quit(0)
		return
	push_error(
		"Tunnel centimetre audit failed: %d/%d assertions"
		% [failure_count, assertion_count]
	)
	quit(1)

extends SceneTree

const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const RADIO_DEFINITION_PATH := "res://resources/items/radios/portable_radio.tres"
const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")

const REPORT_PATH := "res://tests/generated/tunnel_acoustic_dense_snapshot.json"
const LISTENER_HEIGHT := 1.7
const GRID_SPACING := 0.25
const X_RADIUS := 12.0
const INSIDE_DISTANCE := 4.0
const OUTSIDE_DISTANCE := 24.0
const FIRST_LISTENER_ID := 310000
const CONTINUOUS_SOURCE_ID := 319001
const HARD_CUTOFF_AUDIBLE_DB := -58.0
const MAX_REPORTED_TRANSITIONS := 128

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
		"dense measurement uses the active world, radio definition, and baked acoustic graph"
	)
	if complex == null or radio == null or service.graph.probe_count() <= 0:
		await _finish(world, service)
		return

	var south_mouth := complex.to_global(
		LAYOUT.TUNNEL_CENTER
		+ Vector3(0.0, LISTENER_HEIGHT, -LAYOUT.TUNNEL_LENGTH * 0.5)
	)
	var source_position := complex.to_global(
		LAYOUT.TUNNEL_CENTER
		+ Vector3(
			0.0,
			LISTENER_HEIGHT,
			LAYOUT.TUNNEL_LENGTH * 0.5 - 4.0
		)
	)
	var x_count := roundi(X_RADIUS * 2.0 / GRID_SPACING) + 1
	var outward_count := roundi(
		(INSIDE_DISTANCE + OUTSIDE_DISTANCE) / GRID_SPACING
	) + 1
	var sample_count := x_count * outward_count
	var samples: Array[Dictionary] = []
	samples.resize(sample_count)
	var space_state := world.get_world_3d().direct_space_state
	var valid_count := 0
	var audible_count := 0
	var maximum_guided_gain_db := 0.0

	for x_index: int in range(x_count):
		var x_offset := -X_RADIUS + float(x_index) * GRID_SPACING
		for outward_index: int in range(outward_count):
			var outside_m := -INSIDE_DISTANCE + float(outward_index) * GRID_SPACING
			var listener_position := south_mouth + Vector3(x_offset, 0.0, -outside_m)
			var sample_index := x_index * outward_count + outward_index
			var occupied := _point_is_occupied(space_state, listener_position)
			var sample := {
				"grid": [x_index, outward_index],
				"x_offset": x_offset,
				"outside_distance": outside_m,
				"position": _vector_array(listener_position),
				"occupied": occupied,
				"audible": false,
				"volume_db": -80.0,
			}
			if occupied:
				samples[sample_index] = sample
				continue
			valid_count += 1
			var listener_id := FIRST_LISTENER_ID + sample_index
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
			var direct_path := service._sample_direct_path(
				listener_id,
				listener_position,
				source_position,
				[],
				CONTINUOUS_SOURCE_ID
			)
			var source_probe_index := int(result.get("source_probe_index", -1))
			var listener_origin_probe_index := -1
			var listener_field := service._fields_by_listener.get(
				listener_id
			) as AcousticPropagationField
			if (
				listener_field != null
				and source_probe_index >= 0
				and source_probe_index < listener_field.origin_probes.size()
			):
				listener_origin_probe_index = listener_field.origin_probes[
					source_probe_index
				]
			var audible := bool(result.get("audible", false))
			var guided_gain_db := float(
				result.get("guided_propagation_gain_db", 0.0)
			)
			maximum_guided_gain_db = maxf(maximum_guided_gain_db, guided_gain_db)
			if audible:
				audible_count += 1
			var modifier_ids: Array[String] = []
			for modifier_id: String in result.get("modifier_ids", PackedStringArray()):
				modifier_ids.append(modifier_id)
			sample.merge({
				"audible": audible,
				"volume_db": (
					float(result.get("volume_db", -80.0))
					+ radio.playback_volume_db
					if audible
					else -80.0
				),
				"propagation_volume_db": float(result.get("volume_db", -80.0)),
				"direct_distance": listener_position.distance_to(source_position),
				"path_length": float(result.get("path_length", 0.0)),
				"source_probe_index": source_probe_index,
				"source_probe_id": str(service.graph.get_probe_id(source_probe_index)),
				"listener_origin_probe_index": listener_origin_probe_index,
				"listener_origin_probe_id": str(service.graph.get_probe_id(
					listener_origin_probe_index
				)),
				"range_path_length": float(result.get("range_path_length", 0.0)),
				"guided_path_length": float(result.get("guided_path_length", 0.0)),
				"guided_gain_db": guided_gain_db,
				"route_guided_strength": float(result.get("route_guided_strength", 0.0)),
				"unspread_volume_db": float(result.get("unspread_volume_db", -80.0)),
				"geometric_spreading_db": float(result.get("geometric_spreading_db", 0.0)),
				"diffuse_field_gain_db": float(result.get("diffuse_field_gain_db", 0.0)),
				"diffuse_field_support": float(result.get("diffuse_field_support", 0.0)),
				"route_kind": str(result.get("route_kind", &"unknown")),
				"direct_path_blocked": bool(direct_path.get("blocked", false)),
				"direct_occlusion": float(direct_path.get("occlusion", 0.0)),
				"environment_enclosure": float(result.get("environment_enclosure", 0.0)),
				"lowpass_hz": float(result.get("lowpass_hz", 20000.0)),
				"modifier_ids": modifier_ids,
			}, true)
			samples[sample_index] = sample

	var analysis := _analyze(samples, x_count, outward_count)
	var ten_meter_sample: Dictionary = samples[
		roundi(X_RADIUS / GRID_SPACING) * outward_count
		+ roundi((INSIDE_DISTANCE + 10.0) / GRID_SPACING)
	]
	var mouth_center_sample: Dictionary = samples[
		roundi(X_RADIUS / GRID_SPACING) * outward_count
		+ roundi(INSIDE_DISTANCE / GRID_SPACING)
	]
	var report := {
		"schema_version": 1,
		"world_scene": SERVER_WORLD_PATH,
		"sound": {
			"definition": radio.resource_path,
			"source_position": _vector_array(source_position),
			"base_max_distance": radio.maximum_hearing_distance,
			"playback_volume_db": radio.playback_volume_db,
		},
		"grid": {
			"center": _vector_array(south_mouth),
			"spacing": GRID_SPACING,
			"x_radius": X_RADIUS,
			"inside_distance": INSIDE_DISTANCE,
			"outside_distance": OUTSIDE_DISTANCE,
			"x_count": x_count,
			"outward_count": outward_count,
		},
		"summary": {
			"sample_count": sample_count,
			"valid_sample_count": valid_count,
			"audible_sample_count": audible_count,
			"maximum_guided_gain_db": maximum_guided_gain_db,
			"hard_cutoff_count": (analysis.get("hard_cutoffs", []) as Array).size(),
			"reappearance_count": (analysis.get("reappearances", []) as Array).size(),
			"same_regime_rise_count": (analysis.get("same_regime_rises", []) as Array).size(),
			"largest_same_regime_step_db": analysis.get("largest_same_regime_step_db", 0.0),
			"largest_clearly_audible_same_regime_step_db": analysis.get(
				"largest_clearly_audible_same_regime_step_db",
				0.0
			),
			"largest_center_outward_rise_db": analysis.get("largest_center_outward_rise_db", 0.0),
			"ten_meters_outside_center_volume_db": ten_meter_sample.get("volume_db", -80.0),
		},
		"hard_cutoffs": analysis.get("hard_cutoffs", []),
		"reappearances": analysis.get("reappearances", []),
		"largest_same_regime_transitions": analysis.get("largest_same_regime_transitions", []),
		"same_regime_rises": analysis.get("same_regime_rises", []),
		"samples": samples,
	}
	_expect(_save_report(report), "quarter-metre tunnel-mouth measurements are serialized as JSON")
	_expect(
		sample_count >= 10000 and is_equal_approx(GRID_SPACING, 0.25),
		"the focused field contains more than ten thousand evenly spaced quarter-metre probes"
	)
	_expect(
		bool(ten_meter_sample.get("audible", false))
		and float(ten_meter_sample.get("volume_db", -80.0))
		<= float(mouth_center_sample.get("volume_db", -80.0)) + 1.0
		and float(ten_meter_sample.get("volume_db", -80.0)) > -58.0,
		"a far-end radio remains audible ten metres outside without exceeding its mouth level"
	)
	_expect(
		maximum_guided_gain_db <= AcousticPropagationGraph.MAX_GUIDED_RECOVERY_DB + 0.01,
		"the measured field never exceeds the bounded tunnel recovery budget"
	)
	_expect(
		(analysis.get("hard_cutoffs", []) as Array).is_empty(),
		"no quarter-metre neighbor cuts a clearly audible sample directly to silence"
	)
	_expect(
		(analysis.get("reappearances", []) as Array).is_empty(),
		"outward probe lines never go silent and then become audible again"
	)
	_expect(
		float(analysis.get("largest_clearly_audible_same_regime_step_db", INF)) < 6.0,
		"usefully audible same-route neighbors stay below a six-decibel quarter-metre step"
	)
	_expect(
		float(analysis.get("largest_center_outward_rise_db", INF)) < 2.3,
		"the centerline cannot produce a large loudness rebound while moving away from the mouth"
	)
	print(
		"Dense tunnel report: %s (%d samples, %.2f dB at 10 m, %d hard cutoffs)"
		% [
			ProjectSettings.globalize_path(REPORT_PATH),
			sample_count,
			float(ten_meter_sample.get("volume_db", -80.0)),
			(analysis.get("hard_cutoffs", []) as Array).size(),
		]
	)
	await _finish(world, service)


func _analyze(
	samples: Array[Dictionary],
	x_count: int,
	outward_count: int
) -> Dictionary:
	var hard_cutoffs: Array[Dictionary] = []
	var same_regime_transitions: Array[Dictionary] = []
	var same_regime_rises: Array[Dictionary] = []
	var reappearances: Array[Dictionary] = []
	var largest_same_regime_step_db := 0.0
	var largest_clearly_audible_same_regime_step_db := 0.0
	var largest_center_outward_rise_db := 0.0
	for x_index: int in range(x_count):
		var quiet_boundary_seen := false
		for outward_index: int in range(outward_count):
			var sample := samples[x_index * outward_count + outward_index]
			if bool(sample.get("occupied", true)):
				quiet_boundary_seen = false
				continue
			if not bool(sample.get("audible", false)):
				quiet_boundary_seen = true
			elif (
				quiet_boundary_seen
				and float(sample.get("volume_db", -80.0)) > HARD_CUTOFF_AUDIBLE_DB
			):
				reappearances.append({
					"grid": sample.get("grid", []),
					"position": sample.get("position", []),
					"volume_db": sample.get("volume_db", -80.0),
				})
				quiet_boundary_seen = false
	for x_index: int in range(x_count):
		for outward_index: int in range(outward_count):
			var index := x_index * outward_count + outward_index
			if x_index + 1 < x_count:
				_analyze_pair(
					samples[index],
					samples[(x_index + 1) * outward_count + outward_index],
					hard_cutoffs,
					same_regime_transitions,
					same_regime_rises
				)
			if outward_index + 1 < outward_count:
				_analyze_pair(
					samples[index],
					samples[index + 1],
					hard_cutoffs,
					same_regime_transitions,
					same_regime_rises
				)
	same_regime_transitions.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return float(left["step_db"]) > float(right["step_db"])
	)
	if not same_regime_transitions.is_empty():
		largest_same_regime_step_db = float(same_regime_transitions[0]["step_db"])
	for transition: Dictionary in same_regime_transitions:
		if maxf(
			float(transition.get("a_volume_db", -80.0)),
			float(transition.get("b_volume_db", -80.0))
		) <= HARD_CUTOFF_AUDIBLE_DB:
			continue
		largest_clearly_audible_same_regime_step_db = maxf(
			largest_clearly_audible_same_regime_step_db,
			float(transition.get("step_db", 0.0))
		)
	var center_x_index := x_count >> 1
	for outward_index: int in range(1, outward_count):
		var nearer := samples[center_x_index * outward_count + outward_index - 1]
		var farther := samples[center_x_index * outward_count + outward_index]
		if (
			bool(nearer.get("occupied", true))
			or bool(farther.get("occupied", true))
			or not bool(nearer.get("audible", false))
			or not bool(farther.get("audible", false))
		):
			continue
		largest_center_outward_rise_db = maxf(
			largest_center_outward_rise_db,
			float(farther.get("volume_db", -80.0))
			- float(nearer.get("volume_db", -80.0))
		)
	return {
		"hard_cutoffs": hard_cutoffs.slice(0, mini(MAX_REPORTED_TRANSITIONS, hard_cutoffs.size())),
		"reappearances": reappearances.slice(0, mini(MAX_REPORTED_TRANSITIONS, reappearances.size())),
		"same_regime_rises": same_regime_rises.slice(0, mini(MAX_REPORTED_TRANSITIONS, same_regime_rises.size())),
		"largest_same_regime_step_db": largest_same_regime_step_db,
		"largest_clearly_audible_same_regime_step_db": largest_clearly_audible_same_regime_step_db,
		"largest_center_outward_rise_db": largest_center_outward_rise_db,
		"largest_same_regime_transitions": same_regime_transitions.slice(
			0,
			mini(MAX_REPORTED_TRANSITIONS, same_regime_transitions.size())
		),
	}


func _analyze_pair(
	left: Dictionary,
	right: Dictionary,
	hard_cutoffs: Array[Dictionary],
	same_regime_transitions: Array[Dictionary],
	same_regime_rises: Array[Dictionary]
) -> void:
	if bool(left.get("occupied", true)) or bool(right.get("occupied", true)):
		return
	var left_audible := bool(left.get("audible", false))
	var right_audible := bool(right.get("audible", false))
	if left_audible != right_audible:
		var audible_sample := left if left_audible else right
		if float(audible_sample.get("volume_db", -80.0)) > HARD_CUTOFF_AUDIBLE_DB:
			hard_cutoffs.append({
				"audible_grid": audible_sample.get("grid", []),
				"audible_position": audible_sample.get("position", []),
				"audible_volume_db": audible_sample.get("volume_db", -80.0),
				"silent_grid": right.get("grid", []) if left_audible else left.get("grid", []),
			})
		return
	if not left_audible:
		return
	var same_regime: bool = (
		str(left.get("route_kind", "")) == str(right.get("route_kind", ""))
		and bool(left.get("direct_path_blocked", false))
		== bool(right.get("direct_path_blocked", false))
		and left.get("modifier_ids", []) == right.get("modifier_ids", [])
		and absf(
			float(left.get("environment_enclosure", 0.0))
			- float(right.get("environment_enclosure", 0.0))
		) < 0.1
	)
	if not same_regime:
		return
	var left_volume := float(left.get("volume_db", -80.0))
	var right_volume := float(right.get("volume_db", -80.0))
	var transition := {
		"a_grid": left.get("grid", []),
		"b_grid": right.get("grid", []),
		"a_position": left.get("position", []),
		"b_position": right.get("position", []),
		"a_volume_db": left_volume,
		"b_volume_db": right_volume,
		"step_db": absf(right_volume - left_volume),
		"a_path_length": left.get("path_length", 0.0),
		"b_path_length": right.get("path_length", 0.0),
		"a_range_path_length": left.get("range_path_length", 0.0),
		"b_range_path_length": right.get("range_path_length", 0.0),
		"route": left.get("route_kind", ""),
	}
	same_regime_transitions.append(transition)
	var farther := (
		right
		if float(right.get("direct_distance", 0.0))
		> float(left.get("direct_distance", 0.0))
		else left
	)
	var nearer := left if farther == right else right
	if (
		float(farther.get("volume_db", -80.0))
		> float(nearer.get("volume_db", -80.0)) + 1.0
	):
		same_regime_rises.append(transition)


func _point_is_occupied(
	space_state: PhysicsDirectSpaceState3D,
	position: Vector3
) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space_state.intersect_point(query, 1).is_empty()


func _save_report(report: Dictionary) -> bool:
	var absolute_directory := ProjectSettings.globalize_path(REPORT_PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(absolute_directory) != OK:
		return false
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t", true, true))
	return true


func _finish(world: Node3D, service: ServerAcousticService) -> void:
	service.queue_free()
	world.queue_free()
	await process_frame
	if failure_count == 0:
		print("Dense tunnel acoustic tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Dense tunnel acoustic tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)


func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

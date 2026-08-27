extends SceneTree

const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const RADIO_DEFINITION_PATH := "res://resources/items/radios/portable_radio.tres"
const INDUSTRIAL_LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")

const REPORT_PATH := "res://tests/generated/acoustic_world_probe_snapshot.json"
const GRID_MIN_X := -25.0
const GRID_MAX_X := 31.0
const GRID_MIN_Z := -115.0
const GRID_MAX_Z := 175.0
const GRID_SPACING := 2.0
const LISTENER_HEIGHT := 1.7
const CONTINUOUS_SOURCE_ID := 91001
const FIRST_LISTENER_ID := 92000
const MAX_SERIALIZED_TRANSITIONS := 96
const UNEXPLAINED_RISE_DB := 0.75
# This broad diagnostic compares independent raw listener targets two metres apart, not a movement
# history. Allow the authored range-fade slope plus a bounded 3 dB for inverse-distance, guided, and
# diffuse-field decay. The centimetre audit owns the much stricter rendered-motion continuity rule.
const RADIO_MAX_DISTANCE := 42.0
const MAX_CLEAR_RAW_TARGET_STEP_DB := (
	AcousticPropagationGraph.MAX_RANGE_FADE_ATTENUATION_DB
	/ (1.0 - AcousticPropagationGraph.RANGE_FADE_EDGE_EASE_FRACTION)
	/ (RADIO_MAX_DISTANCE * AcousticPropagationGraph.RANGE_FADE_FRACTION)
	* GRID_SPACING
	+ 3.0
)

var failure_count := 0
var assertion_count := 0
var _radio_definition: RadioItemDefinition


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Autoload-backed server/item scripts must be loaded after project initialization.
	var world := (
		(load(SERVER_WORLD_PATH) as PackedScene).instantiate() as Node3D
	)
	_radio_definition = load(RADIO_DEFINITION_PATH) as RadioItemDefinition
	root.add_child(world)
	await physics_frame
	await process_frame

	var industrial_complex := world.get_node_or_null(
		"IndustrialAcousticComplex"
	) as Node3D
	var acoustic_service := ServerAcousticService.new()
	root.add_child(acoustic_service)
	acoustic_service.bind_world(world)
	await process_frame
	await physics_frame

	_expect(
		industrial_complex != null and acoustic_service.graph.probe_count() > 0,
		"the measurement grid uses the complete active server world and its baked probe graph"
	)
	if industrial_complex == null or acoustic_service.graph.probe_count() <= 0:
		_finish(world, acoustic_service)
		return

	var source_position := industrial_complex.to_global(
		INDUSTRIAL_LAYOUT.TUNNEL_CENTER + Vector3(0.0, LISTENER_HEIGHT, 0.0)
	)
	var south_mouth := industrial_complex.to_global(
		INDUSTRIAL_LAYOUT.TUNNEL_CENTER
		+ Vector3(0.0, LISTENER_HEIGHT, -INDUSTRIAL_LAYOUT.TUNNEL_LENGTH * 0.5)
	)
	var north_mouth := industrial_complex.to_global(
		INDUSTRIAL_LAYOUT.TUNNEL_CENTER
		+ Vector3(0.0, LISTENER_HEIGHT, INDUSTRIAL_LAYOUT.TUNNEL_LENGTH * 0.5)
	)
	var x_count := roundi((GRID_MAX_X - GRID_MIN_X) / GRID_SPACING) + 1
	var z_count := roundi((GRID_MAX_Z - GRID_MIN_Z) / GRID_SPACING) + 1
	var sample_count := x_count * z_count
	var samples: Array[Dictionary] = []
	samples.resize(sample_count)
	var space_state := world.get_world_3d().direct_space_state
	var valid_probe_count := 0
	var audible_probe_count := 0
	var unsupported_range_extension_count := 0

	for x_index: int in range(x_count):
		for z_index: int in range(z_count):
			var sample_index := x_index * z_count + z_index
			var listener_position := Vector3(
				GRID_MIN_X + float(x_index) * GRID_SPACING,
				LISTENER_HEIGHT,
				GRID_MIN_Z + float(z_index) * GRID_SPACING
			)
			var occupied := _point_is_occupied(space_state, listener_position)
			var sample := {
				"grid": [x_index, z_index],
				"position": _vector_array(listener_position),
				"occupied": occupied,
				"distance_to_source": listener_position.distance_to(source_position),
				"distance_to_south_mouth": listener_position.distance_to(south_mouth),
				"distance_to_north_mouth": listener_position.distance_to(north_mouth),
				"audible": false,
				"volume_db": -80.0,
			}
			if occupied:
				samples[sample_index] = sample
				continue

			valid_probe_count += 1
			var listener_id := FIRST_LISTENER_ID + sample_index
			var result := acoustic_service.calculate_listener_result(
				listener_id,
				listener_position,
				source_position,
				_radio_definition.maximum_hearing_distance,
				_radio_definition.source_modifier,
				1.0,
				false,
				[],
				CONTINUOUS_SOURCE_ID
			)
			var field := acoustic_service._fields_by_listener.get(
				listener_id
			) as AcousticPropagationField
			if field != null:
				acoustic_service.graph._update_listener_environment_sample(
					field,
					listener_position
				)
			var source_probe := acoustic_service.graph.find_nearest_probe(
				source_position
			)
			var direct_path: Dictionary = acoustic_service._sample_direct_path(
				listener_id,
				listener_position,
				source_position,
				[],
				CONTINUOUS_SOURCE_ID
			)
			var direct_path_is_clear := (
				bool(direct_path.get("available", false))
				and not bool(direct_path.get("blocked", false))
			)
			var shared_guided_strength := acoustic_service.graph._shared_guided_strength(
				listener_position,
				source_position,
				source_probe,
				field,
				direct_path_is_clear
			)
			var effective_max_distance := acoustic_service.graph.effective_hearing_distance(
				_radio_definition.maximum_hearing_distance,
				listener_position,
				source_position,
				field,
				direct_path_is_clear
			)
			var listener_guided_strength := (
				field.environment_guided_strength
				if field != null
				else 0.0
			)
			var range_extension_without_listener_guide := (
				effective_max_distance
				> _radio_definition.maximum_hearing_distance + 0.01
				and shared_guided_strength <= 0.0001
			)
			if range_extension_without_listener_guide:
				unsupported_range_extension_count += 1
			var modifier_ids: Array[String] = []
			for modifier_id: String in result.get(
				"modifier_ids",
				PackedStringArray()
			):
				modifier_ids.append(modifier_id)
			var audible := bool(result.get("audible", false))
			if audible:
				audible_probe_count += 1
			var apparent_position: Vector3 = result.get(
				"apparent_position",
				source_position
			)
			var band_gain: Vector3 = result.get("band_gain", Vector3.ZERO)
			sample.merge({
				"audible": audible,
				"volume_db": (
					float(result.get("volume_db", -80.0))
					+ _radio_definition.playback_volume_db
					if audible
					else -80.0
				),
				"propagation_volume_db": float(result.get("volume_db", -80.0)),
				"direct_distance": float(result.get("direct_distance", 0.0)),
				"path_length": float(result.get("path_length", 0.0)),
				"travel_delay_seconds": float(result.get("travel_delay_seconds", 0.0)),
				"apparent_position": _vector_array(apparent_position),
				"route_kind": str(result.get("route_kind", &"unknown")),
				"direct_path_blocked": bool(direct_path.get("blocked", false)),
				"direct_occlusion": float(direct_path.get("occlusion", 0.0)),
				"effective_max_distance": effective_max_distance,
				"range_extension_without_listener_guide": range_extension_without_listener_guide,
				"listener_guided_strength": listener_guided_strength,
				"shared_guided_strength": shared_guided_strength,
				"guided_gain_db": float(result.get("guided_propagation_gain_db", 0.0)),
				"diffuse_gain_db": float(result.get("diffuse_field_gain_db", 0.0)),
				"band_gain": _vector_array(band_gain),
				"environment_enclosure": float(result.get("environment_enclosure", 0.0)),
				"reverb_send": float(result.get("reverb_send", 0.0)),
				"source_reverb_spill_send": float(result.get("source_reverb_spill_send", 0.0)),
				"lowpass_hz": float(result.get("lowpass_hz", 20000.0)),
				"highpass_hz": float(result.get("highpass_hz", 20.0)),
				"modifier_ids": modifier_ids,
				"listener_environment_visible": (
					field.listener_probe_visibility_confirmed
					if field != null
					else false
				),
			}, true)
			samples[sample_index] = sample

	var transition_report := _measure_neighbor_transitions(
		samples,
		x_count,
		z_count
	)
	var report := {
		"schema_version": 1,
		"world_scene": "res://scenes/server/server_world.tscn",
		"sound": {
			"definition": _radio_definition.resource_path,
			"source_position": _vector_array(source_position),
			"base_max_distance": _radio_definition.maximum_hearing_distance,
			"playback_volume_db": _radio_definition.playback_volume_db,
		},
		"grid": {
			"min_x": GRID_MIN_X,
			"max_x": GRID_MAX_X,
			"min_z": GRID_MIN_Z,
			"max_z": GRID_MAX_Z,
			"listener_y": LISTENER_HEIGHT,
			"spacing": GRID_SPACING,
			"x_count": x_count,
			"z_count": z_count,
		},
		"landmarks": {
			"tunnel_south_mouth": _vector_array(south_mouth),
			"tunnel_north_mouth": _vector_array(north_mouth),
		},
		"summary": {
			"sample_count": sample_count,
			"valid_probe_count": valid_probe_count,
			"audible_probe_count": audible_probe_count,
			"occupied_probe_count": sample_count - valid_probe_count,
			"range_extension_without_listener_guide_count": unsupported_range_extension_count,
			"neighbor_transition_count": transition_report.get("transition_count", 0),
			"large_neighbor_jump_count": transition_report.get("large_jump_count", 0),
			"unexplained_farther_gain_count": transition_report.get("unexplained_rise_count", 0),
			"largest_neighbor_jump_db": transition_report.get("largest_jump_db", 0.0),
			"largest_unexplained_farther_gain_db": transition_report.get("largest_unexplained_rise_db", 0.0),
			"largest_clear_neighbor_step_db": transition_report.get("largest_clear_step_db", 0.0),
			"maximum_clear_raw_target_step_db": MAX_CLEAR_RAW_TARGET_STEP_DB,
		},
		"largest_neighbor_transitions": transition_report.get("largest_transitions", []),
		"largest_clear_neighbor_transitions": transition_report.get("largest_clear_transitions", []),
		"largest_unexplained_farther_gains": transition_report.get("largest_unexplained_rises", []),
		"samples": samples,
	}
	var report_saved := _save_report(report)
	_expect(report_saved, "the complete acoustic measurement field is serialized as JSON")
	_expect(
		sample_count > 1500 and valid_probe_count > 1200,
		"more than twelve hundred evenly spaced valid listener probes cover the active level"
	)
	_expect(
		unsupported_range_extension_count == 0,
		"tunnel range extension is limited to listeners supported by the tunnel or its mouth field"
	)
	_expect(
		int(transition_report.get("unexplained_rise_count", 0)) == 0,
		"a farther neighboring probe cannot get louder without a geometry or acoustic-regime change"
	)
	_expect(
		float(transition_report.get("largest_clear_step_db", INF))
		<= MAX_CLEAR_RAW_TARGET_STEP_DB,
		"clear direct-wave targets stay within the physical two-metre range and environment decay budget"
	)
	print(
		"Acoustic world probe report: %s (%d samples, %d unsupported range extensions, %d unexplained rises)"
		% [
			ProjectSettings.globalize_path(REPORT_PATH),
			sample_count,
			unsupported_range_extension_count,
			int(transition_report.get("unexplained_rise_count", 0)),
		]
	)
	_finish(world, acoustic_service)


func _measure_neighbor_transitions(
	samples: Array[Dictionary],
	x_count: int,
	z_count: int
) -> Dictionary:
	var transitions: Array[Dictionary] = []
	var unexplained_rises: Array[Dictionary] = []
	var clear_transitions: Array[Dictionary] = []
	var large_jump_count := 0
	var largest_clear_step_db := 0.0
	for x_index: int in range(x_count):
		for z_index: int in range(z_count):
			var sample_index := x_index * z_count + z_index
			if x_index + 1 < x_count:
				_append_transition(
					transitions,
					unexplained_rises,
					samples[sample_index],
					samples[(x_index + 1) * z_count + z_index]
				)
			if z_index + 1 < z_count:
				_append_transition(
					transitions,
					unexplained_rises,
					samples[sample_index],
					samples[sample_index + 1]
				)
	transitions.sort_custom(_higher_jump_first)
	unexplained_rises.sort_custom(_higher_rise_first)
	for transition: Dictionary in transitions:
		if float(transition.get("absolute_jump_db", 0.0)) >= 3.0:
			large_jump_count += 1
		if bool(transition.get("clear_continuous_field", false)):
			clear_transitions.append(transition)
			largest_clear_step_db = maxf(
				largest_clear_step_db,
				float(transition.get("absolute_jump_db", 0.0))
			)
	var largest_transitions := transitions.slice(
		0,
		mini(MAX_SERIALIZED_TRANSITIONS, transitions.size())
	)
	var largest_unexplained_rises := unexplained_rises.slice(
		0,
		mini(MAX_SERIALIZED_TRANSITIONS, unexplained_rises.size())
	)
	var largest_clear_transitions := clear_transitions.slice(
		0,
		mini(MAX_SERIALIZED_TRANSITIONS, clear_transitions.size())
	)
	return {
		"transition_count": transitions.size(),
		"large_jump_count": large_jump_count,
		"unexplained_rise_count": unexplained_rises.size(),
		"largest_jump_db": (
			float(transitions[0].get("absolute_jump_db", 0.0))
			if not transitions.is_empty()
			else 0.0
		),
		"largest_unexplained_rise_db": (
			float(unexplained_rises[0].get("farther_gain_db", 0.0))
			if not unexplained_rises.is_empty()
			else 0.0
		),
		"largest_clear_step_db": largest_clear_step_db,
		"largest_transitions": largest_transitions,
		"largest_clear_transitions": largest_clear_transitions,
		"largest_unexplained_rises": largest_unexplained_rises,
	}


func _append_transition(
	transitions: Array[Dictionary],
	unexplained_rises: Array[Dictionary],
	left: Dictionary,
	right: Dictionary
) -> void:
	if (
		bool(left.get("occupied", true))
		or bool(right.get("occupied", true))
		or not bool(left.get("audible", false))
		or not bool(right.get("audible", false))
	):
		return
	var left_volume := float(left.get("volume_db", -80.0))
	var right_volume := float(right.get("volume_db", -80.0))
	# "Farther" in this assertion is radial source distance. Baked path length is still serialized
	# and owns traveled spreading, but can grow while the listener physically approaches the source
	# (for example, by moving toward a different maze/tunnel opening). Calling that a distance-gain
	# violation inverted several legitimate pairs.
	var left_distance := float(left.get("distance_to_source", 0.0))
	var right_distance := float(right.get("distance_to_source", 0.0))
	var farther := right if right_distance > left_distance else left
	var nearer := left if right_distance > left_distance else right
	var farther_gain_db := (
		float(farther.get("volume_db", -80.0))
		- float(nearer.get("volume_db", -80.0))
	)
	# A radially farther point may legitimately own a shorter route through connected air. That is
	# precisely the geometry explanation this check promises to allow. Demand monotonicity only when
	# both radial source distance and traveled propagation distance increase together.
	var farther_path_is_not_shorter := (
		float(farther.get("path_length", 0.0))
		>= float(nearer.get("path_length", 0.0)) - 0.05
	)
	var left_guided_strength := float(left.get("listener_guided_strength", 0.0))
	var right_guided_strength := float(right.get("listener_guided_strength", 0.0))
	var guided_strength_max := maxf(left_guided_strength, right_guided_strength)
	var guided_strength_min := minf(left_guided_strength, right_guided_strength)
	var same_guided_lobe_band := (
		guided_strength_max <= 0.001
		or guided_strength_min / guided_strength_max >= 0.8
	)
	var same_regime: bool = (
		str(left.get("route_kind", "")) == str(right.get("route_kind", ""))
		and bool(left.get("direct_path_blocked", false))
		== bool(right.get("direct_path_blocked", false))
		and absf(
			float(left.get("direct_occlusion", 0.0))
			- float(right.get("direct_occlusion", 0.0))
		) < 0.05
		and absf(
			float(left.get("guided_gain_db", 0.0))
			- float(right.get("guided_gain_db", 0.0))
		) < 0.25
		and same_guided_lobe_band
		and absf(
			float(left.get("diffuse_gain_db", 0.0))
			- float(right.get("diffuse_gain_db", 0.0))
		) < 0.25
		and absf(
			float(left.get("environment_enclosure", 0.0))
			- float(right.get("environment_enclosure", 0.0))
		) < 0.12
		and left.get("modifier_ids", []) == right.get("modifier_ids", [])
		# Modifier IDs are intentionally deduplicated. Equal IDs therefore do not prove that two rays
		# crossed the same number of modular wall pieces; the rendered three-band response does.
		and _largest_band_response_step_db(left, right) < 1.0
		and absf(
			float(left.get("lowpass_hz", 20000.0))
			- float(right.get("lowpass_hz", 20000.0))
		) < 1.0
	)
	var clear_continuous_field: bool = (
		str(left.get("route_kind", "")) == "direct"
		and str(right.get("route_kind", "")) == "direct"
		and not bool(left.get("direct_path_blocked", false))
		and not bool(right.get("direct_path_blocked", false))
		and left.get("modifier_ids", []) == right.get("modifier_ids", [])
		and minf(
			float(left.get("distance_to_source", 0.0)),
			float(right.get("distance_to_source", 0.0))
		) >= 4.0
	)
	var transition := {
		"a_grid": left.get("grid", []),
		"b_grid": right.get("grid", []),
		"a_position": left.get("position", []),
		"b_position": right.get("position", []),
		"a_volume_db": left_volume,
		"b_volume_db": right_volume,
		"a_path_length": left.get("path_length", 0.0),
		"b_path_length": right.get("path_length", 0.0),
		"a_source_distance": left.get("distance_to_source", 0.0),
		"b_source_distance": right.get("distance_to_source", 0.0),
		"band_response_step_db": _largest_band_response_step_db(left, right),
		"absolute_jump_db": absf(right_volume - left_volume),
		"farther_gain_db": farther_gain_db,
		"farther_path_is_not_shorter": farther_path_is_not_shorter,
		"nearer_position": nearer.get("position", []),
		"farther_position": farther.get("position", []),
		"same_regime": same_regime,
		"clear_continuous_field": clear_continuous_field,
		"a_route": left.get("route_kind", ""),
		"b_route": right.get("route_kind", ""),
		"a_blocked": left.get("direct_path_blocked", false),
		"b_blocked": right.get("direct_path_blocked", false),
		"a_direct_occlusion": left.get("direct_occlusion", 0.0),
		"b_direct_occlusion": right.get("direct_occlusion", 0.0),
		"a_guided_strength": left.get("listener_guided_strength", 0.0),
		"b_guided_strength": right.get("listener_guided_strength", 0.0),
		"a_shared_guided_strength": left.get("shared_guided_strength", 0.0),
		"b_shared_guided_strength": right.get("shared_guided_strength", 0.0),
		"a_guided_gain_db": left.get("guided_gain_db", 0.0),
		"b_guided_gain_db": right.get("guided_gain_db", 0.0),
		"a_diffuse_gain_db": left.get("diffuse_gain_db", 0.0),
		"b_diffuse_gain_db": right.get("diffuse_gain_db", 0.0),
		"a_enclosure": left.get("environment_enclosure", 0.0),
		"b_enclosure": right.get("environment_enclosure", 0.0),
		"a_modifiers": left.get("modifier_ids", []),
		"b_modifiers": right.get("modifier_ids", []),
	}
	transitions.append(transition)
	if (
		same_regime
		and farther_path_is_not_shorter
		and farther_gain_db > UNEXPLAINED_RISE_DB
	):
		unexplained_rises.append(transition)


func _largest_band_response_step_db(left: Dictionary, right: Dictionary) -> float:
	var left_bands: Array = left.get("band_gain", [])
	var right_bands: Array = right.get("band_gain", [])
	if left_bands.size() < 3 or right_bands.size() < 3:
		return INF
	var largest_step_db := 0.0
	for band_index: int in range(3):
		largest_step_db = maxf(
			largest_step_db,
			absf(
				linear_to_db(maxf(float(left_bands[band_index]), 0.000001))
				- linear_to_db(maxf(float(right_bands[band_index]), 0.000001))
			)
		)
	return largest_step_db


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


func _finish(world: Node3D, acoustic_service: ServerAcousticService) -> void:
	acoustic_service.queue_free()
	world.queue_free()
	await process_frame
	if failure_count == 0:
		print("Acoustic world probe tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Acoustic world probe tests failed: %d/%d assertions"
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


func _higher_jump_first(left: Dictionary, right: Dictionary) -> bool:
	return float(left.get("absolute_jump_db", 0.0)) > float(
		right.get("absolute_jump_db", 0.0)
	)


func _higher_rise_first(left: Dictionary, right: Dictionary) -> bool:
	return float(left.get("farther_gain_db", 0.0)) > float(
		right.get("farther_gain_db", 0.0)
	)

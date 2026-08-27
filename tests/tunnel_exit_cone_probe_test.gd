extends SceneTree

const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const RADIO_DEFINITION_PATH := "res://resources/items/radios/portable_radio.tres"
const LAYOUT := preload(
	"res://scripts/world/industrial_acoustic_complex_layout.gd"
)

const REPORT_STEM := "res://tests/generated/tunnel_exit_cone_report"
const FIELD_STEM := "res://tests/generated/tunnel_exit_cone_field"
const LISTENER_HEIGHT := 1.7
const GRID_SPACING := 0.2
const X_RADIUS := 18.0
const OUTSIDE_DISTANCE := 24.0
const SOURCE_END_INSET := 4.0
const CROSS_SECTION_SPACING := 2.0
const FIRST_LISTENER_ID := 4_100_000
const CONTINUOUS_SOURCE_ID := 4_190_001
const BYTES_PER_SAMPLE := 16
const MAX_CENTERLINE_STEP_DB := 1.5
const MIN_FAR_MOUTH_STRENGTH := 0.01
const MIN_CONE_WIDTH_GROWTH_2_TO_6_M := 1.0
const MIN_CONE_WIDTH_GROWTH_6_TO_12_M := 1.5

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var label := OS.get_environment("SCAVANGE_TUNNEL_CONE_LABEL").strip_edges()
	if not label.is_empty() and not label.begins_with("_"):
		label = "_" + label
	var report_path := REPORT_STEM + label + ".json"
	var field_path := FIELD_STEM + label + ".bin"
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
	var mouth_probe_index := _find_probe(
		service.graph,
		&"industrial_comfort_tunnel_north_outside"
	)
	_expect(
		complex != null
		and radio != null
		and mouth_probe_index >= 0,
		"cone audit uses the active modular tunnel, radio, and far-side mouth probe"
	)
	if complex == null or radio == null or mouth_probe_index < 0:
		await _finish(world, service)
		return

	var source_position := complex.to_global(
		LAYOUT.TUNNEL_CENTER
		+ Vector3(
			0.0,
			LISTENER_HEIGHT,
			-LAYOUT.TUNNEL_LENGTH * 0.5 + SOURCE_END_INSET
		)
	)
	var mouth_position := complex.to_global(
		LAYOUT.TUNNEL_CENTER
		+ Vector3(0.0, LISTENER_HEIGHT, LAYOUT.TUNNEL_LENGTH * 0.5)
	)
	var x_count := roundi(X_RADIUS * 2.0 / GRID_SPACING) + 1
	var outward_count := roundi(OUTSIDE_DISTANCE / GRID_SPACING) + 1
	var sample_count := x_count * outward_count
	var field_file := FileAccess.open(field_path, FileAccess.WRITE)
	_expect(field_file != null, "cone audit opens its compact full-field log")
	if field_file == null:
		await _finish(world, service)
		return

	var mouth_response := service.graph.environment_response(mouth_probe_index)
	var mouth_guidance := float(mouth_response.get("guided_propagation", 0.0))
	var space_state := world.get_world_3d().direct_space_state
	var cross_sections: Array[Dictionary] = []
	var width_by_distance: Dictionary[float, float] = {}
	var center_strength_by_distance: Dictionary[float, float] = {}
	var center_range_fade_by_distance: Dictionary[float, float] = {}
	var previous_center_volume := -80.0
	var previous_center_audible := false
	var maximum_centerline_step_db := 0.0
	var maximum_centerline_step: Dictionary = {}
	var valid_count := 0
	var audible_count := 0
	var center_x_index := x_count >> 1
	var cross_section_interval := maxi(
		roundi(CROSS_SECTION_SPACING / GRID_SPACING),
		1
	)
	for outward_index: int in range(outward_count):
		var outside_m := float(outward_index) * GRID_SPACING
		var row_mouth_strengths := PackedFloat32Array()
		row_mouth_strengths.resize(x_count)
		var row_listener_strengths := PackedFloat32Array()
		row_listener_strengths.resize(x_count)
		var row_volumes := PackedFloat32Array()
		row_volumes.resize(x_count)
		row_volumes.fill(-80.0)
		var row_flags := PackedByteArray()
		row_flags.resize(x_count)
		var row_probe_ids := PackedStringArray()
		row_probe_ids.resize(x_count)
		var center_breakdown: Dictionary = {}
		for x_index: int in range(x_count):
			var x_offset := -X_RADIUS + float(x_index) * GRID_SPACING
			var listener_position := mouth_position + Vector3(
				x_offset,
				0.0,
				outside_m
			)
			var occupied := _point_is_occupied(space_state, listener_position)
			var mouth_strength := mouth_guidance * float(service.graph.call(
				"_guided_environment_influence",
				mouth_probe_index,
				listener_position
			))
			var volume_db := -80.0
			var listener_guided_strength := 0.0
			var audible := false
			var route_code := 0
			var listener_probe := -1
			if not occupied:
				valid_count += 1
				var sample_index := outward_index * x_count + x_index
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
				if x_index == center_x_index:
					center_breakdown = {
						"path_length": float(result.get("path_length", 0.0)),
						"range_path_length": float(
							result.get("range_path_length", 0.0)
						),
						"geometric_spreading_db": float(
							result.get("geometric_spreading_db", 0.0)
						),
						"range_fade_volume_db": float(
							result.get("range_fade_volume_db", 0.0)
						),
						"guided_propagation_gain_db": float(
							result.get("guided_propagation_gain_db", 0.0)
						),
					}
				audible = bool(result.get("audible", false))
				if audible:
					audible_count += 1
					volume_db = (
						float(result.get("volume_db", -80.0))
						+ radio.playback_volume_db
					)
				route_code = _route_code(StringName(str(
					result.get("route_kind", &"none")
				)))
				var source_probe := int(result.get("source_probe_index", -1))
				var field := service._fields_by_listener.get(
					listener_id
				) as AcousticPropagationField
				if field != null:
					listener_guided_strength = field.environment_guided_strength
					if source_probe >= 0 and source_probe < field.origin_probes.size():
						listener_probe = field.origin_probes[source_probe]
			row_mouth_strengths[x_index] = mouth_strength
			row_listener_strengths[x_index] = listener_guided_strength
			row_volumes[x_index] = volume_db
			row_flags[x_index] = (
				(1 if occupied else 0)
				| (2 if audible else 0)
			)
			row_probe_ids[x_index] = str(service.graph.get_probe_id(listener_probe))
			field_file.store_float(volume_db)
			field_file.store_float(listener_guided_strength)
			field_file.store_float(mouth_strength)
			field_file.store_8(row_flags[x_index])
			field_file.store_8(route_code)
			field_file.store_16(clampi(listener_probe + 1, 0, 65535))

		var center_strength := float(row_mouth_strengths[center_x_index])
		var half_width := _relative_half_width(
			row_mouth_strengths,
			center_strength,
			X_RADIUS,
			GRID_SPACING
		)
		width_by_distance[_distance_key(outside_m)] = half_width
		center_strength_by_distance[_distance_key(outside_m)] = center_strength
		center_range_fade_by_distance[_distance_key(outside_m)] = float(
			center_breakdown.get("range_fade_volume_db", 0.0)
		)
		var center_volume := float(row_volumes[center_x_index])
		var center_audible := bool(row_flags[center_x_index] & 2)
		if previous_center_audible and center_audible:
			var step_db := absf(center_volume - previous_center_volume)
			if step_db > maximum_centerline_step_db:
				maximum_centerline_step_db = step_db
				maximum_centerline_step = {
					"near_distance": outside_m - GRID_SPACING,
					"far_distance": outside_m,
					"near_volume_db": previous_center_volume,
					"far_volume_db": center_volume,
					"step_db": step_db,
				}
		previous_center_volume = center_volume
		previous_center_audible = center_audible
		if outward_index % cross_section_interval == 0:
			cross_sections.append({
				"outside_distance": outside_m,
				"mouth_center_strength": center_strength,
				"mouth_half_strength_width": half_width,
				"center_volume_db": center_volume,
				"center_breakdown": center_breakdown,
				"samples": _cross_section_samples(
					row_volumes,
					row_listener_strengths,
					row_mouth_strengths,
					row_flags,
					row_probe_ids
				),
			})
	field_file.close()

	var width_2m := _sample_at(width_by_distance, 2.0)
	var width_6m := _sample_at(width_by_distance, 6.0)
	var width_12m := _sample_at(width_by_distance, 12.0)
	var strength_12m := _sample_at(center_strength_by_distance, 12.0)
	var strength_20m := _sample_at(center_strength_by_distance, 20.0)
	var range_fade_12m := _sample_at(center_range_fade_by_distance, 12.0)
	var report := {
		"schema_version": 1,
		"world_scene": SERVER_WORLD_PATH,
		"sound": {
			"definition": radio.resource_path,
			"source_position": _vector_array(source_position),
			"playback_volume_db": radio.playback_volume_db,
		},
		"mouth": {
			"probe_id": str(service.graph.get_probe_id(mouth_probe_index)),
			"position": _vector_array(mouth_position),
			"guided_propagation": mouth_guidance,
		},
		"grid": {
			"spacing": GRID_SPACING,
			"x_radius": X_RADIUS,
			"outside_distance": OUTSIDE_DISTANCE,
			"x_count": x_count,
			"outward_count": outward_count,
			"sample_count": sample_count,
			"binary_bytes_per_sample": BYTES_PER_SAMPLE,
			"binary_fields": [
				"volume_db:float32",
				"listener_guided_strength:float32",
				"mouth_lobe_strength:float32",
				"flags:uint8",
				"route:uint8",
				"listener_probe_plus_one:uint16",
			],
		},
		"summary": {
			"valid_sample_count": valid_count,
			"audible_sample_count": audible_count,
			"maximum_centerline_step_db": maximum_centerline_step_db,
			"maximum_centerline_step": maximum_centerline_step,
			"mouth_half_strength_width_2m": width_2m,
			"mouth_half_strength_width_6m": width_6m,
			"mouth_half_strength_width_12m": width_12m,
			"mouth_center_strength_12m": strength_12m,
			"mouth_center_strength_20m": strength_20m,
			"range_fade_volume_db_12m": range_fade_12m,
			"runtime_seconds": (
				float(Time.get_ticks_msec() - started_msec) * 0.001
			),
		},
		"cross_sections": cross_sections,
	}
	_expect(_save_report(report_path, report), "cone cross-sections serialize as readable JSON")
	_expect(
		FileAccess.get_file_as_bytes(field_path).size()
		== sample_count * BYTES_PER_SAMPLE,
		"the binary log contains every small-probe field measurement"
	)
	_expect(
		maximum_centerline_step_db <= MAX_CENTERLINE_STEP_DB,
		"far-side tunnel volume has no sudden centerline transition"
	)
	_expect(
		absf(range_fade_12m) < 0.05,
		"ordinary aperture radiation owns the useful field before the final range tail"
	)
	_expect(
		strength_12m > MIN_FAR_MOUTH_STRENGTH
		and strength_20m > MIN_FAR_MOUTH_STRENGTH,
		"mouth radiation decays continuously instead of ending at a spill-box boundary"
	)
	_expect(
		width_6m >= width_2m + MIN_CONE_WIDTH_GROWTH_2_TO_6_M
		and width_12m >= width_6m + MIN_CONE_WIDTH_GROWTH_6_TO_12_M,
		"the far-side half-strength footprint widens with distance like an aperture lobe"
	)
	print(
		"Tunnel exit cone: %d samples, center step %.3f dB, widths %.1f/%.1f/%.1f m"
		% [
			sample_count,
			maximum_centerline_step_db,
			width_2m,
			width_6m,
			width_12m,
		]
	)
	await _finish(world, service)


func _cross_section_samples(
	volumes: PackedFloat32Array,
	listener_strengths: PackedFloat32Array,
	mouth_strengths: PackedFloat32Array,
	flags: PackedByteArray,
	probe_ids: PackedStringArray
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.resize(volumes.size())
	for index: int in range(volumes.size()):
		result[index] = {
			"x": -X_RADIUS + float(index) * GRID_SPACING,
			"volume_db": volumes[index],
			"listener_guided_strength": listener_strengths[index],
			"mouth_lobe_strength": mouth_strengths[index],
			"occupied": bool(flags[index] & 1),
			"audible": bool(flags[index] & 2),
			"listener_probe_id": probe_ids[index],
		}
	return result


static func _relative_half_width(
	strengths: PackedFloat32Array,
	center_strength: float,
	x_radius: float,
	spacing: float
) -> float:
	if center_strength <= 0.000001:
		return 0.0
	var threshold := center_strength * 0.5
	var width := 0.0
	for index: int in range(strengths.size()):
		if strengths[index] >= threshold:
			width = maxf(width, absf(-x_radius + float(index) * spacing))
	return width


static func _distance_key(distance: float) -> float:
	return snappedf(distance, GRID_SPACING)


static func _sample_at(values: Dictionary[float, float], distance: float) -> float:
	return float(values.get(_distance_key(distance), 0.0))


static func _route_code(route: StringName) -> int:
	match route:
		&"direct":
			return 1
		&"graph":
			return 2
		&"parallel":
			return 3
		&"transmitted":
			return 4
		_:
			return 0


static func _find_probe(graph: AcousticPropagationGraph, probe_id: StringName) -> int:
	for probe_index: int in range(graph.probe_count()):
		if graph.get_probe_id(probe_index) == probe_id:
			return probe_index
	return -1


static func _point_is_occupied(
	space_state: PhysicsDirectSpaceState3D,
	position: Vector3
) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space_state.intersect_point(query, 1).is_empty()


static func _save_report(path: String, report: Dictionary) -> bool:
	var directory := DirAccess.open("res://")
	if directory == null:
		return false
	directory.make_dir_recursive(path.get_base_dir().trim_prefix("res://"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return true


static func _vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error("FAIL: " + message)


func _finish(world: Node, service: Node) -> void:
	if is_instance_valid(service):
		service.queue_free()
	if is_instance_valid(world):
		world.queue_free()
	await process_frame
	if failure_count == 0:
		print("Tunnel exit cone tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Tunnel exit cone tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

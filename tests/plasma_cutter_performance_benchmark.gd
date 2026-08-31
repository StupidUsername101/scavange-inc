extends SceneTree

## Continuous-stroke benchmark for the shipped plasma cutter. Unlike the general SDF microbench,
## this deliberately grows one connected cut across a real wall so structural scans, worker-job
## coalescing, ArrayMesh commits, and Jolt collision replacement are all represented.

const CUTTER := preload("res://resources/items/tools/plasma_cutter_standard.tres")
const PULSE_COUNT := 52
const WALL_SIZE := Vector3(4.0, 3.0, 0.45)
const WALL_VOXEL_SIZE := 0.06
const WALL_BRICK_CELLS := 16


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var texture := DestructionMaterialRegistry.profile_for(&"concrete")
	var raw_profile := _profile_field(texture)
	var runtime_root := Node3D.new()
	root.add_child(runtime_root)
	var visual_profile := await _profile_runtime_volume(runtime_root, texture, false)
	var collision_profile := await _profile_runtime_volume(runtime_root, texture, true)
	print("PLASMA CUTTER PERFORMANCE BENCHMARK")
	_print_profile("raw field", raw_profile)
	_print_profile("visual runtime", visual_profile)
	_print_profile("visual + Jolt", collision_profile)
	if not _profiles_are_valid(raw_profile, visual_profile, collision_profile):
		push_error("Plasma cutter performance fixture diverged from its expected complete cut")
		quit(1)
		return
	quit(0)


func _profile_field(texture: DestructionTextureDefinition) -> Dictionary:
	var field := SparseSdfVolumeData.new().configure(
		WALL_SIZE,
		WALL_VOXEL_SIZE,
		WALL_BRICK_CELLS,
		texture.material_index,
		4.0
	)
	field.structural_anchor_faces = SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y
	var timings := PackedInt64Array()
	var scans := PackedInt64Array()
	var full_scans := 0
	var changed_pulses := 0
	var detached_components := 0
	var peak_breakdown: Dictionary = {}
	for pulse_index: int in range(PULSE_COUNT):
		var local_position := _stroke_position(pulse_index)
		var event := _cutter_event(pulse_index, local_position)
		var started_usec := Time.get_ticks_usec()
		var result := field.apply_damage_event(
			local_position,
			Vector3.FORWARD,
			Vector3.BACK,
			event,
			texture
		)
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		timings.append(elapsed_usec)
		if peak_breakdown.is_empty() or elapsed_usec > int(peak_breakdown.get("pulse_usec", 0)):
			peak_breakdown = _fragment_breakdown(result, elapsed_usec)
		var scan_cells := int(result.get("fragment_scan_cells", 0))
		scans.append(scan_cells)
		if scan_cells >= _logical_cell_count(field):
			full_scans += 1
		if bool(result.get("geometry_changed", false)):
			changed_pulses += 1
		detached_components += int(result.get("detached_component_count", 0))
	return {
		"timings": timings,
		"scans": scans,
		"full_scans": full_scans,
		"changed_pulses": changed_pulses,
		"detached_components": detached_components,
		"peak_breakdown": peak_breakdown,
		"state": field.debug_state(),
	}


func _profile_runtime_volume(
	parent: Node3D,
	texture: DestructionTextureDefinition,
	with_collision: bool
) -> Dictionary:
	var volume := DestructibleVolume3D.new()
	volume.name = "PlasmaCutterBenchmark_%s" % ["Collision" if with_collision else "Visual"]
	volume.volume_id = StringName(volume.name.to_snake_case())
	volume.authoritative = false
	volume.create_collision = with_collision
	volume.volume_size = WALL_SIZE
	volume.voxel_size = WALL_VOXEL_SIZE
	volume.brick_cells = WALL_BRICK_CELLS
	volume.destruction_texture = texture.duplicate(true)
	volume.structural_anchor_faces = SdfStructuralFragmenter.ANCHOR_NEGATIVE_Y
	volume.position = Vector3.ZERO
	parent.add_child(volume)
	var timings := PackedInt64Array()
	var scans := PackedInt64Array()
	var full_scans := 0
	var detached_components := 0
	var peak_breakdown: Dictionary = {}
	for pulse_index: int in range(PULSE_COUNT):
		var local_position := _stroke_position(pulse_index)
		var event := _cutter_event(
			pulse_index,
			volume.to_global(local_position)
		)
		var started_usec := Time.get_ticks_usec()
		var result := volume.apply_replicated_damage_event(event, volume.field.revision)
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		timings.append(elapsed_usec)
		if peak_breakdown.is_empty() or elapsed_usec > int(peak_breakdown.get("pulse_usec", 0)):
			peak_breakdown = _fragment_breakdown(result, elapsed_usec)
		var scan_cells := int(result.get("fragment_scan_cells", 0))
		scans.append(scan_cells)
		if scan_cells >= _logical_cell_count(volume.field):
			full_scans += 1
		detached_components += int(result.get("detached_component_count", 0))
		# The shipped cadence is about five 60 Hz frames. Let the real worker/main-thread pipeline
		# advance at that rate instead of unrealistically forcing a synchronous rebuild per pulse.
		for _frame: int in range(5):
			await process_frame
	var flush_started_usec := Time.get_ticks_usec()
	volume.flush_pending_rebuilds()
	var flush_usec := Time.get_ticks_usec() - flush_started_usec
	var state := volume.debug_state()
	volume.queue_free()
	await process_frame
	return {
		"timings": timings,
		"scans": scans,
		"full_scans": full_scans,
		"changed_pulses": int(state.get("committed_events", 0)),
		"detached_components": detached_components,
		"peak_breakdown": peak_breakdown,
		"flush_usec": flush_usec,
		"state": state,
	}


func _stroke_position(pulse_index: int) -> Vector3:
	var progress := float(pulse_index) / float(PULSE_COUNT - 1)
	# Begin/end beyond the side faces so this is a complete structural cut, not merely a scar.
	return Vector3(lerpf(-2.08, 2.08, progress), 0.0, WALL_SIZE.z * 0.5)


func _cutter_event(event_index: int, world_position: Vector3) -> DamageEvent:
	var event_id := 900000 + event_index
	return DamageEvent.from_dict({
		"event_id": event_id,
		"sequence": event_id,
		"source_kind": &"plasma_cutter_benchmark",
		"source_id": 1,
		"world_position": world_position,
		"normal": Vector3.BACK,
		"direction": Vector3.FORWARD,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": float(CUTTER.cut_radius),
		"length": float(CUTTER.cut_depth),
		"energy": float(CUTTER.destruction_energy),
		"impulse": 0.0,
		"penetration": float(CUTTER.cut_depth),
		"heat": float(CUTTER.heat_energy),
		"damage_tags": PackedStringArray(["blade", "heat"]),
		"seed": event_id,
	})


func _print_profile(label: String, profile: Dictionary) -> void:
	var timings: PackedInt64Array = profile.get("timings", PackedInt64Array())
	var scans: PackedInt64Array = profile.get("scans", PackedInt64Array())
	var split_index := maxi(timings.size() / 3, 1)
	var early := timings.slice(0, split_index)
	var late := timings.slice(maxi(timings.size() - split_index, 0), timings.size())
	var state: Dictionary = profile.get("state", {})
	print("  ", label, ":")
	print("    pulse:       ", _timing_summary(timings))
	print("    early third: ", _timing_summary(early))
	print("    late third:  ", _timing_summary(late))
	print(
		"    structural: scan median=%d cells max=%d full=%d/%d detached=%d"
		% [
			_median(scans), _maximum(scans), int(profile.get("full_scans", 0)),
			timings.size(), int(profile.get("detached_components", 0)),
		]
	)
	print(
		"    runtime:     changed=%d rebuild_avg=%.0fus rebuild_max=%dus flush=%dus stale=%d"
		% [
			int(profile.get("changed_pulses", 0)),
			float(state.get("rebuild_average_usec", 0.0)),
			int(state.get("rebuild_max_usec", 0)),
			int(profile.get("flush_usec", 0)),
			int(state.get("discarded_stale_jobs", 0)),
		]
	)
	print("    peak split:  ", profile.get("peak_breakdown", {}))


func _fragment_breakdown(result: Dictionary, pulse_usec: int) -> Dictionary:
	return {
		"pulse_usec": pulse_usec,
		"fragment_total": int(result.get("fragment_total_usec", 0)),
		"mapping": int(result.get("fragment_mapping_usec", 0)),
		"grouping": int(result.get("fragment_grouping_usec", 0)),
		"mesh": int(result.get("fragment_mesh_usec", 0)),
		"erase": int(result.get("fragment_erase_usec", 0)),
	}


func _profiles_are_valid(
	raw_profile: Dictionary,
	visual_profile: Dictionary,
	collision_profile: Dictionary
) -> bool:
	var expected_checksum := int((raw_profile.get("state", {}) as Dictionary).get("checksum", -1))
	for profile: Dictionary in [raw_profile, visual_profile, collision_profile]:
		var timings: PackedInt64Array = profile.get("timings", PackedInt64Array())
		var state: Dictionary = profile.get("state", {})
		var field_state: Dictionary = state.get("field", state)
		if (
			timings.size() != PULSE_COUNT
			or int(profile.get("changed_pulses", 0)) != PULSE_COUNT
			or int(profile.get("detached_components", 0)) != 1
			or int(profile.get("full_scans", 0)) != 1
			or int(field_state.get("checksum", -2)) != expected_checksum
			or not bool(field_state.get("native_backend", false))
		):
			print(
				"    invalid profile: samples=%d changed=%d detached=%d full=%d checksum=%d/%d native=%s"
				% [
					timings.size(), int(profile.get("changed_pulses", 0)),
					int(profile.get("detached_components", 0)), int(profile.get("full_scans", 0)),
					int(field_state.get("checksum", -2)), expected_checksum,
					str(field_state.get("native_backend", false)),
				]
			)
			return false
	return true


func _timing_summary(values: PackedInt64Array) -> String:
	if values.is_empty():
		return "no samples"
	var ordered := values.duplicate()
	ordered.sort()
	var p95_index := mini(ceili(float(ordered.size()) * 0.95) - 1, ordered.size() - 1)
	return "median=%dus p95=%dus max=%dus" % [
		ordered[ordered.size() / 2], ordered[p95_index], ordered[ordered.size() - 1]
	]


func _median(values: PackedInt64Array) -> int:
	if values.is_empty():
		return 0
	var ordered := values.duplicate()
	ordered.sort()
	return ordered[ordered.size() / 2]


func _maximum(values: PackedInt64Array) -> int:
	var maximum := 0
	for value: int in values:
		maximum = maxi(maximum, value)
	return maximum


func _logical_cell_count(field: SparseSdfVolumeData) -> int:
	return (
		maxi(ceili(field.size.x / field.voxel_size), 1)
		* maxi(ceili(field.size.y / field.voxel_size), 1)
		* maxi(ceili(field.size.z / field.voxel_size), 1)
	)

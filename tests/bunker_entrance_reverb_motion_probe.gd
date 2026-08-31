extends SceneTree

## Stateful entrance-crossing audit for the two large four-speaker bunkers.
##
## Static listener grids cannot expose a stale room response. This probe advances one persistent
## listener through each real doorway at the production 20 Hz snapshot cadence, preserving the
## server's field/dezipper state and advancing the real client renderer at 60 Hz between snapshots.
## The serialized trace identifies whether a post-exit rise originates in propagation,
## shared-program composition, or client presentation.

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const REPORT_PATH := "res://tests/generated/bunker_entrance_reverb_motion_report.json"
const SNAPSHOT_SECONDS := 0.05
const CLIENT_FRAME_SECONDS := 1.0 / 60.0
const LISTENER_HEIGHT := 1.7
const START_INSIDE_METERS := 7.0
const END_OUTSIDE_METERS := 10.0
const SPEEDS_MPS := [2.4, 5.2, 8.5, 14.0]
const EXIT_PATHS := [
	{"name": "straight", "start_z": 0.0, "end_z": 0.0},
	{"name": "north_diagonal", "start_z": -4.0, "end_z": 7.0},
	{"name": "south_diagonal", "start_z": 4.0, "end_z": -7.0},
]
const OUTSIDE_EPSILON := 0.02
const TRANSITION_ANALYSIS_OUTSIDE_METERS := 3.0
const MIN_VOLUME_DB := -80.0
const MAX_NEAR_EXIT_LATE_RISE_DB := 0.10
const MAX_NEAR_EXIT_WET_TO_DIRECT_RISE_DB := 0.25
const MAX_NEAR_EXIT_EARLY_REFLECTION_RISE_DB := 1.0
# Shared-program spatial gain is expected to settle to 99 percent of each authoritative update
# within the 50 ms snapshot period. Across the complete -80..18 dB presentation range, the largest
# possible one-period remainder is therefore below one decibel. Unlike the rise checks above, this
# bound catches a monotonically fading but spatially stale indoor field.
const MAX_WET_TO_DIRECT_TRACKING_ERROR_DB := 1.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var server := root.get_node_or_null("Server")
	if server == null:
		_fail("server autoload unavailable")
		return
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	await physics_frame
	var world := server.get("server_world") as Node3D
	var complex := world.get_node_or_null("IndustrialAcousticComplex") as Node3D
	var service := server.get("acoustic_service") as ServerAcousticService
	if complex == null or service == null:
		_fail("industrial acoustic complex unavailable")
		return
	var bunkers: Array[Dictionary] = [
		{
			"name": "large",
			"center": LAYOUT.LARGE_BUNKER_CENTER,
			"cluster": complex.get_node_or_null("LargeBunkerSpeakerArray"),
		},
		{
			"name": "valve",
			"center": LAYOUT.VALVE_BUNKER_CENTER,
			"cluster": complex.get_node_or_null("ValveReferenceBunkerSpeakerArray"),
		},
	]
	var report_runs: Array[Dictionary] = []
	var listener_id := 8_420_000
	var complete := true
	for bunker: Dictionary in bunkers:
		var cluster := bunker.get("cluster") as ServerSpeakerCluster
		if cluster == null:
			complete = false
			continue
		cluster.set_control_volume_ratio(1.0)
		if not cluster.apply_fieldlink_command(null, &"play_track", {"track_index": 0}):
			complete = false
			continue
		for path: Dictionary in EXIT_PATHS:
			for speed: float in SPEEDS_MPS:
				listener_id += 1
				report_runs.append(_measure_exit_run(
					str(bunker["name"]),
					bunker["center"],
					cluster,
					service,
					listener_id,
					speed,
					path
				))
				service.forget_listener(listener_id)

	var report := {
		"schema_version": 1,
		"purpose": "Stateful 20 Hz large-bunker doorway reverb transition audit",
		"snapshot_seconds": SNAPSHOT_SECONDS,
		"client_frame_seconds": CLIENT_FRAME_SECONDS,
		"speeds_mps": SPEEDS_MPS,
		"exit_paths": EXIT_PATHS,
		"bunker_width_m": LAYOUT.LARGE_BUNKER_WIDTH,
		"wall_thickness_m": LAYOUT.LARGE_BUNKER_WALL_THICKNESS,
		"runs": report_runs,
	}
	var acceptance := _acceptance_results(report_runs)
	report["acceptance"] = acceptance
	var saved := _save_json(REPORT_PATH, report)
	for run: Dictionary in report_runs:
		var summary: Dictionary = run.get("summary", {})
		print(
			"%s %s exit %.1f m/s: late target/client/early rises %.3f/%.3f/%.3f dB, ratio rise %.3f dB, tracking %.3f dB"
			% [
				run.get("bunker", "missing"),
				run.get("path", "missing"),
				float(run.get("speed_mps", 0.0)),
				float(summary.get("late_target_post_exit_rise_db", INF)),
				float(summary.get("client_late_post_exit_rise_db", INF)),
				float(summary.get("early_reflection_post_exit_rise_db", INF)),
				float(summary.get("wet_to_direct_post_exit_rise_db", INF)),
				float(summary.get("maximum_wet_to_direct_tracking_error_db", INF)),
			]
		)
	if (
		complete
		and saved
		and report_runs.size()
		== bunkers.size() * SPEEDS_MPS.size() * EXIT_PATHS.size()
		and bool(acceptance.get("passed", false))
	):
		print("Bunker entrance reverb motion probe completed: %d runs" % report_runs.size())
		quit(0)
	else:
		_fail("one or more bunker motion traces could not be captured")


func _measure_exit_run(
	bunker_name: String,
	bunker_center: Vector3,
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService,
	listener_id: int,
	speed_mps: float,
	path: Dictionary
) -> Dictionary:
	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	renderer._ensure_pool()
	var half_width := LAYOUT.LARGE_BUNKER_WIDTH * 0.5
	var start := Vector3(
		half_width - START_INSIDE_METERS,
		LISTENER_HEIGHT,
		float(path.get("start_z", 0.0))
	)
	var end := Vector3(
		half_width + END_OUTSIDE_METERS,
		LISTENER_HEIGHT,
		float(path.get("end_z", 0.0))
	)
	var sample_distance := speed_mps * SNAPSHOT_SECONDS
	var sample_count := ceili(start.distance_to(end) / sample_distance) + 1
	var trace: Array[Dictionary] = []
	var runtime_initialized := false
	for sample_index: int in range(sample_count):
		var ratio := float(sample_index) / float(maxi(sample_count - 1, 1))
		var path_position := start.lerp(end, ratio)
		var x_offset := path_position.x
		var local_position := bunker_center + path_position
		var listener_position := cluster.get_parent_node_3d().global_transform * local_position
		var raw_states: Dictionary = {}
		cluster.append_listener_states(
			raw_states,
			listener_id,
			listener_position,
			service
		)
		var packets: Array[Dictionary] = []
		for state: Dictionary in raw_states.values():
			packets.append(state.duplicate(false))
		renderer._prepare_shared_program_mix(packets)
		var group_id := (
			int(packets[0].get("shared_program_group_id", -1))
			if not packets.is_empty()
			else -1
		)
		var group_slot := renderer._shared_program_group_slot(group_id)
		var target: Dictionary = (
			renderer._shared_program_target_packets[group_slot]
			if group_slot >= 0
			else {}
		)
		var late_target_db := float(target.get("late_field_volume_db", MIN_VOLUME_DB))
		for packet: Dictionary in packets:
			var item_id := int(packet.get("item_id", -1))
			var slot_index := int(renderer._slot_by_item_id.get(item_id, -1))
			if slot_index < 0:
				for candidate_index: int in range(renderer._slot_item_ids.size()):
					if renderer._slot_item_ids[candidate_index] < 0:
						slot_index = candidate_index
						renderer._bind_slot(slot_index, item_id)
						break
			if slot_index < 0:
				continue
			renderer._route_slot_to_shared_program(slot_index, group_id)
			var direct_target_db := float(packet.get("volume_db", MIN_VOLUME_DB))
			renderer._target_volumes_db[slot_index] = direct_target_db
			renderer._effect_target_packets[slot_index] = packet
			if not runtime_initialized:
				renderer._players[slot_index].volume_db = direct_target_db
		if not runtime_initialized:
			if group_slot >= 0:
				var initial_direct_db := (
					renderer._shared_program_target_direct_volumes_db[group_slot]
				)
				var initial_ratio_db := late_target_db - initial_direct_db
				renderer._shared_program_players[group_slot].volume_db = (
					initial_direct_db
				)
				renderer._shared_program_presented_wet_to_direct_db[group_slot] = (
					initial_ratio_db
				)
				renderer._shared_program_ratio_initialized[group_slot] = 1
				renderer._shared_program_racks[group_slot].set_presentation_gain_db(
					initial_ratio_db
				)
			runtime_initialized = true
		else:
			var remaining := SNAPSHOT_SECONDS
			while remaining > 0.000001:
				var frame_delta := minf(remaining, CLIENT_FRAME_SECONDS)
				renderer._process(frame_delta)
				remaining -= frame_delta
		var client_direct_power := 0.0
		for packet: Dictionary in packets:
			var slot_index := int(renderer._slot_by_item_id.get(
				int(packet.get("item_id", -1)),
				-1
			))
			if slot_index >= 0:
				client_direct_power += pow(
					10.0,
					renderer._players[slot_index].volume_db / 10.0
				)
		var client_late_db := (
			(
				renderer._shared_program_players[group_slot].volume_db
				+ renderer._shared_program_racks[group_slot].get_presentation_gain_db()
			)
			if group_slot >= 0
			else MIN_VOLUME_DB
		)
		trace.append({
			"time_seconds": float(sample_index) * SNAPSHOT_SECONDS,
			"x_offset_m": x_offset,
			"outside_m": x_offset - half_width,
			"emitter_count": packets.size(),
			"raw_group_level_db": _combined_energy_db(raw_states),
			"raw_early_reflection_level_db": _combined_early_reflection_db(raw_states),
			"render_direct_level_db": _combined_packet_energy_db(packets),
			"mean_enclosure": _power_weighted_mean(raw_states, &"environment_enclosure"),
			"mean_reverb_send": _power_weighted_mean(raw_states, &"reverb_send"),
			"mean_diffuse_support": _power_weighted_mean(raw_states, &"diffuse_field_support"),
			"late_target_db": late_target_db,
			"late_target_send": float(target.get("reverb_send", 0.0)),
			"late_target_room_size": float(target.get("reverb_room_size", 0.0)),
			"client_late_db": client_late_db,
			"client_direct_level_db": (
				10.0 * log(maxf(client_direct_power, 0.000000000001)) / log(10.0)
			),
		})
	var summary := _summarize_trace(trace)
	renderer.reset_session()
	renderer.free()
	return {
		"bunker": bunker_name,
		"track_path": cluster.current_song_path,
		"control_volume_ratio": cluster.get_control_volume_ratio(),
		"playback_volume_db": cluster.playback_volume_db,
		"path": str(path.get("name", "unnamed")),
		"exit_angle_degrees": rad_to_deg(atan2(
			end.z - start.z,
			end.x - start.x
		)),
		"speed_mps": speed_mps,
		"sample_distance_m": sample_distance,
		"summary": summary,
		"trace": trace,
	}


func _summarize_trace(trace: Array[Dictionary]) -> Dictionary:
	var first_outside_index := -1
	for sample_index: int in range(trace.size()):
		if float(trace[sample_index].get("outside_m", -INF)) >= OUTSIDE_EPSILON:
			first_outside_index = sample_index
			break
	if first_outside_index < 0:
		return {}
	var target_min_before_peak := INF
	var client_min_before_peak := INF
	var target_rise := 0.0
	var client_rise := 0.0
	var target_peak_outside := 0.0
	var client_peak_outside := 0.0
	var early_min_before_peak := INF
	var ratio_min_before_peak := INF
	var early_rise := 0.0
	var ratio_rise := 0.0
	var maximum_ratio_tracking_error := 0.0
	var maximum_stale_wet_excess := 0.0
	var minimum_emitter_count := 4
	for sample_index: int in range(first_outside_index, trace.size()):
		var sample: Dictionary = trace[sample_index]
		var target_wet_to_direct_db := (
			float(sample.get("late_target_db", MIN_VOLUME_DB))
			- float(sample.get("render_direct_level_db", MIN_VOLUME_DB))
		)
		var presented_wet_to_direct_db := (
			float(sample.get("client_late_db", MIN_VOLUME_DB))
			- float(sample.get("client_direct_level_db", MIN_VOLUME_DB))
		)
		var tracking_error := (
			presented_wet_to_direct_db - target_wet_to_direct_db
		)
		maximum_ratio_tracking_error = maxf(
			maximum_ratio_tracking_error,
			absf(tracking_error)
		)
		maximum_stale_wet_excess = maxf(
			maximum_stale_wet_excess,
			tracking_error
		)
		if (
			float(sample.get("outside_m", INF))
			> TRANSITION_ANALYSIS_OUTSIDE_METERS
		):
			continue
		var target_db := float(sample.get("late_target_db", MIN_VOLUME_DB))
		var client_db := float(sample.get("client_late_db", MIN_VOLUME_DB))
		var early_db := float(sample.get("raw_early_reflection_level_db", MIN_VOLUME_DB))
		var wet_to_direct_db := (
			client_db - float(sample.get("client_direct_level_db", MIN_VOLUME_DB))
		)
		target_min_before_peak = minf(target_min_before_peak, target_db)
		client_min_before_peak = minf(client_min_before_peak, client_db)
		early_min_before_peak = minf(early_min_before_peak, early_db)
		ratio_min_before_peak = minf(ratio_min_before_peak, wet_to_direct_db)
		minimum_emitter_count = mini(
			minimum_emitter_count,
			int(sample.get("emitter_count", 0))
		)
		var target_candidate := target_db - target_min_before_peak
		var client_candidate := client_db - client_min_before_peak
		early_rise = maxf(early_rise, early_db - early_min_before_peak)
		ratio_rise = maxf(ratio_rise, wet_to_direct_db - ratio_min_before_peak)
		if target_candidate > target_rise:
			target_rise = target_candidate
			target_peak_outside = float(sample.get("outside_m", 0.0))
		if client_candidate > client_rise:
			client_rise = client_candidate
			client_peak_outside = float(sample.get("outside_m", 0.0))
	return {
		"first_outside_index": first_outside_index,
		"first_outside_target_db": trace[first_outside_index].get("late_target_db", MIN_VOLUME_DB),
		"first_outside_client_db": trace[first_outside_index].get("client_late_db", MIN_VOLUME_DB),
		"late_target_post_exit_rise_db": target_rise,
		"client_late_post_exit_rise_db": client_rise,
		"late_target_peak_outside_m": target_peak_outside,
		"client_late_peak_outside_m": client_peak_outside,
		"early_reflection_post_exit_rise_db": early_rise,
		"wet_to_direct_post_exit_rise_db": ratio_rise,
		"maximum_wet_to_direct_tracking_error_db": maximum_ratio_tracking_error,
		"maximum_stale_wet_excess_db": maximum_stale_wet_excess,
		"minimum_near_exit_emitter_count": minimum_emitter_count,
	}


func _acceptance_results(runs: Array[Dictionary]) -> Dictionary:
	var maximum_target_rise := 0.0
	var maximum_client_rise := 0.0
	var maximum_ratio_rise := 0.0
	var maximum_early_rise := 0.0
	var maximum_ratio_tracking_error := 0.0
	var maximum_stale_wet_excess := 0.0
	var all_emitters_present := not runs.is_empty()
	for run: Dictionary in runs:
		var summary: Dictionary = run.get("summary", {})
		maximum_target_rise = maxf(
			maximum_target_rise,
			float(summary.get("late_target_post_exit_rise_db", INF))
		)
		maximum_client_rise = maxf(
			maximum_client_rise,
			float(summary.get("client_late_post_exit_rise_db", INF))
		)
		maximum_ratio_rise = maxf(
			maximum_ratio_rise,
			float(summary.get("wet_to_direct_post_exit_rise_db", INF))
		)
		maximum_early_rise = maxf(
			maximum_early_rise,
			float(summary.get("early_reflection_post_exit_rise_db", INF))
		)
		maximum_ratio_tracking_error = maxf(
			maximum_ratio_tracking_error,
			float(summary.get("maximum_wet_to_direct_tracking_error_db", INF))
		)
		maximum_stale_wet_excess = maxf(
			maximum_stale_wet_excess,
			float(summary.get("maximum_stale_wet_excess_db", INF))
		)
		all_emitters_present = (
			all_emitters_present
			and int(summary.get("minimum_near_exit_emitter_count", 0)) == 4
		)
	return {
		"passed": (
			all_emitters_present
			and maximum_target_rise <= MAX_NEAR_EXIT_LATE_RISE_DB
			and maximum_client_rise <= MAX_NEAR_EXIT_LATE_RISE_DB
			and maximum_ratio_rise <= MAX_NEAR_EXIT_WET_TO_DIRECT_RISE_DB
			and maximum_early_rise <= MAX_NEAR_EXIT_EARLY_REFLECTION_RISE_DB
			and maximum_ratio_tracking_error
			<= MAX_WET_TO_DIRECT_TRACKING_ERROR_DB
		),
		"all_emitters_present": all_emitters_present,
		"maximum_late_target_rise_db": maximum_target_rise,
		"maximum_client_late_rise_db": maximum_client_rise,
		"maximum_wet_to_direct_ratio_rise_db": maximum_ratio_rise,
		"maximum_early_reflection_rise_db": maximum_early_rise,
		"maximum_wet_to_direct_tracking_error_db": maximum_ratio_tracking_error,
		"maximum_stale_wet_excess_db": maximum_stale_wet_excess,
		"limits_db": {
			"late_rise": MAX_NEAR_EXIT_LATE_RISE_DB,
			"wet_to_direct_ratio_rise": MAX_NEAR_EXIT_WET_TO_DIRECT_RISE_DB,
			"early_reflection_rise": MAX_NEAR_EXIT_EARLY_REFLECTION_RISE_DB,
			"wet_to_direct_tracking_error": MAX_WET_TO_DIRECT_TRACKING_ERROR_DB,
		},
	}


func _combined_energy_db(states: Dictionary) -> float:
	var power_sum := 0.0
	for state: Dictionary in states.values():
		power_sum += pow(10.0, float(state.get("volume_db", MIN_VOLUME_DB)) / 10.0)
	return 10.0 * log(maxf(power_sum, 0.000000000001)) / log(10.0)


func _combined_packet_energy_db(packets: Array[Dictionary]) -> float:
	var power_sum := 0.0
	for packet: Dictionary in packets:
		power_sum += pow(10.0, float(packet.get("volume_db", MIN_VOLUME_DB)) / 10.0)
	return 10.0 * log(maxf(power_sum, 0.000000000001)) / log(10.0)


func _combined_early_reflection_db(states: Dictionary) -> float:
	var reflected_power_sum := 0.0
	for state: Dictionary in states.values():
		var source_power := pow(
			10.0,
			float(state.get("volume_db", MIN_VOLUME_DB)) / 10.0
		)
		var taps: Variant = state.get("early_reflections", [])
		if not taps is Array:
			continue
		for tap: Variant in taps:
			if tap is Dictionary:
				var gain := clampf(float((tap as Dictionary).get("gain", 0.0)), 0.0, 1.0)
				reflected_power_sum += source_power * gain * gain
	return 10.0 * log(maxf(reflected_power_sum, 0.000000000001)) / log(10.0)


func _power_weighted_mean(states: Dictionary, key: StringName) -> float:
	var power_sum := 0.0
	var value_sum := 0.0
	for state: Dictionary in states.values():
		var power := pow(10.0, float(state.get("volume_db", MIN_VOLUME_DB)) / 10.0)
		power_sum += power
		value_sum += power * float(state.get(key, 0.0))
	return value_sum / maxf(power_sum, 0.000000000001)


func _save_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t"))
	return true


func _fail(message: String) -> void:
	push_error("Bunker entrance reverb motion probe: %s" % message)
	quit(1)

extends SceneTree

## Static quarter-metre pressure audit for the garage PA bunker.
##
## Every point receives a fresh listener field so row traversal order and temporal smoothing cannot
## manufacture the measured shape. The generated JSON retains the complete authoritative and
## post-shared-mix packets, plus compact summaries of the dry/late split, route balance, spectrum,
## and adjacent-point continuity. It also gates the direct/parallel room-energy regression exposed
## by this field: changing early-route classification must not attach the same late field twice.

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const REPORT_PATH := "res://tests/generated/bunker_quarter_meter_mix_report.json"
const SUMMARY_PATH := "res://tests/generated/bunker_quarter_meter_mix_summary.json"
const SPACING := 0.25
const LISTENER_HEIGHT := 1.7
const INTERIOR_MIN_X := -8.5
const INTERIOR_MAX_X := 8.5
const INTERIOR_MIN_Z := -6.5
const INTERIOR_MAX_Z := 6.5
const APRON_MIN_X := -11.0
const APRON_MAX_X := 11.0
const APRON_MIN_Z := -10.0
const APRON_MAX_Z := -6.75
const FIRST_LISTENER_ID := 7_250_000
const PROGRESS_INTERVAL := 500
const MIN_DB := -80.0
const POWER_FLOOR := 0.000000000001
const MIN_DIRECT_PARALLEL_TRANSITIONS := 100
const MAX_STABLE_BLOCKED_LOUDER_RATIO := 0.25
const MAX_STABLE_BLOCKED_GAIN_P90_DB := 0.25
const MAX_STABLE_BLOCKED_GAIN_DB := 0.5
const MAX_INTERIOR_MIX_STEP_P99_DB := 0.75
const STABLE_DIFFUSE_FIELD_STEP_DB := 0.25

var _samples: Array[Dictionary] = []
var _metric_grids: Dictionary[String, Dictionary] = {}
var _stats: Dictionary[String, Dictionary] = {}
var _neighbor_steps: Dictionary[String, Dictionary] = {}
var _route_counts: Dictionary[String, int] = {}
var _worst_edges: Array[Dictionary] = []
var _direct_parallel_blocked_gain_db: Array[float] = []
var _stable_direct_parallel_blocked_gain_db: Array[float] = []
var _solid_sample_count := 0
var _silent_sample_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var server := root.get_node_or_null("Server")
	if server == null:
		push_error("Bunker 25 cm probe: server autoload unavailable")
		quit(1)
		return
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	await physics_frame
	var world := server.get("server_world") as Node3D
	var cluster := world.get_node_or_null("SpeakerClusterDemo") as ServerSpeakerCluster
	var service := server.get("acoustic_service") as ServerAcousticService
	if cluster == null or service == null:
		push_error("Bunker 25 cm probe: production cluster or acoustic service unavailable")
		quit(1)
		return

	# The field is a maximum-output stress measurement. A common gain does not alter the dry/late
	# ratio, but it prevents hearing-range cutoffs from hiding weak exterior contributions.
	cluster.set_control_volume_ratio(1.0)
	cluster.apply_fieldlink_command(null, &"play_track", {"track_index": 0})
	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	renderer._ensure_pool()
	var space_state := world.get_world_3d().direct_space_state

	_stats["all_walkable"] = _new_metric_accumulator()
	_stats["interior"] = _new_metric_accumulator()
	_stats["front_apron"] = _new_metric_accumulator()
	_neighbor_steps["all_walkable"] = _new_neighbor_accumulator()
	_neighbor_steps["interior"] = _new_neighbor_accumulator()
	_neighbor_steps["front_apron"] = _new_neighbor_accumulator()

	var listener_id := FIRST_LISTENER_ID
	listener_id = _measure_region(
		"interior",
		INTERIOR_MIN_X,
		INTERIOR_MAX_X,
		INTERIOR_MIN_Z,
		INTERIOR_MAX_Z,
		listener_id,
		cluster,
		service,
		renderer,
		space_state
	)
	_measure_region(
		"front_apron",
		APRON_MIN_X,
		APRON_MAX_X,
		APRON_MIN_Z,
		APRON_MAX_Z,
		listener_id,
		cluster,
		service,
		renderer,
		space_state
	)

	var transition_summary := _direct_parallel_transition_summary()
	var acceptance := _acceptance_results(transition_summary)
	var report := {
		"schema_version": 1,
		"purpose": "Static 25 cm bunker PA dry/late/route mixture audit",
		"measurement_notes": [
			"One horizontal listener plane at 1.7 m; this is not a 3D impulse-response scan.",
			"Every point has a fresh listener ID and is forgotten immediately.",
			"dry_to_late_db is renderer dry energy divided by renderer late-field feed energy; it is not a standards-compliant measured DRR.",
			"route_direct_to_graph_db is a propagation-route proxy; graph energy includes routed/diffracted support rather than only physical reverberation.",
			"Samples intersecting a collision body remain in the raw file but are excluded from walkable summaries and neighbor statistics.",
		],
		"layout": {
			"world_position": _vector_array(LAYOUT.WORLD_POSITION),
			"size_m": [LAYOUT.WIDTH, LAYOUT.HEIGHT, LAYOUT.DEPTH],
			"door_center_x": LAYOUT.DOOR_CENTER_X,
			"door_width_m": LAYOUT.DOOR_WIDTH,
			"speakers": _json_safe(LAYOUT.speaker_descriptors()),
		},
		"playback": {
			"track_path": cluster.current_song_path,
			"control_volume_ratio": cluster.get_control_volume_ratio(),
			"playback_volume_db": cluster.playback_volume_db,
			"control_volume_db": cluster.control_volume_db,
		},
		"grid": {
			"spacing_m": SPACING,
			"listener_height_m": LISTENER_HEIGHT,
			"interior_bounds_local": [
				INTERIOR_MIN_X, INTERIOR_MAX_X, INTERIOR_MIN_Z, INTERIOR_MAX_Z,
			],
			"front_apron_bounds_local": [
				APRON_MIN_X, APRON_MAX_X, APRON_MIN_Z, APRON_MAX_Z,
			],
		},
		"summary": {
			"sample_count": _samples.size(),
			"solid_overlap_sample_count": _solid_sample_count,
			"silent_sample_count": _silent_sample_count,
			"regions": _summarize_accumulators(_stats),
			"neighbor_continuity": _summarize_neighbors(_neighbor_steps),
			"route_counts": _route_counts,
			"worst_neighbor_edges": _worst_edges,
			"direct_parallel_transitions": transition_summary,
		},
		"acceptance": acceptance,
		"sample_schema": {
			"mix": "Post shared-program dry/late energy and three-band pressure estimates.",
			"raw_emitters": "Complete server-authoritative per-cabinet packets before client mix preparation.",
			"render_emitters": "Complete per-cabinet packets after shared-program dry normalization.",
			"shared_late_field": "Complete shared wet-only late-field target packet.",
		},
		"samples": _samples,
		"elapsed_seconds": float(Time.get_ticks_msec() - started_msec) * 0.001,
	}
	var saved := _save_json(REPORT_PATH, report)
	var compact_summary := report.duplicate(false)
	compact_summary.erase("samples")
	saved = _save_json(SUMMARY_PATH, compact_summary) and saved
	var all_summary: Dictionary = (
		(report["summary"] as Dictionary)["regions"] as Dictionary
	)["all_walkable"]
	var continuity: Dictionary = (
		(report["summary"] as Dictionary)["neighbor_continuity"] as Dictionary
	)["all_walkable"]
	print(
		"Bunker 25 cm field: %d samples (%d solid, %d silent), mix %.2f..%.2f dB, dry/late median %.2f dB, late p10/p90 %.1f%%/%.1f%%, worst 25 cm mix step %.2f dB, %.2fs"
		% [
			_samples.size(),
			_solid_sample_count,
			_silent_sample_count,
			float(all_summary.get("mix_energy_db_min", MIN_DB)),
			float(all_summary.get("mix_energy_db_max", MIN_DB)),
			float(all_summary.get("dry_to_late_db_p50", 0.0)),
			100.0 * float(all_summary.get("late_fraction_p10", 0.0)),
			100.0 * float(all_summary.get("late_fraction_p90", 0.0)),
			float(continuity.get("mix_step_db_max", 0.0)),
			float(report["elapsed_seconds"]),
		]
	)
	var accepted := _report_acceptance(acceptance)
	renderer.reset_session()
	renderer.free()
	quit(0 if saved and accepted else 1)


func _measure_region(
	region: String,
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float,
	listener_id: int,
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService,
	renderer: RadioAudioRenderer,
	space_state: PhysicsDirectSpaceState3D
) -> int:
	var x_count := roundi((max_x - min_x) / SPACING) + 1
	var z_count := roundi((max_z - min_z) / SPACING) + 1
	var grid: Dictionary = {}
	_metric_grids[region] = grid
	for z_index: int in range(z_count):
		var local_z := min_z + float(z_index) * SPACING
		for x_index: int in range(x_count):
			var local_x := min_x + float(x_index) * SPACING
			var local_position := Vector3(local_x, LISTENER_HEIGHT, local_z)
			var world_position := cluster.global_transform * local_position
			var overlaps := _collision_overlaps(space_state, world_position)
			var raw_states: Dictionary = {}
			cluster.append_listener_states(
				raw_states,
				listener_id,
				world_position,
				service
			)
			var render_packets: Array[Dictionary] = []
			for raw_state: Dictionary in raw_states.values():
				render_packets.append(raw_state.duplicate(false))
			renderer._prepare_shared_program_mix(render_packets)
			var shared_target := _shared_target(renderer)
			var mix := _mix_metrics(raw_states, render_packets, shared_target)
			var walkable := overlaps.is_empty()
			if not walkable:
				_solid_sample_count += 1
			if raw_states.is_empty():
				_silent_sample_count += 1
			var sample := {
				"index": _samples.size(),
				"region": region,
				"grid_index": [x_index, z_index],
				"local_position": _vector_array(local_position),
				"world_position": _vector_array(world_position),
				"walkable": walkable,
				"collision_overlaps": overlaps,
				"mix": mix,
				"raw_emitters": _json_safe(raw_states),
				"render_emitters": _json_safe(render_packets),
				"shared_late_field": _json_safe(shared_target),
			}
			_samples.append(sample)
			var grid_key := Vector2i(x_index, z_index)
			grid[grid_key] = {
				"walkable": walkable,
				"sample_index": int(sample["index"]),
				"position": local_position,
				"mix": mix,
				"raw_emitters": raw_states,
			}
			if walkable and not raw_states.is_empty():
				_accumulate_metric(_stats[region], mix)
				_accumulate_metric(_stats["all_walkable"], mix)
				_compare_neighbor(region, grid_key, Vector2i(x_index - 1, z_index))
				_compare_neighbor(region, grid_key, Vector2i(x_index, z_index - 1))
			for state: Dictionary in raw_states.values():
				var route := str(state.get("route_kind", &"missing"))
				_route_counts[route] = int(_route_counts.get(route, 0)) + 1
			service.forget_listener(listener_id)
			listener_id += 1
			if _samples.size() % PROGRESS_INTERVAL == 0:
				print("Bunker 25 cm field: measured %d points" % _samples.size())
	return listener_id


func _shared_target(renderer: RadioAudioRenderer) -> Dictionary:
	var slot := renderer._shared_program_group_slot(LAYOUT.SHARED_PROGRAM_GROUP_ID)
	if slot < 0:
		return {}
	return renderer._shared_program_target_packets[slot].duplicate(true)


func _mix_metrics(
	raw_states: Dictionary,
	render_packets: Array[Dictionary],
	shared_target: Dictionary
) -> Dictionary:
	var raw_power := 0.0
	var dry_power := 0.0
	var late_power := 0.0
	var route_direct_power := 0.0
	var route_graph_power := 0.0
	var parallel_route_count := 0
	var maximum_parallel_route_gain_db := 0.0
	var maximum_diffuse_field_gain_db := 0.0
	var maximum_direct_occlusion := 0.0
	var reverb_decay_seconds_sum := 0.0
	var environment_enclosure_sum := 0.0
	var raw_parameter_count := 0
	var nearest_speaker_distance := INF
	var dry_band_amplitude := Vector3.ZERO
	for state: Dictionary in raw_states.values():
		var state_power := _db_to_power(float(state.get("volume_db", MIN_DB)))
		var reverb_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(
			float(state.get("reverb_send", 0.0))
		)
		raw_power += state_power
		dry_power += state_power * reverb_mix.x * reverb_mix.x
		late_power += state_power * reverb_mix.y * reverb_mix.y
		var route_kind := str(state.get("route_kind", &"missing"))
		var direct_weight := (
			1.0
			if route_kind == "direct"
			else clampf(
				float(state.get("route_direct_energy_weight", 0.0)), 0.0, 1.0
			)
		)
		var graph_weight := (
			0.0
			if route_kind == "direct"
			else 1.0
			if route_kind in ["graph", "transmitted"]
			else clampf(
				float(state.get("route_graph_energy_weight", 0.0)), 0.0, 1.0
			)
		)
		route_direct_power += state_power * direct_weight
		route_graph_power += state_power * graph_weight
		if route_kind == "parallel":
			parallel_route_count += 1
		maximum_parallel_route_gain_db = maxf(
			maximum_parallel_route_gain_db,
			float(state.get("parallel_route_gain_db", 0.0))
		)
		maximum_diffuse_field_gain_db = maxf(
			maximum_diffuse_field_gain_db,
			float(state.get("diffuse_field_gain_db", 0.0))
		)
		maximum_direct_occlusion = maxf(
			maximum_direct_occlusion,
			float(state.get("direct_occlusion", 0.0))
		)
		reverb_decay_seconds_sum += float(state.get("reverb_decay_seconds", 0.0))
		environment_enclosure_sum += float(state.get("environment_enclosure", 0.0))
		raw_parameter_count += 1
		nearest_speaker_distance = minf(
			nearest_speaker_distance,
			float(state.get("direct_distance", INF))
		)
	for packet: Dictionary in render_packets:
		var amplitude := db_to_linear(float(packet.get("volume_db", MIN_DB)))
		var band_gain: Vector3 = packet.get("band_gain", Vector3.ONE)
		dry_band_amplitude += amplitude * band_gain
	var dry_band_power := Vector3(
		dry_band_amplitude.x * dry_band_amplitude.x,
		dry_band_amplitude.y * dry_band_amplitude.y,
		dry_band_amplitude.z * dry_band_amplitude.z
	)
	var late_band_gain: Vector3 = shared_target.get("band_gain", Vector3.ONE)
	var target_late_power := _db_to_power(
		float(shared_target.get("late_field_volume_db", MIN_DB))
	)
	var late_band_power := Vector3(
		target_late_power * late_band_gain.x * late_band_gain.x,
		target_late_power * late_band_gain.y * late_band_gain.y,
		target_late_power * late_band_gain.z * late_band_gain.z
	)
	var combined_band_power := dry_band_power + late_band_power
	var total_split_power := dry_power + late_power
	return {
		"active_speaker_count": raw_states.size(),
		"raw_arrival_energy_db": _power_to_db(raw_power),
		"mix_energy_db": _power_to_db(total_split_power),
		"dry_energy_db": _power_to_db(dry_power),
		"late_energy_db": _power_to_db(late_power),
		"shared_target_late_energy_db": _power_to_db(target_late_power),
		"late_target_error_db": (
			_power_to_db(target_late_power) - _power_to_db(late_power)
		),
		"dry_to_late_db": _power_ratio_db(dry_power, late_power),
		"late_fraction": late_power / maxf(total_split_power, POWER_FLOOR),
		"route_direct_to_graph_db": _power_ratio_db(
			route_direct_power, route_graph_power
		),
		"route_direct_fraction": route_direct_power / maxf(
			route_direct_power + route_graph_power, POWER_FLOOR
		),
		"parallel_route_count": parallel_route_count,
		"maximum_parallel_route_gain_db": maximum_parallel_route_gain_db,
		"maximum_diffuse_field_gain_db": maximum_diffuse_field_gain_db,
		"maximum_direct_occlusion": maximum_direct_occlusion,
		"mean_reverb_decay_seconds": (
			reverb_decay_seconds_sum / float(maxi(raw_parameter_count, 1))
		),
		"mean_environment_enclosure": (
			environment_enclosure_sum / float(maxi(raw_parameter_count, 1))
		),
		"nearest_speaker_distance_m": (
			nearest_speaker_distance if is_finite(nearest_speaker_distance) else -1.0
		),
		"dry_band_db": _band_db_array(dry_band_power),
		"late_band_db": _band_db_array(late_band_power),
		"combined_band_db": _band_db_array(combined_band_power),
		"shared_reverb_send": float(shared_target.get("reverb_send", 0.0)),
		"shared_reverb_room_size": float(
			shared_target.get("reverb_room_size", 0.0)
		),
		"shared_reverb_damping": float(
			shared_target.get("reverb_damping", 0.0)
		),
		"shared_reverb_predelay_msec": float(
			shared_target.get("reverb_predelay_msec", 0.0)
		),
		"shared_reverb_predelay_feedback": float(
			shared_target.get("reverb_predelay_feedback", 0.0)
		),
		"shared_reverb_hipass": float(
			shared_target.get("reverb_hipass", 0.0)
		),
	}


func _collision_overlaps(
	space_state: PhysicsDirectSpaceState3D,
	position: Vector3
) -> Array[String]:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = position
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var names: Array[String] = []
	for hit: Dictionary in space_state.intersect_point(query, 16):
		var collider := hit.get("collider") as Node
		var name := str(collider.get_path()) if collider != null else str(hit.get("rid"))
		if not name in names:
			names.append(name)
	names.sort()
	return names


func _compare_neighbor(region: String, current_key: Vector2i, neighbor_key: Vector2i) -> void:
	var grid: Dictionary = _metric_grids[region]
	if not grid.has(neighbor_key):
		return
	var current: Dictionary = grid[current_key]
	var neighbor: Dictionary = grid[neighbor_key]
	if not bool(neighbor.get("walkable", false)):
		return
	var current_mix: Dictionary = current["mix"]
	var neighbor_mix: Dictionary = neighbor["mix"]
	if region == "interior":
		_accumulate_direct_parallel_transitions(
			current["raw_emitters"],
			neighbor["raw_emitters"]
		)
	var edge := {
		"region": region,
		"from_sample": int(neighbor["sample_index"]),
		"to_sample": int(current["sample_index"]),
		"from_local": _vector_array(neighbor["position"]),
		"to_local": _vector_array(current["position"]),
		"mix_step_db": absf(
			float(current_mix["mix_energy_db"])
			- float(neighbor_mix["mix_energy_db"])
		),
		"dry_step_db": absf(
			float(current_mix["dry_energy_db"])
			- float(neighbor_mix["dry_energy_db"])
		),
		"late_step_db": absf(
			float(current_mix["late_energy_db"])
			- float(neighbor_mix["late_energy_db"])
		),
		"dry_to_late_step_db": absf(
			float(current_mix["dry_to_late_db"])
			- float(neighbor_mix["dry_to_late_db"])
		),
		"route_balance_step_db": absf(
			float(current_mix["route_direct_to_graph_db"])
			- float(neighbor_mix["route_direct_to_graph_db"])
		),
		"largest_band_step_db": _largest_band_step(
			current_mix["combined_band_db"], neighbor_mix["combined_band_db"]
		),
	}
	_accumulate_neighbor(_neighbor_steps[region], edge)
	_accumulate_neighbor(_neighbor_steps["all_walkable"], edge)
	_insert_worst_edge(edge)


func _accumulate_direct_parallel_transitions(
	current_emitters: Dictionary,
	neighbor_emitters: Dictionary
) -> void:
	for emitter_id: Variant in current_emitters:
		if not neighbor_emitters.has(emitter_id):
			continue
		var current: Dictionary = current_emitters[emitter_id]
		var neighbor: Dictionary = neighbor_emitters[emitter_id]
		var current_route := str(current.get("route_kind", &"missing"))
		var neighbor_route := str(neighbor.get("route_kind", &"missing"))
		if not (
			current_route == "direct" and neighbor_route == "parallel"
			or current_route == "parallel" and neighbor_route == "direct"
		):
			continue
		var direct := current if current_route == "direct" else neighbor
		var blocked := current if current_route == "parallel" else neighbor
		var blocked_gain_db := (
			float(blocked.get("volume_db", MIN_DB))
			- float(direct.get("volume_db", MIN_DB))
		)
		_direct_parallel_blocked_gain_db.append(blocked_gain_db)
		var diffuse_step_db := absf(
			float(blocked.get("diffuse_field_level_db", MIN_DB))
			- float(direct.get("diffuse_field_level_db", MIN_DB))
		)
		if diffuse_step_db <= STABLE_DIFFUSE_FIELD_STEP_DB:
			_stable_direct_parallel_blocked_gain_db.append(blocked_gain_db)


func _direct_parallel_transition_summary() -> Dictionary:
	return {
		"scope": "Walkable adjacent samples inside the bunker interior.",
		"all": _signed_distribution(_direct_parallel_blocked_gain_db),
		"stable_diffuse_field": _signed_distribution(
			_stable_direct_parallel_blocked_gain_db
		),
		"stable_diffuse_field_threshold_db": STABLE_DIFFUSE_FIELD_STEP_DB,
		"positive_value_semantics": (
			"The obstructed parallel side is louder than the adjacent clear/direct side."
		),
	}


func _signed_distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "positive_count": 0, "positive_ratio": 0.0}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var positive_count := 0
	for value: float in sorted:
		if value > 0.0:
			positive_count += 1
	return {
		"count": sorted.size(),
		"min_db": float(sorted.front()),
		"p10_db": _percentile(sorted, 0.10),
		"p50_db": _percentile(sorted, 0.50),
		"p90_db": _percentile(sorted, 0.90),
		"p99_db": _percentile(sorted, 0.99),
		"max_db": float(sorted.back()),
		"positive_count": positive_count,
		"positive_ratio": float(positive_count) / float(sorted.size()),
	}


func _acceptance_results(transition_summary: Dictionary) -> Dictionary:
	var stable: Dictionary = transition_summary["stable_diffuse_field"]
	var interior_neighbors := _summarize_neighbors({
		"interior": _neighbor_steps["interior"],
	})["interior"] as Dictionary
	return {
		"no_silent_samples": _silent_sample_count == 0,
		"topology_exercised": int(stable.get("count", 0))
		>= MIN_DIRECT_PARALLEL_TRANSITIONS,
		"blocked_louder_ratio_bounded": (
			float(stable.get("positive_ratio", 1.0))
			<= MAX_STABLE_BLOCKED_LOUDER_RATIO
		),
		"blocked_gain_p90_bounded": (
			float(stable.get("p90_db", INF))
			<= MAX_STABLE_BLOCKED_GAIN_P90_DB
		),
		"blocked_gain_max_bounded": (
			float(stable.get("max_db", INF)) <= MAX_STABLE_BLOCKED_GAIN_DB
		),
		"interior_mix_p99_continuous": (
			float(interior_neighbors.get("mix_step_db_p99", INF))
			<= MAX_INTERIOR_MIX_STEP_P99_DB
		),
		"thresholds": {
			"minimum_stable_transition_count": MIN_DIRECT_PARALLEL_TRANSITIONS,
			"maximum_blocked_louder_ratio": MAX_STABLE_BLOCKED_LOUDER_RATIO,
			"maximum_blocked_gain_p90_db": MAX_STABLE_BLOCKED_GAIN_P90_DB,
			"maximum_blocked_gain_db": MAX_STABLE_BLOCKED_GAIN_DB,
			"maximum_interior_mix_step_p99_db": MAX_INTERIOR_MIX_STEP_P99_DB,
		},
	}


func _report_acceptance(acceptance: Dictionary) -> bool:
	var passed := true
	for key: Variant in acceptance:
		if key == "thresholds":
			continue
		if bool(acceptance[key]):
			print("[PASS] Bunker 25 cm acceptance: %s" % str(key))
		else:
			passed = false
			push_error("[FAIL] Bunker 25 cm acceptance: %s" % str(key))
	return passed


func _new_metric_accumulator() -> Dictionary:
	return {
		"mix_energy_db": [],
		"dry_energy_db": [],
		"late_energy_db": [],
		"dry_to_late_db": [],
		"late_fraction": [],
		"route_direct_to_graph_db": [],
		"route_direct_fraction": [],
		"parallel_route_count": [],
		"maximum_parallel_route_gain_db": [],
		"maximum_diffuse_field_gain_db": [],
		"maximum_direct_occlusion": [],
		"mean_reverb_decay_seconds": [],
		"mean_environment_enclosure": [],
		"nearest_speaker_distance_m": [],
		"combined_low_db": [],
		"combined_mid_db": [],
		"combined_high_db": [],
		"shared_reverb_send": [],
		"shared_reverb_room_size": [],
		"shared_reverb_damping": [],
		"shared_reverb_predelay_msec": [],
		"shared_reverb_predelay_feedback": [],
		"shared_reverb_hipass": [],
	}


func _accumulate_metric(accumulator: Dictionary, mix: Dictionary) -> void:
	for key: String in [
		"mix_energy_db",
		"dry_energy_db",
		"late_energy_db",
		"dry_to_late_db",
		"late_fraction",
		"route_direct_to_graph_db",
		"route_direct_fraction",
		"parallel_route_count",
		"maximum_parallel_route_gain_db",
		"maximum_diffuse_field_gain_db",
		"maximum_direct_occlusion",
		"mean_reverb_decay_seconds",
		"mean_environment_enclosure",
		"nearest_speaker_distance_m",
		"shared_reverb_send",
		"shared_reverb_room_size",
		"shared_reverb_damping",
		"shared_reverb_predelay_msec",
		"shared_reverb_predelay_feedback",
		"shared_reverb_hipass",
	]:
		(accumulator[key] as Array).append(float(mix[key]))
	var bands: Array = mix["combined_band_db"]
	(accumulator["combined_low_db"] as Array).append(float(bands[0]))
	(accumulator["combined_mid_db"] as Array).append(float(bands[1]))
	(accumulator["combined_high_db"] as Array).append(float(bands[2]))


func _new_neighbor_accumulator() -> Dictionary:
	return {
		"mix_step_db": [],
		"dry_step_db": [],
		"late_step_db": [],
		"dry_to_late_step_db": [],
		"route_balance_step_db": [],
		"largest_band_step_db": [],
	}


func _accumulate_neighbor(accumulator: Dictionary, edge: Dictionary) -> void:
	for key: String in accumulator.keys():
		(accumulator[key] as Array).append(float(edge[key]))


func _summarize_accumulators(accumulators: Dictionary) -> Dictionary:
	var result := {}
	for region: String in accumulators:
		var accumulator: Dictionary = accumulators[region]
		var summary := {"sample_count": (accumulator["mix_energy_db"] as Array).size()}
		for key: String in accumulator:
			_append_distribution(summary, key, accumulator[key])
		result[region] = summary
	return result


func _summarize_neighbors(accumulators: Dictionary) -> Dictionary:
	var result := {}
	for region: String in accumulators:
		var accumulator: Dictionary = accumulators[region]
		var summary := {"edge_count": (accumulator["mix_step_db"] as Array).size()}
		for key: String in accumulator:
			_append_distribution(summary, key, accumulator[key])
		result[region] = summary
	return result


func _append_distribution(summary: Dictionary, key: String, raw_values: Array) -> void:
	if raw_values.is_empty():
		return
	var values := raw_values.duplicate()
	values.sort()
	summary["%s_min" % key] = float(values.front())
	summary["%s_p10" % key] = _percentile(values, 0.10)
	summary["%s_p50" % key] = _percentile(values, 0.50)
	summary["%s_p90" % key] = _percentile(values, 0.90)
	summary["%s_p99" % key] = _percentile(values, 0.99)
	summary["%s_max" % key] = float(values.back())
	summary["%s_mean" % key] = _mean(values)
	summary["%s_stddev" % key] = _stddev(values)


func _percentile(sorted_values: Array, ratio: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(
		roundi(ratio * float(sorted_values.size() - 1)),
		0,
		sorted_values.size() - 1
	)
	return float(sorted_values[index])


func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / float(maxi(values.size(), 1))


func _stddev(values: Array) -> float:
	if values.size() <= 1:
		return 0.0
	var average := _mean(values)
	var squared_sum := 0.0
	for value: float in values:
		var delta := value - average
		squared_sum += delta * delta
	return sqrt(squared_sum / float(values.size()))


func _insert_worst_edge(edge: Dictionary) -> void:
	var insertion_index := 0
	while (
		insertion_index < _worst_edges.size()
		and float(_worst_edges[insertion_index]["mix_step_db"])
		>= float(edge["mix_step_db"])
	):
		insertion_index += 1
	_worst_edges.insert(insertion_index, edge)
	if _worst_edges.size() > 40:
		_worst_edges.resize(40)


func _largest_band_step(current: Array, previous: Array) -> float:
	var result := 0.0
	for index: int in range(mini(current.size(), previous.size())):
		result = maxf(result, absf(float(current[index]) - float(previous[index])))
	return result


func _db_to_power(value_db: float) -> float:
	return pow(10.0, value_db / 10.0)


func _power_to_db(power: float) -> float:
	return maxf(10.0 * log(maxf(power, POWER_FLOOR)) / log(10.0), MIN_DB)


func _power_ratio_db(numerator: float, denominator: float) -> float:
	return clampf(
		10.0 * log(maxf(numerator, POWER_FLOOR) / maxf(denominator, POWER_FLOOR))
		/ log(10.0),
		MIN_DB,
		80.0
	)


func _band_db_array(power: Vector3) -> Array[float]:
	return [_power_to_db(power.x), _power_to_db(power.y), _power_to_db(power.z)]


func _vector_array(vector: Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]


func _json_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_DICTIONARY:
			var result := {}
			for key: Variant in (value as Dictionary):
				result[str(key)] = _json_safe((value as Dictionary)[key])
			return result
		TYPE_ARRAY:
			var result: Array = []
			for item: Variant in (value as Array):
				result.append(_json_safe(item))
			return result
		TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			return Array(value)
		TYPE_VECTOR2:
			var vector2: Vector2 = value
			return [vector2.x, vector2.y]
		TYPE_VECTOR2I:
			var vector2i: Vector2i = value
			return [vector2i.x, vector2i.y]
		TYPE_VECTOR3:
			return _vector_array(value)
		TYPE_VECTOR3I:
			var vector3i: Vector3i = value
			return [vector3i.x, vector3i.y, vector3i.z]
		TYPE_STRING_NAME:
			return str(value)
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
	return str(value)


func _save_json(path: String, report: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Bunker 25 cm probe: cannot write %s" % path)
		return false
	file.store_string(JSON.stringify(report))
	file.close()
	return true

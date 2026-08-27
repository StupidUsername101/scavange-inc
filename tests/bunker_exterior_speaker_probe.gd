extends SceneTree

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const PLAYER_EAR_HEIGHT := 1.7
const SAMPLE_DISTANCES := [1.0, 2.0, 5.0, 10.0]
const CALIBRATION_SAMPLE_DISTANCES := [2.0, 5.0]
const MAX_MATCHED_PLAYER_LEVEL_SPAN_DB := 3.5


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var server := root.get_node_or_null("Server")
	if server == null:
		push_error("Bunker speaker probe: server autoload unavailable")
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
		push_error("Bunker speaker probe: facility unavailable")
		quit(1)
		return
	if not cluster.apply_fieldlink_command(null, &"play_track", {"track_index": 0}):
		push_error("Bunker speaker probe: facility test program could not start")
		quit(1)
		return
	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	renderer._ensure_pool()

	var report: Array[Dictionary] = []
	var matched_player_levels: Dictionary[float, Array] = {}
	var direct_path_count := 0
	var expected_direct_path_count := 0
	var calibrated_exterior_count := 0
	var listener_id := 41000
	for descriptor: Dictionary in LAYOUT.speaker_descriptors():
		var cabinet_local: Vector3 = descriptor.get("position", Vector3.ZERO)
		var source_local := LAYOUT.speaker_source_local_position(descriptor)
		var face_direction := (source_local - cabinet_local).normalized()
		var emitter_id := int(descriptor.get("emitter_id", -1))
		var installation_gain_db := LAYOUT.speaker_installation_gain_db(descriptor)
		if not bool(descriptor.get("inside", false)) and is_equal_approx(
			installation_gain_db,
			6.0
		):
			calibrated_exterior_count += 1
		for distance: float in SAMPLE_DISTANCES:
			for player_height: bool in [false, true]:
				var listener_local := source_local + face_direction * distance
				if player_height:
					listener_local.y = PLAYER_EAR_HEIGHT
				var states: Dictionary = {}
				cluster.append_listener_states(
					states,
					listener_id,
					cluster.global_transform * listener_local,
					service
				)
				listener_id += 1
				var state: Dictionary = states.get(emitter_id, {})
				var render_packets: Array[Dictionary] = []
				for raw_state: Dictionary in states.values():
					render_packets.append(raw_state.duplicate(false))
				renderer._prepare_shared_program_mix(render_packets)
				var render_packet: Dictionary = {}
				for candidate: Dictionary in render_packets:
					if int(candidate.get("item_id", -1)) == emitter_id:
						render_packet = candidate
						break
				var normalization_db := float(
					render_packet.get("shared_program_normalization_db", 0.0)
				)
				if distance in CALIBRATION_SAMPLE_DISTANCES:
					expected_direct_path_count += 1
					if str(state.get("route_kind", &"missing")) == "direct":
						direct_path_count += 1
				if player_height and distance in CALIBRATION_SAMPLE_DISTANCES:
					if not matched_player_levels.has(distance):
						matched_player_levels[distance] = []
					matched_player_levels[distance].append(
						float(state.get("volume_db", -80.0))
					)
				report.append({
					"speaker": str(descriptor.get("name", &"Speaker")),
					"inside": bool(descriptor.get("inside", false)),
					"installation_gain_db": installation_gain_db,
					"distance_m": distance,
					"listener_height": "player" if player_height else "source",
					"listener_local": listener_local,
					"own_volume_db": state.get("volume_db", -80.0),
					"own_render_target_db": (
						float(render_packet.get("volume_db", -80.0))
					),
					"render_band_gain": render_packet.get("band_gain", Vector3.ZERO),
					"combined_energy_db": _combined_energy_db(states),
					"normalization_db": normalization_db,
					"route": str(state.get("route_kind", &"missing")),
					"occlusion": state.get("direct_occlusion", -1.0),
					"direct_distance": state.get("direct_distance", -1.0),
					"path_length": state.get("path_length", -1.0),
					"band_gain": state.get("band_gain", Vector3.ZERO),
					"graph_weight": state.get("route_graph_energy_weight", 0.0),
					"direct_weight": state.get("route_direct_energy_weight", 0.0),
					"enclosure": state.get("environment_enclosure", 0.0),
					"reverb_send": state.get("reverb_send", 0.0),
					"reverb_room_size": state.get("reverb_room_size", 0.0),
					"reverb_damping": state.get("reverb_damping", 0.0),
					"reverb_predelay_feedback": state.get(
						"reverb_predelay_feedback",
						0.0
					),
				})
	var level_spans: Dictionary[float, float] = {}
	var matched_levels_are_balanced := true
	for distance: float in CALIBRATION_SAMPLE_DISTANCES:
		var levels: Array = matched_player_levels.get(distance, [])
		if levels.size() != LAYOUT.speaker_descriptors().size():
			matched_levels_are_balanced = false
			continue
		levels.sort()
		var level_span := float(levels.back()) - float(levels.front())
		level_spans[distance] = level_span
		matched_levels_are_balanced = (
			matched_levels_are_balanced
			and level_span <= MAX_MATCHED_PLAYER_LEVEL_SPAN_DB
		)
	print("Bunker matched speaker report:\n%s" % JSON.stringify(report, "\t"))
	print("Bunker matched player-height level spans: %s" % level_spans)
	var passed := (
		calibrated_exterior_count == 2
		and direct_path_count == expected_direct_path_count
		and matched_levels_are_balanced
	)
	if not passed:
		push_error(
			"Bunker exterior calibration failed: calibrated=%d, direct=%d/%d, spans=%s"
			% [
				calibrated_exterior_count,
				direct_path_count,
				expected_direct_path_count,
				level_spans,
			]
		)
	renderer.reset_session()
	renderer.free()
	quit(0 if passed else 1)


func _combined_energy_db(states: Dictionary) -> float:
	var power_sum := 0.0
	for state: Dictionary in states.values():
		power_sum += pow(10.0, float(state.get("volume_db", -80.0)) / 10.0)
	return 10.0 * log(maxf(power_sum, 0.00000001)) / log(10.0)

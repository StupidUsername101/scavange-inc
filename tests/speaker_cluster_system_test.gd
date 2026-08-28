extends SceneTree

const LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const SERVER_SCENE := preload("res://scenes/server/speaker_cluster_demo.tscn")
const CLIENT_SCENE := preload("res://scenes/proxy/speaker_cluster_demo.tscn")
const WRIST_VIEW := preload("res://scripts/client/wrist_terminal_view.gd")
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const VOLUME_CONTROL := preload("res://scripts/audio/speaker_volume_control.gd")
const MUSIC_LOUDNESS := preload("res://scripts/audio/music_loudness_catalog.gd")
const INDUSTRIAL_LAYOUT := preload(
	"res://scripts/world/industrial_acoustic_complex_layout.gd"
)
const SERVER_PLAYER_SCENE := preload("res://scenes/server/server_player.tscn")
const RADIO_STATE_SNAPSHOT_CODEC := preload(
	"res://scripts/audio/radio_state_snapshot_codec.gd"
)

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shared_layout()
	await _test_generic_array_composition()
	await _test_client_facility()
	await _test_authoritative_cluster()
	_finish()


func _test_shared_layout() -> void:
	var speakers := LAYOUT.speaker_descriptors()
	var emitter_ids: Dictionary[int, bool] = {}
	var positions: Dictionary[Vector3, bool] = {}
	var inside_count := 0
	var calibrated_exterior_count := 0
	for descriptor: Dictionary in speakers:
		emitter_ids[int(descriptor.get("emitter_id", -1))] = true
		positions[descriptor.get("position", Vector3.ZERO)] = true
		inside_count += 1 if bool(descriptor.get("inside", false)) else 0
		if (
			not bool(descriptor.get("inside", false))
			and is_equal_approx(
				LAYOUT.speaker_installation_gain_db(descriptor),
				6.0
			)
		):
			calibrated_exterior_count += 1
	_expect(
		speakers.size() == 4
		and emitter_ids.size() == 4
		and positions.size() == 4
		and inside_count == 2,
		"garage authors four unique asymmetric emitters split across inside and outside"
	)
	_expect(
		calibrated_exterior_count == 2,
		"both exterior PA channels declare generic installation gain instead of relying on a propagation exception"
	)
	_expect(
		LAYOUT.structural_boxes().size() >= 9
		and LAYOUT.acoustic_probe_descriptors().size() >= 10
		and LAYOUT.prop_descriptors().size() >= 8,
		"shared garage layout includes an enclosed shell, dense probes, and curated solid props"
	)
	var has_emitter_specific_probe := false
	for probe: Dictionary in LAYOUT.acoustic_probe_descriptors():
		has_emitter_specific_probe = (
			has_emitter_specific_probe
			or str(probe.get("probe_id", &"")).contains("speaker")
		)
	_expect(
		not has_emitter_specific_probe,
		"the bunker bake describes air volumes without one-off probes named after emitters"
	)
	var garage_nature_count := 0
	for descriptor: Dictionary in NATURE_LAYOUT.collision_descriptors():
		if str(descriptor.get("name", "")).contains("Garage"):
			garage_nature_count += 1
	_expect(
		garage_nature_count >= 10,
		"solid nature assets surround the garage approach and rear field"
	)
	_expect(
		SERVER_SCENE != null and CLIENT_SCENE != null,
		"paired authoritative and visible garage scenes load"
	)


func _test_generic_array_composition() -> void:
	var definition := SpeakerArrayDefinition.new()
	definition.contact_id = &"test:generic_twelve_speaker_array"
	definition.display_name = "GENERIC TWELVE SPEAKER ARRAY"
	definition.audio_id_base = 1_900_012_000
	definition.playback_profile = load(
		"res://resources/items/radios/facility_pa_playback.tres"
	) as RadioItemDefinition
	var server_array := ServerSpeakerCluster.new()
	server_array.array_definition = definition
	var client_array := SpeakerClusterDemoProxy.new()
	client_array.array_definition = definition
	# Reverse insertion order deliberately proves that authored sort order—not child order or a
	# hidden four-speaker layout—owns stable network IDs on both sides.
	for speaker_index: int in range(11, -1, -1):
		for array_node: Node3D in [server_array, client_array]:
			var emitter := SpeakerArrayEmitter3D.new()
			emitter.name = "Emitter%02d" % speaker_index
			emitter.sort_order = speaker_index
			emitter.position = Vector3(float(speaker_index) * 1.5, 1.0, 0.0)
			array_node.add_child(emitter)
	root.add_child(server_array)
	root.add_child(client_array)
	await process_frame
	var acoustic_service := ServerAcousticService.new()
	root.add_child(acoustic_service)
	acoustic_service.bind_world(server_array)
	await physics_frame
	var playback_started := server_array.apply_fieldlink_command(
		null,
		&"play_track",
		{"track_index": 0}
	)
	var listener_states: Dictionary = {}
	server_array.append_listener_states(
		listener_states,
		1_900_012_999,
		Vector3(8.25, 1.0, 5.0),
		acoustic_service
	)
	var ids := server_array.get_emitter_ids()
	var wire_payload := RADIO_STATE_SNAPSHOT_CODEC.encode(listener_states)
	var decoded_states := RADIO_STATE_SNAPSHOT_CODEC.decode(wire_payload)
	var verbose_wire_size := var_to_bytes(listener_states).size()
	var ids_are_sequential := ids.size() == 12
	for speaker_index: int in range(ids.size()):
		ids_are_sequential = (
			ids_are_sequential
			and ids[speaker_index] == definition.audio_id_base + speaker_index
		)
	_expect(
		playback_started
		and listener_states.size() == 12
		and ids_are_sequential
		and server_array.get_speaker_markers().size() == 12
		and client_array.get_speaker_markers().size() == 12
		and server_array.find_children(
			"FacilitySpeaker*Body",
			"StaticBody3D",
			true,
			false
		).size() == 12
		and client_array.find_children(
			"SpeakerCone",
			"MeshInstance3D",
			true,
			false
		).size() == 12
		and decoded_states.size() == 12
		and wire_payload.size() < 4096
		and wire_payload.size() * 4 < verbose_wire_size,
		"one marker-driven controller discovers, IDs, collides, and renders an arbitrary twelve-speaker installation"
	)
	server_array.set_powered(false)
	acoustic_service.free()
	server_array.free()
	client_array.free()


func _test_client_facility() -> void:
	var client := root.get_node_or_null("Client")
	_expect(client != null, "client autoload is available")
	if client == null:
		return
	var proxy := CLIENT_SCENE.instantiate() as SpeakerClusterDemoProxy
	_expect(proxy != null, "visible garage proxy instantiates")
	if proxy == null:
		return
	proxy.position = LAYOUT.WORLD_POSITION
	root.add_child(proxy)
	await process_frame
	var cones: Array[Node] = proxy.find_children("SpeakerCone", "MeshInstance3D", true, false)
	_expect(
		cones.size() == 4,
		"visible facility constructs one independently animated cone per emitter"
	)
	if cones.size() == 4:
		var cone := cones[0] as MeshInstance3D
		var rest_scale := cone.scale
		var rest_position := cone.position
		proxy.call("_apply_speaker_level", 0, 1.0)
		_expect(
			cone.scale.x > rest_scale.x
			and cone.scale.x < rest_scale.x * 1.07
			and cone.position.z > rest_position.z,
			"PA cone pulse remains visible but restrained at full music envelope"
		)
		proxy.call("_apply_speaker_level", 0, 0.0)
		_expect(
			cone.scale.is_equal_approx(rest_scale)
			and cone.position.is_equal_approx(rest_position),
			"PA cone returns exactly to its authored rest transform"
		)
	var contacts_value: Variant = client.call(
		"collect_nearby_fieldlink_devices",
		LAYOUT.WORLD_POSITION + Vector3(0.0, 1.6, -8.0),
		0.0,
		36.0
	)
	var contacts: Array = contacts_value if contacts_value is Array else []
	var cluster_contact: Dictionary = {}
	for value: Variant in contacts:
		if value is Dictionary and (value as Dictionary).get("contact_id", &"") == LAYOUT.CONTACT_ID:
			cluster_contact = value
			break
	_expect(
		cluster_contact.get("control_type", &"") == &"speaker_cluster"
		and cluster_contact.get("device_class", &"") == &"PA ARRAY"
		and str(cluster_contact.get("display_name", "")).contains("GARAGE"),
		"Fieldlink scanner advertises the facility as one named PA array rather than four radios"
	)
	proxy.free()


func _test_authoritative_cluster() -> void:
	var server := root.get_node_or_null("Server")
	_expect(server != null, "server autoload is available")
	if server == null:
		return
	var server_constants := (server.get_script() as Script).get_script_constant_map()
	_expect(
		ServerAcousticService.DIRECT_PATH_EDGE_BLEND_DISTANCE
		> ServerPlayer.RUN_SPEED * float(server_constants.get("SYNC_RATE", 0.0)),
		"even a full-speed player cannot skip an entire obstacle-edge transition between server snapshots"
	)
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	await physics_frame
	var server_world := server.get("server_world") as Node3D
	var cluster := server_world.get_node_or_null("SpeakerClusterDemo") as ServerSpeakerCluster
	var large_cluster := server_world.get_node_or_null(
		"IndustrialAcousticComplex/LargeBunkerSpeakerArray"
	) as ServerSpeakerCluster
	var valve_cluster := server_world.get_node_or_null(
		"IndustrialAcousticComplex/ValveReferenceBunkerSpeakerArray"
	) as ServerSpeakerCluster
	_expect(
		cluster != null
		and server.get("server_speaker_clusters").has(cluster)
		and server.get("fieldlink_control_targets_by_contact_id").get(LAYOUT.CONTACT_ID) == cluster,
		"server registers one cluster with both continuous audio publishing and Fieldlink control"
	)
	if cluster == null:
		return
	var every_installed_music_source_is_silent := true
	for installed_cluster: Node3D in server.get("server_speaker_clusters"):
		every_installed_music_source_is_silent = (
			every_installed_music_source_is_silent
			and not bool(installed_cluster.get("powered"))
		)
	for installed_radio: Variant in (
		server.get("server_radios_by_item_id") as Dictionary
	).values():
		var radio_node := installed_radio as Node
		every_installed_music_source_is_silent = (
			every_installed_music_source_is_silent
			and radio_node != null
			and not bool(radio_node.get("powered"))
		)
	_expect(
		(server.get("server_speaker_clusters") as Array).size() >= 3
		and every_installed_music_source_is_silent,
		"every installed radio and speaker array in the active world starts silent"
	)
	_expect(
		large_cluster != null
		and server.get("server_speaker_clusters").has(large_cluster)
		and server.get("fieldlink_control_targets_by_contact_id").get(
			INDUSTRIAL_LAYOUT.LARGE_BUNKER_CONTACT_ID
		) == large_cluster
		and large_cluster.get_emitter_ids().size() == 4
		and not large_cluster.powered,
		"the large hall registers one distinct silent four-speaker Fieldlink array"
	)
	_expect(
		valve_cluster != null
		and server.get("server_speaker_clusters").has(valve_cluster)
		and server.get("fieldlink_control_targets_by_contact_id").get(
			INDUSTRIAL_LAYOUT.VALVE_BUNKER_CONTACT_ID
		) == valve_cluster
		and valve_cluster.get_emitter_ids().size() == 4
		and not valve_cluster.powered,
		"the Valve reference room registers its own silent four-speaker scanner target"
	)
	if large_cluster != null:
		var hall_control_position := (
			large_cluster.get_fieldlink_control_world_position()
		)
		var expected_hall_control_position := large_cluster.global_transform * (
			large_cluster.array_definition.scanner_beacon_position
		)
		var fieldlink_player := SERVER_PLAYER_SCENE.instantiate() as ServerPlayer
		root.add_child(fieldlink_player)
		fieldlink_player.global_position = hall_control_position + Vector3(6.4, 0.0, 0.0)
		fieldlink_player.set_wrist_interface_open(true)
		_expect(
			hall_control_position.is_equal_approx(expected_hall_control_position)
			and hall_control_position.distance_to(large_cluster.global_position)
			> 36.0
			and server.call(
				"_validate_fieldlink_control_target",
				fieldlink_player,
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_CONTACT_ID
			) == large_cluster,
			"large offset-mounted arrays validate control range at the same beacon the PBD displays"
		)
		fieldlink_player.free()
	_expect(
		not cluster.powered
		and cluster.current_song_path.is_empty()
		and cluster.get_emitter_ids().size() == 4,
		"installed PA registers all four emitters without starting music on scene load"
	)
	_expect(
		cluster.set_powered(true)
		and cluster.apply_fieldlink_command(null, &"play_track", {"track_index": 0})
		and cluster.powered
		and not cluster.current_song_path.is_empty(),
		"an explicit control action starts one deterministic authoritative playlist timeline for the array"
	)
	_expect(
		cluster.playback_profile.resource_path
		== "res://resources/items/radios/facility_pa_playback.tres"
		and cluster.playback_profile.distortion_mode == 4
		and is_zero_approx(cluster.playback_profile.distortion_drive)
		and is_zero_approx(cluster.playback_profile.distortion_post_gain_db)
		and not cluster.playback_profile.receiver_static_enabled
		and cluster.playback_profile.static_mix_db <= -60.0,
		"facility PA explicitly disables receiver static instead of approximating silence with gain"
	)
	var garage_facility := cluster.get_node_or_null(
		"Facility"
	) as ServerSpeakerClusterDemoFacility
	var generator_body := (
		garage_facility.get_node_or_null("GarageGeneratorBody") as StaticBody3D
		if garage_facility != null
		else null
	)
	var generator_material := (
		generator_body.get_meta(&"acoustic_material") as AcousticMaterial
		if generator_body != null
		else null
	)
	_expect(
		generator_body != null
		and PhysicalSurface.from_collider(generator_body) == &"metal"
		and generator_material != null
		and generator_material.material_id == &"machinery_housing"
		and garage_facility.acoustic_material != null
		and generator_material.material_id
		!= garage_facility.acoustic_material.material_id,
		"generic prop metadata keeps the generator physically metal but acoustically distinct from the bunker shell"
	)
	_expect(
		is_zero_approx(cluster.control_volume_db)
		and is_equal_approx(
			cluster.MAX_CONTROL_VOLUME_DB,
			VOLUME_CONTROL.MAX_CONTROL_VOLUME_DB
		),
		"PA array shares the raised speaker ceiling without changing its default output"
	)
	var loud_reference_track := "res://assets/sounds/music/temp/amerika.mp3"
	var calibrated_maximum_output_db := (
		cluster.playback_volume_db
		+ VOLUME_CONTROL.MAX_CONTROL_VOLUME_DB
		+ MUSIC_LOUDNESS.gain_db_for_path(loud_reference_track)
		+ MUSIC_LOUDNESS.DEVICE_REFERENCE_GAIN_DB
	)
	_expect(
		calibrated_maximum_output_db > -2.0,
		"100 percent PA output restores the physical speaker level after track balancing"
	)
	var snapshot_value: Variant = cluster.call("build_fieldlink_control_snapshot", null)
	var snapshot := snapshot_value as Dictionary
	snapshot["contact_id"] = LAYOUT.CONTACT_ID
	var sanitized := FieldlinkDeviceControlPacket.sanitize_snapshot(snapshot)
	_expect(
		sanitized.get("control_type", &"") == &"speaker_cluster"
		and sanitized.get("display_name", "") == LAYOUT.DISPLAY_NAME
		and not (sanitized.get("payload", {}) as Dictionary).get("tracks", []).is_empty(),
		"speaker-cluster snapshot passes the strict generic playlist-device boundary"
	)
	var view := WRIST_VIEW.new() as WristTerminalView
	root.add_child(view)
	view.show_scanner_page()
	view.set_scanner_contacts([{
		"contact_id": LAYOUT.CONTACT_ID,
		"display_name": LAYOUT.DISPLAY_NAME,
		"device_class": &"PA ARRAY",
		"control_type": &"speaker_cluster",
		"status_text": "PLAYING",
		"relative_position": Vector3(0.0, 0.0, -4.0),
		"distance_meters": 4.0,
		"signal_strength": 1.35,
	}], 36.0)
	view.call("_on_scanner_contact_selected", view.scanner_contacts[0])
	view.apply_device_control_snapshot(sanitized)
	var panel := view.device_control_panel as FieldlinkRadioControlPanel
	_expect(
		panel != null
		and panel.status_label.text.contains("GARAGE PRESSURE")
		and not panel.status_label.text.contains("RADIO"),
		"PBD reuses playlist controls while naming the selected system as a garage pressure array"
	)
	view.free()
	var routing_probe_count := 0
	var sampled_response_probe_count := 0
	for child: Node in cluster.find_children("*", "AcousticProbe3D", true, false):
		if not child is AcousticProbe3D:
			continue
		routing_probe_count += 1
		if (child as AcousticProbe3D).sample_reflections:
			sampled_response_probe_count += 1
	_expect(
		routing_probe_count == LAYOUT.acoustic_probe_descriptors().size()
		and sampled_response_probe_count == 0,
		"the bunker retains every routing probe while disabling its sampled response everywhere"
	)

	var states: Dictionary = {}
	var service := server.get("acoustic_service") as ServerAcousticService
	if large_cluster != null:
		var hall_started := large_cluster.apply_fieldlink_command(
			null,
			&"play_track",
			{"track_index": 0}
		)
		var hall_states: Dictionary = {}
		large_cluster.append_listener_states(
			hall_states,
			9909,
			large_cluster.global_transform * (
				INDUSTRIAL_LAYOUT.LARGE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0)
			),
			service
		)
		var hall_packets_are_shared_and_wet := hall_states.size() == 4
		for packet: Dictionary in hall_states.values():
			hall_packets_are_shared_and_wet = (
				hall_packets_are_shared_and_wet
				and int(packet.get("shared_program_group_id", -1))
				== INDUSTRIAL_LAYOUT.LARGE_BUNKER_SHARED_PROGRAM_GROUP_ID
				and bool(packet.get("shared_program_late_field_enabled", false))
				and float(packet.get("environment_enclosure", 0.0)) > 0.65
				and float(packet.get("reverb_decay_seconds", 0.0)) > 1.2
			)
		_expect(
			hall_started and hall_packets_are_shared_and_wet,
			"explicitly starting the hall array yields four phase-safe sources with the large room's long late field"
		)
		var wall_center_dominance := _large_bunker_directional_dominance(
			large_cluster,
			service,
			99091,
			INDUSTRIAL_LAYOUT.LARGE_BUNKER_CENTER
			+ Vector3(-17.0, 1.7, 0.0)
		)
		var wall_offset_dominance := _large_bunker_directional_dominance(
			large_cluster,
			service,
			99092,
			INDUSTRIAL_LAYOUT.LARGE_BUNKER_CENTER
			+ Vector3(-17.0, 1.7, -8.0)
		)
		_expect(
			float(wall_center_dominance.get("nearest_over_rest_db", -INF)) > 10.0
			and float(wall_offset_dominance.get("nearest_over_rest_db", -INF)) > 4.0
			and int(wall_center_dominance.get("nearest_emitter_id", -1))
			== int(wall_center_dominance.get("loudest_emitter_id", -2))
			and int(wall_offset_dominance.get("nearest_emitter_id", -1))
			== int(wall_offset_dominance.get("loudest_emitter_id", -2)),
			"the real large-bunker wall keeps its nearest physical cabinet directionally dominant without removing diffuse room energy"
		)
		await _test_large_bunker_renderer_lifecycle(hall_states)
		large_cluster.set_powered(false)
	var outside_states: Dictionary = {}
	var threshold_states: Dictionary = {}
	var inside_states: Dictionary = {}
	var center_states: Dictionary = {}
	var rear_states: Dictionary = {}
	var prop_shadow_states: Dictionary = {}
	cluster.append_listener_states(
		outside_states,
		9910,
		cluster.global_transform * Vector3(LAYOUT.DOOR_CENTER_X, 1.55, -7.45),
		service
	)
	cluster.append_listener_states(
		threshold_states,
		9911,
		cluster.global_transform * Vector3(LAYOUT.DOOR_CENTER_X, 1.55, -6.95),
		service
	)
	cluster.append_listener_states(
		inside_states,
		9912,
		cluster.global_transform * Vector3(LAYOUT.DOOR_CENTER_X, 1.55, -5.8),
		service
	)
	cluster.append_listener_states(
		center_states,
		9913,
		cluster.global_transform * Vector3(-0.4, 1.55, 0.0),
		service
	)
	cluster.append_listener_states(
		rear_states,
		9915,
		cluster.global_transform * Vector3(-0.4, 1.55, 5.0),
		service
	)
	cluster.append_listener_states(
		prop_shadow_states,
		9914,
		cluster.global_transform * Vector3(-5.4, 1.55, 2.3),
		service
	)
	var back_left_id := LAYOUT.emitter_id(0)
	var right_inside_id := LAYOUT.emitter_id(1)
	var entrance_exterior_id := LAYOUT.emitter_id(2)
	var outside_reverb := float((outside_states.get(back_left_id, {}) as Dictionary).get("reverb_send", 1.0))
	var threshold_reverb := float((threshold_states.get(back_left_id, {}) as Dictionary).get("reverb_send", 1.0))
	var inside_reverb := float((inside_states.get(back_left_id, {}) as Dictionary).get("reverb_send", 0.0))
	var center_reverb := float((center_states.get(back_left_id, {}) as Dictionary).get("reverb_send", 0.0))
	_expect(
		outside_reverb <= 0.001
		and threshold_reverb <= 0.001
		and inside_reverb <= 0.001
		and center_reverb <= 0.001,
		"the bunker-wide A/B profile disables sampled room response on both sides of its doorway"
	)
	var exterior_outside: Dictionary = outside_states.get(
		entrance_exterior_id,
		{}
	)
	var exterior_inside: Dictionary = inside_states.get(
		entrance_exterior_id,
		{}
	)
	var exterior_rear: Dictionary = rear_states.get(
		entrance_exterior_id,
		{}
	)
	var exterior_inside_modifiers: PackedStringArray = exterior_inside.get(
		"modifier_ids",
		PackedStringArray()
	)
	var exterior_rear_modifiers: PackedStringArray = exterior_rear.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		float(exterior_outside.get("direct_occlusion", 1.0)) < 0.01
		and not exterior_inside_modifiers.has("garage_concrete_metal")
		and not exterior_rear_modifiers.has("garage_concrete_metal")
		and float(exterior_inside.get("volume_db", -80.0))
		> float(exterior_outside.get("volume_db", -80.0)) - 6.0
		and float(exterior_rear.get("volume_db", -80.0))
		> float(exterior_inside.get("volume_db", -80.0)) - 18.0,
		"the exterior entrance speaker follows the open doorway route through the full bunker instead of transmitting through its header"
	)
	var shadow_state: Dictionary = prop_shadow_states.get(back_left_id, {})
	_expect(
		float(shadow_state.get("direct_occlusion", 1.0)) > 0.0
		and float(shadow_state.get("direct_occlusion", 1.0)) < 1.0
		and float(shadow_state.get("reverb_send", 1.0)) <= 0.001
		and float(shadow_state.get("environment_enclosure", 1.0)) <= 0.001,
		"the generator retains partial geometric shadowing without recreating a room response"
	)
	var inside_back_left: Dictionary = inside_states.get(back_left_id, {})
	var inside_right: Dictionary = inside_states.get(right_inside_id, {})
	var inside_pair_energy := 0.0
	var strongest_inside_pair_db := -80.0
	for state: Dictionary in [inside_back_left, inside_right]:
		var volume_db := float(state.get("volume_db", -80.0))
		strongest_inside_pair_db = maxf(strongest_inside_pair_db, volume_db)
		inside_pair_energy += pow(10.0, volume_db / 10.0)
	var combined_inside_pair_db := (
		10.0 * log(maxf(inside_pair_energy, 0.00000001)) / log(10.0)
	)
	var all_speaker_energy := 0.0
	for state: Dictionary in inside_states.values():
		var volume_db := float(state.get("volume_db", -80.0))
		all_speaker_energy += pow(10.0, volume_db / 10.0)
	var combined_all_speakers_db := (
		10.0 * log(maxf(all_speaker_energy, 0.00000001)) / log(10.0)
	)
	_expect(
		inside_states.size() == 4
		# Without diffuse equalization, the two interior cabinets legitimately arrive at different
		# levels. Both must remain audible and add energy; they no longer need to be nearly equal.
		and float(inside_back_left.get("volume_db", -80.0)) > -60.0
		and float(inside_right.get("volume_db", -80.0)) > -60.0
		and combined_inside_pair_db > strongest_inside_pair_db + 0.25
		and combined_all_speakers_db > combined_inside_pair_db
		and not inside_back_left.is_empty()
		and not inside_right.is_empty(),
		"multiple propagation-only speakers add energy and both interior boxes reach the entrance"
	)
	cluster.set_control_volume_ratio(1.0)
	var full_output_positions := PackedVector3Array([
		Vector3(-5.7, 1.55, -3.8),
		Vector3(4.2, 1.55, -3.7),
		Vector3(-0.4, 1.55, 0.0),
		Vector3(-5.5, 1.55, 4.3),
		Vector3(5.5, 1.55, 4.4),
		Vector3(5.7, 1.55, 1.3),
		# Between the rear probes and above real props: these caught a response-radius hole that
		# made the room tail vanish on top of either crate.
		Vector3(-0.2, 1.55, 4.9),
		Vector3(-0.2, 2.85, 4.9),
		Vector3(1.05, 1.55, 5.25),
		Vector3(1.05, 2.85, 5.25),
	])
	var quietest_full_output_db := INF
	var loudest_full_output_db := -INF
	var shared_room_field := true
	var full_output_listener_id := 9930
	for local_position: Vector3 in full_output_positions:
		var full_output_states: Dictionary = {}
		cluster.append_listener_states(
			full_output_states,
			full_output_listener_id,
			cluster.global_transform * local_position,
			service
		)
		full_output_listener_id += 1
		var full_output_energy := 0.0
		for state: Dictionary in full_output_states.values():
			full_output_energy += pow(
				10.0,
				float(state.get("volume_db", -80.0)) / 10.0
			)
		var combined_full_output_db := 10.0 * log(
			maxf(full_output_energy, 0.00000001)
		) / log(10.0)
		quietest_full_output_db = minf(
			quietest_full_output_db,
			combined_full_output_db
		)
		loudest_full_output_db = maxf(
			loudest_full_output_db,
			combined_full_output_db
		)
		var back_left_state: Dictionary = full_output_states.get(back_left_id, {})
		var right_inside_state: Dictionary = full_output_states.get(right_inside_id, {})
		shared_room_field = (
			shared_room_field
			and int(back_left_state.get("diffuse_field_region_id", -1)) >= 0
			and int(back_left_state.get("diffuse_field_region_id", -1))
			== int(right_inside_state.get("diffuse_field_region_id", -2))
			and float(back_left_state.get("diffuse_field_support", 0.0)) > 0.5
			and float(right_inside_state.get("diffuse_field_support", 0.0)) > 0.5
		)
	print(
		"Bunker fixed-position field: quiet %.3f dB, loud %.3f dB, spread %.3f dB, shared=%s"
		% [
			quietest_full_output_db,
			loudest_full_output_db,
			loudest_full_output_db - quietest_full_output_db,
			str(shared_room_field),
		]
	)
	_expect(
		not shared_room_field
		and is_finite(quietest_full_output_db)
		and is_finite(loudest_full_output_db)
		and loudest_full_output_db - quietest_full_output_db > 3.0
		and loudest_full_output_db - quietest_full_output_db < 8.0,
		"the propagation-only bunker retains complete coverage without diffuse-field equalization"
	)
	var back_left_source := LAYOUT.speaker_source_local_position(
		LAYOUT.speaker_descriptors()[0]
	)
	var near_full_output_states: Dictionary = {}
	var far_full_output_states: Dictionary = {}
	cluster.append_listener_states(
		near_full_output_states,
		9946,
		cluster.global_transform * (
			back_left_source + Vector3(0.0, -2.0, -2.0)
		),
		service
	)
	cluster.append_listener_states(
		far_full_output_states,
		9947,
		cluster.global_transform * (
			back_left_source + Vector3(0.0, -2.0, -5.0)
		),
		service
	)
	var near_primary: Dictionary = near_full_output_states.get(back_left_id, {})
	var far_primary: Dictionary = far_full_output_states.get(back_left_id, {})
	var near_primary_bands: Vector3 = near_primary.get("band_gain", Vector3.ZERO)
	var far_primary_bands: Vector3 = far_primary.get("band_gain", Vector3.ZERO)
	print(
		"Bunker near/far field: %.3f / %.3f dB, bands %s / %s"
		% [
			_combined_energy_db(near_full_output_states),
			_combined_energy_db(far_full_output_states),
			str(near_primary_bands),
			str(far_primary_bands),
		]
	)
	_expect(
		_combined_energy_db(near_full_output_states)
		> _combined_energy_db(far_full_output_states) + 1.0
		and _combined_energy_db(near_full_output_states)
		< _combined_energy_db(far_full_output_states) + 6.0
		and near_primary_bands.x > 0.9
		and near_primary_bands.y > 0.9
		and far_primary_bands.x > 0.9
		and far_primary_bands.y > 0.9,
		"a propagation-only indoor array preserves low/mid energy while regaining physical distance falloff"
	)
	var dense_perimeter := _trace_dense_perimeter(cluster, service)
	print("Bunker dense-perimeter trace: ", dense_perimeter)
	_expect(
		int(dense_perimeter.get("sample_count", 0)) >= 480
		and int(dense_perimeter.get("missing_state_edges", -1)) == 0
		and float(dense_perimeter.get("max_volume_step_db", INF)) <= 2.0
		and float(dense_perimeter.get("max_band_step", INF)) <= 0.12
		and float(dense_perimeter.get("max_reverb_step", INF)) <= 0.08,
		"a ten-centimetre bunker perimeter trace keeps every speaker state and changes audible level, colour, and hall continuously"
	)
	var generator_shadow_trace := _trace_generator_shadow(
		cluster,
		service,
		back_left_id
	)
	_expect(
		int(generator_shadow_trace.get("sample_count", 0)) >= 200
		and int(generator_shadow_trace.get("missing_state_edges", -1)) == 0
		and float(generator_shadow_trace.get("max_volume_step_db", INF)) <= 0.85
		and float(generator_shadow_trace.get("max_band_step", INF)) <= 0.10
		and float(generator_shadow_trace.get("max_lowpass_ratio", INF)) <= 1.18
		and float(generator_shadow_trace.get("max_reverb_step", INF)) <= 0.06
		and float(generator_shadow_trace.get("max_occlusion_step", INF)) <= 0.16
		and float(generator_shadow_trace.get("max_route_weight_step", INF)) <= 0.18
		and float(generator_shadow_trace.get("max_apparent_position_step", INF)) <= 0.75,
		"the real five-centimetre generator-shadow walk is continuous in energy, colour, hall, routing, and apparent direction (trace: %s)"
		% generator_shadow_trace
	)
	cluster.set_control_volume_ratio(
		VOLUME_CONTROL.DEFAULT_CONTROL_VOLUME_RATIO
	)
	var exterior_speaker: Dictionary = LAYOUT.speaker_descriptors()[2]
	var exterior_source := cluster.global_transform * (
		LAYOUT.speaker_source_local_position(exterior_speaker)
	)
	var forest_path_uses_wood := false
	var forest_trunk_scatters_partially := false
	var forest_listener_id := 9950
	for descriptor: Dictionary in NATURE_LAYOUT.collision_descriptors():
		if (
			descriptor.get("collision_kind", &"") != &"trunk"
			or not str(descriptor.get("name", "")).begins_with("ForestTree_")
		):
			continue
		var tree_position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var horizontal_direction := Vector3(
			tree_position.x - exterior_source.x,
			0.0,
			tree_position.z - exterior_source.z
		)
		if horizontal_direction.length() < 14.0 or horizontal_direction.length() > 65.0:
			continue
		var listener_position := Vector3(tree_position.x, 1.7, tree_position.z)
		listener_position += horizontal_direction.normalized() * 3.0
		var direct_path := service._sample_direct_path(
			forest_listener_id,
			listener_position,
			exterior_source,
			[],
			0
		)
		forest_listener_id += 1
		var modifier := direct_path.get("modifier") as AcousticPathModifier
		if (
			bool(direct_path.get("blocked", false))
			and modifier != null
			and modifier.modifier_id == &"outdoor_wood"
			and modifier.lowpass_hz < 5000.0
		):
			forest_path_uses_wood = true
			var propagated := service.calculate_listener_result(
				forest_listener_id,
				listener_position,
				exterior_source,
				165.0
			)
			var free_field := AcousticPropagationGraph.sample_free_field(
				listener_position,
				exterior_source,
				165.0
			)
			var propagated_bands: Vector3 = propagated.get(
				"band_gain",
				Vector3.ZERO
			)
			forest_trunk_scatters_partially = (
				float(direct_path.get("occlusion", 1.0)) > 0.0
				and float(direct_path.get("occlusion", 1.0)) <= 0.3
				and float(propagated.get("volume_db", -80.0))
				> float(free_field.get("volume_db", 0.0)) - 3.0
				and float(propagated.get("lowpass_hz", 0.0)) > 12000.0
				and propagated_bands.z > 0.75
			)
			if forest_trunk_scatters_partially:
				break
	_expect(
		forest_path_uses_wood and forest_trunk_scatters_partially,
		"a real forest trunk uses authored wood but only gently scatters the PA wave around its narrow silhouette"
	)
	cluster.append_listener_states(
		states,
		9921,
		LAYOUT.WORLD_POSITION + Vector3(LAYOUT.DOOR_CENTER_X, 1.55, -8.0),
		service
	)
	var all_share_timeline := not states.is_empty()
	var all_omit_synthesized_late_field := not states.is_empty()
	var shared_program_offset := -1.0
	for raw_state: Variant in states.values():
		if not raw_state is Dictionary:
			all_share_timeline = false
			continue
		var state: Dictionary = raw_state
		var client_packet := RadioStatePacket.sanitize(state)
		if (
			client_packet.is_empty()
			or client_packet.get("song_path", "") != cluster.current_song_path
			or int(client_packet.get("revision", -1)) != cluster.playback_revision
			or int(client_packet.get("shared_program_group_id", -1))
			!= LAYOUT.SHARED_PROGRAM_GROUP_ID
		):
			all_share_timeline = false
		if bool(client_packet.get("receiver_static_enabled", true)):
			all_share_timeline = false
		if bool(client_packet.get("shared_program_late_field_enabled", true)):
			all_omit_synthesized_late_field = false
		var program_offset := float(
			client_packet.get("program_playback_offset_seconds", -1.0)
		)
		if shared_program_offset < 0.0:
			shared_program_offset = program_offset
		elif not is_equal_approx(shared_program_offset, program_offset):
			all_share_timeline = false
	_expect(
		all_share_timeline,
		"every audible cabinet shares one phase-safe program timeline while retaining its own path result"
	)
	_expect(
		all_omit_synthesized_late_field,
		"the bunker A/B profile leaves its extra synthesized late return disabled on every client"
	)
	var previous_revision := cluster.control_revision
	_expect(
		cluster.apply_fieldlink_command(null, &"pause", {})
		and cluster.paused
		and cluster.apply_fieldlink_command(null, &"resume", {})
		and not cluster.paused
		and cluster.apply_fieldlink_command(null, &"set_volume", {"volume_ratio": 0.41})
		and cluster.control_revision > previous_revision,
		"shared Fieldlink controls authoritatively pause, resume, and regulate the whole array"
	)


func _test_large_bunker_renderer_lifecycle(raw_states: Dictionary) -> void:
	var immediate_states: Dictionary = {}
	for emitter_id: int in raw_states:
		var packet := (raw_states[emitter_id] as Dictionary).duplicate(true)
		packet["start_delay_seconds"] = 0.0
		immediate_states[emitter_id] = packet
	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	renderer.submit_snapshot(immediate_states)
	renderer._process(1.0 / 60.0)
	var debug := renderer.get_debug_state()
	var direct_paths_are_full_band := true
	for slot_index: int in range(renderer._slot_item_ids.size()):
		if renderer._slot_item_ids[slot_index] < 0:
			continue
		var rack := renderer._effect_racks[slot_index]
		direct_paths_are_full_band = (
			direct_paths_are_full_band
			and is_zero_approx(AudioServer.get_bus_volume_db(rack.bus_index))
			and not AudioServer.is_bus_effect_enabled(
				rack.bus_index,
				rack._tail_lowpass_effect_index
			)
		)
	var group_slot := renderer._shared_program_group_slot(
		INDUSTRIAL_LAYOUT.LARGE_BUNKER_SHARED_PROGRAM_GROUP_ID
	)
	var wet_path_is_live := false
	if group_slot >= 0:
		var wet_rack := renderer._shared_program_racks[group_slot]
		wet_path_is_live = (
			renderer._shared_program_players[group_slot].playing
			and wet_rack.reverb.wet > 0.001
			and is_zero_approx(AudioServer.get_bus_volume_db(wet_rack.bus_index))
			and not AudioServer.is_bus_effect_enabled(
				wet_rack.bus_index,
				wet_rack._tail_lowpass_effect_index
			)
		)
	_expect(
		int(debug.get("active_count", 0)) == 4
		and int(debug.get("active_shared_late_field_count", 0)) == 1
		and direct_paths_are_full_band
		and wet_path_is_live,
		"the real four-speaker bunker renderer keeps four localized dry paths and one live full-band Hall return"
	)

	# One absent unreliable snapshot must remain a level interpolation event. It cannot transition
	# either the direct cabinets or their shared Hall rack into post-tail filtering while audio input
	# is still flowing.
	renderer.submit_snapshot({})
	renderer._process(0.05)
	renderer.submit_snapshot(immediate_states)
	renderer._process(0.05)
	var recovered_full_band := true
	for slot_index: int in range(renderer._slot_item_ids.size()):
		if renderer._slot_item_ids[slot_index] < 0:
			continue
		var rack := renderer._effect_racks[slot_index]
		recovered_full_band = (
			recovered_full_band
			and not AudioServer.is_bus_effect_enabled(
				rack.bus_index,
				rack._tail_lowpass_effect_index
			)
		)
	if group_slot >= 0:
		var wet_rack := renderer._shared_program_racks[group_slot]
		recovered_full_band = (
			recovered_full_band
			and not AudioServer.is_bus_effect_enabled(
				wet_rack.bus_index,
				wet_rack._tail_lowpass_effect_index
			)
		)
	_expect(
		recovered_full_band,
		"a skipped bunker snapshot cannot leave the resumed cabinets or shared Hall return darkened"
	)

	# Also cross the complete pause boundary: voices release, their returns settle, then the same
	# authoritative program revision resumes from its updated timeline. No pooled bus state may leak
	# into or attenuate the restarted array.
	renderer.submit_snapshot({})
	renderer._process(1.0)
	renderer._process(2.5)
	renderer.submit_snapshot(immediate_states)
	renderer._process(1.0 / 60.0)
	var settled_resume_is_clean := (
		int(renderer.get_debug_state().get("active_count", 0)) == 4
	)
	for slot_index: int in range(renderer._slot_item_ids.size()):
		if renderer._slot_item_ids[slot_index] < 0:
			continue
		var rack := renderer._effect_racks[slot_index]
		settled_resume_is_clean = (
			settled_resume_is_clean
			and is_zero_approx(AudioServer.get_bus_volume_db(rack.bus_index))
			and not AudioServer.is_bus_effect_enabled(
				rack.bus_index,
				rack._tail_lowpass_effect_index
			)
		)
	if group_slot >= 0:
		var wet_rack := renderer._shared_program_racks[group_slot]
		settled_resume_is_clean = (
			settled_resume_is_clean
			and renderer._shared_program_players[group_slot].playing
			and is_zero_approx(AudioServer.get_bus_volume_db(wet_rack.bus_index))
			and not AudioServer.is_bus_effect_enabled(
				wet_rack.bus_index,
				wet_rack._tail_lowpass_effect_index
			)
		)
	_expect(
		settled_resume_is_clean,
		"the bunker can resume after complete silence without inheriting a retired Hall bus"
	)
	renderer.reset_session()
	renderer.free()


func _combined_energy_db(states: Dictionary) -> float:
	var power_sum := 0.0
	for state: Dictionary in states.values():
		power_sum += pow(
			10.0,
			float(state.get("volume_db", -80.0)) / 10.0
		)
	return 10.0 * log(maxf(power_sum, 0.00000001)) / log(10.0)


func _large_bunker_directional_dominance(
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService,
	listener_id: int,
	listener_local_position: Vector3
) -> Dictionary:
	var states: Dictionary = {}
	cluster.append_listener_states(
		states,
		listener_id,
		cluster.global_transform * listener_local_position,
		service
	)
	var packets: Array[Dictionary] = []
	var nearest_emitter_id := -1
	var nearest_distance := INF
	for emitter_id: int in states:
		var packet := RadioStatePacket.sanitize(states[emitter_id])
		if packet.is_empty():
			continue
		packets.append(packet)
		var distance := float(packet.get("direct_distance", INF))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_emitter_id = emitter_id
	var renderer := RadioAudioRenderer.new()
	renderer._prepare_shared_program_mix(packets)
	var loudest_emitter_id := -1
	var loudest_db := -INF
	var nearest_db := -INF
	var rest_power := 0.0
	for packet: Dictionary in packets:
		var emitter_id := int(packet.get("item_id", -1))
		var volume_db := float(packet.get("volume_db", -80.0))
		if volume_db > loudest_db:
			loudest_db = volume_db
			loudest_emitter_id = emitter_id
		if emitter_id == nearest_emitter_id:
			nearest_db = volume_db
		else:
			rest_power += pow(10.0, volume_db / 10.0)
	return {
		"nearest_emitter_id": nearest_emitter_id,
		"loudest_emitter_id": loudest_emitter_id,
		"nearest_over_rest_db": (
			nearest_db
			- 10.0 * log(maxf(rest_power, 0.00000001)) / log(10.0)
		),
	}


func _trace_dense_perimeter(
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService
) -> Dictionary:
	# These paths cover both long exterior walls and, critically, the rear-right corner beside the
	# outside speaker. Reuse one listener ID per walk so this exercises the same cached continuous
	# state a moving player receives, rather than a collection of unrelated point samples.
	var paths := [
		{
			"from": Vector3(-13.0, 1.7, 8.0),
			"to": Vector3(13.0, 1.7, 8.0),
			"listener_id": 9981,
		},
		{
			"from": Vector3(10.0, 1.7, -11.0),
			"to": Vector3(10.0, 1.7, 11.0),
			"listener_id": 9982,
		},
	]
	var sample_count := 0
	var missing_state_edges := 0
	var max_occlusion_step := 0.0
	var max_volume_step_db := 0.0
	var max_band_step := 0.0
	var max_reverb_step := 0.0
	var worst_volume_step: Dictionary = {}
	for path: Dictionary in paths:
		var from: Vector3 = path["from"]
		var to: Vector3 = path["to"]
		var count := ceili(from.distance_to(to) / 0.1) + 1
		var previous_presence: Dictionary[int, bool] = {}
		var previous_occlusion: Dictionary[int, float] = {}
		var previous_volume_db: Dictionary[int, float] = {}
		var previous_band_gain: Dictionary[int, Vector3] = {}
		var previous_reverb_send: Dictionary[int, float] = {}
		for index: int in range(count):
			var ratio := float(index) / float(maxi(count - 1, 1))
			var states: Dictionary = {}
			cluster.append_listener_states(
				states,
				int(path["listener_id"]),
				cluster.global_transform * from.lerp(to, ratio),
				service
			)
			sample_count += 1
			for emitter_id: int in cluster.get_emitter_ids():
				var present := states.has(emitter_id)
				if (
					previous_presence.has(emitter_id)
					and bool(previous_presence[emitter_id]) != present
				):
					missing_state_edges += 1
				previous_presence[emitter_id] = present
				if not present:
					continue
				var state: Dictionary = states[emitter_id]
				var occlusion := float(state.get("direct_occlusion", 0.0))
				if previous_occlusion.has(emitter_id):
					max_occlusion_step = maxf(
						max_occlusion_step,
						absf(occlusion - float(previous_occlusion[emitter_id]))
					)
				previous_occlusion[emitter_id] = occlusion
				var volume_db := float(state.get("volume_db", -80.0))
				var band_gain: Vector3 = state.get("band_gain", Vector3.ONE)
				var reverb_send := float(state.get("reverb_send", 0.0))
				if previous_volume_db.has(emitter_id):
					var volume_step := absf(
						volume_db - float(previous_volume_db[emitter_id])
					)
					if volume_step > max_volume_step_db:
						worst_volume_step = {
							"path_listener_id": int(path["listener_id"]),
							"sample_index": index,
							"position": from.lerp(to, ratio),
							"emitter_id": emitter_id,
							"previous_volume_db": previous_volume_db[emitter_id],
							"volume_db": volume_db,
							"previous_band_gain": previous_band_gain[emitter_id],
							"band_gain": band_gain,
							"direct_occlusion": state.get("direct_occlusion", -1.0),
							"path_length": state.get("path_length", -1.0),
							"direct_distance": state.get("direct_distance", -1.0),
							"modifier_ids": state.get("modifier_ids", PackedStringArray()),
						}
					max_volume_step_db = maxf(
						max_volume_step_db,
						volume_step
					)
					max_band_step = maxf(
						max_band_step,
						band_gain.distance_to(previous_band_gain[emitter_id])
					)
					max_reverb_step = maxf(
						max_reverb_step,
						absf(
							reverb_send
							- float(previous_reverb_send[emitter_id])
						)
					)
				previous_volume_db[emitter_id] = volume_db
				previous_band_gain[emitter_id] = band_gain
				previous_reverb_send[emitter_id] = reverb_send
	return {
		"sample_count": sample_count,
		"missing_state_edges": missing_state_edges,
		"max_occlusion_step": max_occlusion_step,
		"max_volume_step_db": max_volume_step_db,
		"max_band_step": max_band_step,
		"max_reverb_step": max_reverb_step,
		"worst_volume_step": worst_volume_step,
	}


func _trace_generator_shadow(
	cluster: ServerSpeakerCluster,
	service: ServerAcousticService,
	emitter_id: int
) -> Dictionary:
	const LISTENER_ID := 9991
	const SAMPLE_SPACING := 0.05
	var endpoints := PackedVector3Array([
		Vector3(-8.0, 1.55, 2.3),
		Vector3(-2.8, 1.55, 2.3),
	])
	var sample_count := 0
	var missing_state_edges := 0
	var max_volume_step_db := 0.0
	var max_band_step := 0.0
	var max_lowpass_ratio := 1.0
	var max_reverb_step := 0.0
	var max_occlusion_step := 0.0
	var max_route_weight_step := 0.0
	var max_apparent_position_step := 0.0
	var worst_step: Dictionary = {}
	var previous_state: Dictionary = {}
	for pass_index: int in range(2):
		var from := endpoints[pass_index]
		var to := endpoints[1 - pass_index]
		var count := ceili(from.distance_to(to) / SAMPLE_SPACING) + 1
		for sample_index: int in range(count):
			var ratio := float(sample_index) / float(maxi(count - 1, 1))
			var local_position := from.lerp(to, ratio)
			var states: Dictionary = {}
			cluster.append_listener_states(
				states,
				LISTENER_ID,
				cluster.global_transform * local_position,
				service
			)
			sample_count += 1
			var state: Dictionary = states.get(emitter_id, {})
			if state.is_empty():
				if not previous_state.is_empty():
					missing_state_edges += 1
				continue
			if previous_state.is_empty():
				previous_state = state
				continue
			var volume_step := absf(
				float(state.get("volume_db", -80.0))
				- float(previous_state.get("volume_db", -80.0))
			)
			var band_step := (state.get(
				"band_gain",
				Vector3.ONE
			) as Vector3).distance_to(previous_state.get(
				"band_gain",
				Vector3.ONE
			))
			var lowpass := maxf(float(state.get("lowpass_hz", 20.0)), 20.0)
			var previous_lowpass := maxf(float(
				previous_state.get("lowpass_hz", 20.0)
			), 20.0)
			var lowpass_ratio := maxf(
				lowpass / previous_lowpass,
				previous_lowpass / lowpass
			)
			var reverb_step := absf(
				float(state.get("reverb_send", 0.0))
				- float(previous_state.get("reverb_send", 0.0))
			)
			var occlusion_step := absf(
				float(state.get("direct_occlusion", 0.0))
				- float(previous_state.get("direct_occlusion", 0.0))
			)
			var route_weight_step := maxf(
				absf(
					float(state.get("route_graph_energy_weight", 0.0))
					- float(previous_state.get("route_graph_energy_weight", 0.0))
				),
				absf(
					float(state.get("route_direct_energy_weight", 1.0))
					- float(previous_state.get("route_direct_energy_weight", 1.0))
				)
			)
			var apparent_position_step := (state.get(
				"apparent_position",
				Vector3.ZERO
			) as Vector3).distance_to(previous_state.get(
				"apparent_position",
				Vector3.ZERO
			))
			if volume_step > max_volume_step_db:
				worst_step = {
					"pass": pass_index,
					"sample": sample_index,
					"local_position": local_position,
					"previous_volume_db": previous_state.get("volume_db", -80.0),
					"volume_db": state.get("volume_db", -80.0),
					"previous_route": previous_state.get("route_kind", &""),
					"route": state.get("route_kind", &""),
					"previous_occlusion": previous_state.get("direct_occlusion", 0.0),
					"occlusion": state.get("direct_occlusion", 0.0),
				}
			max_volume_step_db = maxf(max_volume_step_db, volume_step)
			max_band_step = maxf(max_band_step, band_step)
			max_lowpass_ratio = maxf(max_lowpass_ratio, lowpass_ratio)
			max_reverb_step = maxf(max_reverb_step, reverb_step)
			max_occlusion_step = maxf(max_occlusion_step, occlusion_step)
			max_route_weight_step = maxf(
				max_route_weight_step,
				route_weight_step
			)
			max_apparent_position_step = maxf(
				max_apparent_position_step,
				apparent_position_step
			)
			previous_state = state
	return {
		"sample_count": sample_count,
		"missing_state_edges": missing_state_edges,
		"max_volume_step_db": max_volume_step_db,
		"max_band_step": max_band_step,
		"max_lowpass_ratio": max_lowpass_ratio,
		"max_reverb_step": max_reverb_step,
		"max_occlusion_step": max_occlusion_step,
		"max_route_weight_step": max_route_weight_step,
		"max_apparent_position_step": max_apparent_position_step,
		"worst_step": worst_step,
	}


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if failure_count == 0:
		print("Speaker cluster tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Speaker cluster tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

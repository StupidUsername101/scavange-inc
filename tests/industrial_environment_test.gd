extends SceneTree

const LAYOUT := preload("res://scripts/world/industrial_acoustic_complex_layout.gd")
const SERVER_COMPLEX_SCENE := preload("res://scenes/server/industrial_acoustic_complex.tscn")
const CLIENT_COMPLEX_SCENE := preload("res://scenes/proxy/industrial_acoustic_complex.tscn")
const SERVER_WORLD_PATH := "res://scenes/server/server_world.tscn"
const CLIENT_WORLD_PATH := "res://scenes/proxy/world.tscn"
const PISTOL_PATH := "res://resources/items/guns/basic_service_pistol.tres"
const GARAGE_LAYOUT := preload("res://scripts/world/speaker_cluster_demo_layout.gd")
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shared_layout_contract()
	await _test_server_and_client_environment()
	_test_active_world_replacement()
	_test_pistol_presentation_and_sound_registration()
	if failure_count == 0:
		print("Industrial environment tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Industrial environment tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_shared_layout_contract() -> void:
	var descriptors := LAYOUT.structural_boxes()
	var ramp_count := 0
	var tunnel_shell_count := LAYOUT.tunnel_structural_boxes().size()
	for descriptor: Dictionary in descriptors:
		var name := str(descriptor.get("name", ""))
		if name.begins_with("BuildingRamp"):
			ramp_count += 1
	_expect(
		LAYOUT.STOREY_COUNT >= 3 and ramp_count == LAYOUT.STOREY_COUNT - 1,
		"the replacement building has three accessible storeys and two continuous ramps"
	)
	var tread_descriptors := LAYOUT.stair_tread_boxes()
	var treads_are_horizontal := true
	for descriptor: Dictionary in tread_descriptors:
		treads_are_horizontal = (
			treads_are_horizontal
			and (descriptor.get("rotation", Vector3.ZERO) as Vector3)
			.is_zero_approx()
		)
	_expect(
		tread_descriptors.size()
		== (LAYOUT.STOREY_COUNT - 1) * LAYOUT.STAIR_TREAD_COUNT
		and LAYOUT.foot_contact_boxes().size()
		== (
			descriptors.size()
			+ tread_descriptors.size()
			+ LAYOUT.parkour_contact_detail_boxes().size()
		)
		and treads_are_horizontal,
		"smooth movement ramps expose generated horizontal presentation treads for procedural feet"
	)
	_expect(
		LAYOUT.TUNNEL_LENGTH >= 40.0
		and LAYOUT.tunnel_module_descriptors().size() == LAYOUT.TUNNEL_MODULE_COUNT
		and tunnel_shell_count
		== LAYOUT.TUNNEL_RUN_COUNT * LAYOUT.TUNNEL_MODULE_COUNT * 5
		and LAYOUT.TUNNEL_WIDTH >= 4.5
		and LAYOUT.WIDE_TUNNEL_DEFINITION.module_size().x > LAYOUT.TUNNEL_WIDTH
		and LAYOUT.HANGAR_TUNNEL_DEFINITION.module_size().x
		> LAYOUT.WIDE_TUNNEL_DEFINITION.module_size().x,
		"three eight-module bunker runs expose progressively larger clearances"
	)
	_expect(
		LAYOUT.building_floor_probe_positions().size() == LAYOUT.STOREY_COUNT
		and LAYOUT.building_room_probe_descriptors().size() == 24
		and LAYOUT.tunnel_probe_positions().size() >= 11,
		"shared layout exposes a dense room grid and a four-metre tunnel chain"
	)
	var hall_volume := (
		LAYOUT.LARGE_BUNKER_WIDTH
		* LAYOUT.LARGE_BUNKER_DEPTH
		* LAYOUT.LARGE_BUNKER_HEIGHT
	)
	var garage_volume := GARAGE_LAYOUT.WIDTH * GARAGE_LAYOUT.DEPTH * GARAGE_LAYOUT.HEIGHT
	var hall_structure_count := 0
	var valve_structure_count := 0
	var valve_material_is_authored := true
	for descriptor: Dictionary in descriptors:
		var descriptor_name := str(descriptor.get("name", ""))
		if descriptor_name.begins_with("LargeBunker"):
			hall_structure_count += 1
		elif descriptor_name.begins_with("ValveBunker"):
			valve_structure_count += 1
			valve_material_is_authored = (
				valve_material_is_authored
				and descriptor.get("acoustic_material")
				== LAYOUT.VALVE_REFERENCE_CONCRETE
			)
	_expect(
		hall_volume >= garage_volume * 8.0
		and hall_structure_count >= 14
		and valve_structure_count == hall_structure_count
		and LAYOUT.large_bunker_probe_descriptors().size() >= 40,
		"the industrial and Valve comparison bunkers share one large shell and probe layout"
	)
	_expect(
		valve_material_is_authored
		and LAYOUT.valve_bunker_probe_descriptors().size()
		== LAYOUT.large_bunker_probe_descriptors().size()
		and LAYOUT.VALVE_REFERENCE_CONCRETE.absorption.is_equal_approx(
			Vector3(0.05, 0.07, 0.08)
		)
		and is_equal_approx(LAYOUT.VALVE_REFERENCE_CONCRETE.scattering, 0.05)
		and LAYOUT.VALVE_REFERENCE_CONCRETE.transmission_gain.is_equal_approx(
			Vector3(0.015, 0.002, 0.001)
		),
		"the A/B room changes only to Valve's documented default-concrete surface coefficients"
	)
	var hall_speakers := LAYOUT.large_bunker_speaker_descriptors()
	var symmetric_inward_array := hall_speakers.size() == 4
	var hall_emitter_ids: Dictionary[int, bool] = {}
	for descriptor: Dictionary in hall_speakers:
		var position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var rotation: Vector3 = descriptor.get("rotation", Vector3.ZERO)
		var acoustic_center := Vector3(
			LAYOUT.LARGE_BUNKER_CENTER.x,
			position.y,
			LAYOUT.LARGE_BUNKER_CENTER.z
		)
		symmetric_inward_array = (
			symmetric_inward_array
			and bool(descriptor.get("inside", false))
			and (Basis.from_euler(rotation) * Vector3.FORWARD * -1.0).dot(
				(acoustic_center - position).normalized()
			) >= 0.999
		)
		hall_emitter_ids[int(descriptor.get("emitter_id", -1))] = true
	if hall_speakers.size() == 4:
		var west_position: Vector3 = hall_speakers[0].get("position", Vector3.ZERO)
		var east_position: Vector3 = hall_speakers[1].get("position", Vector3.ZERO)
		var south_position: Vector3 = hall_speakers[2].get("position", Vector3.ZERO)
		var north_position: Vector3 = hall_speakers[3].get("position", Vector3.ZERO)
		symmetric_inward_array = (
			symmetric_inward_array
			and ((west_position + east_position) * 0.5).is_equal_approx(
				LAYOUT.LARGE_BUNKER_CENTER + Vector3.UP * 4.2
			)
			and ((south_position + north_position) * 0.5).is_equal_approx(
				LAYOUT.LARGE_BUNKER_CENTER + Vector3.UP * 4.2
			)
		)
	_expect(
		symmetric_inward_array and hall_emitter_ids.size() == 4,
		"the large bunker owns exactly four unique wall-centred speakers facing symmetrically inward"
	)
	var hall_world_center_3d := LAYOUT.WORLD_POSITION + LAYOUT.LARGE_BUNKER_CENTER
	var hall_world_center := Vector2(hall_world_center_3d.x, hall_world_center_3d.z)
	var valve_world_center_3d := LAYOUT.WORLD_POSITION + LAYOUT.VALVE_BUNKER_CENTER
	var valve_world_center := Vector2(valve_world_center_3d.x, valve_world_center_3d.z)
	var parkour_world_center_3d := (
		LAYOUT.WORLD_POSITION + LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CENTER
	)
	var parkour_world_center := Vector2(
		parkour_world_center_3d.x,
		parkour_world_center_3d.z
	)
	var nature_clear := true
	var parkour_nature_clear := true
	for descriptor: Dictionary in NATURE_LAYOUT.visual_descriptors():
		var nature_position: Vector3 = descriptor.get("position", Vector3.ZERO)
		var hall_delta := Vector2(nature_position.x, nature_position.z) - hall_world_center
		var valve_delta := Vector2(nature_position.x, nature_position.z) - valve_world_center
		var parkour_delta := (
			Vector2(nature_position.x, nature_position.z) - parkour_world_center
		)
		if (
			absf(parkour_delta.x)
			<= LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CLEAR_HALF_EXTENTS.x
			and absf(parkour_delta.y)
			<= LAYOUT.MOVEMENT_PARKOUR_LAYOUT.CLEAR_HALF_EXTENTS.y
		):
			parkour_nature_clear = false
		if (
			absf(hall_delta.x) <= LAYOUT.LARGE_BUNKER_WIDTH * 0.5 + 1.0
			and absf(hall_delta.y) <= LAYOUT.LARGE_BUNKER_DEPTH * 0.5 + 1.0
		):
			nature_clear = false
			break
		if (
			absf(valve_delta.x) <= LAYOUT.LARGE_BUNKER_WIDTH * 0.5 + 1.0
			and absf(valve_delta.y) <= LAYOUT.LARGE_BUNKER_DEPTH * 0.5 + 1.0
		):
			nature_clear = false
			break
	_expect(
		nature_clear,
		"procedural nature leaves both A/B bunker shells and acoustic perimeters clear"
	)
	_expect(
		parkour_nature_clear,
		"procedural nature leaves the complete movement-lab clearance free"
	)
	var tunnel_acoustic_descriptors := LAYOUT.tunnel_acoustic_probe_descriptors()
	var acoustic_counts_by_run: Dictionary[StringName, Dictionary] = {}
	var aperture_spill_is_derived := true
	for descriptor: Dictionary in tunnel_acoustic_descriptors:
		var run_id: StringName = descriptor.get("run_id", &"tunnel")
		var role: StringName = descriptor.get("role", &"inside")
		var counts: Dictionary = acoustic_counts_by_run.get(run_id, {})
		counts[role] = int(counts.get(role, 0)) + 1
		acoustic_counts_by_run[run_id] = counts
		if role == &"south_outside" or role == &"north_outside":
			var spill_aperture: Vector2 = descriptor.get(
				"guided_spill_aperture_half_extents",
				Vector2.ZERO
			)
			var spill_origin_offset: Vector3 = descriptor.get(
				"guided_spill_origin_offset",
				Vector3.ZERO
			)
			var spill_axis: Vector3 = descriptor.get(
				"guided_spill_axis",
				Vector3.ZERO
			)
			var spill_divergence: Vector2 = descriptor.get(
				"guided_spill_divergence",
				Vector2.ZERO
			)
			aperture_spill_is_derived = (
				aperture_spill_is_derived
				and float(descriptor.get("environment_influence_radius", INF)) <= 8.0
				and spill_aperture.x > 0.0
				and spill_aperture.y > 0.0
				and spill_origin_offset.length() <= 2.01
				and is_equal_approx(spill_axis.length(), 1.0)
				and spill_divergence.x > 0.0
				and spill_divergence.y > 0.0
				and not descriptor.has("guided_influence_half_extents")
			)
	var every_run_has_perimeter_air := acoustic_counts_by_run.size() == LAYOUT.TUNNEL_RUN_COUNT
	for run: Dictionary in LAYOUT.tunnel_runs():
		var counts: Dictionary = acoustic_counts_by_run.get(
			run.get("run_id", &"tunnel"),
			{}
		)
		every_run_has_perimeter_air = (
			every_run_has_perimeter_air
			and int(counts.get(&"inside", 0)) == LAYOUT.tunnel_probe_positions().size()
			and int(counts.get(&"exterior_air", 0))
			== LAYOUT.tunnel_probe_positions().size() * 2 + 8
			and int(counts.get(&"south_outside", 0)) == 1
			and int(counts.get(&"north_outside", 0)) == 1
		)
	_expect(
		every_run_has_perimeter_air and aperture_spill_is_derived,
		"all modular tunnels derive widening aperture spill and collision-visible exterior air chains from one layout rule"
	)


func _test_server_and_client_environment() -> void:
	var server_complex := SERVER_COMPLEX_SCENE.instantiate() as StaticBody3D
	var client_complex := CLIENT_COMPLEX_SCENE.instantiate() as Node3D
	root.add_child(server_complex)
	root.add_child(client_complex)
	await physics_frame
	var tread_descriptors := LAYOUT.stair_tread_boxes()
	var first_tread: Dictionary = tread_descriptors.front()
	var final_tread: Dictionary = tread_descriptors.back()
	var tread_query := PhysicsRayQueryParameters3D.new()
	tread_query.collision_mask = CharacterContactLayers.FOOT_CONTACT_DETAIL
	var tread_contacts_are_discrete := true
	for tread: Dictionary in [first_tread, final_tread]:
		var tread_position: Vector3 = tread.get("position", Vector3.ZERO)
		var tread_size: Vector3 = tread.get("size", Vector3.ZERO)
		var expected_top := tread_position.y + tread_size.y * 0.5
		tread_query.from = tread_position + Vector3.UP
		tread_query.to = tread_position + Vector3.DOWN
		var hit := root.world_3d.direct_space_state.intersect_ray(tread_query)
		tread_contacts_are_discrete = (
			tread_contacts_are_discrete
			and not hit.is_empty()
			and absf((hit.get("position", Vector3.ZERO) as Vector3).y - expected_top)
			< 0.01
		)
	_expect(
		tread_contacts_are_discrete,
		"the production client world resolves first and final stair contacts on discrete tread tops"
	)
	var descriptors := LAYOUT.structural_boxes()
	var covered_structure_names: Dictionary[StringName, bool] = {}
	var single_shape_body_count := 0
	var static_body_count := 0
	for child: Node in server_complex.get_children():
		if not child is StaticBody3D:
			continue
		static_body_count += 1
		var body := child as StaticBody3D
		var body_collision_count := 0
		for body_child: Node in body.get_children():
			if body_child is CollisionShape3D:
				body_collision_count += 1
		if body_collision_count == 1:
			single_shape_body_count += 1
		for source_name: String in body.get_meta(
			&"collision_source_names",
			PackedStringArray()
		):
			covered_structure_names[StringName(source_name)] = true
	_expect(
		covered_structure_names.size()
		== descriptors.size() + LAYOUT.prop_descriptors().size()
		and single_shape_body_count == static_body_count,
		"every authored structure and prop is covered by one-shape broad-phase collision bodies"
	)
	var presentation_matches := true
	for descriptor: Dictionary in descriptors:
		if not bool(descriptor.get("visual", true)):
			continue
		if client_complex.get_node_or_null(str(descriptor.get("name", ""))) == null:
			presentation_matches = false
			break
	var every_tunnel_rendered := true
	for run: Dictionary in LAYOUT.tunnel_runs():
		var tunnel_modules := client_complex.get_node_or_null(
			str(run.get("container_name", &""))
		)
		if (
			tunnel_modules == null
			or tunnel_modules.get_child_count() != LAYOUT.TUNNEL_MODULE_COUNT
		):
			every_tunnel_rendered = false
	_expect(
		presentation_matches
		and every_tunnel_rendered,
		"client presentation renders every module in all three scaled bunker runs"
	)
	var prop_presentation_matches := true
	var wide_tunnel_prop_count := 0
	var hangar_tunnel_prop_count := 0
	for descriptor: Dictionary in LAYOUT.prop_descriptors():
		var prop_name := str(descriptor.get("name", ""))
		if prop_name.begins_with("WideTunnel"):
			wide_tunnel_prop_count += 1
		elif prop_name.begins_with("HangarTunnel"):
			hangar_tunnel_prop_count += 1
		if (
			client_complex.get_node_or_null(prop_name) == null
			or server_complex.find_child(prop_name + "Collision", true, false) == null
		):
			prop_presentation_matches = false
			break
	_expect(
		prop_presentation_matches
		and wide_tunnel_prop_count >= 8
		and hangar_tunnel_prop_count >= 8,
		"both comparison tunnels have curated collision-backed prop layouts"
	)
	var server_hall_array := server_complex.get_node_or_null(
		"LargeBunkerSpeakerArray"
	) as ServerSpeakerCluster
	var client_hall_array := client_complex.get_node_or_null(
		"LargeBunkerSpeakerArray"
	) as SpeakerClusterDemoProxy
	var server_valve_array := server_complex.get_node_or_null(
		"ValveReferenceBunkerSpeakerArray"
	) as ServerSpeakerCluster
	var client_valve_array := client_complex.get_node_or_null(
		"ValveReferenceBunkerSpeakerArray"
	) as SpeakerClusterDemoProxy
	var hall_cones := (
		client_hall_array.find_children("SpeakerCone", "MeshInstance3D", true, false)
		if client_hall_array != null
		else []
	)
	_expect(
		server_hall_array != null
		and client_hall_array != null
		and server_hall_array.get_emitter_ids().size() == 4
		and hall_cones.size() == 4
		and not server_hall_array.powered
		and server_hall_array.current_song_path.is_empty()
		and server_valve_array != null
		and client_valve_array != null
		and server_valve_array.get_emitter_ids().size() == 4
		and client_valve_array.find_children("SpeakerCone", "MeshInstance3D", true, false).size() == 4
		and not server_valve_array.powered
		and server_valve_array.current_song_path.is_empty(),
		"both A/B bunker arrays expose four physical cabinets and start silent"
	)

	var probe_count := 0
	var portal_count := 0
	for child: Node in server_complex.get_children():
		if child is AcousticProbe3D:
			probe_count += 1
		elif child is AcousticPortal3D:
			portal_count += 1
	_expect(
		probe_count >= LAYOUT.STOREY_COUNT + 30 and portal_count >= 7,
		"storeys and all six tunnel mouths are represented in the acoustic graph"
	)

	var acoustic_service := ServerAcousticService.new()
	root.add_child(acoustic_service)
	acoustic_service.bind_world(server_complex)
	await process_frame
	await physics_frame
	var tunnel_probe := acoustic_service.graph.find_nearest_probe(LAYOUT.TUNNEL_CENTER + Vector3(0.0, 2.0, 0.0))
	var tunnel_response := acoustic_service.graph.environment_response(tunnel_probe)
	_expect(
		float(tunnel_response.get("reverb_send", 0.0)) > 0.25
		and float(tunnel_response.get("reverb_spread", 1.0)) < 0.9
		and float(tunnel_response.get("guided_propagation", 0.0)) > 0.5,
		"authored tunnel geometry produces a strong, narrowed and energy-preserving hall response"
	)
	var hall_probe := acoustic_service.graph.find_nearest_probe(
		LAYOUT.LARGE_BUNKER_CENTER + Vector3(0.0, LAYOUT.LARGE_BUNKER_PROBE_HEIGHT, 0.0)
	)
	var hall_response := acoustic_service.graph.environment_response(hall_probe)
	var valve_probe := acoustic_service.graph.find_nearest_probe(
		LAYOUT.VALVE_BUNKER_CENTER + Vector3(0.0, LAYOUT.LARGE_BUNKER_PROBE_HEIGHT, 0.0)
	)
	var valve_response := acoustic_service.graph.environment_response(valve_probe)
	print(
		"Large bunker response: send=%.3f decay=%.3f size=%.3f enclosure=%.3f spread=%.3f"
		% [
			float(hall_response.get("reverb_send", 0.0)),
			float(hall_response.get("rt60_seconds", 0.0)),
			float(hall_response.get("reverb_room_size", 0.0)),
			float(hall_response.get("enclosure", 0.0)),
			float(hall_response.get("reverb_spread", 0.0)),
		]
	)
	_expect(
		hall_probe >= 0
		and float(hall_response.get("reverb_send", 0.0)) > 0.25
		and float(hall_response.get("rt60_seconds", 0.0)) > 1.2
		and float(hall_response.get("reverb_room_size", 0.0)) > 0.55
		and float(hall_response.get("enclosure", 0.0)) > 0.65,
		"the large sealed volume bakes a long, enclosed room response instead of garage-sized acoustics"
	)
	_expect(
		valve_probe >= 0
		and float(valve_response.get("rt60_seconds", 0.0))
		> float(hall_response.get("rt60_seconds", 0.0))
		and float(valve_response.get("enclosure", 0.0)) > 0.65,
		"Valve's less absorptive concrete produces the longer late field in otherwise identical geometry"
	)
	var hybrid_listener := LAYOUT.VALVE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0)
	var hybrid_source := LAYOUT.VALVE_BUNKER_CENTER + Vector3(-12.0, 4.2, 0.0)
	var rollback_sample := acoustic_service.calculate_listener_result(
		53000,
		hybrid_listener,
		hybrid_source,
		90.0,
		null,
		1.0,
		true,
		[],
		53001
	)
	acoustic_service.configure_hybrid_early_reflections(true)
	var enabled_continuous_sample := acoustic_service.calculate_listener_result(
		53002,
		hybrid_listener,
		hybrid_source,
		90.0,
		null,
		1.0,
		true,
		[],
		53003
	)
	var enabled_one_shot_sample := acoustic_service.calculate_listener_result(
		53004,
		hybrid_listener,
		hybrid_source,
		90.0
	)
	_expect(
		not rollback_sample.has("early_reflections")
		and not (enabled_continuous_sample.get("early_reflections", []) as Array).is_empty()
		and not (enabled_one_shot_sample.get("early_reflections", []) as Array).is_empty(),
		"one rollback switch hooks the hybrid into both continuous and one-shot server packets"
	)
	var current_taps := acoustic_service.static_boundary_bake.sample_early_reflections(
		LAYOUT.LARGE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0),
		LAYOUT.LARGE_BUNKER_CENTER + Vector3(-12.0, 4.2, 0.0),
		12.257650
	)
	var valve_taps := acoustic_service.static_boundary_bake.sample_early_reflections(
		LAYOUT.VALVE_BUNKER_CENTER + Vector3(0.0, 1.7, 0.0),
		LAYOUT.VALVE_BUNKER_CENTER + Vector3(-12.0, 4.2, 0.0),
		12.257650
	)
	var current_tap_gain := 0.0
	for tap: Dictionary in current_taps:
		current_tap_gain += float(tap.get("gain", 0.0))
	var valve_tap_gain := 0.0
	for tap: Dictionary in valve_taps:
		valve_tap_gain += float(tap.get("gain", 0.0))
	_expect(
		not current_taps.is_empty()
		and not valve_taps.is_empty()
		and current_taps.size() <= AcousticEventPacket.MAX_EARLY_REFLECTIONS
		and valve_tap_gain > current_tap_gain,
		"the baked hybrid resolves stronger bounded early taps from Valve concrete without runtime ray fans"
	)
	var hall_north_outside := LAYOUT.LARGE_BUNKER_CENTER + Vector3(
		0.0,
		1.7,
		LAYOUT.LARGE_BUNKER_DEPTH * 0.5 + 1.2
	)
	var hall_outdoor_sample := acoustic_service.calculate_listener_result(
		51998,
		hall_north_outside,
		hall_north_outside + Vector3(3.0, 0.0, 0.0),
		30.0,
		null,
		1.0,
		true,
		[],
		51999
	)
	_expect(
		bool(hall_outdoor_sample.get("audible", false))
		and float(hall_outdoor_sample.get("environment_enclosure", 1.0)) < 0.15
		and float(hall_outdoor_sample.get("reverb_send", 1.0)) < 0.08,
		"an outdoor listener beside the large shell cannot inherit the indoor probe field through concrete"
	)
	var hall_speaker_descriptor: Dictionary = (
		LAYOUT.large_bunker_speaker_descriptors()[0]
	)
	var hall_source := LAYOUT.large_bunker_speaker_source_local_position(
		hall_speaker_descriptor
	)
	var hall_doorway_max_level_step_db := 0.0
	var hall_doorway_max_reverb_step := 0.0
	var hall_doorway_all_audible := true
	var previous_hall_level_db := NAN
	var previous_hall_reverb := NAN
	for sample_index: int in range(57):
		var listener_position := LAYOUT.LARGE_BUNKER_CENTER + Vector3(
			23.0 - float(sample_index) * 0.25,
			1.7,
			0.0
		)
		var sample := acoustic_service.calculate_listener_result(
			52000,
			listener_position,
			hall_source,
			90.0,
			null,
			1.0,
			true,
			[],
			52001
		)
		hall_doorway_all_audible = (
			hall_doorway_all_audible and bool(sample.get("audible", false))
		)
		var level_db := float(sample.get("volume_db", -80.0))
		var reverb_send := float(sample.get("reverb_send", 0.0))
		if is_finite(previous_hall_level_db):
			hall_doorway_max_level_step_db = maxf(
				hall_doorway_max_level_step_db,
				absf(level_db - previous_hall_level_db)
			)
			hall_doorway_max_reverb_step = maxf(
				hall_doorway_max_reverb_step,
				absf(reverb_send - previous_hall_reverb)
			)
		previous_hall_level_db = level_db
		previous_hall_reverb = reverb_send
	print(
		"Large bunker doorway: audible=%s max level step=%.3f dB max reverb step=%.3f"
		% [
			str(hall_doorway_all_audible),
			hall_doorway_max_level_step_db,
			hall_doorway_max_reverb_step,
		]
	)
	_expect(
		hall_doorway_all_audible
		and hall_doorway_max_level_step_db < 1.5
		and hall_doorway_max_reverb_step < 0.08,
		"quarter-metre movement through the large doorway keeps both dry level and long hall onset continuous"
	)
	var side_stripe_largest_step_db := 0.0
	var side_stripe_routes_are_visible := true
	var side_stripe_listener_id := 46000
	for scan: Dictionary in [
		{"min_x": 3.8, "max_x": 5.2, "z": 20.22},
		{"min_x": -1.2, "max_x": -0.3, "z": 22.76},
	]:
		var previous_level_db := NAN
		var sample_count := roundi(
			(float(scan.get("max_x", 0.0)) - float(scan.get("min_x", 0.0)))
			/ 0.01
		) + 1
		for sample_index: int in range(sample_count):
			var listener_position := Vector3(
				float(scan.get("min_x", 0.0)) + float(sample_index) * 0.01,
				1.7,
				float(scan.get("z", 0.0))
			)
			var side_result := acoustic_service.calculate_listener_result(
				side_stripe_listener_id,
				listener_position,
				LAYOUT.TUNNEL_CENTER + Vector3(0.0, 1.7, 0.0),
				80.0,
				null,
				1.0,
				false,
				[],
				4600
			)
			var side_field := acoustic_service._fields_by_listener.get(
				side_stripe_listener_id
			) as AcousticPropagationField
			side_stripe_routes_are_visible = (
				side_stripe_routes_are_visible
				and bool(side_result.get("audible", false))
				and side_field != null
				and side_field.listener_probe_visibility_confirmed
			)
			var level_db := float(side_result.get("volume_db", -80.0))
			if is_finite(previous_level_db):
				side_stripe_largest_step_db = maxf(
					side_stripe_largest_step_db,
					absf(level_db - previous_level_db)
				)
			previous_level_db = level_db
			side_stripe_listener_id += 1
	_expect(
		side_stripe_routes_are_visible and side_stripe_largest_step_db <= 0.75,
		"centimetre samples beside the tunnel use visible perimeter air and contain no fallback loud stripe"
	)
	var wider_runs_propagate := true
	for run_index: int in range(1, LAYOUT.TUNNEL_RUN_COUNT):
		var run_positions := LAYOUT.tunnel_probe_positions(run_index)
		var center_position := run_positions[run_positions.size() / 2]
		var center_probe := acoustic_service.graph.find_nearest_probe(center_position)
		var center_response := acoustic_service.graph.environment_response(center_probe)
		var run_result := acoustic_service.calculate_listener_result(
			480 + run_index,
			run_positions[0],
			run_positions[run_positions.size() - 1],
			42.0,
			null,
			1.0,
			false,
			[],
			4800 + run_index
		)
		print(
			"Scaled tunnel %s: guided=%.3f reverb=%.3f gain=%.2f audible=%s"
			% [
				str(LAYOUT.tunnel_runs()[run_index].get("run_id", &"tunnel")),
				float(center_response.get("guided_propagation", 0.0)),
				float(center_response.get("reverb_send", 0.0)),
				float(run_result.get("guided_propagation_gain_db", 0.0)),
				str(run_result.get("audible", false)),
			]
		)
		wider_runs_propagate = (
			wider_runs_propagate
			and center_probe >= 0
			and float(center_response.get("guided_propagation", 0.0)) > 0.35
			and float(center_response.get("reverb_send", 0.0)) > 0.2
			and bool(run_result.get("audible", false))
			and float(run_result.get("guided_propagation_gain_db", 0.0)) > 4.0
		)
	_expect(
		wider_runs_propagate,
		"both wider shells produce sampled tunnel response and guided end-to-end propagation"
	)
	var tunnel_positions := LAYOUT.tunnel_probe_positions()
	var tunnel_listener := tunnel_positions[0]
	var tunnel_source := tunnel_positions[tunnel_positions.size() - 1]
	var tunnel_result := acoustic_service.calculate_listener_result(
		501,
		tunnel_listener,
		tunnel_source,
		42.0
	)
	var open_result := AcousticPropagationGraph.sample_free_field(
		tunnel_listener,
		tunnel_source,
		80.0
	)
	_expect(
		bool(tunnel_result.get("audible", false))
		and float(tunnel_result.get("guided_propagation_gain_db", 0.0)) > 10.0
		and float(tunnel_result.get("volume_db", -80.0))
		> float(open_result.get("volume_db", 0.0)) + 10.0,
		"the rebuilt server graph keeps a source clearly audible across the tunnel"
	)
	var house_listener: Vector3 = LAYOUT.building_floor_probe_positions()[0]
	var tunnel_to_house := acoustic_service.calculate_listener_result(
		502,
		house_listener,
		tunnel_positions[tunnel_positions.size() / 2],
		120.0,
		null,
		1.0,
		false,
		[],
		5002
	)
	var house_field := acoustic_service._fields_by_listener.get(
		502
	) as AcousticPropagationField
	_expect(
		bool(tunnel_to_house.get("audible", false))
		and house_field != null
		and float(tunnel_to_house.get("source_reverb_spill_send", 0.0)) < 0.02
		and absf(
			float(tunnel_to_house.get("reverb_room_size", -1.0))
			- house_field.environment_room_size
		) < 0.05
		and absf(
			float(tunnel_to_house.get("reverb_spread", -1.0))
			- house_field.environment_spread
		) < 0.08
		and absf(
			float(tunnel_to_house.get("reverb_decay_seconds", -1.0))
			- house_field.environment_rt60_seconds
		) < 0.15,
		"a tunnel radio heard from inside the building keeps the building's late-reverb signature"
	)
	var debug_state := acoustic_service.get_debug_state()
	_expect(
		int(debug_state.get("environment_ray_count", 0)) > 0
		and int(debug_state.get("tunnel_probe_count", 0)) > 0
		and int(debug_state.get("probe_count", 0)) >= 45,
		"the server rebuild samples the new environment and recognizes elongated probe regions"
	)
	var building_source := LAYOUT.BUILDING_CENTER + Vector3(
		0.0,
		LAYOUT.STOREY_HEIGHT * 2.0 + 1.45,
		0.0
	)
	var building_volumes := PackedFloat32Array()
	for sample_index: int in range(19):
		var listener_position := LAYOUT.BUILDING_CENTER + Vector3(
			0.0,
			1.45,
			-4.5 + float(sample_index) * 0.5
		)
		var sample := acoustic_service.calculate_listener_result(
			601,
			listener_position,
			building_source,
			80.0,
			null,
			1.0,
			false,
			[],
			6001
		)
		building_volumes.append(float(sample.get("volume_db", -80.0)))
	var largest_building_step := 0.0
	var quietest_building_sample := 0.0
	if not building_volumes.is_empty():
		quietest_building_sample = building_volumes[0]
	for sample_index: int in range(1, building_volumes.size()):
		largest_building_step = maxf(
			largest_building_step,
			absf(building_volumes[sample_index] - building_volumes[sample_index - 1])
		)
		quietest_building_sample = minf(
			quietest_building_sample,
			building_volumes[sample_index]
		)
	_expect(
		building_volumes.size() == 19
		and quietest_building_sample > -40.0
		and largest_building_step < 0.5,
		"dense room probes keep half-metre indoor movement below a half-decibel loudness step"
	)
	var spill_volumes := PackedFloat32Array()
	for listener_z: float in range(-13, -45, -1):
		var spill := acoustic_service.calculate_listener_result(
			602,
			Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, listener_z),
			tunnel_positions[tunnel_positions.size() - 1],
			42.0,
			null,
			1.0,
			false,
			[],
			6002
		)
		spill_volumes.append(float(spill.get("volume_db", -80.0)))
	var largest_audible_spill_step := 0.0
	for sample_index: int in range(1, spill_volumes.size()):
		if maxf(spill_volumes[sample_index], spill_volumes[sample_index - 1]) > -60.0:
			largest_audible_spill_step = maxf(
				largest_audible_spill_step,
				absf(spill_volumes[sample_index] - spill_volumes[sample_index - 1])
			)
	print(
		"Tunnel mouth curve: near %.2f dB, 9 m %.2f dB, 17 m %.2f dB, far %.2f dB, max step %.2f dB"
		% [
			spill_volumes[0],
			spill_volumes[9],
			spill_volumes[17],
			spill_volumes[spill_volumes.size() - 1],
			largest_audible_spill_step,
		]
	)
	_expect(
		spill_volumes.size() == 32
		and spill_volumes[0] > -30.0
		and spill_volumes[17] < spill_volumes[0] - 2.0
		and spill_volumes[17] > spill_volumes[0] - 25.0
		and spill_volumes[spill_volumes.size() - 1] <= -70.0
		and largest_audible_spill_step < 4.0,
		"tunnel-mouth energy decays gradually through its useful lobe, then returns smoothly to the quiet fade floor"
	)
	var tunnel_mouth_source := Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, -8.0)
	var tunnel_mouth_listener := Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, -14.0)
	var tunnel_mouth_reverb := acoustic_service.calculate_listener_result(
		603,
		tunnel_mouth_listener,
		tunnel_mouth_source,
		80.0,
		null,
		1.0,
		false,
		[],
		6003
	)
	_expect(
		float(tunnel_mouth_reverb.get("source_reverb_spill_send", 0.0)) > 0.05
		and float(tunnel_mouth_reverb.get("reverb_send", 0.0)) > 0.08
		and float(tunnel_mouth_reverb.get("reverb_spread", 1.0)) < 0.9
		and float(tunnel_mouth_reverb.get("reverb_decay_seconds", 0.0)) > 0.3,
		"the tunnel's baked late field radiates through its open mouth into nearby open air"
	)
	var tunnel_north_reverb := acoustic_service.calculate_listener_result(
		605,
		Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, 38.0),
		Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, 32.0),
		80.0,
		null,
		1.0,
		false,
		[],
		6005
	)
	_expect(
		float(tunnel_north_reverb.get("source_reverb_spill_send", 0.0)) > 0.05
		and absf(
			float(tunnel_north_reverb.get("reverb_send", 0.0))
			- float(tunnel_mouth_reverb.get("reverb_send", 0.0))
		) < 0.08,
		"both open tunnel mouths radiate comparable late fields"
	)
	var tunnel_side_reverb := acoustic_service.calculate_listener_result(
		604,
		Vector3(
			LAYOUT.TUNNEL_CENTER.x + LAYOUT.TUNNEL_WIDTH * 0.5 + 0.6,
			1.7,
			-6.0
		),
		tunnel_mouth_source,
		80.0,
		null,
		1.0,
		false,
		[],
		6004
	)
	_expect(
		float(tunnel_side_reverb.get("source_reverb_spill_send", 0.0))
		< float(tunnel_mouth_reverb.get("source_reverb_spill_send", 0.0)) * 0.5
		and float(tunnel_side_reverb.get("reverb_send", 0.0))
		< float(tunnel_mouth_reverb.get("reverb_send", 0.0)),
		"a side-wall route receives only the weaker tail that diffracts around the tunnel mouth"
	)
	var entrance_source := Vector3(LAYOUT.TUNNEL_CENTER.x, 1.7, -11.0)
	var outward_level_is_monotonic := true
	var outward_directions: Array[Vector3] = [
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.5, 0.0, -1.0).normalized(),
		Vector3(1.0, 0.0, -1.0).normalized(),
		Vector3(2.0, 0.0, -1.0).normalized(),
	]
	for direction_index: int in range(outward_directions.size()):
		var previous_level_db := INF
		for distance_m: int in range(3, 61):
			var entrance_sample := acoustic_service.calculate_listener_result(
				610 + direction_index,
				entrance_source + outward_directions[direction_index] * float(distance_m),
				entrance_source,
				42.0,
				null,
				1.0,
				false,
				[],
				6100 + direction_index
			)
			var level_db := float(entrance_sample.get("volume_db", -80.0))
			if level_db > previous_level_db + 0.05:
				outward_level_is_monotonic = false
			previous_level_db = level_db
	_expect(
		outward_level_is_monotonic,
		"every clear ray leaving the tunnel mouth loses level monotonically with distance"
	)
	var side_wall_shortcuts_guided_energy := false
	for listener_z: float in range(-6, 31, 2):
		var side_listener := Vector3(
			LAYOUT.TUNNEL_CENTER.x + LAYOUT.TUNNEL_WIDTH * 0.5 + 0.6,
			1.7,
			listener_z
		)
		var side_sample := acoustic_service.calculate_listener_result(
			620,
			side_listener,
			entrance_source,
			80.0,
			null,
			1.0,
			false,
			[],
			6200
		)
		if (
			float(side_sample.get("guided_propagation_gain_db", 0.0)) > 0.05
			and float(side_sample.get("path_length", 0.0))
			<= side_listener.distance_to(entrance_source) + 0.5
		):
			side_wall_shortcuts_guided_energy = true
	_expect(
		not side_wall_shortcuts_guided_energy,
		"guided side-wall energy must take the longer route around a real tunnel opening"
	)
	var server_player := (
		load("res://scenes/server/server_player.tscn") as PackedScene
	).instantiate() as ServerPlayer
	root.add_child(server_player)
	server_player.global_position = Vector3(3.0, 1.0, -2.0)
	server_player.rotation.y = 0.0
	var listener_before_turn := server_player.get_audio_listener_position()
	server_player.rotation.y = PI
	var listener_after_turn := server_player.get_audio_listener_position()
	var player_proxy := (
		load("res://scenes/proxy/player_proxy.tscn") as PackedScene
	).instantiate() as Node3D
	root.add_child(player_proxy)
	await process_frame
	var client_listener := player_proxy.get_node_or_null(
		"AudioListener3D"
	) as AudioListener3D
	var client_before_turn := (
		client_listener.global_position
		if client_listener != null
		else Vector3.INF
	)
	player_proxy.rotation.y = PI
	var client_after_turn := (
		client_listener.global_position
		if client_listener != null
		else Vector3.ZERO
	)
	_expect(
		listener_before_turn.distance_to(listener_after_turn) < 0.0001
		and client_listener != null
		and client_before_turn.distance_to(client_after_turn) < 0.0001,
		"turning in place rotates hearing direction without orbiting either server or client ears"
	)
	server_player.queue_free()
	player_proxy.queue_free()
	acoustic_service.queue_free()
	server_complex.queue_free()
	client_complex.queue_free()
	await process_frame


func _test_active_world_replacement() -> void:
	# Load autoload-dependent world scenes after project initialization. Preloading them while this
	# SceneTree script is parsed runs before Server/Client singleton identifiers are registered.
	var server_world := (load(SERVER_WORLD_PATH) as PackedScene).instantiate()
	var client_world := (load(CLIENT_WORLD_PATH) as PackedScene).instantiate()
	var server_environment := server_world.get_node_or_null("IndustrialAcousticComplex") as Node3D
	var client_environment := client_world.get_node_or_null("IndustrialAcousticComplex") as Node3D
	_expect(
		server_world.get_node_or_null("DevZoo") == null
		and client_world.get_node_or_null("DevZoo") == null,
		"the active server and client worlds no longer instantiate the legacy enemy zoo"
	)
	_expect(
		server_environment != null
		and client_environment != null
		and server_environment.transform == client_environment.transform,
		"server collision and client presentation instantiate the replacement at the same transform"
	)
	server_world.free()
	client_world.free()


func _test_pistol_presentation_and_sound_registration() -> void:
	var pistol := load(PISTOL_PATH) as GunItemDefinition
	var state := pistol.make_default_instance_state() if pistol != null else {}
	var visual := (
		pistol.instantiate_held_visual(state, true)
		if pistol != null
		else null
	)
	_expect(
		visual != null
		and visual.get_node_or_null("Slide") != null
		and visual.get_node_or_null("SlideNose") != null
		and visual.get_node_or_null("ReceiverFrame") != null
		and visual.get_node_or_null("TriggerGuard") != null
		and visual.get_node_or_null("EjectionPort") != null,
		"service pistol presentation has a shaped slide, frame, trigger guard and ejection detail"
	)
	if visual != null:
		var slide := visual.get_node_or_null("Slide") as MeshInstance3D
		var barrel := visual.get_node_or_null("Barrel") as MeshInstance3D
		var slide_material := (
			slide.mesh.surface_get_material(0) as StandardMaterial3D
			if slide != null and slide.mesh != null
			else null
		)
		var slide_bounds := (
			slide.transform * slide.mesh.get_aabb()
			if slide != null and slide.mesh != null
			else AABB()
		)
		var barrel_bounds := (
			barrel.transform * barrel.mesh.get_aabb()
			if barrel != null and barrel.mesh != null
			else AABB()
		)
		_expect(
			slide_material != null
			and slide_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and slide_material.cull_mode == BaseMaterial3D.CULL_DISABLED
			and barrel_bounds.end.z < slide_bounds.position.z,
			"pistol slide is opaque and its visible barrel no longer intersects the closed shell"
		)
	if visual != null:
		visual.free()
	var sound_profile := (
		pistol.default_build.get_fire_sound_profile()
		if pistol != null and pistol.default_build != null
		else {}
	)
	_expect(
		sound_profile.get("sound_id", &"") == &"service_pistol_fire"
		and float(sound_profile.get("max_distance", 0.0)) >= 100.0,
		"service receiver publishes an authoritative long-range semantic gunshot"
	)
	var sound_spec: Dictionary = {}
	for candidate: Dictionary in GameAudioLibrary.WEAPON_REPORT_SPECS:
		if candidate.get("id", &"") == &"service_pistol_fire":
			sound_spec = candidate
			break
	_expect(
		not sound_spec.is_empty()
		and (sound_spec.get("streams", []) as Array).size() == 4
		and (sound_spec.get("pressure_streams", []) as Array).size() == 4,
		"shared client catalog registers four dry pistol reports and four pressure transients"
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)

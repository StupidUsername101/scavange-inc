extends SceneTree

const EPSILON := 0.0001
const NATURE_LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const SPEAKER_CLUSTER_LAYOUT := preload(
	"res://scripts/world/speaker_cluster_demo_layout.gd"
)
const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)

# Normative acoustic rule contract. Every entry must be satisfied by a behavioral assertion in
# this file; _assert_complete_rule_coverage fails when a future edit adds or forgets one. Detailed
# implementation notes live in scripts/audio/README.md, but this is the compact regression contract.
const ACOUSTIC_RULE_CONTRACT: Array[Dictionary] = [
	{"id": &"A01", "rule": "Only authoritative semantic events cross the sanitized network boundary."},
	{"id": &"A02", "rule": "Source level changes physical reach; roughly +6.02 dB doubles it."},
	{"id": &"A03", "rule": "Distance, air loss, and speed-of-sound delay remain physical and continuous."},
	{"id": &"A04", "rule": "Structural paths apply material-dependent nonlinear band transmission."},
	{"id": &"A05", "rule": "Small props partially occlude direct sound but cannot erase a room field."},
	{"id": &"A06", "rule": "Surface responses are baked at graph rebuild and reused at runtime."},
	{"id": &"A07", "rule": "Late reverb belongs to the listener space; open air does not inherit a source room."},
	{"id": &"A08", "rule": "Rooms, tunnels, and outdoor scatter derive from the same sampled-geometry rule."},
	{"id": &"A09", "rule": "Guided tunnel energy is bounded by its volume, then radiates as a continuous widening aperture lobe."},
	{"id": &"A10", "rule": "Impactful one-shots use one bounded baked pressure response; zero opts out."},
	{"id": &"A11", "rule": "Clients use fixed pooled voices/DSP and only replay dedicated pressure layers."},
	{"id": &"A12", "rule": "Parallel direct and diffracted paths add energy; finite-edge changes crossfade instead of electing a winner."},
	{"id": &"A13", "rule": "Independent audible sources occupy independent voices and add in the mix."},
	{"id": &"A14", "rule": "Nature creates a short forest response while one slender trunk only partly covers a direct wave."},
	{"id": &"A15", "rule": "Pistol and rifle reports share server propagation and client pressure handling."},
	{"id": &"A16", "rule": "A shared room sums direct and diffuse energy, then loses only about 1 dB per far-field doubling."},
	{"id": &"A17", "rule": "Sustained brilliance may bloom in a reflective enclosure, but never outdoors or beyond the normalized mix budget."},
	{"id": &"A18", "rule": "Every source caches collision-visible air endpoints; no emitter-specific probe or blocked centre-ray collapse is allowed."},
	{"id": &"A19", "rule": "Continuous multi-speaker safety catches only digital overs and does not pre-compress ordinary program bass."},
	{"id": &"A20", "rule": "Cabinets carrying one synchronized program phase-align and energy-normalize instead of comb-filtering or coherently over-gaining."},
	{"id": &"A21", "rule": "Non-audio systems receive one bounded listener activity signal derived only from post-propagation sound energy."},
	{"id": &"A22", "rule": "A live reverb may morph its response but never resize populated stereo delay lines."},
	{"id": &"A23", "rule": "Indirect sound begins only at collision-visible listener air probes; hidden fallback anchors are never audible."},
	{"id": &"A24", "rule": "Cached route refreshes crossfade one wavefront estimate without adding duplicate-route energy."},
	{"id": &"A25", "rule": "Continuous sources dezipper server output across spatial route changes; one-shots and teleports remain immediate."},
	{"id": &"A26", "rule": "Baked path bends apply bounded frequency-dependent deviation after route election; straight paths remain neutral."},
	{"id": &"A27", "rule": "Distinct early routes add before one listener-space diffuse field is attached."},
	{"id": &"A29", "rule": "A synchronized array uses path-direct energy for cabinet direction while diffuse recovery remains listener-space energy."},
]

var failure_count := 0
var assertion_count := 0
var network_packet_received := false
var automatic_pressure_network_packet_received := false
var pressure_network_packet_received := false
var disabled_pressure_network_packet_received := false
var fieldlink_network_packet_received := false
var quiet_range_network_packet_received := false
var loud_range_network_packet_received := false
var pistol_acoustic_packet: Dictionary = {}
var rifle_acoustic_packet: Dictionary = {}
var _satisfied_acoustic_rules: Dictionary[StringName, bool] = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_listener_centered_wavefront()
	_test_path_deviation_response()
	_test_environment_response_math()
	_test_full_occlusion_control_continuity()
	_test_spectral_room_bloom_math()
	_test_continuous_mix_safety()
	_test_listener_acoustic_activity()
	_test_direct_and_diffuse_room_energy()
	_test_baked_pressure_propagation()
	_test_listener_room_owns_late_reverb()
	_test_free_field_and_packet_safety()
	_test_continuous_distance_updates()
	_test_multi_probe_listener_boundary()
	_test_parallel_route_energy_mix()
	_test_parallel_routes_share_one_diffuse_field()
	_test_client_voice_renderer()
	_test_dev_warehouse_material_authoring()
	await _test_direct_path_collision_bypass_and_cache()
	await _test_listener_probe_blend_respects_walls()
	await _test_hidden_listener_fallback_is_silent()
	await _test_authored_house_propagation()
	await _test_scene_graph_rebuild()
	await _test_server_world_binding()
	_test_fixed_source_air_route()
	_test_nature_acoustic_registration()
	await _test_server_to_client_bridge()
	_assert_complete_rule_coverage()
	if failure_count == 0:
		print(
			"Acoustic propagation tests passed: %d assertions"
			% assertion_count
		)
		quit(0)
	else:
		push_error(
			"Acoustic propagation tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_listener_centered_wavefront() -> void:
	var graph := AcousticPropagationGraph.new()
	var listener_probe := graph.add_probe(Vector3.ZERO, &"listener")
	var doorway_probe := graph.add_probe(Vector3(0.0, 0.0, 5.0), &"door")
	var source_probe := graph.add_probe(Vector3(5.0, 0.0, 5.0), &"source")
	graph.connect_probes(listener_probe, doorway_probe)

	var steel := AcousticMaterial.new()
	steel.material_id = &"steel_wall"
	steel.transmission_gain = Vector3(0.58, 0.16, 0.035)
	steel.transmission_volume_db = -5.0
	steel.transmission_lowpass_hz = 2600.0
	steel.resonance = 0.35
	steel.reverb_send = 0.22
	graph.connect_probes(
		doorway_probe,
		source_probe,
		steel.create_transmission_modifier()
	)

	var concrete := AcousticPathModifier.new()
	concrete.modifier_id = &"concrete_shortcut"
	concrete.band_gain = Vector3(0.03, 0.005, 0.001)
	concrete.volume_db = -16.0
	concrete.lowpass_hz = 900.0
	graph.connect_probes(listener_probe, source_probe, concrete)

	var field := AcousticPropagationField.new()
	graph.solve_from_position(Vector3.ZERO, field)
	var result := graph.sample_source(
		field,
		Vector3(5.0, 0.0, 5.0),
		50.0
	)
	_expect(bool(result.get("audible", false)), "connected source is audible")
	_expect(
		absf(float(result.get("path_length", 0.0)) - 10.0) < EPSILON,
		"dominant path prefers the longer audible doorway route"
	)
	_expect(
		absf(
			float(result.get("travel_delay_seconds", 0.0))
			- 10.0 / AcousticPropagationGraph.SPEED_OF_SOUND_METERS_PER_SECOND
		) < EPSILON,
		"server result carries physical path delay"
	)
	var band_gain: Vector3 = result.get("band_gain", Vector3.ONE)
	_expect_rule(&"A04",
		band_gain.x > band_gain.y and band_gain.y > band_gain.z,
		"steel transmits low frequencies more strongly than highs"
	)
	_expect(
		is_equal_approx(float(result.get("lowpass_hz", 0.0)), 2600.0),
		"material low-pass survives the wavefront"
	)
	_expect(
		is_equal_approx(float(result.get("resonance", 0.0)), 0.35),
		"material resonance survives the wavefront"
	)
	var modifier_ids: PackedStringArray = result.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		modifier_ids.has("steel_wall")
		and not modifier_ids.has("concrete_shortcut"),
		"result identifies only modifiers on the selected path"
	)
	var apparent_position: Vector3 = result.get(
		"apparent_position",
		Vector3.ZERO
	)
	_expect(
		absf(apparent_position.x) < EPSILON
		and apparent_position.z > 0.0,
		"indirect sound arrives from the first path hop"
	)


func _test_path_deviation_response() -> void:
	var bent_graph := AcousticPropagationGraph.new()
	var bent_listener := bent_graph.add_probe(Vector3.ZERO, &"deviation_listener")
	var bent_corner := bent_graph.add_probe(Vector3(0.0, 0.0, 4.0), &"deviation_corner")
	var bent_source := bent_graph.add_probe(Vector3(4.0, 0.0, 4.0), &"deviation_source")
	bent_graph.connect_probes(bent_listener, bent_corner)
	bent_graph.connect_probes(bent_corner, bent_source)
	var bent_field := AcousticPropagationField.new()
	bent_graph.solve_from_position(Vector3.ZERO, bent_field)
	var bent_bands := bent_field.band_gains[bent_source]
	var routing_bands := bent_field.routing_band_gains[bent_source]

	var straight_graph := AcousticPropagationGraph.new()
	var straight_listener := straight_graph.add_probe(Vector3.ZERO, &"straight_listener")
	var straight_middle := straight_graph.add_probe(Vector3(0.0, 0.0, 4.0), &"straight_middle")
	var straight_source := straight_graph.add_probe(Vector3(0.0, 0.0, 8.0), &"straight_source")
	straight_graph.connect_probes(straight_listener, straight_middle)
	straight_graph.connect_probes(straight_middle, straight_source)
	var straight_field := AcousticPropagationField.new()
	straight_graph.solve_from_position(Vector3.ZERO, straight_field)
	var straight_bands := straight_field.band_gains[straight_source]

	var deep_graph := AcousticPropagationGraph.new()
	var previous_position := Vector3.ZERO
	var previous_probe := deep_graph.add_probe(previous_position, &"deep_000")
	var directions := [Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.FORWARD]
	var deep_source := previous_probe
	for step: int in range(1, 41):
		previous_position += directions[(step - 1) % directions.size()] * 2.0
		deep_source = deep_graph.add_probe(
			previous_position,
			StringName("deep_%03d" % step)
		)
		deep_graph.connect_probes(previous_probe, deep_source)
		previous_probe = deep_source
	var deep_field := AcousticPropagationField.new()
	deep_graph.solve_from_position(Vector3.ZERO, deep_field)
	var deep_bands := deep_field.band_gains[deep_source]
	var response_floor := Vector3(
		db_to_linear(-AcousticPropagationGraph.PATH_DEVIATION_MAX_ATTENUATION_DB.x),
		db_to_linear(-AcousticPropagationGraph.PATH_DEVIATION_MAX_ATTENUATION_DB.y),
		db_to_linear(-AcousticPropagationGraph.PATH_DEVIATION_MAX_ATTENUATION_DB.z)
	)
	_expect_rule(
		&"A26",
		bent_bands.x > bent_bands.y
		and bent_bands.y > bent_bands.z
		and routing_bands.is_equal_approx(Vector3.ONE)
		and straight_bands.is_equal_approx(Vector3.ONE)
		and deep_bands.x >= response_floor.x - EPSILON
		and deep_bands.y >= response_floor.y - EPSILON
		and deep_bands.z >= response_floor.z - EPSILON,
		"baked bends darken the rendered wave without changing route topology or erasing deep-path bands"
	)


func _test_environment_response_math() -> void:
	var sample_count := ServerAcousticService.ENVIRONMENT_SAMPLE_DIRECTIONS.size()
	_expect(
		sample_count == 50,
		"probe rebuilds use dense axis-preserving spherical environment samples"
	)
	var open_distances := PackedFloat32Array()
	var open_hits := PackedByteArray()
	var absorptions := PackedVector3Array()
	var scatterings := PackedFloat32Array()
	open_distances.resize(sample_count)
	open_distances.fill(28.0)
	open_hits.resize(sample_count)
	open_hits.fill(0)
	absorptions.resize(sample_count)
	absorptions.fill(Vector3(0.2, 0.2, 0.2))
	scatterings.resize(sample_count)
	scatterings.fill(0.2)
	var outdoors := AcousticEnvironmentModel.response_from_samples(
		open_distances,
		open_hits,
		absorptions,
		scatterings,
		28.0
	)

	var room_distances := PackedFloat32Array()
	var room_hits := PackedByteArray()
	room_distances.resize(sample_count)
	room_distances.fill(3.0)
	room_hits.resize(sample_count)
	room_hits.fill(1)
	var room := AcousticEnvironmentModel.response_from_samples(
		room_distances,
		room_hits,
		absorptions,
		scatterings,
		28.0
	)

	var tunnel_distances := PackedFloat32Array()
	var tunnel_hits := PackedByteArray()
	tunnel_distances.resize(sample_count)
	tunnel_distances.fill(2.0)
	tunnel_hits.resize(sample_count)
	tunnel_hits.fill(1)
	# Two long/open axial samples are enough to make the otherwise enclosed response elongated.
	tunnel_distances[0] = 28.0
	tunnel_distances[1] = 28.0
	tunnel_hits[0] = 0
	tunnel_hits[1] = 0
	var tunnel := AcousticEnvironmentModel.response_from_samples(
		tunnel_distances,
		tunnel_hits,
		absorptions,
		scatterings,
		28.0
	)
	_expect(
		is_zero_approx(float(outdoors.get("reverb_send", 1.0)))
		and is_zero_approx(float(outdoors.get("enclosure", 1.0)))
		and is_zero_approx(float(outdoors.get("guided_propagation", 1.0))),
		"unbounded samples lose reflected energy instead of creating outdoor reverb"
	)
	_expect(
		float(room.get("reverb_send", 0.0)) > 0.35
		and float(room.get("rt60_seconds", 0.0)) > 0.5,
		"enclosed reflective samples produce a persistent room response"
	)
	_expect_rule(&"A08",
		float(tunnel.get("reverb_room_size", 0.0))
		> float(room.get("reverb_room_size", 1.0))
		and float(tunnel.get("reverb_spread", 1.0))
		< float(room.get("reverb_spread", 0.0)),
		"the same reflection rule turns an elongated enclosure into a larger, narrower hall"
	)
	_expect(
		float(tunnel.get("guided_propagation", 0.0)) > 0.6
		and is_zero_approx(float(room.get("guided_propagation", 1.0))),
		"only the elongated enclosure preserves energy as a guided field"
	)
	_expect(
		float(room.get("pressure_confinement", 0.0)) > 0.5
		and float(room.get("pressure_bass_boost_db", 0.0)) > 3.0
		and float(room.get("pressure_reverb_send", 0.0)) > 0.2
		and is_zero_approx(float(outdoors.get("pressure_confinement", 1.0))),
		"the rebuild-time room samples also bake a bounded detonation pressure signature"
	)
	var guide_graph := AcousticPropagationGraph.new()
	var listener_probe := guide_graph.add_probe(
		Vector3.ZERO,
		&"tunnel_listener",
		50.0,
		Vector3(0.0, 0.0, 20.0),
		Vector3(2.0, 2.0, 24.0)
	)
	var source_probe := guide_graph.add_probe(
		Vector3(0.0, 0.0, 40.0),
		&"tunnel_source",
		50.0,
		Vector3(0.0, 0.0, 20.0),
		Vector3(2.0, 2.0, 24.0)
	)
	guide_graph.set_probe_environment(listener_probe, tunnel)
	guide_graph.set_probe_environment(source_probe, tunnel)
	guide_graph.connect_probes(listener_probe, source_probe, null, true, true)
	var mouth_probe := guide_graph.add_probe(
		Vector3(0.0, 0.0, 45.0),
		&"tunnel_mouth",
		10.0,
		Vector3(0.0, 0.0, 45.0),
		Vector3.ZERO,
		2.0,
		{
			"origin": Vector3(0.0, 0.0, 44.0),
			"axis": Vector3.BACK,
			"lateral_axis": Vector3.RIGHT,
			"aperture_half_extents": Vector2(2.0, 2.0),
			"divergence": Vector2(0.5, 0.35),
			"falloff_distance": 10.0,
		}
	)
	var mouth_response := AcousticEnvironmentModel.open_air_response()
	mouth_response["guided_propagation"] = 0.5
	guide_graph.set_probe_environment(mouth_probe, mouth_response)
	var mouth_center_strength := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(0.0, 0.0, 45.0)
	)
	var mouth_edge_strength := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(0.0, 0.0, 50.5)
	)
	var past_mouth_strength := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(0.0, 0.0, 64.0)
	)
	var near_cone_edge := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(3.0, 0.0, 46.0)
	)
	var near_cone_center := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(0.0, 0.0, 46.0)
	)
	var far_same_lateral := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(3.0, 0.0, 54.0)
	)
	var far_cone_center := guide_graph._guided_environment_influence(
		mouth_probe, Vector3(0.0, 0.0, 54.0)
	)
	var guided_range := guide_graph.effective_hearing_distance(
		42.0,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		null,
		1.0,
		source_probe
	)
	var fully_guided_length := guide_graph.direct_guided_path_length(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		null,
		1.0,
		source_probe
	)
	var partly_open_guided_length := guide_graph.direct_guided_path_length(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		null,
		0.93,
		source_probe
	)
	var blocked_guided_length := guide_graph.direct_guided_path_length(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		null,
		0.0,
		source_probe
	)
	var inside_guide_edge := guide_graph._guided_environment_influence(
		source_probe, Vector3(0.0, 0.0, 43.99)
	)
	var outside_guide_edge := guide_graph._guided_environment_influence(
		source_probe, Vector3(0.0, 0.0, 44.01)
	)
	var outside_guide_far := guide_graph._guided_environment_influence(
		source_probe, Vector3(0.0, 0.0, 44.8)
	)
	var guided_result := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		guided_range
	)
	guide_graph.apply_environment_to_result(
		guided_result,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0)
	)
	var open_result := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 40.0),
		80.0
	)
	_expect_rule(&"A09",
		guided_range > 70.0
		and float(guided_result.get("guided_propagation_gain_db", 0.0)) > 10.0
		and float(guided_result.get("volume_db", -80.0))
		> float(open_result.get("volume_db", 0.0)) + 10.0
		and float(guided_result.get("volume_db", 0.0)) < -6.0
		and mouth_center_strength > mouth_edge_strength
		and mouth_edge_strength > past_mouth_strength
		and past_mouth_strength > 0.0
		and absf(near_cone_edge / near_cone_center - 0.5) < 0.02
		and far_same_lateral / far_cone_center > 0.9
		and fully_guided_length > 0.0
		and is_equal_approx(
			partly_open_guided_length / fully_guided_length,
			0.93
		)
		and is_zero_approx(blocked_guided_length)
		and absf(inside_guide_edge - outside_guide_edge) < 0.03
		and inside_guide_edge > outside_guide_far
		and is_zero_approx(outside_guide_far),
		"tunnel guidance stays in its volume, then extends range through a widening continuous aperture lobe without creating gain"
	)


func _test_full_occlusion_control_continuity() -> void:
	var wall := AcousticPathModifier.new()
	wall.modifier_id = &"continuity_wall"
	wall.band_gain = Vector3(0.45, 0.12, 0.02)
	wall.volume_db = -7.0
	wall.lowpass_hz = 1900.0
	wall.resonance = 0.35
	wall.reverb_send = 0.22
	var base := {
		"audible": true,
		"volume_db": -10.0,
		"band_gain": Vector3.ONE,
		"travel_delay_seconds": 0.0,
		"lowpass_hz": AcousticPathModifier.MAX_FILTER_HZ,
		"highpass_hz": AcousticPathModifier.MIN_FILTER_HZ,
		"resonance": 0.0,
		"reverb_send": 0.0,
		"modifier_ids": PackedStringArray(),
	}
	var almost_covered := base.duplicate(true)
	var fully_covered := base.duplicate(true)
	AcousticPropagationGraph.apply_partial_modifier_to_result(
		almost_covered,
		wall,
		0.999,
		false
	)
	AcousticPropagationGraph.apply_partial_modifier_to_result(
		fully_covered,
		wall,
		1.0,
		false
	)
	var almost_bands: Vector3 = almost_covered["band_gain"]
	var full_bands: Vector3 = fully_covered["band_gain"]
	_expect(
		absf(
			float(almost_covered["volume_db"])
			- float(fully_covered["volume_db"])
		) < 0.1
		and almost_bands.distance_to(full_bands) < 0.02
		and absf(
			float(almost_covered["lowpass_hz"])
			- float(fully_covered["lowpass_hz"])
		) < 10.0,
		"99.9 and 100 percent wall coverage use one continuous volume and EQ representation"
	)


func _test_spectral_room_bloom_math() -> void:
	var room := {
		"reverb_send": 0.6,
		"environment_enclosure": 0.85,
		"reverb_damping": 0.85,
		"reverb_predelay_feedback": 0.4,
	}
	var bright := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.04, 0.04),
		Vector2(0.12, 0.12),
		0.0,
		room
	)
	var dark := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.12, 0.12),
		Vector2(0.02, 0.02),
		0.0,
		room
	)
	var outdoors := RadioAudioRenderer.spectral_room_bloom_target(
		Vector2(0.04, 0.04),
		Vector2(0.12, 0.12),
		0.0,
		{"reverb_send": 0.0, "environment_enclosure": 0.0}
	)
	var response := SpatialAudioEffectRack.spectral_bloom_reverb_response(
		room,
		bright
	)
	var mix := SpatialAudioEffectRack.power_normalized_reverb_mix(response.x)
	_expect_rule(
		&"A17",
		bright > 0.75
		and dark < 0.05
		and is_zero_approx(outdoors)
		and response.x > 0.7
		and response.y <= 0.98
		and absf(mix.length_squared() - 1.0) < 0.0001,
		"upper-mid energy blooms a reflective indoor tail without brightening dark content or open air"
	)


func _test_continuous_mix_safety() -> void:
	var renderer := RadioAudioRenderer.new()
	root.add_child(renderer)
	renderer._ensure_pool()
	var bus_index := AudioServer.get_bus_index(
		RadioAudioRenderer.CONTINUOUS_MIX_BUS
	)
	var limiter := (
		AudioServer.get_bus_effect(bus_index, 0) as AudioEffectHardLimiter
		if bus_index >= 0 and AudioServer.get_bus_effect_count(bus_index) == 1
		else null
	)
	var representative_room_mix := (
		SpatialAudioEffectRack.power_normalized_reverb_mix(0.55)
	)
	_expect_rule(
		&"A19",
		limiter != null
		and is_equal_approx(limiter.pre_gain_db, 0.0)
		and is_equal_approx(
			limiter.ceiling_db,
			RadioAudioRenderer.CONTINUOUS_LIMITER_CEILING_DB
		)
		and limiter.release <= 0.1
		and representative_room_mix.x > 0.92,
		"the PA retains dry low-frequency punch and reserves gain reduction for actual overs"
	)
	var correlated_packets: Array[Dictionary] = [
		{
			"shared_program_group_id": 91,
			"volume_db": -3.0,
			"playback_offset_seconds": 4.97,
			"program_playback_offset_seconds": 5.0,
			"start_delay_seconds": 0.03,
		},
		{
			"shared_program_group_id": 91,
			"volume_db": -6.0,
			"playback_offset_seconds": 4.91,
			"program_playback_offset_seconds": 5.0,
			"start_delay_seconds": 0.09,
		},
	]
	renderer._prepare_shared_program_mix(correlated_packets)
	var normalized_pressure := 0.0
	for packet: Dictionary in correlated_packets:
		normalized_pressure += db_to_linear(float(packet["volume_db"]))
	var expected_energy_amplitude := sqrt(
		pow(db_to_linear(-3.0), 2.0) + pow(db_to_linear(-6.0), 2.0)
	)
	_expect_rule(
		&"A20",
		absf(normalized_pressure - expected_energy_amplitude) < 0.0001
		and is_equal_approx(
			float(correlated_packets[0]["playback_offset_seconds"]),
			float(correlated_packets[1]["playback_offset_seconds"])
		)
		and is_equal_approx(
			float(correlated_packets[0]["start_delay_seconds"]),
			float(correlated_packets[1]["start_delay_seconds"])
		),
		"one shared program keeps a common phase while its pressure sum equals the propagated power sum"
	)
	var localized_packets: Array[Dictionary] = [
		{
			"shared_program_group_id": 92,
			"shared_program_late_field_enabled": true,
			"volume_db": -6.0,
			"diffuse_field_gain_db": 0.0,
			"reverb_send": 0.45,
		},
		{
			"shared_program_group_id": 92,
			"shared_program_late_field_enabled": true,
			"volume_db": -6.0,
			"diffuse_field_gain_db": 12.0,
			"reverb_send": 0.45,
		},
	]
	var localized_mix := SpatialAudioEffectRack.power_normalized_reverb_mix(0.45)
	var expected_localized_pressure := sqrt(2.0) * db_to_linear(-6.0) * localized_mix.x
	renderer._prepare_shared_program_mix(localized_packets)
	var rendered_localized_pressure := 0.0
	for packet: Dictionary in localized_packets:
		rendered_localized_pressure += db_to_linear(float(packet["volume_db"]))
	_expect_rule(
		&"A29",
		absf(rendered_localized_pressure - expected_localized_pressure) < 0.0001
		and float(localized_packets[0]["volume_db"])
		> float(localized_packets[1]["volume_db"]) + 10.0
		and is_equal_approx(
			float(localized_packets[1]["shared_program_diffuse_directional_rejection_db"]),
			12.0
		),
		"diffuse room recovery preserves synchronized group pressure without making a distant cabinet directionally equal to a clear one"
	)
	var continuous_rack: SpatialAudioEffectRack = renderer._effect_racks[0]
	var stable_spread := continuous_rack.reverb.spread
	continuous_rack.apply_acoustic({
		"reverb_send": 0.22,
		"reverb_spread": 0.18,
	})
	var quiet_wet := continuous_rack.reverb.wet
	continuous_rack.approach_acoustic({
		"reverb_send": 0.72,
		"reverb_spread": 0.98,
	}, 0.5)
	_expect_rule(
		&"A22",
		continuous_rack.reverb.wet > quiet_wet
		and is_equal_approx(
			stable_spread,
			SpatialAudioEffectRack.REALTIME_SAFE_REVERB_SPREAD
		)
		and is_equal_approx(continuous_rack.reverb.spread, stable_spread),
		"continuous hall energy responds while the right-channel comb/all-pass lengths remain fixed"
	)
	renderer.free()


func _test_listener_acoustic_activity() -> void:
	var quiet_event := LISTENER_ACTIVITY.from_received_volume_db(-40.0)
	var obstructed_event := LISTENER_ACTIVITY.from_received_volume_db(-24.0)
	var loud_event := LISTENER_ACTIVITY.from_received_volume_db(-3.0)
	var loud_program := LISTENER_ACTIVITY.from_spectrum(
		Vector2(0.14, 0.12),
		Vector2(0.08, 0.07),
		Vector2(0.04, 0.03)
	)
	var combined := LISTENER_ACTIVITY.combine_energy(0.65, 0.65)
	var attacked := LISTENER_ACTIVITY.follow(0.0, 1.0, 0.1, 18.0, 4.0)
	var released := LISTENER_ACTIVITY.follow(attacked, 0.0, 0.5, 18.0, 4.0)
	_expect_rule(
		&"A21",
		quiet_event < 0.001
		and obstructed_event < 0.1
		and loud_event > 0.95
		and loud_program > 0.9
		and combined > 0.9
		and combined < 1.0
		and attacked > 0.8
		and released < attacked * 0.15,
		"received event level and live program spectrum feed one fast, bounded, energy-summing listener envelope"
	)


func _test_direct_and_diffuse_room_energy() -> void:
	var distances := PackedFloat32Array([1.0, 2.0, 4.0, 8.0])
	var room_levels := PackedFloat32Array()
	var room_gains := PackedFloat32Array()
	var room_decay := PackedFloat32Array()
	for distance: float in distances:
		var room_result := AcousticPropagationGraph.sample_free_field(
			Vector3.ZERO,
			Vector3(0.0, 0.0, distance),
			80.0
		)
		AcousticPropagationGraph._apply_diffuse_field_support(
			room_result,
			1.0,
			2.0
		)
		room_levels.append(float(room_result.get("volume_db", -80.0)))
		room_gains.append(float(room_result.get("diffuse_field_gain_db", 0.0)))
		room_decay.append(float(room_result.get("diffuse_field_decay_db", 0.0)))
	var open_result := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 8.0),
		80.0
	)
	AcousticPropagationGraph._apply_diffuse_field_support(
		open_result,
		0.0,
		2.0
	)
	_expect_rule(&"A16",
		room_levels[0] > room_levels[1]
		and room_levels[1] > room_levels[2]
		and room_levels[2] > room_levels[3]
		and room_levels[0] - room_levels[1] > 2.0
		and room_levels[2] - room_levels[3] < 2.25
		and absf(room_decay[3] - room_decay[2] - 1.0) < EPSILON
		and room_gains[0] < 1.75
		and room_gains[3] > room_gains[1] + 5.0
		and is_zero_approx(
			float(open_result.get("diffuse_field_gain_db", 1.0))
		),
		"direct energy owns the near field while the shared room field takes over smoothly past critical distance"
	)


func _test_baked_pressure_propagation() -> void:
	var open_graph := AcousticPropagationGraph.new()
	var open_result := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 8.0),
		40.0
	)
	open_graph.attach_pressure_arrivals(
		open_result,
		null,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 8.0),
		40.0,
		0.8
	)
	_expect(
		(open_result.get("pressure_arrivals", []) as Array).size() == 1
		and is_zero_approx(float(open_result.get("pressure_reverb_send", 1.0))),
		"unprobed worlds retain a dry open-air pressure body without runtime geometry work"
	)

	var graph := AcousticPropagationGraph.new()
	var listener_probe := graph.add_probe(Vector3.ZERO, &"pressure_listener")
	var first_exit := graph.add_probe(Vector3(0.0, 0.0, 5.0), &"first_exit")
	var second_exit := graph.add_probe(Vector3(5.0, 0.0, 0.0), &"second_exit")
	var source_probe := graph.add_probe(Vector3(5.0, 0.0, 5.0), &"pressure_source")
	graph.connect_probes(listener_probe, first_exit)
	graph.connect_probes(first_exit, source_probe)
	graph.connect_probes(listener_probe, second_exit)
	var delayed_exit := AcousticPathModifier.new()
	delayed_exit.extra_delay_seconds = 0.025
	delayed_exit.reverb_send = 0.12
	graph.connect_probes(second_exit, source_probe, delayed_exit)
	graph.set_probe_environment(source_probe, {
		"enclosure": 0.91,
		"rt60_seconds": 1.4,
		"reverb_send": 0.55,
		"reverb_room_size": 0.48,
		"reverb_damping": 0.72,
		"reverb_spread": 0.74,
		"pressure_confinement": 0.83,
		"pressure_body_gain_db": -3.8,
		"pressure_bass_boost_db": 6.4,
		"pressure_reflection_delay_seconds": 0.012,
		"pressure_reverb_send": 0.58,
		"pressure_decay_seconds": 1.4,
		"pressure_escape": 0.16,
		"pressure_escape_direction": Vector3(0.0, 0.0, -1.0),
		"pressure_escape_directionality": 0.8,
	})
	var baked_response := graph.environment_response(source_probe)
	var field := AcousticPropagationField.new()
	graph.solve_from_position(Vector3.ZERO, field)
	var result := graph.sample_source(
		field,
		Vector3(5.0, 0.0, 5.0),
		80.0
	)
	graph.apply_environment_to_result(
		result,
		Vector3.ZERO,
		Vector3(5.0, 0.0, 5.0),
		field
	)
	graph.attach_pressure_arrivals(
		result,
		field,
		Vector3.ZERO,
		Vector3(5.0, 0.0, 5.0),
		80.0,
		0.9
	)
	var arrivals: Array = result.get("pressure_arrivals", [])
	_expect(
		is_equal_approx(
			float(baked_response.get("pressure_confinement", 0.0)),
			0.83
		)
		and is_equal_approx(
			float(baked_response.get("pressure_bass_boost_db", 0.0)),
			6.4
		),
		"pressure response values live on stable probes and survive graph baking"
	)
	_expect(
		arrivals.size() == 2
		and int((arrivals[0] as Dictionary).get("kind", -1)) == 0
		and int((arrivals[1] as Dictionary).get("kind", -1)) == 1
		and float((arrivals[0] as Dictionary).get("travel_delay_seconds", 0.0))
		> float(result.get("travel_delay_seconds", 0.0))
		and float((arrivals[1] as Dictionary).get("travel_delay_seconds", 0.0))
		> float((arrivals[0] as Dictionary).get("travel_delay_seconds", 0.0)),
		"one pressure body and one independent delayed exit reuse the baked wavefront"
	)
	_expect_rule(&"A10",
		arrivals.size() <= AcousticPropagationGraph.MAX_PRESSURE_ARRIVALS
		and float(result.get("pressure_reverb_send", 0.0)) > 0.45
		and float(result.get("pressure_decay_seconds", 0.0)) > 1.0,
		"connected probe blending stays strong while pressure work remains strictly bounded"
	)


func _test_listener_room_owns_late_reverb() -> void:
	var graph := AcousticPropagationGraph.new()
	var tunnel_probe := graph.add_probe(Vector3.ZERO, &"tunnel")
	var outdoors_probe := graph.add_probe(Vector3(0.0, 0.0, 10.0), &"outdoors")
	var house_probe := graph.add_probe(Vector3(20.0, 0.0, 0.0), &"house")
	graph.set_probe_environment(tunnel_probe, {
		"enclosure": 0.96,
		"rt60_seconds": 6.2,
		"reverb_send": 0.82,
		"reverb_room_size": 0.94,
		"reverb_damping": 0.18,
		"reverb_spread": 0.22,
		"reverb_predelay_msec": 190.0,
		"reverb_predelay_feedback": 0.72,
		"reverb_hipass": 0.08,
	})
	graph.set_probe_environment(outdoors_probe, {
		"enclosure": 0.0,
		"rt60_seconds": AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		"reverb_send": 0.0,
	})
	graph.set_probe_environment(house_probe, {
		"enclosure": 0.84,
		"rt60_seconds": 0.85,
		"reverb_send": 0.38,
		"reverb_room_size": 0.26,
		"reverb_damping": 0.61,
		"reverb_spread": 0.88,
		"reverb_predelay_msec": 34.0,
		"reverb_predelay_feedback": 0.21,
		"reverb_hipass": 0.17,
	})

	var outdoor_result := AcousticPropagationGraph.sample_free_field(
		Vector3(0.0, 0.0, 10.0),
		Vector3.ZERO,
		50.0
	)
	graph.apply_environment_to_result(
		outdoor_result,
		Vector3(0.0, 0.0, 10.0),
		Vector3.ZERO
	)
	_expect(
		is_zero_approx(float(outdoor_result.get("reverb_send", 1.0))),
		"a tunnel source does not transplant its late reverb into open air"
	)

	var house_result := AcousticPropagationGraph.sample_free_field(
		Vector3(20.0, 0.0, 0.0),
		Vector3.ZERO,
		50.0
	)
	graph.apply_environment_to_result(
		house_result,
		Vector3(20.0, 0.0, 0.0),
		Vector3.ZERO
	)
	_expect_rule(&"A07",
		is_equal_approx(float(house_result.get("reverb_send", 0.0)), 0.38)
		and is_equal_approx(float(house_result.get("reverb_room_size", 0.0)), 0.26)
		and is_equal_approx(float(house_result.get("reverb_spread", 0.0)), 0.88)
		and is_equal_approx(float(house_result.get("reverb_decay_seconds", 0.0)), 0.85)
		and is_zero_approx(
			float(house_result.get("diffuse_field_gain_db", 0.0))
		),
		"entering a house uses the house response instead of the source tunnel response"
	)


func _test_free_field_and_packet_safety() -> void:
	var doubled_reach := AcousticPropagationGraph.level_scaled_hearing_distance(
		40.0,
		6.0206
	)
	var halved_reach := AcousticPropagationGraph.level_scaled_hearing_distance(
		40.0,
		-6.0206
	)
	_expect_rule(&"A02",
		absf(doubled_reach - 80.0) < 0.01
		and absf(halved_reach - 20.0) < 0.01
		and is_equal_approx(
			AcousticPropagationGraph.level_scaled_hearing_distance(
				9000.0,
				18.0
			),
			AcousticPropagationGraph.MAX_LEVEL_SCALED_HEARING_DISTANCE
		),
		"source gain doubles reach per 6.02 dB while retaining the server safety cap"
	)
	var baseline_range_sample := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 60.0),
		40.0
	)
	var loud_range_sample := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 60.0),
		doubled_reach
	)
	_expect(
		not bool(baseline_range_sample.get("audible", false))
		and bool(loud_range_sample.get("audible", false)),
		"the level-scaled distance extends the same free-field propagation and fade path"
	)
	var result := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 34.3),
		100.0
	)
	_expect_rule(&"A03",
		absf(float(result.get("travel_delay_seconds", 0.0)) - 0.1)
		< EPSILON
		and is_zero_approx(
			AcousticPropagationGraph._range_fade_volume_db(58.333, 100.0)
		)
		and absf(
			AcousticPropagationGraph._range_fade_volume_db(58.34, 100.0)
		) < 0.001
		and AcousticPropagationGraph._range_fade_volume_db(83.0, 100.0)
		< AcousticPropagationGraph._range_fade_volume_db(80.0, 100.0),
		"free-field propagation uses the same speed of sound and a slope-bounded eased range tail"
	)
	var folded_graph := AcousticPropagationGraph.new()
	var folded_listener := folded_graph.add_probe(Vector3.ZERO, &"folded_listener")
	var folded_corner := folded_graph.add_probe(Vector3(0.0, 0.0, 30.0), &"folded_corner")
	var folded_source := folded_graph.add_probe(Vector3(5.0, 0.0, 0.0), &"folded_source")
	folded_graph.connect_probes(folded_listener, folded_corner)
	folded_graph.connect_probes(folded_corner, folded_source)
	var folded_field := AcousticPropagationField.new()
	folded_graph.solve_from_position(Vector3.ZERO, folded_field)
	var folded_result := folded_graph.sample_source(
		folded_field,
		Vector3(5.0, 0.0, 0.0),
		10.0
	)
	_expect_rule(&"A03",
		bool(folded_result.get("audible", false))
		and float(folded_result.get("path_length", 0.0)) > 60.0
		and is_equal_approx(
			float(folded_result.get("range_gate_distance", 0.0)),
			5.0
		),
		"a folded probe route pays its traveled spreading once while source reach remains radial"
	)
	result["sound_id"] = &"test_sound"
	result["sequence"] = 7
	result["priority"] = 0.8
	var packet := AcousticEventPacket.sanitize(result)
	_expect(
		packet.get("sound_id", &"") == &"test_sound"
		and int(packet.get("sequence", 0)) == 7,
		"valid authoritative packet crosses the network boundary"
	)
	result["pressure_strength"] = 0.9
	result["pressure_reverb_send"] = 0.55
	result["pressure_arrivals"] = [
		{
			"apparent_position": Vector3(1.0, 0.0, 0.0),
			"travel_delay_seconds": 0.12,
			"volume_db": -8.0,
		},
		{
			"apparent_position": Vector3(0.0, 0.0, 1.0),
			"travel_delay_seconds": 0.18,
			"volume_db": -14.0,
		},
		{
			"apparent_position": Vector3(-1.0, 0.0, 0.0),
			"travel_delay_seconds": 0.23,
			"volume_db": -18.0,
		},
		{
			"apparent_position": Vector3(0.0, 0.0, -1.0),
			"travel_delay_seconds": 0.29,
			"volume_db": -22.0,
		},
	]
	var pressure_packet := AcousticEventPacket.sanitize(result)
	_expect(
		(pressure_packet.get("pressure_arrivals", []) as Array).size()
		== AcousticPropagationGraph.MAX_PRESSURE_ARRIVALS,
		"client validation caps nested pressure arrivals before playback"
	)
	result["source_position"] = Vector3(NAN, 0.0, 0.0)
	_expect(
		AcousticEventPacket.sanitize(result).is_empty(),
		"non-finite authoritative packet fails closed on the client"
	)
	var range_edge := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 100.0),
		100.0
	)
	_expect(
		bool(range_edge.get("audible", false))
		and float(range_edge.get("volume_db", 0.0)) <= -79.0,
		"maximum hearing range fades to silence before culling"
	)


func _test_continuous_distance_updates() -> void:
	var service := ServerAcousticService.new()
	service.graph.add_probe(Vector3.ZERO, &"open_field")
	var source_position := Vector3(0.0, 0.0, 10.0)
	var first := service.calculate_listener_result(
		42,
		Vector3.ZERO,
		source_position,
		100.0
	)
	var moved := service.calculate_listener_result(
		42,
		Vector3(0.0, 0.0, 0.25),
		source_position,
		100.0
	)
	_expect(
		absf(float(moved.get("path_length", 0.0)) - 9.75) < EPSILON,
		"cached wavefield uses the listener's live direct distance"
	)
	_expect(
		float(moved.get("volume_db", -80.0))
		> float(first.get("volume_db", -80.0)),
		"sub-meter listener movement changes volume continuously"
	)
	_expect(
		int(service.get_debug_state().get("field_solve_count", 0)) == 2
		and int(service.get_debug_state().get(
			"cached_previous_listener_fields",
			0
		)) == 1
		and is_equal_approx(
			float(service.get_debug_state().get("field_refresh_distance", 1.0)),
			0.24
		),
		"listener wavefront routing refreshes after 24 cm instead of remaining stale for a full meter"
	)
	var prior_route := {
		"audible": true,
		"volume_db": -36.0,
		"band_gain": Vector3(0.8, 0.6, 0.3),
		"lowpass_hz": 3200.0,
		"apparent_position": Vector3.LEFT,
	}
	var next_route := {
		"audible": true,
		"volume_db": -31.0,
		"band_gain": Vector3.ONE,
		"lowpass_hz": 12000.0,
		"apparent_position": Vector3.RIGHT,
	}
	var five_centimetres := ServerAcousticService._crossfade_field_results(
		prior_route.duplicate(),
		next_route.duplicate(),
		0.25
	)
	var six_centimetres := ServerAcousticService._crossfade_field_results(
		prior_route.duplicate(),
		next_route.duplicate(),
		0.30
	)
	_expect_rule(
		&"A24",
		absf(float(six_centimetres.get("volume_db", -80.0))
		- float(five_centimetres.get("volume_db", -80.0))) <= 0.251
		and float(five_centimetres.get("volume_db", -80.0)) < -31.0
		and not five_centimetres.has("parallel_route_gain_db")
		and bool(five_centimetres.get("field_transition_active", false)),
		"successive cached wavefields crossfade by spatial level without inventing parallel-route gain"
	)
	var continuous_service := ServerAcousticService.new()
	var initial_continuous := continuous_service._smooth_continuous_result(
		{
			"audible": true,
			"volume_db": -30.0,
			"lowpass_hz": 3200.0,
			"band_gain": Vector3(0.8, 0.5, 0.2),
		},
		77,
		88,
		Vector3.ZERO,
		Vector3(0.0, 0.0, 10.0)
	)
	var one_centimetre_louder := continuous_service._smooth_continuous_result(
		{
			"audible": true,
			"volume_db": 0.0,
			"lowpass_hz": 16000.0,
			"band_gain": Vector3.ONE,
		},
		77,
		88,
		Vector3(0.01, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0)
	)
	var next_centimetre_quieter := continuous_service._smooth_continuous_result(
		{
			"audible": true,
			"volume_db": -80.0,
			"lowpass_hz": 800.0,
			"band_gain": Vector3(0.1, 0.05, 0.01),
		},
		77,
		88,
		Vector3(0.02, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0)
	)
	var immediate_one_shot := continuous_service._smooth_continuous_result(
		{"audible": true, "volume_db": 4.0},
		77,
		0,
		Vector3(0.03, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0)
	)
	var immediate_teleport := continuous_service._smooth_continuous_result(
		{"audible": true, "volume_db": -6.0},
		77,
		88,
		Vector3(3.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0)
	)
	_expect_rule(
		&"A25",
		is_equal_approx(float(initial_continuous.get("volume_db", 0.0)), -30.0)
		and absf(
			float(one_centimetre_louder.get("volume_db", 0.0)) + 29.9
		) < 0.001
		and absf(
			float(next_centimetre_quieter.get("volume_db", 0.0)) + 30.0
		) < 0.001
		and float(one_centimetre_louder.get("lowpass_hz", 20000.0)) < 16000.0
		and float(next_centimetre_quieter.get("lowpass_hz", 0.0)) > 800.0
		and is_equal_approx(float(immediate_one_shot.get("volume_db", 0.0)), 4.0)
		and is_equal_approx(float(immediate_teleport.get("volume_db", 0.0)), -6.0),
		"continuous server output has a spatially bounded dezipper while discrete events and teleports remain immediate"
	)
	var near_reference := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 0.99),
		100.0
	)
	var past_reference := AcousticPropagationGraph.sample_free_field(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 1.01),
		100.0
	)
	_expect(
		absf(
			float(near_reference.get("volume_db", 0.0))
			- float(past_reference.get("volume_db", 0.0))
		) < 0.2,
		"distance attenuation has no hard knee at the reference distance"
	)


func _test_multi_probe_listener_boundary() -> void:
	var service := ServerAcousticService.new()
	var left_probe := service.graph.add_probe(Vector3(-1.0, 0.0, 0.0), &"left")
	var right_probe := service.graph.add_probe(Vector3(1.0, 0.0, 0.0), &"right")
	service.graph.add_probe(Vector3(0.0, 0.0, -1.0), &"near_back")
	service.graph.add_probe(Vector3(0.0, 0.0, 1.0), &"near_front")
	var source_probe := service.graph.add_probe(Vector3(0.0, 0.0, 10.0), &"source")
	service.graph.connect_probes(left_probe, source_probe)
	var poor_route := AcousticPathModifier.new()
	poor_route.modifier_id = &"poor_boundary_route"
	poor_route.volume_db = -18.0
	poor_route.band_gain = Vector3(0.25, 0.08, 0.02)
	service.graph.connect_probes(right_probe, source_probe, poor_route)

	var just_left := service.calculate_listener_result(
		701,
		Vector3(-0.005, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0),
		50.0,
		null,
		1.0,
		false,
		[],
		7001
	)
	var just_right := service.calculate_listener_result(
		701,
		Vector3(0.005, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0),
		50.0,
		null,
		1.0,
		false,
		[],
		7001
	)
	_expect(
		bool(just_left.get("audible", false))
		and bool(just_right.get("audible", false))
		and absf(
			float(just_left.get("volume_db", -80.0))
			- float(just_right.get("volume_db", -80.0))
		) < 0.05
		and int(service.get_debug_state().get("field_solve_count", 0)) == 1,
		"crossing a nearest-probe boundary by one centimetre keeps route loudness continuous"
	)


func _test_client_voice_renderer() -> void:
	var renderer := SpatialAudioRenderer.new()
	root.add_child(renderer)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	stream.data = PackedByteArray([128, 132, 128, 124, 128])
	var transient_reports: Array[Vector2] = []
	renderer.foreground_transient_started.connect(func(
		strength: float,
		received_volume_db: float
	) -> void:
		transient_reports.append(Vector2(strength, received_volume_db))
	)
	_expect(
		renderer.register_sound(&"renderer_tail_test", [stream])
		and renderer.submit(AcousticEventPacket.sanitize({
			"sound_id": &"renderer_tail_test",
			"source_position": Vector3.ZERO,
			"apparent_position": Vector3.ZERO,
			"travel_delay_seconds": 0.0,
			"reverb_send": 0.7,
			"reverb_decay_seconds": 2.0,
			"priority": 0.5,
		})),
		"a reverberant one-shot enters the fixed client voice pool"
	)
	_expect(
		renderer.get_listener_acoustic_intensity() > 0.95,
		"a loud accepted one-shot updates the shared listener activity after propagation"
	)
	renderer._players[0].stop()
	_expect(
		renderer._voice_reserved_until_usec[0] > Time.get_ticks_usec()
		and renderer._select_voice(0.5) == 1,
		"a finished dry stream cannot overwrite its still-decaying reverb bus"
	)
	var previous_reverb := renderer._effect_racks[0].reverb
	renderer.reset_session()
	_expect(
		renderer._effect_racks[0].reverb != previous_reverb
		and renderer._voice_reserved_until_usec[0] == 0,
		"session reset flushes DSP delay lines instead of leaking an old room tail"
	)
	_expect(
			renderer.register_sound(
				&"renderer_test",
				[stream],
				{
					"pressure_streams": [stream],
					"pressure_layer_gain_db": 5.5,
					"foreground_transient_strength": 0.8,
				}
			),
		"client registers semantic sound and pressure-layer variations"
	)
	var packet := AcousticEventPacket.sanitize({
		"sound_id": &"renderer_test",
		"source_position": Vector3.ONE,
		"apparent_position": Vector3.ONE,
		"band_gain": Vector3(0.8, 0.4, 0.1),
		"lowpass_hz": 2800.0,
		"highpass_hz": 80.0,
		"resonance": 0.25,
		"travel_delay_seconds": 0.0,
		"priority": 0.7,
		"pressure_strength": 0.8,
		"pressure_reverb_send": 0.4,
		"pressure_arrivals": [{
			"kind": 0,
			"apparent_position": Vector3(0.0, 0.0, 2.0),
			"travel_delay_seconds": 0.04,
			"volume_db": -8.0,
			"band_gain": Vector3(1.2, 0.8, 0.3),
		}],
	})
	_expect(
		renderer.submit(packet),
		"client consumes server EQ, filters, and pressure arrivals through its voice pool"
	)
	_expect_rule(&"A11",
		renderer._pending_events.size() == 1
		and bool(renderer._pending_events[0].get("pressure_layer", false))
		and int(renderer._pending_events[0].get("stream_index_hint", -1)) == 0,
		"pressure playback reuses the fixed voice pool and physical arrival scheduler"
	)
	_expect(
		transient_reports.size() == 1
		and is_equal_approx(transient_reports[0].x, 0.8),
		"the renderer reports a registered foreground attack at its actual client playback time"
	)
	renderer._pending_events[0]["play_at_usec"] = 0
	renderer._process(0.0)
	var pressure_calibration_applied := false
	for voice_index: int in range(renderer._players.size()):
		if (
			AudioServer.get_bus_send(renderer._effect_racks[voice_index].bus_index)
			== SpatialAudioRenderer.PRESSURE_OUTPUT_BUS
			and is_equal_approx(renderer._players[voice_index].volume_db, -2.5)
		):
			pressure_calibration_applied = true
			break
	_expect(
		pressure_calibration_applied,
		"dedicated pressure mastering gain applies without changing the server packet"
	)
	_expect(
		transient_reports.size() == 1,
		"a delayed pressure body cannot retrigger foreground mix headroom"
	)
	_expect(
		renderer.register_sound(&"renderer_fallback_test", [stream]),
		"ordinary one-shots need no dedicated pressure recording"
	)
	var fallback_packet := packet.duplicate(true)
	fallback_packet["sound_id"] = &"renderer_fallback_test"
	fallback_packet["pressure_arrivals"] = [
		(packet.get("pressure_arrivals", []) as Array)[0],
		{
			"kind": 1,
			"apparent_position": Vector3(1.0, 0.0, 2.0),
			"travel_delay_seconds": 0.06,
			"volume_db": -18.0,
			"band_gain": Vector3(0.8, 0.4, 0.2),
		},
	]
	var pending_before_fallback := renderer._pending_events.size()
	_expect(
		renderer.submit(fallback_packet)
		and renderer._pending_events.size() == pending_before_fallback,
		"ordinary recordings use room DSP without an artifact-prone delayed source copy"
	)
	_expect(
		renderer.register_sound(&"renderer_open_fallback_test", [stream]),
		"open-air fallback test registers an ordinary semantic sound"
	)
	var open_fallback_packet := fallback_packet.duplicate(true)
	open_fallback_packet["sound_id"] = &"renderer_open_fallback_test"
	open_fallback_packet["pressure_enclosure"] = 0.0
	open_fallback_packet["pressure_reverb_send"] = 0.0
	var pending_before_open_fallback := renderer._pending_events.size()
	_expect(
		renderer.submit(open_fallback_packet)
		and renderer._pending_events.size() == pending_before_open_fallback,
		"ordinary open-air sounds do not acquire an artificial delayed duplicate"
	)
	var started_voice_count := 0
	for started_at: int in renderer._voice_started_usec:
		started_voice_count += 1 if started_at > 0 else 0
	var mix_packet := AcousticEventPacket.sanitize({
		"sound_id": &"renderer_test",
		"source_position": Vector3.ZERO,
		"apparent_position": Vector3.ZERO,
		"travel_delay_seconds": 0.0,
		"priority": 0.7,
	})
	var first_mix_accepted := renderer.submit(mix_packet)
	var second_mix_accepted := renderer.submit(mix_packet)
	var mixed_voice_count := 0
	for started_at: int in renderer._voice_started_usec:
		mixed_voice_count += 1 if started_at > 0 else 0
	_expect_rule(
		&"A13",
		first_mix_accepted
		and second_mix_accepted
		and mixed_voice_count >= started_voice_count + 2,
		"two simultaneous sources keep separate pooled voices so the audio server can sum them"
	)
	renderer.queue_free()


func _test_parallel_route_energy_mix() -> void:
	var direct := {
		"audible": true,
		"volume_db": -10.0,
		"band_gain": Vector3(0.3, 0.2, 0.1),
		"lowpass_hz": 1200.0,
		"travel_delay_seconds": 0.02,
	}
	var graph_route := {
		"audible": true,
		"volume_db": -10.0,
		"band_gain": Vector3.ONE,
		"lowpass_hz": 18000.0,
		"travel_delay_seconds": 0.06,
	}
	var mixed := ServerAcousticService._mix_parallel_route_results(
		graph_route,
		direct,
		1.0,
		1.0,
		&"parallel"
	)
	var bands: Vector3 = mixed.get("band_gain", Vector3.ZERO)
	var graph_only := ServerAcousticService._mix_parallel_route_results(
		graph_route.duplicate(false),
		{
			"audible": false,
			"volume_db": 0.0,
			"band_gain": Vector3.ONE,
		},
		1.0,
		1.0,
		&"parallel"
	)
	_expect_rule(&"A12",
		absf(float(mixed.get("volume_db", -80.0)) - (-6.9897)) < 0.01
		and absf(float(mixed.get("route_graph_energy_weight", 0.0)) - 0.5) < EPSILON
		and absf(bands.x - sqrt(0.545)) < EPSILON
		and float(mixed.get("lowpass_hz", 0.0)) > 4500.0
		and str(mixed.get("route_kind", "")) == "parallel"
		and bool(graph_only.get("audible", false))
		and absf(float(graph_only.get("volume_db", -80.0)) - (-10.0)) < EPSILON
		and str(graph_only.get("route_kind", "")) == "graph",
		"parallel waves add energy and an invalid path contributes exactly zero without muting the valid route"
	)


func _test_parallel_routes_share_one_diffuse_field() -> void:
	var graph := AcousticPropagationGraph.new()
	var room_probe := graph.add_probe(Vector3.ZERO, &"shared_late_room", 10.0)
	graph.set_probe_environment(room_probe, {
		"enclosure": 0.96,
		"rt60_seconds": 1.3,
		"reverb_send": 0.62,
		"effective_volume_m3": 260.0,
		"reverb_room_size": 0.46,
		"reverb_damping": 0.58,
	})
	var listener_position := Vector3(0.0, 0.0, 4.0)
	var source_position := Vector3.ZERO
	var direct := AcousticPropagationGraph.sample_free_field(
		listener_position,
		source_position,
		40.0
	)
	direct["direct_path_clear"] = false
	var diffracted := direct.duplicate(true)
	diffracted["apparent_position"] = Vector3(1.0, 0.0, 0.0)
	var early := ServerAcousticService._compose_early_route_result(
		diffracted,
		direct,
		true,
		true,
		1.0
	)
	var early_level_db := float(early.get("volume_db", -80.0))
	graph.apply_environment_to_result(
		early,
		listener_position,
		source_position,
		null,
		room_probe,
		true
	)
	var diffuse_level_db := float(early.get(
		"diffuse_field_level_db",
		AcousticPathModifier.MIN_VOLUME_DB
	))
	var early_power := pow(10.0, early_level_db / 10.0)
	var diffuse_power := pow(10.0, diffuse_level_db / 10.0)
	var rendered_power := pow(
		10.0,
		float(early.get("volume_db", -80.0)) / 10.0
	)
	var expected_power := early_power + diffuse_power
	_expect_rule(
		&"A27",
		str(early.get("route_kind", "")) == "parallel"
		and float(early.get("diffuse_field_support", 0.0)) > 0.5
		and absf(rendered_power - expected_power)
		<= expected_power * 0.0001,
		"parallel early arrivals sum first and receive exactly one listener-room diffuse contribution"
	)


func _test_dev_warehouse_material_authoring() -> void:
	var scene := load("res://scenes/server/dev_warehouse.tscn") as PackedScene
	var warehouse := scene.instantiate()
	var portal := warehouse.get_node_or_null(
		"BackboardAcousticTransmission"
	) as AcousticPortal3D
	_expect(
		portal != null
		and portal.material != null
		and portal.material.material_id == &"steel_backboard",
		"dev warehouse steel backboard authors a server material boundary"
	)
	warehouse.free()

	var house_scene := load(
		"res://scenes/server/acoustic_test_house.tscn"
	) as PackedScene
	var house := house_scene.instantiate()
	var doorway := house.get_node_or_null(
		"OpenDoorAcousticPath"
	) as AcousticPortal3D
	_expect(
		house.get("acoustic_material") is AcousticMaterial
		and (house.get("acoustic_material") as AcousticMaterial).material_id
		== &"test_house_wall"
		and doorway != null
		and house.get_node_or_null("SmallWallFrontProbe") is AcousticProbe3D
		and house.get_node_or_null("SmallWallBackProbe") is AcousticProbe3D,
		"acoustic test house authors wall material, doorway routing, and both sides of its small test wall"
	)
	house.free()

	var server_world_scene := load(
		"res://scenes/server/server_world.tscn"
	) as PackedScene
	var client_world_scene := load(
		"res://scenes/proxy/world.tscn"
	) as PackedScene
	var server_world := server_world_scene.instantiate()
	var client_world := client_world_scene.instantiate()
	_expect(
		server_world.get_node_or_null("AcousticTestHouse") != null
		and client_world.get_node_or_null("AcousticTestHouse") != null
		and client_world.get_node_or_null("GameAudioLibrary") != null
		and (GameAudioLibrary.WEAPON_REPORT_SPECS[0].get(
			"pressure_streams", []
		) as Array).size() == 4
		and server_world.get_node("AcousticTestHouse").position.is_equal_approx(
			client_world.get_node("AcousticTestHouse").position
		),
		"server/client acoustic geometry aligns and the pistol owns dedicated pressure layers"
	)
	server_world.free()
	client_world.free()


func _test_direct_path_collision_bypass_and_cache() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 1.0, 2.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.35, 1.0, 0.08)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	wall.add_child(collision)
	var material := AcousticMaterial.new()
	material.material_id = &"tiny_test_wall"
	material.transmission_gain = Vector3(0.45, 0.12, 0.02)
	material.transmission_volume_db = -7.0
	material.transmission_lowpass_hz = 1900.0
	wall.set_meta("acoustic_material", material)
	world.add_child(wall)
	var prop := StaticBody3D.new()
	prop.name = "PartialOcclusionProp"
	prop.position = Vector3(1.5, 1.0, 2.5)
	prop.set_meta("acoustic_material", material)
	prop.set_meta(&"acoustic_boundary", false)
	var prop_shape := BoxShape3D.new()
	prop_shape.size = Vector3(0.16, 0.20, 0.08)
	var prop_collision := CollisionShape3D.new()
	prop_collision.shape = prop_shape
	prop.add_child(prop_collision)
	world.add_child(prop)
	var stacked_prop := StaticBody3D.new()
	stacked_prop.name = "StackedPartialOcclusionProp"
	stacked_prop.position = Vector3(2.5, 1.0, 1.5)
	stacked_prop.set_meta("acoustic_material", material)
	stacked_prop.set_meta(&"acoustic_boundary", false)
	var stacked_prop_shape := BoxShape3D.new()
	stacked_prop_shape.size = Vector3(0.16, 0.20, 0.08)
	var stacked_prop_collision := CollisionShape3D.new()
	stacked_prop_collision.shape = stacked_prop_shape
	stacked_prop.add_child(stacked_prop_collision)
	world.add_child(stacked_prop)
	var rear_wall := StaticBody3D.new()
	rear_wall.name = "StructuralWallBehindPartialProp"
	rear_wall.position = Vector3(2.5, 1.0, 3.5)
	var rear_wall_shape := BoxShape3D.new()
	rear_wall_shape.size = Vector3(0.35, 1.0, 0.08)
	var rear_wall_collision := CollisionShape3D.new()
	rear_wall_collision.shape = rear_wall_shape
	rear_wall.add_child(rear_wall_collision)
	var rear_wall_material := AcousticMaterial.new()
	rear_wall_material.material_id = &"rear_structural_wall"
	rear_wall_material.transmission_gain = Vector3(0.38, 0.08, 0.01)
	rear_wall_material.transmission_volume_db = -9.0
	rear_wall_material.transmission_lowpass_hz = 1400.0
	rear_wall.set_meta("acoustic_material", rear_wall_material)
	world.add_child(rear_wall)

	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await physics_frame
	await process_frame
	var listener_position := Vector3(0.0, 1.0, 0.0)
	var blocked := service.calculate_listener_result(
		71,
		listener_position,
		Vector3(0.0, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9001
	)
	var rays_after_first := int(
		service.get_debug_state().get("visibility_ray_count", 0)
	)
	var blocked_cached := service.calculate_listener_result(
		71,
		listener_position,
		Vector3(0.0, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9001
	)
	var rays_after_cached := int(
		service.get_debug_state().get("visibility_ray_count", 0)
	)
	var blocked_ids: PackedStringArray = blocked.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		blocked_ids.has("tiny_test_wall")
		and float(blocked.get("lowpass_hz", 20000.0)) <= 1900.01
		and bool(blocked_cached.get("audible", false)),
		"one narrow static wall affects the direct acoustic path even inside a single sparse-probe region"
	)
	_expect_rule(&"A06",
		rays_after_first > 0 and rays_after_cached == rays_after_first,
		"continuous sources reuse their short-lived direct-path check instead of raycasting every server snapshot"
	)
	var partial := service.calculate_listener_result(
		72,
		Vector3(1.5, 1.0, 0.0),
		Vector3(1.5, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9010
	)
	_expect_rule(&"A05",
		float(partial.get("direct_occlusion", 1.0)) > 0.0
		and float(partial.get("direct_occlusion", 1.0)) < 1.0
		and float(partial.get("volume_db", -80.0))
		> float(blocked.get("volume_db", 0.0)) + 3.0
		and float(partial.get("lowpass_hz", 0.0)) > 1900.0,
		"a small prop partially shadows the direct wave instead of behaving like a complete wall"
	)
	var stacked := service.calculate_listener_result(
		73,
		Vector3(2.5, 1.0, 0.0),
		Vector3(2.5, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9011
	)
	var stacked_ids: PackedStringArray = stacked.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect_rule(
		&"A05",
		is_equal_approx(float(stacked.get("direct_occlusion", 0.0)), 1.0)
		and stacked_ids.has("rear_structural_wall")
		and float(stacked.get("lowpass_hz", 20000.0)) <= 1400.01,
		"a partial prop cannot mask a structural boundary farther along the same acoustic ray"
	)
	service.calculate_listener_result(
		71,
		listener_position + Vector3(0.05, 0.0, 0.0),
		Vector3(0.0, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9001
	)
	_expect(
		int(service.get_debug_state().get("visibility_ray_count", 0))
		> rays_after_cached,
		"five centimeters of listener motion refreshes obstruction at network cadence instead of waiting on a slow timer"
	)
	service.forget_continuous_source(9001)
	service.forget_continuous_source(9010)
	service.forget_continuous_source(9011)
	_expect(
		int(service.get_debug_state().get("cached_direct_paths", -1)) == 0
		and int(service.get_debug_state().get("cached_source_attachments", -1)) == 0,
		"removing a continuous source releases its cached path and air attachment"
	)

	var barrier := AcousticMaterial.new()
	barrier.material_id = &"unrelated_probe_barrier"
	barrier.transmission_volume_db = -20.0
	barrier.transmission_lowpass_hz = 700.0
	var left_probe := service.graph.add_probe(listener_position, &"left")
	var right_probe := service.graph.add_probe(Vector3(2.0, 1.0, 5.0), &"right")
	service.graph.connect_probes(
		left_probe,
		right_probe,
		barrier.create_transmission_modifier()
	)
	var clear := service.calculate_listener_result(
		71,
		listener_position,
		Vector3(2.0, 1.0, 5.0),
		30.0,
		null,
		1.0,
		false,
		[],
		9002
	)
	var clear_ids: PackedStringArray = clear.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		bool(clear.get("audible", false))
		and not clear_ids.has("unrelated_probe_barrier")
		and float(clear.get("lowpass_hz", 0.0)) >= 19000.0
		and float(clear.get("volume_db", -80.0)) > float(blocked.get("volume_db", 0.0)),
		"a physically clear path bypasses an unrelated nearest-probe material edge instead of extending that wall to infinity"
	)
	service.queue_free()
	world.queue_free()
	await process_frame


func _test_listener_probe_blend_respects_walls() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var wall := StaticBody3D.new()
	wall.name = "ProbeBlendWall"
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(0.12, 3.0, 4.0)
	var wall_collision := CollisionShape3D.new()
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	world.add_child(wall)
	var minor_prop := StaticBody3D.new()
	minor_prop.name = "NonBoundaryProp"
	minor_prop.position = Vector3(-0.55, 1.0, 0.0)
	minor_prop.set_meta(&"acoustic_boundary", false)
	var minor_prop_shape := BoxShape3D.new()
	minor_prop_shape.size = Vector3(0.1, 2.0, 2.0)
	var minor_prop_collision := CollisionShape3D.new()
	minor_prop_collision.shape = minor_prop_shape
	minor_prop.add_child(minor_prop_collision)
	world.add_child(minor_prop)

	var indoor_probe := AcousticProbe3D.new()
	indoor_probe.name = "IndoorProbe"
	indoor_probe.probe_id = &"blend_indoor"
	indoor_probe.position = Vector3(-1.0, 1.0, 0.0)
	indoor_probe.auto_connect = false
	indoor_probe.sample_reflections = false
	world.add_child(indoor_probe)
	var outdoor_probe := AcousticProbe3D.new()
	outdoor_probe.name = "OutdoorProbe"
	outdoor_probe.probe_id = &"blend_outdoor"
	outdoor_probe.position = Vector3(1.0, 1.0, 0.0)
	outdoor_probe.auto_connect = false
	outdoor_probe.sample_reflections = false
	world.add_child(outdoor_probe)
	var nearer_blocked_probe := AcousticProbe3D.new()
	nearer_blocked_probe.name = "NearerBlockedProbe"
	nearer_blocked_probe.probe_id = &"blend_nearer_but_blocked"
	nearer_blocked_probe.position = Vector3(0.2, 1.0, 0.0)
	nearer_blocked_probe.auto_connect = false
	nearer_blocked_probe.sample_reflections = false
	world.add_child(nearer_blocked_probe)

	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await physics_frame
	await process_frame

	service.calculate_listener_result(
		702,
		Vector3(-0.10, 1.0, 0.0),
		Vector3(-1.0, 1.0, 0.5),
		30.0,
		null,
		1.0,
		false,
		[],
		7002
	)
	var field := service._fields_by_listener.get(702) as AcousticPropagationField
	var outside_probe_index := service.graph.find_nearest_probe(
		outdoor_probe.global_position
	)
	var nearer_blocked_probe_index := service.graph.find_nearest_probe(
		nearer_blocked_probe.global_position
	)
	var indoor_probe_index := service.graph.find_nearest_probe(
		indoor_probe.global_position
	)
	var includes_outside_probe := false
	if field != null:
		for listener_probe_index: int in range(field.listener_probe_count):
			if field.listener_probes[listener_probe_index] == outside_probe_index:
				includes_outside_probe = true
				break
	_expect(
		field != null
		and field.listener_probe_count == 1
		and not includes_outside_probe,
		"listener probe blending ignores a prop but rejects a nearby probe when a wall blocks it"
	)
	var source_attachment := service.create_source_attachment(
		Vector3(-0.1, 1.0, 0.0)
	)
	var includes_nearer_blocked_probe := false
	for attachment_index: int in range(source_attachment.probe_count):
		if source_attachment.probes[attachment_index] == nearer_blocked_probe_index:
			includes_nearer_blocked_probe = true
			break
	_expect(
		source_attachment.visibility_confirmed
		and source_attachment.primary_probe() == indoor_probe_index
		and not includes_nearer_blocked_probe,
		"a source attaches to collision-visible air instead of a geometrically nearer probe behind a wall"
	)
	service.queue_free()
	world.queue_free()
	await process_frame


func _test_hidden_listener_fallback_is_silent() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var wall := StaticBody3D.new()
	wall.name = "FallbackIsolationWall"
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(0.2, 4.0, 20.0)
	var wall_collision := CollisionShape3D.new()
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	world.add_child(wall)

	var far_side_probe := AcousticProbe3D.new()
	far_side_probe.name = "FarSideProbe"
	far_side_probe.probe_id = &"fallback_far_side"
	far_side_probe.position = Vector3(1.0, 1.0, 4.0)
	far_side_probe.auto_connect = false
	far_side_probe.sample_reflections = false
	world.add_child(far_side_probe)

	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await physics_frame
	await process_frame
	var listener_position := Vector3(-1.0, 1.0, 0.0)
	var source_position := Vector3(2.0, 1.0, 0.0)
	var result := service.calculate_listener_result(
		723,
		listener_position,
		source_position,
		30.0,
		null,
		1.0,
		false,
		[],
		7203
	)
	var field := service._fields_by_listener.get(723) as AcousticPropagationField
	var source_attachment := service.create_source_attachment(source_position)
	_expect_rule(
		&"A23",
		field != null
		and field.listener_probe_count == 1
		and not field.listener_probe_visibility_confirmed
		and source_attachment.visibility_confirmed
		and result.get("route_kind", &"") == &"transmitted"
		and not result.has("route_graph_energy_weight"),
		"a blocked nearest-probe fallback cannot turn a longer route through the far room into audible energy"
	)
	service.queue_free()
	world.queue_free()
	await process_frame


func _test_authored_house_propagation() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var house_scene := load(
		"res://scenes/server/acoustic_test_house.tscn"
	) as PackedScene
	var house := house_scene.instantiate()
	world.add_child(house)
	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await physics_frame
	await process_frame
	var floor_collision := house.get_node_or_null(
		"FloorCollision"
	) as CollisionShape3D
	var floor_shape := (
		floor_collision.shape as BoxShape3D
		if floor_collision != null
		else null
	)
	_expect(
		floor_shape != null
		and floor_shape.size.x >= 6.69
		and house.get_node_or_null("FrontLintelCollision") is CollisionShape3D,
		"enlarged acoustic house has a sealed physical door lintel and wider floor plan"
	)

	var radio_pad := Vector3(-0.9, 0.35, -0.55)
	var listener_pad := Vector3(-0.9, 1.35, 1.15)
	var direct_distance := radio_pad.distance_to(listener_pad)
	var around_small_wall := service.calculate_listener_result(
		81,
		listener_pad,
		radio_pad,
		40.0,
		null,
		1.0,
		false,
		[],
		8101
	)
	var unobstructed_baseline := AcousticPropagationGraph.sample_free_field(
		listener_pad,
		radio_pad,
		40.0
	)
	_expect(
		bool(around_small_wall.get("audible", false))
		and str(around_small_wall.get("route_kind", "")) == "parallel"
		and float(around_small_wall.get("direct_occlusion", 0.0)) > 0.9
		and float(around_small_wall.get("route_graph_energy_weight", 0.0)) > 0.1
		and float(around_small_wall.get("route_direct_energy_weight", 0.0)) > 0.1
		and float(around_small_wall.get("path_length", INF))
		< direct_distance + 1.0
		and float(around_small_wall.get("volume_db", -80.0))
		> float(unobstructed_baseline.get("volume_db", 0.0)) - 2.0
		and float(around_small_wall.get("lowpass_hz", 0.0)) >= 8000.0,
		"the small indoor panel mixes transmitted and wrapped energy instead of isolating two fake rooms"
	)

	var through_open_door := service.calculate_listener_result(
		82,
		Vector3(0.0, 1.35, 4.4),
		Vector3(0.0, 1.35, 0.4),
		40.0,
		null,
		1.0,
		false,
		[],
		8102
	)
	var door_ids: PackedStringArray = through_open_door.get(
		"modifier_ids",
		PackedStringArray()
	)
	_expect(
		bool(through_open_door.get("audible", false))
		and absf(float(through_open_door.get("path_length", 0.0)) - 4.0) < EPSILON
		and not door_ids.has("test_house_wall"),
		"sound travels cleanly through the test house's physical open doorway"
	)
	var left_front := service.calculate_listener_result(
		83,
		Vector3(-1.7, 1.45, 3.5),
		Vector3(-1.7, 1.45, 2.4),
		40.0,
		null,
		1.0,
		false,
		[],
		8103
	)
	var right_front := service.calculate_listener_result(
		84,
		Vector3(1.7, 1.45, 3.5),
		Vector3(1.7, 1.45, 2.4),
		40.0,
		null,
		1.0,
		false,
		[],
		8104
	)
	_expect(
		bool(left_front.get("audible", false))
		and bool(right_front.get("audible", false))
		and absf(
			float(left_front.get("volume_db", -80.0))
			- float(right_front.get("volume_db", -80.0))
		) < 0.25
		and absf(
			float(left_front.get("path_length", 0.0))
			- float(right_front.get("path_length", 0.0))
		) < 0.05,
		"mirrored walls beside the entrance have matching transmission and doorway-route geometry"
	)
	var indoor_response := service.calculate_listener_result(
		85,
		Vector3(1.2, 1.35, 0.0),
		Vector3(1.2, 1.35, -1.0),
		40.0,
		null,
		1.0,
		false,
		[],
		8105
	)
	var outdoor_response := service.calculate_listener_result(
		86,
		Vector3(8.0, 1.35, 5.0),
		Vector3(8.0, 1.35, 4.0),
		40.0,
		null,
		1.0,
		false,
		[],
		8106
	)
	_expect(
		float(indoor_response.get("reverb_send", 0.0))
		> float(outdoor_response.get("reverb_send", 1.0)) + 0.15
		and float(indoor_response.get("environment_enclosure", 0.0)) > 0.55,
		"authored house geometry creates reflections while the nearby open field lets them escape"
	)
	_expect(
		float(indoor_response.get("diffuse_field_gain_db", 0.0)) > 0.1
		and float(indoor_response.get("diffuse_field_support", 0.0)) > 0.25
		and float(indoor_response.get("diffuse_critical_distance", 0.0))
		> AcousticPropagationGraph.MIN_DIFFUSE_CRITICAL_DISTANCE
		and is_zero_approx(
			float(outdoor_response.get("diffuse_field_gain_db", 0.0))
		),
		"the shared indoor volume supports reflected energy while open air keeps spherical spreading"
	)
	service.queue_free()
	world.queue_free()
	await process_frame


func _test_scene_graph_rebuild() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var first := AcousticProbe3D.new()
	first.name = "First"
	first.probe_id = &"first"
	world.add_child(first)
	var second := AcousticProbe3D.new()
	second.name = "Second"
	second.probe_id = &"second"
	second.position = Vector3(3.0, 0.0, 0.0)
	world.add_child(second)
	var portal := AcousticPortal3D.new()
	portal.name = "Portal"
	portal.probe_a_path = NodePath("../First")
	portal.probe_b_path = NodePath("../Second")
	var modifier := AcousticPathModifier.new()
	modifier.modifier_id = &"test_portal"
	portal.modifier = modifier
	world.add_child(portal)

	var service := ServerAcousticService.new()
	root.add_child(service)
	service.bind_world(world)
	await process_frame
	var debug := service.get_debug_state()
	_expect(
		int(debug.get("probe_count", 0)) == 2,
		"server discovers authored acoustic probes"
	)
	_expect(
		int(debug.get("directed_edge_count", 0)) == 2,
		"explicit bidirectional portal builds one edge each way"
	)
	service.queue_free()
	world.queue_free()


func _test_server_world_binding() -> void:
	var server := root.get_node_or_null("Server")
	_expect(server != null, "server autoload is available to the acoustic bridge")
	if server == null:
		return
	server.call("spawn_server_world")
	await process_frame
	await process_frame
	var debug: Dictionary = server.call("get_acoustic_debug_state")
	_expect(
		int(debug.get("probe_count", 0)) >= 10,
		"server world binds warehouse and acoustic-house probes to the authoritative service"
	)


func _test_fixed_source_air_route() -> void:
	var server := root.get_node_or_null("Server")
	var service := (
		server.get("acoustic_service") as ServerAcousticService
		if server != null
		else null
	)
	var server_world := (
		server.get("server_world") as Node3D if server != null else null
	)
	var cluster := (
		server_world.get_node_or_null("SpeakerClusterDemo")
		as ServerSpeakerCluster
		if server_world != null
		else null
	)
	if cluster == null or service == null:
		_expect_rule(
			&"A18",
			false,
			"fixed-source routing requires the authoritative bunker"
		)
		return
	var emitter_id := SPEAKER_CLUSTER_LAYOUT.emitter_id(2)
	var exterior_descriptor: Dictionary = (
		SPEAKER_CLUSTER_LAYOUT.speaker_descriptors()[2]
	)
	var source_position := cluster.global_transform * (
		SPEAKER_CLUSTER_LAYOUT.speaker_source_local_position(
			exterior_descriptor
		)
	)
	var near_listener := cluster.global_transform * Vector3(
		SPEAKER_CLUSTER_LAYOUT.DOOR_CENTER_X,
		1.55,
		-5.8
	)
	var rear_listener := cluster.global_transform * Vector3(
		-0.4,
		1.55,
		5.0
	)
	service.forget_continuous_source(emitter_id)
	var solves_before := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	var near_state := service.calculate_listener_result(
		8810,
		near_listener,
		source_position,
		165.0,
		null,
		1.0,
		false,
		[],
		emitter_id
	)
	var solves_after_near := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	var rear_state := service.calculate_listener_result(
		8811,
		rear_listener,
		source_position,
		165.0,
		null,
		1.0,
		false,
		[],
		emitter_id
	)
	var solves_after_rear := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	service.calculate_listener_result(
		8812,
		near_listener,
		source_position + Vector3(0.1, 0.0, 0.0),
		165.0,
		null,
		1.0,
		false,
		[],
		emitter_id
	)
	var solves_after_small_move := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	service.calculate_listener_result(
		8813,
		near_listener,
		source_position + Vector3(0.4, 0.0, 0.0),
		165.0,
		null,
		1.0,
		false,
		[],
		emitter_id
	)
	var solves_after_large_move := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	var one_shot_attachment := service.create_source_attachment(source_position)
	var one_shot_emission := service.create_pressure_emission(
		source_position,
		0.8,
		[],
		one_shot_attachment
	)
	var solves_after_one_shot_bake := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	var one_shot_near := service.calculate_listener_result(
		8814,
		near_listener,
		source_position,
		165.0,
		null,
		1.0,
		false,
		[],
		0,
		0.8,
		one_shot_emission,
		one_shot_attachment
	)
	var one_shot_rear := service.calculate_listener_result(
		8815,
		rear_listener,
		source_position,
		165.0,
		null,
		1.0,
		false,
		[],
		0,
		0.8,
		one_shot_emission,
		one_shot_attachment
	)
	var solves_after_one_shot_listeners := int(
		service.get_debug_state().get("source_attachment_solve_count", 0)
	)
	var near_modifiers: PackedStringArray = near_state.get(
		"modifier_ids",
		PackedStringArray()
	)
	var rear_modifiers: PackedStringArray = rear_state.get(
		"modifier_ids",
		PackedStringArray()
	)
	var has_emitter_specific_probe := false
	for descriptor: Dictionary in (
		SPEAKER_CLUSTER_LAYOUT.acoustic_probe_descriptors()
	):
		has_emitter_specific_probe = (
			has_emitter_specific_probe
			or str(descriptor.get("probe_id", &"")).contains("speaker")
		)
	_expect_rule(
		&"A18",
		not has_emitter_specific_probe
		and not near_state.is_empty()
		and not rear_state.is_empty()
		and not near_modifiers.has("garage_concrete_metal")
		and not rear_modifiers.has("garage_concrete_metal")
		and float(near_state.get("path_length", 0.0))
		> near_listener.distance_to(source_position) + 0.5
		and float(rear_state.get("volume_db", -80.0))
		> float(near_state.get("volume_db", -80.0)) - 18.0
		and solves_after_near == solves_before + 1
		and solves_after_rear == solves_after_near
		and solves_after_small_move == solves_after_rear
		and solves_after_large_move == solves_after_small_move + 1
		and solves_after_one_shot_bake == solves_after_large_move + 1
		and solves_after_one_shot_listeners == solves_after_one_shot_bake
		and not (one_shot_near.get("pressure_arrivals", []) as Array).is_empty()
		and not (one_shot_rear.get("pressure_arrivals", []) as Array).is_empty(),
		"every source caches collision-visible air endpoints and the entrance PA routes around its header without an emitter-specific probe"
	)


func _test_nature_acoustic_registration() -> void:
	var server := root.get_node_or_null("Server")
	var service := (
		server.get("acoustic_service") as ServerAcousticService
		if server != null
		else null
	)
	var server_world := (
		server.get("server_world") as Node3D if server != null else null
	)
	if service == null or server_world == null:
		_expect_rule(&"A14", false, "nature acoustics require the authoritative world")
		return
	var nature := server_world.get_node_or_null("WorldNature") as Node3D
	var tree_body := (
		nature.get_node_or_null("TreeCollision") as StaticBody3D
		if nature != null
		else null
	)
	var tree_material := (
		tree_body.get_meta(&"acoustic_material") as AcousticMaterial
		if tree_body != null
		else null
	)
	var forest_probe_count := 0
	for node: Node in get_nodes_in_group(&"acoustic_probes"):
		if (
			node is AcousticProbe3D
			and nature != null
			and nature.is_ancestor_of(node)
		):
			forest_probe_count += 1
	var acoustic_debug_before := service.get_debug_state()
	var environment_rays_before := int(
		acoustic_debug_before.get("environment_ray_count", 0)
	)
	var open_result := service.calculate_listener_result(
		8801,
		Vector3(8.0, 1.6, 5.0),
		Vector3(8.0, 1.6, 3.0),
		165.0,
		null,
		1.0,
		false,
		[],
		0,
		1.0
	)
	var forest_result := service.calculate_listener_result(
		8802,
		Vector3(75.0, 1.6, -40.0),
		Vector3(75.0, 1.6, -42.0),
		165.0,
		null,
		1.0,
		false,
		[],
		0,
		1.0
	)
	var environment_rays_after := int(
		service.get_debug_state().get("environment_ray_count", 0)
	)
	var isolated_trunk_path: Dictionary = {}
	var exterior_speaker: Dictionary = (
		SPEAKER_CLUSTER_LAYOUT.speaker_descriptors()[2]
	)
	var exterior_source := SPEAKER_CLUSTER_LAYOUT.WORLD_POSITION + (
		SPEAKER_CLUSTER_LAYOUT.speaker_source_local_position(exterior_speaker)
	)
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
		var candidate := service._sample_direct_path(
			8890,
			listener_position,
			exterior_source,
			[],
			0
		)
		var candidate_modifier := candidate.get("modifier") as AcousticPathModifier
		if (
			bool(candidate.get("blocked", false))
			and candidate_modifier != null
			and candidate_modifier.modifier_id == &"outdoor_wood"
		):
			isolated_trunk_path = candidate
			break
	_expect_rule(
		&"A06",
		forest_probe_count >= 100
		and (
			environment_rays_before > forest_probe_count * 40
			or (
				bool(acoustic_debug_before.get("bake_loaded_from_cache", false))
				and int(acoustic_debug_before.get("bake_cache_load_count", 0)) > 0
			)
		)
		and environment_rays_after == environment_rays_before,
		"forest surfaces are sampled during graph rebuild and runtime shots reuse the bake"
	)
	print(
		"Nature acoustic contrast: reverb %.3f/%.3f, pressure %.3f/%.3f, decay %.3f/%.3f, trunk %.3f"
		% [
			float(forest_result.get("reverb_send", 0.0)),
			float(open_result.get("reverb_send", 0.0)),
			float(forest_result.get("pressure_reverb_send", 0.0)),
			float(open_result.get("pressure_reverb_send", 0.0)),
			float(forest_result.get("reverb_decay_seconds", 0.0)),
			float(open_result.get("reverb_decay_seconds", 0.0)),
			float(isolated_trunk_path.get("occlusion", 0.0)),
		]
	)
	_expect_rule(
		&"A14",
		tree_material != null
		and tree_material.material_id == &"outdoor_wood"
		and not bool(tree_body.get_meta(&"acoustic_boundary", true))
		and float(tree_body.get_meta(&"acoustic_max_partial_occlusion", 1.0)) <= 0.3
		and float(isolated_trunk_path.get("occlusion", 1.0)) > 0.0
		and float(isolated_trunk_path.get("occlusion", 1.0))
		<= float(tree_body.get_meta(&"acoustic_max_partial_occlusion", 0.0)) + 0.001
		and float(forest_result.get("reverb_send", 0.0))
		> float(open_result.get("reverb_send", 0.0)) + 0.04
		and float(forest_result.get("pressure_reverb_send", 0.0))
		> float(open_result.get("pressure_reverb_send", 0.0)) + 0.02
		and float(forest_result.get("pressure_reverb_send", 0.0))
		> float(open_result.get("pressure_reverb_send", 0.0)) * 1.5
		and float(forest_result.get("reverb_decay_seconds", 0.0)) > 0.3
		and float(forest_result.get("reverb_decay_seconds", 0.0)) < 1.2
		and (
			float(forest_result.get("reverb_send", 0.0))
			* float(forest_result.get("reverb_decay_seconds", 0.0))
		) > (
			float(open_result.get("reverb_send", 0.0))
			* float(open_result.get("reverb_decay_seconds", 0.0))
		) + 0.03,
		"the forest bake adds a short wood-scattered response while one real trunk covers only part of a direct wave"
	)


func _test_server_to_client_bridge() -> void:
	var server := root.get_node_or_null("Server")
	var client := root.get_node_or_null("Client")
	var game_state := root.get_node_or_null("GameState")
	if server == null or client == null or game_state == null:
		_expect(false, "audio bridge autoloads exist")
		return
	var player_id: int = game_state.call("try_register_player", 1, 1000, 4)
	if player_id < 0:
		player_id = int(game_state.call("get_player_id", 1))
	server.call(
		"spawn_server_player",
		player_id,
		Vector3(0.0, 1.0, 0.0),
		null,
		null
	)
	client.connect(
		"spatial_sound_received",
		func(packet: Dictionary) -> void:
			if packet.get("sound_id", &"") == &"network_test":
				network_packet_received = true
				automatic_pressure_network_packet_received = not (
					packet.get("pressure_arrivals", []) as Array
				).is_empty()
			elif packet.get("sound_id", &"") == &"network_pressure_test":
				pressure_network_packet_received = not (
					packet.get("pressure_arrivals", []) as Array
				).is_empty()
			elif packet.get("sound_id", &"") == &"network_no_pressure_test":
				disabled_pressure_network_packet_received = (
					packet.get("pressure_arrivals", []) as Array
				).is_empty()
			elif packet.get("sound_id", &"") == &"fieldlink_open":
				fieldlink_network_packet_received = true
			elif packet.get("sound_id", &"") == &"quiet_range_test":
				quiet_range_network_packet_received = true
			elif packet.get("sound_id", &"") == &"loud_range_test":
				loud_range_network_packet_received = true
			elif packet.get("sound_id", &"") == &"service_pistol_fire":
				pistol_acoustic_packet = packet.duplicate(true)
			elif packet.get("sound_id", &"") == &"automatic_rifle_fire":
				rifle_acoustic_packet = packet.duplicate(true)
	)
	var fieldlink_player := server.call(
		"get_server_player",
		player_id
	) as ServerPlayer
	if fieldlink_player != null:
		fieldlink_player.set_wrist_interface_open(true)
	await process_frame
	_expect_rule(&"A01",
		fieldlink_network_packet_received,
		"authoritative Fieldlink use reaches the ordinary multiplayer acoustic bridge"
	)
	server.call(
		"emit_spatial_sound",
		&"network_test",
		Vector3(0.0, 1.0, 2.0),
		30.0,
		0.0,
		null,
		0.5
	)
	await process_frame
	_expect(
		network_packet_received and automatic_pressure_network_packet_received,
		"ordinary server one-shots automatically include their baked source response"
	)
	var listener_position := (
		fieldlink_player.get_audio_listener_position()
		if fieldlink_player != null
		else Vector3(0.0, 1.0, 0.0)
	)
	var far_source_position := listener_position + Vector3.UP * 45.0
	server.call(
		"emit_spatial_sound",
		&"quiet_range_test",
		far_source_position,
		30.0,
		0.0,
		null,
		0.5,
		0.0
	)
	server.call(
		"emit_spatial_sound",
		&"loud_range_test",
		far_source_position,
		30.0,
		6.0206,
		null,
		0.5,
		0.0
	)
	await process_frame
	_expect(
		not quiet_range_network_packet_received
		and loud_range_network_packet_received,
		"server distribution reaches a listener beyond nominal range only when source level supports it"
	)
	var pressure_builds_before := int(
		(server.call("get_acoustic_debug_state") as Dictionary).get(
			"pressure_emission_build_count",
			0
		)
	)
	server.call(
		"emit_spatial_sound",
		&"network_pressure_test",
		Vector3(0.0, 1.0, 2.0),
		30.0,
		0.0,
		null,
		0.9,
		0.8
	)
	await process_frame
	var pressure_builds_after := int(
		(server.call("get_acoustic_debug_state") as Dictionary).get(
			"pressure_emission_build_count",
			0
		)
	)
	_expect(
		pressure_network_packet_received
		and pressure_builds_after == pressure_builds_before + 1,
		"one baked source emission serves the server-to-client pressure event"
	)
	var disabled_builds_before := pressure_builds_after
	server.call(
		"emit_spatial_sound",
		&"network_no_pressure_test",
		Vector3(0.0, 1.0, 2.0),
		30.0,
		0.0,
		null,
		0.5,
		0.0
	)
	await process_frame
	var disabled_builds_after := int(
		(server.call("get_acoustic_debug_state") as Dictionary).get(
			"pressure_emission_build_count",
			0
		)
	)
	_expect(
		disabled_pressure_network_packet_received
		and disabled_builds_after == disabled_builds_before,
		"an explicit zero opts a one-shot out without preparing pressure state"
	)
	if fieldlink_player != null:
		# Put the authoritative ears at the house's interior probe and fire both receiver profiles
		# from the same muzzle point. Sound identity may select recordings, never propagation.
		fieldlink_player.global_position = Vector3(12.0, 0.89, -4.65)
		var indoor_listener := fieldlink_player.get_audio_listener_position()
		var indoor_source := indoor_listener + Vector3(0.0, 0.0, -0.8)
		var pistol := load(
			"res://resources/items/guns/basic_service_pistol.tres"
		) as GunItemDefinition
		var rifle := load(
			"res://resources/items/guns/warehouse_automatic_rifle.tres"
		) as GunItemDefinition
		var pistol_profile := pistol.default_build.get_fire_sound_profile()
		var rifle_profile := rifle.default_build.get_fire_sound_profile()
		for profile: Dictionary in [pistol_profile, rifle_profile]:
			server.call(
				"emit_spatial_sound",
				profile.get("sound_id", &""),
				indoor_source,
				float(profile.get("max_distance", 1.0)),
				float(profile.get("volume_db", 0.0)),
				null,
				float(profile.get("priority", 0.5)),
				float(profile.get("pressure_strength", 0.0))
			)
		await process_frame
	_expect_rule(
		&"A15",
		not pistol_acoustic_packet.is_empty()
		and not rifle_acoustic_packet.is_empty()
		and float(pistol_acoustic_packet.get("reverb_send", 0.0)) > 0.2
		and float(rifle_acoustic_packet.get("reverb_send", 0.0)) > 0.2
		and not (pistol_acoustic_packet.get("pressure_arrivals", []) as Array).is_empty()
		and not (rifle_acoustic_packet.get("pressure_arrivals", []) as Array).is_empty()
		and is_equal_approx(
			float(pistol_acoustic_packet.get("reverb_room_size", 0.0)),
			float(rifle_acoustic_packet.get("reverb_room_size", 1.0))
		),
		"pistol and rifle packets both carry the same simulated indoor hall and pressure routes"
	)


func _expect_rule(rule_id: StringName, condition: bool, label: String) -> void:
	var known_rule := false
	for rule: Dictionary in ACOUSTIC_RULE_CONTRACT:
		if rule.get("id", &"") == rule_id:
			known_rule = true
			break
	if condition and known_rule:
		_satisfied_acoustic_rules[rule_id] = true
	_expect(
		condition and known_rule,
		"[%s] %s" % [rule_id, label]
	)


func _assert_complete_rule_coverage() -> void:
	var missing := PackedStringArray()
	var unique_ids: Dictionary[StringName, bool] = {}
	for rule: Dictionary in ACOUSTIC_RULE_CONTRACT:
		var rule_id: StringName = rule.get("id", &"")
		if rule_id.is_empty() or unique_ids.has(rule_id):
			missing.append("invalid-or-duplicate:%s" % rule_id)
			continue
		unique_ids[rule_id] = true
		if not _satisfied_acoustic_rules.has(rule_id):
			missing.append(str(rule_id))
	_expect(
		missing.is_empty(),
		"every normative acoustic rule has passing behavioral evidence (missing: %s)"
		% ", ".join(missing)
	)


func _expect(condition: bool, label: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)

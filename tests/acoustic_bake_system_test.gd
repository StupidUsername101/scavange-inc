extends SceneTree

const EPSILON := 0.0001
const TEST_ARTIFACT_PATH := "res://tests/generated/acoustic_bake_roundtrip_test.sacb"
const TEST_SERVICE_CACHE_PATH := "res://tests/generated/acoustic_service_cache_test.sacb"
const TEST_SIGNATURE := "acoustic-bake-roundtrip-v1"

var failure_count := 0
var assertion_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_static_boundary_accumulation()
	_test_baked_image_source_reflections()
	_test_graph_and_artifact_roundtrip()
	await _test_service_cache_fallback()
	if failure_count == 0:
		print("Acoustic bake tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Acoustic bake tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)


func _test_static_boundary_accumulation() -> void:
	var bake := AcousticStaticBoundaryBake.new()
	var wall := AcousticPathModifier.new()
	wall.modifier_id = &"test_concrete"
	wall.band_gain = Vector3(0.8, 0.5, 0.25)
	wall.volume_db = -4.0
	wall.extra_delay_seconds = 0.002
	wall.lowpass_hz = 2400.0
	wall.reverb_send = 0.2

	# The first two boxes overlap and represent adjacent pieces of one physical wall. The bake must
	# merge that interval, while the separated boxes remain independent transmission boundaries.
	_expect(
		bake.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 2.0)), Vector3(4.0, 4.0, 0.20), wall),
		"static bake accepts a structural box"
	)
	_expect(
		bake.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 2.05)), Vector3(4.0, 4.0, 0.20), wall),
		"static bake accepts an overlapping modular wall piece"
	)
	_expect(
		bake.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 5.0)), Vector3(4.0, 4.0, 0.20), wall),
		"static bake accepts a second boundary"
	)
	_expect(
		bake.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 8.0)), Vector3(4.0, 4.0, 0.20), wall),
		"static bake accepts a third boundary"
	)

	var sampled := bake.sample_transmission(Vector3.ZERO, Vector3(0.0, 0.0, 10.0))
	var modifier := sampled.get("modifier") as AcousticPathModifier
	_expect(
		int(sampled.get("crossing_count", 0)) == 3,
		"overlapping modular pieces merge while separated walls accumulate"
	)
	_expect(modifier != null, "cumulative transmission returns one reusable modifier")
	if modifier != null:
		_expect(
			absf(modifier.volume_db - -12.0) <= EPSILON,
			"three distinct walls add their decibel transmission loss"
		)
		_expect(
			modifier.band_gain.is_equal_approx(Vector3(0.512, 0.125, 0.015625)),
			"three distinct walls multiply nonlinear spectral transmission"
		)
		_expect(
			absf(modifier.extra_delay_seconds - 0.006) <= EPSILON,
			"three distinct walls accumulate bounded material delay"
		)

	var imported := AcousticStaticBoundaryBake.new()
	_expect(
		imported.import_bake_data(bake.export_bake_data()),
		"static boundary index round-trips through value-only bake data"
	)
	var imported_sample := imported.sample_transmission(
		Vector3.ZERO,
		Vector3(0.0, 0.0, 10.0)
	)
	_expect(
		int(imported_sample.get("crossing_count", 0)) == 3,
		"imported static boundary index preserves crossing topology"
	)


func _test_baked_image_source_reflections() -> void:
	var concrete := AcousticMaterial.new()
	concrete.material_id = &"valve_reference_concrete"
	concrete.absorption = Vector3(0.05, 0.07, 0.08)
	concrete.scattering = 0.05
	var bake := AcousticStaticBoundaryBake.new()
	_expect(
		bake.add_box(
			Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 5.0)),
			Vector3(12.0, 6.0, 0.2),
			concrete.create_transmission_modifier(),
			concrete
		),
		"reflection fixture bakes Valve material data with its wall face"
	)
	var listener := Vector3(2.0, 0.0, 0.0)
	var source := Vector3(-2.0, 0.0, 0.0)
	var taps := bake.sample_early_reflections(
		listener,
		source,
		listener.distance_to(source)
	)
	_expect(
		taps.size() == 1
		and float(taps[0].get("extra_delay_seconds", 0.0)) > 0.015
		and float(taps[0].get("extra_delay_seconds", 1.0)) < 0.025
		and float(taps[0].get("gain", 0.0)) > 0.1,
		"baked image-source sampling returns one finite first-order wall reflection"
	)
	var restored := AcousticStaticBoundaryBake.new()
	_expect(
		restored.import_bake_data(bake.export_bake_data())
		and restored.sample_early_reflections(
			listener,
			source,
			listener.distance_to(source)
		).size() == taps.size(),
		"reflection coefficients and reflector topology survive the bake cache round trip"
	)


func _test_graph_and_artifact_roundtrip() -> void:
	var graph := AcousticPropagationGraph.new()
	var listener_probe := graph.add_probe(
		Vector3.ZERO,
		&"bake_listener",
		0.0,
		Vector3(INF, INF, INF),
		Vector3.ZERO,
		0.5,
		{},
		Vector3(20.0, 1.0, 0.0),
		Vector3(2.0, 2.0, 2.0),
		Vector3.ZERO,
		Vector3(2.0, 2.0, 2.0),
		1.0
	)
	var doorway_probe := graph.add_probe(Vector3(0.0, 0.0, 4.0), &"bake_door")
	var source_probe := graph.add_probe(Vector3(4.0, 0.0, 4.0), &"bake_source")
	var room_response := AcousticEnvironmentModel.open_air_response()
	room_response["enclosure"] = 0.9
	room_response["effective_volume_m3"] = 96.0
	room_response["rt60_seconds"] = 0.85
	room_response["reverb_send"] = 0.42
	for probe_index: int in range(graph.probe_count()):
		_expect(
			graph.set_probe_environment(probe_index, room_response),
			"test graph accepts a baked environment response"
		)

	var doorway := AcousticPathModifier.new()
	doorway.modifier_id = &"bake_doorway"
	doorway.band_gain = Vector3(0.94, 0.82, 0.65)
	doorway.volume_db = -1.5
	doorway.extra_delay_seconds = 0.004
	doorway.lowpass_hz = 6200.0
	doorway.reverb_send = 0.16
	_expect(graph.connect_probes(listener_probe, doorway_probe), "test graph connects its first hop")
	_expect(
		graph.connect_probes(doorway_probe, source_probe, doorway, true, true),
		"test graph connects and marks its guided material hop"
	)
	_expect(
		graph.connect_diffuse_probes(listener_probe, doorway_probe),
		"test graph bakes a diffuse-volume link"
	)
	_expect(
		graph.connect_diffuse_probes(doorway_probe, source_probe),
		"test graph bakes its second diffuse-volume link"
	)
	graph.rebuild_guided_regions()
	graph.rebuild_diffuse_regions()

	var boundaries := AcousticStaticBoundaryBake.new()
	_expect(
		boundaries.add_box(
			Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 2.0)),
			Vector3(0.2, 3.0, 3.0),
			doorway
		),
		"artifact fixture contains one static boundary"
	)
	_expect(
		AcousticBakeArtifact.save_atomic(
			TEST_ARTIFACT_PATH,
			TEST_SIGNATURE,
			graph.export_bake_data(),
			boundaries.export_bake_data()
		),
		"versioned acoustic artifact saves through a temporary file"
	)

	var payload := AcousticBakeArtifact.load_validated(
		TEST_ARTIFACT_PATH,
		TEST_SIGNATURE
	)
	_expect(not payload.is_empty(), "matching artifact signature loads")
	_expect(
		AcousticBakeArtifact.load_validated(TEST_ARTIFACT_PATH, "stale-world").is_empty(),
		"stale world signature rejects the artifact and forces a normal rebuild"
	)

	var restored_graph := AcousticPropagationGraph.new()
	var restored_boundaries := AcousticStaticBoundaryBake.new()
	_expect(
		restored_graph.import_bake_data(payload.get("graph", {})),
		"graph restores from validated value-only data"
	)
	_expect(
		restored_boundaries.import_bake_data(payload.get("static_boundaries", {})),
		"static boundary broadphase restores from validated value-only data"
	)
	_expect(
		restored_graph.probe_count() == graph.probe_count()
		and restored_graph.edge_count() == graph.edge_count(),
		"restored graph preserves probe and directed-edge topology"
	)
	_expect(
		restored_graph.diffuse_region_id(listener_probe)
		== restored_graph.diffuse_region_id(source_probe),
		"restored diffuse links preserve shared room ownership"
	)
	_expect(
		not graph.probe_allows_attachment(listener_probe, Vector3(20.0, 1.0, 0.0))
		and graph.probe_allows_attachment(listener_probe, Vector3.ZERO)
		and not restored_graph.probe_allows_attachment(
			listener_probe,
			Vector3(20.0, 1.0, 0.0)
		),
		"attachment exclusion volumes survive the graph bake round trip"
	)
	_expect(
		not graph.probe_allows_attachment(listener_probe, Vector3(4.0, 0.0, 0.0))
		and graph.probe_attachment_strength(
			listener_probe,
			Vector3(2.5, 0.0, 0.0)
		) > 0.0
		and is_equal_approx(
			restored_graph.probe_attachment_strength(
				listener_probe,
				Vector3(2.5, 0.0, 0.0)
			),
			graph.probe_attachment_strength(
				listener_probe,
				Vector3(2.5, 0.0, 0.0)
			)
		),
		"continuous attachment influence volumes survive the graph bake round trip"
	)

	var original_result := _sample_fixture_graph(graph)
	var restored_result := _sample_fixture_graph(restored_graph)
	_expect(
		bool(restored_result.get("audible", false)),
		"restored route remains audible"
	)
	_expect(
		absf(
			float(restored_result.get("volume_db", -80.0))
			- float(original_result.get("volume_db", -80.0))
		) <= EPSILON,
		"restored route preserves calculated level"
	)
	_expect(
		(restored_result.get("band_gain", Vector3.ONE) as Vector3).is_equal_approx(
			original_result.get("band_gain", Vector3.ONE) as Vector3
		),
		"restored route preserves nonlinear spectral response"
	)
	_expect(
		absf(
			float(restored_result.get("travel_delay_seconds", 0.0))
			- float(original_result.get("travel_delay_seconds", 0.0))
		) <= EPSILON,
		"restored route preserves physical delay"
	)


func _sample_fixture_graph(graph: AcousticPropagationGraph) -> Dictionary:
	var field := AcousticPropagationField.new()
	graph.solve_from_position(Vector3.ZERO, field)
	return graph.sample_source(
		field,
		Vector3(4.0, 0.0, 4.0),
		40.0,
		null,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		Vector3.ZERO
	)


func _test_service_cache_fallback() -> void:
	var world := Node3D.new()
	world.name = "AcousticBakeServiceFixture"
	get_root().add_child(world)
	for probe_index: int in range(2):
		var probe := AcousticProbe3D.new()
		probe.name = "Probe%d" % probe_index
		probe.probe_id = StringName("service_bake_probe_%d" % probe_index)
		probe.position = Vector3(0.0, 0.0, float(probe_index) * 4.0)
		probe.sample_reflections = false
		world.add_child(probe)

	var building_service := ServerAcousticService.new()
	building_service.name = "BuildingService"
	building_service.configure_bake_cache(true, TEST_SERVICE_CACHE_PATH)
	get_root().add_child(building_service)
	building_service.bind_world(world)
	await process_frame
	await process_frame
	var built_state := building_service.get_debug_state()
	_expect(
		int(built_state.get("bake_cache_write_count", 0)) == 1
		and not bool(built_state.get("bake_loaded_from_cache", true)),
		"cache miss performs the ordinary graph build and writes one artifact"
	)
	var original_signature := str(built_state.get("bake_signature", ""))
	building_service.queue_free()
	await process_frame

	var loading_service := ServerAcousticService.new()
	loading_service.name = "LoadingService"
	loading_service.configure_bake_cache(true, TEST_SERVICE_CACHE_PATH)
	get_root().add_child(loading_service)
	loading_service.bind_world(world)
	await process_frame
	await process_frame
	var loaded_state := loading_service.get_debug_state()
	_expect(
		bool(loaded_state.get("bake_loaded_from_cache", false))
		and int(loaded_state.get("bake_cache_load_count", 0)) == 1,
		"unchanged world loads the baked graph instead of tracing it again"
	)
	_expect(
		str(loaded_state.get("bake_signature", "")) == original_signature,
		"cache validation uses a stable world signature"
	)
	_expect(
		int(loaded_state.get("visibility_ray_count", -1)) == 0
		and int(loaded_state.get("environment_ray_count", -1)) == 0,
		"cache hit performs no probe-visibility or environment ray bake"
	)

	# Moving a probe changes the signature. The same stale cache must be ignored safely and replaced
	# by a normal rebuild; users never need to delete cache files after editing a level.
	var moved_probe := world.get_node("Probe1") as AcousticProbe3D
	moved_probe.position.z += 0.5
	loading_service.queue_free()
	await process_frame
	var invalidating_service := ServerAcousticService.new()
	invalidating_service.name = "InvalidatingService"
	invalidating_service.configure_bake_cache(true, TEST_SERVICE_CACHE_PATH)
	get_root().add_child(invalidating_service)
	invalidating_service.bind_world(world)
	await process_frame
	await process_frame
	var invalidated_state := invalidating_service.get_debug_state()
	_expect(
		not bool(invalidated_state.get("bake_loaded_from_cache", true))
		and int(invalidated_state.get("bake_cache_rejection_count", 0)) == 1
		and int(invalidated_state.get("bake_cache_write_count", 0)) == 1,
		"changed geometry rejects stale data, rebuilds, and refreshes the cache"
	)

	invalidating_service.queue_free()
	world.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("[PASS] ", message)
		return
	failure_count += 1
	push_error("[FAIL] %s" % message)

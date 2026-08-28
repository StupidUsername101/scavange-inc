class_name ServerAcousticService
extends Node

const LOCAL_AUDIO_PREDICTION := preload(
	"res://scripts/audio/local_audio_prediction.gd"
)

const FIELD_REFRESH_DISTANCE := 0.24
const FIELD_REFRESH_DISTANCE_SQUARED := (
	FIELD_REFRESH_DISTANCE * FIELD_REFRESH_DISTANCE
)
const AUTO_CONNECT_BUCKET_SIZE := 12.0
const DIRECT_PATH_CACHE_SECONDS := 0.08
const DIRECT_PATH_LISTENER_REFRESH_DISTANCE := 0.04
const DIRECT_PATH_SOURCE_REFRESH_DISTANCE := 0.03
const DIRECT_PATH_EDGE_BLEND_DISTANCE := 0.75
const DIRECT_PATH_EDGE_BLEND_SECONDS := 0.16
const MAX_IGNORED_DIRECT_PATH_BODIES := 3
const PARTIAL_OCCLUSION_SAMPLE_RADIUS := 0.65
const PARTIAL_OCCLUSION_SAMPLE_COUNT := 5
const META_MAX_PARTIAL_OCCLUSION := &"acoustic_max_partial_occlusion"
const ACOUSTIC_BAKE_BEHAVIOR_VERSION := 2
const EARLY_REFLECTION_REFRESH_DISTANCE := 0.40
const EARLY_REFLECTION_REFRESH_DISTANCE_SQUARED := (
	EARLY_REFLECTION_REFRESH_DISTANCE * EARLY_REFLECTION_REFRESH_DISTANCE
)
const LISTENER_PROBE_CANDIDATE_COUNT := 16
const LISTENER_GUIDED_REGION_CANDIDATE_COUNT := 24
const LISTENER_GUIDED_PROBES_PER_REGION := 4
# Local room fidelity and distant waveguide routing have separate bounded budgets. Reserving guide
# slots inside the old eight-probe total made every newly authored tunnel evict valid room samples.
const LISTENER_PROBE_BASE_BLEND_COUNT := 8
const LISTENER_PROBE_BLEND_COUNT := 14
const LISTENER_PROBE_SOFT_VISIBILITY_MIN_DISTANCE := 4.0
const LISTENER_GUIDED_PROBE_MAX_ATTACHMENT_DISTANCE := 24.0
const LISTENER_PROBE_SOFT_VISIBILITY_RADIUS := 0.75
const LISTENER_PROBE_SOFT_VISIBILITY_SAMPLE_COUNT := 17
const LISTENER_PROBE_STRENGTH_BLEND_DISTANCE := 0.75
const SOURCE_PROBE_CANDIDATE_COUNT := 12
const SOURCE_PROBE_ATTACHMENT_COUNT := 3
const SOURCE_ATTACHMENT_REFRESH_DISTANCE := 0.24
const SOURCE_ATTACHMENT_REFRESH_DISTANCE_SQUARED := (
	SOURCE_ATTACHMENT_REFRESH_DISTANCE * SOURCE_ATTACHMENT_REFRESH_DISTANCE
)
const CONTINUOUS_RESULT_GAIN_SLEW_DB_PER_METER := 10.0
const CONTINUOUS_RESULT_LOSS_SLEW_DB_PER_METER := 10.0
const CONTINUOUS_RESULT_STATIONARY_SLEW_DB_PER_SECOND := 24.0
const CONTINUOUS_RESULT_PARAMETER_BLEND_DISTANCE := 0.35
const CONTINUOUS_RESULT_BAND_BLEND_DISTANCE := 0.75
const CONTINUOUS_RESULT_PARAMETER_BLEND_SECONDS := 0.12
const CONTINUOUS_RESULT_TELEPORT_DISTANCE := 2.0
const DISTRIBUTED_ENVIRONMENT_SAMPLE_COUNT := 44
const ROUTE_MIX_SCALAR_KEYS := [
	&"direct_distance",
	&"path_length",
	&"guided_path_length",
	&"range_path_length",
	&"geometric_spreading_db",
	&"unspread_volume_db",
	&"travel_delay_seconds",
	&"resonance",
	&"reverb_send",
	&"reverb_room_size",
	&"reverb_damping",
	&"reverb_spread",
	&"reverb_predelay_msec",
	&"reverb_predelay_feedback",
	&"reverb_hipass",
	&"reverb_decay_seconds",
	&"environment_enclosure",
	&"diffuse_field_gain_db",
	&"diffuse_field_support",
	&"diffuse_critical_distance",
	&"diffuse_field_level_db",
	&"diffuse_field_decay_db",
	&"guided_propagation_gain_db",
	&"route_guided_strength",
	&"source_reverb_spill_send",
]
const ROUTE_MIX_FREQUENCY_KEYS := [&"lowpass_hz", &"highpass_hz"]
static var ENVIRONMENT_SAMPLE_DIRECTIONS: Array[Vector3] = (
	_build_environment_sample_directions()
)


static func _build_environment_sample_directions() -> Array[Vector3]:
	var result: Array[Vector3] = [
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, -1.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
	]
	# A deterministic Fibonacci sphere resolves small openings without clustering samples at the
	# poles. It is constructed once with the script class, then reused by every probe rebuild.
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for sample_index: int in range(DISTRIBUTED_ENVIRONMENT_SAMPLE_COUNT):
		var y := 1.0 - 2.0 * (
			float(sample_index) + 0.5
		) / float(DISTRIBUTED_ENVIRONMENT_SAMPLE_COUNT)
		var radial := sqrt(maxf(1.0 - y * y, 0.0))
		var angle := golden_angle * float(sample_index)
		result.append(Vector3(
			cos(angle) * radial,
			y,
			sin(angle) * radial
		))
	return result

## Server-owned sparse wavefront service. Probe visibility is paid while rebuilding the graph.
## Direct obstruction uses one cached endpoint line. Listener fields and source attachments each
## retain a small collision-validated probe set, so hot-path graph sampling performs no physics.

@export_flags_3d_physics var acoustic_collision_mask := 0xFFFFFFFF
@export var enable_static_bake_cache := false
@export var enable_cumulative_static_transmission := true
@export var enable_hybrid_early_reflections := false
@export var acoustic_bake_cache_path := ""

var graph := AcousticPropagationGraph.new()
var static_boundary_bake := AcousticStaticBoundaryBake.new()
var server_world: Node3D

var _fields_by_listener: Dictionary[int, AcousticPropagationField] = {}
var _previous_fields_by_listener: Dictionary[int, AcousticPropagationField] = {}
var _field_origins_by_listener: Dictionary[int, Vector3] = {}
var _direct_paths_by_source: Dictionary[Vector2i, Dictionary] = {}
var _source_attachments_by_id: Dictionary[int, AcousticSourceAttachment] = {}
var _continuous_result_states: Dictionary[Vector2i, Dictionary] = {}
var _early_reflection_states: Dictionary[Vector2i, Dictionary] = {}
var _material_modifiers_by_instance_id: Dictionary[int, AcousticPathModifier] = {}
var _default_solid_modifier: AcousticPathModifier
var _default_environment_material: AcousticMaterial
var _visibility_ray_count := 0
var _environment_ray_count := 0
var _enclosed_probe_count := 0
var _tunnel_probe_count := 0
var _field_solve_count := 0
var _source_attachment_solve_count := 0
var _pressure_emission_build_count := 0
var _pressure_listener_event_count := 0
var _pressure_arrival_count := 0
var _rebuild_pending := false
var _bake_signature := ""
var _bake_loaded_from_cache := false
var _bake_cache_load_count := 0
var _bake_cache_write_count := 0
var _bake_cache_rejection_count := 0
var _cumulative_transmission_query_count := 0
var _cumulative_transmission_crossing_count := 0
var _early_reflection_solve_count := 0


func bind_world(world: Node3D) -> void:
	server_world = world
	request_rebuild()


func configure_bake_cache(enabled: bool, path: String = "") -> void:
	enable_static_bake_cache = enabled
	acoustic_bake_cache_path = path.strip_edges()


func configure_cumulative_static_transmission(enabled: bool) -> void:
	enable_cumulative_static_transmission = enabled


func configure_hybrid_early_reflections(enabled: bool) -> void:
	enable_hybrid_early_reflections = enabled
	if not enabled:
		_early_reflection_states.clear()


func request_rebuild() -> void:
	if _rebuild_pending:
		return
	_rebuild_pending = true
	call_deferred("_rebuild_from_world")


func calculate_listener_result(
	listener_id: int,
	listener_position: Vector3,
	source_position: Vector3,
	max_distance: float,
	source_modifier: AcousticPathModifier = null,
	reference_distance := AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
	source_modifier_is_sanitized := false,
	exclude_rids: Array[RID] = [],
	continuous_source_id := 0,
	pressure_strength := 0.0,
	prepared_pressure_emission: Dictionary = {},
	prepared_source_attachment: AcousticSourceAttachment = null,
	record_pressure_metrics := true
) -> Dictionary:
	var field: AcousticPropagationField
	var source_attachment: AcousticSourceAttachment
	if graph.probe_count() > 0:
		field = _get_listener_field(
			listener_id,
			listener_position,
			exclude_rids
		)
		source_attachment = _resolve_source_attachment(
			source_position,
			continuous_source_id,
			exclude_rids,
			prepared_source_attachment
		)
	var primary_source_probe := (
		source_attachment.primary_probe()
		if source_attachment != null
		else -1
	)
	var direct_path := _sample_direct_path(
		listener_id,
		listener_position,
		source_position,
		exclude_rids,
		continuous_source_id
	)
	var direct_path_available := bool(direct_path.get("available", false))
	var direct_path_blocked := bool(direct_path.get("blocked", false))
	var direct_path_structurally_blocked := bool(direct_path.get(
		"structural_blocked",
		false
	))
	var direct_path_is_clear := direct_path_available and not direct_path_blocked
	var direct_path_openness := clampf(
		float(direct_path.get(
			"aperture_openness",
			1.0 if direct_path_is_clear else 0.0
		)),
		0.0,
		1.0
	)
	var previous_field := _transition_field_for_listener(
		listener_id,
		listener_position,
		field
	)
	var effective_max_distance := graph.effective_hearing_distance(
		max_distance,
		listener_position,
		source_position,
		field,
		direct_path_openness,
		primary_source_probe
	)
	var direct_guided_path_length := graph.direct_guided_path_length(
		listener_position,
		source_position,
		field,
		direct_path_openness,
		primary_source_probe
	)
	var direct_range_path_length := graph.direct_range_path_length(
		listener_position,
		source_position,
		field,
		direct_path_openness,
		direct_guided_path_length,
		primary_source_probe
	)
	var direct_result: Dictionary = {}
	if direct_path_available or graph.probe_count() <= 0:
		direct_result = AcousticPropagationGraph.sample_free_field(
			listener_position,
			source_position,
			max_distance,
			source_modifier,
			reference_distance,
			source_modifier_is_sanitized,
			direct_range_path_length,
			direct_guided_path_length
		)
		if direct_path_blocked and bool(direct_result.get("audible", false)):
			AcousticPropagationGraph.apply_partial_modifier_to_result(
				direct_result,
				direct_path.get("modifier") as AcousticPathModifier,
				float(direct_path.get("occlusion", 1.0)),
				true
			)
		direct_result["direct_occlusion"] = float(
			direct_path.get("occlusion", 0.0)
		)
		direct_result["direct_path_clear"] = direct_path_is_clear
		direct_result["source_probe_index"] = primary_source_probe
	# A physically clear endpoint pair is the dominant direct wave. This prevents a sparse graph's
	# nearest-probe Voronoi boundary from behaving like an infinite warehouse wall.
	if (
		direct_path_available
		and not direct_path_blocked
		and bool(direct_result.get("audible", false))
	):
		direct_result["route_kind"] = &"direct"
		direct_result = _apply_single_route_environment(
			direct_result,
			field,
			previous_field,
			listener_position,
			source_position,
			primary_source_probe,
			primary_source_probe,
			true
		)
		return _finalize_pressure_result(
			direct_result,
			field,
			listener_position,
			source_position,
			effective_max_distance,
			pressure_strength,
			reference_distance,
			prepared_pressure_emission,
			listener_id,
			continuous_source_id,
			record_pressure_metrics
		)
	if graph.probe_count() <= 0:
		direct_result["route_kind"] = &"direct"
		direct_result = _apply_single_route_environment(
			direct_result,
			field,
			previous_field,
			listener_position,
			source_position,
			primary_source_probe,
			primary_source_probe,
			not direct_path_structurally_blocked
		)
		return _finalize_pressure_result(
			direct_result,
			field,
			listener_position,
			source_position,
			effective_max_distance,
			pressure_strength,
			reference_distance,
			prepared_pressure_emission,
			listener_id,
			continuous_source_id,
			record_pressure_metrics
		)

	var graph_result := (
		graph.sample_source_attached(
			field,
			source_position,
			source_attachment.probes,
			source_attachment.probe_count,
			max_distance,
			source_modifier,
			reference_distance,
			listener_position,
			source_modifier_is_sanitized,
			source_attachment.visibility_confirmed
		)
		if source_attachment != null
		and source_attachment.probe_count > 0
		and field != null
		and field.listener_probe_visibility_confirmed
		else {"audible": false}
	)
	var current_graph_source_probe := int(graph_result.get(
		"source_probe_index",
		primary_source_probe
	))
	_assign_listener_origin_probe(
		graph_result,
		field,
		current_graph_source_probe
	)
	var previous_graph_result: Dictionary = {}
	var previous_source_probe := primary_source_probe
	if previous_field != null:
		previous_graph_result = (
			graph.sample_source_attached(
				previous_field,
				source_position,
				source_attachment.probes,
				source_attachment.probe_count,
				max_distance,
				source_modifier,
				reference_distance,
				listener_position,
				source_modifier_is_sanitized,
				source_attachment.visibility_confirmed
			)
			if source_attachment != null
			and source_attachment.probe_count > 0
			and previous_field.listener_probe_visibility_confirmed
			else {"audible": false}
		)
		previous_source_probe = int(previous_graph_result.get(
			"source_probe_index",
			primary_source_probe
		))
		_assign_listener_origin_probe(
			previous_graph_result,
			previous_field,
			previous_source_probe
		)
	var obstruction_coverage := clampf(
		float(direct_path.get("occlusion", 1.0)),
		0.0,
		1.0
	)
	# Direct/transmitted and graph/diffracted arrivals are distinct early waves, so their route-only
	# energy remains additive. The room response is not: it is a single late field shared by every
	# route in that room. Compose the early route first, then apply environment exactly once. This is
	# the same early/late decomposition used by precomputed wave renderers and prevents an obstruction
	# transition from duplicating already-mixed room energy by almost +3 dB.
	var previous_direct_result := (
		direct_result.duplicate(false)
		if previous_field != null
		else {}
	)
	var current_route := _compose_early_route_result(
		graph_result,
		direct_result,
		direct_path_available,
		direct_path_blocked,
		obstruction_coverage
	)
	var previous_route: Dictionary = {}
	if previous_field != null:
		previous_route = _compose_early_route_result(
			previous_graph_result,
			previous_direct_result,
			direct_path_available,
			direct_path_blocked,
			obstruction_coverage
		)
	var current_route_kind := str(current_route.get("route_kind", &"silent"))
	var previous_route_kind := str(previous_route.get("route_kind", &"silent"))
	var current_environment_probe := (
		current_graph_source_probe
		if current_route_kind in ["graph", "parallel"]
		else primary_source_probe
	)
	var previous_environment_probe := (
		previous_source_probe
		if previous_route_kind in ["graph", "parallel"]
		else primary_source_probe
	)
	var current_allows_diffuse := (
		current_route_kind != "transmitted"
		or not direct_path_structurally_blocked
	)
	var previous_allows_diffuse := (
		previous_route_kind != "transmitted"
		or not direct_path_structurally_blocked
	)
	current_route = _apply_route_environment_transition(
		current_route,
		previous_route,
		field,
		previous_field,
		listener_position,
		source_position,
		current_environment_probe,
		previous_environment_probe,
		current_allows_diffuse,
		previous_allows_diffuse
	)
	return _finalize_pressure_result(
		current_route,
		field,
		listener_position,
		source_position,
		effective_max_distance,
		pressure_strength,
		reference_distance,
		prepared_pressure_emission,
		listener_id,
		continuous_source_id,
		record_pressure_metrics
	)


func build_local_prediction_context(
	listener_id: int,
	listener_position: Vector3,
	listener_rid: RID
) -> Dictionary:
	if not listener_position.is_finite():
		return {}
	# A near-body source samples the same listener field, room response, early reflections and
	# pressure attachment used by ordinary one-shots. The static graph and listener field are
	# already cached; this small 5 Hz packet lets the owner start a cue without running trusted
	# world geometry on the client or waiting for a round trip.
	var source_position := listener_position + Vector3.DOWN * 0.35
	var exclusions: Array[RID] = []
	if listener_rid.is_valid():
		exclusions.append(listener_rid)
	var result := calculate_listener_result(
		listener_id,
		listener_position,
		source_position,
		140.0,
		null,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		false,
		exclusions,
		0,
		1.0,
		{},
		null,
		false
	)
	if not bool(result.get("audible", false)):
		return {}
	result.erase("audible")
	result["version"] = AcousticEventPacket.VERSION
	result["sequence"] = 0
	result["sound_id"] = LOCAL_AUDIO_PREDICTION.CONTEXT_SOUND_ID
	result["priority"] = 0.0
	return AcousticEventPacket.sanitize(result)


func _apply_single_route_environment(
	current_result: Dictionary,
	current_field: AcousticPropagationField,
	previous_field: AcousticPropagationField,
	listener_position: Vector3,
	source_position: Vector3,
	current_source_probe: int,
	previous_source_probe: int,
	allow_diffuse_field: bool
) -> Dictionary:
	var previous_result := (
		current_result.duplicate(false)
		if previous_field != null
		else {}
	)
	return _apply_route_environment_transition(
		current_result,
		previous_result,
		current_field,
		previous_field,
		listener_position,
		source_position,
		current_source_probe,
		previous_source_probe,
		allow_diffuse_field,
		allow_diffuse_field
	)


func _apply_route_environment_transition(
	current_result: Dictionary,
	previous_result: Dictionary,
	current_field: AcousticPropagationField,
	previous_field: AcousticPropagationField,
	listener_position: Vector3,
	source_position: Vector3,
	current_source_probe: int,
	previous_source_probe: int,
	current_allows_diffuse: bool,
	previous_allows_diffuse: bool
) -> Dictionary:
	graph.apply_environment_to_result(
		current_result,
		listener_position,
		source_position,
		current_field,
		current_source_probe,
		current_allows_diffuse
	)
	if previous_field == null:
		return current_result
	graph.apply_environment_to_result(
		previous_result,
		listener_position,
		source_position,
		previous_field,
		previous_source_probe,
		previous_allows_diffuse
	)
	return _crossfade_field_results(
		previous_result,
		current_result,
		_field_transition_weight(listener_position, current_field)
	)


static func _compose_early_route_result(
	graph_route: Dictionary,
	direct_route: Dictionary,
	direct_path_available: bool,
	direct_path_blocked: bool,
	obstruction_coverage: float
) -> Dictionary:
	if not direct_path_available or not direct_path_blocked:
		graph_route["route_kind"] = &"graph"
		return graph_route
	if not bool(graph_route.get("audible", false)):
		direct_route["route_kind"] = &"transmitted"
		return direct_route
	# A finite obstruction exposes two edge-wrapping opportunities. Their union grows smoothly with
	# coverage. This participation affects only the route-specific early wave; the shared room field
	# is attached once after this function returns.
	var safe_coverage := clampf(obstruction_coverage, 0.0, 1.0)
	var diffracted_edge_exposure := safe_coverage * (2.0 - safe_coverage)
	var graph_participation := (
		diffracted_edge_exposure
		if bool(direct_route.get("audible", false))
		else 1.0
	)
	return _mix_parallel_route_results(
		graph_route,
		direct_route,
		graph_participation,
		1.0,
		&"parallel"
	)


static func _assign_listener_origin_probe(
	result: Dictionary,
	field: AcousticPropagationField,
	source_probe: int
) -> void:
	result["listener_origin_probe_index"] = (
		field.origin_probes[source_probe]
		if field != null
		and source_probe >= 0
		and source_probe < field.origin_probes.size()
		else -1
	)


func _finalize_pressure_result(
	result: Dictionary,
	field: AcousticPropagationField,
	listener_position: Vector3,
	source_position: Vector3,
	max_distance: float,
	pressure_strength: float,
	reference_distance: float,
	prepared_pressure_emission: Dictionary,
	listener_id: int,
	continuous_source_id: int,
	record_pressure_metrics: bool
) -> Dictionary:
	_attach_hybrid_early_reflections(
		result,
		listener_id,
		continuous_source_id,
		listener_position,
		source_position
	)
	result = _smooth_continuous_result(
		result,
		listener_id,
		continuous_source_id,
		listener_position,
		source_position
	)
	if pressure_strength <= 0.0001 or not bool(result.get("audible", false)):
		return result
	var emission := prepared_pressure_emission
	if emission.is_empty():
		emission = graph.create_pressure_emission(
			source_position,
			pressure_strength,
			int(result.get("source_probe_index", -1))
		)
		if not emission.is_empty() and record_pressure_metrics:
			_pressure_emission_build_count += 1
	graph.attach_pressure_arrivals(
		result,
		field,
		listener_position,
		source_position,
		max_distance,
		pressure_strength,
		reference_distance,
		emission
	)
	var arrivals: Array = result.get("pressure_arrivals", [])
	if not arrivals.is_empty() and record_pressure_metrics:
		_pressure_listener_event_count += 1
		_pressure_arrival_count += arrivals.size()
	return result


func _attach_hybrid_early_reflections(
	result: Dictionary,
	listener_id: int,
	continuous_source_id: int,
	listener_position: Vector3,
	source_position: Vector3
) -> void:
	result.erase("early_reflections")
	if (
		not enable_hybrid_early_reflections
		or not bool(result.get("audible", false))
		or not bool(result.get("direct_path_clear", false))
	):
		return
	if continuous_source_id == 0:
		var one_shot_taps := static_boundary_bake.sample_early_reflections(
			listener_position,
			source_position,
			maxf(listener_position.distance_to(source_position), 0.001)
		)
		_early_reflection_solve_count += 1
		if not one_shot_taps.is_empty():
			result["early_reflections"] = one_shot_taps
		return
	var state_key := Vector2i(listener_id, continuous_source_id)
	var state: Dictionary = _early_reflection_states.get(state_key, {})
	var cached_listener: Vector3 = state.get(
		"listener_position",
		Vector3(INF, INF, INF)
	)
	var cached_source: Vector3 = state.get(
		"source_position",
		Vector3(INF, INF, INF)
	)
	if (
		state.is_empty()
		or cached_listener.distance_squared_to(listener_position)
		> EARLY_REFLECTION_REFRESH_DISTANCE_SQUARED
		or cached_source.distance_squared_to(source_position)
		> EARLY_REFLECTION_REFRESH_DISTANCE_SQUARED
	):
		var taps := static_boundary_bake.sample_early_reflections(
			listener_position,
			source_position,
			maxf(listener_position.distance_to(source_position), 0.001)
		)
		state = {
			"listener_position": listener_position,
			"source_position": source_position,
			"taps": taps,
		}
		_early_reflection_states[state_key] = state
		_early_reflection_solve_count += 1
	var cached_taps: Array = state.get("taps", [])
	if not cached_taps.is_empty():
		result["early_reflections"] = cached_taps


func _smooth_continuous_result(
	result: Dictionary,
	listener_id: int,
	continuous_source_id: int,
	listener_position: Vector3,
	source_position: Vector3
) -> Dictionary:
	if continuous_source_id == 0:
		return result
	var state_key := Vector2i(listener_id, continuous_source_id)
	if not bool(result.get("audible", false)):
		_continuous_result_states.erase(state_key)
		return result
	var now_msec := Time.get_ticks_msec()
	var state: Dictionary = _continuous_result_states.get(state_key, {})
	if state.is_empty():
		_capture_continuous_result_state(
			state,
			result,
			listener_position,
			source_position,
			now_msec
		)
		_continuous_result_states[state_key] = state
		return result
	var previous_listener: Vector3 = state.get("listener_position", listener_position)
	var previous_source: Vector3 = state.get("source_position", source_position)
	var spatial_distance := maxf(
		previous_listener.distance_to(listener_position),
		previous_source.distance_to(source_position)
	)
	if spatial_distance >= CONTINUOUS_RESULT_TELEPORT_DISTANCE:
		_capture_continuous_result_state(
			state,
			result,
			listener_position,
			source_position,
			now_msec
		)
		return result
	var elapsed_seconds := clampf(
		float(now_msec - int(state.get("updated_at_msec", now_msec))) / 1000.0,
		0.0,
		0.25
	)
	var previous_volume_db := float(state.get(
		"volume_db",
		result.get("volume_db", AcousticPathModifier.MIN_VOLUME_DB)
	))
	var target_volume_db := SafeVariant.finite_float_or(
		result.get("volume_db"),
		previous_volume_db
	)
	var spatial_volume_step := spatial_distance * (
		CONTINUOUS_RESULT_GAIN_SLEW_DB_PER_METER
		if target_volume_db > previous_volume_db
		else CONTINUOUS_RESULT_LOSS_SLEW_DB_PER_METER
	)
	var stationary_volume_step := (
		elapsed_seconds * CONTINUOUS_RESULT_STATIONARY_SLEW_DB_PER_SECOND
		if spatial_distance <= 0.0001
		else 0.0
	)
	var smoothed_volume_db := move_toward(
		previous_volume_db,
		target_volume_db,
		maxf(spatial_volume_step, stationary_volume_step)
	)
	state["volume_db"] = smoothed_volume_db
	result["volume_db"] = smoothed_volume_db
	var blend_progress := 1.0 - exp(-(
		spatial_distance / CONTINUOUS_RESULT_PARAMETER_BLEND_DISTANCE
		+ (
			elapsed_seconds / CONTINUOUS_RESULT_PARAMETER_BLEND_SECONDS
			if spatial_distance <= 0.0001
			else 0.0
		)
	))
	for key: StringName in ROUTE_MIX_SCALAR_KEYS:
		if not result.has(key):
			continue
		var previous_value := SafeVariant.finite_float_or(
			state.get(key),
			SafeVariant.finite_float_or(result.get(key), 0.0)
		)
		var smoothed_value := lerpf(
			previous_value,
			SafeVariant.finite_float_or(result.get(key), previous_value),
			blend_progress
		)
		state[key] = smoothed_value
		result[key] = smoothed_value
	for key: StringName in ROUTE_MIX_FREQUENCY_KEYS:
		if not result.has(key):
			continue
		var previous_hz := maxf(
			SafeVariant.finite_float_or(state.get(key), float(result[key])),
			AcousticPathModifier.MIN_FILTER_HZ
		)
		var target_hz := maxf(
			SafeVariant.finite_float_or(result.get(key), previous_hz),
			AcousticPathModifier.MIN_FILTER_HZ
		)
		var smoothed_hz := exp(lerpf(
			log(previous_hz),
			log(target_hz),
			blend_progress
		))
		state[key] = smoothed_hz
		result[key] = smoothed_hz
	var previous_bands: Vector3 = state.get(
		"band_gain",
		result.get("band_gain", Vector3.ONE)
	)
	var target_bands: Vector3 = result.get("band_gain", previous_bands)
	# Material color needs a longer spatial dezipper than scalar room parameters. A newly exposed
	# wall can replace all three target bands at once; applying the short 35 cm room blend made the
	# timbre jump even while the authoritative level remained perfectly continuous.
	var band_blend_progress := 1.0 - exp(-(
		spatial_distance / CONTINUOUS_RESULT_BAND_BLEND_DISTANCE
		+ (
			elapsed_seconds / CONTINUOUS_RESULT_PARAMETER_BLEND_SECONDS
			if spatial_distance <= 0.0001
			else 0.0
		)
	))
	var smoothed_bands := previous_bands.lerp(
		target_bands,
		band_blend_progress
	)
	state["band_gain"] = smoothed_bands
	result["band_gain"] = smoothed_bands
	var previous_position: Vector3 = state.get(
		"apparent_position",
		result.get("apparent_position", source_position)
	)
	var target_position: Vector3 = result.get("apparent_position", previous_position)
	var smoothed_position := previous_position.lerp(
		target_position,
		blend_progress
	)
	state["apparent_position"] = smoothed_position
	result["apparent_position"] = smoothed_position
	state["listener_position"] = listener_position
	state["source_position"] = source_position
	state["updated_at_msec"] = now_msec
	return result


func _capture_continuous_result_state(
	state: Dictionary,
	result: Dictionary,
	listener_position: Vector3,
	source_position: Vector3,
	now_msec: int
) -> void:
	state["volume_db"] = SafeVariant.finite_float_or(
		result.get("volume_db"),
		AcousticPathModifier.MIN_VOLUME_DB
	)
	for key: StringName in ROUTE_MIX_SCALAR_KEYS:
		if result.has(key):
			state[key] = SafeVariant.finite_float_or(result.get(key), 0.0)
	for key: StringName in ROUTE_MIX_FREQUENCY_KEYS:
		if result.has(key):
			state[key] = SafeVariant.finite_float_or(
				result.get(key),
				AcousticPathModifier.MIN_FILTER_HZ
			)
	state["band_gain"] = result.get("band_gain", Vector3.ONE)
	state["apparent_position"] = result.get("apparent_position", source_position)
	state["listener_position"] = listener_position
	state["source_position"] = source_position
	state["updated_at_msec"] = now_msec


func _transition_field_for_listener(
	listener_id: int,
	listener_position: Vector3,
	current_field: AcousticPropagationField
) -> AcousticPropagationField:
	var previous_field := _previous_fields_by_listener.get(
		listener_id
	) as AcousticPropagationField
	if (
		previous_field == null
		or current_field == null
		or previous_field.graph_revision != graph.revision
		or current_field.graph_revision != graph.revision
		or previous_field.source_probe < 0
		or not previous_field.source_position.is_finite()
		or previous_field.source_position.distance_to(current_field.source_position)
		> FIELD_REFRESH_DISTANCE * 2.5
		or _field_transition_weight(listener_position, current_field) >= 0.9999
	):
		return null
	return previous_field


func _field_transition_weight(
	listener_position: Vector3,
	current_field: AcousticPropagationField
) -> float:
	if current_field == null or not current_field.source_position.is_finite():
		return 1.0
	return clampf(
		listener_position.distance_to(current_field.source_position)
		/ FIELD_REFRESH_DISTANCE,
		0.0,
		1.0
	)


static func _crossfade_field_results(
	previous_result: Dictionary,
	current_result: Dictionary,
	current_weight: float
) -> Dictionary:
	var safe_current_weight := clampf(current_weight, 0.0, 1.0)
	if safe_current_weight <= 0.0001:
		return previous_result
	if safe_current_weight >= 0.9999:
		return current_result
	var previous_audible := bool(previous_result.get("audible", false))
	var current_audible := bool(current_result.get("audible", false))
	if not previous_audible and not current_audible:
		return current_result
	var previous_weight := 1.0 - safe_current_weight
	var result := (
		current_result if safe_current_weight >= 0.5 else previous_result
	)
	var previous_volume_db := (
		SafeVariant.finite_float_or(
			previous_result.get("volume_db"),
			AcousticPathModifier.MIN_VOLUME_DB
		)
		if previous_audible
		else AcousticPathModifier.MIN_VOLUME_DB
	)
	var current_volume_db := (
		SafeVariant.finite_float_or(
			current_result.get("volume_db"),
			AcousticPathModifier.MIN_VOLUME_DB
		)
		if current_audible
		else AcousticPathModifier.MIN_VOLUME_DB
	)
	# These are successive estimates of one wavefront, not two simultaneous emitters. Interpolate
	# level in decibels so a route handoff cannot acquire the +3 dB gain appropriate to genuinely
	# independent paths. The ordinary parallel-route mixer remains energy additive.
	result["audible"] = true
	result["volume_db"] = lerpf(
		previous_volume_db,
		current_volume_db,
		safe_current_weight
	)
	for key: StringName in ROUTE_MIX_SCALAR_KEYS:
		if previous_result.has(key) or current_result.has(key):
			var previous_value := SafeVariant.finite_float_or(
				previous_result.get(key),
				SafeVariant.finite_float_or(current_result.get(key), 0.0)
			)
			result[key] = lerpf(
				previous_value,
				SafeVariant.finite_float_or(current_result.get(key), previous_value),
				safe_current_weight
			)
	for key: StringName in ROUTE_MIX_FREQUENCY_KEYS:
		var previous_hz := maxf(
			SafeVariant.finite_float_or(
				previous_result.get(key),
				SafeVariant.finite_float_or(
					current_result.get(key),
					AcousticPathModifier.MIN_FILTER_HZ
				)
			),
			AcousticPathModifier.MIN_FILTER_HZ
		)
		var current_hz := maxf(
			SafeVariant.finite_float_or(current_result.get(key), previous_hz),
			AcousticPathModifier.MIN_FILTER_HZ
		)
		result[key] = exp(lerpf(
			log(previous_hz),
			log(current_hz),
			safe_current_weight
		))
	var previous_bands: Vector3 = previous_result.get("band_gain", Vector3.ONE)
	var current_bands: Vector3 = current_result.get("band_gain", previous_bands)
	result["band_gain"] = Vector3(
		sqrt(maxf(
			previous_bands.x * previous_bands.x * previous_weight
			+ current_bands.x * current_bands.x * safe_current_weight,
			0.0
		)),
		sqrt(maxf(
			previous_bands.y * previous_bands.y * previous_weight
			+ current_bands.y * current_bands.y * safe_current_weight,
			0.0
		)),
		sqrt(maxf(
			previous_bands.z * previous_bands.z * previous_weight
			+ current_bands.z * current_bands.z * safe_current_weight,
			0.0
		))
	)
	var previous_position: Vector3 = previous_result.get(
		"apparent_position",
		current_result.get("apparent_position", Vector3.ZERO)
	)
	var current_position: Vector3 = current_result.get(
		"apparent_position",
		previous_position
	)
	result["apparent_position"] = previous_position.lerp(
		current_position,
		safe_current_weight
	)
	var current_is_dominant := (
		current_audible
		and (not previous_audible or safe_current_weight >= 0.5)
	)
	var dominant := current_result if current_is_dominant else previous_result
	result["source_position"] = dominant.get(
		"source_position",
		current_result.get(
			"source_position",
			previous_result.get("source_position", Vector3.ZERO)
		)
	)
	result["source_probe_index"] = int(dominant.get(
		"source_probe_index",
		result.get("source_probe_index", -1)
	))
	result["listener_origin_probe_index"] = int(dominant.get(
		"listener_origin_probe_index",
		-1
	))
	result["modifier_ids"] = dominant.get(
		"modifier_ids",
		PackedStringArray()
	)
	result["field_transition_active"] = true
	result["field_transition_weight"] = safe_current_weight
	return result


func create_pressure_emission(
	source_position: Vector3,
	pressure_strength: float,
	exclude_rids: Array[RID] = [],
	prepared_source_attachment: AcousticSourceAttachment = null
) -> Dictionary:
	var source_attachment := _resolve_source_attachment(
		source_position,
		0,
		exclude_rids,
		prepared_source_attachment
	)
	var result := graph.create_pressure_emission(
		source_position,
		pressure_strength,
		source_attachment.primary_probe()
		if source_attachment != null
		else -1
	)
	if not result.is_empty():
		_pressure_emission_build_count += 1
	return result


func _get_listener_field(
	listener_id: int,
	listener_position: Vector3,
	exclude_rids: Array[RID]
) -> AcousticPropagationField:
	var field := _fields_by_listener.get(listener_id) as AcousticPropagationField
	var previous_origin: Vector3 = _field_origins_by_listener.get(
		listener_id,
		Vector3(INF, INF, INF)
	)
	if (
		field != null
		and field.graph_revision == graph.revision
		and previous_origin.distance_squared_to(listener_position)
		< FIELD_REFRESH_DISTANCE_SQUARED
	):
		return field
	if field == null:
		field = AcousticPropagationField.new()
		_fields_by_listener[listener_id] = field
	var previous_field := field
	var next_field := _previous_fields_by_listener.get(
		listener_id
	) as AcousticPropagationField
	if next_field == null:
		next_field = AcousticPropagationField.new()
	_previous_fields_by_listener[listener_id] = previous_field
	_fields_by_listener[listener_id] = next_field
	field = next_field
	var can_blend_previous_field := (
		previous_field.graph_revision == graph.revision
		and previous_origin.is_finite()
		and previous_field.listener_probe_count > 0
	)
	field.prepare_listener_probe_buffers(
		LISTENER_PROBE_CANDIDATE_COUNT,
		LISTENER_GUIDED_REGION_CANDIDATE_COUNT,
		LISTENER_PROBE_BLEND_COUNT,
		previous_field if can_blend_previous_field else null
	)
	field.listener_probe_transition_step = (
		clampf(
			previous_origin.distance_to(listener_position)
			/ LISTENER_PROBE_STRENGTH_BLEND_DISTANCE,
			0.0,
			1.0
		)
		if can_blend_previous_field
		else 1.0
	)
	var candidate_count := graph.find_nearest_probes(
		listener_position,
		LISTENER_PROBE_CANDIDATE_COUNT,
		field.candidate_probes
	)
	for candidate_index: int in range(candidate_count):
		_try_add_listener_probe(
			listener_position,
			field.candidate_probes[candidate_index],
			exclude_rids,
			field,
			false
		)
		if field.listener_probe_count >= LISTENER_PROBE_BLEND_COUNT:
			break
	if field.listener_probe_count < LISTENER_PROBE_BLEND_COUNT:
		var guided_candidate_count := graph.find_nearest_guided_region_probes(
			listener_position,
			LISTENER_GUIDED_REGION_CANDIDATE_COUNT,
			field.guided_candidate_probes,
			LISTENER_GUIDED_PROBES_PER_REGION
		)
		for candidate_index: int in range(guided_candidate_count):
			_consider_guided_listener_probe(
				listener_position,
				field.guided_candidate_probes[candidate_index],
				exclude_rids,
				field
			)
		for best_index: int in range(field.guided_best_count):
			if field.listener_probe_count >= LISTENER_PROBE_BLEND_COUNT:
				break
			_add_listener_probe_with_strength(
				field.guided_best_probes[best_index],
				field.guided_best_strengths[best_index],
				field
			)
	# A level with no reachable probe is under-authored. The nearest probe remains only as a
	# diagnostic/fallback graph anchor; calculate_listener_result never renders an unvalidated
	# route, because that probe may be on the opposite side of a wall.
	if field.listener_probe_count <= 0 and candidate_count > 0:
		field.listener_probes[0] = field.candidate_probes[0]
		field.listener_probe_strengths[0] = 1.0
		field.listener_probe_count = 1
	graph.solve_from_position(
		listener_position,
		field,
		field.listener_probes,
		field.listener_probe_count,
		field.listener_probe_strengths
	)
	_field_solve_count += 1
	_field_origins_by_listener[listener_id] = listener_position
	return field


func _try_add_listener_probe(
	listener_position: Vector3,
	probe_index: int,
	exclude_rids: Array[RID],
	field: AcousticPropagationField,
	allow_partial_guided := true
) -> bool:
	if probe_index < 0:
		return false
	for listener_probe_index: int in range(field.listener_probe_count):
		if field.listener_probes[listener_probe_index] == probe_index:
			return false
	if (
		field.listener_probe_count >= LISTENER_PROBE_BASE_BLEND_COUNT
		and not _adds_listener_guided_region(field, probe_index)
	):
		return false
	var attachment_strength := _listener_probe_attachment_strength(
		listener_position,
		graph.get_probe_position(probe_index),
		probe_index,
		exclude_rids,
		field
	)
	if attachment_strength <= 0.0001:
		return false
	if (
		not allow_partial_guided
		and graph.guided_region_id(probe_index) >= 0
		and attachment_strength < 0.999
	):
		return false
	return _add_listener_probe_with_strength(
		probe_index,
		attachment_strength,
		field
	)


func _add_listener_probe_with_strength(
	probe_index: int,
	attachment_strength: float,
	field: AcousticPropagationField
) -> bool:
	if field.listener_probe_count >= field.listener_probes.size():
		return false
	field.listener_probes[field.listener_probe_count] = probe_index
	field.listener_probe_strengths[field.listener_probe_count] = attachment_strength
	field.listener_probe_count += 1
	field.listener_probe_visibility_confirmed = true
	return true


func _consider_guided_listener_probe(
	listener_position: Vector3,
	probe_index: int,
	exclude_rids: Array[RID],
	field: AcousticPropagationField
) -> void:
	var region_id := graph.guided_region_id(probe_index)
	if region_id < 0:
		return
	for listener_probe_index: int in range(field.listener_probe_count):
		if graph.guided_region_id(field.listener_probes[listener_probe_index]) == region_id:
			return
	var strength := _listener_probe_attachment_strength(
		listener_position,
		graph.get_probe_position(probe_index),
		probe_index,
		exclude_rids,
		field
	)
	if strength <= 0.0001:
		return
	var distance_squared := listener_position.distance_squared_to(
		graph.get_probe_position(probe_index)
	)
	var best_index := -1
	for candidate_index: int in range(field.guided_best_count):
		if field.guided_best_region_ids[candidate_index] == region_id:
			best_index = candidate_index
			break
	if best_index < 0:
		if field.guided_best_count >= field.guided_best_region_ids.size():
			return
		best_index = field.guided_best_count
		field.guided_best_count += 1
		field.guided_best_region_ids[best_index] = region_id
	elif (
		strength < field.guided_best_strengths[best_index] - 0.0001
		or (
			is_equal_approx(strength, field.guided_best_strengths[best_index])
			and distance_squared >= field.guided_best_distances_squared[best_index]
		)
	):
		return
	field.guided_best_probes[best_index] = probe_index
	field.guided_best_strengths[best_index] = strength
	field.guided_best_distances_squared[best_index] = distance_squared


func _adds_listener_guided_region(
	field: AcousticPropagationField,
	probe_index: int
) -> bool:
	var candidate_region := graph.guided_region_id(probe_index)
	if candidate_region < 0:
		return false
	for listener_probe_index: int in range(field.listener_probe_count):
		if graph.guided_region_id(
			field.listener_probes[listener_probe_index]
		) == candidate_region:
			return false
	return true


func _listener_probe_attachment_strength(
	listener_position: Vector3,
	probe_position: Vector3,
	probe_index: int,
	exclude_rids: Array[RID],
	field: AcousticPropagationField
) -> float:
	var target_strength := _listener_probe_target_strength(
		listener_position,
		probe_position,
		probe_index,
		exclude_rids,
		field
	)
	if field.previous_listener_probe_count <= 0:
		return target_strength
	var previous_strength := 0.0
	for previous_index: int in range(field.previous_listener_probe_count):
		if field.previous_listener_probes[previous_index] == probe_index:
			previous_strength = field.previous_listener_probe_strengths[previous_index]
			break
	return move_toward(
		previous_strength,
		target_strength,
		field.listener_probe_transition_step
	)


func _listener_probe_target_strength(
	listener_position: Vector3,
	probe_position: Vector3,
	probe_index: int,
	exclude_rids: Array[RID],
	field: AcousticPropagationField
) -> float:
	var influence_strength := graph.probe_attachment_strength(
		probe_index,
		listener_position
	)
	if influence_strength <= 0.0001:
		return 0.0
	var attachment_distance := listener_position.distance_to(probe_position)
	if (
		graph.guided_region_id(probe_index) >= 0
		and attachment_distance > LISTENER_GUIDED_PROBE_MAX_ATTACHMENT_DISTANCE
	):
		return 0.0
	var needs_soft_edge_visibility := (
		attachment_distance > LISTENER_PROBE_SOFT_VISIBILITY_MIN_DISTANCE
		and graph.guided_region_id(probe_index) >= 0
	)
	if not needs_soft_edge_visibility:
		return influence_strength * (
			1.0
			if _endpoint_can_reach_probe(
				listener_position,
				probe_position,
				exclude_rids,
				field.visibility_exclusions
			)
			else 0.0
		)

	# A distant tunnel/room anchor can disappear behind a corner while the listener moves only a
	# centimetre. Treating the centre ray as a boolean made the whole wavefront jump to a much
	# longer graph route. A small deterministic aperture is paid only for these distant guided
	# attachments (never per sound). Its visible area becomes pressure amplitude, so the old path
	# fades into the edge-wrapped path instead of popping; a fully hidden anchor still contributes
	# nothing and cannot leak through a wall.
	var direction := (probe_position - listener_position).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() <= 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var vertical := side.cross(direction).normalized()
	var visible_samples := 0
	var ring_sample_count := LISTENER_PROBE_SOFT_VISIBILITY_SAMPLE_COUNT - 1
	var golden_angle := PI * (3.0 - sqrt(5.0))
	for sample_index: int in range(LISTENER_PROBE_SOFT_VISIBILITY_SAMPLE_COUNT):
		var offset := Vector3.ZERO
		if sample_index > 0:
			var ring_index := sample_index - 1
			var radius := (
				sqrt((float(ring_index) + 0.5) / float(ring_sample_count))
				* LISTENER_PROBE_SOFT_VISIBILITY_RADIUS
			)
			var angle := float(ring_index) * golden_angle
			offset = side * (cos(angle) * radius) + vertical * (sin(angle) * radius)
		if _endpoint_can_reach_probe(
			listener_position + offset,
			probe_position + offset,
			exclude_rids,
			field.visibility_exclusions
		):
			visible_samples += 1
	if visible_samples <= 0:
		return 0.0
	return influence_strength * sqrt(
		float(visible_samples)
		/ float(LISTENER_PROBE_SOFT_VISIBILITY_SAMPLE_COUNT)
	)


func create_source_attachment(
	source_position: Vector3,
	exclude_rids: Array[RID] = []
) -> AcousticSourceAttachment:
	var attachment := AcousticSourceAttachment.new()
	_populate_source_attachment(
		attachment,
		source_position,
		exclude_rids
	)
	return attachment


func source_hearing_distance_upper_bound(
	base_distance: float,
	source_position: Vector3,
	continuous_source_id := 0,
	exclude_rids: Array[RID] = [],
	prepared_attachment: AcousticSourceAttachment = null
) -> float:
	var attachment := _resolve_source_attachment(
		source_position,
		continuous_source_id,
		exclude_rids,
		prepared_attachment
	)
	return graph.source_hearing_distance_upper_bound(
		base_distance,
		source_position,
		attachment.primary_probe() if attachment != null else -1
	)


func _resolve_source_attachment(
	source_position: Vector3,
	continuous_source_id: int,
	exclude_rids: Array[RID],
	prepared_attachment: AcousticSourceAttachment = null
) -> AcousticSourceAttachment:
	if (
		prepared_attachment != null
		and prepared_attachment.is_current(
			graph.revision,
			source_position,
			SOURCE_ATTACHMENT_REFRESH_DISTANCE_SQUARED
		)
	):
		return prepared_attachment
	if continuous_source_id != 0:
		var cached := _source_attachments_by_id.get(
			continuous_source_id
		) as AcousticSourceAttachment
		if (
			cached != null
			and cached.is_current(
				graph.revision,
				source_position,
				SOURCE_ATTACHMENT_REFRESH_DISTANCE_SQUARED
			)
		):
			return cached
		var refreshed := create_source_attachment(
			source_position,
			exclude_rids
		)
		_source_attachments_by_id[continuous_source_id] = refreshed
		return refreshed
	return create_source_attachment(source_position, exclude_rids)


func _populate_source_attachment(
	attachment: AcousticSourceAttachment,
	source_position: Vector3,
	exclude_rids: Array[RID]
) -> void:
	attachment.prepare(
		SOURCE_PROBE_CANDIDATE_COUNT,
		SOURCE_PROBE_ATTACHMENT_COUNT
	)
	attachment.graph_revision = graph.revision
	attachment.source_position = source_position
	if not source_position.is_finite() or graph.probe_count() <= 0:
		return
	var candidate_count := graph.find_nearest_probes(
		source_position,
		SOURCE_PROBE_CANDIDATE_COUNT,
		attachment.candidate_probes
	)
	if candidate_count <= 0:
		return
	attachment.nearest_unfiltered_probe = attachment.candidate_probes[0]
	var can_validate_visibility := (
		is_instance_valid(server_world)
		and server_world.is_inside_tree()
		and server_world.get_world_3d() != null
	)
	for candidate_index: int in range(candidate_count):
		var probe_index := attachment.candidate_probes[candidate_index]
		if probe_index < 0:
			continue
		if not graph.probe_allows_attachment(probe_index, source_position):
			continue
		if (
			can_validate_visibility
			and not _endpoint_can_reach_probe(
				source_position,
				graph.get_probe_position(probe_index),
				exclude_rids,
				attachment.visibility_exclusions
			)
		):
			continue
		attachment.probes[attachment.probe_count] = probe_index
		attachment.probe_count += 1
		if attachment.probe_count >= SOURCE_PROBE_ATTACHMENT_COUNT:
			break
	attachment.visibility_confirmed = (
		attachment.probe_count > 0 and can_validate_visibility
	)
	_source_attachment_solve_count += 1


func _endpoint_can_reach_probe(
	endpoint_position: Vector3,
	probe_position: Vector3,
	exclude_rids: Array[RID],
	visibility_exclusions: Array[RID]
) -> bool:
	if endpoint_position.distance_squared_to(probe_position) <= 0.000001:
		return true
	if (
		not is_instance_valid(server_world)
		or not server_world.is_inside_tree()
		or server_world.get_world_3d() == null
	):
		return true
	visibility_exclusions.assign(exclude_rids)
	var space_state := server_world.get_world_3d().direct_space_state
	for _attempt: int in range(MAX_IGNORED_DIRECT_PATH_BODIES + 1):
		var query := PhysicsRayQueryParameters3D.create(
			endpoint_position,
			probe_position,
			acoustic_collision_mask
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		query.exclude = visibility_exclusions
		var hit := space_state.intersect_ray(query)
		_visibility_ray_count += 1
		if hit.is_empty():
			return true
		var collider := hit.get("collider") as CollisionObject3D
		if _defines_acoustic_boundary(collider):
			return false
		var collider_rid: RID = hit.get("rid", RID())
		if not collider_rid.is_valid():
			return false
		visibility_exclusions.append(collider_rid)
	return false


func forget_listener(listener_id: int) -> void:
	_fields_by_listener.erase(listener_id)
	_previous_fields_by_listener.erase(listener_id)
	_field_origins_by_listener.erase(listener_id)
	for path_key: Vector2i in _direct_paths_by_source.keys():
		if path_key.x == listener_id:
			_direct_paths_by_source.erase(path_key)
	for state_key: Vector2i in _continuous_result_states.keys():
		if state_key.x == listener_id:
			_continuous_result_states.erase(state_key)
	for state_key: Vector2i in _early_reflection_states.keys():
		if state_key.x == listener_id:
			_early_reflection_states.erase(state_key)


func forget_continuous_source(source_id: int) -> void:
	if source_id == 0:
		return
	for path_key: Vector2i in _direct_paths_by_source.keys():
		if path_key.y == source_id:
			_direct_paths_by_source.erase(path_key)
	_source_attachments_by_id.erase(source_id)
	for state_key: Vector2i in _continuous_result_states.keys():
		if state_key.y == source_id:
			_continuous_result_states.erase(state_key)
	for state_key: Vector2i in _early_reflection_states.keys():
		if state_key.y == source_id:
			_early_reflection_states.erase(state_key)


func get_debug_state() -> Dictionary:
	var result := {
		"probe_count": graph.probe_count(),
		"directed_edge_count": graph.edge_count(),
		"graph_revision": graph.revision,
		"cached_listener_fields": _fields_by_listener.size(),
		"cached_previous_listener_fields": _previous_fields_by_listener.size(),
		"cached_direct_paths": _direct_paths_by_source.size(),
		"cached_source_attachments": _source_attachments_by_id.size(),
		"cached_continuous_result_states": _continuous_result_states.size(),
		"cached_early_reflection_states": _early_reflection_states.size(),
		"hybrid_early_reflections_enabled": enable_hybrid_early_reflections,
		"early_reflection_solve_count": _early_reflection_solve_count,
		"early_reflection_refresh_distance": EARLY_REFLECTION_REFRESH_DISTANCE,
		"visibility_ray_count": _visibility_ray_count,
		"environment_ray_count": _environment_ray_count,
		"enclosed_probe_count": _enclosed_probe_count,
		"tunnel_probe_count": _tunnel_probe_count,
		"environment_samples_per_probe": ENVIRONMENT_SAMPLE_DIRECTIONS.size(),
		"field_solve_count": _field_solve_count,
		"source_attachment_solve_count": _source_attachment_solve_count,
		"field_refresh_distance": FIELD_REFRESH_DISTANCE,
		"listener_probe_candidate_count": LISTENER_PROBE_CANDIDATE_COUNT,
		"listener_probe_blend_count": LISTENER_PROBE_BLEND_COUNT,
		"source_probe_candidate_count": SOURCE_PROBE_CANDIDATE_COUNT,
		"source_probe_attachment_count": SOURCE_PROBE_ATTACHMENT_COUNT,
		"source_attachment_refresh_distance": SOURCE_ATTACHMENT_REFRESH_DISTANCE,
		"pressure_emission_build_count": _pressure_emission_build_count,
		"pressure_listener_event_count": _pressure_listener_event_count,
		"pressure_arrival_count": _pressure_arrival_count,
		"maximum_pressure_arrivals": (
			AcousticPropagationGraph.MAX_PRESSURE_ARRIVALS
		),
		"direct_path_cache_seconds": DIRECT_PATH_CACHE_SECONDS,
		"listener_refresh_distance": DIRECT_PATH_LISTENER_REFRESH_DISTANCE,
		"source_refresh_distance": DIRECT_PATH_SOURCE_REFRESH_DISTANCE,
		"bake_cache_enabled": enable_static_bake_cache,
		"bake_loaded_from_cache": _bake_loaded_from_cache,
		"bake_signature": _bake_signature,
		"bake_cache_load_count": _bake_cache_load_count,
		"bake_cache_write_count": _bake_cache_write_count,
		"bake_cache_rejection_count": _bake_cache_rejection_count,
		"cumulative_static_transmission_enabled": (
			enable_cumulative_static_transmission
		),
		"cumulative_transmission_query_count": (
			_cumulative_transmission_query_count
		),
		"cumulative_transmission_crossing_count": (
			_cumulative_transmission_crossing_count
		),
	}
	result.merge(static_boundary_bake.debug_state(), true)
	return result


func _rebuild_from_world() -> void:
	_rebuild_pending = false
	graph.clear()
	static_boundary_bake.clear()
	_fields_by_listener.clear()
	_previous_fields_by_listener.clear()
	_field_origins_by_listener.clear()
	_direct_paths_by_source.clear()
	_source_attachments_by_id.clear()
	_continuous_result_states.clear()
	_early_reflection_states.clear()
	_material_modifiers_by_instance_id.clear()
	_environment_ray_count = 0
	_enclosed_probe_count = 0
	_tunnel_probe_count = 0
	_source_attachment_solve_count = 0
	_early_reflection_solve_count = 0
	_bake_signature = ""
	_bake_loaded_from_cache = false
	if not is_instance_valid(server_world) or not server_world.is_inside_tree():
		return

	var probes: Array[AcousticProbe3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"acoustic_probes"):
		if node is AcousticProbe3D and server_world.is_ancestor_of(node):
			probes.append(node as AcousticProbe3D)
	probes.sort_custom(
		func(left: AcousticProbe3D, right: AcousticProbe3D) -> bool:
			return str(left.stable_id()) < str(right.stable_id())
	)
	if enable_static_bake_cache and not acoustic_bake_cache_path.is_empty():
		_bake_signature = _world_bake_signature(probes)
		if _try_load_cached_bake():
			return

	var probe_index_by_instance_id: Dictionary[int, int] = {}
	for probe: AcousticProbe3D in probes:
		var probe_index := graph.add_probe(
			probe.global_position,
			probe.stable_id(),
			probe.effective_environment_influence_radius(),
			probe.guided_influence_world_center(),
			probe.guided_influence_world_half_extents(),
			probe.guided_influence_boundary_fade,
			probe.guided_spill_world_shape(),
			probe.attachment_exclusion_world_center(),
			probe.attachment_exclusion_world_half_extents(),
			probe.attachment_influence_world_center(),
			probe.attachment_influence_world_half_extents(),
			probe.attachment_influence_boundary_fade
		)
		probe_index_by_instance_id[probe.get_instance_id()] = probe_index

	var explicit_pairs: Dictionary[String, bool] = {}
	for node: Node in get_tree().get_nodes_in_group(&"acoustic_portals"):
		var portal := node as AcousticPortal3D
		if (
			portal == null
			or not portal.enabled
			or not server_world.is_ancestor_of(portal)
		):
			continue
		var probe_a := portal.get_probe_a()
		var probe_b := portal.get_probe_b()
		if probe_a == null or probe_b == null:
			continue
		var probe_a_index := int(probe_index_by_instance_id.get(
			probe_a.get_instance_id(),
			-1
		))
		var probe_b_index := int(probe_index_by_instance_id.get(
			probe_b.get_instance_id(),
			-1
		))
		if graph.connect_probes(
			probe_a_index,
			probe_b_index,
			portal.create_path_modifier(),
			portal.bidirectional,
			portal.carries_guided_energy
		):
			explicit_pairs[_pair_key(probe_a_index, probe_b_index)] = true

	var probe_indices_by_cell: Dictionary[Vector3i, Array] = {}
	for probe_index: int in range(probes.size()):
		var cell := _auto_connect_cell(probes[probe_index].global_position)
		var bucket: Array = probe_indices_by_cell.get(cell, [])
		bucket.append(probe_index)
		probe_indices_by_cell[cell] = bucket

	var space_state := server_world.get_world_3d().direct_space_state
	for probe_index: int in range(probes.size()):
		var probe := probes[probe_index]
		var response := (
			_sample_probe_environment(probe, space_state)
			if probe.sample_reflections
			else AcousticEnvironmentModel.open_air_response()
		)
		response = probe.apply_authored_environment_overrides(response)
		graph.set_probe_environment(probe_index, response)
		if float(response.get("enclosure", 0.0)) >= 0.70:
			_enclosed_probe_count += 1
		if float(response.get("tunnel_factor", 0.0)) >= 0.35:
			_tunnel_probe_count += 1
	for probe_a_index: int in range(probes.size()):
		var probe_a := probes[probe_a_index]
		if not probe_a.auto_connect:
			continue
		var cell_radius := ceili(
			probe_a.auto_connect_radius / AUTO_CONNECT_BUCKET_SIZE
		)
		var center_cell := _auto_connect_cell(probe_a.global_position)
		for cell_x: int in range(
			center_cell.x - cell_radius,
			center_cell.x + cell_radius + 1
		):
			for cell_y: int in range(
				center_cell.y - cell_radius,
				center_cell.y + cell_radius + 1
			):
				for cell_z: int in range(
					center_cell.z - cell_radius,
					center_cell.z + cell_radius + 1
				):
					var candidates: Array = probe_indices_by_cell.get(
						Vector3i(cell_x, cell_y, cell_z),
						[]
					)
					for probe_b_value: Variant in candidates:
						var probe_b_index := int(probe_b_value)
						if probe_b_index <= probe_a_index:
							continue
						_try_auto_connect_pair(
							probe_a_index,
							probe_b_index,
							probes,
							explicit_pairs,
							space_state
						)
	_build_diffuse_volume_links(probes, space_state)
	graph.rebuild_guided_regions()
	graph.rebuild_diffuse_regions()
	_build_static_boundary_bake()
	_try_save_cached_bake()


func _try_load_cached_bake() -> bool:
	var payload := AcousticBakeArtifact.load_validated(
		acoustic_bake_cache_path,
		_bake_signature
	)
	if payload.is_empty():
		if FileAccess.file_exists(acoustic_bake_cache_path):
			_bake_cache_rejection_count += 1
		return false
	if (
		not graph.import_bake_data(payload.get("graph", {}))
		or not static_boundary_bake.import_bake_data(
			payload.get("static_boundaries", {})
		)
	):
		graph.clear()
		static_boundary_bake.clear()
		_bake_cache_rejection_count += 1
		return false
	_recount_baked_probe_classes()
	_bake_loaded_from_cache = true
	_bake_cache_load_count += 1
	return true


func _try_save_cached_bake() -> void:
	if (
		not enable_static_bake_cache
		or acoustic_bake_cache_path.is_empty()
		or _bake_signature.is_empty()
		or graph.probe_count() <= 0
	):
		return
	if AcousticBakeArtifact.save_atomic(
		acoustic_bake_cache_path,
		_bake_signature,
		graph.export_bake_data(),
		static_boundary_bake.export_bake_data()
	):
		_bake_cache_write_count += 1


func _recount_baked_probe_classes() -> void:
	_enclosed_probe_count = 0
	_tunnel_probe_count = 0
	for probe_index: int in range(graph.probe_count()):
		var response := graph.environment_response(probe_index)
		if float(response.get("enclosure", 0.0)) >= 0.70:
			_enclosed_probe_count += 1
		if float(response.get("guided_propagation", 0.0)) >= 0.35:
			_tunnel_probe_count += 1


func _build_static_boundary_bake() -> void:
	static_boundary_bake.clear()
	for collider: CollisionObject3D in _bake_collision_objects():
		if (
			not collider is StaticBody3D
			or not _defines_acoustic_boundary(collider)
			or (collider.collision_layer & acoustic_collision_mask) == 0
		):
			continue
		var authored_material := _environment_material(collider)
		var modifier := _modifier_for_material(authored_material)
		var owner_ids := collider.get_shape_owners()
		owner_ids.sort()
		for owner_id: int in owner_ids:
			if collider.is_shape_owner_disabled(owner_id):
				continue
			var shape_transform := (
				collider.global_transform
				* collider.shape_owner_get_transform(owner_id)
			)
			for shape_index: int in range(
				collider.shape_owner_get_shape_count(owner_id)
			):
				var shape := collider.shape_owner_get_shape(
					owner_id,
					shape_index
				)
				if shape is BoxShape3D:
					static_boundary_bake.add_box(
						shape_transform,
						(shape as BoxShape3D).size,
						modifier,
						authored_material
					)
				else:
					static_boundary_bake.note_unsupported_shape()


func _world_bake_signature(probes: Array[AcousticProbe3D]) -> String:
	var probe_descriptors: Array[Dictionary] = []
	probe_descriptors.resize(probes.size())
	for probe_index: int in range(probes.size()):
		var probe := probes[probe_index]
		probe_descriptors[probe_index] = {
			"id": str(probe.stable_id()),
			"transform": probe.global_transform,
			"auto_connect": probe.auto_connect,
			"auto_connect_radius": probe.auto_connect_radius,
			"auto_connect_layer": probe.auto_connect_layer,
			"auto_connect_mask": probe.auto_connect_mask,
			"sample_reflections": probe.sample_reflections,
			"reflection_sample_distance": probe.reflection_sample_distance,
			"environment_influence_radius": probe.environment_influence_radius,
			"reverb_scale": probe.reverb_scale,
			"guided_spill_strength": probe.guided_spill_strength,
			"guided_center": probe.guided_influence_world_center(),
			"guided_half_extents": probe.guided_influence_world_half_extents(),
			"guided_boundary_fade": probe.guided_influence_boundary_fade,
			"guided_spill_shape": probe.guided_spill_world_shape(),
			"attachment_exclusion_center": probe.attachment_exclusion_world_center(),
			"attachment_exclusion_half_extents": probe.attachment_exclusion_world_half_extents(),
			"attachment_influence_center": probe.attachment_influence_world_center(),
			"attachment_influence_half_extents": probe.attachment_influence_world_half_extents(),
			"attachment_influence_boundary_fade": probe.attachment_influence_boundary_fade,
		}
	var collision_descriptors: Array[Dictionary] = []
	for collider: CollisionObject3D in _bake_collision_objects():
		var owner_ids := collider.get_shape_owners()
		owner_ids.sort()
		var shape_descriptors: Array[Dictionary] = []
		for owner_id: int in owner_ids:
			var owner_transform := (
				collider.global_transform
				* collider.shape_owner_get_transform(owner_id)
			)
			for shape_index: int in range(
				collider.shape_owner_get_shape_count(owner_id)
			):
				var shape := collider.shape_owner_get_shape(owner_id, shape_index)
				shape_descriptors.append(_shape_signature_descriptor(
					shape,
					owner_transform,
					collider.is_shape_owner_disabled(owner_id)
				))
		collision_descriptors.append({
			"path": str(collider.get_path()),
			"class": collider.get_class(),
			"collision_layer": collider.collision_layer,
			"acoustic_boundary": _defines_acoustic_boundary(collider),
			"material": _material_signature_descriptor(
				_environment_material(collider)
			),
			"shapes": shape_descriptors,
		})
	var portal_descriptors: Array[Dictionary] = []
	var portals: Array[AcousticPortal3D] = []
	for node: Node in get_tree().get_nodes_in_group(&"acoustic_portals"):
		if node is AcousticPortal3D and server_world.is_ancestor_of(node):
			portals.append(node as AcousticPortal3D)
	portals.sort_custom(
		func(left: AcousticPortal3D, right: AcousticPortal3D) -> bool:
			return str(left.get_path()) < str(right.get_path())
	)
	for portal: AcousticPortal3D in portals:
		var probe_a := portal.get_probe_a()
		var probe_b := portal.get_probe_b()
		portal_descriptors.append({
			"path": str(portal.get_path()),
			"enabled": portal.enabled,
			"probe_a": str(probe_a.stable_id()) if probe_a != null else "",
			"probe_b": str(probe_b.stable_id()) if probe_b != null else "",
			"bidirectional": portal.bidirectional,
			"guided": portal.carries_guided_energy,
			"modifier": _modifier_signature_descriptor(
				portal.create_path_modifier()
			),
		})
	var signature_data := {
		"behavior_version": ACOUSTIC_BAKE_BEHAVIOR_VERSION,
		"environment_sample_count": ENVIRONMENT_SAMPLE_DIRECTIONS.size(),
		"collision_mask": acoustic_collision_mask,
		"probes": probe_descriptors,
		"collisions": collision_descriptors,
		"portals": portal_descriptors,
	}
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(var_to_bytes(signature_data)) != OK:
		return ""
	return context.finish().hex_encode()


func _bake_collision_objects() -> Array[CollisionObject3D]:
	var result: Array[CollisionObject3D] = []
	_collect_bake_collision_objects(server_world, result)
	result.sort_custom(
		func(left: CollisionObject3D, right: CollisionObject3D) -> bool:
			return str(left.get_path()) < str(right.get_path())
	)
	return result


func _collect_bake_collision_objects(
	node: Node,
	result: Array[CollisionObject3D]
) -> void:
	if node is StaticBody3D or node is AnimatableBody3D:
		result.append(node as CollisionObject3D)
	for child: Node in node.get_children():
		_collect_bake_collision_objects(child, result)


func _shape_signature_descriptor(
	shape: Shape3D,
	world_transform: Transform3D,
	disabled: bool
) -> Dictionary:
	var result := {
		"class": shape.get_class() if shape != null else "null",
		"transform": world_transform,
		"disabled": disabled,
		"resource_path": shape.resource_path if shape != null else "",
	}
	if shape is BoxShape3D:
		result["size"] = (shape as BoxShape3D).size
	elif shape is SphereShape3D:
		result["radius"] = (shape as SphereShape3D).radius
	elif shape is CapsuleShape3D:
		result["radius"] = (shape as CapsuleShape3D).radius
		result["height"] = (shape as CapsuleShape3D).height
	elif shape is CylinderShape3D:
		result["radius"] = (shape as CylinderShape3D).radius
		result["height"] = (shape as CylinderShape3D).height
	elif shape is ConvexPolygonShape3D:
		result["points"] = (shape as ConvexPolygonShape3D).points
	elif shape is ConcavePolygonShape3D:
		result["faces"] = (shape as ConcavePolygonShape3D).get_faces()
	elif shape != null:
		var debug_mesh := shape.get_debug_mesh()
		if debug_mesh != null:
			result["debug_faces"] = debug_mesh.get_faces()
	return result


static func _material_signature_descriptor(material: AcousticMaterial) -> Dictionary:
	if material == null:
		return {}
	return {
		"id": str(material.material_id),
		"transmission_gain": material.transmission_gain,
		"absorption": material.absorption,
		"scattering": material.scattering,
		"transmission_volume_db": material.transmission_volume_db,
		"transmission_lowpass_hz": material.transmission_lowpass_hz,
		"transmission_highpass_hz": material.transmission_highpass_hz,
		"resonance": material.resonance,
		"reverb_send": material.reverb_send,
		"additional_modifier": _modifier_signature_descriptor(
			material.additional_modifier
		),
	}


static func _modifier_signature_descriptor(
	modifier: AcousticPathModifier
) -> Dictionary:
	if modifier == null:
		return {}
	var safe := modifier.sanitized_copy()
	return {
		"id": str(safe.modifier_id),
		"band_gain": safe.band_gain,
		"volume_db": safe.volume_db,
		"extra_delay_seconds": safe.extra_delay_seconds,
		"lowpass_hz": safe.lowpass_hz,
		"highpass_hz": safe.highpass_hz,
		"resonance": safe.resonance,
		"reverb_send": safe.reverb_send,
	}


func _build_diffuse_volume_links(
	probes: Array[AcousticProbe3D],
	space_state: PhysicsDirectSpaceState3D
) -> void:
	# Propagation edges stay deliberately local. A room field needs a second, bake-only notion of
	# shared air so distant probes in one garage are not split merely because a crate interrupted
	# their shortest graph edge. Structural walls still stop this visibility test.
	for probe_a_index: int in range(probes.size()):
		for probe_b_index: int in range(probe_a_index + 1, probes.size()):
			if not probes[probe_a_index].can_auto_connect_to(probes[probe_b_index]):
				continue
			if not graph.probes_can_share_diffuse_region(
				probe_a_index,
				probe_b_index
			):
				continue
			var probe_a := probes[probe_a_index]
			var probe_b := probes[probe_b_index]
			var link_distance := (
				minf(probe_a.auto_connect_radius, probe_b.auto_connect_radius)
				* 2.25
			)
			if probe_a.global_position.distance_squared_to(
				probe_b.global_position
			) > link_distance * link_distance:
				continue
			if _diffuse_volume_line_clear(
				probe_a.global_position,
				probe_b.global_position,
				space_state
			):
				graph.connect_diffuse_probes(probe_a_index, probe_b_index)


func _diffuse_volume_line_clear(
	from: Vector3,
	to: Vector3,
	space_state: PhysicsDirectSpaceState3D
) -> bool:
	var exclusions: Array[RID] = []
	for _attempt: int in range(MAX_IGNORED_DIRECT_PATH_BODIES + 1):
		var query := PhysicsRayQueryParameters3D.create(
			from,
			to,
			acoustic_collision_mask
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		query.exclude = exclusions
		var hit := space_state.intersect_ray(query)
		_environment_ray_count += 1
		if hit.is_empty():
			return true
		var collider := hit.get("collider") as CollisionObject3D
		if _defines_acoustic_boundary(collider):
			return false
		var collider_rid: RID = hit.get("rid", RID())
		if not collider_rid.is_valid():
			return false
		exclusions.append(collider_rid)
	return false


func _try_auto_connect_pair(
	probe_a_index: int,
	probe_b_index: int,
	probes: Array[AcousticProbe3D],
	explicit_pairs: Dictionary[String, bool],
	space_state: PhysicsDirectSpaceState3D
) -> void:
	var probe_a := probes[probe_a_index]
	var probe_b := probes[probe_b_index]
	if (
		not probe_b.auto_connect
		or not probe_a.can_auto_connect_to(probe_b)
		or explicit_pairs.has(_pair_key(probe_a_index, probe_b_index))
	):
		return
	var maximum_distance := minf(
		probe_a.auto_connect_radius,
		probe_b.auto_connect_radius
	)
	if probe_a.global_position.distance_squared_to(
		probe_b.global_position
	) > maximum_distance * maximum_distance:
		return
	var query := PhysicsRayQueryParameters3D.create(
		probe_a.global_position,
		probe_b.global_position,
		acoustic_collision_mask
	)
	query.collide_with_areas = false
	if space_state.intersect_ray(query).is_empty():
		graph.connect_probes(
			probe_a_index,
			probe_b_index,
			null,
			true,
			graph.probes_can_share_guided_region(
				probe_a_index,
				probe_b_index
			)
		)


func _sample_probe_environment(
	probe: AcousticProbe3D,
	space_state: PhysicsDirectSpaceState3D
) -> Dictionary:
	var distances := PackedFloat32Array()
	var hit_mask := PackedByteArray()
	var absorptions := PackedVector3Array()
	var scatterings := PackedFloat32Array()
	var escape_direction_sum := Vector3.ZERO
	var escape_sample_count := 0
	var maximum_distance := maxf(probe.reflection_sample_distance, 2.0)
	distances.resize(ENVIRONMENT_SAMPLE_DIRECTIONS.size())
	hit_mask.resize(ENVIRONMENT_SAMPLE_DIRECTIONS.size())
	absorptions.resize(ENVIRONMENT_SAMPLE_DIRECTIONS.size())
	scatterings.resize(ENVIRONMENT_SAMPLE_DIRECTIONS.size())
	for sample_index: int in range(ENVIRONMENT_SAMPLE_DIRECTIONS.size()):
		var hit := _environment_surface_hit(
			probe.global_position,
			probe.global_position
			+ ENVIRONMENT_SAMPLE_DIRECTIONS[sample_index] * maximum_distance,
			space_state
		)
		_environment_ray_count += 1
		if hit.is_empty():
			distances[sample_index] = maximum_distance
			hit_mask[sample_index] = 0
			absorptions[sample_index] = Vector3.ONE
			scatterings[sample_index] = 0.0
			escape_direction_sum += ENVIRONMENT_SAMPLE_DIRECTIONS[sample_index]
			escape_sample_count += 1
			continue
		var hit_position: Vector3 = hit.get("position", probe.global_position)
		distances[sample_index] = clampf(
			probe.global_position.distance_to(hit_position),
			0.01,
			maximum_distance
		)
		hit_mask[sample_index] = 1
		var collider := hit.get("collider") as CollisionObject3D
		var material := _environment_material(collider)
		absorptions[sample_index] = material.sanitized_absorption()
		scatterings[sample_index] = material.sanitized_scattering()
	var response := AcousticEnvironmentModel.response_from_samples(
		distances,
		hit_mask,
		absorptions,
		scatterings,
		maximum_distance,
		probe.reverb_scale
	)
	if escape_sample_count > 0:
		var mean_escape_direction := (
			escape_direction_sum / float(escape_sample_count)
		)
		response["pressure_escape_directionality"] = clampf(
			mean_escape_direction.length(),
			0.0,
			1.0
		)
		if not mean_escape_direction.is_zero_approx():
			response["pressure_escape_direction"] = (
				mean_escape_direction.normalized()
			)
	return response


func _environment_surface_hit(
	from: Vector3,
	to: Vector3,
	space_state: PhysicsDirectSpaceState3D
) -> Dictionary:
	var exclusions: Array[RID] = []
	for _attempt: int in range(MAX_IGNORED_DIRECT_PATH_BODIES + 1):
		var query := PhysicsRayQueryParameters3D.create(
			from,
			to,
			acoustic_collision_mask
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		query.exclude = exclusions
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.get("collider") as CollisionObject3D
		if (
			collider is StaticBody3D
			or collider is AnimatableBody3D
			or _authored_material(collider) != null
		):
			return hit
		var collider_rid: RID = hit.get("rid", RID())
		if not collider_rid.is_valid():
			return {}
		exclusions.append(collider_rid)
	return {}


static func _pair_key(probe_a: int, probe_b: int) -> String:
	return (
		"%d:%d" % [probe_a, probe_b]
		if probe_a < probe_b
		else "%d:%d" % [probe_b, probe_a]
	)


static func _auto_connect_cell(position: Vector3) -> Vector3i:
	return Vector3i(
		floori(position.x / AUTO_CONNECT_BUCKET_SIZE),
		floori(position.y / AUTO_CONNECT_BUCKET_SIZE),
		floori(position.z / AUTO_CONNECT_BUCKET_SIZE)
	)


func _sample_direct_path(
	listener_id: int,
	listener_position: Vector3,
	source_position: Vector3,
	exclude_rids: Array[RID],
	continuous_source_id: int
) -> Dictionary:
	if (
		not is_instance_valid(server_world)
		or not server_world.is_inside_tree()
		or server_world.get_world_3d() == null
		or not listener_position.is_finite()
		or not source_position.is_finite()
	):
		return {"available": false, "blocked": false}
	if listener_position.distance_squared_to(source_position) <= 0.000001:
		return {"available": true, "blocked": false}

	var cache_key := Vector2i(listener_id, continuous_source_id)
	var now_msec := Time.get_ticks_msec()
	var previous_path: Dictionary = {}
	if continuous_source_id != 0:
		var cached: Dictionary = _direct_paths_by_source.get(cache_key, {})
		previous_path = cached
		if (
			not cached.is_empty()
			and now_msec - int(cached.get("sampled_at_msec", 0))
			< int(DIRECT_PATH_CACHE_SECONDS * 1000.0)
			and listener_position.distance_squared_to(
				cached.get("listener_position", Vector3(INF, INF, INF))
			) < DIRECT_PATH_LISTENER_REFRESH_DISTANCE * DIRECT_PATH_LISTENER_REFRESH_DISTANCE
			and source_position.distance_squared_to(
				cached.get("source_position", Vector3(INF, INF, INF))
			) < DIRECT_PATH_SOURCE_REFRESH_DISTANCE * DIRECT_PATH_SOURCE_REFRESH_DISTANCE
		):
			return cached

	var space_state := server_world.get_world_3d().direct_space_state
	var central_hit := _trace_acoustic_obstruction(
		listener_position,
		source_position,
		exclude_rids,
		space_state
	)
	var geometry_blocked := not central_hit.is_empty()
	var blocked := geometry_blocked
	var blocking_modifier: AcousticPathModifier
	var occlusion := 0.0
	var static_boundary_crossing_count := 0
	var blocking_collider := central_hit.get("collider") as CollisionObject3D
	var structural_blocked := (
		geometry_blocked and _defines_acoustic_boundary(blocking_collider)
	)
	if geometry_blocked:
		blocking_modifier = _modifier_for_material(
			_authored_material(blocking_collider)
		)
		if (
			enable_cumulative_static_transmission
			and _defines_acoustic_boundary(blocking_collider)
		):
			_cumulative_transmission_query_count += 1
			var cumulative := static_boundary_bake.sample_transmission(
				listener_position,
				source_position
			)
			static_boundary_crossing_count = int(cumulative.get(
				"crossing_count",
				0
			))
			if static_boundary_crossing_count > 0:
				_cumulative_transmission_crossing_count += (
					static_boundary_crossing_count
				)
				var cumulative_modifier := cumulative.get(
					"modifier"
				) as AcousticPathModifier
				var hit_position: Vector3 = central_hit.get(
					"position",
					listener_position
				)
				var central_hit_distance := listener_position.distance_to(
					hit_position
				)
				var baked_first_distance := float(cumulative.get(
					"first_entry_distance",
					INF
				))
				if cumulative_modifier != null:
					blocking_modifier = (
						cumulative_modifier
						if absf(
							baked_first_distance - central_hit_distance
						) <= AcousticStaticBoundaryBake.MERGE_DISTANCE_METERS * 2.0
						else blocking_modifier.combined_with(
							cumulative_modifier
						)
					)
		occlusion = (
			1.0
			if _defines_acoustic_boundary(blocking_collider)
			else _sample_partial_occlusion(
				listener_position,
				source_position,
				exclude_rids,
				space_state
			)
		)
		# A narrow prop can intersect the centre line and still leave most of the acoustic
		# aperture clear. Collision owners may cap coverage independently from their material:
		# material says how a covered ray changes, geometry says how much of the wave is covered.
		if (
			blocking_collider != null
			and blocking_collider.has_meta(META_MAX_PARTIAL_OCCLUSION)
		):
			occlusion = minf(
				occlusion,
				clampf(
					SafeVariant.finite_float_or(
						blocking_collider.get_meta(META_MAX_PARTIAL_OCCLUSION),
						1.0
					),
					0.0,
					1.0
				)
			)
	# A five-ray aperture estimate is deliberately cheap, but its raw coverage has discrete levels.
	# Reconstruct every coverage change through the persistent direct-path cache—not only changes
	# of the centre ray. This adds no physics queries and applies the same continuous rule to props,
	# tree trunks, door frames, walls, and future imported geometry.
	var target_occlusion := occlusion if geometry_blocked else 0.0
	var aperture_openness := 1.0 - target_occlusion
	var transition_active := false
	if continuous_source_id != 0 and not previous_path.is_empty():
		var previous_occlusion := clampf(
			float(previous_path.get("occlusion", 0.0)),
			0.0,
			1.0
		)
		if not is_equal_approx(target_occlusion, previous_occlusion):
			var movement_distance := (
				listener_position.distance_to(previous_path.get(
					"listener_position",
					listener_position
				))
				+ source_position.distance_to(previous_path.get(
					"source_position",
					source_position
				))
			)
			var elapsed_seconds := maxf(
				float(now_msec - int(previous_path.get(
					"sampled_at_msec",
					now_msec
				))) / 1000.0,
				0.0
			)
			var transition_step := clampf(maxf(
				movement_distance / DIRECT_PATH_EDGE_BLEND_DISTANCE,
				elapsed_seconds / DIRECT_PATH_EDGE_BLEND_SECONDS
			), 0.0, 1.0)
			occlusion = move_toward(
				previous_occlusion,
				target_occlusion,
				transition_step
			)
			aperture_openness = 1.0 - occlusion
			transition_active = not is_equal_approx(
				occlusion,
				target_occlusion
			)
			if not geometry_blocked:
				blocking_modifier = previous_path.get("modifier") as AcousticPathModifier
				structural_blocked = bool(previous_path.get(
					"structural_blocked",
					false
				))
	blocked = occlusion > 0.0001

	var result := {
		"available": true,
		"blocked": blocked,
		"geometry_blocked": geometry_blocked,
		"structural_blocked": structural_blocked,
		"edge_transition_active": transition_active,
		"aperture_openness": aperture_openness,
		"occlusion": occlusion,
		"modifier": blocking_modifier,
		"static_boundary_crossing_count": static_boundary_crossing_count,
		"listener_position": listener_position,
		"source_position": source_position,
		"sampled_at_msec": now_msec,
	}
	if continuous_source_id != 0:
		_direct_paths_by_source[cache_key] = result
	return result


static func _mix_parallel_route_results(
	graph_route: Dictionary,
	direct_route: Dictionary,
	graph_participation: float,
	direct_participation: float,
	route_kind: StringName
) -> Dictionary:
	var safe_graph_participation := (
		clampf(graph_participation, 0.0, 1.0)
		if bool(graph_route.get("audible", false))
		else 0.0
	)
	var safe_direct_participation := (
		clampf(direct_participation, 0.0, 1.0)
		if bool(direct_route.get("audible", false))
		else 0.0
	)
	var graph_volume_db := SafeVariant.finite_float_or(
		graph_route.get("volume_db"),
		AcousticPathModifier.MIN_VOLUME_DB
	)
	var direct_volume_db := SafeVariant.finite_float_or(
		direct_route.get("volume_db"),
		AcousticPathModifier.MIN_VOLUME_DB
	)
	var graph_amplitude := db_to_linear(graph_volume_db)
	var direct_amplitude := db_to_linear(direct_volume_db)
	var graph_power := (
		graph_amplitude * graph_amplitude * safe_graph_participation
	)
	var direct_power := (
		direct_amplitude * direct_amplitude * safe_direct_participation
	)
	var total_power := graph_power + direct_power
	if total_power <= 0.000000000001:
		direct_route["audible"] = false
		direct_route["route_kind"] = &"silent"
		return direct_route
	var graph_weight := graph_power / total_power
	var direct_weight := direct_power / total_power
	# Reuse the already allocated direct dictionary. The hot path adds no third result object.
	var result := direct_route
	result["audible"] = true
	result["volume_db"] = clampf(
		10.0 * log(total_power) / log(10.0),
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	for key: StringName in ROUTE_MIX_SCALAR_KEYS:
		if graph_route.has(key) or direct_route.has(key):
			var direct_value := SafeVariant.finite_float_or(
				direct_route.get(key),
				SafeVariant.finite_float_or(graph_route.get(key), 0.0)
			)
			result[key] = lerpf(
				direct_value,
				SafeVariant.finite_float_or(graph_route.get(key), direct_value),
				graph_weight
			)
	for key: StringName in ROUTE_MIX_FREQUENCY_KEYS:
		var direct_hz := maxf(SafeVariant.finite_float_or(
			direct_route.get(key),
			AcousticPathModifier.MIN_FILTER_HZ
		), AcousticPathModifier.MIN_FILTER_HZ)
		var graph_hz := maxf(SafeVariant.finite_float_or(
			graph_route.get(key),
			direct_hz
		), AcousticPathModifier.MIN_FILTER_HZ)
		result[key] = exp(lerpf(log(direct_hz), log(graph_hz), graph_weight))
	var graph_bands: Vector3 = graph_route.get("band_gain", Vector3.ONE)
	var direct_bands: Vector3 = direct_route.get("band_gain", Vector3.ONE)
	# EQ gains are amplitudes. Sum their squared, route-weighted values so each output band carries
	# exactly the parallel-path energy represented by the scalar volume above.
	result["band_gain"] = Vector3(
		sqrt(maxf(
			direct_bands.x * direct_bands.x * direct_weight
			+ graph_bands.x * graph_bands.x * graph_weight,
			0.0
		)),
		sqrt(maxf(
			direct_bands.y * direct_bands.y * direct_weight
			+ graph_bands.y * graph_bands.y * graph_weight,
			0.0
		)),
		sqrt(maxf(
			direct_bands.z * direct_bands.z * direct_weight
			+ graph_bands.z * graph_bands.z * graph_weight,
			0.0
		))
	)
	var graph_position: Vector3 = graph_route.get(
		"apparent_position",
		direct_route.get("apparent_position", Vector3.ZERO)
	)
	var direct_position: Vector3 = direct_route.get(
		"apparent_position",
		graph_position
	)
	var listener_position: Vector3 = graph_route.get(
		"listener_position",
		direct_route.get("listener_position", Vector3(INF, INF, INF))
	)
	if listener_position.is_finite():
		var graph_offset := graph_position - listener_position
		var direct_offset := direct_position - listener_position
		var graph_direction := (
			graph_offset.normalized()
			if not graph_offset.is_zero_approx()
			else Vector3.ZERO
		)
		var direct_direction := (
			direct_offset.normalized()
			if not direct_offset.is_zero_approx()
			else Vector3.ZERO
		)
		var mixed_direction := (
			direct_direction * direct_weight
			+ graph_direction * graph_weight
		)
		if mixed_direction.is_zero_approx():
			mixed_direction = (
				graph_direction
				if graph_weight >= direct_weight
				else direct_direction
			)
		var apparent_distance := lerpf(
			clampf(direct_offset.length(), 1.0, AcousticPropagationGraph.APPARENT_SOURCE_DISTANCE),
			clampf(graph_offset.length(), 1.0, AcousticPropagationGraph.APPARENT_SOURCE_DISTANCE),
			graph_weight
		)
		result["apparent_position"] = (
			listener_position
			+ mixed_direction.normalized() * apparent_distance
		)
	else:
		result["apparent_position"] = direct_position.lerp(
			graph_position,
			graph_weight
		)
	result["route_kind"] = (
		route_kind
		if safe_graph_participation > 0.0 and safe_direct_participation > 0.0
		else &"graph" if safe_graph_participation > 0.0 else &"transmitted"
	)
	result["route_graph_energy_weight"] = graph_weight
	result["route_direct_energy_weight"] = direct_weight
	result["route_graph_participation"] = safe_graph_participation
	result["route_direct_participation"] = safe_direct_participation
	var strongest_route_db := maxf(
		graph_volume_db
		if safe_graph_participation > 0.0
		else AcousticPathModifier.MIN_VOLUME_DB,
		direct_volume_db
		if safe_direct_participation > 0.0
		else AcousticPathModifier.MIN_VOLUME_DB
	)
	result["parallel_route_gain_db"] = (
		float(result["volume_db"]) - strongest_route_db
	)
	result["modifier_ids"] = (
		graph_route.get("modifier_ids", PackedStringArray())
		if graph_weight >= direct_weight
		else direct_route.get("modifier_ids", PackedStringArray())
	)
	if graph_weight >= direct_weight:
		result["source_probe_index"] = int(graph_route.get(
			"source_probe_index",
			result.get("source_probe_index", -1)
		))
	if graph_route.has("listener_origin_probe_index"):
		result["listener_origin_probe_index"] = int(
			graph_route["listener_origin_probe_index"]
		)
	if graph_route.has("field_transition_active"):
		result["field_transition_active"] = bool(
			graph_route["field_transition_active"]
		)
		result["field_transition_weight"] = float(
			graph_route.get("field_transition_weight", 1.0)
		)
	return result


func _trace_acoustic_obstruction(
	listener_position: Vector3,
	source_position: Vector3,
	exclude_rids: Array[RID],
	space_state: PhysicsDirectSpaceState3D
) -> Dictionary:
	var exclusions: Array[RID] = exclude_rids.duplicate()
	var nearest_partial_hit: Dictionary = {}
	for _attempt: int in range(MAX_IGNORED_DIRECT_PATH_BODIES + 1):
		var query := PhysicsRayQueryParameters3D.create(
			listener_position,
			source_position,
			acoustic_collision_mask
		)
		query.collide_with_areas = false
		query.hit_from_inside = false
		query.exclude = exclusions
		var hit := space_state.intersect_ray(query)
		_visibility_ray_count += 1
		if hit.is_empty():
			return nearest_partial_hit
		var collider := hit.get("collider") as CollisionObject3D
		if (
			collider is StaticBody3D
			or collider is AnimatableBody3D
			or _authored_material(collider) != null
		):
			# A deliberately non-boundary object (tree, crate, narrow prop) may
			# partially cover a wave, but it cannot hide a structural wall farther
			# along the same ray. Retain the nearest partial hit as the fallback and
			# keep looking for a true boundary. Nature batches all trunks into one
			# body, so excluding its RID also skips the rest without per-tree work.
			if _defines_acoustic_boundary(collider):
				return hit
			if nearest_partial_hit.is_empty():
				nearest_partial_hit = hit
		var collider_rid: RID = hit.get("rid", RID())
		if not collider_rid.is_valid():
			return nearest_partial_hit
		exclusions.append(collider_rid)
	return nearest_partial_hit


func _sample_partial_occlusion(
	listener_position: Vector3,
	source_position: Vector3,
	exclude_rids: Array[RID],
	space_state: PhysicsDirectSpaceState3D
) -> float:
	var direction := (source_position - listener_position).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() <= 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized() * PARTIAL_OCCLUSION_SAMPLE_RADIUS
	var vertical := side.normalized().cross(direction).normalized()
	vertical *= PARTIAL_OCCLUSION_SAMPLE_RADIUS
	var blocked_samples := 1
	# Offset both endpoints. These are parallel aperture samples, so their spacing is stable
	# regardless of whether the obstruction is beside the source, listener, or halfway between.
	# Offsetting only the source collapses the fan close to the listener and makes a tree trunk
	# several metres away look like a full wall.
	if not _trace_acoustic_obstruction(
		listener_position + side,
		source_position + side,
		exclude_rids,
		space_state
	).is_empty():
		blocked_samples += 1
	if not _trace_acoustic_obstruction(
		listener_position - side,
		source_position - side,
		exclude_rids,
		space_state
	).is_empty():
		blocked_samples += 1
	if not _trace_acoustic_obstruction(
		listener_position + vertical,
		source_position + vertical,
		exclude_rids,
		space_state
	).is_empty():
		blocked_samples += 1
	if not _trace_acoustic_obstruction(
		listener_position - vertical,
		source_position - vertical,
		exclude_rids,
		space_state
	).is_empty():
		blocked_samples += 1
	return float(blocked_samples) / float(PARTIAL_OCCLUSION_SAMPLE_COUNT)


func _defines_acoustic_boundary(collider: CollisionObject3D) -> bool:
	if collider == null:
		return false
	if collider.has_meta(&"acoustic_boundary"):
		return bool(collider.get_meta(&"acoustic_boundary"))
	return (
		collider is StaticBody3D
		or collider is AnimatableBody3D
		or _authored_material(collider) != null
	)


func _authored_material(collider: CollisionObject3D) -> AcousticMaterial:
	if collider == null:
		return null
	var candidate: Variant
	if collider.has_method("get_acoustic_material"):
		candidate = collider.call("get_acoustic_material")
	elif collider.has_meta("acoustic_material"):
		candidate = collider.get_meta("acoustic_material")
	return candidate as AcousticMaterial


func _environment_material(collider: CollisionObject3D) -> AcousticMaterial:
	var authored := _authored_material(collider)
	if authored != null:
		return authored
	if _default_environment_material == null:
		_default_environment_material = AcousticMaterial.new()
		_default_environment_material.material_id = &"generic_solid"
	return _default_environment_material


func _modifier_for_material(material: AcousticMaterial) -> AcousticPathModifier:
	if material == null:
		if _default_solid_modifier == null:
			var fallback := AcousticMaterial.new()
			fallback.material_id = &"generic_solid"
			_default_solid_modifier = fallback.create_transmission_modifier()
		return _default_solid_modifier
	var instance_id := int(material.get_instance_id())
	var cached := _material_modifiers_by_instance_id.get(instance_id) as AcousticPathModifier
	if cached == null:
		cached = material.create_transmission_modifier()
		_material_modifiers_by_instance_id[instance_id] = cached
	return cached

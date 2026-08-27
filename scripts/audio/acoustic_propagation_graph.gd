class_name AcousticPropagationGraph
extends RefCounted

const SPEED_OF_SOUND_METERS_PER_SECOND := 343.0
const DEFAULT_REFERENCE_DISTANCE := 1.0
const MAX_LEVEL_SCALED_HEARING_DISTANCE := 10000.0
const MIN_SOURCE_LEVEL_DB := -80.0
const MAX_SOURCE_LEVEL_DB := 18.0
const APPARENT_SOURCE_DISTANCE := 4.0
const MIN_GAIN := 0.0001
const SOURCE_ATTACHMENT_ROUTE_DISTANCE_SLACK := 0.75
const UNGUIDED_NEAR_FIELD_LOSS_DB := 6.0
const GUIDED_SPREADING_RECOVERY_SCALE := 0.68
const MAX_GUIDED_RECOVERY_DB := 18.0
const MAX_GUIDED_RANGE_SCALE := 2.2
const GUIDED_PATH_DISTANCE_SCALE := 0.32
const OPEN_GUIDED_SPILL_FALLOFF_DISTANCE := 10.0
const ENCLOSED_GUIDED_BOUNDARY_BLEND_DISTANCE := 0.75
const ROOM_CRITICAL_DISTANCE_SCALE := 0.057
const MIN_DIFFUSE_CRITICAL_DISTANCE := 0.75
const MAX_DIFFUSE_CRITICAL_DISTANCE := 12.0
const DIFFUSE_FAR_LOSS_DB_PER_DOUBLING := 1.0
const MIN_DIFFUSE_REGION_ENCLOSURE := 0.5
const MIN_DIFFUSE_REGION_REVERB_SEND := 0.05
const MIN_DIFFUSE_EDGE_BAND_GAIN := 0.95
const MIN_DIFFUSE_EDGE_VOLUME_DB := -0.5
const RANGE_FADE_FRACTION := 5.0 / 12.0
const MAX_RANGE_FADE_ATTENUATION_DB := 48.0
const RANGE_FADE_EDGE_EASE_FRACTION := 0.15
const SOURCE_REVERB_SPILL_SCALE := 0.78
const MAX_SOURCE_REVERB_SPILL_SEND := 0.38
const LISTENER_PROBE_BLEND_REGULARIZATION_SQUARED := 2.25
const MAX_PRESSURE_ARRIVALS := 3
const PRESSURE_ALTERNATE_DELAY_EPSILON_SECONDS := 0.006
const PRESSURE_ALTERNATE_ROUTE_PENALTY_DB := -9.0
const BAKE_SCHEMA_VERSION := 3
const MAX_BAKED_PROBES := 200000
const MAX_BAKED_DIRECTED_EDGES := 2000000
const MAX_BAKED_DIFFUSE_LINKS := 1000000
const DEFAULT_AIR_ABSORPTION_DB_PER_METER := Vector3(
	0.0002,
	0.002,
	0.02
)
# Probe paths approximate the center line of the open wave route. A route that changes direction
# around an aperture or wall edge must therefore pay diffraction/deviation loss; charging only
# distance made a many-corner maze route sound like clean outdoor line-of-sight once it reached the
# forest. The small angular dead zone prevents harmless probe-placement jitter from becoming EQ.
const PATH_DEVIATION_DEAD_ZONE_RADIANS := deg_to_rad(8.0)
# Late/reverberant arrivals keep finite energy even after many bends. Saturating the cumulative
# response models that floor and avoids a long tunnel or maze multiplying whole music bands to
# digital zero while retaining clear low > mid > high diffraction coloration.
const PATH_DEVIATION_MAX_ATTENUATION_DB := Vector3(5.0, 15.0, 32.0)
const PATH_DEVIATION_SATURATION_SCALE := 4.0
const PATH_DEVIATION_EXPONENT := 1.15

var revision := 0

var _positions := PackedVector3Array()
var _probe_ids := PackedStringArray()
var _targets_by_probe: Array[PackedInt32Array] = []
var _lengths_by_probe: Array[PackedFloat32Array] = []
var _band_gains_by_probe: Array[PackedVector3Array] = []
var _volume_db_by_probe: Array[PackedFloat32Array] = []
var _delays_by_probe: Array[PackedFloat32Array] = []
var _lowpass_by_probe: Array[PackedFloat32Array] = []
var _highpass_by_probe: Array[PackedFloat32Array] = []
var _resonance_by_probe: Array[PackedFloat32Array] = []
var _reverb_by_probe: Array[PackedFloat32Array] = []
var _guided_edges_by_probe: Array[PackedByteArray] = []
var _modifier_indices_by_probe: Array[PackedInt32Array] = []
var _diffuse_links_by_probe: Array[PackedInt32Array] = []
var _modifiers: Array[AcousticPathModifier] = []
var _environment_influence_radii := PackedFloat32Array()
var _environment_guided_centers := PackedVector3Array()
var _environment_guided_half_extents := PackedVector3Array()
var _environment_guided_boundary_fades := PackedFloat32Array()
var _environment_guided_spill_origins := PackedVector3Array()
var _environment_guided_spill_axes := PackedVector3Array()
var _environment_guided_spill_lateral_axes := PackedVector3Array()
var _environment_guided_spill_vertical_axes := PackedVector3Array()
var _environment_guided_spill_apertures := PackedVector2Array()
var _environment_guided_spill_divergences := PackedVector2Array()
var _environment_guided_spill_falloff_distances := PackedFloat32Array()
var _attachment_exclusion_centers := PackedVector3Array()
var _attachment_exclusion_half_extents := PackedVector3Array()
var _attachment_influence_centers := PackedVector3Array()
var _attachment_influence_half_extents := PackedVector3Array()
var _attachment_influence_boundary_fades := PackedFloat32Array()
var _environment_guidance_is_authored := PackedByteArray()
var _environment_enclosure := PackedFloat32Array()
var _environment_guided_propagation := PackedFloat32Array()
var _guided_region_by_probe := PackedInt32Array()
var _guided_probes_by_region: Array[PackedInt32Array] = []
var _guided_regions_dirty := true
var _environment_guided_wall_loss_db_per_m := PackedFloat32Array()
var _environment_rt60_seconds := PackedFloat32Array()
var _environment_reverb_send := PackedFloat32Array()
var _environment_volume_m3 := PackedFloat32Array()
var _environment_room_size := PackedFloat32Array()
var _environment_damping := PackedFloat32Array()
var _environment_spread := PackedFloat32Array()
var _environment_predelay_msec := PackedFloat32Array()
var _environment_predelay_feedback := PackedFloat32Array()
var _environment_hipass := PackedFloat32Array()
var _pressure_confinement := PackedFloat32Array()
var _pressure_body_gain_db := PackedFloat32Array()
var _pressure_bass_boost_db := PackedFloat32Array()
var _pressure_reflection_delay_seconds := PackedFloat32Array()
var _pressure_reverb_send := PackedFloat32Array()
var _pressure_decay_seconds := PackedFloat32Array()
var _pressure_escape := PackedFloat32Array()
var _pressure_escape_directions := PackedVector3Array()
var _pressure_escape_directionality := PackedFloat32Array()
var _diffuse_region_by_probe := PackedInt32Array()
var _diffuse_region_volume_m3 := PackedFloat32Array()
var _diffuse_region_rt60_seconds := PackedFloat32Array()
var _diffuse_region_strength := PackedFloat32Array()
var _diffuse_region_critical_distance := PackedFloat32Array()
var _diffuse_regions_dirty := true


## Authored hearing distances are calibrated at 0 dB. In the far field, spherical spreading loses
## 6.02 dB per distance doubling, so applying the inverse amplitude gain to reach preserves the
## same level at the fade boundary. The cap bounds gain-derived reach before geometry guidance.
static func level_scaled_hearing_distance(
	zero_db_distance: float,
	source_level_db: float
) -> float:
	if not is_finite(zero_db_distance) or not is_finite(source_level_db):
		return 0.0
	var safe_distance := maxf(zero_db_distance, 0.0)
	var safe_level_db := clampf(
		source_level_db,
		MIN_SOURCE_LEVEL_DB,
		MAX_SOURCE_LEVEL_DB
	)
	return minf(
		safe_distance * db_to_linear(safe_level_db),
		MAX_LEVEL_SCALED_HEARING_DISTANCE
	)


func clear() -> void:
	_positions.clear()
	_probe_ids.clear()
	_targets_by_probe.clear()
	_lengths_by_probe.clear()
	_band_gains_by_probe.clear()
	_volume_db_by_probe.clear()
	_delays_by_probe.clear()
	_lowpass_by_probe.clear()
	_highpass_by_probe.clear()
	_resonance_by_probe.clear()
	_reverb_by_probe.clear()
	_guided_edges_by_probe.clear()
	_modifier_indices_by_probe.clear()
	_diffuse_links_by_probe.clear()
	_modifiers.clear()
	_environment_influence_radii.clear()
	_environment_guided_centers.clear()
	_environment_guided_half_extents.clear()
	_environment_guided_boundary_fades.clear()
	_environment_guided_spill_origins.clear()
	_environment_guided_spill_axes.clear()
	_environment_guided_spill_lateral_axes.clear()
	_environment_guided_spill_vertical_axes.clear()
	_environment_guided_spill_apertures.clear()
	_environment_guided_spill_divergences.clear()
	_environment_guided_spill_falloff_distances.clear()
	_attachment_exclusion_centers.clear()
	_attachment_exclusion_half_extents.clear()
	_attachment_influence_centers.clear()
	_attachment_influence_half_extents.clear()
	_attachment_influence_boundary_fades.clear()
	_environment_guidance_is_authored.clear()
	_environment_enclosure.clear()
	_environment_guided_propagation.clear()
	_guided_region_by_probe.clear()
	_guided_probes_by_region.clear()
	_guided_regions_dirty = true
	_environment_guided_wall_loss_db_per_m.clear()
	_environment_rt60_seconds.clear()
	_environment_reverb_send.clear()
	_environment_volume_m3.clear()
	_environment_room_size.clear()
	_environment_damping.clear()
	_environment_spread.clear()
	_environment_predelay_msec.clear()
	_environment_predelay_feedback.clear()
	_environment_hipass.clear()
	_pressure_confinement.clear()
	_pressure_body_gain_db.clear()
	_pressure_bass_boost_db.clear()
	_pressure_reflection_delay_seconds.clear()
	_pressure_reverb_send.clear()
	_pressure_decay_seconds.clear()
	_pressure_escape.clear()
	_pressure_escape_directions.clear()
	_pressure_escape_directionality.clear()
	_diffuse_region_by_probe.clear()
	_diffuse_region_volume_m3.clear()
	_diffuse_region_rt60_seconds.clear()
	_diffuse_region_strength.clear()
	_diffuse_region_critical_distance.clear()
	_diffuse_regions_dirty = true
	revision += 1


func add_probe(
	position: Vector3,
	probe_id: StringName = &"",
	environment_influence_radius := 0.0,
	guided_influence_center := Vector3(INF, INF, INF),
	guided_influence_half_extents := Vector3.ZERO,
	guided_influence_boundary_fade := 0.5,
	guided_spill_shape: Dictionary = {},
	attachment_exclusion_center := Vector3(INF, INF, INF),
	attachment_exclusion_half_extents := Vector3.ZERO,
	attachment_influence_center := Vector3(INF, INF, INF),
	attachment_influence_half_extents := Vector3.ZERO,
	attachment_influence_boundary_fade := 0.0
) -> int:
	if not position.is_finite():
		return -1
	var probe_index := _positions.size()
	_positions.append(position)
	_probe_ids.append(str(probe_id))
	_targets_by_probe.append(PackedInt32Array())
	_lengths_by_probe.append(PackedFloat32Array())
	_band_gains_by_probe.append(PackedVector3Array())
	_volume_db_by_probe.append(PackedFloat32Array())
	_delays_by_probe.append(PackedFloat32Array())
	_lowpass_by_probe.append(PackedFloat32Array())
	_highpass_by_probe.append(PackedFloat32Array())
	_resonance_by_probe.append(PackedFloat32Array())
	_reverb_by_probe.append(PackedFloat32Array())
	_guided_edges_by_probe.append(PackedByteArray())
	_modifier_indices_by_probe.append(PackedInt32Array())
	_diffuse_links_by_probe.append(PackedInt32Array())
	_environment_influence_radii.append(maxf(environment_influence_radius, 0.0))
	_environment_guided_centers.append(
		guided_influence_center if guided_influence_center.is_finite() else position
	)
	_environment_guided_half_extents.append(
		guided_influence_half_extents.abs()
		if guided_influence_half_extents.is_finite()
		else Vector3.ZERO
	)
	_environment_guided_boundary_fades.append(
		maxf(guided_influence_boundary_fade, 0.0)
	)
	var spill_origin := SafeVariant.vector3_strict_or(
		guided_spill_shape.get("origin"),
		position
	)
	var spill_axis := SafeVariant.vector3_strict_or(
		guided_spill_shape.get("axis"),
		Vector3.ZERO
	)
	spill_axis = (
		spill_axis.normalized()
		if not spill_axis.is_zero_approx()
		else Vector3.ZERO
	)
	var spill_lateral_axis := SafeVariant.vector3_strict_or(
		guided_spill_shape.get("lateral_axis"),
		Vector3.ZERO
	)
	spill_lateral_axis -= spill_axis * spill_lateral_axis.dot(spill_axis)
	if not spill_axis.is_zero_approx() and spill_lateral_axis.is_zero_approx():
		spill_lateral_axis = spill_axis.cross(Vector3.UP)
		if spill_lateral_axis.is_zero_approx():
			spill_lateral_axis = spill_axis.cross(Vector3.RIGHT)
	spill_lateral_axis = (
		spill_lateral_axis.normalized()
		if not spill_lateral_axis.is_zero_approx()
		else Vector3.ZERO
	)
	var spill_vertical_axis := (
		spill_axis.cross(spill_lateral_axis).normalized()
		if not spill_axis.is_zero_approx()
		and not spill_lateral_axis.is_zero_approx()
		else Vector3.ZERO
	)
	var spill_aperture := SafeVariant.vector2_strict_or(
		guided_spill_shape.get("aperture_half_extents"),
		Vector2.ZERO
	).abs()
	var spill_divergence := SafeVariant.vector2_strict_or(
		guided_spill_shape.get("divergence"),
		Vector2.ZERO
	)
	spill_divergence = Vector2(
		clampf(spill_divergence.x, 0.0, 4.0),
		clampf(spill_divergence.y, 0.0, 4.0)
	)
	var spill_falloff_distance := maxf(
		SafeVariant.finite_float_or(
			guided_spill_shape.get("falloff_distance"),
			OPEN_GUIDED_SPILL_FALLOFF_DISTANCE
		),
		0.01
	)
	var has_spill_lobe := (
		not spill_axis.is_zero_approx()
		and not spill_lateral_axis.is_zero_approx()
		and spill_aperture.x > 0.0
		and spill_aperture.y > 0.0
	)
	_environment_guided_spill_origins.append(spill_origin)
	_environment_guided_spill_axes.append(
		spill_axis if has_spill_lobe else Vector3.ZERO
	)
	_environment_guided_spill_lateral_axes.append(
		spill_lateral_axis if has_spill_lobe else Vector3.ZERO
	)
	_environment_guided_spill_vertical_axes.append(
		spill_vertical_axis if has_spill_lobe else Vector3.ZERO
	)
	_environment_guided_spill_apertures.append(
		spill_aperture if has_spill_lobe else Vector2.ZERO
	)
	_environment_guided_spill_divergences.append(
		spill_divergence if has_spill_lobe else Vector2.ZERO
	)
	_environment_guided_spill_falloff_distances.append(
		spill_falloff_distance
	)
	_attachment_exclusion_centers.append(
		attachment_exclusion_center
		if attachment_exclusion_center.is_finite()
		else position
	)
	_attachment_exclusion_half_extents.append(
		attachment_exclusion_half_extents.abs()
		if attachment_exclusion_half_extents.is_finite()
		else Vector3.ZERO
	)
	_attachment_influence_centers.append(
		attachment_influence_center
		if attachment_influence_center.is_finite()
		else position
	)
	_attachment_influence_half_extents.append(
		attachment_influence_half_extents.abs()
		if attachment_influence_half_extents.is_finite()
		else Vector3.ZERO
	)
	_attachment_influence_boundary_fades.append(
		maxf(attachment_influence_boundary_fade, 0.0)
	)
	_environment_guidance_is_authored.append(
		1
		if has_spill_lobe or not guided_influence_half_extents.is_zero_approx()
		else 0
	)
	_environment_enclosure.append(0.0)
	_environment_guided_propagation.append(0.0)
	_guided_region_by_probe.append(-1)
	_guided_regions_dirty = true
	_environment_guided_wall_loss_db_per_m.append(0.0)
	_environment_rt60_seconds.append(AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS)
	_environment_reverb_send.append(0.0)
	_environment_volume_m3.append(0.0)
	_environment_room_size.append(0.02)
	_environment_damping.append(0.05)
	_environment_spread.append(1.0)
	_environment_predelay_msec.append(1.0)
	_environment_predelay_feedback.append(0.0)
	_environment_hipass.append(0.0)
	_pressure_confinement.append(0.0)
	_pressure_body_gain_db.append(-10.5)
	_pressure_bass_boost_db.append(0.75)
	_pressure_reflection_delay_seconds.append(0.003)
	_pressure_reverb_send.append(0.0)
	_pressure_decay_seconds.append(
		AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
	)
	_pressure_escape.append(1.0)
	_pressure_escape_directions.append(Vector3.ZERO)
	_pressure_escape_directionality.append(0.0)
	_diffuse_region_by_probe.append(-1)
	_diffuse_regions_dirty = true
	revision += 1
	return probe_index


func set_probe_environment(probe_index: int, response: Dictionary) -> bool:
	if probe_index < 0 or probe_index >= probe_count():
		return false
	_environment_enclosure[probe_index] = clampf(
		SafeVariant.finite_float_or(response.get("enclosure"), 0.0),
		0.0,
		1.0
	)
	_environment_guided_propagation[probe_index] = clampf(
		SafeVariant.finite_float_or(response.get("guided_propagation"), 0.0),
		0.0,
		AcousticEnvironmentModel.MAX_GUIDED_PROPAGATION
	)
	_guided_regions_dirty = true
	_environment_guided_wall_loss_db_per_m[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("guided_wall_loss_db_per_m"),
			0.0
		),
		0.0,
		1.0
	)
	_environment_rt60_seconds[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("rt60_seconds"),
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
		),
		AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	_environment_reverb_send[probe_index] = clampf(
		SafeVariant.finite_float_or(response.get("reverb_send"), 0.0),
		0.0,
		1.0
	)
	_environment_volume_m3[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("effective_volume_m3"),
			125.0 if _environment_enclosure[probe_index] >= 0.5 else 0.0
		),
		0.0,
		1000000.0
	)
	_environment_room_size[probe_index] = _unit_response_value(
		response,
		"reverb_room_size",
		0.02
	)
	_environment_damping[probe_index] = _unit_response_value(
		response,
		"reverb_damping",
		0.05
	)
	_environment_spread[probe_index] = _unit_response_value(
		response,
		"reverb_spread",
		1.0
	)
	_environment_predelay_msec[probe_index] = clampf(
		SafeVariant.finite_float_or(response.get("reverb_predelay_msec"), 1.0),
		0.0,
		500.0
	)
	_environment_predelay_feedback[probe_index] = _unit_response_value(
		response,
		"reverb_predelay_feedback",
		0.0
	)
	_environment_hipass[probe_index] = _unit_response_value(
		response,
		"reverb_hipass",
		0.0
	)
	_pressure_confinement[probe_index] = _unit_response_value(
		response,
		"pressure_confinement",
		0.0
	)
	_pressure_body_gain_db[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("pressure_body_gain_db"),
			-10.5
		),
		-24.0,
		0.0
	)
	_pressure_bass_boost_db[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("pressure_bass_boost_db"),
			0.75
		),
		0.0,
		12.0
	)
	_pressure_reflection_delay_seconds[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("pressure_reflection_delay_seconds"),
			0.003
		),
		0.0,
		0.5
	)
	_pressure_reverb_send[probe_index] = _unit_response_value(
		response,
		"pressure_reverb_send",
		0.0
	)
	_pressure_decay_seconds[probe_index] = clampf(
		SafeVariant.finite_float_or(
			response.get("pressure_decay_seconds"),
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
		),
		AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	_pressure_escape[probe_index] = _unit_response_value(
		response,
		"pressure_escape",
		1.0
	)
	var escape_direction := SafeVariant.vector3_strict_or(
		response.get("pressure_escape_direction"),
		Vector3.ZERO
	)
	_pressure_escape_directions[probe_index] = (
		escape_direction.normalized()
		if not escape_direction.is_zero_approx()
		else Vector3.ZERO
	)
	_pressure_escape_directionality[probe_index] = _unit_response_value(
		response,
		"pressure_escape_directionality",
		0.0
	)
	_diffuse_regions_dirty = true
	return true


func environment_response(probe_index: int) -> Dictionary:
	if probe_index < 0 or probe_index >= probe_count():
		return AcousticEnvironmentModel.open_air_response()
	return {
		"enclosure": _environment_enclosure[probe_index],
		"guided_propagation": _environment_guided_propagation[probe_index],
		"guided_wall_loss_db_per_m": (
			_environment_guided_wall_loss_db_per_m[probe_index]
		),
		"rt60_seconds": _environment_rt60_seconds[probe_index],
		"reverb_send": _environment_reverb_send[probe_index],
		"effective_volume_m3": _environment_volume_m3[probe_index],
		"reverb_room_size": _environment_room_size[probe_index],
		"reverb_damping": _environment_damping[probe_index],
		"reverb_spread": _environment_spread[probe_index],
		"reverb_predelay_msec": _environment_predelay_msec[probe_index],
		"reverb_predelay_feedback": _environment_predelay_feedback[probe_index],
		"reverb_hipass": _environment_hipass[probe_index],
		"pressure_confinement": _pressure_confinement[probe_index],
		"pressure_body_gain_db": _pressure_body_gain_db[probe_index],
		"pressure_bass_boost_db": _pressure_bass_boost_db[probe_index],
		"pressure_reflection_delay_seconds": (
			_pressure_reflection_delay_seconds[probe_index]
		),
		"pressure_reverb_send": _pressure_reverb_send[probe_index],
		"pressure_decay_seconds": _pressure_decay_seconds[probe_index],
		"pressure_escape": _pressure_escape[probe_index],
		"pressure_escape_direction": _pressure_escape_directions[probe_index],
		"pressure_escape_directionality": (
			_pressure_escape_directionality[probe_index]
		),
	}


func connect_probes(
	probe_a: int,
	probe_b: int,
	modifier: AcousticPathModifier = null,
	bidirectional := true,
	carries_guided_energy := false
) -> bool:
	if (
		probe_a < 0
		or probe_b < 0
		or probe_a >= probe_count()
		or probe_b >= probe_count()
		or probe_a == probe_b
	):
		return false
	var safe_modifier := (
		modifier.sanitized_copy()
		if modifier != null
		else AcousticPathModifier.identity()
	)
	var modifier_index := _modifiers.size()
	_modifiers.append(safe_modifier)
	_append_edge(
		probe_a,
		probe_b,
		modifier_index,
		safe_modifier,
		carries_guided_energy
	)
	if bidirectional:
		_append_edge(
			probe_b,
			probe_a,
			modifier_index,
			safe_modifier,
			carries_guided_energy
		)
	_guided_regions_dirty = true
	_diffuse_regions_dirty = true
	revision += 1
	return true


func probes_can_share_guided_region(probe_a: int, probe_b: int) -> bool:
	if (
		probe_a < 0
		or probe_b < 0
		or probe_a >= probe_count()
		or probe_b >= probe_count()
	):
		return false
	return (
		_probe_can_own_guided_region(probe_a)
		and _probe_can_own_guided_region(probe_b)
		and _environment_enclosure[probe_a] >= 0.5
		and _environment_enclosure[probe_b] >= 0.5
	)


func probes_can_share_diffuse_region(probe_a: int, probe_b: int) -> bool:
	return (
		_probe_can_own_diffuse_region(probe_a)
		and _probe_can_own_diffuse_region(probe_b)
	)


func connect_diffuse_probes(probe_a: int, probe_b: int) -> bool:
	if (
		probe_a < 0
		or probe_b < 0
		or probe_a >= probe_count()
		or probe_b >= probe_count()
		or probe_a == probe_b
		or not probes_can_share_diffuse_region(probe_a, probe_b)
	):
		return false
	var links_a: PackedInt32Array = _diffuse_links_by_probe[probe_a]
	if not links_a.has(probe_b):
		links_a.append(probe_b)
		_diffuse_links_by_probe[probe_a] = links_a
	var links_b: PackedInt32Array = _diffuse_links_by_probe[probe_b]
	if not links_b.has(probe_a):
		links_b.append(probe_a)
		_diffuse_links_by_probe[probe_b] = links_b
	_diffuse_regions_dirty = true
	return true


func rebuild_guided_regions() -> void:
	var count := probe_count()
	_guided_region_by_probe.resize(count)
	_guided_region_by_probe.fill(-1)
	var parents := PackedInt32Array()
	parents.resize(count)
	for probe_index: int in range(count):
		parents[probe_index] = probe_index
	for probe_index: int in range(count):
		if not _probe_can_own_guided_region(probe_index):
			continue
		var targets: PackedInt32Array = _targets_by_probe[probe_index]
		var guided_edges: PackedByteArray = _guided_edges_by_probe[probe_index]
		for edge_index: int in range(targets.size()):
			if guided_edges[edge_index] == 0:
				continue
			var target_probe := targets[edge_index]
			if not _probe_can_own_guided_region(target_probe):
				continue
			var left_root := _guided_region_root(parents, probe_index)
			var right_root := _guided_region_root(parents, target_probe)
			if left_root != right_root:
				parents[right_root] = left_root
	var region_by_root: Dictionary[int, int] = {}
	var next_region := 0
	for probe_index: int in range(count):
		if not _probe_can_own_guided_region(probe_index):
			continue
		var root_probe := _guided_region_root(parents, probe_index)
		if not region_by_root.has(root_probe):
			region_by_root[root_probe] = next_region
			next_region += 1
		_guided_region_by_probe[probe_index] = region_by_root[root_probe]
	_guided_probes_by_region.clear()
	for _region_index: int in range(next_region):
		_guided_probes_by_region.append(PackedInt32Array())
	for probe_index: int in range(count):
		var region_index := _guided_region_by_probe[probe_index]
		if region_index < 0:
			continue
		_guided_probes_by_region[region_index].append(probe_index)
	_guided_regions_dirty = false


func guided_region_id(probe_index: int) -> int:
	_ensure_guided_regions()
	if probe_index < 0 or probe_index >= _guided_region_by_probe.size():
		return -1
	return _guided_region_by_probe[probe_index]


func rebuild_diffuse_regions() -> void:
	var count := probe_count()
	_diffuse_region_by_probe.resize(count)
	_diffuse_region_by_probe.fill(-1)
	var parents := PackedInt32Array()
	parents.resize(count)
	for probe_index: int in range(count):
		parents[probe_index] = probe_index
	for probe_index: int in range(count):
		if not _probe_can_own_diffuse_region(probe_index):
			continue
		for target_probe: int in _diffuse_links_by_probe[probe_index]:
			if not _probe_can_own_diffuse_region(target_probe):
				continue
			var left_root := _guided_region_root(parents, probe_index)
			var right_root := _guided_region_root(parents, target_probe)
			if left_root != right_root:
				parents[right_root] = left_root
		var targets: PackedInt32Array = _targets_by_probe[probe_index]
		for edge_index: int in range(targets.size()):
			var target_probe := targets[edge_index]
			if (
				not _probe_can_own_diffuse_region(target_probe)
				or not _edge_carries_same_diffuse_field(probe_index, edge_index)
			):
				continue
			var left_root := _guided_region_root(parents, probe_index)
			var right_root := _guided_region_root(parents, target_probe)
			if left_root != right_root:
				parents[right_root] = left_root

	var region_by_root: Dictionary[int, int] = {}
	var next_region := 0
	for probe_index: int in range(count):
		if not _probe_can_own_diffuse_region(probe_index):
			continue
		var root_probe := _guided_region_root(parents, probe_index)
		if not region_by_root.has(root_probe):
			region_by_root[root_probe] = next_region
			next_region += 1
		_diffuse_region_by_probe[probe_index] = region_by_root[root_probe]

	_diffuse_region_volume_m3.resize(next_region)
	_diffuse_region_volume_m3.fill(0.0)
	_diffuse_region_rt60_seconds.resize(next_region)
	_diffuse_region_rt60_seconds.fill(0.0)
	_diffuse_region_strength.resize(next_region)
	_diffuse_region_strength.fill(0.0)
	_diffuse_region_critical_distance.resize(next_region)
	_diffuse_region_critical_distance.fill(MIN_DIFFUSE_CRITICAL_DISTANCE)
	var region_weights := PackedFloat32Array()
	region_weights.resize(next_region)
	region_weights.fill(0.0)
	for probe_index: int in range(count):
		var region_index := _diffuse_region_by_probe[probe_index]
		if region_index < 0:
			continue
		var strength := (
			_environment_enclosure[probe_index]
			* _environment_reverb_send[probe_index]
		)
		var weight := maxf(strength, 0.01)
		region_weights[region_index] += weight
		_diffuse_region_volume_m3[region_index] += (
			_environment_volume_m3[probe_index] * weight
		)
		_diffuse_region_rt60_seconds[region_index] += (
			_environment_rt60_seconds[probe_index] * weight
		)
		_diffuse_region_strength[region_index] += strength * weight
	for region_index: int in range(next_region):
		var weight := maxf(region_weights[region_index], 0.000001)
		_diffuse_region_volume_m3[region_index] /= weight
		_diffuse_region_rt60_seconds[region_index] /= weight
		_diffuse_region_strength[region_index] /= weight
		_diffuse_region_critical_distance[region_index] = clampf(
			ROOM_CRITICAL_DISTANCE_SCALE * sqrt(
				maxf(_diffuse_region_volume_m3[region_index], 1.0)
				/ maxf(
					_diffuse_region_rt60_seconds[region_index],
					AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
				)
			),
			MIN_DIFFUSE_CRITICAL_DISTANCE,
			MAX_DIFFUSE_CRITICAL_DISTANCE
		)
	_diffuse_regions_dirty = false


func diffuse_region_id(probe_index: int) -> int:
	_ensure_diffuse_regions()
	if probe_index < 0 or probe_index >= _diffuse_region_by_probe.size():
		return -1
	return _diffuse_region_by_probe[probe_index]


func probe_count() -> int:
	return _positions.size()


func edge_count() -> int:
	var result := 0
	for targets: PackedInt32Array in _targets_by_probe:
		result += targets.size()
	return result


func export_bake_data() -> Dictionary:
	var probes: Array[Dictionary] = []
	probes.resize(probe_count())
	for probe_index: int in range(probe_count()):
		var spill_shape: Dictionary = {}
		if not _environment_guided_spill_axes[probe_index].is_zero_approx():
			spill_shape = {
				"origin": _environment_guided_spill_origins[probe_index],
				"axis": _environment_guided_spill_axes[probe_index],
				"lateral_axis": _environment_guided_spill_lateral_axes[probe_index],
				"aperture_half_extents": _environment_guided_spill_apertures[probe_index],
				"divergence": _environment_guided_spill_divergences[probe_index],
				"falloff_distance": _environment_guided_spill_falloff_distances[probe_index],
			}
		probes[probe_index] = {
			"position": _positions[probe_index],
			"id": _probe_ids[probe_index],
			"environment_influence_radius": _environment_influence_radii[probe_index],
			"guided_center": _environment_guided_centers[probe_index],
			"guided_half_extents": _environment_guided_half_extents[probe_index],
			"guided_boundary_fade": _environment_guided_boundary_fades[probe_index],
			"guided_spill_shape": spill_shape,
			"attachment_exclusion_center": _attachment_exclusion_centers[probe_index],
			"attachment_exclusion_half_extents": _attachment_exclusion_half_extents[probe_index],
			"attachment_influence_center": _attachment_influence_centers[probe_index],
			"attachment_influence_half_extents": _attachment_influence_half_extents[probe_index],
			"attachment_influence_boundary_fade": _attachment_influence_boundary_fades[probe_index],
			"environment": environment_response(probe_index),
		}
	var edges: Array[Dictionary] = []
	for from_probe: int in range(probe_count()):
		var targets: PackedInt32Array = _targets_by_probe[from_probe]
		var modifier_indices: PackedInt32Array = _modifier_indices_by_probe[from_probe]
		var guided_edges: PackedByteArray = _guided_edges_by_probe[from_probe]
		for edge_index: int in range(targets.size()):
			var modifier_index := modifier_indices[edge_index]
			if modifier_index < 0 or modifier_index >= _modifiers.size():
				continue
			edges.append({
				"from": from_probe,
				"to": targets[edge_index],
				"guided": guided_edges[edge_index] != 0,
				"modifier": _modifier_to_bake_data(_modifiers[modifier_index]),
			})
	var diffuse_links: Array[Vector2i] = []
	for probe_a: int in range(probe_count()):
		for probe_b: int in _diffuse_links_by_probe[probe_a]:
			if probe_b > probe_a:
				diffuse_links.append(Vector2i(probe_a, probe_b))
	return {
		"schema_version": BAKE_SCHEMA_VERSION,
		"probes": probes,
		"directed_edges": edges,
		"diffuse_links": diffuse_links,
	}


func import_bake_data(data: Dictionary) -> bool:
	if int(data.get("schema_version", -1)) != BAKE_SCHEMA_VERSION:
		return false
	var raw_probes: Variant = data.get("probes", null)
	var raw_edges: Variant = data.get("directed_edges", null)
	var raw_diffuse_links: Variant = data.get("diffuse_links", null)
	if (
		not raw_probes is Array
		or not raw_edges is Array
		or not raw_diffuse_links is Array
	):
		return false
	var probes := raw_probes as Array
	var edges := raw_edges as Array
	var diffuse_links := raw_diffuse_links as Array
	if (
		probes.size() > MAX_BAKED_PROBES
		or edges.size() > MAX_BAKED_DIRECTED_EDGES
		or diffuse_links.size() > MAX_BAKED_DIFFUSE_LINKS
	):
		return false
	clear()
	for raw_probe: Variant in probes:
		if not raw_probe is Dictionary:
			clear()
			return false
		var probe := raw_probe as Dictionary
		var position: Variant = probe.get("position", null)
		var guided_center: Variant = probe.get("guided_center", null)
		var guided_half_extents: Variant = probe.get("guided_half_extents", null)
		var spill_shape: Variant = probe.get("guided_spill_shape", {})
		var exclusion_center: Variant = probe.get("attachment_exclusion_center", null)
		var exclusion_half_extents: Variant = probe.get("attachment_exclusion_half_extents", null)
		var influence_center: Variant = probe.get("attachment_influence_center", null)
		var influence_half_extents: Variant = probe.get("attachment_influence_half_extents", null)
		var environment: Variant = probe.get("environment", null)
		if (
			not position is Vector3
			or not guided_center is Vector3
			or not guided_half_extents is Vector3
			or not spill_shape is Dictionary
			or not exclusion_center is Vector3
			or not exclusion_half_extents is Vector3
			or not influence_center is Vector3
			or not influence_half_extents is Vector3
			or not environment is Dictionary
		):
			clear()
			return false
		var probe_index := add_probe(
			position as Vector3,
			StringName(str(probe.get("id", ""))),
			float(probe.get("environment_influence_radius", 0.0)),
			guided_center as Vector3,
			guided_half_extents as Vector3,
			float(probe.get("guided_boundary_fade", 0.5)),
			spill_shape as Dictionary,
			exclusion_center as Vector3,
			exclusion_half_extents as Vector3,
			influence_center as Vector3,
			influence_half_extents as Vector3,
			float(probe.get("attachment_influence_boundary_fade", 0.0))
		)
		if probe_index < 0 or not set_probe_environment(
			probe_index,
			environment as Dictionary
		):
			clear()
			return false
	for raw_edge: Variant in edges:
		if not raw_edge is Dictionary:
			clear()
			return false
		var edge := raw_edge as Dictionary
		var from_probe := int(edge.get("from", -1))
		var to_probe := int(edge.get("to", -1))
		var modifier_data: Variant = edge.get("modifier", null)
		if not modifier_data is Dictionary:
			clear()
			return false
		var modifier := _modifier_from_bake_data(modifier_data as Dictionary)
		if (
			modifier == null
			or not connect_probes(
				from_probe,
				to_probe,
				modifier,
				false,
				bool(edge.get("guided", false))
			)
		):
			clear()
			return false
	for raw_link: Variant in diffuse_links:
		if not raw_link is Vector2i:
			clear()
			return false
		var link := raw_link as Vector2i
		if not connect_diffuse_probes(link.x, link.y):
			clear()
			return false
	rebuild_guided_regions()
	rebuild_diffuse_regions()
	return true


func get_probe_position(probe_index: int) -> Vector3:
	if probe_index < 0 or probe_index >= probe_count():
		return Vector3.ZERO
	return _positions[probe_index]


func get_probe_id(probe_index: int) -> StringName:
	if probe_index < 0 or probe_index >= probe_count():
		return &""
	return StringName(_probe_ids[probe_index])


## Allocating route inspection for tests and diagnostics only. Runtime propagation continues to
## use packed reusable field arrays and performs no per-edge Dictionary/Array allocation.
func debug_route(field: AcousticPropagationField, target_probe: int) -> Dictionary:
	if (
		field == null
		or target_probe < 0
		or target_probe >= probe_count()
		or target_probe >= field.predecessors.size()
	):
		return {}
	var probe_indices := PackedInt32Array()
	var probe_ids := PackedStringArray()
	var positions := PackedVector3Array()
	var modifier_ids := PackedStringArray()
	var current_probe := target_probe
	var remaining := probe_count()
	while current_probe >= 0 and remaining > 0:
		probe_indices.append(current_probe)
		probe_ids.append(_probe_ids[current_probe])
		positions.append(_positions[current_probe])
		var modifier_index := field.predecessor_modifiers[current_probe]
		if modifier_index >= 0 and modifier_index < _modifiers.size():
			modifier_ids.append(str(_modifiers[modifier_index].modifier_id))
		else:
			modifier_ids.append("")
		current_probe = field.predecessors[current_probe]
		remaining -= 1
	var deviation_count := 0
	var deviation_radians := 0.0
	var deviation_strength := 0.0
	for route_index: int in range(1, positions.size() - 1):
		var response := path_deviation_response(
			positions[route_index - 1],
			positions[route_index],
			positions[route_index + 1]
		)
		if not bool(response.get("active", false)):
			continue
		deviation_count += 1
		deviation_radians += float(response.get("angle_radians", 0.0))
		deviation_strength += float(response.get("strength", 0.0))
	var deviation_band_gain := _aggregate_path_deviation_band_gain(deviation_strength)
	return {
		"probe_indices": probe_indices,
		"probe_ids": probe_ids,
		"positions": positions,
		"edge_modifier_ids": modifier_ids,
		"deviation_count": deviation_count,
		"deviation_radians": deviation_radians,
		"deviation_strength": deviation_strength,
		"deviation_band_gain": deviation_band_gain,
		"terminated_at_seed": current_probe < 0,
	}


static func path_deviation_response(
	previous_position: Vector3,
	corner_position: Vector3,
	next_position: Vector3
) -> Dictionary:
	var angle := _path_deviation_angle(
		previous_position,
		corner_position,
		next_position
	)
	if angle < 0.0:
		return {"active": false, "angle_radians": 0.0, "band_gain": Vector3.ONE}
	if angle <= PATH_DEVIATION_DEAD_ZONE_RADIANS:
		return {"active": false, "angle_radians": angle, "band_gain": Vector3.ONE}
	var strength := _path_deviation_strength(angle)
	var attenuation_db := PATH_DEVIATION_MAX_ATTENUATION_DB * (
		1.0 - exp(-strength / PATH_DEVIATION_SATURATION_SCALE)
	)
	return {
		"active": true,
		"angle_radians": angle,
		"strength": strength,
		"attenuation_db": attenuation_db,
		"band_gain": Vector3(
			db_to_linear(-attenuation_db.x),
			db_to_linear(-attenuation_db.y),
			db_to_linear(-attenuation_db.z)
		),
	}


static func _path_deviation_angle(
	previous_position: Vector3,
	corner_position: Vector3,
	next_position: Vector3
) -> float:
	var incoming := corner_position - previous_position
	var outgoing := next_position - corner_position
	if (
		not incoming.is_finite()
		or not outgoing.is_finite()
		or incoming.length_squared() <= 0.000001
		or outgoing.length_squared() <= 0.000001
	):
		return -1.0
	return acos(clampf(
		incoming.normalized().dot(outgoing.normalized()),
		-1.0,
		1.0
	))


static func _path_deviation_strength(angle: float) -> float:
	if angle <= PATH_DEVIATION_DEAD_ZONE_RADIANS:
		return 0.0
	var normalized_deviation := clampf(
		(angle - PATH_DEVIATION_DEAD_ZONE_RADIANS)
		/ (PI - PATH_DEVIATION_DEAD_ZONE_RADIANS),
		0.0,
		1.0
	)
	return pow(normalized_deviation, PATH_DEVIATION_EXPONENT)


static func _aggregate_path_deviation_band_gain(strength: float) -> Vector3:
	if strength <= 0.0:
		return Vector3.ONE
	var saturation := 1.0 - exp(
		-maxf(strength, 0.0) / PATH_DEVIATION_SATURATION_SCALE
	)
	var attenuation_db := PATH_DEVIATION_MAX_ATTENUATION_DB * saturation
	return Vector3(
		db_to_linear(-attenuation_db.x),
		db_to_linear(-attenuation_db.y),
		db_to_linear(-attenuation_db.z)
	)


func probe_allows_attachment(probe_index: int, position: Vector3) -> bool:
	return probe_attachment_strength(probe_index, position) > 0.0001


func probe_attachment_strength(probe_index: int, position: Vector3) -> float:
	if probe_index < 0 or probe_index >= probe_count() or not position.is_finite():
		return 0.0
	var exclusion_half_extents := _attachment_exclusion_half_extents[probe_index]
	if not exclusion_half_extents.is_zero_approx():
		var exclusion_delta := (
			position - _attachment_exclusion_centers[probe_index]
		).abs()
		if (
			exclusion_delta.x <= exclusion_half_extents.x
			and exclusion_delta.y <= exclusion_half_extents.y
			and exclusion_delta.z <= exclusion_half_extents.z
		):
			return 0.0
	var influence_half_extents := _attachment_influence_half_extents[probe_index]
	if influence_half_extents.is_zero_approx():
		return 1.0
	var influence_delta := (
		position - _attachment_influence_centers[probe_index]
	).abs()
	var outside_distance := maxf(
		influence_delta.x - influence_half_extents.x,
		maxf(
			influence_delta.y - influence_half_extents.y,
			influence_delta.z - influence_half_extents.z
		)
	)
	if outside_distance <= 0.0:
		return 1.0
	var boundary_fade := _attachment_influence_boundary_fades[probe_index]
	if boundary_fade <= 0.0 or outside_distance >= boundary_fade:
		return 0.0
	return 1.0 - smoothstep(0.0, boundary_fade, outside_distance)


func find_nearest_probe(position: Vector3) -> int:
	if not position.is_finite() or _positions.is_empty():
		return -1
	var best_index := 0
	var best_distance_squared := position.distance_squared_to(_positions[0])
	for probe_index: int in range(1, _positions.size()):
		var distance_squared := position.distance_squared_to(
			_positions[probe_index]
		)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_index = probe_index
	return best_index


func find_nearest_probes(
	position: Vector3,
	maximum_results: int,
	result: PackedInt32Array
) -> int:
	var result_count := mini(maxi(maximum_results, 0), probe_count())
	if result.size() != result_count:
		result.resize(result_count)
	result.fill(-1)
	if not position.is_finite() or result_count <= 0:
		return 0
	# Fixed-size insertion keeps the reusable output sorted without allocating a candidate list.
	for probe_index: int in range(probe_count()):
		var distance_squared := position.distance_squared_to(_positions[probe_index])
		for result_index: int in range(result_count):
			var existing_probe := result[result_index]
			if (
				existing_probe >= 0
				and distance_squared
				>= position.distance_squared_to(_positions[existing_probe])
			):
				continue
			for shift_index: int in range(
				result_count - 1,
				result_index,
				-1
			):
				result[shift_index] = result[shift_index - 1]
			result[result_index] = probe_index
			break
	return result_count


func find_nearest_guided_region_probes(
	position: Vector3,
	maximum_results: int,
	result: PackedInt32Array,
	probes_per_region := 3
) -> int:
	_ensure_guided_regions()
	var result_capacity := maxi(maximum_results, 0)
	if result.size() != result_capacity:
		result.resize(result_capacity)
	result.fill(-1)
	if not position.is_finite() or result_capacity <= 0:
		return 0
	var result_count := 0
	# The regular nearest-N query describes local air. Preserve one nearest representative from
	# every waveguide as a separate, allocation-free set so a valid tunnel mouth cannot pop out of
	# consideration merely because a neighboring structure happens to contain many closer probes.
	# Keep a few representatives per region: its nearest interior sample can be hidden by the shell
	# while its mouth probe is legitimately visible.
	for region_probes: PackedInt32Array in _guided_probes_by_region:
		var region_result_start := result_count
		for _rank: int in range(maxi(probes_per_region, 1)):
			var nearest_probe := -1
			var nearest_distance_squared := INF
			for probe_index: int in region_probes:
				var already_selected := false
				for existing_index: int in range(
					region_result_start,
					result_count
				):
					if result[existing_index] == probe_index:
						already_selected = true
						break
				if already_selected:
					continue
				var distance_squared := position.distance_squared_to(
					_positions[probe_index]
				)
				if distance_squared < nearest_distance_squared:
					nearest_distance_squared = distance_squared
					nearest_probe = probe_index
			if nearest_probe < 0:
				break
			result[result_count] = nearest_probe
			result_count += 1
			if result_count >= result_capacity:
				return result_count
	return result_count


func _update_listener_environment_sample(
	field: AcousticPropagationField,
	listener_position: Vector3
) -> void:
	if (
		field.environment_sample_revision == revision
		and field.environment_sample_position.is_equal_approx(listener_position)
	):
		return
	field.environment_enclosure = 0.0
	field.environment_diffuse_strength = 0.0
	field.environment_guided_strength = 0.0
	field.environment_guided_wall_loss_db_per_m = 0.0
	field.environment_rt60_seconds = AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
	field.environment_reverb_send = 0.0
	field.environment_room_size = 0.02
	field.environment_damping = 0.05
	field.environment_spread = 1.0
	field.environment_predelay_msec = 1.0
	field.environment_predelay_feedback = 0.0
	field.environment_hipass = 0.0
	if not field.listener_probe_visibility_confirmed:
		field.environment_sample_position = listener_position
		field.environment_sample_revision = revision
		return

	var total_weight := 0.0
	var environment_coverage := 0.0
	var shape_weight := 0.0
	var guided_weight := 0.0
	var rt60_sum := 0.0
	var room_size_sum := 0.0
	var damping_sum := 0.0
	var spread_sum := 0.0
	var predelay_sum := 0.0
	var predelay_feedback_sum := 0.0
	var hipass_sum := 0.0
	for listener_probe_index: int in range(field.listener_probe_count):
		var local_environment_strength := clampf(
			field.listener_probe_strengths[listener_probe_index],
			0.0,
			1.0
		)
		# A weak aperture-visible probe is a legitimate alternate route, but barely describes
		# the listener's local room. A fourth-power coverage kernel makes that distinction
		# continuous: 24% visibility contributes 0.35%, while a genuinely local probe keeps its
		# full sampled environment.
		var local_environment_weight := pow(local_environment_strength, 4.0)
		if local_environment_weight <= 0.0001:
			continue
		var probe_index := field.listener_probes[listener_probe_index]
		if probe_index < 0 or probe_index >= probe_count():
			continue
		var distance_squared := listener_position.distance_squared_to(
			_positions[probe_index]
		)
		var proximity_weight := local_environment_weight / (
			distance_squared + LISTENER_PROBE_BLEND_REGULARIZATION_SQUARED
		)
		var environment_influence := _environment_influence(
			probe_index,
			listener_position
		)
		var effective_weight := proximity_weight * environment_influence
		environment_coverage = maxf(
			environment_coverage,
			environment_influence * local_environment_weight
		)
		var reverb_weight := (
			effective_weight * _environment_reverb_send[probe_index]
		)
		var guided_probe_strength := (
			_guided_environment_influence(probe_index, listener_position)
			* _environment_guided_propagation[probe_index]
		)
		var guided_probe_weight := proximity_weight * guided_probe_strength
		# Normalize by the same spatial support used by every environment numerator. Counting a
		# visible but out-of-influence probe only in the denominator creates false room-field holes:
		# the probe contributes no enclosure or reverb, yet used to dilute all valid local probes.
		total_weight += effective_weight
		shape_weight += reverb_weight
		guided_weight += guided_probe_weight
		field.environment_enclosure += (
			effective_weight * _environment_enclosure[probe_index]
		)
		field.environment_diffuse_strength += (
			effective_weight
			* _environment_enclosure[probe_index]
			* _environment_reverb_send[probe_index]
		)
		# A visible waveguide field is not diluted by unrelated open-air probes. Taking the
		# maximum of their already spatially-faded fields preserves tunnel-mouth energy while
		# remaining continuous as the listener moves.
		field.environment_guided_strength = maxf(
			field.environment_guided_strength,
			guided_probe_strength
		)
		field.environment_guided_wall_loss_db_per_m += (
			guided_probe_weight
			* _environment_guided_wall_loss_db_per_m[probe_index]
		)
		field.environment_reverb_send += (
			effective_weight * _environment_reverb_send[probe_index]
		)
		rt60_sum += reverb_weight * _environment_rt60_seconds[probe_index]
		room_size_sum += reverb_weight * _environment_room_size[probe_index]
		damping_sum += reverb_weight * _environment_damping[probe_index]
		spread_sum += reverb_weight * _environment_spread[probe_index]
		predelay_sum += reverb_weight * _environment_predelay_msec[probe_index]
		predelay_feedback_sum += (
			reverb_weight * _environment_predelay_feedback[probe_index]
		)
		hipass_sum += reverb_weight * _environment_hipass[probe_index]

	if total_weight > 0.000001:
		field.environment_enclosure /= total_weight
		field.environment_diffuse_strength /= total_weight
		field.environment_reverb_send /= total_weight
		# First normalize the response among probes that actually support this point, then fade that
		# local response by continuous coverage. Normalizing without coverage keeps one probe at full
		# strength until its exact outer boundary; using all zero-support probes in the denominator
		# instead creates holes above props. The strongest active support is a bounded union proxy:
		# overlapping cells remain full, while the outermost cell decays smoothly into open air.
		field.environment_enclosure *= environment_coverage
		field.environment_diffuse_strength *= environment_coverage
		field.environment_reverb_send *= environment_coverage
	if guided_weight > 0.000001:
		field.environment_guided_wall_loss_db_per_m /= guided_weight
	if shape_weight > 0.000001:
		field.environment_rt60_seconds = rt60_sum / shape_weight
		field.environment_room_size = room_size_sum / shape_weight
		field.environment_damping = damping_sum / shape_weight
		field.environment_spread = spread_sum / shape_weight
		field.environment_predelay_msec = predelay_sum / shape_weight
		field.environment_predelay_feedback = (
			predelay_feedback_sum / shape_weight
		)
		field.environment_hipass = hipass_sum / shape_weight
	field.environment_sample_position = listener_position
	field.environment_sample_revision = revision


func solve_from_position(
	listener_position: Vector3,
	field: AcousticPropagationField,
	listener_probes := PackedInt32Array(),
	listener_probe_count := -1,
	listener_probe_strengths := PackedFloat32Array()
) -> int:
	if field == null:
		return -1
	field.reset(probe_count())
	field.graph_revision = revision
	if probe_count() <= 0 or not listener_position.is_finite():
		return -1
	field.source_position = listener_position

	var requested_probe_count := (
		listener_probes.size()
		if listener_probe_count < 0
		else mini(listener_probe_count, listener_probes.size())
	)
	var initialized_count := 0
	var nearest_distance_squared := INF
	for listener_probe_index: int in range(requested_probe_count):
		var probe_index: int = listener_probes[listener_probe_index]
		if probe_index < 0 or probe_index >= probe_count():
			continue
		var distance_squared := listener_position.distance_squared_to(
			_positions[probe_index]
		)
		if distance_squared < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			field.source_probe = probe_index
		_initialize_listener_seed(
			probe_index,
			sqrt(distance_squared),
			field,
			(
				listener_probe_strengths[listener_probe_index]
				if listener_probe_index < listener_probe_strengths.size()
				else 1.0
			)
		)
		initialized_count += 1
	if initialized_count <= 0:
		var fallback_probe := find_nearest_probe(listener_position)
		field.source_probe = fallback_probe
		_initialize_listener_seed(
			fallback_probe,
			listener_position.distance_to(_positions[fallback_probe]),
			field
		)
	while not field.heap_is_empty():
		var current_probe := field.heap_pop_min()
		_relax_edges(current_probe, field)
	return field.source_probe


func sample_source(
	field: AcousticPropagationField,
	source_position: Vector3,
	max_distance: float,
	source_modifier: AcousticPathModifier = null,
	reference_distance := DEFAULT_REFERENCE_DISTANCE,
	live_listener_position := Vector3(INF, INF, INF),
	source_modifier_is_sanitized := false
) -> Dictionary:
	return sample_source_attached(
		field,
		source_position,
		PackedInt32Array(),
		0,
		max_distance,
		source_modifier,
		reference_distance,
		live_listener_position,
		source_modifier_is_sanitized,
		false
	)


func sample_source_attached(
	field: AcousticPropagationField,
	source_position: Vector3,
	source_probes: PackedInt32Array,
	source_probe_count: int,
	max_distance: float,
	source_modifier: AcousticPathModifier = null,
	reference_distance := DEFAULT_REFERENCE_DISTANCE,
	live_listener_position := Vector3(INF, INF, INF),
	source_modifier_is_sanitized := false,
	preserve_same_probe_detour := true
) -> Dictionary:
	if (
		field == null
		or field.graph_revision != revision
		or field.source_probe < 0
		or not source_position.is_finite()
	):
		return {"audible": false}
	var source_probe := _best_attached_source_probe(
		field,
		source_position,
		source_probes,
		source_probe_count
	)
	if source_probe < 0 or not is_finite(field.route_costs[source_probe]):
		return {"audible": false}

	var listener_position := (
		live_listener_position
		if live_listener_position.is_finite()
		else field.source_position
	)
	var direct_distance := listener_position.distance_to(source_position)
	var source_offset := source_position.distance_to(
		_positions[source_probe]
	)
	# The expensive graph route is cached, but the listener's short segment to its current probe is
	# cheap and must remain live. Using field.source_position here caused one-meter volume steps.
	var listener_origin_probe := field.origin_probes[source_probe]
	if listener_origin_probe < 0 or listener_origin_probe >= probe_count():
		return {"audible": false}
	var cached_listener_offset := field.source_position.distance_to(
		_positions[listener_origin_probe]
	)
	var live_listener_offset := listener_position.distance_to(
		_positions[listener_origin_probe]
	)
	var path_length := (
		field.path_lengths[source_probe]
		- cached_listener_offset
		+ live_listener_offset
		+ source_offset
	)
	var arrival_time := (
		field.arrival_times[source_probe]
		- cached_listener_offset / SPEED_OF_SOUND_METERS_PER_SECOND
		+ live_listener_offset / SPEED_OF_SOUND_METERS_PER_SECOND
		+ source_offset / SPEED_OF_SOUND_METERS_PER_SECOND
	)
	path_length = maxf(path_length, 0.0)
	arrival_time = maxf(arrival_time, 0.0)
	if (
		source_probe == listener_origin_probe
		and not preserve_same_probe_detour
	):
		path_length = direct_distance
		arrival_time = direct_distance / SPEED_OF_SOUND_METERS_PER_SECOND
	# With collision-validated attachments, both endpoints seeing the same probe describes a real
	# route through that air anchor. It must include both local segments instead of collapsing back
	# into a potentially blocked Euclidean centre ray.
	var endpoint_detour := path_length > direct_distance + 0.05
	var guided_path_length := clampf(
		field.guided_path_lengths[source_probe],
		0.0,
		path_length
	)
	if (
		source_probe != listener_origin_probe
		and _probe_can_own_guided_region(source_probe)
		and _guided_environment_influence(source_probe, source_position) > 0.0001
	):
		guided_path_length = minf(
			guided_path_length + source_offset,
			path_length
		)
	var range_path_length := (
		path_length
		- guided_path_length * (1.0 - GUIDED_PATH_DISTANCE_SCALE)
	)
	# Maximum hearing distance is a radial source bound, not a second loss charged for every bend.
	# The traveled route already pays geometric spreading, air absorption, materials and delay.
	# Applying the range tail to that route as well made a folded corridor abruptly die while an
	# equally distant outdoor listener remained eligible. Keep a shorter, conservative path only
	# for rare authored guides whose baked route is genuinely shorter than the endpoint distance.
	var range_gate_distance := minf(range_path_length, direct_distance)
	var safe_max_distance := maxf(max_distance, 0.0)
	if range_gate_distance > safe_max_distance:
		return {"audible": false}

	var modifier := (
		source_modifier
		if source_modifier != null and source_modifier_is_sanitized
		else (
			source_modifier.sanitized_copy()
			if source_modifier != null
			else AcousticPathModifier.identity()
		)
	)
	var band_gain: Vector3 = field.band_gains[source_probe]
	band_gain *= modifier.band_gain
	band_gain *= _air_absorption_gain(path_length)
	var geometric_spreading_db := _distance_volume_db(
		path_length,
		reference_distance
	)
	var range_fade_db := _range_fade_volume_db(
		range_gate_distance,
		safe_max_distance
	)
	var distance_volume_db := geometric_spreading_db + range_fade_db
	var apparent_position := _apparent_position(
		field,
		source_probe,
		source_position,
		direct_distance,
		listener_position,
		endpoint_detour
	)
	var modifier_ids := _collect_modifier_ids(
		field,
		source_probe,
		modifier.modifier_id
	)
	return {
		"audible": true,
		"source_probe_index": source_probe,
		"source_position": source_position,
		"listener_position": listener_position,
		"apparent_position": apparent_position,
		"direct_distance": direct_distance,
		"path_length": path_length,
		"guided_path_length": guided_path_length,
		"range_path_length": range_path_length,
		"range_gate_distance": range_gate_distance,
		"geometric_spreading_db": geometric_spreading_db,
		"range_fade_volume_db": range_fade_db,
		"reference_distance": maxf(reference_distance, 0.01),
		"unspread_volume_db": (
			field.volume_db[source_probe]
			+ modifier.volume_db
			+ range_fade_db
		),
		"travel_delay_seconds": (
			arrival_time + modifier.extra_delay_seconds
		),
		"volume_db": clampf(
			field.volume_db[source_probe]
			+ modifier.volume_db
			+ distance_volume_db,
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"band_gain": band_gain,
		"lowpass_hz": minf(
			field.lowpass_hz[source_probe],
			modifier.lowpass_hz
		),
		"highpass_hz": minf(
			maxf(
				field.highpass_hz[source_probe],
				modifier.highpass_hz
			),
			minf(field.lowpass_hz[source_probe], modifier.lowpass_hz)
		),
		"resonance": maxf(
			field.resonance[source_probe],
			modifier.resonance
		),
		"reverb_send": 1.0 - (
			(1.0 - field.reverb_send[source_probe])
			* (1.0 - modifier.reverb_send)
		),
		"modifier_ids": modifier_ids,
	}


func _best_attached_source_probe(
	field: AcousticPropagationField,
	source_position: Vector3,
	source_probes: PackedInt32Array,
	source_probe_count: int
) -> int:
	var safe_count := mini(
		maxi(source_probe_count, 0),
		source_probes.size()
	)
	if safe_count <= 0:
		return find_nearest_probe(source_position)
	var nearest_source_offset := INF
	for attachment_index: int in range(safe_count):
		var probe_index := source_probes[attachment_index]
		if probe_index < 0 or probe_index >= probe_count():
			continue
		nearest_source_offset = minf(
			nearest_source_offset,
			source_position.distance_to(_positions[probe_index])
		)
	var best_probe := -1
	var best_route_cost := INF
	for attachment_index: int in range(safe_count):
		var probe_index := source_probes[attachment_index]
		if (
			probe_index < 0
			or probe_index >= probe_count()
			or not is_finite(field.route_costs[probe_index])
		):
			continue
		var source_offset := source_position.distance_to(_positions[probe_index])
		# Multiple visible endpoints smooth a source crossing a real probe boundary. They must not
		# let a stationary emitter jump several metres into a different room merely because that
		# remote endpoint owns a cheaper listener route (and therefore a different diffuse field).
		if source_offset > (
			nearest_source_offset + SOURCE_ATTACHMENT_ROUTE_DISTANCE_SLACK
		):
			continue
		var path_length := field.path_lengths[probe_index] + source_offset
		var guided_path_length := field.guided_path_lengths[probe_index]
		if (
			_probe_can_own_guided_region(probe_index)
			and _guided_environment_influence(probe_index, source_position) > 0.0001
		):
			guided_path_length = minf(guided_path_length + source_offset, path_length)
		var route_cost := _route_signal_loss_db(
			path_length,
			guided_path_length,
			field.routing_band_gains[probe_index],
			field.volume_db[probe_index]
		)
		if route_cost >= best_route_cost:
			continue
		best_route_cost = route_cost
		best_probe = probe_index
	return best_probe


static func sample_free_field(
	listener_position: Vector3,
	source_position: Vector3,
	max_distance: float,
	source_modifier: AcousticPathModifier = null,
	reference_distance := DEFAULT_REFERENCE_DISTANCE,
	source_modifier_is_sanitized := false,
	range_path_length := -1.0,
	guided_path_length := 0.0
) -> Dictionary:
	if not listener_position.is_finite() or not source_position.is_finite():
		return {"audible": false}
	var path_length := listener_position.distance_to(source_position)
	var safe_range_path_length := (
		maxf(range_path_length, 0.0)
		if range_path_length >= 0.0
		else path_length
	)
	var safe_guided_path_length := clampf(
		guided_path_length,
		0.0,
		path_length
	)
	if safe_range_path_length > maxf(max_distance, 0.0):
		return {"audible": false}
	var modifier := (
		source_modifier
		if source_modifier != null and source_modifier_is_sanitized
		else (
			source_modifier.sanitized_copy()
			if source_modifier != null
			else AcousticPathModifier.identity()
		)
	)
	var geometric_spreading_db := _distance_volume_db(
		path_length,
		reference_distance
	)
	var range_fade_db := _range_fade_volume_db(
		safe_range_path_length,
		maxf(max_distance, 0.0)
	)
	var distance_volume_db := geometric_spreading_db + range_fade_db
	var modifier_ids := PackedStringArray()
	if not modifier.modifier_id.is_empty():
		modifier_ids.append(str(modifier.modifier_id))
	return {
		"audible": true,
		"source_position": source_position,
		"listener_position": listener_position,
		"apparent_position": source_position,
		"direct_distance": path_length,
		"path_length": path_length,
		"range_path_length": safe_range_path_length,
		"guided_path_length": safe_guided_path_length,
		"geometric_spreading_db": geometric_spreading_db,
		"range_fade_volume_db": range_fade_db,
		"reference_distance": maxf(reference_distance, 0.01),
		"unspread_volume_db": modifier.volume_db + range_fade_db,
		"travel_delay_seconds": (
			path_length / SPEED_OF_SOUND_METERS_PER_SECOND
			+ modifier.extra_delay_seconds
		),
		"volume_db": clampf(
			distance_volume_db + modifier.volume_db,
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"band_gain": (
			modifier.band_gain * _air_absorption_gain(path_length)
		),
		"lowpass_hz": modifier.lowpass_hz,
		"highpass_hz": modifier.highpass_hz,
		"resonance": modifier.resonance,
		"reverb_send": modifier.reverb_send,
		"modifier_ids": modifier_ids,
	}


func apply_environment_to_result(
	result: Dictionary,
	listener_position: Vector3,
	source_position: Vector3,
	listener_field: AcousticPropagationField = null,
	source_probe_override := -1,
	allow_diffuse_field := true
) -> void:
	if (
		not bool(result.get("audible", false))
		or probe_count() <= 0
		or not listener_position.is_finite()
		or not source_position.is_finite()
	):
		return
	var listener_probe := find_nearest_probe(listener_position)
	var source_probe := (
		source_probe_override
		if source_probe_override >= 0
		and source_probe_override < probe_count()
		else find_nearest_probe(source_position)
	)
	if listener_probe < 0 or source_probe < 0:
		return
	var listener_influence := _environment_influence(
		listener_probe,
		listener_position
	)
	var listener_enclosure := (
		_environment_enclosure[listener_probe] * listener_influence
	)
	var listener_diffuse_strength := (
		_environment_enclosure[listener_probe]
		* _environment_reverb_send[listener_probe]
		* listener_influence
	)
	var listener_guided_strength := (
		_environment_guided_propagation[listener_probe]
		* _guided_environment_influence(listener_probe, listener_position)
	)
	var listener_guided_wall_loss := (
		_environment_guided_wall_loss_db_per_m[listener_probe]
	)
	var listener_send := (
		_environment_reverb_send[listener_probe] * listener_influence
	)
	var listener_rt60 := (
		_environment_rt60_seconds[listener_probe] * listener_influence
	)
	var listener_room_size := _environment_room_size[listener_probe]
	var listener_damping := _environment_damping[listener_probe]
	var listener_spread := _environment_spread[listener_probe]
	var listener_predelay_msec := _environment_predelay_msec[listener_probe]
	var listener_predelay_feedback := (
		_environment_predelay_feedback[listener_probe]
	)
	var listener_hipass := _environment_hipass[listener_probe]
	if listener_field != null and listener_field.listener_probe_count > 0:
		_update_listener_environment_sample(listener_field, listener_position)
		listener_enclosure = listener_field.environment_enclosure
		listener_diffuse_strength = listener_field.environment_diffuse_strength
		listener_guided_strength = listener_field.environment_guided_strength
		listener_guided_wall_loss = (
			listener_field.environment_guided_wall_loss_db_per_m
		)
		listener_send = listener_field.environment_reverb_send
		listener_rt60 = listener_field.environment_rt60_seconds
		listener_room_size = listener_field.environment_room_size
		listener_damping = listener_field.environment_damping
		listener_spread = listener_field.environment_spread
		listener_predelay_msec = listener_field.environment_predelay_msec
		listener_predelay_feedback = (
			listener_field.environment_predelay_feedback
		)
		listener_hipass = listener_field.environment_hipass
	var source_environment_influence := _environment_influence(
		source_probe,
		source_position
	)
	var guided_source_influence := _guided_environment_influence(
		source_probe,
		source_position
	)
	var source_guided_strength := (
		_environment_guided_propagation[source_probe]
		* guided_source_influence
	)
	var guided_strength := _shared_guided_strength(
		listener_position,
		source_position,
		source_probe,
		listener_field,
		bool(result.get("direct_path_clear", false))
	)
	var path_length := maxf(
		SafeVariant.finite_float_or(result.get("path_length"), 0.0),
		0.0
	)
	var guided_path_length := clampf(
		SafeVariant.finite_float_or(result.get("guided_path_length"), 0.0),
		0.0,
		path_length
	)
	var route_guided_strength := 0.0
	if path_length > 0.0001 and guided_path_length > 0.0001:
		route_guided_strength = (
			source_guided_strength * guided_path_length / path_length
		)
		guided_strength = maxf(guided_strength, route_guided_strength)
	result["route_guided_strength"] = route_guided_strength
	var guided_weight_sum := listener_guided_strength + source_guided_strength
	var guided_wall_loss := 0.0
	if guided_weight_sum > 0.0001:
		guided_wall_loss = (
			listener_guided_wall_loss * listener_guided_strength
			+ _environment_guided_wall_loss_db_per_m[source_probe]
			* source_guided_strength
		) / guided_weight_sum
	_apply_guided_propagation(
		result,
		guided_strength,
		guided_wall_loss
		)
	var guided_recovery_ratio := clampf(
		SafeVariant.finite_float_or(
			result.get("guided_propagation_gain_db"),
			0.0
		) / MAX_GUIDED_RECOVERY_DB,
		0.0,
		1.0
	)
	_ensure_diffuse_regions()
	var source_diffuse_region := (
		_diffuse_region_by_probe[source_probe]
		if source_probe < _diffuse_region_by_probe.size()
		else -1
	)
	var listener_shares_diffuse_region := false
	if source_diffuse_region >= 0:
		if listener_field != null:
			if listener_field.listener_probe_visibility_confirmed:
				for listener_probe_index: int in range(listener_field.listener_probe_count):
					var field_probe := listener_field.listener_probes[listener_probe_index]
					if (
						field_probe >= 0
						and field_probe < _diffuse_region_by_probe.size()
						and _diffuse_region_by_probe[field_probe]
						== source_diffuse_region
					):
						listener_shares_diffuse_region = true
						break
		else:
			listener_shares_diffuse_region = (
				listener_probe < _diffuse_region_by_probe.size()
				and _diffuse_region_by_probe[listener_probe]
				== source_diffuse_region
			)
	var diffuse_field_support := 0.0
	var diffuse_critical_distance := MIN_DIFFUSE_CRITICAL_DISTANCE
	if listener_shares_diffuse_region and allow_diffuse_field:
		var shared_diffuse_strength := minf(
			listener_diffuse_strength,
			_environment_enclosure[source_probe]
			* _environment_reverb_send[source_probe]
			* source_environment_influence
		)
		var nominal_region_strength := maxf(
			_diffuse_region_strength[source_diffuse_region],
			0.0001
		)
		var support_ratio := clampf(
			shared_diffuse_strength / nominal_region_strength,
			0.0,
			1.0
		)
		var guided_diffuse_suppression := (
			1.0 - guided_recovery_ratio
		) * (1.0 - guided_recovery_ratio)
		diffuse_field_support = (
			support_ratio * support_ratio * (3.0 - 2.0 * support_ratio)
			* guided_diffuse_suppression
		)
		diffuse_critical_distance = (
			_diffuse_region_critical_distance[source_diffuse_region]
		)
	result["diffuse_field_region_id"] = source_diffuse_region
	result["diffuse_critical_distance"] = diffuse_critical_distance
	_apply_diffuse_field_support(
		result,
		diffuse_field_support,
		diffuse_critical_distance
	)
	var existing_send := clampf(
		SafeVariant.finite_float_or(result.get("reverb_send"), 0.0),
		0.0,
		1.0
	)
	# Late reverb normally belongs to the listener's space. A guided volume is the one
	# exception: its authored spill field describes a real opening through which the
	# source volume's decaying field can radiate. Squaring the open-air weight prevents
	# that source response from becoming the perceived room when the listener enters a
	# different enclosure.
	var guided_spill_weight := clampf(
		guided_strength / AcousticEnvironmentModel.MAX_GUIDED_PROPAGATION,
		0.0,
		1.0
	)
	var open_listener_weight := 1.0 - clampf(listener_enclosure, 0.0, 1.0)
	var source_reverb_spill_weight := (
		guided_spill_weight
		* open_listener_weight
		* open_listener_weight
	)
	var source_reverb_spill_send := clampf(
		_environment_reverb_send[source_probe]
		* source_environment_influence
		* source_reverb_spill_weight
		* SOURCE_REVERB_SPILL_SCALE,
		0.0,
		MAX_SOURCE_REVERB_SPILL_SEND
	)
	# A surface modifier may scatter an existing room response, but it cannot create a
	# diffuse field on its own in open air. This removes the false side-wall reverb that
	# used to be stronger than the actual tunnel mouth.
	var path_reverb_support := clampf(
		maxf(listener_enclosure, source_reverb_spill_weight),
		0.0,
		1.0
	)
	existing_send *= path_reverb_support
	result["source_reverb_spill_send"] = source_reverb_spill_send
	result["reverb_send"] = 1.0 - (
		(1.0 - existing_send)
		* (1.0 - listener_send)
		* (1.0 - source_reverb_spill_send)
	)
	if listener_send > 0.0001:
		result["reverb_room_size"] = listener_room_size
		result["reverb_damping"] = listener_damping
		result["reverb_spread"] = listener_spread
		result["reverb_predelay_msec"] = listener_predelay_msec
		result["reverb_predelay_feedback"] = listener_predelay_feedback
		result["reverb_hipass"] = listener_hipass
		result["reverb_decay_seconds"] = listener_rt60
	elif source_reverb_spill_send > 0.0001:
		result["reverb_room_size"] = _environment_room_size[source_probe]
		result["reverb_damping"] = _environment_damping[source_probe]
		result["reverb_spread"] = _environment_spread[source_probe]
		result["reverb_predelay_msec"] = _environment_predelay_msec[source_probe]
		result["reverb_predelay_feedback"] = (
			_environment_predelay_feedback[source_probe]
		)
		result["reverb_hipass"] = _environment_hipass[source_probe]
		result["reverb_decay_seconds"] = _environment_rt60_seconds[source_probe]
	else:
		_apply_default_reverb_shape(result)
	result["environment_enclosure"] = listener_enclosure


func create_pressure_emission(
	source_position: Vector3,
	pressure_strength: float,
	source_probe_override := -1
) -> Dictionary:
	var safe_strength := clampf(pressure_strength, 0.0, 1.0)
	if safe_strength <= 0.0001 or not source_position.is_finite():
		return {}
	var source_probe := (
		source_probe_override
		if source_probe_override >= 0
		and source_probe_override < probe_count()
		else find_nearest_probe(source_position)
	)
	if source_probe < 0 or source_probe >= probe_count():
		return _open_pressure_emission(safe_strength)
	var accumulator := {
		"weight": 0.0,
		"confinement": 0.0,
		"body_gain_db": 0.0,
		"bass_boost_db": 0.0,
		"reflection_delay_seconds": 0.0,
		"reverb_send": 0.0,
		"decay_seconds": 0.0,
		"escape": 0.0,
		"room_size": 0.0,
		"damping": 0.0,
		"spread": 0.0,
		"predelay_feedback": 0.0,
		"hipass": 0.0,
		"escape_direction_sum": Vector3.ZERO,
		"escape_directionality": 0.0,
	}
	_accumulate_pressure_probe(
		accumulator,
		source_probe,
		source_position,
		1.0
	)
	# Only directly connected air volumes may influence a source response. Edge transmission
	# suppresses samples across closed or massive portals, while open doorway probes can blend
	# smoothly as a muzzle crosses their boundary.
	for edge_index: int in range(_targets_by_probe[source_probe].size()):
		var target_probe := _targets_by_probe[source_probe][edge_index]
		var edge_band_gain := _band_gains_by_probe[source_probe][edge_index]
		var mean_transmission := (
			edge_band_gain.x + edge_band_gain.y + edge_band_gain.z
		) / 3.0
		var transmission_weight := clampf(
			mean_transmission
			* db_to_linear(_volume_db_by_probe[source_probe][edge_index]),
			0.0,
			1.0
		)
		if transmission_weight <= 0.001:
			continue
		_accumulate_pressure_probe(
			accumulator,
			target_probe,
			source_position,
			transmission_weight
		)
	var total_weight := float(accumulator.get("weight", 0.0))
	if total_weight <= 0.000001:
		var open_emission := _open_pressure_emission(safe_strength)
		open_emission["source_probe"] = source_probe
		return open_emission
	var escape_direction_sum: Vector3 = accumulator.get(
		"escape_direction_sum",
		Vector3.ZERO
	)
	return {
		"graph_revision": revision,
		"source_probe": source_probe,
		"strength": safe_strength,
		"confinement": float(accumulator["confinement"]) / total_weight,
		"body_gain_db": float(accumulator["body_gain_db"]) / total_weight,
		"bass_boost_db": float(accumulator["bass_boost_db"]) / total_weight,
		"reflection_delay_seconds": (
			float(accumulator["reflection_delay_seconds"]) / total_weight
		),
		"reverb_send": float(accumulator["reverb_send"]) / total_weight,
		"decay_seconds": float(accumulator["decay_seconds"]) / total_weight,
		"escape": float(accumulator["escape"]) / total_weight,
		"room_size": float(accumulator["room_size"]) / total_weight,
		"damping": float(accumulator["damping"]) / total_weight,
		"spread": float(accumulator["spread"]) / total_weight,
		"predelay_feedback": (
			float(accumulator["predelay_feedback"]) / total_weight
		),
		"hipass": float(accumulator["hipass"]) / total_weight,
		"escape_direction": (
			escape_direction_sum.normalized()
			if not escape_direction_sum.is_zero_approx()
			else Vector3.ZERO
		),
		"escape_directionality": clampf(
			float(accumulator["escape_directionality"]) / total_weight,
			0.0,
			1.0
		),
	}


func attach_pressure_arrivals(
	result: Dictionary,
	field: AcousticPropagationField,
	listener_position: Vector3,
	source_position: Vector3,
	max_distance: float,
	pressure_strength: float,
	reference_distance := DEFAULT_REFERENCE_DISTANCE,
	prepared_emission: Dictionary = {}
) -> void:
	var safe_strength := clampf(pressure_strength, 0.0, 1.0)
	if (
		safe_strength <= 0.0001
		or not bool(result.get("audible", false))
		or (field != null and field.graph_revision != revision)
		or not listener_position.is_finite()
		or not source_position.is_finite()
	):
		return
	var emission := prepared_emission
	if (
		emission.is_empty()
		or int(emission.get("graph_revision", -1)) != revision
	):
		emission = create_pressure_emission(
			source_position,
			safe_strength,
			int(result.get("source_probe_index", -1))
		)
	var source_probe := int(emission.get("source_probe", -1))
	if source_probe >= probe_count():
		return

	var confinement := clampf(float(emission.get("confinement", 0.0)), 0.0, 1.0)
	var body_gain_db := clampf(float(emission.get("body_gain_db", -10.5)), -24.0, 0.0)
	var bass_boost_db := clampf(float(emission.get("bass_boost_db", 0.75)), 0.0, 12.0)
	var reflection_delay_seconds := clampf(
		float(emission.get("reflection_delay_seconds", 0.003)),
		0.0,
		0.5
	)
	var strength_gain_db := 20.0 * log(maxf(safe_strength, MIN_GAIN)) / log(10.0)
	var parent_band_gain: Vector3 = result.get("band_gain", Vector3.ONE)
	var pressure_band_gain := _pressure_colored_band_gain(
		parent_band_gain,
		bass_boost_db,
		confinement
	)
	var body_lowpass_hz := minf(
		SafeVariant.finite_float_or(
			result.get("lowpass_hz"),
			AcousticPathModifier.MAX_FILTER_HZ
		),
		lerpf(10500.0, 4800.0, confinement)
	)
	var body_highpass_hz := minf(
		maxf(
			SafeVariant.finite_float_or(
				result.get("highpass_hz"),
				AcousticPathModifier.MIN_FILTER_HZ
			),
			AcousticPathModifier.MIN_FILTER_HZ
		),
		body_lowpass_hz
	)
	var arrivals: Array[Dictionary] = []
	var body_arrival := {
		"kind": 0,
		"apparent_position": SafeVariant.vector3_strict_or(
			result.get("apparent_position"),
			source_position
		),
		"path_length": maxf(
			SafeVariant.finite_float_or(result.get("path_length"), 0.0),
			0.0
		),
		"travel_delay_seconds": maxf(
			SafeVariant.finite_float_or(
				result.get("travel_delay_seconds"),
				0.0
			) + reflection_delay_seconds,
			0.0
		),
		"volume_db": clampf(
			SafeVariant.finite_float_or(result.get("volume_db"), 0.0)
			+ body_gain_db
			+ strength_gain_db,
			AcousticPathModifier.MIN_VOLUME_DB,
			AcousticPathModifier.MAX_VOLUME_DB
		),
		"band_gain": pressure_band_gain,
		"lowpass_hz": body_lowpass_hz,
		"highpass_hz": body_highpass_hz,
		"resonance": maxf(
			SafeVariant.finite_float_or(result.get("resonance"), 0.0),
			confinement * 0.18
		),
		"reverb_scale": 1.0,
	}
	arrivals.append(body_arrival)

	# A source probe's outgoing graph edges are a baked opening template. The shortest path is
	# already represented by the body arrival; independent neighboring routes become quiet,
	# physically delayed escape arrivals. This captures a blast leaving multiple doors without a
	# runtime K-shortest-path solve or any additional physics query.
	var alternate_candidates: Array[Dictionary] = []
	var pressure_escape := clampf(
		float(emission.get("escape", 1.0)),
		0.0,
		1.0
	)
	var pressure_escape_direction: Vector3 = emission.get(
		"escape_direction",
		Vector3.ZERO
	)
	var pressure_escape_directionality := clampf(
		float(emission.get("escape_directionality", 0.0)),
		0.0,
		1.0
	)
	if source_probe >= 0 and field != null:
		var primary_predecessor := field.predecessors[source_probe]
		for edge_index: int in range(_targets_by_probe[source_probe].size()):
			var target_probe := _targets_by_probe[source_probe][edge_index]
			if (
				target_probe == primary_predecessor
				or field.predecessors[target_probe] == source_probe
			):
				continue
			var candidate := _pressure_arrival_via_edge(
				result,
				field,
				listener_position,
				source_position,
				source_probe,
				edge_index,
				max_distance,
				reference_distance,
				body_gain_db + strength_gain_db,
				bass_boost_db,
				confinement,
				reflection_delay_seconds,
				pressure_escape,
				pressure_escape_direction,
				pressure_escape_directionality
			)
			if candidate.is_empty():
				continue
			_insert_pressure_candidate(
				alternate_candidates,
				candidate,
				MAX_PRESSURE_ARRIVALS - 1
			)
	for candidate: Dictionary in alternate_candidates:
		candidate.erase("score_db")
		arrivals.append(candidate)

	result["pressure_strength"] = safe_strength
	result["pressure_enclosure"] = confinement
	result["pressure_reverb_send"] = clampf(
		float(emission.get("reverb_send", 0.0)),
		0.0,
		1.0
	)
	result["pressure_reverb_room_size"] = clampf(
		float(emission.get("room_size", 0.02)),
		0.0,
		1.0
	)
	result["pressure_reverb_damping"] = clampf(
		float(emission.get("damping", 0.05)),
		0.0,
		1.0
	)
	result["pressure_reverb_spread"] = clampf(
		float(emission.get("spread", 1.0)),
		0.0,
		1.0
	)
	result["pressure_reverb_predelay_msec"] = (
		reflection_delay_seconds * 1000.0
	)
	result["pressure_reverb_predelay_feedback"] = clampf(
		float(emission.get("predelay_feedback", 0.0)),
		0.0,
		1.0
	)
	result["pressure_reverb_hipass"] = clampf(
		float(emission.get("hipass", 0.0)),
		0.0,
		1.0
	)
	result["pressure_decay_seconds"] = clampf(
		float(emission.get(
			"decay_seconds",
			AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
		)),
		AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	result["pressure_escape"] = clampf(
		float(emission.get("escape", 1.0)),
		0.0,
		1.0
	)
	result["pressure_arrivals"] = arrivals


func effective_hearing_distance(
	base_distance: float,
	listener_position: Vector3,
	source_position: Vector3,
	listener_field: AcousticPropagationField = null,
	direct_path_openness := 0.0,
	source_probe_override := -1
) -> float:
	var safe_base := maxf(base_distance, 0.0)
	if (
		safe_base <= 0.0
		or probe_count() <= 0
		or not listener_position.is_finite()
		or not source_position.is_finite()
	):
		return safe_base
	var source_probe := (
		source_probe_override
		if source_probe_override >= 0
		and source_probe_override < probe_count()
		else find_nearest_probe(source_position)
	)
	if source_probe < 0:
		return safe_base
	# Extended culling is valid only along one continuous guided route. A source sitting in a
	# tunnel must not extend its lifetime in every world direction, and two unrelated elongated
	# spaces (for example the tunnel and the test house) must not reinforce each other.
	var safe_path_openness := _direct_path_openness(direct_path_openness)
	var strength := _shared_guided_strength(
		listener_position,
		source_position,
		source_probe,
		listener_field,
		safe_path_openness > 0.0001
	) * safe_path_openness
	return safe_base * lerpf(1.0, MAX_GUIDED_RANGE_SCALE, strength)


func direct_range_path_length(
	listener_position: Vector3,
	source_position: Vector3,
	listener_field: AcousticPropagationField = null,
	direct_path_openness := 0.0,
	guided_path_length := -1.0,
	source_probe_override := -1
) -> float:
	if not listener_position.is_finite() or not source_position.is_finite():
		return INF
	var direct_distance := listener_position.distance_to(source_position)
	var safe_guided_path_length := (
		direct_guided_path_length(
			listener_position,
			source_position,
			listener_field,
			direct_path_openness,
			source_probe_override
		)
		if guided_path_length < 0.0
		else clampf(guided_path_length, 0.0, direct_distance)
	)
	return (
		direct_distance
		- safe_guided_path_length * (1.0 - GUIDED_PATH_DISTANCE_SCALE)
	)


func direct_guided_path_length(
	listener_position: Vector3,
	source_position: Vector3,
	listener_field: AcousticPropagationField = null,
	direct_path_openness := 0.0,
	source_probe_override := -1
) -> float:
	if not listener_position.is_finite() or not source_position.is_finite():
		return 0.0
	var direct_distance := listener_position.distance_to(source_position)
	if direct_distance <= 0.0001:
		return 0.0
	# Aperture coverage is continuous. Removing the whole preserved guide on the first blocked
	# sample made 6.7% wall coverage erase eight decibels at a tunnel lip. Preserve only the open
	# pressure share; a fully blocked transmitted path still receives no guided distance and the
	# separately sampled graph route carries energy around the real opening.
	var safe_path_openness := _direct_path_openness(direct_path_openness)
	if safe_path_openness <= 0.0001:
		return 0.0
	var source_probe := (
		source_probe_override
		if source_probe_override >= 0
		and source_probe_override < probe_count()
		else find_nearest_probe(source_position)
	)
	if source_probe < 0:
		return 0.0
	var guided_strength := _shared_guided_strength(
		listener_position,
		source_position,
		source_probe,
		listener_field,
		true
	)
	var normalized_strength := clampf(
		guided_strength / AcousticEnvironmentModel.MAX_GUIDED_PROPAGATION,
		0.0,
		1.0
	)
	if normalized_strength >= 0.95:
		return direct_distance * safe_path_openness

	# For a source in a guide and a listener outside it, measure the reusable path to the best
	# authored opening. This keeps direct and graph routes on the same distance budget: endpoint
	# spill strength alone otherwise collapses just before a house wall and jumps back after it.
	_ensure_guided_regions()
	var source_region := guided_region_id(source_probe)
	var best_total_path := INF
	var best_guided_path := 0.0
	if source_region >= 0 and source_region < _guided_probes_by_region.size():
		var listener_direction := (
			listener_position - source_position
		).normalized()
		for exit_probe: int in _guided_probes_by_region[source_region]:
			if (
				_environment_enclosure[exit_probe] > 0.1
				or _environment_guided_propagation[exit_probe] <= 0.0001
			):
				continue
			var source_to_exit := _positions[exit_probe] - source_position
			if source_to_exit.dot(listener_direction) <= 0.0:
				continue
			var source_to_exit_distance := source_to_exit.length()
			var total_path := (
				source_to_exit_distance
				+ _positions[exit_probe].distance_to(listener_position)
			)
			if total_path >= best_total_path:
				continue
			best_total_path = total_path
			best_guided_path = minf(source_to_exit_distance, direct_distance)
	if best_guided_path > 0.0001:
		return best_guided_path * safe_path_openness
	return direct_distance * normalized_strength * safe_path_openness


static func _direct_path_openness(value: Variant) -> float:
	if value is bool:
		return 1.0 if bool(value) else 0.0
	return clampf(SafeVariant.finite_float_or(value, 0.0), 0.0, 1.0)


func source_hearing_distance_upper_bound(
	base_distance: float,
	source_position: Vector3,
	source_probe_override := -1
) -> float:
	var safe_base := maxf(base_distance, 0.0)
	if safe_base <= 0.0 or not source_position.is_finite():
		return safe_base
	var source_probe := (
		source_probe_override
		if source_probe_override >= 0
		and source_probe_override < probe_count()
		else find_nearest_probe(source_position)
	)
	if source_probe < 0:
		return safe_base
	var source_strength := (
		_environment_guided_propagation[source_probe]
		* _guided_environment_influence(source_probe, source_position)
	)
	return safe_base * lerpf(
		1.0,
		1.0 / GUIDED_PATH_DISTANCE_SCALE,
		clampf(
			source_strength / AcousticEnvironmentModel.MAX_GUIDED_PROPAGATION,
			0.0,
			1.0
		)
	)


static func _apply_guided_propagation(
	result: Dictionary,
	guided_strength: float,
	wall_loss_db_per_m: float
) -> void:
	var safe_strength := clampf(
		guided_strength,
		0.0,
		AcousticEnvironmentModel.MAX_GUIDED_PROPAGATION
	)
	if safe_strength <= 0.0001:
		result["guided_propagation_gain_db"] = 0.0
		return
	var geometric_spreading_db := minf(
		SafeVariant.finite_float_or(result.get("geometric_spreading_db"), 0.0),
		0.0
	)
	var recoverable_loss_db := maxf(
		-geometric_spreading_db - UNGUIDED_NEAR_FIELD_LOSS_DB,
		0.0
	)
	var path_length := maxf(
		SafeVariant.finite_float_or(
			result.get(
				"guided_path_length",
				result.get("path_length", 0.0)
			),
			0.0
		),
		0.0
	)
	var wall_loss_db := (
		maxf(path_length - DEFAULT_REFERENCE_DISTANCE, 0.0)
		* maxf(wall_loss_db_per_m, 0.0)
	)
	var recovery_db := clampf(
		recoverable_loss_db
		* safe_strength
		* GUIDED_SPREADING_RECOVERY_SCALE
		- wall_loss_db,
		0.0,
		MAX_GUIDED_RECOVERY_DB
	)
	result["volume_db"] = clampf(
		SafeVariant.finite_float_or(result.get("volume_db"), 0.0) + recovery_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	result["guided_propagation_gain_db"] = recovery_db


static func _apply_diffuse_field_support(
	result: Dictionary,
	field_support: float,
	critical_distance: float = 1.0
) -> void:
	var safe_support := clampf(field_support, 0.0, 1.0)
	result["diffuse_field_support"] = safe_support
	if safe_support <= 0.000001:
		result["diffuse_field_gain_db"] = 0.0
		result["diffuse_field_level_db"] = AcousticPathModifier.MIN_VOLUME_DB
		result["diffuse_field_decay_db"] = 0.0
		return

	var direct_level_db := SafeVariant.finite_float_or(
		result.get("volume_db"),
		AcousticPathModifier.MIN_VOLUME_DB
	)
	var reference_distance := maxf(
		SafeVariant.finite_float_or(result.get("reference_distance"), 1.0),
		0.01
	)
	var safe_critical_distance := clampf(
		critical_distance,
		MIN_DIFFUSE_CRITICAL_DISTANCE,
		MAX_DIFFUSE_CRITICAL_DISTANCE
	)
	var direct_distance := maxf(
		SafeVariant.finite_float_or(result.get("direct_distance"), 0.0),
		0.0
	)
	# A late field still has to travel through connected air. Euclidean distance is correct in one
	# open room, but it is a physically impossible shortcut through maze partitions, a bent tunnel,
	# or multiple doorways. The baked route is never allowed to shorten the straight-line distance.
	var path_distance := maxf(
		SafeVariant.finite_float_or(
			result.get("path_length"),
			direct_distance
		),
		direct_distance
	)
	result["diffuse_field_path_distance"] = path_distance
	# Union-find room ownership is deliberately transitive so props cannot split a warehouse, but
	# connected air alone does not make a labyrinth one uniform pressure volume. Measure the actual
	# extra travel instead of a distance ratio: a small divider may have high relative tortuosity at
	# close range yet costs only a few metres, while chained openings add tens or hundreds of metres.
	var tortuosity := path_distance / maxf(
		direct_distance,
		safe_critical_distance
	)
	var detour_distance := maxf(path_distance - direct_distance, 0.0)
	var detour_scale := maxf(safe_critical_distance * 2.0, 12.0)
	var normalized_detour := detour_distance / detour_scale
	var normalized_detour_squared := normalized_detour * normalized_detour
	var detour_support := 1.0 / (
		1.0 + normalized_detour_squared * normalized_detour_squared
	)
	safe_support *= detour_support
	result["diffuse_field_tortuosity"] = tortuosity
	result["diffuse_field_detour_distance"] = detour_distance
	result["diffuse_field_detour_support"] = detour_support
	result["diffuse_field_support"] = safe_support
	if safe_support <= 0.000001:
		result["diffuse_field_gain_db"] = 0.0
		result["diffuse_field_level_db"] = AcousticPathModifier.MIN_VOLUME_DB
		result["diffuse_field_decay_db"] = 0.0
		return
	# Unlike the direct ray, this source baseline intentionally excludes endpoint occlusion. A
	# crate or short divider removes the direct wave but cannot remove energy already mixed through
	# the shared room. Structural separation is handled by diffuse-region membership above.
	var unspread_level_db := SafeVariant.finite_float_or(
		result.get("unspread_volume_db"),
		direct_level_db - SafeVariant.finite_float_or(
			result.get("geometric_spreading_db"),
			0.0
		)
	)
	var far_decay_db := (
		DIFFUSE_FAR_LOSS_DB_PER_DOUBLING
		* maxf(
			log(maxf(path_distance / safe_critical_distance, 1.0))
			/ log(2.0),
			0.0
		)
	)
	var diffuse_level_db := (
		unspread_level_db
		+ _distance_volume_db(safe_critical_distance, reference_distance)
		- far_decay_db
		+ 10.0 * log(maxf(safe_support, 0.000001)) / log(10.0)
	)
	# Sum relative power rather than converting both absolute levels. Besides being numerically
	# stable near the packet floor, this removes one exponential from every source/listener sample.
	var diffuse_to_direct_power := pow(
		10.0,
		(diffuse_level_db - direct_level_db) / 10.0
	)
	var recovery_db := 10.0 * log(
		1.0 + diffuse_to_direct_power
	) / log(10.0)
	result["diffuse_field_level_db"] = diffuse_level_db
	result["diffuse_field_decay_db"] = far_decay_db
	result["diffuse_field_gain_db"] = recovery_db
	result["volume_db"] = clampf(
		direct_level_db + recovery_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)


func _environment_influence(probe_index: int, position: Vector3) -> float:
	var radius := _environment_influence_radii[probe_index]
	if radius <= 0.0:
		return 1.0
	var distance := position.distance_to(_positions[probe_index])
	var fade_start := radius * 0.72
	if distance <= fade_start:
		return 1.0
	var fade := clampf(
		(distance - fade_start) / maxf(radius - fade_start, 0.01),
		0.0,
		1.0
	)
	return 1.0 - fade * fade * (3.0 - 2.0 * fade)


func _guided_environment_influence(probe_index: int, position: Vector3) -> float:
	# A guide opening radiates through an aperture. It is deliberately evaluated before the
	# probe's finite attachment radius: the radius chooses graph connections during the bake,
	# while this lobe describes the continuous field heard beyond the baked mouth.
	if not _environment_guided_spill_axes[probe_index].is_zero_approx():
		return _guided_spill_lobe_influence(probe_index, position)
	var radial_influence := _environment_influence(probe_index, position)
	if radial_influence <= 0.0:
		return 0.0
	# Open mouth probes describe radiation leaving a guide, not another lossless tunnel hundreds
	# of metres wide. Their influence therefore decays continuously with aperture distance while
	# enclosed guide probes retain their authored volume response.
	if (
		_environment_enclosure[probe_index] <= 0.1
		and _environment_guided_propagation[probe_index] > 0.0001
	):
		radial_influence *= 1.0 / (
			1.0
			+ position.distance_to(_positions[probe_index])
			/ OPEN_GUIDED_SPILL_FALLOFF_DISTANCE
		)
	var half_extents := _environment_guided_half_extents[probe_index]
	if half_extents.is_zero_approx():
		return radial_influence
	var local_delta := (position - _environment_guided_centers[probe_index]).abs()
	var outside_delta := Vector3(
		maxf(local_delta.x - half_extents.x, 0.0),
		maxf(local_delta.y - half_extents.y, 0.0),
		maxf(local_delta.z - half_extents.z, 0.0)
	)
	var outside_distance := outside_delta.length()
	# An enclosed guide remains strong beside its wall, but its mathematical box may still be
	# sampled by an opening-visible endpoint outside the shell. A half-amplitude boundary kernel
	# is continuous on both sides: it avoids the old full-to-zero pixel seam, preserves most of the
	# interior field, and fades the exterior diffraction share within a bounded 75 cm.
	if _environment_enclosure[probe_index] > 0.1:
		if outside_distance > 0.0:
			return radial_influence * 0.5 * (
				1.0 - smoothstep(
					0.0,
					ENCLOSED_GUIDED_BOUNDARY_BLEND_DISTANCE,
					outside_distance
				)
			)
		var enclosed_edge_margin := minf(
			half_extents.x - local_delta.x,
			minf(
				half_extents.y - local_delta.y,
				half_extents.z - local_delta.z
			)
		)
		return radial_influence * (
			0.5
			+ 0.5 * smoothstep(
				0.0,
				ENCLOSED_GUIDED_BOUNDARY_BLEND_DISTANCE,
				enclosed_edge_margin
			)
		)
	if outside_distance > 0.0:
		return 0.0
	var boundary_fade := _environment_guided_boundary_fades[probe_index]
	if boundary_fade <= 0.0:
		return radial_influence
	var edge_margin := minf(
		half_extents.x - local_delta.x,
		minf(
			half_extents.y - local_delta.y,
			half_extents.z - local_delta.z
		)
	)
	return radial_influence * smoothstep(0.0, boundary_fade, edge_margin)


func _guided_spill_lobe_influence(probe_index: int, position: Vector3) -> float:
	var axis := _environment_guided_spill_axes[probe_index]
	var delta := position - _environment_guided_spill_origins[probe_index]
	var axial_distance := delta.dot(axis)
	var aperture := _environment_guided_spill_apertures[probe_index]
	# Blend a short distance back into the opening. This prevents a mathematical seam at the
	# mouth without allowing the exterior lobe to become a second field inside the tunnel.
	var rear_transition := maxf(aperture.y * 0.35, 0.5)
	if axial_distance <= -rear_transition:
		return 0.0
	var forward_weight := (
		smoothstep(-rear_transition, 0.0, axial_distance)
		if axial_distance < 0.0
		else 1.0
	)
	var forward_distance := maxf(axial_distance, 0.0)
	var divergence := _environment_guided_spill_divergences[probe_index]
	var half_width := maxf(
		aperture.x + divergence.x * forward_distance,
		0.01
	)
	var half_height := maxf(
		aperture.y + divergence.y * forward_distance,
		0.01
	)
	var lateral_distance := absf(
		delta.dot(_environment_guided_spill_lateral_axes[probe_index])
	)
	var vertical_distance := absf(
		delta.dot(_environment_guided_spill_vertical_axes[probe_index])
	)
	var normalized_radius_squared := (
		(lateral_distance * lateral_distance) / (half_width * half_width)
		+ (vertical_distance * vertical_distance) / (half_height * half_height)
	)
	# A reciprocal fourth-order shoulder is half strength on the nominal cone and retains a
	# quiet diffraction tail outside it. Unlike a clamped cone or AABB, it has no audible edge.
	var lateral_weight := 1.0 / (
		1.0 + normalized_radius_squared * normalized_radius_squared
	)
	var falloff_distance := _environment_guided_spill_falloff_distances[probe_index]
	var axial_weight := 1.0 / (
		1.0 + forward_distance / maxf(falloff_distance, 0.01)
	)
	return forward_weight * lateral_weight * axial_weight


func _shared_guided_strength(
	listener_position: Vector3,
	source_position: Vector3,
	source_probe: int,
	listener_field: AcousticPropagationField,
	allow_spatial_fallback := false
) -> float:
	_ensure_guided_regions()
	if source_probe < 0 or source_probe >= _guided_region_by_probe.size():
		return 0.0
	var source_region := _guided_region_by_probe[source_probe]
	if source_region < 0:
		return 0.0
	var source_strength := (
		_environment_guided_propagation[source_probe]
		* _guided_environment_influence(source_probe, source_position)
	)
	if source_strength <= 0.0001:
		return 0.0

	var listener_strength := 0.0
	if (
		listener_field != null
		and listener_field.graph_revision == revision
		and listener_field.listener_probe_visibility_confirmed
	):
		for listener_probe_index: int in range(listener_field.listener_probe_count):
			var listener_probe := listener_field.listener_probes[listener_probe_index]
			if (
				listener_probe < 0
				or listener_probe >= _guided_region_by_probe.size()
				or _guided_region_by_probe[listener_probe] != source_region
			):
				continue
			listener_strength = maxf(
				listener_strength,
				_environment_guided_propagation[listener_probe]
				* _guided_environment_influence(listener_probe, listener_position)
			)
	else:
		var listener_probe := find_nearest_probe(listener_position)
		if (
			listener_probe >= 0
			and _guided_region_by_probe[listener_probe] == source_region
		):
			listener_strength = (
				_environment_guided_propagation[listener_probe]
				* _guided_environment_influence(listener_probe, listener_position)
			)
	if (
		allow_spatial_fallback
		and source_region < _guided_probes_by_region.size()
	):
		for listener_probe: int in _guided_probes_by_region[source_region]:
			listener_strength = maxf(
				listener_strength,
				_environment_guided_propagation[listener_probe]
				* _guided_environment_influence(listener_probe, listener_position)
			)
	return minf(listener_strength, source_strength)


func _ensure_guided_regions() -> void:
	if _guided_regions_dirty:
		rebuild_guided_regions()


func _ensure_diffuse_regions() -> void:
	if _diffuse_regions_dirty:
		rebuild_diffuse_regions()


func _probe_can_own_diffuse_region(probe_index: int) -> bool:
	return (
		probe_index >= 0
		and probe_index < probe_count()
		and _environment_enclosure[probe_index] >= MIN_DIFFUSE_REGION_ENCLOSURE
		and _environment_reverb_send[probe_index] >= MIN_DIFFUSE_REGION_REVERB_SEND
		and _environment_volume_m3[probe_index] > 0.0
	)


func _edge_carries_same_diffuse_field(
	probe_index: int,
	edge_index: int
) -> bool:
	var band_gain := _band_gains_by_probe[probe_index][edge_index]
	return (
		minf(band_gain.x, minf(band_gain.y, band_gain.z))
		>= MIN_DIFFUSE_EDGE_BAND_GAIN
		and _volume_db_by_probe[probe_index][edge_index]
		>= MIN_DIFFUSE_EDGE_VOLUME_DB
	)


func _probe_can_own_guided_region(probe_index: int) -> bool:
	return (
		probe_index >= 0
		and probe_index < probe_count()
		and _environment_guidance_is_authored[probe_index] != 0
		and _environment_guided_propagation[probe_index] > 0.0001
	)


static func _guided_region_root(
	parents: PackedInt32Array,
	probe_index: int
) -> int:
	var root_probe := probe_index
	while parents[root_probe] != root_probe:
		root_probe = parents[root_probe]
	return root_probe


static func _apply_default_reverb_shape(result: Dictionary) -> void:
	result["reverb_room_size"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_room_size"), 0.35),
		0.0,
		1.0
	)
	result["reverb_damping"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_damping"), 0.5),
		0.0,
		1.0
	)
	result["reverb_spread"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_spread"), 0.9),
		0.0,
		1.0
	)
	result["reverb_predelay_msec"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_predelay_msec"), 8.0),
		0.0,
		500.0
	)
	result["reverb_predelay_feedback"] = clampf(
		SafeVariant.finite_float_or(
			result.get("reverb_predelay_feedback"),
			0.25
		),
		0.0,
		1.0
	)
	result["reverb_hipass"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_hipass"), 0.05),
		0.0,
		1.0
	)
	result["reverb_decay_seconds"] = clampf(
		SafeVariant.finite_float_or(result.get("reverb_decay_seconds"), 0.25),
		0.0,
		AcousticEnvironmentModel.MAX_REVERB_TIME_SECONDS
	)
	result["environment_enclosure"] = clampf(
		SafeVariant.finite_float_or(result.get("environment_enclosure"), 0.0),
		0.0,
		1.0
	)


static func apply_modifier_to_result(
	result: Dictionary,
	modifier: AcousticPathModifier,
	modifier_is_sanitized := false
) -> void:
	if not bool(result.get("audible", false)) or modifier == null:
		return
	var safe_modifier := (
		modifier
		if modifier_is_sanitized
		else modifier.sanitized_copy()
	)
	result["band_gain"] = (
		result.get("band_gain", Vector3.ONE) as Vector3
	) * safe_modifier.band_gain
	result["travel_delay_seconds"] = float(
		result.get("travel_delay_seconds", 0.0)
	) + safe_modifier.extra_delay_seconds
	result["volume_db"] = clampf(
		float(result.get("volume_db", 0.0)) + safe_modifier.volume_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	result["lowpass_hz"] = minf(
		float(result.get("lowpass_hz", AcousticPathModifier.MAX_FILTER_HZ)),
		safe_modifier.lowpass_hz
	)
	result["highpass_hz"] = minf(
		maxf(
			float(result.get("highpass_hz", AcousticPathModifier.MIN_FILTER_HZ)),
			safe_modifier.highpass_hz
		),
		float(result["lowpass_hz"])
	)
	result["resonance"] = maxf(
		float(result.get("resonance", 0.0)),
		safe_modifier.resonance
	)
	result["reverb_send"] = 1.0 - (
		(1.0 - float(result.get("reverb_send", 0.0)))
		* (1.0 - safe_modifier.reverb_send)
	)
	var modifier_ids: PackedStringArray = result.get(
		"modifier_ids",
		PackedStringArray()
	)
	if (
		not safe_modifier.modifier_id.is_empty()
		and not modifier_ids.has(str(safe_modifier.modifier_id))
	):
		modifier_ids.append(str(safe_modifier.modifier_id))
	result["modifier_ids"] = modifier_ids


static func apply_partial_modifier_to_result(
	result: Dictionary,
	modifier: AcousticPathModifier,
	occlusion: float,
	modifier_is_sanitized := false
) -> void:
	if not bool(result.get("audible", false)) or modifier == null:
		return
	var safe_occlusion := clampf(occlusion, 0.0, 1.0)
	if safe_occlusion <= 0.0001:
		return
	var safe_modifier := (
		modifier
		if modifier_is_sanitized
		else modifier.sanitized_copy()
	)
	# Use this identical amplitude/band decomposition through 100 percent. The previous full-hit
	# shortcut encoded the same nominal material partly in volume at 99.9 percent and entirely in
	# EQ at 100 percent. That is not perceptually equivalent for coloured content and produced a
	# hard, song-dependent level step at wall edges.
	var clear_weight := 1.0 - safe_occlusion
	var transmitted_amplitude := db_to_linear(safe_modifier.volume_db)
	var transmitted_bands := safe_modifier.band_gain * transmitted_amplitude
	var mixed_bands := Vector3(
		clear_weight + safe_occlusion * transmitted_bands.x,
		clear_weight + safe_occlusion * transmitted_bands.y,
		clear_weight + safe_occlusion * transmitted_bands.z
	)
	var broadband_amplitude := maxf(
		(mixed_bands.x + mixed_bands.y + mixed_bands.z) / 3.0,
		MIN_GAIN
	)
	result["band_gain"] = (
		result.get("band_gain", Vector3.ONE) as Vector3
	) * (mixed_bands / broadband_amplitude)
	result["volume_db"] = clampf(
		float(result.get("volume_db", 0.0))
		+ linear_to_db(broadband_amplitude),
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	result["travel_delay_seconds"] = float(
		result.get("travel_delay_seconds", 0.0)
	) + safe_modifier.extra_delay_seconds * safe_occlusion
	var filter_weight := safe_occlusion * safe_occlusion
	var partial_lowpass := exp(lerpf(
		log(AcousticPathModifier.MAX_FILTER_HZ),
		log(maxf(safe_modifier.lowpass_hz, AcousticPathModifier.MIN_FILTER_HZ)),
		filter_weight
	))
	var partial_highpass := exp(lerpf(
		log(AcousticPathModifier.MIN_FILTER_HZ),
		log(maxf(safe_modifier.highpass_hz, AcousticPathModifier.MIN_FILTER_HZ)),
		filter_weight
	))
	result["lowpass_hz"] = minf(
		float(result.get("lowpass_hz", AcousticPathModifier.MAX_FILTER_HZ)),
		partial_lowpass
	)
	result["highpass_hz"] = minf(
		maxf(
			float(result.get("highpass_hz", AcousticPathModifier.MIN_FILTER_HZ)),
			partial_highpass
		),
		float(result["lowpass_hz"])
	)
	result["resonance"] = maxf(
		float(result.get("resonance", 0.0)),
		safe_modifier.resonance * safe_occlusion
	)
	result["reverb_send"] = 1.0 - (
		(1.0 - float(result.get("reverb_send", 0.0)))
		* (1.0 - safe_modifier.reverb_send * safe_occlusion)
	)
	var modifier_ids: PackedStringArray = result.get(
		"modifier_ids",
		PackedStringArray()
	)
	if (
		not safe_modifier.modifier_id.is_empty()
		and not modifier_ids.has(str(safe_modifier.modifier_id))
	):
		modifier_ids.append(str(safe_modifier.modifier_id))
	result["modifier_ids"] = modifier_ids
	result["direct_occlusion"] = safe_occlusion


func _append_edge(
	from_probe: int,
	to_probe: int,
	modifier_index: int,
	modifier: AcousticPathModifier,
	carries_guided_energy: bool
) -> void:
	var targets := _targets_by_probe[from_probe]
	var lengths := _lengths_by_probe[from_probe]
	var band_gains := _band_gains_by_probe[from_probe]
	var volumes := _volume_db_by_probe[from_probe]
	var delays := _delays_by_probe[from_probe]
	var lowpasses := _lowpass_by_probe[from_probe]
	var highpasses := _highpass_by_probe[from_probe]
	var resonances := _resonance_by_probe[from_probe]
	var reverbs := _reverb_by_probe[from_probe]
	var guided_edges := _guided_edges_by_probe[from_probe]
	var modifier_indices := _modifier_indices_by_probe[from_probe]
	targets.append(to_probe)
	lengths.append(_positions[from_probe].distance_to(_positions[to_probe]))
	band_gains.append(modifier.band_gain)
	volumes.append(modifier.volume_db)
	delays.append(modifier.extra_delay_seconds)
	lowpasses.append(modifier.lowpass_hz)
	highpasses.append(modifier.highpass_hz)
	resonances.append(modifier.resonance)
	reverbs.append(modifier.reverb_send)
	guided_edges.append(1 if carries_guided_energy else 0)
	modifier_indices.append(modifier_index)
	_targets_by_probe[from_probe] = targets
	_lengths_by_probe[from_probe] = lengths
	_band_gains_by_probe[from_probe] = band_gains
	_volume_db_by_probe[from_probe] = volumes
	_delays_by_probe[from_probe] = delays
	_lowpass_by_probe[from_probe] = lowpasses
	_highpass_by_probe[from_probe] = highpasses
	_resonance_by_probe[from_probe] = resonances
	_reverb_by_probe[from_probe] = reverbs
	_guided_edges_by_probe[from_probe] = guided_edges
	_modifier_indices_by_probe[from_probe] = modifier_indices


func _relax_edges(current_probe: int, field: AcousticPropagationField) -> void:
	var targets: PackedInt32Array = _targets_by_probe[current_probe]
	var lengths: PackedFloat32Array = _lengths_by_probe[current_probe]
	var edge_band_gains: PackedVector3Array = (
		_band_gains_by_probe[current_probe]
	)
	var edge_volumes: PackedFloat32Array = _volume_db_by_probe[current_probe]
	var edge_delays: PackedFloat32Array = _delays_by_probe[current_probe]
	var edge_lowpasses: PackedFloat32Array = _lowpass_by_probe[current_probe]
	var edge_highpasses: PackedFloat32Array = _highpass_by_probe[current_probe]
	var edge_resonances: PackedFloat32Array = _resonance_by_probe[current_probe]
	var edge_reverbs: PackedFloat32Array = _reverb_by_probe[current_probe]
	var guided_edges: PackedByteArray = _guided_edges_by_probe[current_probe]
	var modifier_indices: PackedInt32Array = (
		_modifier_indices_by_probe[current_probe]
	)
	for edge_index: int in range(targets.size()):
		var target_probe := targets[edge_index]
		var edge_length := lengths[edge_index]
		var candidate_path_length := field.path_lengths[current_probe] + edge_length
		var candidate_guided_path_length := (
			field.guided_path_lengths[current_probe]
			+ (edge_length if guided_edges[edge_index] != 0 else 0.0)
		)
		var candidate_routing_band_gain := (
			field.routing_band_gains[current_probe] * edge_band_gains[edge_index]
		)
		var candidate_deviation_strength := field.path_deviation_strengths[current_probe]
		var previous_probe := field.predecessors[current_probe]
		if previous_probe >= 0 and target_probe != previous_probe:
			# Finite-edge diffraction is frequency dependent: low frequencies bend around a
			# corner more readily than highs. This response is derived only from the baked route
			# geometry, so authored portals, auto-connected probes, and imported levels all share
			# one rule. Straight probe chains remain bit-for-bit neutral.
			var deviation_angle := _path_deviation_angle(
				_positions[previous_probe],
				_positions[current_probe],
				_positions[target_probe]
			)
			candidate_deviation_strength += _path_deviation_strength(deviation_angle)
		var candidate_band_gain := (
			candidate_routing_band_gain
			* _aggregate_path_deviation_band_gain(candidate_deviation_strength)
		)
		var candidate_volume_db := (
			field.volume_db[current_probe] + edge_volumes[edge_index]
		)
		# The rendered wave is dominated by the strongest useful arrival, not necessarily the first.
		# Compare the same cumulative spreading and material amplitude later rendered by sample_source.
		# The previous seconds-plus-arbitrary-dB metric could prefer a quiet wall shortcut over a much
		# stronger corridor route. Arrival time remains physical and independent below.
		var route_cost := _route_signal_loss_db(
			candidate_path_length,
			candidate_guided_path_length,
			candidate_routing_band_gain,
			candidate_volume_db
		)
		if route_cost >= field.route_costs[target_probe]:
			continue
		field.route_costs[target_probe] = route_cost
		field.arrival_times[target_probe] = (
			field.arrival_times[current_probe]
			+ edge_length / SPEED_OF_SOUND_METERS_PER_SECOND
			+ edge_delays[edge_index]
		)
		field.path_lengths[target_probe] = candidate_path_length
		field.guided_path_lengths[target_probe] = candidate_guided_path_length
		field.routing_band_gains[target_probe] = candidate_routing_band_gain
		field.path_deviation_strengths[target_probe] = candidate_deviation_strength
		field.band_gains[target_probe] = candidate_band_gain
		field.volume_db[target_probe] = candidate_volume_db
		field.lowpass_hz[target_probe] = minf(
			field.lowpass_hz[current_probe],
			edge_lowpasses[edge_index]
		)
		field.highpass_hz[target_probe] = minf(
			maxf(
				field.highpass_hz[current_probe],
				edge_highpasses[edge_index]
			),
			field.lowpass_hz[target_probe]
		)
		field.resonance[target_probe] = maxf(
			field.resonance[current_probe],
			edge_resonances[edge_index]
		)
		field.reverb_send[target_probe] = 1.0 - (
			(1.0 - field.reverb_send[current_probe])
			* (1.0 - edge_reverbs[edge_index])
		)
		field.predecessors[target_probe] = current_probe
		field.predecessor_modifiers[target_probe] = (
			modifier_indices[edge_index]
		)
		field.origin_probes[target_probe] = field.origin_probes[current_probe]
		field.first_hops[target_probe] = (
			target_probe
			if current_probe == field.origin_probes[current_probe]
			else field.first_hops[current_probe]
		)
		field.heap_push_or_decrease(target_probe, route_cost)


func _initialize_listener_seed(
	probe_index: int,
	listener_offset: float,
	field: AcousticPropagationField,
	attachment_strength := 1.0
) -> void:
	var safe_strength := clampf(attachment_strength, MIN_GAIN, 1.0)
	var attachment_volume_db := linear_to_db(safe_strength)
	var route_cost := _route_signal_loss_db(
		listener_offset,
		0.0,
		Vector3.ONE,
		attachment_volume_db
	)
	if route_cost >= field.route_costs[probe_index]:
		return
	field.route_costs[probe_index] = route_cost
	field.arrival_times[probe_index] = (
		listener_offset / SPEED_OF_SOUND_METERS_PER_SECOND
	)
	field.path_lengths[probe_index] = listener_offset
	field.guided_path_lengths[probe_index] = 0.0
	field.routing_band_gains[probe_index] = Vector3.ONE
	field.path_deviation_strengths[probe_index] = 0.0
	field.band_gains[probe_index] = Vector3.ONE
	field.volume_db[probe_index] = attachment_volume_db
	field.lowpass_hz[probe_index] = AcousticPathModifier.MAX_FILTER_HZ
	field.highpass_hz[probe_index] = AcousticPathModifier.MIN_FILTER_HZ
	field.resonance[probe_index] = 0.0
	field.reverb_send[probe_index] = 0.0
	field.predecessors[probe_index] = -1
	field.predecessor_modifiers[probe_index] = -1
	field.first_hops[probe_index] = probe_index
	field.origin_probes[probe_index] = probe_index
	field.heap_push_or_decrease(probe_index, route_cost)


func _apparent_position(
	field: AcousticPropagationField,
	source_probe: int,
	actual_source_position: Vector3,
	direct_distance: float,
	listener_position: Vector3,
	force_probe_direction := false
) -> Vector3:
	if (
		source_probe == field.origin_probes[source_probe]
		and not force_probe_direction
	):
		return actual_source_position
	var first_hop := field.first_hops[source_probe]
	if force_probe_direction and source_probe == field.origin_probes[source_probe]:
		first_hop = source_probe
	if first_hop < 0 or first_hop >= probe_count():
		return actual_source_position
	var apparent_direction := (
		_positions[first_hop] - listener_position
	)
	if apparent_direction.length_squared() <= 0.000001:
		apparent_direction = actual_source_position - listener_position
	if apparent_direction.length_squared() <= 0.000001:
		return actual_source_position
	return (
		listener_position
		+ apparent_direction.normalized()
		* minf(maxf(direct_distance, 1.0), APPARENT_SOURCE_DISTANCE)
	)


static func _distance_volume_db(path_length: float, reference_distance: float) -> float:
	var safe_reference := maxf(reference_distance, 0.01)
	var normalized_distance := maxf(path_length, 0.0) / safe_reference
	# A regularized inverse-distance curve avoids the old flat-near-field/hard-knee transition.
	return -10.0 * log(1.0 + normalized_distance * normalized_distance) / log(10.0)


static func _range_fade_volume_db(path_length: float, max_distance: float) -> float:
	if max_distance <= 0.0:
		return AcousticPathModifier.MIN_VOLUME_DB
	var fade_width := minf(
		maxf(max_distance * RANGE_FADE_FRACTION, 0.5),
		max_distance
	)
	var fade_start := max_distance - fade_width
	if path_length <= fade_start:
		return 0.0
	var fade_t := clampf(
		(path_length - fade_start) / maxf(fade_width, 0.001),
		0.0,
		1.0
	)
	# Fading an amplitude polynomial all the way to zero creates an unbounded dB slope near
	# the culling radius. A bounded dB ramp is perceptually smooth and already leaves ordinary
	# sources below useful audibility before the authoritative cull.
	var fade_attenuation_db := MAX_RANGE_FADE_ATTENUATION_DB
	# The old half-range linear ramp changed derivative abruptly and made a tunnel mouth sound as
	# though level had entered a conveyor-belt fade. A short quadratic ease at both edges gives this
	# tail continuous slope, while the bounded middle derivative avoids concentrating most loss in
	# one steep cubic patch. Ordinary spreading still owns the useful aperture field.
	return -fade_attenuation_db * _bounded_range_fade_weight(fade_t)


static func _bounded_range_fade_weight(fade_t: float) -> float:
	var safe_t := clampf(fade_t, 0.0, 1.0)
	var edge := RANGE_FADE_EDGE_EASE_FRACTION
	var middle_slope := 1.0 / (1.0 - edge)
	if safe_t < edge:
		return middle_slope * safe_t * safe_t / (2.0 * edge)
	if safe_t > 1.0 - edge:
		var remaining := 1.0 - safe_t
		return 1.0 - middle_slope * remaining * remaining / (2.0 * edge)
	return middle_slope * (safe_t - edge * 0.5)


func _collect_modifier_ids(
	field: AcousticPropagationField,
	target_probe: int,
	source_modifier_id: StringName
) -> PackedStringArray:
	var result := PackedStringArray()
	var current_probe := target_probe
	var remaining := probe_count()
	while current_probe >= 0 and remaining > 0:
		var modifier_index := field.predecessor_modifiers[current_probe]
		if modifier_index >= 0 and modifier_index < _modifiers.size():
			var modifier_id := _modifiers[modifier_index].modifier_id
			if (
				not modifier_id.is_empty()
				and not result.has(str(modifier_id))
			):
				result.append(str(modifier_id))
		current_probe = field.predecessors[current_probe]
		remaining -= 1
	if (
		not source_modifier_id.is_empty()
		and not result.has(str(source_modifier_id))
	):
		result.append(str(source_modifier_id))
	return result


static func _routing_loss_db(band_gain: Vector3, volume_offset_db: float) -> float:
	var mean_gain := maxf(
		(band_gain.x + band_gain.y + band_gain.z) / 3.0,
		MIN_GAIN
	)
	return maxf(
		-20.0 * log(mean_gain) / log(10.0) - volume_offset_db,
		0.0
	)


static func _route_signal_loss_db(
	path_length: float,
	guided_path_length: float,
	band_gain: Vector3,
	volume_offset_db: float
) -> float:
	var safe_path_length := maxf(path_length, 0.0)
	var safe_guided_path_length := clampf(
		guided_path_length,
		0.0,
		safe_path_length
	)
	var effective_spreading_length := (
		safe_path_length
		- safe_guided_path_length * (1.0 - GUIDED_PATH_DISTANCE_SCALE)
	)
	return (
		-_distance_volume_db(effective_spreading_length, DEFAULT_REFERENCE_DISTANCE)
		+ _routing_loss_db(band_gain, volume_offset_db)
	)


static func _air_absorption_gain(path_length: float) -> Vector3:
	var attenuation_db := DEFAULT_AIR_ABSORPTION_DB_PER_METER * maxf(
		path_length,
		0.0
	)
	return Vector3(
		db_to_linear(-attenuation_db.x),
		db_to_linear(-attenuation_db.y),
		db_to_linear(-attenuation_db.z)
	)


static func _modifier_to_bake_data(modifier: AcousticPathModifier) -> Dictionary:
	return {
		"id": str(modifier.modifier_id),
		"band_gain": modifier.band_gain,
		"volume_db": modifier.volume_db,
		"extra_delay_seconds": modifier.extra_delay_seconds,
		"lowpass_hz": modifier.lowpass_hz,
		"highpass_hz": modifier.highpass_hz,
		"resonance": modifier.resonance,
		"reverb_send": modifier.reverb_send,
	}


static func _modifier_from_bake_data(data: Dictionary) -> AcousticPathModifier:
	var band_gain: Variant = data.get("band_gain", null)
	if not band_gain is Vector3:
		return null
	var result := AcousticPathModifier.new()
	result.modifier_id = StringName(str(data.get("id", "")))
	result.band_gain = band_gain as Vector3
	result.volume_db = float(data.get("volume_db", 0.0))
	result.extra_delay_seconds = float(data.get("extra_delay_seconds", 0.0))
	result.lowpass_hz = float(data.get("lowpass_hz", AcousticPathModifier.MAX_FILTER_HZ))
	result.highpass_hz = float(data.get("highpass_hz", AcousticPathModifier.MIN_FILTER_HZ))
	result.resonance = float(data.get("resonance", 0.0))
	result.reverb_send = float(data.get("reverb_send", 0.0))
	return result.sanitized_copy()


func _pressure_arrival_via_edge(
	primary_result: Dictionary,
	field: AcousticPropagationField,
	listener_position: Vector3,
	source_position: Vector3,
	source_probe: int,
	edge_index: int,
	max_distance: float,
	reference_distance: float,
	pressure_gain_db: float,
	bass_boost_db: float,
	confinement: float,
	reflection_delay_seconds: float,
	pressure_escape: float,
	pressure_escape_direction: Vector3,
	pressure_escape_directionality: float
) -> Dictionary:
	var target_probe := _targets_by_probe[source_probe][edge_index]
	if (
		target_probe < 0
		or target_probe >= probe_count()
		or not is_finite(field.route_costs[target_probe])
	):
		return {}
	var listener_origin_probe := field.origin_probes[target_probe]
	if listener_origin_probe < 0 or listener_origin_probe >= probe_count():
		return {}
	var cached_listener_offset := field.source_position.distance_to(
		_positions[listener_origin_probe]
	)
	var live_listener_offset := listener_position.distance_to(
		_positions[listener_origin_probe]
	)
	var listener_route_length := maxf(
		field.path_lengths[target_probe]
		- cached_listener_offset
		+ live_listener_offset,
		0.0
	)
	var listener_arrival_time := maxf(
		field.arrival_times[target_probe]
		- cached_listener_offset / SPEED_OF_SOUND_METERS_PER_SECOND
		+ live_listener_offset / SPEED_OF_SOUND_METERS_PER_SECOND,
		0.0
	)
	var source_offset := source_position.distance_to(_positions[source_probe])
	var edge_length := _lengths_by_probe[source_probe][edge_index]
	var path_length := source_offset + edge_length + listener_route_length
	if path_length > maxf(max_distance, 0.0):
		return {}
	var travel_delay_seconds := (
		source_offset / SPEED_OF_SOUND_METERS_PER_SECOND
		+ edge_length / SPEED_OF_SOUND_METERS_PER_SECOND
		+ _delays_by_probe[source_probe][edge_index]
		+ listener_arrival_time
		+ reflection_delay_seconds
	)
	var primary_delay := maxf(
		SafeVariant.finite_float_or(
			primary_result.get("travel_delay_seconds"),
			0.0
		),
		0.0
	) + reflection_delay_seconds
	if travel_delay_seconds < (
		primary_delay + PRESSURE_ALTERNATE_DELAY_EPSILON_SECONDS
	):
		return {}

	var edge_direction := (
		_positions[target_probe] - _positions[source_probe]
	).normalized()
	var directionality := clampf(pressure_escape_directionality, 0.0, 1.0)
	var alignment_gain := lerpf(
		1.0,
		0.35 + 0.65 * maxf(
			pressure_escape_direction.dot(edge_direction),
			0.0
		),
		directionality
	)
	var escape_support := maxf(
		clampf(pressure_escape, 0.0, 1.0),
		0.28 * directionality
	)
	var escape_gain_db := 20.0 * log(maxf(
		lerpf(0.38, 1.0, escape_support) * alignment_gain,
		MIN_GAIN
	)) / log(10.0)
	var geometric_spreading_db := _distance_volume_db(
		path_length,
		reference_distance
	)
	var volume_db := clampf(
		field.volume_db[target_probe]
		+ _volume_db_by_probe[source_probe][edge_index]
		+ geometric_spreading_db
		+ _range_fade_volume_db(path_length, maxf(max_distance, 0.0))
		+ pressure_gain_db
		+ PRESSURE_ALTERNATE_ROUTE_PENALTY_DB
		+ escape_gain_db,
		AcousticPathModifier.MIN_VOLUME_DB,
		AcousticPathModifier.MAX_VOLUME_DB
	)
	if volume_db <= AcousticPathModifier.MIN_VOLUME_DB + 1.0:
		return {}
	var band_gain := (
		field.band_gains[target_probe]
		* _band_gains_by_probe[source_probe][edge_index]
		* _air_absorption_gain(path_length)
	)
	band_gain = _pressure_colored_band_gain(
		band_gain,
		bass_boost_db,
		confinement
	)
	var lowpass_hz := minf(
		field.lowpass_hz[target_probe],
		minf(
			_lowpass_by_probe[source_probe][edge_index],
			lerpf(8800.0, 4200.0, confinement)
		)
	)
	return {
		"kind": 1,
		"apparent_position": _apparent_position(
			field,
			target_probe,
			source_position,
			listener_position.distance_to(source_position),
			listener_position
		),
		"path_length": path_length,
		"travel_delay_seconds": travel_delay_seconds,
		"volume_db": volume_db,
		"band_gain": band_gain,
		"lowpass_hz": lowpass_hz,
		"highpass_hz": minf(
			maxf(
				field.highpass_hz[target_probe],
				_highpass_by_probe[source_probe][edge_index]
			),
			lowpass_hz
		),
		"resonance": maxf(
			field.resonance[target_probe],
			_resonance_by_probe[source_probe][edge_index]
		),
		"reverb_scale": clampf(0.55 + 0.35 * confinement, 0.0, 1.0),
		"score_db": volume_db,
	}


func _accumulate_pressure_probe(
	accumulator: Dictionary,
	probe_index: int,
	source_position: Vector3,
	transmission_weight: float
) -> void:
	if probe_index < 0 or probe_index >= probe_count():
		return
	var influence := _environment_influence(probe_index, source_position)
	if influence <= 0.0001:
		return
	var distance_squared := source_position.distance_squared_to(
		_positions[probe_index]
	)
	var weight := (
		clampf(transmission_weight, 0.0, 1.0)
		* influence
		/ (distance_squared + LISTENER_PROBE_BLEND_REGULARIZATION_SQUARED)
	)
	if weight <= 0.000001:
		return
	accumulator["weight"] = float(accumulator["weight"]) + weight
	accumulator["confinement"] = (
		float(accumulator["confinement"])
		+ weight * _pressure_confinement[probe_index]
	)
	accumulator["body_gain_db"] = (
		float(accumulator["body_gain_db"])
		+ weight * _pressure_body_gain_db[probe_index]
	)
	accumulator["bass_boost_db"] = (
		float(accumulator["bass_boost_db"])
		+ weight * _pressure_bass_boost_db[probe_index]
	)
	accumulator["reflection_delay_seconds"] = (
		float(accumulator["reflection_delay_seconds"])
		+ weight * _pressure_reflection_delay_seconds[probe_index]
	)
	accumulator["reverb_send"] = (
		float(accumulator["reverb_send"])
		+ weight * _pressure_reverb_send[probe_index]
	)
	accumulator["decay_seconds"] = (
		float(accumulator["decay_seconds"])
		+ weight * _pressure_decay_seconds[probe_index]
	)
	accumulator["escape"] = (
		float(accumulator["escape"])
		+ weight * _pressure_escape[probe_index]
	)
	accumulator["room_size"] = (
		float(accumulator["room_size"])
		+ weight * _environment_room_size[probe_index]
	)
	accumulator["damping"] = (
		float(accumulator["damping"])
		+ weight * _environment_damping[probe_index]
	)
	accumulator["spread"] = (
		float(accumulator["spread"])
		+ weight * _environment_spread[probe_index]
	)
	accumulator["predelay_feedback"] = (
		float(accumulator["predelay_feedback"])
		+ weight * _environment_predelay_feedback[probe_index]
	)
	accumulator["hipass"] = (
		float(accumulator["hipass"])
		+ weight * _environment_hipass[probe_index]
	)
	var directionality := _pressure_escape_directionality[probe_index]
	accumulator["escape_direction_sum"] = (
		accumulator["escape_direction_sum"] as Vector3
		+ _pressure_escape_directions[probe_index]
		* weight
		* directionality
	)
	accumulator["escape_directionality"] = (
		float(accumulator["escape_directionality"])
		+ weight * directionality
	)


func _open_pressure_emission(pressure_strength: float) -> Dictionary:
	return {
		"graph_revision": revision,
		"source_probe": -1,
		"strength": clampf(pressure_strength, 0.0, 1.0),
		"confinement": 0.0,
		"body_gain_db": -10.5,
		"bass_boost_db": 0.75,
		"reflection_delay_seconds": 0.003,
		"reverb_send": 0.0,
		"decay_seconds": AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS,
		"escape": 1.0,
		"room_size": 0.02,
		"damping": 0.05,
		"spread": 1.0,
		"predelay_feedback": 0.0,
		"hipass": 0.0,
		"escape_direction": Vector3.ZERO,
		"escape_directionality": 0.0,
	}


static func _pressure_colored_band_gain(
	base_gain: Vector3,
	bass_boost_db: float,
	confinement: float
) -> Vector3:
	var bass_gain := db_to_linear(clampf(bass_boost_db, 0.0, 12.0))
	var safe_confinement := clampf(confinement, 0.0, 1.0)
	return Vector3(
		clampf(base_gain.x * bass_gain, 0.0, 4.0),
		clampf(base_gain.y * lerpf(0.92, 0.78, safe_confinement), 0.0, 4.0),
		clampf(base_gain.z * lerpf(0.62, 0.30, safe_confinement), 0.0, 4.0)
	)


static func _insert_pressure_candidate(
	candidates: Array[Dictionary],
	candidate: Dictionary,
	maximum_count: int
) -> void:
	var insert_index := candidates.size()
	var score := float(candidate.get("score_db", -INF))
	for candidate_index: int in range(candidates.size()):
		if score > float(candidates[candidate_index].get("score_db", -INF)):
			insert_index = candidate_index
			break
	candidates.insert(insert_index, candidate)
	if candidates.size() > maxi(maximum_count, 0):
		candidates.pop_back()


static func _unit_response_value(
	response: Dictionary,
	key: String,
	fallback: float
) -> float:
	return clampf(
		SafeVariant.finite_float_or(response.get(key), fallback),
		0.0,
		1.0
	)

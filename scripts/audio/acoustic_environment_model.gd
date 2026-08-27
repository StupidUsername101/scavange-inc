class_name AcousticEnvironmentModel
extends RefCounted

const SPEED_OF_SOUND_METERS_PER_SECOND := 343.0
const MIN_RETENTION := 0.001
const MAX_RETENTION := 0.995
const MIN_REVERB_TIME_SECONDS := 0.04
const MAX_REVERB_TIME_SECONDS := 8.0
const MAX_GUIDED_PROPAGATION := 0.82

## Converts a sparse, rebuild-time set of surface samples into one diffuse reflection response.
## A missing surface is treated as escaped energy. Rooms, tunnels, and open air therefore use the
## same decay rule instead of selecting authored environment presets.


static func response_from_samples(
	distances_m: PackedFloat32Array,
	hit_mask: PackedByteArray,
	absorptions: PackedVector3Array,
	scattering_values: PackedFloat32Array,
	maximum_distance_m: float,
	reverb_scale := 1.0
) -> Dictionary:
	var sample_count := mini(distances_m.size(), hit_mask.size())
	if sample_count <= 0:
		return open_air_response()

	var safe_maximum_distance := maxf(maximum_distance_m, 0.1)
	var hit_count := 0
	var hit_distance_sum := 0.0
	var sample_distance_sum := 0.0
	var nearest_hit_distance := safe_maximum_distance
	var ordered_distances := PackedFloat32Array()
	ordered_distances.resize(sample_count)
	var absorption_sum := Vector3.ZERO
	var scattering_sum := 0.0
	for sample_index: int in range(sample_count):
		var distance := clampf(
			float(distances_m[sample_index]),
			0.01,
			safe_maximum_distance
		)
		ordered_distances[sample_index] = distance
		sample_distance_sum += distance
		if hit_mask[sample_index] == 0:
			continue
		hit_count += 1
		hit_distance_sum += distance
		nearest_hit_distance = minf(nearest_hit_distance, distance)
		if sample_index < absorptions.size():
			absorption_sum += _unit_vector(absorptions[sample_index])
		if sample_index < scattering_values.size():
			scattering_sum += clampf(
				float(scattering_values[sample_index]),
				0.0,
				1.0
			)

	if hit_count <= 0:
		return open_air_response()

	ordered_distances.sort()
	var median_distance := float(ordered_distances[sample_count / 2])
	var median_hit_distance := float(ordered_distances[(hit_count - 1) / 2])
	var longest_distance := float(ordered_distances[sample_count - 1])
	# Uniform radial samples also give us a useful star-volume estimate:
	# V = integral(r^3 dOmega) / 3. Escaping rays use the median hit distance rather than the
	# hit median, so a doorway does not turn a garage into a twenty-metre sphere. This is
	# rebuild-only data used to derive the room's critical distance; runtime sources never repeat it.
	var radial_cubic_sum := 0.0
	for sample_index: int in range(sample_count):
		var radial_distance := (
			float(distances_m[sample_index])
			if hit_mask[sample_index] != 0
			else median_hit_distance
		)
		radial_cubic_sum += radial_distance * radial_distance * radial_distance
	var effective_volume_m3 := clampf(
		4.0 * PI * radial_cubic_sum / (3.0 * float(sample_count)),
		1.0,
		4.0 * PI * pow(safe_maximum_distance, 3.0) / 3.0
	)
	var elongation := longest_distance / maxf(median_distance, 0.1)
	var enclosure := float(hit_count) / float(sample_count)
	var enclosure_factor := smoothstep(0.35, 0.88, enclosure)
	var tunnel_factor := (
		enclosure_factor * smoothstep(2.0, 6.0, elongation)
	)
	var mean_absorption := absorption_sum / float(hit_count)
	var mean_scattering := scattering_sum / float(hit_count)
	var mean_hit_distance := hit_distance_sum / float(hit_count)
	var mean_sample_distance := sample_distance_sum / float(sample_count)
	# A ray starts roughly halfway through its next chord. Doubling the mean endpoint distance is
	# a stable mean-free-path approximation without reconstructing a watertight room mesh.
	var mean_free_path := clampf(
		lerpf(mean_hit_distance, mean_sample_distance, enclosure_factor) * 2.0,
		0.1,
		safe_maximum_distance * 2.0
	)
	var mean_reflectivity := clampf(
		1.0 - (mean_absorption.x + mean_absorption.y + mean_absorption.z) / 3.0,
		0.0,
		1.0
	)
	# Long, enclosed, reflective volumes behave partly like acoustic waveguides: wall reflections
	# keep returning energy to the axis instead of allowing ordinary spherical spreading. Keep the
	# coefficient below one because real tunnels still lose energy at their walls and portals.
	var guided_propagation := clampf(
		enclosure_factor
		* smoothstep(0.42, 0.72, tunnel_factor)
		* lerpf(0.55, 0.95, mean_reflectivity),
		0.0,
		MAX_GUIDED_PROPAGATION
	)
	var mean_absorption_scalar := (
		mean_absorption.x + mean_absorption.y + mean_absorption.z
	) / 3.0
	var guided_wall_loss_db_per_m := lerpf(
		0.01,
		0.075,
		mean_absorption_scalar
	)
	# Eyring-style diffuse decay: each mean-free-path traversal retains the surface reflection
	# energy, while the unbounded fraction escapes. RT60 is the time to lose 60 dB of energy.
	var retention := clampf(
		enclosure * mean_reflectivity,
		MIN_RETENTION,
		MAX_RETENTION
	)
	var rt60_seconds := clampf(
		-6.0 * log(10.0) * mean_free_path
		/ (SPEED_OF_SOUND_METERS_PER_SECOND * log(retention)),
		MIN_REVERB_TIME_SECONDS,
		MAX_REVERB_TIME_SECONDS
	)
	var safe_scale := clampf(reverb_scale, 0.0, 2.0)
	var send := clampf(
		enclosure_factor
		* (0.16 + 0.54 * mean_reflectivity)
		* lerpf(0.78, 1.0, mean_scattering)
		* safe_scale,
		0.0,
		0.82
	)
	var size_from_path := 1.0 - exp(-mean_free_path / 11.0)
	var size_from_decay := 1.0 - exp(-rt60_seconds / 1.8)
	var room_size := clampf(
		lerpf(size_from_path, size_from_decay, 0.45),
		0.02,
		1.0
	)
	# A narrow guide has a short cross-section but a perceptually large axial dimension. A denser
	# spherical sample set should not dilute those two important open-axis rays into a tiny room.
	var axial_size := 1.0 - exp(-longest_distance / 16.0)
	room_size = clampf(
		lerpf(room_size, maxf(room_size, axial_size), tunnel_factor * 0.55),
		0.02,
		1.0
	)
	# Detonations need a compact source-side response in addition to the listener's late reverb.
	# These values are baked with the probe: runtime events only look them up and route a handful
	# of pressure arrivals through the already-built graph. Small reflective rooms reinforce the
	# body of the impulse; large rooms trade that body for a later, longer response.
	var compactness := 1.0 - smoothstep(2.0, 12.0, mean_free_path)
	var pressure_confinement := clampf(
		enclosure_factor * lerpf(0.55, 1.0, mean_reflectivity),
		0.0,
		1.0
	)
	var pressure_body_gain_db := clampf(
		lerpf(-10.5, -4.5, pressure_confinement)
		+ 2.0 * pressure_confinement * compactness,
		-12.0,
		-2.5
	)
	var pressure_bass_boost_db := clampf(
		lerpf(
			0.75,
			7.5,
			pressure_confinement * lerpf(0.68, 1.0, compactness)
		),
		0.0,
		9.0
	)
	var pressure_reflection_delay_seconds := clampf(
		2.0 * nearest_hit_distance / SPEED_OF_SOUND_METERS_PER_SECOND,
		0.003,
		0.14
	)
	return {
		"enclosure": enclosure,
		"mean_free_path_m": mean_free_path,
		"effective_volume_m3": effective_volume_m3,
		"longest_sample_m": longest_distance,
		"elongation": elongation,
		"tunnel_factor": tunnel_factor,
		"guided_propagation": guided_propagation,
		"guided_wall_loss_db_per_m": guided_wall_loss_db_per_m,
		"mean_absorption": mean_absorption,
		"mean_scattering": mean_scattering,
		"rt60_seconds": rt60_seconds,
		"reverb_send": send,
		"reverb_room_size": room_size,
		# Godot's damping control behaves as wall reflectivity: reflective high frequencies retain
		# a brighter tail, while absorptive surfaces make it dark and short.
		"reverb_damping": clampf(1.0 - mean_absorption.z, 0.05, 0.98),
		"reverb_spread": lerpf(0.96, 0.48, tunnel_factor),
		"reverb_predelay_msec": clampf(
			2000.0 * nearest_hit_distance / SPEED_OF_SOUND_METERS_PER_SECOND,
			1.0,
			180.0
		),
		"reverb_predelay_feedback": clampf(
			retention * lerpf(0.28, 0.72, tunnel_factor),
			0.0,
			0.82
		),
		"reverb_hipass": clampf(
			0.03 + mean_absorption.x * 0.22,
			0.0,
			0.35
		),
		"pressure_confinement": pressure_confinement,
		"pressure_body_gain_db": pressure_body_gain_db,
		"pressure_bass_boost_db": pressure_bass_boost_db,
		"pressure_reflection_delay_seconds": (
			pressure_reflection_delay_seconds
		),
		"pressure_reverb_send": clampf(
			send * lerpf(0.52, 1.0, pressure_confinement),
			0.0,
			0.82
		),
		"pressure_decay_seconds": rt60_seconds,
		"pressure_escape": 1.0 - enclosure,
		"pressure_escape_direction": Vector3.ZERO,
		"pressure_escape_directionality": 0.0,
	}


static func open_air_response() -> Dictionary:
	return {
		"enclosure": 0.0,
		"mean_free_path_m": 0.0,
		"effective_volume_m3": 0.0,
		"longest_sample_m": 0.0,
		"elongation": 1.0,
		"tunnel_factor": 0.0,
		"guided_propagation": 0.0,
		"guided_wall_loss_db_per_m": 0.0,
		"mean_absorption": Vector3.ONE,
		"mean_scattering": 0.0,
		"rt60_seconds": MIN_REVERB_TIME_SECONDS,
		"reverb_send": 0.0,
		"reverb_room_size": 0.02,
		"reverb_damping": 0.05,
		"reverb_spread": 1.0,
		"reverb_predelay_msec": 1.0,
		"reverb_predelay_feedback": 0.0,
		"reverb_hipass": 0.0,
		"pressure_confinement": 0.0,
		"pressure_body_gain_db": -10.5,
		"pressure_bass_boost_db": 0.75,
		"pressure_reflection_delay_seconds": 0.003,
		"pressure_reverb_send": 0.0,
		"pressure_decay_seconds": MIN_REVERB_TIME_SECONDS,
		"pressure_escape": 1.0,
		"pressure_escape_direction": Vector3.ZERO,
		"pressure_escape_directionality": 0.0,
	}


static func _unit_vector(value: Vector3) -> Vector3:
	if not value.is_finite():
		return Vector3.ZERO
	return Vector3(
		clampf(value.x, 0.0, 1.0),
		clampf(value.y, 0.0, 1.0),
		clampf(value.z, 0.0, 1.0)
	)

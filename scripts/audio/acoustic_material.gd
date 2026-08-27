@tool
class_name AcousticMaterial
extends Resource

## Material data used while crossing a wall or portal. Absorption and scattering are retained
## independently from transmission so later reflection/impulse-response renderers do not need a
## resource format migration.

@export var material_id: StringName = &"generic"
@export var transmission_gain := Vector3(0.72, 0.38, 0.14)
@export var absorption := Vector3(0.12, 0.22, 0.38)
@export_range(0.0, 1.0, 0.01) var scattering := 0.08
@export_range(-80.0, 0.0, 0.1) var transmission_volume_db := -2.0
@export_range(20.0, 20000.0, 1.0, "or_greater") var transmission_lowpass_hz := 5200.0
@export_range(20.0, 20000.0, 1.0, "or_greater") var transmission_highpass_hz := 20.0
@export_range(0.0, 1.0, 0.01) var resonance := 0.0
@export_range(0.0, 1.0, 0.01) var reverb_send := 0.12
@export var additional_modifier: AcousticPathModifier


func create_transmission_modifier() -> AcousticPathModifier:
	var result := AcousticPathModifier.new()
	result.modifier_id = material_id
	result.band_gain = _sanitize_unit_vector(transmission_gain, Vector3.ONE)
	result.volume_db = clampf(
		SafeVariant.finite_float_or(transmission_volume_db, -2.0),
		AcousticPathModifier.MIN_VOLUME_DB,
		0.0
	)
	result.lowpass_hz = clampf(
		SafeVariant.finite_float_or(transmission_lowpass_hz, 5200.0),
		AcousticPathModifier.MIN_FILTER_HZ,
		AcousticPathModifier.MAX_FILTER_HZ
	)
	result.highpass_hz = clampf(
		SafeVariant.finite_float_or(transmission_highpass_hz, 20.0),
		AcousticPathModifier.MIN_FILTER_HZ,
		result.lowpass_hz
	)
	result.resonance = clampf(
		SafeVariant.finite_float_or(resonance, 0.0),
		0.0,
		1.0
	)
	result.reverb_send = clampf(
		SafeVariant.finite_float_or(reverb_send, 0.12),
		0.0,
		1.0
	)
	return (
		result.combined_with(additional_modifier)
		if additional_modifier != null
		else result.sanitized_copy()
	)


func sanitized_absorption() -> Vector3:
	return _sanitize_unit_vector(absorption, Vector3.ZERO)


func sanitized_scattering() -> float:
	return clampf(
		SafeVariant.finite_float_or(scattering, 0.08),
		0.0,
		1.0
	)


static func _sanitize_unit_vector(value: Vector3, fallback: Vector3) -> Vector3:
	if not value.is_finite():
		return fallback
	return Vector3(
		clampf(value.x, 0.0, 1.0),
		clampf(value.y, 0.0, 1.0),
		clampf(value.z, 0.0, 1.0)
	)

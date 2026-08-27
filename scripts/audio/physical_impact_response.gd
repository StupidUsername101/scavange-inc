class_name PhysicalImpactResponse
extends RefCounted

## Converts projectile excitation into a material response before ordinary world propagation.
## The response is deliberately nonlinear: quiet hits emphasize body, while harder hits expose
## progressively more crack/ring. Eight cached energy bands keep the impact hot path allocation-free.

const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const ENERGY_BUCKET_COUNT := 8

static var _modifier_cache: Dictionary[int, AcousticPathModifier] = {}


static func prewarm() -> void:
	for surface: StringName in [
		PHYSICAL_SURFACE.CONCRETE,
		PHYSICAL_SURFACE.METAL,
		PHYSICAL_SURFACE.WOOD,
		PHYSICAL_SURFACE.STONE,
		PHYSICAL_SURFACE.SOIL,
	]:
		for bucket: int in range(ENERGY_BUCKET_COUNT):
			_modifier_for_bucket(surface, bucket)


static func modifier_for(
	surface_value: Variant,
	excitation: float
) -> AcousticPathModifier:
	var surface := PHYSICAL_SURFACE.normalize(surface_value)
	var bucket := clampi(
		roundi(clampf(excitation, 0.0, 1.0) * float(ENERGY_BUCKET_COUNT - 1)),
		0,
		ENERGY_BUCKET_COUNT - 1
	)
	return _modifier_for_bucket(surface, bucket)


static func _modifier_for_bucket(
	surface: StringName,
	bucket: int
) -> AcousticPathModifier:
	var cache_key := _surface_index(surface) * ENERGY_BUCKET_COUNT + bucket
	var cached := _modifier_cache.get(cache_key) as AcousticPathModifier
	if cached != null:
		return cached
	var energy := float(bucket) / float(ENERGY_BUCKET_COUNT - 1)
	var drive := 1.0 - exp(-3.2 * energy)
	var crack := pow(drive, 0.42)
	var body := drive * drive
	var modifier := AcousticPathModifier.new()
	match surface:
		PHYSICAL_SURFACE.METAL:
			modifier.modifier_id = &"impact_response_metal"
			modifier.band_gain = Vector3(
				lerpf(0.72, 0.92, body),
				lerpf(0.88, 1.34, drive),
				lerpf(0.62, 1.52, crack)
			)
			modifier.volume_db = lerpf(-3.0, 2.4, crack)
			modifier.lowpass_hz = lerpf(7200.0, 19000.0, crack)
			modifier.highpass_hz = lerpf(95.0, 240.0, body)
			modifier.resonance = lerpf(0.28, 0.72, drive)
			modifier.reverb_send = lerpf(0.03, 0.13, body)
		PHYSICAL_SURFACE.WOOD:
			modifier.modifier_id = &"impact_response_wood"
			modifier.band_gain = Vector3(
				lerpf(1.08, 1.28, body),
				lerpf(0.92, 1.14, drive),
				lerpf(0.34, 0.68, crack)
			)
			modifier.volume_db = lerpf(-4.5, 0.8, drive)
			modifier.lowpass_hz = lerpf(3600.0, 9800.0, crack)
			modifier.highpass_hz = 55.0
			modifier.resonance = lerpf(0.12, 0.34, body)
			modifier.reverb_send = lerpf(0.025, 0.08, drive)
		PHYSICAL_SURFACE.STONE:
			modifier.modifier_id = &"impact_response_stone"
			modifier.band_gain = Vector3(
				lerpf(0.92, 1.18, body),
				lerpf(0.86, 1.24, drive),
				lerpf(0.48, 1.02, crack)
			)
			modifier.volume_db = lerpf(-3.5, 1.8, crack)
			modifier.lowpass_hz = lerpf(5200.0, 14800.0, crack)
			modifier.highpass_hz = lerpf(60.0, 135.0, body)
			modifier.resonance = lerpf(0.2, 0.5, drive)
			modifier.reverb_send = lerpf(0.035, 0.11, body)
		PHYSICAL_SURFACE.SOIL:
			modifier.modifier_id = &"impact_response_soil"
			modifier.band_gain = Vector3(
				lerpf(1.12, 1.34, body),
				lerpf(0.58, 0.82, drive),
				lerpf(0.12, 0.3, crack)
			)
			modifier.volume_db = lerpf(-7.0, -1.2, drive)
			modifier.lowpass_hz = lerpf(1900.0, 5200.0, crack)
			modifier.highpass_hz = 35.0
			modifier.resonance = lerpf(0.02, 0.1, body)
			modifier.reverb_send = lerpf(0.01, 0.035, drive)
		_:
			modifier.modifier_id = &"impact_response_concrete"
			modifier.band_gain = Vector3(
				lerpf(0.86, 1.08, body),
				lerpf(0.9, 1.22, drive),
				lerpf(0.5, 1.18, crack)
			)
			modifier.volume_db = lerpf(-3.8, 1.6, crack)
			modifier.lowpass_hz = lerpf(5600.0, 16400.0, crack)
			modifier.highpass_hz = lerpf(65.0, 155.0, body)
			modifier.resonance = lerpf(0.16, 0.42, drive)
			modifier.reverb_send = lerpf(0.03, 0.1, body)
	_modifier_cache[cache_key] = modifier
	return modifier


static func _surface_index(surface: StringName) -> int:
	match surface:
		PHYSICAL_SURFACE.METAL:
			return 1
		PHYSICAL_SURFACE.WOOD:
			return 2
		PHYSICAL_SURFACE.STONE:
			return 3
		PHYSICAL_SURFACE.SOIL:
			return 4
	return 0

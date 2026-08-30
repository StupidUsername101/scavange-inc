class_name DamageEvent
extends RefCounted

## Immutable-at-use description of one authoritative material interaction. Geometry backends,
## character wounds, audio, and effects consume the same normalized event instead of interpreting a
## projectile's scalar damage independently.

const BRUSH_SPHERE := &"sphere"
const BRUSH_CAPSULE := &"capsule"
const BRUSH_CONTACT := &"contact"

const TAG_BALLISTIC := &"ballistic"
const TAG_BLUNT := &"blunt"
const TAG_EXPLOSIVE := &"explosive"
const TAG_BLADE := &"blade"
const TAG_HEAT := &"heat"

const MIN_DIRECTION_LENGTH_SQUARED := 0.000001
const MAX_EVENT_RADIUS := 32.0
const MAX_EVENT_LENGTH := 128.0
const MAX_EVENT_ENERGY := 1000000.0
const NETWORK_POSITION_STEP := 0.001
const NETWORK_SCALAR_STEP := 0.001

var event_id := 0
var sequence := 0
var source_kind := &"unknown"
var source_id := -1
var world_position := Vector3.ZERO
var normal := Vector3.UP
var direction := Vector3.FORWARD
var brush_kind := BRUSH_SPHERE
var radius := 0.05
var length := 0.0
var energy := 0.0
var impulse := 0.0
var penetration := 0.0
var heat := 0.0
var damage_tags := PackedStringArray()
var seed := 0
var timestamp_tick := 0


func configure(value: Dictionary) -> DamageEvent:
	event_id = maxi(_integral(value.get("event_id", 0), 0), 0)
	sequence = maxi(_integral(value.get("sequence", event_id), event_id), 0)
	source_kind = StringName(str(value.get("source_kind", &"unknown")))
	source_id = _integral(value.get("source_id", -1), -1)
	world_position = _finite_vector(value.get("world_position"), Vector3.ZERO)
	normal = _safe_direction(value.get("normal"), Vector3.UP)
	direction = _safe_direction(value.get("direction"), -normal)
	brush_kind = normalize_brush_kind(value.get("brush_kind", BRUSH_SPHERE))
	radius = clampf(_finite_float(value.get("radius", 0.05), 0.05), 0.001, MAX_EVENT_RADIUS)
	length = clampf(_finite_float(value.get("length", 0.0), 0.0), 0.0, MAX_EVENT_LENGTH)
	energy = clampf(_finite_float(value.get("energy", 0.0), 0.0), 0.0, MAX_EVENT_ENERGY)
	impulse = clampf(_finite_float(value.get("impulse", 0.0), 0.0), 0.0, MAX_EVENT_ENERGY)
	penetration = clampf(
		_finite_float(value.get("penetration", 0.0), 0.0),
		0.0,
		MAX_EVENT_LENGTH
	)
	heat = clampf(_finite_float(value.get("heat", 0.0), 0.0), 0.0, MAX_EVENT_ENERGY)
	damage_tags = _normalize_tags(value.get("damage_tags", PackedStringArray()))
	seed = _integral(value.get("seed", event_id), event_id)
	timestamp_tick = maxi(_integral(value.get("timestamp_tick", 0), 0), 0)
	return self


func is_valid() -> bool:
	return (
		world_position.is_finite()
		and normal.is_finite()
		and direction.is_finite()
		and normal.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED
		and direction.length_squared() >= MIN_DIRECTION_LENGTH_SQUARED
		and is_finite(radius)
		and radius > 0.0
		and is_finite(energy)
		and energy >= 0.0
	)


func has_tag(tag: StringName) -> bool:
	return damage_tags.has(str(tag))


func to_dict(quantize_for_network := false) -> Dictionary:
	var result := {
		"event_id": event_id,
		"sequence": sequence,
		"source_kind": source_kind,
		"source_id": source_id,
		"world_position": world_position,
		"normal": normal,
		"direction": direction,
		"brush_kind": brush_kind,
		"radius": radius,
		"length": length,
		"energy": energy,
		"impulse": impulse,
		"penetration": penetration,
		"heat": heat,
		"damage_tags": damage_tags,
		"seed": seed,
		"timestamp_tick": timestamp_tick,
	}
	if not quantize_for_network:
		return result
	result["world_position"] = _snapped_vector(world_position, NETWORK_POSITION_STEP)
	result["normal"] = _snapped_vector(normal, NETWORK_SCALAR_STEP).normalized()
	result["direction"] = _snapped_vector(direction, NETWORK_SCALAR_STEP).normalized()
	for key: String in ["radius", "length", "energy", "impulse", "penetration", "heat"]:
		result[key] = snappedf(float(result[key]), NETWORK_SCALAR_STEP)
	return result


static func from_dict(value: Dictionary) -> DamageEvent:
	return DamageEvent.new().configure(value)


static func normalize_brush_kind(value: Variant) -> StringName:
	var normalized := StringName(str(value).to_lower())
	match normalized:
		BRUSH_SPHERE, BRUSH_CAPSULE, BRUSH_CONTACT:
			return normalized
	return BRUSH_SPHERE


static func deterministic_seed(
	volume_id: StringName,
	sequence_value: int,
	source_id_value: int,
	authored_seed := 0
) -> int:
	var value := hash(str(volume_id))
	value = _mix_hash(value, sequence_value)
	value = _mix_hash(value, source_id_value)
	value = _mix_hash(value, authored_seed)
	return value & 0x7fffffff


static func _mix_hash(left: int, right: int) -> int:
	var value := left ^ (right + 0x9e3779b9 + (left << 6) + (left >> 2))
	return value & 0x7fffffff


static func _finite_vector(value: Variant, fallback: Vector3) -> Vector3:
	return value if value is Vector3 and (value as Vector3).is_finite() else fallback


static func _safe_direction(value: Variant, fallback: Vector3) -> Vector3:
	var vector := _finite_vector(value, fallback)
	if vector.length_squared() < MIN_DIRECTION_LENGTH_SQUARED:
		vector = fallback
	return vector.normalized()


static func _finite_float(value: Variant, fallback: float) -> float:
	if value is float or value is int:
		var result := float(value)
		return result if is_finite(result) else fallback
	return fallback


static func _integral(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and is_equal_approx(value, roundf(value)):
		return int(value)
	return fallback


static func _normalize_tags(value: Variant) -> PackedStringArray:
	var unique: Dictionary[StringName, bool] = {}
	if value is PackedStringArray or value is Array:
		for raw_tag: Variant in value:
			var tag := StringName(str(raw_tag).to_lower())
			if not tag.is_empty():
				unique[tag] = true
	var tags := PackedStringArray()
	for tag: StringName in unique.keys():
		tags.append(str(tag))
	tags.sort()
	return tags


static func _snapped_vector(value: Vector3, step: float) -> Vector3:
	return Vector3(
		snappedf(value.x, step),
		snappedf(value.y, step),
		snappedf(value.z, step)
	)

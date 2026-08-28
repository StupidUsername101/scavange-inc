extends RefCounted

## Allocation-free key contract shared by predicted audio producers and packet validation.
## This script intentionally has no class_name and no project-script dependencies so callers can
## preload it by path even when Godot's global script-class cache has not refreshed yet.

const MAX_SEQUENCE := 0x0FFFFFFF
const SEQUENCE_NAMESPACE := 0x100000000
const GAIT_NAMESPACE := 0x200000000
const WEAPON_NAMESPACE := 0x300000000
const NAMESPACE_MASK := 0xF00000000
const PAYLOAD_MASK := 0x0FFFFFFFF
const WEAPON_SESSION_BITS := 20
const WEAPON_SHOT_BITS := 12
const WEAPON_MAX_SESSION := (1 << WEAPON_SESSION_BITS) - 1
const WEAPON_MAX_SHOT := (1 << WEAPON_SHOT_BITS) - 1


static func sequence_key(sequence: int) -> int:
	return SEQUENCE_NAMESPACE | (maxi(sequence, 0) & MAX_SEQUENCE)


static func gait_step_key(step_sequence: int) -> int:
	return GAIT_NAMESPACE | (maxi(step_sequence, 0) & PAYLOAD_MASK)


static func weapon_shot_key(session: int, shot_index: int) -> int:
	var payload := (
		(clampi(session, 0, WEAPON_MAX_SESSION) << WEAPON_SHOT_BITS)
		| clampi(shot_index, 0, WEAPON_MAX_SHOT)
	)
	return WEAPON_NAMESPACE | payload


static func sanitize_key(value: Variant) -> int:
	if not value is int and not value is float:
		return 0
	var key := int(value)
	if key <= 0 or (value is float and (not is_finite(value) or value != key)):
		return 0
	match key & NAMESPACE_MASK:
		SEQUENCE_NAMESPACE, GAIT_NAMESPACE, WEAPON_NAMESPACE:
			return key
	return 0

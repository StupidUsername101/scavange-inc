extends RefCounted

const MAX_AI_CHIP_SLOTS := 8
const MAX_PROPELLER_SLOTS: int = 4

#######################################################
# Implements the drone slot layout subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

static func get_propeller_position(
	slot_index: int,
	core_size: Vector3
) -> Vector3:
	# Legacy resources without explicit creator-authored transforms keep the familiar four-corner
	# arrangement. New creator bodies serialize exact Core-local transforms instead.
	var half_x: float = maxf(core_size.x * 0.9, 0.30)
	var half_z: float = maxf(core_size.z * 0.9, 0.30)
	var positions: Array[Vector2] = [
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(-half_x, half_z),
		Vector2(half_x, half_z),
	]
	var index: int = clampi(slot_index, 0, positions.size() - 1)
	return Vector3(
		positions[index].x,
		core_size.y * 0.5 + 0.03,
		positions[index].y
	)

static func get_ai_chip_position(
	slot_index: int,
	core_size: Vector3
) -> Vector3:
	var half_x := maxf(core_size.x * 0.5 - 0.12, 0.15)
	var half_z := maxf(core_size.z * 0.5 - 0.11, 0.15)
	var positions: Array[Vector2] = [
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(-half_x, half_z),
		Vector2(half_x, half_z),
		Vector2(0.0, -half_z),
		Vector2(0.0, half_z),
		Vector2(-half_x, 0.0),
		Vector2(half_x, 0.0),
	]
	var index := clampi(slot_index, 0, positions.size() - 1)
	return Vector3(
		positions[index].x,
		core_size.y * 0.5 + 0.025,
		positions[index].y
	)


static func get_attachment_position(
	slot_index: int,
	core_size: Vector3
) -> Vector3:
	var half_x := maxf(core_size.x * 0.3, 0.2)
	var half_z := maxf(core_size.z * 0.32, 0.22)
	var positions: Array[Vector2] = [
		Vector2(-half_x, -half_z),
		Vector2(half_x, -half_z),
		Vector2(-half_x, half_z),
		Vector2(half_x, half_z),
	]
	var index := clampi(slot_index, 0, positions.size() - 1)
	return Vector3(
		positions[index].x,
		-core_size.y * 0.5 - 0.09,
		positions[index].y
	)

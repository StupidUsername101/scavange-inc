class_name FourLimbAttachmentStateProvider
extends Node3D

const CATEGORY_FEATURE_COUNT = 4
const PAYLOAD_FEATURE_COUNT = 10
const CATEGORY_TAGS = ["weapon", "sensor", "mobility", "utility"]

#######################################################
# Extend this node for a future gun, sensor, tool, battery, or other attachment. The locomotion
# model receives installed/functional masks, contributed mass, category flags, and ten normalized payload values per fixed slot.
# No gun behavior is implemented here.
#######################################################

@export var attachment_type_id = "generic_attachment"
@export var attachment_tags: PackedStringArray = PackedStringArray()
@export var operational = true
@export_range(0.0, 1000.0, 0.01, "or_greater") var contributed_mass_kg = 0.0

var mounted_body: FourLimbPhysicalBody3D
var mounted_slot_index = -1


func is_operational() -> bool:
	return operational


func ml_category_features() -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(CATEGORY_FEATURE_COUNT)
	result.fill(0.0)
	for category_index in range(CATEGORY_TAGS.size()):
		if attachment_tags.has(CATEGORY_TAGS[category_index]):
			result[category_index] = 1.0
	return result


func ml_feature_names() -> PackedStringArray:
	return PackedStringArray([
		"feature_0", "feature_1", "feature_2", "feature_3", "feature_4",
		"feature_5", "feature_6", "feature_7", "feature_8", "feature_9",
	])


func ml_observation_payload(_context: Dictionary = {}) -> PackedFloat64Array:
	var result = PackedFloat64Array()
	result.resize(PAYLOAD_FEATURE_COUNT)
	result.fill(0.0)
	return result


func on_mounted_to_body(body: FourLimbPhysicalBody3D, slot_index: int) -> void:
	mounted_body = body
	mounted_slot_index = slot_index


func on_unmounted_from_body(body: FourLimbPhysicalBody3D, slot_index: int) -> void:
	if mounted_body == body and mounted_slot_index == slot_index:
		mounted_body = null
		mounted_slot_index = -1


func apply_recoil_or_tool_impulse(world_impulse: Vector3, world_position: Vector3) -> bool:
	# This is the physical hand-off a future gun can call when it fires. It adds no gun logic,
	# trigger action, projectile, or ammunition behavior to the locomotion profile.
	return (
		is_instance_valid(mounted_body)
		and mounted_body.apply_attachment_impulse(world_impulse, world_position)
	)


func collision_rids_for_body_queries() -> Array[RID]:
	# Future attachments may contain their own physics bodies. Excluding those RIDs from the
	# locomotion body's ground/contact probes prevents a mounted gun or tool from being mistaken
	# for terrain. Providers with custom physics can override this method.
	var result: Array[RID] = []
	var pending: Array[Node] = [self]
	while not pending.is_empty():
		var current = pending.pop_back() as Node
		if current is PhysicsBody3D:
			result.append((current as PhysicsBody3D).get_rid())
		for child: Node in current.get_children():
			pending.append(child)
	return result


func attachment_runtime_state() -> Dictionary:
	return {
		"attachment_type_id": attachment_type_id,
		"attachment_tags": Array(attachment_tags),
		"operational": operational,
		"contributed_mass_kg": (
			maxf(contributed_mass_kg, 0.0) if is_finite(contributed_mass_kg) else 0.0
		),
	}

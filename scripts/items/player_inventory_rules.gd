extends RefCounted
class_name PlayerInventoryRules

const BASE_CAPACITY := 1
const MAX_CAPACITY := 9
const BACKPACK_SLOT := "backpack"
const EYES_SLOT := "eyes"

#######################################################
# Centralizes deterministic player inventory policy shared by clients and the server.
#######################################################

static func make_entry(
	definition: ItemDefinition,
	instance_state: Dictionary = {}
) -> Dictionary:
	if definition == null or definition.resource_path.is_empty():
		return {}
	var normalized_state := definition.normalize_instance_state(
		instance_state
		if not instance_state.is_empty()
		else definition.make_default_instance_state()
	)
	return {
		"definition_path": definition.resource_path,
		"instance_state": normalized_state,
	}


static func get_definition(entry: Dictionary) -> ItemDefinition:
	var definition_path := str(entry.get("definition_path", ""))
	if definition_path.is_empty():
		return null
	var definition := load(definition_path)
	return definition as ItemDefinition


static func get_equippable_definition(
	entry: Dictionary
) -> EquippableItemDefinition:
	return get_definition(entry) as EquippableItemDefinition


static func get_capacity(equipment: Dictionary) -> int:
	var backpack_entry := equipment.get(BACKPACK_SLOT, {}) as Dictionary
	var backpack := get_definition(backpack_entry) as BackpackDefinition
	if backpack == null:
		return BASE_CAPACITY
	return clampi(backpack.inventory_capacity, BASE_CAPACITY, MAX_CAPACITY)


static func can_fit(item_count: int, equipment: Dictionary) -> bool:
	return item_count >= 0 and item_count <= get_capacity(equipment)


static func to_public_entry(entry: Dictionary) -> Dictionary:
	var definition := get_definition(entry)
	if definition == null:
		return {}

	var result := {
		"definition_path": definition.resource_path,
		"display_name": definition.display_name,
		"inventory_code": definition.get_inventory_code(),
	}
	var instance_state: Dictionary = entry.get("instance_state", {})
	var public_state := definition.get_public_instance_state(instance_state)
	if not public_state.is_empty():
		result["instance_state"] = public_state
	var status_text := definition.get_inventory_status_text(instance_state)
	if not status_text.is_empty():
		result["status_text"] = status_text
	var equippable := definition as EquippableItemDefinition
	if equippable != null:
		result["equipment_slot"] = str(equippable.equipment_slot)
	return result

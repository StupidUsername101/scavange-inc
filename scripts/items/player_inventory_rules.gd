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
	var backpack_entry: Dictionary = SafeVariant.dictionary_copy(
		equipment.get(BACKPACK_SLOT, {}),
		false
	)
	var backpack: BackpackDefinition = get_definition(backpack_entry) as BackpackDefinition
	if backpack == null:
		return BASE_CAPACITY
	return clampi(backpack.inventory_capacity, BASE_CAPACITY, MAX_CAPACITY)


static func can_fit(item_count: int, equipment: Dictionary) -> bool:
	return item_count >= 0 and item_count <= get_capacity(equipment)


static func sanitize_public_inventory(value: Variant) -> Dictionary:
	var source: Dictionary = SafeVariant.dictionary_copy(value, false)
	var capacity: int = clampi(
		SafeVariant.integral_int_or(source.get("capacity", BASE_CAPACITY), BASE_CAPACITY),
		BASE_CAPACITY,
		MAX_CAPACITY
	)
	var selected_slot: int = clampi(
		SafeVariant.integral_int_or(source.get("selected_slot", 0), 0),
		0,
		maxi(capacity - 1, 0)
	)
	var entries: Array[Dictionary] = []
	var entries_value: Variant = source.get("entries", [])
	if entries_value is Array:
		for entry_value: Variant in (entries_value as Array):
			# Preserve slot indices even when one network entry is malformed. Replacing only that slot
			# with an empty record is safer than shifting every later item toward selected_slot.
			entries.append(_sanitize_public_entry(entry_value))
	var equipment: Dictionary = {}
	var equipment_value: Variant = source.get("equipment", {})
	if equipment_value is Dictionary:
		for slot_value: Variant in (equipment_value as Dictionary).keys():
			var entry: Dictionary = _sanitize_public_entry(
				(equipment_value as Dictionary)[slot_value]
			)
			if not entry.is_empty():
				equipment[str(slot_value)] = entry
	return {
		"capacity": capacity,
		"selected_slot": selected_slot,
		"entries": entries,
		"equipment": equipment,
	}


static func _sanitize_public_entry(value: Variant) -> Dictionary:
	var entry: Dictionary = SafeVariant.dictionary_copy(value)
	if entry.is_empty():
		return {}
	if entry.has("instance_state") and not (entry["instance_state"] is Dictionary):
		entry.erase("instance_state")
	return entry


static func to_public_entry(entry: Dictionary) -> Dictionary:
	var definition := get_definition(entry)
	if definition == null:
		return {}

	var result := {
		"definition_path": definition.resource_path,
		"display_name": definition.display_name,
		"inventory_code": definition.get_inventory_code(),
	}
	var instance_state: Dictionary = SafeVariant.dictionary_copy(
		entry.get("instance_state", {}),
		false
	)
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

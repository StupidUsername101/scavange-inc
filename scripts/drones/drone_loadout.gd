@tool
class_name DroneLoadout
extends Resource

#######################################################
# Implements the drone loadout subsystem and keeps its gameplay data and behavior in one
# focused script.
#######################################################

@export var core: DroneCoreDefinition
@export var battery: DroneBatteryDefinition
@export var propellers: Array[DronePropellerDefinition] = []
@export var ai_chips: Array[DroneAIChipDefinition] = []
@export var attachments: Array[DroneAttachmentDefinition] = []


func install_core(value: DroneCoreDefinition) -> void:
	core = value
	_trim_unsupported_propellers()
	_trim_unsupported_ai_chips()
	_trim_unsupported_attachments()


func remove_core() -> void:
	core = null
	ai_chips.clear()
	attachments.clear()


func install_battery(value: DroneBatteryDefinition) -> void:
	battery = value


func remove_battery() -> void:
	battery = null


func install_propeller(
	slot_index: int,
	value: DronePropellerDefinition
) -> bool:
	if slot_index < 0:
		return false
	if core != null and slot_index >= core.propeller_slot_count:
		return false

	while propellers.size() <= slot_index:
		propellers.append(null)

	propellers[slot_index] = value
	return true


func remove_propeller(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < propellers.size():
		propellers[slot_index] = null


func get_propeller(slot_index: int) -> DronePropellerDefinition:
	if slot_index < 0 or slot_index >= propellers.size():
		return null
	if core != null and slot_index >= core.propeller_slot_count:
		return null

	return propellers[slot_index]


func install_ai_chip(
	slot_index: int,
	value: DroneAIChipDefinition
) -> bool:
	if core == null or slot_index < 0 or slot_index >= core.ai_chip_slot_count:
		return false

	while ai_chips.size() <= slot_index:
		ai_chips.append(null)

	ai_chips[slot_index] = value
	return true


func remove_ai_chip(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < ai_chips.size():
		ai_chips[slot_index] = null


func get_ai_chip(slot_index: int) -> DroneAIChipDefinition:
	if (
		core == null
		or slot_index < 0
		or slot_index >= core.ai_chip_slot_count
		or slot_index >= ai_chips.size()
	):
		return null
	return ai_chips[slot_index]


func get_ai_chip_presence() -> Array[bool]:
	var result: Array[bool] = []
	var slot_count = core.ai_chip_slot_count if core != null else 0
	for slot_index in range(slot_count):
		result.append(get_ai_chip(slot_index) != null)
	return result


func install_attachment(
	slot_index: int,
	value: DroneAttachmentDefinition
) -> bool:
	if core == null or slot_index < 0 or slot_index >= core.attachment_slot_count:
		return false
	while attachments.size() <= slot_index:
		attachments.append(null)
	attachments[slot_index] = value
	return true


func remove_attachment(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < attachments.size():
		attachments[slot_index] = null


func get_attachment(slot_index: int) -> DroneAttachmentDefinition:
	if (
		core == null
		or slot_index < 0
		or slot_index >= core.attachment_slot_count
		or slot_index >= attachments.size()
	):
		return null
	return attachments[slot_index]


func get_attachment_presence() -> Array[bool]:
	var result: Array[bool] = []
	var slot_count = core.attachment_slot_count if core != null else 0
	for slot_index in range(slot_count):
		result.append(get_attachment(slot_index) != null)
	return result


func find_attachment_slots_with_capability(
	capability: StringName
) -> Array[int]:
	var result: Array[int] = []
	var slot_count = core.attachment_slot_count if core != null else 0
	for slot_index in range(slot_count):
		var attachment := get_attachment(slot_index)
		if attachment != null and attachment.provides_capability(capability):
			result.append(slot_index)
	return result


func supports_propeller_slot(slot_index: int) -> bool:
	if slot_index < 0:
		return false
	return (
		slot_index < core.propeller_slot_count
		if core != null
		else slot_index < propellers.size()
	)


func get_total_mass() -> float:
	var result := core.get_mass() if core != null else 0.0
	if battery != null:
		result += battery.get_mass()

	for propeller in propellers:
		if propeller != null:
			result += propeller.get_mass()

	if core != null:
		for slot_index in range(core.ai_chip_slot_count):
			var chip := get_ai_chip(slot_index)
			if chip != null:
				result += chip.get_mass()
		for slot_index in range(core.attachment_slot_count):
			var attachment := get_attachment(slot_index)
			if attachment != null:
				result += attachment.get_mass()

	return maxf(result, 0.001)


func get_total_propeller_power_demand() -> float:
	var result := 0.0
	if core == null:
		return result

	for slot_index in range(mini(propellers.size(), core.propeller_slot_count)):
		var propeller := propellers[slot_index]
		if propeller != null:
			result += maxf(propeller.max_power_draw, 0.0)

	return result


func get_propeller_presence() -> Array[bool]:
	var result: Array[bool] = []
	var slot_count := propellers.size()
	if core != null:
		slot_count = maxi(slot_count, core.propeller_slot_count)

	for slot_index in range(slot_count):
		result.append(get_propeller(slot_index) != null)

	return result


func get_propeller_definition_paths() -> Array[String]:
	var result: Array[String] = []
	var slot_count := propellers.size()
	if core != null:
		slot_count = maxi(slot_count, core.propeller_slot_count)

	for slot_index in range(slot_count):
		var propeller := get_propeller(slot_index)
		result.append(definition_path(propeller))
	return result


func get_ai_chip_definition_paths() -> Array[String]:
	var result: Array[String] = []
	var slot_count = core.ai_chip_slot_count if core != null else 0
	for slot_index in range(slot_count):
		var chip := get_ai_chip(slot_index)
		result.append(definition_path(chip))
	return result


func get_attachment_definition_paths() -> Array[String]:
	var result: Array[String] = []
	var slot_count = core.attachment_slot_count if core != null else 0
	for slot_index in range(slot_count):
		var attachment := get_attachment(slot_index)
		result.append(definition_path(attachment))
	return result


static func definition_path(part: DronePartDefinition) -> String:
	# Runtime/creator copies are detached Resources. The shared body-part helper preserves their
	# authored .tres identity through deep copies and snapshot restore.
	return MLBodyPartContract.resource_source_path(part)


func _trim_unsupported_propellers() -> void:
	var supported_count = core.propeller_slot_count if core != null else 0
	if propellers.size() > supported_count:
		propellers.resize(supported_count)


func _trim_unsupported_ai_chips() -> void:
	var supported_count = core.ai_chip_slot_count if core != null else 0
	if ai_chips.size() > supported_count:
		ai_chips.resize(supported_count)


func _trim_unsupported_attachments() -> void:
	var supported_count = core.attachment_slot_count if core != null else 0
	if attachments.size() > supported_count:
		attachments.resize(supported_count)

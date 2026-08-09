class_name MLBodyPreset
extends RefCounted

#######################################################
# Immutable built-in/template record consumed by the future model-body creator. A preset is only
# a convenient starting point: selecting it creates a fresh editable MLBodyBuildDraft. Neural
# dimensions remain unfrozen until that draft is explicitly accepted.
#######################################################

var preset_id: StringName = &""
var display_name: String = ""
var description: String = ""
var body_kind: StringName = &"generic"
var _draft_template: MLBodyBuildDraft
var _runtime_template: Resource


func configure(
	id_value: StringName,
	name_value: String,
	description_value: String,
	kind_value: StringName,
	draft_template: MLBodyBuildDraft,
	runtime_template: Resource = null
) -> bool:
	if str(id_value).strip_edges().is_empty() or draft_template == null:
		return false
	if draft_template.core == null or not draft_template.last_error.is_empty():
		return false
	preset_id = id_value
	display_name = name_value.strip_edges()
	description = description_value.strip_edges()
	body_kind = kind_value
	_draft_template = _creator_draft_from(draft_template, kind_value)
	_runtime_template = MLBodyPartContract.deep_duplicate_resource(runtime_template)
	return _draft_template != null and _draft_template.core != null


func instantiate_draft() -> MLBodyBuildDraft:
	if _draft_template == null:
		return null
	var result: MLBodyBuildDraft = _draft_template.duplicate_editable()
	if result == null:
		return null
	result.core_contract["preset_id"] = str(preset_id)
	result.core_contract["preset_display_name"] = display_name
	return result


func instantiate_manifest() -> MLBodyInterfaceManifest:
	var draft: MLBodyBuildDraft = instantiate_draft()
	return draft.accept_build() if draft != null else null


func runtime_template_copy() -> Resource:
	return MLBodyPartContract.deep_duplicate_resource(_runtime_template)


func _creator_draft_from(source: MLBodyBuildDraft, kind_value: StringName) -> MLBodyBuildDraft:
	if source == null or source.core == null:
		return null
	var creator_core = MLBodyCoreDefinition.new()
	creator_core.core_id = StringName("%s_core" % str(kind_value))
	creator_core.display_name = "%s Core" % (display_name if not display_name.is_empty() else str(kind_value).capitalize())
	var source_physical_core: Resource = source.core
	if source.core is MLBodyCoreDefinition:
		source_physical_core = (source.core as MLBodyCoreDefinition).physical_core
	creator_core.physical_core = MLBodyPartContract.deep_duplicate_resource(source_physical_core)
	for entry: Dictionary in source.slots:
		var source_slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if source_slot == null:
			return null
		var copied_slot: MLBodySlotDefinition = MLBodyPartContract.deep_duplicate_resource(source_slot) as MLBodySlotDefinition
		if copied_slot == null or not creator_core.add_slot(copied_slot):
			return null
	var result = MLBodyBuildDraft.new()
	if not result.configure_from_core(creator_core, str(kind_value)):
		return null
	result.core_contract.merge(source.core_contract.duplicate(true), true)
	result.core_contract["body_kind"] = str(kind_value)
	for index in range(source.slots.size()):
		var source_part: Resource = source.slots[index].get("part") as Resource
		if source_part == null:
			continue
		var target_slot: MLBodySlotDefinition = creator_core.attachment_slots[index]
		var copied_part: Resource = MLBodyPartContract.deep_duplicate_resource(source_part)
		if copied_part == null or not result.equip(target_slot.slot_id, copied_part):
			return null
	return result


func ui_record() -> Dictionary:
	var preview: Dictionary = _draft_template.ui_snapshot() if _draft_template != null else {}
	return {
		"preset_id": str(preset_id),
		"display_name": display_name,
		"description": description,
		"body_kind": str(body_kind),
		"core_name": str(preview.get("core_name", "")),
		"slot_count": int(preview.get("slot_count", 0)),
		"preview_control_count": int(preview.get("preview_control_count", 0)),
		"preview_observation_count": int(preview.get("preview_observation_count", 0)),
	}

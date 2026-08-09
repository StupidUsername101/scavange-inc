class_name MLBodyCreatorPanel
extends Window

signal create_requested(request: Dictionary)

const ORANGE: Color = Color("ffad42")
const GREEN: Color = Color("54e6b1")
const MUTED: Color = Color("a8d8c1")
const EMPTY_KEY: String = "__empty__"
const CURRENT_KEY_PREFIX: String = "__current__:"

var preset_picker: OptionButton
var core_picker: OptionButton
var group_name_input: LineEdit
var description_label: Label
var core_label: Label
var slots_content: VBoxContainer
var summary_label: Label
var status_label: Label
var create_button: Button

var current_preset_id: StringName = &""
var current_draft: MLBodyBuildDraft
var current_body_kind: String = ""
var slot_pickers: Dictionary = {}
var slot_parts: Dictionary = {}
var initial_slot_keys: Dictionary = {}
var changed_slot_ids: Dictionary = {}
var core_parts: Dictionary = {}


func _ready() -> void:
	title = "Model Body Creator"
	size = Vector2i(820, 720)
	min_size = Vector2i(620, 520)
	unresizable = false
	transient = true
	exclusive = false
	close_requested.connect(hide)
	_build_ui()
	_populate_presets()
	hide()


func open_creator() -> void:
	if preset_picker == null:
		return
	if preset_picker.item_count > 0 and current_draft == null:
		_load_preset_at(0)
	# Match the room's other authored windows: restore intended bounds before centering instead of
	# passing them as popup_centered()'s minimum-size argument.
	size = Vector2i(820, 720)
	popup_centered()
	call_deferred("_focus_group_name")


func _focus_group_name() -> void:
	if not visible or group_name_input == null:
		return
	group_name_input.grab_focus()
	group_name_input.select_all()


func _build_ui() -> void:
	var root_panel: PanelContainer = PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(false)
	)
	add_child(root_panel)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root_panel.add_child(root)

	var heading: Label = Label.new()
	heading.text = "MODEL BODY CREATOR"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", ORANGE)
	heading.tooltip_text = "Build a physical worker body from the same serialized parts used by gameplay and training."
	root.add_child(heading)

	var intro: Label = Label.new()
	intro.text = "Choose a body, equip compatible saved parts, then create a fresh worker group from the accepted hardware contract."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", MUTED)
	root.add_child(intro)

	var identity_panel: PanelContainer = PanelContainer.new()
	identity_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	root.add_child(identity_panel)
	var identity: VBoxContainer = VBoxContainer.new()
	identity.add_theme_constant_override("separation", 7)
	identity_panel.add_child(identity)

	var preset_row: HBoxContainer = HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	identity.add_child(preset_row)
	var preset_label: Label = Label.new()
	preset_label.text = "Body preset"
	preset_label.custom_minimum_size.x = 120.0
	preset_row.add_child(preset_label)
	preset_picker = OptionButton.new()
	preset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_picker.item_selected.connect(_on_preset_selected)
	preset_row.add_child(preset_picker)

	var core_row: HBoxContainer = HBoxContainer.new()
	core_row.add_theme_constant_override("separation", 8)
	identity.add_child(core_row)
	var physical_core_label: Label = Label.new()
	physical_core_label.text = "Physical Core"
	physical_core_label.custom_minimum_size.x = 120.0
	core_row.add_child(physical_core_label)
	core_picker = OptionButton.new()
	core_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	core_picker.item_selected.connect(_on_core_selected)
	core_row.add_child(core_picker)

	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	identity.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = "Group name"
	name_label.custom_minimum_size.x = 120.0
	name_row.add_child(name_label)
	group_name_input = LineEdit.new()
	group_name_input.max_length = 48
	group_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(group_name_input)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", MUTED)
	identity.add_child(description_label)
	core_label = Label.new()
	core_label.add_theme_color_override("font_color", GREEN)
	identity.add_child(core_label)

	var parts_heading: Label = Label.new()
	parts_heading.text = "ATTACHED PARTS"
	parts_heading.add_theme_font_size_override("font_size", 17)
	parts_heading.add_theme_color_override("font_color", ORANGE)
	root.add_child(parts_heading)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	slots_content = VBoxContainer.new()
	slots_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_content.add_theme_constant_override("separation", 7)
	scroll.add_child(slots_content)

	var footer_panel: PanelContainer = PanelContainer.new()
	footer_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	root.add_child(footer_panel)
	var footer: VBoxContainer = VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	footer_panel.add_child(footer)
	summary_label = Label.new()
	summary_label.add_theme_color_override("font_color", GREEN)
	footer.add_child(summary_label)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", MUTED)
	footer.add_child(status_label)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	footer.add_child(actions)
	var cancel_button: Button = _creator_button("CANCEL", false)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.pressed.connect(hide)
	actions.add_child(cancel_button)
	create_button = _creator_button("CREATE WORKER GROUP", true)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(_accept_current_build)
	actions.add_child(create_button)


func _populate_presets() -> void:
	preset_picker.clear()
	var presets: Array[MLBodyPreset] = MLBodyPresetLibrary.built_in_presets()
	for preset: MLBodyPreset in presets:
		var index: int = preset_picker.item_count
		preset_picker.add_item(preset.display_name)
		preset_picker.set_item_metadata(index, str(preset.preset_id))
	if preset_picker.item_count > 0:
		preset_picker.select(0)
		_load_preset_at(0)


func _on_preset_selected(index: int) -> void:
	_load_preset_at(index)


func _load_preset_at(index: int) -> void:
	if index < 0 or index >= preset_picker.item_count:
		return
	var preset_id: StringName = StringName(str(preset_picker.get_item_metadata(index)))
	var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(preset_id)
	if preset == null:
		_set_error("The selected body preset could not be loaded.")
		return
	var draft: MLBodyBuildDraft = preset.instantiate_draft()
	if draft == null or draft.core == null or not draft.last_error.is_empty():
		_set_error("The selected body preset could not create an editable draft.")
		return
	current_preset_id = preset_id
	current_draft = draft
	current_body_kind = str(draft.core_contract.get("body_kind", preset.body_kind))
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	slot_parts.clear()
	description_label.text = preset.description
	core_label.text = "Core: %s   •   Family: %s" % [
		str(draft.ui_snapshot().get("core_name", "Core")),
		current_body_kind.replace("_", " ").capitalize(),
	]
	group_name_input.text = "%s group" % preset.display_name
	_populate_core_picker()
	_rebuild_slot_rows()
	_refresh_summary()


func _populate_core_picker() -> void:
	core_picker.clear()
	core_parts.clear()
	var current_core: Resource = _current_physical_core()
	if current_core == null:
		core_picker.add_item("No compatible physical Core")
		core_picker.disabled = true
		return
	core_picker.disabled = false
	var current_key: String = CURRENT_KEY_PREFIX + "core"
	core_parts[current_key] = MLBodyPartContract.deep_duplicate_resource(current_core)
	core_picker.add_item("%s  • current" % MLBodyPartCatalog.display_name(current_core))
	core_picker.set_item_metadata(0, current_key)
	core_picker.select(0)
	var current_source: String = MLBodyPartContract.resource_source_path(current_core)
	for part: Resource in MLBodyPartCatalog.all_parts():
		if not _same_core_family(part, current_core):
			continue
		var source_path: String = MLBodyPartContract.resource_source_path(part)
		if source_path.is_empty() or source_path == current_source or core_parts.has(source_path):
			continue
		core_parts[source_path] = part
		var option_index: int = core_picker.item_count
		var label: String = "%s   [%s]" % [
			MLBodyPartCatalog.display_name(part),
			source_path.get_base_dir().get_file(),
		]
		if part is DroneCoreDefinition and (part as DroneCoreDefinition).propeller_slot_count != 4:
			label += "   • 4-prop trainer required"
		core_picker.add_item(label)
		core_picker.set_item_metadata(option_index, source_path)
		if part is DroneCoreDefinition and (part as DroneCoreDefinition).propeller_slot_count != 4:
			core_picker.set_item_disabled(option_index, true)


func _on_core_selected(index: int) -> void:
	if current_draft == null or index < 0 or index >= core_picker.item_count:
		return
	var key: String = str(core_picker.get_item_metadata(index))
	if key.begins_with(CURRENT_KEY_PREFIX):
		return
	var selected_core: Resource = core_parts.get(key) as Resource
	if selected_core == null:
		_set_error("The selected Core is no longer available.")
		return
	var current_runtime: Resource = MLBodyCreatorRuntimeFactory.runtime_from_draft(
		current_preset_id,
		current_draft,
		changed_slot_ids
	)
	if current_runtime == null:
		_set_error(MLBodyCreatorRuntimeFactory.last_error)
		return
	var next_draft: MLBodyBuildDraft = null
	if current_runtime is DroneLoadout and selected_core is DroneCoreDefinition:
		var drone_loadout: DroneLoadout = current_runtime as DroneLoadout
		drone_loadout.install_core(
			MLBodyPartContract.deep_duplicate_resource(selected_core) as DroneCoreDefinition
		)
		next_draft = DroneMLBodyInterfaceFactory.create_draft(drone_loadout)
	elif current_runtime is TurretLoadout and selected_core is TurretBaseDefinition:
		var turret_loadout: TurretLoadout = current_runtime as TurretLoadout
		turret_loadout.base = (
			MLBodyPartContract.deep_duplicate_resource(selected_core) as TurretBaseDefinition
		)
		next_draft = TurretMLBodyInterfaceFactory.create_draft(turret_loadout)
	else:
		_set_error("This body family does not support swapping that Core yet.")
		_populate_core_picker()
		return
	if next_draft == null or next_draft.core == null or not next_draft.last_error.is_empty():
		_set_error("The selected Core could not rebuild the body slot topology.")
		_populate_core_picker()
		return
	next_draft.core_contract["preset_id"] = str(current_preset_id)
	current_draft = next_draft
	changed_slot_ids.clear()
	initial_slot_keys.clear()
	slot_parts.clear()
	status_label.text = "Core changed. Compatible existing parts were kept where their slots still exist."
	status_label.add_theme_color_override("font_color", MUTED)
	core_label.text = "Core: %s   •   Family: %s" % [
		MLBodyPartCatalog.display_name(_current_physical_core()),
		current_body_kind.replace("_", " ").capitalize(),
	]
	_populate_core_picker()
	_rebuild_slot_rows()
	_refresh_summary()


func _current_physical_core() -> Resource:
	if current_draft == null or current_draft.core == null:
		return null
	if current_draft.core is MLBodyCoreDefinition:
		return (current_draft.core as MLBodyCoreDefinition).physical_core
	return current_draft.core


func _same_core_family(candidate: Resource, current_core: Resource) -> bool:
	if candidate == null or current_core == null:
		return false
	if current_core is DroneCoreDefinition:
		return candidate is DroneCoreDefinition
	if current_core is TurretBaseDefinition:
		return candidate is TurretBaseDefinition
	if current_core is MLRigidCorePartDefinition:
		return candidate is MLRigidCorePartDefinition
	return candidate.get_script() == current_core.get_script()


func _rebuild_slot_rows() -> void:
	for child: Node in slots_content.get_children():
		child.queue_free()
	slot_pickers.clear()
	if current_draft == null:
		return
	for entry: Dictionary in current_draft.slots:
		var slot: MLBodySlotDefinition = entry.get("definition") as MLBodySlotDefinition
		if slot != null:
			_build_slot_row(slot, entry.get("part") as Resource)


func _build_slot_row(slot: MLBodySlotDefinition, current_part: Resource) -> void:
	var slot_id: String = str(slot.slot_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_slot_panel_style()
	)
	slots_content.add_child(panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	panel.add_child(body)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	var label: Label = Label.new()
	label.text = slot.display_name
	label.custom_minimum_size.x = 180.0
	label.add_theme_color_override("font_color", GREEN)
	row.add_child(label)
	var picker: OptionButton = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	slot_pickers[slot_id] = picker
	var part_map: Dictionary = {}
	slot_parts[slot_id] = part_map

	var required: bool = _slot_is_required(slot)
	var editable: bool = _slot_runtime_edit_supported(slot)
	var selected_index: int = -1
	var selected_key: String = EMPTY_KEY
	if not required:
		picker.add_item("Empty")
		picker.set_item_metadata(0, EMPTY_KEY)
		if current_part == null:
			selected_index = 0
	elif current_part == null:
		picker.add_item("Select required part…")
		picker.set_item_metadata(0, EMPTY_KEY)
		picker.set_item_disabled(0, true)
		selected_index = 0
	if current_part != null:
		var current_key: String = CURRENT_KEY_PREFIX + slot_id
		part_map[current_key] = MLBodyPartContract.deep_duplicate_resource(current_part)
		var current_index: int = picker.item_count
		picker.add_item("%s  • current" % MLBodyPartCatalog.display_name(current_part))
		picker.set_item_metadata(current_index, current_key)
		selected_index = current_index
		selected_key = current_key
	var current_source: String = MLBodyPartContract.resource_source_path(current_part)
	if editable:
		for part: Resource in MLBodyPartCatalog.compatible_parts(slot):
			var source_path: String = MLBodyPartContract.resource_source_path(part)
			if source_path.is_empty() or source_path == current_source:
				continue
			if part_map.has(source_path):
				continue
			part_map[source_path] = part
			var option_index: int = picker.item_count
			picker.add_item("%s   [%s]" % [
				MLBodyPartCatalog.display_name(part),
				source_path.get_base_dir().get_file(),
			])
			picker.set_item_metadata(option_index, source_path)
	if selected_index >= 0:
		picker.select(selected_index)
	initial_slot_keys[slot_id] = selected_key
	picker.disabled = not editable
	picker.item_selected.connect(_on_slot_part_selected.bind(slot_id))

	var detail: Label = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color", MUTED)
	var accepted_tags: Array = slot.contract_dictionary().get("accepted_part_tags", [])
	var accepted_tag_strings: PackedStringArray = PackedStringArray()
	for accepted_tag_value: Variant in accepted_tags:
		accepted_tag_strings.append(str(accepted_tag_value))
	detail.text = "Slot: %s   •   accepts: %s" % [
		str(slot.slot_type),
		", ".join(accepted_tag_strings),
	]
	if not editable:
		detail.text += "   •   read-only in this first runtime pass"
		detail.tooltip_text = "This slot is represented by the generic creator contract, but the current four-limb runtime does not yet install arbitrary Core attachments."
	body.add_child(detail)


func _on_slot_part_selected(index: int, slot_id: String) -> void:
	if current_draft == null or not slot_pickers.has(slot_id):
		return
	var picker: OptionButton = slot_pickers[slot_id] as OptionButton
	if picker == null or index < 0 or index >= picker.item_count:
		return
	var key: String = str(picker.get_item_metadata(index))
	var changed: bool = key != str(initial_slot_keys.get(slot_id, EMPTY_KEY))
	if changed:
		changed_slot_ids[slot_id] = true
	else:
		changed_slot_ids.erase(slot_id)
	if key == EMPTY_KEY:
		current_draft.unequip(StringName(slot_id))
	else:
		var part_map: Dictionary = slot_parts.get(slot_id, {})
		var source_part: Resource = part_map.get(key) as Resource
		if source_part == null:
			_set_error("The selected part is no longer available.")
			return
		var copied_part: Resource = MLBodyPartContract.deep_duplicate_resource(source_part)
		if not current_draft.equip(StringName(slot_id), copied_part):
			_set_error(current_draft.last_error)
			return
	status_label.text = ""
	status_label.add_theme_color_override("font_color", MUTED)
	_refresh_summary()


func _refresh_summary() -> void:
	if current_draft == null:
		summary_label.text = "No body selected."
		return
	var snapshot: Dictionary = current_draft.ui_snapshot()
	summary_label.text = "Neural body contract preview: %d controls   •   %d body observations   •   %d slots" % [
		int(snapshot.get("preview_control_count", 0)),
		int(snapshot.get("preview_observation_count", 0)),
		int(snapshot.get("slot_count", 0)),
	]


func _accept_current_build() -> void:
	if current_draft == null:
		_set_error("Choose a body first.")
		return
	var runtime_body: Resource = MLBodyCreatorRuntimeFactory.runtime_from_draft(
		current_preset_id,
		current_draft,
		changed_slot_ids
	)
	if runtime_body == null:
		_set_error(MLBodyCreatorRuntimeFactory.last_error)
		return
	var accepted_draft: MLBodyBuildDraft = current_draft.duplicate_editable()
	var manifest: MLBodyInterfaceManifest = accepted_draft.accept_build()
	if manifest == null:
		_set_error(accepted_draft.last_error)
		return
	var runtime_manifest: MLBodyInterfaceManifest = MLBodyCreatorRuntimeFactory.runtime_manifest(runtime_body)
	if runtime_manifest == null:
		_set_error("The selected parts could not be represented by the training runtime.")
		return
	if runtime_manifest.contract_signature != manifest.contract_signature:
		_set_error("The gameplay body does not reproduce the accepted neural contract; the group was not created.")
		return
	var requested_name: String = group_name_input.text.strip_edges()
	if requested_name.is_empty():
		requested_name = "Model worker group"
	create_requested.emit({
		"preset_id": str(current_preset_id),
		"body_kind": current_body_kind,
		"name": requested_name,
		"runtime_body": runtime_body,
		"body_interface": manifest.to_dictionary(),
		"body_interface_signature": manifest.contract_signature,
	})
	hide()


func _slot_is_required(slot: MLBodySlotDefinition) -> bool:
	return str(slot.slot_type) in ["battery", "propeller", "limb", "gun"]


func _slot_runtime_edit_supported(slot: MLBodySlotDefinition) -> bool:
	if current_body_kind == "articulated_body" and str(slot.slot_type) == "attachment":
		return false
	return true


func _set_error(message: String) -> void:
	status_label.text = message if not message.strip_edges().is_empty() else "Body creation failed."
	status_label.add_theme_color_override("font_color", Color("ff8f7a"))


func _creator_button(text: String, accent: bool) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(accent)
	)
	return button

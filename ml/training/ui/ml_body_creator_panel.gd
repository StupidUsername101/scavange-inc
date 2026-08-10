class_name MLBodyCreatorPanel
extends Window

signal create_requested(request: Dictionary)

const ORANGE: Color = Color("ffad42")
const GREEN: Color = Color("54e6b1")
const MUTED: Color = Color("a8d8c1")
const EMPTY_KEY: String = "__empty__"
const CURRENT_KEY_PREFIX: String = "__current__:"
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(900, 860)
const WINDOW_EDGE_MARGIN_PX: int = 40
const SLOT_SCROLL_MINIMUM_HEIGHT_PX: float = 120.0

var root_panel: PanelContainer
var content_scroll: ScrollContainer
var root_content: VBoxContainer
var slots_scroll: ScrollContainer
var preset_picker: OptionButton
var core_picker: OptionButton
var group_name_input: LineEdit
var description_label: Label
var core_label: Label
var slots_content: VBoxContainer
var summary_label: Label
var status_label: Label
var create_button: Button
var training_settings_panel: PanelContainer
var algorithm_picker: OptionButton
var hidden_width_input: SpinBox
var hidden_depth_input: SpinBox
var worker_count_input: SpinBox
var control_rate_input: SpinBox
var exploration_input: SpinBox
var reward_cardset_picker: OptionButton
var start_training_checkbox: CheckBox

var current_preset_id: StringName = &""
var current_draft: MLBodyBuildDraft
var current_body_kind: String = ""
var slot_pickers: Dictionary = {}
var slot_parts: Dictionary = {}
var initial_slot_keys: Dictionary = {}
var changed_slot_ids: Dictionary = {}
var core_parts: Dictionary = {}
var reward_cardsets: Dictionary = {}
var reward_cardset_library: TrainingRewardCardsetLibrary = TrainingRewardCardsetLibrary.new()
var suppress_training_ui_callbacks: bool = false


func _ready() -> void:
	title = "Model Body Creator"
	size = DEFAULT_WINDOW_SIZE
	min_size = Vector2i(640, 600)
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
	# Derive the first-open size from the realized creator contents. The complete creator is one
	# vertical scroll surface, so every control remains reachable when the content is taller than
	# the game window instead of trapping scrolling inside only the parts list.
	_prepare_creator_window_size()
	if content_scroll != null:
		content_scroll.scroll_vertical = 0
	popup_centered()
	# Window/content minimums settle one frame after the popup becomes visible. Re-apply the
	# content-derived bounds so Godot cannot leave the first open too small or partially off-screen.
	call_deferred("_fit_creator_window_to_content")
	call_deferred("_focus_group_name")


func _creator_viewport_size() -> Vector2i:
	var parent_node: Node = get_parent()
	var parent_viewport: Viewport = (
		parent_node.get_viewport() if parent_node != null else get_tree().root
	)
	return Vector2i(parent_viewport.get_visible_rect().size)


func _update_slot_scroll_minimum() -> void:
	if slots_scroll == null or slots_content == null:
		return
	var natural_height: float = slots_content.get_combined_minimum_size().y
	# The whole creator now owns vertical scrolling. Keep the parts container at its natural height
	# so wheel/trackpad scrolling works from anywhere in the dialog instead of trapping the pointer
	# inside a nested parts-only scroll region.
	slots_scroll.custom_minimum_size.y = maxf(natural_height, SLOT_SCROLL_MINIMUM_HEIGHT_PX)


func _desired_creator_window_size() -> Vector2i:
	var viewport_size: Vector2i = _creator_viewport_size()
	var available_width: int = maxi(viewport_size.x - WINDOW_EDGE_MARGIN_PX, min_size.x)
	var available_height: int = maxi(viewport_size.y - WINDOW_EDGE_MARGIN_PX, min_size.y)
	var content_minimum: Vector2 = (
		root_content.get_combined_minimum_size() if root_content != null else Vector2(float(DEFAULT_WINDOW_SIZE.x), float(DEFAULT_WINDOW_SIZE.y))
	)
	var desired_width: int = maxi(DEFAULT_WINDOW_SIZE.x, int(ceil(content_minimum.x)))
	var desired_height: int = maxi(min_size.y, int(ceil(content_minimum.y)))
	return Vector2i(
		mini(desired_width, available_width),
		mini(desired_height, available_height)
	)


func _prepare_creator_window_size() -> void:
	_update_slot_scroll_minimum()
	size = _desired_creator_window_size()


func _fit_creator_window_to_content() -> void:
	if not visible:
		return
	_update_slot_scroll_minimum()
	var viewport_size: Vector2i = _creator_viewport_size()
	var desired_size: Vector2i = _desired_creator_window_size()
	size = desired_size
	position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _refresh_creator_window_after_layout() -> void:
	if visible:
		_fit_creator_window_to_content()


func _focus_group_name() -> void:
	if not visible or group_name_input == null:
		return
	group_name_input.grab_focus()
	group_name_input.select_all()


func _build_ui() -> void:
	root_panel = PanelContainer.new()
	root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(false)
	)
	add_child(root_panel)

	content_scroll = ScrollContainer.new()
	content_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_scroll.follow_focus = true
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_panel.add_child(content_scroll)

	root_content = VBoxContainer.new()
	root_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_content.add_theme_constant_override("separation", 10)
	content_scroll.add_child(root_content)
	var root: VBoxContainer = root_content

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
	preset_picker.fit_to_longest_item = false
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
	core_picker.fit_to_longest_item = false
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

	_build_training_settings(root)

	var parts_heading: Label = Label.new()
	parts_heading.text = "ATTACHED PARTS"
	parts_heading.add_theme_font_size_override("font_size", 17)
	parts_heading.add_theme_color_override("font_color", ORANGE)
	root.add_child(parts_heading)

	slots_scroll = ScrollContainer.new()
	slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slots_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	slots_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(slots_scroll)
	slots_content = VBoxContainer.new()
	slots_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_content.add_theme_constant_override("separation", 7)
	slots_scroll.add_child(slots_content)

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


func _build_training_settings(root: VBoxContainer) -> void:
	var heading: Label = Label.new()
	heading.text = "TRAINING SETUP"
	heading.add_theme_font_size_override("font_size", 17)
	heading.add_theme_color_override("font_color", ORANGE)
	root.add_child(heading)

	training_settings_panel = PanelContainer.new()
	training_settings_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.creator_panel_style(true)
	)
	root.add_child(training_settings_panel)
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	training_settings_panel.add_child(body)

	var algorithm_row: HBoxContainer = HBoxContainer.new()
	algorithm_row.add_theme_constant_override("separation", 8)
	body.add_child(algorithm_row)
	var algorithm_label: Label = Label.new()
	algorithm_label.text = "Learning algorithm"
	algorithm_label.custom_minimum_size.x = 170.0
	algorithm_row.add_child(algorithm_label)
	algorithm_picker = OptionButton.new()
	algorithm_picker.fit_to_longest_item = false
	algorithm_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	algorithm_picker.item_selected.connect(_on_algorithm_selected)
	algorithm_row.add_child(algorithm_picker)

	hidden_width_input = _add_numeric_setting(
		body,
		"Hidden layer width",
		float(DronePPOMLP.MINIMUM_HIDDEN_WIDTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_WIDTH),
		8.0,
		float(DronePPOActorCritic.HIDDEN_SIZE),
		"Neurons in each hidden layer. Wider networks can represent more complicated control relationships but cost more inference and optimizer work."
	)
	hidden_depth_input = _add_numeric_setting(
		body,
		"Hidden layer depth",
		float(DronePPOMLP.MINIMUM_HIDDEN_DEPTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_DEPTH),
		1.0,
		float(DronePPOActorCritic.HIDDEN_LAYER_COUNT),
		"Number of hidden layers. This topology is fixed when the worker group is created."
	)
	worker_count_input = _add_numeric_setting(
		body,
		"Starting workers",
		1.0,
		48.0,
		1.0,
		8.0,
		"Number of physical workers that initially collect experience for this model."
	)
	control_rate_input = _add_numeric_setting(
		body,
		"Control rate (Hz)",
		2.0,
		60.0,
		1.0,
		20.0,
		"How often the model chooses new actuator commands per simulated second."
	)
	exploration_input = _add_numeric_setting(
		body,
		"Exploration strength",
		0.0,
		2.0,
		0.005,
		0.01,
		"Initial PPO entropy coefficient or SAC entropy temperature. This is available only for drone algorithms in this first creator pass."
	)
	exploration_input.allow_greater = false

	var reward_row: HBoxContainer = HBoxContainer.new()
	reward_row.add_theme_constant_override("separation", 8)
	body.add_child(reward_row)
	var reward_label: Label = Label.new()
	reward_label.text = "Reward preset"
	reward_label.custom_minimum_size.x = 170.0
	reward_label.tooltip_text = "Starting reward-card preset. This uses the same reward-card library as the worker-group tuning UI and can be changed later while the group is paused."
	reward_row.add_child(reward_label)
	reward_cardset_picker = OptionButton.new()
	reward_cardset_picker.fit_to_longest_item = false
	reward_cardset_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_cardset_picker.tooltip_text = reward_label.tooltip_text
	reward_cardset_picker.item_selected.connect(func(_index: int) -> void:
		if current_draft != null and not suppress_training_ui_callbacks:
			_refresh_summary()
	)
	reward_row.add_child(reward_cardset_picker)

	start_training_checkbox = CheckBox.new()
	start_training_checkbox.text = "Start training immediately"
	start_training_checkbox.button_pressed = true
	start_training_checkbox.tooltip_text = "Off creates the worker group paused so you can inspect or tune it before any episode starts."
	body.add_child(start_training_checkbox)
	var branch_note: Label = Label.new()
	branch_note.text = "Fresh bodies start with random weights. Saved-model sources and weight variation stay under BRANCH VARIANT so incompatible body contracts cannot be mixed accidentally."
	branch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	branch_note.add_theme_color_override("font_color", MUTED)
	body.add_child(branch_note)
	for input: SpinBox in [hidden_width_input, hidden_depth_input, worker_count_input, control_rate_input, exploration_input]:
		input.value_changed.connect(func(_value: float) -> void:
			if current_draft != null and not suppress_training_ui_callbacks:
				_refresh_summary()
		)
	start_training_checkbox.toggled.connect(func(_pressed: bool) -> void:
		if current_draft != null and not suppress_training_ui_callbacks:
			_refresh_summary()
	)


func _add_numeric_setting(
	parent: VBoxContainer,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	initial_value: float,
	tooltip: String
) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 170.0
	label.tooltip_text = tooltip
	row.add_child(label)
	var input: SpinBox = SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.value = initial_value
	input.allow_lesser = false
	input.allow_greater = false
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.tooltip_text = tooltip
	row.add_child(input)
	return input


func _on_algorithm_selected(_index: int) -> void:
	if suppress_training_ui_callbacks:
		return
	_refresh_training_settings_for_body(true)
	_refresh_summary()


func _selected_algorithm_id() -> String:
	if algorithm_picker == null or algorithm_picker.selected < 0:
		return "ppo_clip"
	return str(algorithm_picker.get_item_metadata(algorithm_picker.selected))


func _create_algorithm_preview(algorithm_id: String) -> DroneTrainingAlgorithm:
	var config: Dictionary = {}
	if algorithm_id == "ppo_clip" and current_draft != null:
		var preview_draft: MLBodyBuildDraft = current_draft.duplicate_editable()
		var manifest: MLBodyInterfaceManifest = preview_draft.accept_build()
		if manifest != null:
			config["body_interface"] = manifest.to_dictionary()
			config["action_count"] = manifest.control_count()
	return DroneTrainingAlgorithmCatalog.create(algorithm_id, config)


func _algorithm_configuration_control(
	algorithm: DroneTrainingAlgorithm,
	key: String
) -> Dictionary:
	if algorithm == null:
		return {}
	for control: Dictionary in algorithm.configuration_controls():
		if str(control.get("key", "")) == key:
			return control.duplicate(true)
	return {}


func _refresh_training_settings_for_body(reset_values: bool = false) -> void:
	if algorithm_picker == null:
		return
	suppress_training_ui_callbacks = true
	var previous_algorithm: String = _selected_algorithm_id()
	algorithm_picker.clear()
	if current_body_kind == "drone":
		var control_count: int = int(current_draft.ui_snapshot().get("preview_control_count", 0)) if current_draft != null else 0
		var selected_valid_index: int = -1
		var ppo_index: int = -1
		for descriptor: Dictionary in DroneTrainingAlgorithmCatalog.descriptors():
			var index: int = algorithm_picker.item_count
			var descriptor_id: String = str(descriptor.get("id", "ppo_clip"))
			algorithm_picker.add_item(str(descriptor.get("display_name", "Learning algorithm")))
			algorithm_picker.set_item_metadata(index, descriptor_id)
			algorithm_picker.set_item_tooltip(index, str(descriptor.get("description", "")))
			var supported: bool = descriptor_id == "ppo_clip" or control_count == 4
			algorithm_picker.set_item_disabled(index, not supported)
			if descriptor_id == "ppo_clip":
				ppo_index = index
			if descriptor_id == previous_algorithm and supported:
				selected_valid_index = index
		if selected_valid_index >= 0:
			algorithm_picker.select(selected_valid_index)
		elif ppo_index >= 0:
			algorithm_picker.select(ppo_index)
		algorithm_picker.disabled = false
		var algorithm_id: String = _selected_algorithm_id()
		var algorithm_changed: bool = algorithm_id != previous_algorithm
		var preview: DroneTrainingAlgorithm = _create_algorithm_preview(algorithm_id)
		if preview != null:
			var architecture: Dictionary = preview.network_architecture()
			var exploration_key: String = "entropy_coefficient" if algorithm_id == "ppo_clip" else "entropy_temperature"
			var exploration_control: Dictionary = _algorithm_configuration_control(preview, exploration_key)
			if not exploration_control.is_empty():
				exploration_input.min_value = float(exploration_control.get("minimum", 0.0))
				exploration_input.max_value = float(exploration_control.get("maximum", 2.0))
				exploration_input.step = maxf(float(exploration_control.get("step", 0.005)), 0.000001)
				exploration_input.tooltip_text = str(exploration_control.get(
					"tooltip",
					"Initial exploration strength for the selected learning algorithm."
				))
			if reset_values or algorithm_changed:
				hidden_width_input.value = float(architecture.get("hidden_layer_width", DronePPOActorCritic.HIDDEN_SIZE))
				hidden_depth_input.value = float(architecture.get("hidden_layer_depth", DronePPOActorCritic.HIDDEN_LAYER_COUNT))
				worker_count_input.value = float(preview.default_worker_count())
				control_rate_input.value = 1.0 / maxf(float(preview.config_values().get("control_interval_seconds", 0.05)), 0.001)
				exploration_input.value = float(preview.config_values().get(exploration_key, 0.01))
			worker_count_input.max_value = float(preview.maximum_worker_count())
		exploration_input.editable = true
	else:
		algorithm_picker.add_item("Clipped PPO + GAE")
		algorithm_picker.set_item_metadata(0, "ppo_clip")
		algorithm_picker.select(0)
		algorithm_picker.disabled = true
		exploration_input.editable = false
		exploration_input.value = 0.0
		if current_body_kind == "articulated_body":
			worker_count_input.max_value = float(FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT)
			if reset_values:
				hidden_width_input.value = float(FourLimbPPOActorCritic.HIDDEN_SIZE)
				hidden_depth_input.value = float(FourLimbPPOActorCritic.HIDDEN_LAYER_COUNT)
				worker_count_input.value = float(FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT)
				control_rate_input.value = 1.0 / FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS
		elif current_body_kind == "turret":
			worker_count_input.max_value = float(TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT)
			if reset_values:
				hidden_width_input.value = float(TurretPPOActorCritic.HIDDEN_SIZE)
				hidden_depth_input.value = float(TurretPPOActorCritic.HIDDEN_LAYER_COUNT)
				worker_count_input.value = float(TurretTrainingCoordinator.DEFAULT_WORKER_COUNT)
				control_rate_input.value = 1.0 / TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS
	_refresh_reward_cardsets(false)
	suppress_training_ui_callbacks = false


func _reward_body_type() -> String:
	match current_body_kind:
		"drone":
			return TrainingRewardCardsetLibrary.BODY_TYPE_DRONE
		"articulated_body":
			return TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB
		"turret":
			return TrainingRewardCardsetLibrary.BODY_TYPE_TURRET
	return TrainingRewardCardsetLibrary.BODY_TYPE_DRONE


func _default_reward_cardset_id() -> String:
	match _reward_body_type():
		TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB:
			return "builtin:limb_ground"
		TrainingRewardCardsetLibrary.BODY_TYPE_TURRET:
			return "builtin:turret_precision"
	return "builtin:drone_balanced"


func _refresh_reward_cardsets(reset_selection: bool) -> void:
	if reward_cardset_picker == null:
		return
	var previous_id: String = _selected_reward_cardset().get("id", "") if not reset_selection else ""
	reward_cardset_picker.clear()
	reward_cardsets.clear()
	var selected_index: int = -1
	var fallback_index: int = -1
	var default_id: String = _default_reward_cardset_id()
	for record: Dictionary in reward_cardset_library.cardsets_for_body_type(_reward_body_type()):
		var cardset_id: String = str(record.get("id", ""))
		if cardset_id.is_empty():
			continue
		var index: int = reward_cardset_picker.item_count
		reward_cardsets[cardset_id] = record.duplicate(true)
		reward_cardset_picker.add_item(str(record.get("display_name", "Reward preset")))
		reward_cardset_picker.set_item_metadata(index, cardset_id)
		if cardset_id == previous_id:
			selected_index = index
		if cardset_id == default_id:
			fallback_index = index
	if selected_index < 0:
		selected_index = fallback_index if fallback_index >= 0 else (0 if reward_cardset_picker.item_count > 0 else -1)
	if selected_index >= 0:
		reward_cardset_picker.select(selected_index)
	reward_cardset_picker.disabled = reward_cardset_picker.item_count <= 1


func _selected_reward_cardset() -> Dictionary:
	if reward_cardset_picker == null or reward_cardset_picker.selected < 0:
		return {}
	var cardset_id: String = str(reward_cardset_picker.get_item_metadata(reward_cardset_picker.selected))
	var value: Variant = reward_cardsets.get(cardset_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _training_request() -> Dictionary:
	var algorithm_id: String = _selected_algorithm_id()
	var reward_cardset: Dictionary = _selected_reward_cardset()
	var reward_cards_value: Variant = reward_cardset.get("cards", {})
	var reward_cards: Dictionary = (
		(reward_cards_value as Dictionary).duplicate(true)
		if reward_cards_value is Dictionary
		else {}
	)
	return {
		"algorithm_id": algorithm_id,
		"hidden_layer_width": int(round(hidden_width_input.value)),
		"hidden_layer_depth": int(round(hidden_depth_input.value)),
		"worker_count": int(round(worker_count_input.value)),
		"control_rate_hz": maxf(control_rate_input.value, 1.0),
		"exploration_strength": maxf(exploration_input.value, 0.0),
		"reward_cardset_id": str(reward_cardset.get("id", "custom")),
		"reward_cardset_name": str(reward_cardset.get("display_name", "Custom")),
		"reward_cards": reward_cards,
		"start_active": start_training_checkbox.button_pressed,
	}


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
	_refresh_training_settings_for_body(true)
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
	_refresh_training_settings_for_body(false)
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
	# queue_free() removes old rows at the end of the frame. Measure after that point so stale rows
	# do not inflate the next preset/Core's opening size.
	call_deferred("_refresh_creator_window_after_layout")


func _creator_part_label(part: Resource, suffix: String = "") -> String:
	var label_text: String = MLBodyPartCatalog.display_name(part)
	var controls: int = MLBodyPartContract.control_descriptors(part).size()
	var observations: int = MLBodyPartContract.observation_descriptors(part).size()
	if controls > 0 or observations > 0:
		label_text += "  • ML %dC/%dO" % [controls, observations]
	elif part is DroneAttachmentDefinition:
		label_text += "  • passive (no ML controls)"
	if not suffix.is_empty():
		label_text += suffix
	return label_text


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
	picker.fit_to_longest_item = false
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
		picker.add_item(_creator_part_label(current_part, "  • current"))
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
				_creator_part_label(part),
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
	_refresh_training_settings_for_body(false)
	_refresh_summary()


func _refresh_summary() -> void:
	if current_draft == null:
		summary_label.text = "No body selected."
		return
	var snapshot: Dictionary = current_draft.ui_snapshot()
	var algorithm_name: String = (
		algorithm_picker.get_item_text(algorithm_picker.selected)
		if algorithm_picker != null and algorithm_picker.selected >= 0
		else "PPO"
	)
	var reward_name: String = str(_selected_reward_cardset().get("display_name", "Custom rewards"))
	summary_label.text = "Neural body contract: %d controls   •   %d observations   •   %d slots\nTraining: %s   •   hidden %d × %d   •   %d workers   •   %s Hz\nRewards: %s   •   %s" % [
		int(snapshot.get("preview_control_count", 0)),
		int(snapshot.get("preview_observation_count", 0)),
		int(snapshot.get("slot_count", 0)),
		algorithm_name,
		int(round(hidden_width_input.value)),
		int(round(hidden_depth_input.value)),
		int(round(worker_count_input.value)),
		String.num(control_rate_input.value, 0),
		reward_name,
		"starts immediately" if start_training_checkbox.button_pressed else "starts paused",
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
		"training": _training_request(),
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

class_name TurretTrainingRoomUI
extends RefCounted

const BRANCH_DIALOG_SIZE = Vector2i(580, 560)

#######################################################
# Turret-specific presentation/controller plugged into the shared training room. The room
# remains the owner of global selection, camera, plots, and reward workspaces; this class owns
# turret cards, parts, manual servo controls, branching, and the separate model library.
#######################################################

var room
var training: TurretTrainingCoordinator
var registry: TurretModelRegistry

var model_browser: Window
var model_list: ItemList
var model_records: Array[Dictionary] = []
var model_name_edit: LineEdit
var delete_dialog: ConfirmationDialog
var pending_delete_record: Dictionary = {}

var branch_dialog: ConfirmationDialog
var branch_source_group_id = -1
var branch_source_label: Label
var branch_name_edit: LineEdit
var branch_variation_slider: HSlider
var branch_hidden_width_slider: HSlider
var branch_hidden_depth_slider: HSlider
var branch_start_active_checkbox: CheckBox

var tuning_body: VBoxContainer
var tuning_summary_label: Label
var manual_override_checkbox: CheckBox
var manual_yaw_slider: HSlider
var manual_pitch_slider: HSlider
var manual_trigger_checkbox: CheckBox
var part_inputs: Dictionary = {}
var part_edit_controls: Array[Control] = []
var reset_loadout_button: Button
var keyboard_state = {
	"yaw_left": false,
	"yaw_right": false,
	"pitch_up": false,
	"pitch_down": false,
	"trigger": false,
}


func configure(
	new_room,
	new_training: TurretTrainingCoordinator,
	new_registry: TurretModelRegistry
) -> void:
	room = new_room
	training = new_training
	registry = new_registry


func build_model_browser() -> void:
	if room == null or model_browser != null:
		return
	model_browser = Window.new()
	model_browser.title = "Stationary Turret Model Library"
	model_browser.min_size = Vector2i(720, 520)
	model_browser.size = Vector2i(860, 620)
	model_browser.transient = true
	model_browser.exclusive = false
	model_browser.visible = false
	model_browser.close_requested.connect(model_browser.hide)
	room.add_child(model_browser)

	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete Turret Model Permanently"
	delete_dialog.ok_button_text = "Delete Permanently"
	delete_dialog.cancel_button_text = "Cancel"
	delete_dialog.transient = true
	delete_dialog.exclusive = true
	delete_dialog.confirmed.connect(_confirm_delete_model)
	model_browser.add_child(delete_dialog)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	model_browser.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	DroneTrainingRoomPresentation.add_heading(content, "STATIONARY TURRET MODEL LIBRARY", 22)
	var path_label = Label.new()
	path_label.text = registry.globalized_root_path()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.add_theme_color_override("font_color", Color("ffad42"))
	content.add_child(path_label)
	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 7)
	content.add_child(save_row)
	model_name_edit = LineEdit.new()
	model_name_edit.placeholder_text = "Turret model name"
	model_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(model_name_edit)
	var save_button: Button = room._button("SAVE SELECTED", true)
	save_button.pressed.connect(_on_save_selected_pressed)
	save_row.add_child(save_button)
	model_list = ItemList.new()
	model_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_list.allow_reselect = true
	content.add_child(model_list)
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 7)
	actions.add_theme_constant_override("v_separation", 7)
	content.add_child(actions)
	var load_button: Button = room._button("LOAD INTO SELECTED TURRET", true)
	load_button.pressed.connect(_load_selected_model)
	actions.add_child(load_button)
	var delete_button: Button = room._button("DELETE")
	room._set_button_danger(delete_button)
	delete_button.pressed.connect(_request_delete_selected_model)
	actions.add_child(delete_button)
	var close_button: Button = room._button("CLOSE")
	close_button.pressed.connect(model_browser.hide)
	actions.add_child(close_button)
	_build_branch_dialog()


func build_tuning_section(parent: VBoxContainer) -> VBoxContainer:
	if room == null:
		return null
	tuning_body = room._add_section(
		parent,
		"STATIONARY TURRET BODY",
		"Edit the shared rotatable-base and gun loadout used by every turret worker in the selected group. The drive commands request angular acceleration; they never teleport the barrel to an angle.",
		true
	)
	tuning_summary_label = Label.new()
	tuning_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tuning_summary_label.add_theme_color_override("font_color", Color("8de1ff"))
	tuning_body.add_child(tuning_summary_label)

	var manual = room._add_section(
		tuning_body,
		"MANUAL SERVO AIMING",
		"The first turret worker can be driven through the exact same rate-limited yaw, pitch, and trigger path used by the policy. A/D yaw, W/S pitch, and Space fires while manual override is enabled.",
		true
	)
	manual_override_checkbox = CheckBox.new()
	manual_override_checkbox.text = "Manual override"
	manual_override_checkbox.tooltip_text = "Manual turret control\n\nWhen enabled, this group's first turret worker follows these controls and its manually influenced episode is excluded from autonomous scoring."
	manual_override_checkbox.toggled.connect(_set_manual_override)
	manual.add_child(manual_override_checkbox)
	manual_yaw_slider = room._add_slider(
		manual,
		"Yaw drive",
		-1.0,
		1.0,
		0.01,
		0.0,
		"Signed servo drive. The base accelerates toward its authored maximum yaw speed and brakes when released.",
		_on_manual_yaw_changed
	)
	manual_pitch_slider = room._add_slider(
		manual,
		"Pitch drive",
		-1.0,
		1.0,
		0.01,
		0.0,
		"Signed barrel-elevation servo drive. Authored elevation limits stop the barrel and remove outward velocity at the limit.",
		_on_manual_pitch_changed
	)
	manual_trigger_checkbox = CheckBox.new()
	manual_trigger_checkbox.text = "Trigger held"
	manual_trigger_checkbox.tooltip_text = "Manual trigger\n\nThe gun still obeys its trigger threshold, cooldown, projectile speed, spread, and finite range."
	manual_trigger_checkbox.toggled.connect(_on_manual_trigger_toggled)
	manual.add_child(manual_trigger_checkbox)
	var manual_hint = Label.new()
	manual_hint.text = "Keyboard: A / D yaw · W / S pitch · Space fire"
	manual_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	manual_hint.add_theme_color_override("font_color", Color("5ab889"))
	manual.add_child(manual_hint)

	var base_section = room._add_section(
		tuning_body,
		"ROTATABLE BASE PART",
		"Geometry and physical yaw-servo values from TurretBaseDefinition. Pause the group before replacing this private part contract.",
		false
	)
	_add_part_input(base_section, "Base width", "base", "footprint_size:x", 0.20, 4.0, 0.01, " m", "Stationary footprint width.")
	_add_part_input(base_section, "Base height", "base", "footprint_size:y", 0.10, 3.0, 0.01, " m", "Stationary footprint height.")
	_add_part_input(base_section, "Base depth", "base", "footprint_size:z", 0.20, 4.0, 0.01, " m", "Stationary footprint depth.")
	_add_part_input(base_section, "Head radius", "base", "rotating_head_radius_m", 0.05, 2.0, 0.01, " m", "Radius of the rotating yaw head.")
	_add_part_input(base_section, "Head height", "base", "rotating_head_height_m", 0.05, 2.0, 0.01, " m", "Height of the rotating yaw head.")
	_add_part_input(base_section, "Head center height", "base", "head_center_height_m", 0.05, 3.0, 0.01, " m", "Vertical position of the yaw pivot.")
	_add_part_input(base_section, "Maximum yaw speed", "base", "maximum_yaw_speed_degrees_per_second", 1.0, 720.0, 0.5, "°/s", "Maximum physical base rotation speed.")
	_add_part_input(base_section, "Yaw acceleration", "base", "yaw_acceleration_degrees_per_second_squared", 1.0, 2000.0, 0.5, "°/s²", "Acceleration while a yaw command is held.")
	_add_part_input(base_section, "Yaw braking", "base", "yaw_braking_degrees_per_second_squared", 0.0, 2000.0, 0.5, "°/s²", "Passive braking after the command returns to zero.")

	var gun_section = room._add_section(
		tuning_body,
		"GUN & BARREL PART",
		"Pitch-servo limits, barrel geometry, cooldown, projectile ballistics, damage, spread, and range from TurretGunDefinition.",
		false
	)
	_add_part_input(gun_section, "Barrel length", "gun", "barrel_length_m", 0.10, 10.0, 0.01, " m", "Physical barrel length and muzzle offset.")
	_add_part_input(gun_section, "Barrel radius", "gun", "barrel_radius_m", 0.01, 1.0, 0.005, " m", "Physical barrel radius.")
	_add_part_input(gun_section, "Minimum pitch", "gun", "minimum_pitch_degrees", -89.0, 88.0, 0.5, "°", "Lowest allowed barrel elevation.")
	_add_part_input(gun_section, "Maximum pitch", "gun", "maximum_pitch_degrees", -88.0, 89.0, 0.5, "°", "Highest allowed barrel elevation.")
	_add_part_input(gun_section, "Maximum pitch speed", "gun", "maximum_pitch_speed_degrees_per_second", 1.0, 720.0, 0.5, "°/s", "Maximum physical elevation speed.")
	_add_part_input(gun_section, "Pitch acceleration", "gun", "pitch_acceleration_degrees_per_second_squared", 1.0, 2000.0, 0.5, "°/s²", "Acceleration while a pitch command is held.")
	_add_part_input(gun_section, "Pitch braking", "gun", "pitch_braking_degrees_per_second_squared", 0.0, 2000.0, 0.5, "°/s²", "Passive elevation braking after release.")
	_add_part_input(gun_section, "Seconds between shots", "gun", "seconds_between_shots", 0.01, 10.0, 0.01, " s", "Hard firing cooldown.")
	_add_part_input(gun_section, "Projectile speed", "gun", "projectile_speed_mps", 1.0, 1000.0, 1.0, " m/s", "Finite projectile speed used by aiming prediction and actual shots.")
	_add_part_input(gun_section, "Projectile damage", "gun", "projectile_damage", 0.1, 1000.0, 0.1, "", "Damage recorded by the shared combat adapter when a projectile hits.")
	_add_part_input(gun_section, "Maximum range", "gun", "maximum_range_m", 1.0, 1000.0, 0.5, " m", "Projectile lifetime expressed as maximum travelled distance.")
	_add_part_input(gun_section, "Spread", "gun", "spread_degrees", 0.0, 20.0, 0.01, "°", "Random angular shot spread.")
	_add_part_input(gun_section, "Trigger threshold", "gun", "trigger_threshold", 0.0, 1.0, 0.01, "", "Minimum trigger command required to fire when cooldown is ready.")
	reset_loadout_button = room._button("RESTORE TURRET PRESET")
	reset_loadout_button.tooltip_text = "Restore Stationary Turret preset\n\nPause the selected turret group, then replace its private base and gun with a fresh Stationary Turret creator preset."
	reset_loadout_button.pressed.connect(_reset_selected_loadout)
	tuning_body.add_child(reset_loadout_button)
	part_edit_controls.append(reset_loadout_button)
	return tuning_body


func add_group_cards(parent: VBoxContainer) -> void:
	if parent == null:
		return
	for group: Dictionary in training.groups:
		_add_group_card(parent, group)


func refresh_group_cards() -> void:
	for group: Dictionary in training.groups:
		var trainer = group.get("trainer") as TurretPPOTrainer
		var active = bool(group.get("active", false))
		var optimizing = bool(group.get("optimizer_waiting", false))
		var button = group.get("card_button") as Button
		if button != null and trainer != null:
			var state = (
				"running · optimizing"
				if active and optimizing
				else ("running" if active else ("optimizer finishing" if optimizing else "paused"))
			)
			button.text = "%s %s  ·  %s\nTURRET PPO  ·  %s  ·  update %d  ·  %s" % [
				("▼" if int(group["group_id"]) == int(room.selected_turret_group_id) else "▶"),
				str(group["name"]),
				state,
				room._network_architecture_compact_text(trainer.network_architecture()),
				trainer.update_count,
				room.group_episode_progress_text(group, "turret"),
			]
			button.add_theme_color_override("font_color", group["color"])
		var evaluation_candidate_id: int = (
			trainer.pending_evaluation_candidate_id() if trainer != null else -1
		)
		var evaluation_label = group.get("candidate_evaluation_label") as Label
		if evaluation_label != null:
			evaluation_label.visible = evaluation_candidate_id >= 0
			if evaluation_candidate_id >= 0:
				evaluation_label.text = room.candidate_evaluation_compact_text(group)
				evaluation_label.tooltip_text = room.candidate_evaluation_tooltip(group)
		var best = group.get("best_score_label") as Label
		if best != null and trainer != null:
			var best_summary = trainer.best_selection_summary()
			if best_summary.is_empty():
				best.text = "BEST —"
				best.tooltip_text = (
					"No policy has passed fixed-seed verification yet. The current frozen candidate is being evaluated; this label becomes a numeric BEST score only after a candidate is promoted."
					if evaluation_candidate_id >= 0
					else "No policy has passed fixed-seed verification yet. BEST is reserved for a policy that completed the deterministic evaluation suite."
				)
			else:
				best.text = "BEST %+.3f/s" % float(best_summary.get("selection_score", 0.0))
				best.tooltip_text = "Best fixed-seed-verified policy score for this group. Training-candidate scores are separate and do not become BEST until deterministic evaluation promotes them."
		var pause = group.get("pause_button") as Button
		if pause != null:
			pause.text = "Ⅱ" if active else "▶"
			pause.tooltip_text = "Pause this turret group." if active else "Resume this turret group."
		var activity = group.get("activity_label") as Label
		if activity != null:
			activity.visible = active
			activity.text = str(room.GROUP_ACTIVITY_FRAMES[room.group_activity_animation_frame])
		var worker_label = group.get("worker_label") as Label
		if worker_label != null:
			worker_label.text = "Turrets: %d" % int(group.get("worker_count", 1))
		var add_worker_button = group.get("add_worker_button") as Button
		if add_worker_button != null:
			add_worker_button.disabled = (
				not training.group_can_add_worker(int(group.get("group_id", -1)))
				or room.turret_placement_active
			)
		var reward_label = group.get("reward_label") as Label
		if reward_label != null:
			var enabled_count = 0
			var card_count = 0
			for reward_card: FourLimbRewardCard in (group["reward_deck"] as TurretRewardDeck).card_list():
				card_count += 1
				if reward_card.enabled:
					enabled_count += 1
			reward_label.text = "Reward cards: %d/%d enabled" % [enabled_count, card_count]
		_refresh_rolling_button(group)


func selected_group() -> Dictionary:
	return training.group_by_id(int(room.selected_turret_group_id)) if room != null else {}


func open_model_browser() -> void:
	if model_browser == null:
		build_model_browser()
	var group = selected_group()
	if model_name_edit != null and not group.is_empty():
		model_name_edit.text = str(group["name"])
	model_records = registry.list_models()
	model_list.clear()
	for record: Dictionary in model_records:
		model_list.add_item("%s · %s · rev %d" % [
			registry.display_name(record),
			str(record.get("algorithm", TurretPPOTrainer.ALGORITHM_ID)),
			int(record.get("checkpoint_revision", 1)),
		])
	model_browser.popup_centered()


func save_group(
	group_id: int,
	requested_name: String = "",
	use_best_policy: bool = false
) -> Dictionary:
	var group = training.group_by_id(group_id)
	if group.is_empty():
		_set_status("Select a turret worker group before saving.")
		return {}
	var checkpoint = training.save_checkpoint(group_id, use_best_policy)
	var room_settings: Dictionary = checkpoint.get("room_settings", {})
	room_settings["target_handler"] = room._target_handler_configuration_for_group(group_id)
	checkpoint["room_settings"] = room_settings
	var model_name = requested_name.strip_edges()
	if model_name.is_empty():
		model_name = str(group["name"])
	var overwrite_enabled = bool(group.get("overwrite_saved_versions", true))
	var rolling_version_id = str(group.get("rolling_version_id", ""))
	var record: Dictionary = {}
	var overwritten = false
	if overwrite_enabled and not rolling_version_id.is_empty():
		var rolling_record = registry.get_version(rolling_version_id)
		if (
			rolling_record.is_empty()
			or not room._rolling_record_matches_requested_name(rolling_record, model_name)
			or str(rolling_record.get("hardware_signature", ""))
			!= str(checkpoint.get("hardware_signature", ""))
		):
			group["rolling_version_id"] = ""
			rolling_version_id = ""
		else:
			record = registry.overwrite_checkpoint(rolling_version_id, checkpoint)
			overwritten = not record.is_empty()
	if record.is_empty() and rolling_version_id.is_empty():
		record = registry.save_checkpoint(model_name, checkpoint)
	if overwrite_enabled and not record.is_empty():
		group["rolling_version_id"] = str(record.get("version_id", ""))
	if record.is_empty():
		_set_status(registry.last_error)
	else:
		_set_status("%s %s." % ["Updated" if overwritten else "Saved", registry.display_name(record)])
	_refresh_rolling_button(group)
	return record


func set_group_active(group_id: int, active: bool) -> void:
	var group = training.group_by_id(group_id)
	if group.is_empty() or bool(group.get("active", false)) == active:
		return
	if not active and int(room.selected_turret_group_id) == group_id:
		release_manual_keys()
	if not training.set_group_active(
		group_id,
		active,
		room._target_objective_position(group_id),
		room.episode_duration,
		room.ARENA_SIZE
	):
		_set_status(training.last_error)
		return
	room._rebuild_group_cards()
	room._refresh_selected_group_controls()
	room._refresh_all_groups_pause_button()
	_set_status("%s %s." % [str(group["name"]), "resumed" if active else "paused"])


func set_group_worker_count(group_id: int, requested_count: int) -> void:
	var group = training.group_by_id(group_id)
	if group.is_empty():
		return
	var count = clampi(requested_count, 1, TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT)
	training.apply_worker_count_now(
		group_id,
		count,
		room._target_objective_position(group_id),
		room.episode_duration,
		room.ARENA_SIZE
	)
	room._refresh_group_card_texts()
	room._refresh_selected_group_controls()
	_set_status("%s now uses %d stationary turret workers." % [str(group["name"]), count])


func set_group_overwrite(group_id: int, enabled: bool) -> void:
	var group = training.group_by_id(group_id)
	if group.is_empty():
		return
	group["overwrite_saved_versions"] = enabled
	group["rolling_version_id"] = ""
	_refresh_rolling_button(group)
	_set_status(
		"%s will keep one newest group-owned turret model. Its source checkpoint remains untouched."
		% str(group.get("name", "Turret group"))
		if enabled
		else "%s will create a new numbered turret-model version for every save."
		% str(group.get("name", "Turret group"))
	)


func remove_group(group_id: int) -> void:
	var existing = training.group_by_id(group_id)
	if existing.is_empty():
		return
	if bool(room.turret_placement_active) and int(room.turret_placement_group_id) == group_id:
		room._cancel_turret_placement("", false)
	if int(room.selected_turret_group_id) == group_id:
		release_manual_keys()
	var replacement_parent_id = int(existing.get("parent_group_id", -1))
	for child_value: Variant in training.groups:
		if not (child_value is Dictionary):
			continue
		var child = child_value as Dictionary
		if int(child.get("parent_group_id", -1)) == group_id:
			child["parent_group_id"] = replacement_parent_id
	room._clear_turret_target_references_to_group(group_id)
	var group = training.remove_group(group_id)
	if group.is_empty():
		return
	room._remove_action_trace_source("turret", group_id)
	room._remove_group_target_handler(group_id)
	if int(room.selected_turret_group_id) == group_id:
		room.selected_turret_group_id = -1
	room._rebuild_group_cards()
	room._refresh_selected_group_controls()
	room._refresh_target_controls_for_selection()
	room._rebuild_reward_cards()
	room._apply_selection_highlight()
	room._refresh_all_groups_pause_button()
	room.plots_dirty = true
	_set_status("Removed %s. Saved turret models remain available." % str(group.get("name", "turret group")))


func open_branch_dialog(group_id: int) -> void:
	var source = training.group_by_id(group_id)
	var is_branch: bool = not source.is_empty()
	if branch_dialog == null:
		return
	branch_source_group_id = group_id if is_branch else -1
	branch_dialog.title = (
		"New Stationary Turret Branch" if is_branch else "New Stationary Turret Model"
	)
	branch_dialog.ok_button_text = "Create Branch" if is_branch else "Create Model"
	if branch_source_label != null:
		branch_source_label.text = (
			"Policy source: live turret weights from %s\nThe PPO settings, reward cards, private base/gun loadout, target configuration, and control rate are copied into an independent child." % str(source.get("name", "turret group"))
			if is_branch
			else "Policy source: fresh random stationary-turret model\nChoose the actor/critic hidden width and depth before the network is constructed."
		)
	branch_name_edit.text = room._unique_group_name(
		"%s variant" % str(source["name"]) if is_branch else "Turret worker group %d" % (room.group_counter + 1),
		-1
	)
	branch_variation_slider.editable = is_branch
	branch_variation_slider.value = room.DEFAULT_BRANCH_WEIGHT_VARIATION if is_branch else 0.0
	var source_trainer = source.get("trainer") as TurretPPOTrainer
	var architecture: Dictionary = (
		source_trainer.network_architecture()
		if is_branch and source_trainer != null
		else {
			"hidden_layer_width": TurretPPOActorCritic.HIDDEN_SIZE,
			"hidden_layer_depth": TurretPPOActorCritic.HIDDEN_LAYER_COUNT,
		}
	)
	branch_hidden_width_slider.editable = not is_branch
	branch_hidden_width_slider.value = float(architecture.get(
		"hidden_layer_width", TurretPPOActorCritic.HIDDEN_SIZE
	))
	branch_hidden_depth_slider.editable = not is_branch
	branch_hidden_depth_slider.value = float(architecture.get(
		"hidden_layer_depth", TurretPPOActorCritic.HIDDEN_LAYER_COUNT
	))
	branch_start_active_checkbox.button_pressed = true
	# popup_centered(size) treats the argument as a minimum, not an exact size. Restore the
	# authored bounds explicitly so a previous content/minimum-size calculation cannot leak
	# into the first popup.
	branch_dialog.size = BRANCH_DIALOG_SIZE
	branch_dialog.popup_centered()
	# On the first popup Godot may apply the newly-realized custom-content minimum after
	# popup_centered(), producing a tall one-frame/first-open window. Re-apply the authored
	# window bounds after layout, matching the shared room's other top-level dialogs.
	call_deferred("_normalize_branch_dialog_window")
	call_deferred("_focus_branch_name")


func _normalize_branch_dialog_window() -> void:
	if branch_dialog == null or not branch_dialog.visible or room == null:
		return
	var viewport_size = Vector2i(room.get_viewport().get_visible_rect().size)
	var desired_size = Vector2i(
		mini(BRANCH_DIALOG_SIZE.x, maxi(viewport_size.x - 40, branch_dialog.min_size.x)),
		mini(BRANCH_DIALOG_SIZE.y, maxi(viewport_size.y - 40, branch_dialog.min_size.y))
	)
	branch_dialog.size = desired_size
	branch_dialog.position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _focus_branch_name() -> void:
	if branch_dialog == null or not branch_dialog.visible or branch_name_edit == null:
		return
	branch_name_edit.grab_focus()
	branch_name_edit.select_all()


func refresh_selection() -> void:
	if tuning_body == null:
		return
	var group = selected_group()
	var has_group = not group.is_empty()
	room._set_section_body_card_visible(tuning_body, has_group)
	if not has_group:
		if tuning_summary_label != null:
			tuning_summary_label.text = "Select a stationary turret group."
		return
	var loadout = group.get("turret_loadout") as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		if tuning_summary_label != null:
			tuning_summary_label.text = "This turret body is incomplete; choose or build a valid preset/body."
		return
	var trainer = group.get("trainer") as TurretPPOTrainer
	tuning_summary_label.text = "%s + %s · %.1f kg · %.0f health · 3 outputs (yaw drive, pitch drive, trigger) · %d features" % [
		loadout.base.display_name,
		loadout.gun.display_name,
		loadout.total_mass_kg(),
		loadout.maximum_health(),
		TurretMLFeatureEncoder.FEATURE_COUNT,
	]
	room.suppress_ui_callbacks = true
	manual_override_checkbox.set_pressed_no_signal(bool(group.get("manual_override_enabled", false)))
	manual_yaw_slider.set_value_no_signal(float(group.get("manual_yaw_drive", 0.0)))
	manual_pitch_slider.set_value_no_signal(float(group.get("manual_pitch_drive", 0.0)))
	manual_trigger_checkbox.set_pressed_no_signal(float(group.get("manual_trigger", 0.0)) >= 0.5)
	for key: String in part_inputs:
		var input = part_inputs[key] as SpinBox
		if input == null:
			continue
		var parts = key.split(":", false, 1)
		if parts.size() != 2:
			continue
		input.set_value_no_signal(_read_part_value(loadout, parts[0], parts[1]))
	room.suppress_ui_callbacks = false
	var editable = not bool(group.get("active", false))
	for control: Control in part_edit_controls:
		if control is SpinBox:
			(control as SpinBox).editable = editable
		elif control is Button:
			(control as Button).disabled = not editable
	manual_override_checkbox.disabled = false
	manual_yaw_slider.editable = bool(group.get("manual_override_enabled", false))
	manual_pitch_slider.editable = bool(group.get("manual_override_enabled", false))
	manual_trigger_checkbox.disabled = not bool(group.get("manual_override_enabled", false))
	if trainer == null:
		return


func handle_unhandled_input(event: InputEvent) -> bool:
	var group = selected_group()
	if group.is_empty() or not bool(group.get("manual_override_enabled", false)):
		return false
	var key = event as InputEventKey
	if key == null or key.echo:
		return false
	if _text_control_has_focus():
		return false
	var state_key = ""
	match key.keycode:
		KEY_A:
			state_key = "yaw_left"
		KEY_D:
			state_key = "yaw_right"
		KEY_W:
			state_key = "pitch_up"
		KEY_S:
			state_key = "pitch_down"
		KEY_SPACE:
			state_key = "trigger"
		_:
			return false
	keyboard_state[state_key] = key.pressed
	_apply_keyboard_controls(group)
	return true


func release_manual_keys() -> void:
	for key: String in keyboard_state:
		keyboard_state[key] = false
	var group = selected_group()
	if not group.is_empty() and bool(group.get("manual_override_enabled", false)):
		training.set_manual_controls(int(group["group_id"]), 0.0, 0.0, 0.0)


func selected_status_text() -> String:
	var group = selected_group()
	if group.is_empty():
		return ""
	var trainer = group.get("trainer") as TurretPPOTrainer
	if trainer == null:
		return "Turret trainer unavailable."
	var active = bool(group.get("active", false))
	var optimizing = bool(group.get("optimizer_waiting", false))
	var state = (
		"training · optimizing"
		if active and optimizing
		else ("training" if active else ("optimizer finishing" if optimizing else "paused"))
	)
	return "%s · PPO update %d · episode %d" % [state, trainer.update_count, int(group.get("episode", 0))]


func selected_status_tooltip() -> String:
	var group = selected_group()
	if group.is_empty():
		return ""
	var trainer = group.get("trainer") as TurretPPOTrainer
	if trainer == null:
		return "Turret trainer unavailable."
	var metrics: Dictionary = trainer.last_metrics
	return "Stationary turret training\n%d turret%s · %d environment steps · %d completed episodes\nLast mean reward: %+.3f · best mean reward: %s\nRollout samples: %d · actor loss: %+.4f · value loss: %+.4f\nConfirmed hits and finite-speed projectile damage are rewarded; unsafe shots, misses, abrupt servo changes, and damage received are punished.\n\nInput audit\n%s" % [
		int(group.get("worker_count", 1)),
		"" if int(group.get("worker_count", 1)) == 1 else "s",
		trainer.environment_steps,
		trainer.completed_episodes,
		float(group.get("last_mean_reward", 0.0)),
		String.num(float(group.get("best_mean_reward", 0.0)), 3) if is_finite(float(group.get("best_mean_reward", -INF))) else "—",
		int(metrics.get("rollout_samples", trainer.rollout.size())),
		float(metrics.get("actor_loss", 0.0)),
		float(metrics.get("value_loss", 0.0)),
		trainer.diagnostic_status_text(),
	]


func _add_group_card(parent: VBoxContainer, group: Dictionary) -> void:
	var group_id = int(group["group_id"])
	var selected = group_id == int(room.selected_turret_group_id)
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = float(group.get("card_minimum_height", 0.0))
	card.add_theme_stylebox_override("panel", DroneTrainingRoomPresentation.scanner_panel_style(selected))
	parent.add_child(card)
	var shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	card.add_child(shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	shell.add_child(header)
	var select_button: Button = room._button("")
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.clip_text = true
	select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select_button.tooltip_text = "Select stationary turret worker group\n\nThis group owns an independent three-output turret policy, private base/gun loadout, rewards, placement, and model history.\nPress F2 while selected to rename it in place."
	select_button.pressed.connect(_on_group_select_pressed.bind(group_id))
	header.add_child(select_button)
	var name_edit = LineEdit.new()
	name_edit.visible = false
	name_edit.text = str(group["name"])
	name_edit.max_length = room.GROUP_NAME_MAX_LENGTH
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 30.0
	name_edit.tooltip_text = "Rename turret group\n\nType the new name here.\nEnter saves it; Escape restores the old name."
	name_edit.text_submitted.connect(_on_group_name_submitted.bind(group_id))
	name_edit.focus_exited.connect(_on_group_name_focus_exited.bind(group_id))
	name_edit.gui_input.connect(_on_group_name_gui_input.bind(group_id))
	header.add_child(name_edit)
	var candidate_evaluation_label = Label.new()
	candidate_evaluation_label.custom_minimum_size.x = 86.0
	candidate_evaluation_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	candidate_evaluation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	candidate_evaluation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	candidate_evaluation_label.clip_text = true
	candidate_evaluation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	candidate_evaluation_label.add_theme_color_override("font_color", Color("76ddff"))
	candidate_evaluation_label.tooltip_text = "Fixed-seed evaluation\n\nShows frozen-candidate verification progress without replacing the preserved Best score."
	candidate_evaluation_label.visible = false
	header.add_child(candidate_evaluation_label)
	var best_score_label = Label.new()
	best_score_label.custom_minimum_size.x = 112.0
	best_score_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	best_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best_score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best_score_label.clip_text = true
	best_score_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	best_score_label.add_theme_color_override("font_color", Color("54e6b1"))
	best_score_label.tooltip_text = "Best fixed-seed evaluation\n\nShows the best policy that passed deterministic verification. Candidate evaluation is separate until promotion."
	header.add_child(best_score_label)
	var activity_label = Label.new()
	activity_label.custom_minimum_size.x = 30.0
	activity_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	activity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	activity_label.add_theme_color_override("font_color", group["color"])
	activity_label.tooltip_text = "Group activity\n\nAnimated while the turret is running or its PPO model is optimizing."
	header.add_child(activity_label)
	var pause_button: Button = room._button("Ⅱ" if bool(group.get("active", false)) else "▶")
	pause_button.custom_minimum_size = Vector2(34.0, 30.0)
	pause_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_button.pressed.connect(_on_group_pause_pressed.bind(group_id))
	header.add_child(pause_button)
	var worker_row: HBoxContainer = HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 7)
	shell.add_child(worker_row)
	var worker_label: Label = Label.new()
	worker_label.text = "Turrets: %d" % int(group.get("worker_count", 1))
	worker_label.tooltip_text = "Physical turret workers sharing this policy. Each turret has its own arena placement and contributes experience to this group."
	worker_row.add_child(worker_label)
	var add_worker_button: Button = room._button("+")
	add_worker_button.custom_minimum_size = Vector2(30.0, 26.0)
	add_worker_button.tooltip_text = "Add one turret worker\n\nPauses the group temporarily and lets you place the new turret on the floor or an obstacle top. It then shares this group's policy and training history."
	add_worker_button.pressed.connect(room._begin_add_turret_worker.bind(group_id))
	worker_row.add_child(add_worker_button)
	var details = VBoxContainer.new()
	details.visible = selected
	details.add_theme_constant_override("separation", 6)
	shell.add_child(details)
	var identity = Label.new()
	var turret_card_trainer: TurretPPOTrainer = group.get("trainer") as TurretPPOTrainer
	var turret_architecture: Dictionary = (
		turret_card_trainer.network_architecture() if turret_card_trainer != null else {}
	)
	identity.text = "STATIONARY TURRET · 3 servo/fire outputs · finite-speed projectiles · PPO · %s" % DroneTrainingRoom._network_architecture_text(turret_architecture)
	identity.add_theme_color_override("font_color", Color("ffad42"))
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(identity)
	var lineage = Label.new()
	lineage.text = "Root model" if int(group.get("parent_group_id", -1)) < 0 else "Child variant · %s%% weight variation" % String.num(float(group.get("branch_weight_variation", 0.0)) * 100.0, 1)
	lineage.add_theme_color_override("font_color", Color("5ab889"))
	details.add_child(lineage)
	var reward_label = Label.new()
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(reward_label)
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	details.add_child(actions)
	var overwrite_button = room.ROLLING_SAVE_BUTTON_SCRIPT.new() as Button
	overwrite_button.toggle_mode = true
	overwrite_button.tooltip_text = "Keep only the newest turret-model save\n\nOff creates numbered versions. On reuses one group-owned rolling version. A loaded or branched source is never overwritten."
	overwrite_button.call("configure", group["color"], bool(group.get("overwrite_saved_versions", true)))
	overwrite_button.toggled.connect(_on_group_overwrite_toggled.bind(group_id))
	actions.add_child(overwrite_button)
	var place_button: Button = room._button("PLACE / MOVE TURRET", true)
	place_button.tooltip_text = "Place this turret in the arena\n\nClick the floor or the upward-facing top of a placed obstacle. The turret keeps this location across episode resets."
	place_button.pressed.connect(room._begin_turret_placement.bind(group_id))
	actions.add_child(place_button)
	var branch_button: Button = room._button("BRANCH VARIANT", true)
	branch_button.pressed.connect(_on_group_branch_pressed.bind(group_id))
	actions.add_child(branch_button)
	var model_button: Button = room._button("MODEL", true)
	model_button.pressed.connect(_on_group_workspace_pressed.bind(group_id, "model"))
	actions.add_child(model_button)
	var tuning_button: Button = room._button("TURRET / TUNING")
	tuning_button.pressed.connect(_on_group_workspace_pressed.bind(group_id, "tuning"))
	actions.add_child(tuning_button)
	var plots_button: Button = room._button("PLOTS")
	plots_button.pressed.connect(_on_group_workspace_pressed.bind(group_id, "plots"))
	actions.add_child(plots_button)
	var rewards_button: Button = room._button("REWARD CARDS", true)
	rewards_button.pressed.connect(_on_group_workspace_pressed.bind(group_id, "rewards"))
	actions.add_child(rewards_button)
	var save_best: Button = room._button("SAVE BEST")
	save_best.pressed.connect(_on_group_save_pressed.bind(group_id, true))
	actions.add_child(save_best)
	var save_current: Button = room._button("SAVE CURRENT")
	save_current.pressed.connect(_on_group_save_pressed.bind(group_id, false))
	actions.add_child(save_current)
	var library_button: Button = room._button("TURRET MODELS")
	library_button.pressed.connect(_on_group_library_pressed.bind(group_id))
	actions.add_child(library_button)
	var remove_button: Button = room._button("REMOVE")
	room._set_button_danger(remove_button)
	remove_button.pressed.connect(_on_group_remove_pressed.bind(group_id))
	actions.add_child(remove_button)
	room._attach_resize_handle(card, details, _on_group_card_resized.bind(group_id))
	group["card"] = card
	group["card_button"] = select_button
	group["name_edit"] = name_edit
	group["pause_button"] = pause_button
	group["activity_label"] = activity_label
	group["candidate_evaluation_label"] = candidate_evaluation_label
	group["best_score_label"] = best_score_label
	group["worker_label"] = worker_label
	group["add_worker_button"] = add_worker_button
	group["reward_label"] = reward_label
	group["hardware_label"] = null
	group["overwrite_button"] = overwrite_button
	_refresh_rolling_button(group)
	if selected:
		room.call_deferred("_animate_box_open", details)


func begin_group_rename(group_id: int) -> bool:
	if group_id != int(room.selected_turret_group_id):
		return false
	var group: Dictionary = training.group_by_id(group_id)
	if group.is_empty():
		return false
	var name_edit = group.get("name_edit") as LineEdit
	var select_button = group.get("card_button") as Button
	if name_edit == null or select_button == null:
		return false
	name_edit.text = str(group["name"])
	select_button.visible = false
	name_edit.visible = true
	name_edit.modulate.a = 1.0
	name_edit.grab_focus()
	name_edit.select_all()
	room._blink_group_name_edit(name_edit)
	return true


func _cancel_group_rename(group_id: int) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	if group.is_empty():
		return
	var name_edit = group.get("name_edit") as LineEdit
	var select_button = group.get("card_button") as Button
	if name_edit != null:
		name_edit.text = str(group["name"])
		name_edit.visible = false
		name_edit.modulate.a = 1.0
		name_edit.release_focus()
	if select_button != null:
		select_button.visible = true


func _commit_group_name(group_id: int) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	if group.is_empty():
		return
	var name_edit = group.get("name_edit") as LineEdit
	var select_button = group.get("card_button") as Button
	if name_edit == null or not name_edit.visible:
		return
	var requested_name: String = name_edit.text.strip_edges()
	if requested_name.is_empty():
		name_edit.text = str(group["name"])
		_set_status("A worker group needs a name.")
		name_edit.grab_focus()
		name_edit.select_all()
		return
	var old_name: String = str(group["name"])
	var new_name: String = room._unique_group_name_for_kind(
		requested_name,
		"turret",
		group_id
	)
	group["name"] = new_name
	if new_name != old_name:
		# A rolling saved version keeps its original manifest identity. Force the next save
		# to create the newly named model instead of hiding it inside the old family.
		group["rolling_version_id"] = ""
	name_edit.text = new_name
	name_edit.visible = false
	name_edit.modulate.a = 1.0
	name_edit.release_focus()
	if select_button != null:
		select_button.visible = true
	room.plots_dirty = true
	if int(room.selected_turret_group_id) == group_id:
		room.selected_group_title.text = new_name
	room._refresh_group_card_texts()
	if new_name != old_name:
		_set_status("%s renamed to %s. Future saves use the new name." % [old_name, new_name])


func _on_group_name_submitted(_new_text: String, group_id: int) -> void:
	_commit_group_name(group_id)


func _on_group_name_focus_exited(group_id: int) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit) and name_edit.visible:
		_commit_group_name(group_id)


func _on_group_name_gui_input(event: InputEvent, group_id: int) -> void:
	var rename_key = event as InputEventKey
	if rename_key == null or not rename_key.pressed or rename_key.keycode != KEY_ESCAPE:
		return
	_cancel_group_rename(group_id)
	var group: Dictionary = training.group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit):
		name_edit.accept_event()


func _on_save_selected_pressed() -> void:
	var group: Dictionary = selected_group()
	if group.is_empty():
		_set_status("Select a turret worker group before saving.")
		return
	var model_name: String = str(group.get("name", "Turret Model"))
	if is_instance_valid(model_name_edit):
		model_name = model_name_edit.text
	save_group(int(group["group_id"]), model_name, false)
	open_model_browser()


func _on_manual_yaw_changed(value: float) -> void:
	if not room.suppress_ui_callbacks:
		_set_manual_axis("yaw", value)


func _on_manual_pitch_changed(value: float) -> void:
	if not room.suppress_ui_callbacks:
		_set_manual_axis("pitch", value)


func _on_manual_trigger_toggled(value: bool) -> void:
	if not room.suppress_ui_callbacks:
		_set_manual_axis("trigger", 1.0 if value else 0.0)


func _on_group_select_pressed(group_id: int) -> void:
	room._select_turret_group(-1 if int(room.selected_turret_group_id) == group_id else group_id)


func _on_group_pause_pressed(group_id: int) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	if not group.is_empty():
		set_group_active(group_id, not bool(group.get("active", false)))


func _on_group_overwrite_toggled(enabled: bool, group_id: int) -> void:
	set_group_overwrite(group_id, enabled)


func _on_group_branch_pressed(group_id: int) -> void:
	open_branch_dialog(group_id)


func _on_group_workspace_pressed(group_id: int, page_name: String) -> void:
	room._select_turret_group(group_id)
	room._set_workspace_page(page_name)


func _on_group_save_pressed(group_id: int, best: bool) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	if group.is_empty():
		return
	room._select_turret_group(group_id)
	save_group(group_id, str(group.get("name", "Turret Model")), best)


func _on_group_library_pressed(group_id: int) -> void:
	room._select_turret_group(group_id)
	open_model_browser()


func _on_group_remove_pressed(group_id: int) -> void:
	remove_group(group_id)


func _on_group_card_resized(new_height: float, group_id: int) -> void:
	var group: Dictionary = training.group_by_id(group_id)
	if not group.is_empty():
		group["card_minimum_height"] = new_height


func _ignore_slider_value(_value: float) -> void:
	pass


func _on_part_input_changed(value: float, part_name: String, property_path: String) -> void:
	if not room.suppress_ui_callbacks:
		_set_selected_part_value(part_name, property_path, value)


func _build_branch_dialog() -> void:
	branch_dialog = ConfirmationDialog.new()
	branch_dialog.title = "New Stationary Turret Branch"
	branch_dialog.ok_button_text = "Create Branch"
	branch_dialog.cancel_button_text = "Cancel"
	# AcceptDialog/ConfirmationDialog enables Window.wrap_controls by default. With custom
	# children that means the dialog can permanently adopt a bogus build-time minimum before
	# its first popup (especially when an autowrapped label has not received its real width yet).
	# This dialog has an authored size, so never let child additions resize the Window itself.
	branch_dialog.wrap_controls = false
	branch_dialog.min_size = Vector2i(540, 450)
	branch_dialog.size = BRANCH_DIALOG_SIZE
	branch_dialog.confirmed.connect(_confirm_branch)
	room.add_child(branch_dialog)
	var margin = MarginContainer.new()
	# Match the drone/limb creation dialogs: give wrapped content its final width before its
	# minimum height is measured. Without these anchors the first layout pass can measure the
	# note at a tiny width and stretch the popup vertically until it is opened a second time.
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16.0
	margin.offset_top = 16.0
	margin.offset_right = -16.0
	margin.offset_bottom = -64.0
	branch_dialog.add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Give wrapped labels a stable build-time width even before the Window performs layout.
	# The vertical ScrollContainer then prevents content minimum-height changes from stretching
	# the dialog itself.
	content.custom_minimum_size.x = float(BRANCH_DIALOG_SIZE.x - 60)
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)
	branch_source_label = Label.new()
	branch_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	branch_source_label.add_theme_color_override("font_color", Color("8de1ff"))
	content.add_child(branch_source_label)
	branch_name_edit = LineEdit.new()
	branch_name_edit.max_length = room.GROUP_NAME_MAX_LENGTH
	branch_name_edit.placeholder_text = "Example: Faster traverse variant"
	content.add_child(branch_name_edit)
	branch_hidden_width_slider = room._add_slider(
		content,
		"Hidden layer width",
		float(DronePPOMLP.MINIMUM_HIDDEN_WIDTH),
		512.0,
		8.0,
		float(TurretPPOActorCritic.HIDDEN_SIZE),
		"Neurons per hidden actor/critic layer. Wider turret models can learn richer tracking policies but cost more CPU per control step.",
		_ignore_slider_value
	)
	branch_hidden_depth_slider = room._add_slider(
		content,
		"Hidden layer depth",
		float(DronePPOMLP.MINIMUM_HIDDEN_DEPTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_DEPTH),
		1.0,
		float(TurretPPOActorCritic.HIDDEN_LAYER_COUNT),
		"Number of hidden tanh layers. A fresh model may choose 1-6; branches retain their source architecture.",
		_ignore_slider_value
	)
	branch_variation_slider = room._add_slider(
		content,
		"Weight variation",
		0.0,
		room.MAXIMUM_BRANCH_WEIGHT_VARIATION,
		0.001,
		room.DEFAULT_BRANCH_WEIGHT_VARIATION,
		"Independent Gaussian perturbation applied once to the copied policy.",
		_ignore_slider_value
	)
	var one_turret_note: Label = Label.new()
	one_turret_note.text = "Groups start with one placed turret; use + on the group card to add workers."
	one_turret_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	one_turret_note.add_theme_color_override("font_color", Color("5ab889"))
	content.add_child(one_turret_note)
	branch_start_active_checkbox = CheckBox.new()
	branch_start_active_checkbox.text = "Start training immediately"
	branch_start_active_checkbox.button_pressed = true
	content.add_child(branch_start_active_checkbox)


func _confirm_branch() -> void:
	var source = training.group_by_id(branch_source_group_id)
	var is_branch: bool = not source.is_empty()
	var checkpoint: Dictionary = {}
	if is_branch:
		checkpoint = training.save_checkpoint(branch_source_group_id, false)
		if checkpoint.is_empty():
			_set_status("The live turret policy could not be copied.")
			return
	room.group_counter += 1
	var hue = float(posmod(room.group_counter * 2371, 10000)) / 10000.0
	var network_config: Dictionary = {
		"hidden_layer_width": int(round(branch_hidden_width_slider.value)),
		"hidden_layer_depth": int(round(branch_hidden_depth_slider.value)),
	}
	var child = training.create_group(
		room.group_counter,
		room._unique_group_name(branch_name_edit.text, -1),
		Color.from_hsv(hue, 0.68, 0.95),
		1,
		training.group_loadout(branch_source_group_id) if is_branch else null,
		network_config
	)
	if child.is_empty():
		_set_status(training.last_error)
		return
	var child_id: int = int(child["group_id"])
	room._ensure_group_target_handler(
		child_id, child["color"], branch_source_group_id if is_branch else -1
	)
	if is_branch and not training.load_checkpoint(child_id, checkpoint):
		training.remove_group(child_id)
		room._remove_group_target_handler(child_id)
		_set_status(training.last_error)
		return
	child["worker_count"] = 1
	child["pending_worker_count"] = 1
	if is_branch:
		child["parent_group_id"] = branch_source_group_id
		child["branch_weight_variation"] = float(branch_variation_slider.value)
		child["source_description"] = "Branched from live turret group %s" % str(source["name"])
		child["reward_cardset_id"] = str(source.get("reward_cardset_id", "builtin:turret_precision"))
		child["reward_cardset_name"] = str(source.get("reward_cardset_name", "Precision Fire"))
		child["rolling_version_id"] = ""
		(child["trainer"] as TurretPPOTrainer).perturb_policy(
			float(branch_variation_slider.value),
			int(child["group_id"]) * 104729 + int(Time.get_ticks_usec() & 0x7fffffff)
		)
	training.clear_group_placement(child_id)
	room._select_turret_group(child_id)
	room._rebuild_group_cards()
	branch_dialog.hide()
	branch_source_group_id = -1
	_set_status(
		"%s branched from %s." % [str(child["name"]), str(source["name"])]
		if is_branch
		else "%s created with a %dx%d hidden network; place its turret." % [
			str(child["name"]),
			int(network_config["hidden_layer_depth"]),
			int(network_config["hidden_layer_width"]),
		]
	)
	room._begin_turret_placement(child_id, branch_start_active_checkbox.button_pressed)


func _add_part_input(
	parent: VBoxContainer,
	title: String,
	part_name: String,
	property_path: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	tooltip: String
) -> void:
	var key = "%s:%s" % [part_name, property_path]
	var input: SpinBox = room._add_number_input(
		parent,
		title,
		minimum,
		maximum,
		step,
		minimum,
		suffix,
		tooltip,
		_on_part_input_changed.bind(part_name, property_path)
	)
	part_inputs[key] = input
	part_edit_controls.append(input)


func _set_selected_part_value(part_name: String, property_path: String, value: float) -> void:
	var group = selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		_set_status("Pause %s before changing its turret parts." % str(group["name"]))
		refresh_selection()
		return
	var loadout = MLBodyPartContract.deep_duplicate_resource(group.get("turret_loadout") as TurretLoadout) as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		_set_status("This turret body is incomplete; select a valid creator preset/body before editing it.")
		return
	_write_part_value(loadout, part_name, property_path, value)
	loadout.gun.sanitize()
	if not training.replace_group_loadout(int(group["group_id"]), loadout):
		_set_status(training.last_error)
	refresh_selection()


func _read_part_value(loadout: TurretLoadout, part_name: String, property_path: String) -> float:
	var part: Object = loadout.base if part_name == "base" else loadout.gun
	var path = property_path.split(":", false, 1)
	if path.size() == 1:
		return float(part.get(path[0]))
	var vector: Vector3 = part.get(path[0])
	match path[1]:
		"x": return vector.x
		"y": return vector.y
		"z": return vector.z
	return 0.0


func _write_part_value(
	loadout: TurretLoadout,
	part_name: String,
	property_path: String,
	value: float
) -> void:
	var part: Object = loadout.base if part_name == "base" else loadout.gun
	var path = property_path.split(":", false, 1)
	if path.size() == 1:
		part.set(path[0], value)
		return
	var vector: Vector3 = part.get(path[0])
	match path[1]:
		"x": vector.x = value
		"y": vector.y = value
		"z": vector.z = value
	part.set(path[0], vector)


func _reset_selected_loadout() -> void:
	var group = selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		_set_status("Pause %s before resetting its turret parts." % str(group["name"]))
		return
	if training.reset_group_loadout(int(group["group_id"])):
		_set_status("%s now uses the Stationary Turret preset." % str(group["name"]))
	else:
		_set_status(training.last_error)
	refresh_selection()


func _set_manual_override(enabled: bool) -> void:
	if room.suppress_ui_callbacks:
		return
	var group = selected_group()
	if group.is_empty():
		return
	training.set_manual_override(int(group["group_id"]), enabled)
	if not enabled:
		release_manual_keys()
		training.set_manual_controls(int(group["group_id"]), 0.0, 0.0, 0.0)
	_set_status(
		"Manual servo control enabled for %s worker 1. Other workers continue learning."
		% str(group["name"])
		if enabled
		else "Manual servo control disabled for %s." % str(group["name"])
	)
	refresh_selection()


func _set_manual_axis(axis: String, value: float) -> void:
	var group = selected_group()
	if group.is_empty() or not bool(group.get("manual_override_enabled", false)):
		return
	var yaw = float(group.get("manual_yaw_drive", 0.0))
	var pitch = float(group.get("manual_pitch_drive", 0.0))
	var trigger = float(group.get("manual_trigger", 0.0))
	match axis:
		"yaw": yaw = value
		"pitch": pitch = value
		"trigger": trigger = value
	training.set_manual_controls(int(group["group_id"]), yaw, pitch, trigger)


static func keyboard_yaw_drive(left_pressed: bool, right_pressed: bool) -> float:
	# Godot's positive Y rotation turns the forward -Z axis toward world left. Keep the
	# familiar manual convention: A/left turns left, D/right turns right.
	return float(int(left_pressed) - int(right_pressed))


func _apply_keyboard_controls(group: Dictionary) -> void:
	var yaw = keyboard_yaw_drive(
		bool(keyboard_state["yaw_left"]),
		bool(keyboard_state["yaw_right"])
	)
	var pitch = float(int(bool(keyboard_state["pitch_up"])) - int(bool(keyboard_state["pitch_down"])))
	var trigger = 1.0 if bool(keyboard_state["trigger"]) else 0.0
	training.set_manual_controls(int(group["group_id"]), yaw, pitch, trigger)
	room.suppress_ui_callbacks = true
	manual_yaw_slider.set_value_no_signal(yaw)
	manual_pitch_slider.set_value_no_signal(pitch)
	manual_trigger_checkbox.set_pressed_no_signal(trigger >= 0.5)
	room.suppress_ui_callbacks = false


func _text_control_has_focus() -> bool:
	var focus = room.get_viewport().gui_get_focus_owner() as Control
	while focus != null:
		if focus is LineEdit or focus is TextEdit or focus is SpinBox:
			return true
		focus = focus.get_parent() as Control
	return false


func _load_selected_model() -> void:
	var selected = model_list.get_selected_items()
	if selected.is_empty() or selected[0] >= model_records.size():
		return
	var group = selected_group()
	if group.is_empty():
		_set_status("Select a turret worker group before loading.")
		return
	var record = model_records[selected[0]]
	var checkpoint = registry.load_checkpoint(record)
	if checkpoint.is_empty():
		_set_status(registry.last_error)
		return
	var group_id: int = int(group["group_id"])
	if not training.load_checkpoint(group_id, checkpoint):
		_set_status(training.last_error)
		return
	room._load_target_handler_configuration_for_group(
		group_id,
		(checkpoint.get("room_settings", {}) as Dictionary).get("target_handler", {})
	)
	group["rolling_version_id"] = ""
	room._rebuild_reward_cards()
	room._refresh_selected_group_controls()
	room._refresh_group_card_texts()
	room._refresh_target_controls_for_selection()
	_set_status("Loaded %s into %s." % [registry.display_name(record), str(group["name"])])
	model_browser.hide()


func _request_delete_selected_model() -> void:
	var selected = model_list.get_selected_items()
	if selected.is_empty() or selected[0] >= model_records.size():
		return
	pending_delete_record = model_records[selected[0]]
	delete_dialog.dialog_text = "Delete %s permanently?" % registry.display_name(pending_delete_record)
	delete_dialog.popup_centered()


func _confirm_delete_model() -> void:
	if pending_delete_record.is_empty():
		return
	if registry.delete_model(pending_delete_record):
		for group: Dictionary in training.groups:
			if str(group.get("rolling_version_id", "")) == str(pending_delete_record.get("version_id", "")):
				group["rolling_version_id"] = ""
		open_model_browser()
	else:
		_set_status(registry.last_error)
	pending_delete_record = {}


func _refresh_rolling_button(group: Dictionary) -> void:
	var button = group.get("overwrite_button") as Button
	if button == null:
		return
	var enabled = bool(group.get("overwrite_saved_versions", true))
	button.set_pressed_no_signal(enabled)
	button.text = "KEEP NEWEST: ON" if enabled else "KEEP NEWEST: OFF"
	button.call("set_rolling_active", enabled)


func _set_status(text: String) -> void:
	if room != null and room.status_label != null:
		room.status_label.text = text

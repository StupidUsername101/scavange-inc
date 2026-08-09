class_name FourLimbTrainingRoom
extends Node3D

const DEFAULT_WORKER_COUNT = 6
const MAXIMUM_WORKER_COUNT = 16
const MAXIMUM_GROUP_COUNT = 9
const DECISION_INTERVAL_SECONDS = 0.05
const DEFAULT_EPISODE_SECONDS = 24.0
const TARGET_RADIUS = 1.25
const GROUP_SPACING = 18.0
const BODY_SPAWN_HEIGHT = 1.85
const ARENA_COLLISION_LAYER = 1
const BODY_COLLISION_LAYER = 4
enum Lesson {
	STAND,
	APPROACH,
	RANDOM_WAYPOINTS,
	WEAK_LIMB,
	MISSING_LIMB,
}

const LESSON_NAMES = [
	"Stand upright",
	"Approach stationary target",
	"Follow random waypoints",
	"Approach with one weak limb",
	"Approach with one missing limb",
]

const GROUP_COLORS = [
	Color(0.95, 0.55, 0.18, 1.0),
	Color(0.25, 0.72, 0.92, 1.0),
	Color(0.62, 0.86, 0.32, 1.0),
	Color(0.78, 0.46, 0.92, 1.0),
	Color(0.94, 0.34, 0.47, 1.0),
]

#######################################################
# Dedicated physical-body trainer. It deliberately lives beside the drone room so introducing
# twelve joint actuators cannot change the proven four-propeller training path.
#######################################################

var walker_preset_template = MLBodyPresetLibrary.four_limb_walker_definition()
var groups: Array[Dictionary] = []
var selected_group_id = -1
var next_group_id = 1
var globally_paused = false
var model_registry = FourLimbModelRegistry.new()
var map_registry = DroneTrainingMapRegistry.new()
var custom_obstacle_container: Node3D
var target_container: Node3D
var spectator_camera: Camera3D
var camera_yaw = 0.65
var camera_pitch = -0.42
var camera_distance = 15.0
var camera_dragging = false
var last_mouse_position = Vector2.ZERO

var ui_layer: CanvasLayer
var group_list: VBoxContainer
var reward_card_list: VBoxContainer
var reward_card_value_labels: Dictionary[String, Label] = {}
var diagnostics_label: RichTextLabel
var status_label: Label
var pause_button: Button
var model_name_input: LineEdit
var lesson_selector: OptionButton
var worker_count_input: SpinBox
var manual_override_toggle: CheckButton
var manual_worker_selector: OptionButton
var manual_sliders: Array[HSlider] = []
var model_library_window: Window
var model_library_list: ItemList
var model_library_records: Array[Dictionary] = []
var map_library_window: Window
var map_library_list: ItemList
var map_library_records: Array[Dictionary] = []
var loaded_map_obstacle_records: Array = []


func _ready() -> void:
	_build_environment()
	_build_ui()
	_add_group()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _physics_process(delta: float) -> void:
	if globally_paused:
		return
	for group: Dictionary in groups:
		_tick_group(group, delta)
	_refresh_diagnostics()


func _process(delta: float) -> void:
	_update_camera(delta)
	_refresh_group_cards(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		SceneController.leave_four_limb_training_room()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			camera_dragging = mouse_button.pressed
			last_mouse_position = mouse_button.position
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			camera_distance = maxf(camera_distance - 1.0, 2.5)
		elif mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			camera_distance = minf(camera_distance + 1.0, 45.0)
	elif event is InputEventMouseMotion and camera_dragging:
		var motion = event as InputEventMouseMotion
		camera_yaw -= motion.relative.x * 0.006
		camera_pitch = clampf(camera_pitch - motion.relative.y * 0.006, -1.25, -0.08)


func _build_environment() -> void:
	var environment = WorldEnvironment.new()
	var environment_resource = Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color(0.018, 0.03, 0.034, 1.0)
	environment_resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment_resource.ambient_light_color = Color(0.42, 0.48, 0.52, 1.0)
	environment_resource.ambient_light_energy = 0.75
	environment_resource.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_resource.tonemap_white = 2.2
	environment.environment = environment_resource
	add_child(environment)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)
	var floor = DroneTrainingRoomPresentation.add_static_obstacle(
		self,
		"TrainingFloor",
		Vector3(36.0, -0.3, 36.0),
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": 120.0, "height": 0.6, "depth": 120.0},
		Color(0.12, 0.17, 0.18, 1.0),
		ARENA_COLLISION_LAYER,
		BODY_COLLISION_LAYER
	)
	for floor_child: Node in floor.get_children():
		var floor_visual: MeshInstance3D = floor_child as MeshInstance3D
		if floor_visual != null:
			floor_visual.material_override = DroneTrainingRoomPresentation.matte_material(
				Color(0.12, 0.17, 0.18, 1.0)
			)
	floor.set_meta("permanent_training_floor", true)
	custom_obstacle_container = Node3D.new()
	custom_obstacle_container.name = "CustomObstacles"
	add_child(custom_obstacle_container)
	target_container = Node3D.new()
	target_container.name = "Targets"
	add_child(target_container)
	spectator_camera = Camera3D.new()
	spectator_camera.name = "SpectatorCamera"
	spectator_camera.current = true
	spectator_camera.near = 0.05
	spectator_camera.far = 250.0
	add_child(spectator_camera)


func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_layer.add_child(root)

	var left_panel = PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_right = 430.0
	left_panel.add_theme_stylebox_override("panel", _panel_style(false))
	root.add_child(left_panel)
	var left_margin = MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 12)
	left_margin.add_theme_constant_override("margin_right", 12)
	left_margin.add_theme_constant_override("margin_top", 12)
	left_margin.add_theme_constant_override("margin_bottom", 12)
	left_panel.add_child(left_margin)
	var left_content = VBoxContainer.new()
	left_content.add_theme_constant_override("separation", 8)
	left_margin.add_child(left_content)

	var title = Label.new()
	title.text = "FOUR-LIMB PHYSICAL TRAINER"
	title.add_theme_font_size_override("font_size", 22)
	left_content.add_child(title)
	var top_actions = HBoxContainer.new()
	left_content.add_child(top_actions)
	_add_button(top_actions, "BACK", _on_back_pressed)
	pause_button = _add_button(top_actions, "PAUSE", _on_pause_pressed, true)
	_add_button(top_actions, "+ GROUP", _add_group, true)
	_add_button(top_actions, "MAPS", _open_map_library)

	var save_row = HBoxContainer.new()
	left_content.add_child(save_row)
	model_name_input = LineEdit.new()
	model_name_input.placeholder_text = "Model name"
	model_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(model_name_input)
	_add_button(save_row, "SAVE", _save_selected_group, true)
	_add_button(save_row, "MODELS", _open_model_library)

	status_label = Label.new()
	status_label.text = "Ready"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_content.add_child(status_label)

	var lesson_row = HBoxContainer.new()
	left_content.add_child(lesson_row)
	var lesson_label = Label.new()
	lesson_label.text = "Selected lesson"
	lesson_row.add_child(lesson_label)
	lesson_selector = OptionButton.new()
	lesson_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for lesson_index in range(LESSON_NAMES.size()):
		lesson_selector.add_item(LESSON_NAMES[lesson_index], lesson_index)
	lesson_selector.item_selected.connect(_on_lesson_selected)
	lesson_row.add_child(lesson_selector)
	worker_count_input = SpinBox.new()
	worker_count_input.min_value = 1
	worker_count_input.max_value = MAXIMUM_WORKER_COUNT
	worker_count_input.step = 1
	DroneTrainingRoomPresentation.configure_spinbox_arrow_speed(worker_count_input)
	worker_count_input.value = DEFAULT_WORKER_COUNT
	worker_count_input.tooltip_text = "Workers in the selected group.\n\nChanging this restarts only that group at the next episode boundary."
	worker_count_input.value_changed.connect(_on_worker_count_changed)
	lesson_row.add_child(worker_count_input)

	var groups_heading = Label.new()
	groups_heading.text = "WORKER GROUPS"
	groups_heading.add_theme_font_size_override("font_size", 18)
	left_content.add_child(groups_heading)
	var group_scroll = ScrollContainer.new()
	group_scroll.custom_minimum_size.y = 180.0
	group_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.add_child(group_scroll)
	group_list = VBoxContainer.new()
	group_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_list.add_theme_constant_override("separation", 6)
	group_scroll.add_child(group_list)

	var reward_heading = Label.new()
	reward_heading.text = "REWARD / PUNISHMENT CARDS"
	reward_heading.add_theme_font_size_override("font_size", 18)
	left_content.add_child(reward_heading)
	var reward_note = Label.new()
	reward_note.text = "Changes are applied at the next episode."
	reward_note.modulate = Color(0.78, 0.82, 0.82, 1.0)
	left_content.add_child(reward_note)
	var reward_scroll = ScrollContainer.new()
	reward_scroll.custom_minimum_size.y = 310.0
	reward_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_content.add_child(reward_scroll)
	reward_card_list = VBoxContainer.new()
	reward_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_card_list.add_theme_constant_override("separation", 6)
	reward_scroll.add_child(reward_card_list)

	_build_diagnostics_panel(root)
	_build_model_library()
	_build_map_library()


func _build_diagnostics_panel(root: Control) -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 445.0
	panel.offset_top = -290.0
	panel.add_theme_stylebox_override("panel", _panel_style(false))
	root.add_child(panel)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var manual_column = VBoxContainer.new()
	manual_column.custom_minimum_size.x = 420.0
	content.add_child(manual_column)
	manual_override_toggle = CheckButton.new()
	manual_override_toggle.text = "Manual raw-actuator override"
	manual_override_toggle.tooltip_text = "Use the sixteen direct actuator sliders for the selected worker.\nNo gait or pickup macro is used."
	manual_column.add_child(manual_override_toggle)
	manual_worker_selector = OptionButton.new()
	manual_column.add_child(manual_worker_selector)
	var sliders_grid = GridContainer.new()
	sliders_grid.columns = 6
	manual_column.add_child(sliders_grid)
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		for axis_index in range(FourLimbMLAction.ACTIONS_PER_LIMB):
			var label = Label.new()
			label.text = "%s %s" % [
				["FL", "FR", "BL", "BR"][limb_index],
				["Elevation", "Sweep", "Knee", "Grip"][axis_index],
			]
			sliders_grid.add_child(label)
			var slider = HSlider.new()
			slider.min_value = -1.0 if axis_index < FourLimbMLAction.JOINT_AXES_PER_LIMB else 0.0
			slider.max_value = 1.0
			slider.step = 0.01
			slider.value = 0.0
			slider.custom_minimum_size.x = 110.0
			slider.tooltip_text = (
				"Direct normalized grip activation."
				if axis_index == 3
				else "Direct normalized target for this joint axis.\n-1 and +1 are the authored joint limits."
			)
			sliders_grid.add_child(slider)
			manual_sliders.append(slider)
	diagnostics_label = RichTextLabel.new()
	diagnostics_label.bbcode_enabled = true
	diagnostics_label.fit_content = false
	diagnostics_label.scroll_active = true
	diagnostics_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(diagnostics_label)


func _build_model_library() -> void:
	model_library_window = Window.new()
	model_library_window.title = "Four-Limb Model Library"
	model_library_window.size = Vector2i(860, 620)
	model_library_window.unresizable = false
	model_library_window.visible = false
	model_library_window.close_requested.connect(model_library_window.hide)
	add_child(model_library_window)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	model_library_window.add_child(margin)
	var content = VBoxContainer.new()
	margin.add_child(content)
	var path_label = Label.new()
	path_label.text = model_registry.globalized_root_path()
	path_label.modulate = Color(0.96, 0.67, 0.18, 1.0)
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(path_label)
	model_library_list = ItemList.new()
	model_library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(model_library_list)
	var actions = HBoxContainer.new()
	content.add_child(actions)
	_add_button(actions, "LOAD INTO SELECTED GROUP", _load_selected_model, true)
	_add_button(actions, "DELETE", _delete_selected_model, false, true)
	_add_button(actions, "CLOSE", model_library_window.hide)


func _build_map_library() -> void:
	map_library_window = Window.new()
	map_library_window.title = "Training Map Library"
	map_library_window.size = Vector2i(820, 580)
	map_library_window.unresizable = false
	map_library_window.visible = false
	map_library_window.close_requested.connect(map_library_window.hide)
	add_child(map_library_window)
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	map_library_window.add_child(margin)
	var content = VBoxContainer.new()
	margin.add_child(content)
	var path_label = Label.new()
	path_label.text = map_registry.globalized_root_path()
	path_label.modulate = Color(0.96, 0.67, 0.18, 1.0)
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(path_label)
	map_library_list = ItemList.new()
	map_library_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(map_library_list)
	var actions = HBoxContainer.new()
	content.add_child(actions)
	_add_button(actions, "LOAD MAP", _load_selected_map, true)
	_add_button(actions, "DELETE", _delete_selected_map, false, true)
	_add_button(actions, "CLOSE", map_library_window.hide)


func _add_group() -> void:
	if groups.size() >= MAXIMUM_GROUP_COUNT:
		if status_label != null:
			status_label.text = "The physical trainer supports up to %d worker groups at once." % MAXIMUM_GROUP_COUNT
		return
	var group_id = next_group_id
	next_group_id += 1
	# Reuse an empty arena slot without moving existing groups or overlapping their bodies/maps.
	var group_index = _next_free_group_layout_slot()
	var column = group_index % 3
	var row = floori(float(group_index) / 3.0)
	var center = Vector3(
		18.0 + float(column) * GROUP_SPACING,
		0.0,
		18.0 + float(row) * GROUP_SPACING
	)
	var color: Color = GROUP_COLORS[group_index % GROUP_COLORS.size()]
	var target = center + Vector3(0.0, 1.2, -5.5)
	var marker = _create_target_marker(target, color)
	var group = {
		"id": group_id,
		"layout_slot": group_index,
		"name": "Body Group %d" % group_id,
		"color": color,
		"center": center,
		"target_position": target,
		"target_marker": marker,
		"trainer": FourLimbPPOTrainer.new(7340033 + group_id * 97),
		"reward_deck": FourLimbRewardDeck.new(),
		"pending_reward_config": {},
		"workers": [],
		"worker_count": DEFAULT_WORKER_COUNT,
		"episode": 0,
		"last_mean_reward": 0.0,
		"best_mean_reward": -INF,
		"last_update": {},
		"lesson": Lesson.STAND,
		"pending_lesson": Lesson.STAND,
		"pending_worker_count": DEFAULT_WORKER_COUNT,
		"waypoint_elapsed": 0.0,
		"rng": RandomNumberGenerator.new(),
	}
	(group["rng"] as RandomNumberGenerator).seed = 9001 + group_id * 313
	groups.append(group)
	if not loaded_map_obstacle_records.is_empty():
		_rebuild_loaded_map_obstacles()
	selected_group_id = group_id
	_start_group_episode(group)
	# Selecting the newly created group also synchronizes the lesson and worker-count controls.
	# Without this, the panel could display the previous group's settings while editing the new one.
	_select_group(group_id)


func _start_group_episode(group: Dictionary) -> void:
	_apply_pending_reward_config(group)
	group["lesson"] = int(group.get("pending_lesson", group.get("lesson", Lesson.APPROACH)))
	group["worker_count"] = clampi(
		int(group.get("pending_worker_count", group.get("worker_count", DEFAULT_WORKER_COUNT))),
		1,
		MAXIMUM_WORKER_COUNT
	)
	_prepare_group_target_for_episode(group)
	_clear_group_workers(group)
	group["episode"] = int(group.get("episode", 0)) + 1
	var workers: Array[Dictionary] = []
	var worker_count = clampi(int(group.get("worker_count", DEFAULT_WORKER_COUNT)), 1, MAXIMUM_WORKER_COUNT)
	for worker_index in range(worker_count):
		var body = FourLimbPhysicalBody3D.new()
		body.name = "FourLimbWorker_%d_%d" % [int(group["id"]), worker_index]
		var worker_definition = walker_preset_template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
		var affected_limb = -1
		var lesson = int(group.get("lesson", Lesson.APPROACH))
		if lesson == Lesson.MISSING_LIMB:
			affected_limb = (group["rng"] as RandomNumberGenerator).randi_range(0, 3)
			worker_definition.limbs[affected_limb].installed = false
		body.definition = worker_definition
		body.auto_start_simulation = true
		var spawn = _worker_spawn_transform(group, worker_index, worker_count)
		body.transform = spawn
		add_child(body)
		if lesson == Lesson.WEAK_LIMB:
			affected_limb = (group["rng"] as RandomNumberGenerator).randi_range(0, 3)
			body.set_limb_effectiveness(
				affected_limb,
				(group["rng"] as RandomNumberGenerator).randf_range(0.25, 0.65)
			)
		var adapter = FourLimbMLBodyAdapter.new(body)
		var stand_target = Vector3(spawn.origin.x, 1.35, spawn.origin.z)
		var objective = _objective_for_group(group)
		if lesson == Lesson.STAND:
			objective["target_position_world"] = stand_target
		var observation = adapter.capture_observation(objective)
		var sample = (group["trainer"] as FourLimbPPOTrainer).sample_validated_runtime_action(observation)
		if not sample.is_empty():
			adapter.apply_commands(sample.get("commands", PackedFloat64Array()))
		var initial_commands: PackedFloat64Array = sample.get("commands", PackedFloat64Array())
		workers.append({
			"id": worker_index,
			"body": body,
			"adapter": adapter,
			"elapsed": 0.0,
			"decision_elapsed": 0.0,
			"last_action_sample": sample,
			"interval_reward": 0.0,
			"interval_elapsed_seconds": 0.0,
			"total_reward": 0.0,
			"previous_physics_observation": observation,
			"previous_commands": initial_commands.duplicate(),
			"action_change_pending": 0.0,
			"reward_state": (group["reward_deck"] as FourLimbRewardDeck).create_worker_state(),
			"finished": false,
			"failure_reason": "",
			"fallen_since": -1.0,
			"affected_limb": affected_limb,
			"stand_target_position": stand_target,
		})
	group["workers"] = workers
	_refresh_manual_worker_list()


func _tick_group(group: Dictionary, delta: float) -> void:
	if int(group.get("lesson", Lesson.APPROACH)) == Lesson.RANDOM_WAYPOINTS:
		group["waypoint_elapsed"] = float(group.get("waypoint_elapsed", 0.0)) + delta
		if float(group["waypoint_elapsed"]) >= 5.0:
			group["waypoint_elapsed"] = 0.0
			_choose_random_group_target(group)
	var workers: Array = group.get("workers", [])
	if workers.is_empty():
		_start_group_episode(group)
		return
	var all_finished = true
	for worker_value: Variant in workers:
		var worker: Dictionary = worker_value
		if bool(worker.get("finished", false)):
			continue
		all_finished = false
		_tick_worker(group, worker, delta)
	if all_finished:
		_finish_group_episode(group)


func _tick_worker(group: Dictionary, worker: Dictionary, delta: float) -> void:
	var body = worker.get("body") as FourLimbPhysicalBody3D
	var adapter = worker.get("adapter") as FourLimbMLBodyAdapter
	if not is_instance_valid(body) or adapter == null:
		_finish_worker(group, worker, "missing_body", false, {})
		return
	worker["elapsed"] = float(worker.get("elapsed", 0.0)) + delta
	worker["decision_elapsed"] = float(worker.get("decision_elapsed", 0.0)) + delta
	var observation = adapter.capture_observation(_objective_for_worker(group, worker))
	if observation.is_empty():
		_finish_worker(group, worker, "invalid_observation", false, {})
		return
	var reward_result = (group["reward_deck"] as FourLimbRewardDeck).step_reward(
		worker.get("previous_physics_observation", observation),
		observation,
		delta,
		worker["reward_state"],
		{"action_change_norm": float(worker.get("action_change_pending", 0.0))}
	)
	worker["action_change_pending"] = 0.0
	var reward = float(reward_result.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + reward
	worker["interval_elapsed_seconds"] = float(worker.get("interval_elapsed_seconds", 0.0)) + delta
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + reward
	worker["previous_physics_observation"] = observation

	var termination = _worker_termination(group, worker, observation)
	if bool(termination.get("finished", false)):
		_finish_worker(
			group,
			worker,
			str(termination.get("reason", "")),
			bool(termination.get("timed_out", false)),
			observation
		)
		return
	if float(worker["decision_elapsed"]) < DECISION_INTERVAL_SECONDS:
		return
	worker["decision_elapsed"] = fmod(float(worker["decision_elapsed"]), DECISION_INTERVAL_SECONDS)
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var last_sample: Dictionary = worker.get("last_action_sample", {})
	var sample = _sample_worker_action(group, worker, observation)
	if not last_sample.is_empty() and not bool(last_sample.get("manual", false)):
		if not sample.is_empty() and not bool(sample.get("manual", false)):
			trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", DECISION_INTERVAL_SECONDS)), 0.000001),
				sample.get("actor_input", PackedFloat64Array()),
				float(sample.get("value", NAN))
			)
		else:
			trainer.add_transition(
				int(worker["id"]),
				last_sample,
				float(worker["interval_reward"]),
				observation,
				false,
				false,
				maxf(float(worker.get("interval_elapsed_seconds", DECISION_INTERVAL_SECONDS)), 0.000001)
			)
	worker["interval_reward"] = 0.0
	worker["interval_elapsed_seconds"] = 0.0
	if not sample.is_empty():
		adapter.apply_commands(sample.get("commands", PackedFloat64Array()))
		var new_commands: PackedFloat64Array = sample.get("commands", PackedFloat64Array())
		var previous_commands: PackedFloat64Array = worker.get("previous_commands", PackedFloat64Array())
		worker["action_change_pending"] = _command_change_norm(previous_commands, new_commands)
		worker["previous_commands"] = new_commands
	worker["last_action_sample"] = sample


func _sample_worker_action(
	group: Dictionary,
	worker: Dictionary,
	observation: Dictionary
) -> Dictionary:
	if (
		manual_override_toggle.button_pressed
		and int(worker.get("id", -1)) == manual_worker_selector.get_selected_id()
	):
		var commands = PackedFloat64Array()
		commands.resize(FourLimbMLAction.ACTION_COUNT)
		for index in range(FourLimbMLAction.ACTION_COUNT):
			commands[index] = manual_sliders[index].value
		var input = FourLimbMLFeatureEncoder.encode(observation)
		return {
			"action": FourLimbMLAction.from_commands(commands),
			"actor_input": input,
			"critic_input": input,
			"latent_action": commands.duplicate(),
			"commands": commands,
			"log_probability": 0.0,
			"value": 0.0,
			"manual": true,
		}
	return (group["trainer"] as FourLimbPPOTrainer).sample_validated_runtime_action(observation)


func _worker_termination(
	group: Dictionary,
	worker: Dictionary,
	observation: Dictionary
) -> Dictionary:
	var elapsed = float(worker.get("elapsed", 0.0))
	if elapsed >= DEFAULT_EPISODE_SECONDS:
		return {"finished": true, "timed_out": true, "reason": "timeout"}
	var body = worker.get("body") as FourLimbPhysicalBody3D
	if not is_instance_valid(body) or not body.is_body_alive():
		return {"finished": true, "timed_out": false, "reason": body.last_failure_reason if is_instance_valid(body) else "missing_body"}
	var body_state: Dictionary = observation.get("body", {})
	var position: Vector3 = body_state.get("position_world", Vector3.ZERO)
	var uprightness = float(body_state.get("uprightness", 0.0))
	var center: Vector3 = group.get("center", Vector3.ZERO)
	if position.y < -0.8:
		return {"finished": true, "timed_out": false, "reason": "fell_below_arena"}
	if Vector2(position.x - center.x, position.z - center.z).length() > 11.0:
		return {"finished": true, "timed_out": false, "reason": "left_training_area"}
	if elapsed > 1.0 and uprightness < -0.25:
		return {"finished": true, "timed_out": false, "reason": "upside_down"}
	var clearance = float(body_state.get("ground_clearance", 99.0))
	if uprightness < 0.20 and clearance < 0.60:
		if float(worker.get("fallen_since", -1.0)) < 0.0:
			worker["fallen_since"] = elapsed
		elif elapsed - float(worker.get("fallen_since", elapsed)) >= 1.0:
			return {"finished": true, "timed_out": false, "reason": "fallen_on_side"}
	else:
		worker["fallen_since"] = -1.0
	return {"finished": false}


func _finish_worker(
	group: Dictionary,
	worker: Dictionary,
	reason: String,
	timed_out: bool,
	observation: Dictionary
) -> void:
	if bool(worker.get("finished", false)):
		return
	worker["finished"] = true
	worker["failure_reason"] = reason
	var terminal = (group["reward_deck"] as FourLimbRewardDeck).terminal_reward(
		worker["reward_state"],
		"" if timed_out else reason,
		timed_out
	)
	var terminal_reward = float(terminal.get("total", 0.0))
	worker["interval_reward"] = float(worker.get("interval_reward", 0.0)) + terminal_reward
	worker["total_reward"] = float(worker.get("total_reward", 0.0)) + terminal_reward
	var trainer = group["trainer"] as FourLimbPPOTrainer
	var last_sample: Dictionary = worker.get("last_action_sample", {})
	if not last_sample.is_empty() and not bool(last_sample.get("manual", false)):
		trainer.add_transition(
			int(worker["id"]),
			last_sample,
			float(worker["interval_reward"]),
			observation,
			not timed_out,
			timed_out,
			maxf(float(worker.get("interval_elapsed_seconds", DECISION_INTERVAL_SECONDS)), 0.000001)
		)
	var body = worker.get("body") as FourLimbPhysicalBody3D
	if is_instance_valid(body):
		body.kill(reason)
		body.queue_free()


func _finish_group_episode(group: Dictionary) -> void:
	var workers: Array = group.get("workers", [])
	var total = 0.0
	for worker_value: Variant in workers:
		total += float((worker_value as Dictionary).get("total_reward", 0.0))
	var mean = total / float(maxi(workers.size(), 1))
	group["last_mean_reward"] = mean
	group["best_mean_reward"] = maxf(float(group.get("best_mean_reward", -INF)), mean)
	var trainer = group["trainer"] as FourLimbPPOTrainer
	trainer.record_completed_episode(mean)
	var update = trainer.update_if_ready(false)
	if not update.is_empty():
		group["last_update"] = update
	_start_group_episode(group)
	_refresh_group_cards(true)


func _clear_group_workers(group: Dictionary) -> void:
	for worker_value: Variant in group.get("workers", []):
		var body = (worker_value as Dictionary).get("body") as FourLimbPhysicalBody3D
		if is_instance_valid(body):
			body.queue_free()
	group["workers"] = []


func _prepare_group_target_for_episode(group: Dictionary) -> void:
	var center: Vector3 = group.get("center", Vector3.ZERO)
	match int(group.get("lesson", Lesson.APPROACH)):
		Lesson.STAND:
			group["target_position"] = center + Vector3(0.0, 1.35, 2.7)
		Lesson.RANDOM_WAYPOINTS:
			_choose_random_group_target(group)
		_:
			group["target_position"] = center + Vector3(0.0, 1.35, -5.5)
	group["waypoint_elapsed"] = 0.0
	var marker = group.get("target_marker") as Node3D
	if is_instance_valid(marker):
		marker.position = group["target_position"]


func _choose_random_group_target(group: Dictionary) -> void:
	var center: Vector3 = group.get("center", Vector3.ZERO)
	var rng = group.get("rng") as RandomNumberGenerator
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = int(group.get("id", 1)) * 991
		group["rng"] = rng
	group["target_position"] = center + Vector3(
		rng.randf_range(-6.0, 6.0),
		1.35,
		rng.randf_range(-6.0, 6.0)
	)
	var marker = group.get("target_marker") as Node3D
	if is_instance_valid(marker):
		marker.position = group["target_position"]


func _objective_for_group(group: Dictionary) -> Dictionary:
	return {
		"target_position_world": group.get("target_position", Vector3.ZERO),
		"target_velocity_world": Vector3.ZERO,
		"target_radius": TARGET_RADIUS,
	}


func _objective_for_worker(group: Dictionary, worker: Dictionary) -> Dictionary:
	var objective = _objective_for_group(group)
	if int(group.get("lesson", Lesson.APPROACH)) == Lesson.STAND:
		objective["target_position_world"] = worker.get(
			"stand_target_position",
			objective["target_position_world"]
		)
	return objective


func _worker_spawn_transform(
	group: Dictionary,
	worker_index: int,
	worker_count: int
) -> Transform3D:
	var columns = mini(3, worker_count)
	var row = floori(float(worker_index) / float(maxi(columns, 1)))
	var column = worker_index % columns
	var width = float(columns - 1) * 2.3
	var center: Vector3 = group.get("center", Vector3.ZERO)
	var position = center + Vector3(
		float(column) * 2.3 - width * 0.5,
		BODY_SPAWN_HEIGHT,
		float(row) * 2.4 + 3.5
	)
	return Transform3D(Basis.IDENTITY, position)


func _create_target_marker(position: Vector3, color: Color) -> Node3D:
	var root = Node3D.new()
	root.position = position
	target_container.add_child(root)
	var sphere = MeshInstance3D.new()
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.28
	sphere_mesh.height = 0.56
	sphere.mesh = sphere_mesh
	sphere.material_override = DroneTrainingRoomPresentation.material(color, true)
	root.add_child(sphere)
	var ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = TARGET_RADIUS - 0.04
	torus.outer_radius = TARGET_RADIUS + 0.04
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.material_override = DroneTrainingRoomPresentation.material(Color(color.r, color.g, color.b, 0.45), true)
	root.add_child(ring)
	return root


func _refresh_group_cards(force: bool) -> void:
	if group_list == null:
		return
	if not force and Engine.get_process_frames() % 15 != 0:
		return
	for child in group_list.get_children():
		child.queue_free()
	for group: Dictionary in groups:
		var selected = int(group["id"]) == selected_group_id
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style(selected, group["color"]))
		group_list.add_child(panel)
		var row = HBoxContainer.new()
		panel.add_child(row)
		var trainer = group["trainer"] as FourLimbPPOTrainer
		var button = Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\nEpisode %d · mean %.3f · best %.3f\nUpdate %d · steps %d" % [
			str(group["name"]),
			int(group["episode"]),
			float(group["last_mean_reward"]),
			float(group["best_mean_reward"]) if is_finite(float(group["best_mean_reward"])) else 0.0,
			trainer.update_count,
			trainer.environment_steps,
		]
		var group_id = int(group["id"])
		button.pressed.connect(func() -> void: _select_group(group_id))
		row.add_child(button)
		var remove = Button.new()
		remove.text = "×"
		remove.tooltip_text = "Remove this worker group."
		remove.add_theme_stylebox_override("normal", _button_style(false, true))
		remove.pressed.connect(func() -> void: _remove_group(group_id))
		row.add_child(remove)


func _select_group(group_id: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	selected_group_id = group_id
	if lesson_selector != null:
		lesson_selector.select(int(group.get("pending_lesson", group.get("lesson", Lesson.APPROACH))))
	if worker_count_input != null:
		worker_count_input.set_value_no_signal(float(group.get("pending_worker_count", group.get("worker_count", DEFAULT_WORKER_COUNT))))
	_refresh_group_cards(true)
	_rebuild_reward_cards()
	_refresh_manual_worker_list()


func _remove_group(group_id: int) -> void:
	if groups.size() <= 1:
		status_label.text = "At least one worker group must remain."
		return
	for index in range(groups.size()):
		if int(groups[index]["id"]) != group_id:
			continue
		_clear_group_workers(groups[index])
		var marker = groups[index].get("target_marker") as Node3D
		if is_instance_valid(marker):
			marker.queue_free()
		groups.remove_at(index)
		break
	if selected_group_id == group_id:
		selected_group_id = int(groups[0]["id"])
	if not loaded_map_obstacle_records.is_empty():
		_rebuild_loaded_map_obstacles()
	_refresh_group_cards(true)
	_rebuild_reward_cards()
	_refresh_manual_worker_list()


func _rebuild_reward_cards() -> void:
	if reward_card_list == null:
		return
	for child in reward_card_list.get_children():
		child.queue_free()
	reward_card_value_labels.clear()
	var group = _selected_group()
	if group.is_empty():
		return
	var deck = group["reward_deck"] as FourLimbRewardDeck
	var pending: Dictionary = group.get("pending_reward_config", {})
	for card_value: FourLimbRewardCard in deck.card_list():
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override(
			"panel",
			DroneTrainingRoomPresentation.reward_card_panel_style(card_value.signal_type)
		)
		reward_card_list.add_child(panel)
		var content = VBoxContainer.new()
		panel.add_child(content)
		var header = HBoxContainer.new()
		content.add_child(header)
		var enabled = CheckButton.new()
		enabled.text = card_value.display_name
		enabled.button_pressed = bool((pending.get(card_value.card_id, {}) as Dictionary).get("enabled", card_value.enabled))
		enabled.tooltip_text = card_value.explanation
		enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(enabled)
		var signal_label = Label.new()
		signal_label.text = card_value.signal_label()
		signal_label.add_theme_color_override(
			"font_color",
			DroneTrainingRoomPresentation.reward_signal_color(card_value.signal_type)
		)
		header.add_child(signal_label)
		var row = HBoxContainer.new()
		content.add_child(row)
		var slider = HSlider.new()
		slider.min_value = card_value.minimum_intensity
		slider.max_value = card_value.maximum_intensity
		slider.step = card_value.step
		slider.value = float((pending.get(card_value.card_id, {}) as Dictionary).get("intensity", card_value.intensity))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = card_value.explanation
		row.add_child(slider)
		var value_label = Label.new()
		value_label.text = "%.3f / %.3f" % [slider.value, card_value.maximum_intensity]
		value_label.custom_minimum_size.x = 112.0
		row.add_child(value_label)
		var contribution_label = Label.new()
		contribution_label.text = "Now +0.0000 · Episode +0.000"
		contribution_label.modulate = Color(0.76, 0.84, 0.82, 1.0)
		content.add_child(contribution_label)
		var card_id = card_value.card_id
		var group_id = int(group["id"])
		reward_card_value_labels[card_id] = contribution_label
		enabled.toggled.connect(
			_on_reward_card_enabled_toggled.bind(group_id, card_id)
		)
		slider.value_changed.connect(
			_on_reward_card_intensity_changed.bind(
				group_id,
				card_id,
				value_label.get_instance_id(),
				card_value.maximum_intensity
			)
		)
	_refresh_reward_card_values({})


func _on_reward_card_enabled_toggled(
	value: bool,
	group_id: int,
	card_id: String
) -> void:
	var group = _group_by_id(group_id)
	if not group.is_empty():
		_queue_reward_change(group, card_id, "enabled", value)


func _on_reward_card_intensity_changed(
	value: float,
	group_id: int,
	card_id: String,
	value_label_instance_id: int,
	maximum_intensity: float
) -> void:
	var value_label = instance_from_id(value_label_instance_id) as Label
	if is_instance_valid(value_label):
		value_label.text = "%.3f / %.3f" % [value, maximum_intensity]
	var group = _group_by_id(group_id)
	if not group.is_empty():
		_queue_reward_change(group, card_id, "intensity", value)


func _refresh_reward_card_values(worker_state: Dictionary) -> void:
	var current: Dictionary = worker_state.get("last_components", {})
	var totals: Dictionary = worker_state.get("episode_totals", {})
	for card_id: String in reward_card_value_labels:
		var label = reward_card_value_labels[card_id]
		if not is_instance_valid(label):
			continue
		label.text = "Now %+.4f · Episode %+.3f" % [
			float(current.get(card_id, 0.0)),
			float(totals.get(card_id, 0.0)),
		]


func _queue_reward_change(
	group: Dictionary,
	card_id: String,
	key: String,
	value: Variant
) -> void:
	var pending: Dictionary = group.get("pending_reward_config", {})
	var card_pending: Dictionary = pending.get(card_id, {})
	card_pending[key] = value
	pending[card_id] = card_pending
	group["pending_reward_config"] = pending


func _apply_pending_reward_config(group: Dictionary) -> void:
	var pending: Dictionary = group.get("pending_reward_config", {})
	if pending.is_empty():
		return
	var deck = group["reward_deck"] as FourLimbRewardDeck
	for card_id: String in pending:
		var card_value = deck.card(card_id)
		if card_value == null:
			continue
		var values: Dictionary = pending[card_id]
		card_value.enabled = bool(values.get("enabled", card_value.enabled))
		card_value.intensity = clampf(
			float(values.get("intensity", card_value.intensity)),
			card_value.minimum_intensity,
			card_value.maximum_intensity
		)
	group["pending_reward_config"] = {}


func _refresh_manual_worker_list() -> void:
	if manual_worker_selector == null:
		return
	manual_worker_selector.clear()
	var group = _selected_group()
	for worker_value: Variant in group.get("workers", []):
		var worker: Dictionary = worker_value
		manual_worker_selector.add_item("Worker %d" % int(worker["id"]), int(worker["id"]))


func _refresh_diagnostics() -> void:
	if diagnostics_label == null or Engine.get_physics_frames() % 5 != 0:
		return
	var group = _selected_group()
	if group.is_empty():
		diagnostics_label.text = "No group selected."
		_refresh_reward_card_values({})
		return
	var selected_worker_id = manual_worker_selector.get_selected_id()
	var worker = _worker_by_id(group, selected_worker_id)
	if worker.is_empty():
		var workers: Array = group.get("workers", [])
		worker = workers[0] if not workers.is_empty() else {}
	if worker.is_empty():
		diagnostics_label.text = "Waiting for workers."
		_refresh_reward_card_values({})
		return
	var observation: Dictionary = worker.get("previous_physics_observation", {})
	var body_state: Dictionary = observation.get("body", {})
	var reward_state: Dictionary = worker.get("reward_state", {})
	_refresh_reward_card_values(reward_state)
	var text = "[b]%s · Worker %d[/b]\n" % [str(group["name"]), int(worker["id"])]
	var body_velocity: Vector3 = body_state.get("linear_velocity_world", Vector3.ZERO)
	text += "Reward %.3f · Upright %.2f · Height %.2f m · Speed %.2f m/s\n" % [
		float(worker.get("total_reward", 0.0)),
		float(body_state.get("uprightness", 0.0)),
		float(body_state.get("ground_clearance", 0.0)),
		body_velocity.length(),
	]
	for limb_value: Variant in observation.get("limbs", []):
		var limb: Dictionary = limb_value
		var commands: Vector3 = limb.get("commands", Vector3.ZERO)
		var angles: Vector3 = limb.get("joint_angles", Vector3.ZERO)
		var torque: Vector3 = limb.get("applied_torque", Vector3.ZERO)
		text += "%s: cmd [%.2f %.2f %.2f] · angle [%.2f %.2f %.2f] · torque [%.1f %.1f %.1f] · foot %s\n" % [
			str(limb.get("slot_name", "Limb")), commands.x, commands.y, commands.z,
			angles.x, angles.y, angles.z, torque.x, torque.y, torque.z,
			"grounded" if bool(limb.get("foot_contact", false)) else "air",
		]
	text += "\n[b]Current reward contributions[/b]\n"
	var last_components: Dictionary = reward_state.get("last_components", {})
	for card_id: String in last_components:
		text += "%s: %+.4f\n" % [card_id.replace("_", " ").capitalize(), float(last_components[card_id])]
	diagnostics_label.text = text


func _on_lesson_selected(index: int) -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	group["pending_lesson"] = clampi(index, 0, LESSON_NAMES.size() - 1)
	status_label.text = "Lesson change will apply when the selected group starts its next episode."


func _on_worker_count_changed(value: float) -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	group["pending_worker_count"] = clampi(int(round(value)), 1, MAXIMUM_WORKER_COUNT)
	status_label.text = "Worker-count change will apply when the selected group starts its next episode."


func _on_pause_pressed() -> void:
	globally_paused = not globally_paused
	pause_button.text = "RESUME" if globally_paused else "PAUSE"
	for group: Dictionary in groups:
		for worker_value: Variant in group.get("workers", []):
			var body = (worker_value as Dictionary).get("body") as FourLimbPhysicalBody3D
			if is_instance_valid(body) and is_instance_valid(body.physical_rig):
				body.physical_rig.set_runtime_active(not globally_paused)


func _on_back_pressed() -> void:
	SceneController.leave_four_limb_training_room()


func _save_selected_group() -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	var checkpoint = (group["trainer"] as FourLimbPPOTrainer).to_checkpoint(
		walker_preset_template.hardware_signature(),
		(group["reward_deck"] as FourLimbRewardDeck).configuration_dictionary()
	)
	var record = model_registry.save_checkpoint(model_name_input.text, checkpoint)
	status_label.text = (
		"Saved %s" % model_registry.display_name(record)
		if not record.is_empty()
		else model_registry.last_error
	)


func _open_model_library() -> void:
	model_library_records = model_registry.list_models()
	model_library_list.clear()
	for record: Dictionary in model_library_records:
		model_library_list.add_item("%s · %s" % [
			model_registry.display_name(record),
			str(record.get("algorithm", "four_limb_ppo")),
		])
	model_library_window.popup_centered()


func _load_selected_model() -> void:
	var selected = model_library_list.get_selected_items()
	if selected.is_empty() or selected[0] >= model_library_records.size():
		return
	var group = _selected_group()
	if group.is_empty():
		return
	var checkpoint = model_registry.load_checkpoint(model_library_records[selected[0]])
	if checkpoint.is_empty():
		status_label.text = model_registry.last_error
		return
	if not (group["trainer"] as FourLimbPPOTrainer).load_checkpoint(
		checkpoint,
		walker_preset_template.hardware_signature()
	):
		status_label.text = (group["trainer"] as FourLimbPPOTrainer).last_error
		return
	if checkpoint.get("reward_cards", {}) is Dictionary:
		(group["reward_deck"] as FourLimbRewardDeck).load_configuration(checkpoint["reward_cards"])
	group["pending_reward_config"] = {}
	_start_group_episode(group)
	_rebuild_reward_cards()
	status_label.text = "Loaded %s" % model_registry.display_name(model_library_records[selected[0]])
	model_library_window.hide()


func _delete_selected_model() -> void:
	var selected = model_library_list.get_selected_items()
	if selected.is_empty() or selected[0] >= model_library_records.size():
		return
	if model_registry.delete_model(model_library_records[selected[0]]):
		_open_model_library()
	else:
		status_label.text = model_registry.last_error


func _open_map_library() -> void:
	map_library_records = map_registry.list_maps()
	map_library_list.clear()
	for record: Dictionary in map_library_records:
		map_library_list.add_item("%s · %d obstacle(s)" % [
			map_registry.display_name(record),
			int(record.get("obstacle_count", 0)),
		])
	map_library_window.popup_centered()


func _load_selected_map() -> void:
	var selected = map_library_list.get_selected_items()
	if selected.is_empty() or selected[0] >= map_library_records.size():
		return
	var record = map_registry.get_map(str(map_library_records[selected[0]].get("map_id", "")))
	if record.is_empty():
		status_label.text = map_registry.last_error
		return
	_replace_obstacles(record.get("obstacles", []))
	map_registry.mark_used(record)
	status_label.text = "Loaded %s" % map_registry.display_name(record)
	map_library_window.hide()


func _delete_selected_map() -> void:
	var selected = map_library_list.get_selected_items()
	if selected.is_empty() or selected[0] >= map_library_records.size():
		return
	if map_registry.delete_map(map_library_records[selected[0]]):
		_open_map_library()
	else:
		status_label.text = map_registry.last_error


func _replace_obstacles(records: Array) -> void:
	loaded_map_obstacle_records = records.duplicate(true)
	_rebuild_loaded_map_obstacles()


func _rebuild_loaded_map_obstacles() -> void:
	for child in custom_obstacle_container.get_children():
		child.queue_free()
	var counter = 0
	# Map coordinates are authored around the map origin in the drone room. Each independent
	# physical-body group receives the same layout translated to that group's arena centre.
	for group: Dictionary in groups:
		var group_center: Vector3 = group.get("center", Vector3.ZERO)
		for value: Variant in loaded_map_obstacle_records:
			if not (value is Dictionary):
				continue
			var record: Dictionary = value
			var shape_kind = clampi(
				int(record.get("shape_kind", DroneTrainingObstacleShape.Kind.BOX)),
				0,
				DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
			)
			var dimensions: Dictionary = record.get("dimensions_m", {})
			var local_position = _vector3_from_array(
				record.get("position_m", []),
				Vector3.ZERO
			)
			var rotation = _vector3_from_array(
				record.get("rotation_degrees", []),
				Vector3.ZERO
			)
			counter += 1
			var obstacle = DroneTrainingRoomPresentation.add_static_obstacle(
				custom_obstacle_container,
				"LoadedObstacle_G%d_%03d" % [int(group.get("id", 0)), counter],
				group_center + local_position,
				shape_kind,
				dimensions,
				Color(0.72, 0.39, 0.15, 1.0),
				ARENA_COLLISION_LAYER,
				BODY_COLLISION_LAYER
			)
			obstacle.rotation_degrees = rotation


func _update_camera(_delta: float) -> void:
	if not is_instance_valid(spectator_camera):
		return
	var group = _selected_group()
	var target = Vector3(18.0, 1.5, 18.0)
	if not group.is_empty():
		var alive_positions: Array[Vector3] = []
		for worker_value: Variant in group.get("workers", []):
			var body = (worker_value as Dictionary).get("body") as FourLimbPhysicalBody3D
			if is_instance_valid(body) and body.is_body_alive():
				alive_positions.append(body.core_transform().origin)
		if not alive_positions.is_empty():
			target = Vector3.ZERO
			for position: Vector3 in alive_positions:
				target += position
			target /= float(alive_positions.size())
		else:
			var group_center: Vector3 = group.get("center", target)
			target = group_center + Vector3.UP * 1.0
	var direction = Vector3(
		cos(camera_pitch) * sin(camera_yaw),
		sin(-camera_pitch),
		cos(camera_pitch) * cos(camera_yaw)
	).normalized()
	spectator_camera.global_position = target + direction * camera_distance
	spectator_camera.look_at(target, Vector3.UP)


func _next_free_group_layout_slot() -> int:
	var occupied: Dictionary[int, bool] = {}
	for group: Dictionary in groups:
		var slot = int(group.get("layout_slot", -1))
		if slot >= 0:
			occupied[slot] = true
	var candidate = 0
	while occupied.has(candidate):
		candidate += 1
	return candidate


func _group_by_id(group_id: int) -> Dictionary:
	for group: Dictionary in groups:
		if int(group.get("id", -1)) == group_id:
			return group
	return {}


func _selected_group() -> Dictionary:
	return _group_by_id(selected_group_id)


func _worker_by_id(group: Dictionary, worker_id: int) -> Dictionary:
	for worker_value: Variant in group.get("workers", []):
		var worker: Dictionary = worker_value
		if int(worker.get("id", -1)) == worker_id:
			return worker
	return {}


func _command_change_norm(
	previous: PackedFloat64Array,
	current: PackedFloat64Array
) -> float:
	if previous.size() != current.size() or current.is_empty():
		return 0.0
	var sum = 0.0
	for index in range(current.size()):
		sum += pow(current[index] - previous[index], 2.0)
	return sqrt(sum)


func _vector3_from_array(value: Variant, fallback: Vector3) -> Vector3:
	if not (value is Array) or (value as Array).size() < 3:
		return fallback
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _add_button(
	parent: Control,
	text_value: String,
	callback: Callable,
	accent: bool = false,
	danger: bool = false
) -> Button:
	var button = Button.new()
	button.text = text_value
	button.add_theme_stylebox_override("normal", _button_style(accent, danger))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _panel_style(
	selected: bool,
	accent_color: Color = Color(0.12, 0.58, 0.42, 1.0)
) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.075, 0.062, 0.96)
	style.border_color = accent_color if selected else Color(0.08, 0.35, 0.28, 1.0)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


func _button_style(accent: bool, danger: bool) -> StyleBoxFlat:
	if danger:
		return DroneTrainingRoomPresentation.scanner_danger_button_style()
	return DroneTrainingRoomPresentation.scanner_button_style(accent)

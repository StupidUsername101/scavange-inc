class_name DroneTrainingRoom
extends Node3D

const DRONE_SCENE = preload("res://scenes/server/server_drone.tscn")
const PLOT_SCRIPT = preload("res://ml/training/ui/drone_training_plot.gd")
const ACTION_TRACE_BUFFER_SCRIPT = preload("res://ml/training/drone_training_action_trace_buffer.gd")
const ACTION_TRACE_PANEL_SCRIPT = preload("res://ml/training/ui/drone_training_action_trace_panel.gd")
const ROLLING_SAVE_BUTTON_SCRIPT = preload("res://ml/training/ui/drone_training_rolling_save_button.gd")
const TARGET_PAD_SCRIPT = preload("res://ml/training/ui/drone_training_target_pad.gd")
const CANDIDATE_EVALUATION_JOB_SCRIPT = preload("res://ml/training/drone_candidate_evaluation_job.gd")
const FOUR_LIMB_CANDIDATE_EVALUATION_JOB_SCRIPT = preload("res://ml/training/evaluation/four_limb_candidate_evaluation_job.gd")
const TURRET_CANDIDATE_EVALUATION_JOB_SCRIPT = preload("res://ml/training/evaluation/turret_candidate_evaluation_job.gd")
const TRAINING_CAMERA_ATTACHMENT = preload("res://resources/drones/attachments/training_observer_camera.tres")
const LOADOUT_CONFIG = preload("res://ml/training/drone_training_loadout_config.gd")
const QUAD_PROPELLER_COUNT = 4
const ARENA_SIZE = Vector3(100, 8.0, 100)
const DEFAULT_DRONE_SPAWN_POSITION = Vector3(-7.0, 1.2, 4.5)
const TARGET_START = Vector3(0.0, 5.0, 0.0)
const TARGET_BEHAVIORS = TrainingPathTargetSystem.BEHAVIORS
const MANUAL_TARGET_BEHAVIOR = TrainingPathTargetSystem.MANUAL_BEHAVIOR
const TARGET_PAD_MARGIN_M = 1.0
const TARGET_MARKER_COLOR = Color("ff3d71")
const DRONE_SPAWN_PAD_MARGIN_M = 1.0
const DRONE_SPAWN_MINIMUM_HEIGHT_M = 0.45
const DRONE_SPAWN_MAXIMUM_HEIGHT_M = 7.5
const DRONE_SPAWN_MARKER_COLOR = Color("55d9ff")
const OBSTACLE_SENSOR_INTERVAL_SECONDS = 0.05
const TRAINING_CONTACTS_REPORTED = 12
const TELEMETRY_REFRESH_SECONDS = 0.2
const EPISODE_INTERMISSION_SECONDS = 1.0
const EPISODE_SEED_BASE = 4194301
const CANDIDATE_EVALUATION_MAX_CONCURRENT = 1
# Hidden candidates collide with the arena through their mask but publish no collision layer,
# so live training projectiles/drones cannot accidentally perturb the supposedly fixed suite.
const CANDIDATE_EVALUATION_COLLISION_LAYER = 0
const CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS = 8.0
const FRAME_HITCH_THRESHOLD_MS = 20.0
const DRONE_COLLISION_LAYER = 1 << 1
const FOUR_LIMB_COLLISION_LAYER = 1 << 2
const TRAINING_BODY_COLLISION_MASK = DRONE_COLLISION_LAYER | FOUR_LIMB_COLLISION_LAYER
const ARENA_COLLISION_LAYER = 1
const INTERFACE_MARGIN = 12.0
const LEFT_PANEL_GAP = 10.0
const COLLAPSED_PANEL_WIDTH = 44.0
const WORKER_PANEL_MINIMUM_WIDTH = 220.0
const WORKER_PANEL_MAXIMUM_WIDTH = 620.0
const LEFT_PANEL_MINIMUM_WIDTH = 350.0
const LEFT_PANEL_MAXIMUM_WIDTH = 860.0
const RIGHT_PANEL_MINIMUM_WIDTH = 300.0
const RIGHT_PANEL_MAXIMUM_WIDTH = 1320.0
const RIGHT_PANEL_DEFAULT_VIEWPORT_RATIO = 0.136
const MINIMUM_ARENA_VIEW_WIDTH = 440.0
const CAMERA_FOCUS = Vector3(0.0, 2.4, 0.0)
const CAMERA_MINIMUM_DISTANCE = 1.25
const CAMERA_MAXIMUM_DISTANCE = 150.0
const CAMERA_ORBIT_SENSITIVITY = 0.005
const CAMERA_ZOOM_STEP = 1.18
const CAMERA_FOCUS_SMOOTHING_RATE = 5.0
const CAMERA_FINISHED_DRONE_FADE_SECONDS = 1.0
const CAMERA_AUTO_ORBIT_DEFAULT_SPEED_DEGREES = 8.0
const CAMERA_FOCUS_MODES: Array[String] = [
	"Room center",
	"Live target",
	"Drone spawn",
	"Selected group / evaluator",
	"All training bodies",
	"Random selected-group drone (attached)",
]
const CAMERA_FOCUS_SELECTED_SUBJECT = 3
const CAMERA_FOCUS_ATTACHED_RANDOM_DRONE = 5
const CUSTOM_WALL_DEFAULT_WIDTH_M = 4.0
const CUSTOM_WALL_DEFAULT_HEIGHT_M = 3.0
const CUSTOM_WALL_DEFAULT_THICKNESS_M = 0.35
const CUSTOM_WALL_COLOR = Color("34485c")
const CUSTOM_WALL_SELECTED_COLOR = Color("f0a84b")
const CUSTOM_WALL_PREVIEW_COLOR = Color(0.33, 0.82, 1.0, 0.42)
const EDITOR_PICK_RAY_LENGTH_M = 1000000.0
const TRAINING_ITEM_DEFAULT_DEFINITION: TrainingItemDefinition = preload(
	"res://resources/training/items/generic_cargo.tres"
)
const TRAINING_ITEM_DEFAULT_TYPE: String = TrainingItem3D.DEFAULT_ITEM_TYPE
const DELIVERY_DESTINATION_DEFAULT_RADIUS_M = 1.25
const DELIVERY_DESTINATION_DEFAULT_HEIGHT_M = 1.25
const DELIVERY_DESTINATION_PREVIEW_ALPHA = 0.34
const DELIVERY_DESTINATION_MINIMUM_SURFACE_NORMAL_Y = 0.55
const DELIVERY_DESTINATION_COLORS: Array[Color] = [
	Color("54e6b1"), Color("8de1ff"), Color("ffad42"), Color("b08cff"),
	Color("ff6b8a"), Color("7ee787"),
]
const TRAINING_ITEM_PREVIEW_COLOR = Color(0.95, 0.72, 0.29, 0.46)
const TRAINING_ITEM_MINIMUM_SURFACE_NORMAL_Y = 0.55
const TRAINING_ITEM_PLACEMENT_MAXIMUM_RAY_RETRIES = 8
const TRAINING_ITEM_RECOVERY_MARGIN_M = TrainingItem3D.DEFAULT_RECOVERY_HORIZONTAL_MARGIN_M
const TRAINING_ITEM_RECOVERY_MINIMUM_Y_M = TrainingItem3D.DEFAULT_RECOVERY_MINIMUM_WORLD_Y_M
const TRAINING_ITEM_RECOVERY_MAXIMUM_Y_M = TrainingItem3D.DEFAULT_RECOVERY_MAXIMUM_WORLD_Y_M
const TURRET_PLACEMENT_MINIMUM_UP_NORMAL = 0.55
const TURRET_PLACEMENT_PREVIEW_ALPHA = 0.48
const SIMULATION_SPEEDS: Array[float] = [
	1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0,
]
const GROUP_NAME_MAX_LENGTH = 48
const MODEL_BROWSER_SIZE = Vector2i(1080, 760)
const MAP_BROWSER_SIZE = Vector2i(1040, 720)
const ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA = 1.0
const ACTION_TRACE_FULLSCREEN_MINIMUM_ALPHA = 0.20
const DEFAULT_BRANCH_WEIGHT_VARIATION = 0.025
const MAXIMUM_BRANCH_WEIGHT_VARIATION = 0.20
const GROUP_TREE_INDENT = 18.0
const BOX_RESIZE_MAXIMUM_HEIGHT = 900.0
const BOX_OPEN_ANIMATION_SECONDS = 0.18
const GROUP_ACTIVITY_ANIMATION_INTERVAL_SECONDS = 0.30
const GROUP_ACTIVITY_FRAMES = [".", "..", "...", "...."]
const DRONE_DISABLE_SOUND_DIRECTORY = "res://assets/sounds/hit_effects"
const DRONE_DISABLE_SOUND_DEFAULT_VOLUME_DB = -16.0
const DRONE_DISABLE_SOUND_MINIMUM_VOLUME_DB = -40.0
const DRONE_DISABLE_SOUND_MAXIMUM_VOLUME_DB = -3.0
const DRONE_DISABLE_SOUND_MAX_DISTANCE_M = 90.0
const DRONE_DISABLE_SOUND_PLAYER_COUNT = 8
#######################################################
# Scanner-style mixed-body learning lab. The established quadrotor path remains the default;
# optional four-limb and turret groups share the arena while keeping independent trainers,
# target handlers, checkpoints, reward decks, and worker populations.
#######################################################

var model_registry = DroneTrainingModelRegistry.new()
var limb_model_registry = FourLimbModelRegistry.new()
var turret_model_registry = TurretModelRegistry.new()
var limb_training = FourLimbTrainingCoordinator.new()
var turret_training = TurretTrainingCoordinator.new()
var turret_ui = TurretTrainingRoomUI.new()
var training_entity_spatial_hash = ServerSpatialHash3D.new(4.0)
var map_registry = DroneTrainingMapRegistry.new()
var model_versions: Array[Dictionary] = []
var worker_groups: Array[Dictionary] = []
var worker_groups_by_id: Dictionary = {}
var trials: Array[Dictionary] = []
var group_counter = 0
var instance_counter = 0
var selected_group_id = -1
var selected_limb_group_id = -1
var selected_turret_group_id = -1
var selected_evaluator_instance_id = -1
var retired_trainers: Array[DroneTrainingAlgorithm] = []
var background_optimizer_limit = maxi(OS.get_processor_count() - 2, 1)
var frame_monitor_elapsed = 0.0
var frame_monitor_worst_ms = 0.0
var frame_monitor_hitches = 0
var recent_worst_frame_ms = 0.0
var recent_frame_hitches = 0
var group_activity_animation_elapsed = 0.0
var group_activity_animation_frame = 0
var drone_disable_sounds: Array[AudioStream] = []
var drone_disable_sound_players: Array[AudioStreamPlayer3D] = []
var drone_disable_sound_player_cursor = 0
var drone_disable_sound_rng = RandomNumberGenerator.new()
var drone_disable_sound_volume_db = DRONE_DISABLE_SOUND_DEFAULT_VOLUME_DB

var target_marker: MeshInstance3D
var target_radius_ring: MeshInstance3D
var default_target_handler: TrainingTargetHandler
var target_handlers_by_group_id: Dictionary = {}
var target_visuals_by_group_id: Dictionary = {}
var target_contexts_by_group_id: Dictionary = {}
var default_target_context: Dictionary = {}
var resolved_targets_by_group_cache: Dictionary = {}
var default_target_visual_has_state: bool = false
var default_target_visual_position: Vector3 = Vector3.ZERO
var default_target_visual_radius_m: float = -1.0
var target_editor_type_id: String = str(TrainingPathTargetSystem.TYPE_ID)
var target_random_area_preview: MeshInstance3D
var target_random_area_checkbox: CheckBox
var target_context_label: Label
var target_type_picker: OptionButton
var target_worker_group_row: HBoxContainer
var target_worker_group_picker: OptionButton
var target_behavior_row: HBoxContainer
var target_runtime_info_label: Label
var turret_runtime_target_ids_by_group_id: Dictionary = {}

var drone_spawn_position = DEFAULT_DRONE_SPAWN_POSITION
var drone_spawn_marker: MeshInstance3D
var drone_spawn_pad: Control
var drone_spawn_height_input: SpinBox
var drone_spawn_position_label: Label

var wall_spatial_hash = DroneTrainingWallSpatialHash.new()
var wall_spatial_hash_dirty = true
var fixed_training_walls: Array[StaticBody3D] = []
var custom_wall_container: Node3D
var custom_walls: Array[StaticBody3D] = []
var custom_wall_counter = 0
var wall_shape_kind = DroneTrainingObstacleShape.Kind.BOX
var wall_dimensions: Dictionary = {
	"width": CUSTOM_WALL_DEFAULT_WIDTH_M,
	"height": CUSTOM_WALL_DEFAULT_HEIGHT_M,
	"depth": CUSTOM_WALL_DEFAULT_THICKNESS_M,
	"radius": 1.0,
}
var wall_pitch_degrees = 0.0
var wall_yaw_degrees = 0.0
var wall_roll_degrees = 0.0
var wall_position_x_m = 0.0
var wall_position_y_m = CUSTOM_WALL_DEFAULT_HEIGHT_M * 0.5
var wall_position_z_m = 0.0
var wall_placement_active = false
var wall_preview: MeshInstance3D
var turret_placement_active = false
var turret_placement_group_id = -1
var turret_placement_worker_index = 0
var turret_placement_adds_worker = false
var turret_placement_position = Vector3.ZERO
var turret_placement_yaw_degrees = 0.0
var turret_placement_preview: Node3D
var turret_placement_activate_on_confirm = true
var turret_placement_restore_active = false
var turret_placement_restore_had_workers = false
var selected_custom_wall: StaticBody3D
var wall_drag_active = false
var wall_drag_start_position = Vector3.ZERO
var wall_drag_offset = Vector2.ZERO
var wall_drag_changed = false
var wall_shape_picker: OptionButton
var wall_dimensions_body: VBoxContainer
var wall_dimension_inputs: Dictionary = {}
var wall_dimension_link_buttons: Dictionary = {}
var wall_linked_dimensions_by_shape: Dictionary = {}
var wall_dimension_sync_in_progress = false
var wall_pitch_input: SpinBox
var wall_yaw_input: SpinBox
var wall_roll_input: SpinBox
var wall_position_x_input: SpinBox
var wall_position_y_input: SpinBox
var wall_position_z_input: SpinBox
var wall_place_button: Button
var wall_apply_button: Button
var wall_delete_button: Button
var wall_auto_replace_button: Button
var wall_auto_replace_enabled = false
var wall_status_label: Label

var training_item_container: Node3D
var training_items: Array[TrainingItem3D] = []
var training_item_counter: int = 0
var training_item_shape_kind: int = DroneTrainingObstacleShape.Kind.BOX
var training_item_dimensions: Dictionary = {}
var training_item_linked_dimensions_by_shape: Dictionary = {}
var training_item_dimension_sync_in_progress: bool = false
var training_item_mass_kg: float = 0.0
var training_item_reward_value: float = 0.0
var training_item_type: String = ""
var training_item_pitch_degrees: float = 0.0
var training_item_yaw_degrees: float = 0.0
var training_item_roll_degrees: float = 0.0
var training_item_position_x_m: float = 0.0
var training_item_position_y_m: float = 0.0
var training_item_position_z_m: float = 0.0
var training_item_placement_active: bool = false
var training_item_preview: MeshInstance3D
var selected_training_item: TrainingItem3D
var training_item_shape_picker: OptionButton
var training_item_dimensions_body: VBoxContainer
var training_item_dimension_inputs: Dictionary = {}
var training_item_dimension_link_buttons: Dictionary = {}
var training_item_mass_input: SpinBox
var training_item_reward_input: SpinBox
var training_item_type_input: LineEdit
var training_item_pitch_input: SpinBox
var training_item_yaw_input: SpinBox
var training_item_roll_input: SpinBox
var training_item_position_x_input: SpinBox
var training_item_position_y_input: SpinBox
var training_item_position_z_input: SpinBox
var training_item_place_button: Button
var training_item_apply_button: Button
var training_item_delete_button: Button
var training_item_status_label: Label

var delivery_destination_container: Node3D
var delivery_destination_groups: Array[Dictionary] = []
var delivery_destination_groups_by_id: Dictionary = {}
var delivery_destination_group_counter: int = 0
var delivery_destination_list: VBoxContainer
var delivery_destination_dialog: ConfirmationDialog
var delivery_destination_dialog_title: Label
var delivery_destination_name_input: LineEdit
var delivery_destination_accept_all_checkbox: CheckBox
var delivery_destination_types_input: LineEdit
var delivery_destination_available_types_label: Label
var delivery_destination_radius_input: SpinBox
var delivery_destination_height_input: SpinBox
var delivery_destination_approach_reward_input: SpinBox
var delivery_destination_completion_reward_input: SpinBox
var delivery_destination_dialog_group_id: int = -1
var delivery_destination_placement_active: bool = false
var delivery_destination_placement_group_id: int = -1
var delivery_destination_placement_position: Vector3 = Vector3.ZERO
var delivery_destination_preview: MeshInstance3D
var delivery_destination_preview_mesh: CylinderMesh
var delivery_destination_preview_material: StandardMaterial3D

var episode_duration = DroneTrainingEpisode.DEFAULT_DURATION_SECONDS
var unlimited_episode_battery = true
var episode_number = 0
var episode_seed = EPISODE_SEED_BASE
var episode_elapsed = 0.0
var episode_running = false
var auto_restart_episodes = true
var evaluation_drones_keep_episode_running = false
var intermission_remaining = 0.0
var candidate_evaluations_by_group_id: Dictionary = {}
var candidate_evaluation_environment_revision: int = 0
var candidate_evaluation_queue_sequence: int = 0

var telemetry_next_refresh_usec = 0
var previous_render_tick_usec = 0
var status_label: Label
var episode_status_label: Label
var group_list: VBoxContainer
var all_groups_pause_button: Button
var model_body_creator: MLBodyCreatorPanel
var worker_camera_split: VSplitContainer
var evaluator_list: VBoxContainer
var evaluator_summary_label: Label
var selected_group_panel: Control
var worker_panel: PanelContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var worker_panel_body: Control
var left_panel_body: Control
var right_panel_body: Control
var worker_panel_title: Label
var left_panel_title: Label
var worker_panel_collapse_button: Button
var left_panel_collapse_button: Button
var right_panel_collapse_button: Button
var worker_panel_collapsed = false
var left_panel_collapsed = false
var right_panel_collapsed = false
var worker_panel_width_override = 0.0
var left_panel_width_override = 0.0
var right_panel_width_override = 0.0
var worker_panel_resize_handle: Control
var left_panel_resize_handle: Control
var right_panel_resize_handle: Control
var worker_content: VBoxContainer
var left_content: VBoxContainer
var right_content: VBoxContainer
var selected_group_title: Label
var selected_group_status: Label
var selected_group_auto_save_label: Label
var reward_card_list: VBoxContainer
var reward_card_note: Label
var reward_card_value_labels: Dictionary[String, Label] = {}
var reward_card_intensity_labels: Dictionary[String, Label] = {}
var reward_card_refresh_signature = ""
var reward_cardset_library = TrainingRewardCardsetLibrary.new()
var reward_cardset_tabs: TabBar
var reward_cardset_records: Array[Dictionary] = []
var reward_cardset_name_input: LineEdit
var reward_cardset_delete_button: Button
var suppress_reward_cardset_tab_signal = false
var limb_model_browser: Window
var limb_model_list: ItemList
var limb_model_records: Array[Dictionary] = []
var limb_model_name_edit: LineEdit
var selected_group_root_button: Button
var selected_group_branch_button: Button
var selected_group_distribute_button: Button
var model_save_best_button: Button
var model_save_current_button: Button
var model_library_button: Button
var drone_loadout_body: VBoxContainer
var limb_body_tuning_body: VBoxContainer
var limb_body_tuning_label: Label
var limb_body_stat_inputs: Dictionary = {}
var limb_body_edit_controls: Array[Control] = []
var worker_count_slider: HSlider
var control_rate_slider: HSlider
var ground_contact_terminal_checkbox: CheckBox
var flipped_terminal_checkbox: CheckBox
var algorithm_config_sliders: Dictionary = {}
var algorithm_controls_body: VBoxContainer
var algorithm_controls_id = ""
var selected_group_controls: Array[HSlider] = []
var loadout_summary_label: Label
var linked_flight_power_input: SpinBox
var loadout_core_picker: OptionButton
var loadout_battery_picker: OptionButton
var loadout_propeller_picker: OptionButton
var loadout_stat_inputs: Dictionary = {}
var loadout_edit_controls: Array[Control] = []
var model_version_list: Tree
var selected_model_version_id = ""
var model_list_refreshing = false
var model_browser: Window
var model_browser_context_label: Label
var model_inspection_label: Label
var model_browser_pause_button: Button
var target_behavior_picker: OptionButton
var target_behavior_settings_body: VBoxContainer
var target_height_input: SpinBox
var target_position_label: Label
var simulation_speed_picker: OptionButton
var unlimited_episode_battery_checkbox: CheckBox
var evaluation_keep_episode_checkbox: CheckBox
var target_pad: Control
var action_trace_buffer = ACTION_TRACE_BUFFER_SCRIPT.new()
var action_trace_panel: Control
var action_trace_card: PanelContainer
var action_trace_body: VBoxContainer
var action_trace_header_button: Button
var action_trace_fullscreen_button: Button
var action_trace_resize_handle: Control
var action_trace_fullscreen_overlay: PanelContainer
var action_trace_fullscreen_host: VBoxContainer
var action_trace_fullscreen_alpha_input: SpinBox
var action_trace_original_parent: Node
var action_trace_original_index = -1
var action_trace_fullscreen = false
var action_trace_was_expanded = true
var plot_grid: GridContainer
var plot_widgets: Dictionary = {}
var plot_cards: Dictionary = {}
var plot_title_labels: Dictionary = {}
var plot_expand_buttons: Dictionary = {}
var plot_cut_buttons: Dictionary = {}
var closed_plots: Dictionary = {}
var expanded_plot_id = ""
var plots_dirty = true
var training_identity_label: Label
var loader_identity_label: Label
var load_model_button: Button
var model_browser_branch_source_mode = false
var spawn_evaluator_button: Button
var delete_model_button: Button
var model_delete_dialog: ConfirmationDialog
var model_batch_selection_label: Label
var model_batch_selected_ids: Dictionary = {}
var pending_delete_version_ids: Array[String] = []
var map_browser: Window
var map_list: Tree
var map_name_edit: LineEdit
var map_inspection_label: Label
var map_selected_id = ""
var map_list_refreshing = false
var map_batch_selected_ids: Dictionary = {}
var map_batch_selection_label: Label
var map_delete_button: Button
var map_update_button: Button
var map_load_button: Button
var map_delete_dialog: ConfirmationDialog
var pending_delete_map_ids: Array[String] = []
var suppress_ui_callbacks = false
var workspace_pages: Dictionary = {}
var workspace_buttons: Dictionary = {}
var workspace_page_id = "plots"
var plots_page: VBoxContainer
var spectator_camera: Camera3D
var camera_yaw = deg_to_rad(41.0)
var camera_pitch = deg_to_rad(25.0)
var camera_distance = 25.5
var camera_orbit_dragging = false
var camera_focus_mode = 0
var camera_focus_position = CAMERA_FOCUS
var camera_auto_orbit = false
var camera_auto_orbit_speed_degrees = CAMERA_AUTO_ORBIT_DEFAULT_SPEED_DEGREES
var camera_focus_picker: OptionButton
var camera_auto_orbit_checkbox: CheckBox
var camera_auto_orbit_speed_input: SpinBox
var camera_reverse_orbit_button: Button
var attached_camera_instance_id = -1
var attached_camera_node: Camera3D
var attached_camera_rng = RandomNumberGenerator.new()
var simulation_speed = 1.0
var original_time_scale = 1.0
var original_physics_ticks_per_second = 60
var original_max_physics_steps_per_frame = 8
var branch_dialog: ConfirmationDialog
var branch_name_edit: LineEdit
var branch_source_label: Label
var branch_model_source_button: Button
var branch_clear_model_source_button: Button
var branch_reward_warning: Label
var branch_reward_checks: Dictionary = {}
var branch_variation_slider: HSlider
var branch_algorithm_picker: OptionButton
var branch_hidden_width_slider: HSlider
var branch_hidden_depth_slider: HSlider
var branch_worker_count_slider: HSlider
var branch_belly_grabber_checkbox: CheckBox
var branch_control_rate_slider: HSlider
var branch_exploration_slider: HSlider
var branch_start_active_checkbox: CheckBox
var branch_source_group_id = -1
var branch_source_version_id = ""
var limb_branch_dialog: ConfirmationDialog
var limb_branch_name_edit: LineEdit
var limb_branch_source_label: Label
var limb_branch_variation_slider: HSlider
var limb_branch_hidden_width_slider: HSlider
var limb_branch_hidden_depth_slider: HSlider
var limb_branch_worker_count_slider: HSlider
var limb_branch_start_active_checkbox: CheckBox
var limb_branch_source_group_id = -1


func _ready() -> void:
	_reset_training_item_editor_to_definition(TRAINING_ITEM_DEFAULT_DEFINITION)
	limb_training.host = self
	limb_training.wall_spatial_hash = wall_spatial_hash
	limb_training.entity_spatial_hash = training_entity_spatial_hash
	limb_training.evaluation_contract_provider = _evaluation_contract_for_group_id
	limb_training.item_candidate_provider = _training_item_candidate_for_limb
	limb_training.item_fallback_type_provider = _delivery_fallback_item_type_for_limb
	limb_training.delivery_destination_provider = _delivery_destination_for_limb
	limb_training.group_episode_completed.connect(_on_limb_training_metrics_changed)
	limb_training.group_update_completed.connect(_on_limb_training_metrics_changed)
	limb_training.group_episode_started.connect(_on_limb_action_episode_started)
	limb_training.worker_action_applied.connect(_on_limb_worker_action_applied)
	turret_training.host = self
	turret_training.wall_spatial_hash = wall_spatial_hash
	turret_training.entity_spatial_hash = training_entity_spatial_hash
	turret_training.evaluation_contract_provider = _evaluation_contract_for_group_id
	turret_training.group_episode_completed.connect(_on_turret_training_metrics_changed)
	turret_training.group_update_completed.connect(_on_turret_training_metrics_changed)
	turret_training.group_episode_started.connect(_on_turret_action_episode_started)
	turret_training.worker_action_applied.connect(_on_turret_worker_action_applied)
	turret_ui.configure(self, turret_training, turret_model_registry)
	original_time_scale = Engine.time_scale
	original_physics_ticks_per_second = Engine.physics_ticks_per_second
	original_max_physics_steps_per_frame = Engine.max_physics_steps_per_frame
	previous_render_tick_usec = Time.get_ticks_usec()
	telemetry_next_refresh_usec = previous_render_tick_usec
	drone_disable_sound_rng.randomize()
	_preload_drone_disable_sounds()
	_build_environment()
	_build_spectator_camera()
	_initialize_targeting()
	_build_target()
	_build_drone_spawn_marker()
	_build_interface()
	get_viewport().size_changed.connect(_layout_interface)
	_layout_interface()
	call_deferred("_initialize_top_level_panel_widths")
	var initial_version: Dictionary = model_registry.ensure_initial_version(
		DroneTrainingPolicy.DEFAULT_WEIGHTS
	)
	_refresh_model_versions(str(initial_version.get("version_id", "")))
	status_label.text = "No worker groups yet. Press + above Worker Groups to build one."


func _on_limb_training_metrics_changed(_group_id: int) -> void:
	plots_dirty = true


func _on_turret_training_metrics_changed(_group_id: int) -> void:
	plots_dirty = true


func _action_trace_source_id(worker_kind: String, group_id: int) -> String:
	return "%s:%d" % [worker_kind, group_id]


func _remove_action_trace_source(worker_kind: String, group_id: int) -> void:
	action_trace_buffer.remove_source(_action_trace_source_id(worker_kind, group_id))


func _drone_action_names(group: Dictionary = {}) -> Array[String]:
	var labels: Array[String] = []
	var body_contract_value: Variant = group.get("body_interface", {})
	var body_contract: Dictionary = (
		body_contract_value as Dictionary if body_contract_value is Dictionary else {}
	)
	var controls_value: Variant = body_contract.get("controls", [])
	if controls_value is Array:
		for descriptor_value: Variant in controls_value:
			if not (descriptor_value is Dictionary):
				continue
			var descriptor: Dictionary = descriptor_value
			var name: String = str(descriptor.get("name", "")).strip_edges()
			if name.is_empty():
				name = "Action %d" % (labels.size() + 1)
			if str(descriptor.get("kind", "")) == "propeller_throttle":
				name += " (policy cmd)"
			labels.append(name)
	if not labels.is_empty():
		return labels
	for action_index in range(QUAD_PROPELLER_COUNT):
		labels.append("P%d thrust" % action_index)
	return labels


func _drone_realized_actuator_status(drone: ServerDrone) -> String:
	if not is_instance_valid(drone):
		return ""
	var applied_power: float = 0.0
	for power_value: float in drone.last_propeller_applied_power_w:
		applied_power += maxf(power_value, 0.0)
	var realized_upward_thrust: float = 0.0
	for array_index: int in range(mini(
		drone.propeller_slots.size(),
		drone.last_propeller_realized_thrust_n.size()
	)):
		var axis: Vector3 = drone.propeller_slots[array_index].global_basis.y
		if axis.length_squared() <= 0.000001:
			continue
		realized_upward_thrust += maxf(
			drone.last_propeller_realized_thrust_n[array_index],
			0.0
		) * maxf(axis.normalized().dot(Vector3.UP), 0.0)
	return "Motors applied %.1f W · realized upward thrust %.1f N · bus spool %.0f%%" % [
		applied_power,
		realized_upward_thrust,
		clampf(drone.power_spool_ratio, 0.0, 1.0) * 100.0,
	]


func _four_limb_action_names(group: Dictionary = {}) -> Array[String]:
	var labels: Array[String] = []
	var definition = group.get("body_definition") as FourLimbBodyDefinition
	for limb_index in range(FourLimbMLAction.LIMB_COUNT):
		var limb_name = "L%d" % (limb_index + 1)
		if definition != null and limb_index < definition.limbs.size():
			var limb_definition = definition.limbs[limb_index]
			if limb_definition != null and not limb_definition.slot_name.strip_edges().is_empty():
				limb_name = limb_definition.slot_name.strip_edges()
		for actuator_index in range(FourLimbMLAction.ACTIONS_PER_LIMB):
			var actuator_name = "action %d" % (actuator_index + 1)
			if actuator_index < FourLimbMLAction.ACTION_NAMES.size():
				actuator_name = str(FourLimbMLAction.ACTION_NAMES[actuator_index])
			actuator_name = actuator_name.replace("_target", "")
			actuator_name = actuator_name.replace("_activation", "")
			actuator_name = actuator_name.replace("_", " ")
			labels.append("%s %s" % [limb_name, actuator_name])
	return labels


func _turret_action_names() -> Array[String]:
	var canonical = ["Yaw drive", "Pitch drive", "Trigger"]
	var labels: Array[String] = []
	for action_index in range(TurretMLAction.ACTION_COUNT):
		labels.append(
			str(canonical[action_index])
			if action_index < canonical.size()
			else "Action %d" % (action_index + 1)
		)
	return labels


func _on_limb_action_episode_started(group_id: int, new_episode_number: int) -> void:
	var group = limb_training.group_by_id(group_id)
	action_trace_buffer.begin_source_episode(
		_action_trace_source_id("four_limb", group_id),
		group_id,
		new_episode_number,
		_four_limb_action_names(group),
		-1.0,
		1.0
	)


func _on_limb_worker_action_applied(
	group_id: int,
	worker_episode_number: int,
	worker_index: int,
	instance_id: int,
	elapsed_seconds: float,
	commands: PackedFloat64Array
) -> void:
	var source_id = _action_trace_source_id("four_limb", group_id)
	var config: Dictionary = action_trace_buffer.source_config(source_id)
	if int(config.get("episode_number", -1)) != worker_episode_number:
		_on_limb_action_episode_started(group_id, worker_episode_number)
	action_trace_buffer.append_source_commands(
		source_id,
		instance_id,
		worker_index,
		elapsed_seconds,
		commands
	)


func _on_turret_action_episode_started(group_id: int, new_episode_number: int) -> void:
	action_trace_buffer.begin_source_episode(
		_action_trace_source_id("turret", group_id),
		group_id,
		new_episode_number,
		_turret_action_names(),
		-1.0,
		1.0
	)


func _on_turret_worker_action_applied(
	group_id: int,
	worker_episode_number: int,
	worker_index: int,
	instance_id: int,
	elapsed_seconds: float,
	commands: PackedFloat64Array
) -> void:
	var source_id = _action_trace_source_id("turret", group_id)
	var config: Dictionary = action_trace_buffer.source_config(source_id)
	if int(config.get("episode_number", -1)) != worker_episode_number:
		_on_turret_action_episode_started(group_id, worker_episode_number)
	action_trace_buffer.append_source_commands(
		source_id,
		instance_id,
		worker_index,
		elapsed_seconds,
		commands
	)


func _physics_process(delta: float) -> void:
	if wall_spatial_hash_dirty:
		_rebuild_wall_spatial_hash()
	var drone_group_active: bool = _has_active_drone_group()
	var limb_group_active: bool = false
	for group: Dictionary in limb_training.groups:
		if bool(group.get("active", false)):
			limb_group_active = true
			break
	var turret_group_active: bool = false
	for group: Dictionary in turret_training.groups:
		if bool(group.get("active", false)):
			turret_group_active = true
			break
	# A paused turret stays registered so resuming does not rebuild combat identity, but its
	# shared combat adapter is inactive. Only a running turret group can currently produce a
	# threat, so paused turrets must not keep threat sensors or spatial re-bucketing hot.
	var turret_threats_active: bool = turret_group_active
	# Drone-only and limb-only runs never query the combat entity index. Keep registered
	# entities for future turret spawning, but do not walk and re-bucket every body each
	# physics tick until a turret group can actually consume that index.
	_set_training_items_simulation_active(
		drone_group_active or limb_group_active or turret_group_active
	)
	_recover_lost_training_items(false)
	if turret_group_active:
		training_entity_spatial_hash.refresh_all()
	elif not training_items.is_empty():
		_refresh_training_item_spatial_positions(false)
	_tick_target_handlers(delta)
	_tick_candidate_evaluations(delta)
	if episode_running:
		# Individual worker-group pause is a true simulation pause. In particular, a room that
		# contains only paused drone groups must not keep advancing their shared episode clock in
		# the background. Evaluation drones and any still-running drone group keep the clock alive.
		if _has_runtime_active_drone_trials():
			episode_elapsed += delta
			_update_trials(delta, turret_threats_active)
			if _episode_completion_reached():
				_end_episode()
	elif intermission_remaining > 0.0:
		# Match the limb coordinator's respawn-delay pause semantics: an all-paused drone
		# population freezes its intermission countdown too. Standalone evaluator drones are
		# not controlled by worker-group pause and therefore keep the shared cycle moving.
		if drone_group_active or not _evaluation_trials().is_empty():
			intermission_remaining = maxf(intermission_remaining - delta, 0.0)
			if intermission_remaining <= 0.0 and auto_restart_episodes:
				_start_episode("Next controlled episode started.")
	var resolved_targets_by_group: Dictionary = _resolved_targets_by_group()
	limb_training.tick(
		delta,
		drone_spawn_position,
		_target_objective_position(),
		_target_velocity_for_group_id(-1),
		_target_radius_for_group_id(-1),
		episode_duration,
		ARENA_SIZE,
		resolved_targets_by_group
	)
	# Physics bodies have not integrated their applied forces yet, so a second full spatial
	# hash refresh in the same physics callback only repeated work with identical positions.
	turret_training.tick(
		delta,
		_target_objective_position(),
		episode_duration,
		ARENA_SIZE,
		resolved_targets_by_group
	)



func _process(_delta: float) -> void:
	# Only non-blocking completion checks run here. Backpropagation, Adam, GAE, shuffling,
	# and feature audits live on private low-priority threads and cannot stall UI drawing.
	var now_usec = Time.get_ticks_usec()
	var real_delta = maxf(
		float(now_usec - previous_render_tick_usec) / 1000000.0,
		0.0
	)
	previous_render_tick_usec = now_usec
	_record_frame_time(real_delta)
	_update_group_activity_animation(real_delta)
	_update_camera_tracking(real_delta)
	# A drag can end over a Control, in which case that release never reaches
	# _unhandled_input(). Commit it here as soon as the physical button is up.
	if wall_drag_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_wall_drag(true)
	_poll_optimizer_jobs()
	if now_usec >= telemetry_next_refresh_usec:
		telemetry_next_refresh_usec = now_usec + int(
			TELEMETRY_REFRESH_SECONDS * 1000000.0
		)
		# Candidate discovery/queue maintenance is UI-scale state, not physics-scale state.
		# Keeping it at telemetry cadence avoids scanning and allocating queue entries hundreds
		# of times per second when accelerated simulation is enabled. Active jobs still tick in physics.
		_sync_candidate_evaluation_jobs()
		_refresh_interface()


func _exit_tree() -> void:
	# Persist an exact candidate even if the user leaves before the normal episode-boundary
	# flush. This writes only already-frozen behavior-policy state; active rollout fragments
	# are still discarded below and never mislabeled as a best checkpoint.
	_flush_pending_auto_saves(true)
	_restore_engine_timing()
	if camera_orbit_dragging:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		camera_orbit_dragging = false
	# Godot requires every started Thread to be joined before its owner is freed. Waiting is
	# restricted to scene shutdown; normal pause/remove paths remain non-blocking.
	for group in worker_groups:
		(group["trainer"] as DroneTrainingAlgorithm).shutdown_background_update()
	for trainer in retired_trainers:
		trainer.shutdown_background_update()
	retired_trainers.clear()
	_cancel_all_candidate_evaluations()
	limb_training.shutdown()
	turret_training.shutdown()


func _preload_drone_disable_sounds() -> void:
	drone_disable_sounds.clear()
	var directory = DirAccess.open(DRONE_DISABLE_SOUND_DIRECTORY)
	if directory == null:
		return
	var file_names: Array[String] = []
	directory.list_dir_begin()
	while true:
		var file_name = directory.get_next()
		if file_name.is_empty():
			break
		if directory.current_is_dir():
			continue
		if file_name.get_extension().to_lower() == "mp3":
			file_names.append(file_name)
	directory.list_dir_end()
	file_names.sort()
	for file_name in file_names:
		var resource_path = DRONE_DISABLE_SOUND_DIRECTORY.path_join(file_name)
		var stream = load(resource_path) as AudioStream
		if stream != null:
			drone_disable_sounds.append(stream)
	if drone_disable_sounds.is_empty():
		return
	for _player_index in range(DRONE_DISABLE_SOUND_PLAYER_COUNT):
		var player = AudioStreamPlayer3D.new()
		player.name = "TrainingDisableSound%02d" % drone_disable_sound_players.size()
		player.volume_db = drone_disable_sound_volume_db
		player.unit_size = 8.0
		player.max_distance = DRONE_DISABLE_SOUND_MAX_DISTANCE_M
		add_child(player)
		drone_disable_sound_players.append(player)


func _play_drone_disable_sound(drone: ServerDrone) -> void:
	if (
		not is_instance_valid(drone)
		or drone_disable_sounds.is_empty()
		or drone_disable_sound_players.is_empty()
	):
		return
	var player_index = -1
	for offset in range(drone_disable_sound_players.size()):
		var candidate_index = (drone_disable_sound_player_cursor + offset) % drone_disable_sound_players.size()
		if not drone_disable_sound_players[candidate_index].playing:
			player_index = candidate_index
			break
	if player_index < 0:
		# Cap simultaneous effects so a mass crash cannot stack dozens of samples and
		# produce an unexpectedly loud burst. Reuse the oldest round-robin voice.
		player_index = drone_disable_sound_player_cursor
	var player = drone_disable_sound_players[player_index]
	drone_disable_sound_player_cursor = (player_index + 1) % drone_disable_sound_players.size()
	player.stop()
	player.global_position = drone.global_position
	player.stream = drone_disable_sounds[drone_disable_sound_rng.randi_range(
		0,
		drone_disable_sounds.size() - 1
	)]
	player.pitch_scale = drone_disable_sound_rng.randf_range(0.96, 1.04)
	player.play()


func _update_group_activity_animation(delta: float) -> void:
	group_activity_animation_elapsed += maxf(delta, 0.0)
	if group_activity_animation_elapsed < GROUP_ACTIVITY_ANIMATION_INTERVAL_SECONDS:
		return
	group_activity_animation_elapsed = fmod(
		group_activity_animation_elapsed,
		GROUP_ACTIVITY_ANIMATION_INTERVAL_SECONDS
	)
	group_activity_animation_frame = (group_activity_animation_frame + 1) % 4
	for group in worker_groups:
		var activity_label = group.get("activity_label") as Label
		if activity_label == null:
			continue
		activity_label.visible = bool(group.get("active", false))
		activity_label.text = str(GROUP_ACTIVITY_FRAMES[group_activity_animation_frame])
	for group: Dictionary in limb_training.groups:
		var activity_label = group.get("activity_label") as Label
		if activity_label == null:
			continue
		activity_label.visible = bool(group.get("active", false))
		activity_label.text = str(GROUP_ACTIVITY_FRAMES[group_activity_animation_frame])
	for group: Dictionary in turret_training.groups:
		var activity_label = group.get("activity_label") as Label
		if activity_label == null:
			continue
		activity_label.visible = bool(group.get("active", false))
		activity_label.text = str(GROUP_ACTIVITY_FRAMES[group_activity_animation_frame])


func _record_frame_time(delta: float) -> void:
	var frame_ms = maxf(delta, 0.0) * 1000.0
	frame_monitor_elapsed += maxf(delta, 0.0)
	frame_monitor_worst_ms = maxf(frame_monitor_worst_ms, frame_ms)
	if frame_ms >= FRAME_HITCH_THRESHOLD_MS:
		frame_monitor_hitches += 1
	if frame_monitor_elapsed >= 1.0:
		recent_worst_frame_ms = frame_monitor_worst_ms
		recent_frame_hitches = frame_monitor_hitches
		frame_monitor_elapsed = fmod(frame_monitor_elapsed, 1.0)
		frame_monitor_worst_ms = 0.0
		frame_monitor_hitches = 0


func _unhandled_input(event: InputEvent) -> void:
	if turret_ui.handle_unhandled_input(event):
		get_viewport().set_input_as_handled()
		return
	var key_event = event as InputEventKey
	if (
		key_event != null
		and key_event.pressed
		and not key_event.echo
		and key_event.keycode == KEY_F2
		and _begin_selected_group_rename()
	):
		get_viewport().set_input_as_handled()
		return
	if (
		key_event != null
		and key_event.pressed
		and key_event.keycode == KEY_ESCAPE
	):
		if action_trace_fullscreen:
			_set_action_trace_fullscreen(false)
			get_viewport().set_input_as_handled()
			return
		if delivery_destination_placement_active:
			_cancel_delivery_destination_placement("Delivery destination placement cancelled.", false)
			get_viewport().set_input_as_handled()
			return
		if training_item_placement_active:
			_cancel_training_item_placement("Training item placement finished.", true)
			get_viewport().set_input_as_handled()
			return
		if turret_placement_active:
			_cancel_turret_placement("Turret placement cancelled.")
			get_viewport().set_input_as_handled()
			return
		if wall_placement_active:
			_cancel_wall_placement("Obstacle placement cancelled.")
			get_viewport().set_input_as_handled()
			return
		if wall_drag_active:
			_finish_wall_drag(false)
			get_viewport().set_input_as_handled()
			return
		if camera_orbit_dragging:
			camera_orbit_dragging = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
	var mouse_event = event as InputEventMouseButton
	if mouse_event != null:
		if (
			delivery_destination_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_delivery_destination_placement("Delivery destination placement cancelled.", false)
			get_viewport().set_input_as_handled()
			return
		if (
			delivery_destination_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			if _update_delivery_destination_position_from_screen(mouse_event.position):
				_confirm_delivery_destination_placement()
			else:
				status_label.text = "Aim at the floor or an upward-facing obstacle surface to place the delivery destination."
			get_viewport().set_input_as_handled()
			return
		if (
			training_item_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_training_item_placement("Training item placement finished.", true)
			get_viewport().set_input_as_handled()
			return
		if (
			training_item_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			if _update_training_item_position_from_screen(mouse_event.position):
				_confirm_training_item_placement()
			else:
				status_label.text = "Aim at the floor or an upward-facing obstacle surface to place the training item."
			get_viewport().set_input_as_handled()
			return
		if (
			turret_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_turret_placement("Turret placement cancelled.")
			get_viewport().set_input_as_handled()
			return
		if (
			turret_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			if _update_turret_placement_from_screen(mouse_event.position):
				_confirm_turret_placement()
			else:
				status_label.text = "Aim at the floor or an upward-facing obstacle surface to place the turret."
			get_viewport().set_input_as_handled()
			return
		if (
			wall_drag_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_finish_wall_drag(false)
			get_viewport().set_input_as_handled()
			return
		if (
			wall_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		):
			_cancel_wall_placement("Obstacle placement cancelled.")
			get_viewport().set_input_as_handled()
			return
		if (
			wall_placement_active
			and mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			if _update_wall_position_from_screen(mouse_event.position):
				_confirm_wall_placement()
			else:
				status_label.text = "Aim at the arena floor to place the obstacle."
			get_viewport().set_input_as_handled()
			return
		if (
			wall_drag_active
			and not mouse_event.pressed
			and mouse_event.button_index == MOUSE_BUTTON_LEFT
		):
			_finish_wall_drag(true)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			camera_orbit_dragging = mouse_event.pressed
			Input.mouse_mode = (
				Input.MOUSE_MODE_CAPTURED
				if camera_orbit_dragging
				else Input.MOUSE_MODE_VISIBLE
			)
			get_viewport().set_input_as_handled()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = clampf(
				camera_distance / CAMERA_ZOOM_STEP,
				CAMERA_MINIMUM_DISTANCE,
				CAMERA_MAXIMUM_DISTANCE
			)
			_update_spectator_camera()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = clampf(
				camera_distance * CAMERA_ZOOM_STEP,
				CAMERA_MINIMUM_DISTANCE,
				CAMERA_MAXIMUM_DISTANCE
			)
			_update_spectator_camera()
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var picked_item: TrainingItem3D = _pick_training_item_from_screen(mouse_event.position)
			if picked_item != null:
				_select_custom_wall(null)
				_select_training_item(picked_item)
				if (
					selected_group_id >= 0
					or selected_limb_group_id >= 0
					or selected_turret_group_id >= 0
					or selected_evaluator_instance_id >= 0
				):
					_select_group(-1)
				get_viewport().set_input_as_handled()
				return
			var picked_wall = _pick_custom_wall_from_screen(mouse_event.position)
			if picked_wall != null:
				_select_training_item(null)
				_begin_wall_drag(picked_wall, mouse_event.position)
				get_viewport().set_input_as_handled()
				return
			var had_selected_wall = is_instance_valid(selected_custom_wall)
			var had_selected_item: bool = is_instance_valid(selected_training_item)
			_select_custom_wall(null)
			_select_training_item(null)
			if (
				selected_group_id >= 0
				or selected_limb_group_id >= 0
				or selected_turret_group_id >= 0
				or selected_evaluator_instance_id >= 0
			):
				_select_group(-1)
				get_viewport().set_input_as_handled()
				return
			if had_selected_wall or had_selected_item:
				get_viewport().set_input_as_handled()
				return
	var motion_event = event as InputEventMouseMotion
	if motion_event != null and delivery_destination_placement_active and not camera_orbit_dragging:
		_update_delivery_destination_position_from_screen(motion_event.position)
	if motion_event != null and training_item_placement_active and not camera_orbit_dragging:
		_update_training_item_position_from_screen(motion_event.position)
	if motion_event != null and turret_placement_active and not camera_orbit_dragging:
		_update_turret_placement_from_screen(motion_event.position)
	if motion_event != null and wall_placement_active and not camera_orbit_dragging:
		_update_wall_position_from_screen(motion_event.position)
	if motion_event != null and wall_drag_active and not camera_orbit_dragging:
		_update_wall_drag_from_screen(motion_event.position)
		get_viewport().set_input_as_handled()
		return
	if motion_event != null and camera_orbit_dragging:
		camera_yaw += motion_event.relative.x * CAMERA_ORBIT_SENSITIVITY
		camera_pitch = clampf(
			camera_pitch + motion_event.relative.y * CAMERA_ORBIT_SENSITIVITY,
			deg_to_rad(10.0),
			deg_to_rad(72.0)
		)
		_update_spectator_camera()
		get_viewport().set_input_as_handled()


func _build_environment() -> void:
	var air = AirEnvironment.new()
	air.name = "AirEnvironment"
	add_child(air)
	fixed_training_walls = DroneTrainingRoomPresentation.build_environment(
		self,
		ARENA_SIZE,
		ARENA_COLLISION_LAYER,
		TRAINING_BODY_COLLISION_MASK
	)
	custom_wall_container = Node3D.new()
	custom_wall_container.name = "CustomTrainingWalls"
	add_child(custom_wall_container)
	training_item_container = Node3D.new()
	training_item_container.name = "TrainingItems"
	add_child(training_item_container)
	delivery_destination_container = Node3D.new()
	delivery_destination_container.name = "TrainingDeliveryDestinations"
	add_child(delivery_destination_container)
	_rebuild_wall_spatial_hash()


func _mark_wall_spatial_hash_dirty() -> void:
	wall_spatial_hash_dirty = true
	candidate_evaluation_environment_revision += 1


func _rebuild_wall_spatial_hash() -> void:
	var walls: Array[Node3D] = []
	for wall in fixed_training_walls:
		if is_instance_valid(wall):
			walls.append(wall)
	_prune_invalid_custom_walls()
	for wall in custom_walls:
		if is_instance_valid(wall):
			walls.append(wall)
	wall_spatial_hash.rebuild(walls)
	wall_spatial_hash_dirty = false


func _build_spectator_camera() -> void:
	spectator_camera = DroneTrainingRoomPresentation.build_spectator_camera(self)
	_update_spectator_camera()


func _update_spectator_camera() -> void:
	if spectator_camera == null:
		return
	var horizontal_distance = cos(camera_pitch) * camera_distance
	var orbit_offset = Vector3(
		sin(camera_yaw) * horizontal_distance,
		sin(camera_pitch) * camera_distance,
		cos(camera_yaw) * horizontal_distance
	)
	spectator_camera.look_at_from_position(
		camera_focus_position + orbit_offset,
		camera_focus_position
	)


func _update_camera_tracking(real_delta: float) -> void:
	if camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE:
		_ensure_attached_camera_has_live_host()
		return
	_release_attached_camera()
	if spectator_camera == null:
		return
	spectator_camera.current = true
	if camera_auto_orbit:
		camera_yaw = fmod(
			camera_yaw + deg_to_rad(camera_auto_orbit_speed_degrees) * real_delta,
			TAU
		)
	var desired_focus = _desired_camera_focus()
	var blend = 1.0 - exp(-CAMERA_FOCUS_SMOOTHING_RATE * maxf(real_delta, 0.0))
	camera_focus_position = camera_focus_position.lerp(desired_focus, blend)
	_update_spectator_camera()


func _desired_camera_focus() -> Vector3:
	match camera_focus_mode:
		1:
			return _target_objective_position(_selected_target_group_id())
		2:
			return drone_spawn_position
		CAMERA_FOCUS_SELECTED_SUBJECT:
			return _selected_camera_subject_position(CAMERA_FOCUS)
		4:
			return _all_drone_centroid(CAMERA_FOCUS)
	return CAMERA_FOCUS


func _selected_camera_subject_position(fallback: Vector3) -> Vector3:
	var group_focus = fallback
	if selected_turret_group_id >= 0:
		group_focus = _turret_group_centroid(selected_turret_group_id, fallback)
	elif selected_limb_group_id >= 0:
		group_focus = _limb_group_centroid(selected_limb_group_id, fallback)
	else:
		group_focus = _drone_group_centroid(selected_group_id, fallback)
	if selected_evaluator_instance_id >= 0:
		var evaluator = _trial_by_instance_id(selected_evaluator_instance_id)
		var evaluator_drone = evaluator.get("drone") as ServerDrone
		var evaluator_weight = _trial_camera_focus_weight(evaluator)
		if is_instance_valid(evaluator_drone) and evaluator_weight > 0.0:
			return group_focus.lerp(evaluator_drone.global_position, evaluator_weight)
	return group_focus


func _trial_by_instance_id(instance_id: int) -> Dictionary:
	for trial in trials:
		if int(trial.get("instance_id", -1)) == instance_id:
			return trial
	return {}


func _drone_group_centroid(group_id: int, fallback: Vector3) -> Vector3:
	if group_id < 0:
		return fallback
	var total = Vector3.ZERO
	var total_weight = 0.0
	for trial in trials:
		if int(trial.get("group_id", -1)) != group_id:
			continue
		var drone = trial.get("drone") as ServerDrone
		var weight = _trial_camera_focus_weight(trial)
		if is_instance_valid(drone) and weight > 0.0:
			total += drone.global_position * weight
			total_weight += weight
	return total / total_weight if total_weight > 0.0 else fallback


func _all_drone_centroid(fallback: Vector3) -> Vector3:
	var total = Vector3.ZERO
	var total_weight = 0.0
	for trial in trials:
		var drone = trial.get("drone") as ServerDrone
		var weight = _trial_camera_focus_weight(trial)
		if is_instance_valid(drone) and weight > 0.0:
			total += drone.global_position * weight
			total_weight += weight
	for group: Dictionary in limb_training.groups:
		for worker_value: Variant in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker = worker_value as Dictionary
			var body = worker.get("body") as FourLimbPhysicalBody3D
			if _limb_worker_is_camera_focus_candidate(worker, body):
				var limb_position = body.core_transform().origin
				if not limb_position.is_finite():
					continue
				total += limb_position
				total_weight += 1.0
	for group: Dictionary in turret_training.groups:
		for worker_value: Variant in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker = worker_value as Dictionary
			var turret = worker.get("turret") as TurretPhysicalBody3D
			if _turret_worker_is_camera_focus_candidate(worker, turret):
				var turret_position = turret.camera_anchor_transform().origin
				if not turret_position.is_finite():
					continue
				total += turret_position
				total_weight += 1.0
	return total / total_weight if total_weight > 0.0 else fallback


func _limb_group_centroid(group_id: int, fallback: Vector3) -> Vector3:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty():
		return fallback
	var total = Vector3.ZERO
	var count = 0
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker = worker_value as Dictionary
		var body = worker.get("body") as FourLimbPhysicalBody3D
		if _limb_worker_is_camera_focus_candidate(worker, body):
			var limb_position = body.core_transform().origin
			if not limb_position.is_finite():
				continue
			total += limb_position
			count += 1
	return total / float(count) if count > 0 else fallback


static func _limb_worker_is_camera_focus_candidate(
	worker: Dictionary,
	body: FourLimbPhysicalBody3D
) -> bool:
	return (
		not bool(worker.get("finished", false))
		and is_instance_valid(body)
		and body.alive
		and body.has_finite_physics_state()
	)


func _turret_group_centroid(group_id: int, fallback: Vector3) -> Vector3:
	var group = turret_training.group_by_id(group_id)
	if group.is_empty():
		return fallback
	var total = Vector3.ZERO
	var count = 0
	for worker_value: Variant in group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		var worker = worker_value as Dictionary
		var turret = worker.get("turret") as TurretPhysicalBody3D
		if not _turret_worker_is_camera_focus_candidate(worker, turret):
			continue
		var position = turret.camera_anchor_transform().origin
		if not position.is_finite():
			continue
		total += position
		count += 1
	return total / float(count) if count > 0 else fallback


static func _turret_worker_is_camera_focus_candidate(
	worker: Dictionary,
	turret: TurretPhysicalBody3D
) -> bool:
	return (
		not bool(worker.get("finished", false))
		and is_instance_valid(turret)
		and turret.is_body_alive()
		and turret.global_position.is_finite()
	)


func _trial_camera_focus_weight(trial: Dictionary) -> float:
	if trial.is_empty():
		return 0.0
	if not bool(trial.get("episode_finished", false)):
		return 1.0
	var retired_at_usec = int(trial.get("camera_focus_retired_at_usec", -1))
	if retired_at_usec < 0:
		return 0.0
	var elapsed_seconds = (
		float(Time.get_ticks_usec() - retired_at_usec) / 1000000.0
	)
	return clampf(
		1.0 - elapsed_seconds / CAMERA_FINISHED_DRONE_FADE_SECONDS,
		0.0,
		1.0
	)


func _center_camera_now() -> void:
	if camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE:
		_select_attached_camera_host(true)
		return
	camera_focus_position = _desired_camera_focus()
	_update_spectator_camera()


func _set_camera_focus_mode(index: int) -> void:
	camera_focus_mode = clampi(index, 0, CAMERA_FOCUS_MODES.size() - 1)
	if camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE:
		_select_attached_camera_host(true)
	else:
		_release_attached_camera()
		_center_camera_now()


func _set_camera_auto_orbit(enabled: bool) -> void:
	camera_auto_orbit = enabled
	_refresh_camera_orbit_controls()


func _set_camera_auto_orbit_speed(value: float) -> void:
	camera_auto_orbit_speed_degrees = clampf(value, -45.0, 45.0)
	_refresh_camera_orbit_controls()


func _reverse_camera_auto_orbit() -> void:
	var magnitude = maxf(absf(camera_auto_orbit_speed_degrees), 0.5)
	camera_auto_orbit_speed_degrees = (
		-magnitude if camera_auto_orbit_speed_degrees >= 0.0 else magnitude
	)
	if camera_auto_orbit_speed_input != null:
		camera_auto_orbit_speed_input.set_value_no_signal(camera_auto_orbit_speed_degrees)
	_refresh_camera_orbit_controls()
	status_label.text = "Camera auto-orbit direction reversed."


func _refresh_camera_orbit_controls() -> void:
	if camera_reverse_orbit_button == null:
		return
	var reversed = camera_auto_orbit_speed_degrees < 0.0
	var visibly_active = camera_auto_orbit and reversed
	camera_reverse_orbit_button.text = (
		"REVERSE: ON" if reversed else "REVERSE: OFF"
	)
	camera_reverse_orbit_button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(visibly_active)
	)
	camera_reverse_orbit_button.add_theme_color_override(
		"font_color",
		Color("ffad42") if visibly_active else Color("a8d8c1")
	)


func _install_training_camera_part(drone: ServerDrone) -> Camera3D:
	if not is_instance_valid(drone):
		return null
	var existing: Camera3D = drone.get_camera_attachment()
	if existing != null:
		return existing
	var definition: DroneCameraAttachmentDefinition = (
		MLBodyPartContract.deep_duplicate_resource(TRAINING_CAMERA_ATTACHMENT)
		as DroneCameraAttachmentDefinition
	)
	if definition == null:
		return null
	# Training cameras are instrumentation, not authored body hardware. Installing this helper into
	# a free attachment slot mutates the runtime MLBodyInterfaceManifest after the trainer has
	# already accepted its body. That changes the interface signature (an empty attachment slot
	# becomes a camera-tagged slot), so the worker is rejected before a trial is registered. Mount
	# the observer directly on the Core instead; gameplay camera parts already present in the
	# selected loadout are still preferred above.
	return drone.mount_core_camera_part(definition)


func _attached_camera_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selected_group_id < 0:
		return result
	for trial in trials:
		if (
			int(trial.get("group_id", -1)) != selected_group_id
			or str(trial.get("mode", "")) != "algorithm_training"
			or bool(trial.get("episode_finished", false))
		):
			continue
		var drone = trial.get("drone") as ServerDrone
		if is_instance_valid(drone) and drone.activated:
			result.append(trial)
	return result


func _select_attached_camera_host(randomize_choice: bool) -> void:
	var candidates = _attached_camera_candidates()
	if candidates.is_empty():
		_release_attached_camera()
		if spectator_camera != null:
			spectator_camera.current = true
		return
	var selected_trial: Dictionary = candidates[0]
	if randomize_choice and candidates.size() > 1:
		attached_camera_rng.seed = (
			int(episode_seed)
			+ selected_group_id * 7919
			+ candidates.size() * 104729
		)
		selected_trial = candidates[attached_camera_rng.randi_range(
			0,
			candidates.size() - 1
		)]
	_activate_attached_camera_for_trial(selected_trial)


func _activate_attached_camera_for_trial(trial: Dictionary) -> void:
	var drone = trial.get("drone") as ServerDrone
	if not is_instance_valid(drone):
		return
	var camera = drone.get_camera_attachment()
	if camera == null:
		camera = _install_training_camera_part(drone)
	if camera == null:
		return
	_release_attached_camera()
	attached_camera_instance_id = int(trial.get("instance_id", -1))
	attached_camera_node = camera
	if spectator_camera != null:
		spectator_camera.current = false
	camera.current = true


func _ensure_attached_camera_has_live_host() -> void:
	var current_trial = _trial_by_instance_id(attached_camera_instance_id)
	var current_drone = current_trial.get("drone") as ServerDrone
	if (
		current_trial.is_empty()
		or bool(current_trial.get("episode_finished", true))
		or not is_instance_valid(current_drone)
		or not current_drone.activated
		or not is_instance_valid(attached_camera_node)
		or not attached_camera_node.is_inside_tree()
	):
		_select_attached_camera_host(false)
		return
	if spectator_camera != null:
		spectator_camera.current = false
	attached_camera_node.current = true


func _release_attached_camera() -> void:
	if is_instance_valid(attached_camera_node):
		attached_camera_node.current = false
	attached_camera_node = null
	attached_camera_instance_id = -1


func _initialize_targeting() -> void:
	default_target_handler = _new_target_handler("room-default")
	default_target_handler.reset(
		EPISODE_SEED_BASE,
		{"reference_position_world": drone_spawn_position}
	)


func _new_target_handler(
	handler_key: String,
	source_handler: TrainingTargetHandler = null
) -> TrainingTargetHandler:
	if source_handler != null:
		return source_handler.clone_configured(handler_key)
	var handler: TrainingTargetHandler = TrainingTargetHandler.new()
	handler.handler_key = handler_key
	var path_system: TrainingPathTargetSystem = TrainingPathTargetSystem.new()
	# Navigation-path height is the exact policy objective height for flying bodies.
	path_system.base_height_m = TARGET_START.y
	path_system.manual_subject_position.y = TARGET_START.y
	# Preserve the old routed random altitude range (1.5..5.5 + 2 m) without a hidden offset.
	path_system.random_height_range_m = Vector2(3.5, 7.5)
	handler.add_system(path_system)
	handler.add_system(TrainingRegisteredTargetSystem.new())
	return handler


func _ensure_group_target_handler(
	group_id: int,
	color: Color,
	source_group_id: int = -1
) -> TrainingTargetHandler:
	var existing = target_handlers_by_group_id.get(group_id) as TrainingTargetHandler
	if existing != null:
		_configure_target_geometry_for_group(group_id, existing)
		return existing
	var source_handler = target_handlers_by_group_id.get(source_group_id) as TrainingTargetHandler
	if source_handler == null:
		source_handler = default_target_handler
	var handler: TrainingTargetHandler = _new_target_handler(
		"group:%d" % group_id,
		source_handler
	)
	if (
		not limb_training.group_by_id(group_id).is_empty()
		and source_handler == default_target_handler
	):
		_configure_new_limb_target_defaults(handler)
	_configure_target_geometry_for_group(group_id, handler)
	target_handlers_by_group_id[group_id] = handler
	handler.reset(
		EPISODE_SEED_BASE + group_id * 7919,
		{"reference_position_world": drone_spawn_position}
	)
	_create_group_target_visual(group_id, color, handler)
	return handler


func _configure_new_limb_target_defaults(handler: TrainingTargetHandler) -> void:
	if handler == null:
		return
	var path_system: TrainingPathTargetSystem = handler.path_system()
	if path_system == null:
		return
	# Drone navigation starts several metres above the floor. That is a bad default lesson for a
	# walking body because it creates an unsupported floating destination before the user has placed
	# any ledge to climb. Fresh limb groups therefore start with ground-surface navigation.
	path_system.base_height_m = 0.0
	path_system.manual_subject_position.y = 0.0
	path_system.random_height_range_m = Vector2.ZERO


func _configure_target_geometry_for_group(
	group_id: int,
	handler: TrainingTargetHandler
) -> void:
	if handler == null:
		return
	var path_system: TrainingPathTargetSystem = handler.path_system()
	if path_system == null:
		return
	# The shared path primitive now stores one literal world-space target height. Four-limb
	# coordinators interpret that point as a support surface and derive core height there; drones
	# and turrets consume it directly. Keep the manual Y synchronized with the authored height.
	path_system.manual_subject_position.y = path_system.base_height_m


func _clear_turret_target_references_to_group(removed_group_id: int) -> void:
	if removed_group_id < 0:
		return
	for turret_group_value: Variant in turret_training.groups:
		if not (turret_group_value is Dictionary):
			continue
		var turret_group: Dictionary = turret_group_value as Dictionary
		if int(turret_group.get("target_worker_group_id", -1)) != removed_group_id:
			continue
		var turret_group_id: int = int(turret_group.get("group_id", -1))
		if turret_group_id >= 0:
			turret_training.set_group_target_worker(turret_group_id, -1)


func _remove_group_target_handler(group_id: int) -> void:
	turret_runtime_target_ids_by_group_id.erase(group_id)
	target_handlers_by_group_id.erase(group_id)
	target_contexts_by_group_id.erase(group_id)
	resolved_targets_by_group_cache.erase(group_id)
	var visual: Dictionary = target_visuals_by_group_id.get(group_id, {})
	for key: String in ["marker", "radius_ring"]:
		var node = visual.get(key) as Node
		if is_instance_valid(node):
			node.queue_free()
	target_visuals_by_group_id.erase(group_id)
	_refresh_random_target_area_preview()


func _create_group_target_visual(
	group_id: int,
	color: Color,
	handler: TrainingTargetHandler
) -> void:
	var path_system: TrainingPathTargetSystem = handler.path_system()
	if path_system == null:
		return
	var target_nodes: Dictionary = DroneTrainingRoomPresentation.build_target(
		self,
		path_system.objective_position_world(),
		path_system.hover_radius_m,
		color
	)
	var marker = target_nodes.get("marker") as MeshInstance3D
	var radius_ring = target_nodes.get("radius_ring") as MeshInstance3D
	if is_instance_valid(marker):
		marker.name = "Group%03dTargetMarker" % group_id
	if is_instance_valid(radius_ring):
		radius_ring.name = "Group%03dTargetRadius" % group_id
	target_visuals_by_group_id[group_id] = {
		"marker": marker,
		"radius_ring": radius_ring,
		"has_state": false,
		"last_position_world": Vector3.ZERO,
		"last_radius_m": -1.0,
	}


func _build_target() -> void:
	var path_system: TrainingPathTargetSystem = default_target_handler.path_system()
	var target_nodes: Dictionary = DroneTrainingRoomPresentation.build_target(
		self,
		path_system.objective_position_world(),
		path_system.hover_radius_m,
		TARGET_MARKER_COLOR
	)
	target_marker = target_nodes["marker"]
	target_marker.name = "DefaultTargetMarker"
	target_radius_ring = target_nodes["radius_ring"]
	target_radius_ring.name = "DefaultTargetRadius"
	# The room-default handler remains the shared evaluator/template configuration, but it is
	# not a worker-group target. Keeping its marker visible unconditionally makes the migrated
	# per-group target system look as if a legacy target is still active in the arena.
	_refresh_default_target_visual_visibility()
	target_random_area_preview = MeshInstance3D.new()
	target_random_area_preview.name = "RandomWaypointAreaPreview"
	target_random_area_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var waypoint_area_material = DroneTrainingRoomPresentation.material(
		Color(TARGET_MARKER_COLOR.r, TARGET_MARKER_COLOR.g, TARGET_MARKER_COLOR.b, 0.10),
		false
	)
	waypoint_area_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	target_random_area_preview.material_override = waypoint_area_material
	target_random_area_preview.visible = false
	add_child(target_random_area_preview)
	_refresh_all_target_visuals()
	_refresh_random_target_area_preview()


func _selected_target_group_id() -> int:
	if selected_group_id >= 0:
		return selected_group_id
	if selected_limb_group_id >= 0:
		return selected_limb_group_id
	if selected_turret_group_id >= 0:
		return selected_turret_group_id
	return -1


func _target_handler_for_group_id(group_id: int) -> TrainingTargetHandler:
	if group_id < 0:
		return default_target_handler
	# A missing positive group id is an error boundary, not an alias for the evaluator target.
	# Never let an invalid task publisher silently mutate or read the room-default handler.
	return target_handlers_by_group_id.get(group_id) as TrainingTargetHandler


func _target_editor_handler() -> TrainingTargetHandler:
	return _target_handler_for_group_id(_selected_target_group_id())


func _target_path_for_group_id(group_id: int) -> TrainingPathTargetSystem:
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	return handler.path_system() if handler != null else null


func _target_editor_path() -> TrainingPathTargetSystem:
	return _target_path_for_group_id(_selected_target_group_id())


func _target_reference_position_for_group(group_id: int) -> Vector3:
	if group_id < 0:
		return drone_spawn_position
	if not _group_by_id(group_id).is_empty():
		return _drone_group_centroid(group_id, drone_spawn_position)
	if not limb_training.group_by_id(group_id).is_empty():
		return _limb_group_centroid(group_id, drone_spawn_position)
	if not turret_training.group_by_id(group_id).is_empty():
		return _turret_group_centroid(group_id, drone_spawn_position)
	return drone_spawn_position


func _target_context_for_group(group_id: int) -> Dictionary:
	var context: Dictionary
	if group_id < 0:
		context = default_target_context
	else:
		if target_contexts_by_group_id.has(group_id):
			context = target_contexts_by_group_id[group_id] as Dictionary
		else:
			context = {}
			target_contexts_by_group_id[group_id] = context
	context["group_id"] = group_id
	context["reference_position_world"] = _target_reference_position_for_group(group_id)
	context["arena_size"] = ARENA_SIZE
	return context


func _target_handler_should_tick(group_id: int) -> bool:
	if group_id < 0:
		return episode_running and _has_runtime_active_drone_trials()
	var drone_group: Dictionary = _group_by_id(group_id)
	if not drone_group.is_empty():
		return bool(drone_group.get("active", false))
	var limb_group: Dictionary = limb_training.group_by_id(group_id)
	if not limb_group.is_empty():
		return bool(limb_group.get("active", false))
	var turret_group: Dictionary = turret_training.group_by_id(group_id)
	if not turret_group.is_empty():
		return bool(turret_group.get("active", false))
	return false


func _tick_target_handlers(delta: float) -> void:
	if default_target_handler != null and _target_handler_should_tick(-1):
		default_target_handler.tick(delta, _target_context_for_group(-1))
		_refresh_target_visual_for_group(-1)
	for group_id_value: Variant in target_handlers_by_group_id:
		var group_id: int = int(group_id_value)
		var handler = target_handlers_by_group_id.get(group_id) as TrainingTargetHandler
		if handler == null:
			continue
		var is_turret_group: bool = not turret_training.group_by_id(group_id).is_empty()
		if is_turret_group:
			# Runtime combat targets are world state, not animation state. Keep them current even
			# while the turret is paused so the UI truthfully shows registered candidates and a
			# selected group snaps to the live body immediately.
			_sync_turret_group_target_registration(group_id, handler)
		if not _target_handler_should_tick(group_id):
			if is_turret_group:
				handler.resolve(_target_context_for_group(group_id))
				_push_turret_resolved_target_identity(group_id, handler)
				_refresh_target_visual_for_group(group_id)
			continue
		handler.tick(delta, _target_context_for_group(group_id))
		if is_turret_group:
			_push_turret_resolved_target_identity(group_id, handler)
		_refresh_target_visual_for_group(group_id)


func _refresh_turret_target_group_picker(selected_owner_group_id: int) -> void:
	if target_worker_group_row == null or target_worker_group_picker == null:
		return
	var turret_group: Dictionary = turret_training.group_by_id(selected_owner_group_id)
	var is_turret_selection: bool = not turret_group.is_empty()
	target_worker_group_row.visible = is_turret_selection
	if not is_turret_selection:
		return
	target_worker_group_picker.clear()
	target_worker_group_picker.add_item("Path training target")
	target_worker_group_picker.set_item_metadata(0, -1)
	var selected_target_group_id: int = int(turret_group.get("target_worker_group_id", -1))
	var selected_index: int = 0
	var options: Array[Dictionary] = _worker_group_target_options(selected_owner_group_id)
	for option: Dictionary in options:
		var option_index: int = target_worker_group_picker.item_count
		target_worker_group_picker.add_item(str(option.get("label", "Worker group")))
		var option_group_id: int = int(option.get("group_id", -1))
		target_worker_group_picker.set_item_metadata(option_index, option_group_id)
		if option_group_id == selected_target_group_id:
			selected_index = option_index
	if selected_target_group_id >= 0 and selected_index == 0:
		turret_group["target_worker_group_id"] = -1
	target_worker_group_picker.select(selected_index)


func _worker_group_target_options(excluded_group_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: Dictionary in worker_groups:
		var group_id: int = int(group.get("group_id", -1))
		if group_id >= 0 and group_id != excluded_group_id:
			result.append({
				"group_id": group_id,
				"label": "DRONE · %s" % str(group.get("name", "Group %d" % group_id)),
			})
	for group: Dictionary in limb_training.groups:
		var group_id: int = int(group.get("group_id", -1))
		if group_id >= 0 and group_id != excluded_group_id:
			result.append({
				"group_id": group_id,
				"label": "LIMB · %s" % str(group.get("name", "Group %d" % group_id)),
			})
	for group: Dictionary in turret_training.groups:
		var group_id: int = int(group.get("group_id", -1))
		if group_id >= 0 and group_id != excluded_group_id:
			result.append({
				"group_id": group_id,
				"label": "TURRET · %s" % str(group.get("name", "Group %d" % group_id)),
			})
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("label", "")) < str(b.get("label", ""))
	)
	return result


func _set_turret_target_worker_group(index: int) -> void:
	if suppress_ui_callbacks or target_worker_group_picker == null:
		return
	if index < 0 or index >= target_worker_group_picker.item_count:
		return
	var group_id: int = _selected_target_group_id()
	var turret_group: Dictionary = turret_training.group_by_id(group_id)
	if turret_group.is_empty():
		return
	var target_group_id: int = int(target_worker_group_picker.get_item_metadata(index))
	if not turret_training.set_group_target_worker(group_id, target_group_id):
		return
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler != null:
		_sync_turret_group_target_registration(group_id, handler)
		handler.resolve(_target_context_for_group(group_id))
		_push_turret_resolved_target_identity(group_id, handler)
		_refresh_target_visual_for_group(group_id)
	_refresh_runtime_target_info_label()
	status_label.text = (
		"%s now targets %s." % [str(turret_group.get("name", "Turret group")), _group_display_name(target_group_id)]
		if target_group_id >= 0
		else "%s returned to the routed training target." % str(turret_group.get("name", "Turret group"))
	)


func _group_display_name(group_id: int) -> String:
	var drone_group: Dictionary = _group_by_id(group_id)
	if not drone_group.is_empty():
		return str(drone_group.get("name", "Group %d" % group_id))
	var limb_group: Dictionary = limb_training.group_by_id(group_id)
	if not limb_group.is_empty():
		return str(limb_group.get("name", "Group %d" % group_id))
	var turret_group: Dictionary = turret_training.group_by_id(group_id)
	if not turret_group.is_empty():
		return str(turret_group.get("name", "Group %d" % group_id))
	return "Group %d" % group_id


func _sync_turret_group_target_registration(
	group_id: int,
	handler: TrainingTargetHandler
) -> void:
	if handler == null:
		return
	var turret_group: Dictionary = turret_training.group_by_id(group_id)
	if turret_group.is_empty():
		return
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	if registered == null:
		return
	var target_group_id: int = int(turret_group.get("target_worker_group_id", -1))
	if target_group_id < 0 or target_group_id == group_id or not _training_group_exists(target_group_id):
		_clear_turret_runtime_target_registrations(group_id, registered)
		if target_group_id >= 0 and not _training_group_exists(target_group_id):
			turret_group["target_worker_group_id"] = -1
		return

	var previous_ids: Array[String] = []
	var previous_value: Variant = turret_runtime_target_ids_by_group_id.get(group_id, [])
	if previous_value is Array:
		for previous_id_value: Variant in (previous_value as Array):
			previous_ids.append(str(previous_id_value))
	var current_ids: Array[String] = []
	var previously_selected_stable_id: String = str(handler.selected_candidate.get("stable_id", ""))
	var turret_reference_position: Vector3 = _target_reference_position_for_group(group_id)
	var source_turret: TurretPhysicalBody3D = null
	for worker_value: Variant in turret_group.get("workers", []):
		if not (worker_value is Dictionary):
			continue
		source_turret = (worker_value as Dictionary).get("turret") as TurretPhysicalBody3D
		if is_instance_valid(source_turret):
			turret_reference_position = source_turret.muzzle_position_world()
			break
	for adapter: TrainingCombatantAdapter in _combatant_adapters_for_group(target_group_id):
		var target_position: Vector3 = adapter.aim_point_world()
		if not target_position.is_finite():
			continue
		# A selected worker group is the task objective. Do not remove a live member merely
		# because it is temporarily outside this turret's current range or elevation arc.
		# The turret observation carries those reachability facts separately. Keeping the
		# candidate registered prevents the target marker/policy from intermittently falling
		# back to the path target and producing uncontrolled scanning/spinning.
		var stable_id: String = "turret-group:%d:selected-worker-group:%s:%d" % [
			group_id,
			String(adapter.entity_kind),
			adapter.entity_id,
		]
		current_ids.append(stable_id)
		var line_of_sight: bool = (
			TurretTrainingTargetSensor.has_wall_line_of_sight(
				wall_spatial_hash,
				turret_reference_position,
				target_position,
				adapter.collision_radius_m()
			)
			if is_instance_valid(source_turret)
			else true
		)
		var was_selected: bool = stable_id == previously_selected_stable_id
		var reachable: bool = true
		if is_instance_valid(source_turret):
			var range_m: float = maxf(source_turret.loadout.gun.maximum_range_m, 0.0)
			reachable = (
				turret_reference_position.distance_to(target_position) <= range_m
				and TurretTrainingTargetSensor.target_within_pitch_limits(
					source_turret,
					target_position,
					adapter.collision_radius_m()
				)
			)
		# Keep a reachable selected body sticky so equal-distance siblings do not make the
		# target thrash. If that body leaves the actual weapon envelope, prefer a reachable
		# sibling without deleting the old body from the task provider. This separates
		# persistent group intent from momentary weapon reach and avoids both fallback scans
		# and permanent lock-on to an impossible target.
		var selection_urgency: float = (
			6.0 if was_selected and reachable
			else 4.0 if reachable and line_of_sight
			else 2.0 if reachable
			else 1.0 if was_selected
			else 0.5 if line_of_sight
			else 0.25
		)
		registered.upsert_target(
			stable_id,
			"combat_objective",
			target_position,
			adapter.linear_velocity_world(),
			adapter.collision_radius_m(),
			0.0,
			selection_urgency,
			1.0,
			{
				"target_worker_group_id": target_group_id,
				"target_entity_id": adapter.entity_id,
				"target_entity_kind": String(adapter.entity_kind),
			}
		)
	for previous_id: String in previous_ids:
		if not current_ids.has(previous_id):
			registered.remove_target(previous_id)
	turret_runtime_target_ids_by_group_id[group_id] = current_ids


func _push_turret_resolved_target_identity(
	group_id: int,
	handler: TrainingTargetHandler
) -> void:
	var turret_group: Dictionary = turret_training.group_by_id(group_id)
	if turret_group.is_empty():
		return
	if int(turret_group.get("target_worker_group_id", -1)) < 0 or handler == null:
		turret_group["resolved_target_entity_id"] = -1
		return
	var selected: Dictionary = handler.selected_candidate
	var metadata_value: Variant = selected.get("metadata", {})
	if not (metadata_value is Dictionary):
		turret_group["resolved_target_entity_id"] = -1
		return
	var metadata: Dictionary = metadata_value as Dictionary
	var selected_group_id: int = RLTrainingMath.finite_int_or(
		metadata.get("target_worker_group_id", -1),
		-1
	)
	if selected_group_id != int(turret_group.get("target_worker_group_id", -1)):
		turret_group["resolved_target_entity_id"] = -1
		return
	turret_group["resolved_target_entity_id"] = maxi(
		RLTrainingMath.finite_int_or(metadata.get("target_entity_id", -1), -1),
		-1
	)


func _clear_turret_runtime_target_registrations(
	group_id: int,
	registered: TrainingRegisteredTargetSystem
) -> void:
	var previous_value: Variant = turret_runtime_target_ids_by_group_id.get(group_id, [])
	if registered != null and previous_value is Array:
		for previous_id_value: Variant in (previous_value as Array):
			registered.remove_target(str(previous_id_value))
	turret_runtime_target_ids_by_group_id.erase(group_id)


func _combatant_adapters_for_group(group_id: int) -> Array[TrainingCombatantAdapter]:
	var result: Array[TrainingCombatantAdapter] = []
	if group_id < 0:
		return result
	for entity_kind: StringName in [&"drone", &"four_limb", &"turret"]:
		for entity_key: StringName in training_entity_spatial_hash.readonly_keys_for_kind(entity_kind):
			var record: Dictionary = training_entity_spatial_hash.get_record(entity_key)
			var metadata_value: Variant = record.get("metadata", {})
			if not (metadata_value is Dictionary):
				continue
			var adapter = (metadata_value as Dictionary).get("adapter") as TrainingCombatantAdapter
			if adapter == null or adapter.group_id != group_id or not adapter.is_alive():
				continue
			result.append(adapter)
	result.sort_custom(func(a: TrainingCombatantAdapter, b: TrainingCombatantAdapter) -> bool:
		if String(a.entity_kind) != String(b.entity_kind):
			return String(a.entity_kind) < String(b.entity_kind)
		return a.entity_id < b.entity_id
	)
	return result


func _training_group_exists(group_id: int) -> bool:
	return (
		not _group_by_id(group_id).is_empty()
		or not limb_training.group_by_id(group_id).is_empty()
		or not turret_training.group_by_id(group_id).is_empty()
	)


func _reset_target_handler_for_group(group_id: int, seed: int) -> void:
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return
	var is_turret_group: bool = not turret_training.group_by_id(group_id).is_empty()
	if is_turret_group:
		_sync_turret_group_target_registration(group_id, handler)
	handler.reset(seed, _target_context_for_group(group_id))
	if is_turret_group:
		_push_turret_resolved_target_identity(group_id, handler)
	_refresh_target_visual_for_group(group_id)


func _resolved_target_for_group_id(group_id: int) -> Dictionary:
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return {
			"position_world": TARGET_START,
			"velocity_world": Vector3.ZERO,
			"radius_m": 0.75,
			"target_kind": "fallback",
			"metadata": {},
		}
	var path_system: TrainingPathTargetSystem = handler.path_system()
	var fallback_position: Vector3 = (
		path_system.objective_position_world()
		if path_system != null
		else TARGET_START
	)
	var fallback_radius: float = path_system.hover_radius_m if path_system != null else 0.75
	if handler.selected_candidate.is_empty():
		handler.resolve(_target_context_for_group(group_id))
	return handler.resolved_target(fallback_position, fallback_radius)


func _resolved_target_for_trial(trial: Dictionary) -> Dictionary:
	return _resolved_target_for_group_id(_target_group_id_for_trial(trial))


func _target_group_id_for_trial(trial: Dictionary) -> int:
	if str(trial.get("mode", "evaluation")) == "algorithm_training":
		return int(trial.get("group_id", -1))
	return -1


func _target_objective_position(group_id: int = -1) -> Vector3:
	return _resolved_target_for_group_id(group_id).get(
		"position_world",
		TARGET_START
	)


func _target_objective_local_position(group_id: int = -1) -> Vector3:
	return _target_objective_position(group_id)


func _target_velocity_for_group_id(group_id: int) -> Vector3:
	return _resolved_target_for_group_id(group_id).get("velocity_world", Vector3.ZERO)


func _target_radius_for_group_id(group_id: int) -> float:
	return maxf(float(_resolved_target_for_group_id(group_id).get("radius_m", 0.75)), 0.05)


func _target_handler_configuration_for_group(group_id: int) -> Dictionary:
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	return handler.configuration_dictionary() if handler != null else {}


func _active_target_kinds_for_group_id(group_id: int) -> Array[String]:
	var result: Array[String] = []
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return result
	var path_system: TrainingPathTargetSystem = handler.path_system()
	if path_system != null and path_system.enabled:
		result.append("navigation")
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	if registered != null and registered.enabled:
		for target_kind: String in registered.active_target_kinds():
			if not result.has(target_kind):
				result.append(target_kind)
	result.sort()
	return result


func _evaluation_contract_for_group_id(
	group_id: int,
	body_kind: String = ""
) -> Dictionary:
	var resolved_kind: String = body_kind
	if resolved_kind.is_empty():
		if not _group_by_id(group_id).is_empty():
			resolved_kind = "drone"
		elif not limb_training.group_by_id(group_id).is_empty():
			resolved_kind = "four_limb"
		elif not turret_training.group_by_id(group_id).is_empty():
			resolved_kind = "turret"
	if resolved_kind.is_empty():
		return {}
	var environment: Dictionary = {
		"evaluation_scenario_manifest_version": (
			4 if resolved_kind == "four_limb" else (3 if resolved_kind == "turret" else 2)
		),
		"arena_size_m": [ARENA_SIZE.x, ARENA_SIZE.y, ARENA_SIZE.z],
		"spawn_position_m": [drone_spawn_position.x, drone_spawn_position.y, drone_spawn_position.z],
		"evaluation_case_duration_seconds": RLDeterministicEvaluationSuite.DEFAULT_CASE_DURATION_SECONDS,
		"evaluation_seed_base": RLDeterministicEvaluationSuite.DEFAULT_SEED_BASE,
		"evaluation_seeds_per_scenario": RLDeterministicEvaluationSuite.SEEDS_PER_SCENARIO,
		"target_handler": _target_handler_configuration_for_group(group_id),
		"active_target_kinds": _active_target_kinds_for_group_id(group_id),
	}
	match resolved_kind:
		"drone":
			var group: Dictionary = _group_by_id(group_id)
			if group.is_empty():
				return {}
			var trainer = group.get("trainer") as DroneTrainingAlgorithm
			environment["algorithm"] = trainer.algorithm_id() if trainer != null else ""
			environment["observation_schema_version"] = DronePPOObservationEncoder.SCHEMA_VERSION
			environment["action_schema_version"] = DroneMLAction.SCHEMA_VERSION
			environment["reward_schema_version"] = DroneTrainingReward.SCHEMA_VERSION
			environment["reward_cards"] = _ensure_drone_reward_deck(group).configuration_dictionary()
			environment["episode_termination"] = _episode_termination_options_for_group(group)
			environment["unlimited_episode_battery"] = unlimited_episode_battery
			var hardware_record: Dictionary = LOADOUT_CONFIG.to_record(
				group.get("drone_loadout") as DroneLoadout
			)
			# A deterministic candidate without frozen hardware is not a deterministic candidate.
			# Fail closed here so PPO/SAC never nominate a policy whose evaluator can only discover
			# the missing body several seconds later.
			if hardware_record.is_empty():
				return {}
			environment["hardware"] = hardware_record
		"four_limb":
			var group: Dictionary = limb_training.group_by_id(group_id)
			if group.is_empty():
				return {}
			var definition: FourLimbBodyDefinition = limb_training.group_body_definition(group_id)
			if definition == null:
				return {}
			environment["algorithm"] = FourLimbPPOTrainer.ALGORITHM_ID
			environment["observation_schema_version"] = FourLimbMLObservation.SCHEMA_VERSION
			environment["action_schema_version"] = FourLimbMLAction.SCHEMA_VERSION
			environment["reward_cards"] = (group["reward_deck"] as FourLimbRewardDeck).configuration_dictionary()
			environment["hardware"] = definition.to_dictionary()
		"turret":
			var group: Dictionary = turret_training.group_by_id(group_id)
			if group.is_empty():
				return {}
			var loadout: TurretLoadout = turret_training.group_loadout(group_id)
			if loadout == null:
				return {}
			environment["algorithm"] = TurretPPOTrainer.ALGORITHM_ID
			environment["observation_schema_version"] = TurretMLObservation.SCHEMA_VERSION
			environment["action_schema_version"] = TurretMLAction.SCHEMA_VERSION
			environment["reward_cards"] = (group["reward_deck"] as TurretRewardDeck).configuration_dictionary()
			environment["hardware"] = loadout.to_dictionary()
		_:
			return {}
	var contract: Dictionary = RLEvaluationContract.create(resolved_kind, environment)
	if resolved_kind == "drone" and not contract.is_empty():
		var drone_group: Dictionary = _group_by_id(group_id)
		_cache_drone_evaluation_loadout(
			drone_group,
			contract,
			drone_group.get("drone_loadout") as DroneLoadout
		)
	return contract


func _cache_drone_evaluation_loadout(
	group: Dictionary,
	contract: Dictionary,
	loadout: DroneLoadout
) -> void:
	if group.is_empty() or contract.is_empty() or loadout == null:
		return
	var contract_hash: String = str(contract.get("contract_hash", ""))
	var environment_value: Variant = contract.get("environment", {})
	if contract_hash.is_empty() or not (environment_value is Dictionary):
		return
	var hardware_value: Variant = (environment_value as Dictionary).get("hardware", {})
	if not (hardware_value is Dictionary):
		return
	var hardware_record: Dictionary = hardware_value as Dictionary
	if not LOADOUT_CONFIG.records_match(hardware_record, LOADOUT_CONFIG.to_record(loadout)):
		return
	var cache_value: Variant = group.get("candidate_drone_loadout_cache", {})
	var cache: Dictionary = cache_value as Dictionary if cache_value is Dictionary else {}
	cache[contract_hash] = LOADOUT_CONFIG.duplicate_loadout(loadout)
	# Keep a handful of recent frozen bodies so a pending evaluator remains independent from pause-
	# time edits without letting long sessions retain an unbounded number of Resource trees.
	var pending_hash: String = str(_pending_candidate_for_group(group).get(
		"evaluation_contract_hash",
		""
	))
	# A background optimizer can finish *after* the user pauses the group. Until it nominates its
	# candidate there is no pending-candidate hash yet, but the trainer's current evaluation
	# contract is already the exact contract that candidate will inherit. Protect that cache entry
	# too, so repeated pause-time hardware edits/saves cannot evict the body out from under a
	# still-running update.
	var trainer_contract_hash: String = ""
	var trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
	if trainer != null:
		var trainer_contract: Dictionary = trainer.evaluation_contract()
		trainer_contract_hash = str(trainer_contract.get("contract_hash", ""))
	while cache.size() > 6:
		var removable_key: Variant = null
		for candidate_key: Variant in cache.keys():
			var key_text: String = str(candidate_key)
			if (
				key_text != contract_hash
				and key_text != pending_hash
				and key_text != trainer_contract_hash
			):
				removable_key = candidate_key
				break
		if removable_key == null:
			break
		cache.erase(removable_key)
	group["candidate_drone_loadout_cache"] = cache


func _candidate_drone_loadout(
	group: Dictionary,
	candidate: Dictionary
) -> DroneLoadout:
	if group.is_empty() or candidate.is_empty():
		return null
	var contract_value: Variant = candidate.get("evaluation_contract", {})
	if not (contract_value is Dictionary):
		return null
	var contract: Dictionary = contract_value as Dictionary
	var contract_hash: String = str(candidate.get(
		"evaluation_contract_hash",
		contract.get("contract_hash", "")
	))
	var environment_value: Variant = contract.get("environment", {})
	if contract_hash.is_empty() or not (environment_value is Dictionary):
		return null
	var hardware_value: Variant = (environment_value as Dictionary).get("hardware", {})
	if not (hardware_value is Dictionary):
		return null
	var hardware_record: Dictionary = hardware_value as Dictionary
	var cache_value: Variant = group.get("candidate_drone_loadout_cache", {})
	if cache_value is Dictionary:
		var cached: DroneLoadout = (cache_value as Dictionary).get(contract_hash) as DroneLoadout
		if cached != null and LOADOUT_CONFIG.records_match(
			hardware_record,
			LOADOUT_CONFIG.to_record(cached)
		):
			return LOADOUT_CONFIG.duplicate_loadout(cached)
	var live_loadout: DroneLoadout = group.get("drone_loadout") as DroneLoadout
	var frozen: DroneLoadout = LOADOUT_CONFIG.frozen_loadout(hardware_record, live_loadout)
	if frozen != null:
		_cache_drone_evaluation_loadout(group, contract, frozen)
	return frozen


func register_group_target_candidate(
	group_id: int,
	stable_id: String,
	target_kind: String,
	position_world: Vector3,
	velocity_world: Vector3 = Vector3.ZERO,
	radius_m: float = 0.75,
	priority_bias: float = 0.0,
	urgency: float = 0.0,
	distance_weight: float = 1.0,
	metadata: Dictionary = {}
) -> bool:
	# Runtime bridge for task systems. Cargo bays, pickup items, swarm coordinators, explicit
	# escape planners, and future target providers can publish candidates here without ever
	# changing the policy's observation shape. group_id < 0 publishes to evaluator/default.
	if group_id >= 0 and not target_handlers_by_group_id.has(group_id):
		return false
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return false
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	if registered == null:
		return false
	registered.upsert_target(
		stable_id,
		target_kind,
		position_world,
		velocity_world,
		radius_m,
		priority_bias,
		urgency,
		distance_weight,
		metadata
	)
	handler.resolve(_target_context_for_group(group_id))
	_refresh_target_visual_for_group(group_id)
	return true


func remove_group_target_candidate(group_id: int, stable_id: String) -> bool:
	if group_id >= 0 and not target_handlers_by_group_id.has(group_id):
		return false
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return false
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	if registered == null:
		return false
	registered.remove_target(stable_id)
	handler.resolve(_target_context_for_group(group_id))
	_refresh_target_visual_for_group(group_id)
	return true


func clear_group_target_candidates(group_id: int) -> void:
	if group_id >= 0 and not target_handlers_by_group_id.has(group_id):
		return
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	if registered == null:
		return
	registered.clear_targets()
	handler.resolve(_target_context_for_group(group_id))
	_refresh_target_visual_for_group(group_id)


func _resolved_targets_by_group() -> Dictionary:
	_ensure_runtime_group_target_handlers()
	resolved_targets_by_group_cache.clear()
	for group_id_value: Variant in target_handlers_by_group_id:
		var group_id: int = int(group_id_value)
		resolved_targets_by_group_cache[group_id] = _resolved_target_for_group_id(group_id)
	return resolved_targets_by_group_cache


func _ensure_runtime_group_target_handlers() -> void:
	# Group creation currently installs handlers eagerly. Keep this dispatch boundary defensive
	# as well: a future loader/body type must never fall through to the room-default objective
	# just because one creation path forgot to initialize its target handler.
	for group: Dictionary in worker_groups:
		_ensure_runtime_group_target_handler(group)
	for group: Dictionary in limb_training.groups:
		_ensure_runtime_group_target_handler(group)
	for group: Dictionary in turret_training.groups:
		_ensure_runtime_group_target_handler(group)


func _ensure_runtime_group_target_handler(group: Dictionary) -> void:
	var group_id: int = int(group.get("group_id", -1))
	if group_id < 0 or target_handlers_by_group_id.has(group_id):
		return
	var color: Color = group.get("color", TARGET_MARKER_COLOR)
	var source_group_id: int = int(group.get("parent_group_id", -1))
	_ensure_group_target_handler(group_id, color, source_group_id)


func _load_target_handler_configuration_for_group(
	group_id: int,
	configuration: Dictionary
) -> void:
	if configuration.is_empty():
		return
	if group_id >= 0 and not target_handlers_by_group_id.has(group_id):
		return
	var handler: TrainingTargetHandler = _target_handler_for_group_id(group_id)
	if handler == null:
		return
	handler.load_configuration(configuration)
	_configure_target_geometry_for_group(group_id, handler)
	var is_turret_group: bool = not turret_training.group_by_id(group_id).is_empty()
	if is_turret_group:
		_sync_turret_group_target_registration(group_id, handler)
	handler.reset(
		EPISODE_SEED_BASE + maxi(group_id, 0) * 7919 + episode_number,
		_target_context_for_group(group_id)
	)
	if is_turret_group:
		_push_turret_resolved_target_identity(group_id, handler)
	_refresh_target_visual_for_group(group_id)
	if group_id == _selected_target_group_id():
		_refresh_target_controls_for_selection()


func _refresh_target_visual_for_group(group_id: int) -> void:
	var resolved: Dictionary = _resolved_target_for_group_id(group_id)
	var position_world: Vector3 = resolved.get(
		"position_world",
		TARGET_START
	)
	var radius_m: float = maxf(float(resolved.get("radius_m", 0.75)), 0.05)
	if group_id < 0:
		_refresh_default_target_visual_visibility()
		var position_changed: bool = (
			not default_target_visual_has_state
			or not default_target_visual_position.is_equal_approx(position_world)
		)
		var radius_changed: bool = (
			not default_target_visual_has_state
			or not is_equal_approx(default_target_visual_radius_m, radius_m)
		)
		if position_changed:
			if is_instance_valid(target_marker):
				target_marker.position = position_world
			if is_instance_valid(target_radius_ring):
				target_radius_ring.position = position_world
		if radius_changed and is_instance_valid(target_radius_ring):
			DroneTrainingRoomPresentation.update_target_ring(target_radius_ring, radius_m)
		default_target_visual_has_state = true
		default_target_visual_position = position_world
		default_target_visual_radius_m = radius_m
		return
	var visual_value: Variant = target_visuals_by_group_id.get(group_id)
	if not (visual_value is Dictionary):
		return
	var visual: Dictionary = visual_value
	var has_state: bool = bool(visual.get("has_state", false))
	var last_position: Vector3 = visual.get("last_position_world", Vector3.ZERO)
	var last_radius_m: float = float(visual.get("last_radius_m", -1.0))
	var position_changed: bool = not has_state or not last_position.is_equal_approx(position_world)
	var radius_changed: bool = not has_state or not is_equal_approx(last_radius_m, radius_m)
	var marker = visual.get("marker") as MeshInstance3D
	var radius_ring = visual.get("radius_ring") as MeshInstance3D
	if position_changed:
		if is_instance_valid(marker):
			marker.position = position_world
		if is_instance_valid(radius_ring):
			radius_ring.position = position_world
	if radius_changed and is_instance_valid(radius_ring):
		DroneTrainingRoomPresentation.update_target_ring(radius_ring, radius_m)
	visual["has_state"] = true
	visual["last_position_world"] = position_world
	visual["last_radius_m"] = radius_m
	target_visuals_by_group_id[group_id] = visual


func _refresh_default_target_visual_visibility() -> void:
	var should_show: bool = false
	for trial: Dictionary in trials:
		if str(trial.get("mode", "")) == "evaluation":
			should_show = true
			break
	if is_instance_valid(target_marker):
		target_marker.visible = should_show
	if is_instance_valid(target_radius_ring):
		target_radius_ring.visible = should_show


func _refresh_all_target_visuals() -> void:
	_refresh_target_visual_for_group(-1)
	for group_id_value: Variant in target_handlers_by_group_id:
		_refresh_target_visual_for_group(int(group_id_value))


func _build_drone_spawn_marker() -> void:
	drone_spawn_marker = DroneTrainingRoomPresentation.build_position_marker(
		self,
		"DroneEpisodeSpawnMarker",
		drone_spawn_position,
		DRONE_SPAWN_MARKER_COLOR,
		0.23
	)


func _build_interface() -> void:
	var layer = CanvasLayer.new()
	add_child(layer)
	_build_left_panel(layer)
	_build_right_panel(layer)
	_build_action_trace_fullscreen_overlay(layer)
	_build_top_level_resize_handles(layer)
	_build_model_browser()
	_build_limb_model_browser()
	turret_ui.build_model_browser()
	_build_map_browser()
	_build_branch_dialog()
	_build_limb_branch_dialog()
	_build_model_body_creator()
	var camera_hint = Label.new()
	camera_hint.anchor_left = 0.5
	camera_hint.anchor_right = 0.5
	camera_hint.anchor_top = 1.0
	camera_hint.anchor_bottom = 1.0
	camera_hint.offset_left = -122.0
	camera_hint.offset_top = -36.0
	camera_hint.offset_right = 122.0
	camera_hint.offset_bottom = -12.0
	camera_hint.text = "Middle-drag: orbit  ·  Wheel: zoom"
	camera_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_hint.add_theme_color_override("font_color", Color("5ab889"))
	camera_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(camera_hint)


func _build_action_trace_fullscreen_overlay(layer: CanvasLayer) -> void:
	action_trace_fullscreen_overlay = PanelContainer.new()
	action_trace_fullscreen_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	action_trace_fullscreen_overlay.offset_left = 10.0
	action_trace_fullscreen_overlay.offset_top = 10.0
	action_trace_fullscreen_overlay.offset_right = -10.0
	action_trace_fullscreen_overlay.offset_bottom = -10.0
	action_trace_fullscreen_overlay.visible = false
	action_trace_fullscreen_overlay.z_index = 100
	action_trace_fullscreen_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_update_action_trace_fullscreen_alpha(ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA)
	layer.add_child(action_trace_fullscreen_overlay)

	var shell = VBoxContainer.new()
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("separation", 8)
	action_trace_fullscreen_overlay.add_child(shell)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	shell.add_child(toolbar)
	var title = Label.new()
	title.text = "LIVE MODEL ACTIONS // FULLSCREEN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("8de1ff"))
	toolbar.add_child(title)
	var alpha_label = Label.new()
	alpha_label.text = "Background opacity"
	toolbar.add_child(alpha_label)
	action_trace_fullscreen_alpha_input = SpinBox.new()
	action_trace_fullscreen_alpha_input.min_value = ACTION_TRACE_FULLSCREEN_MINIMUM_ALPHA * 100.0
	action_trace_fullscreen_alpha_input.max_value = 100.0
	action_trace_fullscreen_alpha_input.step = 5.0
	DroneTrainingRoomPresentation.configure_spinbox_arrow_speed(action_trace_fullscreen_alpha_input)
	action_trace_fullscreen_alpha_input.value = ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA * 100.0
	action_trace_fullscreen_alpha_input.suffix = "%"
	action_trace_fullscreen_alpha_input.custom_minimum_size.x = 105.0
	action_trace_fullscreen_alpha_input.tooltip_text = "Fullscreen background opacity\n\nChanges only the dark background behind the inspector.\nThe text and tables stay fully opaque."
	action_trace_fullscreen_alpha_input.value_changed.connect(func(value: float) -> void:
		_update_action_trace_fullscreen_alpha(value / 100.0)
	)
	toolbar.add_child(action_trace_fullscreen_alpha_input)
	var exit_button = _button("EXIT FULLSCREEN")
	exit_button.tooltip_text = "Leave fullscreen\n\nReturns the action inspector to its normal plot-page box.\nThe current episode trace stays intact."
	exit_button.pressed.connect(func() -> void:
		_set_action_trace_fullscreen(false)
	)
	toolbar.add_child(exit_button)

	action_trace_fullscreen_host = VBoxContainer.new()
	action_trace_fullscreen_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_trace_fullscreen_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(action_trace_fullscreen_host)


func _update_action_trace_fullscreen_alpha(alpha: float) -> void:
	if action_trace_fullscreen_overlay == null:
		return
	var style = DroneTrainingRoomPresentation.scanner_panel_style(false)
	var background = style.bg_color
	background.a = clampf(alpha, ACTION_TRACE_FULLSCREEN_MINIMUM_ALPHA, 1.0)
	style.bg_color = background
	action_trace_fullscreen_overlay.add_theme_stylebox_override("panel", style)


func _set_action_trace_fullscreen(enabled: bool) -> void:
	if action_trace_card == null or action_trace_fullscreen_overlay == null:
		return
	if action_trace_fullscreen == enabled:
		return
	action_trace_fullscreen = enabled
	if enabled:
		action_trace_was_expanded = bool(action_trace_body.get_meta(
			"box_expanded",
			action_trace_body.visible
		))
		action_trace_original_parent = action_trace_card.get_parent()
		action_trace_original_index = action_trace_card.get_index()
		action_trace_original_parent.remove_child(action_trace_card)
		action_trace_fullscreen_host.add_child(action_trace_card)
		action_trace_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_trace_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		action_trace_card.custom_minimum_size = Vector2.ZERO
		var transparent_style = DroneTrainingRoomPresentation.scanner_panel_style(false)
		var transparent_background = transparent_style.bg_color
		transparent_background.a = 0.0
		transparent_style.bg_color = transparent_background
		action_trace_card.add_theme_stylebox_override("panel", transparent_style)
		action_trace_body.visible = true
		action_trace_body.set_meta("box_expanded", true)
		action_trace_header_button.text = "LIVE MODEL ACTIONS"
		action_trace_header_button.disabled = true
		action_trace_fullscreen_button.visible = false
		if action_trace_resize_handle != null:
			action_trace_resize_handle.visible = false
		action_trace_fullscreen_alpha_input.value = ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA * 100.0
		_update_action_trace_fullscreen_alpha(ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA)
		action_trace_fullscreen_overlay.visible = true
		action_trace_panel.call("set_fullscreen_mode", true)
	else:
		action_trace_fullscreen_overlay.visible = false
		action_trace_fullscreen_host.remove_child(action_trace_card)
		if action_trace_original_parent != null and is_instance_valid(action_trace_original_parent):
			action_trace_original_parent.add_child(action_trace_card)
			action_trace_original_parent.move_child(
				action_trace_card,
				clampi(action_trace_original_index, 0, action_trace_original_parent.get_child_count() - 1)
			)
		action_trace_card.size_flags_vertical = Control.SIZE_FILL
		action_trace_card.custom_minimum_size.y = 0.0
		action_trace_card.add_theme_stylebox_override(
			"panel",
			DroneTrainingRoomPresentation.scanner_panel_style(false)
		)
		action_trace_header_button.disabled = false
		action_trace_body.set_meta("box_expanded", action_trace_was_expanded)
		action_trace_body.visible = action_trace_was_expanded
		action_trace_header_button.text = (
			"▼ LIVE MODEL ACTIONS"
			if action_trace_was_expanded
			else "▶ LIVE MODEL ACTIONS"
		)
		action_trace_fullscreen_button.visible = true
		action_trace_fullscreen_button.text = "FULLSCREEN"
		if action_trace_resize_handle != null:
			action_trace_resize_handle.visible = action_trace_was_expanded
		action_trace_panel.call("set_fullscreen_mode", false)
		action_trace_fullscreen_alpha_input.value = ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA * 100.0
		_update_action_trace_fullscreen_alpha(ACTION_TRACE_FULLSCREEN_DEFAULT_ALPHA)
		action_trace_original_parent = null
		action_trace_original_index = -1
	_layout_interface()


func _set_top_level_panel_collapsed(panel_id: String, collapsed: bool) -> void:
	match panel_id:
		"workers":
			worker_panel_collapsed = collapsed
			if worker_panel_body != null:
				worker_panel_body.visible = not collapsed
			if worker_panel_title != null:
				worker_panel_title.visible = not collapsed
			if worker_panel_collapse_button != null:
				worker_panel_collapse_button.text = "▶" if collapsed else "◀"
				worker_panel_collapse_button.tooltip_text = (
					"Expand Training Control\n\nShows Simulation & Camera and Worker Groups again."
					if collapsed
					else "Collapse Training Control\n\nHides Simulation & Camera and Worker Groups.\nUse it when you need more room to watch the arena."
				)
		"setup":
			left_panel_collapsed = collapsed
			if left_panel_body != null:
				left_panel_body.visible = not collapsed
			if left_panel_title != null:
				left_panel_title.visible = not collapsed
			if left_panel_collapse_button != null:
				left_panel_collapse_button.text = "▶" if collapsed else "◀"
				left_panel_collapse_button.tooltip_text = (
					"Expand Training Setup\n\nShows spawn, target, and obstacle controls again."
					if collapsed
					else "Collapse Training Setup\n\nHides spawn, target, and obstacle controls.\nThe current setup stays active."
				)
		"selected":
			right_panel_collapsed = collapsed
			if right_panel_body != null:
				right_panel_body.visible = not collapsed
			if selected_group_title != null:
				selected_group_title.visible = not collapsed
			if right_panel_collapse_button != null:
				right_panel_collapse_button.text = "◀" if collapsed else "▶"
				right_panel_collapse_button.tooltip_text = (
					"Expand Model Details\n\nShows plots, model controls, and tuning settings again."
					if collapsed
					else "Collapse Model Details\n\nHides plots, model controls, and tuning settings.\nTraining continues normally."
				)
		_:
			return
	_layout_interface()


func _layout_interface() -> void:
	if worker_panel == null or left_panel == null or right_panel == null:
		return
	var viewport_size = get_viewport().get_visible_rect().size
	var worker_width = _top_level_panel_width(
		worker_panel_collapsed,
		worker_panel_width_override,
		viewport_size.x * 0.15,
		WORKER_PANEL_MINIMUM_WIDTH,
		WORKER_PANEL_MAXIMUM_WIDTH
	)
	var left_width = _top_level_panel_width(
		left_panel_collapsed,
		left_panel_width_override,
		viewport_size.x * 0.19,
		LEFT_PANEL_MINIMUM_WIDTH,
		LEFT_PANEL_MAXIMUM_WIDTH
	)
	var right_width = _top_level_panel_width(
		right_panel_collapsed,
		right_panel_width_override,
		viewport_size.x * RIGHT_PANEL_DEFAULT_VIEWPORT_RATIO,
		RIGHT_PANEL_MINIMUM_WIDTH,
		RIGHT_PANEL_MAXIMUM_WIDTH
	)
	var reserved_arena_width: float = minf(
		MINIMUM_ARENA_VIEW_WIDTH,
		maxf(viewport_size.x * 0.30, 120.0)
	)
	var available_panel_width: float = maxf(
		viewport_size.x
		- INTERFACE_MARGIN * 2.0
		- reserved_arena_width
		- LEFT_PANEL_GAP,
		COLLAPSED_PANEL_WIDTH * 3.0
	)
	var requested_panel_width = worker_width + left_width + right_width
	if requested_panel_width > available_panel_width:
		var fixed_collapsed_width = 0.0
		var scalable_width = 0.0
		for panel_state in [
			{"collapsed": worker_panel_collapsed, "width": worker_width},
			{"collapsed": left_panel_collapsed, "width": left_width},
			{"collapsed": right_panel_collapsed, "width": right_width},
		]:
			if bool(panel_state["collapsed"]):
				fixed_collapsed_width += float(panel_state["width"])
			else:
				scalable_width += float(panel_state["width"])
		var scalable_available = maxf(
			available_panel_width - fixed_collapsed_width,
			1.0
		)
		var width_scale = minf(
			scalable_available / maxf(scalable_width, 1.0),
			1.0
		)
		if not worker_panel_collapsed:
			worker_width *= width_scale
		if not left_panel_collapsed:
			left_width *= width_scale
		if not right_panel_collapsed:
			right_width *= width_scale
	worker_panel.offset_left = INTERFACE_MARGIN
	worker_panel.offset_top = INTERFACE_MARGIN
	worker_panel.offset_right = INTERFACE_MARGIN + worker_width
	worker_panel.offset_bottom = -INTERFACE_MARGIN
	left_panel.offset_left = INTERFACE_MARGIN + worker_width + LEFT_PANEL_GAP
	left_panel.offset_top = INTERFACE_MARGIN
	left_panel.offset_right = (
		INTERFACE_MARGIN + worker_width + LEFT_PANEL_GAP + left_width
	)
	left_panel.offset_bottom = -INTERFACE_MARGIN
	right_panel.offset_left = -right_width - INTERFACE_MARGIN
	right_panel.offset_top = INTERFACE_MARGIN
	right_panel.offset_right = -INTERFACE_MARGIN
	right_panel.offset_bottom = -INTERFACE_MARGIN
	worker_content.custom_minimum_size.x = (
		0.0 if worker_panel_collapsed else maxf(worker_width - 38.0, 180.0)
	)
	left_content.custom_minimum_size.x = (
		0.0 if left_panel_collapsed else maxf(left_width - 38.0, 240.0)
	)
	right_content.custom_minimum_size.x = (
		0.0 if right_panel_collapsed else maxf(right_width - 38.0, 0.0)
	)
	_layout_top_level_resize_handles(
		viewport_size,
		worker_width,
		left_width,
		right_width
	)
	if plot_grid != null:
		plot_grid.columns = (
			1
			if not expanded_plot_id.is_empty() or right_content.custom_minimum_size.x < 760.0
			else 2
		)
	_resize_plot_cards(viewport_size)


func _initialize_top_level_panel_widths() -> void:
	# Containers only know their real child minimums after the first layout pass. Starting the
	# two left workspaces at their authored maximums avoids the first resize drag snapping open
	# just to satisfy child minimum sizes. The common layout scaler still shrinks them when the
	# viewport cannot fit both panels plus the arena and the deliberately compact right panel.
	worker_panel_width_override = WORKER_PANEL_MAXIMUM_WIDTH
	left_panel_width_override = LEFT_PANEL_MAXIMUM_WIDTH
	_layout_interface()


func _top_level_panel_width(
	collapsed: bool,
	width_override: float,
	automatic_width: float,
	minimum_width: float,
	maximum_width: float
) -> float:
	if collapsed:
		return COLLAPSED_PANEL_WIDTH
	return clampf(
		width_override if width_override > 0.0 else automatic_width,
		minimum_width,
		maximum_width
	)


func _build_top_level_resize_handles(layer: CanvasLayer) -> void:
	worker_panel_resize_handle = _create_top_level_resize_handle(
		layer,
		"workers",
		"Drag to resize Worker Groups. Double-click to restore automatic width."
	)
	left_panel_resize_handle = _create_top_level_resize_handle(
		layer,
		"setup",
		"Drag to resize Training Setup. Double-click to restore automatic width."
	)
	right_panel_resize_handle = _create_top_level_resize_handle(
		layer,
		"selected",
		"Drag to resize the selected-group workspace. Double-click to restore automatic width."
	)


func _create_top_level_resize_handle(
	layer: CanvasLayer,
	panel_id: String,
	tooltip: String
) -> Control:
	var handle = ColorRect.new()
	var idle_color = Color(0.35, 0.82, 1.0, 0.14)
	var hover_color = Color(0.35, 0.82, 1.0, 0.52)
	handle.color = idle_color
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_entered.connect(func() -> void:
		handle.color = hover_color
	)
	handle.mouse_exited.connect(func() -> void:
		handle.color = idle_color
	)
	handle.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	handle.tooltip_text = _readable_tooltip(tooltip)
	handle.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var button = event as InputEventMouseButton
			if button.button_index == MOUSE_BUTTON_LEFT and button.double_click:
				_reset_top_level_panel_width(panel_id)
				handle.accept_event()
		elif event is InputEventMouseMotion:
			var motion = event as InputEventMouseMotion
			if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
				_resize_top_level_panel(panel_id, motion.relative.x)
				handle.accept_event()
	)
	layer.add_child(handle)
	return handle


func _resize_top_level_panel(panel_id: String, horizontal_delta: float) -> void:
	match panel_id:
		"workers":
			if worker_panel_collapsed:
				return
			var worker_current = worker_panel.size.x
			worker_panel_width_override = clampf(
				worker_current + horizontal_delta,
				WORKER_PANEL_MINIMUM_WIDTH,
				WORKER_PANEL_MAXIMUM_WIDTH
			)
		"setup":
			if left_panel_collapsed:
				return
			var setup_current = left_panel.size.x
			left_panel_width_override = clampf(
				setup_current + horizontal_delta,
				LEFT_PANEL_MINIMUM_WIDTH,
				LEFT_PANEL_MAXIMUM_WIDTH
			)
		"selected":
			if right_panel_collapsed:
				return
			var selected_current = right_panel.size.x
			right_panel_width_override = clampf(
				selected_current - horizontal_delta,
				RIGHT_PANEL_MINIMUM_WIDTH,
				RIGHT_PANEL_MAXIMUM_WIDTH
			)
		_:
			return
	_layout_interface()


func _reset_top_level_panel_width(panel_id: String) -> void:
	match panel_id:
		"workers":
			worker_panel_width_override = 0.0
		"setup":
			left_panel_width_override = 0.0
		"selected":
			right_panel_width_override = 0.0
		_:
			return
	_layout_interface()


func _layout_top_level_resize_handles(
	viewport_size: Vector2,
	worker_width: float,
	left_width: float,
	right_width: float
) -> void:
	var handle_half_width = 4.0
	var top = INTERFACE_MARGIN + 42.0
	var bottom = viewport_size.y - INTERFACE_MARGIN
	if worker_panel_resize_handle != null:
		worker_panel_resize_handle.visible = not worker_panel_collapsed
		var worker_edge = INTERFACE_MARGIN + worker_width
		worker_panel_resize_handle.position = Vector2(worker_edge - handle_half_width, top)
		worker_panel_resize_handle.size = Vector2(handle_half_width * 2.0, maxf(bottom - top, 1.0))
	if left_panel_resize_handle != null:
		left_panel_resize_handle.visible = not left_panel_collapsed
		var setup_edge = INTERFACE_MARGIN + worker_width + LEFT_PANEL_GAP + left_width
		left_panel_resize_handle.position = Vector2(setup_edge - handle_half_width, top)
		left_panel_resize_handle.size = Vector2(handle_half_width * 2.0, maxf(bottom - top, 1.0))
	if right_panel_resize_handle != null:
		right_panel_resize_handle.visible = not right_panel_collapsed
		var selected_edge = viewport_size.x - INTERFACE_MARGIN - right_width
		right_panel_resize_handle.position = Vector2(selected_edge - handle_half_width, top)
		right_panel_resize_handle.size = Vector2(handle_half_width * 2.0, maxf(bottom - top, 1.0))


func _build_left_panel(layer: CanvasLayer) -> void:
	_build_worker_panel(layer)
	_build_training_setup_panel(layer)


func _build_worker_panel(layer: CanvasLayer) -> void:
	var panel = PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	layer.add_child(panel)
	worker_panel = panel
	var panel_shell = VBoxContainer.new()
	panel_shell.add_theme_constant_override("separation", 8)
	panel.add_child(panel_shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	panel_shell.add_child(header)
	worker_panel_title = Label.new()
	worker_panel_title.text = "TRAINING CONTROL"
	worker_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worker_panel_title.clip_text = true
	worker_panel_title.add_theme_font_size_override("font_size", 23)
	worker_panel_title.add_theme_color_override("font_color", Color("8de1ff"))
	header.add_child(worker_panel_title)
	worker_panel_collapse_button = _button("◀")
	worker_panel_collapse_button.custom_minimum_size = Vector2(30.0, 30.0)
	worker_panel_collapse_button.tooltip_text = "Collapse Training Control\n\nHides Simulation & Camera and Worker Groups.\nUse it when you need more room to watch the arena."
	worker_panel_collapse_button.pressed.connect(func() -> void:
		_set_top_level_panel_collapsed("workers", not worker_panel_collapsed)
	)
	header.add_child(worker_panel_collapse_button)

	var panel_body = VSplitContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_theme_constant_override("separation", 10)
	panel_body.add_theme_constant_override("minimum_grab_thickness", 10)
	panel_shell.add_child(panel_body)
	worker_panel_body = panel_body
	worker_camera_split = panel_body

	var camera_card = PanelContainer.new()
	camera_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera_card.size_flags_stretch_ratio = 0.46
	camera_card.custom_minimum_size.y = 560.0
	camera_card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	panel_body.add_child(camera_card)
	var camera_shell = VBoxContainer.new()
	camera_shell.add_theme_constant_override("separation", 6)
	camera_card.add_child(camera_shell)
	var camera_title = Label.new()
	camera_title.text = "SIMULATION & CAMERA"
	camera_title.add_theme_font_size_override("font_size", 18)
	camera_title.add_theme_color_override("font_color", Color("8de1ff"))
	camera_title.tooltip_text = "Simulation & Camera\n\nControls simulation speed, episode rules, sound, and the spectator camera.\nDrag the divider below to give this box more or less height."
	camera_shell.add_child(camera_title)
	var camera_content = VBoxContainer.new()
	camera_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	camera_content.add_theme_constant_override("separation", 7)
	camera_shell.add_child(camera_content)
	_build_camera_controls(camera_content)
	DroneTrainingRoomPresentation.add_separator(camera_content)
	_build_episode_controls(camera_content)
	DroneTrainingRoomPresentation.add_separator(camera_content)
	var map_library_button = _button("MAP LIBRARY")
	map_library_button.tooltip_text = "Open Map Library\n\nSave the custom obstacles currently placed in this room.\nLoad, update, or permanently delete saved maps."
	map_library_button.pressed.connect(_open_map_browser)
	camera_content.add_child(map_library_button)

	var groups_card = PanelContainer.new()
	groups_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	groups_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	groups_card.size_flags_stretch_ratio = 0.54
	groups_card.custom_minimum_size.y = 220.0
	groups_card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	panel_body.add_child(groups_card)
	var groups_shell = VBoxContainer.new()
	groups_shell.add_theme_constant_override("separation", 6)
	groups_card.add_child(groups_shell)
	var groups_title = Label.new()
	groups_title.text = "WORKER GROUPS"
	groups_title.add_theme_font_size_override("font_size", 18)
	groups_title.add_theme_color_override("font_color", Color("8de1ff"))
	groups_title.tooltip_text = "Worker Groups\n\nEach card is one independently trained model.\nDrag the divider above to resize this area."
	groups_shell.add_child(groups_title)

	var group_toolbar = HBoxContainer.new()
	group_toolbar.add_theme_constant_override("separation", 6)
	groups_shell.add_child(group_toolbar)
	var create_button = _button("+", true)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.custom_minimum_size.y = 32.0
	create_button.tooltip_text = "Create a model body\n\nOpen the model-body creator, choose a body/Core and compatible serialized parts, then create a fresh worker group from that hardware."
	create_button.pressed.connect(_open_model_body_creator)
	group_toolbar.add_child(create_button)
	all_groups_pause_button = _button("Ⅱ")
	all_groups_pause_button.custom_minimum_size = Vector2(42.0, 32.0)
	all_groups_pause_button.tooltip_text = "Pause or resume all groups\n\nPausing keeps every model in memory.\nIt does not clear the current episode action traces."
	all_groups_pause_button.pressed.connect(_toggle_all_groups)
	group_toolbar.add_child(all_groups_pause_button)


	var groups_scroll = ScrollContainer.new()
	groups_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	groups_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	groups_shell.add_child(groups_scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	groups_scroll.add_child(content)
	worker_content = content
	_build_group_browser(content)



func _build_training_setup_panel(layer: CanvasLayer) -> void:
	var panel = PanelContainer.new()
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	layer.add_child(panel)
	left_panel = panel
	var panel_shell = VBoxContainer.new()
	panel_shell.add_theme_constant_override("separation", 8)
	panel.add_child(panel_shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	panel_shell.add_child(header)
	left_panel_title = Label.new()
	left_panel_title.text = "TRAINING SETUP"
	left_panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel_title.clip_text = true
	left_panel_title.add_theme_font_size_override("font_size", 23)
	left_panel_title.add_theme_color_override("font_color", Color("8de1ff"))
	header.add_child(left_panel_title)
	left_panel_collapse_button = _button("◀")
	left_panel_collapse_button.custom_minimum_size = Vector2(30.0, 30.0)
	left_panel_collapse_button.tooltip_text = "Collapse Training Setup\n\nHides spawn, target, and obstacle controls.\nThe current setup stays active."
	left_panel_collapse_button.pressed.connect(func() -> void:
		_set_top_level_panel_collapsed("setup", not left_panel_collapsed)
	)
	header.add_child(left_panel_collapse_button)
	var panel_body = VBoxContainer.new()
	panel_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_theme_constant_override("separation", 8)
	panel_shell.add_child(panel_body)
	left_panel_body = panel_body
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_body.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	left_content = content

	var spawn_body = _add_section(
		content,
		"DRONE SPAWN POSITION",
		"Choose the common start position. Four-limb groups use the same X/Z point and raise the chassis only when needed to keep their feet above the floor.",
		true
	)
	_build_drone_spawn_controls(spawn_body)
	var target_body = _add_section(
		content,
		"TARGET SETTINGS",
		"Each worker group owns an independent target handler. Select a group card to edit its target systems; with no group selected, these controls edit the room-default target used by evaluators.",
		false
	)
	_build_target_controls(target_body)
	var walls_body = _add_section(
		content,
		"TRAINING OBSTACLES",
		"Create unrestricted primitive obstacles for curriculum training. Enter exact dimensions, coordinates, and rotations, or arm mouse placement and click the arena.",
		false
	)
	_build_wall_controls(walls_body)
	var items_body = _add_section(
		content,
		"TRAINING ITEMS",
		"Author physical carryable objects for pickup and delivery lessons. Items are generic room entities: grippers can hold them now, and future take/bring task providers can address the same stable item ids.",
		false
	)
	_build_training_item_controls(items_body)
	status_label = Label.new()
	status_label.text = "Initializing worker groups..."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.tooltip_text = "Training-room status\n\nShows the last completed action.\nIf something fails, the reason appears here in plain language."
	content.add_child(status_label)
	var back_button = _button("BACK TO MAIN MENU")
	back_button.tooltip_text = "Return to the main menu\n\nSaved models stay in the Model Library.\nUnsaved live training progress is lost."
	back_button.pressed.connect(SceneController.leave_ml_training_room)
	panel_body.add_child(back_button)


func _build_right_panel(layer: CanvasLayer) -> void:
	var panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	layer.add_child(panel)
	right_panel = panel
	selected_group_panel = panel
	# Decouple the top-level PanelContainer minimum width from whichever workspace page is
	# currently visible. Without this wrapper, selecting a group after manually shrinking the
	# panel lets a newly-visible child minimum force the right-anchored panel past the viewport.
	var panel_clip = Control.new()
	panel_clip.clip_contents = true
	panel_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(panel_clip)
	var panel_shell = VBoxContainer.new()
	panel_shell.add_theme_constant_override("separation", 8)
	panel_clip.add_child(panel_shell)
	panel_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var selected_header = HBoxContainer.new()
	selected_header.add_theme_constant_override("separation", 8)
	panel_shell.add_child(selected_header)
	selected_group_title = Label.new()
	selected_group_title.text = "ALL RUNNING MODELS"
	selected_group_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_group_title.clip_text = true
	selected_group_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_group_title.add_theme_font_size_override("font_size", 23)
	selected_group_title.add_theme_color_override("font_color", Color("8de1ff"))
	selected_header.add_child(selected_group_title)
	right_panel_collapse_button = _button("▶")
	right_panel_collapse_button.custom_minimum_size = Vector2(30.0, 30.0)
	right_panel_collapse_button.tooltip_text = "Collapse Model Details\n\nHides plots, model controls, and tuning settings.\nTraining continues normally."
	right_panel_collapse_button.pressed.connect(func() -> void:
		_set_top_level_panel_collapsed("selected", not right_panel_collapsed)
	)
	selected_header.add_child(right_panel_collapse_button)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_shell.add_child(scroll)
	right_panel_body = scroll
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	right_content = content
	scroll.resized.connect(_sync_right_workspace_minimum_height)
	call_deferred("_sync_right_workspace_minimum_height")
	selected_group_status = Label.new()
	selected_group_status.tooltip_text = "Current training status\n\nShows whether the selected model is collecting experience, learning, paused, or waiting."
	content.add_child(selected_group_status)
	selected_group_auto_save_label = Label.new()
	selected_group_auto_save_label.visible = false
	selected_group_auto_save_label.add_theme_color_override(
		"font_color",
		Color("54e6b1")
	)
	selected_group_auto_save_label.tooltip_text = "Latest automatic best save\n\nAppears when this group reaches a new best result.\nAn update number is a learning step, not a model-file version."
	content.add_child(selected_group_auto_save_label)

	var navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 7)
	content.add_child(navigation)
	_add_workspace_button(navigation, "model", "MODEL")
	_add_workspace_button(navigation, "plots", "PLOTS")
	_add_workspace_button(navigation, "tuning", "TUNING")
	_add_workspace_button(navigation, "rewards", "REWARDS")

	var model_page = _add_workspace_page(content, "model")
	var live_model_body = _add_section(
		model_page,
		"CURRENT MODEL",
		"The neural-network weights actually controlling this group right now.",
		true
	)
	training_identity_label = Label.new()
	training_identity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	training_identity_label.add_theme_color_override("font_color", Color("ffad42"))
	live_model_body.add_child(training_identity_label)
	_build_selected_group_actions(live_model_body)
	var registry_body = _add_section(
		model_page,
		"SAVE OR INSPECT MODEL",
		"Save this group's current name as a checkpoint family, or inspect stored models.",
		true
	)
	_build_model_controls(registry_body)

	plots_page = _add_workspace_page(content, "plots")
	_build_plot_dashboard(plots_page)

	var rewards_page = _add_workspace_page(content, "rewards")
	_build_reward_card_workspace(rewards_page)

	var tuning_page = _add_workspace_page(content, "tuning")
	drone_loadout_body = _add_section(
		tuning_page,
		"DRONE PARTS & POWER",
		"Inspect and edit the selected worker group's physical drone. Pause the group before changing hardware; the next resume spawns every worker with the new loadout.",
		true
	)
	_build_loadout_controls(drone_loadout_body)
	limb_body_tuning_body = _add_section(
		tuning_page,
		"FOUR-LIMB BODY",
		"Physical contract used by every worker in the selected limb group. Limb checkpoints remain separate from drone checkpoints.",
		true
	)
	limb_body_tuning_label = Label.new()
	limb_body_tuning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limb_body_tuning_label.add_theme_color_override("font_color", Color("8de1ff"))
	limb_body_tuning_body.add_child(limb_body_tuning_label)
	_build_limb_body_controls(limb_body_tuning_body)
	turret_ui.build_tuning_section(tuning_page)
	var worker_body = _add_section(
		tuning_page,
		"WORKERS AND CONTROL",
		"The common settings that control simulation load and decision frequency.",
		true
	)
	_build_worker_controls(worker_body)
	var optimizer_body = _add_section(
		tuning_page,
		"LEARNING ALGORITHM",
		"Algorithm-specific learning settings. Pause the group before editing.",
		false
	)
	_build_algorithm_controls(optimizer_body)
	_set_workspace_page("plots")


func _add_workspace_button(
	parent: HBoxContainer,
	page_id: String,
	text: String
) -> void:
	var button = _button(text)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = {
		"model": "Model page\n\nInspect the live model, save it, or load a compatible checkpoint.",
		"plots": "Plots page\n\nShows training history for the selected group.\nWith no group selected, the plots compare all running groups.",
		"tuning": "Tuning page\n\nEdit workers, drone parts, control rate, and learning settings.\nPause the group before changing protected settings.",
		"rewards": "Reward cards\n\nEnable, disable, and scale the reward or punishment rules for the selected drone or four-limb group.\nChanges apply at its next episode.",
	}.get(page_id, "")
	button.pressed.connect(func() -> void:
		_set_workspace_page(page_id)
	)
	parent.add_child(button)
	workspace_buttons[page_id] = button


func _add_workspace_page(parent: VBoxContainer, page_id: String) -> VBoxContainer:
	var page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	parent.add_child(page)
	workspace_pages[page_id] = page
	return page


func _set_workspace_page(page_id: String) -> void:
	if (
		_selected_group().is_empty()
		and _selected_limb_group().is_empty()
		and _selected_turret_group().is_empty()
		and page_id != "plots"
	):
		page_id = "plots"
	if not workspace_pages.has(page_id):
		return
	workspace_page_id = page_id
	for candidate_id in workspace_pages:
		var page = workspace_pages[candidate_id] as Control
		if page != null:
			page.visible = candidate_id == page_id
			if page.visible:
				call_deferred("_animate_box_open", page)
	for candidate_id in workspace_buttons:
		var button = workspace_buttons[candidate_id] as Button
		if button == null:
			continue
		var selected = candidate_id == page_id
		button.add_theme_stylebox_override(
			"normal",
			DroneTrainingRoomPresentation.scanner_button_style(selected)
		)
		button.add_theme_color_override(
			"font_color",
			Color("ffad42") if selected else Color("a8d8c1")
		)
	# Every workspace switch can reveal a different child minimum. Reassert the authored
	# top-level geometry immediately and once after Godot's container pass; the clip/root above
	# ensures those child minimums can no longer resize the right-anchored panel itself.
	_layout_interface()
	call_deferred("_layout_interface")
	if page_id == "plots":
		plots_dirty = true
		_refresh_action_trace_panel()
		_refresh_plots()


func _build_drone_spawn_controls(content: VBoxContainer) -> void:
	drone_spawn_height_input = _add_number_input(
		content,
		"Spawn height",
		DRONE_SPAWN_MINIMUM_HEIGHT_M,
		DRONE_SPAWN_MAXIMUM_HEIGHT_M,
		0.05,
		drone_spawn_position.y,
		" m",
		"World-space height of every drone at the start of each episode. Keep enough clearance below the drone to avoid an immediate floor collision.",
		_set_drone_spawn_height
	)
	drone_spawn_pad = TARGET_PAD_SCRIPT.new() as Control
	drone_spawn_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drone_spawn_pad.call(
		"configure",
		"X / Z episode spawn pad",
		"Move the episode spawn\n\nClick or drag to choose where every drone starts.\nReleasing the mouse applies the position and restarts active trials.",
		DRONE_SPAWN_MARKER_COLOR
	)
	drone_spawn_pad.connect("target_selected", _move_drone_spawn_from_pad)
	drone_spawn_pad.connect(
		"selection_finished",
		_finish_drone_spawn_pad_selection
	)
	content.add_child(drone_spawn_pad)
	drone_spawn_position_label = Label.new()
	drone_spawn_position_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drone_spawn_position_label.tooltip_text = "Episode spawn position\n\nDrones start exactly here. Four-limb groups use the same X/Z point and only raise the chassis enough to keep its feet clear of the floor."
	content.add_child(drone_spawn_position_label)
	_update_drone_spawn_pad_marker()
	_refresh_drone_spawn_position_label()


func _set_drone_spawn_height(value: float) -> void:
	drone_spawn_position.y = clampf(
		value,
		DRONE_SPAWN_MINIMUM_HEIGHT_M,
		DRONE_SPAWN_MAXIMUM_HEIGHT_M
	)
	_refresh_drone_spawn_marker()
	_refresh_drone_spawn_position_label()
	_restart_for_configuration_change("Drone episode spawn height changed.")


func _move_drone_spawn_from_pad(normalized_position: Vector2) -> void:
	var half_width = ARENA_SIZE.x * 0.5 - DRONE_SPAWN_PAD_MARGIN_M
	var half_depth = ARENA_SIZE.z * 0.5 - DRONE_SPAWN_PAD_MARGIN_M
	drone_spawn_position.x = lerpf(
		-half_width,
		half_width,
		clampf(normalized_position.x, 0.0, 1.0)
	)
	drone_spawn_position.z = lerpf(
		-half_depth,
		half_depth,
		clampf(normalized_position.y, 0.0, 1.0)
	)
	_refresh_drone_spawn_marker()
	_refresh_drone_spawn_position_label()
	if status_label != null:
		status_label.text = "Drone spawn moved. Release left mouse to restart the episode at this position."


func _finish_drone_spawn_pad_selection(_normalized_position: Vector2) -> void:
	# Four-limb groups share this X/Z spawn anchor with drones, so the same operator edit is an
	# episode boundary for both body kinds. Turrets use explicit authored placements instead.
	_restart_for_configuration_change("Drone episode spawn position changed.", true, true, false)


func _refresh_drone_spawn_marker() -> void:
	if is_instance_valid(drone_spawn_marker):
		drone_spawn_marker.position = drone_spawn_position


func _refresh_drone_spawn_position_label() -> void:
	if drone_spawn_position_label == null:
		return
	drone_spawn_position_label.text = "Current spawn · X %s m · Y %s m · Z %s m" % [
		String.num(drone_spawn_position.x, 2),
		String.num(drone_spawn_position.y, 2),
		String.num(drone_spawn_position.z, 2),
	]


func _update_drone_spawn_pad_marker() -> void:
	if drone_spawn_pad == null:
		return
	var half_width = ARENA_SIZE.x * 0.5 - DRONE_SPAWN_PAD_MARGIN_M
	var half_depth = ARENA_SIZE.z * 0.5 - DRONE_SPAWN_PAD_MARGIN_M
	var normalized = Vector2(
		inverse_lerp(-half_width, half_width, drone_spawn_position.x),
		inverse_lerp(-half_depth, half_depth, drone_spawn_position.z)
	)
	drone_spawn_pad.call("set_marker", normalized)


func _build_camera_controls(content: VBoxContainer) -> void:
	var focus_row = HBoxContainer.new()
	focus_row.add_theme_constant_override("separation", 6)
	content.add_child(focus_row)
	var focus_label = Label.new()
	focus_label.text = "Focus"
	focus_row.add_child(focus_label)
	camera_focus_picker = OptionButton.new()
	camera_focus_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_focus_picker.tooltip_text = "Camera focus\n\nChooses what the spectator camera follows.\nYour current orbit angle and zoom are preserved."
	for mode_name in CAMERA_FOCUS_MODES:
		camera_focus_picker.add_item(mode_name)
	camera_focus_picker.select(camera_focus_mode)
	camera_focus_picker.item_selected.connect(_set_camera_focus_mode)
	focus_row.add_child(camera_focus_picker)
	var center_button = _button("CENTER")
	center_button.tooltip_text = "Center camera now\n\nImmediately moves the focus to the selected subject.\nYour orbit angle and zoom stay unchanged."
	center_button.pressed.connect(_center_camera_now)
	focus_row.add_child(center_button)

	var orbit_row = HBoxContainer.new()
	orbit_row.add_theme_constant_override("separation", 6)
	content.add_child(orbit_row)
	camera_auto_orbit_checkbox = CheckBox.new()
	camera_auto_orbit_checkbox.text = "Auto orbit"
	camera_auto_orbit_checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_auto_orbit_checkbox.button_pressed = camera_auto_orbit
	camera_auto_orbit_checkbox.tooltip_text = "Automatic camera orbit\n\nRotates around the current focus point.\nYou can still middle-drag to change the angle manually."
	camera_auto_orbit_checkbox.toggled.connect(_set_camera_auto_orbit)
	orbit_row.add_child(camera_auto_orbit_checkbox)
	camera_reverse_orbit_button = _button("REVERSE")
	camera_reverse_orbit_button.tooltip_text = "Reverse camera orbit\n\nFlips the automatic camera rotation direction.\nThe orbit speed stays the same."
	camera_reverse_orbit_button.pressed.connect(_reverse_camera_auto_orbit)
	orbit_row.add_child(camera_reverse_orbit_button)
	var speed_label = Label.new()
	speed_label.text = "Speed"
	orbit_row.add_child(speed_label)
	camera_auto_orbit_speed_input = SpinBox.new()
	camera_auto_orbit_speed_input.min_value = -45.0
	camera_auto_orbit_speed_input.max_value = 45.0
	camera_auto_orbit_speed_input.step = 0.5
	DroneTrainingRoomPresentation.configure_spinbox_arrow_speed(camera_auto_orbit_speed_input)
	camera_auto_orbit_speed_input.value = camera_auto_orbit_speed_degrees
	camera_auto_orbit_speed_input.suffix = "°/s"
	camera_auto_orbit_speed_input.custom_minimum_size.x = 100.0
	camera_auto_orbit_speed_input.tooltip_text = "Orbit speed and direction\n\nPositive values rotate one way.\nNegative values rotate the opposite way."
	camera_auto_orbit_speed_input.value_changed.connect(_set_camera_auto_orbit_speed)
	orbit_row.add_child(camera_auto_orbit_speed_input)
	_refresh_camera_orbit_controls()


func _build_target_controls(content: VBoxContainer) -> void:
	target_context_label = Label.new()
	target_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_context_label.add_theme_color_override("font_color", Color("8de1ff"))
	target_context_label.tooltip_text = "Target owner\n\nSelect a worker group to edit only that group's target handler. With no group selected, these controls edit the room-default target used by evaluators."
	content.add_child(target_context_label)

	target_worker_group_row = HBoxContainer.new()
	target_worker_group_row.add_theme_constant_override("separation", 8)
	content.add_child(target_worker_group_row)
	var worker_target_label: Label = Label.new()
	worker_target_label.text = "Target group"
	worker_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worker_target_label.tooltip_text = "Turret combat target\n\nFor turret groups, choose another live worker group as the combat objective. The registered target handler follows that group and the turret sensor filters perception to members of that group."
	target_worker_group_row.add_child(worker_target_label)
	target_worker_group_picker = OptionButton.new()
	target_worker_group_picker.custom_minimum_size.x = 180.0
	target_worker_group_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_worker_group_picker.item_selected.connect(_set_turret_target_worker_group)
	target_worker_group_row.add_child(target_worker_group_picker)

	var type_row = HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	content.add_child(type_row)
	var type_label = Label.new()
	type_label.text = "Type"
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_label.tooltip_text = "Target system type\n\nA handler may own multiple target systems at once. This dropdown chooses which system you are editing; the handler continuously considers candidates from every enabled system."
	type_row.add_child(type_label)
	target_type_picker = OptionButton.new()
	target_type_picker.custom_minimum_size.x = 180.0
	target_type_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_type_picker.tooltip_text = "Target system\n\nNavigation path is the current moving-target system. Task targets (runtime) are the generic input point for future cargo destinations, pickup items, swarm targets, escape destinations, and other task providers."
	target_type_picker.item_selected.connect(_set_target_editor_type)
	type_row.add_child(target_type_picker)

	target_behavior_row = HBoxContainer.new()
	target_behavior_row.add_theme_constant_override("separation", 8)
	content.add_child(target_behavior_row)
	var behavior_label = Label.new()
	behavior_label.text = "Behaviour"
	behavior_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	behavior_label.tooltip_text = "Target behaviour\n\nChoose how this group's navigation target moves. Only settings used by that behaviour are shown."
	target_behavior_row.add_child(behavior_label)
	target_behavior_picker = OptionButton.new()
	target_behavior_picker.custom_minimum_size.x = 180.0
	target_behavior_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for behavior_name: String in TARGET_BEHAVIORS:
		target_behavior_picker.add_item(behavior_name)
	target_behavior_picker.tooltip_text = "Navigation movement\n\nChanges the path followed by this group's navigation target. The model still receives the same single target position/velocity/radius fields."
	target_behavior_picker.item_selected.connect(_set_target_behavior)
	target_behavior_row.add_child(target_behavior_picker)

	target_behavior_settings_body = VBoxContainer.new()
	target_behavior_settings_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_behavior_settings_body.add_theme_constant_override("separation", 5)
	content.add_child(target_behavior_settings_body)
	_refresh_target_controls_for_selection()


func _refresh_target_controls_for_selection() -> void:
	if target_behavior_settings_body == null or target_type_picker == null:
		return
	var group_id: int = _selected_target_group_id()
	var handler: TrainingTargetHandler = _target_editor_handler()
	if handler == null:
		return
	if target_context_label != null:
		if group_id < 0:
			target_context_label.text = "Editing target · ROOM DEFAULT / EVALUATORS"
		else:
			var group_name: String = "Group %d" % group_id
			var group: Dictionary = _selected_any_training_group()
			if not group.is_empty():
				group_name = str(group.get("name", group_name))
			target_context_label.text = "Editing target · %s" % group_name

	_refresh_turret_target_group_picker(group_id)

	target_type_picker.clear()
	var selected_type_index: int = -1
	for target_system: TrainingTargetSystem in handler.systems:
		var index: int = target_type_picker.item_count
		target_type_picker.add_item(target_system.display_name())
		target_type_picker.set_item_metadata(index, str(target_system.type_id()))
		if str(target_system.type_id()) == target_editor_type_id:
			selected_type_index = index
	if selected_type_index < 0 and target_type_picker.item_count > 0:
		selected_type_index = 0
		target_editor_type_id = str(target_type_picker.get_item_metadata(0))
	if selected_type_index >= 0:
		target_type_picker.select(selected_type_index)
	_rebuild_target_behavior_settings()


func _set_target_editor_type(index: int) -> void:
	if target_type_picker == null or index < 0 or index >= target_type_picker.item_count:
		return
	target_editor_type_id = str(target_type_picker.get_item_metadata(index))
	_rebuild_target_behavior_settings()


func _current_target_editor_system() -> TrainingTargetSystem:
	var handler: TrainingTargetHandler = _target_editor_handler()
	if handler == null:
		return null
	return handler.system(StringName(target_editor_type_id))


func _rebuild_target_behavior_settings() -> void:
	if target_behavior_settings_body == null:
		return
	target_pad = null
	target_height_input = null
	target_position_label = null
	target_random_area_checkbox = null
	target_runtime_info_label = null
	for child in target_behavior_settings_body.get_children():
		target_behavior_settings_body.remove_child(child)
		child.queue_free()

	var editor_system: TrainingTargetSystem = _current_target_editor_system()
	var path_system = editor_system as TrainingPathTargetSystem
	if target_behavior_row != null:
		target_behavior_row.visible = path_system != null
	if path_system == null:
		_build_non_path_target_settings(editor_system)
		_refresh_random_target_area_preview()
		return

	if target_behavior_picker != null:
		target_behavior_picker.select(path_system.behavior)
	target_height_input = _add_number_input(
		target_behavior_settings_body,
		"Target height",
		-100000.0,
		100000.0,
		0.05,
		path_system.base_height_m,
		" m",
		"Exact navigation target height for drones and turrets. Four-limb workers interpret the same authored point as the destination support surface and derive their core goal from standing height.",
		_set_target_height
	)
	target_height_input.allow_lesser = true
	target_height_input.allow_greater = true
	if path_system.behavior != 0:
		_add_number_input(
			target_behavior_settings_body,
			"Path speed",
			0.0,
			100.0,
			0.25,
			path_system.speed_mps,
			" m/s",
			"World-space target movement speed for this group.",
			func(value: float) -> void:
				path_system.speed_mps = value
				_target_configuration_changed("Target speed changed.")
		)
	_add_number_input(
		target_behavior_settings_body,
		"Hover radius",
		0.05,
		100.0,
		0.05,
		path_system.hover_radius_m,
		" m",
		"Distance from the routed objective that counts as following the target.",
		func(value: float) -> void:
			path_system.hover_radius_m = value
			_target_configuration_changed("Hover radius changed.")
	)

	match path_system.behavior:
		0:
			pass
		1:
			_add_number_input(
				target_behavior_settings_body,
				"Orbit radius",
				0.2,
				100.0,
				0.1,
				path_system.path_radius_m,
				" m",
				"Radius of this group's circular navigation path.",
				func(value: float) -> void:
					path_system.path_radius_m = value
					_target_configuration_changed("Orbit radius changed.")
			)
			_add_automatic_path_orientation_controls(path_system)
		2:
			_add_number_input(
				target_behavior_settings_body,
				"Line half-length",
				0.2,
				100.0,
				0.1,
				path_system.line_half_length_m,
				" m",
				"Distance from path center to either end of this group's line.",
				func(value: float) -> void:
					path_system.line_half_length_m = value
					_target_configuration_changed("Line length changed.")
			)
			_add_automatic_path_orientation_controls(path_system)
		3:
			_add_number_input(
				target_behavior_settings_body,
				"Maximum waypoint jump",
				0.1,
				200.0,
				0.25,
				path_system.random_max_jump_distance_m,
				" m",
				"Maximum 3D distance from this group's current target to its next waypoint.",
				func(value: float) -> void:
					path_system.random_max_jump_distance_m = value
					_target_configuration_changed("Random waypoint jump distance changed.")
			)
			_add_number_input(
				target_behavior_settings_body,
				"Waypoint interval",
				0.1,
				120.0,
				0.1,
				path_system.random_waypoint_interval_seconds,
				" s",
				"Simulated seconds between choosing new random waypoints for this group.",
				func(value: float) -> void:
					path_system.random_waypoint_interval_seconds = value
					path_system.random_timer_seconds = minf(path_system.random_timer_seconds, value)
					_target_configuration_changed("Random waypoint interval changed.")
			)
			_add_number_input(
				target_behavior_settings_body,
				"Horizontal X extent",
				0.0,
				1000.0,
				0.5,
				path_system.random_horizontal_extent_m.x,
				" m",
				"Maximum waypoint distance left or right from arena center.",
				func(value: float) -> void:
					path_system.random_horizontal_extent_m.x = value
					_refresh_random_target_area_preview()
					_target_configuration_changed("Random waypoint X extent changed.")
			)
			_add_number_input(
				target_behavior_settings_body,
				"Horizontal Z extent",
				0.0,
				1000.0,
				0.5,
				path_system.random_horizontal_extent_m.y,
				" m",
				"Maximum waypoint distance forward or backward from arena center.",
				func(value: float) -> void:
					path_system.random_horizontal_extent_m.y = value
					_refresh_random_target_area_preview()
					_target_configuration_changed("Random waypoint Z extent changed.")
			)
			var minimum_waypoint_height_input = _add_number_input(
				target_behavior_settings_body,
				"Minimum waypoint height",
				-100000.0,
				100000.0,
				0.25,
				path_system.random_height_range_m.x,
				" m",
				"First unrestricted height bound used by this group's random waypoints.",
				func(value: float) -> void:
					path_system.random_height_range_m.x = value
					_refresh_random_target_area_preview()
					_target_configuration_changed("Random waypoint minimum height changed.")
			)
			minimum_waypoint_height_input.allow_lesser = true
			minimum_waypoint_height_input.allow_greater = true
			var maximum_waypoint_height_input = _add_number_input(
				target_behavior_settings_body,
				"Maximum waypoint height",
				-100000.0,
				100000.0,
				0.25,
				path_system.random_height_range_m.y,
				" m",
				"Second unrestricted height bound used by this group's random waypoints.",
				func(value: float) -> void:
					path_system.random_height_range_m.y = value
					_refresh_random_target_area_preview()
					_target_configuration_changed("Random waypoint maximum height changed.")
			)
			maximum_waypoint_height_input.allow_lesser = true
			maximum_waypoint_height_input.allow_greater = true
			target_random_area_checkbox = CheckBox.new()
			target_random_area_checkbox.text = "Show waypoint area"
			target_random_area_checkbox.button_pressed = path_system.random_area_visible
			target_random_area_checkbox.tooltip_text = "Show random-waypoint area\n\nDisplays the volume used by the currently selected group's navigation system. The preview is visual only and has no collision."
			target_random_area_checkbox.toggled.connect(func(value: bool) -> void:
				path_system.random_area_visible = value
				_refresh_random_target_area_preview()
			)
			target_behavior_settings_body.add_child(target_random_area_checkbox)
		MANUAL_TARGET_BEHAVIOR:
			target_pad = TARGET_PAD_SCRIPT.new() as Control
			target_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			target_pad.call(
				"configure",
				"X / Z live target pad",
				"Move this group's navigation target\n\nClick or drag to choose its subject position. Path speed controls how quickly the target reaches it.",
				_target_editor_color()
			)
			target_pad.connect("target_selected", _move_target_from_pad)
			target_behavior_settings_body.add_child(target_pad)
			target_position_label = Label.new()
			target_position_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			target_position_label.tooltip_text = "Current routed objective\n\nThis is the exact point forwarded through the existing target-position input when Navigation path wins the handler."
			target_behavior_settings_body.add_child(target_position_label)
			_update_target_pad_marker()
			_refresh_target_position_label()
	_refresh_random_target_area_preview()


func _build_non_path_target_settings(editor_system: TrainingTargetSystem) -> void:
	var info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if editor_system is TrainingRegisteredTargetSystem:
		target_runtime_info_label = info
		_refresh_runtime_target_info_label()
		info.tooltip_text = "Registered target provider\n\nThe provider can hold many live candidates. A selected turret target group publishes its actual live members here. The handler chooses one immediately and forwards only that member's position/velocity/radius tuple to the model."
	else:
		info.text = "This target system has no room-level controls yet."
	target_behavior_settings_body.add_child(info)
	var priorities = Label.new()
	priorities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	priorities.text = "Current hardcoded priority: survival escape > cargo delivery > cargo pickup > combat objective > navigation. Equal-priority registered targets prefer higher urgency, then nearer distance, then stable ID."
	priorities.add_theme_color_override("font_color", Color("a8d8c1"))
	priorities.tooltip_text = "Priority routing\n\nThis is intentionally hardcoded for the first implementation. A TODO in TrainingTargetHandler marks it for future UI sliders and ordering controls."
	target_behavior_settings_body.add_child(priorities)


func _refresh_runtime_target_info_label() -> void:
	if target_runtime_info_label == null or not is_instance_valid(target_runtime_info_label):
		return
	var editor_system: TrainingTargetSystem = _current_target_editor_system()
	var registered = editor_system as TrainingRegisteredTargetSystem
	if registered == null:
		return
	var kinds: Array[String] = registered.active_target_kinds()
	var kind_text: String = ", ".join(PackedStringArray(kinds)) if not kinds.is_empty() else "none"
	target_runtime_info_label.text = (
		"Runtime target provider · %d registered candidate(s) · kinds: %s. "
		+ "Selected turret groups publish every live member here and keep the chosen member stable while it remains weapon-reachable. "
		+ "Range, pitch-arc, and line-of-sight are separate observation facts, so temporarily unreachable workers do not make the task target disappear. "
		+ "Cargo, pickup, swarm, escape, and other task systems can use the same provider without changing model inputs."
	) % [registered.target_count(), kind_text]


func _target_editor_color() -> Color:
	var group_id: int = _selected_target_group_id()
	if group_id < 0:
		return TARGET_MARKER_COLOR
	var group: Dictionary = _selected_any_training_group()
	return group.get("color", TARGET_MARKER_COLOR) if not group.is_empty() else TARGET_MARKER_COLOR


func _add_automatic_path_orientation_controls(path_system: TrainingPathTargetSystem) -> void:
	_add_number_input(
		target_behavior_settings_body,
		"Path yaw",
		-180.0,
		180.0,
		1.0,
		path_system.path_rotation_degrees.y,
		"°",
		"Rotates this group's path around the vertical axis.",
		func(value: float) -> void:
			path_system.path_rotation_degrees.y = value
			_target_configuration_changed("Target path yaw changed.")
	)
	_add_number_input(
		target_behavior_settings_body,
		"Path pitch",
		-90.0,
		90.0,
		1.0,
		path_system.path_rotation_degrees.x,
		"°",
		"Tilts this group's path forward or backward.",
		func(value: float) -> void:
			path_system.path_rotation_degrees.x = value
			_target_configuration_changed("Target path pitch changed.")
	)
	_add_number_input(
		target_behavior_settings_body,
		"Path roll",
		-180.0,
		180.0,
		1.0,
		path_system.path_rotation_degrees.z,
		"°",
		"Tilts this group's path sideways.",
		func(value: float) -> void:
			path_system.path_rotation_degrees.z = value
			_target_configuration_changed("Target path roll changed.")
	)
	_add_number_input(
		target_behavior_settings_body,
		"Starting phase",
		0.0,
		360.0,
		1.0,
		path_system.path_phase_degrees,
		"°",
		"Starting point on this group's path after a target reset.",
		func(value: float) -> void:
			path_system.path_phase_degrees = value
			_target_configuration_changed("Target path phase changed.")
	)
	var reverse_path = CheckBox.new()
	reverse_path.text = "Reverse target path"
	reverse_path.button_pressed = path_system.path_reverse
	reverse_path.tooltip_text = "Reverse target path\n\nMakes this group's target travel around its orbit or line in the opposite direction."
	reverse_path.toggled.connect(func(value: bool) -> void:
		path_system.path_reverse = value
		_target_configuration_changed("Target path direction changed.")
	)
	target_behavior_settings_body.add_child(reverse_path)


func _set_target_height(value: float) -> void:
	var path_system: TrainingPathTargetSystem = _target_editor_path()
	if path_system == null:
		return
	path_system.set_base_height(value)
	_target_configuration_changed("Target height changed.")
	_update_target_pad_marker()
	_refresh_target_position_label()


func _target_configuration_changed(message: String) -> void:
	var group_id: int = _selected_target_group_id()
	var handler: TrainingTargetHandler = _target_editor_handler()
	if handler != null:
		handler.resolve(_target_context_for_group(group_id))
	_refresh_target_visual_for_group(group_id)
	_refresh_random_target_area_preview()
	_push_target_objective_to_live_drones()
	if group_id < 0:
		_restart_for_configuration_change(message)
		return
	var drone_group: Dictionary = _group_by_id(group_id)
	if not drone_group.is_empty():
		if bool(drone_group.get("active", false)):
			# This target belongs only to the selected drone group. Restart the active shared
			# drone cycle as before, but do not destroy unrelated paused groups whose own target
			# generators did not change.
			_restart_for_configuration_change(message, false)
		else:
			_clear_drone_group_runtime_for_configuration_change(drone_group)
			if status_label != null:
				status_label.text = "%s Paused drone episode cleared so one rollout cannot mix target configurations." % message
			_rebuild_group_cards()
			_refresh_selected_group_controls()
		return
	var resolved_target: Dictionary = _resolved_target_for_group_id(group_id)
	var target_position: Vector3 = resolved_target.get(
		"position_world",
		_target_objective_position(group_id)
	)
	var target_velocity: Vector3 = resolved_target.get("velocity_world", Vector3.ZERO)
	var target_radius: float = maxf(float(resolved_target.get("radius_m", 0.75)), 0.05)
	if not limb_training.group_by_id(group_id).is_empty():
		limb_training.restart_group_for_configuration_change(
			group_id,
			drone_spawn_position,
			target_position,
			target_velocity,
			target_radius,
			episode_duration,
			ARENA_SIZE
		)
		if status_label != null:
			status_label.text = "%s Four-limb episode restarted so one rollout cannot mix target configurations." % message
		return
	if not turret_training.group_by_id(group_id).is_empty():
		turret_training.restart_group_for_configuration_change(
			group_id,
			target_position,
			episode_duration,
			ARENA_SIZE
		)
		if status_label != null:
			status_label.text = "%s Turret episode restarted so one rollout cannot mix target configurations." % message
		return
	if status_label != null:
		status_label.text = message


func _refresh_target_position_label() -> void:
	if target_position_label == null:
		return
	var group_id: int = _selected_target_group_id()
	var displayed_position: Vector3 = _target_objective_local_position(group_id)
	target_position_label.text = "Current routed objective · X %s m · Y %s m · Z %s m" % [
		String.num(displayed_position.x, 2),
		String.num(displayed_position.y, 2),
		String.num(displayed_position.z, 2),
	]


func _build_wall_controls(content: VBoxContainer) -> void:
	var shape_row = HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 8)
	content.add_child(shape_row)
	var shape_label = Label.new()
	shape_label.text = "Shape"
	shape_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(shape_label)
	wall_shape_picker = OptionButton.new()
	wall_shape_picker.custom_minimum_size.x = 150.0
	for shape_name in DroneTrainingObstacleShape.DISPLAY_NAMES:
		wall_shape_picker.add_item(shape_name)
	wall_shape_picker.select(wall_shape_kind)
	wall_shape_picker.tooltip_text = "Obstacle shape\n\nChoose the primitive to create.\nThe Dimensions box updates to show only values used by that shape."
	wall_shape_picker.item_selected.connect(_set_wall_shape)
	shape_row.add_child(wall_shape_picker)

	wall_dimensions_body = _add_section(
		content,
		"DIMENSIONS",
		"The selected obstacle shape determines which dimensions are editable.",
		true
	)
	_rebuild_wall_dimension_inputs()

	var placement = _add_section(
		content,
		"POSITION & ROTATION",
		"All world coordinates and Euler rotations are unrestricted. Mouse placement starts on the arena floor; numeric values may place and rotate obstacles anywhere.",
		true
	)
	wall_position_x_input = _add_number_input(
		placement,
		"Position X",
		-1000000.0,
		1000000.0,
		0.1,
		wall_position_x_m,
		" m",
		"World-space left/right position of the obstacle center.",
		func(value: float) -> void:
			wall_position_x_m = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_position_x_input, true)
	wall_position_y_input = _add_number_input(
		placement,
		"Position Y",
		-1000000.0,
		1000000.0,
		0.1,
		wall_position_y_m,
		" m",
		"Unrestricted world-space vertical position of the obstacle center.",
		func(value: float) -> void:
			wall_position_y_m = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_position_y_input, true)
	wall_position_z_input = _add_number_input(
		placement,
		"Position Z",
		-1000000.0,
		1000000.0,
		0.1,
		wall_position_z_m,
		" m",
		"World-space forward/back position of the obstacle center.",
		func(value: float) -> void:
			wall_position_z_m = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_position_z_input, true)
	wall_pitch_input = _add_number_input(
		placement,
		"Pitch",
		-1000000.0,
		1000000.0,
		1.0,
		wall_pitch_degrees,
		"°",
		"Unrestricted rotation around local X.",
		func(value: float) -> void:
			wall_pitch_degrees = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_pitch_input, true)
	wall_yaw_input = _add_number_input(
		placement,
		"Yaw",
		-1000000.0,
		1000000.0,
		1.0,
		wall_yaw_degrees,
		"°",
		"Unrestricted rotation around the vertical axis.",
		func(value: float) -> void:
			wall_yaw_degrees = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_yaw_input, true)
	wall_roll_input = _add_number_input(
		placement,
		"Roll",
		-1000000.0,
		1000000.0,
		1.0,
		wall_roll_degrees,
		"°",
		"Unrestricted rotation around local Z.",
		func(value: float) -> void:
			wall_roll_degrees = value
			_update_wall_preview()
	)
	_configure_unbounded_spinbox(wall_roll_input, true)

	var place_row = HBoxContainer.new()
	place_row.add_theme_constant_override("separation", 7)
	content.add_child(place_row)
	var spawn_button = _button("SPAWN AT VALUES", true)
	spawn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_button.tooltip_text = "Create obstacle now\n\nUses the exact shape, dimensions, position, and rotation shown above."
	spawn_button.pressed.connect(func() -> void:
		if wall_placement_active:
			_cancel_wall_placement("")
		_spawn_or_replace_custom_wall()
	)
	place_row.add_child(spawn_button)
	wall_place_button = _button("SPAWN WITH MOUSE")
	wall_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_place_button.tooltip_text = "Place obstacle with the mouse\n\nThe next left-click places the selected shape on the arena floor.\nRight-click or Escape cancels placement."
	wall_place_button.pressed.connect(_toggle_wall_placement)
	place_row.add_child(wall_place_button)

	wall_auto_replace_button = ROLLING_SAVE_BUTTON_SCRIPT.new() as Button
	wall_auto_replace_button.text = "AUTO PLACE: OFF"
	wall_auto_replace_button.toggle_mode = true
	wall_auto_replace_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_auto_replace_button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(false)
	)
	wall_auto_replace_button.tooltip_text = (
		"Automatic obstacle placement\n\n"
		+ "When enabled, mouse placement stays armed after every click.\n"
		+ "Each click creates another obstacle, so you do not need to press Spawn with Mouse again.\n\n"
		+ "Use Apply to Selected when you want to edit an existing obstacle instead."
	)
	wall_auto_replace_button.call(
		"configure",
		CUSTOM_WALL_SELECTED_COLOR,
		wall_auto_replace_enabled
	)
	wall_auto_replace_button.toggled.connect(_set_wall_auto_replace)
	content.add_child(wall_auto_replace_button)

	var edit_row = HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 7)
	content.add_child(edit_row)
	wall_apply_button = _button("APPLY TO SELECTED", true)
	wall_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_apply_button.tooltip_text = "Apply edits to selected obstacle\n\nRebuilds the highlighted obstacle using the values currently shown."
	wall_apply_button.pressed.connect(_apply_wall_values_to_selected)
	edit_row.add_child(wall_apply_button)
	wall_delete_button = _button("DELETE SELECTED")
	wall_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_delete_button.tooltip_text = "Delete selected obstacle\n\nPermanently removes only the highlighted custom obstacle."
	wall_delete_button.pressed.connect(_delete_selected_custom_wall)
	_set_button_danger(wall_delete_button)
	edit_row.add_child(wall_delete_button)

	var cleanup_row = HBoxContainer.new()
	cleanup_row.add_theme_constant_override("separation", 7)
	content.add_child(cleanup_row)
	var remove_last_button = _button("REMOVE LAST")
	remove_last_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_last_button.tooltip_text = "Remove last obstacle\n\nDeletes the newest custom obstacle, even when another obstacle is selected."
	remove_last_button.pressed.connect(_remove_last_custom_wall)
	_set_button_danger(remove_last_button)
	cleanup_row.add_child(remove_last_button)
	var clear_button = _button("CLEAR ALL")
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.tooltip_text = "Clear custom obstacles\n\nDeletes every obstacle you created in this training-room session."
	clear_button.pressed.connect(_clear_custom_walls)
	_set_button_danger(clear_button)
	cleanup_row.add_child(clear_button)

	wall_status_label = Label.new()
	wall_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(wall_status_label)
	_refresh_wall_status()


func _build_training_item_controls(content: VBoxContainer) -> void:
	var shape_row: HBoxContainer = HBoxContainer.new()
	shape_row.add_theme_constant_override("separation", 8)
	content.add_child(shape_row)
	var shape_label: Label = Label.new()
	shape_label.text = "Shape"
	shape_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(shape_label)
	training_item_shape_picker = OptionButton.new()
	training_item_shape_picker.custom_minimum_size.x = 150.0
	for shape_name: String in DroneTrainingObstacleShape.DISPLAY_NAMES:
		training_item_shape_picker.add_item(shape_name)
	training_item_shape_picker.select(training_item_shape_kind)
	training_item_shape_picker.tooltip_text = "Training item shape\n\nUses the same primitive shape contract as Training Obstacles so collision and visible dimensions always agree."
	training_item_shape_picker.item_selected.connect(_set_training_item_shape)
	shape_row.add_child(training_item_shape_picker)

	training_item_dimensions_body = _add_section(
		content,
		"DIMENSIONS",
		"Set the physical item size. Chain two or more dimensions to keep them equal while editing, exactly like Training Obstacles.",
		true
	)
	_rebuild_training_item_dimension_inputs()

	var properties: VBoxContainer = _add_section(
		content,
		"ITEM PROPERTIES",
		"Mass changes the real rigid-body weight and therefore grip load. Reward value is task metadata used by pickup reward now and by future take/bring-here tasks.",
		true
	)
	var type_row: HBoxContainer = HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	properties.add_child(type_row)
	var type_label: Label = Label.new()
	type_label.text = "Item type"
	type_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_row.add_child(type_label)
	training_item_type_input = LineEdit.new()
	training_item_type_input.text = training_item_type
	training_item_type_input.custom_minimum_size.x = 150.0
	training_item_type_input.placeholder_text = "generic"
	training_item_type_input.tooltip_text = "Stable cargo type\n\nDelivery groups accept one or more item types. Names are normalized case-insensitively (for example Medical Crate becomes medical_crate)."
	training_item_type_input.text_changed.connect(func(value: String) -> void:
		training_item_type = TrainingItem3D.normalized_item_type(value)
	)
	training_item_type_input.focus_exited.connect(func() -> void:
		training_item_type = TrainingItem3D.normalized_item_type(training_item_type_input.text)
		training_item_type_input.text = training_item_type
	)
	type_row.add_child(training_item_type_input)
	training_item_mass_input = _add_number_input(
		properties,
		"Weight",
		0.01,
		1000000.0,
		0.05,
		training_item_mass_kg,
		" kg",
		"Physical rigid-body mass. A gripper still obeys its own maximum held mass, so very heavy items can intentionally be impossible for a weak worker to carry.",
		func(value: float) -> void:
			training_item_mass_kg = maxf(value, 0.01)
		)
	_configure_unbounded_spinbox(training_item_mass_input, false)
	training_item_reward_input = _add_number_input(
		properties,
		"Reward value",
		0.0,
		1000.0,
		0.05,
		training_item_reward_value,
		"",
		"Intrinsic task value of this item. The limb pickup reward scales by this value; future delivery/task systems can reuse the same field instead of inventing another item score.",
		func(value: float) -> void:
			training_item_reward_value = maxf(value, 0.0)
		)
	_configure_unbounded_spinbox(training_item_reward_input, false)

	var placement: VBoxContainer = _add_section(
		content,
		"POSITION & ROTATION",
		"Numeric values author the item's spawn transform. Mouse placement rests the current shape on the arena floor or an upward-facing obstacle surface.",
		true
	)
	training_item_position_x_input = _add_number_input(
		placement, "Position X", -1000000.0, 1000000.0, 0.1,
		training_item_position_x_m, " m", "Authored world-space item spawn X.",
		func(value: float) -> void:
			training_item_position_x_m = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_position_x_input, true)
	training_item_position_y_input = _add_number_input(
		placement, "Position Y", -1000000.0, 1000000.0, 0.1,
		training_item_position_y_m, " m", "Authored world-space item spawn Y.",
		func(value: float) -> void:
			training_item_position_y_m = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_position_y_input, true)
	training_item_position_z_input = _add_number_input(
		placement, "Position Z", -1000000.0, 1000000.0, 0.1,
		training_item_position_z_m, " m", "Authored world-space item spawn Z.",
		func(value: float) -> void:
			training_item_position_z_m = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_position_z_input, true)
	training_item_pitch_input = _add_number_input(
		placement, "Pitch", -1000000.0, 1000000.0, 1.0,
		training_item_pitch_degrees, "°", "Item rotation around local X.",
		func(value: float) -> void:
			training_item_pitch_degrees = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_pitch_input, true)
	training_item_yaw_input = _add_number_input(
		placement, "Yaw", -1000000.0, 1000000.0, 1.0,
		training_item_yaw_degrees, "°", "Item rotation around local Y.",
		func(value: float) -> void:
			training_item_yaw_degrees = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_yaw_input, true)
	training_item_roll_input = _add_number_input(
		placement, "Roll", -1000000.0, 1000000.0, 1.0,
		training_item_roll_degrees, "°", "Item rotation around local Z.",
		func(value: float) -> void:
			training_item_roll_degrees = value
			_update_training_item_preview()
	)
	_configure_unbounded_spinbox(training_item_roll_input, true)

	var spawn_row: HBoxContainer = HBoxContainer.new()
	spawn_row.add_theme_constant_override("separation", 7)
	content.add_child(spawn_row)
	var spawn_button: Button = _button("SPAWN AT VALUES", true)
	spawn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_button.tooltip_text = "Spawn one training item using the exact values above."
	spawn_button.pressed.connect(func() -> void:
		if training_item_placement_active:
			_cancel_training_item_placement("", true)
		var item: TrainingItem3D = _spawn_training_item(true)
		if item != null:
			status_label.text = "Training item %d spawned." % item.training_item_id
	)
	spawn_row.add_child(spawn_button)
	training_item_place_button = _button("SPAWN WITH MOUSE")
	training_item_place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_item_place_button.tooltip_text = "Continuous item placement\n\nLeft-click repeatedly to create as many items as you want. Placement stays armed after every click. Right-click, Escape, or this button ends the session."
	training_item_place_button.pressed.connect(_toggle_training_item_placement)
	spawn_row.add_child(training_item_place_button)

	var edit_row: HBoxContainer = HBoxContainer.new()
	edit_row.add_theme_constant_override("separation", 7)
	content.add_child(edit_row)
	training_item_apply_button = _button("APPLY TO SELECTED", true)
	training_item_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_item_apply_button.tooltip_text = "Apply current shape, dimensions, weight, reward value, and transform to the selected training item."
	training_item_apply_button.pressed.connect(_apply_training_item_values_to_selected)
	edit_row.add_child(training_item_apply_button)
	training_item_delete_button = _button("DELETE SELECTED")
	training_item_delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	training_item_delete_button.tooltip_text = "Delete only the selected training item."
	training_item_delete_button.pressed.connect(_delete_selected_training_item)
	_set_button_danger(training_item_delete_button)
	edit_row.add_child(training_item_delete_button)

	var cleanup_row: HBoxContainer = HBoxContainer.new()
	cleanup_row.add_theme_constant_override("separation", 7)
	content.add_child(cleanup_row)
	var reset_button: Button = _button("RESET TO SPAWNS")
	reset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_button.tooltip_text = "Return every training item to its authored spawn transform with zero linear/angular velocity."
	reset_button.pressed.connect(_reset_all_training_items)
	cleanup_row.add_child(reset_button)
	var clear_button: Button = _button("CLEAR ALL")
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.tooltip_text = "Delete every authored training item from the room."
	clear_button.pressed.connect(_clear_training_items)
	_set_button_danger(clear_button)
	cleanup_row.add_child(clear_button)

	training_item_status_label = Label.new()
	training_item_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(training_item_status_label)
	_refresh_training_item_status()
	_build_delivery_destination_controls(content)


func _build_delivery_destination_controls(content: VBoxContainer) -> void:
	var destination_section: VBoxContainer = _add_section(
		content,
		"DELIVERY DESTINATIONS",
		"Destination groups share one acceptance/reward policy across every placed volume in that group. A delivery-trained limb approaches compatible cargo first, then routes the held item toward the nearest matching destination. Enable the ‘Deliver held item’ reward card or use the Item Pickup + Delivery preset.",
		true
	)
	var add_group_button: Button = _button("+ NEW DESTINATION GROUP", true)
	add_group_button.tooltip_text = "Create delivery destination group\n\nChoose accepted item types and reward policy, then place the first destination in the arena. Use + on the group row to add more destinations with the same policy."
	add_group_button.pressed.connect(_open_delivery_destination_dialog.bind(-1))
	destination_section.add_child(add_group_button)
	delivery_destination_list = VBoxContainer.new()
	delivery_destination_list.add_theme_constant_override("separation", 6)
	destination_section.add_child(delivery_destination_list)
	_rebuild_delivery_destination_group_rows()
	_build_delivery_destination_dialog()


func _build_delivery_destination_dialog() -> void:
	if delivery_destination_dialog != null:
		return
	delivery_destination_dialog = ConfirmationDialog.new()
	delivery_destination_dialog.title = "Delivery Destination Group"
	delivery_destination_dialog.wrap_controls = false
	delivery_destination_dialog.size = Vector2i(620, 620)
	delivery_destination_dialog.min_size = Vector2i(620, 620)
	delivery_destination_dialog.ok_button_text = "CREATE & PLACE"
	delivery_destination_dialog.cancel_button_text = "CANCEL"
	add_child(delivery_destination_dialog)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12.0
	scroll.offset_top = 12.0
	scroll.offset_right = -12.0
	scroll.offset_bottom = -58.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	delivery_destination_dialog.add_child(scroll)
	var body: VBoxContainer = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 9)
	scroll.add_child(body)
	delivery_destination_dialog_title = Label.new()
	delivery_destination_dialog_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(delivery_destination_dialog_title)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	body.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = "Group name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	delivery_destination_name_input = LineEdit.new()
	delivery_destination_name_input.custom_minimum_size.x = 260.0
	name_row.add_child(delivery_destination_name_input)
	delivery_destination_accept_all_checkbox = CheckBox.new()
	delivery_destination_accept_all_checkbox.text = "Accept every item type"
	delivery_destination_accept_all_checkbox.tooltip_text = "When enabled, every Training Item type is accepted by every destination in this group."
	delivery_destination_accept_all_checkbox.toggled.connect(func(enabled: bool) -> void:
		if delivery_destination_types_input != null:
			delivery_destination_types_input.editable = not enabled
	)
	body.add_child(delivery_destination_accept_all_checkbox)
	var types_label: Label = Label.new()
	types_label.text = "Accepted item types"
	body.add_child(types_label)
	delivery_destination_types_input = LineEdit.new()
	delivery_destination_types_input.placeholder_text = "generic, ore, medical_crate"
	delivery_destination_types_input.tooltip_text = "Comma-separated item types\n\nMultiple types may be accepted simultaneously. Matching is case-insensitive and uses the same normalized type keys shown on Training Items."
	body.add_child(delivery_destination_types_input)
	delivery_destination_available_types_label = Label.new()
	delivery_destination_available_types_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delivery_destination_available_types_label.add_theme_color_override("font_color", Color("8aaea1"))
	body.add_child(delivery_destination_available_types_label)
	delivery_destination_radius_input = _add_number_input(
		body, "Destination radius", 0.10, 1000.0, 0.05,
		DELIVERY_DESTINATION_DEFAULT_RADIUS_M, " m",
		"Horizontal acceptance radius shared by every destination in this group.",
		func(_value: float) -> void: pass
	)
	delivery_destination_height_input = _add_number_input(
		body, "Destination height", 0.10, 1000.0, 0.05,
		DELIVERY_DESTINATION_DEFAULT_HEIGHT_M, " m",
		"Vertical acceptance height shared by every destination in this group.",
		func(_value: float) -> void: pass
	)
	delivery_destination_approach_reward_input = _add_number_input(
		body, "Approach reward scale", 0.0, 1000.0, 0.05,
		1.0, "",
		"Scales signed potential reward while an accepted item is actually held. Moving closer pays; moving away gives the reward back.",
		func(_value: float) -> void: pass
	)
	delivery_destination_completion_reward_input = _add_number_input(
		body, "Delivery reward scale", 0.0, 1000.0, 0.05,
		1.0, "",
		"One-time completion reward when an accepted held item enters any destination in this group. The item's own Reward value multiplies this scale.",
		func(_value: float) -> void: pass
	)
	delivery_destination_dialog.confirmed.connect(_confirm_delivery_destination_dialog)


func _open_delivery_destination_dialog(group_id: int) -> void:
	if delivery_destination_placement_active:
		_cancel_delivery_destination_placement("", false)
	if delivery_destination_dialog == null:
		_build_delivery_destination_dialog()
	delivery_destination_dialog_group_id = group_id
	var group: Dictionary = _delivery_destination_group_by_id(group_id)
	var editing: bool = not group.is_empty()
	if delivery_destination_dialog_title != null:
		delivery_destination_dialog_title.text = (
			"Edit the shared policy. Radius/height and acceptance changes apply to every placed destination in this group."
			if editing
			else "Create one shared delivery policy, then place its first destination. More destinations can be added later with the group's + button."
		)
	delivery_destination_name_input.text = str(group.get("name", "Delivery group %d" % (delivery_destination_group_counter + 1)))
	delivery_destination_accept_all_checkbox.button_pressed = RLTrainingMath.bool_or(
		group.get("accept_all_item_types", false),
		false
	)
	delivery_destination_types_input.editable = not delivery_destination_accept_all_checkbox.button_pressed
	var accepted: PackedStringArray = _delivery_item_types_from_variant(
		group.get("accepted_item_types", PackedStringArray([TRAINING_ITEM_DEFAULT_TYPE]))
	)
	if accepted.is_empty():
		accepted.append(TRAINING_ITEM_DEFAULT_TYPE)
	delivery_destination_types_input.text = ", ".join(Array(accepted))
	if delivery_destination_available_types_label != null:
		var authored_types: PackedStringArray = _authored_training_item_types()
		delivery_destination_available_types_label.text = (
			"Authored item types currently in room: %s" % ", ".join(Array(authored_types))
			if not authored_types.is_empty()
			else "No authored item types in room yet. You can still enter future type names here."
		)
	delivery_destination_radius_input.set_value_no_signal(float(group.get("radius_m", DELIVERY_DESTINATION_DEFAULT_RADIUS_M)))
	delivery_destination_height_input.set_value_no_signal(float(group.get("height_m", DELIVERY_DESTINATION_DEFAULT_HEIGHT_M)))
	delivery_destination_approach_reward_input.set_value_no_signal(float(group.get("approach_reward_scale", 1.0)))
	delivery_destination_completion_reward_input.set_value_no_signal(float(group.get("completion_reward_scale", 1.0)))
	delivery_destination_dialog.ok_button_text = "APPLY POLICY" if editing else "CREATE & PLACE"
	delivery_destination_dialog.size = Vector2i(620, 620)
	delivery_destination_dialog.popup_centered()
	call_deferred("_focus_delivery_destination_name")


func _focus_delivery_destination_name() -> void:
	if delivery_destination_dialog != null and delivery_destination_dialog.visible:
		delivery_destination_name_input.grab_focus()
		delivery_destination_name_input.select_all()


func _confirm_delivery_destination_dialog() -> void:
	var accepted_types: PackedStringArray = _parse_delivery_item_types(delivery_destination_types_input.text)
	var accept_all: bool = delivery_destination_accept_all_checkbox.button_pressed
	if not accept_all and accepted_types.is_empty():
		accepted_types.append(TRAINING_ITEM_DEFAULT_TYPE)
	var radius_m: float = maxf(float(delivery_destination_radius_input.value), 0.10)
	var height_m: float = maxf(float(delivery_destination_height_input.value), 0.10)
	var approach_scale: float = maxf(float(delivery_destination_approach_reward_input.value), 0.0)
	var completion_scale: float = maxf(float(delivery_destination_completion_reward_input.value), 0.0)
	var group: Dictionary = _delivery_destination_group_by_id(delivery_destination_dialog_group_id)
	var created: bool = group.is_empty()
	if created:
		delivery_destination_group_counter += 1
		var group_id: int = delivery_destination_group_counter
		var color: Color = DELIVERY_DESTINATION_COLORS[(group_id - 1) % DELIVERY_DESTINATION_COLORS.size()]
		group = {
			"group_id": group_id,
			"name": delivery_destination_name_input.text.strip_edges() if not delivery_destination_name_input.text.strip_edges().is_empty() else "Delivery group %d" % group_id,
			"color": color,
			"accept_all_item_types": accept_all,
			"accepted_item_types": accepted_types,
			"radius_m": radius_m,
			"height_m": height_m,
			"approach_reward_scale": approach_scale,
			"completion_reward_scale": completion_scale,
			"destination_counter": 0,
			"destinations": [],
		}
		delivery_destination_groups.append(group)
		delivery_destination_groups_by_id[group_id] = group
	else:
		group["name"] = delivery_destination_name_input.text.strip_edges() if not delivery_destination_name_input.text.strip_edges().is_empty() else str(group.get("name", "Delivery group"))
		group["accept_all_item_types"] = accept_all
		group["accepted_item_types"] = accepted_types
		group["radius_m"] = radius_m
		group["height_m"] = height_m
		group["approach_reward_scale"] = approach_scale
		group["completion_reward_scale"] = completion_scale
		for destination_value: Variant in group.get("destinations", []):
			var destination: TrainingItemDeliveryDestination3D = destination_value as TrainingItemDeliveryDestination3D
			if not is_instance_valid(destination):
				continue
			destination.configure_destination(
				int(group["group_id"]), destination.destination_id,
				radius_m, height_m, destination.spawn_transform_world,
				group.get("color", Color("54e6b1"))
			)
			_register_delivery_destination(destination, group)
	_rebuild_delivery_destination_group_rows()
	if created:
		_begin_delivery_destination_placement(int(group["group_id"]))
	else:
		_restart_limb_groups_for_delivery_change("Delivery destination policy changed; limb episodes restarted.")
		status_label.text = "Delivery destination policy updated for every destination in %s." % str(group["name"])


func _parse_delivery_item_types(text: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for raw_value: String in text.split(",", false):
		# A whitespace-only field is an omitted value, not an implicit request for the generic type.
		# This matters for ordinary editing such as `ore, , medical_crate`, where normalizing the blank
		# token would otherwise silently broaden the accepted cargo policy.
		if raw_value.strip_edges().is_empty():
			continue
		var item_type: String = TrainingItem3D.normalized_item_type(raw_value)
		if not result.has(item_type):
			result.append(item_type)
	return result


func _delivery_item_types_from_variant(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var raw_values: Array = []
	if value is Array:
		raw_values = value as Array
	elif value is PackedStringArray:
		var packed_values: PackedStringArray = value as PackedStringArray
		for packed_value: String in packed_values:
			raw_values.append(packed_value)
	elif value is String:
		return _parse_delivery_item_types(value as String)
	for raw_value: Variant in raw_values:
		var raw_text: String = str(raw_value)
		if raw_text.strip_edges().is_empty():
			continue
		var item_type: String = TrainingItem3D.normalized_item_type(raw_text)
		if not result.has(item_type):
			result.append(item_type)
	return result


func _authored_training_item_types() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for item: TrainingItem3D in training_items:
		if not is_instance_valid(item):
			continue
		var item_type: String = TrainingItem3D.normalized_item_type(item.item_type)
		if not result.has(item_type):
			result.append(item_type)
	result.sort()
	return result


func _delivery_destination_group_by_id(group_id: int) -> Dictionary:
	return delivery_destination_groups_by_id.get(group_id, {})


func _limb_group_uses_delivery_task(group: Dictionary) -> bool:
	if group.is_empty():
		return false
	var deck: FourLimbRewardDeck = group.get("reward_deck") as FourLimbRewardDeck
	var delivery_card: FourLimbRewardCard = deck.card("item_delivery") if deck != null else null
	return delivery_card != null and delivery_card.enabled and delivery_card.intensity > 0.0


func _delivery_group_accepts_item(group: Dictionary, item: TrainingItem3D) -> bool:
	if group.is_empty() or not is_instance_valid(item):
		return false
	if RLTrainingMath.bool_or(group.get("accept_all_item_types", false), false):
		return true
	var accepted: PackedStringArray = _delivery_item_types_from_variant(
		group.get("accepted_item_types", PackedStringArray())
	)
	return accepted.has(TrainingItem3D.normalized_item_type(item.item_type))


func _delivery_fallback_item_type_for_limb(group_id: int = -1) -> String:
	var limb_group: Dictionary = limb_training.group_by_id(group_id)
	if not _limb_group_uses_delivery_task(limb_group):
		return TrainingItem3D.DEFAULT_ITEM_TYPE
	var accepted_types: PackedStringArray = PackedStringArray()
	for group: Dictionary in delivery_destination_groups:
		# A policy without a placed volume cannot currently complete a delivery, so it must not
		# decide the private fallback cargo type for an active lesson.
		if _valid_delivery_destinations(group).is_empty():
			continue
		if RLTrainingMath.bool_or(group.get("accept_all_item_types", false), false):
			return TrainingItem3D.DEFAULT_ITEM_TYPE
		for item_type: String in _delivery_item_types_from_variant(
			group.get("accepted_item_types", PackedStringArray())
		):
			if not accepted_types.has(item_type):
				accepted_types.append(item_type)
	if accepted_types.is_empty():
		return TrainingItem3D.DEFAULT_ITEM_TYPE
	accepted_types.sort()
	return accepted_types[0]


func _rebuild_delivery_destination_group_rows() -> void:
	if delivery_destination_list == null:
		return
	for child: Node in delivery_destination_list.get_children():
		child.queue_free()
	if delivery_destination_groups.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "No delivery destination groups yet."
		empty_label.add_theme_color_override("font_color", Color("8aaea1"))
		delivery_destination_list.add_child(empty_label)
		return
	for group: Dictionary in delivery_destination_groups:
		var panel: PanelContainer = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", DroneTrainingRoomPresentation.scanner_panel_style(true))
		delivery_destination_list.add_child(panel)
		var body: VBoxContainer = VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		panel.add_child(body)
		var header: HBoxContainer = HBoxContainer.new()
		header.add_theme_constant_override("separation", 5)
		body.add_child(header)
		var title: Label = Label.new()
		title.text = "%s · %d" % [str(group.get("name", "Delivery group")), _valid_delivery_destinations(group).size()]
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_color_override("font_color", group.get("color", Color("54e6b1")))
		header.add_child(title)
		var add_button: Button = _button("+")
		add_button.custom_minimum_size = Vector2(30.0, 28.0)
		add_button.tooltip_text = "Place another destination\n\nAdds one more destination using this group's existing policy."
		var group_id: int = int(group.get("group_id", -1))
		add_button.pressed.connect(_begin_delivery_destination_placement.bind(group_id))
		header.add_child(add_button)
		var remove_button: Button = _button("−")
		remove_button.custom_minimum_size = Vector2(30.0, 28.0)
		remove_button.tooltip_text = "Remove newest destination\n\nDeletes only the most recently placed destination in this group; the shared policy and the other destinations remain."
		remove_button.disabled = _valid_delivery_destinations(group).is_empty()
		remove_button.pressed.connect(_remove_last_delivery_destination.bind(group_id))
		header.add_child(remove_button)
		var edit_button: Button = _button("EDIT")
		edit_button.pressed.connect(_open_delivery_destination_dialog.bind(group_id))
		header.add_child(edit_button)
		var delete_button: Button = _button("X")
		delete_button.tooltip_text = "Delete this destination group and all of its placed destinations."
		_set_button_danger(delete_button)
		delete_button.pressed.connect(_delete_delivery_destination_group.bind(group_id))
		header.add_child(delete_button)
		var accepted_types: PackedStringArray = _delivery_item_types_from_variant(
			group.get("accepted_item_types", PackedStringArray())
		)
		var accepted_text: String = (
			"all item types"
			if RLTrainingMath.bool_or(group.get("accept_all_item_types", false), false)
			else ", ".join(Array(accepted_types))
		)
		var info: Label = Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = "Accepts: %s · radius %s m · height %s m · approach ×%s · delivery ×%s" % [
			accepted_text,
			String.num(float(group.get("radius_m", 1.25)), 2),
			String.num(float(group.get("height_m", 1.25)), 2),
			String.num(float(group.get("approach_reward_scale", 1.0)), 2),
			String.num(float(group.get("completion_reward_scale", 1.0)), 2),
		]
		body.add_child(info)


func _valid_delivery_destinations(group: Dictionary) -> Array[TrainingItemDeliveryDestination3D]:
	var result: Array[TrainingItemDeliveryDestination3D] = []
	for value: Variant in group.get("destinations", []):
		var destination: TrainingItemDeliveryDestination3D = value as TrainingItemDeliveryDestination3D
		if is_instance_valid(destination):
			result.append(destination)
	return result


func _delete_delivery_destination_group(group_id: int) -> void:
	var group: Dictionary = _delivery_destination_group_by_id(group_id)
	if group.is_empty():
		return
	if delivery_destination_placement_active and delivery_destination_placement_group_id == group_id:
		_cancel_delivery_destination_placement("", false)
	for destination: TrainingItemDeliveryDestination3D in _valid_delivery_destinations(group):
		_unregister_delivery_destination(destination)
		if destination.get_parent() != null:
			destination.get_parent().remove_child(destination)
		destination.queue_free()
	delivery_destination_groups.erase(group)
	delivery_destination_groups_by_id.erase(group_id)
	_rebuild_delivery_destination_group_rows()
	_restart_limb_groups_for_delivery_change("Delivery destination group deleted; limb episodes restarted.")


func _remove_last_delivery_destination(group_id: int) -> void:
	var group: Dictionary = _delivery_destination_group_by_id(group_id)
	if group.is_empty():
		return
	var destinations: Array[TrainingItemDeliveryDestination3D] = _valid_delivery_destinations(group)
	if destinations.is_empty():
		if status_label != null:
			status_label.text = "This delivery group has no placed destinations to remove."
		return
	var destination: TrainingItemDeliveryDestination3D = destinations.back()
	_unregister_delivery_destination(destination)
	var raw_destinations: Array = group.get("destinations", [])
	raw_destinations.erase(destination)
	group["destinations"] = raw_destinations
	if destination.get_parent() != null:
		destination.get_parent().remove_child(destination)
	destination.queue_free()
	_rebuild_delivery_destination_group_rows()
	_restart_limb_groups_for_delivery_change("Delivery destination removed; limb episodes restarted.")


func _begin_delivery_destination_placement(group_id: int) -> void:
	var group: Dictionary = _delivery_destination_group_by_id(group_id)
	if group.is_empty():
		return
	if training_item_placement_active:
		_cancel_training_item_placement("", true)
	if turret_placement_active:
		_cancel_turret_placement("")
	if wall_placement_active:
		_cancel_wall_placement("")
	delivery_destination_placement_active = true
	delivery_destination_placement_group_id = group_id
	_ensure_delivery_destination_preview()
	_update_delivery_destination_preview()
	status_label.text = "Place a destination for %s with left-click. Right-click or Escape cancels." % str(group.get("name", "delivery group"))


func _cancel_delivery_destination_placement(message: String, _restart_if_changed: bool) -> void:
	delivery_destination_placement_active = false
	delivery_destination_placement_group_id = -1
	if delivery_destination_preview != null:
		delivery_destination_preview.visible = false
	if not message.is_empty() and status_label != null:
		status_label.text = message


func _ensure_delivery_destination_preview() -> void:
	if is_instance_valid(delivery_destination_preview):
		return
	delivery_destination_preview = MeshInstance3D.new()
	delivery_destination_preview.name = "DeliveryDestinationPreview"
	delivery_destination_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	delivery_destination_preview_mesh = CylinderMesh.new()
	delivery_destination_preview_mesh.radial_segments = 40
	delivery_destination_preview.mesh = delivery_destination_preview_mesh
	var initial_preview_color: Color = Color("54e6b1")
	initial_preview_color.a = DELIVERY_DESTINATION_PREVIEW_ALPHA
	delivery_destination_preview_material = DroneTrainingRoomPresentation.material(
		initial_preview_color,
		true
	)
	delivery_destination_preview.material_override = delivery_destination_preview_material
	add_child(delivery_destination_preview)


func _update_delivery_destination_preview() -> void:
	if delivery_destination_preview == null:
		return
	var group: Dictionary = _delivery_destination_group_by_id(delivery_destination_placement_group_id)
	if group.is_empty():
		delivery_destination_preview.visible = false
		return
	var radius_m: float = maxf(float(group.get("radius_m", 1.25)), 0.10)
	var height_m: float = maxf(float(group.get("height_m", 1.25)), 0.10)
	if delivery_destination_preview_mesh == null:
		delivery_destination_preview_mesh = CylinderMesh.new()
		delivery_destination_preview_mesh.radial_segments = 40
		delivery_destination_preview.mesh = delivery_destination_preview_mesh
	delivery_destination_preview_mesh.top_radius = radius_m
	delivery_destination_preview_mesh.bottom_radius = radius_m
	delivery_destination_preview_mesh.height = height_m
	delivery_destination_preview.global_position = delivery_destination_placement_position + Vector3.UP * (height_m * 0.5)
	var color: Color = group.get("color", Color("54e6b1"))
	var preview_color: Color = Color(color.r, color.g, color.b, DELIVERY_DESTINATION_PREVIEW_ALPHA)
	if delivery_destination_preview_material == null:
		delivery_destination_preview_material = DroneTrainingRoomPresentation.material(preview_color, true)
		delivery_destination_preview.material_override = delivery_destination_preview_material
	else:
		delivery_destination_preview_material.albedo_color = preview_color
		delivery_destination_preview_material.emission = Color(color.r, color.g, color.b)
	delivery_destination_preview.visible = delivery_destination_placement_active


func _delivery_destination_surface_hit(screen_position: Vector2) -> Dictionary:
	return DroneTrainingEditorRaycast.authored_surface_hit(
		_interaction_camera(),
		get_world_3d(),
		screen_position,
		EDITOR_PICK_RAY_LENGTH_M,
		ARENA_COLLISION_LAYER,
		TRAINING_ITEM_PLACEMENT_MAXIMUM_RAY_RETRIES,
		DELIVERY_DESTINATION_MINIMUM_SURFACE_NORMAL_Y,
		false
	)

func _update_delivery_destination_position_from_screen(screen_position: Vector2) -> bool:
	if not delivery_destination_placement_active:
		return false
	var hit: Dictionary = _delivery_destination_surface_hit(screen_position)
	if hit.is_empty():
		return false
	var point_value: Variant = hit.get("point", null)
	if not (point_value is Vector3) or not (point_value as Vector3).is_finite():
		return false
	delivery_destination_placement_position = point_value as Vector3
	_update_delivery_destination_preview()
	return true


func _confirm_delivery_destination_placement() -> void:
	if not delivery_destination_placement_active or delivery_destination_container == null:
		return
	var group: Dictionary = _delivery_destination_group_by_id(delivery_destination_placement_group_id)
	if group.is_empty():
		_cancel_delivery_destination_placement("Delivery destination group is no longer available.", false)
		return
	var next_id: int = int(group.get("destination_counter", 0)) + 1
	group["destination_counter"] = next_id
	var destination: TrainingItemDeliveryDestination3D = TrainingItemDeliveryDestination3D.new()
	destination.name = "DeliveryGroup%02dDestination%03d" % [int(group["group_id"]), next_id]
	delivery_destination_container.add_child(destination)
	destination.configure_destination(
		int(group["group_id"]), next_id,
		float(group.get("radius_m", DELIVERY_DESTINATION_DEFAULT_RADIUS_M)),
		float(group.get("height_m", DELIVERY_DESTINATION_DEFAULT_HEIGHT_M)),
		Transform3D(Basis.IDENTITY, delivery_destination_placement_position),
		group.get("color", Color("54e6b1"))
	)
	var destinations: Array = group.get("destinations", [])
	destinations.append(destination)
	group["destinations"] = destinations
	_register_delivery_destination(destination, group)
	_cancel_delivery_destination_placement("", false)
	_rebuild_delivery_destination_group_rows()
	_restart_limb_groups_for_delivery_change("Delivery destination added; limb episodes restarted.")
	status_label.text = "Placed destination %d in %s." % [next_id, str(group.get("name", "delivery group"))]


func _register_delivery_destination(destination: TrainingItemDeliveryDestination3D, group: Dictionary) -> void:
	if not is_instance_valid(destination):
		return
	training_entity_spatial_hash.register_entity(
		destination.spatial_key(), destination,
		TrainingItemDeliveryDestination3D.ENTITY_KIND,
		destination.get_instance_id(),
		_delivery_destination_metadata(group, destination)
	)


func _unregister_delivery_destination(destination: TrainingItemDeliveryDestination3D) -> void:
	if destination == null:
		return
	training_entity_spatial_hash.clear_query_cache(destination.spatial_key())
	training_entity_spatial_hash.unregister_entity(destination.spatial_key())


func _delivery_destination_metadata(group: Dictionary, destination: TrainingItemDeliveryDestination3D) -> Dictionary:
	return {
		"stable_id": destination.stable_id(),
		"target_kind": TrainingItemDeliveryDestination3D.TARGET_KIND,
		"task_role": "delivery_destination",
		"destination_group_id": int(group.get("group_id", 0)),
		"destination_id": destination.destination_id,
		"accept_all_item_types": RLTrainingMath.bool_or(
			group.get("accept_all_item_types", false),
			false
		),
		"accepted_item_types": _delivery_item_types_from_variant(
			group.get("accepted_item_types", PackedStringArray())
		),
		"radius_m": float(group.get("radius_m", 1.25)),
		"height_m": float(group.get("height_m", 1.25)),
		"approach_reward_scale": float(group.get("approach_reward_scale", 1.0)),
		"completion_reward_scale": float(group.get("completion_reward_scale", 1.0)),
	}


func _held_training_item_for_limb(body: FourLimbPhysicalBody3D, assigned_item: TrainingItem3D) -> TrainingItem3D:
	if not is_instance_valid(body):
		return null
	if is_instance_valid(assigned_item) and body.holds_instance_id(assigned_item.get_instance_id()):
		return assigned_item
	for item: TrainingItem3D in training_items:
		if is_instance_valid(item) and body.holds_instance_id(item.get_instance_id()):
			return item
	return null


func _delivery_destination_for_limb(
	body: FourLimbPhysicalBody3D,
	assigned_item: TrainingItem3D,
	group_id: int = -1
) -> Dictionary:
	var limb_group: Dictionary = limb_training.group_by_id(group_id)
	if not _limb_group_uses_delivery_task(limb_group):
		return {}

	# A delivery lesson is a two-phase task. Before grip, make the assigned compatible cargo the
	# generic task target so the existing target-progress/search features can teach approach rather
	# than continuing to point at the unrelated room waypoint. Once cargo is actually held, the
	# generic target switches to the nearest compatible destination below. The dedicated pickup
	# observation remains present in both phases, so no policy-input/schema change is required.
	var held_item: TrainingItem3D = _held_training_item_for_limb(body, assigned_item)
	if not is_instance_valid(held_item):
		if is_instance_valid(assigned_item) and _any_delivery_group_accepts_item(assigned_item):
			var pickup_navigation_position: Vector3 = assigned_item.global_position
			var pickup_item_velocity: Vector3 = assigned_item.task_velocity_world()
			if is_instance_valid(body):
				# Target-progress is a chassis/navigation signal. Keep its Y at the current core height
				# while approaching floor cargo so the worker is not paid to collapse its torso down to
				# the item's center. The dedicated pickup-item vector still exposes the full 3D reach.
				pickup_navigation_position.y = body.core_transform().origin.y
			return {
				"task_active": true,
				"phase": "pickup",
				"pickup_target_position_world": pickup_navigation_position,
				"pickup_target_velocity_world": Vector3(
					pickup_item_velocity.x,
					0.0,
					pickup_item_velocity.z
				),
				"pickup_target_radius_m": maxf(assigned_item.collision_radius_m() + 0.75, 0.75),
				"item_accepted": true,
			}
		return {}

	var best_match: Dictionary = _best_delivery_destination_for_item(held_item)
	var best_destination: TrainingItemDeliveryDestination3D = best_match.get("destination") as TrainingItemDeliveryDestination3D
	var best_destination_group: Dictionary = best_match.get("group", {})
	if not is_instance_valid(best_destination) or best_destination_group.is_empty():
		return {}
	var delivery_navigation_position: Vector3 = best_destination.target_position_world()
	if is_instance_valid(body) and body.definition != null:
		var destination_up: Vector3 = best_destination.global_basis.y.normalized()
		if destination_up.length_squared() <= 0.000001:
			destination_up = Vector3.UP
		delivery_navigation_position = (
			best_destination.global_position
			+ destination_up * body.definition.preferred_core_height()
		)
	return {
		"task_active": true,
		"phase": "delivery",
		"available": true,
		"group_id": int(best_destination_group.get("group_id", 0)),
		"stable_id": best_destination.stable_id(),
		"position_world": delivery_navigation_position,
		"radius_m": best_destination.radius_m,
		"distance_m": maxf(RLTrainingMath.finite_float_or(best_match.get("distance_m", 0.0), 0.0), 0.0),
		"held_item": held_item,
		"item_accepted": true,
		"item_inside": bool(best_match.get("item_inside", false)),
		"approach_reward_scale": maxf(float(best_destination_group.get("approach_reward_scale", 1.0)), 0.0),
		"completion_reward_scale": maxf(float(best_destination_group.get("completion_reward_scale", 1.0)), 0.0),
		"target_kind": TrainingItemDeliveryDestination3D.TARGET_KIND,
	}


func _best_delivery_destination_for_item(item: TrainingItem3D) -> Dictionary:
	if not is_instance_valid(item):
		return {}
	var best_destination: TrainingItemDeliveryDestination3D = null
	var best_destination_group: Dictionary = {}
	var best_distance: float = INF
	var best_contains_item: bool = false
	for destination_group: Dictionary in delivery_destination_groups:
		if not _delivery_group_accepts_item(destination_group, item):
			continue
		for destination: TrainingItemDeliveryDestination3D in _valid_delivery_destinations(destination_group):
			var contains_item: bool = destination.contains_item(item)
			var distance_m: float = destination.distance_to_item(item)
			var should_replace: bool = false
			if contains_item != best_contains_item:
				should_replace = contains_item
			elif distance_m < best_distance:
				should_replace = true
			elif is_equal_approx(distance_m, best_distance):
				should_replace = destination.stable_id() < (best_destination.stable_id() if is_instance_valid(best_destination) else "~")
			if should_replace:
				best_contains_item = contains_item
				best_distance = distance_m
				best_destination = destination
				best_destination_group = destination_group
	if not is_instance_valid(best_destination):
		return {}
	return {
		"destination": best_destination,
		"group": best_destination_group,
		"distance_m": best_distance,
		"item_inside": best_contains_item,
	}


func _delivery_destination_environment_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for group: Dictionary in delivery_destination_groups:
		var destination_records: Array[Dictionary] = []
		for destination: TrainingItemDeliveryDestination3D in _valid_delivery_destinations(group):
			destination_records.append(destination.environment_record())
		var group_color: Color = group.get("color", Color("54e6b1"))
		records.append({
			"group_id": int(group.get("group_id", 0)),
			"name": str(group.get("name", "Delivery group")),
			"color": group_color.to_html(),
			"accept_all_item_types": RLTrainingMath.bool_or(
			group.get("accept_all_item_types", false),
			false
		),
			"accepted_item_types": Array(_delivery_item_types_from_variant(
				group.get("accepted_item_types", PackedStringArray())
			)),
			"radius_m": float(group.get("radius_m", 1.25)),
			"height_m": float(group.get("height_m", 1.25)),
			"approach_reward_scale": float(group.get("approach_reward_scale", 1.0)),
			"completion_reward_scale": float(group.get("completion_reward_scale", 1.0)),
			"destinations": destination_records,
		})
	return records


func _replace_delivery_destinations_from_records(records: Array) -> void:
	if delivery_destination_placement_active:
		_cancel_delivery_destination_placement("", false)
	for group: Dictionary in delivery_destination_groups:
		for destination: TrainingItemDeliveryDestination3D in _valid_delivery_destinations(group):
			_unregister_delivery_destination(destination)
			if destination.get_parent() != null:
				destination.get_parent().remove_child(destination)
			destination.queue_free()
	delivery_destination_groups.clear()
	delivery_destination_groups_by_id.clear()
	delivery_destination_group_counter = 0
	if delivery_destination_container == null:
		_rebuild_delivery_destination_group_rows()
		return
	var restored_group_ids: Dictionary[int, bool] = {}
	for value: Variant in records:
		if not (value is Dictionary):
			continue
		var record: Dictionary = value as Dictionary
		var group_id: int = maxi(RLTrainingMath.finite_int_or(record.get("group_id", delivery_destination_group_counter + 1), delivery_destination_group_counter + 1), 1)
		while restored_group_ids.has(group_id):
			group_id += 1
		restored_group_ids[group_id] = true
		delivery_destination_group_counter = maxi(delivery_destination_group_counter, group_id)
		var accepted: PackedStringArray = _delivery_item_types_from_variant(
			record.get("accepted_item_types", [])
		)
		if accepted.is_empty():
			accepted.append(TRAINING_ITEM_DEFAULT_TYPE)
		var fallback_color: Color = DELIVERY_DESTINATION_COLORS[(group_id - 1) % DELIVERY_DESTINATION_COLORS.size()]
		var color_text: String = str(record.get("color", "")).strip_edges()
		var restored_color: Color = fallback_color
		if not color_text.is_empty() and Color.html_is_valid(color_text):
			restored_color = Color(color_text)
		var restored_name: String = str(record.get("name", "")).strip_edges()
		if restored_name.is_empty():
			restored_name = "Delivery group %d" % group_id
		var group: Dictionary = {
			"group_id": group_id,
			"name": restored_name,
			"color": restored_color,
			"accept_all_item_types": RLTrainingMath.bool_or(
				record.get("accept_all_item_types", false),
				false
			),
			"accepted_item_types": accepted,
			"radius_m": maxf(RLTrainingMath.finite_float_or(record.get("radius_m", 1.25), 1.25), 0.10),
			"height_m": maxf(RLTrainingMath.finite_float_or(record.get("height_m", 1.25), 1.25), 0.10),
			"approach_reward_scale": maxf(RLTrainingMath.finite_float_or(record.get("approach_reward_scale", 1.0), 1.0), 0.0),
			"completion_reward_scale": maxf(RLTrainingMath.finite_float_or(record.get("completion_reward_scale", 1.0), 1.0), 0.0),
			"destination_counter": 0,
			"destinations": [],
		}
		var destinations_value: Variant = record.get("destinations", [])
		if destinations_value is Array:
			var restored_destination_ids: Dictionary[int, bool] = {}
			for destination_value: Variant in destinations_value:
				if not (destination_value is Dictionary):
					continue
				var destination_record: Dictionary = destination_value as Dictionary
				var destination_id: int = maxi(RLTrainingMath.finite_int_or(destination_record.get("destination_id", int(group["destination_counter"]) + 1), int(group["destination_counter"]) + 1), 1)
				while restored_destination_ids.has(destination_id):
					destination_id += 1
				restored_destination_ids[destination_id] = true
				group["destination_counter"] = maxi(int(group["destination_counter"]), destination_id)
				var position: Vector3 = _vector3_from_number_array(destination_record.get("position_m", []), Vector3.ZERO)
				var rotation: Vector3 = _vector3_from_number_array(destination_record.get("rotation_degrees", []), Vector3.ZERO)
				var destination: TrainingItemDeliveryDestination3D = TrainingItemDeliveryDestination3D.new()
				destination.name = "DeliveryGroup%02dDestination%03d" % [group_id, destination_id]
				delivery_destination_container.add_child(destination)
				destination.configure_destination(
					group_id, destination_id,
					float(group["radius_m"]), float(group["height_m"]),
					Transform3D(Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z))), position),
					group["color"]
				)
				(group["destinations"] as Array).append(destination)
				_register_delivery_destination(destination, group)
		delivery_destination_groups.append(group)
		delivery_destination_groups_by_id[group_id] = group
	_rebuild_delivery_destination_group_rows()


func _reset_training_item_editor_to_definition(source: TrainingItemDefinition) -> void:
	if source == null:
		return
	var safe: TrainingItemDefinition = source.sanitized_copy()
	if safe == null:
		return
	training_item_shape_kind = safe.shape_kind
	training_item_dimensions = safe.dimensions.duplicate(true)
	training_item_mass_kg = safe.mass_kg
	training_item_reward_value = safe.reward_value
	training_item_type = safe.item_type
	training_item_pitch_degrees = 0.0
	training_item_yaw_degrees = 0.0
	training_item_roll_degrees = 0.0
	training_item_position_x_m = 0.0
	training_item_position_y_m = DroneTrainingObstacleShape.vertical_half_extent(
		safe.shape_kind,
		safe.dimensions
	)
	training_item_position_z_m = 0.0


func _training_item_definition_from_editor(
	base_definition: TrainingItemDefinition
) -> TrainingItemDefinition:
	var source: TrainingItemDefinition = (
		base_definition if base_definition != null else TRAINING_ITEM_DEFAULT_DEFINITION
	)
	if source == null:
		return null
	var result: TrainingItemDefinition = source.sanitized_copy()
	if result == null:
		return null
	result.shape_kind = training_item_shape_kind
	result.dimensions = _current_training_item_dimensions()
	result.mass_kg = training_item_mass_kg
	result.reward_value = training_item_reward_value
	result.item_type = training_item_type
	result.sanitize()
	return result


func _training_item_base_definition_for_item(item: TrainingItem3D) -> TrainingItemDefinition:
	if not is_instance_valid(item):
		return TRAINING_ITEM_DEFAULT_DEFINITION
	if (
		not item.definition_resource_path.is_empty()
		and ResourceLoader.exists(item.definition_resource_path)
	):
		var loaded: Resource = load(item.definition_resource_path)
		if loaded is TrainingItemDefinition:
			return loaded as TrainingItemDefinition
	if item.item_definition != null:
		return item.item_definition
	return TRAINING_ITEM_DEFAULT_DEFINITION


func _training_item_definition_from_record(record: Dictionary) -> TrainingItemDefinition:
	var path: String = str(record.get("definition_resource_path", "")).strip_edges()
	# Legacy map records predate item archetype paths and migrate to the generic cargo preset. Once
	# a record names a definition explicitly, however, fail closed if that resource is missing or is
	# the wrong type. Silently replacing a custom creator item with generic cargo would change the
	# authored task behind the user's back.
	if path.is_empty():
		return TRAINING_ITEM_DEFAULT_DEFINITION
	if not ResourceLoader.exists(path):
		return null
	var loaded: Resource = load(path)
	if loaded is TrainingItemDefinition:
		return loaded as TrainingItemDefinition
	return null


func _set_training_item_shape(index: int) -> void:
	training_item_shape_kind = clampi(index, 0, DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1)
	_rebuild_training_item_dimension_inputs()
	_update_training_item_preview()


func _rebuild_training_item_dimension_inputs() -> void:
	if training_item_dimensions_body == null:
		return
	for child: Node in training_item_dimensions_body.get_children():
		training_item_dimensions_body.remove_child(child)
		child.queue_free()
	training_item_dimension_inputs.clear()
	training_item_dimension_link_buttons.clear()
	# Shape normalization can couple dimensions (capsule total height must be at least 2r). Update
	# the authored values before building the SpinBoxes so the UI can never display a size that
	# differs from the collision/mesh that will actually be spawned.
	training_item_dimensions.merge(
		DroneTrainingObstacleShape.normalized_dimensions(
			training_item_shape_kind,
			training_item_dimensions
		),
		true
	)
	var definitions: Array[Dictionary] = DroneTrainingObstacleShape.dimension_definitions(training_item_shape_kind)
	var links_available: bool = definitions.size() > 1
	for definition: Dictionary in definitions:
		var key: String = str(definition.get("key", ""))
		if not training_item_dimensions.has(key):
			training_item_dimensions[key] = float(definition.get("default", 1.0))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		training_item_dimensions_body.add_child(row)
		var label: Label = Label.new()
		label.text = str(definition.get("label", key.capitalize()))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = "Training item dimension\n\nThis is the real collision/visual size. Link dimensions with the chain buttons when you want equal values."
		row.add_child(label)
		var link_button: Button = Button.new()
		link_button.text = "⛓"
		link_button.toggle_mode = true
		link_button.custom_minimum_size = Vector2(34.0, 30.0)
		link_button.disabled = not links_available
		link_button.tooltip_text = "Link this dimension\n\nChanging any linked value copies it to all other linked dimensions for this shape."
		link_button.button_pressed = _is_training_item_dimension_linked(key)
		link_button.toggled.connect(_set_training_item_dimension_linked.bind(key))
		row.add_child(link_button)
		training_item_dimension_link_buttons[key] = link_button
		var input: SpinBox = SpinBox.new()
		input.custom_minimum_size.x = 118.0
		input.min_value = DroneTrainingObstacleShape.MINIMUM_DIMENSION_M
		input.max_value = 1000000.0
		input.step = float(definition.get("step", 0.1))
		DroneTrainingRoomPresentation.configure_spinbox_arrow_speed(input)
		input.value = float(training_item_dimensions[key])
		input.suffix = " m"
		input.tooltip_text = label.tooltip_text
		input.value_changed.connect(_set_training_item_dimension.bind(key))
		row.add_child(input)
		_configure_unbounded_spinbox(input, false)
		training_item_dimension_inputs[key] = input
	_refresh_training_item_dimension_link_buttons()


func _set_training_item_dimension(value: float, dimension_key: String) -> void:
	if training_item_dimension_sync_in_progress:
		return
	var safe_value: float = maxf(absf(value), DroneTrainingObstacleShape.MINIMUM_DIMENSION_M)
	training_item_dimensions[dimension_key] = safe_value
	if _is_training_item_dimension_linked(dimension_key):
		for linked_key: String in _training_item_linked_dimension_keys():
			if linked_key != dimension_key and training_item_dimension_inputs.has(linked_key):
				training_item_dimensions[linked_key] = safe_value
	training_item_dimensions.merge(
		DroneTrainingObstacleShape.normalized_dimensions(training_item_shape_kind, training_item_dimensions),
		true
	)
	training_item_dimension_sync_in_progress = true
	for key: Variant in training_item_dimension_inputs:
		var input: SpinBox = training_item_dimension_inputs[key] as SpinBox
		if input != null:
			input.set_value_no_signal(float(training_item_dimensions.get(key, safe_value)))
	training_item_dimension_sync_in_progress = false
	_update_training_item_preview()


func _training_item_linked_dimension_state() -> Dictionary:
	var stored: Variant = training_item_linked_dimensions_by_shape.get(training_item_shape_kind, {})
	if stored is Dictionary:
		return stored as Dictionary
	var created: Dictionary = {}
	training_item_linked_dimensions_by_shape[training_item_shape_kind] = created
	return created


func _training_item_linked_dimension_keys() -> Array[String]:
	var result: Array[String] = []
	var state: Dictionary = _training_item_linked_dimension_state()
	for key: Variant in state:
		if bool(state.get(key, false)):
			result.append(str(key))
	return result


func _is_training_item_dimension_linked(dimension_key: String) -> bool:
	return bool(_training_item_linked_dimension_state().get(dimension_key, false))


func _set_training_item_dimension_linked(enabled: bool, dimension_key: String) -> void:
	var state: Dictionary = _training_item_linked_dimension_state()
	if enabled:
		state[dimension_key] = true
	else:
		state.erase(dimension_key)
	training_item_linked_dimensions_by_shape[training_item_shape_kind] = state
	_refresh_training_item_dimension_link_buttons()


func _refresh_training_item_dimension_link_buttons() -> void:
	for key: Variant in training_item_dimension_link_buttons:
		var button: Button = training_item_dimension_link_buttons[key] as Button
		if button == null:
			continue
		var linked: bool = _is_training_item_dimension_linked(str(key))
		button.set_pressed_no_signal(linked)
		var style: StyleBox = DroneTrainingRoomPresentation.scanner_button_style(linked)
		for state_name: String in ["normal", "pressed", "hover", "hover_pressed"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_color_override("font_color", Color("ffad42") if linked else Color("8de1ff"))


func _current_training_item_dimensions() -> Dictionary:
	return DroneTrainingObstacleShape.normalized_dimensions(
		training_item_shape_kind,
		training_item_dimensions
	)


func _training_item_editor_transform() -> Transform3D:
	var rotation_radians: Vector3 = Vector3(
		deg_to_rad(training_item_pitch_degrees),
		deg_to_rad(training_item_yaw_degrees),
		deg_to_rad(training_item_roll_degrees)
	)
	return Transform3D(
		Basis.from_euler(rotation_radians),
		Vector3(training_item_position_x_m, training_item_position_y_m, training_item_position_z_m)
	)


func _toggle_training_item_placement() -> void:
	if delivery_destination_placement_active:
		_cancel_delivery_destination_placement("", false)
	if turret_placement_active:
		_cancel_turret_placement("")
	if wall_placement_active:
		_cancel_wall_placement("")
	if wall_drag_active:
		_finish_wall_drag(true)
	if training_item_placement_active:
		_cancel_training_item_placement("Training item placement finished.", true)
		return
	training_item_placement_active = true
	_ensure_training_item_preview()
	_update_training_item_preview()
	if is_instance_valid(training_item_preview):
		training_item_preview.visible = true
	if training_item_place_button != null:
		training_item_place_button.text = "FINISH PLACEMENT"
		training_item_place_button.add_theme_stylebox_override(
			"normal", DroneTrainingRoomPresentation.scanner_button_style(true)
		)
	_refresh_training_item_status()
	status_label.text = "Training item placement armed. Left-click repeatedly to spawn items; right-click or Escape finishes the session."


func _cancel_training_item_placement(message: String, restart_if_changed: bool) -> void:
	var had_changes: bool = bool(get_meta("training_item_placement_changed", false))
	remove_meta("training_item_placement_changed")
	training_item_placement_active = false
	if is_instance_valid(training_item_preview):
		training_item_preview.visible = false
	if training_item_place_button != null:
		training_item_place_button.text = "SPAWN WITH MOUSE"
		training_item_place_button.add_theme_stylebox_override(
			"normal", DroneTrainingRoomPresentation.scanner_button_style(false)
		)
	_refresh_training_item_status()
	if restart_if_changed and had_changes:
		_restart_for_configuration_change(
			"Training item layout changed; episodes restarted.",
			true,
			true,
			true
		)
	if status_label != null and not message.is_empty():
		status_label.text = message


func _ensure_training_item_preview() -> void:
	if is_instance_valid(training_item_preview):
		return
	if training_item_container == null:
		return
	training_item_preview = MeshInstance3D.new()
	training_item_preview.name = "TrainingItemPlacementPreview"
	training_item_preview.material_override = DroneTrainingRoomPresentation.material(
		TRAINING_ITEM_PREVIEW_COLOR,
		true
	)
	training_item_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	training_item_preview.visible = false
	training_item_container.add_child(training_item_preview)


func _update_training_item_preview() -> void:
	if not training_item_placement_active:
		return
	_ensure_training_item_preview()
	if not is_instance_valid(training_item_preview):
		return
	training_item_preview.mesh = DroneTrainingObstacleShape.visual_mesh(
		training_item_shape_kind,
		_current_training_item_dimensions()
	)
	training_item_preview.global_transform = _training_item_editor_transform()
	training_item_preview.visible = true


func _training_item_surface_hit(screen_position: Vector2) -> Dictionary:
	return DroneTrainingEditorRaycast.authored_surface_hit(
		_interaction_camera(),
		get_world_3d(),
		screen_position,
		EDITOR_PICK_RAY_LENGTH_M,
		ARENA_COLLISION_LAYER,
		TRAINING_ITEM_PLACEMENT_MAXIMUM_RAY_RETRIES,
		TRAINING_ITEM_MINIMUM_SURFACE_NORMAL_Y,
		true
	)

func _update_training_item_position_from_screen(screen_position: Vector2) -> bool:
	if not training_item_placement_active:
		return false
	var hit: Dictionary = _training_item_surface_hit(screen_position)
	if hit.is_empty():
		return false
	var point: Vector3 = hit.get("point", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if not normal.is_finite() or normal.length_squared() <= 0.000001:
		return false
	normal = normal.normalized()
	var editor_transform: Transform3D = _training_item_editor_transform()
	var support_extent: float = DroneTrainingObstacleShape.support_extent_world(
		training_item_shape_kind,
		_current_training_item_dimensions(),
		editor_transform.basis,
		normal
	)
	var resting_center: Vector3 = point + normal * support_extent
	training_item_position_x_m = resting_center.x
	training_item_position_y_m = resting_center.y
	training_item_position_z_m = resting_center.z
	_sync_training_item_position_inputs()
	_update_training_item_preview()
	return true


func _confirm_training_item_placement() -> void:
	if not training_item_placement_active:
		return
	# Match automatic obstacle placement: every authored environment mutation is an episode
	# boundary, but the placement tool itself remains armed for the next click. This prevents a
	# single on-policy rollout from spanning two different item layouts.
	var item: TrainingItem3D = _spawn_training_item(true)
	if item == null:
		return
	_update_training_item_preview()
	status_label.text = "Training item %d placed. Placement remains armed; left-click again or right-click/Escape to finish." % item.training_item_id


func _spawn_training_item(restart_episode: bool) -> TrainingItem3D:
	if training_item_container == null:
		return null
	training_item_counter += 1
	var item: TrainingItem3D = TrainingItem3D.new()
	item.name = "TrainingItem%03d" % training_item_counter
	item.set_meta("training_authored_item", true)
	training_item_container.add_child(item)
	var item_definition: TrainingItemDefinition = _training_item_definition_from_editor(
		TRAINING_ITEM_DEFAULT_DEFINITION
	)
	if item_definition == null or not item.configure_from_definition(
		training_item_counter,
		item_definition,
		_training_item_editor_transform(),
		true,
		training_item_type,
		TRAINING_ITEM_DEFAULT_DEFINITION.resource_path
	):
		item.queue_free()
		return null
	training_items.append(item)
	item.set_simulation_active(_training_items_should_simulate())
	_register_training_item(item)
	_select_training_item(item)
	_refresh_training_item_status()
	if restart_episode:
		_restart_for_configuration_change(
			"Training item added; episodes restarted.",
			true,
			true,
			true
		)
	return item


func _register_training_item(item: TrainingItem3D) -> void:
	if not is_instance_valid(item):
		return
	training_entity_spatial_hash.register_entity(
		item.spatial_key(),
		item,
		TrainingItem3D.ENTITY_KIND,
		item.training_item_id,
		item.discovery_metadata()
	)


func _unregister_training_item(item: TrainingItem3D) -> void:
	if item == null:
		return
	training_entity_spatial_hash.clear_query_cache(item.spatial_key())
	training_entity_spatial_hash.unregister_entity(item.spatial_key())


func _refresh_training_item_spatial_metadata(item: TrainingItem3D) -> void:
	if not is_instance_valid(item):
		return
	training_entity_spatial_hash.set_entity_metadata(item.spatial_key(), item.discovery_metadata())
	training_entity_spatial_hash.update_entity(item.spatial_key())


func _training_items_should_simulate() -> bool:
	if _has_active_drone_group():
		return true
	for group: Dictionary in limb_training.groups:
		if bool(group.get("active", false)):
			return true
	for group: Dictionary in turret_training.groups:
		if bool(group.get("active", false)):
			return true
	return false


func _set_training_items_simulation_active(active: bool) -> void:
	_prune_invalid_training_items()
	for item: TrainingItem3D in training_items:
		# A shared authored item normally follows the room-wide simulation state. The one
		# exception is an item physically held by a paused limb group: letting it keep falling
		# while the holder is frozen would stretch/break the generic grip before resume.
		var item_active: bool = active and not _training_item_is_held_by_paused_limb(item)
		item.set_simulation_active(item_active)


func _training_item_is_held_by_paused_limb(item: TrainingItem3D) -> bool:
	if not is_instance_valid(item):
		return false
	var item_instance_id: int = int(item.get_instance_id())
	# Drone-mounted generic limbs share the same physical grip implementation. Preserve a held
	# cargo object's simulation state while that drone group is paused, just as we already do for
	# four-limb workers, so pausing cannot stretch/break an articulated attachment's grip.
	for group: Dictionary in worker_groups:
		if bool(group.get("active", false)):
			continue
		for trial_value: Variant in group.get("trials", []):
			if not (trial_value is Dictionary):
				continue
			var trial: Dictionary = trial_value
			var drone: ServerDrone = trial.get("drone") as ServerDrone
			if is_instance_valid(drone) and drone.holds_instance_id(item_instance_id):
				return true
	for group: Dictionary in limb_training.groups:
		if bool(group.get("active", false)):
			continue
		for worker_value: Variant in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker: Dictionary = worker_value
			var body: FourLimbPhysicalBody3D = worker.get("body") as FourLimbPhysicalBody3D
			if (
				is_instance_valid(body)
				and body.holds_instance_id(item_instance_id)
			):
				return true
	return false


func _recover_lost_training_items(prune_first: bool = true) -> int:
	if prune_first:
		_prune_invalid_training_items()
	var recovered_count: int = 0
	for item: TrainingItem3D in training_items:
		if not item.needs_recovery(
			ARENA_SIZE,
			TRAINING_ITEM_RECOVERY_MARGIN_M,
			TRAINING_ITEM_RECOVERY_MINIMUM_Y_M,
			TRAINING_ITEM_RECOVERY_MAXIMUM_Y_M
		):
			continue
		item.reset_to_spawn()
		_refresh_training_item_spatial_metadata(item)
		recovered_count += 1
	if recovered_count > 0:
		# Recovery is a real world-state discontinuity, not cosmetic housekeeping. Retire every
		# affected open trajectory before any worker observes the teleported task object.
		_restart_for_configuration_change(
			"Recovered %d lost training item%s to authored spawn; episodes restarted." % [
				recovered_count,
				"" if recovered_count == 1 else "s",
			],
			true,
			true,
			true
		)
	return recovered_count


func _refresh_training_item_spatial_positions(prune_first: bool = true) -> void:
	if prune_first:
		_prune_invalid_training_items()
	for item: TrainingItem3D in training_items:
		training_entity_spatial_hash.update_entity(item.spatial_key())


func _training_item_candidate_for_limb(
	origin_world: Vector3,
	excluded_item_ids: Array[int],
	group_id: int = -1
) -> TrainingItem3D:
	var limb_group: Dictionary = limb_training.group_by_id(group_id)
	var require_delivery_compatible: bool = (
		_limb_group_uses_delivery_task(limb_group)
		and _has_active_delivery_destinations()
	)
	var best_item: TrainingItem3D = null
	var best_distance_squared: float = INF
	for entity_key: StringName in training_entity_spatial_hash.readonly_keys_for_kind(TrainingItem3D.ENTITY_KIND):
		var record: Dictionary = training_entity_spatial_hash.get_record(entity_key)
		var item: TrainingItem3D = record.get("body") as TrainingItem3D
		if not is_instance_valid(item) or excluded_item_ids.has(item.training_item_id):
			continue
		if require_delivery_compatible:
			if not _any_delivery_group_accepts_item(item):
				continue
			# Cargo already resting inside any accepting destination is already delivered for the
			# generic "bring to any accepting bay" lesson. Do not assign it as fresh pickup cargo in
			# the next episode; this prevents grab-inside / step-out / step-back reward loops.
			if _item_is_inside_any_accepting_destination(item):
				continue
		var distance_squared: float = origin_world.distance_squared_to(item.global_position)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_item = item
	return best_item


func _any_delivery_group_accepts_item(item: TrainingItem3D) -> bool:
	if not is_instance_valid(item):
		return false
	for group: Dictionary in delivery_destination_groups:
		if not _valid_delivery_destinations(group).is_empty() and _delivery_group_accepts_item(group, item):
			return true
	return false


func _item_is_inside_any_accepting_destination(item: TrainingItem3D) -> bool:
	if not is_instance_valid(item):
		return false
	for group: Dictionary in delivery_destination_groups:
		if not _delivery_group_accepts_item(group, item):
			continue
		for destination: TrainingItemDeliveryDestination3D in _valid_delivery_destinations(group):
			if destination.contains_item(item):
				return true
	return false


func _has_active_delivery_destinations() -> bool:
	for group: Dictionary in delivery_destination_groups:
		if not _valid_delivery_destinations(group).is_empty():
			return true
	return false


func _pick_training_item_from_screen(screen_position: Vector2) -> TrainingItem3D:
	return DroneTrainingEditorRaycast.pick_authored_training_item(
		_interaction_camera(),
		get_world_3d(),
		screen_position,
		EDITOR_PICK_RAY_LENGTH_M,
		ARENA_COLLISION_LAYER,
		TRAINING_ITEM_PLACEMENT_MAXIMUM_RAY_RETRIES
	)

func _select_training_item(item: TrainingItem3D) -> void:
	if is_instance_valid(selected_training_item) and selected_training_item != item:
		selected_training_item.set_selected(false)
	selected_training_item = item if is_instance_valid(item) else null
	if is_instance_valid(selected_training_item):
		selected_training_item.set_selected(true)
		_sync_training_item_editor_from_selected()
	_refresh_training_item_status()


func _sync_training_item_editor_from_selected() -> void:
	if not is_instance_valid(selected_training_item):
		return
	training_item_shape_kind = selected_training_item.shape_kind
	training_item_dimensions.merge(selected_training_item.dimensions, true)
	training_item_mass_kg = selected_training_item.mass
	training_item_reward_value = selected_training_item.reward_value
	training_item_type = selected_training_item.item_type
	if training_item_type_input != null:
		training_item_type_input.text = training_item_type
	# The editor authors the reset/map spawn, not the item's transient rigid-body pose. Reading
	# global_position here meant selecting an item after a worker dragged it and then changing
	# only Reward value could silently redefine its authored spawn.
	var authored_transform: Transform3D = selected_training_item.spawn_transform_world
	var authored_rotation_degrees: Vector3 = authored_transform.basis.get_euler() * (180.0 / PI)
	training_item_position_x_m = authored_transform.origin.x
	training_item_position_y_m = authored_transform.origin.y
	training_item_position_z_m = authored_transform.origin.z
	training_item_pitch_degrees = authored_rotation_degrees.x
	training_item_yaw_degrees = authored_rotation_degrees.y
	training_item_roll_degrees = authored_rotation_degrees.z
	if training_item_shape_picker != null:
		training_item_shape_picker.select(training_item_shape_kind)
	_rebuild_training_item_dimension_inputs()
	if training_item_mass_input != null:
		training_item_mass_input.set_value_no_signal(training_item_mass_kg)
	if training_item_reward_input != null:
		training_item_reward_input.set_value_no_signal(training_item_reward_value)
	_sync_training_item_position_inputs()
	if training_item_pitch_input != null:
		training_item_pitch_input.set_value_no_signal(training_item_pitch_degrees)
	if training_item_yaw_input != null:
		training_item_yaw_input.set_value_no_signal(training_item_yaw_degrees)
	if training_item_roll_input != null:
		training_item_roll_input.set_value_no_signal(training_item_roll_degrees)


func _sync_training_item_position_inputs() -> void:
	if training_item_position_x_input != null:
		training_item_position_x_input.set_value_no_signal(training_item_position_x_m)
	if training_item_position_y_input != null:
		training_item_position_y_input.set_value_no_signal(training_item_position_y_m)
	if training_item_position_z_input != null:
		training_item_position_z_input.set_value_no_signal(training_item_position_z_m)


func _apply_training_item_values_to_selected() -> void:
	if training_item_placement_active:
		_cancel_training_item_placement("", true)
	if not is_instance_valid(selected_training_item):
		status_label.text = "Select a training item in the arena before applying edits."
		_refresh_training_item_status()
		return
	var base_definition: TrainingItemDefinition = _training_item_base_definition_for_item(
		selected_training_item
	)
	var edited_definition: TrainingItemDefinition = _training_item_definition_from_editor(
		base_definition
	)
	if edited_definition == null or not selected_training_item.configure_from_definition(
		selected_training_item.training_item_id,
		edited_definition,
		_training_item_editor_transform(),
		true,
		training_item_type,
		MLBodyPartContract.resource_source_path(base_definition) if base_definition != null else ""
	):
		status_label.text = "Training item definition could not be applied."
		_refresh_training_item_status()
		return
	_refresh_training_item_spatial_metadata(selected_training_item)
	selected_training_item.set_selected(true)
	_restart_for_configuration_change(
		"Training item updated; episodes restarted.",
		true,
		true,
		true
	)
	_refresh_training_item_status()


func _delete_selected_training_item() -> void:
	if training_item_placement_active:
		_cancel_training_item_placement("", true)
	if not is_instance_valid(selected_training_item):
		status_label.text = "Select a training item before deleting it."
		return
	var item: TrainingItem3D = selected_training_item
	selected_training_item = null
	training_items.erase(item)
	_unregister_training_item(item)
	if item.get_parent() != null:
		item.get_parent().remove_child(item)
	item.queue_free()
	_refresh_training_item_status()
	_restart_for_configuration_change(
		"Training item deleted; episodes restarted.",
		true,
		true,
		true
	)


func _reset_all_training_items() -> void:
	_prune_invalid_training_items()
	if training_items.is_empty():
		status_label.text = "There are no training items to reset."
		return
	for item: TrainingItem3D in training_items:
		item.reset_to_spawn()
		_refresh_training_item_spatial_metadata(item)
	_refresh_training_item_status()
	_restart_for_configuration_change(
		"Training items reset to authored spawns; episodes restarted.",
		true,
		true,
		true
	)


func _clear_training_items() -> void:
	if training_item_placement_active:
		_cancel_training_item_placement("", false)
	_prune_invalid_training_items()
	if training_items.is_empty():
		status_label.text = "There are no training items to clear."
		return
	selected_training_item = null
	for item: TrainingItem3D in training_items:
		_unregister_training_item(item)
		if is_instance_valid(item):
			if item.get_parent() != null:
				item.get_parent().remove_child(item)
			item.queue_free()
	training_items.clear()
	_refresh_training_item_status()
	_restart_for_configuration_change(
		"All training items cleared; episodes restarted.",
		true,
		true,
		true
	)


func _prune_invalid_training_items() -> void:
	var valid_items: Array[TrainingItem3D] = []
	for item: TrainingItem3D in training_items:
		if is_instance_valid(item):
			valid_items.append(item)
	training_items = valid_items
	if not is_instance_valid(selected_training_item):
		selected_training_item = null


func _refresh_training_item_status() -> void:
	_prune_invalid_training_items()
	var has_selection: bool = is_instance_valid(selected_training_item)
	if training_item_apply_button != null:
		training_item_apply_button.disabled = not has_selection
	if training_item_delete_button != null:
		training_item_delete_button.disabled = not has_selection
	if training_item_status_label == null:
		return
	if training_item_placement_active:
		training_item_status_label.text = "%d item(s) · continuous placement armed · left-click adds another" % training_items.size()
	elif has_selection:
		training_item_status_label.text = "%d item(s) · item %d selected · type %s · %.2f kg · reward %.2f" % [
			training_items.size(),
			selected_training_item.training_item_id,
			selected_training_item.item_type,
			selected_training_item.mass,
			selected_training_item.reward_value,
		]
	else:
		training_item_status_label.text = "%d training item(s) · click an item to inspect/edit it" % training_items.size()


func _training_item_environment_records() -> Array[Dictionary]:
	_prune_invalid_training_items()
	var records: Array[Dictionary] = []
	for item: TrainingItem3D in training_items:
		records.append(item.environment_record())
	return records


func _replace_training_items_from_records(records: Array) -> void:
	if training_item_placement_active:
		_cancel_training_item_placement("", false)
	if training_item_container == null:
		return
	for item: TrainingItem3D in training_items:
		_unregister_training_item(item)
		if is_instance_valid(item):
			if item.get_parent() != null:
				item.get_parent().remove_child(item)
			item.queue_free()
	training_items.clear()
	selected_training_item = null
	training_item_counter = 0
	var restored_item_ids: Dictionary[int, bool] = {}
	for value: Variant in records:
		if not (value is Dictionary):
			continue
		var record: Dictionary = value as Dictionary
		var item_id: int = maxi(
			RLTrainingMath.finite_int_or(
				record.get("item_id", training_item_counter + 1),
				training_item_counter + 1
			),
			1
		)
		# Stable ids are task addresses. Corrupt/hand-edited map files must not create two
		# different physical items with the same address, so remap duplicates monotonically.
		while restored_item_ids.has(item_id):
			item_id = maxi(training_item_counter + 1, item_id + 1)
		restored_item_ids[item_id] = true
		training_item_counter = maxi(training_item_counter, item_id)
		var base_definition: TrainingItemDefinition = _training_item_definition_from_record(record)
		if base_definition == null:
			continue
		var shape_kind: int = clampi(
			RLTrainingMath.finite_int_or(
				record.get("shape_kind", base_definition.shape_kind),
				base_definition.shape_kind
			),
			0,
			DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
		)
		var dimensions_value: Variant = record.get(
			"dimensions_m",
			base_definition.dimensions
		)
		var dimensions: Dictionary = (
			dimensions_value.duplicate(true)
			if dimensions_value is Dictionary
			else base_definition.dimensions.duplicate(true)
		)
		dimensions = DroneTrainingObstacleShape.normalized_dimensions(shape_kind, dimensions)
		var position: Vector3 = _vector3_from_number_array(record.get("position_m", []), Vector3.ZERO)
		var rotation: Vector3 = _vector3_from_number_array(record.get("rotation_degrees", []), Vector3.ZERO)
		var restored_definition: TrainingItemDefinition = base_definition.sanitized_copy()
		if restored_definition == null:
			continue
		restored_definition.shape_kind = shape_kind
		restored_definition.dimensions = dimensions
		restored_definition.mass_kg = maxf(
			RLTrainingMath.finite_float_or(record.get("mass", restored_definition.mass_kg), restored_definition.mass_kg),
			0.01
		)
		restored_definition.reward_value = maxf(
			RLTrainingMath.finite_float_or(record.get("reward_value", restored_definition.reward_value), restored_definition.reward_value),
			0.0
		)
		restored_definition.item_type = TrainingItem3D.normalized_item_type(
			str(record.get("item_type", restored_definition.item_type))
		)
		restored_definition.sanitize()
		var item: TrainingItem3D = TrainingItem3D.new()
		item.name = "TrainingItem%03d" % item_id
		item.set_meta("training_authored_item", true)
		training_item_container.add_child(item)
		if not item.configure_from_definition(
			item_id,
			restored_definition,
			Transform3D(Basis.from_euler(Vector3(deg_to_rad(rotation.x), deg_to_rad(rotation.y), deg_to_rad(rotation.z))), position),
			true,
			restored_definition.item_type,
			MLBodyPartContract.resource_source_path(base_definition)
		):
			item.queue_free()
			continue
		training_items.append(item)
		item.set_simulation_active(_training_items_should_simulate())
		_register_training_item(item)
	_refresh_training_item_status()


func _configure_unbounded_spinbox(input: SpinBox, allow_negative: bool) -> void:
	if input == null:
		return
	input.allow_greater = true
	input.allow_lesser = allow_negative


func _set_wall_shape(index: int) -> void:
	wall_shape_kind = clampi(
		index,
		0,
		DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
	)
	_rebuild_wall_dimension_inputs()
	_update_wall_preview()


func _rebuild_wall_dimension_inputs() -> void:
	if wall_dimensions_body == null:
		return
	for child in wall_dimensions_body.get_children():
		wall_dimensions_body.remove_child(child)
		child.queue_free()
	wall_dimension_inputs.clear()
	wall_dimension_link_buttons.clear()
	var definitions = DroneTrainingObstacleShape.dimension_definitions(
		wall_shape_kind
	)
	var links_available = definitions.size() > 1
	for definition in definitions:
		var key = str(definition.get("key", ""))
		if not wall_dimensions.has(key):
			wall_dimensions[key] = float(definition.get("default", 1.0))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		wall_dimensions_body.add_child(row)
		var label = Label.new()
		label.text = str(definition.get("label", key.capitalize()))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = (
			"Obstacle dimension\n\n"
			+ "Enter any positive physical size. There is no configured upper limit.\n"
			+ "Use the chain button to synchronize only the dimensions you choose."
		)
		row.add_child(label)
		var link_button = Button.new()
		link_button.text = "⛓"
		link_button.toggle_mode = true
		link_button.custom_minimum_size = Vector2(34.0, 30.0)
		link_button.disabled = not links_available
		link_button.tooltip_text = (
			"Link this dimension\n\n"
			+ "Enable the chain on two or more dimensions.\n"
			+ "Changing any linked value copies that value to the other linked dimensions.\n\n"
			+ "Unlinked dimensions remain independent."
		)
		link_button.button_pressed = _is_wall_dimension_linked(key)
		link_button.toggled.connect(_set_wall_dimension_linked.bind(key))
		row.add_child(link_button)
		wall_dimension_link_buttons[key] = link_button
		var input = SpinBox.new()
		input.custom_minimum_size.x = 118.0
		input.min_value = DroneTrainingObstacleShape.MINIMUM_DIMENSION_M
		input.max_value = 1000000.0
		input.step = float(definition.get("step", 0.1))
		DroneTrainingRoomPresentation.configure_spinbox_arrow_speed(input)
		input.value = float(wall_dimensions[key])
		input.suffix = " m"
		input.tooltip_text = label.tooltip_text
		input.value_changed.connect(_set_wall_dimension.bind(key))
		row.add_child(input)
		_configure_unbounded_spinbox(input, false)
		wall_dimension_inputs[key] = input
	_refresh_wall_dimension_link_buttons()


func _set_wall_dimension(value: float, dimension_key: String) -> void:
	if wall_dimension_sync_in_progress:
		return
	var safe_value = maxf(
		absf(value),
		DroneTrainingObstacleShape.MINIMUM_DIMENSION_M
	)
	wall_dimensions[dimension_key] = safe_value
	if _is_wall_dimension_linked(dimension_key):
		for linked_key in _wall_linked_dimension_keys():
			if linked_key == dimension_key:
				continue
			if wall_dimension_inputs.has(linked_key):
				wall_dimensions[linked_key] = safe_value
	var normalized = DroneTrainingObstacleShape.normalized_dimensions(
		wall_shape_kind,
		wall_dimensions
	)
	wall_dimensions.merge(normalized, true)
	wall_dimension_sync_in_progress = true
	for key in wall_dimension_inputs:
		var input = wall_dimension_inputs[key] as SpinBox
		if input != null:
			input.set_value_no_signal(float(wall_dimensions.get(key, safe_value)))
	wall_dimension_sync_in_progress = false
	_update_wall_preview()


func _wall_linked_dimension_state() -> Dictionary:
	var stored: Variant = wall_linked_dimensions_by_shape.get(wall_shape_kind, {})
	if stored is Dictionary:
		return stored as Dictionary
	var created: Dictionary = {}
	wall_linked_dimensions_by_shape[wall_shape_kind] = created
	return created


func _wall_linked_dimension_keys() -> Array[String]:
	var result: Array[String] = []
	var state = _wall_linked_dimension_state()
	for key in state:
		if bool(state.get(key, false)):
			result.append(str(key))
	return result


func _is_wall_dimension_linked(dimension_key: String) -> bool:
	return bool(_wall_linked_dimension_state().get(dimension_key, false))


func _set_wall_dimension_linked(enabled: bool, dimension_key: String) -> void:
	var state = _wall_linked_dimension_state()
	if enabled:
		state[dimension_key] = true
	else:
		state.erase(dimension_key)
	wall_linked_dimensions_by_shape[wall_shape_kind] = state
	_refresh_wall_dimension_link_buttons()


func _refresh_wall_dimension_link_buttons() -> void:
	for key in wall_dimension_link_buttons:
		var button = wall_dimension_link_buttons[key] as Button
		if button == null:
			continue
		var linked = _is_wall_dimension_linked(str(key))
		button.set_pressed_no_signal(linked)
		var style = DroneTrainingRoomPresentation.scanner_button_style(linked)
		for state_name in ["normal", "pressed", "hover", "hover_pressed"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_color_override(
			"font_color",
			Color("ffad42") if linked else Color("8de1ff")
		)


func _current_wall_dimensions() -> Dictionary:
	return DroneTrainingObstacleShape.normalized_dimensions(
		wall_shape_kind,
		wall_dimensions
	)


func _wall_vertical_half_extent() -> float:
	return DroneTrainingObstacleShape.vertical_half_extent(
		wall_shape_kind,
		_current_wall_dimensions()
	)


func _begin_turret_placement(
	group_id: int,
	activate_on_confirm_override: Variant = null,
	worker_index: int = 0,
	adds_worker: bool = false
) -> void:
	var group: Dictionary = turret_training.group_by_id(group_id)
	if group.is_empty():
		return
	var worker_count: int = turret_training.group_worker_count(group_id)
	if adds_worker:
		if not turret_training.group_can_add_worker(group_id):
			status_label.text = "This turret group already has the maximum of %d workers." % TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT
			return
		worker_index = worker_count
	elif worker_index < 0 or worker_index >= worker_count:
		return
	if training_item_placement_active:
		_cancel_training_item_placement("", true)
	if wall_placement_active:
		_cancel_wall_placement("")
	if wall_drag_active:
		_finish_wall_drag(true)
	if turret_placement_active:
		_cancel_turret_placement("")
	# Placement pauses the group's runtime. Moving an existing turret clears that physical
	# population so its ghost cannot overlap the live body; adding a worker keeps the already
	# placed turrets frozen and visible until the new placement is confirmed.
	var was_active: bool = bool(group.get("active", false))
	var was_placed: bool = bool(group.get("placement_configured", false))
	turret_placement_activate_on_confirm = (
		bool(activate_on_confirm_override)
		if activate_on_confirm_override is bool
		else (was_active if was_placed else true)
	)
	turret_placement_restore_active = was_active
	turret_placement_restore_had_workers = not (group.get("workers", []) as Array).is_empty()
	turret_training.set_group_active(
		group_id,
		false,
		_target_objective_position(group_id),
		episode_duration,
		ARENA_SIZE
	)
	# Adding another worker must not make the already placed paused turrets vanish. Moving an
	# existing turret still uses the old clear-and-ghost flow so the preview cannot overlap the
	# body whose placement is being edited.
	if not adds_worker:
		turret_training.prepare_group_for_placement(group_id)
	turret_placement_active = true
	turret_placement_group_id = group_id
	turret_placement_worker_index = worker_index
	turret_placement_adds_worker = adds_worker
	var current_transform: Transform3D = (
		turret_training.group_worker_placement_transform(group_id, worker_index)
		if not adds_worker
		else turret_training.group_worker_placement_transform(group_id, maxi(worker_count - 1, 0))
	)
	turret_placement_position = current_transform.origin
	turret_placement_yaw_degrees = (
		turret_training.group_worker_placement_yaw_degrees(group_id, worker_index)
		if not adds_worker
		else 0.0
	)
	_ensure_turret_placement_preview(group)
	_update_turret_placement_preview_transform()
	_rebuild_group_cards()
	var action_text: String = "Add turret %d to" % (worker_index + 1) if adds_worker else "Place turret %d for" % (worker_index + 1)
	status_label.text = "%s %s: move the mouse over the floor or obstacle top, left-click to confirm, right-click/Escape to cancel." % [
		action_text,
		str(group.get("name", "turret group")),
	]


func _next_unconfigured_turret_worker_index(group: Dictionary) -> int:
	var placements_value: Variant = group.get("worker_placements", [])
	if not (placements_value is Array):
		return -1
	var placements: Array = placements_value as Array
	var worker_count: int = clampi(
		int(group.get("worker_count", placements.size())),
		1,
		TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT
	)
	for worker_index in range(mini(worker_count, placements.size())):
		var placement_value: Variant = placements[worker_index]
		if not (placement_value is Dictionary):
			return worker_index
		if not bool((placement_value as Dictionary).get("configured", false)):
			return worker_index
	return -1


func _begin_add_turret_worker(group_id: int) -> void:
	_begin_turret_placement(group_id, null, turret_training.group_worker_count(group_id), true)


func _cancel_turret_placement(message: String, restore_previous: bool = true) -> void:
	var restore_group_id: int = turret_placement_group_id
	var restore_active: bool = turret_placement_restore_active
	var restore_had_workers: bool = turret_placement_restore_had_workers
	var workers_were_cleared: bool = not turret_placement_adds_worker
	turret_placement_active = false
	turret_placement_group_id = -1
	turret_placement_worker_index = 0
	turret_placement_adds_worker = false
	turret_placement_activate_on_confirm = true
	turret_placement_restore_active = false
	turret_placement_restore_had_workers = false
	if is_instance_valid(turret_placement_preview):
		turret_placement_preview.visible = false
	if restore_previous and restore_had_workers and restore_group_id >= 0:
		# Moving an existing turret clears its body for the ghost, so recreate it. Adding a worker
		# leaves a paused population intact; cancelling that flow must not briefly wake it just to
		# pause it again.
		if restore_active or workers_were_cleared:
			turret_training.set_group_active(
				restore_group_id,
				true,
				_target_objective_position(restore_group_id),
				episode_duration,
				ARENA_SIZE
			)
			if not restore_active:
				turret_training.set_group_active(
					restore_group_id,
					false,
					_target_objective_position(restore_group_id),
					episode_duration,
					ARENA_SIZE
				)
		_rebuild_group_cards()
		_refresh_selected_group_controls()
	if status_label != null and not message.is_empty():
		status_label.text = message


func _ensure_turret_placement_preview(group: Dictionary) -> void:
	if is_instance_valid(turret_placement_preview):
		turret_placement_preview.queue_free()
	turret_placement_preview = Node3D.new()
	turret_placement_preview.name = "TurretPlacementPreview"
	add_child(turret_placement_preview)
	var loadout: TurretLoadout = turret_training.group_loadout(int(group.get("group_id", -1)))
	if loadout == null:
		return
	var preview_color: Color = group.get("color", Color("ffad42"))
	preview_color.a = TURRET_PLACEMENT_PREVIEW_ALPHA
	var preview_material: StandardMaterial3D = DroneTrainingRoomPresentation.material(preview_color, false)
	var base_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var base_mesh: BoxMesh = BoxMesh.new()
	base_mesh.size = loadout.base.footprint_size
	base_mesh_instance.mesh = base_mesh
	base_mesh_instance.position.y = loadout.base.footprint_size.y * 0.5
	base_mesh_instance.material_override = preview_material
	base_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turret_placement_preview.add_child(base_mesh_instance)
	var head_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: CylinderMesh = CylinderMesh.new()
	head_mesh.top_radius = loadout.base.rotating_head_radius_m
	head_mesh.bottom_radius = loadout.base.rotating_head_radius_m
	head_mesh.height = loadout.base.rotating_head_height_m
	head_mesh_instance.mesh = head_mesh
	head_mesh_instance.position.y = loadout.base.head_center_height_m
	head_mesh_instance.material_override = preview_material
	head_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turret_placement_preview.add_child(head_mesh_instance)
	var barrel_mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var barrel_mesh: CylinderMesh = CylinderMesh.new()
	barrel_mesh.top_radius = loadout.gun.barrel_radius_m
	barrel_mesh.bottom_radius = loadout.gun.barrel_radius_m
	barrel_mesh.height = loadout.gun.barrel_length_m
	barrel_mesh_instance.mesh = barrel_mesh
	barrel_mesh_instance.rotation.x = PI * 0.5
	barrel_mesh_instance.position = Vector3(
		loadout.gun.barrel_mount_offset.x,
		loadout.base.head_center_height_m + loadout.gun.barrel_mount_offset.y,
		loadout.gun.barrel_mount_offset.z - loadout.gun.barrel_length_m * 0.5
	)
	barrel_mesh_instance.material_override = preview_material
	barrel_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	turret_placement_preview.add_child(barrel_mesh_instance)
	turret_placement_preview.visible = true


func _turret_placement_surface_hit(screen_position: Vector2) -> Dictionary:
	var camera: Camera3D = _interaction_camera()
	if camera == null or get_world_3d() == null:
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * EDITOR_PICK_RAY_LENGTH_M,
		ARENA_COLLISION_LAYER
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: StaticBody3D = hit.get("collider") as StaticBody3D
	if collider == null:
		return {}
	var is_training_surface: bool = (
		bool(collider.get_meta("training_ground", false))
		or bool(collider.get_meta("training_custom_wall", false))
		or bool(collider.get_meta("training_wall", false))
	)
	if not is_training_surface:
		return {}
	var normal_value: Variant = hit.get("normal", Vector3.UP)
	if not (normal_value is Vector3):
		return {}
	var normal: Vector3 = normal_value as Vector3
	if not normal.is_finite() or normal.y < TURRET_PLACEMENT_MINIMUM_UP_NORMAL:
		return {}
	var point_value: Variant = hit.get("position", Vector3.ZERO)
	if not (point_value is Vector3) or not (point_value as Vector3).is_finite():
		return {}
	return {"point": point_value, "normal": normal, "collider": collider}


func _update_turret_placement_from_screen(screen_position: Vector2) -> bool:
	if not turret_placement_active:
		return false
	var hit: Dictionary = _turret_placement_surface_hit(screen_position)
	if hit.is_empty():
		return false
	turret_placement_position = hit.get("point", Vector3.ZERO)
	_update_turret_placement_preview_transform()
	return true


func _update_turret_placement_preview_transform() -> void:
	if not is_instance_valid(turret_placement_preview):
		return
	turret_placement_preview.global_position = turret_placement_position
	turret_placement_preview.global_rotation = Vector3(0.0, deg_to_rad(turret_placement_yaw_degrees), 0.0)
	turret_placement_preview.visible = turret_placement_active


func _confirm_turret_placement() -> void:
	if not turret_placement_active:
		return
	var group_id: int = turret_placement_group_id
	var worker_index: int = turret_placement_worker_index
	var adds_worker: bool = turret_placement_adds_worker
	var placed_position: Vector3 = turret_placement_position
	var placed_yaw: float = turret_placement_yaw_degrees
	var group: Dictionary = turret_training.group_by_id(group_id)
	if group.is_empty():
		_cancel_turret_placement("Turret group disappeared before placement completed.")
		return
	var accepted: bool = (
		turret_training.append_group_worker_placement(group_id, placed_position, placed_yaw)
		if adds_worker
		else turret_training.set_group_worker_placement(
			group_id,
			worker_index,
			placed_position,
			placed_yaw
		)
	)
	if not accepted:
		status_label.text = (
			turret_training.last_error
			if not turret_training.last_error.is_empty()
			else "Turret placement was rejected."
		)
		return
	var activate_after_placement: bool = turret_placement_activate_on_confirm
	var next_worker_index: int = _next_unconfigured_turret_worker_index(group)
	_cancel_turret_placement("", false)
	if next_worker_index >= 0:
		call_deferred(
			"_begin_turret_placement",
			group_id,
			activate_after_placement,
			next_worker_index,
			false
		)
		status_label.text = "%s turret %d placed. Place turret %d next." % [
			str(group.get("name", "Turret group")),
			worker_index + 1,
			next_worker_index + 1,
		]
		return
	if activate_after_placement:
		turret_ui.set_group_active(group_id, true)
	# A creator group configured to start paused must stay genuinely untouched: do not briefly
	# activate it just to materialize bodies, because that would create episode 1 and sample the
	# policy before the user ever presses Start. Its authored placements are retained and the real
	# turret population is instantiated on the first explicit resume.
	_rebuild_group_cards()
	_refresh_target_controls_for_selection()
	status_label.text = "%s turret %d placed at (%.2f, %.2f, %.2f)." % [
		str(group.get("name", "Turret group")),
		worker_index + 1,
		placed_position.x,
		placed_position.y,
		placed_position.z,
	]


func _toggle_wall_placement() -> void:
	if training_item_placement_active:
		_cancel_training_item_placement("", true)
	if turret_placement_active:
		_cancel_turret_placement("")
	if wall_drag_active:
		_finish_wall_drag(true)
	if wall_placement_active:
		_cancel_wall_placement("Obstacle placement cancelled.")
		return
	wall_placement_active = true
	_ensure_wall_preview()
	_update_wall_preview()
	if wall_preview != null:
		wall_preview.visible = true
	if wall_place_button != null:
		wall_place_button.text = "CANCEL PLACEMENT"
		wall_place_button.add_theme_stylebox_override(
			"normal",
			DroneTrainingRoomPresentation.scanner_button_style(true)
		)
	_refresh_wall_status()
	status_label.text = "Obstacle spawn armed. The next left-click on the arena places it; right-click or Escape cancels."


func _cancel_wall_placement(message: String) -> void:
	wall_placement_active = false
	if is_instance_valid(wall_preview):
		wall_preview.visible = false
	if wall_place_button != null:
		wall_place_button.text = "SPAWN WITH MOUSE"
		wall_place_button.add_theme_stylebox_override(
			"normal",
			DroneTrainingRoomPresentation.scanner_button_style(false)
		)
	_refresh_wall_status()
	if status_label != null and not message.is_empty():
		status_label.text = message


func _ensure_wall_preview() -> void:
	if is_instance_valid(wall_preview):
		return
	if custom_wall_container == null:
		return
	wall_preview = MeshInstance3D.new()
	wall_preview.name = "CustomObstaclePlacementPreview"
	wall_preview.material_override = DroneTrainingRoomPresentation.material(
		CUSTOM_WALL_PREVIEW_COLOR,
		true
	)
	wall_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall_preview.visible = false
	custom_wall_container.add_child(wall_preview)


func _update_wall_preview() -> void:
	if not wall_placement_active:
		return
	_ensure_wall_preview()
	if not is_instance_valid(wall_preview):
		return
	wall_preview.mesh = DroneTrainingObstacleShape.visual_mesh(
		wall_shape_kind,
		_current_wall_dimensions()
	)
	wall_preview.position = Vector3(
		wall_position_x_m,
		wall_position_y_m,
		wall_position_z_m
	)
	wall_preview.rotation_degrees = Vector3(
		wall_pitch_degrees,
		wall_yaw_degrees,
		wall_roll_degrees
	)


func _interaction_camera() -> Camera3D:
	if is_instance_valid(attached_camera_node) and attached_camera_node.current:
		return attached_camera_node
	return spectator_camera


func _arena_floor_hit_from_screen(screen_position: Vector2) -> Dictionary:
	var camera = _interaction_camera()
	if camera == null:
		return {}
	var ray_origin = camera.project_ray_origin(screen_position)
	var ray_direction = camera.project_ray_normal(screen_position)
	if absf(ray_direction.y) <= 0.000001:
		return {}
	var distance_to_floor = -ray_origin.y / ray_direction.y
	if distance_to_floor < 0.0:
		return {}
	return {"point": ray_origin + ray_direction * distance_to_floor}


func _clamped_wall_floor_position(floor_point: Vector3) -> Vector2:
	# Kept as a compatibility helper for drag/placement call sites; positions are deliberately
	# no longer clamped to the arena bounds.
	return Vector2(floor_point.x, floor_point.z)


func _update_wall_position_from_screen(screen_position: Vector2) -> bool:
	var floor_hit = _arena_floor_hit_from_screen(screen_position)
	if floor_hit.is_empty():
		return false
	var floor_position = _clamped_wall_floor_position(floor_hit["point"])
	wall_position_x_m = floor_position.x
	wall_position_y_m = _wall_vertical_half_extent()
	wall_position_z_m = floor_position.y
	_sync_wall_position_inputs()
	_update_wall_preview()
	return true


func _pick_custom_wall_from_screen(screen_position: Vector2) -> StaticBody3D:
	return DroneTrainingEditorRaycast.pick_custom_wall(
		_interaction_camera(),
		get_world_3d(),
		screen_position,
		EDITOR_PICK_RAY_LENGTH_M,
		ARENA_COLLISION_LAYER,
		TRAINING_ITEM_PLACEMENT_MAXIMUM_RAY_RETRIES
	)

func _confirm_wall_placement() -> void:
	if not wall_placement_active:
		return
	var wall: StaticBody3D = _spawn_custom_wall()
	if not wall_auto_replace_enabled:
		_cancel_wall_placement("")
	else:
		_update_wall_preview()
	if wall == null:
		return
	if wall_auto_replace_enabled:
		status_label.text = "Obstacle placed. Automatic placement remains armed; click again to create another obstacle, or right-click to stop."
	else:
		status_label.text = "Obstacle placed and selected. Drag it in the arena or edit its values and apply."


func _set_wall_auto_replace(enabled: bool) -> void:
	wall_auto_replace_enabled = enabled
	_refresh_wall_auto_replace_button()
	_refresh_wall_status()
	if status_label != null:
		status_label.text = (
			"Automatic placement enabled. Mouse placement stays armed and every click creates another obstacle."
			if enabled
			else "Automatic placement disabled. Mouse placement stops after one obstacle."
		)


func _refresh_wall_auto_replace_button() -> void:
	if wall_auto_replace_button == null:
		return
	wall_auto_replace_button.text = (
		"AUTO PLACE: ON"
		if wall_auto_replace_enabled
		else "AUTO PLACE: OFF"
	)
	wall_auto_replace_button.call(
		"set_rolling_active",
		wall_auto_replace_enabled
	)


func _spawn_or_replace_custom_wall() -> StaticBody3D:
	# Kept as a compatibility call site. Automatic placement means repeated creation,
	# not replacing the selected obstacle. Existing obstacles are edited explicitly
	# through Apply to Selected.
	return _spawn_custom_wall()


func _configure_selected_custom_wall_from_editor(restart_message: String) -> void:
	if not is_instance_valid(selected_custom_wall):
		return
	var dimensions = _current_wall_dimensions()
	DroneTrainingRoomPresentation.configure_static_obstacle(
		selected_custom_wall,
		wall_shape_kind,
		dimensions
	)
	selected_custom_wall.position = Vector3(
		wall_position_x_m,
		wall_position_y_m,
		wall_position_z_m
	)
	selected_custom_wall.rotation_degrees = Vector3(
		wall_pitch_degrees,
		wall_yaw_degrees,
		wall_roll_degrees
	)
	DroneTrainingRoomPresentation.recolor_static_box(
		selected_custom_wall,
		CUSTOM_WALL_SELECTED_COLOR,
		true
	)
	_sync_wall_editor_from_selected()
	_rebuild_wall_spatial_hash()
	_restart_for_configuration_change(restart_message, true, true, true)


func _spawn_custom_wall() -> StaticBody3D:
	if custom_wall_container == null:
		return null
	custom_wall_counter += 1
	var dimensions = _current_wall_dimensions()
	var wall = DroneTrainingRoomPresentation.add_static_obstacle(
		custom_wall_container,
		"CustomObstacle%03d" % custom_wall_counter,
		Vector3(
			wall_position_x_m,
			wall_position_y_m,
			wall_position_z_m
		),
		wall_shape_kind,
		dimensions,
		CUSTOM_WALL_COLOR,
		ARENA_COLLISION_LAYER,
		TRAINING_BODY_COLLISION_MASK
	)
	wall.rotation_degrees = Vector3(
		wall_pitch_degrees,
		wall_yaw_degrees,
		wall_roll_degrees
	)
	wall.set_meta("training_custom_wall", true)
	wall.set_meta("training_wall", true)
	wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
	custom_walls.append(wall)
	_select_custom_wall(wall)
	_rebuild_wall_spatial_hash()
	_restart_for_configuration_change("Custom obstacle added; episode restarted.", true, true, true)
	return wall


func _custom_wall_shape_kind(wall: StaticBody3D) -> int:
	if wall != null and wall.has_meta("training_shape_kind"):
		return int(wall.get_meta("training_shape_kind"))
	return DroneTrainingObstacleShape.Kind.BOX


func _custom_wall_dimensions(wall: StaticBody3D) -> Dictionary:
	if wall != null and wall.has_meta("training_shape_dimensions"):
		var stored: Variant = wall.get_meta("training_shape_dimensions")
		if stored is Dictionary:
			return (stored as Dictionary).duplicate(true)
	if wall != null:
		for child in wall.get_children():
			var collision = child as CollisionShape3D
			if collision != null and collision.shape != null:
				return DroneTrainingObstacleShape.dimensions_from_shape(
					collision.shape
				)
	return DroneTrainingObstacleShape.normalized_dimensions(
		DroneTrainingObstacleShape.Kind.BOX,
		{
			"width": CUSTOM_WALL_DEFAULT_WIDTH_M,
			"height": CUSTOM_WALL_DEFAULT_HEIGHT_M,
			"depth": CUSTOM_WALL_DEFAULT_THICKNESS_M,
		}
	)


func _select_custom_wall(wall: StaticBody3D) -> void:
	var selection_changed = selected_custom_wall != wall
	if is_instance_valid(selected_custom_wall) and selection_changed:
		DroneTrainingRoomPresentation.recolor_static_box(
			selected_custom_wall,
			CUSTOM_WALL_COLOR
		)
	selected_custom_wall = wall if is_instance_valid(wall) else null
	if is_instance_valid(selected_custom_wall):
		DroneTrainingRoomPresentation.recolor_static_box(
			selected_custom_wall,
			CUSTOM_WALL_SELECTED_COLOR,
			true
		)
		if selection_changed:
			_sync_wall_editor_from_selected()
	_refresh_wall_status()


func _sync_wall_editor_from_selected() -> void:
	if not is_instance_valid(selected_custom_wall):
		return
	wall_shape_kind = _custom_wall_shape_kind(selected_custom_wall)
	wall_dimensions.merge(
		_custom_wall_dimensions(selected_custom_wall),
		true
	)
	wall_position_x_m = selected_custom_wall.position.x
	wall_position_y_m = selected_custom_wall.position.y
	wall_position_z_m = selected_custom_wall.position.z
	wall_pitch_degrees = selected_custom_wall.rotation_degrees.x
	wall_yaw_degrees = selected_custom_wall.rotation_degrees.y
	wall_roll_degrees = selected_custom_wall.rotation_degrees.z
	if wall_shape_picker != null:
		wall_shape_picker.select(wall_shape_kind)
	_rebuild_wall_dimension_inputs()
	for dimension_key in wall_dimension_inputs:
		var input = wall_dimension_inputs[dimension_key] as SpinBox
		if input != null:
			input.set_value_no_signal(float(wall_dimensions.get(
				dimension_key,
				1.0
			)))
	if wall_pitch_input != null:
		wall_pitch_input.set_value_no_signal(wall_pitch_degrees)
	if wall_yaw_input != null:
		wall_yaw_input.set_value_no_signal(wall_yaw_degrees)
	if wall_roll_input != null:
		wall_roll_input.set_value_no_signal(wall_roll_degrees)
	_sync_wall_position_inputs()
	_update_wall_preview()


func _sync_wall_position_inputs() -> void:
	if wall_position_x_input != null:
		wall_position_x_input.set_value_no_signal(wall_position_x_m)
	if wall_position_y_input != null:
		wall_position_y_input.set_value_no_signal(wall_position_y_m)
	if wall_position_z_input != null:
		wall_position_z_input.set_value_no_signal(wall_position_z_m)


func _apply_wall_values_to_selected() -> void:
	if wall_placement_active:
		_cancel_wall_placement("")
	if not is_instance_valid(selected_custom_wall):
		status_label.text = "Select an obstacle in the arena before applying edits."
		_refresh_wall_status()
		return
	_configure_selected_custom_wall_from_editor(
		"Selected obstacle updated; episode restarted."
	)


func _begin_wall_drag(wall: StaticBody3D, screen_position: Vector2) -> void:
	_select_custom_wall(wall)
	var floor_hit = _arena_floor_hit_from_screen(screen_position)
	if floor_hit.is_empty():
		status_label.text = "Obstacle selected. Edit its values and press Apply to Selected."
		return
	var floor_point: Vector3 = floor_hit["point"]
	wall_drag_active = true
	wall_drag_changed = false
	wall_drag_start_position = wall.position
	wall_drag_offset = Vector2(
		wall.position.x - floor_point.x,
		wall.position.z - floor_point.z
	)
	_refresh_wall_status()
	status_label.text = "Dragging selected obstacle. Release left mouse to keep it; right-click or Escape restores its old position."


func _update_wall_drag_from_screen(screen_position: Vector2) -> void:
	if not wall_drag_active or not is_instance_valid(selected_custom_wall):
		return
	var floor_hit = _arena_floor_hit_from_screen(screen_position)
	if floor_hit.is_empty():
		return
	var floor_point: Vector3 = floor_hit["point"]
	var floor_position = _clamped_wall_floor_position(Vector3(
		floor_point.x + wall_drag_offset.x,
		0.0,
		floor_point.z + wall_drag_offset.y
	))
	selected_custom_wall.position = Vector3(
		floor_position.x,
		selected_custom_wall.position.y,
		floor_position.y
	)
	wall_position_x_m = floor_position.x
	wall_position_y_m = selected_custom_wall.position.y
	wall_position_z_m = floor_position.y
	_sync_wall_position_inputs()
	wall_drag_changed = (
		selected_custom_wall.position.distance_squared_to(wall_drag_start_position) > 0.000001
	)
	_mark_wall_spatial_hash_dirty()


func _finish_wall_drag(commit: bool) -> void:
	if not wall_drag_active:
		return
	var moved = wall_drag_changed and is_instance_valid(selected_custom_wall)
	if not commit and is_instance_valid(selected_custom_wall):
		selected_custom_wall.position = wall_drag_start_position
		wall_position_x_m = wall_drag_start_position.x
		wall_position_y_m = wall_drag_start_position.y
		wall_position_z_m = wall_drag_start_position.z
		_sync_wall_position_inputs()
	wall_drag_active = false
	wall_drag_changed = false
	_rebuild_wall_spatial_hash()
	_refresh_wall_status()
	if not commit:
		status_label.text = "Obstacle move cancelled. Its previous position was restored."
	elif moved:
		_restart_for_configuration_change("Custom obstacle moved; episode restarted.", true, true, true)
	else:
		status_label.text = "Obstacle selected. Drag it or edit its values and press Apply to Selected."


func _delete_selected_custom_wall() -> void:
	if wall_placement_active:
		_cancel_wall_placement("")
	if not is_instance_valid(selected_custom_wall):
		status_label.text = "Select an obstacle in the arena before deleting it."
		_refresh_wall_status()
		return
	var wall = selected_custom_wall
	wall_drag_active = false
	custom_walls.erase(wall)
	_select_custom_wall(null)
	if wall.get_parent() != null:
		wall.get_parent().remove_child(wall)
	wall.queue_free()
	_rebuild_wall_spatial_hash()
	_refresh_wall_status()
	_restart_for_configuration_change("Selected custom obstacle deleted; episode restarted.", true, true, true)


func _remove_last_custom_wall() -> void:
	if wall_placement_active:
		_cancel_wall_placement("")
	_prune_invalid_custom_walls()
	if custom_walls.is_empty():
		status_label.text = "There are no custom walls to remove."
		_refresh_wall_status()
		return
	var wall: StaticBody3D = custom_walls.pop_back()
	if wall == selected_custom_wall:
		_select_custom_wall(null)
	if is_instance_valid(wall):
		if wall.get_parent() != null:
			wall.get_parent().remove_child(wall)
		wall.queue_free()
	_rebuild_wall_spatial_hash()
	_refresh_wall_status()
	_restart_for_configuration_change("Last custom wall removed; episode restarted.", true, true, true)


func _clear_custom_walls() -> void:
	if wall_placement_active:
		_cancel_wall_placement("")
	_prune_invalid_custom_walls()
	if custom_walls.is_empty():
		status_label.text = "There are no custom walls to clear."
		_refresh_wall_status()
		return
	wall_drag_active = false
	_select_custom_wall(null)
	for wall in custom_walls:
		if is_instance_valid(wall):
			if wall.get_parent() != null:
				wall.get_parent().remove_child(wall)
			wall.queue_free()
	custom_walls.clear()
	_rebuild_wall_spatial_hash()
	_refresh_wall_status()
	_restart_for_configuration_change("All custom walls removed; episode restarted.", true, true, true)


func _prune_invalid_custom_walls() -> void:
	var valid_walls: Array[StaticBody3D] = []
	for wall in custom_walls:
		if is_instance_valid(wall):
			valid_walls.append(wall)
	custom_walls = valid_walls
	if not is_instance_valid(selected_custom_wall):
		selected_custom_wall = null
		wall_drag_active = false


func _refresh_wall_status() -> void:
	_prune_invalid_custom_walls()
	var has_selection = is_instance_valid(selected_custom_wall)
	if wall_apply_button != null:
		wall_apply_button.disabled = not has_selection
		wall_apply_button.add_theme_stylebox_override(
			"normal",
			DroneTrainingRoomPresentation.scanner_button_style(has_selection)
		)
	if wall_delete_button != null:
		wall_delete_button.disabled = not has_selection
	_refresh_wall_auto_replace_button()
	if wall_status_label == null:
		return
	var replace_text = " · auto place on" if wall_auto_replace_enabled else ""
	if wall_placement_active:
		wall_status_label.text = "%d obstacle(s) · %s spawn armed%s · next left-click places one" % [
			custom_walls.size(),
			DroneTrainingObstacleShape.display_name(wall_shape_kind),
			replace_text,
		]
	elif wall_drag_active and has_selection:
		wall_status_label.text = "%d obstacle(s) · dragging %s%s" % [
			custom_walls.size(),
			selected_custom_wall.name,
			replace_text,
		]
	elif has_selection:
		wall_status_label.text = "%d obstacle(s) · %s selected · %s%s" % [
			custom_walls.size(),
			selected_custom_wall.name,
			DroneTrainingObstacleShape.display_name(
				_custom_wall_shape_kind(selected_custom_wall)
			),
			replace_text,
		]
	else:
		wall_status_label.text = "%d custom obstacle(s)%s · click one to select and move it" % [
			custom_walls.size(),
			replace_text,
		]


func _replace_custom_walls_from_records(records: Array) -> void:
	if wall_placement_active:
		_cancel_wall_placement("")
	wall_drag_active = false
	_select_custom_wall(null)
	for wall in custom_walls:
		if is_instance_valid(wall):
			if wall.get_parent() != null:
				wall.get_parent().remove_child(wall)
			wall.queue_free()
	custom_walls.clear()
	custom_wall_counter = 0
	for value in records:
		if not (value is Dictionary):
			continue
		var record = value as Dictionary
		var shape_kind = clampi(
			RLTrainingMath.finite_int_or(
				record.get("shape_kind", DroneTrainingObstacleShape.Kind.BOX),
				DroneTrainingObstacleShape.Kind.BOX
			),
			0,
			DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1
		)
		var dimensions_value: Variant = record.get("dimensions_m", {})
		var dimensions: Dictionary = (
			(dimensions_value as Dictionary).duplicate(true)
			if dimensions_value is Dictionary
			else {}
		)
		if dimensions.is_empty() and record.get("size_m", []) is Array:
			var legacy_size: Array = record.get("size_m", [])
			if legacy_size.size() >= 3:
				dimensions = {
					"width": RLTrainingMath.finite_float_or(legacy_size[0], 1.0),
					"height": RLTrainingMath.finite_float_or(legacy_size[1], 1.0),
					"depth": RLTrainingMath.finite_float_or(legacy_size[2], 1.0),
				}
		dimensions = DroneTrainingObstacleShape.normalized_dimensions(shape_kind, dimensions)
		var position = _vector3_from_number_array(record.get("position_m", []), Vector3.ZERO)
		var rotation = _vector3_from_number_array(
			record.get("rotation_degrees", []),
			Vector3(
				0.0,
				RLTrainingMath.finite_float_or(record.get("yaw_degrees", 0.0), 0.0),
				0.0
			)
		)
		custom_wall_counter += 1
		var wall = DroneTrainingRoomPresentation.add_static_obstacle(
			custom_wall_container,
			"CustomObstacle%03d" % custom_wall_counter,
			position,
			shape_kind,
			dimensions,
			CUSTOM_WALL_COLOR,
			ARENA_COLLISION_LAYER,
			TRAINING_BODY_COLLISION_MASK
		)
		wall.rotation_degrees = rotation
		wall.set_meta("training_custom_wall", true)
		wall.set_meta("training_wall", true)
		wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
		custom_walls.append(wall)
	_rebuild_wall_spatial_hash()
	_refresh_wall_status()


func _vector3_from_number_array(value: Variant, fallback: Vector3) -> Vector3:
	if not (value is Array):
		return fallback
	var values = value as Array
	if values.size() < 3:
		return fallback
	return Vector3(
		RLTrainingMath.finite_float_or(values[0], fallback.x),
		RLTrainingMath.finite_float_or(values[1], fallback.y),
		RLTrainingMath.finite_float_or(values[2], fallback.z)
	)


func _custom_wall_environment_records() -> Array[Dictionary]:
	_prune_invalid_custom_walls()
	var records: Array[Dictionary] = []
	for wall in custom_walls:
		var shape_kind = _custom_wall_shape_kind(wall)
		var dimensions = _custom_wall_dimensions(wall)
		var record = {
			"position_m": [wall.position.x, wall.position.y, wall.position.z],
			"shape_kind": shape_kind,
			"shape": DroneTrainingObstacleShape.display_name(shape_kind),
			"dimensions_m": dimensions.duplicate(true),
			"rotation_degrees": [
				wall.rotation_degrees.x,
				wall.rotation_degrees.y,
				wall.rotation_degrees.z,
			],
			"yaw_degrees": wall.rotation_degrees.y,
		}
		if shape_kind == DroneTrainingObstacleShape.Kind.BOX:
			record["size_m"] = [
				float(dimensions.get("width", 1.0)),
				float(dimensions.get("height", 1.0)),
				float(dimensions.get("depth", 1.0)),
			]
		records.append(record)
	return records


func _build_episode_controls(content: VBoxContainer) -> void:
	var speed_label = Label.new()
	speed_label.text = "Simulation speed"
	speed_label.tooltip_text = "Simulation speed\n\nRuns more simulated physics steps during each real second.\nEpisode timing, rewards, and model decisions still use simulated time."
	content.add_child(speed_label)
	simulation_speed_picker = OptionButton.new()
	simulation_speed_picker.tooltip_text = "Choose simulation speed\n\n1× is normal speed. Higher values collect experience faster but use more CPU.\nThe visible UI still runs in real time."
	for speed in SIMULATION_SPEEDS:
		var speed_index = simulation_speed_picker.item_count
		simulation_speed_picker.add_item(_simulation_speed_text(speed))
		simulation_speed_picker.set_item_metadata(speed_index, speed)
	simulation_speed_picker.item_selected.connect(_set_simulation_speed)
	content.add_child(simulation_speed_picker)
	episode_status_label = Label.new()
	episode_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	episode_status_label.tooltip_text = "Shared episode setup\n\nAll worker families use the room's same episode-duration setting. Per-group episode counters remain available on their own cards; this room label shows the shared duration and aggregate runtime population only."
	content.add_child(episode_status_label)
	_add_slider(
		content,
		"Duration (seconds)",
		2.0,
		600.0,
		1.0,
		episode_duration,
		"Maximum simulated duration. A worker can still finish earlier after destruction, power loss, arena exit, wall deadlock, or any optional per-group terminal rules you enabled. Ground contact and flipped orientation are non-terminal by default. This does not decide when optimizer updates happen; each algorithm updates after collecting enough experience.",
		func(value: float) -> void:
			episode_duration = value
			_restart_for_configuration_change("Episode duration changed.", true, true, true)
	)
	_add_slider(
		content,
		"Drone disable sound volume (dB)",
		DRONE_DISABLE_SOUND_MINIMUM_VOLUME_DB,
		DRONE_DISABLE_SOUND_MAXIMUM_VOLUME_DB,
		1.0,
		drone_disable_sound_volume_db,
		"Volume of the random positional sound played when a drone receives its terminal reason label. -16 dB is deliberately audible but still leaves headroom for several drones failing together; -3 dB is the safety-capped maximum.",
		_set_drone_disable_sound_volume_db
	)
	unlimited_episode_battery_checkbox = CheckBox.new()
	unlimited_episode_battery_checkbox.text = "Unlimited battery during episodes"
	unlimited_episode_battery_checkbox.button_pressed = unlimited_episode_battery
	unlimited_episode_battery_checkbox.tooltip_text = "Unlimited training charge\n\nKeeps battery charge full so long episodes do not end from normal battery drain.\nBattery mass, voltage, power limits, and fluctuations still behave normally."
	unlimited_episode_battery_checkbox.toggled.connect(
		_set_unlimited_episode_battery
	)
	content.add_child(unlimited_episode_battery_checkbox)
	var auto_restart = CheckBox.new()
	auto_restart.text = "Automatic next episode"
	auto_restart.button_pressed = auto_restart_episodes
	auto_restart.tooltip_text = "Automatic next episode\n\nAfter the result pause, resets every drone and starts the next episode using the same shared setup."
	auto_restart.toggled.connect(_set_auto_restart)
	content.add_child(auto_restart)
	evaluation_keep_episode_checkbox = CheckBox.new()
	evaluation_keep_episode_checkbox.text = "Evaluation drones keep episode running"
	evaluation_keep_episode_checkbox.button_pressed = evaluation_drones_keep_episode_running
	evaluation_keep_episode_checkbox.tooltip_text = (
		"Evaluation drones and episode ending\n\n"
		+ "Off: training workers decide when the episode ends. Evaluators do not hold it open.\n"
		+ "On: the episode waits for evaluation drones too.\n\n"
		+ "With no active training group, evaluators still run normally."
	)
	evaluation_keep_episode_checkbox.toggled.connect(
		_set_evaluation_drones_keep_episode_running
	)
	content.add_child(evaluation_keep_episode_checkbox)
	var restart_button = _button("RESTART EPISODE")
	restart_button.tooltip_text = "Restart episode now\n\nEnds the unfinished attempt without counting it as a completed result.\nAll drones restart from the shared spawn state."
	restart_button.pressed.connect(func() -> void:
		_start_episode("Episode restarted manually.")
	)
	content.add_child(restart_button)


func _build_group_browser(content: VBoxContainer) -> void:
	group_list = VBoxContainer.new()
	group_list.add_theme_constant_override("separation", 8)
	content.add_child(group_list)
	DroneTrainingRoomPresentation.add_separator(content)
	evaluator_summary_label = Label.new()
	evaluator_summary_label.text = "EVALUATION DRONES // NONE"
	evaluator_summary_label.add_theme_color_override("font_color", Color("8de1ff"))
	evaluator_summary_label.tooltip_text = "Evaluation drones\n\nThey run saved models without exploration or learning.\nRemoving one does not delete the saved model."
	content.add_child(evaluator_summary_label)
	evaluator_list = VBoxContainer.new()
	evaluator_list.add_theme_constant_override("separation", 8)
	content.add_child(evaluator_list)


func _build_selected_group_actions(content: VBoxContainer) -> void:
	var action_flow = HFlowContainer.new()
	action_flow.add_theme_constant_override("h_separation", 7)
	action_flow.add_theme_constant_override("v_separation", 7)
	content.add_child(action_flow)
	selected_group_branch_button = _button("BRANCH VARIANT", true)
	selected_group_branch_button.tooltip_text = "Create child branch\n\nCopies the selected drone or four-limb group's live weights, settings, rewards, and physical body.\nYou may add a small random weight variation before the child starts."
	selected_group_branch_button.pressed.connect(_open_selected_branch_dialog)
	action_flow.add_child(selected_group_branch_button)
	selected_group_root_button = _button("MAKE ROOT")
	selected_group_root_button.tooltip_text = "Make this group a root\n\nDetaches the selected branch from its parent.\nAll child branches move with it."
	selected_group_root_button.pressed.connect(_promote_selected_group_to_root)
	action_flow.add_child(selected_group_root_button)
	selected_group_distribute_button = _button("APPLY TO ALL GROUPS")
	selected_group_distribute_button.tooltip_text = "Copy weights to other drone groups\n\nReplaces compatible drone groups' live weights with this group's current weights.\nTheir settings and future learning remain separate."
	selected_group_distribute_button.pressed.connect(_apply_selected_policy_to_all_groups)
	action_flow.add_child(selected_group_distribute_button)
	var reset_button = _button("RESET AVERAGES")
	reset_button.tooltip_text = "Reset displayed statistics\n\nClears this group's plots, averages, and best marker.\nThe learned model itself is not changed."
	reset_button.pressed.connect(_reset_selected_group_statistics)
	action_flow.add_child(reset_button)
	var remove_button = _button("REMOVE GROUP")
	remove_button.tooltip_text = "Remove runtime group\n\nDeletes this live training group and its drones.\nSaved model versions remain in the Model Library."
	remove_button.pressed.connect(_remove_selected_group)
	action_flow.add_child(remove_button)


func _build_loadout_controls(content: VBoxContainer) -> void:
	loadout_summary_label = Label.new()
	loadout_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_summary_label.add_theme_color_override("font_color", Color("8de1ff"))
	loadout_summary_label.tooltip_text = "Drone hardware summary\n\nThese values come from the exact parts used when this group spawns new workers."
	content.add_child(loadout_summary_label)

	linked_flight_power_input = _add_number_input(
		content,
		"Linked flight power",
		1.0,
		500.0,
		1.0,
		30.0,
		" W per rotor",
		"Comfort control for lift authority. It changes every installed rotor limit and the battery/core bus ceilings together, so raising it actually increases available thrust instead of being silently bottlenecked by another part.",
		_set_selected_linked_flight_power
	)
	loadout_edit_controls.append(linked_flight_power_input)

	var presets = _add_section(
		content,
		"PART PRESETS",
		"Install one of the existing gameplay part resources into this group's private training loadout. Custom stat edits never modify the original .tres files.",
		true
	)
	loadout_core_picker = _add_loadout_preset_picker(
		presets,
		"Core",
		LOADOUT_CONFIG.core_presets(),
		&"core"
	)
	loadout_battery_picker = _add_loadout_preset_picker(
		presets,
		"Battery",
		LOADOUT_CONFIG.battery_presets(),
		&"battery"
	)
	loadout_propeller_picker = _add_loadout_preset_picker(
		presets,
		"All propellers",
		LOADOUT_CONFIG.propeller_presets(),
		&"propeller"
	)
	var reset_button = _button("RESTORE QUAD DRONE PRESET")
	reset_button.tooltip_text = "Restore Quad Drone preset\n\nReplaces this paused group's body with a fresh Quad Drone creator preset.\nOther groups are not changed."
	reset_button.pressed.connect(_reset_selected_group_loadout)
	presets.add_child(reset_button)
	loadout_edit_controls.append(reset_button)

	var core_stats = _add_section(
		content,
		"CORE PHYSICS",
		"Mass, electrical throughput, motor response and aerodynamic damping from DroneCoreDefinition.",
		false
	)
	_add_loadout_stat_input(core_stats, "Core mass", &"core", &"mass", 0.05, 20.0, 0.05, " kg", "Contributes directly to RigidBody3D mass and therefore required hover thrust.")
	_add_loadout_stat_input(core_stats, "Core power throughput", &"core", &"max_power_throughput", 1.0, 2000.0, 1.0, " W", "Maximum total propeller power the core can pass through.")
	_add_loadout_stat_input(core_stats, "Spool-up response", &"core", &"spool_up_response", 0.01, 100.0, 0.05, "", "How quickly requested motor power rises toward a new command.")
	_add_loadout_stat_input(core_stats, "Spool-down response", &"core", &"spool_down_response", 0.01, 100.0, 0.05, "", "How quickly motor power falls after a command is reduced.")
	_add_loadout_stat_input(core_stats, "Core power consistency", &"core", &"power_output_consistency", 0.0, 1.0, 0.001, "", "One means stable power. Lower values add stronger core-output variation.")
	_add_loadout_stat_input(core_stats, "Core fluctuation rate", &"core", &"fluctuation_rate", 0.0, 20.0, 0.01, " Hz", "How quickly core-output variation changes.")
	_add_loadout_stat_input(core_stats, "Drag area", &"core", &"drag_area", 0.001, 10.0, 0.001, " m²", "Reference area used by the drone's aerodynamic drag calculation.")
	_add_loadout_stat_input(core_stats, "Drag coefficient", &"core", &"drag_coefficient", 0.0, 10.0, 0.01, "", "Linear aerodynamic drag coefficient.")
	_add_loadout_stat_input(core_stats, "Angular drag coefficient", &"core", &"angular_drag_coefficient", 0.0, 50.0, 0.01, "", "Rotational aerodynamic damping applied by the drone physics.")

	var battery_stats = _add_section(
		content,
		"BATTERY",
		"Energy, bus-power and fluctuation values from DroneBatteryDefinition. Unlimited episode battery prevents depletion only; these output limits still apply.",
		false
	)
	_add_loadout_stat_input(battery_stats, "Battery mass", &"battery", &"mass", 0.01, 20.0, 0.01, " kg", "Contributes directly to total drone mass.")
	_add_loadout_stat_input(battery_stats, "Capacity", &"battery", &"energy_capacity_wh", 0.001, 10000.0, 0.01, " Wh", "Stored energy used when unlimited episode battery is disabled.")
	_add_loadout_stat_input(battery_stats, "Nominal output", &"battery", &"nominal_power_output", 0.0, 2000.0, 1.0, " W", "Normal total bus power available to all installed propellers.")
	_add_loadout_stat_input(battery_stats, "Maximum output", &"battery", &"maximum_power_output", 0.0, 3000.0, 1.0, " W", "Upper total bus-power ceiling during positive fluctuations or spikes.")
	_add_loadout_stat_input(battery_stats, "Battery consistency", &"battery", &"power_output_consistency", 0.0, 1.0, 0.001, "", "One means stable battery output. Lower values create stronger power variation.")
	_add_loadout_stat_input(battery_stats, "Battery fluctuation rate", &"battery", &"fluctuation_rate", 0.0, 20.0, 0.01, " Hz", "How quickly battery-output variation changes.")
	_add_loadout_stat_input(battery_stats, "Spike chance / second", &"battery", &"spike_chance_per_second", 0.0, 10.0, 0.001, "", "Chance per simulated second of entering the battery's configured drop or boost behavior.")

	var propeller_stats = _add_section(
		content,
		"PROPELLERS",
		"These values are applied identically to every installed propeller. The accepted body interface still determines how many rotor controls the policy owns.",
		false
	)
	_add_loadout_stat_input(propeller_stats, "Maximum draw per propeller", &"propeller", &"max_power_draw", 0.0, 500.0, 1.0, " W", "Advanced per-rotor power cap. Unlike Linked flight power, this does not automatically change battery or core bus limits.")
	_add_loadout_stat_input(propeller_stats, "Mass per propeller", &"propeller", &"mass", 0.001, 10.0, 0.001, " kg", "Mass of each rotor assembly; total propeller mass is this value multiplied by the number of installed propellers.")
	_add_loadout_stat_input(propeller_stats, "Rotor radius", &"propeller", &"rotor_radius", 0.01, 2.0, 0.01, " m", "Rotor disk radius used by the thrust model and visual rotor size.")
	_add_loadout_stat_input(propeller_stats, "Aerodynamic efficiency", &"propeller", &"aerodynamic_efficiency", 0.01, 1.0, 0.01, "", "Fraction of electrical power converted into useful induced airflow in the thrust model.")
	_add_loadout_stat_input(propeller_stats, "Reaction torque / newton", &"propeller", &"reaction_torque_per_newton", 0.0, 1.0, 0.001, "", "Yaw reaction torque generated for each newton of rotor thrust.")
	_add_loadout_stat_input(propeller_stats, "Axial-flow response", &"propeller", &"axial_flow_response", 0.0, 5.0, 0.01, "", "Strength of thrust loss or gain caused by moving through air along the rotor axis.")
	_add_loadout_stat_input(propeller_stats, "Minimum axial-flow factor", &"propeller", &"minimum_axial_flow_factor", 0.0, 1.0, 0.01, "", "Lowest multiplier the axial-flow model may apply to static thrust.")
	_add_loadout_stat_input(propeller_stats, "Maximum axial-flow factor", &"propeller", &"maximum_axial_flow_factor", 1.0, 5.0, 0.01, "", "Highest multiplier the axial-flow model may apply to static thrust.")


func _add_loadout_preset_picker(
	parent: VBoxContainer,
	title: String,
	presets: Array[Dictionary],
	part_kind: StringName
) -> OptionButton:
	var label = Label.new()
	label.text = title
	parent.add_child(label)
	var picker = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = "Choose gameplay part\n\nThe selected group receives its own private copy.\nChanging it here does not edit the original resource or another group."
	for preset in presets:
		var item_index = picker.item_count
		picker.add_item(str(preset.get("name", "Unnamed part")))
		picker.set_item_metadata(item_index, str(preset.get("path", "")))
	picker.item_selected.connect(func(index: int) -> void:
		if suppress_ui_callbacks:
			return
		_select_loadout_preset(part_kind, str(picker.get_item_metadata(index)))
	)
	parent.add_child(picker)
	loadout_edit_controls.append(picker)
	return picker


func _add_loadout_stat_input(
	parent: VBoxContainer,
	title: String,
	part_kind: StringName,
	property_name: StringName,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	tooltip: String
) -> SpinBox:
	var key = "%s:%s" % [str(part_kind), str(property_name)]
	var input = _add_number_input(
		parent,
		title,
		minimum,
		maximum,
		step,
		0.0,
		suffix,
		tooltip,
		func(value: float) -> void:
			if not suppress_ui_callbacks:
				_set_selected_loadout_stat(part_kind, property_name, value)
	)
	loadout_stat_inputs[key] = input
	loadout_edit_controls.append(input)
	return input


func _selected_group_loadout() -> DroneLoadout:
	var group = _selected_group()
	if group.is_empty():
		return null
	return group.get("drone_loadout") as DroneLoadout


func _set_selected_linked_flight_power(value: float) -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before changing its drone hardware." % group["name"]
		_refresh_selected_loadout_controls()
		return
	var loadout = group.get("drone_loadout") as DroneLoadout
	if not LOADOUT_CONFIG.set_linked_flight_power_per_rotor(loadout, value):
		status_label.text = "Could not apply linked flight power to this loadout."
		_refresh_selected_loadout_controls()
		return
	_clear_drone_group_runtime_for_configuration_change(group)
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	_refresh_selected_loadout_controls()
	_refresh_group_card_texts()
	status_label.text = "%s linked flight power updated. Resume the group to spawn the revised drone." % group["name"]


func _set_selected_loadout_stat(
	part_kind: StringName,
	property_name: StringName,
	value: float
) -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before changing its drone hardware." % group["name"]
		_refresh_selected_loadout_controls()
		return
	var loadout = group.get("drone_loadout") as DroneLoadout
	if loadout == null or not LOADOUT_CONFIG.set_part_stat(
		loadout,
		part_kind,
		property_name,
		value
	):
		status_label.text = "Could not change %s on this loadout." % str(property_name)
		_refresh_selected_loadout_controls()
		return
	_normalize_selected_loadout_values(loadout, part_kind, property_name)
	_clear_drone_group_runtime_for_configuration_change(group)
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	_refresh_selected_loadout_controls()
	_refresh_group_card_texts()
	status_label.text = "%s hardware updated. Resume the group to spawn workers with these exact parts." % group["name"]


func _normalize_selected_loadout_values(
	loadout: DroneLoadout,
	part_kind: StringName,
	property_name: StringName
) -> void:
	if loadout == null:
		return
	if part_kind == &"battery" and loadout.battery != null:
		if property_name == &"nominal_power_output":
			loadout.battery.maximum_power_output = maxf(
				loadout.battery.maximum_power_output,
				loadout.battery.nominal_power_output
			)
		elif property_name == &"maximum_power_output":
			loadout.battery.nominal_power_output = minf(
				loadout.battery.nominal_power_output,
				loadout.battery.maximum_power_output
			)
	if part_kind == &"propeller":
		var propeller_count: int = maxi(loadout.core.propeller_slot_count, 0) if loadout.core != null else 0
		for slot_index in range(propeller_count):
			var propeller = loadout.get_propeller(slot_index)
			if propeller == null:
				continue
			if property_name == &"minimum_axial_flow_factor":
				propeller.maximum_axial_flow_factor = maxf(
					propeller.maximum_axial_flow_factor,
					propeller.minimum_axial_flow_factor
				)
			elif property_name == &"maximum_axial_flow_factor":
				propeller.minimum_axial_flow_factor = minf(
					propeller.minimum_axial_flow_factor,
					propeller.maximum_axial_flow_factor
				)


func _ensure_group_drone_profile_hardware(group: Dictionary) -> bool:
	if group.is_empty():
		return false
	var loadout = group.get("drone_loadout") as DroneLoadout
	if loadout == null:
		return false
	var manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(loadout)
	if manifest == null:
		return false
	var trainer = group.get("trainer") as DroneTrainingAlgorithm
	if trainer == null:
		return false
	if str(group.get("algorithm_id", "")) == "ppo_clip":
		var architecture: Dictionary = trainer.network_architecture()
		if (
			int(architecture.get("action_count", -1)) != manifest.control_count()
			or int(architecture.get("body_feature_count", -1)) != manifest.observation_count()
			or str(architecture.get("body_interface_signature", "")) != manifest.contract_signature
		):
			return false
	elif not _manifest_is_legacy_four_propeller_body(manifest):
		return false
	group["body_interface"] = manifest.to_dictionary()
	group["body_interface_signature"] = manifest.contract_signature
	group["belly_grabber"] = LOADOUT_CONFIG.has_training_belly_grabber(loadout)
	return true


func _select_loadout_preset(part_kind: StringName, resource_path: String) -> void:
	var group = _selected_group()
	if group.is_empty() or resource_path.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before replacing drone parts." % group["name"]
		_refresh_selected_loadout_controls()
		return
	var loadout = group.get("drone_loadout") as DroneLoadout
	var previous_loadout = LOADOUT_CONFIG.duplicate_loadout(loadout)
	var installed = false
	match part_kind:
		&"core":
			installed = LOADOUT_CONFIG.install_core_preset(loadout, resource_path)
		&"battery":
			installed = LOADOUT_CONFIG.install_battery_preset(loadout, resource_path)
		&"propeller":
			installed = LOADOUT_CONFIG.install_propeller_preset(loadout, resource_path)
	if not installed:
		status_label.text = "Could not install that part into this training body."
		_refresh_selected_loadout_controls()
		return
	if not _ensure_group_drone_profile_hardware(group):
		group["drone_loadout"] = previous_loadout
		status_label.text = "That hardware preset changes the accepted model-body interface for this policy."
		_refresh_selected_loadout_controls()
		return
	_clear_drone_group_runtime_for_configuration_change(group)
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	_refresh_selected_loadout_controls()
	_refresh_group_card_texts()
	status_label.text = "%s part preset installed. Resume the group to use it." % group["name"]


func _reset_selected_group_loadout() -> void:
	var group = _selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before resetting its drone hardware." % group["name"]
		return
	var previous_loadout = group.get("drone_loadout") as DroneLoadout
	group["drone_loadout"] = MLBodyPresetLibrary.drone_quad_loadout(false)
	if not _ensure_group_drone_profile_hardware(group):
		group["drone_loadout"] = previous_loadout
		status_label.text = "Could not restore hardware compatible with this policy."
		_refresh_selected_loadout_controls()
		return
	_clear_drone_group_runtime_for_configuration_change(group)
	group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	_refresh_selected_loadout_controls()
	_refresh_group_card_texts()
	status_label.text = "%s restored to the Quad Drone preset." % group["name"]


func _refresh_selected_loadout_controls() -> void:
	if loadout_summary_label == null:
		return
	var group = _selected_group()
	var loadout = _selected_group_loadout()
	var editable = not group.is_empty() and not bool(group.get("active", false))
	for control in loadout_edit_controls:
		if control is SpinBox:
			(control as SpinBox).editable = editable
		elif control is BaseButton:
			(control as BaseButton).disabled = not editable
	if group.is_empty() or loadout == null:
		loadout_summary_label.text = "Select a worker group to inspect its drone parts."
		return
	suppress_ui_callbacks = true
	if linked_flight_power_input != null:
		linked_flight_power_input.value = LOADOUT_CONFIG.linked_flight_power_per_rotor(loadout)
	for key in loadout_stat_inputs:
		var parts = str(key).split(":", false, 1)
		if parts.size() != 2:
			continue
		var input = loadout_stat_inputs[key] as SpinBox
		if input != null:
			input.value = float(LOADOUT_CONFIG.part_stat(
				loadout,
				StringName(str(parts[0])),
				StringName(str(parts[1])),
				0.0
			))
	_select_picker_path(loadout_core_picker, LOADOUT_CONFIG.source_path(loadout.core))
	_select_picker_path(loadout_battery_picker, LOADOUT_CONFIG.source_path(loadout.battery))
	_select_picker_path(
		loadout_propeller_picker,
		LOADOUT_CONFIG.source_path(loadout.get_propeller(0))
	)
	suppress_ui_callbacks = false
	loadout_summary_label.text = _loadout_summary_text(loadout, editable)


func _select_picker_path(picker: OptionButton, resource_path: String) -> void:
	if picker == null:
		return
	var selected_index = -1
	for item_index in range(picker.item_count):
		if str(picker.get_item_metadata(item_index)) == resource_path:
			selected_index = item_index
			break
	if selected_index >= 0:
		picker.select(selected_index)
	else:
		picker.selected = -1


func _loadout_summary_text(loadout: DroneLoadout, editable: bool) -> String:
	var summary: Dictionary = LOADOUT_CONFIG.physical_summary(loadout)
	if summary.is_empty():
		return "Incomplete loadout — fill every authored hardware slot."
	var propeller_count: int = int(summary.get("propeller_count", 0))
	if propeller_count == 0:
		return "%s · %s · articulated ground body\nMass %s kg · no propellers / no flight-lift estimate\n%s" % [
			str(summary.get("core_name", "Core")),
			str(summary.get("battery_name", "Battery")),
			String.num(float(summary.get("mass_kg", 0.0)), 2),
			"Paused — hardware editing enabled." if editable else "Running — pause this group to edit hardware.",
		]
	var lift_ratio = float(summary.get("nominal_lift_to_weight", 0.0))
	var lift_status = "cannot hover"
	if lift_ratio >= 1.5:
		lift_status = "strong lift margin"
	elif lift_ratio >= 1.15:
		lift_status = "usable lift margin"
	elif lift_ratio >= 1.0:
		lift_status = "barely able to hover"
	return "%s · %s · %d× %s\nMass %s kg · nominal bus %s W · estimated hover %s W\nNominal lift %sx body weight · %s\n%s" % [
		str(summary.get("core_name", "Core")),
		str(summary.get("battery_name", "Battery")),
		propeller_count,
		str(summary.get("propeller_name", "Propeller")),
		String.num(float(summary.get("mass_kg", 0.0)), 2),
		String.num(float(summary.get("nominal_bus_power_w", 0.0)), 1),
		String.num(float(summary.get("hover_power_w", 0.0)), 1),
		String.num(lift_ratio, 2),
		lift_status,
		"Paused — hardware editing enabled." if editable else "Running — pause this group to edit hardware."
	]


func _compact_loadout_text(loadout: DroneLoadout) -> String:
	var summary: Dictionary = LOADOUT_CONFIG.physical_summary(loadout)
	if summary.is_empty():
		return "incomplete hardware"
	if int(summary.get("propeller_count", 0)) == 0:
		return "%s / articulated · %s kg · ground body" % [
			str(summary.get("core_name", "Core")),
			String.num(float(summary.get("mass_kg", 0.0)), 2),
		]
	return "%s / %s / %s · %s kg · %sx lift" % [
		str(summary.get("core_name", "Core")),
		str(summary.get("battery_name", "Battery")),
		str(summary.get("propeller_name", "Propeller")),
		String.num(float(summary.get("mass_kg", 0.0)), 2),
		String.num(float(summary.get("nominal_lift_to_weight", 0.0)), 2),
	]


func _build_worker_controls(content: VBoxContainer) -> void:
	var default_algorithm = _create_algorithm_preview(
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	)
	worker_count_slider = _add_group_slider(
		content,
		"Workers",
		1.0,
		float(default_algorithm.maximum_worker_count()),
		1.0,
		float(default_algorithm.default_worker_count()),
		"Number of physical workers collecting experience for the selected model. More workers collect data faster but use more CPU. Change this while paused.",
		func(value: float) -> void:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				return
			_set_selected_worker_count(int(round(value)))
	)
	worker_count_slider.drag_ended.connect(func(value_changed: bool) -> void:
		if not value_changed:
			return
		_set_selected_worker_count(int(round(worker_count_slider.value)))
	)
	control_rate_slider = _add_group_slider(
		content,
		"Control rate (Hz)",
		2.0,
		60.0,
		1.0,
		20.0,
		"How many times per simulated second the selected model chooses new body commands. The meaningful ceiling is 60 Hz because the room preserves a 60-step simulated physics clock even when accelerated.",
		func(value: float) -> void:
			_set_selected_control_rate(value)
	)


	var terminal_label: Label = Label.new()
	terminal_label.text = "Optional episode-ending rules"
	terminal_label.tooltip_text = (
		"These are artificial training cutoffs, not physical damage rules. "
		+ "They are disabled by default so ground bodies can tumble, roll, spin, recover, "
		+ "or intentionally use unusual orientations. Pause the group before changing them."
	)
	content.add_child(terminal_label)
	ground_contact_terminal_checkbox = CheckBox.new()
	ground_contact_terminal_checkbox.text = "End episode on low ground contact"
	ground_contact_terminal_checkbox.tooltip_text = (
		"Optional low-ground cutoff\n\n"
		+ "Off by default. A worker may touch, scrape, rest on, or move along the ground and "
		+ "continue learning. Ground-safety rewards can still discourage this behavior.\n\n"
		+ "On: the legacy center-height ground-crash rule ends the episode early. "
		+ "This is a training convenience only; it does not represent collision damage."
	)
	ground_contact_terminal_checkbox.toggled.connect(
		func(enabled: bool) -> void:
			_set_selected_episode_termination_option("ground_contact", enabled)
	)
	content.add_child(ground_contact_terminal_checkbox)
	flipped_terminal_checkbox = CheckBox.new()
	flipped_terminal_checkbox.text = "End episode when flipped"
	flipped_terminal_checkbox.tooltip_text = (
		"Optional orientation cutoff\n\n"
		+ "Off by default. A worker may run inverted, roll, spin like a top, or discover its "
		+ "own recovery strategy.\n\n"
		+ "On: remaining below the legacy uprightness threshold for "
		+ String.num(DroneTrainingEpisode.FLIPPED_DURATION_SECONDS, 2)
		+ " seconds ends the episode."
	)
	flipped_terminal_checkbox.toggled.connect(
		func(enabled: bool) -> void:
			_set_selected_episode_termination_option("flipped", enabled)
	)
	content.add_child(flipped_terminal_checkbox)


func _episode_termination_options_for_group(group: Dictionary) -> Dictionary:
	if group.is_empty():
		return DroneTrainingEpisode.DEFAULT_TERMINATION_OPTIONS.duplicate(true)
	return {
		"ground_contact": bool(group.get("episode_end_on_ground_contact", false)),
		"flipped": bool(group.get("episode_end_on_flipped", false)),
	}


func _episode_termination_options_for_trial(trial: Dictionary) -> Dictionary:
	if str(trial.get("mode", "")) == "algorithm_training":
		var group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
		return _episode_termination_options_for_group(group)
	var saved_value: Variant = trial.get("episode_termination", {})
	if saved_value is Dictionary:
		return (saved_value as Dictionary).duplicate(true)
	return DroneTrainingEpisode.DEFAULT_TERMINATION_OPTIONS.duplicate(true)


func _set_selected_episode_termination_option(option_id: String, enabled: bool) -> void:
	if suppress_ui_callbacks:
		return
	var group: Dictionary = _selected_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before changing its episode-ending rules." % group["name"]
		_refresh_selected_group_controls()
		return
	match option_id:
		"ground_contact":
			group["episode_end_on_ground_contact"] = enabled
		"flipped":
			group["episode_end_on_flipped"] = enabled
		_:
			return
	_clear_drone_group_runtime_for_configuration_change(group)
	var trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
	if trainer != null:
		trainer.set_evaluation_contract(
			_evaluation_contract_for_group_id(int(group.get("group_id", -1)), "drone")
		)
	_refresh_selected_group_controls()
	status_label.text = (
		"%s episode-ending rules updated. Resume the group to start with the new policy."
		% group["name"]
	)


func _load_episode_termination_options_into_group(
	group: Dictionary,
	environment: Dictionary
) -> void:
	if group.is_empty():
		return
	var saved_value: Variant = environment.get("episode_termination", {})
	if not (saved_value is Dictionary):
		group["episode_end_on_ground_contact"] = false
		group["episode_end_on_flipped"] = false
		return
	var saved: Dictionary = saved_value as Dictionary
	group["episode_end_on_ground_contact"] = bool(saved.get("ground_contact", false))
	group["episode_end_on_flipped"] = bool(saved.get("flipped", false))


func _build_algorithm_controls(content: VBoxContainer) -> void:
	algorithm_controls_body = content
	_rebuild_algorithm_controls(_create_algorithm_preview(
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	))


func _rebuild_algorithm_controls(algorithm: DroneTrainingAlgorithm) -> void:
	if algorithm_controls_body == null or algorithm == null:
		return
	for slider_value in algorithm_config_sliders.values():
		var old_slider = slider_value as HSlider
		if old_slider != null:
			selected_group_controls.erase(old_slider)
	algorithm_config_sliders.clear()
	for child in algorithm_controls_body.get_children():
		child.queue_free()
	algorithm_controls_id = algorithm.algorithm_id()
	var identity = Label.new()
	identity.text = "%s // %s" % [
		algorithm.algorithm_display_name(),
		algorithm.algorithm_id(),
	]
	identity.add_theme_color_override("font_color", Color("8de1ff"))
	identity.tooltip_text = _readable_tooltip(str(DroneTrainingAlgorithmCatalog.descriptor(
		algorithm.algorithm_id()
	).get("description", "")))
	algorithm_controls_body.add_child(identity)
	for control_definition: Dictionary in algorithm.configuration_controls():
		_add_algorithm_config_slider(
			algorithm_controls_body,
			control_definition,
			algorithm.config_values()
		)


func _rebuild_limb_algorithm_controls(trainer: FourLimbPPOTrainer) -> void:
	if algorithm_controls_body == null or trainer == null:
		return
	for slider_value in algorithm_config_sliders.values():
		var old_slider = slider_value as HSlider
		if old_slider != null:
			selected_group_controls.erase(old_slider)
	algorithm_config_sliders.clear()
	for child in algorithm_controls_body.get_children():
		child.queue_free()
	algorithm_controls_id = "limb:%s" % FourLimbPPOTrainer.ALGORITHM_ID
	var identity = Label.new()
	identity.text = "%s // %s" % [
		trainer.algorithm_display_name(),
		FourLimbPPOTrainer.ALGORITHM_ID,
	]
	identity.add_theme_color_override("font_color", Color("8de1ff"))
	identity.tooltip_text = "The four-limb trainer uses the same compact split-policy PPO architecture as the drone PPO path, with a stable behavior network and background optimizer network."
	algorithm_controls_body.add_child(identity)
	for control_definition: Dictionary in trainer.configuration_controls():
		_add_algorithm_config_slider(
			algorithm_controls_body,
			control_definition,
			trainer.config_values()
		)


func _rebuild_turret_algorithm_controls(trainer: TurretPPOTrainer) -> void:
	if algorithm_controls_body == null or trainer == null:
		return
	for slider_value in algorithm_config_sliders.values():
		var old_slider = slider_value as HSlider
		if old_slider != null:
			selected_group_controls.erase(old_slider)
	algorithm_config_sliders.clear()
	for child in algorithm_controls_body.get_children():
		child.queue_free()
	algorithm_controls_id = "turret:%s" % TurretPPOTrainer.ALGORITHM_ID
	var identity = Label.new()
	identity.text = "%s // %s" % [
		trainer.algorithm_display_name(),
		TurretPPOTrainer.ALGORITHM_ID,
	]
	identity.add_theme_color_override("font_color", Color("8de1ff"))
	identity.tooltip_text = "The stationary turret uses the same split behavior/optimizer PPO contract as the other physical workers, with three continuous actions: yaw drive, pitch drive, and trigger."
	algorithm_controls_body.add_child(identity)
	for control_definition: Dictionary in trainer.configuration_controls():
		_add_algorithm_config_slider(
			algorithm_controls_body,
			control_definition,
			trainer.config_values()
		)


func _sync_right_workspace_minimum_height() -> void:
	if right_panel_body == null or right_content == null:
		return
	# ScrollContainer children otherwise shrink to their content height. Matching the current
	# viewport guarantees that workspace pages, especially Rewards, consume the full panel
	# while still allowing the outer scrollbar when their content is taller than the panel.
	right_content.custom_minimum_size.y = maxf(right_panel_body.size.y, 0.0)


func _build_model_controls(content: VBoxContainer) -> void:
	var save_row = HFlowContainer.new()
	save_row.add_theme_constant_override("h_separation", 7)
	save_row.add_theme_constant_override("v_separation", 7)
	content.add_child(save_row)
	model_save_best_button = _button("SAVE BEST", true)
	model_save_best_button.tooltip_text = "Save best known model\n\nWrites the best policy snapshot this group has preserved.\nUse Save Current when you specifically want the live weights instead."
	model_save_best_button.pressed.connect(_save_selected_model_best)
	save_row.add_child(model_save_best_button)
	model_save_current_button = _button("SAVE CURRENT")
	model_save_current_button.tooltip_text = "Save current live model\n\nWrites the weights controlling the selected group right now."
	model_save_current_button.pressed.connect(_save_selected_model_current)
	save_row.add_child(model_save_current_button)
	model_library_button = _button("MODEL LIBRARY")
	model_library_button.tooltip_text = "Open the selected body's model library. Drone, four-limb, and turret checkpoints remain completely separate."
	model_library_button.pressed.connect(_open_selected_model_library)
	content.add_child(model_library_button)


func _save_selected_model_best() -> void:
	var turret_group = _selected_turret_group()
	if not turret_group.is_empty():
		turret_ui.save_group(int(turret_group["group_id"]), str(turret_group["name"]), true)
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		_save_limb_group(int(limb_group["group_id"]), str(limb_group["name"]), true)
		return
	_save_selected_group_best()


func _save_selected_model_current() -> void:
	var turret_group = _selected_turret_group()
	if not turret_group.is_empty():
		turret_ui.save_group(int(turret_group["group_id"]), str(turret_group["name"]), false)
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		_save_limb_group(int(limb_group["group_id"]), str(limb_group["name"]), false)
		return
	_save_selected_group_current()


func _open_selected_model_library() -> void:
	if not _selected_turret_group().is_empty():
		turret_ui.open_model_browser()
		return
	if not _selected_limb_group().is_empty():
		_open_limb_model_browser()
		return
	_open_model_browser(selected_group_id)


func _refresh_model_workspace_for_selection(
	has_drone_group: bool,
	has_limb_group: bool,
	has_turret_group: bool
) -> void:
	if selected_group_branch_button != null:
		selected_group_branch_button.visible = has_drone_group or has_limb_group or has_turret_group
	if selected_group_root_button != null:
		selected_group_root_button.visible = false
	if selected_group_distribute_button != null:
		selected_group_distribute_button.visible = has_drone_group
	var has_any_group = has_drone_group or has_limb_group or has_turret_group
	if model_save_best_button != null:
		model_save_best_button.visible = has_any_group
		model_save_best_button.text = "SAVE BEST"
	if model_save_current_button != null:
		model_save_current_button.visible = has_any_group
	if model_library_button != null:
		model_library_button.visible = has_any_group
		model_library_button.text = (
			"TURRET MODEL LIBRARY"
			if has_turret_group
			else ("LIMB MODEL LIBRARY" if has_limb_group else "MODEL LIBRARY")
		)


func _refresh_tuning_sections(
	has_drone_group: bool,
	has_limb_group: bool,
	has_turret_group: bool
) -> void:
	_set_section_body_card_visible(drone_loadout_body, has_drone_group)
	_set_section_body_card_visible(limb_body_tuning_body, has_limb_group)
	if not has_turret_group and turret_ui.tuning_body != null:
		_set_section_body_card_visible(turret_ui.tuning_body, false)
	turret_ui.refresh_selection()


func _set_section_body_card_visible(body: VBoxContainer, visible: bool) -> void:
	if body == null:
		return
	var shell = body.get_parent() as Control
	if shell == null:
		return
	var card = shell.get_parent() as Control
	if card != null:
		card.visible = visible


func _refresh_limb_body_tuning_summary() -> void:
	if limb_body_tuning_label == null:
		return
	var definition = _selected_limb_body_definition()
	if definition == null:
		limb_body_tuning_label.text = "The four-limb physical definition is unavailable."
		return
	definition.ensure_contract()
	var total_mass = definition.core_mass
	var installed_limbs = 0
	var upper_length = 0.0
	var lower_length = 0.0
	for limb: FourLimbSlotDefinition in definition.limbs:
		if limb == null or not limb.installed:
			continue
		installed_limbs += 1
		total_mass += limb.segment_mass * 2.0
		upper_length = maxf(upper_length, limb.upper_length)
		lower_length = maxf(lower_length, limb.lower_length)
	var limb_health = 0.0
	if not definition.limbs.is_empty() and definition.limbs[0] != null:
		limb_health = definition.limbs[0].maximum_health
	var selected_group = _selected_limb_group()
	var editing_status = (
		"PAUSE THIS GROUP TO EDIT ITS BODY."
		if bool(selected_group.get("active", false))
		else "BODY EDITING ENABLED · workers rebuild when the group resumes."
	)
	limb_body_tuning_label.text = (
		"%s\n%d radial limbs · %d joint + %d grip outputs\n"
		+ "Core %.2f × %.2f × %.2f m · estimated body mass %.2f kg\n"
		+ "Leg reach %.2f m (%.2f + %.2f) · hip torque %.1f · knee torque %.1f\n"
		+ "Passive joint spring %.1f Nm/rad · damping %.1f · cap %.1f Nm\n"
		+ "Progressive resistance ×%.1f after %.0f%% of range · native solver share %.0f%%\n"
		+ "Training health %.0f core / %.0f per limb · damage immune"
	) % [
		editing_status,
		installed_limbs,
		FourLimbMLAction.JOINT_ACTION_COUNT,
		FourLimbMLAction.LIMB_COUNT,
		definition.core_size.x,
		definition.core_size.y,
		definition.core_size.z,
		total_mass,
		upper_length + lower_length,
		upper_length,
		lower_length,
		definition.maximum_hip_torque,
		definition.maximum_knee_torque,
		definition.passive_joint_stiffness,
		definition.passive_joint_damping,
		definition.maximum_passive_joint_torque,
		definition.passive_joint_progressive_ratio,
		definition.passive_joint_progressive_onset_ratio * 100.0,
		definition.passive_joint_native_fraction * 100.0,
		definition.core_maximum_health,
		limb_health,
	]


func _build_limb_body_controls(parent: VBoxContainer) -> void:
	var reset_button = _button("RESTORE WALKER PRESET")
	reset_button.tooltip_text = "Restore Four-Limb Walker preset\n\nReplaces this paused group's body with a fresh Four-Limb Walker creator preset. Other limb groups are not changed."
	reset_button.pressed.connect(_reset_selected_limb_body)
	parent.add_child(reset_button)
	limb_body_edit_controls.append(reset_button)

	var core = _add_section(
		parent,
		"CORE PHYSICS",
		"Dimensions, mass, contact material and damping for the central rigid body.",
		false
	)
	_add_limb_body_input(core, "Core width", "body:core_size:x", 0.1, 4.0, 0.01, " m", "Physical width along the local X axis.")
	_add_limb_body_input(core, "Core height", "body:core_size:y", 0.1, 4.0, 0.01, " m", "Physical thickness along the local Y axis.")
	_add_limb_body_input(core, "Core length", "body:core_size:z", 0.1, 4.0, 0.01, " m", "Physical length along the local Z axis.")
	_add_limb_body_input(core, "Core mass", "body:core_mass", 0.1, 100.0, 0.05, " kg", "Mass of the central body before limb segments are added.")
	_add_limb_body_input(core, "Friction", "body:friction", 0.0, 1.0, 0.01, "", "Contact friction shared by the body and limb segments.")
	_add_limb_body_input(core, "Bounce", "body:bounce", 0.0, 1.0, 0.01, "", "Restitution used by the physical body.")
	_add_limb_body_input(core, "Linear damping", "body:linear_damp", 0.0, 20.0, 0.05, "", "Passive damping applied to translational movement.")
	_add_limb_body_input(core, "Angular damping", "body:angular_damp", 0.0, 20.0, 0.05, "", "Passive damping applied to body rotation.")

	var actuators = _add_section(
		parent,
		"JOINT ACTUATORS",
		"PD stiffness, damping and torque limits used by all four hip and knee drives.",
		false
	)
	_add_limb_body_input(actuators, "Hip stiffness", "body:hip_stiffness", 0.0, 1000.0, 0.5, "", "How strongly hips move toward the policy target.")
	_add_limb_body_input(actuators, "Hip damping", "body:hip_damping", 0.0, 100.0, 0.1, "", "Velocity damping in each hip drive.")
	_add_limb_body_input(actuators, "Maximum hip torque", "body:maximum_hip_torque", 0.0, 10000.0, 1.0, "", "Maximum torque available to each hip axis.")
	_add_limb_body_input(actuators, "Horizontal hip response", "body:hip_horizontal_response_degrees_per_second", 0.0, 1440.0, 1.0, "°/s", "Maximum target slew for horizontal coxa sweep only. Lower values calm side-to-side reaction torque without slowing hip elevation or knee bend.")
	_add_limb_body_input(actuators, "Knee stiffness", "body:knee_stiffness", 0.0, 1000.0, 0.5, "", "How strongly knees move toward the policy target.")
	_add_limb_body_input(actuators, "Knee damping", "body:knee_damping", 0.0, 100.0, 0.1, "", "Velocity damping in each knee drive.")
	_add_limb_body_input(actuators, "Maximum knee torque", "body:maximum_knee_torque", 0.0, 10000.0, 1.0, "", "Maximum torque available to each knee.")
	_add_limb_body_input(actuators, "Joint-limit soft zone", "body:joint_limit_soft_zone_degrees", 0.0, 45.0, 0.25, "°", "Starts a separate restoring torque before a knee reaches its physical hinge stop.")
	_add_limb_body_input(actuators, "Joint-limit stiffness", "body:joint_limit_stiffness", 0.0, 5000.0, 1.0, "", "Strength of the independent anatomical hard-stop controller.")
	_add_limb_body_input(actuators, "Joint-limit damping", "body:joint_limit_damping", 0.0, 500.0, 0.25, "", "Brakes a knee that is moving toward or through an anatomical limit.")
	_add_limb_body_input(actuators, "Maximum limit torque", "body:maximum_joint_limit_torque", 0.0, 10000.0, 1.0, "", "Torque cap reserved for enforcing hinge limits. The policy cannot command around it.")

	var stance = _add_section(
		parent,
		"PASSIVE LIMB ELASTICITY",
		"Permanent rubber-like joint impedance around the authored pose. It stays active without policy input and resists model commands more strongly as a limb bends away from rest.",
		false
	)
	_add_limb_body_input(stance, "Passive joint stiffness", "body:passive_joint_stiffness", 0.0, 1000.0, 0.5, " Nm/rad", "Restoring torque per radian away from the authored neutral hip or knee pose.")
	_add_limb_body_input(stance, "Passive joint damping", "body:passive_joint_damping", 0.0, 100.0, 0.1, " Nms/rad", "Resistance to joint angular velocity so the elastic limb settles instead of oscillating.")
	_add_limb_body_input(stance, "Maximum passive joint torque", "body:maximum_passive_joint_torque", 0.0, 10000.0, 1.0, " Nm", "Torque cap for passive elasticity. Policy torque is separate and must work against this spring.")
	_add_limb_body_input(stance, "Progressive onset", "body:passive_joint_progressive_onset_ratio", 0.0, 0.95, 0.01, " × range", "Fraction of the allowed joint range where the rubber-like spring begins hardening progressively.")
	_add_limb_body_input(stance, "Progressive resistance", "body:passive_joint_progressive_ratio", 0.0, 50.0, 0.1, " ×", "Additional nonlinear stiffness near the edge of the authored range. Higher values prevent flat noodle-like folding while leaving the center compliant.")
	_add_limb_body_input(stance, "Native solver share", "body:passive_joint_native_fraction", 0.0, 1.0, 0.01, " ×", "Fraction of baseline passive stiffness handled directly by Jolt's joint spring. The controller supplies the remaining bounded resistance and all progressive hardening.")

	var walker_preset_definition = MLBodyPresetLibrary.four_limb_walker_definition()
	walker_preset_definition.ensure_contract()
	for limb_index in range(FourLimbBodyDefinition.LIMB_SLOT_COUNT):
		var preset_limb = walker_preset_definition.limbs[limb_index]
		var limb_name = preset_limb.slot_name if preset_limb != null else "Limb %d" % (limb_index + 1)
		var limb_body = _add_section(
			parent,
			str(limb_name).to_upper(),
			"Private geometry and joint limits for this limb slot. Mount and rest offsets are relative to the core.",
			false
		)
		var prefix = "limb:%d:" % limb_index
		_add_limb_body_input(limb_body, "Hip mount X", prefix + "hip_offset:x", -4.0, 4.0, 0.01, " m", "Lateral mount position on the core.")
		_add_limb_body_input(limb_body, "Hip mount Y", prefix + "hip_offset:y", -4.0, 4.0, 0.01, " m", "Vertical mount position on the core.")
		_add_limb_body_input(limb_body, "Hip mount Z", prefix + "hip_offset:z", -4.0, 4.0, 0.01, " m", "Forward/back mount position on the core.")
		_add_limb_body_input(limb_body, "Rest foot X", prefix + "rest_foot_offset:x", -6.0, 6.0, 0.01, " m", "Desired neutral foot position relative to the core.")
		_add_limb_body_input(limb_body, "Rest foot Y", prefix + "rest_foot_offset:y", -6.0, 6.0, 0.01, " m", "Desired neutral foot height relative to the core.")
		_add_limb_body_input(limb_body, "Rest foot Z", prefix + "rest_foot_offset:z", -6.0, 6.0, 0.01, " m", "Desired neutral foot forward/back position.")
		_add_limb_body_input(limb_body, "Upper length", prefix + "upper_length", 0.1, 4.0, 0.01, " m", "Length of the upper physical segment.")
		_add_limb_body_input(limb_body, "Lower length", prefix + "lower_length", 0.1, 4.0, 0.01, " m", "Length of the lower physical segment.")
		_add_limb_body_input(limb_body, "Segment radius", prefix + "segment_radius", 0.02, 0.5, 0.005, " m", "Collision and visual radius of both segments.")
		_add_limb_body_input(limb_body, "Segment mass", prefix + "segment_mass", 0.01, 100.0, 0.01, " kg", "Mass of each of this limb's two segments.")
		_add_limb_body_input(limb_body, "Hip elevation span", prefix + "hip_swing_span_degrees", 1.0, 90.0, 0.5, "°", "Symmetric radial raise/lower range around the neutral leg pose. Existing saved bodies keep this behavior.")
		_add_limb_body_input(limb_body, "Extra upward hip lift", prefix + "hip_elevation_upper_extension_degrees", 0.0, 60.0, 0.5, "°", "Additional positive radial elevation only. The Four-Limb Walker preset uses this to let a direct hip command lift a limb above the core without increasing the downward range.")
		_add_limb_body_input(limb_body, "Hip horizontal sweep", prefix + "hip_twist_span_degrees", 1.0, 90.0, 0.5, "°", "Allowed horizontal sweep of the complete upper leg around the body.")
		_add_limb_body_input(limb_body, "Knee lower limit", prefix + "knee_limit_lower_degrees", -20.0, -1.0, 0.5, "°", "Small backward straightening allowance. The anatomy contract prevents a knee from folding through itself.")
		_add_limb_body_input(limb_body, "Knee upper limit", prefix + "knee_limit_upper_degrees", 15.0, 120.0, 0.5, "°", "Maximum forward knee bend.")


func _add_limb_body_input(
	parent: VBoxContainer,
	title: String,
	property_path: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String,
	tooltip: String
) -> SpinBox:
	var input = _add_number_input(
		parent,
		title,
		minimum,
		maximum,
		step,
		0.0,
		suffix,
		tooltip,
		func(value: float) -> void:
			if not suppress_ui_callbacks:
				_set_selected_limb_body_value(property_path, value)
	)
	limb_body_stat_inputs[property_path] = input
	limb_body_edit_controls.append(input)
	return input


func _selected_limb_body_definition() -> FourLimbBodyDefinition:
	var group = _selected_limb_group()
	if group.is_empty():
		return null
	return limb_training.group_body_definition(int(group["group_id"]))


func _set_selected_limb_body_value(property_path: String, value: float) -> void:
	var group = _selected_limb_group()
	if group.is_empty():
		return
	if bool(group.get("active", false)):
		status_label.text = "Pause %s before changing its physical body." % group["name"]
		_refresh_limb_body_tuning_controls()
		return
	var source = _selected_limb_body_definition()
	if source == null:
		return
	var definition = source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as FourLimbBodyDefinition
	var parts = property_path.split(":", false)
	var changed = false
	if parts.size() >= 2 and parts[0] == "body":
		changed = _set_limb_definition_property(definition, parts, value)
	elif parts.size() >= 3 and parts[0] == "limb":
		var limb_index = int(parts[1])
		if limb_index >= 0 and limb_index < definition.limbs.size():
			var limb = definition.limbs[limb_index]
			if limb != null:
				changed = _set_limb_slot_property(limb, parts, value)
	if not changed:
		status_label.text = "Could not change four-limb property %s." % property_path
		_refresh_limb_body_tuning_controls()
		return
	if not limb_training.replace_group_body_definition(int(group["group_id"]), definition):
		status_label.text = limb_training.last_error
		_refresh_limb_body_tuning_controls()
		return
	_refresh_limb_body_tuning_controls()
	_refresh_limb_body_tuning_summary()
	_refresh_group_card_texts()
	status_label.text = "%s body updated. Resume the group to rebuild workers with the new anatomy." % group["name"]


func _set_limb_definition_property(
	definition: FourLimbBodyDefinition,
	parts: PackedStringArray,
	value: float
) -> bool:
	var property_name = str(parts[1])
	if property_name == "core_size" and parts.size() >= 3:
		definition.core_size = _vector_with_axis(definition.core_size, str(parts[2]), value)
		return true
	if property_name in [
		"core_mass", "friction", "bounce", "linear_damp", "angular_damp",
		"hip_stiffness", "hip_damping", "maximum_hip_torque",
		"hip_horizontal_response_degrees_per_second",
		"knee_stiffness", "knee_damping", "maximum_knee_torque",
		"joint_limit_soft_zone_degrees", "joint_limit_stiffness",
		"joint_limit_damping", "maximum_joint_limit_torque",
		"passive_joint_stiffness", "passive_joint_damping",
		"maximum_passive_joint_torque"
	]:
		definition.set(property_name, value)
		return true
	return false


func _set_limb_slot_property(
	limb: FourLimbSlotDefinition,
	parts: PackedStringArray,
	value: float
) -> bool:
	var property_name = str(parts[2])
	if property_name in ["hip_offset", "rest_foot_offset"] and parts.size() >= 4:
		var vector_value = (
			limb.hip_offset
			if property_name == "hip_offset"
			else limb.rest_foot_offset
		)
		vector_value = _vector_with_axis(vector_value, str(parts[3]), value)
		if property_name == "hip_offset":
			limb.hip_offset = vector_value
		else:
			limb.rest_foot_offset = vector_value
		return true
	if property_name in [
		"upper_length", "lower_length", "segment_radius", "segment_mass",
		"hip_swing_span_degrees", "hip_elevation_upper_extension_degrees",
		"hip_twist_span_degrees", "knee_limit_lower_degrees",
		"knee_limit_upper_degrees"
	]:
		limb.set(property_name, value)
		return true
	return false


func _vector_with_axis(source: Vector3, axis: String, value: float) -> Vector3:
	match axis:
		"x":
			source.x = value
		"y":
			source.y = value
		"z":
			source.z = value
	return source


func _limb_body_property_value(
	definition: FourLimbBodyDefinition,
	property_path: String
) -> float:
	var parts = property_path.split(":", false)
	if parts.size() >= 2 and parts[0] == "body":
		var property_name = str(parts[1])
		if property_name == "core_size" and parts.size() >= 3:
			return _vector_axis(definition.core_size, str(parts[2]))
		return float(definition.get(property_name))
	if parts.size() >= 3 and parts[0] == "limb":
		var limb_index = int(parts[1])
		if limb_index < 0 or limb_index >= definition.limbs.size():
			return 0.0
		var limb = definition.limbs[limb_index]
		if limb == null:
			return 0.0
		var limb_property_name = str(parts[2])
		if limb_property_name in ["hip_offset", "rest_foot_offset"] and parts.size() >= 4:
			var vector_value = (
				limb.hip_offset
				if limb_property_name == "hip_offset"
				else limb.rest_foot_offset
			)
			return _vector_axis(vector_value, str(parts[3]))
		return float(limb.get(limb_property_name))
	return 0.0


func _vector_axis(value: Vector3, axis: String) -> float:
	match axis:
		"x":
			return value.x
		"y":
			return value.y
		"z":
			return value.z
	return 0.0


func _refresh_limb_body_tuning_controls() -> void:
	var group = _selected_limb_group()
	var definition = _selected_limb_body_definition()
	var editable = not group.is_empty() and not bool(group.get("active", false))
	for control in limb_body_edit_controls:
		if control is SpinBox:
			(control as SpinBox).editable = editable
		elif control is BaseButton:
			(control as BaseButton).disabled = not editable
	if definition == null:
		return
	suppress_ui_callbacks = true
	for property_path: String in limb_body_stat_inputs:
		var input = limb_body_stat_inputs[property_path] as SpinBox
		if input != null:
			input.value = _limb_body_property_value(definition, property_path)
	suppress_ui_callbacks = false


func _reset_selected_limb_body() -> void:
	var group = _selected_limb_group()
	if group.is_empty():
		return
	if not limb_training.reset_group_body_definition(int(group["group_id"])):
		status_label.text = limb_training.last_error
		return
	_refresh_limb_body_tuning_controls()
	_refresh_limb_body_tuning_summary()
	_refresh_group_card_texts()
	status_label.text = "%s restored to the Four-Limb Walker preset." % group["name"]


func _build_reward_card_workspace(parent: VBoxContainer) -> void:
	parent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reward_card_note = Label.new()
	reward_card_note.text = "Select a drone, four-limb, or turret worker group. Changes apply at that group's next episode."
	reward_card_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_card_note.add_theme_color_override("font_color", Color("5ab889"))
	parent.add_child(reward_card_note)

	var preset_panel = PanelContainer.new()
	preset_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	parent.add_child(preset_panel)
	var preset_content = VBoxContainer.new()
	preset_content.add_theme_constant_override("separation", 6)
	preset_panel.add_child(preset_content)
	var preset_heading = Label.new()
	preset_heading.text = "REWARD CARDSETS"
	preset_heading.add_theme_color_override("font_color", Color("8de1ff"))
	preset_content.add_child(preset_heading)
	reward_cardset_tabs = TabBar.new()
	reward_cardset_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_cardset_tabs.tooltip_text = "Select a tab to queue every reward switch and slider value from that cardset."
	reward_cardset_tabs.tab_changed.connect(_on_reward_cardset_tab_changed)
	preset_content.add_child(reward_cardset_tabs)
	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	preset_content.add_child(save_row)
	reward_cardset_name_input = LineEdit.new()
	reward_cardset_name_input.placeholder_text = "Preset name"
	reward_cardset_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_cardset_name_input.tooltip_text = "Save the currently visible switches and slider values as a reusable tab. A matching name updates that preset."
	save_row.add_child(reward_cardset_name_input)
	var save_button = Button.new()
	save_button.text = "SAVE CURRENT"
	save_button.tooltip_text = reward_cardset_name_input.tooltip_text
	save_button.pressed.connect(_save_current_reward_cardset)
	save_row.add_child(save_button)
	reward_cardset_delete_button = Button.new()
	reward_cardset_delete_button.text = "DELETE TAB"
	reward_cardset_delete_button.disabled = true
	reward_cardset_delete_button.tooltip_text = "Delete the selected user preset. Built-in cardsets cannot be deleted."
	reward_cardset_delete_button.pressed.connect(_delete_selected_reward_cardset)
	save_row.add_child(reward_cardset_delete_button)

	# The complete right panel already has a ScrollContainer. Let the reward list expand inside
	# that workspace instead of introducing a second fixed-height scroller.
	reward_card_list = VBoxContainer.new()
	reward_card_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_card_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reward_card_list.add_theme_constant_override("separation", 7)
	parent.add_child(reward_card_list)


func _rebuild_reward_cards() -> void:
	if reward_card_list == null:
		return
	for child in reward_card_list.get_children():
		child.queue_free()
	reward_card_value_labels.clear()
	reward_card_intensity_labels.clear()
	var group = _selected_any_training_group()
	_refresh_reward_card_note(group)
	_rebuild_reward_cardset_tabs(group)
	if group.is_empty():
		reward_card_refresh_signature = "none"
		var empty_label = Label.new()
		empty_label.text = "Select a worker group to edit its reward and punishment cards."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_card_list.add_child(empty_label)
		return
	var deck = _reward_deck_for_group(group)
	if deck == null:
		reward_card_refresh_signature = _reward_card_group_signature(group)
		var unavailable_label = Label.new()
		unavailable_label.text = "This worker group has no compatible reward-card deck."
		unavailable_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_card_list.add_child(unavailable_label)
		return
	var body_type = str(group.get("body_type", "drone"))
	var group_id = int(group.get("group_id", -1))
	var pending: Dictionary = group.get("pending_reward_config", {})
	var cards: Array = deck.call("card_list")
	for card_variant: Variant in cards:
		var card_value = card_variant as FourLimbRewardCard
		if card_value == null:
			continue
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override(
			"panel",
			DroneTrainingRoomPresentation.reward_card_panel_style(card_value.signal_type)
		)
		reward_card_list.add_child(panel)
		var content = VBoxContainer.new()
		content.add_theme_constant_override("separation", 5)
		panel.add_child(content)
		var pending_card: Dictionary = pending.get(card_value.card_id, {})
		var header = HBoxContainer.new()
		header.add_theme_constant_override("separation", 7)
		content.add_child(header)
		var enabled = CheckButton.new()
		enabled.text = card_value.display_name
		enabled.button_pressed = bool(pending_card.get("enabled", card_value.enabled))
		enabled.tooltip_text = _readable_tooltip(card_value.explanation)
		enabled.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(enabled)
		var signal_label = Label.new()
		signal_label.text = card_value.signal_label()
		signal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		signal_label.add_theme_color_override(
			"font_color",
			DroneTrainingRoomPresentation.reward_signal_color(card_value.signal_type)
		)
		header.add_child(signal_label)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		content.add_child(row)
		var slider = HSlider.new()
		slider.min_value = card_value.minimum_intensity
		slider.max_value = card_value.maximum_intensity
		slider.step = card_value.step
		slider.value = float(pending_card.get("intensity", card_value.intensity))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size.y = 24.0
		slider.tooltip_text = "%s\n\nSlider range: %.4f to %.4f" % [
			enabled.tooltip_text,
			card_value.minimum_intensity,
			card_value.maximum_intensity,
		]
		row.add_child(slider)
		var value_label = Label.new()
		value_label.text = _reward_card_intensity_text(slider.value, card_value.maximum_intensity)
		value_label.set_meta("maximum_intensity", card_value.maximum_intensity)
		value_label.custom_minimum_size.x = 118.0
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value_label)
		var contribution_label = Label.new()
		contribution_label.text = "Now +0.0000 · Episode +0.000"
		contribution_label.add_theme_color_override("font_color", Color("8aaea1"))
		content.add_child(contribution_label)
		var card_id = card_value.card_id
		reward_card_value_labels[card_id] = contribution_label
		reward_card_intensity_labels[card_id] = value_label
		enabled.toggled.connect(
			_on_reward_card_enabled_toggled.bind(body_type, group_id, card_id)
		)
		slider.value_changed.connect(
			_on_reward_card_intensity_changed.bind(body_type, group_id, card_id)
		)
	reward_card_refresh_signature = _reward_card_group_signature(group)
	_refresh_reward_card_values()


func _reward_card_intensity_text(value: float, maximum: float) -> String:
	return "×%.3f / %.3f" % [value, maximum]


func _rebuild_reward_cardset_tabs(group: Dictionary) -> void:
	if reward_cardset_tabs == null:
		return
	suppress_reward_cardset_tab_signal = true
	reward_cardset_tabs.clear_tabs()
	reward_cardset_records.clear()
	if group.is_empty():
		if reward_cardset_name_input != null:
			reward_cardset_name_input.editable = false
			reward_cardset_name_input.text = ""
		if reward_cardset_delete_button != null:
			reward_cardset_delete_button.disabled = true
		suppress_reward_cardset_tab_signal = false
		return
	var body_type = str(group.get("body_type", "drone"))
	reward_cardset_records.append({
		"id": "custom",
		"display_name": "Custom",
		"body_type": body_type,
		"cards": {},
		"builtin": true,
	})
	for record: Dictionary in reward_cardset_library.cardsets_for_body_type(body_type):
		reward_cardset_records.append(record)
	for record: Dictionary in reward_cardset_records:
		reward_cardset_tabs.add_tab(str(record.get("display_name", "Preset")))
	var effective_configuration = _effective_reward_card_configuration(group)
	var preferred_id = str(group.get(
		"pending_reward_cardset_id",
		group.get("reward_cardset_id", "")
	))
	var selected_index = 0
	for index in range(1, reward_cardset_records.size()):
		var record: Dictionary = reward_cardset_records[index]
		var cards_value: Variant = record.get("cards", {})
		if not (cards_value is Dictionary):
			continue
		var cards = cards_value as Dictionary
		if (
			str(record.get("id", "")) == preferred_id
			and TrainingRewardCardsetLibrary.configurations_match(
				cards,
				effective_configuration
			)
		):
			selected_index = index
			break
	if selected_index == 0:
		var matching_id = reward_cardset_library.matching_cardset_id(
			body_type,
			effective_configuration
		)
		for index in range(1, reward_cardset_records.size()):
			if str(reward_cardset_records[index].get("id", "")) == matching_id:
				selected_index = index
				break
	if not reward_cardset_records.is_empty():
		reward_cardset_tabs.current_tab = selected_index
	_update_reward_cardset_controls(selected_index)
	if reward_cardset_name_input != null:
		reward_cardset_name_input.editable = true
	suppress_reward_cardset_tab_signal = false


func _update_reward_cardset_controls(index: int) -> void:
	var record: Dictionary = (
		reward_cardset_records[index]
		if index >= 0 and index < reward_cardset_records.size()
		else {}
	)
	var record_id = str(record.get("id", ""))
	var custom_saved = not bool(record.get("builtin", true)) and record_id.begins_with("user:")
	if reward_cardset_delete_button != null:
		reward_cardset_delete_button.disabled = not custom_saved
	if reward_cardset_name_input != null:
		reward_cardset_name_input.text = (
			str(record.get("display_name", ""))
			if custom_saved
			else ""
		)


func _on_reward_cardset_tab_changed(index: int) -> void:
	if suppress_reward_cardset_tab_signal:
		return
	_update_reward_cardset_controls(index)
	if index <= 0 or index >= reward_cardset_records.size():
		return
	var group = _selected_any_training_group()
	if group.is_empty():
		return
	var record: Dictionary = reward_cardset_records[index]
	_queue_reward_cardset(group, record)
	status_label.text = "%s queued for %s's next episode." % [
		str(record.get("display_name", "Reward cardset")),
		str(group.get("name", "selected group")),
	]
	_rebuild_reward_cards()


func _queue_reward_cardset(group: Dictionary, record: Dictionary) -> void:
	var configuration_value: Variant = record.get("cards", {})
	if not (configuration_value is Dictionary):
		return
	var configuration = configuration_value as Dictionary
	var deck = _reward_deck_for_group(group)
	if deck == null or configuration.is_empty():
		return
	var pending = {}
	var cards: Array = deck.call("card_list")
	for card_variant: Variant in cards:
		var card_value = card_variant as FourLimbRewardCard
		if card_value == null:
			continue
		var configured: Variant = configuration.get(card_value.card_id, {})
		if not (configured is Dictionary):
			continue
		var values = configured as Dictionary
		var safe_intensity = RLTrainingMath.finite_float_or(
			values.get("intensity", card_value.intensity),
			card_value.intensity
		)
		pending[card_value.card_id] = {
			"enabled": RLTrainingMath.bool_or(
				values.get("enabled", card_value.enabled),
				card_value.enabled
			),
			"intensity": clampf(
				safe_intensity,
				card_value.minimum_intensity,
				card_value.maximum_intensity
			),
		}
	group["pending_reward_config"] = pending
	group["pending_reward_cardset_id"] = str(record.get("id", "custom"))
	group["pending_reward_cardset_name"] = str(record.get("display_name", "Custom"))
	_refresh_reward_card_note(group)


func _effective_reward_card_configuration(group: Dictionary) -> Dictionary:
	var deck = _reward_deck_for_group(group)
	if deck == null:
		return {}
	var deck_configuration: Variant = deck.call("configuration_dictionary")
	if not (deck_configuration is Dictionary):
		return {}
	var result: Dictionary = (deck_configuration as Dictionary).duplicate(true)
	var pending: Dictionary = group.get("pending_reward_config", {})
	for card_id: String in pending:
		if not result.has(card_id):
			continue
		var current: Dictionary = (result[card_id] as Dictionary).duplicate(true)
		var values: Dictionary = pending[card_id]
		if values.has("enabled"):
			current["enabled"] = bool(values["enabled"])
		if values.has("intensity"):
			current["intensity"] = float(values["intensity"])
		result[card_id] = current
	return result


func _save_current_reward_cardset() -> void:
	var group = _selected_any_training_group()
	if group.is_empty():
		status_label.text = "Select a drone, four-limb, or turret worker group first."
		return
	var preset_name = (
		reward_cardset_name_input.text.strip_edges()
		if reward_cardset_name_input != null
		else ""
	)
	var record = reward_cardset_library.save_custom_cardset(
		str(group.get("body_type", "drone")),
		preset_name,
		_effective_reward_card_configuration(group)
	)
	if record.is_empty():
		status_label.text = reward_cardset_library.last_error
		return
	if (group.get("pending_reward_config", {}) as Dictionary).is_empty():
		group["reward_cardset_id"] = str(record.get("id", "custom"))
		group["reward_cardset_name"] = str(record.get("display_name", preset_name))
		group.erase("pending_reward_cardset_id")
		group.erase("pending_reward_cardset_name")
	else:
		group["pending_reward_cardset_id"] = str(record.get("id", "custom"))
		group["pending_reward_cardset_name"] = str(record.get("display_name", preset_name))
	status_label.text = "Saved reward cardset %s." % str(record.get("display_name", preset_name))
	_rebuild_reward_cards()


func _delete_selected_reward_cardset() -> void:
	if reward_cardset_tabs == null:
		return
	var index = reward_cardset_tabs.current_tab
	if index <= 0 or index >= reward_cardset_records.size():
		return
	var record: Dictionary = reward_cardset_records[index]
	if bool(record.get("builtin", true)):
		return
	var group = _selected_any_training_group()
	var body_type = str(record.get("body_type", group.get("body_type", "drone")))
	if not reward_cardset_library.delete_custom_cardset(
		body_type,
		str(record.get("id", ""))
	):
		status_label.text = reward_cardset_library.last_error
		return
	_forget_deleted_reward_cardset(body_type, str(record.get("id", "")))
	status_label.text = "Deleted reward cardset %s." % str(record.get("display_name", "Preset"))
	_rebuild_reward_cards()


func _forget_deleted_reward_cardset(body_type: String, cardset_id: String) -> void:
	var affected_groups: Array[Dictionary] = []
	match body_type:
		TrainingRewardCardsetLibrary.BODY_TYPE_FOUR_LIMB:
			for limb_group: Dictionary in limb_training.groups:
				affected_groups.append(limb_group)
		TrainingRewardCardsetLibrary.BODY_TYPE_TURRET:
			for turret_group: Dictionary in turret_training.groups:
				affected_groups.append(turret_group)
		_:
			for drone_group: Dictionary in worker_groups:
				affected_groups.append(drone_group)
	for affected_group: Dictionary in affected_groups:
		var effective_id = str(affected_group.get(
			"pending_reward_cardset_id",
			affected_group.get("reward_cardset_id", "")
		))
		if effective_id != cardset_id:
			continue
		if (affected_group.get("pending_reward_config", {}) as Dictionary).is_empty():
			affected_group["reward_cardset_id"] = "custom"
			affected_group["reward_cardset_name"] = "Custom"
			affected_group.erase("pending_reward_cardset_id")
			affected_group.erase("pending_reward_cardset_name")
		else:
			affected_group["pending_reward_cardset_id"] = "custom"
			affected_group["pending_reward_cardset_name"] = "Custom"


func _mark_reward_cardset_custom(group: Dictionary) -> void:
	group["pending_reward_cardset_id"] = "custom"
	group["pending_reward_cardset_name"] = "Custom"
	if reward_cardset_tabs != null and reward_cardset_tabs.get_tab_count() > 0:
		suppress_reward_cardset_tab_signal = true
		reward_cardset_tabs.current_tab = 0
		suppress_reward_cardset_tab_signal = false
	_update_reward_cardset_controls(0)


func _on_reward_card_enabled_toggled(
	value: bool,
	body_type: String,
	group_id: int,
	card_id: String
) -> void:
	var group = _training_group_by_identity(body_type, group_id)
	if group.is_empty():
		return
	_queue_reward_card_change(group, card_id, "enabled", value)


func _on_reward_card_intensity_changed(
	value: float,
	body_type: String,
	group_id: int,
	card_id: String
) -> void:
	var group = _training_group_by_identity(body_type, group_id)
	if group.is_empty():
		return
	if _reward_card_group_signature(group) != reward_card_refresh_signature:
		return
	var value_label_variant: Variant = reward_card_intensity_labels.get(card_id, null)
	if is_instance_valid(value_label_variant):
		var value_label = value_label_variant as Label
		value_label.text = _reward_card_intensity_text(
			value,
			float(value_label.get_meta("maximum_intensity", value))
		)
	_queue_reward_card_change(group, card_id, "intensity", value)


func _training_group_by_identity(body_type: String, group_id: int) -> Dictionary:
	match body_type:
		"four_limb":
			return limb_training.group_by_id(group_id)
		"turret":
			return turret_training.group_by_id(group_id)
	return _group_by_id(group_id)


func _reward_deck_for_group(group: Dictionary) -> RefCounted:
	if group.is_empty():
		return null
	match str(group.get("body_type", "drone")):
		"four_limb":
			return group.get("reward_deck") as FourLimbRewardDeck
		"turret":
			return group.get("reward_deck") as TurretRewardDeck
	return _ensure_drone_reward_deck(group)


func _ensure_drone_reward_deck(group: Dictionary) -> DroneTrainingRewardDeck:
	var deck = group.get("reward_deck") as DroneTrainingRewardDeck
	if deck != null:
		return deck
	deck = DroneTrainingRewardDeck.new(group.get("reward_components", {}))
	var stored_configuration: Dictionary = group.get("reward_card_config", {})
	if not stored_configuration.is_empty():
		deck.load_configuration(stored_configuration)
	group["reward_deck"] = deck
	group["reward_card_config"] = deck.configuration_dictionary()
	group["reward_components"] = deck.enabled_components_dictionary()
	return deck


func _queue_reward_card_change(
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
	_mark_reward_cardset_custom(group)
	_refresh_reward_card_note(group)


func _apply_pending_drone_reward_config(group: Dictionary) -> void:
	var pending: Dictionary = group.get("pending_reward_config", {})
	var deck = _ensure_drone_reward_deck(group)
	if not pending.is_empty():
		for card_id: String in pending:
			var card_value = deck.card(card_id)
			if card_value == null:
				continue
			var values: Dictionary = pending[card_id]
			card_value.load_dictionary(values)
		group["pending_reward_config"] = {}
		group["reward_cardset_id"] = str(group.get("pending_reward_cardset_id", "custom"))
		group["reward_cardset_name"] = str(group.get("pending_reward_cardset_name", "Custom"))
		group.erase("pending_reward_cardset_id")
		group.erase("pending_reward_cardset_name")
	group["reward_card_config"] = deck.configuration_dictionary()
	group["reward_components"] = deck.enabled_components_dictionary()
	for trial in group.get("trials", []):
		(trial as Dictionary)["reward_cards"] = group["reward_card_config"].duplicate(true)
		(trial as Dictionary)["reward_components"] = group["reward_components"].duplicate()


func _refresh_reward_card_values() -> void:
	var group = _selected_any_training_group()
	_refresh_reward_card_note(group)
	if reward_card_value_labels.is_empty() or group.is_empty():
		return
	var current = {}
	var totals = {}
	if str(group.get("body_type", "drone")) in ["four_limb", "turret"]:
		var reward_state: Dictionary = _worker_group_reward_ui_state(group)
		current = reward_state.get("last_components", {})
		totals = reward_state.get("episode_totals", {})
	else:
		var group_trials: Array = group.get("trials", [])
		if not group_trials.is_empty():
			var reward: Dictionary = (group_trials[0] as Dictionary).get("reward", {})
			for card_id in reward_card_value_labels:
				match str(card_id):
					"failure":
						current[card_id] = float(reward.get("failure_penalty", 0.0))
						totals[card_id] = float(reward.get("failure_penalty", 0.0))
					"smoothness":
						current[card_id] = (
							float(reward.get("smoothness_reward", 0.0))
							+ float(reward.get("action_abuse_reward", 0.0))
						)
						totals[card_id] = (
							float(reward.get("cumulative_smoothness_reward", 0.0))
							+ float(reward.get("cumulative_action_abuse_reward", 0.0))
						)
					_:
						current[card_id] = float(reward.get("%s_reward" % card_id, 0.0))
						totals[card_id] = float(reward.get("cumulative_%s_reward" % card_id, 0.0))
	for card_id: String in reward_card_value_labels:
		var label_variant: Variant = reward_card_value_labels.get(card_id, null)
		if not is_instance_valid(label_variant):
			continue
		var label = label_variant as Label
		label.text = "Now %+.4f · Episode %+.3f" % [
			float(current.get(card_id, 0.0)),
			float(totals.get(card_id, 0.0)),
		]


func _refresh_reward_card_note(group: Dictionary) -> void:
	if reward_card_note == null:
		return
	if group.is_empty():
		reward_card_note.text = "Select a drone, four-limb, or turret worker group. Changes apply at that group's next episode."
		return
	var group_name = str(group.get("name", "Selected group"))
	var pending: Dictionary = group.get("pending_reward_config", {})
	var cardset_name = str(group.get(
		"pending_reward_cardset_name",
		group.get("reward_cardset_name", "Custom")
	))
	var note_text: String = (
		"%s · %s is queued for its next episode." % [group_name, cardset_name]
		if not pending.is_empty()
		else "%s · %s is active. New changes apply at its next episode." % [group_name, cardset_name]
	)
	if str(group.get("body_type", "drone")) == "turret":
		var reward_state: Dictionary = _worker_group_reward_ui_state(group)
		var target_debug_value: Variant = reward_state.get("last_target_debug", {})
		if target_debug_value is Dictionary and not (target_debug_value as Dictionary).is_empty():
			note_text += "\n" + _turret_reward_target_debug_text(
				target_debug_value as Dictionary
			)
		var weapon_totals_value: Variant = reward_state.get("weapon_event_totals", {})
		if weapon_totals_value is Dictionary:
			note_text += "\n" + _turret_reward_weapon_debug_text(
				weapon_totals_value as Dictionary
			)
	reward_card_note.text = note_text


func _turret_reward_target_debug_text(target_debug: Dictionary) -> String:
	if not bool(target_debug.get("present", false)):
		return "Target telemetry · no routed aim objective"
	var combat_target: bool = bool(target_debug.get("is_combat_target", false))
	var target_kind: String = str(target_debug.get("target_kind", "target")).replace("_", " ")
	var alignment: float = clampf(
		RLTrainingMath.finite_float_or(target_debug.get("alignment", -1.0), -1.0),
		-1.0,
		1.0
	)
	var shootable: bool = bool(target_debug.get("is_shootable_target", combat_target))
	var target_mode: String = (
		"live combat"
		if combat_target
		else "synthetic target" if shootable
		else "aim only"
	)
	return "Target telemetry · %s · aim %+.3f · LOS %s · range %s · pitch %s · %s" % [
		target_kind,
		alignment,
		"yes" if bool(target_debug.get("line_of_sight", false)) else "no",
		"yes" if bool(target_debug.get("within_range", false)) else "no",
		"yes" if bool(target_debug.get("within_pitch_arc", false)) else "no",
		target_mode,
	]


static func _worker_group_reward_ui_state(group: Dictionary) -> Dictionary:
	var workers_value: Variant = group.get("workers", [])
	if not (workers_value is Array) or (workers_value as Array).is_empty():
		var fallback_value: Variant = group.get("last_reward_state", {})
		return fallback_value as Dictionary if fallback_value is Dictionary else {}
	var component_sums: Dictionary = {}
	var episode_sums: Dictionary = {}
	var last_weapon_sums: Dictionary = {}
	var weapon_total_sums: Dictionary = {}
	var target_debug: Dictionary = {}
	var state_count: int = 0
	for worker_value: Variant in workers_value as Array:
		if not (worker_value is Dictionary):
			continue
		var state_value: Variant = (worker_value as Dictionary).get("reward_state", {})
		if not (state_value is Dictionary) or (state_value as Dictionary).is_empty():
			continue
		var state: Dictionary = state_value as Dictionary
		state_count += 1
		_accumulate_numeric_dictionary(component_sums, state.get("last_components", {}))
		_accumulate_numeric_dictionary(episode_sums, state.get("episode_totals", {}))
		_accumulate_numeric_dictionary(last_weapon_sums, state.get("last_weapon_events", {}))
		_accumulate_numeric_dictionary(weapon_total_sums, state.get("weapon_event_totals", {}))
		if target_debug.is_empty():
			var debug_value: Variant = state.get("last_target_debug", {})
			if debug_value is Dictionary and not (debug_value as Dictionary).is_empty():
				target_debug = (debug_value as Dictionary).duplicate(false)
	if state_count <= 0:
		var fallback_value: Variant = group.get("last_reward_state", {})
		return fallback_value as Dictionary if fallback_value is Dictionary else {}
	var divisor: float = float(state_count)
	for key: Variant in component_sums.keys():
		component_sums[key] = float(component_sums[key]) / divisor
	for key: Variant in episode_sums.keys():
		episode_sums[key] = float(episode_sums[key]) / divisor
	# Reward values are means so changing worker count does not rescale the UI. Weapon events are
	# counts and remain sums, which makes a group-level hit counter truthful when several turrets
	# are firing at once.
	return {
		"last_components": component_sums,
		"episode_totals": episode_sums,
		"last_target_debug": target_debug,
		"last_weapon_events": last_weapon_sums,
		"weapon_event_totals": weapon_total_sums,
	}


static func _accumulate_numeric_dictionary(destination: Dictionary, source_value: Variant) -> void:
	if not (source_value is Dictionary):
		return
	for key: Variant in (source_value as Dictionary).keys():
		var value: Variant = (source_value as Dictionary).get(key)
		if value is int or value is float:
			destination[key] = float(destination.get(key, 0.0)) + float(value)


func _turret_reward_weapon_debug_text(weapon_totals: Dictionary) -> String:
	var shots: int = maxi(RLTrainingMath.finite_int_or(weapon_totals.get("shots_fired", 0), 0), 0)
	var viable: int = maxi(RLTrainingMath.finite_int_or(weapon_totals.get("viable_shots", 0), 0), 0)
	var hits: int = maxi(RLTrainingMath.finite_int_or(weapon_totals.get("hits", 0), 0), 0)
	var misses: int = maxi(RLTrainingMath.finite_int_or(weapon_totals.get("misses", 0), 0), 0)
	var damage: float = maxf(
		RLTrainingMath.finite_float_or(weapon_totals.get("damage_dealt", 0.0), 0.0),
		0.0
	)
	var unresolved: int = maxi(shots - hits - misses, 0)
	return "Fire telemetry · shots %d · viable %d · hits %d · misses %d · unresolved %d · damage %.1f" % [
		shots, viable, hits, misses, unresolved, damage
	]


func _reward_card_group_signature(group: Dictionary) -> String:
	if group.is_empty():
		return "none"
	return "%s:%d" % [
		str(group.get("body_type", "drone")),
		int(group.get("group_id", -1)),
	]


func _build_limb_model_browser() -> void:
	limb_model_browser = Window.new()
	limb_model_browser.title = "Four-Limb Model Library"
	limb_model_browser.min_size = Vector2i(720, 520)
	limb_model_browser.size = Vector2i(860, 620)
	limb_model_browser.transient = true
	# The room owns several sibling library windows. Making every hidden sibling exclusive
	# at construction time causes Godot to report that the root already has an exclusive
	# child. The destructive confirmation dialogs remain exclusive to their own browser.
	limb_model_browser.exclusive = false
	# Dynamically-created Window nodes default to visible. Hide library windows before
	# they enter the scene tree so startup never flashes/opens them.
	limb_model_browser.visible = false
	limb_model_browser.close_requested.connect(limb_model_browser.hide)
	add_child(limb_model_browser)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	limb_model_browser.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	DroneTrainingRoomPresentation.add_heading(content, "FOUR-LIMB MODEL LIBRARY", 22)
	var path_label = Label.new()
	path_label.text = limb_model_registry.globalized_root_path()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.add_theme_color_override("font_color", Color("ffad42"))
	content.add_child(path_label)
	var save_row = HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 7)
	content.add_child(save_row)
	limb_model_name_edit = LineEdit.new()
	limb_model_name_edit.placeholder_text = "Four-limb model name"
	limb_model_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_row.add_child(limb_model_name_edit)
	var save_button = _button("SAVE SELECTED", true)
	save_button.pressed.connect(_save_selected_limb_group)
	save_row.add_child(save_button)
	limb_model_list = ItemList.new()
	limb_model_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	limb_model_list.allow_reselect = true
	content.add_child(limb_model_list)
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 7)
	actions.add_theme_constant_override("v_separation", 7)
	content.add_child(actions)
	var load_button = _button("LOAD INTO SELECTED LIMB GROUP", true)
	load_button.pressed.connect(_load_selected_limb_model)
	actions.add_child(load_button)
	var delete_button = _button("DELETE")
	_set_button_danger(delete_button)
	delete_button.pressed.connect(_delete_selected_limb_model)
	actions.add_child(delete_button)
	var close_button = _button("CLOSE")
	close_button.pressed.connect(limb_model_browser.hide)
	actions.add_child(close_button)


func _open_limb_model_browser() -> void:
	var selected_group = _selected_limb_group()
	if limb_model_name_edit != null and not selected_group.is_empty():
		limb_model_name_edit.text = str(selected_group["name"])
	limb_model_records = limb_model_registry.list_models()
	limb_model_list.clear()
	for record: Dictionary in limb_model_records:
		limb_model_list.add_item("%s · %s" % [
			limb_model_registry.display_name(record),
			str(record.get("algorithm", "four_limb_ppo")),
		])
	limb_model_browser.popup_centered()


func _save_selected_limb_group() -> void:
	var group = _selected_limb_group()
	if group.is_empty():
		status_label.text = "Select a four-limb worker group before saving."
		return
	_save_limb_group(
		int(group["group_id"]),
		limb_model_name_edit.text if limb_model_name_edit != null else str(group["name"])
	)
	_open_limb_model_browser()


func _save_limb_group(
	group_id: int,
	requested_name: String = "",
	use_best_policy: bool = false
) -> Dictionary:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty():
		status_label.text = "Select a four-limb worker group before saving."
		return {}
	var checkpoint = limb_training.save_checkpoint(group_id, use_best_policy)
	var room_settings: Dictionary = checkpoint.get("room_settings", {})
	room_settings["target_handler"] = _target_handler_configuration_for_group(group_id)
	checkpoint["room_settings"] = room_settings
	var model_name = requested_name.strip_edges()
	if model_name.is_empty():
		model_name = str(group["name"])
	var overwrite_enabled = bool(group.get("overwrite_saved_versions", true))
	var rolling_version_id = str(group.get("rolling_version_id", ""))
	var record: Dictionary = {}
	var overwritten_existing = false
	if overwrite_enabled and not rolling_version_id.is_empty():
		# Deleting a saved version must not permanently wedge the live group. Start a new
		# group-owned rolling chain when its old target no longer exists, its body contract
		# changed, or the requested model name changed. A rolling version's manifest name is
		# immutable identity; silently overwriting it would make a renamed save invisible.
		var rolling_record = limb_model_registry.get_version(rolling_version_id)
		if (
			rolling_record.is_empty()
			or not _rolling_record_matches_requested_name(rolling_record, model_name)
			or str(rolling_record.get("hardware_signature", ""))
			!= str(checkpoint.get("hardware_signature", ""))
		):
			group["rolling_version_id"] = ""
			rolling_version_id = ""
		else:
			record = limb_model_registry.overwrite_checkpoint(rolling_version_id, checkpoint)
			overwritten_existing = not record.is_empty()
	if record.is_empty() and rolling_version_id.is_empty():
		record = limb_model_registry.save_checkpoint(model_name, checkpoint)
	if overwrite_enabled and not record.is_empty():
		group["rolling_version_id"] = str(record.get("version_id", ""))
	if record.is_empty():
		status_label.text = limb_model_registry.last_error
	else:
		var save_verb = "Updated" if overwritten_existing else "Saved"
		status_label.text = "%s %s." % [save_verb, limb_model_registry.display_name(record)]
	_refresh_limb_group_rolling_save_button(group)
	return record


func _load_selected_limb_model() -> void:
	var selected = limb_model_list.get_selected_items()
	if selected.is_empty() or selected[0] >= limb_model_records.size():
		return
	var group = _selected_limb_group()
	if group.is_empty():
		status_label.text = "Select a four-limb worker group before loading."
		return
	var record = limb_model_records[selected[0]]
	var checkpoint = limb_model_registry.load_checkpoint(record)
	if checkpoint.is_empty():
		status_label.text = limb_model_registry.last_error
		return
	if not limb_training.load_checkpoint(int(group["group_id"]), checkpoint):
		status_label.text = limb_training.last_error
		return
	# Loading may use someone else's saved checkpoint. Keep-newest must create a fresh
	# group-owned version on the next save rather than modifying that source artifact.
	group["rolling_version_id"] = ""
	_refresh_limb_group_rolling_save_button(group)
	var group_id: int = int(group["group_id"])
	var loaded_room_settings = checkpoint.get("room_settings", {}) as Dictionary
	var target_handler_value: Variant = loaded_room_settings.get("target_handler", {})
	if target_handler_value is Dictionary:
		_load_target_handler_configuration_for_group(
			group_id,
			target_handler_value as Dictionary
		)
	if bool(group.get("active", false)):
		limb_training.set_group_active(
			group_id,
			true,
			drone_spawn_position,
			_target_objective_position(group_id),
			_target_velocity_for_group_id(group_id),
			_target_radius_for_group_id(group_id),
			episode_duration,
			ARENA_SIZE
		)
	_rebuild_reward_cards()
	_refresh_selected_group_controls()
	_refresh_group_card_texts()
	status_label.text = "Loaded %s into %s." % [
		limb_model_registry.display_name(record),
		str(group["name"]),
	]
	limb_model_browser.hide()


func _delete_selected_limb_model() -> void:
	var selected = limb_model_list.get_selected_items()
	if selected.is_empty() or selected[0] >= limb_model_records.size():
		return
	if limb_model_registry.delete_model(limb_model_records[selected[0]]):
		_open_limb_model_browser()
	else:
		status_label.text = limb_model_registry.last_error


func _build_model_browser() -> void:
	model_browser = Window.new()
	model_browser.title = "Saved Model Library"
	model_browser.min_size = Vector2i(820, 600)
	model_browser.size = MODEL_BROWSER_SIZE
	model_browser.borderless = false
	model_browser.unresizable = false
	model_browser.transient = true
	model_browser.exclusive = false
	model_browser.visible = false
	model_browser.close_requested.connect(_close_model_browser)
	add_child(model_browser)
	model_delete_dialog = ConfirmationDialog.new()
	model_delete_dialog.title = "Delete Saved Models Permanently"
	model_delete_dialog.ok_button_text = "Delete Selected Permanently"
	model_delete_dialog.cancel_button_text = "Cancel"
	model_delete_dialog.transient = true
	model_delete_dialog.exclusive = true
	model_delete_dialog.confirmed.connect(_confirm_delete_selected_models)
	model_browser.add_child(model_delete_dialog)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	model_browser.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	DroneTrainingRoomPresentation.add_heading(content, "SAVED MODEL LIBRARY", 22)
	model_browser_context_label = Label.new()
	model_browser_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(model_browser_context_label)
	var batch_toolbar = HBoxContainer.new()
	batch_toolbar.add_theme_constant_override("separation", 7)
	content.add_child(batch_toolbar)
	var select_all_button = _button("SELECT ALL")
	select_all_button.tooltip_text = "Select all saved versions\n\nChecks every row for batch deletion.\nNothing is deleted until you confirm."
	select_all_button.pressed.connect(func() -> void:
		_set_all_model_batch_selection(true)
	)
	batch_toolbar.add_child(select_all_button)
	var clear_selection_button = _button("CLEAR")
	clear_selection_button.tooltip_text = "Clear deletion selection\n\nUnchecks every row.\nThe currently inspected model stays selected."
	clear_selection_button.pressed.connect(func() -> void:
		_set_all_model_batch_selection(false)
	)
	batch_toolbar.add_child(clear_selection_button)
	model_batch_selection_label = Label.new()
	model_batch_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_batch_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	model_batch_selection_label.add_theme_color_override("font_color", Color("8de1ff"))
	batch_toolbar.add_child(model_batch_selection_label)

	model_version_list = Tree.new()
	model_version_list.columns = 5
	model_version_list.hide_root = true
	model_version_list.column_titles_visible = true
	model_version_list.set_column_title(0, "Batch")
	model_version_list.set_column_title(1, "Saved version")
	model_version_list.set_column_title(2, "Created at")
	model_version_list.set_column_title(3, "Training updated")
	model_version_list.set_column_title(4, "Last used")
	model_version_list.set_column_expand(0, false)
	model_version_list.set_column_custom_minimum_width(0, 64)
	model_version_list.set_column_expand(1, true)
	model_version_list.set_column_expand_ratio(1, 2)
	for date_column in range(2, 5):
		model_version_list.set_column_expand(date_column, true)
		model_version_list.set_column_expand_ratio(date_column, 1)
		model_version_list.set_column_custom_minimum_width(date_column, 155)
	model_version_list.custom_minimum_size.y = 245.0
	model_version_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_version_list.tooltip_text = "Saved model list\n\nUse the first column to mark versions for batch deletion.\nClick a model name to inspect, load, or spawn it."
	model_version_list.cell_selected.connect(_on_model_version_cell_selected)
	model_version_list.item_edited.connect(_on_model_version_item_edited)
	content.add_child(model_version_list)
	var inspection_panel = PanelContainer.new()
	inspection_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspection_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	content.add_child(inspection_panel)
	model_inspection_label = Label.new()
	model_inspection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_inspection_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_inspection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model_inspection_label.add_theme_color_override("font_color", Color("8de1ff"))
	inspection_panel.add_child(model_inspection_label)
	loader_identity_label = model_inspection_label
	var action_flow = HFlowContainer.new()
	action_flow.add_theme_constant_override("h_separation", 7)
	action_flow.add_theme_constant_override("v_separation", 7)
	content.add_child(action_flow)
	model_browser_pause_button = _button("PAUSE GROUP")
	model_browser_pause_button.tooltip_text = "Pause or resume target group\n\nA saved model can only replace a live group while that group is paused."
	model_browser_pause_button.pressed.connect(func() -> void:
		_toggle_selected_group()
		_refresh_loader_identity()
	)
	action_flow.add_child(model_browser_pause_button)
	load_model_button = _button("LOAD INTO GROUP", true)
	load_model_button.tooltip_text = "Load into paused group\n\nReplaces the group's live weights with the selected saved model.\nThe group keeps its own reward switches."
	load_model_button.pressed.connect(_on_model_browser_primary_action)
	action_flow.add_child(load_model_button)
	spawn_evaluator_button = _button("SPAWN EVALUATOR")
	spawn_evaluator_button.tooltip_text = "Spawn evaluation drone\n\nCreates one test drone from this exact saved model.\nIt does not explore, learn, or modify the checkpoint."
	spawn_evaluator_button.pressed.connect(_spawn_selected_version)
	action_flow.add_child(spawn_evaluator_button)
	delete_model_button = _button("DELETE SELECTED (0)")
	delete_model_button.tooltip_text = "Delete selected saved versions\n\nPermanently removes every checked saved version and its stored evaluation history.\nAlready-running drones keep their in-memory copy."
	delete_model_button.disabled = true
	delete_model_button.pressed.connect(_request_delete_selected_models)
	_set_button_danger(delete_model_button)
	action_flow.add_child(delete_model_button)
	var close_button = _button("CLOSE")
	close_button.pressed.connect(_close_model_browser)
	action_flow.add_child(close_button)


func _build_map_browser() -> void:
	map_browser = Window.new()
	map_browser.title = "Training Map Library"
	map_browser.min_size = Vector2i(760, 560)
	map_browser.size = MAP_BROWSER_SIZE
	map_browser.borderless = false
	map_browser.unresizable = false
	map_browser.transient = true
	map_browser.exclusive = false
	map_browser.visible = false
	map_browser.close_requested.connect(_close_map_browser)
	add_child(map_browser)

	map_delete_dialog = ConfirmationDialog.new()
	map_delete_dialog.title = "Delete Training Maps Permanently"
	map_delete_dialog.ok_button_text = "Delete Selected Permanently"
	map_delete_dialog.cancel_button_text = "Cancel"
	map_delete_dialog.transient = true
	map_delete_dialog.exclusive = true
	map_delete_dialog.confirmed.connect(_confirm_delete_selected_maps)
	map_browser.add_child(map_delete_dialog)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	map_browser.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	DroneTrainingRoomPresentation.add_heading(content, "TRAINING MAP LIBRARY", 22)
	var path_label = Label.new()
	path_label.text = "Map files: %s" % map_registry.globalized_root_path()
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_label.add_theme_color_override("font_color", Color("ffad42"))
	path_label.tooltip_text = "Map save folder\n\nThis is the real folder containing your saved maps.\nNo map is created automatically."
	content.add_child(path_label)

	var name_row = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 7)
	content.add_child(name_row)
	var name_label = Label.new()
	name_label.text = "Map name"
	name_label.tooltip_text = "Map name\n\nSave as New creates another version under this name.\nLoading a map never changes its file."
	name_row.add_child(name_label)
	map_name_edit = LineEdit.new()
	map_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_name_edit.placeholder_text = "Example: Narrow corridor maze"
	map_name_edit.tooltip_text = "Map name\n\nNames are used to organize saved map versions."
	name_row.add_child(map_name_edit)
	var save_new_button = _button("SAVE AS NEW", true)
	save_new_button.tooltip_text = "Save current room as a new map\n\nStores every custom obstacle, authored Training Item, and delivery-destination group including all placed destination volumes and their shared acceptance/reward policy.\nThe fixed arena floor and outer walls are not duplicated."
	save_new_button.pressed.connect(_save_current_map_as_new)
	name_row.add_child(save_new_button)

	var batch_toolbar = HBoxContainer.new()
	batch_toolbar.add_theme_constant_override("separation", 7)
	content.add_child(batch_toolbar)
	var select_all_button = _button("SELECT ALL")
	select_all_button.tooltip_text = "Select all maps\n\nChecks every saved map version for batch deletion."
	select_all_button.pressed.connect(func() -> void:
		_set_all_map_batch_selection(true)
	)
	batch_toolbar.add_child(select_all_button)
	var clear_button = _button("CLEAR")
	clear_button.tooltip_text = "Clear map deletion selection\n\nUnchecks every map without changing the inspected row."
	clear_button.pressed.connect(func() -> void:
		_set_all_map_batch_selection(false)
	)
	batch_toolbar.add_child(clear_button)
	map_batch_selection_label = Label.new()
	map_batch_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_batch_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_batch_selection_label.add_theme_color_override("font_color", Color("8de1ff"))
	batch_toolbar.add_child(map_batch_selection_label)

	map_list = Tree.new()
	map_list.columns = 6
	map_list.hide_root = true
	map_list.column_titles_visible = true
	map_list.set_column_title(0, "Batch")
	map_list.set_column_title(1, "Saved map")
	map_list.set_column_title(2, "Objects")
	map_list.set_column_title(3, "Created at")
	map_list.set_column_title(4, "Updated")
	map_list.set_column_title(5, "Last used")
	map_list.set_column_expand(0, false)
	map_list.set_column_custom_minimum_width(0, 64)
	map_list.set_column_expand(1, true)
	map_list.set_column_expand_ratio(1, 2)
	map_list.set_column_expand(2, false)
	map_list.set_column_custom_minimum_width(2, 130)
	for date_column in range(3, 6):
		map_list.set_column_expand(date_column, true)
		map_list.set_column_expand_ratio(date_column, 1)
		map_list.set_column_custom_minimum_width(date_column, 145)
	map_list.custom_minimum_size.y = 240.0
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_list.tooltip_text = "Saved map list\n\nClick a map to inspect it.\nUse the first column only for batch deletion."
	map_list.cell_selected.connect(_on_map_cell_selected)
	map_list.item_edited.connect(_on_map_item_edited)
	content.add_child(map_list)

	var inspection_panel = PanelContainer.new()
	inspection_panel.custom_minimum_size.y = 100.0
	inspection_panel.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	content.add_child(inspection_panel)
	map_inspection_label = Label.new()
	map_inspection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_inspection_label.add_theme_color_override("font_color", Color("8de1ff"))
	inspection_panel.add_child(map_inspection_label)

	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 7)
	actions.add_theme_constant_override("v_separation", 7)
	content.add_child(actions)
	map_load_button = _button("LOAD SELECTED", true)
	map_load_button.tooltip_text = "Load selected map\n\nReplaces every custom obstacle, authored Training Item, and delivery-destination group currently in the room.\nThe fixed arena and all models remain unchanged."
	map_load_button.pressed.connect(_load_selected_map)
	actions.add_child(map_load_button)
	map_update_button = _button("UPDATE SELECTED")
	map_update_button.tooltip_text = "Update selected map\n\nOverwrites this saved map version with the current obstacles, authored Training Items, and delivery-destination groups."
	map_update_button.pressed.connect(_update_selected_map)
	actions.add_child(map_update_button)
	map_delete_button = _button("DELETE SELECTED (0)")
	map_delete_button.tooltip_text = "Delete checked maps\n\nPermanently removes every checked map version from disk.\nThis cannot be undone."
	map_delete_button.disabled = true
	map_delete_button.pressed.connect(_request_delete_selected_maps)
	_set_button_danger(map_delete_button)
	actions.add_child(map_delete_button)
	var close_button = _button("CLOSE")
	close_button.tooltip_text = "Close Map Library\n\nThe currently loaded room stays exactly as it is."
	close_button.pressed.connect(_close_map_browser)
	actions.add_child(close_button)


func _open_map_browser() -> void:
	_refresh_map_library(map_selected_id)
	map_browser.popup_centered(MAP_BROWSER_SIZE)
	call_deferred("_center_map_browser_window")


func _center_map_browser_window() -> void:
	if map_browser == null or not map_browser.visible:
		return
	var viewport_size = Vector2i(get_viewport().get_visible_rect().size)
	var desired_size = Vector2i(
		mini(MAP_BROWSER_SIZE.x, maxi(viewport_size.x - 40, map_browser.min_size.x)),
		mini(MAP_BROWSER_SIZE.y, maxi(viewport_size.y - 40, map_browser.min_size.y))
	)
	map_browser.size = desired_size
	map_browser.position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _close_map_browser() -> void:
	if map_browser != null:
		map_browser.hide()


func _refresh_map_library(preferred_map_id = "") -> void:
	if map_list == null:
		return
	var maps = map_registry.list_maps()
	var available_ids: Dictionary = {}
	for record in maps:
		available_ids[str(record.get("map_id", ""))] = true
	for map_id in map_batch_selected_ids.keys():
		if not available_ids.has(str(map_id)):
			map_batch_selected_ids.erase(map_id)
	var requested_id = str(preferred_map_id)
	if requested_id.is_empty():
		requested_id = map_selected_id
	map_list_refreshing = true
	map_list.clear()
	var root = map_list.create_item()
	var selected_item: TreeItem = null
	for record in maps:
		var item = map_list.create_item(root)
		var map_id = str(record.get("map_id", ""))
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, bool(map_batch_selected_ids.get(map_id, false)))
		item.set_tooltip_text(0, "Select for deletion\n\nChecks this exact map version.\nNothing is deleted until you confirm.")
		item.set_text(1, map_registry.display_name(record))
		var obstacle_count: int = maxi(RLTrainingMath.finite_int_or(record.get("obstacle_count", 0), 0), 0)
		var item_count: int = maxi(RLTrainingMath.finite_int_or(record.get("item_count", 0), 0), 0)
		var delivery_count: int = maxi(
			RLTrainingMath.finite_int_or(record.get("delivery_destination_group_count", 0), 0),
			0
		)
		item.set_text(2, "%d obs · %d items · %d delivery" % [obstacle_count, item_count, delivery_count])
		item.set_text(3, _model_library_time_text(record, "created_utc", "Unknown"))
		item.set_text(4, _model_library_time_text(record, "updated_utc", "Unknown"))
		item.set_text(5, _model_library_time_text(record, "last_used_utc", "Never"))
		for column in range(6):
			item.set_metadata(column, map_id)
		if map_id == requested_id:
			selected_item = item
	if selected_item == null and root.get_first_child() != null:
		selected_item = root.get_first_child()
	if selected_item != null:
		map_selected_id = str(selected_item.get_metadata(1))
		selected_item.select(1)
	else:
		map_selected_id = ""
	map_list_refreshing = false
	_update_map_batch_controls()
	_refresh_map_inspection()


func _on_map_cell_selected() -> void:
	if map_list_refreshing or map_list == null:
		return
	var item = map_list.get_selected()
	if item == null:
		return
	var column = map_list.get_selected_column()
	map_selected_id = str(item.get_metadata(column))
	_refresh_map_inspection()


func _on_map_item_edited() -> void:
	if map_list_refreshing or map_list == null or map_list.get_edited_column() != 0:
		return
	var item = map_list.get_edited()
	if item == null:
		return
	var map_id = str(item.get_metadata(0))
	if item.is_checked(0):
		map_batch_selected_ids[map_id] = true
	else:
		map_batch_selected_ids.erase(map_id)
	_update_map_batch_controls()


func _set_all_map_batch_selection(selected: bool) -> void:
	map_batch_selected_ids.clear()
	if selected:
		for record in map_registry.list_maps():
			map_batch_selected_ids[str(record.get("map_id", ""))] = true
	_refresh_map_library(map_selected_id)


func _batch_selected_map_ids() -> Array[String]:
	var result: Array[String] = []
	for map_id in map_batch_selected_ids.keys():
		if bool(map_batch_selected_ids.get(map_id, false)):
			result.append(str(map_id))
	result.sort()
	return result


func _update_map_batch_controls() -> void:
	var count = _batch_selected_map_ids().size()
	if map_batch_selection_label != null:
		map_batch_selection_label.text = "%d selected" % count
	if map_delete_button != null:
		map_delete_button.text = "DELETE SELECTED (%d)" % count
		map_delete_button.disabled = count <= 0


func _selected_map_record() -> Dictionary:
	if map_selected_id.is_empty():
		return {}
	return map_registry.get_map(map_selected_id)


func _refresh_map_inspection() -> void:
	var record = _selected_map_record()
	var has_selection = not record.is_empty()
	if map_load_button != null:
		map_load_button.disabled = not has_selection
	if map_update_button != null:
		map_update_button.disabled = not has_selection
	if map_inspection_label == null:
		return
	if not has_selection:
		map_inspection_label.text = "No maps saved yet.\n\nPlace obstacles, Training Items, and optional delivery destinations in the room, enter a name, and press Save as New."
		return
	var obstacle_count = maxi(RLTrainingMath.finite_int_or(record.get("obstacle_count", 0), 0), 0)
	var item_count = maxi(RLTrainingMath.finite_int_or(record.get("item_count", 0), 0), 0)
	var delivery_group_count = maxi(
		RLTrainingMath.finite_int_or(record.get("delivery_destination_group_count", 0), 0),
		0
	)
	map_inspection_label.text = "%s\n\n%d custom obstacle%s · %d training item%s · %d delivery group%s\nCreated: %s\nUpdated: %s\nLast used: %s\n\nStored at: %s" % [
		map_registry.display_name(record),
		obstacle_count,
		"" if obstacle_count == 1 else "s",
		item_count,
		"" if item_count == 1 else "s",
		delivery_group_count,
		"" if delivery_group_count == 1 else "s",
		_model_library_time_text(record, "created_utc", "Unknown"),
		_model_library_time_text(record, "updated_utc", "Unknown"),
		_model_library_time_text(record, "last_used_utc", "Never"),
		ProjectSettings.globalize_path(str(record.get("storage_path", ""))),
	]


func _save_current_map_as_new() -> void:
	var map_name = map_name_edit.text.strip_edges() if map_name_edit != null else ""
	if map_name.is_empty():
		status_label.text = "Enter a map name before saving."
		if map_name_edit != null:
			map_name_edit.grab_focus()
		return
	var record = map_registry.save_map(
		map_name,
		_custom_wall_environment_records(),
		_training_item_environment_records(),
		_delivery_destination_environment_records()
	)
	if record.is_empty():
		status_label.text = "Could not save map: %s" % map_registry.last_error
		return
	map_selected_id = str(record.get("map_id", ""))
	_refresh_map_library(map_selected_id)
	status_label.text = "Saved %s with %d obstacle(s), %d training item(s), and %d delivery group(s)." % [
		map_registry.display_name(record),
		maxi(RLTrainingMath.finite_int_or(record.get("obstacle_count", 0), 0), 0),
		maxi(RLTrainingMath.finite_int_or(record.get("item_count", 0), 0), 0),
		maxi(RLTrainingMath.finite_int_or(record.get("delivery_destination_group_count", 0), 0), 0),
	]


func _update_selected_map() -> void:
	var record = _selected_map_record()
	if record.is_empty():
		status_label.text = "Select a saved map before updating it."
		return
	var updated = map_registry.overwrite_map(
		record,
		_custom_wall_environment_records(),
		_training_item_environment_records(),
		_delivery_destination_environment_records()
	)
	if updated.is_empty():
		status_label.text = "Could not update map: %s" % map_registry.last_error
		return
	_refresh_map_library(str(updated.get("map_id", "")))
	status_label.text = "Updated %s from the current room." % map_registry.display_name(updated)


func _load_selected_map() -> void:
	var record = _selected_map_record()
	if record.is_empty():
		status_label.text = "Select a saved map before loading it."
		return
	var obstacles: Variant = record.get("obstacles", [])
	if not (obstacles is Array):
		status_label.text = "The selected map file has no readable obstacle list."
		return
	var items: Variant = record.get("items", [])
	if not (items is Array):
		status_label.text = "The selected map file has no readable training-item list."
		return
	var delivery_groups: Variant = record.get("delivery_destination_groups", [])
	if not (delivery_groups is Array):
		delivery_groups = []
	_replace_custom_walls_from_records(obstacles as Array)
	_replace_training_items_from_records(items as Array)
	_replace_delivery_destinations_from_records(delivery_groups as Array)
	map_registry.mark_used(record)
	_refresh_map_library(str(record.get("map_id", "")))
	_close_map_browser()
	_restart_for_configuration_change(
		"Loaded %s; episode restarted." % map_registry.display_name(record),
		true,
		true,
		true
	)


func _request_delete_selected_maps() -> void:
	var map_ids = _batch_selected_map_ids()
	if map_ids.is_empty() or map_delete_dialog == null:
		status_label.text = "Select at least one saved map to delete."
		return
	pending_delete_map_ids = map_ids.duplicate()
	var names: Array[String] = []
	for map_id in map_ids:
		var record = map_registry.get_map(map_id)
		names.append(map_registry.display_name(record) if not record.is_empty() else map_id)
	map_delete_dialog.dialog_text = "Delete %d saved map version%s permanently?\n\n%s\n\nThis removes the map files from disk. The room currently loaded in memory is not changed." % [
		map_ids.size(),
		"" if map_ids.size() == 1 else "s",
		"\n".join(names),
	]
	map_delete_dialog.popup_centered(Vector2i(620, 360))


func _confirm_delete_selected_maps() -> void:
	var map_ids = pending_delete_map_ids.duplicate()
	pending_delete_map_ids.clear()
	var deleted = 0
	var failures: Array[String] = []
	for map_id in map_ids:
		var deleted_ok = map_registry.delete_map(map_id)
		if deleted_ok:
			deleted += 1
			map_batch_selected_ids.erase(map_id)
			if map_selected_id == map_id:
				map_selected_id = ""
		else:
			failures.append("%s: %s" % [map_id, map_registry.last_error])
	_refresh_map_library(map_selected_id)
	if failures.is_empty():
		status_label.text = "Deleted %d saved map version%s." % [deleted, "" if deleted == 1 else "s"]
	else:
		status_label.text = "Deleted %d maps; %d failed: %s" % [deleted, failures.size(), "; ".join(failures)]


func _request_delete_selected_models() -> void:
	var version_ids = _batch_selected_model_ids()
	if version_ids.is_empty() or model_delete_dialog == null:
		status_label.text = "Select at least one saved model version to delete."
		return
	pending_delete_version_ids = version_ids.duplicate()
	var names: Array[String] = []
	for version_id in version_ids:
		var record = model_registry.get_version(version_id)
		names.append(
			model_registry.display_name(record)
			if not record.is_empty()
			else version_id
		)
	var preview_count = mini(names.size(), 8)
	var preview_lines: Array[String] = []
	for index in range(preview_count):
		preview_lines.append("• %s" % names[index])
	if names.size() > preview_count:
		preview_lines.append("• …and %d more" % (names.size() - preview_count))
	model_delete_dialog.dialog_text = "Delete %d saved model version%s permanently?\n\n%s\n\nThis removes their checkpoints and recorded evaluation runs from disk. This cannot be undone. Running groups and evaluators that already loaded them keep their current in-memory policies." % [
		version_ids.size(),
		"" if version_ids.size() == 1 else "s",
		"\n".join(preview_lines),
	]
	model_delete_dialog.popup_centered(Vector2i(620, 360))


func _confirm_delete_selected_models() -> void:
	var version_ids = pending_delete_version_ids.duplicate()
	pending_delete_version_ids.clear()
	if version_ids.is_empty():
		return
	var deleted_names: Array[String] = []
	var failed_names: Array[String] = []
	for version_id in version_ids:
		var record = model_registry.get_version(version_id)
		var display = (
			model_registry.display_name(record)
			if not record.is_empty()
			else version_id
		)
		if model_registry.delete_version(version_id):
			deleted_names.append(display)
			model_batch_selected_ids.erase(version_id)
			if selected_model_version_id == version_id:
				selected_model_version_id = ""
			_forget_deleted_version_references(version_id)
		else:
			failed_names.append("%s (%s)" % [display, model_registry.last_error])
	_refresh_model_versions(selected_model_version_id)
	_rebuild_evaluator_cards()
	if failed_names.is_empty():
		status_label.text = "%d saved model version%s permanently deleted." % [
			deleted_names.size(),
			"" if deleted_names.size() == 1 else "s",
		]
	else:
		status_label.text = "Deleted %d model version%s; %d failed: %s" % [
			deleted_names.size(),
			"" if deleted_names.size() == 1 else "s",
			failed_names.size(),
			"; ".join(failed_names),
		]


func _forget_deleted_version_references(version_id: String) -> void:
	for group in worker_groups:
		if str(group.get("last_exact_saved_version_id", "")) == version_id:
			group["last_exact_saved_version_id"] = ""
			group["last_exact_saved_update"] = -1
		if str(group.get("last_auto_saved_version_id", "")) == version_id:
			group["last_auto_saved_version_id"] = ""
	for trial in _evaluation_trials():
		var trial_version: Dictionary = trial.get("version", {})
		if str(trial_version.get("version_id", "")) != version_id:
			continue
		trial["version_deleted"] = true
		trial_version["storage_path"] = ""
		trial["version"] = trial_version
	_refresh_group_card_texts()


func _build_branch_dialog() -> void:
	branch_dialog = ConfirmationDialog.new()
	branch_dialog.title = "New Branch Group"
	branch_dialog.ok_button_text = "Create Group"
	branch_dialog.cancel_button_text = "Cancel"
	# AcceptDialog defaults wrap_controls to true; these custom creation forms own their
	# window size, so child minimum-size changes must not resize the dialog behind our back.
	branch_dialog.wrap_controls = false
	branch_dialog.min_size = Vector2i(560, 620)
	branch_dialog.confirmed.connect(_confirm_branch_group)
	add_child(branch_dialog)
	var content_margin = MarginContainer.new()
	content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_margin.offset_left = 16.0
	content_margin.offset_top = 16.0
	content_margin.offset_right = -16.0
	content_margin.offset_bottom = -64.0
	branch_dialog.add_child(content_margin)
	var content_scroll = ScrollContainer.new()
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content_scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	content_scroll.add_child(content)
	branch_source_label = Label.new()
	branch_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	branch_source_label.add_theme_color_override("font_color", Color("8de1ff"))
	content.add_child(branch_source_label)
	var source_actions = HFlowContainer.new()
	source_actions.add_theme_constant_override("h_separation", 7)
	source_actions.add_theme_constant_override("v_separation", 7)
	content.add_child(source_actions)
	branch_model_source_button = _button("SELECT MODEL FROM LIBRARY")
	branch_model_source_button.tooltip_text = "Choose starting model\n\nOpens the Model Library and uses the selected saved model as this new group's starting policy."
	branch_model_source_button.pressed.connect(_open_model_browser_for_branch_source)
	source_actions.add_child(branch_model_source_button)
	branch_clear_model_source_button = _button("CLEAR SAVED SOURCE")
	branch_clear_model_source_button.visible = false
	branch_clear_model_source_button.tooltip_text = "Clear saved-model source\n\nThe new group will again branch from the selected live group, or start fresh when no group is selected."
	branch_clear_model_source_button.pressed.connect(_clear_branch_saved_source)
	source_actions.add_child(branch_clear_model_source_button)
	var name_label = Label.new()
	name_label.text = "Group and checkpoint name"
	name_label.tooltip_text = "Worker-group name\n\nIdentifies the live group and becomes the saved model family name."
	content.add_child(name_label)
	branch_name_edit = LineEdit.new()
	branch_name_edit.max_length = GROUP_NAME_MAX_LENGTH
	branch_name_edit.placeholder_text = "Example: Stable hover branch"
	content.add_child(branch_name_edit)
	var algorithm_label = Label.new()
	algorithm_label.text = "Learning algorithm"
	algorithm_label.tooltip_text = "Learning algorithm\n\nPPO learns from the newest collected flight and follows the accepted creator body interface. SAC-HER reuses older flights and safe points reached during failed attempts, and remains restricted to the stock four-propeller body."
	content.add_child(algorithm_label)
	branch_algorithm_picker = OptionButton.new()
	branch_algorithm_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for descriptor: Dictionary in DroneTrainingAlgorithmCatalog.descriptors():
		var algorithm_index = branch_algorithm_picker.item_count
		branch_algorithm_picker.add_item(str(descriptor.get(
			"display_name",
			"Learning algorithm"
		)))
		branch_algorithm_picker.set_item_metadata(
			algorithm_index,
			str(descriptor.get("id", ""))
		)
		branch_algorithm_picker.set_item_tooltip(
			algorithm_index,
			_readable_tooltip(str(descriptor.get("description", "")))
		)
	branch_algorithm_picker.item_selected.connect(func(_index: int) -> void:
		_update_branch_algorithm_state()
	)
	content.add_child(branch_algorithm_picker)
	branch_hidden_width_slider = _add_slider(
		content,
		"Hidden layer width",
		float(DronePPOMLP.MINIMUM_HIDDEN_WIDTH),
		512.0,
		8.0,
		float(DronePPOActorCritic.HIDDEN_SIZE),
		"Neurons in every hidden layer. Wider networks can represent more complex behavior but cost more CPU per decision and more optimizer work.",
		func(_value: float) -> void:
			pass
	)
	branch_hidden_depth_slider = _add_slider(
		content,
		"Hidden layer depth",
		float(DronePPOMLP.MINIMUM_HIDDEN_DEPTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_DEPTH),
		1.0,
		float(DronePPOActorCritic.HIDDEN_LAYER_COUNT),
		"Number of hidden tanh layers. More depth can model more complicated control relationships but increases inference/training cost. Architecture is fixed once the model is created.",
		func(_value: float) -> void:
			pass
	)
	branch_variation_slider = _add_slider(
		content,
		"Weight variation",
		0.0,
		MAXIMUM_BRANCH_WEIGHT_VARIATION,
		0.005,
		DEFAULT_BRANCH_WEIGHT_VARIATION,
		"Adds small random changes relative to the parent network's existing weight magnitude. 0 makes an exact copy; 0.025 is a conservative 2.5% variation; values above 0.10 are experimental.",
		func(_value: float) -> void:
			pass
	)
	DroneTrainingRoomPresentation.add_separator(content)
	var starting_setup_label = Label.new()
	starting_setup_label.text = "Starting simulation setup"
	starting_setup_label.add_theme_color_override("font_color", Color("8de1ff"))
	starting_setup_label.tooltip_text = "Starting simulation setup\n\nThese values are used when the new group creates its first workers.\nYou can change them later while the group is paused."
	content.add_child(starting_setup_label)
	branch_worker_count_slider = _add_slider(
		content,
		"Starting workers",
		1.0,
		48.0,
		1.0,
		8.0,
		"Initial number of simulation drones assigned to the new branch. You can change it later from the worker-group card.",
		func(_value: float) -> void:
			pass
	)
	branch_belly_grabber_checkbox = CheckBox.new()
	branch_belly_grabber_checkbox.text = "Articulated belly limb (PPO)"
	branch_belly_grabber_checkbox.tooltip_text = "Adds a compact two-segment GenericLimbDefinition under the belly. PPO receives shoulder X/Z, elbow Z, and grip controls plus the limb state observations. Its generic grip can hold climbable walls and carryable items."
	branch_belly_grabber_checkbox.toggled.connect(func(_pressed: bool) -> void:
		_update_branch_algorithm_state()
	)
	content.add_child(branch_belly_grabber_checkbox)
	branch_control_rate_slider = _add_slider(
		content,
		"Control rate (Hz)",
		2.0,
		60.0,
		1.0,
		20.0,
		"How often the new policy chooses motor commands. 60 Hz is the room's simulated physics ceiling.",
		func(_value: float) -> void:
			pass
	)
	branch_exploration_slider = _add_slider(
		content,
		"Exploration strength",
		0.0,
		2.0,
		0.005,
		0.01,
		"Initial exploration strength. Larger values resist repetitive deterministic behavior; values above 0.5 are intentionally aggressive.",
		func(_value: float) -> void:
			pass
	)
	branch_start_active_checkbox = CheckBox.new()
	branch_start_active_checkbox.text = "Start training immediately"
	branch_start_active_checkbox.button_pressed = true
	branch_start_active_checkbox.tooltip_text = "Start immediately\n\nOn: the group begins training as soon as it is created.\nOff: it starts paused for inspection or editing."
	content.add_child(branch_start_active_checkbox)
	DroneTrainingRoomPresentation.add_separator(content)
	var rewards_label = Label.new()
	rewards_label.text = "Rewards used by this group"
	rewards_label.tooltip_text = "Reward switches\n\nEnabled rewards change the score the model learns from.\nDisabling a reward does not necessarily remove the related sensor input."
	content.add_child(rewards_label)
	for reward_key in [
		"approach", "radius", "survival", "ground_safety",
		"smoothness", "obstacle", "failure",
	]:
		var check = CheckBox.new()
		check.text = str(DroneTrainingRoomPresentation.REWARD_COMPONENT_LABELS[reward_key])
		check.tooltip_text = _reward_component_tooltip(reward_key)
		check.toggled.connect(func(_enabled: bool) -> void:
			_update_branch_reward_warning()
		)
		content.add_child(check)
		branch_reward_checks[reward_key] = check
	branch_reward_warning = Label.new()
	branch_reward_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(branch_reward_warning)


func _build_limb_branch_dialog() -> void:
	limb_branch_dialog = ConfirmationDialog.new()
	limb_branch_dialog.title = "New Four-Limb Branch"
	limb_branch_dialog.ok_button_text = "Create Branch"
	limb_branch_dialog.cancel_button_text = "Cancel"
	limb_branch_dialog.wrap_controls = false
	limb_branch_dialog.min_size = Vector2i(540, 470)
	limb_branch_dialog.confirmed.connect(_confirm_limb_branch_group)
	add_child(limb_branch_dialog)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 16.0
	margin.offset_top = 16.0
	margin.offset_right = -16.0
	margin.offset_bottom = -64.0
	limb_branch_dialog.add_child(margin)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	margin.add_child(content)
	limb_branch_source_label = Label.new()
	limb_branch_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limb_branch_source_label.add_theme_color_override("font_color", Color("8de1ff"))
	content.add_child(limb_branch_source_label)
	var name_label = Label.new()
	name_label.text = "Branch name"
	content.add_child(name_label)
	limb_branch_name_edit = LineEdit.new()
	limb_branch_name_edit.max_length = GROUP_NAME_MAX_LENGTH
	limb_branch_name_edit.placeholder_text = "Example: Longer-leg variant"
	content.add_child(limb_branch_name_edit)
	limb_branch_hidden_width_slider = _add_slider(
		content,
		"Hidden layer width",
		float(DronePPOMLP.MINIMUM_HIDDEN_WIDTH),
		512.0,
		8.0,
		float(FourLimbPPOActorCritic.HIDDEN_SIZE),
		"Neurons per hidden layer in the four-limb actor and critic. Larger networks cost noticeably more because limb observations are large.",
		func(_value: float) -> void:
			pass
	)
	limb_branch_hidden_depth_slider = _add_slider(
		content,
		"Hidden layer depth",
		float(DronePPOMLP.MINIMUM_HIDDEN_DEPTH),
		float(DronePPOMLP.MAXIMUM_HIDDEN_DEPTH),
		1.0,
		float(FourLimbPPOActorCritic.HIDDEN_LAYER_COUNT),
		"Number of hidden tanh layers. Architecture is chosen only for a fresh model; a branch keeps its parent's exact shape.",
		func(_value: float) -> void:
			pass
	)
	limb_branch_variation_slider = _add_slider(
		content,
		"Weight variation",
		0.0,
		MAXIMUM_BRANCH_WEIGHT_VARIATION,
		0.005,
		DEFAULT_BRANCH_WEIGHT_VARIATION,
		"Copies the source policy and optionally perturbs actor and critic parameters. Zero creates an exact independent copy.",
		func(_value: float) -> void:
			pass
	)
	limb_branch_worker_count_slider = _add_slider(
		content,
		"Starting workers",
		1.0,
		float(FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT),
		1.0,
		float(FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT),
		"Initial physical worker count for the child branch.",
		func(_value: float) -> void:
			pass
	)
	limb_branch_start_active_checkbox = CheckBox.new()
	limb_branch_start_active_checkbox.text = "Start training immediately"
	limb_branch_start_active_checkbox.button_pressed = true
	limb_branch_start_active_checkbox.tooltip_text = "Off creates the branch paused so you can edit its body before spawning workers."
	content.add_child(limb_branch_start_active_checkbox)
	var note = Label.new()
	note.text = "The child receives its own policy, PPO configuration, reward cards, control rate, worker settings, and complete physical body definition. Later changes remain independent."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("5ab889"))
	content.add_child(note)


func _open_limb_branch_dialog_for_group(source_group_id: int) -> void:
	var source = limb_training.group_by_id(source_group_id)
	var is_branch: bool = not source.is_empty()
	limb_branch_source_group_id = source_group_id if is_branch else -1
	limb_branch_dialog.title = (
		"New Four-Limb Branch" if is_branch else "New Four-Limb Model"
	)
	limb_branch_dialog.ok_button_text = "Create Branch" if is_branch else "Create Model"
	limb_branch_source_label.text = (
		"Policy source: live four-limb weights from %s\nThe complete private anatomy and tuning setup will also be copied." % source["name"]
		if is_branch
		else "Policy source: fresh random four-limb model\nChoose the network architecture before the policy is created."
	)
	limb_branch_name_edit.text = _unique_group_name(
		"%s branch" % str(source["name"]) if is_branch else "Limb worker group %d" % (group_counter + 1),
		-1
	)
	limb_branch_variation_slider.editable = is_branch
	limb_branch_variation_slider.value = DEFAULT_BRANCH_WEIGHT_VARIATION if is_branch else 0.0
	var source_trainer = source.get("trainer") as FourLimbPPOTrainer
	var architecture: Dictionary = (
		source_trainer.network_architecture()
		if is_branch and source_trainer != null
		else {
			"hidden_layer_width": FourLimbPPOActorCritic.HIDDEN_SIZE,
			"hidden_layer_depth": FourLimbPPOActorCritic.HIDDEN_LAYER_COUNT,
		}
	)
	limb_branch_hidden_width_slider.editable = not is_branch
	limb_branch_hidden_width_slider.value = float(architecture.get(
		"hidden_layer_width", FourLimbPPOActorCritic.HIDDEN_SIZE
	))
	limb_branch_hidden_depth_slider.editable = not is_branch
	limb_branch_hidden_depth_slider.value = float(architecture.get(
		"hidden_layer_depth", FourLimbPPOActorCritic.HIDDEN_LAYER_COUNT
	))
	limb_branch_worker_count_slider.value = float(
		source.get(
			"pending_worker_count",
			source.get("worker_count", FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT)
		)
		if is_branch
		else FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT
	)
	limb_branch_start_active_checkbox.button_pressed = true
	limb_branch_dialog.size = Vector2i(580, 600)
	limb_branch_dialog.popup_centered()
	call_deferred("_focus_limb_branch_name")


func _focus_limb_branch_name() -> void:
	if limb_branch_dialog == null or not limb_branch_dialog.visible:
		return
	limb_branch_name_edit.grab_focus()
	limb_branch_name_edit.select_all()


func _confirm_limb_branch_group() -> void:
	var source = limb_training.group_by_id(limb_branch_source_group_id)
	var is_branch: bool = not source.is_empty()
	var source_checkpoint: Dictionary = {}
	if is_branch:
		source_checkpoint = limb_training.save_checkpoint(limb_branch_source_group_id, false)
		if source_checkpoint.is_empty():
			status_label.text = "Could not copy the source four-limb policy."
			return
	group_counter += 1
	var hue = float(posmod(group_counter * 2371, 10000)) / 10000.0
	var network_config: Dictionary = {
		"hidden_layer_width": int(round(limb_branch_hidden_width_slider.value)),
		"hidden_layer_depth": int(round(limb_branch_hidden_depth_slider.value)),
	}
	var child = limb_training.create_group(
		group_counter,
		_unique_group_name(limb_branch_name_edit.text, -1),
		Color.from_hsv(hue, 0.68, 0.95),
		int(round(limb_branch_worker_count_slider.value)),
		limb_training.group_body_definition(limb_branch_source_group_id) if is_branch else null,
		network_config
	)
	if child.is_empty():
		status_label.text = limb_training.last_error
		return
	var child_id = int(child["group_id"])
	if is_branch and not limb_training.load_checkpoint(child_id, source_checkpoint):
		limb_training.remove_group(child_id)
		status_label.text = limb_training.last_error
		return
	if is_branch:
		child["parent_group_id"] = limb_branch_source_group_id
		child["branch_weight_variation"] = limb_branch_variation_slider.value
		child["source_description"] = "Live branch of %s" % source["name"]
	child["pending_worker_count"] = clampi(
		int(round(limb_branch_worker_count_slider.value)),
		1,
		FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT
	)
	child["worker_count"] = int(child["pending_worker_count"])
	var child_trainer = child["trainer"] as FourLimbPPOTrainer
	if is_branch:
		child_trainer.reset_episode_statistics()
		if not child_trainer.perturb_policy(
			limb_branch_variation_slider.value,
			104729 + child_id * 7919
		):
			limb_training.remove_group(child_id)
			status_label.text = child_trainer.last_error
			return
		child["episode"] = 0
		child["last_mean_reward"] = 0.0
		child["best_mean_reward"] = -INF
		child["last_update"] = {}
		(child["history"] as DroneTrainingMetricsHistory).reset()
	_ensure_group_target_handler(
		child_id, child["color"], limb_branch_source_group_id if is_branch else -1
	)
	_select_limb_group(child_id)
	if limb_branch_start_active_checkbox.button_pressed:
		limb_training.set_group_active(
			child_id,
			true,
			drone_spawn_position,
			_target_objective_position(child_id),
			_target_velocity_for_group_id(child_id),
			_target_radius_for_group_id(child_id),
			episode_duration,
			ARENA_SIZE
		)
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	_refresh_all_groups_pause_button()
	status_label.text = (
		"%s branched from %s." % [str(child["name"]), str(source["name"])]
		if is_branch
		else "%s created with a %dx%d hidden network." % [
			str(child["name"]),
			int(network_config["hidden_layer_depth"]),
			int(network_config["hidden_layer_width"]),
		]
	)
	limb_branch_source_group_id = -1


func _build_plot_dashboard(content: VBoxContainer) -> void:
	_build_action_trace_card(content)

	var restore_button = _button("RESTORE PLOTS")
	restore_button.tooltip_text = "Restore plots\n\nMakes every closed plot card visible again.\nStored history is not changed."
	restore_button.pressed.connect(_restore_plots)
	content.add_child(restore_button)
	plot_grid = GridContainer.new()
	plot_grid.columns = 2
	plot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot_grid.add_theme_constant_override("h_separation", 8)
	plot_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(plot_grid)
	for plot_id in DroneTrainingPlotSeriesBuilder.GROUP_PLOT_DEFINITIONS:
		_add_plot_card(plot_id, DroneTrainingPlotSeriesBuilder.GROUP_PLOT_DEFINITIONS[plot_id])


func _build_action_trace_card(content: VBoxContainer) -> void:
	action_trace_card = PanelContainer.new()
	action_trace_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_trace_card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	content.add_child(action_trace_card)
	var shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 7)
	action_trace_card.add_child(shell)

	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 7)
	shell.add_child(header)
	action_trace_header_button = _button("▼ LIVE MODEL ACTIONS")
	action_trace_header_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_trace_header_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	action_trace_header_button.tooltip_text = "Live model actions\n\nLists drone, four-limb, and turret workers together. Each worker kind exposes its complete direct action vector with semantic channel names and an independent current-episode trace."
	header.add_child(action_trace_header_button)
	action_trace_fullscreen_button = _button("FULLSCREEN")
	action_trace_fullscreen_button.custom_minimum_size = Vector2(104.0, 28.0)
	action_trace_fullscreen_button.tooltip_text = "Fullscreen action inspector\n\nShows the complete action contract, current values, episode statistics, ranges, saturation, and every channel in the condensed timeline for the selected worker."
	action_trace_fullscreen_button.pressed.connect(func() -> void:
		_set_action_trace_fullscreen(not action_trace_fullscreen)
	)
	header.add_child(action_trace_fullscreen_button)

	action_trace_body = VBoxContainer.new()
	action_trace_body.visible = true
	action_trace_body.set_meta("box_expanded", true)
	action_trace_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_trace_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_trace_body.add_theme_constant_override("separation", 7)
	shell.add_child(action_trace_body)
	action_trace_panel = ACTION_TRACE_PANEL_SCRIPT.new() as Control
	action_trace_body.add_child(action_trace_panel)
	action_trace_resize_handle = _attach_resize_handle(
		action_trace_card,
		action_trace_body,
		Callable(),
		shell
	)
	action_trace_header_button.pressed.connect(func() -> void:
		var expanded = not bool(action_trace_body.get_meta(
			"box_expanded",
			action_trace_body.visible
		))
		_set_box_body_expanded(
			action_trace_body,
			action_trace_header_button,
			"LIVE MODEL ACTIONS",
			expanded
		)
	)


func _add_plot_card(plot_id: String, definition: Dictionary) -> void:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 205.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	card.tooltip_text = _readable_tooltip(str(definition.get("tooltip", "")))
	plot_grid.add_child(card)
	var shell = VBoxContainer.new()
	card.add_child(shell)
	var header = HBoxContainer.new()
	shell.add_child(header)
	var title = Label.new()
	title.text = str(definition.get("title", plot_id))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", Color("8de1ff"))
	header.add_child(title)
	plot_title_labels[plot_id] = title
	var cut_button = _button("CUT")
	cut_button.custom_minimum_size = Vector2(56.0, 26.0)
	cut_button.tooltip_text = "Cut old graph history\n\nPress this, then move the orange triangle along the bottom of the graph.\nThe dashed line shows the cut position.\n\nLeft-click inside the graph to remove everything to the left.\nMove the mouse out of the graph or right-click to cancel."
	header.add_child(cut_button)
	plot_cut_buttons[plot_id] = cut_button
	var expand_button = _button("EXPAND")
	expand_button.custom_minimum_size = Vector2(72.0, 26.0)
	expand_button.tooltip_text = "Expand plot\n\nOpens a larger chart with more labels and detail.\nUse the wheel to zoom and middle-drag to move through history."
	expand_button.pressed.connect(func() -> void:
		_toggle_plot_expanded(plot_id)
	)
	header.add_child(expand_button)
	plot_expand_buttons[plot_id] = expand_button
	var close_button = _button("×")
	close_button.custom_minimum_size = Vector2(28.0, 26.0)
	close_button.tooltip_text = "Hide this plot\n\nThe history remains stored.\nUse Restore Plots to show the card again."
	close_button.pressed.connect(func() -> void:
		if expanded_plot_id == plot_id:
			_toggle_plot_expanded(plot_id)
		closed_plots[plot_id] = true
		card.visible = false
	)
	header.add_child(close_button)
	var plot = PLOT_SCRIPT.new() as Control
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(plot)
	plot.connect("detail_requested", func() -> void:
		_toggle_plot_expanded(plot_id)
	)
	cut_button.pressed.connect(func() -> void:
		_toggle_plot_cut_mode(plot_id)
	)
	plot.connect("cut_mode_changed", func(active: bool) -> void:
		cut_button.text = "CUTTING" if active else "CUT"
		cut_button.custom_minimum_size = Vector2(76.0 if active else 56.0, 26.0)
		cut_button.add_theme_color_override(
			"font_color",
			Color("ffaa3d") if active else Color("dfffee")
		)
	)
	plot.connect("history_cut", func(cut_x: float) -> void:
		status_label.text = "%s now starts at %s %s. New points will continue from there." % [
			str(definition.get("title", plot_id)),
			str(definition.get("x_axis", "step")),
			String.num(cut_x, 2),
		]
	)
	plot_widgets[plot_id] = plot
	plot_cards[plot_id] = card


func _toggle_plot_cut_mode(plot_id: String) -> void:
	var requested_plot = plot_widgets.get(plot_id) as Control
	if requested_plot == null:
		return
	if bool(requested_plot.call("is_cut_mode_active")):
		requested_plot.call("cancel_cut_mode")
		return
	for candidate_id in plot_widgets:
		var candidate_plot = plot_widgets[candidate_id] as Control
		if candidate_plot != null:
			candidate_plot.call("cancel_cut_mode")
	var started = bool(requested_plot.call("begin_cut_mode"))
	if not started and status_label != null:
		status_label.text = "This graph has no finished points to cut yet."


func _resize_plot_cards(viewport_size: Vector2) -> void:
	if plot_cards.is_empty():
		return
	var expanded_height = clampf(viewport_size.y * 0.62, 410.0, 680.0)
	for plot_id in plot_cards:
		var card = plot_cards[plot_id] as Control
		if card == null:
			continue
		card.custom_minimum_size = Vector2(
			0.0,
			expanded_height if expanded_plot_id == plot_id else 205.0
		)


func _add_section(
	parent: VBoxContainer,
	title: String,
	tooltip: String,
	expanded: bool
) -> VBoxContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(false)
	)
	parent.add_child(card)
	var shell = VBoxContainer.new()
	card.add_child(shell)
	var header = _button(("▼ " if expanded else "▶ ") + title)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.tooltip_text = "%s\n\n%s" % [title, _readable_tooltip(tooltip)]
	shell.add_child(header)
	var body = VBoxContainer.new()
	body.visible = expanded
	body.set_meta("box_expanded", expanded)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 7)
	shell.add_child(body)
	var resize_handle = _attach_resize_handle(card, body, Callable(), shell)
	resize_handle.visible = expanded
	body.set_meta("resize_handle_row", resize_handle)
	header.pressed.connect(func() -> void:
		_set_box_body_expanded(
			body,
			header,
			title,
			not bool(body.get_meta("box_expanded", body.visible))
		)
	)
	return body


func _set_box_body_expanded(
	body: Control,
	header: Button,
	title: String,
	expanded: bool
) -> void:
	body.set_meta("box_expanded", expanded)
	header.text = ("▼ " if expanded else "▶ ") + title

	if body.has_meta("resize_handle_row"):
		var resize_handle = body.get_meta("resize_handle_row") as Control
		if resize_handle != null:
			resize_handle.visible = expanded

	if body.has_meta("box_open_tween"):
		var previous_tween = body.get_meta("box_open_tween") as Tween
		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()

		body.remove_meta("box_open_tween")

	if expanded:
		body.visible = true
		_animate_box_open(body)
		return

	body.pivot_offset = Vector2(body.size.x * 0.5, 0.0)
	var tween = create_tween()
	body.set_meta("box_open_tween", tween)

	tween.set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)

	tween.tween_property(
		body,
		"modulate:a",
		0.0,
		BOX_OPEN_ANIMATION_SECONDS * 0.75
	)

	tween.tween_property(
		body,
		"scale",
		Vector2(0.99, 0.96),
		BOX_OPEN_ANIMATION_SECONDS * 0.75
	)

	tween.finished.connect(
		_on_box_close_tween_finished.bind(
			body.get_instance_id(),
			tween.get_instance_id()
		)
	)


func _animate_box_open(value: Variant) -> void:
	if not is_instance_valid(value):
		return

	var body = value as Control
	if body == null or not body.visible:
		return

	if body.has_meta("box_open_tween"):
		var previous_tween = body.get_meta("box_open_tween") as Tween

		if previous_tween != null and previous_tween.is_valid():
			previous_tween.kill()

		body.remove_meta("box_open_tween")

	body.pivot_offset = Vector2(body.size.x * 0.5, 0.0)
	body.modulate.a = 0.0
	body.scale = Vector2(0.99, 0.94)

	var tween = create_tween()
	body.set_meta("box_open_tween", tween)

	tween.set_ignore_time_scale(true)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		body,
		"modulate:a",
		1.0,
		BOX_OPEN_ANIMATION_SECONDS
	)

	tween.tween_property(
		body,
		"scale",
		Vector2.ONE,
		BOX_OPEN_ANIMATION_SECONDS
	)

	tween.finished.connect(
		_on_box_open_tween_finished.bind(
			body.get_instance_id(),
			tween.get_instance_id()
		)
	)


func _on_box_close_tween_finished(body_instance_id: int, tween_instance_id: int) -> void:
	var body = instance_from_id(body_instance_id) as Control
	if not is_instance_valid(body):
		return
	body.visible = false
	body.modulate.a = 1.0
	body.scale = Vector2.ONE
	_clear_box_tween_metadata(body, tween_instance_id)


func _on_box_open_tween_finished(body_instance_id: int, tween_instance_id: int) -> void:
	var body = instance_from_id(body_instance_id) as Control
	if is_instance_valid(body):
		_clear_box_tween_metadata(body, tween_instance_id)


func _clear_box_tween_metadata(body: Control, tween_instance_id: int) -> void:
	if not body.has_meta("box_open_tween"):
		return
	var recorded_tween = body.get_meta("box_open_tween") as Tween
	if is_instance_valid(recorded_tween) and recorded_tween.get_instance_id() == tween_instance_id:
		body.remove_meta("box_open_tween")


func _attach_resize_handle(
	card: Control,
	content: Control,
	changed: Callable = Callable(),
	handle_parent: Control = null
) -> HBoxContainer:
	var resize_row = HBoxContainer.new()
	resize_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row_parent = handle_parent if handle_parent != null else content
	row_parent.add_child(resize_row)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resize_row.add_child(spacer)
	var handle = _button("⋰")
	handle.custom_minimum_size = Vector2(28.0, 22.0)
	handle.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	handle.tooltip_text = "Resize this box\n\nDrag up or down to change its height.\nDouble-click the handle to return to automatic sizing."
	handle.gui_input.connect(
		_on_resize_handle_gui_input.bind(
			card.get_instance_id(),
			content.get_instance_id(),
			handle.get_instance_id(),
			changed
		)
	)
	resize_row.add_child(handle)
	return resize_row

func _on_resize_handle_gui_input(
	event: InputEvent,
	card_instance_id: int,
	content_instance_id: int,
	handle_instance_id: int,
	changed: Callable
) -> void:
	var card = instance_from_id(card_instance_id) as Control
	var content = instance_from_id(content_instance_id) as Control
	var handle = instance_from_id(handle_instance_id) as Control
	if not is_instance_valid(card) or not is_instance_valid(content) or not is_instance_valid(handle):
		return
	if event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.double_click:
			content.custom_minimum_size.y = 0.0
			card.custom_minimum_size.y = 0.0
			if changed.is_valid():
				changed.call(0.0)
			handle.accept_event()
	elif event is InputEventMouseMotion:
		var motion = event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var current_height = maxf(
				content.custom_minimum_size.y,
				content.get_combined_minimum_size().y
			)
			var new_height = clampf(
				current_height + motion.relative.y,
				0.0,
				BOX_RESIZE_MAXIMUM_HEIGHT
			)
			content.custom_minimum_size.y = new_height
			if changed.is_valid():
				changed.call(new_height)
			handle.accept_event()



func _button(text: String, accent = false) -> Button:
	var button = Button.new()
	button.text = text
	button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(accent)
	)
	return button


func _set_button_danger(button: Button) -> void:
	if button == null:
		return
	var style = DroneTrainingRoomPresentation.scanner_danger_button_style()
	for state_name in ["normal", "pressed", "hover", "hover_pressed"]:
		button.add_theme_stylebox_override(state_name, style)
	button.add_theme_color_override("font_color", Color("ff8c8c"))


func _readable_tooltip(text: String) -> String:
	var cleaned = text.strip_edges()
	if cleaned.is_empty() or cleaned.contains("\n"):
		return cleaned
	var sentences = cleaned.split(". ", false)
	if sentences.size() <= 1:
		return cleaned
	var first = str(sentences[0]).strip_edges()
	if not first.ends_with("."):
		first += "."
	var remaining = PackedStringArray()
	for index in range(1, sentences.size()):
		var sentence = str(sentences[index]).strip_edges()
		if sentence.is_empty():
			continue
		if index < sentences.size() - 1 and not sentence.ends_with("."):
			sentence += "."
		remaining.append(sentence)
	return first + "\n\n" + "\n".join(remaining)


func _add_slider(
	parent: VBoxContainer,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	tooltip: String,
	callback: Callable
) -> HSlider:
	var slider = DroneTrainingRoomPresentation.add_slider(
		parent,
		title,
		minimum,
		maximum,
		step,
		value,
		callback
	)
	var readable = "%s\n\n%s" % [title, _readable_tooltip(tooltip)]
	slider.tooltip_text = readable
	var slider_label = slider.get_parent().get_child(slider.get_index() - 1) as Control
	if slider_label != null:
		slider_label.tooltip_text = readable
	return slider


func _add_number_input(
	parent: VBoxContainer,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	suffix: String,
	tooltip: String,
	callback: Callable
) -> SpinBox:
	var input = DroneTrainingRoomPresentation.add_number_input(
		parent,
		title,
		minimum,
		maximum,
		step,
		value,
		suffix,
		callback
	)
	var readable = "%s\n\n%s" % [title, _readable_tooltip(tooltip)]
	input.tooltip_text = readable
	var input_row = input.get_parent() as Control
	if input_row != null:
		input_row.tooltip_text = readable
		var input_label = input_row.get_child(0) as Control
		if input_label != null:
			input_label.tooltip_text = readable
	return input


func _add_group_slider(
	parent: VBoxContainer,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	tooltip: String,
	callback: Callable
) -> HSlider:
	var slider = _add_slider(
		parent, title, minimum, maximum, step, value, tooltip,
		func(new_value: float) -> void:
			if not suppress_ui_callbacks:
				callback.call(new_value)
	)
	selected_group_controls.append(slider)
	return slider


func _add_algorithm_config_slider(
	content: VBoxContainer,
	definition: Dictionary,
	config: Dictionary
) -> void:
	var config_key = str(definition.get("key", ""))
	if config_key.is_empty() or not config.has(config_key):
		return
	var slider = _add_group_slider(
		content,
		str(definition.get("title", config_key)),
		float(definition.get("minimum", 0.0)),
		float(definition.get("maximum", 1.0)),
		float(definition.get("step", 0.01)),
		float(config[config_key]),
		str(definition.get("tooltip", "")),
		func(value: float) -> void:
			_set_selected_config_value(
				config_key,
				value,
				bool(definition.get("integer", false))
			)
	)
	algorithm_config_sliders[config_key] = slider


static func _create_algorithm_preview(algorithm_id: String) -> DroneTrainingAlgorithm:
	var preview_config: Dictionary = {}
	if algorithm_id == "ppo_clip":
		var preset: MLBodyPreset = MLBodyPresetLibrary.preset_by_id(MLBodyPresetLibrary.DRONE_QUAD)
		var manifest: MLBodyInterfaceManifest = preset.instantiate_manifest() if preset != null else null
		if manifest == null:
			return null
		preview_config["body_interface"] = manifest.to_dictionary()
	return DroneTrainingAlgorithmCatalog.create(algorithm_id, preview_config)


static func _group_requested_trainer_config(initial_setup: Dictionary) -> Dictionary:
	var config_value: Variant = initial_setup.get("config", {})
	return (config_value as Dictionary).duplicate(true) if config_value is Dictionary else {}


static func _create_group_training_algorithm(
	algorithm_id: String,
	initial_setup: Dictionary,
	initialization_seed: int
) -> DroneTrainingAlgorithm:
	# Network architecture is immutable after construction, so startup configuration must reach
	# the trainer constructor. Applying width/depth later through set_config_value() is deliberately
	# rejected by every trainer and used to make fresh groups silently fall back to defaults.
	return DroneTrainingAlgorithmCatalog.create(
		algorithm_id,
		_group_requested_trainer_config(initial_setup),
		initialization_seed
	)


func _manifest_is_legacy_four_propeller_body(manifest: MLBodyInterfaceManifest) -> bool:
	return DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(manifest)


func _runtime_contract_is_stock_quad(contract: Dictionary) -> bool:
	var controls_value: Variant = contract.get("controls", [])
	if not (controls_value is Array) or int(contract.get("action_count", -1)) != QUAD_PROPELLER_COUNT:
		return false
	var propeller_controls: int = 0
	for control_value: Variant in controls_value:
		if control_value is Dictionary and str((control_value as Dictionary).get("kind", "")) == "propeller_throttle":
			propeller_controls += 1
	return propeller_controls == QUAD_PROPELLER_COUNT


func _create_worker_group(
	clone_selected: bool,
	reward_components: Dictionary = {},
	requested_name = "",
	source_group_id = -1,
	weight_variation = 0.0,
	algorithm_id = DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID,
	initial_setup: Dictionary = {}
) -> Dictionary:
	group_counter += 1
	var source = (
		_group_by_id(int(source_group_id))
		if int(source_group_id) >= 0
		else _selected_group()
	)
	var cloned_from_group = clone_selected and not source.is_empty()
	# Build the physical body first. The accepted manifest is the only authority allowed to size
	# a new network. A future body-creator UI will edit an MLBodyBuildDraft and reach this exact
	# point only after its Accept button finalizes the chosen Core + slots + parts.
	var source_loadout = source.get("drone_loadout") as DroneLoadout
	var requested_loadout_value: Variant = initial_setup.get("drone_loadout", null)
	var group_loadout: DroneLoadout = null
	if requested_loadout_value is DroneLoadout:
		group_loadout = LOADOUT_CONFIG.duplicate_loadout(requested_loadout_value as DroneLoadout)
	elif requested_loadout_value is Dictionary and not (requested_loadout_value as Dictionary).is_empty():
		group_loadout = LOADOUT_CONFIG.from_record(requested_loadout_value as Dictionary)
	else:
		group_loadout = (
			LOADOUT_CONFIG.duplicate_loadout(source_loadout)
			if cloned_from_group and source_loadout != null
			else MLBodyPresetLibrary.drone_quad_loadout(false)
		)
	if initial_setup.has("belly_grabber"):
		var belly_grabber_enabled: bool = bool(initial_setup.get("belly_grabber", false))
		if belly_grabber_enabled and not LOADOUT_CONFIG.install_training_belly_grabber(group_loadout):
			status_label.text = "Could not install the articulated belly limb on this drone core."
			return {}
		if not belly_grabber_enabled:
			LOADOUT_CONFIG.remove_training_belly_grabber(group_loadout)
	var accepted_body: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(group_loadout)
	if accepted_body == null:
		status_label.text = "Could not finalize the drone body interface."
		return {}
	if group_loadout.core == null or group_loadout.core.propeller_slot_count > QUAD_PROPELLER_COUNT:
		status_label.text = "The current flight runtime supports at most four propeller slots."
		return {}
	if str(algorithm_id) == "ppo_clip" and accepted_body.control_count() <= 0:
		status_label.text = "The created body has no model-controlled hardware. Add a propeller or controlled articulated attachment."
		return {}
	if str(algorithm_id) != "ppo_clip" and not _manifest_is_legacy_four_propeller_body(accepted_body):
		status_label.text = "%s currently supports only a plain four-propeller body; use PPO for custom rotor counts or controlled attachments." % str(algorithm_id)
		return {}
	var trainer_setup: Dictionary = initial_setup.duplicate(true)
	var trainer_config: Dictionary = _group_requested_trainer_config(initial_setup)
	if str(algorithm_id) == "ppo_clip":
		trainer_config["body_interface"] = accepted_body.to_dictionary()
		trainer_config["action_count"] = accepted_body.control_count()
		trainer_config["initial_control_values"] = LOADOUT_CONFIG.recommended_initial_control_values(
			group_loadout,
			accepted_body
		)
	trainer_setup["config"] = trainer_config
	var trainer = _create_group_training_algorithm(
		str(algorithm_id),
		trainer_setup,
		EPISODE_SEED_BASE + group_counter * 1009
	)
	if trainer == null:
		status_label.text = "Could not create learning algorithm '%s'." % str(
			algorithm_id
		)
		return {}
	if cloned_from_group:
		if not trainer.copy_policy_from(source["trainer"]):
			status_label.text = "Could not copy the parent policy: %s" % trainer.last_error_text()
			return {}
		if not trainer.perturb_policy(
			clampf(float(weight_variation), 0.0, MAXIMUM_BRANCH_WEIGHT_VARIATION),
			EPISODE_SEED_BASE + group_counter * 7919
		):
			status_label.text = "Could not vary the parent policy: %s" % trainer.last_error_text()
			return {}
	var requested_config: Dictionary = _group_requested_trainer_config(initial_setup)
	# Width/depth must be applied by the constructor above because an existing policy cannot
	# safely change tensor topology in place. Re-apply only mutable tuning here: SAC branching
	# intentionally copies the source configuration along with its weights, so branch-dialog
	# overrides such as control rate/exploration have to win after that copy.
	for config_key in requested_config:
		if str(config_key) in ["hidden_layer_width", "hidden_layer_depth", "action_count", "body_interface", "initial_control_values"]:
			continue
		trainer.set_config_value(str(config_key), requested_config[config_key])
	var source_trainer = source.get("trainer") as DroneTrainingAlgorithm
	var source_description = "Fresh random %s initialization created this session" % trainer.algorithm_short_name()
	var source_label = "Fresh policy"
	if cloned_from_group and source_trainer != null:
		source_description = "Branched from %s at %s update %d with %s%% relative weight variation" % [
			source["name"],
			source_trainer.algorithm_short_name(),
			source_trainer.update_count_value(),
			String.num(float(weight_variation) * 100.0, 1),
		]
		source_label = "Variant of %s" % source["name"]
	var group_name = _unique_group_name(
		str(requested_name) if not str(requested_name).strip_edges().is_empty()
		else "Worker group %d" % group_counter,
		-1
	)
	var enabled_rewards = DroneTrainingReward.DEFAULT_COMPONENTS.duplicate()
	var requested_rewards = reward_components
	if requested_rewards.is_empty() and cloned_from_group:
		requested_rewards = source.get("reward_components", {})
	for reward_key in enabled_rewards:
		if requested_rewards.has(reward_key):
			enabled_rewards[reward_key] = bool(requested_rewards[reward_key])
	var reward_deck = DroneTrainingRewardDeck.new(enabled_rewards)
	var reward_card_configuration: Dictionary = initial_setup.get("reward_cards", {})
	if reward_card_configuration.is_empty() and cloned_from_group:
		var source_deck = _ensure_drone_reward_deck(source)
		if source_deck != null:
			reward_card_configuration = source_deck.configuration_dictionary()
	if not reward_card_configuration.is_empty():
		reward_deck.load_configuration(reward_card_configuration)
	enabled_rewards = reward_deck.enabled_components_dictionary()
	var reward_cardset_id = str(initial_setup.get(
		"reward_cardset_id",
		source.get("reward_cardset_id", "builtin:drone_balanced") if cloned_from_group else "builtin:drone_balanced"
	))
	var reward_cardset_name = str(initial_setup.get(
		"reward_cardset_name",
		source.get("reward_cardset_name", "Balanced Flight") if cloned_from_group else "Balanced Flight"
	))
	if not reward_card_configuration.is_empty() and not initial_setup.has("reward_cardset_id") and not cloned_from_group:
		reward_cardset_id = "custom"
		reward_cardset_name = "Custom"
	var hue = float(posmod(group_counter * 2371, 10000)) / 10000.0
	var group_trials: Array[Dictionary] = []
	var group = {
		"group_id": group_counter,
		"body_type": "drone",
		"name": group_name,
		"color": Color.from_hsv(hue, 0.68, 0.95),
		"trainer": trainer,
		"algorithm_id": trainer.algorithm_id(),
		"algorithm_short_name": trainer.algorithm_short_name(),
		"history": DroneTrainingMetricsHistory.new(),
		"worker_count": clampi(
			int(initial_setup.get("worker_count", trainer.default_worker_count())),
			1,
			trainer.maximum_worker_count()
		),
		"active": false,
		"trials": group_trials,
		"control_elapsed": 0.0,
		"model_family_name": group_name,
		"reward_components": enabled_rewards,
		"reward_deck": reward_deck,
		"reward_card_config": reward_deck.configuration_dictionary(),
		"reward_cardset_id": reward_cardset_id,
		"reward_cardset_name": reward_cardset_name,
		"pending_reward_config": {},
		"drone_loadout": group_loadout,
		"body_interface": accepted_body.to_dictionary(),
		"body_interface_signature": accepted_body.contract_signature,
		"belly_grabber": LOADOUT_CONFIG.has_training_belly_grabber(group_loadout),
		"episode_end_on_ground_contact": bool(initial_setup.get(
			"episode_end_on_ground_contact",
			source.get("episode_end_on_ground_contact", false) if cloned_from_group else false
		)),
		"episode_end_on_flipped": bool(initial_setup.get(
			"episode_end_on_flipped",
			source.get("episode_end_on_flipped", false) if cloned_from_group else false
		)),
		"hardware_revision": int(source.get("hardware_revision", 0)) if cloned_from_group else 0,
		"parent_group_id": int(source.get("group_id", -1)) if cloned_from_group else -1,
		"branch_weight_variation": (
			clampf(float(weight_variation), 0.0, MAXIMUM_BRANCH_WEIGHT_VARIATION)
			if cloned_from_group
			else 0.0
		),
		"parent_version_id": str(source.get("parent_version_id", "")) if cloned_from_group else "",
		"source_version_id": str(source.get("source_version_id", "")) if cloned_from_group else "",
		"source_description": source_description,
		"source_label": source_label,
		"source_update_count": trainer.update_count_value(),
		"last_exact_saved_version_id": str(source.get("last_exact_saved_version_id", "")) if cloned_from_group else "",
		"last_exact_saved_update": int(source.get("last_exact_saved_update", -1)) if cloned_from_group else -1,
		"last_auto_saved_version_id": "",
		"last_auto_saved_candidate": {},
		# Rolling saves are enabled by default and remain group-owned. Never inherit a
		# parent's rolling target: a child or loaded source must not overwrite the
		# checkpoint it came from.
		"overwrite_saved_versions": true,
		"rolling_version_id": "",
		"auto_save_flash_until_usec": 0,
		"auto_save_retry_after_usec": 0,
		"candidate_evaluation_queue_position": 0,
		"candidate_evaluation_queue_ticket": 0,
		"candidate_evaluation_queued_candidate_id": -1,
		"candidate_evaluation_started_usec": 0,
		"candidate_evaluation_subject": "",
		"candidate_evaluation_last_result": {},
		"candidate_drone_loadout_cache": {},
		"card": null,
		"card_button": null,
		"pause_button": null,
		"activity_label": null,
		"candidate_evaluation_label": null,
		"best_score_label": null,
		"worker_slider": null,
		"worker_label": null,
		"worker_slider_dragging": false,
		"name_edit": null,
		"reward_label": null,
		"hardware_label": null,
		"overwrite_button": null,
		"card_minimum_height": 0.0,
	}
	if not _ensure_group_drone_profile_hardware(group):
		status_label.text = "Could not reconcile the new drone policy with its accepted body-interface contract."
		return {}
	worker_groups.append(group)
	worker_groups_by_id[group_counter] = group
	_ensure_group_target_handler(
		group_counter,
		group["color"],
		int(source.get("group_id", -1)) if cloned_from_group else -1
	)
	_select_group(group_counter)
	_rebuild_group_cards()
	status_label.text = (
		"%s created below %s with %s%% weight variation." % [
			group["name"],
			source["name"],
			String.num(float(weight_variation) * 100.0, 1),
		]
		if cloned_from_group
		else "%s created as a fresh root %s model." % [
			group["name"],
			trainer.algorithm_short_name(),
		]
	)
	return group


func _rebuild_group_cards() -> void:
	if group_list == null:
		return
	for child in group_list.get_children():
		child.queue_free()
	var rendered: Dictionary = {}
	for group in worker_groups:
		if int(group.get("parent_group_id", -1)) < 0:
			_add_group_card_tree(group, 0, rendered)
	# Old runtime data or an unexpectedly removed parent must never make a model vanish.
	for group in worker_groups:
		if not rendered.has(int(group["group_id"])):
			group["parent_group_id"] = -1
			_add_group_card_tree(group, 0, rendered)
	for limb_group: Dictionary in limb_training.groups:
		_add_limb_group_card(limb_group)
	turret_ui.add_group_cards(group_list)
	_refresh_group_card_texts()


func _add_group_card_tree(
	group: Dictionary,
	depth: int,
	rendered: Dictionary
) -> void:
	var group_id = int(group["group_id"])
	if rendered.has(group_id):
		return
	rendered[group_id] = true
	var selected = group_id == selected_group_id
	var tree_row = HBoxContainer.new()
	tree_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree_row.add_theme_constant_override("separation", 4)
	group_list.add_child(tree_row)
	if depth > 0:
		var indent = Control.new()
		indent.custom_minimum_size.x = float(mini(depth - 1, 6)) * GROUP_TREE_INDENT
		tree_row.add_child(indent)
		var branch_guide = Label.new()
		branch_guide.text = "└─"
		branch_guide.custom_minimum_size.x = GROUP_TREE_INDENT + 4.0
		branch_guide.add_theme_color_override("font_color", Color("358b69"))
		tree_row.add_child(branch_guide)
	var card = PanelContainer.new()
	card.tooltip_text = "Worker group\n\nThis card owns one independent model and its workers.\nIndented cards were branched from the model above them."
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = float(group.get("card_minimum_height", 0.0))
	card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(selected)
	)
	tree_row.add_child(card)
	var shell = VBoxContainer.new()
	card.add_child(shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	shell.add_child(header)
	var select_button = _button("")
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.clip_text = true
	select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select_button.tooltip_text = "Select worker group\n\nClick to inspect this model and highlight its drones.\nPress F2 while selected to rename it in place."
	select_button.pressed.connect(func() -> void:
		_select_group(-1 if selected_group_id == group_id else group_id)
	)
	header.add_child(select_button)
	var name_edit = LineEdit.new()
	name_edit.visible = false
	name_edit.text = str(group["name"])
	name_edit.max_length = GROUP_NAME_MAX_LENGTH
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 30.0
	name_edit.tooltip_text = "Rename group\n\nType the new name here.\nEnter saves it; Escape restores the old name."
	name_edit.text_submitted.connect(_on_drone_group_name_submitted.bind(group_id))
	name_edit.focus_exited.connect(_on_drone_group_name_focus_exited.bind(group_id))
	name_edit.gui_input.connect(_on_drone_group_name_gui_input.bind(group_id))
	header.add_child(name_edit)
	var candidate_evaluation_label = Label.new()
	candidate_evaluation_label.custom_minimum_size.x = 86.0
	candidate_evaluation_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	candidate_evaluation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	candidate_evaluation_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	candidate_evaluation_label.clip_text = true
	candidate_evaluation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	candidate_evaluation_label.add_theme_color_override("font_color", Color("76ddff"))
	candidate_evaluation_label.tooltip_text = "Fixed-seed evaluation\n\nShows frozen-candidate verification progress. This is separate from training-data collection and from the preserved Best score."
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
	best_score_label.tooltip_text = "Best recorded score\n\nShows the best completed policy result saved for this group under the current score rules."
	header.add_child(best_score_label)
	var activity_label = Label.new()
	activity_label.custom_minimum_size.x = 30.0
	activity_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	activity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	activity_label.add_theme_color_override("font_color", group["color"])
	activity_label.tooltip_text = "Group activity\n\nAnimated while workers are flying or the model is learning from collected experience."
	header.add_child(activity_label)
	var pause_button = _button("Ⅱ" if bool(group["active"]) else "▶")
	pause_button.custom_minimum_size = Vector2(34.0, 30.0)
	pause_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_button.tooltip_text = "Pause or resume this group\n\nPausing stops its workers and learning.\nThe live model weights stay in memory."
	pause_button.pressed.connect(func() -> void:
		_set_group_active(group_id, not bool(_group_by_id(group_id).get("active", false)))
	)
	header.add_child(pause_button)
	var worker_row = HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 7)
	shell.add_child(worker_row)
	var worker_label = Label.new()
	worker_label.text = "Workers: %d" % int(group["worker_count"])
	worker_label.custom_minimum_size.x = 76.0
	worker_label.tooltip_text = "Worker count\n\nMore drones collect experience faster but use more CPU.\nChanging the count rebuilds this group and restarts the shared episode."
	worker_row.add_child(worker_label)
	var worker_slider = HSlider.new()
	worker_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worker_slider.min_value = 1.0
	worker_slider.max_value = float((group["trainer"] as DroneTrainingAlgorithm).maximum_worker_count())
	worker_slider.step = 1.0
	worker_slider.value = float(group["worker_count"])
	worker_slider.tooltip_text = worker_label.tooltip_text
	group["worker_slider_dragging"] = false
	worker_slider.drag_started.connect(func() -> void:
		var live_group = _group_by_id(group_id)
		if not live_group.is_empty():
			live_group["worker_slider_dragging"] = true
	)
	worker_slider.value_changed.connect(_on_drone_worker_slider_value_changed.bind(group_id))
	worker_slider.drag_ended.connect(_on_drone_worker_slider_drag_ended.bind(group_id))
	worker_slider.focus_exited.connect(_on_drone_worker_slider_focus_exited.bind(group_id))
	worker_row.add_child(worker_slider)
	var auto_save_label = Label.new()
	auto_save_label.visible = false
	auto_save_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_save_label.clip_text = true
	auto_save_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	auto_save_label.add_theme_color_override("font_color", Color("54e6b1"))
	auto_save_label.tooltip_text = "Automatic best save\n\nAt an episode boundary, a new record is saved automatically.\nKeep newest can make these saves reuse one rolling version."
	shell.add_child(auto_save_label)
	var details = VBoxContainer.new()
	details.visible = selected
	details.add_theme_constant_override("separation", 6)
	shell.add_child(details)
	var lineage_label = Label.new()
	lineage_label.text = (
		"Root model"
		if int(group.get("parent_group_id", -1)) < 0
		else "Child variant · %s%% weight variation" % String.num(
			float(group.get("branch_weight_variation", 0.0)) * 100.0,
			1
		)
	)
	lineage_label.add_theme_color_override("font_color", Color("5ab889"))
	details.add_child(lineage_label)
	var model_label = Label.new()
	model_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model_label.add_theme_color_override("font_color", Color("ffad42"))
	model_label.tooltip_text = "Model source\n\nShows whether this group started fresh, from another live group, or from a saved model."
	details.add_child(model_label)
	var reward_label = Label.new()
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_label.tooltip_text = "Enabled rewards\n\nLists the score components currently used to train this group."
	details.add_child(reward_label)
	var hardware_label = Label.new()
	hardware_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hardware_label.tooltip_text = "Drone hardware\n\nShows the part setup used whenever this group creates workers."
	details.add_child(hardware_label)
	var action_flow = HFlowContainer.new()
	action_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_flow.add_theme_constant_override("h_separation", 6)
	action_flow.add_theme_constant_override("v_separation", 6)
	details.add_child(action_flow)
	var overwrite_button = ROLLING_SAVE_BUTTON_SCRIPT.new() as Button
	overwrite_button.text = (
		"KEEP NEWEST: ON"
		if bool(group.get("overwrite_saved_versions", true))
		else "KEEP NEWEST: OFF"
	)
	overwrite_button.toggle_mode = true
	overwrite_button.tooltip_text = (
		"Keep only the newest save\n\n"
		+ "Off: every save creates another numbered version.\n"
		+ "On: this group reuses one rolling version for later saves.\n\n"
		+ "A model loaded or branched from is never overwritten. The moving border means this mode is active."
	)
	overwrite_button.call(
		"configure",
		group["color"],
		bool(group.get("overwrite_saved_versions", true))
	)
	overwrite_button.toggled.connect(func(enabled: bool) -> void:
		_set_group_overwrite_saved_versions(group_id, enabled)
	)
	action_flow.add_child(overwrite_button)
	var branch_button = _button("BRANCH VARIANT", true)
	branch_button.tooltip_text = "Branch this model\n\nCreates a child from the current live weights.\nYou choose how much random variation to add."
	branch_button.pressed.connect(func() -> void:
		_open_branch_dialog_for_group(group_id)
	)
	action_flow.add_child(branch_button)
	if int(group.get("parent_group_id", -1)) >= 0:
		var root_button = _button("MAKE ROOT")
		root_button.tooltip_text = "Make root group\n\nDetaches this card from its parent.\nAll descendant branches move with it."
		root_button.pressed.connect(func() -> void:
			_promote_group_to_root(group_id)
		)
		action_flow.add_child(root_button)
	var save_button = _button("SAVE BEST")
	save_button.tooltip_text = "Save best snapshot\n\nSaves the best preserved policy for this group.\nWith Keep newest off, this creates another numbered version."
	save_button.pressed.connect(func() -> void:
		_save_group_best(group_id)
	)
	action_flow.add_child(save_button)
	var save_current_button = _button("SAVE CURRENT")
	save_current_button.tooltip_text = "Save current snapshot\n\nSaves the exact weights controlling this group now.\nWith Keep newest off, this creates another numbered version."
	save_current_button.pressed.connect(func() -> void:
		_save_group_current(group_id)
	)
	action_flow.add_child(save_current_button)
	var library_button = _button("MODEL LIBRARY")
	library_button.tooltip_text = "Open Model Library\n\nInspect saved versions or load a compatible saved model into this group while it is paused."
	library_button.pressed.connect(func() -> void:
		_open_model_browser(group_id)
	)
	action_flow.add_child(library_button)
	var plots_button = _button("PLOTS")
	plots_button.tooltip_text = "Open plots\n\nShows this group's reward, targeting, learning, and saved-model history."
	plots_button.pressed.connect(func() -> void:
		_set_workspace_page("plots")
	)
	action_flow.add_child(plots_button)
	var tuning_button = _button("DRONE / TUNING")
	tuning_button.tooltip_text = "Open tuning controls\n\nShows parts, power, worker count, control rate, and learning settings.\nPause before changing hardware."
	tuning_button.pressed.connect(func() -> void:
		_set_workspace_page("tuning")
	)
	action_flow.add_child(tuning_button)
	var remove_button = _button("REMOVE")
	remove_button.tooltip_text = "Remove live group\n\nDeletes this group and its drones.\nIts child groups move up one level; saved models remain."
	remove_button.pressed.connect(func() -> void:
		_remove_group(group_id)
	)
	action_flow.add_child(remove_button)
	_attach_resize_handle(
		card,
		details,
		_on_drone_group_card_resized.bind(group_id)
	)
	group["card"] = card
	group["card_button"] = select_button
	group["pause_button"] = pause_button
	group["activity_label"] = activity_label
	group["candidate_evaluation_label"] = candidate_evaluation_label
	group["best_score_label"] = best_score_label
	group["worker_slider"] = worker_slider
	group["worker_label"] = worker_label
	group["model_label"] = model_label
	group["name_edit"] = name_edit
	group["reward_label"] = reward_label
	group["hardware_label"] = hardware_label
	group["overwrite_button"] = overwrite_button
	group["auto_save_label"] = auto_save_label
	if selected:
		call_deferred("_animate_box_open", details)
	for child_group in _child_groups(group_id):
		_add_group_card_tree(child_group, depth + 1, rendered)


func _add_limb_group_card(group: Dictionary) -> void:
	var group_id = int(group["group_id"])
	var selected = group_id == selected_limb_group_id
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = float(group.get("card_minimum_height", 0.0))
	card.add_theme_stylebox_override(
		"panel",
		DroneTrainingRoomPresentation.scanner_panel_style(selected)
	)
	group_list.add_child(card)
	var shell = VBoxContainer.new()
	shell.add_theme_constant_override("separation", 6)
	card.add_child(shell)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 5)
	shell.add_child(header)
	var select_button = _button("")
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.clip_text = true
	select_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	select_button.tooltip_text = "Select four-limb worker group\n\nThis group owns a separate sixteen-output physical-body model.\nPress F2 while selected to rename it in place."
	select_button.pressed.connect(func() -> void:
		_select_limb_group(-1 if selected_limb_group_id == group_id else group_id)
	)
	header.add_child(select_button)
	var name_edit = LineEdit.new()
	name_edit.visible = false
	name_edit.text = str(group["name"])
	name_edit.max_length = GROUP_NAME_MAX_LENGTH
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.custom_minimum_size.y = 30.0
	name_edit.tooltip_text = "Rename four-limb group\n\nType the new name here.\nEnter saves it; Escape restores the old name."
	name_edit.text_submitted.connect(_on_limb_group_name_submitted.bind(group_id))
	name_edit.focus_exited.connect(_on_limb_group_name_focus_exited.bind(group_id))
	name_edit.gui_input.connect(_on_limb_group_name_gui_input.bind(group_id))
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
	activity_label.tooltip_text = "Group activity\n\nAnimated while the four-limb workers are running or their PPO model is learning."
	header.add_child(activity_label)
	var pause_button = _button("Ⅱ" if bool(group.get("active", false)) else "▶")
	pause_button.custom_minimum_size = Vector2(34.0, 30.0)
	pause_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pause_button.pressed.connect(func() -> void:
		_set_limb_group_active(group_id, not bool(limb_training.group_by_id(group_id).get("active", false)))
	)
	header.add_child(pause_button)
	var worker_row = HBoxContainer.new()
	worker_row.add_theme_constant_override("separation", 7)
	shell.add_child(worker_row)
	var worker_label = Label.new()
	worker_label.custom_minimum_size.x = 76.0
	worker_row.add_child(worker_label)
	var worker_slider = HSlider.new()
	worker_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	worker_slider.min_value = 1.0
	worker_slider.max_value = float(FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT)
	worker_slider.step = 1.0
	worker_slider.value = float(group.get("pending_worker_count", group.get("worker_count", 1)))
	worker_slider.tooltip_text = "Four-limb worker count\n\nMore bodies collect experience faster but use more CPU. Changing the count rebuilds this group and immediately restarts its current episode, just like a drone group."
	group["worker_slider_dragging"] = false
	worker_slider.drag_started.connect(func() -> void:
		var live_group = limb_training.group_by_id(group_id)
		if not live_group.is_empty():
			live_group["worker_slider_dragging"] = true
	)
	worker_slider.value_changed.connect(_on_limb_worker_slider_value_changed.bind(group_id))
	worker_slider.drag_ended.connect(_on_limb_worker_slider_drag_ended.bind(group_id))
	worker_slider.focus_exited.connect(_on_limb_worker_slider_focus_exited.bind(group_id))
	worker_row.add_child(worker_slider)
	var details = VBoxContainer.new()
	details.visible = selected
	details.add_theme_constant_override("separation", 6)
	shell.add_child(details)
	var identity = Label.new()
	var limb_card_trainer: FourLimbPPOTrainer = group.get("trainer") as FourLimbPPOTrainer
	var limb_architecture: Dictionary = (
		limb_card_trainer.network_architecture() if limb_card_trainer != null else {}
	)
	identity.text = "FOUR-LIMB BODY · 16 direct outputs (12 joints + 4 grips) · PPO · %s" % _network_architecture_text(limb_architecture)
	identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	identity.add_theme_color_override("font_color", Color("ffad42"))
	details.add_child(identity)
	var lineage_label = Label.new()
	lineage_label.text = (
		"Root model"
		if int(group.get("parent_group_id", -1)) < 0
		else "Child variant · %s%% weight variation" % String.num(
			float(group.get("branch_weight_variation", 0.0)) * 100.0,
			1
		)
	)
	lineage_label.add_theme_color_override("font_color", Color("5ab889"))
	details.add_child(lineage_label)
	var reward_label = Label.new()
	reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(reward_label)
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 6)
	actions.add_theme_constant_override("v_separation", 6)
	details.add_child(actions)
	var overwrite_button = ROLLING_SAVE_BUTTON_SCRIPT.new() as Button
	overwrite_button.text = (
		"KEEP NEWEST: ON"
		if bool(group.get("overwrite_saved_versions", true))
		else "KEEP NEWEST: OFF"
	)
	overwrite_button.toggle_mode = true
	overwrite_button.tooltip_text = (
		"Keep only the newest limb-model save\n\n"
		+ "Off: every save creates another numbered version.\n"
		+ "On: this group reuses one rolling version for later saves.\n\n"
		+ "A model loaded or branched from is never overwritten. The moving border means this mode is active."
	)
	overwrite_button.call(
		"configure",
		group["color"],
		bool(group.get("overwrite_saved_versions", true))
	)
	overwrite_button.toggled.connect(func(enabled: bool) -> void:
		_set_limb_group_overwrite_saved_versions(group_id, enabled)
	)
	actions.add_child(overwrite_button)
	var branch_button = _button("BRANCH VARIANT", true)
	branch_button.tooltip_text = "Branch this four-limb model\n\nCreates an independent child with copied policy weights, PPO settings, reward cards, worker settings, and physical anatomy."
	branch_button.pressed.connect(func() -> void:
		_open_limb_branch_dialog_for_group(group_id)
	)
	actions.add_child(branch_button)
	if int(group.get("parent_group_id", -1)) >= 0:
		var root_button = _button("MAKE ROOT")
		root_button.tooltip_text = "Make root group\n\nDetaches this limb branch from its parent. Its learned policy and body remain unchanged."
		root_button.pressed.connect(func() -> void:
			_promote_limb_group_to_root(group_id)
		)
		actions.add_child(root_button)
	var model_button = _button("MODEL", true)
	model_button.tooltip_text = "Open model hub\n\nSave or load this group's separate four-limb PPO checkpoint."
	model_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_set_workspace_page("model")
	)
	actions.add_child(model_button)
	var tuning_button = _button("BODY / TUNING")
	tuning_button.tooltip_text = "Open tuning hub\n\nAdjust worker count, control rate, and four-limb PPO settings while paused."
	tuning_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_set_workspace_page("tuning")
	)
	actions.add_child(tuning_button)
	var plots_button = _button("PLOTS")
	plots_button.tooltip_text = "Open plots\n\nShows this group’s reward, target-following, learning, and policy-stability history."
	plots_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_set_workspace_page("plots")
	)
	actions.add_child(plots_button)
	var rewards_button = _button("REWARD CARDS", true)
	rewards_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_set_workspace_page("rewards")
	)
	actions.add_child(rewards_button)
	var save_button = _button("SAVE BEST")
	save_button.tooltip_text = "Save best snapshot\n\nSaves the best preserved four-limb policy for this group.\nWith Keep newest off, this creates another numbered version."
	save_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_save_limb_group(group_id, str(group.get("name", "Four Limb Model")), true)
	)
	actions.add_child(save_button)
	var save_current_button = _button("SAVE CURRENT")
	save_current_button.tooltip_text = "Save current snapshot\n\nSaves the exact four-limb weights controlling this group now.\nWith Keep newest off, this creates another numbered version."
	save_current_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_save_limb_group(group_id, str(group.get("name", "Four Limb Model")), false)
	)
	actions.add_child(save_current_button)
	var library_button = _button("LIMB MODELS")
	library_button.pressed.connect(func() -> void:
		_select_limb_group(group_id)
		_open_limb_model_browser()
	)
	actions.add_child(library_button)
	var remove_button = _button("REMOVE")
	_set_button_danger(remove_button)
	remove_button.pressed.connect(func() -> void:
		_remove_limb_group(group_id)
	)
	actions.add_child(remove_button)
	_attach_resize_handle(
		card,
		details,
		_on_limb_group_card_resized.bind(group_id)
	)
	group["card"] = card
	group["card_button"] = select_button
	group["name_edit"] = name_edit
	group["pause_button"] = pause_button
	group["activity_label"] = activity_label
	group["candidate_evaluation_label"] = candidate_evaluation_label
	group["best_score_label"] = best_score_label
	group["worker_slider"] = worker_slider
	group["worker_label"] = worker_label
	group["reward_label"] = reward_label
	group["hardware_label"] = null
	group["overwrite_button"] = overwrite_button
	if selected:
		call_deferred("_animate_box_open", details)


func _on_limb_group_name_submitted(_new_text: String, group_id: int) -> void:
	_commit_limb_group_name(group_id)


func _on_limb_group_name_focus_exited(group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit) and name_edit.visible:
		_commit_limb_group_name(group_id)


func _on_limb_group_name_gui_input(event: InputEvent, group_id: int) -> void:
	var rename_key = event as InputEventKey
	if rename_key == null or not rename_key.pressed or rename_key.keycode != KEY_ESCAPE:
		return
	_cancel_limb_group_rename(group_id)
	var group: Dictionary = limb_training.group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit):
		name_edit.accept_event()


func _on_drone_group_name_submitted(_new_text: String, group_id: int) -> void:
	_commit_group_name(group_id)


func _on_drone_group_name_focus_exited(group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit) and name_edit.visible:
		_commit_group_name(group_id)


func _on_drone_group_name_gui_input(event: InputEvent, group_id: int) -> void:
	var rename_key = event as InputEventKey
	if rename_key == null or not rename_key.pressed or rename_key.keycode != KEY_ESCAPE:
		return
	_cancel_group_rename(group_id)
	var group: Dictionary = _group_by_id(group_id)
	var name_edit = group.get("name_edit") as LineEdit
	if is_instance_valid(name_edit):
		name_edit.accept_event()


func _on_drone_worker_slider_value_changed(value: float, group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	if group.is_empty():
		return
	var worker_label = group.get("worker_label") as Label
	if is_instance_valid(worker_label):
		worker_label.text = "Workers: %d" % int(round(value))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_group_worker_count(group_id, int(round(value)))


func _on_drone_worker_slider_drag_ended(value_changed: bool, group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	if group.is_empty():
		return
	group["worker_slider_dragging"] = false
	if not value_changed:
		return
	var worker_slider = group.get("worker_slider") as HSlider
	if is_instance_valid(worker_slider):
		_set_group_worker_count(group_id, int(round(worker_slider.value)))


func _on_drone_worker_slider_focus_exited(group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	var worker_slider = group.get("worker_slider") as HSlider
	if is_instance_valid(worker_slider):
		_set_group_worker_count(group_id, int(round(worker_slider.value)))


func _on_drone_group_card_resized(new_height: float, group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	if not group.is_empty():
		group["card_minimum_height"] = new_height


func _on_limb_worker_slider_value_changed(value: float, group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	if group.is_empty():
		return
	var worker_label = group.get("worker_label") as Label
	if is_instance_valid(worker_label):
		worker_label.text = "Workers: %d" % int(round(value))
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_limb_group_worker_count(group_id, int(round(value)))


func _on_limb_worker_slider_drag_ended(value_changed: bool, group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	if group.is_empty():
		return
	group["worker_slider_dragging"] = false
	if not value_changed:
		return
	var worker_slider = group.get("worker_slider") as HSlider
	if is_instance_valid(worker_slider):
		_set_limb_group_worker_count(group_id, int(round(worker_slider.value)))


func _on_limb_worker_slider_focus_exited(group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	var worker_slider = group.get("worker_slider") as HSlider
	if is_instance_valid(worker_slider):
		_set_limb_group_worker_count(group_id, int(round(worker_slider.value)))


func _on_limb_group_card_resized(new_height: float, group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	if not group.is_empty():
		group["card_minimum_height"] = new_height


func _child_groups(parent_group_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group in worker_groups:
		if int(group.get("parent_group_id", -1)) == parent_group_id:
			result.append(group)
	return result


func _refresh_group_card_texts() -> void:
	for group in worker_groups:
		var trainer: DroneTrainingAlgorithm = group["trainer"]
		var button = group.get("card_button") as Button
		if button != null:
			var card_text = "%s %s  ·  %s\n%s %s  ·  update %d  ·  %s  ·  %s" % [
				("▼" if int(group["group_id"]) == selected_group_id else "▶"),
				str(group["name"]),
				("running" if bool(group["active"]) else "paused"),
				trainer.algorithm_short_name(),
				_network_architecture_compact_text(trainer.network_architecture()),
				trainer.update_count_value(),
				_group_model_short_name(group),
				group_episode_progress_text(group, "drone"),
			]
			if button.text != card_text:
				button.text = card_text
			button.add_theme_color_override("font_color", group["color"])
		var evaluation_candidate_id: int = trainer.pending_evaluation_candidate_id()
		var evaluation_label = group.get("candidate_evaluation_label") as Label
		if evaluation_label != null:
			evaluation_label.visible = evaluation_candidate_id >= 0
			if evaluation_candidate_id >= 0:
				evaluation_label.text = _candidate_evaluation_compact_text(group)
				evaluation_label.tooltip_text = _candidate_evaluation_tooltip(group)
		var best_score_label = group.get("best_score_label") as Label
		if best_score_label != null:
			var best_summary = trainer.best_selection_summary()
			if best_summary.is_empty():
				best_score_label.text = "BEST —"
				best_score_label.tooltip_text = (
					"No policy has passed fixed-seed verification yet. The current frozen candidate is being evaluated; this label becomes a numeric BEST score only after a candidate is promoted."
					if evaluation_candidate_id >= 0
					else "No policy has passed fixed-seed verification yet. BEST is reserved for a policy that completed the deterministic evaluation suite."
				)
			else:
				best_score_label.text = "BEST %+.3f/s" % float(best_summary.get("selection_score", 0.0))
				best_score_label.tooltip_text = "Best fixed-seed-verified policy score for this group. Training-candidate scores are separate and do not become BEST until deterministic evaluation promotes them."
		var is_active = bool(group["active"])
		var pause_button = group.get("pause_button") as Button
		if pause_button != null:
			pause_button.text = "Ⅱ" if is_active else "▶"
			pause_button.tooltip_text = (
				"Pause this group\n\nStops its workers and learning while keeping the live weights in memory."
				if is_active
				else "Resume this group\n\nStarts its workers and continues learning from the current live weights."
			)
		var activity_label = group.get("activity_label") as Label
		if activity_label != null:
			activity_label.visible = is_active
			activity_label.text = GROUP_ACTIVITY_FRAMES[group_activity_animation_frame]
		_refresh_group_rolling_save_button(group)
		var compact_worker_slider = group.get("worker_slider") as HSlider
		if compact_worker_slider != null:
			compact_worker_slider.max_value = float(trainer.maximum_worker_count())
			if not bool(group.get("worker_slider_dragging", false)):
				compact_worker_slider.set_value_no_signal(float(group["worker_count"]))
		var compact_worker_label = group.get("worker_label") as Label
		if compact_worker_label != null:
			compact_worker_label.text = "Workers: %d" % int(group["worker_count"])
		var model_label = group.get("model_label") as Label
		if model_label != null:
			model_label.text = "Using: %s" % _group_model_summary(group)
		var reward_label = group.get("reward_label") as Label
		if reward_label != null:
			reward_label.text = "Rewards: %s" % _reward_summary(
				group.get("reward_components", {})
			)
		var hardware_label = group.get("hardware_label") as Label
		if hardware_label != null:
			hardware_label.text = "Drone: %s" % _compact_loadout_text(
				group.get("drone_loadout") as DroneLoadout
			)
		var auto_save_label = group.get("auto_save_label") as Label
		if auto_save_label != null:
			_refresh_group_auto_save_label(group, auto_save_label)
	for limb_group: Dictionary in limb_training.groups:
		var limb_trainer = limb_group["trainer"] as FourLimbPPOTrainer
		var limb_optimizing = bool(limb_group.get("optimizer_waiting", false))
		var limb_active = bool(limb_group.get("active", false))
		var limb_state_text = (
			"running · optimizing"
			if limb_active and limb_optimizing
			else (
				"running"
				if limb_active
				else ("optimizer finishing" if limb_optimizing else "paused")
			)
		)
		var limb_button = limb_group.get("card_button") as Button
		if limb_button != null:
			limb_button.text = "%s %s  ·  %s\nFOUR-LIMB PPO  ·  %s  ·  update %d  ·  %s" % [
				("▼" if int(limb_group["group_id"]) == selected_limb_group_id else "▶"),
				str(limb_group["name"]),
				limb_state_text,
				_network_architecture_compact_text(limb_trainer.network_architecture()),
				limb_trainer.update_count,
				group_episode_progress_text(limb_group, "limb"),
			]
			limb_button.add_theme_color_override("font_color", limb_group["color"])
		var limb_candidate_id: int = limb_trainer.pending_evaluation_candidate_id()
		var limb_evaluation_label = limb_group.get("candidate_evaluation_label") as Label
		if limb_evaluation_label != null:
			limb_evaluation_label.visible = limb_candidate_id >= 0
			if limb_candidate_id >= 0:
				limb_evaluation_label.text = _candidate_evaluation_compact_text(limb_group)
				limb_evaluation_label.tooltip_text = _candidate_evaluation_tooltip(limb_group)
		var limb_best = limb_group.get("best_score_label") as Label
		if limb_best != null:
			var limb_summary = limb_trainer.best_selection_summary()
			if limb_summary.is_empty():
				limb_best.text = "BEST —"
				limb_best.tooltip_text = (
					"No policy has passed fixed-seed verification yet. The current frozen candidate is being evaluated; this label becomes a numeric BEST score only after a candidate is promoted."
					if limb_candidate_id >= 0
					else "No policy has passed fixed-seed verification yet. BEST is reserved for a policy that completed the deterministic evaluation suite."
				)
			else:
				limb_best.text = "BEST %+.3f/s" % float(limb_summary.get("selection_score", 0.0))
				limb_best.tooltip_text = "Best fixed-seed-verified policy score for this group. Training-candidate scores are separate and do not become BEST until deterministic evaluation promotes them."
		var limb_pause = limb_group.get("pause_button") as Button
		if limb_pause != null:
			limb_pause.text = "Ⅱ" if limb_active else "▶"
			limb_pause.tooltip_text = (
				"Pause this group. The current optimizer job will finish safely, but no new bodies will spawn."
				if limb_optimizing and limb_active
				else ("Pause this four-limb group." if limb_active else "Resume this four-limb group.")
			)
		var limb_activity = limb_group.get("activity_label") as Label
		if limb_activity != null:
			limb_activity.visible = limb_active
			limb_activity.text = GROUP_ACTIVITY_FRAMES[group_activity_animation_frame]
		var limb_worker_slider = limb_group.get("worker_slider") as HSlider
		if (
			limb_worker_slider != null
			and not bool(limb_group.get("worker_slider_dragging", false))
		):
			limb_worker_slider.set_value_no_signal(float(limb_group.get("pending_worker_count", limb_group.get("worker_count", 1))))
		var limb_worker_label = limb_group.get("worker_label") as Label
		if limb_worker_label != null:
			limb_worker_label.text = "Workers: %d" % int(limb_group.get("pending_worker_count", limb_group.get("worker_count", 1)))
		var limb_reward_label = limb_group.get("reward_label") as Label
		if limb_reward_label != null:
			var enabled_card_count = 0
			var total_card_count = 0
			for card_value: FourLimbRewardCard in (
				limb_group["reward_deck"] as FourLimbRewardDeck
			).card_list():
				total_card_count += 1
				if card_value.enabled:
					enabled_card_count += 1
			limb_reward_label.text = "Reward cards: %d/%d enabled" % [
				enabled_card_count,
				total_card_count,
			]
	turret_ui.refresh_group_cards()
	_refresh_all_groups_pause_button()


static func _network_architecture_compact_text(architecture: Dictionary) -> String:
	var width: int = RLTrainingMath.finite_int_or(architecture.get("hidden_layer_width", 0), 0)
	var depth: int = RLTrainingMath.finite_int_or(architecture.get("hidden_layer_depth", 0), 0)
	if width <= 0 or depth <= 0:
		return "?×?"
	return "%d×%d" % [depth, width]


static func _network_architecture_text(architecture: Dictionary) -> String:
	return "hidden %s" % _network_architecture_compact_text(architecture)


func _group_model_summary(group: Dictionary) -> String:
	if group.is_empty():
		return "none"
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var source_name = str(group.get("source_label", "Fresh policy"))
	var source_update = int(group.get(
		"source_update_count",
		trainer.update_count_value()
	))
	var newer_updates = maxi(trainer.update_count_value() - source_update, 0)
	var source_summary: String = (
		source_name
		if newer_updates <= 0
		else "%s · %d updates newer" % [source_name, newer_updates]
	)
	return "%s · %s" % [
		source_summary,
		_network_architecture_text(trainer.network_architecture()),
	]


func _group_model_short_name(group: Dictionary) -> String:
	return str(group.get("source_label", "Fresh policy"))


func _selected_group_rename_target() -> Dictionary:
	if selected_group_id >= 0:
		return {"kind": "drone", "group_id": selected_group_id}
	if selected_limb_group_id >= 0:
		return {"kind": "four_limb", "group_id": selected_limb_group_id}
	if selected_turret_group_id >= 0:
		return {"kind": "turret", "group_id": selected_turret_group_id}
	return {}


func _begin_selected_group_rename() -> bool:
	var target = _selected_group_rename_target()
	if target.is_empty():
		return false
	var group_id = int(target["group_id"])
	match str(target["kind"]):
		"drone":
			return _begin_group_rename(group_id)
		"four_limb":
			return _begin_limb_group_rename(group_id)
		"turret":
			return turret_ui.begin_group_rename(group_id)
	return false


func _begin_limb_group_rename(group_id: int) -> bool:
	if group_id != selected_limb_group_id:
		return false
	var group: Dictionary = limb_training.group_by_id(group_id)
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
	_blink_group_name_edit(name_edit)
	return true


func _cancel_limb_group_rename(group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
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


func _commit_limb_group_name(group_id: int) -> void:
	var group: Dictionary = limb_training.group_by_id(group_id)
	if group.is_empty():
		return
	var name_edit = group.get("name_edit") as LineEdit
	var select_button = group.get("card_button") as Button
	if name_edit == null or not name_edit.visible:
		return
	var requested_name: String = name_edit.text.strip_edges()
	if requested_name.is_empty():
		name_edit.text = str(group["name"])
		status_label.text = "A worker group needs a name."
		name_edit.grab_focus()
		name_edit.select_all()
		return
	var old_name: String = str(group["name"])
	var new_name: String = _unique_group_name_for_kind(requested_name, "four_limb", group_id)
	group["name"] = new_name
	if new_name != old_name:
		# Rolling checkpoint identity belongs to the saved model family, not merely to this
		# runtime worker. Renaming must fork the next save so its manifest can carry the new
		# name instead of silently overwriting the old family under its old display name.
		group["rolling_version_id"] = ""
	name_edit.text = new_name
	name_edit.visible = false
	name_edit.modulate.a = 1.0
	name_edit.release_focus()
	if select_button != null:
		select_button.visible = true
	plots_dirty = true
	if selected_limb_group_id == group_id:
		selected_group_title.text = new_name
	_refresh_group_card_texts()
	if new_name != old_name:
		status_label.text = "%s renamed to %s. Future saves use the new name." % [old_name, new_name]


func _blink_group_name_edit(name_edit: LineEdit) -> void:
	if not is_instance_valid(name_edit):
		return
	var blink = create_tween()
	blink.tween_property(name_edit, "modulate:a", 0.35, 0.08)
	blink.tween_property(name_edit, "modulate:a", 1.0, 0.08)
	blink.tween_property(name_edit, "modulate:a", 0.35, 0.08)
	blink.tween_property(name_edit, "modulate:a", 1.0, 0.08)


func _begin_group_rename(group_id: int) -> bool:
	if group_id != selected_group_id:
		return false
	var group = _group_by_id(group_id)
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
	_blink_group_name_edit(name_edit)
	return true


func _cancel_group_rename(group_id: int) -> void:
	var group = _group_by_id(group_id)
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
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	var name_edit = group.get("name_edit") as LineEdit
	var select_button = group.get("card_button") as Button
	if name_edit == null or not name_edit.visible:
		return
	var requested_name = name_edit.text.strip_edges()
	if requested_name.is_empty():
		name_edit.text = str(group["name"])
		status_label.text = "A worker group needs a name."
		name_edit.grab_focus()
		name_edit.select_all()
		return
	var old_name = str(group["name"])
	var new_name = _unique_group_name_for_kind(requested_name, "drone", group_id)
	group["name"] = new_name
	group["model_family_name"] = new_name
	if new_name != old_name:
		# Do not keep overwriting a rolling version whose manifest belongs to the old name.
		# The existing version remains the lineage/source; the next save creates a new named
		# version and becomes this group's new rolling target.
		group["rolling_version_id"] = ""
	name_edit.text = new_name
	name_edit.visible = false
	name_edit.modulate.a = 1.0
	name_edit.release_focus()
	if select_button != null:
		select_button.visible = true
	plots_dirty = true
	if selected_group_id == group_id:
		selected_group_title.text = new_name
	_refresh_group_card_texts()
	if new_name != old_name:
		status_label.text = "%s renamed to %s. Future saves use the new name." % [
			old_name,
			new_name,
		]


func _unique_group_name(requested_name: String, ignored_group_id: int) -> String:
	return _unique_group_name_for_kind(requested_name, "drone", ignored_group_id)


func _rolling_record_matches_requested_name(
	record: Dictionary,
	requested_name: String
) -> bool:
	if record.is_empty():
		return false
	return (
		str(record.get("model_name", "")).strip_edges()
		== requested_name.strip_edges()
	)


func _unique_group_name_for_kind(
	requested_name: String,
	ignored_kind: String,
	ignored_group_id: int
) -> String:
	var base_name = requested_name.strip_edges().substr(0, GROUP_NAME_MAX_LENGTH)
	if base_name.is_empty():
		base_name = "Worker group"
	var candidate = base_name
	var suffix = 2
	while true:
		var conflict = false
		for group in worker_groups:
			if (
				not (ignored_kind == "drone" and int(group.get("group_id", -1)) == ignored_group_id)
				and str(group.get("name", "")).nocasecmp_to(candidate) == 0
			):
				conflict = true
				break
		if not conflict:
			for group: Dictionary in limb_training.groups:
				if (
					not (ignored_kind == "four_limb" and int(group.get("group_id", -1)) == ignored_group_id)
					and str(group.get("name", "")).nocasecmp_to(candidate) == 0
				):
					conflict = true
					break
		if not conflict:
			for group: Dictionary in turret_training.groups:
				if (
					not (ignored_kind == "turret" and int(group.get("group_id", -1)) == ignored_group_id)
					and str(group.get("name", "")).nocasecmp_to(candidate) == 0
				):
					conflict = true
					break
		if not conflict:
			return candidate
		var suffix_text = " %d" % suffix
		candidate = base_name.substr(
			0,
			maxi(GROUP_NAME_MAX_LENGTH - suffix_text.length(), 1)
		) + suffix_text
		suffix += 1
	return ""


func _build_model_body_creator() -> void:
	model_body_creator = MLBodyCreatorPanel.new()
	# Dynamically-created Window nodes default to visible. Hide before entering the scene tree so
	# the creator only appears after the Worker Groups + button is pressed.
	model_body_creator.visible = false
	model_body_creator.create_requested.connect(_on_model_body_creator_requested)
	add_child(model_body_creator)


func _open_model_body_creator() -> void:
	if model_body_creator == null or not is_instance_valid(model_body_creator):
		return
	model_body_creator.open_creator()
	status_label.text = "Model Body Creator opened. Choose a Core, lay out its mounts, then equip the authored slots."


func _on_model_body_creator_requested(request: Dictionary) -> void:
	var body_kind: String = str(request.get("body_kind", "")).strip_edges()
	var requested_name: String = str(request.get("name", "Model worker group")).strip_edges()
	var runtime_body: Resource = request.get("runtime_body") as Resource
	if runtime_body == null:
		status_label.text = "The creator returned no runtime body."
		return
	var training_value: Variant = request.get("training", {})
	var training: Dictionary = training_value as Dictionary if training_value is Dictionary else {}
	var requested_worker_count: int = int(training.get("worker_count", -1))
	var start_active: bool = bool(training.get("start_active", true))
	var reward_cards_value: Variant = training.get("reward_cards", {})
	var reward_cards: Dictionary = (
		(reward_cards_value as Dictionary).duplicate(true)
		if reward_cards_value is Dictionary
		else {}
	)
	var reward_cardset_id: String = str(training.get("reward_cardset_id", "")).strip_edges()
	var reward_cardset_name: String = str(training.get("reward_cardset_name", "")).strip_edges()
	var reward_setup: Dictionary = {}
	if not reward_cards.is_empty() or not reward_cardset_id.is_empty() or not reward_cardset_name.is_empty():
		reward_setup = {
			"cards": reward_cards,
			"id": reward_cardset_id,
			"name": reward_cardset_name,
		}
	var network_config: Dictionary = {}
	if training.has("hidden_layer_width"):
		network_config["hidden_layer_width"] = clampi(
			int(training.get("hidden_layer_width", DronePPOActorCritic.HIDDEN_SIZE)),
			DronePPOMLP.MINIMUM_HIDDEN_WIDTH,
			DronePPOMLP.MAXIMUM_HIDDEN_WIDTH
		)
	if training.has("hidden_layer_depth"):
		network_config["hidden_layer_depth"] = clampi(
			int(training.get("hidden_layer_depth", DronePPOActorCritic.HIDDEN_LAYER_COUNT)),
			DronePPOMLP.MINIMUM_HIDDEN_DEPTH,
			DronePPOMLP.MAXIMUM_HIDDEN_DEPTH
		)
	if training.has("control_rate_hz"):
		var control_rate_hz: float = clampf(float(training.get("control_rate_hz", 20.0)), 2.0, 60.0)
		network_config["control_interval_seconds"] = 1.0 / control_rate_hz
	match body_kind:
		"drone":
			var drone_loadout: DroneLoadout = runtime_body as DroneLoadout
			if drone_loadout == null:
				status_label.text = "The accepted creator body is not a drone loadout."
				return
			var algorithm_id: String = str(training.get(
				"algorithm_id",
				DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
			))
			var exploration_key: String = _branch_exploration_config_key(algorithm_id)
			if training.has("exploration_strength") and not exploration_key.is_empty():
				network_config[exploration_key] = maxf(
					float(training.get("exploration_strength", 0.01)),
					0.0
				)
			var initial_setup: Dictionary = {
				"drone_loadout": drone_loadout,
			}
			if requested_worker_count > 0:
				initial_setup["worker_count"] = requested_worker_count
			if not network_config.is_empty():
				initial_setup["config"] = network_config
			if not reward_setup.is_empty():
				initial_setup["reward_cards"] = reward_cards
				if not reward_cardset_id.is_empty():
					initial_setup["reward_cardset_id"] = reward_cardset_id
				if not reward_cardset_name.is_empty():
					initial_setup["reward_cardset_name"] = reward_cardset_name
			var group: Dictionary = _create_worker_group(
				false,
				{},
				requested_name,
				-1,
				0.0,
				algorithm_id,
				initial_setup
			)
			if not group.is_empty():
				if start_active:
					_set_group_active(int(group["group_id"]), true)
				status_label.text = "%s created from the Model Body Creator%s." % [
					str(group["name"]),
					" and started" if start_active else " paused",
				]
		"articulated_body":
			var definition: FourLimbBodyDefinition = runtime_body as FourLimbBodyDefinition
			if definition == null:
				status_label.text = "The accepted creator body is not a four-limb definition."
				return
			var limb_worker_count: int = (
				requested_worker_count
				if requested_worker_count > 0
				else FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT
			)
			_create_four_limb_worker_group(
				definition,
				requested_name,
				limb_worker_count,
				network_config,
				start_active,
				reward_setup
			)
		"turret":
			var turret_loadout: TurretLoadout = runtime_body as TurretLoadout
			if turret_loadout == null:
				status_label.text = "The accepted creator body is not a turret loadout."
				return
			var turret_worker_count: int = (
				requested_worker_count
				if requested_worker_count > 0
				else TurretTrainingCoordinator.DEFAULT_WORKER_COUNT
			)
			_create_turret_worker_group(
				turret_loadout,
				requested_name,
				turret_worker_count,
				network_config,
				start_active,
				reward_setup
			)
		_:
			status_label.text = "Body kind '%s' is not connected to a worker trainer yet." % body_kind


func _apply_creator_reward_setup(group: Dictionary, reward_setup: Dictionary) -> void:
	if group.is_empty() or reward_setup.is_empty():
		return
	var cards_value: Variant = reward_setup.get("cards", {})
	var deck: Object = group.get("reward_deck") as Object
	if cards_value is Dictionary and deck != null and deck.has_method("load_configuration"):
		deck.call("load_configuration", (cards_value as Dictionary).duplicate(true))
	var cardset_id: String = str(reward_setup.get("id", "custom")).strip_edges()
	var cardset_name: String = str(reward_setup.get("name", "Custom")).strip_edges()
	group["reward_cardset_id"] = cardset_id if not cardset_id.is_empty() else "custom"
	group["reward_cardset_name"] = cardset_name if not cardset_name.is_empty() else "Custom"
	# Any pending edit belongs to the previous/default deck. Creator-selected rewards are the
	# group's initial accepted state and must reach its first episode/evaluation contract directly.
	group["pending_reward_config"] = {}


func _create_four_limb_worker_group(
	initial_body_definition: FourLimbBodyDefinition = null,
	requested_name: String = "",
	worker_count: int = FourLimbTrainingCoordinator.DEFAULT_WORKER_COUNT,
	network_config: Dictionary = {},
	start_active: bool = true,
	reward_setup: Dictionary = {}
) -> void:
	group_counter += 1
	var hue = float(posmod(group_counter * 2371, 10000)) / 10000.0
	var default_name: String = "Limb worker group %d" % group_counter
	var group_name: String = requested_name if not requested_name.strip_edges().is_empty() else default_name
	var group = limb_training.create_group(
		group_counter,
		_unique_group_name(group_name, -1),
		Color.from_hsv(hue, 0.68, 0.95),
		clampi(worker_count, 1, FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT),
		initial_body_definition,
		network_config
	)
	if group.is_empty():
		status_label.text = limb_training.last_error
		return
	_apply_creator_reward_setup(group, reward_setup)
	var group_id: int = int(group["group_id"])
	limb_training.set_control_interval(
		group_id,
		float(network_config.get(
			"control_interval_seconds",
			FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS
		))
	)
	_ensure_group_target_handler(group_id, group["color"])
	_select_limb_group(group_id)
	if start_active:
		limb_training.set_group_active(
			group_id,
			true,
			drone_spawn_position,
			_target_objective_position(group_id),
			_target_velocity_for_group_id(group_id),
			_target_radius_for_group_id(group_id),
			episode_duration,
			ARENA_SIZE
		)
	_rebuild_group_cards()
	status_label.text = "%s created %s in the shared arena." % [
		str(group["name"]),
		"running" if start_active else "paused",
	]


func _create_turret_worker_group(
	initial_loadout: TurretLoadout = null,
	requested_name: String = "",
	worker_count: int = TurretTrainingCoordinator.DEFAULT_WORKER_COUNT,
	network_config: Dictionary = {},
	start_active: bool = true,
	reward_setup: Dictionary = {}
) -> void:
	group_counter += 1
	var hue = float(posmod(group_counter * 2371, 10000)) / 10000.0
	var default_name: String = "Turret worker group %d" % group_counter
	var group_name: String = requested_name if not requested_name.strip_edges().is_empty() else default_name
	var group = turret_training.create_group(
		group_counter,
		_unique_group_name(group_name, -1),
		Color.from_hsv(hue, 0.68, 0.95),
		clampi(worker_count, 1, TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT),
		initial_loadout,
		network_config
	)
	if group.is_empty():
		status_label.text = turret_training.last_error
		return
	_apply_creator_reward_setup(group, reward_setup)
	var group_id: int = int(group["group_id"])
	turret_training.set_control_interval(
		group_id,
		float(network_config.get(
			"control_interval_seconds",
			TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS
		))
	)
	_ensure_group_target_handler(group_id, group["color"])
	_select_turret_group(group_id)
	_rebuild_group_cards()
	# Turrets still need authored positions. For multi-worker groups, placement proceeds one body at
	# a time; the final confirmation starts the group only when requested by the creator.
	_begin_turret_placement(group_id, start_active, 0, false)


func _open_selected_branch_dialog() -> void:
	if selected_turret_group_id >= 0 and not _selected_turret_group().is_empty():
		turret_ui.open_branch_dialog(selected_turret_group_id)
		return
	if selected_limb_group_id >= 0 and not _selected_limb_group().is_empty():
		_open_limb_branch_dialog_for_group(selected_limb_group_id)
		return
	_open_branch_dialog_for_group(selected_group_id)


func _open_branch_dialog_for_group(source_group_id: int) -> void:
	var source = _group_by_id(source_group_id)
	branch_source_group_id = int(source.get("group_id", -1))
	branch_source_version_id = ""
	model_browser_branch_source_mode = false
	if branch_algorithm_picker != null:
		branch_algorithm_picker.disabled = false
	branch_source_label.text = (
		"Policy source: live weights from %s" % source["name"]
		if not source.is_empty()
		else "Policy source: fresh random learning model"
	)
	branch_source_label.tooltip_text = (
		"Starting from a live group\n\nThe new group copies the selected model's current weights. Later learning remains independent."
		if not source.is_empty()
		else "Starting fresh\n\nNo group is selected, so the new group begins with random weights."
	)
	branch_name_edit.text = _unique_group_name(
		(
			"%s variant" % source["name"]
			if not source.is_empty()
			else "Worker group %d" % (group_counter + 1)
		),
		-1
	)
	var source_algorithm_id = str(source.get(
		"algorithm_id",
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	))
	for index in range(branch_algorithm_picker.item_count):
		if str(branch_algorithm_picker.get_item_metadata(index)) == source_algorithm_id:
			branch_algorithm_picker.select(index)
			break
	branch_variation_slider.editable = not source.is_empty()
	branch_variation_slider.value = (
		DEFAULT_BRANCH_WEIGHT_VARIATION if not source.is_empty() else 0.0
	)
	var rewards = (
		source.get("reward_components", {})
		if not source.is_empty()
		else DroneTrainingReward.DEFAULT_COMPONENTS
	)
	for reward_key in branch_reward_checks:
		var check = branch_reward_checks[reward_key] as CheckBox
		if check != null:
			check.button_pressed = bool(rewards.get(reward_key, true))
	_update_branch_reward_warning()
	if branch_belly_grabber_checkbox != null:
		branch_belly_grabber_checkbox.button_pressed = (
			LOADOUT_CONFIG.has_training_belly_grabber(source.get("drone_loadout") as DroneLoadout)
			if not source.is_empty()
			else false
		)
	if branch_start_active_checkbox != null:
		branch_start_active_checkbox.button_pressed = true
	_update_branch_algorithm_state()
	_popup_branch_dialog_centered()


func _popup_branch_dialog_centered() -> void:
	if branch_dialog == null:
		return
	branch_dialog.size = Vector2i(620, 760)
	branch_dialog.popup_centered()
	call_deferred("_center_branch_dialog_window")
	call_deferred("_focus_branch_name_edit")


func _center_branch_dialog_window() -> void:
	if branch_dialog == null or not branch_dialog.visible:
		return
	var viewport_size = Vector2i(get_viewport().get_visible_rect().size)
	var desired_size = Vector2i(
		mini(620, maxi(viewport_size.x - 40, branch_dialog.min_size.x)),
		mini(760, maxi(viewport_size.y - 40, branch_dialog.min_size.y))
	)
	branch_dialog.size = desired_size
	branch_dialog.position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _focus_branch_name_edit() -> void:
	if branch_dialog == null or not branch_dialog.visible or branch_name_edit == null:
		return
	branch_name_edit.grab_focus()
	branch_name_edit.select_all()


func _confirm_branch_group() -> void:
	var rewards = DroneTrainingReward.DEFAULT_COMPONENTS.duplicate()
	for reward_key in branch_reward_checks:
		var check = branch_reward_checks[reward_key] as CheckBox
		if check != null:
			rewards[reward_key] = check.button_pressed
	var saved_source = _model_version_by_id(branch_source_version_id)
	var clone_source = _group_by_id(branch_source_group_id)
	var algorithm_id = _selected_branch_algorithm_id()
	if not saved_source.is_empty():
		algorithm_id = str(saved_source.get(
			"training_algorithm_id",
			DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
		))
	var belly_grabber_enabled = (
		_saved_drone_version_has_belly_grabber(saved_source)
		if not saved_source.is_empty()
		else bool(branch_belly_grabber_checkbox.button_pressed)
		if branch_belly_grabber_checkbox != null
		else false
	)
	if belly_grabber_enabled and saved_source.is_empty():
		algorithm_id = "ppo_clip"
	var can_clone = (
		saved_source.is_empty()
		and not clone_source.is_empty()
		and DroneTrainingAlgorithmCatalog.can_branch(
			str(clone_source.get("algorithm_id", "")),
			algorithm_id
		)
	)
	var source_trainer = clone_source.get("trainer") as DroneTrainingAlgorithm
	var initial_config: Dictionary = (
		source_trainer.config_values().duplicate(true)
		if can_clone and source_trainer != null
		else {}
	)
	initial_config["control_interval_seconds"] = 1.0 / maxf(
		branch_control_rate_slider.value,
		1.0
	)
	if branch_hidden_width_slider != null:
		initial_config["hidden_layer_width"] = int(round(branch_hidden_width_slider.value))
	if branch_hidden_depth_slider != null:
		initial_config["hidden_layer_depth"] = int(round(branch_hidden_depth_slider.value))
	var exploration_key = _branch_exploration_config_key(algorithm_id)
	if (
		branch_exploration_slider != null
		and branch_exploration_slider.editable
		and not exploration_key.is_empty()
	):
		initial_config[exploration_key] = branch_exploration_slider.value
	var worker_setup: Dictionary = {
		"worker_count": int(round(branch_worker_count_slider.value)),
		"config": initial_config,
	}
	if not saved_source.is_empty():
		var saved_environment_value: Variant = saved_source.get("training_environment", {})
		if saved_environment_value is Dictionary:
			var saved_loadout_value: Variant = (saved_environment_value as Dictionary).get("drone_loadout", {})
			if saved_loadout_value is Dictionary and not (saved_loadout_value as Dictionary).is_empty():
				worker_setup["drone_loadout"] = (saved_loadout_value as Dictionary).duplicate(true)
	else:
		worker_setup["belly_grabber"] = belly_grabber_enabled
	var group = _create_worker_group(
		can_clone,
		rewards,
		branch_name_edit.text,
		branch_source_group_id,
		branch_variation_slider.value,
		algorithm_id,
		worker_setup
	)
	if not group.is_empty() and not saved_source.is_empty():
		if not _load_checkpoint_version_into_group(group, saved_source):
			_remove_group(int(group.get("group_id", -1)))
			group = {}
		else:
			var trainer = group.get("trainer") as DroneTrainingAlgorithm
			if trainer != null:
				trainer.set_config_value(
					"control_interval_seconds",
					1.0 / maxf(branch_control_rate_slider.value, 1.0)
				)
				if not exploration_key.is_empty():
					trainer.set_config_value(
						exploration_key,
						branch_exploration_slider.value
					)
			_refresh_selected_group_controls()
	branch_source_group_id = -1
	branch_source_version_id = ""
	if branch_algorithm_picker != null:
		branch_algorithm_picker.disabled = false
	if (
		not group.is_empty()
		and branch_start_active_checkbox != null
		and branch_start_active_checkbox.button_pressed
	):
		_set_group_active(int(group["group_id"]), true)


func _saved_drone_version_has_belly_grabber(version: Dictionary) -> bool:
	if version.is_empty():
		return false
	var environment_value: Variant = version.get("training_environment", {})
	if environment_value is Dictionary:
		var loadout_value: Variant = (environment_value as Dictionary).get("drone_loadout", {})
		if loadout_value is Dictionary and not (loadout_value as Dictionary).is_empty():
			return LOADOUT_CONFIG.has_training_belly_grabber(
				LOADOUT_CONFIG.from_record(loadout_value as Dictionary)
			)
	var runtime_contract_value: Variant = version.get("runtime_contract", {})
	if runtime_contract_value is Dictionary:
		var body_contract_value: Variant = (runtime_contract_value as Dictionary).get("body_interface", {})
		if body_contract_value is Dictionary:
			for slot_value: Variant in (body_contract_value as Dictionary).get("slots", []):
				if not (slot_value is Dictionary):
					continue
				var part_contract: Dictionary = (slot_value as Dictionary).get("part_contract", {})
				var tags: Array = part_contract.get("tags", []) if part_contract is Dictionary else []
				if "training_belly_grabber" in tags:
					return true
	return false


func _selected_branch_algorithm_id() -> String:
	if branch_algorithm_picker == null or branch_algorithm_picker.selected < 0:
		return DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	return str(branch_algorithm_picker.get_item_metadata(
		branch_algorithm_picker.selected
	))


func _branch_exploration_config_key(algorithm_id: String) -> String:
	match algorithm_id:
		"ppo_clip":
			return "entropy_coefficient"
		"sac_her_maze":
			return "entropy_temperature"
	return ""



func _algorithm_configuration_control(
	algorithm: DroneTrainingAlgorithm,
	key: String
) -> Dictionary:
	if algorithm == null or key.is_empty():
		return {}
	for definition: Dictionary in algorithm.configuration_controls():
		if str(definition.get("key", "")) == key:
			return definition.duplicate(true)
	return {}

func _update_branch_algorithm_state() -> void:
	if branch_algorithm_picker == null or branch_variation_slider == null:
		return
	var saved_source = _model_version_by_id(branch_source_version_id)
	var source = _group_by_id(branch_source_group_id)
	var algorithm_id = _selected_branch_algorithm_id()
	var belly_grabber_enabled = false
	if not saved_source.is_empty():
		belly_grabber_enabled = _saved_drone_version_has_belly_grabber(saved_source)
		algorithm_id = str(saved_source.get(
			"training_algorithm_id",
			DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
		))
	elif not source.is_empty():
		belly_grabber_enabled = LOADOUT_CONFIG.has_training_belly_grabber(
			source.get("drone_loadout") as DroneLoadout
		)
	elif branch_belly_grabber_checkbox != null:
		belly_grabber_enabled = branch_belly_grabber_checkbox.button_pressed
	if belly_grabber_enabled and saved_source.is_empty():
		algorithm_id = "ppo_clip"
	for index in range(branch_algorithm_picker.item_count):
		if str(branch_algorithm_picker.get_item_metadata(index)) == algorithm_id:
			branch_algorithm_picker.select(index)
			break
	if branch_belly_grabber_checkbox != null:
		branch_belly_grabber_checkbox.set_pressed_no_signal(belly_grabber_enabled)
		branch_belly_grabber_checkbox.disabled = (
			not saved_source.is_empty() or not source.is_empty()
		)
	branch_algorithm_picker.disabled = (not saved_source.is_empty() or belly_grabber_enabled)
	var can_clone = (
		saved_source.is_empty()
		and not source.is_empty()
		and DroneTrainingAlgorithmCatalog.can_branch(
			str(source.get("algorithm_id", "")),
			algorithm_id
		)
	)
	branch_variation_slider.editable = can_clone
	if not can_clone:
		branch_variation_slider.value = 0.0
	if not saved_source.is_empty():
		branch_source_label.text = "Policy source: saved %s" % model_registry.display_name(
			saved_source
		)
		branch_source_label.tooltip_text = (
			"Starting from a saved model\n\n"
			+ "The new group receives its own copy of this checkpoint. Later learning and rolling saves do not change the source model."
		)
	elif can_clone:
		branch_source_label.text = "Policy source: live %s weights from %s" % [
			str(source.get("algorithm_short_name", "model")),
			source["name"],
		]
		branch_source_label.tooltip_text = "Starting from live weights\n\nThe new group receives its own copy. Later learning remains independent."
	else:
		branch_source_label.text = "Policy source: fresh %s model" % str(
			DroneTrainingAlgorithmCatalog.descriptor(algorithm_id).get(
				"display_name",
				algorithm_id
			)
		)
		branch_source_label.tooltip_text = "Starting fresh\n\nThe new group uses random weights unless you select a saved model."
	if branch_model_source_button != null:
		branch_model_source_button.text = (
			"CHANGE SAVED MODEL" if not saved_source.is_empty()
			else "SELECT MODEL FROM LIBRARY"
		)
	if branch_clear_model_source_button != null:
		branch_clear_model_source_button.visible = not saved_source.is_empty()
	var preview_algorithm = _create_algorithm_preview(algorithm_id)
	if preview_algorithm == null:
		return
	var setup_source = source.get("trainer") as DroneTrainingAlgorithm
	var preview_architecture: Dictionary = preview_algorithm.network_architecture()
	var setup_config: Dictionary = preview_algorithm.config_values()
	if not saved_source.is_empty():
		var checkpoint = model_registry.load_training_checkpoint(saved_source)
		if not checkpoint.is_empty():
			var checkpoint_config: Variant = checkpoint.get("config", {})
			if checkpoint_config is Dictionary:
				setup_config = (checkpoint_config as Dictionary).duplicate(true)
	elif can_clone and setup_source != null:
		setup_config = setup_source.config_values()
	var architecture_locked: bool = not saved_source.is_empty() or can_clone
	if branch_hidden_width_slider != null:
		branch_hidden_width_slider.editable = not architecture_locked
		var preview_hidden_width: int = RLTrainingMath.finite_int_or(
			preview_architecture.get("hidden_layer_width", DronePPOActorCritic.HIDDEN_SIZE),
			DronePPOActorCritic.HIDDEN_SIZE
		)
		branch_hidden_width_slider.value = float(RLTrainingMath.finite_int_or(
			setup_config.get("hidden_layer_width", preview_hidden_width),
			preview_hidden_width
		))
	if branch_hidden_depth_slider != null:
		branch_hidden_depth_slider.editable = not architecture_locked
		var preview_hidden_depth: int = RLTrainingMath.finite_int_or(
			preview_architecture.get("hidden_layer_depth", DronePPOActorCritic.HIDDEN_LAYER_COUNT),
			DronePPOActorCritic.HIDDEN_LAYER_COUNT
		)
		branch_hidden_depth_slider.value = float(RLTrainingMath.finite_int_or(
			setup_config.get("hidden_layer_depth", preview_hidden_depth),
			preview_hidden_depth
		))
	if branch_worker_count_slider != null:
		branch_worker_count_slider.max_value = float(
			preview_algorithm.maximum_worker_count()
		)
		branch_worker_count_slider.value = float(
			int(source.get("worker_count", preview_algorithm.default_worker_count()))
			if can_clone
			else preview_algorithm.default_worker_count()
		)
	if branch_control_rate_slider != null:
		var preview_control_interval = clampf(
			RLTrainingMath.finite_float_or(
				setup_config.get("control_interval_seconds"),
				0.05
			),
			0.01,
			1.0
		)
		branch_control_rate_slider.value = 1.0 / preview_control_interval
	if branch_exploration_slider != null:
		var exploration_key = _branch_exploration_config_key(algorithm_id)
		var exploration_control = _algorithm_configuration_control(
			preview_algorithm,
			exploration_key
		)
		branch_exploration_slider.editable = (
			not exploration_key.is_empty()
			and setup_config.has(exploration_key)
			and not exploration_control.is_empty()
		)
		if not exploration_control.is_empty():
			branch_exploration_slider.min_value = float(
				exploration_control.get("minimum", 0.0)
			)
			branch_exploration_slider.max_value = float(
				exploration_control.get("maximum", 1.0)
			)
			branch_exploration_slider.step = maxf(
				float(exploration_control.get("step", 0.001)),
				0.000001
			)
			branch_exploration_slider.allow_lesser = false
			branch_exploration_slider.allow_greater = false
		branch_exploration_slider.value = float(setup_config.get(
			exploration_key,
			0.0
		))
		branch_exploration_slider.tooltip_text = _readable_tooltip(str(exploration_control.get(
			"tooltip",
			"Exploration setting\n\nThe selected algorithm does not provide a separate exploration control."
		)))


func _update_branch_reward_warning() -> void:
	if branch_reward_warning == null:
		return
	var approach_check = branch_reward_checks.get("approach") as CheckBox
	var radius_check = branch_reward_checks.get("radius") as CheckBox
	var has_positive_target_reward = (
		approach_check != null
		and radius_check != null
		and (approach_check.button_pressed or radius_check.button_pressed)
	)
	if has_positive_target_reward:
		branch_reward_warning.text = "Each switch affects only this new branch."
		branch_reward_warning.add_theme_color_override(
			"font_color",
			Color("a8d8c1")
		)
	else:
		branch_reward_warning.text = "Warning: this branch has no positive target reward, so it has no score signal telling it to reach or hold the target."
		branch_reward_warning.add_theme_color_override(
			"font_color",
			Color("ffad42")
		)


func _reward_component_tooltip(reward_key: String) -> String:
	return {
		"approach": "Move toward target\n\nMoving closer gives positive score. Moving farther away gives negative score.\nUseful partial progress is kept even when the drone never reaches the target radius.",
		"radius": "Hold near target\n\nGives positive score for each simulated second spent inside the hover radius.\nThis is the main task reward.",
		"survival": "Stay alive\n\nAdds a small reward that grows during the episode and a small bonus for reaching the time limit.\nIt is intentionally much weaker than holding the target.",
		"ground_safety": "Keep ground clearance\n\nPunishes descending while closer than 2 m to solid ground or objects below the drone.\nVery low clearance also receives a small warning cost.",
		"smoothness": "Use sensible propeller commands\n\nTiny corrections are free. Large command jumps and sustained extreme or heavily uneven output are punished.",
		"obstacle": "Avoid walls and objects\n\nPunishes moving into nearby geometry and adds a small contact cost.\nStanding safely nearby or moving away is not punished.",
		"failure": "Avoid terminal failure\n\nDestruction, power loss, arena exit, wall deadlock, and any optional per-group ground/flipped cutoff give a strong negative score.\nGround contact and inverted orientation are non-terminal by default. Very early terminal failure is punished extra so immediate suicide is not a shortcut.",
	}.get(reward_key, "")


func _reward_summary(rewards: Dictionary) -> String:
	var enabled: Array[String] = []
	for reward_key in [
		"approach", "radius", "survival", "ground_safety",
		"smoothness", "obstacle", "failure",
	]:
		if bool(rewards.get(reward_key, true)):
			enabled.append(str(DroneTrainingRoomPresentation.REWARD_COMPONENT_LABELS[reward_key]))
	return " · ".join(PackedStringArray(enabled)) if not enabled.is_empty() else "None"


func _select_group(group_id: int) -> void:
	if group_id >= 0 and _group_by_id(group_id).is_empty():
		return
	turret_ui.release_manual_keys()
	var selection_changed = (
		selected_group_id != group_id
		or selected_limb_group_id >= 0
		or selected_turret_group_id >= 0
		or selected_evaluator_instance_id >= 0
	)
	selected_group_id = group_id
	selected_limb_group_id = -1
	selected_turret_group_id = -1
	selected_evaluator_instance_id = -1
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_apply_selection_highlight()
	_rebuild_group_cards()
	_rebuild_reward_cards()
	if camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE:
		_select_attached_camera_host(true)
	if selection_changed:
		_set_workspace_page("plots" if group_id < 0 else "model")
	else:
		_refresh_plots()


func _select_limb_group(group_id: int) -> void:
	if group_id >= 0 and limb_training.group_by_id(group_id).is_empty():
		return
	turret_ui.release_manual_keys()
	var selection_changed = (
		selected_limb_group_id != group_id
		or selected_group_id >= 0
		or selected_turret_group_id >= 0
		or selected_evaluator_instance_id >= 0
	)
	selected_limb_group_id = group_id
	selected_group_id = -1
	selected_turret_group_id = -1
	selected_evaluator_instance_id = -1
	_release_attached_camera()
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_apply_selection_highlight()
	_rebuild_group_cards()
	_rebuild_reward_cards()
	if selection_changed:
		_set_workspace_page("model" if group_id >= 0 else "plots")
	else:
		_refresh_plots()


func _select_turret_group(group_id: int) -> void:
	if group_id >= 0 and turret_training.group_by_id(group_id).is_empty():
		return
	turret_ui.release_manual_keys()
	var selection_changed = (
		selected_turret_group_id != group_id
		or selected_group_id >= 0
		or selected_limb_group_id >= 0
		or selected_evaluator_instance_id >= 0
	)
	selected_turret_group_id = group_id
	selected_group_id = -1
	selected_limb_group_id = -1
	selected_evaluator_instance_id = -1
	_release_attached_camera()
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_apply_selection_highlight()
	_rebuild_group_cards()
	_rebuild_reward_cards()
	if selection_changed:
		_set_workspace_page("model" if group_id >= 0 else "plots")
	else:
		_refresh_plots()


func _set_group_worker_count(group_id: int, requested_count: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var worker_count = clampi(
		requested_count,
		1,
		trainer.maximum_worker_count()
	)
	if int(group["worker_count"]) == worker_count:
		return
	group["worker_count"] = worker_count
	if bool(group.get("active", false)):
		# A worker-count change alters the set of on-policy trajectories. Rebuild this
		# group's drones, then restart the shared episode. _start_episode() discards every
		# active group's unfinished fragment so no policy learns across the reset boundary.
		trainer.discard_incomplete_rollout()
		_remove_trials_for_group(group_id)
		group["control_elapsed"] = 0.0
		if not _spawn_drone_group_population(group):
			group["active"] = false
			_rebuild_group_cards()
			_refresh_selected_group_controls()
			_refresh_all_groups_pause_button()
			return
		_start_episode("%s now uses %d workers." % [group["name"], worker_count])
	else:
		# Paused drones are retained for an ordinary pause, but changing the population is an
		# episode-semantic boundary just like it is for limb and turret groups. Do not leave an
		# obsolete frozen population around and then silently continue its partial rollout.
		_clear_drone_group_runtime_for_configuration_change(group)
		status_label.text = "%s will use %d workers when resumed." % [
			group["name"],
			worker_count,
		]
	_refresh_group_card_texts()
	_refresh_selected_group_controls()


func _set_group_overwrite_saved_versions(group_id: int, enabled: bool) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	group["overwrite_saved_versions"] = enabled
	# Enabling starts a new group-owned rolling chain on the next save. Disabling also
	# forgets the old target, so re-enabling later cannot unexpectedly overwrite it.
	group["rolling_version_id"] = ""
	_refresh_group_rolling_save_button(group)
	status_label.text = (
		"%s will keep one newest group-owned model version. Its source checkpoint remains untouched."
		% str(group.get("name", "Worker group"))
		if enabled
		else "%s will create a new numbered version for every save."
		% str(group.get("name", "Worker group"))
	)


func _set_limb_group_overwrite_saved_versions(group_id: int, enabled: bool) -> void:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty():
		return
	group["overwrite_saved_versions"] = enabled
	# As with drones, toggling never revives an old target. This makes it impossible for a
	# loaded or branched source checkpoint to become an accidental overwrite destination.
	group["rolling_version_id"] = ""
	_refresh_limb_group_rolling_save_button(group)
	status_label.text = (
		"%s will keep one newest group-owned limb model version. Its source checkpoint remains untouched."
		% str(group.get("name", "Four-limb group"))
		if enabled
		else "%s will create a new numbered limb-model version for every save."
		% str(group.get("name", "Four-limb group"))
	)


func _refresh_group_rolling_save_button(group: Dictionary) -> void:
	var button = group.get("overwrite_button") as Button
	if button == null:
		return
	var enabled = bool(group.get("overwrite_saved_versions", true))
	button.text = "KEEP NEWEST: ON" if enabled else "KEEP NEWEST: OFF"
	button.call("set_rolling_active", enabled)


func _refresh_limb_group_rolling_save_button(group: Dictionary) -> void:
	var button = group.get("overwrite_button") as Button
	if button == null:
		return
	var enabled = bool(group.get("overwrite_saved_versions", true))
	button.set_pressed_no_signal(enabled)
	button.text = "KEEP NEWEST: ON" if enabled else "KEEP NEWEST: OFF"
	button.call("set_rolling_active", enabled)


func _refresh_all_groups_pause_button() -> void:
	if all_groups_pause_button == null:
		return
	var has_groups = (
		not worker_groups.is_empty()
		or not limb_training.groups.is_empty()
		or not turret_training.groups.is_empty()
	)
	all_groups_pause_button.disabled = not has_groups
	var any_running = false
	for group in worker_groups:
		if bool(group.get("active", false)):
			any_running = true
			break
	if not any_running:
		for group: Dictionary in limb_training.groups:
			if bool(group.get("active", false)):
				any_running = true
				break
	if not any_running:
		for group: Dictionary in turret_training.groups:
			if bool(group.get("active", false)):
				any_running = true
				break
	all_groups_pause_button.text = "Ⅱ" if any_running else "▶"
	all_groups_pause_button.add_theme_stylebox_override(
		"normal",
		DroneTrainingRoomPresentation.scanner_button_style(not any_running)
	)
	all_groups_pause_button.add_theme_color_override(
		"font_color",
		Color("ffad42") if not any_running else Color("a8d8c1")
	)
	all_groups_pause_button.tooltip_text = (
		"Pause all groups\n\nStops drone, four-limb, and turret training while keeping every live model in memory."
		if any_running
		else "Resume all groups\n\nStarts every paused drone, four-limb, and turret worker group."
	)


func _toggle_all_groups() -> void:
	var any_running = false
	for group in worker_groups:
		if bool(group.get("active", false)):
			any_running = true
			break
	if not any_running:
		for group: Dictionary in limb_training.groups:
			if bool(group.get("active", false)):
				any_running = true
				break
	if not any_running:
		for group: Dictionary in turret_training.groups:
			if bool(group.get("active", false)):
				any_running = true
				break
	_set_all_groups_active(not any_running)


func _set_all_groups_active(active: bool) -> void:
	if (
		worker_groups.is_empty()
		and limb_training.groups.is_empty()
		and turret_training.groups.is_empty()
	):
		_refresh_all_groups_pause_button()
		return
	var drone_changed = false
	var drone_population_created = false
	var drone_population_failure: String = ""
	var unplaced_turret_count: int = 0
	if active:
		var rebuild_drone_groups: Array[Dictionary] = []
		var retained_drone_groups: Array[Dictionary] = []
		for group: Dictionary in worker_groups:
			if bool(group.get("active", false)):
				continue
			if _drone_group_population_matches(group):
				retained_drone_groups.append(group)
			else:
				rebuild_drone_groups.append(group)
		# Configuration-invalid groups need a genuine new episode. Keep exact retained groups
		# inactive until that boundary has been created so Resume All cannot reset another
		# group's suspended episode merely because one paused group changed its hardware/count.
		for group: Dictionary in rebuild_drone_groups:
			group["active"] = true
			(group["trainer"] as DroneTrainingAlgorithm).discard_incomplete_rollout()
			_remove_trials_for_group(int(group["group_id"]))
			group["control_elapsed"] = 0.0
			if not _spawn_drone_group_population(group):
				group["active"] = false
				drone_population_failure = status_label.text
				continue
			drone_population_created = true
			drone_changed = true
		if drone_population_created:
			_start_episode("Rebuilt changed drone groups before resuming retained workers.")
		for group: Dictionary in retained_drone_groups:
			group["active"] = true
			_set_drone_group_trials_paused(group, false)
			drone_changed = true
	else:
		for group in worker_groups:
			if not bool(group.get("active", false)):
				continue
			group["active"] = false
			_set_drone_group_trials_paused(group, true)
			drone_changed = true
	for group: Dictionary in limb_training.groups:
		var limb_group_id: int = int(group["group_id"])
		limb_training.set_group_active(
			limb_group_id,
			active,
			drone_spawn_position,
			_target_objective_position(limb_group_id),
			_target_velocity_for_group_id(limb_group_id),
			_target_radius_for_group_id(limb_group_id),
			episode_duration,
			ARENA_SIZE
		)
	for group: Dictionary in turret_training.groups:
		var turret_group_id: int = int(group["group_id"])
		if not turret_training.set_group_active(
			turret_group_id,
			active,
			_target_objective_position(turret_group_id),
			episode_duration,
			ARENA_SIZE
		):
			if active and not bool(group.get("placement_configured", false)):
				unplaced_turret_count += 1
	if drone_changed and active and not episode_running:
		if _has_runtime_active_drone_trials():
			# Resume a frozen in-progress episode exactly where it was paused. Limb and turret
			# groups already preserve their live episode state; drone groups must do the same.
			episode_running = true
			intermission_remaining = 0.0
		elif _has_active_drone_group() and intermission_remaining <= 0.0:
			# Every retained trial is already finished and no suspended intermission remains,
			# so a real new cycle is required.
			_start_episode("All worker groups resumed into a new episode.")
	if active and not drone_population_failure.is_empty():
		status_label.text = drone_population_failure
	elif active and unplaced_turret_count > 0:
		status_label.text = "Placed worker groups resumed; %d turret group%s still need placement." % [
			unplaced_turret_count,
			"" if unplaced_turret_count == 1 else "s",
		]
	else:
		status_label.text = "All worker groups resumed." if active else "All worker groups paused."
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	_refresh_all_groups_pause_button()


func _set_group_active(group_id: int, active: bool) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty() or bool(group["active"]) == active:
		return
	if active:
		group["active"] = true
		if not _drone_group_population_matches(group):
			(group["trainer"] as DroneTrainingAlgorithm).discard_incomplete_rollout()
			_remove_trials_for_group(group_id)
			group["control_elapsed"] = 0.0
			if not _spawn_drone_group_population(group):
				group["active"] = false
				_rebuild_group_cards()
				_refresh_selected_group_controls()
				_refresh_all_groups_pause_button()
				return
			_start_episode("%s resumed." % str(group["name"]))
		else:
			_set_drone_group_trials_paused(group, false)
			var has_unfinished_trial = false
			for trial_value: Variant in group.get("trials", []):
				if trial_value is Dictionary and not bool((trial_value as Dictionary).get("episode_finished", false)):
					has_unfinished_trial = true
					break
			if not has_unfinished_trial:
				# If another drone group is still inside the shared room cycle, this group simply
				# waits for that cycle to end. If it was paused during the room intermission, keep
				# the remaining delay just like the limb coordinator instead of skipping it.
				if not episode_running and intermission_remaining <= 0.0:
					_start_episode("%s resumed into a new episode." % str(group["name"]))
			elif not episode_running:
				episode_running = true
				intermission_remaining = 0.0
	else:
		group["active"] = false
		_set_drone_group_trials_paused(group, true)
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	_refresh_all_groups_pause_button()
	status_label.text = "%s %s." % [group["name"], "resumed" if active else "paused"]


func _set_drone_group_trials_paused(group: Dictionary, paused: bool) -> void:
	for trial_value: Variant in group.get("trials", []):
		if not (trial_value is Dictionary):
			continue
		var trial: Dictionary = trial_value
		if bool(trial.get("episode_finished", false)):
			continue
		var drone = trial.get("drone") as ServerDrone
		if is_instance_valid(drone):
			drone.set_ml_training_paused(paused)
		var combat_adapter = trial.get("combat_adapter") as TrainingCombatantAdapter
		if combat_adapter != null:
			combat_adapter.set_simulation_active(not paused)


func _drone_group_population_matches(group: Dictionary) -> bool:
	var group_trials: Array = group.get("trials", [])
	if group_trials.size() != int(group.get("worker_count", 0)):
		return false
	for trial_value: Variant in group_trials:
		if not (trial_value is Dictionary):
			return false
		var drone = (trial_value as Dictionary).get("drone") as ServerDrone
		if not is_instance_valid(drone):
			return false
	return true


func _clear_drone_group_runtime_for_configuration_change(group: Dictionary) -> void:
	if group.is_empty():
		return
	var trainer = group.get("trainer") as DroneTrainingAlgorithm
	if trainer != null:
		trainer.discard_incomplete_rollout()
	var history = group.get("history") as DroneTrainingMetricsHistory
	var episode_numbers: Dictionary = {}
	for trial_value: Variant in group.get("trials", []):
		if not (trial_value is Dictionary):
			continue
		var trial: Dictionary = trial_value
		var episode = trial.get("episode") as DroneTrainingEpisode
		if episode != null:
			episode_numbers[episode.episode_number] = true
	if history != null:
		for episode_number_value: Variant in episode_numbers.keys():
			history.discard_incomplete_episode(int(episode_number_value))
	_remove_trials_for_group(int(group.get("group_id", -1)))
	group["control_elapsed"] = 0.0


func _toggle_selected_group() -> void:
	var group = _selected_group()
	if not group.is_empty():
		_set_group_active(int(group["group_id"]), not bool(group["active"]))
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		_set_limb_group_active(
			int(limb_group["group_id"]),
			not bool(limb_group.get("active", false))
		)
		return
	var turret_group = _selected_turret_group()
	if not turret_group.is_empty():
		turret_ui.set_group_active(
			int(turret_group["group_id"]),
			not bool(turret_group.get("active", false))
		)


func _remove_selected_group() -> void:
	if selected_group_id >= 0:
		_remove_group(selected_group_id)
	elif selected_limb_group_id >= 0:
		_remove_limb_group(selected_limb_group_id)
	elif selected_turret_group_id >= 0:
		turret_ui.remove_group(selected_turret_group_id)




func _set_limb_group_active(group_id: int, active: bool) -> void:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty() or bool(group.get("active", false)) == active:
		return
	limb_training.set_group_active(
		group_id,
		active,
		drone_spawn_position,
		_target_objective_position(group_id),
		_target_velocity_for_group_id(group_id),
		_target_radius_for_group_id(group_id),
		episode_duration,
		ARENA_SIZE
	)
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	_refresh_all_groups_pause_button()
	status_label.text = "%s %s." % [
		str(group["name"]),
		"resumed" if active else "paused",
	]


func _set_limb_group_worker_count(group_id: int, requested_count: int) -> void:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty():
		return
	var worker_count = clampi(
		requested_count,
		1,
		FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT
	)
	if (
		int(group.get("worker_count", 0)) == worker_count
		and int(group.get("pending_worker_count", 0)) == worker_count
	):
		return
	limb_training.apply_worker_count_now(
		group_id,
		worker_count,
		drone_spawn_position,
		_target_objective_position(group_id),
		_target_velocity_for_group_id(group_id),
		_target_radius_for_group_id(group_id),
		episode_duration,
		ARENA_SIZE
	)
	_refresh_group_card_texts()
	_refresh_selected_group_controls()
	status_label.text = "%s now uses %d workers%s." % [
		str(group["name"]),
		worker_count,
		" and restarted its episode" if bool(group.get("active", false)) else " when resumed",
	]


func _remove_limb_group(group_id: int) -> void:
	var existing = limb_training.group_by_id(group_id)
	if existing.is_empty():
		return
	var replacement_parent_id = int(existing.get("parent_group_id", -1))
	for child: Dictionary in limb_training.groups:
		if int(child.get("parent_group_id", -1)) == group_id:
			child["parent_group_id"] = replacement_parent_id
	_clear_turret_target_references_to_group(group_id)
	var group = limb_training.remove_group(group_id)
	if group.is_empty():
		return
	_remove_action_trace_source("four_limb", group_id)
	_remove_group_target_handler(group_id)
	if selected_limb_group_id == group_id:
		selected_limb_group_id = -1
	_rebuild_group_cards()
	_rebuild_reward_cards()
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_apply_selection_highlight()
	_refresh_all_groups_pause_button()
	status_label.text = "%s removed. Saved four-limb models were kept." % str(group["name"])


func _promote_selected_group_to_root() -> void:
	if selected_turret_group_id >= 0 and not _selected_turret_group().is_empty():
		var turret_group = _selected_turret_group()
		if int(turret_group.get("parent_group_id", -1)) >= 0:
			turret_group["parent_group_id"] = -1
			_rebuild_group_cards()
			_refresh_selected_group_controls()
			status_label.text = "%s is now an independent turret root model." % turret_group["name"]
		return
	if selected_limb_group_id >= 0 and not _selected_limb_group().is_empty():
		_promote_limb_group_to_root(selected_limb_group_id)
		return
	_promote_group_to_root(selected_group_id)


func _promote_limb_group_to_root(group_id: int) -> void:
	var group = limb_training.group_by_id(group_id)
	if group.is_empty() or int(group.get("parent_group_id", -1)) < 0:
		return
	group["parent_group_id"] = -1
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	status_label.text = "%s is now an independent four-limb root model." % group["name"]


func _promote_group_to_root(group_id: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty() or int(group.get("parent_group_id", -1)) < 0:
		return
	group["parent_group_id"] = -1
	group["model_family_name"] = str(group["name"])
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	status_label.text = "%s is now a root model. Its %d descendant model(s) moved with it." % [
		group["name"],
		_count_group_descendants(group_id),
	]


func _count_group_descendants(group_id: int) -> int:
	var count = 0
	for child_group in _child_groups(group_id):
		count += 1 + _count_group_descendants(int(child_group["group_id"]))
	return count


func _remove_group(group_id: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	_flush_group_pending_auto_save(group, true)
	var replacement_parent_id = int(group.get("parent_group_id", -1))
	for child_group in _child_groups(group_id):
		child_group["parent_group_id"] = replacement_parent_id
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	trainer.discard_incomplete_rollout()
	if trainer.has_background_update():
		# Keep the owner alive until its already-running detached job can be joined. The
		# result is marked stale above and can never overwrite another model.
		retired_trainers.append(trainer)
	_cancel_candidate_evaluation(group_id)
	_remove_trials_for_group(group_id)
	_clear_turret_target_references_to_group(group_id)
	worker_groups.erase(group)
	worker_groups_by_id.erase(group_id)
	_remove_group_target_handler(group_id)
	_remove_action_trace_source("drone", group_id)
	plots_dirty = true
	if selected_group_id == group_id:
		selected_group_id = -1
	_rebuild_group_cards()
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_apply_selection_highlight()
	status_label.text = "%s removed. Saved versions were kept." % group["name"]
	if trials.is_empty():
		episode_running = false


func _spawn_drone_group_population(group: Dictionary) -> bool:
	if group.is_empty():
		return false
	var group_id: int = int(group.get("group_id", -1))
	var worker_count: int = maxi(int(group.get("worker_count", 0)), 0)
	if worker_count <= 0:
		status_label.text = "%s has no workers configured; training was not started." % str(
			group.get("name", "Drone group")
		)
		return false
	for worker_index: int in range(worker_count):
		if _spawn_training_worker(group, worker_index):
			continue
		# Never leave a UI group claiming to run with a partial/zero physical population. The old
		# activation path overwrote the worker-spawn error with "resumed", which made this exact
		# failure look like a renderer/episode bug instead of a rejected body contract.
		_remove_trials_for_group(group_id)
		group["control_elapsed"] = 0.0
		return false
	if not _drone_group_population_matches(group):
		_remove_trials_for_group(group_id)
		group["control_elapsed"] = 0.0
		status_label.text = "%s could not create its complete worker population." % str(
			group.get("name", "Drone group")
		)
		return false
	return true


func _spawn_training_worker(group: Dictionary, worker_index: int) -> bool:
	if not _ensure_group_drone_profile_hardware(group):
		status_label.text = "Could not build drone hardware matching this policy."
		return false
	var drone = DRONE_SCENE.instantiate() as ServerDrone
	if drone == null:
		status_label.text = "Could not instantiate a training drone."
		return false
	instance_counter += 1
	drone.name = "PPOGroup%02dWorker%03d" % [int(group["group_id"]), worker_index]
	drone.network_visible = false
	drone.position = drone_spawn_position
	drone.collision_layer = DRONE_COLLISION_LAYER
	drone.collision_mask = ARENA_COLLISION_LAYER
	drone.contact_monitor = true
	drone.max_contacts_reported = TRAINING_CONTACTS_REPORTED
	drone.starts_activated = false
	var group_loadout = group.get("drone_loadout") as DroneLoadout
	if group_loadout != null:
		drone.loadout = LOADOUT_CONFIG.duplicate_loadout(group_loadout)
	add_child(drone)
	_install_training_camera_part(drone)
	drone.set_ml_training_performance_mode(true)
	drone.set_ml_episode_unlimited_battery(unlimited_episode_battery)
	var expected_propeller_slots: int = group_loadout.core.propeller_slot_count if group_loadout != null and group_loadout.core != null else 0
	if expected_propeller_slots < 0 or drone.propeller_slots.size() != expected_propeller_slots:
		drone.queue_free()
		status_label.text = "Drone worker rejected: runtime propeller slots do not match the accepted Core layout."
		return false
	var runtime_manifest: MLBodyInterfaceManifest = drone.model_body_interface()
	var trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
	var trainer_architecture: Dictionary = (
		trainer.network_architecture() if trainer != null else {}
	)
	if (
		runtime_manifest == null
		or trainer == null
		or not DroneMLBodyInterfaceFactory.matches_trainer_architecture(
			runtime_manifest,
			trainer_architecture
		)
	):
		drone.queue_free()
		if runtime_manifest == null or trainer == null:
			status_label.text = "Drone worker rejected before episode start: its runtime body or trainer contract is missing."
		elif (
			int(trainer_architecture.get("action_count", -1)) != runtime_manifest.control_count()
			or int(trainer_architecture.get("body_feature_count", -1)) != runtime_manifest.observation_count()
		):
			status_label.text = (
				"Drone worker rejected before episode start: policy expects %d controls / %d body observations, runtime body exposes %d / %d."
				% [
					int(trainer_architecture.get("action_count", -1)),
					int(trainer_architecture.get("body_feature_count", -1)),
					runtime_manifest.control_count(),
					runtime_manifest.observation_count(),
				]
			)
		else:
			status_label.text = "Drone worker rejected before episode start: runtime body topology changed after the policy body was accepted."
		return false
	var runtime_validation_error: String = DroneMLBodyInterfaceFactory.training_runtime_validation_error(drone)
	if not runtime_validation_error.is_empty():
		drone.queue_free()
		status_label.text = "Drone worker rejected before episode start: %s" % runtime_validation_error
		return false
	DroneTrainingRoomPresentation.add_drone_visual(drone, group["color"])
	var trial: Dictionary = {
		"drone": drone,
		"instance_id": instance_counter,
		"worker_index": worker_index,
		"sensor_phase_index": worker_index,
		"mode": "algorithm_training",
		"group_id": int(group["group_id"]),
		"reward_components": group.get(
			"reward_components",
			DroneTrainingReward.DEFAULT_COMPONENTS
		).duplicate(),
		"reward_cards": _ensure_drone_reward_deck(group).configuration_dictionary(),
		"episode_termination": _episode_termination_options_for_group(group),
		"version": {},
		"color": group["color"],
		"episode": DroneTrainingEpisode.new(),
		"reward": {},
		"distance": INF,
		"episode_finished": true,
		"camera_focus_retired_at_usec": -1,
		"completed_episodes": 0,
		"best_mean_reward": -INF,
		"last_run_id": "",
		"action_sample": {},
		"held_action": {},
		"interval_reward": 0.0,
		"interval_delta_seconds": 0.0,
		"interval_reward_trace": {},
		"reward_trace_previous_position_world": drone.global_position,
		"obstacle_probe": DroneTrainingObstacleSensor.clear_probe(),
		"turret_threat_probe": TrainingTurretThreatSensor.empty_probe(),
		"turret_threat_sensor_elapsed": 0.0,
		"combat_adapter": _new_drone_combat_adapter(
			drone, int(group["group_id"]), worker_index
		),
		"obstacle_sensor_elapsed": OBSTACLE_SENSOR_INTERVAL_SECONDS,
	}
	trials.append(trial)
	(group["trials"] as Array).append(trial)
	return true


func _close_model_browser() -> void:
	if model_browser != null:
		model_browser.hide()
	if model_browser_branch_source_mode:
		model_browser_branch_source_mode = false
		call_deferred("_popup_branch_dialog_centered")


func _on_model_browser_primary_action() -> void:
	if model_browser_branch_source_mode:
		_select_saved_model_for_branch()
	else:
		_load_selected_checkpoint_into_group()


func _open_model_browser_for_branch_source() -> void:
	model_browser_branch_source_mode = true
	if branch_dialog != null:
		branch_dialog.hide()
	_refresh_model_versions(branch_source_version_id)
	_refresh_loader_identity()
	_popup_model_browser_centered()


func _clear_branch_saved_source() -> void:
	branch_source_version_id = ""
	if branch_algorithm_picker != null:
		branch_algorithm_picker.disabled = false
	_update_branch_algorithm_state()


func _select_saved_model_for_branch() -> void:
	var version = _selected_model_record()
	if version.is_empty():
		status_label.text = "Select a saved model version first."
		return
	if not DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
		status_label.text = "Only trainable checkpoints can become a worker-group source."
		return
	var inspection = model_registry.inspect_version(version)
	if not bool(inspection.get("trainable", false)):
		status_label.text = str(inspection.get(
			"compatibility_text",
			"This checkpoint cannot continue training in the current build."
		))
		return
	branch_source_version_id = str(version.get("version_id", ""))
	var algorithm_id = str(version.get(
		"training_algorithm_id",
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	))
	for index in range(branch_algorithm_picker.item_count):
		if str(branch_algorithm_picker.get_item_metadata(index)) == algorithm_id:
			branch_algorithm_picker.select(index)
			break
	branch_algorithm_picker.disabled = true
	var saved_environment: Dictionary = inspection.get("training_environment", {})
	var saved_rewards: Dictionary = saved_environment.get("reward_components", {})
	if not saved_rewards.is_empty():
		for reward_key in branch_reward_checks:
			var check = branch_reward_checks[reward_key] as CheckBox
			if check != null and saved_rewards.has(reward_key):
				check.button_pressed = bool(saved_rewards[reward_key])
	branch_name_edit.text = _unique_group_name(
		"%s continuation" % str(version.get("model_name", "Saved model")),
		-1
	)
	_update_branch_algorithm_state()
	_update_branch_reward_warning()
	model_browser_branch_source_mode = false
	model_browser.hide()
	_popup_branch_dialog_centered()
	status_label.text = "%s selected as the new group's starting policy." % model_registry.display_name(version)


func _model_version_by_id(version_id: String) -> Dictionary:
	if version_id.is_empty():
		return {}
	for version in model_versions:
		if str(version.get("version_id", "")) == version_id:
			return version
	for version in model_registry.list_versions():
		if str(version.get("version_id", "")) == version_id:
			return version
	return {}


func _open_model_browser(group_id: int) -> void:
	model_browser_branch_source_mode = false
	if group_id >= 0 and not _group_by_id(group_id).is_empty():
		if selected_group_id != group_id:
			_select_group(group_id)
	var preferred_version_id = ""
	var selected_version = _selected_model_record()
	if not selected_version.is_empty():
		preferred_version_id = str(selected_version.get("version_id", ""))
	_refresh_model_versions(preferred_version_id)
	_refresh_loader_identity()
	_popup_model_browser_centered()


func _popup_model_browser_centered() -> void:
	if model_browser == null:
		return
	model_browser.popup_centered(MODEL_BROWSER_SIZE)
	call_deferred("_center_model_browser_window")


func _center_model_browser_window() -> void:
	if model_browser == null or not model_browser.visible:
		return
	var viewport_size = Vector2i(get_viewport().get_visible_rect().size)
	var desired_size = Vector2i(
		mini(MODEL_BROWSER_SIZE.x, maxi(viewport_size.x - 40, model_browser.min_size.x)),
		mini(MODEL_BROWSER_SIZE.y, maxi(viewport_size.y - 40, model_browser.min_size.y))
	)
	model_browser.size = desired_size
	model_browser.position = Vector2i(
		maxi((viewport_size.x - desired_size.x) / 2, 0),
		maxi((viewport_size.y - desired_size.y) / 2, 0)
	)


func _spawn_selected_version() -> void:
	var version = _selected_model_record()
	if version.is_empty():
		status_label.text = "Select a saved model version first."
		return
	var policy = _model_for_version(version)
	if policy == null:
		status_label.text = "Evaluator not spawned: %s is incompatible or could not be read. %s" % [
			model_registry.display_name(version),
			model_registry.last_error,
		]
		return
	model_registry.mark_version_used(version)
	_refresh_model_versions(str(version.get("version_id", "")))
	_spawn_model_instance(version, policy)


func _spawn_model_instance(version: Dictionary, policy: DroneMLModel) -> void:
	if policy == null:
		status_label.text = "Evaluator not spawned because no valid model was loaded."
		return
	var drone = DRONE_SCENE.instantiate() as ServerDrone
	if drone == null:
		status_label.text = "Could not instantiate the evaluation drone."
		return
	instance_counter += 1
	drone.name = "EvaluationDrone%04d" % instance_counter
	drone.network_visible = false
	drone.position = drone_spawn_position
	drone.collision_layer = DRONE_COLLISION_LAYER
	drone.collision_mask = ARENA_COLLISION_LAYER
	drone.contact_monitor = true
	drone.max_contacts_reported = TRAINING_CONTACTS_REPORTED
	drone.starts_activated = false
	var training_environment_value: Variant = version.get("training_environment", {})
	var training_environment: Dictionary = (
		(training_environment_value as Dictionary)
		if training_environment_value is Dictionary
		else {}
	)
	var saved_reward_components_value: Variant = training_environment.get(
		"reward_components",
		DroneTrainingReward.DEFAULT_COMPONENTS
	)
	var saved_reward_components: Dictionary = (
		(saved_reward_components_value as Dictionary)
		if saved_reward_components_value is Dictionary
		else DroneTrainingReward.DEFAULT_COMPONENTS.duplicate(true)
	)
	var evaluator_reward_deck = DroneTrainingRewardDeck.new(saved_reward_components)
	var saved_reward_cards_value: Variant = training_environment.get("reward_cards", {})
	var saved_reward_cards: Dictionary = (
		(saved_reward_cards_value as Dictionary)
		if saved_reward_cards_value is Dictionary
		else {}
	)
	if not saved_reward_cards.is_empty():
		evaluator_reward_deck.load_configuration(saved_reward_cards)
	var saved_termination_value: Variant = training_environment.get("episode_termination", {})
	var saved_episode_termination: Dictionary = (
		(saved_termination_value as Dictionary).duplicate(true)
		if saved_termination_value is Dictionary
		else DroneTrainingEpisode.DEFAULT_TERMINATION_OPTIONS.duplicate(true)
	)
	var saved_loadout_value: Variant = training_environment.get("drone_loadout", {})
	var saved_loadout_record: Dictionary = (
		(saved_loadout_value as Dictionary)
		if saved_loadout_value is Dictionary
		else {}
	)
	if not saved_loadout_record.is_empty():
		drone.loadout = LOADOUT_CONFIG.from_record(saved_loadout_record)
		if drone.loadout == null:
			drone.queue_free()
			status_label.text = "Evaluator not spawned: the saved drone body record is invalid."
			return
	else:
		drone.loadout = LOADOUT_CONFIG.duplicate_loadout(drone.loadout)
	var saved_runtime_contract: Dictionary = {}
	if DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
		var saved_inspection: Dictionary = model_registry.inspect_version(version)
		var runtime_contract_value: Variant = saved_inspection.get("runtime_contract", {})
		saved_runtime_contract = (
			runtime_contract_value as Dictionary
			if runtime_contract_value is Dictionary
			else {}
		)
		if saved_runtime_contract.is_empty():
			drone.queue_free()
			status_label.text = "Evaluator not spawned: the saved policy has no valid body-interface contract."
			return
		# Arbitrary attachment topology cannot be reconstructed from action count. The exact
		# accepted gameplay loadout is the physical half of the model contract and must travel
		# with a non-stock body checkpoint.
		if saved_loadout_record.is_empty() and not _runtime_contract_is_stock_quad(saved_runtime_contract):
			drone.queue_free()
			status_label.text = "Evaluator not spawned: the saved custom body is missing its frozen loadout."
			return
	add_child(drone)
	_install_training_camera_part(drone)
	drone.set_ml_training_performance_mode(true)
	drone.set_ml_episode_unlimited_battery(unlimited_episode_battery)
	var evaluator_propeller_count: int = drone.loadout.core.propeller_slot_count if drone.loadout != null and drone.loadout.core != null else 0
	if evaluator_propeller_count < 0 or drone.propeller_slots.size() != evaluator_propeller_count:
		drone.queue_free()
		status_label.text = "Evaluator not spawned: runtime propeller slots do not match the saved body."
		return
	if not saved_runtime_contract.is_empty():
		var evaluator_manifest: MLBodyInterfaceManifest = drone.model_body_interface()
		if not DroneMLBodyInterfaceFactory.matches_runtime_contract(
			evaluator_manifest,
			saved_runtime_contract
		):
			drone.queue_free()
			status_label.text = "Evaluator not spawned: the saved body loadout does not match the policy interface."
			return
	var color = model_registry.color_for_version(version)
	DroneTrainingRoomPresentation.add_drone_visual(drone, color)
	trials.append({
		"drone": drone,
		"instance_id": instance_counter,
		"sensor_phase_index": instance_counter,
		"mode": "evaluation",
		"group_id": -1,
		"reward_components": evaluator_reward_deck.enabled_components_dictionary(),
		"reward_cards": evaluator_reward_deck.configuration_dictionary(),
		"episode_termination": saved_episode_termination,
		"version": version.duplicate(true),
		"evaluation_model": policy,
		"evaluation_error": "",
		"color": color,
		"episode": DroneTrainingEpisode.new(),
		"reward": {},
		"distance": INF,
		"episode_finished": true,
		"camera_focus_retired_at_usec": -1,
		"completed_episodes": 0,
		"best_mean_reward": -INF,
		"last_run_id": "",
		"action_sample": {},
		"held_action": {},
		"interval_reward": 0.0,
		"interval_delta_seconds": 0.0,
		"interval_reward_trace": {},
		"reward_trace_previous_position_world": drone.global_position,
		"obstacle_probe": DroneTrainingObstacleSensor.clear_probe(),
		"turret_threat_probe": TrainingTurretThreatSensor.empty_probe(),
		"turret_threat_sensor_elapsed": 0.0,
		"combat_adapter": _new_drone_combat_adapter(drone),
		"obstacle_sensor_elapsed": OBSTACLE_SENSOR_INTERVAL_SECONDS,
	})
	_rebuild_evaluator_cards()
	_apply_selection_highlight()
	_start_episode("Spawned evaluator %s." % model_registry.display_name(version))


func _rebuild_evaluator_cards() -> void:
	_refresh_default_target_visual_visibility()
	if evaluator_list == null:
		return
	for child in evaluator_list.get_children():
		child.queue_free()
	var evaluators = _evaluation_trials()
	if evaluator_summary_label != null:
		evaluator_summary_label.text = (
			"EVALUATION DRONES // NONE"
			if evaluators.is_empty()
			else "EVALUATION DRONES // %d" % evaluators.size()
		)
	for trial in evaluators:
		var instance_id = int(trial.get("instance_id", -1))
		var version: Dictionary = trial.get("version", {})
		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.tooltip_text = "Select evaluation drone\n\nClick the card, then use Selected group / evaluator camera focus to follow it."
		card.add_theme_stylebox_override(
			"panel",
			DroneTrainingRoomPresentation.scanner_panel_style(
				instance_id == selected_evaluator_instance_id
			)
		)
		card.gui_input.connect(_on_evaluator_card_input.bind(instance_id))
		evaluator_list.add_child(card)
		var shell = VBoxContainer.new()
		shell.add_theme_constant_override("separation", 6)
		shell.mouse_filter = Control.MOUSE_FILTER_PASS
		card.add_child(shell)
		var title = Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.text = "%s // evaluator %d" % [
			model_registry.display_name(version),
			instance_id,
		]
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var evaluator_color: Color = trial.get("color", Color("8de1ff"))
		title.add_theme_color_override("font_color", evaluator_color)
		shell.add_child(title)
		var status = Label.new()
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		shell.add_child(status)
		trial["evaluator_status_label"] = status
		var actions = HFlowContainer.new()
		actions.mouse_filter = Control.MOUSE_FILTER_PASS
		actions.add_theme_constant_override("h_separation", 6)
		actions.add_theme_constant_override("v_separation", 6)
		shell.add_child(actions)
		var inspect_button = _button("INSPECT MODEL")
		var version_deleted = bool(trial.get("version_deleted", false))
		inspect_button.disabled = version_deleted
		inspect_button.tooltip_text = (
			"Saved model was deleted\n\nThe evaluator can keep flying from memory, but there is no checkpoint left to inspect."
			if version_deleted
			else "Inspect evaluator model\n\nOpens the saved checkpoint controlling this drone. Running groups are not changed."
		)
		inspect_button.pressed.connect(_inspect_evaluator_model.bind(instance_id))
		actions.add_child(inspect_button)
		var remove_button = _button("REMOVE")
		remove_button.tooltip_text = "Remove evaluator\n\nDeletes only this test drone from the room.\nThe saved model and training groups remain."
		remove_button.pressed.connect(_remove_evaluator.bind(instance_id))
		_set_button_danger(remove_button)
		actions.add_child(remove_button)
	_refresh_evaluator_card_texts()


func _refresh_evaluator_card_texts() -> void:
	for trial in _evaluation_trials():
		var status = trial.get("evaluator_status_label") as Label
		if status == null:
			continue
		var reward: Dictionary = trial.get("reward", {})
		var phase = (
			"finished: %s" % str(reward.get("termination_reason", "complete"))
			if bool(trial.get("episode_finished", false))
			else "evaluating episode %d" % episode_number
		)
		status.text = "%s%s · reward %+.3f/s · distance %s m · %d runs%s" % [
			"SELECTED · " if int(trial.get("instance_id", -1)) == selected_evaluator_instance_id else "",
			phase,
			float(reward.get("mean_reward_per_second", 0.0)),
			String.num(float(reward.get("distance_m", 0.0)), 2),
			int(trial.get("completed_episodes", 0)),
			" · save deleted" if bool(trial.get("version_deleted", false)) else "",
		]


func _on_evaluator_card_input(event: InputEvent, instance_id: int) -> void:
	var mouse_event = event as InputEventMouseButton
	if (
		mouse_event == null
		or not mouse_event.pressed
		or mouse_event.button_index != MOUSE_BUTTON_LEFT
	):
		return
	_select_evaluator(
		-1 if selected_evaluator_instance_id == instance_id else instance_id
	)


func _select_evaluator(instance_id: int) -> void:
	if instance_id >= 0 and _trial_by_instance_id(instance_id).is_empty():
		return
	selected_group_id = -1
	selected_limb_group_id = -1
	selected_turret_group_id = -1
	selected_evaluator_instance_id = instance_id
	_refresh_selected_group_controls()
	_refresh_target_controls_for_selection()
	_rebuild_group_cards()
	_rebuild_evaluator_cards()
	_apply_selection_highlight()
	if instance_id >= 0:
		camera_focus_mode = CAMERA_FOCUS_SELECTED_SUBJECT
		if camera_focus_picker != null:
			camera_focus_picker.select(camera_focus_mode)
		_release_attached_camera()
		_center_camera_now()
		status_label.text = "Evaluation drone %d selected for camera focus." % instance_id
	else:
		_refresh_plots()


func _set_evaluation_drones_keep_episode_running(enabled: bool) -> void:
	evaluation_drones_keep_episode_running = enabled
	if evaluation_keep_episode_checkbox != null:
		evaluation_keep_episode_checkbox.set_pressed_no_signal(enabled)
	status_label.text = (
		"Evaluation drones now participate in the shared episode end condition."
		if enabled
		else "Evaluation drones no longer extend episodes while training workers are present."
	)
	if episode_running and _episode_completion_reached():
		_end_episode()


func _training_trials() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trial in trials:
		if str(trial.get("mode", "")) == "algorithm_training":
			result.append(trial)
	return result


func _trial_runtime_is_active(trial: Dictionary) -> bool:
	if bool(trial.get("episode_finished", false)):
		return false
	if str(trial.get("mode", "evaluation")) != "algorithm_training":
		return true
	var group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
	return not group.is_empty() and bool(group.get("active", false))


func _active_training_trials() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trial: Dictionary in _training_trials():
		var group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
		if not group.is_empty() and bool(group.get("active", false)):
			result.append(trial)
	return result


func _has_runtime_active_drone_trials() -> bool:
	for trial: Dictionary in trials:
		if _trial_runtime_is_active(trial):
			return true
	return false


func _has_active_drone_group() -> bool:
	for group: Dictionary in worker_groups:
		if bool(group.get("active", false)):
			return true
	return false


func _episode_completion_trials() -> Array[Dictionary]:
	var training = _active_training_trials()
	if not evaluation_drones_keep_episode_running and not training.is_empty():
		return training
	var result: Array[Dictionary] = []
	for trial: Dictionary in trials:
		if str(trial.get("mode", "evaluation")) == "algorithm_training":
			var group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
			if group.is_empty() or not bool(group.get("active", false)):
				continue
		# Evaluation trials remain part of the shared episode exactly as before. The pause
		# filter applies only to training groups; otherwise an evaluator-only room would never
		# reach _end_episode() after the last evaluation drone finishes.
		result.append(trial)
	return result


func _episode_completion_reached() -> bool:
	var blockers = _episode_completion_trials()
	return not blockers.is_empty() and DroneTrainingEpisode.all_finished(blockers)


func _finish_nonblocking_evaluators() -> void:
	if evaluation_drones_keep_episode_running or _active_training_trials().is_empty():
		return
	for trial in _evaluation_trials():
		if bool(trial.get("episode_finished", false)):
			continue
		var episode = trial.get("episode") as DroneTrainingEpisode
		if episode == null:
			trial["episode_finished"] = true
			continue
		trial["reward"] = episode.finish("training_workers_complete", true)
		_complete_trial_episode(trial)


func _evaluation_trials() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for trial in trials:
		if str(trial.get("mode", "")) == "evaluation":
			result.append(trial)
	return result


func _inspect_evaluator_model(instance_id: int) -> void:
	model_browser_branch_source_mode = false
	for trial in _evaluation_trials():
		if int(trial.get("instance_id", -1)) != instance_id:
			continue
		if bool(trial.get("version_deleted", false)):
			status_label.text = "This evaluator's checkpoint was deleted; only its in-memory policy remains."
			return
		var version: Dictionary = trial.get("version", {})
		_select_group(-1)
		_refresh_model_versions(str(version.get("version_id", "")))
		_refresh_loader_identity()
		_popup_model_browser_centered()
		return


func _remove_evaluator(instance_id: int) -> void:
	for index in range(trials.size() - 1, -1, -1):
		var trial: Dictionary = trials[index]
		if (
			str(trial.get("mode", "")) != "evaluation"
			or int(trial.get("instance_id", -1)) != instance_id
		):
			continue
		_unregister_trial_combatant(trial)
		var drone = trial.get("drone") as ServerDrone
		if is_instance_valid(drone):
			drone.queue_free()
		trials.remove_at(index)
		if selected_evaluator_instance_id == instance_id:
			selected_evaluator_instance_id = -1
		if attached_camera_instance_id == instance_id:
			_release_attached_camera()
		status_label.text = "Evaluation drone %d removed. Its saved model was kept." % instance_id
		break
	_rebuild_evaluator_cards()
	if trials.is_empty():
		episode_running = false
		intermission_remaining = 0.0
	elif episode_running and _episode_completion_reached():
		_end_episode()


func _start_episode(message: String) -> void:
	if trials.is_empty():
		episode_running = false
		intermission_remaining = 0.0
		status_label.text = "Create or resume a worker group to start an episode."
		return
	if episode_running:
		for group in worker_groups:
			if not bool(group.get("active", false)):
				# A paused group owns a suspended in-progress episode. Starting a new shared
				# cycle for other workers must not touch its rollout or history bookkeeping.
				continue
			var history = group.get("history") as DroneTrainingMetricsHistory
			var incomplete_episode_numbers: Dictionary = {}
			for trial_value: Variant in group.get("trials", []):
				if not (trial_value is Dictionary):
					continue
				var trial: Dictionary = trial_value
				if bool(trial.get("episode_finished", false)):
					continue
				var trial_episode = trial.get("episode") as DroneTrainingEpisode
				if trial_episode != null:
					incomplete_episode_numbers[trial_episode.episode_number] = true
			if history != null:
				for episode_number_value: Variant in incomplete_episode_numbers.keys():
					history.discard_incomplete_episode(int(episode_number_value))
			(group["trainer"] as DroneTrainingAlgorithm).discard_incomplete_rollout()
	for group in worker_groups:
		if bool(group.get("active", false)):
			_apply_pending_drone_reward_config(group)
			var trainer: DroneTrainingAlgorithm = group.get("trainer") as DroneTrainingAlgorithm
			if trainer != null:
				# PPO may nominate a frozen rollout candidate before this episode ends. Freeze the
				# exact task/hardware/reward contract before any transition from the episode enters
				# the rollout instead of waiting until episode-completion bookkeeping.
				trainer.set_evaluation_contract(
					_evaluation_contract_for_group_id(int(group.get("group_id", -1)), "drone")
				)
	episode_number += 1
	episode_seed = EPISODE_SEED_BASE + episode_number
	episode_elapsed = 0.0
	episode_running = true
	intermission_remaining = 0.0
	_reset_action_trace_for_episode()
	_reset_target_for_episode()
	var spawn_transform = Transform3D(Basis.IDENTITY, drone_spawn_position)
	var start_errors: Array[String] = []
	for trial in trials:
		if str(trial.get("mode", "evaluation")) == "algorithm_training":
			var trial_group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
			if trial_group.is_empty() or not bool(trial_group.get("active", false)):
				# Paused groups retain their exact live body, episode, held action, reward state,
				# and control-interval progress while other groups begin another episode.
				continue
		var drone = trial.get("drone") as ServerDrone
		var version: Dictionary = trial.get("version", {})
		var policy: DroneMLModel = null
		var is_evaluation = str(trial.get("mode", "evaluation")) == "evaluation"
		if is_evaluation:
			policy = trial.get("evaluation_model") as DroneMLModel
			if policy == null:
				policy = _model_for_version(version)
				trial["evaluation_model"] = policy
		if is_instance_valid(drone):
			DroneTrainingRoomPresentation.clear_drone_episode_finished(drone)
			drone.contact_monitor = true
			drone.max_contacts_reported = TRAINING_CONTACTS_REPORTED
			drone.set_ml_episode_unlimited_battery(unlimited_episode_battery)
		var reset_ok = (
			is_instance_valid(drone)
			and drone.reset_ml_episode(spawn_transform, episode_seed, policy)
		)
		if (
			is_evaluation
			and DroneTrainingAlgorithmCatalog.is_training_checkpoint(version)
			and policy == null
		):
			reset_ok = false
		var resolved_target: Dictionary = _resolved_target_for_trial(trial)
		var trial_target_group_id: int = _target_group_id_for_trial(trial)
		var target_objective_position: Vector3 = resolved_target.get(
			"position_world",
			_target_objective_position(trial_target_group_id)
		)
		var target_radius_value: float = maxf(
			float(resolved_target.get(
				"radius_m",
				_target_radius_for_group_id(trial_target_group_id)
			)),
			0.05
		)
		var episode = DroneTrainingEpisode.new()
		episode.start(
			drone_spawn_position,
			target_objective_position,
			target_radius_value,
			episode_duration,
			episode_number,
			episode_seed,
			trial.get("reward_cards", trial.get("reward_components", {})),
			_episode_termination_options_for_trial(trial)
		)
		trial["episode"] = episode
		trial["reward"] = episode.latest_result
		trial["distance"] = drone_spawn_position.distance_to(target_objective_position)
		trial["episode_finished"] = false
		trial["camera_focus_retired_at_usec"] = -1
		trial["action_sample"] = {}
		trial["held_action"] = {}
		trial["interval_reward"] = 0.0
		trial["interval_delta_seconds"] = 0.0
		trial["reward_trace_previous_position_world"] = (
			drone.global_position if is_instance_valid(drone) else drone_spawn_position
		)
		trial["interval_reward_trace"] = _new_interval_reward_trace(trial, episode)
		var initial_probe = DroneTrainingObstacleSensor.clear_probe()
		initial_probe["ground_clearance_m"] = spawn_transform.origin.y
		trial["obstacle_probe"] = initial_probe
		# Match wall sensing to fast policies instead of feeding repeated 20 Hz geometry into a
		# 60 Hz controller. Phase staggering still prevents every worker querying on one tick.
		var sensor_interval = _obstacle_sensor_interval_for_trial(trial)
		trial["obstacle_sensor_interval"] = sensor_interval
		trial["obstacle_sensor_elapsed"] = fmod(
			float(int(trial.get("sensor_phase_index", 0)) * 37)
			* sensor_interval / 97.0,
			sensor_interval
		)
		trial["turret_threat_sensor_elapsed"] = trial["obstacle_sensor_elapsed"]
		if reset_ok:
			_register_trial_combatant(trial)
			var threat_probe = _turret_threat_for_trial(trial)
			trial["turret_threat_probe"] = threat_probe
			_apply_target_objective(
				drone,
				trial["obstacle_probe"],
				threat_probe,
				int(trial.get("group_id", -1)) if not is_evaluation else -1,
				_trial_episode_progress(trial)
			)
			if is_evaluation:
				var preview_observation: Dictionary = drone.get_ml_snapshot_for_model(policy)
				var preview_action = policy.predict_action(preview_observation)
				var preview_validation = DroneMLAction.validate(
					preview_action,
					drone.propeller_slots
				)
				if not bool(preview_validation.get("valid", false)):
					reset_ok = false
					trial["evaluation_error"] = str(preview_validation.get(
						"error",
						"the model produced no valid motor command"
					))
				elif policy != null:
					# SAC validation inference updates navigation memory. The preview checks shape only;
					# it must not count as an artificial visit before the evaluator's first real action.
					policy.reset_episode_state(episode_seed)
		if not reset_ok:
			episode.finish("reset_failed", true)
			trial["reward"] = episode.latest_result
			_complete_trial_episode(trial)
			if is_evaluation:
				var evaluator_error = str(trial.get("evaluation_error", ""))
				if evaluator_error.is_empty():
					evaluator_error = model_registry.last_error
				if evaluator_error.is_empty():
					evaluator_error = "the drone could not reset, activate or load this policy"
				start_errors.append("%s: %s" % [
					model_registry.display_name(version),
					evaluator_error,
				])
	if camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE:
		_select_attached_camera_host(true)
	for group in worker_groups:
		if bool(group.get("active", false)):
			group["control_elapsed"] = 0.0
			_sample_new_group_actions(group)
	status_label.text = (
		message
		if start_errors.is_empty()
		else "Evaluator could not start — %s" % "; ".join(
			PackedStringArray(start_errors)
		)
	)
	_apply_selection_highlight()
	_refresh_interface()


func _model_for_version(version: Dictionary) -> DroneMLModel:
	if DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
		var checkpoint = model_registry.load_training_checkpoint(version)
		if checkpoint.is_empty():
			return null
		var inspection = DroneTrainingAlgorithmCatalog.inspect_checkpoint(checkpoint)
		if not bool(inspection.get("compatible", false)):
			model_registry.last_error = str(inspection.get(
				"compatibility_text",
				"The model is incompatible with this build."
			))
			return null
		var runtime_model = DroneTrainingAlgorithmCatalog.create_runtime_model(
			checkpoint
		)
		if runtime_model == null:
			model_registry.last_error = "The checkpoint passed metadata checks but its runtime model could not load the stored weights."
		return runtime_model
	return DroneTrainingPolicy.new(version.get("weights", {}))


func _obstacle_sensor_interval_for_trial(trial: Dictionary) -> float:
	var control_interval = OBSTACLE_SENSOR_INTERVAL_SECONDS
	var group_id = int(trial.get("group_id", -1))
	if group_id >= 0:
		var group = _group_by_id(group_id)
		if not group.is_empty():
			var trainer = group.get("trainer") as DroneTrainingAlgorithm
			if trainer != null:
				control_interval = float(trainer.config_values().get(
					"control_interval_seconds",
					control_interval
				))
	else:
		var model = trial.get("evaluation_model") as DroneMLModel
		if model != null:
			control_interval = model.get_control_interval_seconds()
	return clampf(
		minf(OBSTACLE_SENSOR_INTERVAL_SECONDS, control_interval),
		0.01,
		OBSTACLE_SENSOR_INTERVAL_SECONDS
	)


func _sync_candidate_evaluation_jobs() -> void:
	# Fixed-seed verification is body-agnostic at the scheduler level. Drone, limb, and turret
	# candidates share one fair hidden-evaluator slot so verification cannot multiply physics cost.
	# A paused training group keeps its queue ticket and continues verification.
	var pending_entries: Array[Dictionary] = []
	for group: Dictionary in _candidate_evaluation_groups():
		var group_id: int = int(group.get("group_id", -1))
		var candidate_id: int = _pending_candidate_id_for_group(group)
		var existing: Node = candidate_evaluations_by_group_id.get(group_id) as Node
		if candidate_id < 0:
			group["candidate_evaluation_queue_position"] = 0
			group["candidate_evaluation_queued_candidate_id"] = -1
			group["candidate_evaluation_queue_ticket"] = 0
			if existing != null:
				_cancel_candidate_evaluation(group_id)
			continue
		if existing != null:
			if int(existing.get("candidate_id")) == candidate_id:
				group["candidate_evaluation_queue_position"] = 0
				continue
			_cancel_candidate_evaluation(group_id)
		if int(group.get("candidate_evaluation_queued_candidate_id", -1)) != candidate_id:
			candidate_evaluation_queue_sequence += 1
			group["candidate_evaluation_queued_candidate_id"] = candidate_id
			group["candidate_evaluation_queue_ticket"] = candidate_evaluation_queue_sequence
		pending_entries.append({
			"group_id": group_id,
			"ticket": int(group.get("candidate_evaluation_queue_ticket", 0)),
		})

	# Preserve first-seen order. A fast-running group cannot repeatedly jump in front of a paused
	# limb/turret group by nominating a new candidate as soon as its previous one finishes.
	for index in range(1, pending_entries.size()):
		var entry: Dictionary = pending_entries[index]
		var previous_index: int = index - 1
		while (
			previous_index >= 0
			and int(pending_entries[previous_index].get("ticket", 0))
				> int(entry.get("ticket", 0))
		):
			pending_entries[previous_index + 1] = pending_entries[previous_index]
			previous_index -= 1
		pending_entries[previous_index + 1] = entry

	var active_count: int = candidate_evaluations_by_group_id.size()
	var queue_position: int = 0
	for entry: Dictionary in pending_entries:
		var queued_group_id: int = int(entry.get("group_id", -1))
		var queued_group: Dictionary = _candidate_group_by_id(queued_group_id)
		if queued_group.is_empty():
			continue
		if active_count < CANDIDATE_EVALUATION_MAX_CONCURRENT:
			if _start_candidate_evaluation(queued_group):
				active_count += 1
				queued_group["candidate_evaluation_queue_position"] = 0
				continue
		queue_position += 1
		queued_group["candidate_evaluation_queue_position"] = queue_position


func _candidate_evaluation_groups() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: Dictionary in worker_groups:
		result.append(group)
	for group: Dictionary in limb_training.groups:
		result.append(group)
	for group: Dictionary in turret_training.groups:
		result.append(group)
	return result


func _candidate_group_by_id(group_id: int) -> Dictionary:
	var group: Dictionary = _group_by_id(group_id)
	if not group.is_empty():
		return group
	group = limb_training.group_by_id(group_id)
	if not group.is_empty():
		return group
	return turret_training.group_by_id(group_id)


func _candidate_group_body_kind(group: Dictionary) -> String:
	if group.is_empty():
		return ""
	var body_type: String = str(group.get("body_type", ""))
	if body_type == "four_limb" or body_type == "turret":
		return body_type
	return "drone"


func _pending_candidate_id_for_group(group: Dictionary) -> int:
	if group.is_empty():
		return -1
	var trainer: Variant = group.get("trainer")
	if trainer == null:
		return -1
	if trainer.has_method("pending_evaluation_candidate_id"):
		return int(trainer.call("pending_evaluation_candidate_id"))
	if trainer.has_method("pending_evaluation_candidate"):
		var pending: Dictionary = trainer.call("pending_evaluation_candidate")
		return int(pending.get("candidate_id", -1))
	return -1


func _pending_candidate_for_group(group: Dictionary) -> Dictionary:
	var trainer: Variant = group.get("trainer") if not group.is_empty() else null
	if trainer == null or not trainer.has_method("pending_evaluation_candidate"):
		return {}
	return trainer.call("pending_evaluation_candidate") as Dictionary


func _candidate_checkpoint_for_group(group: Dictionary) -> Dictionary:
	if group.is_empty():
		return {}
	var group_id: int = int(group.get("group_id", -1))
	match _candidate_group_body_kind(group):
		"drone":
			var trainer = group.get("trainer") as DroneTrainingAlgorithm
			return trainer.candidate_checkpoint() if trainer != null else {}
		"four_limb":
			return limb_training.evaluation_candidate_checkpoint(group_id)
		"turret":
			return turret_training.evaluation_candidate_checkpoint(group_id)
	return {}


func _best_checkpoint_for_group(group: Dictionary) -> Dictionary:
	if group.is_empty():
		return {}
	var group_id: int = int(group.get("group_id", -1))
	match _candidate_group_body_kind(group):
		"drone":
			var trainer = group.get("trainer") as DroneTrainingAlgorithm
			return trainer.to_best_checkpoint() if trainer != null else {}
		"four_limb":
			return limb_training.save_checkpoint(group_id, true)
		"turret":
			return turret_training.save_checkpoint(group_id, true)
	return {}


func _start_candidate_evaluation(group: Dictionary) -> bool:
	if group.is_empty():
		return false
	var group_id: int = int(group.get("group_id", -1))
	var trainer: Variant = group.get("trainer")
	if trainer == null:
		return false
	var pending_candidate: Dictionary = _pending_candidate_for_group(group)
	if pending_candidate.is_empty():
		return false
	var candidate_id: int = RLTrainingMath.finite_int_or(pending_candidate.get("candidate_id", -1), -1)
	var evaluation_subject: String = "candidate"
	var subject_candidate: Dictionary = pending_candidate
	var checkpoint: Dictionary = _candidate_checkpoint_for_group(group)
	var candidate_contract_hash: String = str(pending_candidate.get("evaluation_contract_hash", ""))
	var candidate_plan: Dictionary = pending_candidate.get("evaluation_plan", {})
	var candidate_suite_hash: String = str(candidate_plan.get("suite_hash", ""))
	var best_evaluation: Dictionary = (
		trainer.call("best_evaluation_summary") as Dictionary
		if trainer.has_method("best_evaluation_summary")
		else {}
	)
	var has_best: bool = bool(trainer.call("has_best_checkpoint")) if trainer.has_method("has_best_checkpoint") else false
	if (
		has_best
		and (
			best_evaluation.is_empty()
			or str(best_evaluation.get("evaluation_contract_hash", "")) != candidate_contract_hash
			or str(best_evaluation.get("suite_hash", "")) != candidate_suite_hash
		)
	):
		# Best and Candidate are comparable only under the exact same frozen task/hardware/world
		# contract *and* deterministic benchmark suite. Measure the preserved Best first whenever
		# either provenance hash changed.
		checkpoint = _best_checkpoint_for_group(group)
		var best_network: Dictionary = checkpoint.get("network", {})
		if checkpoint.is_empty() or best_network.is_empty():
			_candidate_evaluation_start_failed(
				group,
				candidate_id,
				"the preserved Best policy could not be loaded for contract re-evaluation"
			)
			return false
		evaluation_subject = "best_baseline"
		subject_candidate = pending_candidate.duplicate(true)
		subject_candidate["candidate_hash"] = RLDeterministicEvaluator.candidate_hash(best_network)
		subject_candidate["evaluation_status"] = "re_evaluating_best_for_candidate_contract"
	if checkpoint.is_empty():
		_candidate_evaluation_start_failed(group, candidate_id, "candidate checkpoint is missing")
		return false

	var job: Node = null
	var configured: bool = false
	match _candidate_group_body_kind(group):
		"drone":
			# The candidate owns a frozen body snapshot. Pausing a group, editing its live hardware, or
			# simply retaining paused worker instances must not redefine or invalidate that evaluator.
			var loadout: DroneLoadout = _candidate_drone_loadout(group, subject_candidate)
			if loadout == null:
				_candidate_evaluation_start_failed(
					group,
					candidate_id,
					"candidate frozen drone hardware is unavailable"
				)
				return false
			job = CANDIDATE_EVALUATION_JOB_SCRIPT.new() as Node
			var reward_deck: DroneTrainingRewardDeck = _ensure_drone_reward_deck(group)
			configured = bool(job.call(
				"configure",
				group_id,
				subject_candidate,
				checkpoint,
				loadout,
				_target_handler_configuration_for_group(group_id),
				reward_deck.configuration_dictionary(),
				drone_spawn_position,
				ARENA_SIZE,
				CANDIDATE_EVALUATION_COLLISION_LAYER,
				ARENA_COLLISION_LAYER,
				unlimited_episode_battery,
				candidate_evaluation_environment_revision
			))
		"four_limb":
			job = FOUR_LIMB_CANDIDATE_EVALUATION_JOB_SCRIPT.new() as Node
			configured = bool(job.call(
				"configure",
				group_id,
				subject_candidate,
				checkpoint,
				limb_training.group_body_definition(group_id),
				candidate_evaluation_environment_revision
			))
		"turret":
			job = TURRET_CANDIDATE_EVALUATION_JOB_SCRIPT.new() as Node
			configured = bool(job.call(
				"configure",
				group_id,
				subject_candidate,
				checkpoint,
				turret_training.group_loadout(group_id),
				candidate_evaluation_environment_revision
			))
		_:
			_candidate_evaluation_start_failed(group, candidate_id, "unsupported evaluator body type")
			return false
	if job == null:
		_candidate_evaluation_start_failed(group, candidate_id, "candidate evaluation job could not be created")
		return false
	if not configured:
		_candidate_evaluation_start_failed(group, candidate_id, str(job.get("last_error")))
		job.queue_free()
		return false
	job.connect("completed", Callable(self, "_on_candidate_evaluation_completed"))
	job.connect("failed", Callable(self, "_on_candidate_evaluation_failed"))
	add_child(job)
	candidate_evaluations_by_group_id[group_id] = job
	group["candidate_evaluation_subject"] = evaluation_subject
	if not bool(job.call("begin")):
		# begin() should emit a detailed failure. Keep this fallback for an implementation that
		# returns false before it emits.
		if candidate_evaluations_by_group_id.has(group_id):
			_on_candidate_evaluation_failed(group_id, candidate_id, str(job.get("last_error")))
		return false
	group["candidate_evaluation_started_usec"] = Time.get_ticks_usec()
	group["candidate_evaluation_queue_position"] = 0
	_refresh_group_card_texts()
	if turret_ui != null:
		turret_ui.refresh_group_cards()
	return true


func _tick_candidate_evaluations(delta: float) -> void:
	if candidate_evaluations_by_group_id.is_empty():
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var jobs: Array = candidate_evaluations_by_group_id.values()
	for job_value: Variant in jobs:
		var job: Node = job_value as Node
		if job == null or not is_instance_valid(job):
			continue
		if int(job.get("environment_revision")) != candidate_evaluation_environment_revision:
			job.call("restart_for_environment", candidate_evaluation_environment_revision)
		job.call("tick", delta, space_state, wall_spatial_hash)


func _cancel_candidate_evaluation(group_id: int) -> void:
	var job: Node = candidate_evaluations_by_group_id.get(group_id) as Node
	candidate_evaluations_by_group_id.erase(group_id)
	if job != null and is_instance_valid(job):
		job.call("shutdown")
		job.queue_free()
	var group: Dictionary = _candidate_group_by_id(group_id)
	if not group.is_empty():
		group["candidate_evaluation_queue_position"] = 0
		group["candidate_evaluation_subject"] = ""


func _cancel_all_candidate_evaluations() -> void:
	var group_ids: Array = candidate_evaluations_by_group_id.keys()
	for group_id_value: Variant in group_ids:
		_cancel_candidate_evaluation(int(group_id_value))


func _on_candidate_evaluation_completed(
	group_id: int,
	candidate_id: int,
	records: Array[Dictionary]
) -> void:
	var group: Dictionary = _candidate_group_by_id(group_id)
	if group.is_empty():
		_cancel_candidate_evaluation(group_id)
		return
	var trainer: Variant = group.get("trainer")
	if trainer == null:
		_cancel_candidate_evaluation(group_id)
		return
	var job: Node = candidate_evaluations_by_group_id.get(group_id) as Node
	var subject: String = str(group.get("candidate_evaluation_subject", "candidate"))
	if subject == "best_baseline":
		var baseline_result: Dictionary = (
			trainer.call("record_best_deterministic_evaluation_records", job.get("plan"), records) as Dictionary
			if job != null and is_instance_valid(job) and trainer.has_method("record_best_deterministic_evaluation_records")
			else {"recorded": false, "reason": "missing_best_evaluation_job"}
		)
		var recorded: bool = bool(baseline_result.get("recorded", false))
		var reason: String = str(baseline_result.get("reason", "unknown"))
		_cancel_candidate_evaluation(group_id)
		if recorded:
			# Keep the frozen candidate and queue ticket. The next scheduler pass evaluates the
			# Candidate under the identical contract that just measured Best.
			group["candidate_evaluation_last_result"] = {
				"candidate_id": candidate_id,
				"promoted": false,
				"evaluation_error": false,
				"reason": "best_baseline_ready",
				"record_count": records.size(),
				"until_usec": Time.get_ticks_usec()
					+ int(CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS * 1000000.0),
			}
			status_label.text = "Best baseline verified for group %d; candidate evaluation follows." % group_id
		else:
			_discard_pending_candidate_for_group(group, candidate_id)
			group["candidate_evaluation_last_result"] = {
				"candidate_id": candidate_id,
				"promoted": false,
				"evaluation_error": true,
				"reason": "best_baseline_error: %s" % reason,
				"record_count": records.size(),
				"until_usec": Time.get_ticks_usec()
					+ int(CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS * 1000000.0),
			}
			status_label.text = "Best baseline evaluation failed for group %d: %s" % [group_id, reason]
		_refresh_candidate_evaluation_ui()
		return

	var result: Dictionary = (
		trainer.call("record_deterministic_evaluation_records", candidate_id, records) as Dictionary
		if trainer.has_method("record_deterministic_evaluation_records")
		else {"promoted": false, "reason": "trainer_has_no_evaluation_consumer"}
	)
	var result_reason: String = str(result.get("reason", "unknown"))
	var pending_after_result_id: int = _pending_candidate_id_for_group(group)
	var evaluation_error: bool = false
	if pending_after_result_id == candidate_id:
		# A complete suite must consume its candidate. Validation failures are terminal for this
		# frozen candidate so a malformed evaluator cannot loop forever.
		evaluation_error = true
		_discard_pending_candidate_for_group(group, candidate_id)
		result_reason = "evaluation_error: %s" % result_reason
	group["candidate_evaluation_last_result"] = {
		"candidate_id": candidate_id,
		"promoted": bool(result.get("promoted", false)),
		"evaluation_error": evaluation_error,
		"reason": result_reason,
		"record_count": records.size(),
		"until_usec": Time.get_ticks_usec()
			+ int(CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS * 1000000.0),
	}
	_cancel_candidate_evaluation(group_id)
	if evaluation_error:
		status_label.text = "Fixed-seed evaluator produced invalid records for group %d: %s" % [
			group_id,
			result_reason,
		]
	elif bool(result.get("promoted", false)):
		status_label.text = "Fixed-seed evaluation promoted a new Best for group %d." % group_id
		if _candidate_group_body_kind(group) == "drone":
			_mark_group_auto_save_pending(group)
			call_deferred("_flush_candidate_evaluation_auto_save", group_id)
	_refresh_candidate_evaluation_ui()


func _on_candidate_evaluation_failed(
	group_id: int,
	candidate_id: int,
	reason: String
) -> void:
	var group: Dictionary = _candidate_group_by_id(group_id)
	var subject: String = str(group.get("candidate_evaluation_subject", "candidate")) if not group.is_empty() else "candidate"
	if not group.is_empty():
		_discard_pending_candidate_for_group(group, candidate_id)
		group["candidate_evaluation_last_result"] = {
			"candidate_id": candidate_id,
			"promoted": false,
			"evaluation_error": true,
			"reason": "evaluation_error: %s" % reason,
			"record_count": 0,
			"until_usec": Time.get_ticks_usec()
				+ int(CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS * 1000000.0),
		}
	_cancel_candidate_evaluation(group_id)
	status_label.text = "%s stopped for group %d: %s" % [
		"Best baseline evaluator" if subject == "best_baseline" else "Fixed-seed evaluator",
		group_id,
		reason,
	]
	_refresh_candidate_evaluation_ui()


func _candidate_evaluation_start_failed(
	group: Dictionary,
	candidate_id: int,
	reason: String
) -> void:
	_discard_pending_candidate_for_group(group, candidate_id)
	group["candidate_evaluation_last_result"] = {
		"candidate_id": candidate_id,
		"promoted": false,
		"evaluation_error": true,
		"reason": "evaluation_error: %s" % reason,
		"record_count": 0,
		"until_usec": Time.get_ticks_usec()
			+ int(CANDIDATE_EVALUATION_RESULT_FLASH_SECONDS * 1000000.0),
	}
	status_label.text = "Fixed-seed evaluator could not start for %s: %s" % [
		str(group.get("name", "worker group")),
		reason,
	]


func _discard_pending_candidate_for_group(group: Dictionary, candidate_id: int) -> bool:
	var trainer: Variant = group.get("trainer") if not group.is_empty() else null
	return (
		bool(trainer.call("discard_pending_evaluation_candidate", candidate_id))
		if trainer != null and trainer.has_method("discard_pending_evaluation_candidate")
		else false
	)


func _refresh_candidate_evaluation_ui() -> void:
	_refresh_group_card_texts()
	if turret_ui != null:
		turret_ui.refresh_group_cards()


func _flush_candidate_evaluation_auto_save(group_id: int) -> void:
	var group: Dictionary = _group_by_id(group_id)
	if group.is_empty():
		return
	_flush_group_pending_auto_save(group, true)
	_refresh_group_card_texts()


func _candidate_evaluation_progress(group_id: int) -> Dictionary:
	var job: Node = candidate_evaluations_by_group_id.get(group_id) as Node
	return (
		job.call("progress") as Dictionary
		if job != null and is_instance_valid(job) and job.has_method("progress")
		else {}
	)


func candidate_evaluation_compact_text(group: Dictionary) -> String:
	return _candidate_evaluation_compact_text(group)


func candidate_evaluation_tooltip(group: Dictionary) -> String:
	return _candidate_evaluation_tooltip(group)


func _candidate_evaluation_tooltip(group: Dictionary) -> String:
	var group_id: int = int(group.get("group_id", -1))
	var candidate_id: int = _pending_candidate_id_for_group(group)
	var progress: Dictionary = _candidate_evaluation_progress(group_id)
	if not progress.is_empty():
		var subject: String = str(group.get("candidate_evaluation_subject", "candidate"))
		return "%s %d is running deterministic fixed-seed verification: case %d/%d, %s, %.1f/%.1fs. Pausing training does not pause verification. The . .. ... activity animation remains reserved for rollout collection." % [
			"Preserved Best baseline for candidate" if subject == "best_baseline" else "Frozen candidate",
			candidate_id,
			int(progress.get("current_case_number", 0)),
			int(progress.get("total_cases", 0)),
			_candidate_evaluation_scenario_label(str(progress.get("scenario_id", ""))),
			float(progress.get("case_elapsed_seconds", 0.0)),
			float(progress.get("case_duration_seconds", 0.0)),
		]
	var queue_position: int = int(group.get("candidate_evaluation_queue_position", 0))
	if queue_position > 0:
		return "Frozen candidate %d is waiting in deterministic-evaluation queue position %d. One hidden evaluator is shared across drone, limb, and turret groups to bound simulation cost." % [candidate_id, queue_position]
	return "Frozen candidate %d has been nominated and is waiting for the hidden deterministic evaluator to start." % candidate_id


func _candidate_evaluation_compact_text(group: Dictionary) -> String:
	var group_id: int = int(group.get("group_id", -1))
	var progress: Dictionary = _candidate_evaluation_progress(group_id)
	if not progress.is_empty():
		var prefix: String = (
			"BEST-EVAL"
			if str(group.get("candidate_evaluation_subject", "")) == "best_baseline"
			else "EVAL"
		)
		return "%s %d/%d" % [
			prefix,
			int(progress.get("current_case_number", 0)),
			int(progress.get("total_cases", 0)),
		]
	var queue_position: int = int(group.get("candidate_evaluation_queue_position", 0))
	if queue_position > 0:
		return "EVAL Q#%d" % queue_position
	return "EVAL START"


func _candidate_evaluation_scenario_label(scenario_id: String) -> String:
	return DroneTrainingRoomPresentation.friendly_name(scenario_id).to_upper()


func _update_trials(delta: float, turret_threats_active: bool) -> void:
	var space_state = get_world_3d().direct_space_state
	for trial in trials:
		if bool(trial.get("episode_finished", false)):
			continue
		var drone = trial.get("drone") as ServerDrone
		var episode = trial.get("episode") as DroneTrainingEpisode
		var is_training = int(trial.get("group_id", -1)) >= 0
		if not is_instance_valid(drone) or episode == null:
			trial["episode_finished"] = true
			continue
		if is_training:
			var training_group: Dictionary = _group_by_id(int(trial.get("group_id", -1)))
			if training_group.is_empty() or not bool(training_group.get("active", false)):
				continue
		var resolved_target: Dictionary = _resolved_target_for_trial(trial)
		var trial_target_group_id: int = _target_group_id_for_trial(trial)
		var target_position_world: Vector3 = resolved_target.get(
			"position_world",
			_target_objective_position(trial_target_group_id)
		)
		var target_radius_value: float = maxf(
			float(resolved_target.get(
				"radius_m",
				_target_radius_for_group_id(trial_target_group_id)
			)),
			0.05
		)
		var sensor_elapsed = (
			float(trial.get("obstacle_sensor_elapsed", 0.0)) + delta
		)
		var obstacle_probe: Dictionary
		var sensor_interval = float(trial.get(
			"obstacle_sensor_interval",
			_obstacle_sensor_interval_for_trial(trial)
		))
		if sensor_elapsed >= sensor_interval:
			obstacle_probe = DroneTrainingObstacleSensor.sample(
				drone,
				space_state,
				target_position_world,
				ARENA_COLLISION_LAYER,
				wall_spatial_hash,
				ARENA_SIZE
			)
			sensor_elapsed = fmod(sensor_elapsed, sensor_interval)
		else:
			obstacle_probe = DroneTrainingObstacleSensor.refresh_motion(
				drone,
				trial.get("obstacle_probe", {})
			)
		trial["obstacle_probe"] = obstacle_probe
		trial["obstacle_sensor_elapsed"] = sensor_elapsed
		var threat_probe: Dictionary = trial.get("turret_threat_probe", {})
		if threat_probe.is_empty():
			threat_probe = TrainingTurretThreatSensor.empty_probe()
		var threat_sensor_elapsed = float(trial.get(
			"turret_threat_sensor_elapsed",
			0.0
		)) + delta
		if turret_threats_active:
			if threat_sensor_elapsed >= sensor_interval:
				threat_probe = _turret_threat_for_trial(trial)
				threat_sensor_elapsed = fmod(threat_sensor_elapsed, sensor_interval)
		elif bool(threat_probe.get("present", false)):
			# Allocate a replacement only on the one frame where the last turret disappears.
			threat_probe = TrainingTurretThreatSensor.empty_probe()
			threat_sensor_elapsed = 0.0
		trial["turret_threat_probe"] = threat_probe
		trial["turret_threat_sensor_elapsed"] = threat_sensor_elapsed
		var combat_adapter = trial.get("combat_adapter") as TrainingCombatantAdapter
		var combat_events = (
			combat_adapter.consume_combat_events()
			if combat_adapter != null
			else TrainingCombatantAdapter.EMPTY_COMBAT_EVENTS
		)
		if not is_training:
			_apply_target_objective(
				drone,
				obstacle_probe,
				threat_probe,
				-1,
				_trial_episode_progress(trial)
			)
		var reward = episode.step(
			drone,
			target_position_world,
			target_radius_value,
			ARENA_SIZE,
			delta,
			obstacle_probe,
			combat_events,
			threat_probe
		)
		trial["reward"] = reward
		trial["distance"] = float(reward.get("distance_m", INF))
		if is_training:
			trial["interval_reward"] = (
				float(trial.get("interval_reward", 0.0))
				+ float(reward.get("step_reward", 0.0))
			)
			if not (trial.get("action_sample", {}) as Dictionary).is_empty():
				trial["interval_delta_seconds"] = (
					float(trial.get("interval_delta_seconds", 0.0))
					+ maxf(delta, 0.0)
				)
				var interval_trace: Dictionary = trial.get("interval_reward_trace", {})
				if str(interval_trace.get("goal_schema", "")) == "stationary_position_v1":
					if _goal_reward_trace_matches_resolved_target(interval_trace, resolved_target):
						_append_interval_reward_trace_frame(
							trial,
							drone.global_position,
							delta,
							reward
						)
					else:
						# A higher-priority task target took over during this control interval.
						# Keep the real SAC transition, but do not feed mixed-goal reward frames to HER.
						trial["interval_reward_trace"] = {}
		if episode.finished:
			_record_group_transition(trial, drone, reward)
			_complete_trial_episode(trial)

	for group in worker_groups:
		if not bool(group["active"]):
			continue
		var trainer: DroneTrainingAlgorithm = group["trainer"]
		group["control_elapsed"] = float(group["control_elapsed"]) + delta
		var control_interval = float(trainer.config_values().get(
			"control_interval_seconds",
			0.05
		))
		if float(group["control_elapsed"]) >= control_interval:
			var prepared_decisions: Array[Dictionary] = []
			for trial in _trials_for_group(int(group["group_id"])):
				if bool(trial.get("episode_finished", false)):
					continue
				var drone = trial.get("drone") as ServerDrone
				if not is_instance_valid(drone):
					continue
				# The value estimate produced for the next action is exactly the bootstrap
				# value required by the previous transition while the behavior policy has
				# not changed. Reusing it removes one complete critic pass per worker and
				# decision. If a pending optimizer result synchronizes below, only that
				# boundary action is resampled under the new behavior policy.
				var decision = _prepare_group_decision(trial, drone, trainer)
				_record_group_transition(
					trial,
					drone,
					trial.get("reward", {}),
					decision
				)
				prepared_decisions.append({
					"trial": trial,
					"drone": drone,
					"decision": decision,
				})
			_begin_group_update_if_ready(group, false)
			_apply_prepared_group_decisions(group, prepared_decisions)
			group["control_elapsed"] = fmod(
				float(group["control_elapsed"]),
				maxf(control_interval, 0.000001)
			)


func _trial_requires_goal_relabel_reward_trace(trial: Dictionary) -> bool:
	if str(trial.get("mode", "evaluation")) != "algorithm_training":
		return false
	var group_id: int = int(trial.get("group_id", -1))
	var group: Dictionary = _group_by_id(group_id)
	if group.is_empty():
		return false
	var path_system: TrainingPathTargetSystem = _target_path_for_group_id(group_id)
	if path_system == null or path_system.behavior != 0:
		return false
	var resolved_target: Dictionary = _resolved_target_for_group_id(group_id)
	if str(resolved_target.get("system_type_id", "")) != str(TrainingPathTargetSystem.TYPE_ID):
		# HER's stationary-position reward replay is valid only while the path target is the
		# actual routed objective. A higher-priority cargo/escape/task target may change without
		# changing the path system's own Stationary setting.
		return false
	var trainer = group.get("trainer") as DroneTrainingAlgorithm
	return trainer != null and trainer.requires_goal_relabel_reward_trace()


func _new_interval_reward_trace(
	trial: Dictionary,
	episode: DroneTrainingEpisode
) -> Dictionary:
	# Elapsed simulated time is accumulated as a scalar directly on the trial. Only SAC with
	# HER enabled needs the richer path metadata required to recompute goal rewards.
	if not _trial_requires_goal_relabel_reward_trace(trial):
		return {}
	var component_configuration: Dictionary = {}
	if episode != null and episode.reward_tracker != null:
		component_configuration = episode.reward_tracker.component_configuration()
	elif trial.get("reward_cards", {}) is Dictionary:
		component_configuration = trial.get("reward_cards", {}) as Dictionary
	var resolved_target: Dictionary = _resolved_target_for_trial(trial)
	var trial_target_group_id: int = _target_group_id_for_trial(trial)
	return {
		"schema_version": 1,
		"goal_schema": "stationary_position_v1",
		"reward_components": component_configuration,
		"target_position_world": resolved_target.get(
			"position_world",
			_target_objective_position(trial_target_group_id)
		),
		"target_radius_m": maxf(float(resolved_target.get("radius_m", 0.75)), 0.05),
		# Compact parallel buffers replace one nested Dictionary allocation per physics frame.
		"frame_previous_positions": PackedVector3Array(),
		"frame_next_positions": PackedVector3Array(),
		"frame_delta_seconds": PackedFloat64Array(),
		"frame_reward_components": PackedFloat64Array(),
		"terminal_adjustments": {
			"failure_penalty": 0.0,
			"timeout_survival_bonus": 0.0,
			"progress_correction": 0.0,
		},
		"algorithm_shaping": {
			"exploration_bonus": 0.0,
			"blocked_detour_relief": 0.0,
		},
		"original_total": 0.0,
		"delta_seconds": 0.0,
	}


func _goal_reward_trace_matches_resolved_target(
	trace: Dictionary,
	resolved_target: Dictionary
) -> bool:
	if str(resolved_target.get("system_type_id", "")) != str(TrainingPathTargetSystem.TYPE_ID):
		return false
	var trace_position_value: Variant = trace.get("target_position_world")
	var resolved_position_value: Variant = resolved_target.get("position_world")
	if not (trace_position_value is Vector3) or not (resolved_position_value is Vector3):
		return false
	var trace_position: Vector3 = trace_position_value
	var resolved_position: Vector3 = resolved_position_value
	if not trace_position.is_equal_approx(resolved_position):
		return false
	return is_equal_approx(
		maxf(float(trace.get("target_radius_m", 0.75)), 0.05),
		maxf(float(resolved_target.get("radius_m", 0.75)), 0.05)
	)


func _append_interval_reward_trace_frame(
	trial: Dictionary,
	next_position_world: Vector3,
	delta_seconds: float,
	reward: Dictionary
) -> void:
	var trace: Dictionary = trial.get("interval_reward_trace", {})
	if str(trace.get("goal_schema", "")) != "stationary_position_v1":
		return
	var safe_delta = maxf(delta_seconds, 0.0)
	var previous_position_world: Vector3 = trial.get(
		"reward_trace_previous_position_world",
		next_position_world
	)
	var previous_positions: PackedVector3Array = trace.get(
		"frame_previous_positions",
		PackedVector3Array()
	)
	var next_positions: PackedVector3Array = trace.get(
		"frame_next_positions",
		PackedVector3Array()
	)
	var frame_deltas: PackedFloat64Array = trace.get(
		"frame_delta_seconds",
		PackedFloat64Array()
	)
	var frame_components: PackedFloat64Array = trace.get(
		"frame_reward_components",
		PackedFloat64Array()
	)
	previous_positions.append(previous_position_world)
	next_positions.append(next_position_world)
	frame_deltas.append(safe_delta)
	# Stable six-value layout: survival, ground, smoothness, action-abuse, obstacle, turret.
	frame_components.append(float(reward.get("survival_reward", 0.0)))
	frame_components.append(float(reward.get("ground_safety_reward", 0.0)))
	frame_components.append(float(reward.get("smoothness_reward", 0.0)))
	frame_components.append(float(reward.get("action_abuse_reward", 0.0)))
	frame_components.append(float(reward.get("obstacle_reward", 0.0)))
	frame_components.append(float(reward.get("turret_safety_reward", 0.0)))
	trace["frame_previous_positions"] = previous_positions
	trace["frame_next_positions"] = next_positions
	trace["frame_delta_seconds"] = frame_deltas
	trace["frame_reward_components"] = frame_components
	trial["interval_reward_trace"] = trace
	trial["reward_trace_previous_position_world"] = next_position_world


func _finalize_interval_reward_trace(
	trial: Dictionary,
	reward: Dictionary
) -> Dictionary:
	# Hand off the current trace instead of recursively cloning it. The caller replaces the
	# trial's accumulator immediately after add_transition(), so ownership is unambiguous.
	var trace: Dictionary = trial.get("interval_reward_trace", {})
	if trace.is_empty():
		return {
			"delta_seconds": float(trial.get("interval_delta_seconds", 0.0)),
		}
	if str(trace.get("goal_schema", "")) != "stationary_position_v1":
		trace["delta_seconds"] = float(trial.get("interval_delta_seconds", 0.0))
		return trace
	trace["delta_seconds"] = float(trial.get("interval_delta_seconds", 0.0))
	trace["terminal_adjustments"] = {
		"failure_penalty": float(reward.get("failure_penalty", 0.0)),
		"timeout_survival_bonus": float(reward.get("timeout_survival_bonus", 0.0)),
		"progress_correction": float(reward.get("unreached_target_progress_correction", 0.0)),
	}
	trace["original_total"] = float(trial.get("interval_reward", 0.0))
	trace["source_terminated"] = bool(reward.get("terminated", false))
	trace["source_truncated"] = bool(reward.get("truncated", false))
	return trace


func _record_group_transition(
	trial: Dictionary,
	drone: ServerDrone,
	reward: Dictionary,
	prepared_decision: Dictionary = {}
) -> Dictionary:
	if (
		str(trial.get("mode", "evaluation")) != "algorithm_training"
		or trial.get("action_sample", {}).is_empty()
		or not is_instance_valid(drone)
	):
		return {}
	var group = _group_by_id(int(trial.get("group_id", -1)))
	if group.is_empty():
		return {}
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var terminated: bool = bool(reward.get("terminated", false))
	var decision_state = prepared_decision
	# A true terminal transition has zero bootstrap by definition. Do not touch the dead body's
	# successor sensors just to manufacture data the trainer must ignore. Truncations remain
	# bootstrap-eligible, so they still require a genuine encoded successor below.
	if decision_state.is_empty() and not terminated:
		decision_state = _encode_group_decision_state(
			trial,
			drone,
			trainer
		)
	var observation: Dictionary = decision_state.get("observation", {})
	var actor_input: PackedFloat64Array = decision_state.get(
		"actor_input",
		PackedFloat64Array()
	)
	var critic_input: PackedFloat64Array = decision_state.get(
		"critic_input",
		PackedFloat64Array()
	)
	var next_value_override = NAN
	var next_sample: Dictionary = decision_state.get("sample", {})
	if not next_sample.is_empty():
		next_value_override = float(next_sample.get("value", NAN))
	# SAC already freezes the observation attached to the next action because the live
	# obstacle/objective dictionaries continue changing between sensor samples. Reuse that
	# snapshot as the transition successor instead of deep-copying the same state twice.
	var transition_next_observation: Dictionary = observation
	if not terminated:
		var frozen_next_value: Variant = next_sample.get("observation", {})
		if frozen_next_value is Dictionary and not (frozen_next_value as Dictionary).is_empty():
			transition_next_observation = frozen_next_value as Dictionary
	var added = trainer.add_transition(
		int(trial.get("instance_id", -1)),
		trial.get("action_sample", {}),
		float(trial.get("interval_reward", 0.0)),
		transition_next_observation,
		terminated,
		bool(reward.get("truncated", false)),
		critic_input,
		next_value_override,
		_finalize_interval_reward_trace(trial, reward)
	)
	if not added:
		status_label.text = "%s transition rejected: %s" % [
			group["name"], trainer.last_error_text(),
		]
	trial["action_sample"] = {}
	trial["held_action"] = {}
	trial["interval_reward"] = 0.0
	trial["interval_delta_seconds"] = 0.0
	trial["interval_reward_trace"] = _new_interval_reward_trace(
		trial,
		trial.get("episode") as DroneTrainingEpisode
	)
	trial["reward_trace_previous_position_world"] = drone.global_position
	return {
		"observation": observation,
		"actor_input": actor_input,
		"critic_input": critic_input,
	}


func _encode_group_decision_state(
	trial: Dictionary,
	drone: ServerDrone,
	trainer: DroneTrainingAlgorithm
) -> Dictionary:
	_apply_target_objective(
		drone,
		trial.get("obstacle_probe", {}),
		trial.get("turret_threat_probe", {}),
		int(trial.get("group_id", -1)),
		_trial_episode_progress(trial)
	)
	return trainer.encode_observation(
		drone.get_ppo_snapshot(),
		int(trial.get("instance_id", -1))
	)


func _prepare_group_decision(
	trial: Dictionary,
	drone: ServerDrone,
	trainer: DroneTrainingAlgorithm
) -> Dictionary:
	var decision = _encode_group_decision_state(trial, drone, trainer)
	var observation: Dictionary = decision.get("observation", {})
	var actor_input: PackedFloat64Array = decision.get(
		"actor_input",
		PackedFloat64Array()
	)
	var critic_input: PackedFloat64Array = decision.get(
		"critic_input",
		PackedFloat64Array()
	)
	decision["policy_revision"] = trainer.behavior_policy_revision()
	decision["sample"] = trainer.sample_action_from_inputs(
		observation,
		actor_input,
		critic_input,
		int(trial.get("instance_id", -1))
	)
	return decision


func _apply_prepared_group_decisions(
	group: Dictionary,
	prepared_decisions: Array[Dictionary]
) -> void:
	if group.is_empty() or not bool(group.get("active", false)):
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var current_policy_revision = trainer.behavior_policy_revision()
	for prepared in prepared_decisions:
		var trial: Dictionary = prepared.get("trial", {})
		var drone = prepared.get("drone") as ServerDrone
		var decision: Dictionary = prepared.get("decision", {})
		if trial.is_empty() or not is_instance_valid(drone):
			continue
		var sample: Dictionary = decision.get("sample", {})
		if int(decision.get("policy_revision", -1)) != current_policy_revision:
			# A completed background update became the behavior policy after the old
			# transition was closed. The encoded state is still current, but its action
			# must come from the newly synchronized policy.
			sample = trainer.sample_action_from_inputs(
				decision.get("observation", {}),
				decision.get("actor_input", PackedFloat64Array()),
				decision.get("critic_input", PackedFloat64Array()),
				int(trial.get("instance_id", -1))
			)
		_apply_group_action_sample(group, trial, drone, sample)


func _apply_group_action_sample(
	group: Dictionary,
	trial: Dictionary,
	drone: ServerDrone,
	sample: Dictionary
) -> void:
	if sample.is_empty():
		status_label.text = "%s could not sample a valid body action." % group["name"]
		action_trace_buffer.mark_invalid(
			int(group.get("group_id", -1)),
			int(trial.get("instance_id", -1)),
			int(trial.get("worker_index", trial.get("sensor_phase_index", -1)))
		)
		drone.submit_ml_action({})
		return
	var held_action: Dictionary = sample.get("action", {})
	if not drone.submit_ml_action(held_action):
		# Never graph an action that the physical runtime rejected. Previously this trace was written
		# first, which could make a dead actuator path look healthy in the plots.
		action_trace_buffer.mark_invalid(
			int(group.get("group_id", -1)),
			int(trial.get("instance_id", -1)),
			int(trial.get("worker_index", trial.get("sensor_phase_index", -1)))
		)
		trial["held_action"] = {}
		status_label.text = "%s runtime rejected its body action: %s" % [
			group["name"],
			drone.ml_controller.latest_action_error if drone.ml_controller != null else "unknown action error",
		]
		return
	_record_action_trace_sample(group, trial, drone, sample)
	trial["action_sample"] = sample
	trial["held_action"] = held_action
	trial["interval_reward"] = 0.0
	trial["interval_delta_seconds"] = 0.0
	trial["interval_reward_trace"] = _new_interval_reward_trace(
		trial,
		trial.get("episode") as DroneTrainingEpisode
	)
	trial["reward_trace_previous_position_world"] = drone.global_position


func _sample_new_group_actions(group: Dictionary) -> void:
	if group.is_empty() or not bool(group.get("active", false)):
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	for trial in _trials_for_group(int(group["group_id"])):
		if bool(trial.get("episode_finished", false)):
			continue
		var drone = trial.get("drone") as ServerDrone
		if not is_instance_valid(drone):
			continue
		var decision = _prepare_group_decision(trial, drone, trainer)
		_apply_group_action_sample(
			group,
			trial,
			drone,
			decision.get("sample", {})
		)


func _begin_group_update_if_ready(group: Dictionary, force_partial: bool) -> void:
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if trainer.can_update(force_partial):
		# Leave two logical CPUs available for physics, rendering, audio, and the operating
		# system. PPO workers may keep flying while their detached rollout is optimized, but
		# the trainer deliberately discards transitions generated in that window so stale
		# behavior data cannot become a second interleaved on-policy lineage.
		if _background_optimizer_count() >= background_optimizer_limit:
			return
		if not trainer.begin_background_update(force_partial):
			status_label.text = "%s optimizer could not start: %s" % [
				group["name"],
				trainer.last_error_text(),
			]
		else:
			_mark_group_auto_save_pending(group)


func _poll_optimizer_jobs() -> void:
	for group in worker_groups:
		var trainer: DroneTrainingAlgorithm = group["trainer"]
		var metrics = trainer.poll_background_update()
		if metrics.has("error"):
			status_label.text = "%s optimizer stopped: %s" % [
				group["name"],
				str(metrics["error"]),
			]
		elif not metrics.is_empty():
			(group["history"] as DroneTrainingMetricsHistory).record_update(metrics)
			plots_dirty = true

	for index in range(retired_trainers.size() - 1, -1, -1):
		var retired = retired_trainers[index]
		retired.poll_background_update()
		if not retired.has_background_update():
			retired_trainers.remove_at(index)
	if not episode_running:
		# At an episode boundary no old behavior-policy action is still open, so queued
		# partial rollouts can safely claim newly available background slots.
		for group in worker_groups:
			if bool(group.get("active", false)):
				_begin_group_update_if_ready(group, true)
		_flush_pending_auto_saves()


func _background_optimizer_count() -> int:
	var result = 0
	for group in worker_groups:
		if (group["trainer"] as DroneTrainingAlgorithm).has_background_update():
			result += 1
	for trainer in retired_trainers:
		if trainer.has_background_update():
			result += 1
	return result


func _complete_trial_episode(trial: Dictionary) -> void:
	if bool(trial.get("episode_finished", false)):
		return
	trial["episode_finished"] = true
	_unregister_trial_combatant(trial)
	trial["camera_focus_retired_at_usec"] = Time.get_ticks_usec()
	var drone = trial.get("drone") as ServerDrone
	var reward: Dictionary = trial.get("reward", {})
	if is_instance_valid(drone):
		if drone.ml_training_paused:
			drone.set_ml_training_paused(false)
		drone.set_limb_attachments_runtime_active(false, true)
		drone.set_activated(false)
		drone.freeze = true
		# Contact reporting is useful only while the worker is alive. Finished workers may wait
		# a long time for the slowest peer, so detach their contact monitor until the reset.
		drone.contact_monitor = false
		drone.max_contacts_reported = 0
		DroneTrainingRoomPresentation.set_drone_episode_finished(
			drone,
			str(reward.get("termination_reason", "finished"))
		)
		_play_drone_disable_sound(drone)
	if (
		camera_focus_mode == CAMERA_FOCUS_ATTACHED_RANDOM_DRONE
		and int(trial.get("instance_id", -1)) == attached_camera_instance_id
	):
		_select_attached_camera_host(false)
	trial["completed_episodes"] = int(trial.get("completed_episodes", 0)) + 1
	trial["best_mean_reward"] = maxf(
		float(trial.get("best_mean_reward", -INF)),
		float(reward.get("mean_reward_per_second", -INF))
	)
	if str(trial.get("mode", "evaluation")) == "algorithm_training":
		var group = _group_by_id(int(trial.get("group_id", -1)))
		if not group.is_empty():
			var trainer: DroneTrainingAlgorithm = group["trainer"]
			trainer.set_evaluation_contract(
				_evaluation_contract_for_group_id(int(group.get("group_id", -1)), "drone")
			)
			trainer.record_completed_episode(
				float(reward.get("mean_reward_per_second", 0.0))
			)
			var expected_group_results = maxi(
				_trials_for_group(int(group.get("group_id", -1))).size(),
				1
			)
			(group["history"] as DroneTrainingMetricsHistory).record_episode(
				reward,
				expected_group_results
			)
			plots_dirty = true
		return
	if bool(trial.get("version_deleted", false)):
		trial["last_run_id"] = ""
		return
	var evaluator_path: TrainingPathTargetSystem = _target_path_for_group_id(-1)
	var evaluator_target: Dictionary = _resolved_target_for_trial(trial)
	var stored_result = DroneTrainingEpisode.build_persistence_record(
		trial,
		evaluator_path.behavior_name() if evaluator_path != null else "Priority routed",
		evaluator_path.speed_mps if evaluator_path != null else 0.0,
		maxf(float(evaluator_target.get("radius_m", 0.75)), 0.05),
		evaluator_target.get("position_world", _target_objective_position())
	)
	stored_result["reward_components"] = trial.get(
		"reward_components",
		DroneTrainingReward.DEFAULT_COMPONENTS
	).duplicate()
	stored_result["reward_cards"] = (trial.get("reward_cards", {}) as Dictionary).duplicate(true)
	var run_id = model_registry.record_episode(trial.get("version", {}), stored_result)
	trial["last_run_id"] = run_id


func _end_episode() -> void:
	_finish_nonblocking_evaluators()
	episode_running = false
	for group in worker_groups:
		if bool(group["active"]):
			_begin_group_update_if_ready(group, true)
	_flush_pending_auto_saves()
	intermission_remaining = (
		EPISODE_INTERMISSION_SECONDS
		if auto_restart_episodes and not trials.is_empty()
		else 0.0
	)
	var termination_summary = _episode_termination_summary()
	status_label.text = "Episode %d complete at %.1f / %.1f s%s." % [
		episode_number,
		episode_elapsed,
		episode_duration,
		"" if termination_summary.is_empty() else " · %s" % termination_summary,
	]
	_refresh_interface()


func _episode_termination_summary() -> String:
	var counts: Dictionary = {}
	# Report only the trials that participated in the cycle that just ended. Paused drone
	# groups retain an older suspended episode and must not appear as "still running" in a
	# different group's completion summary.
	for trial: Dictionary in _episode_completion_trials():
		var reward: Dictionary = trial.get("reward", {})
		var reason = str(reward.get("termination_reason", "unknown"))
		counts[reason] = int(counts.get(reason, 0)) + 1
	var labels = {
		"time_limit": "time limit",
		"power_loss": "battery depleted",
		"ground_crash": "ground crash",
		"left_arena": "left arena",
		"flipped": "flipped",
		"wall_deadlock": "wall deadlock",
		"destroyed": "destroyed",
		"reset_failed": "reset failed",
		"running": "still running",
		"unknown": "unknown",
	}
	var ordered_reasons = [
		"time_limit", "power_loss", "ground_crash", "left_arena",
		"flipped", "wall_deadlock", "destroyed", "reset_failed", "running", "unknown",
	]
	var parts = PackedStringArray()
	for reason in ordered_reasons:
		if not counts.has(reason):
			continue
		parts.append("%s ×%d" % [labels[reason], int(counts[reason])])
		counts.erase(reason)
	for reason in counts:
		parts.append("%s ×%d" % [DroneTrainingRoomPresentation.friendly_name(str(reason)), int(counts[reason])])
	return ", ".join(parts)


func _apply_target_objective(
	drone: ServerDrone,
	obstacle_probe: Dictionary,
	turret_threat_probe: Dictionary = {},
	target_group_id: int = -1,
	episode_progress_override: float = -1.0
) -> void:
	var target: Dictionary = _resolved_target_for_group_id(target_group_id)
	var objective_episode_progress: float = (
		clampf(episode_progress_override, 0.0, 1.0)
		if episode_progress_override >= 0.0
		else clampf(
			episode_elapsed / maxf(episode_duration, 0.1),
			0.0,
			1.0
		)
	)
	drone.set_ml_objective({
		"target_position_world": target.get(
			"position_world",
			_target_objective_position(target_group_id)
		),
		"target_velocity_world": target.get("velocity_world", Vector3.ZERO),
		"target_hover_radius_m": maxf(float(target.get("radius_m", 0.75)), 0.05),
		"episode_progress": objective_episode_progress,
		"obstacle_probe": obstacle_probe,
		"turret_threat_probe": turret_threat_probe,
	})


func _trial_episode_progress(trial: Dictionary) -> float:
	var episode = trial.get("episode") as DroneTrainingEpisode
	if episode == null:
		return 0.0
	return clampf(
		episode.elapsed_seconds / maxf(episode.duration_seconds, 0.1),
		0.0,
		1.0
	)


func _trial_episode_number(trial: Dictionary) -> int:
	var episode = trial.get("episode") as DroneTrainingEpisode
	return episode.episode_number if episode != null else episode_number


func _trial_episode_elapsed(trial: Dictionary) -> float:
	var episode = trial.get("episode") as DroneTrainingEpisode
	return episode.elapsed_seconds if episode != null else episode_elapsed


func group_episode_progress_text(group: Dictionary, family: String) -> String:
	var fallback_episode: int = int(group.get("episode", 0))
	var current_episode: int = fallback_episode
	var elapsed: float = 0.0
	var duration: float = 0.0
	var found_runtime: bool = false
	if family == "drone":
		var group_id: int = int(group.get("group_id", -1))
		for trial: Dictionary in trials:
			if (
				str(trial.get("mode", "evaluation")) != "algorithm_training"
				or int(trial.get("group_id", -1)) != group_id
			):
				continue
			var trial_episode: DroneTrainingEpisode = trial.get("episode") as DroneTrainingEpisode
			if trial_episode == null:
				continue
			found_runtime = true
			current_episode = maxi(current_episode, trial_episode.episode_number)
			elapsed = maxf(elapsed, trial_episode.elapsed_seconds)
			duration = maxf(duration, trial_episode.duration_seconds)
	else:
		var workers_value: Variant = group.get("workers", [])
		if workers_value is Array:
			var workers: Array = workers_value as Array
			for worker_value: Variant in workers:
				if not (worker_value is Dictionary):
					continue
				var worker: Dictionary = worker_value as Dictionary
				found_runtime = true
				elapsed = maxf(elapsed, float(worker.get("episode_elapsed", 0.0)))
				duration = maxf(duration, float(worker.get("episode_duration", episode_duration)))
	if found_runtime and duration > 0.0:
		return "episode %d · %.1f/%.1f s" % [current_episode, elapsed, duration]
	return "episode %d" % current_episode


func _push_target_objective_to_live_drones() -> void:
	for trial in trials:
		if bool(trial.get("episode_finished", false)):
			continue
		var drone = trial.get("drone") as ServerDrone
		var obstacle_probe: Dictionary = trial.get("obstacle_probe", {})
		if not is_instance_valid(drone):
			continue
		var target_group_id: int = (
			int(trial.get("group_id", -1))
			if str(trial.get("mode", "evaluation")) == "algorithm_training"
			else -1
		)
		_apply_target_objective(
			drone,
			obstacle_probe,
			trial.get("turret_threat_probe", {}),
			target_group_id,
			_trial_episode_progress(trial)
		)


func _refresh_random_target_area_preview() -> void:
	if not is_instance_valid(target_random_area_preview):
		return
	var path_system: TrainingPathTargetSystem = _target_editor_path()
	var should_show: bool = (
		path_system != null
		and target_editor_type_id == str(TrainingPathTargetSystem.TYPE_ID)
		and path_system.random_area_visible
		and path_system.behavior == 3
	)
	target_random_area_preview.visible = should_show
	if not should_show:
		return
	var minimum_height: float = minf(
		path_system.random_height_range_m.x,
		path_system.random_height_range_m.y
	)
	var maximum_height: float = maxf(
		path_system.random_height_range_m.x,
		path_system.random_height_range_m.y
	)
	var box = target_random_area_preview.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		target_random_area_preview.mesh = box
	box.size = Vector3(
		maxf(absf(path_system.random_horizontal_extent_m.x) * 2.0, 0.05),
		maxf(maximum_height - minimum_height, 0.05),
		maxf(absf(path_system.random_horizontal_extent_m.y) * 2.0, 0.05)
	)
	target_random_area_preview.position = Vector3(
		0.0,
		(minimum_height + maximum_height) * 0.5,
		0.0
	)


func _move_target_from_pad(normalized_position: Vector2) -> void:
	var path_system: TrainingPathTargetSystem = _target_editor_path()
	if path_system == null:
		return
	var half_width: float = ARENA_SIZE.x * 0.5 - TARGET_PAD_MARGIN_M
	var half_depth: float = ARENA_SIZE.z * 0.5 - TARGET_PAD_MARGIN_M
	path_system.move_manual_target(Vector3(
		lerpf(-half_width, half_width, normalized_position.x),
		path_system.base_height_m,
		lerpf(-half_depth, half_depth, normalized_position.y)
	))
	if target_behavior_picker != null:
		target_behavior_picker.select(MANUAL_TARGET_BEHAVIOR)
	var handler: TrainingTargetHandler = _target_editor_handler()
	if handler != null:
		handler.resolve(_target_context_for_group(_selected_target_group_id()))
	_refresh_target_visual_for_group(_selected_target_group_id())
	_push_target_objective_to_live_drones()
	_update_target_pad_marker()
	_refresh_target_position_label()
	status_label.text = "Live target moved for %s." % (
		"evaluators"
		if _selected_target_group_id() < 0
		else str(_selected_any_training_group().get("name", "selected group"))
	)


func _update_target_pad_marker() -> void:
	if target_pad == null:
		return
	var path_system: TrainingPathTargetSystem = _target_editor_path()
	if path_system == null:
		return
	var half_width: float = ARENA_SIZE.x * 0.5 - TARGET_PAD_MARGIN_M
	var half_depth: float = ARENA_SIZE.z * 0.5 - TARGET_PAD_MARGIN_M
	var normalized = Vector2(
		inverse_lerp(-half_width, half_width, path_system.subject_position_world.x),
		inverse_lerp(-half_depth, half_depth, path_system.subject_position_world.z)
	)
	target_pad.call("set_marker", normalized)


func _reset_target_for_episode() -> void:
	_reset_target_handler_for_group(-1, episode_seed)
	for group: Dictionary in worker_groups:
		if bool(group.get("active", false)):
			var group_id: int = int(group.get("group_id", -1))
			_reset_target_handler_for_group(
				group_id,
				episode_seed + group_id * 7919
			)
	_refresh_random_target_area_preview()
	_update_target_pad_marker()


func _set_target_behavior(index: int) -> void:
	var path_system: TrainingPathTargetSystem = _target_editor_path()
	if path_system == null:
		return
	path_system.set_behavior(index)
	var group_id: int = _selected_target_group_id()
	var handler: TrainingTargetHandler = _target_editor_handler()
	if handler != null:
		var is_turret_group: bool = not turret_training.group_by_id(group_id).is_empty()
		if is_turret_group:
			_sync_turret_group_target_registration(group_id, handler)
		handler.reset(
			EPISODE_SEED_BASE + maxi(group_id, 0) * 7919 + episode_number,
			_target_context_for_group(group_id)
		)
		if is_turret_group:
			_push_turret_resolved_target_identity(group_id, handler)
	_rebuild_target_behavior_settings()
	_refresh_target_visual_for_group(group_id)
	_refresh_random_target_area_preview()
	_target_configuration_changed("Target behavior changed.")


func _set_auto_restart(value: bool) -> void:
	auto_restart_episodes = value
	if value and not episode_running and intermission_remaining <= 0.0 and not trials.is_empty():
		_start_episode("Automatic episode restart enabled.")


func _set_drone_disable_sound_volume_db(value: float) -> void:
	drone_disable_sound_volume_db = clampf(
		value,
		DRONE_DISABLE_SOUND_MINIMUM_VOLUME_DB,
		DRONE_DISABLE_SOUND_MAXIMUM_VOLUME_DB
	)
	for player in drone_disable_sound_players:
		if is_instance_valid(player):
			player.volume_db = drone_disable_sound_volume_db
	if status_label != null:
		status_label.text = "Drone disable sounds set to %d dB." % roundi(
			drone_disable_sound_volume_db
		)


func _set_unlimited_episode_battery(value: bool) -> void:
	unlimited_episode_battery = value
	for trial in trials:
		var drone = trial.get("drone") as ServerDrone
		if is_instance_valid(drone):
			drone.set_ml_episode_unlimited_battery(value)
	var message = (
		"Unlimited episode battery enabled."
		if value
		else "Finite battery endurance enabled."
	)
	_restart_for_configuration_change(message)


func _simulation_speed_text(value: float) -> String:
	var rounded_value = roundf(value)
	if is_equal_approx(value, rounded_value):
		return "%d×" % int(rounded_value)
	return "%s×" % String.num(value, 1)


func _set_simulation_speed(index: int) -> void:
	if (
		simulation_speed_picker == null
		or index < 0
		or index >= simulation_speed_picker.item_count
	):
		return
	simulation_speed = clampf(
		float(simulation_speed_picker.get_item_metadata(index)),
		SIMULATION_SPEEDS[0],
		SIMULATION_SPEEDS[SIMULATION_SPEEDS.size() - 1]
	)
	Engine.time_scale = original_time_scale * simulation_speed
	Engine.physics_ticks_per_second = maxi(
		roundi(float(original_physics_ticks_per_second) * simulation_speed),
		original_physics_ticks_per_second
	)
	# Two rendered frames of catch-up headroom keeps accelerated simulation accurate
	# without allowing an overloaded machine to freeze the UI in a long catch-up spiral.
	Engine.max_physics_steps_per_frame = maxi(
		original_max_physics_steps_per_frame,
		ceili(simulation_speed * 2.0)
	)
	status_label.text = "Simulation running at %s with %d physics ticks per real second." % [
		_simulation_speed_text(simulation_speed),
		Engine.physics_ticks_per_second,
	]
	_refresh_episode_status()


func _restore_engine_timing() -> void:
	Engine.time_scale = original_time_scale
	Engine.physics_ticks_per_second = original_physics_ticks_per_second
	Engine.max_physics_steps_per_frame = original_max_physics_steps_per_frame


func _restart_limb_groups_for_delivery_change(message: String) -> void:
	# Delivery volumes are non-blocking task metadata consumed only by groups that actually enable
	# the delivery lesson. Do not reset unrelated drone/turret training—or locomotion-only limb
	# groups—merely because a delivery policy/volume changed.
	var affected_groups: Array[Dictionary] = []
	for limb_group: Dictionary in limb_training.groups:
		if _limb_group_uses_delivery_task(limb_group):
			affected_groups.append(limb_group)
	for limb_group: Dictionary in affected_groups:
		var limb_group_id: int = int(limb_group.get("group_id", -1))
		var limb_target: Dictionary = _resolved_target_for_group_id(limb_group_id)
		var limb_target_position: Vector3 = limb_target.get(
			"position_world",
			_target_objective_position(limb_group_id)
		)
		var limb_target_velocity: Vector3 = limb_target.get("velocity_world", Vector3.ZERO)
		limb_training.restart_group_for_configuration_change(
			limb_group_id,
			drone_spawn_position,
			limb_target_position,
			limb_target_velocity,
			maxf(float(limb_target.get("radius_m", 0.75)), 0.05),
			episode_duration,
			ARENA_SIZE
		)
	if status_label != null:
		status_label.text = message


func _restart_for_configuration_change(
	message: String,
	invalidate_paused_drone_groups: bool = true,
	restart_limb_groups: bool = false,
	restart_turret_groups: bool = false
) -> void:
	if restart_limb_groups:
		# Four-limb candidate evaluation has task-conditional pickup/delivery scenarios. Any
		# shared task/environment edit that restarts limb groups invalidates an in-flight hidden
		# evaluation so it cannot finish under a mixture of old/new room semantics.
		candidate_evaluation_environment_revision += 1
	# Ordinary pause retains a live drone by design. An actual environment/task edit is a
	# different boundary: a suspended transition must never resume under changed physics or
	# objective semantics. Retire only the paused populations here; _start_episode() handles
	# active groups and evaluators through the normal shared-cycle path.
	if invalidate_paused_drone_groups:
		for group: Dictionary in worker_groups:
			if bool(group.get("active", false)) or (group.get("trials", []) as Array).is_empty():
				continue
			_clear_drone_group_runtime_for_configuration_change(group)
	if restart_limb_groups:
		for limb_group: Dictionary in limb_training.groups:
			var limb_group_id: int = int(limb_group.get("group_id", -1))
			var limb_target: Dictionary = _resolved_target_for_group_id(limb_group_id)
			var limb_target_position: Vector3 = limb_target.get(
				"position_world",
				_target_objective_position(limb_group_id)
			)
			var limb_target_velocity: Vector3 = limb_target.get("velocity_world", Vector3.ZERO)
			limb_training.restart_group_for_configuration_change(
				limb_group_id,
				drone_spawn_position,
				limb_target_position,
				limb_target_velocity,
				maxf(float(limb_target.get("radius_m", 0.75)), 0.05),
				episode_duration,
				ARENA_SIZE
			)
	if restart_turret_groups:
		for turret_group: Dictionary in turret_training.groups:
			var turret_group_id: int = int(turret_group.get("group_id", -1))
			turret_training.restart_group_for_configuration_change(
				turret_group_id,
				_target_objective_position(turret_group_id),
				episode_duration,
				ARENA_SIZE
			)
	if not trials.is_empty():
		_start_episode(message)
	elif status_label != null:
		status_label.text = message


func _save_selected_group_best() -> void:
	_save_group_best(selected_group_id)


func _save_group_best(group_id: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if not trainer.has_best_checkpoint():
		status_label.text = "No preserved best candidate exists yet. Let this group complete a %s episode, or use Save Current." % trainer.algorithm_short_name()
		return
	_save_group_checkpoint(group, trainer.to_best_checkpoint(), "best")


func _save_selected_group_current() -> void:
	_save_group_current(selected_group_id)


func _save_group_current(group_id: int) -> void:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	_save_group_checkpoint(group, trainer.to_checkpoint(), "current")


func _save_group_checkpoint(
	group: Dictionary,
	checkpoint: Dictionary,
	label: String,
	announce = true,
	select_saved_version = true
) -> Dictionary:
	var stored_checkpoint = checkpoint.duplicate(true)
	var group_id: int = int(group.get("group_id", -1))
	var runtime_parent = _group_by_id(int(group.get("parent_group_id", -1)))
	var path_system: TrainingPathTargetSystem = _target_path_for_group_id(group_id)
	var target_configuration: Dictionary = _target_handler_configuration_for_group(group_id)
	stored_checkpoint["training_environment"] = {
		"reward_schema_version": DroneTrainingReward.SCHEMA_VERSION,
		"reward_components": group.get(
			"reward_components",
			DroneTrainingReward.DEFAULT_COMPONENTS
		).duplicate(),
		"reward_cards": _ensure_drone_reward_deck(group).configuration_dictionary(),
		"episode_termination": _episode_termination_options_for_group(group),
		"reward_cardset": {
			"id": str(group.get("reward_cardset_id", "custom")),
			"display_name": str(group.get("reward_cardset_name", "Custom")),
		},
		"arena_size_m": [ARENA_SIZE.x, ARENA_SIZE.y, ARENA_SIZE.z],
		"drone_spawn_position_m": [
			drone_spawn_position.x,
			drone_spawn_position.y,
			drone_spawn_position.z,
		],
		"custom_walls": _custom_wall_environment_records(),
		"training_items": _training_item_environment_records(),
		"target_handler": target_configuration,
		# Keep readable flat metadata for external inspection. The handler configuration above
		# is authoritative for restoring current training state.
		"target_behavior": path_system.behavior_name() if path_system != null else "Priority routed",
		"target_speed_mps": path_system.speed_mps if path_system != null else 0.0,
		"target_hover_radius_m": path_system.hover_radius_m if path_system != null else 0.75,
		"target_base_height_m": path_system.base_height_m if path_system != null else 0.0,
		"target_path_radius_m": path_system.path_radius_m if path_system != null else 0.0,
		"target_line_half_length_m": path_system.line_half_length_m if path_system != null else 0.0,
		"target_path_rotation_degrees": [
			path_system.path_rotation_degrees.x if path_system != null else 0.0,
			path_system.path_rotation_degrees.y if path_system != null else 0.0,
			path_system.path_rotation_degrees.z if path_system != null else 0.0,
		],
		"target_path_phase_degrees": path_system.path_phase_degrees if path_system != null else 0.0,
		"target_path_reverse": path_system.path_reverse if path_system != null else false,
		"target_random_horizontal_extent_m": [
			path_system.random_horizontal_extent_m.x if path_system != null else 0.0,
			path_system.random_horizontal_extent_m.y if path_system != null else 0.0,
		],
		"target_random_height_range_m": [
			path_system.random_height_range_m.x if path_system != null else 0.0,
			path_system.random_height_range_m.y if path_system != null else 0.0,
		],
		"target_random_max_jump_distance_m": path_system.random_max_jump_distance_m if path_system != null else 0.0,
		"target_random_waypoint_interval_seconds": path_system.random_waypoint_interval_seconds if path_system != null else 0.0,
		"runtime_branch_parent_name": str(runtime_parent.get("name", "")),
		"runtime_branch_weight_variation": float(group.get(
			"branch_weight_variation",
			0.0
		)),
		"episode_duration_seconds": episode_duration,
		"unlimited_episode_battery": unlimited_episode_battery,
		"drone_loadout": LOADOUT_CONFIG.to_record(
			group.get("drone_loadout") as DroneLoadout
		),
	}
	# Keep room continuation settings and verified Best provenance separate. A user may edit
	# loadout/rewards/targets after Best was promoted; those current settings must not rewrite
	# the benchmark contract under which the preserved Best was actually measured.
	var trainer = group.get("trainer") as DroneTrainingAlgorithm
	var current_contract: Dictionary = _evaluation_contract_for_group_id(group_id, "drone")
	if RLEvaluationContract.is_valid(current_contract, "drone"):
		stored_checkpoint["current_room_evaluation_contract"] = current_contract
	if label == "best" or label == "auto_best":
		var best_contract: Dictionary = (
			trainer.best_evaluation_contract_snapshot() if trainer != null else {}
		)
		if RLEvaluationContract.is_valid(best_contract, "drone"):
			stored_checkpoint["best_evaluation_contract"] = best_contract

	var overwrite_enabled = bool(group.get("overwrite_saved_versions", true))
	var rolling_version_id = str(group.get("rolling_version_id", ""))
	var version: Dictionary = {}
	var overwritten_existing = false
	if overwrite_enabled and not rolling_version_id.is_empty():
		# A library deletion can remove the rolling target while the runtime group remains
		# alive. Renaming is also a family fork: a rolling manifest keeps the name it was
		# created with, so a differently named group must create a new version rather than
		# silently updating the old visible model.
		var rolling_record: Dictionary = model_registry.get_version(rolling_version_id)
		if (
			rolling_record.is_empty()
			or not _rolling_record_matches_requested_name(
				rolling_record,
				str(group.get("name", "Worker group"))
			)
		):
			group["rolling_version_id"] = ""
			rolling_version_id = ""
		else:
			version = model_registry.overwrite_training_checkpoint(
				rolling_version_id,
				stored_checkpoint,
				label
			)
			overwritten_existing = not version.is_empty()
	if version.is_empty() and rolling_version_id.is_empty():
		version = model_registry.save_training_checkpoint(
			str(group.get("name", "Worker group")),
			stored_checkpoint,
			str(group.get("parent_version_id", "")),
			label
		)
	if version.is_empty():
		status_label.text = "Could not save checkpoint: %s" % model_registry.last_error
		return {}
	var saved_inspection = model_registry.inspect_version(version)
	if not bool(saved_inspection.get("trainable", false)):
		status_label.text = "The checkpoint was written but failed the read-back check: %s" % str(
			saved_inspection.get("compatibility_text", model_registry.last_error)
		)
		return {}
	if overwrite_enabled:
		group["rolling_version_id"] = str(version.get("version_id", ""))
	group["model_family_name"] = str(version.get("model_name", "Model X"))
	if label == "current":
		group["parent_version_id"] = str(version.get("version_id", ""))
		group["source_version_id"] = str(version.get("version_id", ""))
		group["source_description"] = "Current live policy saved as %s" % model_registry.display_name(version)
		group["source_label"] = model_registry.display_name(version)
		group["source_update_count"] = (group["trainer"] as DroneTrainingAlgorithm).update_count_value()
		group["last_exact_saved_version_id"] = str(version.get("version_id", ""))
		group["last_exact_saved_update"] = (group["trainer"] as DroneTrainingAlgorithm).update_count_value()
	var preferred_version_id = str(version.get("version_id", ""))
	if not select_saved_version:
		preferred_version_id = str(_selected_model_record().get("version_id", ""))
	_refresh_model_versions(preferred_version_id)
	_refresh_selected_group_controls()
	if announce:
		var save_verb = "Updated" if overwritten_existing else "Saved"
		var save_location = (
			"in %s" if overwritten_existing else "as %s"
		) % model_registry.display_name(version)
		status_label.text = "%s %s policy %s." % [
			save_verb,
			label,
			save_location,
		]
	return version


func _mark_group_auto_save_pending(group: Dictionary) -> void:
	if group.is_empty():
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if trainer.pending_auto_save_candidate().is_empty():
		return
	_refresh_group_card_texts()


func _flush_pending_auto_saves(flush_all = false) -> void:
	for group in worker_groups:
		if _flush_group_pending_auto_save(group, bool(flush_all)) and not bool(flush_all):
			# Stagger multiple groups across rendered frames. JSON serialization and disk IO
			# are small but synchronous, so writing every model on one boundary could recreate
			# the UI hitch that background optimization removed.
			break
	_refresh_group_card_texts()


func _flush_group_pending_auto_save(
	group: Dictionary,
	ignore_retry_delay = false
) -> bool:
	if group.is_empty():
		return false
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if (
		not bool(ignore_retry_delay)
		and Time.get_ticks_usec() < int(group.get("auto_save_retry_after_usec", 0))
	):
		return false
	var candidate = trainer.pending_auto_save_candidate()
	if candidate.is_empty() or not trainer.has_best_checkpoint():
		return false
	var version = _save_group_checkpoint(
		group,
		trainer.to_best_checkpoint(),
		"auto_best",
		false,
		false
	)
	if version.is_empty():
		group["auto_save_retry_after_usec"] = Time.get_ticks_usec() + 5000000
		return false
	trainer.acknowledge_auto_save_candidate(
		RLTrainingMath.finite_int_or(candidate.get("candidate_id", -1), -1)
	)
	group["last_auto_saved_version_id"] = str(version.get("version_id", ""))
	group["last_auto_saved_candidate"] = candidate.duplicate(true)
	group["auto_save_flash_until_usec"] = Time.get_ticks_usec() + 5000000
	group["auto_save_retry_after_usec"] = 0
	group["parent_version_id"] = str(version.get("version_id", ""))
	if int(group.get("group_id", -1)) == selected_group_id:
		status_label.text = "Automatic Best saved %s at selection score %+.3f/s." % [
			model_registry.display_name(version),
			float(candidate.get("selection_score", 0.0)),
		]
	return true


func _refresh_group_auto_save_label(group: Dictionary, label: Label) -> void:
	if label == null or group.is_empty():
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var pending = trainer.pending_auto_save_candidate()
	var evaluation_candidate_id: int = trainer.pending_evaluation_candidate_id()
	var saved: Dictionary = group.get("last_auto_saved_candidate", {})
	if evaluation_candidate_id >= 0:
		label.visible = true
		label.add_theme_color_override("font_color", Color("8de1ff"))
		var group_id: int = int(group.get("group_id", -1))
		var progress: Dictionary = _candidate_evaluation_progress(group_id)
		var queue_position: int = int(group.get("candidate_evaluation_queue_position", 0))
		if not progress.is_empty():
			var completed_cases: int = int(progress.get("completed_cases", 0))
			var current_case_number: int = int(progress.get("current_case_number", 0))
			var total_cases: int = int(progress.get("total_cases", 0))
			var scenario_label: String = _candidate_evaluation_scenario_label(
				str(progress.get("scenario_id", ""))
			)
			var subject: String = str(group.get("candidate_evaluation_subject", "candidate"))
			var subject_label: String = "BEST BASELINE" if subject == "best_baseline" else "CANDIDATE"
			label.text = "◇ FIXED-SEED %s %d/%d · %s · %.1f/%.1fs" % [
				subject_label,
				current_case_number,
				total_cases,
				scenario_label,
				float(progress.get("case_elapsed_seconds", 0.0)),
				float(progress.get("case_duration_seconds", 0.0)),
			]
			label.tooltip_text = (
				"The preserved Best policy is being re-evaluated under candidate %d's frozen environment contract before the two policies are compared."
				if subject == "best_baseline"
				else "Frozen candidate %d is actively running a deterministic shadow evaluation. Training may continue, and pausing this worker group does not pause verification."
			) % evaluation_candidate_id
			label.tooltip_text += " Completed %d of %d fixed-seed cases. Environment restarts: %d. The . .. ... animation remains reserved for training-data collection." % [
				completed_cases,
				total_cases,
				int(progress.get("restart_count", 0)),
			]
		elif queue_position > 0:
			label.text = "◇ FIXED-SEED EVAL QUEUED · position %d" % queue_position
			label.tooltip_text = "Frozen candidate %d is queued for deterministic evaluation. Only %d hidden evaluator runs at once so model verification cannot become another simulation-performance regression. Paused groups remain eligible and will advance when the evaluator slot is free." % [
				evaluation_candidate_id,
				CANDIDATE_EVALUATION_MAX_CONCURRENT,
			]
		else:
			label.text = "◇ FIXED-SEED EVAL STARTING"
			label.tooltip_text = "Training nominated frozen candidate %d. The universal room is preparing its deterministic shadow evaluator." % evaluation_candidate_id
		return
	var last_evaluation: Dictionary = group.get("candidate_evaluation_last_result", {})
	if (
		not last_evaluation.is_empty()
		and Time.get_ticks_usec() < int(last_evaluation.get("until_usec", 0))
		and str(last_evaluation.get("reason", "")) == "best_baseline_ready"
	):
		label.visible = true
		label.text = "◇ BEST BASELINE VERIFIED · CANDIDATE NEXT"
		label.add_theme_color_override("font_color", Color("76ddff"))
		label.tooltip_text = "The preserved Best has just been measured under the candidate's frozen evaluation contract. The queued candidate will now run against the same benchmark."
		return
	if (
		not last_evaluation.is_empty()
		and Time.get_ticks_usec() < int(last_evaluation.get("until_usec", 0))
		and not bool(last_evaluation.get("promoted", false))
	):
		label.visible = true
		var evaluation_error: bool = bool(last_evaluation.get("evaluation_error", false))
		var reason_text: String = str(last_evaluation.get("reason", "not promoted"))
		label.text = "◇ FIXED-SEED EVAL %s · %s" % [
			"ERROR" if evaluation_error else "REJECTED",
			DroneTrainingRoomPresentation.friendly_name(reason_text).to_upper(),
		]
		label.add_theme_color_override(
			"font_color",
			Color("ff6b6b") if evaluation_error else Color("ffad42")
		)
		label.tooltip_text = (
			"Candidate %d evaluator failed validation and was discarded so it cannot leave this group permanently stuck in an evaluation-pending state. Reason: %s."
			if evaluation_error
			else "Candidate %d completed verification but did not replace Best. Reason: %s. Training continues and may nominate a later policy."
		) % [
			int(last_evaluation.get("candidate_id", -1)),
			reason_text,
		]
		return
	var saved_version_id = str(group.get("last_auto_saved_version_id", ""))
	if not pending.is_empty():
		label.visible = true
		label.text = "● NEW AUTO-BEST PENDING // score %+.3f/s" % float(
			pending.get("selection_score", 0.0)
		)
		label.add_theme_color_override("font_color", Color("ffad42"))
		label.tooltip_text = _auto_save_candidate_tooltip(pending) + "\n\nIt will be written at the current episode boundary so repeated tiny improvements do not create several disk versions per second."
		return
	if saved.is_empty() or saved_version_id.is_empty():
		label.visible = false
		return
	label.visible = true
	label.text = "✓ AUTO-SAVED %s // score %+.3f/s" % [
		saved_version_id,
		float(saved.get("selection_score", 0.0)),
	]
	label.add_theme_color_override(
		"font_color",
		Color("a7ffd9")
		if Time.get_ticks_usec() < int(group.get("auto_save_flash_until_usec", 0))
		else Color("54e6b1")
	)
	label.tooltip_text = _auto_save_candidate_tooltip(saved)


func _auto_save_candidate_tooltip(candidate: Dictionary) -> String:
	return "Automatic best save\n\nThis checkpoint contains the exact policy that produced the measured episode.\n\nSelection score: %+.3f/s\nStrong worker result: %+.3f/s\nTypical worker support: %+.3f/s\nBest single worker: %+.3f/s\nWhole-group mean: %+.3f/s\n\nThe score combines a strong result with support from the rest of the group, so one lucky outlier cannot win by itself." % [
		float(candidate.get("selection_score", 0.0)),
		float(candidate.get("robust_best_worker_reward_per_second", 0.0)),
		float(candidate.get("support_reward_per_second", 0.0)),
		float(candidate.get("best_worker_reward_per_second", 0.0)),
		float(candidate.get("group_mean_reward_per_second", 0.0)),
	]


func _apply_selected_policy_to_all_groups() -> void:
	var source = _selected_group()
	if source.is_empty():
		return
	var source_trainer: DroneTrainingAlgorithm = source["trainer"]
	var source_algorithm_id: String = str(source.get("algorithm_id", ""))
	var source_architecture: Dictionary = source_trainer.network_architecture()
	var source_action_count: int = int(source_architecture.get("action_count", 0))
	var source_body_feature_count: int = int(source_architecture.get("body_feature_count", -1))
	var source_body_signature: String = str(source_architecture.get("body_interface_signature", ""))
	var applied_count = 0
	var incompatible_count = 0
	for group in worker_groups:
		if int(group["group_id"]) == int(source["group_id"]):
			continue
		var trainer: DroneTrainingAlgorithm = group["trainer"]
		var target_architecture: Dictionary = trainer.network_architecture()
		var target_action_count: int = int(target_architecture.get("action_count", 0))
		if (
			str(group.get("algorithm_id", "")) != source_algorithm_id
			or target_action_count != source_action_count
			or int(target_architecture.get("body_feature_count", -1)) != source_body_feature_count
			or str(target_architecture.get("body_interface_signature", "")) != source_body_signature
		):
			incompatible_count += 1
			continue
		if not trainer.copy_policy_from(source_trainer):
			incompatible_count += 1
			continue
		applied_count += 1
		(group["history"] as DroneTrainingMetricsHistory).reset()
		group["model_family_name"] = source.get("model_family_name", "Model X")
		group["parent_version_id"] = source.get("parent_version_id", "")
		group["source_version_id"] = source.get("source_version_id", "")
		group["source_description"] = "Copied from %s at update %d" % [
			source["name"],
			source_trainer.update_count_value(),
		]
		group["source_label"] = "Copy of %s" % source["name"]
		group["source_update_count"] = source_trainer.update_count_value()
		group["last_exact_saved_version_id"] = source.get("last_exact_saved_version_id", "")
		group["last_exact_saved_update"] = source.get("last_exact_saved_update", -1)
		group["last_auto_saved_version_id"] = ""
		group["last_auto_saved_candidate"] = {}
		group["rolling_version_id"] = ""
		group["auto_save_retry_after_usec"] = 0
	plots_dirty = true
	if not trials.is_empty():
		_start_episode("Selected policy applied to every worker group.")
	status_label.text = "%s policy copied into %d compatible groups; %d incompatible algorithm/topology groups were left unchanged." % [
		source["name"],
		applied_count,
		incompatible_count,
	]


func _reset_selected_group_statistics() -> void:
	var turret_group = _selected_turret_group()
	if not turret_group.is_empty():
		turret_training.reset_group_statistics(int(turret_group["group_id"]))
		plots_dirty = true
		_refresh_plots()
		status_label.text = "%s averages and plots reset; model weights were kept." % turret_group["name"]
		return
	var group = _selected_group()
	if not group.is_empty():
		(group["trainer"] as DroneTrainingAlgorithm).reset_episode_statistics()
		(group["history"] as DroneTrainingMetricsHistory).reset()
		group["last_auto_saved_version_id"] = ""
		group["last_auto_saved_candidate"] = {}
		group["auto_save_retry_after_usec"] = 0
		plots_dirty = true
		_refresh_plots()
		status_label.text = "%s averages and plots reset; model weights were kept." % group["name"]
		return
	var limb_group = _selected_limb_group()
	if limb_group.is_empty():
		return
	limb_training.reset_group_statistics(int(limb_group["group_id"]))
	plots_dirty = true
	_refresh_plots()
	status_label.text = "%s averages and plots reset; model weights were kept." % limb_group["name"]


func _load_selected_checkpoint_into_group() -> void:
	var group = _selected_group()
	var version = _selected_model_record()
	if group.is_empty() or version.is_empty():
		return
	_load_checkpoint_version_into_group(group, version)


func _load_checkpoint_version_into_group(
	group: Dictionary,
	version: Dictionary
) -> bool:
	if group.is_empty() or version.is_empty():
		return false
	if bool(group.get("active", false)):
		status_label.text = "Pause the selected group before loading a checkpoint."
		return false
	if not DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
		status_label.text = "The selected version is a diagnostic baseline, not a trainable checkpoint."
		return false
	if str(version.get(
		"training_algorithm_id",
		DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
	)) != str(group.get("algorithm_id", "")):
		status_label.text = "This checkpoint uses a different learning algorithm. Create a new root group with that algorithm instead of replacing incompatible live state."
		return false
	var inspection = model_registry.inspect_version(version)
	if not bool(inspection.get("trainable", false)):
		status_label.text = str(inspection.get(
			"compatibility_text",
			"This checkpoint can be evaluated but not continued by the current trainer."
		))
		return false
	var checkpoint = model_registry.load_training_checkpoint(version)
	var training_environment_value: Variant = version.get("training_environment", {})
	var training_environment: Dictionary = (
		training_environment_value as Dictionary
		if training_environment_value is Dictionary
		else {}
	)
	var saved_reward_schema: int = RLTrainingMath.finite_int_or(
		training_environment.get("reward_schema_version", 1), 1
	)
	var saved_termination_value: Variant = training_environment.get("episode_termination", null)
	var legacy_terminal_semantics: bool = not (saved_termination_value is Dictionary)
	var reward_statistics_reset: bool = (
		saved_reward_schema != DroneTrainingReward.SCHEMA_VERSION
		or legacy_terminal_semantics
	)
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if checkpoint.is_empty() or not trainer.load_checkpoint(checkpoint):
		status_label.text = "Could not load checkpoint: %s%s" % [
			model_registry.last_error,
			trainer.last_error_text(),
		]
		return false
	# Loading another policy is a hard behavior boundary. Ordinary pause keeps the exact live
	# drone and held action, so explicitly retire that suspended runtime before installing the
	# loaded policy/hardware into the next episode. Limb and turret checkpoint loads already do
	# the same through their coordinator clear-worker paths.
	_clear_drone_group_runtime_for_configuration_change(group)
	_load_episode_termination_options_into_group(group, training_environment)
	if reward_statistics_reset:
		# The network and optimizer state are compatible, but reward values from the old
		# projected-motion contract cannot compete with scores from the corrected contract.
		# Keep the learned policy plus optimizer update/environment-step counters while
		# clearing episode counts and score-derived best state.
		trainer.reset_episode_statistics()
	var saved_loadout_value: Variant = training_environment.get("drone_loadout", {})
	var saved_loadout_record: Dictionary = (
		(saved_loadout_value as Dictionary).duplicate(true)
		if saved_loadout_value is Dictionary
		else {}
	)
	var restored_hardware = not saved_loadout_record.is_empty()
	if restored_hardware:
		var restored_loadout: DroneLoadout = LOADOUT_CONFIG.from_record(saved_loadout_record)
		if restored_loadout == null:
			status_label.text = "Checkpoint contains an invalid drone body record."
			return false
		group["drone_loadout"] = restored_loadout
		group["hardware_revision"] = int(group.get("hardware_revision", 0)) + 1
	if not _ensure_group_drone_profile_hardware(group):
		status_label.text = "Checkpoint policy topology cannot be matched by the restored drone hardware."
		return false
	group["parent_version_id"] = str(version.get("version_id", ""))
	group["source_version_id"] = str(version.get("version_id", ""))
	group["source_description"] = "Loaded from %s" % model_registry.display_name(version)
	group["source_label"] = model_registry.display_name(version)
	group["source_update_count"] = trainer.update_count_value()
	group["last_exact_saved_version_id"] = str(version.get("version_id", ""))
	group["last_exact_saved_update"] = trainer.update_count_value()
	group["last_auto_saved_version_id"] = (
		str(version.get("version_id", ""))
		if (
			str(version.get("checkpoint_kind", "")) == "auto_best"
			and not reward_statistics_reset
		)
		else ""
	)
	group["last_auto_saved_candidate"] = (
		{} if reward_statistics_reset else trainer.best_selection_summary()
	)
	# Loading identifies a source checkpoint, never an overwrite target. A group with
	# rolling saves enabled creates its own new rolling version on the next save.
	group["rolling_version_id"] = ""
	group["auto_save_retry_after_usec"] = 0
	group["model_family_name"] = str(version.get("model_name", "Model X"))
	var target_handler_value: Variant = training_environment.get("target_handler", {})
	var target_handler_configuration: Dictionary = (
		(target_handler_value as Dictionary).duplicate(true)
		if target_handler_value is Dictionary else {}
	)
	if not target_handler_configuration.is_empty():
		_load_target_handler_configuration_for_group(
			int(group.get("group_id", -1)),
			target_handler_configuration
		)
	(group["history"] as DroneTrainingMetricsHistory).reset()
	model_registry.mark_version_used(version)
	_refresh_model_versions(str(version.get("version_id", "")))
	plots_dirty = true
	_refresh_selected_group_controls()
	status_label.text = "%s loaded into %s. Reward switches were kept%s%s." % [
		model_registry.display_name(version),
		group["name"],
		" and the saved drone hardware was restored" if restored_hardware else "",
		"; its legacy score baseline was reset while keeping the learned weights"
		if reward_statistics_reset
		else "",
	]
	return true


func _set_selected_worker_count(requested_count: int) -> void:
	if suppress_ui_callbacks:
		return
	var group = _selected_group()
	if not group.is_empty():
		_set_group_worker_count(int(group["group_id"]), requested_count)
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		_set_limb_group_worker_count(int(limb_group["group_id"]), requested_count)
		return
	var turret_group = _selected_turret_group()
	if not turret_group.is_empty():
		turret_ui.set_group_worker_count(int(turret_group["group_id"]), requested_count)


func _set_selected_control_rate(rate_hz: float) -> void:
	if suppress_ui_callbacks:
		return
	var interval = 1.0 / maxf(rate_hz, 1.0)
	var group = _selected_group()
	if not group.is_empty():
		_set_selected_config_value("control_interval_seconds", interval, false)
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		if bool(limb_group.get("active", false)):
			status_label.text = "Pause %s before changing its control rate." % limb_group["name"]
			return
		limb_training.set_control_interval(int(limb_group["group_id"]), interval)
		return
	var turret_group = _selected_turret_group()
	if turret_group.is_empty():
		return
	if bool(turret_group.get("active", false)):
		status_label.text = "Pause %s before changing its control rate." % turret_group["name"]
		return
	turret_training.set_control_interval(int(turret_group["group_id"]), interval)


func _set_selected_config_value(
	config_key: String,
	value: float,
	integer_value: bool
) -> void:
	if suppress_ui_callbacks:
		return
	var group = _selected_group()
	if not group.is_empty():
		var trainer: DroneTrainingAlgorithm = group["trainer"]
		trainer.set_config_value(config_key, int(value) if integer_value else value)
		var config = trainer.config_values()
		if config_key == "rollout_transitions":
			var rollout_size = int(config.get("rollout_transitions", 1))
			if int(config.get("minimum_update_transitions", 1)) > rollout_size:
				trainer.set_config_value("minimum_update_transitions", rollout_size)
		elif config_key == "minimum_update_transitions":
			trainer.set_config_value(config_key, mini(int(value), int(config.get("rollout_transitions", 1))))
		return
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		if bool(limb_group.get("active", false)):
			status_label.text = "Pause %s before changing PPO settings." % limb_group["name"]
			return
		var limb_trainer = limb_group["trainer"] as FourLimbPPOTrainer
		limb_trainer.set_config_value(config_key, int(value) if integer_value else value)
		var limb_config = limb_trainer.config_values()
		if config_key == "rollout_size":
			var limb_rollout_size = int(limb_config.get("rollout_size", 1))
			if int(limb_config.get("minimum_update_transitions", 1)) > limb_rollout_size:
				limb_trainer.set_config_value("minimum_update_transitions", limb_rollout_size)
		elif config_key == "minimum_update_transitions":
			limb_trainer.set_config_value(config_key, mini(int(value), int(limb_config.get("rollout_size", 1))))
		return
	var turret_group = _selected_turret_group()
	if turret_group.is_empty():
		return
	if bool(turret_group.get("active", false)):
		status_label.text = "Pause %s before changing PPO settings." % turret_group["name"]
		return
	var turret_trainer = turret_group["trainer"] as TurretPPOTrainer
	turret_trainer.set_config_value(config_key, int(value) if integer_value else value)
	var turret_config = turret_trainer.config_values()
	if config_key == "rollout_size":
		var turret_rollout_size = int(turret_config.get("rollout_size", 1))
		if int(turret_config.get("minimum_update_transitions", 1)) > turret_rollout_size:
			turret_trainer.set_config_value("minimum_update_transitions", turret_rollout_size)
	elif config_key == "minimum_update_transitions":
		turret_trainer.set_config_value(config_key, mini(int(value), int(turret_config.get("rollout_size", 1))))


func _refresh_selected_group_controls() -> void:
	var group = _selected_group()
	var limb_group = _selected_limb_group()
	var turret_group = _selected_turret_group()
	if selected_group_panel == null:
		return
	selected_group_panel.visible = true
	var has_drone_group = not group.is_empty()
	var has_limb_group = not limb_group.is_empty()
	var has_turret_group = not turret_group.is_empty()
	var has_any_group = has_drone_group or has_limb_group or has_turret_group
	if worker_count_slider != null:
		var worker_count_row: Control = worker_count_slider.get_parent() as Control
		if worker_count_row != null:
			worker_count_row.visible = not has_turret_group
	for page_id: String in workspace_buttons:
		var workspace_button = workspace_buttons.get(page_id) as Button
		if workspace_button == null:
			continue
		match page_id:
			"model", "tuning", "rewards":
				workspace_button.visible = has_any_group
			"plots":
				workspace_button.visible = true
	if not has_any_group:
		if ground_contact_terminal_checkbox != null:
			ground_contact_terminal_checkbox.visible = false
		if flipped_terminal_checkbox != null:
			flipped_terminal_checkbox.visible = false
		selected_group_title.text = "ALL MODELS // COMPARISON"
		training_identity_label.text = "No group selected."
		selected_group_auto_save_label.visible = false
		_refresh_model_workspace_for_selection(false, false, false)
		_refresh_tuning_sections(false, false, false)
		_refresh_selected_loadout_controls()
		_refresh_limb_body_tuning_controls()
		_refresh_loader_identity()
		if workspace_page_id != "plots":
			_set_workspace_page("plots")
		return
	if has_turret_group:
		if ground_contact_terminal_checkbox != null:
			ground_contact_terminal_checkbox.visible = false
		if flipped_terminal_checkbox != null:
			flipped_terminal_checkbox.visible = false
		var turret_trainer = turret_group["trainer"] as TurretPPOTrainer
		if algorithm_controls_id != "turret:%s" % TurretPPOTrainer.ALGORITHM_ID:
			_rebuild_turret_algorithm_controls(turret_trainer)
		selected_group_title.text = str(turret_group["name"])
		training_identity_label.text = "Stationary physical turret · PPO · yaw, pitch, and trigger outputs"
		training_identity_label.tooltip_text = "This model owns a private rotatable base and gun loadout. It is stored in the turret model library and shares only the polymorphic combat/entity contract with drones and limb workers."
		selected_group_auto_save_label.visible = false
		_refresh_model_workspace_for_selection(false, false, true)
		if selected_group_root_button != null:
			selected_group_root_button.visible = int(turret_group.get("parent_group_id", -1)) >= 0
		_refresh_tuning_sections(false, false, true)
		suppress_ui_callbacks = true
		worker_count_slider.max_value = float(TurretTrainingCoordinator.MAXIMUM_WORKER_COUNT)
		worker_count_slider.value = float(turret_group.get("pending_worker_count", turret_group.get("worker_count", 1)))
		control_rate_slider.value = 1.0 / maxf(float(turret_group.get("control_interval_seconds", TurretTrainingCoordinator.DECISION_INTERVAL_SECONDS)), 0.000001)
		var turret_config = turret_trainer.config_values()
		for key in algorithm_config_sliders:
			var turret_slider = algorithm_config_sliders[key] as HSlider
			if turret_slider != null and turret_config.has(key):
				turret_slider.value = float(turret_config[key])
		suppress_ui_callbacks = false
		var turret_editable = not bool(turret_group.get("active", false))
		for control in selected_group_controls:
			control.editable = turret_editable
		_refresh_selected_loadout_controls()
		_refresh_limb_body_tuning_controls()
		_refresh_loader_identity()
		turret_ui.refresh_selection()
		return
	if has_limb_group:
		if ground_contact_terminal_checkbox != null:
			ground_contact_terminal_checkbox.visible = false
		if flipped_terminal_checkbox != null:
			flipped_terminal_checkbox.visible = false
		var limb_trainer = limb_group["trainer"] as FourLimbPPOTrainer
		if algorithm_controls_id != "limb:%s" % FourLimbPPOTrainer.ALGORITHM_ID:
			_rebuild_limb_algorithm_controls(limb_trainer)
		selected_group_title.text = str(limb_group["name"])
		training_identity_label.text = "Four-limb physical body · PPO · %d joint + %d grip outputs" % [FourLimbMLAction.JOINT_ACTION_COUNT, FourLimbMLAction.LIMB_COUNT]
		training_identity_label.tooltip_text = "This model is stored in the separate four-limb model library and never shares weights with drone models."
		selected_group_auto_save_label.visible = false
		_refresh_model_workspace_for_selection(false, true, false)
		if selected_group_root_button != null:
			selected_group_root_button.visible = int(limb_group.get("parent_group_id", -1)) >= 0
		_refresh_tuning_sections(false, true, false)
		suppress_ui_callbacks = true
		worker_count_slider.max_value = float(FourLimbTrainingCoordinator.MAXIMUM_WORKER_COUNT)
		worker_count_slider.value = float(limb_group.get("pending_worker_count", limb_group.get("worker_count", 1)))
		control_rate_slider.value = 1.0 / maxf(float(limb_group.get("control_interval_seconds", FourLimbTrainingCoordinator.DECISION_INTERVAL_SECONDS)), 0.000001)
		var limb_config = limb_trainer.config_values()
		for key in algorithm_config_sliders:
			var limb_slider = algorithm_config_sliders[key] as HSlider
			if limb_slider != null and limb_config.has(key):
				limb_slider.value = float(limb_config[key])
		suppress_ui_callbacks = false
		var limb_editable = not bool(limb_group.get("active", false))
		for control in selected_group_controls:
			control.editable = limb_editable
		_refresh_limb_body_tuning_summary()
		_refresh_limb_body_tuning_controls()
		_refresh_selected_loadout_controls()
		_refresh_loader_identity()
		return
	if ground_contact_terminal_checkbox != null:
		ground_contact_terminal_checkbox.visible = true
	if flipped_terminal_checkbox != null:
		flipped_terminal_checkbox.visible = true
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	if algorithm_controls_id != trainer.algorithm_id():
		_rebuild_algorithm_controls(trainer)
	selected_group_title.text = str(group["name"])
	_refresh_model_workspace_for_selection(true, false, false)
	_refresh_tuning_sections(true, false, false)
	if selected_group_root_button != null:
		selected_group_root_button.visible = int(group.get("parent_group_id", -1)) >= 0
	training_identity_label.text = _training_identity_text(group)
	training_identity_label.tooltip_text = str(group.get("source_description", "Fresh policy")) + "\n\n" + _training_identity_details(group)
	suppress_ui_callbacks = true
	worker_count_slider.max_value = float(trainer.maximum_worker_count())
	worker_count_slider.value = float(group["worker_count"])
	var config = trainer.config_values()
	control_rate_slider.value = 1.0 / maxf(float(config.get("control_interval_seconds", 0.05)), 0.000001)
	if ground_contact_terminal_checkbox != null:
		ground_contact_terminal_checkbox.button_pressed = bool(
			group.get("episode_end_on_ground_contact", false)
		)
	if flipped_terminal_checkbox != null:
		flipped_terminal_checkbox.button_pressed = bool(
			group.get("episode_end_on_flipped", false)
		)
	for key in algorithm_config_sliders:
		var slider = algorithm_config_sliders[key] as HSlider
		if slider != null and config.has(key):
			slider.value = float(config[key])
	suppress_ui_callbacks = false
	var editable = not bool(group["active"])
	for control in selected_group_controls:
		control.editable = editable
	if ground_contact_terminal_checkbox != null:
		ground_contact_terminal_checkbox.disabled = not editable
	if flipped_terminal_checkbox != null:
		flipped_terminal_checkbox.disabled = not editable
	_refresh_selected_loadout_controls()
	_refresh_limb_body_tuning_controls()
	_refresh_group_auto_save_label(group, selected_group_auto_save_label)
	_refresh_loader_identity()


func _refresh_interface() -> void:
	_refresh_group_card_texts()
	_refresh_evaluator_card_texts()
	_refresh_selected_group_status()
	_refresh_episode_status()
	_refresh_action_trace_panel()
	var selected_reward_group = _selected_any_training_group()
	var reward_signature = _reward_card_group_signature(selected_reward_group)
	if reward_signature != reward_card_refresh_signature:
		_rebuild_reward_cards()
	else:
		_refresh_reward_card_values()
	if plots_dirty:
		_refresh_plots()
	_update_target_pad_marker()
	_refresh_target_position_label()
	_refresh_runtime_target_info_label()
	_update_drone_spawn_pad_marker()


func _refresh_selected_group_status() -> void:
	var group = _selected_group()
	var limb_group = _selected_limb_group()
	var turret_group = _selected_turret_group()
	if selected_group_status == null:
		return
	if group.is_empty() and limb_group.is_empty() and turret_group.is_empty():
		if selected_group_auto_save_label != null:
			selected_group_auto_save_label.visible = false
		var active_groups = 0
		for candidate in worker_groups:
			if bool(candidate.get("active", false)):
				active_groups += 1
		for candidate: Dictionary in limb_training.groups:
			if bool(candidate.get("active", false)):
				active_groups += 1
		for candidate: Dictionary in turret_training.groups:
			if bool(candidate.get("active", false)):
				active_groups += 1
		var comparison_status = "%d models · %d training" % [
			worker_groups.size() + limb_training.groups.size() + turret_training.groups.size(),
			active_groups,
		]
		if selected_group_status.text != comparison_status:
			selected_group_status.text = comparison_status
		selected_group_status.add_theme_color_override("font_color", Color("8de1ff"))
		selected_group_status.tooltip_text = "No live group selected\n\nDrone, four-limb, and turret groups share this arena, target, obstacles, combat entity hash, and global pause control. Their model files remain separate."
		if training_identity_label.text != "No group selected.":
			training_identity_label.text = "No group selected."
		return
	if not turret_group.is_empty():
		selected_group_status.text = turret_ui.selected_status_text()
		selected_group_status.add_theme_color_override("font_color", turret_group["color"])
		selected_group_status.tooltip_text = turret_ui.selected_status_tooltip()
		return
	if not limb_group.is_empty():
		var limb_trainer = limb_group["trainer"] as FourLimbPPOTrainer
		var limb_active = bool(limb_group.get("active", false))
		var limb_optimizing = bool(limb_group.get("optimizer_waiting", false))
		var limb_state = (
			"training · optimizing"
			if limb_active and limb_optimizing
			else (
				"training"
				if limb_active
				else ("optimizer finishing" if limb_optimizing else "paused")
			)
		)
		var limb_status = "%s · PPO update %d · episode %d" % [
			limb_state,
			limb_trainer.update_count,
			int(limb_group.get("episode", 0)),
		]
		selected_group_status.text = limb_status
		selected_group_status.add_theme_color_override("font_color", limb_group["color"])
		var metrics: Dictionary = limb_trainer.last_metrics
		selected_group_status.tooltip_text = "Four-limb physical training\n%d workers · %d environment steps · %d completed episodes\nLast mean reward: %+.3f · best mean reward: %s\nRollout samples: %d · actor loss: %+.4f · value loss: %+.4f\nPolicy change RMS: %.7f · reward variation: %.5f\n\nInput audit\n%s" % [
			int(limb_group.get("worker_count", 0)),
			limb_trainer.environment_steps,
			limb_trainer.completed_episodes,
			float(limb_group.get("last_mean_reward", 0.0)),
			(
				String.num(float(limb_group.get("best_mean_reward", 0.0)), 3)
				if is_finite(float(limb_group.get("best_mean_reward", -INF)))
				else "—"
			),
			int(metrics.get("rollout_samples", limb_trainer.rollout.size())),
			float(metrics.get("actor_loss", 0.0)),
			float(metrics.get("value_loss", 0.0)),
			float(metrics.get("policy_parameter_delta_rms", 0.0)),
			float(metrics.get("transition_reward_standard_deviation", 0.0)),
			limb_trainer.diagnostic_status_text(),
		]
		return
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	_refresh_group_auto_save_label(group, selected_group_auto_save_label)
	var group_status = trainer.status_text(bool(group["active"]))
	if selected_group_status.text != group_status:
		selected_group_status.text = group_status
	selected_group_status.add_theme_color_override("font_color", group["color"])
	var metrics = trainer.last_metrics_value()
	var audit_text = trainer.diagnostic_status_text()
	var status_tooltip = "Current activity\nWorkers collect flight experience. During learning, %s studies those decisions.\n\nWhat the algorithm reports\n%s" % [
		trainer.algorithm_short_name(),
		audit_text,
	]
	var action_deviation = float(metrics.get("action_standard_deviation_mean", 0.0))
	if action_deviation > 0.0:
		status_tooltip += "\n\nExploration\nAverage action variation: %s\nVery small values can make the model repeat the same behaviour." % String.num(
			action_deviation,
			3
		)
	if trainer.last_background_update_milliseconds() > 0.0:
		status_tooltip += "\n\nLearning speed\nLast %s learning step: %s ms\nLearning runs in the background so the visible simulation stays responsive." % [
			trainer.algorithm_short_name(),
			String.num(trainer.last_background_update_milliseconds(), 1),
		]
	status_tooltip += "\n\nDisplay performance\nWorst recent frame: %s ms\nFrames slower than %s ms: %d" % [
		String.num(recent_worst_frame_ms, 1),
		String.num(FRAME_HITCH_THRESHOLD_MS, 0),
		recent_frame_hitches,
	]
	var wall_hash_state = wall_spatial_hash.debug_state()
	var wall_hash_queries = int(wall_hash_state.get("query_count", 0))
	var wall_hash_cache_hits = int(wall_hash_state.get("query_cache_hits", 0))
	status_tooltip += "\n\nWall sensing\n%d obstacles are tracked. A typical ray checks about %s nearby shapes and performs %s detailed checks. Cached answers reused: %s%%." % [
		int(wall_hash_state.get("wall_count", 0)),
		String.num(float(wall_hash_state.get("candidate_count", 0)) / float(maxi(wall_hash_queries, 1)), 1),
		String.num(float(wall_hash_state.get("exact_test_count", 0)) / float(maxi(wall_hash_queries, 1)), 1),
		String.num(100.0 * float(wall_hash_cache_hits) / float(maxi(wall_hash_queries, 1)), 0),
	]
	if selected_group_status.tooltip_text != status_tooltip:
		selected_group_status.tooltip_text = status_tooltip
	var training_identity = _training_identity_text(group)
	if training_identity_label.text != training_identity:
		training_identity_label.text = training_identity


func _refresh_episode_status() -> void:
	if episode_status_label == null:
		return
	var limb_summaries: Array[Dictionary] = limb_training.episode_progress_summaries()
	var turret_summaries: Array[Dictionary] = turret_training.episode_progress_summaries()
	var active_elapsed_values: Array[float] = []
	var active_duration_values: Array[float] = []
	var active_drone_groups: int = 0
	var paused_drone_groups: int = 0
	for group: Dictionary in worker_groups:
		if bool(group.get("active", false)):
			active_drone_groups += 1
		else:
			paused_drone_groups += 1
	var active_limb_groups: int = 0
	var paused_limb_groups: int = 0
	var active_limb_instances: int = 0
	var retained_limb_instances: int = 0
	for summary: Dictionary in limb_summaries:
		retained_limb_instances += int(summary.get("instance_count", 0))
		if bool(summary.get("active", false)):
			active_limb_groups += 1
			active_limb_instances += int(summary.get("instance_count", 0))
			if int(summary.get("unfinished_instance_count", 0)) > 0:
				active_elapsed_values.append(maxf(float(summary.get("elapsed", 0.0)), 0.0))
				active_duration_values.append(maxf(float(summary.get("duration", episode_duration)), 0.0))
		else:
			paused_limb_groups += 1
	var active_turret_groups: int = 0
	var paused_turret_groups: int = 0
	var active_turret_instances: int = 0
	var retained_turret_instances: int = 0
	for summary: Dictionary in turret_summaries:
		retained_turret_instances += int(summary.get("instance_count", 0))
		if bool(summary.get("active", false)):
			active_turret_groups += 1
			active_turret_instances += int(summary.get("instance_count", 0))
			if int(summary.get("unfinished_instance_count", 0)) > 0:
				active_elapsed_values.append(maxf(float(summary.get("elapsed", 0.0)), 0.0))
				active_duration_values.append(maxf(float(summary.get("duration", episode_duration)), 0.0))
		else:
			paused_turret_groups += 1
	var active_drone_instances: int = 0
	var retained_drone_instances: int = 0
	for trial: Dictionary in trials:
		if str(trial.get("mode", "evaluation")) != "algorithm_training":
			continue
		retained_drone_instances += 1
		if _trial_runtime_is_active(trial):
			active_drone_instances += 1
			var trial_episode: DroneTrainingEpisode = trial.get("episode") as DroneTrainingEpisode
			if trial_episode != null:
				active_elapsed_values.append(maxf(trial_episode.elapsed_seconds, 0.0))
				active_duration_values.append(maxf(trial_episode.duration_seconds, 0.0))
	var active_models: int = active_drone_groups + active_limb_groups + active_turret_groups
	var paused_models: int = paused_drone_groups + paused_limb_groups + paused_turret_groups
	var active_instances: int = active_drone_instances + active_limb_instances + active_turret_instances
	var retained_instances: int = (
		retained_drone_instances + retained_limb_instances + retained_turret_instances
	)
	if worker_groups.is_empty() and limb_summaries.is_empty() and turret_summaries.is_empty():
		episode_status_label.text = "Episode length %.1f s · no worker groups · %s simulation" % [
			episode_duration,
			_simulation_speed_text(simulation_speed),
		]
		return
	var live_progress_text: String = ""
	if not active_elapsed_values.is_empty():
		var minimum_elapsed: float = active_elapsed_values[0]
		var maximum_elapsed: float = active_elapsed_values[0]
		var maximum_duration: float = episode_duration
		for elapsed_value: float in active_elapsed_values:
			minimum_elapsed = minf(minimum_elapsed, elapsed_value)
			maximum_elapsed = maxf(maximum_elapsed, elapsed_value)
		for duration_value: float in active_duration_values:
			maximum_duration = maxf(maximum_duration, duration_value)
		if absf(maximum_elapsed - minimum_elapsed) < 0.11:
			live_progress_text = " · live %.1f / %.1f s" % [maximum_elapsed, maximum_duration]
		else:
			live_progress_text = " · live %.1f–%.1f / %.1f s" % [
				minimum_elapsed, maximum_elapsed, maximum_duration,
			]
	var episode_status: String = "Episode length %.1f s%s · %d active model%s · %d active instance%s" % [
		episode_duration,
		live_progress_text,
		active_models,
		"" if active_models == 1 else "s",
		active_instances,
		"" if active_instances == 1 else "s",
	]
	if paused_models > 0:
		episode_status += " · %d paused model%s" % [
			paused_models,
			"" if paused_models == 1 else "s",
		]
	if retained_instances > active_instances:
		episode_status += " · %d retained instance%s" % [
			retained_instances - active_instances,
			"" if retained_instances - active_instances == 1 else "s",
		]
	episode_status += " · %s simulation" % _simulation_speed_text(simulation_speed)
	if episode_status_label.text != episode_status:
		episode_status_label.text = episode_status


func _reset_action_trace_for_episode() -> void:
	var descriptors_by_group: Dictionary = {}
	for trial in trials:
		if str(trial.get("mode", "evaluation")) != "algorithm_training":
			continue
		var group_id = int(trial.get("group_id", -1))
		if group_id < 0:
			continue
		if not descriptors_by_group.has(group_id):
			descriptors_by_group[group_id] = []
		(descriptors_by_group[group_id] as Array).append({
			"instance_id": int(trial.get("instance_id", -1)),
			"worker_index": int(trial.get(
				"worker_index",
				trial.get("sensor_phase_index", -1)
			)),
		})
	for group in worker_groups:
		if not bool(group.get("active", false)):
			continue
		var group_id = int(group.get("group_id", -1))
		action_trace_buffer.begin_source_episode(
			_action_trace_source_id("drone", group_id),
			group_id,
			episode_number,
			_drone_action_names(group),
			0.0,
			1.0,
			descriptors_by_group.get(group_id, [])
		)
	_refresh_action_trace_panel()


func _record_action_trace_sample(
	group: Dictionary,
	trial: Dictionary,
	drone: ServerDrone,
	sample: Dictionary
) -> void:
	var commands = PackedFloat64Array()
	var sample_commands: Variant = sample.get("commands", PackedFloat64Array())
	if sample_commands is PackedFloat64Array:
		commands = (sample_commands as PackedFloat64Array).duplicate()
	elif sample_commands is Array:
		commands = PackedFloat64Array(sample_commands)
	var expected_action_count = _drone_action_names(group).size()
	if commands.size() != expected_action_count and is_instance_valid(drone):
		var body_contract_value: Variant = group.get("body_interface", {})
		var body_contract: Dictionary = (
			body_contract_value as Dictionary if body_contract_value is Dictionary else {}
		)
		commands = DroneTrainingActionCodec.policy_unit_commands_from_action(
			body_contract,
			sample.get("action", {})
		)
	var group_id = int(group.get("group_id", -1))
	var source_id = _action_trace_source_id("drone", group_id)
	var worker_episode_number: int = _trial_episode_number(trial)
	var config: Dictionary = action_trace_buffer.source_config(source_id)
	if int(config.get("episode_number", -1)) != worker_episode_number:
		action_trace_buffer.begin_source_episode(
			source_id,
			group_id,
			worker_episode_number,
			_drone_action_names(group),
			0.0,
			1.0
		)
	action_trace_buffer.append_source_commands(
		source_id,
		int(trial.get("instance_id", -1)),
		int(trial.get("worker_index", trial.get("sensor_phase_index", -1))),
		_trial_episode_elapsed(trial),
		commands
	)


func _refresh_action_trace_panel() -> void:
	if action_trace_panel == null or plots_page == null or not plots_page.visible:
		return
	var group_rows: Array[Dictionary] = []
	_append_drone_action_trace_rows(group_rows)
	_append_limb_action_trace_rows(group_rows)
	_append_turret_action_trace_rows(group_rows)
	action_trace_panel.call("refresh", group_rows)


func _append_drone_action_trace_rows(group_rows: Array[Dictionary]) -> void:
	var trial_by_instance: Dictionary = {}
	for trial in trials:
		if str(trial.get("mode", "evaluation")) != "algorithm_training":
			continue
		trial_by_instance[int(trial.get("instance_id", -1))] = trial
	for group in worker_groups:
		var action_names = _drone_action_names(group)
		var group_id = int(group.get("group_id", -1))
		var source_id = _action_trace_source_id("drone", group_id)
		var trainer = group.get("trainer") as DroneTrainingAlgorithm
		var workers: Array[Dictionary] = []
		var records = action_trace_buffer.records_for_source(source_id)
		var instance_ids: Array = records.keys()
		instance_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
			var first_record: Dictionary = records.get(first, {})
			var second_record: Dictionary = records.get(second, {})
			return int(first_record.get("worker_index", 0)) < int(second_record.get("worker_index", 0))
		)
		for instance_id_value in instance_ids:
			var instance_id = int(instance_id_value)
			var record: Dictionary = records.get(instance_id, {})
			var trial: Dictionary = trial_by_instance.get(instance_id, {})
			var status = "paused"
			if not trial.is_empty():
				status = "finished" if bool(trial.get("episode_finished", false)) else "live"
			var live_drone: ServerDrone = trial.get("drone") as ServerDrone
			workers.append({
				"source_id": source_id,
				"group_name": str(group.get("name", "Worker group")),
				"worker_kind_label": "Drone",
				"instance_id": instance_id,
				"worker_index": int(record.get("worker_index", -1)),
				"episode_number": episode_number,
				"elapsed_seconds": episode_elapsed,
				"status": status,
				"action_names": action_names,
				"action_minimum": 0.0,
				"action_maximum": 1.0,
				"runtime_actuator_status": _drone_realized_actuator_status(live_drone),
				"record": record,
			})
		group_rows.append({
			"source_id": source_id,
			"group_id": group_id,
			"name": str(group.get("name", "Worker group")),
			"worker_kind": "drone",
			"worker_kind_label": "DRONE",
			"algorithm": trainer.algorithm_short_name() if trainer != null else "",
			"active": bool(group.get("active", false)),
			"episode_number": episode_number,
			"color": group.get("color", Color("8de1ff")),
			"action_names": action_names,
			"action_minimum": 0.0,
			"action_maximum": 1.0,
			"workers": workers,
		})


func _append_limb_action_trace_rows(group_rows: Array[Dictionary]) -> void:
	for group: Dictionary in limb_training.groups:
		var action_names = _four_limb_action_names(group)
		var group_id = int(group.get("group_id", -1))
		var source_id = _action_trace_source_id("four_limb", group_id)
		var workers: Array[Dictionary] = []
		for worker_value in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker: Dictionary = worker_value
			var body = worker.get("body") as FourLimbPhysicalBody3D
			if not is_instance_valid(body):
				continue
			var instance_id = int(body.get_instance_id())
			var status = "live"
			if bool(worker.get("finished", false)):
				status = "finished"
			elif not bool(group.get("active", false)):
				status = "paused"
			elif float(worker.get("settle_remaining", 0.0)) > 0.0:
				status = "settling"
			workers.append({
				"source_id": source_id,
				"group_name": str(group.get("name", "Limb worker group")),
				"worker_kind_label": "Limb",
				"instance_id": instance_id,
				"worker_index": int(worker.get("id", -1)),
				"episode_number": int(group.get("episode", -1)),
				"elapsed_seconds": float(worker.get("episode_elapsed", 0.0)),
				"status": status,
				"action_names": action_names,
				"action_minimum": -1.0,
				"action_maximum": 1.0,
				"record": action_trace_buffer.record_for_source(source_id, instance_id),
			})
		group_rows.append({
			"source_id": source_id,
			"group_id": group_id,
			"name": str(group.get("name", "Limb worker group")),
			"worker_kind": "four_limb",
			"worker_kind_label": "FOUR-LIMB",
			"algorithm": "PPO",
			"active": bool(group.get("active", false)),
			"episode_number": int(group.get("episode", -1)),
			"color": group.get("color", Color("8de1ff")),
			"action_names": action_names,
			"action_minimum": -1.0,
			"action_maximum": 1.0,
			"workers": workers,
		})


func _append_turret_action_trace_rows(group_rows: Array[Dictionary]) -> void:
	var action_names = _turret_action_names()
	for group: Dictionary in turret_training.groups:
		var group_id = int(group.get("group_id", -1))
		var source_id = _action_trace_source_id("turret", group_id)
		var workers: Array[Dictionary] = []
		for worker_value in group.get("workers", []):
			if not (worker_value is Dictionary):
				continue
			var worker: Dictionary = worker_value
			var turret = worker.get("turret") as TurretPhysicalBody3D
			if not is_instance_valid(turret):
				continue
			var instance_id = int(turret.get_instance_id())
			var status = "live"
			if bool(worker.get("finished", false)):
				status = "finished"
			elif not bool(group.get("active", false)):
				status = "paused"
			elif bool(group.get("manual_override_enabled", false)) and int(worker.get("id", -1)) == 0:
				status = "manual"
			workers.append({
				"source_id": source_id,
				"group_name": str(group.get("name", "Turret worker group")),
				"worker_kind_label": "Turret",
				"instance_id": instance_id,
				"worker_index": int(worker.get("id", -1)),
				"episode_number": int(group.get("episode", -1)),
				"elapsed_seconds": float(worker.get("episode_elapsed", 0.0)),
				"status": status,
				"action_names": action_names,
				"action_minimum": -1.0,
				"action_maximum": 1.0,
				"record": action_trace_buffer.record_for_source(source_id, instance_id),
			})
		group_rows.append({
			"source_id": source_id,
			"group_id": group_id,
			"name": str(group.get("name", "Turret worker group")),
			"worker_kind": "turret",
			"worker_kind_label": "TURRET",
			"algorithm": "PPO",
			"active": bool(group.get("active", false)),
			"episode_number": int(group.get("episode", -1)),
			"color": group.get("color", Color("8de1ff")),
			"action_names": action_names,
			"action_minimum": -1.0,
			"action_maximum": 1.0,
			"workers": workers,
		})


func _drone_group_plot_series(
	group: Dictionary,
	plot_id: String
) -> Array[Dictionary]:
	# Keep the room-level test/debug seam stable while the implementation lives in the pure builder.
	return DroneTrainingPlotSeriesBuilder.drone_group_series(group, plot_id)


func _refresh_plots() -> void:
	if plots_page != null and not plots_page.visible:
		plots_dirty = true
		return
	var group = _selected_group()
	var limb_group = _selected_limb_group()
	var turret_group = _selected_turret_group()
	for plot_id in plot_widgets:
		if bool(closed_plots.get(plot_id, false)):
			continue
		if not expanded_plot_id.is_empty() and expanded_plot_id != plot_id:
			continue
		var plot = plot_widgets[plot_id] as Control
		var definitions = (
			DroneTrainingPlotSeriesBuilder.ALL_PLOT_DEFINITIONS
			if group.is_empty() and limb_group.is_empty() and turret_group.is_empty()
			else DroneTrainingPlotSeriesBuilder.GROUP_PLOT_DEFINITIONS
		)
		var definition: Dictionary = definitions.get(plot_id, {})
		var title = plot_title_labels.get(plot_id) as Label
		var card = plot_cards.get(plot_id) as Control
		if title != null:
			title.text = str(definition.get("title", plot_id))
		if card != null:
			card.tooltip_text = _readable_tooltip(str(definition.get("tooltip", "")))
		plot.tooltip_text = "%s\n\nChart controls\nClick to expand. Use the wheel to zoom, middle-drag to move, and right-click to reset.\nUse CUT to remove older history from the visible timeline." % _readable_tooltip(str(
			definition.get("tooltip", "")
		))
		plot.call(
			"set_axis_labels",
			str(definition.get("x_axis", "step")),
			str(definition.get("y_axis", "value"))
		)
		plot.call(
			"set_empty_message",
			(
				"Save at least two Best checkpoints to compare their improvement."
				if plot_id == "checkpoints"
				else "No completed data yet — let the models finish an episode or optimizer update."
			)
		)
		var context_id = _all_plot_context_id(plot_id)
		if group.is_empty() and limb_group.is_empty() and turret_group.is_empty():
			plot.call("set_display_context", context_id)
			plot.call("set_series", DroneTrainingPlotSeriesBuilder.all_group_series(
				plot_id,
				worker_groups,
				limb_training.groups,
				turret_training.groups,
				model_versions
			))
		elif not turret_group.is_empty():
			var turret_source_id = "turret:%d" % int(turret_group.get("group_id", -1))
			plot.call("set_display_context", "%s:%s" % [turret_source_id, plot_id])
			plot.call("set_series", DroneTrainingPlotSeriesBuilder.tag_series(
				DroneTrainingPlotSeriesBuilder.turret_group_series(turret_group, plot_id),
				turret_source_id,
				"turret"
			))
		elif not limb_group.is_empty():
			var limb_source_id = "limb:%d" % int(limb_group.get("group_id", -1))
			plot.call("set_display_context", "%s:%s" % [limb_source_id, plot_id])
			plot.call("set_series", DroneTrainingPlotSeriesBuilder.tag_series(
				DroneTrainingPlotSeriesBuilder.limb_group_series(limb_group, plot_id),
				limb_source_id,
				"limb"
			))
		elif plot_id == "checkpoints":
			plot.call(
				"set_display_context",
				"drone:%d:checkpoints" % int(group.get("group_id", -1))
			)
			plot.call("set_series", DroneTrainingPlotSeriesBuilder.checkpoint_improvement_series(
				model_versions,
				str(group.get("model_family_name", ""))
			))
		else:
			var drone_source_id = "drone:%d" % int(group.get("group_id", -1))
			plot.call("set_display_context", "%s:%s" % [drone_source_id, plot_id])
			plot.call("set_series", DroneTrainingPlotSeriesBuilder.tag_series(
				DroneTrainingPlotSeriesBuilder.drone_group_series(group, plot_id),
				drone_source_id,
				"drone"
			))
	plots_dirty = false


func _restore_plots() -> void:
	closed_plots.clear()
	if not expanded_plot_id.is_empty():
		_toggle_plot_expanded(expanded_plot_id)
	for card in plot_cards.values():
		(card as Control).visible = true
	plots_dirty = true
	_refresh_plots()


func _toggle_plot_expanded(plot_id: String) -> void:
	if not plot_widgets.has(plot_id):
		return
	var should_expand = expanded_plot_id != plot_id
	expanded_plot_id = plot_id if should_expand else ""
	for candidate_id in plot_cards:
		var card = plot_cards[candidate_id] as Control
		var plot = plot_widgets[candidate_id] as Control
		var button = plot_expand_buttons.get(candidate_id) as Button
		var is_expanded = should_expand and candidate_id == plot_id
		card.visible = (
			is_expanded
			if should_expand
			else not bool(closed_plots.get(candidate_id, false))
		)
		plot.call("set_detailed", is_expanded)
		if button != null:
			button.text = "COLLAPSE" if is_expanded else "EXPAND"
		if is_expanded:
			call_deferred("_animate_box_open", card)
	_layout_interface()
	plots_dirty = true
	_refresh_plots()


func _all_plot_context_id(plot_id: String) -> String:
	var source_ids: Array[String] = []
	for group in worker_groups:
		source_ids.append("d%d" % int(group.get("group_id", -1)))
	for limb_group: Dictionary in limb_training.groups:
		source_ids.append("l%d" % int(limb_group.get("group_id", -1)))
	for turret_group: Dictionary in turret_training.groups:
		source_ids.append("t%d" % int(turret_group.get("group_id", -1)))
	source_ids.sort()
	return "all:%s:%s" % [plot_id, ",".join(source_ids)]


func _apply_selection_highlight() -> void:
	for trial in trials:
		var drone = trial.get("drone") as ServerDrone
		var instance_id = int(trial.get("instance_id", -1))
		var highlighted = false
		if selected_evaluator_instance_id >= 0:
			highlighted = instance_id == selected_evaluator_instance_id
		elif selected_group_id >= 0:
			highlighted = (
				int(trial.get("group_id", -1)) == selected_group_id
				and str(trial.get("mode", "evaluation")) == "algorithm_training"
			)
		elif selected_limb_group_id >= 0 or selected_turret_group_id >= 0:
			highlighted = false
		else:
			highlighted = true
		DroneTrainingRoomPresentation.set_drone_highlight(drone, highlighted)


func _refresh_model_versions(preferred_version_id = "") -> void:
	model_versions = model_registry.list_versions()
	if model_version_list == null:
		return
	var available_ids: Dictionary = {}
	for version in model_versions:
		available_ids[str(version.get("version_id", ""))] = true
	for version_id in model_batch_selected_ids.keys():
		if not available_ids.has(str(version_id)):
			model_batch_selected_ids.erase(version_id)
	var requested_id = str(preferred_version_id)
	if requested_id.is_empty():
		requested_id = selected_model_version_id
	model_list_refreshing = true
	model_version_list.clear()
	var root = model_version_list.create_item()
	var selected_item: TreeItem = null
	for version in model_versions:
		var item = model_version_list.create_item(root)
		var version_id = str(version.get("version_id", ""))
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, bool(model_batch_selected_ids.get(version_id, false)))
		item.set_tooltip_text(0, "Select for deletion\n\nChecks this exact saved version.\nNothing is deleted until you confirm Delete Selected.")
		item.set_metadata(0, version_id)
		item.set_text(1, model_registry.display_name(version))
		item.set_tooltip_text(1, model_registry.tooltip_for_version(version))
		item.set_metadata(1, version_id)
		item.set_text(2, _model_library_time_text(version, "created_utc", "Unknown"))
		item.set_tooltip_text(2, "Created at\n\nThe time this saved model version was first written.")
		item.set_text(3, _model_training_updated_text(version))
		item.set_tooltip_text(3, "Training updated\n\nThe latest time training data was written into this version.\nRolling saves may update this without creating another version.")
		item.set_text(4, _model_library_time_text(version, "last_used_utc", "Never"))
		item.set_tooltip_text(4, "Last used\n\nThe latest time this model was loaded for training or spawned as an evaluator.")
		for metadata_column in range(2, 5):
			item.set_metadata(metadata_column, version_id)
		if version_id == requested_id:
			selected_item = item
	if selected_item == null and root.get_first_child() != null:
		selected_item = root.get_first_child()
	if selected_item != null:
		selected_model_version_id = str(selected_item.get_metadata(1))
		selected_item.select(1)
	else:
		selected_model_version_id = ""
	model_list_refreshing = false
	_update_model_batch_delete_controls()
	_refresh_loader_identity()
	_refresh_plots()
	_refresh_group_card_texts()


func _model_library_time_text(
	version: Dictionary,
	key: String,
	fallback: String
) -> String:
	var value = str(version.get(key, "")).strip_edges()
	if value.is_empty():
		return fallback
	return value.replace("T", " ").trim_suffix("Z")


func _model_training_updated_text(version: Dictionary) -> String:
	var value = str(version.get("training_updated_utc", "")).strip_edges()
	if value.is_empty() and DroneTrainingAlgorithmCatalog.is_training_checkpoint(version):
		value = str(version.get("created_utc", "")).strip_edges()
	if value.is_empty():
		return "Not trained"
	return value.replace("T", " ").trim_suffix("Z")


func _selected_model_record() -> Dictionary:
	if selected_model_version_id.is_empty():
		return {}
	for version in model_versions:
		if str(version.get("version_id", "")) == selected_model_version_id:
			return version
	return {}


func _on_model_version_cell_selected() -> void:
	if model_list_refreshing or model_version_list == null:
		return
	var item = model_version_list.get_selected()
	if item == null:
		return
	var column = model_version_list.get_selected_column()
	var version_id = str(item.get_metadata(column))
	if version_id.is_empty():
		version_id = str(item.get_metadata(1))
	selected_model_version_id = version_id
	_refresh_loader_identity()
	_refresh_plots()


func _on_model_version_item_edited() -> void:
	if model_list_refreshing or model_version_list == null:
		return
	if model_version_list.get_edited_column() != 0:
		return
	var item = model_version_list.get_edited()
	if item == null:
		return
	var version_id = str(item.get_metadata(0))
	if version_id.is_empty():
		return
	if item.is_checked(0):
		model_batch_selected_ids[version_id] = true
	else:
		model_batch_selected_ids.erase(version_id)
	selected_model_version_id = version_id
	model_list_refreshing = true
	item.select(1)
	model_list_refreshing = false
	_update_model_batch_delete_controls()
	_refresh_loader_identity()
	_refresh_plots()


func _set_all_model_batch_selection(selected: bool) -> void:
	model_batch_selected_ids.clear()
	if selected:
		for version in model_versions:
			var version_id = str(version.get("version_id", ""))
			if not version_id.is_empty():
				model_batch_selected_ids[version_id] = true
	_refresh_model_versions(selected_model_version_id)


func _batch_selected_model_ids() -> Array[String]:
	var result: Array[String] = []
	for version in model_versions:
		var version_id = str(version.get("version_id", ""))
		if bool(model_batch_selected_ids.get(version_id, false)):
			result.append(version_id)
	return result


func _update_model_batch_delete_controls() -> void:
	var selected_count = _batch_selected_model_ids().size()
	if model_batch_selection_label != null:
		model_batch_selection_label.text = "%d selected" % selected_count
	if delete_model_button != null:
		delete_model_button.text = "DELETE SELECTED (%d)" % selected_count
		delete_model_button.disabled = selected_count == 0


func _training_identity_text(group: Dictionary) -> String:
	if group.is_empty():
		return "No training group selected."
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	return "Using now: %s\n%s · live update %d · %s" % [
		_group_model_summary(group),
		trainer.algorithm_display_name(),
		trainer.update_count_value(),
		"training" if bool(group.get("active", false)) else "paused",
	]


func _training_identity_details(group: Dictionary) -> String:
	if group.is_empty():
		return "No training group selected."
	var trainer: DroneTrainingAlgorithm = group["trainer"]
	var source_id = str(group.get("source_version_id", ""))
	var source_line = str(group.get(
		"source_description",
		"Started with fresh random %s weights in this session" % trainer.algorithm_short_name()
	))
	if source_id.is_empty():
		source_line += ". No saved model was loaded automatically."
	else:
		source_line += "\nSaved source: %s" % source_id
	var save_line = "The exact live weights have not been saved yet."
	var saved_id = str(group.get("last_exact_saved_version_id", ""))
	var saved_update = int(group.get("last_exact_saved_update", -1))
	if not saved_id.is_empty() and saved_update >= 0:
		var updates_since_save = maxi(
			trainer.update_count_value() - saved_update,
			0
		)
		if updates_since_save == 0:
			save_line = "The live weights exactly match saved model %s." % saved_id
		else:
			save_line = "The live model has learned for %d more updates since %s was saved." % [
				updates_since_save,
				saved_id,
			]
	return "Group\n%s\n\nStarting point\n%s\n\nSave status\n%s" % [
		str(group["name"]),
		source_line,
		save_line,
	]


func _refresh_loader_identity() -> void:
	if loader_identity_label == null:
		return
	var version = _selected_model_record()
	var group = _selected_group()
	if model_browser_context_label != null:
		if model_browser_branch_source_mode:
			model_browser_context_label.text = "Choose a trainable checkpoint to insert directly as the new worker group's starting policy."
		else:
			model_browser_context_label.text = (
				"Target group: %s · %s. Inspecting a model is safe; loading requires this group to be paused." % [
					group["name"],
					"training" if bool(group.get("active", false)) else "paused",
				]
				if not group.is_empty()
				else "Inspection mode only. Select a worker group before loading a model."
			)
	if model_browser_pause_button != null:
		model_browser_pause_button.visible = (
			not model_browser_branch_source_mode and not group.is_empty()
		)
		if not group.is_empty():
			model_browser_pause_button.text = (
				"PAUSE GROUP" if bool(group.get("active", false)) else "RESUME GROUP"
			)
	if load_model_button != null:
		load_model_button.text = (
			"USE FOR NEW GROUP"
			if model_browser_branch_source_mode
			else "LOAD INTO GROUP"
		)
		load_model_button.tooltip_text = (
			"Use as new-group source\n\nReturns to group creation with this checkpoint selected as the starting model."
			if model_browser_branch_source_mode
			else "Load into paused group\n\nReplaces the target group's live weights with this checkpoint. The group's reward switches stay unchanged."
		)
	if version.is_empty():
		loader_identity_label.text = "No saved model selected."
		loader_identity_label.tooltip_text = "No model selected\n\nClick a saved version to inspect it and enable the available actions."
		if load_model_button != null:
			load_model_button.disabled = true
		if spawn_evaluator_button != null:
			spawn_evaluator_button.disabled = true
		_update_model_batch_delete_controls()
		return
	var artifact_is_training_checkpoint = DroneTrainingAlgorithmCatalog.is_training_checkpoint(
		version
	)
	var inspection = model_registry.inspect_version(version)
	var compatible = bool(inspection.get("compatible", false))
	var trainable = bool(inspection.get("trainable", false))
	var runtime_contract: Dictionary = inspection.get("runtime_contract", {})
	var training_environment: Dictionary = inspection.get("training_environment", {})
	var reward_components_value: Variant = training_environment.get("reward_components", {})
	var reward_components: Dictionary = (
		(reward_components_value as Dictionary).duplicate(true)
		if reward_components_value is Dictionary
		else {}
	)
	var saved_reward_schema: int = RLTrainingMath.finite_int_or(
		training_environment.get("reward_schema_version", 1), 1
	)
	var reward_schema_matches = (
		not artifact_is_training_checkpoint
		or saved_reward_schema == DroneTrainingReward.SCHEMA_VERSION
	)
	var artifact_text = (
		"%s // %s checkpoint" % [
			str(version.get("training_algorithm_name", "Clipped PPO + GAE")),
			str(version.get("checkpoint_kind", "saved")).replace("_", " "),
		]
		if artifact_is_training_checkpoint
		else "Hand-written diagnostic baseline"
	)
	var relation = "This inspected save is not controlling any selected training group."
	if not group.is_empty():
		var version_id = str(version.get("version_id", ""))
		if version_id == str(group.get("source_version_id", "")):
			relation = "This checkpoint is the recorded source of the selected group; that group's live weights may now be newer."
		elif version_id == str(group.get("last_exact_saved_version_id", "")):
			relation = "This is the most recent checkpoint that exactly matched the selected group's live policy when saved."
	var score_text = "No exact checkpoint score recorded."
	if not reward_schema_matches:
		score_text = "Stored score uses legacy reward v%d and is not comparable with current reward v%d. The policy weights remain loadable; continuing training resets only its reward-score baseline." % [
			saved_reward_schema,
			DroneTrainingReward.SCHEMA_VERSION,
		]
	elif RLTrainingMath.bool_or(version.get("score_matches_checkpoint", false), false):
		score_text = "Exact selection score: %+.3f reward/s · best worker %+.3f · group mean %+.3f" % [
			RLTrainingMath.finite_float_or(version.get("best_candidate_score", 0.0), 0.0),
			RLTrainingMath.finite_float_or(version.get("best_candidate_worker_reward", 0.0), 0.0),
			RLTrainingMath.finite_float_or(version.get("best_candidate_group_mean_reward", 0.0), 0.0),
		]
	elif RLTrainingMath.bool_or(version.get("has_best_episode", false), false):
		score_text = "Historical best exists, but it belongs to different weights."
	var runtime_text = "Runtime: evaluator-only legacy controller"
	if artifact_is_training_checkpoint:
		runtime_text = "%s\nRuntime: %s · observation v%d (%d actor / %d critic inputs) · %d motor outputs · %s Hz control" % [
			str(inspection.get("compatibility_text", "Compatibility unknown.")),
			str(runtime_contract.get("runtime_model_class", "DronePPOModel")),
			RLTrainingMath.finite_int_or(runtime_contract.get("observation_schema_version", 0), 0),
			RLTrainingMath.finite_int_or(runtime_contract.get("actor_feature_count", 0), 0),
			RLTrainingMath.finite_int_or(runtime_contract.get("critic_feature_count", 0), 0),
			RLTrainingMath.finite_int_or(runtime_contract.get("action_count", 0), 0),
			String.num(
				1.0 / maxf(
					RLTrainingMath.finite_float_or(
						runtime_contract.get("control_interval_seconds", 0.05),
						0.05
					),
					0.000001
				),
				1
			),
		]
	var reward_text = (
		_reward_summary(reward_components)
		if not reward_components.is_empty()
		else "Not recorded in this older save"
	)
	var hardware_text = "Not recorded in this older save"
	var inspected_loadout_value: Variant = training_environment.get("drone_loadout", {})
	var saved_loadout_record: Dictionary = (
		(inspected_loadout_value as Dictionary).duplicate(true)
		if inspected_loadout_value is Dictionary
		else {}
	)
	if not saved_loadout_record.is_empty():
		hardware_text = _compact_loadout_text(
			LOADOUT_CONFIG.from_record(saved_loadout_record)
		)
	loader_identity_label.text = "%s\n%s · update %d · %d environment steps · %d completed episodes\nCreated %s · training updated %s · last used %s\nParent %s\n%s\n%s\nTraining rewards: %s\nDrone hardware: %s\n\n%s" % [
		model_registry.display_name(version),
		artifact_text,
		RLTrainingMath.finite_int_or(version.get("training_update", 0), 0),
		RLTrainingMath.finite_int_or(version.get("environment_steps", 0), 0),
		RLTrainingMath.finite_int_or(version.get("completed_episodes", 0), 0),
		_model_library_time_text(version, "created_utc", "unknown"),
		_model_training_updated_text(version),
		_model_library_time_text(version, "last_used_utc", "never"),
		str(version.get("parent_version_id", "none")) if not str(version.get("parent_version_id", "")).is_empty() else "none",
		score_text,
		runtime_text,
		reward_text,
		hardware_text,
		relation,
	]
	loader_identity_label.tooltip_text = "Selected saved model\n\nThe details belong to the highlighted saved model.\nNothing changes until you press a load, use, or spawn button."
	loader_identity_label.add_theme_color_override(
		"font_color",
		Color("8de1ff")
		if compatible or not artifact_is_training_checkpoint
		else Color("ffad42")
	)
	if load_model_button != null:
		var group_algorithm_matches = (
			not group.is_empty()
			and str(group.get("algorithm_id", "")) == str(version.get(
				"training_algorithm_id",
				DroneTrainingAlgorithmCatalog.DEFAULT_ALGORITHM_ID
			))
		)
		load_model_button.disabled = (
			not artifact_is_training_checkpoint
			or not trainable
			or (
				not model_browser_branch_source_mode
				and (
					group.is_empty()
					or bool(group.get("active", false))
					or not group_algorithm_matches
				)
			)
		)
	if spawn_evaluator_button != null:
		spawn_evaluator_button.disabled = artifact_is_training_checkpoint and not compatible
	_update_model_batch_delete_controls()


func _selected_group() -> Dictionary:
	return _group_by_id(selected_group_id)


func _selected_limb_group() -> Dictionary:
	return limb_training.group_by_id(selected_limb_group_id)


func _selected_turret_group() -> Dictionary:
	return turret_training.group_by_id(selected_turret_group_id)


static func _new_drone_combat_adapter(
	drone: ServerDrone,
	group_id: int = -1,
	worker_id: int = -1
) -> DroneTrainingCombatantAdapter:
	if not is_instance_valid(drone):
		return null
	return DroneTrainingCombatantAdapter.new(
		drone,
		int(drone.get_instance_id()),
		group_id,
		worker_id,
		1
	)


func _register_trial_combatant(trial: Dictionary) -> void:
	var adapter = trial.get("combat_adapter") as TrainingCombatantAdapter
	if adapter == null or not adapter.is_alive():
		return
	training_entity_spatial_hash.register_entity(
		adapter.spatial_key(),
		adapter.body,
		adapter.entity_kind,
		adapter.entity_id,
		adapter.metadata()
	)


func _unregister_trial_combatant(trial: Dictionary) -> void:
	var adapter = trial.get("combat_adapter") as TrainingCombatantAdapter
	if adapter != null:
		training_entity_spatial_hash.clear_query_cache(
			TrainingTurretThreatSensor.cache_id_for(adapter)
		)
		training_entity_spatial_hash.unregister_entity(adapter.spatial_key())


func _turret_threat_for_trial(trial: Dictionary) -> Dictionary:
	if not training_entity_spatial_hash.has_kind(TrainingTurretThreatSensor.TURRET_KIND):
		var existing: Dictionary = trial.get("turret_threat_probe", {})
		return existing if not existing.is_empty() else TrainingTurretThreatSensor.empty_probe()
	var adapter = trial.get("combat_adapter") as TrainingCombatantAdapter
	return TrainingTurretThreatSensor.acquire(
		adapter, training_entity_spatial_hash, wall_spatial_hash
	)


func _selected_any_training_group() -> Dictionary:
	var drone_group = _selected_group()
	if not drone_group.is_empty():
		return drone_group
	var limb_group = _selected_limb_group()
	if not limb_group.is_empty():
		return limb_group
	return _selected_turret_group()


func _group_by_id(group_id: int) -> Dictionary:
	var group: Variant = worker_groups_by_id.get(group_id, {})
	return group as Dictionary if group is Dictionary else {}


func _trials_for_group(group_id: int) -> Array:
	var group = _group_by_id(group_id)
	if group.is_empty():
		return []
	return group["trials"] as Array


func _remove_trials_for_group(group_id: int) -> void:
	var group = _group_by_id(group_id)
	var retained: Array[Dictionary] = []
	for trial in trials:
		# Removing or reconfiguring one group must not orphan every other group's still-running drones.
		if int(trial.get("group_id", -1)) != group_id:
			retained.append(trial)
			continue
		if int(trial.get("instance_id", -1)) == attached_camera_instance_id:
			_release_attached_camera()
		_unregister_trial_combatant(trial)
		var drone = trial.get("drone") as ServerDrone
		if is_instance_valid(drone):
			drone.queue_free()
	trials = retained
	if not group.is_empty():
		(group["trials"] as Array).clear()

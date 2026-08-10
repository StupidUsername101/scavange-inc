extends SceneTree

#######################################################
# Focused room-level regression coverage for the per-group target migration. The room-default
# target is evaluator/template state, not an extra worker target, and every runtime worker group
# must own an independent handler before target dispatch.
#######################################################

var failure_count: int = 0
var assertion_count: int = 0


func _init() -> void:
	_test_default_target_visual_only_tracks_evaluators()
	_test_runtime_group_dispatch_repairs_missing_handler()
	_test_drone_target_height_is_literal()
	_test_limb_target_marker_is_support_surface()
	_test_turret_group_publishes_live_runtime_members()
	_test_fresh_drone_model_architecture_reaches_constructor()
	_test_model_body_creator_carries_training_setup()
	_test_model_body_creator_fits_realized_content_to_viewport()
	_test_model_body_creator_staged_core_layout()
	_test_model_body_creator_core_geometry_editing()
	_test_model_body_creator_unbounded_attachment_layout()
	_test_paused_drone_candidate_keeps_frozen_hardware()
	_test_room_episode_status_is_one_shared_line()
	_test_room_ready_does_not_create_default_worker_group()
	_test_library_windows_start_hidden()

	if failure_count == 0:
		print("Training target room integration tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("Training target room integration tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _new_room_with_target_visuals() -> DroneTrainingRoom:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room._initialize_targeting()
	room._build_target()
	return room



func _test_library_windows_start_hidden() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.turret_ui.configure(room, room.turret_training, room.turret_model_registry)
	room._build_model_browser()
	room._build_limb_model_browser()
	room.turret_ui.build_model_browser()
	room._build_map_browser()
	_expect(not room.model_browser.visible, "drone model library starts hidden")
	_expect(not room.limb_model_browser.visible, "four-limb model library starts hidden")
	_expect(not room.turret_ui.model_browser.visible, "turret model library starts hidden")
	_expect(not room.map_browser.visible, "training map library starts hidden")
	room.free()


func _test_model_body_creator_carries_training_setup() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	_expect(panel.current_body_kind == "drone", "model creator opens on the authored quad-drone preset")
	panel.hidden_width_input.value = 96.0
	panel.hidden_depth_input.value = 3.0
	panel.worker_count_input.value = 6.0
	panel.control_rate_input.value = 30.0
	panel.exploration_input.value = 0.035
	panel.start_training_checkbox.button_pressed = false
	var request: Dictionary = panel._training_request()
	_expect(
		int(request.get("hidden_layer_width", -1)) == 96
		and int(request.get("hidden_layer_depth", -1)) == 3,
		"model creator preserves the requested neural-network width/depth"
	)
	_expect(
		int(request.get("worker_count", -1)) == 6
		and is_equal_approx(float(request.get("control_rate_hz", 0.0)), 30.0),
		"model creator preserves starting worker count and policy control rate"
	)
	_expect(
		is_equal_approx(float(request.get("exploration_strength", -1.0)), 0.035)
		and not bool(request.get("start_active", true)),
		"model creator can create a tuned group without starting training immediately"
	)
	_expect(
		str(request.get("reward_cardset_id", "")) == "builtin:drone_balanced"
		and not (request.get("reward_cards", {}) as Dictionary).is_empty(),
		"model creator sends the selected reward-card preset with the fresh worker group"
	)
	panel.free()


func _test_model_body_creator_fits_realized_content_to_viewport() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	panel._prepare_creator_window_size()
	var viewport_size: Vector2i = panel._creator_viewport_size()
	var maximum_width: int = maxi(
		viewport_size.x - MLBodyCreatorPanel.WINDOW_EDGE_MARGIN_PX,
		panel.min_size.x
	)
	var maximum_height: int = maxi(
		viewport_size.y - MLBodyCreatorPanel.WINDOW_EDGE_MARGIN_PX,
		panel.min_size.y
	)
	_expect(
		panel.size.x <= maximum_width and panel.size.y <= maximum_height,
		"model creator clamps its realized content size to the visible game viewport"
	)
	_expect(
		panel.content_scroll != null
		and panel.content_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		and panel.content_scroll.follow_focus
		and panel.root_content != null,
		"the creator form owns one vertical scroll surface so every body/training setting stays reachable"
	)
	_expect(
		panel.footer_panel != null
		and panel.window_layout != null
		and panel.footer_panel.get_parent() == panel.window_layout
		and not panel.content_scroll.is_ancestor_of(panel.footer_panel),
		"creator Cancel/Create actions stay pinned outside the scrolling form"
	)
	_expect(
		panel.hardware_stage != null
		and panel.slots_content != null
		and panel.content_scroll.is_ancestor_of(panel.hardware_stage)
		and panel.content_scroll.is_ancestor_of(panel.slots_content),
		"hardware assignment shares the creator's one outer scroll surface instead of nesting another wheel trap"
	)
	_expect(
		panel.layout_preview != null
		and panel.layout_preview.mouse_filter == Control.MOUSE_FILTER_PASS,
		"3D Core preview participates in the creator's single Window-level wheel route"
	)
	panel.free()


func _test_model_body_creator_staged_core_layout() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	_expect(
		panel.creator_stage == MLBodyCreatorPanel.STAGE_CORE_LAYOUT
		and panel.layout_slot_capacity == -1
		and panel.layout_slot_transforms.is_empty()
		and panel.layout_slot_kinds.is_empty(),
		"drone creator infers body kind from the Core and begins with no non-intrinsic mounts"
	)
	panel.mirror_next_checkbox.button_pressed = true
	panel._on_layout_surface_clicked(Transform3D(
		panel._slot_basis_from_surface_normal(Vector3.UP),
		Vector3(0.0, 0.22, 0.0)
	))
	_expect(
		panel.layout_slot_transforms.is_empty(),
		"mirror-next placement is atomic and rejects center-plane clicks instead of leaving an unmatched slot"
	)
	panel.mirror_next_checkbox.button_pressed = false
	var first_mount: Transform3D = Transform3D(
		panel._slot_basis_from_surface_normal(Vector3.RIGHT),
		Vector3(0.425, 0.0, 0.0)
	)
	panel._on_layout_surface_clicked(first_mount)
	panel._mirror_selected_layout_slot()
	_expect(
		panel.layout_slot_transforms.size() == 2
		and panel.layout_slot_kinds == [&"propeller", &"propeller"]
		and is_equal_approx(panel.layout_slot_transforms[0].origin.x, 0.425)
		and is_equal_approx(panel.layout_slot_transforms[1].origin.x, -0.425),
		"creator can mirror the selected propeller mount across the local X axis"
	)
	# RMB in the preview emits slot_remove_requested; exercise the same handler directly.
	panel._on_layout_slot_remove_requested(1)
	_expect(panel.layout_slot_transforms.size() == 1, "creator removes the exact right-clicked mount")
	panel._mirror_selected_layout_slot()
	# Changing the kind with no selected marker sets the kind for the next placement instead of
	# rewriting an existing mount.
	panel.layout_selected_slot_index = -1
	panel.layout_slot_kind_picker.select(1)
	panel._on_layout_surface_clicked(Transform3D(
		panel._slot_basis_from_surface_normal(Vector3.FORWARD),
		Vector3(0.0, 0.0, -0.425)
	))
	var propeller_mounts: Array[Transform3D] = []
	var attachment_mounts: Array[Transform3D] = []
	for layout_index: int in range(panel.layout_slot_transforms.size()):
		if panel.layout_slot_kinds[layout_index] == &"propeller":
			propeller_mounts.append(panel.layout_slot_transforms[layout_index])
		elif panel.layout_slot_kinds[layout_index] == &"attachment":
			attachment_mounts.append(panel.layout_slot_transforms[layout_index])
	_expect(
		propeller_mounts.size() == 2 and attachment_mounts.size() == 1,
		"slot kind picker authors propeller and attachment mounts instead of inheriting Core defaults"
	)
	_expect(
		propeller_mounts[0].basis.y.dot(Vector3.RIGHT) > 0.99
		and propeller_mounts[1].basis.y.dot(Vector3.LEFT) > 0.99
		and (-attachment_mounts[0].basis.y).dot(Vector3.FORWARD) > 0.99,
		"free Core mounts preserve attachment outward orientation while propeller +Y points along its actual thrust surface normal"
	)
	panel._accept_core_layout()
	_expect(
		panel.creator_stage == MLBodyCreatorPanel.STAGE_HARDWARE
		and panel.current_draft != null
		and panel.current_draft.equipped_part(&"battery") == null
		and panel.current_draft.slot_definition(&"propeller_0") != null
		and panel.current_draft.slot_definition(&"propeller_1") != null
		and panel.current_draft.slot_definition(&"propeller_2") == null
		and panel.current_draft.slot_definition(&"propeller_3") == null
		and panel.current_draft.slot_definition(&"attachment_0") != null
		and panel.current_draft.slot_definition(&"attachment_1") == null,
		"hardware assignment contains only the intrinsic battery plus the exact mount kinds placed in 3D"
	)
	var first_propeller_slot: MLBodySlotDefinition = panel.current_draft.slot_definition(&"propeller_0")
	var second_propeller_slot: MLBodySlotDefinition = panel.current_draft.slot_definition(&"propeller_1")
	var attachment_slot: MLBodySlotDefinition = panel.current_draft.slot_definition(&"attachment_0")
	_expect(
		first_propeller_slot != null
		and second_propeller_slot != null
		and attachment_slot != null
		and panel._slot_is_required(first_propeller_slot)
		and panel._slot_is_required(second_propeller_slot)
		and panel._slot_is_required(attachment_slot)
		and DroneMLBodyInterfaceFactory._transforms_match(first_propeller_slot.mount_transform, propeller_mounts[0])
		and DroneMLBodyInterfaceFactory._transforms_match(second_propeller_slot.mount_transform, propeller_mounts[1])
		and DroneMLBodyInterfaceFactory._transforms_match(attachment_slot.mount_transform, attachment_mounts[0]),
		"hardware assignment preserves every accepted propeller/attachment mount transform"
	)
	panel.free()


func _test_model_body_creator_core_geometry_editing() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	var core: DroneCoreDefinition = panel._current_physical_core() as DroneCoreDefinition
	_expect(
		core != null
		and core.editable_mesh != null
		and core.editable_mesh.has_geometry()
		and core.editable_mesh.face_count() == 6
		and core.editable_mesh.edge_count() == 12,
		"creator materializes saved Core dimensions into editable polygon topology with logical edges"
	)
	panel.layout_slot_kind_picker.select(1)
	panel._on_layout_slot_kind_selected(1)
	panel._on_layout_surface_clicked(Transform3D(
		panel._slot_basis_from_surface_normal(Vector3.RIGHT),
		Vector3(core.body_size.x * 0.5 + MLBodyCreatorPanel.CORE_MOUNT_OFFSET_M, 0.0, 0.0)
	))
	var old_mount: Transform3D = panel.layout_slot_transforms[0]
	panel.suppress_core_geometry_callbacks = true
	panel.core_width_input.value = 1.20
	panel.core_height_input.value = 0.50
	panel.core_depth_input.value = 0.90
	panel.suppress_core_geometry_callbacks = false
	panel._on_core_dimensions_changed(0.0)
	_expect(
		is_equal_approx(core.body_size.x, 1.20)
		and is_equal_approx(core.body_size.y, 0.50)
		and is_equal_approx(core.body_size.z, 0.90)
		and panel.layout_slot_transforms[0].origin.x > old_mount.origin.x,
		"live Core dimension edits rescale editable geometry and keep authored mounts attached to the resized surface"
	)
	panel.core_face_edit_toggle.button_pressed = true
	panel._on_layout_face_selected(3)
	var right_face_before: PackedInt32Array = core.editable_mesh.face_indices(3)
	var first_vertex_before: Vector3 = core.editable_mesh.vertices[right_face_before[0]]
	panel._expand_selected_core_face()
	var first_vertex_after: Vector3 = core.editable_mesh.vertices[right_face_before[0]]
	_expect(
		panel.layout_selected_face_index == 3
		and first_vertex_after.distance_to(first_vertex_before) > 0.001
		and panel.layout_preview.selected_face_index == 3,
		"creator face mode edits the selected logical polygon and keeps that face highlighted after the live mesh rebuild"
	)
	var ray_hit: Dictionary = core.editable_mesh.ray_hit(Vector3(5.0, 0.0, 0.0), Vector3.LEFT)
	_expect(
		int(ray_hit.get("face_index", -1)) == 3
		and (ray_hit.get("normal", Vector3.ZERO) as Vector3).dot(Vector3.RIGHT) > 0.99,
		"editable Core topology provides face-aware ray hits for creator picking instead of relying on an axis-aligned box"
	)
	var snapshot: Dictionary = MLBodyResourceSnapshot.encode_resource(core)
	var restored: DroneCoreDefinition = MLBodyResourceSnapshot.decode_resource(snapshot) as DroneCoreDefinition
	_expect(
		restored != null
		and restored.editable_mesh != null
		and restored.editable_mesh.vertices == core.editable_mesh.vertices
		and restored.editable_mesh.face_vertex_indices == core.editable_mesh.face_vertex_indices,
		"custom Core topology survives the generic body-resource snapshot used by creator/checkpoint persistence"
	)
	var shape: Shape3D = preload("res://scripts/drones/drone_part_geometry.gd").create_collision_shape(core)
	_expect(
		shape is ConvexPolygonShape3D
		and (shape as ConvexPolygonShape3D).points.size() == core.editable_mesh.vertices.size(),
		"edited dynamic Cores use their authored vertices for one convex physics hull instead of reverting to BoxShape3D"
	)
	panel.free()


func _test_model_body_creator_unbounded_attachment_layout() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	get_root().add_child(panel)
	panel.mirror_next_checkbox.button_pressed = false
	panel.layout_slot_kind_picker.select(1)
	panel._on_layout_slot_kind_selected(1)
	for index: int in range(8):
		var x: float = -0.35 + float(index) * 0.10
		panel._on_layout_surface_clicked(Transform3D(
			panel._slot_basis_from_surface_normal(Vector3.FORWARD),
			Vector3(x, 0.0, -0.425)
		))
	_expect(
		panel.layout_slot_transforms.size() == 8
		and panel._layout_slot_kind_count(&"attachment") == 8,
		"creator attachment placement has no four-slot/body-default ceiling"
	)
	panel._accept_core_layout()
	var runtime_core: DroneCoreDefinition = panel._current_physical_core() as DroneCoreDefinition
	_expect(
		panel.creator_stage == MLBodyCreatorPanel.STAGE_HARDWARE
		and runtime_core != null
		and runtime_core.propeller_slot_count == 0
		and runtime_core.attachment_slot_count == 8
		and panel.current_draft.slot_definition(&"propeller_0") == null
		and panel.current_draft.slot_definition(&"attachment_7") != null,
		"a propeller-free eight-limb/spider-style Core layout reaches hardware assignment intact"
	)
	var battery: DroneBatteryDefinition = load(
		"res://resources/drones/batteries/standard_battery.tres"
	) as DroneBatteryDefinition
	var configurable_limb: DroneLimbAttachmentDefinition = load(
		"res://resources/model_forge/attachments/configurable_articulated_limb.tres"
	) as DroneLimbAttachmentDefinition
	var equipped_all_limbs: bool = battery != null and configurable_limb != null
	if equipped_all_limbs:
		equipped_all_limbs = panel.current_draft.equip(
			&"battery",
			MLBodyPartContract.deep_duplicate_resource(battery)
		)
	for attachment_index: int in range(8):
		if not equipped_all_limbs:
			break
		equipped_all_limbs = panel.current_draft.equip(
			StringName("attachment_%d" % attachment_index),
			MLBodyPartContract.deep_duplicate_resource(configurable_limb)
		)
	var copied_attachment_configuration_valid: bool = false
	if equipped_all_limbs:
		var source_attachment: DroneLimbAttachmentDefinition = (
			panel.current_draft.equipped_part(&"attachment_0") as DroneLimbAttachmentDefinition
		)
		var target_slot: MLBodySlotDefinition = panel.current_draft.slot_definition(&"attachment_1")
		if (
			source_attachment != null
			and not source_attachment.limb_definitions.is_empty()
			and source_attachment.limb_definitions[0] != null
			and not source_attachment.limb_definitions[0].segments.is_empty()
			and target_slot != null
		):
			var target_mount_before: Transform3D = target_slot.mount_transform
			source_attachment.limb_definitions[0].segments[0].length = 1.37
			var target_picker: OptionButton = OptionButton.new()
			target_picker.add_item("Attachment 2")
			target_picker.set_item_metadata(0, "attachment_1")
			target_picker.select(0)
			panel._on_apply_slot_configuration_pressed("attachment_0", target_picker)
			var copied_attachment: DroneLimbAttachmentDefinition = (
				panel.current_draft.equipped_part(&"attachment_1") as DroneLimbAttachmentDefinition
			)
			var copied_limb: GenericLimbDefinition = (
				copied_attachment.limb_definitions[0]
				if copied_attachment != null and not copied_attachment.limb_definitions.is_empty()
				else null
			)
			copied_attachment_configuration_valid = (
				copied_attachment != null
				and copied_attachment != source_attachment
				and copied_limb != null
				and copied_limb != source_attachment.limb_definitions[0]
				and is_equal_approx(copied_limb.segments[0].length, 1.37)
				and panel.current_draft.slot_definition(&"attachment_1").mount_transform == target_mount_before
			)
			target_picker.free()
	_expect(
		copied_attachment_configuration_valid,
		"creator can deep-copy one attachment configuration to a compatible same-kind slot without moving that target mount"
	)
	var spider_manifest: MLBodyInterfaceManifest = (
		panel.current_draft.duplicate_editable().accept_build() if equipped_all_limbs else null
	)
	var spider_runtime: DroneLoadout = (
		MLBodyCreatorRuntimeFactory.runtime_from_draft(
			panel.current_preset_id,
			panel.current_draft,
			panel.changed_slot_ids
		) as DroneLoadout
		if equipped_all_limbs
		else null
	)
	var runtime_limb_count: int = 0
	if spider_runtime != null and spider_runtime.core != null:
		for attachment_index: int in range(spider_runtime.core.attachment_slot_count):
			if spider_runtime.get_attachment(attachment_index) is DroneLimbAttachmentDefinition:
				runtime_limb_count += 1
	_expect(
		equipped_all_limbs
		and spider_manifest != null
		and spider_manifest.control_count() == 24
		and spider_runtime != null
		and runtime_limb_count == 8,
		"eight configurable limbs survive accepted manifest and runtime loadout construction with all 24 joint controls"
	)
	var spider_power_cache_valid: bool = false
	if spider_runtime != null and spider_runtime.core != null:
		var expected_idle_power: float = 0.0
		for attachment_index: int in range(spider_runtime.core.attachment_slot_count):
			var attachment: DroneAttachmentDefinition = spider_runtime.get_attachment(attachment_index)
			if attachment != null and not attachment is DroneCameraAttachmentDefinition:
				expected_idle_power += maxf(attachment.idle_power_draw, 0.0)
		var spider_drone: ServerDrone = ServerDrone.new()
		spider_drone.loadout = spider_runtime
		spider_drone.call("_refresh_propeller_runtime_cache")
		var cached_consumption: float = float(spider_drone.call(
			"_apply_attachment_power",
			expected_idle_power + 100.0
		))
		spider_power_cache_valid = (
			spider_drone.has_runtime_attachment_power_cache
			and not spider_drone.has_weapon_attachments_cache
			and is_equal_approx(spider_drone.attachment_idle_power_total_cache, expected_idle_power)
			and is_equal_approx(cached_consumption, expected_idle_power)
		)
		spider_drone.free()
	_expect(
		spider_power_cache_valid,
		"an eight-limb spider keeps authored idle electrical draw through the cached non-weapon attachment power path"
	)
	panel.free()


func _test_paused_drone_candidate_keeps_frozen_hardware() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	var live_loadout: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var frozen_record: Dictionary = DroneTrainingLoadoutConfig.to_record(live_loadout)
	var contract: Dictionary = RLEvaluationContract.create("drone", {
		"hardware": frozen_record,
	})
	var candidate: Dictionary = {
		"candidate_id": 81,
		"evaluation_contract": contract,
		"evaluation_contract_hash": str(contract.get("contract_hash", "")),
	}
	var trainer: DroneTrainingAlgorithm = DroneTrainingAlgorithmCatalog.create("ppo_clip")
	trainer.set_evaluation_contract(contract)
	var group: Dictionary = {
		"group_id": 81,
		"active": false,
		"trainer": trainer,
		"drone_loadout": live_loadout,
		"candidate_drone_loadout_cache": {},
	}
	room._cache_drone_evaluation_loadout(group, contract, live_loadout)
	# The optimizer may still be running when the user pauses. Fill the bounded cache with newer
	# pause-time hardware contracts before a pending candidate formally exists; the trainer's frozen
	# pre-nomination contract must remain protected from eviction.
	for edit_index in range(8):
		var edited: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(live_loadout)
		edited.battery.energy_capacity_wh += float(edit_index + 1)
		var edited_contract: Dictionary = RLEvaluationContract.create("drone", {
			"hardware": DroneTrainingLoadoutConfig.to_record(edited),
		})
		room._cache_drone_evaluation_loadout(group, edited_contract, edited)
	_expect(
		(group.get("candidate_drone_loadout_cache", {}) as Dictionary).has(
			str(contract.get("contract_hash", ""))
		),
		"paused drone cache retains the trainer contract while a background update can still nominate it"
	)
	# Paused hardware editing is intentionally allowed. The pending candidate must keep the exact
	# body it was nominated with instead of inheriting this later live edit or failing reconstruction.
	live_loadout.battery.energy_capacity_wh += 0.75
	_expect(
		not DroneTrainingLoadoutConfig.records_match(
			frozen_record,
			DroneTrainingLoadoutConfig.to_record(live_loadout)
		),
		"test mutation changes the paused group's live drone hardware record"
	)
	var frozen_loadout: DroneLoadout = room._candidate_drone_loadout(group, candidate)
	_expect(
		frozen_loadout != null
		and DroneTrainingLoadoutConfig.records_match(
			frozen_record,
			DroneTrainingLoadoutConfig.to_record(frozen_loadout)
		),
		"paused drone fixed-seed evaluation resolves the candidate's frozen body independently of later live edits"
	)
	room.free()


func _test_room_episode_status_is_one_shared_line() -> void:
	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	room.episode_status_label = Label.new()
	room.add_child(room.episode_status_label)
	room.worker_groups.append({
		"group_id": 91,
		"active": false,
	})
	room.limb_training.groups.append({
		"group_id": 92,
		"name": "Walker",
		"active": true,
		"episode": 7,
		"workers": [],
		"awaiting_respawn": false,
	})
	room._refresh_episode_status()
	_expect(
		not room.episode_status_label.text.contains("\n")
		and room.episode_status_label.text.contains("Episode length 20.0 s")
		and room.episode_status_label.text.contains("1 active model")
		and room.episode_status_label.text.contains("1 paused model")
		and not room.episode_status_label.text.contains("Drones ·")
		and not room.episode_status_label.text.contains("Walker ·"),
		"room episode status keeps one shared room line instead of one timer row per worker family"
	)
	var progress_text: String = room.group_episode_progress_text({
		"episode": 7,
		"workers": [{
			"episode_elapsed": 6.2,
			"episode_duration": 20.0,
		}],
	}, "limb")
	_expect(
		progress_text == "episode 7 · 6.2/20.0 s",
		"worker-group cards expose live episode elapsed/duration progress again"
	)
	room.free()


func _test_room_ready_does_not_create_default_worker_group() -> void:
	var source: String = FileAccess.get_file_as_string("res://ml/training/drone_training_room.gd")
	var ready_start: int = source.find("func _ready() -> void:")
	var next_function: int = source.find("\nfunc ", ready_start + 1)
	var ready_source: String = source.substr(
		ready_start,
		(next_function - ready_start) if next_function > ready_start else source.length() - ready_start
	)
	_expect(
		ready_start >= 0 and not ready_source.contains("_create_worker_group("),
		"training-room startup does not silently create the old default drone worker group"
	)

func _test_default_target_visual_only_tracks_evaluators() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	_expect(not room.target_marker.visible, "room-default marker starts hidden without an evaluator")
	_expect(not room.target_radius_ring.visible, "room-default radius starts hidden without an evaluator")

	room.trials.append({"mode": "algorithm_training", "group_id": 1})
	room._refresh_default_target_visual_visibility()
	_expect(not room.target_marker.visible, "ordinary training workers do not reveal the room-default target")

	var evaluator_trial: Dictionary = {"mode": "evaluation", "group_id": -1}
	room.trials.append(evaluator_trial)
	room._refresh_default_target_visual_visibility()
	_expect(room.target_marker.visible, "an evaluator reveals the room-default target it actually consumes")
	_expect(room.target_radius_ring.visible, "an evaluator reveals the matching room-default radius")

	room.trials.erase(evaluator_trial)
	room._refresh_default_target_visual_visibility()
	_expect(not room.target_marker.visible, "removing the last evaluator hides the room-default target again")
	room.free()


func _test_runtime_group_dispatch_repairs_missing_handler() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 17,
		"color": Color("65d8ff"),
		"parent_group_id": -1,
	}
	room.worker_groups.append(group)
	_expect(not room.target_handlers_by_group_id.has(17), "test begins with a deliberately missing group handler")

	var targets: Dictionary = room._resolved_targets_by_group()
	var handler: TrainingTargetHandler = room._target_handler_for_group_id(17)
	_expect(handler != null, "dispatch repairs a missing runtime group handler")
	_expect(handler != room.default_target_handler, "repaired worker groups never alias the room-default handler")
	_expect(targets.has(17), "repaired group receives an explicit routed target entry")
	_expect(
		room._target_group_id_for_trial({"mode": "algorithm_training", "group_id": 17}) == 17,
		"training trials keep their explicit target-owner group id"
	)
	_expect(
		room._target_group_id_for_trial({"mode": "evaluation", "group_id": 17}) == -1,
		"evaluation trials stay on the room-default evaluator target"
	)
	room.free()


func _test_limb_target_marker_is_support_surface() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 23,
		"color": Color("ffb45e"),
		"parent_group_id": -1,
	}
	room.limb_training.groups.append(group)
	room.limb_training.groups_by_id[23] = group
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(23, group["color"])
	var path_system: TrainingPathTargetSystem = handler.path_system()
	_expect(
		path_system != null
		and is_zero_approx(path_system.base_height_m)
		and path_system.random_height_range_m.is_equal_approx(Vector2.ZERO),
		"fresh four-limb targets start on the ground and represent the actual support/destination surface instead of inheriting drone height assumptions"
	)
	room.limb_training.groups.erase(group)
	room.limb_training.groups_by_id.erase(23)
	room.free()


func _test_turret_group_publishes_live_runtime_members() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var drone_group: Dictionary = {
		"group_id": 31,
		"name": "Runtime targets",
		"color": Color.WHITE,
		"parent_group_id": -1,
	}
	room.worker_groups.append(drone_group)
	room.worker_groups_by_id[31] = drone_group
	var turret_group: Dictionary = {
		"group_id": 32,
		"name": "Targeting turret",
		"color": Color("ff9f5a"),
		"parent_group_id": -1,
		"target_worker_group_id": 31,
		"workers": [],
	}
	room.turret_training.groups.append(turret_group)
	room.turret_training.groups_by_id[32] = turret_group
	var first_body: Node3D = Node3D.new()
	var second_body: Node3D = Node3D.new()
	room.add_child(first_body)
	room.add_child(second_body)
	first_body.global_position = Vector3(1.0, 2.0, 3.0)
	second_body.global_position = Vector3(4.0, 2.0, 5.0)
	var first_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		first_body, &"drone", 3101, 31, 0, 1
	)
	var second_adapter: TrainingCombatantAdapter = TrainingCombatantAdapter.new(
		second_body, &"drone", 3102, 31, 1, 1
	)
	room.training_entity_spatial_hash.register_entity(
		first_adapter.spatial_key(), first_body, first_adapter.entity_kind,
		first_adapter.entity_id, first_adapter.metadata()
	)
	room.training_entity_spatial_hash.register_entity(
		second_adapter.spatial_key(), second_body, second_adapter.entity_kind,
		second_adapter.entity_id, second_adapter.metadata()
	)
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(32, turret_group["color"])
	room._sync_turret_group_target_registration(32, handler)
	var registered: TrainingRegisteredTargetSystem = handler.registered_system()
	handler.resolve(room._target_context_for_group(32))
	var selected: Dictionary = handler.selected_candidate
	_expect(
		registered != null and registered.target_count() == 2,
		"a selected turret target group publishes each live worker as an individual runtime candidate"
	)
	_expect(
		str(selected.get("target_kind", "")) == "combat_objective"
		and int((selected.get("metadata", {}) as Dictionary).get("target_worker_group_id", -1)) == 31
		and [3101, 3102].has(int((selected.get("metadata", {}) as Dictionary).get("target_entity_id", 0))),
		"the registered target handler resolves directly to a real member of the selected group instead of a moving centroid surrogate"
	)
	var locked_entity_id: int = int((selected.get("metadata", {}) as Dictionary).get("target_entity_id", 0))
	room._push_turret_resolved_target_identity(32, handler)
	_expect(
		int(turret_group.get("resolved_target_entity_id", -1)) == locked_entity_id,
		"the target handler pushes its exact selected worker into the turret policy immediately instead of waiting for a later coordinator tick"
	)
	second_body.global_position = Vector3(0.1, 2.0, 0.1)
	room.training_entity_spatial_hash.update_entity(second_adapter.spatial_key())
	room._sync_turret_group_target_registration(32, handler)
	handler.resolve(room._target_context_for_group(32))
	_expect(
		int((handler.selected_candidate.get("metadata", {}) as Dictionary).get("target_entity_id", 0)) == locked_entity_id,
		"an explicit turret target stays locked to the same live worker instead of thrashing when a sibling becomes slightly more attractive"
	)
	second_adapter.body = null
	room._sync_turret_group_target_registration(32, handler)
	_expect(
		registered.target_count() == 1,
		"dead or removed target members disappear from the runtime candidate provider immediately"
	)
	room.free()


func _test_fresh_drone_model_architecture_reaches_constructor() -> void:
	var ppo: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"ppo_clip",
		{"config": {"hidden_layer_width": 96, "hidden_layer_depth": 3}},
		70001
	)
	var ppo_architecture: Dictionary = ppo.network_architecture() if ppo != null else {}
	_expect(
		ppo != null
		and int(ppo_architecture.get("hidden_layer_width", -1)) == 96
		and int(ppo_architecture.get("hidden_layer_depth", -1)) == 3,
		"fresh drone PPO group creation applies requested hidden width/depth before the immutable network is constructed"
	)
	var sac: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"sac_her_maze",
		{"config": {"hidden_layer_width": 192, "hidden_layer_depth": 4}},
		70002
	)
	var sac_architecture: Dictionary = sac.network_architecture() if sac != null else {}
	_expect(
		sac != null
		and int(sac_architecture.get("hidden_layer_width", -1)) == 192
		and int(sac_architecture.get("hidden_layer_depth", -1)) == 4,
		"fresh drone SAC-HER group creation applies requested hidden width/depth before the immutable network is constructed"
	)
	var malformed: DroneTrainingAlgorithm = DroneTrainingRoom._create_group_training_algorithm(
		"ppo_clip",
		{"config": "broken"},
		70003
	)
	var malformed_architecture: Dictionary = malformed.network_architecture() if malformed != null else {}
	_expect(
		malformed != null
		and int(malformed_architecture.get("hidden_layer_width", -1)) == DronePPOActorCritic.HIDDEN_SIZE
		and int(malformed_architecture.get("hidden_layer_depth", -1)) == DronePPOActorCritic.HIDDEN_LAYER_COUNT,
		"malformed startup config falls back to the default architecture instead of throwing during group creation"
	)


func _test_drone_target_height_is_literal() -> void:
	var room: DroneTrainingRoom = _new_room_with_target_visuals()
	var group: Dictionary = {
		"group_id": 19,
		"color": Color("65d8ff"),
		"parent_group_id": -1,
	}
	room.worker_groups.append(group)
	var handler: TrainingTargetHandler = room._ensure_group_target_handler(19, group["color"])
	var path_system: TrainingPathTargetSystem = handler.path_system()
	_expect(
		path_system != null and is_equal_approx(path_system.base_height_m, DroneTrainingRoom.TARGET_START.y),
		"fresh drone targets start at the authored five-metre navigation height"
	)
	path_system.set_base_height(15.0)
	handler.resolve(room._target_context_for_group(19))
	var resolved: Dictionary = room._resolved_target_for_group_id(19)
	var resolved_position: Vector3 = resolved.get("position_world", Vector3.ZERO)
	_expect(
		is_equal_approx(resolved_position.y, 15.0),
		"a drone target height of 15 m routes exactly Y=15 m with no hidden hover offset"
	)
	room.free()


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)

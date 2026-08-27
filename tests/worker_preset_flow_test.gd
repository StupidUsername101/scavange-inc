extends Node

#######################################################
# End-to-end coverage for Worker Groups + presets. Runs as a project scene so the creator and room
# see the same autoload/runtime environment as the actual ML training room.
#######################################################

var assertion_count: int = 0
var failure_count: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_starting_catalog()
	_test_drone_presets()
	_test_articulated_presets()
	_test_creator_and_room_entry_flow()
	print("Worker preset flow assertions: %d, failures: %d" % [
		assertion_count,
		failure_count,
	])
	get_tree().quit(0 if failure_count == 0 else 1)


func _test_starting_catalog() -> void:
	var records: Array[Dictionary] = MLBodyPresetLibrary.worker_start_ui_records()
	var ids: PackedStringArray = PackedStringArray()
	for record: Dictionary in records:
		ids.append(str(record.get("preset_id", "")))
	_expect(
		records.size() == 4
		and ids.has(str(MLBodyPresetLibrary.DRONE_QUAD))
		and ids.has(str(MLBodyPresetLibrary.DRONE_HEX))
		and ids.has(str(MLBodyPresetLibrary.TINY_HUMANOID))
		and ids.has(str(MLBodyPresetLibrary.FOUR_LIMB_WALKER))
		and not ids.has(str(MLBodyPresetLibrary.STATIONARY_TURRET)),
		"Worker Groups + exposes exactly the requested four editable starting bodies"
	)


func _test_drone_presets() -> void:
	var quad: DroneLoadout = MLBodyPresetLibrary.drone_quad_loadout(false)
	var hex: DroneLoadout = MLBodyPresetLibrary.drone_hex_loadout()
	var hex_summary: Dictionary = DroneTrainingLoadoutConfig.physical_summary(hex)
	var quad_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(quad)
	var hex_manifest: MLBodyInterfaceManifest = DroneMLBodyInterfaceFactory.finalize_loadout(hex)
	var hex_complete: bool = hex != null and hex.core != null
	if hex_complete:
		for slot_index: int in range(6):
			hex_complete = hex_complete and hex.get_propeller(slot_index) != null
	_expect(
		quad_manifest != null
		and DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(quad_manifest),
		"4-propeller preset retains the stock geometry required by optional SAC-HER"
	)
	_expect(
		hex_complete
		and hex.core.propeller_slot_count == 6
		and hex_manifest != null
		and hex_manifest.control_count() == 6
		and not DroneMLBodyInterfaceFactory.is_legacy_stock_quad_manifest(hex_manifest)
		and float(hex_summary.get("nominal_upward_thrust_n", 0.0)) > 0.0
		and float(hex_summary.get("nominal_lift_to_weight", 0.0)) > 1.0,
		"6-propeller preset has six equipped upward rotors, a six-action PPO contract, and useful lift"
	)


func _test_articulated_presets() -> void:
	var humanoid: FourLimbBodyDefinition = MLBodyPresetLibrary.tiny_humanoid_definition()
	var dog: FourLimbBodyDefinition = MLBodyPresetLibrary.four_limb_walker_definition()
	if humanoid != null:
		humanoid.ensure_contract()
	if dog != null:
		dog.ensure_contract()
	var humanoid_draft: MLBodyBuildDraft = (
		FourLimbMLBodyInterfaceFactory.create_definition_draft(humanoid)
		if humanoid != null
		else null
	)
	var humanoid_manifest: MLBodyInterfaceManifest = (
		humanoid_draft.accept_build()
		if humanoid_draft != null and humanoid_draft.last_error.is_empty()
		else null
	)
	var arms_valid: bool = humanoid != null and humanoid.limbs.size() == 4
	var feet_valid: bool = arms_valid
	if arms_valid:
		for arm_index: int in range(2):
			var arm: FourLimbSlotDefinition = humanoid.limbs[arm_index]
			arms_valid = (
				arms_valid
				and arm != null
				and arm.slot_name.contains("Arm")
				and arm.end_effector != null
				and arm.end_effector.grip_mode == LimbEndEffectorDefinition.GripMode.CONTROLLED
				and arm.end_effector.allow_dynamic_grip
			)
		for leg_index: int in range(2, 4):
			var leg: FourLimbSlotDefinition = humanoid.limbs[leg_index]
			feet_valid = (
				feet_valid
				and leg != null
				and leg.slot_name.contains("Leg")
				and leg.end_effector != null
				and leg.end_effector.effector_type_id == &"plain_foot"
				and leg.end_effector.is_physically_present()
				and not leg.end_effector.allow_static_grip
				and not leg.end_effector.allow_dynamic_grip
			)
	_expect(
		arms_valid
		and feet_valid
		and humanoid_manifest != null
		and humanoid_manifest.control_count() == FourLimbMLAction.ACTION_COUNT,
		"tiny humanoid has two grabbing arm/hand chains and two physical non-grabbing leg/foot chains"
	)
	var dog_shape_valid: bool = dog != null and dog.limbs.size() == 4
	if dog_shape_valid:
		for limb: FourLimbSlotDefinition in dog.limbs:
			dog_shape_valid = (
				dog_shape_valid
				and limb != null
				and (limb.slot_name.contains("Front") or limb.slot_name.contains("Rear"))
				and limb.rest_foot_offset.y < -dog.core_size.y
			)
	_expect(
		dog_shape_valid and dog.core_size.z > dog.core_size.y,
		"robo-dog preset reuses the established low quadruped body and four articulated legs"
	)


func _test_creator_and_room_entry_flow() -> void:
	var panel: MLBodyCreatorPanel = MLBodyCreatorPanel.new()
	add_child(panel)
	var hex_opened: bool = panel.open_preset(MLBodyPresetLibrary.DRONE_HEX)
	var sac_disabled_for_hex: bool = _algorithm_disabled(panel.algorithm_picker, "sac_her_maze")
	_expect(
		hex_opened
		and panel.creator_stage == MLBodyCreatorPanel.STAGE_HARDWARE
		and panel.layout_slot_transforms.size() == 8
		and panel._layout_slot_kind_count(&"propeller") == 6
		and panel._layout_slot_kind_count(&"attachment") == 2
		and panel.current_draft.equipped_part(&"battery") != null
		and sac_disabled_for_hex,
		"choosing the hex preset skips empty layout assembly, keeps it editable, and disables incompatible SAC"
	)
	var quad_opened: bool = panel.open_preset(MLBodyPresetLibrary.DRONE_QUAD)
	_expect(
		quad_opened
		and not _algorithm_disabled(panel.algorithm_picker, "sac_her_maze")
		and panel.layout_slot_transforms.size() == 6
		and panel._layout_slot_kind_count(&"propeller") == 4,
		"choosing the stock quad keeps both PPO and SAC-HER available"
	)
	var humanoid_opened: bool = panel.open_preset(MLBodyPresetLibrary.TINY_HUMANOID)
	_expect(
		humanoid_opened
		and panel.current_body_kind == "articulated_body"
		and panel.current_draft.equipped_part(&"limb_0") is GenericLimbDefinition
		and panel.current_draft.equipped_part(&"limb_3") is GenericLimbDefinition,
		"choosing the humanoid opens its complete limbs in the existing 3D limb editor"
	)
	panel.hide()
	panel.free()

	var room: DroneTrainingRoom = DroneTrainingRoom.new()
	add_child(room)
	room._open_model_body_creator()
	_expect(
		room.model_body_preset_picker != null
		and room.model_body_preset_picker.visible
		and room.model_body_creator != null
		and not room.model_body_creator.visible,
		"Worker Groups + opens the preset/custom chooser before the full creator"
	)
	room.free()


func _algorithm_disabled(picker: OptionButton, algorithm_id: String) -> bool:
	if picker == null:
		return true
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == algorithm_id:
			return picker.is_item_disabled(index)
	return true


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)

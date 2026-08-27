extends SceneTree

const WAREHOUSE_CATALOG: Script = preload("res://scripts/drones/dev_warehouse_catalog.gd")

var failure_count: int = 0
var assertion_count: int = 0
var test_root: String = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	test_root = "/tmp/scavange_finalized_game_models_%d" % Time.get_ticks_usec()
	var loadout: DroneLoadout = load(
		"res://resources/drones/loadouts/default_quad.tres"
	) as DroneLoadout
	var manifest: MLBodyInterfaceManifest = _test_drone_manifest(loadout)
	_expect(manifest != null and manifest.finalized, "stock gameplay drone body finalizes")
	if manifest == null:
		_finish()
		return
	var trainer: DronePPOTrainer = DronePPOTrainer.new({
		"body_interface": manifest.to_dictionary(),
	}, 91273)
	var checkpoint: Dictionary = trainer.to_checkpoint()
	var artifacts: MLGameModelArtifact = MLGameModelArtifact.new(test_root)
	var first: Dictionary = artifacts.finalize_drone_model(
		"Warehouse Learner",
		checkpoint,
		{
			"group_id": 7,
			"group_name": "Warehouse Learner",
			"policy_scope": "test_policy",
			"policy_update": trainer.update_count_value(),
		}
	)
	_expect(not first.is_empty(), "compatible drone checkpoint finalizes for gameplay")
	if first.is_empty():
		push_error(artifacts.last_error)
		_finish()
		return
	var chip_path: String = str(first.get("chip_path", ""))
	var chip: DroneAIChipDefinition = ResourceLoader.load(
		chip_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as DroneAIChipDefinition
	var game_store: FinalizedMLChipStore = FinalizedMLChipStore.new(test_root)
	_expect(
		chip != null
		and chip.has_finalized_model_contract()
		and chip.finalized_model_id == "warehouse-learner/v0001",
		"export creates a versioned AI chip contract"
	)
	var restored: Dictionary = artifacts.load_checkpoint(chip)
	_expect(
		not restored.is_empty()
		and str((restored.get("game_export", {}) as Dictionary).get("artifact_id", ""))
		== chip.finalized_model_id,
		"manifest hash and checkpoint identity pass read-back validation"
	)
	_expect(
		artifacts.runtime_model_for_chip(chip, manifest.contract_signature) != null,
		"matching gameplay body creates the deterministic runtime model"
	)
	_expect(
		artifacts.runtime_model_for_chip(chip, "different-body") == null,
		"different gameplay body signature rejects the finalized chip"
	)
	var public_snapshot: Dictionary = FinalizedMLChipStore.public_chip_snapshot(chip)
	var client_chip: DroneAIChipDefinition = FinalizedMLChipStore.chip_from_public_snapshot(
		public_snapshot
	)
	_expect(
		client_chip != null
		and client_chip.display_name == chip.display_name
		and client_chip.finalized_model_id == chip.finalized_model_id
		and client_chip.has_finalized_model_identity()
		and not client_chip.has_finalized_model_contract()
		and not public_snapshot.has("finalized_model_path")
		and not public_snapshot.has("checkpoint")
		and not public_snapshot.has("network"),
		"client replication snapshot renders the chip without exposing paths or weights"
	)
	_expect(
		game_store.discover_chips().size() == 1
		and not game_store.load_checkpoint(chip).is_empty(),
		"dependency-light game-side discovery validates the exported chip"
	)
	var second: Dictionary = artifacts.finalize_drone_model(
		"Warehouse Learner",
		checkpoint,
		{"policy_scope": "test_policy"}
	)
	_expect(
		str(second.get("artifact_id", "")) == "warehouse-learner/v0002"
		and game_store.discover_chips().size() == 2,
		"re-finalizing creates a monotonic model version instead of overwriting a chip"
	)
	var sac_trainer: DroneSACTrainer = DroneSACTrainer.new({}, 91274)
	var sac_checkpoint: Dictionary = sac_trainer.to_checkpoint()
	# The room binds SAC's selected stock-quad body during finalization because historical SAC
	# checkpoints contain the fixed four-action architecture but no generic body manifest.
	sac_checkpoint["body_interface"] = manifest.to_dictionary()
	var sac_record: Dictionary = artifacts.finalize_drone_model(
		"Warehouse SAC",
		sac_checkpoint,
		{"policy_scope": "test_policy"}
	)
	var sac_chip: DroneAIChipDefinition = ResourceLoader.load(
		str(sac_record.get("chip_path", "")),
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	) as DroneAIChipDefinition
	_expect(
		not sac_record.is_empty()
		and sac_chip != null
		and sac_chip.finalized_algorithm_id == "sac_her_maze"
		and artifacts.runtime_model_for_chip(sac_chip, manifest.contract_signature) != null,
		"SAC-HER exports with the selected stock-quad body and loads for gameplay"
	)
	ProjectSettings.set_setting(FinalizedMLChipStore.ROOT_PROJECT_SETTING, test_root)
	var warehouse_layout: Dictionary = WAREHOUSE_CATALOG.build_layout()
	var warehouse_has_export: bool = false
	for slot_value: Variant in warehouse_layout.get("slots", []):
		var slot: Dictionary = slot_value
		if str(slot.get("definition_path", "")) == chip_path:
			warehouse_has_export = true
			break
	_expect(
		warehouse_has_export,
		"server/client warehouse layout includes one chip for each finalized model artifact"
	)
	ProjectSettings.set_setting(FinalizedMLChipStore.ROOT_PROJECT_SETTING, null)

	var checkpoint_path: String = str(first.get("checkpoint_path", ""))
	var corrupt: Dictionary = restored.duplicate(true)
	corrupt["network"] = {}
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(checkpoint_path, corrupt),
		"test can stage a corrupt exported checkpoint"
	)
	_expect(
		artifacts.load_checkpoint(chip).is_empty()
		and artifacts.last_error.contains("SHA-256"),
		"tampered finalized weights fail closed before runtime model creation"
	)
	_finish()


func _test_drone_manifest(loadout: DroneLoadout) -> MLBodyInterfaceManifest:
	if loadout == null or loadout.core == null or loadout.battery == null:
		return null
	var draft: MLBodyBuildDraft = MLBodyBuildDraft.new()
	if not draft.set_core(loadout.core, {"body_kind": "drone"}):
		return null
	var battery_slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
	battery_slot.slot_id = &"battery"
	battery_slot.display_name = "Battery"
	battery_slot.slot_type = &"battery"
	battery_slot.accepted_part_tags.append(&"battery")
	if not draft.add_slot(battery_slot, loadout.battery):
		return null
	for slot_index: int in range(loadout.core.propeller_slot_count):
		var slot: MLBodySlotDefinition = MLBodySlotDefinition.new()
		slot.slot_id = StringName("propeller_%d" % slot_index)
		slot.display_name = "Propeller %d" % (slot_index + 1)
		slot.slot_type = &"propeller"
		slot.accepted_part_tags.append(&"propeller")
		slot.mount_transform = loadout.get_propeller_slot_transform(slot_index)
		if not draft.add_slot(slot, loadout.get_propeller(slot_index)):
			return null
	return draft.accept_build()


func _finish() -> void:
	var absolute_root: String = ProjectSettings.globalize_path(test_root)
	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	if failure_count == 0:
		print("ML game model export tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error("ML game model export tests failed: %d/%d assertions" % [
			failure_count,
			assertion_count,
		])
		quit(1)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		return
	failure_count += 1
	push_error(message)

extends SceneTree

#######################################################
# Verifies that persisted training-map identities are derived from their storage directory rather
# than trusted from caller dictionaries or copied/corrupt manifests.
#######################################################

var failure_count: int = 0


func _init() -> void:
	var root_path: String = "user://tests/drone-training-map-registry-pass55"
	var absolute_root: String = ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)

	var registry: DroneTrainingMapRegistry = DroneTrainingMapRegistry.new(root_path)
	var first: Dictionary = registry.save_map(
		"Identity Test",
		[{
			"position_m": [1.0, 2.0, 3.0],
			"shape_kind": "box",
		}],
		[],
		[]
	)
	_expect(not first.is_empty(), "training map can be saved")
	_expect(str(first.get("version_name", "")) == "v0001", "first map version is v0001")
	var discovered_ids: Array[String] = TrainingFileIO.list_version_ids(root_path, "training-map")
	_expect(
		discovered_ids.size() == 1 and discovered_ids[0] == str(first.get("map_id", "")),
		"shared version discovery finds the persisted map identity exactly once"
	)
	_expect(
		not registry.get_map(" /%s/ " % str(first.get("map_id", ""))).is_empty(),
		"map lookup preserves surrounding whitespace/slash tolerance"
	)

	var real_storage_path: String = str(first.get("storage_path", ""))
	var forged: Dictionary = first.duplicate(true)
	forged["storage_path"] = root_path.path_join("forged-location")
	var overwritten: Dictionary = registry.overwrite_map(
		forged,
		[{"position_m": [4.0, 5.0, 6.0], "shape_kind": "box"}],
		[],
		[]
	)
	_expect(
		str(overwritten.get("storage_path", "")) == real_storage_path,
		"overwrite re-resolves the immutable map ID instead of trusting caller storage_path"
	)
	_expect(
		not FileAccess.file_exists(root_path.path_join("forged-location").path_join("map.json")),
		"forged caller paths cannot redirect a map overwrite"
	)

	var manifest_path: String = real_storage_path.path_join(DroneTrainingMapRegistry.MANIFEST_FILE_NAME)
	var valid_manifest: Dictionary = TrainingFileIO.read_json_dictionary(manifest_path)
	var corrupt_manifest: Dictionary = valid_manifest.duplicate(true)
	corrupt_manifest["map_id"] = "identity-test/v9999"
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, corrupt_manifest),
		"test can write a deliberately mismatched map manifest"
	)
	_expect(
		registry.get_map(str(first.get("map_id", ""))).is_empty(),
		"mismatched manifest identity is rejected"
	)
	_expect(
		registry.list_maps().is_empty(),
		"mismatched map manifests are omitted from library listings"
	)
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, valid_manifest),
		"test can restore the valid map manifest"
	)
	_expect(
		not registry.get_map(str(first.get("map_id", ""))).is_empty(),
		"restored valid map identity resolves again"
	)

	var stale_count_manifest: Dictionary = valid_manifest.duplicate(true)
	stale_count_manifest["obstacle_count"] = 999
	stale_count_manifest["item_count"] = 999
	stale_count_manifest["delivery_destination_group_count"] = 999
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, stale_count_manifest),
		"test can write deliberately stale denormalized map counts"
	)
	var normalized_counts: Dictionary = registry.get_map(str(first.get("map_id", "")))
	_expect(
		int(normalized_counts.get("obstacle_count", -1)) == 1
		and int(normalized_counts.get("item_count", -1)) == 0
		and int(normalized_counts.get("delivery_destination_group_count", -1)) == 0,
		"map browser counts are derived from the stored payload instead of stale manifest metadata"
	)
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, valid_manifest),
		"test restores valid manifest counts after denormalized-count coverage"
	)

	var malformed_payload_manifest: Dictionary = valid_manifest.duplicate(true)
	malformed_payload_manifest["obstacles"] = "broken"
	malformed_payload_manifest["items"] = null
	malformed_payload_manifest["delivery_destination_groups"] = 99
	malformed_payload_manifest["obstacle_count"] = 999
	malformed_payload_manifest["item_count"] = 999
	malformed_payload_manifest["delivery_destination_group_count"] = 999
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, malformed_payload_manifest),
		"test can write wrong-type map payload arrays"
	)
	var malformed_payload_counts: Dictionary = registry.get_map(str(first.get("map_id", "")))
	_expect(
		int(malformed_payload_counts.get("obstacle_count", -1)) == 0
		and int(malformed_payload_counts.get("item_count", -1)) == 0
		and int(malformed_payload_counts.get("delivery_destination_group_count", -1)) == 0,
		"wrong-type map payloads cannot preserve forged browser counts"
	)
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, valid_manifest),
		"test restores the valid map manifest after wrong-type payload coverage"
	)

	var fractional_manifest: Dictionary = valid_manifest.duplicate(true)
	fractional_manifest["version"] = 1.5
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, fractional_manifest),
		"test can write a deliberately fractional map version"
	)
	_expect(
		registry.get_map(str(first.get("map_id", ""))).is_empty(),
		"fractional persisted version identities fail closed instead of truncating"
	)
	_expect(
		TrainingFileIO.write_json_dictionary_atomic(manifest_path, valid_manifest),
		"test restores the valid map manifest after fractional identity coverage"
	)
	_expect(
		registry.get_map("identity-test/v0001/extra").is_empty(),
		"map IDs with extra path segments fail closed"
	)
	_expect(
		registry.get_map("../identity-test/v0001").is_empty(),
		"map IDs cannot traverse outside the registry root"
	)

	_expect(registry.delete_map(first), "saved map can be deleted")
	var second: Dictionary = registry.save_map("Identity Test", [], [], [])
	_expect(
		str(second.get("version_name", "")) == "v0002",
		"deleted map version numbers are not reused"
	)

	var external_first: Dictionary = registry.save_map("External Removal", [], [], [])
	_expect(not external_first.is_empty(), "separate map family can be saved for identity-floor coverage")
	_expect(
		TrainingFileIO.remove_directory_recursive_absolute(
			ProjectSettings.globalize_path(str(external_first.get("storage_path", "")))
		),
		"test can simulate a valid map directory being removed outside the registry"
	)
	var external_second: Dictionary = registry.save_map("External Removal", [], [], [])
	_expect(
		str(external_second.get("version_name", "")) == "v0002",
		"successfully issued map identities remain reserved even after external directory removal"
	)

	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)

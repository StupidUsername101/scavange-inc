extends SceneTree

#######################################################
# Persistence regressions for reward-card presets. Tests use a private user:// path so the real
# preset library is never touched.
#######################################################

var failure_count: int = 0


func _init() -> void:
	var root_path: String = "user://tests/reward-cardset-library-pass55"
	var absolute_root: String = ProjectSettings.globalize_path(root_path)
	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	DirAccess.make_dir_recursive_absolute(absolute_root)

	var storage_path: String = root_path.path_join("cardsets.json")
	var library: TrainingRewardCardsetLibrary = TrainingRewardCardsetLibrary.new(storage_path)
	var configuration: Dictionary = DroneTrainingRewardDeck.new().configuration_dictionary()
	var first: Dictionary = library.save_custom_cardset("drone", "Persistence A", configuration)
	_expect(not first.is_empty(), "custom reward preset can be persisted to an isolated library")
	var first_id: String = str(first.get("id", ""))
	_expect(not library.cardset("drone", first_id).is_empty(), "persisted preset is visible in memory")

	var malformed_record: Dictionary = {
		"id": "user:turret:wrong-family",
		"display_name": "Wrong Family",
		"body_type": "turret",
		"cards": configuration.duplicate(true),
		"builtin": false,
	}
	var missing_cards_record: Dictionary = {
		"id": "user:drone:missing-cards",
		"display_name": "Missing Cards",
		"body_type": "drone",
		"builtin": false,
	}
	var malformed_card_payload_record: Dictionary = {
		"id": "user:drone:bad-card-payload",
		"display_name": "Bad Card Payload",
		"body_type": "drone",
		"cards": {"approach": {"enabled": "yes"}},
		"builtin": false,
	}
	var drone_values: Array = library.custom_cardsets.get("drone", [])
	drone_values.append(malformed_record)
	drone_values.append(missing_cards_record)
	drone_values.append(malformed_card_payload_record)
	library.custom_cardsets["drone"] = drone_values
	_expect(
		library.cardset("drone", "user:turret:wrong-family").is_empty(),
		"cross-family custom preset IDs are not re-labeled into the wrong body library"
	)
	_expect(
		library.cardset("drone", "user:drone:missing-cards").is_empty(),
		"custom preset records missing their card payload are treated as corrupt"
	)
	_expect(
		library.cardset("drone", "user:drone:bad-card-payload").is_empty(),
		"custom presets with malformed nested card values are treated as corrupt"
	)
	var repaired_family_record: Dictionary = library.save_custom_cardset(
		"drone",
		"Wrong Family",
		configuration
	)
	_expect(
		str(repaired_family_record.get("id", "")).begins_with("user:drone:"),
		"saving over malformed cross-family metadata allocates a valid body-family identity"
	)
	var raw_after_repair: Variant = library.custom_cardsets.get("drone", [])
	var malformed_survived: bool = false
	if raw_after_repair is Array:
		var raw_records: Array = raw_after_repair as Array
		for raw_record: Variant in raw_records:
			if raw_record is Dictionary and str((raw_record as Dictionary).get("id", "")) == "user:turret:wrong-family":
				malformed_survived = true
				break
	_expect(
		not malformed_survived,
		"a successful preset save scrubs invalid cross-family records instead of carrying hidden corruption forward"
	)

	# Turn the parent of the configured destination into a file. Subsequent writes must fail in a
	# deterministic way without allowing the in-memory library to diverge from what was persisted.
	var blocker_path: String = root_path.path_join("write-blocker")
	var blocker: FileAccess = FileAccess.open(blocker_path, FileAccess.WRITE)
	if blocker != null:
		blocker.store_string("not a directory")
		blocker.close()
	library.storage_directory = blocker_path
	library.storage_path = blocker_path.path_join("cardsets.json")

	var second: Dictionary = library.save_custom_cardset("drone", "Persistence B", configuration)
	_expect(second.is_empty(), "failed preset writes report failure")
	_expect(
		not library.cardset("drone", first_id).is_empty(),
		"failed preset writes roll the in-memory library back to its previously persisted state"
	)
	_expect(
		_user_cardset_count(library, "drone") == 2,
		"failed preset writes do not leave phantom presets visible in memory"
	)

	_expect(
		not library.delete_custom_cardset("drone", first_id),
		"failed preset deletion reports failure"
	)
	_expect(
		not library.cardset("drone", first_id).is_empty(),
		"failed preset deletion restores the in-memory preset instead of hiding persisted data"
	)

	if DirAccess.dir_exists_absolute(absolute_root):
		TrainingFileIO.remove_directory_recursive_absolute(absolute_root)
	quit(0 if failure_count == 0 else 1)


func _user_cardset_count(library: TrainingRewardCardsetLibrary, body_type: String) -> int:
	var count: int = 0
	for record: Dictionary in library.cardsets_for_body_type(body_type):
		if str(record.get("id", "")).begins_with("user:"):
			count += 1
	return count


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("[PASS] %s" % label)
		return
	failure_count += 1
	push_error("[FAIL] %s" % label)

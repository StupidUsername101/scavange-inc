class_name PlayerCharacterAppearanceCatalog
extends RefCounted

## Temporary authored-character catalog. Keep this list explicit: directory enumeration order is
## platform/importer dependent and must never become replicated appearance state.
const MALE_VARIANT_PATHS := [
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_01.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_04.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_07.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_10.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_13.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_16.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_29.fbx",
	"res://assets/Characters_psx_01/Models/Rig/Male/Character_32.fbx",
]

# Five is coprime with the eight-entry catalog, making every consecutive lobby player distinct.
const PLAYER_ID_PERMUTATION_STRIDE := 5
const PLAYER_ID_PERMUTATION_OFFSET := 2


static func variant_count() -> int:
	return MALE_VARIANT_PATHS.size()


static func variant_index_for_player_id(player_id: int) -> int:
	if MALE_VARIANT_PATHS.is_empty():
		return -1
	return posmod(
		player_id * PLAYER_ID_PERMUTATION_STRIDE
		+ PLAYER_ID_PERMUTATION_OFFSET,
		MALE_VARIANT_PATHS.size()
	)


static func variant_path_for_player_id(player_id: int) -> String:
	var index := variant_index_for_player_id(player_id)
	return MALE_VARIANT_PATHS[index] if index >= 0 else ""

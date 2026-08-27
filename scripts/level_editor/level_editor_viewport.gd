class_name LevelEditorViewport
extends SubViewportContainer

signal asset_dropped(asset_path: String, local_position: Vector2)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return (
		data is Dictionary
		and (data as Dictionary).get("type", &"") == &"level_asset"
		and LevelAssetCatalog.is_valid_asset_path(
			str((data as Dictionary).get("asset_path", ""))
		)
	)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	asset_dropped.emit(str((data as Dictionary).get("asset_path", "")), at_position)

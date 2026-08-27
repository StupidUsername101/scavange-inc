extends SceneTree

const BAKER := preload("res://tools/asset_collision_baker.gd")
const MANIFEST_PATH := "res://tools/asset_collision_manifest.json"

## With no user arguments every manifest entry is rebuilt. Pass stable manifest IDs after `--` to
## bake only newly curated assets.


func _init() -> void:
	var requested_ids := PackedStringArray()
	for argument: String in OS.get_cmdline_user_args():
		var clean := argument.strip_edges()
		if not clean.is_empty():
			requested_ids.append(clean)
	quit(0 if BAKER.bake_manifest(MANIFEST_PATH, requested_ids) else 1)

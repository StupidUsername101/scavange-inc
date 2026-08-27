extends SceneTree

## Compatibility entry point retained for the documented nature-only workflow. New curated assets
## use generate_asset_collisions.gd and the shared manifest.

const BAKER := preload("res://tools/asset_collision_baker.gd")
const MANIFEST_PATH := "res://tools/asset_collision_manifest.json"
const NATURE_IDS := PackedStringArray([
	"nature_pine_trunk",
	"nature_broadleaf_trunk",
	"nature_stone",
])


func _init() -> void:
	quit(0 if BAKER.bake_manifest(MANIFEST_PATH, NATURE_IDS) else 1)

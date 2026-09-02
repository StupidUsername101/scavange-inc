class_name LevelLightRuntimeBuilder
extends RefCounted

const LIGHT_AUTHORING := preload(
	"res://scripts/level_editor/level_light_authoring.gd"
)


static func build_into(
	parent: Node,
	descriptors: Array[Dictionary],
	root_name := "AuthoredLights"
) -> Array[Light3D]:
	var result: Array[Light3D] = []
	if parent == null:
		return result
	var root := Node3D.new()
	root.name = root_name
	parent.add_child(root)
	var live_ids: Dictionary[int, bool] = {}
	for raw: Dictionary in descriptors:
		var safe: Dictionary = LIGHT_AUTHORING.sanitize_descriptor(raw)
		var light_id := int(safe.get("id", 0))
		if safe.is_empty() or live_ids.has(light_id):
			continue
		var light: Light3D = LIGHT_AUTHORING.instantiate_light(safe)
		if light == null:
			continue
		live_ids[light_id] = true
		root.add_child(light)
		result.append(light)
	return result

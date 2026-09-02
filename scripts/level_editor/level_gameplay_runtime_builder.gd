class_name LevelGameplayRuntimeBuilder
extends RefCounted

const AUTHORED_ITEM_DEFINITION := preload(
	"res://scripts/level_editor/authored_level_item_definition.gd"
)
const RUNTIME_SELECTION := preload(
	"res://scripts/level_editor/level_runtime_selection.gd"
)
const LIGHT_RUNTIME_BUILDER := preload(
	"res://scripts/level_editor/level_light_runtime_builder.gd"
)


static func spawn_active_level_items(spawn_callable: Callable) -> Array[ServerItem]:
	var active_path := RUNTIME_SELECTION.active_level_path()
	if active_path.is_empty():
		return []
	var document := LevelEditorDocument.load_from_path(active_path)
	if document == null:
		return []
	return spawn_placement_items(document.placements, spawn_callable)


static func build_active_level_lights(parent: Node) -> Array[Light3D]:
	var active_path := RUNTIME_SELECTION.active_level_path()
	if active_path.is_empty():
		return []
	var document := LevelEditorDocument.load_from_path(active_path)
	if document == null:
		return []
	return LIGHT_RUNTIME_BUILDER.build_into(
		parent,
		document.authored_lights,
		"AuthoredLevelLights"
	)


static func spawn_placement_items(
	placements: Array[Dictionary],
	spawn_callable: Callable
) -> Array[ServerItem]:
	var result: Array[ServerItem] = []
	if not spawn_callable.is_valid():
		return result
	for raw_placement: Dictionary in placements:
		var placement := LevelEditorDocument.sanitize_placement(raw_placement)
		if placement.is_empty():
			continue
		var role: StringName = placement.get(
			"gameplay_role",
			LevelEditorDocument.PLACEMENT_ROLE_STATIC
		)
		if (
			role != LevelEditorDocument.PLACEMENT_ROLE_ITEM
			and role != LevelEditorDocument.PLACEMENT_ROLE_VALUABLE
		):
			continue
		var definition := AUTHORED_ITEM_DEFINITION.new() as ItemDefinition
		if (
			definition == null
			or not definition.call("configure_from_placement", placement, true)
		):
			continue
		var item_transform := Transform3D(
			Basis.from_euler(placement.get("rotation", Vector3.ZERO)),
			placement.get("position", Vector3.ZERO)
		)
		var item := spawn_callable.call(definition, item_transform) as ServerItem
		if item == null:
			continue
		item.set_meta("authored_level_placement_id", int(placement["id"]))
		item.set_meta("authored_level_gameplay_role", role)
		item.set_meta(
			"authored_level_total_value",
			definition.get_instance_total_value({})
		)
		item.sleeping = true
		result.append(item)
	return result

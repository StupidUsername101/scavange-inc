class_name DevZooCatalog
extends RefCounted

const ENEMY_DIRECTORY := "res://resources/enemies"
# Twice the width and depth gives every definition four times the floor area.
const PEN_SIZE := Vector2(20.0, 20.0)
const PEN_GAP := 2.0

#######################################################
# Builds the discoverable dev zoo catalog consumed by development or gameplay interfaces.
#######################################################

static func build_layout() -> Dictionary:
	var definitions := _load_definitions()
	var pens: Array[Dictionary] = []
	var total_width := maxf(
		float(definitions.size()) * PEN_SIZE.x
		+ float(maxi(definitions.size() - 1, 0)) * PEN_GAP,
		PEN_SIZE.x
	)
	var left := -total_width * 0.5
	for index: int in range(definitions.size()):
		var definition: EnemyDefinition = definitions[index]
		var center_x := (
			left + PEN_SIZE.x * 0.5
			+ float(index) * (PEN_SIZE.x + PEN_GAP)
		)
		pens.append({
			"slot_index": index,
			"definition_path": definition.resource_path,
			"display_name": definition.display_name,
			"center": Vector3(center_x, 0.0, 0.0),
			"size": PEN_SIZE,
		})
	return {
		"pens": pens,
		"total_width": total_width,
		"depth": PEN_SIZE.y,
	}


static func _load_definitions() -> Array[EnemyDefinition]:
	var result: Array[EnemyDefinition] = []
	var directory := DirAccess.open(ENEMY_DIRECTORY)
	if directory == null:
		push_error("Dev zoo cannot open catalog: %s" % ENEMY_DIRECTORY)
		return result
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var definition := load(ENEMY_DIRECTORY.path_join(file_name))
		if definition is EnemyDefinition:
			result.append(definition as EnemyDefinition)
	result.sort_custom(
		func(left: EnemyDefinition, right: EnemyDefinition) -> bool:
			return left.display_name.naturalnocasecmp_to(right.display_name) < 0
	)
	return result

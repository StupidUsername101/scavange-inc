extends RefCounted

const HORIZONTAL_SPACING := 2.05
const VERTICAL_SPACING := 0.78
const SECTION_GAP := 0.75
const SECTION_PADDING := 0.28
const SLOT_BASE_HEIGHT := 0.88
const SLOT_DEPTH := 0.34

const SECTION_SPECS: Array[Dictionary] = [
	{
		"title": "CORES",
		"directory": "res://resources/drones/cores",
		"columns": 3,
		"copies": 1,
		"color": Color(0.23, 0.52, 0.9, 1.0),
	},
	{
		"title": "BATTERIES",
		"directory": "res://resources/drones/batteries",
		"columns": 3,
		"copies": 1,
		"color": Color(0.22, 0.82, 0.46, 1.0),
	},
	{
		"title": "PROPELLERS (SETS OF FOUR)",
		"directory": "res://resources/drones/propellers",
		"columns": 4,
		"copies": 4,
		"color": Color(0.95, 0.56, 0.12, 1.0),
	},
	{
		"title": "AI CHIPS",
		"directory": "res://resources/drones/ai_chips",
		"columns": 3,
		"copies": 1,
		"color": Color(0.66, 0.3, 0.94, 1.0),
	},
	{
		"title": "BELLY ATTACHMENTS",
		"directory": "res://resources/drones/attachments",
		"columns": 3,
		"copies": 1,
		"color": Color(0.1, 0.82, 0.78, 1.0),
	},
	{
		"title": "BACKPACKS",
		"directory": "res://resources/items/backpacks",
		"columns": 3,
		"copies": 1,
		"color": Color(0.82, 0.48, 0.16, 1.0),
	},
	{
		"title": "OCULARS",
		"directory": "res://resources/items/eyes",
		"columns": 3,
		"copies": 1,
		"color": Color(0.24, 0.82, 0.62, 1.0),
	},
	{
		"title": "FIREARMS",
		"directory": "res://resources/items/guns",
		"columns": 2,
		"copies": 1,
		"color": Color(0.9, 0.28, 0.16, 1.0),
	},
	{
		"title": "GUN COMPONENTS",
		"directory": "res://resources/guns/parts",
		"columns": 4,
		"copies": 1,
		"color": Color(0.78, 0.52, 0.18, 1.0),
	},
	{
		"title": "ROPES & TETHERS",
		"directory": "res://resources/ropes",
		"columns": 2,
		"copies": 1,
		"color": Color(0.96, 0.72, 0.18, 1.0),
	},
]

#######################################################
# Builds the discoverable dev warehouse catalog consumed by development or gameplay
# interfaces.
#######################################################


static func build_layout() -> Dictionary:
	var sections: Array[Dictionary] = []
	var slots: Array[Dictionary] = []
	var cursor_x := 0.0
	var slot_index := 0

	for spec: Dictionary in SECTION_SPECS:
		var definitions := _load_definitions(str(spec["directory"]))
		var columns := int(spec["columns"])
		var copies := int(spec["copies"])
		var row_count := definitions.size()
		if copies == 1:
			row_count = int(ceili(float(definitions.size()) / float(columns)))
		row_count = maxi(row_count, 1)

		var section_width := (
			float(columns) * HORIZONTAL_SPACING
			+ SECTION_PADDING * 2.0
		)
		var section_height := (
			SLOT_BASE_HEIGHT
			+ float(row_count - 1) * VERTICAL_SPACING
			+ 1.05
		)
		var section_left := cursor_x
		var section_center_x := section_left + section_width * 0.5

		sections.append({
			"title": str(spec["title"]),
			"color": spec["color"],
			"center_x": section_center_x,
			"width": section_width,
			"height": section_height,
			"row_count": row_count,
		})

		for definition_index: int in range(definitions.size()):
			var definition: Resource = definitions[definition_index]
			var row := definition_index
			var first_column := 0
			var item_copy_count := copies
			if copies == 1:
				row = int(floori(float(definition_index) / float(columns)))
				first_column = definition_index % columns

			for copy_index: int in range(item_copy_count):
				var column := first_column + copy_index
				var position := Vector3(
					section_left
					+ SECTION_PADDING
					+ HORIZONTAL_SPACING * (float(column) + 0.5),
					SLOT_BASE_HEIGHT + VERTICAL_SPACING * float(row),
					SLOT_DEPTH
				)
				slots.append({
					"slot_index": slot_index,
					"section_title": str(spec["title"]),
					"section_color": spec["color"],
					"definition_path": definition.resource_path,
					"display_name": str(definition.get("display_name")),
					"position": position,
					"rotation": Vector3(deg_to_rad(90.0), 0.0, 0.0),
					"copy_index": copy_index,
					"copy_count": item_copy_count,
				})
				slot_index += 1

		cursor_x += section_width + SECTION_GAP

	var total_width := maxf(cursor_x - SECTION_GAP, 1.0)
	var center_offset := total_width * 0.5
	for section: Dictionary in sections:
		section["center_x"] = float(section["center_x"]) - center_offset
	for slot: Dictionary in slots:
		var position: Vector3 = slot["position"]
		position.x -= center_offset
		slot["position"] = position

	return {
		"sections": sections,
		"slots": slots,
		"total_width": total_width,
		"max_height": _get_max_section_height(sections),
	}


static func _load_definitions(directory_path: String) -> Array[Resource]:
	var definitions: Array[Resource] = []
	if DirAccess.open(directory_path) == null:
		push_error("Dev warehouse cannot open catalog: %s" % directory_path)
		return definitions

	for resource_path: String in ResourcePathDiscovery.collect_shallow(directory_path, ["tres"]):
		var definition: Resource = load(resource_path)
		if definition is DronePartDefinition or definition is ItemDefinition:
			definitions.append(definition)

	definitions.sort_custom(
		func(
			left: Resource,
			right: Resource
		) -> bool:
			return (
				str(left.get("display_name")).naturalnocasecmp_to(
					str(right.get("display_name"))
				)
				< 0
			)
	)
	return definitions


static func _get_max_section_height(sections: Array[Dictionary]) -> float:
	var result := 1.0
	for section: Dictionary in sections:
		result = maxf(result, float(section["height"]))
	return result

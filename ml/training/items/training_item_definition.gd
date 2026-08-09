@tool
class_name TrainingItemDefinition
extends Resource

#######################################################
# Serialized training-item archetype. Runtime TrainingItem3D nodes are instances of one of these
# resources (or an editable deep copy), so item mass/shape/grip identity is content data rather
# than being invented by training-room/coordinator code.
#######################################################

@export_group("Identity")
@export var display_name: String = "Training Item"
@export var item_type: String = "generic"

@export_group("Physics")
@export_enum("Box", "Cylinder", "Sphere", "Capsule") var shape_kind: int = DroneTrainingObstacleShape.Kind.BOX
@export var dimensions: Dictionary = {
	"width": 0.45,
	"height": 0.32,
	"depth": 0.45,
	"radius": 0.22,
}
@export_range(0.01, 10000.0, 0.01, "or_greater") var mass_kg: float = 1.0

@export_group("Task")
@export_range(0.0, 100000.0, 0.01, "or_greater") var reward_value: float = 1.0
@export var grip_surface_tags: PackedStringArray = PackedStringArray(["carryable"])

@export_group("Presentation")
@export var visual_color: Color = Color("f2b84b")


func sanitized_copy() -> TrainingItemDefinition:
	var result: TrainingItemDefinition = duplicate(true) as TrainingItemDefinition
	if result == null:
		return null
	result.sanitize()
	return result


func sanitize() -> void:
	display_name = display_name.strip_edges()
	if display_name.is_empty():
		display_name = "Training Item"
	item_type = normalized_item_type(item_type)
	shape_kind = clampi(shape_kind, 0, DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1)
	dimensions = DroneTrainingObstacleShape.normalized_dimensions(shape_kind, dimensions)
	mass_kg = maxf(RLTrainingMath.finite_float_or(mass_kg, 1.0), 0.01)
	reward_value = maxf(RLTrainingMath.finite_float_or(reward_value, 0.0), 0.0)
	var clean_tags: PackedStringArray = PackedStringArray()
	for value: String in grip_surface_tags:
		var clean: String = value.strip_edges().to_lower()
		if not clean.is_empty() and not clean_tags.has(clean):
			clean_tags.append(clean)
	if clean_tags.is_empty():
		clean_tags.append("carryable")
	grip_surface_tags = clean_tags
	var fallback_color: Color = Color("f2b84b")
	visual_color = Color(
		clampf(RLTrainingMath.finite_float_or(visual_color.r, fallback_color.r), 0.0, 1.0),
		clampf(RLTrainingMath.finite_float_or(visual_color.g, fallback_color.g), 0.0, 1.0),
		clampf(RLTrainingMath.finite_float_or(visual_color.b, fallback_color.b), 0.0, 1.0),
		clampf(RLTrainingMath.finite_float_or(visual_color.a, fallback_color.a), 0.0, 1.0)
	)


func contract_dictionary() -> Dictionary:
	return {
		"resource_path": resource_path,
		"display_name": display_name,
		"item_type": normalized_item_type(item_type),
		"shape_kind": clampi(shape_kind, 0, DroneTrainingObstacleShape.DISPLAY_NAMES.size() - 1),
		"dimensions": DroneTrainingObstacleShape.normalized_dimensions(shape_kind, dimensions),
		"mass_kg": maxf(RLTrainingMath.finite_float_or(mass_kg, 1.0), 0.01),
		"reward_value": maxf(RLTrainingMath.finite_float_or(reward_value, 0.0), 0.0),
		"grip_surface_tags": Array(grip_surface_tags),
		"visual_color": visual_color,
	}


static func normalized_item_type(value: String) -> String:
	var cleaned: String = value.strip_edges().to_lower()
	if cleaned.is_empty():
		return "generic"
	var result: String = ""
	var previous_separator: bool = false
	for index: int in range(cleaned.length()):
		var character: String = cleaned.substr(index, 1)
		var code: int = character.unicode_at(0)
		var alphanumeric: bool = (code >= 48 and code <= 57) or (code >= 97 and code <= 122)
		if alphanumeric:
			result += character
			previous_separator = false
		elif not previous_separator and not result.is_empty():
			result += "_"
			previous_separator = true
	result = result.trim_suffix("_")
	return result if not result.is_empty() else "generic"

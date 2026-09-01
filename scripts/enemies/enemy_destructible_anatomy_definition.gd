@tool
class_name EnemyDestructibleAnatomyDefinition
extends Resource

## Reusable enemy-destruction profile. Enemy behavior, visuals, and networking all consume the same
## named parts; no enemy type check is required to opt into wounds or dismemberment.

@export var damage_texture: DestructionTextureDefinition
@export var parts: Array[EnemyAnatomyPartDefinition] = []
@export_range(0.005, 0.25, 0.005, "or_greater") var voxel_size := 0.01
@export_range(4, 32, 1) var brick_cells := 12
@export_range(0.0, 1.0, 0.001) var aggregate_destruction_threshold := 0.58
@export_range(0.0, 0.1, 0.001) var critical_air_margin := 0.003
@export_range(1, 64, 1) var replicated_wound_limit := 24


func get_part(part_id: StringName) -> EnemyAnatomyPartDefinition:
	for part: EnemyAnatomyPartDefinition in parts:
		if part != null and part.part_id == part_id:
			return part
	return null


func has_usable_parts() -> bool:
	if damage_texture == null or parts.is_empty():
		return false
	var seen: Dictionary[StringName, bool] = {}
	for part: EnemyAnatomyPartDefinition in parts:
		if part == null or part.part_id.is_empty() or seen.has(part.part_id):
			return false
		seen[part.part_id] = true
	return true

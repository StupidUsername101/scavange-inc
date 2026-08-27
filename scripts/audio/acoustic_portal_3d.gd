@tool
class_name AcousticPortal3D
extends Node3D

## Explicit graph edge for doors, vents, thin walls and other paths that need authored material
## behavior. Ordinary line-of-sight probe pairs are connected automatically without a modifier.

@export_node_path("AcousticProbe3D") var probe_a_path: NodePath
@export_node_path("AcousticProbe3D") var probe_b_path: NodePath
@export var bidirectional := true
@export var enabled := true
@export var carries_guided_energy := false
@export var material: AcousticMaterial
@export var modifier: AcousticPathModifier


func _enter_tree() -> void:
	add_to_group(&"acoustic_portals")


func get_probe_a() -> AcousticProbe3D:
	return get_node_or_null(probe_a_path) as AcousticProbe3D


func get_probe_b() -> AcousticProbe3D:
	return get_node_or_null(probe_b_path) as AcousticProbe3D


func create_path_modifier() -> AcousticPathModifier:
	var result := (
		material.create_transmission_modifier()
		if material != null
		else AcousticPathModifier.identity()
	)
	return (
		result.combined_with(modifier)
		if modifier != null
		else result
	)

class_name WorldNatureDressing
extends Node3D

const LAYOUT := preload("res://scripts/world/world_nature_layout.gd")
const ASSET_SCENES := {
	&"pine": preload("res://assets/third_party/pizza_doggy/models/nature/pine_tree_1.glb"),
	&"broadleaf": preload("res://assets/third_party/pizza_doggy/models/nature/tree_8.glb"),
	&"fern": preload("res://assets/third_party/pizza_doggy/models/nature/fern_1.glb"),
	&"grass": preload("res://assets/third_party/pizza_doggy/models/nature/grass_1.glb"),
	&"stone": preload("res://assets/third_party/pizza_doggy/models/nature/stone_2.glb"),
}

const VISIBILITY_RANGE_METERS := 175.0


func _ready() -> void:
	_build_batches()


func _build_batches() -> void:
	var descriptors_by_asset: Dictionary[StringName, Array] = {}
	for descriptor: Dictionary in LAYOUT.visual_descriptors():
		var asset_id: StringName = descriptor.get("asset_id", &"")
		if not descriptors_by_asset.has(asset_id):
			descriptors_by_asset[asset_id] = []
		descriptors_by_asset[asset_id].append(descriptor)

	for asset_id: StringName in descriptors_by_asset:
		var packed_scene := ASSET_SCENES.get(asset_id) as PackedScene
		if packed_scene == null:
			push_warning("Unknown nature asset: %s" % asset_id)
			continue
		_add_asset_batches(asset_id, packed_scene, descriptors_by_asset[asset_id])


func _add_asset_batches(
	asset_id: StringName,
	packed_scene: PackedScene,
	descriptors: Array
) -> void:
	var sample := packed_scene.instantiate() as Node3D
	if sample == null:
		return
	var mesh_components: Array[Dictionary] = []
	_collect_mesh_components(sample, Transform3D.IDENTITY, mesh_components)
	for component_index: int in range(mesh_components.size()):
		var component := mesh_components[component_index]
		var mesh := component.get("mesh") as Mesh
		if mesh == null:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = descriptors.size()
		var component_transform: Transform3D = component.get(
			"transform",
			Transform3D.IDENTITY
		)
		for descriptor_index: int in range(descriptors.size()):
			var descriptor: Dictionary = descriptors[descriptor_index]
			multimesh.set_instance_transform(
				descriptor_index,
				LAYOUT.descriptor_transform(descriptor) * component_transform
			)
		var instance := MultiMeshInstance3D.new()
		instance.name = "%sBatch%d" % [String(asset_id).capitalize(), component_index]
		instance.multimesh = multimesh
		instance.visibility_range_end = VISIBILITY_RANGE_METERS
		instance.visibility_range_end_margin = 18.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(instance)
	sample.free()


func _collect_mesh_components(
	node: Node,
	parent_transform: Transform3D,
	result: Array[Dictionary]
) -> void:
	var current_transform := parent_transform
	if node is Node3D:
		current_transform *= (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result.append({
				"mesh": mesh_instance.mesh,
				"transform": current_transform,
			})
	for child: Node in node.get_children():
		_collect_mesh_components(child, current_transform, result)

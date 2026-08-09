@tool
extends ItemDefinition
class_name BodyPartItemDefinition

const ARM_LENGTH := 0.72
const LEG_LENGTH := 0.9
const ARM_RADIUS := 0.13
const LEG_RADIUS := 0.16

#######################################################
# Wraps a purchasable limb as a physical, replicated inventory item while retaining the limb
# resource that a future surgery or installation system will consume.
#######################################################

@export var limb_definition: LimbDefinition


func instantiate_visual() -> Node3D:
	var root := Node3D.new()
	root.name = "BodyPartVisual"
	var limb := MeshInstance3D.new()
	limb.name = "Limb"

	var is_arm := (
		limb_definition != null
		and (
			limb_definition.slot == LimbDefinition.Slot.LEFT_ARM
			or limb_definition.slot == LimbDefinition.Slot.RIGHT_ARM
		)
	)
	var capsule := CapsuleMesh.new()
	capsule.height = ARM_LENGTH if is_arm else LEG_LENGTH
	capsule.radius = ARM_RADIUS if is_arm else LEG_RADIUS
	var material := StandardMaterial3D.new()
	material.albedo_color = (
		Color(0.73, 0.5, 0.4, 1.0)
		if is_arm
		else Color(0.64, 0.43, 0.34, 1.0)
	)
	material.roughness = 0.78
	capsule.material = material
	limb.mesh = capsule
	limb.rotation_degrees.z = 90.0
	root.add_child(limb)

	var seal := MeshInstance3D.new()
	seal.name = "SocketSeal"
	var seal_mesh := CylinderMesh.new()
	seal_mesh.top_radius = capsule.radius * 1.08
	seal_mesh.bottom_radius = capsule.radius * 1.08
	seal_mesh.height = 0.045
	var seal_material := StandardMaterial3D.new()
	seal_material.albedo_color = Color(0.94, 0.53, 0.08, 1.0)
	seal_material.metallic = 0.5
	seal_material.roughness = 0.32
	seal_mesh.material = seal_material
	seal.mesh = seal_mesh
	seal.rotation_degrees.z = 90.0
	seal.position.x = (capsule.height - capsule.radius * 2.0) * 0.5
	root.add_child(seal)
	return root


func get_public_instance_state(state: Dictionary) -> Dictionary:
	var result := super.get_public_instance_state(state)
	if limb_definition != null:
		result["limb_path"] = limb_definition.resource_path
		result["socket"] = int(limb_definition.slot)
	return result

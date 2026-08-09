@tool
class_name DroneCameraAttachmentDefinition
extends DroneAttachmentDefinition

#######################################################
# A zero-mass, core-mounted camera attachment. The definition is a regular drone attachment so
# gameplay loadouts can install it, while ServerDrone owns the actual Camera3D runtime node.
#######################################################

@export_group("Camera")
@export var mount_position := Vector3(0.0, 0.12, -0.38)
@export var mount_rotation_degrees := Vector3.ZERO
@export_range(1.0, 179.0, 0.1) var field_of_view_degrees := 72.0
@export_range(0.001, 10.0, 0.001, "or_greater") var near_clip_m := 0.03
@export_range(1.0, 10000.0, 1.0, "or_greater") var far_clip_m := 500.0
@export_enum("Keep Width", "Keep Height") var keep_aspect: int = Camera3D.KEEP_HEIGHT


func get_mass() -> float:
	# Installed camera attachments are intentionally massless. Loose RigidBody part instances
	# still receive the engine-safe minimum mass in ServerDronePart.
	return 0.0


func configure_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.position = mount_position
	camera.rotation_degrees = mount_rotation_degrees
	camera.fov = clampf(field_of_view_degrees, 1.0, 179.0)
	camera.near = maxf(near_clip_m, 0.001)
	camera.far = maxf(far_clip_m, camera.near + 0.001)
	camera.keep_aspect = keep_aspect

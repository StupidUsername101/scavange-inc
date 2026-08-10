class_name DroneProxy
extends Node3D

const PART_GEOMETRY := preload(
	"res://scripts/drones/drone_part_geometry.gd"
)
const SLOT_LAYOUT := preload(
	"res://scripts/drones/drone_slot_layout.gd"
)
const INTERP_SPEED := 12.0
const MAX_EXTRAPOLATION_TIME := 0.2
const MAX_ROTOR_VISUAL_SPEED := 42.0
const DEFAULT_CORE_SIZE := Vector3(0.65, 0.24, 0.65)
const DEFAULT_BATTERY_SIZE := Vector3(0.35, 0.12, 0.26)
const MINIMUM_ANGULAR_SPEED := 0.0001
const MAXIMUM_VISUAL_POWER_RATIO := 1.5

#######################################################
# Mirrors authoritative drone state on clients and updates its local visual presentation.
#######################################################

@onready var propeller_visuals: Array[Node3D] = [
	$Propellers/FrontLeft,
	$Propellers/FrontRight,
	$Propellers/BackLeft,
	$Propellers/BackRight,
]
@onready var battery_visual: MeshInstance3D = $Battery
@onready var core_visual: MeshInstance3D = $Core
@onready var core_guide: MeshInstance3D = $EditGuides/CoreGuide
@onready var battery_guide: MeshInstance3D = $EditGuides/BatteryGuide
@onready var propeller_guides: Array[MeshInstance3D] = [
	$EditGuides/Propeller0Guide,
	$EditGuides/Propeller1Guide,
	$EditGuides/Propeller2Guide,
	$EditGuides/Propeller3Guide,
]
@onready var ai_chip_visuals: Array[Node3D] = [
	$AIChips/Slot0,
	$AIChips/Slot1,
	$AIChips/Slot2,
	$AIChips/Slot3,
	$AIChips/Slot4,
	$AIChips/Slot5,
	$AIChips/Slot6,
	$AIChips/Slot7,
]
@onready var ai_chip_guides: Array[MeshInstance3D] = [
	$EditGuides/AIChip0Guide,
	$EditGuides/AIChip1Guide,
	$EditGuides/AIChip2Guide,
	$EditGuides/AIChip3Guide,
	$EditGuides/AIChip4Guide,
	$EditGuides/AIChip5Guide,
	$EditGuides/AIChip6Guide,
	$EditGuides/AIChip7Guide,
]
@onready var attachment_visuals: Array[Node3D] = [
	$Attachments/Slot0,
	$Attachments/Slot1,
	$Attachments/Slot2,
	$Attachments/Slot3,
]
@onready var attachment_guides: Array[MeshInstance3D] = [
	$EditGuides/Attachment0Guide,
	$EditGuides/Attachment1Guide,
	$EditGuides/Attachment2Guide,
	$EditGuides/Attachment3Guide,
]

var drone_id := -1
var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY
var target_linear_velocity := Vector3.ZERO
var target_angular_velocity := Vector3.ZERO
var time_since_last_state := 0.0
var power_ratio := 0.0
var activated := false
var battery_charge_ratio := 0.0
var core_definition_path := ""
var battery_definition_path := ""
var propeller_definition_paths: Array[String] = ["", "", "", ""]
var propeller_slot_transforms: Array[Transform3D] = []
var ai_chip_definition_paths: Array[String] = ["", "", "", "", "", "", "", ""]
var attachment_definition_paths: Array[String] = ["", "", "", ""]
var attachment_slot_transforms: Array[Transform3D] = []
var current_core_size := DEFAULT_CORE_SIZE
var current_battery_size := DEFAULT_BATTERY_SIZE


func _ready() -> void:
	target_position = global_position
	target_rotation = global_basis.get_rotation_quaternion()


func apply_server_state(state: Dictionary) -> void:
	var edit_preview := _apply_primary_state(state)
	_apply_propeller_state(state, edit_preview)
	_apply_ai_chip_state(state, edit_preview)
	_apply_attachment_state(state, edit_preview)
	_update_modular_slot_layout()
	_apply_attachment_weapon_aims(state)


func _apply_primary_state(state: Dictionary) -> bool:
	drone_id = state.get("drone_id", -1)
	target_position = state.get("pos", global_position)
	target_rotation = Quaternion.from_euler(
		state.get("rot", global_rotation)
	)
	target_linear_velocity = state.get("linear_velocity", Vector3.ZERO)
	target_angular_velocity = state.get("angular_velocity", Vector3.ZERO)
	activated = state.get("activated", false)
	power_ratio = state.get("power_ratio", 0.0)
	battery_charge_ratio = state.get("battery_charge_ratio", 0.0)
	visible = state.get("visible", true)
	var edit_preview: bool = state.get("edit_preview", false)
	var core_present: bool = state.get("core_present", true)
	var battery_present: bool = state.get("battery_present", false)
	_apply_core_definition(state.get("core_definition_path", ""))
	_apply_battery_definition(state.get("battery_definition_path", ""))
	core_visual.visible = core_present
	battery_visual.visible = battery_present
	core_guide.visible = edit_preview and not core_present
	battery_guide.visible = edit_preview and not battery_present
	time_since_last_state = 0.0
	return edit_preview


func _apply_propeller_state(
	state: Dictionary,
	edit_preview: bool
) -> void:
	var presence: Array = state.get("propellers", [])
	var definition_paths: Array = state.get(
		"propeller_definition_paths",
		[]
	)
	propeller_slot_transforms.clear()
	var mount_values: Array = state.get("propeller_slot_transforms", [])
	for mount_value: Variant in mount_values:
		if mount_value is Transform3D:
			propeller_slot_transforms.append(mount_value as Transform3D)
	for slot_index in range(propeller_visuals.size()):
		_apply_propeller_definition(
			slot_index,
			str(definition_paths[slot_index])
			if slot_index < definition_paths.size()
			else ""
		)
		# New server state carries exact creator-authored transforms. Fall back to the presence array
		# for older/partial state producers so a missing transform field cannot hide every rotor.
		var slot_supported: bool = (
			slot_index < propeller_slot_transforms.size()
			or (propeller_slot_transforms.is_empty() and slot_index < presence.size())
		)
		var propeller_present: bool = (
			slot_supported
			and slot_index < presence.size()
			and bool(presence[slot_index])
		)
		propeller_visuals[slot_index].visible = propeller_present
		propeller_guides[slot_index].visible = (
			edit_preview and slot_supported and not propeller_present
		)


func _apply_ai_chip_state(
	state: Dictionary,
	edit_preview: bool
) -> void:
	var ai_chip_slot_count := int(state.get("ai_chip_slot_count", 0))
	var ai_paths: Array = state.get("ai_chip_definition_paths", [])
	for slot_index in range(ai_chip_visuals.size()):
		var chip_path := (
			str(ai_paths[slot_index])
			if slot_index < ai_paths.size()
			else ""
		)
		_apply_dynamic_part_definition(
			ai_chip_visuals[slot_index],
			ai_chip_definition_paths,
			slot_index,
			chip_path
		)
		var chip_supported := slot_index < ai_chip_slot_count
		ai_chip_visuals[slot_index].visible = (
			chip_supported and not chip_path.is_empty()
		)
		ai_chip_guides[slot_index].visible = (
			edit_preview and chip_supported and chip_path.is_empty()
		)


func _apply_attachment_state(
	state: Dictionary,
	edit_preview: bool
) -> void:
	var attachment_slot_count := int(state.get("attachment_slot_count", 0))
	var attachment_paths: Array = state.get(
		"attachment_definition_paths",
		[]
	)
	attachment_slot_transforms.clear()
	var mount_values: Array = state.get("attachment_slot_transforms", [])
	for mount_value: Variant in mount_values:
		if mount_value is Transform3D:
			attachment_slot_transforms.append(mount_value as Transform3D)
	for slot_index in range(attachment_visuals.size()):
		var attachment_path := (
			str(attachment_paths[slot_index])
			if slot_index < attachment_paths.size()
			else ""
		)
		_apply_dynamic_part_definition(
			attachment_visuals[slot_index],
			attachment_definition_paths,
			slot_index,
			attachment_path
		)
		var attachment_supported := slot_index < attachment_slot_count
		attachment_visuals[slot_index].visible = (
			attachment_supported and not attachment_path.is_empty()
		)
		attachment_guides[slot_index].visible = (
			edit_preview and attachment_supported and attachment_path.is_empty()
		)


func _apply_attachment_weapon_aims(state: Dictionary) -> void:
	var weapon_aim_directions: Array = state.get("weapon_aim_directions", [])
	for slot_index: int in range(attachment_visuals.size()):
		_apply_weapon_aim(
			slot_index,
			(
				weapon_aim_directions[slot_index]
				if slot_index < weapon_aim_directions.size()
				else Vector3.FORWARD
			)
		)


func _process(delta: float) -> void:
	_update_propeller_visuals(delta)

	if multiplayer.is_server():
		var server_drone := Server.get_server_drone(drone_id)
		if is_instance_valid(server_drone):
			global_transform = server_drone.global_transform
			return

	time_since_last_state += delta
	var extrapolation_time := minf(
		time_since_last_state,
		MAX_EXTRAPOLATION_TIME
	)
	var predicted_position := (
		target_position
		+ target_linear_velocity * extrapolation_time
	)
	var predicted_rotation := target_rotation
	var angular_speed := target_angular_velocity.length()
	if angular_speed > MINIMUM_ANGULAR_SPEED:
		predicted_rotation = (
			Quaternion(
				target_angular_velocity / angular_speed,
				angular_speed * extrapolation_time
			)
			* target_rotation
		)

	var weight := clampf(INTERP_SPEED * delta, 0.0, 1.0)
	global_position += target_linear_velocity * delta
	global_position = global_position.lerp(predicted_position, weight)

	var current_rotation := global_basis.get_rotation_quaternion()
	global_basis = Basis(current_rotation.slerp(predicted_rotation, weight))


func _update_propeller_visuals(delta: float) -> void:
	var speed := MAX_ROTOR_VISUAL_SPEED * sqrt(clampf(
		power_ratio,
		0.0,
		MAXIMUM_VISUAL_POWER_RATIO
	))
	for slot_index in range(propeller_visuals.size()):
		var spin_direction := 1.0 if slot_index in [0, 3] else -1.0
		propeller_visuals[slot_index].rotate_y(
			speed * spin_direction * delta
		)


func _apply_core_definition(path: String) -> void:
	if path.is_empty() or path == core_definition_path:
		return
	var definition := load(path) as DroneCoreDefinition
	if definition == null:
		return
	core_definition_path = path
	core_visual.material_override = (
		PART_GEOMETRY.create_part_material(definition)
	)
	core_visual.scale = Vector3(
		definition.body_size.x / DEFAULT_CORE_SIZE.x,
		definition.body_size.y / DEFAULT_CORE_SIZE.y,
		definition.body_size.z / DEFAULT_CORE_SIZE.z
	)
	current_core_size = definition.body_size


func _apply_battery_definition(path: String) -> void:
	if path.is_empty() or path == battery_definition_path:
		return
	var definition := load(path) as DroneBatteryDefinition
	if definition == null:
		return
	battery_definition_path = path
	battery_visual.material_override = (
		PART_GEOMETRY.create_part_material(definition)
	)
	battery_visual.scale = Vector3(
		definition.body_size.x / DEFAULT_BATTERY_SIZE.x,
		definition.body_size.y / DEFAULT_BATTERY_SIZE.y,
		definition.body_size.z / DEFAULT_BATTERY_SIZE.z
	)
	current_battery_size = definition.body_size


func _apply_propeller_definition(slot_index: int, path: String) -> void:
	if (
		path.is_empty()
		or slot_index < 0
		or slot_index >= propeller_visuals.size()
		or path == propeller_definition_paths[slot_index]
	):
		return
	var definition := load(path) as DronePropellerDefinition
	if definition == null:
		return
	propeller_definition_paths[slot_index] = path
	var material := PART_GEOMETRY.create_part_material(definition)
	for child in propeller_visuals[slot_index].get_children():
		var mesh_visual := child as MeshInstance3D
		if mesh_visual == null:
			continue
		mesh_visual.material_override = material
		if mesh_visual.name == &"Blade":
			mesh_visual.scale.x = definition.rotor_radius / 0.19


func _apply_dynamic_part_definition(
	container: Node3D,
	path_cache: Array[String],
	slot_index: int,
	path: String
) -> void:
	if slot_index < 0 or slot_index >= path_cache.size():
		return
	if path == path_cache[slot_index]:
		return
	for child in container.get_children():
		child.queue_free()
	path_cache[slot_index] = path
	if path.is_empty():
		return
	var definition := load(path) as DronePartDefinition
	if definition == null:
		return
	container.add_child(PART_GEOMETRY.create_visual(definition))


func _update_modular_slot_layout() -> void:
	core_guide.scale = Vector3(
		current_core_size.x / 0.68,
		1.0,
		current_core_size.z / 0.68
	)
	var battery_position := Vector3(
		0.0,
		current_core_size.y * 0.5 + current_battery_size.y * 0.5,
		0.0
	)
	battery_visual.position = battery_position
	battery_guide.position = battery_position
	battery_guide.scale = Vector3(
		current_battery_size.x / 0.37,
		1.0,
		current_battery_size.z / 0.28
	)
	for slot_index in range(propeller_visuals.size()):
		var propeller_transform: Transform3D = (
			propeller_slot_transforms[slot_index]
			if slot_index < propeller_slot_transforms.size()
			else Transform3D(
				Basis.IDENTITY,
				SLOT_LAYOUT.get_propeller_position(slot_index, current_core_size)
			)
		)
		propeller_visuals[slot_index].transform = propeller_transform
		propeller_guides[slot_index].transform = propeller_transform
	for slot_index in range(ai_chip_visuals.size()):
		var chip_position := SLOT_LAYOUT.get_ai_chip_position(
			slot_index,
			current_core_size
		)
		ai_chip_visuals[slot_index].position = chip_position
		ai_chip_guides[slot_index].position = chip_position
	for slot_index in range(attachment_visuals.size()):
		var attachment_transform: Transform3D = (
			attachment_slot_transforms[slot_index]
			if slot_index < attachment_slot_transforms.size()
			else Transform3D(
				Basis.IDENTITY,
				SLOT_LAYOUT.get_attachment_position(slot_index, current_core_size)
			)
		)
		attachment_visuals[slot_index].transform = attachment_transform
		attachment_guides[slot_index].transform = attachment_transform


func _apply_weapon_aim(
	slot_index: int,
	local_direction: Vector3
) -> void:
	if (
		slot_index < 0
		or slot_index >= attachment_visuals.size()
		or local_direction.length_squared() <= 0.0001
	):
		return
	var path := attachment_definition_paths[slot_index]
	if path.is_empty():
		return
	var definition := load(path) as DroneWeaponDefinition
	if definition == null:
		# Non-weapon attachments keep the authored Core-slot basis applied by
		# _update_modular_slot_layout(). In particular, side-mounted articulated arms must not be
		# visually snapped back to identity orientation by the weapon-aim pass.
		return
	var direction := local_direction.normalized()
	var up := (
		Vector3.FORWARD
		if absf(direction.dot(Vector3.UP)) > 0.98
		else Vector3.UP
	)
	attachment_visuals[slot_index].basis = Basis.looking_at(direction, up)


func apply_projectile_muzzle_aim(
	slot_index: int,
	world_direction: Vector3
) -> void:
	if world_direction.length_squared() <= 0.0001:
		return
	_apply_weapon_aim(
		slot_index,
		global_basis.inverse() * world_direction.normalized()
	)

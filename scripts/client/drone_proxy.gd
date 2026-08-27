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
	drone_id = SafeVariant.integral_int_or(state.get("drone_id", -1), -1)
	var rigid_state: Dictionary = ClientProxyMotion.decode_rigid_state(
		state,
		global_position,
		global_rotation
	)
	target_position = rigid_state["position"]
	target_rotation = rigid_state["rotation"]
	target_linear_velocity = rigid_state["linear_velocity"]
	target_angular_velocity = rigid_state["angular_velocity"]
	activated = SafeVariant.bool_or(state.get("activated", false), false)
	power_ratio = SafeVariant.finite_float_or(state.get("power_ratio", 0.0), 0.0)
	battery_charge_ratio = SafeVariant.finite_float_or(
		state.get("battery_charge_ratio", 0.0),
		0.0
	)
	visible = SafeVariant.bool_or(state.get("visible", true), true)
	var edit_preview: bool = SafeVariant.bool_or(state.get("edit_preview", false), false)
	var core_present: bool = SafeVariant.bool_or(state.get("core_present", true), true)
	var battery_present: bool = SafeVariant.bool_or(state.get("battery_present", false), false)
	_apply_core_definition(str(state.get("core_definition_path", "")))
	_apply_battery_definition(str(state.get("battery_definition_path", "")))
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
	var presence: Array = SafeVariant.array_copy(state.get("propellers", []), false)
	var definition_paths: Array = SafeVariant.array_copy(
		state.get("propeller_definition_paths", []),
		false
	)
	var mount_values: Array = SafeVariant.array_copy(
		state.get("propeller_slot_transforms", []),
		false
	)
	_ensure_propeller_visual_capacity(maxi(
		presence.size(),
		maxi(definition_paths.size(), mount_values.size())
	))
	propeller_slot_transforms.clear()
	for slot_index: int in range(mount_values.size()):
		var fallback_transform: Transform3D = Transform3D(
			Basis.IDENTITY,
			SLOT_LAYOUT.get_propeller_position(slot_index, current_core_size)
		)
		propeller_slot_transforms.append(SafeVariant.transform3d_strict_or(
			mount_values[slot_index],
			fallback_transform
		))
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


func _ensure_propeller_visual_capacity(required_count: int) -> void:
	if required_count <= propeller_visuals.size() or propeller_visuals.is_empty():
		return
	var propeller_root: Node3D = $Propellers
	var guide_root: Node3D = $EditGuides
	var visual_template: Node3D = propeller_visuals[0]
	var guide_template: MeshInstance3D = propeller_guides[0]
	while propeller_visuals.size() < required_count:
		var slot_index: int = propeller_visuals.size()
		var visual: Node3D = visual_template.duplicate() as Node3D
		var guide: MeshInstance3D = guide_template.duplicate() as MeshInstance3D
		if visual == null or guide == null:
			return
		visual.name = "CreatorPropeller%d" % slot_index
		visual.visible = false
		propeller_root.add_child(visual)
		guide.name = "Propeller%dGuide" % slot_index
		guide.visible = false
		guide_root.add_child(guide)
		propeller_visuals.append(visual)
		propeller_guides.append(guide)
		propeller_definition_paths.append("")


func _apply_ai_chip_state(
	state: Dictionary,
	edit_preview: bool
) -> void:
	var ai_chip_slot_count: int = maxi(
		SafeVariant.integral_int_or(state.get("ai_chip_slot_count", 0), 0),
		0
	)
	var ai_paths: Array = SafeVariant.array_copy(
		state.get("ai_chip_definition_paths", []),
		false
	)
	var ai_snapshots: Array = SafeVariant.array_copy(
		state.get("ai_chip_definition_snapshots", []),
		false
	)
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
			chip_path,
			SafeVariant.dictionary_copy(
				ai_snapshots[slot_index] if slot_index < ai_snapshots.size() else {}
			)
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
	var attachment_slot_count: int = maxi(
		SafeVariant.integral_int_or(state.get("attachment_slot_count", 0), 0),
		0
	)
	var attachment_paths: Array = SafeVariant.array_copy(
		state.get("attachment_definition_paths", []),
		false
	)
	attachment_slot_transforms.clear()
	var mount_values: Array = SafeVariant.array_copy(
		state.get("attachment_slot_transforms", []),
		false
	)
	for slot_index: int in range(mini(mount_values.size(), attachment_visuals.size())):
		var fallback_transform: Transform3D = Transform3D(
			Basis.IDENTITY,
			SLOT_LAYOUT.get_attachment_position(slot_index, current_core_size)
		)
		attachment_slot_transforms.append(SafeVariant.transform3d_strict_or(
			mount_values[slot_index],
			fallback_transform
		))
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
	var weapon_aim_directions: Array = SafeVariant.array_copy(
		state.get("weapon_aim_directions", []),
		false
	)
	for slot_index: int in range(attachment_visuals.size()):
		var local_direction: Vector3 = Vector3.FORWARD
		if slot_index < weapon_aim_directions.size():
			local_direction = SafeVariant.vector3_strict_or(
				weapon_aim_directions[slot_index],
				Vector3.FORWARD
			)
		_apply_weapon_aim(slot_index, local_direction)


func _process(delta: float) -> void:
	_update_propeller_visuals(delta)

	if multiplayer.is_server():
		var server_drone := Server.get_server_drone(drone_id)
		if is_instance_valid(server_drone):
			global_transform = server_drone.global_transform
			return

	time_since_last_state += delta
	ClientProxyMotion.apply_smoothed_motion(
		self,
		delta,
		time_since_last_state,
		target_position,
		target_rotation,
		target_linear_velocity,
		target_angular_velocity,
		MAX_EXTRAPOLATION_TIME,
		INTERP_SPEED,
		MINIMUM_ANGULAR_SPEED
	)

func _update_propeller_visuals(delta: float) -> void:
	var speed := MAX_ROTOR_VISUAL_SPEED * sqrt(clampf(
		power_ratio,
		0.0,
		MAXIMUM_VISUAL_POWER_RATIO
	))
	for slot_index in range(propeller_visuals.size()):
		var spin_direction := 1.0 if posmod(slot_index, 4) in [0, 3] else -1.0
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
	path: String,
	public_snapshot: Dictionary = {}
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
	var definition: DronePartDefinition = (
		FinalizedMLChipStore.chip_from_public_snapshot(public_snapshot)
		if not public_snapshot.is_empty()
		else null
	)
	if definition == null and ResourceLoader.exists(path):
		definition = ResourceLoader.load(path) as DronePartDefinition
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

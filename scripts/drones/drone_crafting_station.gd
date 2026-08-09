extends Node3D

const EDIT_SESSION_SCRIPT := preload(
	"res://scripts/drones/drone_edit_session.gd"
)

#######################################################
# Implements the drone crafting station subsystem and keeps its gameplay data and behavior in
# one focused script.
#######################################################

var edit_session: RefCounted
var ignored_drone_ids: Dictionary = {}
var pending_drone: ServerDrone


func _ready() -> void:
	$EditArea.body_entered.connect(_on_body_entered)
	$EditArea.body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if edit_session != null:
		edit_session.call("anchor_preview")


func _on_body_entered(body: Node3D) -> void:
	var drone := body as ServerDrone
	if (
		drone == null
		or drone.is_edit_preview
		or edit_session != null
		or pending_drone != null
		or ignored_drone_ids.has(drone.drone_id)
	):
		return

	pending_drone = drone
	call_deferred("_begin_pending_session")


func _begin_pending_session() -> void:
	var drone := pending_drone
	pending_drone = null
	if (
		not is_instance_valid(drone)
		or edit_session != null
		or ignored_drone_ids.has(drone.drone_id)
		or not $EditArea.overlaps_body(drone)
	):
		return

	var candidate := EDIT_SESSION_SCRIPT.new(self, drone) as RefCounted
	if bool(candidate.call("begin")):
		edit_session = candidate


func _on_body_exited(body: Node3D) -> void:
	var drone := body as ServerDrone
	if drone != null:
		ignored_drone_ids.erase(drone.drone_id)


func handle_button(action: StringName, _player: ServerPlayer) -> void:
	if edit_session == null:
		return

	match action:
		&"accept":
			edit_session.call("accept")
		&"abort":
			edit_session.call("abort")
		&"rotate_x_positive":
			edit_session.call("rotate_preview", Vector3.RIGHT, 1.0)
		&"rotate_x_negative":
			edit_session.call("rotate_preview", Vector3.RIGHT, -1.0)
		&"rotate_y_positive":
			edit_session.call("rotate_preview", Vector3.UP, 1.0)
		&"rotate_y_negative":
			edit_session.call("rotate_preview", Vector3.UP, -1.0)
		&"reset_rotation":
			edit_session.call("reset_preview_rotation")


func handle_surface_primary_action(
	player: ServerPlayer,
	_hit: Dictionary
) -> void:
	if edit_session != null or pending_drone != null or player == null:
		return

	var held_part: RigidBody3D = Server.get_grabbed_body(
		player.grabber
	) as RigidBody3D
	if held_part == null or not held_part.is_in_group("drone_parts"):
		return

	var definition: DronePartDefinition = held_part.call(
		"get_drone_part_definition"
	) as DronePartDefinition
	if not definition is DroneCoreDefinition:
		return
	if (
		held_part.has_method("is_operational")
		and not bool(held_part.call("is_operational"))
	):
		return

	var candidate: RefCounted = EDIT_SESSION_SCRIPT.new(
		self,
		null
	) as RefCounted
	if bool(candidate.call("begin_from_core", player, held_part)):
		edit_session = candidate


func finish_edit_session(drone: ServerDrone) -> void:
	if is_instance_valid(drone):
		ignored_drone_ids[drone.drone_id] = true
	edit_session = null


func get_edit_anchor_transform() -> Transform3D:
	return $EditAnchor.global_transform


func get_part_output_transform(index: int) -> Transform3D:
	var result: Transform3D = $PartOutput.global_transform
	var column: int = index % 3
	var row: int = floori(float(index) / 3.0)
	result.origin += global_basis.x * (float(column) - 1.0) * 0.42
	result.origin += global_basis.z * float(row) * 0.38
	return result

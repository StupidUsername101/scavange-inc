extends StaticBody3D

const FRACTAL_LAYOUT := preload(
	"res://scripts/drones/inspection/fractal_terminal_layout.gd"
)

const SCREEN_CENTER := Vector2(0.0, 1.73)
const SCREEN_WORLD_SIZE := Vector2(2.68, 1.02)

#######################################################
# Implements the drone inspection station subsystem and keeps its gameplay data and behavior
# in one focused script.
#######################################################

@export var station_id := 1
@export var stat_interfaces: Array[Resource] = []
@export var part_anchor_path: NodePath = ^"PartAnchor"
@export var part_output_path: NodePath = ^"PartOutput"

@onready var part_anchor: Marker3D = get_node(part_anchor_path) as Marker3D
@onready var part_output: Marker3D = get_node(part_output_path) as Marker3D

var inserted_part: RigidBody3D
var report_document: Dictionary = {}
var view_paths_by_player_id: Dictionary = {}

var original_collision_layer := 1
var original_collision_mask := 1
var original_gravity_scale := 1.0
var original_freeze := false
var original_freeze_mode := RigidBody3D.FREEZE_MODE_STATIC


func _ready() -> void:
	add_to_group("drone_inspection_stations")
	_set_report_document(_idle_document())
	Server.register_inspection_station(station_id, self)


func _exit_tree() -> void:
	if is_instance_valid(inserted_part):
		_restore_part_physics(inserted_part)
	Server.unregister_inspection_station(station_id, self)


func _physics_process(_delta: float) -> void:
	if inserted_part != null and not is_instance_valid(inserted_part):
		inserted_part = null
		_set_report_document(_idle_document())


func server_primary_action(player: ServerPlayer, hit: Dictionary) -> void:
	if player == null:
		return

	var held_body: PhysicsBody3D = Server.get_grabbed_body(player.grabber)
	var held_part := held_body as RigidBody3D

	# Docking takes precedence over terminal navigation. The player can aim at
	# any solid portion of the scanner while holding a supported part.
	if not is_instance_valid(inserted_part) and held_part != null:
		if held_part.has_method("get_inspectable_definition"):
			_insert_part(held_part)
		else:
			_set_report_document(_message_document(
				"Unsupported object",
				"The cradle accepts catalogued parts and tools.",
				"Release this object and bring a drone part, rope or cable."
			))
		return

	if _is_terminal_hit(hit):
		_navigate_terminal(player.player_id, hit)
		return

	# Clicking the physical cradle ejects its current contents. The terminal
	# surface remains dedicated to navigating the recursive report.
	if is_instance_valid(inserted_part):
		_eject_inserted_part()


func _insert_part(part: RigidBody3D) -> void:
	if part == null or not is_instance_valid(part):
		return

	Server.release_grabs_for_body(part)

	original_collision_layer = part.collision_layer
	original_collision_mask = part.collision_mask
	original_gravity_scale = part.gravity_scale
	original_freeze = part.freeze
	original_freeze_mode = part.freeze_mode

	inserted_part = part
	part.set_meta("inspection_station_id", station_id)
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	part.gravity_scale = 0.0
	part.collision_layer = 0
	part.collision_mask = 0
	part.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	part.freeze = true
	part.global_transform = part_anchor.global_transform

	_set_report_document(_build_part_document(part))


func _eject_inserted_part() -> void:
	var part := inserted_part
	inserted_part = null
	if not is_instance_valid(part):
		_set_report_document(_idle_document())
		return

	_restore_part_physics(part)
	part.global_transform = part_output.global_transform
	part.linear_velocity = Vector3.ZERO
	part.angular_velocity = Vector3.ZERO
	if not part.freeze:
		part.apply_central_impulse(
			global_basis.z.normalized() * 0.18
			+ Vector3.UP * 0.08
		)

	_set_report_document(_idle_document())


func _restore_part_physics(part: RigidBody3D) -> void:
	part.remove_meta("inspection_station_id")
	part.collision_layer = original_collision_layer
	part.collision_mask = original_collision_mask
	part.gravity_scale = original_gravity_scale
	part.freeze_mode = original_freeze_mode
	part.freeze = original_freeze


func _build_part_document(part: RigidBody3D) -> Dictionary:
	var definition := part.call("get_inspectable_definition") as Resource
	if definition == null:
		return _message_document(
			"Read failure",
		"The inserted body has no inspectable definition.",
			"The physical object is present, but its data resource is missing."
		)

	var runtime_state: Dictionary = part.call("to_state_dict")
	for interface_resource: Resource in stat_interfaces:
		if (
			interface_resource != null
			and interface_resource.has_method("supports")
			and bool(interface_resource.call("supports", definition))
			and interface_resource.has_method("build_document")
		):
			var built_document: Dictionary = interface_resource.call(
				"build_document",
				definition,
				runtime_state
			)
			return built_document

	return {
		"title": str(definition.get("display_name")),
		"subtitle": "Unknown inspection interface",
		"values": [
			{"label": "Type", "value": "Unknown catalogued item"},
			{"label": "Resource", "value": MLBodyPartContract.resource_source_path(definition)},
		],
		"children": [],
	}


func _idle_document() -> Dictionary:
	return {
		"title": "Part scanner",
		"subtitle": "Cradle ready // left-click station controls",
		"values": [
			{"label": "Status", "value": "Ready"},
			{"label": "Primary", "value": "Left click"},
			{"label": "Hold item", "value": "E"},
			{"label": "Report model", "value": "Recursive"},
		],
		"children": [
			{
				"title": "Docking",
				"subtitle": "Insert or remove a physical part",
				"values": [
					{
						"label": "Insert",
						"value": "Hold a part or rope spool with E, then left click "
						+ "the scanner."
					},
					{
						"label": "Eject",
						"value": "Left click the cradle while a part is docked."
					},
				],
				"children": [],
			},
			{
				"title": "Terminal navigation",
				"subtitle": "Zoom through windows inside windows",
				"values": [
					{
						"label": "Zoom in",
						"value": "Left click any group box on the screen."
					},
					{
						"label": "Zoom out",
						"value": "Left click BACK in the upper-left corner."
					},
				],
				"children": [],
			},
		],
	}


func _message_document(
	title: String,
	subtitle: String,
	message: String
) -> Dictionary:
	return {
		"title": title,
		"subtitle": subtitle,
		"values": [
			{"label": "Scanner message", "value": message},
		],
		"children": [],
	}


func _set_report_document(document: Dictionary) -> void:
	report_document = document.duplicate(true)
	view_paths_by_player_id.clear()


func _is_terminal_hit(hit: Dictionary) -> bool:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position: Vector3 = to_local(world_position)
	return (
		absf(local_position.x - SCREEN_CENTER.x)
			<= SCREEN_WORLD_SIZE.x * 0.5
		and absf(local_position.y - SCREEN_CENTER.y)
			<= SCREEN_WORLD_SIZE.y * 0.5
		and local_position.z < -0.42
	)


func _navigate_terminal(player_id: int, hit: Dictionary) -> void:
	var screen_position: Vector2 = _hit_to_screen_position(hit)
	var path: Array = view_paths_by_player_id.get(player_id, []).duplicate()

	if FRACTAL_LAYOUT.is_back_position(screen_position):
		if not path.is_empty():
			path.pop_back()
		view_paths_by_player_id[player_id] = path
		return

	var current: Dictionary = _get_node_at_path(report_document, path)
	if current.is_empty():
		path.clear()
		current = report_document

	var children: Array = current.get("children", [])
	var child_index: int = FRACTAL_LAYOUT.get_child_index_at(
		screen_position,
		children.size()
	)
	if child_index >= 0:
		path.append(child_index)
		view_paths_by_player_id[player_id] = path


func _hit_to_screen_position(hit: Dictionary) -> Vector2:
	var world_position: Vector3 = hit.get("position", global_position)
	var local_position: Vector3 = to_local(world_position)
	var normalized_x: float = (
		local_position.x - (SCREEN_CENTER.x - SCREEN_WORLD_SIZE.x * 0.5)
	) / SCREEN_WORLD_SIZE.x
	var normalized_y: float = (
		(SCREEN_CENTER.y + SCREEN_WORLD_SIZE.y * 0.5) - local_position.y
	) / SCREEN_WORLD_SIZE.y
	return Vector2(
		clampf(normalized_x, 0.0, 1.0) * FRACTAL_LAYOUT.SCREEN_SIZE.x,
		clampf(normalized_y, 0.0, 1.0) * FRACTAL_LAYOUT.SCREEN_SIZE.y
	)


func _get_node_at_path(root: Dictionary, path: Array) -> Dictionary:
	var current := root
	for child_index_value: Variant in path:
		var child_index := int(child_index_value)
		var children: Array = current.get("children", [])
		if child_index < 0 or child_index >= children.size():
			return {}
		current = children[child_index]
	return current


func to_state_dict() -> Dictionary:
	var definition_path := ""
	var part_id := -1
	if is_instance_valid(inserted_part):
		# The scanner accepts both ServerDronePart and ServerItem bodies. Rope
		# spools are ServerItems, so their missing drone_part_id used to feed
		# null into int() and then call a drone-only definition method.
		var drone_part_id_value: Variant = inserted_part.get("drone_part_id")
		var item_id_value: Variant = inserted_part.get("item_id")
		if drone_part_id_value is int:
			part_id = drone_part_id_value
		elif item_id_value is int:
			part_id = item_id_value
		var definition := inserted_part.call(
			"get_inspectable_definition"
		) as Resource
		if definition != null:
			definition_path = MLBodyPartContract.resource_source_path(definition)

	return {
		"station_id": station_id,
		"occupied": is_instance_valid(inserted_part),
		"inserted_part_id": part_id,
		"definition_path": definition_path,
		"report_document": report_document,
		"view_paths": view_paths_by_player_id,
	}

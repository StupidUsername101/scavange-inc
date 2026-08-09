extends StaticBody3D

const CATALOG := preload("res://scripts/enemies/dev_zoo_catalog.gd")
const ENEMY_SCENE := preload("res://scenes/server/server_enemy.tscn")
const WALL_HEIGHT := 1.35
const WALL_THICKNESS := 0.22
const ENTRANCE_WIDTH := 3.2

#######################################################
# Owns authoritative dev zoo simulation and exposes the state required for replication and
# interaction.
#######################################################

var pen_descriptors: Array[Dictionary] = []
var enemies_by_slot: Dictionary[int, ServerEnemy] = {}
var player_ids_by_slot: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	var layout := CATALOG.build_layout()
	for raw_pen: Variant in layout.get("pens", []):
		var pen: Dictionary = raw_pen
		pen_descriptors.append(pen)
		var slot_index := int(pen["slot_index"])
		player_ids_by_slot[slot_index] = {}
		_build_pen_collision(pen)
		_build_activation_area(pen)
	call_deferred("_populate_all_pens")


func _exit_tree() -> void:
	for enemy: ServerEnemy in enemies_by_slot.values():
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies_by_slot.clear()


func _populate_all_pens() -> void:
	for descriptor: Dictionary in pen_descriptors:
		_spawn_enemy(int(descriptor["slot_index"]))


func _spawn_enemy(slot_index: int) -> void:
	if not is_inside_tree() or enemies_by_slot.has(slot_index):
		return
	if slot_index < 0 or slot_index >= pen_descriptors.size():
		return
	var descriptor: Dictionary = pen_descriptors[slot_index]
	var definition := load(str(descriptor["definition_path"])) as EnemyDefinition
	if definition == null:
		push_error(
			"Dev zoo failed to load %s" % str(descriptor["definition_path"])
		)
		return
	var enemy := ENEMY_SCENE.instantiate() as ServerEnemy
	if enemy == null:
		return
	enemy.configure(definition, slot_index)
	var center: Vector3 = descriptor["center"]
	enemy.position = center
	add_child(enemy)
	for player_id: int in _get_players_in_slot(slot_index).keys():
		enemy.add_activation_player(player_id)
	enemy.died.connect(
		_on_enemy_died.bind(slot_index, definition.respawn_delay_seconds),
		CONNECT_ONE_SHOT
	)
	enemies_by_slot[slot_index] = enemy


func _on_enemy_died(
	enemy: ServerEnemy,
	slot_index: int,
	respawn_delay: float
) -> void:
	if enemies_by_slot.get(slot_index) == enemy:
		enemies_by_slot.erase(slot_index)
	var timer := get_tree().create_timer(maxf(respawn_delay, 0.0))
	timer.timeout.connect(_spawn_enemy.bind(slot_index), CONNECT_ONE_SHOT)


func _on_activation_body_entered(body: Node3D, slot_index: int) -> void:
	var player := body as ServerPlayer
	if player == null:
		return
	var players := _get_players_in_slot(slot_index)
	players[player.player_id] = true
	player_ids_by_slot[slot_index] = players
	var exit_callback := _on_pen_player_tree_exiting.bind(
		player.player_id,
		slot_index
	)
	if not player.tree_exiting.is_connected(exit_callback):
		player.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	var enemy := enemies_by_slot.get(slot_index) as ServerEnemy
	if is_instance_valid(enemy):
		enemy.add_activation_player(player.player_id)


func _on_activation_body_exited(body: Node3D, slot_index: int) -> void:
	var player := body as ServerPlayer
	if player == null:
		return
	var exit_callback := _on_pen_player_tree_exiting.bind(
		player.player_id,
		slot_index
	)
	if player.tree_exiting.is_connected(exit_callback):
		player.tree_exiting.disconnect(exit_callback)
	_remove_player_from_slot(player.player_id, slot_index)


func _on_pen_player_tree_exiting(player_id: int, slot_index: int) -> void:
	_remove_player_from_slot(player_id, slot_index)


func _remove_player_from_slot(player_id: int, slot_index: int) -> void:
	var players := _get_players_in_slot(slot_index)
	players.erase(player_id)
	player_ids_by_slot[slot_index] = players
	var enemy := enemies_by_slot.get(slot_index) as ServerEnemy
	if is_instance_valid(enemy):
		enemy.remove_activation_player(player_id)


func _get_players_in_slot(slot_index: int) -> Dictionary:
	return player_ids_by_slot.get(slot_index, {})


func _build_activation_area(pen: Dictionary) -> void:
	var size: Vector2 = pen["size"]
	var center: Vector3 = pen["center"]
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, 3.0, size.y)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 1.5, 0.0)
	var area := Area3D.new()
	area.name = "Pen%dActivation" % int(pen["slot_index"])
	area.position = center
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	area.add_child(collision)
	add_child(area)
	var slot_index := int(pen["slot_index"])
	area.body_entered.connect(_on_activation_body_entered.bind(slot_index))
	area.body_exited.connect(_on_activation_body_exited.bind(slot_index))


func _build_pen_collision(pen: Dictionary) -> void:
	var size: Vector2 = pen["size"]
	var center: Vector3 = pen["center"]
	_add_box_collision(
		"Pen%dBack" % int(pen["slot_index"]),
		center + Vector3(0.0, WALL_HEIGHT * 0.5, size.y * 0.5),
		Vector3(size.x, WALL_HEIGHT, WALL_THICKNESS)
	)
	_add_box_collision(
		"Pen%dLeft" % int(pen["slot_index"]),
		center + Vector3(-size.x * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y)
	)
	_add_box_collision(
		"Pen%dRight" % int(pen["slot_index"]),
		center + Vector3(size.x * 0.5, WALL_HEIGHT * 0.5, 0.0),
		Vector3(WALL_THICKNESS, WALL_HEIGHT, size.y)
	)
	var front_segment_width := (size.x - ENTRANCE_WIDTH) * 0.5
	for side: float in [-1.0, 1.0]:
		_add_box_collision(
			"Pen%dFront%s" % [
				int(pen["slot_index"]),
				"L" if side < 0.0 else "R",
			],
			center + Vector3(
				side * (ENTRANCE_WIDTH + front_segment_width) * 0.5,
				WALL_HEIGHT * 0.5,
				-size.y * 0.5
			),
			Vector3(front_segment_width, WALL_HEIGHT, WALL_THICKNESS)
		)


func _add_box_collision(
	node_name: String,
	local_position: Vector3,
	size: Vector3
) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = local_position
	collision.shape = shape
	add_child(collision)

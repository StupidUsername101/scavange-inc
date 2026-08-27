class_name ServerEnemy
extends CharacterBody3D

const DEFAULT_GRAVITY := 9.8

#######################################################
# Owns authoritative enemy simulation and exposes the state required for replication and
# interaction.
#######################################################

signal died(enemy: ServerEnemy)

@export var definition: EnemyDefinition

var enemy_id := -1
var zoo_slot_index := -1
var current_health := 0.0
var active := false
var alive := true
var roam_center := Vector3.ZERO
var target_player_id := -1
var activation_player_ids: Dictionary[int, bool] = {}
var behavior_controller := EnemyBehaviorController.new()
var physical_limb_rig: EnemyPhysicalLimbRig3D
var cached_server_service: Node


func _server_service() -> Node:
	if is_instance_valid(cached_server_service):
		return cached_server_service
	var tree := get_tree()
	if tree != null:
		cached_server_service = tree.root.get_node_or_null("Server")
	return cached_server_service


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_stop_on_slope = true
	floor_snap_length = 0.18
	_apply_definition()
	if definition == null:
		push_error("ServerEnemy requires an EnemyDefinition")
		return
	current_health = definition.max_health
	roam_center = global_position
	var server_service := _server_service()
	if server_service == null:
		push_error("ServerEnemy requires the Server autoload")
		return
	enemy_id = int(server_service.call("register_enemy", self))


func _exit_tree() -> void:
	if enemy_id >= 0:
		var server_service := _server_service()
		if server_service != null:
			server_service.call("unregister_enemy", enemy_id)
		enemy_id = -1


func configure(
	new_definition: EnemyDefinition,
	new_zoo_slot_index: int
) -> void:
	definition = new_definition
	zoo_slot_index = new_zoo_slot_index
	if is_inside_tree():
		_apply_definition()
		current_health = definition.max_health if definition != null else 0.0
		roam_center = global_position


func server_physics_tick(delta: float) -> void:
	if definition == null:
		return
	if not alive:
		if physical_limb_rig != null:
			physical_limb_rig.server_physics_tick(delta, Vector3.ZERO)
		return
	if not active:
		return

	var intent := behavior_controller.evaluate(
		delta,
		definition.behavior,
		global_position,
		roam_center,
		_build_behavior_candidates()
	)
	target_player_id = int(intent.get("target_id", -1))
	_apply_movement_intent(intent, delta)
	if bool(intent.get("attack_requested", false)):
		_apply_attack(intent)
	if physical_limb_rig != null:
		physical_limb_rig.server_physics_tick(delta, velocity)


func set_active(value: bool) -> void:
	var next_active := value and alive
	if active == next_active:
		return
	active = next_active
	if not active:
		velocity = Vector3.ZERO
		target_player_id = -1
	if physical_limb_rig != null:
		physical_limb_rig.set_runtime_active(active)
	if enemy_id >= 0:
		var server_service := _server_service()
		if server_service != null:
			server_service.call("set_enemy_spatial_active", enemy_id, active)


func add_activation_player(player_id: int) -> void:
	if player_id < 0:
		return
	activation_player_ids[player_id] = true
	set_active(true)


func remove_activation_player(player_id: int) -> void:
	activation_player_ids.erase(player_id)
	set_active(not activation_player_ids.is_empty())


func is_ai_targetable() -> bool:
	return active and alive and current_health > 0.0


func get_ai_target_snapshot() -> Dictionary:
	if not is_ai_targetable() or definition == null:
		return {}
	return {
		"target_id": enemy_id,
		"kind": &"enemy",
		"position": global_position + Vector3.UP * definition.target_height,
		"velocity": velocity,
		"faction_id": definition.faction_id,
	}


func apply_damage(amount: float) -> void:
	if not is_ai_targetable():
		return
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		_die()


func get_limb_state() -> Array[Dictionary]:
	if physical_limb_rig == null:
		return []
	return physical_limb_rig.get_limb_state()


func to_state_dict() -> Dictionary:
	return {
		"enemy_id": enemy_id,
		"definition_path": (
			definition.resource_path if definition != null else ""
		),
		"pos": global_position,
		"rot": global_rotation,
		"velocity": velocity,
		"health": current_health,
		"max_health": definition.max_health if definition != null else 0.0,
		"active": active,
		"alive": alive,
		"target_player_id": target_player_id,
		"attack_phase": behavior_controller.attack_phase,
		"limbs": get_limb_state(),
		"zoo_slot_index": zoo_slot_index,
	}


func _apply_movement_intent(intent: Dictionary, delta: float) -> void:
	var behavior: EnemyBehaviorDefinition = definition.behavior
	var desired_velocity: Vector3 = intent.get("desired_velocity", Vector3.ZERO)
	desired_velocity.y = 0.0
	var acceleration: float = behavior.acceleration if behavior != null else 20.0
	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var next_horizontal: Vector3 = current_horizontal.move_toward(
		desired_velocity,
		acceleration * delta
	)
	velocity.x = next_horizontal.x
	velocity.z = next_horizontal.z
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= DEFAULT_GRAVITY * delta

	var desired_forward: Vector3 = intent.get("desired_forward", Vector3.ZERO)
	desired_forward.y = 0.0
	if desired_forward.length_squared() > 0.0001:
		var target_yaw := atan2(-desired_forward.x, -desired_forward.z)
		var turn_speed: float = (
			behavior.turn_speed_radians if behavior != null else 8.0
		)
		rotation.y = lerp_angle(
			rotation.y,
			target_yaw,
			clampf(turn_speed * delta, 0.0, 1.0)
		)
	move_and_slide()


func _apply_attack(intent: Dictionary) -> void:
	var target := intent.get("target_body") as Node
	if (
		target == null
		or not is_instance_valid(target)
		or definition.behavior == null
		or not target.has_method("apply_damage")
	):
		return
	target.call("apply_damage", definition.behavior.attack_damage)


func _build_behavior_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var server_service := _server_service()
	if server_service == null:
		return result
	var stale_ids: Array[int] = []
	for player_id: int in activation_player_ids.keys():
		var player := server_service.call("get_server_player", player_id) as ServerPlayer
		if not is_instance_valid(player):
			stale_ids.append(player_id)
			continue
		result.append({
			"target_id": player_id,
			"body": player,
			"position": player.global_position,
			"velocity": player.velocity,
		})
	for stale_id: int in stale_ids:
		activation_player_ids.erase(stale_id)
	return result


func _die() -> void:
	if not alive:
		return
	alive = false
	active = false
	velocity = Vector3.ZERO
	target_player_id = -1
	if enemy_id >= 0:
		var server_service := _server_service()
		if server_service != null:
			server_service.call("set_enemy_spatial_active", enemy_id, false)
	if physical_limb_rig != null:
		physical_limb_rig.set_ragdoll(true)
	var linger: float = (
		definition.death_linger_seconds if definition != null else 0.0
	)
	if linger <= 0.0:
		call_deferred("_finish_death")
		return
	var timer := get_tree().create_timer(linger)
	timer.timeout.connect(_finish_death, CONNECT_ONE_SHOT)


func _finish_death() -> void:
	if not is_inside_tree():
		return
	died.emit(self)
	queue_free()


func _apply_definition() -> void:
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		add_child(collision)
	if physical_limb_rig != null:
		physical_limb_rig.queue_free()
		physical_limb_rig = null
	if definition == null:
		collision.shape = null
		return
	collision.shape = definition.create_collision_shape()
	collision.position.y = definition.get_collision_size().y * 0.5
	if definition.physical_anatomy != null:
		physical_limb_rig = EnemyPhysicalLimbRig3D.new()
		add_child(physical_limb_rig)
		physical_limb_rig.configure(self, definition.physical_anatomy)
		physical_limb_rig.set_runtime_active(active)

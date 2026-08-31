class_name ServerEnemy
extends CharacterBody3D

const DEFAULT_GRAVITY := 9.8
const HUMANOID_AUDIO_SOURCE_ID_BASE := 1_200_000_000
const HUMANOID_ACOUSTIC_LISTENER_ID_BASE := 1_100_000_000
const HUMANOID_FOOTSTEP_MAX_DISTANCE := 34.0
const HUMANOID_FOOTSTEP_PRIORITY := 0.56
const SENSE_EYE_HEIGHT := 1.52
const STEERING_PROBE_HEIGHT := 0.86
const STEERING_PROBE_DISTANCE := 1.15
const STEERING_PROBE_SIDE_ANGLE := deg_to_rad(52.0)
const EPSILON := 0.000001

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
var flute_runner_controller := FluteRunnerBehaviorController.new()
var destructible_anatomy: EnemyDestructibleAnatomy
var humanoid_gait := PlayerGait.new()
var expression_clock := 0.0
var sensed_target: ServerPlayer
var sensed_target_visible := false
var sensed_target_audible := false
var sensed_target_position := Vector3.ZERO
var sense_remaining := 0.0
var _sense_query := PhysicsRayQueryParameters3D.new()
var _steering_query := PhysicsRayQueryParameters3D.new()
var _foot_query := PhysicsRayQueryParameters3D.new()
var _flute_source_modifier: AcousticPathModifier
var _flute_stream_length_seconds := 0.0
var _flute_playback_started_msec := 0
var _flute_playback_revision := 1
var _last_humanoid_step_sequence := 0


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
	_configure_runtime_queries()
	var server_service := _server_service()
	if server_service == null:
		push_error("ServerEnemy requires the Server autoload")
		return
	enemy_id = int(server_service.call("register_enemy", self))
	_configure_destructible_anatomy()
	_configure_flute_runner()
	if _is_flute_runner():
		humanoid_gait.set_expression_identity(40000 + maxi(enemy_id, 0))
	if definition.starts_active:
		set_active(true)


func _exit_tree() -> void:
	if enemy_id >= 0:
		var server_service := _server_service()
		if server_service != null:
			var acoustic_service := server_service.get("acoustic_service") as ServerAcousticService
			if acoustic_service != null and _is_flute_runner():
				acoustic_service.forget_continuous_source(get_continuous_audio_source_id())
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
		_configure_destructible_anatomy()
		_configure_flute_runner()


func server_physics_tick(delta: float) -> void:
	if definition == null:
		return
	if not alive:
		if physical_limb_rig != null:
			physical_limb_rig.server_physics_tick(delta, Vector3.ZERO)
		return
	if not active:
		return
	if _is_flute_runner():
		_server_flute_runner_tick(delta)
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
		sensed_target = null
		sensed_target_visible = false
		sensed_target_audible = false
		sensed_target_position = Vector3.ZERO
	elif _is_flute_runner() and _flute_playback_started_msec <= 0:
		_flute_playback_started_msec = Time.get_ticks_msec()
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


func apply_damage_event(event: DamageEvent) -> Dictionary:
	if not is_ai_targetable() or event == null:
		return {"changed": false, "reason": &"inactive_or_dead"}
	if destructible_anatomy == null:
		apply_damage(event.energy)
		return {
			"changed": event.energy > 0.0,
			"geometry_changed": false,
			"reason": &"scalar_enemy_damage",
		}
	var result := destructible_anatomy.apply_damage_event(event, global_transform)
	if not bool(result.get("changed", false)):
		return result
	current_health = minf(
		current_health,
		definition.max_health * destructible_anatomy.aggregate_remaining_fraction
	)
	if destructible_anatomy.is_dead():
		current_health = 0.0
		_die()
	return result


func get_limb_state() -> Array[Dictionary]:
	if physical_limb_rig == null:
		return []
	return physical_limb_rig.get_limb_state()


func append_kick_guidance_spots(output: Array[Vector3]) -> void:
	# Kicks consume these once as soft anatomical hints. The authoritative hit still has to meet the
	# enemy's physics body, so adding detail here cannot turn a near miss into a locked-on attack.
	if physical_limb_rig != null:
		physical_limb_rig.append_kick_guidance_spots(output)
	var body_height := (
		definition.get_collision_size().y
		if definition != null
		else 1.0
	)
	output.append(global_position + Vector3.UP * body_height * 0.28)
	output.append(global_position + Vector3.UP * body_height * 0.58)
	output.append(global_position + Vector3.UP * body_height * 0.86)


func to_state_dict() -> Dictionary:
	var is_humanoid := (
		definition != null
		and definition.presentation_type == EnemyDefinition.PresentationType.HUMANOID
	)
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
		"attack_phase": (
			0.0 if _is_flute_runner() else behavior_controller.attack_phase
		),
		"limbs": get_limb_state(),
		"zoo_slot_index": zoo_slot_index,
		"presentation_type": (
			definition.presentation_type if definition != null else 0
		),
		"on_floor": is_on_floor(),
		"gait_cycle": humanoid_gait.get_cycle() if is_humanoid else 0.0,
		"gait_active": humanoid_gait.active if is_humanoid else false,
		"gait_stride_distance": humanoid_gait.stride_distance if is_humanoid else 0.0,
		"expression_clock": expression_clock,
		"awareness_state": (
			flute_runner_controller.state_name() if _is_flute_runner() else &"legacy"
		),
		"target_position": (
			sensed_target_position
			if is_instance_valid(sensed_target)
			else flute_runner_controller.last_known_position
		),
		"has_target_position": (
			is_instance_valid(sensed_target)
			or flute_runner_controller.has_last_known_position
		),
		"flute_pose_weight": 1.0 if _is_flute_runner() and active and alive else 0.0,
		"anatomy_destruction": (
			destructible_anatomy.state_dict()
			if destructible_anatomy != null
			else {}
		),
	}


func get_continuous_audio_source_id() -> int:
	return HUMANOID_AUDIO_SOURCE_ID_BASE + maxi(enemy_id, 0)


func build_flute_listener_state(
	listener_id: int,
	listener_position: Vector3,
	acoustic_service: ServerAcousticService,
	listener_collision_rid: RID = RID()
) -> Dictionary:
	var runner := _flute_definition()
	if (
		runner == null
		or not active
		or not alive
		or acoustic_service == null
		or runner.flute_song_path.is_empty()
		or not ResourceLoader.exists(runner.flute_song_path, "AudioStream")
	):
		return {}
	var source_position := _flute_source_world_position()
	var output_level_db := clampf(
		runner.flute_output_level_db,
		AcousticPropagationGraph.MIN_SOURCE_LEVEL_DB,
		AcousticPropagationGraph.MAX_SOURCE_LEVEL_DB
	)
	var scaled_hearing_distance := AcousticPropagationGraph.level_scaled_hearing_distance(
		runner.flute_hearing_distance,
		# Like RadioItemDefinition.maximum_hearing_distance, this is authored at the instrument's
		# calibrated base output. There is no user amplifier control to scale it a second time.
		0.0
	)
	var exclusions: Array[RID] = [get_rid()]
	if listener_collision_rid.is_valid():
		exclusions.append(listener_collision_rid)
	var maximum_world_distance := acoustic_service.source_hearing_distance_upper_bound(
		scaled_hearing_distance,
		source_position,
		get_continuous_audio_source_id(),
		exclusions
	)
	if listener_position.distance_squared_to(source_position) > maximum_world_distance * maximum_world_distance:
		return {}
	var result := acoustic_service.calculate_listener_result(
		listener_id,
		listener_position,
		source_position,
		scaled_hearing_distance,
		_flute_source_modifier,
		AcousticPropagationGraph.DEFAULT_REFERENCE_DISTANCE,
		true,
		exclusions,
		get_continuous_audio_source_id()
	)
	if not bool(result.get("audible", false)):
		return {}
	result.erase("audible")
	var elapsed := _flute_elapsed_seconds()
	var travel_delay := float(result.get("travel_delay_seconds", 0.0))
	result["item_id"] = get_continuous_audio_source_id()
	result["revision"] = _flute_playback_revision
	result["song_path"] = runner.flute_song_path
	result["playback_offset_seconds"] = maxf(elapsed - travel_delay, 0.0)
	result["start_delay_seconds"] = maxf(travel_delay - elapsed, 0.0)
	result["stream_length_seconds"] = _flute_stream_length_seconds
	result["program_normalization_gain_db"] = 0.0
	result["program_reference_gain_db"] = 0.0
	result["volume_db"] = float(result.get("volume_db", 0.0)) + output_level_db
	result["priority"] = runner.flute_priority
	result["distortion_mode"] = 0
	result["distortion_drive"] = 0.0
	result["distortion_keep_hf_hz"] = 20000.0
	result["distortion_post_gain_db"] = 0.0
	result["receiver_static_enabled"] = false
	result["static_mix_db"] = -60.0
	return result


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


func _server_flute_runner_tick(delta: float) -> void:
	var runner := _flute_definition()
	if runner == null:
		return
	expression_clock += maxf(delta, 0.0)
	sense_remaining -= maxf(delta, 0.0)
	if sense_remaining <= 0.0:
		sense_remaining = maxf(runner.sense_interval_seconds, 0.02)
		_sense_flute_runner_target(runner)

	var target_valid := is_instance_valid(sensed_target)
	var observed_target_id := sensed_target.player_id if target_valid else -1
	var observed_position := sensed_target_position if target_valid else Vector3.ZERO
	var observed_velocity := (
		sensed_target.velocity
		if target_valid and sensed_target_visible
		else Vector3.ZERO
	)
	flute_runner_controller.update(
		delta,
		runner,
		global_position,
		-global_basis.z,
		roam_center,
		observed_target_id,
		observed_position,
		observed_velocity,
		sensed_target_visible,
		sensed_target_audible,
		target_valid
	)
	target_player_id = flute_runner_controller.target_id
	_apply_flute_runner_movement(runner, delta)
	_update_humanoid_gait(delta)
	_update_flute_program_loop()


func _sense_flute_runner_target(runner: FluteRunnerDefinition) -> void:
	sensed_target_visible = false
	sensed_target_audible = false
	sensed_target_position = Vector3.ZERO
	var server_service := _server_service()
	if server_service == null:
		sensed_target = null
		return
	var candidate_ids: Array[int]
	if definition.automatically_target_players:
		candidate_ids = server_service.call("get_active_player_ids") as Array[int]
	else:
		candidate_ids.assign(activation_player_ids.keys())
	var sight_range_squared := runner.sight_range * runner.sight_range
	var nearest_visible: ServerPlayer
	var nearest_visible_distance_squared := INF
	for player_id: int in candidate_ids:
		var player := server_service.call("get_server_player", player_id) as ServerPlayer
		if not is_instance_valid(player):
			continue
		var distance_squared := global_position.distance_squared_to(player.global_position)
		if (
			distance_squared <= sight_range_squared
			and distance_squared < nearest_visible_distance_squared
			and _has_line_of_sight_to(player)
		):
			nearest_visible = player
			nearest_visible_distance_squared = distance_squared
	if is_instance_valid(nearest_visible):
		sensed_target = nearest_visible
		sensed_target_visible = true
		sensed_target_position = nearest_visible.global_position
		return
	var heard: Dictionary = server_service.call(
		"get_recent_player_acoustic_stimulus",
		HUMANOID_ACOUSTIC_LISTENER_ID_BASE + maxi(enemy_id, 0),
		global_position + Vector3.UP * SENSE_EYE_HEIGHT,
		candidate_ids,
		runner.heard_memory_seconds,
		runner.hearing_range,
		get_rid()
	)
	if heard.is_empty():
		sensed_target = null
		return
	var heard_player_id := int(heard.get("player_id", -1))
	sensed_target = server_service.call("get_server_player", heard_player_id) as ServerPlayer
	if is_instance_valid(sensed_target):
		sensed_target_audible = true
		sensed_target_position = heard.get("position", sensed_target.global_position)


func _has_line_of_sight_to(player: ServerPlayer) -> bool:
	if not is_instance_valid(player) or not is_inside_tree() or get_world_3d() == null:
		return false
	_sense_query.from = global_position + Vector3.UP * SENSE_EYE_HEIGHT
	_sense_query.to = player.get_audio_listener_position()
	_sense_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_sense_query)
	return hit.is_empty() or hit.get("collider") == player


func _apply_flute_runner_movement(
	runner: FluteRunnerDefinition,
	delta: float
) -> void:
	var desired_velocity := flute_runner_controller.desired_velocity
	desired_velocity.y = 0.0
	if destructible_anatomy != null:
		desired_velocity *= destructible_anatomy.mobility_scale()
	var desired_speed := desired_velocity.length()
	var desired_direction := (
		desired_velocity / desired_speed if desired_speed > EPSILON else Vector3.ZERO
	)
	var steering := _resolve_local_steering(desired_direction)
	var steering_blocked := (
		desired_speed > 0.1
		and steering.length_squared() <= EPSILON
	)
	if desired_speed > EPSILON and steering.length_squared() > EPSILON:
		desired_velocity = steering.normalized() * desired_speed
	var current_horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var acceleration := (
		runner.acceleration
		if desired_velocity.length_squared() > current_horizontal.length_squared()
		else runner.braking_acceleration
	)
	var next_horizontal := current_horizontal.move_toward(
		desired_velocity,
		maxf(acceleration, 0.0) * maxf(delta, 0.0)
	)
	velocity.x = next_horizontal.x
	velocity.z = next_horizontal.z
	if is_on_floor():
		velocity.y = -0.1
	else:
		velocity.y -= DEFAULT_GRAVITY * maxf(delta, 0.0)

	var facing := desired_direction
	if next_horizontal.length_squared() > 0.04:
		facing = next_horizontal.normalized()
	if facing.length_squared() > EPSILON:
		var target_yaw := atan2(-facing.x, -facing.z)
		rotation.y = lerp_angle(
			rotation.y,
			target_yaw,
			clampf(runner.turn_speed_radians * maxf(delta, 0.0), 0.0, 1.0)
		)
	var incoming_velocity := velocity
	move_and_slide()
	flute_runner_controller.report_steering_blocked(steering_blocked, delta)
	_process_flute_runner_contacts(runner, incoming_velocity)


func _resolve_local_steering(desired_direction: Vector3) -> Vector3:
	if desired_direction.length_squared() <= EPSILON:
		return Vector3.ZERO
	if not is_inside_tree() or get_world_3d() == null:
		return desired_direction
	var origin := global_position + Vector3.UP * STEERING_PROBE_HEIGHT
	if not _steering_direction_blocked(origin, desired_direction):
		return desired_direction
	var left := desired_direction.rotated(Vector3.UP, STEERING_PROBE_SIDE_ANGLE)
	var right := desired_direction.rotated(Vector3.UP, -STEERING_PROBE_SIDE_ANGLE)
	var left_blocked := _steering_direction_blocked(origin, left)
	var right_blocked := _steering_direction_blocked(origin, right)
	if left_blocked and right_blocked:
		return Vector3.ZERO
	if left_blocked:
		return right
	if right_blocked:
		return left
	# The controller alternates its fumble sign deterministically; using it here prevents two clear
	# detours from causing left/right indecision on successive physics frames.
	return left if flute_runner_controller.fumble_direction_sign < 0.0 else right


func _steering_direction_blocked(origin: Vector3, direction: Vector3) -> bool:
	_steering_query.from = origin
	_steering_query.to = origin + direction.normalized() * STEERING_PROBE_DISTANCE
	_steering_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_steering_query)
	if hit.is_empty():
		return false
	# A player is an intended physical tackle contact, not static navigation geometry.
	return not hit.get("collider") is ServerPlayer


func _process_flute_runner_contacts(
	runner: FluteRunnerDefinition,
	incoming_velocity: Vector3
) -> void:
	var horizontal_incoming := Vector3(
		incoming_velocity.x,
		0.0,
		incoming_velocity.z
	)
	var incoming_speed := horizontal_incoming.length()
	if incoming_speed <= EPSILON:
		return
	var travel_direction := horizontal_incoming / incoming_speed
	for collision_index: int in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var player := collision.get_collider() as ServerPlayer
		if not is_instance_valid(player):
			continue
		var relative_velocity := horizontal_incoming - Vector3(
			player.velocity.x,
			0.0,
			player.velocity.z
		)
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var facing_dot := (
			travel_direction.dot(to_player.normalized())
			if to_player.length_squared() > EPSILON
			else 1.0
		)
		if not flute_runner_controller.can_tackle(
			relative_velocity.length(),
			facing_dot,
			runner
		):
			continue
		player.apply_damage(runner.tackle_damage)
		player.receive_enemy_tackle(
			travel_direction,
			clampf(
				inverse_lerp(
					runner.tackle_minimum_speed,
					runner.chase_speed,
					relative_velocity.length()
				),
				0.65,
				1.0
			),
			runner.tackle_impulse
		)
		flute_runner_controller.consume_tackle(runner)
		velocity -= travel_direction * runner.tackle_impulse * 0.32
		return


func _update_humanoid_gait(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var completed_steps := humanoid_gait.advance(
		speed,
		is_on_floor(),
		speed >= PlayerGait.RUN_PROFILE_SPEED_THRESHOLD,
		delta
	)
	if completed_steps <= 0:
		return
	for _step: int in range(completed_steps):
		_emit_humanoid_footstep(speed)
	_last_humanoid_step_sequence = humanoid_gait.step_sequence


func _emit_humanoid_footstep(speed: float) -> void:
	var server_service := _server_service()
	if server_service == null or not is_inside_tree() or get_world_3d() == null:
		return
	var side := posmod(humanoid_gait.step_sequence, 2)
	var side_sign := -1.0 if side == PlayerGait.FootSide.LEFT else 1.0
	var origin := (
		global_position
		+ global_basis.x * side_sign * PlayerGait.FOOT_STANCE_HALF_WIDTH
		+ Vector3.UP * 0.34
	)
	_foot_query.from = origin
	_foot_query.to = origin - Vector3.UP * 0.78
	_foot_query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_foot_query)
	var surface := PhysicalSurface.SOIL
	var source_position := global_position
	if not hit.is_empty():
		surface = PhysicalSurface.from_collider(hit.get("collider"), surface)
		source_position = hit.get("position", source_position)
	server_service.call(
		"emit_spatial_sound",
		PhysicalSurface.footstep_sound_id(surface),
		source_position,
		HUMANOID_FOOTSTEP_MAX_DISTANCE,
		PlayerGait.get_footstep_volume_db_for_motion(
			speed,
			maxi(enemy_id, 0) + 40000,
			humanoid_gait.step_sequence
		) - 1.2,
		null,
		HUMANOID_FOOTSTEP_PRIORITY
	)


func _configure_runtime_queries() -> void:
	for query: PhysicsRayQueryParameters3D in [
		_sense_query,
		_steering_query,
		_foot_query,
	]:
		query.collision_mask = CharacterContactLayers.MOVEMENT_SURFACE
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.hit_from_inside = false


func _configure_flute_runner() -> void:
	if not _is_flute_runner():
		return
	flute_runner_controller.reset(global_position)
	humanoid_gait.set_expression_identity(maxi(enemy_id, 0) + 40000)
	var runner := _flute_definition()
	_flute_source_modifier = (
		runner.flute_source_modifier.sanitized_copy()
		if runner.flute_source_modifier != null
		else AcousticPathModifier.identity()
	)
	_flute_stream_length_seconds = 0.0
	if ResourceLoader.exists(runner.flute_song_path, "AudioStream"):
		var stream := load(runner.flute_song_path) as AudioStream
		if stream != null:
			_flute_stream_length_seconds = maxf(stream.get_length(), 0.05)
	_flute_playback_started_msec = Time.get_ticks_msec()
	_flute_playback_revision = maxi(_flute_playback_revision, 1)


func _configure_destructible_anatomy() -> void:
	if definition == null or definition.destructible_anatomy == null:
		destructible_anatomy = null
		return
	destructible_anatomy = EnemyDestructibleAnatomy.new().configure(
		enemy_id,
		definition.destructible_anatomy
	)


func _update_flute_program_loop() -> void:
	if _flute_stream_length_seconds <= 0.05:
		return
	if _flute_elapsed_seconds() < _flute_stream_length_seconds - 0.02:
		return
	_flute_playback_started_msec = Time.get_ticks_msec()
	_flute_playback_revision += 1


func _flute_elapsed_seconds() -> float:
	if _flute_playback_started_msec <= 0:
		return 0.0
	return maxf(
		float(Time.get_ticks_msec() - _flute_playback_started_msec) / 1000.0,
		0.0
	)


func _flute_source_world_position() -> Vector3:
	return global_position + Vector3.UP * 1.58 - global_basis.z * 0.11


func _is_flute_runner() -> bool:
	return definition != null and definition.flute_runner != null


func _flute_definition() -> FluteRunnerDefinition:
	return definition.flute_runner if definition != null else null


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
		destructible_anatomy = null
		collision.shape = null
		return
	collision.shape = definition.create_collision_shape()
	collision.position.y = definition.get_collision_size().y * 0.5
	if definition.physical_anatomy != null:
		physical_limb_rig = EnemyPhysicalLimbRig3D.new()
		add_child(physical_limb_rig)
		physical_limb_rig.configure(self, definition.physical_anatomy)
		physical_limb_rig.set_runtime_active(active)

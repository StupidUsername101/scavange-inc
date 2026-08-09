class_name TurretPhysicalBody3D
extends Node3D

signal shot_requested(request: Dictionary)
signal died(body: TurretPhysicalBody3D)

const BODY_PROFILE_ID = "stationary_turret_v1"

@export var loadout: TurretLoadout
@export var auto_start_active = true
@export var training_invulnerable = true

var base_body: StaticBody3D
var rotating_head_body: StaticBody3D
var barrel_body: StaticBody3D
var base_mesh_instance: MeshInstance3D
var head_mesh_instance: MeshInstance3D
var barrel_mesh_instance: MeshInstance3D
var yaw_pivot: Node3D
var pitch_pivot: Node3D
var muzzle: Marker3D
var yaw_angle_radians = 0.0
var pitch_angle_radians = 0.0
var yaw_velocity_radians_per_second = 0.0
var pitch_velocity_radians_per_second = 0.0
var yaw_drive_command = 0.0
var pitch_drive_command = 0.0
var trigger_command = 0.0
var shot_cooldown_seconds = 0.0
var active = true
var alive = true
var current_health = 0.0
var shots_fired_total = 0
var shots_fired_since_consume = 0
var viable_shots_since_consume = 0
var bad_shots_since_consume = 0
var hits_total = 0
var hits_since_consume = 0
var damage_dealt_since_consume = 0.0
var misses_since_consume = 0
var rng = RandomNumberGenerator.new()
var visual_group_color: Color = Color.WHITE
var visual_group_material: StandardMaterial3D


func _ready() -> void:
	if loadout == null or not loadout.ensure_contract():
		push_error("TurretPhysicalBody3D requires an accepted or preset base + gun body.")
		active = false
		alive = false
		return
	current_health = loadout.maximum_health()
	active = auto_start_active
	rng.seed = get_instance_id() * 104729
	_build_body()


func configure(new_loadout: TurretLoadout) -> void:
	loadout = MLBodyPartContract.deep_duplicate_resource(new_loadout) as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		active = false
		alive = false
		return
	current_health = loadout.maximum_health()
	alive = true
	active = auto_start_active
	if is_inside_tree():
		_build_body()


func set_visual_color(color: Color) -> void:
	visual_group_color = Color(
		clampf(color.r, 0.0, 1.0),
		clampf(color.g, 0.0, 1.0),
		clampf(color.b, 0.0, 1.0),
		1.0
	)
	_remove_legacy_training_label()
	_apply_visual_group_material()


func reset_body(spawn_transform: Transform3D, random_seed: int) -> bool:
	# reset_body() is called from trainers/evaluators after the node is already inside the tree.
	# Never assume _ready() succeeded: a missing/invalid loadout must fail closed instead of
	# dereferencing Nil and producing a second, less useful error.
	if loadout == null or not loadout.ensure_contract():
		active = false
		alive = false
		current_health = 0.0
		return false
	global_transform = spawn_transform
	yaw_angle_radians = 0.0
	pitch_angle_radians = 0.0
	yaw_velocity_radians_per_second = 0.0
	pitch_velocity_radians_per_second = 0.0
	yaw_drive_command = 0.0
	pitch_drive_command = 0.0
	trigger_command = 0.0
	shot_cooldown_seconds = 0.0
	alive = true
	active = true
	current_health = loadout.maximum_health()
	shots_fired_since_consume = 0
	viable_shots_since_consume = 0
	bad_shots_since_consume = 0
	hits_since_consume = 0
	damage_dealt_since_consume = 0.0
	misses_since_consume = 0
	rng.seed = random_seed
	_apply_joint_transforms()
	return true


func submit_ml_action(action: Dictionary) -> bool:
	var commands = TurretMLAction.packed_commands(action)
	return submit_raw_commands(commands)


func submit_raw_commands(commands: PackedFloat64Array) -> bool:
	if commands.size() != TurretMLAction.ACTION_COUNT or not alive:
		return false
	for command: float in commands:
		if not is_finite(command):
			return false
	yaw_drive_command = clampf(commands[TurretMLAction.YAW_INDEX], -1.0, 1.0)
	pitch_drive_command = clampf(commands[TurretMLAction.PITCH_INDEX], -1.0, 1.0)
	trigger_command = clampf((commands[TurretMLAction.TRIGGER_INDEX] + 1.0) * 0.5, 0.0, 1.0)
	return true


func submit_manual_controls(yaw_drive: float, pitch_drive: float, trigger: float) -> bool:
	return submit_ml_action({
		"schema_version": TurretMLAction.SCHEMA_VERSION,
		"yaw_drive": clampf(yaw_drive, -1.0, 1.0),
		"pitch_drive": clampf(pitch_drive, -1.0, 1.0),
		"trigger": clampf(trigger, 0.0, 1.0),
	})


func _physics_process(delta: float) -> void:
	if not active or not alive or loadout == null:
		return
	var safe_delta = maxf(delta, 0.0)
	shot_cooldown_seconds = maxf(shot_cooldown_seconds - safe_delta, 0.0)
	_integrate_yaw(safe_delta)
	_integrate_pitch(safe_delta)
	_apply_joint_transforms()
	if trigger_command >= loadout.gun.trigger_threshold and shot_cooldown_seconds <= 0.0:
		_fire()


func _integrate_yaw(delta: float) -> void:
	var maximum_speed = deg_to_rad(loadout.base.maximum_yaw_speed_degrees_per_second)
	var acceleration = deg_to_rad(loadout.base.yaw_acceleration_degrees_per_second_squared)
	var braking = deg_to_rad(loadout.base.yaw_braking_degrees_per_second_squared)
	if absf(yaw_drive_command) > 0.001:
		yaw_velocity_radians_per_second += yaw_drive_command * acceleration * delta
	else:
		yaw_velocity_radians_per_second = move_toward(
			yaw_velocity_radians_per_second,
			0.0,
			braking * delta
		)
	yaw_velocity_radians_per_second = clampf(
		yaw_velocity_radians_per_second,
		-maximum_speed,
		maximum_speed
	)
	yaw_angle_radians = wrapf(
		yaw_angle_radians + yaw_velocity_radians_per_second * delta,
		-PI,
		PI
	)


func _integrate_pitch(delta: float) -> void:
	var gun = loadout.gun
	var maximum_speed = deg_to_rad(gun.maximum_pitch_speed_degrees_per_second)
	var acceleration = deg_to_rad(gun.pitch_acceleration_degrees_per_second_squared)
	var braking = deg_to_rad(gun.pitch_braking_degrees_per_second_squared)
	if absf(pitch_drive_command) > 0.001:
		pitch_velocity_radians_per_second += pitch_drive_command * acceleration * delta
	else:
		pitch_velocity_radians_per_second = move_toward(
			pitch_velocity_radians_per_second,
			0.0,
			braking * delta
		)
	pitch_velocity_radians_per_second = clampf(
		pitch_velocity_radians_per_second,
		-maximum_speed,
		maximum_speed
	)
	var minimum_pitch = deg_to_rad(gun.minimum_pitch_degrees)
	var maximum_pitch = deg_to_rad(gun.maximum_pitch_degrees)
	pitch_angle_radians = clampf(
		pitch_angle_radians + pitch_velocity_radians_per_second * delta,
		minimum_pitch,
		maximum_pitch
	)
	if (
		is_equal_approx(pitch_angle_radians, minimum_pitch)
		and pitch_velocity_radians_per_second < 0.0
	) or (
		is_equal_approx(pitch_angle_radians, maximum_pitch)
		and pitch_velocity_radians_per_second > 0.0
	):
		pitch_velocity_radians_per_second = 0.0


func _apply_joint_transforms() -> void:
	if is_instance_valid(yaw_pivot):
		yaw_pivot.rotation = Vector3(0.0, yaw_angle_radians, 0.0)
	if is_instance_valid(pitch_pivot):
		pitch_pivot.rotation = Vector3(pitch_angle_radians, 0.0, 0.0)


func _fire() -> void:
	if not is_instance_valid(muzzle):
		return
	shot_cooldown_seconds = loadout.gun.seconds_between_shots
	shots_fired_total += 1
	shots_fired_since_consume += 1
	var direction = muzzle.global_basis * Vector3.FORWARD
	var spread = deg_to_rad(loadout.gun.spread_degrees)
	if spread > 0.0:
		direction = direction.rotated(muzzle.global_basis.x, rng.randf_range(-spread, spread))
		direction = direction.rotated(muzzle.global_basis.y, rng.randf_range(-spread, spread))
	shot_requested.emit({
		"origin": muzzle.global_position,
		"direction": direction.normalized(),
		"speed_mps": loadout.gun.projectile_speed_mps,
		"damage": loadout.gun.projectile_damage,
		"maximum_range_m": loadout.gun.maximum_range_m,
		"shooter": self,
	})


func notify_projectile_hit(damage: float) -> void:
	hits_total += 1
	hits_since_consume += 1
	damage_dealt_since_consume += maxf(damage, 0.0)


func notify_projectile_missed() -> void:
	misses_since_consume += 1


func notify_shot_viability(viable: bool) -> void:
	if viable:
		viable_shots_since_consume += 1
	else:
		bad_shots_since_consume += 1


func consume_weapon_events() -> Dictionary:
	var result = {
		"shots_fired": shots_fired_since_consume,
		"viable_shots": viable_shots_since_consume,
		"bad_shots": bad_shots_since_consume,
		"hits": hits_since_consume,
		"damage_dealt": damage_dealt_since_consume,
		"misses": misses_since_consume,
	}
	shots_fired_since_consume = 0
	viable_shots_since_consume = 0
	bad_shots_since_consume = 0
	hits_since_consume = 0
	damage_dealt_since_consume = 0.0
	misses_since_consume = 0
	return result


func aim_direction_world() -> Vector3:
	return (
		(muzzle.global_basis * Vector3.FORWARD).normalized()
		if is_instance_valid(muzzle)
		else (global_basis * Vector3.FORWARD).normalized()
	)


func muzzle_position_world() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) else global_position


func cooldown_ready_ratio() -> float:
	return 1.0 - clampf(
		shot_cooldown_seconds / maxf(loadout.gun.seconds_between_shots, 0.01),
		0.0,
		1.0
	)


func apply_damage(amount: float) -> void:
	if training_invulnerable or not alive:
		return
	current_health = maxf(current_health - maxf(amount, 0.0), 0.0)
	if current_health <= 0.0:
		alive = false
		active = false
		died.emit(self)


func is_body_alive() -> bool:
	return alive and current_health > 0.0


func camera_anchor_transform() -> Transform3D:
	return (
		Transform3D(yaw_pivot.global_basis, yaw_pivot.global_position)
		if is_instance_valid(yaw_pivot)
		else global_transform
	)


func hardware_signature() -> String:
	return loadout.hardware_signature() if loadout != null else ""


func _build_body() -> void:
	# Rebuilding a paused group must not leave queued children with duplicate names in the same
	# frame. Detach them immediately; queue_free still performs the safe end-of-frame deletion.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	base_mesh_instance = null
	head_mesh_instance = null
	barrel_mesh_instance = null

	base_body = StaticBody3D.new()
	base_body.name = "StationaryBase"
	base_body.collision_layer = 1
	base_body.collision_mask = 0
	add_child(base_body)
	var base_collision = CollisionShape3D.new()
	var base_shape = BoxShape3D.new()
	base_shape.size = loadout.base.footprint_size
	base_collision.shape = base_shape
	base_collision.position.y = loadout.base.footprint_size.y * 0.5
	base_body.add_child(base_collision)
	var base_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = loadout.base.footprint_size
	base_mesh.mesh = box
	base_mesh.position = base_collision.position
	base_body.add_child(base_mesh)
	base_mesh_instance = base_mesh

	yaw_pivot = Node3D.new()
	yaw_pivot.name = "YawPivot"
	yaw_pivot.position.y = loadout.base.head_center_height_m
	add_child(yaw_pivot)
	rotating_head_body = StaticBody3D.new()
	rotating_head_body.name = "RotatingHeadBody"
	rotating_head_body.collision_layer = 1
	rotating_head_body.collision_mask = 0
	yaw_pivot.add_child(rotating_head_body)
	var head_collision = CollisionShape3D.new()
	var head_shape = CylinderShape3D.new()
	head_shape.radius = loadout.base.rotating_head_radius_m
	head_shape.height = loadout.base.rotating_head_height_m
	head_collision.shape = head_shape
	rotating_head_body.add_child(head_collision)
	var head_mesh = MeshInstance3D.new()
	var head_cylinder = CylinderMesh.new()
	head_cylinder.top_radius = loadout.base.rotating_head_radius_m
	head_cylinder.bottom_radius = loadout.base.rotating_head_radius_m
	head_cylinder.height = loadout.base.rotating_head_height_m
	head_mesh.mesh = head_cylinder
	rotating_head_body.add_child(head_mesh)
	head_mesh_instance = head_mesh

	pitch_pivot = Node3D.new()
	pitch_pivot.name = "PitchPivot"
	pitch_pivot.position = loadout.gun.barrel_mount_offset
	yaw_pivot.add_child(pitch_pivot)
	barrel_body = StaticBody3D.new()
	barrel_body.name = "BarrelBody"
	barrel_body.collision_layer = 1
	barrel_body.collision_mask = 0
	pitch_pivot.add_child(barrel_body)
	var barrel_collision = CollisionShape3D.new()
	var barrel_shape = CylinderShape3D.new()
	barrel_shape.radius = loadout.gun.barrel_radius_m
	barrel_shape.height = loadout.gun.barrel_length_m
	barrel_collision.shape = barrel_shape
	barrel_collision.rotation.x = PI * 0.5
	barrel_collision.position.z = -loadout.gun.barrel_length_m * 0.5
	barrel_body.add_child(barrel_collision)
	var barrel_mesh = MeshInstance3D.new()
	var barrel = CylinderMesh.new()
	barrel.top_radius = loadout.gun.barrel_radius_m
	barrel.bottom_radius = loadout.gun.barrel_radius_m
	barrel.height = loadout.gun.barrel_length_m
	barrel_mesh.mesh = barrel
	barrel_mesh.rotation.x = PI * 0.5
	barrel_mesh.position.z = -loadout.gun.barrel_length_m * 0.5
	barrel_body.add_child(barrel_mesh)
	barrel_mesh_instance = barrel_mesh
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position.z = -loadout.gun.barrel_length_m
	pitch_pivot.add_child(muzzle)
	_apply_visual_group_material()
	_apply_joint_transforms()


func _apply_visual_group_material() -> void:
	if visual_group_material == null:
		visual_group_material = StandardMaterial3D.new()
		visual_group_material.roughness = 0.58
		visual_group_material.metallic = 0.12
	visual_group_material.albedo_color = visual_group_color
	var mesh_instances: Array[MeshInstance3D] = [
		base_mesh_instance,
		head_mesh_instance,
		barrel_mesh_instance,
	]
	for mesh_instance: MeshInstance3D in mesh_instances:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_override = visual_group_material


func _remove_legacy_training_label() -> void:
	var label: Node = get_node_or_null("TrainingGroupLabel")
	if label == null:
		return
	remove_child(label)
	label.queue_free()

class_name TrainingEvaluationTurretSupport
extends RefCounted

#######################################################
# Shared deterministic threat-turret plumbing for candidate evaluators. Evaluation jobs own case
# layout, entity identities and scoring; this helper only builds/aims the same hidden physical
# threat and creates its hidden projectiles so those mechanics cannot drift by body family.
#######################################################


static func create_hidden_threat_turret(
	parent: Node,
	node_name: String,
	position_world: Vector3,
	reset_seed: int
) -> Dictionary:
	if parent == null or not position_world.is_finite():
		return {"error": "invalid threat-turret parent or position"}
	var preset: TurretLoadout = MLBodyPresetLibrary.stationary_turret_loadout()
	if preset == null or not preset.ensure_contract():
		return {"error": "could not load the stationary threat-turret preset"}
	var runtime_loadout: TurretLoadout = (
		MLBodyPartContract.deep_duplicate_resource(preset) as TurretLoadout
	)
	if runtime_loadout == null or not runtime_loadout.ensure_contract():
		return {"error": "could not duplicate the stationary threat-turret preset"}
	var turret: TurretPhysicalBody3D = TurretPhysicalBody3D.new()
	turret.name = node_name
	# _ready() validates the loadout, so assign it before entering the tree.
	turret.loadout = runtime_loadout
	turret.auto_start_active = true
	turret.training_invulnerable = true
	turret.visible = false
	parent.add_child(turret)
	if not turret.reset_body(
		Transform3D(Basis.IDENTITY, position_world),
		reset_seed
	):
		turret.queue_free()
		return {"error": "threat turret could not initialize its accepted body"}
	return {"turret": turret}


static func register_hidden_threat_turret(
	turret: TurretPhysicalBody3D,
	adapter: TurretTrainingCombatantAdapter,
	entity_spatial_hash: ServerSpatialHash3D,
	shot_callable: Callable
) -> bool:
	if (
		not is_instance_valid(turret)
		or adapter == null
		or entity_spatial_hash == null
		or not shot_callable.is_valid()
	):
		return false
	entity_spatial_hash.register_entity(
		adapter.spatial_key(),
		turret,
		adapter.entity_kind,
		adapter.entity_id,
		adapter.metadata()
	)
	if not turret.shot_requested.is_connected(shot_callable):
		turret.shot_requested.connect(shot_callable)
	return true


static func aim_and_fire(turret: TurretPhysicalBody3D, target_position_world: Vector3) -> void:
	if not is_instance_valid(turret) or turret.loadout == null or turret.loadout.gun == null:
		return
	if not target_position_world.is_finite():
		return
	var direction_world: Vector3 = target_position_world - turret.global_position
	if direction_world.length_squared() <= 0.000001:
		return
	var local_direction: Vector3 = turret.global_basis.inverse() * direction_world.normalized()
	var horizontal: float = sqrt(
		local_direction.x * local_direction.x + local_direction.z * local_direction.z
	)
	turret.yaw_angle_radians = atan2(-local_direction.x, -local_direction.z)
	turret.pitch_angle_radians = clampf(
		atan2(local_direction.y, maxf(horizontal, 0.000001)),
		deg_to_rad(turret.loadout.gun.minimum_pitch_degrees),
		deg_to_rad(turret.loadout.gun.maximum_pitch_degrees)
	)
	turret.yaw_velocity_radians_per_second = 0.0
	turret.pitch_velocity_radians_per_second = 0.0
	turret._apply_joint_transforms()
	turret.submit_manual_controls(0.0, 0.0, 1.0)


static func create_hidden_projectile(
	parent: Node,
	request: Dictionary,
	owner_adapter: TurretTrainingCombatantAdapter,
	entity_spatial_hash: ServerSpatialHash3D,
	wall_spatial_hash: DroneTrainingWallSpatialHash
) -> TurretTrainingProjectile3D:
	if (
		parent == null
		or owner_adapter == null
		or entity_spatial_hash == null
		or wall_spatial_hash == null
	):
		return null
	var projectile: TurretTrainingProjectile3D = TurretTrainingProjectile3D.new()
	parent.add_child(projectile)
	if not projectile.configure(
		request,
		owner_adapter,
		entity_spatial_hash,
		wall_spatial_hash
	):
		projectile.queue_free()
		return null
	projectile.visible = false
	return projectile

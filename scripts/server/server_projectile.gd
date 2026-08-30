class_name ServerProjectile
extends Node3D

const WORLD_GRAVITY := 9.8
const MINIMUM_MOTION_LENGTH_SQUARED := 0.000001
const MAX_STALE_DESTRUCTIBLE_HITS_PER_TICK := 8
# Keep the acoustic ray origin outside the collider it just struck. Starting exactly on the
# contact plane makes the propagation ray immediately re-hit that surface and falsely treats an
# exposed impact as sound transmitted through a wall.
const IMPACT_SOUND_SURFACE_OFFSET := 0.045
# Impacts still use path occlusion and room DSP, but skip a second pressure-wave bake after every
# gunshot. This keeps automatic fire bounded without making impacts local-only.
const IMPACT_PRESSURE_STRENGTH := 0.0
const PHYSICAL_SURFACE := preload("res://scripts/audio/physical_surface.gd")
const IMPACT_RESPONSE := preload("res://scripts/audio/physical_impact_response.gd")

#######################################################
# Advances an authoritative projectile, performs swept collision, and applies damage and
# impulse on impact.
#######################################################

var projectile_id := -1
var profile: Dictionary = {}
var velocity := Vector3.ZERO
var launch_direction := Vector3.FORWARD
var distance_traveled := 0.0
var excluded_rids: Array[RID] = []
var source_kind: StringName = &"unknown"
var source_id := -1
var source_slot := -1
var resolved := false
var despawn_callback: Callable


func configure(
	new_projectile_id: int,
	new_profile: Dictionary,
	origin: Vector3,
	direction: Vector3,
	inherited_velocity: Vector3,
	exclusions: Array,
	new_source_kind: StringName,
	new_source_id: int,
	new_source_slot: int,
	new_despawn_callback: Callable = Callable()
) -> void:
	projectile_id = new_projectile_id
	profile = BallisticProjectileDefinition.normalize_profile(new_profile)
	global_position = origin
	launch_direction = direction.normalized()
	velocity = (
		launch_direction * float(profile["muzzle_velocity"])
		+ inherited_velocity
	)
	excluded_rids.clear()
	for value: Variant in exclusions:
		if value is RID:
			excluded_rids.append(value)
	source_kind = new_source_kind
	source_id = new_source_id
	source_slot = new_source_slot
	despawn_callback = new_despawn_callback


func server_physics_tick(delta: float) -> void:
	if resolved or not is_inside_tree():
		return

	velocity += (
		Vector3.DOWN
		* WORLD_GRAVITY
		* float(profile.get("gravity_scale", 0.0))
		* delta
	)
	var start := global_position
	var motion := velocity * delta
	var remaining_range := maxf(
		float(profile.get(
			"maximum_range",
			BallisticProjectileDefinition.MIN_MAXIMUM_RANGE
		)) - distance_traveled,
		0.0
	)
	if remaining_range <= MINIMUM_MOTION_LENGTH_SQUARED:
		_resolve()
		return
	if (
		motion.length() >= remaining_range
		and motion.length_squared() > MINIMUM_MOTION_LENGTH_SQUARED
	):
		motion = motion.normalized() * remaining_range
	var finish := start + motion
	var step_distance := start.distance_to(finish)
	var hit := _first_current_physics_hit(start, finish)
	if not hit.is_empty():
		global_position = hit.get("position", finish)
		_resolve_impact(hit)
		return

	global_position = finish
	distance_traveled += step_distance
	if distance_traveled >= float(profile.get(
		"maximum_range",
		BallisticProjectileDefinition.MIN_MAXIMUM_RANGE
	)):
		_resolve()


func _resolve_impact(hit: Dictionary) -> void:
	var collider := hit.get("collider") as Node
	var hit_position: Vector3 = hit.get("position", global_position)
	var hit_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	if collider != null and collider.has_method("apply_damage_event"):
		collider.call("apply_damage_event", _create_damage_event(hit_position, hit_normal))
	elif collider != null and collider.has_method("apply_damage"):
		collider.call("apply_damage", float(profile.get("damage", 0.0)))

	var rigid_body := collider as RigidBody3D
	if rigid_body != null:
		var direction := velocity.normalized()
		var impulse := (
			direction * float(profile.get("impact_impulse", 0.0))
		)
		hit_position = hit.get(
			"position",
			rigid_body.global_position
		)
		rigid_body.apply_impulse(
			impulse,
			hit_position - rigid_body.global_position
		)
	_emit_impact_sound(collider, hit_position, hit_normal)
	_resolve()


func _first_current_physics_hit(start: Vector3, finish: Vector3) -> Dictionary:
	var tick_exclusions := excluded_rids.duplicate()
	for _attempt: int in range(MAX_STALE_DESTRUCTIBLE_HITS_PER_TICK):
		var query := PhysicsRayQueryParameters3D.create(start, finish)
		query.exclude = tick_exclusions
		query.collide_with_areas = false
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider := hit.get("collider") as Node
		if (
			collider == null
			or not collider.has_method("accepts_current_sdf_hit")
			or bool(collider.call(
				"accepts_current_sdf_hit",
				hit.get("position", finish),
				motion_direction(start, finish)
			))
		):
			return hit
		var rid: RID = hit.get("rid", RID())
		if not rid.is_valid():
			return hit
		tick_exclusions.append(rid)
	return {}


func _create_damage_event(hit_position: Vector3, hit_normal: Vector3) -> DamageEvent:
	var speed_ratio := clampf(
		velocity.length() / maxf(
			float(profile.get("muzzle_velocity", BallisticProjectileDefinition.MIN_MUZZLE_VELOCITY)),
			BallisticProjectileDefinition.MIN_MUZZLE_VELOCITY
		),
		0.0,
		2.0
	)
	var volume_id := &"world"
	var direction := motion_direction(Vector3.ZERO, velocity)
	return DamageEvent.from_dict({
		"event_id": projectile_id,
		"sequence": projectile_id,
		"source_kind": source_kind,
		"source_id": source_id,
		"world_position": hit_position,
		"normal": hit_normal,
		"direction": direction,
		"brush_kind": DamageEvent.BRUSH_CAPSULE,
		"radius": float(profile.get(
			"destruction_radius",
			BallisticProjectileDefinition.DEFAULT_DESTRUCTION_RADIUS
		)),
		"length": float(profile.get(
			"penetration_depth",
			BallisticProjectileDefinition.DEFAULT_PENETRATION_DEPTH
		)),
		"energy": float(profile.get(
			"destruction_energy",
			profile.get("damage", 0.0)
		)) * speed_ratio * speed_ratio,
		"impulse": float(profile.get("impact_impulse", 0.0)),
		"penetration": float(profile.get(
			"penetration_depth",
			BallisticProjectileDefinition.DEFAULT_PENETRATION_DEPTH
		)),
		"damage_tags": profile.get(
			"damage_tags",
			PackedStringArray(["ballistic"])
		),
		"seed": DamageEvent.deterministic_seed(
			volume_id,
			projectile_id,
			source_id,
			source_slot
		),
		"timestamp_tick": Engine.get_physics_frames(),
	})


static func motion_direction(start: Vector3, finish: Vector3) -> Vector3:
	var motion := finish - start
	return (
		motion.normalized()
		if motion.length_squared() > MINIMUM_MOTION_LENGTH_SQUARED
		else Vector3.FORWARD
	)


static func impact_sound_id_for_profile(value: Dictionary) -> StringName:
	var sound_id: StringName = value.get(
		"impact_sound_id",
		BallisticProjectileDefinition.DEFAULT_IMPACT_SOUND_ID
	)
	return (
		sound_id
		if not sound_id.is_empty()
		else BallisticProjectileDefinition.DEFAULT_IMPACT_SOUND_ID
	)


static func impact_excitation_for_profile(
	value: Dictionary,
	impact_speed: float
) -> float:
	var reference_speed := maxf(
		float(value.get(
			"muzzle_velocity",
			BallisticProjectileDefinition.DEFAULT_MUZZLE_VELOCITY
		)),
		BallisticProjectileDefinition.MIN_MUZZLE_VELOCITY
	)
	var speed_ratio := clampf(maxf(impact_speed, 0.0) / reference_speed, 0.0, 1.25)
	# Kinetic energy is proportional to velocity squared. The authored strength stands in for
	# projectile mass/shape until those become explicit ammunition properties.
	return clampf(
		float(value.get(
			"impact_response_strength",
			BallisticProjectileDefinition.DEFAULT_IMPACT_RESPONSE_STRENGTH
		)) * speed_ratio * speed_ratio,
		0.0,
		1.0
	)


func _emit_impact_sound(
	collider: Object,
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	if not multiplayer.is_server():
		return
	var server := get_node_or_null("/root/Server")
	if server == null or not server.has_method("emit_spatial_sound"):
		return
	var surface := PHYSICAL_SURFACE.from_collider(collider)
	var source_modifier := IMPACT_RESPONSE.modifier_for(
		surface,
		impact_excitation_for_profile(profile, velocity.length())
	)
	var acoustic_origin := hit_position
	if (
		hit_normal.is_finite()
		and hit_normal.length_squared() > MINIMUM_MOTION_LENGTH_SQUARED
	):
		acoustic_origin += hit_normal.normalized() * IMPACT_SOUND_SURFACE_OFFSET
	server.call(
		"emit_spatial_sound",
		impact_sound_id_for_profile(profile),
		acoustic_origin,
		float(profile.get(
			"impact_sound_max_distance",
			BallisticProjectileDefinition.DEFAULT_IMPACT_SOUND_MAX_DISTANCE
		)),
		float(profile.get(
			"impact_sound_volume_db",
			BallisticProjectileDefinition.DEFAULT_IMPACT_SOUND_VOLUME_DB
		)),
		source_modifier,
		float(profile.get(
			"impact_sound_priority",
			BallisticProjectileDefinition.DEFAULT_IMPACT_SOUND_PRIORITY
		)),
		IMPACT_PRESSURE_STRENGTH
	)


func _resolve() -> void:
	if resolved:
		return
	resolved = true
	if despawn_callback.is_valid():
		despawn_callback.call(projectile_id)
	elif is_inside_tree():
		queue_free()


func to_state_dict() -> Dictionary:
	return {
		"projectile_id": projectile_id,
		"pos": global_position,
		"velocity": velocity,
		"launch_direction": launch_direction,
		"distance_traveled": distance_traveled,
		"visual_definition_path": str(
			profile.get("visual_definition_path", "")
		),
		"tracer_color": profile.get(
			"tracer_color",
			BallisticProjectileDefinition.DEFAULT_TRACER_COLOR
		),
		"tracer_length": float(profile.get(
			"tracer_length",
			BallisticProjectileDefinition.DEFAULT_TRACER_LENGTH
		)),
		"tracer_radius": float(profile.get(
			"tracer_radius",
			BallisticProjectileDefinition.DEFAULT_TRACER_RADIUS
		)),
		"source_kind": source_kind,
		"source_id": source_id,
		"source_slot": source_slot,
	}

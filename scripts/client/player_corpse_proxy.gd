class_name PlayerCorpseProxy
extends Node3D

## Long-lived client presentation for a dead player's detached authoritative torso. The articulated
## bodies remain local and expressive; the sparse server snapshot only corrects the torso island so
## every peer agrees where the corpse settled without replicating every bone.

const PLAYER_RAGDOLL := preload("res://scripts/characters/player_ragdoll_3d.gd")
const CHARACTER_SKIN := preload("res://scripts/characters/player_character_skin.gd")

var corpse_id := -1
var source_player_id := -1
var ragdoll: PlayerRagdoll3D
var target_torso_position := Vector3.ZERO
var target_velocity := Vector3.ZERO
var _fallback_sources: Dictionary[StringName, Node3D] = {}
var _fallback_skin: PlayerCharacterSkin


func initialize_from_player(source: PlayerProxy, state: Dictionary) -> void:
	corpse_id = SafeVariant.integral_int_or(state.get("corpse_id"), -1)
	source_player_id = SafeVariant.integral_int_or(
		state.get("source_player_id"),
		-1
	)
	ragdoll = PLAYER_RAGDOLL.new()
	ragdoll.name = "CorpseRagdoll"
	add_child(ragdoll)
	var velocity := SafeVariant.vector3_strict_or(
		state.get("vel", Vector3.ZERO),
		Vector3.ZERO
	)
	var direction := SafeVariant.vector3_strict_or(
		state.get("trip_direction", Vector3.FORWARD),
		Vector3.FORWARD
	)
	var configured := (
		source != null
		and source.configure_corpse_ragdoll(ragdoll, velocity, direction)
	)
	if not configured:
		_configure_fallback_ragdoll(state, velocity, direction)
	apply_server_state(state)
	set_physics_process(true)


func apply_server_state(state: Dictionary) -> void:
	if ragdoll == null:
		return
	var reference_position := SafeVariant.vector3_strict_or(
		state.get("pos", Vector3.ZERO),
		target_torso_position - PlayerRagdoll3D.TORSO_OFFSET_FROM_PLAYER
	)
	target_torso_position = (
		reference_position + PlayerRagdoll3D.TORSO_OFFSET_FROM_PLAYER
	)
	target_velocity = SafeVariant.vector3_strict_or(
		state.get("vel", target_velocity),
		target_velocity
	)
	ragdoll.synchronize_authoritative_torso(
		target_torso_position,
		target_velocity,
		0.0
	)


func _physics_process(delta: float) -> void:
	if ragdoll == null or not ragdoll.is_active():
		return
	ragdoll.synchronize_authoritative_torso(
		target_torso_position,
		target_velocity,
		delta
	)


func _configure_fallback_ragdoll(
	state: Dictionary,
	velocity: Vector3,
	direction: Vector3
) -> void:
	var reference_position := SafeVariant.vector3_strict_or(
		state.get("pos", Vector3.ZERO),
		Vector3.ZERO
	)
	var yaw := SafeVariant.finite_float_or(state.get("yaw"), 0.0)
	var basis := Basis(Vector3.UP, yaw)
	var source_offsets := {
		&"torso": Vector3(0.0, 0.15, 0.0),
		&"head": Vector3(0.0, 0.78, 0.0),
		&"left_arm": Vector3(-0.47, 0.16, 0.0),
		&"right_arm": Vector3(0.47, 0.16, 0.0),
		&"left_upper_leg": Vector3(-0.20, -0.32, 0.0),
		&"left_lower_leg": Vector3(-0.20, -0.72, 0.0),
		&"left_foot": Vector3(-0.20, -1.04, -0.10),
		&"right_upper_leg": Vector3(0.20, -0.32, 0.0),
		&"right_lower_leg": Vector3(0.20, -0.72, 0.0),
		&"right_foot": Vector3(0.20, -1.04, -0.10),
	}
	for body_name: StringName in source_offsets:
		var marker := Node3D.new()
		marker.name = String(body_name)
		add_child(marker)
		marker.global_transform = Transform3D(
			basis,
			reference_position + basis * (source_offsets[body_name] as Vector3)
		)
		_fallback_sources[body_name] = marker
	_fallback_skin = CHARACTER_SKIN.new()
	_fallback_skin.name = "CorpseSourceSkin"
	add_child(_fallback_skin)
	_fallback_skin.set_player_identity(source_player_id)
	_fallback_skin.global_transform = Transform3D(basis, reference_position)
	_fallback_skin.visible = false
	var limbs := SafeVariant.dictionary_copy(state.get("limbs", {}), false)
	ragdoll.set_limb_presence(
		bool(limbs.get("left_arm", true)),
		bool(limbs.get("right_arm", true)),
		bool(limbs.get("left_leg", true)),
		bool(limbs.get("right_leg", true))
	)
	ragdoll.start_ragdoll(
		_fallback_sources,
		velocity,
		direction,
		_fallback_skin,
		false
	)

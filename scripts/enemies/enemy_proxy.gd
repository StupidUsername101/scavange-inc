class_name EnemyProxy
extends Node3D

const INTERPOLATION_SPEED := 12.0

#######################################################
# Mirrors authoritative enemy state on clients and updates its local visual presentation.
#######################################################

var enemy_id := -1
var definition_path := ""
var definition: EnemyDefinition
var visual: Node3D
var status_label: Label3D
var target_position := Vector3.ZERO
var target_rotation := Quaternion.IDENTITY
var last_limb_states: Array = []


func _ready() -> void:
	status_label = Label3D.new()
	status_label.name = "EnemyStatus"
	status_label.font_size = 34
	status_label.outline_size = 9
	status_label.pixel_size = 0.0022
	status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	status_label.no_depth_test = false
	status_label.outline_modulate = Color(0.005, 0.008, 0.01, 1.0)
	add_child(status_label)


func apply_server_state(state: Dictionary) -> void:
	enemy_id = int(state.get("enemy_id", -1))
	_apply_definition(str(state.get("definition_path", "")))
	target_position = state.get("pos", global_position)
	target_rotation = Quaternion.from_euler(state.get("rot", global_rotation))
	var health := float(state.get("health", 0.0))
	var maximum_health := float(state.get("max_health", 0.0))
	var active := bool(state.get("active", false))
	var alive := bool(state.get("alive", true))
	last_limb_states = state.get("limbs", [])
	_apply_limb_visual_state(last_limb_states)
	var display_name: String = (
		definition.display_name if definition != null else "Enemy"
	)
	status_label.text = "%s\n%s  •  %d / %d HP" % [
		display_name,
		(
			"RAGDOLL — RESPAWNING"
			if not alive
			else ("ACTIVE" if active else "DORMANT — ENTER PEN")
		),
		roundi(health),
		roundi(maximum_health),
	]
	status_label.modulate = (
		Color(0.45, 0.42, 0.4, 1.0)
		if not alive
		else Color(1.0, 0.38, 0.2, 1.0) if active
		else Color(0.62, 0.68, 0.72, 1.0)
	)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		var server_enemy := Server.get_server_enemy(enemy_id)
		if is_instance_valid(server_enemy):
			global_transform = server_enemy.global_transform
			_apply_limb_visual_state(server_enemy.get_limb_state())
			return
	var weight := clampf(
		1.0 - exp(-INTERPOLATION_SPEED * delta),
		0.0,
		1.0
	)
	global_position = global_position.lerp(target_position, weight)
	var current_rotation := global_basis.get_rotation_quaternion()
	global_basis = Basis(current_rotation.slerp(target_rotation, weight))


func _apply_definition(path: String) -> void:
	if path.is_empty() or path == definition_path:
		return
	var loaded := load(path) as EnemyDefinition
	if loaded == null:
		push_error("Invalid enemy definition: %s" % path)
		return
	definition_path = path
	definition = loaded
	if visual != null:
		visual.queue_free()
	visual = definition.instantiate_visual()
	add_child(visual)
	status_label.position = Vector3.UP * (definition.get_visual_height() + 0.55)
	_apply_limb_visual_state(last_limb_states)


func _apply_limb_visual_state(states: Array) -> void:
	if visual != null and visual.has_method("apply_limb_state"):
		visual.call("apply_limb_state", states)

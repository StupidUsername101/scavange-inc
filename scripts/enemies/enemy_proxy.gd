class_name EnemyProxy
extends Node3D

const INTERPOLATION_SPEED := 12.0
const HUMANOID_PRESENTATION := preload(
	"res://scripts/enemies/enemy_humanoid_presentation_3d.gd"
)

#######################################################
# Mirrors authoritative enemy state on clients and updates its local visual presentation.
#######################################################

var enemy_id := -1
var definition_path := ""
var definition: EnemyDefinition
var visual: Node3D
var humanoid_visual: Node3D
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
	if humanoid_visual != null:
		humanoid_visual.apply_server_state(state)
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
	status_label.visible = definition == null or definition.show_status_label


func _process(delta: float) -> void:
	if multiplayer.is_server():
		var server := get_node_or_null("/root/Server")
		var server_enemy := (
			server.call("get_server_enemy", enemy_id) as ServerEnemy
			if server != null
			else null
		)
		if is_instance_valid(server_enemy):
			global_transform = server_enemy.global_transform
			_apply_limb_visual_state(server_enemy.get_limb_state())
			if humanoid_visual != null:
				humanoid_visual.apply_authoritative_enemy(server_enemy)
				humanoid_visual.update_presentation(delta)
			return
	var weight := clampf(
		1.0 - exp(-INTERPOLATION_SPEED * delta),
		0.0,
		1.0
	)
	global_position = global_position.lerp(target_position, weight)
	var current_rotation := global_basis.get_rotation_quaternion()
	global_basis = Basis(current_rotation.slerp(target_rotation, weight))
	if humanoid_visual != null:
		humanoid_visual.update_presentation(delta)


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
	humanoid_visual = null
	if definition.presentation_type == EnemyDefinition.PresentationType.HUMANOID:
		humanoid_visual = HUMANOID_PRESENTATION.new()
		humanoid_visual.name = "HumanoidPresentation"
		humanoid_visual.configure(
			40000 + maxi(enemy_id, 0),
			definition.destructible_anatomy
		)
		visual = humanoid_visual
	else:
		visual = definition.instantiate_visual()
	add_child(visual)
	status_label.position = Vector3.UP * (definition.get_visual_height() + 0.55)
	status_label.visible = definition.show_status_label
	_apply_limb_visual_state(last_limb_states)


func _apply_limb_visual_state(states: Array) -> void:
	if visual != null and visual.has_method("apply_limb_state"):
		visual.call("apply_limb_state", states)

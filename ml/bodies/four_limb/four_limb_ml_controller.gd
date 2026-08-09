class_name FourLimbMLController
extends Node

#######################################################
# Runtime inference controller for gameplay bodies. It uses the same observation encoder and
# the same direct joint-and-grip targets as the training room. Future gun attachments can add observation
# payloads through the body's attachment feed without changing this controller.
#######################################################

@export var body_path: NodePath
@export_range(0.01, 1.0, 0.01, "or_greater") var control_interval_seconds = 0.05

var body: FourLimbPhysicalBody3D
var adapter: FourLimbMLBodyAdapter
var model: FourLimbPPOModel
var objective: Dictionary = {}
var enabled = false
var elapsed_since_decision = 0.0


func _ready() -> void:
	body = get_node_or_null(body_path) as FourLimbPhysicalBody3D
	if body == null:
		body = get_parent() as FourLimbPhysicalBody3D
	if body != null:
		adapter = FourLimbMLBodyAdapter.new(body)


func _physics_process(delta: float) -> void:
	if not enabled or model == null or adapter == null or not adapter.is_alive():
		return
	elapsed_since_decision += delta
	if elapsed_since_decision < control_interval_seconds:
		return
	elapsed_since_decision = fmod(elapsed_since_decision, control_interval_seconds)
	var observation = adapter.capture_observation(objective)
	if observation.is_empty():
		return
	var action = model.predict_action(observation)
	if not action.is_empty():
		adapter.apply_action(action)


func enable(runtime_model: FourLimbPPOModel, new_objective: Dictionary = {}) -> bool:
	if (
		runtime_model == null
		or adapter == null
		or not runtime_model.is_compatible_with_hardware(adapter.hardware_signature())
	):
		return false
	model = runtime_model
	objective = new_objective.duplicate(true)
	enabled = true
	elapsed_since_decision = control_interval_seconds
	return true


func disable() -> void:
	enabled = false
	model = null
	if is_instance_valid(body) and is_instance_valid(body.physical_rig):
		body.physical_rig.neutralize_commands()


func set_objective(new_objective: Dictionary) -> void:
	objective = new_objective.duplicate(true)

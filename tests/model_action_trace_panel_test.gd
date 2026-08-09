extends SceneTree

const PANEL_SCRIPT = preload("res://ml/training/ui/drone_training_action_trace_panel.gd")

var failure_count = 0


func _init() -> void:
	var panel = PANEL_SCRIPT.new()
	root.add_child(panel)
	panel.set_fullscreen_mode(true)

	var limb_names: Array[String] = []
	for limb_name in ["Front Right", "Rear Right", "Rear Left", "Front Left"]:
		limb_names.append("%s hip elevation" % limb_name)
		limb_names.append("%s hip horizontal sweep" % limb_name)
		limb_names.append("%s knee bend" % limb_name)
		limb_names.append("%s grip" % limb_name)
	var limb_values = PackedFloat64Array()
	limb_values.resize(16)
	for index in range(limb_values.size()):
		limb_values[index] = float(index) / 15.0 * 2.0 - 1.0
	var limb_record = _record(4, 16, limb_names, limb_values, -1.0, 1.0)
	panel.refresh([{
		"source_id": "four_limb:4",
		"group_id": 4,
		"name": "Leg test",
		"worker_kind": "four_limb",
		"worker_kind_label": "FOUR-LIMB",
		"algorithm": "PPO",
		"active": true,
		"episode_number": 4,
		"color": Color.WHITE,
		"action_names": limb_names,
		"action_minimum": -1.0,
		"action_maximum": 1.0,
		"workers": [{
			"source_id": "four_limb:4",
			"group_name": "Leg test",
			"worker_kind_label": "Limb",
			"instance_id": 44,
			"worker_index": 0,
			"episode_number": 4,
			"elapsed_seconds": 1.0,
			"status": "live",
			"action_names": limb_names,
			"action_minimum": -1.0,
			"action_maximum": 1.0,
			"record": limb_record,
		}],
	}])
	_expect(panel.trace_tree.columns == 18, "four-limb detail table exposes time, samples, and all sixteen model actions")
	_expect(panel.action_contract_label.text.contains("16 model controls"), "four-limb action contract states the complete channel count")
	_expect(panel.action_contract_label.text.contains("Front Right grip"), "four-limb action contract exposes semantic grip labels")
	_expect(panel.action_contract_label.text.contains("Front Left hip elevation"), "four-limb action contract exposes semantic joint labels")

	var turret_names: Array[String] = ["Yaw drive", "Pitch drive", "Trigger"]
	var turret_values = PackedFloat64Array([-0.25, 0.5, 1.0])
	var turret_record = _record(2, 3, turret_names, turret_values, -1.0, 1.0)
	panel.refresh([{
		"source_id": "turret:8",
		"group_id": 8,
		"name": "Aim test",
		"worker_kind": "turret",
		"worker_kind_label": "TURRET",
		"algorithm": "PPO",
		"active": true,
		"episode_number": 2,
		"color": Color.WHITE,
		"action_names": turret_names,
		"action_minimum": -1.0,
		"action_maximum": 1.0,
		"workers": [{
			"source_id": "turret:8",
			"group_name": "Aim test",
			"worker_kind_label": "Turret",
			"instance_id": 88,
			"worker_index": 0,
			"episode_number": 2,
			"elapsed_seconds": 0.5,
			"status": "live",
			"action_names": turret_names,
			"action_minimum": -1.0,
			"action_maximum": 1.0,
			"record": turret_record,
		}],
	}])
	_expect(panel.trace_tree.columns == 5, "turret detail table resizes to exactly three model actions")
	_expect(panel.action_contract_label.text.contains("Trigger"), "turret action contract exposes trigger control")

	panel.queue_free()
	quit(0 if failure_count == 0 else 1)


func _record(
	episode_number: int,
	action_count: int,
	action_names: Array[String],
	values: PackedFloat64Array,
	action_minimum: float,
	action_maximum: float
) -> Dictionary:
	return {
		"episode_number": episode_number,
		"action_count": action_count,
		"action_names": action_names,
		"action_minimum": action_minimum,
		"action_maximum": action_maximum,
		"latest_commands": values.duplicate(),
		"latest_time_seconds": 1.0,
		"total_decisions": 1,
		"invalid_samples": 0,
		"saturated_channel_samples": 0,
		"all_high_decisions": 0,
		"all_low_decisions": 0,
		"sum_commands": values.duplicate(),
		"minimum_commands": values.duplicate(),
		"maximum_commands": values.duplicate(),
		"segments": [{
			"start_time_seconds": 1.0,
			"end_time_seconds": 1.0,
			"sample_count": 1,
			"sum_commands": values.duplicate(),
			"minimum_commands": values.duplicate(),
			"maximum_commands": values.duplicate(),
			"last_commands": values.duplicate(),
		}],
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)

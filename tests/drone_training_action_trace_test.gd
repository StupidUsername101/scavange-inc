extends SceneTree

var failure_count = 0


func _init() -> void:
	var normalized_commands: PackedFloat64Array = DroneTrainingActionCodec.policy_unit_commands_from_action(
		{
			"controls": [
				{"minimum": -2.0, "maximum": 2.0},
				{"minimum": 0.0, "maximum": 10.0},
			]
		},
		{"body_commands": PackedFloat64Array([0.0, 2.5])}
	)
	_expect(
		normalized_commands.size() == 2
		and is_equal_approx(normalized_commands[0], 0.5)
		and is_equal_approx(normalized_commands[1], 0.25),
		"action telemetry codec normalizes generic creator control ranges without room-specific action parsing"
	)
	var legacy_commands: PackedFloat64Array = DroneTrainingActionCodec.policy_unit_commands_from_action(
		{},
		{
			"propeller_commands": [
				{"command": 0.1},
				{"command": 0.2},
				{"command": 0.3},
				{"command": 0.4},
			]
		}
	)
	_expect(
		legacy_commands == PackedFloat64Array([0.1, 0.2, 0.3, 0.4]),
		"action telemetry codec retains legacy quad trace compatibility outside DroneTrainingRoom"
	)

	var buffer = DroneTrainingActionTraceBuffer.new()
	var drone_names: Array[String] = ["P0 thrust", "P1 thrust", "P2 thrust", "P3 thrust"]
	buffer.begin_source_episode(
		"drone:3",
		3,
		7,
		drone_names,
		0.0,
		1.0,
		[{"instance_id": 42, "worker_index": 1}]
	)
	_expect(
		int(buffer.source_config("drone:3").get("episode_number", -1)) == 7,
		"source-aware trace buffer records the drone episode"
	)
	_expect(
		buffer.append_source_commands(
			"drone:3",
			42,
			1,
			0.0,
			PackedFloat64Array([0.1, 0.2, 0.3, 0.4])
		),
		"valid quad action is accepted"
	)
	buffer.append_source_commands(
		"drone:3",
		42,
		1,
		0.1,
		PackedFloat64Array([0.2, 0.3, 0.4, 0.5])
	)
	var record = buffer.record_for_source("drone:3", 42)
	_expect(int(record.get("total_decisions", 0)) == 2, "every model decision contributes to summary statistics")
	var segments: Array = record.get("segments", [])
	_expect(segments.size() == 1, "nearby control ticks are condensed into one time bucket")
	_expect(int(segments[0].get("sample_count", 0)) == 2, "condensed bucket retains its sample count")

	for index in range(DroneTrainingActionTraceBuffer.MAX_SEGMENTS_PER_WORKER + 60):
		var command = float(index % 100) / 100.0
		buffer.append_source_commands(
			"drone:3",
			42,
			1,
			1.0 + float(index),
			PackedFloat64Array([command, command, command, command])
		)
	record = buffer.record_for_source("drone:3", 42)
	segments = record.get("segments", [])
	_expect(
		segments.size() <= DroneTrainingActionTraceBuffer.MAX_SEGMENTS_PER_WORKER,
		"adaptive compaction keeps each worker trace bounded"
	)
	_expect(
		int(record.get("total_decisions", 0)) == DroneTrainingActionTraceBuffer.MAX_SEGMENTS_PER_WORKER + 62,
		"compaction preserves the full decision count"
	)

	var limb_names: Array[String] = []
	for limb_index in range(4):
		limb_names.append("L%d hip elevation" % (limb_index + 1))
		limb_names.append("L%d hip horizontal sweep" % (limb_index + 1))
		limb_names.append("L%d knee bend" % (limb_index + 1))
		limb_names.append("L%d grip" % (limb_index + 1))
	buffer.begin_source_episode(
		"four_limb:9",
		9,
		3,
		limb_names,
		-1.0,
		1.0,
		[{"instance_id": 90, "worker_index": 0}]
	)
	var limb_commands = PackedFloat64Array()
	limb_commands.resize(16)
	for index in range(limb_commands.size()):
		limb_commands[index] = -1.0 + float(index) * (2.0 / 15.0)
	_expect(
		buffer.append_source_commands("four_limb:9", 90, 0, 0.5, limb_commands),
		"sixteen-channel four-limb action is accepted"
	)
	var limb_record = buffer.record_for_source("four_limb:9", 90)
	_expect(int(limb_record.get("action_count", 0)) == 16, "four-limb trace preserves all sixteen action channels")
	_expect((limb_record.get("action_names", []) as Array).size() == 16, "four-limb trace preserves semantic channel names")
	_expect(
		int(limb_record.get("saturated_channel_samples", 0)) == 2,
		"source-specific -1..1 saturation thresholds count the two endpoint limb commands"
	)
	_expect(
		not buffer.append_source_commands(
			"four_limb:9",
			90,
			0,
			0.6,
			PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		),
		"wrong-width commands are rejected for a variable-width source"
	)
	limb_record = buffer.record_for_source("four_limb:9", 90)
	_expect(
		int(limb_record.get("invalid_samples", 0)) == 1,
		"wrong-width source actions are visible as invalid samples instead of disappearing"
	)

	buffer.begin_source_episode(
		"turret:11",
		11,
		5,
		["Yaw drive", "Pitch drive", "Trigger"],
		-1.0,
		1.0,
		[{"instance_id": 110, "worker_index": 0}]
	)
	_expect(
		buffer.append_source_commands(
			"turret:11",
			110,
			0,
			0.2,
			PackedFloat64Array([-0.25, 0.5, 1.0])
		),
		"three-channel turret action is accepted"
	)
	var turret_record = buffer.record_for_source("turret:11", 110)
	_expect(int(turret_record.get("action_count", 0)) == 3, "turret trace preserves all three action channels")

	buffer.begin_source_episode(
		"four_limb:9",
		9,
		4,
		limb_names,
		-1.0,
		1.0,
		[{"instance_id": 90, "worker_index": 0}]
	)
	_expect(
		int(buffer.record_for_source("four_limb:9", 90).get("total_decisions", -1)) == 0,
		"starting a new limb episode clears only that source trace"
	)
	_expect(
		int(buffer.record_for_source("drone:3", 42).get("total_decisions", 0)) > 0,
		"independent worker-kind episodes do not erase drone traces"
	)
	var grabber_names: Array[String] = [
		"P0 thrust", "P1 thrust", "P2 thrust", "P3 thrust",
		"Shoulder X", "Shoulder Z", "Elbow Z", "Belly grip"
	]
	buffer.begin_source_episode(
		"drone:12",
		12,
		1,
		grabber_names,
		0.0,
		1.0,
		[{"instance_id": 120, "worker_index": 0}]
	)
	_expect(
		buffer.append_source_commands(
			"drone:12",
			120,
			0,
			0.1,
			PackedFloat64Array([0.4, 0.4, 0.4, 0.4, 0.1, 0.9, 0.3, 0.8])
		),
		"eight-output articulated grabber-drone action trace is accepted"
	)
	var grabber_record: Dictionary = buffer.record_for_source("drone:12", 120)
	_expect(
		int(grabber_record.get("action_count", 0)) == 8
		and (grabber_record.get("action_names", []) as Array).size() == 8,
		"grabber-drone trace preserves four rotors plus all articulated limb controls"
	)
	_expect(
		int(buffer.record_for_source("turret:11", 110).get("total_decisions", 0)) == 1,
		"independent worker-kind episodes do not erase turret traces"
	)

	buffer.remove_source("turret:11")
	_expect(buffer.records_for_source("turret:11").is_empty(), "removed source releases its debug trace")
	quit(0 if failure_count == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)

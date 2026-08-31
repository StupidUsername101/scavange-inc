class_name AcousticStimulusLedger
extends RefCounted

## Fixed-capacity server memory for gameplay sounds that AI may hear. Events reuse ring slots, so
## automatic weapons and running players cannot grow an unbounded queue or allocate during queries.

const CAPACITY := 64


class Stimulus:
	var sequence := 0
	var emitted_msec := 0
	var sound_id: StringName = &""
	var position := Vector3.ZERO
	var maximum_distance := 0.0
	var base_volume_db := 0.0
	var priority := 0.0
	var origin_player_id := -1
	var source_modifier: AcousticPathModifier


var _records: Array[Stimulus] = []
var _write_index := 0


func record(
	sequence: int,
	sound_id: StringName,
	position: Vector3,
	maximum_distance: float,
	base_volume_db: float,
	priority: float,
	origin_player_id: int,
	source_modifier: AcousticPathModifier
) -> void:
	var stimulus: Stimulus
	if _records.size() < CAPACITY:
		stimulus = Stimulus.new()
		_records.append(stimulus)
	else:
		stimulus = _records[_write_index]
	stimulus.sequence = maxi(sequence, 0)
	stimulus.emitted_msec = Time.get_ticks_msec()
	stimulus.sound_id = sound_id
	stimulus.position = position
	stimulus.maximum_distance = maxf(maximum_distance, 0.0)
	stimulus.base_volume_db = base_volume_db
	stimulus.priority = clampf(priority, 0.0, 1.0)
	stimulus.origin_player_id = origin_player_id
	stimulus.source_modifier = source_modifier
	_write_index = (_write_index + 1) % CAPACITY


func readonly_records() -> Array[Stimulus]:
	return _records


func clear() -> void:
	_records.clear()
	_write_index = 0

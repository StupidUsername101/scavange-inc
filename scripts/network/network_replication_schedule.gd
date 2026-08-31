class_name NetworkReplicationSchedule
extends RefCounted

## Full snapshots replace older snapshots; only their cadence differs. Player/combat state remains
## at the server's 20 Hz network tick, including complete player-interactive item lifecycle state.
## Actively grabbed items and destruction fragments add a tiny physics-rate motion delta on the
## same interaction lane. Loose drone parts and secondary simulation use 10 Hz with extrapolation,
## while mostly static station panels refresh at 2 Hz. Reliable commands and transactions are not
## scheduled here.

const REALTIME_INTERVAL_TICKS := 1
const BULK_PHYSICS_INTERVAL_TICKS := 2
const STATION_INTERVAL_TICKS := 10
const LOCAL_AUDIO_CONTEXT_INTERVAL_TICKS := 4


static func is_due(snapshot_sequence: int, interval_ticks: int) -> bool:
	return (
		snapshot_sequence >= 0
		and interval_ticks > 0
		and snapshot_sequence % interval_ticks == 0
	)


static func read_snapshot_sequence(states: Dictionary) -> int:
	for entity_id: Variant in states:
		var raw_state: Variant = states[entity_id]
		if not raw_state is Dictionary:
			continue
		var snapshot_sequence := SafeVariant.integral_int_or(
			(raw_state as Dictionary).get("network_snapshot_sequence"),
			-1
		)
		if snapshot_sequence >= 0:
			return snapshot_sequence
	return -1


static func is_newer_snapshot(snapshot_sequence: int, last_sequence: int) -> bool:
	# Negative sequences identify legacy/empty snapshots, which remain compatible.
	return snapshot_sequence < 0 or snapshot_sequence > last_sequence

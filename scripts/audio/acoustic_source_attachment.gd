class_name AcousticSourceAttachment
extends RefCounted

## Collision-validated graph endpoints for one real sound origin. Continuous emitters retain this
## object while stationary; moving emitters rebuild it only after a meaningful displacement.

var graph_revision := -1
var source_position := Vector3(INF, INF, INF)
var nearest_unfiltered_probe := -1
var probes := PackedInt32Array()
var probe_count := 0
var visibility_confirmed := false
var candidate_probes := PackedInt32Array()
var visibility_exclusions: Array[RID] = []


func prepare(candidate_capacity: int, attachment_capacity: int) -> void:
	var safe_candidate_capacity := maxi(candidate_capacity, 0)
	var safe_attachment_capacity := maxi(attachment_capacity, 0)
	if candidate_probes.size() != safe_candidate_capacity:
		candidate_probes.resize(safe_candidate_capacity)
	if probes.size() != safe_attachment_capacity:
		probes.resize(safe_attachment_capacity)
	candidate_probes.fill(-1)
	probes.fill(-1)
	probe_count = 0
	visibility_confirmed = false
	visibility_exclusions.clear()


func primary_probe() -> int:
	return probes[0] if probe_count > 0 else nearest_unfiltered_probe


func is_current(
	current_graph_revision: int,
	current_source_position: Vector3,
	maximum_displacement_squared: float
) -> bool:
	return (
		graph_revision == current_graph_revision
		and current_source_position.is_finite()
		and source_position.distance_squared_to(current_source_position)
		<= maxf(maximum_displacement_squared, 0.0)
	)

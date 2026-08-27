class_name AcousticPropagationField
extends RefCounted

## Reusable listener-centered solver storage. All hot arrays retain capacity between solves, and
## the indexed decrease-key heap contains each probe at most once.

var source_probe := -1
var source_position := Vector3.ZERO
var graph_revision := -1

var route_costs := PackedFloat32Array()
var arrival_times := PackedFloat32Array()
var path_lengths := PackedFloat32Array()
var guided_path_lengths := PackedFloat32Array()
# Routing bands contain authored material transmission only. Render bands additionally contain the
# frequency-dependent deviation of the selected path. Keeping them separate preserves the graph's
# shortest/strongest-path optimality without requiring one Dijkstra state per incoming edge.
var routing_band_gains := PackedVector3Array()
# Accumulated dimensionless bend burden. The graph maps it through a bounded response, so a long
# reverberant route grows progressively darker without multiplying useful music bands to zero.
var path_deviation_strengths := PackedFloat32Array()
var band_gains := PackedVector3Array()
var volume_db := PackedFloat32Array()
var lowpass_hz := PackedFloat32Array()
var highpass_hz := PackedFloat32Array()
var resonance := PackedFloat32Array()
var reverb_send := PackedFloat32Array()
var predecessors := PackedInt32Array()
var predecessor_modifiers := PackedInt32Array()
var first_hops := PackedInt32Array()
var origin_probes := PackedInt32Array()

# Reused listener-local buffers. The service fills candidate_probes with the nearest graph
# samples, filters them against world collision into listener_probes, then one multi-source solve
# serves every audible source for this listener.
var candidate_probes := PackedInt32Array()
var guided_candidate_probes := PackedInt32Array()
var guided_best_region_ids := PackedInt32Array()
var guided_best_probes := PackedInt32Array()
var guided_best_strengths := PackedFloat32Array()
var guided_best_distances_squared := PackedFloat32Array()
var guided_best_count := 0
var listener_probes := PackedInt32Array()
var listener_probe_strengths := PackedFloat32Array()
var listener_probe_count := 0
var previous_listener_probes := PackedInt32Array()
var previous_listener_probe_strengths := PackedFloat32Array()
var previous_listener_probe_count := 0
var listener_probe_transition_step := 1.0
# A hidden nearest-probe fallback may keep diagnostic graph state populated, but it may neither
# render an indirect route nor describe the listener's local room. The server sets this only after
# a collision-clear probe sightline.
var listener_probe_visibility_confirmed := true
var visibility_exclusions: Array[RID] = []

var environment_sample_position := Vector3(INF, INF, INF)
var environment_sample_revision := -1
var environment_enclosure := 0.0
var environment_diffuse_strength := 0.0
var environment_guided_strength := 0.0
var environment_guided_wall_loss_db_per_m := 0.0
var environment_rt60_seconds := AcousticEnvironmentModel.MIN_REVERB_TIME_SECONDS
var environment_reverb_send := 0.0
var environment_room_size := 0.02
var environment_damping := 0.05
var environment_spread := 1.0
var environment_predelay_msec := 1.0
var environment_predelay_feedback := 0.0
var environment_hipass := 0.0

var _heap_nodes := PackedInt32Array()
var _heap_costs := PackedFloat32Array()
var _heap_positions := PackedInt32Array()
var _heap_size := 0


func reset(probe_count: int) -> void:
	_resize_if_needed(probe_count)
	source_probe = -1
	source_position = Vector3.ZERO
	route_costs.fill(INF)
	arrival_times.fill(INF)
	path_lengths.fill(INF)
	guided_path_lengths.fill(0.0)
	routing_band_gains.fill(Vector3.ZERO)
	path_deviation_strengths.fill(0.0)
	band_gains.fill(Vector3.ZERO)
	volume_db.fill(0.0)
	lowpass_hz.fill(AcousticPathModifier.MAX_FILTER_HZ)
	highpass_hz.fill(AcousticPathModifier.MIN_FILTER_HZ)
	resonance.fill(0.0)
	reverb_send.fill(0.0)
	predecessors.fill(-1)
	predecessor_modifiers.fill(-1)
	first_hops.fill(-1)
	origin_probes.fill(-1)
	_heap_positions.fill(-1)
	_heap_size = 0


func prepare_listener_probe_buffers(
	candidate_capacity: int,
	guided_candidate_capacity: int,
	blend_capacity: int,
	previous_field: AcousticPropagationField = null
) -> void:
	var safe_candidate_capacity := maxi(candidate_capacity, 0)
	var safe_guided_candidate_capacity := maxi(guided_candidate_capacity, 0)
	var safe_blend_capacity := maxi(blend_capacity, 0)
	var previous_source := (
		previous_field if previous_field != null else self
	)
	previous_listener_probe_count = mini(
		previous_source.listener_probe_count,
		safe_blend_capacity
	)
	if previous_listener_probes.size() != safe_blend_capacity:
		previous_listener_probes.resize(safe_blend_capacity)
		previous_listener_probe_strengths.resize(safe_blend_capacity)
	for previous_index: int in range(previous_listener_probe_count):
		previous_listener_probes[previous_index] = (
			previous_source.listener_probes[previous_index]
		)
		previous_listener_probe_strengths[previous_index] = (
			previous_source.listener_probe_strengths[previous_index]
		)
	for previous_index: int in range(previous_listener_probe_count, safe_blend_capacity):
		previous_listener_probes[previous_index] = -1
		previous_listener_probe_strengths[previous_index] = 0.0
	if candidate_probes.size() != safe_candidate_capacity:
		candidate_probes.resize(safe_candidate_capacity)
	if guided_candidate_probes.size() != safe_guided_candidate_capacity:
		guided_candidate_probes.resize(safe_guided_candidate_capacity)
	if guided_best_region_ids.size() != safe_blend_capacity:
		guided_best_region_ids.resize(safe_blend_capacity)
		guided_best_probes.resize(safe_blend_capacity)
		guided_best_strengths.resize(safe_blend_capacity)
		guided_best_distances_squared.resize(safe_blend_capacity)
	if listener_probes.size() != safe_blend_capacity:
		listener_probes.resize(safe_blend_capacity)
	if listener_probe_strengths.size() != safe_blend_capacity:
		listener_probe_strengths.resize(safe_blend_capacity)
	candidate_probes.fill(-1)
	guided_candidate_probes.fill(-1)
	guided_best_region_ids.fill(-1)
	guided_best_probes.fill(-1)
	guided_best_strengths.fill(0.0)
	guided_best_distances_squared.fill(INF)
	guided_best_count = 0
	listener_probes.fill(-1)
	listener_probe_strengths.fill(0.0)
	listener_probe_count = 0
	listener_probe_visibility_confirmed = false
	invalidate_environment_sample()


func invalidate_environment_sample() -> void:
	environment_sample_position = Vector3(INF, INF, INF)
	environment_sample_revision = -1


func heap_push_or_decrease(probe_index: int, cost: float) -> void:
	var heap_index := _heap_positions[probe_index]
	if heap_index < 0:
		heap_index = _heap_size
		_heap_size += 1
		_heap_nodes[heap_index] = probe_index
		_heap_costs[heap_index] = cost
		_heap_positions[probe_index] = heap_index
	else:
		if cost >= _heap_costs[heap_index]:
			return
		_heap_costs[heap_index] = cost
	_heap_sift_up(heap_index)


func heap_pop_min() -> int:
	if _heap_size <= 0:
		return -1
	var result := _heap_nodes[0]
	_heap_positions[result] = -1
	_heap_size -= 1
	if _heap_size > 0:
		var moved_node := _heap_nodes[_heap_size]
		_heap_nodes[0] = moved_node
		_heap_costs[0] = _heap_costs[_heap_size]
		_heap_positions[moved_node] = 0
		_heap_sift_down(0)
	return result


func heap_is_empty() -> bool:
	return _heap_size <= 0


func _resize_if_needed(probe_count: int) -> void:
	if route_costs.size() == probe_count:
		return
	route_costs.resize(probe_count)
	arrival_times.resize(probe_count)
	path_lengths.resize(probe_count)
	guided_path_lengths.resize(probe_count)
	routing_band_gains.resize(probe_count)
	path_deviation_strengths.resize(probe_count)
	band_gains.resize(probe_count)
	volume_db.resize(probe_count)
	lowpass_hz.resize(probe_count)
	highpass_hz.resize(probe_count)
	resonance.resize(probe_count)
	reverb_send.resize(probe_count)
	predecessors.resize(probe_count)
	predecessor_modifiers.resize(probe_count)
	first_hops.resize(probe_count)
	origin_probes.resize(probe_count)
	_heap_nodes.resize(probe_count)
	_heap_costs.resize(probe_count)
	_heap_positions.resize(probe_count)


func _heap_sift_up(start_index: int) -> void:
	var heap_index := start_index
	while heap_index > 0:
		var parent_index := (heap_index - 1) >> 1
		if _heap_costs[parent_index] <= _heap_costs[heap_index]:
			break
		_heap_swap(heap_index, parent_index)
		heap_index = parent_index


func _heap_sift_down(start_index: int) -> void:
	var heap_index := start_index
	while true:
		var left_index := heap_index * 2 + 1
		if left_index >= _heap_size:
			return
		var right_index := left_index + 1
		var smallest_index := left_index
		if (
			right_index < _heap_size
			and _heap_costs[right_index] < _heap_costs[left_index]
		):
			smallest_index = right_index
		if _heap_costs[heap_index] <= _heap_costs[smallest_index]:
			return
		_heap_swap(heap_index, smallest_index)
		heap_index = smallest_index


func _heap_swap(left_index: int, right_index: int) -> void:
	var left_node := _heap_nodes[left_index]
	var right_node := _heap_nodes[right_index]
	var left_cost := _heap_costs[left_index]
	_heap_nodes[left_index] = right_node
	_heap_costs[left_index] = _heap_costs[right_index]
	_heap_nodes[right_index] = left_node
	_heap_costs[right_index] = left_cost
	_heap_positions[left_node] = right_index
	_heap_positions[right_node] = left_index

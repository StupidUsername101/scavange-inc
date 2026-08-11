extends VBoxContainer

const MAX_DETAIL_ROWS = 480
const MAX_INLINE_TREE_VALUES = 6

var split: HSplitContainer
var tree: Tree
var detail_panel: VBoxContainer
var detail_title: Label
var detail_status: Label
var action_contract_label: Label
var current_output_label: Label
var mean_output_label: Label
var range_output_label: Label
var saturation_label: Label
var trace_heading: Label
var trace_tree: Tree
var selected_source_id = ""
var selected_instance_id = -1
var tree_signature = ""
var records_by_key: Dictionary = {}
var items_by_key: Dictionary = {}
var fullscreen_mode = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 310.0)
	add_theme_constant_override("separation", 7)

	var summary = Label.new()
	summary.name = "EpisodeSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color("70e8b2"))
	add_child(summary)

	split = HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("minimum_grab_thickness", 10)
	add_child(split)

	tree = Tree.new()
	tree.columns = 2
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.custom_minimum_size = Vector2(0.0, 250.0)
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.column_titles_visible = true
	tree.set_column_title(0, "Worker")
	tree.set_column_title(1, "Latest model actions")
	tree.set_column_expand(0, true)
	tree.set_column_expand(1, true)
	tree.set_column_expand_ratio(0, 3)
	tree.set_column_expand_ratio(1, 2)
	tree.item_selected.connect(_on_item_selected)
	split.add_child(tree)

	detail_panel = VBoxContainer.new()
	detail_panel.visible = false
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_constant_override("separation", 6)
	split.add_child(detail_panel)

	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 18)
	detail_title.add_theme_color_override("font_color", Color("8de1ff"))
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(detail_title)

	detail_status = Label.new()
	detail_status.add_theme_color_override("font_color", Color("70e8b2"))
	detail_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(detail_status)

	action_contract_label = Label.new()
	action_contract_label.add_theme_color_override("font_color", Color("a8d7c2"))
	action_contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(action_contract_label)

	var metrics = GridContainer.new()
	metrics.columns = 2
	metrics.add_theme_constant_override("h_separation", 14)
	metrics.add_theme_constant_override("v_separation", 5)
	detail_panel.add_child(metrics)
	current_output_label = _add_metric(metrics, "Current")
	mean_output_label = _add_metric(metrics, "Episode mean")
	range_output_label = _add_metric(metrics, "Episode range")
	saturation_label = _add_metric(metrics, "Saturation")

	trace_heading = Label.new()
	trace_heading.text = "Condensed current-episode output · newest first"
	trace_heading.add_theme_color_override("font_color", Color("ffad42"))
	detail_panel.add_child(trace_heading)

	trace_tree = Tree.new()
	trace_tree.columns = 2
	trace_tree.hide_root = true
	trace_tree.column_titles_visible = true
	trace_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trace_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	trace_tree.custom_minimum_size = Vector2(0.0, 220.0)
	detail_panel.add_child(trace_tree)
	_configure_trace_columns([])

	resized.connect(_layout_split)


func _add_metric(parent: GridContainer, title: String) -> Label:
	var name_label = Label.new()
	name_label.text = title
	name_label.add_theme_color_override("font_color", Color("a8b8b1"))
	parent.add_child(name_label)
	var value_label = Label.new()
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_color_override("font_color", Color("b8e9d2"))
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(value_label)
	return value_label


func set_fullscreen_mode(enabled: bool) -> void:
	fullscreen_mode = enabled
	detail_panel.visible = enabled
	custom_minimum_size.y = 0.0 if enabled else 310.0
	call_deferred("_layout_split")
	_refresh_detail()


func _layout_split() -> void:
	if split == null or not fullscreen_mode:
		return
	split.split_offset = int(maxf(size.x * 0.36, 380.0))


func refresh(group_rows: Array[Dictionary]) -> void:
	records_by_key.clear()
	var signature_parts = PackedStringArray()
	var worker_count = 0
	var decision_count = 0
	var active_group_count = 0
	for group_row in group_rows:
		var source_id = str(group_row.get("source_id", ""))
		if bool(group_row.get("active", false)):
			active_group_count += 1
		var action_names: Array = group_row.get("action_names", [])
		signature_parts.append("g:%s:%s:%s:%s:%d:%s" % [
			source_id,
			str(group_row.get("name", "")),
			str(group_row.get("worker_kind", "")),
			str(bool(group_row.get("active", false))),
			int(group_row.get("episode_number", -1)),
			"|".join(PackedStringArray(action_names)),
		])
		for worker_row_value in group_row.get("workers", []):
			if not (worker_row_value is Dictionary):
				continue
			var worker_row: Dictionary = worker_row_value
			var instance_id = int(worker_row.get("instance_id", -1))
			var key = _key(source_id, instance_id)
			records_by_key[key] = worker_row
			signature_parts.append("w:%s:%d" % [key, int(worker_row.get("worker_index", -1))])
			worker_count += 1
			var record: Dictionary = worker_row.get("record", {})
			decision_count += int(record.get("total_decisions", 0))
	var new_signature = "|".join(signature_parts)
	if new_signature != tree_signature:
		tree_signature = new_signature
		_rebuild_tree(group_rows)
	else:
		_refresh_tree_rows(group_rows)

	var summary = get_node_or_null("EpisodeSummary") as Label
	if summary != null:
		summary.text = "%d model groups · %d active · %d workers · %d model decisions · variable-width action traces" % [
			group_rows.size(),
			active_group_count,
			worker_count,
			decision_count,
		]
	_ensure_valid_selection(group_rows)
	_refresh_detail()


func _rebuild_tree(group_rows: Array[Dictionary]) -> void:
	tree.clear()
	items_by_key.clear()
	var root = tree.create_item()
	for group_row in group_rows:
		var source_id = str(group_row.get("source_id", ""))
		var group_item = tree.create_item(root)
		group_item.set_text(0, "%s · %s" % [
			str(group_row.get("worker_kind_label", "Model")),
			str(group_row.get("name", "Worker group")),
		])
		group_item.set_text(1, "%s · episode %d · %d actions · %s" % [
			str(group_row.get("algorithm", "")),
			int(group_row.get("episode_number", -1)),
			(group_row.get("action_names", []) as Array).size(),
			"active" if bool(group_row.get("active", false)) else "paused",
		])
		var group_action_names: Array = group_row.get("action_names", [])
		var group_contract = "%d model controls\n%s" % [
			group_action_names.size(),
			_action_contract_text(group_action_names),
		]
		group_item.set_tooltip_text(0, group_contract)
		group_item.set_tooltip_text(1, group_contract)
		var group_color: Color = group_row.get("color", Color("8de1ff"))
		group_item.set_custom_color(0, group_color)
		group_item.set_custom_color(1, group_color)
		group_item.set_selectable(0, false)
		group_item.set_selectable(1, false)
		for worker_row_value in group_row.get("workers", []):
			if not (worker_row_value is Dictionary):
				continue
			var worker_row: Dictionary = worker_row_value
			var item = tree.create_item(group_item)
			var instance_id = int(worker_row.get("instance_id", -1))
			var key = _key(source_id, instance_id)
			item.set_metadata(0, {
				"source_id": source_id,
				"instance_id": instance_id,
			})
			items_by_key[key] = item
			_update_tree_item(item, worker_row)
	_restore_tree_selection()


func _refresh_tree_rows(group_rows: Array[Dictionary]) -> void:
	for group_row in group_rows:
		var source_id = str(group_row.get("source_id", ""))
		for worker_row_value in group_row.get("workers", []):
			if not (worker_row_value is Dictionary):
				continue
			var worker_row: Dictionary = worker_row_value
			var key = _key(source_id, int(worker_row.get("instance_id", -1)))
			var item = items_by_key.get(key) as TreeItem
			if item != null:
				_update_tree_item(item, worker_row)


func _update_tree_item(item: TreeItem, worker_row: Dictionary) -> void:
	var worker_index = int(worker_row.get("worker_index", -1))
	var instance_id = int(worker_row.get("instance_id", -1))
	var status_text = str(worker_row.get("status", "waiting"))
	var worker_kind_label = str(worker_row.get("worker_kind_label", "Worker"))
	var record: Dictionary = worker_row.get("record", {})
	var action_names: Array = worker_row.get("action_names", [])
	item.set_text(0, "%s %02d · ID %d · %s" % [
		worker_kind_label,
		worker_index + 1,
		instance_id,
		status_text,
	])
	item.set_text(1, _format_commands_compact(
		record.get("latest_commands", PackedFloat64Array()),
		action_names
	))
	var command_tooltip: String = _named_commands(
		DroneTrainingActionCodec.packed_numeric_sequence(record.get("latest_commands", PackedFloat64Array())),
		action_names
	)
	var runtime_actuator_status: String = str(worker_row.get("runtime_actuator_status", "")).strip_edges()
	if not runtime_actuator_status.is_empty():
		command_tooltip += "\n\n" + runtime_actuator_status
	item.set_tooltip_text(1, command_tooltip)
	var status_color = Color("70e8b2")
	if status_text == "finished":
		status_color = Color("a8b8b1")
	elif status_text == "paused" or status_text == "settling" or status_text == "manual":
		status_color = Color("ffad42")
	item.set_custom_color(0, status_color)


func _on_item_selected() -> void:
	var item = tree.get_selected()
	if item == null:
		return
	var metadata: Variant = item.get_metadata(0)
	if not (metadata is Dictionary):
		return
	var selection = metadata as Dictionary
	selected_source_id = str(selection.get("source_id", ""))
	selected_instance_id = int(selection.get("instance_id", -1))
	_refresh_detail()


func _ensure_valid_selection(group_rows: Array[Dictionary]) -> void:
	var selected_key = _key(selected_source_id, selected_instance_id)
	if records_by_key.has(selected_key):
		_restore_tree_selection()
		return
	selected_source_id = ""
	selected_instance_id = -1
	for group_row in group_rows:
		var workers: Array = group_row.get("workers", [])
		if workers.is_empty():
			continue
		var first_worker: Dictionary = workers[0]
		selected_source_id = str(group_row.get("source_id", ""))
		selected_instance_id = int(first_worker.get("instance_id", -1))
		break
	_restore_tree_selection()


func _restore_tree_selection() -> void:
	var item = items_by_key.get(_key(selected_source_id, selected_instance_id)) as TreeItem
	if item != null:
		item.select(0)


func _refresh_detail() -> void:
	if not fullscreen_mode:
		return
	var row: Dictionary = records_by_key.get(
		_key(selected_source_id, selected_instance_id),
		{}
	)
	trace_tree.clear()
	if row.is_empty():
		detail_title.text = "No worker selected"
		detail_status.text = "Select a model worker in the list to inspect its current episode."
		action_contract_label.text = "—"
		current_output_label.text = "—"
		mean_output_label.text = "—"
		range_output_label.text = "—"
		saturation_label.text = "—"
		_configure_trace_columns([])
		return
	var record: Dictionary = row.get("record", {})
	var action_names: Array = row.get("action_names", record.get("action_names", []))
	var action_count = action_names.size()
	var total_decisions = int(record.get("total_decisions", 0))
	var invalid_samples = int(record.get("invalid_samples", 0))
	var latest: PackedFloat64Array = DroneTrainingActionCodec.packed_numeric_sequence(record.get("latest_commands", PackedFloat64Array()))
	var sums: PackedFloat64Array = DroneTrainingActionCodec.packed_numeric_sequence(record.get("sum_commands", PackedFloat64Array()))
	var minimums: PackedFloat64Array = DroneTrainingActionCodec.packed_numeric_sequence(record.get("minimum_commands", PackedFloat64Array()))
	var maximums: PackedFloat64Array = DroneTrainingActionCodec.packed_numeric_sequence(record.get("maximum_commands", PackedFloat64Array()))
	var saturated_channels = int(record.get("saturated_channel_samples", 0))
	var all_high_decisions = int(record.get("all_high_decisions", 0))
	var all_low_decisions = int(record.get("all_low_decisions", 0))
	var means = PackedFloat64Array()
	means.resize(action_count)
	for index in range(action_count):
		means[index] = sums[index] / float(maxi(total_decisions, 1)) if sums.size() == action_count else 0.0

	detail_title.text = "%s · %s %02d · ID %d" % [
		str(row.get("group_name", "Worker group")),
		str(row.get("worker_kind_label", "Worker")),
		int(row.get("worker_index", -1)) + 1,
		int(row.get("instance_id", -1)),
	]
	detail_status.text = "Episode %d · %s · %.2f s · %d decisions · %d invalid" % [
		int(row.get("episode_number", record.get("episode_number", -1))),
		str(row.get("status", "waiting")),
		float(record.get("latest_time_seconds", row.get("elapsed_seconds", 0.0))),
		total_decisions,
		invalid_samples,
	]
	var runtime_actuator_status: String = str(row.get("runtime_actuator_status", "")).strip_edges()
	if not runtime_actuator_status.is_empty():
		detail_status.text += "\n" + runtime_actuator_status
	var action_minimum = float(row.get("action_minimum", record.get("action_minimum", -1.0)))
	var action_maximum = float(row.get("action_maximum", record.get("action_maximum", 1.0)))
	action_contract_label.text = "%d model controls · range %.2f … %.2f\n%s" % [
		action_count,
		action_minimum,
		action_maximum,
		_action_contract_text(action_names),
	]
	_configure_trace_columns(action_names)
	if total_decisions <= 0:
		current_output_label.text = "No model output sampled yet"
		mean_output_label.text = "—"
		range_output_label.text = "—"
		saturation_label.text = "—"
		return
	current_output_label.text = _named_commands(latest, action_names)
	mean_output_label.text = _named_commands(means, action_names)
	range_output_label.text = _named_ranges(minimums, maximums, action_names)
	saturation_label.text = "%d / %d channels (%.1f%%) · all max %d · all min %d" % [
		saturated_channels,
		maxi(total_decisions * action_count, 0),
		100.0 * float(saturated_channels) / float(maxi(total_decisions * action_count, 1)),
		all_high_decisions,
		all_low_decisions,
	]

	var root = trace_tree.create_item()
	var segments: Array = record.get("segments", [])
	var first_index = maxi(segments.size() - MAX_DETAIL_ROWS, 0)
	for reverse_offset in range(segments.size() - first_index):
		var index = segments.size() - 1 - reverse_offset
		_add_segment_row(root, segments[index], action_count)


func _configure_trace_columns(action_names: Array) -> void:
	var action_count = action_names.size()
	trace_tree.columns = maxi(2 + action_count, 2)
	trace_tree.set_column_title(0, "Time")
	trace_tree.set_column_title(1, "Samples")
	trace_tree.set_column_expand(0, true)
	trace_tree.set_column_expand_ratio(0, 2)
	trace_tree.set_column_custom_minimum_width(0, 108)
	trace_tree.set_column_expand(1, true)
	trace_tree.set_column_expand_ratio(1, 1)
	trace_tree.set_column_custom_minimum_width(1, 72)
	for action_index in range(action_count):
		var column = action_index + 2
		var full_name = str(action_names[action_index])
		trace_tree.set_column_title(column, _short_action_name(full_name))
		trace_tree.set_column_title_tooltip_text(column, full_name)
		trace_tree.set_column_expand(column, true)
		trace_tree.set_column_expand_ratio(column, 2)
		trace_tree.set_column_custom_minimum_width(column, 118)
	trace_heading.text = "Condensed current-episode output · newest first · %d action channels" % action_count


func _add_segment_row(root: TreeItem, segment: Dictionary, action_count: int) -> void:
	var count = maxi(int(segment.get("sample_count", 0)), 1)
	var sums: PackedFloat64Array = DroneTrainingActionCodec.packed_numeric_sequence(segment.get("sum_commands", PackedFloat64Array()))
	var start_time = float(segment.get("start_time_seconds", 0.0))
	var end_time = float(segment.get("end_time_seconds", start_time))
	var item = trace_tree.create_item(root)
	item.set_text(0, "%.2f–%.2f s" % [start_time, end_time])
	item.set_text(1, str(count))
	for action_index in range(action_count):
		item.set_text(action_index + 2, "%.3f" % (_value(sums, action_index) / float(count)))


func _action_contract_text(action_names: Array) -> String:
	if action_names.is_empty():
		return "No action contract available"
	var lines = PackedStringArray()
	for index in range(action_names.size()):
		lines.append("%02d  %s" % [index, str(action_names[index])])
	return "  ·  ".join(lines)


func _named_commands(commands: PackedFloat64Array, action_names: Array) -> String:
	if commands.size() != action_names.size() or action_names.is_empty():
		return "—"
	var parts = PackedStringArray()
	for index in range(action_names.size()):
		parts.append("%s %.3f" % [str(action_names[index]), commands[index]])
	return "  ·  ".join(parts)


func _named_ranges(minimums: PackedFloat64Array, maximums: PackedFloat64Array, action_names: Array) -> String:
	if minimums.size() != action_names.size() or maximums.size() != action_names.size():
		return "—"
	var parts = PackedStringArray()
	for index in range(action_names.size()):
		parts.append("%s [%.3f, %.3f]" % [
			str(action_names[index]),
			minimums[index],
			maximums[index],
		])
	return "  ·  ".join(parts)


func _format_commands_compact(value: Variant, action_names: Array) -> String:
	var commands = DroneTrainingActionCodec.packed_numeric_sequence(value)
	if commands.size() != action_names.size() or action_names.is_empty():
		return "%d actions · waiting" % action_names.size()
	var parts = PackedStringArray()
	var shown = mini(commands.size(), MAX_INLINE_TREE_VALUES)
	for index in range(shown):
		parts.append("%.2f" % commands[index])
	var suffix = " · … +%d" % (commands.size() - shown) if commands.size() > shown else ""
	return "%dch · %s%s" % [commands.size(), " · ".join(parts), suffix]


func _short_action_name(name: String) -> String:
	var result = name.replace("hip_elevation_target", "hip elev")
	result = result.replace("hip_horizontal_sweep_target", "hip sweep")
	result = result.replace("knee_bend_target", "knee")
	result = result.replace("grip_activation", "grip")
	result = result.replace(" hip horizontal sweep", " hip sweep")
	result = result.replace(" hip elevation", " hip elev")
	result = result.replace(" knee bend", " knee")
	result = result.replace("Propeller", "P")
	result = result.replace(" thrust", "")
	return result


func _value(values: PackedFloat64Array, index: int) -> float:
	return values[index] if index >= 0 and index < values.size() else 0.0


func _key(source_id: String, instance_id: int) -> String:
	return "%s:%d" % [source_id, instance_id]

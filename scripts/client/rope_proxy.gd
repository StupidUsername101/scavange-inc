class_name RopeProxy
extends Node3D

const INTERPOLATION_SPEED := 18.0

#######################################################
# Mirrors authoritative rope state on clients and updates its local visual presentation.
#######################################################

var rope_id := -1
var definition_path := ""
var definition: RopeDefinition
var target_points := PackedVector3Array()
var rendered_points := PackedVector3Array()
var preview := false
var placement_valid := true
var tension_ratio := 0.0
var current_flow_w := 0.0
var current_direction := 0
var effect_time := 0.0

var rope_mesh: MultiMeshInstance3D
var rope_multimesh: MultiMesh
var segment_mesh: CylinderMesh
var rope_material: StandardMaterial3D
var knot_a: MeshInstance3D
var knot_b: MeshInstance3D


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build_visual_nodes()


func apply_server_state(state: Dictionary) -> void:
	rope_id = SafeVariant.integral_int_or(state.get("rope_id", -1), -1)
	_apply_definition(str(state.get("definition_path", "")))
	preview = SafeVariant.strict_bool_or(state.get("preview", false), false)
	placement_valid = SafeVariant.strict_bool_or(state.get("valid", true), true)
	tension_ratio = SafeVariant.finite_float_or(state.get("tension_ratio", 0.0), 0.0)
	current_flow_w = SafeVariant.finite_float_or(state.get("current_flow_w", 0.0), 0.0)
	current_direction = SafeVariant.integral_int_or(state.get("current_direction", 0), 0)
	var received_points: PackedVector3Array = SafeVariant.packed_vector3_array_strict_or(
		state.get("points", PackedVector3Array()),
		PackedVector3Array()
	)
	target_points = received_points.duplicate()
	if rendered_points.size() != target_points.size():
		rendered_points = target_points.duplicate()


func _process(delta: float) -> void:
	effect_time += delta
	if multiplayer.is_server() and rope_id >= 0:
		var server_rope := Server.get_server_rope(rope_id)
		if is_instance_valid(server_rope):
			target_points = server_rope.points.duplicate()
			if rendered_points.size() != target_points.size():
				rendered_points = target_points.duplicate()
	var interpolation_weight := clampf(
		1.0 - exp(-INTERPOLATION_SPEED * delta),
		0.0,
		1.0
	)
	for point_index in range(rendered_points.size()):
		rendered_points[point_index] = rendered_points[point_index].lerp(
			target_points[point_index],
			interpolation_weight
		)
	_update_rope_geometry()


func _build_visual_nodes() -> void:
	rope_multimesh = MultiMesh.new()
	rope_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	rope_multimesh.use_colors = true
	segment_mesh = CylinderMesh.new()
	segment_mesh.height = 1.0
	segment_mesh.radial_segments = 8
	rope_multimesh.mesh = segment_mesh
	rope_mesh = MultiMeshInstance3D.new()
	rope_mesh.name = "RopeSegments"
	rope_mesh.multimesh = rope_multimesh
	add_child(rope_mesh)

	var knot_mesh := SphereMesh.new()
	knot_mesh.radius = 0.055
	knot_mesh.height = 0.11
	knot_mesh.radial_segments = 10
	knot_mesh.rings = 6
	knot_a = MeshInstance3D.new()
	knot_a.name = "KnotA"
	knot_a.mesh = knot_mesh
	add_child(knot_a)
	knot_b = MeshInstance3D.new()
	knot_b.name = "KnotB"
	knot_b.mesh = knot_mesh
	add_child(knot_b)


func _apply_definition(path: String) -> void:
	if path.is_empty() or path == definition_path:
		return
	var loaded := load(path) as RopeDefinition
	if loaded == null:
		push_error("Invalid rope definition: %s" % path)
		return
	definition_path = path
	definition = loaded
	segment_mesh.top_radius = definition.get_radius()
	segment_mesh.bottom_radius = definition.get_radius()
	segment_mesh.height = definition.visual_repeat_length
	_rope_material_from_definition()


func _rope_material_from_definition() -> void:
	if definition == null:
		return
	rope_material = StandardMaterial3D.new()
	rope_material.albedo_color = definition.rope_color
	rope_material.roughness = 0.72
	rope_material.vertex_color_use_as_albedo = true
	rope_material.emission_enabled = (
		definition.visual_effect != RopeDefinition.VisualEffect.NONE
	)
	rope_material.emission = definition.effect_color * 0.2
	segment_mesh.material = rope_material
	var knot_material := rope_material.duplicate(true) as StandardMaterial3D
	knot_a.material_override = knot_material
	knot_b.material_override = knot_material


func _update_rope_geometry() -> void:
	if definition == null or rendered_points.size() < 2:
		rope_multimesh.instance_count = 0
		knot_a.visible = false
		knot_b.visible = false
		return
	var visual_sections := _build_visual_sections()
	var segment_count := visual_sections.size()
	rope_multimesh.instance_count = segment_count
	var base_color: Color = (
		Color(1.0, 0.12, 0.08, 1.0)
		if preview and not placement_valid
		else definition.rope_color
	)
	for segment_index in range(segment_count):
		var section: Dictionary = visual_sections[segment_index]
		var start: Vector3 = section["start"]
		var end: Vector3 = section["end"]
		var offset := end - start
		var length := offset.length()
		if length <= 0.00001:
			rope_multimesh.set_instance_transform(
				segment_index,
				Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), start)
			)
			continue
		var direction := offset / length
		var side := direction.cross(Vector3.FORWARD)
		if side.length_squared() < 0.0001:
			side = direction.cross(Vector3.RIGHT)
		side = side.normalized()
		var forward := side.cross(direction).normalized()
		var segment_basis := Basis(side, direction, forward)
		segment_basis = segment_basis.scaled(Vector3(
			1.0,
			length / maxf(definition.visual_repeat_length, 0.001),
			1.0
		))
		rope_multimesh.set_instance_transform(
			segment_index,
			Transform3D(segment_basis, (start + end) * 0.5)
		)
		rope_multimesh.set_instance_color(
			segment_index,
			_get_segment_color(
				base_color,
				int(section["repeat_index"]),
				int(section["repeat_count"])
			)
		)
	knot_a.visible = true
	knot_b.visible = not preview
	knot_a.global_position = rendered_points[0]
	knot_b.global_position = rendered_points[rendered_points.size() - 1]
	_update_material_emission()


func _build_visual_sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if definition == null or rendered_points.size() < 2:
		return result
	var repeat_length := maxf(definition.visual_repeat_length, 0.04)
	var total_length := 0.0
	for path_index in range(rendered_points.size() - 1):
		total_length += rendered_points[path_index].distance_to(
			rendered_points[path_index + 1]
		)
	var repeat_count := maxi(ceili(total_length / repeat_length), 1)
	var traveled_length := 0.0
	for path_index in range(rendered_points.size() - 1):
		var edge_start := rendered_points[path_index]
		var edge_end := rendered_points[path_index + 1]
		var edge := edge_end - edge_start
		var edge_length := edge.length()
		if edge_length <= 0.00001:
			continue
		var direction := edge / edge_length
		var cursor := 0.0
		while cursor < edge_length - 0.00001:
			var phase := fposmod(traveled_length + cursor, repeat_length)
			var distance_to_boundary := repeat_length - phase
			if distance_to_boundary <= 0.00001:
				distance_to_boundary = repeat_length
			var next_cursor := minf(
				cursor + distance_to_boundary,
				edge_length
			)
			result.append({
				"start": edge_start + direction * cursor,
				"end": edge_start + direction * next_cursor,
				"repeat_index": floori(
					(traveled_length + cursor + 0.00001) / repeat_length
				),
				"repeat_count": repeat_count,
			})
			cursor = next_cursor
		traveled_length += edge_length
	return result


func _get_segment_color(
	base_color: Color,
	segment_index: int,
	segment_count: int
) -> Color:
	if definition == null or preview and not placement_valid:
		return base_color
	var section_color := (
		base_color.darkened(definition.visual_section_contrast)
		if segment_index % 2 == 1
		else base_color
	)
	if definition.visual_effect == RopeDefinition.VisualEffect.NONE:
		return section_color
	var progress := float(segment_index) / float(maxi(segment_count, 1))
	var pulse_direction := (
		float(current_direction)
		if (
			definition.visual_effect == RopeDefinition.VisualEffect.CURRENT_PULSE
			and current_direction != 0
		)
		else 1.0
	)
	var pulse := pow(
		maxf(sin(
			progress * TAU * 2.0
			- effect_time * definition.effect_speed * pulse_direction
		), 0.0),
		7.0
	)
	if (
		definition.visual_effect == RopeDefinition.VisualEffect.CURRENT_PULSE
		and current_flow_w <= 0.01
	):
		pulse = 0.0
	return section_color.lerp(definition.effect_color, pulse * 0.9)


func _update_material_emission() -> void:
	if rope_material == null or definition == null:
		return
	var active_effect := definition.visual_effect != RopeDefinition.VisualEffect.NONE
	if definition.visual_effect == RopeDefinition.VisualEffect.CURRENT_PULSE:
		active_effect = current_flow_w > 0.01
	rope_material.emission_enabled = active_effect
	var tension_glow := clampf(tension_ratio - 0.65, 0.0, 0.35) * 1.5
	rope_material.emission = (
		definition.effect_color * (0.18 if active_effect else 0.0)
		+ Color(1.0, 0.08, 0.02, 1.0) * tension_glow
	)

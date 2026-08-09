class_name DroneTrainingRoomPresentation
extends RefCounted

#######################################################
# Builds the training room's static arena, spectator presentation, reusable drone visuals,
# and compact control widgets without mixing presentation code into episode orchestration.
#######################################################

const SPINBOX_TARGET_ARROW_TICKS = 100.0
const SPINBOX_MAX_ARROW_STEP_MULTIPLIER = 10


static func spinbox_arrow_step(minimum: float, maximum: float, precision_step: float) -> float:
	var safe_step: float = maxf(absf(precision_step), 0.000001)
	var span: float = absf(maximum - minimum)
	if not is_finite(span) or span <= 0.0:
		return safe_step * float(SPINBOX_MAX_ARROW_STEP_MULTIPLIER)
	var target_step: float = span / SPINBOX_TARGET_ARROW_TICKS
	var minimum_multiplier: int = 5 if safe_step < 1.0 else 1
	var multiplier: int = clampi(
		int(round(target_step / safe_step)),
		minimum_multiplier,
		SPINBOX_MAX_ARROW_STEP_MULTIPLIER
	)
	return safe_step * float(multiplier)


static func configure_spinbox_arrow_speed(input: SpinBox) -> void:
	if input == null:
		return
	input.custom_arrow_step = spinbox_arrow_step(
		input.min_value,
		input.max_value,
		input.step
	)


static func build_environment(
	parent: Node3D,
	arena_size: Vector3,
	arena_collision_layer: int = 1,
	drone_collision_layer: int = 1 << 1
) -> Array[StaticBody3D]:
	var floor = add_static_box(
		parent,
		"Floor",
		Vector3(0.0, -0.3, 0.0),
		Vector3(arena_size.x, 0.6, arena_size.z),
		Color("202833"),
		arena_collision_layer,
		drone_collision_layer
	)
	# The training floor is intentionally matte. A broad glossy highlight made the flat ground
	# look wet at grazing camera angles and also amplified specular aliasing while orbiting.
	for floor_child: Node in floor.get_children():
		var floor_visual: MeshInstance3D = floor_child as MeshInstance3D
		if floor_visual != null:
			floor_visual.material_override = matte_material(Color("202833"))
	# Ground remains tagged so observations and deliberately authored ground-bracing end effectors
	# can recognize it. The stock four-limb generic grip does not include "ground" in its compatible
	# tags, so normal walking cannot silently turn a foot contact into a static spring anchor.
	floor.set_meta("training_ground", true)
	floor.set_meta("grip_surface_tags", PackedStringArray(["ground"]))
	var back_wall = add_static_box(
		parent,
		"BackWall",
		Vector3(0.0, arena_size.y * 0.5, -arena_size.z * 0.5),
		Vector3(arena_size.x, arena_size.y, 0.35),
		Color("151b24"),
		arena_collision_layer,
		drone_collision_layer
	)
	back_wall.set_meta("training_wall", true)
	back_wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
	var left_wall = add_static_box(
		parent,
		"LeftWall",
		Vector3(-arena_size.x * 0.5, arena_size.y * 0.5, 0.0),
		Vector3(0.35, arena_size.y, arena_size.z),
		Color("151b24"),
		arena_collision_layer,
		drone_collision_layer
	)
	left_wall.set_meta("training_wall", true)
	left_wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
	var right_wall = add_static_box(
		parent,
		"RightWall",
		Vector3(arena_size.x * 0.5, arena_size.y * 0.5, 0.0),
		Vector3(0.35, arena_size.y, arena_size.z),
		Color("151b24"),
		arena_collision_layer,
		drone_collision_layer
	)
	right_wall.set_meta("training_wall", true)
	right_wall.set_meta("grip_surface_tags", PackedStringArray(["climbable"]))
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.2
	# Training geometry is diagnostic and frequently rebuilt. Disable real-time
	# shadows for the entire training environment to keep obstacle-heavy rooms cheap.
	light.shadow_enabled = false
	parent.add_child(light)
	var world_environment = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("0b1017")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8ca0b8")
	environment.ambient_light_energy = 0.55
	# Filmic tonemapping is a cheap readability improvement for the bright emissive training
	# markers without the cost of screen-space AO, reflections, volumetric fog, or real shadows.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_white = 2.2
	world_environment.environment = environment
	parent.add_child(world_environment)
	var training_walls: Array[StaticBody3D] = [
		back_wall,
		left_wall,
		right_wall,
	]
	return training_walls


static func build_spectator_camera(parent: Node3D) -> Camera3D:
	var camera = Camera3D.new()
	camera.current = true
	camera.fov = 58.0
	parent.add_child(camera)
	return camera


static func build_target(
	parent: Node3D,
	target_start: Vector3,
	target_radius: float,
	marker_color: Color = Color("ff3d71")
) -> Dictionary:
	var marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	marker.mesh = sphere
	marker.material_override = material(marker_color, true)
	marker.position = target_start
	parent.add_child(marker)
	var radius_ring = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.0
	radius_ring.mesh = torus
	radius_ring.material_override = material(
		Color(marker_color.r, marker_color.g, marker_color.b, 0.60),
		true
	)
	radius_ring.position = target_start
	radius_ring.scale = Vector3(target_radius, 1.0, target_radius)
	parent.add_child(radius_ring)
	return {"marker": marker, "radius_ring": radius_ring}


static func build_position_marker(
	parent: Node3D,
	node_name: String,
	position_value: Vector3,
	color: Color,
	radius: float = 0.24
) -> MeshInstance3D:
	var marker = MeshInstance3D.new()
	marker.name = node_name
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	marker.mesh = sphere
	marker.material_override = material(color, true)
	marker.position = position_value
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(marker)
	return marker


static func add_drone_visual(drone: ServerDrone, color: Color) -> void:
	drone.set_meta("training_visual_color", color)
	var drone_material = material(color)
	var core = MeshInstance3D.new()
	core.name = "TrainingVisualCore"
	var core_mesh = BoxMesh.new()
	core_mesh.size = (
		drone.loadout.core.body_size
		if drone.loadout != null and drone.loadout.core != null
		else Vector3(0.65, 0.24, 0.65)
	)
	core.mesh = core_mesh
	core.material_override = drone_material
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drone.add_child(core)
	for angle in [45.0, -45.0]:
		var arm = MeshInstance3D.new()
		arm.name = "TrainingVisualArm"
		var arm_mesh = BoxMesh.new()
		arm_mesh.size = Vector3(1.35, 0.055, 0.075)
		arm.mesh = arm_mesh
		arm.rotation_degrees.y = angle
		arm.position.y = 0.08
		arm.material_override = drone_material
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drone.add_child(arm)
	for slot in drone.propeller_slots:
		var rotor = MeshInstance3D.new()
		rotor.name = "TrainingVisualRotor"
		var rotor_mesh = CylinderMesh.new()
		var propeller: DronePropellerDefinition = null
		if drone.loadout != null:
			propeller = drone.loadout.get_propeller(slot.slot_index)
		var rotor_radius = (
			propeller.rotor_radius if propeller != null else 0.18
		)
		rotor_mesh.top_radius = rotor_radius
		rotor_mesh.bottom_radius = rotor_radius
		rotor_mesh.height = 0.035
		rotor.mesh = rotor_mesh
		rotor.position = slot.position
		rotor.material_override = drone_material
		rotor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drone.add_child(rotor)


static func set_drone_episode_finished(
	drone: ServerDrone,
	reason: String
) -> void:
	if not is_instance_valid(drone):
		return
	var label = drone.get_node_or_null("TrainingEpisodeStatus") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "TrainingEpisodeStatus"
		label.position = Vector3(0.0, 0.75, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = 28
		label.outline_size = 8
		label.pixel_size = 0.006
		drone.add_child(label)
	label.text = reason.replace("_", " ").to_upper()
	label.modulate = Color("ffad42")
	label.visible = true


static func clear_drone_episode_finished(drone: ServerDrone) -> void:
	if not is_instance_valid(drone):
		return
	var label = drone.get_node_or_null("TrainingEpisodeStatus") as Label3D
	if label != null:
		label.visible = false


static func set_drone_highlight(drone: ServerDrone, highlighted: bool) -> void:
	if not is_instance_valid(drone):
		return
	var base_color: Color = drone.get_meta(
		"training_visual_color",
		Color("54e6b1")
	)
	var visible_color = base_color
	visible_color.a = 1.0 if highlighted else 0.14
	for child in drone.get_children():
		var mesh = child as MeshInstance3D
		if mesh == null or not mesh.name.begins_with("TrainingVisual"):
			continue
		mesh.material_override = material(visible_color, highlighted)


static func add_static_box(
	parent: Node3D,
	node_name: String,
	position_value: Vector3,
	size: Vector3,
	color: Color,
	collision_layer: int = 1,
	collision_mask: int = 1
) -> StaticBody3D:
	return add_static_obstacle(
		parent,
		node_name,
		position_value,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": size.x, "height": size.y, "depth": size.z},
		color,
		collision_layer,
		collision_mask
	)


static func add_static_obstacle(
	parent: Node3D,
	node_name: String,
	position_value: Vector3,
	shape_kind: int,
	dimensions: Dictionary,
	color: Color,
	collision_layer: int = 1,
	collision_mask: int = 1
) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.name = node_name
	body.position = position_value
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	var collision = CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = DroneTrainingObstacleShape.collision_shape(
		shape_kind,
		dimensions
	)
	body.add_child(collision)
	var visual = MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = DroneTrainingObstacleShape.visual_mesh(shape_kind, dimensions)
	visual.material_override = material(color)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(visual)
	body.set_meta("training_shape_kind", shape_kind)
	body.set_meta(
		"training_shape_dimensions",
		DroneTrainingObstacleShape.normalized_dimensions(shape_kind, dimensions)
	)
	parent.add_child(body)
	return body


static func resize_static_box(body: StaticBody3D, size: Vector3) -> void:
	configure_static_obstacle(
		body,
		DroneTrainingObstacleShape.Kind.BOX,
		{"width": size.x, "height": size.y, "depth": size.z}
	)


static func configure_static_obstacle(
	body: StaticBody3D,
	shape_kind: int,
	dimensions: Dictionary
) -> void:
	if not is_instance_valid(body):
		return
	var normalized = DroneTrainingObstacleShape.normalized_dimensions(
		shape_kind,
		dimensions
	)
	for child in body.get_children():
		var collision = child as CollisionShape3D
		if collision != null:
			collision.shape = DroneTrainingObstacleShape.collision_shape(
				shape_kind,
				normalized
			)
			continue
		var visual = child as MeshInstance3D
		if visual != null:
			visual.mesh = DroneTrainingObstacleShape.visual_mesh(
				shape_kind,
				normalized
			)
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.set_meta("training_shape_kind", shape_kind)
	body.set_meta("training_shape_dimensions", normalized)


static func recolor_static_box(
	body: StaticBody3D,
	color: Color,
	emission = false
) -> void:
	if not is_instance_valid(body):
		return
	for child in body.get_children():
		var visual = child as MeshInstance3D
		if visual != null:
			visual.material_override = material(color, emission)


static func material(color: Color, emission = false) -> StandardMaterial3D:
	var result = StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.18
	result.roughness = 0.55
	if color.a < 0.999:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission:
		result.emission_enabled = true
		result.emission = Color(color.r, color.g, color.b)
		result.emission_energy_multiplier = 2.0
	return result


static func matte_material(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = 0.0
	result.metallic_specular = 0.0
	result.roughness = 1.0
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return result


static func scanner_panel_style(selected = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = (
		Color(0.025, 0.105, 0.085, 0.98)
		if selected
		else Color(0.018, 0.075, 0.062, 0.98)
	)
	style.border_color = (
		Color(0.96, 0.67, 0.18, 1.0)
		if selected
		else Color(0.12, 0.58, 0.42, 1.0)
	)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func creator_panel_style(inner: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = (
		Color(0.075, 0.050, 0.016, 0.985)
		if inner
		else Color(0.115, 0.070, 0.018, 0.99)
	)
	style.border_color = Color(0.96, 0.62, 0.16, 1.0)
	style.set_border_width_all(2 if not inner else 1)
	style.set_corner_radius_all(5)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func creator_slot_panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.024, 0.078, 0.061, 0.96)
	style.border_color = Color(0.70, 0.43, 0.12, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func reward_card_panel_style(signal_type: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	match signal_type:
		FourLimbRewardCard.TYPE_PUNISHMENT:
			style.bg_color = Color(0.105, 0.025, 0.032, 0.98)
			style.border_color = Color(0.90, 0.24, 0.25, 1.0)
		FourLimbRewardCard.TYPE_MIXED:
			style.bg_color = Color(0.105, 0.068, 0.018, 0.98)
			style.border_color = Color(0.96, 0.62, 0.16, 1.0)
		_:
			style.bg_color = Color(0.018, 0.075, 0.062, 0.98)
			style.border_color = Color(0.12, 0.64, 0.42, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


static func reward_signal_color(signal_type: int) -> Color:
	match signal_type:
		FourLimbRewardCard.TYPE_PUNISHMENT:
			return Color("ff8f7a")
		FourLimbRewardCard.TYPE_MIXED:
			return Color("ffad42")
	return Color("54e6b1")


static func scanner_button_style(accent = false) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = (
		Color(0.16, 0.105, 0.025, 1.0)
		if accent
		else Color(0.012, 0.045, 0.039, 1.0)
	)
	style.border_color = (
		Color(0.96, 0.67, 0.18, 1.0)
		if accent
		else Color(0.06, 0.29, 0.23, 1.0)
	)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


static func scanner_danger_button_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.035, 0.035, 1.0)
	style.border_color = Color(0.92, 0.22, 0.22, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 9.0
	style.content_margin_right = 9.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


static func update_target_ring(radius_ring: MeshInstance3D, radius: float) -> void:
	if radius_ring != null:
		radius_ring.scale = Vector3(radius, 1.0, radius)


static func add_heading(parent: Control, text: String, size: int) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("8de1ff"))
	parent.add_child(label)


static func add_copy(parent: Control, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


static func add_separator(parent: Control) -> void:
	parent.add_child(HSeparator.new())


static func add_slider(
	parent: Control,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	callback: Callable
) -> HSlider:
	var label = Label.new()
	label.text = _slider_label(title, value, step)
	parent.add_child(label)
	var slider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.value_changed.connect(func(new_value: float) -> void:
		label.text = _slider_label(title, new_value, step)
		callback.call(new_value)
	)
	parent.add_child(slider)
	return slider


static func add_number_input(
	parent: Control,
	title: String,
	minimum: float,
	maximum: float,
	step: float,
	value: float,
	suffix: String,
	callback: Callable
) -> SpinBox:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label = Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input = SpinBox.new()
	input.custom_minimum_size.x = 118.0
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	configure_spinbox_arrow_speed(input)
	input.value = value
	input.suffix = suffix
	input.value_changed.connect(callback)
	row.add_child(input)
	return input


static func _slider_label(title: String, value: float, step: float) -> String:
	var absolute_step: float = absf(step)
	if absolute_step >= 1.0:
		return "%s: %d" % [title, int(round(value))]
	var decimal_places = clampi(
		ceili(-log(absolute_step) / log(10.0)),
		1,
		6
	)
	return "%s: %s" % [title, String.num(value, decimal_places)]


static func friendly_name(key: String) -> String:
	return key.replace("_", " ").capitalize()


static func episode_status_text(
	instance_count: int,
	episode_running: bool,
	episode_number: int,
	episode_elapsed: float,
	episode_duration: float,
	episode_seed: int,
	intermission_remaining: float
) -> String:
	if instance_count <= 0:
		return "No active model instances."
	if episode_running:
		return "Episode %d · %.1f / %.1f s · seed %d · %d instances" % [
			episode_number,
			episode_elapsed,
			episode_duration,
			episode_seed,
			instance_count,
		]
	if intermission_remaining > 0.0:
		return "Episode %d complete · next run in %.1f s" % [
			episode_number,
			intermission_remaining,
		]
	return "Episode %d complete · automatic restart paused" % episode_number

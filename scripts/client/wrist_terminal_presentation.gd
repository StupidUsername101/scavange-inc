class_name WristTerminalPresentation
extends Node3D

const TERMINAL_VIEW := preload(
	"res://scripts/client/wrist_terminal_view.gd"
)
const TERMINAL_SHADER := preload(
	"res://shaders/inspection_terminal_crt.gdshader"
)
const HELD_DEVICE_MOTION := preload(
	"res://scripts/characters/first_person_held_device_motion.gd"
)
const LISTENER_ACTIVITY := preload(
	"res://scripts/audio/listener_acoustic_activity.gd"
)
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const SCREEN_VIEWPORT_SIZE := Vector2i(720, 520)
# The imported screen uses a small rectangle in the asset's texture atlas.
# Normalize that authored rectangle before sampling our live viewport.
const SCREEN_ASSET_UV_RECT := Vector4(
	0.2324101627,
	0.8066376448,
	0.0820325017,
	0.0605478287
)
const SCREEN_CURVATURE_COMPENSATION := -0.008
const SCREEN_GLITCH_STRENGTH := 0.004
const SCREEN_GLITCH_TICK_RATE := 6.0
const SCREEN_GLITCH_EVENT_CHANCE := 0.025
const SCREEN_GLITCH_BAND_CHANCE := 0.12
const SCREEN_GLITCH_CHROMA_STRENGTH := 0.0012
const SCREEN_GLITCH_LUMA_FLUTTER := 0.055
const SCREEN_ACOUSTIC_GLITCH_EVENT_LIFT := 0.30
# The renderer already supplies post-propagation listener energy. This response merely maps its
# useful in-game range to glitch frequency: true silence remains idle, ordinary nearby sound is
# noticeable, and loud speakers saturate without making the glitch itself larger or uglier.
const SCREEN_ACOUSTIC_DRIVE_FLOOR := 0.015
const SCREEN_ACOUSTIC_DRIVE_FULL_SCALE := 0.45
const SCREEN_ACOUSTIC_DRIVE_EXPONENT := 0.65
const SCREEN_ACOUSTIC_ATTACK_SPEED := 16.0
const SCREEN_ACOUSTIC_RELEASE_SPEED := 4.5
const SCREEN_REFRESH_MIN_SPEED := 0.09
const SCREEN_REFRESH_MAX_SPEED := 0.18
const SCREEN_REFRESH_LINE_WIDTH := 0.006
const SCREEN_REFRESH_LINE_OPACITY := 0.11
const SCREEN_REFRESH_DISTORTION_MIN := 0.0025
const SCREEN_REFRESH_DISTORTION_MAX := 0.0065
const SCREEN_REFRESH_POINT_COUNT := 22.0
const SCREEN_REFRESH_POINT_MIN_STRENGTH := 0.38
const SCREEN_REFRESH_POINT_MAX_STRENGTH := 1.22
const SCREEN_PHOSPHOR_DECAY_PER_SECOND := 0.22
const SCREEN_PHOSPHOR_BRIGHTNESS_FLOOR := 0.64
const SCREEN_GRIT_STRENGTH := 0.038
const SCREEN_GRIT_TICK_RATE := 15.0
const SCREEN_GRIT_GRID := Vector2(360.0, 260.0)
const SCREEN_GRIT_SPECK_CHANCE := 0.024
const SCREEN_GRIT_AGE_INFLUENCE := 0.9
const SCREEN_TEXEL_SIZE := Vector2(
	1.0 / float(SCREEN_VIEWPORT_SIZE.x),
	1.0 / float(SCREEN_VIEWPORT_SIZE.y)
)
const SCREEN_NEON_GLOW_RADIUS_PIXELS := 1.65
const SCREEN_NEON_GLOW_STRENGTH := 0.14
const SCREEN_COLOR_BLEED_STRENGTH := 0.12
const SHADER_TIME_ROLLOVER_SECONDS := 3600.0
const OPEN_POSITION := Vector3(-0.055, -0.105, -0.44)
const CLOSED_POSITION := Vector3(0.46, -0.68, -0.61)
const OPEN_ROTATION := Vector3(-0.04, 0.015, 0.025)
const CLOSED_ROTATION := Vector3(0.24, -0.38, -0.52)
const PRESENTATION_SPEED := 7.5
const HOVER_SOUND_COOLDOWN_MSEC := 80
const INPUT_RAY_PARALLEL_EPSILON := 0.000001
const INPUT_SURFACE_EDGE_TOLERANCE := 0.002
const POINTER_EDGE_INSET := 14.0
const POINTER_MOTION_SCALE := 1.0

signal invite_friend_requested
signal return_to_menu_requested
signal device_sound_requested(sound_id: StringName)
signal device_control_requested(contact_id: StringName)
signal device_command_requested(
	contact_id: StringName,
	action: StringName,
	payload: Dictionary
)
signal display_page_changed(page: StringName)

#######################################################
# Presents the first-person wrist rig and forwards pointer input into its real 3D screen.
#######################################################

@onready var terminal_screen: MeshInstance3D = (
	$DeviceMount/CorporateFieldTerminalVisual/TechScreenHousing/
	screen_etx_1_partial/screen_etx_1_partial_round_screen
)
@onready var terminal_input_surface: MeshInstance3D = (
	$DeviceMount/TerminalInputSurface
)
@onready var forearm: MeshInstance3D = $Forearm
@onready var hand: MeshInstance3D = $Hand

var terminal_viewport: SubViewport
var terminal_view: WristTerminalView
var camera: Camera3D
var open_target := false
var presentation_weight := 0.0
var session_label := "OFFLINE"
var invite_available := false
var last_hover_sound_msec := -HOVER_SOUND_COOLDOWN_MSEC
var scanner_contacts: Array[Dictionary] = []
var scanner_range_meters := 36.0
var scanner_heading_yaw := 0.0
var held_device_motion := HELD_DEVICE_MOTION.new()
var acoustic_intensity_provider := Callable()
var acoustic_intensity_target := 0.0
var acoustic_intensity := 0.0
var acoustic_glitch_drive := 0.0
var terminal_screen_material: ShaderMaterial
var display_page: StringName = FIELDLINK_DISPLAY_STATE.PAGE_HOME
var pointer_position := Vector2(SCREEN_VIEWPORT_SIZE) * 0.5


func _ready() -> void:
	camera = get_parent() as Camera3D
	position = CLOSED_POSITION
	rotation = CLOSED_ROTATION
	visible = false
	set_process(false)


func set_open(value: bool) -> void:
	if value == open_target:
		return
	open_target = value
	if open_target:
		_ensure_interface()
		terminal_view.set_pointer_indicator(pointer_position, true)
		_restart_refresh_lines()
		visible = true
		set_process(true)
		terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		if terminal_view != null:
			terminal_view.set_pointer_indicator(pointer_position, false)
		if terminal_viewport != null:
			terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func is_open() -> bool:
	return open_target


func set_session_info(next_label: String, can_invite: bool) -> void:
	session_label = next_label
	invite_available = can_invite
	if terminal_view != null:
		terminal_view.set_session_info(session_label, invite_available)


func set_scanner_contacts(
	next_contacts: Array[Dictionary],
	next_range_meters: float
) -> void:
	scanner_contacts.clear()
	for contact: Dictionary in next_contacts:
		scanner_contacts.append(contact.duplicate(false))
	scanner_range_meters = maxf(next_range_meters, 1.0)
	if terminal_view != null:
		terminal_view.set_scanner_contacts(
			scanner_contacts,
			scanner_range_meters
		)


func set_scanner_heading(value: float) -> void:
	if not is_finite(value):
		return
	scanner_heading_yaw = wrapf(value, -PI, PI)
	if terminal_view != null:
		terminal_view.set_scanner_heading(scanner_heading_yaw)


func is_scanner_page_active() -> bool:
	return (
		terminal_view != null
		and terminal_view.is_scanner_page_active()
	)


func get_selected_contact_id() -> StringName:
	return (
		terminal_view.get_selected_contact_id()
		if terminal_view != null
		else &""
	)


func get_selected_control_type() -> StringName:
	return (
		terminal_view.get_selected_control_type()
		if terminal_view != null
		else &""
	)


func apply_replicated_page(page_value: Variant) -> void:
	var next_page := FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	if (
		next_page == display_page
		and terminal_view != null
		and terminal_view.current_page == next_page
	):
		return
	display_page = next_page
	if terminal_view != null:
		terminal_view.apply_replicated_page(display_page)


func apply_device_control_snapshot(snapshot: Dictionary) -> void:
	if terminal_view != null:
		terminal_view.apply_device_control_snapshot(snapshot)


func apply_device_control_error(contact_id: StringName, message: String) -> void:
	if terminal_view != null:
		terminal_view.apply_device_control_error(contact_id, message)


func set_wrist_side(use_left_arm: bool) -> void:
	var side := 1.0 if use_left_arm else -1.0
	forearm.position.x = -0.215 * side
	forearm.rotation.z = -0.78 * side
	hand.position.x = 0.205 * side
	hand.rotation.z = -1.03 * side


func set_motion_input(
	head_bob_offset: Vector3,
	movement_weight: float,
	endurance_spent_ratio: float = 0.0,
	gait_cycle: float = 0.0,
	run_weight: float = 0.0
) -> void:
	held_device_motion.set_gait_input(
		head_bob_offset,
		movement_weight,
		gait_cycle,
		run_weight
	)
	held_device_motion.set_endurance_spent_ratio(endurance_spent_ratio)


func set_acoustic_intensity_provider(provider: Callable) -> void:
	acoustic_intensity_provider = provider


func set_acoustic_intensity(value: float) -> void:
	acoustic_intensity_target = clampf(
		value if is_finite(value) else 0.0,
		0.0,
		1.0
	)


func set_feedback(message: String, is_error := false) -> void:
	if terminal_view != null:
		terminal_view.set_feedback(message, is_error)
	if open_target:
		device_sound_requested.emit(
			&"fieldlink_warning" if is_error else &"fieldlink_confirm"
		)


func _process(delta: float) -> void:
	if acoustic_intensity_provider.is_valid():
		set_acoustic_intensity(float(acoustic_intensity_provider.call()))
	acoustic_intensity = LISTENER_ACTIVITY.follow(
		acoustic_intensity,
		acoustic_intensity_target,
		delta,
		SCREEN_ACOUSTIC_ATTACK_SPEED,
		SCREEN_ACOUSTIC_RELEASE_SPEED
	)
	acoustic_glitch_drive = screen_acoustic_glitch_drive(acoustic_intensity)
	if terminal_screen_material != null:
		terminal_screen_material.set_shader_parameter(
			"acoustic_glitch_drive",
			acoustic_glitch_drive
		)
	held_device_motion.advance(delta)
	presentation_weight = move_toward(
		presentation_weight,
		1.0 if open_target else 0.0,
		PRESENTATION_SPEED * maxf(delta, 0.0)
	)
	var eased_weight := smoothstep(0.0, 1.0, presentation_weight)
	position = (
		CLOSED_POSITION.lerp(OPEN_POSITION, eased_weight)
		+ held_device_motion.position_offset * eased_weight
	)
	rotation = (
		CLOSED_ROTATION.lerp(OPEN_ROTATION, eased_weight)
		+ held_device_motion.rotation_offset * eased_weight
	)
	if not open_target and presentation_weight <= 0.0001:
		visible = false
		set_process(false)
		if terminal_viewport != null:
			terminal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func forward_pointer_input(event: InputEvent) -> bool:
	if (
		not open_target
		or terminal_viewport == null
		or camera == null
		or not is_instance_valid(terminal_screen)
		or not is_instance_valid(terminal_input_surface)
	):
		return false
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false

	var local_position := pointer_position
	var local_relative := Vector2.ZERO
	if event is InputEventMouseMotion:
		local_relative = event.relative * POINTER_MOTION_SCALE
		var next_position := _clamp_pointer_position(
			pointer_position + local_relative
		)
		local_relative = next_position - pointer_position
		pointer_position = next_position
		local_position = pointer_position
		terminal_view.set_pointer_indicator(pointer_position, true)

	var forwarded := event.duplicate()
	forwarded.position = local_position
	forwarded.global_position = local_position
	if forwarded is InputEventMouseMotion:
		var motion := forwarded as InputEventMouseMotion
		motion.relative = local_relative
	terminal_viewport.push_input(forwarded, true)
	return true


func _clamp_pointer_position(value: Vector2) -> Vector2:
	return Vector2(
		clampf(
			value.x,
			POINTER_EDGE_INSET,
			float(SCREEN_VIEWPORT_SIZE.x) - POINTER_EDGE_INSET
		),
		clampf(
			value.y,
			POINTER_EDGE_INSET,
			float(SCREEN_VIEWPORT_SIZE.y) - POINTER_EDGE_INSET
		)
	)


func _pointer_to_terminal_position(pointer_position: Vector2) -> Vector2:
	if (
		camera == null
		or not pointer_position.is_finite()
		or not is_instance_valid(terminal_input_surface)
	):
		return Vector2.INF
	var ray_origin := camera.project_ray_origin(pointer_position)
	var ray_direction := camera.project_ray_normal(pointer_position)
	var local_ray_origin := terminal_input_surface.to_local(ray_origin)
	var local_ray_direction := (
		terminal_input_surface.to_local(ray_origin + ray_direction)
		- local_ray_origin
	)
	if absf(local_ray_direction.z) <= INPUT_RAY_PARALLEL_EPSILON:
		return Vector2.INF
	var bounds := terminal_input_surface.get_aabb()
	var hit_distance := (
		bounds.get_center().z - local_ray_origin.z
	) / local_ray_direction.z
	if hit_distance < 0.0:
		return Vector2.INF
	var local_hit := local_ray_origin + local_ray_direction * hit_distance
	if (
		local_hit.x < bounds.position.x - INPUT_SURFACE_EDGE_TOLERANCE
		or local_hit.x > bounds.end.x + INPUT_SURFACE_EDGE_TOLERANCE
		or local_hit.y < bounds.position.y - INPUT_SURFACE_EDGE_TOLERANCE
		or local_hit.y > bounds.end.y + INPUT_SURFACE_EDGE_TOLERANCE
	):
		return Vector2.INF
	var normalized_x := inverse_lerp(
		bounds.position.x,
		bounds.end.x,
		clampf(local_hit.x, bounds.position.x, bounds.end.x)
	)
	# QuadMesh is authored in XY with +Y at the visual top, while Control space
	# grows downward. The inversion keeps the rendered texel and its hit target
	# on the same side of the curved display.
	var normalized_y := inverse_lerp(
		bounds.end.y,
		bounds.position.y,
		clampf(local_hit.y, bounds.position.y, bounds.end.y)
	)
	return Vector2(
		normalized_x * float(SCREEN_VIEWPORT_SIZE.x),
		normalized_y * float(SCREEN_VIEWPORT_SIZE.y)
	)


func _ensure_interface() -> void:
	if terminal_viewport != null:
		terminal_view.set_session_info(session_label, invite_available)
		terminal_view.set_scanner_contacts(
			scanner_contacts,
			scanner_range_meters
		)
		terminal_view.set_scanner_heading(scanner_heading_yaw)
		return
	terminal_viewport = SubViewport.new()
	terminal_viewport.name = "FieldlinkViewport"
	terminal_viewport.size = SCREEN_VIEWPORT_SIZE
	terminal_viewport.disable_3d = true
	terminal_viewport.gui_disable_input = false
	terminal_viewport.transparent_bg = false
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(terminal_viewport)

	terminal_view = TERMINAL_VIEW.new() as WristTerminalView
	terminal_viewport.add_child(terminal_view)
	terminal_view.set_session_info(session_label, invite_available)
	terminal_view.set_scanner_contacts(
		scanner_contacts,
		scanner_range_meters
	)
	terminal_view.set_scanner_heading(scanner_heading_yaw)
	terminal_view.apply_replicated_page(display_page)
	terminal_view.set_pointer_indicator(pointer_position, open_target)
	terminal_view.invite_friend_requested.connect(
		invite_friend_requested.emit
	)
	terminal_view.return_to_menu_requested.connect(
		return_to_menu_requested.emit
	)
	terminal_view.hover_sound_requested.connect(
		_on_hover_sound_requested
	)
	terminal_view.click_sound_requested.connect(
		_on_click_sound_requested
	)
	terminal_view.device_control_requested.connect(
		device_control_requested.emit
	)
	terminal_view.device_command_requested.connect(
		device_command_requested.emit
	)
	terminal_view.display_page_changed.connect(
		_on_display_page_changed
	)

	terminal_screen_material = create_screen_material(
		terminal_viewport.get_texture(),
		acoustic_intensity
	)
	terminal_screen.material_override = terminal_screen_material


static func create_screen_material(
	terminal_texture: Texture2D,
	initial_acoustic_intensity := 0.0
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERMINAL_SHADER
	material.set_shader_parameter("terminal_texture", terminal_texture)
	material.set_shader_parameter(
		"terminal_uv_rect",
		SCREEN_ASSET_UV_RECT
	)
	# Counter only a little of the mesh's physical bow so the UI stays readable
	# without making the glass appear flat.
	material.set_shader_parameter(
		"curvature",
		SCREEN_CURVATURE_COMPENSATION
	)
	material.set_shader_parameter(
		"glitch_strength",
		SCREEN_GLITCH_STRENGTH
	)
	material.set_shader_parameter(
		"glitch_tick_rate",
		SCREEN_GLITCH_TICK_RATE
	)
	material.set_shader_parameter(
		"glitch_event_chance",
		SCREEN_GLITCH_EVENT_CHANCE
	)
	material.set_shader_parameter(
		"glitch_band_chance",
		SCREEN_GLITCH_BAND_CHANCE
	)
	material.set_shader_parameter(
		"glitch_chroma_strength",
		SCREEN_GLITCH_CHROMA_STRENGTH
	)
	material.set_shader_parameter(
		"glitch_luma_flutter",
		SCREEN_GLITCH_LUMA_FLUTTER
	)
	material.set_shader_parameter(
		"acoustic_glitch_drive",
		screen_acoustic_glitch_drive(initial_acoustic_intensity)
	)
	material.set_shader_parameter(
		"acoustic_glitch_event_lift",
		SCREEN_ACOUSTIC_GLITCH_EVENT_LIFT
	)
	material.set_shader_parameter(
		"refresh_line_min_speed",
		SCREEN_REFRESH_MIN_SPEED
	)
	material.set_shader_parameter(
		"refresh_line_max_speed",
		SCREEN_REFRESH_MAX_SPEED
	)
	material.set_shader_parameter(
		"refresh_line_width",
		SCREEN_REFRESH_LINE_WIDTH
	)
	material.set_shader_parameter(
		"refresh_line_opacity",
		SCREEN_REFRESH_LINE_OPACITY
	)
	material.set_shader_parameter(
		"refresh_line_distortion_min",
		SCREEN_REFRESH_DISTORTION_MIN
	)
	material.set_shader_parameter(
		"refresh_line_distortion_max",
		SCREEN_REFRESH_DISTORTION_MAX
	)
	material.set_shader_parameter(
		"refresh_line_point_count",
		SCREEN_REFRESH_POINT_COUNT
	)
	material.set_shader_parameter(
		"refresh_line_point_min_strength",
		SCREEN_REFRESH_POINT_MIN_STRENGTH
	)
	material.set_shader_parameter(
		"refresh_line_point_max_strength",
		SCREEN_REFRESH_POINT_MAX_STRENGTH
	)
	material.set_shader_parameter(
		"phosphor_decay_per_second",
		SCREEN_PHOSPHOR_DECAY_PER_SECOND
	)
	material.set_shader_parameter(
		"phosphor_brightness_floor",
		SCREEN_PHOSPHOR_BRIGHTNESS_FLOOR
	)
	material.set_shader_parameter("grit_strength", SCREEN_GRIT_STRENGTH)
	material.set_shader_parameter("grit_tick_rate", SCREEN_GRIT_TICK_RATE)
	material.set_shader_parameter("grit_grid", SCREEN_GRIT_GRID)
	material.set_shader_parameter(
		"grit_speck_chance",
		SCREEN_GRIT_SPECK_CHANCE
	)
	material.set_shader_parameter(
		"grit_age_influence",
		SCREEN_GRIT_AGE_INFLUENCE
	)
	material.set_shader_parameter("terminal_texel_size", SCREEN_TEXEL_SIZE)
	material.set_shader_parameter(
		"neon_glow_radius_pixels",
		SCREEN_NEON_GLOW_RADIUS_PIXELS
	)
	material.set_shader_parameter(
		"neon_glow_strength",
		SCREEN_NEON_GLOW_STRENGTH
	)
	material.set_shader_parameter(
		"color_bleed_strength",
		SCREEN_COLOR_BLEED_STRENGTH
	)
	return material


static func screen_acoustic_glitch_drive(value: float) -> float:
	var safe_value := clampf(value if is_finite(value) else 0.0, 0.0, 1.0)
	return pow(
		smoothstep(
			SCREEN_ACOUSTIC_DRIVE_FLOOR,
			SCREEN_ACOUSTIC_DRIVE_FULL_SCALE,
			safe_value
		),
		SCREEN_ACOUSTIC_DRIVE_EXPONENT
	)


func _restart_refresh_lines() -> void:
	var material := terminal_screen.material_override as ShaderMaterial
	restart_screen_refresh(material)


static func restart_screen_refresh(material: ShaderMaterial) -> void:
	if material == null:
		return
	material.set_shader_parameter(
		"refresh_start_time",
		fmod(
			float(Time.get_ticks_msec()) * 0.001,
			SHADER_TIME_ROLLOVER_SECONDS
		)
	)


func _on_display_page_changed(page_value: StringName) -> void:
	display_page = FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	display_page_changed.emit(display_page)


func _on_hover_sound_requested() -> void:
	var now_msec := Time.get_ticks_msec()
	if now_msec - last_hover_sound_msec < HOVER_SOUND_COOLDOWN_MSEC:
		return
	last_hover_sound_msec = now_msec
	device_sound_requested.emit(&"fieldlink_hover")


func _on_click_sound_requested() -> void:
	device_sound_requested.emit(&"fieldlink_click")

class_name LevelAssetPreview
extends SubViewportContainer

const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")
const PREVIEW_FRAMING := preload("res://scripts/level_editor/level_asset_preview_framing.gd")

var viewport: SubViewport
var preview_root: Node3D
var asset_pivot: Node3D
var camera: Camera3D
var current_visual: Node3D
var current_bounds := AABB()
var preview_direction := Vector3(1.0, 0.5, 1.0).normalized()
var preview_zoom := 1.0
var orbit_dragging := false


func _ready() -> void:
	stretch = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag to orbit // Mouse wheel to zoom // Double-click to reset"
	viewport = SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = Vector2i(320, 220)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	preview_root = Node3D.new()
	viewport.add_child(preview_root)
	asset_pivot = Node3D.new()
	preview_root.add_child(asset_pivot)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_root.add_child(camera)
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.7, -0.65, 0.0)
	light.light_energy = 1.5
	preview_root.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.0, 2.0, 3.0)
	fill.omni_range = 12.0
	fill.light_energy = 0.8
	preview_root.add_child(fill)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("08100f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5e8cf")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	preview_root.add_child(environment_node)
	resized.connect(_apply_camera_frame)
	call_deferred("_apply_camera_frame")


func show_asset(asset_path: String) -> void:
	if current_visual != null:
		asset_pivot.remove_child(current_visual)
		current_visual.queue_free()
		current_visual = null
	current_visual = ASSET_SCENE_LOADER.instantiate(asset_path)
	if current_visual == null:
		return
	asset_pivot.add_child(current_visual)
	current_bounds = LevelAssetPlacement.calculate_visual_bounds(current_visual)
	current_visual.position -= current_bounds.get_center()
	asset_pivot.rotation = Vector3.ZERO
	preview_direction = PREVIEW_FRAMING.camera_direction(current_bounds)
	preview_zoom = 1.0
	_apply_camera_frame()
	camera.make_current()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			orbit_dragging = button.pressed
			if button.pressed and button.double_click:
				reset_view()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			preview_zoom = maxf(preview_zoom * 0.86, 0.45)
			_apply_camera_frame()
			accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preview_zoom = minf(preview_zoom / 0.86, 3.0)
			_apply_camera_frame()
			accept_event()
	elif event is InputEventMouseMotion and orbit_dragging:
		var motion := event as InputEventMouseMotion
		_apply_orbit_delta(motion.relative)
		accept_event()


func reset_view() -> void:
	if current_visual == null:
		return
	preview_direction = PREVIEW_FRAMING.camera_direction(current_bounds)
	preview_zoom = 1.0
	_apply_camera_frame()


func _apply_orbit_delta(mouse_delta: Vector2) -> void:
	if current_visual == null or mouse_delta.length_squared() <= 0.0:
		return
	preview_direction = (
		Basis(Vector3.UP, -mouse_delta.x * 0.012) * preview_direction
	).normalized()
	var right := Vector3.UP.cross(preview_direction).normalized()
	if right.length_squared() > 0.000001:
		var candidate := (
			Basis(right, -mouse_delta.y * 0.012) * preview_direction
		).normalized()
		if absf(candidate.dot(Vector3.UP)) < 0.985:
			preview_direction = candidate
	_apply_camera_frame()


func _apply_camera_frame() -> void:
	if camera == null or current_visual == null:
		return
	var aspect := (
		size.x / maxf(size.y, 1.0)
	)
	var framing: Dictionary = PREVIEW_FRAMING.frame(
		current_bounds,
		aspect,
		preview_direction,
		preview_zoom
	)
	camera.position = framing.get("position", Vector3(2.0, 0.5, 2.0))
	camera.size = float(framing.get("size", 1.0))
	camera.near = float(framing.get("near", 0.01))
	camera.far = float(framing.get("far", 100.0))
	camera.look_at(Vector3.ZERO, framing.get("up", Vector3.UP))
	camera.make_current()

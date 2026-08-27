class_name LevelAssetPreview
extends SubViewportContainer

const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")

var viewport: SubViewport
var preview_root: Node3D
var asset_pivot: Node3D
var camera: Camera3D
var current_visual: Node3D
var current_bounds := AABB()


func _ready() -> void:
	stretch = true
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
	var extent := maxf(
		maxf(current_bounds.size.x, current_bounds.size.y),
		current_bounds.size.z
	)
	extent = maxf(extent, 0.25)
	# A slightly elevated side view reads silhouettes reliably across the packs
	# and avoids depending on inconsistent authored forward axes.
	camera.position = Vector3(extent * 2.2, extent * 0.18, 0.0)
	camera.size = maxf(current_bounds.size.y, current_bounds.size.z) * 1.28
	camera.near = maxf(extent * 0.001, 0.01)
	camera.far = maxf(extent * 8.0, 100.0)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

class_name LevelAssetThumbnailRenderer
extends Node

signal thumbnail_ready(asset_path: String, texture: Texture2D)

const ASSET_SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")
const PREVIEW_FRAMING := preload("res://scripts/level_editor/level_asset_preview_framing.gd")
## Render above the default UI size so widening the catalog can enlarge previews
## without magnifying a tiny cached image. The cache remains bounded below.
const THUMBNAIL_SIZE := Vector2i(192, 144)
const MAXIMUM_CACHED_THUMBNAILS := 256
const MAXIMUM_QUEUED_THUMBNAILS := 64
const RENDER_SETTLE_FRAMES := 2

var placeholder: Texture2D

var _viewport: SubViewport
var _preview_root: Node3D
var _asset_pivot: Node3D
var _camera: Camera3D
var _current_visual: Node3D
var _active_path := ""
var _settle_frames := 0
var _queue: Array[String] = []
var _queued_paths: Dictionary[String, bool] = {}
var _cache: Dictionary[String, Texture2D] = {}
var _cache_order: Array[String] = []


func _ready() -> void:
	placeholder = _create_placeholder()
	_build_render_world()
	set_process(false)


func request(asset_path: String, prioritize := false) -> Texture2D:
	if _cache.has(asset_path):
		_touch_cache_entry(asset_path)
		return _cache[asset_path]
	if (
		asset_path.is_empty()
		or _queued_paths.has(asset_path)
		or asset_path == _active_path
		or not LevelAssetCatalog.is_valid_asset_path(asset_path)
	):
		return placeholder
	_queued_paths[asset_path] = true
	if prioritize:
		_queue.push_front(asset_path)
	else:
		_queue.append(asset_path)
	_trim_queue()
	set_process(true)
	return placeholder


func cached(asset_path: String) -> Texture2D:
	return _cache.get(asset_path, placeholder) as Texture2D


func _process(_delta: float) -> void:
	if not _active_path.is_empty():
		_settle_frames -= 1
		if _settle_frames <= 0:
			_capture_active_thumbnail()
		return
	_start_next_thumbnail()


func _build_render_world() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "AssetThumbnailViewport"
	_viewport.size = THUMBNAIL_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.transparent_bg = false
	add_child(_viewport)

	_preview_root = Node3D.new()
	_viewport.add_child(_preview_root)
	_asset_pivot = Node3D.new()
	_preview_root.add_child(_asset_pivot)

	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_preview_root.add_child(_camera)
	_camera.make_current()

	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(-0.7, -0.65, 0.0)
	key_light.light_energy = 1.5
	_preview_root.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-2.0, 2.0, 3.0)
	fill_light.omni_range = 12.0
	fill_light.light_energy = 0.8
	_preview_root.add_child(fill_light)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("08100f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b5e8cf")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	_preview_root.add_child(environment_node)


func _start_next_thumbnail() -> void:
	while not _queue.is_empty():
		var asset_path: String = _queue.pop_front()
		_queued_paths.erase(asset_path)
		if _cache.has(asset_path):
			continue
		_current_visual = ASSET_SCENE_LOADER.instantiate(asset_path)
		if _current_visual == null:
			continue
		_active_path = asset_path
		_asset_pivot.add_child(_current_visual)
		_frame_visual(_current_visual)
		_settle_frames = RENDER_SETTLE_FRAMES
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return
	set_process(false)


func _frame_visual(visual: Node3D) -> void:
	var bounds := LevelAssetPlacement.calculate_visual_bounds(visual)
	visual.position -= bounds.get_center()
	_asset_pivot.rotation = Vector3.ZERO
	var framing: Dictionary = PREVIEW_FRAMING.frame(
		bounds,
		float(THUMBNAIL_SIZE.x) / float(THUMBNAIL_SIZE.y)
	)
	_camera.position = framing.get("position", Vector3(2.0, 0.5, 2.0))
	_camera.size = float(framing.get("size", 1.0))
	_camera.near = float(framing.get("near", 0.01))
	_camera.far = float(framing.get("far", 100.0))
	_camera.look_at(Vector3.ZERO, framing.get("up", Vector3.UP))
	_camera.make_current()


func _capture_active_thumbnail() -> void:
	var texture: Texture2D = placeholder
	if DisplayServer.get_name() != "headless":
		var image := _viewport.get_texture().get_image()
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_cache[_active_path] = texture
	_cache_order.append(_active_path)
	_trim_cache()
	thumbnail_ready.emit(_active_path, texture)
	_clear_active_visual()


func _clear_active_visual() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _current_visual != null:
		_asset_pivot.remove_child(_current_visual)
		_current_visual.queue_free()
	_current_visual = null
	_active_path = ""
	_settle_frames = 0


func _touch_cache_entry(asset_path: String) -> void:
	_cache_order.erase(asset_path)
	_cache_order.append(asset_path)


func _trim_cache() -> void:
	while _cache_order.size() > MAXIMUM_CACHED_THUMBNAILS:
		var stale_path: String = _cache_order.pop_front()
		_cache.erase(stale_path)


func _trim_queue() -> void:
	while _queue.size() > MAXIMUM_QUEUED_THUMBNAILS:
		var stale_path: String = _queue.pop_back()
		_queued_paths.erase(stale_path)


static func _create_placeholder() -> Texture2D:
	var image := Image.create(
		THUMBNAIL_SIZE.x,
		THUMBNAIL_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color("0a1514"))
	for x: int in range(THUMBNAIL_SIZE.x):
		image.set_pixel(x, 0, Color("255b48"))
		image.set_pixel(x, THUMBNAIL_SIZE.y - 1, Color("255b48"))
	for y: int in range(THUMBNAIL_SIZE.y):
		image.set_pixel(0, y, Color("255b48"))
		image.set_pixel(THUMBNAIL_SIZE.x - 1, y, Color("255b48"))
	return ImageTexture.create_from_image(image)

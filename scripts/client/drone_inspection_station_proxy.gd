extends Node3D

const TERMINAL_VIEW_SCRIPT := preload(
	"res://scripts/client/inspection_terminal_view.gd"
)
const FRACTAL_LAYOUT := preload(
	"res://scripts/drones/inspection/fractal_terminal_layout.gd"
)
const TERMINAL_SHADER := preload(
	"res://shaders/inspection_terminal_crt.gdshader"
)

const SCREEN_CENTER := Vector2(0.0, 1.73)
const SCREEN_WORLD_SIZE := Vector2(2.68, 1.02)
const SCREEN_PLANE_Z := -0.555
const MAX_AIM_DISTANCE := 4.0

#######################################################
# Mirrors authoritative drone inspection station state on clients and updates its local visual
# presentation.
#######################################################

@export var station_id := 1

@onready var terminal_screen: MeshInstance3D = $TerminalScreen
@onready var occupied_light: MeshInstance3D = $OccupiedLight

var occupied := false
var inserted_part_id := -1
var report_document: Dictionary = {}
var view_path: Array[int] = []
var terminal_viewport: SubViewport
var terminal_view: Control


func _ready() -> void:
	add_to_group("drone_inspection_station_proxies")
	_build_terminal_surface()
	_update_indicator(false)
	set_process(true)


func _process(_delta: float) -> void:
	_update_terminal_aim_indicator()


func apply_server_state(state: Dictionary) -> void:
	inserted_part_id = int(state.get("inserted_part_id", -1))
	var next_occupied := bool(state.get("occupied", false))
	if next_occupied != occupied:
		occupied = next_occupied
		_update_indicator(occupied)

	var next_document: Dictionary = state.get("report_document", {})
	var all_paths: Dictionary = state.get("view_paths", {})
	var next_path: Array[int] = _get_local_view_path(all_paths)
	if next_document != report_document or next_path != view_path:
		report_document = next_document.duplicate(true)
		view_path = next_path
		if terminal_view != null:
			terminal_view.call(
				"set_document",
				report_document,
				view_path
			)


func _build_terminal_surface() -> void:
	terminal_viewport = SubViewport.new()
	terminal_viewport.name = "InspectionTerminalViewport"
	terminal_viewport.size = Vector2i(
		roundi(FRACTAL_LAYOUT.SCREEN_SIZE.x),
		roundi(FRACTAL_LAYOUT.SCREEN_SIZE.y)
	)
	terminal_viewport.disable_3d = true
	terminal_viewport.gui_disable_input = true
	terminal_viewport.transparent_bg = false
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(terminal_viewport)

	terminal_view = TERMINAL_VIEW_SCRIPT.new() as Control
	terminal_viewport.add_child(terminal_view)

	var material := ShaderMaterial.new()
	material.shader = TERMINAL_SHADER
	material.set_shader_parameter(
		"terminal_texture",
		terminal_viewport.get_texture()
	)
	terminal_screen.material_override = material

	terminal_view.call("set_document", report_document, view_path)


func _update_terminal_aim_indicator() -> void:
	if terminal_view == null:
		return
	var local_player := Client.get_local_player_proxy()
	if (
		Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
		or local_player == null
		or not is_instance_valid(local_player.camera)
	):
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return

	var ray_origin: Vector3 = local_player.camera.global_position
	var ray_direction: Vector3 = -local_player.camera.global_basis.z.normalized()
	var local_origin: Vector3 = to_local(ray_origin)
	var local_direction: Vector3 = global_basis.inverse() * ray_direction
	if absf(local_direction.z) <= 0.0001:
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return

	var distance: float = (SCREEN_PLANE_Z - local_origin.z) / local_direction.z
	if distance < 0.0 or distance > MAX_AIM_DISTANCE:
		terminal_view.call("set_aim_indicator", Vector2.ZERO, false)
		return

	var hit: Vector3 = local_origin + local_direction * distance
	var left: float = SCREEN_CENTER.x - SCREEN_WORLD_SIZE.x * 0.5
	var top: float = SCREEN_CENTER.y + SCREEN_WORLD_SIZE.y * 0.5
	var normalized := Vector2(
		(hit.x - left) / SCREEN_WORLD_SIZE.x,
		(top - hit.y) / SCREEN_WORLD_SIZE.y
	)
	var visible := (
		normalized.x >= 0.0
		and normalized.x <= 1.0
		and normalized.y >= 0.0
		and normalized.y <= 1.0
	)
	terminal_view.call(
		"set_aim_indicator",
		Vector2(
			normalized.x * FRACTAL_LAYOUT.SCREEN_SIZE.x,
			normalized.y * FRACTAL_LAYOUT.SCREEN_SIZE.y
		),
		visible
	)


func _get_local_view_path(all_paths: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var raw_path: Array = []
	if all_paths.has(Client.local_player_id):
		raw_path = all_paths[Client.local_player_id]
	elif all_paths.has(str(Client.local_player_id)):
		raw_path = all_paths[str(Client.local_player_id)]
	for child_index_value: Variant in raw_path:
		result.append(int(child_index_value))
	return result


func _update_indicator(is_occupied: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	if is_occupied:
		material.albedo_color = Color(0.12, 0.9, 0.42, 1.0)
		material.emission = Color(0.04, 0.7, 0.22, 1.0)
	else:
		material.albedo_color = Color(0.9, 0.56, 0.08, 1.0)
		material.emission = Color(0.55, 0.24, 0.015, 1.0)
	occupied_light.material_override = material

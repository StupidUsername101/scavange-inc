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
	inserted_part_id = SafeVariant.integral_int_or(state.get("inserted_part_id", -1), -1)
	var next_occupied: bool = SafeVariant.strict_bool_or(state.get("occupied", false), false)
	if next_occupied != occupied:
		occupied = next_occupied
		_update_indicator(occupied)

	var next_document: Dictionary = SafeVariant.dictionary_copy(
		state.get("report_document", {})
	)
	var all_paths: Dictionary = SafeVariant.dictionary_copy(
		state.get("view_paths", {}),
		false
	)
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
	TerminalAimIndicator.update(
		self,
		terminal_view,
		SCREEN_PLANE_Z,
		SCREEN_CENTER,
		SCREEN_WORLD_SIZE,
		MAX_AIM_DISTANCE,
		FRACTAL_LAYOUT.SCREEN_SIZE
	)

func _get_local_view_path(all_paths: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var raw_path_value: Variant = []
	if all_paths.has(Client.local_player_id):
		raw_path_value = all_paths[Client.local_player_id]
	elif all_paths.has(str(Client.local_player_id)):
		raw_path_value = all_paths[str(Client.local_player_id)]
	if not (raw_path_value is Array):
		return result
	for child_index_value: Variant in (raw_path_value as Array):
		var child_index: int = SafeVariant.integral_int_or(child_index_value, -1)
		if child_index >= 0:
			result.append(child_index)
	return result


func _update_indicator(is_occupied: bool) -> void:
	occupied_light.material_override = VisualMaterialFactory.binary_status_light(is_occupied)

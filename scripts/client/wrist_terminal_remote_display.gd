class_name WristTerminalRemoteDisplay
extends Node

const TERMINAL_VIEW := preload(
	"res://scripts/client/wrist_terminal_view.gd"
)
const FIELDLINK_DISPLAY_STATE := preload(
	"res://scripts/network/fieldlink_display_state.gd"
)
const SCREEN_NODE_PATH := NodePath(
	"TechScreenHousing/screen_etx_1_partial/"
	+ "screen_etx_1_partial_round_screen"
)
const REMOTE_UI_REFRESH_SECONDS := 1.0 / 15.0

## Owns only the render target for another player's equipped Fieldlink. The
## physical device remains the ordinary equipment visual, so this creates no
## duplicate arms, shells, collision, or input surface.

var terminal_viewport: SubViewport
var terminal_view: WristTerminalView
var terminal_screen: MeshInstance3D
var bound_visual: Node3D
var terminal_screen_material: ShaderMaterial
var original_material_override: Material
var open := false
var pending_page: StringName = FIELDLINK_DISPLAY_STATE.PAGE_HOME
var session_label := "CREW LINK"
var scanner_contacts: Array[Dictionary] = []
var scanner_range_meters := 36.0
var scanner_heading_yaw := 0.0
var refresh_remaining := 0.0


func _ready() -> void:
	set_process(false)


func bind_equipped_visual(visual: Node3D) -> bool:
	if visual == bound_visual and is_instance_valid(terminal_screen):
		return true
	_unbind_screen()
	if visual == null:
		return false
	bound_visual = visual
	terminal_screen = visual.get_node_or_null(
		SCREEN_NODE_PATH
	) as MeshInstance3D
	if terminal_screen == null:
		terminal_screen = visual.find_child(
			"screen_etx_1_partial_round_screen",
			true,
			false
		) as MeshInstance3D
	if terminal_screen == null:
		return false
	original_material_override = terminal_screen.material_override
	if open:
		_ensure_interface()
		_apply_screen_material()
	return true


func set_open(value: bool) -> void:
	if value == open:
		if open:
			_ensure_interface()
			_apply_screen_material()
		return
	open = value
	if open:
		_ensure_interface()
		_apply_screen_material()
		refresh_remaining = 0.0
		terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(true)
		WristTerminalPresentation.restart_screen_refresh(
			terminal_screen_material
		)
		return
	if terminal_viewport != null:
		terminal_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	_restore_screen_material()


func _process(delta: float) -> void:
	refresh_remaining -= maxf(delta, 0.0)
	if refresh_remaining > 0.0 or terminal_viewport == null:
		return
	refresh_remaining = REMOTE_UI_REFRESH_SECONDS
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func set_page(page_value: Variant) -> void:
	var next_page := FIELDLINK_DISPLAY_STATE.sanitize_page(page_value)
	if next_page == pending_page:
		return
	pending_page = next_page
	if terminal_view != null:
		terminal_view.apply_replicated_page(pending_page)


func set_session_info(next_label: String) -> void:
	session_label = next_label.strip_edges()
	if terminal_view != null:
		terminal_view.set_session_info(session_label, false)


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


func _ensure_interface() -> void:
	if terminal_viewport != null:
		return
	terminal_viewport = SubViewport.new()
	terminal_viewport.name = "RemoteFieldlinkViewport"
	terminal_viewport.size = WristTerminalPresentation.SCREEN_VIEWPORT_SIZE
	terminal_viewport.disable_3d = true
	terminal_viewport.gui_disable_input = true
	terminal_viewport.transparent_bg = false
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(terminal_viewport)

	terminal_view = TERMINAL_VIEW.new() as WristTerminalView
	terminal_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terminal_viewport.add_child(terminal_view)
	terminal_view.set_session_info(session_label, false)
	terminal_view.set_scanner_contacts(
		scanner_contacts,
		scanner_range_meters
	)
	terminal_view.set_scanner_heading(scanner_heading_yaw)
	terminal_view.apply_replicated_page(pending_page)
	terminal_screen_material = WristTerminalPresentation.create_screen_material(
		terminal_viewport.get_texture()
	)


func _apply_screen_material() -> void:
	if is_instance_valid(terminal_screen) and terminal_screen_material != null:
		terminal_screen.material_override = terminal_screen_material


func _restore_screen_material() -> void:
	if is_instance_valid(terminal_screen):
		terminal_screen.material_override = original_material_override


func _unbind_screen() -> void:
	_restore_screen_material()
	bound_visual = null
	terminal_screen = null
	original_material_override = null


func _exit_tree() -> void:
	_restore_screen_material()

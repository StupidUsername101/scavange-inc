extends Node3D

const VIEW_SCRIPT := preload(
	"res://scripts/client/weapon_crafting_station_view.gd"
)
const LAYOUT := preload(
	"res://scripts/weapons/weapon_crafting_station_layout.gd"
)
const SCREEN_CENTER := Vector2(-0.5, 1.72)
const SCREEN_WORLD_SIZE := Vector2(3.05, 1.73)
const SCREEN_PLANE_Z := -1.045
const MAX_AIM_DISTANCE := 5.0

@export var station_id := 3

var catalog_document: Dictionary = {}
var selection_indices: Array[int] = []
var summary: Dictionary = {}
var station_message := ""
var station_message_is_error := false
var catalog_signature := ""
var terminal_screen: MeshInstance3D
var terminal_viewport: SubViewport
var terminal_view: Control
var preview_anchor: Node3D
var preview_visual: Node3D
var ready_light: MeshInstance3D


func _ready() -> void:
	add_to_group("weapon_crafting_station_proxies")
	_build_machine()
	_build_terminal_surface()
	set_process(true)


func _process(delta: float) -> void:
	TerminalAimIndicator.update(
		self,
		terminal_view,
		SCREEN_PLANE_Z,
		SCREEN_CENTER,
		SCREEN_WORLD_SIZE,
		MAX_AIM_DISTANCE,
		LAYOUT.SCREEN_SIZE
	)
	if preview_anchor != null:
		preview_anchor.rotate_y(maxf(delta, 0.0) * 0.38)


func apply_server_state(state: Dictionary) -> void:
	var document_value: Variant = state.get("catalog_document", {})
	var incoming_document: Dictionary = (
		document_value as Dictionary
		if document_value is Dictionary
		else {}
	)
	var next_catalog_signature := str(
		incoming_document.get("catalog_signature", "")
	)
	var document_changed := (
		next_catalog_signature != catalog_signature
		and not next_catalog_signature.is_empty()
	)
	var next_document := (
		incoming_document.duplicate(true)
		if document_changed
		else catalog_document
	)
	var next_selection_value: Variant = _get_local_value(
		state.get("selection_indices_by_player_id", {}),
		[]
	)
	var next_selection := WeaponCraftingCatalog.sanitized_selection_indices(
		next_document,
		next_selection_value
	)
	var next_summary := SafeVariant.dictionary_copy(
		_get_local_value(state.get("summaries_by_player_id", {}), {})
	)
	var status := SafeVariant.dictionary_copy(
		_get_local_value(state.get("status_by_player_id", {}), {})
	)
	var next_message := str(status.get("message", ""))
	var next_message_is_error := SafeVariant.strict_bool_or(
		status.get("is_error", false),
		false
	)
	var selection_changed := next_selection != selection_indices
	var summary_changed := next_summary != summary
	var status_changed := (
		next_message != station_message
		or next_message_is_error != station_message_is_error
	)
	var preview_changed := document_changed or selection_changed
	var ui_changed := preview_changed or summary_changed or status_changed
	catalog_document = next_document
	if document_changed:
		catalog_signature = next_catalog_signature
	selection_indices = next_selection
	summary = next_summary
	station_message = next_message
	station_message_is_error = next_message_is_error
	if terminal_view != null and ui_changed:
		terminal_view.call(
			"set_station_state",
			catalog_document,
			selection_indices,
			summary,
			station_message,
			station_message_is_error
		)
	if preview_changed:
		_rebuild_weapon_preview()
	if document_changed or summary_changed:
		_update_ready_light()


func _build_terminal_surface() -> void:
	terminal_viewport = SubViewport.new()
	terminal_viewport.name = "WeaponFabricatorViewport"
	terminal_viewport.size = Vector2i(
		roundi(LAYOUT.SCREEN_SIZE.x),
		roundi(LAYOUT.SCREEN_SIZE.y)
	)
	terminal_viewport.disable_3d = true
	terminal_viewport.gui_disable_input = true
	terminal_viewport.transparent_bg = false
	terminal_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(terminal_viewport)
	terminal_view = VIEW_SCRIPT.new() as Control
	terminal_viewport.add_child(terminal_view)
	var screen_material := StandardMaterial3D.new()
	screen_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	screen_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen_material.albedo_texture = terminal_viewport.get_texture()
	terminal_screen.material_override = screen_material
	terminal_view.call(
		"set_station_state",
		catalog_document,
		selection_indices,
		summary,
		station_message,
		station_message_is_error
	)


func _rebuild_weapon_preview() -> void:
	if preview_visual != null:
		preview_anchor.remove_child(preview_visual)
		preview_visual.queue_free()
		preview_visual = null
	if catalog_document.is_empty():
		return
	var build := WeaponCraftingCatalog.build_from_selection(
		catalog_document,
		selection_indices
	)
	preview_visual = GunGeometry.create_gun_visual(build)
	preview_visual.name = "SelectedWeaponPreview"
	preview_visual.rotation.y = PI * 0.5
	preview_visual.scale = Vector3.ONE * 0.72
	preview_anchor.add_child(preview_visual)


func _build_machine() -> void:
	var cabinet := VisualMaterialFactory.standard(
		Color(0.075, 0.055, 0.065, 1.0),
		0.72,
		0.3
	)
	var black := VisualMaterialFactory.standard(
		Color(0.018, 0.015, 0.019, 1.0),
		0.54,
		0.42
	)
	var gold := _emissive_material(
		Color(0.56, 0.3, 0.055, 1.0),
		Color(0.9, 0.34, 0.025, 1.0)
	)
	var cyan := _emissive_material(
		Color(0.035, 0.22, 0.24, 1.0),
		Color(0.04, 0.65, 0.72, 1.0)
	)
	var red := _emissive_material(
		Color(0.42, 0.025, 0.045, 1.0),
		Color(0.92, 0.035, 0.07, 1.0)
	)
	_add_box("Cabinet", Vector3(0.0, 1.43, -0.72), Vector3(4.25, 2.85, 0.62), cabinet)
	_add_box("CabinetInset", Vector3(-0.5, 1.72, -1.02), Vector3(3.2, 1.88, 0.08), black)
	_add_box("Base", Vector3(0.0, 0.09, -0.54), Vector3(4.55, 0.18, 1.42), black)
	_add_box("GoldTop", Vector3(0.0, 2.88, -0.98), Vector3(4.34, 0.075, 0.12), gold)
	_add_box("GoldBottom", Vector3(0.0, 0.31, -1.0), Vector3(4.28, 0.055, 0.1), gold)

	var screen_mesh := QuadMesh.new()
	screen_mesh.size = SCREEN_WORLD_SIZE
	terminal_screen = MeshInstance3D.new()
	terminal_screen.name = "TerminalScreen"
	terminal_screen.position = Vector3(SCREEN_CENTER.x, SCREEN_CENTER.y, SCREEN_PLANE_Z)
	terminal_screen.mesh = screen_mesh
	add_child(terminal_screen)

	_add_box("PreviewBay", Vector3(1.53, 1.72, -1.035), Vector3(0.94, 1.74, 0.1), black)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.12, 0.42, 0.44, 0.22)
	glass.metallic = 0.22
	glass.roughness = 0.12
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_box("PreviewGlass", Vector3(1.53, 1.72, -1.105), Vector3(0.9, 1.69, 0.025), glass)
	for rail_x: float in [1.06, 2.0]:
		_add_box("PreviewRail", Vector3(rail_x, 1.72, -1.13), Vector3(0.045, 1.78, 0.055), cyan)
	preview_anchor = Node3D.new()
	preview_anchor.name = "WeaponPreviewAnchor"
	preview_anchor.position = Vector3(1.53, 1.74, -1.18)
	add_child(preview_anchor)

	_add_box("PayoutTray", Vector3(1.43, 0.42, -1.15), Vector3(2.1, 0.09, 0.9), black)
	_add_box("PayoutLip", Vector3(1.43, 0.5, -1.57), Vector3(2.14, 0.18, 0.06), gold)
	_add_world_label(
		"WEAPON PAYOUT",
		Vector3(1.43, 0.61, -1.61),
		22,
		Color(1.0, 0.61, 0.12, 1.0)
	)

	_add_world_label(
		"SCAV INC.  //  THE HOUSE ALWAYS BUILDS",
		Vector3(0.0, 3.13, -1.0),
		42,
		Color(1.0, 0.61, 0.12, 1.0)
	)
	_add_world_label(
		"OPTICS SOLD SEPARATELY",
		Vector3(1.53, 2.69, -1.13),
		18,
		Color(0.28, 0.9, 0.94, 1.0)
	)

	for light_index: int in range(7):
		var light_material := gold if light_index % 2 == 0 else red
		_add_light(
			"MarqueeLight%d" % light_index,
			Vector3(-1.76 + float(light_index) * 0.57, 2.97, -1.08),
			light_material
		)
	ready_light = _add_light(
		"ReadyLight",
		Vector3(2.0, 2.69, -1.14),
		red
	)

	# A deliberately oversized decorative lever sells the gambling-machine
	# silhouette; selection remains precise through the six screen reels.
	_add_box("LeverStem", Vector3(2.28, 1.45, -0.91), Vector3(0.08, 0.82, 0.08), gold, Vector3(0.0, 0.0, -0.28))
	_add_light("LeverKnob", Vector3(2.39, 1.85, -0.91), red, 0.13)


func _update_ready_light() -> void:
	if ready_light == null:
		return
	ready_light.material_override = _emissive_material(
		Color(0.03, 0.46, 0.2, 1.0) if bool(summary.get("compatible", false)) else Color(0.42, 0.025, 0.045, 1.0),
		Color(0.05, 1.0, 0.35, 1.0) if bool(summary.get("compatible", false)) else Color(0.92, 0.035, 0.07, 1.0)
	)


func _get_local_value(values_value: Variant, default_value: Variant) -> Variant:
	var values := SafeVariant.dictionary_copy(values_value, false)
	var client := get_node_or_null("/root/Client")
	var local_player_id := int(client.get("local_player_id")) if client != null else -1
	if values.has(local_player_id):
		return values[local_player_id]
	var player_id_string := str(local_player_id)
	if values.has(player_id_string):
		return values[player_id_string]
	return default_value


func _add_box(
	node_name: String,
	position_value: Vector3,
	size: Vector3,
	material: Material,
	rotation_value := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position_value
	instance.rotation = rotation_value
	instance.mesh = mesh
	add_child(instance)
	return instance


func _add_light(
	node_name: String,
	position_value: Vector3,
	material: Material,
	radius := 0.055
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.position = position_value
	instance.mesh = mesh
	add_child(instance)
	return instance


func _add_world_label(
	text_value: String,
	position_value: Vector3,
	font_size: int,
	color: Color
) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = position_value
	label.font_size = font_size
	label.pixel_size = 0.002
	label.outline_size = 8
	label.modulate = color
	label.outline_modulate = Color(0.01, 0.005, 0.008, 1.0)
	add_child(label)
	return label


func _emissive_material(
	color: Color,
	emission: Color
) -> StandardMaterial3D:
	var material := VisualMaterialFactory.standard(color, 0.52, 0.3)
	material.emission_enabled = true
	material.emission = emission
	return material

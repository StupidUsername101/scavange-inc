extends SceneTree

const BUILDER := preload(
	"res://scripts/world/static_structure_collision_builder.gd"
)
const INDUSTRIAL_SCENE := preload(
	"res://scenes/server/industrial_acoustic_complex.tscn"
)
const GARAGE_SCENE := preload(
	"res://scenes/server/speaker_cluster_demo.tscn"
)
const INDUSTRIAL_LAYOUT := preload(
	"res://scripts/world/industrial_acoustic_complex_layout.gd"
)
const GARAGE_LAYOUT := preload(
	"res://scripts/world/speaker_cluster_demo_layout.gd"
)
const ASSET_SCENE_LOADER := preload(
	"res://scripts/level_editor/level_asset_scene_loader.gd"
)
const ASSET_PLACEMENT := preload(
	"res://scripts/level_editor/level_asset_placement.gd"
)
const MANIFEST_PATH := "res://tools/asset_collision_manifest.json"

var assertion_count := 0
var failure_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_exact_box_clustering()
	_test_bunker_tunnel_clustering()
	_test_import_manifest()
	await _test_active_structure_bodies()
	_finish()


func _test_exact_box_clustering() -> void:
	var wall_pieces: Array[Dictionary] = []
	for piece_index: int in range(5):
		wall_pieces.append({
			"name": &"WallPiece%d" % piece_index,
			"position": Vector3(-4.0 + piece_index * 2.0, 1.5, 0.0),
			"size": Vector3(2.0, 3.0, 0.25),
			"rotation": Vector3.ZERO,
			"material_id": &"concrete_wall",
		})
	var clusters := BUILDER.cluster_box_descriptors(wall_pieces)
	_expect(
		clusters.size() == 1
		and (clusters[0].get("size", Vector3.ZERO) as Vector3).is_equal_approx(
			Vector3(10.0, 3.0, 0.25)
		)
		and (clusters[0].get("position", Vector3.INF) as Vector3).is_equal_approx(
			Vector3(0.0, 1.5, 0.0)
		)
		and (clusters[0].get("source_names", PackedStringArray()) as PackedStringArray).size() == 5,
		"five aligned wall modules collapse into one exact primitive wall"
	)
	var doorway: Array[Dictionary] = [
		{"name": &"DoorLeft", "position": Vector3(-2.0, 1.5, 0.0), "size": Vector3(2.0, 3.0, 0.25), "rotation": Vector3.ZERO, "material_id": &"wall"},
		{"name": &"DoorRight", "position": Vector3(2.0, 1.5, 0.0), "size": Vector3(2.0, 3.0, 0.25), "rotation": Vector3.ZERO, "material_id": &"wall"},
		{"name": &"DoorLintel", "position": Vector3(0.0, 2.75, 0.0), "size": Vector3(2.0, 0.5, 0.25), "rotation": Vector3.ZERO, "material_id": &"wall"},
	]
	_expect(
		BUILDER.cluster_box_descriptors(doorway).size() == 3,
		"clustering cannot seal a doorway whose pieces do not form one exact box"
	)
	var material_boundary := wall_pieces.duplicate(true)
	material_boundary[2]["material_id"] = &"glass"
	_expect(
		BUILDER.cluster_box_descriptors(material_boundary).size() == 3,
		"touching pieces retain collision and acoustic material boundaries"
	)
	var rotation := Vector3(0.0, deg_to_rad(37.0), 0.0)
	var basis := Basis.from_euler(rotation)
	var rotated: Array[Dictionary] = [
		{"name": &"RotatedA", "position": basis * Vector3(-1.0, 1.0, 0.0), "size": Vector3(2.0, 2.0, 0.3), "rotation": rotation, "material_id": &"wall"},
		{"name": &"RotatedB", "position": basis * Vector3(1.0, 1.0, 0.0), "size": Vector3(2.0, 2.0, 0.3), "rotation": rotation, "material_id": &"wall"},
	]
	var rotated_clusters := BUILDER.cluster_box_descriptors(rotated)
	_expect(
		rotated_clusters.size() == 1
		and (rotated_clusters[0].get("size", Vector3.ZERO) as Vector3).is_equal_approx(
			Vector3(4.0, 2.0, 0.3)
		),
		"the exact merger works in a shared rotated wall basis"
	)
	var parent := Node3D.new()
	root.add_child(parent)
	var bodies := BUILDER.build_clustered_box_bodies(
		parent,
		wall_pieces,
		&"concrete"
	)
	var collision := (
		bodies[0].get_child(0) as CollisionShape3D
		if bodies.size() == 1
		else null
	)
	_expect(
		bodies.size() == 1
		and collision != null
		and collision.transform.is_equal_approx(Transform3D.IDENTITY)
		and collision.shape is BoxShape3D,
		"a merged wall becomes one body with one identity-transformed primitive shape"
	)
	parent.free()


func _test_bunker_tunnel_clustering() -> void:
	var every_definition_matches := true
	for run: Dictionary in INDUSTRIAL_LAYOUT.tunnel_runs():
		var definition := run.get("definition") as ModularStructureDefinition
		var visual := ASSET_SCENE_LOADER.instantiate(definition.visual_scene_path)
		var measured_bounds := (
			ASSET_PLACEMENT.calculate_visual_bounds(visual)
			if visual != null
			else AABB()
		)
		every_definition_matches = (
			every_definition_matches
			and visual != null
			and measured_bounds.position.is_equal_approx(definition.source_bounds.position)
			and measured_bounds.size.is_equal_approx(definition.source_bounds.size)
		)
		if visual != null:
			visual.free()
	_expect(
		every_definition_matches,
		"every scaled tunnel definition still matches the current source asset"
	)
	var pieces := INDUSTRIAL_LAYOUT.tunnel_structural_boxes()
	var report := BUILDER.debug_cluster_report(pieces)
	var source_count := (
		INDUSTRIAL_LAYOUT.TUNNEL_RUN_COUNT
		* INDUSTRIAL_LAYOUT.TUNNEL_MODULE_COUNT
		* 5
	)
	var cluster_count := INDUSTRIAL_LAYOUT.TUNNEL_RUN_COUNT * 5
	_expect(
		pieces.size() == source_count
		and int(report.get("cluster_count", 0)) == cluster_count
		and int(report.get("merged_piece_count", 0)) == pieces.size() - cluster_count,
		"three scaled bunker runs each collapse to five open tunnel primitives"
	)


func _test_import_manifest() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var assets: Array = (parsed as Dictionary).get("assets", []) if parsed is Dictionary else []
	var valid_count := 0
	var prop_count := 0
	for raw_spec: Variant in assets:
		if not raw_spec is Dictionary:
			continue
		var spec: Dictionary = raw_spec
		var source_path := str(spec.get("source", ""))
		var output_path := str(spec.get("output", ""))
		var shape := load(output_path) as Shape3D
		if (
			ResourceLoader.exists(source_path, "PackedScene")
			and shape != null
			and shape.get_meta(&"collision_bake_source", "") == source_path
			and int(shape.get_meta(&"collision_bake_manifest_version", 0)) == 1
		):
			valid_count += 1
		if str(spec.get("id", "")).begins_with("prop_"):
			prop_count += 1
	_expect(
		assets.size() == 11 and valid_count == assets.size() and prop_count == 8,
		"one manifest reproducibly maps every curated solid asset to a baked Godot shape"
	)
	var tunnel_definitions_are_valid := true
	for run: Dictionary in INDUSTRIAL_LAYOUT.tunnel_runs():
		var definition := run.get("definition") as ModularStructureDefinition
		tunnel_definitions_are_valid = (
			tunnel_definitions_are_valid
			and definition != null
			and definition.is_valid()
		)
	_expect(
		ResourceLoader.exists("res://tools/generate_asset_collisions.gd", "Script")
		and ResourceLoader.exists("res://tools/asset_collision_baker.gd", "Script")
		and ResourceLoader.exists(
			"res://tools/create_modular_structure_definition.gd",
			"Script"
		)
		and tunnel_definitions_are_valid
		and ResourceLoader.exists(
			INDUSTRIAL_LAYOUT.TUNNEL_DEFINITION.visual_scene_path,
			"PackedScene"
		),
		"solid props and repeated structures each have one reusable headless onboarding path"
	)


func _test_active_structure_bodies() -> void:
	var industrial := INDUSTRIAL_SCENE.instantiate() as Node3D
	var garage := GARAGE_SCENE.instantiate() as Node3D
	root.add_child(industrial)
	root.add_child(garage)
	await physics_frame
	_test_structure_instance(
		industrial,
		INDUSTRIAL_LAYOUT.structural_boxes().size()
		+ INDUSTRIAL_LAYOUT.prop_descriptors().size()
		+ INDUSTRIAL_LAYOUT.large_bunker_speaker_descriptors().size(),
		"industrial complex"
	)
	var tunnel_report: Dictionary = industrial.get_meta(
		&"tunnel_collision_report",
		{}
	)
	_expect(
		int(tunnel_report.get("input_piece_count", 0))
		== INDUSTRIAL_LAYOUT.TUNNEL_RUN_COUNT * INDUSTRIAL_LAYOUT.TUNNEL_MODULE_COUNT * 5
		and int(tunnel_report.get("cluster_count", 0))
		== INDUSTRIAL_LAYOUT.TUNNEL_RUN_COUNT * 5
		and int(tunnel_report.get("merged_piece_count", 0))
		== INDUSTRIAL_LAYOUT.TUNNEL_RUN_COUNT * (INDUSTRIAL_LAYOUT.TUNNEL_MODULE_COUNT * 5 - 5),
		"the active server exposes all three forty-to-five bunker bake results"
	)
	var garage_source_count := (
		GARAGE_LAYOUT.structural_boxes().size()
		+ GARAGE_LAYOUT.prop_descriptors().size()
		+ GARAGE_LAYOUT.speaker_descriptors().size()
	)
	_test_structure_instance(garage, garage_source_count, "garage PA")
	industrial.free()
	garage.free()


func _test_structure_instance(
	structure: Node3D,
	expected_source_count: int,
	label: String
) -> void:
	var source_names: Dictionary[StringName, bool] = {}
	var valid_bodies := 0
	var baked_prop_count := 0
	var baked_props_are_non_boundaries := true
	var baked_props_have_acoustic_materials := true
	var structural_boundary_count := 0
	for child: Node in structure.find_children("*", "StaticBody3D", true, false):
		if not child is StaticBody3D:
			continue
		var body := child as StaticBody3D
		var collisions := body.find_children("*", "CollisionShape3D", false, false)
		if collisions.size() != 1:
			continue
		var collision := collisions[0] as CollisionShape3D
		if collision.transform.is_equal_approx(Transform3D.IDENTITY):
			valid_bodies += 1
		if body.get_meta(&"collision_source", &"") == &"manifest_baked_asset":
			baked_prop_count += 1
			baked_props_are_non_boundaries = (
				baked_props_are_non_boundaries
				and not bool(body.get_meta(&"acoustic_boundary", true))
			)
			baked_props_have_acoustic_materials = (
				baked_props_have_acoustic_materials
				and body.get_meta(&"acoustic_material") is AcousticMaterial
			)
			if not collision.shape is ConvexPolygonShape3D:
				valid_bodies = -1000
		elif bool(body.get_meta(&"acoustic_boundary", false)):
			structural_boundary_count += 1
		for source_name: String in body.get_meta(
			&"collision_source_names",
			PackedStringArray()
		):
			source_names[StringName(source_name)] = true
	_expect(
		source_names.size() == expected_source_count
		and valid_bodies > 0
		and valid_bodies == structure.find_children("*", "StaticBody3D", true, false).size()
		and baked_prop_count > 0
		and baked_props_are_non_boundaries
		and baked_props_have_acoustic_materials
		and structural_boundary_count > 0,
		"%s keeps one-shape collision while separating room boundaries from prop hulls" % label
	)


func _expect(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		print("PASS: ", message)
		return
	failure_count += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if failure_count == 0:
		print("Structure collision pipeline tests passed: %d assertions" % assertion_count)
		quit(0)
	else:
		push_error(
			"Structure collision pipeline tests failed: %d/%d assertions"
			% [failure_count, assertion_count]
		)
		quit(1)

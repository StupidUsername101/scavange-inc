extends SceneTree

const DEFINITION := preload("res://scripts/world/modular_structure_definition.gd")
const SCENE_LOADER := preload("res://scripts/level_editor/level_asset_scene_loader.gd")
const PLACEMENT := preload("res://scripts/level_editor/level_asset_placement.gd")


func _init() -> void:
	var exit_code := _run(OS.get_cmdline_user_args())
	quit(exit_code)


func _run(arguments: PackedStringArray) -> int:
	if arguments.size() < 2:
		print(
			"Usage: godot --headless --path . --script "
			+ "res://tools/create_modular_structure_definition.gd -- "
			+ "<source.glb> <output.tres> [module_count] [collision_profile] "
			+ "[--scale=x,y,z] [--force]"
		)
		return 2
	var source_path := arguments[0]
	var output_path := arguments[1]
	var module_count := maxi(int(arguments[2]), 1) if arguments.size() >= 3 else 1
	var collision_profile := (
		String(arguments[3])
		if arguments.size() >= 4 and not arguments[3].begins_with("--")
		else DEFINITION.PROFILE_ARCHED_TUNNEL
	)
	var force := arguments.has("--force")
	var module_scale := _parse_scale_argument(arguments)
	if not module_scale.is_finite() or minf(
		module_scale.x,
		minf(module_scale.y, module_scale.z)
	) <= 0.0:
		push_error("--scale must contain three positive finite values")
		return 3
	if not DEFINITION.is_supported_collision_profile(collision_profile):
		push_error("Unsupported collision profile: %s" % collision_profile)
		return 4
	if FileAccess.file_exists(output_path) and not force:
		push_error("Refusing to overwrite %s without --force" % output_path)
		return 5
	var visual := SCENE_LOADER.instantiate(source_path)
	if visual == null:
		push_error("Could not load modular structure source: %s" % source_path)
		return 6
	var bounds := PLACEMENT.calculate_visual_bounds(visual)
	visual.free()
	if bounds.size.length_squared() <= 0.000001:
		push_error("Modular source has no usable visual bounds: %s" % source_path)
		return 7
	var definition := DEFINITION.new() as ModularStructureDefinition
	definition.structure_id = StringName(output_path.get_file().get_basename())
	definition.visual_scene_path = source_path
	definition.source_bounds = bounds
	definition.module_scale = module_scale
	definition.module_count = module_count
	definition.module_name_prefix = StringName(
		output_path.get_file().get_basename().to_pascal_case() + "Module"
	)
	definition.collision_profile = collision_profile
	definition.floor_thickness = 0.12
	definition.shell_thickness = clampf(
		minf(
			bounds.size.x * module_scale.x,
			bounds.size.y * module_scale.y
		) * 0.055,
		0.08,
		0.22
	)
	definition.lower_wall_height_ratio = 0.42
	var absolute_directory := ProjectSettings.globalize_path(output_path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		push_error("Could not create output directory: %s" % error_string(directory_error))
		return 8
	var save_error := ResourceSaver.save(definition, output_path)
	if save_error != OK:
		push_error("Could not save %s: %s" % [output_path, error_string(save_error)])
		return 9
	print(
		"Created %s from %s: bounds=%s, scale=%s, modules=%d, profile=%s"
		% [output_path, source_path, bounds, module_scale, module_count, collision_profile]
	)
	return 0


func _parse_scale_argument(arguments: PackedStringArray) -> Vector3:
	for argument: String in arguments:
		if not argument.begins_with("--scale="):
			continue
		var components := argument.trim_prefix("--scale=").split(",", false)
		if components.size() != 3:
			return Vector3.INF
		return Vector3(
			float(components[0]),
			float(components[1]),
			float(components[2])
		)
	return Vector3.ONE

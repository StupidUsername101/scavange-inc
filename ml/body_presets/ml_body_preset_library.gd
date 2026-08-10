class_name MLBodyPresetLibrary
extends RefCounted

#######################################################
# Built-in starting bodies for the model creator. These are presets, never implicit runtime
# defaults. Existing trainers ask for the same preset template while they are migrated to the
# generic creator, so preset anatomy has one explicit source of truth rather than hidden runtime construction.
#######################################################

const DRONE_QUAD: StringName = &"drone_quad"
const DRONE_QUAD_GRABBER: StringName = &"drone_quad_grabber"
const FOUR_LIMB_WALKER: StringName = &"four_limb_walker"
const STATIONARY_TURRET: StringName = &"stationary_turret"

const DRONE_QUAD_LOADOUT_PATH = "res://resources/ml_body_presets/drone_quad.tres"
const DRONE_QUAD_GRABBER_LOADOUT_PATH = "res://resources/ml_body_presets/drone_quad_grabber.tres"
const FOUR_LIMB_WALKER_DEFINITION_PATH = "res://resources/ml_body_presets/four_limb_walker.tres"
const STATIONARY_TURRET_LOADOUT_PATH = "res://resources/ml_body_presets/stationary_turret.tres"


static func built_in_presets() -> Array[MLBodyPreset]:
	var result: Array[MLBodyPreset] = []
	for preset_id: StringName in [
		DRONE_QUAD,
		FOUR_LIMB_WALKER,
		STATIONARY_TURRET,
	]:
		var preset: MLBodyPreset = preset_by_id(preset_id)
		if preset != null:
			result.append(preset)
	return result


static func ui_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: MLBodyPreset in built_in_presets():
		result.append(preset.ui_record())
	return result


static func preset_by_id(preset_id: StringName) -> MLBodyPreset:
	match preset_id:
		DRONE_QUAD:
			return _drone_preset(false)
		DRONE_QUAD_GRABBER:
			return _drone_preset(true)
		FOUR_LIMB_WALKER:
			return _four_limb_preset()
		STATIONARY_TURRET:
			return _turret_preset()
	return null


static func instantiate_draft(preset_id: StringName) -> MLBodyBuildDraft:
	var preset: MLBodyPreset = preset_by_id(preset_id)
	return preset.instantiate_draft() if preset != null else null


static func instantiate_manifest(preset_id: StringName) -> MLBodyInterfaceManifest:
	var preset: MLBodyPreset = preset_by_id(preset_id)
	return preset.instantiate_manifest() if preset != null else null


static func instantiate_runtime_template(preset_id: StringName) -> Resource:
	var preset: MLBodyPreset = preset_by_id(preset_id)
	return preset.runtime_template_copy() if preset != null else null


static func drone_quad_loadout(with_grabber: bool = false) -> DroneLoadout:
	var preset_id: StringName = DRONE_QUAD_GRABBER if with_grabber else DRONE_QUAD
	return instantiate_runtime_template(preset_id) as DroneLoadout


static func four_limb_walker_definition() -> FourLimbBodyDefinition:
	return instantiate_runtime_template(FOUR_LIMB_WALKER) as FourLimbBodyDefinition


static func stationary_turret_loadout() -> TurretLoadout:
	return instantiate_runtime_template(STATIONARY_TURRET) as TurretLoadout


static func _drone_preset(with_grabber: bool) -> MLBodyPreset:
	var source_path: String = (
		DRONE_QUAD_GRABBER_LOADOUT_PATH if with_grabber else DRONE_QUAD_LOADOUT_PATH
	)
	var source: DroneLoadout = load(source_path) as DroneLoadout
	if source == null or source.core == null:
		return null
	# Build the creator draft from the loaded .tres itself so every equipped part retains a stable
	# source-resource identity. Runtime workers receive an isolated deep loadout copy separately.
	var draft: MLBodyBuildDraft = DroneMLBodyInterfaceFactory.create_draft(source)
	var loadout: DroneLoadout = DroneTrainingLoadoutConfig.duplicate_loadout(source)
	if loadout == null or loadout.core == null:
		return null
	var preset = MLBodyPreset.new()
	var preset_id: StringName = DRONE_QUAD_GRABBER if with_grabber else DRONE_QUAD
	var name_value: String = "Quad Drone + Grabber Limb" if with_grabber else "Quad Drone"
	var description_value: String = (
		"Four independent propellers plus a regular articulated belly limb with shoulder, elbow, and controlled grip."
		if with_grabber
		else "Stock four-propeller drone body using the normal gameplay Core and slots."
	)
	if not preset.configure(preset_id, name_value, description_value, &"drone", draft, loadout):
		return null
	return preset


static func _four_limb_preset() -> MLBodyPreset:
	var source: FourLimbBodyDefinition = load(FOUR_LIMB_WALKER_DEFINITION_PATH) as FourLimbBodyDefinition
	if source == null:
		return null
	var draft: MLBodyBuildDraft = FourLimbMLBodyInterfaceFactory.create_definition_draft(source)
	var definition: FourLimbBodyDefinition = (
		MLBodyPartContract.deep_duplicate_resource(source) as FourLimbBodyDefinition
	)
	if definition == null:
		return null
	var preset = MLBodyPreset.new()
	if not preset.configure(
		FOUR_LIMB_WALKER,
		"Four-Limb Walker",
		"Current four-legged articulated training body expressed as ordinary generic limb slots.",
		&"articulated_body",
		draft,
		definition
	):
		return null
	return preset


static func _turret_preset() -> MLBodyPreset:
	var source: TurretLoadout = load(STATIONARY_TURRET_LOADOUT_PATH) as TurretLoadout
	if source == null or source.base == null or source.gun == null:
		return null
	var draft: MLBodyBuildDraft = TurretMLBodyInterfaceFactory.create_draft(source)
	var loadout: TurretLoadout = MLBodyPartContract.deep_duplicate_resource(source) as TurretLoadout
	if loadout == null or not loadout.ensure_contract():
		return null
	var preset = MLBodyPreset.new()
	if not preset.configure(
		STATIONARY_TURRET,
		"Stationary Turret",
		"Turret Core with yaw control and one gun slot contributing pitch and trigger controls.",
		&"turret",
		draft,
		loadout
	):
		return null
	return preset

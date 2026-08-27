class_name MLBodyPresetLibrary
extends RefCounted

#######################################################
# Built-in starting bodies for the model creator. These are presets, never implicit runtime
# defaults. Existing trainers ask for the same preset template while they are migrated to the
# generic creator, so preset anatomy has one explicit source of truth rather than hidden runtime construction.
#######################################################

const DRONE_QUAD: StringName = &"drone_quad"
const DRONE_HEX: StringName = &"drone_hex"
const DRONE_QUAD_GRABBER: StringName = &"drone_quad_grabber"
const TINY_HUMANOID: StringName = &"tiny_humanoid"
const FOUR_LIMB_WALKER: StringName = &"four_limb_walker"
const STATIONARY_TURRET: StringName = &"stationary_turret"

const DRONE_QUAD_LOADOUT_PATH = "res://resources/ml_body_presets/drone_quad.tres"
const DRONE_HEX_LOADOUT_PATH = "res://resources/ml_body_presets/drone_hex.tres"
const DRONE_HEX_CORE_PATH = "res://resources/drones/cores/hex_training_core.tres"
const DRONE_QUAD_GRABBER_LOADOUT_PATH = "res://resources/ml_body_presets/drone_quad_grabber.tres"
const TINY_HUMANOID_DEFINITION_PATH = "res://resources/ml_body_presets/tiny_humanoid.tres"
const FOUR_LIMB_WALKER_DEFINITION_PATH = "res://resources/ml_body_presets/four_limb_walker.tres"
const STATIONARY_TURRET_LOADOUT_PATH = "res://resources/ml_body_presets/stationary_turret.tres"


static func built_in_presets() -> Array[MLBodyPreset]:
	var result: Array[MLBodyPreset] = []
	for preset_id: StringName in [
		DRONE_QUAD,
		DRONE_HEX,
		TINY_HUMANOID,
		FOUR_LIMB_WALKER,
		STATIONARY_TURRET,
	]:
		var preset: MLBodyPreset = preset_by_id(preset_id)
		if preset != null:
			result.append(preset)
	return result


static func worker_start_presets() -> Array[MLBodyPreset]:
	# These are the four one-click starting bodies shown by Worker Groups +. The turret remains a
	# valid creator preset/runtime, but is intentionally not one of the requested worker defaults.
	var result: Array[MLBodyPreset] = []
	for preset_id: StringName in [
		DRONE_QUAD,
		DRONE_HEX,
		TINY_HUMANOID,
		FOUR_LIMB_WALKER,
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


static func worker_start_ui_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for preset: MLBodyPreset in worker_start_presets():
		var record: Dictionary = preset.ui_record()
		record["algorithm_hint"] = (
			"PPO or SAC-HER"
			if preset.preset_id == DRONE_QUAD
			else "PPO"
		)
		result.append(record)
	return result


static func preset_by_id(preset_id: StringName) -> MLBodyPreset:
	match preset_id:
		DRONE_QUAD:
			return _drone_preset(
				DRONE_QUAD,
				DRONE_QUAD_LOADOUT_PATH,
				"4-Propeller Drone",
				"Balanced stock flight worker. Its standard geometry supports PPO or SAC-HER."
			)
		DRONE_HEX:
			return _drone_preset(
				DRONE_HEX,
				DRONE_HEX_LOADOUT_PATH,
				"6-Propeller Drone",
				"Six-rotor flight worker with a wider stable frame and six independent PPO controls."
			)
		DRONE_QUAD_GRABBER:
			return _drone_preset(
				DRONE_QUAD_GRABBER,
				DRONE_QUAD_GRABBER_LOADOUT_PATH,
				"Quad Drone + Grabber Limb",
				"Four independent propellers plus a regular articulated belly limb with shoulder, elbow, and controlled grip."
			)
		TINY_HUMANOID:
			return _four_limb_preset(
				TINY_HUMANOID,
				TINY_HUMANOID_DEFINITION_PATH,
				"Tiny Humanoid",
				"Small upright worker with two articulated arms, controlled grabbing hands, two legs, and physical feet."
			)
		FOUR_LIMB_WALKER:
			return _four_limb_preset(
				FOUR_LIMB_WALKER,
				FOUR_LIMB_WALKER_DEFINITION_PATH,
				"Robo-Dog Quadruped",
				"Low four-legged worker using the established articulated quadruped physics and PPO controller."
			)
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


static func drone_hex_loadout() -> DroneLoadout:
	return instantiate_runtime_template(DRONE_HEX) as DroneLoadout


static func tiny_humanoid_definition() -> FourLimbBodyDefinition:
	return instantiate_runtime_template(TINY_HUMANOID) as FourLimbBodyDefinition


static func four_limb_walker_definition() -> FourLimbBodyDefinition:
	return instantiate_runtime_template(FOUR_LIMB_WALKER) as FourLimbBodyDefinition


static func stationary_turret_loadout() -> TurretLoadout:
	return instantiate_runtime_template(STATIONARY_TURRET) as TurretLoadout


static func _drone_preset(
	preset_id: StringName,
	source_path: String,
	name_value: String,
	description_value: String
) -> MLBodyPreset:
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
	if not preset.configure(preset_id, name_value, description_value, &"drone", draft, loadout):
		return null
	return preset


static func _four_limb_preset(
	preset_id: StringName,
	source_path: String,
	name_value: String,
	description_value: String
) -> MLBodyPreset:
	var source: FourLimbBodyDefinition = load(source_path) as FourLimbBodyDefinition
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
		preset_id,
		name_value,
		description_value,
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
